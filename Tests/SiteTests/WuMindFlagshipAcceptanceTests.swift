import AVFoundation
import XCTest
@testable import ShiftReminder

@MainActor
final class WuMindFlagshipAcceptanceTests: XCTestCase {
    func testLibraryTenderChecksAgainstTheOriginalPDF() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "henan-library-2025-1285", withExtension: "pdf"))
        let pdf = try Data(contentsOf: url)
        let quotes = [
            "投标报价不得超过招标文件中规定的预算金额或者最高限价，否则投标无效",
            "每提供一家得0.5分，满分得16分",
            "D包：2022年1月1日以来，每有一份已完成的类似图书项目采购业绩"
        ]
        let refs = quotes.map { ["location": "第999页", "quote": $0] }
        func completion(_ value: [String: Any]) throws -> Data {
            let json = try JSONSerialization.data(withJSONObject: value)
            return try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop",
                "message": ["content": String(decoding: json, as: UTF8.self)]]]])
        }
        let evidence = try completion(["outline": ["评标"], "excerpts": refs, "limitations": []])
        let rows = zip(["报价否决条款", "A/B 包出版社授权评分", "D 包业绩附件"], refs).map {
            ["requirement": $0.0, "source": $0.1, "response": "待补对应证明，未核实资格。", "status": "missing"] as [String: Any]
        }
        let draft = try completion(["title": "河南省图书馆投标核对", "sections": [
            ["title": "报价", "body": "待填写。", "sources": [refs[0]]] as [String: Any]],
            "requirements": rows, "missing_facts": ["出版社授权、合同及发票"], "warnings": []])
        let result = try await DeepSeekTenderClient.generate(data: pdf, filename: url.lastPathComponent, apiKey: "fixture") { request in
            let body: Data
            if request.url?.path == "/files" { body = Data(#"{"id":"file-api-library-fixture"}"#.utf8) }
            else if request.httpMethod == "DELETE" { body = Data(#"{"id":"file-api-library-fixture","deleted":true}"#.utf8) }
            else {
                let pro = String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("deepseek-v4-pro")
                body = pro ? draft : evidence
            }
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertEqual(result.draft.requirements.map { $0.source.reviewPDFPageIndex }, [15, 34, 36])
        XCTAssertTrue(result.draft.requirements.allSatisfy { $0.status == .missing && $0.source.verified })
    }

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
        works.reloadForCurrentAccount()
        let work = works.recordSubmittedTask(workType: .video, title: "样例", prompt: "样例", modelID: "sample",
                                             params: ["channel":"managed"], syncToCloud: false)
        let job = try await client.submitManagedVideo(gatewayURL: a, userToken: "offline-fixture", modelID: "sample",
                                                      prompt: "样例", seconds: 4, size: "1280x720")
        works.updateProgress(id: work.id, status: job.status, progress: 10, upstreamJobID: job.id,
                             videoJobOrigin: .init(gateway: a, accountID: wm.managedAccountID, jobID: job.id))
        wm.gatewayBaseURL = b
        works.reloadForCurrentAccount()
        let blocked = await works.refreshInProgressVideoWork(work, client: client, sessionToken: { "offline-fixture" })
        XCTAssertTrue(blocked?.errorMessage?.contains("切回") == true)
        wm.gatewayBaseURL = a
        works.reloadForCurrentAccount()
        let restored = await works.refreshInProgressVideoWork(work, client: client, sessionToken: { "offline-fixture" })
        XCTAssertEqual(restored?.upstreamJobID, job.id)
        XCTAssertEqual(restored?.status, "in_progress")
        let calls = await requests.calls
        XCTAssertEqual(calls, ["POST " + a + "/v1/videos", "GET " + a + "/v1/videos/VID-original"])
    }
}
