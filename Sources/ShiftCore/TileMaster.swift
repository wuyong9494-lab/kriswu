import Foundation

extension TileGame {
    /// Screen only newly opened master games. Existing seeds, daily games and
    /// challenge codes keep their exact layouts and original guaranteed solution.
    /// This is a bounded heuristic screen, not a claim of measured human difficulty.
    public static func masterSeed(startingAt seed: UInt64, ruleSet: RuleSet) -> UInt64 {
        var bestSeed = seed % seedLimit
        var bestWins = Int.max
        for offset in 0..<8 {
            if Task.isCancelled { break }
            let candidate = (seed % seedLimit + UInt64(offset) * 104729) % seedLimit
            let game = TileGame(level: .hard, seed: candidate, ruleSet: ruleSet)
            let wins = (0..<3).reduce(0) { $0 + (game.greedyClear(policy: $1) ? 1 : 0) }
            if wins < bestWins {
                bestWins = wins
                bestSeed = candidate
            }
            if wins == 0 { break }
        }
        return bestSeed
    }

    /// Edition 1 is frozen: the same date always selects the same board.
    /// Prefer fewer shallow wins, then greater minimum progress: avoid selecting
    /// a deal solely because every policy crashes immediately at the opening.
    public static func dailyMasterSeed(_ day: DayKey) -> UInt64 {
        let base = dailySeed(day)
        var chosen = base
        var bestWins = Int.max
        var bestProgress = -1
        for offset in 0..<12 {
            if Task.isCancelled { break }
            let seed = (base + UInt64(offset) * 104729) % seedLimit
            let game = TileGame(level: .hard, seed: seed, ruleSet: .constellation)
            let progress = (0..<3).map { game.greedyProgress(policy: $0) }
            let wins = progress.filter { $0 == game.total }.count
            let minimum = progress.min() ?? 0
            if wins < bestWins || (wins == bestWins && minimum > bestProgress) {
                chosen = seed
                bestWins = wins
                bestProgress = minimum
            }
        }
        return chosen
    }

    public static func dailyMasterRecordKey(_ day: DayKey) -> String {
        "master-v1:" + day.description
    }

    /// Three deliberately shallow players: match first, expose first, and
    /// match first with reversed tie breaks. No tools, hidden solution or randomness.
    func greedyClear(policy: Int) -> Bool { greedyProgress(policy: policy) == total }

    func greedyProgress(policy: Int) -> Int {
        var game = self
        // Geometry never changes during tool-free trial play. Build cover edges
        // once instead of rescanning overlapping rectangles for every candidate.
        let blockers = Dictionary(uniqueKeysWithValues: board.map { lower in
            (lower.id, board.filter { $0.z > lower.z && $0.overlaps(lower) }.map(\.id))
        })
        while game.status == .playing {
            if Task.isCancelled { return game.cleared }
            let remaining = Set(game.board.map(\.id))
            var freeIDs = Set<Int>()
            var openedBy: [Int: Int] = [:]
            for tile in game.board {
                let active = (blockers[tile.id] ?? []).filter { remaining.contains($0) }
                if active.isEmpty { freeIDs.insert(tile.id) }
                if active.count == 1 { openedBy[active[0], default: 0] += 1 }
            }
            let free = game.board.filter { freeIDs.contains($0.id) }
            guard !free.isEmpty else { return game.cleared }
            let counts = Dictionary(grouping: game.tray, by: \.kind).mapValues(\.count)
            let ranks = free.map { tile -> (tile: Tile, rank: Int) in
                let match = counts[tile.kind, default: 0]
                let opens = openedBy[tile.id, default: 0]
                let rank = policy == 1 ? (match == 2 ? 10000 : 0) + opens * 10 + match : match * 1000 + opens
                return (tile, rank)
            }
            let choice = ranks.max { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                return policy == 2 ? a.tile.id < b.tile.id : a.tile.id > b.tile.id
            }!.tile
            guard game.pick(choice.id) else { return game.cleared }
            game.settle()
        }
        return game.cleared
    }
}
