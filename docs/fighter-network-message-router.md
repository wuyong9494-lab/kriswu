# Native fighter phase message router

## Scope

`App/Services/DuelNetworkMessageRouter.swift` owns one `DuelLobbyTransport` lease
continuously while selection, load/start, and combat consumers hold independent
channel leases. A selection lobby can remain `.started` without blocking another
protocol's callback claim.

The actual fighter room screen now constructs `DuelNetworkSelectionModel(room:)`.
Its transport initializer retains the router and injects the selection channel
into the existing lobby. It explicitly attaches the root before the lobby when
the screen reports a ready room. `.started` retains the root; timeout, background
close, attachment failure, or protocol-driven closure releases it terminally.
`init(lobby:)` remains available for existing protocol/presentation tests.

Only the selection model and its one RoomView construction call change. There
are no GameRoom, lobby, core protocol, workflow, asset, or UI label changes, and
no added room start/leave/sign-in calls. Start/combat consumers are not wired or
enabled. The existing directory-based XcodeGen targets include the new app
source and native test extension automatically.

## Future integration

The following lower-level composition is available for future start/combat
integration. The installed selection screen uses the model-owned router above:

```swift
// room must already be an authenticated, ready, two-player fighter room.
let router = DuelNetworkMessageRouter(transport: DuelGameRoomTransport(room: room))
try router.attach()
let lobby = DuelNetworkLobby(transport: router.channel(for: .selection))
try lobby.attach()

// Future start/combat adapters independently claim these transports:
let startTransport: any DuelLobbyTransport = router.channel(for: .start)
let combatTransport: any DuelLobbyTransport = router.channel(for: .combat)

// The owner retains router across all phases and closes it on session exit.
router.close()
```

Construction, channel lookup, and root attachment send no packets. No path starts
or leaves a room, signs in, starts matchmaking, constructs a simulation, advances
a clock, or adds outbound loopback. Each endpoint must be handed only to its
intended coordinator. `DuelLobbyTransport.sendReliable` has no owner argument,
so an endpoint is a send capability while its current lease exists; the router
does not claim to authenticate separate local callers sharing that endpoint.

## Routing and limits

Only these existing, exact namespace/version pairs are registered:

| Channel | Namespace | Version source | Maximum JSON bytes |
| --- | --- | --- | ---: |
| selection | `shift.fighter.selection` | `DuelMultiplayerSelection.protocolVersion` | 24,576 |
| start | `fighter.combat-start` | `DuelNetworkStartBarrier.protocolVersion` | 8,192 |
| combat | `fighter.combat-frames` | `DuelNetworkCombatProtocol.protocolVersion` | 32,768 |

The implementation refers to those protocol constants rather than defining new
wire identities. It checks the largest registered byte limit before decoding a
minimal JSON header, then checks the exact namespace/version and that channel's
own byte limit. Outbound packets undergo the same checks and must match the
sending channel. No namespace prefixes, foreign fallbacks, broadcast, queue, or
implicit delivery to an unclaimed channel exist.

Inbound packets retain their original bytes and transport-authenticated sender
string. Only the pinned remote participant is eligible; local echo, absent
members, and identities embedded in packet bodies do not confer authority.
The router validates only the envelope and room context. Protocol bodies,
session/start identifiers, sequence order, rate/timeout policies, committed
barriers, and simulation authority remain downstream responsibilities. A routed
packet is not evidence that a protocol accepted it or that combat may begin.

## Ownership and lifecycle

- Root attachment requires a ready fighter room with capacity two, two distinct
  bounded nonempty identities, a member local identity, and a member host.
- Every read, claim, send, receive, and room observation checks pinned local,
  host, and membership identities. Member array reordering is harmless; host
  seat ownership still comes from `hostID`.
- Each channel accepts one owner. A wrong owner's release cannot erase its
  successor, and a separate per-claim generation prevents a reentrant callback
  from notifying a replacement that happens to reuse the same owner UUID.
- Releasing a phase channel never releases the root. There is no automatic
  transition or callback handoff when selection becomes `.started`.
- Readiness loss, kind/capacity changes, or identity/roster changes close the
  router terminally. All endpoint states become `ready == false` before any
  close callbacks, even if the underlying room remains ready. This lets the
  existing injected lobby clear itself through its normal room-state check.
- Explicit `close()` is synchronous and idempotent. The root token is cleared
  before release and callbacks, and root release occurs once. Late root
  callbacks cannot resurrect the router. Terminal endpoints cannot claim/send.
- Retained endpoints do not retain the router. Deallocation makes endpoint
  reads immediately closed and schedules root release plus consumer notification
  on MainActor. Explicit close is the normal integration contract.

`DuelLobbyRoomState` has no room/session generation identifier. A disconnect and
reconnect to identical identities that the upstream transport never reports
cannot be inferred here, nor can a packet's claimed session be trusted as a
room change. The future session owner must close this router when ending or
replacing a session, and downstream protocols must continue pinning their own
session IDs. An explicit new session uses a new router, not reattachment to a
closed one. Code outside the router must not replace the sole authenticated
GameRoom callback while this router owns it; the existing owner-aware release
contract protects a successor from cleanup but exposes no lease-revocation
query to this layer.

## Focused native verification

`Tests/SiteTests/DuelLifecycleTests+MessageRouter.swift` adds 21 entirely in-memory
XCTest cases covering:

- explicit attachment, invalid/busy root leases, and identity change during claim;
- exact routing, authenticated identity preservation, malformed/unknown/version
  rejection, exact byte boundaries, per-channel bounds, and no local loopback;
- independent owners, stale release, unclaimed drops, and reentrant observer
  replacement including owner UUID reuse;
- a real `DuelNetworkLobby` handshake and `.started` selection coexisting with
  start/combat channels under one root lease, then lobby-only shutdown;
- harmless member reordering and terminal identity/readiness invalidation;
- missed upstream observations detected at read/claim/send/receive boundaries;
- synchronous reentrant close, closed-state propagation to the existing lobby,
  late root callback rejection, successor root ownership, and deallocation.
- model-owned root retention through selection agreement, routed selection
  commands, handshake/pending timeout, background-like close before/after attach,
  busy/error cleanup, host protocol-session replacement, and model deallocation
  without a second attachment attempt.

The start/combat payload fixtures deliberately test routing, not full wire-body
acceptance. Existing core start-barrier/replay tests remain the protocol checks.

On a configured Mac, generate the existing project and run the native suite:

```sh
xcodegen
xcodebuild test -project ShiftReminder.xcodeproj -scheme ShiftReminder \
  -configuration Debug -destination 'platform=iOS Simulator,id=<existing-device-udid>' \
  -parallel-testing-enabled NO -only-testing:SiteTests/DuelLifecycleTests \
  CODE_SIGNING_ALLOWED=NO
```

The implementation workspace is Linux with neither Swift nor Xcode installed.
No native compile or XCTest pass is claimed here. This change has not started
CI, signed in, connected to a network match, committed, or pushed anything.
