# Reliable consumed-frame replay, protocol 1

## Scope

`DuelNetworkCombatProtocol`, `DuelNetworkCombatHost` and `DuelNetworkReplay` add
pure-core host-to-guest replay after the existing combat-start barrier. They do
not add GameRoom transport, app/UI integration, network time synchronization,
prediction, rollback, snapshots, host migration, a reconnect flow or playable
two-device combat. Existing simulation, input inbox and barrier files are not
changed by this slice.

## Construction and authority

- Create the host wrapper from its **locally committed**
  `DuelNetworkStartBarrier`, the exact matching trusted started selection, the
  caller's independently verified loaded compatibility, and the same verified
  equipped catalog used during the barrier. Create the guest replica from its
  own locally committed barrier and its verified loaded compatibility/catalog.
  A decoded configuration by itself is deliberately not a constructor input.
- The barrier pins independently supplied session/host/guest identities and
  compatibility. Constructors reject uncommitted or closed barriers, the wrong
  local role, incompatible loaded assertions and missing/invalid catalogs. The
  host also requires its selection revisions, IDs and choices to match the
  committed configuration. Neither endpoint selects a fallback hero or a
  laboratory moveset.
- Host is fighter 0 and guest is fighter 1 on **both** devices, independent of
  identity sorting or hero order. Both use the exact committed seed, choices,
  mode, difficulty and tick rules. A guest renderer can orient its display, but
  must not swap simulation seats or initialize itself as fighter 0.
- Catalog structure and profile matching are checked; actual resource loading
  and SHA production are still the caller's responsibility. A passed
  `loadedCompatibility` is an assertion, not a computed fingerprint or proof of
  possession. The complete catalog/content/rules recipe remains the start
  barrier's adapter requirement. No new cryptographic implementation is added.
- A barrier is a value, not a live revocation handle. After constructing either
  wrapper, the adapter must propagate subsequent cancellation, session/roster
  changes, app interruption, authentication loss and disconnect to that wrapper.
  Never recreate a wrapper from an old saved barrier to reset replay counters.

## Host and wire contract

`DuelNetworkCombatHost.receive` passes raw input requests and the separately
authenticated sender to the existing host inbox. `advance(frameCount:)` copies
that simulation, actually consumes and steps 1...32 frames, validates and encodes
the resulting message, then commits the copied simulation and stream sequence.
A rejected count, counter exhaustion or encoding failure leaves the host
unchanged. The wrapped simulation is not externally mutable. There is no API
to stamp arbitrary caller-supplied input requests as consumed frames.

The wire message carries namespace `fighter.combat-frames`, protocol version 1,
session ID, start ID, epoch, sequence and a closed Codable command: `frames` or
`cancel`. Session/start identifiers are nonblank, control-character-free and at
most 256 UTF-8 bytes. The sender identity never comes from the payload. Epoch is
fixed at zero for this first version. Sequences start at one and are contiguous
for the host stream, separately from selection, barrier and input sequences.

Each frame has its host consumption tick and both fully resolved input samples.
For example, a late request originally targeting tick 0 but consumed at tick 2
is sent as tick 2. Held leases appear on every tick where the host consumed
them; attack edges appear only on their actual consumed tick. The guest never
re-runs arrival scheduling, lease expiry, AI, local control or guessed neutral
input. The host's neutral input for an absent peer is explicitly present in
the frame, not inferred by the guest.

Wire `Input` has required integer `move`, integer `vertical`, boolean
`guardHeld`, integer `tapBits`, and an optional closed weapon-command enum.
It never decodes through `DuelGame.Input`, whose decoder clamps directions and
supplies defaults. Directions must be -1...1, taps 0...63, with at most one
laboratory attack bit plus optional jump. Weapon commands exclude all tap bits;
guard excludes both edges and weapon commands. Movement plus guard is legal.
Malformed/missing required fields, invalid raw values and unknown commands are
rejected, not clamped, defaulted, merged or partially accepted.

Inbound bytes are capped at 32 KiB **before decoding**. Outbound validation
bounds arrays before encoding. A frame batch must contain 1...32 frames with
strictly contiguous ticks, starting at the replica's `nextTick`. No frame may
use `UInt64.max`, so the next tick remains representable. These ticks count
host input consumptions, not the internal game-frame counter. That distinction
remains valid when a finished game stops updating its own frame.

## Reliable ordered application, duplicates and retries

Feed bytes only through `DuelNetworkReplay.receive` with the transport-bound
host identity. Every input and tick in the complete batch is checked before
any simulation step; both inputs are then explicitly passed to `game.step`.
Invalid later frames cannot apply a valid prefix. Wrong sender/session/start,
malformed/oversized packets, invalid input, sequence gaps, tick gaps/overlap and
conflicting duplicates do not change the game or counters.

Only one accepted decoded envelope is retained, bounded to one batch:

- An identical retry of the immediately previous message returns
  `ignoredDuplicate`, without replaying it. Equality is decoded message equality,
  not byte-for-byte JSON equality. This also recognizes a terminal cancellation
  retry or the last frame after a separate local teardown, but cannot reopen.
- The same sequence with different contents is `conflictingDuplicate` while
  active. Earlier sequences are `staleSequence`, rather than being replayed or
  silently accepted as verified duplicates with unavailable history.
- A skipped sequence is `sequenceGap`; a skipped/overlapping batch start is
  `tickGap`. Rejected packets consume no sequence. Deliver the missing original
  messages in order, then retry the rejected original bytes. There is no queue,
  retransmission timer, acknowledgement, recovery snapshot or unbounded history.
- Cache/resend the returned host message after uncertain delivery. Calling
  `advance` again is **not** a retry: it advances new ticks. Bound the adapter's
  outstanding messages and stop/close on stalled delivery or timeout. A host
  emitting a message does not prove receipt or simultaneous display timing.
- Sequence and tick overflow are guarded. A maximum positive sequence cannot
  skip missing earlier messages. Exhaustion cannot wrap counters or reopen the
  stream; local terminal cancellation does not depend on available counters.

## Terminal interruption and epoch policy

This slice intentionally does **not** support pause/resume. `interrupt`,
`cancel`, or a trusted disconnect of either pinned participant permanently
closes either wrapper and clears buffered game commands. The host also clears
its inbox/held leases. Started actions are not undone. There is no AI takeover,
host migration or implicit new match. Restart requires a fresh unpredictable
session/start and a fresh selection/load/commit sequence.

`makeCancellation()` closes the host and returns an optional ordered terminal
notification. If it fails or delivery is uncertain, still close locally and
have the adapter stop the peer via its disconnect/timeout handling. Remote
cancellation obeys the same ordered sequence rule; it does not leapfrog missing
frames. A guest wanting to leave closes locally and lets the existing
authenticated transport/lifecycle signal stop the host.

A valid, correctly routed message from the pinned host with an unexpected epoch
returns **`terminatedForEpochChange`**, closes the guest and clears its buffered
commands without applying frames or advancing counters. This is explicitly a
terminal outcome, **not an atomic rejection**. Wrong sender/session/start or
invalid payload cannot trigger that transition. It prevents an old buffered
simulation from continuing across a pause boundary this version cannot replay.
The adapter must stop processing and replace the session, not retry old epoch
frames or resume this replica. No pause-state synchronization is implied.

The caller owns a bounded liveness watchdog on both devices, packet byte/rate
limits, backpressure, stop-on-disconnect behavior and clearing local physical
control state. The pure core cannot notice a silent cable/link loss or revoke a
stale committed barrier on its own.

## Optional state diagnostics

Both wrappers expose `verificationState()` returning the exact committed
configuration, epoch, next consumption tick, last stream sequence, lifecycle
phase and `DuelReplayStateEncoding.encode(game)` bytes. Compare the **entire**
record after the same completed message. Same visible pose or same game bytes
alone do not identify the same start or stream position.

This is an optional local equality API, not a wire command or digest. It uses
the canonical encoder's full state, including RNG, pending commands and equipped
profiles/tracks. It neither uses Swift `Hasher` nor claims cryptography. A future
platform SHA layer must bind the configuration and boundary as well as these
bytes. There is no expected hash received from an untrusted host and no state
overwrite when mismatching. The caller decides to stop/report a mismatch.

Canonical bytes preserve exact floating bits and can reveal differences across
platforms; they do not prove cross-architecture floating-point determinism. Full
equipped state can be large. Generate only at bounded diagnostic checkpoints,
off the UI/render thread using immutable copies, not on every production tick.

## Verification status

`DuelNetworkReplayTests` covers both hero orders over 180 real
host-input-consumption → Codable wire → guest steps, checking each consumed
frame and host/reference/guest state plus canonical verification records. It
also covers lease and late-input resolution, explicit neutral absent peers,
commit/role/catalog binding, sequence retry/conflict/old replay, tick gaps and
overlap, malformed final-frame atomicity, strict raw scalar combinations,
missing fields/unknown commands, identity/session/start/version checks,
byte/batch/counter boundaries, terminal cancellation with actual queued
commands, both peer disconnects, interruption and unexpected epoch shutdown.
Fixtures are synthetic `DuelWeaponTestFixtures`, not production/private assets.

The local executor has no Swift compiler. Tests were written and source-reviewed
but **not compiled or run**. Run in an authorized Swift environment:

```sh
swift test --jobs 2 --filter DuelNetworkReplayTests
swift test --jobs 2 --filter 'DuelNetworkStartBarrierTests|DuelNetworkHostSimulationTests|DuelNetworkInputsTests|DuelReplayState'
swift test --jobs 2
```

This is not evidence of transport integration, a successful iOS/native build,
verified SHA/content production, cross-device determinism, a completed live
match or real-device acceptance. No assets, app, workflow, existing combat
engine or host/barrier implementation was edited by this slice.
