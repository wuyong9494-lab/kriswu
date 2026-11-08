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
