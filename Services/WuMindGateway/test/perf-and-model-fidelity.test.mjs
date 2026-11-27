import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";

import worker from "../src/index.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCHEMA_SQL = fs.readFileSync(path.join(__dirname, "..", "schema.sql"), "utf8");

function createD1Mock() {
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec(SCHEMA_SQL);
  const makeStmt = (sql) => {
    let args = [];
    const stmt = {
      bind(...params) {
        args = params.map((p) => (p === undefined ? null : p));
        return stmt;
      },
      async first() {
        return sqlite.prepare(sql).get(...args) ?? null;
      },
      async all() {
        return { results: sqlite.prepare(sql).all(...args) };
      },
      async run() {
        const res = sqlite.prepare(sql).run(...args);
        return { success: true, meta: { changes: res.changes, last_row_id: res.lastInsertRowid } };
      },
    };
    return stmt;
  };
  return {
    sqlite,
    prepare: makeStmt,
    async batch(stmts) {
      const out = [];
      for (const s of stmts) out.push(await s.run());
      return out;
    },
    async exec(sql) {
      sqlite.exec(sql);
    },
  };
}

function makeDelayedSSE(chunks, delayMs = 35) {
  const encoder = new TextEncoder();
  return new ReadableStream({
    async start(controller) {
      for (let i = 0; i < chunks.length; i++) {
        if (i > 0 && delayMs > 0) {
          await new Promise((r) => setTimeout(r, delayMs));
        }
        controller.enqueue(encoder.encode(chunks[i]));
      }
      controller.close();
    },
  });
}

async function readSSEWithTiming(res) {
  const started = performance.now();
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  let trace = null;
  let billing = null;
  let reasoning = "";
  let content = "";
  let firstChunkMs = null;
  let firstAnswerMs = null;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    const lines = buf.split("\n");
    buf = lines.pop() || "";
    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line.startsWith("data:")) continue;
      const payload = line.slice(5).trim();
      if (!payload || payload === "[DONE]") continue;
      const obj = JSON.parse(payload);
      if (obj.wumind_trace) trace = obj.wumind_trace;
      if (obj.wumind_billing) billing = obj.wumind_billing;
      if (obj.reasoning) {
        if (firstChunkMs === null) firstChunkMs = Math.round(performance.now() - started);
        reasoning += obj.reasoning;
      }
      if (obj.content) {
        if (firstChunkMs === null) firstChunkMs = Math.round(performance.now() - started);
        if (firstAnswerMs === null) firstAnswerMs = Math.round(performance.now() - started);
        content += obj.content;
      }
    }
  }
  const totalMs = Math.round(performance.now() - started);
  return { trace, billing, reasoning, content, firstChunkMs, firstAnswerMs, totalMs };
}

function percentiles(arr) {
  const s = [...arr].sort((a, b) => a - b);
  const pick = (p) => s[Math.max(0, Math.min(s.length - 1, Math.ceil(p * s.length) - 1))];
  return { n: s.length, p50Ms: pick(0.5), p95Ms: pick(0.95), minMs: s[0], maxMs: s[s.length - 1] };
}

const tinyPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";

async function runTests() {
  const db = createD1Mock();
  const capturedUpstreamCalls = [];

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, init = {}) => {
    const u = String(url);
    const body = init.body ? JSON.parse(String(init.body)) : {};
    capturedUpstreamCalls.push({ url: u, headers: init.headers || {}, body });

    // 1. OpenAI / DeepSeek / Grok / AIHubMix SSE
    if (u.includes("/chat/completions")) {
      const model = body.model || "unknown";
      const input = body.messages?.at(-1)?.content;
      if (input === "test:upstream-interruption") {
        const bytes = new TextEncoder().encode('data: {"choices":[{"delta":{"content":"Only the first part."}}]}\n\n');
        let sent = false;
        return new Response(new ReadableStream({
          pull(controller) {
            if (!sent) {
              sent = true;
              controller.enqueue(bytes);
            } else {
              controller.error(new Error("mock upstream disconnected"));
            }
          },
        }), { headers: { "Content-Type": "text/event-stream" } });
      }
      const reported = input === "evidence:mismatch" ? "gpt-4o" : input === "evidence:missing" ? undefined : model;
      const chunks = [
        `data: ${JSON.stringify({ model: reported, choices: [{ delta: { reasoning_content: `[think:${model}] ` } }] })}\n\n`,
        `data: ${JSON.stringify({ choices: [{ delta: { content: "Part1-" } }] })}\n\n`,
        `data: ${JSON.stringify({ choices: [{ delta: { content: "Part2" } }] })}\n\n`,
        `data: ${JSON.stringify({ choices: [], usage: { prompt_tokens: 120, completion_tokens: 45, completion_tokens_details: { reasoning_tokens: 20 } } })}\n\n`,
        `data: [DONE]\n\n`,
      ];
      return new Response(makeDelayedSSE(chunks, 35), {
        status: 200,
        headers: { "Content-Type": "text/event-stream" },
      });
    }

    // 2. Claude Messages API TRUE SSE streaming
    if (u.includes("/v1/messages")) {
      assert.equal(body.stream, true, "Gateway MUST request stream: true from Claude Messages API");
      const chunks = [
        `event: message_start\ndata: ${JSON.stringify({ type: "message_start", message: { usage: { input_tokens: 150 } } })}\n\n`,
        `event: content_block_delta\ndata: ${JSON.stringify({ type: "content_block_delta", delta: { type: "thinking_delta", thinking: "ClaudeThinking..." } })}\n\n`,
        `event: content_block_delta\ndata: ${JSON.stringify({ type: "content_block_delta", delta: { type: "text_delta", text: "ClaudeStream1-" } })}\n\n`,
        `event: content_block_delta\ndata: ${JSON.stringify({ type: "content_block_delta", delta: { type: "text_delta", text: "ClaudeStream2" } })}\n\n`,
        `event: message_delta\ndata: ${JSON.stringify({ type: "message_delta", usage: { output_tokens: 60 } })}\n\n`,
        `data: [DONE]\n\n`,
      ];
      return new Response(makeDelayedSSE(chunks, 45), {
        status: 200,
        headers: { "Content-Type": "text/event-stream" },
      });
    }

    // 3. Gemini :streamGenerateContent?alt=sse TRUE SSE streaming
    if (u.includes(":streamGenerateContent")) {
      assert.ok(u.includes("alt=sse"), "Gateway MUST call Gemini :streamGenerateContent?alt=sse");
      const chunks = [
        `data: ${JSON.stringify({ candidates: [{ content: { parts: [{ thought: true, text: "GeminiThought..." }] } }] })}\n\n`,
        `data: ${JSON.stringify({ candidates: [{ content: { parts: [{ text: "GeminiStream1-" }] } }] })}\n\n`,
        `data: ${JSON.stringify({ candidates: [{ content: { parts: [{ text: "GeminiStream2" }] } }], usageMetadata: { promptTokenCount: 140, candidatesTokenCount: 55, thoughtsTokenCount: 30 } })}\n\n`,
      ];
      return new Response(makeDelayedSSE(chunks, 45), {
        status: 200,
        headers: { "Content-Type": "text/event-stream" },
      });
    }

    throw new Error(`Unexpected fetch URL: ${u}`);
  };

  try {
    const baseEnv = {
      DB: db,
      ADMIN_SECRET: "admin-secret-test",
      OPENAI_API_KEY: "sk-openai-test",
      DEEPSEEK_API_KEY: "sk-deepseek-test",
      CLAUDE_API_KEY: "sk-claude-test",
      GEMINI_API_KEY: "sk-gemini-test",
      GROK_API_KEY: "sk-grok-test",
      AIHUBMIX_API_KEY: "sk-aihubmix-test",
      AIHUBMIX_ALLOWED_MODELS: "deepseek-reasoner,gpt-5,claude-sonnet-4-20250514,gemini-2.5-pro,grok-4",
    };

    const call = async (method, urlPath, body = null, headers = {}, envOverride = null) => {
      const waitPromises = [];
      const ctx = { waitUntil: (p) => waitPromises.push(p) };
      const req = new Request(`https://wumind.test${urlPath}`, {
        method,
        headers: { "Content-Type": "application/json", ...headers },
        body: body ? JSON.stringify(body) : undefined,
      });
      const res = await worker.fetch(req, envOverride || baseEnv, ctx);
      return { res, waitPromises };
    };

    // Register & fund user
    const reg = await call("POST", "/v1/account/register", { displayName: "FidelityTester" });
    const regJSON = await reg.res.json();
    const userToken = regJSON.userToken;
    const userID = regJSON.userID || regJSON.account?.userID;
    assert.ok(userToken && userID, `register failed: ${JSON.stringify(regJSON)}`);
    const auth = { Authorization: `Bearer ${userToken}` };

    await call("POST", "/v1/admin/topup", {
      userID,
      amountYuan: 100,
      operatorID: "ops-kris",
      reason: "test",
      idempotencyKey: "topup-fidelity-1",
    }, { "X-WuMind-Admin-Secret": "admin-secret-test" });

    // Seed catalog entries for GPT-5, GPT-4o, DeepSeek Reasoner, Claude Sonnet 4, Gemini 2.5 Pro, Grok 4
    const models = [
      ["gpt-5", "openAI", "OpenAI", "GPT-5", 1, 20, 80],
      ["gpt-4o", "openAI", "OpenAI", "GPT-4o", 0, 18, 72],
      ["deepseek-reasoner", "deepSeek", "DeepSeek", "DeepSeek Reasoner", 1, 4, 16],
      ["claude-sonnet-4-20250514", "claude", "Anthropic", "Claude Sonnet 4", 1, 25, 110],
      ["gemini-2.5-pro", "gemini", "Google", "Gemini 2.5 Pro", 1, 12, 80],
      ["grok-4", "grok", "xAI", "Grok 4", 1, 24, 100],
    ];
    for (const [id, prov, vendor, name, think, inp, out] of models) {
      db.sqlite.prepare(
        `INSERT OR REPLACE INTO model_catalog (
           model_id, upstream_provider, vendor, display_name, capabilities_json,
           pricing_mode, input_price_per_million, output_price_per_million,
           supports_thinking, enabled, probe_status, pricing_status, deprecated
         ) VALUES (?, ?, ?, ?, '["chat"]', 'token', ?, ?, ?, 1, 'verified', 'priced', 0)`
      ).run(id, prov, vendor, name, inp, out, think);
    }

    // ------------------------------------------------------------------
    // SUITE 1: Strict Pre-Flight Honesty (ZERO Silent Image Drop / Thinking Off!)
    // ------------------------------------------------------------------
    const balBeforeRejects = (await (await call("GET", "/v1/account/me", null, auth)).res.json()).balanceYuan;

    // 1A. DeepSeek Reasoner + attached image -> MUST return 400 vision_not_supported, ¥0 charge, 0 upstream calls
    const beforeCalls = capturedUpstreamCalls.length;
    const dsImg = await call("POST", "/v1/chat/completions", {
      model: "deepseek-reasoner",
      deepThinking: true,
      messages: [{ role: "user", content: "看这张图", images: [{ mimeType: "image/png", base64Data: tinyPNG }] }],
    }, auth);
    assert.equal(dsImg.res.status, 400, "DeepSeek + image MUST be rejected explicitly, NOT silently dropped");
    const dsImgErr = await dsImg.res.json();
    assert.equal(dsImgErr.code, "vision_not_supported");
    assert.equal(capturedUpstreamCalls.length, beforeCalls, "No upstream call should occur when vision is unsupported");

    // 1B. GPT-4o (non-thinking) + deepThinking=true -> MUST return 400 thinking_not_supported, ¥0 charge
    const gpt4oThink = await call("POST", "/v1/chat/completions", {
      model: "gpt-4o",
      deepThinking: true,
      messages: [{ role: "user", content: "请深度思考" }],
    }, auth);
    assert.equal(gpt4oThink.res.status, 400, "Non-thinking model with deepThinking=true MUST reject instead of silently turning off thinking");
    const gpt4oErr = await gpt4oThink.res.json();
    assert.equal(gpt4oErr.code, "thinking_not_supported");
    assert.equal(capturedUpstreamCalls.length, beforeCalls);

    const balAfterRejects = (await (await call("GET", "/v1/account/me", null, auth)).res.json()).balanceYuan;
    assert.equal(balAfterRejects, balBeforeRejects, "Pre-flight capability rejections MUST cost ¥0");

    // ------------------------------------------------------------------
    // SUITE 2: Exact Wire Parameters & Multimodal Fidelity Across All 5 Families + AIHubMix
    // ------------------------------------------------------------------
    // 2A. Official GPT-5: reasoning_effort="high", max_completion_tokens, image_url intact
    const gpt5Call = await call("POST", "/v1/chat/completions", {
      model: "gpt-5",
      deepThinking: true,
      messages: [{ role: "user", content: "分析图片", images: [{ mimeType: "image/png", base64Data: tinyPNG }] }],
    }, { ...auth, "Idempotency-Key": "req-gpt5-1" });
    const gpt5Stream = await readSSEWithTiming(gpt5Call.res);
    await Promise.all(gpt5Call.waitPromises);
    const gpt5Wire = capturedUpstreamCalls.at(-1);
    assert.equal(gpt5Wire.body.model, "gpt-5");
    assert.equal(gpt5Wire.body.reasoning_effort, "high", "GPT-5 MUST receive reasoning_effort=high");
    assert.ok(typeof gpt5Wire.body.max_completion_tokens === "number" && gpt5Wire.body.max_tokens === undefined,
      "Direct OpenAI GPT-5 MUST use max_completion_tokens instead of max_tokens");
    assert.equal(gpt5Wire.body.messages[0].content[1].type, "image_url");
    assert.equal(gpt5Stream.trace.actualModel, "gpt-5");
    assert.equal(gpt5Stream.trace.providerReportedModel, "gpt-5");
    assert.equal(gpt5Stream.trace.reasoningObserved, true);
    assert.ok(gpt5Stream.firstAnswerMs > gpt5Stream.firstChunkMs, "reasoning must not count as first answer");
    for (const [kind, expected] of [["mismatch", "gpt-4o"], ["missing", undefined]]) {
      const evidence = await call("POST", "/v1/chat/completions", {
        model: "gpt-5", messages: [{ role: "user", content: `evidence:${kind}` }],
      }, { ...auth, "Idempotency-Key": `req-evidence-${kind}` });
      const stream = await readSSEWithTiming(evidence.res);
      await Promise.all(evidence.waitPromises);
      assert.equal(stream.trace.actualModel, "gpt-5");
      assert.equal(stream.trace.providerReportedModel, expected);
    }
    assert.equal(gpt5Stream.trace.imagesSent, 1);
    assert.equal(gpt5Stream.trace.thinkingParam, "reasoning_effort=high");

    // 2B. AIHubMix DeepSeek Reasoner (explicit upstream_provider='aihubmix') -> MUST still send thinking.type=enabled!
    db.sqlite.prepare(
      `UPDATE model_catalog SET upstream_provider = 'aihubmix' WHERE model_id = 'deepseek-reasoner'`
    ).run();
    const dsHubCall = await call("POST", "/v1/chat/completions", {
      model: "deepseek-reasoner",
      deepThinking: true,
      messages: [{ role: "user", content: "证明素数无穷多" }],
    }, { ...auth, "Idempotency-Key": "req-dshub-1" });
    assert.equal(dsHubCall.res.status, 200, "AIHubMix DeepSeek Reasoner should succeed with HTTP 200");
    const dsHubStream = await readSSEWithTiming(dsHubCall.res);
    await Promise.all(dsHubCall.waitPromises);
    const dsHubWire = capturedUpstreamCalls.at(-1);
    assert.equal(dsHubWire.body.model, "deepseek-reasoner");
    assert.deepEqual(dsHubWire.body.thinking, { type: "enabled" }, "AIHubMix DeepSeek MUST preserve thinking={type:enabled}");
    assert.equal(dsHubStream.trace.upstreamRoute, "aihubmix");
    assert.equal(dsHubStream.trace.thinkingParam, "thinking.type=enabled");

    // 2C. Grok 4: reasoning_effort="high" + image_url intact
    const grokCall = await call("POST", "/v1/chat/completions", {
      model: "grok-4",
      deepThinking: true,
      messages: [{ role: "user", content: "描述画面", images: [{ mimeType: "image/png", base64Data: tinyPNG }] }],
    }, { ...auth, "Idempotency-Key": "req-grok4-1" });
    const grokStream = await readSSEWithTiming(grokCall.res);
    await Promise.all(grokCall.waitPromises);
    const grokWire = capturedUpstreamCalls.at(-1);
    assert.equal(grokWire.body.reasoning_effort, "high");
    assert.equal(grokWire.body.messages[0].content[1].type, "image_url");
    assert.equal(grokStream.trace.imagesSent, 1);

    // ------------------------------------------------------------------
    // SUITE 3: Claude & Gemini TRUE Real-Time SSE Streaming (TTFT << Total Time!)
    // ------------------------------------------------------------------
    const claudeCall = await call("POST", "/v1/chat/completions", {
      model: "claude-sonnet-4-20250514",
      deepThinking: true,
      messages: [{ role: "user", content: "读图并推理", images: [{ mimeType: "image/png", base64Data: tinyPNG }] }],
    }, { ...auth, "Idempotency-Key": "req-claude-sse-1" });
    const claudeStream = await readSSEWithTiming(claudeCall.res);
    await Promise.all(claudeCall.waitPromises);
    assert.equal(claudeStream.reasoning, "ClaudeThinking...");
    assert.equal(claudeStream.content, "ClaudeStream1-ClaudeStream2");
    assert.equal(claudeStream.trace.imagesSent, 1);
    assert.ok(claudeStream.firstChunkMs < claudeStream.totalMs - 40,
      `Claude MUST stream first token immediately (TTFT=${claudeStream.firstChunkMs}ms << total=${claudeStream.totalMs}ms)`);

    const geminiCall = await call("POST", "/v1/chat/completions", {
      model: "gemini-2.5-pro",
      deepThinking: true,
      messages: [{ role: "user", content: "读图并思考", images: [{ mimeType: "image/png", base64Data: tinyPNG }] }],
    }, { ...auth, "Idempotency-Key": "req-gemini-sse-1" });
    const geminiStream = await readSSEWithTiming(geminiCall.res);
    await Promise.all(geminiCall.waitPromises);
    assert.equal(geminiStream.reasoning, "GeminiThought...");
    assert.equal(geminiStream.content, "GeminiStream1-GeminiStream2");
    assert.equal(geminiStream.trace.imagesSent, 1);
    assert.ok(geminiStream.firstChunkMs < geminiStream.totalMs - 30,
      `Gemini MUST stream first token immediately (TTFT=${geminiStream.firstChunkMs}ms << total=${geminiStream.totalMs}ms)`);

    // ------------------------------------------------------------------
    // SUITE 4: Network-Interruption Recovery (GET /v1/chat/recovery) — Zero Double Billing!
    // ------------------------------------------------------------------
    const balBeforeRecovery = (await (await call("GET", "/v1/account/me", null, auth)).res.json()).balanceYuan;
    const recSettled = await call("GET", "/v1/chat/recovery?clientRequestID=req-claude-sse-1", null, auth);
    assert.equal(recSettled.res.status, 200);
    const recJSON = await recSettled.res.json();
    assert.equal(recJSON.status, "settled");
    assert.equal(recJSON.safeToRetry, false);
    assert.equal(recJSON.recovered, true);
    assert.equal(recJSON.outputComplete, true);
    assert.equal(recJSON.content, "ClaudeStream1-ClaudeStream2");
    assert.equal(recJSON.reasoning, "ClaudeThinking...");

    // Replay same Idempotency-Key -> zero extra charge!
    const replayCall = await call("POST", "/v1/chat/completions", {
      model: "claude-sonnet-4-20250514",
      deepThinking: true,
      messages: [{ role: "user", content: "读图并推理", images: [{ mimeType: "image/png", base64Data: tinyPNG }] }],
    }, { ...auth, "Idempotency-Key": "req-claude-sse-1" });
    const replayStream = await readSSEWithTiming(replayCall.res);
    assert.equal(replayStream.trace.recoveredFromOriginalTask, true);
    assert.equal(replayStream.content, "ClaudeStream1-ClaudeStream2");
    const balAfterRecovery = (await (await call("GET", "/v1/account/me", null, auth)).res.json()).balanceYuan;
    assert.equal(balAfterRecovery, balBeforeRecovery, "Recovering or replaying settled task MUST charge ¥0 extra");

    const partialID = "req-interrupted-output";
    const partialCall = await call("POST", "/v1/chat/completions", {
      model: "deepseek-chat",
      messages: [{ role: "user", content: "test:upstream-interruption" }],
    }, { ...auth, "Idempotency-Key": partialID });
    const partialStream = await partialCall.res.text();
    assert.match(partialStream, /stream_interrupted/);
    await Promise.all(partialCall.waitPromises);
    const callsAfterPartial = capturedUpstreamCalls.length;
    const partialRecovery = await (await call("GET", `/v1/chat/recovery?clientRequestID=${partialID}`, null, auth)).res.json();
    assert.equal(partialRecovery.status, "settled");
    assert.equal(partialRecovery.outputComplete, false);
    assert.equal(partialRecovery.content, "Only the first part.");
    assert.equal(partialRecovery.safeToRetry, false);
    assert.equal(capturedUpstreamCalls.length, callsAfterPartial, "Status lookup must not repeat the model call");

    // Unknown task -> safeToRetry: true
    const recMissing = await (await call("GET", "/v1/chat/recovery?clientRequestID=never-sent-xyz", null, auth)).res.json();
    assert.equal(recMissing.status, "not_found");
    assert.equal(recMissing.safeToRetry, true);

    // ------------------------------------------------------------------
    // SUITE 5: Controlled P50 / P95 Overhead Benchmark (WuMind Gateway SSE vs Direct Upstream)
    // ------------------------------------------------------------------
    const directClaudeTTFT = [];
    const gatewayClaudeTTFT = [];
    const gatewayClaudePrep = [];
    const legacyBufferedTTFT = [];

    for (let i = 0; i < 12; i++) {
      // Direct upstream SSE call baseline
      const dStart = performance.now();
      const dRes = await globalThis.fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        body: JSON.stringify({ model: "claude-sonnet-4-20250514", stream: true }),
      });
      const dReader = dRes.body.getReader();
      let dFirst = null;
      while (true) {
        const { done } = await dReader.read();
        if (done) break;
        if (dFirst === null) dFirst = Math.round(performance.now() - dStart);
      }
      const dTotal = Math.round(performance.now() - dStart);
      directClaudeTTFT.push(dFirst);
      legacyBufferedTTFT.push(dTotal); // Old non-streaming gateway waited for full stream completion!

      // WuMind Gateway SSE streaming call
      const gCall = await call("POST", "/v1/chat/completions", {
        model: "claude-sonnet-4-20250514",
        deepThinking: false,
        messages: [{ role: "user", content: `bench-${i}` }],
      }, { ...auth, "Idempotency-Key": `bench-claude-${i}` });
      const gOut = await readSSEWithTiming(gCall.res);
      await Promise.all(gCall.waitPromises);
      gatewayClaudeTTFT.push(gOut.firstChunkMs);
      gatewayClaudePrep.push(gOut.trace.gatewayPrepMs);
    }

    const benchSummary = {
      directUpstreamSSE: percentiles(directClaudeTTFT),
      legacyBufferedGateway: percentiles(legacyBufferedTTFT),
      wumindStreamingGateway: percentiles(gatewayClaudeTTFT),
      wumindGatewayPrepOnly: percentiles(gatewayClaudePrep),
    };
    assert.ok(benchSummary.wumindStreamingGateway.p50Ms < benchSummary.legacyBufferedGateway.p50Ms - 80,
      `Streaming upgrade must drastically reduce TTFT P50: new=${benchSummary.wumindStreamingGateway.p50Ms}ms vs legacy=${benchSummary.legacyBufferedGateway.p50Ms}ms`);
    assert.ok(benchSummary.wumindGatewayPrepOnly.p95Ms <= 25,
      `Gateway D1 auth+reserve prep overhead P95 should stay <=25ms, got ${benchSummary.wumindGatewayPrepOnly.p95Ms}ms`);

    console.log("PERF_AND_FIDELITY_BENCHMARK:", JSON.stringify(benchSummary, null, 2));
    console.log("PASS: ALL 5 Performance & Model-Calling Fidelity Suites succeeded (GPT-5 / DeepSeek / Claude SSE / Gemini SSE / Grok 4 / AIHubMix / Pre-Flight Honesty / Recovery / P50-P95 Overhead)!");
  } finally {
    globalThis.fetch = originalFetch;
  }
}

runTests().catch((err) => {
  console.error("FAIL:", err);
  process.exit(1);
});
