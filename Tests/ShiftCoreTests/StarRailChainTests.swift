import XCTest
@testable import ShiftCore

final class StarRailChainTests: XCTestCase {
    func testFourthStepExtendsButFifthStepRestartsWithoutLosingScore() {
        var fourth = StarRail.Chain()
        fourth.record(matched: true)
        for _ in 0..<3 { fourth.record(matched: false) }
        fourth.record(matched: true)
        XCTAssertEqual(fourth.current, 2)
        XCTAssertEqual(fourth.score, 300)
        var fifth = StarRail.Chain()
        fifth.record(matched: true)
        for _ in 0..<4 { fifth.record(matched: false) }
        XCTAssertEqual(fifth.current, 0)
        XCTAssertEqual(fifth.score, 100)
        fifth.record(matched: true)
        XCTAssertEqual(fifth.current, 1)
        XCTAssertEqual(fifth.score, 200)
    }

    func testAwardCapsAtFiveWithoutCappingCombo() {
        var chain = StarRail.Chain()
        for _ in 0..<6 {
            for _ in 0..<2 { chain.record(matched: false) }
            chain.record(matched: true)
        }
        XCTAssertEqual(chain.current, 6)
        XCTAssertEqual(chain.best, 6)
        XCTAssertEqual(chain.lastAward, 500)
        XCTAssertEqual(chain.score, 2000)
    }

    func testRealMovesPreviewsRejectedPicksUndoAndSaveRecovery() throws {
        var game = StarRail.Game(stage: StarRail.stage(1)!)
        for id in [0, 1, 2] { XCTAssertTrue(game.perform(.pick(id))) }
        XCTAssertEqual(game.chain.score, 100)
        XCTAssertEqual(game.chain.stepsLeft, 4)
        let before = game.chain
        XCTAssertTrue(try XCTUnwrap(game.preview(0, in: game.state)).canMove)
        XCTAssertEqual(game.chain, before)
        XCTAssertTrue(game.perform(.shift(0)))
        XCTAssertEqual(game.chain.stepsLeft, 3)
        let moved = game.chain
        XCTAssertFalse(game.perform(.pick(5)))
        XCTAssertEqual(game.chain, moved)
        let data = try JSONEncoder().encode(game.archive)
        let archive = try JSONDecoder().decode(StarRail.Game.Archive.self, from: data)
        XCTAssertEqual(try XCTUnwrap(StarRail.Game(archive: archive)).chain, moved)
        XCTAssertTrue(game.undo())
        XCTAssertEqual(game.chain, before)
        XCTAssertTrue(game.perform(.shift(0)))
        for id in [9, 10, 11] { XCTAssertTrue(game.perform(.pick(id))) }
        XCTAssertEqual(game.chain.current, 2)
        XCTAssertEqual(game.chain.score, 300)
        XCTAssertTrue(game.undo())
        XCTAssertEqual(game.chain.score, 100)
        XCTAssertTrue(game.perform(.pick(11)))
        XCTAssertEqual(game.chain.score, 300, "Undo and replay must not farm score")
        for id in [3, 4, 6, 5, 7, 8] { XCTAssertTrue(game.perform(.pick(id))) }
        XCTAssertEqual(game.status, .won)
        XCTAssertEqual(game.chain.best, 4)
        XCTAssertEqual(game.chain.score, 1000)
    }

    func testRewindAndRestartDiscardFutureChain() throws {
        var game = StarRail.Game(stage: StarRail.stage(1)!)
        for action in [StarRail.Action.pick(0), .pick(1), .pick(2), .shift(0), .pick(9), .pick(10), .pick(11)] {
            XCTAssertTrue(game.perform(action))
        }
        var session = StarRail.Session(game: game)
        XCTAssertTrue(session.rewind(to: 3))
        XCTAssertEqual(session.game.chain.score, 100)
        XCTAssertEqual(session.game.chain.stepsLeft, 4)
        session.setActive(false)
        session.setActive(true)
        XCTAssertEqual(session.game.chain.stepsLeft, 4)
        session.restart()
        XCTAssertEqual(session.game.chain, StarRail.Chain())
    }
}
