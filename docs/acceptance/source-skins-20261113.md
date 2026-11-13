# Original skinned weapon trails: source-backed integration

Continues verified HEAD `39d1b481b3991c95fdf017dd615dd7eb31fd539e`. Build 702 and TestFlight are unchanged.

## Proven source relationship

The four source renderers have null prefab bone slots, but their companion MonoBehaviour `_bindBonesName` lists resolve all slots. Every list matches the mesh bone-name CRC32 hashes and the equipped GLB node paths, in source order. Source motion IDs 260–267 already exist in the equipped character animations. The prior exporter excluded these four meshes.

Katana skins retain 12 vertices / 12 triangles each. Hammer skins retain 32 vertices / 24 triangles each. The new 20,724-byte private payload preserves vertices, normals, UV0, indices, four weights/indices per vertex and all four original inverse bind matrices. Body inverse binds differ by approximately 0.58–0.60 in matrix elements; replacing trail binds with them would be incorrect. Existing body/head/weapon files and their encrypted chunks are unchanged.

## Runtime change

`DuelSourceWeaponTrails` authenticates the optional payload and existing alpha texture, binds to the existing character instance's source bones, and retains source motion sampling. Ordinary attack clips with source trail tracks select these skins and suppress their endpoint-history ribbon. Clips without a verified trail track and shadow effects keep the existing adapter. Sun uses the equipped left katana; Liu retains independently animated left/right hammers. Effects are installed after body bounds are cached, so they do not widen the combat camera's body envelope. Optional payload identity is included in network resource comparison.

The small new envelope uses the existing protected presentation secret with a distinct authenticated purpose. Only encrypted bytes and metadata are public. An absent optional pack keeps the old adapter; a present invalid pack fails before character creation.

## Remaining fidelity limits

The recovered source shader samples alpha from UV0 and equipment color from UV1. These four serialized meshes have no UV1; its runtime population has not been established. This adapter therefore retains verified UV0/alpha with neutral tint. Source lighting, dynamic equipment color and original controller emission/retirement are not claimed. Visibility still uses the application's existing attack window. This is not a claim of 1:1 fidelity.

## Verification

Local: exact three source-bundle hashes and two character hashes; prefab/hash/node binding agreement for all 16 slots; source mesh counts and finite weights; encrypted round-trip and wrong-key rejection without replacing the valid destination; Swift syntax parse and bounded workflow/schema checks passed.

Native scope: exactly two methods, twelve images, 73 staged/compiled resource identities. Eight fixed-pose images cover both heroes, ordinary/heavy and both facings; four production-contact images additionally verify contribution, duplicate-ribbon suppression, freeze and teardown. No prior successful broad suite is repeated.

Run `43399280258`, source `76d493ab9f1e9b2db9303b159a7c3fa8a9135856`: native build and all resource identities passed, but both selected methods failed. All twelve authenticated images were inspected. Two fixed-pose assertions and two production-contact assertions reported zero katana pixels; hammer contribution checks did not fail. The katana is visible from the opposite facing. This is a rendering failure, not a resource-loading success being counted as visual acceptance.

The sampled source topology explains the failure: the equipped katana's twelve triangles all face one camera side; the active hammer has twelve triangles per side. The source prefab's `_Cull=2` does not establish the original runtime facing controller. Our SceneKit actor turns 180 degrees, exposing the back of the single katana surface. The follow-up uses a two-sided material only for that thin katana surface; hammer culling, geometry, indices, animation, alpha, timings and collision remain unchanged. Both pixel thresholds remain unchanged. This explicit facing adapter is an additional fidelity limit until source runtime cull behavior is established.

Local full motion audit covered 30 clips / 1,889 source frames with finite skinned geometry. Sixteen network identity checks and thirteen existing workflow-helper checks passed. These do not replace the pending native rerun of the two failed methods.
