# Erlang source pelvis scale and floor offset

## Scope

This change binds the five authenticated D15 `TweenScale` intervals to the
pelvis bone and consumes the source floor-offset actions in the actual battle
queue order. It does not claim original-device visual acceptance or complete
the remaining Erlang effect/material branches.

The settings configuration is SHA-256
`3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701`.
The private TweenScale evidence receipt is 42,218 bytes, SHA-256
`69d53408a4ca49dea5b474cfcec37dcddae996befe385f53e5626d4f920c8257`.
The final floor/order evidence receipt is 57,605 bytes, SHA-256
`25c5a162f7cce8783db3501fa713515e382a2ead5b4a6f3dcfa11736fdb38f41`.
Neither receipt's original bytes or private assets are committed here.

## Authenticated intervals

Bindings require the exact profile role, source motion SHA, bundle, frame count,
playback duration, SelfEnd marker and pelvis samples. One source frame spans
two arena ticks for these five motions.

| Record | Role | Scale start tick | In / out source frames | Floor Start tick | Full last sample / SelfEnd tick |
| --- | --- | ---: | ---: | ---: | ---: |
| 90 | Avatar stance | 0 | 10 / 5 | 2 | 86 / 78 |
| 97 | Level 2 transform start | 18 | 20 / 5 | 48 | 64 / 56 |
| 107 | Transform | 70 | 10 / 5 | 48 | 168 / 160 |
| 108 | Mirrored transform | 70 | 10 / 5 | 48 | 168 / 160 |
| 133 | Transform out | 0 | 0 / 1 | 0 | 0 / 0 |

The first four intervals tween from 1 to the source Float32 value
`0x3f8f5c29` (1.12); the return interval reverses those endpoints. All five have
null End, normalized by the source to `INT_MAX - 1`. SelfEnd emits
`AnimationEnd` but does not close these intervals. Physical close occurs after
the full last sample, or when an actual animation replacement closes them.

Native tween updates write the current elapsed value before incrementing it.
The InOnly terminal check does not add an unwritten final sample. Explicit
replacement's close and cleanup are separate operations and retain a partial
bone value. The distinct native pending-change branch that skips interval End
is represented separately, not assumed equivalent.

## Floor timing and shared geometry

Lock 1432/t25 queues `SetModelFloorOffset(14)` on the normal floor interval
Start. Lock 1454/t63 queues zero on the Out floor interval End. Equal Start/End
indices span one full source frame: ordinary floor events end at start tick + 2.
Those ordinary ends do not clear the persistent offset.

The actual LocationScene updates actor poses, resolves collisions, then
consumes external trigger actions. Thus transform tick 48 samples the old zero
offset, commits 14 at the end of the step, and tick 49 samples 14. The one-frame
Out first pose samples 14 and its SelfEnd zero does not clear it. Replacement
queues the Out End action while sampling the new pose with 14; the queued zero
applies at the end of that step and the following pose samples zero. This is
different from the direct native TweenScale interval callback.

The source offset adds 0.14 metres to pelvis local Y, before the authenticated
outer model scale of 0.92, giving 0.1288 arena metres. Pelvis scale changes its
descendant FK points, not this translation, capsule radii, actor translation or
independent summons. Previous poses retain their own scale and applied offset
for swept contacts. Source head/hand/foot/pelvis/COM anchors use the same values.
Raw source bone transforms and displayed bones apply the adjustment once.
Display idle blending retains raw poses and applies current bone values after
the blend, so the gameplay offset is neither accumulated nor blended away.

All 62 currently authenticated humanoid clips have source evidence excluding
an Align.Y branch, which would skip the native floor addition. The two paired
D19 unthrow clips were checked directly in settings records 248/249, with
supplement receipt SHA-256
`3a8d45c0474acc598c76ce9086036bdecf4bdc8ef5d9137fc7ad62f267d1824b`.
Future clips still require their own axis check.

## Verification and limits

- Final targeted suite: 10 tests, zero failures, 12.056 seconds. It covers the
  original clock/binding rules, partial replacement, queued floor order, real
  staged transform FK/capsules in both facings, stored-property inventory and
  canonical byte/header checks.
- The preceding integration suite passed 11 tests in 22.612 seconds, including
  three actual static summon/release checks after the shared FK changes.
- The modified SceneKit source passes Swift syntax parsing. Apple framework
  type checking of this exact change remains a separate CI gate.
- Replay schema/rules are 12/17. Each pose stores scale and applied source
  offset; the persistent actor state also stores the queued optional setter.
  Synthetic diagnostic sizes are 66,737 bytes for the equipped fight and
  67,219 for the equipped game; bare game/catalog remain 382/65,562.

No private resource upload, signing, TestFlight upload or original-client
execution was performed by this change.
