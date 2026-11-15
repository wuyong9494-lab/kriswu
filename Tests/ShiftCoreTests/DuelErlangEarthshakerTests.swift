import XCTest
@testable import ShiftCore

final class DuelErlangEarthshakerTests: XCTestCase {
    private func setUpAvatar(_ game: inout DuelErlangSparring, approach: Int) {
        for _ in 0..<approach { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        game.step(erlangAction: .ascend)
    }
    private func execute(_ game: inout DuelErlangSparring, partnerAction: DuelErlangSparring.Action? = nil) {
        game.step(erlangAction: .earthshaker, partnerAction: partnerAction)
        XCTAssertEqual(Array(game.events.prefix(1)), [.earthshakerStarted])
        for _ in 0..<8 { game.step() }
        XCTAssertEqual(game.fighters[1].health, 100)
        game.step()
    }
    func testGoldenGateAndWhiffStillCausesGroundImpact() {
        var game = DuelErlangSparring()
        game.step(erlangAction: .earthshaker)
        XCTAssertEqual(game.events, [])
        setUpAvatar(&game, approach: 0)
        execute(&game)
        XCTAssertEqual(game.events, [.earthshakerGroundImpact])
        XCTAssertEqual(game.fighters[1].health, 100)
        XCTAssertFalse(game.hasPendingQuake)
    }
    func testDistanceFalloffAndKnockdownOnce() {
        for (approach, damage) in [(10, 21), (7, 12), (3, 1)] {
            var game = DuelErlangSparring()
            setUpAvatar(&game, approach: approach)
            execute(&game)
            XCTAssertEqual(game.events, [.earthshakerGroundImpact,
                .contact(attacker: .erlang, strike: .earthshaker, damage: damage, blocked: false)])
            XCTAssertEqual(game.fighters[1].health, 100 - damage)
            XCTAssertGreaterThan(game.fighters[1].knockdown, 0)
            for _ in 0..<25 { game.step() }
            XCTAssertEqual(game.fighters[1].health, 100 - damage)
            XCTAssertFalse(game.hasPendingQuake)
            game.step(erlangAction: .earthshaker)
            XCTAssertEqual(game.events, [])
        }
    }
    func testFixtureGuardAndInterruption() {
        var game = DuelErlangSparring()
        setUpAvatar(&game, approach: 7)
        execute(&game, partnerAction: .guardOn)
        XCTAssertEqual(game.events, [.earthshakerGroundImpact,
            .contact(attacker: .erlang, strike: .earthshaker, damage: 0, blocked: true)])
        XCTAssertEqual(game.fighters[1].health, 100)
        XCTAssertEqual(game.fighters[1].knockdown, 0)

        game = DuelErlangSparring()
        setUpAvatar(&game, approach: 10)
        game.step(erlangAction: .earthshaker, partnerAction: .spear)
        var observed = [DuelErlangSparring.Event]()
        for _ in 0..<15 { game.step(); observed += game.events }
        XCTAssertFalse(observed.contains(.earthshakerGroundImpact))
        XCTAssertEqual(game.fighters[0].health, 90)
        XCTAssertEqual(game.fighters[1].health, 100)
    }
}
