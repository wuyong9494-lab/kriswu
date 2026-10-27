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

/// 能选的角色（都是原创的）：各有各的普通攻击和大招
public enum Brawler: Int, CaseIterable, Codable, Sendable {
    case panda, fox, tiger, frog, robot

    public var name: String { ["团团", "小狐", "虎哥", "呱呱", "铁蛋"][rawValue] }
    public var emoji: String { ["🐼", "🦊", "🐯", "🐸", "🤖"][rawValue] }
    public var role: String { ["近身霰弹", "远程狙击", "肉盾重拳", "隔墙投弹", "连发机枪"][rawValue] }
    public var attackNote: String {
        ["一次打出五颗散开的弹丸，贴脸打最疼", "一颗又快又远的子弹", "近身三连拳，血厚", "扔炸弹，能越过墙，落地炸一片", "一口气连射四发"][rawValue]
    }
    public var superNote: String {
        ["大招：往前冲撞，撞到的人都受伤", "大招：能穿透好几个人的大子弹", "大招：跳过去砸一片（能跳过墙）", "大招：超大炸弹", "大招：一大片扇形弹幕"][rawValue]
    }

    public var maxHealth: Int { [5600, 3200, 7800, 3800, 4400][rawValue] }
    /// 每秒走几格
    public var speed: Double { [2.45, 2.4, 2.55, 2.3, 2.4][rawValue] }
    /// 装一发弹要几秒（最多存 3 发）
    public var reload: Double { [1.5, 2.0, 1.2, 1.7, 1.4][rawValue] }
    public var attackRange: Double { [4.5, 9, 2.6, 7, 7][rawValue] }
    public var superRange: Double { [5.5, 11, 6, 8, 7][rawValue] }
    /// 打出多少伤害攒满一次大招
    public var superCost: Double { [7200, 3900, 8400, 4800, 6000][rawValue] }
    /// 子弹飞多快（电脑瞄准提前量用）
    public var bulletSpeed: Double { [13, 17, 14, 10, 14][rawValue] }
}

// MARK: - 地图

public struct ArenaMap: Sendable {
    public enum Tile: Sendable { case floor, wall, bush }

    public let width: Int
    public let height: Int
    public let tiles: [Tile]
    /// 出生点：分队玩法是 [下边一队, 上边一队]，各自为战是一组
    public let spawns: [[V2]]
    /// 中间：星星冒出来的地方、占点的圈
    public let center: V2

    /// 用字画地图：# 墙、* 草丛、. 空地；a 下边一队的出生点、b 上边一队的、o 各自为战的；s 中间
    public init(rows: [String]) {
        height = rows.count
        width = rows.map(\.count).max() ?? 0
        var tiles: [Tile] = []
        var a: [V2] = [], b: [V2] = [], o: [V2] = []
        var center = V2(Double(width) / 2, Double(height) / 2)
        for (y, row) in rows.enumerated() {
            let characters = Array(row)
            for x in 0..<width {
                let c = x < characters.count ? characters[x] : "."
                let spot = V2(Double(x) + 0.5, Double(y) + 0.5)
                switch c {
                case "#": tiles.append(.wall)
                case "*": tiles.append(.bush)
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
    }

    public func tile(_ x: Int, _ y: Int) -> Tile {
        guard x >= 0, y >= 0, x < width, y < height else { return .wall }
        return tiles[y * width + x]
    }

    public func tile(at p: V2) -> Tile { tile(Int(p.x.rounded(.down)), Int(p.y.rounded(.down))) }

    public func blocks(_ p: V2) -> Bool { tile(at: p) == .wall }

    public func inBush(_ p: V2) -> Bool { tile(at: p) == .bush }

    /// 一个圆（角色）有没有碰到墙或地图边
    public func collides(_ p: V2, radius: Double) -> Bool {
        let minX = Int((p.x - radius).rounded(.down)), maxX = Int((p.x + radius).rounded(.down))
        let minY = Int((p.y - radius).rounded(.down)), maxY = Int((p.y + radius).rounded(.down))
        for y in minY...maxY {
            for x in minX...maxX where tile(x, y) == .wall {
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
        guard tile(gx, gy) != .wall, tile(sx, sy) != .wall else { return [goal] }
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
                guard tile(nx, ny) != .wall else { continue }
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

    /// 分队玩法的地图（15 × 25，上下两队，中心对称）
    public static let canyon: ArenaMap = {
        let top = [
            "**....###....**",
            "*...b..b..b...*",
            "...............",
            "..###.....###..",
            "..#.........#..",
            "....**...**....",
            "....**...**....",
            ".#...........#.",
            ".#...#####...#.",
            "...............",
            "**...*...*...**",
            "**...*...*...**",
        ]
        let bottom = top.reversed().map { String($0.reversed()).replacingOccurrences(of: "b", with: "a") }
        return ArenaMap(rows: top + [".......s......."] + bottom)
    }()

    /// 各自为战的地图（19 × 19，六个出生点）
    public static let plaza: ArenaMap = {
        let top = [
            "....*.........*....",
            "....o.........o....",
            "..##....***....##..",
            "..#.............#..",
            ".......#...#.......",
            "**....##...##....**",
            "**...............**",
            "....#....*....#....",
            "...##...***...##...",
        ]
        let middle = ".o.......s.......o."
        return ArenaMap(rows: top + [middle] + top.reversed())
    }()
}

// MARK: - 一局

/// 一个人（玩家或电脑）这一局的样子
public struct Fighter: Equatable, Codable, Sendable, Identifiable {
    public struct Dash: Equatable, Codable, Sendable {
        public var direction: V2
        public var remaining: Double
        public var hit: [Int]
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
    /// 这一帧走的速度（电脑瞄准算提前量、画面上用）
    public var moving: V2 = .zero
    public var kills = 0
    public var deaths = 0
    public var damageDealt = 0
    /// 各自为战：第几名（被打倒或赢了时定下）
    public var place: Int?

    public var maxHealth: Int { brawler.maxHealth }
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

/// 摇杆的输入：走的方向（长度 0–1）、这一帧开火、放大招（相对自己的偏移，单位格：方向 + 想打多远）
public struct ArenaInput: Equatable, Codable, Sendable {
    public var move: V2
    public var attack: V2?
    public var special: V2?

    public init(move: V2 = .zero, attack: V2? = nil, special: V2? = nil) {
        self.move = move
        self.attack = attack
        self.special = special
    }
}

public struct ArenaGame: Sendable {
    public enum Mode: String, CaseIterable, Codable, Sendable {
        case teamFight, stars, showdown, zone

        public var title: String {
            switch self {
            case .teamFight: return "3v3 团战"
            case .stars: return "抢星星"
            case .showdown: return "大乱斗"
            case .zone: return "占点"
            }
        }

        public var rules: String {
            switch self {
            case .teamFight: return "两队各 3 人，先打倒对方 10 次的赢；时间到了打倒次数多的赢。被打倒 3 秒后在自己家复活。"
            case .stars: return "中间每隔几秒冒一颗星星，捡到带在身上；一队凑够 10 颗、又比对方多，守住 15 秒就赢。被打倒身上的星星全掉出来。"
            case .showdown: return "6 个人各打各的，不复活；毒圈慢慢缩小，圈外一直掉血，活到最后的赢。"
            case .zone: return "地图中间有个圈，只有一队的人站在圈里就给这队加分，两队都在就谁也不加，先满 100 的赢。"
            }
        }

        /// 一局最长几秒
        public var duration: Double {
            switch self {
            case .teamFight: return 150
            case .stars: return 180
            case .showdown: return 150
            case .zone: return 150
            }
        }

        public var isTeams: Bool { self != .showdown }
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
    }

    public struct Countdown: Equatable, Sendable {
        public var team: Int
        public var left: Double
    }

    /// 报名的人
    public struct Entrant: Equatable, Codable, Sendable {
        public var name: String
        public var brawler: Brawler
        public var isBot: Bool
        public var team: Int

        public init(name: String, brawler: Brawler, isBot: Bool, team: Int) {
            self.name = name
            self.brawler = brawler
            self.isBot = isBot
            self.team = team
        }
    }

    public static let fighterRadius = 0.42
    public static let goal = 10
    public static let starHold = 15.0
    public static let zoneRadius = 2.5
    public static let respawnDelay = 3.0

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
    public var events: [Event] = []
    private var nextProjectile = 1
    private var starTimer = 0.0
    private var random: SeededRandom

    public init(mode: Mode, entrants: [Entrant], seed: UInt64) {
        self.mode = mode
        map = mode == .showdown ? .plaza : .canyon
        random = SeededRandom(seed: seed)
        safeRadius = Double(max(map.width, map.height))
        var slots = [Int: Int]()
        var list: [Fighter] = []
        for (index, entrant) in entrants.enumerated() {
            let team = mode.isTeams ? min(max(entrant.team, 0), 1) : index
            let group = mode.isTeams ? map.spawns[team] : map.spawns[0]
            let slot = mode.isTeams ? slots[team, default: 0] : index
            slots[team, default: 0] += 1
            let spawn = group.isEmpty ? map.center : group[slot % group.count]
            let facing = (map.center - spawn).normalized
            list.append(Fighter(id: index, name: entrant.name, team: team, brawler: entrant.brawler, isBot: entrant.isBot,
                                pos: spawn, facing: facing, health: entrant.brawler.maxHealth))
        }
        fighters = list
    }

    public var timeLeft: Double { max(0, mode.duration - time) }

    /// 一队身上带着几颗星星
    public func teamStars(_ team: Int) -> Int {
        fighters.filter { $0.team == team }.reduce(0) { $0 + $1.stars }
    }

    public var aliveCount: Int { fighters.filter(\.alive).count }

    /// 这个人现在看不看得见：在草丛里的，敌人走近（2.5 格内）或者他刚开过火才看得见
    public func isVisible(_ fighter: Fighter, to team: Int) -> Bool {
        guard fighter.alive else { return false }
        if fighter.team == team || !map.inBush(fighter.pos) || time - fighter.lastAttack < 1 { return true }
        return fighters.contains { $0.alive && $0.team == team && $0.pos.distance(to: fighter.pos) < 2.5 }
    }

    // MARK: 一帧

    public mutating func step(_ dt: Double, inputs: [Int: ArenaInput]) {
        guard result == nil else { return }
        time += dt
        for i in fighters.indices {
            update(i, inputs[i] ?? ArenaInput(), dt)
        }
        moveProjectiles(dt)
        switch mode {
        case .stars: updateStars(dt)
        case .zone: updateZone(dt)
        case .showdown: updatePoison(dt)
        case .teamFight: break
        }
        decide()
    }

    private mutating func update(_ i: Int, _ input: ArenaInput, _ dt: Double) {
        if !fighters[i].alive {
            guard mode.isTeams else { return }
            fighters[i].respawnIn -= dt
            if fighters[i].respawnIn <= 0 { respawn(i) }
            return
        }
        fighters[i].cooldown -= dt
        fighters[i].ammo = min(3, fighters[i].ammo + dt / fighters[i].brawler.reload)
        if fighters[i].leap != nil {
            updateLeap(i, dt)
            return
        }
        if fighters[i].dash != nil {
            updateDash(i, dt)
            return
        }
        let move = input.move.clamped(to: 1)
        fighters[i].moving = move * fighters[i].brawler.speed
        if move.length > 0.05 {
            walk(i, by: move * (fighters[i].brawler.speed * dt))
            if input.attack == nil && input.special == nil { fighters[i].facing = move.normalized }
        }
        if var burst = fighters[i].burst {
            burst.timer -= dt
            while burst.timer <= 0 && burst.left > 0 {
                shoot(i, burst.direction.rotated(by: (random.chance(0.5) ? 1 : -1) * 0.03), speed: 14, range: 7, damage: 380, radius: 0.2)
                burst.left -= 1
                burst.timer += 0.08
            }
            fighters[i].burst = burst.left > 0 ? burst : nil
        }
        if let aim = input.attack, fighters[i].ammo >= 1, fighters[i].cooldown <= 0 {
            attack(i, aim)
        }
        if let aim = input.special, fighters[i].superCharge >= 1, fighters[i].alive {
            special(i, aim)
        }
        if fighters[i].alive, time - max(fighters[i].lastHurt, fighters[i].lastAttack) > 3 {
            let gain = Int((Double(fighters[i].maxHealth) * 0.13 * dt).rounded(.up))
            fighters[i].health = min(fighters[i].maxHealth, fighters[i].health + gain)
        }
    }

    /// 走：先整个走，碰墙了就只走横的或只走竖的（贴着墙滑）
    private mutating func walk(_ i: Int, by delta: V2) {
        fighters[i].pos = Self.walk(from: fighters[i].pos, by: delta, on: map)
    }

    private mutating func respawn(_ i: Int) {
        let group = map.spawns[mode.isTeams ? fighters[i].team : 0]
        let spawn = group.isEmpty ? map.center : group[i % group.count]
        fighters[i].pos = spawn
        fighters[i].facing = (map.center - spawn).normalized
        fighters[i].health = fighters[i].maxHealth
        fighters[i].ammo = 3
        fighters[i].alive = true
        fighters[i].lastHurt = time
        fighters[i].moving = .zero
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
        switch fighter.brawler {
        case .panda:
            spread(i, direction, count: 5, angle: 0.52, speed: 13, range: 4.5, damage: 360, radius: 0.2)
        case .fox:
            shoot(i, direction, speed: 17, range: 9, damage: 1300, radius: 0.22)
        case .tiger:
            spread(i, direction, count: 3, angle: 0.9, speed: 14, range: 2.6, damage: 700, radius: 0.3)
        case .frog:
            lob(i, to: fighter.pos + direction * min(max(aim.length, 1.5), fighter.brawler.attackRange),
                duration: 0.7, blast: 1.2, damage: 1200, isSuper: false)
        case .robot:
            fighters[i].burst = Fighter.Burst(left: 4, timer: 0, direction: direction)
        }
    }

    private mutating func special(_ i: Int, _ aim: V2) {
        let fighter = fighters[i]
        let direction = aim.length > 0.01 ? aim.normalized : fighter.facing
        fighters[i].superCharge = 0
        fighters[i].lastAttack = time
        fighters[i].facing = direction
        events.append(.special(fighter: i))
        switch fighter.brawler {
        case .panda:
            fighters[i].dash = Fighter.Dash(direction: direction, remaining: fighter.brawler.superRange, hit: [])
        case .fox:
            shoot(i, direction, speed: 18, range: fighter.brawler.superRange, damage: 2400, radius: 0.35, pierce: true, isSuper: true)
        case .tiger:
            let target = map.nearestOpen(to: fighter.pos + direction * min(max(aim.length, 2), fighter.brawler.superRange))
            fighters[i].leap = Fighter.Leap(from: fighter.pos, to: target, elapsed: 0)
        case .frog:
            lob(i, to: fighter.pos + direction * min(max(aim.length, 2), fighter.brawler.superRange),
                duration: 0.9, blast: 2.2, damage: 2600, isSuper: true)
        case .robot:
            spread(i, direction, count: 12, angle: 1.05, speed: 14, range: 7, damage: 500, radius: 0.2, isSuper: true)
        }
    }

    private mutating func shoot(_ i: Int, _ direction: V2, speed: Double, range: Double, damage: Int, radius: Double,
                                pierce: Bool = false, isSuper: Bool = false) {
        let fighter = fighters[i]
        projectiles.append(Projectile(id: nextProjectile, owner: i, team: fighter.team, pos: fighter.pos + direction * 0.3,
                                      velocity: direction * speed, rangeLeft: range, damage: damage, radius: radius,
                                      pierce: pierce, charges: !isSuper, isSuper: isSuper))
        nextProjectile += 1
    }

    private mutating func spread(_ i: Int, _ direction: V2, count: Int, angle: Double, speed: Double, range: Double,
                                 damage: Int, radius: Double, isSuper: Bool = false) {
        for k in 0..<count {
            let offset = count == 1 ? 0 : angle * (Double(k) / Double(count - 1) - 0.5)
            shoot(i, direction.rotated(by: offset), speed: speed, range: range, damage: damage, radius: radius, isSuper: isSuper)
        }
    }

    private mutating func lob(_ i: Int, to target: V2, duration: Double, blast: Double, damage: Int, isSuper: Bool) {
        let fighter = fighters[i]
        projectiles.append(Projectile(id: nextProjectile, owner: i, team: fighter.team, pos: fighter.pos, velocity: .zero,
                                      rangeLeft: .infinity, damage: damage, radius: 0.3, charges: !isSuper, isSuper: isSuper,
                                      lob: Projectile.Lob(from: fighter.pos, to: target, duration: duration, elapsed: 0, blast: blast)))
        nextProjectile += 1
    }

    private mutating func updateDash(_ i: Int, _ dt: Double) {
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
        for j in fighters.indices where fighters[j].alive && fighters[j].team != fighters[i].team && !dash.hit.contains(j)
            && fighters[j].pos.distance(to: next) < Self.fighterRadius * 2.2 {
            dash.hit.append(j)
            hurt(j, 1600, by: i, charges: false)
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
            blast(at: leap.to, radius: 1.6, damage: 1800, by: i, team: fighters[i].team, charges: false)
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
            if p.rangeLeft <= 0 || map.blocks(p.pos) { continue }
            var consumed = false
            for j in fighters.indices where fighters[j].alive && fighters[j].team != p.team && fighters[j].leap == nil && !p.hit.contains(j) {
                guard fighters[j].pos.distance(to: p.pos) < Self.fighterRadius + p.radius else { continue }
                hurt(j, p.damage, by: p.owner, charges: p.charges)
                if p.pierce {
                    p.hit.append(j)
                } else {
                    consumed = true
                    break
                }
            }
            if !consumed { kept.append(p) }
        }
        projectiles = kept
    }

    private mutating func blast(at point: V2, radius: Double, damage: Int, by owner: Int, team: Int, charges: Bool) {
        events.append(.explosion(at: point, radius: radius))
        for j in fighters.indices where fighters[j].alive && fighters[j].team != team && fighters[j].pos.distance(to: point) < radius + Self.fighterRadius {
            hurt(j, damage, by: owner, charges: charges)
        }
    }

    private mutating func hurt(_ j: Int, _ amount: Int, by attacker: Int?, charges: Bool) {
        guard fighters[j].alive, amount > 0 else { return }
        let dealt = min(amount, fighters[j].health)
        fighters[j].health -= amount
        fighters[j].lastHurt = time
        events.append(.hit(target: j, amount: amount))
        if let attacker, fighters.indices.contains(attacker) {
            fighters[attacker].damageDealt += dealt
            if charges {
                fighters[attacker].superCharge = min(1, fighters[attacker].superCharge + Double(amount) / fighters[attacker].brawler.superCost)
            }
        }
        if fighters[j].health <= 0 { knockOut(j, by: attacker) }
    }

    private mutating func knockOut(_ j: Int, by attacker: Int?) {
        fighters[j].alive = false
        fighters[j].health = 0
        fighters[j].deaths += 1
        fighters[j].dash = nil
        fighters[j].leap = nil
        fighters[j].burst = nil
        fighters[j].moving = .zero
        if let attacker, attacker != j {
            fighters[attacker].kills += 1
            if mode.isTeams { teamKills[fighters[attacker].team] += 1 }
        }
        // 身上的星星掉出来，散在旁边
        for _ in 0..<fighters[j].stars {
            let angle = Double(random.below(360)) * .pi / 180
            let offset = V2(cos(angle), sin(angle)) * (0.4 + Double(random.below(80)) / 100)
            stars.append(map.nearestOpen(to: fighters[j].pos + offset, radius: 0.2))
        }
        fighters[j].stars = 0
        if mode.isTeams {
            fighters[j].respawnIn = Self.respawnDelay
        } else {
            fighters[j].place = aliveCount + 1
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

    private mutating func updatePoison(_ dt: Double) {
        let start = 15.0, end = 110.0
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
        case .stars, .zone:
            break
        }
        guard result == nil, time >= mode.duration else { return }
        // 时间到了
        switch mode {
        case .teamFight: result = compare(Double(teamKills[0]), Double(teamKills[1]))
        case .stars: result = compare(Double(teamStars(0)), Double(teamStars(1)))
        case .zone: result = compare(zoneProgress[0], zoneProgress[1])
        case .showdown:
            // 还剩几个人：血多的赢，其余按血排名
            let alive = fighters.filter(\.alive).sorted { $0.health > $1.health }
            for (rank, fighter) in alive.enumerated() { fighters[fighter.id].place = rank + 1 }
            result = alive.first.map { .survivor($0.id) } ?? .draw
        }
    }

    private func compare(_ a: Double, _ b: Double) -> Result {
        a == b ? .draw : (a > b ? .team(0) : .team(1))
    }

    /// 直接改一个人（测试用：摆位置、改血）
    mutating func adjust(_ id: Int, _ change: (inout Fighter) -> Void) {
        change(&fighters[id])
    }
}
