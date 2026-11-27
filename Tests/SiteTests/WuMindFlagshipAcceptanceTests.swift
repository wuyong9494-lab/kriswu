import AVFoundation
import XCTest
@testable import ShiftReminder

@MainActor
final class WuMindFlagshipAcceptanceTests: XCTestCase {
    func testFootageCutSubtitleAndSecondEditKeepOriginal() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "wumind-footage-fixture", withExtension: "mp4"))
        let original = try Data(contentsOf: url)
        let source = try WuMindFootageSource(copying: url)
        for (instruction, seconds) in [("删除第 1 到 2 秒，字幕改为「抵达」", 2.0), ("字幕改为「出发」", 3.0)] {
            let edit = try XCTUnwrap(WuMindFootageEdit(instruction: instruction))
            let data = try await WuMindFootageEditor.render(source: source, edit: edit)
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            defer { try? FileManager.default.removeItem(at: output) }
            try data.write(to: output)
            let asset = AVURLAsset(url: output)
            let duration = try await asset.load(.duration)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertEqual(duration.seconds, seconds, accuracy: 0.12)
            XCTAssertEqual(audio.count, 1)
            let (image, _) = try await AVAssetImageGenerator(asset: asset).image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
            XCTAssertEqual(image.width, 320)
            XCTAssertEqual(image.height, 180)
            XCTAssertEqual(try Data(contentsOf: source.url), original)
        }
    }

    func testWorkIndexReloadRefusesOtherGatewayAndReadsOriginalID() async throws {
        actor Requests {
            var calls: [String] = []
            func record(_ request: URLRequest) {
                calls.append((request.httpMethod ?? "") + " " + (request.url?.absoluteString ?? ""))
            }
        }
        let requests = Requests()
        let client = WuMindGatewayClient(dataTransport: { request in
            await requests.record(request)
            return (Data(#"{"id":"VID-original","model":"sample","status":"queued"}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, streamTransport: { _, _, _ in XCTFail("unexpected streaming request") })
        let wm = WuMindStore.shared
        let works = WuMindWorksStore.shared
        let a = "https://a.example.invalid/fixture"
        let b = "https://b.example.invalid/fixture"
        wm.gatewayBaseURL = a
        wm.managedAccountID = "fixture-" + UUID().uuidString
        XCTAssertTrue(Keychain.setWuMindGatewayUserToken("offline-fixture"))
        defer { _ = Keychain.setWuMindGatewayUserToken("") }
        works.reloadForCurrentAccount()
        let work = works.recordSubmittedTask(workType: .video, title: "样例", prompt: "样例", modelID: "sample",
                                             params: ["channel":"managed"], syncToCloud: false)
        let job = try await client.submitManagedVideo(gatewayURL: a, userToken: "offline-fixture", modelID: "sample",
                                                      prompt: "样例", seconds: 4, size: "1280x720")
        works.updateProgress(id: work.id, status: job.status, progress: 10, upstreamJobID: job.id,
                             videoJobOrigin: .init(gateway: a, accountID: wm.managedAccountID, jobID: job.id))
        wm.gatewayBaseURL = b
        works.reloadForCurrentAccount()
        let blocked = await works.refreshInProgressVideoWork(work, client: client)
        XCTAssertTrue(blocked?.errorMessage?.contains("切回") == true)
        wm.gatewayBaseURL = a
        works.reloadForCurrentAccount()
        let restored = await works.refreshInProgressVideoWork(work, client: client)
        XCTAssertEqual(restored?.upstreamJobID, job.id)
        XCTAssertEqual(restored?.status, "in_progress")
        let calls = await requests.calls
        XCTAssertEqual(calls, ["POST " + a + "/v1/videos", "GET " + a + "/v1/videos/VID-original"])
    }
}
