/**
 * WUMIND Managed Media Gateway Routes (Image Generation, Reference-Image Editing & Video Generation):
 * - Enforces dynamic catalog capability, permission, and per-model parameter validation (zero silent fallback).
 * - Uses atomic pre-request credit reservation -> post-success actual settlement -> failure full release.
 * - Uses idempotency_key deduplication to prevent duplicate generation & double-charging on retries.
 */

import { redactUpstreamDiagnostic } from "./upstream-diagnostics.js";

import {
  extractIdempotencyKey,
  reserveCreditAtomic,
  settleReservationAtomic,
  releaseReservationAtomic,
} from "./billing-safety.js";
import {
  resolveCatalogModelForExecution,
  buildUpstreamSupplyEndpoints,
  buildAIHubMixWan26VideoRequest,
  getPublicCallableModels,
} from "./model-catalog.js";
import {
  isUserBillingExempt,
  checkAdminExemptQuota,
  recordAdminExemptUsage,
  isUpstreamBalanceError,
  upsertWorkFromGatewayTask,
  isWorksObjectStorageConfigured,
  storeWorkBinaryInR2,
} from "./admin-ops-works.js";

import {
  encodeUint8ArrayBase64,
  extractAndValidateGeneratedImages,
} from "./image-payload.js";

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

function sanitizeErrorMessage(status, rawText, supply) {
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
  const clean = redactUpstreamDiagnostic(msg, supply.key, supply.extraHeaders).trim().slice(0, 320);
  return { clean: clean || `上游接口返回 HTTP ${status}`, code: redactUpstreamDiagnostic(code, supply.key, supply.extraHeaders).slice(0, 120) };
}

function isValidMP4Header(bytes) {
  return bytes instanceof Uint8Array &&
    bytes.length >= 12 &&
    bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70; // "ftyp"
}

const ALLOWED_ASPECT_RATIOS = new Set([
  "1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9",
]);

function normalizeImageAspectRatio(rawRatio, size) {
  const candidate = String(rawRatio || "").trim();
  if (ALLOWED_ASPECT_RATIOS.has(candidate)) return candidate;
  const s = String(size || "").trim().toLowerCase();
  if (s === "1536x1024" || s === "1792x1024") return "3:2";
  if (s === "1024x1536" || s === "1024x1792") return "2:3";
  return "1:1";
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
  const requestID = `REQ-${randomCode(10)}`;
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权，请重新激活 WUMIND 账户。", code: "unauthorized", requestID, route: "managed_gateway" }, 401);

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "请求 JSON 格式不正确。", code: "invalid_json", requestID, route: "managed_gateway" }, 400);
  }

  const modelID = String(body.model || "").trim();
  const prompt = String(body.prompt || "").trim();
  if (!prompt || prompt.length > 8000) {
    return json({ error: "请输入有效的生图提示词（1~8000 字）。", code: "invalid_prompt", requestID, route: "managed_gateway" }, 400);
  }

  const refObj = body.referenceImage && typeof body.referenceImage === "object" ? body.referenceImage : null;
  const hasReferenceImage = Boolean(forceEditMode || (refObj && typeof refObj.base64Data === "string" && refObj.base64Data.trim().length > 0));
  if (forceEditMode && (!refObj || !refObj.base64Data)) {
    return json({ error: "图生图/参考图编辑接口缺少 referenceImage.base64Data。", code: "missing_reference_image", requestID, route: "managed_gateway" }, 400);
  }

  const n = Math.min(4, Math.max(1, parseInt(body.n || 1, 10) || 1));
  const size = String(body.size || "1024x1024").trim();
  const aspectRatio = normalizeImageAspectRatio(body.aspectRatio || body.aspect_ratio, size);
  const quality = ["low", "medium", "high"].includes(String(body.quality || "").toLowerCase())
    ? String(body.quality).toLowerCase()
    : "medium";
  const outputFormat = String(body.outputFormat || body.output_format || "jpeg").toLowerCase() === "png" ? "png" : "jpeg";

  const config = await loadCommercialConfig(env);
  const requiredCap = hasReferenceImage ? "image_edit" : "text_to_image";
  const resolved = await resolveCatalogModelForExecution(env, config, modelID, requiredCap, parseAIHubMixAllowlist);
  if (resolved.error || !resolved.model || !resolved.supply) {
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
      requestID,
      route: "managed_gateway",
      modelID,
      billingResult: "not_charged",
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
          requestID,
          route: "managed_gateway",
          workID: existingWork.id,
          model: existingWork.model_id,
          mode: hasReferenceImage ? "image_edit" : "text_to_image",
          data: [{ b64_json: existingWork.asset_base64, mime_type: existingWork.asset_mime || "image/png" }],
          billing: { exempt: true, costYuan: 0, balanceYuan: 0 },
          billingResult: "idempotent_replay_exempt",
          idempotentReplay: true,
        });
      }
    }
    const capCheck = await checkAdminExemptQuota(env, user, reserveMicros);
    if (!capCheck.allowed) {
      return json({ error: capCheck.error, code: capCheck.code, requestID, route: "managed_gateway", billingResult: "not_charged" }, capCheck.status);
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

    if (reserve.duplicateSettled) {
      const u = await env.DB.prepare("SELECT balance_micros, reserved_micros FROM users WHERE id = ?").bind(user.id).first();
      const settledBilling = {
        alreadySettled: true,
        reservationID: reserve.reservation?.id || null,
        reservedYuan: microsToYuan(reserve.reservation?.reserved_micros || 0),
        costYuan: microsToYuan(reserve.reservation?.actual_micros || 0),
        balanceYuan: microsToYuan(u?.balance_micros || 0),
        availableYuan: microsToYuan(Math.max(0, Number(u?.balance_micros || 0) - Number(u?.reserved_micros || 0))),
      };
      if (reserve.cachedResponse && Array.isArray(reserve.cachedResponse.data) && reserve.cachedResponse.data.length > 0) {
        return json({
          ...reserve.cachedResponse,
          requestID,
          billing: reserve.cachedResponse.billing || settledBilling,
          billingResult: "idempotent_replay_no_extra_charge",
          idempotentReplay: true,
        });
      }
      if (idempotencyKey) {
        const existingWork = await env.DB.prepare(
          "SELECT * FROM user_works WHERE user_id = ? AND idempotency_key = ?"
        ).bind(user.id, idempotencyKey).first();
        if (existingWork) {
          let replayB64 = existingWork.asset_base64 || null;
          if (!replayB64 && existingWork.asset_object_key && isWorksObjectStorageConfigured(env)) {
            const obj = await env.WORKS_BUCKET.get(existingWork.asset_object_key);
            if (obj) {
              replayB64 = encodeUint8ArrayBase64(new Uint8Array(await obj.arrayBuffer()));
            }
          }
          if (replayB64) {
            return json({
              ...(reserve.cachedResponse || {}),
              ok: true,
              requestID,
              route: reserve.cachedResponse?.route || "managed_gateway",
              workID: existingWork.id,
              model: existingWork.model_id || model.id,
              mode: hasReferenceImage ? "image_edit" : "text_to_image",
              data: [{ b64_json: replayB64, mime_type: existingWork.asset_mime || "image/png" }],
              billing: settledBilling,
              billingResult: "idempotent_replay_no_extra_charge",
              idempotentReplay: true,
            });
          }
        }
      }
      return json({
        ...(reserve.cachedResponse || {}),
        ok: true,
        requestID,
        model: model.id,
        billing: settledBilling,
        billingResult: "idempotent_replay_no_extra_charge",
        idempotentReplay: true,
      });
    }
    if (reserve.duplicateInFlight) {
      return json({
        error: "相同生图请求正在处理中，请勿重复提交。",
        code: "duplicate_in_flight",
        requestID,
        route: "managed_gateway",
        billingResult: "in_flight_deduplicated",
      }, 409);
    }
    if (reserve.insufficient) {
      return json({
        error: `可用余额不足（可用 ¥${microsToYuan(reserve.availableMicros)}，本次需预留 ¥${microsToYuan(reserve.requiredMicros)}），请先充值。`,
        code: "insufficient_balance",
        requestID,
        route: "managed_gateway",
        billingResult: "insufficient_balance",
        availableYuan: microsToYuan(reserve.availableMicros),
        requiredReserveYuan: microsToYuan(reserve.requiredMicros),
      }, 402);
    }
    reservationID = reserve.reservationID;
  }

  const workID = `WRK-${randomCode(12)}`;
  const workParams = { size, aspectRatio, quality, outputFormat, n, hasReferenceImage };
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
  let routeLabel = "managed_gateway:openai_images";

  try {
    let upstreamRes;
    let rawText = "";
    const modelProtocol = model.supportedParams?.protocol || "";
    const lowerModelID = model.id.toLowerCase();
    const isGeminiImageModel = lowerModelID.includes("gemini") && lowerModelID.includes("image");
    const isGeminiOfficial = (modelProtocol === "gemini_generate_content" || isGeminiImageModel) && supply.style === "gemini";
    const isAIHubMixGemini = (modelProtocol === "aihubmix_gemini_image" || isGeminiImageModel) && supply.provider === "aihubmix";

    // Pre-validate reference image bytes once when present
    let refMime = "image/png";
    let refCleanBase64 = "";
    let refBytes = null;
    if (hasReferenceImage && refObj?.base64Data) {
      refMime = typeof refObj.mimeType === "string" && refObj.mimeType.startsWith("image/") ? refObj.mimeType : "image/png";
      refCleanBase64 = String(refObj.base64Data).replace(/^data:[^;]+;base64,/i, "").replace(/\s+/g, "");
      refBytes = decodeBase64Bytes(refCleanBase64);
      if (refBytes.length === 0 || refBytes.length > 10 * 1024 * 1024) {
        if (reservationID) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: "invalid_reference_image_size" });
        await upsertWorkFromGatewayTask(env, { id: workID, userID: user.id, workType: "image", title: prompt.slice(0, 48), prompt, modelID: model.id, params: workParams, status: "failed", progress: 0, errorMessage: "参考图文件为空或超过 10MB 限制。" });
        return json({ error: "参考图文件为空或超过 10MB 限制。", code: "invalid_reference_image", requestID, route: "managed_gateway", billingResult: "released_no_charge", workID }, 400);
      }
    }

    const callAIHubMixUnified = async () => {
      routeLabel = "managed_gateway:aihubmix_unified";
      targetURL = supply.unifiedImageGenURL || `${supply.baseOrigin}/ai/v1/images/generations`;
      const unifiedPayload = {
        model: model.id,
        prompt,
        n,
        aspect_ratio: aspectRatio,
        output_format: outputFormat,
        response_format: "b64_json",
      };
      if (hasReferenceImage && refCleanBase64) {
        unifiedPayload.image = `data:${refMime};base64,${refCleanBase64}`;
      }
      const res = await fetch(targetURL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${supply.key}`,
          ...(supply.extraHeaders || {}),
        },
        body: JSON.stringify(unifiedPayload),
      });
      return { res, text: await res.text() };
    };

    if (isGeminiOfficial || isAIHubMixGemini) {
      routeLabel = isAIHubMixGemini ? "managed_gateway:aihubmix_gemini_image" : "managed_gateway:gemini_official";
      const geminiBase = isAIHubMixGemini
        ? (supply.geminiNativeBaseURL || `${supply.baseOrigin}/gemini/v1beta/models`)
        : supply.chatURL;
      targetURL = `${geminiBase}/${encodeURIComponent(model.id)}:generateContent`;
      const parts = [];
      if (hasReferenceImage && refCleanBase64) {
        parts.push({ inline_data: { mime_type: refMime, data: refCleanBase64 } });
      }
      parts.push({ text: prompt });
      upstreamRes = await fetch(targetURL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": supply.key,
          ...(supply.extraHeaders || {}),
        },
        body: JSON.stringify({
          contents: [{ role: "user", parts }],
          generationConfig: {
            responseModalities: ["TEXT", "IMAGE"],
            imageConfig: {
              aspectRatio,
              imageSize: quality === "high" ? "2K" : "1K",
            },
          },
        }),
      });
      rawText = await upstreamRes.text();
      if (!upstreamRes.ok && isAIHubMixGemini && (upstreamRes.status === 404 || rawText.includes("protocol_not_supported") || rawText.includes("/ai/v1/images"))) {
        const fallback = await callAIHubMixUnified();
        upstreamRes = fallback.res;
        rawText = fallback.text;
      }
    } else if (hasReferenceImage) {
      // Real multipart/form-data POST /v1/images/edits (OpenAI & AIHubMix GPT-Image spec)
      routeLabel = "managed_gateway:openai_images";
      targetURL = supply.imageEditURL || `${supply.baseOrigin}/v1/images/edits`;
      const ext = refMime.includes("jpeg") || refMime.includes("jpg") ? "jpg" : refMime.includes("webp") ? "webp" : "png";

      const form = new FormData();
      form.append("model", model.id);
      form.append("prompt", prompt);
      form.append("n", String(n));
      form.append("size", size);
      form.append("quality", quality);
      form.append("output_format", outputFormat);
      form.append("image", new Blob([refBytes], { type: refMime }), String(refObj.filename || `reference.${ext}`).slice(0, 64));

      upstreamRes = await fetch(targetURL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${supply.key}`,
          ...(supply.extraHeaders || {}),
        },
        body: form,
      });
      rawText = await upstreamRes.text();
      if (!upstreamRes.ok && supply.provider === "aihubmix" && (rawText.includes("protocol_not_supported") || rawText.includes("/ai/v1/images"))) {
        const fallback = await callAIHubMixUnified();
        upstreamRes = fallback.res;
        rawText = fallback.text;
      }
    } else {
      routeLabel = "managed_gateway:openai_images";
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
      rawText = await upstreamRes.text();
      if (!upstreamRes.ok && supply.provider === "aihubmix" && (rawText.includes("protocol_not_supported") || rawText.includes("/ai/v1/images"))) {
        const fallback = await callAIHubMixUnified();
        upstreamRes = fallback.res;
        rawText = fallback.text;
      }
    }

    const upstreamGenerateMs = Math.max(1, Date.now() - upstreamStartMs);
    if (!upstreamRes.ok) {
      const { clean, code } = sanitizeErrorMessage(upstreamRes.status, rawText, supply);
      if (reservationID) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: `upstream_${upstreamRes.status}` });
      const upstreamOutOfFunds = isUpstreamBalanceError(upstreamRes.status, rawText);
      const isAsyncDisabled = rawText.toLowerCase().includes("async_not_enabled");
      const isUpstreamAuth = !upstreamOutOfFunds && !isAsyncDisabled && (upstreamRes.status === 401 || upstreamRes.status === 403);
      const errCode = upstreamOutOfFunds
        ? "upstream_balance_insufficient"
        : isAsyncDisabled
          ? "upstream_async_not_enabled"
          : isUpstreamAuth
            ? "upstream_auth_failed"
            : (code || `upstream_http_${upstreamRes.status}`);
      const errMsg = upstreamOutOfFunds
        ? "上游 API 余额不足，请管理员前往上游控制台充值（非 App 钱包余额问题）。"
        : isAsyncDisabled
          ? "上游 AIHubMix 尚未开启异步任务开关（async_not_enabled），请联系管理员检查上游通道设置，本次未扣费。"
          : isUpstreamAuth
            ? `上游 API 鉴权失败（HTTP ${upstreamRes.status}：${clean}），请联系管理员核对服务端密钥，本次未扣费。`
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
      // Never return 401 for upstream auth failure so client does not confuse it with WuMind session expiry
      const clientStatus = (upstreamOutOfFunds || isUpstreamAuth)
        ? 502
        : (upstreamRes.status >= 400 && upstreamRes.status < 500 ? upstreamRes.status : 502);
      return json({
        error: errMsg,
        code: errCode,
        requestID,
        route: routeLabel,
        workID,
        modelID: model.id,
        endpoint: targetURL,
        httpStatus: upstreamRes.status,
        billingResult: "released_no_charge",
      }, clientStatus);
    }

    let parsed;
    try { parsed = JSON.parse(rawText); } catch {
      if (reservationID) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: "invalid_upstream_json" });
      await upsertWorkFromGatewayTask(env, { id: workID, userID: user.id, workType: "image", title: prompt.slice(0, 48), prompt, modelID: model.id, params: workParams, status: "failed", progress: 0, errorMessage: "上游生图接口返回无法解析的数据。" });
      return json({ error: "上游生图接口返回无法解析的数据，本次未扣费。", code: "invalid_upstream_response", requestID, route: routeLabel, billingResult: "released_no_charge", workID }, 502);
    }

    const { images, rejectedReasons } = await extractAndValidateGeneratedImages(parsed, { supply });

    if (images.length === 0) {
      const hasCorruptPayload = rejectedReasons.some((r) => r !== "blocked_off_origin_content_url");
      const errCode = hasCorruptPayload ? "invalid_image_payload" : "no_image";
      const errMsg = hasCorruptPayload
        ? `上游返回的图片无法解码或格式损坏（${rejectedReasons[0]}），本次未扣费。`
        : "上游未返回有效图片数据，本次未扣费。";
      if (reservationID) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: errCode });
      await upsertWorkFromGatewayTask(env, { id: workID, userID: user.id, workType: "image", title: prompt.slice(0, 48), prompt, modelID: model.id, params: workParams, status: "failed", progress: 0, errorMessage: errMsg });
      return json({ error: errMsg, code: errCode, requestID, route: routeLabel, billingResult: "released_no_charge", workID }, 502);
    }

    const actualMicros = unitMicros * images.length;
    const timing = { gatewaySubmitMs, upstreamGenerateMs };
    const responseData = {
      ok: true,
      requestID,
      route: routeLabel,
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
      billingResult: isExempt ? "admin_exempt_recorded" : "settled",
    });
  } catch (err) {
    if (reservationID) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: "upstream_exception" });
    const msg = `生图请求异常（${redactUpstreamDiagnostic(err?.message || err, supply.key, supply.extraHeaders).slice(0, 160)}），本次未扣费。`;
    await upsertWorkFromGatewayTask(env, { id: workID, userID: user.id, workType: "image", title: prompt.slice(0, 48), prompt, modelID: model.id, params: workParams, status: "failed", progress: 0, errorMessage: msg });
    return json({
      error: msg,
      code: "upstream_network_error",
      requestID,
      route: routeLabel,
      workID,
      modelID: model.id,
      endpoint: targetURL,
      billingResult: "released_no_charge",
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
      return json({
        error: capCheck.error,
        code: capCheck.code,
        spentTodayYuan: capCheck.spentTodayYuan,
        inflightYuan: capCheck.inflightYuan,
        inflightCount: capCheck.inflightCount,
        dailyCapYuan: capCheck.dailyCapYuan,
      }, capCheck.status);
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
  const aspectRatio = paramCheck.size === "720x1280" || paramCheck.size === "1080x1920" ? "9:16" : "16:9";
  const resolution = paramCheck.size.includes("1920") ? "1080p" : "720p";
  let submitURL = "";
  let storedVideoBase = supply.baseOrigin;

  try {
    let upstreamRes;
    let rawText = "";
    if (protocol === "gemini_interactions" && supply.style === "gemini") {
      submitURL = `${supply.baseOrigin}/v1beta/interactions`;
      storedVideoBase = submitURL;
      upstreamRes = await fetch(submitURL, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": supply.key },
        body: JSON.stringify({
          model: model.id,
          input: prompt,
          response_format: {
            type: "video",
            delivery: "uri",
            resolution,
            aspect_ratio: aspectRatio,
            duration: `${paramCheck.seconds}s`,
          },
          background: true,
          store: true,
          stream: false,
        }),
      });
      rawText = await upstreamRes.text();
    } else if (protocol === "gemini_veo" && supply.style === "gemini") {
      submitURL = `${supply.chatURL}/${encodeURIComponent(model.id)}:predictLongRunning`;
      upstreamRes = await fetch(submitURL, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": supply.key },
        body: JSON.stringify({
          instances: [{ prompt }],
          parameters: { aspectRatio, durationSeconds: paramCheck.seconds, resolution },
        }),
      });
      rawText = await upstreamRes.text();
    } else if (protocol === "grok_videos" && supply.provider === "grok") {
      submitURL = supply.videosURL;
      upstreamRes = await fetch(submitURL, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${supply.key}` },
        body: JSON.stringify({ model: model.id, prompt, duration: paramCheck.seconds, aspect_ratio: aspectRatio, resolution }),
      });
      rawText = await upstreamRes.text();
    } else {
      // OpenAI / AIHubMix unified POST /v1/videos (with Kling/Seedance schemas)
      submitURL = supply.videosURL || `${supply.baseOrigin}/v1/videos`;
      storedVideoBase = submitURL;
      let wireBody;
      if (protocol === "aihubmix_kling") {
        wireBody = {
          model: model.id,
          prompt,
          duration: paramCheck.secondsStr,
          aspect_ratio: aspectRatio,
          mode: resolution === "1080p" ? "pro" : "std",
          sound: "on",
        };
      } else if (protocol === "aihubmix_seedance") {
        submitURL = storedVideoBase = `${supply.baseOrigin}/ai/v1/videos`;
        wireBody = { model: model.id, prompt, duration: paramCheck.seconds, aspect_ratio: aspectRatio, resolution };
      } else {
        wireBody = {
          model: model.id,
          prompt,
          seconds: paramCheck.secondsStr,
          size: paramCheck.size,
        };
        if (body.input_reference) {
          wireBody.input_reference = body.input_reference;
        }
      }

      const wanRequest = buildAIHubMixWan26VideoRequest(supply, model.id, prompt, paramCheck.seconds, paramCheck.size);
      if (wanRequest) {
        submitURL = storedVideoBase = wanRequest.url;
        wireBody = wanRequest.payload;
      }
      const headers = {
        "Content-Type": "application/json",
        Authorization: `Bearer ${supply.key}`,
        ...(supply.extraHeaders || {}),
      };
      upstreamRes = await fetch(submitURL, {
        method: "POST",
        headers,
        body: JSON.stringify(wireBody),
      });
      rawText = await upstreamRes.text();


    }

    if (!upstreamRes.ok) {
      const { clean, code } = sanitizeErrorMessage(upstreamRes.status, rawText, supply);
      if (!isExempt) await releaseReservationAtomic(env, { reservationID, userID: user.id, reason: `video_submit_http_${upstreamRes.status}` });
      const upstreamOutOfFunds = isUpstreamBalanceError(upstreamRes.status, rawText);
      const asyncDisabled = supply.provider === "aihubmix" && upstreamRes.status === 403
        && /async_not_enabled|does not support asynchronous calls/i.test(rawText);
      const errMsg = upstreamOutOfFunds
        ? "上游 API 余额不足，请管理员前往上游控制台充值（非 App 钱包余额问题）。"
        : asyncDisabled
          ? "本内置通道所用的 AIHubMix 账号尚未开启异步任务，请管理员检查上游设置。本次未扣费。"
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
        code: upstreamOutOfFunds ? "upstream_balance_insufficient" : (asyncDisabled ? "upstream_async_not_enabled" : (code || `upstream_http_${upstreamRes.status}`)),
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
    const createdOutputURL = created.url || created.output?.find?.((o) => o?.url)?.url || null;

    await env.DB.prepare(
      `INSERT INTO video_jobs
       (id, user_id, upstream_job_id, upstream_route, upstream_base_url, model_id, reservation_id, seconds, size, status, progress, download_url, is_admin_exempt, estimated_cost_micros, work_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      localJobID,
      user.id,
      upstreamJobID,
      model.upstreamProvider,
      storedVideoBase,
      model.id,
      reservationID,
      paramCheck.seconds,
      paramCheck.size,
      initialStatus,
      initialProgress,
      createdOutputURL,
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
      error: `提交视频任务失败（${redactUpstreamDiagnostic(err?.message || err, supply.key, supply.extraHeaders).slice(0, 160)}），本次未扣费。`,
      code: "upstream_network_error",
      modelID: model.id,
      endpoint: submitURL,
    }, 502);
  }
}

function extractGeminiInteractionVideoPart(data) {
  const steps = Array.isArray(data?.steps) ? data.steps : [];
  for (const step of steps) {
    const content = Array.isArray(step?.content) ? step.content : [];
    for (const part of content) {
      if (part?.type === "video" || String(part?.mime_type || "").startsWith("video/")) {
        if (part.uri || part.data) return part;
      }
    }
  }
  const outputs = Array.isArray(data?.outputs) ? data.outputs : [];
  for (const part of outputs) {
    if (part?.type === "video" || String(part?.mime_type || "").startsWith("video/")) {
      if (part.uri || part.data) return part;
    }
  }
  return null;
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

  const isGeminiInteractions = supply.style === "gemini" && (
    String(job.upstream_base_url || "").includes("/v1beta/interactions") ||
    String(job.model_id || "").toLowerCase().startsWith("gemini-omni-")
  );
  const pollBase = String(job.upstream_base_url || "").includes("/videos")
    ? String(job.upstream_base_url).replace(/\/+$/, "")
    : (supply.videoPollBaseURL || supply.videosURL || `${supply.baseOrigin}/v1/videos`);

  const pollURL = isGeminiInteractions
    ? `${supply.baseOrigin}/v1beta/interactions/${encodeURIComponent(job.upstream_job_id)}`
    : supply.style === "gemini"
      ? `${supply.baseOrigin}/v1beta/${job.upstream_job_id.replace(/^\/+/, "")}`
      : `${pollBase}/${encodeURIComponent(job.upstream_job_id)}`;
  const headers = { Accept: "application/json", ...(supply.extraHeaders || {}) };
  if (supply.style === "gemini") headers["x-goog-api-key"] = supply.key;
  else headers.Authorization = `Bearer ${supply.key}`;

  const res = await fetch(pollURL, { method: "GET", headers });
  const rawText = await res.text();
  if (!res.ok) {
    const { clean } = sanitizeErrorMessage(res.status, rawText, supply);
    return json({ error: `查询视频进度失败（${clean}）`, code: `poll_http_${res.status}` }, 502);
  }

  let data;
  try { data = JSON.parse(rawText); } catch {
    return json({ error: "上游视频状态响应无法解析。" }, 502);
  }

  let status = "in_progress";
  let progress = Number(data.progress || job.progress || 10);
  let errorMsg = null;
  let downloadURL = data.url || data.video?.url || data.output?.find?.((o) => o?.url)?.url || job.download_url || null;

  if (isGeminiInteractions) {
    const rawSt = String(data.status || "in_progress").toLowerCase();
    const part = extractGeminiInteractionVideoPart(data);
    if (rawSt === "failed" || rawSt === "cancelled") {
      status = "failed";
      errorMsg = data.error?.message || "Gemini Omni 视频渲染失败。";
    } else if (rawSt === "completed" || part) {
      status = "completed";
      progress = 100;
      if (part?.uri) downloadURL = part.uri;
    } else {
      status = rawSt === "queued" ? "queued" : "in_progress";
    }
  } else if (supply.style === "gemini") {
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
    } else if (rawSt === "failed" || rawSt === "cancelled" || rawSt === "canceled" || rawSt === "expired") {
      status = "failed";
      errorMsg = typeof data.error === "string"
        ? data.error
        : (data.error?.message || "上游视频渲染失败。");
    } else {
      status = rawSt === "queued" ? "queued" : "in_progress";
    }
  }

  if (errorMsg) errorMsg = redactUpstreamDiagnostic(errorMsg, supply.key, supply.extraHeaders).slice(0, 320);
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

  // Serve directly from private R2 when already archived for cross-device fast replay
  if (job.work_id && isWorksObjectStorageConfigured(env)) {
    const workRow = await env.DB.prepare(
      "SELECT asset_object_key, asset_size_bytes, asset_sha256 FROM user_works WHERE id = ? AND user_id = ?"
    ).bind(job.work_id, user.id).first();
    if (workRow?.asset_object_key) {
      const cachedObj = await env.WORKS_BUCKET.get(workRow.asset_object_key);
      if (cachedObj) {
        const body = cachedObj.body ?? (await cachedObj.arrayBuffer());
        return new Response(body, {
          status: 200,
          headers: {
            "Content-Type": "video/mp4",
            "Content-Disposition": `attachment; filename="wumind_${job.id}.mp4"`,
            "Cache-Control": "private, max-age=3600",
            ...(workRow.asset_sha256 ? { "X-Asset-SHA256": workRow.asset_sha256 } : {}),
          },
        });
      }
    }
  }

  async function archiveVideoBytesIfPossible(bytes) {
    if (!job.work_id) return;
    if (isWorksObjectStorageConfigured(env)) {
      try {
        const stored = await storeWorkBinaryInR2(env, {
          userID: user.id,
          workID: job.work_id,
          bytes,
          mimeType: "video/mp4",
          kind: "asset",
        });
        await env.DB.prepare(
          `UPDATE user_works
           SET asset_object_key = ?, asset_mime = 'video/mp4', asset_size_bytes = ?, asset_sha256 = ?,
               asset_base64 = NULL, asset_sync_state = 'synced', updated_at = datetime('now')
           WHERE id = ? AND user_id = ?`
        ).bind(stored.objectKey, stored.sizeBytes, stored.sha256, job.work_id, user.id).run();
      } catch {}
    } else {
      await env.DB.prepare(
        "UPDATE user_works SET asset_mime = 'video/mp4', asset_size_bytes = ?, asset_sync_state = 'storage_unconfigured', updated_at = datetime('now') WHERE id = ? AND user_id = ?"
      ).bind(bytes.byteLength, job.work_id, user.id).run();
    }
  }

  const supply = buildUpstreamSupplyEndpoints(job.upstream_route, env);
  if (!supply) return json({ error: "上游视频通道密钥已不可用。" }, 503);

  const isGeminiInteractions = supply.style === "gemini" && (
    String(job.upstream_base_url || "").includes("/v1beta/interactions") ||
    String(job.model_id || "").toLowerCase().startsWith("gemini-omni-")
  );

  // Gemini Interactions GET returns inline base64 MP4 when no download_url was cached
  if (isGeminiInteractions && (!job.download_url || !/^https:\/\//i.test(job.download_url))) {
    const getURL = `${supply.baseOrigin}/v1beta/interactions/${encodeURIComponent(job.upstream_job_id)}`;
    const res = await fetch(getURL, { method: "GET", headers: { Accept: "application/json", "x-goog-api-key": supply.key } });
    if (!res.ok) {
      const raw = await res.text();
      const { clean } = sanitizeErrorMessage(res.status, raw, supply);
      return json({ error: `读取 Gemini Omni 视频成片失败（${clean}）`, code: "video_download_failed" }, 502);
    }
    const parsed = await res.json();
    const part = extractGeminiInteractionVideoPart(parsed);
    if (part?.data) {
      const bytes = decodeBase64Bytes(part.data);
      if (!isValidMP4Header(bytes)) {
        return json({ error: "上游返回的数据不是合法 MP4 视频文件。", code: "invalid_mp4" }, 502);
      }
      await archiveVideoBytesIfPossible(bytes);
      return new Response(bytes, {
        status: 200,
        headers: {
          "Content-Type": "video/mp4",
          "Content-Disposition": `attachment; filename="wumind_${job.id}.mp4"`,
          "Cache-Control": "private, max-age=3600",
        },
      });
    }
    if (part?.uri && /^https:\/\//i.test(part.uri)) {
      job.download_url = part.uri;
    } else {
      return json({ error: "Gemini Omni 尚未返回可下载视频内容。", code: "video_not_ready" }, 202);
    }
  }

  const videoBase = String(job.upstream_base_url || "").includes("/videos")
    ? String(job.upstream_base_url).replace(/\/+$/, "")
    : (supply.videosURL || `${supply.baseOrigin}/v1/videos`);
  const contentURL = job.download_url && /^https:\/\//i.test(job.download_url)
    ? job.download_url
    : `${videoBase}/${encodeURIComponent(job.upstream_job_id)}/content`;

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
    const { clean } = sanitizeErrorMessage(res.status, raw, supply);
    return json({ error: `下载 MP4 成片失败（${clean}）`, code: "video_download_failed" }, 502);
  }

  const bytes = new Uint8Array(await res.arrayBuffer());
  if (!isValidMP4Header(bytes)) {
    return json({ error: "上游返回的数据不是合法 MP4 视频文件。", code: "invalid_mp4" }, 502);
  }

  await archiveVideoBytesIfPossible(bytes);

  return new Response(bytes, {
    status: 200,
    headers: {
      "Content-Type": "video/mp4",
      "Content-Disposition": `attachment; filename="wumind_${job.id}.mp4"`,
      "Cache-Control": "private, max-age=3600",
    },
  });
}
