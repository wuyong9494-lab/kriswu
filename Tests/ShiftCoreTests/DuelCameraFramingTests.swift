import XCTest
@testable import ShiftCore

final class DuelCameraFramingTests: XCTestCase {
    func testWideCloseUpAndSeparatedFighters() {
        let close = DuelCameraFraming(aspect: 2.1, separation: 3)
        let apart = DuelCameraFraming(aspect: 2.1, separation: 10)
        XCTAssertEqual(close.verticalFieldOfView, 31)
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
