import XCTest
import Combine
import UIKit
import SceneKit
import SwiftUI
@testable import ShiftReminder

#if DEBUG
@MainActor
private final class RoomIntegrationTransport: DuelLobbyTransport {
    var state: DuelLobbyRoomState
    var owner: UUID?
    var receive: ((Data, String) -> Void)?
    var changed: (() -> Void)?
    weak var peer: RoomIntegrationTransport?
    var packets: [Data] = []
    var claims = 0
    var releases = 0
    var drop = false
    init(local: String) {
        state = .init(isFighter: true, capacity: 2, ready: true, localID: local,
                      hostID: "z-host", members: ["a-guest", "z-host"])
    }
    func claim(_ owner: UUID, receive: @escaping (Data, String) -> Void,
               changed: @escaping () -> Void) -> Bool {
        guard self.owner == nil else { return false }
        claims += 1; self.owner = owner; self.receive = receive; self.changed = changed
        return true
    }
    func release(_ owner: UUID) {
        guard self.owner == owner else { return }
        releases += 1; self.owner = nil; receive = nil; changed = nil
    }
    func sendReliable(_ data: Data) {
        packets.append(data)
        if !drop { peer?.receive?(data, state.localID) }
    }
}

@MainActor
private final class RoomIntegrationClock {
    var time: TimeInterval = 100
}

@MainActor
private func roomIntegrationCatalog() -> DuelWeaponCatalog {
    let profiles: [DuelWeaponProfile] = [DuelGame.Hero.ember, .liu].map { hero in
        let katana = hero == .ember, prefix = katana ? "katana" : "hammers"
        let zero = Array(repeating: DuelWeaponPoint(), count: 17)
        func clip(_ name: String) -> DuelWeaponClip {
            let base = (0..<17).map { DuelWeaponPoint(x: 0.2 + Double($0) / 20, y: 1) }
            let tip = (0..<17).map { DuelWeaponPoint(x: 0.7 + Double($0) / 20, y: 1) }
            return .init(name: prefix + "_" + name, frames: 9, sha256: String(repeating: "c", count: 64),
                bundle: "synthetic-room-test", tracks: .init(samplesPerSourceFrame: 2,
                    root: zero, handL: zero, handR: zero, footL: zero, footR: zero,
                    weaponBaseL: katana ? [] : base, weaponTipL: katana ? [] : tip,
                    weaponBaseR: base, weaponTipR: tip, groundLift: Array(repeating: 0, count: 17)))
        }
        let roles = ["idle", "walkForward", "walkBackward", "guard", "hit", "knockdown", "getUp",
                     "jump", "weapon1", "heavy", "kick"]
        return .init(id: katana ? "sun_katana" : "liu_hammers", hero: hero, faction: prefix,
            resourceName: "Synthetic_" + prefix, bytes: 128,
            sha256: String(repeating: katana ? "a" : "b", count: 64),
            bodyID: "body_" + prefix, weaponID: "weapon_" + prefix,
            activeWeaponSides: katana ? ["right"] : ["left", "right"],
            roles: Dictionary(uniqueKeysWithValues: roles.map { ($0, prefix + "_" + $0) }),
            clips: roles.map(clip), comboLinks: nil)
    }
    return .init(schemaVersion: 1, previewFramesPerSecond: 30, sourceFramesPerSecond: nil, profiles: profiles)
}

/// Lifecycle test double only. Its explicit finish() bypasses GPU preparation
/// exclusively on the coordinator's DEBUG fixture path, never on the real loader.
@MainActor
private final class RoomIntegrationLoader: DuelNetworkRoomLoading {
    static let compatibility = DuelNetworkStartBarrier.Compatibility(
        rulesFingerprint: String(repeating: "a", count: 64), catalogFingerprint: String(repeating: "b", count: 64))
    let catalog = roomIntegrationCatalog()
    var pendingPreparation: DuelNetworkMatchPreparation?
    var isClosed = false
    var didChange: (@MainActor () -> Void)?
    var time: TimeInterval = 100
    var cancellations = 0
    var loads = 0
    var completion: DuelNetworkCombatCoordinator.PresentationCompletion?
    var savedSession: DuelSession?
    func makeCoordinator(transport: any DuelLobbyTransport) throws -> DuelNetworkCombatCoordinator {
        DuelNetworkCombatCoordinator(testingTransport: transport, compatibility: Self.compatibility,
            loader: { [weak self] _, completion in
                guard let self else { return }
                self.loads += 1
                completion(.success(.init(testingCompatibility: Self.compatibility, catalog: self.catalog,
                    makePresentation: { [weak self] barrier, callback in
                        guard let self, let config = barrier.committedConfiguration else { return }
                        do {
                            let game = DuelGame(hero: config.host.choice.hero, difficulty: config.difficulty,
                                mode: config.mode, seed: config.seed, opponentHero: config.guest.choice.hero,
                                weaponCatalog: self.catalog)
                            let session = try DuelSession(presentationFixture: game,
                                localFighterIndex: barrier.localPlayerID == barrier.hostID ? 0 : 1)
                            self.savedSession = session; self.completion = callback
                            self.pendingPreparation = try DuelNetworkMatchPreparation(testing: session) { _ in }
                            self.didChange?()
                        } catch { callback(.failure(error)) }
                    }, release: { [weak self] in self?.cancel() })))
            }, cancelLoading: { [weak self] in self?.cancel() }, now: { [weak self] in self?.time ?? 100 })
    }
    func finish() {
        guard let session = savedSession else { return }
        // Production completes this only from its exact receipt checks.
        completion?(.success(session))
    }
    func cancel() {
        guard !isClosed else { return }
        isClosed = true; cancellations += 1
        let mount = pendingPreparation; pendingPreparation = nil
        mount?.cancel(); didChange?()
    }
}

@MainActor
private final class RoomIntegrationPair {
    let h = RoomIntegrationTransport(local: "z-host")
    let g = RoomIntegrationTransport(local: "a-guest")
    let hl = RoomIntegrationLoader()
    let gl = RoomIntegrationLoader()
    var hostLeaves = 0
    var guestLeaves = 0
    var hostStarts = 0
    var guestStarts = 0
    lazy var host = DuelNetworkRoomModel(testingTransport: h,
        start: { [weak self] in self?.hostStarts += 1 }, leave: { [weak self] in self?.hostLeaves += 1 },
        preflight: { [hl] in hl })
    lazy var guest = DuelNetworkRoomModel(testingTransport: g,
        start: { [weak self] in self?.guestStarts += 1 }, leave: { [weak self] in self?.guestLeaves += 1 },
        preflight: { [gl] in gl })
    init() { h.peer = g; g.peer = h }
    func begin() async {
        guest.begin(); host.begin()
        for _ in 0..<30 where host.state == .preparing || guest.state == .preparing { await Task.yield() }
    }
    func select() {
        host.selection?.choose(.sun); guest.selection?.choose(.liu)
        host.selection?.toggleReady(); guest.selection?.toggleReady()
    }
    func close() { host.close(); guest.close() }
}

@MainActor
extension DuelLifecycleTests {
    func testNetworkRoomExplicitEntryPreflightsBeforeTransportAndClaimsOneRoot() async {
        let pair = RoomIntegrationPair(); defer { pair.close() }
        XCTAssertEqual(pair.host.state, .idle)
        XCTAssertEqual(pair.hostStarts, 0); XCTAssertEqual(pair.h.claims, 0)
        pair.host.begin()
        XCTAssertEqual(pair.host.state, .preparing)
        XCTAssertEqual(pair.hostStarts, 0); XCTAssertNil(pair.host.selection)
        pair.guest.begin()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(pair.host.state, .selecting); XCTAssertEqual(pair.guest.state, .selecting)
        XCTAssertEqual(pair.h.claims, 1); XCTAssertEqual(pair.g.claims, 1)
        XCTAssertEqual(pair.hostStarts, 1); XCTAssertEqual(pair.guestStarts, 1)
        pair.host.begin(); pair.host.roomChanged()
        XCTAssertEqual(pair.h.claims, 1); XCTAssertEqual(pair.hostStarts, 1)
    }

    func testNetworkRoomPreflightFailureNeverStartsTransportOrOfflineSession() async {
        enum Broken: Error { case preflight }
        let transport = RoomIntegrationTransport(local: "z-host")
        var starts = 0, leaves = 0
        let owner = DuelNetworkRoomModel(testingTransport: transport, start: { starts += 1 },
            leave: { leaves += 1 }, preflight: { throw Broken.preflight })
        owner.begin()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(owner.state, .closed); XCTAssertNotNil(owner.error)
        XCTAssertEqual(starts, 0); XCTAssertEqual(leaves, 1); XCTAssertEqual(transport.claims, 0)
        XCTAssertNil(owner.coordinator); XCTAssertNil(owner.pendingPreparation)
    }

    func testNetworkRoomCloseBeforePreflightKeepsLaterTaskInert() async {
        let transport = RoomIntegrationTransport(local: "z-host"), loader = RoomIntegrationLoader()
        var starts = 0, calls = 0, leaves = 0
        let owner = DuelNetworkRoomModel(testingTransport: transport, start: { starts += 1 },
            leave: { leaves += 1 }, preflight: { calls += 1; return loader })
        owner.begin(); owner.close(); owner.close(); owner.begin()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(owner.state, .closed); XCTAssertEqual(calls, 0)
        XCTAssertEqual(starts, 0); XCTAssertEqual(leaves, 1); XCTAssertNil(transport.owner)
    }

    func testNetworkRoomRechecksForegroundAfterSynchronousPreflight() async {
        let transport = RoomIntegrationTransport(local: "z-host"), loader = RoomIntegrationLoader()
        var foreground = true, starts = 0, leaves = 0
        let owner = DuelNetworkRoomModel(testingTransport: transport, start: { starts += 1 },
            leave: { leaves += 1 }, foreground: { foreground },
            preflight: { foreground = false; return loader })
        owner.begin()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(owner.state, .closed); XCTAssertEqual(starts, 0); XCTAssertEqual(leaves, 1)
        XCTAssertEqual(loader.cancellations, 1); XCTAssertEqual(transport.claims, 0)
    }

    func testNetworkRoomReentrantPreflightCloseDropsReturnedResources() async {
        let transport = RoomIntegrationTransport(local: "z-host"), loader = RoomIntegrationLoader()
        var owner: DuelNetworkRoomModel?
        var starts = 0, leaves = 0
        owner = DuelNetworkRoomModel(testingTransport: transport, start: { starts += 1 },
            leave: { leaves += 1 }, preflight: { owner?.close(); return loader })
        owner?.begin()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(owner?.state, .closed); XCTAssertEqual(starts, 0); XCTAssertEqual(leaves, 1)
        XCTAssertEqual(loader.cancellations, 1)
        owner = nil
    }

    func testNetworkRoomHostOfferFollowsSettledStartedSnapshotAndMountPrecedesReady() async throws {
        let pair = RoomIntegrationPair(); defer { pair.close() }
        await pair.begin(); pair.select()
        let host = try XCTUnwrap(pair.host.coordinator), guest = try XCTUnwrap(pair.guest.coordinator)
        pair.host.startSelection()
        XCTAssertEqual(host.lobby.status, .started); XCTAssertEqual(guest.lobby.status, .started)
        XCTAssertEqual(pair.hl.loads, 1); XCTAssertEqual(pair.gl.loads, 1)
        let packets = pair.h.packets
        let started = try XCTUnwrap(packets.firstIndex { data in
            guard let envelope = try? JSONDecoder().decode(DuelNetworkLobby.Envelope.self, from: data),
                  case .snapshot(let value, _) = envelope.body else { return false }
            return value.phase == .started
        })
        let offer = try XCTUnwrap(packets.firstIndex { data in
            guard let message = try? JSONDecoder().decode(DuelNetworkStartBarrier.Message.self, from: data) else { return false }
            if case .offer = message.command { return true }; return false
        })
        XCTAssertLessThan(started, offer)
        XCTAssertEqual(pair.host.state, .mounting); XCTAssertEqual(pair.guest.state, .mounting)
        let mount = try XCTUnwrap(pair.host.pendingPreparation)
        XCTAssertTrue(mount.session.paused); XCTAssertNil(host.presentation); XCTAssertNil(guest.presentation)
        XCTAssertEqual(host.host?.nextTick, 0)
        pair.host.startSelection(); XCTAssertEqual(pair.hl.loads, 1)
        pair.hl.finish()
        XCTAssertEqual(host.state, .awaitingPresentation)
        pair.gl.finish()
        XCTAssertEqual(host.state, .running); XCTAssertEqual(guest.state, .running)
        XCTAssertTrue(host.presentation === mount.session)
        XCTAssertTrue(pair.host.pendingPreparation === mount, "Readiness must not replace the mounted view/session")
        mount.session.weaponDirection(x: 1, y: 0)
        guest.presentation?.weaponDirection(x: -1, y: 0)
        for _ in 0..<12 {
            pair.hl.time += 1.0 / 60; pair.gl.time += 1.0 / 60
            host.service(); guest.service()
        }
        let frames = pair.h.packets.compactMap {
            try? JSONDecoder().decode(DuelNetworkCombatProtocol.Message.self, from: $0)
        }.flatMap { message -> [DuelNetworkCombatProtocol.Frame] in
            if case .frames(let frames) = message.command { return frames }; return []
        }
        XCTAssertTrue(frames.contains { $0.tick >= DuelNetworkCombatCoordinator.inputLead &&
            $0.host.move == 1 && $0.guest.move == -1 }, "Consume both physical mailboxes after input lead")
        XCTAssertEqual(host.host?.game, guest.replay?.game)
        XCTAssertEqual(host.presentation?.game, guest.presentation?.game)
        XCTAssertEqual(host.presentation?.nextPresentationTick, 12)
    }

    func testNetworkRoomHostedInlineTransitionDoesNotLeaveOwningScreen() async throws {
        guard DuelWeaponAssets.catalogURL() != nil else { throw XCTSkip("Hosted combat requires approved fighter originals") }
        // A procedural equipped fixture lacks the original effect owners. Use
        // the real path here instead of accepting a failed synthetic mount.
        let hp = try DuelNetworkCompatibilityIdentity.prepare()
        defer { hp.release() }
        let gp = try DuelNetworkCompatibilityIdentity.prepare()
        defer { gp.release() }
        // This test intentionally leaves the guest unmounted. It tests screen
        // ownership, not whether an overloaded simulator prepares within the
        // production 15-second handshake deadline. Keep real verified loading
        // and GPU receipts; only the coordinator clock is controlled.
        let clock = RoomIntegrationClock()
        let hl = DuelNetworkPresentationLoader(testingPrepared: hp, now: { clock.time })
        let gl = DuelNetworkPresentationLoader(testingPrepared: gp, now: { clock.time })
        let h = RoomIntegrationTransport(local: "z-host"), g = RoomIntegrationTransport(local: "a-guest")
        h.peer = g; g.peer = h
        var leaves = 0
        let host = DuelNetworkRoomModel(testingTransport: h, leave: { leaves += 1 }, preflight: { hl })
        let guest = DuelNetworkRoomModel(testingTransport: g, leave: {}, preflight: { gl })
        let displayedRoom = GameRoom(kind: .fighter, mode: .nearbyHost, name: "UI fixture", capacity: 2)
        let hosting = UIHostingController(rootView: DuelNetworkRoomView(testing: displayedRoom, owner: host)
            .environment(\.scenePhase, .active))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 956, height: 440))
        window.rootViewController = hosting; hosting.view.frame = window.bounds
        defer { host.close(); guest.close(); window.isHidden = true; window.rootViewController = nil }
        window.makeKeyAndVisible(); hosting.view.layoutIfNeeded(); guest.begin()
        for _ in 0..<100 where host.state != .selecting || guest.state != .selecting {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(host.state, .selecting); XCTAssertEqual(leaves, 0)
        let hostCoordinator = try XCTUnwrap(host.coordinator)
        let guestCoordinator = try XCTUnwrap(guest.coordinator)
        host.selection?.choose(.sun); guest.selection?.choose(.liu)
        let started = ProcessInfo.processInfo.systemUptime
        host.selection?.toggleReady(); guest.selection?.toggleReady(); host.startSelection()
        let mount = try XCTUnwrap(host.pendingPreparation)
        let mounted = expectation(description: "Hosted room mounts and genuinely prepares original combat")
        var fulfilled = false
        func observeMount() {
            guard !fulfilled else { return }
            switch mount.state {
            case .prepared, .failed, .cancelled: fulfilled = true; mounted.fulfill()
            default: break
            }
        }
        let observation = mount.objectWillChange.sink { observeMount() }
        defer { observation.cancel() }
        hosting.view.setNeedsLayout(); hosting.view.layoutIfNeeded(); observeMount()
        await fulfillment(of: [mounted], timeout: 20)
        guard case .prepared(let receipt) = mount.state else {
            return XCTFail("Hosted combat must prepare: mount=\(mount.state), " +
                "host=\(String(describing: hostCoordinator.failure)), guest=\(String(describing: guestCoordinator.failure)), " +
                "elapsed=\(ProcessInfo.processInfo.systemUptime - started), room=\(host.error ?? "none")")
        }
        XCTAssertFalse(mount.permitsFixture)
        XCTAssertTrue(receipt.verifiedResourceOwnershipComplete)
        XCTAssertEqual(host.state, .mounting, "Guest has deliberately not mounted yet")
        XCTAssertTrue(host.pendingPreparation === mount)
        XCTAssertEqual(leaves, 0, "Selection disappearance is not room disappearance")
        XCTAssertNotNil(h.owner); XCTAssertEqual(h.claims, 1)
        host.close(reason: "Fixture disconnect remains visible")
        for _ in 0..<5 {
            hosting.view.setNeedsLayout(); hosting.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(host.error, "Fixture disconnect remains visible")
        XCTAssertTrue(window.rootViewController === hosting)
        XCTAssertEqual(leaves, 1); XCTAssertNil(h.owner)
    }

    func testVerifiedRoomClockExpiryCancelsPendingMountAndIgnoresLateRendererCompletion() async throws {
        guard DuelWeaponAssets.catalogURL() != nil else { throw XCTSkip("Clocked preparation requires approved fighter originals") }
        let hp = try DuelNetworkCompatibilityIdentity.prepare()
        defer { hp.release() }
        let gp = try DuelNetworkCompatibilityIdentity.prepare()
        defer { gp.release() }
        let clock = RoomIntegrationClock()
        let hl = DuelNetworkPresentationLoader(testingPrepared: hp, now: { clock.time })
        let gl = DuelNetworkPresentationLoader(testingPrepared: gp, now: { clock.time })
        let h = RoomIntegrationTransport(local: "z-host"), g = RoomIntegrationTransport(local: "a-guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkRoomModel(testingTransport: h, leave: {}, preflight: { hl })
        let guest = DuelNetworkRoomModel(testingTransport: g, leave: {}, preflight: { gl })
        defer { host.close(); guest.close() }
        host.begin(); guest.begin()
        for _ in 0..<100 where host.state != .selecting || guest.state != .selecting { await Task.yield() }
        XCTAssertEqual(host.state, .selecting); XCTAssertEqual(guest.state, .selecting)
        host.selection?.choose(.sun); guest.selection?.choose(.liu)
        host.selection?.toggleReady(); guest.selection?.toggleReady(); host.startSelection()
        let coordinator = try XCTUnwrap(host.coordinator), mount = try XCTUnwrap(host.pendingPreparation)
        XCTAssertFalse(mount.permitsFixture)
        let world = DuelWorldView(session: mount.session)
        var finish: (@MainActor (Bool) -> Void)?
        // A delayed preparation callback is used only to prove that expiry
        // cannot be undone. It never supplies a successful readiness receipt.
        world.testingPrepare = { _, callback in finish = callback }
        mount.attach(world)
        let controls = DuelNetworkControlsView(preparation: mount)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 956, height: 440))
        let controller = UIViewController(); window.rootViewController = controller
        controller.view.frame = window.bounds; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; world.shutdown() }
        for view in [world as UIView, controls] {
            view.frame = window.bounds; controller.view.addSubview(view); view.setNeedsLayout(); view.layoutIfNeeded()
        }
        XCTAssertNotNil(finish)
        XCTAssertEqual(coordinator.state, .awaitingPresentation)
        clock.time += DuelNetworkCombatCoordinator.handshakeTimeout
        coordinator.service()
        XCTAssertEqual(coordinator.failure, .handshakeTimeout)
        XCTAssertEqual(mount.state, .cancelled)
        XCTAssertTrue(hp.isReleased); XCTAssertTrue(gp.isReleased)
        finish?(true); finish?(false)
        XCTAssertEqual(coordinator.state, .closed)
        XCTAssertNil(coordinator.presentation)
        XCTAssertTrue(mount.session.paused)
        XCTAssertNil(mount.session.preparedResources)
        XCTAssertNil(world.scene)
        XCTAssertEqual(host.state, .closed); XCTAssertEqual(guest.state, .closed)
        XCTAssertNil(h.owner); XCTAssertNil(g.owner)
    }

    func testNetworkRoomSelectionCloseReasonPublicationCannotRecurse() {
        let transport = RoomIntegrationTransport(local: "z-host")
        let model = DuelNetworkSelectionModel(transport: transport)
        var publications = 0
        let observation = model.$error.sink { reason in
            guard let reason else { return }
            publications += 1
            model.close(reason: reason)
        }
        model.close(reason: "First close")
        XCTAssertEqual(model.status, .closed); XCTAssertEqual(model.error, "First close")
        model.close(reason: "Updated reason")
        XCTAssertEqual(model.error, "Updated reason"); XCTAssertEqual(publications, 2)
        XCTAssertEqual(transport.claims, 0); XCTAssertEqual(transport.releases, 0)
        withExtendedLifetime(observation) {}
    }

    func testNetworkRoomBorrowedSelectionDoesNotAttachOrOwnSharedRoot() async throws {
        let pair = RoomIntegrationPair(); defer { pair.close() }
        await pair.begin()
        let selection = try XCTUnwrap(pair.host.selection)
        selection.attach(localID: "wrong")
        XCTAssertEqual(selection.localID, "z-host"); XCTAssertEqual(pair.h.claims, 1)
        let coordinator = try XCTUnwrap(pair.host.coordinator)
        selection.close(reason: "cancelled by selection")
        XCTAssertEqual(pair.host.state, .closed); XCTAssertEqual(coordinator.state, .closed)
        XCTAssertEqual(pair.h.releases, 1); XCTAssertEqual(pair.hostLeaves, 1)
    }

    func testNetworkRoomBorrowedPendingTimeoutClosesWholeRoom() async throws {
        let h = RoomIntegrationTransport(local: "z-host"), g = RoomIntegrationTransport(local: "a-guest")
        h.peer = g; g.peer = h
        let hl = RoomIntegrationLoader(), gl = RoomIntegrationLoader()
        var leaves = 0
        let host = DuelNetworkRoomModel(testingTransport: h, leave: {}, preflight: { hl })
        let guest = DuelNetworkRoomModel(testingTransport: g, leave: { leaves += 1 },
            selectionTimeout: 1_000_000, preflight: { gl })
        defer { host.close(); guest.close() }
        guest.begin(); host.begin()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(guest.selection?.status, .selecting)
        g.drop = true; guest.selection?.choose(.liu)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(guest.state, .closed); XCTAssertEqual(leaves, 1)
        XCTAssertNil(g.owner); XCTAssertEqual(gl.cancellations, 1)
    }

    func testNetworkRoomMembershipReplacementAndInterruptAreTerminal() async throws {
        for replaceMembership in [false, true] {
            let pair = RoomIntegrationPair(); defer { pair.close() }
            await pair.begin(); pair.select(); pair.host.startSelection()
            let old = try XCTUnwrap(pair.host.coordinator), pending = try XCTUnwrap(pair.host.pendingPreparation)
            if replaceMembership {
                pair.h.state = .init(isFighter: true, capacity: 2, ready: true, localID: "z-host",
                                     hostID: "z-host", members: ["z-host", "replacement"])
                pair.host.roomChanged()
            } else { pair.host.interrupt() }
            pair.host.close(); pair.host.begin(); pair.hl.finish()
            XCTAssertEqual(pair.host.state, .closed); XCTAssertEqual(old.state, .closed)
            XCTAssertNil(pair.host.pendingPreparation); XCTAssertEqual(pending.state, .cancelled)
            XCTAssertEqual(pair.hostLeaves, 1); XCTAssertEqual(pair.h.releases, 1)
            XCTAssertEqual(pair.hl.cancellations, 1)
            if replaceMembership {
                XCTAssertTrue(pair.host.error?.contains("连接已中断") == true,
                              "Loader teardown must not erase the coordinator's terminal reason")
            }
        }
    }

    func testNetworkRoomLateOldCallbacksCannotClaimNewOwner() async throws {
        let pair = RoomIntegrationPair(); await pair.begin(); pair.select(); pair.host.startSelection()
        let oldReceive = pair.h.receive, oldChanged = pair.h.changed
        let stalePacket = try XCTUnwrap(pair.g.packets.last)
        pair.close()
        let fresh = RoomIntegrationLoader()
        let next = DuelNetworkRoomModel(testingTransport: pair.h, leave: {}, preflight: { fresh })
        defer { next.close() }
        next.begin()
        for _ in 0..<30 { await Task.yield() }
        let lease = pair.h.owner
        oldReceive?(stalePacket, "a-guest"); oldChanged?(); pair.hl.finish(); pair.host.close()
        XCTAssertEqual(pair.h.owner, lease); XCTAssertNotNil(lease)
        XCTAssertEqual(next.state, .selecting); XCTAssertEqual(fresh.cancellations, 0)
    }

    func testNetworkRoomStateObserverCanCloseWithoutStartingTransport() async {
        let transport = RoomIntegrationTransport(local: "z-host"), loader = RoomIntegrationLoader()
        var starts = 0, leaves = 0
        let owner = DuelNetworkRoomModel(testingTransport: transport, start: { starts += 1 },
            leave: { leaves += 1 }, preflight: { loader })
        let observation = owner.objectWillChange.sink {
            if owner.state == .connecting { owner.close() }
        }
        owner.begin()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(owner.state, .closed); XCTAssertEqual(starts, 0); XCTAssertEqual(leaves, 1)
        XCTAssertEqual(loader.cancellations, 1)
        withExtendedLifetime(observation) {}
    }

    func testNetworkRoomCoordinatorClosedCallbackSeesCompletedCleanup() async throws {
        let pair = RoomIntegrationPair(); defer { pair.close() }
        await pair.begin(); pair.select(); pair.host.startSelection()
        let combat = try XCTUnwrap(pair.host.coordinator)
        // Stop root recursion to inspect the coordinator's own post-transition callback.
        pair.hl.didChange = nil
        var closed = 0
        combat.didChange = {
            if combat.state == .closed {
                closed += 1
                XCTAssertNil(pair.h.owner); XCTAssertEqual(pair.hl.cancellations, 1)
                XCTAssertNil(pair.hl.pendingPreparation)
                combat.close()
            }
        }
        combat.close()
        XCTAssertEqual(closed, 1)
        combat.didChange = nil
    }

    func testNetworkRoomRemotePathRemainsSelectionOnlyAndSkipsPreflight() async {
        let h = RoomIntegrationTransport(local: "z-host"), g = RoomIntegrationTransport(local: "a-guest")
        h.peer = g; g.peer = h
        var preflights = 0
        let host = DuelNetworkRoomModel(testingTransport: h, nearbyCombat: false, leave: {},
            preflight: { preflights += 1; return RoomIntegrationLoader() })
        let guest = DuelNetworkRoomModel(testingTransport: g, nearbyCombat: false, leave: {},
            preflight: { preflights += 1; return RoomIntegrationLoader() })
        defer { host.close(); guest.close() }
        guest.begin(); host.begin()
        for _ in 0..<30 { await Task.yield() }
        host.selection?.choose(.sun); guest.selection?.choose(.liu)
        host.selection?.toggleReady(); guest.selection?.toggleReady(); host.startSelection()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(host.state, .selectionComplete); XCTAssertEqual(guest.state, .selectionComplete)
        XCTAssertEqual(preflights, 0); XCTAssertNil(host.coordinator); XCTAssertNil(guest.pendingPreparation)
    }

    func testNetworkRoomProductionLoaderMountsExactOriginalsBeforeCoordinatorReadiness() async throws {
        guard DuelWeaponAssets.catalogURL() != nil else { throw XCTSkip("Approved fighter originals are not installed") }
        // Both expensive synchronous preflights finish before either transport or
        // handshake deadline starts. This path never supplies testingPrepare.
        let hp = try DuelNetworkCompatibilityIdentity.prepare()
        defer { hp.release() }
        let gp = try DuelNetworkCompatibilityIdentity.prepare()
        defer { gp.release() }
        let hl = DuelNetworkPresentationLoader(prepared: hp), gl = DuelNetworkPresentationLoader(prepared: gp)
        let h = RoomIntegrationTransport(local: "z-host"), g = RoomIntegrationTransport(local: "a-guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkRoomModel(testingTransport: h, leave: {}, preflight: { hl })
        let guest = DuelNetworkRoomModel(testingTransport: g, leave: {}, preflight: { gl })
        defer { host.close(); guest.close() }
        guest.begin(); host.begin()
        for _ in 0..<30 { await Task.yield() }
        host.selection?.choose(.sun); guest.selection?.choose(.liu)
        host.selection?.toggleReady(); guest.selection?.toggleReady(); host.startSelection()
        let hc = try XCTUnwrap(host.coordinator), gc = try XCTUnwrap(guest.coordinator)
        let hm = try XCTUnwrap(host.pendingPreparation), gm = try XCTUnwrap(guest.pendingPreparation)
        XCTAssertNil(hc.presentation); XCTAssertNil(gc.presentation)
        XCTAssertTrue(hm.session.preparedResources === hp); XCTAssertTrue(gm.session.preparedResources === gp)
        XCTAssertTrue(hm.session.paused); XCTAssertTrue(gm.session.paused)
        let windows = [UIWindow(frame: CGRect(x: 0, y: 0, width: 956, height: 440)),
                       UIWindow(frame: CGRect(x: 0, y: 0, width: 956, height: 440))]
        defer { windows.forEach { $0.isHidden = true } }
        let completed = expectation(description: "Both production room endpoints reach actual renderer readiness")
        var fulfilled = false
        func observe() {
            guard !fulfilled else { return }
            if (host.state == .running && guest.state == .running) || host.state == .closed || guest.state == .closed {
                fulfilled = true; completed.fulfill()
            }
        }
        let hs = host.objectWillChange.sink { observe() }, gs = guest.objectWillChange.sink { observe() }
        defer { hs.cancel(); gs.cancel() }
        var worlds: [DuelWorldView] = [], controls: [DuelNetworkControlsView] = []
        for (index, mount) in [hm, gm].enumerated() {
            let window = windows[index]
            window.rootViewController = UIViewController()
            window.rootViewController?.view.frame = window.bounds; window.makeKeyAndVisible()
            let world = DuelWorldView(session: mount.session)
            mount.attach(world)
            let control = DuelNetworkControlsView(preparation: mount)
            worlds.append(world); controls.append(control)
            for view in [world as UIView, control as UIView] {
                view.frame = window.bounds; window.rootViewController?.view.addSubview(view)
                view.setNeedsLayout(); view.layoutIfNeeded()
            }
        }
        observe()
        await fulfillment(of: [completed], timeout: 20)
        XCTAssertEqual(host.state, .running); XCTAssertEqual(guest.state, .running)
        XCTAssertTrue(hc.presentation === hm.session); XCTAssertTrue(gc.presentation === gm.session)
        XCTAssertTrue(host.pendingPreparation === hm); XCTAssertTrue(guest.pendingPreparation === gm)
        for (index, resources) in [hp, gp].enumerated() {
            let mount = index == 0 ? hm : gm
            guard case .prepared(let receipt) = mount.state else { XCTFail("Expected real verified mount"); continue }
            XCTAssertTrue(receipt.verifiedResourceOwnershipComplete)
            XCTAssertTrue(worlds[index].usedActualScenePreparation)
            XCTAssertTrue(worlds[index].stageAsset === resources.stage)
            XCTAssertTrue(worlds[index].sourceEffects === resources.sourceEffects)
            XCTAssertTrue(worlds[index].weaponEffects === resources.weaponEffects)
            XCTAssertTrue(controls[index].controls === resources.controls)
        }
        // Exercise the retained source controls' actual pointer/binding path,
        // then consume enough authoritative ticks to pass the four-tick lead.
        for (index, container) in controls.enumerated() {
            container.refreshReadiness()
            XCTAssertTrue(container.controls.inputEnabled)
            let stick = container.controls.layoutSnapshot.joystick
            container.controls.beginPointers([.init(id: index, location: CGPoint(
                x: stick.midX + stick.width * (index == 0 ? 0.35 : -0.35), y: stick.midY))])
        }
        for _ in 0..<12 { hc.service(); gc.service() }
        let frames = h.packets.compactMap {
            try? JSONDecoder().decode(DuelNetworkCombatProtocol.Message.self, from: $0)
        }.flatMap { message -> [DuelNetworkCombatProtocol.Frame] in
            if case .frames(let frames) = message.command { return frames }; return []
        }
        XCTAssertTrue(frames.contains { $0.host.move == 1 && $0.guest.move == -1 })
        XCTAssertEqual(hc.host?.game, gc.replay?.game)
        XCTAssertEqual(hm.session.game, gm.session.game)
        controls.enumerated().forEach { index, view in view.controls.endPointers([index]) }
        host.close(); guest.close()
        XCTAssertTrue(hp.isReleased); XCTAssertTrue(gp.isReleased)
        XCTAssertNil(h.owner); XCTAssertNil(g.owner)
    }

    func testNetworkRoomProductionPreflightOwnerCancelsBeforeTransportWhenOriginalsExist() async throws {
        guard DuelWeaponAssets.catalogURL() != nil else { throw XCTSkip("Approved fighter originals are not installed") }
        let prepared = try DuelNetworkCompatibilityIdentity.prepare()
        let loader = DuelNetworkPresentationLoader(prepared: prepared)
        let transport = RoomIntegrationTransport(local: "z-host")
        var starts = 0, foreground = true
        let room = DuelNetworkRoomModel(testingTransport: transport, start: { starts += 1 }, leave: {},
            foreground: { foreground }, preflight: { foreground = false; return loader })
        room.begin()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(room.state, .closed); XCTAssertEqual(starts, 0)
        XCTAssertTrue(prepared.isReleased); XCTAssertTrue(loader.isClosed)
    }
}
#endif
