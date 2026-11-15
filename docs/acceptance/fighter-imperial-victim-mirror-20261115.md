# Imperial Spear paired victim assets — 2026-11-15

## Result and scope

The cached original Imperial Spear heavy victim motion now has separate normal
and source-mirrored exports on Sun's and Liu's own rigs. The append preserves
their original geometry, materials, skins, old animation records and complete
old GLB BIN prefixes. It does not activate D19/Pangu equipment.

The shared source is `imperial_spear_heavy_slash_passive`, SHA-256
`75e0ec9ac3674098657aac66d6c3ee51b66f342234aae2a7b33fc3a666a6c411`,
from the already cached `baccadc1bc62c24fcf83246b63fd6c17.bin`.
`settings_style_imperial_spear.bytes` records 9 and 10 share the 120-frame raw
motion and crop it to indices 0...70. Record 10 is precisely
`Imperial_Spear_Heavy_Slash_Passive_Mirror`, with `Mirrored = -1`.

Both aliases retain 71 source frames, 140 full playback ticks and source
AnimationEnd tick 132. Their 141 GLB keys at 60 Hz include the original source
frames and their interpolated half-frames. Floorfall starts at tick 112.
The release's frame/FPS pair describes the source frame window and duration;
the additional baked keys are recorded in GLB extras.

| Profile | Preserved / resulting clips | Character bytes | Character SHA-256 |
|---|---:|---:|---|
| Sun | 68 / 70 | 16,252,036 | `7c9ebfe285f637cbd002f717d80b859a57d3ab11ef491f15930dc4f3eb50d96a` |
| Liu reference | 62 / 64 | 11,585,516 | `d873864549fd7c7c3f2e9450aba12725c1d488f68ccf5c775ef5e889a4c4fe80` |

Roles are `imperialHeavyPassive` and `imperialHeavyPassiveMirrored`. These are
asset capabilities; the complete paired hit selector, contact transition and
runtime alignment require separate integration validation.

## Recovered mirror semantics

Private native proof receipt: 4,064 bytes, SHA-256
`27398036b6909ef505ed2f528fb311acf9936bf13a91dc229e80904e0ee744e3`.
The 21 bounded method records come from the cached, unencrypted framework
SHA-256 `7c192647b0e035bd246c135a59c597ee3910d50fc4ed128abe402da39a62a55b`.
The executable was inspected, not executed.

Method 38157 toggles the current model mirror when `Mirrored` is -1. Direction
resolution in method 38304 happens before this override. This is distinct from
reversing frame order or negating world X. The source body's mirror table uses
26 disjoint bilateral pairs and six self bones:

| Rule | Position | Euler rotation |
|---|---|---|
| Dual, None | target rest minus source rest-relative delta | target rest plus source rest-relative delta |
| Dual, YZ | target rest plus delta multiplied by `[1,-1,-1]` | target rest plus delta multiplied by `[1,-1,-1]` |
| Self, YZ | unchanged | own rest plus delta multiplied by `[1,-1,-1]` |

The helper interpolates the raw source local poses first, then applies the
recovered mirror at each simulation sample. The Z-X-Y quaternion conversion
uses Unity's documented default rotation order, independently described by the
[Unity Mathematics rotation implementation](https://github.com/Unity-Technologies/Unity.Mathematics/blob/master/src/Unity.Mathematics/quaternion.cs).
It rejects singular inputs rather than implementing an unverified native
singularity branch. This reviewed motion remains outside that branch.

The portable Euler bake is not claimed to reproduce Unity's native floating
point results bit for bit. Runtime model-mirror selection and native Apple
rendering remain separate acceptance requirements.

## Export and mathematical checks

`verify_imperial_passive_candidate.py` independently reads the exported GLB
channels back. For every one of the 141 samples in each of the four clips it
rebuilds the own-rig world poses and checks hands, feet, toes, pelvis, weighted
mass centre, original weapon landmarks, and every source hurt/attack capsule
endpoint against the exported profile.

| Rig | Checked points | Maximum error |
|---|---:|---:|
| Sun, both aliases | 14,100 | 5.97e-8 m |
| Liu, both aliases | 11,844 | 5.97e-8 m |

The source quaternion round trip over 141 samples × 58 bones has maximum
quaternion error 9.39e-15. The source rest pose is a fixed point of the mirror
on both rigs, with zero position error and quaternion error below 4.75e-16.
Unknown mirror schemas and singular inputs are rejected.

Initial attempts stopped before creating character outputs: one exposed the
earlier compact-versus-named Sounds tuple representation; another rejected an
older Sun bindings file. The final Sun source binding is the existing
`Sun_DeadForestTriad_Ninjato_provenance.json`, SHA-256
`3e292f26f59830d397cf1471ff4e5c3e62652c0c7f1752694213a48187da893a`.
Neither failed attempt is counted as acceptance.

## Private release staging

`stage_cached_imperial_passives.py` authenticates all 302 files of the post-Stun
release before staging a fresh candidate. It appends only the two new roles
and clips to the production catalog, preserving its later COM, combos and
combat rules. Nine files change and 293 remain byte-identical. The five
dependent media manifests change only their bound character digests; the
original PCM, FX, morph samples and materials are preserved.

The resulting release is 35,631 bytes, SHA-256
`eec331dbc99b73478c4f2c3bae3e7a1d32bd57636b6badc38ae514bc03d33823`.
It is a private staged candidate. No signed build pin, TestFlight upload, or
production Pangu claim follows from this asset check.

## Missing source collision names

The Imperial up attack contains the literal source names `Tight_Left` and
`Tight_right`. They must not be silently renamed to existing thigh capsules.
Native lookup method 36245 compares exact names with `String.Equals` and
returns null if none matches. Its actual attack consumer, method 38174, calls
that lookup at `0x7125b70` and branches from `0x7125b74` back to the next-name
iteration at `0x7125a94` on null. Thus the original runtime skips unmatched
names while retaining other existing leg/foot parts in the same attack.

The source configuration keeps both names; the runtime binding includes only
the source parts that actually exist. No replacement capsule is invented.

## The paired selector's InMirrorPose predicate

The serialized function case 65 was followed through dispatcher 16637,
constructor 28559, consumer 28563 and native method 38302. It reads the
queried model's skeleton, not the opponent's position or stored animation-mirror
override. In lock4797's passive/PostHit context, this is the victim (`Me`);
the attacker (`Enemy`) supplies the separate COM and toe comparisons. Skeleton initializer 37731 binds offset 0x90 to the exact `foot_l`
bone and 0x98 to `foot_r`. The original compressed enum defaults establish
NONE=0, RIGHT=1 and LEFT=2.

For RIGHT the predicate is `foot_l.worldX <= foot_r.worldX`; for LEFT it is
`foot_l.worldX >= foot_r.worldX`. A missing foot returns false. The gameplay
adapter must preserve the source-to-arena coordinate transform before using
this predicate; facing alone, the toes, or the two fighters' relative X values
cannot replace it.

The bounded private receipt is 1,377 bytes, SHA-256
`b01a4494ce4d5d65cc64d1ea871b89d34aa9c2e0ec8b2565ea81dc9c111a8cb0`.
This closes the native predicate's meaning. Paired runtime contact and
alignment checks remain separate from this read-only native inspection.
