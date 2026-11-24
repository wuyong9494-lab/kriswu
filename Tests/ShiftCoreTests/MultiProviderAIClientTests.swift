import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class MultiProviderAIClientTests: XCTestCase {
    private let fixtureKey = "dummy-key-for-mocked-tests"

    func testOpenAIListsTextAndCatalogOnlyModelsAndDoesNotLeakKeyInURL() async throws {
        let client = MultiProviderAIClient { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer dummy-key-for-mocked-tests")
            XCTAssertEqual(request.httpMethod, "GET")
            return Self.reply(request, """
            {"data":[{"id":"gpt-6-sol"},{"id":"gpt-image-2"},{"id":"gpt-4o-audio-preview"},
             {"id":"text-embedding-3-small"},{"id":"gpt-6-sol"}, {"id":"ft:gpt-4.1-mini-2025-04-14:my-org:imagetags:demo"}]}
            """)
        }
        let actual = try await client.listModels(provider: .openAI, apiKey: fixtureKey)
        XCTAssertEqual(actual.filter(\.supportsTextChat).map(\.id),
                       ["ft:gpt-4.1-mini-2025-04-14:my-org:imagetags:demo", "gpt-6-sol"])
        XCTAssertEqual(actual.count, 5)
    }

    func testGeminiListsAllPagesAndUsesHeaderForKey() async throws {
        let client = MultiProviderAIClient { request in
            XCTAssertEqual(request.url?.host, "generativelanguage.googleapis.com")
            XCTAssertEqual(request.url?.path, "/v1beta/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "dummy-key-for-mocked-tests")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            switch URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems {
            case nil:
                return Self.reply(request, """
                {"models":[{"name":"models/gemini-flash","displayName":"Flash",
                  "supportedGenerationMethods":["generateContent"]}],"nextPageToken":"next&safe"}
                """)
            case let items?:
                XCTAssertEqual(items, [URLQueryItem(name: "pageToken", value: "next&safe")])
                return Self.reply(request, """
                {"models":[{"name":"models/embedding","supportedGenerationMethods":["embedContent"]},
                  {"name":"models/gemini-flash-image","supportedGenerationMethods":["generateContent"]}]}
                """)
            }
        }
        let actual = try await client.listModels(provider: .gemini, apiKey: fixtureKey)
        XCTAssertEqual(actual.first, AIProviderModel(id: "gemini-flash", displayName: "Flash", supportsTextChat: true))
        XCTAssertTrue(actual.dropFirst().allSatisfy { !$0.supportsTextChat })
        XCTAssertEqual(actual.count, 3)
    }

    func testClaudePaginationUsesStableAPIVersionAndAfterID() async throws {
        let client = MultiProviderAIClient { request in
            XCTAssertEqual(request.url?.host, "api.anthropic.com")
            XCTAssertEqual(request.url?.path, "/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "dummy-key-for-mocked-tests")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            if request.url?.query == nil {
                return Self.reply(request, """
                {"data":[{"id":"claude-latest","display_name":"Latest"}],"has_more":true,"last_id":"claude-latest"}
                """)
            }
            XCTAssertEqual(request.url?.query, "after_id=claude-latest")
            return Self.reply(request, """
            {"data":[{"id":"claude-smaller","display_name":"Smaller"}],"has_more":false,"last_id":"claude-smaller"}
            """)
        }
        let actual = try await client.listModels(provider: .claude, apiKey: fixtureKey)
        XCTAssertEqual(actual.map(\.id), ["claude-latest", "claude-smaller"])
        XCTAssertEqual(actual.map(\.displayName), ["Latest", "Smaller"])
        XCTAssertTrue(actual.allSatisfy(\.supportsTextChat))
    }

    func testClaudeRejectsMissingOrRepeatedPaginationCursor() async throws {
        for response in [#"{"data":[],"has_more":true}"#, #"{"data":[],"has_more":true,"last_id":"repeat"}"#] {
            let client = MultiProviderAIClient { Self.reply($0, response) }
            await assertError(.invalidCatalog) {
                _ = try await client.listModels(provider: .claude, apiKey: self.fixtureKey)
            }
        }
    }

    func testGrokUsesOfficialLanguageCapabilitiesAndRetainsSpecializedModels() async throws {
        let client = MultiProviderAIClient { request in
            XCTAssertEqual(request.url?.host, "api.x.ai")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer dummy-key-for-mocked-tests")
            switch request.url?.path {
            case "/v1/models":
                return Self.reply(request, """
                {"data":[{"id":"grok-future"},{"id":"grok-image","aliases":["image-latest"]}]}
                """)
            case "/v1/language-models":
                return Self.reply(request, """
                {"models":[{"id":"grok-future","input_modalities":["text","image"],
                 "output_modalities":["text"],"aliases":["grok-text-latest"]},
                {"id":"unlisted-language-model","input_modalities":["text"],"output_modalities":["text"]}]}
                """)
            default:
                XCTFail("Unexpected catalog endpoint")
                return Self.reply(request, "{}", 404)
            }
        }
        let actual = try await client.listModels(provider: .grok, apiKey: fixtureKey)
        XCTAssertEqual(actual.filter(\.supportsTextChat).map(\.id), ["grok-future", "grok-text-latest"])
        XCTAssertEqual(actual.filter { !$0.supportsTextChat }.map(\.id), ["grok-image", "image-latest"])
    }

    func testResponsesRoutesOpenAIAndGrokAndReturnsVisibleTextOnly() async throws {
        for (provider, host) in [(AIProvider.openAI, "api.openai.com"), (.grok, "api.x.ai")] {
            let client = MultiProviderAIClient { request in
                XCTAssertEqual(request.url?.host, host)
                XCTAssertEqual(request.url?.path, "/v1/responses")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer dummy-key-for-mocked-tests")
                let body = try Self.jsonBody(request)
                XCTAssertEqual(body["model"] as? String, "chosen")
                XCTAssertEqual(body["store"] as? Bool, false)
                XCTAssertNil(body["tools"])
                XCTAssertEqual((body["input"] as? [[String: String]])?.map { $0["content"] }, ["first", "previous", "new"])
                return Self.reply(request, """
                {"status":"completed","output":[{"type":"reasoning","summary":[{"type":"summary_text","text":"Reasoning"}]},
                {"type":"message","role":"assistant","content":[{"type":"output_text","text":"Right"},
                 {"type":"output_text","text":" answer"}]}]}
                """)
            }
            let result = try await client.send(provider: provider, model: textModel, apiKey: fixtureKey, messages: history)
            XCTAssertEqual(result, "Right answer")
        }
    }

    func testClaudeUsesMessagesAndIgnoresThinkingBlocks() async throws {
        let client = MultiProviderAIClient { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "dummy-key-for-mocked-tests")
            let json = try Self.jsonBody(request)
            XCTAssertEqual(json["max_tokens"] as? Int, 4096)
            XCTAssertEqual((json["messages"] as? [[String: String]])?.map { $0["role"] }, ["user", "assistant", "user"])
            return Self.reply(request, """
            {"content":[{"type":"thinking","thinking":"hidden"},{"type":"text","text":"visible"}],"stop_reason":"end_turn"}
            """)
        }
        let result = try await client.send(provider: .claude, model: textModel, apiKey: fixtureKey, messages: history)
        XCTAssertEqual(result, "visible")
    }

    func testGeminiUsesTheModelAliasAndNativeHistoryRoles() async throws {
        let client = MultiProviderAIClient { request in
            XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/chosen:generateContent")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "dummy-key-for-mocked-tests")
            let json = try Self.jsonBody(request)
            let entries = try XCTUnwrap(json["contents"] as? [[String: Any]])
            XCTAssertEqual(entries.compactMap { $0["role"] as? String }, ["user", "model", "user"])
            return Self.reply(request, """
            {"candidates":[{"finishReason":"STOP","content":{"parts":[{"thought":true,"text":"hidden"},{"text":"visible"}]}}]}
            """)
        }
        let result = try await client.send(provider: .gemini, model: textModel, apiKey: fixtureKey, messages: history)
        XCTAssertEqual(result, "visible")
    }

    func testErrorMessagesDoNotExposeRawBodiesAndRedirectsAreRejected() async throws {
        for (status, expected) in [
            (302, MultiProviderAIError.redirectBlocked), (401, .invalidCredential), (402, .quota), (403, .forbidden),
            (404, .unsupportedModel), (429, .rateLimited), (503, .unavailable), (418, .requestRejected(418))
        ] {
            let client = MultiProviderAIClient { Self.reply($0, "sensitive request text", status) }
            await assertError(expected) {
                _ = try await client.send(provider: .openAI, model: self.textModel, apiKey: self.fixtureKey,
                                          messages: self.history)
            }
            XCTAssertFalse(expected.localizedDescription.contains("sensitive request text"))
        }
    }

    func testInvalidInputsAreRejectedBeforeAnyNetworkRequest() async throws {
        let client = MultiProviderAIClient { request in
            XCTFail("Request must be rejected locally")
            return Self.reply(request, "{}", 404)
        }
        let injectedPath = AIProviderModel(id: "../files?key=fake", displayName: "Bad", supportsTextChat: true)
        let nonChat = AIProviderModel(id: "embed", displayName: "Embed", supportsTextChat: false)
        await assertError(.invalidRequest) {
            _ = try await client.send(provider: .gemini, model: injectedPath, apiKey: self.fixtureKey, messages: self.history)
        }
        await assertError(.unsupportedModel) {
            _ = try await client.send(provider: .openAI, model: nonChat, apiKey: self.fixtureKey, messages: self.history)
        }
        await assertError(.invalidCredential) {
            _ = try await client.listModels(provider: .grok, apiKey: "abc\nBad-Header")
        }
    }

    func testIncompleteGenerationIsNotPresentedAsSuccess() async throws {
        let client = MultiProviderAIClient { Self.reply($0, #"{"status":"incomplete","output":[]}"#) }
        await assertError(.replyIncomplete) {
            _ = try await client.send(provider: .openAI, model: self.textModel, apiKey: self.fixtureKey, messages: self.history)
        }
    }

    func testSendDetailedSurfacesReasoningAcrossProviders() async throws {
        let openAIClient = MultiProviderAIClient { request in
            Self.reply(request, """
            {"status":"completed","output":[{"type":"reasoning","summary":[{"type":"summary_text","text":"Step 1"}]},
            {"type":"message","role":"assistant","content":[{"type":"output_text","text":"Final"}]}]}
            """)
        }
        let oai = try await openAIClient.sendDetailed(provider: .openAI, model: textModel, apiKey: fixtureKey, messages: history)
        XCTAssertEqual(oai, AIProviderReply(answer: "Final", reasoning: "Step 1"))

        let claudeClient = MultiProviderAIClient { request in
            Self.reply(request, """
            {"content":[{"type":"thinking","thinking":"Claude CoT"},{"type":"text","text":"Claude Ans"}],"stop_reason":"end_turn"}
            """)
        }
        let claude = try await claudeClient.sendDetailed(provider: .claude, model: textModel, apiKey: fixtureKey, messages: history)
        XCTAssertEqual(claude, AIProviderReply(answer: "Claude Ans", reasoning: "Claude CoT"))

        let geminiClient = MultiProviderAIClient { request in
            Self.reply(request, """
            {"candidates":[{"finishReason":"STOP","content":{"parts":[{"thought":true,"text":"Gemini Thought"},{"text":"Gemini Ans"}]}}]}
            """)
        }
        let gemini = try await geminiClient.sendDetailed(provider: .gemini, model: textModel, apiKey: fixtureKey, messages: history)
        XCTAssertEqual(gemini, AIProviderReply(answer: "Gemini Ans", reasoning: "Gemini Thought"))
    }

    private var textModel: AIProviderModel {
        AIProviderModel(id: "chosen", displayName: "Chosen", supportsTextChat: true)
    }

    private var history: [AIProviderMessage] {
        [.init(role: .user, text: "first"), .init(role: .assistant, text: "previous"), .init(role: .user, text: "new")]
    }

    private static func reply(_ request: URLRequest, _ json: String, _ status: Int = 200) -> (Data, URLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private static func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func assertError(_ expected: MultiProviderAIError, using operation: () async throws -> Void,
                             file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? MultiProviderAIError, expected, file: file, line: line)
        }
    }
}
