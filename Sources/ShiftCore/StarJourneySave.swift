import Foundation

extension StarJourney {
    public struct Run: Codable, Equatable, Sendable, Identifiable {
        public let version: Int
        public let id: UUID
        public let ability: Ability
        public private(set) var route: Route?
        public private(set) var completed: [StarRail.Game.Archive]
        public private(set) var current: StarRail.Game.Archive
        public init(ability: Ability) {
            version = 1; id = UUID(); self.ability = ability; route = nil; completed = []
            current = StarRail.Game(stage:Configuration(runID:id,ability:ability,chapter:0).stage).archive
        }
        public var chapter: Int { completed.count }
        public var game: StarRail.Game { StarRail.Game(archive:current)! }
        public var finished: Bool { chapter == 2 && game.status == .won }
        public var score: Int { completed.compactMap(StarRail.Game.init(archive:)).reduce(0) { $0 + $1.stars } + game.stars }
        public var rewardStars: Int { finished ? score + (route == .signal ? 1 : 0) : 0 }
        public var rewinds: Int { completed.reduce(0) { $0 + $1.rewinds } + current.rewinds }
        public var recordKey: String? { route.map { "J1-\(ability.rawValue)-\($0.rawValue)" } }
        public func nextEnergy(after game: StarRail.Game, route: Route) -> Int {
            let carried = ability == .navigator ? 0 : game.state.energy
            let supply = chapter == 0 && route == .supply ? 1 : 0
            return min(ability.energyLimit, carried + supply)
        }
        @discardableResult public mutating func keep(_ game: StarRail.Game) -> Bool {
            guard let config = current.journey, game.stage.journey == config, game.stage == config.stage else { return false }
            current = game.archive; return true
        }
        @discardableResult public mutating func advance(route choice: Route? = nil) -> Bool {
            let previous = game
            guard previous.status == .won, chapter < 2 else { return false }
            let chosen: Route
            if chapter == 0 { guard let choice else { return false }; chosen = choice }
            else { guard choice == nil, let route else { return false }; chosen = route }
            let energy = nextEnergy(after:previous,route:chosen)
            let next = Configuration(runID:id,ability:ability,chapter:chapter+1,route:chosen,openingEnergy:energy)
            completed.append(current); route = chosen
            current = StarRail.Game(stage:next.stage).archive
            return true
        }
        public var isValid: Bool {
            guard version == 1, completed.count <= 2, (completed.isEmpty ? route == nil : route != nil) else { return false }
            var previous: StarRail.Game?
            for (index, archive) in (completed + [current]).enumerated() {
                let supplied = index == 1 && route == .supply ? 1 : 0
                let carried = ability == .navigator ? 0 : previous?.state.energy ?? 0
                let expected = Configuration(runID:id,ability:ability,chapter:index,route:index == 0 ? nil : route,
                                             openingEnergy:index == 0 ? 0 : min(ability.energyLimit,carried+supplied))
                guard archive.journey == expected, let game = StarRail.Game(archive:archive), game.stage == expected.stage,
                      index == completed.count || game.status == .won else { return false }
                previous = game
            }
            return true
        }
        private enum CodingKeys: String, CodingKey { case version, id, ability, route, completed, current }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy:CodingKeys.self)
            version = try c.decode(Int.self,forKey:.version); id = try c.decode(UUID.self,forKey:.id)
            ability = try c.decode(Ability.self,forKey:.ability); route = try c.decodeIfPresent(Route.self,forKey:.route)
            completed = try c.decode([StarRail.Game.Archive].self,forKey:.completed)
            current = try c.decode(StarRail.Game.Archive.self,forKey:.current)
            guard isValid else { throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Invalid journey chain or carried energy")) }
        }
    }
    public struct Reward: Codable, Equatable, Sendable, Identifiable {
        public let id: UUID
        public let earned: Int
        public let totalBefore: Int
        public let totalAfter: Int
        public let score: Int
        public let route: Route
    }
    public struct Save: Codable, Equatable, Sendable {
        public static let storageKey = "tileGame.starJourney.v1"
        public let version: Int
        public private(set) var active: Run?
        public private(set) var best: [String:Run]
        public private(set) var pendingReward: Reward?
        public private(set) var rewardedRunID: UUID?
        // Derived once on load or a new best, never replay six records on each tap.
        public private(set) var totalStars = 0
        public init() { version = 1; best = [:] }
        public mutating func start(ability: Ability) {
            active = Run(ability:ability); pendingReward = nil; rewardedRunID = nil
        }
        @discardableResult public mutating func advance(route: Route? = nil) -> Bool {
            guard var run = active, run.advance(route:route) else { return false }; active = run; return true
        }
        @discardableResult public mutating func keep(_ game: StarRail.Game, otherStars: Int = 0) -> Bool {
            guard (0...10_000).contains(otherStars), var run = active, run.keep(game) else { return false }
            active = run
            if !run.finished { pendingReward = nil }
            if run.finished, let key = run.recordKey {
                let before = totalStars
                if let old = best[key] {
                    if run.score > old.score || (run.score == old.score && run.rewinds < old.rewinds) { best[key] = run }
                } else { best[key] = run }
                totalStars = best.values.reduce(0) { $0 + $1.rewardStars }
                let earned = totalStars - before
                if let pending = pendingReward, pending.id == run.id {
                    pendingReward = Reward(id:run.id,earned:pending.earned+earned,totalBefore:pending.totalBefore,
                        totalAfter:pending.totalAfter+earned,score:run.score,route:run.route!)
                } else if rewardedRunID != run.id || earned > 0 {
                    pendingReward = Reward(id:run.id,earned:earned,totalBefore:otherStars+before,
                        totalAfter:otherStars+totalStars,score:run.score,route:run.route!)
                }
                rewardedRunID = run.id
            }
            return true
        }
        public mutating func acknowledgeReward(_ id: UUID) {
            if pendingReward?.id == id { pendingReward = nil }
        }
        public var isValid: Bool {
            guard version == 1, best.count <= Ability.allCases.count * Route.allCases.count, active?.isValid != false,
                  best.allSatisfy({ key,run in run.isValid && run.finished && run.recordKey == key }) else { return false }
            if let rewardedRunID { guard active?.id == rewardedRunID else { return false } }
            if let reward = pendingReward {
                guard let active, active.finished, active.id == reward.id, rewardedRunID == reward.id,
                      reward.score == active.score, reward.route == active.route,
                      (0...(active.recordKey.flatMap { best[$0]?.rewardStars } ?? 0)).contains(reward.earned),
                      (0...(10_000 + totalStars)).contains(reward.totalBefore),
                      reward.totalAfter >= reward.totalBefore, reward.totalAfter <= 10_000 + totalStars,
                      reward.totalAfter - reward.totalBefore == reward.earned else { return false }
            }
            return true
        }
        public init?(data: Data) {
            guard data.count <= 524_288, let value = try? JSONDecoder().decode(Self.self,from:data) else { return nil }; self = value
        }
        public func encoded() -> Data? { try? JSONEncoder().encode(self) }
        private enum CodingKeys: String, CodingKey { case version, active, best, pendingReward, rewardedRunID }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy:CodingKeys.self)
            version = try c.decode(Int.self,forKey:.version); active = try c.decodeIfPresent(Run.self,forKey:.active)
            best = try c.decode([String:Run].self,forKey:.best)
            pendingReward = try c.decodeIfPresent(Reward.self,forKey:.pendingReward)
            rewardedRunID = try c.decodeIfPresent(UUID.self,forKey:.rewardedRunID)
            totalStars = best.values.reduce(0) { $0 + $1.rewardStars }
            guard isValid else { throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Invalid journey records or reward")) }
        }
    }
}
