import Foundation

/// One authenticated room lease shared by explicit, non-overlapping protocols.
/// Keep this router alive across selection/start/combat; closing a channel does
/// not release the room. No matchmaking, sign-in, simulation, or room lifecycle.
@MainActor
final class DuelNetworkMessageRouter {
    enum Phase: CaseIterable, Hashable {
        case selection, start, combat

        var namespace: String {
            switch self {
            case .selection: return DuelNetworkLobby.namespace
            case .start: return DuelNetworkStartBarrier.namespace
            case .combat: return DuelNetworkCombatProtocol.namespace
            }
        }
        var version: Int {
            switch self {
            case .selection: return DuelMultiplayerSelection.protocolVersion
            case .start: return DuelNetworkStartBarrier.protocolVersion
            case .combat: return DuelNetworkCombatProtocol.protocolVersion
            }
        }
        var maximumBytes: Int {
            switch self {
            case .selection: return DuelNetworkLobby.maximumEnvelopeBytes
            case .start: return DuelNetworkStartBarrier.maximumMessageBytes
            case .combat: return DuelNetworkCombatProtocol.maximumMessageBytes
            }
        }
    }
    enum Failure: Error, Equatable { case invalidRoom, callbackBusy, alreadyAttached, closed }
    enum Status: Equatable { case idle, attached, closed }
    nonisolated static let maximumPacketBytes = max(DuelNetworkLobby.maximumEnvelopeBytes,
        max(DuelNetworkStartBarrier.maximumMessageBytes, DuelNetworkCombatProtocol.maximumMessageBytes))

    private struct Header: Decodable {
        let namespace: String
        let version: Int
    }
    private(set) var status: Status = .idle
    private let transport: any DuelLobbyTransport
    private var rootOwner: UUID?
    private var snapshot: DuelLobbyRoomState
    private var channels: [Phase: Channel] = [:]

    /// Construction never claims callbacks or sends traffic.
    init(transport: any DuelLobbyTransport) {
        self.transport = transport
        snapshot = transport.state
    }

    deinit {
        let transport = transport, owner = rootOwner
        let channels = Array(channels.values), state = Self.closedState(snapshot)
        Task { @MainActor in
            // All states become closed before any consumer receives a callback.
            channels.forEach { $0.remember(state) }
            if let owner { transport.release(owner) }
            channels.forEach { $0.finishClosing() }
        }
    }

    /// Stable endpoints, each with one independent callback lease. Retain the
    /// router itself; an endpoint intentionally does not keep the root alive.
    func channel(for phase: Phase) -> Channel {
        if let existing = channels[phase] { return existing }
        let channel = Channel(router: self, phase: phase, state: snapshot)
        channels[phase] = channel
        return channel
    }

    /// Claim the existing, ready two-player fighter room exactly once.
    func attach() throws {
        guard status != .closed else { throw Failure.closed }
        guard status == .idle else { throw Failure.alreadyAttached }
        let initial = transport.state
        guard Self.valid(initial) else { throw Failure.invalidRoom }
        let token = UUID()
        guard transport.claim(token, receive: { [weak self] data, sender in
            guard self?.rootOwner == token else { return }
            self?.receive(data, sender: sender)
        }, changed: { [weak self] in
            guard self?.rootOwner == token else { return }
            self?.roomChanged()
        }) else { throw Failure.callbackBusy }
        rootOwner = token; snapshot = initial; status = .attached
        // A transport may settle to a different room during claim().
        guard refreshRoom() else { throw Failure.invalidRoom }
    }

    /// Terminal and synchronous. Never leaves or disconnects the caller's room.
    /// Consumers observe ready == false even if the underlying room stays ready.
    func close() {
        guard status != .closed else { return }
        let owner = rootOwner
        rootOwner = nil; status = .closed
        snapshot = Self.closedState(transport.state)
        let endpoints = Phase.allCases.compactMap { channels[$0] }
        endpoints.forEach { $0.remember(snapshot) }
        if let owner { transport.release(owner) }
        // Release may re-enter; the root token and all endpoint states are
        // already invalid. A callback can release another endpoint safely.
        endpoints.forEach { $0.finishClosing() }
    }

    private var state: DuelLobbyRoomState {
        _ = refreshRoom()
        return status == .attached ? snapshot : Self.closedState(snapshot)
    }

    /// Room observations can lag a packet. Check identity at every boundary,
    /// including reads, claims, sends, and receives, rather than relying on them.
    @discardableResult
    private func refreshRoom() -> Bool {
        guard status == .attached, rootOwner != nil else { return false }
        let current = transport.state
        guard Self.valid(current), current.localID == snapshot.localID,
              current.hostID == snapshot.hostID,
              Set(current.members) == Set(snapshot.members) else {
            close(); return false
        }
        // Member ordering is not seat identity; hostID defines the host seat.
        snapshot = current
        channels.values.forEach { $0.remember(current) }
        return true
    }

    private func roomChanged() {
        guard refreshRoom() else { return }
        let observers = Phase.allCases.compactMap { phase -> (Channel, UUID)? in
            guard let channel = channels[phase], let token = channel.leaseToken else { return nil }
            return (channel, token)
        }
        // One observer may close the router or replace another observer.
        for (channel, token) in observers { channel.notifyChanged(token) }
    }

    private func receive(_ data: Data, sender: String) {
        guard refreshRoom(), sender != snapshot.localID, snapshot.members.contains(sender),
              let phase = Self.phase(of: data) else { return }
        // Preserve both the original bytes and transport-authenticated identity.
        // Unclaimed namespaces are dropped, never broadcast or queued.
        channels[phase]?.deliver(data, sender: sender)
    }

    private func send(_ data: Data, from channel: Channel) {
        guard refreshRoom(), channels[channel.phase] === channel, channel.owner != nil,
              Self.phase(of: data) == channel.phase else { return }
        transport.sendReliable(data) // No local receive/loopback.
    }

    private static func phase(of data: Data) -> Phase? {
        // Check the outer bound BEFORE parsing even the namespace. Then apply
        // the selected protocol's smaller limit and exact supported version.
        guard !data.isEmpty, data.count <= maximumPacketBytes,
              let header = try? JSONDecoder().decode(Header.self, from: data),
              let phase = Phase.allCases.first(where: { $0.namespace == header.namespace }),
              header.version == phase.version, data.count <= phase.maximumBytes else { return nil }
        return phase
    }

    private static func valid(_ state: DuelLobbyRoomState) -> Bool {
        state.isFighter && state.capacity == 2 && state.ready
            && state.members.count == 2 && Set(state.members).count == 2
            && state.members.allSatisfy {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 256
            }
            && state.members.contains(state.localID)
            && state.hostID.map { state.members.contains($0) } == true
    }

    nonisolated private static func closedState(_ state: DuelLobbyRoomState) -> DuelLobbyRoomState {
        .init(isFighter: state.isFighter, capacity: state.capacity, ready: false,
              localID: state.localID, hostID: state.hostID, members: state.members)
    }

    @MainActor
    final class Channel: DuelLobbyTransport {
        fileprivate let phase: Phase
        private weak var router: DuelNetworkMessageRouter?
        private var lastState: DuelLobbyRoomState
        private struct Lease {
            let token = UUID()
            let owner: UUID
            let receive: (Data, String) -> Void
            let changed: () -> Void
        }
        private var lease: Lease?
        fileprivate var owner: UUID? { lease?.owner }
        fileprivate var leaseToken: UUID? { lease?.token }

        fileprivate init(router: DuelNetworkMessageRouter, phase: Phase, state: DuelLobbyRoomState) {
            self.router = router; self.phase = phase; lastState = state
        }
        var state: DuelLobbyRoomState {
            router?.state ?? DuelNetworkMessageRouter.closedState(lastState)
        }
        func claim(_ owner: UUID, receive: @escaping (Data, String) -> Void,
                   changed: @escaping () -> Void) -> Bool {
            guard let router, router.refreshRoom(), lease == nil else { return false }
            lease = .init(owner: owner, receive: receive, changed: changed)
            return true
        }
        func release(_ owner: UUID) {
            guard lease?.owner == owner else { return }
            lease = nil
        }
        func sendReliable(_ data: Data) {
            guard lease != nil else { return }
            router?.send(data, from: self)
        }
        fileprivate func remember(_ state: DuelLobbyRoomState) { lastState = state }
        fileprivate func deliver(_ data: Data, sender: String) {
            guard router?.status == .attached else { return }
            lease?.receive(data, sender)
        }
        fileprivate func notifyChanged(_ token: UUID) {
            guard router?.status == .attached, lease?.token == token else { return }
            lease?.changed()
        }
        fileprivate func finishClosing() {
            let previous = lease
            lease = nil
            previous?.changed()
        }
    }
}
