import Foundation
import Combine
import UIKit
import AVFoundation

/// One explicit room entry, including preflight and the pending committed mount.
/// No navigation or failure branch constructs an offline DuelSession.
@MainActor
final class DuelNetworkRoomModel: @MainActor ObservableObject {
    enum State: Equatable {
        case idle, preparing, connecting, selecting, awaitingStart, mounting, running, closed
    }
    typealias Preflight = @MainActor () throws -> any DuelNetworkRoomLoading
    let objectWillChange = ObservableObjectPublisher()
    /// Transport mode for labels only; both modes use the same verified combat path.
    let nearbyCombat: Bool
    private(set) var state = State.idle
    private(set) var error: String?
    private(set) var selection: DuelNetworkSelectionModel?
    private(set) var coordinator: DuelNetworkCombatCoordinator?
    var pendingPreparation: DuelNetworkMatchPreparation? { loading?.pendingPreparation }

    private let transport: any DuelLobbyTransport
    private let startTransport: @MainActor () -> Void
    private let leaveTransport: @MainActor () -> Void
    private let isForeground: @MainActor () -> Bool
    private let preflight: Preflight
    private var loading: (any DuelNetworkRoomLoading)?
    private var generation: UUID?
    private var startup: Task<Void, Never>?
    private var observations = Set<AnyCancellable>()
    private let interruptions = DuelRoomInterruptionTokens()
    private var attached = false
    private var left = false
    private var startingSelection = false
    private let selectionTimeout: UInt64

    convenience init(room: GameRoom) {
        let nearby: Bool
        switch room.mode { case .nearbyHost, .nearbyGuest: nearby = true; case .remote: nearby = false }
        self.init(transport: DuelGameRoomTransport(room: room), nearbyCombat: nearby,
                  start: { room.start() }, leave: { room.leave() },
                  foreground: { UIApplication.shared.applicationState == .active },
                  preflight: {
                      DuelNetworkPresentationLoader(prepared: try DuelNetworkCompatibilityIdentity.prepare())
                  })
        // GameRoom publishes before assignment. Reinspect only the settled value;
        // the generation check prevents an old queued notification reopening us.
        Publishers.CombineLatest3(room.$phase, room.$members, room.$hostID)
            .dropFirst().sink { [weak self] _ in
                guard let token = self?.generation else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    if case .closed(let reason) = room.phase { self.close(reason: reason) }
                    else { self.roomChanged() }
                }
            }.store(in: &observations)
    }

    private init(transport: any DuelLobbyTransport, nearbyCombat: Bool,
                 start: @escaping @MainActor () -> Void, leave: @escaping @MainActor () -> Void,
                 foreground: @escaping @MainActor () -> Bool, preflight: @escaping Preflight,
                 selectionTimeout: UInt64 = 10_000_000_000) {
        self.transport = transport; self.nearbyCombat = nearbyCombat
        startTransport = start; leaveTransport = leave; isForeground = foreground
        self.preflight = preflight; self.selectionTimeout = selectionTimeout
    }

    #if DEBUG
    convenience init(testingTransport: any DuelLobbyTransport, nearbyCombat: Bool = true,
                     start: @escaping @MainActor () -> Void = {}, leave: @escaping @MainActor () -> Void,
                     foreground: @escaping @MainActor () -> Bool = { true },
                     selectionTimeout: UInt64 = 10_000_000_000, preflight: @escaping Preflight) {
        self.init(transport: testingTransport, nearbyCombat: nearbyCombat, start: start, leave: leave,
                  foreground: foreground, preflight: preflight, selectionTimeout: selectionTimeout)
    }
    #endif

    deinit { startup?.cancel() }

    /// Called after explicit room entry. Loading state is visible before the
    /// deferred synchronous MainActor preflight. It is not a cancellable decoder.
    func begin() {
        guard state == .idle, isForeground() else { return }
        let token = UUID(); generation = token
        observeInterruptions(token: token)
        state = .preparing
        objectWillChange.send()
        guard generation == token, state != .closed else { return }
        startup = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, self.generation == token, self.isForeground() else {
                self?.close(reason: "应用已中断，请重新进入房间。")
                return
            }
            self.finishStartup(token: token)
        }
    }

    private func finishStartup(token: UUID) {
        guard generation == token, state != .closed else { return }
        do {
            let resources = try preflight() // Deliberately synchronous, before transport and deadlines.
            guard generation == token, state != .closed, isForeground() else {
                resources.cancel(); close(reason: "准备期间应用已中断，请重新进入房间。")
                return
            }
            loading = resources
            resources.didChange = { [weak self] in
                guard let self, self.generation == token else { return }
                self.loadingChanged()
            }
            let combat = try resources.makeCoordinator(transport: transport)
            coordinator = combat
            combat.didChange = { [weak self] in
                guard let self, self.generation == token else { return }
                self.coordinatorChanged()
            }
            selection = DuelNetworkSelectionModel(borrowing: combat.lobby,
                localID: transport.state.localID, timeoutNanoseconds: selectionTimeout,
                requestClose: { [weak self] reason in self?.close(reason: reason) })
            guard generation == token, state != .closed, isForeground() else {
                close(reason: "应用已中断，请重新进入房间。"); return
            }
            state = .connecting; objectWillChange.send()
            guard generation == token, state != .closed, isForeground() else {
                close(reason: "应用已中断，请重新进入房间。"); return
            }
            startTransport()
            guard generation == token, state != .closed else { return }
            roomChanged()
        } catch {
            close(reason: "联机资源或房间准备失败。需要完整且通过校验的原始资源，请退出后重试。")
        }
    }

    /// Safe to call repeatedly; readiness cannot attach a replacement session.
    func roomChanged() {
        guard generation != nil, state != .preparing, state != .idle, state != .closed else { return }
        guard isForeground() else { interrupt(); return }
        if attached {
            // Coordinator service validates pinned identity/membership even if a
            // room notification arrives before the transport's queued callback.
            coordinator?.validateRoom()
            return
        }
        guard transport.state.ready else { return }
        attached = true
        do {
            guard let coordinator, let selection,
                  selection.bindBorrowedIdentityBeforeAttachment(transport.state.localID) else {
                close(reason: "无法确认本机联机身份，请重新进入房间。"); return
            }
            // Game Center authentication may replace the provisional UUID during start().
            // Bind the settled room identity before the coordinator publishes any snapshot.
            guard generation != nil, state != .closed else { return }
            try coordinator.attach(); coordinatorChanged()
        } catch { close(reason: "无法建立双人连接，请离开后重新进入。") }
    }

    /// Host-only UI action. The started snapshot must finish publication and
    /// reliable send before any offer is made. Never launch from a Combine sink.
    func startSelection() {
        guard !startingSelection, state == .selecting, let selection else { return }
        startingSelection = true
        defer { startingSelection = false }
        guard selection.startSelection(), state != .closed else { return }
        if let coordinator {
            do { try coordinator.offer(startID: UUID().uuidString, seed: UInt64.random(in: 0...UInt64.max)) }
            catch { close(reason: "联机开始未能确认，请离开后重新进入。") }
        }
    }

    func interrupt() {
        guard state != .idle, state != .closed else { return }
        close(reason: "应用或音频已中断，联机已结束。请重新进入房间。")
    }

    /// The only terminal path. Invalidate generation BEFORE arbitrary hooks;
    /// cleanup is synchronous and room.leave is invoked exactly once.
    func close(reason: String? = nil) {
        guard state != .closed else { return }
        state = .closed; generation = nil; error = reason
        startup?.cancel(); startup = nil
        observations.removeAll(); interruptions.remove()
        let combat = coordinator, resources = loading, model = selection
        coordinator = nil; loading = nil; selection = nil
        combat?.didChange = nil; resources?.didChange = nil
        combat?.close(); resources?.cancel(); model?.close(reason: reason)
        if !left { left = true; leaveTransport() }
        objectWillChange.send()
    }

    private func loadingChanged() {
        guard state != .closed else { return }
        guard loading?.isClosed == false else {
            // Coordinator teardown cancels loading before its settled callback.
            // Let that callback retain the actual timeout/disconnect/result,
            // rather than replacing it with a generic loader error mid-cleanup.
            if coordinator?.state == .closed { return }
            close(reason: "联机画面或资源已失效，请重新进入房间。"); return
        }
        if pendingPreparation != nil { state = .mounting }
        objectWillChange.send()
    }

    private func coordinatorChanged() {
        guard state != .closed, let coordinator else { return }
        switch coordinator.state {
        case .idle: break
        case .selecting: state = .selecting
        case .awaitingOffer, .loading: state = .awaitingStart
        case .awaitingPresentation: state = .mounting
        case .running: state = .running
        case .closed:
            close(reason: terminalReason(coordinator)); return
        }
        objectWillChange.send()
    }

    private func terminalReason(_ combat: DuelNetworkCombatCoordinator) -> String {
        switch combat.failure {
        case .matchEnded?:
            if let game = combat.host?.game ?? combat.replay?.game,
               case .matchOver(let winner) = game.phase, let local = combat.presentation?.localFighterIndex {
                return (winner == local ? "本场胜利" : "本场失利") + " · 比分 \(game.wins[local]) : \(game.wins[1 - local])"
            }
            return "本场对决已结束。"
        case .handshakeTimeout?: return "等待双方准备超时，请重新进入房间。"
        case .peerTimeout?, .clockStalled?: return "联机同步超时，对战已停止。请重新进入房间。"
        case .disconnected?, .peerCancelled?: return "对方已离开或房间连接已中断，请重新进入房间。"
        case .interrupted?: return "联机已结束，请重新进入房间。"
        case .loadingFailed?, .incompatibleResources?, .invalidPresentation?:
            return "双方资源或画面未能通过确认，请检查完整资源后重新进入房间。"
        default: return "联机同步未能通过校验，对战已停止。请重新进入房间。"
        }
    }

    private func observeInterruptions(token: UUID) {
        for name in [UIApplication.willResignActiveNotification, AVAudioSession.interruptionNotification] {
            interruptions.tokens.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard self?.generation == token else { return }
                        self?.interrupt()
                    }
                })
        }
    }
}

private final class DuelRoomInterruptionTokens {
    var tokens: [NSObjectProtocol] = []
    func remove() {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens.removeAll()
    }
    deinit { remove() }
}
