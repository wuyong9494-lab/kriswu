import Foundation

/// 小游戏「叠叠消」：一堆叠着的牌，点没被压住的牌放进下面的槽；槽里凑齐三张一样的就消掉，
/// 槽里放满七张还没凑齐就输了，牌全消完就赢了。
/// 同一档难度、同一个种子摆出来的牌一模一样（几个人玩同一局比快慢）；
/// 摆牌时先定好一种消法、再按它放牌，所以每一局都消得完
public struct TileGame: Equatable, Sendable {
    public enum Level: Int, Codable, CaseIterable, Sendable {
        case easy = 1, normal, hard

        public var title: String {
            switch self {
            case .easy: return "简单"
            case .normal: return "普通"
            case .hard: return "困难"
            }
        }
    }

    public enum Status: String, Codable, Sendable {
        case playing, won, lost
    }

    /// 一张牌。位置以 1/4 张牌为一格（一张牌占 4×4 格：上下层错开半张是 2 格，底下两摞一张错开 1 格），
    /// x 往右、y 往下；z 大的压在上面
    public struct Tile: Equatable, Hashable, Identifiable, Sendable {
        public var id: Int
        public var kind: Int
        public var x: Int
        public var y: Int
        public var z: Int

        public init(id: Int, kind: Int, x: Int, y: Int, z: Int) {
            self.id = id
            self.kind = kind
            self.x = x
            self.y = y
            self.z = z
        }

        /// 两张牌叠在一起（只碰到边不算）
        public func overlaps(_ other: Tile) -> Bool {
            abs(x - other.x) < TileGame.size && abs(y - other.y) < TileGame.size
        }
    }

    /// 一张牌占几格
    public static let size = 4
    /// 槽有几格
    public static let capacity = 7
    /// 牌堆多宽（格）：一排最多 7 张
    public static let width = 28

    public let level: Level
    public let seed: UInt64
    /// 一共几张
    public let total: Int
    /// 牌堆多高（格，含底下两摞）
    public let height: Int
    /// 还在牌堆里的
    public private(set) var board: [Tile]
    /// 槽里的，一样的挨在一起
    public private(set) var tray: [Tile] = []
    /// 「移出」挪出槽的几张：放在槽上面，点一张放回槽里
    public private(set) var parked: [Tile] = []
    /// 槽里刚凑齐、马上消掉的三张（界面上停一下让人看见，再 settle）
    public private(set) var clearing: Set<Int> = []
    public private(set) var cleared = 0
    public private(set) var status = Status.playing
    /// 三种道具各还能用几次
    public private(set) var undos = 1
    public private(set) var moveOuts = 1
    public private(set) var shuffles = 1
    /// 上一张放进槽的牌、它从哪来（撤回用；凑齐消掉了就不能撤回）
    private var last: Move?
    /// 摆牌时定好的那种消法（依次拿哪几张，测试里照着拿一遍看消不消得完）
    let solution: [Int]

    private struct Move: Equatable, Sendable {
        var tile: Tile
        var fromParked: Bool
    }

    // MARK: - 摆牌

    /// 每档难度：几种牌、几层、底下两摞各几张、最多几张，
    /// 定好的那种消法槽里最多同时放几张（limit）、多常开一种新牌（越常开，几种牌搅得越乱）
    struct Spec {
        var kinds: Int
        var layers: Int
        var columns: Int
        var rows: Int
        var stack: Int
        var most: Int
        var limit: Int
        var openChance: Double

        init(_ level: Level) {
            switch level {
            case .easy: self = Spec(kinds: 4, layers: 3, columns: 5, rows: 6, stack: 0, most: 36, limit: 3, openChance: 0.3)
            case .normal: self = Spec(kinds: 8, layers: 5, columns: 7, rows: 8, stack: 6, most: 111, limit: 4, openChance: 0.4)
            case .hard: self = Spec(kinds: 9, layers: 7, columns: 7, rows: 8, stack: 10, most: 150, limit: 5, openChance: 0.5)
            }
        }

        init(kinds: Int, layers: Int, columns: Int, rows: Int, stack: Int, most: Int, limit: Int, openChance: Double) {
            self.kinds = kinds
            self.layers = layers
            self.columns = columns
            self.rows = rows
            self.stack = stack
            self.most = most
            self.limit = limit
            self.openChance = openChance
        }
    }

    public init(level: Level, seed: UInt64) {
        let spec = Spec(level)
        var random = SeededRandom(seed: seed &* 0x2545_F491_4F6C_DD1D &+ UInt64(level.rawValue))
        var spots = Self.layout(spec, using: &random)
        // 张数凑成 3 的倍数，也不超过最多几张：从最上面拿掉几张
        while spots.count > spec.most || spots.count % 3 != 0 {
            let top = spots.map(\.z).max()!
            let candidates = spots.indices.filter { spots[$0].z == top }
            spots.remove(at: candidates[random.below(candidates.count)])
        }
        let order = Self.removalOrder(spots, using: &random)
        let kinds = Self.kindSequence(count: spots.count, spec: spec, using: &random)
        var tiles = spots
        for (step, index) in order.enumerated() { tiles[index].kind = kinds[step] }
        self.init(level: level, seed: seed, tiles: tiles, solution: order.map { tiles[$0].id })
    }

    /// 直接给定牌堆（测试用）
    init(level: Level, seed: UInt64, tiles: [Tile], solution: [Int] = []) {
        self.level = level
        self.seed = seed
        self.solution = solution
        board = tiles
        total = tiles.count
        height = (tiles.map(\.y).max() ?? 0) + Self.size
    }

    /// 牌堆一层层摆：偶数层对齐、奇数层错开半张；每层是左右对称的一块（满的、隔一个空一个、一圈、菱形、挖几个洞），
    /// 越往上越小。有底下两摞的话，在牌堆下面左右各一摞，一张压一张往里错开一点，只有最上面那张能拿
    static func layout(_ spec: Spec, using random: inout SeededRandom) -> [Tile] {
        var tiles: [Tile] = []
        let middleX = width / 2, middleY = spec.rows * size / 2
        for z in 0..<spec.layers {
            let odd = z % 2 == 1
            // 宽和高跟层的奇偶搭配好，才能左右对称、和下一层错开半张
            let shrink = 2 * (z / 3)
            var w = (odd ? spec.columns - 1 : spec.columns) - shrink - 2 * random.below(2)
            var h = (odd ? spec.rows - 1 : spec.rows) - shrink - 2 * random.below(2)
            w = max(w, odd ? 2 : 3)
            h = max(h, odd ? 3 : 2)
            let pattern = random.below(5)
            let radius = Double(min(w, h)) / 2 + Double(random.below(2))
            /// 洞：按离左右边多远定，左右自然对称
            var holes: Set<[Int]> = []
            for r in 0..<h {
                for m in 0..<((w + 1) / 2) where !random.chance(0.75) { holes.insert([r, m]) }
            }
            var cells: [(Int, Int)] = []
            for r in 0..<h {
                for c in 0..<w {
                    let m = min(c, w - 1 - c)
                    let keep: Bool
                    switch pattern {
                    case 0: keep = true
                    case 1: keep = (r + m) % 2 == 0
                    case 2: keep = r == 0 || r == h - 1 || m == 0
                    case 3: keep = abs(Double(r) - Double(h - 1) / 2) + abs(Double(c) - Double(w - 1) / 2) <= radius
                    default: keep = !holes.contains([r, m])
                    }
                    if keep { cells.append((r, c)) }
                }
            }
            // 太空了就整块铺满
            if cells.count < max(4, w * h / 3) {
                cells = (0..<h).flatMap { r in (0..<w).map { (r, $0) } }
            }
            for (r, c) in cells {
                tiles.append(Tile(id: tiles.count, kind: 0, x: middleX - 2 * w + size * c,
                                  y: middleY - 2 * h + size * r, z: z))
            }
        }
        if spec.stack > 0 {
            let y = spec.rows * size + 2
            for i in 0..<spec.stack {
                tiles.append(Tile(id: tiles.count, kind: 0, x: i, y: y, z: i))
                tiles.append(Tile(id: tiles.count, kind: 0, x: width - size - i, y: y, z: i))
            }
        }
        return tiles
    }

    /// 定好的那种消法：每一步拿一张没被压住的（随便挑一张），一直拿完
    static func removalOrder(_ tiles: [Tile], using random: inout SeededRandom) -> [Int] {
        var above = [Int](repeating: 0, count: tiles.count)
        var covers = [[Int]](repeating: [], count: tiles.count)
        for i in tiles.indices {
            for j in tiles.indices where tiles[i].z > tiles[j].z && tiles[i].overlaps(tiles[j]) {
                covers[i].append(j)
                above[j] += 1
            }
        }
        var free = tiles.indices.filter { above[$0] == 0 }
        var order: [Int] = []
        while !free.isEmpty {
            let i = free.remove(at: random.below(free.count))
            order.append(i)
            for j in covers[i] {
                above[j] -= 1
                if above[j] == 0 { free.append(j) }
            }
        }
        return order
    }

    /// 按定好的消法依次拿牌时每张是哪种：槽里同时最多放 limit 张（凑齐三张的那一下不算），最后正好全凑齐。
    /// 开一种新牌要留一格余地（不然槽里全是各差两张的，下一步怎么拿都超）；新牌挑到现在为止用得最少的几种，各种牌差不多一样多
    static func kindSequence(count: Int, spec: Spec, using random: inout SeededRandom) -> [Int] {
        var sequence: [Int] = []
        var waiting: [Int: Int] = [:]
        var uses = [Int](repeating: 0, count: spec.kinds)
        for step in 0..<count {
            let remaining = count - step
            let needed = waiting.values.reduce(0) { $0 + 3 - $1 }
            let inTray = waiting.values.reduce(0, +)
            let canOpen = remaining >= needed + 3 && inTray + 1 <= spec.limit - 1 && waiting.count < spec.kinds
            // 接着凑的：差一张就齐的随时能放；只放了一张的，放进去槽里不超过 limit 才行
            let progress = waiting.keys.sorted().filter { waiting[$0] == 2 || inTray + 1 <= spec.limit }
            let kind: Int
            if canOpen && (progress.isEmpty || random.chance(spec.openChance)) {
                let fresh = (0..<spec.kinds).filter { waiting[$0] == nil }
                let fewest = fresh.map { uses[$0] }.min()!
                let pool = fresh.filter { uses[$0] == fewest }
                kind = pool[random.below(pool.count)]
            } else {
                kind = progress[random.below(progress.count)]
            }
            uses[kind] += 1
            let now = (waiting[kind] ?? 0) + 1
            waiting[kind] = now == 3 ? nil : now
            sequence.append(kind)
        }
        return sequence
    }

    // MARK: - 玩

    /// 这张牌上面没有压着别的（能拿）
    public func isFree(_ tile: Tile) -> Bool {
        !board.contains { $0.z > tile.z && $0.overlaps(tile) }
    }

    /// 牌堆里能拿的那些
    public var freeIDs: Set<Int> {
        Set(board.filter(isFree).map(\.id))
    }

    /// 槽里等着凑的几张（不算正要消掉的）
    public var waiting: Int { tray.count - clearing.count }

    /// 拿一张（牌堆里没被压住的，或移出去的那几张）放进槽：放在一样的旁边，凑齐三张就消掉
    @discardableResult
    public mutating func pick(_ id: Int) -> Bool {
        settle()
        guard status == .playing else { return false }
        let tile: Tile
        let fromParked: Bool
        if let i = board.firstIndex(where: { $0.id == id }) {
            guard isFree(board[i]) else { return false }
            tile = board.remove(at: i)
            fromParked = false
        } else if let i = parked.firstIndex(where: { $0.id == id }) {
            tile = parked.remove(at: i)
            fromParked = true
        } else {
            return false
        }
        let at = tray.lastIndex { $0.kind == tile.kind }.map { $0 + 1 } ?? tray.count
        tray.insert(tile, at: at)
        last = Move(tile: tile, fromParked: fromParked)
        let same = tray.filter { $0.kind == tile.kind }
        if same.count >= 3 {
            clearing = Set(same.prefix(3).map(\.id))
            last = nil
        }
        updateStatus()
        return true
    }

    /// 消掉槽里凑齐的三张
    public mutating func settle() {
        guard !clearing.isEmpty else { return }
        tray.removeAll { clearing.contains($0.id) }
        cleared += clearing.count
        clearing = []
        updateStatus()
    }

    /// 撤回：上一张放进槽的放回原处（输了也能用，用完接着玩）
    @discardableResult
    public mutating func undo() -> Bool {
        settle()
        guard undos > 0, status != .won, let move = last, let i = tray.firstIndex(where: { $0.id == move.tile.id }) else {
            return false
        }
        tray.remove(at: i)
        if move.fromParked { parked.append(move.tile) } else { board.append(move.tile) }
        undos -= 1
        last = nil
        updateStatus()
        return true
    }

    /// 移出：槽里最左边三张挪到槽上面放着（输了也能用，用完接着玩）
    @discardableResult
    public mutating func moveOut() -> Bool {
        settle()
        guard moveOuts > 0, status != .won, !tray.isEmpty else { return false }
        let n = min(3, tray.count)
        parked += tray.prefix(n)
        tray.removeFirst(n)
        moveOuts -= 1
        last = nil
        updateStatus()
        return true
    }

    /// 洗牌：牌堆里的牌换换位置（每张的位置不动，种类打乱）
    @discardableResult
    public mutating func shuffle() -> Bool {
        settle()
        guard shuffles > 0, status == .playing, board.count > 1 else { return false }
        var kinds = board.map(\.kind)
        var random = SeededRandom(seed: seed ^ UInt64(board.count) &* 0x9E37_79B9_7F4A_7C15)
        random.shuffle(&kinds)
        for i in board.indices { board[i].kind = kinds[i] }
        shuffles -= 1
        last = nil
        return true
    }

    private mutating func updateStatus() {
        if board.isEmpty && parked.isEmpty && waiting == 0 {
            status = .won
        } else if waiting >= Self.capacity {
            status = .lost
        } else {
            status = .playing
        }
    }

    // MARK: - 挑战码、今日挑战

    /// 挑战码用的字：去掉 0、1、I、O（容易看错）
    static let codeAlphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
    /// 种子的范围（挑战码装得下的）
    public static let seedLimit: UInt64 = 1 << 28

    /// 挑战码：难度和种子编成 6 个字，发给别人输进来玩同一局
    public static func code(level: Level, seed: UInt64) -> String {
        var value = UInt64(level.rawValue - 1) << 28 | seed % seedLimit
        var characters: [Character] = []
        for _ in 0..<6 {
            characters.append(codeAlphabet[Int(value & 31)])
            value >>= 5
        }
        return String(characters.reversed())
    }

    public var code: String { Self.code(level: level, seed: seed) }

    /// 从挑战码（或贴进来的一整段话，比如别人发的「挑战码 K7Q2MX」）里读出难度和种子
    public static func decode(_ text: String) -> (level: Level, seed: UInt64)? {
        let upper = text.uppercased()
        let searchFrom = upper.range(of: "挑战码").map { String(upper[$0.upperBound...]) } ?? upper
        for source in [searchFrom, upper] {
            for match in candidates(in: source) {
                if let decoded = decodeExact(match) { return decoded }
            }
        }
        return nil
    }

    /// 一段字里前后不挨着别的字母数字、正好 6 个挑战码用字的那几段
    private static func candidates(in text: String) -> [String] {
        var result: [String] = []
        var run = ""
        for ch in text + " " {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                run.append(ch)
            } else {
                if run.count == 6 { result.append(run) }
                run = ""
            }
        }
        return result
    }

    private static func decodeExact(_ code: String) -> (level: Level, seed: UInt64)? {
        var value: UInt64 = 0
        for ch in code {
            guard let i = codeAlphabet.firstIndex(of: ch) else { return nil }
            value = value << 5 | UInt64(i)
        }
        guard let level = Level(rawValue: Int(value >> 28) + 1) else { return nil }
        return (level, value & (seedLimit - 1))
    }

    /// 今日挑战：同一天大家玩同一局（种子按日期算）
    public static func dailySeed(_ day: DayKey) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "叠叠消\(day)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash % seedLimit
    }
}

/// 摆牌用的随机数：同一个种子在哪台手机上都摆出一样的牌。
/// 不用标准库的 random(in:)、shuffled()：它们怎么算可能随系统版本变
public struct SeededRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<n 里的一个
    public mutating func below(_ n: Int) -> Int {
        Int(next() % UInt64(max(n, 1)))
    }

    /// 有 p 的机会是 true
    public mutating func chance(_ p: Double) -> Bool {
        Double(next() >> 11) / Double(UInt64(1) << 53) < p
    }

    public mutating func shuffle<T>(_ items: inout [T]) {
        guard items.count > 1 else { return }
        for i in stride(from: items.count - 1, to: 0, by: -1) {
            items.swapAt(i, below(i + 1))
        }
    }
}

/// 面对面对战：几台手机玩同一局，看谁先消完。房主开局，大家每走一步把进度告诉房主，房主转给别人
public enum TileRace {
    /// 一个人这一局的进度
    public struct Player: Codable, Equatable, Hashable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var cleared: Int
        public var total: Int
        public var status: TileGame.Status
        /// 用了几秒（消完、输了时停在那一刻）
        public var seconds: Double

        public init(id: String, name: String, cleared: Int = 0, total: Int = 0,
                    status: TileGame.Status = .playing, seconds: Double = 0) {
            self.id = id
            self.name = name
            self.cleared = cleared
            self.total = total
            self.status = status
            self.seconds = seconds
        }
    }

    public enum Message: Codable, Equatable, Sendable {
        /// 加入的人告诉房主自己是谁
        case hello(Player)
        /// 房主告诉大家房间里有谁
        case lobby([Player])
        /// 房主开局：第几局、难度、种子
        case start(round: Int, level: TileGame.Level, seed: UInt64)
        /// 每走一步告诉大家自己这一局的进度
        case progress(round: Int, player: Player)
    }

    /// 排名：消完的在前、按用时；没消完的按消了几张（多的在前），一样多按名字
    public static func ranking(_ players: [Player]) -> [Player] {
        players.sorted { a, b in
            let aWon = a.status == .won, bWon = b.status == .won
            if aWon != bWon { return aWon }
            if aWon, a.seconds != b.seconds { return a.seconds < b.seconds }
            if !aWon, a.cleared != b.cleared { return a.cleared > b.cleared }
            return a.name < b.name
        }
    }

    /// 这一局大家都结束了（消完或输了）
    public static func finished(_ players: [Player]) -> Bool {
        !players.isEmpty && players.allSatisfy { $0.status != .playing }
    }
}
