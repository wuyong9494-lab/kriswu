#!/usr/bin/env node
/**
 * Automated Verification Suite for Live 2026 Multi-Vendor Video Protocols on WUMIND Gateway:
 *  1. Google Gemini Omni 1.2 Flash (`gemini-omni-1.2-flash`):
 *     - Classified as `video` with `protocol: "gemini_interactions"` (NEVER misclassified as chat!)
 *     - Probed via `POST /v1beta/interactions`
 *     - Full create -> poll `GET /v1beta/interactions/{id}` -> download inline base64 MP4 with `ftyp` check!
 *  2. AIHubMix Kling v3 Omni (`kling-v3-omni`):
 *     - Uses Kling schema (`mode`, `aspect_ratio`, `duration`, `sound`, NO `size`!) on both probe and create.
 *  3. AIHubMix `/ai/v1/videos` Auto-Upgrade (`doubao-seedance-2-0-fast-260128`):
 *     - When `/v1/videos` returns HTTP 400 `protocol_not_supported` (`Use POST /ai/v1/videos`),
 *       automatically upgrades to `POST /ai/v1/videos`, polls `GET /ai/v1/videos/{id}`, and downloads `GET /ai/v1/videos/{id}/content`!
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

function makeSampleMP4() {
  const buf = new Uint8Array(64);
  buf.set([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d], 0);
  return buf;
}

const SAMPLE_MP4 = makeSampleMP4();
const SAMPLE_MP4_B64 = Buffer.from(SAMPLE_MP4).toString("base64");

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

  const observedCalls = [];

  globalThis.fetch = async (input, init = {}) => {
    const url = typeof input === "string" ? input : input.url;
    const method = (init.method || "GET").toUpperCase();
    const bodyText = init.body ? String(init.body) : "";
    observedCalls.push({ method, url, body: bodyText });

    // Discover endpoints
    if (url === "https://aihubmix.com/v1/models" && method === "GET") {
      return new Response(JSON.stringify({
        data: [
          { id: "wan2.6-t2v" },
          { id: "kling-v3-omni" },
          { id: "doubao-seedance-2-0-fast-260128" },
        ],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (url.startsWith("https://generativelanguage.googleapis.com/v1beta/models") && method === "GET") {
      return new Response(JSON.stringify({
        models: [
          { name: "models/gemini-2.5-flash", displayName: "Gemini 2.5 Flash" },
          { name: "models/gemini-omni-1.2-flash", displayName: "Gemini Omni 1.2 Flash" },
        ],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    // 1. Google Gemini Interactions API
    if (url === "https://generativelanguage.googleapis.com/v1beta/interactions" && method === "POST") {
      const parsed = JSON.parse(bodyText);
      assert.equal(parsed.model, "gemini-omni-1.2-flash");
      assert.equal(parsed.response_format?.type, "video");
      return new Response(JSON.stringify({
        id: "v1_omni_job_9",
        status: "in_progress",
        steps: [],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (url === "https://generativelanguage.googleapis.com/v1beta/interactions/v1_omni_job_9" && method === "GET") {
      return new Response(JSON.stringify({
        id: "v1_omni_job_9",
        status: "completed",
        steps: [
          {
            type: "model_output",
            content: [{ type: "video", mime_type: "video/mp4", data: SAMPLE_MP4_B64 }],
          },
        ],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    // 2. AIHubMix /v1/videos (Kling succeeds; Seedance instructs /ai/v1/videos upgrade)
    if (url === "https://aihubmix.com/v1/videos" && method === "POST") {
      const parsed = JSON.parse(bodyText);
      if (parsed.model === "kling-v3-omni") {
        assert.equal(parsed.size, undefined, "Kling MUST NOT send size field");
        assert.ok(["std", "pro"].includes(parsed.mode));
        assert.equal(parsed.aspect_ratio, "16:9");
        assert.equal(parsed.duration, "5");
        return new Response(JSON.stringify({ id: "kling_99", status: "completed" }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }
      if (parsed.model === "doubao-seedance-2-0-fast-260128") {
        return new Response(JSON.stringify({
          error: {
            code: "protocol_not_supported",
            message: "This model does not support the legacy protocol. Use POST /ai/v1/videos.",
          },
        }), { status: 400, headers: { "Content-Type": "application/json" } });
      }
      assert.notEqual(parsed.model, "wan2.6-t2v", "Wan must not use the legacy route");
      return new Response(JSON.stringify({ id: "wan_1", status: "completed" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 3. AIHubMix unified /ai/v1/videos
    if (url === "https://aihubmix.com/ai/v1/videos" && method === "POST") {
      const parsed = JSON.parse(bodyText);
      if (parsed.model === "wan2.6-t2v") {
        assert.equal(parsed.duration, 5);
        assert.equal(parsed.size, "1280x720");
        assert.equal(parsed.seconds, undefined);
        assert.equal(parsed.resolution, undefined);
        const disabled = parsed.prompt === "wan async disabled";
        return Response.json(disabled
          ? { error: { code: "async_not_enabled", message: "current user api does not support asynchronous calls" } }
          : { id: "task_wan_42", status: "in_progress" }, { status: disabled ? 403 : 200 });
      }

      assert.equal(parsed.model, "doubao-seedance-2-0-fast-260128");
      assert.equal(parsed.duration, 5);
      return new Response(JSON.stringify({ id: "v2_seed_42", status: "in_progress" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
    if (url === "https://aihubmix.com/ai/v1/videos/task_wan_42" && method === "GET") {
      return Response.json({ id: "task_wan_42", status: "completed" });
    }
    if (url === "https://aihubmix.com/ai/v1/videos/task_wan_42/content" && method === "GET") {
      return new Response(SAMPLE_MP4, { headers: { "Content-Type": "video/mp4" } });
    }
    if (url === "https://aihubmix.com/ai/v1/videos/v2_seed_42" && method === "GET") {
      return new Response(JSON.stringify({ id: "v2_seed_42", status: "completed", progress: 100 }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
    if (url === "https://aihubmix.com/ai/v1/videos/v2_seed_42/content" && method === "GET") {
      return new Response(SAMPLE_MP4, { status: 200, headers: { "Content-Type": "video/mp4" } });
    }
    if (url === "https://aihubmix.com/v1/videos/kling_99/content" && method === "GET") {
      return new Response(SAMPLE_MP4, { status: 200, headers: { "Content-Type": "video/mp4" } });
    }

    return new Response(JSON.stringify({ error: `unexpected mock call: ${method} ${url}` }), { status: 404 });
  };

  const env = {
    DB,
    ADMIN_SECRET: "adm_secret_2026",
    AIHUBMIX_API_KEY: "sk-aihubmix-test",
    GEMINI_API_KEY: "AIza-gemini-test",
    WELCOME_BONUS_YUAN: "0",
    AUTO_CREDIT_PAUSED: "true",
    ALLOW_APPLE_PRODUCTION_IAP: "false",
  };

  async function call(method, route, body = null, headers = {}) {
    const req = new Request(`https://gw.test${route}`, {
      method,
      headers: { ...(body ? { "Content-Type": "application/json" } : {}), ...headers },
      body: body ? JSON.stringify(body) : undefined,
    });
    const res = await worker.fetch(req, env);
    const ct = res.headers.get("Content-Type") || "";
    if (ct.includes("video/mp4")) {
      return { status: res.status, bytes: new Uint8Array(await res.arrayBuffer()) };
    }
    return { status: res.status, data: await res.json() };
  }

  const adminHdr = { "X-WuMind-Admin-Secret": "adm_secret_2026" };

  // Register user & fund with ¥50 via admin grant
  const reg = await call("POST", "/v1/account/register", { displayName: "视频测试用户" });
  assert.equal(reg.status, 200);
  const authHdr = { Authorization: `Bearer ${reg.data.userToken}` };
  await call("POST", "/v1/admin/topup", {
    userID: reg.data.userID,
    amountYuan: 50,
    environment: "production",
    idempotencyKey: "vid-fund-1",
  }, adminHdr);

  // Discover both AIHubMix + Gemini catalogs
  const disc = await call("POST", "/v1/admin/models/discover", { providers: ["aihubmix", "gemini"] }, adminHdr);
  assert.equal(disc.status, 200);
  const omniRow = disc.data.models.find((m) => m.id === "gemini-omni-1.2-flash");
  assert.ok(omniRow, "gemini-omni-1.2-flash must be discovered");
  assert.deepEqual(omniRow.capabilities, ["video"]);
  assert.equal(omniRow.supportedParams.protocol, "gemini_interactions");

  const klingRow = disc.data.models.find((m) => m.id === "kling-v3-omni");
  assert.ok(klingRow);
  assert.equal(klingRow.supportedParams.protocol, "aihubmix_kling");

  const seedRow = disc.data.models.find((m) => m.id === "doubao-seedance-2-0-fast-260128");
  assert.ok(seedRow);
  assert.equal(seedRow.supportedParams.protocol, "aihubmix_seedance");

  // Probe all three live video models (verifies Interactions, Kling schema, and /ai/v1/videos auto-upgrade!)
  const probe = await call("POST", "/v1/admin/models/probe", {
    modelIDs: ["gemini-omni-1.2-flash", "kling-v3-omni", "doubao-seedance-2-0-fast-260128", "wan2.6-t2v"],
  }, adminHdr);
  assert.equal(probe.status, 200);
  for (const r of probe.data.results) {
    assert.equal(r.probeStatus, "verified", `Expected ${r.id} verified, got ${r.probeStatus}: ${r.probeMessage}`);
  }
  const seedProbe = probe.data.results.find((r) => r.id === "doubao-seedance-2-0-fast-260128");
  assert.equal(seedProbe.probeEndpoint, "https://aihubmix.com/ai/v1/videos");

  // Price & enable all three
  const batch = await call("POST", "/v1/admin/models/batch-update", {
    updates: [
      { id: "gemini-omni-1.2-flash", unitPriceYuan: 0.6, enabled: true },
      { id: "kling-v3-omni", unitPriceYuan: 0.8, enabled: true },
      { id: "wan2.6-t2v", unitPriceYuan: 0.8, enabled: true },
      { id: "doubao-seedance-2-0-fast-260128", unitPriceYuan: 0.5, enabled: true },
    ],
  }, adminHdr);
  assert.equal(batch.status, 200);
  assert.equal(batch.data.appliedCount, 4);

  // Execute end-to-end Google Gemini Omni 1.2 Flash video flow
  const omniCreate = await call("POST", "/v1/videos", {
    model: "gemini-omni-1.2-flash",
    prompt: "海浪轻拍金色沙滩",
    seconds: "5",
    size: "1280x720",
  }, { ...authHdr, "Idempotency-Key": "omni-1" });
  assert.equal(omniCreate.status, 200);
  assert.equal(omniCreate.data.endpoint, "https://generativelanguage.googleapis.com/v1beta/interactions");

  const omniPoll = await call("GET", `/v1/videos/${omniCreate.data.id}`, null, authHdr);
  assert.equal(omniPoll.status, 200);
  assert.equal(omniPoll.data.status, "completed");

  const omniDl = await call("GET", `/v1/videos/${omniCreate.data.id}/content`, null, authHdr);
  assert.equal(omniDl.status, 200);
  assert.deepEqual(Buffer.from(omniDl.bytes), Buffer.from(SAMPLE_MP4));

  // Execute end-to-end AIHubMix Seedance with automatic /ai/v1/videos upgrade -> poll -> content
  const seedCreate = await call("POST", "/v1/videos", {
    model: "doubao-seedance-2-0-fast-260128",
    prompt: "城市航拍黄昏车流",
    seconds: "5",
    size: "1280x720",
  }, { ...authHdr, "Idempotency-Key": "seed-1" });
  assert.equal(seedCreate.status, 200);
  assert.equal(seedCreate.data.endpoint, "https://aihubmix.com/ai/v1/videos");

  const seedPoll = await call("GET", `/v1/videos/${seedCreate.data.id}`, null, authHdr);
  assert.equal(seedPoll.status, 200);
  assert.equal(seedPoll.data.status, "completed");

  const seedDl = await call("GET", `/v1/videos/${seedCreate.data.id}/content`, null, authHdr);
  assert.equal(seedDl.status, 200);
  assert.deepEqual(Buffer.from(seedDl.bytes), Buffer.from(SAMPLE_MP4));

  const wanBody = { model: "wan2.6-t2v", prompt: "wan success", seconds: "5", size: "1280x720" };
  const wanCreate = await call("POST", "/v1/videos", wanBody, { ...authHdr, "Idempotency-Key": "wan-1" });
  assert.equal(wanCreate.status, 200);
  assert.equal(wanCreate.data.endpoint, "https://aihubmix.com/ai/v1/videos");
  const wanPoll = await call("GET", `/v1/videos/${wanCreate.data.id}`, null, authHdr);
  assert.equal(wanPoll.data.status, "completed");
  const wanDownload = await call("GET", `/v1/videos/${wanCreate.data.id}/content`, null, authHdr);
  assert.deepEqual(Buffer.from(wanDownload.bytes), Buffer.from(SAMPLE_MP4));
  const disabled = await call("POST", "/v1/videos", { ...wanBody, prompt: "wan async disabled" },
    { ...authHdr, "Idempotency-Key": "wan-403" });
  assert.equal(disabled.status, 403);
  assert.equal(disabled.data.code, "upstream_async_not_enabled");
  assert.equal(observedCalls.filter((c) => c.method === "POST" && c.body.includes("wan async disabled")).length, 1);

  // Execute Kling v3 Omni create + content
  const klingCreate = await call("POST", "/v1/videos", {
    model: "kling-v3-omni",
    prompt: "清晨竹林微风吹拂",
    seconds: "5",
    size: "1920x1080",
  }, { ...authHdr, "Idempotency-Key": "kling-1" });
  assert.equal(klingCreate.status, 200);
  const klingDl = await call("GET", `/v1/videos/${klingCreate.data.id}/content`, null, authHdr);
  assert.equal(klingDl.status, 200);
  assert.deepEqual(Buffer.from(klingDl.bytes), Buffer.from(SAMPLE_MP4));

  console.log("PASS: All 2026 Video Protocol tests (Gemini Omni 1.2 Flash Interactions, AIHubMix Kling v3 Omni, and /ai/v1/videos auto-upgrade) succeeded.");
} finally {
  globalThis.fetch = originalFetch;
}
