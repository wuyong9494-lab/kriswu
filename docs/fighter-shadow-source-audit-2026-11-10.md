# Shadow source audit and reconstruction boundary

## Scope

This is an offline diagnostic addition based on local commit
`906e02619ee4f8543aa52b4d5c0be855f91706bd`. It changes no Swift code, gameplay gate,
asset, workflow, build setting, or published branch. It does not reconstruct
either skill. The existing `DuelWeaponFight.supports(.shadow)` guard remains.

New files are the audit script, its synthetic tests, and this document. Existing
native tests and prior resource acceptance are described below, not counted as
tests newly executed for this work.

## What the current source actually provides

- `Sources/ShiftCore/DuelWeaponMotion.swift:55–65`: the production clip contains
  name, frame count, clip SHA-256, source bundle, and kinematic tracks. It has no
  source event schedule or event interpreter. `ticks` uses the documented
  30 FPS preview convention, not verified original playback speed.
- `Tests/SiteTests/DuelWeaponAssetTests.swift:11–27,104–137`: separate acceptance
  evidence preserves base64 raw clip bytes, source array count, and source bone
  IDs. The existing verifier checks the magic, two arrays, dimensions, packed or
  expanded declared sizes, ordered IDs, hash, and exact byte consumption. There
  is no separately framed trailing event section in that accepted layout. This
  is not proof that all meaning of either array has been interpreted.
- `App/Services/DuelWeaponAssets.swift:20–29,54–93`: the entire catalog and each
  exported GLB are hash-bound before sampling. Frame duration and retained
  channels are verified. Hash authenticity is not proof of recovered combat
  semantics.
- `App/Services/GLTFModel.swift:335–369`: animation loading handles translation,
  rotation, and scale channels. It does not load gameplay event instructions.
- `Sources/ShiftCore/DuelWeaponFight.swift:73–83,193–196,285–350`: ordinary
  root deltas move the fighter, the host's 12–78% activity window gates contact,
  and weapon endpoints are swept between samples. None of these distinguish a
  relocation, detached hammer, hidden weapon, return, or valid contact phase.
- `Sources/ShiftCore/DuelGame.swift:212–218`: equipped combat clears the outer
  legacy projectile list every step. Reusing the laboratory projectile without
  designing equipped projectile ownership is not a viable shortcut.
- `App/Services/DuelWeaponEffects.swift:242–277`: the ribbon has a 2.5 m visual
  discontinuity guard and optional shadow material. It explicitly uses host
  activity windows. These visual provisions do not supply combat semantics or
  justify enabling shadow.

Authenticated catalog metadata supplied during this investigation reports:

- `coordinateSpace` is `actor_facing_right_metres`.
- Katana role `shadow` resolves to `s_katana_dash`, 74 frames, source bundle
  `9262b5378a7ea7e66c3b15cfb612a97a.bin`, source path ID
  `1198749689987741031`, raw byte count 138,882, two arrays, 78 bone IDs. Raw SHA-256
  is `42848d44d9b08effddf3e9dcad7c3feb93bd2d44795e5fa3d5ff4a27067410ce`.
- Dual-hammer role `shadow` resolves to `s_dual_hammers_throw`, 86 frames, source
  bundle `fb23429d844a55b8171a227187a7b46b.bin`, path ID
  `1152929322118614009`, two arrays, and 70 bone IDs. Raw SHA-256 is
  `349b1d86136b48aaa5e3aae5b064bb1098efc50473c0e7b08c0448357d715e2e`.
- Clip fields are `name`, `frames`, `sha256`, `bundle`, `sourcePathID`,
  `sourceBytesBase64`, `sourceArrayCount`, `sourceBoneIDs`, and `tracks`.
  No explicit event, visibility, projectile, or contact field is present.
- Both source path IDs are decimal strings in the authenticated JSON. Keep
  them exact rather than passing them through floating-point representations.
- GLB animation extras contain only `sourceSHA256`, `sourceFrames`,
  `sourceFPS` (null), `previewFPS`, and `sourceBytesRetainedInProfile`; they
  supply no missing event metadata.
- Provenance says `contactWindowsRecovered` and `gameRulesRecovered` are false.
  The original tangent array is retained but not consumed by the export's
  interpolation. Translations are linear; rotations use normalized shortest-arc
  interpolation. The raw arrays therefore must not be replaced by resampled
  exports or assumed to supply authoritative contact timing.
- GLB pelvis X/Z is zeroed; the root track retains horizontal displacement from
  the first frame. Source pelvis Y remains in the pose; root Y is informational.
  Ground lift is applied once. This coordinate contract must survive any future
  event interpretation.

The documented 8.4594 m katana root and 7.7835 m hammer-tip half-frame jumps are
review targets, not evidence of when to inflict damage, hide a mesh, or spawn a
projectile. The authenticated in-memory audit below confirms these displacements
without recovering their event semantics.

## New offline diagnostic

`scripts/audit_fighter_shadow_sources.py` accepts only an explicitly named
plaintext catalog and its expected SHA-256. It does not locate assets, decrypt
anything, use credentials, follow source bundle names as paths, or contact the
network. It exclusively creates the requested report and refuses to overwrite
existing files, including the input. Keep actual-resource reports private until
their contents have been reviewed for the intended audience.

Example, after an authorized owner has already materialized the catalog:

```sh
python3 scripts/audit_fighter_shadow_sources.py \
  --catalog /approved/local/SF3_DistinctFighters.json \
  --expected-sha256 c4ee840d89cf1b2b8b82db0aebce878dbc5c2f2f60a52cf5b5a77b84f139ed5f \
  --output /approved/local/shadow-source-audit.json
```

The report preserves catalog, raw-clip, and individual-array hashes; source
bundle/path ID; exact array offsets/sizes; and the largest stored-track intervals
in zero-based source frames. Array payloads remain opaque. Raw bytes, full
tracks, and unrecognized metadata values are not copied into the report.

An authorized caller can avoid materializing the catalog by importing the module
and calling `audit_catalog(catalog_bytes, expected_sha256)`. It returns the same
report dictionary in memory without reading or writing files. The CLI alone
performs explicit input/output file access.

The default 1 m review threshold is only a way to prioritize inspection. It is
not a collision threshold, automatic discontinuity classifier, or proposed
teleport rule. Track distances remain in their stored coordinate space rather
than pretending to be world-space contact sweeps. Reports always state that
source timing and event semantics were not verified and gameplay enablement is
not permitted by this audit, even if future input has fields named `events`.
For this known unrecovered baseline, both root `provenance` fields
`contactWindowsRecovered` and `gameRulesRecovered` must be explicitly boolean
false. Missing, true, null, numeric zero, or string values are rejected instead
of silently reclassifying new or unknown source provenance.

## Concrete next source-recovery step

1. Have the already-authorized asset owner run the audit on the pinned catalog.
   Verify both shadow identities, exact binary consumption, and the flagged
   frame intervals. Do not edit, clamp, smooth, or crop the raw tracks.
2. Using each clip's source bundle plus path ID, locate its owning references in
   the matching source-package index. Inspect related serialized move/config
   objects or controller definitions if present. Record absence rather than
   inventing a sidecar. Bind any recovered payload to package version/platform,
   bundle hash, object ID, exact bytes/offset, and parser version. Android 1.45.3
   and iOS 1.46.1 are documented separately in
   `fighter-sf3-resource-2026-11-08.md`; do not silently mix them.
3. Recover and verify the actual clock and event-to-frame mapping. A method name,
   animation peak, or a 30 FPS export is not enough. Required semantics include
   relocation destination/facing rules, actor and weapon visibility, projectile
   detach/owner/trajectory/return/despawn, permitted contact phases, and
   interruption/cleanup behavior. Preserve unknowns as unsupported.
4. Only after source evidence exists, design a separate versioned event model
   and fail-closed capability validator. Keep raw source data unchanged. Event
   timing, actor placement, collision continuity, and visible state must derive
   from the same simulation step. Never sweep through a relocation gap or use
   the held hammer and detached hammer as two simultaneous damage sources.
5. Future gameplay state additions must also update canonical replay encoding
   and its stored-property audit, rules/schema versions where required, and
   network compatibility checks. See `Sources/ShiftCore/DuelReplayState.swift:
   181–208` and `docs/fighter-replay-state-encoding.md`. A rendering-only change
   cannot satisfy this requirement.

If the original event owners are not recoverable, the task remains blocked on
source semantics. The existing controls must remain disabled rather than
presenting invented timing as an original skill.

## Existing protections versus future acceptance

Existing source tests, not newly introduced here:

- `Tests/SiteTests/DuelWeaponGameplayTests.swift:48–69` asserts both shadow
  resources remain present but cannot move actors, damage, consume energy, or
  generate contacts when pressed.
- `Tests/ShiftCoreTests/DuelWeaponFightTests.swift:210–240` ensures unsupported
  shadow/ranged presses cannot occupy recovery or hit-stop queues.
- `Tests/SiteTests/DuelWeaponAssetTests.swift:151–265` checks actual hashes,
  source arrays/channels, and native half-frame weapon geometry. That does not
  verify original source event semantics.
- `Tests/SiteTests/DuelWeaponEffectsTests.swift` uses explicit synthetic shadow
  poses to test source-material rendering and clock behavior. It does not
  establish playable shadow skills.

Future acceptance must add authenticated event fixtures and expected source
sequences, no contact across relocation/hidden phases, correct detached weapon
ownership, exactly-once contacts/effects, mirrored behavior, walls and targets,
interruption and round reset, pause/background/resume/teardown, replay parity,
and original-versus-native visual sequence review. Synthetic interpreter tests
are useful but cannot replace actual-source acceptance.

## Verification of this addition

- 13 new synthetic Python tests and all 16 existing network-rules script tests
  passed (29 total). New cases cover byte/hash/framing failures,
  bounds and duplicate IDs, packed/expanded declared sizes, sample indices,
  non-finite/overflow coordinates, invalid tracks, provenance retention, no raw
  payload output, input immutability, exclusive output creation, symlinks,
  canonical Int64 decimal-string identities, and strict recovery booleans.
- No Swift/native tests were run here. This executor has no Swift compiler;
  no CI was launched.
- No source events were recovered, no shadow capability was enabled, and no
  repository or media publication was performed.

### Authenticated in-memory catalog verification

The authorized asset owner subsequently ran the helper successfully against the
authenticated catalog in memory: 13,211,630 bytes, SHA-256
`c4ee840d89cf1b2b8b82db0aebce878dbc5c2f2f60a52cf5b5a77b84f139ed5f`.
No raw catalog file was materialized. Only the audit report was saved privately,
outside the repository.

- Sun's raw clip is 138,882 bytes; Liu's is 144,802 bytes. Each contains exactly
  two arrays with zero trailing bytes.
- Sun's largest root interval is 8.459406 m, samples 65 to 66, corresponding to
  zero-based source frames 32.5 to 33. Eight root intervals exceed 1 m.
- Liu's right hammer tip has a maximum interval of 7.783473 m, samples 42 to 43
  (source frames 21 to 21.5); nine intervals exceed 1 m. The left tip has a
  maximum interval of 4.789786 m, samples 106 to 107 (source frames 53 to 53.5);
  four intervals exceed 1 m.

These are stored-track displacement-review findings, not recovered contact,
teleport, visibility, projectile, or source-FPS semantics. The shadow gameplay
gate remains unchanged.

## Original Android motion bundles traced

The saved Android 1.45.3 motion/source backup was inspected read-only after the
catalog audit. Both exact source bundles match their saved SHA-256 values.
The katana bundle contains 60 TextAssets and one AssetBundle; the hammer bundle
contains 22 TextAssets and one AssetBundle. All 82 clips match the saved motion
index by name, path ID, byte count and hash, and consume exactly two arrays.
Their container/preload references are one-to-one local clip links. Both bundles
have empty dependencies, external references and script references, null main
assets, and no unconsumed AssetBundle bytes. No controller or event sidecar was
found in these bundles.

Additional source motions include katana ability start/hit/miss/passive/reaction
and hammer throw hit/miss/passive-start/passive-end clips. Their existence does
not establish transition order, participants, contact windows, or compatibility
with the currently mapped shadow clip.

The wider Android index identifies two useful FX leads:

- Katana dash: `e3952b4c6d938bc40073572fdb98ab17.bin`, 97,678 bytes, SHA-256
  `5ec3fbcad36ddf5a436dcae44f7cee46884156d768332c77ad64f5ae6d7b8e05`.
  Its container directory is
  `assets/gamedata/resources/effects/prefabs/shadow/shadow_katana_dash/`.
- Hammer effects: `45eba7001704cc3f95e6ae975a34eb6c.bin`, 240,853 bytes, SHA-256
  `b4b45d1b1ff3ea3c09347172bb985a5202be1e6e97831690f522b7fae75f43d4`.
  Its container directory is
  `assets/gamedata/resources/effects/prefabs/shadow/mash/`.

These FX bundles are index-only in the saved backup: their bytes and the full
matching Android APK are unavailable in the current workspace. Their indexed
MonoBehaviours are leads for further source tracing, not recovered event
authority. A separate iOS 1.46.1 encrypted configuration checkpoint must not be
substituted for the Android 1.45.3 move semantics. No source FPS, transition or
combat-event interpretation was established, and shadow remains disabled.
