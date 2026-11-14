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

The authenticated overlay contains 295 files, totaling 129,746,107 bytes.
The catalog and release validate with the current Swift implementation.
Against the previous 293-file overlay, 292 files remain byte-identical, the
release binding changes, and only the original Morph manifest and raw texture
are added. Neither character model nor its animation bytes changed.

| Independently pinned item | SHA-256 |
| --- | --- |
| Sun 65-motion GLB | `ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6` |
| Liu 56-motion GLB | `f83d8cbbd7b2158604dad9eff28398bcf57c64fdcb4146e5c142608484a5a472` |
| H17 compressed effects | `ce7350283846c370e00df073d2c04146687301c095a1be4b6f19aece982f2435` |
| Fighter release | `fe8056c7a65c51a83704d975f696316d0848d998143a384d85b8ef5aad8f0db3` |
| Morph binding | `1bf98c9c06ac813333fb943be1440bea21dc5d4e7d5979454835790c02164680` |
| Original Morph mask | `f5572cfbbe87bd2feb2e9aa93843815b0acdf1b71c0dd7ab584df24ce3ede514` |
| Encrypted overlay manifest | `af2dfb819f2d256f71c557495c9bf731c7557138214f14509dd94e541f3d8164` |

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
- D19 wind and upper-wind releases align to the actual enemy pelvis on X/Y.
  All 121 character clips carry independently verified half-frame pelvis
  tracks; missing source data never falls back to a guessed field origin.
  Pivot-aligned fall and ultimate attacks retain their own source alignment.
- Original paired front/back throws and active/passive escape clips. Both
  actors play their own skeleton's motion. Range and wall tests use recovered
  mass-weighted centers of mass, preserving submillimeter precision.
- The eight authenticated H17 stance clips now drive the entrance, later-round
  entrance, round victory, final victory, and their idle transitions. Source
  AnimationEnd ticks (392, 100, 198, and 314) remain separate from the full
  sampling durations. The original birth loops wait for RoundStart; they are
  not shortened or forced to play a complete cycle before that event.
- A separate deterministic presentation clock keeps stance FX/audio moving
  while combat timers, ability state, and spatial lifetimes stay frozen. Intro
  inputs are drained, including tutorial feedback. The final victory reaches
  Win_Idle tick zero before the existing match-over/network shutdown boundary.
- Original X-only stance alignment, source root displacement, facing and
  existing ground lift are retained without adding source root Y twice.
  First-round effects retain their explicit source scope; subsequent-round
  forest ambience cannot start early from the first RoundStart event.
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
- Original H17 final-victory HideModel/Morph: the real frame-36 source marker
  (tick 70) targets the enemy, waits for one committed render boundary, then
  runs the recovered 140-tick linear transition. Cutoff follows
  `(1 + edge) * (1 - progress) - edge`, not node opacity. The original linear
  ETC2 mask, V-origin correction, opaque discard and Gamma-space edge colors
  are authenticated separately. Armor and actor base geometry use the source
  black/teal override; the weapon retains its distinct blue/cyan defaults.
- The four exact Liu materials are bound to that enemy-only effect. The
  accepted personal head/neck follow the original actor-base-model branch
  without a fictional equipment type. Pause and repeated renders cannot
  advance the tween. Completion hides the affected mesh holders; arena reset
  restores the installation-time materials and visibility.
- Liu's appended-motion release explicitly retains the original armor/hammer
  back-face culling and single-mip bilinear/repeat texture state. Its new GLB
  digest no longer relies on the old-export initializer's hash whitelist.

## Verification completed before Apple execution

These are separate focused runs; their counts overlap and must not be added
as a claimed number of distinct tests.

| Scope | Result |
| --- | --- |
| D19 / H17 state, source collision, COM, throws, replay audit and trail batch | 155 passed |
| Input, replay, source-motion sample and throw batch | 55 passed |
| Fractional throw boundaries plus source audio events | 29 passed |
| Particle renderer grouping, age/depth ordering and invalid keys | 5 passed |
| Pelvis, source D19 fight and canonical replay checks | 31 passed initially; the one incorrect cast fixture was corrected and its exact retest passed |
| Independent pelvis FK extraction fixtures | 4 passed; 484 real samples cross-checked |
| CI gate contracts | 28 passed |
| Private release schema, binding isolation and Morph trust boundary | 26 passed; the old unsupported-version fixture was updated for the already supported H17 schema 2 |
| Offline particle sorting extraction fixtures | 5 passed |
| Current real catalog and fighter release | Swift validation passed |
| Actual source audio manifest and 88 WAVs | Foundation loading passed; 89 verified records, 112 markers, eight cues |
| Source stance, source audio-event, replay and replay-audit batch | 37 passed; 15 stance, six audio-event, 14 replay, two audit methods |
| Exact source stance capability identity | The existing capability method passed its exact retest after adding the source runtime configuration SHA gate |
| Real unchanged Sun65 / Liu56 catalog stance lifecycle | Birth, original intro, start-idle and combat entry passed; seven original marker ticks crossed once; no duplicate arena ambience adapter |
| First/subsequent RoundStart cue scopes against the real audio manifest | Six exact cases passed; all 89 file records, 112 markers and eight cues still load |
| Authenticated encrypted overlay | Cross-implementation assembly/decrypt/ZIP/file validation passed |

The first source-only Apple build (run 43587119695) reported one compile
error: SourceFX could not read the private Core round counter. The counter is
now public with a private setter; its canonical encoding is unchanged. That
failed build executed no native test methods.

The second build (run 43588550268) reached the native renderer compilation
and identified a SCNView-only antialiasing property used on SCNRenderer. That
unsupported assignment was removed; the caller-owned multisample color/depth
attachments and resolve path remain subject to the actual native tests. This
failed build also executed no native methods.

The third build (run 43589690716) passed production-source compilation and
found two type-inference errors in the native renderer test fixture. The
SCNView option now uses its explicit string raw value, and the attachment
lifetime uses the explicit XCTest enum. The five renderer methods and their
format, depth, projection, and sample-count assertions are unchanged. This
build executed no native methods either.

The fourth build (run 43591757910) compiled successfully, booted the simulator,
and executed all 97 selected methods: 96 passed, one failed, zero skipped.
The failure was the 20-byte original-mip readback comparison; the old test read
CPU texture storage without submitting GPU work. The revised test checks the
same exact bytes through a completed GPU blit and retains CPU readback as
diagnostic evidence. This change does not establish that the failure is fixed
until the next Apple run actually passes.

The source-only Apple workflow now selects exactly 108 synthetic native methods,
including 11 additional Morph lifecycle and actual GPU contract tests.
It receives no asset keys, uses no private asset environment, and excludes the
five installed-source tests. The protected full-resource workflow selects 113
methods, including those five tests and the original-resource captures. Neither
method inventory is evidence of execution until an actual run completes.

## Acceptance boundaries

- The dedicated D19 costume, long axe and remaining exclusive motions are not
  installed by this H17 overlay. Formal D19 rule tests do not prove that full
  character is playable with original visuals.
- The entrance begins on this arena's first authoritative RoundStart tick;
  combat opens after its source AnimationEnd and initial start-idle sample.
  Round/final victory likewise reaches win-idle before advancing the existing
  arena lifecycle. These are explicit lifecycle adapters: the original
  PLAYER/NOT_PLAYER lock selection, opponent's 20-tick start gate, and global
  phase dispatcher are not inferred from local/network player indices.
- Morph reproduces the recovered normal coroutine/tween path. The original
  special pending-exit-shadow callback dictionary is absent from this arena;
  its 46 render-boundary waits are not invented as 45 logical ticks. The
  accepted personal geometry and persistent-actor reset are explicit arena
  adapters. Native GPU assertions do not establish Unity base-lighting parity.
- Remaining Unity modules, cross-emitter dynamic bounds sorting and some
  common floorfall sound events still need their own recovery or native
  comparison. Normalized arena stats/impulses are explicitly identified in
  the runtime evidence.
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
