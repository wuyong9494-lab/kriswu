import Foundation

/// Combat wire protocol shared by the existing authenticated direct room.
/// This adapter never claims transport ownership or runs a timer.
public enum DuelNetworkCombatWire {
    public static let namespace = "shift.fighter.combat"
    public static let maximumBytes = 12_288

    public enum Body: Codable {
        case input(DuelNetworkInputs.Message)
        case state(DuelNetworkCombatState)
        case leave
    }

    public struct Envelope: Codable {
        public let namespace: String
        public let version: Int
        public let body: Body
        public init(_ body: Body) {
            namespace = DuelNetworkCombatWire.namespace
            version = DuelNetworkCombatState.version
            self.body = body
        }
    }

    public static func encode(_ body: Body) -> Data? {
        guard let data = try? JSONEncoder().encode(Envelope(body)),
              data.count <= maximumBytes else { return nil }
        return data
    }

    public static func decode(_ data: Data) -> Body? {
        guard data.count <= maximumBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.namespace == namespace,
              envelope.version == DuelNetworkCombatState.version else { return nil }
        return envelope.body
    }
}

/// Host is the sole simulation authority. GameRoom must supply authenticated
/// sender IDs and must not forward client-provided IDs as trusted identities.
public struct DuelSnapshotCombatHost: Sendable {
    public private(set) var simulation: DuelNetworkHostSimulation
    public let hostID: String
    public let guestID: String

    public init(simulation: DuelNetworkHostSimulation) {
        self.simulation = simulation
        hostID = simulation.inputs.hostID
        guestID = simulation.inputs.guestID
    }

    @discardableResult
    public mutating func receive(_ data: Data, authenticatedSenderID: String) -> Bool {
        guard let body = DuelNetworkCombatWire.decode(data) else { return false }
        switch body {
        case .input(let message):
            return simulation.receive(message, authenticatedSenderID: authenticatedSenderID,
                                      localPlayerID: hostID) == .applied
        case .leave:
            guard authenticatedSenderID == guestID else { return false }
            return simulation.disconnect(playerID: guestID, localPlayerID: hostID) == .applied
        case .state:
            // Guests cannot supply authoritative world state.
            return false
        }
    }

    /// Called once per fixed 60 Hz host simulation tick, not per display refresh.
    /// Send returned bytes to the guest over the authenticated direct channel.
    public mutating func step() throws -> Data {
        _ = try simulation.step(localPlayerID: hostID)
        guard let data = DuelNetworkCombatWire.encode(.state(.init(simulation: simulation))) else {
            throw Failure.stateEncoding
        }
        return data
    }

    public enum Failure: Error { case stateEncoding }
}

/// Guest never simulates authoritative hits. It sends only its own input and
/// consumes authenticated host snapshots for presentation.
public struct DuelNetworkCombatGuest: Sendable {
    public private(set) var replica: DuelNetworkCombatReplica
    public let guestID: String
    private var sequence: UInt64 = 0

    public init(sessionID: String, hostID: String, guestID: String) {
        replica = .init(sessionID: sessionID, hostID: hostID)
        self.guestID = guestID
    }

    public mutating func input(tick: UInt64, epoch: UInt64 = 0,
                               move: Int = 0, vertical: Int = 0,
                               guardHeld: Bool = false, tapBits: Int = 0,
                               weaponCommand: DuelWeaponCommand? = nil) -> Data? {
        guard sequence < UInt64.max else { return nil }
        let next = sequence + 1
        let message = DuelNetworkInputs.Message(sessionID: replica.sessionID, epoch: epoch,
            sequence: next, tick: tick, move: move, vertical: vertical,
            guardHeld: guardHeld, tapBits: tapBits, weaponCommand: weaponCommand)
        guard let data = DuelNetworkCombatWire.encode(.input(message)) else { return nil }
        sequence = next
        return data
    }

    @discardableResult
    public mutating func receive(_ data: Data, authenticatedSenderID: String) -> DuelNetworkCombatReplica.Outcome {
        guard let body = DuelNetworkCombatWire.decode(data) else { return .rejected }
        guard case .state(let state) = body,
              let encoded = try? JSONEncoder().encode(state) else { return .rejected }
        return replica.receive(encoded, authenticatedSenderID: authenticatedSenderID)
    }
}
