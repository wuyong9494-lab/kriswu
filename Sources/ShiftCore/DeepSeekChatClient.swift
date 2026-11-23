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

    public enum Model: String, CaseIterable, Identifiable, Sendable {
        case flash = "deepseek-flash"
        case pro = "deepseek-v4-pro"

        public var id: String { rawValue }
        public var title: String { self == .flash ? "Flash · 快速" : "V4 Pro · 复杂任务" }
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

    private static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    typealias Transport = @Sendable (
        URLRequest,
        @escaping @Sendable (Int) throws -> Void,
        @escaping @Sendable (String) async throws -> Void
    ) async throws -> Void

    public static func stream(messages: [Message], apiKey: String,
                              model: Model = .flash) -> AsyncThrowingStream<String, Error> {
        stream(messages: messages, apiKey: apiKey, model: model,
               transport: { try await send($0, status: $1, line: $2) })
    }

    static func stream(messages: [Message], apiKey: String, model: Model = .flash,
                       transport: @escaping Transport) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    let request = try makeRequest(messages: messages, apiKey: apiKey, model: model)
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

    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let stream = true
        let max_tokens = 4096
        let thinking = ["type": "disabled"]
    }

    private static func makeRequest(messages: [Message], apiKey: String, model: Model) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 512, key.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw Failure.missingKey
        }
        guard messages.count <= 40 else { throw Failure.conversationTooLong }
        guard !messages.isEmpty, messages.last?.role == .user else { throw Failure.invalidConversation }
        var byteCount = 0
        for (index, message) in messages.enumerated() {
            let expected: Role = index.isMultiple(of: 2) ? .user : .assistant
            guard message.role == expected,
                  !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Failure.invalidConversation
            }
            let count = message.content.utf8.count
            guard count <= 32_000 else { throw Failure.conversationTooLong }
            byteCount += count
            guard byteCount <= 128_000 else { throw Failure.conversationTooLong }
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 100
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(RequestBody(model: model.rawValue, messages: messages))
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
        settings.timeoutIntervalForResource = 240
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
        guard data.count <= 2_000_000, let responseText = String(data: data, encoding: .utf8) else {
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
            struct Delta: Decodable { let content: String? }
            let index: Int
            let delta: Delta
            let finish_reason: String?
        }
        let choices: [Choice]
    }

    private actor EventDecoder {
        private let continuation: AsyncThrowingStream<String, Error>.Continuation
        private var finished: String?
        private var done = false
        private var contentBytes = 0
        private var totalBytes = 0

        init(_ continuation: AsyncThrowingStream<String, Error>.Continuation) {
            self.continuation = continuation
        }

        func consume(_ line: String) throws {
            try Task.checkCancellation()
            guard !done, line.hasPrefix("data:") else { return } // comments, empty lines, SSE metadata
            let bytes = line.utf8.count
            totalBytes += bytes
            guard bytes <= 128_000, totalBytes <= 2_000_000 else { throw Failure.invalidResponse }
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
            if let content = choice.delta.content, !content.isEmpty {
                guard finished == nil else { throw Failure.invalidResponse }
                contentBytes += content.utf8.count
                guard contentBytes <= 128_000 else { throw Failure.outputLimit }
                if case .terminated = continuation.yield(content) { throw CancellationError() }
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
