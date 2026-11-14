# H17 / D19 source restoration — 2026-11-14

This revision connects recovered H17 resources to the native application and
continues the independently validated D19 combat implementation. It does not
declare original-game audiovisual parity or a new TestFlight release.

## Character identities and resource release

| Character | Resource identity | Motions | Runtime identity |
| --- | --- | ---: | --- |
| 孙登 | Dead Forest Triad, original Ninjato dual blades | 65 | `sun_triad` |
| 刘泉纬 reference | Original Legion dual hammers, with six appended original throw motions | 56 | `liu_hammers` |
| 盘古 | Primordial Heavenly King / D19, dedicated two-handed axe | Dedicated character release not installed | `isPangu` plus an authenticated D19 runtime profile is required |

The Liu reference model is not renamed or granted D19 equipment powers. Its
original geometry, skins, materials, textures and 50 animation channels are
checked unchanged before six original source throw channels are appended.

The authenticated overlay contains 293 files, totaling 129,460,943 bytes.
The catalog and release validate with the current Swift implementation.

| Independently pinned item | SHA-256 |
| --- | --- |
| Sun 65-motion GLB | `ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6` |
| Liu 56-motion GLB | `f83d8cbbd7b2158604dad9eff28398bcf57c64fdcb4146e5c142608484a5a472` |
| H17 compressed effects | `ce7350283846c370e00df073d2c04146687301c095a1be4b6f19aece982f2435` |
| Fighter release | `a56b4e38498d9c6c176b339c37e8339e942951165b76644d36e7c284597ea454` |
| Encrypted overlay manifest | `884a7cebef4c6ca28101ee1491b8da5d31714e283b5fe8a6ce4204b11e8d70c4` |

The overlay is AES-256-GCM authenticated, split into 68 bounded binary shards.
The staging helper independently validated shard assembly, authenticated
decryption, ZIP entry restrictions, and every resource byte count and digest.
The decryption key is not stored in this repository.

## Implemented behavior

- H17 formal ability/state rules, source attack capsules, soul motions,
  forest/root/wave lifetimes, source input anchors, and deterministic replay
  serialization.
- D19 formal runtime rules including heavenfall, Light, shield, cooldown,
  impact and source counterthrow behavior. Equipment identity remains strict.
- Original paired front/back throws and active/passive escape clips. Both
  actors play their own skeleton's motion. Range and wall tests use recovered
  mass-weighted centers of mass, preserving submillimeter precision.
- Source effect birth/stop events, independent magic-model skeletons, source
  bone attachments, raw 60 Hz StopFrames, and shader `_Transparent` fades.
- 36 recovered effect prefabs, 9,693 particle tracks, 552,099 samples, four
  world-space history trails, and original programs/material/texture bindings.
- Original emitter sort modes, queue values, and prewarm particle ages.
  Source visibility masks are not used as sorting layers.
- 88 original WAV files, 112 motion markers and eight event cues. Liu shared
  throw markers have their own character and source-clip digest checks.
- Public SceneKit/Metal rendering integration with explicit render targets,
  sample counts, depth handling, pause/shutdown and capture contracts.

## Verification completed before Apple execution

These are separate focused runs; their counts overlap and must not be added
as a claimed number of distinct tests.

| Scope | Result |
| --- | --- |
| D19 / H17 state, source collision, COM, throws, replay audit and trail batch | 155 passed |
| Input, replay, source-motion sample and throw batch | 55 passed |
| Fractional throw boundaries plus source audio events | 29 passed |
| Particle renderer grouping, age/depth ordering and invalid keys | 5 passed |
| CI gate contracts | 28 passed |
| Offline particle sorting extraction fixtures | 5 passed |
| Current real catalog and fighter release | Swift validation passed |
| Actual source audio manifest and 88 WAVs | Foundation loading passed; 89 verified records, 112 markers, eight cues |
| Authenticated encrypted overlay | Cross-implementation assembly/decrypt/ZIP/file validation passed |

The source-only Apple workflow selects exactly 97 synthetic native methods.
It receives no asset keys, uses no private asset environment, and excludes the
five installed-source tests. The protected full-resource workflow selects 102
methods, including those five tests and the original-resource captures. Neither
method inventory is evidence of execution until an actual run completes.

## Acceptance boundaries

- The dedicated D19 costume, long axe and remaining exclusive motions are not
  installed by this H17 overlay. Formal D19 rule tests do not prove that full
  character is playable with original visuals.
- Remaining Unity modules, cross-emitter dynamic bounds sorting, original
  intro/win playback and some common floorfall sound events still need their
  own recovery or native comparison. Normalized arena stats/impulses are
  explicitly identified in the runtime evidence.
- The single-prefab particle budget audit reached 90 simultaneously live
  particles; a conservative independent-phase bound was 144. This does not
  prove every combination of concurrently live bursts fits the shared budget.
- Automatic approval review blocked storing `FIGHTER_H17_D19_KEY` in this
  repository's `fighter-private-assets` environment pending explicit
  authorization for that key destination. No alternate transfer was attempted.
- Original-resource simulator captures, physical-device acceptance and any
  TestFlight promotion require their own completed evidence.

See `.github/workflows/fighter-h17-source-native.yml` for the source-only gate
and `.github/workflows/fighter-pangu-native.yml` for the protected resource gate.
