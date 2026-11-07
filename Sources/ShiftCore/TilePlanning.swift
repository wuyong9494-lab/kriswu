import Foundation

extension TileGame {
    /// Bounded beam search. Failure means this search did not solve the board,
    /// never that the board is impossible or that a human has a given win rate.
    public struct PlanningReport: Equatable, Sendable {
        public let won: Bool
        public let expanded: Int
        public let budgetReached: Bool
        public let cancelled: Bool
        public let cleared: Int
        public let solution: [Int]
    }

    public func planningProbe(width: Int, nodeLimit: Int) -> PlanningReport {
        var settled = self
        settled.settle()
        return TilePlanner(game: settled).run(width: width, limit: nodeLimit)
    }

    public struct DailyPlanningSelection: Equatable, Sendable {
        public let seed: UInt64
        public let planningGapVerified: Bool
        public let criticalForks: Int
        public let candidatesChecked: Int
        public let expanded: Int
    }

    /// Edition 2: screen bounded alternatives, then require an actual winning
    /// search path before treating a narrow/wide search gap as verified.
    /// Keep edition 1 and all seed-based boards intact for replay compatibility.
    public static func dailyPlanningSelection(_ day: DayKey) -> DailyPlanningSelection {
        let fallback = dailyMasterSeed(day)
        var candidates: [(seed: UInt64, narrow: PlanningReport)] = []
        var expanded = 0
        for offset in 0..<8 {
            if Task.isCancelled { break }
            let seed = offset == 0 ? fallback : (dailySeed(day) + UInt64(offset) * 104729) % seedLimit
            guard !candidates.contains(where: { $0.seed == seed }) else { continue }
            let game = TileGame(level: .hard, seed: seed, ruleSet: .constellation)
            let report = game.planningProbe(width: 4, nodeLimit: 16000)
            expanded += report.expanded
            candidates.append((seed, report))
        }
        // Reaching farther with a narrow search avoids choosing solely for an
        // opening that immediately defeats every route. All ties are stable.
        let shortlist = candidates.filter { !$0.narrow.won && !$0.narrow.budgetReached && !$0.narrow.cancelled }
            .sorted { a, b in
                a.narrow.cleared == b.narrow.cleared ? a.seed < b.seed : a.narrow.cleared > b.narrow.cleared
            }.prefix(3)
        for candidate in shortlist {
            if Task.isCancelled { break }
            let game = TileGame(level: .hard, seed: candidate.seed, ruleSet: .constellation)
            let wide = game.planningProbe(width: 32, nodeLimit: 100000)
            expanded += wide.expanded
            if wide.won {
                let forks = game.planningForks(along: wide.solution)
                if !forks.isEmpty {
                    return .init(seed: candidate.seed, planningGapVerified: true, criticalForks: forks.count,
                                 candidatesChecked: candidates.count, expanded: expanded)
                }
            }
        }
        // No verified gap: retain the existing guaranteed-solvable daily deal.
        // Do not silently classify search exhaustion as increased difficulty.
        return .init(seed: fallback, planningGapVerified: false, criticalForks: 0,
                     candidatesChecked: candidates.count, expanded: expanded)
    }

    public struct PlanningFork: Equatable, Sendable {
        public let pickNumber: Int
        public let winningTile: Int
        public let losingTile: Int
        public let lossWithinPicks: Int
    }

    /// A fork is counted only after replaying the supplied full winning path.
    /// Its alternative remains alive immediately, but every continuation within
    /// the next two picks loses. Budget exhaustion is unknown, never a proof.
    public func planningForks(along path: [Int], nodeLimit: Int = 8000) -> [PlanningFork] {
        // Parked tiles are additional legal moves; this no-tools proof does not
        // model them, so it must decline rather than report a false forced loss.
        guard parked.isEmpty else { return [] }
        var proof = self
        proof.settle()
        for id in path {
            guard proof.pick(id) else { return [] }
            proof.settle()
        }
        guard proof.status == .won else { return [] }
        var game = self
        game.settle()
        var remaining = max(0, min(nodeLimit, 16000))
        var forks: [PlanningFork] = []
        for (step, goodID) in path.enumerated() {
            if Task.isCancelled || remaining == 0 || forks.count >= 3 { break }
            if (4...5).contains(game.waiting) {
                for tile in game.board.sorted(by: { $0.id < $1.id }) where tile.id != goodID && game.isFree(tile) {
                    var alternative = game
                    guard alternative.pick(tile.id) else { continue }
                    alternative.settle()
                    guard alternative.status == .playing else { continue }
                    if forcedPlanningLoss(alternative, plies: 2, remaining: &remaining) == true {
                        forks.append(.init(pickNumber: step + 1, winningTile: goodID,
                                           losingTile: tile.id, lossWithinPicks: 3))
                        break
                    }
                    if remaining == 0 { break }
                }
            }
            guard game.pick(goodID) else { return [] }
            game.settle()
        }
        return forks
    }

    /// Pre-audited results avoid repeating the bounded search on launch.
    /// The audit checks these values against the frozen edition-2 selector.
    public static func dailyPlanningSeed(_ day: DayKey) -> UInt64 {
        let audited: [String: UInt64] = [
            "2026-11-07": 84135585,
            "2026-11-08": 84550586,
            "2026-11-09": 83817048,
            "2026-11-10": 84616059,
            "2026-11-11": 83778662,
            "2026-11-12": 84198013,
            "2026-11-13": 83988990,
        ]
        return audited[day.description] ?? dailyPlanningSelection(day).seed
    }

    public static func dailyPlanningRecordKey(_ day: DayKey) -> String {
        "master-v2:" + day.description
    }
}

private struct PlanningMask: Hashable {
    var a: UInt64 = 0
    var b: UInt64 = 0
    var c: UInt64 = 0

    mutating func insert(_ i: Int) {
        if i < 64 { a |= 1 << i }
        else if i < 128 { b |= 1 << (i - 64) }
        else { c |= 1 << (i - 128) }
    }
    mutating func remove(_ i: Int) {
        if i < 64 { a &= ~(1 << i) }
        else if i < 128 { b &= ~(1 << (i - 64)) }
        else { c &= ~(1 << (i - 128)) }
    }
    func contains(_ i: Int) -> Bool {
        if i < 64 { return a & (1 << i) != 0 }
        if i < 128 { return b & (1 << (i - 64)) != 0 }
        return c & (1 << (i - 128)) != 0
    }
    func intersects(_ other: Self) -> Bool { (a & other.a) | (b & other.b) | (c & other.c) != 0 }
    var isEmpty: Bool { a == 0 && b == 0 && c == 0 }
}

private struct PlanningKey: Hashable {
    var remaining: PlanningMask
    // Two bits per kind: 0, 1 or 2 waiting tiles; a third clears immediately.
    var tray: UInt64
}

private struct PlanningNode {
    var key: PlanningKey
    var waiting: Int
    var cleared: Int
    var path: [Int]
    var rank: Int
}

private struct TilePlanner {
    let game: TileGame
    let tiles: [TileGame.Tile]
    let kinds: [Int]
    let kindValues: [Int]
    let blockers: [PlanningMask]
    let supported: Bool

    init(game: TileGame) {
        self.game = game
        let tiles = game.board.sorted { $0.id < $1.id }
        self.tiles = tiles
        let values = Set((tiles + game.tray).map(\.kind)).sorted()
        kindValues = values
        let valid = tiles.count <= 192 && values.count <= 32 && game.parked.isEmpty
        supported = valid
        guard valid else { kinds = []; blockers = []; return }
        kinds = tiles.map { values.firstIndex(of: $0.kind)! }
        blockers = tiles.map { lower in
            var mask = PlanningMask()
            for (i, upper) in tiles.enumerated() where upper.z > lower.z && upper.overlaps(lower) { mask.insert(i) }
            return mask
        }
    }

    func run(width: Int, limit: Int) -> TileGame.PlanningReport {
        var expanded = 0
        var bestCleared = game.cleared
        func report(won: Bool = false, budget: Bool = false, cancelled: Bool = false, path: [Int] = []) -> TileGame.PlanningReport {
            .init(won: won, expanded: expanded, budgetReached: budget, cancelled: cancelled,
                  cleared: bestCleared, solution: path)
        }
        guard supported, game.status != .lost else { return report() }
        if game.status == .won { return report(won: true) }
        let beamWidth = min(max(width, 1), 128)
        let budget = min(max(limit, 0), 200000)
        var mask = PlanningMask()
        for i in tiles.indices { mask.insert(i) }
        var tray: UInt64 = 0
        for value in kindValues {
            let count = game.tray.filter { $0.kind == value }.count
            guard count < 3 else { return report() }
            let shift = 2 * kindValues.firstIndex(of: value)!
            tray |= UInt64(count) << shift
        }
        var beam = [PlanningNode(key: .init(remaining: mask, tray: tray), waiting: game.tray.count,
                                 cleared: game.cleared, path: [], rank: 0)]
        for _ in tiles.indices {
            var next: [PlanningNode] = []
            var visited = Set<PlanningKey>()
            for node in beam {
                if Task.isCancelled { return report(cancelled: true) }
                for i in tiles.indices where node.key.remaining.contains(i) && !blockers[i].intersects(node.key.remaining) {
                    if expanded >= budget { return report(budget: true) }
                    expanded += 1
                    var child = node
                    child.key.remaining.remove(i)
                    let shift = kinds[i] * 2
                    let count = Int((child.key.tray >> shift) & 3)
                    child.key.tray &= ~(UInt64(3) << shift)
                    if count == 2 {
                        child.waiting -= 2
                        child.cleared += 3
                    } else {
                        child.key.tray |= UInt64(count + 1) << shift
                        child.waiting += 1
                    }
                    guard child.waiting < TileGame.capacity else { continue }
                    guard visited.insert(child.key).inserted else { continue }
                    child.path.append(tiles[i].id)
                    bestCleared = max(bestCleared, child.cleared)
                    if child.key.remaining.isEmpty && child.waiting == 0 { return report(won: true, path: child.path) }
                    child.rank = rank(child)
                    next.append(child)
                }
            }
            guard !next.isEmpty else { return report() }
            next.sort {
                if $0.rank != $1.rank { return $0.rank > $1.rank }
                return $0.path.lexicographicallyPrecedes($1.path)
            }
            beam = Array(next.prefix(beamWidth))
        }
        return report()
    }

    func rank(_ node: PlanningNode) -> Int {
        var visible = [Int](repeating: 0, count: kindValues.count)
        for i in tiles.indices where node.key.remaining.contains(i) && !blockers[i].intersects(node.key.remaining) {
            visible[kinds[i]] += 1
        }
        var ready = 0
        var stranded = 0
        for kind in kindValues.indices {
            let waiting = Int((node.key.tray >> (kind * 2)) & 3)
            if visible[kind] + waiting >= 3 { ready += 1 }
            if waiting > 0 && visible[kind] == 0 { stranded += waiting }
        }
        return node.cleared * 100 + ready * 18 - node.waiting * 12 - stranded * 25 + visible.reduce(0, +)
    }
}

/// Full enumeration for a very short horizon; unlike beam search, a true
/// result here proves all legal continuations lose without tools.
private func forcedPlanningLoss(_ game: TileGame, plies: Int, remaining: inout Int) -> Bool? {
    if game.status == .lost { return true }
    if game.status == .won || plies == 0 { return false }
    if Task.isCancelled || remaining == 0 { return nil }
    let free = game.board.filter { game.isFree($0) }.sorted { $0.id < $1.id }
    guard !free.isEmpty else { return nil }
    var unknown = false
    for tile in free {
        if remaining == 0 { return nil }
        remaining -= 1
        var next = game
        guard next.pick(tile.id) else { return nil }
        next.settle()
        let result = forcedPlanningLoss(next, plies: plies - 1, remaining: &remaining)
        if result == false { return false }
        if result == nil { unknown = true }
    }
    return unknown ? nil : true
}
