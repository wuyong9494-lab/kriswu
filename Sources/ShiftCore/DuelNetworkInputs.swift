import Foundation

/// Host-only input scheduling, not a transport or rollback implementation.
/// Sender/local identities MUST come from trusted transport/session ownership.
public struct DuelNetworkInputs: Equatable, Sendable {
    public static let protocolVersion = 1
    public static let futureWindow: UInt64 = 6
    public static let lateWindow: UInt64 = 2
    public static let heldLeaseTicks = 3
    public static let queueLimit = 7

    /// Decode raw fields here, never through Input's direction-clamping decoder.
    public struct Message: Equatable, Codable, Sendable {
        public let version: Int
        public let sessionID: String
        public let epoch: UInt64
        public let sequence: UInt64
        public let tick: UInt64
        public let move: Int
        public let vertical: Int
        public let guardHeld: Bool
        public let tapBits: Int
        public let weaponCommand: DuelWeaponCommand?

        public init(sessionID: String, epoch: UInt64 = 0, sequence: UInt64, tick: UInt64,
                    move: Int = 0, vertical: Int = 0, guardHeld: Bool = false,
                    tapBits: Int = 0, weaponCommand: DuelWeaponCommand? = nil,
                    version: Int = DuelNetworkInputs.protocolVersion) {
            self.version = version; self.sessionID = sessionID; self.epoch = epoch
            self.sequence = sequence; self.tick = tick; self.move = move
            self.vertical = vertical; self.guardHeld = guardHeld
            self.tapBits = tapBits; self.weaponCommand = weaponCommand
        }

        fileprivate var valid: Bool {
            guard (-1...1).contains(move), (-1...1).contains(vertical),
                  (0...63).contains(tapBits) else { return false }
            // Jump may accompany one laboratory attack; competing attacks may not.
            let attacks = tapBits & 62
            guard attacks == 0 || (attacks & (attacks - 1)) == 0 else { return false }
            guard weaponCommand == nil || tapBits == 0 else { return false }
            return !guardHeld || (tapBits == 0 && weaponCommand == nil)
        }
        fileprivate var input: DuelGame.Input {
            .init(move: move, guardHeld: guardHeld, taps: .init(rawValue: tapBits),
                  vertical: vertical, weaponCommand: weaponCommand)
        }
    }

    public enum Phase: Equatable, Sendable { case active, paused, closed }
    public enum Failure: Error, Equatable, Sendable {
        case invalidRoster, invalidSession, notHost, unknownPlayer, unsupportedVersion
        case wrongSession, wrongEpoch, invalidSequence, invalidInput, outsideTickWindow
        case conflictingTick, queueFull, inactive, tickExhausted, epochExhausted
    }
    public enum Outcome: Equatable, Sendable {
        case applied, ignoredStaleSequence
        case rejected(Failure)
    }
    public struct Frame: Equatable, Sendable {
        public let tick: UInt64
        public let host: DuelGame.Input
        public let guest: DuelGame.Input
    }
    private struct Peer: Equatable, Sendable {
        var sequence: UInt64 = 0
        var lastScheduledTick: UInt64?
        var queue: [UInt64: Message] = [:]
        var held = DuelGame.Input.neutral
        var lease = 0
    }
    public let sessionID: String
    public let hostID: String
    public let guestID: String
    public private(set) var epoch: UInt64 = 0
    public private(set) var nextTick: UInt64 = 0
    public private(set) var phase = Phase.active
    private var peers = [Peer(), Peer()]

    /// Use the started lobby's pinned roster, and a fresh unpredictable session ID
    /// on rematch/reconnect/host change. This type cannot authenticate callers.
    public init(sessionID: String, hostID: String, guestID: String) throws {
        guard !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.invalidSession
        }
        guard !hostID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !guestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              hostID != guestID else { throw Failure.invalidRoster }
        self.sessionID = sessionID; self.hostID = hostID; self.guestID = guestID
    }

    /// Rejections are atomic, including sequence state. Increasing sequences with
    /// decreasing/equal scheduled ticks are rejected, never merged or overwritten.
    @discardableResult
    public mutating func receive(_ message: Message, authenticatedSenderID: String,
                                 localPlayerID: String) -> Outcome {
        guard localPlayerID == hostID else { return .rejected(.notHost) }
        guard authenticatedSenderID == hostID || authenticatedSenderID == guestID else {
            return .rejected(.unknownPlayer)
        }
        guard message.version == Self.protocolVersion else { return .rejected(.unsupportedVersion) }
        guard message.sessionID == sessionID else { return .rejected(.wrongSession) }
        guard message.epoch == epoch else { return .rejected(.wrongEpoch) }
        guard phase == .active else { return .rejected(.inactive) }
        let index = authenticatedSenderID == hostID ? 0 : 1
        guard message.sequence > 0 else { return .rejected(.invalidSequence) }
        guard message.sequence > peers[index].sequence else { return .ignoredStaleSequence }
        guard message.valid else { return .rejected(.invalidInput) }
        if message.tick >= nextTick {
            guard message.tick - nextTick <= Self.futureWindow else { return .rejected(.outsideTickWindow) }
        } else {
            guard nextTick - message.tick <= Self.lateWindow else { return .rejected(.outsideTickWindow) }
        }
        let scheduled = max(nextTick, message.tick)
        if let previous = peers[index].lastScheduledTick, scheduled <= previous {
            return .rejected(.conflictingTick)
        }
        guard peers[index].queue.count < Self.queueLimit else { return .rejected(.queueFull) }
        peers[index].queue[scheduled] = message
        peers[index].sequence = message.sequence
        peers[index].lastScheduledTick = scheduled
        return .applied
    }

    /// Call exactly once for each host simulation step. Pass BOTH returned inputs
    /// to game.step(frame.host, opponent: frame.guest), never nil (which enables AI).
    public mutating func consume(localPlayerID: String) throws -> Frame {
        guard localPlayerID == hostID else { throw Failure.notHost }
        guard phase == .active else { throw Failure.inactive }
        guard nextTick < UInt64.max else { throw Failure.tickExhausted }
        var inputs: [DuelGame.Input] = []
        for i in peers.indices {
            if let message = peers[i].queue.removeValue(forKey: nextTick) {
                let input = message.input
                peers[i].held = .init(move: input.move, guardHeld: input.guardHeld, vertical: input.vertical)
                peers[i].lease = Self.heldLeaseTicks - 1
                inputs.append(input)
            } else if peers[i].lease > 0 {
                inputs.append(peers[i].held)
                peers[i].lease -= 1
            } else {
                peers[i].held = .neutral
                inputs.append(.neutral)
            }
        }
        let result = Frame(tick: nextTick, host: inputs[0], guest: inputs[1])
        nextTick += 1
        return result
    }

    /// Trusted host lifecycle events, not commands decoded from peer payloads.
    /// Every pause invalidates queued AND in-flight old-epoch inputs. Sequences
    /// remain increasing across resume; a transport must distribute the new epoch.
    @discardableResult
    public mutating func pause(localPlayerID: String) -> Outcome {
        guard localPlayerID == hostID else { return .rejected(.notHost) }
        guard phase == .active else { return .rejected(.inactive) }
        clear()
        guard epoch < UInt64.max else {
            phase = .closed
            return .rejected(.epochExhausted)
        }
        epoch += 1; phase = .paused
        return .applied
    }

    @discardableResult
    public mutating func resume(localPlayerID: String) -> Outcome {
        guard localPlayerID == hostID else { return .rejected(.notHost) }
        guard phase == .paused else { return .rejected(.inactive) }
        phase = .active
        return .applied
    }

    @discardableResult
    public mutating func cancel(localPlayerID: String) -> Outcome {
        guard localPlayerID == hostID else { return .rejected(.notHost) }
        clear(); phase = .closed
        return .applied
    }

    @discardableResult
    public mutating func disconnect(playerID: String, localPlayerID: String) -> Outcome {
        guard localPlayerID == hostID else { return .rejected(.notHost) }
        guard playerID == hostID || playerID == guestID else { return .rejected(.unknownPlayer) }
        return cancel(localPlayerID: localPlayerID)
    }

    private mutating func clear() {
        for i in peers.indices {
            peers[i].queue.removeAll(); peers[i].held = .neutral; peers[i].lease = 0
            peers[i].lastScheduledTick = nil
        }
    }
}
