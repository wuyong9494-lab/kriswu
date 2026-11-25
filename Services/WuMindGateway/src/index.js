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

// Pure-JS RFC 1321 MD5 (UTF-8) for Epay / 彩虹易支付 checkout signing & webhook verification
function md5Hex(input) {
  const bytes = new TextEncoder().encode(String(input ?? ""));
  const len = bytes.length;
  const wordCount = (((len + 8) >> 6) + 1) * 16;
  const x = new Uint32Array(wordCount);
  for (let i = 0; i < len; i++) {
    x[i >> 2] |= bytes[i] << ((i % 4) * 8);
  }
  x[len >> 2] |= 0x80 << ((len % 4) * 8);
  x[wordCount - 2] = (len << 3) >>> 0;
  x[wordCount - 1] = len >>> 29;

  const s = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];
  const K = new Uint32Array(64);
  for (let i = 0; i < 64; i++) K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 0x100000000) >>> 0;

  let a0 = 0x67452301;
  let b0 = 0xefcdab89;
  let c0 = 0x98badcfe;
  let d0 = 0x10325476;

  for (let offset = 0; offset < wordCount; offset += 16) {
    let A = a0, B = b0, C = c0, D = d0;
    for (let i = 0; i < 64; i++) {
      let F, g;
      if (i < 16) { F = (B & C) | (~B & D); g = i; }
      else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
      else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; }
      else { F = C ^ (B | ~D); g = (7 * i) % 16; }
      const sum = (A + F + K[i] + x[offset + g]) >>> 0;
      const rot = ((sum << s[i]) | (sum >>> (32 - s[i]))) >>> 0;
      A = D; D = C; C = B; B = (B + rot) >>> 0;
    }
    a0 = (a0 + A) >>> 0;
    b0 = (b0 + B) >>> 0;
    c0 = (c0 + C) >>> 0;
    d0 = (d0 + D) >>> 0;
  }

  const out = [a0, b0, c0, d0];
  let hex = "";
  for (const w of out) {
    for (let j = 0; j < 4; j++) hex += ((w >>> (j * 8)) & 0xff).toString(16).padStart(2, "0");
  }
  return hex;
}

function signEpayParams(params, epayKey) {
  const keys = Object.keys(params)
    .filter((k) => k !== "sign" && k !== "sign_type" && params[k] !== undefined && params[k] !== null && String(params[k]) !== "")
    .sort();
  const base = keys.map((k) => `${k}=${params[k]}`).join("&");
  return md5Hex(`${base}${epayKey}`);
}

function isEnvTrue(value, defaultValue = false) {
  if (value === undefined || value === null || String(value).trim() === "") return defaultValue;
  const v = String(value).trim().toLowerCase();
  return v === "true" || v === "1" || v === "yes" || v === "on";
}

function isAutoCreditPaused(env) {
  // Fail-closed by default unless explicitly set to "false" / "0"
  return isEnvTrue(env.AUTO_CREDIT_PAUSED, true);
}

function isAppleSandboxTestEnabled(env) {
  return !isAutoCreditPaused(env) && isEnvTrue(env.ALLOW_APPLE_SANDBOX_TEST, false);
}

function isAppleProductionIAPEnabled(env) {
  return !isAutoCreditPaused(env) && isEnvTrue(env.ALLOW_APPLE_PRODUCTION_IAP, false);
}

function isAutoCheckoutConfigured(env) {
  if (isAutoCreditPaused(env)) return false;
  const hasEpay = Boolean((env.EPAY_API_URL || "").trim() && (env.EPAY_PID || "").trim() && (env.EPAY_KEY || "").trim());
  const hasCustomCheckout = Boolean((env.PAYMENT_CHECKOUT_URL || "").trim());
  return hasEpay || hasCustomCheckout;
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

function bytesEqual(a, b) {
  if (!(a instanceof Uint8Array) || !(b instanceof Uint8Array) || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
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
  const autoCreditPaused = isAutoCreditPaused(env);
  const autoCheckoutEnabled = isAutoCheckoutConfigured(env);
  const appleIAPProductionEnabled = isAppleProductionIAPEnabled(env);
  const appleIAPSandboxTestEnabled = isAppleSandboxTestEnabled(env);
  const statusFlags = {
    autoCheckoutEnabled,
    autoCreditPaused,
    appleIAPProductionEnabled,
    appleIAPSandboxTestEnabled,
    smsAuthConfigured: Boolean((env.SMS_WEBHOOK_URL || "").trim()) || isEnvTrue(env.AUTH_TEST_MODE, false),
    wechatAuthConfigured: Boolean((env.WECHAT_APP_ID || "").trim() && (env.WECHAT_APP_SECRET || "").trim()) || isEnvTrue(env.AUTH_TEST_MODE, false),
  };
  const row = await env.DB.prepare("SELECT value FROM config WHERE key = 'commercial_config'").first();
  if (!row || !row.value) return { ...DEFAULT_COMMERCIAL_CONFIG, ...statusFlags };
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
      ...statusFlags,
    };
  } catch {
    return { ...DEFAULT_COMMERCIAL_CONFIG, ...statusFlags };
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
    sandboxBalanceYuan: microsToYuan(user.sandbox_balance_micros || 0),
    sandboxRechargedYuan: microsToYuan(user.sandbox_recharged_micros || 0),
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

// MARK: - Automated Payment Orders, HMAC-SHA256 Webhooks & Cryptographic StoreKit 2 IAP Verification

// Official Apple Root CA - G3 (ECDSA P-384 / SHA-384, Expires 2039-04-30) SHA-256 fingerprint
// Verified against Apple PKI & Apple Support Root Certificate Trust Stores (HT212773 / 105116 / 121672 / 126047).
const APPLE_ROOT_CA_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";
const APPLE_WWDR_INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";
const APPLE_APPSTORE_LEAF_OID = "1.2.840.113635.100.6.11.1";

async function sha256BytesHex(bytes) {
  const buf = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function decodeBase64ToBytes(b64) {
  const clean = String(b64 || "").replace(/\s+/g, "");
  if (!clean || !/^[A-Za-z0-9+/=]+$/.test(clean)) throw new Error("Invalid Base64");
  const bin = atob(clean);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function decodeBase64URLToBytes(segment) {
  const clean = String(segment || "");
  if (!clean || !/^[A-Za-z0-9_-]+$/.test(clean)) throw new Error("Invalid Base64URL");
  const b64 = clean.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((clean.length + 3) % 4);
  return decodeBase64ToBytes(b64);
}

function encodeBytesToBase64URL(bytes) {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function decodeBase64URLJson(segment) {
  return JSON.parse(new TextDecoder().decode(decodeBase64URLToBytes(segment)));
}

// Strict minimal ASN.1 DER reader (RFC 5280 / ITU-T X.690) — rejects indefinite/malformed lengths.
function readDerNode(bytes, offset, limit) {
  if (offset >= limit) throw new Error("DER truncated");
  const tag = bytes[offset];
  let cursor = offset + 1;
  if (cursor >= limit) throw new Error("DER length truncated");
  const lenByte = bytes[cursor++];
  let length;
  if ((lenByte & 0x80) === 0) {
    length = lenByte;
  } else {
    const numOctets = lenByte & 0x7f;
    if (numOctets === 0 || numOctets > 3 || cursor + numOctets > limit) {
      throw new Error("DER unsupported length");
    }
    length = 0;
    for (let i = 0; i < numOctets; i++) {
      length = (length << 8) | bytes[cursor++];
    }
    if (length < 0x80) throw new Error("DER non-canonical length");
  }
  const valueStart = cursor;
  const end = valueStart + length;
  if (end > limit) throw new Error("DER node exceeds bounds");
  return { tag, start: offset, valueStart, length, end };
}

function readDerChildren(bytes, node) {
  const children = [];
  let pos = node.valueStart;
  while (pos < node.end) {
    const child = readDerNode(bytes, pos, node.end);
    children.push(child);
    pos = child.end;
  }
  if (pos !== node.end) throw new Error("DER children trailing bytes");
  return children;
}

function decodeDerOID(bytes, node) {
  if (node.tag !== 0x06 || node.length < 1) throw new Error("Invalid DER OID");
  const b0 = bytes[node.valueStart];
  const first = Math.min(2, Math.floor(b0 / 40));
  const second = b0 - 40 * first;
  const arcs = [first, second];
  let val = 0;
  let arcBytes = 0;
  for (let i = node.valueStart + 1; i < node.end; i++) {
    const b = bytes[i];
    if (arcBytes === 0 && b === 0x80) throw new Error("Non-canonical DER OID");
    val = val * 128 + (b & 0x7f);
    arcBytes++;
    if (arcBytes > 7) throw new Error("DER OID overflow");
    if ((b & 0x80) === 0) {
      arcs.push(val);
      val = 0;
      arcBytes = 0;
    }
  }
  if (arcBytes !== 0) throw new Error("Truncated DER OID");
  return arcs.join(".");
}

function decodeDerTimeMs(bytes, node) {
  const str = new TextDecoder("ascii").decode(bytes.subarray(node.valueStart, node.end));
  if (node.tag === 0x17) {
    // UTCTime: YYMMDDHHMMSSZ (RFC 5280 §4.1.2.5.1)
    const m = str.match(/^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/);
    if (!m) throw new Error("Invalid UTCTime");
    const yy = Number(m[1]);
    const year = yy >= 50 ? 1900 + yy : 2000 + yy;
    return Date.UTC(year, Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
  }
  if (node.tag === 0x18) {
    // GeneralizedTime: YYYYMMDDHHMMSS(.fff)?Z
    const m = str.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\.\d+)?Z$/);
    if (!m) throw new Error("Invalid GeneralizedTime");
    return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
  }
  throw new Error("Unsupported X.509 validity time tag");
}

function ecdsaCurveFromOID(oid) {
  if (oid === "1.2.840.10045.3.1.7") return { namedCurve: "P-256", coordLen: 32 };
  if (oid === "1.3.132.0.34") return { namedCurve: "P-384", coordLen: 48 };
  if (oid === "1.3.132.0.35") return { namedCurve: "P-521", coordLen: 66 };
  return null;
}

function ecdsaHashFromSigOID(oid) {
  if (oid === "1.2.840.10045.4.3.2") return "SHA-256";
  if (oid === "1.2.840.10045.4.3.3") return "SHA-384";
  if (oid === "1.2.840.10045.4.3.4") return "SHA-512";
  return null;
}

function derEcdsaSigToP1363(derSigBytes, coordLen) {
  const seq = readDerNode(derSigBytes, 0, derSigBytes.length);
  if (seq.tag !== 0x30 || seq.end !== derSigBytes.length) throw new Error("Invalid ECDSA DER signature");
  const kids = readDerChildren(derSigBytes, seq);
  if (kids.length !== 2 || kids[0].tag !== 0x02 || kids[1].tag !== 0x02) {
    throw new Error("Invalid ECDSA signature integers");
  }
  const out = new Uint8Array(coordLen * 2);
  for (let idx = 0; idx < 2; idx++) {
    let raw = derSigBytes.subarray(kids[idx].valueStart, kids[idx].end);
    if (raw.length === 0) throw new Error("Empty ECDSA integer");
    if (raw[0] === 0x00 && raw.length > 1) {
      raw = raw.subarray(1);
    } else if ((raw[0] & 0x80) !== 0) {
      throw new Error("Negative ECDSA integer");
    }
    if (raw.length > coordLen) throw new Error("ECDSA integer exceeds curve size");
    out.set(raw, idx * coordLen + (coordLen - raw.length));
  }
  return out;
}

function parseX509Cert(derBytes) {
  const rootSeq = readDerNode(derBytes, 0, derBytes.length);
  if (rootSeq.tag !== 0x30 || rootSeq.end !== derBytes.length) {
    throw new Error("Invalid X.509 outer SEQUENCE");
  }
  const top = readDerChildren(derBytes, rootSeq);
  if (top.length !== 3) throw new Error("X.509 must have 3 top-level fields");
  const [tbsNode, sigAlgNode, sigValNode] = top;
  if (tbsNode.tag !== 0x30 || sigAlgNode.tag !== 0x30 || sigValNode.tag !== 0x03) {
    throw new Error("Malformed X.509 top-level types");
  }

  const sigAlgChildren = readDerChildren(derBytes, sigAlgNode);
  const signatureAlgorithmOID = decodeDerOID(derBytes, sigAlgChildren[0]);
  if (sigValNode.length < 2 || derBytes[sigValNode.valueStart] !== 0x00) {
    throw new Error("Invalid X.509 signature BIT STRING");
  }
  const signatureDerBytes = derBytes.subarray(sigValNode.valueStart + 1, sigValNode.end);
  const tbsBytes = derBytes.subarray(tbsNode.start, tbsNode.end);

  const tbsKids = readDerChildren(derBytes, tbsNode);
  let idx = 0;
  let version = 1;
  if (tbsKids[idx] && tbsKids[idx].tag === 0xa0) {
    const vInt = readDerNode(derBytes, tbsKids[idx].valueStart, tbsKids[idx].end);
    if (vInt.tag !== 0x02 || vInt.length !== 1) throw new Error("Invalid X.509 version");
    version = derBytes[vInt.valueStart] + 1;
    idx++;
  }
  if (tbsKids.length < idx + 6) throw new Error("Truncated TBSCertificate");
  // serialNumber = tbsKids[idx]
  const tbsSigAlgNode = tbsKids[idx + 1];
  const issuerNode = tbsKids[idx + 2];
  const validityNode = tbsKids[idx + 3];
  const subjectNode = tbsKids[idx + 4];
  const spkiNode = tbsKids[idx + 5];

  const tbsSigAlgOID = decodeDerOID(derBytes, readDerChildren(derBytes, tbsSigAlgNode)[0]);
  if (tbsSigAlgOID !== signatureAlgorithmOID) {
    throw new Error("TBSCertificate signature algorithm mismatch");
  }
  const validityKids = readDerChildren(derBytes, validityNode);
  if (validityKids.length !== 2) throw new Error("Invalid X.509 Validity");
  const notBeforeMs = decodeDerTimeMs(derBytes, validityKids[0]);
  const notAfterMs = decodeDerTimeMs(derBytes, validityKids[1]);

  // Parse SubjectPublicKeyInfo EC curve OID
  const spkiKids = readDerChildren(derBytes, spkiNode);
  if (spkiKids.length !== 2 || spkiKids[0].tag !== 0x30) throw new Error("Invalid SPKI");
  const spkiAlgKids = readDerChildren(derBytes, spkiKids[0]);
  const pubKeyAlgOID = decodeDerOID(derBytes, spkiAlgKids[0]);
  if (pubKeyAlgOID !== "1.2.840.10045.2.1" || spkiAlgKids.length < 2) {
    throw new Error("Unsupported X.509 public key algorithm (ECDSA required)");
  }
  const curveOID = decodeDerOID(derBytes, spkiAlgKids[1]);
  const curveInfo = ecdsaCurveFromOID(curveOID);
  if (!curveInfo) throw new Error(`Unsupported EC curve OID: ${curveOID}`);

  // Parse v3 extensions [3] EXPLICIT SEQUENCE OF Extension
  const extensionOIDs = new Set();
  let isCA = false;
  for (let i = idx + 6; i < tbsKids.length; i++) {
    if (tbsKids[i].tag !== 0xa3) continue;
    const extSeq = readDerNode(derBytes, tbsKids[i].valueStart, tbsKids[i].end);
    if (extSeq.tag !== 0x30) throw new Error("Invalid X.509 extensions wrapper");
    for (const ext of readDerChildren(derBytes, extSeq)) {
      if (ext.tag !== 0x30) continue;
      const extParts = readDerChildren(derBytes, ext);
      if (extParts.length < 2) continue;
      const extOID = decodeDerOID(derBytes, extParts[0]);
      extensionOIDs.add(extOID);
      if (extOID === "2.5.29.19") {
        // BasicConstraints ::= SEQUENCE { cA BOOLEAN DEFAULT FALSE, pathLenConstraint INTEGER OPTIONAL }
        const oct = extParts[extParts.length - 1];
        if (oct.tag === 0x04) {
          const bcSeq = readDerNode(derBytes, oct.valueStart, oct.end);
          if (bcSeq.tag === 0x30) {
            const bcKids = readDerChildren(derBytes, bcSeq);
            if (bcKids.length > 0 && bcKids[0].tag === 0x01 && bcKids[0].length === 1) {
              isCA = derBytes[bcKids[0].valueStart] !== 0x00;
            }
          }
        }
      }
    }
  }

  return {
    version,
    rawBytes: derBytes,
    tbsBytes,
    signatureAlgorithmOID,
    signatureDerBytes,
    issuerDER: derBytes.subarray(issuerNode.start, issuerNode.end),
    subjectDER: derBytes.subarray(subjectNode.start, subjectNode.end),
    spkiBytes: derBytes.subarray(spkiNode.start, spkiNode.end),
    namedCurve: curveInfo.namedCurve,
    coordLen: curveInfo.coordLen,
    notBeforeMs,
    notAfterMs,
    extensionOIDs,
    isCA,
  };
}

async function verifyX509CertSignedBy(childCert, issuerCert) {
  if (!bytesEqual(childCert.issuerDER, issuerCert.subjectDER)) return false;
  const hashAlg = ecdsaHashFromSigOID(childCert.signatureAlgorithmOID);
  if (!hashAlg) return false;
  const rawSig = derEcdsaSigToP1363(childCert.signatureDerBytes, issuerCert.coordLen);
  const pubKey = await crypto.subtle.importKey(
    "spki",
    issuerCert.spkiBytes,
    { name: "ECDSA", namedCurve: issuerCert.namedCurve },
    false,
    ["verify"]
  );
  return await crypto.subtle.verify(
    { name: "ECDSA", hash: hashAlg },
    pubKey,
    rawSig,
    childCert.tbsBytes
  );
}

/**
 * Independently verifies an Apple StoreKit 2 / App Store Server JWS token:
 * 1. Strict ES256 header + 3-cert x5c chain (leaf -> intermediate -> Apple Root CA - G3).
 * 2. Pinned SHA-256 fingerprint of Apple Root CA - G3 + self-signature verification.
 * 3. Full ECDSA signature verification across leaf <- intermediate <- root + issuer/subject DN binding.
 * 4. Apple X.509 extension OID checks (WWDR intermediate 1.2.840.113635.100.6.2.1 + leaf 1.2.840.113635.100.6.11.1) & BasicConstraints.
 * 5. Certificate validity window checks at claims.signedDate.
 * 6. ECDSA P-256 SHA-256 cryptographic signature verification of JWS over header.payload.
 */
async function verifyAppleStoreKit2JWS(jws, env) {
  const parts = String(jws || "").split(".");
  if (parts.length !== 3 || !parts[0] || !parts[1] || !parts[2]) {
    throw new Error("StoreKit 2 JWS 格式无效。");
  }
  let header, claims, sigBytes;
  try {
    header = decodeBase64URLJson(parts[0]);
    claims = decodeBase64URLJson(parts[1]);
    sigBytes = decodeBase64URLToBytes(parts[2]);
  } catch {
    throw new Error("无法解码 StoreKit 2 JWS 头部或载荷。");
  }

  if (header?.alg !== "ES256") {
    throw new Error(`不支持的 JWS 签名算法（仅允许 ES256，实际：${String(header?.alg || "none")}）。`);
  }
  if (!Array.isArray(header?.x5c) || header.x5c.length !== 3) {
    throw new Error("JWS 缺少完整的 3 级 Apple x5c 证书链。");
  }
  if (sigBytes.length !== 64) {
    throw new Error("JWS ES256 签名长度无效。");
  }

  let leaf, intermediate, root;
  try {
    [leaf, intermediate, root] = header.x5c.map((b64) => parseX509Cert(decodeBase64ToBytes(b64)));
  } catch (err) {
    throw new Error(`Apple x5c 证书链解析失败：${err.message}`);
  }

  // 1. Pinned Apple Root CA - G3 SHA-256 check (only overridable in isolated unit tests)
  const expectedRootSha256 = (env?.__TEST_TRUSTED_ROOT_SHA256 || APPLE_ROOT_CA_G3_SHA256).trim().toLowerCase();
  const actualRootSha256 = await sha256BytesHex(root.rawBytes);
  if (!constantTimeEqual(actualRootSha256, expectedRootSha256)) {
    throw new Error("x5c 根证书指纹不匹配 Apple Root CA - G3。");
  }

  // 2. Apple marker OIDs & CA constraints
  if (!root.isCA || !intermediate.isCA || leaf.isCA) {
    throw new Error("Apple 证书链 CA 约束校验失败。");
  }
  if (!intermediate.extensionOIDs.has(APPLE_WWDR_INTERMEDIATE_OID)) {
    throw new Error("中间证书缺少 Apple WWDR 扩展标识 OID。");
  }
  if (!leaf.extensionOIDs.has(APPLE_APPSTORE_LEAF_OID)) {
    throw new Error("叶证书缺少 Apple App Store 交易签名扩展 OID。");
  }

  // 3. Validity window at signedDate (must be a valid recent timestamp)
  const signedDateMs = Number(claims?.signedDate);
  if (!Number.isFinite(signedDateMs) || signedDateMs < 1_577_836_800_000 || signedDateMs > Date.now() + 300_000) {
    throw new Error("交易 signedDate 缺失或超出合法时间范围。");
  }
  for (const [label, cert] of [["leaf", leaf], ["intermediate", intermediate], ["root", root]]) {
    if (signedDateMs < cert.notBeforeMs || signedDateMs > cert.notAfterMs) {
      throw new Error(`Apple ${label} 证书在交易签发时间无效或已过期。`);
    }
  }

  // 4. Cryptographic X.509 chain verification (root self-sig, root->intermediate, intermediate->leaf)
  const [rootSelfOk, interOk, leafOk] = await Promise.all([
    verifyX509CertSignedBy(root, root),
    verifyX509CertSignedBy(intermediate, root),
    verifyX509CertSignedBy(leaf, intermediate),
  ]);
  if (!rootSelfOk || !interOk || !leafOk) {
    throw new Error("Apple x5c 证书链数字签名验证失败。");
  }

  // 5. Cryptographic JWS ES256 signature verification using verified leaf public key
  if (leaf.namedCurve !== "P-256") {
    throw new Error("Apple 叶证书公钥曲线不是 P-256。");
  }
  const leafPubKey = await crypto.subtle.importKey(
    "spki",
    leaf.spkiBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"]
  );
  const signingInput = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const jwsSigValid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    leafPubKey,
    sigBytes,
    signingInput
  );
  if (!jwsSigValid) {
    throw new Error("Apple StoreKit 2 JWS 数字签名校验失败（疑似伪造或篡改）。");
  }

  return claims;
}

function decodePemPkcs8ToBytes(pem) {
  const cleaned = String(pem || "")
    .replace(/-----BEGIN [A-Z0-9 ]+-----/g, "")
    .replace(/-----END [A-Z0-9 ]+-----/g, "")
    .replace(/\s+/g, "");
  return decodeBase64ToBytes(cleaned);
}

async function createAppStoreServerApiJwt(env, bundleId) {
  const issuerId = (env.APPLE_IAP_ISSUER_ID || "").trim();
  const keyId = (env.APPLE_IAP_KEY_ID || "").trim();
  const privatePem = (env.APPLE_IAP_PRIVATE_KEY || "").trim();
  if (!issuerId || !keyId || !privatePem) return null;

  const now = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();
  const headerB64 = encodeBytesToBase64URL(enc.encode(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" })));
  const payloadB64 = encodeBytesToBase64URL(enc.encode(JSON.stringify({
    iss: issuerId,
    iat: now,
    exp: now + 300,
    aud: "appstoreconnect-v1",
    bid: bundleId,
  })));
  const signingInput = `${headerB64}.${payloadB64}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    decodePemPkcs8ToBytes(privatePem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
  const sigBuf = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(signingInput));
  return `${signingInput}.${encodeBytesToBase64URL(new Uint8Array(sigBuf))}`;
}

async function crossCheckAppleServerAPI(env, environment, bundleId, transactionID) {
  const jwt = await createAppStoreServerApiJwt(env, bundleId);
  if (!jwt) {
    if (isEnvTrue(env.REQUIRE_APPLE_SERVER_API, false)) {
      throw new Error("服务端已强制要求 Apple App Store Server API 复核，但尚未配置 APPLE_IAP_* 密钥。");
    }
    return null;
  }
  const baseHost = environment === "Production"
    ? "https://api.storekit.itunes.apple.com"
    : "https://api.storekit-sandbox.itunes.apple.com";
  const res = await fetch(`${baseHost}/inApps/v1/transactions/${encodeURIComponent(transactionID)}`, {
    method: "GET",
    headers: { Authorization: `Bearer ${jwt}` },
  });
  if (!res.ok) {
    throw new Error(`Apple App Store Server API 复核失败（HTTP ${res.status}）。`);
  }
  const data = await res.json();
  if (!data?.signedTransactionInfo) {
    throw new Error("Apple App Store Server API 未返回 signedTransactionInfo。");
  }
  return await verifyAppleStoreKit2JWS(data.signedTransactionInfo, env);
}

async function creditUserIdempotent(env, userID, externalOrderID, amountMicros, channel, note, environment = "production") {
  const existing = await env.DB.prepare(
    "SELECT * FROM payment_orders WHERE external_order_id = ?"
  ).bind(externalOrderID).first();
  if (existing && existing.user_id !== userID) {
    return { conflict: true, alreadyCredited: false, balanceMicros: 0, sandboxBalanceMicros: 0 };
  }
  const isSandbox = environment === "sandbox";

  if (existing && existing.status === "paid") {
    const u = await env.DB.prepare("SELECT balance_micros, sandbox_balance_micros FROM users WHERE id = ?").bind(userID).first();
    return {
      conflict: false,
      alreadyCredited: true,
      balanceMicros: Number(u?.balance_micros || 0),
      sandboxBalanceMicros: Number(u?.sandbox_balance_micros || 0),
    };
  }

  // Enforce isolated Sandbox cap before mutating payment_orders or balance
  if (isSandbox) {
    const capYuan = Math.max(1, Number(env.SANDBOX_BALANCE_CAP_YUAN || 50));
    const capMicros = yuanToMicros(capYuan);
    const currentUser = await env.DB.prepare("SELECT sandbox_balance_micros FROM users WHERE id = ?").bind(userID).first();
    const curSandbox = Number(currentUser?.sandbox_balance_micros || 0);
    if (curSandbox + amountMicros > capMicros) {
      return { capExceeded: true, capYuan, alreadyCredited: false, balanceMicros: 0, sandboxBalanceMicros: curSandbox };
    }
  }

  const orderID = existing?.id || `ORD-${randomCode(8)}`;
  if (existing) {
    const upd = await env.DB.prepare(
      "UPDATE payment_orders SET status = 'paid', amount_micros = ?, channel = ?, environment = ?, note = ?, paid_at = datetime('now') WHERE id = ? AND status != 'paid'"
    ).bind(amountMicros, channel, environment, note, orderID).run();
    if ((upd.meta?.changes || 0) === 0) {
      const u = await env.DB.prepare("SELECT balance_micros, sandbox_balance_micros FROM users WHERE id = ?").bind(userID).first();
      return {
        conflict: false,
        alreadyCredited: true,
        balanceMicros: Number(u?.balance_micros || 0),
        sandboxBalanceMicros: Number(u?.sandbox_balance_micros || 0),
      };
    }
  } else {
    try {
      await env.DB.prepare(
        "INSERT INTO payment_orders (id, user_id, external_order_id, amount_micros, channel, environment, status, note, paid_at) VALUES (?, ?, ?, ?, ?, ?, 'paid', ?, datetime('now'))"
      ).bind(orderID, userID, externalOrderID, amountMicros, channel, environment, note).run();
    } catch {
      const race = await env.DB.prepare("SELECT user_id FROM payment_orders WHERE external_order_id = ?").bind(externalOrderID).first();
      if (race && race.user_id !== userID) {
        return { conflict: true, alreadyCredited: false, balanceMicros: 0, sandboxBalanceMicros: 0 };
      }
      const u = await env.DB.prepare("SELECT balance_micros, sandbox_balance_micros FROM users WHERE id = ?").bind(userID).first();
      return {
        conflict: false,
        alreadyCredited: true,
        balanceMicros: Number(u?.balance_micros || 0),
        sandboxBalanceMicros: Number(u?.sandbox_balance_micros || 0),
      };
    }
  }

  if (isSandbox) {
    // STRICT ISOLATION: Sandbox tests credit ONLY sandbox_balance_micros — NEVER production balance_micros!
    await env.DB.prepare(
      "UPDATE users SET sandbox_balance_micros = sandbox_balance_micros + ?, sandbox_recharged_micros = sandbox_recharged_micros + ?, updated_at = datetime('now') WHERE id = ?"
    ).bind(amountMicros, amountMicros, userID).run();
    const fresh = await env.DB.prepare("SELECT balance_micros, sandbox_balance_micros FROM users WHERE id = ?").bind(userID).first();
    const prodBal = Number(fresh?.balance_micros || 0);
    const sandboxBal = Number(fresh?.sandbox_balance_micros || 0);
    await env.DB.prepare(
      "INSERT INTO ledger (user_id, kind, provider, model, cost_micros, balance_after_micros, note) VALUES (?, 'sandbox_apple_iap', ?, 'sandbox_recharge', ?, ?, ?)"
    ).bind(userID, channel, -amountMicros, sandboxBal, note).run();
    return { conflict: false, alreadyCredited: false, balanceMicros: prodBal, sandboxBalanceMicros: sandboxBal };
  }

  await env.DB.prepare(
    "UPDATE users SET balance_micros = balance_micros + ?, total_recharged_micros = total_recharged_micros + ?, updated_at = datetime('now') WHERE id = ?"
  ).bind(amountMicros, amountMicros, userID).run();
  const fresh = await env.DB.prepare("SELECT balance_micros, sandbox_balance_micros FROM users WHERE id = ?").bind(userID).first();
  const bal = Number(fresh?.balance_micros || 0);
  const sandboxBal = Number(fresh?.sandbox_balance_micros || 0);
  const ledgerKind = channel === "apple_iap" ? "apple_iap" : "webhook_topup";
  await env.DB.prepare(
    "INSERT INTO ledger (user_id, kind, provider, model, cost_micros, balance_after_micros, note) VALUES (?, ?, ?, 'recharge', ?, ?, ?)"
  ).bind(userID, ledgerKind, channel, -amountMicros, bal, note).run();
  return { conflict: false, alreadyCredited: false, balanceMicros: bal, sandboxBalanceMicros: sandboxBal };
}

function buildAutoCheckoutURL(request, env, orderID, userID, amountYuan, channel) {
  if (isAutoCreditPaused(env)) return null;
  const origin = new URL(request.url).origin;
  const epayBase = (env.EPAY_API_URL || "").trim().replace(/\/+$/, "");
  const epayPid = (env.EPAY_PID || "").trim();
  const epayKey = (env.EPAY_KEY || "").trim();
  if (epayBase && epayPid && epayKey) {
    const payType = channel === "alipay" ? "alipay" : "wxpay";
    const params = {
      pid: epayPid,
      type: payType,
      out_trade_no: orderID,
      notify_url: `${origin}/v1/webhooks/epay`,
      return_url: `${origin}/v1/payments/return?order=${encodeURIComponent(orderID)}`,
      name: `WUMIND 流量充值 (${userID})`,
      money: Number(amountYuan).toFixed(2),
    };
    const sign = signEpayParams(params, epayKey);
    const qs = new URLSearchParams({ ...params, sign, sign_type: "MD5" });
    return `${epayBase}/submit.php?${qs.toString()}`;
  }

  const template = (env.PAYMENT_CHECKOUT_URL || "").trim();
  if (template && /^https:\/\//i.test(template)) {
    return template
      .replaceAll("{orderID}", encodeURIComponent(orderID))
      .replaceAll("{amount}", encodeURIComponent(Number(amountYuan).toFixed(2)))
      .replaceAll("{userID}", encodeURIComponent(userID))
      .replaceAll("{channel}", encodeURIComponent(channel))
      .replaceAll("{notifyURL}", encodeURIComponent(`${origin}/v1/webhooks/payment`));
  }
  return null;
}

async function handleCreatePaymentOrder(request, env) {
  if (isAutoCreditPaused(env)) {
    return json({ error: "自动充值入账通道当前处于安全暂停状态（AUTO_CREDIT_PAUSED），请先完成沙盒验收后再开启。", code: "auto_credit_paused" }, 503);
  }
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求格式错误。" }, 400); }
  const amountMicros = yuanToMicros(body.amountYuan);
  if (amountMicros < 100_000 || amountMicros > 50_000_000_000) {
    return json({ error: "充值金额需在 ¥0.10 至 ¥50,000 之间。" }, 400);
  }
  const channel = String(body.channel || "wechat").slice(0, 32);
  const orderID = `ORD-${randomCode(8)}`;
  const amountYuan = microsToYuan(amountMicros);
  const checkoutURL = buildAutoCheckoutURL(request, env, orderID, user.id, amountYuan, channel);
  const note = checkoutURL
    ? `在线自动到账充值单（${channel}）`
    : `待入账充值单（${channel}）`;
  await env.DB.prepare(
    "INSERT INTO payment_orders (id, user_id, external_order_id, amount_micros, channel, environment, status, note) VALUES (?, ?, ?, ?, ?, 'production', 'pending', ?)"
  ).bind(orderID, user.id, orderID, amountMicros, channel, note).run();
  return json({
    id: orderID,
    amountYuan,
    channel,
    status: "pending",
    note,
    checkoutURL,
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
      checkoutURL: null,
      createdAt: r.created_at,
      paidAt: r.paid_at || null,
    })),
  });
}

async function handleGetPaymentOrderStatus(request, env, orderID) {
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  const cleanID = String(orderID || "").trim().slice(0, 64);
  if (!cleanID) return json({ error: "缺少订单号。" }, 400);
  const row = await env.DB.prepare(
    "SELECT id, amount_micros, channel, status, paid_at FROM payment_orders WHERE id = ? AND user_id = ?"
  ).bind(cleanID, user.id).first();
  if (!row) return json({ error: "未找到该充值订单。" }, 404);
  return json({
    id: row.id,
    status: row.status,
    amountYuan: microsToYuan(row.amount_micros),
    channel: row.channel,
    balanceYuan: microsToYuan(user.balance_micros),
    paidAt: row.paid_at || null,
  });
}

async function handleEpayWebhook(request, env) {
  if (isAutoCreditPaused(env)) return new Response("auto credit paused", { status: 503 });
  const epayKey = (env.EPAY_KEY || "").trim();
  if (!epayKey) return new Response("epay not configured", { status: 503 });

  const params = {};
  const url = new URL(request.url);
  for (const [k, v] of url.searchParams.entries()) params[k] = v;
  if (request.method === "POST") {
    const ct = (request.headers.get("Content-Type") || "").toLowerCase();
    const raw = await request.text();
    if (ct.includes("application/json")) {
      try {
        const obj = JSON.parse(raw);
        for (const [k, v] of Object.entries(obj || {})) params[k] = String(v ?? "");
      } catch {}
    } else {
      for (const [k, v] of new URLSearchParams(raw).entries()) params[k] = v;
    }
  }

  const providedSign = String(params.sign || "").trim().toLowerCase();
  const expectedSign = signEpayParams(params, epayKey).toLowerCase();
  if (!providedSign || !constantTimeEqual(providedSign, expectedSign)) {
    return new Response("invalid sign", { status: 401 });
  }

  const expectedPid = (env.EPAY_PID || "").trim();
  if (expectedPid && String(params.pid || "").trim() !== expectedPid) {
    return new Response("pid mismatch", { status: 401 });
  }
  if (String(params.trade_status || "") !== "TRADE_SUCCESS") {
    return new Response("success", { status: 200 });
  }

  const outTradeNo = String(params.out_trade_no || "").trim();
  const paidMicros = yuanToMicros(params.money);
  if (!outTradeNo || paidMicros <= 0) {
    return new Response("invalid order", { status: 400 });
  }

  const order = await env.DB.prepare(
    "SELECT id, user_id, amount_micros, channel FROM payment_orders WHERE id = ? OR external_order_id = ?"
  ).bind(outTradeNo, outTradeNo).first();
  if (!order) return new Response("order not found", { status: 404 });
  if (paidMicros + 10_000 < Number(order.amount_micros || 0)) {
    return new Response("amount mismatch", { status: 400 });
  }

  const channel = String(params.type || order.channel || "epay") === "wxpay" ? "wechat" : String(params.type || order.channel || "epay").slice(0, 32);
  await creditUserIdempotent(
    env,
    order.user_id,
    order.id,
    paidMicros,
    channel,
    `在线支付自动到账 · ${channel === "alipay" ? "支付宝" : "微信"} (${order.id})`,
    "production"
  );
  return new Response("success", {
    status: 200,
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}

function handlePaymentReturnPage(request) {
  const url = new URL(request.url);
  const rawOrder = String(url.searchParams.get("order") || url.searchParams.get("out_trade_no") || "").slice(0, 32);
  const safeOrder = rawOrder.replace(/[^A-Za-z0-9_-]/g, "");
  const html = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>WUMIND 充值完成</title><style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#0e1220;color:#fff;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:20px;box-sizing:border-box}.card{max-width:420px;width:100%;background:#182038;border:1px solid rgba(255,255,255,.12);border-radius:22px;padding:28px;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.35)}.badge{display:inline-block;background:#22c55e;color:#fff;font-weight:700;font-size:13px;padding:6px 14px;border-radius:999px;margin-bottom:14px}h1{font-size:21px;margin:0 0 10px}p{font-size:14px;line-height:1.65;color:#cbd5e1;margin:0 0 12px}.ord{font-family:ui-monospace,Menlo,monospace;font-size:13px;background:rgba(255,255,255,.08);padding:8px 12px;border-radius:10px;display:inline-block;margin-top:4px}</style></head><body><div class="card"><div class="badge">✓ 支付已提交</div><h1>请切回 WUMIND App</h1><p>云端收到支付回调后将自动为您入账，切回 App 后钱包余额会在 3 秒内自动刷新，无需联系人工。</p>${safeOrder ? `<div class="ord">订单号：${safeOrder}</div>` : ""}</div></body></html>`;
  return new Response(html, {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
  });
}

async function handlePaymentWebhook(request, env) {
  if (isAutoCreditPaused(env)) {
    return json({ error: "自动充值回调已暂停（AUTO_CREDIT_PAUSED）。", code: "auto_credit_paused" }, 503);
  }
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
  let userID = String(body.userID || "").trim().toUpperCase();
  const externalOrderID = String(body.externalOrderID || body.orderID || "").trim();
  const amountMicros = yuanToMicros(body.amountYuan);
  const channel = String(body.channel || "webhook").slice(0, 32);
  if (!externalOrderID || amountMicros <= 0) {
    return json({ error: "缺少 externalOrderID / orderID 或有效 amountYuan。" }, 400);
  }
  if (!userID) {
    const existingOrder = await env.DB.prepare(
      "SELECT user_id FROM payment_orders WHERE id = ? OR external_order_id = ?"
    ).bind(externalOrderID, externalOrderID).first();
    if (existingOrder?.user_id) userID = String(existingOrder.user_id).toUpperCase();
  }
  if (!userID) {
    return json({ error: "缺少 userID 且未匹配到已有充值订单。" }, 400);
  }
  const user = await env.DB.prepare("SELECT id FROM users WHERE id = ?").bind(userID).first();
  if (!user) return json({ error: `未找到用户 ${userID}` }, 404);

  const result = await creditUserIdempotent(
    env,
    userID,
    externalOrderID,
    amountMicros,
    channel,
    `自动回调入账 · ${channel} (${externalOrderID.slice(0, 24)})`,
    "production"
  );
  if (result.conflict) {
    return json({ error: "该外部订单号已被其他账号使用。" }, 409);
  }
  return json({
    ok: true,
    userID,
    alreadyCredited: result.alreadyCredited,
    balanceYuan: microsToYuan(result.balanceMicros),
  });
}

async function handleVerifyAppleIAP(request, env) {
  if (isAutoCreditPaused(env)) {
    return json({ error: "Apple 内购自动入账已暂停（AUTO_CREDIT_PAUSED），待管理员完成沙盒验收后开放。", code: "auto_credit_paused" }, 503);
  }
  const user = await authenticateUser(request, env);
  if (!user) return json({ error: "未授权。" }, 401);
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求格式错误。" }, 400); }
  const productID = String(body.productID || "").trim();
  const transactionID = String(body.transactionID || "").trim();
  const originalTransactionID = String(body.originalTransactionID || "").trim();
  const jws = String(body.jwsRepresentation || "").trim();
  if (!productID || !transactionID || !jws) {
    return json({ error: "缺少 Apple IAP 交易凭据。" }, 400);
  }
  if (!/^[0-9]{1,64}$/.test(transactionID)) {
    return json({ error: "Apple transactionID 格式无效（必须为纯数字 ID）。" }, 400);
  }

  // 1. Independent server-side cryptographic verification against Apple Root CA - G3 x5c chain & ES256 signature
  let claims;
  try {
    claims = await verifyAppleStoreKit2JWS(jws, env);
  } catch (err) {
    return json({ error: `Apple 交易签名校验未通过：${err.message}`, code: "invalid_apple_jws" }, 401);
  }

  // 2. Strict claim validation (bundleId, productId, transactionId, originalTransactionId, type, revocation, environment)
  const expectedBundle = (env.APPLE_BUNDLE_ID || "com.kriswu.shiftreminder").trim();
  if (claims.bundleId !== expectedBundle || claims.productId !== productID || String(claims.transactionId) !== transactionID) {
    return json({ error: "Apple 内购交易声明不匹配（bundleId/productId/transactionId）。" }, 400);
  }
  if (originalTransactionID && claims.originalTransactionId && String(claims.originalTransactionId) !== originalTransactionID) {
    return json({ error: "Apple 原始交易号（originalTransactionId）不匹配。" }, 400);
  }
  if (claims.type && claims.type !== "Consumable") {
    return json({ error: `不支持的内购商品类型（${String(claims.type)}）。` }, 400);
  }
  if (claims.revocationDate) {
    return json({ error: "该 Apple 交易已被退款或撤销，拒绝入账。", code: "transaction_revoked" }, 403);
  }
  const envName = String(claims.environment || "");
  if (envName !== "Production" && envName !== "Sandbox") {
    return json({ error: `拒绝不受信任的 StoreKit 交易环境（${envName || "unknown"}）。`, code: "untrusted_environment" }, 403);
  }

  // 3. Enforce environment-specific gate (Sandbox vs Production NEVER share balances)
  const isSandbox = envName === "Sandbox";
  if (isSandbox && !isAppleSandboxTestEnabled(env)) {
    return json({ error: "网关尚未开启 Apple 沙盒测试入账（ALLOW_APPLE_SANDBOX_TEST=false）。", code: "sandbox_disabled" }, 403);
  }
  if (!isSandbox && !isAppleProductionIAPEnabled(env)) {
    return json({ error: "网关尚未开启正式环境 Apple 内购入账（ALLOW_APPLE_PRODUCTION_IAP=false）。", code: "production_iap_disabled" }, 403);
  }

  // 4. Optional authoritative cross-check against Apple App Store Server API v1 (mandatory if REQUIRE_APPLE_SERVER_API=true)
  try {
    const serverClaims = await crossCheckAppleServerAPI(env, envName, expectedBundle, transactionID);
    if (serverClaims) {
      if (
        serverClaims.bundleId !== expectedBundle ||
        serverClaims.productId !== productID ||
        String(serverClaims.transactionId) !== transactionID ||
        serverClaims.revocationDate
      ) {
        return json({ error: "Apple 服务器实时复核交易状态不一致或已撤销。", code: "apple_api_mismatch" }, 403);
      }
    }
  } catch (err) {
    return json({ error: err.message, code: "apple_api_check_failed" }, 502);
  }

  const config = await loadCommercialConfig(env);
  const pack = (config.iapPacks || DEFAULT_IAP_PACKS).find((p) => p.id === productID);
  if (!pack) return json({ error: `未配置的内购商品 ID：${productID}` }, 400);

  const amountMicros = yuanToMicros(pack.creditYuan);
  const result = await creditUserIdempotent(
    env,
    user.id,
    isSandbox ? `iap_sandbox:${transactionID}` : `iap:${transactionID}`,
    amountMicros,
    isSandbox ? "apple_iap_sandbox" : "apple_iap",
    isSandbox
      ? `Apple 沙盒测试 · ${pack.title} (#${transactionID.slice(-8)})`
      : `Apple 内购 · ${pack.title} (#${transactionID.slice(-8)})`,
    isSandbox ? "sandbox" : "production"
  );

  if (result.conflict) {
    return json({ error: "该 Apple 交易号已被其他账号核销，无法重复入账。", code: "transaction_owned_by_other" }, 409);
  }
  if (result.capExceeded) {
    return json({
      error: `已达到单账号独立沙盒测试余额上限（¥${result.capYuan}），正式余额未受影响。`,
      code: "sandbox_cap_exceeded",
    }, 403);
  }

  return json({
    ok: true,
    environment: envName,
    isSandbox,
    creditedYuan: result.alreadyCredited ? 0 : microsToYuan(amountMicros),
    balanceYuan: microsToYuan(result.balanceMicros),
    sandboxBalanceYuan: microsToYuan(result.sandboxBalanceMicros),
    alreadyCredited: result.alreadyCredited,
  });
}

// MARK: - External User Registration & Login (Phone SMS OTP + WeChat OAuth, strictly fail-closed)

function normalizeMainlandPhone(raw) {
  let digits = String(raw || "").replace(/\D+/g, "");
  if (digits.startsWith("86") && digits.length === 13) digits = digits.slice(2);
  if (!/^1[3-9]\d{9}$/.test(digits)) return null;
  return digits;
}

function maskMainlandPhone(digits) {
  return `${digits.slice(0, 3)}****${digits.slice(-4)}`;
}

function generateSixDigitCode() {
  const arr = new Uint32Array(1);
  crypto.getRandomValues(arr);
  return String(arr[0] % 1_000_000).padStart(6, "0");
}

async function ensureLinkedWuMindWallet(env, existingUserID, displayName) {
  if (existingUserID) {
    const row = await env.DB.prepare("SELECT id FROM users WHERE id = ?").bind(existingUserID).first();
    if (row) return row.id;
  }
  const wmUserID = `WM-${randomCode(6, "0123456789")}`;
  const rawToken = `wm_live_${randomCode(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}`;
  const tokenHash = await sha256Hex(rawToken);
  await env.DB.prepare(
    "INSERT INTO users (id, token_hash, display_name, balance_micros) VALUES (?, ?, ?, 0)"
  ).bind(wmUserID, tokenHash, String(displayName || "外部用户").slice(0, 40)).run();
  return wmUserID;
}

async function handleAuthSMSSend(request, env) {
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求格式错误。" }, 400); }
  const phone = normalizeMainlandPhone(body.phone);
  if (!phone) {
    return json({ error: "请输入有效的 11 位中国大陆手机号。" }, 400);
  }

  const webhookURL = (env.SMS_WEBHOOK_URL || "").trim();
  const testMode = isEnvTrue(env.AUTH_TEST_MODE, false);
  if (!webhookURL && !testMode) {
    return json({
      error: "短信服务商尚未配置（管理员需在 Cloudflare Workers 设置 SMS_WEBHOOK_URL 密钥）。当前可使用本机外部访客模式体验外部权限界限。",
      code: "sms_provider_not_configured",
    }, 503);
  }

  const pepper = env.AUTH_PEPPER || "wumind_auth_pepper_v1";
  const phoneHash = await sha256Hex(`phone:${phone}:${pepper}`);
  const nowSec = Math.floor(Date.now() / 1000);

  const existing = await env.DB.prepare(
    "SELECT last_sent_epoch FROM sms_verification_codes WHERE phone_hash = ?"
  ).bind(phoneHash).first();
  if (existing && nowSec - Number(existing.last_sent_epoch || 0) < 60) {
    const wait = Math.max(1, 60 - (nowSec - Number(existing.last_sent_epoch)));
    return json({ error: `发送过于频繁，请 ${wait} 秒后重试。`, code: "sms_rate_limited", retryAfterSeconds: wait }, 429);
  }

  const code = generateSixDigitCode();
  const codeHash = await sha256Hex(`otp:${phone}:${code}:${pepper}`);
  const expiresEpoch = nowSec + 300; // 5 minutes TTL

  if (webhookURL) {
    const headers = { "Content-Type": "application/json" };
    if ((env.SMS_WEBHOOK_SECRET || "").trim()) {
      headers.Authorization = `Bearer ${(env.SMS_WEBHOOK_SECRET || "").trim()}`;
    }
    const smsRes = await fetch(webhookURL, {
      method: "POST",
      headers,
      body: JSON.stringify({ phone, code, ttlSeconds: 300, scene: "wumind_external_login" }),
    });
    if (!smsRes.ok) {
      return json({ error: `短信网关发送失败（HTTP ${smsRes.status}），请稍后重试。`, code: "sms_delivery_failed" }, 502);
    }
  }

  await env.DB.prepare(
    `INSERT INTO sms_verification_codes (phone_hash, code_hash, expires_epoch, attempts, last_sent_epoch)
     VALUES (?, ?, ?, 0, ?)
     ON CONFLICT(phone_hash) DO UPDATE SET
       code_hash = excluded.code_hash,
       expires_epoch = excluded.expires_epoch,
       attempts = 0,
       last_sent_epoch = excluded.last_sent_epoch`
  ).bind(phoneHash, codeHash, expiresEpoch, nowSec).run();

  const payload = {
    ok: true,
    maskedPhone: maskMainlandPhone(phone),
    cooldownSeconds: 60,
    expiresInSeconds: 300,
  };
  if (testMode && !webhookURL) {
    payload.testMode = true;
    payload.debugCode = code;
  }
  return json(payload);
}

async function handleAuthSMSVerify(request, env) {
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求格式错误。" }, 400); }
  const phone = normalizeMainlandPhone(body.phone);
  const code = String(body.code || "").trim();
  const nicknameInput = String(body.nickname || "").trim().slice(0, 32);
  if (!phone || !/^\d{6}$/.test(code)) {
    return json({ error: "请输入有效的 11 位手机号和 6 位数字验证码。" }, 400);
  }

  const pepper = env.AUTH_PEPPER || "wumind_auth_pepper_v1";
  const phoneHash = await sha256Hex(`phone:${phone}:${pepper}`);
  const nowSec = Math.floor(Date.now() / 1000);

  const row = await env.DB.prepare(
    "SELECT code_hash, expires_epoch, attempts FROM sms_verification_codes WHERE phone_hash = ?"
  ).bind(phoneHash).first();
  if (!row) {
    return json({ error: "请先获取短信验证码。", code: "otp_not_found" }, 401);
  }
  if (nowSec > Number(row.expires_epoch || 0)) {
    await env.DB.prepare("DELETE FROM sms_verification_codes WHERE phone_hash = ?").bind(phoneHash).run();
    return json({ error: "验证码已过期，请重新获取。", code: "otp_expired" }, 401);
  }
  if (Number(row.attempts || 0) >= 5) {
    await env.DB.prepare("DELETE FROM sms_verification_codes WHERE phone_hash = ?").bind(phoneHash).run();
    return json({ error: "错误次数过多，请重新获取验证码。", code: "otp_too_many_attempts" }, 429);
  }

  const expectedHash = await sha256Hex(`otp:${phone}:${code}:${pepper}`);
  if (!constantTimeEqual(expectedHash, String(row.code_hash || ""))) {
    await env.DB.prepare("UPDATE sms_verification_codes SET attempts = attempts + 1 WHERE phone_hash = ?")
      .bind(phoneHash).run();
    return json({ error: "短信验证码不正确。", code: "otp_invalid" }, 401);
  }

  await env.DB.prepare("DELETE FROM sms_verification_codes WHERE phone_hash = ?").bind(phoneHash).run();

  const masked = maskMainlandPhone(phone);
  const sessionToken = `wm_ext_${randomCode(36, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}`;
  const sessionHash = await sha256Hex(sessionToken);

  let userRow = await env.DB.prepare("SELECT * FROM app_users WHERE phone_hash = ?").bind(phoneHash).first();
  if (userRow) {
    const nickname = nicknameInput || userRow.nickname || `手机用户 ${phone.slice(-4)}`;
    const wmID = await ensureLinkedWuMindWallet(env, userRow.wumind_user_id, nickname);
    await env.DB.prepare(
      "UPDATE app_users SET nickname = ?, wumind_user_id = ?, session_token_hash = ?, updated_at = datetime('now') WHERE id = ?"
    ).bind(nickname, wmID, sessionHash, userRow.id).run();
    userRow = { ...userRow, nickname, wumind_user_id: wmID };
  } else {
    const appUserID = `EXT-${randomCode(8, "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ")}`;
    const nickname = nicknameInput || `手机用户 ${phone.slice(-4)}`;
    const wmID = await ensureLinkedWuMindWallet(env, null, nickname);
    await env.DB.prepare(
      `INSERT INTO app_users (id, phone_hash, phone_masked, nickname, role, login_method, wumind_user_id, session_token_hash)
       VALUES (?, ?, ?, ?, 'externalUser', 'phone', ?, ?)`
    ).bind(appUserID, phoneHash, masked, nickname, wmID, sessionHash).run();
    userRow = {
      id: appUserID,
      phone_masked: masked,
      nickname,
      role: "externalUser",
      login_method: "phone",
      wumind_user_id: wmID,
    };
  }

  return json({
    ok: true,
    sessionToken,
    user: {
      id: userRow.id,
      role: userRow.role || "externalUser",
      nickname: userRow.nickname,
      phoneMasked: userRow.phone_masked,
      loginMethod: "phone",
      wumindUserID: userRow.wumind_user_id,
    },
  });
}

async function handleAuthWeChatLogin(request, env) {
  let body;
  try { body = await request.json(); } catch { return json({ error: "请求格式错误。" }, 400); }
  const code = String(body.code || "").trim();
  const nicknameInput = String(body.nickname || "").trim().slice(0, 32);
  if (!code || code.length > 256) {
    return json({ error: "缺少微信授权码（code）。" }, 400);
  }

  const appID = (env.WECHAT_APP_ID || "").trim();
  const appSecret = (env.WECHAT_APP_SECRET || "").trim();
  const testMode = isEnvTrue(env.AUTH_TEST_MODE, false);
  if ((!appID || !appSecret) && !testMode) {
    return json({
      error: "微信开放平台登录尚未配置（管理员需在 Cloudflare Workers 设置 WECHAT_APP_ID 与 WECHAT_APP_SECRET，并在微信开放平台绑定 App Bundle ID）。",
      code: "wechat_not_configured",
    }, 503);
  }

  let openid = "";
  let wxNickname = nicknameInput || "微信用户";
  if (appID && appSecret) {
    const tokenURL = `https://api.weixin.qq.com/sns/oauth2/access_token?appid=${encodeURIComponent(appID)}&secret=${encodeURIComponent(appSecret)}&code=${encodeURIComponent(code)}&grant_type=authorization_code`;
    const wxRes = await fetch(tokenURL, { method: "GET" });
    if (!wxRes.ok) {
      return json({ error: `微信授权校验失败（HTTP ${wxRes.status}）。`, code: "wechat_exchange_failed" }, 502);
    }
    const wxJson = await wxRes.json();
    if (!wxJson?.openid) {
      return json({ error: wxJson?.errmsg ? `微信拒绝授权：${wxJson.errmsg}` : "微信授权码无效或已过期。", code: "wechat_invalid_code" }, 401);
    }
    openid = String(wxJson.openid);
    if (wxJson.access_token) {
      try {
        const infoRes = await fetch(`https://api.weixin.qq.com/sns/userinfo?access_token=${encodeURIComponent(wxJson.access_token)}&openid=${encodeURIComponent(openid)}&lang=zh_CN`);
        if (infoRes.ok) {
          const info = await infoRes.json();
          if (info?.nickname) wxNickname = String(info.nickname).slice(0, 32);
        }
      } catch {}
    }
  } else {
    // Explicit AUTH_TEST_MODE only
    openid = `wx_test_${code}`;
  }

  const pepper = env.AUTH_PEPPER || "wumind_auth_pepper_v1";
  const openidHash = await sha256Hex(`wx:${openid}:${pepper}`);
  const sessionToken = `wm_ext_${randomCode(36, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}`;
  const sessionHash = await sha256Hex(sessionToken);

  let userRow = await env.DB.prepare("SELECT * FROM app_users WHERE wechat_openid_hash = ?").bind(openidHash).first();
  if (userRow) {
    const nickname = nicknameInput || userRow.nickname || wxNickname;
    const wmID = await ensureLinkedWuMindWallet(env, userRow.wumind_user_id, nickname);
    await env.DB.prepare(
      "UPDATE app_users SET nickname = ?, wumind_user_id = ?, session_token_hash = ?, updated_at = datetime('now') WHERE id = ?"
    ).bind(nickname, wmID, sessionHash, userRow.id).run();
    userRow = { ...userRow, nickname, wumind_user_id: wmID };
  } else {
    const appUserID = `EXT-${randomCode(8, "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ")}`;
    const wmID = await ensureLinkedWuMindWallet(env, null, wxNickname);
    await env.DB.prepare(
      `INSERT INTO app_users (id, wechat_openid_hash, nickname, role, login_method, wumind_user_id, session_token_hash)
       VALUES (?, ?, ?, 'externalUser', 'wechat', ?, ?)`
    ).bind(appUserID, openidHash, wxNickname, wmID, sessionHash).run();
    userRow = {
      id: appUserID,
      phone_masked: "",
      nickname: wxNickname,
      role: "externalUser",
      login_method: "wechat",
      wumind_user_id: wmID,
    };
  }

  return json({
    ok: true,
    sessionToken,
    user: {
      id: userRow.id,
      role: userRow.role || "externalUser",
      nickname: userRow.nickname,
      phoneMasked: userRow.phone_masked || "",
      loginMethod: "wechat",
      wumindUserID: userRow.wumind_user_id,
    },
  });
}

async function handleAuthMe(request, env) {
  const auth = request.headers.get("Authorization") || "";
  const match = auth.match(/^Bearer\s+(.+)$/i);
  if (!match) return json({ error: "未登录。" }, 401);
  const tokenHash = await sha256Hex(match[1].trim());
  const row = await env.DB.prepare("SELECT * FROM app_users WHERE session_token_hash = ?").bind(tokenHash).first();
  if (!row) return json({ error: "登录会话已失效，请重新登录。" }, 401);
  return json({
    ok: true,
    user: {
      id: row.id,
      role: row.role || "externalUser",
      nickname: row.nickname,
      phoneMasked: row.phone_masked || "",
      loginMethod: row.login_method || "phone",
      wumindUserID: row.wumind_user_id,
    },
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
      if (request.method === "POST" && path === "/v1/auth/sms/send") {
        return await handleAuthSMSSend(request, env);
      }
      if (request.method === "POST" && path === "/v1/auth/sms/verify") {
        return await handleAuthSMSVerify(request, env);
      }
      if (request.method === "POST" && path === "/v1/auth/wechat/login") {
        return await handleAuthWeChatLogin(request, env);
      }
      if (request.method === "GET" && path === "/v1/auth/me") {
        return await handleAuthMe(request, env);
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
      if (request.method === "GET" && path.startsWith("/v1/payments/orders/")) {
        return await handleGetPaymentOrderStatus(request, env, decodeURIComponent(path.slice("/v1/payments/orders/".length)));
      }
      if (request.method === "GET" && path === "/v1/payments/return") {
        return handlePaymentReturnPage(request);
      }
      if ((request.method === "GET" || request.method === "POST") && path === "/v1/webhooks/epay") {
        return await handleEpayWebhook(request, env);
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
