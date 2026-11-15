import XCTest
@testable import ShiftCore

final class DuelErlangL6PassiveTests: XCTestCase {
    private func takeHits(_ count: Int, game: inout DuelErlangSparring) {
        for _ in 0..<count {
            for _ in 0..<20 { game.step(partnerAction: .walk(-1)) }
            game.step(partnerAction: .spear)
            for _ in 0..<4 { game.step() }
        }
    }

    private func ascend(_ game: inout DuelErlangSparring) {
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        game.step(erlangAction: .ascend)
    }

    func testDivineArsenalFillsOnAcceptedEntryNotRejectedInputOrRepeat() {
        var game = DuelErlangSparring(enableLevelSixPassives: true)
        game.step(erlangAction: .ascend)
        XCTAssertTrue(game.events.isEmpty)
        XCTAssertEqual(game.lightSwords.active, 0)
        ascend(&game)
        XCTAssertEqual(game.events, [.cue(.ascension), .lightSwords(.summoned(count: 6))])
        XCTAssertEqual(game.lightSwords.active, 6)
        game.step(erlangAction: .lightSwords)
        game.step(erlangAction: .ascend)
        XCTAssertEqual(game.lightSwords.active, 0)
        XCTAssertEqual(game.lightSwords.pending, 6)
        XCTAssertTrue(game.events.isEmpty)
    }

    func testLethalHitExitsAvatarAndCancelsPendingSwordLaunchBeforeKO() {
        var game = DuelErlangSparring(enableLevelSixPassives: true)
        takeHits(9, game: &game)
        XCTAssertEqual(game.fighters[0].health, 10)
        ascend(&game)
        for _ in 0..<20 { game.step(partnerAction: .walk(-1)) }
        game.step(erlangAction: .lightSwords, partnerAction: .spear)
        XCTAssertEqual(game.lightSwords.pending, 6)
        for _ in 0..<3 { game.step() }
        XCTAssertTrue(game.events.contains(.heavensProtection(restoredHealth: 30)))
        XCTAssertFalse(game.events.contains(.defeated(.erlang)))
        XCTAssertNil(game.winner)
        XCTAssertEqual(game.fighters[0].health, 30)
        XCTAssertEqual(game.erlang.phase, .base)
        XCTAssertEqual(game.erlang.light, 0)
        XCTAssertEqual(game.lightSwords.pending, 0)
        for _ in 0..<16 {
            game.step()
            XCTAssertFalse(game.events.contains(.lightSwords(.launchReleased(count: 6))))
        }
        XCTAssertEqual(game.fighters[1].health, 100)

        // Not an unconditional extra life: once outside Avatar the next KO sticks.
        takeHits(3, game: &game)
        XCTAssertEqual(game.winner, .sparringPartner)
        XCTAssertEqual(game.fighters[0].health, 0)
    }

    func testProtectionDuringWrathEndsItAndRoundResetDoesNotLeakOrRestore() {
        var game = DuelErlangSparring(mode: .teamRaid, enableLevelSixPassives: true)
        takeHits(9, game: &game)
        ascend(&game)
        game.step(erlangAction: .finalJudgement)
        for _ in 0..<25 { game.step() }
        XCTAssertGreaterThan(game.wrathTicks, 0)
        takeHits(1, game: &game)
        XCTAssertEqual(game.wrathTicks, 0)
        XCTAssertEqual(game.erlang.phase, .base)
        XCTAssertEqual(game.fighters[0].health, 30)
        XCTAssertEqual(game.lightSwords.active, 0)
        game.resetRound()
        XCTAssertEqual(game.wrathTicks, 0)
        XCTAssertEqual(game.erlang.phase, .base)
        XCTAssertEqual(game.fighters[0].health, 100)
        XCTAssertTrue(game.events.isEmpty)
    }
    func testQualifiedIncomingHitsDamageButDoNotInterruptAvatarCast() {
        let cases: [(DuelErlangSparring.Action, DuelErlangSparring.Strike, Bool, Bool)] = [
            (.partnerShadow, .partnerShadow, true, true),
            (.partnerSetAbility, .partnerSetAbility, true, true),
            (.spear, .partner, true, false),
            (.partnerShadow, .partnerShadow, false, false)
        ]
        for (action, strike, passive, preservesCast) in cases {
            var game = DuelErlangSparring(enableLevelSixPassives: passive)
            ascend(&game)
            for _ in 0..<20 { game.step(partnerAction: .walk(-1)) }
            game.step(erlangAction: .avatarEye, partnerAction: action)
            for _ in 0..<3 { game.step() }
            XCTAssertEqual(game.fighters[0].health, 90)
            XCTAssertEqual(game.events.contains(.contact(attacker: .sparringPartner, strike: strike, damage: 10, blocked: false)), true)
            XCTAssertEqual(game.events.contains(.interruptionPrevented(strike: strike)), preservesCast)
            XCTAssertEqual(game.fighters[0].stun == 0, preservesCast)
            for _ in 0..<3 { game.step() }
            XCTAssertEqual(game.fighters[1].health < 100, preservesCast)
        }
    }

    func testQualifiedHitInBaseStillInterruptsAndLethalHitInAvatarStillEndsForm() {
        var game = DuelErlangSparring(enableLevelSixPassives: true)
        for _ in 0..<30 { game.step(partnerAction: .walk(-1)) }
        game.step(erlangAction: .meditate, partnerAction: .partnerShadow)
        for _ in 0..<3 { game.step() }
        XCTAssertTrue(game.events.contains(.cue(.meditationInterrupted)))
        XCTAssertFalse(game.events.contains(.interruptionPrevented(strike: .partnerShadow)))
        XCTAssertEqual(game.fighters[0].health, 90)

        game.resetRound()
        takeHits(9, game: &game)
        ascend(&game)
        for _ in 0..<20 { game.step(partnerAction: .walk(-1)) }
        game.step(erlangAction: .avatarEye, partnerAction: .partnerSetAbility)
        for _ in 0..<3 { game.step() }
        XCTAssertTrue(game.events.contains(.heavensProtection(restoredHealth: 30)))
        XCTAssertEqual(game.erlang.phase, .base)
        for _ in 0..<4 { game.step() }
        XCTAssertEqual(game.fighters[1].health, 100, "Leaving Avatar on lethal damage cancels the old cast")
    }

}
