# Liu: original King of Serpents body recovery

## Requested identity

The user changed Liu Quanwei's delivery target from Pangu to **King of Serpents / 蛇王**.
The original supplied client identifies this set as **D13**, collection
`D_LEGENDARY_WPN_SHUANGOU_01_04`. D14 is a different set and is not substituted.
WuYong remains the separate D15 Erlang character.

The original Chinese and English localization TextAssets bind both
`D13_set_title` and `CHAR_KING_OF_SERPENTS` to this identity. Their SHA-256 values
are `d2fc0dbbb23f452b557822607987b4d66b1fa6b300bdda5a1c5bcfdcb8f0b88d`
and `360c79ae9ab3e1b594900063c14cb13c4a479e6571d3c91137d6a419e0bb3c07`.

| Original equipment | Original model | Chinese localization |
| --- | --- | --- |
| `WPN_SHUANGOU_01_04` | `wpn__shuangou_01_04` | 毒牙 |
| `ARM_AGL_41` | `arm__agl_41` | 王者鳞片 |
| `HLM_AGL_41` | `helm__agl_41` | 巴西利斯克凝视 |
| `RNG_BOTTLE_01_02` | `rng__bottle_01_02` | 女巫的王牌 |

## Actual recovered bytes

Six exact original bundles were recovered through the previously authenticated
source route, using ZIP member offsets, HTTP 206 range checks, original local
headers, CRC-32, lengths and the original catalog SHA-256 values. The six bundles
contain 4,042,181 bytes; total transferred range data including headers was
4,042,659 bytes. No whole APK or client run was needed for these resources.
The four equipment bundles, D13 effect bundle and thirteen-clip D13 audio bundle
are now real local files, not merely catalog names.

Three further support-model bundles explicitly referenced by original
CreateModel actions were recovered separately: agile cloud, islander push and
islander root. `mgc__common_model_40` was already verified locally. The similarly
named `mgc__snake_liana` was not substituted for those original collision rigs.

## Geometry conversion

`build_serpent_source_geometry.py` authenticates the exact original bundles,
decoded male ModelObject/BonesData documents, shared 64-node actor and supplied
Liu portrait. It produces seven active equipment meshes with 13,963 source
vertices and 17,396 source triangles. Both original hook attachment subtrees,
including their collider nodes, yield the actual 80-node rig.

Two details required source-specific handling:

- The tabard and lower cloth are authored with a real -90-degree X mesh-prefab
  rotation. Their vertices and inverse binds are consistently converted into
  actor coordinates. Ignoring this transform would rotate the cloth away from
  the body; the source values are recorded in the receipt.
- Each hook uses Unity's index-only OneBone layout. Unit weights are reconstructed
  only for the exact authenticated one-index channel layout and single bind
  bone. A missing weight array on any other layout is rejected. Unity documents
  that layout in [SkinWeights.OneBone](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/SkinWeights.OneBone.html).

The original helmet sets `Headless=1`. Liu's supplied head and neck meshes and
images remain preserved in the private container, but are outside the active
scene while the full source helmet is equipped. This avoids overlapping a
personal face with the source mask. No synthetic face or replacement armor was
generated.

Static GLB: 6,117,296 bytes, SHA-256
`b9d2b7a9696dc5a500bc3d51678e2133c80075d077d82d5b218a3cd4584e26c1`.
The written skin inverse-bind readback maximum difference was
`2.6133649262405356e-6`. The embedded scene contains exactly seven active meshes
and two preserved, inactive personal meshes.

## Actual body animations

`prepare_serpent_animated_body.py` consumes the independently recovered,
type-preserving 454-record named configuration. It resolves each motion by the
**full original resource path**, the original bundle and TextAsset path ID,
length and SHA-256. This distinguishes Dynasty's 18-frame forward step from the
different common motion with the same filename stem.

The result contains 54 original configured body motions: eight D13 body aliases,
thirty Shuangou aliases excluding the Dojo-only record, and sixteen ordinary
movement, block, hit and kick records. Eleven D13 model aliases are excluded
from the humanoid rig. They require their actual projectile or magic-model rigs.
Poison Ability and Deadly Intoxication retain distinct original configurations
even though their source body animation bytes are shared.

The exporter retains both original motion arrays, native first/end frame crops,
source frame stride, AnimationEnd threshold, actual half-frame FK, four source
hook/handle capsules, fifteen source body capsules, and the original mass table.
The 69-frame Shuangou round-start crop is original indices 61 through 129.

| Private product | Bytes | SHA-256 |
| --- | ---: | --- |
| Animated GLB | 14,081,224 | `7d47a59c85832a671de191988b95258fd7cdf85b783e5ceb34aa05aba3c4882e` |
| Animation source profile | 18,716,684 | `e0a4d94a15651a189c14c350f3d6820cef2ca0ad40348ffa9de39df19557afce` |

The actual written GLB was read back against retained original animation arrays
and profile FK. All 54 clips passed, with 355,264 compared values and maximum
difference `2.2252400722067023e-7` meters. Static geometry, portrait data, material
definitions, skins and the original binary prefix remained unchanged.

Six targeted tests passed with zero skips: strict OneBone acceptance/rejection;
source cloth transforms and helmet scene policy; real crop and alias semantics;
named-configuration mutation rejection; capsule-track mutation rejection; and
rejection of missing body tracks/model-only substitutions. Offline Blender
inspection of the real GLB also confirmed the source equipment and animated
stance. That rendering is not an iOS or in-game acceptance result.

## Remaining integration

These are authenticated source candidates. At this checkpoint the new body is
not yet an activated match profile. The executable D13 skill state, true
projectile/contact bindings, source effects/audio, common paired reactions and
native match acceptance are still being integrated. Portable material paint
previews do not claim original custom-shader or cloth-physics parity.
No historical missing SHA was forged, no release integrity gate was relaxed,
and no TestFlight upload was performed by this recovery.
