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
