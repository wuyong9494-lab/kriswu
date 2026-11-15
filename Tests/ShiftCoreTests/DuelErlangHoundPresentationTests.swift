import XCTest
@testable import ShiftCore

final class DuelErlangHoundPresentationTests: XCTestCase {
    private func approach(_ steps: Int) -> DuelErlangSparring {
        var game = DuelErlangSparring()
        for _ in 0..<steps { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        return game
    }

    func testHitReportsPrePushContactPointOnceAndEndsCleanly() {
        var g = approach(5)
        let targetPosition = g.fighters[1].position
        g.step(erlangAction: .hound)
        XCTAssertTrue(g.houndPresentation.started)
        XCTAssertTrue(g.houndPresentation.visible)
        XCTAssertEqual(g.houndPresentation.actionAge, 1)
        XCTAssertNil(g.houndPresentation.sweep)
        // Repeated inputs during an accepted action do not start a second dog.
        for _ in 0..<10 {
            g.step(erlangAction: .hound)
            XCTAssertFalse(g.houndPresentation.started)
            XCTAssertNil(g.houndPresentation.outcome)
            XCTAssertEqual(g.houndPresentation.castID, 1)
        }
        g.step()
        XCTAssertEqual(g.houndPresentation.outcome, .hit)
        XCTAssertEqual(g.houndPresentation.contactPosition, targetPosition)
        let sweep = try? XCTUnwrap(g.houndPresentation.sweep)
        XCTAssertTrue(sweep.map { ($0.start...$0.end).contains(targetPosition) } ?? false)
        XCTAssertGreaterThan(g.fighters[1].position, targetPosition)
        XCTAssertEqual(g.fighters[1].health, 85)
        XCTAssertGreaterThan(g.fighters[1].knockdown, 0)
        XCTAssertGreaterThan(g.fighters[1].weakness, 0)
        g.step()
        XCTAssertNil(g.houndPresentation.outcome)
        XCTAssertNil(g.houndPresentation.sweep)
        g.step()
        XCTAssertFalse(g.houndPresentation.visible)
    }

    func testBlockAndWhiffDoNotShowHitOrDebuffs() {
        for block in [false, true] {
            var g = approach(block ? 5 : 0)
            g.step(erlangAction: .hound, partnerAction: block ? .guardOn : nil)
            var outcomes: [DuelErlangHoundPresentation.Outcome] = []
            for _ in 0..<18 {
                g.step()
                if let outcome = g.houndPresentation.outcome { outcomes.append(outcome) }
            }
            XCTAssertEqual(outcomes, [block ? .blocked : .missed])
            XCTAssertFalse(g.houndPresentation.visible)
            XCTAssertEqual(g.fighters[1].health, 100)
            XCTAssertEqual(g.fighters[1].weakness, 0)
            XCTAssertEqual(g.fighters[1].knockdown, 0)
        }
    }

    func testMeleeBeforeSweepCancelsWithoutMissOrImpact() {
        var g = approach(10)
        g.step(erlangAction: .hound, partnerAction: .spear)
        for _ in 0..<3 { g.step() }
        XCTAssertEqual(g.houndPresentation.outcome, .cancelled)
        XCTAssertFalse(g.houndPresentation.visible)
        XCTAssertNil(g.houndPresentation.contactPosition)
        XCTAssertNil(g.houndPresentation.sweep)
        for _ in 0..<18 {
            g.step()
            XCTAssertNil(g.houndPresentation.outcome)
        }
        XCTAssertEqual(g.fighters[1].health, 100)
    }

    func testResetDoesNotLeaveDogOrReuseID() {
        var g = approach(0)
        g.step(erlangAction: .hound)
        g.resetRound()
        XCTAssertEqual(g.houndPresentation.outcome, .cancelled)
        XCTAssertFalse(g.houndPresentation.visible)
        XCTAssertNil(g.houndPresentation.sweep)
        g.step(erlangAction: .hound)
        XCTAssertEqual(g.houndPresentation.castID, 2)
        XCTAssertTrue(g.houndPresentation.started)
    }
}
