#!/usr/bin/env node
/**
 * Automated Reliability Verification Suite for WUMIND Scheduled Tasks Center:
 *  1. One-time (`once`) task executes AT MOST ONCE (even under concurrent cron overlap + repeated ticks),
 *     immediately marks `status='completed', enabled=0, nextRunEpoch=0`, charges ONCE, writes 1 run record.
 *  2. Reminder-only (`reminder_only`) mode explicitly writes `status='reminder_sent'` (NOT `ai_completed`),
 *     makes 0 LLM calls, charges ¥0.
 *  3. Beijing Time (`Asia/Shanghai`) daily & weekly next-run calculations + server ACK (`serverConfirmed: true`,
 *     `nextRunBeijingText`, `supportsLockScreenCloudExecution: true`).
 *  4. Insufficient balance records independent failed run (`failed_insufficient_balance`), 0 LLM call, ¥0 charge,
 *     and advances/terminates without spin-looping.
 *  5. Pause and Cancel endpoints prevent due execution cleanly; resuming a completed `once` task returns 409.
 *  6. Non-destructive in-place schema upgrade (`ensureSchemaUpgraded`) upgrades legacy `schedules` tables cleanly.
 */
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import worker, {
  executeDueCloudSchedules,
  computeNextScheduleEpoch,
  formatEpochInTimezone,
} from "../src/index.js";
import { ensureSchemaUpgraded } from "../src/schema-upgrade.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const schemaSql = fs.readFileSync(path.join(__dirname, "..", "schema.sql"), "utf8");
const originalFetch = globalThis.fetch;

function makeDB(sqlite) {
  return {
    prepare(sql) {
      let args = [];
      const stmtObj = {
        bind(...v) { args = v; return stmtObj; },
        async first() { return sqlite.prepare(sql).get(...args) ?? null; },
        async all() { return { results: sqlite.prepare(sql).all(...args) }; },
        async run() {
          const info = sqlite.prepare(sql).run(...args);
          return {
            success: true,
            meta: {
              changes: Number(info.changes || 0),
              last_row_id: Number(info.lastInsertRowid || 0),
            },
          };
        },
        _execSync() { return sqlite.prepare(sql).run(...args); },
      };
      return stmtObj;
    },
    async batch(stmts) {
      sqlite.exec("BEGIN IMMEDIATE");
      try {
        for (const s of stmts) s._execSync();
        sqlite.exec("COMMIT");
        return [];
      } catch (err) {
        sqlite.exec("ROLLBACK");
        throw err;
      }
    },
  };
}

try {
  // 0. Pure Beijing Timezone (`Asia/Shanghai`) schedule calculation check
  {
    // 2026-11-26 08:00:00 Beijing Time = 2026-11-26T00:00:00Z
    const baseUTC = Math.floor(Date.UTC(2026, 10, 26, 0, 0, 0) / 1000);
    const sameDay0830 = computeNextScheduleEpoch({
      recurrenceKind: "daily",
      hour: 8,
      minute: 30,
      timezone: "Asia/Shanghai",
      afterEpoch: baseUTC,
    });
    assert.equal(sameDay0830, Math.floor(Date.UTC(2026, 10, 26, 0, 30, 0) / 1000));
    assert.equal(formatEpochInTimezone(sameDay0830, "Asia/Shanghai"), "2026-11-26 08:30 (北京时间)");

    // After 08:30 Beijing -> rolls to NEXT Beijing morning 2026-11-27 08:30
    const nextDay0830 = computeNextScheduleEpoch({
      recurrenceKind: "daily",
      hour: 8,
      minute: 30,
      timezone: "Asia/Shanghai",
      afterEpoch: sameDay0830,
    });
    assert.equal(nextDay0830, Math.floor(Date.UTC(2026, 10, 27, 0, 30, 0) / 1000));
    assert.equal(formatEpochInTimezone(nextDay0830, "Asia/Shanghai"), "2026-11-27 08:30 (北京时间)");

    // Weekly Monday (weekday = 2) 09:00 Beijing after Thu 2026-11-26 -> Mon 2026-11-30 09:00 Beijing (01:00Z)
    const nextMon0900 = computeNextScheduleEpoch({
      recurrenceKind: "weekly",
      weekday: 2,
      hour: 9,
      minute: 0,
      timezone: "Asia/Shanghai",
      afterEpoch: baseUTC,
    });
    assert.equal(nextMon0900, Math.floor(Date.UTC(2026, 10, 30, 1, 0, 0) / 1000));
    assert.equal(formatEpochInTimezone(nextMon0900, "Asia/Shanghai"), "2026-11-30 09:00 (北京时间)");
  }

  // Setup Gateway + mock upstream
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec(schemaSql);
  const DB = makeDB(sqlite);
  const ADMIN_SECRET = "test-admin-secret-sched";
  const env = {
    DB,
    ADMIN_SECRET,
    DEEPSEEK_API_KEY: "sk-deepseek-test",
    AUTO_CREDIT_PAUSED: "true",
    ALLOW_APPLE_PRODUCTION_IAP: "false",
  };

  let upstreamCallCount = 0;
  globalThis.fetch = async (url, init) => {
    const u = String(url);
    if (u.includes("api.deepseek.com") && u.includes("/chat/completions")) {
      upstreamCallCount += 1;
      // Add slight async delay to exercise concurrent cron claim lock
      await new Promise((r) => setTimeout(r, 25));
      const payload = JSON.parse(init.body || "{}");
      return new Response(
        JSON.stringify({
          id: `chatcmpl_${upstreamCallCount}`,
          choices: [{ message: { role: "assistant", content: `定时执行结果 #${upstreamCallCount}: ${payload.messages?.[0]?.content || ""}` } }],
          usage: { prompt_tokens: 120, completion_tokens: 80 },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }
    throw new Error(`Unexpected external fetch in schedule test: ${u}`);
  };

  async function req(method, pathname, { token, admin, body } = {}) {
    const headers = { "Content-Type": "application/json" };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (admin) headers["X-WuMind-Admin-Secret"] = ADMIN_SECRET;
    const r = await worker.fetch(
      new Request(`https://gw.test${pathname}`, {
        method,
        headers,
        body: body !== undefined ? JSON.stringify(body) : undefined,
      }),
      env
    );
    const json = await r.json();
    return { status: r.status, json };
  }

  // Register funded user (¥20) and zero-balance user (¥0)
  const fundedReg = await req("POST", "/v1/account/register", { body: { displayName: "FundedSchedUser", deviceName: "iPhone" } });
  assert.equal(fundedReg.status, 200);
  const fundedToken = fundedReg.json.userToken;
  const fundedUserID = fundedReg.json.userID;

  const grant = await req("POST", "/v1/admin/topup", {
    admin: true,
    body: { userID: fundedUserID, amountYuan: 20, environment: "production", operatorID: "qa-admin", note: "schedule test credit", idempotencyKey: "cred-sched-1" },
  });
  assert.equal(grant.status, 200);

  const brokeReg = await req("POST", "/v1/account/register", { body: { displayName: "ZeroBalanceUser", deviceName: "iPad" } });
  assert.equal(brokeReg.status, 200);
  const brokeToken = brokeReg.json.userToken;

  // Enable deepseek-chat in model catalog for execution
  sqlite.prepare(
    `INSERT OR REPLACE INTO model_catalog (
       model_id, upstream_provider, vendor, display_name, capabilities_json,
       pricing_mode, input_price_per_million, output_price_per_million,
       enabled, probe_status, pricing_status, deprecated
     ) VALUES ('deepseek-chat', 'deepSeek', 'deepSeek', 'DeepSeek Chat', '["chat"]',
               'token', 2.0, 8.0, 1, 'verified', 'priced', 0)`
  ).run();

  const fixedNow = Math.floor(Date.UTC(2026, 10, 26, 2, 0, 0) / 1000); // 10:00 Beijing

  // TEST 1: One-time (`once`) AI task -> server ACK + concurrent cron + repeated ticks = AT MOST ONCE execution & billing!
  {
    const createRes = await req("POST", "/v1/schedules", {
      token: fundedToken,
      body: {
        id: "sched-once-1",
        title: "一次性晨报汇总",
        prompt: "总结今天核心待办",
        modelID: "deepseek-chat",
        recurrenceKind: "once",
        timezone: "Asia/Shanghai",
        executionMode: "ai_run",
        enabled: true,
        nextRunEpoch: fixedNow - 10,
      },
    });
    assert.equal(createRes.status, 200);
    assert.equal(createRes.json.serverConfirmed, true);
    assert.equal(createRes.json.schedule.recurrenceKind, "once");
    assert.equal(createRes.json.schedule.supportsLockScreenCloudExecution, true);
    assert.match(createRes.json.schedule.nextRunBeijingText, /北京时间/);

    // Fire TWO concurrent cron triggers simultaneously!
    const [r1, r2] = await Promise.all([
      executeDueCloudSchedules(env, { nowEpoch: fixedNow }),
      executeDueCloudSchedules(env, { nowEpoch: fixedNow }),
    ]);
    assert.equal(r1.executed + r2.executed, 1, "Concurrent cron triggers MUST execute a due once task at most once");

    // Fire 3 more cron ticks afterwards (simulating next minutes/hours/days)
    await executeDueCloudSchedules(env, { nowEpoch: fixedNow + 60 });
    await executeDueCloudSchedules(env, { nowEpoch: fixedNow + 3600 });
    await executeDueCloudSchedules(env, { nowEpoch: fixedNow + 90000 });

    assert.equal(upstreamCallCount, 1, "One-time task MUST call upstream LLM strictly ONCE");

    const listRes = await req("GET", "/v1/schedules", { token: fundedToken });
    assert.equal(listRes.status, 200);
    const item = listRes.json.schedules.find((s) => s.id === "sched-once-1");
    assert.ok(item);
    assert.equal(item.enabled, false);
    assert.equal(item.status, "completed");
    assert.equal(item.nextRunEpoch, 0);
    assert.equal(item.runCount, 1);
    assert.equal(item.lastRunStatus, "ai_completed");
    assert.equal(item.runs.length, 1);
    assert.equal(item.runs[0].status, "ai_completed");
    assert.ok(item.runs[0].costYuan > 0);

    // Ledger must have strictly 1 schedule_chat charge
    const ledgerCount = sqlite.prepare("SELECT COUNT(*) AS cnt FROM ledger WHERE user_id = ? AND kind = 'schedule_chat'").get(fundedUserID).cnt;
    assert.equal(ledgerCount, 1, "One-time task MUST produce strictly 1 billing ledger row");

    // Attempting to resume a completed one-time task must be rejected cleanly (409)
    const resumeCompleted = await req("POST", "/v1/schedules/sched-once-1/resume", { token: fundedToken });
    assert.equal(resumeCompleted.status, 409);
  }

  // TEST 2: Reminder-only (`reminder_only`) vs AI completion distinction
  {
    const remRes = await req("POST", "/v1/schedules", {
      token: fundedToken,
      body: {
        id: "sched-reminder-1",
        title: "交接班打卡提醒",
        prompt: "记得填写值班交接单",
        modelID: "",
        recurrenceKind: "once",
        timezone: "Asia/Shanghai",
        executionMode: "reminder_only",
        enabled: true,
        nextRunEpoch: fixedNow - 5,
      },
    });
    assert.equal(remRes.status, 200);
    const beforeCalls = upstreamCallCount;
    await executeDueCloudSchedules(env, { nowEpoch: fixedNow });
    assert.equal(upstreamCallCount, beforeCalls, "Reminder-only schedule MUST NOT call LLM");

    const listRes = await req("GET", "/v1/schedules", { token: fundedToken });
    const rem = listRes.json.schedules.find((s) => s.id === "sched-reminder-1");
    assert.equal(rem.status, "completed");
    assert.equal(rem.enabled, false);
    assert.equal(rem.lastRunStatus, "reminder_sent");
    assert.equal(rem.runs.length, 1);
    assert.equal(rem.runs[0].status, "reminder_sent");
    assert.equal(rem.runs[0].costYuan, 0);
  }

  // TEST 3: Insufficient balance writes independent failed run (¥0 charge, 0 LLM call) & does NOT loop
  {
    const brokeCreate = await req("POST", "/v1/schedules", {
      token: brokeToken,
      body: {
        id: "sched-broke-1",
        title: "零余额定时分析",
        prompt: "分析今日日志",
        modelID: "deepseek-chat",
        recurrenceKind: "once",
        timezone: "Asia/Shanghai",
        executionMode: "ai_run",
        enabled: true,
        nextRunEpoch: fixedNow - 5,
      },
    });
    assert.equal(brokeCreate.status, 200);
    const beforeCalls = upstreamCallCount;

    await executeDueCloudSchedules(env, { nowEpoch: fixedNow });
    await executeDueCloudSchedules(env, { nowEpoch: fixedNow + 60 }); // second tick must not duplicate failure!

    assert.equal(upstreamCallCount, beforeCalls, "Zero-balance schedule MUST NOT call upstream LLM");
    const listRes = await req("GET", "/v1/schedules", { token: brokeToken });
    const item = listRes.json.schedules.find((s) => s.id === "sched-broke-1");
    assert.equal(item.status, "completed");
    assert.equal(item.enabled, false);
    assert.equal(item.lastRunStatus, "failed_insufficient_balance");
    assert.match(item.lastError || "", /余额不足/);
    assert.equal(item.runs.length, 1);
    assert.equal(item.runs[0].status, "failed_insufficient_balance");
    assert.equal(item.runs[0].costYuan, 0);
  }

  // TEST 4: Pause & Cancel stop execution with 0 LLM calls and 0 charges
  {
    await req("POST", "/v1/schedules", {
      token: fundedToken,
      body: {
        id: "sched-pause-1",
        title: "可暂停的每日任务",
        prompt: "每日巡检",
        modelID: "deepseek-chat",
        recurrenceKind: "daily",
        scheduleHour: 8,
        scheduleMinute: 30,
        timezone: "Asia/Shanghai",
        executionMode: "ai_run",
        enabled: true,
        nextRunEpoch: fixedNow - 5,
      },
    });
    const pauseRes = await req("POST", "/v1/schedules/sched-pause-1/pause", { token: fundedToken });
    assert.equal(pauseRes.status, 200);
    assert.equal(pauseRes.json.schedule.status, "paused");
    assert.equal(pauseRes.json.schedule.enabled, false);

    await req("POST", "/v1/schedules", {
      token: fundedToken,
      body: {
        id: "sched-cancel-1",
        title: "可取消的单次任务",
        prompt: "取消后不执行",
        modelID: "deepseek-chat",
        recurrenceKind: "once",
        timezone: "Asia/Shanghai",
        executionMode: "ai_run",
        enabled: true,
        nextRunEpoch: fixedNow - 5,
      },
    });
    const cancelRes = await req("POST", "/v1/schedules/sched-cancel-1/cancel", { token: fundedToken });
    assert.equal(cancelRes.status, 200);
    assert.equal(cancelRes.json.schedule.status, "cancelled");
    assert.equal(cancelRes.json.schedule.nextRunEpoch, 0);

    const beforeCalls = upstreamCallCount;
    await executeDueCloudSchedules(env, { nowEpoch: fixedNow });
    assert.equal(upstreamCallCount, beforeCalls, "Paused and cancelled schedules MUST NOT execute");
  }

  // TEST 5: Daily Beijing recurring task executes once for today's slot and advances to tomorrow 08:30 Beijing
  {
    const day1Due = Math.floor(Date.UTC(2026, 10, 26, 0, 30, 0) / 1000); // 2026-11-26 08:30 Beijing
    await req("POST", "/v1/schedules", {
      token: fundedToken,
      body: {
        id: "sched-daily-bj",
        title: "每日早八半值班提醒",
        prompt: "汇报今日值班重点",
        modelID: "deepseek-chat",
        recurrenceKind: "daily",
        scheduleHour: 8,
        scheduleMinute: 30,
        timezone: "Asia/Shanghai",
        executionMode: "ai_run",
        enabled: true,
        nextRunEpoch: day1Due,
      },
    });
    const beforeCalls = upstreamCallCount;
    await executeDueCloudSchedules(env, { nowEpoch: day1Due + 5 });
    // Repeating cron 2 minutes later MUST NOT re-run today's slot!
    await executeDueCloudSchedules(env, { nowEpoch: day1Due + 125 });
    assert.equal(upstreamCallCount, beforeCalls + 1);

    const listRes = await req("GET", "/v1/schedules", { token: fundedToken });
    const daily = listRes.json.schedules.find((s) => s.id === "sched-daily-bj");
    assert.equal(daily.enabled, true);
    assert.equal(daily.status, "active");
    assert.equal(daily.nextRunBeijingText, "2026-11-27 08:30 (北京时间)");
    assert.equal(daily.runs.length, 1);
  }

  // TEST 6: Non-destructive schema upgrade on legacy schedules table
  {
    const legacySqlite = new DatabaseSync(":memory:");
    legacySqlite.exec(`
      CREATE TABLE users (id TEXT PRIMARY KEY, token_hash TEXT UNIQUE, display_name TEXT, balance_micros INTEGER DEFAULT 0, sandbox_balance_micros INTEGER DEFAULT 0, total_recharged_micros INTEGER DEFAULT 0, total_spent_micros INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now')));
      CREATE TABLE ledger (id TEXT PRIMARY KEY, user_id TEXT, kind TEXT, amount_micros INTEGER, balance_after_micros INTEGER, created_at TEXT DEFAULT (datetime('now')));
      CREATE TABLE schedules (id TEXT PRIMARY KEY, user_id TEXT, title TEXT, prompt TEXT, model_id TEXT, interval_minutes INTEGER, enabled INTEGER, next_run_epoch INTEGER, last_run_at TEXT, last_answer TEXT, last_cost_micros INTEGER, created_at TEXT DEFAULT (datetime('now')));
      INSERT INTO schedules (id, user_id, title, prompt, model_id, interval_minutes, enabled, next_run_epoch, last_cost_micros) VALUES ('legacy-1', 'u1', 'OldTask', 'Hi', 'deepseek-chat', 1440, 1, 9999999999, 0);
    `);
    const legacyEnv = { DB: makeDB(legacySqlite) };
    await ensureSchemaUpgraded(legacyEnv);
    const preserved = legacySqlite.prepare("SELECT id, recurrence_kind, timezone, execution_mode, status FROM schedules WHERE id = 'legacy-1'").get();
    assert.equal(preserved.id, "legacy-1");
    assert.equal(preserved.recurrence_kind, "daily");
    assert.equal(preserved.timezone, "Asia/Shanghai");
    assert.equal(preserved.execution_mode, "ai_run");
    assert.equal(preserved.status, "active");
  }

  console.log("ALL schedules-reliability.test.mjs assertions PASSED (6/6 suites)");
} finally {
  globalThis.fetch = originalFetch;
}
