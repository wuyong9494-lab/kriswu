import Foundation

extension StarRail {
    /// An optional planning challenge. Every committed pick or rail move costs
    /// one step; previews and wall-clock time never spend the chain window.
    public struct Chain: Equatable, Sendable {
        public static let window = 4
        public private(set) var score = 0
        public private(set) var current = 0
        public private(set) var best = 0
        public private(set) var stepsLeft = 0
        public private(set) var lastAward = 0

        public init() {}

        mutating func record(matched: Bool) {
            lastAward = 0
            if matched {
                current = stepsLeft > 0 ? current + 1 : 1
                best = max(best, current)
                lastAward = min(current, 5) * 100
                score += lastAward
                stepsLeft = Self.window
            } else if stepsLeft > 0 {
                stepsLeft -= 1
                if stepsLeft == 0 { current = 0 }
            }
        }
    }
}

extension StarRail.Game {
    /// Derive from committed history so undo, resume and replay cannot farm
    /// points or retain a combo from a discarded future. No save migration.
    public var chain: StarRail.Chain {
        var result = StarRail.Chain()
        let states = replayStates
        for index in actions.indices {
            result.record(matched: states[index + 1].matches > states[index].matches)
        }
        return result
    }
}
