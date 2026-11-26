import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The JSON wire protocol for the OpenAI Realtime GA WebSocket. This type does
/// not open a socket, record a microphone, retain credentials, or retry a call.
public enum AILiveProtocol {
    public struct Model: Identifiable, Hashable, Sendable {
        public let id: String
        public let displayName: String

        public init(id: String, displayName: String) {
            self.id = id
            self.displayName = displayName
        }
    }

    public static let models: [Model] = [
        Model(id: "gpt-realtime-2.1", displayName: "GPT Realtime 2.1"),
        Model(id: "gpt-realtime", displayName: "GPT Realtime (OpenAI / AIHubMix)"),
        Model(id: "gpt-realtime-mini", displayName: "GPT Realtime mini"),
        Model(id: "gpt-4o-realtime-preview", displayName: "GPT-4o Realtime Preview"),
        Model(id: "gpt-realtime-2.1-mini", displayName: "GPT Realtime 2.1 mini"),
    ]

    /// Signed 16-bit little-endian PCM, mono, at 24 kHz, without a WAV header.
    public static let sampleRate = 24_000
    public static let bytesPerSample = 2
    public static let maximumPCMChunkBytes = sampleRate * bytesPerSample * 2
    public static let maximumServerEventBytes = 256 * 1024
    private static let mintTTL = 60

    public enum ServerEvent: Equatable, Sendable {
        case unhandled
        case sessionCreated
        case sessionReady
        case userSpeechStarted
        case userSpeechStopped
        case audioChunk(Data, itemID: String, contentIndex: Int)
        /// Network output is complete; the app may still have playback queued.
        case audioDone(itemID: String, contentIndex: Int)
        case transcriptDelta(String)
        case transcriptDone
        case responseDone
        case failure(AILiveProtocolError)
    }

    /// The user's BYOK credential only authorizes an HTTPS mint, never the WebSocket.
    public static func tokenRequest(model: Model, apiKey: String) throws -> URLRequest {
        guard models.contains(model),
              let url = URL(string: "https://api.openai.com/v1/realtime/client_secrets")
        else { throw MultiProviderAIError.unsupportedModel }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try AIProviderToolHTTP.authorize(&request, provider: .openAI, apiKey: apiKey)
        var session = configuration()
        session["model"] = model.id
        request.httpBody = try encode([
            "expires_after": ["anchor": "created_at", "seconds": mintTTL],
            "session": session,
        ])
        return request
    }

    public static func parseToken(_ data: Data, now: Date = Date()) throws -> String {
        guard data.count <= maximumServerEventBytes,
              let reply = try? JSONDecoder().decode(ClientSecret.self, from: data),
              isEphemeralToken(reply.value) else { throw AILiveProtocolError.malformedToken }
        guard TimeInterval(reply.expiresAt) > now.timeIntervalSince1970
        else { throw AILiveProtocolError.expired }
        return reply.value
    }

    public static func webSocketRequest(model: Model, token: String) throws -> URLRequest {
        guard models.contains(model) else { throw MultiProviderAIError.unsupportedModel }
        let protocols = try webSocketProtocols(token: token)
        var parts = URLComponents()
        parts.scheme = "wss"
        parts.host = "api.openai.com"
        parts.path = "/v1/realtime"
        parts.queryItems = [URLQueryItem(name: "model", value: model.id)]
        guard let url = parts.url else { throw MultiProviderAIError.invalidRequest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpShouldHandleCookies = false
        request.setValue(protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        return request
    }

    /// Direct Bearer WebSocket request for AIHubMix (`wss://aihubmix.com/v1/realtime?model=...`)
    /// and WUMIND Managed Gateway (`wss://<gateway>/v1/realtime?model=...`).
    /// Never sets `Origin` or `openai-insecure-api-key` subprotocol (both rejected by AIHubMix).
    public static func directWebSocketRequest(model: Model, baseURL: String, bearerToken: String) throws -> URLRequest {
        let cleanToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty, cleanToken.utf8.count <= 512,
              cleanToken.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw MultiProviderAIError.invalidCredential
        }
        guard let normalized = try AIProvider.normalizedBaseURL(baseURL),
              let host = normalized.host, !host.isEmpty else {
            throw MultiProviderAIError.invalidRequest
        }
        var parts = URLComponents()
        parts.scheme = "wss"
        parts.host = host
        parts.port = normalized.port
        let trimmedPath = normalized.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.hasSuffix("v1/realtime") {
            parts.path = "/" + trimmedPath
        } else if trimmedPath.hasSuffix("v1") {
            parts.path = "/" + trimmedPath + "/realtime"
        } else if trimmedPath.isEmpty {
            parts.path = "/v1/realtime"
        } else {
            parts.path = "/" + trimmedPath + "/v1/realtime"
        }
        parts.queryItems = [URLQueryItem(name: "model", value: model.id)]
        guard let url = parts.url else { throw MultiProviderAIError.invalidRequest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// The Realtime guide documents this subprotocol for native/browser client secrets.
    /// Native URLSession can pass it through its URL + protocols initializer, rather than
    /// relying on a custom handshake header being preserved by a particular OS release.
    public static func webSocketProtocols(token: String) throws -> [String] {
        guard isEphemeralToken(token) else { throw AILiveProtocolError.malformedToken }
        return ["realtime", "openai-insecure-api-key." + token]
    }

    /// Send after session.created. Open the microphone only after session.updated.
    public static func sessionUpdate(omitNoiseReduction: Bool = false) throws -> Data {
        try encode(["type": "session.update", "session": configuration(omitNoiseReduction: omitNoiseReduction)])
    }

    /// Send ONCE after session.updated AND audio playback readiness so AI actively greets the user.
    public static func responseCreateGreeting(_ greeting: String = "你好，今天想聊什么？") throws -> Data {
        let trimmed = greeting.trimmingCharacters(in: .whitespacesAndNewlines)
        let phrase = trimmed.isEmpty ? "你好，今天想聊什么？" : trimmed
        return try encode([
            "type": "response.create",
            "response": [
                "output_modalities": ["audio"],
                "instructions": "通话已接通。请用自然温和的中文主动开场打招呼，直接说一句：「\(phrase)」",
            ],
        ])
    }

    public static func appendPCM(_ bytes: Data) throws -> Data {
        guard !bytes.isEmpty, bytes.count <= maximumPCMChunkBytes, bytes.count % bytesPerSample == 0
        else { throw AILiveProtocolError.invalidAudio }
        return try encode(["type": "input_audio_buffer.append", "audio": bytes.base64EncodedString()])
    }

    /// The caller stops local playback first, then passes the *played* duration,
    /// not the number of milliseconds received or enqueued, for this exact item.
    public static func truncate(itemID: String, contentIndex: Int, audioEndMS: Int) throws -> Data {
        guard isItemID(itemID), contentIndex >= 0, audioEndMS >= 0
        else { throw AILiveProtocolError.invalidEvent }
        return try encode([
            "type": "conversation.item.truncate",
            "item_id": itemID,
            "content_index": contentIndex,
            "audio_end_ms": audioEndMS,
        ])
    }

    public static func parse(_ message: Data) throws -> ServerEvent {
        guard message.count <= maximumServerEventBytes,
              let head = try? JSONDecoder().decode(EventHeader.self, from: message)
        else { throw AILiveProtocolError.invalidEvent }
        switch head.type {
        // session.created is not sufficient: wait for the requested PCM/VAD settings to be echoed.
        case "session.created": return .sessionCreated
        case "session.updated":
            guard let ack = try? JSONDecoder().decode(SessionAck.self, from: message),
                  (ack.session.type ?? "realtime") == "realtime",
                  (ack.session.outputModalities ?? ["audio"]).contains("audio"),
                  ack.session.audio.input.format == PCMFormat.expected,
                  ack.session.audio.output.format == PCMFormat.expected,
                  ack.session.audio.input.turnDetection?.type == "server_vad",
                  (ack.session.audio.input.turnDetection?.createResponse ?? true),
                  (ack.session.audio.input.turnDetection?.interruptResponse ?? true)
            else { throw AILiveProtocolError.invalidSession }
            return .sessionReady
        case "input_audio_buffer.speech_started": return .userSpeechStarted
        case "input_audio_buffer.speech_stopped": return .userSpeechStopped
        case "response.output_audio.delta":
            guard let delta = try? JSONDecoder().decode(DeltaEvent.self, from: message),
                  isItemID(delta.itemID), delta.contentIndex >= 0,
                  let pcm = Data(base64Encoded: delta.delta),
                  !pcm.isEmpty, pcm.count <= maximumPCMChunkBytes, pcm.count % bytesPerSample == 0
            else { throw AILiveProtocolError.invalidAudio }
            return .audioChunk(pcm, itemID: delta.itemID, contentIndex: delta.contentIndex)
        case "response.output_audio.done":
            guard let item = try? JSONDecoder().decode(AudioItem.self, from: message),
                  isItemID(item.itemID), item.contentIndex >= 0
            else { throw AILiveProtocolError.invalidEvent }
            return .audioDone(itemID: item.itemID, contentIndex: item.contentIndex)
        case "response.output_audio_transcript.delta", "response.output_text.delta":
            if let t = try? JSONDecoder().decode(TextDeltaEvent.self, from: message), !t.delta.isEmpty {
                return .transcriptDelta(t.delta)
            }
            return .unhandled
        case "response.output_audio_transcript.done", "response.output_text.done":
            return .transcriptDone
        case "response.done":
            guard let event = try? JSONDecoder().decode(ResponseDone.self, from: message)
            else { throw AILiveProtocolError.invalidEvent }
            // A normal barge-in triggers cancelled; this is not a service failure.
            switch event.response.status {
            case "completed", "cancelled": return .responseDone
            case "incomplete": return .failure(.responseIncomplete)
            case "failed": return .failure(sanitize(code: event.response.statusDetails?.error?.code))
            default: throw AILiveProtocolError.invalidEvent
            }
        case "error":
            let error = try? JSONDecoder().decode(ErrorEvent.self, from: message)
            return .failure(sanitize(code: error?.error.code, type: error?.error.type))
        default: return .unhandled
        }
    }

    private static func configuration(omitNoiseReduction: Bool = false) -> [String: Any] {
        let pcm: [String: Any] = ["type": "audio/pcm", "rate": sampleRate]
        let vad: [String: Any] = [
            "type": "server_vad", "threshold": 0.5, "prefix_padding_ms": 300, "silence_duration_ms": 500,
            "create_response": true, "interrupt_response": true,
        ]
        var inputAudio: [String: Any] = ["format": pcm, "turn_detection": vad]
        if !omitNoiseReduction {
            inputAudio["noise_reduction"] = ["type": "near_field"]
        }
        return [
            "type": "realtime",
            "output_modalities": ["audio"],
            "instructions": "你是实时语音助手。优先使用用户说话的语言，简明回答。",
            "audio": [
                "input": inputAudio,
                "output": ["format": pcm, "voice": "alloy"],
            ],
        ]
    }

    private static func encode(_ fields: [String: Any]) throws -> Data {
        do { return try JSONSerialization.data(withJSONObject: fields) }
        catch { throw AILiveProtocolError.invalidEvent }
    }

    private static func isEphemeralToken(_ token: String) -> Bool {
        token.hasPrefix("ek_") && (8...512).contains(token.utf8.count) && token.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }

    private static func isItemID(_ itemID: String) -> Bool {
        !itemID.isEmpty && itemID.utf8.count <= 256 && itemID.utf8.allSatisfy { (33...126).contains($0) }
    }

    private static func sanitize(code: String?, type: String? = nil) -> AILiveProtocolError {
        switch code ?? type {
        case "session_expired", "token_expired", "expired_api_key": return .expired
        case "invalid_api_key", "invalid_token", "authentication_error": return .unauthorized
        case "permission_denied", "insufficient_permissions", "model_not_found", "realtime_disabled": return .unpermitted
        case "rate_limit_exceeded", "rate_limit_error", "insufficient_quota", "insufficient_user_quota": return .rateLimited
        default: return .serviceFailure
        }
    }

    private struct ClientSecret: Decodable {
        let value: String
        let expiresAt: Int
        enum CodingKeys: String, CodingKey { case value, expiresAt = "expires_at" }
    }

    private struct EventHeader: Decodable { let type: String }
    private struct TextDeltaEvent: Decodable { let delta: String }

    private struct PCMFormat: Decodable, Equatable {
        let type: String
        let rate: Int
        static let expected = PCMFormat(type: "audio/pcm", rate: AILiveProtocol.sampleRate)
    }

    private struct SessionAck: Decodable {
        struct Session: Decodable {
            struct Audio: Decodable {
                struct Input: Decodable {
                    struct TurnDetection: Decodable {
                        let type: String
                        let createResponse: Bool?
                        let interruptResponse: Bool?
                        enum CodingKeys: String, CodingKey {
                            case type, createResponse = "create_response", interruptResponse = "interrupt_response"
                        }
                    }
                    let format: PCMFormat
                    let turnDetection: TurnDetection?
                    enum CodingKeys: String, CodingKey { case format, turnDetection = "turn_detection" }
                }
                struct Output: Decodable { let format: PCMFormat }
                let input: Input
                let output: Output
            }
            let type: String?
            let outputModalities: [String]?
            let audio: Audio
            enum CodingKeys: String, CodingKey { case type, outputModalities = "output_modalities", audio }
        }
        let session: Session
    }

    private struct AudioItem: Decodable {
        let itemID: String
        let contentIndex: Int
        enum CodingKeys: String, CodingKey { case itemID = "item_id", contentIndex = "content_index" }
    }

    private struct DeltaEvent: Decodable {
        let itemID: String
        let contentIndex: Int
        let delta: String
        enum CodingKeys: String, CodingKey { case itemID = "item_id", contentIndex = "content_index", delta }
    }

    private struct ErrorBody: Decodable { let code: String?; let type: String? }
    private struct ErrorEvent: Decodable { let error: ErrorBody }

    private struct ResponseDone: Decodable {
        struct Response: Decodable {
            struct Details: Decodable { let error: ErrorBody? }
            let status: String
            let statusDetails: Details?
            enum CodingKeys: String, CodingKey { case status, statusDetails = "status_details" }
        }
        let response: Response
    }
}

public enum AILiveProtocolError: LocalizedError, Equatable, Sendable {
    case invalidAudio, invalidEvent, invalidSession, malformedToken, expired
    case unauthorized, unpermitted, rateLimited, responseIncomplete, serviceFailure

    public var errorDescription: String? {
        switch self {
        case .invalidAudio: return "实时通话的语音格式无效。"
        case .invalidEvent: return "无法读取实时通话事件。"
        case .invalidSession: return "服务商未确认所需语音设置，麦克风未开启。"
        case .malformedToken: return "未能取得实时通话的临时凭证。"
        case .expired: return "实时通话已过期，请重新开始。"
        case .unauthorized: return "实时通话授权失败，请检查 OpenAI API Key。"
        case .unpermitted: return "当前 API 项目不能使用所选实时语音模型。"
        case .rateLimited: return "已达到实时通话的用量或速率限制。"
        case .responseIncomplete: return "服务商未完成这次语音回复。"
        case .serviceFailure: return "实时语音服务返回错误，请稍后重试。"
        }
    }
}
