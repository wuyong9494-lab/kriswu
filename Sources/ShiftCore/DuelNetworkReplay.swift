import Foundation

/// Encapsulates the existing host simulation so only inputs it actually consumed
/// can become authoritative wire frames. There is no caller-supplied frame API.
/// Supply a trusted host barrier, its exact started selection, and the same
/// independently verified catalog/assets used for its local load confirmation.
public struct DuelNetworkCombatHost: Equatable, Sendable {
    public typealias Wire = DuelNetworkCombatProtocol
    public let configuration: DuelNetworkStartBarrier.Configuration
    public private(set) var phase = Wire.Phase.active
    public private(set) var lastSequence: UInt64 = 0
    private var simulation: DuelNetworkHostSimulation

    public var game: DuelGame { simulation.game }
    public var nextTick: UInt64 { simulation.inputs.nextTick }
    public var epoch: UInt64 { simulation.inputs.epoch }

    public init(committed barrier: DuelNetworkStartBarrier,
                started snapshot: DuelMultiplayerSelection.Snapshot,
                loadedCompatibility: DuelNetworkStartBarrier.Compatibility,
                catalog: DuelWeaponCatalog?) throws {
        let configuration = try Wire.configuration(from: barrier, host: true,
                                                   loadedCompatibility: loadedCompatibility, catalog: catalog)
        guard snapshot.sessionID == configuration.sessionID,
              snapshot.revision == configuration.snapshotRevision,
              snapshot.selectionRevision == configuration.selectionRevision,
              snapshot.players.count == 2,
              snapshot.players[0].id == configuration.host.id,
              snapshot.players[1].id == configuration.guest.id,
              snapshot.players[0].choice == configuration.host.choice,
              snapshot.players[1].choice == configuration.guest.choice else {
            throw Wire.Failure.configurationMismatch
        }
        simulation = try DuelNetworkHostSimulation(started: snapshot, localPlayerID: configuration.host.id,
                                                   catalog: catalog, seed: configuration.seed)
        self.configuration = configuration
    }

    /// Input requests remain a separate host inbox protocol. Transport identity
    /// is supplied separately; arrival/lease decisions are made only by the host.
    @discardableResult
    public mutating func receive(_ message: DuelNetworkInputs.Message,
                                 authenticatedSenderID: String) -> DuelNetworkInputs.Outcome {
        simulation.receive(message, authenticatedSenderID: authenticatedSenderID,
                           localPlayerID: configuration.host.id)
    }

    /// Advance at most one bounded batch. Validation/encoding failure leaves the
    /// entire host unchanged. Cache/resend the returned message on uncertain
    /// delivery; calling advance again creates NEW ticks and a NEW sequence.
    public mutating func advance(frameCount: Int = 1) throws -> Wire.Message {
        guard phase == .active else { throw Wire.Failure.closed }
        guard (1...Wire.maximumFrames).contains(frameCount) else { throw Wire.Failure.invalidBatch }
        guard lastSequence < UInt64.max else { throw Wire.Failure.sequenceExhausted }
        guard UInt64(frameCount) <= UInt64.max - nextTick else { throw Wire.Failure.tickExhausted }
        var next = simulation
        var frames: [Wire.Frame] = []
        frames.reserveCapacity(frameCount)
        for _ in 0..<frameCount {
            frames.append(.init(consumed: try next.step(localPlayerID: configuration.host.id)))
        }
        let message = Wire.Message(sessionID: configuration.sessionID, startID: configuration.startID,
                                   epoch: epoch, sequence: lastSequence + 1, command: .frames(frames))
        _ = try message.encoded()
        simulation = next; lastSequence = message.sequence
        return message
    }

    /// Optional ordered terminal notification. If delivery or encoding fails,
    /// still call cancel locally. No guest acknowledgement is implied here.
    public mutating func makeCancellation() throws -> Wire.Message {
        guard phase == .active else { throw Wire.Failure.closed }
        guard lastSequence < UInt64.max else { throw Wire.Failure.sequenceExhausted }
        let message = Wire.Message(sessionID: configuration.sessionID, startID: configuration.startID,
                                   epoch: epoch, sequence: lastSequence + 1, command: .cancel)
        _ = try message.encoded()
        cancel(); lastSequence = message.sequence
        return message
    }

    /// Pause/app interruption is TERMINAL in protocol 1. There is intentionally
    /// no resume or epoch-switch API. A fresh session/start/barrier is required.
    @discardableResult
    public mutating func interrupt() -> Wire.Outcome { cancel() }

    @discardableResult
    public mutating func cancel() -> Wire.Outcome {
        guard phase == .active else { return .rejected(.closed) }
        _ = simulation.cancel(localPlayerID: configuration.host.id)
        phase = .closed
        return .applied
    }

    @discardableResult
    public mutating func disconnect(playerID: String) -> Wire.Outcome {
        guard playerID == configuration.host.id || playerID == configuration.guest.id else {
            return .rejected(.wrongSender)
        }
        return cancel()
    }

    public func verificationState() throws -> DuelNetworkCombatVerification {
        .init(configuration: configuration, epoch: epoch, nextTick: nextTick,
              lastSequence: lastSequence, phase: phase, gameBytes: try DuelReplayStateEncoding.encode(game))
    }
}

/// Reliable host-frame replay, not client prediction or snapshot reconciliation.
/// No local tick, input, timer or missing-packet fallback can advance this game.
/// Construct from the guest's locally committed barrier, not a decoded DTO.
public struct DuelNetworkReplay: Equatable, Sendable {
    public typealias Wire = DuelNetworkCombatProtocol
    public let configuration: DuelNetworkStartBarrier.Configuration
    public let epoch: UInt64 = 0
    public private(set) var game: DuelGame
    public private(set) var phase = Wire.Phase.active
    public private(set) var nextTick: UInt64 = 0
    public private(set) var lastSequence: UInt64 = 0
    private var lastMessage: Wire.Message?

    public init(committed barrier: DuelNetworkStartBarrier,
                loadedCompatibility: DuelNetworkStartBarrier.Compatibility,
                catalog: DuelWeaponCatalog?) throws {
        let configuration = try Wire.configuration(from: barrier, host: false,
                                                   loadedCompatibility: loadedCompatibility, catalog: catalog)
        let game = DuelGame(hero: configuration.host.choice.hero,
                            difficulty: configuration.difficulty, mode: configuration.mode,
                            seed: configuration.seed, opponentHero: configuration.guest.choice.hero,
                            weaponCatalog: catalog)
        guard game.weaponFight != nil else { throw Wire.Failure.invalidCatalog }
        self.configuration = configuration; self.game = game
    }

    /// Bounds bytes BEFORE decoding and validates ALL raw fields before stepping.
    /// Gaps, malformed frames and conflicting retries change neither simulation
    /// nor counters. Only the immediately previous identical message is retained
    /// for duplicate recognition; older sequences are rejected, never replayed.
    @discardableResult
    public mutating func receive(_ data: Data, authenticatedSenderID: String) -> Wire.Outcome {
        guard authenticatedSenderID == configuration.host.id else { return .rejected(.wrongSender) }
        guard data.count <= Wire.maximumMessageBytes else { return .rejected(.oversized) }
        guard let message = try? JSONDecoder().decode(Wire.Message.self, from: data) else {
            return .rejected(.malformed)
        }
        do { try message.validate() }
        catch let failure as Wire.Failure { return .rejected(failure) }
        catch { return .rejected(.malformed) }
        guard message.sessionID == configuration.sessionID else { return .rejected(.wrongSession) }
        guard message.startID == configuration.startID else { return .rejected(.wrongStart) }
        // A retry of the terminal message is harmless too. Local teardown can
        // also recognize the last frame, but can never apply another frame.
        if message == lastMessage { return .ignoredDuplicate }
        guard phase == .active else { return .rejected(.closed) }
        guard message.epoch == epoch else {
            cancel()
            return .terminatedForEpochChange
        }
        guard message.sequence != lastSequence else { return .rejected(.conflictingDuplicate) }
        guard message.sequence > lastSequence else { return .rejected(.staleSequence) }
        guard lastSequence < UInt64.max else { return .rejected(.sequenceExhausted) }
        guard message.sequence == lastSequence + 1 else { return .rejected(.sequenceGap) }
        switch message.command {
        case .cancel:
            cancel()
        case .frames(let frames):
            guard frames[0].tick == nextTick else { return .rejected(.tickGap) }
            // validate() proved nonempty, bounded, valid inputs, contiguous ticks,
            // and representable nextTick. Both seats are ALWAYS explicit.
            for frame in frames { game.step(frame.host.gameInput, opponent: frame.guest.gameInput) }
            nextTick = frames[frames.count - 1].tick + 1
        }
        lastSequence = message.sequence; lastMessage = message
        return .applied
    }

    @discardableResult
    public mutating func interrupt() -> Wire.Outcome { cancel() }

    @discardableResult
    public mutating func cancel() -> Wire.Outcome {
        guard phase == .active else { return .rejected(.closed) }
        game.cancelBufferedInputs(); phase = .closed
        return .applied
    }

    @discardableResult
    public mutating func disconnect(playerID: String) -> Wire.Outcome {
        guard playerID == configuration.host.id || playerID == configuration.guest.id else {
            return .rejected(.wrongSender)
        }
        return cancel()
    }

    public func verificationState() throws -> DuelNetworkCombatVerification {
        .init(configuration: configuration, epoch: epoch, nextTick: nextTick,
              lastSequence: lastSequence, phase: phase, gameBytes: try DuelReplayStateEncoding.encode(game))
    }
}
