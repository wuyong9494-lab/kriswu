import XCTest
@testable import ShiftCore

final class DuelErlangHoundSmokeTests: XCTestCase {
    func testNormalExposureAndPuffsDoNotRequireContact() {
        for hit in [false, true] {
            var g = DuelErlangSparring()
            if hit { for _ in 0..<5 { g.step(erlangAction: .walk(1), partnerAction: .walk(-1)) } }
            var trail = 0, spawn = 0, dismiss = 0, hits = 0
            for i in 0..<20 {
                g.step(erlangAction: i < 6 ? .hound : nil)
                trail += g.houndSmoke.trail ? 1 : 0
                spawn += g.houndSmoke.spawnPuff ? 1 : 0
                dismiss += g.houndSmoke.dismissPuff ? 1 : 0
                hits += g.houndPresentation.outcome == .hit ? 1 : 0
                XCTAssertFalse(g.houndSmoke.trail && g.houndSmoke.dismissPuff)
                XCTAssertEqual(g.houndSmoke.castID, 1)
            }
            XCTAssertEqual([trail, spawn, dismiss, hits], [13, 3, 3, hit ? 1 : 0])
        }
    }

    func testInterruptAndResetConcludeWithoutDismiss() {
        var g = DuelErlangSparring()
        for _ in 0..<10 { g.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        g.step(erlangAction: .hound, partnerAction: .spear)
        for _ in 0..<3 { g.step() }
        XCTAssertEqual(g.houndPresentation.outcome, .cancelled)
        XCTAssertFalse(g.houndSmoke.trail || g.houndSmoke.spawnPuff || g.houndSmoke.dismissPuff)
        for _ in 0..<6 {
            g.step()
            XCTAssertFalse(g.houndSmoke.dismissPuff)
        }
        g.resetRound()
        g.step(erlangAction: .hound)
        XCTAssertEqual(g.houndSmoke.castID, 2)
        XCTAssertTrue(g.houndSmoke.trail)
        g.resetRound()
        XCTAssertFalse(g.houndSmoke.trail || g.houndSmoke.spawnPuff || g.houndSmoke.dismissPuff)
        g.step()
        XCTAssertFalse(g.houndSmoke.dismissPuff)
    }

    func testRoundEndClearsResidualAndCannotTriggerASpawn() {
        var g = DuelErlangSparring()
        g.step(erlangAction: .hound)
        var smoke = g.houndSmoke
        XCTAssertTrue(smoke.spawnPuff)
        smoke.observe(g.houndPresentation, roundFinished: true)
        XCTAssertFalse(smoke.trail || smoke.spawnPuff || smoke.dismissPuff)
        smoke.observe(g.houndPresentation, roundFinished: false)
        XCTAssertFalse(smoke.trail || smoke.spawnPuff || smoke.dismissPuff)
    }
}
