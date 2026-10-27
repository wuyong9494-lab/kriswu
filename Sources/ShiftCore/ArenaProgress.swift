import Foundation

// 乱斗的成长：每个角色各自攒奖杯（赢了加、输了扣），打一局给金币，金币给角色升级；
// 所有角色的奖杯加起来走「奖杯之路」，到了路上的点给金币、解锁新角色。只存在这台手机上

public struct ArenaProgress: Codable, Equatable, Sendable {
    public static let maxLevel = 9

    /// 奖杯之路上的一个点
    public struct Milestone: Equatable, Sendable {
        public let trophies: Int
        public let coins: Int
        /// 到这里解锁的角色
        public let brawler: Brawler?
    }

    /// 一局的结果
    public enum Outcome: Equatable, Sendable {
        case win, draw, loss
        /// 大乱斗第几名（1–6）
        case place(Int)
    }

    /// 打完一局得到的
    public struct Reward: Equatable, Sendable {
        /// 这个角色的奖杯变了多少（输了是负的）
        public var trophies: Int
        public var coins: Int
        /// 走到奖杯之路上新的点给的金币（已经算在 coins 里）
        public var milestoneCoins: Int
        /// 这局之后新解锁的角色
        public var unlocked: [Brawler]
    }

    /// 每个角色的奖杯（按 Brawler.rawValue）
    private var trophyTable: [Int: Int] = [:]
    /// 每个角色的等级（没记的是 1 级）
    private var levelTable: [Int: Int] = [:]
    public private(set) var coins = 0
    /// 奖杯之路走到过最远的地方（奖杯掉了再涨回来不重复给）
    public private(set) var reached = 0

    public init() {}

    /// 奖杯之路：越往后间隔越大
    public static let road: [Milestone] = {
        var points: [Milestone] = []
        let steps = [20, 40, 70, 100, 140, 180, 230, 280, 340, 400, 470, 550, 640, 740, 850, 1000]
        for (k, trophies) in steps.enumerated() {
            let brawler = Brawler.allCases.first { $0.unlockAt == trophies }
            points.append(Milestone(trophies: trophies, coins: brawler == nil ? 30 + 10 * k : 0, brawler: brawler))
        }
        // 解锁点不在上面那串里的角色也放进去
        for brawler in Brawler.allCases where brawler.unlockAt > 0 && !steps.contains(brawler.unlockAt) {
            points.append(Milestone(trophies: brawler.unlockAt, coins: 0, brawler: brawler))
        }
        return points.sorted { $0.trophies < $1.trophies }
    }()

    /// 升级要的金币：下标是现在的等级（1 级升 2 级要 costs[1]）
    static let costs = [0, 25, 50, 80, 120, 170, 230, 300, 380]

    public func trophies(_ brawler: Brawler) -> Int {
        trophyTable[brawler.rawValue] ?? 0
    }

    public func level(_ brawler: Brawler) -> Int {
        min(max(levelTable[brawler.rawValue] ?? 1, 1), Self.maxLevel)
    }

    public var totalTrophies: Int {
        trophyTable.values.reduce(0, +)
    }

    public func isUnlocked(_ brawler: Brawler) -> Bool {
        brawler.unlockAt == 0 || max(totalTrophies, reached) >= brawler.unlockAt
    }

    /// 下一个还没走到的点
    public var nextMilestone: Milestone? {
        Self.road.first { $0.trophies > max(totalTrophies, reached) }
    }

    /// 升到下一级要多少金币（满级 nil）
    public func upgradeCost(_ brawler: Brawler) -> Int? {
        let level = level(brawler)
        return level < Self.maxLevel ? Self.costs[level] : nil
    }

    /// 花金币升一级；金币不够、满级、没解锁返回 false
    @discardableResult
    public mutating func upgrade(_ brawler: Brawler) -> Bool {
        guard isUnlocked(brawler), let cost = upgradeCost(brawler), coins >= cost else { return false }
        coins -= cost
        levelTable[brawler.rawValue] = level(brawler) + 1
        return true
    }

    /// 打完一局：这个角色加减奖杯、给金币，走到奖杯之路上新的点给奖励
    public mutating func record(_ outcome: Outcome, brawler: Brawler) -> Reward {
        let unlockedBefore = Set(Brawler.allCases.filter { isUnlocked($0) })
        let before = trophies(brawler)
        var change = Self.trophyChange(outcome)
        // 奖杯少的时候输了不扣
        if change < 0 && before < 30 { change = 0 }
        trophyTable[brawler.rawValue] = max(0, before + change)
        var gained = Self.coinReward(outcome)
        var milestoneCoins = 0
        let total = totalTrophies
        if total > reached {
            for point in Self.road where point.trophies > reached && point.trophies <= total {
                milestoneCoins += point.coins
            }
            reached = total
        }
        gained += milestoneCoins
        coins += gained
        let unlocked = Brawler.allCases.filter { isUnlocked($0) && !unlockedBefore.contains($0) }
        return Reward(trophies: trophies(brawler) - before, coins: gained, milestoneCoins: milestoneCoins, unlocked: unlocked)
    }

    static func trophyChange(_ outcome: Outcome) -> Int {
        switch outcome {
        case .win: return 8
        case .draw: return 1
        case .loss: return -3
        case .place(let place): return [10, 7, 4, 0, -2, -3][min(max(place, 1), 6) - 1]
        }
    }

    static func coinReward(_ outcome: Outcome) -> Int {
        switch outcome {
        case .win: return 20
        case .draw: return 12
        case .loss: return 8
        case .place(let place): return [25, 18, 13, 10, 8, 6][min(max(place, 1), 6) - 1]
        }
    }

    private enum CodingKeys: String, CodingKey {
        case trophyTable = "trophies", levelTable = "levels", coins, reached
    }
}
