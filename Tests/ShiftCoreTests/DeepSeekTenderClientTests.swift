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
        let evidence = try Self.evidenceResponse()
        let modelReply = try Self.draftResponse(rowQuote: Self.genuineQuote)
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
                XCTAssertEqual(object["stream"] as? Bool, false)
                XCTAssertNil(object["tools"])
                XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(Self.key))
                let message = try XCTUnwrap((object["messages"] as? [[String: Any]])?.first)
                let thinking = try XCTUnwrap(object["thinking"] as? [String: String])
                if object["model"] as? String == "deepseek-flash" {
                    XCTAssertEqual(thinking["type"], "disabled")
                    XCTAssertNil(object["reasoning_effort"])
                    let parts = try XCTUnwrap(message["content"] as? [[String: String]])
                    XCTAssertEqual(parts.first?["type"], "file")
                    XCTAssertEqual(parts.first?["file_id"], Self.id)
                    XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("示例团队可提供培训"))
                    return Self.reply(evidence, for: request)
                }
                XCTAssertEqual(object["model"] as? String, "deepseek-v4-pro")
                XCTAssertEqual(thinking["type"], "enabled")
                XCTAssertEqual(object["reasoning_effort"] as? String, "max")
                XCTAssertEqual(object["max_tokens"] as? Int, 32_768)
                XCTAssertTrue((message["content"] as? String)?.contains("不虚构编号") == true)
                let payload = String(decoding: body, as: UTF8.self)
                XCTAssertTrue(payload.contains("示例团队可提供培训"))
                XCTAssertTrue(payload.contains(Self.genuineQuote))
                XCTAssertFalse(payload.contains(Self.fabricatedQuote))
                XCTAssertFalse(payload.contains("不能应转发的思考内容"))
                XCTAssertFalse(payload.contains(Self.id))
                XCTAssertFalse(payload.contains("file_id"))
                return Self.reply(modelReply, for: request)
            }
            XCTAssertNil(request.httpBody)
            return Self.reply(Self.deleted, for: request)
        }
        let requests = await calls.records
        XCTAssertEqual(requests, ["POST /files", "POST /chat/completions", "POST /chat/completions", "DELETE /files/\(Self.id)"])
        XCTAssertEqual(outcome.cleanup, .deleted)
        let credible = try XCTUnwrap(outcome.draft.sections.first?.sources.first)
        XCTAssertTrue(credible.verified)
        XCTAssertTrue(credible.location.hasPrefix("正文第 "))
        XCTAssertEqual(credible.reviewLocation, credible.location)
        XCTAssertFalse(credible.location.contains("999"), "Replaces false model location, not just attestation flag")
        XCTAssertTrue(outcome.draft.sections.first?.body.contains("待填写") == true)
        let missing = try XCTUnwrap(outcome.draft.requirements.first)
        XCTAssertTrue(missing.source.verified)
        XCTAssertEqual(missing.status, .drafted)
        XCTAssertFalse(outcome.draft.missingFacts.isEmpty)
        XCTAssertTrue(outcome.draft.warnings.contains(where: { $0.contains("未直接读取原文件") }))
    }

    func testOriginalPreviewPositionOnlyForLocallyMatchedCanonicalLocations() {
        func source(_ location: String, verified: Bool = true) -> Client.Source {
            .init(location: location, quote: Self.genuineQuote, verified: verified)
        }
        XCTAssertEqual(source("第 1 页（PDF 本机核对）").reviewPDFPageIndex, 0)
        XCTAssertEqual(source("第 250 页（PDF 本机核对）").reviewPDFPageIndex, 249)
        XCTAssertEqual(source("正文第 31 段（本机提取顺序）").reviewWordParagraph, 31)
        XCTAssertNil(source("第 1 页（PDF 本机核对）", verified: false).reviewPDFPageIndex)
        XCTAssertNil(source("正文第 31 段（本机提取顺序）", verified: false).reviewWordParagraph)
        XCTAssertNil(source("第 251 页（PDF 本机核对）").reviewPDFPageIndex)
        XCTAssertNil(source("第 0 页（PDF 本机核对）").reviewPDFPageIndex)
        XCTAssertNil(source("第 01 页（PDF 本机核对）").reviewPDFPageIndex)
        XCTAssertNil(source("第 1 页").reviewPDFPageIndex)
        XCTAssertNil(source("正文第 31 段（本机提取顺序）").reviewPDFPageIndex)
    }

    func testRefusesAllFabricatedQuotesWhenLocalTextAvailableAndCleansUp() async throws {
        let modelReply = try Self.evidenceResponse(quotes: [Self.fabricatedQuote])
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

    func testProCannotAddQuoteThatFlashDidNotProvide() async throws {
        let extraction = try Self.evidenceResponse(quotes: [Self.genuineQuote])
        let draft = try Self.draftResponse()
        let calls = Calls()
        do {
            _ = try await Client.generate(data: makeWordSource(), filename: "bid.docx", apiKey: Self.key) { request in
                await calls.add(request.httpMethod ?? "")
                switch request.url?.path {
                case "/files": return Self.reply(Self.uploaded, for: request)
                case "/chat/completions": return Self.reply(Self.isPro(request) ? draft : extraction, for: request)
                default: return Self.reply(Self.deleted, for: request)
                }
            }
            XCTFail("Expected unsupported source")
        } catch let failure as Client.Failure {
            XCTAssertEqual(failure.reason, .cannotVerifySources)
            XCTAssertEqual(failure.cleanup, .deleted)
        }
        let requests = await calls.records
        XCTAssertEqual(requests, ["POST", "POST", "POST", "DELETE"])
    }

    func testNoReadableLocalTextMarksAllClaimsUnverifiedAndWarnsOnCleanupFailure() async throws {
        let evidence = try Self.evidenceResponse()
        let response = try Self.draftResponse()
        let tinyFixture = Data("%PDF-1.4\n% Placeholder used only for mocked transport".utf8)
        let result = try await Client.generate(data: tinyFixture, filename: "scan.pdf", apiKey: Self.key) { request in
            switch request.url?.path {
            case "/files": return Self.reply(Self.uploaded, for: request)
            case "/chat/completions": return Self.reply(Self.isPro(request) ? response : evidence, for: request)
            default: return Self.reply(Data("not valid deletion".utf8), for: request, code: 503)
            }
        }
        XCTAssertEqual(result.cleanup, .expirationScheduled)
        XCTAssertNotNil(result.cleanup.notice)
        let excerpt = result.draft.sections[0].sources[0]
        XCTAssertFalse(excerpt.verified)
        XCTAssertNil(excerpt.reviewLocation)
        XCTAssertFalse(excerpt.location.contains("999"))
        XCTAssertFalse(result.draft.requirements[0].source.location.contains("555"))
        XCTAssertEqual(result.draft.requirements[0].status, .verify)
        XCTAssertTrue(result.draft.warnings.contains(where: { $0.contains("所有摘录") }))
    }

    func testRejectsEmptyMalformedUntrustedFileIDAndTruncatedDrafts() async throws {
        let source = try makeWordSource()
        let evidence = try Self.evidenceResponse(quotes: [Self.genuineQuote])
        let truncated = try Self.draftResponse(finish: "length")
        let cases: [(Data, Data, Data, Int)] = [
            (Data(#"{"id":"file-api-../../credentials"}"#.utf8), Data(), Data(), 1),
            (Self.uploaded, Data(), Data(), 3),
            (Self.uploaded, evidence, truncated, 4)
        ]
        for (upload, extraction, draft, count) in cases {
            let calls = Calls()
            do {
                _ = try await Client.generate(data: source, filename: "sample.docx", apiKey: Self.key) { request in
                    await calls.add(request.httpMethod ?? "")
                    switch request.url?.path {
                    case "/files": return Self.reply(upload, for: request)
                    case "/chat/completions": return Self.reply(Self.isPro(request) ? draft : extraction, for: request)
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

    func testCancelDuringProDraftDoesNotRetryAndStillDeletesOnce() async throws {
        let source = try makeWordSource()
        let extraction = try Self.evidenceResponse(quotes: [Self.genuineQuote])
        let proStarted = expectation(description: "Pro drafting began")
        let calls = Calls()
        let task = Task {
            try await Client.generate(data: source, filename: "bid.docx", apiKey: Self.key) { request in
                await calls.add(request.httpMethod ?? "")
                switch request.url?.path {
                case "/files": return Self.reply(Self.uploaded, for: request)
                case "/chat/completions" where Self.isPro(request):
                    proStarted.fulfill()
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    return Self.reply(Data(), for: request)
                case "/chat/completions": return Self.reply(extraction, for: request)
                default:
                    XCTAssertFalse(Task.isCancelled)
                    return Self.reply(Self.deleted, for: request)
                }
            }
        }
        await fulfillment(of: [proStarted], timeout: 4)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        let requests = await calls.records
        XCTAssertEqual(requests, ["POST", "POST", "POST", "DELETE"])
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

    private static func isPro(_ request: URLRequest) -> Bool {
        String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("deepseek-v4-pro")
    }

    private static func evidenceResponse(quotes: [String] = [genuineQuote, fabricatedQuote]) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: [
            "outline": ["售后方案"],
            "excerpts": quotes.map { ["location": "第999页", "quote": $0] },
            "limitations": ["覆盖范围仍待核实"]
        ])
        return try JSONSerialization.data(withJSONObject: [
            "choices": [["finish_reason": "stop", "message": [
                "content": String(decoding: json, as: UTF8.self), "reasoning_content": "不能应转发的思考内容"
            ]]]
        ])
    }

    private static func draftResponse(sectionQuote: String = genuineQuote, rowQuote: String = fabricatedQuote,
                                      finish: String = "stop") throws -> Data {
        let cited: [String: String] = ["location": "第999页", "quote": sectionQuote]
        let fabricated: [String: String] = ["location": "第555页", "quote": rowQuote]
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
