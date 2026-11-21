#if L12_INTERNAL_PREVIEW
import XCTest
@testable import ShiftCore

final class DuelXuXiaoPracticeTests: XCTestCase {
    private func closeRange() -> DuelXuXiaoPractice {
        var game = DuelXuXiaoPractice()
        for _ in 0..<40 { game.step(.init(right: true)) }
        return game
    }
    func testFreshStateAndSyntheticDuration() {
        let game = DuelXuXiaoPractice()
        XCTAssertEqual(game.fighters.map(\.health), [100, 100])
        XCTAssertEqual(game.fighters.map(\.x), [3900, 6100])
        XCTAssertEqual(game.remainingSeconds, 60)
        XCTAssertNil(game.outcome)
    }
    func testOppositeDirectionsCancelWithoutGuard() {
        var game = DuelXuXiaoPractice()
        game.step(.init(left: true, right: true))
        XCTAssertEqual(game.fighters[0].x, 3900)
        XCTAssertFalse(game.fighters[0].guarding)
    }
    func testForwardMovementNeverCrossesOpponent() {
        let game = closeRange()
        XCTAssertEqual(game.fighters[1].x - game.fighters[0].x, 500)
        XCTAssertEqual(game.fighters.map(\.facing), [1, -1])
    }
    func testRearMovementExplicitlyGuardsButIdleDoesNot() {
        var game = DuelXuXiaoPractice()
        game.step(.init(left: true))
        XCTAssertTrue(game.fighters[0].guarding)
        XCTAssertEqual(game.fighters[0].x, 3852)
        game.step(.init())
        XCTAssertFalse(game.fighters[0].guarding)
    }
    func testSwordHasWindupAndHitsOnlyOnce() {
        var game = DuelXuXiaoPractice()
        for _ in 0..<15 { game.step(.init(right: true)) }
        game.step(.init(attack: true))
        for _ in 0..<7 { game.step(.init()) }
        XCTAssertEqual(game.fighters[1].health, 100)
        game.step(.init())
        XCTAssertEqual(game.fighters[1].health, 88)
        for _ in 0..<8 { game.step(.init()) }
        XCTAssertEqual(game.fighters[1].health, 88)
    }
    func testHeavyWinsSimultaneousButtonChoiceAndUsesOwnWindup() {
        var game = DuelXuXiaoPractice()
        for _ in 0..<15 { game.step(.init(right: true)) }
        game.step(.init(attack: true, heavy: true))
        XCTAssertEqual(game.fighters[0].strike, .heavy)
        for _ in 0..<19 { game.step(.init()) }
        XCTAssertEqual(game.fighters[1].health, 100)
        game.step(.init())
        XCTAssertEqual(game.fighters[1].health, 76)
    }
    func testOutOfRangeSwordDoesNotInventContact() {
        var game = DuelXuXiaoPractice()
        game.step(.init(attack: true))
        for _ in 0..<8 { game.step(.init()) }
        XCTAssertEqual(game.fighters[1].health, 100)
        XCTAssertNil(game.lastImpact)
    }
    func testRearGuardReducesRealAIContact() {
        var game = closeRange()
        for _ in 0..<7 { game.step(.init()) }
        for _ in 0..<9 { game.step(.init(left: true)) }
        XCTAssertEqual(game.tick, 56)
        XCTAssertEqual(game.fighters[0].health, 98)
        XCTAssertEqual(game.lastImpact?.blocked, true)
    }
    func testIdlePlayerLosesAndTerminalStateFreezes() {
        var game = DuelXuXiaoPractice()
        for _ in 0..<DuelXuXiaoPractice.maximumTicks { game.step(.init()) }
        XCTAssertEqual(game.outcome, .lost)
        XCTAssertEqual(game.fighters[0].health, 0)
        let finished = game
        for _ in 0..<120 { game.step(.init(left: true, attack: true, heavy: true)) }
        XCTAssertEqual(game, finished)
    }
    func testPlayerCanWinSingleFightWithoutCatalog() {
        var game = DuelXuXiaoPractice()
        for _ in 0..<DuelXuXiaoPractice.maximumTicks {
            let near = game.fighters[1].x - game.fighters[0].x <= 500
            game.step(.init(right: !near, heavy: near))
        }
        XCTAssertEqual(game.outcome, .won)
        XCTAssertEqual(game.fighters[1].health, 0)
    }
    func testRematchStartsWithFreshStateNotPreviousDamage() {
        var game = closeRange()
        for _ in 0..<120 { game.step(.init()) }
        XCTAssertNotEqual(game, DuelXuXiaoPractice())
        game = .init()
        XCTAssertEqual(game, DuelXuXiaoPractice())
        XCTAssertNil(game.lastImpact)
    }
    func testRepeatedInputStreamIsDeterministicAndBounded() {
        var first = DuelXuXiaoPractice(), second = DuelXuXiaoPractice()
        var seed: UInt64 = 42
        for _ in 0..<7200 {
            seed = seed &* 6364136223846793005 &+ 1
            let input = DuelXuXiaoPractice.Input(left: seed & 1 != 0, right: seed & 2 != 0,
                                                attack: seed & 4 != 0, heavy: seed & 8 != 0)
            first.step(input); second.step(input)
            XCTAssertEqual(first, second)
            XCTAssertLessThanOrEqual(first.tick, DuelXuXiaoPractice.maximumTicks)
            XCTAssertGreaterThanOrEqual(first.fighters[1].x - first.fighters[0].x, 500)
            for fighter in first.fighters {
                XCTAssertTrue((0...100).contains(fighter.health))
                XCTAssertTrue((700...9300).contains(fighter.x))
            }
        }
        XCTAssertNotNil(first.outcome)
    }
}
#endif
