import XCTest
@testable import ShiftCore

final class TileReplayTests: XCTestCase {
    private var fixture: TileGame {
        TileGame(level: .hard, seed: 13, tiles: (0..<9).map {
            .init(id: $0, kind: $0 % 3, x: $0 * 5, y: 0, z: 0)
        })
    }

    func testAnimationSettlementAndRapidPicksProduceOneFramePerAction() {
        var game = fixture
        var replay = TileReplay(game: game)
        for id in [0, 3, 6, 1] {
            XCTAssertTrue(game.pick(id)) // Do not settle: next pick finishes the animation.
            XCTAssertTrue(replay.append(.pick(id), resultingIn: game))
        }
        XCTAssertEqual(replay.actionCount, 4)
        XCTAssertEqual(replay.frames[3].clearedChange, 3)
        XCTAssertEqual(replay.frames[3].game.waiting, 0)
        XCTAssertTrue(replay.frames.allSatisfy { $0.game.clearing.isEmpty })
        game.settle()
        XCTAssertEqual(replay.frames.last?.game, game)
    }

    func testParkedPicksUndoAndShufflePreserveExactActualState() {
        var game = fixture
        var replay = TileReplay(game: game)
        let actions: [TileReplay.Action] = [.pick(0), .pick(1), .moveOut, .pick(0), .undo, .shuffle]
        for action in actions {
            XCTAssertTrue(action.apply(to: &game))
            XCTAssertTrue(replay.append(action, resultingIn: game))
            XCTAssertEqual(replay.frames.last?.game, game)
        }
        XCTAssertEqual(replay.actionCount, actions.count)
        XCTAssertEqual(replay.frames.last?.game.toolsUsed, 3)
        XCTAssertEqual(replay.frames.last?.game.parked.count, 2)
        XCTAssertEqual(replay.turningPoints, [3, 5, 6])
    }

    func testInvalidMismatchedAndDuplicateEventsCannotRewriteHistory() {
        var game = fixture
        var replay = TileReplay(game: game)
        XCTAssertFalse(replay.append(.pick(-1), resultingIn: game))
        XCTAssertFalse(replay.append(.pick(0), resultingIn: game))
        XCTAssertTrue(game.pick(0))
        XCTAssertTrue(replay.append(.pick(0), resultingIn: game))
        let saved = replay
        XCTAssertFalse(replay.append(.pick(0), resultingIn: game))
        XCTAssertFalse(replay.append(.pick(1), resultingIn: fixture))
        XCTAssertEqual(replay, saved)
        var viewingCopy = replay.frames[0].game
        XCTAssertTrue(viewingCopy.pick(2))
        XCTAssertEqual(replay, saved)
        XCTAssertEqual(game, replay.frames.last?.game)
    }

    func testLossRescueAndFirstAttemptOutcomeRemainIndependentOfViewing() {
        var game = TileGame(level: .hard, seed: 0, tiles: (0..<9).map {
            .init(id: $0, kind: $0, x: $0 * 5, y: 0, z: 0)
        })
        var replay = TileReplay(game: game)
        for id in 0..<7 {
            XCTAssertTrue(game.pick(id))
            XCTAssertTrue(replay.append(.pick(id), resultingIn: game))
        }
        XCTAssertEqual(game.status, .lost)
        XCTAssertEqual(replay.turningPoints, [5, 7])
        let original = game
        for frame in replay.frames { _ = frame.game.freeIDs }
        XCTAssertEqual(game, original)
        XCTAssertTrue(game.undo())
        XCTAssertTrue(replay.append(.undo, resultingIn: game))
        XCTAssertEqual(replay.frames[7].game.status, .lost)
        XCTAssertEqual(replay.frames.last?.game.status, .playing)
        XCTAssertEqual(replay.frames.last?.game.undos, 0)
    }

    func testFullWinningGameReplaysWithoutChangingCodeOrTools() {
        var game = TileGame(level: .hard, seed: 84135585, ruleSet: .constellation)
        var replay = TileReplay(game: game)
        let code = game.code
        for id in game.solution {
            XCTAssertTrue(game.pick(id))
            XCTAssertTrue(replay.append(.pick(id), resultingIn: game))
        }
        game.settle()
        XCTAssertEqual(replay.actionCount, game.total)
        XCTAssertEqual(replay.frames.last?.game, game)
        XCTAssertEqual(game.status, .won)
        XCTAssertEqual(game.toolsUsed, 0)
        XCTAssertTrue(replay.frames.allSatisfy { $0.game.code == code })
    }
}
