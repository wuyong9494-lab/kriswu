# D15 StopEffect: independent source frame-job contract

## Result and release boundary

This change closes a small source-analysis gap: the original positive-frame
`StopEffect` path, its exact Float32 `_Transparent` callback, and its final
liveness-checked `GameObject.SetActive(false)` call now have an independently
testable contract. **It does not activate a new effect in App or close HIDE
parent lifetime.** The current 67/79 emitter scope, actor/profile identities,
resource pins, and reviewed material programs remain unchanged.

The new implementation is `scripts/erlang_effect_stop_source_state.py`. It
accepts an explicit observation of the original integer frame counter and
current renderer/object liveness. It returns the source calls in order. It
does not supply a clock, select a pool instance, run a scheduler, generate a
particle, or turn an absent model into a substitute effect.

The separate Avatar contract uses another native job type and another clock
field. Reusing its timeline, or mapping this stop duration directly onto
`erlangLiveTick`, would erase an observed source difference.

## Authenticated evidence

The bounded read used the same original IL2CPP pair as the existing recovery:

| Input | Bytes | SHA-256 |
| --- | ---: | --- |
| UnityFramework | 182,750,944 | `7c192647b0e035bd246c135a59c597ee3910d50fc4ed128abe402da39a62a55b` |
| global-metadata.dat, version 39 | 27,877,556 | `12d52d278c904b210541e7c337025c68454e2b89a83eddab51f9c74fcc5a245c` |
| Existing recovered sword source receipt | 113,605 | `245d64669edd31d5e7e5707ad60a4081d2e91424b235c6ddc67ed2a5a2e3af86` |

`scripts/erlang_effect_stop_source_evidence_20261117.json` records the complete
SHA-256, virtual start/end, file offset, byte count, code digest, metadata
definition digest, and registered method-pointer cell for each selected
method. It includes 15 method bodies totaling 3,260 code bytes and a separate
104-byte generic null/empty collection query. The private disassembly stays
outside the repository. No original binary was executed.

| Method index | Virtual start | Bytes | Relevant observation |
| --- | --- | ---: | --- |
| 34214 | `0x7054390` | 448 | Name/model filtering forwards stop frames to each selected effect. |
| 34436 | `0x705418c` | 516 | Immediate-stop or frame-job branch. |
| 35910 | `0x70c2a28` | 156 | Constructs the integer-frame job and enqueues it. |
| 35942 | `0x70c2ac4` | 44 | Stores integer duration. |
| 35943 | `0x70c3f00` | 112 | Frame-job update, progress write, signed completion test. |
| 35944 | `0x70c3f70` | 40 | Captures the integer start/end frames. |
| 34452 | `0x706085c` | 12 | Exactly `Float32(1 - progress)`, then calls the material setter. |
| 34435 | `0x705a9f8` | 688 | Main material and exact ParticleSystemRenderer trail-material writes. |
| 34453 | `0x7060868` | 180 | Checks GameObject liveness, then sets it inactive. |
| 35977 | `0x70c4518` | 116 | Distinguishes integer-frame virtual update from float-clock advance. |
| 35978 | `0x70c4698` | 100 | Base virtual implementation increments integer frame by one. |
| 34341 | `0x705cd54` | 196 | Stores injected dependencies; does not choose the provider. |
| 34905 | `0x708b3ac` | 164 | Direct provider implementation forwards to a generic helper. |
| 34300 | `0x705aca8` | 212 | Selected derived cleanup, not a complete parent-lifetime proof. |
| 34437 | `0x705ad7c` | 276 | Selected base cleanup; does not establish the model/parent ordering. |

The call targets were also resolved through the original UnityEngine module
registration cells: `Renderer.get_material`, `Material.SetFloat`,
`GameObject.SetActive`, `Object.op_Implicit`, `Object.op_Inequality`, and
`ParticleSystemRenderer.get_trailMaterial`. These six entries are registration
bindings, not six additional engine-function body reads.

The native material-name usage cell at `0xa588358` points to metadata literal
21999. Its exact bytes are `_Transparent`. The additional material path
compares the renderer's exact runtime class pointer to
`UnityEngine.ParticleSystemRenderer`, type-definition index 24245.

## Source actions remain distinct

The already authenticated recovered receipt contains these original lock1449
actions, with the source argument types and nulls retained:

| Trigger | Event | Four named-effect stop durations | Separate model deletion |
| --- | --- | --- | --- |
| 11 | `D15_HIDE_SWORDS` | 10 integer frames each | No `a50` in this trigger. |
| 12 | `RoundFightEnd` or `D15_Sword_Destroy` | 5 integer frames each | A later `a50` action is present. |

The four names are `D15_fx_sword_model`, its `_retext` variant,
`D15_fx_sword_jian_glow(weapon_r)`, and its `_retext` variant. Reading these
commands does not authorize those variants in App or establish that their
parent survives all five frames.

The evidence JSON separately preserves original-lock identity and derived
field-view identity. For example, lock1449 is 10,982 original bytes with
SHA-256 `53c460feb2adb787c80efe8a26de64d1fc86eb4868f099a46de67f146e238b9a`;
its 116,621-byte recovered field view has SHA-256
`74cc9d2373bf32b443b32d7011b6b34fbd0ef352a0eb431593ef84ced9ca25b7`.
The new loader authenticates the existing receipt. It does not claim to have
restored or independently decoded all original locks again.

## Exact stop behavior

For `frames < 1`, or a null/empty renderer list, native method34436 checks
the effect GameObject's Unity liveness and immediately calls
`SetActive(false)` when it is live. It never divides by zero or calls the
uniform progress callback on this branch. A nonempty list containing only
destroyed renderer objects still schedules a job; null/empty is a collection
test, not a count of currently live renderer objects.

Positive durations use `ILKPKONFNAM` (35942–35944). They do not use the
`BKMBLKKFCIF` job employed by the Avatar logical-clock path. With explicit
source observations, the arithmetic is:

```
start = observed Int32 frame
end = Int32 wrapping(start + duration)
remaining = Float32(Int32 wrapping(end - observedFrame))
span = Float32(Int32 wrapping(end - start))
progress = Float32(1 - Float32(remaining / span))
transparent = Float32(1 - progress)
completed = signed Int32(end) <= signed Int32(observedFrame)
```

The callback executes before the completion test. Every Float32 operation is
separate; the two subtractions cannot be algebraically replaced with the
remaining/duration ratio. For a ten-frame job observed nine frames after
start, the final value is Float32 bits `0x3dccccd0`, not the rounded `0.1`
value `0x3dcccccd`. Integer-to-Float32 conversion also rounds before division.

There is no clamp in this selected frame-job or progress callback. An explicit
late observation can produce a negative `_Transparent` value before the
completion call. Signed Int32 addition/subtraction and signed comparison are
preserved at wrap. The helper does not repair these source edge behaviors.

NaN, infinity, Boolean values, Float-valued clocks, and integers outside Int32
are rejected as *frame observations*: none is an original Int32 field value.
A positive Int32 duration and Int32 frame input cannot produce NaN in this
formula. If the Float32 callback itself is observed with NaN or infinity, its
single subtraction propagates the corresponding nonfinite classification.
The helper does not model NaN payloads, signaling behavior, or FPSCR settings.

The material loop skips destroyed Unity renderer objects. For every live
renderer it requests that renderer's material and calls
`SetFloat("_Transparent", value)`. An exact ParticleSystemRenderer additionally
writes its live trail material. The source does not deduplicate material
identities, fade vertex RGBA, or test shader-property availability here.
Returned commands therefore mean attempted native API calls, not proof that a
particular GPU program used the value. A null primary material getter and a
null renderer collection at callback time remain explicit failure branches.
Exceptional partial-write recovery is outside the helper's normal result.

## Why App HIDE and parent lifetime remain open

The frame job reads `clock + 0x28`, whereas the Avatar job reads a floating
logical-clock field. Clock entry35977 invokes a virtual update when flag
`+0x55` permits it; the base implementation35978 increments the integer field
by one. The floating-clock advance additionally tests flag `+0x54`. The frame
job update has no equivalent two-flag pause check. The actual injected clock
subtype, source action/scheduler ordering, and first callback phase are not
established. Neither a current render call nor `erlangLiveTick` supplies that
missing observation.

Provider follow-up also has a precise boundary. `SetDependencies`34341 merely
stores its fifth argument at EffectsManager `+0x80`. Metadata identifies one
direct implementer of provider interface `MLGMIPEFMLK`, and its selected method
forwards a GameObject through generic helper `0x4020acc`. This is not proof
that dependency injection actually chooses that implementation. The selected
cleanup methods do not establish root/bone/parent lifetime after HIDE or
model deletion. Calls into further generic helpers are not assumed harmless.

Remaining work before an honest App connection is possible:

- Observe the selected native frame counter and exact scheduler phase for
  HIDE/SHOW and model deletion, including each pause state.
- Close actual provider construction, effect-root attachment, and the parent
  lifetime/transform path after the separate model-delete action.
- Establish SHOW while an older stop is pending: pool reuse, simultaneous
  instances, queue/cancellation ordering, and effect material reset.
- Establish particle emission and history-trail evolution during the pending
  stop. This helper only models material calls and eventual deactivation.

Signed Stretch, actual Noise algorithm/seed/module order, remaining emitters,
whole-prefab parity, simulator rendering, and phone performance are separate
open acceptance items. No source count or runtime status is advanced by this
contract.

## Verification

Run `python -m unittest -v test_erlang_effect_stop_source_state` from `scripts`,
with `ERLANG_EFFECT_STOP_NATIVE_DIR` pointing to the exact original binary and
metadata directory and `ERLANG_EFFECT_STOP_SWORD_RECEIPT` pointing to the exact
existing recovered receipt. With both actual inputs supplied, **19/19 tests
passed, zero skipped** on 2026-11-17. These comprise 15 numeric/behavior boundary
tests, two original binary/metadata/property readback checks, and two recovered
receipt/identity-rejection checks. Without the relevant inputs the four
original-input tests are explicitly skipped.

The checks cover delayed first observation, repeat observations, Float32
cancellation and conversion, zero/negative durations, overshoot, signed wrap,
exact trail-renderer selection, duplicate material writes, liveness/null
branches, input type boundaries, and receipt tampering. They do not execute
UnityFramework, build App, run Metal, or establish device acceptance. No
workflow, environment review, resource upload, or TestFlight action was run.
