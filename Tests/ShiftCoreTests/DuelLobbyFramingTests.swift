import XCTest
@testable import ShiftCore

final class DuelLobbyFramingTests: XCTestCase {
    func testPerspectiveEnvelopeClearsMeasuredControlsAtPhoneAndTabletSizes() throws {
        for (size, rect) in fixtures {
            let fit = try XCTUnwrap(DuelLobbyFraming(size: size, visibleRect: rect))
            for point in DuelLobbyFraming.envelope {
                let projected = fit.project(point, size: size)
                XCTAssertGreaterThanOrEqual(projected.x, rect.minX + 7.9999)
                XCTAssertLessThanOrEqual(projected.x, rect.maxX - 7.9999)
                XCTAssertGreaterThanOrEqual(projected.y, rect.minY + 7.9999)
                XCTAssertLessThanOrEqual(projected.y, rect.maxY - 7.9999)
            }
        }
    }

    func testShowroomOpeningUsesOpticalShiftWithoutMovingEye() throws {
        let size = CGSize(width: 956, height: 440)
        let fit = try XCTUnwrap(DuelLobbyFraming(size: size,
            visibleRect: CGRect(x: 285, y: 0, width: 386, height: 326)))
        // Full empty central height is available above the title. Restricting
        // the opening to the side panels' height needlessly halves body scale.
        XCTAssertLessThan(fit.distance, 6.7)
        XCTAssertEqual(fit.target, DuelLobbyFraming.center)
        XCTAssertEqual(fit.position, DuelLobbyFraming.originalPosition)
        XCTAssertGreaterThan(fit.projectionOffset.y, 0)
        XCTAssertEqual(DuelLobbyFraming.verticalFieldOfView, 35)
    }

    func testTallerRailReframesAndZoomRemainsRelativeToEachLayout() throws {
        let size = CGSize(width: 844, height: 390)
        let opening = CGRect(x: 264, y: 0, width: 316, height: 280)
        let reduced = CGRect(x: 264, y: 0, width: 316, height: 225)
        let full = try XCTUnwrap(DuelLobbyFraming(size: size, visibleRect: opening))
        let small = try XCTUnwrap(DuelLobbyFraming(size: size, visibleRect: reduced))
        XCTAssertEqual(small.distance, full.distance, accuracy: 0.000001)
        XCTAssertGreaterThanOrEqual(small.verticalTangent, full.verticalTangent)
        for rect in [opening, reduced] {
            let base = try XCTUnwrap(DuelLobbyFraming(size: size, visibleRect: rect))
            for zoom in [0.7, 0.9, 1.0, 1.5] {
                let result = try XCTUnwrap(DuelLobbyFraming(size: size, visibleRect: rect, zoom: zoom))
                XCTAssertEqual(result.distance, base.distance, accuracy: 0.000001)
                XCTAssertEqual(result.position, DuelLobbyFraming.originalPosition)
                XCTAssertEqual(result.verticalTangent, base.verticalTangent * zoom, accuracy: 0.000001)
                XCTAssertEqual(result, DuelLobbyFraming(size: size, visibleRect: rect, zoom: zoom))
            }
        }
    }

    func testOffCenterRegionUsesLensShiftRatherThanExtraDistance() throws {
        let size = CGSize(width: 956, height: 440)
        let left = CGRect(x: 210, y: 0, width: 386, height: 326)
        let fit = try XCTUnwrap(DuelLobbyFraming(size: size, visibleRect: left))
        for point in DuelLobbyFraming.envelope {
            let projected = fit.project(point, size: size)
            XCTAssertTrue(left.insetBy(dx: 7.99, dy: 7.99).contains(projected))
        }
    }

    func testInvalidTransientLayoutIsRejectedAndFallbackInputsRemainFinite() throws {
        let size = CGSize(width: 956, height: 440)
        let rect = CGRect(x: 285, y: 0, width: 386, height: 326)
        for invalid in [CGSize.zero, CGSize(width: 0, height: 440),
                        CGSize(width: CGFloat.nan, height: 440), CGSize(width: CGFloat.infinity, height: 440)] {
            XCTAssertNil(DuelLobbyFraming(size: invalid, visibleRect: rect))
        }
        for invalid in [CGRect.zero, CGRect.null, CGRect(x: 2000, y: 0, width: 40, height: 40),
                        CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)] {
            XCTAssertNil(DuelLobbyFraming(size: size, visibleRect: invalid))
        }
        let ordinary = try XCTUnwrap(DuelLobbyFraming(size: size, visibleRect: rect))
        for invalid in [Double.nan, .infinity] {
            XCTAssertEqual(ordinary, DuelLobbyFraming(size: size, visibleRect: rect, zoom: invalid))
            let tiny = try XCTUnwrap(DuelLobbyFraming(size: size,
                visibleRect: CGRect(x: 0, y: 0, width: 3, height: 3), margin: invalid))
            XCTAssertTrue(tiny.distance.isFinite)
        }
    }

    func testPathologicalFiniteViewportsCannotReturnAnUnrenderableCamera() {
        let largest = CGFloat.greatestFiniteMagnitude
        let cases: [(CGSize, CGRect)] = [
            (CGSize(width: largest, height: 440), CGRect(x: 0, y: 0, width: 3, height: 300)),
            (CGSize(width: 956, height: largest), CGRect(x: 285, y: 0, width: 386, height: 3)),
            (CGSize(width: 3, height: largest), CGRect(x: 0, y: 0, width: 3, height: 300))
        ]
        for (size, rect) in cases {
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
            XCTAssertNil(DuelLobbyFraming(size: size, visibleRect: rect),
                         "Overflow or a numerically collapsed opening must preserve the last valid camera")
        }
        // Not every large finite viewport is invalid. Uniform resizing keeps
        // its aspect / normalized region and therefore its camera finite.
        let size = CGSize(width: 95_600, height: 44_000)
        let rect = CGRect(x: 28_500, y: 0, width: 38_600, height: 32_600)
        XCTAssertNotNil(DuelLobbyFraming(size: size, visibleRect: rect, margin: 800))
    }

    private var fixtures: [(CGSize, CGRect)] {
        [(CGSize(width: 956, height: 440), CGRect(x: 285, y: 0, width: 386, height: 326)),
         (CGSize(width: 844, height: 390), CGRect(x: 264, y: 0, width: 316, height: 280)),
         (CGSize(width: 740, height: 360), CGRect(x: 238, y: 0, width: 264, height: 242)),
         (CGSize(width: 1024, height: 768), CGRect(x: 254, y: 0, width: 516, height: 630)),
         (CGSize(width: 1194, height: 834), CGRect(x: 274, y: 0, width: 646, height: 702))]
    }
}

