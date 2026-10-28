import Foundation

// 乱斗的成长：每个角色各自攒奖杯（赢了加、输了扣），打一局给金币，金币给角色升级；
// 所有角色的奖杯加起来走「奖杯之路」，到了路上的点给金币、解锁新角色。只存在这台手机上

public struct ArenaProgress: Codable, Equatable, Sendable {
    public static let maxLevel = 9
    /// 几级解锁第一个、第二个小道具
    public static let gadgetLevels = [3, 5]
    /// 几级解锁第一个、第二个星徽
    public static let starLevels = [6, 8]
    /// 几级解锁超级充能
    public static let hyperLevel = 9

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
    /// 每个角色选的小道具、星徽（按 Brawler.rawValue；没选过的带第一个）
    private var gadgetTable: [Int: Int] = [:]
    private var starTable: [Int: Int] = [:]
    /// 冒险：每一关最好拿过几颗星（按关的编号）
    public internal(set) var storyStars: [String: Int] = [:]
    /// 冒险里投奔过来的骷髅（按 Brawler.rawValue，不用攒奖杯就解锁）
    private var recruited: Set<Int> = []

    public init() {}

    /// 老版本存的没有小道具、星徽的选择
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trophyTable = try container.decodeIfPresent([Int: Int].self, forKey: .trophyTable) ?? [:]
        levelTable = try container.decodeIfPresent([Int: Int].self, forKey: .levelTable) ?? [:]
        coins = try container.decodeIfPresent(Int.self, forKey: .coins) ?? 0
        reached = try container.decodeIfPresent(Int.self, forKey: .reached) ?? 0
        gadgetTable = try container.decodeIfPresent([Int: Int].self, forKey: .gadgetTable) ?? [:]
        starTable = try container.decodeIfPresent([Int: Int].self, forKey: .starTable) ?? [:]
        storyStars = try container.decodeIfPresent([String: Int].self, forKey: .storyStars) ?? [:]
        recruited = try container.decodeIfPresent(Set<Int>.self, forKey: .recruited) ?? []
    }

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
        brawler.unlockAt == 0 || max(totalTrophies, reached) >= brawler.unlockAt || recruited.contains(brawler.rawValue)
    }

    /// 冒险给的金币
    mutating func addCoins(_ amount: Int) {
        coins += max(amount, 0)
    }

    /// 冒险里投奔过来的（马上解锁）
    mutating func recruit(_ brawlers: [Brawler]) {
        recruited.formUnion(brawlers.map(\.rawValue))
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

    /// 这个角色已经解锁的小道具（按等级）
    public func gadgets(_ brawler: Brawler) -> [Gadget] {
        ArenaLoadout.gadgets(brawler, level: level(brawler))
    }

    /// 这个角色已经解锁的星徽（按等级）
    public func starPowers(_ brawler: Brawler) -> [StarPower] {
        ArenaLoadout.starPowers(brawler, level: level(brawler))
    }

    public func hasHypercharge(_ brawler: Brawler) -> Bool {
        level(brawler) >= Self.hyperLevel
    }

    /// 上场带的：选过的（还得是解锁了的），没选过的带第一个
    public func loadout(for brawler: Brawler) -> ArenaLoadout {
        let owned = self.gadgets(brawler), stars = self.starPowers(brawler)
        let gadget = gadgetTable[brawler.rawValue].flatMap(Gadget.init(rawValue:)).flatMap { owned.contains($0) ? $0 : nil }
        let star = starTable[brawler.rawValue].flatMap(StarPower.init(rawValue:)).flatMap { stars.contains($0) ? $0 : nil }
        return ArenaLoadout(gadget: gadget ?? owned.first, starPower: star ?? stars.first, hypercharge: hasHypercharge(brawler))
    }

    /// 选这个角色带的小道具（没解锁的不让选）
    public mutating func choose(_ gadget: Gadget, for brawler: Brawler) {
        guard gadgets(brawler).contains(gadget) else { return }
        gadgetTable[brawler.rawValue] = gadget.rawValue
    }

    /// 选这个角色带的星徽（没解锁的不让选）
    public mutating func choose(_ starPower: StarPower, for brawler: Brawler) {
        guard starPowers(brawler).contains(starPower) else { return }
        starTable[brawler.rawValue] = starPower.rawValue
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
        case trophyTable = "trophies", levelTable = "levels", coins, reached, gadgetTable = "gadgets", starTable = "stars"
        case storyStars = "story", recruited
    }
}
