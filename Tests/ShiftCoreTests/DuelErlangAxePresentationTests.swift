import XCTest
@testable import ShiftCore

final class DuelErlangAxePresentationTests: XCTestCase {
    private func ready(_ approach: Int, enhanced: Bool = true, mode: DuelErlangState.Mode = .versus) -> DuelErlangSparring {
        var game = DuelErlangSparring(mode: mode, enhancedMountainSplitter: enhanced)
        for _ in 0..<approach { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        game.step(erlangAction: .ascend)
        return game
    }

    func testImpactAndQuakeAreIndependentEdgesFromAdjudication() throws {
        var game = ready(7)
        game.step(erlangAction: .mountainSplitter)
        for _ in 0..<10 { game.step() }
        XCTAssertNil(game.axePresentation.pendingQuake)
        let before = game.fighters[1].position
        game.step()
        let swing = game.axePresentation
        XCTAssertEqual(swing.contact, .landed)
        XCTAssertEqual(swing.contactX, before)
        XCTAssertEqual(swing.damage, 24)
        XCTAssertNil(swing.quake)
        let schedule = try XCTUnwrap(swing.pendingQuake)
        XCTAssertEqual(schedule.originX, game.fighters[1].position)
        XCTAssertEqual(schedule.dueTick, game.tick + 24)
        for _ in 0..<23 {
            game.step()
            XCTAssertEqual(game.axePresentation.pendingQuake, schedule)
            XCTAssertNil(game.axePresentation.contact)
            XCTAssertNil(game.axePresentation.quake)
        }
        XCTAssertFalse(game.axePresentation.visible)
        game.step()
        XCTAssertNil(game.axePresentation.pendingQuake)
        XCTAssertEqual(game.axePresentation.quake?.outcome, .landed)
        XCTAssertEqual(game.axePresentation.quake?.contactX, schedule.originX)
        XCTAssertEqual(game.axePresentation.quake?.damage, 36)
        game.step()
        XCTAssertNil(game.axePresentation.quake)
        XCTAssertEqual(game.fighters[1].health, 40)
    }

    func testBlockedMissedAndBaseSwingNeverGenerateQuake() {
        for (distance, enhanced, guardOn, result) in [
            (7, true, true, DuelErlangAxePresentation.Outcome.blocked),
            (1, true, false, .missed),
            (7, false, false, .landed)
        ] {
            var game = ready(distance, enhanced: enhanced)
            game.step(erlangAction: .mountainSplitter, partnerAction: guardOn ? .guardOn : nil)
            for _ in 0..<40 {
                game.step()
                XCTAssertNil(game.axePresentation.pendingQuake)
                XCTAssertNil(game.axePresentation.quake)
            }
            XCTAssertEqual(game.axePresentation.outcome, result)
        }
    }

    func testFixedQuakeStillFiresAfterEscapeButDoesNotTouchTarget() throws {
        var game = ready(10)
        game.step(erlangAction: .mountainSplitter)
        for _ in 0..<11 { game.step() }
        let schedule = try XCTUnwrap(game.axePresentation.pendingQuake)
        for _ in 0..<24 { game.step(partnerAction: .walk(1)) }
        let quake = try XCTUnwrap(game.axePresentation.quake)
        XCTAssertEqual(quake.originX, schedule.originX)
        XCTAssertEqual(quake.dueTick, game.tick)
        XCTAssertEqual(quake.outcome, .missed)
        XCTAssertNil(quake.contactX)
        XCTAssertNil(quake.damage)
        XCTAssertEqual(game.fighters[1].health, 76)
    }

    func testDefenderCanRecoverAndGuardSecondaryEvenIfAxeLanded() {
        var game = ready(7)
        game.step(erlangAction: .mountainSplitter)
        for _ in 0..<11 { game.step() }
        for _ in 0..<24 { game.step(partnerAction: .guardOn) }
        XCTAssertEqual(game.axePresentation.quake?.outcome, .blocked)
        XCTAssertEqual(game.axePresentation.quake?.damage, 0)
        XCTAssertEqual(game.fighters[1].health, 76)
    }

    func testInterruptAndRoundResetDoNotLeakEffects() {
        var game = ready(10, mode: .teamRaid)
        game.step(erlangAction: .mountainSplitter, partnerAction: .spear)
        for _ in 0..<5 { game.step() }
        XCTAssertEqual(game.axePresentation.outcome, .cancelled)
        XCTAssertFalse(game.axePresentation.visible)
        XCTAssertNil(game.axePresentation.contact)
        XCTAssertNil(game.axePresentation.pendingQuake)
        for _ in 0..<65 { game.step() }
        game.step(erlangAction: .mountainSplitter)
        for _ in 0..<13 { game.step() }
        let castID = game.axePresentation.castID
        XCTAssertNotNil(game.axePresentation.pendingQuake)
        game.resetRound()
        XCTAssertEqual(game.axePresentation.outcome, .reset)
        XCTAssertFalse(game.axePresentation.visible)
        XCTAssertNil(game.axePresentation.pendingQuake)
        for _ in 0..<40 {
            game.step()
            XCTAssertNil(game.axePresentation.quake)
        }
        game.step(erlangAction: .mountainSplitter)
        XCTAssertEqual(game.axePresentation.castID, castID + 1)
    }
}
