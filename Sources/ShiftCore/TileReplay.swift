import Foundation

/// Read-only history of accepted actions. Each frame is settled, so animation
/// timing cannot create extra moves or change the board shown in a replay.
public struct TileReplay: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case pick(Int), undo, moveOut, shuffle

        @discardableResult
        public func apply(to game: inout TileGame) -> Bool {
            switch self {
            case .pick(let id): return game.pick(id)
            case .undo: return game.undo()
            case .moveOut: return game.moveOut()
            case .shuffle: return game.shuffle()
            }
        }
    }

    public struct Frame: Equatable, Sendable {
        public let action: Action?
        public let game: TileGame
        public let waitingChange: Int
        public let clearedChange: Int
        public let exposedIDs: Set<Int>
    }

    public private(set) var frames: [Frame]
    public var actionCount: Int { frames.count - 1 }
    /// Entry into a tight tray, a loss, or a tool use. These are navigation
    /// markers, not a claim that a particular move caused the eventual loss.
    public var turningPoints: [Int] {
        frames.indices.dropFirst().filter { index in
            let frame = frames[index]
            let prior = frames[index - 1]
            if frame.game.status == .lost { return true }
            if frame.game.toolsUsed > prior.game.toolsUsed { return true }
            return frame.game.waiting >= 5 && prior.game.waiting < 5
        }
    }

    public init(game: TileGame) {
        var settled = game
        settled.settle()
        frames = [.init(action: nil, game: settled, waitingChange: 0, clearedChange: 0, exposedIDs: [])]
    }

    /// Reject stale, illegal, duplicated or mismatched observations. This never
    /// mutates the live game and cannot grant an undo, tool, or new attempt.
    @discardableResult
    public mutating func append(_ action: Action, resultingIn observed: TileGame) -> Bool {
        let previous = frames[frames.count - 1].game
        var expected = previous
        guard action.apply(to: &expected) else { return false }
        expected.settle()
        var actual = observed
        actual.settle()
        guard expected == actual else { return false }
        frames.append(.init(action: action, game: actual,
                            waitingChange: actual.waiting - previous.waiting,
                            clearedChange: actual.cleared - previous.cleared,
                            exposedIDs: actual.freeIDs.subtracting(previous.freeIDs)))
        return true
    }
}
