import XCTest
@testable import ShiftCore

final class DuelGameTests: XCTestCase {
    private func closeRange(_ hero: DuelGame.Hero = .ember) -> DuelGame {
        var game = DuelGame(hero: hero)
        for _ in 0..<24 { game.step(.init(move: 1), opponent: .init(move: -1)) }
        return game
    }
    func testStartupActiveRecoveryAndOnlyOneHitPerAttack() {
        var game = closeRange()
        game.step(.init(taps: .light), opponent: .neutral)
        XCTAssertEqual(game.fighters[1].health, 1000)
        for _ in 0..<80 { game.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(game.fighters[1].health, 925)
        XCTAssertEqual(game.landedHits[0], 1)
        XCTAssertNil(game.fighters[0].attack)
    }
    func testWhiffDoesNoDamageAndSimultaneousAttacksTrade() {
        var far = DuelGame()
        far.step(.init(taps: .heavy), opponent: .neutral)
        for _ in 0..<70 { far.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(far.damageDealt, [0, 0])
        var trade = closeRange()
        trade.step(.init(taps: .light), opponent: .init(taps: .light))
        for _ in 0..<30 { trade.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(trade.landedHits, [1, 1])
    }
    func testGuardPreventsHealthLossAndConsumesGuardMeter() {
        var game = closeRange()
        game.step(.init(taps: .heavy), opponent: .init(guardHeld: true))
        var blocked = false
        for _ in 0..<80 {
            game.step(.neutral, opponent: .init(guardHeld: true))
            blocked = blocked || game.events.contains(.blocked(defender: 1))
        }
        XCTAssertTrue(blocked)
        XCTAssertEqual(game.fighters[1].health, 1000)
        XCTAssertEqual(game.fighters[1].guardMeter, 670)
        XCTAssertEqual(game.landedHits[0], 0)
    }
    func testMoveAndAttackCanCoexistAndJumpLandsWithoutLeavingWalls() {
        var game = DuelGame()
        let start = game.fighters[0].x
        game.step(.init(move: 1, taps: .light), opponent: .neutral)
        XCTAssertGreaterThan(game.fighters[0].x, start)
        XCTAssertNotNil(game.fighters[0].attack)
        for _ in 0..<80 { game.step(.neutral, opponent: .neutral) }
        game.step(.init(move: -1, taps: .jump), opponent: .neutral)
        for _ in 0..<5 { game.step(.init(move: -1), opponent: .neutral) }
        XCTAssertGreaterThan(game.fighters[0].y, 0)
        for _ in 0..<200 { game.step(.init(move: -1), opponent: .neutral) }
        XCTAssertEqual(game.fighters[0].y, 0)
        XCTAssertEqual(game.fighters[0].x, DuelGame.leftWall)
        let stopped = game.fighters[0].x
        for _ in 0..<12 { game.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(game.fighters[0].x, stopped)
    }
    func testBodyCollisionAndProjectileLifetimeAreBounded() {
        var game = DuelGame(hero: .gale)
        for i in 0..<900 {
            game.step(.init(move: 1, taps: i % 70 == 0 ? .skill1 : []), opponent: .init(move: -1))
            XCTAssertGreaterThanOrEqual(abs(game.fighters[1].x - game.fighters[0].x), DuelGame.bodyWidth)
            for f in game.fighters { XCTAssertTrue((DuelGame.leftWall...DuelGame.rightWall).contains(f.x)) }
            XCTAssertLessThanOrEqual(game.projectiles.count, 4)
        }
    }
    func testKnockdownCannotBeRepeatedlyHitAndWakeupIsProtected() {
        var game = closeRange()
        game.step(.init(taps: .heavy), opponent: .neutral)
        for _ in 0..<30 { game.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(game.fighters[1].knockdown, 0)
        let damage = game.damageDealt[0]
        for _ in 0..<12 { game.step(.init(move: 1, taps: .light), opponent: .neutral) }
        XCTAssertEqual(game.damageDealt[0], damage)
        for _ in 0..<100 {
            game.step(.neutral, opponent: .neutral)
            if game.fighters[1].knockdown == 0 && game.fighters[1].invulnerable > 0 { return }
        }
        XCTFail("Expected protected wakeup")
    }
    func testBestOfThreeReachesResultThroughActualHitsAndCanRestart() {
        for hero in DuelGame.Hero.allCases {
            var game = DuelGame(hero: hero)
            for tick in 0..<15000 {
                let direction = game.fighters[1].x >= game.fighters[0].x ? 1 : -1
                game.step(.init(move: direction, taps: tick % 28 == 0 ? .light : []), opponent: .neutral)
                if case .matchOver = game.phase { break }
            }
            XCTAssertEqual(game.phase, .matchOver(winner: 0))
            XCTAssertEqual(game.wins, [2, 0])
            let result = game
            game.step(.init(move: 1, taps: .skill2))
            XCTAssertEqual(game, result)
            let restarted = DuelGame(hero: hero)
            XCTAssertEqual(restarted.wins, [0, 0])
            XCTAssertEqual(restarted.phase, .fighting)
        }
    }
    func testInputReplayWithSeededAIIsDeterministic() {
        for difficulty in DuelGame.Difficulty.allCases {
            var a = DuelGame(hero: .gale, difficulty: difficulty, seed: 812)
            var b = a
            for tick in 0..<5000 {
                let input = DuelGame.Input(move: tick % 110 < 65 ? 1 : -1, guardHeld: tick % 100 > 80,
                    taps: tick % 41 == 0 ? .skill1 : tick % 23 == 0 ? .light : [])
                a.step(input); b.step(input)
                XCTAssertEqual(a, b)
            }
        }
    }
    func testFixedClockAtDifferentDisplayRatesAndSuspensionReset() {
        for rate in [30, 60, 120] {
            var clock = DuelClock(), steps = 0
            for _ in 0..<rate * 10 { steps += clock.consume(seconds: 1 / Double(rate)) }
            XCTAssertEqual(steps, 600)
        }
        var clock = DuelClock()
        XCTAssertEqual(clock.consume(seconds: 0.01), 0)
        clock.reset()
        XCTAssertEqual(clock.consume(seconds: 0.01), 0)
        XCTAssertEqual(clock.consume(seconds: 10), 6)
        XCTAssertGreaterThan(clock.droppedSeconds, 9)
        XCTAssertEqual(clock.consume(seconds: .infinity), 0)
    }
}
