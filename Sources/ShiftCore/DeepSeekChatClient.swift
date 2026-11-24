import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Opt-in, text-only DeepSeek client. The caller explicitly supplies the current chat's messages.
public enum DeepSeekChatClient {
    public enum Role: String, Codable, Sendable {
        case user, assistant
    }

    public struct Message: Codable, Equatable, Sendable {
        public let role: Role
        public let content: String

        public init(role: Role, content: String) {
            self.role = role
            self.content = content
        }
    }

    /// Incremental stream token separating DeepSeek chain-of-thought (`reasoning_content`) from final answer (`content`).
    public enum StreamEvent: Equatable, Sendable {
        case reasoning(String)
        case content(String)
    }

    public enum Model: String, CaseIterable, Identifiable, Sendable {
        case flash = "deepseek-flash"
        case pro = "deepseek-v4-pro"

        public var id: String { rawValue }
        public var title: String { self == .flash ? "DeepSeek Flash · 快速" : "DeepSeek V4 Pro · 旗舰" }
        public var shortTitle: String { self == .flash ? "DeepSeek Flash" : "DeepSeek V4 Pro" }
    }

    public enum Thinking: String, CaseIterable, Identifiable, Sendable {
        case normal, deep

        public var id: String { rawValue }
        public var title: String { self == .deep ? "深度思考" : "普通" }
        var enabled: Bool { self == .deep }
    }

    public enum Failure: LocalizedError, Equatable, Sendable {
        case missingKey, invalidConversation, conversationTooLong
        case unauthorized, insufficientBalance, rateLimited, unavailable, network
        case invalidResponse, interrupted, outputLimit, filtered

        public var errorDescription: String? {
            switch self {
            case .missingKey: return "请先在本机设置 DeepSeek API Key。"
            case .invalidConversation: return "对话内容为空或顺序不完整，请重新发送。"
            case .conversationTooLong: return "这次发送的文字太长，请缩短消息或新建对话。"
            case .unauthorized: return "DeepSeek API Key 无效或没有权限，请检查本机设置。"
            case .insufficientBalance: return "DeepSeek API 余额不足，请检查 DeepSeek 账户。"
            case .rateLimited: return "DeepSeek 当前请求太多，请稍后重试。"
            case .unavailable: return "DeepSeek 暂时不可用，请稍后重试。"
            case .network: return "连接 DeepSeek 失败，请检查网络后重试。"
            case .invalidResponse: return "DeepSeek 没有返回可读的回答，请重试。"
            case .interrupted: return "回答传输中断，请重试。"
            case .outputLimit: return "回答达到长度上限；可缩小问题后再试。"
            case .filtered: return "DeepSeek 未返回完整回答，请换一种问法。"
            }
        }
    }

    private static let responseWireLimit = 32 * 1024 * 1024
    private static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    typealias Transport = @Sendable (
        URLRequest,
        @escaping @Sendable (Int) throws -> Void,
        @escaping @Sendable (String) async throws -> Void
    ) async throws -> Void

    /// Streams only final visible answer deltas (backwards-compatible helper).
    public static func stream(messages: [Message], apiKey: String,
                              model: Model = .pro, thinking: Thinking = .deep,
                              systemPrompt: String? = nil) -> AsyncThrowingStream<String, Error> {
        stream(messages: messages, apiKey: apiKey, model: model, thinking: thinking, systemPrompt: systemPrompt,
               transport: { try await send($0, status: $1, line: $2) })
    }

    static func stream(messages: [Message], apiKey: String, model: Model = .pro, thinking: Thinking = .deep,
                       systemPrompt: String? = nil,
                       transport: @escaping Transport) -> AsyncThrowingStream<String, Error> {
        let events = streamEvents(messages: messages, apiKey: apiKey, model: model, thinking: thinking,
                                  systemPrompt: systemPrompt, transport: transport)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        if case .content(let delta) = event {
                            if case .terminated = continuation.yield(delta) { throw CancellationError() }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Streams both chain-of-thought reasoning (`reasoning_content`) and final answer (`content`) deltas live.
    public static func streamEvents(messages: [Message], apiKey: String,
                                    model: Model = .pro, thinking: Thinking = .deep,
                                    systemPrompt: String? = nil,
                                    extendedContext: Bool = false) -> AsyncThrowingStream<StreamEvent, Error> {
        streamEvents(messages: messages, apiKey: apiKey, model: model, thinking: thinking,
                     systemPrompt: systemPrompt, extendedContext: extendedContext,
                     transport: { try await send($0, status: $1, line: $2) })
    }

    static func streamEvents(messages: [Message], apiKey: String, model: Model = .pro, thinking: Thinking = .deep,
                             systemPrompt: String? = nil,
                             extendedContext: Bool = false,
                             transport: @escaping Transport) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    let request = try makeRequest(messages: messages, apiKey: apiKey, model: model,
                                                  thinking: thinking, systemPrompt: systemPrompt,
                                                  extendedContext: extendedContext)
                    let decoder = EventDecoder(continuation)
                    try await transport(request, { try checkStatus($0) }, { try await decoder.consume($0) })
                    try Task.checkCancellation()
                    try await decoder.validateCompletion()
                    continuation.finish()
                } catch let failure as Failure {
                    continuation.finish(throwing: failure)
                } catch {
                    if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                        continuation.finish(throwing: CancellationError())
                    } else {
                        // Never display or record request headers, raw bodies or provider/network errors.
                        continuation.finish(throwing: Failure.network)
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private struct WireMessage: Encodable {
        let role: String
        let content: String
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [WireMessage]
        let stream = true
        let max_tokens: Int
        let thinking: [String: String]
        let reasoning_effort: String
    }

    private static func makeRequest(messages: [Message], apiKey: String, model: Model,
                                    thinking: Thinking, systemPrompt: String?,
                                    extendedContext: Bool = false) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 512, key.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw Failure.missingKey
        }
        let maxMessages = extendedContext ? 240 : 40
        let maxSingleBytes = extendedContext ? 1_500_000 : 64_000
        let maxTotalBytes = extendedContext ? 4_000_000 : 128_000
        let maxSystemBytes = extendedContext ? 400_000 : 24_000

        guard messages.count <= maxMessages else { throw Failure.conversationTooLong }
        guard !messages.isEmpty, messages.last?.role == .user else { throw Failure.invalidConversation }
        var byteCount = 0
        for (index, message) in messages.enumerated() {
            let expected: Role = index.isMultiple(of: 2) ? .user : .assistant
            guard message.role == expected,
                  !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Failure.invalidConversation
            }
            let count = message.content.utf8.count
            guard count <= maxSingleBytes else { throw Failure.conversationTooLong }
            byteCount += count
            guard byteCount <= maxTotalBytes else { throw Failure.conversationTooLong }
        }

        var wireMessages: [WireMessage] = []
        if let sys = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !sys.isEmpty {
            let bounded = sys.utf8.count > maxSystemBytes ? String(sys.prefix(maxSystemBytes / 3)) : sys
            wireMessages.append(WireMessage(role: "system", content: bounded))
        }
        wireMessages.append(contentsOf: messages.map { WireMessage(role: $0.role.rawValue, content: $0.content) })

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = thinking.enabled ? 180 : 100
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: model.rawValue, messages: wireMessages, max_tokens: thinking.enabled ? 32_768 : 8_192,
            thinking: ["type": thinking.enabled ? "enabled" : "disabled"],
            reasoning_effort: thinking.enabled ? "max" : "none"))
        return request
    }

    private static func checkStatus(_ code: Int) throws {
        switch code {
        case 200: return
        case 401, 403: throw Failure.unauthorized
        case 402: throw Failure.insufficientBalance
        case 429: throw Failure.rateLimited
        case 500...599: throw Failure.unavailable
        default: throw Failure.invalidResponse
        }
    }

    private static func send(_ request: URLRequest, status: @escaping @Sendable (Int) throws -> Void,
                             line: @escaping @Sendable (String) async throws -> Void) async throws {
        let settings = URLSessionConfiguration.ephemeral
        settings.httpShouldSetCookies = false
        settings.httpCookieStorage = nil
        settings.urlCache = nil
        settings.urlCredentialStorage = nil
        settings.timeoutIntervalForResource = request.timeoutInterval == 180 ? 600 : 240
        let session = URLSession(configuration: settings, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        #if canImport(Darwin)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        try status(http.statusCode)
        for try await eventLine in bytes.lines {
            try Task.checkCancellation()
            try await line(eventLine)
        }
        #else
        // swift-corelibs-foundation doesn't expose URLSession.AsyncBytes. The protocol parser
        // remains shared; production on iOS uses the incremental path above.
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        try status(http.statusCode)
        guard data.count <= responseWireLimit, let responseText = String(data: data, encoding: .utf8) else {
            throw Failure.invalidResponse
        }
        for eventLine in responseText.components(separatedBy: .newlines) {
            try Task.checkCancellation()
            try await line(eventLine)
        }
        #endif
    }

    private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let reasoning_content: String?
                let content: String?
            }
            let index: Int
            let delta: Delta
            let finish_reason: String?
        }
        let choices: [Choice]
    }

    private actor EventDecoder {
        private let continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
        private var finished: String?
        private var done = false
        private var reasoningBytes = 0
        private var contentBytes = 0
        private var totalBytes = 0

        init(_ continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) {
            self.continuation = continuation
        }

        func consume(_ line: String) throws {
            try Task.checkCancellation()
            guard !done, line.hasPrefix("data:") else { return } // comments, empty lines, SSE metadata
            let bytes = line.utf8.count
            totalBytes += bytes
            guard bytes <= 128_000, totalBytes <= DeepSeekChatClient.responseWireLimit else { throw Failure.invalidResponse }
            let value = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if value == "[DONE]" {
                done = true
                return
            }

            guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(value.utf8)) else {
                throw Failure.invalidResponse
            }
            if chunk.choices.isEmpty { return } // Optional usage-only chunk.
            guard chunk.choices.count == 1, let choice = chunk.choices.first, choice.index == 0 else {
                throw Failure.invalidResponse
            }
            if let reasoning = choice.delta.reasoning_content, !reasoning.isEmpty {
                guard finished == nil else { throw Failure.invalidResponse }
                reasoningBytes += reasoning.utf8.count
                if reasoningBytes <= 262_144 {
                    if case .terminated = continuation.yield(.reasoning(reasoning)) { throw CancellationError() }
                }
            }
            if let content = choice.delta.content, !content.isEmpty {
                guard finished == nil else { throw Failure.invalidResponse }
                contentBytes += content.utf8.count
                guard contentBytes <= 196_608 else { throw Failure.outputLimit }
                if case .terminated = continuation.yield(.content(content)) { throw CancellationError() }
            }
            if let reason = choice.finish_reason {
                guard finished == nil else { throw Failure.invalidResponse }
                finished = reason
            }
        }

        func validateCompletion() throws {
            guard done, let finished else { throw Failure.interrupted }
            switch finished {
            case "stop": guard contentBytes > 0 else { throw Failure.invalidResponse }
            case "length": throw Failure.outputLimit
            case "content_filter": throw Failure.filtered
            default: throw Failure.invalidResponse
            }
        }
    }
}
