import XCTest
@testable import ShiftCore

final class DuelErlangEarthPresentationTests: XCTestCase {
    private func ready(approach: Int = 0, stock: Bool = true) -> DuelErlangSparring {
        var game = DuelErlangSparring(mode: .teamRaid)
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        game.step(erlangAction: .ascend)
        if stock {
            game.step(erlangAction: .mountainSplitter)
            for _ in 0..<36 { game.step() }
        }
        for _ in 0..<approach { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        return game
    }

    private func impact(_ game: inout DuelErlangSparring, guardOn: Bool = false) {
        game.step(erlangAction: .earthshaker, partnerAction: guardOn ? .guardOn : nil)
        for _ in 0..<8 {
            XCTAssertNil(game.earthPresentation.impact)
            XCTAssertNil(game.earthPresentation.barrage)
            game.step()
        }
        XCTAssertNil(game.earthPresentation.impact)
        game.step()
    }

    func testIndependentAttachedEdgesWithNoDuplicateOnFollowingStep() {
        var game = ready(approach: 7)
        impact(&game)
        let view = game.earthPresentation
        XCTAssertEqual(view.age, 10)
        XCTAssertEqual(view.impact?.outcome, .landed)
        XCTAssertEqual(view.barrage?.landed, 2)
        XCTAssertEqual(view.impact?.contactX, view.barrage?.contactX)
        XCTAssertEqual((view.impact?.damage ?? -1) + (view.barrage?.damage ?? -1), 100 - game.fighters[1].health)
        game.step()
        XCTAssertNil(game.earthPresentation.impact)
        XCTAssertNil(game.earthPresentation.barrage)
        XCTAssertFalse(game.earthPresentation.visible)
    }

    func testGroundCanMissAndSwordsStillTouch() {
        var game = ready()
        impact(&game)
        let view = game.earthPresentation
        XCTAssertEqual(view.impact?.outcome, .missed)
        XCTAssertNil(view.impact?.contactX)
        XCTAssertNil(view.impact?.damage)
        XCTAssertEqual(view.barrage?.released, 2)
        XCTAssertEqual(view.barrage?.landed, 2)
        XCTAssertEqual(view.barrage?.damage, 6)
        XCTAssertEqual(game.fighters[1].health, 94)
    }

    func testReleaseCarriesNoContactIfOutOfBothRanges() {
        var game = ready()
        for _ in 0..<6 { game.step(erlangAction: .walk(-1), partnerAction: .walk(1)) }
        impact(&game)
        XCTAssertEqual(game.earthPresentation.impact?.outcome, .missed)
        XCTAssertEqual(game.earthPresentation.barrage?.released, 2)
        XCTAssertEqual(game.earthPresentation.barrage?.landed, 0)
        XCTAssertNil(game.earthPresentation.barrage?.contactX)
        XCTAssertEqual(game.fighters[1].health, 100)
    }

    func testBaseAndGuardDoNotInventSwordDamage() {
        var base = ready(approach: 7, stock: false)
        impact(&base)
        XCTAssertEqual(base.earthPresentation.consumed, 0)
        XCTAssertEqual(base.earthPresentation.impact?.outcome, .landed)
        XCTAssertNil(base.earthPresentation.barrage)

        var protected = ready(approach: 7)
        impact(&protected, guardOn: true)
        XCTAssertEqual(protected.earthPresentation.impact?.outcome, .blocked)
        XCTAssertEqual(protected.earthPresentation.barrage?.blocked, 2)
        XCTAssertEqual(protected.earthPresentation.barrage?.damage, 0)
        XCTAssertEqual(protected.fighters[1].health, 100)
    }

    func testInterruptBeforeImpactAndResetClearPendingPresentation() {
        var game = ready(approach: 10)
        game.step(erlangAction: .earthshaker, partnerAction: .spear)
        let id = game.earthPresentation.castID
        XCTAssertEqual(game.earthPresentation.consumed, 2)
        for _ in 0..<25 {
            game.step()
            XCTAssertNil(game.earthPresentation.impact)
            XCTAssertNil(game.earthPresentation.barrage)
        }
        XCTAssertEqual(game.earthPresentation.outcome, .cancelled)
        XCTAssertFalse(game.earthPresentation.visible)
        game.resetRound()
        XCTAssertEqual(game.earthPresentation.outcome, .reset)
        XCTAssertEqual(game.earthPresentation.consumed, 0)
        game.step(erlangAction: .earthshaker)
        XCTAssertEqual(game.earthPresentation.castID, id + 1)
        game.resetRound() // while the new spear is still winding up
        for _ in 0..<18 {
            game.step()
            XCTAssertNil(game.earthPresentation.impact)
            XCTAssertNil(game.earthPresentation.barrage)
        }
    }
}
