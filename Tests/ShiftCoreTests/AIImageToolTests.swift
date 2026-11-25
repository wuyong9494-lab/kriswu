import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class AIImageToolTests: XCTestCase {
    private static let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4H5EGAAQXAb41vZwdAAAAAElFTkSuQmCC"
    private static let jpeg = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwC5RRRXmH6Sf//Z"

    func testOpenAIRoutesImagePromptOnlyAndDecodesPNG() async throws {
        let model = try Self.model(.openAI)
        let tool = AIImageTool { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/images/generations")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
            let body = try Self.body(request)
            XCTAssertEqual(body["model"] as? String, "gpt-image-2")
            XCTAssertEqual(body["n"] as? Int, 1)
            XCTAssertEqual(body["prompt"] as? String, "sunrise")
            XCTAssertEqual(body["output_format"] as? String, "png")
            XCTAssertNil(body["response_format"])
            XCTAssertNil(body["messages"])
            return Self.reply(request, """
            {"data":[{"b64_json":"\(Self.png)"}]}
            """)
        }
        let data = try await tool.generate(model: model, apiKey: "fixture-key", prompt: " sunrise ")
        XCTAssertEqual(data, Data(base64Encoded: Self.png))
    }

    func testOpenAIImageVariantsUseSameVerifiedEndpoint() async throws {
        for id in ["gpt-image-2.6-flare", "gpt-image-2.6-sunburst"] {
            let model = try XCTUnwrap(AIImageTool.models.first { $0.provider == .openAI && $0.id == id })
            let tool = AIImageTool { request in
                XCTAssertEqual(request.url?.path, "/v1/images/generations")
                let body = try Self.body(request)
                XCTAssertEqual(body["model"] as? String, id)
                XCTAssertEqual(body["size"] as? String, "1024x1024")
                XCTAssertEqual(body["quality"] as? String, "medium")
                XCTAssertEqual(body["output_format"] as? String, "png")
                return Self.reply(request, """
                {"data":[{"b64_json":"\(Self.png)"}]}
                """)
            }
            let data = try await tool.generate(model: model, apiKey: "fixture-key", prompt: "sunrise")
            XCTAssertEqual(data, Data(base64Encoded: Self.png))
        }
    }

    func testGeminiReadsFirstFinalInlineImageNotExposedThoughtImage() async throws {
        let model = try Self.model(.gemini)
        let tool = AIImageTool { request in
            XCTAssertEqual(request.url?.absoluteString,
                           "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:generateContent")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "fixture-key")
            let body = try Self.body(request)
            let config = try XCTUnwrap(body["generationConfig"] as? [String: Any])
            XCTAssertEqual(config["responseModalities"] as? [String], ["IMAGE"])
            let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
            XCTAssertEqual((contents.first?["parts"] as? [[String: String]])?.first?["text"], "sunrise")
            return Self.reply(request, """
            {"candidates":[{"content":{"parts":[
              {"thought":true,"inlineData":{"mimeType":"image/png","data":"invalid"}},
              {"text":"image description"},
              {"inlineData":{"mimeType":"image/jpeg","data":"\(Self.jpeg)"}}
            ]}}]}
            """)
        }
        let data = try await tool.generate(model: model, apiKey: "fixture-key", prompt: "sunrise")
        XCTAssertEqual(data, Data(base64Encoded: Self.jpeg))
    }

    func testGrokRequestsBase64AndDecodesJPEG() async throws {
        let model = try Self.model(.grok)
        let tool = AIImageTool { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.x.ai/v1/images/generations")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
            let body = try Self.body(request)
            XCTAssertEqual(body["model"] as? String, "grok-imagine-image-2.0")
            XCTAssertEqual(body["n"] as? Int, 1)
            XCTAssertEqual(body["response_format"] as? String, "b64_json")
            XCTAssertNil(body["deferred"])
            return Self.reply(request, """
            {"data":[{"b64_json":"\(Self.jpeg)","mime_type":"image/jpeg"}]}
            """)
        }
        let data = try await tool.generate(model: model, apiKey: "fixture-key", prompt: "sunrise")
        XCTAssertEqual(data, Data(base64Encoded: Self.jpeg))
    }

    func testRejectsHostedURLsRatherThanFetchingThem() async throws {
        let tool = AIImageTool { request in
            XCTAssertEqual(request.url?.host, "api.x.ai")
            return Self.reply(request, #"{"data":[{"url":"https://example.com/should-not-fetch.png"}]}"#)
        }
        do {
            _ = try await tool.generate(model: Self.model(.grok), apiKey: "fixture-key", prompt: "sunrise")
            XCTFail("A URL is not an image result")
        } catch { XCTAssertEqual(error as? AIImageToolError, .noImage) }
    }

    func testRejectsTruncatedOversizedAndMislabeledImages() async throws {
        var oversized = try XCTUnwrap(Data(base64Encoded: Self.png))
        oversized.replaceSubrange(16...19, with: [0, 0, 16, 1]) // Width = 4097.
        let cases = [
            ("image/jpeg", Self.png),
            ("image/jpeg", String(Self.jpeg.dropLast(8))),
            ("image/png", oversized.base64EncodedString()),
            ("image/png", "aW52YWxpZA=="),
        ]
        for (mime, encoded) in cases {
            let tool = AIImageTool { request in
                Self.reply(request, """
                {"data":[{"mime_type":"\(mime)","b64_json":"\(encoded)"}]}
                """)
            }
            do {
                _ = try await tool.generate(model: Self.model(.grok), apiKey: "fixture-key", prompt: "sunrise")
                XCTFail("Invalid output should not reach the renderer")
            } catch { XCTAssertEqual(error as? AIImageToolError, .invalidImage) }
        }
    }

    func testEmptyOrOversizePromptCannotIncurAPICost() async throws {
        let tool = AIImageTool { request in
            XCTFail("Invalid prompt should never reach provider")
            return Self.reply(request, "{}")
        }
        for prompt in [" \n ", String(repeating: "字", count: 2667)] {
            do {
                _ = try await tool.generate(model: Self.model(.openAI), apiKey: "fixture-key", prompt: prompt)
                XCTFail("Invalid prompt should fail locally")
            } catch { XCTAssertEqual(error as? AIImageToolError, .invalidPrompt) }
        }
    }

    func testHTTPErrorDoesNotExposePromptOrCredential() async throws {
        let tool = AIImageTool { request in Self.reply(request, "provider echoes fixture-key and private text", status: 403) }
        do {
            _ = try await tool.generate(model: Self.model(.openAI), apiKey: "fixture-key", prompt: "private text")
            XCTFail("Permission denied should throw")
        } catch {
            XCTAssertEqual(error as? MultiProviderAIError, .forbidden)
            XCTAssertFalse(error.localizedDescription.contains("fixture-key"))
            XCTAssertFalse(error.localizedDescription.contains("private text"))
        }
    }

    func testFastStudioOptionsSendLowQualityCompressedJPEGAndPortraitSize() async throws {
        let model = try Self.model(.openAI)
        let tool = AIImageTool { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/images/generations")
            let body = try Self.body(request)
            XCTAssertEqual(body["quality"] as? String, "low")
            XCTAssertEqual(body["size"] as? String, "1024x1536")
            XCTAssertEqual(body["output_format"] as? String, "jpeg")
            XCTAssertEqual(body["output_compression"] as? Int, 80)
            return Self.reply(request, """
            {"data":[{"b64_json":"\(Self.jpeg)"}]}
            """)
        }
        let data = try await tool.generate(model: model, apiKey: "fixture-key", prompt: "portrait", options: .fastStudio)
        XCTAssertEqual(data, Data(base64Encoded: Self.jpeg))
    }

    func testHDUpgradeSendsHighQualityAcrossOpenAIGrokAndGemini() async throws {
        let hdLandscape = AIImageTool.Options(quality: .hd, aspectRatio: .landscape, outputFormat: .jpeg)

        // OpenAI HD
        let openAITool = AIImageTool { request in
            let body = try Self.body(request)
            XCTAssertEqual(body["quality"] as? String, "high")
            XCTAssertEqual(body["size"] as? String, "1536x1024")
            XCTAssertEqual(body["output_compression"] as? Int, 92)
            return Self.reply(request, #"{"data":[{"b64_json":"\#(Self.jpeg)"}]}"#)
        }
        _ = try await openAITool.generate(model: Self.model(.openAI), apiKey: "fixture-key", prompt: "alpine", options: hdLandscape)

        // Grok HD 2K
        let grokTool = AIImageTool { request in
            let body = try Self.body(request)
            XCTAssertEqual(body["quality"] as? String, "high")
            XCTAssertEqual(body["resolution"] as? String, "2k")
            XCTAssertEqual(body["aspect_ratio"] as? String, "3:2")
            return Self.reply(request, #"{"data":[{"b64_json":"\#(Self.jpeg)","mime_type":"image/jpeg"}]}"#)
        }
        _ = try await grokTool.generate(model: Self.model(.grok), apiKey: "fixture-key", prompt: "alpine", options: hdLandscape)

        // Gemini HD 2K
        let geminiTool = AIImageTool { request in
            let body = try Self.body(request)
            let gen = try XCTUnwrap(body["generationConfig"] as? [String: Any])
            let img = try XCTUnwrap(gen["imageConfig"] as? [String: Any])
            XCTAssertEqual(img["imageSize"] as? String, "2K")
            XCTAssertEqual(img["aspectRatio"] as? String, "3:2")
            return Self.reply(request, """
            {"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/jpeg","data":"\(Self.jpeg)"}}]}}]}
            """)
        }
        _ = try await geminiTool.generate(model: Self.model(.gemini), apiKey: "fixture-key", prompt: "alpine", options: hdLandscape)
    }

    func testOpenAIRelayRejectingCompressionFallsBackCleanlyToPNG() async throws {
        actor Counter {
            var calls = 0
            func next() -> Int { calls += 1; return calls }
        }
        let counter = Counter()
        let tool = AIImageTool { request in
            let attempt = await counter.next()
            let body = try Self.body(request)
            if attempt == 1 {
                XCTAssertEqual(body["output_format"] as? String, "jpeg")
                XCTAssertNotNil(body["output_compression"])
                return Self.reply(request, #"{"error":{"message":"unsupported output_compression"}}"#, status: 400)
            }
            XCTAssertEqual(body["output_format"] as? String, "png")
            XCTAssertNil(body["output_compression"])
            return Self.reply(request, #"{"data":[{"b64_json":"\#(Self.png)"}]}"#)
        }
        let data = try await tool.generate(model: Self.model(.openAI), apiKey: "fixture-key", prompt: "castle", options: .fastStudio)
        XCTAssertEqual(data, Data(base64Encoded: Self.png))
    }

    func testConcurrentBatchStreamsProgressiveResultsAndSurvivesPartialFailure() async throws {
        actor Tracker {
            var count = 0
            var streamed: [Int] = []
            func nextCall() -> Int { count += 1; return count }
            func record(_ idx: Int) { streamed.append(idx) }
            func allStreamed() -> [Int] { streamed }
        }
        let tracker = Tracker()
        let tool = AIImageTool { request in
            let call = await tracker.nextCall()
            if call == 2 {
                return Self.reply(request, #"{"error":"transient"}"#, status: 503)
            }
            return Self.reply(request, #"{"data":[{"b64_json":"\#(Self.jpeg)"}]}"#)
        }
        let results = try await tool.generateBatch(
            model: Self.model(.openAI),
            apiKey: "fixture-key",
            prompt: "elephant",
            count: 4,
            options: .fastStudio
        ) { slot in
            await tracker.record(slot.index)
        }
        XCTAssertEqual(results.count, 3)
        let streamedCount = await tracker.allStreamed().count
        XCTAssertEqual(streamedCount, 3)
    }

    func testCustomHTTPSRelayPinsHostAndBlocksHTTPDowngrade() async throws {
        let model = try Self.model(.openAI)
        let custom = AIImageTool.Options(
            quality: .fast,
            aspectRatio: .square,
            outputFormat: .jpeg,
            customBaseURL: "https://relay.example.com/v1"
        )
        let tool = AIImageTool { request in
            XCTAssertEqual(request.url?.absoluteString, "https://relay.example.com/v1/images/generations")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
            return Self.reply(request, #"{"data":[{"b64_json":"\#(Self.jpeg)"}]}"#)
        }
        let data = try await tool.generate(model: model, apiKey: "fixture-key", prompt: "nebula", options: custom)
        XCTAssertEqual(data, Data(base64Encoded: Self.jpeg))

        let insecure = AIImageTool.Options(customBaseURL: "http://relay.example.com/v1")
        do {
            _ = try await tool.generate(model: model, apiKey: "fixture-key", prompt: "nebula", options: insecure)
            XCTFail("HTTP custom relay must be rejected")
        } catch {
            XCTAssertEqual(error as? MultiProviderAIError, .invalidRequest)
        }
    }

    func testPreferredModelSelectsConfiguredProviderFirst() {
        let grokOnly = AIImageTool.preferredModel(configuredProviders: [.grok])
        XCTAssertEqual(grokOnly.provider, .grok)
        let geminiOnly = AIImageTool.preferredModel(configuredProviders: [.gemini])
        XCTAssertEqual(geminiOnly.provider, .gemini)
        let remembered = AIImageTool.preferredModel(configuredProviders: [.openAI, .grok], lastSelectedID: "grok-imagine-image-2.0")
        XCTAssertEqual(remembered.id, "grok-imagine-image-2.0")
    }

    private static func model(_ provider: AIProvider) throws -> AIImageTool.Model {
        try XCTUnwrap(AIImageTool.models.first { $0.provider == provider })
    }

    private static func body(_ request: URLRequest) throws -> [String: Any] {
        XCTAssertEqual(request.httpMethod, "POST")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private static func reply(_ request: URLRequest, _ json: String, status: Int = 200) -> (Data, URLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
