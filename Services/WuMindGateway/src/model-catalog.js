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

export const VALID_CAPABILITIES = ["chat", "text_to_image", "image_edit", "video", "realtime_voice"];
export const DEFAULT_FX_USD_TO_CNY = 7.25;
export const UNIFORM_MARKUP_MULTIPLIER = 1.5;
export const AIHUBMIX_OFFICIAL_PRICING_SOURCE = "https://aihubmix.com/models";

function roundPrice4(n) {
  const v = Number(n);
  if (!Number.isFinite(v) || v <= 0) return 0;
  return Math.round(v * 10000) / 10000;
}

/**
 * Verifiable AIHubMix / official upstream base prices in USD (before WUMIND 1.50× uniform markup).
 * Text models store USD per 1M tokens (input / output / cache);
 * Image models store USD per image; Video models store USD per second; Realtime voice stores USD per minute.
 * Any model NOT present here AND not providing official price metadata from upstream stays `pending_pricing`
 * (NEVER priced at ¥0, NEVER auto-enabled).
 */
export const VERIFIED_AIHUBMIX_OFFICIAL_PRICING_USD = {
  // Chat / Reasoning (USD per 1M tokens)
  "deepseek-chat": { mode: "token", inputUSD: 0.27, outputUSD: 1.10, cacheUSD: 0.07 },
  "deepseek-reasoner": { mode: "token", inputUSD: 0.55, outputUSD: 2.19, cacheUSD: 0.14 },
  "gpt-4o": { mode: "token", inputUSD: 2.50, outputUSD: 10.00, cacheUSD: 1.25 },
  "gpt-4o-mini": { mode: "token", inputUSD: 0.15, outputUSD: 0.60, cacheUSD: 0.075 },
  "gpt-4.1": { mode: "token", inputUSD: 2.00, outputUSD: 8.00, cacheUSD: 0.50 },
  "gpt-4.1-mini": { mode: "token", inputUSD: 0.40, outputUSD: 1.60, cacheUSD: 0.10 },
  "gpt-5": { mode: "token", inputUSD: 1.25, outputUSD: 10.00, cacheUSD: 0.125 },
  "gpt-5-mini": { mode: "token", inputUSD: 0.25, outputUSD: 2.00, cacheUSD: 0.025 },
  "o3": { mode: "token", inputUSD: 2.00, outputUSD: 8.00, cacheUSD: 0.50 },
  "o4-mini": { mode: "token", inputUSD: 1.10, outputUSD: 4.40, cacheUSD: 0.275 },
  "claude-sonnet-4-20250514": { mode: "token", inputUSD: 3.00, outputUSD: 15.00, cacheUSD: 0.30 },
  "claude-3-7-sonnet-20250219": { mode: "token", inputUSD: 3.00, outputUSD: 15.00, cacheUSD: 0.30 },
  "claude-opus-4-20250514": { mode: "token", inputUSD: 15.00, outputUSD: 75.00, cacheUSD: 1.50 },
  "gemini-2.5-pro": { mode: "token", inputUSD: 1.25, outputUSD: 10.00, cacheUSD: 0.3125 },
  "gemini-2.5-flash": { mode: "token", inputUSD: 0.30, outputUSD: 2.50, cacheUSD: 0.075 },
  "grok-3": { mode: "token", inputUSD: 3.00, outputUSD: 15.00, cacheUSD: 0.75 },
  "grok-3-mini": { mode: "token", inputUSD: 0.30, outputUSD: 0.50, cacheUSD: 0.075 },
  // Image (USD per image)
  "gpt-image-1": { mode: "per_image", unitUSD: 0.04 },
  "gpt-image-1-mini": { mode: "per_image", unitUSD: 0.015 },
  "dall-e-3": { mode: "per_image", unitUSD: 0.04 },
  "imagen-3.0-generate-002": { mode: "per_image", unitUSD: 0.03 },
  "flux-kontext-pro": { mode: "per_image", unitUSD: 0.04 },
  "flux-pro-1.1": { mode: "per_image", unitUSD: 0.04 },
  "gemini-2.5-flash-image-preview": { mode: "per_image", unitUSD: 0.039 },
  // Video (USD per second)
  "sora-2": { mode: "per_second", unitUSD: 0.10 },
  "sora-2-pro": { mode: "per_second", unitUSD: 0.30 },
  "veo-3.1-fast-generate-preview": { mode: "per_second", unitUSD: 0.15 },
  "veo-3.1-generate-preview": { mode: "per_second", unitUSD: 0.35 },
  "kling-v3-omni": { mode: "per_second", unitUSD: 0.07 },
  "doubao-seedance-2-0-fast-260128": { mode: "per_second", unitUSD: 0.05 },
  "wan2.6-t2v": { mode: "per_second", unitUSD: 0.06 },
  "grok-imagine-video": { mode: "per_second", unitUSD: 0.05 },
  "gemini-omni-1.2-flash": { mode: "per_second", unitUSD: 0.08 },
  // Realtime Voice (USD per minute)
  "gpt-realtime": { mode: "per_minute", unitUSD: 0.24 },
  "gpt-realtime-mini": { mode: "per_minute", unitUSD: 0.08 },
  "gpt-4o-realtime-preview": { mode: "per_minute", unitUSD: 0.24 },
  "gpt-realtime-2.1": { mode: "per_minute", unitUSD: 0.24 },
  "gpt-realtime-2.1-mini": { mode: "per_minute", unitUSD: 0.08 },
};

/**
 * Extracts official USD base pricing from upstream `/v1/models` metadata if provided,
 * falling back ONLY to verified official AIHubMix catalog entries (never guessing unknown models!).
 */
export function lookupVerifiedOfficialPricingUSD(modelID, pricingMode = "token", rawMeta = {}) {
  const id = String(modelID || "").trim();
  const lower = id.toLowerCase();

  // 1. Check live pricing fields if upstream catalog returned them directly
  const p = rawMeta?.pricing || rawMeta?.price || rawMeta?.model_price || null;
  if (p && typeof p === "object") {
    if (pricingMode === "token") {
      const inUSD = Number(p.input_usd_per_million ?? p.input_per_million ?? p.prompt_usd_per_million ?? (Number(p.prompt) > 0 && Number(p.prompt) < 0.01 ? Number(p.prompt) * 1_000_000 : p.input));
      const outUSD = Number(p.output_usd_per_million ?? p.output_per_million ?? p.completion_usd_per_million ?? (Number(p.completion) > 0 && Number(p.completion) < 0.01 ? Number(p.completion) * 1_000_000 : p.output));
      const cacheUSD = Number(p.cache_usd_per_million ?? p.cache_read_usd_per_million ?? p.cached_input ?? 0);
      if (Number.isFinite(inUSD) && inUSD > 0 && Number.isFinite(outUSD) && outUSD > 0) {
        return {
          mode: "token",
          inputUSD: roundPrice4(inUSD),
          outputUSD: roundPrice4(outUSD),
          cacheUSD: Number.isFinite(cacheUSD) && cacheUSD > 0 ? roundPrice4(cacheUSD) : null,
          unitUSD: null,
          source: "upstream_live",
        };
      }
    } else {
      const unitUSD = Number(p.unit_usd ?? p.per_image_usd ?? p.per_second_usd ?? p.per_minute_usd ?? p.unit);
      if (Number.isFinite(unitUSD) && unitUSD > 0) {
        return {
          mode: pricingMode,
          inputUSD: null,
          outputUSD: null,
          cacheUSD: null,
          unitUSD: roundPrice4(unitUSD),
          source: "upstream_live",
        };
      }
    }
  }

  // 2. Exact match in verified official AIHubMix USD catalog
  const known = VERIFIED_AIHUBMIX_OFFICIAL_PRICING_USD[id] || VERIFIED_AIHUBMIX_OFFICIAL_PRICING_USD[lower];
  if (known) {
    return {
      mode: known.mode || pricingMode,
      inputUSD: known.inputUSD ?? null,
      outputUSD: known.outputUSD ?? null,
      cacheUSD: known.cacheUSD ?? null,
      unitUSD: known.unitUSD ?? null,
      source: "aihubmix_official_catalog",
    };
  }

  return null;
}

/**
 * Pure non-compounding server pricing rule:
 * Retail CNY = Official USD base price × fxRate × multiplier (default 1.50×).
 * Re-running sync ALWAYS starts from Official USD base prices and NEVER multiplies already-marked-up CNY prices!
 * Models without verifiable official USD prices are marked `pending_pricing` (never ¥0, never enabled).
 */
export function computeUniformMarkupPrices({
  pricingMode = "token",
  officialInputUSD = null,
  officialOutputUSD = null,
  officialCacheUSD = null,
  officialUnitUSD = null,
}, fxRate = DEFAULT_FX_USD_TO_CNY, multiplier = UNIFORM_MARKUP_MULTIPLIER) {
  const safeFx = Number.isFinite(Number(fxRate)) && Number(fxRate) > 0 ? Number(fxRate) : DEFAULT_FX_USD_TO_CNY;
  const safeMult = Number.isFinite(Number(multiplier)) && Number(multiplier) >= 1.0 ? Number(multiplier) : UNIFORM_MARKUP_MULTIPLIER;

  if (pricingMode === "token") {
    const inUSD = Number(officialInputUSD);
    const outUSD = Number(officialOutputUSD);
    const cacheUSD = Number(officialCacheUSD);
    const hasOfficial = Number.isFinite(inUSD) && inUSD > 0 && Number.isFinite(outUSD) && outUSD > 0;
    if (!hasOfficial) {
      return {
        pricingStatus: "pending_pricing",
        inputPricePerMillion: 0,
        outputPricePerMillion: 0,
        cachePricePerMillion: 0,
        unitPriceYuan: 0,
        fxUsdToCny: safeFx,
        markupMultiplier: safeMult,
        officialReferenceNote: "官方目录暂无可核验价格（待定价，禁止 0 元售卖）",
      };
    }
    const retailIn = roundPrice4(inUSD * safeFx * safeMult);
    const retailOut = roundPrice4(outUSD * safeFx * safeMult);
    const retailCache = Number.isFinite(cacheUSD) && cacheUSD > 0 ? roundPrice4(cacheUSD * safeFx * safeMult) : 0;
    const cacheNote = Number.isFinite(cacheUSD) && cacheUSD > 0 ? ` / 缓存 $${cacheUSD}` : "";
    return {
      pricingStatus: "priced",
      inputPricePerMillion: retailIn,
      outputPricePerMillion: retailOut,
      cachePricePerMillion: retailCache,
      unitPriceYuan: 0,
      fxUsdToCny: safeFx,
      markupMultiplier: safeMult,
      officialReferenceNote: `官方 $${inUSD} / $${outUSD}${cacheNote} (1M) · 汇率 ${safeFx} · ${safeMult.toFixed(2)}×`,
    };
  }

  const uUSD = Number(officialUnitUSD);
  if (!Number.isFinite(uUSD) || uUSD <= 0) {
    return {
      pricingStatus: "pending_pricing",
      inputPricePerMillion: 0,
      outputPricePerMillion: 0,
      cachePricePerMillion: 0,
      unitPriceYuan: 0,
      fxUsdToCny: safeFx,
      markupMultiplier: safeMult,
      officialReferenceNote: "官方目录暂无可核验单价（待定价，禁止 0 元售卖）",
    };
  }
  const unitLabel = pricingMode === "per_second" ? "秒" : pricingMode === "per_minute" ? "分钟" : "张";
  const retailUnit = roundPrice4(uUSD * safeFx * safeMult);
  return {
    pricingStatus: "priced",
    inputPricePerMillion: 0,
    outputPricePerMillion: 0,
    cachePricePerMillion: 0,
    unitPriceYuan: retailUnit,
    fxUsdToCny: safeFx,
    markupMultiplier: safeMult,
    officialReferenceNote: `官方 $${uUSD}/${unitLabel} · 汇率 ${safeFx} · ${safeMult.toFixed(2)}×`,
  };
}

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

  // Exclude non-generation utility models from interactive catalog (keep realtime voice models!)
  const excludedTokens = ["embedding", "text-embedding", "moderation", "whisper", "transcribe", "tts-", "-tts", "rerank", "bge-", "lyria"];
  if (excludedTokens.some((tok) => lower.includes(tok))) return null;

  const vendor = inferVendorFromModelID(id, upstreamProvider);
  const displayName = String(rawMeta.display_name || rawMeta.displayName || id).trim();

  // 0. Realtime Voice models
  if (lower.includes("realtime") || lower.includes("native-audio")) {
    return {
      modelID: id,
      upstreamProvider,
      vendor,
      displayName,
      capabilities: ["realtime_voice"],
      pricingMode: "per_minute",
      inputPricePerMillion: 0,
      outputPricePerMillion: 0,
      unitPriceYuan: 0,
      supportsThinking: false,
      supportedParams: {
        protocol: "openai_realtime_ws",
        sampleRateHz: 24000,
      },
    };
  }

  // 1. Video generation models
  const isSora = lower === "sora-2" || lower === "sora-2-pro" || lower.startsWith("sora-2-");
  const isVeo = lower.startsWith("veo-");
  const isGeminiOmni = lower.startsWith("gemini-omni-");
  const isWanVideo = /^wan\d/.test(lower) || lower.includes("happyhorse");
  const isSeedance = lower.includes("seedance");
  const isKling = lower.startsWith("kling-");
  const isGrokVideo = lower.includes("grok-imagine-video");
  const isMiniMaxVideo = lower.startsWith("minimax-h") || lower.includes("hailuo");

  if (isSora || isVeo || isGeminiOmni || isWanVideo || isSeedance || isKling || isGrokVideo || isMiniMaxVideo || lower.includes("-video") || lower.includes("t2v") || lower.includes("i2v")) {
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
    } else if (isGeminiOmni) {
      supportedParams = {
        seconds: ["3", "4", "5", "8", "10", "15"],
        defaultSeconds: "5",
        sizes: ["1280x720", "720x1280", "1920x1080", "1080x1920"],
        defaultSize: "1280x720",
        supportsInputReference: true,
        protocol: upstreamProvider === "gemini" ? "gemini_interactions" : "aihubmix_videos",
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
      const isWan26Plus = lower.startsWith("wan2.6") || lower.startsWith("wan2.7") || lower.startsWith("wan3.");
      supportedParams = {
        seconds: isWan26Plus ? ["4", "5", "8", "10", "15"] : ["5", "10"],
        defaultSeconds: "5",
        sizes: ["1280x720", "720x1280", "1920x1080", "1080x1920"],
        defaultSize: "1280x720",
        supportsInputReference: lower.includes("i2v") || lower.includes("r2v"),
        protocol: "aihubmix_videos",
      };
    } else if (isKling) {
      supportedParams = {
        seconds: ["5", "10"],
        defaultSeconds: "5",
        sizes: ["1280x720", "720x1280", "1920x1080", "1080x1920"],
        defaultSize: "1280x720",
        supportsInputReference: true,
        protocol: "aihubmix_kling",
      };
    } else if (isSeedance) {
      supportedParams = {
        seconds: ["4", "5", "8", "10", "12"],
        defaultSeconds: "5",
        sizes: ["1280x720", "720x1280"],
        defaultSize: "1280x720",
        supportsInputReference: true,
        protocol: "aihubmix_seedance",
      };
    } else if (isGrokVideo) {
      supportedParams = {
        seconds: ["4", "5", "8", "10"],
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
  const pricingMode = row.pricing_mode || "token";
  const inCNY = Number(row.input_price_per_million || 0);
  const outCNY = Number(row.output_price_per_million || 0);
  const cacheCNY = Number(row.cache_price_per_million || 0);
  const unitCNY = Number(row.unit_price_yuan || 0);
  const hasRetailPrice = pricingMode === "token" ? (inCNY > 0 || outCNY > 0) : unitCNY > 0;
  const pricingStatus = row.pricing_status === "priced" || (hasRetailPrice && row.pricing_status !== "pending_pricing")
    ? "priced"
    : "pending_pricing";
  return {
    id: row.model_id,
    upstreamProvider: row.upstream_provider,
    provider: row.upstream_provider,
    vendor: row.vendor || inferVendorFromModelID(row.model_id, row.upstream_provider),
    displayName: row.display_name || row.model_id,
    capabilities,
    pricingMode,
    inputPricePerMillion: inCNY,
    outputPricePerMillion: outCNY,
    cachePricePerMillion: cacheCNY,
    unitPriceYuan: unitCNY,
    officialInputUSDPerMillion: row.official_input_usd_per_million !== null && row.official_input_usd_per_million !== undefined
      ? Number(row.official_input_usd_per_million)
      : null,
    officialOutputUSDPerMillion: row.official_output_usd_per_million !== null && row.official_output_usd_per_million !== undefined
      ? Number(row.official_output_usd_per_million)
      : null,
    officialCacheUSDPerMillion: row.official_cache_usd_per_million !== null && row.official_cache_usd_per_million !== undefined
      ? Number(row.official_cache_usd_per_million)
      : null,
    officialUnitUSD: row.official_unit_usd !== null && row.official_unit_usd !== undefined
      ? Number(row.official_unit_usd)
      : null,
    fxUsdToCny: Number(row.fx_usd_to_cny || DEFAULT_FX_USD_TO_CNY),
    markupMultiplier: Number(row.markup_multiplier || UNIFORM_MARKUP_MULTIPLIER),
    pricingStatus,
    priceVersion: Number(row.price_version || 1),
    lastSyncedAt: row.last_synced_at || null,
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
  const status = row.pricing_status ?? row.pricingStatus;
  if (status === "pending_pricing") {
    // Allow if retail prices are explicitly > 0 ONLY when status wasn't forced pending_pricing
    const mode = String(row.pricing_mode || row.pricingMode || "token");
    const retailOK = mode === "token"
      ? (Number(row.input_price_per_million ?? row.inputPricePerMillion ?? 0) > 0 || Number(row.output_price_per_million ?? row.outputPricePerMillion ?? 0) > 0)
      : Number(row.unit_price_yuan ?? row.unitPriceYuan ?? 0) > 0;
    if (!retailOK) return false;
  }
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
 * Official USD base prices (if verifiable) are recorded alongside `pricing_status`, keeping retail prices
 * controlled by Admin's pricing preview/approval workflow (never billed at ¥0!).
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

        const official = lookupVerifiedOfficialPricingUSD(meta.modelID, meta.pricingMode, item);

        await env.DB.prepare(
          `INSERT INTO model_catalog
           (model_id, upstream_provider, vendor, display_name, capabilities_json, pricing_mode,
            input_price_per_million, output_price_per_million, cache_price_per_million, unit_price_yuan,
            official_input_usd_per_million, official_output_usd_per_million, official_cache_usd_per_million, official_unit_usd,
            fx_usd_to_cny, markup_multiplier, pricing_status, supports_thinking,
            supported_params_json, enabled, probe_status, discovered_from, deprecated, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0, 0, ?, ?, ?, ?, ?, ?, 'pending_pricing', ?, ?, 0, 'unverified', ?, 0, datetime('now'))
           ON CONFLICT(model_id) DO UPDATE SET
             upstream_provider = excluded.upstream_provider,
             vendor = excluded.vendor,
             capabilities_json = excluded.capabilities_json,
             pricing_mode = excluded.pricing_mode,
             official_input_usd_per_million = COALESCE(excluded.official_input_usd_per_million, model_catalog.official_input_usd_per_million),
             official_output_usd_per_million = COALESCE(excluded.official_output_usd_per_million, model_catalog.official_output_usd_per_million),
             official_cache_usd_per_million = COALESCE(excluded.official_cache_usd_per_million, model_catalog.official_cache_usd_per_million),
             official_unit_usd = COALESCE(excluded.official_unit_usd, model_catalog.official_unit_usd),
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
          official?.inputUSD ?? null,
          official?.outputUSD ?? null,
          official?.cacheUSD ?? null,
          official?.unitUSD ?? null,
          Number(env.USD_TO_CNY_RATE || DEFAULT_FX_USD_TO_CNY),
          UNIFORM_MARKUP_MULTIPLIER,
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
      const isGeminiInteractions = params.protocol === "gemini_interactions" && supply.style === "gemini";
      const isGeminiVeo = params.protocol === "gemini_veo" && supply.style === "gemini";
      let url = isGeminiInteractions
        ? `${supply.baseOrigin}/v1beta/interactions`
        : isGeminiVeo
          ? `${supply.chatURL}/${encodeURIComponent(row.model_id)}:predictLongRunning`
          : (supply.videosURL || `${supply.baseOrigin}/v1/videos`);
      const headers = { "Content-Type": "application/json", ...(supply.extraHeaders || {}) };
      let payload;
      if (isGeminiInteractions) {
        headers["x-goog-api-key"] = supply.key;
        payload = {
          model: row.model_id,
          input: "Gentle ocean waves at sunrise, fixed wide shot",
          response_format: {
            type: "video",
            delivery: "uri",
            resolution: "360p",
            aspect_ratio: "16:9",
            duration: "3s",
          },
          background: true,
          store: true,
          stream: false,
        };
      } else if (isGeminiVeo) {
        headers["x-goog-api-key"] = supply.key;
        payload = {
          instances: [{ prompt: "Gentle ocean waves at sunrise, cinematic wide shot" }],
          parameters: { aspectRatio: "16:9", durationSeconds: Number(params.defaultSeconds || 8), resolution: "720p" },
        };
      } else if (params.protocol === "grok_videos" && supply.provider === "grok") {
        headers.Authorization = `Bearer ${supply.key}`;
        payload = { model: row.model_id, prompt: "Gentle ocean waves at sunrise", duration: Number(params.defaultSeconds || 5), aspect_ratio: "16:9", resolution: "720p" };
      } else if (params.protocol === "aihubmix_kling") {
        headers.Authorization = `Bearer ${supply.key}`;
        payload = {
          model: row.model_id,
          prompt: "Gentle ocean waves at sunrise, soft golden light",
          duration: String(params.defaultSeconds || "5"),
          aspect_ratio: "16:9",
          mode: "std",
          sound: "off",
        };
      } else if (params.protocol === "aihubmix_seedance") {
        headers.Authorization = `Bearer ${supply.key}`;
        payload = {
          model: row.model_id,
          prompt: "Gentle ocean waves at sunrise, soft golden light",
          extra_body: {
            ratio: "16:9",
            duration: Number(params.defaultSeconds || 5),
            resolution: "720p",
            watermark: false,
          },
        };
      } else {
        headers.Authorization = `Bearer ${supply.key}`;
        payload = {
          model: row.model_id,
          prompt: "Gentle ocean waves at sunrise, soft golden light",
          seconds: String(params.defaultSeconds || "5"),
          size: String(params.defaultSize || "1280x720"),
        };
      }

      let res = await fetch(url, { method: "POST", headers, body: JSON.stringify(payload) });
      let raw = await res.text();
      // Auto-upgrade to AIHubMix unified /ai/v1/videos if model requires new protocol
      if (!res.ok && supply.provider === "aihubmix" && (raw.includes("protocol_not_supported") || raw.includes("/ai/v1/videos"))) {
        url = `${supply.baseOrigin}/ai/v1/videos`;
        res = await fetch(url, {
          method: "POST",
          headers,
          body: JSON.stringify({
            model: row.model_id,
            prompt: "Gentle ocean waves at sunrise, soft golden light",
            duration: Number(params.defaultSeconds || 5),
            aspect_ratio: "16:9",
            resolution: "720p",
          }),
        });
        raw = await res.text();
      }
      const latency = Date.now() - started;
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
    const cachePrice = item.cachePricePerMillion !== undefined ? Math.max(0, Number(item.cachePricePerMillion || 0)) : Number(row.cache_price_per_million || 0);
    const unitPrice = item.unitPriceYuan !== undefined ? Math.max(0, Number(item.unitPriceYuan || 0)) : Number(row.unit_price_yuan || 0);
    const wantEnabled = item.enabled !== undefined ? Boolean(item.enabled) : Boolean(row.enabled);
    const note = item.officialReferenceNote !== undefined ? String(item.officialReferenceNote).trim().slice(0, 120) : (row.official_reference_note || "");

    const candidateCheck = {
      pricing_mode: row.pricing_mode,
      input_price_per_million: inputPrice,
      output_price_per_million: outputPrice,
      unit_price_yuan: unitPrice,
    };
    const nextPricingStatus = isModelRowPriced(candidateCheck) ? "priced" : "pending_pricing";

    if (wantEnabled) {
      if (row.deprecated) {
        rejected.push({ id: modelID, code: "deprecated", reason: "该模型已下线，禁止启用。" });
        continue;
      }
      if (row.probe_status !== "verified") {
        rejected.push({ id: modelID, code: "not_verified", reason: `该模型尚未通过真实权限与接口实测（当前状态：${row.probe_status}），禁止启用。` });
        continue;
      }
      if (nextPricingStatus !== "priced") {
        rejected.push({ id: modelID, code: "unpriced", pricingStatus: "pending_pricing", reason: "该模型处于「待定价」状态（无有效售价 > 0），严禁启用或按 0 元计费。" });
        continue;
      }
    }

    await env.DB.prepare(
      `UPDATE model_catalog
       SET display_name = ?, input_price_per_million = ?, output_price_per_million = ?,
           cache_price_per_million = ?, unit_price_yuan = ?, pricing_status = ?,
           official_reference_note = ?, enabled = ?, updated_at = datetime('now')
       WHERE model_id = ?`
    ).bind(
      displayName || modelID,
      inputPrice,
      outputPrice,
      cachePrice,
      unitPrice,
      nextPricingStatus,
      note,
      wantEnabled ? 1 : 0,
      modelID
    ).run();

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

async function loadPricingMetaState(env) {
  const latestVer = await env.DB.prepare(
    "SELECT version, fx_usd_to_cny, markup_multiplier, source_url, changed_count, pending_count, operator_id, approved_at FROM pricing_versions ORDER BY version DESC LIMIT 1"
  ).first();
  const counts = await env.DB.prepare(
    `SELECT
       COUNT(*) AS total_count,
       SUM(CASE WHEN pricing_status = 'priced' OR (pricing_mode = 'token' AND (input_price_per_million > 0 OR output_price_per_million > 0)) OR (pricing_mode != 'token' AND unit_price_yuan > 0) THEN 1 ELSE 0 END) AS priced_count,
       MAX(last_synced_at) AS max_synced_at
     FROM model_catalog WHERE deprecated = 0`
  ).first();
  const totalCount = Number(counts?.total_count || 0);
  const pricedCount = Number(counts?.priced_count || 0);
  return {
    markupMultiplier: Number(latestVer?.markup_multiplier || UNIFORM_MARKUP_MULTIPLIER),
    fxUsdToCny: Number(latestVer?.fx_usd_to_cny || env.USD_TO_CNY_RATE || DEFAULT_FX_USD_TO_CNY),
    priceVersion: Number(latestVer?.version || 1),
    lastSyncedAt: latestVer?.approved_at || counts?.max_synced_at || null,
    sourceURL: latestVer?.source_url || AIHUBMIX_OFFICIAL_PRICING_SOURCE,
    pricedCount,
    pendingPricingCount: Math.max(0, totalCount - pricedCount),
  };
}

function buildPricingSyncProposal(rows, fxRate, multiplier, officialOverrides = {}) {
  const safeFx = Number.isFinite(Number(fxRate)) && Number(fxRate) > 0 ? Number(fxRate) : DEFAULT_FX_USD_TO_CNY;
  const safeMult = Number.isFinite(Number(multiplier)) && Number(multiplier) >= 1.0 ? Number(multiplier) : UNIFORM_MARKUP_MULTIPLIER;

  const diffs = [];
  let changed = 0;
  let unchanged = 0;
  let pendingPricing = 0;

  for (const row of rows) {
    if (row.deprecated) continue;
    const mode = row.pricing_mode || "token";
    const override = officialOverrides?.[row.model_id] || null;
    const known = lookupVerifiedOfficialPricingUSD(row.model_id, mode, override ? { pricing: override } : {});

    // Always resolve from verifiable official USD base (explicit override > stored official USD > verified AIHubMix official catalog)
    // NEVER compute from existing retail CNY!
    const officialInputUSD = override?.inputUSD ?? row.official_input_usd_per_million ?? known?.inputUSD ?? null;
    const officialOutputUSD = override?.outputUSD ?? row.official_output_usd_per_million ?? known?.outputUSD ?? null;
    const officialCacheUSD = override?.cacheUSD ?? row.official_cache_usd_per_million ?? known?.cacheUSD ?? null;
    const officialUnitUSD = override?.unitUSD ?? row.official_unit_usd ?? known?.unitUSD ?? null;

    const computed = computeUniformMarkupPrices(
      { pricingMode: mode, officialInputUSD, officialOutputUSD, officialCacheUSD, officialUnitUSD },
      safeFx,
      safeMult
    );

    const oldIn = Number(row.input_price_per_million || 0);
    const oldOut = Number(row.output_price_per_million || 0);
    const oldCache = Number(row.cache_price_per_million || 0);
    const oldUnit = Number(row.unit_price_yuan || 0);
    const oldStatus = row.pricing_status || (isModelRowPriced(row) ? "priced" : "pending_pricing");

    const priceChanged =
      Math.abs(oldIn - computed.inputPricePerMillion) > 0.0001 ||
      Math.abs(oldOut - computed.outputPricePerMillion) > 0.0001 ||
      Math.abs(oldCache - computed.cachePricePerMillion) > 0.0001 ||
      Math.abs(oldUnit - computed.unitPriceYuan) > 0.0001 ||
      oldStatus !== computed.pricingStatus;

    if (computed.pricingStatus === "pending_pricing") {
      pendingPricing++;
    }
    if (priceChanged) {
      changed++;
    } else {
      unchanged++;
    }

    diffs.push({
      id: row.model_id,
      displayName: row.display_name || row.model_id,
      vendor: row.vendor || inferVendorFromModelID(row.model_id, row.upstream_provider),
      capabilities: parseCapabilities(row.capabilities_json),
      pricingMode: mode,
      probeStatus: row.probe_status || "unverified",
      enabled: Boolean(row.enabled),
      changed: priceChanged,
      pricingStatus: computed.pricingStatus,
      officialInputUSD,
      officialOutputUSD,
      officialCacheUSD,
      officialUnitUSD,
      oldInputPricePerMillion: oldIn,
      newInputPricePerMillion: computed.inputPricePerMillion,
      oldOutputPricePerMillion: oldOut,
      newOutputPricePerMillion: computed.outputPricePerMillion,
      oldCachePricePerMillion: oldCache,
      newCachePricePerMillion: computed.cachePricePerMillion,
      oldUnitPriceYuan: oldUnit,
      newUnitPriceYuan: computed.unitPriceYuan,
      officialReferenceNote: computed.officialReferenceNote,
    });
  }

  return {
    fxUsdToCny: safeFx,
    markupMultiplier: safeMult,
    sourceURL: AIHUBMIX_OFFICIAL_PRICING_SOURCE,
    summary: {
      total: diffs.length,
      changed,
      unchanged,
      pendingPricing,
    },
    diffs,
  };
}

/**
 * Preview uniform 1.50× AIHubMix official-base pricing sync WITHOUT writing to DB yet.
 * Admin reviews price changes & pending_pricing models before approving.
 */
export async function handleAdminPreviewPricingSync(request, env, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可预览统一倍率定价同步。", code: "admin_forbidden" }, 403);
  }
  let body = {};
  try { body = await request.json(); } catch {}
  const meta = await loadPricingMetaState(env);
  const fxRate = body.fxUsdToCny !== undefined ? Number(body.fxUsdToCny) : meta.fxUsdToCny;
  const multiplier = body.markupMultiplier !== undefined ? Number(body.markupMultiplier) : UNIFORM_MARKUP_MULTIPLIER;

  if (!Number.isFinite(fxRate) || fxRate <= 0 || fxRate > 30) {
    return json({ error: "汇率 fxUsdToCny 非法（需在 0~30 之间）。" }, 400);
  }
  if (!Number.isFinite(multiplier) || multiplier < 1.0 || multiplier > 10.0) {
    return json({ error: "统一倍率 markupMultiplier 非法（需在 1.0~10.0 之间）。" }, 400);
  }

  const rowsRes = await env.DB.prepare("SELECT * FROM model_catalog WHERE deprecated = 0 ORDER BY enabled DESC, vendor ASC, model_id ASC").all();
  const proposal = buildPricingSyncProposal(rowsRes.results || [], fxRate, multiplier, body.officialOverrides || {});

  return json({
    ok: true,
    currentVersion: meta.priceVersion,
    nextVersion: meta.priceVersion + 1,
    ...proposal,
  });
}

/**
 * Approves and applies uniform 1.50× official-base pricing to `model_catalog`.
 * Guarantees:
 * 1. Re-running sync ALWAYS calculates from official USD base (never compounds 1.5x twice!).
 * 2. Models lacking verified official USD price stay `pending_pricing` and `enabled = 0` (never ¥0!).
 * 3. Newly priced models are NOT auto-enabled (`enabled` stays untouched unless demoted to `pending_pricing`).
 * 4. Already-submitted in-flight jobs / credit_reservations retain their locked submission-time prices.
 */
export async function handleAdminApprovePricingSync(request, env, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可批准发布统一倍率定价。", code: "admin_forbidden" }, 403);
  }
  let body = {};
  try { body = await request.json(); } catch {}
  const meta = await loadPricingMetaState(env);
  const fxRate = body.fxUsdToCny !== undefined ? Number(body.fxUsdToCny) : meta.fxUsdToCny;
  const multiplier = body.markupMultiplier !== undefined ? Number(body.markupMultiplier) : UNIFORM_MARKUP_MULTIPLIER;
  const operatorID = String(body.operatorID || "admin").trim().slice(0, 64) || "admin";

  if (!Number.isFinite(fxRate) || fxRate <= 0 || fxRate > 30) {
    return json({ error: "汇率 fxUsdToCny 非法（需在 0~30 之间）。" }, 400);
  }
  if (!Number.isFinite(multiplier) || multiplier < 1.0 || multiplier > 10.0) {
    return json({ error: "统一倍率 markupMultiplier 非法（需在 1.0~10.0 之间）。" }, 400);
  }

  const rowsRes = await env.DB.prepare("SELECT * FROM model_catalog WHERE deprecated = 0 ORDER BY model_id ASC").all();
  const proposal = buildPricingSyncProposal(rowsRes.results || [], fxRate, multiplier, body.officialOverrides || {});
  const syncedAt = new Date().toISOString();

  const insertVer = await env.DB.prepare(
    `INSERT INTO pricing_versions (fx_usd_to_cny, markup_multiplier, source_url, changed_count, pending_count, snapshot_json, operator_id, approved_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    proposal.fxUsdToCny,
    proposal.markupMultiplier,
    proposal.sourceURL,
    proposal.summary.changed,
    proposal.summary.pendingPricing,
    JSON.stringify({ summary: proposal.summary, syncedAt }),
    operatorID,
    syncedAt
  ).run();

  const latestVerRow = await env.DB.prepare("SELECT MAX(version) AS v FROM pricing_versions").first();
  const newVersion = Number(latestVerRow?.v || insertVer?.meta?.last_row_id || (meta.priceVersion + 1));

  for (const item of proposal.diffs) {
    const forceDisable = item.pricingStatus !== "priced";
    await env.DB.prepare(
      `UPDATE model_catalog
       SET input_price_per_million = ?,
           output_price_per_million = ?,
           cache_price_per_million = ?,
           unit_price_yuan = ?,
           official_input_usd_per_million = ?,
           official_output_usd_per_million = ?,
           official_cache_usd_per_million = ?,
           official_unit_usd = ?,
           fx_usd_to_cny = ?,
           markup_multiplier = ?,
           pricing_status = ?,
           price_version = ?,
           last_synced_at = ?,
           official_reference_note = ?,
           enabled = CASE WHEN ? = 1 THEN 0 ELSE enabled END,
           updated_at = datetime('now')
       WHERE model_id = ?`
    ).bind(
      item.newInputPricePerMillion,
      item.newOutputPricePerMillion,
      item.newCachePricePerMillion,
      item.newUnitPriceYuan,
      item.officialInputUSD,
      item.officialOutputUSD,
      item.officialCacheUSD,
      item.officialUnitUSD,
      proposal.fxUsdToCny,
      proposal.markupMultiplier,
      item.pricingStatus,
      newVersion,
      syncedAt,
      item.officialReferenceNote,
      forceDisable ? 1 : 0,
      item.id
    ).run();
  }

  return json({
    ok: true,
    priceVersion: newVersion,
    syncedAt,
    fxUsdToCny: proposal.fxUsdToCny,
    markupMultiplier: proposal.markupMultiplier,
    sourceURL: proposal.sourceURL,
    summary: proposal.summary,
    diffs: proposal.diffs,
  });
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
  const filterPricingStatus = String(url.searchParams.get("pricingStatus") || "").trim().toLowerCase();
  const searchQuery = String(url.searchParams.get("q") || "").trim().toLowerCase();
  const page = Math.max(1, parseInt(url.searchParams.get("page") || "1", 10) || 1);
  const rawLimit = url.searchParams.get("limit");
  const limit = rawLimit ? Math.max(1, Math.min(200, parseInt(rawLimit, 10) || 50)) : 200;

  const rows = await env.DB.prepare("SELECT * FROM model_catalog ORDER BY enabled DESC, vendor ASC, model_id ASC").all();
  let models = (rows.results || []).map(serializeCatalogRow);

  if (filterVendor) models = models.filter((m) => m.vendor.toLowerCase() === filterVendor);
  if (filterProvider) models = models.filter((m) => m.upstreamProvider.toLowerCase() === filterProvider);
  if (filterCapability) {
    if (filterCapability === "image") {
      models = models.filter((m) => m.capabilities.includes("text_to_image") || m.capabilities.includes("image_edit"));
    } else if (filterCapability === "voice") {
      models = models.filter((m) => m.capabilities.includes("realtime_voice"));
    } else {
      models = models.filter((m) => m.capabilities.includes(filterCapability));
    }
  }
  if (filterStatus) models = models.filter((m) => m.probeStatus.toLowerCase() === filterStatus);
  if (filterPricingStatus) models = models.filter((m) => m.pricingStatus.toLowerCase() === filterPricingStatus);
  if (searchQuery) {
    models = models.filter(
      (m) =>
        m.id.toLowerCase().includes(searchQuery) ||
        m.displayName.toLowerCase().includes(searchQuery) ||
        m.vendor.toLowerCase().includes(searchQuery)
    );
  }

  const totalCount = models.length;
  const enabledVerifiedCount = models.filter((m) => m.enabled && !m.deprecated && m.probeStatus === "verified" && isModelRowPriced(m)).length;
  const totalPages = Math.max(1, Math.ceil(totalCount / limit));
  const offset = (page - 1) * limit;
  const pagedModels = models.slice(offset, offset + limit);

  const allowlist = [...parseAIHubMixAllowlist(env)];
  const config = await loadCommercialConfig(env);
  const pricingMeta = await loadPricingMetaState(env);
  const configuredUpstreams = ["aihubmix", "openAI", "deepSeek", "gemini", "claude", "grok"]
    .filter((p) => Boolean(buildUpstreamSupplyEndpoints(p, env)));

  return json({
    ok: true,
    configuredUpstreams,
    legacyAIHubMixAllowlist: allowlist,
    legacyPricingCount: (config.pricing || []).length,
    pricingMeta,
    page,
    limit,
    totalCount,
    totalPages,
    hasMore: offset + pagedModels.length < totalCount,
    enabledVerifiedCount,
    models: pagedModels,
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
