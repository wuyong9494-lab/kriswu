import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI, gemini, claude, grok

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI / GPT"
        case .gemini: return "Google Gemini"
        case .claude: return "Anthropic Claude"
        case .grok: return "xAI Grok"
        }
    }

    public var defaultBaseURLString: String { "https://\(apiHost)" }

    fileprivate var apiHost: String {
        switch self {
        case .openAI: return "api.openai.com"
        case .gemini: return "generativelanguage.googleapis.com"
        case .claude: return "api.anthropic.com"
        case .grok: return "api.x.ai"
        }
    }

    public static func normalizedBaseURL(_ raw: String?) throws -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "https",
              let host = comps.host, !host.isEmpty,
              comps.user == nil, comps.password == nil,
              comps.query == nil, comps.fragment == nil,
              let url = comps.url else {
            throw MultiProviderAIError.invalidRequest
        }
        return url
    }

    fileprivate func url(path: String, query: [URLQueryItem], baseURL: String? = nil) throws -> URL {
        if let custom = try Self.normalizedBaseURL(baseURL),
           var parts = URLComponents(url: custom, resolvingAgainstBaseURL: false) {
            var basePath = parts.path
            while basePath.hasSuffix("/") { basePath.removeLast() }
            var tail = path
            if !tail.hasPrefix("/") { tail = "/" + tail }
            for prefix in ["/v1beta", "/v1"] {
                if basePath.lowercased().hasSuffix(prefix), tail.lowercased().hasPrefix(prefix + "/") {
                    tail = String(tail.dropFirst(prefix.count))
                    break
                } else if basePath.lowercased().hasSuffix(prefix), tail.lowercased() == prefix {
                    tail = ""
                    break
                }
            }
            parts.path = basePath + tail
            parts.queryItems = query.isEmpty ? nil : query
            guard let resolved = parts.url else { throw MultiProviderAIError.invalidRequest }
            return resolved
        }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = apiHost
        parts.path = path
        parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url else { throw MultiProviderAIError.invalidRequest }
        return url
    }
}

public struct AIProviderModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let supportsTextChat: Bool

    public init(id: String, displayName: String, supportsTextChat: Bool) {
        self.id = id
        self.displayName = displayName
        self.supportsTextChat = supportsTextChat
    }
}

public struct AIProviderMessage: Sendable {
    public enum Role: String, Sendable { case user, assistant }
    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public struct AIProviderReply: Equatable, Sendable {
    public let answer: String
    public let reasoning: String?

    public init(answer: String, reasoning: String? = nil) {
        self.answer = answer
        self.reasoning = reasoning
    }
}

public enum MultiProviderAIError: LocalizedError, Equatable, Sendable {
    case missingKey, invalidRequest, invalidCredential, forbidden, quota, rateLimited
    case unavailable, unsupportedModel, invalidResponse, invalidCatalog, noAnswer, replyIncomplete
    case timedOut, networkError, redirectBlocked, requestRejected(Int)

    public var errorDescription: String? {
        switch self {
        case .missingKey: return "请先填写该服务商的 API 密钥。"
        case .invalidRequest: return "请求内容或模型编号无效。"
        case .invalidCredential: return "服务商未接受此 API 密钥，请在对应服务商检查密钥。"
        case .forbidden: return "此项目或 API 密钥没有调用权限，或该服务在当前地区不可用。"
        case .quota: return "该 API 项目余额或配额不足。"
        case .rateLimited: return "达到该 API 的速率或配额限制，请稍后重试或检查用量。"
        case .unavailable: return "该 AI 服务暂时不可用，请稍后重试。"
        case .unsupportedModel: return "该模型当前无法用于此 App 的文字对话，请刷新模型列表或另选模型。"
        case .invalidResponse: return "服务商返回了无法读取的响应。"
        case .invalidCatalog: return "未能完整读取服务商的模型目录，请重试。"
        case .noAnswer: return "服务商没有返回可显示的文字回答。"
        case .replyIncomplete: return "服务商未完整生成回答，请缩短问题或重试。"
        case .timedOut: return "连接服务商超时，请重试。"
        case .networkError: return "无法连接所选 AI 服务商，请检查网络。"
        case .redirectBlocked: return "服务商返回跳转；为保护 API 密钥，已停止请求。"
        case .requestRejected(let status): return "服务商拒绝了请求（HTTP \(status)）。"
        }
    }
}

public struct MultiProviderAIClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport

    public init() {
        self.transport = { request in
            try await SessionPool.shared.data(for: request)
        }
    }

    public init(transport: @escaping Transport) {
        self.transport = transport
    }

    /// Cleans common copy/paste noise ("Bearer ", quotes, zero-width spaces) in UI key inputs.
    public static func sanitizePastedKey(_ raw: String) -> String {
        let invisibles: Set<Unicode.Scalar> = [
            Unicode.Scalar(0x200B)!, Unicode.Scalar(0x200C)!, Unicode.Scalar(0x200D)!,
            Unicode.Scalar(0xFEFF)!, Unicode.Scalar(0x00A0)!
        ]
        var cleaned = String(raw.unicodeScalars.filter { !invisibles.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("bearer ") {
            cleaned = String(cleaned.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while (cleaned.hasPrefix("\"") && cleaned.hasSuffix("\""))
                || (cleaned.hasPrefix("'") && cleaned.hasSuffix("'")), cleaned.count >= 2 {
            cleaned = String(cleaned.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    /// Listing is a discovery call, not proof of generation access or remaining quota.
    /// OpenAI gives IDs without per-endpoint modalities; unknown/specialized IDs remain
    /// visible as catalog-only on the official host, while custom OpenAI-compatible relays
    /// allow third-party chat model IDs (e.g. OpenRouter / SiliconFlow / One-API).
    public func listModels(provider: AIProvider, apiKey: String, baseURL: String? = nil) async throws -> [AIProviderModel] {
        let hasCustomBase = (try AIProvider.normalizedBaseURL(baseURL)) != nil
        let models: [AIProviderModel]
        switch provider {
        case .openAI:
            let page = try await read(GeneralCatalog.self, provider: provider, path: "/v1/models",
                                      key: apiKey, baseURL: baseURL)
            models = page.data.map {
                let canChat = hasCustomBase ? Self.isRelayTextID($0.id) : Self.isOpenAITextID($0.id)
                return model($0, canChat: canChat)
            }
        case .gemini:
            var all: [AIProviderModel] = []
            var seen: Set<String> = []
            var cursor: String?
            repeat {
                let query = cursor.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? []
                let page = try await read(GeminiCatalog.self, provider: provider, path: "/v1beta/models",
                                          key: apiKey, query: query, baseURL: baseURL)
                all += page.models.map { item in
                    let id = String(item.name.dropFirst(item.name.hasPrefix("models/") ? 7 : 0))
                    let canChat = item.supportedGenerationMethods?.contains("generateContent") == true
                        && !Self.isNonTextGeminiID(id)
                    return AIProviderModel(id: id, displayName: item.displayName ?? id, supportsTextChat: canChat)
                }
                cursor = try Self.nextCursor(page.nextPageToken, seen: &seen)
            } while cursor != nil
            models = all
        case .claude:
            var all: [AIProviderModel] = []
            var seen: Set<String> = []
            var cursor: String?
            repeat {
                let query = cursor.map { [URLQueryItem(name: "after_id", value: $0)] } ?? []
                let page = try await read(GeneralCatalog.self, provider: provider, path: "/v1/models", key: apiKey,
                                          query: query, baseURL: baseURL)
                all += page.data.map { model($0, canChat: true) }
                guard page.hasMore != true || !(page.lastID ?? "").isEmpty else { throw MultiProviderAIError.invalidCatalog }
                cursor = try Self.nextCursor(page.hasMore == true ? page.lastID : nil, seen: &seen)
            } while cursor != nil
            models = all
        case .grok:
            // The generic catalog includes non-text offerings. The language endpoint adds exact
            // modalities and aliases when available, and gracefully falls back to /v1/models if unavailable.
            let complete = try await read(GeneralCatalog.self, provider: provider, path: "/v1/models",
                                          key: apiKey, baseURL: baseURL)
            let detail = try? await read(GrokLanguageCatalog.self, provider: provider, path: "/v1/language-models",
                                         key: apiKey, baseURL: baseURL)
            if let detail, !detail.models.isEmpty {
                let textRecords = detail.models.filter {
                    $0.inputModalities?.contains("text") == true && $0.outputModalities?.contains("text") == true
                }
                let textIDs = Set(textRecords.flatMap { [$0.id] + ($0.aliases ?? []) })
                let authorizedIDs = Set(complete.data.flatMap { [$0.id] + ($0.aliases ?? []) })
                let authorizedLanguageAliases = textRecords.filter { authorizedIDs.contains($0.id) }
                    .flatMap { $0.aliases ?? [] }
                let ids = authorizedIDs.union(authorizedLanguageAliases)
                models = ids.map { id in
                    AIProviderModel(id: id, displayName: id, supportsTextChat: textIDs.contains(id))
                }
            } else {
                let ids = Set(complete.data.flatMap { [$0.id] + ($0.aliases ?? []) })
                models = ids.map { id in
                    AIProviderModel(id: id, displayName: id, supportsTextChat: Self.isRelayTextID(id))
                }
            }
        }
        var ids: Set<String> = []
        return models.filter { !$0.id.isEmpty && ids.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.supportsTextChat != rhs.supportsTextChat { return lhs.supportsTextChat }
                return lhs.displayName == rhs.displayName ? lhs.id < rhs.id : lhs.displayName < rhs.displayName
            }
    }

    /// Explicit text-only user/assistant history. No tools, attachments, or system-provided app data.
    public func send(provider: AIProvider, model: AIProviderModel, apiKey: String,
                     messages: [AIProviderMessage], baseURL: String? = nil) async throws -> String {
        try await sendDetailed(provider: provider, model: model, apiKey: apiKey, messages: messages,
                               deepThinking: false, baseURL: baseURL).answer
    }

    /// Returns both final answer and optional chain-of-thought reasoning when the provider/model emits it.
    /// Automatically supports custom OpenAI-compatible relays (/v1/chat/completions) and gracefully retries
    /// without reasoning/thinking params if a specific model/org rejects them with HTTP 400.
    public func sendDetailed(provider: AIProvider, model: AIProviderModel, apiKey: String,
                             messages: [AIProviderMessage], deepThinking: Bool = false,
                             baseURL: String? = nil, systemPrompt: String? = nil) async throws -> AIProviderReply {
        guard model.supportsTextChat else { throw MultiProviderAIError.unsupportedModel }
        guard !model.id.isEmpty, messages.first?.role == .user, messages.last?.role == .user,
              messages.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw MultiProviderAIError.invalidRequest }
        let hasCustomBase = (try AIProvider.normalizedBaseURL(baseURL)) != nil
        let cleanSystem: String? = {
            guard let s = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s.utf8.count > 400_000 ? String(s.prefix(120_000)) : s
        }()
        let input = messages.map { ["role": $0.role.rawValue, "content": $0.text] }

        switch provider {
        case .openAI, .grok:
            if hasCustomBase {
                do {
                    return try await sendChatCompletions(provider: provider, model: model, apiKey: apiKey,
                                                         input: input, baseURL: baseURL, systemPrompt: cleanSystem)
                } catch let err as MultiProviderAIError where err == .unsupportedModel || err == .requestRejected(405) || err == .requestRejected(501) {
                    return try await sendResponses(provider: provider, model: model, apiKey: apiKey,
                                                   input: input, deepThinking: deepThinking,
                                                   baseURL: baseURL, systemPrompt: cleanSystem)
                }
            }
            do {
                return try await sendResponses(provider: provider, model: model, apiKey: apiKey,
                                               input: input, deepThinking: deepThinking,
                                               baseURL: baseURL, systemPrompt: cleanSystem)
            } catch let err as MultiProviderAIError where err == .unsupportedModel || err == .requestRejected(405) || err == .requestRejected(501) {
                do {
                    return try await sendChatCompletions(provider: provider, model: model, apiKey: apiKey,
                                                         input: input, baseURL: baseURL, systemPrompt: cleanSystem)
                } catch {
                    throw err
                }
            }
        case .claude:
            let useThinking = deepThinking && Self.supportsClaudeThinking(model.id)
            do {
                return try await sendClaude(model: model, apiKey: apiKey, input: input,
                                            useThinking: useThinking, baseURL: baseURL, systemPrompt: cleanSystem)
            } catch MultiProviderAIError.requestRejected(400) where useThinking {
                return try await sendClaude(model: model, apiKey: apiKey, input: input,
                                            useThinking: false, baseURL: baseURL, systemPrompt: cleanSystem)
            }
        case .gemini:
            guard model.id.utf8.allSatisfy({ byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                    || byte == 45 || byte == 95 || byte == 46
            }), model.id != ".", model.id != ".." else { throw MultiProviderAIError.invalidRequest }
            let contents: [[String: Any]] = messages.map { message in
                ["role": message.role == .user ? "user" : "model", "parts": [["text": message.text]]]
            }
            let useThinking = deepThinking && Self.supportsGeminiThinking(model.id)
            do {
                return try await sendGemini(model: model, apiKey: apiKey, contents: contents,
                                            useThinking: useThinking, baseURL: baseURL, systemPrompt: cleanSystem)
            } catch MultiProviderAIError.requestRejected(400) where useThinking {
                return try await sendGemini(model: model, apiKey: apiKey, contents: contents,
                                            useThinking: false, baseURL: baseURL, systemPrompt: cleanSystem)
            }
        }
    }

    private func sendResponses(provider: AIProvider, model: AIProviderModel, apiKey: String,
                               input: [[String: String]], deepThinking: Bool,
                               baseURL: String?, systemPrompt: String?) async throws -> AIProviderReply {
        let wantsReasoning = provider == .openAI && deepThinking && Self.supportsOpenAIReasoning(model.id)
        func run(withReasoning: Bool) async throws -> AIProviderReply {
            var payload: [String: Any] = ["model": model.id, "input": input, "store": false]
            if let systemPrompt {
                payload["instructions"] = systemPrompt
            }
            if withReasoning {
                payload["reasoning"] = ["effort": "medium", "summary": "auto"]
            }
            let response = try await read(ResponsesReply.self, provider: provider, path: "/v1/responses",
                                          key: apiKey, body: payload, baseURL: baseURL)
            if response.status == "incomplete" { throw MultiProviderAIError.replyIncomplete }
            if let status = response.status, status != "completed" { throw MultiProviderAIError.invalidResponse }
            var content: [String] = []
            var reasoning: [String] = []
            for item in response.output {
                if item.type == "reasoning" {
                    for s in item.summary ?? [] {
                        if let text = s.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            reasoning.append(text)
                        }
                    }
                    for part in item.content ?? [] {
                        if let text = part.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            reasoning.append(text)
                        }
                    }
                } else if item.type == "message" && item.role == "assistant" {
                    for part in item.content ?? [] {
                        if part.type == "output_text", let value = part.text { content.append(value) }
                        if part.type == "refusal", let value = part.refusal { content.append(value) }
                    }
                }
            }
            let answer = try Self.join(content)
            let joinedThought = reasoning.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return AIProviderReply(answer: answer, reasoning: joinedThought.isEmpty ? nil : joinedThought)
        }
        do {
            return try await run(withReasoning: wantsReasoning)
        } catch MultiProviderAIError.requestRejected(400) where wantsReasoning {
            return try await run(withReasoning: false)
        }
    }

    private func sendChatCompletions(provider: AIProvider, model: AIProviderModel, apiKey: String,
                                     input: [[String: String]], baseURL: String?,
                                     systemPrompt: String?) async throws -> AIProviderReply {
        var wireMessages = input
        if let systemPrompt {
            wireMessages.insert(["role": "system", "content": systemPrompt], at: 0)
        }
        let payload: [String: Any] = [
            "model": model.id,
            "messages": wireMessages,
            "stream": false
        ]
        let response = try await read(ChatCompletionsReply.self, provider: provider, path: "/v1/chat/completions",
                                      key: apiKey, body: payload, baseURL: baseURL)
        guard let choice = response.choices.first else { throw MultiProviderAIError.noAnswer }
        if choice.finishReason == "length" { throw MultiProviderAIError.replyIncomplete }
        let rawAnswer = choice.message?.resolvedText ?? ""
        let answer = try Self.join([rawAnswer])
        let rawThought = choice.message?.reasoningContent ?? choice.message?.reasoning ?? ""
        let trimmedThought = rawThought.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIProviderReply(answer: answer, reasoning: trimmedThought.isEmpty ? nil : trimmedThought)
    }

    private func sendClaude(model: AIProviderModel, apiKey: String, input: [[String: String]],
                            useThinking: Bool, baseURL: String?, systemPrompt: String?) async throws -> AIProviderReply {
        var payload: [String: Any] = ["model": model.id, "messages": input, "max_tokens": useThinking ? 8192 : 4096]
        if let systemPrompt {
            payload["system"] = systemPrompt
        }
        if useThinking {
            payload["thinking"] = ["type": "enabled", "budget_tokens": 2048]
        }
        let response = try await read(ClaudeReply.self, provider: .claude, path: "/v1/messages",
                                      key: apiKey, body: payload, baseURL: baseURL)
        if response.stopReason == "max_tokens" { throw MultiProviderAIError.replyIncomplete }
        let thought = response.content.compactMap { $0.type == "thinking" ? $0.thinking : nil }
            .joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = try Self.join(response.content.compactMap { $0.type == "text" ? $0.text : nil })
        return AIProviderReply(answer: answer, reasoning: thought.isEmpty ? nil : thought)
    }

    private func sendGemini(model: AIProviderModel, apiKey: String, contents: [[String: Any]],
                            useThinking: Bool, baseURL: String?, systemPrompt: String?) async throws -> AIProviderReply {
        var payload: [String: Any] = ["contents": contents]
        if let systemPrompt {
            payload["systemInstruction"] = ["parts": [["text": systemPrompt]]]
        }
        if useThinking {
            payload["generationConfig"] = ["thinkingConfig": ["includeThoughts": true]]
        }
        let response = try await read(GeminiReply.self, provider: .gemini,
                                      path: "/v1beta/models/\(model.id):generateContent",
                                      key: apiKey, body: payload, baseURL: baseURL)
        guard let candidate = response.candidates?.first else { throw MultiProviderAIError.noAnswer }
        if candidate.finishReason == "MAX_TOKENS" { throw MultiProviderAIError.replyIncomplete }
        let parts = candidate.content?.parts ?? []
        let thought = parts.compactMap { $0.thought == true ? $0.text : nil }
            .joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = try Self.join(parts.compactMap { $0.thought == true ? nil : $0.text })
        return AIProviderReply(answer: answer, reasoning: thought.isEmpty ? nil : thought)
    }

    private func read<T: Decodable>(_ type: T.Type, provider: AIProvider, path: String, key: String,
                                    query: [URLQueryItem] = [], body: [String: Any]? = nil,
                                    baseURL: String? = nil) async throws -> T {
        let token = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw MultiProviderAIError.missingKey }
        guard token.utf8.allSatisfy({ (33...126).contains($0) }) else { throw MultiProviderAIError.invalidCredential }
        var request = URLRequest(url: try provider.url(path: path, query: query, baseURL: baseURL),
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 120)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch provider {
        case .openAI, .grok: request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .gemini: request.setValue(token, forHTTPHeaderField: "x-goog-api-key")
        case .claude:
            request.setValue(token, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
            catch { throw MultiProviderAIError.invalidRequest }
        }

        let result: (Data, URLResponse)
        do {
            try Task.checkCancellation()
            result = try await transport(request)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? MultiProviderAIError.timedOut : MultiProviderAIError.networkError
        } catch {
            throw MultiProviderAIError.networkError
        }
        guard let response = result.1 as? HTTPURLResponse else { throw MultiProviderAIError.invalidResponse }
        switch response.statusCode {
        case 200..<300:
            guard result.0.count <= 8 * 1024 * 1024,
                  let value = try? JSONDecoder().decode(T.self, from: result.0)
            else { throw MultiProviderAIError.invalidResponse }
            return value
        case 300..<400: throw MultiProviderAIError.redirectBlocked
        case 401: throw MultiProviderAIError.invalidCredential
        case 402: throw MultiProviderAIError.quota
        case 403: throw MultiProviderAIError.forbidden
        case 404 where body != nil: throw MultiProviderAIError.unsupportedModel
        case 429: throw MultiProviderAIError.rateLimited
        case 500..<600: throw MultiProviderAIError.unavailable
        default: throw MultiProviderAIError.requestRejected(response.statusCode)
        }
    }

    private func model(_ item: CatalogRecord, canChat: Bool) -> AIProviderModel {
        AIProviderModel(id: item.id, displayName: item.displayName ?? item.id, supportsTextChat: canChat)
    }

    private static func nextCursor(_ cursor: String?, seen: inout Set<String>) throws -> String? {
        guard let cursor, !cursor.isEmpty else { return nil }
        guard seen.count < 200, cursor.utf8.count <= 4096, seen.insert(cursor).inserted else {
            throw MultiProviderAIError.invalidCatalog
        }
        return cursor
    }

    private static func join(_ parts: [String]) throws -> String {
        let joined = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { throw MultiProviderAIError.noAnswer }
        return joined
    }

    private static func isOpenAITextID(_ id: String) -> Bool {
        let name = id.lowercased()
        if name.hasPrefix("ft:") {
            // Official fine-tuning guide demonstrates this family on Responses.
            // Examine the base ID only; project and custom suffix can contain arbitrary words.
            let base = name.split(separator: ":", omittingEmptySubsequences: false).dropFirst().first ?? ""
            return base == "gpt-4.1" || base.hasPrefix("gpt-4.1-")
        }
        let prefixes = ["gpt-4", "gpt-5", "gpt-6", "chatgpt-4o-latest", "o1", "o3", "o4"]
        let nonChat = ["audio", "realtime", "transcribe", "tts", "image", "embed", "moderation",
                       "translate", "search-preview", "deep-research"]
        return prefixes.contains(where: { name.hasPrefix($0) }) && !nonChat.contains(where: { name.contains($0) })
    }

    private static func isRelayTextID(_ id: String) -> Bool {
        let name = id.lowercased()
        let nonChat = ["embed", "whisper", "tts", "dall-e", "moderation", "rerank",
                       "-image", "image-gen", "imagen", "veo", "lyria", "audio", "realtime", "transcribe"]
        return !nonChat.contains(where: { name.contains($0) })
    }

    private static func isNonTextGeminiID(_ id: String) -> Bool {
        let name = id.lowercased()
        return ["imagen", "veo", "lyria", "-image", "-tts", "-audio", "-native-audio", "-live"]
            .contains { name.contains($0) }
    }

    private static func supportsOpenAIReasoning(_ id: String) -> Bool {
        let name = id.lowercased()
        return ["o1", "o3", "o4", "gpt-5", "gpt-6"].contains { name.hasPrefix($0) }
    }

    private static func supportsClaudeThinking(_ id: String) -> Bool {
        let name = id.lowercased()
        return name.contains("claude-3-7") || name.contains("claude-3.7")
            || name.contains("claude-sonnet-4") || name.contains("claude-opus-4")
            || name.contains("claude-4")
    }

    private static func supportsGeminiThinking(_ id: String) -> Bool {
        let name = id.lowercased()
        return name.contains("2.5") || name.contains("gemini-3") || name.contains("thinking")
    }
}

private final class BlockRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Never forward bearer or custom API headers, even to a different path on the same host.
        completionHandler(nil)
    }
}

private enum SessionPool {
    static let shared: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config, delegate: BlockRedirects(), delegateQueue: nil)
    }()
}

private struct CatalogRecord: Decodable {
    let id: String
    let displayName: String?
    let aliases: [String]?
    enum CodingKeys: String, CodingKey { case id, displayName = "display_name", aliases }
}

private struct GeneralCatalog: Decodable {
    let data: [CatalogRecord]
    let hasMore: Bool?
    let lastID: String?
    enum CodingKeys: String, CodingKey { case data, hasMore = "has_more", lastID = "last_id" }
}

private struct GeminiCatalog: Decodable {
    struct Record: Decodable {
        let name: String
        let displayName: String?
        let supportedGenerationMethods: [String]?
    }
    let models: [Record]
    let nextPageToken: String?
}

private struct GrokLanguageCatalog: Decodable {
    struct Record: Decodable {
        let id: String
        let aliases: [String]?
        let inputModalities: [String]?
        let outputModalities: [String]?
        enum CodingKeys: String, CodingKey {
            case id, aliases, inputModalities = "input_modalities", outputModalities = "output_modalities"
        }
    }
    let models: [Record]
}

private struct ResponsesReply: Decodable {
    struct SummaryBlock: Decodable {
        let type: String?
        let text: String?
    }
    struct Item: Decodable {
        let type: String
        let role: String?
        let content: [Block]?
        let summary: [SummaryBlock]?
    }
    struct Block: Decodable {
        let type: String
        let text: String?
        let refusal: String?
    }
    let status: String?
    let output: [Item]
}

private struct ChatCompletionsReply: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            struct Part: Decodable {
                let type: String?
                let text: String?
            }
            let contentString: String?
            let contentParts: [Part]?
            let reasoningContent: String?
            let reasoning: String?

            var resolvedText: String {
                if let s = contentString, !s.isEmpty { return s }
                if let parts = contentParts {
                    return parts.compactMap(\.text).joined()
                }
                return ""
            }

            private enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
                case reasoning
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                if let s = try? c.decode(String.self, forKey: .content) {
                    contentString = s
                    contentParts = nil
                } else if let parts = try? c.decode([Part].self, forKey: .content) {
                    contentString = nil
                    contentParts = parts
                } else {
                    contentString = nil
                    contentParts = nil
                }
                reasoningContent = try? c.decodeIfPresent(String.self, forKey: .reasoningContent)
                reasoning = try? c.decodeIfPresent(String.self, forKey: .reasoning)
            }
        }
        let message: Message?
        let finishReason: String?
        private enum CodingKeys: String, CodingKey { case message, finishReason = "finish_reason" }
    }
    let choices: [Choice]
}

private struct ClaudeReply: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
        let thinking: String?
    }
    let stopReason: String?
    let content: [Block]
    enum CodingKeys: String, CodingKey { case stopReason = "stop_reason", content }
}

private struct GeminiReply: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let thought: Bool?; let text: String? }
            let parts: [Part]
        }
        let content: Content?
        let finishReason: String?
    }
    let candidates: [Candidate]?
}

/// Fixed-destination transport for explicitly invoked provider tools. Shares the
/// redirect-rejecting ephemeral session with chat, but never sends chat history.
public enum AIProviderToolHTTP {
    public static func authorize(_ request: inout URLRequest, provider: AIProvider, apiKey: String) throws {
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw MultiProviderAIError.missingKey }
        guard token.utf8.count <= 512, token.utf8.allSatisfy({ (33...126).contains($0) })
        else { throw MultiProviderAIError.invalidCredential }
        guard let url = request.url, allowed(url, provider: provider) else {
            throw MultiProviderAIError.invalidRequest
        }
        switch provider {
        case .openAI, .grok: request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .gemini: request.setValue(token, forHTTPHeaderField: "x-goog-api-key")
        case .claude:
            request.setValue(token, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
    }

    public static func data(for request: URLRequest, provider: AIProvider, maxBytes: Int,
                            transport: MultiProviderAIClient.Transport? = nil) async throws -> Data {
        guard let url = request.url, allowed(url, provider: provider), maxBytes > 0 else {
            throw MultiProviderAIError.invalidRequest
        }
        var safe = request
        safe.cachePolicy = .reloadIgnoringLocalCacheData
        safe.httpShouldHandleCookies = false
        let result: (Data, URLResponse)
        do {
            try Task.checkCancellation()
            if let transport {
                result = try await transport(safe)
            } else {
                result = try await SessionPool.shared.data(for: safe)
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? MultiProviderAIError.timedOut : MultiProviderAIError.networkError
        } catch {
            throw MultiProviderAIError.networkError
        }
        guard let response = result.1 as? HTTPURLResponse else { throw MultiProviderAIError.invalidResponse }
        guard let actual = response.url, allowed(actual, provider: provider) else {
            throw MultiProviderAIError.redirectBlocked
        }
        switch response.statusCode {
        case 200..<300:
            guard result.0.count <= maxBytes else { throw MultiProviderAIError.invalidResponse }
            return result.0
        case 300..<400: throw MultiProviderAIError.redirectBlocked
        case 401: throw MultiProviderAIError.invalidCredential
        case 402: throw MultiProviderAIError.quota
        case 403: throw MultiProviderAIError.forbidden
        case 404: throw MultiProviderAIError.unsupportedModel
        case 429: throw MultiProviderAIError.rateLimited
        case 500..<600: throw MultiProviderAIError.unavailable
        default: throw MultiProviderAIError.requestRejected(response.statusCode)
        }
    }

    private static func allowed(_ url: URL, provider: AIProvider) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == provider.apiHost
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
            && url.fragment == nil
    }
}
