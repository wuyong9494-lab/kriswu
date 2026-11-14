# Target mechanics continuation — 2026-11-14

## Baseline and acceptance boundary

- Repository baseline: `0d83323a5463b9f3feb57cc00532da2ade5a5c48` on
  `codex/fighter-visual-acceptance-20261113-1200`.
- Local continuation: `codex/fighter-lab-target-mechanics-20261114`.
- Sites publication reviewed: version 11, published 2026-11-13 21:24 CST.
  The published board records Build 705; later source changes are separate.
- Current targets: Sun is Dead Forest Triad with Ninjato, Liu is Primordial
  Heavenly King with a long single axe. The existing katana/hammers catalog
  has **not** been relabeled or accepted as either new target.
- This change is a tested interpreter/resource-preparation increment. Complete
  original-game mechanics, visuals and physical-device acceptance remain open.

## Implemented changes

### Independent contact rules

`DuelCombatRuleProfile` binds every attack to both command and exact clip name.
Each strike owns a bounded simulation window, selected weapon sides, one-hit
budget, direct/block damage, hit-stop and impact response. Two blades can have
different windows and damage without one blade borrowing the other's contact.
An explicit incomplete table is rejected; it does not fall back to old numbers.

Existing catalogs without this optional table still select the documented
application adaptation. Its damage values, shadow dash/throw and 1000-point
health bar are **not** original DFT or Heavenly King parameters. Provenance
fields distinguish application adaptation, reference measurement and declared
source configuration. Declared receipts are retained for review, not treated
as automatic proof of original parity.

The existing provisional shadow interpreter only supports its own bounded
dash/throw timeline. Rule validation rejects windows outside that timeline;
arbitrary new shadow/light abilities are not enabled by changing a damage row.

### Continuous impact motion

Confirmed contacts schedule horizontal motion instead of moving the defender
instantly. The legacy 65/200 mm total displacement is distributed over 6/10
simulation ticks; those durations are application adaptations. A separate,
explicit launch/gravity response can drive vertical movement. No unverified
launch has been silently assigned to every heavy attack.

Hit-stop freezes motion. Source root motion and external impact displacement
are applied once each. Reaction recovery waits for motion to settle and land.
Body render roots, hit/hurt bounds and effect endpoints share the authoritative
external height. Per-strike and cross-combo overlap latches prevent repeated
damage caused by persistent contact or changed strike identifiers.

### Replay and network compatibility

Diagnostic schema 3 / rules 7 retains explicit contact rules, strike latches,
previous collision origins and pending motion. New rules files are required
by both manifest generation and the native manifest reader. Command packet
tags remain unchanged; existing fingerprint checks reject mismatched builds.
The host still distributes consumed inputs and the guest replays them. There
is no separate unreliable impulse channel or renderer-owned damage clock.

### Real source preparation

`prepare_fighter_target_motions.py` verifies the saved source archive and two
original bundles, then decodes 24 Ninjato and 23 H17 motions: 47 motions,
94 arrays, 2,663 source frames. Private outputs stay outside the repository.
The public inventory contains identities, counts and validation outcomes only.

The user-provided iOS 1.46.1 / build 11345 IPA was also inspected. Its original
localization confirms the Dead Forest Triad name and the body43, helm43 and
ninjato06 equipment names. Exactly three corresponding Android 1.45.3 model
bundles were recovered with bounded HTTP byte ranges: 3,297,673 bytes in total,
each matching the saved SHA256 and ZIP CRC32. Unity objects were parsed, but
two external references and the opaque bone/config payload remain unresolved.
This is verified model recovery, not an accepted renderable character.

The IPA provides H17 level 1–6 descriptions with 27 distinct parameter
placeholders. Their values are not present in the readable localization. The
inner configuration archives remain opaque. No authenticated Pangu asset/rule
mapping was found in the inspected readable data; substring matches from
birthday keys and unrelated symbols were excluded.

Frame rate, collision events, damage, health and ability triggers are not
recovered by decoding positions/quaternions. The inventory consequently keeps
`permitsGameplayEnablement` false. Exact source and reference details are in:

- `acceptance/fighter-target-source-inventory-20261114.json`
- `fighter-target-mechanics-reference-20261114.md`

## Validation

Final counts and source fingerprints are recorded in
`acceptance/fighter-target-mechanics-validation-20261114.json`.

The first Swift 6.4.2 full-package compile stopped in the unchanged
`APIDiscovery.swift` expression at line 315 with a compiler type-check-time
error. The existing CI-pinned Swift 6.0.3 toolchain was then used without
changing that unrelated parser. The first selected regression run compiled
and passed 175 tests. After four airborne edge-case fixes, the final selected
run passed **179 tests with zero failures**. The source-preparation tests
passed 8/8 and the network-manifest tests passed 16/16.

The final airborne cases verify preservation of source jump height on impact,
relative sweeps against moving source hurtboxes, grounded terminal state after
airborne KO/timeout, and contact effects inside elevated hurtboxes. An
independent static review matched each fix to its new regression assertion.

Linux core checks do not verify SceneKit pixels, native iOS compilation,
original asset presentation, two-device synchronization or sustained 60 FPS.
No new TestFlight build is produced by this local increment.

## Remaining original-mechanic work

1. Bind the verified Ninjato/H17 source motions to the correct armor, weapons,
   skeleton, skill events and source timing. Resource existence alone does not
   establish an input, hit, transition or effect event.
2. Recover the target version/level rules for mist, suppression, souls,
   roots, enhanced blades and cross-round effects. The supplied source text
   uses parameter placeholders; the video does not expose all parameters.
3. Obtain an authenticated Heavenly King resource and rule mapping. Implement
   light-energy damage absorption, combo thresholds, four directional primal
   abilities, spear/ranged transformation and Heavenfall from the correct
   version. The old hammer throw is not an implementation of these mechanics.
4. Use the same client version, set level, equipment/perks and mode to compare
   health, damage and timing. DFT levels 7/8 and pre-release videos must not be
   conflated with the older source text or the user's unknown loadout.
5. Run native rendering and actual-resource checks after source integration,
   followed by iPhone 17 Pro Max acceptance.

The legacy presentation path can still derive motion speed/trail activity from
all equipped weapon sides. Per-strike side restrictions currently govern
gameplay collision; target-specific blade trails and sound timing still need
presentation acceptance.

## Publication state

A remote `git push --dry-run` preflight was rejected by automatic approval
review. The stated reason was missing explicit authorization to publish this
new branch and its source. No remote push, PR, workflow dispatch, Site update
or TestFlight upload was performed. Local code and validation continued.

The reviewable batch contains code, tests, tooling and metadata/documentation.
Original media, motion bytes/transforms, IPA/config payloads and keys are not
included. Public submission and a native run require approval for this concrete
batch; approval would not make the unresolved original-parity items complete.
