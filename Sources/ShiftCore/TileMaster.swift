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

    /// Three deliberately shallow players: match first, expose first, and
    /// match first with reversed tie breaks. No tools, hidden solution or randomness.
    func greedyClear(policy: Int) -> Bool {
        var game = self
        while game.status == .playing {
            if Task.isCancelled { return false }
            let free = game.board.filter { game.isFree($0) }
            guard !free.isEmpty else { return false }
            let counts = Dictionary(grouping: game.tray, by: \.kind).mapValues(\.count)
            let ranks = free.map { tile -> (tile: Tile, rank: Int) in
                let match = counts[tile.kind, default: 0]
                let opens = game.board.filter { lower in
                    lower.z < tile.z && lower.overlaps(tile) &&
                    !game.board.contains { other in
                        other.id != tile.id && other.z > lower.z && other.overlaps(lower)
                    }
                }.count
                let rank = policy == 1 ? (match == 2 ? 10000 : 0) + opens * 10 + match : match * 1000 + opens
                return (tile, rank)
            }
            let choice = ranks.max { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                return policy == 2 ? a.tile.id < b.tile.id : a.tile.id > b.tile.id
            }!.tile
            guard game.pick(choice.id) else { return false }
            game.settle()
        }
        return game.status == .won
    }
}
