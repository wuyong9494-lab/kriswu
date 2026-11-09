# Retained verified fighter preparation

## Scope and evidence

This opt-in slice closes the gap between installed-resource verification and the
objects used by a network presentation. It does not connect the room screen to
combat, replace the coordinator, add a transport, change offline behavior, or
ship assets. The duty app, global GLTF texture cache, releases and signing are
unchanged.

No Swift/Xcode toolchain is available in this Linux workspace. The new native
cases are written but unrun. Production-success cases require the approved
installed original pack and skip when it is absent. Neither synthetic fixtures
nor a mocked SceneKit completion can produce a full verified-ownership receipt.
This is not evidence of playable nearby/Game Center multiplayer or acceptable
frame pacing on a device.

## Synchronous preflight, then one session

`DuelNetworkCompatibilityIdentity.prepare(bundle:)` and its explicit
`prepare(rules:directory:stageURL:)` seam run synchronously on MainActor. A future
room owner must run this preflight before beginning the start/handshake deadline
and before offering the compatibility identity. It can block the UI while
hashing and decoding; this is not a background or cooperatively cancellable GLTF
loader. There is no mid-call cancel claim. Do not move these SceneKit/UIKit
objects to a detached task. Native load-time/peak-memory measurements and a
separately designed async loader remain future work.

Preflight preserves all fixed pins, schema/clip/image/audio validation, 62 content
records, byte limits and the final reread of every observed content file. Signed
installed resources remain the trust boundary. Directory inputs are not an
adversarial mutable-file-store guarantee, and the rules manifest is not proof of
compiler output or a cryptographic publisher signature.

The returned `DuelNetworkPreparedResources` has a file-private constructor. It
retains the independently verified identity/catalog, one character manager and
both decoded equipped characters, palace stage, original verified control view,
source and weapon effect owners, and their dedicated effect root. It creates no
session, advances no clock and emits/plays no combat effects. Existing
`verify(...)` calls prepare and immediately releases its live payload, returning
only the immutable identity. Any thrown preflight error cleans up completed
partial allocations before propagating the failure.

`DuelSession.networkPresentation(committed:prepared:)` reserves the owner's only
session claim **before** constructing a session. A second call fails without
creating a second session whose teardown might release the first session's
characters. A reserved construction failure closes the owner. Compatibility,
catalog, selected profiles and cache object identities must match the committed
barrier exactly. `loadedCharacter(for:)` is cache-only: a miss cannot reread a
file or accept a replacement object. The earlier identity-plus-manager factory
cannot adopt a manager belonging to this preparation owner.

## Mounting the retained objects

Create `DuelNetworkMatchPreparation(session:prepared:invalidated:completion:)`
with the same live owner. This reserves one mount for the lifetime of that
session. Then mount the existing external `DuelMatchView`. The owner must remain
retained by the future loader/room flow until terminal cleanup.

- The full-path world reserves its sole renderer before installing callbacks or
  touching nodes. A rejected second renderer cannot detach the first one's root
  or erase its callbacks.
- Character instances use exactly the cached verified assets. The palace root
  is instantiated from the retained stage model. No full-path branch consults
  `Bundle.main`, reopens a character file on cache miss, or reloads effect files.
- The exact dedicated effect root is attached to that scene and the world uses
  the retained source/weapon effect owners. The existing SceneKit preparation
  includes the initial scene and those owners' stable runtime-effect templates.
- The controls container mounts the exact control view created by verification.
  A released/missing/already-claimed owner gets a fail-closed empty placeholder,
  never a file load or a successful production receipt.
- Normal mounted bounds, source art, input bindings and actual SceneKit success
  remain required. Initial controls stay disabled and the session stays paused.
  Only the coordinator can subsequently start presentation/advance authority.

`verifiedResourceOwnershipComplete` becomes true only for this full path after
actual renderer and controls readiness, a live session/mount claim, exact
manager/stage/character/effect/control reference identities, and stage/actor/
effect roots attached to the expected scene, including the live weapon effect
owner's exact private runtime container attached to that dedicated root. A
same-named replacement node does not satisfy this check. These checks run again after
synchronous prepared-state observers return. A release, root/scene replacement,
cache change or session stop during those callbacks prevents success delivery.
The legacy identity-plus-manager and DEBUG synthetic paths still report false.
A DEBUG renderer completion override also cannot issue a full receipt, even with
installed originals.

The receipt describes a point-in-time preparation milestone, not an ongoing
attestation or transport permission. Later disappearance, renderer invalidation,
room changes and coordinator shutdown must still close the presentation. This
slice does not redesign control callback mutability or protect against arbitrary
same-process code altering loaded geometry/materials.

## Terminal release and next work

`release()` first nils the optional payload and consumes lifecycle hooks, before
any reentrant UI/session callbacks. It disables/unbinds controls, shuts down
effects, detaches their root, clears the character manager and tears down mounted
views/session. Repeated release is harmless. An owner object retained after
release keeps identity and consumed claim markers, not its closed payload.
Session shutdown also releases this owner. Late UIKit view construction preserves
a full-path marker so it cannot restart loading through the legacy path.
Explicit synchronous release remains the integration contract; callers must not
abandon an active mounted owner without cleanup. UIKit/SceneKit may transiently
retain view/render work after teardown, and the existing global texture cache is
not cleared or changed here.

Nine new native cases cover retained originals/release, duplicate session and
mount rejection, compatibility failure, cache-only misses, reentrant release
with pending/late renderer completions, real SceneKit plus original control
success, post-publication root/claim/container changes, rejection of mocked readiness and
exact live runtime-container parenting (including a same-named impostor).
Run the existing `SiteTests/DuelLifecycleTests` selection with the private pack,
plus Debug/Release strict-concurrency builds and existing UI/lifecycle tests.
The success/reentrancy cases use actual renderer callbacks and are explicitly
not replaceable by manufactured production identities.

Next: integrate an explicit room-owned preflight/mount flow with cancellation,
coordinator resources and commit acknowledgements; measure synchronous preflight
and runtime performance; and test two physical devices, foreground/background,
audio interruption, loss/duplication/reordering, host loss and fresh-session
reconnect. Selection agreement alone still does not start a playable match.

The earlier device build also diagnosed the manually stored
`ObservableObjectPublisher` as a MainActor witness for a nonisolated conformance.
`DuelNetworkMatchPreparation` now explicitly declares its `ObservableObject`
conformance MainActor-isolated, supported by the required Xcode 26 / Swift 6.2+
toolchain. This keeps the publisher actor-confined; no `@unchecked Sendable`,
`nonisolated(unsafe)`, preconcurrency suppression or concurrency-gate change is
used. The correction still needs the native device/simulator build rerun.
