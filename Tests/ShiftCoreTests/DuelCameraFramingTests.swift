import XCTest
@testable import ShiftCore

final class DuelCameraFramingTests: XCTestCase {
    func testWideCloseUpAndSeparatedFighters() {
        let close = DuelCameraFraming(aspect: 2.1, separation: 3)
        let apart = DuelCameraFraming(aspect: 2.1, separation: 10)
        XCTAssertEqual(close.verticalFieldOfView, 29)
        XCTAssertEqual(close.orthographicScale, 2.85)
        XCTAssertGreaterThan(apart.verticalFieldOfView, close.verticalFieldOfView)
        XCTAssertGreaterThan(apart.orthographicScale, close.orthographicScale)
        XCTAssertLessThanOrEqual(apart.verticalFieldOfView, 47)
    }

    func testPortraitRetainsOverviewAtEverySeparation() {
        for distance in [0.0, 3, 6, 10] {
            let portrait = DuelCameraFraming(aspect: 0.46, separation: distance)
            let wide = DuelCameraFraming(aspect: 2.1, separation: distance)
            XCTAssertGreaterThan(portrait.verticalFieldOfView, wide.verticalFieldOfView)
            let horizontalSpan = 2 * portrait.perspectiveDistance
                * tan(portrait.verticalFieldOfView * .pi / 360) * 0.46
            XCTAssertGreaterThanOrEqual(horizontalSpan, 11.6 - 0.0001,
                                        "FOV cap must not crop the safe stage overview")
            XCTAssertGreaterThanOrEqual(portrait.orthographicScale, 5.8 / 0.46)
        }
    }

    func testSeparatedFightersKeepBodyMarginInEveryLandscapeWidth() {
        for aspect in [1.5, 1.6, 1.78, 2.1, 2.4] {
            for separation in [0.0, 3, 6, 9.3, 10, 13] {
                let result = DuelCameraFraming(aspect: aspect, separation: separation)
                let halfWidth = result.perspectiveDistance * tan(result.verticalFieldOfView * .pi / 360) * aspect
                XCTAssertGreaterThanOrEqual(halfWidth + 0.000001, separation * 0.5 + 0.8,
                                           "Both silhouettes need room even when landscape FOV reaches its cap")
                XCTAssertLessThanOrEqual(result.verticalFieldOfView, 47)
            }
        }
        XCTAssertGreaterThan(DuelCameraFraming(aspect: 1.5, separation: 10).perspectiveDistance, 7.7)
    }

    func testOpeningShotTargetsHalfHeightForNominalTwoMeterSilhouetteOnWidePhones() {
        // An optical estimate, not proof of the actual source character's
        // on-screen bounds. The screenshot and bone-extents gate is separate.
        for aspect in [1.78, 2.1, 2.4] {
            let opening = DuelCameraFraming(aspect: aspect, separation: 3)
            XCTAssertEqual(opening.verticalFieldOfView, 29)
            XCTAssertEqual(opening.perspectiveDistance, 7.7)
            let visibleHeight = 2 * opening.perspectiveDistance
                * tan(opening.verticalFieldOfView * .pi / 360)
            let nominalFraction = 2.0 / visibleHeight
            XCTAssertGreaterThanOrEqual(nominalFraction, 0.48)
            XCTAssertLessThanOrEqual(nominalFraction, 0.55)
        }
    }

    func testLandscapeThresholdHasNoHardLensJump() {
        // The pre-fix 1.5 aspect boundary changed the perspective FOV and
        // orthographic size in one layout callback with no fighter movement.
        for separation in [0.0, 3, 6, 10, 13] {
            let before = DuelCameraFraming(aspect: 1.4999, separation: separation)
            let after = DuelCameraFraming(aspect: 1.5001, separation: separation)
            XCTAssertLessThan(abs(before.verticalFieldOfView - after.verticalFieldOfView), 0.1)
            XCTAssertLessThan(abs(before.perspectiveDistance - after.perspectiveDistance), 0.1)
            XCTAssertLessThan(abs(before.orthographicScale - after.orthographicScale), 0.1)
        }
    }


    func testUnexpectedFiniteSeparationCannotOverflowCameraDistance() {
        // Gameplay tracks two clamped stage positions, but a malformed
        // presentation sample must not turn the SceneKit camera z into infinity.
        for aspect in [0.1, 0.46, 1.0, 1.5, 2.1, 3.0] {
            let bounded = DuelCameraFraming(aspect: aspect, separation: 20)
            for sample in [20.0, 1_000.0, 1.0e40, Double.greatestFiniteMagnitude] {
                let framing = DuelCameraFraming(aspect: aspect, separation: sample)
                XCTAssertEqual(framing, bounded, "Oversized pair extent must be clamped")
                XCTAssertTrue(framing.perspectiveDistance.isFinite)
                XCTAssertTrue(framing.verticalFieldOfView.isFinite)
                XCTAssertTrue(framing.orthographicScale.isFinite)
            }
        }
    }

    func testContinuousCameraEnvelopeKeepsBothFightersVisible() {
        // Sweep rather than checking only a few predefined dashes and gaps.
        // This uses the ten-unit stage's conservative two-sided 0.8 m margin;
        // actual skeleton and weapon projection remains a native acceptance gate.
        for aspect in [0.46, 1.0, 1.5, 1.78, 2.1, 2.4] {
            for quarterStep in 0...80 {
                let separation = Double(quarterStep) * 0.25
                let framing = DuelCameraFraming(aspect: aspect, separation: separation)
                let halfWidth = framing.perspectiveDistance
                    * tan(framing.verticalFieldOfView * .pi / 360) * aspect
                XCTAssertGreaterThanOrEqual(halfWidth + 0.000001, separation * 0.5 + 0.8)
                XCTAssertTrue(framing.perspectiveDistance.isFinite)
            }
        }
    }

    func testInvalidTransientGeometryCannotPoisonProjection() {
        for aspect in [0.0, -1, Double.nan, Double.infinity] {
            let result = DuelCameraFraming(aspect: aspect, separation: .nan)
            XCTAssertTrue(result.verticalFieldOfView.isFinite)
            XCTAssertTrue(result.orthographicScale.isFinite)
            XCTAssertTrue(result.perspectiveDistance.isFinite)
            XCTAssertGreaterThan(result.verticalFieldOfView, 0)
            XCTAssertLessThanOrEqual(result.verticalFieldOfView, 100)
        }
    }

    func testOpticalFOVExpandsImmediatelyButReturnsSmoothly() {
        var lens = DuelCameraOpticalFOV()
        XCTAssertEqual(lens.consume(required: 29, frame: 1, aspect: 2.1), 29)
        XCTAssertEqual(lens.consume(required: 45, frame: 2, aspect: 2.1), 45)
        let contracting = lens.consume(required: 29, frame: 3, aspect: 2.1)
        XCTAssertGreaterThan(contracting, 29)
        XCTAssertLessThan(contracting, 45)
        let later = lens.consume(required: 29, frame: 33, aspect: 2.1)
        XCTAssertLessThan(later, contracting)
        XCTAssertGreaterThanOrEqual(later, 29)
    }

    func testRepeatedLayoutsNeverAccelerateOpticalZoomOrCropNewPose() {
        var lens = DuelCameraOpticalFOV()
        lens.consume(required: 50, frame: 1, aspect: 2.1)
        let first = lens.consume(required: 29, frame: 2, aspect: 2.1)
        for _ in 0..<100 {
            XCTAssertEqual(lens.consume(required: 29, frame: 2, aspect: 2.1), first)
        }
        XCTAssertEqual(lens.consume(required: 55, frame: 2, aspect: 2.1), 55)
        XCTAssertEqual(lens.consume(required: 29, frame: 2, aspect: 2.1), 55)
        XCTAssertGreaterThan(lens.consume(required: 29, frame: 3, aspect: 2.1), 29)
    }

    func testExplicitBoutRestartClearsOpticalFOVEvenOnIdenticalFrame() {
        var lens = DuelCameraOpticalFOV()
        XCTAssertEqual(lens.consume(required: 56, frame: 0, aspect: 2.1), 56)
        // A repeated layout of the same match correctly keeps the widest
        // measured pose. Restart is different despite reusing frame zero.
        XCTAssertEqual(lens.consume(required: 29, frame: 0, aspect: 2.1), 56)
        lens.reset()
        XCTAssertEqual(lens.consume(required: 29, frame: 0, aspect: 2.1), 29,
                       "A new bout must not inherit the last weapon swing's optical zoom")
        XCTAssertEqual(lens.consume(required: 48, frame: 0, aspect: 2.1), 48,
                       "The new bout must still expand immediately for its real pose")
        XCTAssertGreaterThan(lens.consume(required: 29, frame: 1, aspect: 2.1), 29)
    }

    func testOpticalFOVResetsOnRewindAndRotation() {
        var lens = DuelCameraOpticalFOV()
        lens.consume(required: 52, frame: 10, aspect: 2.1)
        XCTAssertEqual(lens.consume(required: 29, frame: 11, aspect: 2.1), 52 * 0.92 + 29 * 0.08,
                       accuracy: 0.000001)
        XCTAssertEqual(lens.consume(required: 31, frame: 11, aspect: 1.0), 31,
                       "Changing device orientation must recompute the optical fit immediately")
        XCTAssertEqual(lens.consume(required: 29, frame: 0, aspect: 1.0), 29,
                       "A new match or rewound simulation must not inherit the old lens")
        XCTAssertEqual(lens.consume(required: .nan, frame: 1, aspect: 1.0), 29)
        lens.reset()
        XCTAssertEqual(lens.consume(required: 33, frame: 1, aspect: 2.1), 33)
    }


    func testSmallSafeAreaAspectJitterCannotSnapOutOfWideWeaponFit() {
        var lens = DuelCameraOpticalFOV()
        XCTAssertEqual(lens.consume(required: 52, frame: 10, aspect: 2.10), 52)
        let eased = lens.consume(required: 29, frame: 11, aspect: 2.115)
        XCTAssertEqual(eased, 29 + (52 - 29) * 0.92, accuracy: 0.000001,
                       "Minor UIKit viewport changes must not abruptly shrink the lens")

        // A newly extended weapon must still fit, including multiple layouts
        // during the SAME simulation frame.
        XCTAssertEqual(lens.consume(required: 55, frame: 11, aspect: 2.119), 55)
        XCTAssertEqual(lens.consume(required: 29, frame: 11, aspect: 2.12), 55)
        XCTAssertGreaterThan(lens.consume(required: 29, frame: 12, aspect: 2.135), 29)

        // Compare against the initial anchor, not the previous layout: a
        // true orientation transition must not carry an obsolete wide shot.
        XCTAssertEqual(lens.consume(required: 29, frame: 13, aspect: 2.15), 29)
        XCTAssertEqual(lens.consume(required: 54, frame: 14, aspect: 2.15), 54)
        XCTAssertEqual(lens.consume(required: 30, frame: 15, aspect: 1.0), 30)
    }
}
