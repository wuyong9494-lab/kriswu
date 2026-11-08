import XCTest
@testable import ShiftCore

final class DuelOriginalRigReviewTests: XCTestCase {
    func testCatalogSeparatesSourceMovesFromDiagnosticAndLegacyGrapple() {
        let clips = DuelOriginalRigReview.Clip.allCases
        XCTAssertEqual(clips.count, 26)
        XCTAssertEqual(clips.compactMap(\.source).count, 25)
        XCTAssertEqual(Set(clips.compactMap(\.source).map(\.sha256)).count, 25)
        XCTAssertNil(DuelOriginalRigReview.Clip.tPose.source)
        for absent in ["Grab", "SideLock", "Release"] {
            XCTAssertNil(DuelOriginalRigReview.Clip(rawValue: absent))
        }
        XCTAssertNil(DuelOriginalRigReview.sourceFramesPerSecond)
        XCTAssertFalse(DuelOriginalRigReview.combatTimingVerified)
        XCTAssertTrue(DuelOriginalRigReview.horizontalRootMotionRemoved)
    }

    func testEverySourceFrameUsesWholeDecodedIntervalIncludingNonzeroStart() {
        for clip in DuelOriginalRigReview.Clip.allCases where clip.source != nil {
            let start: Float = 1 / 30
            let end = Float(clip.frameCount) / 30
            for frame in 0..<clip.frameCount {
                let selection = DuelOriginalRigReview.Selection(clip: clip, sourceFrame: frame)
                XCTAssertEqual(selection.assetTime(start: start, end: end), Float(frame + 1) / 30, accuracy: 0.00001)
            }
        }
    }

    func testOneShotLoopsAndInvalidInputAreExplicitAndBounded() {
        typealias Selection = DuelOriginalRigReview.Selection
        XCTAssertEqual(Selection(clip: .jab, previewElapsed: 100).phase, 1)
        XCTAssertEqual(Selection(clip: .jab, previewElapsed: 0).phase, 0)
        let duration = Double(DuelOriginalRigReview.Clip.jab.frameCount - 1) / 30
        XCTAssertEqual(Selection(clip: .jab, previewElapsed: duration, looping: true).phase, 0)
        XCTAssertEqual(Selection(clip: .jab, previewElapsed: duration / 2).phase, 0.5, accuracy: 0.00001)
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertEqual(Selection(clip: .jab, phase: invalid).phase, 0)
            XCTAssertEqual(Selection(clip: .jab, previewElapsed: invalid, looping: true).phase, 0)
        }
        XCTAssertEqual(Selection(clip: .jab, sourceFrame: Int.max).phase, 1)
        XCTAssertEqual(Selection(clip: .jab, sourceFrame: Int.min).phase, 0)
        XCTAssertEqual(Selection(clip: .tPose, previewElapsed: 100).phase, 0)
        XCTAssertEqual(Selection(clip: .jab, phase: 0.5).assetTime(start: .nan, end: 1), 0)
    }
}
