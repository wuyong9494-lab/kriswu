import Foundation

// 赛季、任务、排位、皮肤、表情（都存在这台手机上的成长里）：
// - 赛季：每个自然月一季。打完一局、做完任务攒赛季经验，每 100 点升一级，一共 30 级，每级领一份奖励（金币、皮肤、表情）；换季从头来。
// - 任务：每天 3 个、每周 3 个，按日期定（同一天大家一样）；打完一局自动算进度，做完给赛季经验。
// - 排位：只打 3v3 的玩法，赢了加分、输了扣分，分数到了升段（青铜、白银、黄金、钻石、大师）；段位越高，电脑越强。排位不加减奖杯。
// - 皮肤：每个角色两套换颜色的，商店用金币买，有的是赛季奖励；表情：对局里点一下，头顶冒一个。

/// 一局打完的数（任务、赛季经验按这个算）
public struct ArenaMatchStats: Equatable, Sendable {
    public var mode: ArenaGame.Mode
    public var brawler: Brawler
    public var won: Bool
    public var kills: Int
    public var damage: Int
    public var gadgets: Int
    public var supers: Int
    public var ranked: Bool

    public init(mode: ArenaGame.Mode, brawler: Brawler, won: Bool, kills: Int = 0, damage: Int = 0, gadgets: Int = 0, supers: Int = 0,
                ranked: Bool = false) {
        self.mode = mode
        self.brawler = brawler
        self.won = won
        self.kills = kills
        self.damage = damage
        self.gadgets = gadgets
        self.supers = supers
        self.ranked = ranked
    }
}

/// 一个任务
public struct ArenaQuest: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case play, win, kills, damage, gadgets, supers, winMode, winWith
    }

    /// 「d2026-10-28-0」这样：哪天（哪周）的第几个
    public let id: String
    public let kind: Kind
    public let target: Int
    public var mode: ArenaGame.Mode?
    public var brawler: Brawler?
    /// 做完给的赛季经验
    public let points: Int
    public let weekly: Bool

    public var title: String {
        switch kind {
        case .play: return "打 \(target) 局"
        case .win: return "赢 \(target) 局"
        case .kills: return "打倒 \(target) 个人"
        case .damage: return "打出 \(target) 伤害"
        case .gadgets: return "用 \(target) 次小道具"
        case .supers: return "放 \(target) 次大招"
        case .winMode: return "「\(mode?.title ?? "")」赢 \(target) 局"
        case .winWith: return "用\(brawler?.name ?? "")赢 \(target) 局"
        }
    }

    /// 这一局给这个任务算多少进度
    public func progress(of stats: ArenaMatchStats) -> Int {
        switch kind {
        case .play: return 1
        case .win: return stats.won ? 1 : 0
        case .kills: return stats.kills
        case .damage: return stats.damage
        case .gadgets: return stats.gadgets
        case .supers: return stats.supers
        case .winMode: return stats.won && stats.mode == mode ? 1 : 0
        case .winWith: return stats.won && stats.brawler == brawler ? 1 : 0
        }
    }
}

/// 皮肤：换颜色（身上的颜色乘上 tint，再加一点 glow 的光）
public struct ArenaSkin: Equatable, Sendable, Identifiable {
    public let brawler: Brawler
    /// 第几套（1、2；0 是原来的样子）
    public let index: Int
    public let name: String
    public let tint: [Double]
    public let glow: [Double]
    /// 商店里卖多少金币
    public let price: Int

    public var id: Int { brawler.rawValue * 10 + index }

    /// 全部皮肤（每个角色两套）
    public static let all: [ArenaSkin] = {
        let table: [(Brawler, String, [Double], [Double], String, [Double], [Double])] = [
            (.knight, "黄金骑士", [1, 0.86, 0.45], [0.18, 0.12, 0], "寒冰骑士", [0.62, 0.85, 1], [0, 0.06, 0.14]),
            (.ranger, "森林游侠", [0.6, 1, 0.55], [0, 0.08, 0], "夜鸦游侠", [0.48, 0.45, 0.62], [0.04, 0, 0.08]),
            (.barbarian, "熔岩蛮王", [1, 0.55, 0.38], [0.2, 0.05, 0], "雪原蛮王", [0.85, 0.93, 1], [0.12, 0.14, 0.18]),
            (.mage, "星空法师", [0.55, 0.55, 1], [0.06, 0.04, 0.16], "南瓜法师", [1, 0.68, 0.3], [0.14, 0.06, 0]),
            (.assassin, "影刃刺客", [0.52, 0.4, 0.72], [0.06, 0, 0.12], "樱花刺客", [1, 0.7, 0.82], [0.14, 0.04, 0.08]),
            (.guardian, "黄金骨盾卫", [1, 0.85, 0.42], [0.16, 0.1, 0], "翡翠骨盾卫", [0.55, 1, 0.68], [0, 0.12, 0.04]),
            (.necromancer, "冰魂巫师", [0.55, 0.92, 1], [0, 0.1, 0.16], "血月巫师", [1, 0.42, 0.42], [0.16, 0, 0]),
            (.shade, "虚空幽影", [0.66, 0.45, 1], [0.1, 0, 0.18], "白骨幽影", [1, 0.97, 0.88], [0.16, 0.15, 0.12]),
            (.summoner, "蓝焰骨灵", [0.5, 0.75, 1], [0, 0.06, 0.2], "金骨灵", [1, 0.84, 0.4], [0.16, 0.1, 0]),
        ]
        return table.flatMap { brawler, firstName, firstTint, firstGlow, secondName, secondTint, secondGlow in
            [ArenaSkin(brawler: brawler, index: 1, name: firstName, tint: firstTint, glow: firstGlow, price: 160),
             ArenaSkin(brawler: brawler, index: 2, name: secondName, tint: secondTint, glow: secondGlow, price: 120)]
        }
    }()

    public static func of(_ brawler: Brawler) -> [ArenaSkin] { all.filter { $0.brawler == brawler } }

    public static func find(_ id: Int) -> ArenaSkin? { all.first { $0.id == id } }
}

/// 表情：对局里头顶冒一个
public struct ArenaEmote: Equatable, Sendable, Identifiable {
    public let id: Int
    public let symbol: String
    public let name: String
    /// 怎么来的：一开始就有、赛季奖励、商店（多少金币）
    public let price: Int?

    public var free: Bool { id < 4 }

    public static let all: [ArenaEmote] = [
        ArenaEmote(id: 0, symbol: "👍", name: "好样的", price: nil),
        ArenaEmote(id: 1, symbol: "😂", name: "哈哈", price: nil),
        ArenaEmote(id: 2, symbol: "😡", name: "气死了", price: nil),
        ArenaEmote(id: 3, symbol: "😭", name: "呜呜", price: nil),
        ArenaEmote(id: 4, symbol: "🎉", name: "赢啦", price: nil),
        ArenaEmote(id: 5, symbol: "😎", name: "太帅了", price: nil),
        ArenaEmote(id: 6, symbol: "🤝", name: "一起上", price: nil),
        ArenaEmote(id: 7, symbol: "💤", name: "困了", price: nil),
        ArenaEmote(id: 8, symbol: "🔥", name: "燃起来", price: 60),
        ArenaEmote(id: 9, symbol: "👻", name: "吓你一跳", price: 60),
    ]

    public static func find(_ id: Int) -> ArenaEmote? { all.first { $0.id == id } }
}

/// 排位的段位
public enum ArenaRank {
    public struct Tier: Equatable, Sendable {
        public let name: String
        /// 到多少分进这一段
        public let points: Int
        /// 这一段的电脑几级
        public let botLevel: Int
    }

    public static let tiers: [Tier] = [
        Tier(name: "青铜", points: 0, botLevel: 3),
        Tier(name: "白银", points: 200, botLevel: 5),
        Tier(name: "黄金", points: 500, botLevel: 7),
        Tier(name: "钻石", points: 900, botLevel: 8),
        Tier(name: "大师", points: 1400, botLevel: 9),
    ]

    /// 这个分数在第几段
    public static func tier(_ points: Int) -> Int {
        tiers.lastIndex { points >= $0.points } ?? 0
    }

    /// 打完一局排位加减多少分：赢了加 25，输了扣（段位越高扣得越多），平局不变
    public static func change(won: Bool, draw: Bool, points: Int) -> Int {
        if draw { return 0 }
        if won { return 25 }
        return -[8, 12, 15, 18, 20][tier(points)]
    }

    /// 排位能打的玩法（3v3 分队的）
    public static func allows(_ mode: ArenaGame.Mode) -> Bool {
        mode.seatTeams == [0, 0, 0, 1, 1, 1]
    }
}

/// 赛季
public enum ArenaSeason {
    public static let tiers = 30
    public static let pointsPerTier = 100
    /// 一局给的赛季经验：赢了多给
    public static func matchPoints(_ stats: ArenaMatchStats) -> Int { stats.won ? 20 : 8 }

    /// 每一级的奖励
    public enum Prize: Equatable, Sendable {
        case coins(Int)
        case skin(Int)
        case emote(Int)
    }

    private static let special: [Int: Prize] = [
        3: .emote(4), 5: .skin(Brawler.knight.rawValue * 10 + 1), 8: .emote(5), 10: .skin(Brawler.mage.rawValue * 10 + 1),
        13: .emote(6), 15: .skin(Brawler.assassin.rawValue * 10 + 1), 18: .emote(7), 20: .skin(Brawler.barbarian.rawValue * 10 + 1),
        25: .skin(Brawler.ranger.rawValue * 10 + 1), 30: .skin(Brawler.shade.rawValue * 10 + 1),
    ]

    /// 第几级（1–30）给什么
    public static func prize(_ tier: Int) -> Prize {
        special[tier] ?? .coins(20 + tier * 2)
    }

    /// 哪一季（年-月）
    public static func season(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// 哪一天
    public static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 哪一周
    public static func week(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    /// 这一季还剩几天（今天算一天）
    public static func daysLeft(_ date: Date, calendar: Calendar) -> Int {
        guard let range = calendar.range(of: .day, in: .month, for: date) else { return 1 }
        return range.count - calendar.component(.day, from: date) + 1
    }

    /// 这一天的 3 个任务（同一天大家一样）
    public static func daily(_ day: String) -> [ArenaQuest] {
        var random = SeededRandom(seed: stableHash("d" + day))
        var kinds: [ArenaQuest.Kind] = [.play, .win, .kills, .damage, .gadgets, .supers, .winMode, .winWith]
        random.shuffle(&kinds)
        return kinds.prefix(3).enumerated().map { k, kind in
            quest("d\(day)-\(k)", kind, weekly: false, random: &random)
        }
    }

    /// 这一周的 3 个任务
    public static func weekly(_ week: String) -> [ArenaQuest] {
        var random = SeededRandom(seed: stableHash("w" + week))
        var kinds: [ArenaQuest.Kind] = [.play, .win, .kills, .damage, .supers, .winMode]
        random.shuffle(&kinds)
        return kinds.prefix(3).enumerated().map { k, kind in
            quest("w\(week)-\(k)", kind, weekly: true, random: &random)
        }
    }

    private static func quest(_ id: String, _ kind: ArenaQuest.Kind, weekly: Bool, random: inout SeededRandom) -> ArenaQuest {
        let scale = weekly ? 5 : 1
        let teamModes = ArenaGame.Mode.allCases.filter(ArenaRank.allows)
        let starters = Brawler.allCases.filter { $0.unlockAt == 0 }
        switch kind {
        case .play: return ArenaQuest(id: id, kind: kind, target: 3 * scale, points: 40 * scale, weekly: weekly)
        case .win: return ArenaQuest(id: id, kind: kind, target: 2 * scale, points: 60 * scale, weekly: weekly)
        case .kills: return ArenaQuest(id: id, kind: kind, target: 8 * scale, points: 50 * scale, weekly: weekly)
        case .damage: return ArenaQuest(id: id, kind: kind, target: 20_000 * scale, points: 50 * scale, weekly: weekly)
        case .gadgets: return ArenaQuest(id: id, kind: kind, target: 4 * scale, points: 40 * scale, weekly: weekly)
        case .supers: return ArenaQuest(id: id, kind: kind, target: 5 * scale, points: 50 * scale, weekly: weekly)
        case .winMode:
            return ArenaQuest(id: id, kind: kind, target: weekly ? 4 : 1, mode: teamModes[random.below(teamModes.count)],
                              points: weekly ? 220 : 60, weekly: weekly)
        case .winWith:
            return ArenaQuest(id: id, kind: kind, target: weekly ? 4 : 1, brawler: starters[random.below(starters.count)],
                              points: weekly ? 220 : 70, weekly: weekly)
        }
    }

    /// 字符串的固定哈希（Swift 自带的每次启动都不一样）
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// 赛季、任务、排位、皮肤、表情的进度（存在 ArenaProgress 里）
public struct ArenaSeasonState: Equatable, Codable, Sendable {
    /// 这一季、这一季的经验、领过第几级的奖励
    public var season = ""
    public var points = 0
    public var claimed: Set<Int> = []
    /// 任务：今天、这一周是哪天哪周；每个任务的进度；做完的
    public var day = ""
    public var week = ""
    public var progress: [String: Int] = [:]
    public var done: Set<String> = []
    /// 排位分、到过的最高段
    public var rankPoints = 0
    public var bestTier = 0
    /// 有的皮肤（ArenaSkin.id）、每个角色穿哪套（Brawler.rawValue → 第几套）、有的表情
    public var skins: Set<Int> = []
    public var wearing: [Int: Int] = [:]
    public var emotes: Set<Int> = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        season = try container.decodeIfPresent(String.self, forKey: .season) ?? ""
        points = try container.decodeIfPresent(Int.self, forKey: .points) ?? 0
        claimed = try container.decodeIfPresent(Set<Int>.self, forKey: .claimed) ?? []
        day = try container.decodeIfPresent(String.self, forKey: .day) ?? ""
        week = try container.decodeIfPresent(String.self, forKey: .week) ?? ""
        progress = try container.decodeIfPresent([String: Int].self, forKey: .progress) ?? [:]
        done = try container.decodeIfPresent(Set<String>.self, forKey: .done) ?? []
        rankPoints = try container.decodeIfPresent(Int.self, forKey: .rankPoints) ?? 0
        bestTier = try container.decodeIfPresent(Int.self, forKey: .bestTier) ?? 0
        skins = try container.decodeIfPresent(Set<Int>.self, forKey: .skins) ?? []
        wearing = try container.decodeIfPresent([Int: Int].self, forKey: .wearing) ?? [:]
        emotes = try container.decodeIfPresent(Set<Int>.self, forKey: .emotes) ?? []
    }

    /// 赛季几级（0–30）
    public var tier: Int { min(points / ArenaSeason.pointsPerTier, ArenaSeason.tiers) }
}

/// 打完一局在赛季里拿到的
public struct ArenaSeasonGain: Equatable, Sendable {
    public var points: Int
    /// 这局做完的任务
    public var quests: [ArenaQuest]
    /// 排位分变了多少、升没升段
    public var rankChange: Int?
    public var promoted: Bool
}

extension ArenaProgress {
    /// 今天、这一周的任务
    public func quests(_ now: Date, calendar: Calendar) -> [ArenaQuest] {
        ArenaSeason.daily(ArenaSeason.day(now, calendar: calendar)) + ArenaSeason.weekly(ArenaSeason.week(now, calendar: calendar))
    }

    /// 这个任务做到多少了（不是今天、这周的算 0）
    public func questProgress(_ quest: ArenaQuest) -> Int {
        season.done.contains(quest.id) ? quest.target : min(season.progress[quest.id] ?? 0, quest.target)
    }

    /// 换季、换天、换周：赛季经验和领过的奖励从头来，旧任务的进度清掉
    public mutating func refreshSeason(_ now: Date, calendar: Calendar) {
        let id = ArenaSeason.season(now, calendar: calendar)
        if season.season != id {
            season.season = id
            season.points = 0
            season.claimed = []
        }
        let day = ArenaSeason.day(now, calendar: calendar), week = ArenaSeason.week(now, calendar: calendar)
        if season.day != day || season.week != week {
            let current = Set(quests(now, calendar: calendar).map(\.id))
            season.progress = season.progress.filter { current.contains($0.key) }
            season.done = season.done.filter { current.contains($0) }
            season.day = day
            season.week = week
        }
    }

    /// 打完一局：赛季经验、任务进度，排位的话加减排位分
    public mutating func recordSeason(_ stats: ArenaMatchStats, draw: Bool = false, now: Date, calendar: Calendar) -> ArenaSeasonGain {
        refreshSeason(now, calendar: calendar)
        var gain = ArenaSeasonGain(points: ArenaSeason.matchPoints(stats), quests: [], rankChange: nil, promoted: false)
        for quest in quests(now, calendar: calendar) where !season.done.contains(quest.id) {
            let value = (season.progress[quest.id] ?? 0) + quest.progress(of: stats)
            season.progress[quest.id] = value
            if value >= quest.target {
                season.done.insert(quest.id)
                gain.quests.append(quest)
                gain.points += quest.points
            }
        }
        season.points += gain.points
        if stats.ranked {
            let before = ArenaRank.tier(season.rankPoints)
            let change = ArenaRank.change(won: stats.won, draw: draw, points: season.rankPoints)
            season.rankPoints = max(0, season.rankPoints + change)
            let after = ArenaRank.tier(season.rankPoints)
            gain.rankChange = change
            gain.promoted = after > before
            season.bestTier = max(season.bestTier, after)
        }
        return gain
    }

    /// 领赛季第几级的奖励（到了这一级、还没领过）
    @discardableResult
    public mutating func claim(_ tier: Int) -> ArenaSeason.Prize? {
        guard tier >= 1, tier <= season.tier, !season.claimed.contains(tier) else { return nil }
        season.claimed.insert(tier)
        let prize = ArenaSeason.prize(tier)
        switch prize {
        case .coins(let amount): addCoins(amount)
        case .skin(let id): season.skins.insert(id)
        case .emote(let id): season.emotes.insert(id)
        }
        return prize
    }

    /// 有没有这套皮肤、这个表情
    public func owns(skin: ArenaSkin) -> Bool { season.skins.contains(skin.id) }

    public func owns(emote: ArenaEmote) -> Bool { emote.free || season.emotes.contains(emote.id) }

    /// 有的表情（按顺序）
    public var emotes: [ArenaEmote] { ArenaEmote.all.filter { owns(emote: $0) } }

    /// 商店：用金币买皮肤、表情
    @discardableResult
    public mutating func buy(_ skin: ArenaSkin) -> Bool {
        guard !owns(skin: skin), spend(skin.price) else { return false }
        season.skins.insert(skin.id)
        return true
    }

    @discardableResult
    public mutating func buy(_ emote: ArenaEmote) -> Bool {
        guard !owns(emote: emote), let price = emote.price, spend(price) else { return false }
        season.emotes.insert(emote.id)
        return true
    }

    /// 这个角色穿哪套（0 原来的样子；没有的穿不上）
    public func skin(_ brawler: Brawler) -> Int {
        let index = season.wearing[brawler.rawValue] ?? 0
        return ArenaSkin.of(brawler).contains { $0.index == index && owns(skin: $0) } ? index : 0
    }

    public mutating func wear(_ index: Int, for brawler: Brawler) {
        guard index == 0 || ArenaSkin.of(brawler).contains(where: { $0.index == index && owns(skin: $0) }) else { return }
        season.wearing[brawler.rawValue] = index
    }

    /// 排位赛的段位
    public var rankTier: Int { ArenaRank.tier(season.rankPoints) }
}
