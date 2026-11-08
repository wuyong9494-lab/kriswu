# Original-rig review adapter

This is staged visual integration, not a gameplay profile switch. The existing
`DuelCharacterAsset`, `DuelCharacterAnimation` and Liu three-second grapple are
unchanged. No source motion is retargeted onto their 42-bone rig.

`DuelOriginalRigAsset` loads either approved Liu or Sun original-rig GLB using
an exact byte count and SHA-256, validates the 64 original skeleton node names,
personal head, 25 source moves plus diagnostic TPose, and decoded clip intervals.
Missing or wrong assets fail; there is no silent fallback. It uses existing
`GLTFModel` mesh/skinning/interpolation support and independent instances.

A review surface can create `DuelOriginalRigInstance(asset)`, attach its
`instance.root` to a SceneKit scene, then call `apply` with a
`DuelOriginalRigReview.Selection`:

- `init(clip:phase:)` scrubs the entire clip from 0 through 1.
- `init(clip:sourceFrame:)` steps zero-based decoded source frames.
- `init(clip:previewElapsed:looping:)` plays at the explicitly assumed 30 preview
  FPS; one-shot playback holds its final pose and looping is opt-in. The caller
  owns elapsed time, pause/resume and restart. Loops are not certified seamless.

Selection is stateless; no blend history or hidden wall clock obscures a frame.
Every apply resets from rest before sampling the original channels. Non-finite
inputs reset to the first frame. Asset sampling includes the exported nonzero
start time (1/30 second); do not infer source frame count from the first channel,
because Blender optimizes constant tracks down to two keys.

The core catalog preserves source motion names, hashes and frame counts from
`OriginalRigReview/research/personal_action_set.json`. TPose is generated, not a
26th source move. Source FPS and combat timing are explicitly unverified.
Horizontal pelvis motion was removed by the exporter. No guessed wrist peak,
forward direction, startup/contact/recovery boundary or combo splice is supplied.
The source set has no Grab, SideLock or Release, so it cannot directly play the
existing grapple profile. Playback does not move the gameplay simulation or
change hits. The subsequent [runtime integration](fighter-original-runtime-2026-11-08.md)
adds a separate presentation adapter with application-authored pose windows and
a blended arm hold on the original bones; this review sampler remains exact.

## Verification

- `swift test --filter DuelOriginalRigReviewTests` exercises catalog boundaries,
  source frame controls, decoded offsets, clamping and explicit preview looping.
- Native `SiteTests/DuelOriginalRigAdapterTests` requires both private GLBs staged
  in the app resources. It compares adapter samples against direct decoding for
  every source frame, checks independent actors and repeated/reversed scrubbing,
  and rejects mismatched identity before decoding.
- Native `DuelOriginalRigAssetTests` separately reviews poses and rendered output.

Neither a passing loader test nor preview rendering certifies combat equivalence,
face/neck quality, on-device performance or source-game hit timing.
