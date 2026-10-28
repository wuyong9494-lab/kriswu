import Foundation

// 乱斗小游戏：俯视的小地图，左手摇杆走、右手摇杆瞄准开火，3 对 3 或各自为战，人不够电脑补位。
// 这里只管规则（每一帧谁走到哪、子弹打中谁、谁赢了），画面和摇杆在 App 里

/// 平面上的一个点、一个方向（以格为单位，x 往右、y 往下）
public struct V2: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = V2(0, 0)

    public static func + (a: V2, b: V2) -> V2 { V2(a.x + b.x, a.y + b.y) }
    public static func - (a: V2, b: V2) -> V2 { V2(a.x - b.x, a.y - b.y) }
    public static func * (a: V2, k: Double) -> V2 { V2(a.x * k, a.y * k) }

    public var length: Double { (x * x + y * y).squareRoot() }

    public var normalized: V2 {
        let l = length
        return l > 1e-9 ? V2(x / l, y / l) : .zero
    }

    public func distance(to other: V2) -> Double { (self - other).length }

    public func rotated(by angle: Double) -> V2 {
        let c = cos(angle), s = sin(angle)
        return V2(x * c - y * s, x * s + y * c)
    }

    /// 长度不超过 limit
    public func clamped(to limit: Double) -> V2 {
        let l = length
        return l > limit ? self * (limit / l) : self
    }

    public static func lerp(_ a: V2, _ b: V2, _ t: Double) -> V2 { a + (b - a) * t }
}

// MARK: - 角色

/// 能选的角色：各有各的普通攻击和大招（3D 模型用 KayKit 的冒险者、骷髅，CC0 授权）。
/// 后四个要攒奖杯解锁，各带一样新本事：护盾、亡灵之地（回血 + 伤人）、闪现、召唤骨塔
public enum Brawler: Int, CaseIterable, Codable, Sendable {
    case knight, ranger, barbarian, mage, assassin, guardian, necromancer, shade, summoner

    public var name: String { ["骑士", "游侠", "蛮王", "法师", "刺客", "骨盾卫", "亡灵巫师", "幽影", "骨灵"][rawValue] }
    public var emoji: String { ["🛡️", "🏹", "🪓", "🔮", "🗡️", "💀", "🕯️", "👻", "🦴"][rawValue] }
    public var role: String {
        ["近身剑气", "远程弩箭", "肉盾斧劈", "隔墙火球", "连掷飞刀", "护盾坦克", "回血辅助", "闪现突袭", "召唤骨塔"][rawValue]
    }
    public var attackNote: String {
        ["一剑挥出五道散开的剑气，贴脸打最疼", "一支又快又远的弩箭", "近身连劈三斧，血厚", "扔火球，能越过墙，落地炸一片", "一口气连掷四把飞刀",
         "斧子劈出一道宽宽的冲击波，能穿过一排人", "射出一团慢慢飞的魂火，能穿过好几个人", "连射两支短弩", "扔出三把散开的骨刃"][rawValue]
    }
    public var superNote: String {
        ["大招：举盾往前冲锋，撞到的人都受伤", "大招：能穿透好几个人的重弩", "大招：跳过去砸一片（能跳过墙）", "大招：召唤一颗大陨石", "大招：一大片扇形飞刀",
         "大招：举起骨盾，4 秒里受到的伤害少六成，还回一口血", "大招：放下一片亡灵之地，5 秒里队友在里面回血、敌人掉血",
         "大招：一下闪到远处（能穿墙），落地炸伤旁边的敌人", "大招：召唤一座骨塔，12 秒里自动打附近的敌人"][rawValue]
    }

    public var maxHealth: Int { [5600, 3200, 7800, 3800, 4400, 6800, 3600, 3700, 4000][rawValue] }
    /// 每秒走几格
    public var speed: Double { [2.45, 2.4, 2.55, 2.3, 2.4, 2.35, 2.4, 2.65, 2.45][rawValue] }
    /// 装一发弹要几秒（最多存 3 发）
    public var reload: Double { [1.5, 2.0, 1.2, 1.7, 1.4, 1.5, 1.6, 1.3, 1.5][rawValue] }
    public var attackRange: Double { [4.5, 9, 2.6, 7, 7, 3.2, 7.5, 6.5, 5.5][rawValue] }
    /// 大招打多远（骨盾卫的护盾是给自己的，只是一点点）
    public var superRange: Double { [5.5, 11, 6, 8, 7, 1, 6, 6.5, 5][rawValue] }
    /// 打出多少伤害攒满一次大招
    public var superCost: Double { [7200, 3900, 8400, 4800, 6000, 6400, 4600, 4400, 5200][rawValue] }
    /// 子弹飞多快（电脑瞄准提前量用）
    public var bulletSpeed: Double { [13, 17, 14, 10, 14, 12, 9, 18, 14][rawValue] }
    /// 总奖杯到多少解锁（一开始就有的是 0）
    public var unlockAt: Int { [0, 0, 0, 0, 0, 70, 140, 230, 340][rawValue] }

    /// 等级加成：每升一级血量、伤害多 6%（1 级不加）
    public static func boost(_ level: Int) -> Double {
        1 + 0.06 * Double(min(max(level, 1), ArenaProgress.maxLevel) - 1)
    }

    /// 这个等级的满血
    public func health(level: Int) -> Int {
        Int((Double(maxHealth) * Self.boost(level)).rounded())
    }
}

// MARK: - 地图

public struct ArenaMap: Sendable {
    /// goal：球门里的格子（球能进、人进不去）
    public enum Tile: Sendable { case floor, wall, bush, goal }
    /// 地面、墙长什么样（画面上用）
    public enum Theme: String, Sendable { case sand, meadow, stone, dusk }

    /// 宝箱攻防的宝箱：占几格（当墙），上半边的归上边一队
    public struct ChestSpot: Equatable, Sendable {
        public let team: Int
        public let center: V2
        public let cells: [Int]
    }

    /// 联机开局时房主告诉大家用哪张
    public let id: String
    public let title: String
    public let theme: Theme
    public let width: Int
    public let height: Int
    public let tiles: [Tile]
    /// 出生点：分队玩法是 [下边一队, 上边一队]，各自为战是一组
    public let spawns: [[V2]]
    /// 中间：星星冒出来的地方、占点的圈、开球的地方
    public let center: V2
    /// 宝箱（宝箱攻防的地图才有）
    public let chestSpots: [ChestSpot]
    /// 两队守的球门的中间：[下边一队的, 上边一队的]（足球的地图才有）
    public let goalCenters: [V2?]
    private let chestOfCell: [Int: Int]

    /// 用字画地图：# 墙、* 草丛、. 空地；a 下边一队的出生点、b 上边一队的、o 各自为战的；s 中间；
    /// G 球门（上半边的是上边一队守的）；C 宝箱（连在一起的几格是一个）
    public init(id: String = "custom", title: String = "", theme: Theme = .sand, rows: [String]) {
        self.id = id
        self.title = title
        self.theme = theme
        let h = rows.count
        let w = rows.map(\.count).max() ?? 0
        height = h
        width = w
        var tiles: [Tile] = []
        var a: [V2] = [], b: [V2] = [], o: [V2] = []
        var center = V2(Double(w) / 2, Double(h) / 2)
        var chestCells = Set<Int>()
        var goals: [[V2]] = [[], []]
        for (y, row) in rows.enumerated() {
            let characters = Array(row)
            for x in 0..<w {
                let c = x < characters.count ? characters[x] : "."
                let spot = V2(Double(x) + 0.5, Double(y) + 0.5)
                switch c {
                case "#": tiles.append(.wall)
                case "*": tiles.append(.bush)
                case "G":
                    tiles.append(.goal)
                    goals[spot.y < Double(h) / 2 ? 1 : 0].append(spot)
                case "C":
                    tiles.append(.wall)
                    chestCells.insert(y * w + x)
                default: tiles.append(.floor)
                }
                switch c {
                case "a": a.append(spot)
                case "b": b.append(spot)
                case "o": o.append(spot)
                case "s": center = spot
                default: break
                }
            }
        }
        self.tiles = tiles
        spawns = o.isEmpty ? [a, b] : [o]
        self.center = center
        goalCenters = goals.map { cells in
            cells.isEmpty ? nil : cells.reduce(V2.zero, +) * (1 / Double(cells.count))
        }
        // 连在一起的宝箱格子算一个宝箱
        var spots: [ChestSpot] = []
        var owner: [Int: Int] = [:]
        for cell in chestCells.sorted() where owner[cell] == nil {
            var group: [Int] = []
            var stack = [cell]
            owner[cell] = spots.count
            while let current = stack.popLast() {
                group.append(current)
                let cx = current % w, cy = current / w
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = cx + dx, ny = cy + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let next = ny * w + nx
                    if chestCells.contains(next) && owner[next] == nil {
                        owner[next] = spots.count
                        stack.append(next)
                    }
                }
            }
            let middle = group.reduce(V2.zero) { $0 + V2(Double($1 % w) + 0.5, Double($1 / w) + 0.5) } * (1 / Double(group.count))
            spots.append(ChestSpot(team: middle.y < Double(h) / 2 ? 1 : 0, center: middle, cells: group.sorted()))
        }
        chestSpots = spots
        chestOfCell = owner
    }

    public func tile(_ x: Int, _ y: Int) -> Tile {
        guard x >= 0, y >= 0, x < width, y < height else { return .wall }
        return tiles[y * width + x]
    }

    public func tile(at p: V2) -> Tile { tile(Int(p.x.rounded(.down)), Int(p.y.rounded(.down))) }

    /// 人走不过去（墙、宝箱、球门）
    public func solid(_ x: Int, _ y: Int) -> Bool {
        let t = tile(x, y)
        return t == .wall || t == .goal
    }

    /// 子弹过不去（墙、宝箱；球门挡不住子弹）
    public func blocks(_ p: V2) -> Bool { tile(at: p) == .wall }

    public func inBush(_ p: V2) -> Bool { tile(at: p) == .bush }

    /// 这一格是不是宝箱
    public func isChest(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height && chestOfCell[y * width + x] != nil
    }

    /// 这一点在第几个宝箱里
    public func chest(at p: V2) -> Int? {
        let x = Int(p.x.rounded(.down)), y = Int(p.y.rounded(.down))
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return chestOfCell[y * width + x]
    }

    /// 这一点在不在球门里：在的话是哪队守的门（上半边的门上边一队守）
    public func goalTeam(at p: V2) -> Int? {
        tile(at: p) == .goal ? (p.y < Double(height) / 2 ? 1 : 0) : nil
    }

    /// 一个圆有没有碰到墙或地图边。人：球门也算墙；球（ball）：球门进得去
    public func collides(_ p: V2, radius: Double, ball: Bool = false) -> Bool {
        let minX = Int((p.x - radius).rounded(.down)), maxX = Int((p.x + radius).rounded(.down))
        let minY = Int((p.y - radius).rounded(.down)), maxY = Int((p.y + radius).rounded(.down))
        for y in minY...maxY {
            for x in minX...maxX where ball ? tile(x, y) == .wall : solid(x, y) {
                let nearX = min(max(p.x, Double(x)), Double(x + 1))
                let nearY = min(max(p.y, Double(y)), Double(y + 1))
                let dx = p.x - nearX, dy = p.y - nearY
                if dx * dx + dy * dy < radius * radius { return true }
            }
        }
        return false
    }

    /// 两点之间没有墙挡着
    public func lineOfSight(_ a: V2, _ b: V2) -> Bool {
        let distance = a.distance(to: b)
        let steps = max(1, Int(distance / 0.25))
        for i in 1..<steps where blocks(V2.lerp(a, b, Double(i) / Double(steps))) { return false }
        return true
    }

    /// 离 p 最近的、站得下人的空地（跳到墙上、星星掉进墙里时用）
    public func nearestOpen(to p: V2, radius: Double = 0.42) -> V2 {
        if !collides(p, radius: radius) { return p }
        for ring in 1...8 {
            for k in 0..<(8 * ring) {
                let angle = Double(k) / Double(8 * ring) * 2 * .pi
                let candidate = p + V2(cos(angle), sin(angle)) * (Double(ring) * 0.5)
                if !collides(candidate, radius: radius) { return candidate }
            }
        }
        return center
    }

    /// 格子之间走得通的最短路（四个方向，绕开墙），返回路上每一格的中心（不含起点所在的格）
    public func path(from start: V2, to goal: V2) -> [V2] {
        let sx = Int(start.x), sy = Int(start.y), gx = Int(goal.x), gy = Int(goal.y)
        guard !solid(gx, gy), !solid(sx, sy) else { return [goal] }
        if sx == gx && sy == gy { return [goal] }
        var previous = [Int](repeating: -1, count: width * height)
        var queue = [sy * width + sx]
        previous[sy * width + sx] = sy * width + sx
        var head = 0
        let goalIndex = gy * width + gx
        while head < queue.count {
            let current = queue[head]
            head += 1
            if current == goalIndex { break }
            let cx = current % width, cy = current / width
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard !solid(nx, ny) else { continue }
                let next = ny * width + nx
                if previous[next] == -1 {
                    previous[next] = current
                    queue.append(next)
                }
            }
        }
        guard previous[goalIndex] != -1 else { return [goal] }
        var cells: [V2] = []
        var current = goalIndex
        while current != sy * width + sx {
            cells.append(V2(Double(current % width) + 0.5, Double(current / width) + 0.5))
            current = previous[current]
        }
        return cells.reversed()
    }
}

// MARK: - 一局

/// 一个人（玩家或电脑）这一局的样子
public struct Fighter: Equatable, Codable, Sendable, Identifiable {
    public struct Dash: Equatable, Codable, Sendable {
        public var direction: V2
        public var remaining: Double
        public var hit: [Int]
        /// 只是翻滚（小道具），不撞人
        public var harmless = false
    }

    public struct Leap: Equatable, Codable, Sendable {
        public var from: V2
        public var to: V2
        public var elapsed: Double
        public static let duration = 0.6
    }

    public struct Burst: Equatable, Codable, Sendable {
        public var left: Int
        public var timer: Double
        public var direction: V2
    }

    public var id: Int
    public var name: String
    public var team: Int
    public var brawler: Brawler
    public var isBot: Bool
    /// 等级（1–9，血量、伤害按等级加成）
    public var level = 1
    public var pos: V2
    public var facing: V2
    public var health: Int
    public var ammo: Double = 3
    /// 大招攒了多少（满了是 1）
    public var superCharge: Double = 0
    public var alive = true
    public var respawnIn: Double = 0
    /// 身上带着几颗星星（抢星星）
    public var stars = 0
    public var lastHurt: Double = -10
    public var lastAttack: Double = -10
    public var cooldown: Double = 0
    public var dash: Dash?
    public var leap: Leap?
    public var burst: Burst?
    /// 骨盾还剩几秒（这段时间受到的伤害少六成）
    public var shield: Double = 0
    /// 这一帧走的速度（电脑瞄准算提前量、画面上用）
    public var moving: V2 = .zero
    public var kills = 0
    public var deaths = 0
    public var damageDealt = 0
    /// 各自为战：第几名（被打倒或赢了时定下）
    public var place: Int?
    /// 讨伐骷髅王里的骷髅王（血多、个子大、自己会打，不复活）
    public var isBoss = false
    /// 一对一：带的几个角色（按顺序上场）、现在上的是第几个
    public var lineup: [Brawler] = []
    public var lineupIndex = 0
    /// 带的小道具、还能用几次、用完一次还要等几秒
    public var gadget: Gadget?
    public var gadgetUses = 0
    public var gadgetCooldown: Double = 0
    /// 星徽
    public var starPower: StarPower?
    /// 超级充能：解锁了没有、攒了多少（满了是 1）、开着还剩几秒
    public var hyperUnlocked = false
    public var hyperCharge: Double = 0
    public var hyperTime: Double = 0
    /// 疾行加速、被冰霜减速、隐身还剩几秒
    public var speedBoost: Double = 0
    public var slowed: Double = 0
    public var invisible: Double = 0
    /// 穿的第几套皮肤（0 原来的样子）、上次冒表情是什么时候
    public var skin = 0
    public var lastEmote: Double = -10

    public var maxHealth: Int {
        if isBoss { return ArenaGame.bossHealth(level: level) }
        let base = brawler.health(level: level)
        return starPower == .tough ? Int((Double(base) * 1.12).rounded()) : base
    }
    public var busy: Bool { dash != nil || leap != nil }
}

/// 飞着的子弹、炸弹
public struct Projectile: Equatable, Codable, Sendable, Identifiable {
    /// 扔出去的炸弹：从哪到哪、飞了多久、炸多大
    public struct Lob: Equatable, Codable, Sendable {
        public var from: V2
        public var to: V2
        public var duration: Double
        public var elapsed: Double
        public var blast: Double
    }

    public var id: Int
    public var owner: Int
    public var team: Int
    public var pos: V2
    public var velocity: V2
    public var rangeLeft: Double
    public var damage: Int
    public var radius: Double
    public var pierce = false
    /// 打中了攒大招（大招本身打中不攒）
    public var charges = true
    public var isSuper = false
    public var hit: [Int] = []
    public var lob: Lob?
}

/// 摇杆的输入：走的方向（长度 0–1）、这一帧开火、放大招（相对自己的偏移，单位格：方向 + 想打多远）、用小道具
public struct ArenaInput: Equatable, Codable, Sendable {
    public var move: V2
    public var attack: V2?
    public var special: V2?
    public var gadget: Bool
    /// 头顶冒个表情（ArenaEmote.id）
    public var emote: Int?

    public init(move: V2 = .zero, attack: V2? = nil, special: V2? = nil, gadget: Bool = false, emote: Int? = nil) {
        self.move = move
        self.attack = attack
        self.special = special
        self.gadget = gadget
        self.emote = emote
    }
}

public struct ArenaGame: Sendable {
    public enum Mode: String, CaseIterable, Codable, Sendable {
        case teamFight, stars, ball, heist, bounty, zone, knockout, showdown, duo, duel, boss

        public var title: String {
            switch self {
            case .teamFight: return "3v3 团战"
            case .stars: return "抢星星"
            case .ball: return "足球赛"
            case .heist: return "宝箱攻防"
            case .bounty: return "悬赏"
            case .zone: return "占点"
            case .knockout: return "三局两胜"
            case .showdown: return "大乱斗"
            case .duo: return "双人大乱斗"
            case .duel: return "一对一"
            case .boss: return "讨伐骷髅王"
            }
        }

        public var rules: String {
            switch self {
            case .teamFight: return "两队各 3 人，先打倒对方 10 次的赢；时间到了打倒次数多的赢。被打倒 3 秒后在自己家复活。"
            case .stars: return "中间每隔几秒冒一颗星星，捡到带在身上；一队凑够 10 颗、又比对方多，守住 15 秒就赢。被打倒身上的星星全掉出来。"
            case .ball:
                return "两队各 3 人，抢中间的球：走过去就捡起来，带着球时攻击键把球踢出去、大招踢得又快又远；踢进对面的球门进 1 球，先进 2 球的赢。进球后大家回去重新开球；带着球不能开枪，被打倒球就掉了。"
            case .heist: return "两队家里各有一个宝箱：打对面的宝箱、守住自己的，先把对面宝箱打爆的赢；时间到了宝箱剩的血多的赢。"
            case .bounty:
                return "每个人头上有悬赏（一开始 2 颗星）：打倒一个敌人，按他的悬赏给队里加星星，自己的悬赏 +1（最多 7 颗），被打倒了回到 2 颗。时间到了星星多的赢。"
            case .zone: return "地图中间有个圈，只有一队的人站在圈里就给这队加分，两队都在就谁也不加，先满 100 的赢。"
            case .knockout: return "被打倒了这一局就不能复活：一队全倒下，另一队赢这一局，先赢两局的赢。每局开打 40 秒后毒圈开始缩小。"
            case .showdown: return "6 个人各打各的，不复活；毒圈慢慢缩小，圈外一直掉血，活到最后的赢。"
            case .duo: return "6 个人分 3 队、两人一队，毒圈慢慢缩小；被打倒了只要队友还活着，10 秒后在队友身边复活，最后剩下的一队赢。"
            case .duel: return "1 对 1，每人带 3 个角色轮流上场：一个被打倒了，3 秒后换下一个；先把对方 3 个都打倒的赢。"
            case .boss:
                return "3 个勇者一起打骷髅王：它会砸地（地上的红圈快躲开）、冲撞、召唤骨塔，血少了会发狂；3 分钟内打倒它就赢。勇者被打倒 5 秒后复活。"
            }
        }

        /// 一局最长几秒（三局两胜是所有局加起来的上限，每局另算）
        public var duration: Double {
            switch self {
            case .stars, .boss: return 180
            case .knockout: return 400
            default: return 150
            }
        }

        /// 两队对打（下边一队、上边一队）；大乱斗、双人大乱斗不是
        public var isTeams: Bool { self != .showdown && self != .duo }

        /// 有毒圈
        public var hasPoison: Bool { self == .showdown || self == .duo || self == .knockout }

        /// 被打倒了还能回来（三局两胜这一局、大乱斗不行；双人大乱斗要队友还活着；一对一换下一个角色上）
        public var respawns: Bool { self != .showdown && self != .knockout }

        /// 被打倒后几秒回来
        public var respawnDelay: Double {
            switch self {
            case .ball: return 4
            case .boss: return 5
            case .duo: return 10
            default: return ArenaGame.respawnDelay
            }
        }

        /// 每个座位在哪队（也就是一局几个人）：两队对打 3v3，大乱斗 6 个各自为战，双人大乱斗 3 队各 2 人，一对一 1v1，
        /// 讨伐骷髅王 3 个勇者 + 骷髅王
        public var seatTeams: [Int] {
            switch self {
            case .showdown: return [0, 1, 2, 3, 4, 5]
            case .duo: return [0, 0, 1, 1, 2, 2]
            case .duel: return [0, 1]
            case .boss: return [0, 0, 0, 1]
            default: return [0, 0, 0, 1, 1, 1]
            }
        }
    }

    public enum Result: Equatable, Sendable {
        case team(Int)
        case survivor(Int)
        case draw
    }

    /// 这一帧发生的事（画面上放特效、飘字用；画完清掉）
    public enum Event: Equatable, Sendable {
        case hit(target: Int, amount: Int)
        case knockout(target: Int, by: Int?)
        case explosion(at: V2, radius: Double)
        case pickup(fighter: Int)
        case respawn(fighter: Int)
        case special(fighter: Int)
        /// 开了一枪（普通攻击），画面上放出手的动作
        case attack(fighter: Int)
        /// 回了血（骨盾、亡灵之地）
        case heal(target: Int, amount: Int)
        /// 进球了（哪队进的）
        case goal(team: Int)
        /// 三局两胜：这一局分出来了（哪队赢；nil 是平局）
        case round(winner: Int?)
        /// 进球、一局打完停一会儿后，大家回到出发的地方
        case reset
        /// 宝箱挨打（第几个宝箱、多少）
        case chestHit(chest: Int, amount: Int)
        /// 用了小道具
        case gadget(fighter: Int)
        /// 开了超级充能
        case hyper(fighter: Int)
        /// 头顶冒了个表情
        case emote(fighter: Int, emote: Int)
    }

    /// 亡灵之地：圈里的队友回血、敌人掉血，每 0.5 秒结一次
    public struct Zone: Equatable, Sendable {
        public var center: V2
        public var radius: Double
        public var team: Int
        public var owner: Int
        public var left: Double
        /// 每秒回多少血、扣多少血
        public var heal: Int
        public var damage: Int
        public var tick: Double = 0.25
        public static let duration = 5.0
    }

    /// 骨灵召唤的骨塔：站在原地，自动打看得见、够得着的最近的敌人
    public struct Turret: Equatable, Sendable {
        public var id: Int
        public var owner: Int
        public var team: Int
        public var pos: V2
        public var facing: V2
        public var health: Int
        public var maxHealth: Int
        public var left: Double
        public var cooldown: Double = 0.4
        public static let duration = 12.0
        public static let range = 6.5
        public static let radius = 0.45
    }

    public struct Countdown: Equatable, Sendable {
        public var team: Int
        public var left: Double
    }

    /// 足球：在哪、往哪滚、谁带着
    public struct Ball: Equatable, Sendable {
        public var pos: V2
        public var velocity: V2 = .zero
        public var carrier: Int?
        /// 刚踢出去的人一小会儿碰不到球（不然一踢就又捡回来了）
        public var kicker: Int?
        public var kickTimer: Double = 0
        public static let radius = 0.3
    }

    /// 宝箱攻防的宝箱（和地图上的宝箱一个对一个）
    public struct Chest: Equatable, Sendable {
        public var team: Int
        public var center: V2
        public var health: Int
        public var maxHealth: Int
        public static let fullHealth = 36000
    }

    /// 地上的红圈：时间到了炸（骷髅王砸地）
    public struct Warning: Equatable, Sendable {
        public var center: V2
        public var radius: Double
        public var left: Double
        /// 一共要等几秒（画面上按这个画红圈慢慢填满）
        public var total: Double
        public var damage: Int
        public var owner: Int
        public var team: Int
    }

    /// 报名的人
    public struct Entrant: Equatable, Codable, Sendable {
        public var name: String
        public var brawler: Brawler
        public var isBot: Bool
        public var team: Int
        public var level: Int
        /// 一对一带的角色（第一个是 brawler；不够 3 个开局时补上）
        public var lineup: [Brawler]
        /// 带的小道具、星徽、超级充能
        public var loadout: ArenaLoadout

        public init(name: String, brawler: Brawler, isBot: Bool, team: Int, level: Int = 1, lineup: [Brawler] = [],
                    loadout: ArenaLoadout = ArenaLoadout()) {
            self.name = name
            self.brawler = brawler
            self.isBot = isBot
            self.team = team
            self.level = level
            self.lineup = lineup
            self.loadout = loadout
        }

        /// 老版本存的、发来的没有等级（按 1 级）、没有一对一的阵容
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            brawler = try container.decode(Brawler.self, forKey: .brawler)
            isBot = try container.decode(Bool.self, forKey: .isBot)
            team = try container.decode(Int.self, forKey: .team)
            level = try container.decodeIfPresent(Int.self, forKey: .level) ?? 1
            lineup = try container.decodeIfPresent([Brawler].self, forKey: .lineup) ?? []
            loadout = try container.decodeIfPresent(ArenaLoadout.self, forKey: .loadout) ?? ArenaLoadout()
        }
    }

    public static let fighterRadius = 0.42
    public static let goal = 10
    public static let starHold = 15.0
    public static let zoneRadius = 2.5
    public static let respawnDelay = 3.0
    /// 足球先进几球赢、三局两胜先赢几局
    public static let ballGoals = 2
    public static let roundsToWin = 2
    /// 三局两胜：每局开打多少秒后毒圈开始缩、一局最长打多久
    public static let roundPoison = 40.0
    public static let roundLimit = 80.0
    /// 进球、一局打完后停几秒
    public static let breakTime = 2.5
    /// 悬赏：一开始几颗星、最多几颗
    public static let startingBounty = 2
    public static let maxBounty = 7

    public let mode: Mode
    public let map: ArenaMap
    public internal(set) var time: Double = 0
    public internal(set) var fighters: [Fighter]
    public internal(set) var projectiles: [Projectile] = []
    /// 地上的星星
    public internal(set) var stars: [V2] = []
    public internal(set) var teamKills = [0, 0]
    public internal(set) var zoneProgress = [0.0, 0.0]
    public internal(set) var countdown: Countdown?
    /// 毒圈半径（各自为战）
    public internal(set) var safeRadius: Double
    public internal(set) var result: Result?
    /// 地上的亡灵之地、骨塔
    public internal(set) var zones: [Zone] = []
    public internal(set) var turrets: [Turret] = []
    /// 两队的分：足球进了几球、悬赏攒了几颗星、三局两胜赢了几局、一对一打倒对方几个
    public internal(set) var score = [0, 0]
    public internal(set) var ball: Ball?
    public internal(set) var chests: [Chest] = []
    /// 地上快要炸的红圈
    public internal(set) var warnings: [Warning] = []
    /// 三局两胜：第几局、这局从第几秒开始
    public internal(set) var round = 1
    public internal(set) var roundStart = 0.0
    /// 进球、一局打完后停一会儿（停完大家回到出发的地方）
    public internal(set) var pause = 0.0
    public var events: [Event] = []
    var nextProjectile = 1
    var nextTurret = 1
    private var starTimer = 0.0
    var random: SeededRandom
    var bossBrain = BossBrain()

    /// map：用哪张地图；nil 或者不是这个玩法的地图（拿团战的图打大乱斗）就用这个玩法的第一张。
    /// bossLevel：讨伐骷髅王时骷髅王几级（nil：按勇者们的平均等级；冒险里每关定好）
    public init(mode: Mode, entrants: [Entrant], seed: UInt64, map chosen: ArenaMap? = nil, bossLevel: Int? = nil) {
        self.mode = mode
        let pool = ArenaMap.pool(for: mode)
        if let chosen, pool.contains(where: { $0.id == chosen.id })
            || (chosen.id == "custom" && chosen.spawns.count == (mode.isTeams ? 2 : 1)) {
            map = chosen
        } else {
            map = pool[0]
        }
        random = SeededRandom(seed: seed)
        safeRadius = Double(max(map.width, map.height))
        var slots = [Int: Int]()
        var list: [Fighter] = []
        let anchors = Self.duoAnchors(map)
        for (index, entrant) in entrants.enumerated() {
            let team: Int
            switch mode {
            case .showdown: team = index
            case .duo: team = min(max(entrant.team, 0), 2)
            default: team = min(max(entrant.team, 0), 1)
            }
            let slot = slots[team, default: 0]
            slots[team, default: 0] += 1
            let spawn: V2
            switch mode {
            case .showdown:
                let group = map.spawns[0]
                spawn = group.isEmpty ? map.center : group[index % group.count]
            case .duo:
                spawn = Self.duoSpawn(map, anchors: anchors, team: team, slot: slot)
            default:
                let group = map.spawns.indices.contains(team) ? map.spawns[team] : []
                spawn = group.isEmpty ? map.center : group[slot % group.count]
            }
            let level = min(max(entrant.level, 1), ArenaProgress.maxLevel)
            var fighter = Fighter(id: index, name: entrant.name, team: team, brawler: entrant.brawler, isBot: entrant.isBot, level: level,
                                  pos: spawn, facing: (map.center - spawn).normalized, health: entrant.brawler.health(level: level))
            if mode == .duel { fighter.lineup = Self.lineup(entrant, seed: seed &+ UInt64(index + 1)) }
            if mode == .bounty { fighter.stars = Self.startingBounty }
            Self.equip(&fighter, entrant.loadout)
            list.append(fighter)
        }
        fighters = list
        switch mode {
        case .ball:
            ball = Ball(pos: map.center)
        case .heist:
            chests = map.chestSpots.map { Chest(team: $0.team, center: $0.center, health: Chest.fullHealth, maxHealth: Chest.fullHealth) }
        case .boss:
            setUpBoss(level: bossLevel)
        default:
            break
        }
    }

    /// 还剩几秒（三局两胜是这一局还剩几秒）
    public var timeLeft: Double {
        mode == .knockout ? max(0, Self.roundLimit - (time - roundStart)) : max(0, mode.duration - time)
    }

    /// 毒圈在缩
    public var poisonShrinking: Bool {
        switch mode {
        case .showdown, .duo: return time > 15
        case .knockout: return time - roundStart > Self.roundPoison
        default: return false
        }
    }

    /// 一队身上带着几颗星星
    public func teamStars(_ team: Int) -> Int {
        fighters.filter { $0.team == team }.reduce(0) { $0 + $1.stars }
    }

    public var aliveCount: Int { fighters.filter(\.alive).count }

    /// 这个人现在看不看得见：在草丛里的，敌人走近（2.5 格内）或者他刚开过火才看得见
    public func isVisible(_ fighter: Fighter, to team: Int) -> Bool {
        guard fighter.alive else { return false }
        if fighter.isBoss || fighter.team == team || time - fighter.lastAttack < 1 { return true }
        // 隐身：贴得很近才看得见；草丛里：走近才看得见
        if fighter.invisible > 0 {
            return fighters.contains { $0.alive && $0.team == team && $0.pos.distance(to: fighter.pos) < 1.5 }
        }
        if !map.inBush(fighter.pos) { return true }
        return fighters.contains { $0.alive && $0.team == team && $0.pos.distance(to: fighter.pos) < 2.5 }
    }

    // MARK: 一帧

    public mutating func step(_ dt: Double, inputs: [Int: ArenaInput]) {
        guard result == nil else { return }
        time += dt
        // 进球、一局打完：停一会儿，停完大家回到出发的地方
        if pause > 0 {
            pause -= dt
            if pause <= 0 {
                pause = 0
                resetField()
            }
            return
        }
        for i in fighters.indices {
            if fighters[i].isBoss {
                updateBoss(i, dt)
            } else {
                update(i, inputs[i] ?? ArenaInput(), dt)
            }
        }
        moveProjectiles(dt)
        updateWarnings(dt)
        updateZones(dt)
        updateTurrets(dt)
        switch mode {
        case .stars: updateStars(dt)
        case .zone: updateZone(dt)
        case .ball: updateBall(dt)
        case .showdown, .duo, .knockout: updatePoison(dt)
        case .teamFight, .heist, .bounty, .duel, .boss: break
        }
        decide()
    }

    private mutating func update(_ i: Int, _ input: ArenaInput, _ dt: Double) {
        // 表情：倒下了也能冒，1.5 秒最多一个
        if let emote = input.emote, time - fighters[i].lastEmote >= 1.5 {
            fighters[i].lastEmote = time
            events.append(.emote(fighter: i, emote: emote))
        }
        if !fighters[i].alive {
            guard canRespawn(i) else { return }
            fighters[i].respawnIn -= dt
            if fighters[i].respawnIn <= 0 { respawn(i) }
            return
        }
        fighters[i].cooldown -= dt
        fighters[i].ammo = min(3, fighters[i].ammo + dt / reloadTime(fighters[i]))
        if fighters[i].shield > 0 { fighters[i].shield = max(0, fighters[i].shield - dt) }
        tickStatus(i, dt)
        if input.gadget { useGadget(i, move: input.move) }
        if fighters[i].leap != nil {
            updateLeap(i, dt)
            return
        }
        if fighters[i].dash != nil {
            updateDash(i, dt)
            return
        }
        let move = input.move.clamped(to: 1)
        let speed = moveSpeed(fighters[i])
        fighters[i].moving = move * speed
        if move.length > 0.05 {
            walk(i, by: move * (speed * dt))
            if input.attack == nil && input.special == nil { fighters[i].facing = move.normalized }
        }
        if var burst = fighters[i].burst {
            burst.timer -= dt
            while burst.timer <= 0 && burst.left > 0 {
                burstShot(i, burst.direction)
                burst.left -= 1
                burst.timer += fighters[i].brawler == .shade ? 0.14 : 0.08
            }
            fighters[i].burst = burst.left > 0 ? burst : nil
        }
        if ball?.carrier == i {
            // 带着球：攻击键把球踢出去，大招大力踢；不开枪
            if let aim = input.special, fighters[i].superCharge >= 1 {
                kick(i, aim, power: true)
            } else if let aim = input.attack {
                kick(i, aim, power: false)
            }
        } else {
            if let aim = input.attack, fighters[i].ammo >= 1, fighters[i].cooldown <= 0 {
                attack(i, aim)
            }
            if let aim = input.special, fighters[i].superCharge >= 1, fighters[i].alive {
                special(i, aim)
            }
        }
        if fighters[i].alive, time - max(fighters[i].lastHurt, fighters[i].lastAttack) > 3 {
            let gain = Int((Double(fighters[i].maxHealth) * 0.13 * dt).rounded(.up))
            fighters[i].health = min(fighters[i].maxHealth, fighters[i].health + gain)
        }
    }

    /// 走：先整个走，碰墙了就只走横的或只走竖的（贴着墙滑）
    mutating func walk(_ i: Int, by delta: V2) {
        fighters[i].pos = Self.walk(from: fighters[i].pos, by: delta, on: map)
    }

    /// 被打倒的这个人还回不回来：大乱斗、三局两胜（这一局）不回来，双人大乱斗要队友还活着，一对一要还有角色没上过
    func canRespawn(_ i: Int) -> Bool {
        guard mode.respawns, !fighters[i].isBoss else { return false }
        switch mode {
        case .duo: return fighters.contains { $0.team == fighters[i].team && $0.id != i && $0.alive }
        case .duel: return fighters[i].lineupIndex + 1 < fighters[i].lineup.count
        default: return true
        }
    }

    /// 出发的地方（复活、重新开球时站回去）：自己队的出生点里按在队里的先后挑
    func homeSpot(_ i: Int) -> V2 {
        let team = fighters[i].team
        if !mode.isTeams {
            let group = map.spawns.first ?? []
            return group.isEmpty ? map.center : group[i % group.count]
        }
        let group = map.spawns.indices.contains(team) ? map.spawns[team] : []
        let slot = fighters.filter { $0.team == team && $0.id < i }.count
        return group.isEmpty ? map.center : group[slot % group.count]
    }

    private mutating func respawn(_ i: Int) {
        let spawn: V2
        if mode == .duo, let mate = fighters.first(where: { $0.team == fighters[i].team && $0.id != i && $0.alive }) {
            // 双人大乱斗：在队友身边回来
            spawn = map.nearestOpen(to: mate.pos + V2(0.9, 0))
        } else {
            spawn = homeSpot(i)
        }
        if mode == .duel {
            // 一对一：换下一个角色上（小道具、星徽按这个角色的等级带）
            fighters[i].lineupIndex = min(fighters[i].lineupIndex + 1, max(fighters[i].lineup.count - 1, 0))
            if fighters[i].lineup.indices.contains(fighters[i].lineupIndex) {
                fighters[i].brawler = fighters[i].lineup[fighters[i].lineupIndex]
            }
            fighters[i].superCharge = 0
            fighters[i].hyperCharge = 0
            Self.equip(&fighters[i], ArenaLoadout.basic(fighters[i].brawler, level: fighters[i].level))
        }
        fighters[i].speedBoost = 0
        fighters[i].slowed = 0
        fighters[i].invisible = 0
        fighters[i].hyperTime = 0
        fighters[i].pos = spawn
        fighters[i].facing = (map.center - spawn).normalized
        fighters[i].health = fighters[i].maxHealth
        fighters[i].ammo = 3
        fighters[i].alive = true
        fighters[i].lastHurt = time
        fighters[i].moving = .zero
        fighters[i].shield = 0
        events.append(.respawn(fighter: i))
    }

    // MARK: 攻击

    private mutating func attack(_ i: Int, _ aim: V2) {
        let fighter = fighters[i]
        let direction = aim.length > 0.01 ? aim.normalized : fighter.facing
        fighters[i].ammo -= 1
        fighters[i].cooldown = 0.4
        fighters[i].lastAttack = time
        fighters[i].facing = direction
        events.append(.attack(fighter: i))
        switch fighter.brawler {
        case .knight:
            spread(i, direction, count: 5, angle: 0.52, speed: 13, range: 4.5, damage: 360, radius: 0.2)
        case .ranger:
            shoot(i, direction, speed: 17, range: fighter.starPower == .farsight ? 10.5 : 9, damage: 1300, radius: 0.22)
        case .barbarian:
            spread(i, direction, count: 3, angle: 0.9, speed: 14, range: 2.6, damage: 700, radius: 0.3)
        case .mage:
            lob(i, to: fighter.pos + direction * min(max(aim.length, 1.5), fighter.brawler.attackRange),
                duration: 0.7, blast: fighter.starPower == .bigFire ? 1.5 : 1.2, damage: 1200, isSuper: false)
        case .assassin:
            fighters[i].burst = Fighter.Burst(left: fighter.starPower == .fiveKnives ? 5 : 4, timer: 0, direction: direction)
        case .guardian:
            shoot(i, direction, speed: 12, range: 3.2, damage: 1100, radius: 0.5, pierce: true)
        case .necromancer:
            shoot(i, direction, speed: 9, range: 7.5, damage: 900, radius: 0.32, pierce: true)
        case .shade:
            fighters[i].burst = Fighter.Burst(left: 2, timer: 0, direction: direction)
        case .summoner:
            spread(i, direction, count: 3, angle: 0.3, speed: 14, range: 5.5, damage: 420, radius: 0.2)
        }
    }

    /// 连发的一发：刺客的飞刀、幽影的短弩
    private mutating func burstShot(_ i: Int, _ direction: V2) {
        let wobble = (random.chance(0.5) ? 1.0 : -1.0) * 0.03
        if fighters[i].brawler == .shade {
            shoot(i, direction.rotated(by: wobble), speed: 18, range: 6.5, damage: 650, radius: 0.22)
        } else {
            shoot(i, direction.rotated(by: wobble), speed: 14, range: 7, damage: 380, radius: 0.2)
        }
    }

    private mutating func special(_ i: Int, _ aim: V2) {
        let fighter = fighters[i]
        let direction = aim.length > 0.01 ? aim.normalized : fighter.facing
        fighters[i].superCharge = 0
        fighters[i].lastAttack = time
        fighters[i].facing = direction
        events.append(.special(fighter: i))
        // 超级充能满了：这一下是加强版，还开 5 秒加速、加伤、减伤
        let hyper = startHyper(i)
        switch fighter.brawler {
        case .knight:
            fighters[i].dash = Fighter.Dash(direction: direction, remaining: hyper ? 8 : fighter.brawler.superRange, hit: [])
        case .ranger:
            shoot(i, direction, speed: 18, range: fighter.brawler.superRange + (hyper ? 2 : 0), damage: hyper ? 3100 : 2400,
                  radius: hyper ? 0.6 : 0.35, pierce: true, isSuper: true)
        case .barbarian:
            let target = map.nearestOpen(to: fighter.pos + direction * min(max(aim.length, 2), fighter.brawler.superRange))
            fighters[i].leap = Fighter.Leap(from: fighter.pos, to: target, elapsed: 0)
        case .mage:
            lob(i, to: fighter.pos + direction * min(max(aim.length, 2), fighter.brawler.superRange),
                duration: 0.9, blast: hyper ? 3 : 2.2, damage: 2600, isSuper: true)
        case .assassin:
            spread(i, direction, count: hyper ? 18 : 12, angle: hyper ? 1.4 : 1.05, speed: 14, range: 7, damage: 500, radius: 0.2, isSuper: true)
        case .guardian:
            fighters[i].shield = fighter.starPower == .longShield ? 6 : 4
            let healed = min(power(i, hyper ? 2400 : 1200), fighters[i].maxHealth - fighters[i].health)
            if healed > 0 {
                fighters[i].health += healed
                events.append(.heal(target: i, amount: healed))
            }
        case .necromancer:
            let center = map.nearestOpen(to: fighter.pos + direction * min(max(aim.length, 1.5), fighter.brawler.superRange), radius: 0.2)
            zones.append(Zone(center: center, radius: hyper ? 3 : 2.2, team: fighter.team, owner: i,
                              left: fighter.starPower == .feast ? 7 : Zone.duration, heal: power(i, 700), damage: power(i, 350)))
        case .shade:
            // 一下闪过去（能穿墙），落地炸一下
            let target = map.nearestOpen(to: fighter.pos + direction * min(max(aim.length, 2), fighter.brawler.superRange))
            fighters[i].pos = target
            fighters[i].moving = .zero
            blast(at: target, radius: hyper ? 2.4 : 1.6, damage: power(i, fighter.starPower == .ambush ? 1960 : 1400), by: i,
                  team: fighter.team, charges: false)
        case .summoner:
            // 同时只有一座（星徽「双塔」两座）：再召唤就换掉最早的
            let spot = map.nearestOpen(to: fighter.pos + direction * min(max(aim.length, 1.2), fighter.brawler.superRange))
            let health = Int(Double(power(i, 2800)) * (fighter.starPower == .sturdy ? 1.5 : 1) * (hyper ? 2 : 1))
            let limit = fighter.starPower == .twin ? 2 : 1
            let mine = turrets.filter { $0.owner == i }.sorted { $0.id < $1.id }
            if mine.count >= limit {
                let gone = Set(mine.prefix(mine.count - limit + 1).map(\.id))
                turrets.removeAll { gone.contains($0.id) }
            }
            turrets.append(Turret(id: nextTurret, owner: i, team: fighter.team, pos: spot, facing: direction,
                                  health: health, maxHealth: health, left: Turret.duration))
            nextTurret += 1
        }
    }

    mutating func shoot(_ i: Int, _ direction: V2, speed: Double, range: Double, damage: Int, radius: Double,
                                pierce: Bool = false, isSuper: Bool = false) {
        let fighter = fighters[i]
        projectiles.append(Projectile(id: nextProjectile, owner: i, team: fighter.team, pos: fighter.pos + direction * 0.3,
                                      velocity: direction * speed, rangeLeft: range, damage: power(i, damage), radius: radius,
                                      pierce: pierce, charges: !isSuper, isSuper: isSuper))
        nextProjectile += 1
    }

    /// 按这个人的等级加成后的伤害
    func power(_ i: Int, _ damage: Int) -> Int {
        let hyper = fighters[i].hyperTime > 0 ? 1.1 : 1
        return Int((Double(damage) * Brawler.boost(fighters[i].level) * hyper).rounded())
    }

    mutating func spread(_ i: Int, _ direction: V2, count: Int, angle: Double, speed: Double, range: Double,
                                 damage: Int, radius: Double, isSuper: Bool = false) {
        for k in 0..<count {
            let offset = count == 1 ? 0 : angle * (Double(k) / Double(count - 1) - 0.5)
            shoot(i, direction.rotated(by: offset), speed: speed, range: range, damage: damage, radius: radius, isSuper: isSuper)
        }
    }

    private mutating func lob(_ i: Int, to target: V2, duration: Double, blast: Double, damage: Int, isSuper: Bool) {
        let fighter = fighters[i]
        projectiles.append(Projectile(id: nextProjectile, owner: i, team: fighter.team, pos: fighter.pos, velocity: .zero,
                                      rangeLeft: .infinity, damage: power(i, damage), radius: 0.3, charges: !isSuper, isSuper: isSuper,
                                      lob: Projectile.Lob(from: fighter.pos, to: target, duration: duration, elapsed: 0, blast: blast)))
        nextProjectile += 1
    }

    mutating func updateDash(_ i: Int, _ dt: Double) {
        guard var dash = fighters[i].dash else { return }
        let step = min(dash.remaining, 12 * dt)
        let next = fighters[i].pos + dash.direction * step
        if map.collides(next, radius: Self.fighterRadius) {
            fighters[i].dash = nil
            return
        }
        fighters[i].pos = next
        fighters[i].moving = dash.direction * 12
        dash.remaining -= step
        for j in fighters.indices where !dash.harmless && fighters[j].alive && fighters[j].team != fighters[i].team && !dash.hit.contains(j)
            && fighters[j].pos.distance(to: next) < Self.hitRadius(fighters[j]) + Self.hitRadius(fighters[i]) + 0.08 {
            dash.hit.append(j)
            let damage = fighters[i].isBoss ? 2000 : (fighters[i].hyperTime > 0 ? 2400 : 1600)
            hurt(j, power(i, damage), by: i, charges: false)
            // 星徽「骑士精神」：撞到一个回一口血
            if fighters[i].starPower == .chivalry, fighters[i].alive {
                let healed = min(power(i, 800), fighters[i].maxHealth - fighters[i].health)
                if healed > 0 {
                    fighters[i].health += healed
                    events.append(.heal(target: i, amount: healed))
                }
            }
        }
        fighters[i].dash = dash.remaining > 0.01 ? dash : nil
    }

    private mutating func updateLeap(_ i: Int, _ dt: Double) {
        guard var leap = fighters[i].leap else { return }
        leap.elapsed += dt
        let t = min(1, leap.elapsed / Fighter.Leap.duration)
        fighters[i].pos = V2.lerp(leap.from, leap.to, t)
        if t >= 1 {
            fighters[i].leap = nil
            let radius = fighters[i].hyperTime > 0 ? 2.4 : 1.6
            // 星徽「震荡」：砸中的人走得慢
            if fighters[i].starPower == .quake {
                for j in fighters.indices where fighters[j].alive && fighters[j].team != fighters[i].team
                    && fighters[j].pos.distance(to: leap.to) < radius + Self.hitRadius(fighters[j]) {
                    fighters[j].slowed = max(fighters[j].slowed, 2)
                }
            }
            blast(at: leap.to, radius: radius, damage: power(i, 1800), by: i, team: fighters[i].team, charges: false)
        } else {
            fighters[i].leap = leap
        }
    }

    private mutating func moveProjectiles(_ dt: Double) {
        var kept: [Projectile] = []
        for var p in projectiles {
            if var lob = p.lob {
                lob.elapsed += dt
                if lob.elapsed >= lob.duration {
                    blast(at: lob.to, radius: lob.blast, damage: p.damage, by: p.owner, team: p.team, charges: p.charges)
                    continue
                }
                p.lob = lob
                p.pos = V2.lerp(lob.from, lob.to, lob.elapsed / lob.duration)
                kept.append(p)
                continue
            }
            let delta = p.velocity * dt
            p.pos = p.pos + delta
            p.rangeLeft -= delta.length
            if p.rangeLeft <= 0 { continue }
            if map.blocks(p.pos) {
                // 打到墙上；是对面的宝箱就扣宝箱的血
                if let k = map.chest(at: p.pos), chests.indices.contains(k), chests[k].team != p.team {
                    hitChest(k, p.damage, by: p.owner)
                }
                continue
            }
            var consumed = false
            for j in fighters.indices where fighters[j].alive && fighters[j].team != p.team && fighters[j].leap == nil && !p.hit.contains(j) {
                guard fighters[j].pos.distance(to: p.pos) < Self.hitRadius(fighters[j]) + p.radius else { continue }
                hurt(j, p.damage, by: p.owner, charges: p.charges)
                if p.pierce {
                    p.hit.append(j)
                } else {
                    consumed = true
                    break
                }
            }
            // 打到对面的骨塔（穿透的记一下打过哪座：骨塔用负的编号，和人分开）
            if !consumed {
                for t in turrets.indices where turrets[t].team != p.team && turrets[t].health > 0 && !p.hit.contains(-turrets[t].id)
                    && turrets[t].pos.distance(to: p.pos) < Turret.radius + p.radius {
                    turrets[t].health -= p.damage
                    if p.pierce {
                        p.hit.append(-turrets[t].id)
                    } else {
                        consumed = true
                        break
                    }
                }
            }
            if !consumed { kept.append(p) }
        }
        projectiles = kept
    }

    mutating func blast(at point: V2, radius: Double, damage: Int, by owner: Int, team: Int, charges: Bool) {
        events.append(.explosion(at: point, radius: radius))
        for j in fighters.indices where fighters[j].alive && fighters[j].team != team
            && fighters[j].pos.distance(to: point) < radius + Self.hitRadius(fighters[j]) {
            hurt(j, damage, by: owner, charges: charges)
        }
        for t in turrets.indices where turrets[t].team != team && turrets[t].pos.distance(to: point) < radius + Turret.radius {
            turrets[t].health -= damage
        }
        for k in chests.indices where chests[k].team != team && chests[k].center.distance(to: point) < radius + 1.3 {
            hitChest(k, damage, by: owner)
        }
    }

    /// 亡灵之地：每 0.5 秒给圈里的队友回血、敌人扣血，时间到了消失
    private mutating func updateZones(_ dt: Double) {
        guard !zones.isEmpty else { return }
        for k in zones.indices {
            zones[k].left -= dt
            zones[k].tick -= dt
            guard zones[k].tick <= 0 else { continue }
            zones[k].tick += 0.5
            let zone = zones[k]
            for j in fighters.indices where fighters[j].alive && fighters[j].pos.distance(to: zone.center) < zone.radius {
                if fighters[j].team == zone.team {
                    let amount = min(zone.heal / 2, fighters[j].maxHealth - fighters[j].health)
                    if amount > 0 {
                        fighters[j].health += amount
                        events.append(.heal(target: j, amount: amount))
                    }
                } else {
                    hurt(j, zone.damage / 2, by: zone.owner, charges: false)
                }
            }
        }
        zones.removeAll { $0.left <= 0 }
    }

    /// 骨塔：每 0.7 秒朝看得见、够得着的最近的敌人打一发；被打掉了炸一下，时间到了消失
    private mutating func updateTurrets(_ dt: Double) {
        guard !turrets.isEmpty else { return }
        for k in turrets.indices {
            turrets[k].left -= dt
            turrets[k].cooldown -= dt
            let turret = turrets[k]
            guard turret.cooldown <= 0, turret.health > 0 else { continue }
            let targets = fighters.filter {
                $0.alive && $0.team != turret.team && isVisible($0, to: turret.team)
                    && $0.pos.distance(to: turret.pos) < Turret.range && map.lineOfSight(turret.pos, $0.pos)
            }
            guard let target = targets.min(by: { $0.pos.distance(to: turret.pos) < $1.pos.distance(to: turret.pos) }) else { continue }
            let direction = (target.pos - turret.pos).normalized
            turrets[k].cooldown = 0.7
            turrets[k].facing = direction
            let damage = fighters.indices.contains(turret.owner) ? power(turret.owner, 320) : 320
            projectiles.append(Projectile(id: nextProjectile, owner: turret.owner, team: turret.team, pos: turret.pos + direction * 0.4,
                                          velocity: direction * 13, rangeLeft: Turret.range + 0.5, damage: damage, radius: 0.2,
                                          charges: false))
            nextProjectile += 1
        }
        for turret in turrets where turret.health <= 0 {
            events.append(.explosion(at: turret.pos, radius: 0.8))
        }
        turrets.removeAll { $0.left <= 0 || $0.health <= 0 }
    }

    mutating func hurt(_ j: Int, _ raw: Int, by attacker: Int?, charges: Bool) {
        guard fighters[j].alive, raw > 0 else { return }
        // 骨盾、铁壁少受六成，超级充能少受一成半
        let factor = damageTaken(fighters[j])
        let amount = factor < 1 ? max(1, Int((Double(raw) * factor).rounded())) : raw
        let dealt = min(amount, fighters[j].health)
        fighters[j].health -= amount
        fighters[j].lastHurt = time
        events.append(.hit(target: j, amount: amount))
        if let attacker, fighters.indices.contains(attacker) {
            fighters[attacker].damageDealt += dealt
            if charges {
                fighters[attacker].superCharge = min(1, fighters[attacker].superCharge + Double(amount) / superCost(fighters[attacker]))
                chargeHyper(attacker, amount)
            }
            // 星徽「嗜血」：打中回伤害的 15%
            if fighters[attacker].starPower == .bloodlust, fighters[attacker].alive, attacker != j {
                let healed = min(Int((Double(dealt) * 0.15).rounded()), fighters[attacker].maxHealth - fighters[attacker].health)
                if healed > 0 {
                    fighters[attacker].health += healed
                    events.append(.heal(target: attacker, amount: healed))
                }
            }
            // 星徽「反震」：举着骨盾时打你的人掉血
            if charges, attacker != j, fighters[j].starPower == .thorns, fighters[j].shield > 0 {
                hurt(attacker, power(j, 250), by: j, charges: false)
            }
        }
        if fighters[j].health <= 0 { knockOut(j, by: attacker) }
    }

    mutating func knockOut(_ j: Int, by attacker: Int?) {
        let victim = fighters[j]
        fighters[j].alive = false
        fighters[j].health = 0
        fighters[j].deaths += 1
        fighters[j].dash = nil
        fighters[j].leap = nil
        fighters[j].burst = nil
        fighters[j].shield = 0
        fighters[j].moving = .zero
        fighters[j].speedBoost = 0
        fighters[j].slowed = 0
        fighters[j].invisible = 0
        fighters[j].hyperTime = 0
        if let attacker, attacker != j {
            fighters[attacker].kills += 1
            if mode.isTeams { teamKills[fighters[attacker].team] += 1 }
            // 星徽「灵魂收割」：打倒一个人回血
            if fighters[attacker].starPower == .harvest, fighters[attacker].alive {
                let healed = min(power(attacker, 1500), fighters[attacker].maxHealth - fighters[attacker].health)
                if healed > 0 {
                    fighters[attacker].health += healed
                    events.append(.heal(target: attacker, amount: healed))
                }
            }
            // 悬赏：按他头上的星星给队里加分，自己的悬赏涨一颗
            if mode == .bounty, fighters[attacker].team != victim.team {
                score[fighters[attacker].team] += victim.stars
                fighters[attacker].stars = min(Self.maxBounty, fighters[attacker].stars + 1)
            }
        }
        switch mode {
        case .bounty:
            fighters[j].stars = Self.startingBounty
        default:
            // 身上的星星掉出来，散在旁边
            for _ in 0..<fighters[j].stars {
                let angle = Double(random.below(360)) * .pi / 180
                let offset = V2(cos(angle), sin(angle)) * (0.4 + Double(random.below(80)) / 100)
                stars.append(map.nearestOpen(to: fighters[j].pos + offset, radius: 0.2))
            }
            fighters[j].stars = 0
        }
        // 带着的球掉在地上
        if ball?.carrier == j {
            ball?.carrier = nil
            ball?.velocity = .zero
        }
        if mode == .duel, victim.team <= 1 { score[1 - victim.team] += 1 }
        if canRespawn(j) {
            fighters[j].respawnIn = mode.respawnDelay
        } else if mode == .showdown {
            fighters[j].place = aliveCount + 1
        } else if mode == .duo, !fighters.contains(where: { $0.team == victim.team && $0.alive }) {
            // 队友也倒下了：这一队出局，按还剩几队排名次
            let teamsLeft = Set(fighters.filter(\.alive).map(\.team)).count
            for k in fighters.indices where fighters[k].team == victim.team { fighters[k].place = teamsLeft + 1 }
        }
        events.append(.knockout(target: j, by: attacker))
    }

    // MARK: 各个玩法

    private mutating func updateStars(_ dt: Double) {
        starTimer += dt
        if starTimer >= 7 {
            starTimer -= 7
            if stars.count < 20 {
                let angle = Double(random.below(360)) * .pi / 180
                stars.append(map.nearestOpen(to: map.center + V2(cos(angle), sin(angle)) * 0.6, radius: 0.2))
            }
        }
        for i in fighters.indices where fighters[i].alive && !fighters[i].busy {
            let before = stars.count
            let position = fighters[i].pos
            stars.removeAll { $0.distance(to: position) < 0.75 }
            let picked = before - stars.count
            if picked > 0 {
                fighters[i].stars += picked
                events.append(.pickup(fighter: i))
            }
        }
        let a = teamStars(0), b = teamStars(1)
        let leader: Int? = a >= Self.goal && a > b ? 0 : (b >= Self.goal && b > a ? 1 : nil)
        if let leader {
            if var current = countdown, current.team == leader {
                current.left -= dt
                countdown = current
                if current.left <= 0 { result = .team(leader) }
            } else {
                countdown = Countdown(team: leader, left: Self.starHold)
            }
        } else {
            countdown = nil
        }
    }

    private mutating func updateZone(_ dt: Double) {
        let inside = Set(fighters.filter { $0.alive && $0.pos.distance(to: map.center) < Self.zoneRadius }.map(\.team))
        if inside.count == 1, let team = inside.first {
            zoneProgress[team] = min(100, zoneProgress[team] + dt * 100 / 50)
            if zoneProgress[team] >= 100 { result = .team(team) }
        }
    }

    /// 毒圈：大乱斗开打 15 秒后、三局两胜每局开打 40 秒后开始缩，圈外一直掉血
    private mutating func updatePoison(_ dt: Double) {
        let start = mode == .knockout ? roundStart + Self.roundPoison : 15
        let end = mode == .knockout ? start + 30 : 110
        let biggest = Double(max(map.width, map.height)) * 0.75
        let t = min(max((time - start) / (end - start), 0), 1)
        safeRadius = biggest - (biggest - 2.5) * t
        for i in fighters.indices where fighters[i].alive && fighters[i].pos.distance(to: map.center) > safeRadius {
            fighters[i].lastHurt = time
            let amount = Int((900 * dt).rounded(.up))
            hurt(i, amount, by: nil, charges: false)
        }
    }

    private mutating func decide() {
        guard result == nil else { return }
        switch mode {
        case .teamFight:
            if let team = teamKills.firstIndex(where: { $0 >= Self.goal }) { result = .team(team) }
        case .showdown:
            let alive = fighters.filter(\.alive)
            if alive.count == 1, let winner = alive.first {
                fighters[winner.id].place = 1
                result = .survivor(winner.id)
            } else if alive.isEmpty {
                result = .draw
            }
        case .duo:
            let teams = Set(fighters.filter(\.alive).map(\.team))
            if teams.count == 1, let team = teams.first {
                for k in fighters.indices where fighters[k].team == team { fighters[k].place = 1 }
                result = .team(team)
            } else if teams.isEmpty {
                result = .draw
            }
        case .ball:
            if let team = score.firstIndex(where: { $0 >= Self.ballGoals }) { result = .team(team) }
        case .heist:
            if let broken = chests.first(where: { $0.health <= 0 }) { result = .team(1 - broken.team) }
        case .knockout:
            decideRound()
        case .duel:
            // 一边的角色都倒下了、也没有下一个了
            for team in 0...1 where !fighters.contains(where: { $0.team == team && ($0.alive || canRespawn($0.id)) }) {
                result = .team(1 - team)
            }
        case .boss:
            if fighters.contains(where: { $0.isBoss && !$0.alive }) { result = .team(0) }
        case .stars, .zone, .bounty:
            break
        }
        guard result == nil, time >= mode.duration else { return }
        // 时间到了
        switch mode {
        case .teamFight: result = compare(Double(teamKills[0]), Double(teamKills[1]))
        case .stars: result = compare(Double(teamStars(0)), Double(teamStars(1)))
        case .zone: result = compare(zoneProgress[0], zoneProgress[1])
        case .ball, .bounty, .knockout: result = compare(Double(score[0]), Double(score[1]))
        case .heist: result = compare(chestShare(0), chestShare(1))
        case .duel:
            // 打倒的一样多：看场上那个血剩几成
            result = score[0] != score[1] ? compare(Double(score[0]), Double(score[1])) : compare(healthShare(0), healthShare(1))
        case .boss:
            result = .team(1)
        case .showdown:
            // 还剩几个人：血多的赢，其余按血排名
            let alive = fighters.filter(\.alive).sorted { $0.health > $1.health }
            for (rank, fighter) in alive.enumerated() { fighters[fighter.id].place = rank + 1 }
            result = alive.first.map { .survivor($0.id) } ?? .draw
        case .duo:
            // 还剩几队：按队里剩的血排名
            var totals: [Int: Int] = [:]
            for fighter in fighters where fighter.alive { totals[fighter.team, default: 0] += fighter.health }
            let ranked = totals.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            for (rank, entry) in ranked.enumerated() {
                for k in fighters.indices where fighters[k].team == entry.key { fighters[k].place = rank + 1 }
            }
            result = ranked.first.map { .team($0.key) } ?? .draw
        }
    }

    /// 自己队的宝箱还剩几成血
    func chestShare(_ team: Int) -> Double {
        guard let chest = chests.first(where: { $0.team == team }) else { return 0 }
        return Double(chest.health) / Double(max(chest.maxHealth, 1))
    }

    /// 这队场上的人还剩几成血（一对一比血用）
    func healthShare(_ team: Int) -> Double {
        fighters.filter { $0.team == team && $0.alive }.reduce(0) { $0 + Double($1.health) / Double(max($1.maxHealth, 1)) }
    }

    func compare(_ a: Double, _ b: Double) -> Result {
        a == b ? .draw : (a > b ? .team(0) : .team(1))
    }

    /// 直接改一个人（测试用：摆位置、改血）
    mutating func adjust(_ id: Int, _ change: (inout Fighter) -> Void) {
        change(&fighters[id])
    }
}
