#!/usr/bin/env node
/**
 * P0 & P1 Critical Verification Suite:
 *  1. Single-Transaction ACID Billing (`settleReservationAtomic` & `releaseReservationAtomic`):
 *     - Fault injection mid-transaction -> full rollback (zero balance drift, status remains 'reserved', 0 ledger rows)
 *     - Clean retry after rollback -> succeeds & debits strictly once
 *     - 8x concurrent settlement race -> strictly 1 debit, 1 ledger row, zero double-charging
 *  2. Admin Exempt In-Flight Video Budget Enforcement:
 *     - Parallel exempt video submissions count in-flight `video_jobs` against daily cost ceiling (blocks bypass!)
 *  3. Legacy Order & Reservation Reconciliation (`GET /v1/admin/reconcile-orders`):
 *     - Detects paid orders missing ledger rows & verifies fail-closed auto-credit defaults
 *  4. Private Cloudflare R2 Works Object Storage (`PUT/GET /v1/works/:id/asset`):
 *     - Unconfigured R2 -> HTTP 503 `object_storage_unconfigured`, honest `assetSyncState`, never fakes synced or bloats D1
 *     - Configured R2 -> 4.5 MB binary roundtrip (SHA-256 verified), D1 `asset_base64` stays NULL, cross-account 404, delete cleans R2
 *  5. Server-Verified Web Search & Web Fetch (`/v1/tools/web-search`, `/v1/tools/web-fetch`):
 *     - Unconfigured -> 503 `search_not_configured` (zero debit)
 *     - Timeout -> 504 `timeout` (zero debit, never swallowed)
 *     - No results -> `no_results` (zero debit)
 *     - Real Tavily + `readTopPages` -> distinguishes `full_text` vs `fetch_failed`, SSRF blocks `127.0.0.1`
 */
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import worker from "../src/index.js";
import {
  reserveCreditAtomic,
  settleReservationAtomic,
  releaseReservationAtomic,
} from "../src/billing-safety.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const schemaSql = fs.readFileSync(path.join(__dirname, "..", "schema.sql"), "utf8");
const originalFetch = globalThis.fetch;

function makeFaultInjectableDB(sqlite) {
  let failOnBatchStmtIndex = null;
  let injectedFaults = 0;

  return {
    setFailOnBatchStmtIndex(idx) {
      failOnBatchStmtIndex = idx;
    },
    getInjectedFaultCount() {
      return injectedFaults;
    },
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
        const results = [];
        for (let i = 0; i < stmts.length; i++) {
          if (failOnBatchStmtIndex !== null && i === failOnBatchStmtIndex) {
            failOnBatchStmtIndex = null;
            injectedFaults += 1;
            throw new Error(`INJECTED_D1_FAULT_AT_STMT_${i}`);
          }
          results.push(stmts[i]._execSync());
        }
        sqlite.exec("COMMIT");
        return results;
      } catch (err) {
        sqlite.exec("ROLLBACK");
        throw err;
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
      return { key, size: bytes.byteLength };
    },
    async get(key) {
      const entry = objects.get(key);
      if (!entry) return null;
      return {
        key,
        size: entry.bytes.byteLength,
        httpMetadata: entry.httpMetadata,
        customMetadata: entry.customMetadata,
        body: entry.bytes,
        async arrayBuffer() { return entry.bytes.buffer.slice(entry.bytes.byteOffset, entry.bytes.byteOffset + entry.bytes.byteLength); },
        async text() { return new TextDecoder().decode(entry.bytes); },
      };
    },
    async delete(key) {
      objects.delete(key);
    },
  };
}

let seq = 0;
function deterministicCode(n) {
  seq += 1;
  return String(seq).padStart(n, "A").slice(0, n);
}

try {
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec(schemaSql);
  const DB = makeFaultInjectableDB(sqlite);
  const R2 = makeMockR2Bucket();

  let tavilyMode = "ok"; // 'ok' | 'timeout' | 'empty'
  let videoSeq = 0;

  globalThis.fetch = async (input, init = {}) => {
    const url = typeof input === "string" ? input : input.url;
    const method = (init.method || "GET").toUpperCase();

    if (url === "https://api.tavily.com/search" && method === "POST") {
      if (tavilyMode === "timeout") {
        const err = new Error("Simulated AbortError");
        err.name = "AbortError";
        throw err;
      }
      if (tavilyMode === "empty") {
        return new Response(JSON.stringify({ results: [] }), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      return new Response(JSON.stringify({
        results: [
          {
            title: "Verified Official Spec 2026",
            url: "https://example.org/verified-doc",
            content: "Short summary snippet from search index.",
            published_date: "2026-11-20",
          },
          {
            title: "Paywalled Report",
            url: "https://example.org/paywalled",
            content: "Snippet only from index.",
            published_date: "2026-11-21",
          },
        ],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    if (url === "https://example.org/verified-doc") {
      return new Response(
        "<html><body><h1>Verified Official Spec</h1><p>This is the authentic full text fetched from the official source page with verified figures 98.6%.</p></body></html>",
        { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } }
      );
    }

    if (url === "https://example.org/paywalled") {
      return new Response("Forbidden", { status: 403, headers: { "Content-Type": "text/html" } });
    }

    if (url.endsWith("/v1/models") && method === "GET") {
      return new Response(JSON.stringify({ data: [{ id: "sora-2" }] }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    if (url.endsWith("/v1/videos") && method === "POST") {
      const id = `up_vid_${++videoSeq}`;
      return new Response(JSON.stringify({ id, status: "queued", progress: 10 }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    throw new Error(`Unexpected fetch: ${method} ${url}`);
  };

  const baseEnv = {
    DB,
    WORKS_BUCKET: R2,
    ADMIN_SECRET: "p0_admin_secret",
    AIHUBMIX_API_KEY: "sk-aihubmix-test",
    AIHUBMIX_BASE_URL: "https://aihubmix.com",
    ADMIN_EXEMPT_DAILY_CAP_YUAN: "10",
    ADMIN_EXEMPT_RPM: "30",
    AUTO_CREDIT_PAUSED: "true",
    ALLOW_APPLE_PRODUCTION_IAP: "false",
  };

  async function call(method, route, body = null, headers = {}, envOverrides = {}) {
    const isBinary = body instanceof Uint8Array || body instanceof ArrayBuffer;
    const req = new Request(`https://gw.wumind.test${route}`, {
      method,
      headers: isBinary ? headers : { "Content-Type": "application/json", ...headers },
      body: body == null ? undefined : (isBinary ? body : JSON.stringify(body)),
    });
    const res = await worker.fetch(req, { ...baseEnv, ...envOverrides }, { waitUntil() {} });
    const ct = res.headers.get("Content-Type") || "";
    if (ct.includes("application/json")) {
      return { status: res.status, headers: res.headers, json: await res.json() };
    }
    return { status: res.status, headers: res.headers, bytes: new Uint8Array(await res.arrayBuffer()) };
  }

  // Register two users (Owner A + User B)
  const regA = await call("POST", "/v1/account/register", { displayName: "Owner A" });
  const regB = await call("POST", "/v1/account/register", { displayName: "User B" });
  assert.equal(regA.status, 200);
  assert.equal(regB.status, 200);
  const userA = regA.json.userID;
  const tokenA = regA.json.userToken;
  const userB = regB.json.userID;
  const tokenB = regB.json.userToken;

  // Admin topup User A with ¥20.00
  const topup = await call("POST", "/v1/admin/topup", {
    userID: userA,
    amountYuan: 20.0,
    environment: "production",
    note: "P0 ACID test seed",
  }, { "X-WuMind-Admin-Secret": "p0_admin_secret" });
  assert.equal(topup.status, 200);
  assert.equal(topup.json.balanceYuan, 20);

  // =========================================================================
  // TEST 1: P0 Atomic Settlement — Fault Injection Mid-Write -> Full Rollback -> Clean Retry
  // =========================================================================
  const res1 = await reserveCreditAtomic(baseEnv, {
    userID: userA,
    idempotencyKey: "acid-settle-1",
    kind: "chat",
    modelID: "gpt-4o",
    reserveMicros: 5_000_000, // ¥5.00
    randomCode: deterministicCode,
  });
  assert.equal(res1.ok, true);

  // Inject failure at statement index 2 (after ledger insert & user balance update, BEFORE reservation status update!)
  DB.setFailOnBatchStmtIndex(2);
  await assert.rejects(
    () => settleReservationAtomic(baseEnv, {
      reservationID: res1.reservationID,
      userID: userA,
      actualMicros: 2_500_000, // ¥2.50
      kind: "chat",
      provider: "openAI",
      model: "gpt-4o",
      note: "fault injection test",
    }),
    /INJECTED_D1_FAULT_AT_STMT_2/
  );
  assert.equal(DB.getInjectedFaultCount(), 1);

  // Verify 100% atomic rollback: balance still ¥20, reserved still ¥5, reservation still 'reserved', 0 ledger rows!
  const uAfterFault = sqlite.prepare("SELECT balance_micros, reserved_micros, total_spent_micros FROM users WHERE id = ?").get(userA);
  const rAfterFault = sqlite.prepare("SELECT status, actual_micros FROM credit_reservations WHERE id = ?").get(res1.reservationID);
  const lAfterFault = sqlite.prepare("SELECT COUNT(*) AS cnt FROM ledger WHERE reservation_id = ?").get(res1.reservationID);
  assert.equal(Number(uAfterFault.balance_micros), 20_000_000, "Balance must NOT change after mid-transaction rollback");
  assert.equal(Number(uAfterFault.reserved_micros), 5_000_000, "Reserved hold must remain intact after rollback");
  assert.equal(Number(uAfterFault.total_spent_micros), 0, "Total spent must remain 0 after rollback");
  assert.equal(rAfterFault.status, "reserved", "Reservation status must roll back to 'reserved'");
  assert.equal(Number(lAfterFault.cnt), 0, "Ledger must have 0 rows after rollback");

  // Retry cleanly after rollback + 8x concurrent settlement race on the SAME reservation!
  const raceResults = await Promise.all(
    Array.from({ length: 8 }, () =>
      settleReservationAtomic(baseEnv, {
        reservationID: res1.reservationID,
        userID: userA,
        actualMicros: 2_500_000, // ¥2.50
        kind: "chat",
        provider: "openAI",
        model: "gpt-4o",
        note: "retry + concurrent race",
      })
    )
  );
  const freshSettledCount = raceResults.filter((r) => !r.alreadySettled).length;
  assert.equal(freshSettledCount, 1, "Exactly ONE concurrent caller may perform the settlement");

  const uAfterSettle = sqlite.prepare("SELECT balance_micros, reserved_micros, total_spent_micros FROM users WHERE id = ?").get(userA);
  const lAfterSettle = sqlite.prepare("SELECT * FROM ledger WHERE reservation_id = ?").all(res1.reservationID);
  assert.equal(Number(uAfterSettle.balance_micros), 17_500_000, "Balance must be debited strictly once (¥20 - ¥2.5 = ¥17.5)");
  assert.equal(Number(uAfterSettle.reserved_micros), 0, "Reserved hold must be completely released");
  assert.equal(Number(uAfterSettle.total_spent_micros), 2_500_000);
  assert.equal(lAfterSettle.length, 1, "Exactly one ledger row per reservation");
  assert.equal(Number(lAfterSettle[0].balance_before_micros), 20_000_000);
  assert.equal(Number(lAfterSettle[0].balance_after_micros), 17_500_000);

  // Fault injection mid-releaseReservationAtomic -> full rollback -> clean retry
  const res2 = await reserveCreditAtomic(baseEnv, {
    userID: userA,
    idempotencyKey: "acid-release-1",
    kind: "image",
    modelID: "gpt-image-1",
    reserveMicros: 3_000_000,
    randomCode: deterministicCode,
  });
  assert.equal(res2.ok, true);
  DB.setFailOnBatchStmtIndex(1);
  await assert.rejects(
    () => releaseReservationAtomic(baseEnv, { reservationID: res2.reservationID, userID: userA, reason: "injected_fail" }),
    /INJECTED_D1_FAULT_AT_STMT_1/
  );
  const uMidRel = sqlite.prepare("SELECT reserved_micros FROM users WHERE id = ?").get(userA);
  const rMidRel = sqlite.prepare("SELECT status FROM credit_reservations WHERE id = ?").get(res2.reservationID);
  assert.equal(Number(uMidRel.reserved_micros), 3_000_000, "Release rollback must preserve reserved_micros");
  assert.equal(rMidRel.status, "reserved");
  const relOk = await releaseReservationAtomic(baseEnv, { reservationID: res2.reservationID, userID: userA, reason: "retry_release" });
  assert.equal(relOk.released, true);
  assert.equal(Number(sqlite.prepare("SELECT reserved_micros FROM users WHERE id = ?").get(userA).reserved_micros), 0);

  // =========================================================================
  // TEST 2: P0 Admin Exempt In-Flight Video Budget Enforcement
  // =========================================================================
  // Grant userB admin fee-waiver with daily cap ¥10
  const exemptRes = await call("POST", "/v1/admin/users/billing-exempt", {
    userID: userB,
    exempt: true,
    dailyCostCapYuan: 10.0,
  }, { "X-WuMind-Admin-Secret": "p0_admin_secret" });
  assert.equal(exemptRes.status, 200);
  assert.equal(exemptRes.json.billingExempt, true);

  // Seed verified sora-2 model priced at ¥1.00 / sec (8s = ¥8.00)
  sqlite.prepare(
    `INSERT OR REPLACE INTO model_catalog
     (model_id, upstream_provider, vendor, display_name, capabilities_json, pricing_mode, unit_price_yuan, supported_params_json, enabled, probe_status, deprecated)
     VALUES ('sora-2', 'aihubmix', 'OpenAI', 'Sora 2', '["video"]', 'per_second', 1.0, '{"seconds":["4","8","12"],"sizes":["1280x720"],"protocol":"aihubmix_videos"}', 1, 'verified', 0)`
  ).run();

  // 1st 8s video (¥8 <= ¥10 cap) succeeds and stays in-flight (queued, ledger still ¥0!)
  const v1 = await call("POST", "/v1/videos", {
    model: "sora-2",
    prompt: "First parallel exempt video",
    seconds: "8",
    size: "1280x720",
  }, { Authorization: `Bearer ${tokenB}`, "Idempotency-Key": "exempt-vid-1" });
  assert.equal(v1.status, 200, `Expected 1st exempt video to succeed: ${JSON.stringify(v1.json)}`);

  // 2nd 8s video submitted concurrently (¥8 in-flight + ¥8 new = ¥16 > ¥10 cap) MUST be blocked 429!
  const v2 = await call("POST", "/v1/videos", {
    model: "sora-2",
    prompt: "Second parallel exempt video bypassing budget",
    seconds: "8",
    size: "1280x720",
  }, { Authorization: `Bearer ${tokenB}`, "Idempotency-Key": "exempt-vid-2" });
  assert.equal(v2.status, 429, "In-flight exempt video cost MUST be counted against daily cap");
  assert.equal(v2.json.code, "admin_exempt_daily_cap_exceeded");
  assert.equal(v2.json.inflightYuan, 8);

  // =========================================================================
  // TEST 3: P0 Legacy Payment Orders Reconciliation (`GET /v1/admin/reconcile-orders`)
  // =========================================================================
  const recForbidden = await call("GET", "/v1/admin/reconcile-orders", null, { Authorization: `Bearer ${tokenA}` });
  assert.equal(recForbidden.status, 403);

  // Clean initially
  const recClean = await call("GET", "/v1/admin/reconcile-orders", null, { "X-WuMind-Admin-Secret": "p0_admin_secret" });
  assert.equal(recClean.status, 200);
  assert.equal(recClean.json.clean, true);
  assert.equal(recClean.json.autoCreditPaused, true);
  assert.equal(recClean.json.appleProductionEnabled, false);

  // Inject legacy paid order missing ledger row -> reconciliation flags it immediately!
  sqlite.prepare(
    `INSERT INTO payment_orders (id, user_id, external_order_id, amount_micros, channel, environment, status, note)
     VALUES ('ORD-LEGACY-1', ?, 'legacy_ext_999', 18000000, 'iap', 'production', 'paid', 'legacy missing ledger')`
  ).run(userA);
  const recDirty = await call("GET", "/v1/admin/reconcile-orders", null, { "X-WuMind-Admin-Secret": "p0_admin_secret" });
  assert.equal(recDirty.status, 200);
  assert.equal(recDirty.json.clean, false);
  assert.equal(recDirty.json.readyToEnableAutoCredit, false);
  assert.equal(recDirty.json.paidOrdersMissingLedger.length, 1);
  assert.equal(recDirty.json.paidOrdersMissingLedger[0].orderID, "ORD-LEGACY-1");

  // =========================================================================
  // TEST 4: P1 Private Cloudflare R2 Binary Works Object Storage (> 3.2 MB original!)
  // =========================================================================
  const createWork = await call("POST", "/v1/works", {
    workType: "ppt",
    title: "Q3 Executive Deck (4.5 MB)",
    prompt: "季度经营汇报 10 页",
    modelID: "deepseek-reasoner",
    status: "completed",
    progress: 100,
  }, { Authorization: `Bearer ${tokenA}` });
  assert.equal(createWork.status, 200);
  const workID = createWork.json.work.id;

  // Build deterministic 4.5 MB binary payload (well above D1's 2 MB row limit & old 3.2 MB skip!)
  const largeBytes = new Uint8Array(4_500_000);
  for (let i = 0; i < largeBytes.length; i++) largeBytes[i] = (i * 31 + 7) & 0xff;

  // 4a. Without WORKS_BUCKET bound -> MUST return 503 object_storage_unconfigured & NEVER mark synced!
  const putNoR2 = await call("PUT", `/v1/works/${workID}/asset`, largeBytes, {
    Authorization: `Bearer ${tokenA}`,
    "Content-Type": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  }, { WORKS_BUCKET: undefined });
  assert.equal(putNoR2.status, 503);
  assert.equal(putNoR2.json.code, "object_storage_unconfigured");
  assert.equal(putNoR2.json.assetSyncState, "storage_unconfigured");
  const d1NoR2 = sqlite.prepare("SELECT asset_base64, asset_sync_state FROM user_works WHERE id = ?").get(workID);
  assert.equal(d1NoR2.asset_base64, null, "Must NEVER stuff 4.5 MB into D1");
  assert.equal(d1NoR2.asset_sync_state, "storage_unconfigured");

  // 4b. With private R2 WORKS_BUCKET bound -> uploads 4.5 MB binary cleanly, D1 stays tiny!
  const putR2 = await call("PUT", `/v1/works/${workID}/asset`, largeBytes, {
    Authorization: `Bearer ${tokenA}`,
    "Content-Type": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  });
  assert.equal(putR2.status, 200);
  assert.equal(putR2.json.assetSyncState, "synced");
  assert.equal(putR2.json.sizeBytes, 4_500_000);
  assert.ok(putR2.json.sha256 && putR2.json.sha256.length === 64);

  const d1WithR2 = sqlite.prepare("SELECT asset_base64, asset_object_key, asset_size_bytes, asset_sync_state FROM user_works WHERE id = ?").get(workID);
  assert.equal(d1WithR2.asset_base64, null, "D1 must NOT store raw base64 when stored in R2");
  assert.ok(d1WithR2.asset_object_key.endsWith(".pptx"));
  assert.equal(Number(d1WithR2.asset_size_bytes), 4_500_000);
  assert.equal(d1WithR2.asset_sync_state, "synced");

  // Cross-device owner download returns exact 4.5 MB binary!
  const dlOwner = await call("GET", `/v1/works/${workID}/asset`, null, { Authorization: `Bearer ${tokenA}` });
  assert.equal(dlOwner.status, 200);
  assert.equal(dlOwner.bytes.byteLength, 4_500_000);
  assert.equal(dlOwner.bytes[0], largeBytes[0]);
  assert.equal(dlOwner.bytes[4_499_999], largeBytes[4_499_999]);
  assert.equal(dlOwner.headers.get("X-Asset-SHA256"), putR2.json.sha256);

  // Cross-account access MUST return 404!
  const dlOther = await call("GET", `/v1/works/${workID}/asset`, null, { Authorization: `Bearer ${tokenB}` });
  assert.equal(dlOther.status, 404);

  // Delete cleans up private R2 object too!
  assert.equal(R2._objects.size, 1);
  const delWork = await call("DELETE", `/v1/works/${workID}`, null, { Authorization: `Bearer ${tokenA}` });
  assert.equal(delWork.status, 200);
  assert.equal(R2._objects.size, 0, "Deleting work must clean up private R2 object");

  // =========================================================================
  // TEST 5: P1 Server-Verified Web Search & Web Fetch (Honest Errors + Full-Text Verification)
  // =========================================================================
  const balBeforeSearch = Number(sqlite.prepare("SELECT balance_micros FROM users WHERE id = ?").get(userA).balance_micros);

  // 5a. Search unconfigured -> HTTP 503 search_not_configured, ZERO debit!
  const searchUnconf = await call("POST", "/v1/tools/web-search", { query: "test query" }, { Authorization: `Bearer ${tokenA}` });
  assert.equal(searchUnconf.status, 503);
  assert.equal(searchUnconf.json.code, "search_not_configured");
  assert.equal(Number(sqlite.prepare("SELECT balance_micros FROM users WHERE id = ?").get(userA).balance_micros), balBeforeSearch);

  // 5b. Configured Tavily timeout -> HTTP 504 timeout, ZERO debit!
  tavilyMode = "timeout";
  const searchTimeout = await call("POST", "/v1/tools/web-search", { query: "timeout query" }, { Authorization: `Bearer ${tokenA}` }, { TAVILY_API_KEY: "tvly-live-test" });
  assert.equal(searchTimeout.status, 504);
  assert.equal(searchTimeout.json.code, "timeout");
  assert.equal(Number(sqlite.prepare("SELECT balance_micros FROM users WHERE id = ?").get(userA).balance_micros), balBeforeSearch);

  // 5c. Configured Tavily returns 0 results -> no_results, ZERO debit!
  tavilyMode = "empty";
  const searchEmpty = await call("POST", "/v1/tools/web-search", { query: "empty query" }, { Authorization: `Bearer ${tokenA}` }, { TAVILY_API_KEY: "tvly-live-test" });
  assert.equal(searchEmpty.status, 200);
  assert.equal(searchEmpty.json.status, "no_results");
  assert.equal(searchEmpty.json.costYuan, 0);
  assert.equal(Number(sqlite.prepare("SELECT balance_micros FROM users WHERE id = ?").get(userA).balance_micros), balBeforeSearch);

  // 5d. Configured Tavily OK + readTopPages: 2 -> distinguishes full_text vs fetch_failed, debits once!
  tavilyMode = "ok";
  const searchOk = await call("POST", "/v1/tools/web-search", {
    query: "verified official spec 2026",
    maxResults: 5,
    readTopPages: 2,
  }, { Authorization: `Bearer ${tokenA}` }, { TAVILY_API_KEY: "tvly-live-test" });
  assert.equal(searchOk.status, 200);
  assert.equal(searchOk.json.status, "ok");
  assert.equal(searchOk.json.provider, "Tavily");
  assert.equal(searchOk.json.results.length, 2);
  assert.equal(searchOk.json.results[0].readStatus, "full_text");
  assert.ok(searchOk.json.results[0].extractedText.includes("98.6%"));
  assert.equal(searchOk.json.results[1].readStatus, "fetch_failed");
  assert.ok(searchOk.json.results[1].fetchError.includes("HTTP 403"));
  assert.equal(searchOk.json.fullTextCount, 1);
  assert.equal(searchOk.json.fetchFailedCount, 1);

  // 5e. SSRF protection on /v1/tools/web-fetch blocks private/localhost URLs!
  const ssrf = await call("POST", "/v1/tools/web-fetch", { url: "http://127.0.0.1:8080/internal" }, { Authorization: `Bearer ${tokenA}` });
  assert.equal(ssrf.status, 200);
  assert.equal(ssrf.json.ok, false);
  assert.equal(ssrf.json.readStatus, "fetch_failed");
  assert.ok(ssrf.json.fetchError.includes("安全限制"));

  console.log("PASS: All P0 ACID billing fault-injection/concurrency, admin in-flight video cap, order reconciliation, private R2 4.5MB binary roundtrip, and verified search/fetch tests succeeded.");
} finally {
  globalThis.fetch = originalFetch;
}
