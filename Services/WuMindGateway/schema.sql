-- WUMIND Billing Gateway D1 Schema (Non-Destructive Additive Migration Safe)
-- All monetary balances are stored as integer micro-yuan (1,000,000 = ¥1.00) to avoid floating-point drift.
-- Existing databases are upgraded lazily in-place via ensureSchemaUpgraded(env); NEVER drop or rebuild tables.

CREATE TABLE IF NOT EXISTS config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,                 -- Short readable user ID, e.g. WM-849201
  token_hash TEXT NOT NULL UNIQUE,     -- SHA-256 hex of bearer user token
  display_name TEXT NOT NULL DEFAULT '',
  balance_micros INTEGER NOT NULL DEFAULT 0,
  reserved_micros INTEGER NOT NULL DEFAULT 0,          -- Active in-flight pre-reserved production credit holds
  total_recharged_micros INTEGER NOT NULL DEFAULT 0,
  purchased_recharged_micros INTEGER NOT NULL DEFAULT 0, -- Verified real purchases (Apple IAP / verified payment webhooks)
  admin_granted_micros INTEGER NOT NULL DEFAULT 0,     -- Admin manual grants & vouchers (strictly separated from real purchases)
  total_spent_micros INTEGER NOT NULL DEFAULT 0,
  upstream_spent_micros INTEGER NOT NULL DEFAULT 0,    -- Total tracked upstream cost (including billing_exempt admin calls)
  billing_exempt INTEGER NOT NULL DEFAULT 0,           -- Server-verified admin fee-waiver flag (0 = normal paid user, 1 = exempt admin)
  admin_daily_cost_cap_micros INTEGER NOT NULL DEFAULT 0, -- Configurable daily upstream cost cap for exempt admins (0 = global default)
  registered_role TEXT NOT NULL DEFAULT 'user',        -- 'rosterMember' | 'externalUser' | 'admin' | 'user'
  sandbox_balance_micros INTEGER NOT NULL DEFAULT 0,   -- Isolated TestFlight / Apple Sandbox test balance (never mixed with real production funds)
  sandbox_reserved_micros INTEGER NOT NULL DEFAULT 0,
  sandbox_recharged_micros INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS vouchers (
  code TEXT PRIMARY KEY,               -- e.g. WM-8K3P-9Q2M-4V7R
  amount_micros INTEGER NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  redeemed_by TEXT,
  redeemed_at TEXT
);

CREATE TABLE IF NOT EXISTS ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  kind TEXT NOT NULL,                  -- 'chat' | 'image' | 'image_edit' | 'video' | 'realtime_voice' | 'web_search' | 'admin_exempt_*' | 'redeem' | 'admin_grant' | 'sandbox_admin_grant' | 'apple_iap' | 'sandbox_apple_iap' | 'apple_iap_refund' | 'sandbox_apple_iap_refund' | 'webhook_topup' | 'welcome'
  provider TEXT NOT NULL DEFAULT '',
  model TEXT NOT NULL DEFAULT '',
  prompt_tokens INTEGER NOT NULL DEFAULT 0,
  completion_tokens INTEGER NOT NULL DEFAULT 0,
  reasoning_tokens INTEGER NOT NULL DEFAULT 0,
  cost_micros INTEGER NOT NULL DEFAULT 0,       -- positive for user wallet debit, negative for credit, 0 for billing_exempt
  upstream_cost_micros INTEGER NOT NULL DEFAULT 0, -- actual upstream cost tracked even when user is billing_exempt
  balance_before_micros INTEGER,
  balance_after_micros INTEGER NOT NULL DEFAULT 0,
  environment TEXT NOT NULL DEFAULT 'production', -- 'production' | 'sandbox'
  operator_id TEXT,
  reservation_id TEXT,
  note TEXT NOT NULL DEFAULT '',
  external_order_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS credit_reservations (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  idempotency_key TEXT,
  kind TEXT NOT NULL,                  -- 'chat' | 'image' | 'image_edit' | 'video' | 'web_search'
  model_id TEXT NOT NULL DEFAULT '',
  environment TEXT NOT NULL DEFAULT 'production',
  reserved_micros INTEGER NOT NULL,
  actual_micros INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'reserved', -- 'reserved' | 'settled' | 'released' | 'expired'
  response_json TEXT,
  error_note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  settled_at TEXT,
  expires_epoch INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS admin_credit_audit (
  id TEXT PRIMARY KEY,
  idempotency_key TEXT UNIQUE,
  operator_id TEXT NOT NULL,
  target_user_id TEXT NOT NULL,
  environment TEXT NOT NULL DEFAULT 'production', -- 'production' | 'sandbox'
  amount_micros INTEGER NOT NULL,
  balance_before_micros INTEGER NOT NULL,
  balance_after_micros INTEGER NOT NULL,
  note TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS model_catalog (
  model_id TEXT PRIMARY KEY,
  upstream_provider TEXT NOT NULL,     -- 'aihubmix' | 'openAI' | 'deepSeek' | 'gemini' | 'claude' | 'grok'
  vendor TEXT NOT NULL DEFAULT '',     -- 'OpenAI' | 'Anthropic' | 'Google' | 'DeepSeek' | 'xAI' | 'Qwen' | 'ByteDance' | 'Kling' | 'MiniMax' | 'Other'
  display_name TEXT NOT NULL,
  capabilities_json TEXT NOT NULL DEFAULT '["chat"]', -- JSON array of 'chat' | 'text_to_image' | 'image_edit' | 'video' | 'realtime_voice'
  pricing_mode TEXT NOT NULL DEFAULT 'token', -- 'token' | 'per_image' | 'per_second' | 'per_minute'
  input_price_per_million REAL NOT NULL DEFAULT 0,
  output_price_per_million REAL NOT NULL DEFAULT 0,
  cache_price_per_million REAL NOT NULL DEFAULT 0,
  unit_price_yuan REAL NOT NULL DEFAULT 0,
  official_input_usd_per_million REAL,
  official_output_usd_per_million REAL,
  official_cache_usd_per_million REAL,
  official_unit_usd REAL,
  fx_usd_to_cny REAL NOT NULL DEFAULT 7.25,
  markup_multiplier REAL NOT NULL DEFAULT 1.5,
  pricing_status TEXT NOT NULL DEFAULT 'pending_pricing', -- 'priced' | 'pending_pricing'
  price_version INTEGER NOT NULL DEFAULT 1,
  last_synced_at TEXT,
  official_reference_note TEXT NOT NULL DEFAULT '',
  supports_thinking INTEGER NOT NULL DEFAULT 0,
  supported_params_json TEXT NOT NULL DEFAULT '{}',
  enabled INTEGER NOT NULL DEFAULT 0,
  probe_status TEXT NOT NULL DEFAULT 'unverified', -- 'unverified' | 'verified' | 'permission_denied' | 'unsupported_params' | 'deprecated' | 'error'
  probe_endpoint TEXT NOT NULL DEFAULT '',
  probe_message TEXT NOT NULL DEFAULT '',
  probe_latency_ms INTEGER NOT NULL DEFAULT 0,
  last_probed_at TEXT,
  discovered_from TEXT NOT NULL DEFAULT '',
  deprecated INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS pricing_versions (
  version INTEGER PRIMARY KEY AUTOINCREMENT,
  fx_usd_to_cny REAL NOT NULL,
  markup_multiplier REAL NOT NULL,
  source_url TEXT NOT NULL DEFAULT 'https://aihubmix.com/models',
  changed_count INTEGER NOT NULL DEFAULT 0,
  pending_count INTEGER NOT NULL DEFAULT 0,
  snapshot_json TEXT NOT NULL DEFAULT '{}',
  operator_id TEXT NOT NULL DEFAULT 'admin',
  approved_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS video_jobs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  upstream_job_id TEXT NOT NULL,
  upstream_route TEXT NOT NULL,
  upstream_base_url TEXT NOT NULL DEFAULT '',
  model_id TEXT NOT NULL,
  reservation_id TEXT NOT NULL,
  seconds INTEGER NOT NULL DEFAULT 4,
  size TEXT NOT NULL DEFAULT '1280x720',
  status TEXT NOT NULL DEFAULT 'queued', -- 'queued' | 'in_progress' | 'completed' | 'failed'
  progress INTEGER NOT NULL DEFAULT 0,
  download_url TEXT,
  error_message TEXT,
  is_admin_exempt INTEGER NOT NULL DEFAULT 0,
  estimated_cost_micros INTEGER NOT NULL DEFAULT 0,
  price_version INTEGER NOT NULL DEFAULT 1,
  work_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS user_works (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  work_type TEXT NOT NULL,               -- 'image' | 'video' | 'ppt' | 'scene3d'
  title TEXT NOT NULL DEFAULT '',
  prompt TEXT NOT NULL DEFAULT '',
  model_id TEXT NOT NULL DEFAULT '',
  params_json TEXT NOT NULL DEFAULT '{}',
  reference_assets_json TEXT NOT NULL DEFAULT '[]',
  status TEXT NOT NULL DEFAULT 'queued', -- 'queued' | 'in_progress' | 'completed' | 'failed'
  progress INTEGER NOT NULL DEFAULT 0,
  upstream_job_id TEXT,
  idempotency_key TEXT,
  error_message TEXT,
  preview_base64 TEXT,
  asset_mime TEXT,
  asset_base64 TEXT,
  asset_object_key TEXT,
  asset_size_bytes INTEGER NOT NULL DEFAULT 0,
  asset_sha256 TEXT,
  asset_sync_state TEXT NOT NULL DEFAULT 'local_only', -- 'local_only' | 'uploading' | 'synced' | 'failed' | 'storage_unconfigured'
  project_json TEXT,
  project_object_key TEXT,
  project_size_bytes INTEGER NOT NULL DEFAULT 0,
  timing_json TEXT,
  version_number INTEGER NOT NULL DEFAULT 1,
  parent_work_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS schedules (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  title TEXT NOT NULL,
  prompt TEXT NOT NULL,
  model_id TEXT NOT NULL DEFAULT 'deepseek-reasoner',
  interval_minutes INTEGER NOT NULL DEFAULT 1440,
  enabled INTEGER NOT NULL DEFAULT 1,
  next_run_epoch INTEGER NOT NULL,
  last_run_at TEXT,
  last_answer TEXT,
  last_cost_micros INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS device_tokens (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  device_name TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS sync_snapshots (
  user_id TEXT PRIMARY KEY,
  encrypted_payload TEXT NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  device_name TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS pairing_codes (
  code TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  expires_epoch INTEGER NOT NULL,
  claimed INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS payment_orders (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  external_order_id TEXT UNIQUE,
  amount_micros INTEGER NOT NULL,
  channel TEXT NOT NULL DEFAULT 'qr',
  environment TEXT NOT NULL DEFAULT 'production', -- 'production' | 'sandbox'
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending' | 'paid' | 'failed' | 'refunded'
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  paid_at TEXT
);

CREATE TABLE IF NOT EXISTS app_users (
  id TEXT PRIMARY KEY,
  phone_hash TEXT UNIQUE,
  phone_masked TEXT NOT NULL DEFAULT '',
  wechat_openid_hash TEXT UNIQUE,
  nickname TEXT NOT NULL DEFAULT '外部用户',
  role TEXT NOT NULL DEFAULT 'externalUser', -- 'externalUser' | 'rosterMember'
  login_method TEXT NOT NULL DEFAULT 'phone', -- 'phone' | 'wechat'
  wumind_user_id TEXT,
  session_token_hash TEXT UNIQUE,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS sms_verification_codes (
  phone_hash TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  expires_epoch INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_sent_epoch INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_ledger_user_created ON ledger(user_id, id DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_ledger_external_order ON ledger(external_order_id) WHERE external_order_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_ledger_reservation_id ON ledger(reservation_id) WHERE reservation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reservations_user_status ON credit_reservations(user_id, status, expires_epoch);
CREATE UNIQUE INDEX IF NOT EXISTS idx_reservations_user_idem ON credit_reservations(user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_admin_audit_target ON admin_credit_audit(target_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_model_catalog_enabled ON model_catalog(enabled, deprecated, probe_status);
CREATE INDEX IF NOT EXISTS idx_video_jobs_user ON video_jobs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_works_owner_type ON user_works(user_id, work_type, updated_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_works_owner_idem ON user_works(user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_vouchers_created ON vouchers(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_schedules_due ON schedules(enabled, next_run_epoch);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_orders_user ON payment_orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_users_session ON app_users(session_token_hash);
