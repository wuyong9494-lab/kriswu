# D15 Earth and meditation source effects — 2026-11-15

## Implemented scope

The independent D15 skill renderer now binds **15 of 19 Earth emitters** and
**8 of 9 meditation-explosion emitters**. The previously accepted 15 of 19 Eye
emitters, their binding, material records and resource bytes are reused without
resampling. This is an offline source conversion and App implementation record;
it is not an Apple GPU rendering or full original-engine parity result.

| Effect | Original event and attachment | Observed lifetime |
| --- | --- | --- |
| `D15_fx_floorAttack_(pelvis)` | Lock 1432, trigger 66, the same named interval as model-creation trigger 68; body record 102, interval start 40, MidFrames 0 → live tick 39. Capture the actual actor pelvis once, local=false, Follow000. | 46 particle tracks, 77 live ticks |
| `D15_fx_avatar_start_explos(chest)` | Lock 1438, trigger 1, actual model Initialize; record 106. Capture the model Parent's actor chest once, with the original +3 cm Y shift, local=false, Follow000. | 21 particle tracks, 41 live ticks |

The Earth collision model's independent +20 m X release is not a visual
attachment. Meditation does not infer an Initialize event from a cast phase or
an elapsed body animation. Both visual roots remain fixed after the event;
subsequent actor movement and collision-model deletion do not move surviving
particles. Pause and hit stop retain the existing authoritative live clock.

The new paths distinguish original mesh View/Local/Velocity alignment,
horizontal billboards and individual camera-facing smoke. Smoke's source
Distance sorting uses actual squared camera range; for an orthographic camera
it uses Depth, as specified by the original API. Packet rebasing preserves the
distance key. Existing H17 manifests still reject the new distance mode and
the new One/Zero opaque blend state.

One original stone emitter needs its local ForceModule. The additional
integration is an explicit opt-in; the established default sampler is
unchanged. The original stone shader keeps all four named texture samplers,
One/Zero blending, depth writes, its default Geometry queue and the fragment
discard operation. GLSL `discard` maps to Metal `discard_fragment()` without
changing the original shader arithmetic. Integration at the bounded 60 Hz
adapter clock does not establish identical Unity particle integration or
random-number output.

API references used for these interface mappings:

- [ParticleSystemRenderer alignment](https://docs.unity3d.com/ScriptReference/ParticleSystemRenderer-alignment.html)
- [ParticleSystemSortMode.Distance](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/ParticleSystemSortMode.Distance.html)
- [ShaderLab Queue and the default Geometry queue](https://docs.unity3d.com/2023.2/Documentation/Manual/built-in-rendering-order.html)

## Source and derived identity

| Item | Bytes | SHA-256 |
| --- | ---: | --- |
| Original D15 effect bundle `4f9476ea1326d7c102950a772ee44020.bin` | 2,561,715 | `971b3a1ea36eaaebaea4ae73a56ed65d8ffc4383625a06d64a209d8a70fbbd90` |
| Accepted Eye-only manifest | 161,517 | `fc5c49da06415bdefdb294ad78bfbf406b9dab79fcb527ecbd4f9dc926165619` |
| Combined `SF3_D15_SkillEffects.json.gz` | 356,658 | `54b08e109feb86662470c91c34c19803dfdff28c9ed61d643609c3f1ec810908` |
| Private impact receipt | 114,951 | `5949deef1bd63e9340d03231353fbfe4f6ec61647ecce5c1bf696e99419d6b4c` |

The candidate is bound to the 62-clip actor GLB
`debd14c7af756e52e14b920ce2db37fd77ddcfa26b5668fe552ac79e7a1303bd`.
The model tracks and relevant release records are also compared exactly
against the supplied final profile. The combined manifest expands to
2,811,846 bytes and references 26 materials and 100 resources totaling
17,009,729 bytes. It contains 314 particle tracks, 6,417 sampled frames and
7,167 serialized geometry vertices, within existing loader limits.

Nine authenticated object receipts supply the recovered original textures and
mesh arrays. The exporter reads these local originals only. The previously
missing ShockWave_02, grungy_009 and VFX_DustSeq_2 textures were recovered from
exact original byte ranges; no replacement images were generated. The
ShockWave_02 material remains outside the runtime material set because its
emitter has the unresolved null-mesh shape below. Twenty additional source
material variants were prepared; nineteen are used by this candidate.

## Actual checks

Python 3 with the existing UnityPy 1.25.4 environment checked the new source
objects. Swift 6.0.3 ran the two small executable checks.

| Check | Actual result |
| --- | --- |
| Accepted Eye payload/resources remain byte-for-byte unchanged | PASS |
| Original new emitter identities, mode/force scope, resources and bounds | PASS |
| Original event/Parent bindings and changed release/Parent rejection | PASS |
| Source force affects the actual stone trajectory; unchanged default; isolated constant-force analytic oracle | PASS |
| Twenty prepared source shader variants, fragment discard and the runtime opaque stone's four samplers | PASS |
| Actual original mesh vertices and reflected winding | PASS after correcting the test input list |
| Four individual Facing, pole, horizontal and invalid-vector checks | PASS |
| Three camera Distance/Depth, stable grouping and invalid-distance checks | PASS |
| Six affected App Swift files, syntax parse | PASS; not Apple framework typechecking |

The first six-method Python run had five passes and one harness `KeyError`:
the command omitted the already existing `geo1` mesh-array receipt. The test
was made compatible with that receipt's established schema, the input was
supplied, and only the mesh method was rerun: PASS in 2.307 seconds. No accepted
Eye tests, old clock suite, native test suite or complete gameplay suite was
rerun. Earlier export attempts stopped on actual missing inputs or unsupported
source contracts; they are not test-red or successful-render evidence.

Reproduction entry points:

```text
python3 scripts/prepare_erlang_impact_effects.py --help
python3 scripts/test_erlang_impact_effects.py --help
swiftc App/Services/DuelErlangParticleFacing.swift scripts/check_erlang_particle_facing.swift -o facing-checks
swiftc Sources/ShiftCore/DuelSourceParticleOrder.swift scripts/check_erlang_particle_distance.swift -o distance-checks
```

The mesh check requires the existing `mesh-arrays-private.json` plus both new
Earth/meditation and ground-crush mesh receipts. Private candidate, command and
result paths are retained in the integration handoff. Raw source media and
derived private resources are not committed here.

## Explicit remaining boundaries

| Effect | Original particle-system ID | Unbound behavior |
| --- | --- | --- |
| Earth | `226975819404105122`, `8193636258807174562` | Stretched billboard direction/length behavior |
| Earth | `-8834466512921012830` | ShapeModule type 6, enabled, with a null original Mesh pointer; no point-emitter substitute |
| Earth | `2415301125327312290` | Original Shape.alignToDirection at particle birth |
| Meditation | `2022811022957143107` | Stretched billboard direction/length behavior |

The separate Eye manifest boundary remains: four stretched emitters and its
ground/mirrored prefabs are not bound in this batch. The body's original pelvis
TweenScale records 90/97/107/108/133 remain a separate implementation: the
source modifies a real bone and collision transforms, so a renderer-only body
scale would not close that gap. Other D15 effects and sword Noise/fade behavior
remain independently tracked; these two prefabs do not imply that all Erlang
visual behavior is complete. Production Pangu gates, actor geometry, combat
damage rules, replay versions and release workflows are unchanged by this
batch.
