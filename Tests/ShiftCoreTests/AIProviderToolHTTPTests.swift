import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class AIProviderToolHTTPTests: XCTestCase {
    func testProviderCredentialsAndDestinationsAreBound() throws {
        for (provider, host, field, expected): (AIProvider, String, String, String) in [
            (.openAI, "api.openai.com", "Authorization", "Bearer dummy"),
            (.gemini, "generativelanguage.googleapis.com", "x-goog-api-key", "dummy"),
            (.claude, "api.anthropic.com", "x-api-key", "dummy"),
            (.grok, "api.x.ai", "Authorization", "Bearer dummy")
        ] {
            var request = URLRequest(url: try XCTUnwrap(URL(string: "https://\(host)/v1/test")))
            try AIProviderToolHTTP.authorize(&request, provider: provider, apiKey: " dummy ")
            XCTAssertEqual(request.value(forHTTPHeaderField: field), expected)
            XCTAssertFalse(request.url?.absoluteString.contains("dummy") ?? true)
        }

        for wrong in ["http://api.openai.com/v1", "https://api.openai.com.evil.invalid/v1",
                      "https://api.openai.com:444/v1", "https://user@api.openai.com/v1",
                      "https://api.openai.com/v1#fragment", "https://api.x.ai/v1"] {
            var request = URLRequest(url: try XCTUnwrap(URL(string: wrong)))
            XCTAssertThrowsError(try AIProviderToolHTTP.authorize(&request, provider: .openAI, apiKey: "dummy"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        }
    }

    func testRejectsBadDestinationsResponsesAndOversize() async throws {
        let good = try XCTUnwrap(URL(string: "https://api.openai.com/v1/images/generations"))
        let wrong = try XCTUnwrap(URL(string: "https://invalid.example/"))
        let request = URLRequest(url: good)

        for (url, status, count, expected): (URL, Int, Int, MultiProviderAIError) in [
            (wrong, 200, 1, .redirectBlocked),
            (good, 302, 1, .redirectBlocked),
            (good, 200, 17, .invalidResponse),
            (good, 429, 1, .rateLimited),
        ] {
            do {
                _ = try await AIProviderToolHTTP.data(for: request, provider: .openAI, maxBytes: 16) { req in
                    XCTAssertFalse(req.httpShouldHandleCookies)
                    return (Data(repeating: 0, count: count), try XCTUnwrap(
                        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)))
                }
                XCTFail("An invalid response must never be returned")
            } catch {
                XCTAssertEqual(error as? MultiProviderAIError, expected)
            }
        }
    }
}
