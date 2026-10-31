import Foundation

/// Reviewed overrides for an imported match. Nil means the source value has not
/// been supplied; callers must expose their compatibility policy rather than
/// describe a host-engine default as a verified source-version constant.
public struct ArenaImportedMatchRules: Codable, Equatable, Sendable {
    public var matchDuration: Double?
    public var respawnDelay: Double?
    public var scoreGoal: Int?
    public var gemHoldSeconds: Double?
    public var gemSpawnIntervalSeconds: Double?
    public var usesBlueStarTieBreak: Bool?
    public var safeBaseHealth: Int?
    public var safeCollisionRadius: Double?
    public var zoneCaptureSeconds: Double?
    public var overtimeStartsAt: Double?
    public var overtimeGoldenGoal: Bool?
    public var evidence: [String: String]
    public var compatibilityNotes: [String]

    public init(matchDuration: Double? = nil, respawnDelay: Double? = nil, scoreGoal: Int? = nil,
                gemHoldSeconds: Double? = nil, gemSpawnIntervalSeconds: Double? = nil,
                usesBlueStarTieBreak: Bool? = nil, evidence: [String: String],
                compatibilityNotes: [String] = [], safeBaseHealth: Int? = nil,
                safeCollisionRadius: Double? = nil, zoneCaptureSeconds: Double? = nil,
                overtimeStartsAt: Double? = nil, overtimeGoldenGoal: Bool? = nil) {
        self.matchDuration = matchDuration; self.respawnDelay = respawnDelay; self.scoreGoal = scoreGoal
        self.gemHoldSeconds = gemHoldSeconds; self.gemSpawnIntervalSeconds = gemSpawnIntervalSeconds
        self.usesBlueStarTieBreak = usesBlueStarTieBreak; self.evidence = evidence
        self.compatibilityNotes = compatibilityNotes
        self.safeBaseHealth = safeBaseHealth; self.safeCollisionRadius = safeCollisionRadius
        self.zoneCaptureSeconds = zoneCaptureSeconds; self.overtimeStartsAt = overtimeStartsAt
        self.overtimeGoldenGoal = overtimeGoldenGoal
    }

    public func validationProblems(runtimeMode: ArenaGame.Mode) -> [String] {
        var problems: [String] = []
        let numeric: [(String, Double?, Double, Double)] = [
            ("matchDuration", matchDuration, 0.001, 7_200),
            ("respawnDelay", respawnDelay, 0, 120),
            ("gemHoldSeconds", gemHoldSeconds, 0.001, 120),
            ("gemSpawnIntervalSeconds", gemSpawnIntervalSeconds, 0.001, 120),
            ("safeCollisionRadius", safeCollisionRadius, 0.001, 4),
            ("zoneCaptureSeconds", zoneCaptureSeconds, 0.001, 600),
            ("overtimeStartsAt", overtimeStartsAt, 0, 7_200)
        ]
        var supplied: [String] = []
        for (key, value, lower, upper) in numeric {
            guard let value else { continue }
            supplied.append(key)
            if !value.isFinite || value < lower || value > upper { problems.append("\(key) is outside its supported range.") }
        }
        if let scoreGoal {
            supplied.append("scoreGoal")
            if !(1...100_000).contains(scoreGoal) { problems.append("scoreGoal is outside its supported range.") }
        }
        if usesBlueStarTieBreak != nil { supplied.append("usesBlueStarTieBreak") }
        if overtimeGoldenGoal != nil { supplied.append("overtimeGoldenGoal") }
        if let safeBaseHealth {
            supplied.append("safeBaseHealth")
            if !(1...10_000_000).contains(safeBaseHealth) { problems.append("safeBaseHealth is outside its supported range.") }
        }
        for key in supplied where evidence[key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("\(key) needs a specific source or compatibility-policy reference.")
        }
        if runtimeMode != .stars && (gemHoldSeconds != nil || gemSpawnIntervalSeconds != nil) {
            problems.append("Gem timing overrides require the gem-collection runtime mode.")
        }
        if runtimeMode != .bounty && usesBlueStarTieBreak != nil {
            problems.append("The blue-star rule requires the bounty runtime mode.")
        }
        if runtimeMode != .heist && (safeBaseHealth != nil || safeCollisionRadius != nil) {
            problems.append("Safe overrides require the heist runtime mode.")
        }
        if runtimeMode != .zone && zoneCaptureSeconds != nil { problems.append("Capture timing requires the zone runtime mode.") }
        if let overtimeStartsAt {
            if runtimeMode != .ball { problems.append("Overtime currently requires the ball runtime mode.") }
            if let matchDuration, overtimeStartsAt >= matchDuration { problems.append("Overtime must start before the final match limit.") }
        }
        if overtimeGoldenGoal != nil && (runtimeMode != .ball || overtimeStartsAt == nil) {
            problems.append("A golden-goal rule needs an explicit ball overtime phase.")
        }
        return problems
    }
}

public enum ArenaImportedObjectiveResult: Equatable, Sendable {
    case winner(team: Int)
    case draw
}

/// Objective accounting independent of rendering and fighter AI. The caller
/// supplies current held totals after pickups/deaths; ground gems never count.
public struct ArenaGemGrabObjectiveState: Equatable, Sendable {
    public let target: Int
    public let holdDuration: Double
    public let matchDuration: Double
    public private(set) var countdownTeam: Int?
    public private(set) var countdownRemaining: Double?
    public private(set) var result: ArenaImportedObjectiveResult?

    public enum InvalidRules: Error, Sendable { case invalidValue }

    public init(target: Int, holdDuration: Double, matchDuration: Double) throws {
        guard (1...100_000).contains(target), holdDuration.isFinite, holdDuration > 0,
              matchDuration.isFinite, matchDuration > 0 else { throw InvalidRules.invalidValue }
        self.target = target; self.holdDuration = holdDuration; self.matchDuration = matchDuration
    }

    /// Returns false for invalid input and leaves the state unchanged.
    @discardableResult
    public mutating func update(delta: Double, elapsed: Double, heldByTeam: [Int]) -> Bool {
        guard result == nil, delta.isFinite, delta >= 0, elapsed.isFinite, elapsed >= 0,
              heldByTeam.count == 2, heldByTeam.allSatisfy({ $0 >= 0 }) else { return false }
        if elapsed >= matchDuration {
            result = heldByTeam[0] == heldByTeam[1] ? .draw : .winner(team: heldByTeam[0] > heldByTeam[1] ? 0 : 1)
            return true
        }
        let leader: Int? = heldByTeam[0] > heldByTeam[1] && heldByTeam[0] >= target ? 0
            : heldByTeam[1] > heldByTeam[0] && heldByTeam[1] >= target ? 1 : nil
        guard let leader else {
            countdownTeam = nil; countdownRemaining = nil
            return true
        }
        if countdownTeam != leader {
            // The total was observed at this update; do not credit unobserved past time.
            countdownTeam = leader; countdownRemaining = holdDuration
        } else {
            countdownRemaining = max(0, (countdownRemaining ?? holdDuration) - delta)
            if countdownRemaining == 0 { result = .winner(team: leader) }
        }
        return true
    }
}

/// Bounty's blue star is a unique item: claiming it awards one point; defeating
/// its carrier transfers ownership to the attacker. The holder decides a timed tie.
/// Uncredited/environmental defeat handling is left explicit at the engine boundary.
public struct ArenaBountyObjectiveState: Equatable, Sendable {
    public let teams: [Int]
    public let scoreGoal: Int
    public let startingBounty: Int
    public let maximumBounty: Int
    public private(set) var score: [Int] = [0, 0]
    public private(set) var bounties: [Int]
    public private(set) var blueStarCarrier: Int?
    public private(set) var blueStarAvailable = true
    public private(set) var result: ArenaImportedObjectiveResult?

    public struct Elimination: Equatable, Sendable {
        public let team: Int
        public let awardedStars: Int
        public let transferredBlueStar: Bool
    }

    public enum InvalidRules: Error, Sendable { case invalidValue }

    public init(teams: [Int], scoreGoal: Int, startingBounty: Int, maximumBounty: Int) throws {
        guard !teams.isEmpty, teams.count <= 64, teams.allSatisfy({ $0 == 0 || $0 == 1 }),
              teams.contains(0), teams.contains(1), (1...100_000).contains(scoreGoal),
              startingBounty >= 1, maximumBounty >= startingBounty, maximumBounty <= 100 else {
            throw InvalidRules.invalidValue
        }
        self.teams = teams; self.scoreGoal = scoreGoal
        self.startingBounty = startingBounty; self.maximumBounty = maximumBounty
        self.bounties = Array(repeating: startingBounty, count: teams.count)
    }

    @discardableResult
    public mutating func claimBlueStar(by participant: Int) -> Bool {
        guard result == nil, blueStarAvailable, teams.indices.contains(participant) else { return false }
        blueStarAvailable = false; blueStarCarrier = participant
        let team = teams[participant]
        score[team] += 1
        if score[team] >= scoreGoal { result = .winner(team: team) }
        return true
    }

    /// Only a credited enemy defeat is accepted. No teammate kill or fabricated
    /// participant index can earn points or silently assign the unique blue star.
    @discardableResult
    public mutating func recordElimination(victim: Int, attacker: Int) -> Elimination? {
        guard result == nil, teams.indices.contains(victim), teams.indices.contains(attacker),
              teams[victim] != teams[attacker] else { return nil }
        let team = teams[attacker], awarded = bounties[victim]
        let transferred = blueStarCarrier == victim
        score[team] += awarded
        bounties[attacker] = min(maximumBounty, bounties[attacker] + 1)
        bounties[victim] = startingBounty
        if transferred { blueStarCarrier = attacker }
        if score[team] >= scoreGoal { result = .winner(team: team) }
        return Elimination(team: team, awardedStars: awarded, transferredBlueStar: transferred)
    }

    @discardableResult
    public mutating func finishAtTimeLimit() -> ArenaImportedObjectiveResult {
        if let result { return result }
        let final: ArenaImportedObjectiveResult
        if score[0] != score[1] {
            final = .winner(team: score[0] > score[1] ? 0 : 1)
        } else if let carrier = blueStarCarrier {
            final = .winner(team: teams[carrier])
        } else {
            final = .draw
        }
        result = final
        return final
    }
}
