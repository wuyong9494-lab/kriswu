/**
 * Non-destructive, idempotent in-place D1 schema upgrader.
 * Safely adds new columns and tables to an existing WUMIND D1 database
 * without ever dropping tables or wiping existing user balances/ledgers.
 */

const upgradedDBs = new WeakSet();

async function ensureColumn(db, table, column, definition) {
  const info = await db.prepare(`PRAGMA table_info(${table})`).all();
  const cols = new Set((info.results || []).map((r) => String(r.name || "").toLowerCase()));
  if (cols.has(column.toLowerCase())) return;
  try {
    await db.prepare(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`).run();
  } catch (err) {
    const msg = String(err?.message || err || "").toLowerCase();
    if (!msg.includes("duplicate column")) throw err;
  }
}

export async function ensureSchemaUpgraded(env) {
  if (!env?.DB) return;
  if (upgradedDBs.has(env.DB)) return;

  // 1. Non-destructive additive columns on existing tables
  await ensureColumn(env.DB, "users", "reserved_micros", "INTEGER NOT NULL DEFAULT 0");
  await ensureColumn(env.DB, "users", "sandbox_reserved_micros", "INTEGER NOT NULL DEFAULT 0");
  await ensureColumn(env.DB, "users", "purchased_recharged_micros", "INTEGER NOT NULL DEFAULT 0");
  await ensureColumn(env.DB, "users", "admin_granted_micros", "INTEGER NOT NULL DEFAULT 0");
  await ensureColumn(env.DB, "users", "upstream_spent_micros", "INTEGER NOT NULL DEFAULT 0");
  await ensureColumn(env.DB, "users", "billing_exempt", "INTEGER NOT NULL DEFAULT 0");
  await ensureColumn(env.DB, "users", "admin_daily_cost_cap_micros", "INTEGER NOT NULL DEFAULT 0");
  await ensureColumn(env.DB, "users", "registered_role", "TEXT NOT NULL DEFAULT 'user'");

  await ensureColumn(env.DB, "ledger", "balance_before_micros", "INTEGER");
  await ensureColumn(env.DB, "ledger", "environment", "TEXT NOT NULL DEFAULT 'production'");
  await ensureColumn(env.DB, "ledger", "operator_id", "TEXT");
  await ensureColumn(env.DB, "ledger", "reservation_id", "TEXT");
  await ensureColumn(env.DB, "ledger", "upstream_cost_micros", "INTEGER NOT NULL DEFAULT 0");

  // 2. Non-destructive additive tables
  const ddls = [
    `CREATE TABLE IF NOT EXISTS credit_reservations (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      idempotency_key TEXT,
      kind TEXT NOT NULL,
      model_id TEXT NOT NULL DEFAULT '',
      environment TEXT NOT NULL DEFAULT 'production',
      reserved_micros INTEGER NOT NULL,
      actual_micros INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'reserved',
      response_json TEXT,
      error_note TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      settled_at TEXT,
      expires_epoch INTEGER NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS admin_credit_audit (
      id TEXT PRIMARY KEY,
      idempotency_key TEXT UNIQUE,
      operator_id TEXT NOT NULL,
      target_user_id TEXT NOT NULL,
      environment TEXT NOT NULL DEFAULT 'production',
      amount_micros INTEGER NOT NULL,
      balance_before_micros INTEGER NOT NULL,
      balance_after_micros INTEGER NOT NULL,
      note TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE TABLE IF NOT EXISTS model_catalog (
      model_id TEXT PRIMARY KEY,
      upstream_provider TEXT NOT NULL,
      vendor TEXT NOT NULL DEFAULT '',
      display_name TEXT NOT NULL,
      capabilities_json TEXT NOT NULL DEFAULT '["chat"]',
      pricing_mode TEXT NOT NULL DEFAULT 'token',
      input_price_per_million REAL NOT NULL DEFAULT 0,
      output_price_per_million REAL NOT NULL DEFAULT 0,
      unit_price_yuan REAL NOT NULL DEFAULT 0,
      official_reference_note TEXT NOT NULL DEFAULT '',
      supports_thinking INTEGER NOT NULL DEFAULT 0,
      supported_params_json TEXT NOT NULL DEFAULT '{}',
      enabled INTEGER NOT NULL DEFAULT 0,
      probe_status TEXT NOT NULL DEFAULT 'unverified',
      probe_endpoint TEXT NOT NULL DEFAULT '',
      probe_message TEXT NOT NULL DEFAULT '',
      probe_latency_ms INTEGER NOT NULL DEFAULT 0,
      last_probed_at TEXT,
      discovered_from TEXT NOT NULL DEFAULT '',
      deprecated INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE TABLE IF NOT EXISTS video_jobs (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      upstream_job_id TEXT NOT NULL,
      upstream_route TEXT NOT NULL,
      upstream_base_url TEXT NOT NULL DEFAULT '',
      model_id TEXT NOT NULL,
      reservation_id TEXT NOT NULL,
      seconds INTEGER NOT NULL DEFAULT 4,
      size TEXT NOT NULL DEFAULT '1280x720',
      status TEXT NOT NULL DEFAULT 'queued',
      progress INTEGER NOT NULL DEFAULT 0,
      download_url TEXT,
      error_message TEXT,
      is_admin_exempt INTEGER NOT NULL DEFAULT 0,
      estimated_cost_micros INTEGER NOT NULL DEFAULT 0,
      work_id TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE TABLE IF NOT EXISTS user_works (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      work_type TEXT NOT NULL,
      title TEXT NOT NULL DEFAULT '',
      prompt TEXT NOT NULL DEFAULT '',
      model_id TEXT NOT NULL DEFAULT '',
      params_json TEXT NOT NULL DEFAULT '{}',
      reference_assets_json TEXT NOT NULL DEFAULT '[]',
      status TEXT NOT NULL DEFAULT 'queued',
      progress INTEGER NOT NULL DEFAULT 0,
      upstream_job_id TEXT,
      idempotency_key TEXT,
      error_message TEXT,
      preview_base64 TEXT,
      asset_mime TEXT,
      asset_base64 TEXT,
      project_json TEXT,
      timing_json TEXT,
      version_number INTEGER NOT NULL DEFAULT 1,
      parent_work_id TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE INDEX IF NOT EXISTS idx_reservations_user_status ON credit_reservations(user_id, status, expires_epoch)`,
    `CREATE UNIQUE INDEX IF NOT EXISTS idx_reservations_user_idem ON credit_reservations(user_id, idempotency_key) WHERE idempotency_key IS NOT NULL`,
    `CREATE INDEX IF NOT EXISTS idx_admin_audit_target ON admin_credit_audit(target_user_id, created_at DESC)`,
    `CREATE INDEX IF NOT EXISTS idx_model_catalog_enabled ON model_catalog(enabled, deprecated, probe_status)`,
    `CREATE INDEX IF NOT EXISTS idx_video_jobs_user ON video_jobs(user_id, created_at DESC)`,
    `CREATE INDEX IF NOT EXISTS idx_user_works_owner_type ON user_works(user_id, work_type, updated_at DESC)`,
    `CREATE UNIQUE INDEX IF NOT EXISTS idx_user_works_owner_idem ON user_works(user_id, idempotency_key) WHERE idempotency_key IS NOT NULL`,
  ];

  for (const sql of ddls) {
    await env.DB.prepare(sql).run();
  }

  // Upgrade existing video_jobs table if created before exempt/work columns existed
  await ensureColumn(env.DB, "video_jobs", "is_admin_exempt", "INTEGER NOT NULL DEFAULT 0");
  await ensureColumn(env.DB, "video_jobs", "estimated_cost_micros", "INTEGER NOT NULL DEFAULT 0");
  await ensureColumn(env.DB, "video_jobs", "work_id", "TEXT");

  upgradedDBs.add(env.DB);
}
