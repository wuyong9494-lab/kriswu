import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class AILiveProtocolTests: XCTestCase {
    private let ephemeral = "ek_fake_fixture"
    private let fixtureKey = "fake-personal-key"

    func testMintRequestUsesExactGAEndpointAndBriefTTL() throws {
        let model = try XCTUnwrap(AILiveProtocol.models.first)
        let request = try AILiveProtocol.tokenRequest(model: model, apiKey: fixtureKey)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/realtime/client_secrets")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(fixtureKey)")
        XCTAssertNil(request.value(forHTTPHeaderField: "OpenAI-Beta"))
        XCTAssertEqual(request.timeoutInterval, 30)
        let fields = try json(XCTUnwrap(request.httpBody))
        let expiry = try XCTUnwrap(fields["expires_after"] as? [String: Any])
        XCTAssertEqual(expiry["anchor"] as? String, "created_at")
        XCTAssertEqual(expiry["seconds"] as? Int, 60)
        let session = try XCTUnwrap(fields["session"] as? [String: Any])
        XCTAssertEqual(session["model"] as? String, "gpt-realtime-2.1")
        XCTAssertEqual(session["type"] as? String, "realtime")
    }

    func testTopLevelTokenParseAndNoFallbackToLongLivedAuth() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let active = Data(#"{"value":"ek_fake_fixture","expires_at":1060}"#.utf8)
        let expired = Data(#"{"value":"ek_fake_fixture","expires_at":1000}"#.utf8)
        let wrongKind = Data(#"{"value":"sk_secret_not_ephemeral","expires_at":1060}"#.utf8)
        XCTAssertEqual(try AILiveProtocol.parseToken(active, now: now), ephemeral)
        XCTAssertThrowsError(try AILiveProtocol.parseToken(expired, now: now)) {
            XCTAssertEqual($0 as? AILiveProtocolError, .expired)
        }
        XCTAssertThrowsError(try AILiveProtocol.parseToken(wrongKind, now: now)) {
            XCTAssertEqual($0 as? AILiveProtocolError, .malformedToken)
        }
        XCTAssertThrowsError(try AILiveProtocol.webSocketProtocols(token: "ek_fake, malformed")) {
            XCTAssertEqual($0 as? AILiveProtocolError, .malformedToken)
        }
    }

    func testWebSocketIsGAAndOnlyCarriesEphemeralSubprotocol() throws {
        let model = try XCTUnwrap(AILiveProtocol.models.last)
        let request = try AILiveProtocol.webSocketRequest(model: model, token: ephemeral)
        XCTAssertEqual(request.url?.absoluteString, "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1-mini")
        XCTAssertEqual(try AILiveProtocol.webSocketProtocols(token: ephemeral),
                       ["realtime", "openai-insecure-api-key.ek_fake_fixture"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"),
                       "realtime, openai-insecure-api-key.ek_fake_fixture")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "OpenAI-Beta"))
        XCTAssertEqual(request.timeoutInterval, 30)
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func testSessionUpdateSetsBothPCMFormatsAndServerBargeIn() throws {
        let fields = try json(AILiveProtocol.sessionUpdate())
        XCTAssertEqual(fields["type"] as? String, "session.update")
        let session = try XCTUnwrap(fields["session"] as? [String: Any])
        XCTAssertNil(session["model"]) // Model is negotiated, not changed mid-call.
        XCTAssertEqual(session["output_modalities"] as? [String], ["audio"])
        let audio = try XCTUnwrap(session["audio"] as? [String: [String: Any]])
        for direction in ["input", "output"] {
            let format = try XCTUnwrap(audio[direction]?["format"] as? [String: Any])
            XCTAssertEqual(format["type"] as? String, "audio/pcm")
            XCTAssertEqual(format["rate"] as? Int, 24_000)
        }
        let vad = try XCTUnwrap(audio["input"]?["turn_detection"] as? [String: Any])
        XCTAssertEqual(vad["type"] as? String, "server_vad")
        XCTAssertEqual(vad["create_response"] as? Bool, true)
        XCTAssertEqual(vad["interrupt_response"] as? Bool, true)
    }

    func testMicGateRequiresEchoedCorrectConfiguration() throws {
        XCTAssertEqual(try parse(#"{"type":"session.created"}"#), .sessionCreated)
        let ack = """
        {"type":"session.updated","session":{
          "type":"realtime","output_modalities":["audio"],"audio":{
            "input":{"format":{"type":"audio/pcm","rate":24000},"turn_detection":{
              "type":"server_vad","create_response":true,"interrupt_response":true}},
            "output":{"format":{"type":"audio/pcm","rate":24000}}}}}
        """
        XCTAssertEqual(try parse(ack), .sessionReady)
        XCTAssertThrowsError(try parse(ack.replacingOccurrences(of: "24000", with: "16000"))) {
            XCTAssertEqual($0 as? AILiveProtocolError, .invalidSession)
        }
        XCTAssertThrowsError(try parse(ack.replacingOccurrences(of: "\"interrupt_response\":true", with: "\"interrupt_response\":false"))) {
            XCTAssertEqual($0 as? AILiveProtocolError, .invalidSession)
        }
    }

    func testInputPCMAndPlayedDurationTruncation() throws {
        let samples = Data([0, 1, 2, 3])
        let append = try json(AILiveProtocol.appendPCM(samples))
        XCTAssertEqual(append["type"] as? String, "input_audio_buffer.append")
        XCTAssertEqual(append["audio"] as? String, "AAECAw==")
        for invalid in [Data(), Data([0]), Data(repeating: 0, count: AILiveProtocol.maximumPCMChunkBytes + 2)] {
            XCTAssertThrowsError(try AILiveProtocol.appendPCM(invalid)) {
                XCTAssertEqual($0 as? AILiveProtocolError, .invalidAudio)
            }
        }
        let truncate = try json(AILiveProtocol.truncate(itemID: "item_1", contentIndex: 0, audioEndMS: 1530))
        XCTAssertEqual(truncate["type"] as? String, "conversation.item.truncate")
        XCTAssertEqual(truncate["item_id"] as? String, "item_1")
        XCTAssertEqual(truncate["content_index"] as? Int, 0)
        XCTAssertEqual(truncate["audio_end_ms"] as? Int, 1530)
        XCTAssertThrowsError(try AILiveProtocol.truncate(itemID: "item_1", contentIndex: 0, audioEndMS: -1))
    }

    func testOnlyGAOutputEventsDecodeAndVADCancellationIsNormal() throws {
        XCTAssertEqual(try parse(#"{"type":"input_audio_buffer.speech_started"}"#), .userSpeechStarted)
        XCTAssertEqual(try parse(#"{"type":"input_audio_buffer.speech_stopped"}"#), .userSpeechStopped)
        XCTAssertEqual(try parse(#"{"type":"response.output_audio.delta","item_id":"item_1","content_index":0,"delta":"AAECAw=="}"#),
                       .audioChunk(Data([0, 1, 2, 3]), itemID: "item_1", contentIndex: 0))
        XCTAssertEqual(try parse(#"{"type":"response.output_audio.done","item_id":"item_1","content_index":0}"#),
                       .audioDone(itemID: "item_1", contentIndex: 0))
        XCTAssertThrowsError(try parse(#"{"type":"response.output_audio.done","content_index":0}"#)) {
            XCTAssertEqual($0 as? AILiveProtocolError, .invalidEvent)
        }
        XCTAssertEqual(try parse(#"{"type":"response.audio.delta"}"#), .unhandled)
        XCTAssertEqual(try parse(#"{"type":"response.done","response":{"status":"cancelled","status_details":{"reason":"turn_detected"}}}"#),
                       .responseDone)
        XCTAssertEqual(try parse(#"{"type":"response.done","response":{"status":"incomplete"}}"#), .failure(.responseIncomplete))
        XCTAssertThrowsError(try parse(#"{"type":"response.output_audio.delta","item_id":"item_1","content_index":0,"delta":"AA=="}"#)) {
            XCTAssertEqual($0 as? AILiveProtocolError, .invalidAudio)
        }
        XCTAssertThrowsError(try parse(#"{"type":"response.output_audio.delta","content_index":0,"delta":"AAECAw=="}"#)) {
            XCTAssertEqual($0 as? AILiveProtocolError, .invalidAudio)
        }
    }

    func testFailuresAndExpiredSessionExposeNoProviderText() throws {
        let remote = try parse(#"{"type":"error","error":{"type":"invalid_request_error","code":"session_expired","message":"contains user secret and audio account bits"}}"#)
        XCTAssertEqual(remote, .failure(.expired))
        guard case .failure(let failure) = remote else { return XCTFail("expected sanitized error") }
        XCTAssertFalse(failure.localizedDescription.contains("user secret"))
        XCTAssertEqual(try parse(#"{"type":"response.done","response":{"status":"failed","status_details":{"error":{"code":"insufficient_quota"}}}}"#),
                       .failure(.rateLimited))
        XCTAssertThrowsError(try parse("not json")) {
            XCTAssertEqual($0 as? AILiveProtocolError, .invalidEvent)
        }
        XCTAssertThrowsError(try AILiveProtocol.parse(Data(repeating: 0, count: AILiveProtocol.maximumServerEventBytes + 1))) {
            XCTAssertEqual($0 as? AILiveProtocolError, .invalidEvent)
        }
    }

    func testActiveGreetingPayloadAndAudioTextOutputModalitiesAccepted() throws {
        let greetingData = try AILiveProtocol.responseCreateGreeting("你好，今天想聊什么？")
        let obj = try json(greetingData)
        XCTAssertEqual(obj["type"] as? String, "response.create")
        let response = try XCTUnwrap(obj["response"] as? [String: Any])
        XCTAssertEqual(response["output_modalities"] as? [String], ["audio"])
        let instructions = try XCTUnwrap(response["instructions"] as? String)
        XCTAssertTrue(instructions.contains("你好，今天想聊什么？"))

        // Server returning ["audio", "text"] must also be accepted as .sessionReady
        let ackBoth = """
        {"type":"session.updated","session":{
          "type":"realtime","output_modalities":["audio","text"],"audio":{
            "input":{"format":{"type":"audio/pcm","rate":24000},"turn_detection":{
              "type":"server_vad","create_response":true,"interrupt_response":true}},
            "output":{"format":{"type":"audio/pcm","rate":24000}}}}}
        """
        XCTAssertEqual(try parse(ackBoth), .sessionReady)
        XCTAssertTrue(AILiveProtocol.models.contains(where: { $0.id == "gpt-realtime" }))
        XCTAssertTrue(AILiveProtocol.models.contains(where: { $0.id == "gpt-realtime-mini" }))
    }

    private func parse(_ value: String) throws -> AILiveProtocol.ServerEvent {
        try AILiveProtocol.parse(Data(value.utf8))
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
