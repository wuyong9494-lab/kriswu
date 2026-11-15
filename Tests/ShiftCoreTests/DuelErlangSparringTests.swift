import XCTest
@testable import ShiftCore

final class DuelErlangSparringTests: XCTestCase {
    private func approach(_ distanceSteps: Int, _ game: inout DuelErlangSparring) {
        for _ in 0..<distanceSteps { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
    }

    func testSpearWhiffAndHitWindowAwardsLightOnlyOnce() {
        var game = DuelErlangSparring()
        game.step(erlangAction: .spear)
        for _ in 0..<20 { game.step() }
        XCTAssertEqual(game.fighters[1].health, 100)
        XCTAssertEqual(game.erlang.light, 0)
        approach(7, &game)
        let before = game.fighters[1].position
        game.step(erlangAction: .spear)
        for _ in 0..<3 { game.step() }
        XCTAssertEqual(game.fighters[1].health, 100)
        game.step()
        XCTAssertEqual(game.events, [.contact(attacker: .erlang, strike: .spear, damage: 12, blocked: false)])
        XCTAssertEqual(game.fighters[1].position - before, 18)
        for _ in 0..<8 { game.step() }
        XCTAssertEqual(game.fighters[1].health, 88)
        XCTAssertEqual(game.erlang.light, 5)
    }

    func testGuardPreventsDamageAndConfirmedHitCharge() {
        var game = DuelErlangSparring()
        approach(7, &game)
        game.step(erlangAction: .spear, partnerAction: .guardOn)
        for _ in 0..<4 { game.step() }
        XCTAssertEqual(game.events, [.contact(attacker: .erlang, strike: .spear, damage: 0, blocked: true)])
        XCTAssertEqual(game.fighters[1].health, 100)
        XCTAssertEqual(game.erlang.light, 0)
    }

    func testPartnerHitCancelsMeditation() {
        var game = DuelErlangSparring()
        approach(10, &game)
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate, partnerAction: .spear)
        for _ in 0..<3 { game.step() }
        XCTAssertTrue(game.events.contains(.cue(.meditationInterrupted)))
        XCTAssertEqual(game.erlang.phase, .base)
        XCTAssertEqual(game.fighters[0].health, 90)
    }

    func testHoundSweepsBeforeContactAndNoImmediateRecast() {
        var game = DuelErlangSparring()
        approach(5, &game)
        game.step(erlangAction: .hound)
        XCTAssertEqual(game.events, [.cue(.houndRush)])
        for _ in 0..<10 { game.step() }
        XCTAssertEqual(game.fighters[1].health, 100)
        game.step()
        XCTAssertEqual(game.events, [.contact(attacker: .erlang, strike: .hound, damage: 15, blocked: false), .houndWeakness(target: .sparringPartner)])
        XCTAssertGreaterThan(game.fighters[1].knockdown, 0)
        XCTAssertGreaterThan(game.fighters[1].weakness, 0)
        for _ in 0..<40 { game.step() }
        game.step(erlangAction: .hound, partnerAction: .guardOn)
        XCTAssertEqual(game.events, [])
        XCTAssertFalse(game.fighters[1].guarding)
        XCTAssertEqual(game.fighters[1].knockdown, 0)
        for _ in 0..<20 { game.step() }
        game.step(partnerAction: .guardOn)
        XCTAssertTrue(game.fighters[1].guarding)
    }

    func testAscensionAtFullLightAndRoundBoundaryScopedByMode() {
        for mode in [DuelErlangState.Mode.versus, .teamRaid] {
            var game = DuelErlangSparring(mode: mode)
            game.step(erlangAction: .ascend)
            XCTAssertEqual(game.erlang.phase, .base)
            for _ in 0..<30 { game.step() }
            game.step(erlangAction: .meditate)
            for _ in 0..<(34 * 12) { game.step() }
            XCTAssertEqual(game.erlang.light, 100)
            game.step(erlangAction: .ascend)
            XCTAssertEqual(game.events, [.cue(.ascension)])
            game.step(erlangAction: .guardOn)
            XCTAssertFalse(game.fighters[0].guarding)
            game.step(erlangAction: .meditate)
            XCTAssertEqual(game.erlang.phase, .ascended)
            game.step(erlangAction: .hound)
            XCTAssertEqual(game.events, [])
            game.resetRound()
            XCTAssertEqual(game.erlang.phase, mode == .teamRaid ? .ascended : .base)
        }
    }

    func testHoundBlockedDoesNotApplyWeaknessOrKnockdown() {
        var game = DuelErlangSparring()
        approach(5, &game)
        game.step(erlangAction: .hound, partnerAction: .guardOn)
        for _ in 0..<11 { game.step() }
        XCTAssertEqual(game.events, [.contact(attacker: .erlang, strike: .hound, damage: 0, blocked: true)])
        XCTAssertEqual(game.fighters[1].weakness, 0)
        XCTAssertEqual(game.fighters[1].knockdown, 0)
    }

    func testRunIsDeterministicAndCanEndWithKO() {
        func run() -> DuelErlangSparring {
            var game = DuelErlangSparring()
            for _ in 0..<50 {
                for _ in 0..<12 { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
                game.step(erlangAction: .spear)
                for _ in 0..<20 { game.step() }
            }
            return game
        }
        var result = run()
        XCTAssertEqual(result, run())
        XCTAssertEqual(result.winner, .erlang)
        XCTAssertEqual(result.fighters[1].health, 0)
        let finalTick = result.tick
        result.step()
        XCTAssertEqual(result.tick, finalTick)
    }
}
