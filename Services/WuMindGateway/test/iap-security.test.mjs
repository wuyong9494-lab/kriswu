#!/usr/bin/env node
/**
 * Cryptographic & Isolation Security Test Suite for Services/WuMindGateway/src/index.js
 *
 * Verifies against real OpenSSL-generated 3-level ECDSA X.509 v3 certificate chains
 * (P-384 Root CA -> P-256 WWDR Intermediate -> P-256 App Store Leaf) and SQLite D1:
 *  1. Fail-closed default AUTO_CREDIT_PAUSED across IAP, Epay, HMAC webhook, and create-order
 *  2. Rejection of unsigned/forged JWS, tampered payload, alg:none, untrusted self-signed root
 *  3. Rejection of missing Apple Leaf OID (1.2.840.113635.100.6.11.1) & WWDR OID (1.2.840.113635.100.6.2.1)
 *  4. Rejection of expired/out-of-window signedDate, Xcode local StoreKit env, revoked transactions
 *  5. Strict isolation of Apple Sandbox credits into users.sandbox_balance_micros (never production balance_micros)
 *  6. Sandbox cap enforcement, idempotent replay, cross-user transaction hijack (409), and chat spend isolation (402)
 *  7. Production IAP gating (ALLOW_APPLE_PRODUCTION_IAP) and verified Production crediting
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

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const schemaSql = fs.readFileSync(path.join(__dirname, "..", "schema.sql"), "utf8");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "wumind-iap-pki-"));

try {
  function makeChain(prefix, { includeInterOid = true, includeLeafOid = true, interCA = true } = {}) {
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
basicConstraints = critical,CA:${interCA ? "TRUE" : "FALSE"}
keyUsage = critical,keyCertSign,cRLSign
${includeInterOid ? "1.2.840.113635.100.6.2.1 = DER:05:00" : ""}
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
CN = Test Mac App Store Receipt Signing (${prefix})
O = Apple Inc.
[v3_leaf]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
${includeLeafOid ? "1.2.840.113635.100.6.11.1 = DER:05:00" : ""}
`);
    run("openssl ecparam -name prime256v1 -genkey -noout -out leaf.key");
    run("openssl req -new -key leaf.key -config leaf.cnf -out leaf.csr");
    run("openssl x509 -req -in leaf.csr -CA inter.pem -CAkey inter.key -CAcreateserial -sha256 -days 365 -extfile leaf.cnf -extensions v3_leaf -out leaf.pem");
    run("openssl x509 -in leaf.pem -outform DER -out leaf.der");

    const rootDer = fs.readFileSync(path.join(dir, "root.der"));
    const interDer = fs.readFileSync(path.join(dir, "inter.der"));
    const leafDer = fs.readFileSync(path.join(dir, "leaf.der"));
    const leafKeyPem = fs.readFileSync(path.join(dir, "leaf.key"), "utf8");
    const rootSha256 = crypto.createHash("sha256").update(rootDer).digest("hex");
    return {
      x5c: [leafDer.toString("base64"), interDer.toString("base64"), rootDer.toString("base64")],
      leafKeyPem,
      rootSha256,
    };
  }

  function b64u(buf) {
    return Buffer.from(buf).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
  }

  function signJWS(chain, payload, { alg = "ES256", x5cOverride = null } = {}) {
    const header = { alg, x5c: x5cOverride ?? chain.x5c };
    const h = b64u(JSON.stringify(header));
    const p = b64u(JSON.stringify(payload));
    const sig = crypto.sign("sha256", Buffer.from(`${h}.${p}`), {
      key: chain.leafKeyPem,
      dsaEncoding: "ieee-p1363",
    });
    return `${h}.${p}.${b64u(sig)}`;
  }

  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec(schemaSql);
  let failBatchAtIndex = -1;
  const DB = {
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
        for (let idx = 0; idx < stmts.length; idx++) {
          if (idx === failBatchAtIndex) {
            failBatchAtIndex = -1;
            throw new Error("Simulated mid-transaction D1 I/O error");
          }
          stmts[idx]._execSync();
        }
        sqlite.exec("COMMIT");
        return [];
      } catch (err) {
        sqlite.exec("ROLLBACK");
        throw err;
      }
    },
  };

  const validChain = makeChain("apple_valid");
  const rogueChain = makeChain("attacker_rogue");
  const noLeafOidChain = makeChain("no_leaf_oid", { includeLeafOid: false });
  const noInterOidChain = makeChain("no_inter_oid", { includeInterOid: false });
  const nonCaInterChain = makeChain("non_ca_inter", { interCA: false });

  async function call(method, urlPath, body, headers = {}, envOverrides = {}) {
    const env = {
      DB,
      ADMIN_SECRET: "admin_super_secret",
      APPLE_BUNDLE_ID: "com.kriswu.shiftreminder",
      __TEST_TRUSTED_ROOT_SHA256: validChain.rootSha256,
      ...envOverrides,
    };
    const req = new Request(`https://gw.wumind.test${urlPath}`, {
      method,
      headers: { "Content-Type": "application/json", ...headers },
      body: body ? JSON.stringify(body) : undefined,
    });
    const res = await worker.fetch(req, env, { waitUntil() {} });
    const text = await res.text();
    let data = null;
    try { data = JSON.parse(text); } catch { data = text; }
    return { status: res.status, data };
  }

  const regA = await call("POST", "/v1/account/register", { displayName: "TesterA" });
  const regB = await call("POST", "/v1/account/register", { displayName: "TesterB" });
  const authA = { Authorization: `Bearer ${regA.data.userToken}` };
  const authB = { Authorization: `Bearer ${regB.data.userToken}` };

  const nowMs = Date.now();
  const sandboxClaims = {
    bundleId: "com.kriswu.shiftreminder",
    productId: "com.kriswu.wumind.credit.18",
    transactionId: "2000000111222333",
    originalTransactionId: "2000000111222333",
    type: "Consumable",
    environment: "Sandbox",
    signedDate: nowMs,
  };
  const validSandboxJws = signJWS(validChain, sandboxClaims);

  // 1. Default fail-closed kill-switch blocks IAP, create-order, Epay webhook, and HMAC webhook
  assert.equal((await call("POST", "/v1/iap/verify", {
    productID: sandboxClaims.productId,
    transactionID: sandboxClaims.transactionId,
    jwsRepresentation: validSandboxJws,
  }, authA)).status, 503);
  assert.equal((await call("POST", "/v1/payments/create-order", { amountYuan: 30, channel: "wechat" }, authA)).status, 503);
  assert.equal((await call("GET", "/v1/webhooks/epay?out_trade_no=ORD-1&money=30&trade_status=TRADE_SUCCESS&sign=bad", null, {}, { EPAY_KEY: "k" })).status, 503);
  assert.equal((await call("POST", "/v1/webhooks/payment", { orderID: "ORD-1", amountYuan: 30 }, { "X-WuMind-Signature": "bad" }, { PAYMENT_WEBHOOK_SECRET: "s" })).status, 503);
  const pubDefault = await call("GET", "/v1/public/config", null);
  assert.equal(pubDefault.data.autoCreditPaused, true);
  assert.equal(pubDefault.data.autoCheckoutEnabled, false);

  const activeSandboxEnv = {
    AUTO_CREDIT_PAUSED: "false",
    ALLOW_APPLE_SANDBOX_TEST: "true",
    ALLOW_APPLE_PRODUCTION_IAP: "false",
    SANDBOX_BALANCE_CAP_YUAN: "50",
  };

  // 2-8. Cryptographic signature, chain, OID, CA, validity, alg, Xcode & revocation rejections
  const forgedJws = `${b64u(JSON.stringify({ alg: "ES256", x5c: validChain.x5c }))}.${b64u(JSON.stringify(sandboxClaims))}.${b64u(Buffer.alloc(64, 7))}`;
  assert.equal((await call("POST", "/v1/iap/verify", { productID: sandboxClaims.productId, transactionID: sandboxClaims.transactionId, jwsRepresentation: forgedJws }, authA, activeSandboxEnv)).status, 401);

  const parts = validSandboxJws.split(".");
  const tamperedPayload = b64u(JSON.stringify({ ...sandboxClaims, productId: "com.kriswu.wumind.credit.198" }));
  assert.equal((await call("POST", "/v1/iap/verify", { productID: "com.kriswu.wumind.credit.198", transactionID: sandboxClaims.transactionId, jwsRepresentation: `${parts[0]}.${tamperedPayload}.${parts[2]}` }, authA, activeSandboxEnv)).status, 401);

  assert.equal((await call("POST", "/v1/iap/verify", { productID: sandboxClaims.productId, transactionID: sandboxClaims.transactionId, jwsRepresentation: signJWS(rogueChain, sandboxClaims) }, authA, activeSandboxEnv)).status, 401);
  assert.equal((await call("POST", "/v1/iap/verify", { productID: sandboxClaims.productId, transactionID: sandboxClaims.transactionId, jwsRepresentation: signJWS(noLeafOidChain, sandboxClaims) }, authA, { ...activeSandboxEnv, __TEST_TRUSTED_ROOT_SHA256: noLeafOidChain.rootSha256 })).status, 401);
  assert.equal((await call("POST", "/v1/iap/verify", { productID: sandboxClaims.productId, transactionID: sandboxClaims.transactionId, jwsRepresentation: signJWS(noInterOidChain, sandboxClaims) }, authA, { ...activeSandboxEnv, __TEST_TRUSTED_ROOT_SHA256: noInterOidChain.rootSha256 })).status, 401);
  assert.equal((await call("POST", "/v1/iap/verify", { productID: sandboxClaims.productId, transactionID: sandboxClaims.transactionId, jwsRepresentation: signJWS(nonCaInterChain, sandboxClaims) }, authA, { ...activeSandboxEnv, __TEST_TRUSTED_ROOT_SHA256: nonCaInterChain.rootSha256 })).status, 401);
  assert.equal((await call("POST", "/v1/iap/verify", { productID: sandboxClaims.productId, transactionID: sandboxClaims.transactionId, jwsRepresentation: signJWS(validChain, sandboxClaims, { alg: "none" }) }, authA, activeSandboxEnv)).status, 401);

  // Out-of-window signedDate (before cert notBefore) -> 401
  const outOfWindowJws = signJWS(validChain, { ...sandboxClaims, signedDate: Date.UTC(2021, 0, 1), transactionId: "2000000111222330" });
  assert.equal((await call("POST", "/v1/iap/verify", { productID: sandboxClaims.productId, transactionID: "2000000111222330", jwsRepresentation: outOfWindowJws }, authA, activeSandboxEnv)).status, 401);

  // Xcode local StoreKit file -> 403
  assert.equal((await call("POST", "/v1/iap/verify", { productID: sandboxClaims.productId, transactionID: "2000000111222334", jwsRepresentation: signJWS(validChain, { ...sandboxClaims, environment: "Xcode", transactionId: "2000000111222334" }) }, authA, activeSandboxEnv)).status, 403);

  // Revoked transaction -> 403
  assert.equal((await call("POST", "/v1/iap/verify", { productID: sandboxClaims.productId, transactionID: "2000000111222335", jwsRepresentation: signJWS(validChain, { ...sandboxClaims, revocationDate: nowMs - 1000, transactionId: "2000000111222335" }) }, authA, activeSandboxEnv)).status, 403);

  // Production blocked while ALLOW_APPLE_PRODUCTION_IAP=false -> 403
  const prodClaims = { ...sandboxClaims, environment: "Production", transactionId: "3000000999888777" };
  const validProdJws = signJWS(validChain, prodClaims);
  assert.equal((await call("POST", "/v1/iap/verify", { productID: prodClaims.productId, transactionID: prodClaims.transactionId, jwsRepresentation: validProdJws }, authA, activeSandboxEnv)).status, 403);

  // 9. Valid Sandbox JWS -> credits ONLY isolated sandbox_balance_micros!
  const okSandbox = await call("POST", "/v1/iap/verify", { productID: sandboxClaims.productId, transactionID: sandboxClaims.transactionId, originalTransactionID: sandboxClaims.originalTransactionId, jwsRepresentation: validSandboxJws }, authA, activeSandboxEnv);
  assert.equal(okSandbox.status, 200);
  assert.equal(okSandbox.data.isSandbox, true);
  assert.equal(okSandbox.data.creditedYuan, 18);
  assert.equal(okSandbox.data.sandboxBalanceYuan, 18);
  assert.equal(okSandbox.data.balanceYuan, 0);

  // 10. Idempotent replay -> alreadyCredited=true, no double credit
  const replay = await call("POST", "/v1/iap/verify", { productID: sandboxClaims.productId, transactionID: sandboxClaims.transactionId, jwsRepresentation: validSandboxJws }, authA, activeSandboxEnv);
  assert.equal(replay.status, 200);
  assert.equal(replay.data.alreadyCredited, true);
  assert.equal(replay.data.sandboxBalanceYuan, 18);
  assert.equal(replay.data.balanceYuan, 0);

  // 11. Cross-user hijack -> 409
  assert.equal((await call("POST", "/v1/iap/verify", { productID: sandboxClaims.productId, transactionID: sandboxClaims.transactionId, jwsRepresentation: validSandboxJws }, authB, activeSandboxEnv)).status, 409);

  // 12. Sandbox credits CANNOT spend paid upstream /v1/chat/completions -> 402
  assert.equal((await call("POST", "/v1/chat/completions", { model: "deepseek-chat", messages: [{ role: "user", content: "hi" }] }, authA, { ...activeSandboxEnv, DEEPSEEK_API_KEY: "dummy" })).status, 402);

  // 13. Sandbox cap enforcement (18 + 68 > 50) -> 403
  assert.equal((await call("POST", "/v1/iap/verify", { productID: "com.kriswu.wumind.credit.68", transactionID: "2000000111222999", jwsRepresentation: signJWS(validChain, { ...sandboxClaims, productId: "com.kriswu.wumind.credit.68", transactionId: "2000000111222999" }) }, authA, activeSandboxEnv)).status, 403);

  // 14. Valid Production JWS when ALLOW_APPLE_PRODUCTION_IAP=true -> credits real balance!
  const okProd = await call("POST", "/v1/iap/verify", { productID: prodClaims.productId, transactionID: prodClaims.transactionId, jwsRepresentation: validProdJws }, authA, { ...activeSandboxEnv, ALLOW_APPLE_PRODUCTION_IAP: "true" });
  assert.equal(okProd.status, 200);
  assert.equal(okProd.data.isSandbox, false);
  assert.equal(okProd.data.balanceYuan, 18);
  assert.equal(okProd.data.sandboxBalanceYuan, 18);

  const meA = await call("GET", "/v1/account/me", null, authA, activeSandboxEnv);
  assert.equal(meA.data.balanceYuan, 18);
  assert.equal(meA.data.sandboxBalanceYuan, 18);
  assert.equal(meA.data.totalRechargedYuan, 18);

  // 15. External Phone SMS & WeChat Auth MUST fail-closed (503) when vendor secrets are absent
  assert.equal(pubDefault.data.smsAuthConfigured, false);
  assert.equal(pubDefault.data.wechatAuthConfigured, false);
  const smsFailClosed = await call("POST", "/v1/auth/sms/send", { phone: "13800138000" });
  assert.equal(smsFailClosed.status, 503);
  assert.equal(smsFailClosed.data.code, "sms_provider_not_configured");
  const wxFailClosed = await call("POST", "/v1/auth/wechat/login", { code: "wx_code_123" });
  assert.equal(wxFailClosed.status, 503);
  assert.equal(wxFailClosed.data.code, "wechat_not_configured");

  // 16. Invalid phone number -> 400
  assert.equal((await call("POST", "/v1/auth/sms/send", { phone: "12345" }, {}, { AUTH_TEST_MODE: "true" })).status, 400);

  // 17. Valid SMS OTP send -> cooldown 429 -> wrong code 401 -> correct code 200 (role=externalUser) -> /v1/auth/me 200
  const smsSent = await call("POST", "/v1/auth/sms/send", { phone: "+86 13800138000" }, {}, { AUTH_TEST_MODE: "true" });
  assert.equal(smsSent.status, 200);
  assert.equal(smsSent.data.maskedPhone, "138****8000");
  assert.match(smsSent.data.debugCode, /^\d{6}$/);
  assert.equal((await call("POST", "/v1/auth/sms/send", { phone: "13800138000" }, {}, { AUTH_TEST_MODE: "true" })).status, 429);
  assert.equal((await call("POST", "/v1/auth/sms/verify", { phone: "13800138000", code: "000000" }, {}, { AUTH_TEST_MODE: "true" })).status, 401);
  const smsOk = await call("POST", "/v1/auth/sms/verify", { phone: "13800138000", code: smsSent.data.debugCode, nickname: "外部测试员" }, {}, { AUTH_TEST_MODE: "true" });
  assert.equal(smsOk.status, 200);
  assert.equal(smsOk.data.user.role, "externalUser");
  assert.equal(smsOk.data.user.phoneMasked, "138****8000");
  assert.ok(smsOk.data.sessionToken.startsWith("wm_ext_"));
  const extMe = await call("GET", "/v1/auth/me", null, { Authorization: `Bearer ${smsOk.data.sessionToken}` });
  assert.equal(extMe.status, 200);
  assert.equal(extMe.data.user.role, "externalUser");
  assert.equal(extMe.data.user.nickname, "外部测试员");
  // Replay of already-used OTP -> 401
  assert.equal((await call("POST", "/v1/auth/sms/verify", { phone: "13800138000", code: smsSent.data.debugCode }, {}, { AUTH_TEST_MODE: "true" })).status, 401);

  // 18. WeChat OAuth in explicit AUTH_TEST_MODE -> creates externalUser session
  const wxOk = await call("POST", "/v1/auth/wechat/login", { code: "oauth_demo_001", nickname: "微信访客" }, {}, { AUTH_TEST_MODE: "true" });
  assert.equal(wxOk.status, 200);
  assert.equal(wxOk.data.user.role, "externalUser");
  assert.equal(wxOk.data.user.loginMethod, "wechat");

  // 19. AIHubMix unified supply route: fail-closed allowlist (empty & "*" rejected -> 403), exact key-host isolation!
  // User A already has ¥18 real production balance from test #14.
  const noAllowlist = await call("POST", "/v1/chat/completions", {
    model: "gpt-4o",
    messages: [{ role: "user", content: "hi" }],
  }, authA, { AIHUBMIX_API_KEY: "sk-aihubmix-secret", AIHUBMIX_ALLOWED_MODELS: "" });
  assert.equal(noAllowlist.status, 403);
  assert.equal(noAllowlist.data.code, "aihubmix_model_not_allowed");

  const wildcardRejected = await call("POST", "/v1/chat/completions", {
    model: "gpt-4o",
    messages: [{ role: "user", content: "hi" }],
  }, authA, { AIHUBMIX_API_KEY: "sk-aihubmix-secret", AIHUBMIX_ALLOWED_MODELS: "*" });
  assert.equal(wildcardRejected.status, 403);
  assert.equal(wildcardRejected.data.code, "aihubmix_model_not_allowed");

  const modelNotInList = await call("POST", "/v1/chat/completions", {
    model: "claude-sonnet-4-20250514",
    messages: [{ role: "user", content: "hi" }],
  }, authA, { AIHUBMIX_API_KEY: "sk-aihubmix-secret", AIHUBMIX_ALLOWED_MODELS: "gpt-4o,deepseek-chat" });
  assert.equal(modelNotInList.status, 403);
  assert.equal(modelNotInList.data.code, "aihubmix_model_not_allowed");

  // Intercept global fetch to verify EXACT URL + Authorization header routing without leaking keys across hosts
  const origFetch = globalThis.fetch;
  const capturedCalls = [];
  globalThis.fetch = async (url, init) => {
    capturedCalls.push({ url: String(url), headers: init?.headers || {}, body: JSON.parse(init?.body || "{}") });
    const sse = 'data: {"choices":[{"delta":{"content":"ok"}}],"usage":{"prompt_tokens":10,"completion_tokens":5}}\n\ndata: [DONE]\n\n';
    return new Response(sse, { status: 200, headers: { "Content-Type": "text/event-stream" } });
  };
  try {
    // 19a. AIHUBMIX_API_KEY + allowed model -> routes strictly to https://aihubmix.com/v1/chat/completions with AIHUBMIX_API_KEY
    const viaHub = await call("POST", "/v1/chat/completions", {
      model: "gpt-4o",
      messages: [{ role: "user", content: "hello aihubmix" }],
    }, authA, {
      AIHUBMIX_API_KEY: "sk-aihubmix-only",
      AIHUBMIX_ALLOWED_MODELS: "gpt-4o,deepseek-chat",
      AIHUBMIX_APP_CODE: "WM01",
    });
    assert.equal(viaHub.status, 200);
    assert.equal(capturedCalls.length, 1);
    assert.equal(capturedCalls[0].url, "https://aihubmix.com/v1/chat/completions");
    assert.equal(capturedCalls[0].headers.Authorization, "Bearer sk-aihubmix-only");
    assert.equal(capturedCalls[0].headers["APP-Code"], "WM01");

    // 19b. Official OPENAI_API_KEY configured -> routes strictly to https://api.openai.com/v1/chat/completions (NEVER to aihubmix.com!)
    const viaOfficial = await call("POST", "/v1/chat/completions", {
      model: "gpt-4o",
      messages: [{ role: "user", content: "hello official" }],
    }, authA, {
      OPENAI_API_KEY: "sk-openai-official-only",
      AIHUBMIX_API_KEY: "sk-aihubmix-only",
      AIHUBMIX_ALLOWED_MODELS: "gpt-4o",
    });
    assert.equal(viaOfficial.status, 200);
    assert.equal(capturedCalls.length, 2);
    assert.equal(capturedCalls[1].url, "https://api.openai.com/v1/chat/completions");
    assert.equal(capturedCalls[1].headers.Authorization, "Bearer sk-openai-official-only");
    assert.equal(capturedCalls[1].headers["APP-Code"], undefined);
  } finally {
    globalThis.fetch = origFetch;
  }

  // 20. Mid-transaction fault injection: failure mid-DB.batch MUST roll back ALL statements (order NOT paid, balance unchanged, NO ledger),
  //     and subsequent retry MUST succeed and credit EXACTLY ONCE!
  const faultTxID = "2000000555666777";
  const faultJws = signJWS(validChain, {
    ...sandboxClaims,
    productId: "com.kriswu.wumind.credit.6",
    transactionId: faultTxID,
    originalTransactionId: faultTxID,
  });
  const beforeFault = await call("GET", "/v1/account/me", null, authB, activeSandboxEnv);
  assert.equal(beforeFault.data.sandboxBalanceYuan, 0);
  failBatchAtIndex = 2; // inject failure right at statement #3 (after ledger insert + user credit)
  const failedAttempt = await call("POST", "/v1/iap/verify", {
    productID: "com.kriswu.wumind.credit.6",
    transactionID: faultTxID,
    jwsRepresentation: faultJws,
  }, authB, activeSandboxEnv);
  assert.equal(failedAttempt.status, 500);
  // Verify complete SQLite rollback: balance still 0, no paid order, no ledger row!
  const afterRollback = await call("GET", "/v1/account/me", null, authB, activeSandboxEnv);
  assert.equal(afterRollback.data.sandboxBalanceYuan, 0);
  assert.equal(sqlite.prepare("SELECT COUNT(*) AS c FROM payment_orders WHERE external_order_id = ?").get(`iap_sandbox:${faultTxID}`).c, 0);
  assert.equal(sqlite.prepare("SELECT COUNT(*) AS c FROM ledger WHERE external_order_id = ?").get(`iap_sandbox:${faultTxID}`).c, 0);

  // Retry after transient failure -> MUST recover cleanly and credit ¥6 ONCE!
  const recovered = await call("POST", "/v1/iap/verify", {
    productID: "com.kriswu.wumind.credit.6",
    transactionID: faultTxID,
    jwsRepresentation: faultJws,
  }, authB, activeSandboxEnv);
  assert.equal(recovered.status, 200);
  assert.equal(recovered.data.alreadyCredited, false);
  assert.equal(recovered.data.sandboxBalanceYuan, 6);
  assert.equal(recovered.data.balanceYuan, 0);

  // 21. Legacy partial-failure self-healing: if an order was marked 'paid' WITHOUT a ledger row, retry heals balance + ledger ONCE!
  const healTxID = "2000000888999000";
  const healJws = signJWS(validChain, {
    ...sandboxClaims,
    productId: "com.kriswu.wumind.credit.6",
    transactionId: healTxID,
    originalTransactionId: healTxID,
  });
  sqlite.prepare(
    "INSERT INTO payment_orders (id, user_id, external_order_id, amount_micros, channel, environment, status, note) VALUES ('ORD-BROKEN', ?, ?, 6000000, 'apple_iap_sandbox', 'sandbox', 'paid', 'pre-patch crash')"
  ).run(regB.data.userID, `iap_sandbox:${healTxID}`);
  const healed = await call("POST", "/v1/iap/verify", {
    productID: "com.kriswu.wumind.credit.6",
    transactionID: healTxID,
    jwsRepresentation: healJws,
  }, authB, activeSandboxEnv);
  assert.equal(healed.status, 200);
  assert.equal(healed.data.alreadyCredited, false);
  assert.equal(healed.data.sandboxBalanceYuan, 12);
  // Second retry after healing -> strictly idempotent (alreadyCredited=true, balance stays 12)
  const healedReplay = await call("POST", "/v1/iap/verify", {
    productID: "com.kriswu.wumind.credit.6",
    transactionID: healTxID,
    jwsRepresentation: healJws,
  }, authB, activeSandboxEnv);
  assert.equal(healedReplay.status, 200);
  assert.equal(healedReplay.data.alreadyCredited, true);
  assert.equal(healedReplay.data.sandboxBalanceYuan, 12);

  // 22. Concurrent duplicate submission race -> credits EXACTLY ONCE with exactly 1 ledger row!
  const raceTxID = "2000000777888999";
  const raceJws = signJWS(validChain, {
    ...sandboxClaims,
    productId: "com.kriswu.wumind.credit.6",
    transactionId: raceTxID,
    originalTransactionId: raceTxID,
  });
  const raceResults = await Promise.all([
    call("POST", "/v1/iap/verify", { productID: "com.kriswu.wumind.credit.6", transactionID: raceTxID, jwsRepresentation: raceJws }, authB, activeSandboxEnv),
    call("POST", "/v1/iap/verify", { productID: "com.kriswu.wumind.credit.6", transactionID: raceTxID, jwsRepresentation: raceJws }, authB, activeSandboxEnv),
    call("POST", "/v1/iap/verify", { productID: "com.kriswu.wumind.credit.6", transactionID: raceTxID, jwsRepresentation: raceJws }, authB, activeSandboxEnv),
  ]);
  for (const r of raceResults) assert.equal(r.status, 200);
  assert.equal(raceResults.filter((r) => r.data.alreadyCredited === false).length, 1);
  assert.equal(raceResults.filter((r) => r.data.alreadyCredited === true).length, 2);
  const afterRace = await call("GET", "/v1/account/me", null, authB, activeSandboxEnv);
  assert.equal(afterRace.data.sandboxBalanceYuan, 18);
  assert.equal(sqlite.prepare("SELECT COUNT(*) AS c FROM ledger WHERE external_order_id = ?").get(`iap_sandbox:${raceTxID}`).c, 1);

  console.log("PASS: All 32 Apple StoreKit 2 cryptographic verification, ACID atomic crediting, retry recovery, External Auth & AIHubMix routing tests succeeded.");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
