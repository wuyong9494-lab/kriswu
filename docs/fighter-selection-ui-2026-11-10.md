# Fighter selection UI: local next-stage work

This locally prepared change adds an explicit entry from the existing fighter lobby
to a landscape-first, dark/bronze two-seat selection room. It does not replace
offline fighter practice or any other game, duty screen, reminder or notification.

## Scope

- Opening the entry form performs no networking or Game Center sign-in.
  Creating, browsing or entering a room is an explicit action.
- Fighter rooms always have two seats; manually entered remote codes must begin
  with 2. Nearby and remote room traffic retain the existing fighter game group.
- The room screen owns one start/leave lifetime. It attaches the existing
  `DuelNetworkLobby` only when the room is ready and never silently reattaches
  after disconnect, backgrounding, timeout or a failed attachment.
- The UI displays host-authoritative player seats, choices and readiness.
  A queued guest action is separately marked pending; it cannot change the
  displayed choice, preview or ready flag before host acceptance. Repeated taps
  are disabled while waiting. Unacknowledged commands/handshakes time out.
- Duplicate choices show a conflict and disable readiness. Changing either
  choice clears both ready flags through the existing reducer. Only the host
  sees the enabled finalization control after both players are ready.
- “锁定双方选角” finalizes selection only. Both peers remain on an explicit
  selection-complete screen explaining that network combat is not connected.
  No code path constructs `DuelSetup`, `DuelSession` or `DuelMatchView`.
- Exit, background and coordinator closure release the selection lease and
  leave the owned room. The old screen cannot restart a transport or selection.

## Remaining integration boundaries

This is not a playable network combat implementation or an SF3 visual-parity
claim. Asset/rules compatibility negotiation, load confirmation, a combat-start
acknowledgement barrier, render/input wiring and live two-device validation are
still separate work. The existing showcase renderer is reused without altering
assets or `DuelWorld`.

During source review, the shared GameRoom remote startup was found to have a
separate lifetime gap: `leave()` did not invalidate the asynchronous sign-in /
find-match operation. A late completion could adopt a match after screen exit.
The shared-room fix in this batch reserves startup ownership before sign-in,
cancels a superseded search, rejects stale completions and disconnects late
matches. Delegate callbacks verify their current transport before changing state.
Eleven offline native regressions cover cancellation, restart, late completion
and cross-room ownership, including reversed authentication completion order.
The combined change passed independent static review; native validation and
live two-device checks remain necessary before remote acceptance.

## Validation

Added nine native cases to the existing `DuelLifecycleTests` suite: two-seat
codes, inert construction/one attachment, callback ownership failure, conflicts,
readiness invalidation, host-only terminal finalization, non-optimistic guest
intent/repeated taps, handshake/command timeout and disconnect cleanup.
Added a UI flow that opens/closes the entry three times, validates two-seat codes
and checks that no single-player match is opened. It deliberately does not start
a transport or request Game Center sign-in.

Local Swift/Xcode compilation and execution are unavailable in this Linux
workspace. These are authored regressions, not passing native/UI test results.
Run the complete `DuelLifecycleTests`, `DuelFlowTests` and core suite on the next
authorized native validation, followed by nearby/remote two-device interruption
and reconnect checks. This batch is committed locally; no public push, release
or workflow change is included.
