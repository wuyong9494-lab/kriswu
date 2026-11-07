import XCTest
@testable import ShiftCore

final class DuelGrappleTests: XCTestCase {
    private func closeRange(attacker: Int = 0, mode: DuelGame.Mode = .versus) -> DuelGame {
        var game = DuelGame(hero: attacker == 0 ? .liu : .gale, mode: mode,
                            opponentHero: attacker == 0 ? .gale : .liu)
        for _ in 0..<24 { game.step(.init(move: 1), opponent: .init(move: -1)) }
        return game
    }
    private func capture(_ game: inout DuelGame, attacker: Int = 0, guardHeld: Bool = false) {
        game.step(attacker == 0 ? .init(taps: .ultimate) : .neutral,
                  opponent: attacker == 1 ? .init(taps: .ultimate) : .init(guardHeld: guardHeld))
        for _ in 0..<35 {
            if game.grapple != nil { break }
            game.step(.neutral, opponent: .init(guardHeld: guardHeld))
        }
        XCTAssertEqual(game.grapple?.attacker, attacker)
        XCTAssertEqual(game.grapple?.age, 0)
    }
    func testThreeSecondHoldDealsOnlyTwoImpactsAndReleasesBothFighters() {
        var game = closeRange()
        capture(&game)
        let timer = game.remainingTicks
        for _ in 0..<24 { game.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(game.grapple?.stage, .hold)
        XCTAssertEqual(game.grapple?.holdRemaining, 180)
        XCTAssertEqual(game.damageDealt[0], 100)
        let positions = game.fighters.map(\.x)
        for _ in 0..<179 {
            game.step(.init(move: 1, taps: [.light, .jump, .ultimate]),
                      opponent: .init(move: -1, guardHeld: true, taps: [.light, .jump]))
            XCTAssertEqual(game.grapple?.stage, .hold)
            XCTAssertEqual(game.fighters.map(\.x), positions)
            XCTAssertEqual(game.damageDealt[0], 100)
        }
        game.step(.neutral, opponent: .neutral)
        XCTAssertEqual(game.grapple?.stage, .release)
        XCTAssertEqual(game.grapple?.holdRemaining, 0)
        XCTAssertEqual(game.damageDealt[0], 280)
        for _ in 0..<24 { game.step(.neutral, opponent: .neutral) }
        XCTAssertNil(game.grapple)
        XCTAssertEqual(game.remainingTicks, timer, "The round timer must not expire in the locked animation")
        XCTAssertEqual(game.landedHits, [2, 0])
        XCTAssertEqual(game.fighters[1].health, 720)
        XCTAssertGreaterThan(game.fighters[1].x, positions[1])
        for _ in 0..<90 { game.step(.neutral, opponent: .neutral) }
        XCTAssertTrue(game.fighters.allSatisfy { $0.attack == nil && $0.stun == 0 && $0.knockdown == 0 })
        let x = game.fighters[0].x
        game.step(.init(move: -1), opponent: .neutral)
        XCTAssertLessThan(game.fighters[0].x, x)
        XCTAssertEqual(game.landedHits, [2, 0], "Commands entered during the hold must not play after release")
    }
    func testGrabBeatsGuardButJumpAndRetreatAvoidIt() {
        var guarded = closeRange(); capture(&guarded, guardHeld: true)
        XCTAssertNotNil(guarded.grapple)
        var jumping = closeRange()
        jumping.step(.init(taps: .ultimate), opponent: .neutral)
        for tick in 0..<100 {
            jumping.step(.neutral, opponent: .init(taps: tick == 12 ? .jump : []))
            XCTAssertNil(jumping.grapple)
        }
        XCTAssertEqual(jumping.damageDealt[0], 0)
        var retreating = closeRange()
        retreating.step(.init(taps: .ultimate), opponent: .neutral)
        for _ in 0..<100 { retreating.step(.neutral, opponent: .init(move: 1)); XCTAssertNil(retreating.grapple) }
        XCTAssertEqual(retreating.damageDealt[0], 0)
    }
    func testQuickStrikeInterruptsStartupAndSameTickStrikeWinsOverGrab() {
        for delay in [0, 18] {
            var game = closeRange()
            game.step(.init(taps: .ultimate), opponent: delay == 0 ? .init(taps: .light) : .neutral)
            for tick in 1..<110 {
                game.step(.neutral, opponent: tick == delay ? .init(taps: .light) : .neutral)
                XCTAssertNil(game.grapple)
            }
            XCTAssertEqual(game.damageDealt[0], 0)
            XCTAssertEqual(game.damageDealt[1], 75)
        }
    }
    func testWhiffHasRecoveryAndCostsEnergyWithoutDamage() {
        var game = DuelGame(hero: .liu)
        game.step(.init(taps: .ultimate), opponent: .neutral)
        let x = game.fighters[0].x
        for _ in 0..<30 { game.step(.init(move: 1, taps: .light), opponent: .neutral) }
        XCTAssertEqual(game.fighters[0].attack?.move, .ultimate)
        XCTAssertEqual(game.fighters[0].x, x)
        var whiff = false
        for _ in 0..<80 {
            game.step(.neutral, opponent: .neutral)
            whiff = whiff || game.events.contains(.whiff(attacker: 0))
        }
        XCTAssertTrue(whiff)
        XCTAssertNil(game.fighters[0].attack)
        XCTAssertEqual(game.damageDealt, [0, 0])
        XCTAssertLessThan(game.fighters[0].energy, 20)
        game.step(.init(taps: .ultimate), opponent: .neutral)
        XCTAssertNil(game.fighters[0].attack, "The spent ultimate must not chain from regenerated partial energy")
    }
    func testUltimateIsGroundedAndExclusiveToLiu() {
        for hero in [DuelGame.Hero.ember, .gale] {
            var game = DuelGame(hero: hero)
            game.step(.init(taps: .ultimate), opponent: .neutral)
            XCTAssertNil(game.fighters[0].attack)
            XCTAssertEqual(game.fighters[0].energy, 100)
        }
        var game = closeRange()
        game.step(.init(taps: [.jump, .ultimate]), opponent: .neutral)
        XCTAssertNil(game.fighters[0].attack)
        XCTAssertEqual(game.fighters[0].energy, 100)
    }
    func testMirroredGrabClashIsSymmetric() {
        var game = DuelGame(hero: .liu, opponentHero: .liu)
        for _ in 0..<24 { game.step(.init(move: 1), opponent: .init(move: -1)) }
        game.step(.init(taps: .ultimate), opponent: .init(taps: .ultimate))
        var clash = false
        for _ in 0..<120 {
            game.step(.neutral, opponent: .neutral)
            clash = clash || game.events.contains(.grappleClash)
            XCTAssertNil(game.grapple)
        }
        XCTAssertTrue(clash)
        XCTAssertEqual(game.damageDealt, [0, 0])
        XCTAssertEqual(game.fighters[0].energy, game.fighters[1].energy)
    }
    func testBothDirectionsAndBothWallsRecoverWithoutCrossingOrLeavingArena() {
        for attacker in 0..<2 {
            for direction in [-1, 1] {
                var game = closeRange(attacker: attacker)
                for _ in 0..<170 { game.step(.init(move: direction), opponent: .init(move: direction)) }
                capture(&game, attacker: attacker)
                for _ in 0..<330 {
                    game.step(.neutral, opponent: .neutral)
                    XCTAssertLessThan(game.fighters[0].x, game.fighters[1].x)
                    for f in game.fighters { XCTAssertTrue((DuelGame.leftWall...DuelGame.rightWall).contains(f.x)) }
                }
                XCTAssertNil(game.grapple)
                XCTAssertEqual(game.damageDealt[attacker], 280)
                XCTAssertGreaterThanOrEqual(abs(game.fighters[0].x - game.fighters[1].x), DuelGame.bodyWidth)
            }
        }
    }
    func testLethalTakedownClearsCaptureAndNextRoundStartsClean() {
        var game = closeRange()
        var tick = 0
        while game.fighters[1].health > 100 && tick < 1800 {
            game.step(.init(move: 1, taps: tick % 32 == 0 ? .light : []), opponent: .neutral); tick += 1
        }
        XCTAssertEqual(game.fighters[1].health, 100)
        for _ in 0..<80 { game.step(.neutral, opponent: .neutral) }
        // Close the small gap introduced by prior hits.
        for _ in 0..<25 { game.step(.init(move: 1), opponent: .neutral) }
        capture(&game)
        for _ in 0..<24 { game.step(.neutral, opponent: .neutral) }
        XCTAssertNil(game.grapple)
        XCTAssertEqual(game.wins, [1, 0])
        XCTAssertEqual(game.damageDealt[0], 1000)
        for _ in 0..<120 { game.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(game.phase, .fighting)
        XCTAssertEqual(game.fighters.map(\.health), [1000, 1000])
        XCTAssertTrue(game.fighters.allSatisfy { $0.attack == nil && $0.stun == 0 && $0.knockdown == 0 })
    }
    func testGrabReplayIsIdenticalAtThirtySixtyAndOneHundredTwentyHz() {
        var expected: DuelGame?
        for rate in [30, 60, 120] {
            var game = closeRange(), clock = DuelClock(), tick = 0
            for _ in 0..<rate * 7 {
                for _ in 0..<clock.consume(seconds: 1 / Double(rate)) {
                    game.step(.init(taps: tick == 0 ? .ultimate : []), opponent: .neutral); tick += 1
                }
            }
            XCTAssertEqual(game.damageDealt[0], 280)
            if let expected { XCTAssertEqual(game, expected) } else { expected = game }
        }
    }
}
