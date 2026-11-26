/**
 * WUMIND Billing Safety Kernel:
 * 1. Deterministic RFC 4122 UUID binding between WUMIND account ID (WM-XXXXXX) and StoreKit 2 appAccountToken.
 * 2. Atomic Pre-Request Credit Reservation -> Post-Usage Actual Settlement -> Failure/Disconnect Release.
 * 3. Server-side chat output token cap & media unit cost ceilings preventing overdrafts & balance drift.
 * 4. Idempotent Apple StoreKit 2 Refund / Revocation clawback (App Store Server Notifications V2 + inline verify).
 * 5. Admin user lookup by WM- ID + audited manual credit with strict separation from real IAP purchases.
 */

const MICROS_PER_YUAN = 1_000_000;

function microsToYuan(micros) {
  return Math.round((Number(micros || 0) / MICROS_PER_YUAN) * 10000) / 10000;
}

function yuanToMicros(yuan) {
  const n = Number(yuan);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.round(n * MICROS_PER_YUAN);
}

/**
 * Computes a deterministic RFC 4122 UUID (version 5 layout from SHA-256) for a WUMIND user ID.
 * Matches Swift `WuMindGatewayClient.accountUUID(for:)` bit-for-bit so Apple StoreKit 2
 * `appAccountToken` cryptographically binds each transaction to the exact WM- account.
 */
export async function wumindAccountUUID(userID) {
  const normalized = String(userID || "").trim().toUpperCase();
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`wumind:iap:account:${normalized}`))
  );
  const bytes = digest.slice(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

export function extractIdempotencyKey(request, body = null) {
  const headerKey = (request.headers.get("Idempotency-Key") || request.headers.get("X-Idempotency-Key") || "").trim();
  const bodyKey = body && typeof body.idempotencyKey === "string" ? body.idempotencyKey.trim() : "";
  const raw = headerKey || bodyKey;
  if (!raw) return null;
  return raw.replace(/[^A-Za-z0-9_.:-]/g, "").slice(0, 96) || null;
}

/**
 * Reclaims stale reservations whose Worker isolate crashed or timed out beyond expires_epoch.
 */
export async function releaseExpiredReservations(env, userID = null) {
  const nowEpoch = Math.floor(Date.now() / 1000);
  const query = userID
    ? env.DB.prepare(
        "SELECT id, user_id, reserved_micros FROM credit_reservations WHERE user_id = ? AND status = 'reserved' AND expires_epoch <= ? LIMIT 25"
      ).bind(userID, nowEpoch)
    : env.DB.prepare(
        "SELECT id, user_id, reserved_micros FROM credit_reservations WHERE status = 'reserved' AND expires_epoch <= ? LIMIT 50"
      ).bind(nowEpoch);

  const stale = await query.all();
  for (const row of stale.results || []) {
    await releaseReservationAtomic(env, {
      reservationID: row.id,
      userID: row.user_id,
      reason: "reservation_expired",
      targetStatus: "expired",
    });
  }
}

/**
 * Computes exact pre-request credit reservation & server-enforced max_tokens cap for a chat turn.
 * Guarantees a turn can NEVER exceed the user's available balance!
 */
export function computeChatReservationPlan(pricingItem, promptTokens, availableMicros, requestedMaxTokens, deepThinking, env) {
  const inputPrice = Math.max(0, Number(pricingItem.inputPricePerMillion || 0));
  const outputPrice = Math.max(0, Number(pricingItem.outputPricePerMillion || 0));
  const safePromptTokens = Math.max(1, Number(promptTokens || 1));

  // Hard server-side output ceiling (prevents runaway single-turn spending even for high-balance users)
  const defaultHardCap = Math.max(256, Math.min(32768, parseInt(env.CHAT_MAX_OUTPUT_TOKENS || (deepThinking ? "8192" : "4096"), 10) || 4096));
  const desiredMaxOut = requestedMaxTokens
    ? Math.max(128, Math.min(defaultHardCap, parseInt(requestedMaxTokens, 10) || defaultHardCap))
    : defaultHardCap;

  // Input cost + 15% tokenizer safety margin
  const estimatedInputMicros = Math.ceil(safePromptTokens * inputPrice * 1.15);
  // Require enough balance for input + at least 256 output tokens (or minimum ¥0.0001)
  const minOutputTokens = 256;
  const minRequiredMicros = Math.max(100, estimatedInputMicros + Math.ceil(minOutputTokens * outputPrice));

  if (availableMicros < minRequiredMicros) {
    return {
      insufficient: true,
      availableMicros,
      requiredMinMicros: minRequiredMicros,
      estimatedInputMicros,
      maxOutputTokens: 0,
      reserveMicros: 0,
    };
  }

  const remainingForOutput = Math.max(0, availableMicros - estimatedInputMicros);
  const affordableOutputTokens = outputPrice > 0
    ? Math.floor(remainingForOutput / outputPrice)
    : desiredMaxOut;
  const cappedOutputTokens = Math.max(minOutputTokens, Math.min(desiredMaxOut, affordableOutputTokens));
  const reserveMicros = Math.min(
    availableMicros,
    Math.max(100, estimatedInputMicros + Math.ceil(cappedOutputTokens * outputPrice))
  );

  return {
    insufficient: false,
    availableMicros,
    requiredMinMicros: minRequiredMicros,
    estimatedInputMicros,
    maxOutputTokens: cappedOutputTokens,
    reserveMicros,
  };
}

/**
 * Atomically reserves `reserveMicros` from `users.balance_micros - users.reserved_micros`.
 * Enforces idempotency_key deduplication (replaying settled responses or rejecting in-flight duplicates).
 */
export async function reserveCreditAtomic(env, {
  userID,
  idempotencyKey = null,
  kind,
  modelID = "",
  reserveMicros,
  ttlSeconds = 900,
  randomCode,
}) {
  await releaseExpiredReservations(env, userID);

  if (idempotencyKey) {
    const existing = await env.DB.prepare(
      "SELECT * FROM credit_reservations WHERE user_id = ? AND idempotency_key = ?"
    ).bind(userID, idempotencyKey).first();
    if (existing) {
      if (existing.status === "settled") {
        let cached = null;
        try { cached = existing.response_json ? JSON.parse(existing.response_json) : null; } catch {}
        return { duplicateSettled: true, reservation: existing, cachedResponse: cached };
      }
      if (existing.status === "reserved") {
        return { duplicateInFlight: true, reservation: existing };
      }
      // If previously released/expired, allow caller to retry cleanly by clearing the old idempotency key
      await env.DB.prepare(
        "UPDATE credit_reservations SET idempotency_key = NULL WHERE id = ? AND status IN ('released', 'expired')"
      ).bind(existing.id).run();
    }
  }

  const amount = Math.max(0, Math.round(Number(reserveMicros || 0)));
  const reservationID = `RES-${randomCode(12)}`;
  const expiresEpoch = Math.floor(Date.now() / 1000) + Math.max(60, ttlSeconds);

  // Single atomic transaction: insert reservation ONLY if user has sufficient available balance,
  // then increment reserved_micros ONLY if the reservation row was inserted.
  // If any statement fails (including unique idempotency_key collision), D1 rolls back the entire batch.
  try {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO credit_reservations
         (id, user_id, idempotency_key, kind, model_id, environment, reserved_micros, actual_micros, status, expires_epoch)
         SELECT ?, ?, ?, ?, ?, 'production', ?, 0, 'reserved', ?
         FROM users
         WHERE id = ? AND (balance_micros - reserved_micros) >= ?`
      ).bind(reservationID, userID, idempotencyKey, kind, modelID, amount, expiresEpoch, userID, amount),
      env.DB.prepare(
        `UPDATE users
         SET reserved_micros = reserved_micros + ?, updated_at = datetime('now')
         WHERE id = ? AND EXISTS (
           SELECT 1 FROM credit_reservations
           WHERE id = ? AND user_id = ? AND status = 'reserved'
         )`
      ).bind(amount, userID, reservationID, userID),
    ]);
  } catch (err) {
    if (idempotencyKey) {
      const race = await env.DB.prepare(
        "SELECT * FROM credit_reservations WHERE user_id = ? AND idempotency_key = ?"
      ).bind(userID, idempotencyKey).first();
      if (race) {
        if (race.status === "settled") {
          let cached = null;
          try { cached = race.response_json ? JSON.parse(race.response_json) : null; } catch {}
          return { duplicateSettled: true, reservation: race, cachedResponse: cached };
        }
        if (race.status === "reserved") {
          return { duplicateInFlight: true, reservation: race };
        }
      }
    }
    throw err;
  }

  const created = await env.DB.prepare(
    "SELECT id FROM credit_reservations WHERE id = ? AND user_id = ? AND status = 'reserved'"
  ).bind(reservationID, userID).first();

  if (!created) {
    const u = await env.DB.prepare("SELECT balance_micros, reserved_micros FROM users WHERE id = ?").bind(userID).first();
    const bal = Number(u?.balance_micros || 0);
    const res = Number(u?.reserved_micros || 0);
    return {
      insufficient: true,
      availableMicros: Math.max(0, bal - res),
      balanceMicros: bal,
      reservedMicros: res,
      requiredMicros: amount,
    };
  }

  return {
    ok: true,
    reservationID,
    reservedMicros: amount,
    expiresEpoch,
  };
}

/**
 * Atomically settles a reservation against actual upstream usage inside ONE single ACID D1 batch transaction:
 *   1. Conditionally inserts the single unique ledger row (guarded by `status = 'reserved'` + unique `ledger(reservation_id)`)
 *   2. Conditionally deducts `users.balance_micros`, releases `users.reserved_micros`, and increments `total_spent_micros`
 *   3. Conditionally transitions `credit_reservations.status` from `'reserved'` -> `'settled'`
 *
 * If ANY statement fails mid-write, D1 rolls back ALL three writes cleanly so retrying succeeds without drift or double-debit.
 * If two concurrent settlements race, SQLite/D1 serializes the transactions and the second sees `status != 'reserved'`,
 * applying zero changes and returning `alreadySettled: true`.
 */
export async function settleReservationAtomic(env, {
  reservationID,
  userID,
  actualMicros,
  kind = "chat",
  provider = "",
  model = "",
  promptTokens = 0,
  completionTokens = 0,
  reasoningTokens = 0,
  note = "",
  responsePayload = null,
}) {
  const resRow = await env.DB.prepare(
    "SELECT * FROM credit_reservations WHERE id = ? AND user_id = ?"
  ).bind(reservationID, userID).first();
  if (!resRow) throw new Error(`Reservation ${reservationID} not found`);

  if (resRow.status === "settled") {
    const u = await env.DB.prepare("SELECT balance_micros, reserved_micros FROM users WHERE id = ?").bind(userID).first();
    return {
      alreadySettled: true,
      reservationID,
      promptTokens,
      completionTokens,
      reasoningTokens,
      reservedYuan: microsToYuan(resRow.reserved_micros),
      costYuan: microsToYuan(resRow.actual_micros),
      releasedYuan: microsToYuan(Math.max(0, resRow.reserved_micros - resRow.actual_micros)),
      balanceYuan: microsToYuan(u?.balance_micros || 0),
      availableYuan: microsToYuan(Math.max(0, Number(u?.balance_micros || 0) - Number(u?.reserved_micros || 0))),
    };
  }
  if (resRow.status !== "reserved") {
    throw new Error(`Reservation ${reservationID} is not active (status=${resRow.status})`);
  }

  const reserved = Number(resRow.reserved_micros || 0);
  const rawActual = Math.max(0, Math.round(Number(actualMicros || 0)));
  const settled = Math.min(rawActual, reserved);
  const waivedOverage = Math.max(0, rawActual - settled);
  const cleanNote = waivedOverage > 0
    ? `${String(note || "").trim()}（已按预留封顶结算，免收超额 ¥${microsToYuan(waivedOverage)}）`.trim().slice(0, 160)
    : String(note || "").trim().slice(0, 160);
  const responseJSON = responsePayload ? JSON.stringify(responsePayload).slice(0, 500_000) : null;

  // Execute ledger insert, user balance/reserved update, and reservation status transition in ONE atomic transaction!
  const batchStmts = [];
  if (settled > 0) {
    batchStmts.push(
      env.DB.prepare(
        `INSERT INTO ledger
         (user_id, kind, provider, model, prompt_tokens, completion_tokens, reasoning_tokens, cost_micros, balance_before_micros, balance_after_micros, environment, reservation_id, note)
         SELECT
           u.id, ?, ?, ?, ?, ?, ?,
           MIN(?, u.balance_micros),
           u.balance_micros,
           u.balance_micros - MIN(?, u.balance_micros),
           'production', ?, ?
         FROM users u
         WHERE u.id = ?
           AND EXISTS (
             SELECT 1 FROM credit_reservations r
             WHERE r.id = ? AND r.user_id = u.id AND r.status = 'reserved'
           )
           AND MIN(?, u.balance_micros) > 0`
      ).bind(
        kind,
        provider,
        model,
        promptTokens,
        completionTokens,
        reasoningTokens,
        settled,
        settled,
        reservationID,
        cleanNote,
        userID,
        reservationID,
        settled
      )
    );
  }

  batchStmts.push(
    env.DB.prepare(
      `UPDATE users
       SET balance_micros = balance_micros - MIN(?, balance_micros),
           reserved_micros = MAX(0, reserved_micros - ?),
           total_spent_micros = total_spent_micros + MIN(?, balance_micros),
           updated_at = datetime('now')
       WHERE id = ?
         AND EXISTS (
           SELECT 1 FROM credit_reservations r
           WHERE r.id = ? AND r.user_id = users.id AND r.status = 'reserved'
         )`
    ).bind(settled, reserved, settled, userID, reservationID),
    env.DB.prepare(
      `UPDATE credit_reservations
       SET status = 'settled',
           actual_micros = COALESCE((SELECT cost_micros FROM ledger WHERE reservation_id = ?), 0),
           response_json = ?,
           settled_at = datetime('now')
       WHERE id = ? AND user_id = ? AND status = 'reserved'`
    ).bind(reservationID, responseJSON, reservationID, userID)
  );

  let batchResults = [];
  try {
    batchResults = await env.DB.batch(batchStmts);
  } catch (err) {
    // Handle unique reservation_id race if two callers somehow raced across replicas;
    // re-throw on genuine mid-transaction DB fault so callers know it rolled back cleanly!
    const afterRace = await env.DB.prepare(
      "SELECT status, reserved_micros, actual_micros FROM credit_reservations WHERE id = ? AND user_id = ?"
    ).bind(reservationID, userID).first();
    if (afterRace?.status === "settled") {
      const u = await env.DB.prepare("SELECT balance_micros, reserved_micros FROM users WHERE id = ?").bind(userID).first();
      return {
        alreadySettled: true,
        reservationID,
        promptTokens,
        completionTokens,
        reasoningTokens,
        reservedYuan: microsToYuan(afterRace.reserved_micros),
        costYuan: microsToYuan(afterRace.actual_micros),
        releasedYuan: microsToYuan(Math.max(0, Number(afterRace.reserved_micros || 0) - Number(afterRace.actual_micros || 0))),
        balanceYuan: microsToYuan(u?.balance_micros || 0),
        availableYuan: microsToYuan(Math.max(0, Number(u?.balance_micros || 0) - Number(u?.reserved_micros || 0))),
      };
    }
    throw err;
  }

  const lastResult = Array.isArray(batchResults) && batchResults.length === batchStmts.length
    ? batchResults[batchResults.length - 1]
    : null;
  const reservationClaimChanges = lastResult?.meta?.changes;

  const [finalResRow, afterUser] = await Promise.all([
    env.DB.prepare("SELECT status, reserved_micros, actual_micros FROM credit_reservations WHERE id = ? AND user_id = ?")
      .bind(reservationID, userID).first(),
    env.DB.prepare("SELECT balance_micros, reserved_micros FROM users WHERE id = ?").bind(userID).first(),
  ]);

  const finalBal = Number(afterUser?.balance_micros || 0);
  const finalRes = Number(afterUser?.reserved_micros || 0);
  const actualDeducted = Number(finalResRow?.actual_micros || 0);

  if (reservationClaimChanges === 0) {
    return {
      alreadySettled: true,
      reservationID,
      promptTokens,
      completionTokens,
      reasoningTokens,
      reservedYuan: microsToYuan(reserved),
      costYuan: microsToYuan(actualDeducted),
      releasedYuan: microsToYuan(Math.max(0, reserved - actualDeducted)),
      balanceYuan: microsToYuan(finalBal),
      availableYuan: microsToYuan(Math.max(0, finalBal - finalRes)),
    };
  }

  return {
    alreadySettled: false,
    reservationID,
    promptTokens,
    completionTokens,
    reasoningTokens,
    reservedYuan: microsToYuan(reserved),
    costYuan: microsToYuan(actualDeducted),
    releasedYuan: microsToYuan(Math.max(0, reserved - actualDeducted)),
    balanceYuan: microsToYuan(finalBal),
    availableYuan: microsToYuan(Math.max(0, finalBal - finalRes)),
  };
}

/**
 * Atomically releases an active reservation (zero balance deduction, zero ledger debit)
 * in ONE single ACID D1 batch transaction.
 */
export async function releaseReservationAtomic(env, {
  reservationID,
  userID,
  reason = "upstream_failed",
  targetStatus = "released",
}) {
  if (!reservationID || !userID) return { released: false };
  const row = await env.DB.prepare(
    "SELECT reserved_micros, status FROM credit_reservations WHERE id = ? AND user_id = ?"
  ).bind(reservationID, userID).first();
  if (!row || row.status !== "reserved") return { released: false };

  const reservedAmount = Number(row.reserved_micros || 0);
  const cleanReason = String(reason || "").slice(0, 200);

  const batchResults = await env.DB.batch([
    env.DB.prepare(
      `UPDATE users
       SET reserved_micros = MAX(0, reserved_micros - ?), updated_at = datetime('now')
       WHERE id = ? AND EXISTS (
         SELECT 1 FROM credit_reservations
         WHERE id = ? AND user_id = ? AND status = 'reserved'
       )`
    ).bind(reservedAmount, userID, reservationID, userID),
    env.DB.prepare(
      `UPDATE credit_reservations
       SET status = ?, error_note = ?, settled_at = datetime('now')
       WHERE id = ? AND user_id = ? AND status = 'reserved'`
    ).bind(targetStatus, cleanReason, reservationID, userID),
  ]);

  const claimChanges = Array.isArray(batchResults) && batchResults.length === 2
    ? batchResults[1]?.meta?.changes
    : undefined;

  if (claimChanges === 0) return { released: false };
  return { released: true, releasedYuan: microsToYuan(reservedAmount) };
}

/**
 * Idempotently handles an Apple StoreKit 2 refund or revocation (from App Store Server Notifications V2
 * or inline revocationDate detection). Strictly isolates Sandbox vs Production balances.
 */
export async function processAppleIAPRevocation(env, {
  transactionID,
  environment = "Production",
  revocationReason = "",
}) {
  const isSandbox = String(environment) === "Sandbox";
  const creditOrderID = isSandbox ? `iap_sandbox:${transactionID}` : `iap:${transactionID}`;
  const refundOrderID = isSandbox ? `iap_sandbox_refund:${transactionID}` : `iap_refund:${transactionID}`;

  // Already clawed back? Idempotent return!
  const existingRefund = await env.DB.prepare(
    "SELECT id, user_id, cost_micros, balance_after_micros FROM ledger WHERE external_order_id = ?"
  ).bind(refundOrderID).first();
  if (existingRefund) {
    return {
      ok: true,
      alreadyProcessed: true,
      userID: existingRefund.user_id,
      environment: isSandbox ? "sandbox" : "production",
      clawedBackYuan: microsToYuan(existingRefund.cost_micros),
      balanceAfterYuan: microsToYuan(existingRefund.balance_after_micros),
    };
  }

  // Locate original credited order/ledger row
  const originalCredit = await env.DB.prepare(
    "SELECT user_id, cost_micros FROM ledger WHERE external_order_id = ?"
  ).bind(creditOrderID).first();
  if (!originalCredit) {
    return {
      ok: true,
      notPreviouslyCredited: true,
      environment: isSandbox ? "sandbox" : "production",
      clawedBackYuan: 0,
    };
  }

  const userID = originalCredit.user_id;
  const originalCreditedMicros = Math.abs(Number(originalCredit.cost_micros || 0));
  const user = await env.DB.prepare("SELECT balance_micros, sandbox_balance_micros FROM users WHERE id = ?").bind(userID).first();
  if (!user) return { ok: false, error: "user_not_found" };

  const currentBucket = isSandbox ? Number(user.sandbox_balance_micros || 0) : Number(user.balance_micros || 0);
  const actualClawback = Math.min(currentBucket, originalCreditedMicros);
  const shortfall = Math.max(0, originalCreditedMicros - actualClawback);
  const balanceAfter = currentBucket - actualClawback;
  const kind = isSandbox ? "sandbox_apple_iap_refund" : "apple_iap_refund";
  const reasonTag = revocationReason ? ` · reason=${revocationReason}` : "";
  const note = shortfall > 0
    ? `Apple ${isSandbox ? "沙盒" : ""}交易退款/撤销扣回 (#${transactionID.slice(-8)}${reasonTag} · 实扣 ¥${microsToYuan(actualClawback)}，已消耗缺口 ¥${microsToYuan(shortfall)})`
    : `Apple ${isSandbox ? "沙盒" : ""}交易退款/撤销全额扣回 (#${transactionID.slice(-8)}${reasonTag})`;

  const insertRefundLedger = env.DB.prepare(
    `INSERT INTO ledger
     (user_id, kind, provider, model, cost_micros, balance_before_micros, balance_after_micros, environment, note, external_order_id)
     VALUES (?, ?, ?, 'refund', ?, ?, ?, ?, ?, ?)`
  ).bind(
    userID,
    kind,
    isSandbox ? "apple_iap_sandbox" : "apple_iap",
    actualClawback,
    currentBucket,
    balanceAfter,
    isSandbox ? "sandbox" : "production",
    note,
    refundOrderID
  );

  const deductUser = isSandbox
    ? env.DB.prepare(
        "UPDATE users SET sandbox_balance_micros = MAX(0, sandbox_balance_micros - ?), updated_at = datetime('now') WHERE id = ?"
      ).bind(actualClawback, userID)
    : env.DB.prepare(
        "UPDATE users SET balance_micros = MAX(0, balance_micros - ?), updated_at = datetime('now') WHERE id = ?"
      ).bind(actualClawback, userID);

  const markOrderRefunded = env.DB.prepare(
    "UPDATE payment_orders SET status = 'refunded', note = ? WHERE external_order_id = ?"
  ).bind(note, creditOrderID);

  try {
    await env.DB.batch([insertRefundLedger, deductUser, markOrderRefunded]);
  } catch (err) {
    const race = await env.DB.prepare(
      "SELECT id, user_id, cost_micros, balance_after_micros FROM ledger WHERE external_order_id = ?"
    ).bind(refundOrderID).first();
    if (race) {
      return {
        ok: true,
        alreadyProcessed: true,
        userID: race.user_id,
        environment: isSandbox ? "sandbox" : "production",
        clawedBackYuan: microsToYuan(race.cost_micros),
        balanceAfterYuan: microsToYuan(race.balance_after_micros),
      };
    }
    throw err;
  }

  return {
    ok: true,
    alreadyProcessed: false,
    userID,
    environment: isSandbox ? "sandbox" : "production",
    originalCreditedYuan: microsToYuan(originalCreditedMicros),
    clawedBackYuan: microsToYuan(actualClawback),
    shortfallYuan: microsToYuan(shortfall),
    balanceBeforeYuan: microsToYuan(currentBucket),
    balanceAfterYuan: microsToYuan(balanceAfter),
  };
}

/**
 * Handles Apple App Store Server Notifications V2 (`POST /v1/webhooks/apple-notifications`).
 * Cryptographically verifies BOTH the outer `signedPayload` JWS AND inner `signedTransactionInfo` JWS.
 */
export async function handleAppleServerNotificationV2(request, env, { json, verifyAppleStoreKit2JWS }) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "通知 JSON 格式无效。" }, 400);
  }
  const signedPayload = String(body?.signedPayload || "").trim();
  if (!signedPayload) {
    return json({ error: "缺少 Apple signedPayload。" }, 400);
  }

  let notification;
  try {
    notification = await verifyAppleStoreKit2JWS(signedPayload, env);
  } catch (err) {
    return json({ error: `Apple Server Notification 签名校验失败：${err.message}`, code: "invalid_apple_notification" }, 401);
  }

  const notificationType = String(notification.notificationType || "").toUpperCase();
  const expectedBundle = (env.APPLE_BUNDLE_ID || "com.kriswu.shiftreminder").trim();
  const dataObj = notification.data || {};
  if (dataObj.bundleId && dataObj.bundleId !== expectedBundle) {
    return json({ error: "Apple 通知 bundleId 不匹配。", code: "bundle_mismatch" }, 400);
  }

  if (notificationType !== "REFUND" && notificationType !== "REVOKE") {
    return json({
      ok: true,
      ignored: true,
      notificationType,
      notificationUUID: notification.notificationUUID || null,
    });
  }

  const signedTx = String(dataObj.signedTransactionInfo || "").trim();
  if (!signedTx) {
    return json({ error: "退款/撤销通知缺少 signedTransactionInfo。" }, 400);
  }

  let txClaims;
  try {
    txClaims = await verifyAppleStoreKit2JWS(signedTx, env);
  } catch (err) {
    return json({ error: `内层交易 JWS 校验失败：${err.message}`, code: "invalid_inner_transaction" }, 401);
  }

  if (txClaims.bundleId !== expectedBundle) {
    return json({ error: "内层交易 bundleId 不匹配。" }, 400);
  }
  const txID = String(txClaims.transactionId || "").trim();
  const envName = String(txClaims.environment || dataObj.environment || "");
  if (!txID || (envName !== "Production" && envName !== "Sandbox")) {
    return json({ error: "内层交易缺少合法 transactionId 或 environment。" }, 400);
  }

  const result = await processAppleIAPRevocation(env, {
    transactionID: txID,
    environment: envName,
    revocationReason: String(txClaims.revocationReason ?? notificationType),
  });

  return json({
    ...result,
    notificationType,
    transactionID: txID,
  });
}

/**
 * Admin-only lookup for ANY registered WM- user (exact match or prefix search).
 */
export async function handleAdminLookupUser(request, env, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可查询用户信息（管理员密钥无效或缺失）。", code: "admin_forbidden" }, 403);
  }
  const url = new URL(request.url);
  const rawQuery = String(url.searchParams.get("userID") || url.searchParams.get("q") || "").trim().toUpperCase();
  if (!rawQuery) {
    return json({ error: "请输入要查找的 WM- 用户 ID。" }, 400);
  }

  let user = await env.DB.prepare("SELECT * FROM users WHERE UPPER(id) = ?").bind(rawQuery).first();
  if (!user && rawQuery.length >= 3) {
    const matches = await env.DB.prepare(
      "SELECT * FROM users WHERE UPPER(id) LIKE ? OR UPPER(display_name) LIKE ? ORDER BY updated_at DESC LIMIT 10"
    ).bind(`${rawQuery}%`, `%${rawQuery}%`).all();
    const list = matches.results || [];
    if (list.length === 1) {
      user = list[0];
    } else if (list.length > 1) {
      return json({
        found: false,
        multiple: true,
        matches: list.map((u) => ({
          userID: u.id,
          displayName: u.display_name || "",
          balanceYuan: microsToYuan(u.balance_micros),
          sandboxBalanceYuan: microsToYuan(u.sandbox_balance_micros || 0),
          purchasedRechargedYuan: microsToYuan(u.purchased_recharged_micros || 0),
          adminGrantedYuan: microsToYuan(u.admin_granted_micros || 0),
          totalSpentYuan: microsToYuan(u.total_spent_micros),
          createdAt: u.created_at,
        })),
      });
    }
  }

  if (!user) {
    return json({ error: `未找到已注册用户 ${rawQuery}，请核对 WM- 账号 ID。`, code: "user_not_found" }, 404);
  }

  await releaseExpiredReservations(env, user.id);
  const fresh = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(user.id).first();
  const [recentLedger, recentAudits] = await Promise.all([
    env.DB.prepare(
      "SELECT id, kind, provider, model, cost_micros, balance_before_micros, balance_after_micros, environment, operator_id, note, created_at FROM ledger WHERE user_id = ? ORDER BY id DESC LIMIT 10"
    ).bind(user.id).all(),
    env.DB.prepare(
      "SELECT id, operator_id, environment, amount_micros, balance_before_micros, balance_after_micros, note, created_at FROM admin_credit_audit WHERE target_user_id = ? ORDER BY created_at DESC LIMIT 10"
    ).bind(user.id).all(),
  ]);

  const bal = Number(fresh.balance_micros || 0);
  const res = Number(fresh.reserved_micros || 0);
  return json({
    found: true,
    user: {
      userID: fresh.id,
      displayName: fresh.display_name || "",
      balanceYuan: microsToYuan(bal),
      reservedYuan: microsToYuan(res),
      availableYuan: microsToYuan(Math.max(0, bal - res)),
      sandboxBalanceYuan: microsToYuan(fresh.sandbox_balance_micros || 0),
      totalRechargedYuan: microsToYuan(fresh.total_recharged_micros || 0),
      purchasedRechargedYuan: microsToYuan(fresh.purchased_recharged_micros || 0),
      adminGrantedYuan: microsToYuan(fresh.admin_granted_micros || 0),
      totalSpentYuan: microsToYuan(fresh.total_spent_micros || 0),
      createdAt: fresh.created_at,
      updatedAt: fresh.updated_at,
    },
    recentLedger: (recentLedger.results || []).map((r) => ({
      id: r.id,
      kind: r.kind,
      provider: r.provider,
      model: r.model,
      costYuan: microsToYuan(r.cost_micros),
      balanceBeforeYuan: r.balance_before_micros != null ? microsToYuan(r.balance_before_micros) : null,
      balanceAfterYuan: microsToYuan(r.balance_after_micros),
      environment: r.environment || "production",
      operatorID: r.operator_id || null,
      note: r.note,
      createdAt: r.created_at,
    })),
    recentAdminCredits: (recentAudits.results || []).map((a) => ({
      id: a.id,
      operatorID: a.operator_id,
      environment: a.environment,
      amountYuan: microsToYuan(a.amount_micros),
      balanceBeforeYuan: microsToYuan(a.balance_before_micros),
      balanceAfterYuan: microsToYuan(a.balance_after_micros),
      note: a.note,
      createdAt: a.created_at,
    })),
  });
}

/**
 * Admin-only manual balance credit (`POST /v1/admin/topup`):
 * - Strict admin secret check (normal users get 403)
 * - Single-grant & daily cap limits
 * - Idempotency key preventing duplicate submissions
 * - Explicit environment ('production' | 'sandbox')
 * - Full audit trail (operator, timestamp, before/after balance, memo)
 * - Strictly accounted as `admin_grant` / `admin_granted_micros`, SEPARATE from real IAP purchases (`purchased_recharged_micros`)!
 */
export async function handleAdminManualCredit(request, env, { json, verifyAdminSecret, randomCode }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可手动加余额（管理员密钥无效或缺失）。", code: "admin_forbidden" }, 403);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "请求格式错误。" }, 400);
  }

  const userID = String(body.userID || "").trim().toUpperCase();
  const amountMicros = yuanToMicros(body.amountYuan);
  const environment = String(body.environment || "production").trim().toLowerCase() === "sandbox" ? "sandbox" : "production";
  const note = String(body.note || "管理员手动赠额").trim().slice(0, 160);
  const operatorID = String(body.operatorID || request.headers.get("X-WuMind-Operator") || "admin").trim().slice(0, 64) || "admin";
  const idempotencyKey = extractIdempotencyKey(request, body);

  if (!userID || !/^WM-[A-Z0-9]{4,16}$/.test(userID)) {
    return json({ error: "请输入合法的目标用户 ID（例如 WM-849201）。", code: "invalid_user_id" }, 400);
  }
  if (amountMicros < 100_000) {
    return json({ error: "手动加余额单笔至少 ¥0.10。", code: "amount_too_small" }, 400);
  }

  const maxSingleYuan = Math.max(1, Number(env.ADMIN_TOPUP_MAX_SINGLE_YUAN || 500));
  const dailyCapYuan = Math.max(maxSingleYuan, Number(env.ADMIN_TOPUP_DAILY_CAP_YUAN || 5000));
  if (amountMicros > yuanToMicros(maxSingleYuan)) {
    return json({
      error: `单笔手动加余额不能超过 ¥${maxSingleYuan.toFixed(2)} 上限。`,
      code: "admin_single_limit_exceeded",
      maxSingleYuan,
    }, 400);
  }

  // Idempotency deduplication check BEFORE touching balances
  if (idempotencyKey) {
    const existingAudit = await env.DB.prepare(
      "SELECT * FROM admin_credit_audit WHERE idempotency_key = ?"
    ).bind(idempotencyKey).first();
    if (existingAudit) {
      if (existingAudit.target_user_id !== userID) {
        return json({ error: "该幂等请求号已用于其他用户，已拒绝重复入账。", code: "idempotency_conflict" }, 409);
      }
      const u = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(userID).first();
      return json({
        ok: true,
        alreadyApplied: true,
        auditID: existingAudit.id,
        userID: existingAudit.target_user_id,
        environment: existingAudit.environment,
        operatorID: existingAudit.operator_id,
        amountYuan: microsToYuan(existingAudit.amount_micros),
        balanceBeforeYuan: microsToYuan(existingAudit.balance_before_micros),
        balanceAfterYuan: microsToYuan(existingAudit.balance_after_micros),
        balanceYuan: microsToYuan(u?.balance_micros || 0),
        sandboxBalanceYuan: microsToYuan(u?.sandbox_balance_micros || 0),
        totalRechargedYuan: microsToYuan(u?.total_recharged_micros || 0),
        purchasedRechargedYuan: microsToYuan(u?.purchased_recharged_micros || 0),
        adminGrantedYuan: microsToYuan(u?.admin_granted_micros || 0),
        note: existingAudit.note,
        createdAt: existingAudit.created_at,
      });
    }
  }

  const existing = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(userID).first();
  if (!existing) return json({ error: `未找到已注册用户 ${userID}`, code: "user_not_found" }, 404);

  // Enforce daily admin grant cap
  const todayAgg = await env.DB.prepare(
    "SELECT COALESCE(SUM(amount_micros), 0) AS total_today FROM admin_credit_audit WHERE date(created_at) = date('now')"
  ).first();
  const todayTotal = Number(todayAgg?.total_today || 0);
  if (todayTotal + amountMicros > yuanToMicros(dailyCapYuan)) {
    return json({
      error: `超出每日管理员手动赠额上限（今日已赠 ¥${microsToYuan(todayTotal)}，上限 ¥${dailyCapYuan.toFixed(2)}）。`,
      code: "admin_daily_limit_exceeded",
    }, 429);
  }

  const isSandbox = environment === "sandbox";
  const balanceBefore = isSandbox ? Number(existing.sandbox_balance_micros || 0) : Number(existing.balance_micros || 0);
  const balanceAfter = balanceBefore + amountMicros;
  const auditID = `ADM-${randomCode(10)}`;
  const ledgerKind = isSandbox ? "sandbox_admin_grant" : "admin_grant";
  const externalRef = idempotencyKey ? `admin_grant:${idempotencyKey}` : `admin_grant:${auditID}`;

  const updateUserStmt = isSandbox
    ? env.DB.prepare(
        "UPDATE users SET sandbox_balance_micros = sandbox_balance_micros + ?, sandbox_recharged_micros = sandbox_recharged_micros + ?, updated_at = datetime('now') WHERE id = ?"
      ).bind(amountMicros, amountMicros, userID)
    : env.DB.prepare(
        // Separate accounting: increments admin_granted_micros, NEVER purchased_recharged_micros!
        "UPDATE users SET balance_micros = balance_micros + ?, admin_granted_micros = admin_granted_micros + ?, total_recharged_micros = total_recharged_micros + ?, updated_at = datetime('now') WHERE id = ?"
      ).bind(amountMicros, amountMicros, amountMicros, userID);

  const insertAuditStmt = env.DB.prepare(
    `INSERT INTO admin_credit_audit
     (id, idempotency_key, operator_id, target_user_id, environment, amount_micros, balance_before_micros, balance_after_micros, note)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(auditID, idempotencyKey, operatorID, userID, environment, amountMicros, balanceBefore, balanceAfter, note);

  const insertLedgerStmt = env.DB.prepare(
    `INSERT INTO ledger
     (user_id, kind, provider, model, cost_micros, balance_before_micros, balance_after_micros, environment, operator_id, note, external_order_id)
     VALUES (?, ?, 'admin', 'manual_grant', ?, ?, ?, ?, ?, ?, ?)`
  ).bind(userID, ledgerKind, -amountMicros, balanceBefore, balanceAfter, environment, operatorID, note, externalRef);

  try {
    await env.DB.batch([insertAuditStmt, updateUserStmt, insertLedgerStmt]);
  } catch (err) {
    if (idempotencyKey) {
      const race = await env.DB.prepare(
        "SELECT * FROM admin_credit_audit WHERE idempotency_key = ?"
      ).bind(idempotencyKey).first();
      if (race && race.target_user_id === userID) {
        const u = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(userID).first();
        return json({
          ok: true,
          alreadyApplied: true,
          auditID: race.id,
          userID: race.target_user_id,
          environment: race.environment,
          operatorID: race.operator_id,
          amountYuan: microsToYuan(race.amount_micros),
          balanceBeforeYuan: microsToYuan(race.balance_before_micros),
          balanceAfterYuan: microsToYuan(race.balance_after_micros),
          balanceYuan: microsToYuan(u?.balance_micros || 0),
          sandboxBalanceYuan: microsToYuan(u?.sandbox_balance_micros || 0),
          totalRechargedYuan: microsToYuan(u?.total_recharged_micros || 0),
          purchasedRechargedYuan: microsToYuan(u?.purchased_recharged_micros || 0),
          adminGrantedYuan: microsToYuan(u?.admin_granted_micros || 0),
          note: race.note,
          createdAt: race.created_at,
        });
      }
    }
    throw err;
  }

  const updated = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(userID).first();
  return json({
    ok: true,
    alreadyApplied: false,
    auditID,
    userID: updated.id,
    environment,
    operatorID,
    amountYuan: microsToYuan(amountMicros),
    balanceBeforeYuan: microsToYuan(balanceBefore),
    balanceAfterYuan: microsToYuan(isSandbox ? updated.sandbox_balance_micros : updated.balance_micros),
    balanceYuan: microsToYuan(updated.balance_micros),
    sandboxBalanceYuan: microsToYuan(updated.sandbox_balance_micros || 0),
    totalRechargedYuan: microsToYuan(updated.total_recharged_micros),
    purchasedRechargedYuan: microsToYuan(updated.purchased_recharged_micros || 0),
    adminGrantedYuan: microsToYuan(updated.admin_granted_micros || 0),
    note,
    createdAt: new Date().toISOString(),
  });
}

/**
 * Admin-only legacy order & reservation reconciliation check (`GET /v1/admin/reconcile-orders`):
 * Must report zero discrepancies before operators flip AUTO_CREDIT_PAUSED=false or ALLOW_APPLE_PRODUCTION_IAP=true.
 */
export async function handleAdminReconcileOrders(request, env, { json, verifyAdminSecret }) {
  if (!(await verifyAdminSecret(request, env))) {
    return json({ error: "仅管理员可执行历史订单与账本对账检查。", code: "admin_forbidden" }, 403);
  }

  const [paidMissingLedgerRes, ledgerMissingOrderRes, reservationDriftRes, summaryRes] = await Promise.all([
    env.DB.prepare(
      `SELECT p.id, p.user_id, p.external_order_id, p.amount_micros, p.channel, p.environment, p.status, p.paid_at, p.created_at
       FROM payment_orders p
       LEFT JOIN ledger l ON l.external_order_id = p.external_order_id
       WHERE p.status = 'paid' AND l.id IS NULL
       ORDER BY p.created_at DESC LIMIT 100`
    ).all(),
    env.DB.prepare(
      `SELECT l.id, l.user_id, l.kind, l.external_order_id, l.cost_micros, l.environment, l.created_at
       FROM ledger l
       LEFT JOIN payment_orders p ON p.external_order_id = l.external_order_id
       WHERE l.kind IN ('apple_iap', 'sandbox_apple_iap', 'webhook_topup')
         AND l.external_order_id IS NOT NULL
         AND p.id IS NULL
       ORDER BY l.id DESC LIMIT 100`
    ).all(),
    env.DB.prepare(
      `SELECT u.id AS user_id,
              u.reserved_micros AS user_reserved_micros,
              COALESCE((SELECT SUM(r.reserved_micros) FROM credit_reservations r WHERE r.user_id = u.id AND r.status = 'reserved'), 0) AS active_reserved_micros
       FROM users u
       WHERE u.reserved_micros != COALESCE((SELECT SUM(r.reserved_micros) FROM credit_reservations r WHERE r.user_id = u.id AND r.status = 'reserved'), 0)
       LIMIT 100`
    ).all(),
    env.DB.prepare(
      `SELECT
         (SELECT COUNT(*) FROM payment_orders) AS total_orders,
         (SELECT COUNT(*) FROM payment_orders WHERE status = 'paid') AS paid_orders,
         (SELECT COUNT(*) FROM payment_orders WHERE status = 'pending') AS pending_orders,
         (SELECT COUNT(*) FROM credit_reservations WHERE status = 'reserved') AS active_reservations`
    ).first(),
  ]);

  const paidOrdersMissingLedger = (paidMissingLedgerRes.results || []).map((r) => ({
    orderID: r.id,
    userID: r.user_id,
    externalOrderID: r.external_order_id,
    amountYuan: microsToYuan(r.amount_micros),
    channel: r.channel,
    environment: r.environment,
    paidAt: r.paid_at,
    createdAt: r.created_at,
  }));

  const ledgerCreditsMissingOrder = (ledgerMissingOrderRes.results || []).map((r) => ({
    ledgerID: r.id,
    userID: r.user_id,
    kind: r.kind,
    externalOrderID: r.external_order_id,
    amountYuan: microsToYuan(Math.abs(Number(r.cost_micros || 0))),
    environment: r.environment,
    createdAt: r.created_at,
  }));

  const reservationDriftUsers = (reservationDriftRes.results || []).map((r) => ({
    userID: r.user_id,
    userReservedYuan: microsToYuan(r.user_reserved_micros),
    activeReservationsYuan: microsToYuan(r.active_reserved_micros),
  }));

  const autoCreditPaused = String(env.AUTO_CREDIT_PAUSED ?? "true").trim().toLowerCase() !== "false"
    && String(env.AUTO_CREDIT_PAUSED ?? "true").trim() !== "0";
  const appleProductionEnabled = !autoCreditPaused
    && ["true", "1", "yes", "on"].includes(String(env.ALLOW_APPLE_PRODUCTION_IAP ?? "false").trim().toLowerCase());

  const clean = paidOrdersMissingLedger.length === 0 && reservationDriftUsers.length === 0;

  return json({
    ok: true,
    clean,
    readyToEnableAutoCredit: clean,
    autoCreditPaused,
    appleProductionEnabled,
    summary: {
      totalOrders: Number(summaryRes?.total_orders || 0),
      paidOrders: Number(summaryRes?.paid_orders || 0),
      pendingOrders: Number(summaryRes?.pending_orders || 0),
      activeReservations: Number(summaryRes?.active_reservations || 0),
    },
    paidOrdersMissingLedger,
    ledgerCreditsMissingOrder,
    reservationDriftUsers,
  });
}
