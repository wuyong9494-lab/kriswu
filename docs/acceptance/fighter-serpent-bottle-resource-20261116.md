# D13 original equipped bottle recovery

Continuation after action adapter commit
`6f81d3dddbaa715401be01b84344e27c71d8dca6` on the existing fighter branch.

`recover_serpent_bottle_model.py` now exports the actual equipped
`rng__bottle_01_02` resource and its `D13_Bottle_Throw_Model` motion from the
already recovered source bundles. No new network download or native workflow
was used. The private resource is `SF3_D13_Bottle_Source.glb`, 291,180 bytes,
SHA-256 `5ccf41b00f10b3e504012a33e8f6212c7935a2ff4ac65b831eedfab2d91626cd`.

## Recovered data

- Original seven-node prefab hierarchy, all five animated bone IDs, native
  inverse binds and the two separately selectable mirrored mesh variants.
  Each variant has 425 vertices and 694 triangles. Exact bone path hashes bind
  the left/right meshes to their corresponding gun joints.
- The source uses Unity's serialized OneBone layout: one stored bone index and
  implicit unit weight. A separate exact-bottle gate handles that layout; the
  previously restricted hook exporter was not loosened.
- Original embedded textures, palette parameters and material metadata are
  retained. Portable GLB lighting is a preview adaptation; original custom
  shader/ForceGlow parity is not claimed. The ModelObject configuration remains
  in the private source record, including its mirror and ForceGlow declarations.
- Both original compressed motion arrays remain in the private record. The
  reviewed first array drives the source-coordinate export. Runtime facing,
  source mirrored selection and parent-pelvis X alignment remain explicit
  adapter responsibilities.
- Source FirstFrame 5 and EndFrame 30 are applied to the actual 29-frame source
  using the existing native clamp: indices 4 through 28, 25 real samples and
  49 half-frame verification ticks. SelfEndFrame 0 gives AnimationEnd tick 48.
  No thirtieth frame is invented or extrapolated.
- Original lock 1402 creates the agile cloud at that AnimationEnd and then
  deletes the bottle. The body release event remains the equipped-Ranged
  IntervalStart from lock 1400. The bottle animation declares no Attack
  intervals; its available source capsule declarations do not invent damage.

## Verification

The GLB was read back against the original compressed animation arrays and
source mesh/inverse-bind data at every half-frame:

| Check | Result |
| --- | --- |
| Bone matrix comparisons | 245 |
| Maximum matrix element difference | 1.0490432833520913e-7 |
| Skinned vertex comparisons | 41,650 |
| Maximum vertex difference | 1.1073968453345628e-7 metres |
| Exported mesh variants | 2 |
| Python resource tests | 3 passed; zero failures/skips |

The negative test deliberately corrupts key timing, root motion, mesh position
and mirrored bone binding; all four variants are rejected. Blender rendered
the actual exported GLB at an intermediate pose. Visual inspection confirmed
the bottle geometry and embedded green/rope material. The PNG is an offline
resource inspection, not an iOS game screenshot or device acceptance.

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=scripts:"$UNITYPY_PATH" \
  python3 scripts/recover_serpent_bottle_model.py \
  --recovery "$RECOVERY_ROOT" --archive "$MOTIONS_ARCHIVE" \
  --output "$FRESH_OUTPUT_DIR"
SERPENT_BOTTLE_OUTPUT="$FRESH_OUTPUT_DIR" \
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=scripts:"$UNITYPY_PATH" \
  python3 -m unittest scripts/test_serpent_bottle_model.py -v
```

## Remaining boundary

The cloud prefab itself is present in the recovered model bundle. Its source
configuration references `ranged/universal/s_rng_agl_cloud_bullet.bin`; that
exact motion is absent from the authenticated motion catalog, and no matching
ranged-universal animation bundle occurs in the authenticated bundle catalog.
This is a bounded finding about the recovered sources, not proof the original
asset cannot be obtained elsewhere. No generic cloud motion was substituted.

The new bottle is a recovered resource, not yet an installed flight model in
`DuelWeaponFight`. Source cloud/ground timing, zone contacts, actual particle
assets, source input gates and the rest of D13's skill paths still need complete
integration before full-fighter registration and native/device acceptance.
This continuation does not upload TestFlight or change the existing H17/D15
body resources. Original model/configuration bytes stay in the private recovery
package; this public commit contains exporter, tests and this receipt only.
