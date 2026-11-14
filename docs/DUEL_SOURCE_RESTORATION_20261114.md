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

The authenticated overlay contains 295 files, totaling 129,750,242 bytes.
The catalog and release validate with the current Swift implementation.
Against the previous 295-file Morph overlay, 293 files remain byte-identical.
Only the Morph v2 document and its release binding change, adding the recovered
Palace receiver geometry and independent projector parameters. Neither
character model nor its animation, audio, mask or effects bytes changed.

| Independently pinned item | SHA-256 |
| --- | --- |
| Sun 65-motion GLB | `ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6` |
| Liu 56-motion GLB | `f83d8cbbd7b2158604dad9eff28398bcf57c64fdcb4146e5c142608484a5a472` |
| H17 compressed effects | `ce7350283846c370e00df073d2c04146687301c095a1be4b6f19aece982f2435` |
| Fighter release | `7bf9aa17a1e15273dbe7ae04eecd1ef092c2ad9a72360b99cd4f7ac08695704b` |
| Morph v2 and projected-shadow binding | `364003f89aed01b0db41c68726c71ecd92c714ed6ee443984ba430d3b52c16ff` |
| Original Morph mask | `f5572cfbbe87bd2feb2e9aa93843815b0acdf1b71c0dd7ab584df24ce3ede514` |
| Encrypted overlay manifest | `697d62e8d9bf81da4521b6b828e4b1c4d2aa00e7141eab4d1558b3aa2ee032ff` |

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
- D19 level-two/three Splitter retains its 52-tick air hold without creating
  the landing damage that source SHADOW_UP/t4 reserves for level four. Levels
  four through six retain their five wind markers and 78-tick landing damage.
  The separate ordinary-wind counter and ten-tick timer survive normal
  knockdown, Pangu control, Triad control and the existing throw reaction.
  Force, explicit full cancellation, reset and round boundaries still clear
  them; legacy rules retain their previous cancellation behavior.
- Six D19 skill recoveries now accept the source counterthrow on their own
  current-animation Throwable interval: Splitter 114, Sunder 98, Shard 82,
  Typhoon 68, Missile 82 and normal Heavenfall 308, in 60 Hz core ticks.
  The enemy attempt replaces only that matching body cast with the original
  paired escape response. It preserves independent winds, released models,
  resources and cooldowns, and retains the response's original tick-98 hit.
  A new cast cannot inherit a previous interval. D19 remains immune to an
  ordinary successful throw; range, grounded state and initiator gates remain
  part of the source attempt.
- D19_Unthrow's own recovery now accepts its source frame-68/tick-134
  counterthrow interval after the previous passive participant is released.
  The still-owned active participant must match its authenticated current
  source motion. Replacing that last participant starts the new pair at tick
  zero without an invented idle frame, forced resource cancellation, double
  advancement, duplicate hit, or an old end marker clearing the new pair.
- D19 wind and upper-wind releases align to the actual enemy pelvis on X/Y.
  All 121 character clips carry independently verified half-frame pelvis
  tracks; missing source data never falls back to a guessed field origin.
  Pivot-aligned fall and ultimate attacks retain their own source alignment.
- Original paired front/back throws and active/passive escape clips. Both
  actors play their own skeleton's motion. Range and wall tests use recovered
  mass-weighted centers of mass, preserving submillimeter precision.
- Each imported skinner retains an independent copy of the exact weight and
  joint-index sources passed to its constructor. That record is local to its
  mesh holder and accepts only the same geometry, skinner and bone order.
  Projected shadows, optical framing and personal head/neck bind corrections
  use those authenticated inputs, because the tested SceneKit runtime returns
  empty weight/index getter objects even for a valid constructor input.
  A missing or mismatched record fails validation; an empty getter is never
  interpreted as an implicit rigid skin or replaced with invented weights.
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
  The normal coroutine enables MORPH only after the render boundary; the
  waiting frame retains the original shader even at mask=1, where enabling
  early would already add the weapon's blue edge-start color.
- The source's independent projected shadow uses the recovered Palace
  receiver mesh, material color, ancestry and camera settings. Both actors
  draw ordered whole silhouettes into one 256-by-256 non-depth map; a single
  five-tap bilinear/clamp filter precedes the original DstColor/Zero receiver
  blend. Body MorphMask holes never cut this map. The affected actor's entire
  silhouette fades by the source progress while the other actor retains its
  own value. The camera follows the full mass-weighted XYZ midpoint, uses
  screen aspect and the source's previous-forward positioning order, and
  resets that history with the arena. Receiver projection preserves the
  source half-precision rows, raw RGBA color and no-W-division rule.
  Final presentation writes opaque alpha only after source rendering; the
  original intermediate RGBA math and final RGB bytes are retained.
- H17's current soul/root/wave model creations do not register additional
  projected casters. All 44 recovered CreateModel records leave ModelInfo
  `IsShadowCaster` unset; getter 29388, constructor 32191 and registrar 34903
  establish that this becomes false and skips projector registration. The
  source soul geometry therefore also disables SceneKit's default shadow.
  This decision follows the runtime registration chain, not only the prefab
  layer or cast-shadow flags. The generic additional-model projector path
  remains tested separately.
- The eight source soul models use the recovered render queue 4852. Their
  actual primitive holders now draw after the receiver at 2501 and H17
  effects at 3000/3003, using the shared unorm Gamma surface and preserved
  scene depth. Only that authenticated layer is separated from the first
  SceneKit pass. The four transparent Palace materials remain before the
  receiver, matching their source queues 2110/2460/2470/2500. The final pass
  restores camera/background state and resolves multisampling after the soul
  blend. It issues no second time update or committed-frame callback.
- The authenticated Liu neck bridge has 120 vertices and no UV0, with a
  constant base color and no texture references. Only this exact named actor
  base material may use constant source UV `(0,0)` in its Morph shader. The
  imported geometry, skin and model bytes remain untouched. The other five
  primitives retain their real UV0; equipment, textured geometry, and mixed
  UV/no-UV use of one material cannot acquire the adapter. This is an explicit
  personal-geometry adapter, not a claim of recovered neck UV data.
  That constant coordinate is sampled once from the prepared original mask
  on Metal with normalized repeat/bilinear/no-mip state. Its validated scalar
  reaches both Morph shader stages without a SceneKit texture sampler, so no
  texcoord0 attribute is required. The sample is cached per prepared texture;
  textured source materials retain their original UV sampling path.
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
| D19 formal level gates and queued-wind reaction/lifecycle boundaries | Nine focused methods passed, including actual Fight knockdown, Triad control, original release tick, contact and clean next-round state |
| D19 six current-animation counterthrow windows and source throw regression | 37 passed: 14 formal mechanism, 14 source throw and nine source throw fight methods; includes the earlier seven formal mechanism methods |
| D19 counterthrow recovery takeover plus the previous source throw regression | 45 methods covered: 44 passed in the first run; the remaining fixture used the wrong jump input, was corrected to the actual jump edge and passed its exact retest. Eight new takeover methods are included; production logic did not change between those runs |
| Projected-shadow release builder and authenticated source-field guards | 11 Python fixture methods passed |
| Real GLB shadow input layout | Static checks passed for 48 primitives and 117,681 vertices across both actors and eight soul models; this is not GPU execution |
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
diagnostic evidence.

The fifth build (run 43594347500, published source 03c91c5b) compiled and
executed all 108 selected methods: 107 passed, one failed, zero skipped. The
strict 20-byte GPU mip comparison passed; CPU getBytes returned the base
level's first texel for the level-one read while the completed GPU blit
returned all original bytes. The sole failed method incorrectly expected the
body's MorphMask holes to remove the projected shadow. Recovering the actual
source projector established a different rule: the complete silhouette fades
uniformly while the body's independent noise mask cuts away its fragments.
That finding requires both a new projected-shadow implementation and a
source-correct GPU contract; it is not permission to ignore the failure.

The sixth build (run 43601012291, published source 8de8485e) failed while
compiling the new five-tap test's CPU reference. Its nested pure rounding
function crossed Swift's inferred MainActor isolation boundary. No native
method or GPU comparison executed. The fix inlines the same Float16 rounding
operations, preserving the independent reference algorithm and pixel limits;
a strict Swift 6/default-MainActor minimal reproduction fails before this
change and type-checks afterward. The complete Apple build remains the gate.

The seventh build (run 43602731827, published source 82c20482) compiled and
executed exactly 117 methods once: 108 passed, nine failed, zero skipped.
All nine failures occurred in the projected-shadow caster's skin initializer,
before those methods reached their GPU assertions. The previous strict
20-byte GPU mip comparison passed. The run's eight pinned source-tree entries,
18 selected file digests, exact method inventory and single format-data
attachment were independently verified; there were no image attachments.
The failure log did not expose the actual SCNSkinner getter layout, so it
cannot establish which representation check rejected the skin. The next
revision logs upload/getter layout metadata and reads supported packed
integer widths and one-to-four influences using the returned offsets and
strides, while retaining finite-value, bone-index and byte-bound checks.
The optical framing reader uses the same supported influence/index layouts.
The selected native contract now checks its actual bone movement and model
identity alongside the projector, as well as padded source buffers for all
12 supported influence-count/index-width combinations and rejected invalid
values. Those added assertions remain inside the existing method inventory.

The same run exposed a separate false-positive Morph assertion: the no-UV
Liu neck fixture failed to create a SceneKit pipeline because texcoord0 was
missing, but its background-only discard assertion still passed. The repaired
contract must also prove the neck is visible while the effect is active and
after reset. A successful discard alone is insufficient evidence. These
diagnostics do not turn the run's recorded 108/9 result into a passing run.

The eighth build (run 43605066520, published source eab00708) compiled and
executed all 117 selected methods once: 108 passed, nine failed, zero skipped.
Its 18 upload/getter diagnostic pairs establish the actual representation:
the synthetic float4 weights and UInt16x4 indices were uploaded with complete
data, but both getters returned empty semantics and zero components, counts,
strides and data lengths. Position data remained valid. Seven projector
methods and one Morph projection method failed with skinLayout; the added
optical-framing check rejected the same empty data as unsupportedGeometry.
This was not a test-process crash or a GPU pixel mismatch. The repaired no-UV
neck's visible, edge-color, discard, reset and second-mask assertions passed,
with no missing-texcoord or no-pipeline diagnostics. The strict 20-byte GPU
mip comparison also passed.

Run eight's authenticated artifact preserved all 34 inventory entries and
matched the eight source-tree pins and 18 source-file digests. Its format JSON
was present and correct, but XCTest also emitted eight automatic failure-text
attachments, so the strict attachment inventory correctly remained failed.
There were no images. The subsequent repair retains the real constructor
inputs and uses them through the original loader, bind-correction, trail and
synthetic-fixture paths. Its next Apple execution remains required before the
projector and late-soul comparisons can be reported as passed.

The source-only Apple workflow now selects exactly 117 synthetic native methods,
including 11 Morph and nine independent projected-shadow GPU/contract methods.
It receives no asset keys, uses no private asset environment, and excludes the
five installed-source tests. The protected full-resource workflow selects 122
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
- Static inspection of all six original Liu primitives found and isolated the
  missing-UV personal neck before the full private-resource run. Its targeted
  shader adapter must still be exercised by the installed-character test; the
  source-only synthetic tests cannot replace that resource-level acceptance.
- Render-order recovery is scoped to the installed Palace/H17 layers. Source
  Palace flames and wind are present in the original bundle but absent from
  the current GLB; their existence is not evidence of installed scenery.
  The new late-soul pass still requires actual Apple GPU validation of Gamma
  blending, preserved depth, background load behavior and 1x/4x resolves.
  These contracts do not establish whole-client pixel parity.
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
