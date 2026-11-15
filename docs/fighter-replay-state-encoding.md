# Canonical fighter replay diagnostics, schema 10

## Scope and status

`DuelReplayStateEncoding.encode(game)` includes every stored field of `DuelGame`, recursively including the gameplay state of its optional `DuelWeaponFight`. The derived `panguPresentationEvents`, `triadPresentationEvents`, `sourceMotionSamples` and `erlangAudioEvents` queues are explicitly excluded. They provide renderer/audio observations and do not drive later collision or source timers. The standalone fight overload has its own payload discriminator. These are read-only diagnostic bytes for comparing two simulations at the **same completed tick**, with the same initial configuration, executable/rules version, ordered inputs and pause/cancellation history. They do not change combat, transport or UI, implement rollback/restoration, authenticate a peer, prove asset provenance, or provide cryptography.

The caller may later use a platform SHA implementation on these bytes. The encoder never uses Swift `Hasher`, `hashValue`, `description`, reflection, pointer identity, native struct layout or JSON. Reflection appears only in a test that checks the stored-property audit inventory.

Equipped motion uses floating-point math. This format detects differing bits; it does not establish cross-architecture/libm determinism. Verify replay on all supported peers before treating a digest match as a networking guarantee. A rules version is an explicit compatibility tag, not proof of executable identity. Pin the same verified build separately.

## Wire-independent byte contract

The header is the eight ASCII bytes `DUELSTAT`, unsigned 16-bit schema version `10`, unsigned 16-bit simulation rules version `15`, and one payload byte: game `1`, standalone fight `2`, catalog `3`. Nested values have no additional header. Bump the schema version if any field order, width, meaning, tag, bound or numeric normalization changes. Bump the rules version whenever simulation behavior/constants change even if the stored fields do not.

- All multi-byte numbers are **little-endian**. Swift `Int` becomes a signed, two's-complement 64-bit integer; RNG is unsigned 64-bit. No native-width values are written.
- Boolean and optional-present markers are exactly one byte, `0` or `1`. A present optional is immediately followed by its payload.
- `Double` uses its **exact IEEE-754 binary64 `bitPattern`** as unsigned 64-bit. There is no normalization, rounding or decimal conversion: `+0` and `-0`, infinities and different NaN payloads remain distinct. Validated catalog tracks are finite, but encoding itself is lossless rather than a validator.
- Strings are unsigned 32-bit UTF-8 byte length, then those bytes. There is no Unicode normalization. Collections are unsigned 32-bit element count, then elements in array order.
- The `roles` dictionary is sorted by lexicographic UTF-8 key bytes; each entry is key then value. Pangu's validated unique damage-kind lists and ability rules are sorted by their raw string keys. Other semantic arrays, including profiles, clips, combo links, active sides, scheduled winds and spatial effects, retain order. The first matching clip/link may affect behavior.
- `Action.soundAt == Int.max` is the engine's “no scheduled sound” sentinel. It encodes as absent optional; other values encode as present signed 64-bit. This sentinel is the only integer normalization, making it independent of host `Int` width.
- Limits: 64 MiB total output, 4,096 UTF-8 bytes per string, and 16,384 elements per collection. Fighter/profile/two-player arrays and active weapon sides have the tighter bound 2. The encoder throws `byteLimit`, `stringLimit` or `collectionLimit` and returns no truncated success. Limits are defensive encoding limits, not permission to use invalid catalogs or simulation configurations.

### Enum tags

Tags are unsigned bytes, explicitly switched rather than derived from raw strings or declaration order:

- Hero: ember 0, gale 1, liu 2, wuYong 3. Existing tags remain unchanged.
- Difficulty: learning 0, challenging 1.
- Mode: versus 0, practice 1, tutorial 2.
- Move: jab 0, cross 1, finisher 2, heavy 3, skill1 4, skill2 5, ultimate 6.
- Weapon command: weapon 0, weaponForward 1, weaponUp 2, weaponDown 3, weaponBack 4, heavy 5, kick 6, kickForward 7, kickUp 8, kickDown 9, kickBack 10, shadow 11, ranged 12.
- Phase: fighting 0; roundBreak 1 followed by optional winner then remaining; matchOver 2 followed by winner.
- Event: hit 0 followed by attacker, damage; blocked 1 followed by defender; guardBreak 2 followed by defender; whiff 3 followed by attacker; jumped 4 followed by player; roundEnded 5 followed by optional winner; grappleStarted 6, grappleSlam 7 and grappleReleased 8 each followed by attacker; grappleClash 9 with no payload.
- Contact kind: hit 0, block 1.
- Pangu effect: attack 0; control 1; teleportBehind 2 followed by distance; pillarRise 3 followed by height and duration; descend 4 followed by velocity; castPhase 5 followed by ability and phase strings; castEnded 6 and castInterrupted 7 each followed by ability string. Ability, damage kind, delivery, control kind, cast phase, rule basis and policy enums encode their explicit UTF-8 raw strings, not declaration indices.

`Buttons` retains the full signed-64 raw bit mask, including any unknown bits. Enum additions require an explicit encoder case and compatibility review.

## Source audit checklist and field order

The following lists are the **exact encoding order**, checked against the declarations in `DuelGame.swift`, `DuelWeaponFight.swift` and `DuelWeaponMotion.swift`. No stored simulation fields are omitted. Re-audit this list whenever one of those types changes. `DuelReplayStateAuditTests` fails if their stored-property inventory changes, including private properties; manual review still has to verify each property's encoding and meaning.

- [x] **DuelGame**: selectedHero, difficulty, mode, fighters, projectiles, grapple, phase, frame, remainingTicks, wins, hitStop, events, landedHits, damageDealt, weaponFight, random, nextProjectile, botHeld, buffered, opponentHero, weaponModeRequested. The private RNG, pending hit-stop buttons, AI held input, projectile identity counter and invalid-equipped-mode gate are included. The outer visible fighter/event copies are encoded even when a nested fight exists, so mirror-state drift is not hidden.
- [x] **DuelWeaponFight**: profiles, fighters, phase, frame, remainingTicks, wins, hitStop, landedHits, damageDealt, events, contacts, swings, mode, difficulty, actions, queued, loopTicks, loopRoles, previousX, random, shadowCooldowns, previousY, previousHurtY, impactMotions, panguStates, panguSpace, ordinaryThrowStates, ordinaryThrowKnockdownTicks, sourceThrowStates, sourceThrowDisabledTicks, triadStates, triadSpace, roundNumber, sourcePresentationTick, sourceStances, rootVictims, previousPoses, previousFacings, erlangStates, erlangSpace. Fighter-indexed arrays have limit 2. PreviousHurtY retains the complete hurtbox origin, including source jump/root offsets. This includes queued follow-ups, source stance/root-victim clocks, previous positions used for swept collision, pending recoil/flight, throw authority/recovery and RNG before its next decision.
- [x] **Root victim**, as optional elements of rootVictims: sourceID (UInt64), owner (Int64), motion (UTF-8 string), tick (Int64), durationActive (Bool), originXMillimeters (exact Double), direction (Int64). A visually identical loop pose before and after the duration variable expires remains distinguishable, because the next source checkpoint will branch differently.
- [x] **Explicit presentation exclusion**: `DuelWeaponFight.panguPresentationEvents` is a derived queue, bounded to 128 accepted-feedback events per step and cleared at the next step or round reset. Its `(frame, sequence)` keys do not consume gameplay IDs or RNG. Adding, observing, dropping or discarding this feedback cannot affect simulation outcomes or canonical bytes; the audit test changes the queue independently and verifies this exclusion. The computed `panguPresentation` snapshot and native SceneKit/HUD caches are also outside the encoding. The original `events`, `contacts`, `swings`, Fighter and pose fields listed above remain encoded.
- [x] **Private Action**, as optional elements of actions: name, role, command, tick, hits, touching, landedStrikeIDs, touchingStrikeIDs, requiresContactSeparation, sounded, reaction, comboDepth, soundAt, shadowOriginX. Strike IDs retain independent contact budgets inside one animation stage. The geometric separation latch prevents a new combo stage from damaging a continuously overlapping body just because its strike IDs differ. The optional origin owns the provisional hammer trajectory; cooldowns and external motion freeze with hit-stop. These states affect future events even if the current pose looks identical.
- [x] **Fighter**: hero, x, y, velocityY, facing, health, guardMeter, energy, stun, knockdown, invulnerable, guarding, attack, flash, walking, movementDirection, weaponPose. Presentation fields are intentionally included so deterministic visible state can be diagnosed too.
- [x] **Attack**: move, age, connected, spawned, comboQueued.
- [x] **Input** (botHeld): move, guardHeld, taps.rawValue, vertical, weaponCommand. **Buttons**: rawValue.
- [x] **Projectile**: id, owner, x, direction, lifetime.
- [x] **Grapple**: attacker, direction, age. Its stage and remaining duration are derived from age and code constants.
- [x] **WeaponPose**: clip, tick, duration, groundLift, reaction. Its phase is derived.
- [x] **Contact**: kind, attacker, position, direction, heavy, usesWeapon, authoredAudio. **Swing**: attacker, heavy, usesWeapon. Array order and all event payloads are retained.
- [x] **WeaponPoint**: x, y, z.
- [x] **WeaponProfile**: id, hero, faction, resourceName, bytes, sha256, bodyID, weaponID, activeWeaponSides, roles, clips, comboLinks, combatRules, panguRules, ordinaryThrows, triadRules, erlangRules, summonTracks. Optional nil and present-empty combo links remain distinct. A nil combat rule table selects the explicitly versioned legacy application adaptation. Nil ordinaryThrows disables ordinary grapples. Pangu requires both explicit combat rules and explicit Pangu rules; it cannot inherit the legacy hammer profile.
- [x] **CombatRuleProfile**: id, basis.rawValue, sourceVersion, optional sourceSHA256, evidence, attacks. These provenance declarations are retained but do not themselves prove recovery of original game rules.
- [x] **CombatAttackRule**: command, clipName, strikes.
- [x] **CombatStrike**: id, startTick, endTick, weaponSides, damage, blockedDamage, knocksDown, hitStopTicks, blockedHitStopTicks, impact, blockedImpact, optional collisionEdgeIDs, optional damageKind.rawValue.
- [x] **ImpactResponse**: distanceMillimeters, durationTicks, launchVelocityMillimetersPerTick, gravityMillimetersPerTickSquared.
- [x] **ImpactMotion**: response, direction, elapsedTicks, appliedHorizontalDistance, horizontalStopped. Vertical position/velocity reside in the already encoded Fighter fields.
- [x] **WeaponClip**: name, frames, sha256, bundle, tracks, optional playbackTicks, optional sourceEndEventTick. The source end event can precede the final transition sample; both values are retained.
- [x] **WeaponTracks**: samplesPerSourceFrame, root, handL, handR, footL, footR, weaponBaseL, weaponTipL, weaponBaseR, weaponTipR, groundLift, optional collisionEdges, optional hurtCapsules, optional centerOfMass, optional pelvis, optional toeL, optional toeR, optional head. Every sample and every coordinate is encoded. Collision edges retain id, side, radius, base and tip; hurt capsules retain id, defense, radius, base and tip.
- [x] **WeaponComboLink**: from, to, sourceFrame.
- [x] **Catalog entry point**: schemaVersion, previewFramesPerSecond, sourceFramesPerSecond, profiles. `DuelWeaponFight` retains the selected profiles, not the original catalog object. Its initializer requires schema 1 / preview FPS 30; those are pinned by the rules version. Optional source FPS is descriptive, not used by the simulation; the separate catalog entry point retains it when fingerprinting the original catalog.

### Pangu configuration order

`DuelPanguRules.appendReplayState` is used both by the profile and by the optional live state. This deliberately retains the complete immutable rules in each location. Provenance and evidence remain declarations, not proof of retail parity.

- [x] **Rules**: id, basis.rawValue, sourceVersion, optional sourceSHA256, evidence (limit 16), level, maximumHealth; then the following ordered groups.
- [x] **Light**: integer array [maximum, initial, damageToLightNumerator, damageToLightDenominator, regularHitGain, primordialHitGain, level3GainBonus, level5BlockedHitGain, level5PrimordialGainBonus]; sorted absorbedKinds string array.
- [x] **Combo**: integer array [maximum, pointsPerHit, holdTicks, level6HoldTicks, damageBonusPerPointBps, maximumDamageBonusBps, heavyWindThreshold, allAttackWindThreshold, rangedThreshold, zeroCooldownThreshold, level4SpeedThreshold, level4AttackSpeedBps]; sorted affectedKinds string array.
- [x] **Abilities**: sorted array (limit 7); each ability string, integer array [cooldownTicks, lightCost, startupTicks, activeTicks, recoveryTicks], interruptible Boolean, damageImmune Boolean, AttackSpec.
- [x] **Typhoon and Hunt**: integer array [typhoon.durationTicks, fixedCooldownTicks, damageBonusBps, lightCostReductionBps, stormGateUsesPerCycle, stormGateBehindMillimeters, hunt.durationTicks, pinTicks]; hunt.empoweredSpear AttackSpec.
- [x] **Heavenfall**: integer array [petrifyPhaseTicks, targetPetrifyTicks, riseTicks, chargeTicks, fallTicks, recoveryTicks, pillarHeightMillimeters, descentVelocityMillimetersPerTick, lightPerChargeTick, level6LightPerChargeTick, level6DamageBonusBps, level6ComboGain, level6CooldownMultiplierBps]; tranceTrigger string; optional level6LightChargeRatio; optional level6ComboGainTrigger string.
- [x] **LightChargeRatio**, when present: numerator Int64, denominator Int64, carryAcrossCasts Boolean, discardRemainderAtCapacity Boolean. Ratios are not normalized: nil, an explicit equivalent ratio, and differently declared but equivalent fractions retain distinct configuration identity. Missing optional fields decode as nil; a present ratio must explicitly supply both strategies.
- [x] **Earth**: integer array [shardDamageBonusBps, shardStunTicks, splitterDamageBonusBps, dreadTicks, dreadDamageTakenBonusBps, dreadOutgoingReductionBps, splitterWindCount, splitterWindIntervalTicks, earthquakeWindowTicks, boulderBonusWindowTicks]; landingShock AttackSpec, boulderBonus AttackSpec.
- [x] **Ranged, Trance and global bonuses**: integer array [ranged.maximumCharges, initialCharges, rechargeTicks, level5RechargeMultiplierBps, trance.durationTicks, attackSpeedBps, incomingDamageMultiplierBps, extraComboChancePerMillion, extraComboPoints, heavyWindCount, typhoonWindCount, tranceWindCount, level4PrimordialCooldownReductionTicks, level6PrimordialCooldownReductionTicks, level6CooldownRecoveryBps]; windBlade AttackSpec.
- [x] **Policies**: Boolean array [blockedHitsCountCombo, blockedPrimordialStartsRhythm, blockedSpearCanPin, generatedHitsCountCombo, generatedHitsRestoreLight, blockedDamageResetsCombo, lightOnlyDamageResetsCombo, level6ReceivedHitRefreshesHold, consumeRhythmOnSpearCast, windSourcesStack, thresholdsUseComboBeforeContact, level6RecoveryAffectsTyphoon, level4ReductionAffectsTyphoon, zeroCooldownClearsExisting, shieldRequiresPositiveLight, interruptReleasesPetrification]; windTrigger, typhoonCooldownPriority, earthWindowTrigger, attackSpeedStacking strings.
- [x] **AttackSpec**: damageKind string, delivery string, integer array [damage, blockedDamage, rangeMillimeters, projectileSpeedMillimetersPerTick, hitboxBottomMillimeters, hitboxTopMillimeters, radiusMillimeters, stunTicks, airHoldTicks, hitStopTicks, blockedHitStopTicks], knocksDown Boolean, four ImpactResponse integers in the established order.

### Pangu dynamic state order

- [x] **PanguState**: full rules; integer array [light, combo, comboRemainingTicks, typhoonRemainingTicks, rhythmRemainingTicks, tranceRemainingTicks, earthquakeRemainingTicks, boulderBonusRemainingTicks, rangedCharges, rangedRechargeUnits, stormGateUses, rejectedPendingWindCount, lightChargeRemainder]; unsigned typhoonCycle, randomState, nextEffectID; cooldownUnits integer array (limit 7); optional unsigned lastContactID, lastAttackEventID, lastLandingEventID; optional activeCast; pendingWinds array (limit 256). The fractional Light numerator affects future resource gains even while visible integral Light is unchanged.
- [x] **Cast**: unsigned id, ability string, tick, duration, phase string, empowered Boolean. **PendingWind**: remainingTicks, optional ability string.
- [x] **Attack**: unsigned id, optional ability string, damageKind and delivery strings, the same eleven-integer array as AttackSpec, four ImpactResponse integers, knocksDown/generated/empowered Booleans. Own outgoing damage bonuses are already applied once; target defense remains part of contact resolution.
- [x] **Control effect**: unsigned sourceID, kind string, durationTicks, damageTakenBonusBps, outgoingReductionBps. Petrification release carries its cast source ID so it cannot release unrelated control.
- [x] **PanguSpatialState**: tick; controls; lifts; volumes; deferred; deferredSlams; speedRemainders; lastAirborne; jumpEligible; unsigned hitSequence; pendingSourceShardStuns (two optional unsigned source control IDs). Every per-fighter array has limit 2. This live clock advances only outside hit-stop and round breaks; it is separate from Fight.frame.
- [x] **Spatial Control**: stunUntil, petrifyUntil, pinUntil, airUntil, airHeight, pendingAirHoldTicks, dreadUntil, damageTakenBonusBps, outgoingReductionBps, then unsigned petrifySourceID.
- [x] **Lift** (optional): startHeight, targetHeight, duration, age, fallingSpeed, phaseStartedTick, height.
- [x] **Volume**: owner, Attack, originX, originY, direction, expiresAt, x, travelled, spent Boolean. **DeferredEffect**: owner, tagged Effect. **DeferredSlam**: optional Attack. The generated Heavenfall landing batch can remain in deferred until physical descent completes in the same tick.

### Ordinary throw configuration and state order

- [x] **ThrowRules**: id, basis.rawValue, sourceVersion, optional sourceSHA256, evidence (limit 16), simultaneousContactPolicy.rawValue, attempts (limit 2).
- [x] **ThrowRule**: existing command byte; contactStartTick, contactEndTick, minimumRangeMillimeters, maximumRangeMillimeters integers; canGrabAttackingTarget Boolean; damageKind.rawValue; appliesPanguDamageScaling, startsPanguAttack, registersPanguContact Booleans; attackerEnergyGain and targetEnergyGain integers; attempt, success, miss, immune sequences in that order.
- [x] **ThrowSequence**: durationTicks, attacker track, optional target track, damageTick, damage, hitStopTicks, knockdownTicks.
- [x] **ThrowTrack**: role; keyframes (limit 64), each tick, phaseBps, xMillimeters, yMillimeters, facingMultiplier. All numeric values are Int64. No interpolation output or source phase is rounded into a separate stored tick.
- [x] **ThrowState**: complete rule; attacker, target, facing; attackerOrigin.x/y and targetOrigin.x/y; stageTick; optional outcome.rawValue; contactConsumed, damageApplied, isFinished, isCancelled Booleans. Stage, samples, candidate contexts and one-step results are derived, not stored.

Read-only hit candidates and resource damage receipts are ephemeral values consumed within a step, not retained checkpoint fields. The complete rules/state/spatial inventories are checked in tests; computed speed, readiness, throw immunity and visual labels have no additional stored state. The ordinaryThrowEscaped presentation event follows the same explicit exclusion as other Pangu feedback.

Computed properties/functions (`round`, hit/hurt boxes, pose phase, grapple stage, clip ticks, profile titles, move tables, etc.) contain no additional stored state. Static constants and algorithms are pinned by the executable/rules compatibility requirement above. `DuelClock`, physical `DuelWeaponInput`, network mailboxes and UI state are **not contained in either simulation** and are not claimed to be covered. Replay must supply the same tick inputs and explicit cancellation operations, not compare wall-clock/render accumulators from different refresh rates. Any future full-session checkpoint must encode those separate owners as needed.

## Catalog completeness and cost

No catalog tracks or profile bytes are excluded from a successful equipped simulation encoding. An existing resource `sha256` is recorded as identity, but **not trusted as a fingerprint of the simulation catalog**: roles, combo links or tracks can change without that string changing. Tests exercise all three cases. Invalid catalog objects rejected during initialization are not retained by `DuelGame`; it encodes their resulting blocked state (`weaponFight == nil`, `weaponModeRequested == true`), not discarded constructor input.

`encodeCatalog` provides canonical configuration bytes, but this patch does not implement a compact fingerprint-linked dynamic form. A future optimization must bind dynamic bytes to a **separately pinned, verified SHA of the full canonical configuration**, include that identity in the comparison, and never substitute unverified asset SHA strings. Until then, the full form prevents false matches caused by omitted immutable inputs.

The existing tiny synthetic fixture (two profiles, nine 9-frame clips each) has these current schema-calculated initial sizes, pinned by regression assertions:

- Laboratory game: **382 bytes**.
- Full fixture catalog: **65,562 bytes**.
- Standalone equipped fight: **66,666 bytes**.
- Equipped game including its mirrored visible state: **67,116 bytes**.

Introduced by schema 4 relative to schema 3, each profile adds a nil Pangu-rule marker (two bytes
total). An initial fight additionally stores two nil Pangu-state markers
(4 + 2 bytes) and the empty spatial state (232 bytes): tick 8, controls 164,
lifts 6, volumes 4, deferred 4, deferredSlams 6, speedRemainders 20,
lastAirborne 6, jumpEligible 6, hitSequence 8. Thus an initial fight gains
240 bytes. A real Pangu profile/state adds its complete explicit rules,
timers, counters, cast, RNG, pending attacks and active spatial payloads.

Schema 5 changed only the header for the then-current non-Pangu fixtures
(381 / 65,392 / 66,137 / 66,586 bytes). For a Pangu profile whose two Heavenfall
optionals are nil, its rules gain two marker bytes. The corresponding live
state gains the same two markers and an eight-byte remainder, for a total
12-byte increase in a fight/game containing one Pangu profile and state.
Present optional payloads add their explicit fields in both rules locations.

Schema 6 adds two nil ordinaryThrows profile markers. A fight additionally
adds an array containing two nil throw states (4 + 2 bytes) and the two-entry
Int64 knockdown clock array (4 + 16 bytes). The catalog therefore grows by
2 bytes and an equipped fight/game by 28 bytes. The laboratory-only payload
still has 381 bytes; only its header changes. Enabled configurations and live
states include the complete supplied rules, tracks and stage authority.

These are independent schema-size calculations, **not a production resource benchmark**. Large real catalogs can be much larger. Use this API on demand at diagnostic checkpoints, off the main thread from an immutable copied snapshot, with a bounded diagnostic cadence. Do not allocate and hash the full catalog on the render/main thread every tick. No callers, transport hooks or scheduled hashing are added here.

## Regression coverage and validation

`DuelReplayStateTests` covers same-seed/input bytes with AI for every laboratory hero and both difficulties; both equipped hero orders and difficulties; actual step changes; invisible RNG changes; queued follow-ups before/after pause cancellation; laboratory hit-stop queues and combo cancellation; changed catalog tracks/roles/combo links with unchanged asset SHA; dictionary insertion order; exact scalar and initial-game goldens; enum tags; size bounds; and exact floating bit preservation. `DuelReplayStateAuditTests` inventories all stored fields, including the private action struct.

The original diagnostic-only patch was prepared without a local Swift compiler.
The 2026-11-14 mechanics follow-up changes gameplay and equipped presentation;
its scoped compile, regression results and remaining native/source acceptance
limits are recorded separately. Do not reuse the original diagnostic patch's
validation status as evidence for the new simulation.

## Continuous recoil and strike rules update (2026-11-14)

Schema 3/rules 7 adds explicit per-animation contact windows and per-strike
damage/response data, independent weapon-side latches and deterministic
horizontal/vertical impact motion. The source-derived network rules manifest
requires both new Swift files. Existing command wire tags are unchanged, but
peers with different rule fingerprints must not start a match.

The legacy catalog remains an application adaptation: 65/200 mm total recoil
is consumed over 6/10 ticks, with no inferred vertical launch. A supplied
launch response holds recovery until motion settles and the fighter lands;
models, collision and weapon effects use the same external root height.
Pending impulses freeze during hit-stop and are cleared on round transitions.
This establishes a deterministic interpreter, not original SF3 source parity.

## Pangu interpretation and integration update (2026-11-14)

Schema 4/rules 8 adds opt-in `liu_pangu`, mandatory provenance-bearing rule
profiles, Light absorption, combo and L1–6 ability state, seeded Trance,
projectile and ground contacts, hard control, real pillar descent, and
independent Earth windows. L4 and L6 fixed cooldown reductions are separate
from any explicitly configured recovery multiplier. No original balance
values are inferred from synthetic test fixtures.

Attack-speed microsteps sample every crossed contact window, and stop as soon
as a contact introduces hit-stop. An unresolved explicit strike at a shared
combo anchor owns that sample before the next stage enters; legacy timing
is unchanged. Own-jump landing is distinct from enemy launch. A confirmed
rock's secondary component stays at that contact, while generated landing
wind waits for the same physical floor origin as Heavenfall. Knockdown and
hard interruption cancel unreleased follow-up attacks; round end clears the
whole spatial state. These lifecycle policies belong to this application
unless individually supported by reference evidence.

The network choice `liu_pangu` is distinct from `liu_hammers`; the offered
choice must match the loaded catalog at the start barrier. Host-consumed
directional inputs replay through the existing wire format. Compatibility
fingerprints cover all three new Pangu core files. The new canonical state
does not substitute for native, two-device, or source-asset acceptance; see
`fighter-pangu-implementation-20261114.md` and its validation record.

## Exact Pangu charge and phase options update (2026-11-14)

Schema 5/rules 9 adds an optional exact Level 6 Heavenfall charge ratio,
an optional combo-grant phase and additive attack-speed stacking. These
are opt-in configuration capabilities, not a complete production preset.
Older nil configurations retain the prior integral `level6LightPerChargeTick`
rate and landing combo grant. Their simulation timing is unchanged, although
the version header and Pangu optional/remainder bytes intentionally change.

For each completed charging interval, a present ratio computes
`total = lightPerChargeTick * numerator + lightChargeRemainder`, grants
`total / denominator` integral Light, and retains `total % denominator`.
Multiplication uses Int64 after validation: numerator is 0...1,000,000,
denominator is 1...1,000,000, and the ceiling of the scaled per-tick gain
cannot exceed the existing 1,000,000-unit rate bound. A zero numerator means
zero gain, not fallback. Level 1–5 continues to use the unscaled base rate.

When `carryAcrossCasts` is false, accepted Heavenfall start, normal completion
and permitted interruption clear its fractional remainder. When true, that
fraction survives those boundaries. A denied interruption leaves it intact.
`discardRemainderAtCapacity` controls whether reaching full Light through
charge or any other Light-restoration path clears the fraction. If false,
only the fraction survives capacity; excess whole Light is still capped.
Reset always clears the remainder, and hit-stop cannot advance charge because
the interpreter only steps on the fight's live simulation clock.

`level6ComboGainTrigger` uses the existing `castStarted`, `chargeStarted`,
`landing`, and `castEnded` phase names. Nil means landing independently of
`tranceTrigger`. Each selected boundary grants combo once per accepted cast;
interruption never synthesizes a completion grant. Configurable grant timing
does not prove which exact source-animation frame the original game uses.

The additive attack-speed strategy returns `earthBps + tranceBps - 10,000`,
adding the bonuses once. Maximum and multiplicative retain their existing
semantics. Every strategy must remain at most 100,000 BPS even when both
effects are active. Choosing among these strategies requires explicit
configuration; no original stacking order is inferred.

`DuelPanguPrecisionTests` exercises fractions, cast/capacity/reset lifetime,
nil JSON compatibility, each combo phase and interruption, seeded documented
bonuses on synthetic base values, additive bounds and replay coverage. Test
execution results belong to the new follow-up validation record; earlier
schema 4/rules 8 validation records remain historical and are not rewritten.

## Ordinary throws and automatic Pangu escape update (2026-11-14)

Schema 6/rules 10 introduces opt-in ordinary throws in the equipped fight.
There is no new input wire tag: configured weaponForward/weaponBack commands
select a close-range attempt, while distant inputs retain their ordinary
attack binding. The laboratory ultimate grapple remains a separate mechanic.

The attempt leaves the target free, then checks the actual current front-side
range, authored window, both actors' physical and source-pose grounding,
survival and action eligibility. A confirmed contact selects success or
ordinary-throw immunity. Pangu's existing immunity now enters an explicit
paired automatic-escape sequence instead of being an unused query.

Success/escape tracks are rebased at contact. Their relative position is
preserved at arena walls by one common translation; ordinary body separation
does not run during paired ownership. Successful damage occurs once at the
configured marker; a separate knockdown clock starts only at release.
Damage kind, Pangu scaling, start/contact effects and resource gains are
explicit policies. Miss/escape sequences cannot carry successful throw
damage, hitstop or knockdown. Simultaneous attempts use a single consistent
catalog policy, evaluated before either participant claims its counterpart.

Hitstop freezes both stage clocks and authored poses. Locked presses do not
become delayed attacks. Accepted hard damage/control cancels paired ownership
and retains the incoming reaction/control. Released projectiles keep flying;
an attacker's own successful throw preserves previously scheduled Splitter
follow-ups. Practice KO disposes of the pair before health refill. Round end,
timeout and reset clear authority, and a grounded KO receives a terminal
down pose. Native HUD/diagnostic feedback observes these authoritative states.

All distances, source bindings, numeric timings and damage are configuration,
not recovered retail values. Existing shipped catalogs have no ordinaryThrows
section and retain their current equipment. The new source file is mandatory
in both manifest required-path lists; peers require matching fingerprints.
Input wire protocol remains 1. See fighter-pangu-ordinary-throw-followup-20261114.md
and its separate validation record for this update's checks and limits.

## Source root-victim update (2026-11-15)

Schema 8 appends a two-entry optional root-victim array immediately after sourceStances
and before previousPoses. An empty array payload adds six bytes to an equipped fight
or game; bare laboratory games and catalog payloads keep their prior sizes. The
current small fixture is 382 bytes (laboratory), 65,488 bytes (catalog), 66,516 bytes
(equipped fight), and 66,966 bytes (equipped game). Earlier size tables describe their
named historical schemas and are not current byte-count assertions.

Rules 12 implements reviewed lock_1777 Start/Loop→Loop/End transitions, with a
separate duration condition. Start and Loop transition at source AnimationEnd
ticks 78 and 112. A released duration also allows Loop→End at IntervalEnd ticks
2, 50 or 90. The End clip retains all 94 sampling ticks and publishes its Floorfall
IntervalStart crossing at tick 38. The arena then uses its existing get-up role;
this is not a claim that the original global FOLLOWED_BY dispatcher is restored.

Hit-stop freezes the state and ordered source-motion queue. Locked inputs are
discarded, repulsion remains disabled during the passive sequence, and round
completion/reset clears ownership. The new state is part of canonical diagnostics;
derived audio observations remain excluded. The source-manifest glob covers the
new Swift helper, so old executable fingerprints must not join a new session.

## Provisional shadow schema update (2026-11-10)

Schema/rules 2 append `Action.shadowOriginX` (optional signed Int64) after
`soundAt`, and a two-element `shadowCooldowns` array after the fight RNG.
Initial fights gain 20 bytes; active actions gain an optional-origin marker
and, for shadow actions only, its 8-byte value. Derived `DuelShadowVisual`
contains no stored simulation state. Source-derived network compatibility
fingerprints include the new rules file automatically. Older executable rules
and schema identities must not be combined with this build. See
`fighter-provisional-shadow-2026-11-10.md` for timing and verification limits.

## Source-anchored hammer rules update (2026-11-13)

Rules version 3 changes the provisional hammer's spatial path. Release tick 24
and return tick 71 use the same integer-mapped heavy-clip samples as the displayed
body. A shared sampler provides the rendered weapon, effect endpoints, attack
bounds and continuous contact path. The previous absolute apex and active/return
windows remain bounded; contacts use actual moving segments, including analytic
corner events for a folded sweep, instead of a broad vertical rectangle.

`Action.shadowOriginX` follows body separation until the release tick, then stays
fixed for outgoing travel. The harmless return approaches the caster's current
held pose. This reuses the already encoded field and adds no stored state, so the
schema remains 2. Both independent header/golden fixtures change only their
rules-version bytes. Wire packet layout is unchanged; source-derived network
compatibility must still identify the new executable and reject an old peer.

The initial compiler-availability note above describes the original diagnostic
patch. The 2026-11-13 follow-up uses scoped Linux core/replay checks, recorded in
`fighter-visual-acceptance-2026-11-13.md`. It does not repeat the previously passed
full workflow or establish cross-architecture/native/physical-device acceptance.

## Rules 13: Triad stun preserves impact motion (2026-11-15)

A confirmed soul hit can leave its target in the air either through an explicit launch or by preserving the world height of an interrupted source jump. Ordinary Triad stun now retains the vertical velocity returned by the authoritative impact integrator. Previously, the stun adapter cleared that velocity after each step, holding the target at a fixed height until the stun expired. Root control still cancels vertical motion; hit-stop still freezes both motion and control clocks.

No stored fields, encoding order, or widths changed, so the schema remains 8. The behavior change requires rules 13. The network source manifest also includes `DuelWeaponFight.swift` and `DuelReplayState.swift`, so old and corrected builds have different source fingerprints. This is compatibility bookkeeping, not new evidence of cross-device determinism.

`DuelTriadStunImpactTests` covers live gravity/launch during stun, source-jump height preservation, both player slots, separate legacy and synthetic Pangu target profiles, hit-stop, overlapping root control, lethal-contact round cleanup, and the updated replay header. Synthetic values establish the interpreter behavior only; they do not establish original asset fidelity, measured retail physics, or physical-iPhone performance.

## Schema 9 / rules 14: deferred source Shard stun (2026-11-15)

The recovered D19 enemy-stun trigger first records a pending stun marker and
starts the stun only when its target can enter the source reaction. A Shard
contact during an uninterruptible action must therefore retain its pending
control instead of permanently losing it. Damage and contact deduplication keep
their existing contact-tick behavior; the full control duration starts at the
first eligible live simulation tick, before that tick accepts a new attack.
Hit-stop and pause do not consume this waiting period. Active throw ownership
and passive source bindings must release the target before the control starts.
Round cleanup removes the pending marker.

`DuelPanguSpatialState` appends `pendingSourceShardStuns` immediately after its
existing unsigned `hitSequence`: an array count bounded to two, then one optional
unsigned 64-bit source control ID per target. The initial two nil entries add
exactly six bytes to a standalone fight and an equipped game. The bare
laboratory game and standalone catalog payload sizes do not change. No new
stored field is added to `DuelPanguState`.

Both independent header fixtures now encode schema 9 / rules 14. The schema
bump records the new stored state; the rules bump records the changed combat
behavior. This remains a deterministic diagnostic encoding, not a new restore
format or proof of original motion/media completeness. The three original
shared stun motions are available in the reviewed source cache; their rendering
bindings and general victim Uninterrupt sampling are separate from this
protocol change.

For another Shard contact while a stun is already active, the current adapter
waits for the existing control and reaction to release before starting the
pending stun. The recovered trigger does not itself require the old timer to
reach zero. Existing native interval evidence does not yet establish the exact
event order or earliest source re-entry tick, so this waiting policy remains
an explicitly unresolved application adaptation. The multiple-Shard fixture
covers contacts before the first stun starts, not source equivalence for
repeated contacts during an active stun.


## Wu Yong source actor and companion integration (2026-11-15)

Schema 10 / rules 15 records Wu Yong's distinct hero identity, the complete
Erlang rules and live state, native source end/deletion clocks, original toe/head
FK landmarks, and the source damage kind of ordinary strikes. Wu is a third
roster choice; each match and each canonical catalog still contains exactly
two selected fighters. The original network weapon allowlist remains separate
from this local roster integration. No full-session network or Apple-device
determinism acceptance is claimed by these diagnostic changes.

The fight appends the two optional `erlangStates` and `erlangSpace` after
`previousFacings`. The profile appends `erlangRules` after `triadRules` and before
`summonTracks`. The following orders are explicit in the production encoders:

- **Erlang rules:** schemaVersion, sourceVersion, sourceSHA256, maximumHealth,
  normalizedWeaponPower, normalizedUnarmedPower, normalizedMagicPower,
  normalizedRangedPower, attacks (limit 256), releases (limit 128), optional
  controls (limit 512), optional swordSlots (limit 6).
- **Attack:** id, ability.rawValue, role, optional modelRole,
  sourceConfigurationSHA256, sourceRecordIndex, startTick, endTick, parts
  (limit 32), damageKind.rawValue, baseDamageBps, unblockable, knocksDown,
  impact's four signed integers, hitStopTicks, optional hitTags (limit 64).
- **Release:** id, ability.rawValue, ownerRole, atTick, modelRole, anchor,
  offset.x/y/z, minimumLevel. The source `head.x` and `enemy.pelvis.x` anchors
  are distinct from the owner's full pelvis transform.
- **Control:** role, kind.rawValue, startTick, endTick,
  sourceConfigurationSHA256, sourceRecordIndex.
- **Sword slot:** slot, birthRole, offset.x/y/z, sourceRecordIndex.
- **Erlang state:** sourceVersion and sourceTimerTicksPerUnit constants, level,
  form.rawValue, light, liveTick, optional cast, cooldowns (limit 9),
  meditationUnits, meditationPulse, meditationReleaseRequested,
  meditationRechargeStarted, swords,
  pendingSwords, swordReleaseTicks, swordSpawnSlots (limit 64),
  swordAttackPending, swordConsumeTicks, swordConsumePending,
  wrathTicks, wrathRefillTicks, lightDrainTicks,
  meditationStacks, meditationStackTicks, explosionStacksHalf,
  explosionStackTicks, explosionCooldownTicks, holiness, holinessTicks,
  avatarSwordSummonsPending, avatarSwordSummonTicks, lethalProtectionSpent,
  normalizedHealth, immortalActive, criticalHealTicks, immortalDisableTicks,
  returnToHumanPending, random (UInt64), nextEmissionID (UInt64).
- **Cast:** ability.rawValue, role, tick, duration, direction, originX, released,
  spentSwords, acceptedContact. An emitted value is consumed in its current
  step; pending future emission information remains in the encoded state.
- **Erlang space:** liveTick, nextID (UInt64), models (limit 64), bodyContactIDs,
  releasedModelIDs, dogDebuffTicks. Both contact-latch arrays are fighter-indexed
  (limit 2), each containing source IDs (limit 256).
- **Model:** id (UInt64), owner, ability.rawValue, role, bornAt, stateStartedAt,
  optional swordSlot, direction,
  origin.x/y/z, previousOrigin.x/y/z, optional swordMotion,
  acceptedAttackIDs (limit 256). This retains the exact source
  interval latches and stable identities required to avoid duplicate contacts.
- **Sword motion:** sourceContract string, headDistance, birthY,
  moveCentimetersPerTick (Float converted exactly to Double), hidden.
  Animation transitions retain model identity and birth time while resetting
  stateStartedAt; prior and current origins both participate in swept contact.
- **Summon track:** role, clip, frames, sourceSHA256, sourceBundle, optional
  sourceEndEventTick, optional sourceDeleteEventTick, root points, groundLift,
  optional boneConfigurationSHA256, optional collisionEdges, optional
  hurtCapsules, optional attackParts. Part dictionary keys are sorted and each
  value's part order is preserved. AnimationEnd and explicit DeleteModel remain
  separate clocks.

`normalizedHealth` is an original binary32 gameplay value converted exactly to
binary64 for this encoding. It is never reconstructed from the rounded integer
HUD health. The native critical-health floor is `Float(bitPattern: 0x3727c5ac)`;
its pending one-tick heal, three-tick immortality disable and deferred human
return are all retained. Equal displayed health therefore cannot hide distinct
future damage or recovery behavior. Hit-stop freezes these live source clocks.

The original Transform_Out binding is a single FK sample with playbackTicks=0
and sourceEndEventTick=0. Only the exact D15 role, source digest, bundle and
required landmarks permit that single-frame exception; ordinary motion still
requires two or more frames and a positive duration. Sampling the static pose
returns phase zero, including at the end event.

For the small pre-Erlang diagnostic fixture, each of 18 clips gains four nil
markers (source end, left/right toe and head), and two profiles gain nil Erlang
rules: 74 additional catalog bytes. A fight also gains two nil states (6 bytes)
and an empty Erlang space (64 bytes), for a 144-byte fight/game increase. This
produces the current 382 / 65,562 / 66,666 / 67,116-byte assertions above. Actual
source profiles contain larger FK tables and are not represented by these
fixture sizes.

`DuelErlangReplayStateTests` inventories all retained Erlang types and checks
that invisible RNG differences, sub-display health changes, consumed source
intervals, model-release latches, rule changes and source lifetime changes
remain visible in canonical bytes. Source assets and native presentation have
separate acceptance records; passing this diagnostic check does not complete
Pangu's missing equipment or activate a TestFlight upload.
