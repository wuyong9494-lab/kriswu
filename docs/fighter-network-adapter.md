# Fighter selection transport adapter

`DuelNetworkLobby` is a local-only development stage for two-player **selection**, not playable network combat. No view invokes it yet. It does not implement combat input synchronization, prediction, reconciliation, matchmaking UI, rematch negotiation, or asset availability negotiation.

## Integration contract

- The caller explicitly establishes a `GameRoom(kind: .fighter, ..., capacity: 2)` through the existing user-driven flow. Fighter uses stable matchmaking index 4; the existing indices 1–3 are unchanged.
- Construct `DuelNetworkLobby(room:)`, retain it, and explicitly call `attach()` only after exactly two members are ready. Construction performs no sign-in, advertising, browsing, matchmaking or sends.
- Attachment exclusively leases the previously empty authenticated-direct callback. It does not use legacy sender-claimed callbacks or overwrite other games' handlers. Membership/phase/host observations use Combine, leaving `onMembersChanged` untouched.
- Host attachment creates a fresh UUID. The guest sends a fresh nonce; only its pinned authenticated host may answer. The matching nonce plus validated initial selecting snapshot pins that session. Later snapshots cannot change it.
- Observe `snapshot` and `status`. Submit choices and Ready commands with the displayed selection revision. Host UI actions use the same reducer as guest traffic. Guest submission means queued, not accepted. Only the host may start; `started` means selection agreement, never simulation startup.
- Every packet is reliable, namespaced, protocol-versioned, bounded to 24 KiB before decoding, and checked against the pinned two-member roster. The guest replica additionally bounds/revalidates the snapshot. The existing reducer handles sequence replay, invalid choice, Ready invalidation, stale selection and guest Start rejection.
- Call `shutdown()` on view dismissal, app/lobby suspension, or room disposal, before releasing the coordinator. This clears selections, Ready state and pending handshake, then relinquishes owned callbacks without disconnecting the caller-owned room. Membership, host and phase changes also invalidate the session. Reattach is explicit and creates a new host session. There is no automatic host migration or reconnect.
- Replacing a room callback synchronously invalidates its explicit ownership token, even while the old callback is executing, so an old adapter cannot erase the replacement during shutdown. Do not replace callbacks during an active lobby; shut down its coordinator first.
- Either peer may attach first. Host attachment reliably announces its session; a pending guest responds by resending its existing nonce request. Announcements from anyone except the pinned authenticated host are rejected. No retry timer or automatic room startup is used. A new host session announcement closes an already-pinned guest projection, requiring explicit guest reattachment rather than silently treating it as a rematch.
- A new guest attachment nonce negotiates a fresh host session and resets both players’ choices, readiness, and sequence counters, including after selection has reached Started. Same-nonce retries are idempotent; retired nonces cannot reset a later session. The host retains at most 64 retired nonces per attachment; exceeding that limit explicitly closes both coordinators and requires a new attachment.
- Rejected or stale authenticated guest commands cause the host to resend its current snapshot. This allows a guest to recover an omitted update without optimistic state or authority changes. Same-revision snapshots remain harmlessly ignored by the replica.

## Offline tests and validation boundary

`DuelLifecycleTests+NetworkLobby.swift` extends the already-selected native lifecycle test class. Its injected paired transports use synchronous in-memory bytes only. Coverage includes both attachment orders, untrusted announcements, host and guest reattachment (including after Started), reentrant callback replacement, nonce retry/replay, rejected/stale command resynchronization, readiness invalidation, host-only start, malformed/oversized/foreign/versioned packets, replay, session pinning, member replacement, stale callbacks, callback ownership and stable game indices. The bridge ownership test constructs a room but never starts it or signs into an account.

Native tests require the iOS XCTest runner. No successful native run is claimed from a Linux workspace without Swift/Xcode. Real-device transport and end-to-end network combat remain untested/unimplemented.

## Native-runner recovery

The preceding candidate compiled successfully but its exact iPhone simulator
failed the 240-second boot wait on both attempts. The local CI follow-up opts
fighter jobs into one additional 180-second wait only if that exact device is
still available and Booted/Booting. A successful boot and complete valid PNG
remain mandatory. The fighter preparation step has a 20-minute ceiling; overall
job limits remain unchanged. Other games keep the shared helper's original
single-wait behavior. All 12 Python simulator-helper tests pass locally; this is
not evidence that the hosted simulator or the new native adapter tests passed.

## Verified remote checkpoint

The approved source tree at `e4d8bb9ac7935f50cf390d8cdf9f4bf05aadea64` passed
[unsigned run 42636839221](https://github.com/wuyong9494-lab/kriswu/actions/runs/42636839221).
Core: 857 tests, 16 existing skips, zero failures. Envelope and unsigned device
build passed. Native: 48 tests, zero failures, including the 11 offline lobby
adapter tests and six transport-identity tests. Both real-touch UI flows passed.
The simulator log confirms the extra bounded 180-second wait was used before
successful startup. No TestFlight distribution was triggered.

The actual-private-resource job was skipped on this independent branch. These
results do not establish actual-model visual quality, physical-device frame
pacing, two-device transport behavior, or playable synchronized network combat.
