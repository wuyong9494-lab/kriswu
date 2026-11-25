/**
 * WUMIND Dynamic Multi-Vendor Model Catalog, Live Permission/Capability Probing & Strict Execution Guard.
 *
 * Design guarantees:
 * 1. Catalog discovery (GET /v1/models) NEVER implies key permission or pricing readiness:
 *    newly discovered models are stored with enabled=0 and probe_status='unverified'.
 * 2. Admin can filter candidates by vendor/provider & capability (chat, text_to_image, image_edit, video),
 *    probe actual endpoint/key permissions, set pricing, and batch-enable ONLY verified & priced models.
 * 3. User-facing APIs return ONLY enabled, non-deprecated, verified, priced models whose upstream key exists.
 * 4. Unenabled, unpriced, deprecated, or wrong-capability models are strictly rejected with zero silent substitution.
 */

const TINY_PROBE_PNG_BASE64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAADklEQVR4nGNgGAX4AAAAWAABaN+c3wAAAABJRU5ErkJggg==";

export const VALID_CAPABILITIES = ["chat", "text_to_image", "image_edit", "video"];

function parseCapabilities(raw) {
  if (Array.isArray(raw)) {
    return [...new Set(raw.filter((c) => VALID_CAPABILITIES.includes(c)))];
  }
  try {
    const arr = JSON.parse(String(raw || "[]"));
    if (Array.isArray(arr)) return [...new Set(arr.filter((c) => VALID_CAPABILITIES.includes(c)))];
  } catch {}
  return [];
}

function parseJSONObj(raw) {
  if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
  try {
    const obj = JSON.parse(String(raw || "{}"));
    return obj && typeof obj === "object" && !Array.isArray(obj) ? obj : {};
  } catch {
    return {};
  }
}

export function inferVendorFromModelID(modelID, upstreamProvider = "aihubmix") {
  const id = String(modelID || "").toLowerCase();
  if (id.startsWith("gpt-") || id.startsWith("chatgpt-") || /^o[134](-|$)/.test(id) || id.startsWith("sora-") || id.startsWith("dall-e")) return "OpenAI";
  if (id.includes("claude")) return "Anthropic";
  if (id.includes("gemini") || id.includes("imagen") || id.includes("veo-")) return "Google";
  if (id.includes("deepseek")) return "DeepSeek";
  if (id.includes("grok")) return "xAI";
  if (id.includes("qwen") || id.startsWith("wan") || id.includes("happyhorse")) return "Qwen";
  if (id.includes("doubao") || id.includes("seedance") || id.includes("jimeng")) return "ByteDance";
  if (id.includes("kling")) return "Kling";
  if (id.includes("minimax")) return "MiniMax";
  if (id.includes("flux")) return "BlackForestLabs";
  switch (upstreamProvider) {
    case "openAI": return "OpenAI";
    case "claude": return "Anthropic";
    case "gemini": return "Google";
    case "deepSeek": return "DeepSeek";
    case "grok": return "xAI";
    default: return "Other";
  }
}

/**
 * Classifies a provider model ID into exact capabilities, pricing mode, thinking support, and valid parameter constraints.
 * Returns null for non-interactive utility models (embeddings, moderation, tts, whisper, rerank).
 */
export function classifyModelMetadata(modelID, upstreamProvider = "aihubmix", rawMeta = {}) {
  const id = String(modelID || "").trim();
  const lower = id.toLowerCase();
  if (!id) return null;

  // Exclude non-generation utility models from interactive catalog
  const excludedTokens = ["embedding", "text-embedding", "moderation", "whisper", "transcribe", "tts-", "-tts", "rerank", "bge-", "realtime", "native-audio", "lyria"];
  if (excludedTokens.some((tok) => lower.includes(tok))) return null;

  const vendor = inferVendorFromModelID(id, upstreamProvider);
  const displayName = String(rawMeta.display_name || rawMeta.displayName || id).trim();

  // 1. Video generation models
  const isSora = lower === "sora-2" || lower === "sora-2-pro" || lower.startsWith("sora-2-");
  const isVeo = lower.startsWith("veo-");
  const isWanVideo = /^wan\d/.test(lower) || lower.includes("happyhorse");
  const isSeedance = lower.includes("seedance");
  const isKling = lower.startsWith("kling-");
  const isGrokVideo = lower.includes("grok-imagine-video");
  const isMiniMaxVideo = lower.startsWith("minimax-h") || lower.includes("hailuo");

  if (isSora || isVeo || isWanVideo || isSeedance || isKling || isGrokVideo || isMiniMaxVideo || lower.includes("-video") || lower.includes("t2v") || lower.includes("i2v")) {
    let supportedParams = {
      seconds: ["5", "8"],
      defaultSeconds: "5",
      sizes: ["1280x720", "720x1280"],
      defaultSize: "1280x720",
      supportsInputReference: false,
      protocol: upstreamProvider === "aihubmix" ? "aihubmix_videos" : "openai_videos",
    };
    if (isSora) {
      supportedParams = {
        seconds: ["4", "8", "12"],
        defaultSeconds: "4",
        sizes: ["1280x720", "720x1280", "1792x1024", "1024x1792"],
        defaultSize: "1280x720",
        supportsInputReference: true,
        protocol: upstreamProvider === "aihubmix" ? "aihubmix_videos" : "openai_videos",
      };
    } else if (isVeo) {
      const isVeo2 = lower.startsWith("veo-2");
      supportedParams = {
        seconds: isVeo2 ? ["5", "6", "7", "8"] : ["4", "6", "8"],
        defaultSeconds: "8",
        sizes: ["1280x720", "720x1280", "1920x1080", "1080x1920"],
        defaultSize: "1280x720",
        supportsInputReference: true,
        protocol: upstreamProvider === "gemini" ? "gemini_veo" : "aihubmix_videos",
      };
    } else if (isWanVideo) {
      supportedParams = {
        seconds: ["5", "10"],
        defaultSeconds: "5",
        sizes: ["1280x720", "720x1280", "1920x1080", "1080x1920"],
        defaultSize: "1280x720",
        supportsInputReference: lower.includes("i2v") || lower.includes("r2v"),
        protocol: "aihubmix_videos",
      };
    } else if (isSeedance) {
      supportedParams = {
        seconds: ["4", "5", "8", "10", "12"],
        defaultSeconds: "5",
        sizes: ["1280x720", "720x1280"],
        defaultSize: "1280x720",
        supportsInputReference: true,
        protocol: "aihubmix_videos",
      };
    } else if (isGrokVideo) {
      supportedParams = {
        seconds: ["5", "8", "10"],
        defaultSeconds: "5",
        sizes: ["1280x720", "720x1280"],
        defaultSize: "1280x720",
        supportsInputReference: false,
        protocol: upstreamProvider === "grok" ? "grok_videos" : "aihubmix_videos",
      };
    }

    return {
      modelID: id,
      upstreamProvider,
      vendor,
      displayName,
      capabilities: ["video"],
      pricingMode: "per_second",
      inputPricePerMillion: 0,
      outputPricePerMillion: 0,
      unitPriceYuan: 0, // Must be explicitly priced by Admin before enabling!
      supportsThinking: false,
      supportedParams,
    };
  }

  // 2. Image generation & editing models (strictly distinguish text_to_image vs image_edit!)
  const isGPTImage = lower.startsWith("gpt-image-");
  const isGeminiImage = lower.includes("gemini") && lower.includes("image");
  const isImagen = lower.startsWith("imagen-") || lower.includes("imagen-");
  const isDalle = lower.startsWith("dall-e");
  const isFluxEdit = lower.includes("flux") && (lower.includes("kontext") || lower.includes("edit") || lower.includes("fill"));
  const isFluxT2I = lower.includes("flux") && !isFluxEdit;
  const isQwenImageEdit = lower.includes("qwen-image") && lower.includes("edit");
  const isGenericImage = lower.includes("-image") || lower.includes("image-gen") || lower.includes("grok-imagine-image") || lower.includes("ideogram") || lower.includes("seedream");

  if (isGPTImage || isGeminiImage || isImagen || isDalle || isFluxEdit || isFluxT2I || isQwenImageEdit || isGenericImage) {
    const supportsEdit = isGPTImage || isGeminiImage || isFluxEdit || isQwenImageEdit || lower === "dall-e-2";
    const capabilities = supportsEdit ? ["text_to_image", "image_edit"] : ["text_to_image"];
    const protocol = isGeminiImage && upstreamProvider === "gemini"
      ? "gemini_generate_content"
      : "openai_images";
    return {
      modelID: id,
      upstreamProvider,
      vendor,
      displayName,
      capabilities,
      pricingMode: "per_image",
      inputPricePerMillion: 0,
      outputPricePerMillion: 0,
      unitPriceYuan: 0, // Must be explicitly priced by Admin before enabling!
      supportsThinking: false,
      supportedParams: {
        sizes: ["1024x1024", "1024x1536", "1536x1024"],
        qualities: ["low", "medium", "high"],
        outputFormats: ["jpeg", "png"],
        supportsReferenceImage: supportsEdit,
        editEndpoint: supportsEdit ? (protocol === "gemini_generate_content" ? ":generateContent" : "/v1/images/edits") : null,
        protocol,
      },
    };
  }

  // 3. Chat / Reasoning models
  const supportsThinking =
    lower.includes("reasoner") ||
    lower.includes("thinking") ||
    lower.startsWith("o1") ||
    lower.startsWith("o3") ||
    lower.startsWith("o4") ||
    lower.startsWith("gpt-5") ||
    lower.includes("claude-3-7") ||
    lower.includes("claude-sonnet-4") ||
    lower.includes("claude-opus-4") ||
    lower.includes("gemini-2.5") ||
    lower.includes("gemini-3");

  return {
    modelID: id,
    upstreamProvider,
    vendor,
    displayName,
    capabilities: ["chat"],
    pricingMode: "token",
    inputPricePerMillion: 0,
    outputPricePerMillion: 0,
    unitPriceYuan: 0,
    supportsThinking,
    supportedParams: {
      supportsVision: vendor !== "DeepSeek",
      protocol: upstreamProvider === "claude" ? "claude" : upstreamProvider === "gemini" ? "gemini" : "openai_chat",
    },
  };
}

export function resolveAIHubMixBaseOrigin(env) {
  const custom = String(env.AIHUBMIX_BASE_URL || "").trim();
  if (!custom) return "https://aihubmix.com";
  try {
    const u = new URL(custom);
    if (u.protocol !== "https:" || !u.hostname || u.username || u.password) return null;
    const cleanPath = u.pathname
      .replace(/\/+$/, "")
      .replace(/\/v1\/chat\/completions$/i, "")
      .replace(/\/v1$/i, "");
    return `${u.origin}${cleanPath}`;
  } catch {
    return null;
  }
}

export function buildUpstreamSupplyEndpoints(upstreamProvider, env) {
  switch (upstreamProvider) {
    case "aihubmix": {
      const key = (env.AIHUBMIX_API_KEY || "").trim();
      const base = resolveAIHubMixBaseOrigin(env);
      if (!key || !base) return null;
      const extraHeaders = {};
      const appCode = (env.AIHUBMIX_APP_CODE || "").trim();
      if (appCode) extraHeaders["APP-Code"] = appCode;
      return {
        provider: "aihubmix",
        key,
        baseOrigin: base,
        modelsURL: `${base}/v1/models`,
        chatURL: `${base}/v1/chat/completions`,
        imageGenURL: `${base}/v1/images/generations`,
        imageEditURL: `${base}/v1/images/edits`,
        videosURL: `${base}/v1/videos`,
        style: "openai",
        extraHeaders,
      };
    }
    case "openAI": {
      const key = (env.OPENAI_API_KEY || "").trim();
      if (!key) return null;
      return {
        provider: "openAI",
        key,
        baseOrigin: "https://api.openai.com",
        modelsURL: "https://api.openai.com/v1/models",
        chatURL: "https://api.openai.com/v1/chat/completions",
        imageGenURL: "https://api.openai.com/v1/images/generations",
        imageEditURL: "https://api.openai.com/v1/images/edits",
        videosURL: "https://api.openai.com/v1/videos",
        style: "openai",
        extraHeaders: {},
      };
    }
    case "deepSeek": {
      const key = (env.DEEPSEEK_API_KEY || "").trim();
      if (!key) return null;
      return {
        provider: "deepSeek",
        key,
        baseOrigin: "https://api.deepseek.com",
        modelsURL: "https://api.deepseek.com/models",
        chatURL: "https://api.deepseek.com/chat/completions",
        style: "openai",
        extraHeaders: {},
      };
    }
    case "grok": {
      const key = (env.GROK_API_KEY || "").trim();
      if (!key) return null;
      return {
        provider: "grok",
        key,
        baseOrigin: "https://api.x.ai",
        modelsURL: "https://api.x.ai/v1/models",
        chatURL: "https://api.x.ai/v1/chat/completions",
        imageGenURL: "https://api.x.ai/v1/images/generations",
        videosURL: "https://api.x.ai/v1/videos/generations",
        videoPollBaseURL: "https://api.x.ai/v1/videos",
        style: "openai",
        extraHeaders: {},
      };
    }
    case "claude": {
      const key = (env.CLAUDE_API_KEY || "").trim();
      if (!key) return null;
      return {
        provider: "claude",
        key,
        baseOrigin: "https://api.anthropic.com",
        modelsURL: "https://api.anthropic.com/v1/models",
        chatURL: "https://api.anthropic.com/v1/messages",
        style: "claude",
        extraHeaders: {},
      };
    }
    case "gemini": {
      const key = (env.GEMINI_API_KEY || "").trim();
      if (!key) return null;
      return {
        provider: "gemini",
        key,
        baseOrigin: "https://generativelanguage.googleapis.com",
        modelsURL: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200",
        chatURL: "https://generativelanguage.googleapis.com/v1beta/models",
        style: "gemini",
        extraHeaders: {},
      };
    }
    default:
      return null;
  }
}

function serializeCatalogRow(row) {
  const capabilities = parseCapabilities(row.capabilities_json);
  const supportedParams = parseJSONObj(row.supported_params_json);
  return {
    id: row.model_id,
    upstreamProvider: row.upstream_provider,
    provider: row.upstream_provider,
    vendor: row.vendor || inferVendorFromModelID(row.model_id, row.upstream_provider),
    displayName: row.display_name || row.model_id,
    capabilities,
    pricingMode: row.pricing_mode || "token",
    inputPricePerMillion: Number(row.input_price_per_million || 0),
    outputPricePerMillion: Number(row.output_price_per_million || 0),
    unitPriceYuan: Number(row.unit_price_yuan || 0),
    officialReferenceNote: row.official_reference_note || "",
    supportsThinking: Boolean(row.supports_thinking),
    supportsReferenceImage: capabilities.includes("image_edit"),
    supportedParams,
    enabled: Boolean(row.enabled),
    probeStatus: row.probe_status || "unverified",
    probeEndpoint: row.probe_endpoint || "",
    probeMessage: row.probe_message || "",
    probeLatencyMs: Number(row.probe_latency_ms || 0),
    lastProbedAt: row.last_probed_at || null,
    discoveredFrom: row.discovered_from || "",
    deprecated: Boolean(row.deprecated),
    updatedAt: row.updated_at || null,
  };
}

export function isModelRowPriced(row) {
  const mode = String(row.pricing_mode || row.pricingMode || "token");
  if (mode === "token") {
    return Number(row.input_price_per_million ?? row.inputPricePerMillion ?? 0) > 0 ||
      Number(row.output_price_per_million ?? row.outputPricePerMillion ?? 0) > 0;
  }
  return Number(row.unit_price_yuan ?? row.unitPriceYuan ?? 0) > 0;
}

/**
 * Fetches live model directories from ALL configured upstream providers and upserts them into `model_catalog`.
 * Newly discovered models are inserted with enabled=0, probe_status='unverified' (never auto-enabled!).
 * Models missing from a provider's live catalog are marked deprecated=1 and auto-disabled.
 */
export async function handleAdminDiscoverModels(request, env, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可同步供应商模型目录。", code: "admin_forbidden" }, 403);
  }

  let body = {};
  try { body = await request.json(); } catch {}
  const requestedProviders = Array.isArray(body.providers) && body.providers.length
    ? body.providers.map((p) => String(p).trim())
    : ["aihubmix", "openAI", "deepSeek", "gemini", "claude", "grok"];

  const providerReports = [];
  let totalDiscovered = 0;
  let totalDeprecated = 0;

  for (const providerName of requestedProviders) {
    const supply = buildUpstreamSupplyEndpoints(providerName, env);
    if (!supply) {
      providerReports.push({ provider: providerName, configured: false, discovered: 0, note: "未配置上游 API Key" });
      continue;
    }

    const headers = { Accept: "application/json", ...(supply.extraHeaders || {}) };
    if (supply.style === "claude") {
      headers["x-api-key"] = supply.key;
      headers["anthropic-version"] = "2023-06-01";
    } else if (supply.style === "gemini") {
      headers["x-goog-api-key"] = supply.key;
    } else {
      headers.Authorization = `Bearer ${supply.key}`;
    }

    try {
      const res = await fetch(supply.modelsURL, { method: "GET", headers });
      if (!res.ok) {
        const errText = (await res.text()).slice(0, 240);
        providerReports.push({
          provider: providerName,
          configured: true,
          ok: false,
          httpStatus: res.status,
          error: `目录接口返回 HTTP ${res.status}: ${errText}`,
        });
        continue;
      }

      const data = await res.json();
      const rawItems = supply.style === "gemini"
        ? (data.models || []).map((m) => ({
            id: String(m.name || "").replace(/^models\//, ""),
            display_name: m.displayName || String(m.name || "").replace(/^models\//, ""),
          }))
        : (data.data || data.models || []);

      const seenIDs = new Set();
      let providerCount = 0;

      for (const item of rawItems) {
        const rawID = String(item?.id || "").trim();
        if (!rawID) continue;
        const meta = classifyModelMetadata(rawID, providerName, item);
        if (!meta) continue;
        seenIDs.add(meta.modelID);
        providerCount++;
        totalDiscovered++;

        await env.DB.prepare(
          `INSERT INTO model_catalog
           (model_id, upstream_provider, vendor, display_name, capabilities_json, pricing_mode,
            input_price_per_million, output_price_per_million, unit_price_yuan, supports_thinking,
            supported_params_json, enabled, probe_status, discovered_from, deprecated, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0, ?, ?, 0, 'unverified', ?, 0, datetime('now'))
           ON CONFLICT(model_id) DO UPDATE SET
             upstream_provider = excluded.upstream_provider,
             vendor = excluded.vendor,
             capabilities_json = excluded.capabilities_json,
             pricing_mode = excluded.pricing_mode,
             supports_thinking = excluded.supports_thinking,
             supported_params_json = excluded.supported_params_json,
             discovered_from = excluded.discovered_from,
             deprecated = 0,
             updated_at = datetime('now')`
        ).bind(
          meta.modelID,
          meta.upstreamProvider,
          meta.vendor,
          meta.displayName,
          JSON.stringify(meta.capabilities),
          meta.pricingMode,
          meta.supportsThinking ? 1 : 0,
          JSON.stringify(meta.supportedParams),
          supply.modelsURL
        ).run();
      }

      // Mark models previously discovered from this provider that vanished from live catalog as deprecated & disabled
      if (seenIDs.size > 0) {
        const existingRows = await env.DB.prepare(
          "SELECT model_id FROM model_catalog WHERE upstream_provider = ? AND deprecated = 0"
        ).bind(providerName).all();
        for (const r of existingRows.results || []) {
          if (!seenIDs.has(r.model_id)) {
            await env.DB.prepare(
              "UPDATE model_catalog SET deprecated = 1, enabled = 0, probe_status = 'deprecated', probe_message = '供应商目录已下线该型号，已自动停用。', updated_at = datetime('now') WHERE model_id = ?"
            ).bind(r.model_id).run();
            totalDeprecated++;
          }
        }
      }

      providerReports.push({
        provider: providerName,
        configured: true,
        ok: true,
        endpoint: supply.modelsURL,
        discovered: providerCount,
      });
    } catch (err) {
      providerReports.push({
        provider: providerName,
        configured: true,
        ok: false,
        error: `拉取目录异常：${String(err?.message || err).slice(0, 180)}`,
      });
    }
  }

  const allRows = await env.DB.prepare("SELECT * FROM model_catalog ORDER BY enabled DESC, vendor ASC, model_id ASC").all();
  return json({
    ok: true,
    totalDiscovered,
    totalDeprecated,
    providerReports,
    models: (allRows.results || []).map(serializeCatalogRow),
  });
}

function sanitizeUpstreamError(status, rawText) {
  let msg = "";
  try {
    const parsed = JSON.parse(rawText);
    msg = parsed?.error?.message || parsed?.message || parsed?.error || "";
    if (typeof msg === "object") msg = JSON.stringify(msg);
  } catch {
    msg = String(rawText || "");
  }
  const clean = String(msg || "").replace(/sk-[A-Za-z0-9_-]{8,}/g, "sk-***").trim().slice(0, 260);
  return clean ? `HTTP ${status}: ${clean}` : `HTTP ${status}`;
}

function classifyProbeFailureStatus(httpStatus, message) {
  const lower = String(message || "").toLowerCase();
  if (httpStatus === 401 || httpStatus === 403 || lower.includes("permission") || lower.includes("not authorized") || lower.includes("access denied")) {
    return "permission_denied";
  }
  if (httpStatus === 404 || lower.includes("model_not_found") || lower.includes("does not exist") || lower.includes("deprecated")) {
    return "deprecated";
  }
  if (httpStatus === 400 || httpStatus === 422 || lower.includes("invalid") || lower.includes("unsupported") || lower.includes("protocol_not_supported")) {
    return "unsupported_params";
  }
  return "error";
}

function base64ToUint8Array(b64) {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

/**
 * Probes one specific catalog model against its REAL upstream endpoint, capability protocol & key permission.
 */
async function probeSingleCatalogModel(row, env) {
  const supply = buildUpstreamSupplyEndpoints(row.upstream_provider, env);
  if (!supply) {
    return {
      probeStatus: "permission_denied",
      probeEndpoint: "",
      probeMessage: `未配置 ${row.upstream_provider} 上游 API Key。`,
      probeLatencyMs: 0,
    };
  }

  const capabilities = parseCapabilities(row.capabilities_json);
  const params = parseJSONObj(row.supported_params_json);
  const started = Date.now();

  try {
    // 1. Chat model live probe (1-token minimal completion)
    if (capabilities.includes("chat")) {
      let url = supply.chatURL;
      const headers = { "Content-Type": "application/json", ...(supply.extraHeaders || {}) };
      let payload;

      if (supply.style === "claude") {
        headers["x-api-key"] = supply.key;
        headers["anthropic-version"] = "2023-06-01";
        payload = { model: row.model_id, max_tokens: 8, messages: [{ role: "user", content: "Reply OK" }] };
      } else if (supply.style === "gemini") {
        url = `${supply.chatURL}/${encodeURIComponent(row.model_id)}:generateContent`;
        headers["x-goog-api-key"] = supply.key;
        payload = { contents: [{ role: "user", parts: [{ text: "Reply OK" }] }], generationConfig: { maxOutputTokens: 8 } };
      } else {
        headers.Authorization = `Bearer ${supply.key}`;
        payload = { model: row.model_id, messages: [{ role: "user", content: "Reply OK" }], max_tokens: 8, stream: false };
      }

      const res = await fetch(url, { method: "POST", headers, body: JSON.stringify(payload) });
      const latency = Date.now() - started;
      const raw = await res.text();
      if (!res.ok) {
        const msg = sanitizeUpstreamError(res.status, raw);
        return { probeStatus: classifyProbeFailureStatus(res.status, msg), probeEndpoint: url, probeMessage: msg, probeLatencyMs: latency };
      }
      return { probeStatus: "verified", probeEndpoint: url, probeMessage: `对话实测通过（HTTP ${res.status} · ${latency}ms）`, probeLatencyMs: latency };
    }

    // 2. Reference-image edit model live probe (multipart /v1/images/edits or Gemini inline_data)
    if (capabilities.includes("image_edit")) {
      if (params.protocol === "gemini_generate_content" && supply.style === "gemini") {
        const url = `${supply.chatURL}/${encodeURIComponent(row.model_id)}:generateContent`;
        const res = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json", "x-goog-api-key": supply.key },
          body: JSON.stringify({
            contents: [{
              role: "user",
              parts: [
                { inline_data: { mime_type: "image/png", data: TINY_PROBE_PNG_BASE64 } },
                { text: "Keep this blue square and add a tiny white dot in center" },
              ],
            }],
            generationConfig: { responseModalities: ["IMAGE"] },
          }),
        });
        const latency = Date.now() - started;
        const raw = await res.text();
        if (!res.ok) {
          const msg = sanitizeUpstreamError(res.status, raw);
          return { probeStatus: classifyProbeFailureStatus(res.status, msg), probeEndpoint: url, probeMessage: msg, probeLatencyMs: latency };
        }
        return { probeStatus: "verified", probeEndpoint: url, probeMessage: `图生图/参考图编辑实测通过（HTTP ${res.status} · ${latency}ms）`, probeLatencyMs: latency };
      }

      const url = supply.imageEditURL || `${supply.baseOrigin}/v1/images/edits`;
      const form = new FormData();
      form.append("model", row.model_id);
      form.append("prompt", "Change background to pale blue");
      form.append("n", "1");
      form.append("size", "1024x1024");
      form.append("quality", "low");
      form.append("image", new Blob([base64ToUint8Array(TINY_PROBE_PNG_BASE64)], { type: "image/png" }), "probe.png");

      const res = await fetch(url, {
        method: "POST",
        headers: { Authorization: `Bearer ${supply.key}`, ...(supply.extraHeaders || {}) },
        body: form,
      });
      const latency = Date.now() - started;
      const raw = await res.text();
      if (!res.ok) {
        const msg = sanitizeUpstreamError(res.status, raw);
        return { probeStatus: classifyProbeFailureStatus(res.status, msg), probeEndpoint: url, probeMessage: msg, probeLatencyMs: latency };
      }
      return { probeStatus: "verified", probeEndpoint: url, probeMessage: `参考图编辑实测通过（multipart /v1/images/edits · ${latency}ms）`, probeLatencyMs: latency };
    }

    // 3. Text-to-image only model live probe
    if (capabilities.includes("text_to_image")) {
      const url = supply.imageGenURL || `${supply.baseOrigin}/v1/images/generations`;
      const res = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${supply.key}`,
          ...(supply.extraHeaders || {}),
        },
        body: JSON.stringify({ model: row.model_id, prompt: "minimal green circle on white background", n: 1, size: "1024x1024" }),
      });
      const latency = Date.now() - started;
      const raw = await res.text();
      if (!res.ok) {
        const msg = sanitizeUpstreamError(res.status, raw);
        return { probeStatus: classifyProbeFailureStatus(res.status, msg), probeEndpoint: url, probeMessage: msg, probeLatencyMs: latency };
      }
      return { probeStatus: "verified", probeEndpoint: url, probeMessage: `纯文生图实测通过（HTTP ${res.status} · ${latency}ms）`, probeLatencyMs: latency };
    }

    // 4. Video generation model live probe
    if (capabilities.includes("video")) {
      const isGeminiOfficial = params.protocol === "gemini_veo" && supply.style === "gemini";
      const url = isGeminiOfficial
        ? `${supply.chatURL}/${encodeURIComponent(row.model_id)}:predictLongRunning`
        : (supply.videosURL || `${supply.baseOrigin}/v1/videos`);
      const headers = { "Content-Type": "application/json", ...(supply.extraHeaders || {}) };
      let payload;
      if (isGeminiOfficial) {
        headers["x-goog-api-key"] = supply.key;
        payload = {
          instances: [{ prompt: "Gentle ocean waves at sunrise, cinematic wide shot" }],
          parameters: { aspectRatio: "16:9", durationSeconds: Number(params.defaultSeconds || 8), resolution: "720p" },
        };
      } else if (params.protocol === "grok_videos" && supply.provider === "grok") {
        headers.Authorization = `Bearer ${supply.key}`;
        payload = { model: row.model_id, prompt: "Gentle ocean waves at sunrise", duration: Number(params.defaultSeconds || 5), aspect_ratio: "16:9", resolution: "720p" };
      } else {
        headers.Authorization = `Bearer ${supply.key}`;
        payload = {
          model: row.model_id,
          prompt: "Gentle ocean waves at sunrise, soft golden light",
          seconds: String(params.defaultSeconds || "4"),
          size: String(params.defaultSize || "1280x720"),
        };
      }

      const res = await fetch(url, { method: "POST", headers, body: JSON.stringify(payload) });
      const latency = Date.now() - started;
      const raw = await res.text();
      if (!res.ok) {
        const msg = sanitizeUpstreamError(res.status, raw);
        return { probeStatus: classifyProbeFailureStatus(res.status, msg), probeEndpoint: url, probeMessage: msg, probeLatencyMs: latency };
      }
      let jobID = "";
      try {
        const parsed = JSON.parse(raw);
        jobID = parsed.id || parsed.request_id || parsed.name || "";
      } catch {}
      return {
        probeStatus: "verified",
        probeEndpoint: url,
        probeMessage: jobID ? `视频任务接口实测已受理（task=${String(jobID).slice(0, 28)} · ${latency}ms）` : `视频接口实测通过（HTTP ${res.status} · ${latency}ms）`,
        probeLatencyMs: latency,
      };
    }

    return { probeStatus: "unsupported_params", probeEndpoint: "", probeMessage: "未知模型能力类型。", probeLatencyMs: 0 };
  } catch (err) {
    return {
      probeStatus: "error",
      probeEndpoint: "",
      probeMessage: `探测请求失败：${String(err?.message || err).slice(0, 200)}`,
      probeLatencyMs: Date.now() - started,
    };
  }
}

export async function handleAdminProbeModels(request, env, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可探测模型权限与接口。", code: "admin_forbidden" }, 403);
  }
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求 JSON 格式错误。" }, 400); }
  const modelIDs = Array.isArray(body.modelIDs)
    ? body.modelIDs.map((x) => String(x || "").trim()).filter(Boolean).slice(0, 12)
    : (body.modelID ? [String(body.modelID).trim()] : []);

  if (modelIDs.length === 0) {
    return json({ error: "请提供至少一个待实测的 modelID。" }, 400);
  }

  const results = [];
  for (const modelID of modelIDs) {
    const row = await env.DB.prepare("SELECT * FROM model_catalog WHERE model_id = ?").bind(modelID).first();
    if (!row) {
      results.push({ id: modelID, found: false, probeStatus: "error", probeMessage: "模型不在候选目录中，请先同步供应商目录。" });
      continue;
    }
    const probe = await probeSingleCatalogModel(row, env);
    const shouldAutoDisable = probe.probeStatus !== "verified";
    await env.DB.prepare(
      `UPDATE model_catalog
       SET probe_status = ?, probe_endpoint = ?, probe_message = ?, probe_latency_ms = ?,
           deprecated = CASE WHEN ? = 'deprecated' THEN 1 ELSE deprecated END,
           enabled = CASE WHEN ? = 1 THEN 0 ELSE enabled END,
           last_probed_at = datetime('now'), updated_at = datetime('now')
       WHERE model_id = ?`
    ).bind(
      probe.probeStatus,
      probe.probeEndpoint,
      probe.probeMessage,
      probe.probeLatencyMs,
      probe.probeStatus,
      shouldAutoDisable ? 1 : 0,
      modelID
    ).run();

    const fresh = await env.DB.prepare("SELECT * FROM model_catalog WHERE model_id = ?").bind(modelID).first();
    results.push(serializeCatalogRow(fresh));
  }

  return json({ ok: true, results });
}

/**
 * Admin batch pricing & enable/disable endpoint.
 * Hard server-side guardrail: refuses enabling any model unless verified, non-deprecated, and priced > 0!
 */
export async function handleAdminBatchUpdateModels(request, env, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可修改模型定价与启用状态。", code: "admin_forbidden" }, 403);
  }
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求 JSON 格式错误。" }, 400); }
  const updates = Array.isArray(body.updates) ? body.updates.slice(0, 100) : [];
  if (updates.length === 0) {
    return json({ error: "缺少待更新的模型列表（updates）。" }, 400);
  }

  const applied = [];
  const rejected = [];

  for (const item of updates) {
    const modelID = String(item?.id || item?.modelID || "").trim();
    if (!modelID) continue;
    const row = await env.DB.prepare("SELECT * FROM model_catalog WHERE model_id = ?").bind(modelID).first();
    if (!row) {
      rejected.push({ id: modelID, code: "not_found", reason: "模型不在候选目录中，请先同步供应商目录。" });
      continue;
    }

    const displayName = item.displayName !== undefined ? String(item.displayName).trim().slice(0, 80) : row.display_name;
    const inputPrice = item.inputPricePerMillion !== undefined ? Math.max(0, Number(item.inputPricePerMillion || 0)) : Number(row.input_price_per_million || 0);
    const outputPrice = item.outputPricePerMillion !== undefined ? Math.max(0, Number(item.outputPricePerMillion || 0)) : Number(row.output_price_per_million || 0);
    const unitPrice = item.unitPriceYuan !== undefined ? Math.max(0, Number(item.unitPriceYuan || 0)) : Number(row.unit_price_yuan || 0);
    const wantEnabled = item.enabled !== undefined ? Boolean(item.enabled) : Boolean(row.enabled);
    const note = item.officialReferenceNote !== undefined ? String(item.officialReferenceNote).trim().slice(0, 120) : (row.official_reference_note || "");

    const candidateCheck = {
      pricing_mode: row.pricing_mode,
      input_price_per_million: inputPrice,
      output_price_per_million: outputPrice,
      unit_price_yuan: unitPrice,
    };

    if (wantEnabled) {
      if (row.deprecated) {
        rejected.push({ id: modelID, code: "deprecated", reason: "该模型已下线，禁止启用。" });
        continue;
      }
      if (row.probe_status !== "verified") {
        rejected.push({ id: modelID, code: "not_verified", reason: `该模型尚未通过真实权限与接口实测（当前状态：${row.probe_status}），禁止启用。` });
        continue;
      }
      if (!isModelRowPriced(candidateCheck)) {
        rejected.push({ id: modelID, code: "unpriced", reason: "该模型尚未设置有效售价（必须 > 0），禁止启用。" });
        continue;
      }
    }

    await env.DB.prepare(
      `UPDATE model_catalog
       SET display_name = ?, input_price_per_million = ?, output_price_per_million = ?,
           unit_price_yuan = ?, official_reference_note = ?, enabled = ?, updated_at = datetime('now')
       WHERE model_id = ?`
    ).bind(displayName || modelID, inputPrice, outputPrice, unitPrice, note, wantEnabled ? 1 : 0, modelID).run();

    const fresh = await env.DB.prepare("SELECT * FROM model_catalog WHERE model_id = ?").bind(modelID).first();
    applied.push(serializeCatalogRow(fresh));
  }

  return json({
    ok: rejected.length === 0,
    appliedCount: applied.length,
    rejectedCount: rejected.length,
    applied,
    rejected,
  }, rejected.length > 0 && applied.length === 0 ? 400 : 200);
}

export async function handleAdminListCatalog(request, env, { json, verifyAdminSecret, parseAIHubMixAllowlist, loadCommercialConfig }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可查看候选模型目录。", code: "admin_forbidden" }, 403);
  }
  const url = new URL(request.url);
  const filterVendor = String(url.searchParams.get("vendor") || "").trim().toLowerCase();
  const filterProvider = String(url.searchParams.get("provider") || "").trim().toLowerCase();
  const filterCapability = String(url.searchParams.get("capability") || "").trim().toLowerCase();
  const filterStatus = String(url.searchParams.get("status") || "").trim().toLowerCase();

  const rows = await env.DB.prepare("SELECT * FROM model_catalog ORDER BY enabled DESC, vendor ASC, model_id ASC").all();
  let models = (rows.results || []).map(serializeCatalogRow);

  if (filterVendor) models = models.filter((m) => m.vendor.toLowerCase() === filterVendor);
  if (filterProvider) models = models.filter((m) => m.upstreamProvider.toLowerCase() === filterProvider);
  if (filterCapability) models = models.filter((m) => m.capabilities.includes(filterCapability));
  if (filterStatus) models = models.filter((m) => m.probeStatus.toLowerCase() === filterStatus);

  const allowlist = [...parseAIHubMixAllowlist(env)];
  const config = await loadCommercialConfig(env);
  const configuredUpstreams = ["aihubmix", "openAI", "deepSeek", "gemini", "claude", "grok"]
    .filter((p) => Boolean(buildUpstreamSupplyEndpoints(p, env)));

  return json({
    ok: true,
    configuredUpstreams,
    legacyAIHubMixAllowlist: allowlist,
    legacyPricingCount: (config.pricing || []).length,
    totalCount: models.length,
    enabledVerifiedCount: models.filter((m) => m.enabled && !m.deprecated && m.probeStatus === "verified" && isModelRowPriced(m)).length,
    models,
  });
}

/**
 * Returns ONLY user-callable models: enabled=1, deprecated=0, probe_status='verified', priced > 0, and upstream key configured.
 * If model_catalog is empty (pre-migration legacy deployment), reconciles legacy pricing rows strictly against configured keys + AIHUBMIX_ALLOWED_MODELS.
 */
export async function getPublicCallableModels(env, legacyPricing, parseAIHubMixAllowlist) {
  const catalogRows = await env.DB.prepare("SELECT * FROM model_catalog ORDER BY vendor ASC, model_id ASC").all();
  const allCatalog = catalogRows.results || [];

  if (allCatalog.length > 0) {
    return allCatalog
      .filter((row) =>
        Boolean(row.enabled) &&
        !row.deprecated &&
        row.probe_status === "verified" &&
        isModelRowPriced(row) &&
        Boolean(buildUpstreamSupplyEndpoints(row.upstream_provider, env))
      )
      .map(serializeCatalogRow);
  }

  // Legacy compatibility when Admin has not yet run dynamic discovery:
  // ONLY expose legacy pricing rows that are actually callable with currently configured keys & AIHUBMIX_ALLOWED_MODELS!
  const allowlist = parseAIHubMixAllowlist(env);
  const hasAIHubMix = Boolean(buildUpstreamSupplyEndpoints("aihubmix", env));
  const callable = [];
  for (const item of legacyPricing || []) {
    if (item.enabled === false) continue;
    const provider = String(item.provider || "deepSeek");
    const hasOfficial = Boolean(buildUpstreamSupplyEndpoints(provider, env));
    const callableViaAIHubMix = hasAIHubMix && allowlist.has(item.id);
    if (!hasOfficial && !callableViaAIHubMix) continue;
    const priced = Number(item.inputPricePerMillion || 0) > 0 || Number(item.outputPricePerMillion || 0) > 0;
    if (!priced) continue;
    callable.push({
      id: item.id,
      upstreamProvider: hasOfficial ? provider : "aihubmix",
      provider: provider,
      vendor: inferVendorFromModelID(item.id, provider),
      displayName: item.displayName || item.id,
      capabilities: ["chat"],
      pricingMode: "token",
      inputPricePerMillion: Number(item.inputPricePerMillion || 0),
      outputPricePerMillion: Number(item.outputPricePerMillion || 0),
      unitPriceYuan: 0,
      officialReferenceNote: item.officialReferenceNote || "",
      supportsThinking: Boolean(item.supportsThinking),
      supportsReferenceImage: false,
      supportedParams: { supportsVision: provider !== "deepSeek" },
      enabled: true,
      probeStatus: "verified",
      deprecated: false,
    });
  }
  return callable;
}

/**
 * Single authoritative execution resolver for chat, text_to_image, image_edit, and video requests.
 * NEVER silently substitutes a different model or downgrades capability!
 */
export async function resolveCatalogModelForExecution(env, config, requestedModelID, requiredCapability, parseAIHubMixAllowlist) {
  const modelID = String(requestedModelID || "").trim();
  if (!modelID) {
    return { error: "缺少目标模型 ID。", code: "missing_model", status: 400 };
  }

  const catalogRow = await env.DB.prepare("SELECT * FROM model_catalog WHERE model_id = ?").bind(modelID).first();
  if (catalogRow) {
    const model = serializeCatalogRow(catalogRow);
    if (model.deprecated) {
      return { error: `模型 ${modelID} 已从供应商目录下线，请切换到其他已开通模型。`, code: "model_deprecated", status: 410 };
    }
    if (!model.enabled) {
      return { error: `模型 ${modelID} 尚未在 WUMIND 后台启用，已拒绝调用（不会静默替换模型）。`, code: "model_not_enabled", status: 403 };
    }
    if (model.probeStatus !== "verified") {
      return { error: `模型 ${modelID} 未通过权限与接口实测（状态：${model.probeStatus}），已拒绝调用。`, code: "model_not_verified", status: 403 };
    }
    if (!isModelRowPriced(model)) {
      return { error: `模型 ${modelID} 尚未配置有效计费单价，已拒绝调用。`, code: "model_unpriced", status: 403 };
    }
    if (requiredCapability && !model.capabilities.includes(requiredCapability)) {
      if (requiredCapability === "image_edit" && model.capabilities.includes("text_to_image")) {
        return {
          error: `模型 ${model.displayName}（${modelID}）仅支持纯文生图，不支持上传参考图编辑；请切换到支持参考图的模型（不会悄悄退回纯文生图）。`,
          code: "reference_image_not_supported",
          status: 400,
        };
      }
      return {
        error: `模型 ${model.displayName}（${modelID}）不支持「${requiredCapability}」能力（实际能力：${model.capabilities.join(", ")}），请切换对应类型模型。`,
        code: "capability_mismatch",
        status: 400,
      };
    }

    const supply = buildUpstreamSupplyEndpoints(model.upstreamProvider, env);
    if (!supply) {
      return { error: `云端尚未配置 ${model.upstreamProvider} 的上游 API Key。`, code: "upstream_key_missing", status: 503 };
    }
    return { model, supply };
  }

  // Fallback to legacy commercial_config.pricing ONLY for chat when model_catalog has no entry for this modelID
  if (requiredCapability === "chat") {
    const legacy = (config.pricing || []).find((p) => p.id === modelID && p.enabled !== false);
    if (legacy) {
      const provider = String(legacy.provider || "deepSeek");
      const official = buildUpstreamSupplyEndpoints(provider, env);
      if (official) {
        return {
          model: {
            id: legacy.id,
            upstreamProvider: provider,
            provider,
            vendor: inferVendorFromModelID(legacy.id, provider),
            displayName: legacy.displayName || legacy.id,
            capabilities: ["chat"],
            pricingMode: "token",
            inputPricePerMillion: Number(legacy.inputPricePerMillion || 0),
            outputPricePerMillion: Number(legacy.outputPricePerMillion || 0),
            unitPriceYuan: 0,
            supportsThinking: Boolean(legacy.supportsThinking),
            supportedParams: { supportsVision: provider !== "deepSeek" },
          },
          supply: official,
        };
      }
      const aihubmix = buildUpstreamSupplyEndpoints("aihubmix", env);
      if (aihubmix) {
        const allowlist = parseAIHubMixAllowlist(env);
        if (!allowlist.has(modelID)) {
          return {
            error: `模型 ${modelID} 不在 AIHubMix 可售白名单（AIHUBMIX_ALLOWED_MODELS）且未在动态模型目录启用，已拒绝透传。`,
            code: "aihubmix_model_not_allowed",
            status: 403,
          };
        }
        return {
          model: {
            id: legacy.id,
            upstreamProvider: "aihubmix",
            provider: "aihubmix",
            vendor: inferVendorFromModelID(legacy.id, "aihubmix"),
            displayName: legacy.displayName || legacy.id,
            capabilities: ["chat"],
            pricingMode: "token",
            inputPricePerMillion: Number(legacy.inputPricePerMillion || 0),
            outputPricePerMillion: Number(legacy.outputPricePerMillion || 0),
            unitPriceYuan: 0,
            supportsThinking: Boolean(legacy.supportsThinking),
            supportedParams: { supportsVision: true },
          },
          supply: aihubmix,
        };
      }
      return {
        error: `管理员尚未在云端配置 ${provider} 上游 API Key（或配置 AIHUBMIX_API_KEY + 启用动态模型目录）。`,
        code: "upstream_key_missing",
        status: 503,
      };
    }
  }

  return {
    error: `模型 ${modelID} 未在 WUMIND 可用目录中开通（不会静默替换其他模型）。`,
    code: "model_not_enabled",
    status: 403,
  };
}
