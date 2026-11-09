import Foundation
import Combine

/// Selection only. No combat clock, matchmaking, sign-in, or transport startup.
@MainActor
protocol DuelLobbyTransport: AnyObject, Sendable {
    var state: DuelLobbyRoomState { get }
    func claim(_ owner: UUID, receive: @escaping (Data, String) -> Void,
               changed: @escaping () -> Void) -> Bool
    func release(_ owner: UUID)
    func sendReliable(_ data: Data)
}

struct DuelLobbyRoomState: Equatable {
    let isFighter: Bool
    let capacity: Int
    let ready: Bool
    let localID: String
    let hostID: String?
    let members: [String]
}

/// Explicitly wrap an already-established GameRoom. Never calls start/leave.
@MainActor
final class DuelGameRoomTransport: DuelLobbyTransport {
    private let room: GameRoom
    private var changes: AnyCancellable?
    private var observationOwner: UUID?
    init(room: GameRoom) { self.room = room }
    var state: DuelLobbyRoomState {
        .init(isFighter: room.kind == .fighter, capacity: room.capacity,
              ready: room.phase == .ready, localID: room.me.id,
              hostID: room.hostID, members: room.members.map(\.id))
    }
    func claim(_ owner: UUID, receive: @escaping (Data, String) -> Void,
               changed: @escaping () -> Void) -> Bool {
        guard room.installAuthenticatedDirect(owner: owner, callback: receive) else { return false }
        observationOwner = owner
        changes = Publishers.CombineLatest3(room.$phase, room.$members, room.$hostID)
            .dropFirst().sink { [weak self] _ in
                // Published fires before assignment. Inspect the settled room.
                Task { @MainActor [weak self] in
                    guard self?.room.ownsAuthenticatedDirect(owner) == true else { return }
                    changed()
                }
            }
        return true
    }
    func release(_ owner: UUID) {
        room.removeAuthenticatedDirect(owner: owner)
        if observationOwner == owner {
            changes?.cancel(); changes = nil; observationOwner = nil
        }
    }
    func sendReliable(_ data: Data) { room.sendDirect(data, delivery: .reliable) }
}

@MainActor
final class DuelNetworkLobby: ObservableObject {
    typealias Selection = DuelMultiplayerSelection
    nonisolated static let maximumEnvelopeBytes = 24_576
    nonisolated static let namespace = "shift.fighter.selection"
    enum Failure: Error, Equatable { case invalidRoom, callbackBusy, alreadyAttached }
    enum Status: Equatable { case idle, connecting, selecting, started, closed }
    struct Envelope: Codable {
        let namespace: String
        let version: Int
        let body: Body
        init(_ body: Body) {
            namespace = DuelNetworkLobby.namespace
            version = Selection.protocolVersion
            self.body = body
        }
    }
    enum Body: Codable {
        case available(sessionID: String)
        case request(nonce: String)
        case ended(nonce: String)
        case snapshot(Selection.Snapshot, nonce: String?)
        case command(Selection.Message)
    }
    @Published private(set) var snapshot: Selection.Snapshot?
    @Published private(set) var status: Status = .idle
    private let transport: any DuelLobbyTransport
    private var owner: UUID?
    private var pinned: DuelLobbyRoomState?
    private var authority: Selection?
    private var replica: DuelMultiplayerReplica?
    private var nonce: String?
    private var sequence: UInt64 = 0
    private var guestNonce: String?
    private var retiredGuestNonces: Set<String> = []

    init(transport: any DuelLobbyTransport) { self.transport = transport }
    convenience init(room: GameRoom) { self.init(transport: DuelGameRoomTransport(room: room)) }
    deinit {
        // Explicit shutdown is synchronous; forgotten teardown still releases
        // the lease on the actor, without retaining this coordinator.
        let transport = transport, owner = owner
        Task { @MainActor in
            if let owner { transport.release(owner) }
        }
    }

    /// Only explicit attachment claims callbacks and may send selection traffic.
    func attach() throws {
        guard owner == nil else { throw Failure.alreadyAttached }
        let state = transport.state
        guard state.isFighter, state.capacity == 2, state.ready,
              state.members.count == 2, Set(state.members).count == 2,
              state.members.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 256 }),
              state.members.contains(state.localID), let host = state.hostID,
              state.members.contains(host), let guest = state.members.first(where: { $0 != host }) else {
            throw Failure.invalidRoom
        }
        let token = UUID()
        guard transport.claim(token, receive: { [weak self] data, sender in
            guard self?.owner == token else { return }
            self?.receive(data, sender: sender)
        }, changed: { [weak self] in
            guard self?.owner == token else { return }
            self?.checkRoom()
        }) else { throw Failure.callbackBusy }
        owner = token; pinned = state; sequence = 0; snapshot = nil
        status = .connecting
        if state.localID == host {
            authority = try Selection(sessionID: UUID().uuidString, hostID: host, guestID: guest)
            publish(authority!.snapshot)
            send(.available(sessionID: authority!.snapshot.sessionID))
        } else {
            nonce = UUID().uuidString
            send(.request(nonce: nonce!))
        }
    }

    /// Clears protocol state and only callbacks still owned by this attachment.
    /// Does not disconnect the caller-owned room. Reattach creates a new session.
    func shutdown() {
        let previousOwner = owner
        owner = nil; pinned = nil; authority = nil; replica = nil; nonce = nil
        sequence = 0; snapshot = nil; guestNonce = nil; retiredGuestNonces.removeAll(); status = .closed
        if let previousOwner { transport.release(previousOwner) }
    }

    private func checkRoom() {
        guard let pinned else { return }
        let current = transport.state
        guard current.isFighter, current.capacity == 2, current.ready,
              current.localID == pinned.localID, current.hostID == pinned.hostID,
              current.members.count == 2, Set(current.members) == Set(pinned.members) else {
            shutdown(); return
        }
    }

    /// Both host UI commands and remote guest commands pass through apply().
    @discardableResult
    func submit(_ command: Selection.Command) -> Bool {
        checkRoom()
        guard let pinned, let snapshot, snapshot.phase == .selecting,
              sequence < UInt64.max else { return false }
        sequence += 1
        let message = Selection.Message(sessionID: snapshot.sessionID, sequence: sequence, command: command)
        if pinned.localID == pinned.hostID {
            return apply(message, sender: pinned.localID)
        }
        if case .start = command { return false }
        send(.command(message))
        return true // Queued, not an optimistic local mutation or host acceptance.
    }

    private func receive(_ data: Data, sender: String) {
        checkRoom()
        guard let pinned, sender != pinned.localID, pinned.members.contains(sender),
              data.count <= Self.maximumEnvelopeBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.namespace == Self.namespace,
              envelope.version == Selection.protocolVersion else { return }
        switch envelope.body {
        case .available(let sessionID):
            guard pinned.localID != pinned.hostID, sender == pinned.hostID,
                  UUID(uuidString: sessionID) != nil else { return }
            if let snapshot {
                // No implicit rematch or replacement of a guest's pinned session.
                // Host reattachment invalidates the old selection immediately.
                if snapshot.sessionID != sessionID { shutdown() }
            } else if let nonce {
                // Covers guest-first attachment without timers or fresh nonces.
                send(.request(nonce: nonce))
            }
        case .request(let requestNonce):
            guard pinned.localID == pinned.hostID, UUID(uuidString: requestNonce) != nil,
                  authority != nil, !retiredGuestNonces.contains(requestNonce) else { return }
            if let previous = guestNonce, previous != requestNonce {
                // A newly attached guest starts at sequence 1. Never feed it the
                // previous session's counters or a terminal Started snapshot.
                guard retiredGuestNonces.count < 64 else {
                    send(.ended(nonce: requestNonce)); shutdown(); return
                }
                retiredGuestNonces.insert(previous)
                guard let fresh = try? Selection(sessionID: UUID().uuidString,
                                                  hostID: pinned.localID, guestID: sender) else { return }
                authority = fresh; sequence = 0
                guestNonce = requestNonce
                publish(fresh.snapshot)
            } else {
                guestNonce = requestNonce
            }
            if let authority { send(.snapshot(authority.snapshot, nonce: requestNonce)) }
        case .ended(let responseNonce):
            guard sender == pinned.hostID, pinned.localID != pinned.hostID,
                  nonce == responseNonce else { return }
            shutdown()
        case .command(let message):
            guard authority != nil else { return }
            if !apply(message, sender: sender), let authority {
                // Even rejected/stale commands receive the current truth. A guest
                // never assumes its queued command was accepted by the host.
                send(.snapshot(authority.snapshot, nonce: nil))
            }
        case .snapshot(let incoming, let responseNonce):
            guard pinned.localID != pinned.hostID, sender == pinned.hostID,
                  UUID(uuidString: incoming.sessionID) != nil,
                  let bytes = try? JSONEncoder().encode(incoming) else { return }
            if replica == nil {
                guard let nonce, responseNonce == nonce, let host = pinned.hostID,
                      let candidate = try? DuelMultiplayerReplica(sessionID: incoming.sessionID,
                                                                 hostID: host, guestID: pinned.localID) else { return }
                var validated = candidate
                guard validated.receive(bytes, authenticatedSenderID: sender) == .applied else { return }
                replica = validated; self.nonce = nil
                publish(incoming)
            } else {
                guard replica?.receive(bytes, authenticatedSenderID: sender) == .applied else { return }
                publish(incoming)
            }
        }
    }

    private func apply(_ message: Selection.Message, sender: String) -> Bool {
        guard let pinned, authority?.apply(message, authenticatedSenderID: sender,
                                          localPlayerID: pinned.localID) == .applied,
              let snapshot = authority?.snapshot else { return false }
        publish(snapshot)
        send(.snapshot(snapshot, nonce: nil))
        return true
    }
    private func publish(_ value: Selection.Snapshot) {
        snapshot = value
        switch value.phase {
        case .selecting: status = .selecting
        case .started: status = .started // Selection agreement only, never start simulation.
        case .disconnected: status = .closed
        }
    }
    private func send(_ body: Body) {
        guard owner != nil, let data = try? JSONEncoder().encode(Envelope(body)),
              data.count <= Self.maximumEnvelopeBytes else { return }
        transport.sendReliable(data)
    }
}
