import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class DeepSeekChatClientTests: XCTestCase {
    private typealias Chat = DeepSeekChatClient
    private static let key = "example-key-not-real"
    private static let question: [Chat.Message] = [.init(role: .user, content: "测试问题")]

    func testStreamsOnlyVisibleContentSendsOnlyExplicitHistoryAndSelectedModel() async throws {
        let messages: [Chat.Message] = [
            .init(role: .user, content: "前一个问题"),
            .init(role: .assistant, content: "前一个回答"),
            .init(role: .user, content: "  写段代码\n")
        ]
        let stream = Chat.stream(messages: messages, apiKey: Self.key, model: .pro) { request, status, line in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(Self.key)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
            let raw = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody))
            let body = try XCTUnwrap(raw as? [String: Any])
            XCTAssertEqual(Set(body.keys), ["model", "messages", "stream", "max_tokens", "thinking"])
            XCTAssertEqual(body["model"] as? String, "deepseek-v4-pro")
            XCTAssertEqual(body["stream"] as? Bool, true)
            XCTAssertEqual(body["max_tokens"] as? Int, 4096)
            let sent = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertEqual(sent.map { $0["role"] }, messages.map { $0.role.rawValue })
            XCTAssertEqual(sent.map { $0["content"] }, messages.map(\.content))
            try status(200)
            try await line(": keep-alive")
            try await line(#"data: {"choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}"#)
            try await line(#"data: {"choices":[{"index":0,"delta":{"reasoning_content":"do not render"},"finish_reason":null}]}"#)
            try await line(#"data: {"choices":[{"index":0,"delta":{"content":"好的\n"},"finish_reason":null}]}"#)
            try await line(#"data: {"choices":[{"index":0,"delta":{"content":"print(1)"},"finish_reason":null}]}"#)
            try await line(#"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#)
            try await line(#"data: {"choices":[],"usage":{"total_tokens":22}}"#)
            try await line("data: [DONE]")
        }
        let chunks = try await Self.collect(stream)
        XCTAssertEqual(chunks, ["好的\n", "print(1)"])
    }

    func testDoesNotSendMissingKeyMalformedOrExcessHistory() async {
        let inputs: [(String, [Chat.Message], Chat.Failure)] = [
            ("", Self.question, .missingKey),
            ("test\ninvalid", Self.question, .missingKey),
            (Self.key, [], .invalidConversation),
            (Self.key, [.init(role: .user, content: " ")], .invalidConversation),
            (Self.key, [Self.question[0], Self.question[0]], .invalidConversation),
            (Self.key, [.init(role: .user, content: String(repeating: "字", count: 12_000))], .conversationTooLong)
        ]
        for (key, history, expected) in inputs {
            do {
                _ = try await Self.collect(Chat.stream(messages: history, apiKey: key) { _, _, _ in
                    XCTFail("Invalid request was sent")
                })
                XCTFail("Expected refusal")
            } catch let actual as Chat.Failure {
                XCTAssertEqual(actual, expected)
            } catch {
                XCTFail("Unexpected conversation validation error")
            }
        }
    }

    func testStatusMappingNeverEchoesProviderDetails() async {
        let cases: [(Int, Chat.Failure)] = [
            (307, .invalidResponse), (400, .invalidResponse), (401, .unauthorized), (403, .unauthorized),
            (402, .insufficientBalance), (429, .rateLimited), (503, .unavailable)
        ]
        for (http, failure) in cases {
            do {
                _ = try await Self.collect(Chat.stream(messages: Self.question, apiKey: Self.key) { _, status, line in
                    try status(http)
                    try await line("data: private response text")
                })
                XCTFail("Unexpected success for status \(http)")
            } catch let error as Chat.Failure {
                XCTAssertEqual(error, failure)
                XCTAssertFalse(error.localizedDescription.contains(Self.key))
            } catch {
                XCTFail("Unexpected status error")
            }
        }
    }

    func testMalformedTruncatedFilteredAndOverLimitResponsesAreNotCompleted() async {
        let cases: [([String], Chat.Failure)] = [
            (["data: {broken"], .invalidResponse),
            ([#"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#], .interrupted),
            ([#"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#, "data: [DONE]"], .invalidResponse),
            ([#"data: {"choices":[{"index":0,"delta":{},"finish_reason":"length"}]}"#, "data: [DONE]"], .outputLimit),
            ([#"data: {"choices":[{"index":0,"delta":{},"finish_reason":"content_filter"}]}"#, "data: [DONE]"], .filtered)
        ]
        for (lines, failure) in cases {
            do {
                _ = try await Self.collect(Chat.stream(messages: Self.question, apiKey: Self.key) { _, status, line in
                    try status(200)
                    for value in lines { try await line(value) }
                })
                XCTFail("Unexpected completion")
            } catch let error as Chat.Failure {
                XCTAssertEqual(error, failure)
            } catch {
                XCTFail("Unexpected invalid-response error")
            }
        }
    }

    func testTransportErrorsAreSanitized() async {
        let stream = Chat.stream(messages: Self.question, apiKey: Self.key) { _, _, _ in
            throw NSError(domain: "mock", code: 1, userInfo: [NSLocalizedDescriptionKey: Self.key])
        }
        do {
            _ = try await Self.collect(stream)
            XCTFail("Transport should fail")
        } catch let error as Chat.Failure {
            XCTAssertEqual(error, .network)
            XCTAssertFalse(error.localizedDescription.contains(Self.key))
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testConsumerCancellationStopsInFlightTransport() async {
        let started = expectation(description: "first visible delta arrived")
        let stopped = expectation(description: "transport cancelled")
        let stream = Chat.stream(messages: Self.question, apiKey: Self.key) { _, status, line in
            try status(200)
            try await line(#"data: {"choices":[{"index":0,"delta":{"content":"first"},"finish_reason":null}]}"#)
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                XCTFail("transport finished without cancellation")
            } catch is CancellationError {
                stopped.fulfill()
                throw CancellationError()
            }
        }
        let consumer = Task {
            for try await value in stream {
                XCTAssertEqual(value, "first")
                started.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 5)
        consumer.cancel()
        await fulfillment(of: [stopped], timeout: 5)
        _ = await consumer.result
    }

    private static func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var found: [String] = []
        for try await chunk in stream { found.append(chunk) }
        return found
    }
}
