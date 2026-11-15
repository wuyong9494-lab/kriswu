# WuYong original shared victim motions — 2026-11-15

## Completed source binding

The WuYong D15 candidate contains 62 body clips. The six newly appended victim
clips use the already cached original motion bytes, their original named
configuration records, WuYong's own 58-bone rig and mass table, the two original
Imperial Spear attack edges and all 15 original body hurt capsules.

The source Stun capability supports the existing common stun state machine.
The root-victim capability is also required in the playable Sun–Wu match:
without it, the existing root control would select an ordinary hit pose.
The three existing H17 hypnosis motions remain separate and unchanged.

| Capability | Original configuration | Frames | Last sample tick | Source end tick |
|---|---|---:|---:|---:|
| Stun In | moves_settings 87 | 31 | 60 | 52 |
| Stun Loop | moves_settings 88 | 35 | 68 | 60 |
| Stun Out | moves_settings 89 | 31 | 60 | 52 |
| Root passive Start | settings_sets_heralds 102 | 44 | 86 | 78 |
| Root passive Loop | settings_sets_heralds 103 | 61 | 120 | 112 |
| Root passive End | settings_sets_heralds 104 | 48 | 94 | 86 |

All six original records have no Sounds entries. No sound marker is invented
for them. The existing root and stun consumers retain their own transition
policies; the final animation sample and AnimationEnd remain distinct.

## Preservation and exported-channel readback

`append_erlang_cached_stun.py` starts with the verified 56-clip body.
`append_erlang_cached_root_victim.py` starts with its 59-clip result. Each append
checks the complete previous GLB BIN prefix and every previous animation,
accessor and buffer-view record. Nodes, meshes, textures, materials, skins,
personal portrait geometry and personal neck bridge remain identical.

The readback reconstructs the new exported GLB channels, including interpolated
half-frames, and compares hands, feet, toes, pelvis, head, the original weighted
mass centre and all 34 capsule endpoints with the corresponding profile.

| New group | Samples | Compared points | Maximum error |
|---|---:|---:|---:|
| Stun, three clips | 191 | 8,213 | 2.05e-7 m |
| Root victim, three clips | 303 | 13,029 | 3.42e-7 m |

These are offline exported-channel consistency checks. They do not replace
native SceneKit rendering or live opponent-control acceptance.

## Exact candidate identities

| File | Bytes | SHA-256 |
|---|---:|---|
| WuYong_Erlang_D15.glb | 18,590,120 | `debd14c7af756e52e14b920ce2db37fd77ddcfa26b5668fe552ac79e7a1303bd` |
| SF3_Erlang_Profile.json, body base | 18,784,081 | `d06fa4c2e7040916664a4b32ac0e3181454b7c45e7ea4918f1c8c4767ca5a40d` |
| SF3_Erlang_Profile.json, full model bindings | 18,898,503 | `e9001357a0bda99f2fcc8f833b5e5dbc1c48846551def88aa2057d4d1ee1ad23` |
| SF3_Erlang_Runtime_Rules.json | 49,853 | `09e65d68156639b59a4ee252fb42b56638d59dbcfa8ba30a345d2a396c4444f5` |

The full profile retains the dog, seven independent attack-model tracks and
seven sword birth/idle tracks: 15 tracks in total, with 36 effective source
attack intervals, six static creation bindings and six original sword slots.
The separate dynamic source state machine is required for meditation release
and sword movement; profile generation alone does not certify those features.

The original dog GLB is unchanged at SHA-256
`22a9292b5fa62ae1a64d91cd7e840632119afd62a7c21d8485b5b9de011bc236`.
Rebinding its 53,047-byte manifest to this body produces SHA-256
`ad71feddda95752b819993588c09bf20fa29320384aa2516046a9ac33cfc5fa7`.

## Affected consumer check

The actual full profile and staged Sun opponent passed
`testActualWuVictimCapabilitiesKeepSharedStunRootAndHypnosisSeparate` in 4.242 s.
It validates the actual catalog, both shared victim capability predicates,
source end ticks, head samples, hurt capsules and nine distinct Stun/root/
hypnosis clips. Wu retains its D15 identity and is not identified as Pangu.

The same selected run passed three canonical-state diagnostics. Total:
four checks, zero failures, 4.255 s, after a 34.82 s build. The private log is
`erlang-victim-and-state-checks-20261115.log`.

No private original media was added to the source repository. This record
does not claim native acceptance, completion of Pangu's missing dedicated
equipment/motions, or a TestFlight upload.
