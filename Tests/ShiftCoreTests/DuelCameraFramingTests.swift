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
}
