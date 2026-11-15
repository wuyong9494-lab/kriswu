import XCTest
@testable import ShiftCore

final class DuelErlangMountainSplitterTests: XCTestCase {
    private func setUpAvatar(_ game: inout DuelErlangSparring, approach: Int) {
        for _ in 0..<approach { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        game.step(erlangAction: .ascend)
    }

    func testEnhancedAxeAndDelayedQuakeAreSeparateOnceOnlyHits() {
        var game = DuelErlangSparring()
        game.step(erlangAction: .mountainSplitter)
        XCTAssertEqual(game.events, [])
        setUpAvatar(&game, approach: 7)
        game.step(erlangAction: .mountainSplitter)
        XCTAssertEqual(Array(game.events.prefix(1)), [.mountainSplitterStarted])
        for _ in 0..<10 { game.step() }
        XCTAssertEqual(game.fighters[1].health, 100)
        game.step()
        XCTAssertEqual(game.events, [.contact(attacker: .erlang, strike: .mountainSplitter, damage: 24, blocked: false), .quakeScheduled])
        XCTAssertTrue(game.hasPendingQuake)
        for _ in 0..<23 { game.step() }
        XCTAssertEqual(game.fighters[1].health, 76)
        game.step()
        XCTAssertEqual(game.events, [.quakeTriggered, .contact(attacker: .erlang, strike: .mountainQuake, damage: 36, blocked: false)])
        XCTAssertEqual(game.fighters[1].health, 40)
        XCTAssertGreaterThan(game.fighters[1].knockdown, 0)
        for _ in 0..<30 { game.step() }
        XCTAssertEqual(game.fighters[1].health, 40)
    }

    func testBaseAxeDoesNotProduceEnhancedQuake() {
        var game = DuelErlangSparring(enhancedMountainSplitter: false)
        setUpAvatar(&game, approach: 7)
        game.step(erlangAction: .mountainSplitter)
        for _ in 0..<50 { game.step() }
        XCTAssertEqual(game.fighters[1].health, 76)
        XCTAssertFalse(game.hasPendingQuake)
    }

    func testWhiffAndGuardDoNotScheduleQuakeInFixture() {
        for protected in [false, true] {
            var game = DuelErlangSparring()
            setUpAvatar(&game, approach: protected ? 7 : 0)
            game.step(erlangAction: .mountainSplitter, partnerAction: protected ? .guardOn : nil)
            for _ in 0..<45 { game.step() }
            XCTAssertEqual(game.fighters[1].health, 100)
            XCTAssertFalse(game.hasPendingQuake)
        }
    }

    func testInterruptBeforeAxeContactAndRoundResetClearDelayedEffects() {
        var game = DuelErlangSparring(mode: .teamRaid)
        setUpAvatar(&game, approach: 10)
        game.step(erlangAction: .mountainSplitter, partnerAction: .spear)
        for _ in 0..<15 { game.step() }
        XCTAssertEqual(game.fighters[0].health, 90)
        XCTAssertEqual(game.fighters[1].health, 100)
        XCTAssertFalse(game.hasPendingQuake)

        for _ in 0..<65 { game.step() }
        game.step(erlangAction: .mountainSplitter)
        for _ in 0..<11 { game.step() }
        XCTAssertTrue(game.hasPendingQuake)
        game.resetRound()
        XCTAssertEqual(game.erlang.phase, .ascended)
        XCTAssertFalse(game.hasPendingQuake)
        for _ in 0..<50 { game.step() }
        XCTAssertEqual(game.fighters[1].health, 100)
    }

    func testOpponentCanMoveOutOfFixedQuakeArea() {
        var game = DuelErlangSparring()
        setUpAvatar(&game, approach: 10)
        game.step(erlangAction: .mountainSplitter)
        for _ in 0..<11 { game.step() }
        for _ in 0..<24 { game.step(partnerAction: .walk(1)) }
        XCTAssertEqual(game.events, [.quakeTriggered])
        XCTAssertEqual(game.fighters[1].health, 76)
    }
}
