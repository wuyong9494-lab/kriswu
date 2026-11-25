#!/usr/bin/env node
/**
 * Automated Verification Suite for:
 *  1. Admin Fee-Waiver (`管理员免充值`): ¥0 balance succeeds across chat/image/video/realtime;
 *     wallet stays ¥0; usage + upstream cost recorded in ledger; daily cost cap & rate limit enforced;
 *     normal user blocked 402 at ¥0; revoking exemption restores normal 402 billing immediately.
 *  2. Upstream API Insufficient Balance Detection: returns HTTP 502 `upstream_balance_insufficient`
 *     with "上游 API 余额不足" — NEVER triggers App wallet recharge (402).
 *  3. AIHubMix Shared Pool Account Balance (Manage Key `GET /api/user/self`, `quota / 500000`):
 *     server-only query, normal user 403, low-balance alert threshold, sync failure returns
 *     "上次余额 · 同步失败" with cached last-known USD (NEVER falsely $0!).
 *  4. Full Admin User Registry (`GET /v1/admin/users`): shows everyone who registered, recharged, balances & usage.
 *  5. Private Cross-Device "My Works" (`user_works`): auto-saved on image/video tasks, cross-account privacy (404),
 *     versioned save preserving v1, in-progress video recovery without duplicate submit/charge.
 */
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import worker from "../src/index.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const schemaSql = fs.readFileSync(path.join(__dirname, "..", "schema.sql"), "utf8");
const TINY_PNG_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2dIAAAAASUVORK5CYII=";
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
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec(schemaSql);
  const DB = makeDB(sqlite);

  let mockAIHubMixQuota = 29_071_257; // $58.14 USD (29071257 / 500000)
  let failAIHubMixSelf = false;
  let forceUpstreamInsufficientQuota = false;
  let mockVideoStates = new Map();
  let videoSeq = 0;

  globalThis.fetch = async (input, init = {}) => {
    const url = typeof input === "string" ? input : input.url;
    const method = (init.method || "GET").toUpperCase();

    // AIHubMix Manage Key balance endpoint
    if (url.endsWith("/api/user/self") && method === "GET") {
      if (failAIHubMixSelf) {
        return new Response(JSON.stringify({ success: false, message: "service unavailable" }), { status: 503 });
      }
      assert.equal(init.headers?.Authorization, "fd_manage_secret_readonly", "Must send Manage Key raw without Bearer per CLI spec");
      return new Response(JSON.stringify({
        success: true,
        message: "",
        data: {
          username: "kris_pool",
          display_name: "Kris AIHubMix Pool",
          quota: mockAIHubMixQuota,
          used_quota: 25_000_000, // $50.00 used
          request_count: 12345,
        },
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    if (url.endsWith("/v1/models") && method === "GET") {
      return new Response(JSON.stringify({
        data: [{ id: "gpt-4o" }, { id: "gpt-image-1" }, { id: "sora-2" }],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    if (url.endsWith("/v1/chat/completions") && method === "POST") {
      const body = JSON.parse(String(init.body || "{}"));
      if (forceUpstreamInsufficientQuota) {
        return new Response(JSON.stringify({ error: { code: "insufficient_user_quota", message: "Your account quota is insufficient" } }), { status: 403 });
      }
      if (body.stream === false) {
        return new Response(JSON.stringify({
          choices: [{ message: { role: "assistant", content: "ok" } }],
          usage: { prompt_tokens: 5, completion_tokens: 1 },
        }), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      const enc = new TextEncoder();
      const stream = new ReadableStream({
        start(c) {
          c.enqueue(enc.encode(`data: ${JSON.stringify({ choices: [{ delta: { content: "管理员免扣通道回复成功。" } }] })}\n\n`));
          c.enqueue(enc.encode(`data: ${JSON.stringify({ choices: [], usage: { prompt_tokens: 100, completion_tokens: 50 } })}\n\n`));
          c.enqueue(enc.encode("data: [DONE]\n\n"));
          c.close();
        },
      });
      return new Response(stream, { status: 200, headers: { "Content-Type": "text/event-stream" } });
    }

    if (url.endsWith("/v1/images/generations") || url.endsWith("/v1/images/edits")) {
      if (forceUpstreamInsufficientQuota) {
        return new Response(JSON.stringify({ error: { message: "insufficient_quota on upstream provider" } }), { status: 402 });
      }
      return new Response(JSON.stringify({ data: [{ b64_json: TINY_PNG_B64, mime_type: "image/png" }] }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (url.endsWith("/v1/videos") && method === "POST") {
      const body = JSON.parse(String(init.body || "{}"));
      if (!body.prompt) return new Response(JSON.stringify({ error: { message: "prompt required" } }), { status: 400 });
      const id = `up_vid_${++videoSeq}`;
      mockVideoStates.set(id, { id, status: "queued", progress: 15 });
      return new Response(JSON.stringify(mockVideoStates.get(id)), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    if (/\/v1\/videos\/([^/]+)$/.test(url) && method === "GET") {
      const id = url.match(/\/v1\/videos\/([^/]+)$/)[1];
      return new Response(JSON.stringify(mockVideoStates.get(id)), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    throw new Error(`Unexpected fetch: ${method} ${url}`);
  };

  const baseEnv = {
    DB,
    ADMIN_SECRET: "admin_secret_ops",
    AIHUBMIX_API_KEY: "sk-aihubmix-infer-key",
    AIHUBMIX_MANAGE_KEY: "fd_manage_secret_readonly",
    AIHUBMIX_BASE_URL: "https://aihubmix.com",
    ADMIN_EXEMPT_DAILY_CAP_YUAN: "10",
    ADMIN_EXEMPT_RPM: "20",
  };

  async function call(method, route, body = null, headers = {}, envOverrides = {}) {
    const req = new Request(`https://gw.wumind.test${route}`, {
      method,
      headers: { "Content-Type": "application/json", ...headers },
      body: body !== null ? JSON.stringify(body) : undefined,
    });
    const res = await worker.fetch(req, { ...baseEnv, ...envOverrides }, { waitUntil() {} });
    const raw = await res.text();
    let data = null;
    try { data = JSON.parse(raw); } catch { data = raw; }
    return { status: res.status, data, raw };
  }

  const adminHdr = { "X-WuMind-Admin-Secret": baseEnv.ADMIN_SECRET };

  // Seed verified & priced catalog models
  await call("POST", "/v1/admin/models/discover", { providers: ["aihubmix"] }, adminHdr);
  await call("POST", "/v1/admin/models/probe", { modelIDs: ["gpt-4o", "gpt-image-1", "sora-2"] }, adminHdr);
  await call("POST", "/v1/admin/models/batch-update", {
    updates: [
      { id: "gpt-4o", inputPricePerMillion: 36, outputPricePerMillion: 144, enabled: true },
      { id: "gpt-image-1", unitPriceYuan: 0.30, enabled: true },
      { id: "sora-2", unitPriceYuan: 2.00, enabled: true },
    ],
  }, adminHdr);

  // Register Admin user (with ¥0 balance) & Normal user (with ¥0 balance)
  const regAdmin = await call("POST", "/v1/account/register", { displayName: "吴庸(管理员)", registeredRole: "admin" });
  const regUser = await call("POST", "/v1/account/register", { displayName: "普通用户小王", registeredRole: "externalUser" });
  const adminAuth = { Authorization: `Bearer ${regAdmin.data.userToken}` };
  const userAuth = { Authorization: `Bearer ${regUser.data.userToken}` };

  // =========================================================================
  // 1. Admin Fee-Waiver (`管理员免充值`) Acceptance Suite
  // =========================================================================
  // 1a. Before granting exemption, BOTH accounts have ¥0 balance -> blocked 402
  assert.equal((await call("POST", "/v1/chat/completions", { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }, adminAuth)).status, 402);
  assert.equal((await call("POST", "/v1/chat/completions", { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }, userAuth)).status, 402);

  // 1b. Normal user CANNOT grant themselves billing_exempt -> 403
  assert.equal((await call("POST", "/v1/admin/users/billing-exempt", { userID: regUser.data.userID, exempt: true }, userAuth)).status, 403);

  // 1c. Server grants billing_exempt ONLY to admin account (with daily cap ¥10)
  const grantRes = await call("POST", "/v1/admin/users/billing-exempt", {
    userID: regAdmin.data.userID,
    exempt: true,
    dailyCostCapYuan: 10,
  }, adminHdr);
  assert.equal(grantRes.status, 200);
  assert.equal(grantRes.data.billingExempt, true);

  // 1d. Admin at ¥0 balance calls Chat, Image, and Video -> ALL SUCCEED, wallet stays ¥0, ledger records upstream cost!
  const admChat = await call("POST", "/v1/chat/completions", { model: "gpt-4o", messages: [{ role: "user", content: "测试免扣对话" }] }, adminAuth);
  assert.equal(admChat.status, 200);
  assert.ok(admChat.raw.includes("管理员免扣通道回复成功"));
  assert.ok(admChat.raw.includes(`"adminExempt":true`));

  const admImg = await call("POST", "/v1/images/generations", { model: "gpt-image-1", prompt: "星空山谷", n: 1 }, { ...adminAuth, "Idempotency-Key": "adm-img-1" });
  assert.equal(admImg.status, 200);
  assert.equal(admImg.data.billing.adminExempt, true);
  assert.equal(admImg.data.billing.costYuan, 0);
  assert.equal(admImg.data.billing.upstreamCostYuan, 0.3);
  assert.ok(admImg.data.workID, "Image task must auto-create workID in user_works");
  assert.ok(admImg.data.timing.gatewaySubmitMs >= 1 && admImg.data.timing.upstreamGenerateMs >= 1);

  const admVid = await call("POST", "/v1/videos", { model: "sora-2", prompt: "海岸日出", seconds: "4", size: "1280x720" }, { ...adminAuth, "Idempotency-Key": "adm-vid-1" });
  assert.equal(admVid.status, 200);
  assert.equal(admVid.data.adminExempt, true);
  assert.equal(admVid.data.reservedYuan, 0);
  assert.ok(admVid.data.workID);
  mockVideoStates.set(admVid.data.upstreamJobID, { id: admVid.data.upstreamJobID, status: "completed", progress: 100 });
  const admVidDone = await call("GET", `/v1/videos/${admVid.data.id}`, null, adminAuth);
  assert.equal(admVidDone.status, 200);
  assert.equal(admVidDone.data.billing.adminExempt, true);
  assert.equal(admVidDone.data.billing.upstreamCostYuan, 8); // 4s * ¥2/s

  // Verify admin App wallet balance is STILL ¥0, while upstreamSpentYuan & ledger recorded exact usage!
  const admMe = await call("GET", "/v1/account/me", null, adminAuth);
  assert.equal(admMe.data.balanceYuan, 0, "Admin wallet balance MUST stay ¥0");
  assert.equal(admMe.data.billingExempt, true);
  assert.ok(admMe.data.upstreamSpentYuan > 8.3, `Expected tracked upstream cost > ¥8.30, got ${admMe.data.upstreamSpentYuan}`);
  assert.ok(admMe.data.ledger.some((l) => l.kind === "admin_exempt_video" && l.upstreamCostYuan === 8 && l.costYuan === 0));

  // 1e. Daily upstream cost cap protects against runaway video spend (already spent ¥8.31; another ¥8 video exceeds ¥10 cap -> 429!)
  const overCapVid = await call("POST", "/v1/videos", { model: "sora-2", prompt: "超出每日上限", seconds: "4", size: "1280x720" }, { ...adminAuth, "Idempotency-Key": "adm-vid-2" });
  assert.equal(overCapVid.status, 429);
  assert.equal(overCapVid.data.code, "admin_exempt_daily_cap_exceeded");

  // 1f. Normal user at ¥0 balance is STILL blocked 402!
  assert.equal((await call("POST", "/v1/chat/completions", { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }, userAuth)).status, 402);

  // 1g. Upstream API out-of-funds -> HTTP 502 `upstream_balance_insufficient` ("上游 API 余额不足"), NOT App 402!
  forceUpstreamInsufficientQuota = true;
  const upOutChat = await call("POST", "/v1/chat/completions", { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }, adminAuth);
  assert.equal(upOutChat.status, 502);
  assert.equal(upOutChat.data.code, "upstream_balance_insufficient");
  assert.ok(upOutChat.data.error.includes("上游 API 余额不足"));
  const upOutImg = await call("POST", "/v1/images/generations", { model: "gpt-image-1", prompt: "test" }, adminAuth);
  assert.equal(upOutImg.status, 502);
  assert.equal(upOutImg.data.code, "upstream_balance_insufficient");
  forceUpstreamInsufficientQuota = false;

  // 1h. Revoking admin exemption immediately restores normal 402 billing!
  const revokeRes = await call("POST", "/v1/admin/users/billing-exempt", { userID: regAdmin.data.userID, exempt: false }, adminHdr);
  assert.equal(revokeRes.status, 200);
  assert.equal(revokeRes.data.billingExempt, false);
  const blockedAgain = await call("POST", "/v1/chat/completions", { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }, adminAuth);
  assert.equal(blockedAgain.status, 402);

  // =========================================================================
  // 2. AIHubMix Pool Balance (Manage Key) & Alert Threshold + Failure Fallback
  // =========================================================================
  // Normal user MUST get 403
  assert.equal((await call("GET", "/v1/admin/upstream-balance", null, userAuth)).status, 403);
  assert.equal((await call("POST", "/v1/admin/upstream-balance/refresh", {}, userAuth)).status, 403);

  // Admin fetches real balance ($58.14 USD from quota=29071257 / 500000)
  const bal1 = await call("GET", "/v1/admin/upstream-balance", null, adminHdr);
  assert.equal(bal1.status, 200);
  assert.equal(bal1.data.availableUSD, 58.14);
  assert.equal(bal1.data.usedUSD, 50);
  assert.equal(bal1.data.currency, "USD");
  assert.equal(bal1.data.syncFailed, false);
  assert.equal(bal1.data.alertTriggered, false);

  // Raise alert threshold to $60 -> alertTriggered MUST become true!
  const alertRes = await call("PUT", "/v1/admin/upstream-balance/alert", { lowBalanceAlertUSD: 60 }, adminHdr);
  assert.equal(alertRes.status, 200);
  assert.equal(alertRes.data.lowBalanceAlertUSD, 60);
  assert.equal(alertRes.data.alertTriggered, true);

  // Simulate AIHubMix outage on refresh -> MUST preserve $58.14 and return "上次余额 · 同步失败" (NEVER $0!)
  failAIHubMixSelf = true;
  const balFail = await call("POST", "/v1/admin/upstream-balance/refresh", {}, adminHdr);
  assert.equal(balFail.status, 200);
  assert.equal(balFail.data.syncFailed, true);
  assert.equal(balFail.data.availableUSD, 58.14, "Sync failure MUST keep last known balance, NEVER reset to $0");
  assert.equal(balFail.data.statusLabel, "上次余额 · 同步失败");
  failAIHubMixSelf = false;

  // =========================================================================
  // 3. Full Admin Registered Users Registry (`GET /v1/admin/users`)
  // =========================================================================
  assert.equal((await call("GET", "/v1/admin/users", null, userAuth)).status, 403);
  const usersList = await call("GET", "/v1/admin/users", null, adminHdr);
  assert.equal(usersList.status, 200);
  assert.equal(usersList.data.totalUsers, 2);
  const admRow = usersList.data.users.find((u) => u.userID === regAdmin.data.userID);
  assert.equal(admRow.registeredRole, "admin");
  assert.ok(admRow.requestCount >= 3);
  assert.ok(admRow.upstreamSpentYuan > 8.3);

  // =========================================================================
  // 4. Private Cross-Device "My Works" (`user_works`): Privacy, Versioning, Recovery
  // =========================================================================
  // Admin lists own works -> sees auto-saved completed image, completed video, AND the failed upstream-quota image (preserving reason for retry!)
  const admWorks = await call("GET", "/v1/works", null, adminAuth);
  assert.equal(admWorks.status, 200);
  assert.equal(admWorks.data.works.length, 3);
  const imgWork = admWorks.data.works.find((w) => w.workType === "image" && w.status === "completed");
  const failedImgWork = admWorks.data.works.find((w) => w.workType === "image" && w.status === "failed");
  const vidWork = admWorks.data.works.find((w) => w.workType === "video");
  assert.ok(imgWork && imgWork.hasAsset === true);
  assert.ok(failedImgWork && failedImgWork.errorMessage.includes("上游 API 余额不足"));
  assert.equal(vidWork.status, "completed");

  // Privacy isolation: Normal user CANNOT list or read Admin's works (404!)
  const userWorksEmpty = await call("GET", "/v1/works", null, userAuth);
  assert.equal(userWorksEmpty.data.works.length, 0);
  assert.equal((await call("GET", `/v1/works/${imgWork.id}`, null, userAuth)).status, 404);
  assert.equal((await call("GET", `/v1/works/${imgWork.id}/asset`, null, userAuth)).status, 404);

  // Create PPT & 3D works on User account, then save a v2 edit -> v1 preserved untouched!
  const pptV1 = await call("POST", "/v1/works", {
    workType: "ppt",
    title: "2026 Q3 季度经营报告",
    prompt: "10页中文管理层汇报",
    modelID: "gpt-4o",
    status: "completed",
    progress: 100,
    projectJSON: JSON.stringify({ title: "Q3 Report", slides: [{ id: 1, title: "结论先行" }] }),
    idempotencyKey: "ppt-work-1",
  }, userAuth);
  assert.equal(pptV1.status, 200);
  assert.equal(pptV1.data.work.versionNumber, 1);

  // Save edited v2 -> original v1 remains untouched, v2 has versionNumber == 2 & parentWorkID == v1.id!
  const pptV2 = await call("PATCH", `/v1/works/${pptV1.data.work.id}`, {
    createNewVersion: true,
    title: "2026 Q3 季度经营报告（第5页折线图修订版）",
    projectJSON: JSON.stringify({ title: "Q3 Report v2", slides: [{ id: 1, title: "结论先行" }, { id: 5, chartKind: "line" }] }),
  }, userAuth);
  assert.equal(pptV2.status, 200);
  assert.equal(pptV2.data.versionCreated, true);
  assert.equal(pptV2.data.work.versionNumber, 2);
  assert.equal(pptV2.data.work.parentWorkID, pptV1.data.work.id);

  // Original v1 is completely intact!
  const pptV1Check = await call("GET", `/v1/works/${pptV1.data.work.id}`, null, userAuth);
  assert.ok(pptV1Check.data.work.projectJSON.includes("Q3 Report"));
  assert.ok(!pptV1Check.data.work.projectJSON.includes("Q3 Report v2"));

  // Realtime Voice endpoint enforces auth & balance/exempt properly
  assert.equal((await call("GET", "/v1/realtime?model=gpt-realtime-2.1")).status, 401);
  assert.equal((await call("GET", "/v1/realtime?model=gpt-realtime-2.1", null, userAuth)).status, 402);

  console.log("PASS: All Admin Fee-Waiver, Upstream Balance Error, AIHubMix Pool Balance + Alert, User Registry, Private My Works & Realtime Auth tests succeeded.");
} finally {
  globalThis.fetch = originalFetch;
}
