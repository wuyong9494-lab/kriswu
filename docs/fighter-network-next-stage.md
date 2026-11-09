# Fighter network selection: isolated core, not shipped multiplayer

## Implemented locally

`Sources/ShiftCore/DuelMultiplayerSelection.swift` implements only a two-seat,
host-authoritative pre-match reducer and versioned Codable messages/snapshots.
The reducer is not connected to the app. An additive transport-identity callback
is implemented locally in GameRoom for a future adapter; live fighter networking,
two-device combat and selection UI remain unimplemented. Existing combat, assets
and release workflows are unchanged.

- Protocol version 1; a fresh session ID is mandatory for each reconnect/rematch.
- Stable transport member IDs determine fixed seats: host 0, guest 1. Display
  names and member-array ordering never decide ownership.
- Valid choices are Sun (`ember`, `sun_katana`) and Liu (`liu`, `liu_hammers`).
  Gale and crossed weapon/hero pairs are rejected. Duplicate hero selections may
  be displayed, but Ready(true) and Start reject `conflictingChoices` until the
  choices differ. The equipped engine requires two distinct profiles.
- Each player's accepted sequence is monotonically increasing, beginning at 1.
  Duplicate/older commands are ignored. Gaps are allowed, so a newer command
  supersedes older commands; rejected commands do not consume a sequence.
- Every changed selection increments the shared selection revision and clears
  BOTH ready flags. Ready and Start must reference that exact revision.
  Reselecting the same choice leaves readiness intact.
- Start requires the authenticated host, both choices and both ready flags.
  Once started, selection is frozen. Start replays cannot start a second match.
- Trusted disconnect events clear choices/readiness and permanently close the
  session. No host migration. Fresh membership creates a fresh reducer/session.
- Snapshot revision increments on each accepted command; sequence and revision
  arithmetic never wraps. Exhaustion requires a fresh session. Disconnect still
  closes the local state at exhaustion; the adapter must tear down rather than
  rely on a guest accepting another snapshot with the same revision.

## Existing integration points and opt-in identity binding

`App/Views/DuelView.swift`: `DuelSetup` currently carries one hero, difficulty,
mode and original-weapons flag. `DuelSession` creates an offline opponent.
There is no two-player input/session adapter to reuse directly.

`App/Services/GameRoom.swift` supplies `me.id`, `members`, `hostID`, `isHost`,
`onMembersChanged` and `sendDirect(_:delivery:)`. Reliable direct traffic has the
right host/guest topology for this selection stage.

The additive **`onAuthenticatedDirect`** callback is now implemented locally.
Use this callback, not legacy `onDirect`, for the future selection adapter:

- Nearby host reception resolves the actual MCSession peer through its current
  connection-pinned identity mapping and rejects duplicate identities or attempts
  to change identity until that peer disconnects. Nearby guests accept only their
  established host peer with its pinned identity.
- Game Center reception uses the sending `GKPlayer.gamePlayerID`; guest-side
  reception accepts only the current host.
- Both paths reject claimed sender/transport mismatches, self identities and
  identities missing from or duplicated in the current roster. Current session/
  match object identity is checked to reject delayed callbacks from old objects;
  the peer/player must still belong to the current transport and the room must
  be in its ready phase, excluding queued traffic after closure.
- `leave()` clears the new callback. Legacy `onDirect` behavior remains unchanged
  and still forwards the embedded sender claim; this is an opt-in migration,
  not a security upgrade for existing consumers.

The reducer's `authenticatedSenderID` is a caller contract, not cryptographic
validation. Nearby identities are room-scoped, not verified real-world accounts.
Use trusted local room state for `localPlayerID`. Fresh protocol session IDs,
fixed roster validation and room lifecycle handling remain adapter requirements;
a current transport object alone cannot distinguish a new logical match from
an old one. The reducer does not make a dishonest host secure.

## Next integration stages

1. Add a separate fighter game kind/matchmaking group with exactly two members;
   do not reuse arena traffic. Consume `onAuthenticatedDirect` and verify its
   lifecycle handling before integrating the selection reducer.
   On member/host changes, room closure, background interruption or timeout,
   close the old selection session. On host loss the guest discards its local
   projection immediately; it does not try to author a host reset message.
2. Add an app-level host lobby adapter. Host chooses a fresh unpredictable
   session UUID and pins the two identities. Use a bounded namespaced envelope
   and reliable delivery. Decode commands with a payload size limit; route the
   host's own UI actions through the same reducer. Serialize reducer mutations.
   Broadcast authoritative snapshots after accepted commands. Resend the latest
   snapshot on stale/rejected commands so a client can recover from stale views.
3. Integrate the new local `DuelMultiplayerReplica` guest validator. It bounds
   JSON payloads to 16 KiB and checks the pinned host/session/roster, protocol,
   seats, valid choices/readiness, revision ordering and legal phase progression.
   It requires a selecting snapshot before accepting Start. Initialize it from
   the trusted room handshake, never arbitrary incoming snapshot identities.
   A Codable Snapshot alone is NOT a validated client state; the replica does
   not restore host authority. Discard it on disconnect or host/session change.
   Execute the new tests and native integration tests before displaying network
   state; the replica is not wired to GameRoom or UI in this stage.
4. Add the two-player selection UI with authoritative previews and ready status.
   Disable Ready until both choices are present, distinct, and the current snapshot is
   known. Keep pending UI intent separate from accepted state. Include asset
   catalog/content version compatibility and loading success before final Ready.
5. Define a separate versioned combat-start descriptor: agreed selections/seats,
   rules/assets version, seed, tick rate and start ID, plus an acknowledgement
   barrier before simulation. The current `.started` phase only means the
   selection host accepted Start; it does NOT mean both devices loaded a match.
6. Implement host-authoritative simulation and guest input/snapshot handling,
   bounded tick/sequence validation, disconnect/pause behavior and deterministic
   replay tests. Validate on two physical devices over nearby and Game Center,
   including latency, packet duplication/reordering, reconnect, host loss and
   app backgrounding, before claiming playable network combat.

## Validation in this stage

`Tests/ShiftCoreTests/DuelMultiplayerSelectionTests.swift` contains 12 XCTest
cases covering roster/seat validation, all hero/weapon pairs, identity/version/
session checks, duplicate/reordered traffic, readiness invalidation, stale/future
revisions, unready, host-only start, terminal reset and Codable round trips.

`Tests/SiteTests/GameRoomTrustedDirectTests.swift` (an extension of the existing
`DuelLifecycleTests` suite selected by fighter CI) currently adds five native
XCTest cases for pinned identity/quarantine, duplicate/local identities, callback
cleanup on leave and static sender validation. They have NOT run here. These
tests do not exercise live MCSession/GKMatch callback routing or stale transport
object rejection. Native callback integration and live two-device tests over both
transports remain pending.

`Tests/ShiftCoreTests/DuelMultiplayerReplicaTests.swift` adds nine unrun cases
for legal lifecycle, bounded/malformed payloads, host/version/session/roster/seat/
choice validation, revision ordering, readiness and skipped-snapshot transitions.
Regression cases also reject Start without a newer host command and clearing an
established choice before disconnect, even when supplied counters increase.

Required execution once a Swift toolchain is available:

```sh
swift test --filter DuelMultiplayerSelectionTests
swift test --filter DuelMultiplayerReplicaTests
swift test
```

Swift is not installed in the current execution environment. These tests were
written and source-reviewed but NOT compiled or executed here. A clean whitespace
check is not a compiler or integration-test pass. This stage remains local and
unpublished pending review and the parent task's publication scope.
