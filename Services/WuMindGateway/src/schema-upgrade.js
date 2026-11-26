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
      asset_object_key TEXT,
      asset_size_bytes INTEGER NOT NULL DEFAULT 0,
      asset_sha256 TEXT,
      asset_sync_state TEXT NOT NULL DEFAULT 'local_only',
      project_json TEXT,
      project_object_key TEXT,
      project_size_bytes INTEGER NOT NULL DEFAULT 0,
      timing_json TEXT,
      version_number INTEGER NOT NULL DEFAULT 1,
      parent_work_id TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE TABLE IF NOT EXISTS pricing_versions (
      version INTEGER PRIMARY KEY AUTOINCREMENT,
      fx_usd_to_cny REAL NOT NULL,
      markup_multiplier REAL NOT NULL,
      source_url TEXT NOT NULL DEFAULT 'https://aihubmix.com/models',
      changed_count INTEGER NOT NULL DEFAULT 0,
      pending_count INTEGER NOT NULL DEFAULT 0,
      snapshot_json TEXT NOT NULL DEFAULT '{}',
      operator_id TEXT NOT NULL DEFAULT 'admin',
      approved_at TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `CREATE UNIQUE INDEX IF NOT EXISTS idx_ledger_reservation_id ON ledger(reservation_id) WHERE reservation_id IS NOT NULL`,
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

  // Upgrade existing model_catalog table for unified 1.5x official-base server pricing
  await ensureColumn(env.DB, "model_catalog", "cache_price_per_million", "REAL NOT NULL DEFAULT 0");
  await ensureColumn(env.DB, "model_catalog", "official_input_usd_per_million", "REAL");
  await ensureColumn(env.DB, "model_catalog", "official_output_usd_per_million", "REAL");
  await ensureColumn(env.DB, "model_catalog", "official_cache_usd_per_million", "REAL");
  await ensureColumn(env.DB, "model_catalog", "official_unit_usd", "REAL");
  await ensureColumn(env.DB, "model_catalog", "fx_usd_to_cny", "REAL NOT NULL DEFAULT 7.25");
  await ensureColumn(env.DB, "model_catalog", "markup_multiplier", "REAL NOT NULL DEFAULT 1.5");
  await ensureColumn(env.DB, "model_catalog", "pricing_status", "TEXT NOT NULL DEFAULT 'pending_pricing'");
  await ensureColumn(env.DB, "model_catalog", "price_version", "INTEGER NOT NULL DEFAULT 1");
  await ensureColumn(env.DB, "model_catalog", "last_synced_at", "TEXT");

  // Upgrade existing credit_reservations & video_jobs tables to lock submission-time price_version
  await ensureColumn(env.DB, "credit_reservations", "price_version", "INTEGER NOT NULL DEFAULT 1");
  await ensureColumn(env.DB, "video_jobs", "is_admin_exempt", "INTEGER NOT NULL DEFAULT 0");
  await ensureColumn(env.DB, "video_jobs", "estimated_cost_micros", "INTEGER NOT NULL DEFAULT 0");
  await ensureColumn(env.DB, "video_jobs", "price_version", "INTEGER NOT NULL DEFAULT 1");
  await ensureColumn(env.DB, "video_jobs", "work_id", "TEXT");

  // Upgrade existing user_works table for private Cloudflare R2 object storage metadata
  await ensureColumn(env.DB, "user_works", "asset_object_key", "TEXT");
  await ensureColumn(env.DB, "user_works", "asset_size_bytes", "INTEGER NOT NULL DEFAULT 0");
  await ensureColumn(env.DB, "user_works", "asset_sha256", "TEXT");
  await ensureColumn(env.DB, "user_works", "asset_sync_state", "TEXT NOT NULL DEFAULT 'local_only'");
  await ensureColumn(env.DB, "user_works", "project_object_key", "TEXT");
  await ensureColumn(env.DB, "user_works", "project_size_bytes", "INTEGER NOT NULL DEFAULT 0");

  upgradedDBs.add(env.DB);
}
