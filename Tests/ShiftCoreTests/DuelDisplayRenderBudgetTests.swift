import XCTest
@testable import ShiftCore

final class DuelDisplayRenderBudgetTests: XCTestCase {
    func testTelevisionBoundsBothOrientationsAndRestoresNativePhone() throws {
        let television = try XCTUnwrap(DuelDisplayRenderBudget(
            size: CGSize(width: 3840, height: 2160), screenScale: 1, casting: true))
        XCTAssertEqual(television.drawableSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(television.scale, 0.5)
        XCTAssertEqual(television.samples, 1)
        let portrait = try XCTUnwrap(DuelDisplayRenderBudget(
            size: CGSize(width: 2160, height: 3840), screenScale: 2, casting: true))
        XCTAssertEqual(portrait.drawableSize, CGSize(width: 1080, height: 1920))
        let phone = try XCTUnwrap(DuelDisplayRenderBudget(
            size: CGSize(width: 956, height: 440), screenScale: 3, casting: false))
        XCTAssertEqual(phone.drawableSize, CGSize(width: 2868, height: 1320))
        XCTAssertEqual(phone.scale, 3)
        XCTAssertEqual(phone.samples, 2)
    }

    func testMirroringDoesNotRequirePointBoundsToChange() throws {
        let size = CGSize(width: 956, height: 440)
        let before = try XCTUnwrap(DuelDisplayRenderBudget(size: size, screenScale: 3, casting: false))
        let during = try XCTUnwrap(DuelDisplayRenderBudget(size: size, screenScale: 3, casting: true))
        XCTAssertEqual(during.drawableSize.width, 1920)
        XCTAssertEqual(during.drawableSize.height, 883)
        XCTAssertLessThan(during.drawableSize.width * during.drawableSize.height,
                          before.drawableSize.width * before.drawableSize.height / 2)
        XCTAssertEqual(DuelDisplayRenderBudget(size: size, screenScale: 3, casting: false), before)
    }

    func testShortEdgeLimitLetterboxingAndSmallScreensDoNotUpscale() throws {
        let square = try XCTUnwrap(DuelDisplayRenderBudget(
            size: CGSize(width: 2048, height: 2048), screenScale: 2, casting: true))
        XCTAssertEqual(square.drawableSize, CGSize(width: 1080, height: 1080))
        let small = try XCTUnwrap(DuelDisplayRenderBudget(
            size: CGSize(width: 640, height: 360), screenScale: 1, casting: true))
        XCTAssertEqual(small.drawableSize, CGSize(width: 640, height: 360))
        let ultrawide = try XCTUnwrap(DuelDisplayRenderBudget(
            size: CGSize(width: 3440, height: 1440), screenScale: 1, casting: true))
        XCTAssertEqual(ultrawide.drawableSize, CGSize(width: 1920, height: 803))
    }

    func testInvalidTransientGeometryNeverAllocatesTargets() {
        for size in [CGSize.zero, CGSize(width: -1, height: 1),
                     CGSize(width: CGFloat.nan, height: 1), CGSize(width: 1, height: CGFloat.infinity)] {
            XCTAssertNil(DuelDisplayRenderBudget(size: size, screenScale: 3, casting: true))
        }
        for scale in [CGFloat.zero, -1, .nan, .infinity] {
            XCTAssertNil(DuelDisplayRenderBudget(size: CGSize(width: 100, height: 100), screenScale: scale, casting: false))
        }
    }
}
