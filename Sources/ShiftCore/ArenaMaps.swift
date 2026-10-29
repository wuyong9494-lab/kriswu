import Foundation

// 乱斗的地图：每种玩法几张，开局随机挑一张（联机时房主挑好发给大家）

extension ArenaMap {
    /// 两队对打的地图（团战、抢星星这些是 15 × 25）：只画上边一半，下边一半中心对称（上边一队的 b 换成下边一队的 a）
    private static func teams(_ id: String, _ title: String, _ theme: Theme, _ top: [String], middle: String) -> ArenaMap {
        let bottom = top.reversed().map { String($0.reversed()).replacingOccurrences(of: "b", with: "a") }
        return ArenaMap(id: id, title: title, theme: theme, rows: top + [middle] + bottom)
    }

    /// 各自为战的地图都是 19 × 19、六个出生点：只画上边一半，下边一半上下对称
    private static func solo(_ id: String, _ title: String, _ theme: Theme, _ top: [String], middle: String) -> ArenaMap {
        ArenaMap(id: id, title: title, theme: theme, rows: top + [middle] + top.reversed())
    }

    public static let canyon = teams("canyon", "峡谷", .sand, [
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
    ], middle: ".......s.......")

    /// 中间一个十字口，两边草丛绕过去
    public static let crossroads = teams("crossroads", "十字路口", .dusk, [
        "...**.....**...",
        "..b....b....b..",
        "...............",
        "###...***...###",
        "..#.........#..",
        "..#..#...#..#..",
        "**...#...#...**",
        "**...........**",
        "....##...##....",
        "...............",
        "..*...###...*..",
        ".***.......***.",
    ], middle: "**.....s.....**")

    /// 两队家门口各有一道墙，中间空旷
    public static let fortress = teams("fortress", "双城堡", .stone, [
        "...............",
        ".#..b..b..b..#.",
        ".#...........#.",
        ".####.....####.",
        "......***......",
        "..*...***...*..",
        ".***.......***.",
        "..*..#...#..*..",
        ".....#...#.....",
        "##...........##",
        "....**...**....",
        "....**...**....",
    ], middle: ".......s.......")

    /// 墙少、草丛多，适合埋伏
    public static let garden = teams("garden", "花园", .meadow, [
        "**.....*.....**",
        "*..b...b...b..*",
        "...............",
        ".***..***..***.",
        ".***.......***.",
        "......#.#......",
        "..**..#.#..**..",
        "..**.......**..",
        "#.....***.....#",
        "#.....***.....#",
        "...*.......*...",
        "..***..#..***..",
    ], middle: ".......s.......")

    public static let plaza = solo("plaza", "广场", .sand, [
        "....*.........*....",
        "....o.........o....",
        "..##....***....##..",
        "..#.............#..",
        ".......#...#.......",
        "**....##...##....**",
        "**...............**",
        "....#....*....#....",
        "...##...***...##...",
    ], middle: ".o.......s.......o.")

    /// 东一块西一块的断墙
    public static let ruins = solo("ruins", "废墟", .stone, [
        "........***........",
        "....o.........o....",
        "..#.............#..",
        ".##..**.....**..##.",
        "......#.....#......",
        "..**.....#.....**..",
        "..**....###....**..",
        "......#.....#......",
        "...#...........#...",
    ], middle: ".o.*.....s.....*.o.")

    /// 到处是草丛
    public static let grove = solo("grove", "树林", .meadow, [
        "***.............***",
        "*...o.........o...*",
        "....***.....***....",
        "..#.***.....***.#..",
        "..#.............#..",
        "......**...**......",
        ".**...**.#.**...**.",
        ".**......#......**.",
        ".....#.......#.....",
    ], middle: ".o.......s.......o.")

    // MARK: 足球

    /// 足球的场地：两头各一个 5 格宽的球门（G），中间开球
    public static let pitch = teams("pitch", "绿茵场", .meadow, [
        "#####GGGGG#####",
        "...............",
        "...............",
        "..b....b....b..",
        "...............",
        "##...#...#...##",
        "**...........**",
        "**...##.##...**",
        ".......*.......",
        "...*.......*...",
        "..***.....***..",
        "...............",
    ], middle: ".......s.......")

    /// 中间两道墙把球场分成左右两条路
    public static let sandPitch = teams("sandPitch", "沙地球场", .sand, [
        "#####GGGGG#####",
        "...............",
        "..b....b....b..",
        "...............",
        ".###.......###.",
        "...............",
        "......***......",
        "*....*****....*",
        "**...........**",
        "...#.......#...",
        "...#...#...#...",
        ".......#.......",
    ], middle: "**.....s.....**")

    // MARK: 宝箱攻防

    /// 两队家里各有一个宝箱（C，3 × 2 格），出生在宝箱前面
    public static let vault = teams("vault", "金库", .stone, [
        "...............",
        "......###......",
        "..#...CCC...#..",
        "..#...CCC...#..",
        "..#.........#..",
        "...............",
        "...b...b...b...",
        "**...........**",
        "**...##.##...**",
        ".......*.......",
        "...*.......*...",
        "..***.....***..",
    ], middle: ".......s.......")

    /// 宝箱前面空旷，两边草丛绕过去
    public static let cove = teams("cove", "宝藏湾", .sand, [
        "**...........**",
        "*.....###.....*",
        "......CCC......",
        "......CCC......",
        "...#.......#...",
        "...#.......#...",
        "...b...b...b...",
        "...............",
        "###...***...###",
        "......***......",
        "..*.........*..",
        ".***..#.#..***.",
    ], middle: ".......s.......")

    // MARK: 一对一

    /// 一对一的小场地（15 × 17），一边一个出生点
    public static let ring = teams("ring", "擂台", .dusk, [
        "**...........**",
        "*......b......*",
        "...............",
        "...##.....##...",
        "...#.......#...",
        ".......*.......",
        "..**..***..**..",
        "...............",
    ], middle: ".......s.......")

    public static let glade = teams("glade", "林间空地", .meadow, [
        "...............",
        ".......b.......",
        "..*.........*..",
        ".***..#.#..***.",
        "...............",
        "#.....***.....#",
        "##.....*.....##",
        "....#.....#....",
    ], middle: ".......s.......")

    // MARK: 讨伐骷髅王

    /// 骷髅王在上边（b），三个勇者从下边（a）出发；19 × 19，上下左右都对称
    public static let lair = ArenaMap(id: "lair", title: "骷髅王的墓地", theme: .stone, rows: [
        "*.................*",
        "**...#.......#...**",
        ".........b.........",
        "...#...........#...",
        "...................",
        "..*....#...#....*..",
        ".***...........***.",
        "..*.............*..",
        ".....#.......#.....",
        ".........s.........",
        ".....#.......#.....",
        "..*.............*..",
        ".***...........***.",
        "..*....#...#....*..",
        "...................",
        "...#...........#...",
        "......a..a..a......",
        "**...#.......#...**",
        "*.................*",
    ])

    /// 这个玩法能用的地图（第一张是老版本一直用的那张）
    public static func pool(for mode: ArenaGame.Mode) -> [ArenaMap] {
        switch mode {
        case .ball: return [pitch, sandPitch]
        case .heist: return [vault, cove]
        case .duel: return [ring, glade]
        case .boss: return [lair]
        case .showdown, .duo: return [plaza, ruins, grove]
        case .teamFight, .stars, .bounty, .zone, .knockout: return [canyon, crossroads, fortress, garden]
        }
    }

    /// 所有的地图
    public static let all: [ArenaMap] = [canyon, crossroads, fortress, garden, plaza, ruins, grove, pitch, sandPitch, vault, cove,
                                         ring, glade, lair]

    /// New match arenas have flanking lanes and cover, with distinct wire IDs.
    /// Keep historical IDs intact for story missions, replays and older peers.
    public static let expandedMaps: [ArenaMap] = [canyon, crossroads, fortress, garden, plaza, ruins, grove].map(expanded)

    private static func expanded(_ source: ArenaMap) -> ArenaMap {
        let insetX = 3, insetY = source.width == source.height ? 3 : 2
        let width = source.width + insetX * 2, height = source.height + insetY * 2
        var rows = Array(repeating: Array(repeating: Character("."), count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                let edgeX = min(x, width - 1 - x), edgeY = min(y, height - 1 - y)
                if edgeX < 2 && edgeY > 2 && edgeY % 6 < 4 { rows[y][x] = "*" }
            }
        }
        for y in 0..<source.height {
            for x in 0..<source.width {
                let tile = source.tile(x, y)
                rows[y + insetY][x + insetX] = tile == .wall ? "#" : tile == .bush ? "*" : "."
            }
        }
        // Widen existing cover into adjacent floor cells symmetrically. Leave
        // the middle crossing open; bushes remain traversable in every mode.
        for y in 1..<(source.height - 1) {
            for x in 1..<(source.width - 1) where source.tile(x, y) == .bush {
                for dx in [-1, 1] where source.tile(x + dx, y) == .floor {
                    if abs(Double(y) + 0.5 - source.center.y) > 1 {
                        rows[y + insetY][x + dx + insetX] = "*"
                    }
                }
            }
        }
        // Split the added side lanes into cover and open crossings. Mirrored
        // two-cell walls leave a continuous route along x=2 and x=width-3.
        for y in stride(from: 5, to: height / 2 - 2, by: 6) {
            for x in 0..<2 {
                rows[y][x] = "#"
                rows[height - 1 - y][width - 1 - x] = "#"
            }
            for dy in 1...2 {
                rows[y + dy][1] = "*"
                rows[height - 1 - y - dy][width - 2] = "*"
            }
        }
        for (team, spawns) in source.spawns.enumerated() {
            for spawn in spawns {
                rows[Int(spawn.y) + insetY][Int(spawn.x) + insetX] = source.spawns.count == 1 ? "o" : team == 0 ? "a" : "b"
            }
        }
        rows[Int(source.center.y) + insetY][Int(source.center.x) + insetX] = "s"
        return ArenaMap(id: source.id + "_expanded_v2", title: source.title + " · 扩展", theme: source.theme,
                        rows: rows.map { String($0) })
    }

    public static func playPool(for mode: ArenaGame.Mode) -> [ArenaMap] {
        let ids = Set(pool(for: mode).map { $0.id + "_expanded_v2" })
        let expanded = expandedMaps.filter { ids.contains($0.id) }
        return expanded.isEmpty ? pool(for: mode) : expanded
    }

    /// 按名字找（联机开局时房主发来的）
    public static func named(_ id: String) -> ArenaMap? {
        all.first { $0.id == id } ?? expandedMaps.first { $0.id == id }
    }
}

