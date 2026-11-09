import Foundation

/// Read-only guest projection. Establish identity/session from a trusted room
/// handshake BEFORE accepting bytes. This never creates simulation authority.
public struct DuelMultiplayerReplica: Equatable, Sendable {
    public static let maximumSnapshotBytes = 16_384
    public enum Failure: Error, Equatable, Sendable {
        case oversized, malformed, wrongHost, unsupportedVersion, wrongSession
        case invalidRoster, invalidState, invalidTransition
    }
    public enum Outcome: Equatable, Sendable {
        case applied, ignoredStaleRevision
        case rejected(Failure)
    }
    private let sessionID: String
    private let hostID: String
    private let guestID: String
    public private(set) var snapshot: DuelMultiplayerSelection.Snapshot?

    public init(sessionID: String, hostID: String, guestID: String) throws {
        // Reuse trusted-handshake input validation, not network-decoded authority.
        _ = try DuelMultiplayerSelection(sessionID: sessionID, hostID: hostID, guestID: guestID)
        self.sessionID = sessionID
        self.hostID = hostID
        self.guestID = guestID
    }

    /// Authentication must be supplied by the transport-bound callback.
    @discardableResult
    public mutating func receive(_ data: Data, authenticatedSenderID: String) -> Outcome {
        guard authenticatedSenderID == hostID else { return .rejected(.wrongHost) }
        guard data.count <= Self.maximumSnapshotBytes else { return .rejected(.oversized) }
        guard let incoming = try? JSONDecoder().decode(DuelMultiplayerSelection.Snapshot.self, from: data) else {
            return .rejected(.malformed)
        }
        guard incoming.version == DuelMultiplayerSelection.protocolVersion else { return .rejected(.unsupportedVersion) }
        guard incoming.sessionID == sessionID else { return .rejected(.wrongSession) }
        guard incoming.players.count == 2,
              incoming.players[0].id == hostID, incoming.players[0].seat == .host,
              incoming.players[1].id == guestID, incoming.players[1].seat == .guest else {
            return .rejected(.invalidRoster)
        }
        guard incoming.selectionRevision <= incoming.revision,
              incoming.players.allSatisfy({ $0.choice == nil || $0.choice?.isValid == true }) else {
            return .rejected(.invalidState)
        }
        guard incoming.players.allSatisfy({ player in
            player.choice == nil || (player.lastSequence > 0 && incoming.selectionRevision > 0)
        }), incoming.revision > 0 || incoming.players.allSatisfy({ $0.lastSequence == 0 }) else {
            return .rejected(.invalidState)
        }
        let bothChosen = incoming.players.allSatisfy { $0.choice != nil }
        guard !incoming.players.contains(where: { $0.isReady }) || incoming.hasDistinctChoices else { return .rejected(.invalidState) }
        switch incoming.phase {
        case .selecting: break
        case .started:
            guard bothChosen, incoming.players.allSatisfy({ $0.isReady }) else { return .rejected(.invalidState) }
        case .disconnected:
            guard incoming.players.allSatisfy({ $0.choice == nil && !$0.isReady }) else { return .rejected(.invalidState) }
        }
        if let previous = snapshot {
            guard incoming.revision > previous.revision else { return .ignoredStaleRevision }
            guard previous.phase != .disconnected,
                  previous.phase != .started || incoming.phase == .disconnected,
                  incoming.selectionRevision >= previous.selectionRevision else {
                return .rejected(.invalidTransition)
            }
            // Only the host can issue Start, and every accepted command consumes
            // a newer sender sequence, even when other snapshots were skipped.
            if incoming.phase == .started && incoming.players[0].lastSequence <= previous.players[0].lastSequence {
                return .rejected(.invalidTransition)
            }
            let changedSelections = incoming.selectionRevision > previous.selectionRevision
            for index in previous.players.indices {
                let old = previous.players[index], new = incoming.players[index]
                guard new.lastSequence >= old.lastSequence else { return .rejected(.invalidTransition) }
                if incoming.phase == .disconnected { continue }
                // There is no deselect command. Only terminal disconnect clears
                // an established choice, regardless of claimed counter advances.
                guard old.choice == nil || new.choice != nil else { return .rejected(.invalidTransition) }
                guard old.choice == new.choice || (changedSelections && new.lastSequence > old.lastSequence) else {
                    return .rejected(.invalidTransition)
                }
                // A fresh Ready after ANY selection change needs a fresh player command.
                if new.isReady && (changedSelections || !old.isReady) && new.lastSequence <= old.lastSequence {
                    return .rejected(.invalidTransition)
                }
                if !changedSelections && old.isReady != new.isReady && new.lastSequence <= old.lastSequence {
                    return .rejected(.invalidTransition)
                }
            }
        } else {
            // A start is not an initial handshake. Show selection before accepting Start.
            guard incoming.phase == .selecting else { return .rejected(.invalidTransition) }
        }
        snapshot = incoming
        return .applied
    }
}
