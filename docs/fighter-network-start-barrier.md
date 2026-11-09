# Combat-start compatibility and load barrier

`DuelNetworkStartBarrier` is a pure-core, one-shot handshake after the trusted
`DuelMultiplayerSelection` snapshot reaches `.started`. Selection Started means
both players accepted the matchup, not that either device has loaded combat.
This new type does not alter the lobby, existing host simulation, app, assets,
GameRoom or transport. It neither constructs nor steps a game. Playable network
combat, client state replication and physical two-device validation remain work
for later integration.

## Endpoint and configuration contract

Create one endpoint per device from the same started selection. Separately supply
the trusted session ID, host ID, guest ID, local ID and expected `Compatibility`.
The host uses its authoritative selection reducer; the guest uses its validated
selection replica. The constructor checks exact session/roster/seat binding,
selection version, distinct valid choices, both ready flags and minimum consistent
revision/command counters. These structural checks do not authenticate a decoded
snapshot. Never derive the pinned IDs or trusted compatibility from incoming
combat-start bytes. Nearby IDs remain room-scoped identities, not verified
real-world accounts.

`Compatibility` contains the supported selection and combat-input protocol
versions plus explicit lowercase 64-character SHA-256 rules and catalog/content
fingerprints. The start envelope has its own namespace and protocol version.
Both endpoints compare exactly against their own caller-supplied expected values.
The caller must use the same documented digest recipe on both devices:

- Rules fingerprint must identify the actual gameplay/build rules and protocol
  implementation, not just a product version label.
- Catalog/content fingerprint must cover the full verified catalog and its
  required asset manifest, including schema/clock fields, profile IDs, resource
  hashes, equipment, roles, clips, motion tracks and combo links. Source/model
  changes must change this value even if the profile names remain the same.
- Compute from verified installed bytes, or from a trusted manifest after
  checking those bytes, with a shared canonical representation. The current
  catalog has no top-level content digest. `profile.sha256` identifies only one
  resource and is not a substitute for a full catalog/content fingerprint.

This core does **not** compute hashes, recover source assets, verify a manifest
signature or prove a peer is honest. Syntactically valid matching fingerprint
strings are compatibility assertions from the caller, not authentication or proof
of loading. Fingerprint production and resource verification are still adapter
work, and must be in place before using this in a real match.

The host explicitly chooses `startID` and `seed` in `makeOffer`. No random/default
seed is supplied by the barrier. The resulting immutable Configuration includes
session/start IDs, exact started snapshot and selection revisions, pinned host and
guest seats/choices, compatibility, seed, 60 Hz ticks, `.versus` mode and `.learning`
difficulty. Those fixed values match the current `DuelNetworkHostSimulation`
constructor; other modes/rates/difficulties are rejected. Host is always fighter 0,
guest fighter 1, independent of alphabetic identity or hero order. The host cannot
silently substitute a hero, catalog, seed or second offer after loading begins.

## Handshake

1. Host calls `makeOffer(startID:seed:sequence:)` and sends the returned Message
   reliably to the guest. The guest feeds bytes into `receive`, using the sender
   from the transport-bound identity callback, not any payload claim.
2. Each device independently loads the **exact** offered Configuration and
   verifies all required actual assets. After successful loading, it calls
   `confirmLoaded(configuration:loadedCompatibility:catalog:sequence:)`. This
   checks full Configuration equality, the locally verified compatibility, a
   non-nil valid `DuelWeaponCatalog`, and exact chosen hero/profile pairs. Missing
   or invalid catalogs fail without a fallback. The catalog's existing validator
   checks schema 1, preview clock 30, role/track/combo structure and distinct
   equipment; it does not load renderer resources or calculate content digests.
3. Each device sends its returned `.loaded(Configuration)` to the other. Receiving
   bytes can set only the **other** seat's load flag. A forged local-sender packet
   cannot bypass local resource validation. Each acknowledgement binds the entire
   offered configuration, not merely a start ID or seed.
4. Host calls `commit(sequence:)` only once it has both local and guest load
   confirmations. Guest accepts that exact commit only after its own load and
   the host's load acknowledgement. `committedConfiguration` is nil before the
   endpoint passes its barrier. The host's local commit does not prove delivery
   to the guest or establish a simultaneous wall-clock start.
5. A future host adapter may construct the existing host simulation with the
   pinned selection, committed seed and the same verified catalog. It must not
   advance based on selection Started or an offer alone. This barrier does not
   make the existing simulation constructor inaccessible or automatically enforce
   that adapter rule. Guest simulation/snapshot handling and synchronized display
   timing are outside this change.

All local methods act as the identity pinned at construction. Guest methods
cannot author offers/commits. Only remote bytes from the other pinned identity are
accepted. Methods return messages for the caller to deliver; no network action
occurs inside the core. Serialize all endpoint mutations in the adapter.

## Bounds, ordering and interruption

- Reliable, ordered delivery is the intended transport. Cache and resend the
  **same returned message bytes** after uncertain/lost delivery; do not call an
  emission method again to recreate an already accepted action. There is no
  timer, retransmission queue or delivery acknowledgement in this type.
- Sequences are positive, strictly increase per sender and belong only to this
  barrier. Normal senders begin at one; gaps are allowed. Selection and combat-input counters are separate;
  accepted duplicate/older sequences are ignored. Rejected messages, including
  malformed/wrong-session/incompatible/too-early messages, consume no sequence
  and never partially change state.
- A commit arriving before the host's load acknowledgement is rejected with
  `notLoaded`, not queued or accepted speculatively. Deliver the missing load
  acknowledgement and retry the same commit. Likewise a load arriving before
  its offer must be retried after the offer. An unreliable adapter must supply
  bounded retry/timeout handling or terminate; the core will not recover on its
  own. There is no claim of atomic distributed start during link loss.
- Inbound JSON is bounded to 8 KiB **before decoding**. `Message.encoded()` bounds
  outbound JSON, and local emission checks it before mutation. Identifiers are
  nonblank, control-character-free and at most 256 UTF-8 bytes. Digests have fixed
  length, commands have closed Codable cases, seats are fixed fields rather than
  arbitrary player lists, and retained state contains one offer and two counters.
  The adapter must still enforce rate limits and outer packet limits.
- Host-only offer/commit, exact config equality and pinned session checks reject
  stale or mismatched state. A second offer is never an update or rematch. Use a
  fresh unpredictable session ID and fresh start ID on reconnect/rematch and
  discard the previous endpoint. Reconstructing another barrier for the same old
  session would defeat its in-memory replay history; do not do that.
- `cancel()` and a trusted `disconnect(playerID:)` permanently close either
  endpoint, even after commit or sequence exhaustion. Either peer may send a
  terminal `.cancel` via `makeCancellation(sequence:)`. If no sequence remains
  or sending fails, still call local `cancel()`. A cancelled/disconnected barrier
  cannot reopen, reload, commit again or migrate host. Cancellation clears the
  offered/committed configuration and both load flags.
- The adapter must cancel on either peer's disconnect, host/membership change,
  room/session replacement, app interruption, load failure or handshake timeout.
  It owns notification and teardown on both devices. A previously started
  simulation must be stopped separately; the barrier never mutates that object.
  Cached configuration is not permission to keep running after terminal closure.

## Verification

`DuelNetworkStartBarrierTests` exercises both hero orders, exact serialized
configuration, explicit seeds, local/remote load separation, host-only offer and
commit, missing one/both acknowledgements, retry after reordered commit, malformed
or oversized bytes, namespace/protocol mismatch, different rules/content
fingerprints, independent session/roster validation, invalid source catalogs,
changed choices/seeds, duplicate/reordered sequences, UInt64 exhaustion, and
cancellation/disconnect before/during/after commitment. Fixtures are synthetic
`DuelWeaponTestFixtures`, not the user's private assets.

Swift is not installed in the implementation workspace. The tests have been
written and source-reviewed, **not compiled or executed**. Required follow-up in
an authorized Swift environment:

```sh
swift test --filter DuelNetworkStartBarrierTests
swift test --filter 'DuelMultiplayerSelectionTests|DuelMultiplayerReplicaTests|DuelNetworkInputsTests|DuelNetworkHostSimulationTests'
swift test --jobs 2
```

These files are not evidence of app integration, actual asset compatibility,
live transport delivery, a successful native build or playable two-device combat.
