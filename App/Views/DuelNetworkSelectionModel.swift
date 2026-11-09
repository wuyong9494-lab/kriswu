import Foundation
import Combine

/// View state for the selection experiment. A successful Start is NOT a combat
/// launch. In particular, this type never creates a DuelSession or DuelSetup.
@MainActor
final class DuelNetworkSelectionModel: ObservableObject {
    typealias Selection = DuelMultiplayerSelection
    struct Pending: Equatable {
        let command: Selection.Command
        let sessionID: String
        let lastSequence: UInt64
        let selectionRevision: UInt64
    }

    @Published private(set) var snapshot: Selection.Snapshot?
    @Published private(set) var status: DuelNetworkLobby.Status = .idle
    @Published private(set) var localID = ""
    @Published private(set) var pending: Pending?
    @Published private(set) var error: String?
    private let lobby: DuelNetworkLobby
    private let router: DuelNetworkMessageRouter?
    private var observations = Set<AnyCancellable>()
    private var deadline: Task<Void, Never>?
    private var attemptedAttachment = false
    private var closing = false
    private let timeoutNanoseconds: UInt64

    /// Keep direct lobby injection available to protocol/presentation tests.
    convenience init(lobby: DuelNetworkLobby, timeoutNanoseconds: UInt64 = 10_000_000_000) {
        self.init(lobby: lobby, router: nil, timeoutNanoseconds: timeoutNanoseconds)
    }

    /// The model owns the root across selection, including terminal agreement.
    /// Construction does not claim a callback, send, or start the transport.
    convenience init(transport: any DuelLobbyTransport, timeoutNanoseconds: UInt64 = 10_000_000_000) {
        let router = DuelNetworkMessageRouter(transport: transport)
        let lobby = DuelNetworkLobby(transport: router.channel(for: .selection))
        self.init(lobby: lobby, router: router, timeoutNanoseconds: timeoutNanoseconds)
    }

    convenience init(room: GameRoom, timeoutNanoseconds: UInt64 = 10_000_000_000) {
        self.init(transport: DuelGameRoomTransport(room: room), timeoutNanoseconds: timeoutNanoseconds)
    }

    private init(lobby: DuelNetworkLobby, router: DuelNetworkMessageRouter?, timeoutNanoseconds: UInt64) {
        self.lobby = lobby
        self.router = router
        self.timeoutNanoseconds = timeoutNanoseconds
        lobby.$snapshot.sink { [weak self] in self?.received($0) }.store(in: &observations)
        lobby.$status.sink { [weak self] in self?.changedStatus($0) }.store(in: &observations)
    }

    deinit { deadline?.cancel() }

    var localPlayer: Selection.Player? { snapshot?.players.first { $0.id == localID } }
    var isHost: Bool { localPlayer?.seat == .host }
    var hasConflict: Bool {
        guard let snapshot, snapshot.players.allSatisfy({ $0.choice != nil }) else { return false }
        return !snapshot.hasDistinctChoices
    }
    var canChoose: Bool {
        status == .selecting && snapshot?.phase == .selecting && localPlayer != nil && pending == nil
    }
    var canReady: Bool { canChoose && snapshot?.hasDistinctChoices == true }
    var canStart: Bool { canChoose && isHost && snapshot?.canStart == true }

    /// Fighter rooms are always two seats, including manually entered codes.
    static func roomCode(_ text: String) -> Int? {
        guard let code = RoomCode.parse(text), RoomCode.players(of: code) == 2 else { return nil }
        return code
    }

    /// The owning screen calls this only after the room is ready. Never silently
    /// attach a second session following a disconnect, timeout or host change.
    func attach(localID: String) {
        guard !attemptedAttachment else { return }
        attemptedAttachment = true
        self.localID = localID
        do {
            try router?.attach()
            try lobby.attach()
            if status == .connecting { armDeadline() }
        } catch DuelNetworkMessageRouter.Failure.callbackBusy {
            close(reason: "房间通道正在被使用，请离开后重新进入。")
        } catch DuelNetworkLobby.Failure.callbackBusy {
            close(reason: "房间通道正在被使用，请离开后重新进入。")
        } catch {
            close(reason: "无法建立双人选角，请确认两位玩家都在同一个双人房间。")
        }
    }

    func choose(_ choice: Selection.Choice) {
        guard canChoose, choice.isValid, localPlayer?.choice != choice else { return }
        submit(.select(choice))
    }

    func toggleReady() {
        guard canReady, let snapshot, let localPlayer else { return }
        submit(.ready(!localPlayer.isReady, selectionRevision: snapshot.selectionRevision))
    }

    func startSelection() {
        guard canStart, let snapshot else { return }
        submit(.start(selectionRevision: snapshot.selectionRevision))
    }

    func close(reason: String? = nil) {
        attemptedAttachment = true
        deadline?.cancel(); deadline = nil
        pending = nil
        if let reason { error = reason }
        guard !closing else { return }
        closing = true
        lobby.shutdown()
        router?.close()
        closing = false
    }

    private func submit(_ command: Selection.Command) {
        guard let snapshot, let localPlayer else { return }
        error = nil
        pending = Pending(command: command, sessionID: snapshot.sessionID,
                          lastSequence: localPlayer.lastSequence,
                          selectionRevision: snapshot.selectionRevision)
        // Publish intent before submitting: the host and offline test transports
        // can synchronously publish acceptance while submit() is still running.
        if !lobby.submit(command) {
            pending = nil
            error = "操作未获确认，请按当前选角状态重试。"
        } else if pending != nil {
            armDeadline()
        }
    }

    private func received(_ value: Selection.Snapshot?) {
        snapshot = value
        guard let pending, let value else { return }
        if value.sessionID != pending.sessionID {
            finishPending(error: "选角会话已更新，请重新选择并准备。")
            return
        }
        if let player = value.players.first(where: { $0.id == localID }),
           player.lastSequence > pending.lastSequence {
            let accepted: Bool
            switch pending.command {
            case .select(let choice): accepted = player.choice == choice
            case .ready(let ready, let revision):
                accepted = player.isReady == ready && value.selectionRevision == revision
            case .start: accepted = value.phase == .started
            }
            finishPending(error: accepted ? nil : "选角已变化，请确认当前状态后重试。")
        } else if case .ready = pending.command, value.selectionRevision != pending.selectionRevision {
            finishPending(error: "对阵已变化，双方需要重新准备。")
        }
    }

    private func changedStatus(_ value: DuelNetworkLobby.Status) {
        status = value
        if value == .selecting && pending == nil {
            deadline?.cancel(); deadline = nil
        } else if value == .closed {
            attemptedAttachment = true
            finishPending(error: error ?? "选角连接已结束，请离开后重新进入房间。")
            // Protocol-driven closure (for example a replaced host session)
            // also retires the root. Explicit close finishes lobby teardown first.
            if !closing { router?.close() }
        } else if value == .started {
            finishPending(error: nil)
        }
    }

    private func finishPending(error message: String?) {
        deadline?.cancel(); deadline = nil
        pending = nil
        error = message
    }

    private func armDeadline() {
        deadline?.cancel()
        let delay = timeoutNanoseconds
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.close(reason: "等待对方确认超时，已停止选角。请离开后重新进入房间。")
        }
    }
}
