import XCTest
@testable import ShiftCore

final class DuelErlangEyePresentationTests: XCTestCase {
    private func ready(distanceSteps: Int, mode: DuelErlangState.Mode = .versus) -> DuelErlangSparring {
        var game = DuelErlangSparring(mode: mode)
        for _ in 0..<distanceSteps { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        game.step(erlangAction: .ascend)
        return game
    }

    func testNoPresentationForRejectedInput() {
        var game = DuelErlangSparring()
        game.step(erlangAction: .avatarEye)
        XCTAssertEqual(game.eyePresentation, DuelErlangEyePresentation())
    }

    func testSixAdjudicatedPulseEdgesAndNoLingeringBeam() {
        var game = ready(distanceSteps: 7)
        var ages: [Int] = [], active: [Int] = []
        for age in 1...26 {
            let hp = game.fighters[1].health
            game.step(erlangAction: age == 1 ? .avatarEye : nil)
            let view = game.eyePresentation
            XCTAssertEqual(view.visible, age <= 22)
            if view.active { active.append(age) }
            if view.contact == .landed {
                ages.append(age)
                XCTAssertEqual(view.damage, hp - game.fighters[1].health)
                XCTAssertEqual(view.contactX, game.fighters[1].position)
            } else {
                XCTAssertNil(view.damage)
                XCTAssertNil(view.contactX)
                XCTAssertEqual(game.fighters[1].health, hp)
            }
        }
        XCTAssertEqual(active, Array(7...22))
        XCTAssertEqual(ages, [7, 10, 13, 16, 19, 22])
        XCTAssertEqual(game.eyePresentation.landedCount, 6)
        XCTAssertEqual(game.eyePresentation.outcome, .hit)
    }

    func testGuardAndMissKeepBeamButNeverEmitLandedContact() {
        for blocked in [false, true] {
            var game = ready(distanceSteps: blocked ? 7 : 1)
            game.step(erlangAction: .avatarEye, partnerAction: blocked ? .guardOn : nil)
            for _ in 2...22 {
                game.step()
                XCTAssertNotEqual(game.eyePresentation.contact, .landed)
                XCTAssertEqual(game.fighters[1].health, 100)
                XCTAssertEqual(game.fighters[1].vulnerabilityStacks, 0)
            }
            XCTAssertTrue(game.eyePresentation.active)
            XCTAssertEqual(game.eyePresentation.outcome, blocked ? .blocked : .missed)
            XCTAssertEqual(game.eyePresentation.blockedCount, blocked ? 6 : 0)
            game.step()
            XCTAssertFalse(game.eyePresentation.active)
            XCTAssertNil(game.eyePresentation.contact)
        }
    }

    func testSimultaneousContactSurvivesInterruptWithoutPhantomLaterPulses() {
        var game = ready(distanceSteps: 10)
        for age in 1...10 {
            game.step(erlangAction: age == 1 ? .avatarEye : nil,
                      partnerAction: age == 7 ? .spear : nil)
        }
        XCTAssertEqual(game.eyePresentation.outcome, .cancelled)
        XCTAssertEqual(game.eyePresentation.contact, .landed)
        XCTAssertEqual(game.eyePresentation.landedCount, 2)
        XCTAssertFalse(game.eyePresentation.active)
        XCTAssertFalse(game.eyePresentation.visible)
        let hpAfterInterrupt = game.fighters[1].health
        for _ in 0..<20 {
            game.step()
            XCTAssertNil(game.eyePresentation.contact)
            XCTAssertEqual(game.fighters[1].health, hpAfterInterrupt)
        }
    }

    func testResetDropsCastAndDoesNotReuseIdentity() {
        var game = ready(distanceSteps: 7, mode: .teamRaid)
        game.step(erlangAction: .avatarEye)
        for _ in 2...8 { game.step() }
        let id = game.eyePresentation.castID
        XCTAssertTrue(game.eyePresentation.active)
        game.resetRound()
        XCTAssertEqual(game.eyePresentation.outcome, .reset)
        XCTAssertFalse(game.eyePresentation.active)
        XCTAssertNil(game.eyePresentation.contact)
        XCTAssertEqual(game.eyePresentation.contactCount, 0)
        game.step(erlangAction: .avatarEye)
        XCTAssertEqual(game.eyePresentation.castID, id + 1)
    }
}
