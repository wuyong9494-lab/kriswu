# Nearby callback ordering regression coverage

## Finding and scope

This change adds tests of the **existing** `GameRoom` delegate bridge. It does
not replace production `Task { @MainActor ... }` callbacks with a dispatch queue,
change networking, or claim that a delivery-order defect was reproduced.

Apple documents a private serial delegate queue and ordered reliable delivery:
- [MCSessionDelegate](https://developer.apple.com/documentation/multipeerconnectivity/mcsessiondelegate)
- [Reliable delivery](https://developer.apple.com/documentation/multipeerconnectivity/mcsessionsenddatamode/reliable)

The earlier general discussion of actor scheduling in SE-0306 is insufficient to
establish a defect in this bridge. [SE-0431, implemented in Swift 6.0](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0431-isolated-any-functions.md#adoption-in-task-creation-routines),
adds actor-aware task creation. Its explicit-global-actor example guarantees that
`Task { @MainActor in ... }` starts on that actor in creation order. Its adoption
section also explains back-deployment support. The current `GameRoom` nearby
state, envelope, and direct closures all explicitly specify `@MainActor` and have
no suspension in their delivery bodies. `fighter-lab.yml` selects Xcode 26.6;
`project.yml` uses Swift 5 language compatibility with complete concurrency
checking. The relevant behavior comes from the selected compiler/runtime APIs,
not an assumption that all actor tasks on every toolchain are FIFO.

The sole app-source addition is a DEBUG-only fixture that calls the existing
private session factory. The release-path factory, delegates, session identity
checks, direct authentication, reentrant checks, ownership, message limits,
encryption, discovery, and remote Game Center behavior are unchanged.

## Regression coverage

`Tests/SiteTests/DuelLifecycleTests+NearbyDelivery.swift` adds nine cases to the
existing native `DuelLifecycleTests` suite:

1. All four games retain the room itself as delegate, for both nearby roles.
   Required encryption, no connected peers, and no started room are checked.
2. A real background serial source injects 512 alternating direct/payload
   packets around hello, disconnect, and reconnect. The test waits for all 516
   observable callbacks and compares their exact order and room state.
3. A callback invoked on main cannot overtake an earlier background callback.
4. Queued and late callbacks from a retired session cannot mutate its successor.
5. Leaving rejects old work without erasing a successor's authenticated callback
   lease, even when new callbacks are installed on the same room object.
6. Leaving from a hello callback rejects the rest of the pending burst.
7. Replacing the session from a direct callback rejects old work and preserves
   delivery and ownership for the new session.
8. Malformed packets remain rejected; offline sender claims stay unauthenticated.
9. Existing nearby games keep their raw direct callback and authentication checks.

The fixture creates an actual `MCSession` with the production delegate. It does
not advertise, browse, invite, sign in, or fake `connectedPeers`. The background
source has a bounded completion wait, ensuring that the burst is enqueued before
the main actor processes it. The positive ordering cases await every expected
callback. Other cases use explicitly isolated task completion markers, including
one further marker for a callback enqueued reentrantly. No sleeps, polling loops,
or guessed repeated `Task.yield` counts are used.

Positive authenticated network delivery is deliberately not claimed from these
offline tests. Existing identity-pinning tests independently cover rejection and
quarantine. The synthetic source checks the delegate-to-main bridge, not Apple's
wireless implementation or physical device timing.

## Validation status and remaining checks

Local source review, `git diff --check`, and all 16 Python network-rules generator
unit tests pass. A byte comparison confirms that `GameRoom.swift` is unchanged
from HEAD outside the DEBUG fixture. The current executor has no Swift compiler
or Xcode, so these native tests and native compilation have **not run locally**. The existing fighter-lab native and original-resource lanes already
select `SiteTests/DuelLifecycleTests`; no workflow expansion is needed.

Run those lanes and the iOS build against the final source before treating the
tests as native-validated. Then validate both hero/seat orders on two physical
nearby devices, including burst traffic, disconnect, leave/rejoin, and background
transitions. A passing simulator test does not establish wireless reliability,
end-to-end latency, sustained FPS, or thermal behavior. A failing ordering test
should produce toolchain-specific evidence before a transport rewrite is chosen.
