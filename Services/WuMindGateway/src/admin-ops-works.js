/**
 * WUMIND Admin Operations, Fee-Waiver (管理员免充值), AIHubMix Pool Balance,
 * Private Cross-Device "My Works" (我的作品), and Managed Realtime Voice Proxy.
 */

import { redactUpstreamDiagnostic } from "./upstream-diagnostics.js";

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

  const [rpmRow, dailyRow, inflightVideoRow] = await Promise.all([
    env.DB.prepare(
      "SELECT COUNT(*) AS cnt FROM ledger WHERE user_id = ? AND kind LIKE 'admin_exempt_%' AND created_at >= datetime('now', '-1 minute')"
    ).bind(user.id).first(),
    env.DB.prepare(
      "SELECT COALESCE(SUM(upstream_cost_micros), 0) AS spent_today FROM ledger WHERE user_id = ? AND kind LIKE 'admin_exempt_%' AND date(created_at) = date('now')"
    ).bind(user.id).first(),
    env.DB.prepare(
      "SELECT COALESCE(SUM(estimated_cost_micros), 0) AS inflight_cost, COUNT(*) AS inflight_count FROM video_jobs WHERE user_id = ? AND is_admin_exempt = 1 AND status IN ('queued', 'in_progress')"
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
  const inflightVideoMicros = Number(inflightVideoRow?.inflight_cost || 0);
  const inflightVideoCount = Number(inflightVideoRow?.inflight_count || 0);
  const committedMicros = spentTodayMicros + inflightVideoMicros;
  const requestedMicros = Math.max(0, Number(estimatedCostMicros || 0));

  if (committedMicros + requestedMicros > dailyCapMicros) {
    const inflightNote = inflightVideoMicros > 0
      ? ` + 进行中视频预估 ¥${microsToYuan(inflightVideoMicros)}（${inflightVideoCount} 个任务）`
      : "";
    return {
      allowed: false,
      status: 429,
      code: "admin_exempt_daily_cap_exceeded",
      error: `已达到管理员免扣每日上游成本上限（今日已结算 ¥${microsToYuan(spentTodayMicros)}${inflightNote}，上限 ¥${microsToYuan(dailyCapMicros)}），可在计费管理页调高上限后继续。`,
      spentTodayYuan: microsToYuan(spentTodayMicros),
      inflightYuan: microsToYuan(inflightVideoMicros),
      inflightCount: inflightVideoCount,
      dailyCapYuan: microsToYuan(dailyCapMicros),
    };
  }

  return {
    allowed: true,
    spentTodayYuan: microsToYuan(spentTodayMicros),
    inflightYuan: microsToYuan(inflightVideoMicros),
    inflightCount: inflightVideoCount,
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
// 2. Admin Full Registered User Registry (Paginated 201+, Searchable, Detail & Breakdown)
// ============================================================================

export async function handleAdminListUsers(request, env, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可查看注册用户与消费总览。", code: "admin_forbidden" }, 403);
  }
  const url = new URL(request.url);
  const q = String(url.searchParams.get("q") || "").trim().toUpperCase();
  const page = Math.max(1, parseInt(url.searchParams.get("page") || "1", 10) || 1);
  const limit = Math.max(1, Math.min(200, parseInt(url.searchParams.get("limit") || "50", 10) || 50));
  const offset = (page - 1) * limit;

  const [globalStats, matchCountRow] = await Promise.all([
    env.DB.prepare(
      `SELECT
         COUNT(*) AS all_users,
         SUM(CASE WHEN date(created_at) = date('now') THEN 1 ELSE 0 END) AS today_new_users,
         SUM(CASE WHEN purchased_recharged_micros > 0 OR admin_granted_micros > 0 OR total_recharged_micros > 0 THEN 1 ELSE 0 END) AS recharged_users
       FROM users`
    ).first(),
    q
      ? env.DB.prepare("SELECT COUNT(*) AS cnt FROM users WHERE UPPER(id) LIKE ? OR UPPER(display_name) LIKE ?").bind(`%${q}%`, `%${q}%`).first()
      : env.DB.prepare("SELECT COUNT(*) AS cnt FROM users").first(),
  ]);

  const sql = q
    ? `SELECT u.*,
         (SELECT COUNT(*) FROM ledger l WHERE l.user_id = u.id AND (l.kind IN ('chat','image','image_edit','video','web_search','realtime_voice') OR l.kind LIKE 'admin_exempt_%')) AS req_count,
         (SELECT COALESCE(SUM(l.prompt_tokens + l.completion_tokens + l.reasoning_tokens), 0) FROM ledger l WHERE l.user_id = u.id) AS total_tokens,
         (SELECT MAX(l.created_at) FROM ledger l WHERE l.user_id = u.id) AS last_activity_at
       FROM users u
       WHERE UPPER(u.id) LIKE ? OR UPPER(u.display_name) LIKE ?
       ORDER BY u.created_at DESC, u.id DESC
       LIMIT ? OFFSET ?`
    : `SELECT u.*,
         (SELECT COUNT(*) FROM ledger l WHERE l.user_id = u.id AND (l.kind IN ('chat','image','image_edit','video','web_search','realtime_voice') OR l.kind LIKE 'admin_exempt_%')) AS req_count,
         (SELECT COALESCE(SUM(l.prompt_tokens + l.completion_tokens + l.reasoning_tokens), 0) FROM ledger l WHERE l.user_id = u.id) AS total_tokens,
         (SELECT MAX(l.created_at) FROM ledger l WHERE l.user_id = u.id) AS last_activity_at
       FROM users u
       ORDER BY u.created_at DESC, u.id DESC
       LIMIT ? OFFSET ?`;

  const rows = q
    ? await env.DB.prepare(sql).bind(`%${q}%`, `%${q}%`, limit, offset).all()
    : await env.DB.prepare(sql).bind(limit, offset).all();

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

  const matchedCount = Number(matchCountRow?.cnt || 0);
  const allUsersCount = Number(globalStats?.all_users || matchedCount);
  const todayNewUsers = Number(globalStats?.today_new_users || 0);
  const rechargedUsersCount = Number(globalStats?.recharged_users || 0);
  const totalPages = Math.max(1, Math.ceil(matchedCount / limit));

  return json({
    ok: true,
    totalUsers: matchedCount,
    allUsersCount,
    todayNewUsers,
    rechargedUsersCount,
    page,
    limit,
    totalPages,
    hasMore: offset + users.length < matchedCount,
    users,
  });
}

export async function handleAdminGetUserDetail(request, env, targetUserID, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可查看用户账单与用量详情。", code: "admin_forbidden" }, 403);
  }
  const cleanID = String(targetUserID || "").trim().toUpperCase();
  if (!cleanID) {
    return json({ error: "缺少目标用户 ID。" }, 400);
  }

  const u = await env.DB.prepare("SELECT * FROM users WHERE UPPER(id) = ?").bind(cleanID).first();
  if (!u) {
    return json({ error: `未找到注册用户 ${cleanID}。`, code: "user_not_found" }, 404);
  }

  const usageFilter = `(kind IN ('chat','image','image_edit','video','web_search','realtime_voice') OR kind LIKE 'admin_exempt_%')`;

  const [todayRow, weekRow, allTimeRow, refundRow, byModelRows, byKindRows, ledgerRows, auditRows] = await Promise.all([
    env.DB.prepare(
      `SELECT COUNT(*) AS reqs, COALESCE(SUM(prompt_tokens + completion_tokens + reasoning_tokens), 0) AS toks,
              COALESCE(SUM(CASE WHEN cost_micros > 0 THEN cost_micros ELSE 0 END), 0) AS spent,
              COALESCE(SUM(upstream_cost_micros), 0) AS upstream
       FROM ledger WHERE user_id = ? AND ${usageFilter} AND date(created_at) = date('now')`
    ).bind(u.id).first(),
    env.DB.prepare(
      `SELECT COUNT(*) AS reqs, COALESCE(SUM(prompt_tokens + completion_tokens + reasoning_tokens), 0) AS toks,
              COALESCE(SUM(CASE WHEN cost_micros > 0 THEN cost_micros ELSE 0 END), 0) AS spent,
              COALESCE(SUM(upstream_cost_micros), 0) AS upstream
       FROM ledger WHERE user_id = ? AND ${usageFilter} AND created_at >= datetime('now', '-7 days')`
    ).bind(u.id).first(),
    env.DB.prepare(
      `SELECT COUNT(*) AS reqs, COALESCE(SUM(prompt_tokens + completion_tokens + reasoning_tokens), 0) AS toks,
              COALESCE(SUM(CASE WHEN cost_micros > 0 THEN cost_micros ELSE 0 END), 0) AS spent,
              COALESCE(SUM(upstream_cost_micros), 0) AS upstream
       FROM ledger WHERE user_id = ? AND ${usageFilter}`
    ).bind(u.id).first(),
    env.DB.prepare(
      `SELECT COALESCE(SUM(ABS(cost_micros)), 0) AS refunded
       FROM ledger WHERE user_id = ? AND kind IN ('apple_iap_refund', 'sandbox_apple_iap_refund', 'refund')`
    ).bind(u.id).first(),
    env.DB.prepare(
      `SELECT COALESCE(NULLIF(model, ''), 'unknown') AS model, kind,
              COUNT(*) AS reqs,
              COALESCE(SUM(prompt_tokens + completion_tokens + reasoning_tokens), 0) AS toks,
              COALESCE(SUM(CASE WHEN cost_micros > 0 THEN cost_micros ELSE 0 END), 0) AS spent,
              COALESCE(SUM(upstream_cost_micros), 0) AS upstream
       FROM ledger WHERE user_id = ? AND ${usageFilter}
       GROUP BY model, kind
       ORDER BY spent DESC, reqs DESC
       LIMIT 30`
    ).bind(u.id).all(),
    env.DB.prepare(
      `SELECT kind, COUNT(*) AS reqs,
              COALESCE(SUM(CASE WHEN cost_micros > 0 THEN cost_micros ELSE 0 END), 0) AS spent,
              COALESCE(SUM(upstream_cost_micros), 0) AS upstream
       FROM ledger WHERE user_id = ? AND ${usageFilter}
       GROUP BY kind
       ORDER BY spent DESC, reqs DESC`
    ).bind(u.id).all(),
    env.DB.prepare(
      `SELECT id, kind, provider, model, prompt_tokens, completion_tokens, reasoning_tokens,
              cost_micros, upstream_cost_micros, balance_before_micros, balance_after_micros,
              environment, operator_id, note, created_at
       FROM ledger WHERE user_id = ? ORDER BY id DESC LIMIT 50`
    ).bind(u.id).all(),
    env.DB.prepare(
      `SELECT id, operator_id, target_user_id, environment, amount_micros,
              balance_before_micros, balance_after_micros, note, created_at
       FROM admin_credit_audit WHERE target_user_id = ? ORDER BY created_at DESC LIMIT 20`
    ).bind(u.id).all(),
  ]);

  const bal = Number(u.balance_micros || 0);
  const res = Number(u.reserved_micros || 0);

  const fmtBucket = (row) => ({
    requests: Number(row?.reqs || 0),
    tokens: Number(row?.toks || 0),
    spentYuan: microsToYuan(row?.spent || 0),
    upstreamYuan: microsToYuan(row?.upstream || 0),
  });

  return json({
    ok: true,
    scope: "wumind_gateway_only",
    scopeNote: "以下统计仅覆盖通过 WUMIND 内置计费网关发起的调用与扣费；用户使用自有 API Key 直连厂商产生的用量由厂商计费，不在此处显示为 0。",
    user: {
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
      refundedYuan: microsToYuan(refundRow?.refunded || 0),
      upstreamSpentYuan: microsToYuan(u.upstream_spent_micros || 0),
      billingExempt: isUserBillingExempt(env, u),
      dailyCostCapYuan: microsToYuan(u.admin_daily_cost_cap_micros || 0) || Number(env.ADMIN_EXEMPT_DAILY_CAP_YUAN || 200),
      requestCount: Number(allTimeRow?.reqs || 0),
      totalTokens: Number(allTimeRow?.toks || 0),
      lastActivityAt: ledgerRows.results?.[0]?.created_at || u.updated_at || u.created_at,
      createdAt: u.created_at,
    },
    usageSummary: {
      today: fmtBucket(todayRow),
      last7Days: fmtBucket(weekRow),
      allTime: fmtBucket(allTimeRow),
    },
    breakdownByModel: (byModelRows.results || []).map((r) => ({
      model: r.model,
      kind: r.kind,
      requests: Number(r.reqs || 0),
      tokens: Number(r.toks || 0),
      spentYuan: microsToYuan(r.spent || 0),
      upstreamYuan: microsToYuan(r.upstream || 0),
    })),
    breakdownByKind: (byKindRows.results || []).map((r) => ({
      kind: r.kind,
      requests: Number(r.reqs || 0),
      spentYuan: microsToYuan(r.spent || 0),
      upstreamYuan: microsToYuan(r.upstream || 0),
    })),
    recentLedger: (ledgerRows.results || []).map((r) => ({
      id: r.id,
      kind: r.kind,
      provider: r.provider || "",
      model: r.model || "",
      promptTokens: Number(r.prompt_tokens || 0),
      completionTokens: Number(r.completion_tokens || 0),
      reasoningTokens: Number(r.reasoning_tokens || 0),
      costYuan: microsToYuan(r.cost_micros || 0),
      upstreamCostYuan: microsToYuan(r.upstream_cost_micros || 0),
      balanceBeforeYuan: r.balance_before_micros !== null && r.balance_before_micros !== undefined ? microsToYuan(r.balance_before_micros) : null,
      balanceAfterYuan: microsToYuan(r.balance_after_micros || 0),
      environment: r.environment || "production",
      operatorID: r.operator_id || null,
      note: r.note || "",
      createdAt: r.created_at,
    })),
    recentAdminCredits: (auditRows.results || []).map((a) => ({
      id: a.id,
      operatorID: a.operator_id,
      targetUserID: a.target_user_id,
      environment: a.environment || "production",
      amountYuan: microsToYuan(a.amount_micros || 0),
      balanceBeforeYuan: microsToYuan(a.balance_before_micros || 0),
      balanceAfterYuan: microsToYuan(a.balance_after_micros || 0),
      note: a.note || "",
      createdAt: a.created_at,
    })),
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
    return json(buildUpstreamBalanceResponse(env, snapshot, alertCfg, true, redactUpstreamDiagnostic(err?.message || err, env.AIHUBMIX_MANAGE_KEY).slice(0, 220)));
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
    return json(buildUpstreamBalanceResponse(env, snapshot, alertCfg, true, redactUpstreamDiagnostic(err?.message || err, env.AIHUBMIX_MANAGE_KEY).slice(0, 220)));
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
// 4. Private Cross-Device "My Works" (我的作品) — Private R2 + D1 Index
// ============================================================================

const VALID_WORK_TYPES = new Set(["image", "video", "ppt", "scene3d", "document", "code"]);
const D1_MAX_PREVIEW_B64 = 175_000;      // ~130 KB preview thumbnail max in D1
const D1_MAX_INLINE_ASSET_B64 = 180_000; // Never stuff > ~135 KB binaries into D1 (2 MB row limit safety!)
const D1_MAX_INLINE_PROJECT_CHARS = 350_000;
const R2_MAX_ASSET_BYTES = 100 * 1024 * 1024; // 100 MB per work binary in private R2

function safeParseJSON(raw, fallback) {
  if (!raw) return fallback;
  try { return JSON.parse(raw); } catch { return fallback; }
}

function decodeBase64ToBytes(b64) {
  const clean = String(b64 || "").replace(/^data:[^;]+;base64,/i, "").replace(/\s+/g, "");
  const bin = atob(clean);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

async function sha256BytesHex(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function extensionForMime(mime) {
  const m = String(mime || "").toLowerCase();
  if (m.includes("png")) return "png";
  if (m.includes("jpeg") || m.includes("jpg")) return "jpg";
  if (m.includes("webp")) return "webp";
  if (m.includes("mp4")) return "mp4";
  if (m.includes("presentationml") || m.includes("pptx")) return "pptx";
  if (m.includes("gltf-binary") || m.includes("glb")) return "glb";
  if (m.includes("usdz")) return "usdz";
  if (m.includes("pdf")) return "pdf";
  if (m.includes("json")) return "json";
  return "bin";
}

export function isWorksObjectStorageConfigured(env) {
  return Boolean(env?.WORKS_BUCKET && typeof env.WORKS_BUCKET.put === "function" && typeof env.WORKS_BUCKET.get === "function");
}

/**
 * Stores a binary work original (or large project JSON) inside private Cloudflare R2 (`env.WORKS_BUCKET`).
 */
export async function storeWorkBinaryInR2(env, { userID, workID, bytes, mimeType = "application/octet-stream", kind = "asset" }) {
  if (!isWorksObjectStorageConfigured(env)) {
    return { configured: false, assetSyncState: "storage_unconfigured" };
  }
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  if (u8.byteLength === 0 || u8.byteLength > R2_MAX_ASSET_BYTES) {
    throw new Error(`作品文件大小超出允许范围（1B ~ ${Math.round(R2_MAX_ASSET_BYTES / (1024 * 1024))}MB）。`);
  }
  const safeKind = kind === "project" ? "project" : "asset";
  const ext = safeKind === "project" ? "json" : extensionForMime(mimeType);
  const objectKey = `works/${userID}/${workID}/${safeKind}.${ext}`;
  const sha256 = await sha256BytesHex(u8);
  await env.WORKS_BUCKET.put(objectKey, u8, {
    httpMetadata: { contentType: mimeType },
    customMetadata: {
      userID: String(userID),
      workID: String(workID),
      kind: safeKind,
      sha256,
    },
  });
  return {
    configured: true,
    objectKey,
    sizeBytes: u8.byteLength,
    sha256,
    mimeType,
    assetSyncState: "synced",
  };
}

function serializeWorkSummary(row, env = null) {
  const hasR2Asset = Boolean(row.asset_object_key);
  const hasInlineAsset = Boolean(row.asset_base64);
  const hasR2Project = Boolean(row.project_object_key);
  const hasInlineProject = Boolean(row.project_json);
  const hasAsset = Boolean(row.has_asset ?? (hasR2Asset || hasInlineAsset));
  const hasProject = Boolean(row.has_project ?? (hasR2Project || hasInlineProject));
  const syncState = row.asset_sync_state || (hasAsset ? "synced" : "local_only");
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
    assetObjectKey: row.asset_object_key || null,
    assetSizeBytes: Number(row.asset_size_bytes || 0),
    assetSHA256: row.asset_sha256 || null,
    assetSyncState: syncState,
    hasAsset,
    hasProject,
    objectStorageConfigured: env ? isWorksObjectStorageConfigured(env) : undefined,
    timing: safeParseJSON(row.timing_json, null),
    versionNumber: Number(row.version_number || 1),
    parentWorkID: row.parent_work_id || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function serializeWorkDetail(row, env = null) {
  return {
    ...serializeWorkSummary(row, env),
    assetBase64: row.asset_base64 || null,
    projectJSON: row.project_json || null,
  };
}

/**
 * Helper used internally by managed image/video routes and work CRUD to persist records in `user_works`.
 * Automatically offloads originals to private R2 (`env.WORKS_BUCKET`) when configured, and NEVER stuffs
 * >180 KB blobs into D1 rows (honestly sets `asset_sync_state = 'storage_unconfigured'` if R2 is unbound).
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
  assetBytes = null,
  projectJSON = null,
  timing = null,
  assetSyncState = null,
}) {
  const safePreview = previewBase64 && previewBase64.length <= D1_MAX_PREVIEW_B64
    ? previewBase64
    : (assetBase64 && assetBase64.length <= D1_MAX_PREVIEW_B64 ? assetBase64 : null);

  let inlineAssetB64 = null;
  let assetObjectKey = null;
  let assetSizeBytes = 0;
  let assetSHA256 = null;
  let resolvedSyncState = assetSyncState || null;

  const hasRawBytes = assetBytes instanceof Uint8Array && assetBytes.byteLength > 0;
  const hasBase64 = typeof assetBase64 === "string" && assetBase64.length > 0;

  if (hasRawBytes || hasBase64) {
    const rawBytes = hasRawBytes ? assetBytes : decodeBase64ToBytes(assetBase64);
    assetSizeBytes = rawBytes.byteLength;
    assetSHA256 = await sha256BytesHex(rawBytes);

    if (isWorksObjectStorageConfigured(env)) {
      const stored = await storeWorkBinaryInR2(env, {
        userID,
        workID: id,
        bytes: rawBytes,
        mimeType: assetMime || "application/octet-stream",
        kind: "asset",
      });
      assetObjectKey = stored.objectKey;
      assetSizeBytes = stored.sizeBytes;
      assetSHA256 = stored.sha256;
      inlineAssetB64 = null; // Keep D1 row lightweight; original lives in private R2
      resolvedSyncState = "synced";
    } else if (hasBase64 && assetBase64.length <= D1_MAX_INLINE_ASSET_B64) {
      // Tiny fallback only (well under D1's 2 MB limit)
      inlineAssetB64 = assetBase64;
      resolvedSyncState = "synced";
    } else {
      // Never stuff large blobs into D1 and never falsely mark as synced!
      inlineAssetB64 = null;
      resolvedSyncState = "storage_unconfigured";
    }
  }

  let inlineProjectJSON = null;
  let projectObjectKey = null;
  let projectSizeBytes = 0;
  if (typeof projectJSON === "string" && projectJSON.length > 0) {
    const projBytes = new TextEncoder().encode(projectJSON);
    projectSizeBytes = projBytes.byteLength;
    if (projectJSON.length <= D1_MAX_INLINE_PROJECT_CHARS) {
      inlineProjectJSON = projectJSON;
      if (!resolvedSyncState && !hasRawBytes && !hasBase64) resolvedSyncState = "synced";
    } else if (isWorksObjectStorageConfigured(env)) {
      const storedProj = await storeWorkBinaryInR2(env, {
        userID,
        workID: id,
        bytes: projBytes,
        mimeType: "application/json",
        kind: "project",
      });
      projectObjectKey = storedProj.objectKey;
      projectSizeBytes = storedProj.sizeBytes;
      inlineProjectJSON = null;
      if (!resolvedSyncState) resolvedSyncState = "synced";
    } else {
      inlineProjectJSON = null;
      if (!resolvedSyncState) resolvedSyncState = "storage_unconfigured";
    }
  }

  const finalSyncState = resolvedSyncState || (status === "completed" ? "local_only" : "local_only");

  await env.DB.prepare(
    `INSERT INTO user_works
     (id, user_id, work_type, title, prompt, model_id, params_json, reference_assets_json, status, progress,
      upstream_job_id, idempotency_key, error_message, preview_base64, asset_mime, asset_base64,
      asset_object_key, asset_size_bytes, asset_sha256, asset_sync_state,
      project_json, project_object_key, project_size_bytes, timing_json, version_number, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, datetime('now'))
     ON CONFLICT(id) DO UPDATE SET
       status = excluded.status,
       progress = excluded.progress,
       upstream_job_id = COALESCE(excluded.upstream_job_id, user_works.upstream_job_id),
       error_message = excluded.error_message,
       preview_base64 = COALESCE(excluded.preview_base64, user_works.preview_base64),
       asset_mime = COALESCE(excluded.asset_mime, user_works.asset_mime),
       asset_base64 = CASE WHEN excluded.asset_object_key IS NOT NULL THEN NULL ELSE COALESCE(excluded.asset_base64, user_works.asset_base64) END,
       asset_object_key = COALESCE(excluded.asset_object_key, user_works.asset_object_key),
       asset_size_bytes = CASE WHEN excluded.asset_size_bytes > 0 THEN excluded.asset_size_bytes ELSE user_works.asset_size_bytes END,
       asset_sha256 = COALESCE(excluded.asset_sha256, user_works.asset_sha256),
       asset_sync_state = CASE
         WHEN excluded.asset_object_key IS NOT NULL THEN 'synced'
         WHEN excluded.asset_sync_state IS NOT NULL AND excluded.asset_sync_state != 'local_only' THEN excluded.asset_sync_state
         ELSE user_works.asset_sync_state
       END,
       project_json = CASE WHEN excluded.project_object_key IS NOT NULL THEN NULL ELSE COALESCE(excluded.project_json, user_works.project_json) END,
       project_object_key = COALESCE(excluded.project_object_key, user_works.project_object_key),
       project_size_bytes = CASE WHEN excluded.project_size_bytes > 0 THEN excluded.project_size_bytes ELSE user_works.project_size_bytes END,
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
    inlineAssetB64,
    assetObjectKey,
    assetSizeBytes,
    assetSHA256,
    finalSyncState,
    inlineProjectJSON,
    projectObjectKey,
    projectSizeBytes,
    timing ? JSON.stringify(timing) : null
  ).run();
}

export async function handleListUserWorks(request, env, { json, authenticateUser }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权，请先登录或注册 WUMIND 账号。" }, 401);

  const url = new URL(request.url);
  const typeFilter = String(url.searchParams.get("type") || "").trim().toLowerCase();
  const limit = Math.max(1, Math.min(100, parseInt(url.searchParams.get("limit") || "60", 10) || 60));
  const offset = Math.max(0, parseInt(url.searchParams.get("offset") || "0", 10) || 0);
  const useType = VALID_WORK_TYPES.has(typeFilter);

  const selectCols = `id, user_id, work_type, title, prompt, model_id, params_json, reference_assets_json, status, progress,
              upstream_job_id, idempotency_key, error_message, preview_base64, asset_mime,
              asset_object_key, asset_size_bytes, asset_sha256, asset_sync_state, project_object_key, project_size_bytes,
              CASE WHEN (asset_object_key IS NOT NULL AND length(asset_object_key) > 0) OR (asset_base64 IS NOT NULL AND length(asset_base64) > 0) THEN 1 ELSE 0 END AS has_asset,
              CASE WHEN (project_object_key IS NOT NULL AND length(project_object_key) > 0) OR (project_json IS NOT NULL AND length(project_json) > 0) THEN 1 ELSE 0 END AS has_project,
              timing_json, version_number, parent_work_id, created_at, updated_at`;

  const countRow = useType
    ? await env.DB.prepare("SELECT COUNT(*) AS cnt FROM user_works WHERE user_id = ? AND work_type = ?").bind(user.id, typeFilter).first()
    : await env.DB.prepare("SELECT COUNT(*) AS cnt FROM user_works WHERE user_id = ?").bind(user.id).first();
  const total = Number(countRow?.cnt || 0);

  const sql = useType
    ? `SELECT ${selectCols} FROM user_works WHERE user_id = ? AND work_type = ? ORDER BY updated_at DESC, id DESC LIMIT ? OFFSET ?`
    : `SELECT ${selectCols} FROM user_works WHERE user_id = ? ORDER BY updated_at DESC, id DESC LIMIT ? OFFSET ?`;

  const rows = useType
    ? await env.DB.prepare(sql).bind(user.id, typeFilter, limit, offset).all()
    : await env.DB.prepare(sql).bind(user.id, limit, offset).all();

  const items = (rows.results || []).map((r) => serializeWorkSummary(r, env));
  const nextOffset = offset + items.length < total ? offset + items.length : null;

  return json({
    ok: true,
    userID: user.id,
    objectStorageConfigured: isWorksObjectStorageConfigured(env),
    total,
    offset,
    limit,
    hasMore: nextOffset !== null,
    nextOffset,
    works: items,
  });
}

export async function handleCreateUserWork(request, env, { json, authenticateUser, randomCode }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);

  let body;
  try { body = await request.json(); } catch { return json({ error: "请求 JSON 格式错误。" }, 400); }

  const workType = String(body.workType || "").trim().toLowerCase();
  if (!VALID_WORK_TYPES.has(workType)) {
    return json({ error: "不支持的作品类型（需为 image / video / ppt / scene3d / document / code）。" }, 400);
  }

  const idem = body.idempotencyKey ? String(body.idempotencyKey).trim().slice(0, 96) : null;
  if (idem) {
    const existing = await env.DB.prepare(
      "SELECT * FROM user_works WHERE user_id = ? AND idempotency_key = ?"
    ).bind(user.id, idem).first();
    if (existing) {
      return json({ ok: true, idempotentReplay: true, work: serializeWorkDetail(existing, env) });
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
    assetSyncState: typeof body.assetSyncState === "string" ? body.assetSyncState : null,
  });

  const saved = await env.DB.prepare("SELECT * FROM user_works WHERE id = ? AND user_id = ?").bind(id, user.id).first();
  return json({ ok: true, work: serializeWorkDetail(saved, env) });
}

export async function handleGetUserWork(request, env, workID, { json, authenticateUser }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  const row = await env.DB.prepare(
    "SELECT * FROM user_works WHERE id = ? AND user_id = ?"
  ).bind(workID, user.id).first();
  if (!row) return json({ error: "未找到该作品或无权查看。", code: "work_not_found" }, 404);
  const detail = serializeWorkDetail(row, env);
  // If large projectJSON lives in private R2, hydrate it transparently on detail read
  if (!detail.projectJSON && row.project_object_key && isWorksObjectStorageConfigured(env)) {
    const obj = await env.WORKS_BUCKET.get(row.project_object_key);
    if (obj) {
      detail.projectJSON = await obj.text();
    }
  }
  return json({ ok: true, work: detail });
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
  // NEVER inherits parent asset_object_key / asset_base64 onto the new version:
  // until the new version's own file finishes uploading, asset_sync_state stays 'pending_upload' (待同步).
  if (body.createNewVersion) {
    const rootID = existing.parent_work_id || existing.id;
    const requestedVersionID = typeof (body.versionWorkID || body.targetVersionID) === "string"
      ? String(body.versionWorkID || body.targetVersionID).trim()
      : "";
    const fixedVersionID = /^[A-Za-z0-9_-]{6,64}$/.test(requestedVersionID) ? requestedVersionID : null;
    const versionIdem = typeof body.idempotencyKey === "string" && body.idempotencyKey.trim()
      ? body.idempotencyKey.trim().slice(0, 96)
      : null;

    // Idempotent resume check: if a previous v2 creation/upload was interrupted, reuse THAT EXACT v2 row!
    let existingVersion = null;
    if (fixedVersionID) {
      const collision = await env.DB.prepare("SELECT * FROM user_works WHERE id = ?").bind(fixedVersionID).first();
      if (collision) {
        if (collision.user_id !== user.id) {
          return json({ error: "无权访问或覆盖该版本编号。", code: "work_forbidden" }, 403);
        }
        existingVersion = collision;
      }
    }
    if (!existingVersion && versionIdem) {
      existingVersion = await env.DB.prepare(
        "SELECT * FROM user_works WHERE user_id = ? AND idempotency_key = ?"
      ).bind(user.id, versionIdem).first();
    }

    const newID = existingVersion ? existingVersion.id : (fixedVersionID || `WRK-${randomCode(12)}`);
    let nextVer = existingVersion ? Number(existingVersion.version_number || 2) : 2;
    if (!existingVersion) {
      const maxVerRow = await env.DB.prepare(
        "SELECT COALESCE(MAX(version_number), 1) AS max_ver FROM user_works WHERE user_id = ? AND (id = ? OR parent_work_id = ?)"
      ).bind(user.id, rootID, rootID).first();
      nextVer = Number(maxVerRow?.max_ver || existing.version_number || 1) + 1;
    }

    const rawProject = body.projectJSON !== undefined
      ? (typeof body.projectJSON === "string" ? body.projectJSON : JSON.stringify(body.projectJSON))
      : (existingVersion?.project_json ?? existing.project_json);
    const rawPreview = body.previewBase64 !== undefined ? body.previewBase64 : (existingVersion?.preview_base64 ?? null);
    const safePreview = rawPreview && rawPreview.length <= D1_MAX_PREVIEW_B64 ? rawPreview : (existingVersion?.preview_base64 ?? null);

    let nextInlineProject = null;
    let nextProjectKey = existingVersion?.project_object_key || null;
    let nextProjectSize = Number(existingVersion?.project_size_bytes || 0);
    if (body.pendingProjectUpload) {
      nextInlineProject = null;
      nextProjectKey = existingVersion?.project_object_key || null;
    } else if (typeof rawProject === "string" && rawProject.length > 0) {
      const pBytes = new TextEncoder().encode(rawProject);
      nextProjectSize = pBytes.byteLength;
      if (rawProject.length <= D1_MAX_INLINE_PROJECT_CHARS) {
        nextInlineProject = rawProject;
        nextProjectKey = null;
      } else if (isWorksObjectStorageConfigured(env)) {
        const stored = await storeWorkBinaryInR2(env, {
          userID: user.id,
          workID: newID,
          bytes: pBytes,
          mimeType: "application/json",
          kind: "project",
        });
        nextProjectKey = stored.objectKey;
        nextProjectSize = stored.sizeBytes;
      }
    }

    // Critical safety invariant: NEVER point a new version at the parent's R2 key or base64!
    let nextInlineAsset = existingVersion ? (existingVersion.asset_base64 || null) : null;
    let nextAssetKey = existingVersion ? (existingVersion.asset_object_key || null) : null;
    let nextAssetSize = existingVersion ? Number(existingVersion.asset_size_bytes || 0) : 0;
    let nextAssetSHA = existingVersion ? (existingVersion.asset_sha256 || null) : null;
    let nextSyncState = (nextAssetKey || nextInlineAsset)
      ? "synced"
      : (body.pendingAssetUpload || body.pendingProjectUpload || existing.asset_object_key || existing.asset_base64
          ? "pending_upload"
          : (nextInlineProject || nextProjectKey ? "synced" : "pending_upload"));

    if (typeof body.assetBase64 === "string" && body.assetBase64.length > 0) {
      const rawBytes = decodeBase64ToBytes(body.assetBase64);
      nextAssetSize = rawBytes.byteLength;
      nextAssetSHA = await sha256BytesHex(rawBytes);
      if (isWorksObjectStorageConfigured(env)) {
        const stored = await storeWorkBinaryInR2(env, {
          userID: user.id,
          workID: newID,
          bytes: rawBytes,
          mimeType: body.assetMime ?? existing.asset_mime ?? "application/octet-stream",
          kind: "asset",
        });
        nextAssetKey = stored.objectKey;
        nextInlineAsset = null;
        nextSyncState = "synced";
      } else if (body.assetBase64.length <= D1_MAX_INLINE_ASSET_B64) {
        nextInlineAsset = body.assetBase64;
        nextAssetKey = null;
        nextSyncState = "synced";
      } else {
        nextInlineAsset = null;
        nextAssetKey = null;
        nextSyncState = "storage_unconfigured";
      }
    }

    if (existingVersion) {
      await env.DB.prepare(
        `UPDATE user_works
         SET title = ?, prompt = ?, model_id = ?, params_json = ?, status = ?, progress = ?,
             error_message = ?, preview_base64 = ?, asset_mime = ?, asset_base64 = ?,
             asset_object_key = ?, asset_size_bytes = ?, asset_sha256 = ?, asset_sync_state = ?,
             project_json = ?, project_object_key = ?, project_size_bytes = ?, timing_json = ?,
             updated_at = datetime('now')
         WHERE id = ? AND user_id = ?`
      ).bind(
        String(body.title ?? existingVersion.title).slice(0, 120),
        String(body.prompt ?? existingVersion.prompt).slice(0, 8000),
        String(body.modelID ?? existingVersion.model_id).slice(0, 96),
        body.params ? JSON.stringify(body.params) : existingVersion.params_json,
        String(body.status ?? existingVersion.status),
        body.progress !== undefined ? Math.max(0, Math.min(100, Math.round(Number(body.progress)))) : existingVersion.progress,
        body.errorMessage !== undefined ? body.errorMessage : existingVersion.error_message,
        safePreview,
        body.assetMime ?? existingVersion.asset_mime ?? existing.asset_mime,
        nextInlineAsset,
        nextAssetKey,
        nextAssetSize,
        nextAssetSHA,
        nextSyncState,
        nextInlineProject,
        nextProjectKey,
        nextProjectSize,
        body.timing ? JSON.stringify(body.timing) : existingVersion.timing_json,
        newID,
        user.id
      ).run();
      const resumed = await env.DB.prepare("SELECT * FROM user_works WHERE id = ? AND user_id = ?").bind(newID, user.id).first();
      return json({ ok: true, versionCreated: false, idempotentReplay: true, work: serializeWorkDetail(resumed, env) });
    }

    await env.DB.prepare(
      `INSERT INTO user_works
       (id, user_id, work_type, title, prompt, model_id, params_json, reference_assets_json, status, progress,
        upstream_job_id, idempotency_key, error_message, preview_base64, asset_mime, asset_base64,
        asset_object_key, asset_size_bytes, asset_sha256, asset_sync_state,
        project_json, project_object_key, project_size_bytes, timing_json,
        version_number, parent_work_id, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))`
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
      versionIdem,
      body.errorMessage !== undefined ? body.errorMessage : existing.error_message,
      safePreview,
      body.assetMime ?? existing.asset_mime,
      nextInlineAsset,
      nextAssetKey,
      nextAssetSize,
      nextAssetSHA,
      nextSyncState,
      nextInlineProject,
      nextProjectKey,
      nextProjectSize,
      body.timing ? JSON.stringify(body.timing) : existing.timing_json,
      nextVer,
      rootID
    ).run();

    const created = await env.DB.prepare("SELECT * FROM user_works WHERE id = ?").bind(newID).first();
    return json({ ok: true, versionCreated: true, work: serializeWorkDetail(created, env) });
  }

  // In-place status/progress/asset update
  const nextTitle = body.title !== undefined ? String(body.title).slice(0, 120) : existing.title;
  const nextStatus = body.status !== undefined ? String(body.status) : existing.status;
  const nextProgress = body.progress !== undefined ? Math.max(0, Math.min(100, Math.round(Number(body.progress)))) : existing.progress;
  const nextError = body.errorMessage !== undefined ? (body.errorMessage ? String(body.errorMessage).slice(0, 500) : null) : existing.error_message;
  const rawPreview = body.previewBase64 !== undefined ? body.previewBase64 : existing.preview_base64;
  const nextPreview = rawPreview && rawPreview.length <= D1_MAX_PREVIEW_B64 ? rawPreview : existing.preview_base64;
  const nextAssetMime = body.assetMime !== undefined ? body.assetMime : existing.asset_mime;
  const nextTiming = body.timing !== undefined ? JSON.stringify(body.timing) : existing.timing_json;

  let nextInlineAsset = existing.asset_base64;
  let nextAssetKey = existing.asset_object_key || null;
  let nextAssetSize = Number(existing.asset_size_bytes || 0);
  let nextAssetSHA = existing.asset_sha256 || null;
  let nextSyncState = body.assetSyncState || existing.asset_sync_state || "local_only";

  if (typeof body.assetBase64 === "string" && body.assetBase64.length > 0) {
    const rawBytes = decodeBase64ToBytes(body.assetBase64);
    nextAssetSize = rawBytes.byteLength;
    nextAssetSHA = await sha256BytesHex(rawBytes);
    if (isWorksObjectStorageConfigured(env)) {
      const stored = await storeWorkBinaryInR2(env, {
        userID: user.id,
        workID,
        bytes: rawBytes,
        mimeType: nextAssetMime || "application/octet-stream",
        kind: "asset",
      });
      nextAssetKey = stored.objectKey;
      nextInlineAsset = null;
      nextSyncState = "synced";
    } else if (body.assetBase64.length <= D1_MAX_INLINE_ASSET_B64) {
      nextInlineAsset = body.assetBase64;
      nextSyncState = "synced";
    } else {
      nextInlineAsset = null;
      nextSyncState = "storage_unconfigured";
    }
  }

  let nextInlineProject = existing.project_json;
  let nextProjectKey = existing.project_object_key || null;
  let nextProjectSize = Number(existing.project_size_bytes || 0);
  if (body.projectJSON !== undefined) {
    const projStr = typeof body.projectJSON === "string" ? body.projectJSON : JSON.stringify(body.projectJSON);
    const pBytes = new TextEncoder().encode(projStr);
    nextProjectSize = pBytes.byteLength;
    if (projStr.length <= D1_MAX_INLINE_PROJECT_CHARS) {
      nextInlineProject = projStr;
      nextProjectKey = null;
    } else if (isWorksObjectStorageConfigured(env)) {
      const stored = await storeWorkBinaryInR2(env, {
        userID: user.id,
        workID,
        bytes: pBytes,
        mimeType: "application/json",
        kind: "project",
      });
      nextProjectKey = stored.objectKey;
      nextInlineProject = null;
    } else {
      nextInlineProject = null;
      nextSyncState = "storage_unconfigured";
    }
  }

  await env.DB.prepare(
    `UPDATE user_works
     SET title = ?, status = ?, progress = ?, error_message = ?, preview_base64 = ?,
         asset_mime = ?, asset_base64 = ?, asset_object_key = ?, asset_size_bytes = ?, asset_sha256 = ?, asset_sync_state = ?,
         project_json = ?, project_object_key = ?, project_size_bytes = ?, timing_json = ?, updated_at = datetime('now')
     WHERE id = ? AND user_id = ?`
  ).bind(
    nextTitle,
    nextStatus,
    nextProgress,
    nextError,
    nextPreview,
    nextAssetMime,
    nextInlineAsset,
    nextAssetKey,
    nextAssetSize,
    nextAssetSHA,
    nextSyncState,
    nextInlineProject,
    nextProjectKey,
    nextProjectSize,
    nextTiming,
    workID,
    user.id
  ).run();

  const fresh = await env.DB.prepare("SELECT * FROM user_works WHERE id = ? AND user_id = ?").bind(workID, user.id).first();
  return json({ ok: true, work: serializeWorkDetail(fresh, env) });
}

/**
 * PUT /v1/works/:id/asset[?kind=asset|project]
 * Owner-only raw binary upload straight into private Cloudflare R2 (`env.WORKS_BUCKET`).
 * Returns HTTP 503 `object_storage_unconfigured` if R2 is not bound — NEVER pretends synced!
 */
export async function handlePutUserWorkAsset(request, env, workID, { json, authenticateUser }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);

  const row = await env.DB.prepare(
    "SELECT id, user_id, work_type FROM user_works WHERE id = ? AND user_id = ?"
  ).bind(workID, user.id).first();
  if (!row) return json({ error: "未找到该作品或无权上传。", code: "work_not_found" }, 404);

  const url = new URL(request.url);
  const kind = String(url.searchParams.get("kind") || "asset").toLowerCase() === "project" ? "project" : "asset";

  if (!isWorksObjectStorageConfigured(env)) {
    await env.DB.prepare(
      "UPDATE user_works SET asset_sync_state = 'storage_unconfigured', updated_at = datetime('now') WHERE id = ? AND user_id = ?"
    ).bind(workID, user.id).run();
    return json({
      error: "云端原文件对象存储（Cloudflare R2 WORKS_BUCKET）尚未配置，原文件当前仅保存在本机。",
      code: "object_storage_unconfigured",
      assetSyncState: "storage_unconfigured",
    }, 503);
  }

  const mime = (request.headers.get("Content-Type") || (kind === "project" ? "application/json" : "application/octet-stream"))
    .split(";")[0]
    .trim();
  const buf = await request.arrayBuffer();
  const bytes = new Uint8Array(buf);
  if (bytes.byteLength === 0) {
    return json({ error: "上传的文件内容为空。", code: "empty_asset" }, 400);
  }
  if (bytes.byteLength > R2_MAX_ASSET_BYTES) {
    return json({ error: "单个作品原文件不能超过 100 MB。", code: "asset_too_large", maxBytes: R2_MAX_ASSET_BYTES }, 413);
  }

  const stored = await storeWorkBinaryInR2(env, {
    userID: user.id,
    workID,
    bytes,
    mimeType: mime,
    kind,
  });

  if (kind === "project") {
    await env.DB.prepare(
      `UPDATE user_works
       SET project_object_key = ?, project_size_bytes = ?, project_json = NULL,
           asset_sync_state = CASE WHEN asset_sync_state = 'storage_unconfigured' THEN 'synced' ELSE asset_sync_state END,
           updated_at = datetime('now')
       WHERE id = ? AND user_id = ?`
    ).bind(stored.objectKey, stored.sizeBytes, workID, user.id).run();
  } else {
    await env.DB.prepare(
      `UPDATE user_works
       SET asset_object_key = ?, asset_mime = ?, asset_size_bytes = ?, asset_sha256 = ?,
           asset_base64 = NULL, asset_sync_state = 'synced', updated_at = datetime('now')
       WHERE id = ? AND user_id = ?`
    ).bind(stored.objectKey, mime, stored.sizeBytes, stored.sha256, workID, user.id).run();
  }

  return json({
    ok: true,
    workID,
    kind,
    objectKey: stored.objectKey,
    sizeBytes: stored.sizeBytes,
    sha256: stored.sha256,
    mimeType: mime,
    assetSyncState: "synced",
  });
}

/**
 * GET /v1/works/:id/asset[?kind=asset|project]
 * Owner-only raw binary stream directly from private R2 (or legacy inline small fallback).
 */
export async function handleGetUserWorkAsset(request, env, workID, { json, authenticateUser }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  const url = new URL(request.url);
  const kind = String(url.searchParams.get("kind") || "asset").toLowerCase() === "project" ? "project" : "asset";

  const row = await env.DB.prepare(
    "SELECT id, work_type, asset_mime, asset_base64, asset_object_key, asset_size_bytes, asset_sha256, asset_sync_state, project_json, project_object_key FROM user_works WHERE id = ? AND user_id = ?"
  ).bind(workID, user.id).first();
  if (!row) return json({ error: "未找到该作品或无权下载。", code: "work_not_found" }, 404);

  if (kind === "project") {
    if (row.project_object_key) {
      if (!isWorksObjectStorageConfigured(env)) {
        return json({ error: "云端对象存储（R2）当前不可用。", code: "object_storage_unconfigured" }, 503);
      }
      const obj = await env.WORKS_BUCKET.get(row.project_object_key);
      if (!obj) return json({ error: "云端工程文件不存在或已被清理。", code: "asset_missing" }, 404);
      const body = obj.body ?? (await obj.arrayBuffer());
      return new Response(body, {
        status: 200,
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Cache-Control": "private, max-age=3600",
        },
      });
    }
    if (row.project_json) {
      return new Response(row.project_json, {
        status: 200,
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Cache-Control": "private, max-age=3600",
        },
      });
    }
    if (row.asset_sync_state === "pending_upload") {
      return json({
        error: "该版本工程文件尚未上传完成（待同步），请等待上传完成或恢复上传。",
        code: "asset_pending_sync",
        assetSyncState: "pending_upload",
      }, 409);
    }
    return json({ error: "该作品暂无可下载的可编辑工程文件。", code: "asset_missing" }, 404);
  }

  if (row.asset_object_key) {
    if (!isWorksObjectStorageConfigured(env)) {
      return json({ error: "云端原文件对象存储（R2）未配置，暂无法读取云端原文件。", code: "object_storage_unconfigured" }, 503);
    }
    const obj = await env.WORKS_BUCKET.get(row.asset_object_key);
    if (!obj) return json({ error: "云端原文件不存在或已被清理。", code: "asset_missing" }, 404);
    const mime = row.asset_mime || obj.httpMetadata?.contentType || "application/octet-stream";
    const body = obj.body ?? (await obj.arrayBuffer());
    const headers = {
      "Content-Type": mime,
      "Cache-Control": "private, max-age=3600",
    };
    if (row.asset_size_bytes > 0) headers["Content-Length"] = String(row.asset_size_bytes);
    if (row.asset_sha256) headers["X-Asset-SHA256"] = row.asset_sha256;
    return new Response(body, { status: 200, headers });
  }

  if (!row.asset_base64) {
    if (row.asset_sync_state === "pending_upload") {
      return json({
        error: "该版本原文件尚未上传完成（待同步），请等待上传完成或使用原版本编号恢复上传。",
        code: "asset_pending_sync",
        assetSyncState: "pending_upload",
      }, 409);
    }
    return json({ error: "该作品暂无已同步的云端原文件。", code: "asset_missing" }, 404);
  }
  const bytes = decodeBase64ToBytes(row.asset_base64);
  const mime = row.asset_mime || "application/octet-stream";
  return new Response(bytes, {
    status: 200,
    headers: {
      "Content-Type": mime,
      "Content-Length": String(bytes.byteLength),
      "Cache-Control": "private, max-age=3600",
    },
  });
}

export async function handleDeleteUserWork(request, env, workID, { json, authenticateUser }) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  const existing = await env.DB.prepare(
    "SELECT id, asset_object_key, project_object_key FROM user_works WHERE id = ? AND user_id = ?"
  ).bind(workID, user.id).first();
  if (!existing) {
    return json({ error: "未找到该作品或无权删除。" }, 404);
  }
  const res = await env.DB.prepare(
    "DELETE FROM user_works WHERE id = ? AND user_id = ?"
  ).bind(workID, user.id).run();
  if ((res.meta?.changes || 0) === 0) {
    return json({ error: "未找到该作品或无权删除。" }, 404);
  }
  const deletedKeys = [];
  const retainedSharedKeys = [];
  if (isWorksObjectStorageConfigured(env) && typeof env.WORKS_BUCKET.delete === "function") {
    const keys = [...new Set([existing.asset_object_key, existing.project_object_key].filter(Boolean))];
    for (const k of keys) {
      // Reference-count check: NEVER delete an R2 object if any other version/work still references it!
      const refRow = await env.DB.prepare(
        "SELECT COUNT(*) AS cnt FROM user_works WHERE id != ? AND (asset_object_key = ? OR project_object_key = ?)"
      ).bind(workID, k, k).first();
      if (Number(refRow?.cnt || 0) > 0) {
        retainedSharedKeys.push(k);
        continue;
      }
      try {
        await env.WORKS_BUCKET.delete(k);
        deletedKeys.push(k);
      } catch {}
    }
  }
  return json({ ok: true, deletedID: workID, deletedKeys, retainedSharedKeys });
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
      error: `实时语音上游握手失败（HTTP ${upstreamResp.status}）：${redactUpstreamDiagnostic(rawErr, upstreamKey).slice(0, 220)}`,
      code: `realtime_upstream_${upstreamResp.status}`,
    }, 502);
  }

  const upstreamWS = upstreamResp.webSocket;
  upstreamWS.accept();

  const pair = new WebSocketPair();
  const [clientWS, serverWS] = Object.values(pair);
  serverWS.accept();

  let ended = false;
  function closeSession(code = 1011, reason = "realtime_disconnected") {
    if (ended) return;
    ended = true;
    // Peer close reasons can be non-transferable (e.g. 1006), oversized or provider-specific.
    for (const socket of [serverWS, upstreamWS]) {
      try { socket.close(code, reason); } catch {}
    }
  }

  serverWS.addEventListener("message", (evt) => {
    if (ended) return;
    try { upstreamWS.send(evt.data); } catch { closeSession(); }
  });
  serverWS.addEventListener("close", () => closeSession(1000, "client_closed"));
  serverWS.addEventListener("error", () => closeSession());
  upstreamWS.addEventListener("error", () => closeSession());

  upstreamWS.addEventListener("message", async (evt) => {
    try {
      const data = typeof evt.data === "string" && evt.data.includes(upstreamKey)
        ? evt.data.replaceAll(upstreamKey, "[redacted]") : evt.data;
      if (!ended) serverWS.send(data);
    } catch { closeSession(); }
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
    closeSession(evt.code === 1000 ? 1000 : 1011, "upstream_closed");
  });

  return new Response(null, { status: 101, webSocket: clientWS });
}
