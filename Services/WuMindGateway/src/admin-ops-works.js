/**
 * WUMIND Admin Operations, Fee-Waiver (管理员免充值), AIHubMix Pool Balance,
 * Private Cross-Device "My Works" (我的作品), and Managed Realtime Voice Proxy.
 */

const MICROS_PER_YUAN = 1_000_000;
const AIHUBMIX_QUOTA_PER_USD = 500_000;

function microsToYuan(micros) {
  return Math.round((Number(micros || 0) / MICROS_PER_YUAN) * 10000) / 10000;
}

function yuanToMicros(yuan) {
  const n = Number(yuan);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.round(n * MICROS_PER_YUAN);
}

function roundUSD(val) {
  return Math.round(Number(val || 0) * 100) / 100;
}

// ============================================================================
// 1. Server-Verified Admin Fee-Waiver (管理员免充值) & Upstream Quota Detection
// ============================================================================

export function isUserBillingExempt(env, user) {
  if (!user || !user.id) return false;
  if (Number(user.billing_exempt || 0) === 1) return true;
  const allowRaw = String(env.ADMIN_EXEMPT_USER_IDS || "").trim();
  if (!allowRaw) return false;
  const set = new Set(
    allowRaw
      .split(",")
      .map((s) => s.trim().toUpperCase())
      .filter(Boolean)
  );
  return set.has(String(user.id).trim().toUpperCase());
}

/**
 * Checks per-minute rate limit and configurable daily upstream cost ceiling for billing-exempt admins.
 * Prevents runaway accidental spending (especially on high-cost video models).
 */
export async function checkAdminExemptQuota(env, user, estimatedCostMicros = 0) {
  const maxRpm = Math.max(1, parseInt(env.ADMIN_EXEMPT_RPM || "30", 10) || 30);
  const globalCapYuan = Math.max(1, Number(env.ADMIN_EXEMPT_DAILY_CAP_YUAN || 200));
  const userCapMicros = Number(user.admin_daily_cost_cap_micros || 0);
  const dailyCapMicros = userCapMicros > 0 ? userCapMicros : yuanToMicros(globalCapYuan);

  const [rpmRow, dailyRow] = await Promise.all([
    env.DB.prepare(
      "SELECT COUNT(*) AS cnt FROM ledger WHERE user_id = ? AND kind LIKE 'admin_exempt_%' AND created_at >= datetime('now', '-1 minute')"
    ).bind(user.id).first(),
    env.DB.prepare(
      "SELECT COALESCE(SUM(upstream_cost_micros), 0) AS spent_today FROM ledger WHERE user_id = ? AND kind LIKE 'admin_exempt_%' AND date(created_at) = date('now')"
    ).bind(user.id).first(),
  ]);

  const recentCount = Number(rpmRow?.cnt || 0);
  if (recentCount >= maxRpm) {
    return {
      allowed: false,
      status: 429,
      code: "admin_exempt_rate_limited",
      error: `管理员免扣通道触发频率保护（每分钟上限 ${maxRpm} 次），请稍后再试。`,
    };
  }

  const spentTodayMicros = Number(dailyRow?.spent_today || 0);
  if (spentTodayMicros + Math.max(0, Number(estimatedCostMicros || 0)) > dailyCapMicros) {
    return {
      allowed: false,
      status: 429,
      code: "admin_exempt_daily_cap_exceeded",
      error: `已达到管理员免扣每日上游成本上限（今日已记录 ¥${microsToYuan(spentTodayMicros)}，上限 ¥${microsToYuan(dailyCapMicros)}），可在计费管理页调高上限后继续。`,
      spentTodayYuan: microsToYuan(spentTodayMicros),
      dailyCapYuan: microsToYuan(dailyCapMicros),
    };
  }

  return {
    allowed: true,
    spentTodayYuan: microsToYuan(spentTodayMicros),
    dailyCapYuan: microsToYuan(dailyCapMicros),
  };
}

/**
 * Records an exempt-admin invocation in ledger & users.upstream_spent_micros
 * with cost_micros = 0 and ZERO change to App wallet balance.
 */
export async function recordAdminExemptUsage(env, {
  userID,
  kind,
  provider = "",
  model = "",
  promptTokens = 0,
  completionTokens = 0,
  reasoningTokens = 0,
  upstreamCostMicros = 0,
  note = "",
}) {
  const userRow = await env.DB.prepare("SELECT balance_micros FROM users WHERE id = ?").bind(userID).first();
  const bal = Number(userRow?.balance_micros || 0);
  const safeUpstream = Math.max(0, Math.round(Number(upstreamCostMicros || 0)));
  const exemptKind = kind.startsWith("admin_exempt_") ? kind : `admin_exempt_${kind}`;
  const cleanNote = `[管理员免扣 · 上游成本 ¥${microsToYuan(safeUpstream)}] ${String(note || "").trim()}`.slice(0, 180);

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO ledger
       (user_id, kind, provider, model, prompt_tokens, completion_tokens, reasoning_tokens, cost_micros, upstream_cost_micros, balance_before_micros, balance_after_micros, environment, operator_id, note)
       VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, 'production', ?, ?)`
    ).bind(
      userID,
      exemptKind,
      provider,
      model,
      promptTokens,
      completionTokens,
      reasoningTokens,
      safeUpstream,
      bal,
      bal,
      userID,
      cleanNote
    ),
    env.DB.prepare(
      "UPDATE users SET upstream_spent_micros = upstream_spent_micros + ?, updated_at = datetime('now') WHERE id = ?"
    ).bind(safeUpstream, userID),
  ]);

  return {
    adminExempt: true,
    promptTokens,
    completionTokens,
    reasoningTokens,
    costYuan: 0,
    upstreamCostYuan: microsToYuan(safeUpstream),
    balanceYuan: microsToYuan(bal),
  };
}

/**
 * Detects whether an upstream AI provider error is due to upstream API account exhaustion
 * (NOT the user's App wallet balance).
 */
export function isUpstreamBalanceError(httpStatus, rawText) {
  if (httpStatus === 402) return true;
  const lower = String(rawText || "").toLowerCase();
  return (
    lower.includes("insufficient_quota") ||
    lower.includes("insufficient_user_quota") ||
    lower.includes("insufficient balance") ||
    lower.includes("insufficient_balance") ||
    lower.includes("quota_exceeded") ||
    lower.includes("quota exceeded") ||
    lower.includes("credit balance is too low") ||
    lower.includes("余额不足")
  );
}

export async function handleAdminSetBillingExempt(request, env, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可调整账号免扣权限。", code: "admin_forbidden" }, 403);
  }
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求格式错误。" }, 400); }
  const userID = String(body.userID || "").trim().toUpperCase();
  if (!userID) return json({ error: "缺少目标账号 userID。" }, 400);

  const user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(userID).first();
  if (!user) return json({ error: `未找到已注册账号 ${userID}。`, code: "user_not_found" }, 404);

  const exempt = Boolean(body.exempt);
  const dailyCapYuan = body.dailyCostCapYuan !== undefined
    ? Math.max(0, Number(body.dailyCostCapYuan || 0))
    : microsToYuan(user.admin_daily_cost_cap_micros || 0);
  const dailyCapMicros = yuanToMicros(dailyCapYuan);

  await env.DB.prepare(
    "UPDATE users SET billing_exempt = ?, admin_daily_cost_cap_micros = ?, updated_at = datetime('now') WHERE id = ?"
  ).bind(exempt ? 1 : 0, dailyCapMicros, userID).run();

  const updated = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(userID).first();
  return json({
    ok: true,
    userID: updated.id,
    displayName: updated.display_name || "",
    billingExempt: Boolean(updated.billing_exempt),
    dailyCostCapYuan: microsToYuan(updated.admin_daily_cost_cap_micros || 0),
    balanceYuan: microsToYuan(updated.balance_micros || 0),
    upstreamSpentYuan: microsToYuan(updated.upstream_spent_micros || 0),
  });
}

// ============================================================================
// 2. Admin Full Registered User Registry (Who Registered, Recharged, Balance, Usage)
// ============================================================================

export async function handleAdminListUsers(request, env, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可查看注册用户与消费总览。", code: "admin_forbidden" }, 403);
  }
  const url = new URL(request.url);
  const q = String(url.searchParams.get("q") || "").trim().toUpperCase();
  const limit = Math.max(1, Math.min(200, parseInt(url.searchParams.get("limit") || "100", 10) || 100));

  const sql = q
    ? `SELECT u.*,
         (SELECT COUNT(*) FROM ledger l WHERE l.user_id = u.id AND (l.kind IN ('chat','image','image_edit','video','web_search','realtime_voice') OR l.kind LIKE 'admin_exempt_%')) AS req_count,
         (SELECT COALESCE(SUM(l.prompt_tokens + l.completion_tokens + l.reasoning_tokens), 0) FROM ledger l WHERE l.user_id = u.id) AS total_tokens,
         (SELECT MAX(l.created_at) FROM ledger l WHERE l.user_id = u.id) AS last_activity_at
       FROM users u
       WHERE UPPER(u.id) LIKE ? OR UPPER(u.display_name) LIKE ?
       ORDER BY u.created_at DESC
       LIMIT ?`
    : `SELECT u.*,
         (SELECT COUNT(*) FROM ledger l WHERE l.user_id = u.id AND (l.kind IN ('chat','image','image_edit','video','web_search','realtime_voice') OR l.kind LIKE 'admin_exempt_%')) AS req_count,
         (SELECT COALESCE(SUM(l.prompt_tokens + l.completion_tokens + l.reasoning_tokens), 0) FROM ledger l WHERE l.user_id = u.id) AS total_tokens,
         (SELECT MAX(l.created_at) FROM ledger l WHERE l.user_id = u.id) AS last_activity_at
       FROM users u
       ORDER BY u.created_at DESC
       LIMIT ?`;

  const rows = q
    ? await env.DB.prepare(sql).bind(`%${q}%`, `%${q}%`, limit).all()
    : await env.DB.prepare(sql).bind(limit).all();

  const users = (rows.results || []).map((u) => {
    const bal = Number(u.balance_micros || 0);
    const res = Number(u.reserved_micros || 0);
    return {
      userID: u.id,
      displayName: u.display_name || "",
      registeredRole: u.registered_role || "user",
      balanceYuan: microsToYuan(bal),
      reservedYuan: microsToYuan(res),
      availableYuan: microsToYuan(Math.max(0, bal - res)),
      sandboxBalanceYuan: microsToYuan(u.sandbox_balance_micros || 0),
      totalRechargedYuan: microsToYuan(u.total_recharged_micros || 0),
      purchasedRechargedYuan: microsToYuan(u.purchased_recharged_micros || 0),
      adminGrantedYuan: microsToYuan(u.admin_granted_micros || 0),
      totalSpentYuan: microsToYuan(u.total_spent_micros || 0),
      upstreamSpentYuan: microsToYuan(u.upstream_spent_micros || 0),
      billingExempt: isUserBillingExempt(env, u),
      dailyCostCapYuan: microsToYuan(u.admin_daily_cost_cap_micros || 0) || Number(env.ADMIN_EXEMPT_DAILY_CAP_YUAN || 200),
      requestCount: Number(u.req_count || 0),
      totalTokens: Number(u.total_tokens || 0),
      lastActivityAt: u.last_activity_at || u.updated_at || u.created_at,
      createdAt: u.created_at,
    };
  });

  const rechargedUsersCount = users.filter((u) => u.purchasedRechargedYuan > 0 || u.adminGrantedYuan > 0 || u.totalRechargedYuan > 0).length;
  return json({
    ok: true,
    totalUsers: users.length,
    rechargedUsersCount,
    users,
  });
}

// ============================================================================
// 3. AIHubMix Shared Pool Account Balance (Manage Key, Server-Side Only!) + Alert Threshold
// ============================================================================

async function loadUpstreamBalanceState(env) {
  const [snapRow, alertRow] = await Promise.all([
    env.DB.prepare("SELECT value FROM config WHERE key = 'aihubmix_balance_snapshot'").first(),
    env.DB.prepare("SELECT value FROM config WHERE key = 'upstream_balance_alert_config'").first(),
  ]);
  let snapshot = null;
  if (snapRow?.value) {
    try { snapshot = JSON.parse(snapRow.value); } catch {}
  }
  let alertCfg = { lowBalanceAlertUSD: Math.max(0, Number(env.AIHUBMIX_LOW_BALANCE_ALERT_USD || 10)) };
  if (alertRow?.value) {
    try {
      const parsed = JSON.parse(alertRow.value);
      if (typeof parsed?.lowBalanceAlertUSD === "number" && Number.isFinite(parsed.lowBalanceAlertUSD)) {
        alertCfg.lowBalanceAlertUSD = Math.max(0, parsed.lowBalanceAlertUSD);
      }
    } catch {}
  }
  return { snapshot, alertCfg };
}

function resolveAIHubMixBaseOrigin(env) {
  const raw = String(env.AIHUBMIX_BASE_URL || "https://aihubmix.com").trim().replace(/\/+$/, "");
  try {
    const u = new URL(raw);
    if (u.protocol === "https:") return u.origin;
  } catch {}
  return "https://aihubmix.com";
}

function buildUpstreamBalanceResponse(env, snapshot, alertCfg, syncFailed = false, syncError = null) {
  const configured = Boolean((env.AIHUBMIX_MANAGE_KEY || "").trim());
  const threshold = roundUSD(alertCfg.lowBalanceAlertUSD);
  const hasSnapshot = snapshot && typeof snapshot.availableUSD === "number";
  const availableUSD = hasSnapshot ? roundUSD(snapshot.availableUSD) : null;
  const usedUSD = hasSnapshot && typeof snapshot.usedUSD === "number" ? roundUSD(snapshot.usedUSD) : null;
  const alertTriggered = hasSnapshot && threshold > 0 && availableUSD <= threshold;

  let statusLabel = "尚未同步";
  if (!configured && !hasSnapshot) {
    statusLabel = "未配置 Manage Key（AIHUBMIX_MANAGE_KEY）";
  } else if (syncFailed) {
    statusLabel = hasSnapshot ? "上次余额 · 同步失败" : "同步失败（无历史缓存）";
  } else if (hasSnapshot) {
    statusLabel = "账号共享余额";
  }

  return {
    ok: !syncFailed,
    provider: "AIHubMix",
    currency: "USD",
    configured,
    availableUSD,
    usedUSD,
    accountName: snapshot?.accountName || null,
    requestCount: snapshot?.requestCount ?? null,
    syncedAt: snapshot?.syncedAt || null,
    syncFailed,
    syncError,
    statusLabel,
    lowBalanceAlertUSD: threshold,
    alertTriggered,
    topUpURL: "https://console.aihubmix.com/topup",
  };
}

async function fetchAIHubMixSelfBalance(env) {
  const manageKey = String(env.AIHUBMIX_MANAGE_KEY || "").trim();
  if (!manageKey) {
    throw new Error("未在 Cloudflare Worker Secrets 配置 AIHUBMIX_MANAGE_KEY（需使用控制台「系统访问令牌 Manage Key」，不可使用 sk- 推理 Key）。");
  }
  const baseOrigin = resolveAIHubMixBaseOrigin(env);
  const url = `${baseOrigin}/api/user/self`;

  // Official AIHubMix CLI uses raw Authorization: <token>; get-self doc also shows Bearer <token>.
  // Try raw first per CLI spec, fall back once to Bearer on HTTP 401.
  let res = await fetch(url, {
    method: "GET",
    headers: {
      Authorization: manageKey,
      Accept: "application/json",
      "Content-Type": "application/json",
    },
  });
  if (res.status === 401 && !manageKey.toLowerCase().startsWith("bearer ")) {
    res = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${manageKey}`,
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    });
  }

  const rawText = await res.text();
  if (!res.ok) {
    throw new Error(`AIHubMix /api/user/self 返回 HTTP ${res.status}`);
  }
  let parsed;
  try { parsed = JSON.parse(rawText); } catch {
    throw new Error("AIHubMix 余额接口返回非 JSON 数据");
  }
  if (parsed.success === false || !parsed.data || typeof parsed.data.quota === "undefined") {
    throw new Error(String(parsed.message || "AIHubMix 未返回有效余额字段 (data.quota)"));
  }
  const quota = Number(parsed.data.quota);
  const usedQuota = Number(parsed.data.used_quota || 0);
  if (!Number.isFinite(quota)) {
    throw new Error("AIHubMix 返回的 quota 字段非法");
  }

  const snapshot = {
    availableUSD: roundUSD(quota / AIHUBMIX_QUOTA_PER_USD),
    usedUSD: roundUSD(usedQuota / AIHUBMIX_QUOTA_PER_USD),
    accountName: String(parsed.data.display_name || parsed.data.username || "").slice(0, 64),
    requestCount: Number(parsed.data.request_count || 0),
    syncedAt: new Date().toISOString(),
  };

  await env.DB.prepare(
    `INSERT INTO config (key, value, updated_at) VALUES ('aihubmix_balance_snapshot', ?, datetime('now'))
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')`
  ).bind(JSON.stringify(snapshot)).run();

  return snapshot;
}

export async function handleAdminGetUpstreamBalance(request, env, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可查看上游 API 账户余额。", code: "admin_forbidden" }, 403);
  }
  const url = new URL(request.url);
  const shouldRefresh = url.searchParams.get("refresh") === "1" || url.searchParams.get("refresh") === "true";
  const { snapshot, alertCfg } = await loadUpstreamBalanceState(env);

  if (!shouldRefresh && snapshot) {
    return json(buildUpstreamBalanceResponse(env, snapshot, alertCfg, false, null));
  }
  if (!String(env.AIHUBMIX_MANAGE_KEY || "").trim()) {
    return json(buildUpstreamBalanceResponse(env, snapshot, alertCfg, false, null));
  }
  try {
    const fresh = await fetchAIHubMixSelfBalance(env);
    return json(buildUpstreamBalanceResponse(env, fresh, alertCfg, false, null));
  } catch (err) {
    // CRITICAL: Never overwrite cached balance with $0 on failure! Return last known + syncFailed=true
    return json(buildUpstreamBalanceResponse(env, snapshot, alertCfg, true, String(err?.message || err).slice(0, 220)));
  }
}

export async function handleAdminRefreshUpstreamBalance(request, env, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可刷新上游 API 账户余额。", code: "admin_forbidden" }, 403);
  }
  const { snapshot, alertCfg } = await loadUpstreamBalanceState(env);
  try {
    const fresh = await fetchAIHubMixSelfBalance(env);
    return json(buildUpstreamBalanceResponse(env, fresh, alertCfg, false, null));
  } catch (err) {
    return json(buildUpstreamBalanceResponse(env, snapshot, alertCfg, true, String(err?.message || err).slice(0, 220)));
  }
}

export async function handleAdminSetUpstreamAlertThreshold(request, env, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可设置上游余额报警阈值。", code: "admin_forbidden" }, 403);
  }
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求格式错误。" }, 400); }
  const threshold = Number(body.lowBalanceAlertUSD);
  if (!Number.isFinite(threshold) || threshold < 0 || threshold > 1_000_000) {
    return json({ error: "请输入有效的余额报警阈值（USD，>= 0）。" }, 400);
  }
  const clean = roundUSD(threshold);
  await env.DB.prepare(
    `INSERT INTO config (key, value, updated_at) VALUES ('upstream_balance_alert_config', ?, datetime('now'))
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')`
  ).bind(JSON.stringify({ lowBalanceAlertUSD: clean })).run();

  const { snapshot, alertCfg } = await loadUpstreamBalanceState(env);
  return json(buildUpstreamBalanceResponse(env, snapshot, alertCfg, false, null));
}

// ============================================================================
// 4. Private Cross-Device "My Works" (我的作品) — Image / Video / PPT / 3D
// ============================================================================

const VALID_WORK_TYPES = new Set(["image", "video", "ppt", "scene3d"]);

function safeParseJSON(raw, fallback) {
  if (!raw) return fallback;
  try { return JSON.parse(raw); } catch { return fallback; }
}

function serializeWorkSummary(row) {
  return {
    id: row.id,
    userID: row.user_id,
    workType: row.work_type,
    title: row.title || "",
    prompt: row.prompt || "",
    modelID: row.model_id || "",
    params: safeParseJSON(row.params_json, {}),
    referenceAssets: safeParseJSON(row.reference_assets_json, []),
    status: row.status || "queued",
    progress: Number(row.progress || 0),
    upstreamJobID: row.upstream_job_id || null,
    idempotencyKey: row.idempotency_key || null,
    errorMessage: row.error_message || null,
    previewBase64: row.preview_base64 || null,
    assetMime: row.asset_mime || null,
    hasAsset: Boolean(row.has_asset ?? row.asset_base64),
    hasProject: Boolean(row.has_project ?? row.project_json),
    timing: safeParseJSON(row.timing_json, null),
    versionNumber: Number(row.version_number || 1),
    parentWorkID: row.parent_work_id || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function serializeWorkDetail(row) {
  return {
    ...serializeWorkSummary(row),
    assetBase64: row.asset_base64 || null,
    projectJSON: row.project_json || null,
  };
}

/**
 * Helper used internally by managed image/video routes to immediately record tasks in `user_works`.
 */
export async function upsertWorkFromGatewayTask(env, {
  id,
  userID,
  workType,
  title,
  prompt,
  modelID,
  params = {},
  referenceAssets = [],
  status = "queued",
  progress = 0,
  upstreamJobID = null,
  idempotencyKey = null,
  errorMessage = null,
  previewBase64 = null,
  assetMime = null,
  assetBase64 = null,
  projectJSON = null,
  timing = null,
}) {
  const safeAsset = assetBase64 && assetBase64.length <= 4_500_000 ? assetBase64 : null;
  const safePreview = previewBase64 && previewBase64.length <= 280_000
    ? previewBase64
    : (safeAsset && safeAsset.length <= 280_000 ? safeAsset : null);
  await env.DB.prepare(
    `INSERT INTO user_works
     (id, user_id, work_type, title, prompt, model_id, params_json, reference_assets_json, status, progress,
      upstream_job_id, idempotency_key, error_message, preview_base64, asset_mime, asset_base64, project_json, timing_json, version_number, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, datetime('now'))
     ON CONFLICT(id) DO UPDATE SET
       status = excluded.status,
       progress = excluded.progress,
       upstream_job_id = COALESCE(excluded.upstream_job_id, user_works.upstream_job_id),
       error_message = excluded.error_message,
       preview_base64 = COALESCE(excluded.preview_base64, user_works.preview_base64),
       asset_mime = COALESCE(excluded.asset_mime, user_works.asset_mime),
       asset_base64 = COALESCE(excluded.asset_base64, user_works.asset_base64),
       project_json = COALESCE(excluded.project_json, user_works.project_json),
       timing_json = COALESCE(excluded.timing_json, user_works.timing_json),
       updated_at = datetime('now')
     WHERE user_works.user_id = excluded.user_id`
  ).bind(
    id,
    userID,
    workType,
    String(title || "").slice(0, 120),
    String(prompt || "").slice(0, 8000),
    String(modelID || "").slice(0, 96),
    JSON.stringify(params || {}),
    JSON.stringify(referenceAssets || []),
    status,
    Math.max(0, Math.min(100, Math.round(Number(progress || 0)))),
    upstreamJobID,
    idempotencyKey,
    errorMessage ? String(errorMessage).slice(0, 500) : null,
    safePreview,
    assetMime,
    safeAsset,
    projectJSON ? String(projectJSON).slice(0, 3_000_000) : null,
    timing ? JSON.stringify(timing) : null
  ).run();
}

export async function handleListUserWorks(request, env, { json, authenticateUser }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权，请先登录或注册 WUMIND 账号。" }, 401);

  const url = new URL(request.url);
  const typeFilter = String(url.searchParams.get("type") || "").trim().toLowerCase();
  const limit = Math.max(1, Math.min(100, parseInt(url.searchParams.get("limit") || "60", 10) || 60));

  const sql = VALID_WORK_TYPES.has(typeFilter)
    ? `SELECT id, user_id, work_type, title, prompt, model_id, params_json, reference_assets_json, status, progress,
              upstream_job_id, idempotency_key, error_message, preview_base64, asset_mime,
              CASE WHEN asset_base64 IS NOT NULL AND length(asset_base64) > 0 THEN 1 ELSE 0 END AS has_asset,
              CASE WHEN project_json IS NOT NULL AND length(project_json) > 0 THEN 1 ELSE 0 END AS has_project,
              timing_json, version_number, parent_work_id, created_at, updated_at
       FROM user_works
       WHERE user_id = ? AND work_type = ?
       ORDER BY updated_at DESC LIMIT ?`
    : `SELECT id, user_id, work_type, title, prompt, model_id, params_json, reference_assets_json, status, progress,
              upstream_job_id, idempotency_key, error_message, preview_base64, asset_mime,
              CASE WHEN asset_base64 IS NOT NULL AND length(asset_base64) > 0 THEN 1 ELSE 0 END AS has_asset,
              CASE WHEN project_json IS NOT NULL AND length(project_json) > 0 THEN 1 ELSE 0 END AS has_project,
              timing_json, version_number, parent_work_id, created_at, updated_at
       FROM user_works
       WHERE user_id = ?
       ORDER BY updated_at DESC LIMIT ?`;

  const rows = VALID_WORK_TYPES.has(typeFilter)
    ? await env.DB.prepare(sql).bind(user.id, typeFilter, limit).all()
    : await env.DB.prepare(sql).bind(user.id, limit).all();

  return json({
    ok: true,
    userID: user.id,
    works: (rows.results || []).map(serializeWorkSummary),
  });
}

export async function handleCreateUserWork(request, env, { json, authenticateUser, randomCode }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);

  let body;
  try { body = await request.json(); } catch { return json({ error: "请求 JSON 格式错误。" }, 400); }

  const workType = String(body.workType || "").trim().toLowerCase();
  if (!VALID_WORK_TYPES.has(workType)) {
    return json({ error: "不支持的作品类型（需为 image / video / ppt / scene3d）。" }, 400);
  }

  const idem = body.idempotencyKey ? String(body.idempotencyKey).trim().slice(0, 96) : null;
  if (idem) {
    const existing = await env.DB.prepare(
      "SELECT * FROM user_works WHERE user_id = ? AND idempotency_key = ?"
    ).bind(user.id, idem).first();
    if (existing) {
      return json({ ok: true, idempotentReplay: true, work: serializeWorkDetail(existing) });
    }
  }

  const id = body.id && /^[A-Za-z0-9_-]{6,64}$/.test(String(body.id))
    ? String(body.id)
    : `WRK-${randomCode(12)}`;

  // Ownership safety: never let user overwrite another account's work ID
  const collision = await env.DB.prepare("SELECT user_id FROM user_works WHERE id = ?").bind(id).first();
  if (collision && collision.user_id !== user.id) {
    return json({ error: "无权访问或覆盖该作品编号。", code: "work_forbidden" }, 403);
  }

  await upsertWorkFromGatewayTask(env, {
    id,
    userID: user.id,
    workType,
    title: body.title || `${workType.toUpperCase()} 作品`,
    prompt: body.prompt || "",
    modelID: body.modelID || "",
    params: body.params || {},
    referenceAssets: Array.isArray(body.referenceAssets) ? body.referenceAssets.slice(0, 6) : [],
    status: body.status || "queued",
    progress: body.progress ?? 0,
    upstreamJobID: body.upstreamJobID || null,
    idempotencyKey: idem,
    errorMessage: body.errorMessage || null,
    previewBase64: body.previewBase64 || null,
    assetMime: body.assetMime || null,
    assetBase64: body.assetBase64 || null,
    projectJSON: typeof body.projectJSON === "string"
      ? body.projectJSON
      : (body.projectJSON ? JSON.stringify(body.projectJSON) : null),
    timing: body.timing || null,
  });

  const saved = await env.DB.prepare("SELECT * FROM user_works WHERE id = ? AND user_id = ?").bind(id, user.id).first();
  return json({ ok: true, work: serializeWorkDetail(saved) });
}

export async function handleGetUserWork(request, env, workID, { json, authenticateUser }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  const row = await env.DB.prepare(
    "SELECT * FROM user_works WHERE id = ? AND user_id = ?"
  ).bind(workID, user.id).first();
  if (!row) return json({ error: "未找到该作品或无权查看。", code: "work_not_found" }, 404);
  return json({ ok: true, work: serializeWorkDetail(row) });
}

export async function handleUpdateUserWork(request, env, workID, { json, authenticateUser, randomCode }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  const existing = await env.DB.prepare(
    "SELECT * FROM user_works WHERE id = ? AND user_id = ?"
  ).bind(workID, user.id).first();
  if (!existing) return json({ error: "未找到该作品或无权修改。", code: "work_not_found" }, 404);

  let body;
  try { body = await request.json(); } catch { return json({ error: "请求格式错误。" }, 400); }

  // Versioned save: creates a NEW child work preserving the original untouched!
  if (body.createNewVersion) {
    const rootID = existing.parent_work_id || existing.id;
    const maxVerRow = await env.DB.prepare(
      "SELECT COALESCE(MAX(version_number), 1) AS max_ver FROM user_works WHERE user_id = ? AND (id = ? OR parent_work_id = ?)"
    ).bind(user.id, rootID, rootID).first();
    const nextVer = Number(maxVerRow?.max_ver || existing.version_number || 1) + 1;
    const newID = `WRK-${randomCode(12)}`;

    const projectStr = body.projectJSON !== undefined
      ? (typeof body.projectJSON === "string" ? body.projectJSON : JSON.stringify(body.projectJSON))
      : existing.project_json;
    const assetStr = body.assetBase64 !== undefined ? body.assetBase64 : existing.asset_base64;
    const previewStr = body.previewBase64 !== undefined ? body.previewBase64 : existing.preview_base64;

    await env.DB.prepare(
      `INSERT INTO user_works
       (id, user_id, work_type, title, prompt, model_id, params_json, reference_assets_json, status, progress,
        upstream_job_id, error_message, preview_base64, asset_mime, asset_base64, project_json, timing_json,
        version_number, parent_work_id, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))`
    ).bind(
      newID,
      user.id,
      existing.work_type,
      String(body.title ?? existing.title).slice(0, 120),
      String(body.prompt ?? existing.prompt).slice(0, 8000),
      String(body.modelID ?? existing.model_id).slice(0, 96),
      body.params ? JSON.stringify(body.params) : existing.params_json,
      existing.reference_assets_json,
      String(body.status ?? existing.status),
      body.progress !== undefined ? Math.max(0, Math.min(100, Math.round(Number(body.progress)))) : existing.progress,
      existing.upstream_job_id,
      body.errorMessage !== undefined ? body.errorMessage : existing.error_message,
      previewStr,
      body.assetMime ?? existing.asset_mime,
      assetStr,
      projectStr,
      body.timing ? JSON.stringify(body.timing) : existing.timing_json,
      nextVer,
      rootID
    ).run();

    const created = await env.DB.prepare("SELECT * FROM user_works WHERE id = ?").bind(newID).first();
    return json({ ok: true, versionCreated: true, work: serializeWorkDetail(created) });
  }

  // In-place status/progress/asset update
  const nextTitle = body.title !== undefined ? String(body.title).slice(0, 120) : existing.title;
  const nextStatus = body.status !== undefined ? String(body.status) : existing.status;
  const nextProgress = body.progress !== undefined ? Math.max(0, Math.min(100, Math.round(Number(body.progress)))) : existing.progress;
  const nextError = body.errorMessage !== undefined ? (body.errorMessage ? String(body.errorMessage).slice(0, 500) : null) : existing.error_message;
  const nextPreview = body.previewBase64 !== undefined ? body.previewBase64 : existing.preview_base64;
  const nextAssetMime = body.assetMime !== undefined ? body.assetMime : existing.asset_mime;
  const nextAsset = body.assetBase64 !== undefined ? body.assetBase64 : existing.asset_base64;
  const nextProject = body.projectJSON !== undefined
    ? (typeof body.projectJSON === "string" ? body.projectJSON : JSON.stringify(body.projectJSON))
    : existing.project_json;
  const nextTiming = body.timing !== undefined ? JSON.stringify(body.timing) : existing.timing_json;

  await env.DB.prepare(
    `UPDATE user_works
     SET title = ?, status = ?, progress = ?, error_message = ?, preview_base64 = ?,
         asset_mime = ?, asset_base64 = ?, project_json = ?, timing_json = ?, updated_at = datetime('now')
     WHERE id = ? AND user_id = ?`
  ).bind(
    nextTitle,
    nextStatus,
    nextProgress,
    nextError,
    nextPreview,
    nextAssetMime,
    nextAsset,
    nextProject,
    nextTiming,
    workID,
    user.id
  ).run();

  const fresh = await env.DB.prepare("SELECT * FROM user_works WHERE id = ? AND user_id = ?").bind(workID, user.id).first();
  return json({ ok: true, work: serializeWorkDetail(fresh) });
}

export async function handleGetUserWorkAsset(request, env, workID, { json, authenticateUser }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  const row = await env.DB.prepare(
    "SELECT id, work_type, asset_mime, asset_base64 FROM user_works WHERE id = ? AND user_id = ?"
  ).bind(workID, user.id).first();
  if (!row) return json({ error: "未找到该作品或无权下载。", code: "work_not_found" }, 404);
  if (!row.asset_base64) {
    return json({ error: "该作品暂无可下载的原文件。", code: "asset_missing" }, 404);
  }
  const clean = String(row.asset_base64).replace(/^data:[^;]+;base64,/i, "").replace(/\s+/g, "");
  const bin = atob(clean);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  const mime = row.asset_mime || "application/octet-stream";
  return new Response(bytes, {
    status: 200,
    headers: {
      "Content-Type": mime,
      "Cache-Control": "private, max-age=3600",
    },
  });
}

export async function handleDeleteUserWork(request, env, workID, { json, authenticateUser }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  const res = await env.DB.prepare(
    "DELETE FROM user_works WHERE id = ? AND user_id = ?"
  ).bind(workID, user.id).run();
  if ((res.meta?.changes || 0) === 0) {
    return json({ error: "未找到该作品或无权删除。" }, 404);
  }
  return json({ ok: true, deletedID: workID });
}

// ============================================================================
// 5. Managed Realtime Voice WebSocket Proxy (GET /v1/realtime?model=gpt-realtime-2.1)
// ============================================================================

const ALLOWED_REALTIME_MODELS = new Set([
  "gpt-realtime-2.1",
  "gpt-realtime-2.1-mini",
  "gpt-realtime",
  "gpt-realtime-2",
]);

export async function handleRealtimeWebSocketProxy(request, env, { json, authenticateUser, sha256Hex }) {
  const url = new URL(request.url);
  // Support standard Authorization: Bearer <token> OR ?token= for WebSocket handshakes
  let user = await authenticateUser(request, env);
  if (!user) {
    const qToken = String(url.searchParams.get("token") || "").trim();
    if (qToken) {
      const hash = await sha256Hex(qToken);
      user = await env.DB.prepare("SELECT * FROM users WHERE token_hash = ?").bind(hash).first();
      if (!user) {
        const dt = await env.DB.prepare("SELECT user_id FROM device_tokens WHERE token_hash = ?").bind(hash).first();
        if (dt?.user_id) {
          user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(dt.user_id).first();
        }
      }
    }
  }
  if (!user) {
    return json({ error: "实时语音需要有效的 WUMIND 登录账号。", code: "unauthorized" }, 401);
  }

  const model = String(url.searchParams.get("model") || "gpt-realtime-2.1").trim();
  if (!ALLOWED_REALTIME_MODELS.has(model)) {
    return json({
      error: `不支持的实时语音模型：${model}（当前支持：${[...ALLOWED_REALTIME_MODELS].join(", ")}）。`,
      code: "unsupported_realtime_model",
    }, 400);
  }

  const exempt = isUserBillingExempt(env, user);
  if (exempt) {
    const capCheck = await checkAdminExemptQuota(env, user, 500_000);
    if (!capCheck.allowed) {
      return json({ error: capCheck.error, code: capCheck.code }, capCheck.status);
    }
  } else {
    const available = Math.max(0, Number(user.balance_micros || 0) - Number(user.reserved_micros || 0));
    // Require at least ¥1.00 available to open a real-time audio session
    if (available < 1_000_000) {
      return json({
        error: `可用余额不足（可用 ¥${microsToYuan(available)}），实时语音需至少 ¥1.00 可用余额。`,
        code: "insufficient_balance",
      }, 402);
    }
  }

  const upgradeHeader = (request.headers.get("Upgrade") || "").toLowerCase();
  if (upgradeHeader !== "websocket") {
    return json({
      ok: true,
      protocol: "websocket",
      model,
      adminExempt: exempt,
      hint: "请通过 WebSocket Upgrade 连接此端点（Authorization: Bearer <WUMIND_TOKEN>）。",
    }, 200);
  }

  // Choose server-side upstream: AIHubMix (preferred) or Official OpenAI
  const aihubmixKey = String(env.AIHUBMIX_API_KEY || "").trim();
  const openaiKey = String(env.OPENAI_API_KEY || "").trim();
  const upstreamKey = aihubmixKey || openaiKey;
  if (!upstreamKey) {
    return json({ error: "网关尚未配置实时语音上游 API Key（AIHUBMIX_API_KEY / OPENAI_API_KEY）。", code: "upstream_key_missing" }, 503);
  }
  const upstreamOrigin = aihubmixKey ? resolveAIHubMixBaseOrigin(env) : "https://api.openai.com";
  const upstreamURL = `${upstreamOrigin}/v1/realtime?model=${encodeURIComponent(model)}`;

  // Server-side WebSocket handshake: NEVER forward browser Origin header (AIHubMix rejects Origin!)
  const upstreamResp = await fetch(upstreamURL, {
    headers: {
      Upgrade: "websocket",
      Authorization: `Bearer ${upstreamKey}`,
    },
  });

  if (upstreamResp.status !== 101 || !upstreamResp.webSocket) {
    const rawErr = await upstreamResp.text().catch(() => "");
    if (isUpstreamBalanceError(upstreamResp.status, rawErr)) {
      return json({
        error: "上游 API 余额不足，请管理员前往上游控制台充值（非 App 钱包余额问题）。",
        code: "upstream_balance_insufficient",
      }, 502);
    }
    return json({
      error: `实时语音上游握手失败（HTTP ${upstreamResp.status}）：${String(rawErr).slice(0, 220)}`,
      code: `realtime_upstream_${upstreamResp.status}`,
    }, 502);
  }

  const upstreamWS = upstreamResp.webSocket;
  upstreamWS.accept();

  const pair = new WebSocketPair();
  const [clientWS, serverWS] = Object.values(pair);
  serverWS.accept();

  serverWS.addEventListener("message", (evt) => {
    try { upstreamWS.send(evt.data); } catch {}
  });
  serverWS.addEventListener("close", () => {
    try { upstreamWS.close(); } catch {}
  });

  upstreamWS.addEventListener("message", async (evt) => {
    try { serverWS.send(evt.data); } catch {}
    // Meter real token usage on response.done events!
    if (typeof evt.data === "string" && evt.data.includes("response.done")) {
      try {
        const parsed = JSON.parse(evt.data);
        if (parsed?.type === "response.done" && parsed?.response?.usage) {
          const u = parsed.response.usage;
          const inTok = Number(u.input_tokens || 0);
          const outTok = Number(u.output_tokens || 0);
          // Audio realtime estimate: ¥240 / 1M input, ¥480 / 1M output (conservative CNY equivalent of $32/$64)
          const costMicros = Math.max(1000, Math.round(inTok * 240 + outTok * 480));
          if (exempt) {
            await recordAdminExemptUsage(env, {
              userID: user.id,
              kind: "admin_exempt_realtime_voice",
              provider: aihubmixKey ? "aihubmix" : "openAI",
              model,
              promptTokens: inTok,
              completionTokens: outTok,
              upstreamCostMicros: costMicros,
              note: `实时语音 · ${model}`,
            });
          } else {
            const cur = await env.DB.prepare("SELECT balance_micros FROM users WHERE id = ?").bind(user.id).first();
            const before = Number(cur?.balance_micros || 0);
            const deducted = Math.min(before, costMicros);
            const after = before - deducted;
            await env.DB.batch([
              env.DB.prepare(
                "UPDATE users SET balance_micros = ?, total_spent_micros = total_spent_micros + ?, upstream_spent_micros = upstream_spent_micros + ?, updated_at = datetime('now') WHERE id = ?"
              ).bind(after, deducted, costMicros, user.id),
              env.DB.prepare(
                `INSERT INTO ledger
                 (user_id, kind, provider, model, prompt_tokens, completion_tokens, cost_micros, upstream_cost_micros, balance_before_micros, balance_after_micros, environment, note)
                 VALUES (?, 'realtime_voice', ?, ?, ?, ?, ?, ?, ?, ?, 'production', ?)`
              ).bind(user.id, aihubmixKey ? "aihubmix" : "openAI", model, inTok, outTok, deducted, costMicros, before, after, `实时语音 · ${model}`),
            ]);
            if (after <= 0) {
              try { serverWS.close(1008, "insufficient_balance"); } catch {}
              try { upstreamWS.close(); } catch {}
            }
          }
        }
      } catch {}
    }
  });
  upstreamWS.addEventListener("close", (evt) => {
    try { serverWS.close(evt.code || 1000, evt.reason || ""); } catch {}
  });

  return new Response(null, { status: 101, webSocket: clientWS });
}
