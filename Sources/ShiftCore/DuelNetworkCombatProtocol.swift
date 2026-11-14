import Foundation

/// Reliable, ordered host-to-guest **consumed** input frames. This is not an
/// input-request protocol, snapshot restore format, or authenticated transport.
public enum DuelNetworkCombatProtocol {
    public static let namespace = "fighter.combat-frames"
    public static let protocolVersion = 1
    public static let maximumMessageBytes = 32_768
    public static let maximumFrames = 32
    public static let maximumIdentifierBytes = 256

    public enum Failure: Error, Equatable, Sendable {
        case notCommitted, wrongRole, incompatible, configurationMismatch
        case missingCatalog, invalidCatalog, invalidIdentifier
        case oversized, malformed, wrongNamespace, unsupportedVersion
        case wrongSession, wrongStart, wrongSender, closed
        case invalidSequence, sequenceGap, staleSequence, conflictingDuplicate, sequenceExhausted
        case invalidBatch, invalidInput, noncontiguousTicks, tickGap, tickExhausted
        case invalidTerminalState, terminalStateMismatch
    }
    public enum Outcome: Equatable, Sendable {
        case applied, ignoredDuplicate
        case rejected(Failure)
        /// A correctly routed/authenticated host changed epoch. No frames are
        /// applied; the replica closes and clears buffered commands permanently.
        case terminatedForEpochChange
    }
    public enum Phase: Equatable, Sendable { case active, closed }

    /// Decode raw scalar fields, never DuelGame.Input: its decoder clamps
    /// directions and supplies defaults. Every nonoptional wire field is required.
    public struct Input: Equatable, Codable, Sendable {
        public let move: Int
        public let vertical: Int
        public let guardHeld: Bool
        public let tapBits: Int
        public let weaponCommand: DuelWeaponCommand?
        public let rangedHeld: Bool?

        public init(move: Int = 0, vertical: Int = 0, guardHeld: Bool = false,
                    tapBits: Int = 0, weaponCommand: DuelWeaponCommand? = nil, rangedHeld: Bool = false) {
            self.move = move; self.vertical = vertical; self.guardHeld = guardHeld
            self.tapBits = tapBits; self.weaponCommand = weaponCommand
            self.rangedHeld = rangedHeld ? true : nil
        }

        init(consumed input: DuelGame.Input) {
            self.init(move: input.move, vertical: input.vertical, guardHeld: input.guardHeld,
                      tapBits: input.taps.rawValue, weaponCommand: input.weaponCommand, rangedHeld: input.rangedHeld)
        }

        var valid: Bool {
            guard (-1...1).contains(move), (-1...1).contains(vertical),
                  (0...63).contains(tapBits) else { return false }
            let attacks = tapBits & 62
            guard attacks == 0 || (attacks & (attacks - 1)) == 0 else { return false }
            guard weaponCommand == nil || tapBits == 0 else { return false }
            return !guardHeld || (tapBits == 0 && weaponCommand == nil && rangedHeld != true)
        }

        /// Used only after validating the entire envelope/batch.
        var gameInput: DuelGame.Input {
            .init(move: move, guardHeld: guardHeld, taps: .init(rawValue: tapBits),
                  vertical: vertical, weaponCommand: weaponCommand, rangedHeld: rangedHeld == true)
        }
    }

    public struct Frame: Equatable, Codable, Sendable {
        public let tick: UInt64
        public let host: Input
        public let guest: Input

        public init(tick: UInt64, host: Input, guest: Input) {
            self.tick = tick; self.host = host; self.guest = guest
        }

        init(consumed frame: DuelNetworkInputs.Frame) {
            self.init(tick: frame.tick, host: .init(consumed: frame.host), guest: .init(consumed: frame.guest))
        }
    }

    public enum Command: Equatable, Codable, Sendable {
        case frames([Frame])
        case cancel
    }

    public struct Message: Equatable, Codable, Sendable {
        public let namespace: String
        public let version: Int
        public let sessionID: String
        public let startID: String
        public let epoch: UInt64
        /// Positive, contiguous host-only sequence, separate from lobby/start/
        /// input counters. A fresh stream starts at one; gaps are not skipped.
        public let sequence: UInt64
        public let command: Command
        /// Optional additive field for legacy envelope decoding. New hosts attach
        /// it to terminal frames in this SAME reliable, authenticated envelope.
        /// It is compared with local replay, never installed as authoritative state.
        public let terminalState: DuelNetworkCombatState?

        public init(sessionID: String, startID: String, epoch: UInt64 = 0,
                    sequence: UInt64, command: Command,
                    version: Int = DuelNetworkCombatProtocol.protocolVersion,
                    namespace: String = DuelNetworkCombatProtocol.namespace,
                    terminalState: DuelNetworkCombatState? = nil) {
            self.namespace = namespace; self.version = version
            self.sessionID = sessionID; self.startID = startID; self.epoch = epoch
            self.sequence = sequence; self.command = command
            self.terminalState = terminalState
        }

        /// Checks collection and scalar bounds before encoding. The transport
        /// must also cap the outer packet and enforce a rate/timeout policy.
        public func encoded() throws -> Data {
            try validate()
            let data = try JSONEncoder().encode(self)
            guard data.count <= DuelNetworkCombatProtocol.maximumMessageBytes else { throw Failure.oversized }
            return data
        }

        func validate() throws {
            guard namespace == DuelNetworkCombatProtocol.namespace else { throw Failure.wrongNamespace }
            guard version == DuelNetworkCombatProtocol.protocolVersion else { throw Failure.unsupportedVersion }
            guard DuelNetworkCombatProtocol.validIdentifier(sessionID),
                  DuelNetworkCombatProtocol.validIdentifier(startID) else { throw Failure.invalidIdentifier }
            guard sequence > 0 else { throw Failure.invalidSequence }
            switch command {
            case .cancel:
                guard terminalState == nil else { throw Failure.invalidTerminalState }
            case .frames(let frames):
                guard !frames.isEmpty, frames.count <= DuelNetworkCombatProtocol.maximumFrames else {
                    throw Failure.invalidBatch
                }
                for (index, frame) in frames.enumerated() {
                    guard frame.host.valid, frame.guest.valid else { throw Failure.invalidInput }
                    // nextTick must remain representable after every step.
                    guard frame.tick < UInt64.max else { throw Failure.tickExhausted }
                    if index > 0, frame.tick != frames[index - 1].tick + 1 { throw Failure.noncontiguousTicks }
                }
                if let terminalState {
                    // Do not impose the alternate renderer's pose/name bounds
                    // on verified catalogs. Envelope bytes are capped; replay
                    // compares EVERY decoded value to its exact local projection.
                    guard terminalState.version == DuelNetworkCombatState.version,
                          terminalState.phase == .matchOver, terminalState.fighters.count == 2,
                          terminalState.winner == 0 || terminalState.winner == 1,
                          terminalState.wins.map({ $0.count == 2 }) ?? true,
                          terminalState.sessionID == sessionID, terminalState.epoch == epoch,
                          terminalState.tick == frames[frames.count - 1].tick + 1 else {
                        throw Failure.invalidTerminalState
                    }
                }
            }
        }
    }

    /// This verifies structure and the caller's compatibility assertion, not
    /// asset bytes or fingerprints. Only a local live barrier can supply commit.
    static func configuration(from barrier: DuelNetworkStartBarrier, host: Bool,
                              loadedCompatibility: DuelNetworkStartBarrier.Compatibility,
                              catalog: DuelWeaponCatalog?) throws -> DuelNetworkStartBarrier.Configuration {
        guard barrier.phase == .committed, let configuration = barrier.committedConfiguration else {
            throw Failure.notCommitted
        }
        guard barrier.localPlayerID == (host ? barrier.hostID : barrier.guestID) else { throw Failure.wrongRole }
        guard loadedCompatibility == configuration.compatibility else { throw Failure.incompatible }
        guard let catalog else { throw Failure.missingCatalog }
        do { try catalog.validate() } catch { throw Failure.invalidCatalog }
        guard catalog.profile(for: configuration.host.choice.hero)?.id == configuration.host.choice.weapon.rawValue,
              catalog.profile(for: configuration.guest.choice.hero)?.id == configuration.guest.choice.weapon.rawValue else {
            throw Failure.invalidCatalog
        }
        return configuration
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.utf8.count <= maximumIdentifierBytes
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

/// Optional local diagnostic record. Compare the WHOLE record at the same stream
/// boundary, not gameBytes alone. No decoder, state restoration, hash, signature,
/// peer authentication or cross-platform determinism guarantee is provided.
/// Full canonical equipped state can be large; generate on demand off the UI
/// thread from an immutable copy, never as an automatic per-tick wire payload.
public struct DuelNetworkCombatVerification: Equatable, Sendable {
    public let configuration: DuelNetworkStartBarrier.Configuration
    public let epoch: UInt64
    public let nextTick: UInt64
    public let lastSequence: UInt64
    public let phase: DuelNetworkCombatProtocol.Phase
    public let gameBytes: Data
}
