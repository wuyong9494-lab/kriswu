import Foundation

/// Transport-independent, host-authoritative pre-match selection only.
/// Callers MUST derive sender IDs from authenticated transport peers, not payload fields.
/// This is not a combat synchronizer or a replacement for GameRoom.
public struct DuelMultiplayerSelection: Equatable, Sendable {
    public static let protocolVersion = 1

    public enum Weapon: String, Codable, Sendable {
        case katana = "sun_katana"
        case ninjato = "sun_triad"
        case hammers = "liu_hammers"
        case pangu = "liu_pangu"
    }

    public struct Choice: Equatable, Codable, Sendable {
        public let hero: DuelGame.Hero
        public let weapon: Weapon
        public init(hero: DuelGame.Hero, weapon: Weapon) {
            self.hero = hero
            self.weapon = weapon
        }
        public var isValid: Bool {
            (hero == .ember && (weapon == .katana || weapon == .ninjato)) ||
                (hero == .liu && (weapon == .hammers || weapon == .pangu))
        }
        public static let sun = Self(hero: .ember, weapon: .katana)
        public static let sunTriad = Self(hero: .ember, weapon: .ninjato)
        public static let liu = Self(hero: .liu, weapon: .hammers)
        public static let liuPangu = Self(hero: .liu, weapon: .pangu)

        /// Select only weapons in the exact loaded catalog. Adding a supported
        /// identifier must not relabel, replace, or unlock the legacy assets.
        public static func available(in catalog: DuelWeaponCatalog) -> [Self] {
            guard (try? catalog.validate()) != nil else { return [] }
            return catalog.profiles.compactMap { profile in
                guard let weapon = Weapon(rawValue: profile.id) else { return nil }
                let choice = Self(hero: profile.hero, weapon: weapon)
                return choice.isValid ? choice : nil
            }
        }
    }

    public enum Seat: Int, Codable, Sendable { case host = 0, guest = 1 }
    public enum Phase: String, Codable, Sendable { case selecting, started, disconnected }
    public enum Command: Equatable, Codable, Sendable {
        case select(Choice)
        /// The revision of BOTH selections displayed when the player pressed Ready.
        case ready(Bool, selectionRevision: UInt64)
        case start(selectionRevision: UInt64)
    }

    public struct Message: Equatable, Codable, Sendable {
        public let version: Int
        public let sessionID: String
        /// Strictly increasing per transport identity within one session; starts at 1.
        public let sequence: UInt64
        public let command: Command
        public init(sessionID: String, sequence: UInt64, command: Command,
                    version: Int = DuelMultiplayerSelection.protocolVersion) {
            self.version = version
            self.sessionID = sessionID
            self.sequence = sequence
            self.command = command
        }
    }

    public struct Player: Equatable, Codable, Sendable {
        public let id: String
        public let seat: Seat
        public fileprivate(set) var choice: Choice?
        public fileprivate(set) var isReady: Bool
        public fileprivate(set) var lastSequence: UInt64
    }

    /// Value DTO for a later host-to-guest adapter. Never decode this directly into
    /// reducer authority. Guests must validate version, session, host and revision.
    public struct Snapshot: Equatable, Codable, Sendable {
        public let version: Int
        public let sessionID: String
        public fileprivate(set) var revision: UInt64
        public fileprivate(set) var selectionRevision: UInt64
        public fileprivate(set) var phase: Phase
        /// Always host first, guest second, independent of member-list ordering.
        public fileprivate(set) var players: [Player]
        public var hasDistinctChoices: Bool {
            players.count == 2 && players.allSatisfy({ $0.choice?.isValid == true })
                && players[0].choice?.hero != players[1].choice?.hero
        }
        public var canStart: Bool {
            phase == .selecting && hasDistinctChoices && players.allSatisfy {
                $0.choice?.isValid == true && $0.isReady
            }
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        case invalidRoster, invalidSession, notHost, unsupportedVersion, wrongSession
        case unknownPlayer, invalidSequence, invalidChoice, staleSelection, missingSelection
        case notReady, conflictingChoices, closed, revisionExhausted
    }
    public enum Outcome: Equatable, Sendable {
        case applied
        /// Duplicate or reordered delivery: no state changes, including readiness.
        case ignoredStaleSequence
        case rejected(Failure)
    }

    public private(set) var snapshot: Snapshot
    public var hostID: String { snapshot.players[0].id }

    /// Create once after the transport establishes exactly two distinct peers.
    /// Use a fresh unpredictable session ID on every reconnect/rematch/host change.
    public init(sessionID: String, hostID: String, guestID: String) throws {
        guard !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.invalidSession
        }
        guard !hostID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !guestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              hostID != guestID else { throw Failure.invalidRoster }
        snapshot = Snapshot(version: Self.protocolVersion, sessionID: sessionID,
                            revision: 0, selectionRevision: 0, phase: .selecting,
                            players: [Player(id: hostID, seat: .host, choice: nil,
                                             isReady: false, lastSequence: 0),
                                      Player(id: guestID, seat: .guest, choice: nil,
                                             isReady: false, lastSequence: 0)])
    }

    /// Invoke only on the authoritative host. Invalid messages never consume a
    /// sequence number. A newer accepted command supersedes all older commands.
    @discardableResult
    public mutating func apply(_ message: Message, authenticatedSenderID: String,
                               localPlayerID: String) -> Outcome {
        guard localPlayerID == hostID else { return .rejected(.notHost) }
        guard message.version == Self.protocolVersion else { return .rejected(.unsupportedVersion) }
        guard message.sessionID == snapshot.sessionID else { return .rejected(.wrongSession) }
        guard let index = snapshot.players.firstIndex(where: { $0.id == authenticatedSenderID }) else {
            return .rejected(.unknownPlayer)
        }
        guard message.sequence > 0 else { return .rejected(.invalidSequence) }
        guard message.sequence > snapshot.players[index].lastSequence else { return .ignoredStaleSequence }
        guard snapshot.phase == .selecting else { return .rejected(.closed) }
        guard snapshot.revision < UInt64.max else { return .rejected(.revisionExhausted) }

        switch message.command {
        case .select(let choice):
            guard choice.isValid else { return .rejected(.invalidChoice) }
            if snapshot.players[index].choice != choice {
                guard snapshot.selectionRevision < UInt64.max else { return .rejected(.revisionExhausted) }
                snapshot.players[index].choice = choice
                snapshot.selectionRevision += 1
                // Both players must approve the new matchup, not just the chooser.
                for i in snapshot.players.indices { snapshot.players[i].isReady = false }
            }
        case .ready(let ready, let revision):
            guard revision == snapshot.selectionRevision else { return .rejected(.staleSelection) }
            guard snapshot.players.allSatisfy({ $0.choice != nil }) else {
                return .rejected(.missingSelection)
            }
            guard !ready || snapshot.hasDistinctChoices else { return .rejected(.conflictingChoices) }
            snapshot.players[index].isReady = ready
        case .start(let revision):
            guard authenticatedSenderID == hostID else { return .rejected(.notHost) }
            guard revision == snapshot.selectionRevision else { return .rejected(.staleSelection) }
            if snapshot.players.allSatisfy({ $0.choice != nil }) && !snapshot.hasDistinctChoices {
                return .rejected(.conflictingChoices)
            }
            guard snapshot.canStart else { return .rejected(.notReady) }
            snapshot.phase = .started
        }
        snapshot.players[index].lastSequence = message.sequence
        snapshot.revision += 1
        return .applied
    }

    /// Trusted local transport event, NOT a client command. Host loss also ends
    /// the session; no implicit host migration or reuse of stale Ready messages.
    @discardableResult
    public mutating func disconnect(playerID: String, localPlayerID: String) -> Outcome {
        guard localPlayerID == hostID else { return .rejected(.notHost) }
        guard snapshot.players.contains(where: { $0.id == playerID }) else {
            return .rejected(.unknownPlayer)
        }
        guard snapshot.phase != .disconnected else { return .rejected(.closed) }
        // The terminal state is always reached, even at revision exhaustion.
        snapshot.phase = .disconnected
        for i in snapshot.players.indices {
            snapshot.players[i].choice = nil
            snapshot.players[i].isReady = false
        }
        if snapshot.revision < UInt64.max { snapshot.revision += 1 }
        if snapshot.selectionRevision < UInt64.max { snapshot.selectionRevision += 1 }
        return .applied
    }
}
