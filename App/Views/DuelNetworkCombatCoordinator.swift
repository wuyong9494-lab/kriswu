import Foundation
import Combine
import UIKit
import AVFoundation

/// One-shot combat owner used by the explicit nearby room integration.
/// One owner keeps selection/start/combat leases for an entire, one-shot match.
/// The injected loader must report actual resource and renderer readiness; this
/// type never treats a timer, catalog validation, or scene construction as GPU readiness.
@MainActor
final class DuelNetworkCombatCoordinator {
    typealias Barrier = DuelNetworkStartBarrier
    typealias Configuration = Barrier.Configuration
    typealias Completion = @MainActor (Result<Resources, Error>) -> Void
    typealias Loader = @MainActor (Configuration, @escaping Completion) -> Void
    typealias PresentationCompletion = @MainActor (Result<DuelSession, Error>) -> Void
    typealias PresentationLoader = @MainActor (Barrier, @escaping PresentationCompletion) -> Void
    /// Transferable into deinit cleanup, but callable only on the owner actor.
    typealias Cancellation = @MainActor @Sendable () -> Void

    enum State: Equatable { case idle, selecting, awaitingOffer, loading, awaitingPresentation, running, closed }
    enum Failure: Error, Equatable {
        case invalidState, invalidRoom, callbackBusy, incompatibleResources, invalidPresentation
        case loadingFailed, protocolViolation, peerCancelled, interrupted, disconnected
        case handshakeTimeout, peerTimeout, clockStalled, rateLimited, verificationMismatch, matchEnded
    }

    /// The production initializer accepts only an independently verified identity.
    /// `makePresentation` must finish AFTER the exact renderer is really ready.
    /// It should use DuelSession.networkPresentation; it may not return an offline
    /// session. `release` must clean up resources/renderers retained by the loader.
    @MainActor
    final class Resources {
        let compatibility: Barrier.Compatibility
        let catalog: DuelWeaponCatalog
        fileprivate let makePresentation: PresentationLoader
        fileprivate let permitsFixture: Bool
        private var cleanup: (() -> Void)?

        init(verified identity: DuelNetworkCompatibilityIdentity,
             makePresentation: @escaping PresentationLoader, release: @escaping () -> Void) {
            compatibility = identity.compatibility; catalog = identity.catalog
            self.makePresentation = makePresentation; cleanup = release; permitsFixture = false
        }
        #if DEBUG
        init(testingCompatibility: Barrier.Compatibility, catalog: DuelWeaponCatalog,
             makePresentation: @escaping PresentationLoader, release: @escaping () -> Void = {}) {
            compatibility = testingCompatibility; self.catalog = catalog
            self.makePresentation = makePresentation; cleanup = release; permitsFixture = true
        }
        #endif
        fileprivate func release() {
            let action = cleanup; cleanup = nil
            action?()
        }
    }

    /// Coordinator-only messages share the router's combat phase but cannot be
    /// decoded as authoritative frame batches. Bounds/version/start are checked
    /// before dispatch. Input counters remain the core host inbox's counters.
    struct Control: Codable {
        let namespace: String
        let version: Int
        let coordinatorVersion: Int
        let sessionID: String
        let startID: String
        let control: Command
        enum Command: Codable {
            case ready(Configuration)
            case input(DuelNetworkInputs.Message)
            case checkpoint(nextTick: UInt64, digest: String)
            case cancel
        }
        init(configuration: Configuration, control: Command) {
            namespace = DuelNetworkCombatProtocol.namespace
            version = DuelNetworkCombatProtocol.protocolVersion; coordinatorVersion = 1
            sessionID = configuration.sessionID; startID = configuration.startID; self.control = control
        }
    }

    static let inputLead: UInt64 = 4
    static let handshakeTimeout: TimeInterval = 15
    static let peerTimeout: TimeInterval = 2
    static let maximumClockGap: TimeInterval = 0.25
    static let maximumControlBytes = 4_096
    static let packetsPerSecond = 240
    static let checkpointInterval: UInt64 = 60

    let lobby: DuelNetworkLobby
    private(set) var state = State.idle
    private(set) var failure: Failure?
    private(set) var presentation: DuelSession?
    private(set) var configuration: Configuration?
    private(set) var host: DuelNetworkCombatHost?
    private(set) var replay: DuelNetworkReplay?
    /// Delivered after an outer transition has finished, never from a property's
    /// willSet. The host must still offer only after submit(.start) returns.
    var didChange: (@MainActor () -> Void)?
    private struct Observation: Equatable {
        let state: State
        let failure: Failure?
        let configuration: Configuration?
        let presentation: ObjectIdentifier?
    }
    private var transitionDepth = 0
    private var notifying = false
    private var lastObservation: Observation?

    private func beginTransition() { transitionDepth += 1 }
    private func endTransition() {
        transitionDepth -= 1
        guard transitionDepth == 0, !notifying else { return }
        notifying = true
        defer { notifying = false }
        while true {
            let value = Observation(state: state, failure: failure, configuration: configuration,
                                    presentation: presentation.map(ObjectIdentifier.init))
            guard value != lastObservation else { return }
            lastObservation = value
            didChange?()
        }
    }

    private let router: DuelNetworkMessageRouter
    private let startChannel: DuelNetworkMessageRouter.Channel
    private let combatChannel: DuelNetworkMessageRouter.Channel
    private let expectedCompatibility: Barrier.Compatibility
    private let loader: Loader
    private let cancelLoading: Cancellation
    private let now: () -> TimeInterval
    private let automaticClock: Bool
    private let permitsFixtures: Bool
    private var observations = Set<AnyCancellable>()
    private var owner: UUID?
    private var pinned: DuelLobbyRoomState?
    private var started: DuelMultiplayerSelection.Snapshot?
    private var barrier: Barrier?
    private var resources: Resources?
    private var loadToken: UUID?
    private var didCancelLoading = false
    private var presentationToken: UUID?
    private var startSequence: UInt64 = 0
    private var inputSequence: UInt64 = 0
    private var peerReady = false
    private var deadline: TimeInterval?
    private var lastPeerActivity: TimeInterval = 0
    private var lastPulse: TimeInterval = 0
    private var lastObservedTime: TimeInterval = 0
    private var rateWindow: TimeInterval = 0
    private var packetsInWindow = 0
    private var checkpoints: [UInt64: String] = [:]
    private var lastCheckpoint: UInt64 = 0
    private var hashTask: Task<String?, Never>?
    private var hashToken: UUID?
    private var computingCheckpoint: UInt64?
    private var pendingCheckpoint: (tick: UInt64, digest: String)?
    private let interruptions = DuelCombatInterruptionTokens()
    private var servicing = false
    private var receivingFrame = false
    private var pulseTask: Task<Void, Never>?

    convenience init(transport: any DuelLobbyTransport, verified identity: DuelNetworkCompatibilityIdentity,
                     loader: @escaping Loader, cancelLoading: @escaping Cancellation) {
        self.init(transport: transport, compatibility: identity.compatibility, loader: loader,
                  cancelLoading: cancelLoading, now: { ProcessInfo.processInfo.systemUptime },
                  automaticClock: true, permitsFixtures: false)
    }

    #if DEBUG
    convenience init(testingTransport: any DuelLobbyTransport, compatibility: Barrier.Compatibility,
                     loader: @escaping Loader, cancelLoading: @escaping Cancellation = {},
                     now: @escaping () -> TimeInterval) {
        self.init(transport: testingTransport, compatibility: compatibility, loader: loader,
                  cancelLoading: cancelLoading, now: now, automaticClock: false, permitsFixtures: true)
    }
    #endif

    private init(transport: any DuelLobbyTransport, compatibility: Barrier.Compatibility,
                 loader: @escaping Loader, cancelLoading: @escaping Cancellation,
                 now: @escaping () -> TimeInterval, automaticClock: Bool, permitsFixtures: Bool) {
        let router = DuelNetworkMessageRouter(transport: transport)
        self.router = router
        startChannel = router.channel(for: .start); combatChannel = router.channel(for: .combat)
        lobby = DuelNetworkLobby(transport: router.channel(for: .selection))
        expectedCompatibility = compatibility; self.loader = loader
        self.cancelLoading = cancelLoading; self.now = now; self.automaticClock = automaticClock
        self.permitsFixtures = permitsFixtures
        lobby.$snapshot.sink { [weak self] in self?.selectionChanged($0) }.store(in: &observations)
        lobby.$status.sink { [weak self] value in
            if value == .closed { self?.close(.disconnected, notifyPeer: false) }
        }.store(in: &observations)
    }

    deinit {
        pulseTask?.cancel(); hashTask?.cancel()
        let router = router, lobby = lobby, resources = resources, presentation = presentation
        let cancelLoading = cancelLoading, shouldCancelLoading = !didCancelLoading
        Task { @MainActor in
            router.close(); lobby.shutdown()
            if shouldCancelLoading { cancelLoading() }
            presentation?.didRequestAuthoritativeStop = nil
            presentation?.shutdown(); resources?.release()
        }
    }

    /// Register ALL phase receivers before lobby.attach can send/receive offers.
    /// Attach only once to an already established, authenticated two-seat room.
    func attach() throws {
        beginTransition(); defer { endTransition() }
        guard state == .idle else { throw Failure.invalidState }
        do {
            try router.attach()
            let room = startChannel.state, token = UUID()
            pinned = room; owner = token; state = .selecting
            guard startChannel.claim(token, receive: { [weak self] data, sender in
                guard self?.owner == token else { return }
                self?.receiveStart(data, sender: sender)
            }, changed: { [weak self] in self?.checkRoom() }),
            combatChannel.claim(token, receive: { [weak self] data, sender in
                guard self?.owner == token else { return }
                self?.receiveCombat(data, sender: sender)
            }, changed: { [weak self] in self?.checkRoom() }) else { throw Failure.callbackBusy }
            lastPulse = now(); rateWindow = lastPulse; lastObservedTime = lastPulse
            guard lastPulse.isFinite, lastPulse >= 0 else {
                close(.clockStalled); throw Failure.clockStalled
            }
            deadline = lastPulse + Self.handshakeTimeout
            try lobby.attach()
            guard state != .closed else { throw Failure.invalidRoom }
            if automaticClock { observeInterruptions(token: token); startClock() }
        } catch {
            close(.invalidRoom, notifyPeer: false)
            throw error
        }
    }

    /// Explicit host action AFTER lobby.submit(.start) has returned. The lobby
    /// sends the started snapshot before this offer on the reliable ordered link.
    /// A selection observer must not call this reentrantly from @Published.
    func offer(startID: String, seed: UInt64) throws {
        beginTransition(); defer { endTransition() }
        guard state == .awaitingOffer, var value = barrier,
              value.localPlayerID == value.hostID, lobby.status == .started else { throw Failure.invalidState }
        guard checkedBoundaryTime() != nil else { throw failure ?? Failure.invalidState }
        let message = try value.makeOffer(startID: startID, seed: seed, sequence: 1)
        barrier = value; startSequence = 1; configuration = value.offeredConfiguration
        state = .loading; deadline = now() + Self.handshakeTimeout
        startChannel.sendReliable(try message.encoded())
        beginLoading()
    }

    /// Scene backgrounding, audio interruption, navigation and renderer failure
    /// are terminal. There is no pause/resume, rematch, or host migration here.
    func validateRoom() { checkRoom() }
    func interrupt() { close(.interrupted) }
    func close() { close(.interrupted) }

    /// Monotonic watchdog AND one host tick. Production owns a 60 Hz task;
    /// deterministic tests call this explicitly. Never catch up a stalled clock.
    func service() {
        beginTransition(); defer { endTransition() }
        guard state != .idle, state != .closed, !servicing else { return }
        servicing = true
        defer { servicing = false }
        guard let time = checkedBoundaryTime() else { return }
        lastPulse = time
        guard state == .running else { return }
        // Guest renderer readiness does not prove the host renderer is ready.
        if !isHost, replay?.nextTick == 0 { return }
        // Guests have no simulation clock. Only validated frames advance replay.
        guard host != nil else { return }
        sampleInput()
        guard state == .running, var value = host else { return }
        do {
            let message = try value.advance(frameCount: 1)
            let bytes = try message.encoded()
            guard checkedBoundaryTime() != nil else { return }
            host = value
            makeCheckpoint(game: value.game, nextTick: value.nextTick)
            guard state == .running else { return }
            try presentation?.publishAuthoritativeStep(trustedGame: value.game, tick: value.nextTick - 1)
            guard state == .running, checkedBoundaryTime() != nil else { return }
            combatChannel.sendReliable(bytes)
            if case .matchOver = value.game.phase { close(.matchEnded, notifyPeer: false) }
        } catch { close(.protocolViolation) }
    }

    private var isHost: Bool { pinned?.localID == pinned?.hostID && pinned != nil }

    private func selectionChanged(_ snapshot: DuelMultiplayerSelection.Snapshot?) {
        beginTransition(); defer { endTransition() }
        guard state != .closed, state != .idle, let snapshot, checkedBoundaryTime() != nil else { return }
        if let started {
            guard started == snapshot else { close(.protocolViolation); return }
            return
        }
        guard snapshot.phase == .started, let room = pinned, let hostID = room.hostID,
              let guestID = room.members.first(where: { $0 != hostID }) else {
            if snapshot.phase == .selecting { deadline = nil }
            return
        }
        do {
            barrier = try Barrier(started: snapshot, sessionID: snapshot.sessionID,
                                  hostID: hostID, guestID: guestID, localPlayerID: room.localID,
                                  compatibility: expectedCompatibility)
            started = snapshot; state = .awaitingOffer; deadline = now() + Self.handshakeTimeout
        } catch { close(.protocolViolation) }
    }

    private func receiveStart(_ data: Data, sender: String) {
        beginTransition(); defer { endTransition() }
        guard acceptPacket(sender: sender), var value = barrier else { return }
        let outcome = value.receive(data, authenticatedSenderID: sender)
        guard outcome == .applied else {
            if case .rejected(.wrongSession) = outcome { return }
            if case .ignoredStaleSequence = outcome { return }
            close(.protocolViolation); return
        }
        barrier = value
        if value.phase == .closed { close(.peerCancelled, notifyPeer: false); return }
        configuration = value.offeredConfiguration
        if state == .awaitingOffer { state = .loading }
        beginLoading()
        maybeCommit()
        beginPresentation()
    }

    private func beginLoading() {
        guard state == .loading, resources == nil, loadToken == nil,
              let configuration, checkedBoundaryTime() != nil else { return }
        let token = UUID(); loadToken = token
        loader(configuration) { [weak self] result in
            guard let self else {
                if case .success(let resources) = result { resources.release() }
                return
            }
            self.beginTransition(); defer { self.endTransition() }
            guard self.state != .closed, self.loadToken == token,
                  self.checkedBoundaryTime() != nil else {
                if case .success(let resources) = result, resources !== self.resources { resources.release() }
                return
            }
            self.loadToken = nil
            switch result {
            case .failure: self.close(.loadingFailed)
            case .success(let resources): self.loaded(resources, configuration: configuration)
            }
        }
    }

    private func loaded(_ resources: Resources, configuration: Configuration) {
        guard checkedBoundaryTime() != nil else { resources.release(); return }
        guard var value = barrier, resources.compatibility == expectedCompatibility,
              !resources.permitsFixture || permitsFixtures else {
            resources.release(); close(.incompatibleResources); return
        }
        do {
            let message = try value.confirmLoaded(configuration: configuration,
                loadedCompatibility: resources.compatibility, catalog: resources.catalog, sequence: startSequence + 1)
            guard checkedBoundaryTime() != nil else { resources.release(); return }
            barrier = value; startSequence = message.sequence; self.resources = resources
            startChannel.sendReliable(try message.encoded())
            maybeCommit()
            beginPresentation()
        } catch {
            resources.release(); close(.incompatibleResources)
        }
    }

    private func maybeCommit() {
        guard state != .closed, isHost, var value = barrier, value.phase == .loading,
              value.hostLoaded, value.guestLoaded, checkedBoundaryTime() != nil else { return }
        do {
            let message = try value.commit(sequence: startSequence + 1)
            barrier = value; startSequence = message.sequence
            // Prepare host state before synchronous delivery can return guest
            // ready/input packets. Presentation still cannot start without ready.
            beginPresentation()
            guard state != .closed else { return }
            startChannel.sendReliable(try message.encoded())
        } catch { close(.protocolViolation) }
    }

    private func beginPresentation() {
        guard state != .closed, let value = barrier, value.phase == .committed,
              let resources, presentationToken == nil, presentation == nil,
              checkedBoundaryTime() != nil else { return }
        do {
            if isHost {
                guard let started else { throw Failure.invalidState }
                host = try DuelNetworkCombatHost(committed: value, started: started,
                    loadedCompatibility: resources.compatibility, catalog: resources.catalog)
            } else {
                replay = try DuelNetworkReplay(committed: value,
                    loadedCompatibility: resources.compatibility, catalog: resources.catalog)
            }
        } catch { close(.protocolViolation); return }
        state = .awaitingPresentation
        let token = UUID(); presentationToken = token
        resources.makePresentation(value) { [weak self] result in
            guard let self else {
                if case .success(let session) = result { session.shutdown() }
                return
            }
            self.beginTransition(); defer { self.endTransition() }
            guard self.state != .closed, self.presentationToken == token,
                  self.checkedBoundaryTime() != nil else {
                if case .success(let session) = result, session !== self.presentation { session.shutdown() }
                return
            }
            self.presentationToken = nil
            switch result {
            case .failure: self.close(.loadingFailed)
            case .success(let session): self.presentationLoaded(session)
            }
        }
    }

    private func presentationLoaded(_ session: DuelSession) {
        guard checkedBoundaryTime() != nil else { session.shutdown(); return }
        guard let configuration, let resources, let authoritativeGame = host?.game ?? replay?.game,
              session.driver == .externalAuthoritative,
              session.localFighterIndex == (isHost ? 0 : 1), session.paused,
              session.nextPresentationTick == 0,
              session.game == authoritativeGame,
              session.committedConfiguration == configuration || (permitsFixtures && resources.permitsFixture) else {
            session.shutdown(); close(.invalidPresentation); return
        }
        presentation = session
        session.didRequestAuthoritativeStop = { [weak self] in self?.close(.interrupted) }
        startIfReady()
    }

    private func startIfReady() {
        guard state == .awaitingPresentation, let presentation,
              let configuration, !isHost || peerReady, checkedBoundaryTime() != nil else { return }
        do {
            try presentation.startAuthoritativePresentation()
            guard state != .closed, checkedBoundaryTime() != nil else { return }
            state = .running
            if isHost { deadline = nil }
            lastPeerActivity = now(); lastPulse = lastPeerActivity
            if !isHost {
                // This is the commit-delivery AND local-renderer-ready acknowledgement.
                sendControl(.ready(configuration))
                if state == .running { sampleInput() }
            }
        } catch { close(.invalidPresentation) }
    }

    private func sampleInput() {
        guard checkedBoundaryTime() != nil else { return }
        guard state == .running, let presentation, let configuration,
              let tick = host?.nextTick ?? replay?.nextTick,
              tick <= UInt64.max - Self.inputLead, inputSequence < UInt64.max else {
            close(.protocolViolation); return
        }
        let input = presentation.consumeLocalInput()
        guard state == .running else { return }
        inputSequence += 1
        let message = DuelNetworkInputs.Message(sessionID: configuration.sessionID,
            sequence: inputSequence, tick: tick + Self.inputLead,
            move: input.move, vertical: input.vertical, guardHeld: input.guardHeld,
            tapBits: input.taps.rawValue, weaponCommand: input.weaponCommand)
        if var value = host {
            let outcome = value.receive(message, authenticatedSenderID: configuration.host.id)
            host = value
            if outcome != .applied { close(.protocolViolation) }
        } else { sendControl(.input(message)) }
    }

    private func receiveCombat(_ data: Data, sender: String) {
        beginTransition(); defer { endTransition() }
        guard acceptPacket(sender: sender), let configuration else { return }
        if data.count <= Self.maximumControlBytes,
           let control = try? JSONDecoder().decode(Control.self, from: data) {
            guard data.count <= Self.maximumControlBytes,
                  control.namespace == DuelNetworkCombatProtocol.namespace,
                  control.version == DuelNetworkCombatProtocol.protocolVersion,
                  control.coordinatorVersion == 1 else { close(.protocolViolation); return }
            guard control.sessionID == configuration.sessionID, control.startID == configuration.startID,
                  checkedBoundaryTime() != nil else { return }
            switch control.control {
            case .cancel: close(.peerCancelled, notifyPeer: false)
            case .ready(let acknowledged):
                guard isHost, barrier?.phase == .committed, acknowledged == configuration else {
                    close(.protocolViolation); return
                }
                if !peerReady { peerReady = true; lastPeerActivity = now(); startIfReady() }
            case .input(let input):
                guard isHost, peerReady, var value = host else { close(.protocolViolation); return }
                let outcome = value.receive(input, authenticatedSenderID: sender)
                guard checkedBoundaryTime() != nil else { return }
                host = value
                if outcome == .applied { lastPeerActivity = now() }
                // Late/outside-window/duplicate requests NEVER refresh liveness.
                // Core rejects raw scalars, epochs, sequences and bounded queues.
            case .checkpoint(let tick, let digest):
                receiveCheckpoint(tick: tick, digest: digest)
            }
            return
        }
        // Frames are not wrapped or reconstructed. The core validates their
        // authenticated host/session/start/epoch/sequence and complete raw input.
        guard let message = try? JSONDecoder().decode(DuelNetworkCombatProtocol.Message.self, from: data) else {
            close(.protocolViolation); return
        }
        guard message.sessionID == configuration.sessionID, message.startID == configuration.startID else { return }
        guard !isHost, state == .running, !receivingFrame, var value = replay else {
            close(.protocolViolation); return
        }
        if case .frames(let frames) = message.command, frames.count != 1 {
            close(.protocolViolation); return // No final-state-only batched presentation.
        }
        receivingFrame = true
        defer { receivingFrame = false }
        let outcome = value.receive(data, authenticatedSenderID: sender)
        switch outcome {
        case .ignoredDuplicate: return
        case .rejected(.wrongSession), .rejected(.wrongStart): return
        case .rejected, .terminatedForEpochChange: close(.protocolViolation); return
        case .applied: break
        }
        guard checkedBoundaryTime() != nil else { return }
        replay = value
        if value.phase == .closed { close(.peerCancelled, notifyPeer: false); return }
        lastPeerActivity = now()
        if value.nextTick == 1 { deadline = nil; lastPulse = lastPeerActivity }
        do {
            try presentation?.publishAuthoritativeStep(trustedGame: value.game, tick: value.nextTick - 1)
            guard state == .running, checkedBoundaryTime() != nil else { return }
            makeCheckpoint(game: value.game, nextTick: value.nextTick)
            guard state == .running else { return }
            if case .matchOver = value.game.phase { close(.matchEnded, notifyPeer: false) }
            else { sampleInput() }
        } catch { close(.protocolViolation) }
    }

    private func makeCheckpoint(game: DuelGame, nextTick: UInt64) {
        guard nextTick.isMultiple(of: Self.checkpointInterval) else { return }
        // Only one immutable state copy/job per endpoint. Never queue snapshots
        // faster than they can be encoded, nor hash the full state on the UI actor.
        guard hashToken == nil else { close(.clockStalled); return }
        let token = UUID(); hashToken = token; computingCheckpoint = nextTick
        if !automaticClock {
            let digest = (try? DuelReplayStateEncoding.encode(game)).map(DuelNetworkContentRecord.digest)
            finishedCheckpoint(digest, tick: nextTick, token: token)
            return
        }
        let task = Task.detached(priority: .utility) { () -> String? in
            guard !Task.isCancelled, let bytes = try? DuelReplayStateEncoding.encode(game),
                  !Task.isCancelled else { return nil }
            return DuelNetworkContentRecord.digest(bytes)
        }
        hashTask = task
        Task { @MainActor [weak self] in
            let digest = await task.value
            self?.finishedCheckpoint(digest, tick: nextTick, token: token)
        }
    }

    private func finishedCheckpoint(_ digest: String?, tick: UInt64, token: UUID) {
        beginTransition(); defer { endTransition() }
        guard state == .running, hashToken == token, checkedBoundaryTime() != nil else { return }
        hashToken = nil; hashTask = nil; computingCheckpoint = nil
        guard let digest else { close(.protocolViolation); return }
        if isHost {
            checkpoints[tick] = digest
            for old in checkpoints.keys.sorted().dropLast(4) { checkpoints.removeValue(forKey: old) }
            if let pending = pendingCheckpoint, pending.tick == tick {
                pendingCheckpoint = nil
                receiveCheckpoint(tick: pending.tick, digest: pending.digest)
            }
        } else { sendControl(.checkpoint(nextTick: tick, digest: digest)) }
    }

    private func receiveCheckpoint(tick: UInt64, digest: String) {
        guard isHost, state == .running, tick > lastCheckpoint, tick > 0,
              tick.isMultiple(of: Self.checkpointInterval), tick <= (host?.nextTick ?? 0),
              DuelNetworkContentRecord.validDigest(digest) else { return }
        if let expected = checkpoints[tick] {
            guard expected == digest else { close(.verificationMismatch); return }
            lastCheckpoint = tick
            checkpoints = checkpoints.filter { $0.key > tick }
        } else if computingCheckpoint == tick {
            if let pending = pendingCheckpoint, pending.digest != digest {
                close(.verificationMismatch); return
            }
            pendingCheckpoint = (tick, digest) // One bounded early result, never simulation state.
        }
    }

    private func sendControl(_ command: Control.Command) {
        guard state != .closed, let configuration,
              let bytes = try? JSONEncoder().encode(Control(configuration: configuration, control: command)),
              bytes.count <= Self.maximumControlBytes, checkedBoundaryTime() != nil else { return }
        combatChannel.sendReliable(bytes)
    }

    private func acceptPacket(sender: String) -> Bool {
        checkRoom()
        guard state != .closed, let pinned,
              sender != pinned.localID, pinned.members.contains(sender) else { return false }
        guard let time = checkedBoundaryTime() else { return false }
        if time - rateWindow >= 1 { rateWindow = time; packetsInWindow = 0 }
        packetsInWindow += 1
        guard packetsInWindow <= Self.packetsPerSecond else { close(.rateLimited); return false }
        return true
    }

    /// Do not let a queued packet/completion outrun a delayed watchdog task.
    /// Check absolute monotonic expiry BEFORE it mutates state or refreshes any
    /// deadline/activity. Only service() changes the regular pulse timestamp.
    private func checkedBoundaryTime() -> TimeInterval? {
        guard state != .idle, state != .closed else { return nil }
        checkRoom()
        guard state != .closed else { return nil }
        let time = now()
        guard time.isFinite, time >= lastObservedTime, time >= lastPulse else {
            close(.clockStalled); return nil
        }
        if let deadline, time >= deadline { close(.handshakeTimeout); return nil }
        // Before its first frame the guest still uses the startup deadline,
        // allowing a valid host renderer load to take longer than peerTimeout.
        if state == .running, isHost || replay?.nextTick != 0 {
            guard time - lastPeerActivity < Self.peerTimeout else { close(.peerTimeout); return nil }
            guard time - lastPulse <= Self.maximumClockGap else { close(.clockStalled); return nil }
        }
        lastObservedTime = time
        return time
    }

    private func checkRoom() {
        beginTransition(); defer { endTransition() }
        guard state != .closed, let pinned else { return }
        let current = startChannel.state
        guard state != .closed else { return }
        guard current.ready, current.isFighter, current.capacity == 2,
              current.localID == pinned.localID, current.hostID == pinned.hostID,
              current.members.count == 2, Set(current.members) == Set(pinned.members) else {
            close(.disconnected, notifyPeer: false); return
        }
    }

    private func close(_ reason: Failure, notifyPeer: Bool = true) {
        beginTransition(); defer { endTransition() }
        guard state != .closed else { return }
        // Invalidate EVERY callback before calling transport, loader or renderer.
        state = .closed; failure = reason; loadToken = nil; presentationToken = nil
        pulseTask?.cancel(); pulseTask = nil; deadline = nil
        hashTask?.cancel(); hashTask = nil; hashToken = nil
        computingCheckpoint = nil; pendingCheckpoint = nil; interruptions.remove()
        var cancellation: Data?
        if notifyPeer, var value = barrier, startSequence < UInt64.max {
            cancellation = try? value.makeCancellation(sequence: startSequence + 1).encoded()
        }
        _ = barrier?.cancel(); _ = host?.cancel(); _ = replay?.cancel()
        if let cancellation { startChannel.sendReliable(cancellation) }
        let token = owner; owner = nil
        if let token { startChannel.release(token); combatChannel.release(token) }
        router.close(); lobby.shutdown()
        didCancelLoading = true; cancelLoading()
        presentation?.didRequestAuthoritativeStop = nil
        if let game = host?.game ?? replay?.game {
            try? presentation?.publishAuthoritativeCancellation(trustedGame: game)
        }
        presentation?.shutdown(); resources?.release(); resources = nil
        checkpoints.removeAll()
    }

    private func observeInterruptions(token: UUID) {
        for name in [UIApplication.willResignActiveNotification, AVAudioSession.interruptionNotification] {
            interruptions.tokens.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard self?.owner == token else { return }
                        self?.interrupt()
                    }
                })
        }
    }

    private func startClock() {
        guard var schedule = DuelNetworkPulseSchedule(startingAt: DispatchTime.now().uptimeNanoseconds) else {
            close(.clockStalled); return
        }
        pulseTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let delay = schedule.sleepNanoseconds(at: DispatchTime.now().uptimeNanoseconds) else {
                    self?.close(.clockStalled); return
                }
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                guard !Task.isCancelled, let self, self.state != .closed else { return }
                self.service()
                guard self.state != .closed else { return }
                // Service/encoding/presentation work uses this interval's budget,
                // not an extra delay added to every tick. Skip elapsed deadlines;
                // the watchdog still decides whether a late wake may step once.
                guard schedule.advance(afterPulseAt: DispatchTime.now().uptimeNanoseconds) else {
                    self.close(.clockStalled); return
                }
            }
        }
    }
}

/// Foundation observer cleanup is thread-safe and does not access actor state.
private final class DuelCombatInterruptionTokens {
    var tokens: [NSObjectProtocol] = []
    func remove() {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens.removeAll()
    }
    deinit { remove() }
}
