/**
 * WUMIND Managed Media Gateway Routes (Image Generation, Reference-Image Editing & Video Generation):
 * - Enforces dynamic catalog capability, permission, and per-model parameter validation (zero silent fallback).
 * - Uses atomic pre-request credit reservation -> post-success actual settlement -> failure full release.
 * - Uses idempotency_key deduplication to prevent duplicate generation & double-charging on retries.
 */

import {
  extractIdempotencyKey,
  reserveCreditAtomic,
  settleReservationAtomic,
  releaseReservationAtomic,
} from "./billing-safety.js";
import {
  resolveCatalogModelForExecution,
  buildUpstreamSupplyEndpoints,
  getPublicCallableModels,
} from "./model-catalog.js";
import {
  isUserBillingExempt,
  checkAdminExemptQuota,
  recordAdminExemptUsage,
  isUpstreamBalanceError,
  upsertWorkFromGatewayTask,
} from "./admin-ops-works.js";

const MICROS_PER_YUAN = 1_000_000;

function microsToYuan(micros) {
  return Math.round((Number(micros || 0) / MICROS_PER_YUAN) * 10000) / 10000;
}

function yuanToMicros(yuan) {
  const n = Number(yuan);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.round(n * MICROS_PER_YUAN);
}

function decodeBase64Bytes(b64) {
  const clean = String(b64 || "").replace(/^data:[^;]+;base64,/i, "").replace(/\s+/g, "");
  const bin = atob(clean);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function sanitizeErrorMessage(status, rawText) {
  let msg = "";
  let code = "";
  try {
    const parsed = JSON.parse(rawText);
    msg = parsed?.error?.message || parsed?.message || parsed?.error || "";
    code = parsed?.error?.code || parsed?.code || "";
    if (typeof msg === "object") msg = JSON.stringify(msg);
  } catch {
    msg = String(rawText || "");
  }
  const clean = String(msg || "").replace(/sk-[A-Za-z0-9_-]{8,}/g, "sk-***").trim().slice(0, 320);
  return { clean: clean || `上游接口返回 HTTP ${status}`, code: String(code || "") };
}

function isValidMP4Header(bytes) {
  return bytes instanceof Uint8Array &&
    bytes.length >= 12 &&
    bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70; // "ftyp"
}

/**
 * Handles BOTH POST /v1/images/generations (text-to-image) AND POST /v1/images/edits (reference image editing).
 * If a referenceImage is supplied, strictly requires `image_edit` capability — NEVER silently drops the reference image!
 */
export async function handleManagedImageRoute(request, env, forceEditMode, {
  json,
  authenticateUser,
  loadCommercialConfig,
  parseAIHubMixAllowlist,
  randomCode,
}) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权，请重新激活 WUMIND 账户。" }, 401);

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "请求 JSON 格式不正确。" }, 400);
  }

  const modelID = String(body.model || "").trim();
  const prompt = String(body.prompt || "").trim();
  if (!prompt || prompt.length > 8000) {
    return json({ error: "请输入有效的生图提示词（1~8000 字）。" }, 400);
  }

  const refObj = body.referenceImage && typeof body.referenceImage === "object" ? body.referenceImage : null;
  const hasReferenceImage = Boolean(forceEditMode || (refObj && typeof refObj.base64Data === "string" && refObj.base64Data.trim().length > 0));
  if (forceEditMode && (!refObj || !refObj.base64Data)) {
    return json({ error: "图生图/参考图编辑接口缺少 referenceImage.base64Data。", code: "missing_reference_image" }, 400);
  }

  const n = Math.min(4, Math.max(1, parseInt(body.n || 1, 10) || 1));
  const size = String(body.size || "1024x1024").trim();
  const quality = ["low", "medium", "high"].includes(String(body.quality || "").toLowerCase())
    ? String(body.quality).toLowerCase()
    : "medium";
  const outputFormat = String(body.outputFormat || body.output_format || "jpeg").toLowerCase() === "png" ? "png" : "jpeg";

  const config = await loadCommercialConfig(env);
  const requiredCap = hasReferenceImage ? "image_edit" : "text_to_image";
  const resolved = await resolveCatalogModelForExecution(env, config, modelID, requiredCap, parseAIHubMixAllowlist);
  if (resolved.error || !resolved.model || !resolved.supply) {
    // Provide helpful list of actually enabled reference-image-capable models when capability mismatches
    let suggestedModels = [];
    if (resolved.code === "reference_image_not_supported") {
      const callable = await getPublicCallableModels(env, config.pricing, parseAIHubMixAllowlist);
      suggestedModels = callable.filter((m) => m.capabilities.includes("image_edit")).map((m) => ({
        id: m.id,
        displayName: m.displayName,
        vendor: m.vendor,
        unitPriceYuan: m.unitPriceYuan,
      }));
    }
    return json({
      error: resolved.error,
      code: resolved.code || "model_unavailable",
      suggestedModels,
    }, resolved.status || 403);
  }

  const { model, supply } = resolved;
  const unitMicros = Math.max(10_000, yuanToMicros(model.unitPriceYuan || 0));
  const reserveMicros = unitMicros * n;
  const idempotencyKey = extractIdempotencyKey(request, body);
  const requestStartMs = Date.now();
  const isExempt = isUserBillingExempt(env, user);

  let reservationID = null;
  if (isExempt) {
    // Check idempotency against user_works for exempt admins too so retries never double-generate
    if (idempotencyKey) {
      const existingWork = await env.DB.prepare(
        "SELECT * FROM user_works WHERE user_id = ? AND idempotency_key = ?"
      ).bind(user.id, idempotencyKey).first();
      if (existingWork && existingWork.status === "completed" && existingWork.asset_base64) {
        return json({
          ok: true,
          workID: existingWork.id,
          model: existingWork.model_id,
          mode: hasReferenceImage ? "image_edit" : "text_to_image",
          data: [{ b64_json: existingWork.asset_base64, mime_type: existingWork.asset_mime || "image/png" }],
          idempotentReplay: true,
        });
      }
    }
    const capCheck = await checkAdminExemptQuota(env, user, reserveMicros);
    if (!capCheck.allowed) {
      return json({ error: capCheck.error, code: capCheck.code }, capCheck.status);
    }
  } else {
    // Atomic pre-request credit reservation + idempotency deduplication
    const reserve = await reserveCreditAtomic(env, {
      userID: user.id,
      idempotencyKey,
      kind: hasReferenceImage ? "image_edit" : "image",
      modelID: model.id,
      reserveMicros,
      ttlSeconds: 300,
      randomCode,
    });

    if (reserve.duplicateSettled && reserve.cachedResponse) {
      return json({ ...reserve.cachedResponse, idempotentReplay: true });
    }
    if (reserve.duplicateInFlight) {
      return json({ error: "相同生图请求正在处理中，请勿重复提交。", code: "duplicate_in_flight" }, 409);
    }
    if (reserve.insufficient) {
      return json({
        error: `可用余额不足（可用 ¥${microsToYuan(reserve.availableMicros)}，本次需预留 ¥${microsToYuan(reserve.requiredMicros)}），请先充值。`,
        code: "insufficient_balance",
        availableYuan: microsToYuan(reserve.availableMicros),
        requiredReserveYuan: microsToYuan(reserve.requiredMicros),
      }, 402);
    }
    reservationID = reserve.reservationID;
  }

  const workID = `WRK-${randomCode(12)}`;
  const workParams = { size, quality, outputFormat, n, hasReferenceImage };
  const refMeta = hasReferenceImage ? [{ filename: String(refObj?.filename || "reference.png").slice(0, 64), mimeType: String(refObj?.mimeType || "image/png") }] : [];
  await upsertWorkFromGatewayTask(env, {
    id: workID,
    userID: user.id,
    workType: "image",
    title: prompt.slice(0, 48),
    prompt,
    modelID: model.id,
    params: workParams,
    referenceAssets: refMeta,
    status: "in_progress",
    progress: 15,
    idempotencyKey,
  });

  const gatewaySubmitMs = Math.max(1, Date.now() - requestStartMs);
  const upstreamStartMs = Date.now();
  let targetURL = "";

  try {
    let upstreamRes;
    const isGeminiOfficial = model.supportedParams?.protocol === "gemini_generate_content" && supply.style === "gemini";

    if (isGeminiOfficial) {
      targetURL = `${supply.chatURL}/${encodeURIComponent(model.id)}:generateContent`;
      const parts = [];
      if (hasReferenceImage && refObj?.base64Data) {
        const mime = typeof refObj.mimeType === "string" && refObj.mimeType.startsWith("image/") ? refObj.mimeType : "image/png";
        parts.push({ inline_data: { mime_type: mime, data: refObj.base64Data.replace(/^data:[^;]+;base64,/i, "") } });
      }
      parts.push({ text: prompt });
      upstreamRes = await fetch(targetURL, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": supply.key },
        body: JSON.stringify({
          contents: [{ role: "user", parts }],
          generationConfig: {
            responseModalities: ["IMAGE"],
            imageConfig: { imageSize: quality === "high" ? "2K" : "1K" },
          },
        }),
      });
    } else if (hasReferenceImage) {
      // Real multipart/form-data POST /v1/images/edits (OpenAI & AIHubMix spec)
      targetURL = supply.imageEditURL || `${supply.baseOrigin}/v1/images/edits`;
      const mime = typeof refObj.mimeType === "string" && refObj.mimeType.startsWith("image/") ? refObj.mimeType : "image/png";
      const ext = mime.includes("jpeg") || mime.includes("jpg") ? "jpg" : mime.includes("webp") ? "webp" : "png";
      const imgBytes = decodeBase64Bytes(refObj.base64Data);
      if (imgBytes.length === 0 || imgBytes.length > 10 * 1024 * 1024) {
        if (reservationID) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: "invalid_reference_image_size" });
        await upsertWorkFromGatewayTask(env, { id: workID, userID: user.id, workType: "image", title: prompt.slice(0, 48), prompt, modelID: model.id, params: workParams, status: "failed", progress: 0, errorMessage: "参考图文件为空或超过 10MB 限制。" });
        return json({ error: "参考图文件为空或超过 10MB 限制。", code: "invalid_reference_image", workID }, 400);
      }

      const form = new FormData();
      form.append("model", model.id);
      form.append("prompt", prompt);
      form.append("n", String(n));
      form.append("size", size);
      form.append("quality", quality);
      form.append("output_format", outputFormat);
      form.append("image", new Blob([imgBytes], { type: mime }), String(refObj.filename || `reference.${ext}`).slice(0, 64));

      upstreamRes = await fetch(targetURL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${supply.key}`,
          ...(supply.extraHeaders || {}),
        },
        body: form,
      });
    } else {
      targetURL = supply.imageGenURL || `${supply.baseOrigin}/v1/images/generations`;
      const reqPayload = {
        model: model.id,
        prompt,
        n,
        size,
        quality,
        output_format: outputFormat,
      };
      if (supply.provider === "grok") {
        delete reqPayload.output_format;
        reqPayload.response_format = "b64_json";
      }
      upstreamRes = await fetch(targetURL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${supply.key}`,
          ...(supply.extraHeaders || {}),
        },
        body: JSON.stringify(reqPayload),
      });
    }

    const upstreamGenerateMs = Math.max(1, Date.now() - upstreamStartMs);
    const rawText = await upstreamRes.text();
    if (!upstreamRes.ok) {
      const { clean, code } = sanitizeErrorMessage(upstreamRes.status, rawText);
      if (reservationID) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: `upstream_${upstreamRes.status}` });
      const upstreamOutOfFunds = isUpstreamBalanceError(upstreamRes.status, rawText);
      const errMsg = upstreamOutOfFunds
        ? "上游 API 余额不足，请管理员前往上游控制台充值（非 App 钱包余额问题）。"
        : `上游生图接口拒绝请求（${clean}），本次未扣费。`;
      await upsertWorkFromGatewayTask(env, {
        id: workID,
        userID: user.id,
        workType: "image",
        title: prompt.slice(0, 48),
        prompt,
        modelID: model.id,
        params: workParams,
        referenceAssets: refMeta,
        status: "failed",
        progress: 0,
        errorMessage: errMsg,
        timing: { gatewaySubmitMs, upstreamGenerateMs },
      });
      return json({
        error: errMsg,
        code: upstreamOutOfFunds ? "upstream_balance_insufficient" : (code || `upstream_http_${upstreamRes.status}`),
        workID,
        modelID: model.id,
        endpoint: targetURL,
        httpStatus: upstreamRes.status,
      }, upstreamOutOfFunds ? 502 : (upstreamRes.status >= 400 && upstreamRes.status < 500 ? upstreamRes.status : 502));
    }

    let parsed;
    try { parsed = JSON.parse(rawText); } catch {
      if (reservationID) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: "invalid_upstream_json" });
      await upsertWorkFromGatewayTask(env, { id: workID, userID: user.id, workType: "image", title: prompt.slice(0, 48), prompt, modelID: model.id, params: workParams, status: "failed", progress: 0, errorMessage: "上游生图接口返回无法解析的数据。" });
      return json({ error: "上游生图接口返回无法解析的数据，本次未扣费。", code: "invalid_upstream_response", workID }, 502);
    }

    let images = [];
    if (isGeminiOfficial) {
      const parts = parsed?.candidates?.[0]?.content?.parts || [];
      images = parts
        .filter((p) => !p.thought && p.inlineData?.data)
        .map((p) => ({ b64_json: p.inlineData.data, mime_type: p.inlineData.mimeType || "image/png" }));
    } else {
      images = (parsed?.data || [])
        .filter((img) => typeof img?.b64_json === "string" && img.b64_json.length > 0)
        .map((img) => ({ b64_json: img.b64_json, mime_type: img.mime_type || (outputFormat === "png" ? "image/png" : "image/jpeg") }));
    }

    if (images.length === 0) {
      if (reservationID) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: "no_images_returned" });
      await upsertWorkFromGatewayTask(env, { id: workID, userID: user.id, workType: "image", title: prompt.slice(0, 48), prompt, modelID: model.id, params: workParams, status: "failed", progress: 0, errorMessage: "上游未返回有效图片数据。" });
      return json({ error: "上游未返回有效图片数据，本次未扣费。", code: "no_image", workID }, 502);
    }

    const actualMicros = unitMicros * images.length;
    const timing = { gatewaySubmitMs, upstreamGenerateMs };
    const responseData = {
      ok: true,
      workID,
      model: model.id,
      mode: hasReferenceImage ? "image_edit" : "text_to_image",
      endpoint: targetURL,
      timing,
      data: images,
    };

    const receipt = isExempt
      ? await recordAdminExemptUsage(env, {
          userID: user.id,
          kind: hasReferenceImage ? "image_edit" : "image",
          provider: model.upstreamProvider,
          model: model.id,
          upstreamCostMicros: actualMicros,
          note: `${hasReferenceImage ? "参考图编辑" : "文生图"} · ${images.length} 张 (${size})`,
        })
      : await settleReservationAtomic(env, {
          reservationID,
          userID: user.id,
          actualMicros,
          kind: hasReferenceImage ? "image_edit" : "image",
          provider: model.upstreamProvider,
          model: model.id,
          note: `${hasReferenceImage ? "参考图编辑" : "文生图"} · ${images.length} 张 (${size})`,
          responsePayload: responseData,
        });

    await upsertWorkFromGatewayTask(env, {
      id: workID,
      userID: user.id,
      workType: "image",
      title: prompt.slice(0, 48),
      prompt,
      modelID: model.id,
      params: workParams,
      referenceAssets: refMeta,
      status: "completed",
      progress: 100,
      idempotencyKey,
      assetMime: images[0].mime_type,
      assetBase64: images[0].b64_json,
      timing,
    });

    return json({
      ...responseData,
      billing: receipt,
    });
  } catch (err) {
    if (reservationID) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: "upstream_exception" });
    const msg = `生图请求异常（${String(err?.message || err).slice(0, 160)}），本次未扣费。`;
    await upsertWorkFromGatewayTask(env, { id: workID, userID: user.id, workType: "image", title: prompt.slice(0, 48), prompt, modelID: model.id, params: workParams, status: "failed", progress: 0, errorMessage: msg });
    return json({
      error: msg,
      code: "upstream_network_error",
      workID,
      modelID: model.id,
      endpoint: targetURL,
    }, 502);
  }
}

/**
 * Validates requested video parameters against the model's exact supported schema BEFORE reserving or calling upstream.
 */
export function validateVideoParamsForModel(model, rawSeconds, rawSize) {
  const params = model.supportedParams || {};
  const allowedSeconds = Array.isArray(params.seconds) && params.seconds.length > 0
    ? params.seconds.map(String)
    : ["4", "5", "8", "10", "12"];
  const allowedSizes = Array.isArray(params.sizes) && params.sizes.length > 0
    ? params.sizes.map(String)
    : ["1280x720", "720x1280", "1920x1080", "1080x1920"];

  const secondsStr = String(rawSeconds || params.defaultSeconds || allowedSeconds[0]).trim();
  const sizeStr = String(rawSize || params.defaultSize || allowedSizes[0]).trim();

  if (!allowedSeconds.includes(secondsStr)) {
    return {
      valid: false,
      code: "unsupported_video_duration",
      error: `模型 ${model.displayName}（${model.id}）不支持 ${secondsStr} 秒时长；仅支持：${allowedSeconds.join(" / ")} 秒（不会静默修改或换模型）。`,
      allowedSeconds,
      allowedSizes,
    };
  }
  if (!allowedSizes.includes(sizeStr)) {
    return {
      valid: false,
      code: "unsupported_video_size",
      error: `模型 ${model.displayName}（${model.id}）不支持分辨率 ${sizeStr}；仅支持：${allowedSizes.join(" / ")}。`,
      allowedSeconds,
      allowedSizes,
    };
  }
  return { valid: true, seconds: Number(secondsStr), secondsStr, size: sizeStr };
}

/**
 * POST /v1/videos — Creates an async video generation job with exact pre-reservation & idempotency.
 */
export async function handleManagedVideoCreate(request, env, {
  json,
  authenticateUser,
  loadCommercialConfig,
  parseAIHubMixAllowlist,
  randomCode,
}) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权，请重新激活 WUMIND 账户。" }, 401);

  let body;
  try { body = await request.json(); } catch { return json({ error: "请求 JSON 格式不正确。" }, 400); }

  const modelID = String(body.model || "").trim();
  const prompt = String(body.prompt || "").trim();
  if (!prompt || prompt.length > 4000) {
    return json({ error: "请输入有效的视频描述提示词（1~4000 字）。" }, 400);
  }

  const config = await loadCommercialConfig(env);
  const resolved = await resolveCatalogModelForExecution(env, config, modelID, "video", parseAIHubMixAllowlist);
  if (resolved.error || !resolved.model || !resolved.supply) {
    return json({
      error: resolved.error,
      code: resolved.code || "video_model_unavailable",
      modelID,
    }, resolved.status || 403);
  }

  const { model, supply } = resolved;
  const paramCheck = validateVideoParamsForModel(model, body.seconds ?? body.duration, body.size);
  if (!paramCheck.valid) {
    return json({
      error: paramCheck.error,
      code: paramCheck.code,
      modelID: model.id,
      allowedSeconds: paramCheck.allowedSeconds,
      allowedSizes: paramCheck.allowedSizes,
    }, 400);
  }

  const perSecondMicros = Math.max(100_000, yuanToMicros(model.unitPriceYuan || 0));
  const reserveMicros = perSecondMicros * paramCheck.seconds;
  const idempotencyKey = extractIdempotencyKey(request, body);
  const isExempt = isUserBillingExempt(env, user);

  // Check if same idempotencyKey already created a video job (works for both normal and exempt admins!)
  if (idempotencyKey) {
    const existingWork = await env.DB.prepare(
      "SELECT * FROM user_works WHERE user_id = ? AND idempotency_key = ? AND work_type = 'video'"
    ).bind(user.id, idempotencyKey).first();
    if (existingWork && existingWork.upstream_job_id) {
      const existingJob = await env.DB.prepare(
        "SELECT * FROM video_jobs WHERE id = ? AND user_id = ?"
      ).bind(existingWork.upstream_job_id, user.id).first();
      if (existingJob) {
        return json({
          id: existingJob.id,
          workID: existingWork.id,
          model: existingJob.model_id,
          status: existingJob.status,
          progress: existingJob.progress,
          seconds: String(existingJob.seconds),
          size: existingJob.size,
          idempotentReplay: true,
        });
      }
    }
    const existingRes = await env.DB.prepare(
      "SELECT * FROM credit_reservations WHERE user_id = ? AND idempotency_key = ?"
    ).bind(user.id, idempotencyKey).first();
    if (existingRes) {
      const existingJob = await env.DB.prepare(
        "SELECT * FROM video_jobs WHERE reservation_id = ? AND user_id = ?"
      ).bind(existingRes.id, user.id).first();
      if (existingJob) {
        return json({
          id: existingJob.id,
          workID: existingJob.work_id || null,
          model: existingJob.model_id,
          status: existingJob.status,
          progress: existingJob.progress,
          seconds: String(existingJob.seconds),
          size: existingJob.size,
          idempotentReplay: true,
        });
      }
    }
  }

  let reservationID = `EXEMPT-${randomCode(10)}`;
  if (isExempt) {
    const capCheck = await checkAdminExemptQuota(env, user, reserveMicros);
    if (!capCheck.allowed) {
      return json({ error: capCheck.error, code: capCheck.code }, capCheck.status);
    }
  } else {
    const reserve = await reserveCreditAtomic(env, {
      userID: user.id,
      idempotencyKey,
      kind: "video",
      modelID: model.id,
      reserveMicros,
      ttlSeconds: 1800, // Videos can render up to 30 min
      randomCode,
    });

    if (reserve.duplicateSettled && reserve.cachedResponse) {
      return json({ ...reserve.cachedResponse, idempotentReplay: true });
    }
    if (reserve.duplicateInFlight) {
      return json({ error: "相同视频生成任务正在处理中，请勿重复提交。", code: "duplicate_in_flight" }, 409);
    }
    if (reserve.insufficient) {
      return json({
        error: `可用余额不足（可用 ¥${microsToYuan(reserve.availableMicros)}，本次 ${paramCheck.seconds}s 视频需预留 ¥${microsToYuan(reserve.requiredMicros)}），请先充值。`,
        code: "insufficient_balance",
        availableYuan: microsToYuan(reserve.availableMicros),
        requiredReserveYuan: microsToYuan(reserve.requiredMicros),
      }, 402);
    }
    reservationID = reserve.reservationID;
  }

  const workID = `WRK-${randomCode(12)}`;
  const workParams = { seconds: paramCheck.seconds, size: paramCheck.size };
  const protocol = model.supportedParams?.protocol || "aihubmix_videos";
  let submitURL = "";

  try {
    let upstreamRes;
    if (protocol === "gemini_veo" && supply.style === "gemini") {
      submitURL = `${supply.chatURL}/${encodeURIComponent(model.id)}:predictLongRunning`;
      const aspectRatio = paramCheck.size === "720x1280" || paramCheck.size === "1080x1920" ? "9:16" : "16:9";
      const resolution = paramCheck.size.includes("1920") ? "1080p" : "720p";
      upstreamRes = await fetch(submitURL, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": supply.key },
        body: JSON.stringify({
          instances: [{ prompt }],
          parameters: { aspectRatio, durationSeconds: paramCheck.seconds, resolution },
        }),
      });
    } else if (protocol === "grok_videos" && supply.provider === "grok") {
      submitURL = supply.videosURL;
      const aspectRatio = paramCheck.size === "720x1280" ? "9:16" : "16:9";
      upstreamRes = await fetch(submitURL, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${supply.key}` },
        body: JSON.stringify({ model: model.id, prompt, duration: paramCheck.seconds, aspect_ratio: aspectRatio, resolution: "720p" }),
      });
    } else {
      // OpenAI / AIHubMix unified POST /v1/videos protocol
      submitURL = supply.videosURL || `${supply.baseOrigin}/v1/videos`;
      const wireBody = {
        model: model.id,
        prompt,
        seconds: paramCheck.secondsStr,
        size: paramCheck.size,
      };
      if (body.input_reference) {
        wireBody.input_reference = body.input_reference;
      }
      upstreamRes = await fetch(submitURL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${supply.key}`,
          ...(supply.extraHeaders || {}),
        },
        body: JSON.stringify(wireBody),
      });
    }

    const rawText = await upstreamRes.text();
    if (!upstreamRes.ok) {
      const { clean, code } = sanitizeErrorMessage(upstreamRes.status, rawText);
      if (!isExempt) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: `video_submit_http_${upstreamRes.status}` });
      const upstreamOutOfFunds = isUpstreamBalanceError(upstreamRes.status, rawText);
      const errMsg = upstreamOutOfFunds
        ? "上游 API 余额不足，请管理员前往上游控制台充值（非 App 钱包余额问题）。"
        : `上游视频接口拒绝提交（${clean}），本次未扣费。`;
      await upsertWorkFromGatewayTask(env, {
        id: workID,
        userID: user.id,
        workType: "video",
        title: prompt.slice(0, 48),
        prompt,
        modelID: model.id,
        params: workParams,
        status: "failed",
        progress: 0,
        errorMessage: errMsg,
      });
      return json({
        error: errMsg,
        code: upstreamOutOfFunds ? "upstream_balance_insufficient" : (code || `upstream_http_${upstreamRes.status}`),
        workID,
        modelID: model.id,
        endpoint: submitURL,
        httpStatus: upstreamRes.status,
      }, upstreamOutOfFunds ? 502 : (upstreamRes.status >= 400 && upstreamRes.status < 500 ? upstreamRes.status : 502));
    }

    let created;
    try { created = JSON.parse(rawText); } catch {
      if (!isExempt) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: "video_invalid_json" });
      return json({ error: "上游视频接口返回无法解析的响应，本次未扣费。", code: "invalid_upstream_response" }, 502);
    }

    const upstreamJobID = String(created.id || created.request_id || created.name || "").trim();
    if (!upstreamJobID) {
      if (!isExempt) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: "video_missing_job_id" });
      return json({ error: "上游视频接口未返回任务编号，本次未扣费。", code: "invalid_job_response" }, 502);
    }

    const localJobID = `VID-${randomCode(12)}`;
    const initialStatus = String(created.status || "queued").toLowerCase();
    const initialProgress = Number(created.progress || 0);

    await env.DB.prepare(
      `INSERT INTO video_jobs
       (id, user_id, upstream_job_id, upstream_route, upstream_base_url, model_id, reservation_id, seconds, size, status, progress, download_url, is_admin_exempt, estimated_cost_micros, work_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      localJobID,
      user.id,
      upstreamJobID,
      model.upstreamProvider,
      supply.baseOrigin,
      model.id,
      reservationID,
      paramCheck.seconds,
      paramCheck.size,
      initialStatus,
      initialProgress,
      created.url || null,
      isExempt ? 1 : 0,
      reserveMicros,
      workID
    ).run();

    await upsertWorkFromGatewayTask(env, {
      id: workID,
      userID: user.id,
      workType: "video",
      title: prompt.slice(0, 48),
      prompt,
      modelID: model.id,
      params: workParams,
      status: initialStatus === "completed" ? "completed" : "in_progress",
      progress: Math.max(5, initialProgress),
      upstreamJobID: localJobID,
      idempotencyKey,
      assetMime: "video/mp4",
    });

    return json({
      id: localJobID,
      workID,
      upstreamJobID,
      model: model.id,
      endpoint: submitURL,
      status: initialStatus,
      progress: initialProgress,
      seconds: paramCheck.secondsStr,
      size: paramCheck.size,
      reservedYuan: isExempt ? 0 : microsToYuan(reserveMicros),
      adminExempt: isExempt,
    });
  } catch (err) {
    if (!isExempt) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: "video_submit_exception" });
    return json({
      error: `提交视频任务失败（${String(err?.message || err).slice(0, 160)}），本次未扣费。`,
      code: "upstream_network_error",
      modelID: model.id,
      endpoint: submitURL,
    }, 502);
  }
}

/**
 * GET /v1/videos/:id — Polls real upstream video job progress; settles credit ONCE on completion or releases on failure.
 */
export async function handleManagedVideoStatus(request, env, jobID, { json, authenticateUser }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);

  const job = await env.DB.prepare(
    "SELECT * FROM video_jobs WHERE id = ? AND user_id = ?"
  ).bind(jobID, user.id).first();
  if (!job) return json({ error: "未找到该视频任务。" }, 404);

  if (job.status === "completed" || job.status === "failed") {
    return json({
      id: job.id,
      workID: job.work_id || null,
      model: job.model_id,
      status: job.status,
      progress: job.progress,
      seconds: String(job.seconds),
      size: job.size,
      error: job.error_message || null,
      contentPath: job.status === "completed" ? `/v1/videos/${encodeURIComponent(job.id)}/content` : null,
    });
  }

  const supply = buildUpstreamSupplyEndpoints(job.upstream_route, env);
  if (!supply) return json({ error: "上游视频通道密钥已不可用。" }, 503);

  const pollURL = supply.style === "gemini"
    ? `${supply.baseOrigin}/v1beta/${job.upstream_job_id.replace(/^\/+/, "")}`
    : `${supply.videoPollBaseURL || supply.videosURL || `${supply.baseOrigin}/v1/videos`}/${encodeURIComponent(job.upstream_job_id)}`;
  const headers = { Accept: "application/json", ...(supply.extraHeaders || {}) };
  if (supply.style === "gemini") headers["x-goog-api-key"] = supply.key;
  else headers.Authorization = `Bearer ${supply.key}`;

  const res = await fetch(pollURL, { method: "GET", headers });
  const rawText = await res.text();
  if (!res.ok) {
    const { clean } = sanitizeErrorMessage(res.status, rawText);
    return json({ error: `查询视频进度失败（${clean}）`, code: `poll_http_${res.status}` }, 502);
  }

  let data;
  try { data = JSON.parse(rawText); } catch {
    return json({ error: "上游视频状态响应无法解析。" }, 502);
  }

  let status = "in_progress";
  let progress = Number(data.progress || job.progress || 10);
  let errorMsg = null;
  let downloadURL = data.url || data.video?.url || job.download_url || null;

  if (supply.style === "gemini") {
    if (data.done) {
      if (data.error?.message) {
        status = "failed";
        errorMsg = data.error.message;
      } else {
        status = "completed";
        progress = 100;
        downloadURL = data.response?.generateVideoResponse?.generatedSamples?.[0]?.video?.uri || downloadURL;
      }
    }
  } else {
    const rawSt = String(data.status || "in_progress").toLowerCase();
    if (rawSt === "completed" || rawSt === "succeeded") {
      status = "completed";
      progress = 100;
    } else if (rawSt === "failed" || rawSt === "cancelled" || rawSt === "expired") {
      status = "failed";
      errorMsg = typeof data.error === "string"
        ? data.error
        : (data.error?.message || "上游视频渲染失败。");
    } else {
      status = rawSt === "queued" ? "queued" : "in_progress";
    }
  }

  const jobExempt = Number(job.is_admin_exempt || 0) === 1;
  let billingReceipt = null;
  if (status === "completed") {
    if (jobExempt) {
      billingReceipt = await recordAdminExemptUsage(env, {
        userID: user.id,
        kind: "video",
        provider: job.upstream_route,
        model: job.model_id,
        upstreamCostMicros: Number(job.estimated_cost_micros || 0),
        note: `视频生成 · ${job.seconds}s (${job.size})`,
      });
    } else {
      const resRow = await env.DB.prepare("SELECT reserved_micros FROM credit_reservations WHERE id = ?").bind(job.reservation_id).first();
      billingReceipt = await settleReservationAtomic(env, {
        reservationID: job.reservation_id,
        userID: user.id,
        actualMicros: Number(resRow?.reserved_micros || 0),
        kind: "video",
        provider: job.upstream_route,
        model: job.model_id,
        note: `视频生成 · ${job.seconds}s (${job.size})`,
      });
    }
  } else if (status === "failed" && !jobExempt) {
    await releaseReservationAtomic(env, {
      reservationID: job.reservation_id,
      userID: user.id,
      reason: errorMsg || "video_failed",
    });
  }

  const clampedProgress = Math.max(0, Math.min(100, Math.round(progress)));
  await env.DB.prepare(
    "UPDATE video_jobs SET status = ?, progress = ?, download_url = ?, error_message = ?, updated_at = datetime('now') WHERE id = ?"
  ).bind(status, clampedProgress, downloadURL, errorMsg, job.id).run();

  if (job.work_id) {
    await env.DB.prepare(
      "UPDATE user_works SET status = ?, progress = ?, error_message = ?, updated_at = datetime('now') WHERE id = ? AND user_id = ?"
    ).bind(status, clampedProgress, errorMsg, job.work_id, user.id).run();
  }

  return json({
    id: job.id,
    workID: job.work_id || null,
    model: job.model_id,
    status,
    progress: clampedProgress,
    seconds: String(job.seconds),
    size: job.size,
    error: errorMsg,
    contentPath: status === "completed" ? `/v1/videos/${encodeURIComponent(job.id)}/content` : null,
    billing: billingReceipt,
  });
}

/**
 * GET /v1/videos/:id/content — Streams validated MP4 bytes back to the authenticated owner.
 */
export async function handleManagedVideoContent(request, env, jobID, { json, authenticateUser }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);

  const job = await env.DB.prepare(
    "SELECT * FROM video_jobs WHERE id = ? AND user_id = ?"
  ).bind(jobID, user.id).first();
  if (!job) return json({ error: "未找到该视频任务。" }, 404);
  if (job.status !== "completed") {
    return json({ error: `视频尚未生成完成（当前状态：${job.status}）。`, code: "video_not_ready" }, 202);
  }

  const supply = buildUpstreamSupplyEndpoints(job.upstream_route, env);
  if (!supply) return json({ error: "上游视频通道密钥已不可用。" }, 503);

  const contentURL = job.download_url && /^https:\/\//i.test(job.download_url)
    ? job.download_url
    : `${supply.videosURL || `${supply.baseOrigin}/v1/videos`}/${encodeURIComponent(job.upstream_job_id)}/content`;

  const headers = { ...(supply.extraHeaders || {}) };
  // Only attach upstream API key when downloading from the upstream's own host (never leak key to third-party CDN!)
  const parsedContent = new URL(contentURL);
  const parsedSupply = new URL(supply.baseOrigin);
  if (parsedContent.host.toLowerCase() === parsedSupply.host.toLowerCase()) {
    if (supply.style === "gemini") headers["x-goog-api-key"] = supply.key;
    else headers.Authorization = `Bearer ${supply.key}`;
  }

  const res = await fetch(contentURL, { method: "GET", headers });
  if (res.status === 202) {
    return json({ error: "视频成片正在封装中，请稍后重试下载。", code: "video_still_generating" }, 202);
  }
  if (!res.ok) {
    const raw = await res.text();
    const { clean } = sanitizeErrorMessage(res.status, raw);
    return json({ error: `下载 MP4 成片失败（${clean}）`, code: "video_download_failed" }, 502);
  }

  const bytes = new Uint8Array(await res.arrayBuffer());
  if (!isValidMP4Header(bytes)) {
    return json({ error: "上游返回的数据不是合法 MP4 视频文件。", code: "invalid_mp4" }, 502);
  }

  return new Response(bytes, {
    status: 200,
    headers: {
      "Content-Type": "video/mp4",
      "Content-Disposition": `attachment; filename="wumind_${job.id}.mp4"`,
      "Cache-Control": "private, max-age=3600",
    },
  });
}
