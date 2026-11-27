import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class WuMindBackgroundVideoRecoveryTests: XCTestCase {
    func testReopenAcrossGatewayAndAccountSwitch() async throws {
        actor Requests {
            var calls: [String] = []
            func record(_ request: URLRequest) {
                calls.append((request.httpMethod ?? "") + " " + (request.url?.absoluteString ?? ""))
            }
        }
        let requests = Requests()
        let client = WuMindGatewayClient(dataTransport: { request in
            await requests.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"id":"VID-original","model":"fixture","status":"queued"}"#.utf8), response)
        }, streamTransport: { _, _, _ in XCTFail("Unexpected stream") })
        let a = "https://worker.example/a"
        let b = "https://worker.example/b"
        let accepted = try await client.submitManagedVideo(gatewayURL: a, userToken: "fixture", modelID: "fixture",
                                                           prompt: "日出", seconds: 4, size: "1280x720")
        let record = try XCTUnwrap(WuMindVideoJobOrigin(gateway: a, accountID: "user-A", jobID: accepted.id))
        let restored = try JSONDecoder().decode(WuMindVideoJobOrigin.self, from: JSONEncoder().encode(record))
        for (origin, gateway, account, id) in [
            (Optional(restored), b, "user-A", accepted.id), (restored, a, "user-B", accepted.id),
            (nil, a, "user-A", accepted.id), (restored, a, "user-A", "VID-other")
        ] {
            let blocked = try await WuMindBackgroundVideoRecovery.fetchOriginalStatus(
                origin: origin, gateway: gateway, accountID: account, jobID: id, token: "fixture", client: client)
            XCTAssertNil(blocked)
        }
        let status = try await WuMindBackgroundVideoRecovery.fetchOriginalStatus(
            origin: restored, gateway: a + "/", accountID: "user-A", jobID: accepted.id, token: "fixture", client: client)
        XCTAssertEqual(status?.id, accepted.id)
        let calls = await requests.calls
        XCTAssertEqual(calls, ["POST " + a + "/v1/videos", "GET " + a + "/v1/videos/VID-original"])
    }

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
