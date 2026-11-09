# Fighter local controls and external-authoritative presentation

## Scope and status

This local slice separates `DuelSession`'s physical input and presentation from
its existing offline simulation driver. It does not wire the network selection
UI, transport, start acknowledgements, a combat coordinator or a playable nearby
match. Core simulation, replay/wire/barrier code, assets and release workflows
are unchanged. The first native CI attempt reached test compilation but rejected
four throwing assertion callbacks; explicit nonthrowing do/catch checks now
preserve those assertions. Native verification is pending the corrected run.
No release was made for this slice.

## Driver and construction

- The existing `DuelSession(DuelSetup)` initializer remains offline with local
  fighter 0. `advance()` samples its mailbox and calls the existing one-player
  simulation path, including the existing offline opponent behavior.
- External sessions are explicitly `.externalAuthoritative`, begin paused and
  validate `localFighterIndex` as 0 or 1 before accessing arrays. Host is fighter
  0 and guest is fighter 1 on both devices. No world coordinates, directions,
  actors, health arrays or score arrays are swapped for a guest.
- Production `networkPresentation(committed:verified:assets:)` requires a
  locally committed barrier, a `DuelNetworkCompatibilityIdentity` produced by
  the independent full-source verifier, and a matching `DuelWeaponAssets` owner.
  It validates the role/configuration/compatibility/catalog through the existing
  combat protocol guard, checks exact catalog equality and loads both
  integrity-checked equipped characters. It builds the exact host-first heroes,
  seed, difficulty and mode. Missing or corrupt assets throw, never select the
  laboratory moveset. The production external renderer also fails closed rather
  than substituting its procedural stage when the verified stage cannot load.
- A `DEBUG`-only `presentationFixture` initializer permits synthetic native tests
  without private assets. It is separate from the production factory and carries
  no committed configuration. Neither fixture construction nor generic
  presentation start grants network authority or satisfies a load barrier.
- `startAuthoritativePresentation()` only enables this session's initial local
  controls/rendering. The future coordinator still owns renderer loading,
  commit/acknowledgement, transport liveness and the actual simulation clock.
  Local Resume/Restart cannot bypass the coordinator, even before initial start.
  Start is reserved before input-reset hooks run, so nested starts are rejected.
  A pause/shutdown from an input-reset, renderer or published-property callback
  wins over the outer start and cannot be overwritten into a running session.

## Input and authoritative steps

`consumeLocalInput()` consumes physical edges once without touching canonical
simulation state. Equipped input uses the local fighter's current authoritative
facing and airborne state. Horizontal movement retains world-coordinate sign.
Control labels/support/readiness, opponent-prone fading, ultimate readiness,
hit/damage totals and outcome/hit/guard/grapple feedback use the local seat.

In external mode, the display link's `advance()` is a no-op: no simulation, AI,
neutral-input guess, catch-up replay, animation tick, effect event or mailbox
consumption occurs. The coordinator chooses when to sample physical input and
submit it through its validated host input path.

`publishAuthoritativeStep(trustedGame:tick:)` accepts one already validated
host/replay simulation result. Its tick is the zero-based consumed-input tick,
not `game.frame`. It requires contiguous ticks beginning at zero, rejects
repeats/gaps/out-of-order/overflow and further steps after match-over. It rejects changed seat heroes, mode,
difficulty or equipped profiles before changing presentation state. It keeps
animation frozen according to the previous authoritative hit-stop state and
publishes existing event/HUD feedback once. It never calls `game.step`.
Nested step publication is rejected until the entire preceding publication,
including feedback, returns. A rejected nested step consumes no tick. Feedback
reads an immutable step snapshot and stops immediately if a renderer callback
pauses, shuts down or supplies authoritative cancellation. Physical reset and
terminal-stop callbacks are guarded against recursive reset/stop notification.

This is an in-process **trusted caller contract**, not a snapshot decoder,
wire validator, state authenticator or resynchronization API. The coordinator
must use state produced by its committed host or accepted guest replay, tied to
the same start. It must not feed arbitrary decoded states or reconstruct state
from unvalidated peer claims. Construction does not revoke a copied barrier
when the live room closes; lifecycle cancellation still must be propagated.

For this first integration seam, use `DuelNetworkCombatHost.advance(frameCount: 1)`
and publish each accepted one-frame guest replay. Existing wrappers expose only
the final state of a larger batch. Do not skip intermediate ticks, fabricate
intermediate states or replay a batch through `DuelSession`; a future deliberate
per-step wrapper API is needed before supporting larger presentation batches.

## Clearing input and terminal lifecycle

- External touch cancellation, `clearInput`, pause, interruption and renderer or
  session shutdown clear physical controls only. They cannot clear the canonical
  hit-stop/queued-combo buffers. Offline clearing keeps its existing behavior.
- Local pause or renderer shutdown requests coordinator stop once through
  `didRequestAuthoritativeStop`, stops presentation and is terminal. Repeated
  calls, Resume, Restart or another presentation-start request cannot reopen it.
- The coordinator cancels its own host/replay wrapper, then may supply the
  resulting state through `publishAuthoritativeCancellation(trustedGame:)`.
  This can arrive after local pause, but not after session shutdown. It neither
  emits another simulation event nor advances animation/presentation counters.
  A second cancellation publication is rejected. Teardown rejects late work.
- The coordinator must own input request sequencing, bounded queues, disconnects,
  timeout and scene lifecycle. There is no reconnect, host migration, epoch
  switching, input transport or automatic restart in this change.

## Verification

`DuelLifecycleTests+ExternalPresentation.swift` adds 20 native tests to the
existing lifecycle suite. Synthetic cases cover both hero orders and seats,
invalid seats, no clock/AI/input-drain behavior, facing/world movement and guest
airborne selection, local equipped labels/readiness, canonical pending-input
preservation through physical clear/pause/renderer teardown, terminal cancellation,
contiguous publication and late-work rejection, final-event deduplication, hit-stop animation, guest HUD
feedback/counters/readiness, existing offline stepping, and actual host → wire →
validated guest replay → presentation for 60 single-frame ticks in both hero
orders. Six callback-reentrancy regressions additionally exercise nested starts,
input-reset/renderer/published-observer stops, nested next-tick publication and
pause/shutdown/cancellation during a simulation callback. Synthetic resources
do not prove private-asset loading or rendering.

The current executor has neither `swift` nor `xcodebuild`. Native tests and the
production network factory are **not compiled or executed here**. Run the existing
`DuelLifecycleTests` selection on an authorized Xcode simulator and the equipped
private-resource suite before integration. Real two-device nearby testing, full
renderer loading/commit coordination and all failure/recovery flows remain open.

## Mounted renderer/control preparation seam

This continuation adds a pending mount, not room networking or a completed
verified-resource loader. `DuelNetworkMatchPreparation` retains the **exact**
paused external session independently of `DuelNetworkCombatCoordinator.presentation`.
The future loader can expose this owner immediately after constructing the
committed session, then mount `DuelMatchView(external:onExit:)`. Waiting for the
coordinator's `presentation` property before mounting would deadlock: that
property is assigned only after the loader reports readiness.

The existing `DuelMatchView(setup:)` still owns its offline session through a
StateObject. The external branch observes the supplied session and keys its
native subtree by the one-match mount ID. It never reconstructs a DuelSetup or
starts an offline fight. While paused it displays preparation status and an
explicit exit action, without Resume/Restart. Exit, disappearance and scene
interruption cancel the mount and invoke the supplied exit action once. A fresh
match needs a fresh session and mount; another owner cannot reuse its callbacks.

### What is actually prepared

- `DuelWorldView.prepareNetworkScene` waits for that exact SCNView to have a
  window and finite, nonzero bounds. Scene construction, SwiftUI appearance and
  elapsed time are not readiness. It calls SceneKit's asynchronous
  `prepare(_:completionHandler:)` on the scene and effect preparation objects.
- The SceneKit completion is returned to MainActor. Its owner token, paused
  initial session, live scene identity, window and current bounds are checked
  before a one-shot receipt. A prepared scene identity remains retained until
  teardown, because controls may become ready later. The combined receipt
  checks that scene identity and both views' current layouts again.
- A network-only native controls container binds the existing source-control
  callbacks, requires authenticated source artwork, then waits for attachment
  and a usable joystick/button layout. It stays disabled while the session is
  paused. A previous good layout does not remain ready after becoming too small
  while renderer preparation is pending. Layout changes retrigger the gate.
- Source hit/block effects expose detached SCNPlane/material templates for every
  verified track, including additive/alpha, depth and sampler variants. Weapon
  effects expose every family/swing/shadow shader/material variant with the same
  vertex/UV/UInt16 triangle layout builder used by live ribbons. These bounded,
  per-owner templates remain retained and underpin runtime material copies.
  Copies isolate per-particle color/UV transforms and per-trail source time.
- The new preparation APIs never call emit, consumeStep, audio playback or audio
  warming. They do not advance input, simulation or animation. Existing ordinary
  effect initialization/audio behavior is unchanged. Templates survive reset
  and are released on shutdown; no global match cache is added.

A successful SceneKit preparation covers these shader/material resources, not
allocation-free runtime bursts, dynamic trail-buffer uploads, visible-first-frame
proof, sustained frame rate, latency or two-device playability. Shader/material
copies may still incur framework runtime work. Measure that on the target device.

### Deliberate remaining resource boundary

The mount completion returns a `DuelNetworkMatchPreparation.Receipt`, **not** a
`DuelSession` suitable for blindly forwarding to the coordinator completion.
It reports initial scene, runtime-effect variants and controls separately.
`verifiedResourceOwnershipComplete` remains **false**: the current world still
reopens the palace through `Bundle.main`, and the earlier verifier does not yet
retain and hand the exact verified stage/control/effect objects to this mount.
A production loader must solve that ownership/materialization pipeline before it
can promote this milestone to full resource-ready session delivery. This slice
must not be wired as an unconditional `.success(session)` callback.

Production mount construction requires an untouched paused committed equipped
session with a weapon-assets owner. DEBUG-only session/control/effect fixtures
are separately named and cannot satisfy that production constructor. Synthetic
image injection never changes `sourceArtAvailable`; only the explicit DEBUG mount
path permits it for lifecycle tests.

### Cancellation and tests

Cancellation invalidates callbacks before disposing controls, scene, effect
owners and session resources. Detachment, scene replacement, preparation failure
and duplicate mounting fail closed; queued or duplicate prepare completions
cannot revive the session. A persistent invalidation callback reports renderer
or controls loss even after the one-shot milestone has been delivered. Old mount
cleanup does not clear another session's renderer/input callbacks.

The mount also owns a token-scoped pending-session invalidation hook, independent
of the coordinator stop callback installed only after loading. Pause, shutdown,
load failure or authoritative cancellation immediately fail and dispose a pending
mount, including after scene preparation while controls have never become ready.
No later layout or GPU callback is required. The hook is consumed before calling
out, removed only for its matching mount on cleanup, and removed before successful
delivery so a synchronous coordinator start is not mistaken for failed loading.
Renderer teardown reports its precise failure after disposing its resources and
before the generic terminal-session notification.

`DuelLifecycleTests+NetworkPreparation.swift` adds 19 native tests to the existing
lifecycle suite, covering mount/layout gating, combined readiness, source failure,
exact failure reasons, duplicate/late completions, cancellation/detachment,
post-prepare scene replacement and renderer resize, controls resize during async
preparation, pending-session termination without subsequent readiness events,
synchronous post-receipt start, callback ownership, reentrant cancellation and
post-observer gate revalidation, one-shot exit and
post-receipt invalidation. It also adds an actual mounted synthetic SceneKit
prepare test, a SwiftUI exact-session mount test, and synthetic effect-template
identity/no-side-effect/runtime-material-isolation tests. The synthetic geometry
and shader tests do not authenticate private production resources.

Local whitespace checks and the 16 existing Python rules-manifest tests pass.
This new slice has **not been Swift-compiled or native-tested in this workspace**,
which has neither Swift nor Xcode. Run the new native suite plus existing offline,
resource and UI regressions in authorized CI before continuing room integration.
No coordinator, transport, room UI, asset payload, key or release workflow is
changed by this preparation slice; it is not published by this worker.
