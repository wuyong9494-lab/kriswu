import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class DeepSeekTenderClientTests: XCTestCase {
    private typealias Client = DeepSeekTenderClient
    private static let key = "not-a-real-test-key"
    private static let id = "file-api-test-1234"
    private static let genuineQuote = "投标单位应提交售后方案说明"
    private static let fabricatedQuote = "测试用文件从未载有这个要求"

    func testUploadThenDraftThenCleanupAndMatchSourceLocally() async throws {
        let sourceFile = try makeWordSource()
        let modelReply = try Self.draftResponse()
        let calls = Calls()
        let outcome = try await Client.generate(data: sourceFile, filename: "synthetic-private-name.DOCX",
                                                facts: "示例团队可提供培训", apiKey: Self.key) { request in
            let method = request.httpMethod ?? ""
            let path = request.url?.path ?? ""
            await calls.add(method + " " + path)
            XCTAssertEqual(request.url?.host, "api.deepseek.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(Self.key)")
            if method == "POST" && path == "/files" {
                let body = try XCTUnwrap(request.httpBody)
                let decoded = String(decoding: body, as: UTF8.self)
                XCTAssertTrue(decoded.contains("filename=\"source.docx\""))
                XCTAssertFalse(decoded.contains("synthetic-private-name"))
                XCTAssertTrue(decoded.contains("expires_after[anchor]"))
                XCTAssertTrue(decoded.contains("expires_after[seconds]\"\r\n\r\n3600"))
                let purpose = try XCTUnwrap(decoded.range(of: "name=\"purpose\"\r\n\r\ntext_recognition"))
                let file = try XCTUnwrap(decoded.range(of: "name=\"file\""))
                XCTAssertLessThan(purpose.lowerBound, file.lowerBound)
                XCTAssertNotNil(body.range(of: sourceFile))
                return Self.reply(Self.uploaded, for: request)
            }
            if method == "POST" && path == "/chat/completions" {
                let body = try XCTUnwrap(request.httpBody)
                let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(object["model"] as? String, "deepseek-flash")
                XCTAssertEqual(object["stream"] as? Bool, false)
                XCTAssertNil(object["tools"])
                XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(Self.key))
                let message = try XCTUnwrap((object["messages"] as? [[String: Any]])?.first)
                let parts = try XCTUnwrap(message["content"] as? [[String: String]])
                XCTAssertEqual(parts.first?["type"], "file")
                XCTAssertEqual(parts.first?["file_id"], Self.id)
                XCTAssertTrue(parts.last?["text"]?.contains("示例团队可提供培训") == true)
                XCTAssertTrue(parts[1]["text"]?.contains("不虚构编号") == true)
                return Self.reply(modelReply, for: request)
            }
            XCTAssertNil(request.httpBody)
            return Self.reply(Self.deleted, for: request)
        }
        let requests = await calls.records
        XCTAssertEqual(requests, ["POST /files", "POST /chat/completions", "DELETE /files/\(Self.id)"])
        XCTAssertEqual(outcome.cleanup, .deleted)
        let credible = try XCTUnwrap(outcome.draft.sections.first?.sources.first)
        XCTAssertTrue(credible.verified)
        XCTAssertTrue(credible.location.hasPrefix("正文第 "))
        XCTAssertFalse(credible.location.contains("999"), "Replaces false model location, not just attestation flag")
        XCTAssertTrue(outcome.draft.sections.first?.body.contains("待填写") == true)
        let missing = try XCTUnwrap(outcome.draft.requirements.first)
        XCTAssertFalse(missing.source.verified)
        XCTAssertEqual(missing.status, .verify)
        XCTAssertFalse(outcome.draft.missingFacts.isEmpty)
        XCTAssertTrue(outcome.draft.warnings.contains(where: { $0.contains("部分摘录") }))
    }

    func testRefusesAllFabricatedQuotesWhenLocalTextAvailableAndCleansUp() async throws {
        let modelReply = try Self.draftResponse(sectionQuote: Self.fabricatedQuote)
        let calls = Calls()
        do {
            _ = try await Client.generate(data: makeWordSource(), filename: "bid.docx", apiKey: Self.key) { request in
                await calls.add(request.httpMethod ?? "")
                switch request.url?.path {
                case "/files": return Self.reply(Self.uploaded, for: request)
                case "/chat/completions": return Self.reply(modelReply, for: request)
                default: return Self.reply(Self.deleted, for: request)
                }
            }
            XCTFail("Expected unsupported source")
        } catch let failure as Client.Failure {
            XCTAssertEqual(failure.reason, .cannotVerifySources)
            XCTAssertEqual(failure.cleanup, .deleted)
        }
        let requests = await calls.records
        XCTAssertEqual(requests, ["POST", "POST", "DELETE"])
    }

    func testNoReadableLocalTextMarksAllClaimsUnverifiedAndWarnsOnCleanupFailure() async throws {
        let response = try Self.draftResponse()
        let tinyFixture = Data("%PDF-1.4\n% Placeholder used only for mocked transport".utf8)
        let result = try await Client.generate(data: tinyFixture, filename: "scan.pdf", apiKey: Self.key) { request in
            switch request.url?.path {
            case "/files": return Self.reply(Self.uploaded, for: request)
            case "/chat/completions": return Self.reply(response, for: request)
            default: return Self.reply(Data("not valid deletion".utf8), for: request, code: 503)
            }
        }
        XCTAssertEqual(result.cleanup, .expirationScheduled)
        XCTAssertNotNil(result.cleanup.notice)
        XCTAssertFalse(result.draft.sections[0].sources[0].verified)
        XCTAssertEqual(result.draft.requirements[0].status, .verify)
        XCTAssertTrue(result.draft.warnings.contains(where: { $0.contains("所有摘录") }))
    }

    func testRejectsEmptyMalformedUntrustedFileIDAndTruncatedDrafts() async throws {
        let source = try makeWordSource()
        let truncated = try Self.draftResponse(finish: "length")
        let cases: [(Data, Data, Int)] = [
            (Data(#"{"id":"file-api-../../credentials"}"#.utf8), Data(), 1),
            (Self.uploaded, Data(), 3),
            (Self.uploaded, truncated, 3)
        ]
        for (upload, draft, count) in cases {
            let calls = Calls()
            do {
                _ = try await Client.generate(data: source, filename: "sample.docx", apiKey: Self.key) { request in
                    await calls.add(request.httpMethod ?? "")
                    switch request.url?.path {
                    case "/files": return Self.reply(upload, for: request)
                    case "/chat/completions": return Self.reply(draft, for: request)
                    default: return Self.reply(Self.deleted, for: request)
                    }
                }
                XCTFail("Expected invalid response")
            } catch let failure as Client.Failure {
                XCTAssertEqual(failure.reason, .invalidResponse)
                XCTAssertEqual(failure.cleanup, count == 1 ? .expirationScheduled : .deleted)
            }
            let requests = await calls.records
            XCTAssertEqual(requests.count, count)
        }
    }

    func testInvalidLocalInputIsNeverSent() async throws {
        let pdf = Data("%PDF-1.4".utf8)
        let validations: [(Data, String, String, String, Client.Reason)] = [
            (pdf, "test.pdf", "", "", .missingKey),
            (pdf, "test.pdf", String(repeating: "x", count: Client.maxFactsBytes + 1), Self.key, .factsTooLong),
            (pdf, "test.xlsx", "", Self.key, .unsupportedFile),
            (Data([0x50, 0x4B, 0x03, 0x04]), "test.docx", "", Self.key, .unsupportedFile),
            (Data(repeating: 0, count: Client.maxFileBytes + 1), "test.pdf", "", Self.key, .fileTooLarge)
        ]
        for (data, name, notes, key, expected) in validations {
            do {
                _ = try await Client.generate(data: data, filename: name, facts: notes, apiKey: key) { request in
                    XCTFail("Validation should precede upload")
                    return Self.reply(Data(), for: request)
                }
                XCTFail("Expected validation failure")
            } catch let failure as Client.Failure {
                XCTAssertEqual(failure.reason, expected)
                XCTAssertNil(failure.cleanup)
            }
        }
    }

    func testStatusErrorsDoNotSurfacePrivatePayload() async throws {
        let input = try makeWordSource()
        for (code, expected): (Int, Client.Reason) in [(400, .uploadRejected), (401, .unauthorized),
                     (402, .insufficientBalance), (429, .rateLimited), (503, .unavailable)] {
            do {
                _ = try await Client.generate(data: input, filename: "test.docx", apiKey: Self.key) { request in
                    Self.reply(Data(Self.key.utf8), for: request, code: code)
                }
                XCTFail("Expected mapped status")
            } catch let error as Client.Failure {
                XCTAssertEqual(error.reason, expected)
                XCTAssertFalse(error.localizedDescription.contains(Self.key))
            }
        }
    }

    func testCancelAfterUploadDeletesExactlyOnce() async throws {
        let source = try makeWordSource()
        let generationStarted = expectation(description: "generation began")
        let calls = Calls()
        let task = Task {
            try await Client.generate(data: source, filename: "bid.docx", apiKey: Self.key) { request in
                switch request.url?.path {
                case "/files": return Self.reply(Self.uploaded, for: request)
                case "/chat/completions":
                    generationStarted.fulfill()
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    return Self.reply(Data(), for: request)
                default:
                    await calls.add(request.httpMethod ?? "")
                    XCTAssertFalse(Task.isCancelled, "Cleanup inherits no parent cancellation")
                    return Self.reply(Self.deleted, for: request)
                }
            }
        }
        await fulfillment(of: [generationStarted], timeout: 4)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            let requests = await calls.records
            XCTAssertEqual(requests, ["DELETE"])
        }
    }

    private func makeWordSource() throws -> Data {
        try TenderDOCXExporter.make(title: "合成采购文件", sections: [
            .init(title: "技术条款", body: "第一项：\(Self.genuineQuote)，并按要求整理。")
        ], reviewNotes: [])
    }

    private actor Calls {
        var records: [String] = []
        func add(_ value: String) { records.append(value) }
    }

    private static var uploaded: Data { Data("{\"id\":\"\(id)\"}".utf8) }
    private static var deleted: Data { Data("{\"id\":\"\(id)\",\"deleted\":true}".utf8) }

    private static func reply(_ data: Data, for request: URLRequest, code: Int = 200) -> (Data, URLResponse) {
        (data, HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }

    private static func draftResponse(sectionQuote: String = genuineQuote, finish: String = "stop") throws -> Data {
        let cited: [String: String] = ["location": "第999页", "quote": sectionQuote]
        let fabricated: [String: String] = ["location": "第555页", "quote": fabricatedQuote]
        let output: [String: Any] = [
            "title": "演示投标草稿",
            "sections": [["title": "售后方案", "body": "拟根据要求提供培训，【待填写：培训安排】。", "sources": [cited]]],
            "requirements": [["requirement": "示例条款", "response": "拟提供说明。", "status": "drafted", "source": fabricated]],
            "missing_facts": ["培训安排"],
            "warnings": []
        ]
        let json = try JSONSerialization.data(withJSONObject: output)
        return try JSONSerialization.data(withJSONObject: [
            "choices": [["finish_reason": finish, "message": ["content": String(decoding: json, as: UTF8.self)]]]
        ])
    }
}
