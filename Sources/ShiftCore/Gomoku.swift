import Foundation

/// 五子棋：15×15，黑先，横、竖、斜连成五个（或更多）就赢；不设禁手。
/// 存的只是下过的每一步（格子编号 = 行 × 15 + 列），轮流下、联机时发出去的也只是这些
public struct Gomoku: Equatable, Sendable {
    public static let size = 15
    public static let center = size / 2 * size + size / 2

    public enum Stone: Int, Codable, Sendable {
        case black = 1, white = 2

        public var other: Stone { self == .black ? .white : .black }
        public var title: String { self == .black ? "黑" : "白" }
    }

    /// 电脑的难度
    public enum Level: Int, Codable, CaseIterable, Sendable {
        case easy = 1, normal, hard

        public var title: String {
            switch self {
            case .easy: return "简单"
            case .normal: return "普通"
            case .hard: return "难"
            }
        }
    }

    public private(set) var moves: [Int] = []
    public private(set) var cells: [Stone?] = Array(repeating: nil, count: size * size)
    public private(set) var winner: Stone?
    /// 连成的那几颗（赢了才有）
    public private(set) var line: [Int] = []
    /// 谁认输了
    public private(set) var resigned: Stone?

    public init() {}

    /// 按这些步一步步重新下一遍（下不了的那步和之后的都不要）
    public init(moves: [Int], resigned: Stone? = nil) {
        for move in moves where place(move) == false { break }
        if let resigned { resign(resigned) }
    }

    /// 该谁下
    public var next: Stone { moves.count % 2 == 0 ? .black : .white }
    /// 棋盘下满了还没人赢：和棋
    public var isDraw: Bool { winner == nil && moves.count == cells.count }
    public var isOver: Bool { winner != nil || isDraw }

    public subscript(row: Int, column: Int) -> Stone? {
        Self.inside(row, column) ? cells[row * Self.size + column] : nil
    }

    @discardableResult
    public mutating func place(_ index: Int) -> Bool {
        guard !isOver, cells.indices.contains(index), cells[index] == nil else { return false }
        let stone = next
        cells[index] = stone
        moves.append(index)
        if let five = Self.five(at: index, for: stone, in: cells) {
            winner = stone
            line = five
        }
        return true
    }

    /// 悔棋：退回去几步
    public mutating func undo(_ count: Int = 1) {
        self = Gomoku(moves: Array(moves.dropLast(count)))
    }

    public mutating func resign(_ stone: Stone) {
        guard winner == nil else { return }
        winner = stone.other
        resigned = stone
    }

    static func inside(_ row: Int, _ column: Int) -> Bool {
        (0..<size).contains(row) && (0..<size).contains(column)
    }

    static let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]

    /// 在 index 下了 stone 以后，有没有连成五个以上：有的话返回连成的那几颗
    static func five(at index: Int, for stone: Stone, in cells: [Stone?]) -> [Int]? {
        let row = index / size, column = index % size
        for (dr, dc) in directions {
            var line = [index]
            for sign in [1, -1] {
                var r = row + dr * sign, c = column + dc * sign
                while inside(r, c), cells[r * size + c] == stone {
                    line.append(r * size + c)
                    r += dr * sign
                    c += dc * sign
                }
            }
            if line.count >= 5 { return line.sorted() }
        }
        return nil
    }

    // MARK: - 电脑下

    /// 电脑下哪一步。看「五个一组」：每一组五个格子里没有对方的子，自己已经有几个，越多越值钱；
    /// 一个格子的分 = 它所在的各组加起来（进攻）+ 对方在这里的分（防守）。
    /// 先看能不能直接赢、要不要堵对方马上要赢的；难的再往后看一步对方怎么应
    public func suggestion(level: Level, random: inout SeededRandom) -> Int? {
        guard !isOver else { return nil }
        if moves.isEmpty { return Self.center }
        let me = next, them = me.other
        let spots = candidates()
        if let win = spots.first(where: { completes($0, for: me) }) { return win }
        // 简单的有时看不见对方马上要赢
        if let block = spots.first(where: { completes($0, for: them) }), level != .easy || random.chance(0.7) {
            return block
        }
        let ranked = spots.map { ($0, value($0, for: me)) }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first else { return nil }
        switch level {
        case .easy:
            let top = Array(ranked.prefix(6))
            return top[random.below(top.count)].0
        case .normal:
            let ties = ranked.prefix { $0.1 == best.1 }
            return ties[random.below(ties.count)].0
        case .hard:
            // 前几个好点各试一下：对方最好的应手越差越好
            var choice = best.0
            var bestOutcome = Int.min
            for (spot, score) in ranked.prefix(8) {
                var trial = self
                trial.place(spot)
                if trial.winner == me { return spot }
                let reply = trial.candidates().map { trial.value($0, for: them) }.max() ?? 0
                let outcome = score - reply * 7 / 10
                if outcome > bestOutcome {
                    bestOutcome = outcome
                    choice = spot
                }
            }
            return choice
        }
    }

    /// 值得考虑的空格：离已有的子两格以内
    func candidates() -> [Int] {
        var result: [Int] = []
        for index in cells.indices where cells[index] == nil {
            let row = index / Self.size, column = index % Self.size
            var near = false
            for dr in -2...2 where !near {
                for dc in -2...2 where Self.inside(row + dr, column + dc) && cells[(row + dr) * Self.size + column + dc] != nil {
                    near = true
                    break
                }
            }
            if near { result.append(index) }
        }
        return result
    }

    /// 在这里下 stone 能不能直接连成五个
    func completes(_ index: Int, for stone: Stone) -> Bool {
        var trial = cells
        trial[index] = stone
        return Self.five(at: index, for: stone, in: trial) != nil
    }

    /// 这个空格对 stone 的分：进攻分加上防守分（对方在这里的进攻分打个折）
    func value(_ index: Int, for stone: Stone) -> Int {
        tuples(index, for: stone, weights: Self.attack) + tuples(index, for: stone.other, weights: Self.defense)
    }

    /// 自己已经有 0…4 个子的一组值多少（进攻、防守）
    static let attack = [7, 35, 800, 15_000, 800_000]
    static let defense = [7, 15, 400, 1_800, 100_000]

    private func tuples(_ index: Int, for stone: Stone, weights: [Int]) -> Int {
        let row = index / Self.size, column = index % Self.size
        var total = 0
        for (dr, dc) in Self.directions {
            for start in -4...0 {
                var mine = 0
                var open = true
                for k in 0..<5 {
                    let r = row + dr * (start + k), c = column + dc * (start + k)
                    guard Self.inside(r, c) else { open = false; break }
                    let cell = cells[r * Self.size + c]
                    if cell == stone.other { open = false; break }
                    if cell == stone { mine += 1 }
                }
                if open { total += weights[mine] }
            }
        }
        return total
    }
}

extension Gomoku: Codable {
    private enum CodingKeys: String, CodingKey { case moves, resigned }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(moves: try container.decode([Int].self, forKey: .moves),
                  resigned: try container.decodeIfPresent(Stone.self, forKey: .resigned))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(moves, forKey: .moves)
        try container.encodeIfPresent(resigned, forKey: .resigned)
    }
}
