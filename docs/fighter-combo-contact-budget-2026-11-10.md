# Per-stage contact opportunities for equipped combos

## Change

Sun's katana and Liu's twin-hammer continuations retain their existing source
clips, frame anchors and input mapping. Each entered combo stage now has one
contact opportunity. A missed earlier stage no longer leaves unused hits that
can be spent when the same later stage leaves and re-enters the target.

Previously, the contact limit was `1 + comboDepth`, while `hits` counted only
actual contacts over the whole chain. After one missed stage, the second stage
could therefore hit twice. After two misses, the third stage could hit three
times if its geometry re-entered the hurtbox often enough. Blocks could also
spend those carried opportunities, producing extra chip damage and energy.

At a continuation, the existing `touching` latch survives the shared source pose
and only the per-stage contact count resets. An overlap at the splice cannot
become an immediate duplicate hit. Once contact ends, the new stage can connect
once. This is an explicit application combat rule, not recovered original-game
hit timing.

The change does not alter original rigs, source tracks, root movement, clip
duration, hit-stop, damage per contact, controls, combo anchors, or the current
shadow capability gate. The original motion bundles were inspected read-only
and verified against their saved hashes. They still do not provide the missing
shadow event semantics. No assets or secrets are included in this patch.

## Replay and compatibility

No stored property or encoded field is added or removed. The current-stage
meaning of `Action.hits` is documented in the replay inventory. `landedHits` and
`damageDealt` retain their existing match-wide meanings. Existing source-derived
network compatibility includes `DuelWeaponFight.swift`, so this rule change
produces a different rules fingerprint and cannot silently match an older build.

## Added acceptance

- Seven synthetic Swift test methods exercise both heroes and facing directions,
  a missed opener, two missed stages, a successful opening strike, guarded chip
  and energy, hit-stop at the exact splice, cancellation, and byte-identical replay.
- One native test method uses the authenticated actual catalog for both heroes,
  both directions, near and far spacing, and guarded/unguarded opponents. It checks
  the existing primary splice frame, complete final source frame, one contact per
  entered stage, recovery, and unchanged source profile data.

## Verification status

- `git diff --check` passed.
- All four authenticated distinct-resource script tests passed.
- All sixteen network-rules script tests passed.
- The rules generator includes the changed combat source in its fingerprint.
- Swift compilation and the new Swift tests have **not** run in this executor:
  `swift test --filter DuelWeaponComboTests --jobs 2` returned `swift: command not found`.
- Actual-resource iOS execution and visual acceptance remain pending. No CI,
  repository push, resource publication, signing, or TestFlight release was
  performed by this work.
