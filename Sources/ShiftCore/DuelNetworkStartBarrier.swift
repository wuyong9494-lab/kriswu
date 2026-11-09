import Foundation

/// One-shot, transport-independent load barrier after selection has started.
/// Identity and fingerprints are assertions from a trusted adapter, not authentication.
/// This type neither constructs nor advances a simulation, and is not Codable authority.
public struct DuelNetworkStartBarrier: Equatable, Sendable {
    public static let protocolVersion = 1
    public static let namespace = "fighter.combat-start"
    public static let maximumMessageBytes = 8_192
    public static let maximumIdentifierBytes = 256

    /// The caller must calculate these lowercase SHA-256 digests from its verified
    /// rules/build manifest and complete loaded catalog/assets, using a shared recipe.
    /// Equality here does not calculate a hash or establish that bytes were loaded.
    public struct Compatibility: Equatable, Codable, Sendable {
        public let selectionProtocolVersion: Int
        public let inputProtocolVersion: Int
        public let rulesFingerprint: String
        public let catalogFingerprint: String
        public init(rulesFingerprint: String, catalogFingerprint: String,
                    selectionProtocolVersion: Int = DuelMultiplayerSelection.protocolVersion,
                    inputProtocolVersion: Int = DuelNetworkInputs.protocolVersion) {
            self.selectionProtocolVersion = selectionProtocolVersion
            self.inputProtocolVersion = inputProtocolVersion
            self.rulesFingerprint = rulesFingerprint; self.catalogFingerprint = catalogFingerprint
        }
        fileprivate var valid: Bool {
            selectionProtocolVersion == DuelMultiplayerSelection.protocolVersion
                && inputProtocolVersion == DuelNetworkInputs.protocolVersion
                && Self.isDigest(rulesFingerprint) && Self.isDigest(catalogFingerprint)
        }
        private static func isDigest(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }

    public struct Participant: Equatable, Codable, Sendable {
        public let id: String
        public let seat: DuelMultiplayerSelection.Seat
        public let choice: DuelMultiplayerSelection.Choice
    }

    /// Exactly the current equipped host-simulation rules. Mode/difficulty/tick
    /// rate are serialized and checked, never negotiated into unsupported values.
    public struct Configuration: Equatable, Codable, Sendable {
        public let sessionID: String
        public let startID: String
        public let snapshotRevision: UInt64
        public let selectionRevision: UInt64
        public let host: Participant
        public let guest: Participant
        public let compatibility: Compatibility
        public let seed: UInt64
        public let ticksPerSecond: Int
        public let mode: DuelGame.Mode
        public let difficulty: DuelGame.Difficulty
    }

    public enum Command: Equatable, Codable, Sendable {
        case offer(Configuration)
        case loaded(Configuration)
        case commit(Configuration)
        case cancel
    }
    public struct Message: Equatable, Codable, Sendable {
        public let namespace: String
        public let version: Int
        public let sessionID: String
        /// Separate from selection and combat-input sequences. Strictly increasing
        /// per pinned sender for this one-shot barrier. Positive values; gaps allowed.
        public let sequence: UInt64
        public let command: Command
        public init(sessionID: String, sequence: UInt64, command: Command,
                    version: Int = DuelNetworkStartBarrier.protocolVersion,
                    namespace: String = DuelNetworkStartBarrier.namespace) {
            self.namespace = namespace; self.version = version
            self.sessionID = sessionID; self.sequence = sequence; self.command = command
        }
        public func encoded() throws -> Data {
            let data = try JSONEncoder().encode(self)
            guard data.count <= DuelNetworkStartBarrier.maximumMessageBytes else { throw Failure.oversized }
            return data
        }
    }
    public enum Phase: Equatable, Sendable { case awaitingOffer, loading, committed, closed }
    public enum Failure: Error, Equatable, Sendable {
        case invalidSession, invalidRoster, invalidLocalPlayer, invalidSelection, invalidCompatibility
        case oversized, malformed, wrongNamespace, unsupportedVersion, wrongSession, wrongSender
        case notHost, invalidSequence, invalidConfiguration, incompatible, noOffer, alreadyOffered
        case configurationMismatch, alreadyLoaded, missingCatalog, invalidCatalog, notLoaded, closed
    }
    public enum Outcome: Equatable, Sendable {
        case applied, ignoredStaleSequence
        case rejected(Failure)
    }

    public let sessionID: String
    public let hostID: String
    public let guestID: String
    public let localPlayerID: String
    public let compatibility: Compatibility
    public private(set) var phase = Phase.awaitingOffer
    public private(set) var offeredConfiguration: Configuration?
    public private(set) var hostLoaded = false
    public private(set) var guestLoaded = false
    /// No configuration is exposed as committed until this endpoint's barrier passes.
    /// Cancellation/disconnect removes it, including after a previously successful start.
    public var committedConfiguration: Configuration? {
        phase == .committed ? offeredConfiguration : nil
    }
    private let selection: DuelMultiplayerSelection.Snapshot
    private var sequences: [UInt64] = [0, 0]

    /// Pin identities/session independently of the snapshot, from trusted room state.
    /// Host uses its reducer's snapshot; guest uses its validated selection replica.
    /// Decoding an arbitrary snapshot and supplying matching strings is not authority.
    public init(started snapshot: DuelMultiplayerSelection.Snapshot,
                sessionID: String, hostID: String, guestID: String,
                localPlayerID: String, compatibility: Compatibility) throws {
        guard Self.validIdentifier(sessionID) else { throw Failure.invalidSession }
        guard Self.validIdentifier(hostID), Self.validIdentifier(guestID), hostID != guestID else {
            throw Failure.invalidRoster
        }
        guard localPlayerID == hostID || localPlayerID == guestID else { throw Failure.invalidLocalPlayer }
        guard snapshot.version == DuelMultiplayerSelection.protocolVersion else { throw Failure.unsupportedVersion }
        guard snapshot.sessionID == sessionID else { throw Failure.wrongSession }
        guard snapshot.players.count == 2,
              snapshot.players[0].id == hostID, snapshot.players[0].seat == .host,
              snapshot.players[1].id == guestID, snapshot.players[1].seat == .guest else {
            throw Failure.invalidRoster
        }
        guard snapshot.phase == .started, snapshot.hasDistinctChoices,
              snapshot.players.allSatisfy({ $0.isReady }),
              snapshot.revision >= 5, snapshot.selectionRevision >= 2,
              snapshot.selectionRevision <= snapshot.revision - 3,
              snapshot.players[0].lastSequence >= 3, snapshot.players[1].lastSequence >= 2 else {
            throw Failure.invalidSelection
        }
        guard compatibility.valid else { throw Failure.invalidCompatibility }
        self.sessionID = sessionID; self.hostID = hostID; self.guestID = guestID
        self.localPlayerID = localPlayerID; self.compatibility = compatibility; selection = snapshot
    }

    /// Host chooses an explicit fresh start ID and seed. At most one offer per
    /// barrier/session. No default seed, fallback catalog or silent renegotiation.
    public mutating func makeOffer(startID: String, seed: UInt64, sequence: UInt64) throws -> Message {
        guard localPlayerID == hostID else { throw Failure.notHost }
        guard Self.validIdentifier(startID) else { throw Failure.invalidConfiguration }
        guard let host = selection.players[0].choice, let guest = selection.players[1].choice else {
            throw Failure.invalidSelection
        }
        let configuration = Configuration(
            sessionID: sessionID, startID: startID,
            snapshotRevision: selection.revision, selectionRevision: selection.selectionRevision,
            host: Participant(id: hostID, seat: .host, choice: host),
            guest: Participant(id: guestID, seat: .guest, choice: guest),
            compatibility: compatibility, seed: seed, ticksPerSecond: DuelGame.ticksPerSecond,
            mode: .versus, difficulty: .learning)
        return try emit(.offer(configuration), sequence: sequence)
    }

    /// Call only after verifying all actual assets and successfully loading this
    /// exact configuration. The catalog check covers structure/profile IDs, not
    /// content hashes or renderer resources. No raw wire packet can set local load.
    public mutating func confirmLoaded(configuration: Configuration, loadedCompatibility: Compatibility,
                                       catalog: DuelWeaponCatalog?, sequence: UInt64) throws -> Message {
        guard phase != .closed && phase != .committed else { throw Failure.closed }
        guard let offer = offeredConfiguration else { throw Failure.noOffer }
        guard configuration == offer else { throw Failure.configurationMismatch }
        guard loadedCompatibility == compatibility else { throw Failure.incompatible }
        guard let catalog else { throw Failure.missingCatalog }
        do { try catalog.validate() } catch { throw Failure.invalidCatalog }
        guard catalog.profile(for: offer.host.choice.hero)?.id == offer.host.choice.weapon.rawValue,
              catalog.profile(for: offer.guest.choice.hero)?.id == offer.guest.choice.weapon.rawValue else {
            throw Failure.invalidCatalog
        }
        return try emit(.loaded(configuration), sequence: sequence)
    }

    /// Returns the single reliable commit to deliver to the guest. Delivery is
    /// not proved by this return value, and no synchronized wall-clock is implied.
    public mutating func commit(sequence: UInt64) throws -> Message {
        guard localPlayerID == hostID else { throw Failure.notHost }
        guard let offer = offeredConfiguration else { throw Failure.noOffer }
        return try emit(.commit(offer), sequence: sequence)
    }

    /// Optional wire notification. If no sequence is left or sending fails, call
    /// cancel() anyway; terminal local shutdown never depends on packet delivery.
    public mutating func makeCancellation(sequence: UInt64) throws -> Message {
        try emit(.cancel, sequence: sequence)
    }

    /// Only the other pinned transport identity may supply incoming bytes.
    /// The host's own actions and each local load acknowledgement use methods above.
    @discardableResult
    public mutating func receive(_ data: Data, authenticatedSenderID: String) -> Outcome {
        let remoteID = localPlayerID == hostID ? guestID : hostID
        guard authenticatedSenderID == remoteID else { return .rejected(.wrongSender) }
        guard data.count <= Self.maximumMessageBytes else { return .rejected(.oversized) }
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else { return .rejected(.malformed) }
        return apply(message, senderID: authenticatedSenderID)
    }

    /// Trusted lifecycle event on either endpoint, including host loss. No
    /// migration, reopening, retry offer or restoration from a decoded DTO.
    @discardableResult
    public mutating func disconnect(playerID: String) -> Outcome {
        guard playerID == hostID || playerID == guestID else { return .rejected(.wrongSender) }
        return cancel()
    }

    @discardableResult
    public mutating func cancel() -> Outcome {
        guard phase != .closed else { return .rejected(.closed) }
        close()
        return .applied
    }

    private mutating func emit(_ command: Command, sequence: UInt64) throws -> Message {
        let message = Message(sessionID: sessionID, sequence: sequence, command: command)
        _ = try message.encoded() // Bound output before any state mutation.
        switch apply(message, senderID: localPlayerID) {
        case .applied: return message
        case .ignoredStaleSequence: throw Failure.invalidSequence
        case .rejected(let failure): throw failure
        }
    }

    private mutating func apply(_ message: Message, senderID: String) -> Outcome {
        guard message.namespace == Self.namespace else { return .rejected(.wrongNamespace) }
        guard message.version == Self.protocolVersion else { return .rejected(.unsupportedVersion) }
        guard message.sessionID == sessionID else { return .rejected(.wrongSession) }
        guard phase != .closed else { return .rejected(.closed) }
        guard message.sequence > 0 else { return .rejected(.invalidSequence) }
        let index = senderID == hostID ? 0 : 1
        guard message.sequence > sequences[index] else { return .ignoredStaleSequence }
        switch message.command {
        case .offer(let incoming):
            guard senderID == hostID else { return .rejected(.notHost) }
            guard phase == .awaitingOffer else { return .rejected(.alreadyOffered) }
            guard valid(incoming) else { return .rejected(.invalidConfiguration) }
            guard incoming.compatibility == compatibility else { return .rejected(.incompatible) }
            offeredConfiguration = incoming; phase = .loading
        case .loaded(let incoming):
            guard phase != .committed else { return .rejected(.closed) }
            guard let offer = offeredConfiguration else { return .rejected(.noOffer) }
            guard incoming == offer else { return .rejected(.configurationMismatch) }
            guard !(index == 0 ? hostLoaded : guestLoaded) else { return .rejected(.alreadyLoaded) }
            if index == 0 { hostLoaded = true } else { guestLoaded = true }
        case .commit(let incoming):
            guard senderID == hostID else { return .rejected(.notHost) }
            guard phase != .committed else { return .rejected(.closed) }
            guard let offer = offeredConfiguration else { return .rejected(.noOffer) }
            guard incoming == offer else { return .rejected(.configurationMismatch) }
            guard hostLoaded && guestLoaded else { return .rejected(.notLoaded) }
            phase = .committed
        case .cancel:
            close()
        }
        sequences[index] = message.sequence
        return .applied
    }

    private func valid(_ configuration: Configuration) -> Bool {
        configuration.sessionID == sessionID && Self.validIdentifier(configuration.startID)
            && configuration.snapshotRevision == selection.revision
            && configuration.selectionRevision == selection.selectionRevision
            && configuration.host.id == hostID && configuration.host.seat == .host
            && configuration.guest.id == guestID && configuration.guest.seat == .guest
            && configuration.host.choice == selection.players[0].choice
            && configuration.guest.choice == selection.players[1].choice
            && configuration.ticksPerSecond == DuelGame.ticksPerSecond
            && configuration.mode == .versus && configuration.difficulty == .learning
            && configuration.compatibility.valid
    }
    private static func validIdentifier(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.utf8.count <= maximumIdentifierBytes
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    private mutating func close() {
        offeredConfiguration = nil; hostLoaded = false; guestLoaded = false; phase = .closed
    }
}
