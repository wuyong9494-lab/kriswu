import XCTest
@testable import ShiftCore

final class DuelErlangFinalJudgementTests: XCTestCase {
    private func charged(approach: Int = 0, mode: DuelErlangState.Mode = .versus,
                         ascend: Bool = true) -> DuelErlangSparring {
        var game = DuelErlangSparring(mode: mode, enableSwordRetribution: false)
        for _ in 0..<approach { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        if ascend { game.step(erlangAction: .ascend) }
        return game
    }

    func testGoldenAndFullGateAndEmptyStockSupported() {
        var game = charged(ascend: false)
        game.step(erlangAction: .finalJudgement)
        XCTAssertTrue(game.events.isEmpty)
        XCTAssertEqual(game.erlang.light, 100)
        game.step(erlangAction: .ascend)
        game.step(erlangAction: .finalJudgement)
        XCTAssertEqual(game.events, [.finalJudgementStarted(consumedSwords: 0)])
        XCTAssertEqual(game.wrathTicks, 0)
        XCTAssertEqual(game.fighters[1].health, 100)
        for _ in 0..<10 { game.step(); XCTAssertTrue(game.events.isEmpty) }
        game.step()
        XCTAssertEqual(game.events.prefix(2), [.finalJudgementReleased, .wrathStarted])
        XCTAssertEqual(game.fighters[1].health, 76)
    }

    func testStockPenetratesFixtureGuardAndRefreshesSkillCooldowns() {
        var game = charged()
        game.step(erlangAction: .mountainSplitter)
        for _ in 0..<30 { game.step() }
        XCTAssertGreaterThan(game.mountainSplitterCooldown, 0)
        game.step(erlangAction: .finalJudgement, partnerAction: .guardOn)
        XCTAssertEqual(game.events, [.finalJudgementStarted(consumedSwords: 2)])
        XCTAssertEqual(game.lightSwords.active, 0)
        for _ in 0..<11 { game.step() }
        XCTAssertTrue(game.events.contains(.contact(attacker: .erlang, strike: .finalJudgement, damage: 5, blocked: true)))
        XCTAssertEqual(game.fighters[1].health, 95)
        XCTAssertEqual(game.mountainSplitterCooldown, 0)
        XCTAssertEqual(game.lightSwords.active, 6)
    }

    func testWhiffStillEntersWrathAndLaterMovesRegainLightAndUseCriticalAndShorterCooldown() {
        var game = charged()
        game.step(erlangAction: .walk(-1), partnerAction: .walk(1))
        game.step(erlangAction: .walk(-1), partnerAction: .walk(1))
        game.step(erlangAction: .finalJudgement)
        for _ in 0..<11 { game.step() }
        XCTAssertTrue(game.events.contains(.wrathStarted))
        XCTAssertEqual(game.fighters[1].health, 100)
        for _ in 0..<10 { game.step() }
        game.step(erlangAction: .lightSwords)
        XCTAssertEqual(game.lightSwords.rangedCooldown, 22)
        for _ in 0..<8 { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        game.step(erlangAction: .avatarEye)
        XCTAssertEqual(game.erlang.light, 25)
        XCTAssertEqual(game.avatarEyeCooldown, 31)
        for _ in 0..<6 { game.step() }
        XCTAssertTrue(game.events.contains(.contact(attacker: .erlang, strike: .avatarEye, damage: 9, blocked: false)))
        XCTAssertEqual(game.lightSwords.active, 2)
        while game.wrathTicks > 68 { game.step() }
        XCTAssertEqual(game.lightSwords.active, 6)
        while game.wrathTicks > 0 { game.step() }
        XCTAssertTrue(game.events.contains(.wrathEnded))
        XCTAssertEqual(game.erlang.light, 0)
        game.step(erlangAction: .finalJudgement)
        XCTAssertTrue(game.events.isEmpty)
    }

    func testInterruptedWindupDoesNotReleaseOrEnterWrath() {
        var game = charged(approach: 10)
        game.step(erlangAction: .finalJudgement, partnerAction: .spear)
        var observed: [DuelErlangSparring.Event] = []
        for _ in 0..<20 { game.step(); observed += game.events }
        XCTAssertFalse(observed.contains(.finalJudgementReleased))
        XCTAssertFalse(observed.contains(.wrathStarted))
        XCTAssertEqual(game.erlang.light, 100)
        XCTAssertEqual(game.wrathTicks, 0)
    }

    func testRoundResetAndTerminalEndClearWrath() {
        var game = charged(approach: 10, mode: .teamRaid)
        game.step(erlangAction: .finalJudgement)
        for _ in 0..<22 { game.step() }
        game.step(erlangAction: .mountainSplitter)
        XCTAssertEqual(game.erlang.light, 25)
        game.resetRound()
        XCTAssertEqual(game.erlang.phase, .ascended) // raid existing form carry
        XCTAssertEqual(game.erlang.light, 0)
        XCTAssertEqual(game.wrathTicks, 0)
        XCTAssertEqual(game.lightSwords.active, 0)

        game = charged(approach: 10)
        game.step(erlangAction: .finalJudgement)
        for _ in 0..<22 { game.step() }
        game.step(erlangAction: .earthshaker)
        for _ in 0..<23 { game.step() }
        game.step(erlangAction: .mountainSplitter)
        for _ in 0..<13 where game.winner == nil { game.step() }
        XCTAssertEqual(game.winner, .erlang)
        XCTAssertTrue(game.events.contains(.wrathEnded))
        XCTAssertEqual(game.wrathTicks, 0)
        XCTAssertEqual(game.erlang.light, 0)
        XCTAssertEqual(game.lightSwords.active, 0)
    }
}
