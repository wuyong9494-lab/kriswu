import XCTest
@testable import ShiftCore

final class DuelErlangMeditationMediaTests: XCTestCase {
    private func begin(close: Bool = true) -> DuelErlangSparring {
        var game = DuelErlangSparring(enableLevelThreeMeditation: true)
        for i in 0..<30 {
            game.step(erlangAction: close && i < 10 ? .walk(1) : nil,
                      partnerAction: close && i < 10 ? .walk(-1) : nil)
        }
        game.step(erlangAction: .meditate)
        return game
    }

    func testHeldAndReleaseHaveOneEdgeEachAndShortEffectExpires() {
        var game = begin()
        XCTAssertEqual(game.meditationMedia.transition, .started)
        XCTAssertTrue(game.meditationMedia.loopMediaActive)
        let start = game.meditationMedia.transitionID
        for _ in 0..<95 {
            game.step(erlangAction: .meditate)
            XCTAssertTrue(game.meditationMedia.loopMediaActive)
            XCTAssertNil(game.meditationMedia.transition)
            XCTAssertEqual(game.meditationMedia.transitionID, start)
        }
        game.step(erlangAction: .stopMeditation)
        XCTAssertTrue(game.releasedMeditationThisTick)
        XCTAssertFalse(game.meditationMedia.loopMediaActive)
        XCTAssertTrue(game.meditationMedia.releaseEffectActive)
        XCTAssertEqual(game.meditationMedia.transition, .released)
        XCTAssertEqual(game.meditationMedia.transitionID, start + 1)
        for _ in 1..<DuelErlangMeditationMedia.releasePreviewTicks {
            game.step(erlangAction: .stopMeditation)
            XCTAssertFalse(game.releasedMeditationThisTick)
            XCTAssertTrue(game.meditationMedia.releaseEffectActive)
            XCTAssertNil(game.meditationMedia.transition)
        }
        game.step()
        XCTAssertFalse(game.meditationMedia.releaseEffectActive)
        XCTAssertEqual(game.meditationPresentation.animationStatus, .releasing)
    }

    func testRangedImmunityKeepsLoopButMeleeKillsBothLayersWithoutPulse() {
        var game = begin()
        game.step(partnerAction: .partnerRanged)
        for _ in 0..<3 { game.step() }
        XCTAssertTrue(game.events.contains(.rangedDamagePrevented))
        XCTAssertTrue(game.meditationMedia.loopMediaActive)
        XCTAssertNil(game.meditationMedia.transition)
        for _ in 0..<12 { game.step() }
        game.step(partnerAction: .spear)
        for _ in 0..<3 { game.step() }
        XCTAssertEqual(game.meditationMedia.transition, .interrupted)
        XCTAssertFalse(game.meditationMedia.loopMediaActive)
        XCTAssertFalse(game.meditationMedia.releaseEffectActive)
        XCTAssertFalse(game.releasedMeditationThisTick)
        XCTAssertEqual(game.fighters[1].health, 100)
    }

    func testResetClearsHeldAndReleaseMediaAndDoesNotReuseEdgeID() {
        for beforeReset in [false, true] {
            var game = begin(close: false)
            if beforeReset { game.step(erlangAction: .stopMeditation) }
            let previous = game.meditationMedia.transitionID
            game.resetRound()
            XCTAssertFalse(game.meditationMedia.loopMediaActive)
            XCTAssertFalse(game.meditationMedia.releaseEffectActive)
            XCTAssertEqual(game.meditationMedia.transition, .cancelled)
            XCTAssertEqual(game.meditationMedia.transitionID, previous + 1)
            game.resetRound()
            XCTAssertNil(game.meditationMedia.transition)
            for _ in 0..<30 { game.step() }
            game.step(erlangAction: .meditate)
            XCTAssertEqual(game.meditationMedia.transition, .started)
            XCTAssertEqual(game.meditationMedia.transitionID, previous + 2)
        }
    }

    func testRoundTerminationHasPriorityOverResidualOrNewEffect() {
        var media = DuelErlangMeditationMedia()
        media.advance(holding: true, released: false, interrupted: false, roundFinished: false)
        media.advance(holding: true, released: true, interrupted: false, roundFinished: true)
        XCTAssertFalse(media.loopMediaActive)
        XCTAssertFalse(media.releaseEffectActive)
        XCTAssertEqual(media.transition, .cancelled)
        media.advance(holding: false, released: false, interrupted: false, roundFinished: true)
        XCTAssertNil(media.transition)
    }

    func testNaturalFinishWithoutContactStillReleasesVisualOnlyOnce() {
        var game = begin(close: false)
        var releases = 0
        for _ in 0..<420 {
            game.step()
            if game.meditationMedia.transition == .released {
                releases += 1
                XCTAssertTrue(game.releasedMeditationThisTick)
                XCTAssertTrue(game.meditationMedia.releaseEffectActive)
                XCTAssertFalse(game.meditationMedia.loopMediaActive)
            }
        }
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(game.fighters[1].health, 100)
        XCTAssertFalse(game.meditationMedia.releaseEffectActive)
    }
}
