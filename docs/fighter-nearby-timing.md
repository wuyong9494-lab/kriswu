# Nearby combat timing and physical-device acceptance

## Evidence boundary

The nearby room is wired to verified preflight, committed startup, actual
SceneKit/control mounting, host simulation and guest replay. Game Center remains
selection-only. Earlier foundation documents describing all native tests as
unrun or the coordinator as unwired describe earlier implementation stages.

The parent task verified grouped CI run `42715474804`, remote commit `b3dff841`:
235 resource-backed native cases, four resource UI cases, 189 ordinary native
cases (including 12 skips), three ordinary UI cases, the unsigned device build,
strict-concurrency gate and core suite passed. Resource suite elapsed times were
863.995 seconds for native and 903.688 seconds for UI. The installed-original
preflight cancellation case took 14.904 seconds; hosted inline transition took
54.421 seconds; two production-loader SceneKit/control endpoints took 54.691
seconds. These are **whole test durations**, not isolated preflight costs, frame
times, transport latency or physical-device measurements. Those two endpoints
use an in-process fake transport, not two physical devices.

The clock change below is later than that baseline and requires its own final
commit's CI. This Linux workspace has neither Swift nor Xcode. Source review and
arithmetic models cannot establish a Swift/native pass or playable multiplayer.

## Current path and latency model

1. UIKit source controls update the local session's physical-input mailbox.
2. The host samples immediately before each authoritative step. The guest
   samples initially after ready, then on its local pulse only when replay has
   advanced since its previous sample. Replay callbacks never drain the current
   physical-input mailbox. Neither display link advances external-authoritative
   simulation. See [the burst regression](fighter-nearby-input-bursts.md).
3. Both sample messages target `nextTick + 4`. Host-local samples use the same
   inbox validator as guest messages. The host steps once, encodes the consumed
   inputs, publishes locally and sends one reliable frame.
4. The guest validates exact sequence/tick continuity, applies both consumed
   inputs and publishes the resulting state. Its next eligible local pulse
   samples against the latest replay tick, without advancing simulation.
5. `DuelWorldView` draws the latest session state on its separate display link.
   Publication is not proof that a frame has reached the screen.

Let `T` be the actual host interval, `w` the wait from a resolved local intent to
its next sample, `h[n]` the host's tick-n start, and `d[n]` that frame's host-send
to guest-publication delay, ignoring service cost for this simple model.
Assume steady cadence, ordered delivery and an input that reaches the host before
its scheduled consumption. These are analytical examples, not measurements:

- Host sampling at tick n targets tick n+4. Resolved intent to host publication is
  `w + 4T`, nominally 66.7–83.3 ms with `0 <= w < T` at 60 Hz. Guest publication
  of that same action adds that authoritative frame's delivery/publication delay.
- A guest whose latest applied tick is n has `nextTick = n+1`, so its new sample
  targets n+5. Let a be the time from that frame's publication to the local input
  sample. Sample to host consumption is approximately `5T - d[n] - a`. Guest
  intent to its own authoritative publication is
  `w + 5T + d[n+5] - d[n] - a`. The earlier 83.3–100 ms example assumed a=0
  because sampling happened inside every frame callback. It is not a measured
  or guaranteed bound for independent local pulses. Do not add an RTT blindly:
  the fixed lead already budgets return delivery, while downlink delay and local
  sample age reduce the guest's remaining host-relative lead.
- Late arrival changes that model. The inbox accepts at most two ticks late at
  the next consumption tick, rejects farther-late inputs, and forbids two
  accepted samples for the same scheduled tick. Reliable bursts can therefore
  contain stale/conflicting inputs. A drained one-shot edge is not recovered by
  the next sample. Held movement/guard expires after three consumed ticks total
  without refresh. No rollback or prediction is implemented.
- Add the wait for the next display callback before pose drawing, then renderer
  and scanout delay. A healthy nominal 60 Hz callback adds up to about one period
  before drawing; actual device callback/GPU/display costs must be measured.
- These figures begin at a **resolved intent**, not every button-down. Neutral
  weapon/kick taps resolve on release; neutral weapon heavy needs 18 input
  samples; jump has one sample of chord grace. Directional/ranged/shadow actions
  can resolve on press. Source-control hold/chord timing remains sample-count
  based. A queued guest frame burst no longer advances those timers once per
  historical packet, but missed local pulses or lack of new frames can extend
  their wall-clock duration. This is not a monotonic-time hold-recognition rewrite.

There is no current in-app network RTT, touch-to-consume, frame-publication-age,
input-rejection or screen-presentation telemetry. The renderer's existing
display-callback p95 is not any of those measurements.

## Bounded absolute-deadline clock

Previously the production task slept 16,666,667 ns, ran synchronous `service()`,
then slept that full amount again. Even with perfect wakeups its start-to-start
period was `T + serviceCost`. Illustrative constant costs of 1/3/5 ms imply
56.60/50.85/46.15 Hz. A sub-250 ms workload could therefore slow the game without
tripping the stall watchdog. This follows from the loop, not a device benchmark.

`DuelNetworkPulseSchedule` retains the same nominal interval but uses absolute
monotonic uptime deadlines. After service completes, the next sleep uses only the
remaining budget. If one or more deadlines have passed, integer remainder
arithmetic selects the next strictly future deadline on the original grid in
constant time. It never invokes multiple simulation steps to catch up. A late
wake still calls `service()` once; that method's unchanged absolute watchdog
rejects an excessive running gap before simulation advances. Cancellation still
exits the sleeping task, and a closed coordinator cannot schedule another step.
Clock regression, early schedule advancement and arithmetic overflow fail closed.

Eight `DuelNetworkPulseScheduleTests` cover the initial wait, 600-pulse service
cost/drift model, bounded wake jitter, missed deadlines, exact-boundary overrun,
large gaps, atomic invalid clock observations and UInt64 exhaustion. Existing
native coordinator cases cover no catch-up after a clock stall and a queued frame
that arrives before the stalled watchdog task. Deterministic schedule tests do
not replace testing actual task cancellation, CPU scheduling or frame pacing.

This change does not alter the simulation rate, input lead, inbox windows, wire
protocol, gameplay, asset ownership or offline/duty behavior. It cannot promise
60 Hz under overload; missed deadlines deliberately lose time rather than replay
an unbounded backlog.

## Transport review, unchanged by this clock patch

Apple documents reliable MCSession data as ordered, with delegate callbacks on a
private serial queue. `GameRoom` currently hands each state/envelope/direct event
to a separate task with **explicit** `@MainActor` isolation and no suspension in
its body. Generic actor FIFO warnings are insufficient to diagnose this route:
Swift SE-0431, implemented in Swift 6.0 and supported by back-deployment, gives
explicitly MainActor-isolated task closures a stronger start-in-creation-order
guarantee. The current CI toolchain is Swift 6.2+. No transport-ordering defect
was established on that supported toolchain, and no GameRoom rewrite is included.

The coordinator requires the started snapshot before the offer, and guest replay
closes on a frame sequence gap. Add a targeted callback-handoff regression and
physical transport testing before treating those assumptions as device-verified.
Any future FIFO handoff for an older/different execution path would need to cover
all nearby session state, envelope and direct callbacks, retaining session-object
and authenticated-peer checks. Ordering only combat bytes is insufficient;
hello/lobby/start packets establish the receiver and identity. Other games'
transport behavior should not be changed incidentally.

Also, `GameRoom.sendDirect` suppresses MCSession send errors and exposes no send
result. A locally advanced frame whose send fails is not retransmitted; the next
frame can cause a sequence-gap shutdown, or silence reaches a watchdog. Reliable
head-of-line stalls can delay input and frames. Neither an unreliable conversion
nor a blind retry is safe for this strict contiguous replay protocol.

Current token/peer/session checks and source-control ownership were reviewed;
no additional reproducible ownership violation was established by this pass.

Primary references:

- [Apple MCSessionDelegate](https://developer.apple.com/documentation/multipeerconnectivity/mcsessiondelegate)
- [Apple reliable delivery](https://developer.apple.com/documentation/multipeerconnectivity/mcsessionsenddatamode/reliable)
- [Swift explicit task-isolation scheduling, SE-0431](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0431-isolated-any-functions.md)

## Reproducible two-device acceptance, still pending

Use two physical iPhones, the exact same unsigned-build source identity installed
through the user's authorized development route, and the approved original
resource set. Record build/commit, device/OS, display refresh, thermal state,
battery mode, network arrangement and session/start IDs. Do not infer a selected
Wi-Fi/Bluetooth transport from the UI. Test both host devices and both hero-seat
orders. Separate cold entry, warmed entry and steady combat.

1. Add local-only bounded timing probes before claiming numeric latency:
   touch/intent resolution, sample sequence/target tick, transport receive and
   MainActor dispatch, host inbox outcome/consumed tick, host frame send, guest
   accepted frame/publication and actual draw/render boundary. Keep counters for
   rejected late/conflicting input, FIFO/sequence gaps, skipped deadlines and
   send failures. Correlate input edges to consumed ticks, not just similar game
   animations. Diagnostic correlation must not alter simulation or wire authority.
2. Report sample counts and p50/p95/p99/max separately for each direction and seat:
   intent-to-sample, local input-to-authoritative echo, host service interval and
   service cost, guest frame interval/backlog, draw delay, and checkpoint match.
   Device monotonic clocks have different origins: never subtract host and guest
   uptime directly. Use same-device echo timing, an explicitly bounded clock-sync
   method for cross-device spans, or a common high-speed-camera timeline.
3. Capture both screens and the control contact/release together at high frame
   rate. Use isolated directional or ranged edges as well as neutral release,
   heavy-hold and jump-chord cases. Report video frame period/uncertainty and
   align the visible effect to its corresponding command. Button-down-to-heavy
   includes designed hold recognition and is not transport-only latency.
4. Run at least three 120-second active sessions per host/hero configuration on a
   stable local network, recording warm and thermally stressed runs separately.
   Proposed initial acceptance targets, not existing measured passes: no sequence
   gaps, desyncs, duplicate edges, stuck held controls or unexplained closures;
   no monotonic tick drift beyond recorded skipped deadlines; median host interval
   within 1 ms of 16.67 ms; no routine 250 ms stalls. Record latency distributions
   before setting a product latency limit or changing the four-tick input lead.
5. Exercise short network stalls and delayed/burst delivery, disconnect/host
   loss, permission interruption, background/audio interruption, repeated
   exit/re-entry, and fresh session IDs. Verify terminal paths stop simulation,
   release owners and never switch to AI/offline. Deterministic injected duplicate
   and reordered packets complement, but do not count as, real transport tests.
6. Measure preflight separately with explicit start/end and main-thread
   responsiveness probes. `DuelNetworkRoomModel.finishStartup` still calls the
   synchronous MainActor verifier before networking/deadlines. A loading label
   and `Task.yield()` do not keep Cancel, animation or navigation responsive
   while decoding runs. Do not label its CI whole-test duration combat latency.

Acceptance evidence must distinguish modeled, instrumented software, video,
simulator/in-process and physical-device results. No physical two-device pass,
production latency improvement or complete multiplayer acceptance is claimed.
