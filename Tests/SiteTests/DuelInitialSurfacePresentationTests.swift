import XCTest
@testable import ShiftReminder

final class DuelInitialSurfacePresentationTests: XCTestCase {
    func testLocalDrawableMissWaitsForDistinctDisplayCallbacks() {
        var first = DuelInitialSurfacePresentation()
        for frame in 0..<120 {
            XCTAssertEqual(first.action(offlineFrame: frame), .request)
            first.didRequest(offlineFrame: frame)
            // Layout, music preparation and the recursive retry can all run
            // before the next visible display callback.
            for _ in 0..<10 { XCTAssertEqual(first.action(offlineFrame: frame), .waitForDisplay) }
        }
        XCTAssertEqual(first.action(offlineFrame: 120), .request)
    }

    func testPausedNetworkPreparationRetainsItsBoundWithoutAClock() {
        var first = DuelInitialSurfacePresentation()
        for _ in 0..<3 {
            XCTAssertEqual(first.action(offlineFrame: nil), .request)
            first.didRequest(offlineFrame: nil)
        }
        XCTAssertEqual(first.action(offlineFrame: nil), .exhausted)
    }
}
