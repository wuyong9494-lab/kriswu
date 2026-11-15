import XCTest
@testable import ShiftCore

final class DuelErlangEarthshakerBarrageTests: XCTestCase {
    private func withStock(enhanced: Bool = true) -> DuelErlangSparring {
        var game = DuelErlangSparring(enhancedEarthshaker: enhanced)
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        game.step(erlangAction: .ascend)
        game.step(erlangAction: .mountainSplitter)
        for _ in 0..<35 { game.step() }
        XCTAssertEqual(game.lightSwords.active, 2)
        XCTAssertEqual(game.fighters[1].health, 100)
        return game
    }

    func testBarrageSpendsExistingStockAndReleasesExactlyOnceEvenIfGroundWhiffs() {
        var game = withStock()
        game.step(erlangAction: .earthshaker)
        XCTAssertEqual(game.events, [.earthshakerStarted, .lightSwords(.earthshakerConsumed(count: 2)),
            .lightSwords(.summoned(count: 2))])
        XCTAssertEqual(game.lightSwords.active, 2) // new activation grant, not double spending
        for _ in 0..<8 { game.step(); XCTAssertTrue(game.events.isEmpty) }
        game.step()
        XCTAssertEqual(game.events, [.earthshakerGroundImpact, .lightSwords(.earthshakerBarrageReleased(count: 2)),
            .contact(attacker: .erlang, strike: .earthshakerBarrage, damage: 3, blocked: false),
            .contact(attacker: .erlang, strike: .earthshakerBarrage, damage: 3, blocked: false)])
        game.step()
        XCTAssertTrue(game.events.isEmpty)
        XCTAssertEqual(game.fighters[1].health, 94)
    }

    func testQueuedManualSwordsReservedAgainstEarthshaker() {
        var game = withStock()
        game.step(erlangAction: .lightSwords)
        XCTAssertEqual(game.events, [.lightSwords(.launchQueued(count: 2))])
        game.step(erlangAction: .earthshaker)
        XCTAssertFalse(game.events.contains(.lightSwords(.earthshakerConsumed(count: 2))))
        var history: [DuelErlangSparring.Event] = []
        for _ in 0..<20 { game.step(); history += game.events }
        XCTAssertTrue(history.contains(.earthshakerGroundImpact))
        XCTAssertTrue(history.contains(.lightSwords(.launchReleased(count: 2))))
        XCTAssertFalse(history.contains(.lightSwords(.earthshakerBarrageReleased(count: 2))))
        XCTAssertEqual(game.lightSwords.active, 2)
        XCTAssertEqual(game.lightSwords.pending, 0)
    }

    func testEnhancementCanDisableAndResetCancelsBarrage() {
        var baseline = withStock(enhanced: false)
        baseline.step(erlangAction: .earthshaker)
        for _ in 0..<9 { baseline.step() }
        XCTAssertEqual(baseline.events, [.earthshakerGroundImpact])
        XCTAssertEqual(baseline.lightSwords.active, 4)
        var game = withStock()
        game.step(erlangAction: .earthshaker)
        game.resetRound()
        for _ in 0..<14 { game.step(); XCTAssertTrue(game.events.isEmpty) }
        XCTAssertEqual(game.lightSwords.active, 0)
    }

    func testGuardBlocksBarrage() {
        var game = withStock()
        game.step(erlangAction: .earthshaker, partnerAction: .guardOn)
        for _ in 0..<9 { game.step() }
        XCTAssertEqual(game.events.filter { $0 == .contact(attacker: .erlang, strike: .earthshakerBarrage, damage: 0, blocked: true) }.count, 2)
        XCTAssertEqual(game.fighters[1].health, 100)
        XCTAssertEqual(game.lightSwords.retributionHits, 0)
    }
}
