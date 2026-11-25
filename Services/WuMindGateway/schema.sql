-- WUMIND Billing Gateway D1 Schema
-- All monetary balances are stored as integer micro-yuan (1,000,000 = ¥1.00) to avoid floating-point drift.

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
  total_recharged_micros INTEGER NOT NULL DEFAULT 0,
  total_spent_micros INTEGER NOT NULL DEFAULT 0,
  sandbox_balance_micros INTEGER NOT NULL DEFAULT 0,   -- Isolated TestFlight / Apple Sandbox test balance (never mixed with real production funds)
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
  kind TEXT NOT NULL,                  -- 'chat' | 'redeem' | 'admin_topup' | 'welcome'
  provider TEXT NOT NULL DEFAULT '',
  model TEXT NOT NULL DEFAULT '',
  prompt_tokens INTEGER NOT NULL DEFAULT 0,
  completion_tokens INTEGER NOT NULL DEFAULT 0,
  reasoning_tokens INTEGER NOT NULL DEFAULT 0,
  cost_micros INTEGER NOT NULL DEFAULT 0,       -- positive for debit ('chat'), negative or amount for credit
  balance_after_micros INTEGER NOT NULL DEFAULT 0,
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
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
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending' | 'paid' | 'failed'
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
CREATE INDEX IF NOT EXISTS idx_vouchers_created ON vouchers(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_schedules_due ON schedules(enabled, next_run_epoch);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_orders_user ON payment_orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_users_session ON app_users(session_token_hash);
