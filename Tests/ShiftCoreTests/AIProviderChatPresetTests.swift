import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShiftCore

final class AIProviderChatPresetTests: XCTestCase {
    func testFirstCallUsesPresetOnOfficialHostWithoutModelDiscovery() async throws {
        for provider in AIProvider.allCases {
            let preset = provider.defaultChatModel
            let credential = UUID().uuidString
            let client = MultiProviderAIClient { request in
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertNil(request.url?.query)
                let data = try XCTUnwrap(request.httpBody)
                let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let response: String
                switch provider {
                case .claude:
                    XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), credential)
                    response = #"{"content":[{"type":"text","text":"收到"}],"stop_reason":"end_turn"}"#
                case .gemini:
                    XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/\(preset.id):generateContent")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), credential)
                    response = #"{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"收到"}]}}]}"#
                case .grok, .openAI:
                    let host = provider == .openAI ? "api.openai.com" : "api.x.ai"
                    XCTAssertEqual(request.url?.absoluteString, "https://\(host)/v1/responses")
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + credential)
                    response = #"{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"收到"}]}]}"#
                }
                if provider != .gemini {
                    XCTAssertEqual(payload["model"] as? String, preset.id)
                }
                let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(response.utf8), http)
            }
            let answer = try await client.send(provider: provider, model: preset, apiKey: credential,
                                               messages: [.init(role: .user, text: "请回复收到")])
            XCTAssertEqual(answer, "收到")
        }
    }

    func testNamedRelaysSubmitUsingTheirOwnPresetAndProtocol() async throws {
        for service in AICompatibleChatService.allCases where service != .openAI {
            let baseURL = try XCTUnwrap(service.baseURL)
            XCTAssertEqual(AICompatibleChatService.matching(baseURL + "/"), service)
            let credential = UUID().uuidString
            let client = MultiProviderAIClient { request in
                XCTAssertEqual(request.url?.absoluteString, baseURL + "/chat/completions")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + credential)
                let data = try XCTUnwrap(request.httpBody)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(json["model"] as? String, service.model.id)
                XCTAssertEqual(request.httpMethod, "POST")
                let response = Data(#"{"choices":[{"message":{"content":"收到"},"finish_reason":"stop"}]}"#.utf8)
                return (response, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let answer = try await client.send(provider: .openAI, model: service.model, apiKey: credential,
                                               messages: [.init(role: .user, text: "请回复收到")], baseURL: baseURL)
            XCTAssertEqual(answer, "收到")
        }
        XCTAssertNil(AICompatibleChatService.matching("https://openrouter.ai.example.org/api/v1"))
        XCTAssertNil(AICompatibleChatService.matching("https://openrouter.ai/separate-tenant"))
    }

}
