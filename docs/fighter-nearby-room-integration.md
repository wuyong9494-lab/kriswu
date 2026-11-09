# Explicit nearby room integration

## Scope and evidence

The explicit fighter nearby entry now connects verified installed resources,
selection, the existing committed start barrier, real mounted preparation and
host/guest combat. A stable concrete room container stays mounted and swaps selection for its
pending committed presentation inline. This is a development integration, **not
verified playable multiplayer**: Swift/Xcode and physical devices are unavailable
in this Linux workspace. No native case has been executed here.

Game Center remains clearly labelled selection-only. Opening the entry form does
not start networking or sign in. There is no automatic/offline/procedural fallback
from any nearby verification, connection, mount, readiness or protocol failure.
The existing offline game, assets, duty features, reminders, notifications and
release/signing workflows are untouched.

## Ownership and order

1. `DuelNetworkRoomModel.begin()` marks the room as preparing and schedules a
   later MainActor turn. This lets SwiftUI process the loading state before work
   begins; it is not a guarantee of a rendered frame or a responsive progress bar.
2. `DuelNetworkCompatibilityIdentity.prepare()` runs synchronously on MainActor,
   before `GameRoom.start()` or any coordinator handshake deadline. It can block
   the UI while decoding and hashing. It is not a background or cooperatively
   cancellable decoder. After it returns the owner rechecks its generation and
   application foreground state, releasing the result if cancelled/interrupted.
3. The returned `DuelNetworkPresentationLoader` retains the exact prepared
   resource owner. One coordinator creates/owns the router before selection.
   It attaches all start/combat receivers before its borrowed selection lobby.
   The view's selection model never attaches or shuts down this shared root.
4. Both endpoints select and ready through the existing lobby reducer. The host
   room calls `selection.startSelection()`, waits for that call to return with
   settled `.started` lobby status, and only then offers a fresh start ID/seed.
   No snapshot/status observer sends the offer. The started reliable snapshot
   precedes the offer even with a synchronously responding peer.
5. Loading confirms the offered configuration against the already verified
   catalog. Only a committed barrier can create the single external session
   through `networkPresentation(committed:prepared:)` and reserve its mount.
   The loader publishes `pendingPreparation` while that session is still paused,
   before `coordinator.presentation` exists. The room mounts that exact object;
   waiting for coordinator presentation first would deadlock readiness.
6. Real SceneKit preparation and usable mounted original controls must produce
   a receipt with all readiness fields and verified object ownership. The loader
   rechecks receipt owner, session and live resources. Only then can the existing
   coordinator accept presentation, acknowledge the guest and start the host.
   Timer delays, scene construction and DEBUG fixtures cannot pass the production
   loader's receipt checks. Neither endpoint's display clock advances authority.
7. The mounted preparation/session identity stays unchanged when running begins.
   The lobby preview is removed once selection is committed and never receives
   the prepared character manager. Its separate manager remains preview-only.
   There is no second full-screen combat cover or selection-screen disappearance
   callback that accidentally leaves the active room. Terminal errors/results stay
   on the room screen until its Leave action; match-view dismantling never
   dismisses that explanation.

Coordinator `didChange` is delivered after its outer mutation boundary finishes,
not from a property's `willSet`. It reports coherent state/failure/configuration/
presentation changes and suppresses frame-by-frame UI churn. A callback may close
reentrantly; the closed notification follows cleanup. It does not authorize an
offer from a lobby `@Published` observer, whose sender still owns publication.

## Terminal lifecycle

One synchronous room `close()` invalidates generation before clearing tasks,
observations and callbacks. It closes the coordinator/router, cancels pending
mount/session/resources, closes the selection borrower and calls `room.leave()`
exactly once. Normal disappearance, user exit, scene inactivity/background,
audio interruption, loading/preparation failure, membership/host replacement,
protocol timeout, renderer invalidation and match completion all terminate.

The borrowed selection model retains its bounded pending-command timeout but
routes timeout/close to the room owner. The coordinator retains its connecting,
start, renderer and running watchdogs. Deliberate waiting for a player or a user's
selection has no new arbitrary timeout. A fresh entry requires a fresh room/model,
resource owner, selection session and start. Old queued startup, room, loader and
transport callbacks cannot claim a later owner. System permission/login alerts
that make the app inactive are terminal too; after granting a permission the user
may need to re-enter the room. No reconnect/host migration is implied.

## Coverage and remaining verification

`DuelLifecycleTests+NetworkRoomIntegration.swift` adds 17 native cases:
explicit/preflight ordering, fail-closed preparation, cancellation before/during
preflight, post-preflight foreground check, reliable start-before-offer, pending
mount-before-ready, consumed local/remote controls and replay, one root/borrowed
selection, pending timeout, membership and interruption, stale callbacks,
reentrant observers/repeated close reasons, settled coordinator cleanup,
a hosted SwiftUI lobby-to-mount transition without leaving, and clearly
selection-only remote flow. Three production cases run only with the
approved installed originals: cancellation release, the hosted SwiftUI transition
with real preparation, and two real mounted SceneKit/control endpoints using the
production loader. The latter does not
replace SceneKit preparation or manufacture production identity. It also drives
the retained source controls through their pointer/binding path and checks
consumed host/guest input frames and matching replay after the input lead.
Synthetic routing tests deliberately use the existing DEBUG coordinator/session seam and
are not renderer, network delivery or production-readiness evidence.

Executed here: 16 existing Python rules-generator tests passed; a generated rules
manifest includes both new production files; `git diff --check` passed. None of
these is Swift compilation or native QA. XcodeGen discovers new App and SiteTests
sources through existing directory entries; no project/release changes were made.

Required next: Debug and Release strict-concurrency builds with Xcode 26/Swift
6.2+, the full native lifecycle/core networking suite and existing duty/offline UI
regressions. With approved originals, run the production loader/mount tests and
measure synchronous preflight duration, peak memory and frame pacing. Then test
two physical nearby devices for both hero/seat orders, first-time local-network
permission, repeated entry/exit, readiness asymmetry, background/audio
interruptions, disconnect/host loss, loss/duplication/reordering and genuinely
fresh-session re-entry. Game Center combat and release/TestFlight remain outside
this slice. Do not claim the user's full multiplayer requirement complete before
this evidence exists.
