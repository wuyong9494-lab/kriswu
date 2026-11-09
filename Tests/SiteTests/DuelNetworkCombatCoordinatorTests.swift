import Foundation
import XCTest
@testable import ShiftReminder

#if DEBUG
@MainActor
private final class CombatMemoryTransport: DuelLobbyTransport {
    var state: DuelLobbyRoomState
    var owner: UUID?
    var receive: ((Data, String) -> Void)?
    var changed: (() -> Void)?
    var packets: [Data] = []
    var drop: ((Data) -> Bool)?
    var releases = 0
    weak var peer: CombatMemoryTransport?
    init(local: String) {
        // Intentionally not lexical seat order.
        state = .init(isFighter: true, capacity: 2, ready: true,
                      localID: local, hostID: "z-host", members: ["a-guest", "z-host"])
    }
    func claim(_ owner: UUID, receive: @escaping (Data, String) -> Void,
               changed: @escaping () -> Void) -> Bool {
        guard self.owner == nil else { return false }
        self.owner = owner; self.receive = receive; self.changed = changed
        return true
    }
    func release(_ owner: UUID) {
        guard self.owner == owner else { return }
        releases += 1; self.owner = nil; receive = nil; changed = nil
    }
    func sendReliable(_ data: Data) {
        packets.append(data)
        if drop?(data) != true { peer?.receive?(data, state.localID) }
    }
}

@MainActor
private final class CombatTestTime { var value: TimeInterval = 100 }

@MainActor
private func combatCoordinatorCatalog() -> DuelWeaponCatalog {
    let profiles: [DuelWeaponProfile] = [DuelGame.Hero.ember, .liu].map { hero in
        let katana = hero == .ember, prefix = katana ? "katana" : "hammers"
        let zero = Array(repeating: DuelWeaponPoint(), count: 17)
        func clip(_ name: String) -> DuelWeaponClip {
            let base = (0..<17).map { DuelWeaponPoint(x: 0.2 + Double($0) / 20, y: 1) }
            let tip = (0..<17).map { DuelWeaponPoint(x: 0.7 + Double($0) / 20, y: 1) }
            return .init(name: prefix + "_" + name, frames: 9, sha256: String(repeating: "c", count: 64),
                         bundle: "synthetic-coordinator-test", tracks: .init(
                            samplesPerSourceFrame: 2, root: zero, handL: zero, handR: zero,
                            footL: zero, footR: zero, weaponBaseL: katana ? [] : base,
                            weaponTipL: katana ? [] : tip, weaponBaseR: base, weaponTipR: tip,
                            groundLift: Array(repeating: 0, count: 17)))
        }
        let roles = ["idle", "walkForward", "walkBackward", "guard", "hit", "knockdown", "getUp",
                     "jump", "weapon1", "heavy", "kick"]
        return .init(id: katana ? "sun_katana" : "liu_hammers", hero: hero,
                     faction: prefix, resourceName: "Synthetic_" + prefix, bytes: 128,
                     sha256: String(repeating: katana ? "a" : "b", count: 64),
                     bodyID: "body_" + prefix, weaponID: "weapon_" + prefix,
                     activeWeaponSides: katana ? ["right"] : ["left", "right"],
                     roles: Dictionary(uniqueKeysWithValues: roles.map { ($0, prefix + "_" + $0) }),
                     clips: roles.map(clip), comboLinks: nil)
    }
    return .init(schemaVersion: 1, previewFramesPerSecond: 30, sourceFramesPerSecond: nil, profiles: profiles)
}

@MainActor
private final class CombatTestLoader {
    typealias Coordinator = DuelNetworkCombatCoordinator
    static let expectedCompatibility = DuelNetworkStartBarrier.Compatibility(
        rulesFingerprint: String(repeating: "a", count: 64), catalogFingerprint: String(repeating: "b", count: 64))
    var catalog = combatCoordinatorCatalog()
    var compatibility = CombatTestLoader.expectedCompatibility
    var autoLoad = true
    var autoPresent = true
    var loads = 0
    var released = 0
    var cancelled = 0
    var completion: Coordinator.Completion?
    var presentationCompletion: Coordinator.PresentationCompletion?
    var committed: DuelNetworkStartBarrier?
    var session: DuelSession?
    var receipt: Coordinator.Resources?
    func load(_ configuration: Coordinator.Configuration, completion: @escaping Coordinator.Completion) {
        loads += 1; self.completion = completion
        if autoLoad { finishLoad() }
    }
    func finishLoad() {
        let receipt = Coordinator.Resources(testingCompatibility: compatibility, catalog: catalog,
            makePresentation: { [weak self] barrier, callback in
                guard let self else { return }
                self.committed = barrier; self.presentationCompletion = callback
                if self.autoPresent { self.finishPresentation() }
            }, release: { [weak self] in self?.released += 1 })
        self.receipt = receipt
        completion?(.success(receipt))
    }
    func finishPresentation() {
        guard let barrier = committed, let config = barrier.committedConfiguration else {
            XCTFail("Fixture requires the endpoint's committed barrier"); return
        }
        do {
            let game = DuelGame(hero: config.host.choice.hero, difficulty: config.difficulty, mode: config.mode,
                                seed: config.seed, opponentHero: config.guest.choice.hero, weaponCatalog: catalog)
            let session = try DuelSession(presentationFixture: game,
                                          localFighterIndex: barrier.localPlayerID == barrier.hostID ? 0 : 1)
            self.session = session; presentationCompletion?(.success(session))
        } catch { presentationCompletion?(.failure(error)) }
    }
}

@MainActor
private final class CombatPair {
    let hostTransport: CombatMemoryTransport
    let guestTransport: CombatMemoryTransport
    let hostLoader: CombatTestLoader
    let guestLoader: CombatTestLoader
    let time: CombatTestTime
    let host: DuelNetworkCombatCoordinator
    let guest: DuelNetworkCombatCoordinator
    init() {
        let h = CombatTestLoader(), g = CombatTestLoader(), clock = CombatTestTime()
        let ht = CombatMemoryTransport(local: "z-host"), gt = CombatMemoryTransport(local: "a-guest")
        hostLoader = h; guestLoader = g; time = clock; hostTransport = ht; guestTransport = gt
        host = .init(testingTransport: ht, compatibility: CombatTestLoader.expectedCompatibility,
                     loader: { h.load($0, completion: $1) }, cancelLoading: { h.cancelled += 1 }, now: { clock.value })
        guest = .init(testingTransport: gt, compatibility: CombatTestLoader.expectedCompatibility,
                      loader: { g.load($0, completion: $1) }, cancelLoading: { g.cancelled += 1 }, now: { clock.value })
        hostTransport.peer = guestTransport; guestTransport.peer = hostTransport
    }
    func select(hostChoice: DuelMultiplayerSelection.Choice = .sun) throws {
        try guest.attach(); try host.attach()
        XCTAssertEqual(host.state, .selecting); XCTAssertEqual(guest.state, .selecting)
        XCTAssertTrue(host.lobby.submit(.select(hostChoice)))
        XCTAssertTrue(guest.lobby.submit(.select(hostChoice == .sun ? .liu : .sun)))
        let revision = try XCTUnwrap(host.lobby.snapshot?.selectionRevision)
        XCTAssertTrue(host.lobby.submit(.ready(true, selectionRevision: revision)))
        XCTAssertTrue(guest.lobby.submit(.ready(true, selectionRevision: revision)))
        XCTAssertTrue(host.lobby.submit(.start(selectionRevision: revision)))
        XCTAssertEqual(host.state, .awaitingOffer); XCTAssertEqual(guest.state, .awaitingOffer)
    }
    func start(hostChoice: DuelMultiplayerSelection.Choice = .sun) throws {
        try select(hostChoice: hostChoice)
        try host.offer(startID: "start-one", seed: 739)
    }
    func tick(_ count: Int = 1) {
        for _ in 0..<count { time.value += 1.0 / 60; host.service(); guest.service() }
    }
    func close() { host.close(); guest.close() }
    var frames: [DuelNetworkCombatProtocol.Message] {
        hostTransport.packets.compactMap { try? JSONDecoder().decode(DuelNetworkCombatProtocol.Message.self, from: $0) }
    }
    func sendControl(_ control: DuelNetworkCombatCoordinator.Control.Command, toHost: Bool = true) throws {
        let config = try XCTUnwrap(host.configuration)
        let data = try JSONEncoder().encode(DuelNetworkCombatCoordinator.Control(configuration: config, control: control))
        if toHost { hostTransport.receive?(data, "a-guest") }
        else { guestTransport.receive?(data, "z-host") }
    }
}

/// Included in the existing native lifecycle CI selection. All resources and
/// transport here are synthetic; these cases do not prove live two-device play.
extension DuelLifecycleTests {
    func testCombatCoordinatorSelectionAndAllPhaseRegistrationPrecedeOffer() throws {
        let pair = CombatPair(); defer { pair.close() }
        XCTAssertNil(pair.hostTransport.owner)
        try pair.select()
        XCTAssertEqual(pair.hostLoader.loads, 0)
        XCTAssertNil(pair.host.host); XCTAssertNil(pair.guest.replay)
        for _ in 0..<20 { pair.host.service(); pair.guest.service() }
        XCTAssertNil(pair.host.presentation)
        try pair.host.offer(startID: "registered-before-offer", seed: 91)
        XCTAssertEqual(pair.host.state, .running); XCTAssertEqual(pair.guest.state, .running)
        XCTAssertEqual(pair.hostLoader.loads, 1); XCTAssertEqual(pair.guestLoader.loads, 1)
        XCTAssertThrowsError(try pair.host.offer(startID: "second", seed: 92))
        XCTAssertThrowsError(try pair.host.attach())
    }

    func testCombatCoordinatorHostFirstReplayAndPresentationBothHeroOrders() throws {
        for choice in [DuelMultiplayerSelection.Choice.sun, .liu] {
            let pair = CombatPair(); defer { pair.close() }
            try pair.start(hostChoice: choice)
            XCTAssertEqual(pair.host.presentation?.localFighterIndex, 0)
            XCTAssertEqual(pair.guest.presentation?.localFighterIndex, 1)
            XCTAssertEqual(pair.host.host?.game.fighters[0].hero, choice.hero)
            pair.host.presentation?.weaponDirection(x: 1, y: 0)
            pair.guest.presentation?.weaponDirection(x: -1, y: 0)
            var published: [UInt64] = []
            pair.guest.presentation?.didSimulateStep = { _, _ in
                published.append(pair.guest.presentation?.nextPresentationTick ?? 0)
            }
            pair.tick(90)
            XCTAssertEqual(pair.host.state, .running); XCTAssertEqual(pair.guest.state, .running)
            XCTAssertEqual(pair.host.host?.game, pair.guest.replay?.game)
            XCTAssertEqual(pair.host.presentation?.game, pair.host.host?.game)
            XCTAssertEqual(pair.guest.presentation?.game, pair.guest.replay?.game)
            XCTAssertEqual(published, (UInt64(1)...90).map { $0 })
            XCTAssertEqual(pair.host.presentation?.nextPresentationTick, 90)
            XCTAssertEqual(try pair.host.host?.verificationState(), try pair.guest.replay?.verificationState())
            let frames = pair.frames.flatMap { message -> [DuelNetworkCombatProtocol.Frame] in
                if case .frames(let frames) = message.command { return frames }; return []
            }
            XCTAssertTrue(frames.prefix(4).allSatisfy { $0.host.move == 0 && $0.guest.move == 0 })
            XCTAssertEqual(frames[4].host.move, 1)
            XCTAssertEqual(frames[5].guest.move, -1)
        }
    }

    func testCombatCoordinatorWaitsForLoadedResourcesAndRendererReadyCommitAck() throws {
        let pair = CombatPair(); defer { pair.close() }
        pair.guestLoader.autoLoad = false; pair.guestLoader.autoPresent = false
        try pair.start()
        XCTAssertEqual(pair.host.state, .loading); XCTAssertNil(pair.host.host)
        pair.tick(3)
        pair.guestLoader.finishLoad()
        XCTAssertEqual(pair.host.state, .awaitingPresentation)
        XCTAssertEqual(pair.guest.state, .awaitingPresentation)
        XCTAssertEqual(pair.host.host?.nextTick, 0)
        pair.tick(3)
        XCTAssertEqual(pair.host.host?.nextTick, 0)
        XCTAssertTrue(pair.host.presentation?.paused == true)
        pair.guestLoader.finishPresentation()
        XCTAssertEqual(pair.host.state, .running); XCTAssertEqual(pair.guest.state, .running)
        pair.tick()
        XCTAssertEqual(pair.guest.replay?.nextTick, 1)
    }

    func testCombatCoordinatorHostRendererMustAlsoBeReady() throws {
        let pair = CombatPair(); defer { pair.close() }
        pair.hostLoader.autoPresent = false
        try pair.start()
        XCTAssertEqual(pair.host.state, .awaitingPresentation)
        XCTAssertEqual(pair.guest.state, .running)
        pair.tick(180) // A valid host load may exceed the running peer timeout.
        XCTAssertEqual(pair.guest.state, .running)
        XCTAssertEqual(pair.host.host?.nextTick, 0); XCTAssertEqual(pair.guest.replay?.nextTick, 0)
        pair.hostLoader.finishPresentation()
        pair.tick()
        XCTAssertEqual(pair.host.state, .running); XCTAssertEqual(pair.guest.replay?.nextTick, 1)
    }

    func testCombatCoordinatorLostCommitAckNeverStartsHostClock() throws {
        let pair = CombatPair(); defer { pair.close() }
        pair.guestTransport.drop = { (try? JSONDecoder().decode(DuelNetworkCombatCoordinator.Control.self, from: $0)) != nil }
        try pair.start()
        XCTAssertEqual(pair.host.state, .awaitingPresentation)
        XCTAssertEqual(pair.host.host?.nextTick, 0)
        pair.time.value += DuelNetworkCombatCoordinator.handshakeTimeout
        pair.host.service()
        XCTAssertEqual(pair.host.failure, .handshakeTimeout)
        XCTAssertEqual(pair.host.host?.nextTick, 0)
    }

    func testCombatCoordinatorIncompatibleLoadNeverAcknowledgesOrConstructsCombat() throws {
        let pair = CombatPair(); defer { pair.close() }
        pair.guestLoader.compatibility = .init(rulesFingerprint: String(repeating: "c", count: 64),
                                               catalogFingerprint: String(repeating: "b", count: 64))
        try pair.start()
        XCTAssertEqual(pair.guest.failure, .incompatibleResources)
        XCTAssertEqual(pair.host.state, .closed)
        XCTAssertNil(pair.host.host); XCTAssertNil(pair.guest.replay)
        XCTAssertEqual(pair.guestLoader.released, 1)
    }

    func testCombatCoordinatorCancelledLoadCallbackCannotReopenOrLeakReceipt() throws {
        let pair = CombatPair(); defer { pair.close() }
        pair.guestLoader.autoLoad = false
        try pair.start()
        pair.guest.interrupt()
        pair.guestLoader.finishLoad()
        let receipt = try XCTUnwrap(pair.guestLoader.receipt)
        pair.guestLoader.completion?(.success(receipt))
        XCTAssertEqual(pair.guest.state, .closed); XCTAssertNil(pair.guest.presentation)
        XCTAssertEqual(pair.guestLoader.released, 1)
        XCTAssertEqual(pair.guestLoader.cancelled, 1)
    }

    func testCombatCoordinatorCancelledPresentationCallbackStaysTerminal() throws {
        let pair = CombatPair(); defer { pair.close() }
        pair.guestLoader.autoPresent = false
        try pair.start()
        pair.guest.close()
        pair.guestLoader.finishPresentation()
        let session = try XCTUnwrap(pair.guestLoader.session)
        XCTAssertThrowsError(try session.startAuthoritativePresentation())
        XCTAssertNil(pair.guest.presentation)
        XCTAssertEqual(pair.guestLoader.released, 1)
    }

    func testCombatCoordinatorInterruptionRejectsSavedTransportCallbacksAndLocalResume() throws {
        let pair = CombatPair(); defer { pair.close() }
        try pair.start(); pair.tick(6)
        let callback = try XCTUnwrap(pair.guestTransport.receive)
        let bytes = try XCTUnwrap(pair.frames.last).encoded()
        pair.guest.presentation?.pause()
        XCTAssertEqual(pair.guest.failure, .interrupted); XCTAssertEqual(pair.host.state, .closed)
        callback(bytes, "z-host")
        pair.tick(2)
        pair.guest.presentation?.resume(); pair.guest.presentation?.restart()
        XCTAssertEqual(pair.guest.replay?.nextTick, 6)
        XCTAssertEqual(pair.guest.presentation?.nextPresentationTick, 6)
        XCTAssertTrue(pair.guest.presentation?.paused == true)
        XCTAssertEqual(pair.guestTransport.releases, 1)
        XCTAssertEqual(pair.hostTransport.releases, 1)
    }

    func testCombatCoordinatorUnknownSenderAndStaleStartCannotAffectRunningGame() throws {
        let pair = CombatPair(); defer { pair.close() }
        try pair.start(); pair.tick()
        let config = try XCTUnwrap(pair.host.configuration)
        let cancel = try JSONEncoder().encode(DuelNetworkCombatCoordinator.Control(configuration: config, control: .cancel))
        pair.hostTransport.receive?(cancel, "intruder")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: cancel) as? [String: Any])
        object["startID"] = "retired-start"
        pair.hostTransport.receive?(try JSONSerialization.data(withJSONObject: object), "a-guest")
        XCTAssertEqual(pair.host.state, .running)
        let game = pair.host.host?.game
        try pair.sendControl(.input(.init(sessionID: config.sessionID, sequence: 9_000, tick: 5, move: 9)))
        XCTAssertEqual(pair.host.host?.game, game)
        XCTAssertEqual(pair.host.state, .running)
        pair.tick()
        XCTAssertEqual(pair.host.host?.game, pair.guest.replay?.game)
    }

    func testCombatCoordinatorDuplicateFrameDoesNotRepublishOrConsumeInput() throws {
        let pair = CombatPair(); defer { pair.close() }
        try pair.start(); pair.tick()
        let count = pair.guestTransport.packets.count
        let bytes = try XCTUnwrap(pair.frames.last).encoded()
        pair.guestTransport.receive?(bytes, "z-host")
        XCTAssertEqual(pair.guest.replay?.nextTick, 1)
        XCTAssertEqual(pair.guest.presentation?.nextPresentationTick, 1)
        XCTAssertEqual(pair.guestTransport.packets.count, count)
    }

    func testCombatCoordinatorRejectsSkippedOrBatchedPresentationBeforeReplayMutation() throws {
        for batched in [false, true] {
            let pair = CombatPair(); defer { pair.close() }
            try pair.start()
            let config = try XCTUnwrap(pair.host.configuration)
            let frames = (0..<(batched ? 2 : 1)).map {
                DuelNetworkCombatProtocol.Frame(tick: UInt64($0), host: .init(), guest: .init())
            }
            let message = DuelNetworkCombatProtocol.Message(sessionID: config.sessionID, startID: config.startID,
                sequence: batched ? 1 : 2, command: .frames(frames))
            pair.guestTransport.receive?(try message.encoded(), "z-host")
            XCTAssertEqual(pair.guest.failure, .protocolViolation)
            XCTAssertEqual(pair.guest.replay?.nextTick, 0)
            XCTAssertEqual(pair.guest.presentation?.nextPresentationTick, 0)
        }
    }

    func testCombatCoordinatorNoCatchupAfterClockStall() throws {
        let pair = CombatPair(); defer { pair.close() }
        try pair.start(); pair.tick()
        pair.time.value += DuelNetworkCombatCoordinator.maximumClockGap + 0.01
        pair.host.service()
        XCTAssertEqual(pair.host.failure, .clockStalled)
        XCTAssertEqual(pair.host.host?.nextTick, 1)
    }

    func testCombatCoordinatorQueuedFrameCannotOutrunStallWatchdog() throws {
        let pair = CombatPair(); defer { pair.close() }
        try pair.start(); pair.tick()
        pair.hostTransport.drop = { data in
            (try? JSONDecoder().decode(DuelNetworkCombatProtocol.Message.self, from: data)) != nil
        }
        pair.tick()
        let queued = try XCTUnwrap(pair.frames.last).encoded()
        XCTAssertEqual(pair.host.host?.nextTick, 2)
        XCTAssertEqual(pair.guest.replay?.nextTick, 1)
        var published = 0
        pair.guest.presentation?.didSimulateStep = { _, _ in published += 1 }
        pair.time.value += DuelNetworkCombatCoordinator.maximumClockGap + 0.01
        // Deliberately deliver the valid next frame BEFORE service can wake.
        pair.guestTransport.receive?(queued, "z-host")
        XCTAssertEqual(pair.guest.failure, .clockStalled)
        XCTAssertEqual(pair.guest.replay?.nextTick, 1)
        XCTAssertEqual(pair.guest.presentation?.nextPresentationTick, 1)
        XCTAssertEqual(published, 0)
    }

    func testCombatCoordinatorLateLoadCompletionCannotEraseHandshakeExpiry() throws {
        let pair = CombatPair(); defer { pair.close() }
        pair.guestLoader.autoLoad = false
        try pair.start()
        pair.time.value += DuelNetworkCombatCoordinator.handshakeTimeout
        pair.guestLoader.finishLoad() // No watchdog service call first.
        XCTAssertEqual(pair.guest.failure, .handshakeTimeout)
        XCTAssertNil(pair.guest.replay); XCTAssertNil(pair.host.host)
        XCTAssertNil(pair.guestLoader.committed)
        XCTAssertEqual(pair.guestLoader.released, 1)
        XCTAssertEqual(pair.guestLoader.cancelled, 1)
    }

    func testCombatCoordinatorLateRendererCompletionCannotStartEitherSeat() throws {
        for delayedHost in [false, true] {
            let pair = CombatPair(); defer { pair.close() }
            let loader = delayedHost ? pair.hostLoader : pair.guestLoader
            let coordinator = delayedHost ? pair.host : pair.guest
            loader.autoPresent = false
            try pair.start()
            pair.time.value += DuelNetworkCombatCoordinator.handshakeTimeout
            loader.finishPresentation() // Complete before the expired watchdog runs.
            XCTAssertEqual(coordinator.failure, .handshakeTimeout)
            XCTAssertNil(coordinator.presentation)
            XCTAssertEqual(pair.host.host?.nextTick, 0)
            XCTAssertEqual(pair.guest.replay?.nextTick, 0)
            XCTAssertTrue(pair.frames.isEmpty)
            let session = try XCTUnwrap(loader.session)
            XCTAssertThrowsError(try session.startAuthoritativePresentation())
        }
    }

    func testCombatCoordinatorLateReadyAndInputCannotRefreshExpiredDeadlines() throws {
        let startup = CombatPair(); defer { startup.close() }
        startup.guestTransport.drop = { data in
            (try? JSONDecoder().decode(DuelNetworkCombatCoordinator.Control.self, from: data)) != nil
        }
        try startup.start()
        let config = try XCTUnwrap(startup.host.configuration)
        startup.time.value += DuelNetworkCombatCoordinator.handshakeTimeout
        try startup.sendControl(.ready(config))
        XCTAssertEqual(startup.host.failure, .handshakeTimeout)
        XCTAssertEqual(startup.host.host?.nextTick, 0)

        let running = CombatPair(); defer { running.close() }
        try running.start(); running.tick()
        let runningConfig = try XCTUnwrap(running.host.configuration)
        running.time.value += DuelNetworkCombatCoordinator.peerTimeout
        try running.sendControl(.input(.init(sessionID: runningConfig.sessionID,
                                             sequence: 100, tick: 6, move: 1)))
        XCTAssertEqual(running.host.failure, .peerTimeout)
        XCTAssertEqual(running.host.host?.nextTick, 1)
    }

    func testCombatCoordinatorExplicitCloseThenDeallocationCancelsLoaderOnce() async throws {
        let transport = CombatMemoryTransport(local: "z-host")
        let loader = CombatTestLoader(), time = CombatTestTime()
        var coordinator: DuelNetworkCombatCoordinator? = .init(
            testingTransport: transport, compatibility: CombatTestLoader.expectedCompatibility,
            loader: { loader.load($0, completion: $1) },
            cancelLoading: { loader.cancelled += 1 }, now: { time.value })
        weak var weakCoordinator = coordinator
        try coordinator?.attach()
        coordinator?.close(); coordinator?.close()
        XCTAssertEqual(loader.cancelled, 1)
        coordinator = nil
        XCTAssertNil(weakCoordinator)
        // Give the deinit's MainActor cleanup task time to execute as well.
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(loader.cancelled, 1, "Old owner cleanup must not cancel a subsequent match's loader")
        XCTAssertEqual(transport.releases, 1)
    }

    func testCombatCoordinatorDeallocationAloneCancelsLoaderOnMainActor() async throws {
        let transport = CombatMemoryTransport(local: "z-host")
        let loader = CombatTestLoader(), time = CombatTestTime()
        var coordinator: DuelNetworkCombatCoordinator? = .init(
            testingTransport: transport, compatibility: CombatTestLoader.expectedCompatibility,
            loader: { loader.load($0, completion: $1) },
            cancelLoading: {
                // This closure is both Sendable and MainActor-isolated. Its
                // isolated loader mutation must remain valid under strict checking.
                XCTAssertTrue(Thread.isMainThread)
                loader.cancelled += 1
            }, now: { time.value })
        weak var weakCoordinator = coordinator
        try coordinator?.attach()
        XCTAssertEqual(loader.cancelled, 0)
        coordinator = nil
        XCTAssertNil(weakCoordinator)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(loader.cancelled, 1)
        XCTAssertEqual(transport.releases, 1)
    }

    func testCombatCoordinatorGuestCannotFreeRunAndPeerWatchdogEndsSilence() throws {
        let pair = CombatPair(); defer { pair.close() }
        try pair.start()
        for _ in 0..<20 { pair.guest.service(); pair.guest.presentation?.advance() }
        XCTAssertEqual(pair.guest.replay?.nextTick, 0)
        pair.guestTransport.drop = { _ in true }
        pair.tick(121)
        XCTAssertEqual(pair.host.failure, .peerTimeout)
        XCTAssertEqual(pair.host.state, .closed)
        XCTAssertLessThan(pair.host.host?.nextTick ?? .max, 121)
    }

    func testCombatCoordinatorCanonicalMismatchClosesWithoutRestoration() throws {
        let pair = CombatPair(); defer { pair.close() }
        try pair.start()
        pair.guestTransport.drop = { data in
            guard let value = try? JSONDecoder().decode(DuelNetworkCombatCoordinator.Control.self, from: data) else { return false }
            if case .checkpoint = value.control { return true }; return false
        }
        pair.tick(60)
        XCTAssertEqual(pair.host.state, .running)
        try pair.sendControl(.checkpoint(nextTick: 60, digest: String(repeating: "0", count: 64)))
        XCTAssertEqual(pair.host.failure, .verificationMismatch)
        XCTAssertEqual(pair.host.host?.nextTick, 60)
        XCTAssertEqual(pair.guest.state, .closed)
    }

    func testCombatCoordinatorReentrantRendererStopWinsAndTickCannotNest() throws {
        let pair = CombatPair(); defer { pair.close() }
        try pair.start()
        pair.host.presentation?.didSimulateStep = { _, _ in
            pair.host.service()
            pair.host.interrupt()
        }
        pair.tick()
        XCTAssertEqual(pair.host.failure, .interrupted)
        XCTAssertEqual(pair.host.host?.nextTick, 1)
        XCTAssertEqual(pair.host.presentation?.nextPresentationTick, 1)
        XCTAssertEqual(pair.guest.replay?.nextTick, 0)
        XCTAssertEqual(pair.guest.state, .closed)
    }

    func testCombatCoordinatorRateLimitAndMembershipReplacementAreTerminal() throws {
        let pair = CombatPair(); defer { pair.close() }
        try pair.start()
        let config = try XCTUnwrap(pair.host.configuration)
        for _ in 0..<250 { try pair.sendControl(.ready(config)) }
        XCTAssertEqual(pair.host.failure, .rateLimited)
        let replacement = CombatPair(); defer { replacement.close() }
        try replacement.start()
        replacement.guestTransport.state = .init(isFighter: true, capacity: 2, ready: true,
            localID: "a-guest", hostID: "replacement", members: ["a-guest", "replacement"])
        replacement.guest.service()
        XCTAssertEqual(replacement.guest.failure, .disconnected)
        XCTAssertEqual(replacement.guestTransport.releases, 1)
    }
}
#endif
