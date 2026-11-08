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
Unity 6000.3.11f1. The full download and resource index are complete, as detailed below.

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
static upper-body mesh; the prototype described below adds an existing body and rig.

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


Follow-up run 42443778433: unsigned device/core/envelope checks and both UI flows
passed. Of 23 native unit checks, the new lobby scene lifetime assertion failed
while inspecting an Objective-C scene before the surrounding autorelease
pool drained. The follow-up detaches all scene nodes immediately at shutdown and
checks that the closed scene is released after a scoped autorelease pool drains,
while deliberately retaining the view. No sleep, relaxed assertion, or skipped
check is used. Three repeated lobby entries are checked. A new native run is
required to confirm this fix.

The new encrypted asset upload was rejected by automatic approval review on the
ground that this new personal-model copy had not been explicitly approved for
publication to the public repository. No new binary resource was published. The
three resources, their 56 encrypted parts, verified fingerprints, and a fail-closed
staging helper are retained privately for review. Existing key handling is reused;
no new key or credential has been committed.

## Final code verification

Commit `110878227a23196f57ebf28909e2cc18c3181de0` passed GitHub Actions run
[42444782188](https://github.com/wuyong9494-lab/kriswu/actions/runs/42444782188):
unsigned Release device compilation, core regressions, authenticated-envelope
checks, all 23 native unit tests, and both touch-driven UI flows. The three-entry
lobby shutdown/lifetime test passed. The device concurrency-warning gate passed;
the native log contains no invalid empty-fragment modifier error.

The private-character job was skipped. None of these results validates the new
Sun model, autumn lobby, or palace resource inside SceneKit. Those three binary
resources remain unpublished after the automatic approval rejection above.
No TestFlight build was uploaded.

Separately, offline deformation sampling checked all 12 existing Sun prototype
clips at 34 distinct start/middle/end poses. All skinned coordinates were finite
and within the coarse 4-metre span limit. This catches obvious broken geometry;
it does not establish seam quality, natural motion, contact accuracy, original
SF3 motion timing, or device performance.

The updated private integration checkpoint contains the four model/scenery GLBs,
56 encrypted parts for the three new resources, fingerprints, conversion limits,
offline previews, and deformation evidence. The separate source archive preserves
128 motion bundles and the selected scene dependencies. The next native asset
step requires explicit approval to publish the encrypted new resources to this
public repository, install the staging helper, and run private-character checks
with the existing repository secret. Raw models and the secret remain private.

## Personal action-set continuation — pending private review

Published code `eb30292b8efb445edf25ee424f2a66ae4c87a4b7` passed run
[42446932642](https://github.com/wuyong9494-lab/kriswu/actions/runs/42446932642):
unsigned device/core/envelope checks, 23 native unit tests and 2 UI flows. The
real private-asset job was skipped. The three-resource manifest stager and strict
`DuelPersonalAssetTests` are present; their actual new asset acceptance is pending.

Further offline work recovered the full 64-node source actor hierarchy and the
original inverse bind poses/vertex weights for the male `arm__agl_10` body.
All 53 skinned source bones matched their full-path CRC32 hashes. The three body
meshes contain 6,174 triangles. The earlier simplified 44-node effects skeleton
and 42-bone white-suit retargets are not accepted assets.

Two separately named review GLBs retain the personal heads on this original
combat body, with 25 selected unarmed clips plus one diagnostic bind-pose clip.
The underlying source set has 1,119 frames. Horizontal pelvis motion and per-clip
authoring offsets are removed; preview playback assumes 30 fps because source
rate is not established. Original mask/lighting shaders are not fully reproduced.

Close-up review caught a deformed lower jaw caused by incompatible old neck/chest
weights. Both reconstructed faces now attach rigidly to the head bone, with a
separate weighted neck bridge. Liu's old collar fragments were removed. The
final models each passed 1,121 frame/endpoint geometry evaluations with finite
vertices and a coarse four-metre span bound. A regression check requires every
personal-face vertex to be weighted only to the head. This is not native contact,
seam, timing or device-performance acceptance.

The original-rig assets cannot silently replace `DuelCharacterAsset`'s current
42-bone gameplay profile: its named joints, custom grab/side-lock/release clips,
contact windows and sole markers still require adaptation. The local pending
change adds a separate `private_original_fighters` workflow input and strict
`DuelOriginalRigAssetTests`, with actual-file identity checks, all-clip native
pose sampling and encrypted render evidence. It does not enable this profile in
the game. Local authenticated-envelope/model-staging tests passed 22 checks;
the new Swift suite has not yet been compiled or executed.

Automatic approval review rejected both the new encrypted binary publication
and the subsequent source-only tree containing model filenames/sizes/hashes,
citing missing explicit permission for disclosure to this public repository.
No workaround or alternative upload was attempted. These later edits remain
local, based on `eb30292`, and are preserved as a reviewable patch in the private
integration checkpoint. The new two-model envelope has 23 parts and passed a
local decrypt/byte comparison; the existing three-resource envelope has 56 parts.
No key is included in the checkpoint. No TestFlight upload has occurred.

## Skill display and partial upload follow-up

The subsequent reply explicitly allowed uploading in context, but automatic
approval accepted only the first five encrypted Sun-prototype parts and then
rejected part 005, demanding user-authored text naming the public destination.
The five content-addressed blobs are recorded privately for resumption; no
resource tree/commit/ref was published, and the remaining 74 parts were stopped.
No other upload route or reworded payload was attempted.

Independent presentation code was published as
`d94cc3c48151d14d06894a914c35859512211f9b`. The selected hero now has an individual
skill explanation, named skill buttons and explicit energy costs. Sun retains
the existing dash/heavy-knockdown rules; Liu retains those shared basics plus
his exclusive grounded grab, three-second hold and slam/release. This change
does not introduce a Sun ultimate, alter damage/timing, or integrate the new
64-bone models. Existing accessibility identifiers remain unchanged for the
touch-driven tests. Run 42450826805 completed successfully: unsigned iOS device
build, envelope checks, 782 core tests (16 existing skips, zero failures),
23 native tests and two touch-driven UI flows. The actual private-asset job was
skipped; these results do not validate the new models or pending source changes.

The pending actual-asset workflow can run both private suites on this branch
once the approved full encrypted set is committed. The local review patch is
rebased onto d94cc3c; publishing it still requires clearing the resource and
model-derived-metadata approval block above.


## Preserved original-rig playback adapter

The current private checkpoint contains the original 64-node combat body with
personal heads attached directly to its head bone. The earlier cross-skeleton
retarget experiment is superseded; it is not the current implementation route.

A separate `DuelOriginalRigAsset` and deterministic review player now load those
exact two assets and expose all 25 source clips plus diagnostic TPose without
changing the legacy combat profile. Source-frame stepping uses the actual decoded
clip interval, including its nonzero exported start, and does not infer timing
from an optimized constant channel. See `fighter-original-rig-adapter.md`.

The resource publication remains incomplete. Ordinary source pushes keep the
actual private-asset job off; explicit private review inputs require the complete
encrypted resources to be staged. A code-only CI pass must not be reported as
actual original-model acceptance. Local Python checks: 22 passed; YAML parse and
`git diff --check` passed. Native compilation and new Swift tests are pending.
No original-game hit timing, skill behavior, or TestFlight release is claimed.
