import Foundation

/// Bounded, host-authored combat projection. Never decode a DuelGame from the
/// network: the host alone advances hit detection, damage and match results.
public struct DuelNetworkCombatState: Codable, Equatable, Sendable {
    public static let version = 1
    public static let maximumBytes = 8_192

    public struct Fighter: Codable, Equatable, Sendable {
        public let hero: DuelGame.Hero
        public let x: Int
        public let y: Int
        public let facing: Int
        public let health: Int
        public let guardMeter: Int
        public let energy: Int
        public let stun: Int
        public let knockdown: Int
        /// Host-selected source animation; clients may render but never decide hits.
        public let animation: Animation?
        public struct Animation: Codable, Equatable, Sendable {
            public let clip: String
            public let tick: Int
            public let duration: Int
            public let groundLift: Double
            public let reaction: Bool
            public init(_ pose: DuelWeaponPose) {
                clip = pose.clip; tick = pose.tick; duration = pose.duration
                groundLift = pose.groundLift; reaction = pose.reaction
            }
            public var isPlausible: Bool {
                !clip.isEmpty && clip.utf8.count <= 128 && (0...100_000).contains(tick)
                && (1...100_000).contains(duration) && tick <= duration
                && groundLift.isFinite && (-3...6).contains(groundLift)
            }
            public var pose: DuelWeaponPose {
                DuelWeaponPose(clip: clip, tick: tick, duration: duration,
                               groundLift: groundLift, reaction: reaction)
            }
        }

        public init(_ fighter: DuelGame.Fighter) {
            hero = fighter.hero; x = fighter.x; y = fighter.y
            facing = fighter.facing; health = fighter.health
            guardMeter = fighter.guardMeter; energy = fighter.energy
            stun = fighter.stun; knockdown = fighter.knockdown
            animation = fighter.weaponPose.map(Animation.init)
        }
        public var isPlausible: Bool {
            (-2_000...12_000).contains(x) && (-1_000...10_000).contains(y)
            && (facing == -1 || facing == 1) && (0...1_000).contains(health)
            && (0...1_000).contains(guardMeter) && (0...100).contains(energy)
            && (0...10_000).contains(stun) && (0...10_000).contains(knockdown)
            && (animation?.isPlausible ?? true)
        }
    }

    public enum Phase: String, Codable, Sendable { case fighting, roundBreak, matchOver }
    public let version: Int
    public let sessionID: String
    public let tick: UInt64
    public let epoch: UInt64
    public let fighters: [Fighter]
    public let phase: Phase
    public let winner: Int?
    public let remainingTicks: Int

    public init(simulation: DuelNetworkHostSimulation) {
        version = Self.version
        sessionID = simulation.inputs.sessionID
        tick = simulation.inputs.nextTick
        epoch = simulation.inputs.epoch
        fighters = simulation.game.fighters.map(Fighter.init)
        remainingTicks = simulation.game.remainingTicks
        switch simulation.game.phase {
        case .fighting: phase = .fighting; winner = nil
        case .roundBreak(let player, _): phase = .roundBreak; winner = player
        case .matchOver(let player): phase = .matchOver; winner = player
        }
    }

    public var isPlausible: Bool {
        version == Self.version && !sessionID.isEmpty && sessionID.utf8.count <= 128
        && fighters.count == 2 && fighters.allSatisfy(\.isPlausible)
        && fighters[0].hero != fighters[1].hero
        && (0...100_000).contains(remainingTicks)
        && (winner == nil || winner == 0 || winner == 1)
        && (phase != .fighting || winner == nil)
        && (phase != .matchOver || winner != nil)
    }
}

/// Guest projection is read-only. Authenticated sender identity comes from the
/// transport callback, never a field supplied by a remote peer.
public struct DuelNetworkCombatReplica: Sendable {
    public enum Outcome: Equatable, Sendable {
        case applied, stale, rejected
    }
    public let sessionID: String
    public let hostID: String
    public private(set) var latest: DuelNetworkCombatState?

    public init(sessionID: String, hostID: String) {
        self.sessionID = sessionID
        self.hostID = hostID
    }

    @discardableResult
    public mutating func receive(_ data: Data, authenticatedSenderID: String) -> Outcome {
        guard authenticatedSenderID == hostID, data.count <= DuelNetworkCombatState.maximumBytes,
              let state = try? JSONDecoder().decode(DuelNetworkCombatState.self, from: data),
              state.sessionID == sessionID, state.isPlausible else { return .rejected }
        if let old = latest {
            guard state.epoch >= old.epoch else { return .stale }
            guard state.epoch != old.epoch || state.tick > old.tick else { return .stale }
            guard old.phase != .matchOver || state.epoch > old.epoch else { return .rejected }
            guard state.fighters.map(\.hero) == old.fighters.map(\.hero) else { return .rejected }
        }
        latest = state
        return .applied
    }
}
