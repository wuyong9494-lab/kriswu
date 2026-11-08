# Shadow Fight resource adapter — 2026-11-08

Base: `262aad2d3ae38c4470c95fff711a72512ca556cf` (verified TestFlight 586).
The optional stage changes presentation only; existing combat timing, damage,
character selection, other games and reminder functions are unchanged.

## Implementation

- glTF imports preserve a valid second UV set. The optional `extras.sf3Lightmap`
  binding uses that set for a baked color lightmap and requires an unlit material.
  A missing second UV set or broken texture reference fails loading. Ordinary
  assets without this binding retain their material behavior.
- `KHR_materials_unlit` remains unlit even when the caller enables PBR for the
  character pipeline.
- A separately staged `SF3_Palace_Exterior.glb` is verified by size and SHA-256,
  loaded once per match and released with the scene. Its perspective camera
  fits the existing combat area. Baked scenery does not cast duplicate shadows
  on the fighters. When this optional file is absent, the existing arena loads.
- Native synthetic pixel tests distinguish the diffuse and lightmap UV sets and
  check rejection of missing UVs / invalid lightmap references.

## Asset evidence and limits

The source candidate is the official Xiaomi Android 1.45.3 package, rather than
an exact iOS 1.46.1 companion. Its runtime serialized-file version was read as
Unity 6000.3.11f1. Full download and resource indexing are being completed.

The current static palace conversion contains 24 meshes, 30,087 triangles and
four embedded textures. The GLB is 9,292,540 bytes with SHA-256
`185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8`.
It was imported and rendered offline with the existing Liu model. Projected
character shadows, animated fire shaders, particles and sprite effects are not
implemented by this static conversion. No complete gameplay equivalence is
claimed. This resource file is not included in the public code commit.

An independent compressed-motion decoder read representative real animation
frames and bone transforms. Retargeting, source playback rate, hit windows and
native motion acceptance remain separate work. Sun Deng's supplied source is a
static upper-body mesh and still needs a complete body and a battle rig.

## Verification

- Local `git diff --check`: pass.
- Linux executor has no Xcode / SceneKit. Native tests must run in the existing
  unsigned fighter workflow. Synthetic fixtures do not validate the private
  converted map on a device.
- No release or TestFlight upload is part of this adapter change.


## Supplementary package and personal-character follow-up

The official Xiaomi Android 1.45.3 package finished downloading: 2,683,387,431 bytes,
SHA-256 `29eab6cb60ebec8aeb0a47c2efcfebc5e38320c2c659add3fa5670067ece13ab`.
All 3,434 ZIP entries passed CRC validation. All 2,205 Unity bundles indexed without
parse errors: 55 locations, 8 lobby locations, 128 animation bundles, 170 effects
bundles and 119 audio bundles. These are package categories, not accepted playable
maps or implemented skills. The iOS IPA remains 1.46.1; Android resources do not
establish identical platform/version behavior.

The compressed-motion decoder now recognizes both observed declared-size forms
(packed 12-byte and expanded 28-byte transform sizes), with strict dimensions,
bone IDs, byte consumption and quaternion validation. All 2,711 motion TextAssets
passed those structural checks. Source playback rate and combat timing remain
unverified. An experimental punch retarget failed visual acceptance (bone-axis
and mesh deformation problems); it is excluded from the application.

The autumn lobby conversion resolves two shared dependencies and retains separate
UVs and baked lighting. Its custom fog/projector/particle/MatCap effects are not
reconstructed. The static lobby and palace have offline Blender previews; these
are not SceneKit or iPhone screenshots.

Sun Deng's supplied file is a static bust. The full-body prototype preserves his
head/neck and uses the existing complete clothed body with the 42-bone rig and
12 existing clips. A first cut-shirt splice failed visual review and was replaced.
This prototype still needs native skinning/seam/performance acceptance. It does
not contain accepted SF3 moves.

The app maps the existing `ember` identity to Sun Deng, loads each personal model
with a separate SHA-256/size identity, and pairs Sun Deng/Liu in personal matches
and after restart. The legacy Gale training character is retained. The lobby uses
a separate static SceneKit view and releases its resources before a fight.
Missing or invalid private assets retain the existing procedural presentation.
No raw assets or personal portraits are committed publicly.

Validation of commit `2c56dbe869c6259fd5f9ffc04c72834a13f8ba2b`:
GitHub Actions run 42442176810 passed unsigned device compilation, core regressions,
21 native unit checks (including both lightmap tests), and 2 touch-driven UI flows.
The separate private-character job was skipped: this is not acceptance of the
new real scenery or Sun model. The follow-up lobby/pairing changes require a new
run. This branch is unsigned-only and has not uploaded a new TestFlight build.
