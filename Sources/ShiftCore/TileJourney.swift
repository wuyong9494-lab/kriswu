import Foundation

extension TileGame.Spec {
    static func constellation(_ level: TileGame.Level) -> Self {
        switch level {
        case .easy:
            return .init(kinds: 6, layers: 4, columns: 6, rows: 7, stack: 3, most: 60, limit: 4, openChance: 0.5)
        case .normal:
            return .init(kinds: 10, layers: 6, columns: 7, rows: 7, stack: 7, most: 120, limit: 5, openChance: 0.72)
        case .hard:
            return .init(kinds: 12, layers: 8, columns: 7, rows: 7, stack: 10, most: 168, limit: 6, openChance: 0.86)
        }
    }
}

/// 星域关卡是固定种子的正式关卡，不随打开次数变简单；挑战码能复现同一棋盘。
public enum TileJourney {
    public struct Stage: Identifiable, Equatable, Sendable {
        public let id: Int
        public let name: String
        public let level: TileGame.Level
        public let seed: UInt64
        public var game: TileGame { TileGame(level: level, seed: seed, ruleSet: .constellation) }
    }

    public static let stages: [Stage] = [
        .init(id: 1, name: "星港启航", level: .easy, seed: 11_301),
        .init(id: 2, name: "月面回廊", level: .easy, seed: 11_302),
        .init(id: 3, name: "双星交汇", level: .normal, seed: 21_601),
        .init(id: 4, name: "轨道花园", level: .normal, seed: 21_602),
        .init(id: 5, name: "彗星之桥", level: .normal, seed: 21_603),
        .init(id: 6, name: "引力迷宫", level: .normal, seed: 21_604),
        .init(id: 7, name: "碎星海", level: .hard, seed: 38_101),
        .init(id: 8, name: "暗面航道", level: .hard, seed: 38_102),
        .init(id: 9, name: "土星之环", level: .hard, seed: 38_103),
        .init(id: 10, name: "深空信标", level: .hard, seed: 38_104),
        .init(id: 11, name: "星云核心", level: .hard, seed: 38_105),
        .init(id: 12, name: "银河终章", level: .hard, seed: 38_106),
    ]

    public static func stage(_ id: Int) -> Stage? { stages.first { $0.id == id } }

    public struct Progress: Codable, Equatable, Sendable {
        public private(set) var stars: [Int: Int] = [:]
        public private(set) var scores: [Int: Int] = [:]
        public init() {}
        public var totalStars: Int { stars.values.reduce(0, +) }
        public func isUnlocked(_ id: Int) -> Bool {
            guard TileJourney.stage(id) != nil else { return false }
            return id == 1 || (stars[id - 1] ?? 0) > 0
        }
        public var nextStage: Stage {
            TileJourney.stages.first { (stars[$0.id] ?? 0) == 0 && isUnlocked($0.id) } ?? TileJourney.stages.last!
        }
        @discardableResult
        public mutating func record(stage id: Int, game: TileGame) -> Bool {
            guard let stage = TileJourney.stage(id), isUnlocked(id), game.status == .won,
                  game.level == stage.level, game.seed == stage.seed, game.ruleSet == .constellation else { return false }
            stars[id] = max(stars[id] ?? 0, game.stars)
            scores[id] = max(scores[id] ?? 0, game.score)
            return true
        }
    }
}
