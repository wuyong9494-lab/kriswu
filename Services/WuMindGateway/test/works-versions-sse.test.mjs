#!/usr/bin/env node
/**
 * Release-Blocker Gateway Verification Suite:
 *  1. R2 Version Isolation & Reference-Counted Delete:
 *     - v1 uploaded -> v2 created with fixed versionWorkID & pendingAssetUpload=true (interrupted mid-upload)
 *     - v2 MUST report assetSyncState='pending_upload' and GET /v1/works/v2/asset MUST return 409 asset_pending_sync (NEVER v1 bytes!)
 *     - Re-submitting v2 with the same fixed versionWorkID resumes idempotently (ONLY ONE v2 row!)
 *     - Completing v2 PUT /asset gives distinct v2 bytes; deleting v2 leaves v1 bytes downloadable intact!
 *     - Defense-in-depth: even if two rows share a legacy R2 object key, deleting one retains the shared R2 key for the other!
 *  2. Paginated Works Sync (>80 works, testing work #81 & type filtering + downloading #81 original)
 *  3. Real Event-Driven Web-Search SSE (`searching` -> `search_results` -> `reading` -> `page_result` -> `done` + honest `error` on failure with 0 charge)
 */
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import worker from "../src/index.js";

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
          return { success: true, meta: { changes: Number(info.changes || 0) } };
        },
        _execSync() {
          const info = sqlite.prepare(sql).run(...args);
          return { success: true, meta: { changes: Number(info.changes || 0) } };
        },
      };
      return stmtObj;
    },
    async batch(stmts) {
      sqlite.exec("BEGIN IMMEDIATE");
      try {
        const res = stmts.map((s) => s._execSync());
        sqlite.exec("COMMIT");
        return res;
      } catch (e) {
        sqlite.exec("ROLLBACK");
        throw e;
      }
    },
  };
}

function makeMockR2Bucket() {
  const objects = new Map();
  return {
    _objects: objects,
    async put(key, value, options = {}) {
      const bytes = value instanceof Uint8Array
        ? new Uint8Array(value)
        : (value instanceof ArrayBuffer ? new Uint8Array(value) : new TextEncoder().encode(String(value)));
      objects.set(key, {
        bytes,
        httpMetadata: options.httpMetadata || {},
        customMetadata: options.customMetadata || {},
      });
    },
    async get(key) {
      const entry = objects.get(key);
      if (!entry) return null;
      return {
        httpMetadata: entry.httpMetadata,
        customMetadata: entry.customMetadata,
        async arrayBuffer() {
          return entry.bytes.buffer.slice(entry.bytes.byteOffset, entry.bytes.byteOffset + entry.bytes.byteLength);
        },
      };
    },
    async delete(key) {
      objects.delete(key);
    },
  };
}

async function req(env, method, pathName, { token = null, adminSecret = null, body = null, rawBytes = null, headers = {} } = {}) {
  const h = new Headers(headers);
  if (token) h.set("Authorization", `Bearer ${token}`);
  if (adminSecret) h.set("X-WuMind-Admin-Secret", adminSecret);
  let payload = null;
  if (rawBytes !== null) {
    payload = rawBytes;
  } else if (body !== null) {
    h.set("Content-Type", "application/json");
    payload = JSON.stringify(body);
  }
  const request = new Request(`https://wumind-test.workers.dev${pathName}`, {
    method,
    headers: h,
    body: method === "GET" || method === "HEAD" ? undefined : payload,
  });
  return await worker.fetch(request, env, {});
}

function parseSSEEvents(rawText) {
  const events = [];
  for (const chunk of rawText.split("\n\n")) {
    const trimmed = chunk.trim();
    if (!trimmed) continue;
    let eventName = "message";
    let dataLine = "";
    for (const line of trimmed.split("\n")) {
      if (line.startsWith("event:")) eventName = line.slice(6).trim();
      else if (line.startsWith("data:")) dataLine += line.slice(5).trim();
    }
    if (dataLine) {
      events.push({ event: eventName, data: JSON.parse(dataLine) });
    }
  }
  return events;
}

async function run() {
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec(schemaSql);
  const r2 = makeMockR2Bucket();
  const env = {
    DB: makeDB(sqlite),
    WORKS_BUCKET: r2,
    ADMIN_SECRET: "test-admin-secret-999",
    TAVILY_API_KEY: "tvly-test-key",
    AUTO_CREDIT_PAUSED: "true",
    ALLOW_APPLE_PRODUCTION_IAP: "false",
  };

  // Register user & grant ¥10 balance
  const reg = await (await req(env, "POST", "/v1/account/register", {
    body: { displayName: "版本与同步测试员" },
  })).json();
  const token = reg.userToken;
  assert.ok(token);
  const topupRes = await req(env, "POST", "/v1/admin/topup", {
    adminSecret: env.ADMIN_SECRET,
    body: { userID: reg.userID, amountYuan: 10, environment: "production", idempotencyKey: "seed-10" },
  });
  assert.equal(topupRes.status, 200);

  // =========================================================================
  // TEST 1: R2 Version Isolation, Interrupted v2 Resume, & Ref-Counted Delete
  // =========================================================================
  const v1ID = "WRK-V1-ORIGINAL";
  const v1Bytes = new TextEncoder().encode("V1-ORIGINAL-BINARY-CONTENT-AAAA");
  const c1 = await req(env, "POST", "/v1/works", {
    token,
    body: { id: v1ID, workType: "ppt", title: "季度汇报 v1", status: "completed", progress: 100, assetMime: "application/octet-stream" },
  });
  assert.equal(c1.status, 200);

  const put1 = await req(env, "PUT", `/v1/works/${v1ID}/asset`, {
    token,
    rawBytes: v1Bytes,
    headers: { "Content-Type": "application/octet-stream" },
  });
  assert.equal(put1.status, 200);

  // Start v2 with fixed versionWorkID & pendingAssetUpload=true (simulating interrupted upload BEFORE PUT /asset!)
  const v2FixedID = "WRK-V2-FIXED-RESUME";
  const v2CreateResp = await req(env, "PATCH", `/v1/works/${v1ID}`, {
    token,
    body: {
      createNewVersion: true,
      versionWorkID: v2FixedID,
      idempotencyKey: "ver-idem-v2",
      title: "季度汇报 v2（修改第5页）",
      pendingAssetUpload: true,
      assetMime: "application/octet-stream",
    },
  });
  assert.equal(v2CreateResp.status, 200);
  const v2Create = await v2CreateResp.json();
  assert.equal(v2Create.versionCreated, true);
  assert.equal(v2Create.work.id, v2FixedID);
  assert.equal(v2Create.work.versionNumber, 2);
  assert.equal(v2Create.work.assetSyncState, "pending_upload", "Incomplete v2 MUST show pending_upload (待同步)");
  assert.equal(v2Create.work.hasAsset, false, "Incomplete v2 MUST NOT inherit v1's asset!");

  // Downloading v2 BEFORE its upload finishes MUST return 409 asset_pending_sync (NEVER v1 bytes!)
  const dlV2Pending = await req(env, "GET", `/v1/works/${v2FixedID}/asset`, { token });
  assert.equal(dlV2Pending.status, 409);
  const dlV2PendingBody = await dlV2Pending.json();
  assert.equal(dlV2PendingBody.code, "asset_pending_sync");

  // Reconnect & resume v2 creation using the SAME fixed versionWorkID -> MUST NOT create duplicate v2!
  const v2ResumeResp = await req(env, "PATCH", `/v1/works/${v1ID}`, {
    token,
    body: {
      createNewVersion: true,
      versionWorkID: v2FixedID,
      idempotencyKey: "ver-idem-v2",
      title: "季度汇报 v2（恢复上传）",
      pendingAssetUpload: true,
    },
  });
  const v2Resume = await v2ResumeResp.json();
  assert.equal(v2Resume.idempotentReplay, true);
  assert.equal(v2Resume.work.id, v2FixedID);

  const countV2 = sqlite.prepare("SELECT COUNT(*) AS cnt FROM user_works WHERE parent_work_id = ?").get(v1ID);
  assert.equal(Number(countV2.cnt), 1, "Resuming interrupted v2 MUST keep strictly ONE v2 row!");

  // Finish uploading v2 binary
  const v2Bytes = new TextEncoder().encode("V2-UPDATED-BINARY-CONTENT-BBBB");
  const put2 = await req(env, "PUT", `/v1/works/${v2FixedID}/asset`, {
    token,
    rawBytes: v2Bytes,
    headers: { "Content-Type": "application/octet-stream" },
  });
  assert.equal(put2.status, 200);

  // Verify v2 downloads v2 bytes and v1 downloads v1 bytes
  const gotV2 = await (await req(env, "GET", `/v1/works/${v2FixedID}/asset`, { token })).text();
  const gotV1Before = await (await req(env, "GET", `/v1/works/${v1ID}/asset`, { token })).text();
  assert.equal(gotV2, "V2-UPDATED-BINARY-CONTENT-BBBB");
  assert.equal(gotV1Before, "V1-ORIGINAL-BINARY-CONTENT-AAAA");

  // Delete v2 -> v1 original MUST remain intact and downloadable!
  const delV2 = await req(env, "DELETE", `/v1/works/${v2FixedID}`, { token });
  assert.equal(delV2.status, 200);
  const gotV1After = await req(env, "GET", `/v1/works/${v1ID}/asset`, { token });
  assert.equal(gotV1After.status, 200);
  assert.equal(await gotV1After.text(), "V1-ORIGINAL-BINARY-CONTENT-AAAA");

  // Defense-in-depth: force a legacy row sharing v1's exact asset_object_key, delete that legacy row -> v1 R2 object MUST survive!
  const v1KeyRow = sqlite.prepare("SELECT asset_object_key FROM user_works WHERE id = ?").get(v1ID);
  sqlite.prepare(
    `INSERT INTO user_works (id, user_id, work_type, title, status, progress, asset_object_key, asset_sync_state, version_number, parent_work_id)
     VALUES ('WRK-LEGACY-SHARED', ?, 'ppt', 'Legacy Shared Key Row', 'completed', 100, ?, 'synced', 3, ?)`
  ).run(reg.userID, v1KeyRow.asset_object_key, v1ID);
  const delShared = await (await req(env, "DELETE", "/v1/works/WRK-LEGACY-SHARED", { token })).json();
  assert.equal(delShared.ok, true);
  assert.ok(delShared.retainedSharedKeys.includes(v1KeyRow.asset_object_key), "Shared R2 key MUST be retained!");
  const gotV1AfterSharedDel = await req(env, "GET", `/v1/works/${v1ID}/asset`, { token });
  assert.equal(gotV1AfterSharedDel.status, 200);
  assert.equal(await gotV1AfterSharedDel.text(), "V1-ORIGINAL-BINARY-CONTENT-AAAA");
  console.log("PASS 1: R2 version isolation, pending_upload 409 guard, fixed-ID resume, & ref-counted delete verified");

  // =========================================================================
  // TEST 2: 85-Work Pagination + Type Filter + Work #81 Original Download
  // =========================================================================
  for (let i = 1; i <= 84; i++) {
    const wid = `WRK-PAGE-${String(i).padStart(3, "0")}`;
    const wtype = i === 81 ? "image" : (i % 2 === 0 ? "image" : "document");
    const ts = `2026-11-01 00:${String(Math.floor(i / 60)).padStart(2, "0")}:${String(i % 60).padStart(2, "0")}`;
    sqlite.prepare(
      `INSERT INTO user_works (id, user_id, work_type, title, status, progress, asset_sync_state, version_number, created_at, updated_at)
       VALUES (?, ?, ?, ?, 'completed', 100, 'synced', 1, ?, ?)`
    ).run(wid, reg.userID, wtype, `历史作品 #${i}`, ts, ts);
  }
  // Upload real original binary to the oldest item (WRK-PAGE-001, which is the 85th item on page 2!)
  const oldWorkID = "WRK-PAGE-001";
  const oldBytes = new TextEncoder().encode("OLD-WORK-85-ORIGINAL-PAYLOAD");
  const putOld = await req(env, "PUT", `/v1/works/${oldWorkID}/asset`, {
    token,
    rawBytes: oldBytes,
    headers: { "Content-Type": "text/plain" },
  });
  assert.equal(putOld.status, 200);

  const page1 = await (await req(env, "GET", "/v1/works?limit=80&offset=0", { token })).json();
  assert.equal(page1.total, 85);
  assert.equal(page1.works.length, 80);
  assert.equal(page1.hasMore, true);
  assert.equal(page1.nextOffset, 80);

  const page2 = await (await req(env, "GET", "/v1/works?limit=80&offset=80", { token })).json();
  assert.equal(page2.total, 85);
  assert.equal(page2.works.length, 5);
  assert.equal(page2.hasMore, false);
  assert.equal(page2.nextOffset, null);

  const allIDs = new Set([...page1.works.map((w) => w.id), ...page2.works.map((w) => w.id)]);
  assert.equal(allIDs.size, 85);
  assert.ok(allIDs.has(oldWorkID), "Item #85 beyond 80-item page 1 MUST be retrieved on page 2!");

  const dlOld = await req(env, "GET", `/v1/works/${oldWorkID}/asset`, { token });
  assert.equal(dlOld.status, 200);
  assert.equal(await dlOld.text(), "OLD-WORK-85-ORIGINAL-PAYLOAD");

  const filteredImg = await (await req(env, "GET", "/v1/works?type=image&limit=100", { token })).json();
  assert.equal(filteredImg.total, 43);
  assert.ok(filteredImg.works.every((w) => w.workType === "image"));
  console.log("PASS 2: 85-work paginated sync, type filter, and >80th original asset download verified");

  // =========================================================================
  // TEST 3: Real Event-Driven Web Search SSE (`searching` -> `reading` -> `done` + Failure)
  // =========================================================================
  globalThis.fetch = async (url) => {
    const u = String(url);
    if (u.includes("api.tavily.com/search")) {
      return new Response(JSON.stringify({
        results: [
          { title: "Official Pricing Docs", url: "https://docs.example.com/pricing", content: "Official snippet 1" },
          { title: "Blocked Forum Post", url: "https://blocked.example.com/post", content: "Snippet 2" },
        ],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (u === "https://docs.example.com/pricing") {
      return new Response("<html><body><h1>Pricing</h1><p>GPT-5 costs $1.50 per 1M tokens.</p></body></html>", {
        status: 200,
        headers: { "Content-Type": "text/html" },
      });
    }
    if (u === "https://blocked.example.com/post") {
      return new Response("Forbidden", { status: 403 });
    }
    throw new Error(`Unexpected fetch URL: ${u}`);
  };

  try {
    // A fresh phone login can use its existing wallet and the Worker search provider.
    const loginEnv = { ...env, AUTH_TEST_MODE: "true" };
    const phone = "13800000000";
    const challenge = await (await req(loginEnv, "POST", "/v1/auth/sms/send", { body: { phone } })).json();
    const login = await (await req(loginEnv, "POST", "/v1/auth/sms/verify", { body: { phone, code: challenge.debugCode } })).json();
    assert.ok(login.ok);
    const linkedAccount = await (await req(loginEnv, "GET", "/v1/account/me", { token: login.sessionToken })).json();
    assert.equal(linkedAccount.userID, login.user.wumindUserID);
    const funded = await req(loginEnv, "POST", "/v1/admin/topup", {
      adminSecret: env.ADMIN_SECRET,
      body: { userID: linkedAccount.userID, amountYuan: 1, environment: "test", idempotencyKey: "login-search-fixture" },
    });
    assert.equal(funded.status, 200);
    const byLogin = await req(loginEnv, "POST", "/v1/tools/web-search", {
      token: login.sessionToken, body: { query: "official docs", readTopPages: 1 },
    });
    assert.equal(byLogin.status, 200);
    const source = (await byLogin.json()).results[0];
    assert.equal(source.url, "https://docs.example.com/pricing");
    assert.equal((await fetch(source.url)).status, 200);
    const sseResp = await req(env, "POST", "/v1/tools/web-search", {
      token,
      headers: { Accept: "text/event-stream" },
      body: { query: "GPT-5 official pricing", readTopPages: 2, stream: true },
    });
    assert.equal(sseResp.status, 200);
    assert.ok((sseResp.headers.get("Content-Type") || "").includes("text/event-stream"));
    const events = parseSSEEvents(await sseResp.text());
    const names = events.map((e) => e.event);
    assert.deepEqual(names, ["searching", "search_results", "reading", "page_result", "reading", "page_result", "done"]);
    assert.equal(events[0].data.query, "GPT-5 official pricing");
    assert.equal(events[2].data.domain, "docs.example.com");
    assert.equal(events[3].data.readStatus, "full_text");
    assert.equal(events[4].data.domain, "blocked.example.com");
    assert.equal(events[5].data.readStatus, "fetch_failed");
    assert.equal(events[6].data.fullTextCount, 1);
    assert.equal(events[6].data.fetchFailedCount, 1);

    // Failure case: Tavily returns 500 -> SSE emits `error` AND releases reservation (0 charge!)
    const balBeforeFail = sqlite.prepare("SELECT balance_micros FROM users WHERE id = ?").get(reg.userID).balance_micros;
    const calledHosts = [];
    env.BRAVE_SEARCH_API_KEY = env.TAVILY_API_KEY;
    globalThis.fetch = async (input) => {
      calledHosts.push(new URL(input).hostname);
      return new Response("upstream down", { status: 500 });
    };
    const failResp = await req(env, "POST", "/v1/tools/web-search", {
      token,
      headers: { Accept: "text/event-stream" },
      body: { query: "failing query", readTopPages: 1, stream: true },
    });
    assert.equal(failResp.status, 200);
    const failEvents = parseSSEEvents(await failResp.text());
    assert.deepEqual(failEvents.map((e) => e.event), ["searching", "error"]);
    assert.equal(failEvents[1].data.ok, false);
    assert.equal(failEvents[1].data.costYuan, 0);
    assert.deepEqual(calledHosts, ["api.tavily.com"]);
    const missingConfig = await req({ ...env, TAVILY_API_KEY: "", BRAVE_SEARCH_API_KEY: "", ALLOW_DDG_SEARCH_FALLBACK: "true" },
      "POST", "/v1/tools/web-search", { token, body: { query: "公告", allowFallback: false } });
    assert.equal(missingConfig.status, 503);
    const missing = await missingConfig.json();
    assert.equal(missing.code, "search_not_configured");
    assert.match(missing.error, /管理员/);
    assert.equal(missing.costYuan, 0);
    assert.deepEqual(missing.results, []);
    assert.deepEqual(calledHosts, ["api.tavily.com"]);
    const balAfterFail = sqlite.prepare("SELECT balance_micros, reserved_micros FROM users WHERE id = ?").get(reg.userID);
    assert.equal(balAfterFail.balance_micros, balBeforeFail);
    assert.equal(balAfterFail.reserved_micros, 0);
    console.log("PASS 3: Real event-driven web-search SSE (`searching` -> `reading` -> `page_result` -> `done`) and 0-charge failure verified");
  } finally {
    globalThis.fetch = originalFetch;
  }
}

run().catch((err) => {
  console.error("FAIL:", err);
  process.exit(1);
});
