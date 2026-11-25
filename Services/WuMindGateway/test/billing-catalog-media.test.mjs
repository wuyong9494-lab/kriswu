#!/usr/bin/env node
/**
 * Comprehensive Automated Verification Suite for WUMIND Commercial Gateway:
 *  1. Non-destructive in-place D1 schema upgrade (preserves existing users/balances/ledger)
 *  2. StoreKit 2 appAccountToken ownership enforcement & App Store Server Notifications V2 (REFUND / REVOKE)
 *  3. Billing Safety: pre-request atomic reservation -> post-result settlement -> failure/disconnect release,
 *     zero-balance / low-balance / concurrency / idempotency / upstream-error / mid-stream-disconnect / max_tokens cap
 *  4. Admin user lookup (`WM-`) & manual credit (`给用户加余额`): auth 403, single/daily caps, idempotency,
 *     audit log, and strict separation of `admin_granted_micros` vs `purchased_recharged_micros`
 *  5. Dynamic Model Catalog: provider discovery, live probe (chat / text_to_image / image_edit / video / 403 / 404),
 *     pricing/verification enable guardrails, capability-filtered public catalog, deprecation auto-disable
 *  6. Managed Image Reference Editing (`multipart/form-data /v1/images/edits` + T2I-only refusal) &
 *     Managed Video Generation (`sora-2` 4/8/12s validation, submit, poll settle/release, MP4 ftyp streaming)
 */
import assert from "node:assert/strict";
import { execSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import worker from "../src/index.js";
import { wumindAccountUUID } from "../src/billing-safety.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const schemaSql = fs.readFileSync(path.join(__dirname, "..", "schema.sql"), "utf8");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "wumind-billing-suite-"));

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

function makeAppleChain(prefix) {
  const dir = path.join(tmp, prefix);
  fs.mkdirSync(dir, { recursive: true });
  const run = (c) => execSync(c, { cwd: dir, stdio: "pipe" });

  fs.writeFileSync(path.join(dir, "root.cnf"), `
[req]
distinguished_name = dn
x509_extensions = v3_ca
prompt = no
[dn]
CN = Test Apple Root CA - G3 (${prefix})
O = Apple Inc.
[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
`);
  run("openssl ecparam -name secp384r1 -genkey -noout -out root.key");
  run("openssl req -new -x509 -key root.key -sha384 -days 3650 -config root.cnf -out root.pem");
  run("openssl x509 -in root.pem -outform DER -out root.der");

  fs.writeFileSync(path.join(dir, "inter.cnf"), `
[req]
distinguished_name = dn
prompt = no
[dn]
CN = Test Apple WWDR G6 (${prefix})
O = Apple Inc.
[v3_inter]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
1.2.840.113635.100.6.2.1 = DER:05:00
`);
  run("openssl ecparam -name prime256v1 -genkey -noout -out inter.key");
  run("openssl req -new -key inter.key -config inter.cnf -out inter.csr");
  run("openssl x509 -req -in inter.csr -CA root.pem -CAkey root.key -CAcreateserial -sha384 -days 1825 -extfile inter.cnf -extensions v3_inter -out inter.pem");
  run("openssl x509 -in inter.pem -outform DER -out inter.der");

  fs.writeFileSync(path.join(dir, "leaf.cnf"), `
[req]
distinguished_name = dn
prompt = no
[dn]
CN = Test App Store Signing (${prefix})
O = Apple Inc.
[v3_leaf]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
1.2.840.113635.100.6.11.1 = DER:05:00
`);
  run("openssl ecparam -name prime256v1 -genkey -noout -out leaf.key");
  run("openssl req -new -key leaf.key -config leaf.cnf -out leaf.csr");
  run("openssl x509 -req -in leaf.csr -CA inter.pem -CAkey inter.key -CAcreateserial -sha256 -days 365 -extfile leaf.cnf -extensions v3_leaf -out leaf.pem");
  run("openssl x509 -in leaf.pem -outform DER -out leaf.der");

  const rootDer = fs.readFileSync(path.join(dir, "root.der"));
  const interDer = fs.readFileSync(path.join(dir, "inter.der"));
  const leafDer = fs.readFileSync(path.join(dir, "leaf.der"));
  const leafKeyPem = fs.readFileSync(path.join(dir, "leaf.key"), "utf8");
  return {
    x5c: [leafDer.toString("base64"), interDer.toString("base64"), rootDer.toString("base64")],
    leafKeyPem,
    rootSha256: crypto.createHash("sha256").update(rootDer).digest("hex"),
  };
}

function b64u(buf) {
  return Buffer.from(buf).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function signJWS(chain, payload) {
  const h = b64u(JSON.stringify({ alg: "ES256", x5c: chain.x5c }));
  const p = b64u(JSON.stringify(payload));
  const sig = crypto.sign("sha256", Buffer.from(`${h}.${p}`), {
    key: chain.leafKeyPem,
    dsaEncoding: "ieee-p1363",
  });
  return `${h}.${p}.${b64u(sig)}`;
}

// Tiny valid 1x1 PNG base64
const TINY_PNG_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2dIAAAAASUVORK5CYII=";
// Valid minimal MP4 header with 'ftypisom' box
const FAKE_MP4_BYTES = new Uint8Array([
  0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, // size=24, "ftyp"
  0x69, 0x73, 0x6f, 0x6d, 0x00, 0x00, 0x02, 0x00, // "isom"
  0x69, 0x73, 0x6f, 0x6d, 0x69, 0x73, 0x6f, 0x32,
  0x00, 0x00, 0x00, 0x08, 0x6d, 0x64, 0x61, 0x74, // "mdat"
]);

const originalFetch = globalThis.fetch;

try {
  // =========================================================================
  // 1. Non-destructive in-place D1 schema upgrade test (legacy DB preserved!)
  // =========================================================================
  {
    const legacySql = new DatabaseSync(":memory:");
    legacySql.exec(`
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        token_hash TEXT UNIQUE NOT NULL,
        display_name TEXT NOT NULL DEFAULT '',
        balance_micros INTEGER NOT NULL DEFAULT 0,
        sandbox_balance_micros INTEGER NOT NULL DEFAULT 0,
        sandbox_recharged_micros INTEGER NOT NULL DEFAULT 0,
        total_recharged_micros INTEGER NOT NULL DEFAULT 0,
        total_spent_micros INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      CREATE TABLE config (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL DEFAULT (datetime('now')));
      CREATE TABLE ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        provider TEXT NOT NULL DEFAULT '',
        model TEXT NOT NULL DEFAULT '',
        prompt_tokens INTEGER NOT NULL DEFAULT 0,
        completion_tokens INTEGER NOT NULL DEFAULT 0,
        reasoning_tokens INTEGER NOT NULL DEFAULT 0,
        cost_micros INTEGER NOT NULL DEFAULT 0,
        balance_after_micros INTEGER NOT NULL DEFAULT 0,
        note TEXT NOT NULL DEFAULT '',
        external_order_id TEXT UNIQUE,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      INSERT INTO users (id, token_hash, display_name, balance_micros, total_recharged_micros)
      VALUES ('WM-LEGACY1', 'legacy_hash_123', 'OldUser', 12340000, 12340000);
    `);
    const legacyDB = makeDB(legacySql);
    const res = await worker.fetch(
      new Request("https://gw.wumind.test/v1/public/config", { method: "GET" }),
      { DB: legacyDB, ADMIN_SECRET: "sec" },
      { waitUntil() {} }
    );
    assert.equal(res.status, 200);
    const preserved = legacySql.prepare("SELECT id, balance_micros, reserved_micros, admin_granted_micros, purchased_recharged_micros FROM users WHERE id = 'WM-LEGACY1'").get();
    assert.equal(preserved.balance_micros, 12340000, "Existing balance MUST be preserved untouched");
    assert.equal(preserved.reserved_micros, 0);
    assert.equal(preserved.admin_granted_micros, 0);
    assert.equal(preserved.purchased_recharged_micros, 0);
    const tables = legacySql.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map((r) => r.name);
    for (const reqTable of ["credit_reservations", "admin_credit_audit", "model_catalog", "video_jobs"]) {
      assert.ok(tables.includes(reqTable), `Legacy DB auto-upgrade must create ${reqTable}`);
    }
  }

  // =========================================================================
  // Shared fresh D1 database + mock upstream fetch for full end-to-end suite
  // =========================================================================
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec(schemaSql);
  const DB = makeDB(sqlite);
  const appleChain = makeAppleChain("apple_prod_test");

  const upstreamCalls = [];
  let mockCatalogModels = [
    { id: "gpt-4o" },
    { id: "deepseek-reasoner" },
    { id: "gpt-image-1" },
    { id: "imagen-3.0-generate-002" },
    { id: "sora-2" },
    { id: "permission-denied-chat" },
    { id: "deprecated-chat" },
  ];
  let nextChatBehavior = "ok"; // "ok" | "http500" | "disconnect_empty" | "disconnect_partial"
  let nextImageBehavior = "ok"; // "ok" | "http500"
  let mockVideoStates = new Map();
  let mockVideoCounter = 0;

  globalThis.fetch = async (input, init = {}) => {
    const url = typeof input === "string" ? input : input.url;
    const method = (init.method || "GET").toUpperCase();
    upstreamCalls.push({ url, method, headers: init.headers, body: init.body });

    // 1. Dynamic model catalog discovery
    if (url.endsWith("/v1/models") && method === "GET") {
      return new Response(JSON.stringify({ object: "list", data: mockCatalogModels }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 2. Chat completions (both probe & live requests)
    if (url.endsWith("/v1/chat/completions") && method === "POST") {
      const payload = JSON.parse(String(init.body || "{}"));
      if (payload.model === "permission-denied-chat") {
        return new Response(JSON.stringify({ error: { message: "API key does not have permission for model permission-denied-chat" } }), { status: 403 });
      }
      if (payload.model === "deprecated-chat") {
        return new Response(JSON.stringify({ error: { message: "model_not_found: deprecated-chat has been deprecated" } }), { status: 404 });
      }
      // Non-streaming probe
      if (payload.stream === false) {
        return new Response(JSON.stringify({
          id: "chatcmpl-probe",
          choices: [{ message: { role: "assistant", content: "ok" } }],
          usage: { prompt_tokens: 4, completion_tokens: 1 },
        }), { status: 200, headers: { "Content-Type": "application/json" } });
      }

      if (nextChatBehavior === "http500") {
        nextChatBehavior = "ok";
        return new Response(JSON.stringify({ error: { message: "upstream overloaded" } }), { status: 500 });
      }
      if (nextChatBehavior === "disconnect_empty") {
        nextChatBehavior = "ok";
        const stream = new ReadableStream({
          start(controller) {
            controller.error(new Error("socket hang up before first token"));
          },
        });
        return new Response(stream, { status: 200, headers: { "Content-Type": "text/event-stream" } });
      }
      if (nextChatBehavior === "disconnect_partial") {
        nextChatBehavior = "ok";
        const enc = new TextEncoder();
        let step = 0;
        const stream = new ReadableStream({
          pull(controller) {
            if (step === 0) {
              step++;
              controller.enqueue(enc.encode(`data: ${JSON.stringify({ choices: [{ delta: { content: "局部回答内容" } }] })}\n\n`));
            } else {
              controller.error(new Error("mid-stream disconnect"));
            }
          },
        });
        return new Response(stream, { status: 200, headers: { "Content-Type": "text/event-stream" } });
      }

      // Normal SSE streaming response with usage
      const enc = new TextEncoder();
      const chunks = [
        `data: ${JSON.stringify({ choices: [{ delta: { content: "你好，这是真实流式回复。" } }] })}\n\n`,
        `data: ${JSON.stringify({ choices: [], usage: { prompt_tokens: 120, completion_tokens: 80 } })}\n\n`,
        "data: [DONE]\n\n",
      ];
      const stream = new ReadableStream({
        start(controller) {
          for (const c of chunks) controller.enqueue(enc.encode(c));
          controller.close();
        },
      });
      return new Response(stream, { status: 200, headers: { "Content-Type": "text/event-stream" } });
    }

    // 3. Image edits (multipart/form-data)
    if (url.endsWith("/v1/images/edits") && method === "POST") {
      assert.ok(init.body instanceof FormData, "/v1/images/edits MUST send real multipart FormData");
      const modelField = init.body.get("model");
      const imageField = init.body.get("image");
      assert.ok(imageField && typeof imageField.arrayBuffer === "function", "FormData must include binary image file part");
      if (nextImageBehavior === "http500") {
        nextImageBehavior = "ok";
        return new Response(JSON.stringify({ error: { message: "image edit worker failed" } }), { status: 500 });
      }
      return new Response(JSON.stringify({
        created: Date.now(),
        data: [{ b64_json: TINY_PNG_B64, mime_type: "image/png" }],
        model: modelField,
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    // 4. Image generations (JSON)
    if (url.endsWith("/v1/images/generations") && method === "POST") {
      if (nextImageBehavior === "http500") {
        nextImageBehavior = "ok";
        return new Response(JSON.stringify({ error: { message: "upstream image outage" } }), { status: 500 });
      }
      // Small delay to make concurrency race realistic
      await new Promise((r) => setTimeout(r, 25));
      return new Response(JSON.stringify({
        created: Date.now(),
        data: [{ b64_json: TINY_PNG_B64, mime_type: "image/jpeg" }],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    // 5. Video creation (/v1/videos)
    if (url.endsWith("/v1/videos") && method === "POST") {
      const payload = JSON.parse(String(init.body || "{}"));
      // Probe dry-check sends empty prompt and expects HTTP 400 validation response
      if (!payload.prompt) {
        return new Response(JSON.stringify({ error: { message: "prompt is required" } }), { status: 400 });
      }
      assert.ok(["4", "8", "12"].includes(String(payload.seconds)), `Upstream Sora 2 only accepts 4/8/12s, got ${payload.seconds}`);
      const jobId = `vid_up_${++mockVideoCounter}`;
      mockVideoStates.set(jobId, {
        id: jobId,
        model: payload.model,
        status: "queued",
        progress: 10,
        seconds: String(payload.seconds),
        size: payload.size,
      });
      return new Response(JSON.stringify(mockVideoStates.get(jobId)), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 6. Video content download (/v1/videos/:id/content)
    if (/\/v1\/videos\/[^/]+\/content$/.test(url) && method === "GET") {
      return new Response(FAKE_MP4_BYTES, { status: 200, headers: { "Content-Type": "video/mp4" } });
    }

    // 7. Video status poll (/v1/videos/:id)
    if (/\/v1\/videos\/([^/]+)$/.test(url) && method === "GET") {
      const id = decodeURIComponent(url.match(/\/v1\/videos\/([^/]+)$/)[1]);
      const st = mockVideoStates.get(id);
      if (!st) return new Response(JSON.stringify({ error: { message: "not found" } }), { status: 404 });
      return new Response(JSON.stringify(st), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    throw new Error(`Unexpected upstream fetch in test: ${method} ${url}`);
  };

  const baseEnv = {
    DB,
    ADMIN_SECRET: "admin_secret_test_123",
    APPLE_BUNDLE_ID: "com.kriswu.shiftreminder",
    __TEST_TRUSTED_ROOT_SHA256: appleChain.rootSha256,
    AUTO_CREDIT_PAUSED: "false",
    ALLOW_APPLE_SANDBOX_TEST: "true",
    ALLOW_APPLE_PRODUCTION_IAP: "true",
    AIHUBMIX_API_KEY: "sk-aihubmix-live-mock-key",
    AIHUBMIX_BASE_URL: "https://aihubmix.com",
    AIHUBMIX_ALLOWED_MODELS: "gpt-4o",
    ADMIN_TOPUP_MAX_SINGLE_YUAN: "500",
    ADMIN_TOPUP_DAILY_CAP_YUAN: "600",
    CHAT_MAX_OUTPUT_TOKENS: "4096",
  };

  async function call(method, urlPath, body = null, headers = {}, envOverrides = {}) {
    const env = { ...baseEnv, ...envOverrides };
    const req = new Request(`https://gw.wumind.test${urlPath}`, {
      method,
      headers: { "Content-Type": "application/json", ...headers },
      body: body !== null ? JSON.stringify(body) : undefined,
    });
    const res = await worker.fetch(req, env, { waitUntil() {} });
    const ct = res.headers.get("Content-Type") || "";
    if (ct.includes("video/mp4")) {
      return { status: res.status, headers: res.headers, bytes: new Uint8Array(await res.arrayBuffer()) };
    }
    const text = await res.text();
    let data = null;
    try { data = JSON.parse(text); } catch { data = text; }
    return { status: res.status, headers: res.headers, data, rawText: text };
  }

  const adminHdr = { "X-WuMind-Admin-Secret": baseEnv.ADMIN_SECRET };

  // Register two users
  const regA = await call("POST", "/v1/account/register", { displayName: "Alice" });
  const regB = await call("POST", "/v1/account/register", { displayName: "Bob" });
  assert.equal(regA.status, 200);
  assert.equal(regB.status, 200);
  const userA = regA.data.userID;
  const userB = regB.data.userID;
  const authA = { Authorization: `Bearer ${regA.data.userToken}` };
  const authB = { Authorization: `Bearer ${regB.data.userToken}` };

  // =========================================================================
  // 2. StoreKit 2 appAccountToken Ownership & Refund/Revoke V2 Webhook
  // =========================================================================
  const uuidA = await wumindAccountUUID(userA);
  const uuidB = await wumindAccountUUID(userB);
  assert.notEqual(uuidA, uuidB);
  assert.match(uuidA, /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);

  const nowMs = Date.now();
  // 2a. Mismatched appAccountToken (Bob's UUID submitted on Alice's token) MUST be rejected 403!
  const wrongOwnerTx = signJWS(appleChain, {
    bundleId: "com.kriswu.shiftreminder",
    productId: "com.kriswu.wumind.credit.18",
    transactionId: "9000001001",
    originalTransactionId: "9000001001",
    type: "Consumable",
    environment: "Production",
    appAccountToken: uuidB,
    signedDate: nowMs,
  });
  const wrongOwnerRes = await call("POST", "/v1/iap/verify", {
    productID: "com.kriswu.wumind.credit.18",
    transactionID: "9000001001",
    jwsRepresentation: wrongOwnerTx,
  }, authA);
  assert.equal(wrongOwnerRes.status, 403);
  assert.equal(wrongOwnerRes.data.code, "account_ownership_mismatch");

  // 2b. Valid Production IAP with matching appAccountToken credits purchasedRechargedYuan (separate from adminGrantedYuan)
  const validProdTx = signJWS(appleChain, {
    bundleId: "com.kriswu.shiftreminder",
    productId: "com.kriswu.wumind.credit.18",
    transactionId: "9000001002",
    originalTransactionId: "9000001002",
    type: "Consumable",
    environment: "Production",
    appAccountToken: uuidA,
    signedDate: nowMs,
  });
  const prodOk = await call("POST", "/v1/iap/verify", {
    productID: "com.kriswu.wumind.credit.18",
    transactionID: "9000001002",
    jwsRepresentation: validProdTx,
  }, authA);
  assert.equal(prodOk.status, 200);
  assert.equal(prodOk.data.creditedYuan, 18);
  assert.equal(prodOk.data.balanceYuan, 18);

  // Duplicate delivery returns alreadyCredited=true without adding balance
  const prodDup = await call("POST", "/v1/iap/verify", {
    productID: "com.kriswu.wumind.credit.18",
    transactionID: "9000001002",
    jwsRepresentation: validProdTx,
  }, authA);
  assert.equal(prodDup.status, 200);
  assert.equal(prodDup.data.alreadyCredited, true);
  assert.equal(prodDup.data.balanceYuan, 18);

  const meAfterProd = await call("GET", "/v1/account/me", null, authA);
  assert.equal(meAfterProd.data.purchasedRechargedYuan, 18);
  assert.equal(meAfterProd.data.adminGrantedYuan, 0);

  // 2c. Valid Sandbox IAP credits ONLY sandboxBalanceYuan, NEVER Production balance
  const validSandboxTx = signJWS(appleChain, {
    bundleId: "com.kriswu.shiftreminder",
    productId: "com.kriswu.wumind.credit.6",
    transactionId: "8000001003",
    originalTransactionId: "8000001003",
    type: "Consumable",
    environment: "Sandbox",
    appAccountToken: uuidA,
    signedDate: nowMs,
  });
  const sbOk = await call("POST", "/v1/iap/verify", {
    productID: "com.kriswu.wumind.credit.6",
    transactionID: "8000001003",
    jwsRepresentation: validSandboxTx,
  }, authA);
  assert.equal(sbOk.status, 200);
  assert.equal(sbOk.data.isSandbox, true);
  assert.equal(sbOk.data.balanceYuan, 18);
  assert.equal(sbOk.data.sandboxBalanceYuan, 6);

  // 2d. App Store Server Notification V2 REVOKE for Sandbox claws back ONLY Sandbox balance
  const sandboxRevokeNotif = signJWS(appleChain, {
    notificationType: "REVOKE",
    notificationUUID: "notif-sb-1",
    signedDate: nowMs,
    data: {
      bundleId: "com.kriswu.shiftreminder",
      environment: "Sandbox",
      signedTransactionInfo: signJWS(appleChain, {
        bundleId: "com.kriswu.shiftreminder",
        transactionId: "8000001003",
        environment: "Sandbox",
        revocationReason: 0,
        signedDate: nowMs,
      }),
    },
  });
  const sbRevRes = await call("POST", "/v1/webhooks/apple-notifications", { signedPayload: sandboxRevokeNotif });
  assert.equal(sbRevRes.status, 200);
  assert.equal(sbRevRes.data.environment, "sandbox");
  assert.equal(sbRevRes.data.clawedBackYuan, 6);
  const meAfterSbRev = await call("GET", "/v1/account/me", null, authA);
  assert.equal(meAfterSbRev.data.sandboxBalanceYuan, 0);
  assert.equal(meAfterSbRev.data.balanceYuan, 18, "Sandbox revoke MUST NOT touch Production balance");

  // 2e. App Store Server Notification V2 REFUND for Production claws back Production balance (idempotently!)
  const prodRefundNotif = signJWS(appleChain, {
    notificationType: "REFUND",
    notificationUUID: "notif-prod-1",
    signedDate: nowMs,
    data: {
      bundleId: "com.kriswu.shiftreminder",
      environment: "Production",
      signedTransactionInfo: signJWS(appleChain, {
        bundleId: "com.kriswu.shiftreminder",
        transactionId: "9000001002",
        environment: "Production",
        revocationReason: 1,
        signedDate: nowMs,
      }),
    },
  });
  const prodRef1 = await call("POST", "/v1/webhooks/apple-notifications", { signedPayload: prodRefundNotif });
  assert.equal(prodRef1.status, 200);
  assert.equal(prodRef1.data.clawedBackYuan, 18);
  assert.equal(prodRef1.data.balanceAfterYuan, 0);
  const prodRefDup = await call("POST", "/v1/webhooks/apple-notifications", { signedPayload: prodRefundNotif });
  assert.equal(prodRefDup.status, 200);
  assert.equal(prodRefDup.data.alreadyProcessed, true);

  // =========================================================================
  // 3. Admin User Lookup (`WM-`) & Manual Balance Credit (`给用户加余额`)
  // =========================================================================
  // 3a. Normal user rejected with 403
  assert.equal((await call("GET", `/v1/admin/users/lookup?userID=${userA}`, null, authA)).status, 403);
  assert.equal((await call("POST", "/v1/admin/topup", { userID: userA, amountYuan: 10 }, authA)).status, 403);

  // 3b. Admin lookup ANY registered WM- user
  const lookupRes = await call("GET", `/v1/admin/users/lookup?userID=${userA}`, null, adminHdr);
  assert.equal(lookupRes.status, 200);
  assert.equal(lookupRes.data.found, true);
  assert.equal(lookupRes.data.user.userID, userA);
  assert.equal(lookupRes.data.user.purchasedRechargedYuan, 18);
  assert.equal(lookupRes.data.user.adminGrantedYuan, 0);

  // 3c. Single-grant cap enforced (> ¥500 rejected)
  const overSingle = await call("POST", "/v1/admin/topup", {
    userID: userA,
    amountYuan: 501,
    note: "超单笔上限测试",
  }, adminHdr);
  assert.equal(overSingle.status, 400);
  assert.equal(overSingle.data.code, "admin_single_limit_exceeded");

  // 3d. Valid admin manual credit with idempotency + separate accounting + audit trail
  const topup1 = await call("POST", "/v1/admin/topup", {
    userID: userA,
    amountYuan: 25,
    environment: "production",
    operatorID: "ops-kris",
    note: "客服人工补发额度",
    idempotencyKey: "adm-grant-001",
  }, adminHdr);
  assert.equal(topup1.status, 200);
  assert.equal(topup1.data.alreadyApplied, false);
  assert.equal(topup1.data.balanceBeforeYuan, 0);
  assert.equal(topup1.data.balanceAfterYuan, 25);
  assert.equal(topup1.data.adminGrantedYuan, 25);
  assert.equal(topup1.data.purchasedRechargedYuan, 18, "Admin grant MUST NOT inflate purchasedRechargedYuan!");

  // Replay with same idempotencyKey MUST NOT double-credit
  const topup1Dup = await call("POST", "/v1/admin/topup", {
    userID: userA,
    amountYuan: 25,
    environment: "production",
    operatorID: "ops-kris",
    note: "客服人工补发额度",
    idempotencyKey: "adm-grant-001",
  }, adminHdr);
  assert.equal(topup1Dup.status, 200);
  assert.equal(topup1Dup.data.alreadyApplied, true);
  assert.equal(topup1Dup.data.balanceYuan, 25);

  // Sandbox admin credit touches ONLY sandbox balance
  const sbTopup = await call("POST", "/v1/admin/topup", {
    userID: userA,
    amountYuan: 12,
    environment: "sandbox",
    operatorID: "ops-kris",
    note: "测试沙盒赠额",
    idempotencyKey: "adm-grant-sb-1",
  }, adminHdr);
  assert.equal(sbTopup.status, 200);
  assert.equal(sbTopup.data.balanceYuan, 25);
  assert.equal(sbTopup.data.sandboxBalanceYuan, 12);

  // Daily cap enforced (today already 25+12=37; +500=537 ok, then +100=637 > 600 cap -> 429)
  const nearCap = await call("POST", "/v1/admin/topup", {
    userID: userB,
    amountYuan: 500,
    environment: "production",
    idempotencyKey: "adm-grant-cap-1",
  }, adminHdr);
  assert.equal(nearCap.status, 200);
  const overDaily = await call("POST", "/v1/admin/topup", {
    userID: userB,
    amountYuan: 100,
    environment: "production",
    idempotencyKey: "adm-grant-cap-2",
  }, adminHdr);
  assert.equal(overDaily.status, 429);
  assert.equal(overDaily.data.code, "admin_daily_limit_exceeded");

  // Audit trail present on lookup & admin summary
  const lookupAfter = await call("GET", `/v1/admin/users/lookup?userID=${userA}`, null, adminHdr);
  assert.ok(lookupAfter.data.recentAdminCredits.length >= 2);
  assert.equal(lookupAfter.data.recentAdminCredits[0].operatorID, "ops-kris");
  const summaryRes = await call("GET", "/v1/admin/summary", null, adminHdr);
  assert.equal(summaryRes.status, 200);
  assert.ok(summaryRes.data.totalAdminGrantedYuan >= 525);
  assert.equal(summaryRes.data.totalPurchasedYuan, 18);

  // =========================================================================
  // 4. Dynamic Model Catalog Discovery, Probing, Pricing Guardrails & Capability Filtering
  // =========================================================================
  const discoverRes = await call("POST", "/v1/admin/models/discover", { providers: ["aihubmix"] }, adminHdr);
  assert.equal(discoverRes.status, 200);
  assert.equal(discoverRes.data.totalDiscovered, 7);

  // Newly discovered models MUST default to enabled=false & probeStatus='unverified' -> 0 public callable models!
  const pubBefore = await call("GET", "/v1/public/models");
  assert.equal(pubBefore.status, 200);
  assert.equal(pubBefore.data.count, 0, "Unverified/unpriced discovered models MUST NOT leak to user pages");

  // Guardrail: refuse enabling unverified model
  const rejectUnverified = await call("POST", "/v1/admin/models/batch-update", {
    updates: [{ id: "gpt-4o", inputPricePerMillion: 36, outputPricePerMillion: 144, enabled: true }],
  }, adminHdr);
  assert.equal(rejectUnverified.status, 400);
  assert.equal(rejectUnverified.data.rejected[0].code, "not_verified");

  // Probe all discovered models against live upstream endpoints
  const probeRes = await call("POST", "/v1/admin/models/probe", {
    modelIDs: ["gpt-4o", "gpt-image-1", "imagen-3.0-generate-002", "sora-2", "permission-denied-chat", "deprecated-chat"],
  }, adminHdr);
  assert.equal(probeRes.status, 200);
  const byId = Object.fromEntries(probeRes.data.results.map((r) => [r.id, r]));
  assert.equal(byId["gpt-4o"].probeStatus, "verified");
  assert.equal(byId["gpt-image-1"].probeStatus, "verified");
  assert.equal(byId["imagen-3.0-generate-002"].probeStatus, "verified");
  assert.equal(byId["sora-2"].probeStatus, "verified");
  assert.equal(byId["permission-denied-chat"].probeStatus, "permission_denied");
  assert.equal(byId["deprecated-chat"].probeStatus, "deprecated");
  assert.equal(byId["deprecated-chat"].deprecated, true);

  // Guardrail: refuse enabling verified-but-unpriced model
  const rejectUnpriced = await call("POST", "/v1/admin/models/batch-update", {
    updates: [{ id: "gpt-4o", inputPricePerMillion: 0, outputPricePerMillion: 0, enabled: true }],
  }, adminHdr);
  assert.equal(rejectUnpriced.status, 400);
  assert.equal(rejectUnpriced.data.rejected[0].code, "unpriced");

  // Price & batch-enable the 4 verified models (chat + image_edit + text_to_image-only + video)
  const enableRes = await call("POST", "/v1/admin/models/batch-update", {
    updates: [
      { id: "gpt-4o", displayName: "GPT-4o（已实测）", inputPricePerMillion: 36, outputPricePerMillion: 144, enabled: true },
      { id: "gpt-image-1", displayName: "GPT Image 1（支持参考图）", unitPriceYuan: 0.30, enabled: true },
      { id: "imagen-3.0-generate-002", displayName: "Imagen 3（纯文生图）", unitPriceYuan: 0.25, enabled: true },
      { id: "sora-2", displayName: "Sora 2（视频直出）", unitPriceYuan: 1.00, enabled: true },
    ],
  }, adminHdr);
  assert.equal(enableRes.status, 200);
  assert.equal(enableRes.data.appliedCount, 4);
  assert.equal(enableRes.data.rejectedCount, 0);

  // Verify capability-filtered user endpoints NEVER cross-contaminate pages!
  const chatModels = await call("GET", "/v1/public/models?capability=chat");
  assert.deepEqual(chatModels.data.models.map((m) => m.id), ["gpt-4o"]);
  const t2iModels = await call("GET", "/v1/public/models?capability=text_to_image");
  assert.deepEqual(t2iModels.data.models.map((m) => m.id).sort(), ["gpt-image-1", "imagen-3.0-generate-002"]);
  const editModels = await call("GET", "/v1/public/models?capability=image_edit");
  assert.deepEqual(editModels.data.models.map((m) => m.id), ["gpt-image-1"]);
  const videoModels = await call("GET", "/v1/public/models?capability=video");
  assert.deepEqual(videoModels.data.models.map((m) => m.id), ["sora-2"]);

  // =========================================================================
  // 5. Billing Safety: Zero Balance, Low Balance, Concurrency, Idempotency,
  //    Upstream Failure Release, Mid-Stream Disconnect, Server max_tokens Cap
  // =========================================================================
  const regZero = await call("POST", "/v1/account/register", { displayName: "ZeroUser" });
  const authZero = { Authorization: `Bearer ${regZero.data.userToken}` };
  const callsBeforeZero = upstreamCalls.length;

  // 5a. Zero balance -> 402 before touching upstream
  const zeroChat = await call("POST", "/v1/chat/completions", {
    model: "gpt-4o",
    messages: [{ role: "user", content: "hello" }],
  }, authZero);
  assert.equal(zeroChat.status, 402);
  assert.equal(zeroChat.data.code, "insufficient_balance");
  assert.equal(upstreamCalls.length, callsBeforeZero, "Zero-balance request MUST NOT invoke upstream");

  // 5b. Low balance:
  // (1) Balance below minimum safe turn reserve (¥0.01 < 256-token reserve ~¥0.037) -> 402 BEFORE calling upstream!
  sqlite.prepare("UPDATE users SET balance_micros = 10000, total_recharged_micros = 10000 WHERE id = ?").run(regZero.data.userID);
  const microChat = await call("POST", "/v1/chat/completions", {
    model: "gpt-4o",
    messages: [{ role: "user", content: "hello" }],
    max_tokens: 4096,
  }, authZero);
  assert.equal(microChat.status, 402);
  assert.equal(microChat.data.code, "insufficient_balance");
  assert.equal(upstreamCalls.length, callsBeforeZero, "Below-minimum balance MUST NOT invoke upstream");

  // (2) Tight balance (¥0.10): allows chat ONLY by dynamically capping max_tokens down from 4096 so it can NEVER overdraft!
  await call("POST", "/v1/admin/topup", {
    userID: regZero.data.userID,
    amountYuan: 0.10,
    environment: "production",
    idempotencyKey: "low-bal-seed",
  }, adminHdr);
  const tightChat = await call("POST", "/v1/chat/completions", {
    model: "gpt-4o",
    messages: [{ role: "user", content: "hello" }],
    max_tokens: 4096,
  }, authZero);
  assert.equal(tightChat.status, 200);
  const tightReqBody = JSON.parse(upstreamCalls.filter((c) => c.url.endsWith("/v1/chat/completions")).at(-1).body);
  assert.ok(tightReqBody.max_tokens < 800, `Tight ¥0.11 balance must dynamically cap max_tokens well below 4096, got ${tightReqBody.max_tokens}`);
  const tightMe = await call("GET", "/v1/account/me", null, authZero);
  assert.ok(tightMe.data.balanceYuan > 0 && tightMe.data.reservedYuan === 0);

  // 5c. Concurrency race: seed a user with ¥0.50, fire 3 concurrent ¥0.30 image requests -> ONLY 1 succeeds!
  const regRace = await call("POST", "/v1/account/register", { displayName: "RaceUser" });
  const authRace = { Authorization: `Bearer ${regRace.data.userToken}` };
  await call("POST", "/v1/admin/topup", {
    userID: regRace.data.userID,
    amountYuan: 0.50,
    environment: "production",
    idempotencyKey: "race-seed",
  }, adminHdr);
  const raceResults = await Promise.all([
    call("POST", "/v1/images/generations", { model: "gpt-image-1", prompt: "cat 1", n: 1 }, { ...authRace, "Idempotency-Key": "race-1" }),
    call("POST", "/v1/images/generations", { model: "gpt-image-1", prompt: "cat 2", n: 1 }, { ...authRace, "Idempotency-Key": "race-2" }),
    call("POST", "/v1/images/generations", { model: "gpt-image-1", prompt: "cat 3", n: 1 }, { ...authRace, "Idempotency-Key": "race-3" }),
  ]);
  const race200 = raceResults.filter((r) => r.status === 200);
  const race402 = raceResults.filter((r) => r.status === 402);
  assert.equal(race200.length, 1, "Exactly 1 concurrent ¥0.30 request can succeed on ¥0.50 balance");
  assert.equal(race402.length, 2, "The other 2 concurrent requests must fail with 402 insufficient_balance");
  const raceMe = await call("GET", "/v1/account/me", null, authRace);
  assert.equal(raceMe.data.balanceYuan, 0.2);
  assert.equal(raceMe.data.reservedYuan, 0);
  assert.equal(raceMe.data.totalSpentYuan, 0.3);
  assert.equal(Math.round((raceMe.data.totalRechargedYuan - raceMe.data.totalSpentYuan) * 10000) / 10000, raceMe.data.balanceYuan);

  // 5d. Duplicate idempotency_key replay on image generation -> returns cached image, ZERO double charge!
  const winningIdx = raceResults.findIndex((r) => r.status === 200);
  const winningKey = `race-${winningIdx + 1}`;
  const callsBeforeReplay = upstreamCalls.length;
  const replayImg = await call("POST", "/v1/images/generations", { model: "gpt-image-1", prompt: "cat replay", n: 1 }, { ...authRace, "Idempotency-Key": winningKey });
  assert.equal(replayImg.status, 200);
  assert.equal(replayImg.data.idempotentReplay, true);
  assert.equal(upstreamCalls.length, callsBeforeReplay, "Idempotent replay MUST NOT re-invoke upstream");
  const raceMeAfterReplay = await call("GET", "/v1/account/me", null, authRace);
  assert.equal(raceMeAfterReplay.data.balanceYuan, 0.2, "Idempotent replay MUST NOT double-charge");

  // 5e. Chat streaming happy path + server-side max_tokens cap + exact settlement & remainder release
  const meBeforeChat = await call("GET", "/v1/account/me", null, authA);
  const balBeforeChat = meBeforeChat.data.balanceYuan; // 25
  const chatRes = await call("POST", "/v1/chat/completions", {
    model: "gpt-4o",
    messages: [{ role: "user", content: "请介绍一下预留结算。" }],
    max_tokens: 999999, // Exceeds server cap 4096!
  }, { ...authA, "Idempotency-Key": "chat-ok-1" });
  assert.equal(chatRes.status, 200);
  assert.ok(chatRes.rawText.includes("wumind_billing"));
  const lastChatUpstream = upstreamCalls.filter((c) => c.url.endsWith("/v1/chat/completions")).at(-1);
  assert.equal(JSON.parse(lastChatUpstream.body).max_tokens, 4096, "Server MUST cap max_tokens to CHAT_MAX_OUTPUT_TOKENS");
  const meAfterChat = await call("GET", "/v1/account/me", null, authA);
  assert.equal(meAfterChat.data.reservedYuan, 0, "Reservation must be cleared after settlement");
  assert.ok(meAfterChat.data.balanceYuan < balBeforeChat && meAfterChat.data.balanceYuan > balBeforeChat - 0.1, "Actual token cost should be small and exact");

  // 5f. Upstream HTTP 500 -> reservation 100% released, ¥0 deducted
  const balBefore500 = meAfterChat.data.balanceYuan;
  nextChatBehavior = "http500";
  const err500Chat = await call("POST", "/v1/chat/completions", {
    model: "gpt-4o",
    messages: [{ role: "user", content: "trigger 500" }],
  }, authA);
  assert.equal(err500Chat.status, 502);
  const meAfter500 = await call("GET", "/v1/account/me", null, authA);
  assert.equal(meAfter500.data.balanceYuan, balBefore500);
  assert.equal(meAfter500.data.reservedYuan, 0);

  // 5g. Mid-stream disconnect (0 tokens produced) -> full release, ¥0 deducted
  nextChatBehavior = "disconnect_empty";
  const discEmpty = await call("POST", "/v1/chat/completions", {
    model: "gpt-4o",
    messages: [{ role: "user", content: "disconnect before first token" }],
  }, authA);
  assert.equal(discEmpty.status, 200);
  assert.ok(discEmpty.rawText.includes("stream_interrupted"));
  const meAfterDiscEmpty = await call("GET", "/v1/account/me", null, authA);
  assert.equal(meAfterDiscEmpty.data.balanceYuan, balBefore500, "Zero-token mid-stream disconnect must release 100% of reservation");
  assert.equal(meAfterDiscEmpty.data.reservedYuan, 0);

  // 5h. Mid-stream disconnect (partial tokens delivered) -> settles partial tokens only, releases remainder
  nextChatBehavior = "disconnect_partial";
  const discPart = await call("POST", "/v1/chat/completions", {
    model: "gpt-4o",
    messages: [{ role: "user", content: "disconnect mid answer" }],
  }, authA);
  assert.equal(discPart.status, 200);
  assert.ok(discPart.rawText.includes("局部回答内容"));
  const meAfterDiscPart = await call("GET", "/v1/account/me", null, authA);
  assert.equal(meAfterDiscPart.data.reservedYuan, 0);
  assert.ok(meAfterDiscPart.data.balanceYuan < balBefore500 && meAfterDiscPart.data.balanceYuan > balBefore500 - 0.05);

  // =========================================================================
  // 6. Managed Reference-Image Editing & T2I-Only Refusal (No Silent Fallback!)
  // =========================================================================
  // 6a. Reference image on T2I-only model (`imagen-3.0-generate-002`) MUST be explicitly blocked with 400 + suggestedModels
  const callsBeforeT2iRefuse = upstreamCalls.length;
  const t2iRefuse = await call("POST", "/v1/images/edits", {
    model: "imagen-3.0-generate-002",
    prompt: "把背景换成雪山",
    referenceImage: { base64Data: TINY_PNG_B64, mimeType: "image/png", filename: "room.png" },
  }, authA);
  assert.equal(t2iRefuse.status, 400);
  assert.equal(t2iRefuse.data.code, "reference_image_not_supported");
  assert.equal(t2iRefuse.data.suggestedModels[0].id, "gpt-image-1");
  assert.equal(upstreamCalls.length, callsBeforeT2iRefuse, "Must NOT silently downgrade reference-image edit to text-to-image");

  // 6b. Reference image on image_edit-capable model (`gpt-image-1`) -> real multipart POST /v1/images/edits + settle ¥0.30
  const balBeforeEdit = (await call("GET", "/v1/account/me", null, authA)).data.balanceYuan;
  const editOk = await call("POST", "/v1/images/edits", {
    model: "gpt-image-1",
    prompt: "把桌面木纹改成浅橡木",
    size: "1024x1024",
    quality: "medium",
    referenceImage: { base64Data: TINY_PNG_B64, mimeType: "image/png", filename: "desk.png" },
  }, { ...authA, "Idempotency-Key": "edit-1" });
  assert.equal(editOk.status, 200);
  assert.equal(editOk.data.mode, "image_edit");
  assert.equal(editOk.data.data[0].b64_json, TINY_PNG_B64);
  assert.equal(editOk.data.billing.costYuan, 0.3);
  const balAfterEdit = (await call("GET", "/v1/account/me", null, authA)).data.balanceYuan;
  assert.equal(Math.round((balBeforeEdit - balAfterEdit) * 10000) / 10000, 0.3);

  // 6c. Image edit upstream 500 -> full reservation release, ¥0 deducted
  nextImageBehavior = "http500";
  const editFail = await call("POST", "/v1/images/edits", {
    model: "gpt-image-1",
    prompt: "fail edit",
    referenceImage: { base64Data: TINY_PNG_B64, mimeType: "image/png" },
  }, authA);
  assert.equal(editFail.status, 502);
  const meAfterEditFail = await call("GET", "/v1/account/me", null, authA);
  assert.equal(meAfterEditFail.data.balanceYuan, balAfterEdit);
  assert.equal(meAfterEditFail.data.reservedYuan, 0);

  // =========================================================================
  // 7. Managed Video Generation (`Sora 2`): Validation, Submit, Idempotency,
  //    Poll Settlement & Failure Release, Validated MP4 Stream
  // =========================================================================
  // 7a. Invalid 5s duration on Sora 2 -> rejected 400 with exact allowedSeconds [4,8,12], ¥0 deducted!
  const callsBeforeBadDur = upstreamCalls.length;
  const badDur = await call("POST", "/v1/videos", {
    model: "sora-2",
    prompt: "雨夜霓虹街道慢镜头",
    seconds: "5",
    size: "1280x720",
  }, authA);
  assert.equal(badDur.status, 400);
  assert.equal(badDur.data.code, "unsupported_video_duration");
  assert.deepEqual(badDur.data.allowedSeconds, ["4", "8", "12"]);
  assert.equal(upstreamCalls.length, callsBeforeBadDur);

  // 7b. Valid 4s / 1280x720 Sora 2 submit -> reserves ¥4.00 (4s * ¥1.00/s)
  const vidCreate = await call("POST", "/v1/videos", {
    model: "sora-2",
    prompt: "雨夜霓虹街道慢镜头",
    seconds: "4",
    size: "1280x720",
  }, { ...authA, "Idempotency-Key": "vid-sora-1" });
  assert.equal(vidCreate.status, 200);
  assert.equal(vidCreate.data.reservedYuan, 4);
  const jobID = vidCreate.data.id;
  const upJobID = vidCreate.data.upstreamJobID;

  // Balance still unchanged while reservedYuan == 4
  const meDuringVid = await call("GET", "/v1/account/me", null, authA);
  assert.equal(meDuringVid.data.reservedYuan, 4);
  assert.equal(meDuringVid.data.balanceYuan, balAfterEdit);

  // Duplicate submit with same Idempotency-Key returns same job without double-reserving
  const vidDup = await call("POST", "/v1/videos", {
    model: "sora-2",
    prompt: "雨夜霓虹街道慢镜头",
    seconds: "4",
    size: "1280x720",
  }, { ...authA, "Idempotency-Key": "vid-sora-1" });
  assert.equal(vidDup.status, 200);
  assert.equal(vidDup.data.id, jobID);
  assert.equal(vidDup.data.idempotentReplay, true);
  assert.equal((await call("GET", "/v1/account/me", null, authA)).data.reservedYuan, 4);

  // Complete upstream video -> poll settles ¥4.00 ONCE and returns contentPath
  mockVideoStates.set(upJobID, { id: upJobID, status: "completed", progress: 100 });
  const vidDone = await call("GET", `/v1/videos/${jobID}`, null, authA);
  assert.equal(vidDone.status, 200);
  assert.equal(vidDone.data.status, "completed");
  assert.equal(vidDone.data.billing.costYuan, 4);
  const meAfterVid = await call("GET", "/v1/account/me", null, authA);
  assert.equal(meAfterVid.data.reservedYuan, 0);
  assert.equal(Math.round((balAfterEdit - meAfterVid.data.balanceYuan) * 10000) / 10000, 4);

  // Download MP4 content validates ftyp header
  const mp4Res = await call("GET", `/v1/videos/${jobID}/content`, null, authA);
  assert.equal(mp4Res.status, 200);
  assert.equal(mp4Res.bytes[4], 0x66); // 'f'
  assert.equal(mp4Res.bytes[5], 0x74); // 't'
  assert.equal(mp4Res.bytes[6], 0x79); // 'y'
  assert.equal(mp4Res.bytes[7], 0x70); // 'p'

  // 7c. Failed video job -> poll releases 100% of ¥4.00 reservation, ¥0 deducted, exposes real upstream error
  const vidFailCreate = await call("POST", "/v1/videos", {
    model: "sora-2",
    prompt: "触发上游渲染失败",
    seconds: "4",
    size: "1280x720",
  }, { ...authA, "Idempotency-Key": "vid-sora-fail" });
  assert.equal(vidFailCreate.status, 200);
  mockVideoStates.set(vidFailCreate.data.upstreamJobID, {
    id: vidFailCreate.data.upstreamJobID,
    status: "failed",
    progress: 35,
    error: { message: "content policy rejected frame" },
  });
  const vidFailedPoll = await call("GET", `/v1/videos/${vidFailCreate.data.id}`, null, authA);
  assert.equal(vidFailedPoll.status, 200);
  assert.equal(vidFailedPoll.data.status, "failed");
  assert.ok(vidFailedPoll.data.error.includes("content policy rejected frame"));
  const meAfterVidFail = await call("GET", "/v1/account/me", null, authA);
  assert.equal(meAfterVidFail.data.reservedYuan, 0);
  assert.equal(meAfterVidFail.data.balanceYuan, meAfterVid.data.balanceYuan, "Failed video job MUST release reservation with ¥0 deducted");

  // =========================================================================
  // 8. Re-discovery Auto-Deprecates Vanished Models (No Ghost Models!)
  // =========================================================================
  mockCatalogModels = mockCatalogModels.filter((m) => m.id !== "imagen-3.0-generate-002");
  const rediscover = await call("POST", "/v1/admin/models/discover", { providers: ["aihubmix"] }, adminHdr);
  assert.equal(rediscover.status, 200);
  assert.ok(rediscover.data.totalDeprecated >= 1);
  const t2iAfterDrop = await call("GET", "/v1/public/models?capability=text_to_image");
  assert.deepEqual(t2iAfterDrop.data.models.map((m) => m.id), ["gpt-image-1"], "Vanished model must be auto-deprecated and removed from user catalog");

  // Print sanitized reconciliation & ledger proof for verification artifacts
  const finalLedger = sqlite.prepare(
    "SELECT id, user_id, kind, model, cost_micros, balance_before_micros, balance_after_micros, environment, operator_id, note FROM ledger WHERE user_id = ? ORDER BY id ASC"
  ).all(userA);
  const finalUserA = sqlite.prepare(
    "SELECT id, balance_micros, reserved_micros, sandbox_balance_micros, purchased_recharged_micros, admin_granted_micros, total_recharged_micros, total_spent_micros FROM users WHERE id = ?"
  ).get(userA);
  // Accounting invariant: (purchased + admin_granted - refunded) - total_spent == balance_micros
  const refundSum = finalLedger
    .filter((r) => r.kind === "apple_iap_refund")
    .reduce((acc, r) => acc + Number(r.cost_micros || 0), 0);
  assert.equal(
    finalUserA.purchased_recharged_micros + finalUserA.admin_granted_micros - refundSum - finalUserA.total_spent_micros,
    finalUserA.balance_micros,
    "Exact micro-yuan reconciliation invariant MUST hold across IAP, refund, admin grant, chat, image edit, and video!"
  );

  console.log("PASS: All billing-safety, StoreKit 2 ownership/refund, admin credit, dynamic catalog, reference-image edit, and Sora 2 video tests succeeded.");
  console.log("RECONCILIATION_PROOF:", JSON.stringify({
    userID: finalUserA.id,
    balanceYuan: finalUserA.balance_micros / 1e6,
    reservedYuan: finalUserA.reserved_micros / 1e6,
    sandboxBalanceYuan: finalUserA.sandbox_balance_micros / 1e6,
    purchasedRechargedYuan: finalUserA.purchased_recharged_micros / 1e6,
    adminGrantedYuan: finalUserA.admin_granted_micros / 1e6,
    refundedYuan: refundSum / 1e6,
    totalSpentYuan: finalUserA.total_spent_micros / 1e6,
    ledgerEntries: finalLedger.map((r) => ({
      id: r.id,
      kind: r.kind,
      model: r.model,
      deltaYuan: -(r.cost_micros / 1e6),
      beforeYuan: r.balance_before_micros / 1e6,
      afterYuan: r.balance_after_micros / 1e6,
      env: r.environment,
      operator: r.operator_id || "-",
    })),
  }, null, 2));
} finally {
  globalThis.fetch = originalFetch;
  fs.rmSync(tmp, { recursive: true, force: true });
}
