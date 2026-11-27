import XCTest
@testable import ShiftCore

final class WuMindBackgroundVideoRecoveryTests: XCTestCase {
    func testOnlyOriginalManagedJobsCanBeQueried() {
        for status in ["queued", "pending", "processing", "running", "in_progress", "status_unknown", "completed"] {
            XCTAssertTrue(WuMindBackgroundVideoRecovery.canQuery(jobID: "VID-A123", channel: "managed", hasLocalAsset: false, status: status))
        }
        XCTAssertTrue(WuMindBackgroundVideoRecovery.canQuery(jobID: "VID-A123", channel: nil, hasLocalAsset: false, status: "completed"))
        for id in [nil, "", "VID-", "an-external-job"] {
            XCTAssertFalse(WuMindBackgroundVideoRecovery.canQuery(jobID: id, channel: "managed", hasLocalAsset: false, status: "queued"))
        }
    }

    func testNeverRequeryOwnKeyFailedOrAlreadyDownloadedWorks() {
        XCTAssertFalse(WuMindBackgroundVideoRecovery.canQuery(jobID: "VID-A", channel: "own_api", hasLocalAsset: false, status: "queued"))
        XCTAssertFalse(WuMindBackgroundVideoRecovery.canQuery(jobID: "VID-A", channel: "managed", hasLocalAsset: false, status: "failed"))
        XCTAssertFalse(WuMindBackgroundVideoRecovery.canQuery(jobID: "VID-A", channel: "managed", hasLocalAsset: true, status: "completed"))
    }
}
