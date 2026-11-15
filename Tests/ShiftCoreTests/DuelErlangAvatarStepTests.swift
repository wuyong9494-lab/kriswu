import XCTest
@testable import ShiftCore

final class DuelErlangAvatarStepTests: XCTestCase {
    private func setUpAvatar(_ game: inout DuelErlangSparring) {
        for _ in 0..<7 { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        game.step(erlangAction: .ascend)
    }

    private func cast(_ game: inout DuelErlangSparring, index: Int, damage: Int, blocked: Bool = false) {
        let previousHP = game.fighters[1].health
        game.step(erlangAction: .avatarStep)
        XCTAssertEqual(Array(game.events.prefix(1)), [.avatarStepStarted(chainIndex: index)])
        for _ in 0..<5 { game.step() }
        XCTAssertEqual(game.fighters[1].health, previousHP)
        game.step()
        XCTAssertEqual(game.events, [.contact(attacker: .erlang, strike: .avatarStep, damage: damage, blocked: blocked)])
        XCTAssertEqual(game.fighters[1].health, previousHP - damage)
        if !blocked { XCTAssertGreaterThan(game.fighters[1].knockdown, 0) }
        for _ in 0..<8 { game.step() }
        XCTAssertEqual(game.fighters[1].health, previousHP - damage)
    }

    func testThreeUsesEscalateOnlyThenStartCooldown() {
        var game = DuelErlangSparring()
        game.step(erlangAction: .avatarStep)
        XCTAssertEqual(game.events, [])
        setUpAvatar(&game)
        cast(&game, index: 1, damage: 21)
        XCTAssertEqual(game.avatarStepCooldown, 0)
        cast(&game, index: 2, damage: 27)
        XCTAssertEqual(game.avatarStepCooldown, 0)
        cast(&game, index: 3, damage: 35)
        XCTAssertGreaterThan(game.avatarStepCooldown, 0)
        game.step(erlangAction: .avatarStep)
        XCTAssertEqual(game.events, [])
        for _ in 0..<45 { game.step() }
        game.step(erlangAction: .avatarStep)
        XCTAssertEqual(game.avatarStepChain, 1)
    }

    func testExpiredWindowAndNewRaidRoundResetChain() {
        var game = DuelErlangSparring(mode: .teamRaid)
        setUpAvatar(&game)
        cast(&game, index: 1, damage: 21)
        for _ in 0..<32 { game.step() }
        XCTAssertEqual(game.avatarStepChain, 0)
        cast(&game, index: 1, damage: 21)
        game.resetRound()
        XCTAssertEqual(game.erlang.phase, .ascended)
        XCTAssertEqual(game.avatarStepChain, 0)
        XCTAssertEqual(game.avatarStepCooldown, 0)
    }

    func testGuardedStepDoesNotKnockDownInFixture() {
        var game = DuelErlangSparring()
        setUpAvatar(&game)
        game.step(partnerAction: .guardOn)
        cast(&game, index: 1, damage: 0, blocked: true)
        XCTAssertEqual(game.fighters[1].knockdown, 0)
    }
}
