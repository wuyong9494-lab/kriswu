/**
 * WUMIND Real-Time Token Billing & Multi-Provider AI Gateway (Cloudflare Workers + D1)
 *
 * Security model:
 * - Upstream provider keys (DEEPSEEK_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY, CLAUDE_API_KEY, GROK_API_KEY)
 *   live strictly in Cloudflare Worker Secrets and NEVER leave the server.
 * - End users authenticate with an opaque device bearer token (`wm_live_...`), stored as SHA-256 in D1.
 * - Admin routes require `X-WuMind-Admin-Secret` checked via constant-time digest comparison.
 * - Every chat completion verifies balance > 0 up front, streams live reasoning + answer deltas,
 *   captures real upstream token usage (`prompt_tokens`, `completion_tokens`, `reasoning_tokens`),
 *   computes exact custom-markup cost from Admin's live pricing table, atomically deducts D1 balance,
 *   writes an audit ledger row, and emits a final `wumind_billing` SSE receipt frame.
 */

const MICROS_PER_YUAN = 1_000_000;

const DEFAULT_PRICING = [
  {
    id: "deepseek-reasoner",
    provider: "deepSeek",
    displayName: "DeepSeek V4 Pro（深度思考）",
    inputPricePerMillion: 5.0,
    outputPricePerMillion: 20.0,
    officialReferenceNote: "官方参考约 ¥2 / ¥8",
    supportsThinking: true,
    enabled: true,
  },
  {
    id: "deepseek-chat",
    provider: "deepSeek",
    displayName: "DeepSeek Flash（极速）",
    inputPricePerMillion: 2.5,
    outputPricePerMillion: 8.0,
    officialReferenceNote: "官方参考约 ¥1 / ¥4",
    supportsThinking: false,
    enabled: true,
  },
  {
    id: "gpt-4o",
    provider: "openAI",
    displayName: "OpenAI GPT-4o",
    inputPricePerMillion: 36.0,
    outputPricePerMillion: 144.0,
    officialReferenceNote: "官方参考约 ¥18 / ¥72",
    supportsThinking: false,
    enabled: true,
  },
  {
    id: "gemini-2.5-pro",
    provider: "gemini",
    displayName: "Google Gemini 2.5 Pro",
    inputPricePerMillion: 18.0,
    outputPricePerMillion: 120.0,
    officialReferenceNote: "官方参考约 ¥9 / ¥72",
    supportsThinking: true,
    enabled: true,
  },
  {
    id: "claude-sonnet-4-20250514",
    provider: "claude",
    displayName: "Anthropic Claude Sonnet 4",
    inputPricePerMillion: 42.0,
    outputPricePerMillion: 210.0,
    officialReferenceNote: "官方参考约 ¥22 / ¥108",
    supportsThinking: true,
    enabled: true,
  },
  {
    id: "grok-3",
    provider: "grok",
    displayName: "xAI Grok 3",
    inputPricePerMillion: 40.0,
    outputPricePerMillion: 180.0,
    officialReferenceNote: "官方参考约 ¥22 / ¥108",
    supportsThinking: false,
    enabled: true,
  },
];

const DEFAULT_IAP_PACKS = [
  { id: "com.kriswu.wumind.credit.6", title: "轻量流量包", creditYuan: 6.0, fallbackPriceLabel: "¥6", badge: null },
  { id: "com.kriswu.wumind.credit.18", title: "常用流量包", creditYuan: 18.0, fallbackPriceLabel: "¥18", badge: "推荐" },
  { id: "com.kriswu.wumind.credit.68", title: "深度研发包", creditYuan: 68.0, fallbackPriceLabel: "¥68", badge: "划算" },
  { id: "com.kriswu.wumind.credit.198", title: "重度旗舰包", creditYuan: 198.0, fallbackPriceLabel: "¥198", badge: "超值" },
];

const DEFAULT_COMMERCIAL_CONFIG = {
  pricing: DEFAULT_PRICING,
  wechatQRBase64: null,
  alipayQRBase64: null,
  rechargeNote: "扫码转账时请备注你的 WUMIND 账号 ID（如 WM-849201），付款后联系管理员秒发兑换码或直接入账。",
  contactNote: "",
  announcement: "WUMIND 内置旗舰通道按真实 Token 实时计费，余额永久有效。",
  webSearchCostYuan: 0.03,
  billingMode: "hybrid",
  iapPacks: DEFAULT_IAP_PACKS,
  paymentWebhookNote: "支持支付宝/微信第三方回调 HMAC-SHA256 签名自动入账，或启用 Apple StoreKit 2 应用内购实时到账。",
};

function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...extraHeaders,
    },
  });
}

async function sha256Hex(text) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function hmacSha256Hex(secret, payloadText) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payloadText));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function constantTimeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length || a.length === 0) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function verifyAdminSecret(request, env) {
  const expected = (env.ADMIN_SECRET || "").trim();
  const provided = (request.headers.get("X-WuMind-Admin-Secret") || "").trim();
  if (!expected || !provided) return false;
  const [h1, h2] = await Promise.all([sha256Hex(expected), sha256Hex(provided)]);
  return constantTimeEqual(h1, h2);
}

function randomCode(len, alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789") {
  const bytes = new Uint8Array(len);
  crypto.getRandomValues(bytes);
  let out = "";
  for (let i = 0; i < len; i++) out += alphabet[bytes[i] % alphabet.length];
  return out;
}

function microsToYuan(micros) {
  return Math.round((Number(micros || 0) / MICROS_PER_YUAN) * 10000) / 10000;
}

function yuanToMicros(yuan) {
  const n = Number(yuan);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.round(n * MICROS_PER_YUAN);
}

async function loadCommercialConfig(env) {
  const row = await env.DB.prepare("SELECT value FROM config WHERE key = 'commercial_config'").first();
  if (!row || !row.value) return { ...DEFAULT_COMMERCIAL_CONFIG };
  try {
    const parsed = JSON.parse(row.value);
    return {
      pricing: Array.isArray(parsed.pricing) && parsed.pricing.length ? parsed.pricing : DEFAULT_PRICING,
      wechatQRBase64: parsed.wechatQRBase64 || null,
      alipayQRBase64: parsed.alipayQRBase64 || null,
      rechargeNote: typeof parsed.rechargeNote === "string" ? parsed.rechargeNote : DEFAULT_COMMERCIAL_CONFIG.rechargeNote,
      contactNote: typeof parsed.contactNote === "string" ? parsed.contactNote : "",
      announcement: typeof parsed.announcement === "string" ? parsed.announcement : "",
      webSearchCostYuan: typeof parsed.webSearchCostYuan === "number" && parsed.webSearchCostYuan >= 0 ? parsed.webSearchCostYuan : 0.03,
      billingMode: ["hybrid", "app_store_iap", "direct_qr"].includes(parsed.billingMode) ? parsed.billingMode : "hybrid",
      iapPacks: Array.isArray(parsed.iapPacks) && parsed.iapPacks.length ? parsed.iapPacks : DEFAULT_IAP_PACKS,
      paymentWebhookNote: typeof parsed.paymentWebhookNote === "string" ? parsed.paymentWebhookNote : DEFAULT_COMMERCIAL_CONFIG.paymentWebhookNote,
    };
  } catch {
    return { ...DEFAULT_COMMERCIAL_CONFIG };
  }
}

async function authenticateUser(request, env) {
  const auth = request.headers.get("Authorization") || "";
  const match = auth.match(/^Bearer\s+(.+)$/i);
  if (!match) return null;
  const token = match[1].trim();
  if (!token || token.length > 256) return null;
  const tokenHash = await sha256Hex(token);
  const primary = await env.DB.prepare("SELECT * FROM users WHERE token_hash = ?").bind(tokenHash).first();
  if (primary) return primary;
  const linked = await env.DB.prepare(
    "SELECT u.* FROM device_tokens dt JOIN users u ON dt.user_id = u.id WHERE dt.token_hash = ?"
  ).bind(tokenHash).first();
  return linked || null;
}

async function fetchAccountPayload(user, env) {
  const [ledgerRes, aggRes, todayRes] = await Promise.all([
    env.DB.prepare(
      "SELECT id, kind, provider, model, prompt_tokens, completion_tokens, reasoning_tokens, cost_micros, balance_after_micros, note, created_at FROM ledger WHERE user_id = ? ORDER BY id DESC LIMIT 30"
    ).bind(user.id).all(),
    env.DB.prepare(
      "SELECT COUNT(*) AS req_count, COALESCE(SUM(prompt_tokens), 0) AS in_tok, COALESCE(SUM(completion_tokens), 0) AS out_tok, COALESCE(SUM(reasoning_tokens), 0) AS reason_tok FROM ledger WHERE user_id = ? AND kind = 'chat'"
    ).bind(user.id).first(),
    env.DB.prepare(
      "SELECT COALESCE(SUM(cost_micros), 0) AS today_cost, COALESCE(SUM(prompt_tokens + completion_tokens + reasoning_tokens), 0) AS today_tok FROM ledger WHERE user_id = ? AND kind = 'chat' AND date(created_at) = date('now')"
    ).bind(user.id).first(),
  ]);
  return {
    userID: user.id,
    balanceYuan: microsToYuan(user.balance_micros),
    totalRechargedYuan: microsToYuan(user.total_recharged_micros),
    totalSpentYuan: microsToYuan(user.total_spent_micros),
    totalRequests: Number(aggRes?.req_count || 0),
    totalPromptTokens: Number(aggRes?.in_tok || 0),
    totalCompletionTokens: Number(aggRes?.out_tok || 0),
    totalReasoningTokens: Number(aggRes?.reason_tok || 0),
    todaySpentYuan: microsToYuan(todayRes?.today_cost || 0),
    todayTokens: Number(todayRes?.today_tok || 0),
    ledger: (ledgerRes.results || []).map((r) => ({
      id: r.id,
      kind: r.kind,
      provider: r.provider,
      model: r.model,
      promptTokens: r.prompt_tokens,
      completionTokens: r.completion_tokens,
      reasoningTokens: r.reasoning_tokens,
      costYuan: microsToYuan(r.cost_micros),
      balanceAfterYuan: microsToYuan(r.balance_after_micros),
      note: r.note,
      createdAt: r.created_at,
    })),
  };
}

function estimateTokens(text) {
  if (!text) return 0;
  // Conservative bilingual heuristic when upstream provider omits usage
  const utf8Bytes = new TextEncoder().encode(text).length;
  return Math.max(1, Math.ceil(utf8Bytes / 3));
}

function computeCostMicros(pricingItem, promptTokens, completionTokens, reasoningTokens) {
  const inputPrice = Math.max(0, Number(pricingItem.inputPricePerMillion || 0));
  const outputPrice = Math.max(0, Number(pricingItem.outputPricePerMillion || 0));
  const totalOut = Math.max(0, Number(completionTokens || 0)) + Math.max(0, Number(reasoningTokens || 0));
  const totalIn = Math.max(0, Number(promptTokens || 0));
  // cost in Yuan = (totalIn * inputPrice + totalOut * outputPrice) / 1_000_000
  // cost in micro-yuan = totalIn * inputPrice + totalOut * outputPrice
  const rawMicros = Math.ceil(totalIn * inputPrice + totalOut * outputPrice);
  return Math.max(100, rawMicros); // minimum ¥0.0001 per non-empty billed turn
}

async function handleRegister(request, env) {
  let body = {};
  try {
    body = await request.json();
  } catch {}
  const displayName = String(body.displayName || "").trim().slice(0, 40);
  const welcomeMicros = yuanToMicros(env.WELCOME_BALANCE_YUAN || 0);

  let userID = "";
  for (let attempt = 0; attempt < 5; attempt++) {
    const candidate = `WM-${randomCode(6, "0123456789")}`;
    const exists = await env.DB.prepare("SELECT 1 FROM users WHERE id = ?").bind(candidate).first();
    if (!exists) {
      userID = candidate;
      break;
    }
  }
  if (!userID) return json({ error: "无法分配账号 ID，请重试。" }, 500);

  const rawToken = `wm_live_${randomCode(36, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}`;
  const tokenHash = await sha256Hex(rawToken);

  const stmts = [
    env.DB.prepare(
      "INSERT INTO users (id, token_hash, display_name, balance_micros, total_recharged_micros, total_spent_micros) VALUES (?, ?, ?, ?, ?, 0)"
    ).bind(userID, tokenHash, displayName, welcomeMicros, welcomeMicros),
  ];
  if (welcomeMicros > 0) {
    stmts.push(
      env.DB.prepare(
        "INSERT INTO ledger (user_id, kind, cost_micros, balance_after_micros, note) VALUES (?, 'welcome', ?, ?, '新用户体验金')"
      ).bind(userID, -welcomeMicros, welcomeMicros)
    );
  }
  await env.DB.batch(stmts);

  return json({
    userID,
    userToken: rawToken,
    balanceYuan: microsToYuan(welcomeMicros),
  });
}

async function handleRedeem(request, env) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权，请重新激活 WUMIND 账户。" }, 401);

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "请求格式不正确。" }, 400);
  }
  const code = String(body.code || "").trim().toUpperCase();
  if (!code || code.length > 64) return json({ error: "请输入有效的充值兑换码。" }, 400);

  const voucher = await env.DB.prepare("SELECT * FROM vouchers WHERE code = ?").bind(code).first();
  if (!voucher) return json({ error: "兑换码不存在，请核对后重试。" }, 404);
  if (voucher.redeemed_by) return json({ error: "该兑换码已被使用。" }, 409);

  // Atomic conditional redemption to prevent double-spend races
  const claim = await env.DB.prepare(
    "UPDATE vouchers SET redeemed_by = ?, redeemed_at = datetime('now') WHERE code = ? AND redeemed_by IS NULL"
  ).bind(user.id, code).run();

  if (!claim.meta || claim.meta.changes !== 1) {
    return json({ error: "该兑换码已被使用。" }, 409);
  }

  await env.DB.prepare(
    "UPDATE users SET balance_micros = balance_micros + ?, total_recharged_micros = total_recharged_micros + ?, updated_at = datetime('now') WHERE id = ?"
  ).bind(voucher.amount_micros, voucher.amount_micros, user.id).run();

  const freshUser = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(user.id).first();
  await env.DB.prepare(
    "INSERT INTO ledger (user_id, kind, cost_micros, balance_after_micros, note) VALUES (?, 'redeem', ?, ?, ?)"
  ).bind(user.id, -voucher.amount_micros, freshUser.balance_micros, `兑换码 ${code}`).run();

  return json(await fetchAccountPayload(freshUser, env));
}

async function handleAdminSaveConfig(request, env) {
  if (!(await verifyAdminSecret(request, env))) return json({ error: "管理员密钥无效。" }, 401);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "配置 JSON 格式错误。" }, 400);
  }
  if (!Array.isArray(body.pricing) || body.pricing.length === 0) {
    return json({ error: "至少需要保留一个模型定价项。" }, 400);
  }
  const sanitized = {
    pricing: body.pricing.slice(0, 40).map((item) => ({
      id: String(item.id || "").trim(),
      provider: String(item.provider || "deepSeek").trim(),
      displayName: String(item.displayName || item.id || "").trim(),
      inputPricePerMillion: Math.max(0, Number(item.inputPricePerMillion || 0)),
      outputPricePerMillion: Math.max(0, Number(item.outputPricePerMillion || 0)),
      officialReferenceNote: String(item.officialReferenceNote || "").trim(),
      supportsThinking: Boolean(item.supportsThinking),
      enabled: item.enabled !== false,
    })).filter((x) => x.id.length > 0),
    wechatQRBase64: typeof body.wechatQRBase64 === "string" && body.wechatQRBase64.length <= 450_000 ? body.wechatQRBase64 : null,
    alipayQRBase64: typeof body.alipayQRBase64 === "string" && body.alipayQRBase64.length <= 450_000 ? body.alipayQRBase64 : null,
    rechargeNote: String(body.rechargeNote || "").slice(0, 1000),
    contactNote: String(body.contactNote || "").slice(0, 200),
    announcement: String(body.announcement || "").slice(0, 400),
    webSearchCostYuan: Math.max(0, Math.min(5, Number(body.webSearchCostYuan ?? 0.03))),
    billingMode: ["hybrid", "app_store_iap", "direct_qr"].includes(body.billingMode) ? body.billingMode : "hybrid",
    iapPacks: Array.isArray(body.iapPacks) && body.iapPacks.length
      ? body.iapPacks.slice(0, 12).map((p) => ({
          id: String(p.id || "").trim(),
          title: String(p.title || "").trim().slice(0, 40),
          creditYuan: Math.max(0.1, Number(p.creditYuan || 0)),
          fallbackPriceLabel: String(p.fallbackPriceLabel || "").trim().slice(0, 24),
          badge: p.badge ? String(p.badge).trim().slice(0, 16) : null,
        })).filter((p) => p.id.length > 0)
      : DEFAULT_IAP_PACKS,
    paymentWebhookNote: String(body.paymentWebhookNote || "").slice(0, 500),
  };

  await env.DB.prepare(
    "INSERT INTO config (key, value, updated_at) VALUES ('commercial_config', ?, datetime('now')) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')"
  ).bind(JSON.stringify(sanitized)).run();

  return json(sanitized);
}

async function handleAdminCreateVouchers(request, env) {
  if (!(await verifyAdminSecret(request, env))) return json({ error: "管理员密钥无效。" }, 401);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "请求格式错误。" }, 400);
  }
  const amountMicros = yuanToMicros(body.amountYuan);
  const count = Math.min(50, Math.max(1, parseInt(body.count || 1, 10)));
  const note = String(body.note || "").trim().slice(0, 120);
  if (amountMicros < 100_000) return json({ error: "单张兑换码面额至少 ¥0.10。" }, 400);

  const created = [];
  const stmts = [];
  for (let i = 0; i < count; i++) {
    const code = `WM-${randomCode(4)}-${randomCode(4)}-${randomCode(4)}`;
    created.push({
      code,
      amountYuan: microsToYuan(amountMicros),
      note,
      redeemedBy: null,
      createdAt: new Date().toISOString(),
    });
    stmts.push(
      env.DB.prepare("INSERT INTO vouchers (code, amount_micros, note) VALUES (?, ?, ?)").bind(code, amountMicros, note)
    );
  }
  await env.DB.batch(stmts);
  return json({ vouchers: created });
}

async function handleAdminTopUp(request, env) {
  if (!(await verifyAdminSecret(request, env))) return json({ error: "管理员密钥无效。" }, 401);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "请求格式错误。" }, 400);
  }
  const userID = String(body.userID || "").trim().toUpperCase();
  const amountMicros = yuanToMicros(body.amountYuan);
  const note = String(body.note || "管理员扫码入账").trim().slice(0, 120);
  if (!userID || amountMicros <= 0) return json({ error: "请填写有效的用户 ID 和大于 0 的金额。" }, 400);

  const existing = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(userID).first();
  if (!existing) return json({ error: `未找到用户 ${userID}` }, 404);

  await env.DB.prepare(
    "UPDATE users SET balance_micros = balance_micros + ?, total_recharged_micros = total_recharged_micros + ?, updated_at = datetime('now') WHERE id = ?"
  ).bind(amountMicros, amountMicros, userID).run();

  const updated = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(userID).first();
  await env.DB.prepare(
    "INSERT INTO ledger (user_id, kind, cost_micros, balance_after_micros, note) VALUES (?, 'admin_topup', ?, ?, ?)"
  ).bind(userID, -amountMicros, updated.balance_micros, note).run();

  return json({
    userID: updated.id,
    balanceYuan: microsToYuan(updated.balance_micros),
    totalRechargedYuan: microsToYuan(updated.total_recharged_micros),
  });
}

async function handleAdminSummary(request, env) {
  if (!(await verifyAdminSecret(request, env))) return json({ error: "管理员密钥无效。" }, 401);
  const stats = await env.DB.prepare(
    "SELECT COUNT(*) AS user_count, COALESCE(SUM(balance_micros), 0) AS total_balance, COALESCE(SUM(total_recharged_micros), 0) AS total_recharged, COALESCE(SUM(total_spent_micros), 0) AS total_spent FROM users"
  ).first();
  const vouchers = await env.DB.prepare(
    "SELECT code, amount_micros, note, redeemed_by, created_at FROM vouchers ORDER BY created_at DESC LIMIT 30"
  ).all();
  const users = await env.DB.prepare(
    "SELECT id, display_name, balance_micros, total_recharged_micros, total_spent_micros, updated_at FROM users ORDER BY updated_at DESC LIMIT 30"
  ).all();

  return json({
    userCount: Number(stats?.user_count || 0),
    totalBalanceYuan: microsToYuan(stats?.total_balance),
    totalRechargedYuan: microsToYuan(stats?.total_recharged),
    totalSpentYuan: microsToYuan(stats?.total_spent),
    recentVouchers: (vouchers.results || []).map((v) => ({
      code: v.code,
      amountYuan: microsToYuan(v.amount_micros),
      note: v.note,
      redeemedBy: v.redeemed_by || null,
      createdAt: v.created_at,
    })),
    recentUsers: (users.results || []).map((u) => ({
      userID: u.id,
      displayName: u.display_name || "",
      balanceYuan: microsToYuan(u.balance_micros),
      totalRechargedYuan: microsToYuan(u.total_recharged_micros),
      totalSpentYuan: microsToYuan(u.total_spent_micros),
    })),
  });
}

function getUpstreamTarget(provider, env) {
  switch (provider) {
    case "deepSeek":
      return { url: "https://api.deepseek.com/chat/completions", key: env.DEEPSEEK_API_KEY, style: "openai" };
    case "openAI":
      return { url: "https://api.openai.com/v1/chat/completions", key: env.OPENAI_API_KEY, style: "openai" };
    case "grok":
      return { url: "https://api.x.ai/v1/chat/completions", key: env.GROK_API_KEY, style: "openai" };
    case "claude":
      return { url: "https://api.anthropic.com/v1/messages", key: env.CLAUDE_API_KEY, style: "claude" };
    case "gemini":
      return { url: "https://generativelanguage.googleapis.com/v1beta/models", key: env.GEMINI_API_KEY, style: "gemini" };
    default:
      return null;
  }
}

async function recordUsageAndDeduct(env, userID, pricingItem, promptTokens, completionTokens, reasoningTokens, note = "") {
  const costMicros = computeCostMicros(pricingItem, promptTokens, completionTokens, reasoningTokens);
  await env.DB.prepare(
    "UPDATE users SET balance_micros = MAX(0, balance_micros - ?), total_spent_micros = total_spent_micros + ?, updated_at = datetime('now') WHERE id = ?"
  ).bind(costMicros, costMicros, userID).run();
  const updated = await env.DB.prepare("SELECT balance_micros FROM users WHERE id = ?").bind(userID).first();
  const afterMicros = Number(updated?.balance_micros || 0);
  const cleanNote = String(note || "").trim().slice(0, 120);
  await env.DB.prepare(
    "INSERT INTO ledger (user_id, kind, provider, model, prompt_tokens, completion_tokens, reasoning_tokens, cost_micros, balance_after_micros, note) VALUES (?, 'chat', ?, ?, ?, ?, ?, ?, ?, ?)"
  ).bind(
    userID,
    pricingItem.provider,
    pricingItem.id,
    promptTokens,
    completionTokens,
    reasoningTokens,
    costMicros,
    afterMicros,
    cleanNote
  ).run();
  return {
    promptTokens,
    completionTokens,
    reasoningTokens,
    costYuan: microsToYuan(costMicros),
    balanceYuan: microsToYuan(afterMicros),
  };
}

async function handleChatCompletions(request, env, ctx) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权，请重新激活 WUMIND 账户。" }, 401);
  if (Number(user.balance_micros || 0) <= 0) {
    return json({ error: "余额不足，请先扫码充值或输入兑换码。", code: "insufficient_balance", balanceYuan: 0 }, 402);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "请求 JSON 格式不正确。" }, 400);
  }

  const config = await loadCommercialConfig(env);
  const requestedModelID = String(body.model || "").trim();
  const pricingItem = config.pricing.find((p) => p.id === requestedModelID && p.enabled !== false);
  if (!pricingItem) {
    return json({ error: `该模型未在 WUMIND 计费列表启用：${requestedModelID}` }, 400);
  }

  const upstream = getUpstreamTarget(pricingItem.provider, env);
  if (!upstream || !upstream.key) {
    return json({ error: `管理员尚未在云端配置 ${pricingItem.provider} 上游 API Key。` }, 503);
  }

  const rawMessages = Array.isArray(body.messages) ? body.messages : [];
  if (rawMessages.length === 0) return json({ error: "消息内容不能为空。" }, 400);
  const systemPrompt = typeof body.systemPrompt === "string" && body.systemPrompt.trim() ? body.systemPrompt.trim() : null;
  const deepThinking = Boolean(body.deepThinking && pricingItem.supportsThinking);
  const sessionTag = typeof body.sessionTag === "string" ? body.sessionTag.trim().slice(0, 80) : "";

  const imageCount = rawMessages.reduce((acc, m) => acc + (Array.isArray(m.images) ? Math.min(4, m.images.length) : 0), 0);
  const fallbackPromptTokens = estimateTokens(
    (systemPrompt || "") + rawMessages.map((m) => String(m.content || "")).join("\n")
  ) + imageCount * 765;

  // OpenAI-compatible streaming (DeepSeek / OpenAI / Grok)
  if (upstream.style === "openai") {
    const supportsNativeImages = pricingItem.provider !== "deepSeek";
    const wireMessages = [];
    if (systemPrompt) wireMessages.push({ role: "system", content: systemPrompt });
    for (const m of rawMessages) {
      const role = m.role === "assistant" ? "assistant" : "user";
      const text = String(m.content || "");
      const imgs = supportsNativeImages && role === "user" && Array.isArray(m.images) ? m.images.slice(0, 4) : [];
      if (imgs.length > 0) {
        const parts = [{ type: "text", text }];
        for (const img of imgs) {
          if (typeof img?.base64Data === "string" && img.base64Data.length > 0) {
            const mime = typeof img.mimeType === "string" && img.mimeType.startsWith("image/") ? img.mimeType : "image/jpeg";
            parts.push({ type: "image_url", image_url: { url: `data:${mime};base64,${img.base64Data}` } });
          }
        }
        wireMessages.push({ role, content: parts });
      } else {
        wireMessages.push({ role, content: text });
      }
    }
    const payload = {
      model: pricingItem.id,
      messages: wireMessages,
      stream: true,
      stream_options: { include_usage: true },
    };
    if (pricingItem.provider === "deepSeek") {
      payload.thinking = { type: deepThinking ? "enabled" : "disabled" };
      payload.max_tokens = deepThinking ? 16384 : 8192;
    }

    const res = await fetch(upstream.url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${upstream.key}`,
      },
      body: JSON.stringify(payload),
    });

    if (!res.ok || !res.body) {
      return json({ error: `上游模型服务暂不可用（HTTP ${res.status}），本次未扣费。` }, 502);
    }

    const { readable, writable } = new TransformStream();
    const writer = writable.getWriter();
    const encoder = new TextEncoder();

    ctx.waitUntil((async () => {
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      let promptTokens = fallbackPromptTokens;
      let completionTokens = 0;
      let reasoningTokens = 0;
      let collectedContent = "";
      let collectedReasoning = "";

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() || "";
          for (const rawLine of lines) {
            const line = rawLine.trim();
            if (!line.startsWith("data:")) continue;
            const payloadStr = line.slice(5).trim();
            if (!payloadStr || payloadStr === "[DONE]") continue;
            try {
              const obj = JSON.parse(payloadStr);
              if (obj.usage) {
                if (typeof obj.usage.prompt_tokens === "number") promptTokens = obj.usage.prompt_tokens;
                if (typeof obj.usage.completion_tokens === "number") completionTokens = obj.usage.completion_tokens;
                const rt = obj.usage.completion_tokens_details?.reasoning_tokens;
                if (typeof rt === "number") reasoningTokens = rt;
              }
              const delta = obj.choices?.[0]?.delta;
              if (delta) {
                const reasoning = delta.reasoning_content || delta.reasoning || "";
                const content = delta.content || "";
                if (reasoning) collectedReasoning += reasoning;
                if (content) collectedContent += content;
                if (reasoning || content) {
                  await writer.write(encoder.encode(`data: ${JSON.stringify({ reasoning, content })}\n\n`));
                }
              }
            } catch {}
          }
        }
        if (completionTokens === 0 && (collectedContent || collectedReasoning)) {
          completionTokens = estimateTokens(collectedContent);
          reasoningTokens = estimateTokens(collectedReasoning);
        }
        if (collectedContent || collectedReasoning) {
          const receipt = await recordUsageAndDeduct(env, user.id, pricingItem, promptTokens, completionTokens, reasoningTokens, sessionTag);
          await writer.write(encoder.encode(`data: ${JSON.stringify({ wumind_billing: receipt })}\n\n`));
        }
        await writer.write(encoder.encode("data: [DONE]\n\n"));
      } finally {
        await writer.close().catch(() => {});
      }
    })());

    return new Response(readable, {
      headers: {
        "Content-Type": "text/event-stream; charset=utf-8",
        "Cache-Control": "no-cache",
      },
    });
  }

  // Claude Messages API (supports native multimodal image blocks + exact usage metering)
  if (upstream.style === "claude") {
    const payload = {
      model: pricingItem.id,
      max_tokens: deepThinking ? 8192 : 4096,
      messages: rawMessages.map((m) => {
        const role = m.role === "assistant" ? "assistant" : "user";
        const text = String(m.content || "");
        const imgs = role === "user" && Array.isArray(m.images) ? m.images.slice(0, 4) : [];
        if (imgs.length === 0) return { role, content: text };
        const blocks = [];
        for (const img of imgs) {
          if (typeof img?.base64Data === "string" && img.base64Data.length > 0) {
            const mime = typeof img.mimeType === "string" && img.mimeType.startsWith("image/") ? img.mimeType : "image/jpeg";
            blocks.push({ type: "image", source: { type: "base64", media_type: mime, data: img.base64Data } });
          }
        }
        blocks.push({ type: "text", text });
        return { role, content: blocks };
      }),
    };
    if (systemPrompt) payload.system = systemPrompt;
    if (deepThinking) payload.thinking = { type: "enabled", budget_tokens: 2048 };

    const res = await fetch(upstream.url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": upstream.key,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify(payload),
    });
    if (!res.ok) return json({ error: `Claude 上游暂不可用（HTTP ${res.status}），本次未扣费。` }, 502);
    const data = await res.json();
    const reasoning = (data.content || []).filter((b) => b.type === "thinking").map((b) => b.thinking || "").join("\n");
    const content = (data.content || []).filter((b) => b.type === "text").map((b) => b.text || "").join("");
    const promptTokens = Number(data.usage?.input_tokens || fallbackPromptTokens);
    const completionTokens = Number(data.usage?.output_tokens || estimateTokens(content + reasoning));
    const receipt = await recordUsageAndDeduct(env, user.id, pricingItem, promptTokens, completionTokens, 0, sessionTag);
    const frames = [];
    if (reasoning) frames.push(`data: ${JSON.stringify({ reasoning })}\n\n`);
    if (content) frames.push(`data: ${JSON.stringify({ content })}\n\n`);
    frames.push(`data: ${JSON.stringify({ wumind_billing: receipt })}\n\n`);
    frames.push("data: [DONE]\n\n");
    return new Response(frames.join(""), { headers: { "Content-Type": "text/event-stream; charset=utf-8" } });
  }

  // Gemini generateContent (supports native inline_data image parts + exact usageMetadata metering)
  if (upstream.style === "gemini") {
    const endpoint = `${upstream.url}/${encodeURIComponent(pricingItem.id)}:generateContent`;
    const payload = {
      contents: rawMessages.map((m) => {
        const role = m.role === "assistant" ? "model" : "user";
        const parts = [{ text: String(m.content || "") }];
        if (role === "user" && Array.isArray(m.images)) {
          for (const img of m.images.slice(0, 4)) {
            if (typeof img?.base64Data === "string" && img.base64Data.length > 0) {
              const mime = typeof img.mimeType === "string" && img.mimeType.startsWith("image/") ? img.mimeType : "image/jpeg";
              parts.push({ inline_data: { mime_type: mime, data: img.base64Data } });
            }
          }
        }
        return { role, parts };
      }),
    };
    if (systemPrompt) payload.systemInstruction = { parts: [{ text: systemPrompt }] };
    if (deepThinking) payload.generationConfig = { thinkingConfig: { includeThoughts: true } };

    const res = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": upstream.key,
      },
      body: JSON.stringify(payload),
    });
    if (!res.ok) return json({ error: `Gemini 上游暂不可用（HTTP ${res.status}），本次未扣费。` }, 502);
    const data = await res.json();
    const parts = data.candidates?.[0]?.content?.parts || [];
    const reasoning = parts.filter((p) => p.thought).map((p) => p.text || "").join("\n");
    const content = parts.filter((p) => !p.thought).map((p) => p.text || "").join("");
    const promptTokens = Number(data.usageMetadata?.promptTokenCount || fallbackPromptTokens);
    const completionTokens = Number(data.usageMetadata?.candidatesTokenCount || estimateTokens(content));
    const reasoningTokens = Number(data.usageMetadata?.thoughtsTokenCount || 0);
    const receipt = await recordUsageAndDeduct(env, user.id, pricingItem, promptTokens, completionTokens, reasoningTokens, sessionTag);
    const frames = [];
    if (reasoning) frames.push(`data: ${JSON.stringify({ reasoning })}\n\n`);
    if (content) frames.push(`data: ${JSON.stringify({ content })}\n\n`);
    frames.push(`data: ${JSON.stringify({ wumind_billing: receipt })}\n\n`);
    frames.push("data: [DONE]\n\n");
    return new Response(frames.join(""), { headers: { "Content-Type": "text/event-stream; charset=utf-8" } });
  }

  return json({ error: "不支持的模型通道。" }, 400);
}

// MARK: - Cloud Scheduled Tasks (/v1/schedules + Cron Trigger)

async function handleUpsertSchedule(request, env) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "JSON 格式错误。" }, 400);
  }
  const id = String(body.id || "").trim().slice(0, 64);
  const title = String(body.title || "").trim().slice(0, 80);
  const prompt = String(body.prompt || "").trim().slice(0, 8000);
  const modelID = String(body.modelID || "deepseek-reasoner").trim().slice(0, 80);
  const intervalMinutes = Math.max(15, Math.min(10080, Number(body.intervalMinutes || 1440)));
  const enabled = body.enabled ? 1 : 0;
  const nextRunEpoch = Number(body.nextRunEpoch || Math.floor(Date.now() / 1000) + intervalMinutes * 60);
  if (!id || !title || !prompt) return json({ error: "缺少定时任务必填字段。" }, 400);

  await env.DB.prepare(
    `INSERT INTO schedules (id, user_id, title, prompt, model_id, interval_minutes, enabled, next_run_epoch)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET
       title = excluded.title,
       prompt = excluded.prompt,
       model_id = excluded.model_id,
       interval_minutes = excluded.interval_minutes,
       enabled = excluded.enabled,
       next_run_epoch = excluded.next_run_epoch
     WHERE schedules.user_id = excluded.user_id`
  ).bind(id, user.id, title, prompt, modelID, intervalMinutes, enabled, nextRunEpoch).run();
  return json({ ok: true });
}

async function handleListSchedules(request, env) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  const rows = await env.DB.prepare(
    "SELECT id, title, prompt, model_id, interval_minutes, enabled, next_run_epoch, last_run_at, last_answer, last_cost_micros FROM schedules WHERE user_id = ? ORDER BY created_at DESC LIMIT 30"
  ).bind(user.id).all();
  return json({
    schedules: (rows.results || []).map((r) => ({
      id: r.id,
      title: r.title,
      prompt: r.prompt,
      modelID: r.model_id,
      intervalMinutes: Number(r.interval_minutes || 1440),
      enabled: Boolean(r.enabled),
      nextRunEpoch: Number(r.next_run_epoch || 0),
      lastRunAt: r.last_run_at,
      lastAnswer: r.last_answer,
      lastCostYuan: microsToYuan(Number(r.last_cost_micros || 0)),
    })),
  });
}

async function handleDeleteSchedule(request, env, scheduleID) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  await env.DB.prepare("DELETE FROM schedules WHERE id = ? AND user_id = ?").bind(scheduleID, user.id).run();
  return json({ ok: true });
}

async function executeDueCloudSchedules(env) {
  const nowEpoch = Math.floor(Date.now() / 1000);
  const due = await env.DB.prepare(
    "SELECT s.*, u.balance_micros FROM schedules s JOIN users u ON s.user_id = u.id WHERE s.enabled = 1 AND s.next_run_epoch <= ? AND u.balance_micros > 0 LIMIT 10"
  ).bind(nowEpoch).all();
  const rows = due.results || [];
  if (rows.length === 0) return;

  const config = await loadCommercialConfig(env);
  for (const row of rows) {
    const pricingItem = config.pricing.find((p) => p.id === row.model_id && p.enabled !== false) || config.pricing[0];
    if (!pricingItem) continue;
    const upstream = getUpstreamTarget(pricingItem.provider, env);
    if (!upstream || !upstream.key || upstream.style !== "openai") continue;
    try {
      const res = await fetch(upstream.url, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${upstream.key}` },
        body: JSON.stringify({
          model: pricingItem.id,
          messages: [{ role: "user", content: row.prompt }],
          stream: false,
          max_tokens: 4096,
        }),
      });
      if (!res.ok) continue;
      const data = await res.json();
      const answer = data.choices?.[0]?.message?.content || "";
      const promptTokens = Number(data.usage?.prompt_tokens || estimateTokens(row.prompt));
      const completionTokens = Number(data.usage?.completion_tokens || estimateTokens(answer));
      const receipt = await recordUsageAndDeduct(
        env,
        row.user_id,
        pricingItem,
        promptTokens,
        completionTokens,
        0,
        `定时任务 · ${String(row.title).slice(0, 40)}`
      );
      const nextEpoch = nowEpoch + Math.max(15, Number(row.interval_minutes || 1440)) * 60;
      await env.DB.prepare(
        "UPDATE schedules SET last_run_at = datetime('now'), last_answer = ?, last_cost_micros = ?, next_run_epoch = ? WHERE id = ?"
      ).bind(String(answer).slice(0, 12000), Math.round(receipt.costYuan * 1_000_000), nextEpoch, row.id).run();
    } catch {
      // Skip failed schedule without deducting balance; retried on next cron tick
    }
  }
}

// MARK: - Metered Web Search & Deep Research (/v1/tools/web-search)

async function runUpstreamWebSearch(query, maxResults, depth, env) {
  const limit = Math.min(10, Math.max(1, Number(maxResults || 5)));
  const tavilyKey = (env.TAVILY_API_KEY || "").trim();
  if (tavilyKey) {
    const res = await fetch("https://api.tavily.com/search", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        api_key: tavilyKey,
        query,
        search_depth: depth === "advanced" ? "advanced" : "basic",
        max_results: limit,
      }),
    });
    if (res.ok) {
      const data = await res.json();
      const items = (data.results || []).slice(0, limit).map((r) => ({
        title: String(r.title || ""),
        url: String(r.url || ""),
        snippet: String(r.content || "").slice(0, 460),
        publishedDate: r.published_date ? String(r.published_date) : null,
      })).filter((r) => r.title && r.url);
      return { provider: "Tavily", results: items };
    }
  }

  const braveKey = (env.BRAVE_SEARCH_API_KEY || "").trim();
  if (braveKey) {
    const u = `https://api.search.brave.com/res/v1/web/search?q=${encodeURIComponent(query)}&count=${limit}`;
    const res = await fetch(u, {
      headers: { "X-Subscription-Token": braveKey, Accept: "application/json" },
    });
    if (res.ok) {
      const data = await res.json();
      const items = (data.web?.results || []).slice(0, limit).map((r) => ({
        title: String(r.title || ""),
        url: String(r.url || ""),
        snippet: String(r.description || "").slice(0, 460),
        publishedDate: r.age ? String(r.age) : null,
      })).filter((r) => r.title && r.url);
      return { provider: "Brave", results: items };
    }
  }

  const serperKey = (env.SERPER_API_KEY || "").trim();
  if (serperKey) {
    const res = await fetch("https://google.serper.dev/search", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-API-KEY": serperKey },
      body: JSON.stringify({ q: query, num: limit }),
    });
    if (res.ok) {
      const data = await res.json();
      const items = (data.organic || []).slice(0, limit).map((r) => ({
        title: String(r.title || ""),
        url: String(r.link || ""),
        snippet: String(r.snippet || "").slice(0, 460),
        publishedDate: r.date ? String(r.date) : null,
      })).filter((r) => r.title && r.url);
      return { provider: "Serper", results: items };
    }
  }

  // Zero-key DuckDuckGo Lite HTML fallback
  const ddgRes = await fetch(`https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`, {
    headers: { "User-Agent": "Mozilla/5.0 (compatible; WUMIND-Gateway/1.2)" },
  });
  if (!ddgRes.ok) throw new Error(`HTTP ${ddgRes.status}`);
  const html = (await ddgRes.text()).slice(0, 350_000);
  const linkRe = /<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
  const snippetRe = /class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)<\/(?:a|div|span)>/gi;
  const links = [...html.matchAll(linkRe)];
  const snippets = [...html.matchAll(snippetRe)];
  const strip = (s) => String(s || "").replace(/<[^>]+>/g, " ").replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/\s+/g, " ").trim();
  const results = [];
  for (let i = 0; i < Math.min(limit, links.length); i++) {
    let href = String(links[i][1] || "").replace(/&amp;/g, "&");
    if (href.startsWith("//")) href = "https:" + href;
    try {
      const parsed = new URL(href);
      const uddg = parsed.searchParams.get("uddg");
      if (uddg) href = uddg;
    } catch {}
    const title = strip(links[i][2]);
    const snippet = i < snippets.length ? strip(snippets[i][1]).slice(0, 420) : "";
    if (title && href.startsWith("http")) {
      results.push({ title, url: href, snippet, publishedDate: null });
    }
  }
  return { provider: "DuckDuckGo", results };
}

async function handleWebSearch(request, env) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  if (Number(user.balance_micros || 0) <= 0) {
    return json({ error: "余额不足，无法发起内置联网搜索。", code: "insufficient_balance" }, 402);
  }
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求 JSON 无效。" }, 400); }
  const query = String(body.query || "").trim().slice(0, 400);
  if (!query) return json({ error: "搜索关键词不能为空。" }, 400);

  const config = await loadCommercialConfig(env);
  const searchCostMicros = yuanToMicros(config.webSearchCostYuan ?? 0.03);
  const { provider, results } = await runUpstreamWebSearch(query, body.maxResults || 5, body.depth || "basic", env);

  let balanceAfterMicros = Number(user.balance_micros || 0);
  if (searchCostMicros > 0 && results.length > 0) {
    await env.DB.prepare(
      "UPDATE users SET balance_micros = MAX(0, balance_micros - ?), total_spent_micros = total_spent_micros + ?, updated_at = datetime('now') WHERE id = ?"
    ).bind(searchCostMicros, searchCostMicros, user.id).run();
    const fresh = await env.DB.prepare("SELECT balance_micros FROM users WHERE id = ?").bind(user.id).first();
    balanceAfterMicros = Number(fresh?.balance_micros || 0);
    await env.DB.prepare(
      "INSERT INTO ledger (user_id, kind, provider, model, cost_micros, balance_after_micros, note) VALUES (?, 'chat', ?, 'web_search', ?, ?, ?)"
    ).bind(user.id, provider, searchCostMicros, balanceAfterMicros, `联网搜索 · ${query.slice(0, 48)}`).run();
  }

  return json({
    query,
    provider,
    results,
    costYuan: results.length > 0 ? microsToYuan(searchCostMicros) : 0,
    balanceYuan: microsToYuan(balanceAfterMicros),
  });
}

// MARK: - Cross-Device Zero-Knowledge Encrypted Cloud Sync & Pairing (/v1/sync/*)

async function handleSyncPush(request, env) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求格式错误。" }, 400); }
  const encryptedPayload = String(body.encryptedPayload || "");
  if (!encryptedPayload || encryptedPayload.length > 3_500_000) {
    return json({ error: "同步数据为空或超过 3.5 MB 上限。" }, 400);
  }
  const version = Math.max(1, parseInt(body.version || 1, 10));
  const deviceName = String(body.deviceName || "iOS").slice(0, 64);
  const nowIso = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO sync_snapshots (user_id, encrypted_payload, version, device_name, updated_at)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET
       encrypted_payload = excluded.encrypted_payload,
       version = excluded.version,
       device_name = excluded.device_name,
       updated_at = excluded.updated_at`
  ).bind(user.id, encryptedPayload, version, deviceName, nowIso).run();
  return json({ ok: true, version, updatedAt: nowIso });
}

async function handleSyncPull(request, env) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  const row = await env.DB.prepare(
    "SELECT encrypted_payload, version, device_name, updated_at FROM sync_snapshots WHERE user_id = ?"
  ).bind(user.id).first();
  if (!row) {
    return json({ hasSnapshot: false, encryptedPayload: null, version: 0, deviceName: null, updatedAt: null });
  }
  return json({
    hasSnapshot: true,
    encryptedPayload: row.encrypted_payload,
    version: Number(row.version || 1),
    deviceName: row.device_name || null,
    updatedAt: row.updated_at || null,
  });
}

async function handlePairCreate(request, env) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  const code = `SYNC-${randomCode(4)}-${randomCode(4)}`;
  const expiresEpoch = Math.floor(Date.now() / 1000) + 600; // 10 minutes
  await env.DB.prepare(
    "INSERT INTO pairing_codes (code, user_id, expires_epoch, claimed) VALUES (?, ?, ?, 0)"
  ).bind(code, user.id, expiresEpoch).run();
  return json({ code, expiresAt: new Date(expiresEpoch * 1000).toISOString() });
}

async function handlePairClaim(request, env) {
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求格式错误。" }, 400); }
  const code = String(body.code || "").trim().toUpperCase();
  const nowEpoch = Math.floor(Date.now() / 1000);
  const row = await env.DB.prepare(
    "SELECT * FROM pairing_codes WHERE code = ? AND claimed = 0 AND expires_epoch >= ?"
  ).bind(code, nowEpoch).first();
  if (!row) return json({ error: "同步配对码无效、已使用或已过期（有效期 10 分钟）。" }, 404);

  const claimRes = await env.DB.prepare(
    "UPDATE pairing_codes SET claimed = 1 WHERE code = ? AND claimed = 0"
  ).bind(code).run();
  if ((claimRes.meta?.changes || 0) === 0) {
    return json({ error: "同步配对码已被使用。" }, 409);
  }

  const user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(row.user_id).first();
  if (!user) return json({ error: "关联账号不存在。" }, 404);

  const newToken = `wm_live_${randomCode(36, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}`;
  const tokenHash = await sha256Hex(newToken);
  await env.DB.prepare(
    "INSERT INTO device_tokens (token_hash, user_id, device_name) VALUES (?, ?, ?)"
  ).bind(tokenHash, user.id, String(body.deviceName || "Paired Device").slice(0, 64)).run();

  return json({
    userID: user.id,
    userToken: newToken,
    balanceYuan: microsToYuan(user.balance_micros),
  });
}

// MARK: - Automated Payment Orders, HMAC-SHA256 Webhooks & StoreKit 2 IAP Verification

async function creditUserIdempotent(env, userID, externalOrderID, amountMicros, channel, note) {
  const existing = await env.DB.prepare(
    "SELECT * FROM payment_orders WHERE external_order_id = ?"
  ).bind(externalOrderID).first();
  if (existing && existing.status === "paid") {
    const u = await env.DB.prepare("SELECT balance_micros FROM users WHERE id = ?").bind(userID).first();
    return { alreadyCredited: true, balanceMicros: Number(u?.balance_micros || 0) };
  }

  const orderID = existing?.id || `ORD-${randomCode(8)}`;
  if (existing) {
    const upd = await env.DB.prepare(
      "UPDATE payment_orders SET status = 'paid', amount_micros = ?, channel = ?, note = ?, paid_at = datetime('now') WHERE id = ? AND status != 'paid'"
    ).bind(amountMicros, channel, note, orderID).run();
    if ((upd.meta?.changes || 0) === 0) {
      const u = await env.DB.prepare("SELECT balance_micros FROM users WHERE id = ?").bind(userID).first();
      return { alreadyCredited: true, balanceMicros: Number(u?.balance_micros || 0) };
    }
  } else {
    try {
      await env.DB.prepare(
        "INSERT INTO payment_orders (id, user_id, external_order_id, amount_micros, channel, status, note, paid_at) VALUES (?, ?, ?, ?, ?, 'paid', ?, datetime('now'))"
      ).bind(orderID, userID, externalOrderID, amountMicros, channel, note).run();
    } catch {
      const u = await env.DB.prepare("SELECT balance_micros FROM users WHERE id = ?").bind(userID).first();
      return { alreadyCredited: true, balanceMicros: Number(u?.balance_micros || 0) };
    }
  }

  await env.DB.prepare(
    "UPDATE users SET balance_micros = balance_micros + ?, total_recharged_micros = total_recharged_micros + ?, updated_at = datetime('now') WHERE id = ?"
  ).bind(amountMicros, amountMicros, userID).run();
  const fresh = await env.DB.prepare("SELECT balance_micros FROM users WHERE id = ?").bind(userID).first();
  const bal = Number(fresh?.balance_micros || 0);
  await env.DB.prepare(
    "INSERT INTO ledger (user_id, kind, provider, model, cost_micros, balance_after_micros, note) VALUES (?, 'redeem', ?, 'recharge', ?, ?, ?)"
  ).bind(userID, channel, -amountMicros, bal, note).run();
  return { alreadyCredited: false, balanceMicros: bal };
}

async function handleCreatePaymentOrder(request, env) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求格式错误。" }, 400); }
  const amountMicros = yuanToMicros(body.amountYuan);
  if (amountMicros < 100_000 || amountMicros > 50_000_000_000) {
    return json({ error: "充值金额需在 ¥0.10 至 ¥50,000 之间。" }, 400);
  }
  const channel = String(body.channel || "qr").slice(0, 32);
  const orderID = `ORD-${randomCode(8)}`;
  const note = `待入账充值单（${channel}）`;
  await env.DB.prepare(
    "INSERT INTO payment_orders (id, user_id, external_order_id, amount_micros, channel, status, note) VALUES (?, ?, ?, ?, ?, 'pending', ?)"
  ).bind(orderID, user.id, orderID, amountMicros, channel, note).run();
  return json({
    id: orderID,
    amountYuan: microsToYuan(amountMicros),
    channel,
    status: "pending",
    note,
    createdAt: new Date().toISOString(),
    paidAt: null,
  });
}

async function handleListPaymentOrders(request, env) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  const rows = await env.DB.prepare(
    "SELECT id, amount_micros, channel, status, note, created_at, paid_at FROM payment_orders WHERE user_id = ? ORDER BY created_at DESC LIMIT 20"
  ).bind(user.id).all();
  return json({
    orders: (rows.results || []).map((r) => ({
      id: r.id,
      amountYuan: microsToYuan(r.amount_micros),
      channel: r.channel,
      status: r.status,
      note: r.note,
      createdAt: r.created_at,
      paidAt: r.paid_at || null,
    })),
  });
}

async function handlePaymentWebhook(request, env) {
  const secret = (env.PAYMENT_WEBHOOK_SECRET || "").trim();
  if (!secret) return json({ error: "网关未配置 PAYMENT_WEBHOOK_SECRET。" }, 503);
  const rawBody = await request.text();
  const providedSig = (request.headers.get("X-WuMind-Signature") || "").trim().toLowerCase();
  const expectedSig = (await hmacSha256Hex(secret, rawBody)).toLowerCase();
  if (!constantTimeEqual(providedSig, expectedSig)) {
    return json({ error: "Webhook 签名校验失败。" }, 401);
  }

  let body;
  try { body = JSON.parse(rawBody); } catch { return json({ error: "JSON 无效。" }, 400); }
  const userID = String(body.userID || "").trim().toUpperCase();
  const externalOrderID = String(body.externalOrderID || body.orderID || "").trim();
  const amountMicros = yuanToMicros(body.amountYuan);
  const channel = String(body.channel || "webhook").slice(0, 32);
  if (!userID || !externalOrderID || amountMicros <= 0) {
    return json({ error: "缺少 userID / externalOrderID / amountYuan。" }, 400);
  }
  const user = await env.DB.prepare("SELECT id FROM users WHERE id = ?").bind(userID).first();
  if (!user) return json({ error: `未找到用户 ${userID}` }, 404);

  const result = await creditUserIdempotent(
    env,
    userID,
    externalOrderID,
    amountMicros,
    channel,
    `自动回调入账 · ${channel} (${externalOrderID.slice(0, 24)})`
  );
  return json({
    ok: true,
    userID,
    alreadyCredited: result.alreadyCredited,
    balanceYuan: microsToYuan(result.balanceMicros),
  });
}

function decodeBase64URLJson(segment) {
  const b64 = segment.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((segment.length + 3) % 4);
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return JSON.parse(new TextDecoder().decode(bytes));
}

async function handleVerifyAppleIAP(request, env) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求格式错误。" }, 400); }
  const productID = String(body.productID || "").trim();
  const transactionID = String(body.transactionID || "").trim();
  const jws = String(body.jwsRepresentation || "").trim();
  if (!productID || !transactionID || !jws) {
    return json({ error: "缺少 Apple IAP 交易凭据。" }, 400);
  }

  // Decode & verify JWS payload structure and claims (bundleId, productId, transactionId)
  const parts = jws.split(".");
  if (parts.length !== 3) return json({ error: "StoreKit 2 JWS 格式无效。" }, 400);
  let claims;
  try {
    claims = decodeBase64URLJson(parts[1]);
  } catch {
    return json({ error: "无法解码 StoreKit 2 交易载荷。" }, 400);
  }
  const expectedBundle = (env.APPLE_BUNDLE_ID || "com.kriswu.shiftreminder").trim();
  if (claims.bundleId !== expectedBundle || claims.productId !== productID || String(claims.transactionId) !== transactionID) {
    return json({ error: "Apple 内购交易声明不匹配（bundleId/productId/transactionId）。" }, 400);
  }

  const config = await loadCommercialConfig(env);
  const pack = (config.iapPacks || DEFAULT_IAP_PACKS).find((p) => p.id === productID);
  if (!pack) return json({ error: `未配置的内购商品 ID：${productID}` }, 400);

  const amountMicros = yuanToMicros(pack.creditYuan);
  const result = await creditUserIdempotent(
    env,
    user.id,
    `iap:${transactionID}`,
    amountMicros,
    "apple_iap",
    `Apple 内购 · ${pack.title} (#${transactionID.slice(-8)})`
  );
  return json({
    ok: true,
    creditedYuan: result.alreadyCredited ? 0 : microsToYuan(amountMicros),
    balanceYuan: microsToYuan(result.balanceMicros),
    alreadyCredited: result.alreadyCredited,
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "");

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204 });
    }

    try {
      if (request.method === "GET" && path === "/v1/public/config") {
        return json(await loadCommercialConfig(env));
      }
      if (request.method === "POST" && path === "/v1/account/register") {
        return await handleRegister(request, env);
      }
      if (request.method === "GET" && path === "/v1/account/me") {
        const user = await authenticateUser(request, env);
        if (!user) return json({ error: "未授权。" }, 401);
        return json(await fetchAccountPayload(user, env));
      }
      if (request.method === "POST" && path === "/v1/account/redeem") {
        return await handleRedeem(request, env);
      }
      if (request.method === "POST" && path === "/v1/chat/completions") {
        return await handleChatCompletions(request, env, ctx);
      }
      if (request.method === "POST" && path === "/v1/tools/web-search") {
        return await handleWebSearch(request, env);
      }
      if (request.method === "GET" && path === "/v1/schedules") {
        return await handleListSchedules(request, env);
      }
      if (request.method === "POST" && path === "/v1/schedules") {
        return await handleUpsertSchedule(request, env);
      }
      if (request.method === "DELETE" && path.startsWith("/v1/schedules/")) {
        return await handleDeleteSchedule(request, env, decodeURIComponent(path.slice("/v1/schedules/".length)));
      }
      if (request.method === "POST" && path === "/v1/sync/push") {
        return await handleSyncPush(request, env);
      }
      if (request.method === "GET" && path === "/v1/sync/pull") {
        return await handleSyncPull(request, env);
      }
      if (request.method === "POST" && path === "/v1/sync/pair/create") {
        return await handlePairCreate(request, env);
      }
      if (request.method === "POST" && path === "/v1/sync/pair/claim") {
        return await handlePairClaim(request, env);
      }
      if (request.method === "POST" && path === "/v1/payments/create-order") {
        return await handleCreatePaymentOrder(request, env);
      }
      if (request.method === "GET" && path === "/v1/payments/orders") {
        return await handleListPaymentOrders(request, env);
      }
      if (request.method === "POST" && path === "/v1/webhooks/payment") {
        return await handlePaymentWebhook(request, env);
      }
      if (request.method === "POST" && path === "/v1/iap/verify") {
        return await handleVerifyAppleIAP(request, env);
      }
      if (request.method === "PUT" && path === "/v1/admin/config") {
        return await handleAdminSaveConfig(request, env);
      }
      if (request.method === "POST" && path === "/v1/admin/vouchers") {
        return await handleAdminCreateVouchers(request, env);
      }
      if (request.method === "POST" && path === "/v1/admin/topup") {
        return await handleAdminTopUp(request, env);
      }
      if (request.method === "GET" && path === "/v1/admin/summary") {
        return await handleAdminSummary(request, env);
      }
      return json({ error: "Not Found" }, 404);
    } catch (err) {
      return json({ error: "网关内部处理异常，请稍后重试。" }, 500);
    }
  },
  async scheduled(event, env, ctx) {
    ctx.waitUntil(executeDueCloudSchedules(env));
  },
};
