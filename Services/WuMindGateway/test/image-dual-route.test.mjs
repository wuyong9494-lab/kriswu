#!/usr/bin/env node
/**
 * End-to-End Automated Verification Suite for WUMIND Managed Image Studio Dual-Protocol Routing:
 *  1. GET /health exposes gatewayVersion & read-only billing flags (AUTO_CREDIT_PAUSED=true, ALLOW_APPLE_PRODUCTION_IAP=false).
 *  2. Discovery + Official USD Pricing + Live Probe for:
 *     - `gemini-3.1-flash-image` ("Nano Banana 2") -> `aihubmix_gemini_image` -> `POST /gemini/v1beta/models/gemini-3.1-flash-image:generateContent` (`x-goog-api-key`)
 *     - `gpt-image-1.5` / `gpt-image-2` -> `openai_images` -> multipart `/v1/images/edits` & JSON `/v1/images/generations` (`Authorization: Bearer`)
 *  3. Ordinary user (¥10 balance, zero local vendor keys):
 *     - Generates GPT Image (`gpt-image-2`) T2I + Reference-Image Edit (`gpt-image-1.5`)
 *     - Generates Nano Banana 2 (`gemini-3.1-flash-image`) T2I + Reference-Image Edit (`inline_data` on `:generateContent`)
 *     - Verifies exact 1 ledger settlement per generation and `reserved_micros === 0` after completion
 *  4. AIHubMix Unified `/ai/v1/images/generations` auto-fallback:
 *     - Decodes same-origin `content_url` with `Authorization: Bearer`
 *     - Blocks off-origin SSRF `content_url` and releases reservation (0 charge)
 *  5. Idempotent Retry Safety (including >500KB payload!):
 *     - Same `Idempotency-Key` replays image + billing with `idempotentReplay: true`, calls upstream ONCE, settles ONCE
 *  6. Strict Error Classification & Zero-Charge Guarantee:
 *     - Unenabled model -> 403 `model_not_enabled` (0 upstream call, 0 charge)
 *     - Insufficient WuMind balance -> 402 `insufficient_balance` (0 upstream call)
 *     - Upstream 401 auth error -> 502 `upstream_auth_failed` (preserves WuMind session, releases reservation)
 *     - Upstream balance error -> 502 `upstream_balance_insufficient` (releases reservation)
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

// Valid 8x8 PNG base64
const SAMPLE_PNG_B64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAADklEQVR4nGNgGAX4AAAAWAABaN+c3wAAAABJRU5ErkJggg==";
const SAMPLE_PNG_BYTES = Buffer.from(SAMPLE_PNG_B64, "base64");

// Build a REAL structurally valid >500KB PNG by inserting a valid tEXt ancillary chunk BEFORE the 12-byte IEND trailer!
function makeValidLargePNG() {
  const beforeIEND = SAMPLE_PNG_BYTES.subarray(0, SAMPLE_PNG_BYTES.length - 12);
  const iend = SAMPLE_PNG_BYTES.subarray(SAMPLE_PNG_BYTES.length - 12);
  const payload = Buffer.alloc(400_000, 0x41); // 'A' bytes inside tEXt chunk
  const chunkHeader = Buffer.alloc(8);
  chunkHeader.writeUInt32BE(payload.length, 0);
  chunkHeader.write("tEXt", 4, "ascii");
  const fakeCRC = Buffer.alloc(4, 0);
  return Buffer.concat([beforeIEND, chunkHeader, payload, fakeCRC, iend]);
}
const LARGE_PNG_BYTES = makeValidLargePNG();
const LARGE_PNG_B64 = LARGE_PNG_BYTES.toString("base64");
// Truncated/corrupt PNG (missing IEND) & non-image base64 for Regression Test 3
const CORRUPT_BASE64 = Buffer.from("not-a-valid-image-payload-at-all").toString("base64");
const TRUNCATED_PNG_B64 = SAMPLE_PNG_BYTES.subarray(0, SAMPLE_PNG_BYTES.length - 6).toString("base64");

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
          return { success: true, meta: { changes: Number(info.changes || 0), last_row_id: Number(info.lastInsertRowid || 0) } };
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

  const env = {
    DB,
    ADMIN_SECRET: "test-admin-secret-999",
    AIHUBMIX_API_KEY: "sk-aihubmix-server-only-key",
    AIHUBMIX_BASE_URL: "https://aihubmix.com/v1",
    AUTO_CREDIT_PAUSED: "true",
    ALLOW_APPLE_PRODUCTION_IAP: "false",
    ADMIN_TOPUP_MAX_SINGLE_YUAN: "500",
    ADMIN_TOPUP_DAILY_CAP_YUAN: "5000",
  };

  let upstreamMode = "normal"; // normal | unified_content_url | ssrf_content_url | large_payload | corrupt_image | upstream_401 | upstream_balance | t2i_text_only_edit_ok | t2i_ok_edit_corrupt | both_corrupt
  const observedUpstream = [];
  let forbiddenHostCalled = false;

  globalThis.fetch = async (input, init = {}) => {
    const url = typeof input === "string" ? input : input.url;
    const method = (init.method || "GET").toUpperCase();
    const headers = Object.fromEntries(
      Object.entries(init.headers || {}).map(([k, v]) => [k.toLowerCase(), String(v)])
    );
    const isFormData = typeof FormData !== "undefined" && init.body instanceof FormData;
    const bodyText = isFormData ? "[FormData]" : (init.body ? String(init.body) : "");
    observedUpstream.push({ method, url, headers, isFormData, bodyText });

    if (url.includes("evil.example.com")) {
      forbiddenHostCalled = true;
      return new Response("ssrf should never be fetched", { status: 200 });
    }

    // 1. Model discovery
    if (url === "https://aihubmix.com/v1/models" && method === "GET") {
      return new Response(JSON.stringify({
        data: [
          { id: "gpt-image-1.5" },
          { id: "gpt-image-2" },
          { id: "gemini-3.1-flash-image" },
          { id: "gemini-3-pro-image" },
        ],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    // 2. AIHubMix Gemini Native generateContent for Nano Banana 2 (both T2I and Reference Edit)
    if (url === "https://aihubmix.com/gemini/v1beta/models/gemini-3.1-flash-image:generateContent" && method === "POST") {
      assert.equal(headers["x-goog-api-key"], "sk-aihubmix-server-only-key");
      assert.equal(headers["authorization"], undefined);
      const parsed = JSON.parse(bodyText);
      const parts = parsed.contents?.[0]?.parts || [];
      assert.ok(Array.isArray(parts));
      const isEditRequest = parts.some((p) => Boolean(p.inline_data));

      if (upstreamMode === "unified_content_url" || upstreamMode === "ssrf_content_url") {
        return new Response(JSON.stringify({
          error: { code: "protocol_not_supported", message: "Use POST /ai/v1/images/generations" },
        }), { status: 400, headers: { "Content-Type": "application/json" } });
      }
      if (upstreamMode === "upstream_401") {
        return new Response(JSON.stringify({ error: { message: "Invalid AIHubMix key" } }), { status: 401 });
      }
      if (upstreamMode === "upstream_balance") {
        return new Response(JSON.stringify({ error: { message: "insufficient_quota on upstream account" } }), { status: 402 });
      }
      if (upstreamMode === "corrupt_image") {
        return new Response(JSON.stringify({
          candidates: [{ content: { parts: [{ inlineData: { mimeType: "image/png", data: TRUNCATED_PNG_B64 } }] } }],
        }), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      if (upstreamMode === "t2i_text_only_edit_ok" && !isEditRequest) {
        // HTTP 200 with TEXT ONLY (no decodable image!) on T2I
        return new Response(JSON.stringify({
          candidates: [{ content: { parts: [{ text: "I cannot draw that right now." }] } }],
        }), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      if (upstreamMode === "t2i_ok_edit_corrupt" && isEditRequest) {
        // HTTP 200 with undecodable corrupt base64 on Reference Edit
        return new Response(JSON.stringify({
          candidates: [{ content: { parts: [{ inlineData: { mimeType: "image/png", data: CORRUPT_BASE64 } }] } }],
        }), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      if (upstreamMode === "both_corrupt") {
        return new Response(JSON.stringify({
          candidates: [{ content: { parts: [{ inlineData: { mimeType: "image/png", data: TRUNCATED_PNG_B64 } }] } }],
        }), { status: 200, headers: { "Content-Type": "application/json" } });
      }

      const b64 = upstreamMode === "large_payload" ? LARGE_PNG_B64 : SAMPLE_PNG_B64;
      return new Response(JSON.stringify({
        candidates: [{
          content: {
            parts: [
              { thought: true, inlineData: { mimeType: "image/png", data: "SHOULD_SKIP_THOUGHT" } },
              { inlineData: { mimeType: "image/png", data: b64 } },
            ],
          },
        }],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    // 3. AIHubMix Unified `/ai/v1/images/generations` fallback
    if (url === "https://aihubmix.com/ai/v1/images/generations" && method === "POST") {
      assert.equal(headers["authorization"], "Bearer sk-aihubmix-server-only-key");
      if (upstreamMode === "ssrf_content_url") {
        return new Response(JSON.stringify({
          id: "img_ssrf_1",
          status: "completed",
          output: [{ index: 0, content_url: "https://evil.example.com/steal.png", content_type: "image/png" }],
        }), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      return new Response(JSON.stringify({
        id: "img_uni_1",
        status: "completed",
        output: [{ index: 0, content_url: "https://aihubmix.com/ai/v1/files/img_uni_1/content", content_type: "image/png" }],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    if (url === "https://aihubmix.com/ai/v1/files/img_uni_1/content" && method === "GET") {
      assert.equal(headers["authorization"], "Bearer sk-aihubmix-server-only-key");
      return new Response(SAMPLE_PNG_BYTES, { status: 200, headers: { "Content-Type": "image/png" } });
    }

    // 4. OpenAI/AIHubMix GPT Image T2I
    if (url === "https://aihubmix.com/v1/images/generations" && method === "POST") {
      assert.equal(headers["authorization"], "Bearer sk-aihubmix-server-only-key");
      const parsed = JSON.parse(bodyText);
      assert.ok(parsed.model === "gpt-image-2" || parsed.model === "gpt-image-1.5");
      if (upstreamMode === "t2i_text_only_edit_ok" || upstreamMode === "both_corrupt") {
        return new Response(JSON.stringify({ data: [{ b64_json: CORRUPT_BASE64 }] }), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      return new Response(JSON.stringify({
        data: [{ b64_json: SAMPLE_PNG_B64 }],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    // 5. OpenAI/AIHubMix GPT Image Reference-Image Edit (multipart)
    if (url === "https://aihubmix.com/v1/images/edits" && method === "POST") {
      assert.equal(headers["authorization"], "Bearer sk-aihubmix-server-only-key");
      assert.equal(isFormData, true);
      if (upstreamMode === "t2i_ok_edit_corrupt" || upstreamMode === "both_corrupt") {
        return new Response(JSON.stringify({ data: [{ b64_json: TRUNCATED_PNG_B64 }] }), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      return new Response(JSON.stringify({
        data: [{ b64_json: SAMPLE_PNG_B64 }],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    throw new Error(`Unexpected upstream fetch: ${method} ${url}`);
  };

  const req = (method, p, { token = null, admin = false, body = null, headers = {} } = {}) => {
    const h = { ...headers };
    if (token) h.Authorization = `Bearer ${token}`;
    if (admin) h["X-WuMind-Admin-Secret"] = env.ADMIN_SECRET;
    if (body !== null) h["Content-Type"] = "application/json";
    return worker.fetch(new Request(`https://gateway.test${p}`, {
      method,
      headers: h,
      body: body !== null ? JSON.stringify(body) : undefined,
    }), env, { waitUntil() {} });
  };

  // --- Test 1: /health version & untouched billing switches ---
  const healthRes = await req("GET", "/health");
  assert.equal(healthRes.status, 200);
  const health = await healthRes.json();
  assert.equal(health.ok, true);
  assert.ok(String(health.gatewayVersion).includes("image-dual-route"));
  assert.equal(health.autoCreditPaused, true);
  assert.equal(health.appleProductionIAPEnabled, false);

  // --- Test 2: Discover, price, probe (INDEPENDENTLY testing BOTH T2I + Edit!) & enable GPT Image + Nano Banana 2 ---
  const discoverRes = await req("POST", "/v1/admin/models/discover", { admin: true, body: { provider: "aihubmix" } });
  assert.equal(discoverRes.status, 200);

  const approvePricingRes = await req("POST", "/v1/admin/pricing/approve", {
    admin: true,
    body: { fxUsdToCny: 7.25, markupMultiplier: 1.5, operatorID: "qa-bot" },
  });
  assert.equal(approvePricingRes.status, 200);

  observedUpstream.length = 0;
  const probeRes = await req("POST", "/v1/admin/models/probe", {
    admin: true,
    body: { modelIDs: ["gpt-image-1.5", "gpt-image-2", "gemini-3.1-flash-image"] },
  });
  assert.equal(probeRes.status, 200);
  const probeData = await probeRes.json();
  // Each dual-capability model MUST execute BOTH T2I and Reference-Image Edit probes (3 models × 2 probes = 6 upstream calls!)
  assert.equal(observedUpstream.length, 6, "Dual-capability image models MUST probe BOTH text_to_image AND image_edit independently");
  for (const r of probeData.results) {
    assert.equal(r.probeStatus, "verified", `Expected ${r.id} probe verified, got ${JSON.stringify(r)}`);
    assert.deepEqual(r.verifiedCapabilities, ["text_to_image", "image_edit"]);
    assert.equal(r.capabilityProbes?.text_to_image?.verified, true);
    assert.equal(r.capabilityProbes?.text_to_image?.width, 8);
    assert.equal(r.capabilityProbes?.text_to_image?.height, 8);
    assert.equal(r.capabilityProbes?.image_edit?.verified, true);
    assert.equal(r.capabilityProbes?.image_edit?.width, 8);
    assert.equal(r.capabilityProbes?.image_edit?.height, 8);
  }
  const nbProbe = probeData.results.find((r) => r.id === "gemini-3.1-flash-image");
  assert.ok(nbProbe.probeEndpoint.includes("/gemini/v1beta/models/gemini-3.1-flash-image:generateContent"));

  const enableRes = await req("POST", "/v1/admin/models/batch-update", {
    admin: true,
    body: {
      updates: [
        { id: "gpt-image-1.5", enabled: true },
        { id: "gpt-image-2", enabled: true },
        { id: "gemini-3.1-flash-image", enabled: true },
      ],
    },
  });
  assert.equal(enableRes.status, 200);

  // Verify public callable image models contain friendly name & verified pricing
  const pubRes = await req("GET", "/v1/public/models?capability=text_to_image");
  const pubData = await pubRes.json();
  const pubNB = pubData.models.find((m) => m.id === "gemini-3.1-flash-image");
  const pubGPT2 = pubData.models.find((m) => m.id === "gpt-image-2");
  assert.ok(pubNB, "Nano Banana 2 should be in public callable image models");
  assert.equal(pubNB.displayName, "Nano Banana 2");
  assert.equal(pubNB.supportedParams.protocol, "aihubmix_gemini_image");
  assert.ok(pubNB.unitPriceYuan > 0);
  assert.ok(pubGPT2 && pubGPT2.unitPriceYuan > 0);
  assert.equal(pubData.models.some((m) => m.id === "gemini-3-pro-image"), false, "Disabled model must not appear in public models");

  // --- Test 3: Register ordinary user & grant ¥10 ---
  const regRes = await req("POST", "/v1/account/register", { body: { displayName: "画室测试员" } });
  assert.equal(regRes.status, 200);
  const reg = await regRes.json();
  const userToken = reg.userToken;
  const userID = reg.userID;

  const topupRes = await req("POST", "/v1/admin/topup", {
    admin: true,
    body: { userID, amountYuan: 10.0, environment: "production", note: "QA ¥10 余额", operatorID: "qa-admin", idempotencyKey: "topup-img-10" },
  });
  assert.equal(topupRes.status, 200);

  const countLedger = () => sqlite.prepare("SELECT COUNT(*) AS c FROM ledger WHERE user_id = ? AND kind IN ('image','image_edit')").get(userID).c;
  const getUserRow = () => sqlite.prepare("SELECT balance_micros, reserved_micros FROM users WHERE id = ?").get(userID);

  // 3A. GPT Image 2 T2I
  const gptT2IRes = await req("POST", "/v1/images/generations", {
    token: userToken,
    headers: { "Idempotency-Key": "idem-gpt2-t2i-1" },
    body: { model: "gpt-image-2", prompt: "minimal wooden table", size: "1024x1024", quality: "medium", outputFormat: "png" },
  });
  assert.equal(gptT2IRes.status, 200);
  const gptT2I = await gptT2IRes.json();
  assert.equal(gptT2I.ok, true);
  assert.equal(gptT2I.route, "managed_gateway:openai_images");
  assert.ok(gptT2I.requestID.startsWith("REQ-"));
  assert.equal(gptT2I.data[0].b64_json, SAMPLE_PNG_B64);
  assert.equal(countLedger(), 1);
  assert.equal(getUserRow().reserved_micros, 0);

  // 3B. Nano Banana 2 T2I (via AIHubMix Gemini native :generateContent, zero local Gemini key!)
  const nbT2IRes = await req("POST", "/v1/images/generations", {
    token: userToken,
    headers: { "Idempotency-Key": "idem-nb2-t2i-1" },
    body: { model: "gemini-3.1-flash-image", prompt: "minimal origami crane", aspectRatio: "16:9", quality: "high" },
  });
  assert.equal(nbT2IRes.status, 200);
  const nbT2I = await nbT2IRes.json();
  assert.equal(nbT2I.ok, true);
  assert.equal(nbT2I.route, "managed_gateway:aihubmix_gemini_image");
  assert.equal(nbT2I.data[0].b64_json, SAMPLE_PNG_B64);
  assert.equal(countLedger(), 2);
  assert.equal(getUserRow().reserved_micros, 0);

  // 3C. GPT Image 1.5 Reference-Image Edit (multipart /v1/images/edits)
  const gptEditRes = await req("POST", "/v1/images/edits", {
    token: userToken,
    headers: { "Idempotency-Key": "idem-gpt15-edit-1" },
    body: {
      model: "gpt-image-1.5",
      prompt: "change background to sunset",
      referenceImage: { base64Data: SAMPLE_PNG_B64, mimeType: "image/png", filename: "ref.png" },
    },
  });
  assert.equal(gptEditRes.status, 200);
  const gptEdit = await gptEditRes.json();
  assert.equal(gptEdit.mode, "image_edit");
  assert.equal(countLedger(), 3);

  // 3D. Nano Banana 2 Reference-Image Edit (inline_data on :generateContent)
  observedUpstream.length = 0;
  const nbEditRes = await req("POST", "/v1/images/edits", {
    token: userToken,
    headers: { "Idempotency-Key": "idem-nb2-edit-1" },
    body: {
      model: "gemini-3.1-flash-image",
      prompt: "add warm studio rim light",
      aspectRatio: "4:3",
      referenceImage: { base64Data: SAMPLE_PNG_B64, mimeType: "image/png", filename: "ref.png" },
    },
  });
  assert.equal(nbEditRes.status, 200);
  const nbEdit = await nbEditRes.json();
  assert.equal(nbEdit.mode, "image_edit");
  assert.equal(nbEdit.route, "managed_gateway:aihubmix_gemini_image");
  const lastBody = JSON.parse(observedUpstream[0].bodyText);
  assert.equal(lastBody.contents[0].parts[0].inline_data.mime_type, "image/png");
  assert.equal(lastBody.contents[0].parts[0].inline_data.data, SAMPLE_PNG_B64);
  assert.equal(lastBody.generationConfig.imageConfig.aspectRatio, "4:3");
  assert.equal(countLedger(), 4);

  // --- Test 4: AIHubMix Unified Fallback (same-origin content_url OK, off-origin SSRF blocked) ---
  upstreamMode = "unified_content_url";
  const uniRes = await req("POST", "/v1/images/generations", {
    token: userToken,
    headers: { "Idempotency-Key": "idem-nb2-uni-1" },
    body: { model: "gemini-3.1-flash-image", prompt: "unified fallback test" },
  });
  assert.equal(uniRes.status, 200);
  const uni = await uniRes.json();
  assert.equal(uni.route, "managed_gateway:aihubmix_unified");
  assert.equal(uni.data[0].b64_json, SAMPLE_PNG_B64);
  assert.equal(countLedger(), 5);

  upstreamMode = "ssrf_content_url";
  const balBeforeSSRF = getUserRow().balance_micros;
  const ssrfRes = await req("POST", "/v1/images/generations", {
    token: userToken,
    headers: { "Idempotency-Key": "idem-nb2-ssrf-1" },
    body: { model: "gemini-3.1-flash-image", prompt: "ssrf guard test" },
  });
  assert.equal(ssrfRes.status, 502);
  const ssrfBody = await ssrfRes.json();
  assert.equal(ssrfBody.code, "no_image");
  assert.equal(forbiddenHostCalled, false, "SSRF host must NEVER be fetched!");
  assert.equal(getUserRow().balance_micros, balBeforeSSRF, "Blocked SSRF response must NOT charge user!");
  assert.equal(getUserRow().reserved_micros, 0);

  // --- Test 5: Large (>500KB) Idempotent Retry — Upstream Called ONCE, Settled ONCE ---
  upstreamMode = "large_payload";
  observedUpstream.length = 0;
  const balBeforeLarge = getUserRow().balance_micros;
  const firstLargeRes = await req("POST", "/v1/images/generations", {
    token: userToken,
    headers: { "Idempotency-Key": "idem-large-retry-1" },
    body: { model: "gemini-3.1-flash-image", prompt: "large payload idempotency test" },
  });
  assert.equal(firstLargeRes.status, 200);
  const firstLarge = await firstLargeRes.json();
  assert.equal(firstLarge.data[0].b64_json, LARGE_PNG_B64);
  const balAfterFirstLarge = getUserRow().balance_micros;
  assert.ok(balAfterFirstLarge < balBeforeLarge);
  assert.equal(observedUpstream.length, 1);

  // Retry with SAME Idempotency-Key
  const retryLargeRes = await req("POST", "/v1/images/generations", {
    token: userToken,
    headers: { "Idempotency-Key": "idem-large-retry-1" },
    body: { model: "gemini-3.1-flash-image", prompt: "large payload idempotency test" },
  });
  assert.equal(retryLargeRes.status, 200);
  const retryLarge = await retryLargeRes.json();
  assert.equal(retryLarge.idempotentReplay, true);
  assert.equal(retryLarge.data[0].b64_json, LARGE_PNG_B64);
  assert.ok(retryLarge.billing && typeof retryLarge.billing.balanceYuan === "number");
  assert.equal(observedUpstream.length, 1, "Idempotent retry MUST NOT call upstream a second time!");
  assert.equal(getUserRow().balance_micros, balAfterFirstLarge, "Idempotent retry MUST NOT double-charge!");
  assert.equal(countLedger(), 6);

  // --- Test 6: Strict Error Classifications (model_not_enabled, upstream_auth_failed, upstream_balance_insufficient, insufficient_balance) ---
  observedUpstream.length = 0;
  const disabledRes = await req("POST", "/v1/images/generations", {
    token: userToken,
    body: { model: "gemini-3-pro-image", prompt: "disabled model test" },
  });
  assert.equal(disabledRes.status, 403);
  const disabled = await disabledRes.json();
  assert.equal(disabled.code, "model_not_enabled");
  assert.equal(observedUpstream.length, 0);

  upstreamMode = "upstream_401";
  const balBeforeAuth = getUserRow().balance_micros;
  const authFailRes = await req("POST", "/v1/images/generations", {
    token: userToken,
    headers: { "Idempotency-Key": "idem-up-auth-fail" },
    body: { model: "gemini-3.1-flash-image", prompt: "auth failure test" },
  });
  assert.equal(authFailRes.status, 502, "Upstream 401 must map to 502 so client WuMind session is not revoked");
  const authFail = await authFailRes.json();
  assert.equal(authFail.code, "upstream_auth_failed");
  assert.equal(authFail.billingResult, "released_no_charge");
  assert.equal(getUserRow().balance_micros, balBeforeAuth);
  assert.equal(getUserRow().reserved_micros, 0);

  upstreamMode = "upstream_balance";
  const balFailRes = await req("POST", "/v1/images/generations", {
    token: userToken,
    headers: { "Idempotency-Key": "idem-up-bal-fail" },
    body: { model: "gemini-3.1-flash-image", prompt: "upstream quota test" },
  });
  assert.equal(balFailRes.status, 502);
  const balFail = await balFailRes.json();
  assert.equal(balFail.code, "upstream_balance_insufficient");
  assert.equal(getUserRow().balance_micros, balBeforeAuth);
  assert.equal(getUserRow().reserved_micros, 0);

  // Zero-balance user -> 402 insufficient_balance, 0 upstream calls
  const zeroReg = await (await req("POST", "/v1/account/register", { body: { displayName: "零余额" } })).json();
  observedUpstream.length = 0;
  const zeroRes = await req("POST", "/v1/images/generations", {
    token: zeroReg.userToken,
    body: { model: "gemini-3.1-flash-image", prompt: "zero balance test" },
  });
  assert.equal(zeroRes.status, 402);
  const zeroBody = await zeroRes.json();
  assert.equal(zeroBody.code, "insufficient_balance");
  assert.equal(observedUpstream.length, 0);

  // --- Regression Test ③: Independent T2I vs Reference-Image Edit Verification & Displayable Binary Guard ---

  // 3E. Runtime HTTP 200 with truncated/undecodable PNG MUST be rejected as invalid_image_payload (0 charge!)
  upstreamMode = "corrupt_image";
  const balBeforeCorrupt = getUserRow().balance_micros;
  const corruptRunRes = await req("POST", "/v1/images/generations", {
    token: userToken,
    headers: { "Idempotency-Key": "idem-corrupt-runtime-1" },
    body: { model: "gemini-3.1-flash-image", prompt: "corrupt runtime test" },
  });
  assert.equal(corruptRunRes.status, 502);
  const corruptRun = await corruptRunRes.json();
  assert.equal(corruptRun.code, "invalid_image_payload");
  assert.equal(corruptRun.billingResult, "released_no_charge");
  assert.equal(getUserRow().balance_micros, balBeforeCorrupt);
  assert.equal(getUserRow().reserved_micros, 0);

  // 3B. Probe when image_edit returns valid PNG (HTTP 200) BUT text_to_image returns HTTP 200 text-only / corrupt base64!
  //     MUST NOT mark text_to_image verified! MUST exclude from ?capability=text_to_image & reject POST /v1/images/generations!
  upstreamMode = "t2i_text_only_edit_ok";
  const partialT2IProbeRes = await req("POST", "/v1/admin/models/probe", {
    admin: true,
    body: { modelIDs: ["gemini-3.1-flash-image", "gpt-image-2"] },
  });
  assert.equal(partialT2IProbeRes.status, 200);
  const partialT2IProbe = await partialT2IProbeRes.json();
  for (const r of partialT2IProbe.results) {
    assert.equal(r.probeStatus, "verified", "Edit passed so row stays verified ONLY for image_edit");
    assert.equal(r.capabilityProbes?.text_to_image?.verified, false, `${r.id} T2I returned non-image HTTP 200 and MUST fail verification`);
    assert.equal(r.capabilityProbes?.image_edit?.verified, true, `${r.id} image_edit returned valid 8x8 PNG and passes`);
    assert.deepEqual(r.capabilities, ["image_edit"], `${r.id} MUST NOT expose unverified text_to_image`);
    assert.deepEqual(r.verifiedCapabilities, ["image_edit"]);
  }

  const pubT2IAfterPartial = await (await req("GET", "/v1/public/models?capability=text_to_image")).json();
  assert.equal(pubT2IAfterPartial.models.some((m) => m.id === "gemini-3.1-flash-image"), false, "Model with failed T2I must NOT appear under text_to_image");
  assert.equal(pubT2IAfterPartial.models.some((m) => m.id === "gpt-image-2"), false, "GPT Image 2 with corrupt T2I must NOT appear under text_to_image");

  observedUpstream.length = 0;
  const blockedT2IRes = await req("POST", "/v1/images/generations", {
    token: userToken,
    body: { model: "gemini-3.1-flash-image", prompt: "must block unverified T2I" },
  });
  assert.equal(blockedT2IRes.status, 400);
  const blockedT2I = await blockedT2IRes.json();
  assert.equal(blockedT2I.code, "text_to_image_not_verified");
  assert.equal(observedUpstream.length, 0, "Blocked unverified T2I must not call upstream");

  // 3C. Reverse partial: text_to_image returns valid PNG (HTTP 200), BUT image_edit returns HTTP 200 corrupt/truncated PNG!
  //     MUST mark image_edit verified=false, supportsReferenceImage=false, and block POST /v1/images/edits!
  upstreamMode = "t2i_ok_edit_corrupt";
  const partialEditProbeRes = await req("POST", "/v1/admin/models/probe", {
    admin: true,
    body: { modelIDs: ["gemini-3.1-flash-image", "gpt-image-2"] },
  });
  assert.equal(partialEditProbeRes.status, 200);
  const partialEditProbe = await partialEditProbeRes.json();
  for (const r of partialEditProbe.results) {
    assert.equal(r.capabilityProbes?.text_to_image?.verified, true);
    assert.equal(r.capabilityProbes?.image_edit?.verified, false);
    assert.deepEqual(r.capabilities, ["text_to_image"]);
    assert.equal(r.supportsReferenceImage, false);
  }
  observedUpstream.length = 0;
  const blockedEditRes = await req("POST", "/v1/images/edits", {
    token: userToken,
    body: {
      model: "gemini-3.1-flash-image",
      prompt: "must block unverified edit",
      referenceImage: { base64Data: SAMPLE_PNG_B64, mimeType: "image/png", filename: "ref.png" },
    },
  });
  assert.equal(blockedEditRes.status, 400);
  const blockedEdit = await blockedEditRes.json();
  assert.equal(blockedEdit.code, "reference_image_not_supported");
  assert.equal(observedUpstream.length, 0);

  // 3D. Both T2I and image_edit return HTTP 200 with truncated/corrupt bytes -> probeStatus MUST NOT be verified & model auto-disabled!
  upstreamMode = "both_corrupt";
  const bothCorruptRes = await req("POST", "/v1/admin/models/probe", {
    admin: true,
    body: { modelIDs: ["gemini-3.1-flash-image"] },
  });
  assert.equal(bothCorruptRes.status, 200);
  const bothCorrupt = (await bothCorruptRes.json()).results[0];
  assert.notEqual(bothCorrupt.probeStatus, "verified", "HTTP 200 with undecodable images MUST NEVER be marked verified!");
  assert.equal(bothCorrupt.enabled, false, "Failed probe MUST auto-disable model!");
  assert.deepEqual(bothCorrupt.verifiedCapabilities, []);

  console.log("PASS: All Managed Image Studio dual-protocol, independent T2I vs Reference-Edit displayable-image verification, unified fallback, SSRF guard, large-payload idempotency & error classification tests succeeded.");
} finally {
  globalThis.fetch = originalFetch;
}
