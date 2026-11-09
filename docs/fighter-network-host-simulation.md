# Local host simulation integration

`DuelNetworkHostSimulation` connects the bounded input inbox to the existing
`DuelGame` equipped engine. This is pure-core, local-only preparation, not
playable network combat. There is no native app hookup, transport packet,
client simulation, combat snapshot, prediction or reconciliation here.

## Construction and authority

Provide a trusted authoritative lobby's started snapshot, an explicit local host
identity, an explicit seed and the loaded equipped catalog. Never promote an
arbitrary decoded peer DTO into host authority. The constructor checks protocol,
nonempty session/identities, exactly two distinct identities in host/guest seat
order, started phase, both valid ready choices, distinct heroes, and consistent
minimum command/revision counters. It checks catalog validation and exact
hero/profile IDs, and requires successful equipped-engine construction. Missing
or invalid catalogs throw; no laboratory moveset or alternate hero is selected.
The caller still owns transport authentication, session freshness, asset loading
and compatibility negotiation. Structural validation is not authentication.

Duplicate hero choices remain displayable in the selecting lobby, but
Ready(true) and Start reject `conflictingChoices`, without consuming a sequence.
Ready(false) is still allowed. Changing either choice clears both ready flags.
Replica snapshots with duplicate choices and any Ready flag are invalid. This
preserves the equipped engine's existing distinct-profile invariant.

## Stepping and interruption

- Host is fighter 0, guest fighter 1, regardless of identity sorting or hero order.
- Each host step consumes exactly one inbox frame and passes both inputs to
  `game.step`. Missing/expired guest input is explicit neutral, never nil, so it
  never enables the game's AI fallback. Transport tick and game frame are distinct
  counters, particularly after match completion.
- Input reception, stepping, pause/resume, cancel and disconnect enforce the
  pinned local host identity. The identity must come from trusted local state.
- Pause clears inbox queues and held leases, advances the inbox epoch and calls
  `game.cancelBufferedInputs()` to discard already-buffered game commands.
  Started actions are not undone. Paused stepping throws without advancing.
- Resume retains monotonically increasing sequences and requires the new epoch.
  Cancel or either pinned peer's disconnect permanently closes this wrapper and
  clears both input layers. There is no host migration or rematch reuse.
- State is read-only externally; consumers cannot bypass inbox stepping through
  a mutable game reference. Equal seeded configurations and accepted streams
  produce equal local states, not a cross-platform synchronization guarantee.

## Validation boundary

New source tests cover constructor DTO corruption, both seat/hero orders,
missing/invalid catalogs, host-only lifecycle, neutral guest behavior, identical
seeded replay, and pause clearing both active game buffers and future inbox
entries. An additional deterministic regression feeds distinct non-neutral inputs
from both peers for 180 ticks in each hero order, checking every consumed input
and resulting state against explicit two-input `DuelGame` stepping and a second
seeded wrapper replay. Selection/replica conflict regressions cover refusing readiness/start
until choices differ and skipped-snapshot swaps. Fixtures are synthetic
`DuelWeaponTestFixtures`, not private game assets.

Swift is absent in this workspace. Tests are written/source-reviewed only, not
compiled or executed. Run `swift test --filter DuelNetworkHostSimulationTests`,
the selection/replica suites and the complete core suite in an authorized Swift
environment before relying on this integration. Two-device combat and physical
device validation remain future work. No network action, publication or release
is part of this local change.
