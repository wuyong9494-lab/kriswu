import Foundation
import Combine

/// Owns the authenticated GameRoom direct channel AFTER selection relinquishes
/// its lease. This is the transport-to-combat bridge, not a UI or a new room.
@MainActor
final class DuelNetworkCombatSession: ObservableObject {
    enum Status: Equatable { case idle, running, ended, failed }
    @Published private(set) var status: Status = .idle
    @Published private(set) var state: DuelNetworkCombatState?
    @Published private(set) var failure: String?

    private let room: GameRoom
    private let sessionID: String
    private let hostID: String
    private let guestID: String
    private var owner: UUID?
    private var host: DuelNetworkCombatHost?
    private var guest: DuelNetworkCombatGuest?
    private var clock: Task<Void, Never>?
    private var sequence: UInt64 = 0
    private var lastSentTick: UInt64?
    private var lastSentEpoch: UInt64?
    private var pendingAttack: (tapBits: Int, weaponCommand: DuelWeaponCommand?)?
    private var roomObservation: AnyCancellable?
    private var lastHostStateAt: Date?
    private var watchdog: Task<Void, Never>?

    init(room: GameRoom, started selection: DuelMultiplayerSelection.Snapshot,
         catalog: DuelWeaponCatalog?, seed: UInt64) throws {
        guard selection.phase == .started, selection.players.count == 2,
              selection.players[0].seat == .host, selection.players[1].seat == .guest,
              selection.players.contains(where: { $0.id == room.me.id }),
              room.kind == .fighter, room.capacity == 2,
              room.phase == .ready, room.hostID == selection.players[0].id,
              Set(room.members.map(\.id)) == Set(selection.players.map(\.id)) else {
            throw Failure.invalidRoom
        }
        self.room = room
        sessionID = selection.sessionID
        hostID = selection.players[0].id
        guestID = selection.players[1].id
        if room.me.id == hostID {
            let simulation = try DuelNetworkHostSimulation(started: selection,
                localPlayerID: hostID, catalog: catalog, seed: seed)
            host = DuelNetworkCombatHost(simulation: simulation)
        } else {
            guest = DuelNetworkCombatGuest(sessionID: selection.sessionID,
                hostID: hostID, guestID: guestID)
        }
    }

    enum Failure: Error { case invalidRoom, callbackBusy }

    /// Caller must invoke DuelNetworkLobby.shutdown() first. Never steal its
    /// callback while selection is still processing a Start acknowledgement.
    func start() throws {
        guard status == .idle else { return }
        let token = UUID()
        guard room.installAuthenticatedDirect(owner: token, callback: { [weak self] data, sender in
            self?.receive(data, sender: sender)
        }) else { throw Failure.callbackBusy }
        owner = token
        status = .running
        if let host {
            // The guest must receive a trustworthy first frame before it can
            // schedule inputs. Send this keyframe reliably at combat startup.
            let initial = DuelNetworkCombatState(simulation: host.simulation)
            state = initial
            if let bytes = DuelNetworkCombatWire.encode(.state(initial)) {
                room.sendDirect(bytes, delivery: .reliable)
            }
        }
        roomObservation = Publishers.CombineLatest3(room.$phase, room.$members, room.$hostID)
            .dropFirst().sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.verifyRoom() }
            }
        if guest != nil {
            lastHostStateAt = Date()
            watchdog = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                    catch { return }
                    guard let self, self.status == .running else { return }
                    if let last = self.lastHostStateAt,
                       Date().timeIntervalSince(last) > 5 {
                        self.failure = "超过 5 秒未收到房主战斗状态，请检查网络连接。"
                        self.status = .failed
                        self.stop()
                        return
                    }
                }
            }
        }
        if host != nil {
            clock = Task { @MainActor [weak self] in
                // The host alone advances 60 fixed steps per second.
                while !Task.isCancelled {
                    guard let self, self.status == .running else { return }
                    self.advanceHost()
                    try? await Task.sleep(nanoseconds: 16_666_667)
                }
            }
        }
    }

    /// Called by the local touch adapter. Inputs are never synthesized as AI.
    func sendInput(move: Int = 0, vertical: Int = 0, guardHeld: Bool = false,
                   tapBits: Int = 0, weaponCommand: DuelWeaponCommand? = nil) {
        guard status == .running, sequence < UInt64.max,
              (-1...1).contains(move), (-1...1).contains(vertical),
              (0...63).contains(tapBits) else { return }
        let attacks = tapBits & 62
        guard attacks == 0 || (attacks & (attacks - 1)) == 0 else { return }
        guard weaponCommand == nil || tapBits == 0 else { return }
        guard !guardHeld || (tapBits == 0 && weaponCommand == nil) else { return }
        let tick: UInt64
        let epoch: UInt64
        if let host {
            tick = host.simulation.inputs.nextTick
            epoch = host.simulation.inputs.epoch
        } else if let state {
            // Guest snapshots describe a past host tick. Schedule a few ticks
            // ahead to absorb transit latency rather than submitting input
            // that is already late by the time it reaches the host.
            let lead: UInt64 = 3
            guard state.tick <= UInt64.max - lead else { return }
            tick = state.tick + lead
            epoch = state.epoch
        } else { return }
        // A resumed host uses a new epoch: its scheduling window must not
        // inherit the previous epoch's tick reservation.
        if lastSentEpoch != epoch {
            lastSentTick = nil
            lastSentEpoch = epoch
        }
        let scheduledTick = max(tick, lastSentTick.map { $0 < UInt64.max ? $0 + 1 : $0 } ?? tick)
        guard scheduledTick >= tick, scheduledTick - tick <= DuelNetworkInputs.futureWindow else {
            // The guest has already reserved every available future tick.
            // Retain the latest discrete attack until the host clock advances.
            if tapBits != 0 || weaponCommand != nil {
                pendingAttack = (tapBits, weaponCommand)
            }
            return
        }
        let nextSequence = sequence + 1
        let message = DuelNetworkInputs.Message(sessionID: sessionID, epoch: epoch,
            sequence: nextSequence, tick: scheduledTick, move: move, vertical: vertical,
            guardHeld: guardHeld, tapBits: tapBits, weaponCommand: weaponCommand)
        guard let bytes = DuelNetworkCombatWire.encode(.input(message)) else { return }
        sequence = nextSequence
        lastSentTick = scheduledTick
        if tapBits != 0 || weaponCommand != nil { pendingAttack = nil }
        if var host {
            _ = host.receive(bytes, authenticatedSenderID: hostID)
            self.host = host
        } else {
            room.sendDirect(bytes, delivery: .reliable)
        }
    }

    private func advanceHost() {
        guard var host else { return }
        do {
            let bytes = try host.step()
            self.host = host
            state = .init(simulation: host.simulation)
            let terminal = state?.phase == .matchOver
            // Final results must be reliable; otherwise a lost last UDP-like
            // update leaves the guest waiting forever after the host stops.
            // Periodic reliable keyframes repair lost unreliable updates.
            let keyframe = terminal || host.simulation.inputs.nextTick % 30 == 0
            room.sendDirect(bytes, delivery: keyframe ? .reliable : .unreliable)
            if terminal { stop() }
        } catch {
            failure = "战斗模拟已停止。"
            status = .failed
            stop()
        }
    }

    private func receive(_ bytes: Data, sender: String) {
        guard status == .running else { return }
        if var host {
            guard sender == guestID else { return }
            _ = host.receive(bytes, authenticatedSenderID: sender)
            self.host = host
        } else if var guest {
            guard sender == hostID else { return }
            if guest.receive(bytes, authenticatedSenderID: sender) == .applied {
                lastHostStateAt = Date()
                state = guest.replica.latest
                if let pending = pendingAttack {
                    // Retry only after a new authoritative tick frees room in
                    // the bounded scheduling window; never fabricate extra taps.
                    sendInput(tapBits: pending.tapBits, weaponCommand: pending.weaponCommand)
                }
                if state?.phase == .matchOver { stop() }
            }
            self.guest = guest
        }
    }

    private func verifyRoom() {
        guard status == .running else { return }
        guard room.phase == .ready, room.hostID == hostID,
              Set(room.members.map(\.id)) == Set([hostID, guestID]) else {
            failure = "对方离开或房间身份发生变化，战斗已结束。"
            status = .failed
            stop()
            return
        }
    }

    func stop() {
        clock?.cancel(); clock = nil
        watchdog?.cancel(); watchdog = nil
        roomObservation?.cancel(); roomObservation = nil
        if let owner { room.removeAuthenticatedDirect(owner: owner) }
        owner = nil
        pendingAttack = nil
        lastSentTick = nil
        lastSentEpoch = nil
        if status == .running { status = .ended }
    }

    deinit { clock?.cancel() }
}
