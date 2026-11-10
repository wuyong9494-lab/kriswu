# Fresh guest input during an ordered frame backlog

## Scope and evidence

This investigation starts from remote commit `b85dea7f1a1b1e58779573021bd95c4c8979911a`
on `codex/fighter-lab-host-simulation-20261109`. The coordinator, host inbox,
presentation input, weapon-input resolver and existing coordinator test fixture
were byte-compared against that branch before editing. Their baseline
local sources matched. The complete baseline Git tree also matches:
`39369a5440da3cf007b0257af3a4b1bd0ef47b74`. The local checkout has a different
historical commit ID; it is the same source tree, not the remote commit object.

The existing grouped run is [42730003667](https://github.com/wuyong9494-lab/kriswu/actions/runs/42730003667).
All five jobs passed: 925 core cases (16 skipped), 198 ordinary native cases
(12 skipped), three ordinary UI cases, 244 original-resource native cases, four
original-resource UI cases, 41 Python helper cases, unsigned device Release and
the concurrency gate. There were no failures. That run does **not** contain the
new guest sampling implementation or six new native tests described here.

Only the guest coordinator's local input sampling point changes. Transport
protocol, input admission limits, assets, offline controls, release and TestFlight
configuration remain unchanged. The six added native tests have **not run** in
this Linux executor, which has neither Swift nor Xcode. Source review and the
arithmetic model are not a native pass or a physical-device latency measurement.

## Failure path

Before this change the guest called `sampleInput()` after every accepted authoritative frame. That
function drains the current physical-input mailbox, then targets the replay's
`nextTick + 4`. It does not distinguish a frame that just arrived from a frame
that waited behind older reliable traffic.

Consider a warmed match whose host and guest both have `nextTick == 20`:

1. Withhold eight host frames, ticks 20 through 27, without dropping or changing
   their order. Keep both endpoint watchdogs serviced. The host reaches tick 28
   while the guest still expects tick 20. At nominal 60 Hz this models 133.3 ms,
   below the 250 ms local-clock limit and two-second peer limit.
2. The guest now presses and releases a ranged action. That action did not exist
   when the withheld host frames were produced.
3. Deliver the original frames in order, with immediate guest-to-host delivery.
   After the first frame, guest `nextTick` becomes 21. Its fresh action is drained
   into an input targeting tick 25. Host `nextTick` is already 28.
4. The host correctly rejects a target three ticks late. The allowed late window
   is only two ticks. The guest receives no input-admission acknowledgment.
5. The remaining seven replay callbacks sample again, but the one-shot action
   has already left the mailbox. Some samples are rejected or conflict at the
   current host tick, while later ones are accepted. None carries the action.

The match can remain running and host/guest state can still match exactly.
Therefore checkpoint equality, ordered transport and lack of disconnects do not
establish that a physical action was consumed. This is distinct from a deliberate
policy to reject an input that was actually old when the player submitted it.

Seven withheld frames form the useful boundary comparison: the first target is
25 and host tick is 27, so the action is accepted two ticks late and consumed
once at tick 27. Eight withheld frames make the same fresh action disappear.
The modeled 116.7/133.3 ms values are neither wireless measurements nor product
latency limits. A longer uplink delay can change the boundary.

## Targeted correction

The guest's existing local `service()` pulse now samples the physical mailbox,
but only after at least one authoritative frame and only when `replay.nextTick`
exceeds its previous sampled tick. The initial ready sample remains unchanged.
The previous tick is recorded before consuming or sending to make synchronous
reentrancy safe. A pulse reentered from a renderer callback while a frame is
being received cannot sample. Frame reception still validates, replays, publishes,
checks the match boundary and checkpoints every authoritative frame in order.

For the queued-backlog case above, replay reaches tick 28 before the next guest
pulse. The fresh action is then sampled once for tick 32 and consumed once. The
host's four-tick lead and two-tick late-admission window do not change. No input
is blindly retried, no conflicting samples are merged, and frames remain reliable.
Source fingerprints already include the changed coordinator, so old/new build
identities cannot silently mix even though the wire schema is unchanged.

This is deliberately narrower than acknowledgment/retry reliability. A service
pulse interleaved between portions of a backlog or a continuously delayed stream
can still sample against a stale replay tick. Uplink delay can still cause an
input to be rejected. There is no delivery guarantee or latency-improvement claim.
The local pulse can delay sending compared with immediate receive-callback
sampling, reducing the available input lead budget. Phase jitter, skipped pulses
and missing frames can extend sample-count hold/chord timing. The host still
expires held input after three consumed ticks without refresh, including during
network gaps; the local physical hold survives and can be sampled again later.

## Regression coverage prepared

Six native cases extend the existing synthetic coordinator fixture:

1. Seven/eight queued frames, both hero-seat orders: no guest samples during the
   exact ordered replay, then one fresh ranged edge at latest `nextTick + 4`,
   one authoritative consumption, equal final host/guest games.
2. One initial ready sample; repeated local pulses and duplicate frames neither
   resample the same tick nor consume a waiting edge. The next new frame permits
   one sample. Guest display/clock calls still cannot free-run simulation.
3. A fresh neutral weapon hold before an eighteen-frame burst is not instantly
   promoted to heavy. It needs eighteen actual input samples and consumes once.
4. Held movement expires on the host's unchanged lease during a gap, stays held
   in the local mailbox, refreshes after replay catches up and releases normally.
5. A renderer callback invoking `service()` during every replayed frame cannot
   reintroduce per-packet sampling or consume before frame processing completes.
6. Touch cancellation before the next local pulse clears an unsent action, and
   terminal interruption prevents later sampling or match reopening.

These tests do not exercise MCSession delivery or physical display timing. They
must run in the existing ordinary and original-resource lifecycle CI lanes before
this candidate is considered native-validated. Existing coordinator, input,
checkpoint, interruption, identity and strict replay tests remain applicable.
The 41 existing Python helper tests and `git diff --check` pass locally; those
checks cannot establish that the new Swift test or app code compiles.

## Remaining implementation and acceptance

Expose bounded local-only diagnostics for guest sample sequence/target, host
admission and authoritative consumption. Checkpoint equality does not identify a
lost input edge. Make immediate send errors observable: `GameRoom.sendDirect`
currently discards them. A broader input-delivery design needs bounded
acknowledgment/retention or an explicit freshness policy, with cancellation,
duplicate suppression and wire-version compatibility.

Acceptance must include clean-link latency and independently phased endpoint
clocks, queued and partially interleaved downlink bursts, uplink bursts, slow
continuous delivery, expiry, release/cancel and both seats. Heavy-hold and jump
chord wall-clock behavior still need measurement. Never subtract host and guest
monotonic clocks as if they shared an origin. Preserve host-authoritative
simulation and strict frame replay throughout that work.
