import XCTest
@testable import ShiftCore

final class DuelErlangSwordRetributionTests: XCTestCase {
    func testThresholdUsesOnlyActualDamageInsideWindow() {
        var state = DuelErlangLightSwords()
        for _ in 0..<3 { XCTAssertNil(state.recordSwordContact(.landed)) }
        XCTAssertNil(state.recordSwordContact(.blocked))
        XCTAssertNil(state.recordSwordContact(.missed))
        XCTAssertEqual(state.retributionHits, 0)
        XCTAssertEqual(state.recordSwordContact(.landed), .retribution(hits: 4))
        XCTAssertEqual(state.retributionPercent(), 20)
        XCTAssertEqual(state.recordSwordContact(.landed), .retribution(hits: 5))
        XCTAssertEqual(state.retributionPercent(), 25)
        for _ in 0..<36 { _ = state.step() }
        XCTAssertEqual(state.retributionPercent(), 0)
    }

    func testExpiredHitsCannotQualifyAndRoundClearsBonus() {
        var state = DuelErlangLightSwords()
        for _ in 0..<3 { state.recordSwordContact(.landed) }
        for _ in 0..<20 { _ = state.step() }
        XCTAssertNil(state.recordSwordContact(.landed))
        XCTAssertEqual(state.retributionHits, 0)
        for _ in 0..<3 { state.recordSwordContact(.landed) }
        XCTAssertEqual(state.retributionHits, 4)
        state.clearRound()
        XCTAssertEqual(state.retributionHits, 0)
        XCTAssertNil(state.recordSwordContact(.landed))
    }

    private func matchAfterFourSwords(enable: Bool, guarded: Bool) -> DuelErlangSparring {
        var game = DuelErlangSparring(enableSwordRetribution: enable)
        for _ in 0..<2 { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        game.step(erlangAction: .ascend)
        game.step(erlangAction: .earthshaker)
        for _ in 0..<25 { game.step() }
        game.step(erlangAction: .avatarStep)
        for _ in 0..<26 { game.step() }
        game.step(erlangAction: .lightSwords, partnerAction: guarded ? .guardOn : nil)
        for _ in 0..<14 { game.step() }
        return game
    }

    func testFourRealContactsBoostSubsequentAvatarMoveButNotTheVolley() {
        for enable in [false, true] {
            var game = matchAfterFourSwords(enable: enable, guarded: false)
            let initial = game.fighters[1].health
            XCTAssertEqual(initial, 63) // 21 step + 4×4 sword contacts.
            XCTAssertEqual(game.lightSwords.retributionHits, enable ? 4 : 0)
            game.step(erlangAction: .avatarStep)
            for _ in 0..<6 { game.step() }
            XCTAssertEqual(initial - game.fighters[1].health, enable ? 25 : 21)
        }
    }

    func testGuardedVolleyCannotGrantRetributionOrDamage() {
        let game = matchAfterFourSwords(enable: true, guarded: true)
        XCTAssertEqual(game.fighters[1].health, 79)
        XCTAssertEqual(game.lightSwords.retributionHits, 0)
    }
}
