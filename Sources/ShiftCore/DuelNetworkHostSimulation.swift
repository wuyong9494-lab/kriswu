import Foundation

/// Local host-side integration only: no transport, client simulation or wire state.
/// Supply the trusted lobby's started snapshot, never an arbitrary peer's DTO.
public struct DuelNetworkHostSimulation: Equatable, Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case unsupportedVersion, invalidSession, invalidRoster, notHost
        case notStarted, invalidState, conflictingChoices, missingCatalog, invalidCatalog
    }
    public let seed: UInt64
    public private(set) var game: DuelGame
    public private(set) var inputs: DuelNetworkInputs

    /// IDs are pinned in host/guest seat order; neither sorting nor fallback
    /// heroes/catalogs are allowed. Codable decoding alone proves no authority.
    public init(started snapshot: DuelMultiplayerSelection.Snapshot, localPlayerID: String,
                catalog: DuelWeaponCatalog?, seed: UInt64) throws {
        guard snapshot.version == DuelMultiplayerSelection.protocolVersion else { throw Failure.unsupportedVersion }
        guard !snapshot.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.invalidSession
        }
        guard snapshot.players.count == 2,
              snapshot.players[0].seat == .host, snapshot.players[1].seat == .guest,
              snapshot.players[0].id != snapshot.players[1].id,
              snapshot.players.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw Failure.invalidRoster
        }
        guard localPlayerID == snapshot.players[0].id else { throw Failure.notHost }
        guard snapshot.phase == .started else { throw Failure.notStarted }
        // At least two Select commands, two Ready commands and one host Start.
        guard snapshot.selectionRevision >= 2, snapshot.revision >= 5,
              snapshot.selectionRevision <= snapshot.revision - 3,
              snapshot.players[0].lastSequence >= 3, snapshot.players[1].lastSequence >= 2,
              snapshot.players.allSatisfy({ $0.isReady && $0.choice?.isValid == true }) else {
            throw Failure.invalidState
        }
        guard snapshot.hasDistinctChoices else { throw Failure.conflictingChoices }
        guard let catalog else { throw Failure.missingCatalog }
        do { try catalog.validate() } catch { throw Failure.invalidCatalog }
        guard let hostChoice = snapshot.players[0].choice, let guestChoice = snapshot.players[1].choice,
              catalog.profile(for: hostChoice.hero)?.id == hostChoice.weapon.rawValue,
              catalog.profile(for: guestChoice.hero)?.id == guestChoice.weapon.rawValue else {
            throw Failure.invalidCatalog
        }
        let game = DuelGame(hero: hostChoice.hero, difficulty: .learning, mode: .versus,
                            seed: seed, opponentHero: guestChoice.hero, weaponCatalog: catalog)
        guard game.weaponFight != nil else { throw Failure.invalidCatalog }
        self.game = game; self.seed = seed
        inputs = try DuelNetworkInputs(sessionID: snapshot.sessionID,
                                       hostID: snapshot.players[0].id, guestID: snapshot.players[1].id)
    }

    @discardableResult
    public mutating func receive(_ message: DuelNetworkInputs.Message, authenticatedSenderID: String,
                                 localPlayerID: String) -> DuelNetworkInputs.Outcome {
        inputs.receive(message, authenticatedSenderID: authenticatedSenderID, localPlayerID: localPlayerID)
    }

    /// Exactly one inbox frame per step. Even absent/expired guest input is
    /// explicitly neutral, never nil: the existing game's bot is never selected.
    @discardableResult
    public mutating func step(localPlayerID: String) throws -> DuelNetworkInputs.Frame {
        let frame = try inputs.consume(localPlayerID: localPlayerID)
        game.step(frame.host, opponent: frame.guest)
        return frame
    }

    @discardableResult
    public mutating func pause(localPlayerID: String) -> DuelNetworkInputs.Outcome {
        let outcome = inputs.pause(localPlayerID: localPlayerID)
        if outcome == .applied || outcome == .rejected(.epochExhausted) { game.cancelBufferedInputs() }
        return outcome
    }

    @discardableResult
    public mutating func resume(localPlayerID: String) -> DuelNetworkInputs.Outcome {
        inputs.resume(localPlayerID: localPlayerID)
    }

    @discardableResult
    public mutating func cancel(localPlayerID: String) -> DuelNetworkInputs.Outcome {
        let outcome = inputs.cancel(localPlayerID: localPlayerID)
        if outcome == .applied { game.cancelBufferedInputs() }
        return outcome
    }

    @discardableResult
    public mutating func disconnect(playerID: String, localPlayerID: String) -> DuelNetworkInputs.Outcome {
        let outcome = inputs.disconnect(playerID: playerID, localPlayerID: localPlayerID)
        if outcome == .applied { game.cancelBufferedInputs() }
        return outcome
    }
}
