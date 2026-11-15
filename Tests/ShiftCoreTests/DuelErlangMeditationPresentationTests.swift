import XCTest
@testable import ShiftCore

final class DuelErlangMeditationPresentationTests: XCTestCase {
    private func game(close: Bool = false) -> DuelErlangSparring {
        var game = DuelErlangSparring(enableLevelThreeMeditation: true)
        for i in 0..<30 {
            game.step(erlangAction: i < 10 && close ? .walk(1) : nil,
                      partnerAction: i < 10 && close ? .walk(-1) : nil)
        }
        game.step(erlangAction: .meditate)
        return game
    }

    func testStartAndWrapUseValidSamplesWithoutDuplicatingLoopEndpoint() {
        var g = game()
        for i in 0..<18 {
            XCTAssertEqual(g.meditationPresentation.animationStatus, .entering)
            XCTAssertEqual(g.meditationPresentation.pose, .init(clip: .start, sample: i))
            g.step()
        }
        for i in 1...71 {
            XCTAssertEqual(g.meditationPresentation.animationStatus, .holding)
            XCTAssertEqual(g.meditationPresentation.pose, .init(clip: .loop, sample: i))
            g.step()
        }
        XCTAssertEqual(g.meditationPresentation.pose, .init(clip: .loop, sample: 0))
        g.step()
        XCTAssertEqual(g.meditationPresentation.pose, .init(clip: .loop, sample: 1))
    }

    func testEarlyReleaseCrossfadesFromCurrentPoseAndEmitsBlastOnlyOnce() {
        var g = game(close: true)
        for _ in 0..<11 { g.step() }
        g.step(erlangAction: .stopMeditation)
        XCTAssertEqual(g.meditationPresentation.pose, .init(clip: .end, sample: 0))
        XCTAssertEqual(g.meditationPresentation.blendFrom, .init(clip: .start, sample: 11, weight: 1))
        XCTAssertTrue(g.releasedMeditationThisTick)
        XCTAssertEqual(g.fighters[1].health, 98)
        for i in 1..<22 {
            g.step()
            XCTAssertFalse(g.releasedMeditationThisTick)
            XCTAssertEqual(g.meditationPresentation.pose, .init(clip: .end, sample: i))
            XCTAssertEqual(g.meditationPresentation.blendFrom?.weight, i < 4 ? Double(4 - i) / 4 : nil)
        }
        g.step()
        XCTAssertNil(g.meditationPresentation.pose)
        XCTAssertEqual(g.meditationPresentation.animationStatus, .inactive)
    }

    func testInterruptClearsPoseAndNeverReleasesBlast() {
        var g = game(close: true)
        for _ in 0..<20 { g.step() }
        g.step(partnerAction: .spear)
        for _ in 0..<3 { g.step() }
        XCTAssertEqual(g.meditationPresentation.animationStatus, .interrupted)
        XCTAssertNil(g.meditationPresentation.pose)
        XCTAssertNil(g.meditationPresentation.blendFrom)
        XCTAssertFalse(g.releasedMeditationThisTick)
        g.step(erlangAction: .stopMeditation)
        XCTAssertEqual(g.meditationPresentation.animationStatus, .inactive)
        XCTAssertFalse(g.releasedMeditationThisTick)
    }

    func testNewAcceptedActionAndRoundResetClearRecoveryPose() {
        var g = game()
        for _ in 0..<20 { g.step() }
        g.step(erlangAction: .stopMeditation)
        XCTAssertEqual(g.meditationPresentation.blendFrom?.clip, .loop)
        XCTAssertEqual(g.meditationPresentation.animationStatus, .releasing)
        g.step(erlangAction: .spear)
        XCTAssertNil(g.meditationPresentation.pose)
        XCTAssertFalse(g.releasedMeditationThisTick)
        g.resetRound()
        XCTAssertEqual(g.meditationPresentation, DuelErlangMeditationPresentation())
    }

    func testNaturalCompletionAlsoEndsOnce() {
        var g = game()
        var ends = 0
        for _ in 0..<440 {
            g.step()
            if g.releasedMeditationThisTick {
                ends += 1
                XCTAssertEqual(g.meditationPresentation.pose, .init(clip: .end, sample: 0))
            }
        }
        XCTAssertEqual(ends, 1)
        XCTAssertEqual(g.meditationPresentation.animationStatus, .inactive)
    }
}
