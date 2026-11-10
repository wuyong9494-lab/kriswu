# Canonical fighter replay diagnostics, schema 2

## Scope and status

`DuelReplayStateEncoding.encode(game)` includes every stored field of `DuelGame`, recursively including its optional `DuelWeaponFight`. The standalone fight overload has its own payload discriminator. These are read-only diagnostic bytes for comparing two simulations at the **same completed tick**, with the same initial configuration, executable/rules version, ordered inputs and pause/cancellation history. They do not change combat, transport or UI, implement rollback/restoration, authenticate a peer, prove asset provenance, or provide cryptography.

The caller may later use a platform SHA implementation on these bytes. The encoder never uses Swift `Hasher`, `hashValue`, `description`, reflection, pointer identity, native struct layout or JSON. Reflection appears only in a test that checks the stored-property audit inventory.

Equipped motion uses floating-point math. This format detects differing bits; it does not establish cross-architecture/libm determinism. Verify replay on all supported peers before treating a digest match as a networking guarantee. A rules version is an explicit compatibility tag, not proof of executable identity. Pin the same verified build separately.

## Wire-independent byte contract

The header is the eight ASCII bytes `DUELSTAT`, unsigned 16-bit schema version `2`, unsigned 16-bit simulation rules version `2`, and one payload byte: game `1`, standalone fight `2`, catalog `3`. Nested values have no additional header. Bump the schema version if any field order, width, meaning, tag, bound or numeric normalization changes. Bump the rules version whenever simulation behavior/constants change even if the stored fields do not.

- All multi-byte numbers are **little-endian**. Swift `Int` becomes a signed, two's-complement 64-bit integer; RNG is unsigned 64-bit. No native-width values are written.
- Boolean and optional-present markers are exactly one byte, `0` or `1`. A present optional is immediately followed by its payload.
- `Double` uses its **exact IEEE-754 binary64 `bitPattern`** as unsigned 64-bit. There is no normalization, rounding or decimal conversion: `+0` and `-0`, infinities and different NaN payloads remain distinct. Validated catalog tracks are finite, but encoding itself is lossless rather than a validator.
- Strings are unsigned 32-bit UTF-8 byte length, then those bytes. There is no Unicode normalization. Collections are unsigned 32-bit element count, then elements in array order.
- The `roles` dictionary alone is sorted by lexicographic UTF-8 key bytes; each entry is key then value. Semantic arrays, including profiles, clips, combo links and active sides, retain order. The first matching clip/link may affect behavior.
- `Action.soundAt == Int.max` is the engine's “no scheduled sound” sentinel. It encodes as absent optional; other values encode as present signed 64-bit. This sentinel is the only integer normalization, making it independent of host `Int` width.
- Limits: 64 MiB total output, 4,096 UTF-8 bytes per string, and 16,384 elements per collection. Fighter/profile/two-player arrays and active weapon sides have the tighter bound 2. The encoder throws `byteLimit`, `stringLimit` or `collectionLimit` and returns no truncated success. Limits are defensive encoding limits, not permission to use invalid catalogs or simulation configurations.

### Enum tags

Tags are unsigned bytes, explicitly switched rather than derived from raw strings or declaration order:

- Hero: ember 0, gale 1, liu 2.
- Difficulty: learning 0, challenging 1.
- Mode: versus 0, practice 1, tutorial 2.
- Move: jab 0, cross 1, finisher 2, heavy 3, skill1 4, skill2 5, ultimate 6.
- Weapon command: weapon 0, weaponForward 1, weaponUp 2, weaponDown 3, weaponBack 4, heavy 5, kick 6, kickForward 7, kickUp 8, kickDown 9, kickBack 10, shadow 11, ranged 12.
- Phase: fighting 0; roundBreak 1 followed by optional winner then remaining; matchOver 2 followed by winner.
- Event: hit 0 followed by attacker, damage; blocked 1 followed by defender; guardBreak 2 followed by defender; whiff 3 followed by attacker; jumped 4 followed by player; roundEnded 5 followed by optional winner; grappleStarted 6, grappleSlam 7 and grappleReleased 8 each followed by attacker; grappleClash 9 with no payload.
- Contact kind: hit 0, block 1.

`Buttons` retains the full signed-64 raw bit mask, including any unknown bits. Enum additions require an explicit encoder case and compatibility review.

## Source audit checklist and field order

The following lists are the **exact encoding order**, checked against the declarations in `DuelGame.swift`, `DuelWeaponFight.swift` and `DuelWeaponMotion.swift`. No stored simulation fields are omitted. Re-audit this list whenever one of those types changes. `DuelReplayStateAuditTests` fails if their stored-property inventory changes, including private properties; manual review still has to verify each property's encoding and meaning.

- [x] **DuelGame**: selectedHero, difficulty, mode, fighters, projectiles, grapple, phase, frame, remainingTicks, wins, hitStop, events, landedHits, damageDealt, weaponFight, random, nextProjectile, botHeld, buffered, opponentHero, weaponModeRequested. The private RNG, pending hit-stop buttons, AI held input, projectile identity counter and invalid-equipped-mode gate are included. The outer visible fighter/event copies are encoded even when a nested fight exists, so mirror-state drift is not hidden.
- [x] **DuelWeaponFight**: profiles, fighters, phase, frame, remainingTicks, wins, hitStop, landedHits, damageDealt, events, contacts, swings, mode, difficulty, actions, queued, loopTicks, loopRoles, previousX, random, shadowCooldowns. This includes queued follow-ups, action and loop clocks, previous positions used for swept collision, and RNG before its next decision.
- [x] **Private Action**, as optional elements of actions: name, role, command, tick, hits, touching, sounded, reaction, comboDepth, soundAt, shadowOriginX. `hits` is the current entered combo stage's consumed contact opportunity, including blocks; it resets on a source-linked continuation while `touching` survives the shared pose. Misses do not accumulate later hit opportunities. The optional origin owns the provisional hammer trajectory; cooldowns freeze with hit-stop and are encoded after RNG. Contact/sound one-shot latches and combo depth affect future events even if the current pose looks identical.
- [x] **Fighter**: hero, x, y, velocityY, facing, health, guardMeter, energy, stun, knockdown, invulnerable, guarding, attack, flash, walking, movementDirection, weaponPose. Presentation fields are intentionally included so deterministic visible state can be diagnosed too.
- [x] **Attack**: move, age, connected, spawned, comboQueued.
- [x] **Input** (botHeld): move, guardHeld, taps.rawValue, vertical, weaponCommand. **Buttons**: rawValue.
- [x] **Projectile**: id, owner, x, direction, lifetime.
- [x] **Grapple**: attacker, direction, age. Its stage and remaining duration are derived from age and code constants.
- [x] **WeaponPose**: clip, tick, duration, groundLift, reaction. Its phase is derived.
- [x] **Contact**: kind, attacker, position, direction, heavy, usesWeapon. **Swing**: attacker, heavy, usesWeapon. Array order and all event payloads are retained.
- [x] **WeaponPoint**: x, y, z.
- [x] **WeaponProfile**: id, hero, faction, resourceName, bytes, sha256, bodyID, weaponID, activeWeaponSides, roles, clips, comboLinks. Optional nil and present-empty combo links remain distinct.
- [x] **WeaponClip**: name, frames, sha256, bundle, tracks. Ticks are derived from frames and rules.
- [x] **WeaponTracks**: samplesPerSourceFrame, root, handL, handR, footL, footR, weaponBaseL, weaponTipL, weaponBaseR, weaponTipR, groundLift. Every sample and every coordinate is encoded.
- [x] **WeaponComboLink**: from, to, sourceFrame.
- [x] **Catalog entry point**: schemaVersion, previewFramesPerSecond, sourceFramesPerSecond, profiles. `DuelWeaponFight` retains the selected profiles, not the original catalog object. Its initializer requires schema 1 / preview FPS 30; those are pinned by the rules version. Optional source FPS is descriptive, not used by the simulation; the separate catalog entry point retains it when fingerprinting the original catalog.

Computed properties/functions (`round`, hit/hurt boxes, pose phase, grapple stage, clip ticks, profile titles, move tables, etc.) contain no additional stored state. Static constants and algorithms are pinned by the executable/rules compatibility requirement above. `DuelClock`, physical `DuelWeaponInput`, network mailboxes and UI state are **not contained in either simulation** and are not claimed to be covered. Replay must supply the same tick inputs and explicit cancellation operations, not compare wall-clock/render accumulators from different refresh rates. Any future full-session checkpoint must encode those separate owners as needed.

## Catalog completeness and cost

No catalog tracks or profile bytes are excluded from a successful equipped simulation encoding. An existing resource `sha256` is recorded as identity, but **not trusted as a fingerprint of the simulation catalog**: roles, combo links or tracks can change without that string changing. Tests exercise all three cases. Invalid catalog objects rejected during initialization are not retained by `DuelGame`; it encodes their resulting blocked state (`weaponFight == nil`, `weaponModeRequested == true`), not discarded constructor input.

`encodeCatalog` provides canonical configuration bytes, but this patch does not implement a compact fingerprint-linked dynamic form. A future optimization must bind dynamic bytes to a **separately pinned, verified SHA of the full canonical configuration**, include that identity in the comparison, and never substitute unverified asset SHA strings. Until then, the full form prevents false matches caused by omitted immutable inputs.

The existing tiny synthetic fixture (two profiles, nine 9-frame clips each) has these schema-calculated initial sizes, pinned by regression assertions:

- Laboratory game: **381 bytes**.
- Full fixture catalog: **65,388 bytes**.
- Standalone equipped fight: **65,849 bytes**.
- Equipped game including its mirrored visible state: **66,298 bytes**.

These are independent schema-size calculations, **not a production resource benchmark**. Large real catalogs can be much larger. Use this API on demand at diagnostic checkpoints, off the main thread from an immutable copied snapshot, with a bounded diagnostic cadence. Do not allocate and hash the full catalog on the render/main thread every tick. No callers, transport hooks or scheduled hashing are added here.

## Regression coverage and validation

`DuelReplayStateTests` covers same-seed/input bytes with AI for every laboratory hero and both difficulties; both equipped hero orders and difficulties; actual step changes; invisible RNG changes; queued follow-ups before/after pause cancellation; laboratory hit-stop queues and combo cancellation; changed catalog tracks/roles/combo links with unchanged asset SHA; dictionary insertion order; exact scalar and initial-game goldens; enum tags; size bounds; and exact floating bit preservation. `DuelReplayStateAuditTests` inventories all stored fields, including the private action struct.

Run `swift test --jobs 2 --filter DuelReplayState` for focused coverage, then the repository's full `swift test --jobs 2` regression suite. `git diff --check` passes locally. The current executor has no Swift compiler, so the Swift tests have **not been executed here**; the grouped native/core pipeline must compile and run them before this patch is accepted. No production gameplay, UI, assets, workflow, transport, cryptographic dependencies or published commits are changed by this patch.

## Provisional shadow schema update (2026-11-10)

Schema/rules 2 append `Action.shadowOriginX` (optional signed Int64) after
`soundAt`, and a two-element `shadowCooldowns` array after the fight RNG.
Initial fights gain 20 bytes; active actions gain an optional-origin marker
and, for shadow actions only, its 8-byte value. Derived `DuelShadowVisual`
contains no stored simulation state. Source-derived network compatibility
fingerprints include the new rules file automatically. Older executable rules
and schema identities must not be combined with this build. See
`fighter-provisional-shadow-2026-11-10.md` for timing and verification limits.
