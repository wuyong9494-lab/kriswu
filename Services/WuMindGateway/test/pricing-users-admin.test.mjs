#!/usr/bin/env node
/**
 * Workstream B Verification Suite:
 *  1. Unified 1.50× Official-Base Server Pricing:
 *     - Preview diffs without mutating DB -> Approve -> Verify exact 1.50× prices for chat/image/video/voice
 *     - Re-sync idempotency: running preview + approve repeatedly NEVER compounds 1.50× twice!
 *     - Models lacking official price stay `pending_pricing`, blocked from enabling & never billed at ¥0
 *     - Catalog-visible models are NEVER auto-enabled
 *     - Search + pagination + capability grouping on GET /v1/admin/models (no 40-item cap)
 *  2. Dedicated User Management (205+ Users Pagination, Brand-New ¥0 User, Detail Breakdown, Direct Top-Up):
 *     - 205 registered users paginate cleanly across 5 pages; brand-new ¥0 unused user appears immediately
 *     - Search by WM- ID and nickname
 *     - GET /v1/admin/users/:id/detail returns gateway-only today/7d/all-time stats, model/kind breakdown & ledger
 *     - Direct idempotent top-up credits once & separates admin_grant from purchased_recharged
 *     - Non-admin gets HTTP 403 on all admin pricing & user endpoints
 *     - Existing payment switches (AUTO_CREDIT_PAUSED=true, ALLOW_APPLE_PRODUCTION_IAP=false) remain untouched
 */
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import worker from "../src/index.js";
import { computeUniformMarkupPrices } from "../src/model-catalog.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const schemaSql = fs.readFileSync(path.join(__dirname, "..", "schema.sql"), "utf8");
const originalFetch = globalThis.fetch;

function makeD1(sqlite) {
  return {
    prepare(sql) {
      let args = [];
      const stmtObj = {
        bind(...v) { args = v; return stmtObj; },
        async first() { return sqlite.prepare(sql).get(...args) ?? null; },
        async all() { return { results: sqlite.prepare(sql).all(...args) }; },
        async run() {
          const info = sqlite.prepare(sql).run(...args);
          return { success: true, meta: { changes: info.changes, last_row_id: info.lastInsertRowid } };
        },
        _execSync() {
          const info = sqlite.prepare(sql).run(...args);
          return { success: true, meta: { changes: info.changes, last_row_id: info.lastInsertRowid } };
        },
      };
      return stmtObj;
    },
    async batch(statements) {
      sqlite.exec("BEGIN IMMEDIATE");
      try {
        const out = [];
        for (const s of statements) out.push(s._execSync());
        sqlite.exec("COMMIT");
        return out;
      } catch (err) {
        try { sqlite.exec("ROLLBACK"); } catch {}
        throw err;
      }
    },
  };
}

function makeEnv(sqlite) {
  return {
    DB: makeD1(sqlite),
    ADMIN_SECRET: "test-admin-secret-2026",
    AIHUBMIX_API_KEY: "sk-test-aihubmix",
    AUTO_CREDIT_PAUSED: "true",
    ALLOW_APPLE_PRODUCTION_IAP: "false",
    USD_TO_CNY_RATE: "7.25",
  };
}

async function req(env, method, pathStr, body = null, headers = {}) {
  const init = { method, headers: { ...headers } };
  if (body !== null) {
    init.headers["Content-Type"] = "application/json";
    init.body = JSON.stringify(body);
  }
  const res = await worker.fetch(new Request(`https://gateway.test${pathStr}`, init), env);
  const data = await res.json();
  return { status: res.status, data };
}

async function run() {
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec(schemaSql);
  const env = makeEnv(sqlite);
  const adminHeaders = { "X-WuMind-Admin-Secret": env.ADMIN_SECRET };

  // -------------------------------------------------------------------------
  // 1. Non-admin access MUST return 403
  // -------------------------------------------------------------------------
  for (const [m, p] of [
    ["GET", "/v1/admin/users"],
    ["GET", "/v1/admin/users/WM-TEST/detail"],
    ["POST", "/v1/admin/pricing/preview"],
    ["POST", "/v1/admin/pricing/approve"],
    ["GET", "/v1/admin/models"],
  ]) {
    const r = await req(env, m, p, m === "POST" ? {} : null, { "X-WuMind-Admin-Secret": "wrong-secret" });
    assert.equal(r.status, 403, `Expected 403 on ${m} ${p}, got ${r.status}`);
  }
  console.log("PASS 1: Non-admin blocked with 403 across all pricing & user management endpoints");

  // -------------------------------------------------------------------------
  // 2. Discover 60+ models (including chat/image/video/voice + unpriced mystery model)
  // -------------------------------------------------------------------------
  const mockModels = [
    { id: "deepseek-chat" },
    { id: "gpt-4o" },
    { id: "gpt-image-1" },
    { id: "sora-2" },
    { id: "gpt-realtime" },
    { id: "mystery-unpriced-9000" },
  ];
  for (let i = 1; i <= 50; i++) {
    mockModels.push({ id: `custom-chat-model-${String(i).padStart(2, "0")}` });
  }

  globalThis.fetch = async (url) => {
    if (String(url).includes("/v1/models")) {
      return new Response(JSON.stringify({ data: mockModels }), { status: 200 });
    }
    throw new Error(`Unexpected fetch URL: ${url}`);
  };

  try {
    const disc = await req(env, "POST", "/v1/admin/models/discover", { providers: ["aihubmix"] }, adminHeaders);
    assert.equal(disc.status, 200);
    assert.equal(disc.data.totalDiscovered, 56);

    // Ensure ZERO models were auto-enabled on discovery!
    const listBefore = await req(env, "GET", "/v1/admin/models?limit=100", null, adminHeaders);
    assert.equal(listBefore.status, 200);
    assert.equal(listBefore.data.totalCount, 56, "Must support >40 models without 40-item truncation");
    assert.equal(listBefore.data.enabledVerifiedCount, 0, "Catalog-visible models must NEVER be auto-enabled");

    // -------------------------------------------------------------------------
    // 3. Preview uniform 1.50× pricing -> verify NO DB mutation yet!
    // -------------------------------------------------------------------------
    const prev = await req(env, "POST", "/v1/admin/pricing/preview", { fxUsdToCny: 7.25, markupMultiplier: 1.5 }, adminHeaders);
    assert.equal(prev.status, 200);
    assert.equal(prev.data.markupMultiplier, 1.5);
    assert.equal(prev.data.fxUsdToCny, 7.25);

    const gpt4oDiff = prev.data.diffs.find((d) => d.id === "gpt-4o");
    assert.ok(gpt4oDiff);
    // Official $2.50 / $10.00 / cache $1.25 * 7.25 * 1.50 = 27.1875 / 108.75 / 13.5938
    assert.equal(gpt4oDiff.newInputPricePerMillion, 27.1875);
    assert.equal(gpt4oDiff.newOutputPricePerMillion, 108.75);
    assert.equal(gpt4oDiff.newCachePricePerMillion, 13.5938);
    assert.equal(gpt4oDiff.pricingStatus, "priced");

    const imgDiff = prev.data.diffs.find((d) => d.id === "gpt-image-1");
    assert.equal(imgDiff.newUnitPriceYuan, 0.435); // $0.04 * 7.25 * 1.50
    const vidDiff = prev.data.diffs.find((d) => d.id === "sora-2");
    assert.equal(vidDiff.newUnitPriceYuan, 1.0875); // $0.10 * 7.25 * 1.50
    const voiceDiff = prev.data.diffs.find((d) => d.id === "gpt-realtime");
    assert.equal(voiceDiff.newUnitPriceYuan, 2.61); // $0.24 * 7.25 * 1.50

    const mysteryDiff = prev.data.diffs.find((d) => d.id === "mystery-unpriced-9000");
    assert.equal(mysteryDiff.pricingStatus, "pending_pricing");
    assert.equal(mysteryDiff.newInputPricePerMillion, 0);
    assert.equal(mysteryDiff.newOutputPricePerMillion, 0);

    // Confirm preview did NOT write to DB
    const checkPreApprove = sqlite.prepare("SELECT input_price_per_million, pricing_status FROM model_catalog WHERE model_id = 'gpt-4o'").get();
    assert.equal(checkPreApprove.input_price_per_million, 0, "Preview must NOT mutate DB before admin approval");

    // -------------------------------------------------------------------------
    // 4. Approve pricing sync -> verify applied + ZERO compounding on repeat sync!
    // -------------------------------------------------------------------------
    const appr1 = await req(env, "POST", "/v1/admin/pricing/approve", { fxUsdToCny: 7.25, markupMultiplier: 1.5, operatorID: "WM-ADMIN" }, adminHeaders);
    assert.equal(appr1.status, 200);
    assert.ok(appr1.data.priceVersion >= 1);

    const checkPost1 = sqlite.prepare("SELECT input_price_per_million, output_price_per_million, cache_price_per_million, pricing_status, enabled FROM model_catalog WHERE model_id = 'gpt-4o'").get();
    assert.equal(checkPost1.input_price_per_million, 27.1875);
    assert.equal(checkPost1.output_price_per_million, 108.75);
    assert.equal(checkPost1.cache_price_per_million, 13.5938);
    assert.equal(checkPost1.pricing_status, "priced");
    assert.equal(checkPost1.enabled, 0, "Approving pricing must NOT auto-enable unverified models");

    // Repeat preview & approve 2 more times -> prices MUST NOT multiply by 1.5 again!
    const prev2 = await req(env, "POST", "/v1/admin/pricing/preview", { fxUsdToCny: 7.25, markupMultiplier: 1.5 }, adminHeaders);
    assert.equal(prev2.data.summary.changed, 0, "Re-syncing same official base MUST have 0 changed models (zero compounding!)");
    const appr2 = await req(env, "POST", "/v1/admin/pricing/approve", { fxUsdToCny: 7.25, markupMultiplier: 1.5 }, adminHeaders);
    assert.equal(appr2.status, 200);
    const checkPost2 = sqlite.prepare("SELECT input_price_per_million, output_price_per_million FROM model_catalog WHERE model_id = 'gpt-4o'").get();
    assert.equal(checkPost2.input_price_per_million, 27.1875, "Re-sync MUST NEVER compound 1.5× on top of 1.5×!");
    assert.equal(checkPost2.output_price_per_million, 108.75);

    // Pure function sanity check
    const pureCheck = computeUniformMarkupPrices({ pricingMode: "per_second", officialUnitUSD: 0.10 }, 7.25, 1.5);
    assert.equal(pureCheck.unitPriceYuan, 1.0875);

    // Verify pending_pricing model CANNOT be enabled (even if manually marked verified) -> never billed at ¥0!
    sqlite.prepare("UPDATE model_catalog SET probe_status = 'verified' WHERE model_id = 'mystery-unpriced-9000'").run();
    const enablePending = await req(env, "POST", "/v1/admin/models/batch-update", {
      updates: [{ id: "mystery-unpriced-9000", enabled: true }],
    }, adminHeaders);
    assert.equal(enablePending.status, 400);
    assert.equal(enablePending.data.rejected[0].code, "unpriced");
    assert.equal(enablePending.data.rejected[0].pricingStatus, "pending_pricing");

    // Verify catalog search + capability filter + pagination (>40 items)
    const p1 = await req(env, "GET", "/v1/admin/models?page=1&limit=20&capability=chat", null, adminHeaders);
    assert.equal(p1.status, 200);
    assert.equal(p1.data.models.length, 20);
    assert.equal(p1.data.hasMore, true);
    assert.ok(p1.data.totalCount >= 52);

    const pVoice = await req(env, "GET", "/v1/admin/models?capability=voice", null, adminHeaders);
    assert.equal(pVoice.data.models.some((m) => m.id === "gpt-realtime"), true);
    console.log("PASS 2-4: Unified 1.50× server pricing (chat/image/video/voice), zero compounding, pending_pricing guard, >40 pagination");
  } finally {
    globalThis.fetch = originalFetch;
  }

  // -------------------------------------------------------------------------
  // 5. 205 Registered Users Pagination + New ¥0 User + Detail + Direct Idempotent Top-Up
  // -------------------------------------------------------------------------
  const insertUser = sqlite.prepare(
    `INSERT INTO users (id, token_hash, display_name, balance_micros, purchased_recharged_micros, admin_granted_micros, total_spent_micros, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
  );
  for (let i = 1; i <= 204; i++) {
    const id = `WM-U${String(i).padStart(4, "0")}`;
    insertUser.run(
      id,
      `hash_${id}`,
      `测试用户${i}`,
      i % 3 === 0 ? 10_000_000 : 0,
      i % 3 === 0 ? 10_000_000 : 0,
      0,
      i % 5 === 0 ? 1_200_000 : 0,
      "2026-11-20 10:00:00",
      "2026-11-20 10:00:00"
    );
  }
  // Brand-new ¥0 unused user registered TODAY
  sqlite.prepare(
    `INSERT INTO users (id, token_hash, display_name, balance_micros, created_at, updated_at)
     VALUES ('WM-NEW001', 'hash_new001', '刚注册零消费新用户', 0, datetime('now'), datetime('now'))`
  ).run();

  // Add realistic ledger rows for WM-U0001 (today + 3 days ago + refund)
  sqlite.prepare(
    `INSERT INTO ledger (user_id, kind, provider, model, prompt_tokens, completion_tokens, reasoning_tokens, cost_micros, upstream_cost_micros, balance_after_micros, note, created_at)
     VALUES
       ('WM-U0001', 'chat', 'aihubmix', 'gpt-4o', 1200, 800, 0, 119625, 79750, 9880375, '对话扣费', datetime('now')),
       ('WM-U0001', 'video', 'aihubmix', 'sora-2', 0, 0, 0, 8700000, 5800000, 1180375, '视频8秒', datetime('now', '-2 days')),
       ('WM-U0001', 'apple_iap_refund', 'apple', '', 0, 0, 0, 6000000, 0, 1180375, '退款冲正', datetime('now', '-3 days'))`
  ).run();

  const usersP1 = await req(env, "GET", "/v1/admin/users?page=1&limit=50", null, adminHeaders);
  assert.equal(usersP1.status, 200);
  assert.equal(usersP1.data.allUsersCount, 205);
  assert.equal(usersP1.data.totalUsers, 205);
  assert.equal(usersP1.data.todayNewUsers, 1);
  assert.equal(usersP1.data.totalPages, 5);
  assert.equal(usersP1.data.hasMore, true);
  assert.equal(usersP1.data.users.length, 50);
  assert.equal(usersP1.data.users[0].userID, "WM-NEW001", "Newest brand-new ¥0 user must appear first!");
  assert.equal(usersP1.data.users[0].balanceYuan, 0);

  const usersP5 = await req(env, "GET", "/v1/admin/users?page=5&limit=50", null, adminHeaders);
  assert.equal(usersP5.data.users.length, 5);
  assert.equal(usersP5.data.hasMore, false);

  const usersSearch = await req(env, "GET", "/v1/admin/users?q=刚注册", null, adminHeaders);
  assert.equal(usersSearch.data.totalUsers, 1);
  assert.equal(usersSearch.data.users[0].userID, "WM-NEW001");

  // User Detail check (today / 7d / all-time + model breakdown + gateway-only scope note)
  const detail = await req(env, "GET", "/v1/admin/users/WM-U0001/detail", null, adminHeaders);
  assert.equal(detail.status, 200);
  assert.equal(detail.data.scope, "wumind_gateway_only");
  assert.ok(detail.data.scopeNote.includes("自有 API Key"));
  assert.equal(detail.data.usageSummary.today.requests, 1);
  assert.equal(detail.data.usageSummary.last7Days.requests, 2);
  assert.equal(detail.data.usageSummary.allTime.requests, 2);
  assert.equal(detail.data.user.refundedYuan, 6);
  assert.equal(detail.data.breakdownByModel.length, 2);
  assert.equal(detail.data.breakdownByModel[0].model, "sora-2");

  // Direct idempotent admin top-up on brand-new user WM-NEW001 (sent TWICE -> must credit ONCE!)
  const idem = "adm-direct-new001-001";
  const top1 = await req(env, "POST", "/v1/admin/topup", {
    userID: "WM-NEW001",
    amountYuan: 25,
    environment: "production",
    note: "新用户首测赠额",
    operatorID: "WM-ADMIN",
    idempotencyKey: idem,
  }, adminHeaders);
  assert.equal(top1.status, 200);
  assert.equal(top1.data.balanceYuan, 25);

  const top2 = await req(env, "POST", "/v1/admin/topup", {
    userID: "WM-NEW001",
    amountYuan: 25,
    environment: "production",
    note: "新用户首测赠额",
    operatorID: "WM-ADMIN",
    idempotencyKey: idem,
  }, adminHeaders);
  assert.equal(top2.status, 200);
  assert.equal(top2.data.alreadyApplied, true);
  assert.equal(top2.data.balanceYuan, 25, "Duplicate idempotencyKey MUST NOT double-credit!");

  const detailAfterTop = await req(env, "GET", "/v1/admin/users/WM-NEW001/detail", null, adminHeaders);
  assert.equal(detailAfterTop.data.user.balanceYuan, 25);
  assert.equal(detailAfterTop.data.user.adminGrantedYuan, 25);
  assert.equal(detailAfterTop.data.user.purchasedRechargedYuan, 0, "Admin grant must NEVER count as purchased recharge!");
  assert.equal(detailAfterTop.data.recentAdminCredits.length, 1);

  // Verify summary preserves untouched payment switches
  const summary = await req(env, "GET", "/v1/admin/summary", null, adminHeaders);
  assert.equal(summary.status, 200);
  assert.equal(summary.data.userCount, 205);
  assert.equal(summary.data.todayNewUsers, 1);
  assert.equal(summary.data.todayRequests, 1);
  assert.equal(summary.data.autoCreditPaused, true, "AUTO_CREDIT_PAUSED must remain untouched");
  assert.equal(summary.data.appleIAPProductionEnabled, false, "ALLOW_APPLE_PRODUCTION_IAP must remain untouched");
  assert.equal(summary.data.markupMultiplier, 1.5);
  console.log("PASS 5: 205-user pagination, ¥0 new user visibility, user detail breakdown, idempotent direct credit, untouched payment switches");
}

run().catch((err) => {
  console.error("TEST FAILED:", err);
  process.exit(1);
});
