# WuYong D15 static geometry recovery — 2026-11-16

## Actual result

`prepare_erlang_geometry.py` produced a separate static GLB from the exact
locally restored original skeleton, six armor parts, primary left spear,
original bone configurations, and the supplied WuYong portrait. The command
completed with exit 0. Its existing geometry and material functions were reused
without modification.

| Output | Bytes | SHA-256 |
| --- | ---: | --- |
| `WuYong_Erlang_D15_Static_Source.glb` | 10,379,416 | `fe02e7c96d99905e70af712cfd0b52bea1d6d3b732f07eb44bbe5fe6b8182f39` |
| `geometry-source-receipt-private.json` | 32,390 | `ded6bbc5d5fb98a5a6ae8b245d6a4aa984283668921401de4a1145e0ddad326c` |

The written binary has 89 nodes, eight meshes, one skin with 80 joints, and
zero animations. The original skeleton supplies 64 nodes and the source
weapon attachments supply 16. This recovers actual inspectable geometry;
it is not the historical animated body, a character profile, or a release pack.

## Exact source inputs

The existing source archive/catalog checks and every input digest remain
unchanged. The existing builder verifies mesh selection, original skin path
hashes, shared bind matrices, skin weights, original material keywords,
texture bindings and opaque raster properties.

| Source | SHA-256 |
| --- | --- |
| Original actor `00a21255143c2e6368ba9b34e6914d68.bin` | `a4d032522e8fa3dc612c663ecb7f1aa094fe9bc4719c939c45fd558fca8e39a9` |
| Original armor `21459e232b8ef3f21ee744adf72717f6.bin` | `af28425ecbadd094ee460d94086eccd7a165246e0def9627e25730697b5c3e4f` |
| Original spear `e76bb58980e9e1aa0f9ca0c4b20c0d93.bin` | `bc2be58ee4769b03b088154104b1cf68b3e6307a5a12307a46d003aab3a82b40` |
| Supplied WuYong personal portrait | `279b7d840bbb99550f82e3c283a5a6e58753e7793be225259621f2dfc2a75cd0` |
| Original base bones | `0a5e4b58c5900ddf0bc9a019305b72f628919a4562050349e5f3ee3809e6e455` |
| Original full-body bones | `5fbd5b097b318b58cddef0d63dd94e1addd931882124ad05a3dd9712f0d0ecd8` |
| Original spear bones | `3e768ac7e6a76a30d7eb530428ffb56617da5dd921701f7b284b65231c69fe9c` |

## Actual mesh and material targets

The following names were read from the saved GLB. No mesh has a `head_`
prefix. This result is relevant to the original Avatar selector, which cannot
be mapped to the personal portrait solely by assuming a compatible name.

| Mesh node | Skin | Parent | Material |
| --- | --- | --- | --- |
| `arm__agl_44_m` | 0 | `SF3_Actor_Meters` | `mat_arm__agl_44_base` |
| `arm__agl_44_m_tie` | 0 | `SF3_Actor_Meters` | `mat_arm__agl_44_tie_base` |
| `arm__agl_44_m_tie_back` | 0 | `SF3_Actor_Meters` | `mat_arm__agl_44_tie_base` |
| `arm__agl_44_m_tie_stripes_down` | 0 | `SF3_Actor_Meters` | `mat_arm__agl_44_tie_base` |
| `arm__agl_44_m_tie_stripes_up` | 0 | `SF3_Actor_Meters` | `mat_arm__agl_44_tie_base` |
| `arm__agl_44_m_tie_tabard` | 0 | `SF3_Actor_Meters` | `mat_arm__agl_44_tie_base` |
| `wpn__agl_spear_01_01__l` | 0 | `SF3_Actor_Meters` | `mat_wpn__agl_spear_01_01_base` |
| `WuYong_Personal_Head` | None | `head` | `Material.001` |

The saved portrait contains 59,878 vertices. Four attribute/index arrays were
read back and compared with the supplied portrait; all were equal. Its three
encoded images are byte-identical. The portrait remains unskinned and rigidly
parented to the original head bone. The fit, front-direction adjustment,
outer 0.92 scale and portable material lighting are existing explicit
presentation adaptations, not newly recovered original gameplay behavior.

## Validation and remaining boundary

The normal GLB container validator ran before saving. A separate readback of
the written binary checked the node/mesh/skin counts, single-parent hierarchy,
head binding, portrait arrays and embedded images. It also recorded the real
renderer/material inventory above. No native SceneKit rendering occurred.

The helper writes only the static GLB and its receipt, outside the repository.
It does not consume or reproduce the missing historical throw-reference
catalog, does not export human clips or combat rules, and does not emit a
profile accepted by the production resource loader. The historical animated
body digest, the 302-file base, the full 440-file candidate and App identity
remain unchanged. There was no protected workflow, signing, or TestFlight
operation in this conversion.

The static geometry can now serve as a concrete input for source-selector and
material-binding review. Original Avatar shader compilation, runtime selector
mapping and complete animated character acceptance remain separate work.
