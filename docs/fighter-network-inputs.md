# Host input inbox foundation

`DuelNetworkInputs` is pure Swift host-side input scheduling. It is not wired to
GameRoom, the app, or any transport. There is no prediction, rollback, clock
synchronization, real network latency measurement, or multiplayer UI here.

## Trust and lifecycle

Construct only after the two-player selection session has started. Pin its
session ID and distinct host/guest identities. Supply authenticated transport
sender identity separately from the packet and trusted local host identity to
all mutations. Strings are assertions from the adapter, not authentication.
A future adapter must enforce transport authentication, byte/rate limits,
selection/start authorization and delivery of the authoritative pause epoch.
Do not decode a sender or local authority from untrusted payload fields.
Use a fresh unpredictable session ID for every rematch, reconnect or host change.

Pause clears both peers' queues, edges and held leases and increments the epoch.
Resume retains sequence high-water marks and simulation tick. Old-epoch packets,
including previously unseen in-flight packets, cannot revive input. Disconnect
of either player and cancellation clear state and close permanently. There is no
implicit host migration or AI takeover. Epoch exhaustion closes the inbox;
tick exhaustion rejects consumption rather than overflowing.

## Deterministic scheduling contract

- Host/guest always occupy seats zero/one. Sequence numbers start at one and
  strictly increase per peer for the entire session, including across pauses.
- Duplicate or reordered sequence numbers at/below the accepted high-water mark
  are ignored without mutation. Invalid packets do not consume a sequence.
- A packet may target the next consumption tick through six ticks ahead, or be
  up to two ticks late. Late input is applied at the next tick, never retroactively.
- Each peer's accepted scheduled ticks must strictly increase. A second packet
  for the same tick or an earlier scheduled tick is rejected, not merged or
  silently overwritten. If a future packet arrives first, subsequently arriving
  older-sequence packets are discarded. The sender should send one resolved
  input sample per simulation tick, in sequence order.
- There are at most seven queued samples per peer. The fixed time window also
  bounds queue size. No retry loop or unbounded collection is retained.
- `consume` advances the inbox tick exactly once per call and returns both inputs.
  Calling it twice advances two ticks; the host adapter owns the simulation loop.
  A packet's taps and weapon command occur on only its scheduled tick. Held move,
  vertical direction and guard survive for three ticks total, including that
  packet tick. Missing refresh then yields neutral input. An explicit neutral
  sample releases held state immediately. Future packets do not refresh a lease
  before their scheduled tick.
- Lost samples are not recovered. Later samples refresh held state, but lost
  edges stay lost. An accepted edge is delivered once unless pause/cancel/
  disconnect deliberately discards it. Outcomes depend on arrival order and
  consumption order; replay the resulting frame stream to reproduce that run.

The caller must always use `game.step(frame.host, opponent: frame.guest)`.
Do not omit the opponent or pass nil: that game API deliberately enables AI.
Both missing seats receive neutral input after their individual leases expire.
Inbox ticks count simulation calls, not wall-clock time or the game's frame
counter, which may differ during hit stop or match transitions.

## Raw validation

Decode `Message`, not `DuelGame.Input` (whose initializer clamps directions).
Message directions must be -1, 0 or 1; tap bits must be within 0...63. At most
one laboratory attack bit is allowed, optionally alongside jump. A weapon
command excludes all tap bits. Guard cannot coexist with an edge command.
Guard plus movement is allowed as an explicit sample. Weapon commands use the
existing closed Codable enum; unknown enum values fail decoding. All fields
are required except the optional weapon command. Validation never clamps or
partially accepts a packet. The adapter remains responsible for selecting the
appropriate combat mode and cannot infer animation authority from input.

## Verification status

`DuelNetworkInputsTests` covers authority/session/version checks, atomic invalid
raw fields and combinations, duplicate/reordered sequences, tick boundaries,
late application, lease expiry, one-shot edges, pause replay prevention,
terminal disconnect/cancel, and deterministic explicit two-player DuelGame
replay equivalence. Swift is unavailable in the implementation environment, so
these tests were added but not executed here. Run:

```
swift test --filter DuelNetworkInputsTests
swift test
```
