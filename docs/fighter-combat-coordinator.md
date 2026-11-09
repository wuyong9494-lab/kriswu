# Native combat coordinator seam

## Scope and status

`App/Views/DuelNetworkCombatCoordinator.swift` is an opt-in, injectable native
owner for the existing selection router, committed start barrier, host simulation,
guest replay and external-authoritative `DuelSession`. It is **not wired into the
room screen**. The existing selection UI still stops at selection agreement.
There is no new matchmaking, sign-in, asset, key, release or TestFlight work.
The duty app and notification behavior are unchanged.

This source has not been compiled or exercised on iOS in this Linux workspace:
Swift and Xcode are unavailable. The deterministic native tests use synthetic
catalogs/sessions and an in-memory authenticated transport. Neither the source
nor those tests establishes renderer readiness, live transport delivery, or
playable two-device combat.

## Ownership and startup ordering

- One coordinator owns a router and the selection lobby throughout one session.
  It attaches the root and claims **both start and combat channels before attaching
  the selection lobby**, so a fast peer's offer does not land in an unclaimed phase.
  Construction alone does not claim callbacks or send traffic.
- Selection commands still pass through the existing lobby reducer/replica. A
  started snapshot creates a barrier pinned to trusted local room identities.
  Host is always seat/fighter 0 and guest always 1, regardless of membership array
  order, lexical identity, hero choice or viewpoint.
- The host explicitly calls `offer(startID:seed:)` only after the lobby's Start
  submission returns. That sends the authoritative started snapshot before the
  offer on the reliable ordered channel. Do not invoke it from the lobby's
  synchronous `@Published` snapshot callback, which runs before the lobby sends
  the snapshot. The API also requires the lobby's settled `.started` status.
- The production initializer requires a `DuelNetworkCompatibilityIdentity`
  produced by the independent installed-resource verifier. The injected loader
  receives the exact offered configuration. It must actually prepare its assets
  before returning `Resources`; compatibility and catalog structure/profile
  pairs are checked by the barrier. No procedural, legacy or offline fallback
  is selected when preparation fails.
- `Resources.makePresentation` runs only after the local barrier commits. It
  receives that live committed barrier and must use the production
  `DuelSession.networkPresentation` factory, mount the exact renderer and report
  success **only after real renderer preparation succeeds**. Merely constructing
  a scene or waiting a timer is not readiness. The coordinator checks the exact
  initial authoritative game, seat, committed configuration, paused external
  driver and untouched presentation tick before accepting it.
- The guest acknowledges the entire committed configuration only after its own
  renderer-ready callback and successful presentation start. The host cannot
  start presentation or advance its clock until both its own renderer and this
  guest acknowledgement are ready. Host simulation state is constructed before
  sending commit, so synchronous ready/input responses can be safely accepted.
- A guest waiting for the host's first frame retains the original handshake
  deadline, even though its local renderer can now display the initial state without authoritative advancement. Its shorter running-peer watchdog starts with the first frame. This
  avoids prematurely cancelling a valid host renderer load that takes over two
  seconds. There is no claim of a simultaneous distributed wall-clock start.

`Resources.release` is idempotently called by the coordinator. The injected
`cancelLoading` callback cancels outstanding preparation/render work on terminal
closure, once per owner. The caller must implement real cancellation and resource
cleanup. Late or duplicate resource/session completions are ignored and their
unused results are disposed. The DEBUG-only fixture constructors cannot be used
by the production coordinator.

## Inputs, frames and canonical verification

Coordinator control packets use the router's combat namespace/version with a
separate `coordinatorVersion: 1` and `control` body. They are distinct from the
existing authoritative `command: frames` messages. Control bodies are bounded to
4 KiB before decoding. The router bounds every packet to the appropriate phase
limit before routing, and preserves the authenticated sender identity. A peer
cannot supply a claimed identity to the core through these envelopes.

Controls bind both the selected session and offered start ID. The ready message
binds the complete configuration. Raw input requests additionally retain the
core's own version, session, epoch, sequence and tick checks. Control traffic
includes ready, input, checkpoint and cancellation; normal terminal cancellation
uses the existing start-barrier message so it also works before presentation.

- The host samples physical controls once per tick, and the guest samples once
  initially and once after each applied frame. Both target `nextTick + 4`.
  Sequences are independent from selection/start/frame sequences.
- Both host-local and remote-guest samples pass through `DuelNetworkInputs` with
  a trusted identity. Existing limits remain future 6 ticks, late 2 ticks,
  7 queued samples per seat and a 3-tick held-input lease. Invalid scalars,
  sequences, epochs, conflicting ticks and out-of-window inputs do not mutate
  the host. Rejected or duplicate inputs do not keep its liveness timer alive.
- Only the host clock advances simulation, exactly one frame per invocation.
  The core supplies explicit host and guest input, including neutral input
  after a missing/expired lease. The AI path is never selected. Guest timers,
  render display links and local controls never step its replay.
- The guest feeds original bytes to the existing replay validator. Duplicate
  frames are ignored without resampling input or publishing feedback. Sequence
  gaps, changed epochs and invalid batches terminate rather than guess or
  restore state. This seam rejects batches larger than one so each consumed
  tick has exactly one corresponding trusted presentation state.
- Every 60 consumed frames, both endpoints SHA-256 the full canonical equipped
  game state at the same boundary. Session/start/configuration binding and the
  single-frame stream fix the epoch and sequence context. Production encoding
  and hashing run on a detached utility task from an immutable `Sendable` game
  copy, not on the UI actor. Retention is bounded to one job, four host digests,
  and one early guest result awaiting its matching host digest. DEBUG tests hash
  synchronously for deterministic assertions. A second checkpoint before the
  previous job completes closes rather than queuing more snapshots.
- A matched-boundary digest mismatch closes the session. There is no decode,
  snapshot restoration, rollback, host migration or speculative correction API.
  Digests detect disagreement, not peer honesty or guaranteed cross-platform
  determinism. Missing digest reports are not a separate attestation protocol.

## Watchdogs and teardown

Production owns one MainActor task that sleeps approximately 1/60 second between
service calls. Tests inject monotonic time and call `service()` manually. This is
an initial scheduling seam, not a proven real-time pacing or latency solution.
There is no catch-up loop or frame skipping after a stall.

- Connecting, awaiting an offer and load/commit/presentation wait have a 15-second
  deadline. User selection itself has no arbitrary deadline. The load deadline
  is not refreshed by duplicate packets or repeated loader callbacks.
- Running endpoints close after 2 seconds without a newly accepted peer input
  (host) or frame (guest). A service gap greater than 250 ms closes rather than
  advancing a backlog. Initial host-renderer waiting uses the handshake rule
  above. Production also observes application resign-active and audio-session
  interruptions, including before a presentation exists.
- Start/combat traffic has a maximum of 240 authenticated routed packets per
  monotonic second. The existing router/lobby continue to own selection bounds;
  this is not a transport-wide denial-of-service protection layer.
- Packet, load/presentation completion, start and checkpoint boundaries check
  monotonic time and absolute deadlines before mutation or refreshing liveness.
  Queued work cannot outrun a delayed watchdog or erase a deadline that already
  expired. The same checks preserve the initial first-frame handshake grace.
- Every boundary checks the pinned room. Readiness, host, membership or room
  replacement, explicit interruption, renderer stop, load failure, timeouts,
  match completion and protocol mismatch are terminal. Reordering the same
  membership is harmless. An upstream same-ID reconnect that is never reported
  cannot be detected; its owner must explicitly close the coordinator.
- Closure invalidates tokens/state before invoking any transport, loader,
  observer, renderer or release hook. It cancels host/replay buffers first,
  supplies their cancelled state to presentation, shuts it down and releases
  channel/root ownership. Callback reentrancy cannot reopen the clock, start a
  second offer or publish late frames. Deallocation is a cleanup fallback;
  explicit synchronous close is the integration contract. Loader cancellation
  ownership is one-shot across explicit close and scheduled deinit cleanup, so
  an old owner cannot cancel a newer match through a repeated cleanup hook. The
  cancellation closure is explicitly `@MainActor @Sendable`: nonisolated deinit
  can transfer the immutable hook to cleanup without relaxing actor isolation.

The reliable ordered transport does not expose delivery success. No uncertain
packet is blindly retried or simulation tick regenerated. Lost/reordered startup
or combat traffic fails closed or reaches a watchdog. A future retry policy must
cache exact bytes, preserve strict ordering and remain bounded; it must never
call host advance to recreate a lost frame.

## Verification and next integration requirements

`Tests/SiteTests/DuelNetworkCombatCoordinatorTests.swift` extends the existing
`DuelLifecycleTests` suite with 23 in-memory cases covering both seat/hero orders,
selection-before-offer, synchronous commit/ready traffic, resource and renderer
barriers, a host renderer load longer than the running timeout, missing ready,
compatibility failure, cancelled load/presentation completions, saved stale
transport callbacks, input identity/window rejection, duplicate/gapped/batched
frames, clock/peer watchdogs, canonical mismatch, reentrant renderer interruption,
rate limiting and membership replacement. Additional regressions deliver a queued
frame, expired ready/input, and late resource/renderer completions before the
watchdog runs, and check that explicit close plus deallocation cancels the loader
only once. A separate deinit-only case checks actor-bound cancellation and root
release. Equipped movement fixtures use the real weapon-direction API. These
cases are written but **unrun**.

Executed here:

- Existing Python fighter-rules generator tests: 16 passed.
- Generated rules manifest includes the new coordinator source and its digest.
- Whitespace review passed. These checks are not Swift compilation or native QA.

On the authorized Mac/CI, regenerate the project and run the existing native
`SiteTests/DuelLifecycleTests` selection, plus all core network tests. Build both
Debug and Release to verify fixture exclusion and strict-concurrency checking.
Native tests must pass before integrating the room UI.

Production still needs an actual cancellable configuration-specific loader and
renderer-ready callback, verified original assets on both devices, an explicit
room-screen owner/mounting flow, clock/latency performance validation and nearby
and Game Center physical two-device testing. Exercise foreground/background,
audio interruptions, rendering failure, disconnect, packet loss/duplication/
reordering, host loss and reconnect with a genuinely fresh session/start. Do not
route selection agreement directly into a supposedly playable match or mark
multiplayer complete until this evidence exists.

Independent static review corrected equipped-input fixtures, startup timeout
semantics, one-shot cleanup coverage and queued-work watchdog races. Production
detached-hash completion ordering, close-during-hash and queued interruption
delivery still need native tests; the deterministic fixture path does not
exercise those branches.

A subsequent device build exposed a strict-concurrency warning when nonisolated
deinit read the old non-Sendable cancellation closure. The hook and all initializer
contracts now require `@MainActor @Sendable`; the one-shot guard is unchanged.
This correction still needs the native strict-concurrency CI rerun.
