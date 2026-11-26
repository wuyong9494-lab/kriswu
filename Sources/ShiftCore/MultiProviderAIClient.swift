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

    /// Returns the exact target hostname used for requests (custom relay host if valid, otherwise official host).
    public func resolvedHost(baseURL: String? = nil) -> String {
        if let custom = try? Self.normalizedBaseURL(baseURL), let host = custom.host, !host.isEmpty {
            return host
        }
        return apiHost
    }

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

    internal func toolURL(path: String, query: [URLQueryItem] = [], baseURL: String? = nil) throws -> URL {
        try url(path: path, query: query, baseURL: baseURL)
    }

    fileprivate func url(path: String, query: [URLQueryItem], baseURL: String? = nil) throws -> URL {
        if let custom = try Self.normalizedBaseURL(baseURL),
           var parts = URLComponents(url: custom, resolvingAgainstBaseURL: false) {
            var basePath = parts.path
            while basePath.hasSuffix("/") { basePath.removeLast() }
            var tail = path
            if !tail.hasPrefix("/") { tail = "/" + tail }
            if basePath.lowercased().hasSuffix("/v1"),
               (tail.lowercased().hasPrefix("/ai/v1") || tail.lowercased().hasPrefix("/gemini/")) {
                basePath = String(basePath.dropLast(3))
            } else {
                for prefix in ["/v1beta", "/v1"] {
                    if basePath.lowercased().hasSuffix(prefix), tail.lowercased().hasPrefix(prefix + "/") {
                        tail = String(tail.dropFirst(prefix.count))
                        break
                    } else if basePath.lowercased().hasSuffix(prefix), tail.lowercased() == prefix {
                        tail = ""
                        break
                    }
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
    public enum Capability: String, Codable, Hashable, Sendable {
        case chat
        case image
        case realtimeVoice
        case audio
        case other
    }

    public let id: String
    public let displayName: String
    public let supportsTextChat: Bool

    public init(id: String, displayName: String, supportsTextChat: Bool) {
        self.id = id
        self.displayName = displayName
        self.supportsTextChat = supportsTextChat
    }

    public var capability: Capability {
        Self.classify(id: id, supportsTextChat: supportsTextChat)
    }

    public static func classify(id: String, supportsTextChat: Bool) -> Capability {
        let name = id.lowercased()
        if name.contains("realtime") || name.contains("native-audio") || name.hasSuffix("-live") || name.contains("-live-") {
            return .realtimeVoice
        }
        if name.contains("image") || name.contains("imagen") || name.contains("dall-e")
            || name.contains("grok-imagine") || name.contains("flux") || name.contains("veo") {
            return .image
        }
        if name.contains("tts") || name.contains("whisper") || name.contains("transcribe")
            || name.contains("audio") || name.contains("lyria") {
            return .audio
        }
        if supportsTextChat {
            return .chat
        }
        return .other
    }
}

public struct AIProviderMessage: Sendable {
    public enum Role: String, Sendable { case user, assistant }
    public struct ImageAttachment: Codable, Equatable, Sendable {
        public let mimeType: String
        public let base64Data: String

        public init(mimeType: String = "image/jpeg", base64Data: String) {
            self.mimeType = mimeType
            self.base64Data = base64Data
        }
    }

    public let role: Role
    public let text: String
    public let images: [ImageAttachment]

    public init(role: Role, text: String, images: [ImageAttachment] = []) {
        self.role = role
        self.text = text
        self.images = images
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

public enum AIProviderStreamEvent: Equatable, Sendable {
    case reasoning(String)
    case content(String)
    case finished(host: String, endpointPath: String)
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

/// Verified probe result returned when listing models succeeds against a real endpoint.
/// Note: Catalog readability proves key + host reachability for listing, NOT per-model inference eligibility.
public struct AIProviderProbeResult: Equatable, Sendable {
    public let host: String
    public let models: [AIProviderModel]

    public init(host: String, models: [AIProviderModel]) {
        self.host = host
        self.models = models
    }
}

/// Verified live inference smoke-test result for one specific chat model.
public struct AIProviderModelProbeResult: Equatable, Sendable {
    public let host: String
    public let endpointPath: String
    public let latencyMs: Int
    public let preview: String

    public init(host: String, endpointPath: String, latencyMs: Int, preview: String) {
        self.host = host
        self.endpointPath = endpointPath
        self.latencyMs = latencyMs
        self.preview = preview
    }
}

/// Rich sanitized diagnostic error containing the exact request host, HTTP status,
/// and scrubbed upstream error code/type (strictly stripping any API key tokens).
public struct AIProviderDiagnosticError: LocalizedError, Equatable, Sendable {
    public let underlying: MultiProviderAIError
    public let host: String
    public let httpStatus: Int?
    public let errorCode: String?
    public let sanitizedDetail: String?

    public init(
        underlying: MultiProviderAIError,
        host: String,
        httpStatus: Int? = nil,
        errorCode: String? = nil,
        sanitizedDetail: String? = nil
    ) {
        self.underlying = underlying
        self.host = host
        self.httpStatus = httpStatus
        self.errorCode = errorCode
        self.sanitizedDetail = sanitizedDetail
    }

    public var shortBadgeSummary: String {
        var parts: [String] = [host]
        if let httpStatus {
            parts.append("HTTP \(httpStatus)")
        }
        if let code = errorCode, !code.isEmpty {
            parts.append(code)
        }
        return parts.joined(separator: " · ")
    }

    public var errorDescription: String? {
        var head = underlying.errorDescription ?? "请求失败。"
        if underlying == .invalidCredential {
            head = "服务商拒绝了该 API Key（鉴权失败）。若使用中转站 Key 请核对自定义接口地址；若使用官方 Key 请检查接口地址是否留空或 Key 是否已撤销。"
        }
        var meta: [String] = ["请求域名：\(host)"]
        if let httpStatus {
            meta.append("状态码：HTTP \(httpStatus)")
        }
        if let code = errorCode, !code.isEmpty {
            meta.append("错误码：\(code)")
        }
        if let detail = sanitizedDetail, !detail.isEmpty {
            return "\(head)\n[\(meta.joined(separator: " · "))]\n说明：\(detail)"
        }
        return "\(head)\n[\(meta.joined(separator: " · "))]"
    }
}

public struct MultiProviderAIClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport
    private let usesCustomTransport: Bool

    public init() {
        self.transport = { request in
            try await SessionPool.shared.data(for: request)
        }
        self.usesCustomTransport = false
    }

    public init(transport: @escaping Transport) {
        self.transport = transport
        self.usesCustomTransport = true
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
        do {
            return try await probeAndListModels(provider: provider, apiKey: apiKey, baseURL: baseURL).models
        } catch let diag as AIProviderDiagnosticError {
            throw diag.underlying
        }
    }

    /// Probes the provider's model catalog and returns both the exact target host and models,
    /// or throws `AIProviderDiagnosticError` containing the request host + sanitized upstream error code.
    public func probeAndListModels(provider: AIProvider, apiKey: String, baseURL: String? = nil) async throws -> AIProviderProbeResult {
        let targetHost = provider.resolvedHost(baseURL: baseURL)
        let hasCustomBase: Bool
        do {
            hasCustomBase = (try AIProvider.normalizedBaseURL(baseURL)) != nil
        } catch let err as MultiProviderAIError {
            throw AIProviderDiagnosticError(underlying: err, host: targetHost, sanitizedDetail: "自定义接口地址必须为合法的 https:// 网址")
        }
        let models: [AIProviderModel]
        switch provider {
        case .openAI:
            let page = try await readDiagnosed(GeneralCatalog.self, provider: provider, path: "/v1/models",
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
                let page = try await readDiagnosed(GeminiCatalog.self, provider: provider, path: "/v1beta/models",
                                                   key: apiKey, query: query, baseURL: baseURL)
                all += page.models.map { item in
                    let id = String(item.name.dropFirst(item.name.hasPrefix("models/") ? 7 : 0))
                    let canChat = item.supportedGenerationMethods?.contains("generateContent") == true
                        && !Self.isNonTextGeminiID(id)
                    return AIProviderModel(id: id, displayName: item.displayName ?? id, supportsTextChat: canChat)
                }
                do {
                    cursor = try Self.nextCursor(page.nextPageToken, seen: &seen)
                } catch let err as MultiProviderAIError {
                    throw AIProviderDiagnosticError(underlying: err, host: targetHost)
                }
            } while cursor != nil
            models = all
        case .claude:
            var all: [AIProviderModel] = []
            var seen: Set<String> = []
            var cursor: String?
            repeat {
                let query = cursor.map { [URLQueryItem(name: "after_id", value: $0)] } ?? []
                let page = try await readDiagnosed(GeneralCatalog.self, provider: provider, path: "/v1/models", key: apiKey,
                                                   query: query, baseURL: baseURL)
                all += page.data.map { model($0, canChat: true) }
                guard page.hasMore != true || !(page.lastID ?? "").isEmpty else {
                    throw AIProviderDiagnosticError(underlying: .invalidCatalog, host: targetHost)
                }
                do {
                    cursor = try Self.nextCursor(page.hasMore == true ? page.lastID : nil, seen: &seen)
                } catch let err as MultiProviderAIError {
                    throw AIProviderDiagnosticError(underlying: err, host: targetHost)
                }
            } while cursor != nil
            models = all
        case .grok:
            let complete = try await readDiagnosed(GeneralCatalog.self, provider: provider, path: "/v1/models",
                                                   key: apiKey, baseURL: baseURL)
            let detail = try? await readDiagnosed(GrokLanguageCatalog.self, provider: provider, path: "/v1/language-models",
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
        let sorted = models.filter { !$0.id.isEmpty && ids.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.supportsTextChat != rhs.supportsTextChat { return lhs.supportsTextChat }
                return lhs.displayName == rhs.displayName ? lhs.id < rhs.id : lhs.displayName < rhs.displayName
            }
        return AIProviderProbeResult(host: targetHost, models: sorted)
    }

    /// Strips any potential API keys, bearer tokens, or long credentials from upstream error text.
    public static func redactSecrets(in raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let patterns = [
            #"sk-[A-Za-z0-9_\-]{8,}"#,
            #"AIza[0-9A-Za-z_\-]{12,}"#,
            #"xai-[A-Za-z0-9_\-]{8,}"#,
            #"gh[pousr]_[A-Za-z0-9_]{10,}"#,
            #"Bearer\s+[A-Za-z0-9._\-]{8,}"#,
            #"[A-Za-z0-9_\-]{32,}"#,
        ]
        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "[REDACTED]")
            }
        }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if text.count > 160 {
            text = String(text.prefix(157)) + "…"
        }
        return text
    }

    /// Extracts sanitized error code/type and brief hint from OpenAI / Anthropic / Gemini / Relay error JSON.
    public static func extractSanitizedErrorInfo(from data: Data) -> (code: String?, detail: String?) {
        guard !data.isEmpty, data.count <= 262_144,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        var rawCode: String?
        var rawMsg: String?
        if let err = obj["error"] as? [String: Any] {
            if let c = err["code"] as? String, !c.isEmpty { rawCode = c }
            else if let cInt = err["code"] as? Int { rawCode = "\(cInt)" }
            else if let st = err["status"] as? String, !st.isEmpty { rawCode = st }
            else if let t = err["type"] as? String, !t.isEmpty { rawCode = t }
            if let m = err["message"] as? String, !m.isEmpty { rawMsg = m }
        } else {
            if let c = obj["code"] as? String, !c.isEmpty { rawCode = c }
            else if let t = obj["type"] as? String, !t.isEmpty { rawCode = t }
            if let m = obj["message"] as? String, !m.isEmpty { rawMsg = m }
            else if let e = obj["error"] as? String, !e.isEmpty { rawMsg = e }
        }
        let cleanCode = rawCode.map { redactSecrets(in: $0) }.flatMap { $0.isEmpty ? nil : String($0.prefix(64)) }
        let cleanDetail = rawMsg.map { redactSecrets(in: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        return (cleanCode, cleanDetail)
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
        do {
            return try await sendDetailedDiagnosed(
                provider: provider,
                model: model,
                apiKey: apiKey,
                messages: messages,
                deepThinking: deepThinking,
                baseURL: baseURL,
                systemPrompt: systemPrompt
            ).reply
        } catch let diag as AIProviderDiagnosticError {
            throw diag.underlying
        }
    }

    /// Runs a real minimal inference check against one specific chat model so the UI can distinguish
    /// "catalog readable (/v1/models succeeded)" from "this specific model actually answered".
    public func probeModelChat(provider: AIProvider, model: AIProviderModel, apiKey: String,
                               baseURL: String? = nil) async throws -> AIProviderModelProbeResult {
        let started = Date()
        let result = try await sendDetailedDiagnosed(
            provider: provider,
            model: model,
            apiKey: apiKey,
            messages: [AIProviderMessage(role: .user, text: "Reply OK.")],
            deepThinking: false,
            baseURL: baseURL,
            systemPrompt: "Reply with OK only."
        )
        let ms = max(1, Int(Date().timeIntervalSince(started) * 1000))
        let preview = String(result.reply.answer.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        return AIProviderModelProbeResult(
            host: result.host,
            endpointPath: result.endpointPath,
            latencyMs: ms,
            preview: preview
        )
    }

    /// Same as `sendDetailed`, preserving full `AIProviderDiagnosticError` (host, HTTP status, sanitized error code)
    /// plus returning the exact resolved host and endpoint path that succeeded.
    public func sendDetailedDiagnosed(provider: AIProvider, model: AIProviderModel, apiKey: String,
                                      messages: [AIProviderMessage], deepThinking: Bool = false,
                                      baseURL: String? = nil, systemPrompt: String? = nil) async throws -> (reply: AIProviderReply, host: String, endpointPath: String) {
        let targetHost = provider.resolvedHost(baseURL: baseURL)
        guard model.supportsTextChat else {
            throw AIProviderDiagnosticError(
                underlying: .unsupportedModel,
                host: targetHost,
                errorCode: "non_chat_modality",
                sanitizedDetail: "该模型属于出图/语音等专用能力，请从对应能力入口调用"
            )
        }
        guard !model.id.isEmpty, messages.first?.role == .user, messages.last?.role == .user,
              messages.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw AIProviderDiagnosticError(underlying: .invalidRequest, host: targetHost)
        }
        let hasCustomBase: Bool
        do {
            hasCustomBase = (try AIProvider.normalizedBaseURL(baseURL)) != nil
        } catch let err as MultiProviderAIError {
            throw AIProviderDiagnosticError(underlying: err, host: targetHost)
        }
        let cleanSystem: String? = {
            guard let s = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s.utf8.count > 400_000 ? String(s.prefix(120_000)) : s
        }()

        func isEndpointMismatch(_ diag: AIProviderDiagnosticError) -> Bool {
            diag.underlying == .unsupportedModel
                || diag.underlying == .requestRejected(400)
                || diag.underlying == .requestRejected(405)
                || diag.underlying == .requestRejected(501)
        }

        switch provider {
        case .openAI, .grok:
            let responsesInput = Self.encodeOpenAIResponsesInput(messages)
            let chatInput = Self.encodeOpenAIChatMessages(messages)
            if hasCustomBase {
                do {
                    let reply = try await sendChatCompletions(provider: provider, model: model, apiKey: apiKey,
                                                              input: chatInput, baseURL: baseURL, systemPrompt: cleanSystem)
                    return (reply, targetHost, "/v1/chat/completions")
                } catch let diag as AIProviderDiagnosticError where isEndpointMismatch(diag) {
                    do {
                        let reply = try await sendResponses(provider: provider, model: model, apiKey: apiKey,
                                                            input: responsesInput, deepThinking: deepThinking,
                                                            baseURL: baseURL, systemPrompt: cleanSystem)
                        return (reply, targetHost, "/v1/responses")
                    } catch {
                        throw diag
                    }
                }
            }
            do {
                let reply = try await sendResponses(provider: provider, model: model, apiKey: apiKey,
                                                    input: responsesInput, deepThinking: deepThinking,
                                                    baseURL: baseURL, systemPrompt: cleanSystem)
                return (reply, targetHost, "/v1/responses")
            } catch let diag as AIProviderDiagnosticError where isEndpointMismatch(diag) {
                do {
                    let reply = try await sendChatCompletions(provider: provider, model: model, apiKey: apiKey,
                                                              input: chatInput, baseURL: baseURL, systemPrompt: cleanSystem)
                    return (reply, targetHost, "/v1/chat/completions")
                } catch {
                    throw diag
                }
            }
        case .claude:
            let claudeInput = Self.encodeClaudeMessages(messages)
            let useThinking = deepThinking && Self.supportsClaudeThinking(model.id)
            do {
                let reply = try await sendClaude(model: model, apiKey: apiKey, input: claudeInput,
                                                 useThinking: useThinking, baseURL: baseURL, systemPrompt: cleanSystem)
                return (reply, targetHost, "/v1/messages")
            } catch let diag as AIProviderDiagnosticError where diag.underlying == .requestRejected(400) && useThinking {
                let reply = try await sendClaude(model: model, apiKey: apiKey, input: claudeInput,
                                                 useThinking: false, baseURL: baseURL, systemPrompt: cleanSystem)
                return (reply, targetHost, "/v1/messages")
            }
        case .gemini:
            guard model.id.utf8.allSatisfy({ byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                    || byte == 45 || byte == 95 || byte == 46
            }), model.id != ".", model.id != ".." else {
                throw AIProviderDiagnosticError(underlying: .invalidRequest, host: targetHost)
            }
            let contents = Self.encodeGeminiContents(messages)
            let useThinking = deepThinking && Self.supportsGeminiThinking(model.id)
            let path = "/v1beta/models/\(model.id):generateContent"
            do {
                let reply = try await sendGemini(model: model, apiKey: apiKey, contents: contents,
                                                 useThinking: useThinking, baseURL: baseURL, systemPrompt: cleanSystem)
                return (reply, targetHost, path)
            } catch let diag as AIProviderDiagnosticError where diag.underlying == .requestRejected(400) && useThinking {
                let reply = try await sendGemini(model: model, apiKey: apiKey, contents: contents,
                                                 useThinking: false, baseURL: baseURL, systemPrompt: cleanSystem)
                return (reply, targetHost, path)
            }
        }
    }

    /// Streams chat tokens (reasoning + final content) in real time via SSE for Own API providers
    /// (OpenAI/Grok/Relays `/v1/chat/completions`, Gemini `:streamGenerateContent?alt=sse`, Claude `/v1/messages`).
    /// Automatically salvages reasoning-only responses and transparently falls back to `sendDetailedDiagnosed`
    /// if a provider/relay rejects streaming or returns non-SSE JSON.
    public func streamChatDiagnosed(
        provider: AIProvider,
        model: AIProviderModel,
        apiKey: String,
        messages: [AIProviderMessage],
        deepThinking: Bool = false,
        baseURL: String? = nil,
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<AIProviderStreamEvent, Error> {
        let client = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    #if canImport(Darwin)
                    if !client.usesCustomTransport {
                        let streamed = try await client.performDarwinSSEStream(
                            provider: provider,
                            model: model,
                            apiKey: apiKey,
                            messages: messages,
                            deepThinking: deepThinking,
                            baseURL: baseURL,
                            systemPrompt: systemPrompt,
                            continuation: continuation
                        )
                        if streamed {
                            continuation.finish()
                            return
                        }
                    }
                    #endif
                    let res = try await client.sendDetailedDiagnosed(
                        provider: provider,
                        model: model,
                        apiKey: apiKey,
                        messages: messages,
                        deepThinking: deepThinking,
                        baseURL: baseURL,
                        systemPrompt: systemPrompt
                    )
                    if let r = res.reply.reasoning, !r.isEmpty {
                        continuation.yield(.reasoning(r))
                    }
                    if !res.reply.answer.isEmpty {
                        continuation.yield(.content(res.reply.answer))
                    }
                    continuation.yield(.finished(host: res.host, endpointPath: res.endpointPath))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Parses one SSE `data: ...` line from OpenAI/Grok/Relays, Gemini, or Claude into incremental reasoning/content deltas.
    public static func parseSSELine(provider: AIProvider, line rawLine: String) -> (reasoning: String?, content: String?) {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return (nil, nil) }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        switch provider {
        case .openAI, .grok:
            guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first else {
                return (nil, nil)
            }
            let delta = (first["delta"] as? [String: Any]) ?? (first["message"] as? [String: Any]) ?? [:]
            var rOut: String?
            if let rc = delta["reasoning_content"] as? String, !rc.isEmpty {
                rOut = rc
            } else if let r = delta["reasoning"] as? String, !r.isEmpty {
                rOut = r
            }
            var cOut: String?
            if let c = delta["content"] as? String, !c.isEmpty {
                cOut = c
            } else if let parts = delta["content"] as? [[String: Any]] {
                let joined = parts.compactMap { $0["text"] as? String }.joined()
                if !joined.isEmpty { cOut = joined }
            }
            return (rOut, cOut)
        case .gemini:
            guard let candidates = obj["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let contentObj = first["content"] as? [String: Any],
                  let parts = contentObj["parts"] as? [[String: Any]] else {
                return (nil, nil)
            }
            var rParts: [String] = []
            var cParts: [String] = []
            for p in parts {
                guard let text = p["text"] as? String, !text.isEmpty else { continue }
                if (p["thought"] as? Bool) == true {
                    rParts.append(text)
                } else {
                    cParts.append(text)
                }
            }
            return (rParts.isEmpty ? nil : rParts.joined(), cParts.isEmpty ? nil : cParts.joined())
        case .claude:
            if (obj["type"] as? String) == "content_block_delta",
               let delta = obj["delta"] as? [String: Any] {
                let dt = delta["type"] as? String
                if dt == "thinking_delta", let t = delta["thinking"] as? String, !t.isEmpty {
                    return (t, nil)
                }
                if dt == "text_delta", let t = delta["text"] as? String, !t.isEmpty {
                    return (nil, t)
                }
            }
            return (nil, nil)
        }
    }

    #if canImport(Darwin)
    /// Returns `true` if SSE streaming produced a complete answer (including reasoning-only salvage),
    /// or `false` if the caller should fall back to non-streaming `sendDetailedDiagnosed`.
    private func performDarwinSSEStream(
        provider: AIProvider,
        model: AIProviderModel,
        apiKey: String,
        messages: [AIProviderMessage],
        deepThinking: Bool,
        baseURL: String?,
        systemPrompt: String?,
        continuation: AsyncThrowingStream<AIProviderStreamEvent, Error>.Continuation
    ) async throws -> Bool {
        let targetHost = provider.resolvedHost(baseURL: baseURL)
        guard model.supportsTextChat else {
            throw AIProviderDiagnosticError(
                underlying: .unsupportedModel,
                host: targetHost,
                errorCode: "non_chat_modality",
                sanitizedDetail: "该模型属于出图/语音等专用能力，请从对应能力入口调用"
            )
        }
        guard !model.id.isEmpty, messages.first?.role == .user, messages.last?.role == .user,
              messages.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw AIProviderDiagnosticError(underlying: .invalidRequest, host: targetHost)
        }
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw AIProviderDiagnosticError(underlying: .missingKey, host: targetHost)
        }
        guard token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw AIProviderDiagnosticError(underlying: .invalidCredential, host: targetHost, errorCode: "invalid_characters", sanitizedDetail: "Key 含有非 ASCII 字符或空白")
        }
        let cleanSystem: String? = {
            guard let s = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s.utf8.count > 400_000 ? String(s.prefix(120_000)) : s
        }()

        let endpointPath: String
        let query: [URLQueryItem]
        let payload: [String: Any]

        switch provider {
        case .openAI, .grok:
            endpointPath = "/v1/chat/completions"
            query = []
            var wireMessages = Self.encodeOpenAIChatMessages(messages)
            if let cleanSystem {
                wireMessages.insert(["role": "system", "content": cleanSystem], at: 0)
            }
            payload = [
                "model": model.id,
                "messages": wireMessages,
                "stream": true,
            ]
        case .gemini:
            guard model.id.utf8.allSatisfy({ byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                    || byte == 45 || byte == 95 || byte == 46
            }), model.id != ".", model.id != ".." else {
                throw AIProviderDiagnosticError(underlying: .invalidRequest, host: targetHost)
            }
            endpointPath = "/v1beta/models/\(model.id):streamGenerateContent"
            query = [URLQueryItem(name: "alt", value: "sse")]
            var body: [String: Any] = ["contents": Self.encodeGeminiContents(messages)]
            if let cleanSystem {
                body["systemInstruction"] = ["parts": [["text": cleanSystem]]]
            }
            if deepThinking && Self.supportsGeminiThinking(model.id) {
                body["generationConfig"] = ["thinkingConfig": ["includeThoughts": true]]
            }
            payload = body
        case .claude:
            endpointPath = "/v1/messages"
            query = []
            let useThinking = deepThinking && Self.supportsClaudeThinking(model.id)
            var body: [String: Any] = [
                "model": model.id,
                "messages": Self.encodeClaudeMessages(messages),
                "max_tokens": useThinking ? 8192 : 4096,
                "stream": true,
            ]
            if let cleanSystem {
                body["system"] = cleanSystem
            }
            if useThinking {
                body["thinking"] = ["type": "enabled", "budget_tokens": 2048]
            }
            payload = body
        }

        let targetURL: URL
        do {
            targetURL = try provider.url(path: endpointPath, query: query, baseURL: baseURL)
        } catch let err as MultiProviderAIError {
            throw AIProviderDiagnosticError(underlying: err, host: targetHost)
        }
        let host = targetURL.host ?? targetHost
        var request = URLRequest(url: targetURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        switch provider {
        case .openAI, .grok: request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .gemini: request.setValue(token, forHTTPHeaderField: "x-goog-api-key")
        case .claude:
            request.setValue(token, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw AIProviderDiagnosticError(underlying: .invalidRequest, host: host)
        }

        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config, delegate: BlockRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            try Task.checkCancellation()
            (bytes, response) = try await session.bytes(for: request)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            let mapped: MultiProviderAIError = error.code == .timedOut ? .timedOut : .networkError
            throw AIProviderDiagnosticError(underlying: mapped, host: host, errorCode: "URLError(\(error.code.rawValue))")
        } catch {
            throw AIProviderDiagnosticError(underlying: .networkError, host: host)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIProviderDiagnosticError(underlying: .invalidResponse, host: host)
        }
        let status = http.statusCode
        if !(200..<300).contains(status) {
            var errData = Data()
            for try await b in bytes {
                errData.append(b)
                if errData.count >= 32_768 { break }
            }
            // If endpoint/param rejected streaming (e.g. OpenAI Responses-only model or thinking param),
            // let caller fall back cleanly to non-streaming sendDetailedDiagnosed which handles endpoint/param fallback.
            if [400, 404, 405, 501].contains(status) {
                return false
            }
            let info = Self.extractSanitizedErrorInfo(from: errData)
            let underlying: MultiProviderAIError
            switch status {
            case 300..<400: underlying = .redirectBlocked
            case 401: underlying = .invalidCredential
            case 402: underlying = .quota
            case 403: underlying = .forbidden
            case 429: underlying = .rateLimited
            case 500..<600: underlying = .unavailable
            default: underlying = .requestRejected(status)
            }
            throw AIProviderDiagnosticError(underlying: underlying, host: host, httpStatus: status, errorCode: info.code, sanitizedDetail: info.detail)
        }

        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if contentType.contains("application/json") && !contentType.contains("event-stream") {
            return false
        }

        var reasoningBuf = ""
        var contentBuf = ""
        var hasYieldedAnyToken = false
        do {
            for try await rawLine in bytes.lines {
                try Task.checkCancellation()
                let parsed = Self.parseSSELine(provider: provider, line: rawLine)
                if let r = parsed.reasoning, !r.isEmpty {
                    hasYieldedAnyToken = true
                    reasoningBuf += r
                    continuation.yield(.reasoning(r))
                }
                if let c = parsed.content, !c.isEmpty {
                    hasYieldedAnyToken = true
                    contentBuf += c
                    continuation.yield(.content(c))
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if hasYieldedAnyToken {
                throw AIProviderDiagnosticError(
                    underlying: .networkError,
                    host: host,
                    errorCode: "stream_interrupted_after_first_token",
                    sanitizedDetail: "流式输出中途中断（已保留已接收内容，为避免重复计费不会自动重发）"
                )
            }
            throw error
        }

        let trimmedContent = contentBuf.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReasoning = reasoningBuf.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContent.isEmpty && !trimmedReasoning.isEmpty {
            // Reasoning-only model response: promote accumulated reasoning into visible answer!
            continuation.yield(.content(trimmedReasoning))
            continuation.yield(.finished(host: host, endpointPath: endpointPath))
            return true
        }
        if !trimmedContent.isEmpty {
            continuation.yield(.finished(host: host, endpointPath: endpointPath))
            return true
        }
        // Empty SSE response before any token arrived: fall back once to non-streaming request.
        return false
    }
    #endif

    private static func encodeOpenAIResponsesInput(_ messages: [AIProviderMessage]) -> [[String: Any]] {
        messages.map { msg in
            guard msg.role == .user && !msg.images.isEmpty else {
                return ["role": msg.role.rawValue, "content": msg.text]
            }
            var parts: [[String: Any]] = [["type": "input_text", "text": msg.text]]
            for img in msg.images.prefix(4) {
                parts.append([
                    "type": "input_image",
                    "image_url": "data:\(img.mimeType);base64,\(img.base64Data)"
                ])
            }
            return ["role": msg.role.rawValue, "content": parts]
        }
    }

    private static func encodeOpenAIChatMessages(_ messages: [AIProviderMessage]) -> [[String: Any]] {
        messages.map { msg in
            guard msg.role == .user && !msg.images.isEmpty else {
                return ["role": msg.role.rawValue, "content": msg.text]
            }
            var parts: [[String: Any]] = [["type": "text", "text": msg.text]]
            for img in msg.images.prefix(4) {
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(img.mimeType);base64,\(img.base64Data)"]
                ])
            }
            return ["role": msg.role.rawValue, "content": parts]
        }
    }

    private static func encodeClaudeMessages(_ messages: [AIProviderMessage]) -> [[String: Any]] {
        messages.map { msg in
            guard msg.role == .user && !msg.images.isEmpty else {
                return ["role": msg.role.rawValue, "content": msg.text]
            }
            var blocks: [[String: Any]] = []
            for img in msg.images.prefix(4) {
                blocks.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": img.mimeType,
                        "data": img.base64Data
                    ]
                ])
            }
            blocks.append(["type": "text", "text": msg.text])
            return ["role": msg.role.rawValue, "content": blocks]
        }
    }

    private static func encodeGeminiContents(_ messages: [AIProviderMessage]) -> [[String: Any]] {
        messages.map { msg in
            var parts: [[String: Any]] = [["text": msg.text]]
            if msg.role == .user && !msg.images.isEmpty {
                for img in msg.images.prefix(4) {
                    parts.append([
                        "inline_data": [
                            "mime_type": img.mimeType,
                            "data": img.base64Data
                        ]
                    ])
                }
            }
            return ["role": msg.role == .user ? "user" : "model", "parts": parts]
        }
    }

    private func sendResponses(provider: AIProvider, model: AIProviderModel, apiKey: String,
                               input: [[String: Any]], deepThinking: Bool,
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
            let response = try await readDiagnosed(ResponsesReply.self, provider: provider, path: "/v1/responses",
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
            let joinedThought = reasoning.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let answer: String
            if let joined = try? Self.join(content) {
                answer = joined
            } else if !joinedThought.isEmpty {
                answer = joinedThought
            } else {
                throw MultiProviderAIError.noAnswer
            }
            return AIProviderReply(answer: answer, reasoning: joinedThought.isEmpty ? nil : joinedThought)
        }
        do {
            return try await run(withReasoning: wantsReasoning)
        } catch let diag as AIProviderDiagnosticError where diag.underlying == .requestRejected(400) && wantsReasoning {
            return try await run(withReasoning: false)
        }
    }

    private func sendChatCompletions(provider: AIProvider, model: AIProviderModel, apiKey: String,
                                     input: [[String: Any]], baseURL: String?,
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
        let response = try await readDiagnosed(ChatCompletionsReply.self, provider: provider, path: "/v1/chat/completions",
                                               key: apiKey, body: payload, baseURL: baseURL)
        guard let choice = response.choices.first else { throw MultiProviderAIError.noAnswer }
        let rawAnswer = choice.message?.resolvedText ?? ""
        let rawThought = choice.message?.reasoningContent ?? choice.message?.reasoning ?? ""
        let trimmedThought = rawThought.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer: String
        if let joined = try? Self.join([rawAnswer]) {
            answer = choice.finishReason == "length" ? (joined + "\n\n> 注：本次回答已达到模型单次输出长度上限。") : joined
        } else if !trimmedThought.isEmpty {
            // Reasoning-only reply (e.g. reasoning models that hit token cap before emitting final text):
            // NEVER discard the model's work with a cryptic "noAnswer" error!
            answer = trimmedThought
        } else if choice.finishReason == "length" {
            throw MultiProviderAIError.replyIncomplete
        } else {
            throw MultiProviderAIError.noAnswer
        }
        return AIProviderReply(answer: answer, reasoning: trimmedThought.isEmpty ? nil : trimmedThought)
    }

    private func sendClaude(model: AIProviderModel, apiKey: String, input: [[String: Any]],
                            useThinking: Bool, baseURL: String?, systemPrompt: String?) async throws -> AIProviderReply {
        var payload: [String: Any] = ["model": model.id, "messages": input, "max_tokens": useThinking ? 8192 : 4096]
        if let systemPrompt {
            payload["system"] = systemPrompt
        }
        if useThinking {
            payload["thinking"] = ["type": "enabled", "budget_tokens": 2048]
        }
        let response = try await readDiagnosed(ClaudeReply.self, provider: .claude, path: "/v1/messages",
                                               key: apiKey, body: payload, baseURL: baseURL)
        let thought = response.content.compactMap { $0.type == "thinking" ? $0.thinking : nil }
            .joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let answer: String
        if let joined = try? Self.join(response.content.compactMap { $0.type == "text" ? $0.text : nil }) {
            answer = response.stopReason == "max_tokens" ? (joined + "\n\n> 注：本次回答已达到单次输出长度上限。") : joined
        } else if !thought.isEmpty {
            answer = thought
        } else if response.stopReason == "max_tokens" {
            throw MultiProviderAIError.replyIncomplete
        } else {
            throw MultiProviderAIError.noAnswer
        }
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
        let response = try await readDiagnosed(GeminiReply.self, provider: .gemini,
                                               path: "/v1beta/models/\(model.id):generateContent",
                                               key: apiKey, body: payload, baseURL: baseURL)
        guard let candidate = response.candidates?.first else { throw MultiProviderAIError.noAnswer }
        let parts = candidate.content?.parts ?? []
        let thought = parts.compactMap { $0.thought == true ? $0.text : nil }
            .joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let answer: String
        if let joined = try? Self.join(parts.compactMap { $0.thought == true ? nil : $0.text }) {
            answer = candidate.finishReason == "MAX_TOKENS" ? (joined + "\n\n> 注：本次回答已达到单次输出长度上限。") : joined
        } else if !thought.isEmpty {
            answer = thought
        } else if candidate.finishReason == "MAX_TOKENS" {
            throw MultiProviderAIError.replyIncomplete
        } else {
            throw MultiProviderAIError.noAnswer
        }
        return AIProviderReply(answer: answer, reasoning: thought.isEmpty ? nil : thought)
    }

    private func read<T: Decodable>(_ type: T.Type, provider: AIProvider, path: String, key: String,
                                    query: [URLQueryItem] = [], body: [String: Any]? = nil,
                                    baseURL: String? = nil) async throws -> T {
        do {
            return try await readDiagnosed(type, provider: provider, path: path, key: key,
                                           query: query, body: body, baseURL: baseURL)
        } catch let diag as AIProviderDiagnosticError {
            throw diag.underlying
        }
    }

    private func readDiagnosed<T: Decodable>(_ type: T.Type, provider: AIProvider, path: String, key: String,
                                             query: [URLQueryItem] = [], body: [String: Any]? = nil,
                                             baseURL: String? = nil) async throws -> T {
        let fallbackHost = provider.resolvedHost(baseURL: baseURL)
        let token = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw AIProviderDiagnosticError(underlying: .missingKey, host: fallbackHost)
        }
        guard token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw AIProviderDiagnosticError(underlying: .invalidCredential, host: fallbackHost, errorCode: "invalid_characters", sanitizedDetail: "Key 含有非 ASCII 字符或空白")
        }
        let targetURL: URL
        do {
            targetURL = try provider.url(path: path, query: query, baseURL: baseURL)
        } catch let err as MultiProviderAIError {
            throw AIProviderDiagnosticError(underlying: err, host: fallbackHost)
        }
        let host = targetURL.host ?? fallbackHost
        var request = URLRequest(url: targetURL,
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
            catch { throw AIProviderDiagnosticError(underlying: .invalidRequest, host: host) }
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
            let mapped: MultiProviderAIError = error.code == .timedOut ? .timedOut : .networkError
            throw AIProviderDiagnosticError(underlying: mapped, host: host, errorCode: "URLError(\(error.code.rawValue))")
        } catch {
            throw AIProviderDiagnosticError(underlying: .networkError, host: host)
        }
        guard let response = result.1 as? HTTPURLResponse else {
            throw AIProviderDiagnosticError(underlying: .invalidResponse, host: host)
        }
        let status = response.statusCode
        let info = Self.extractSanitizedErrorInfo(from: result.0)
        switch status {
        case 200..<300:
            guard result.0.count <= 8 * 1024 * 1024,
                  let value = try? JSONDecoder().decode(T.self, from: result.0)
            else {
                throw AIProviderDiagnosticError(underlying: .invalidResponse, host: host, httpStatus: status)
            }
            return value
        case 300..<400:
            throw AIProviderDiagnosticError(underlying: .redirectBlocked, host: host, httpStatus: status, errorCode: info.code, sanitizedDetail: info.detail)
        case 401:
            throw AIProviderDiagnosticError(underlying: .invalidCredential, host: host, httpStatus: status, errorCode: info.code, sanitizedDetail: info.detail)
        case 402:
            throw AIProviderDiagnosticError(underlying: .quota, host: host, httpStatus: status, errorCode: info.code, sanitizedDetail: info.detail)
        case 403:
            throw AIProviderDiagnosticError(underlying: .forbidden, host: host, httpStatus: status, errorCode: info.code, sanitizedDetail: info.detail)
        case 404 where body != nil:
            throw AIProviderDiagnosticError(underlying: .unsupportedModel, host: host, httpStatus: status, errorCode: info.code, sanitizedDetail: info.detail)
        case 429:
            throw AIProviderDiagnosticError(underlying: .rateLimited, host: host, httpStatus: status, errorCode: info.code, sanitizedDetail: info.detail)
        case 500..<600:
            throw AIProviderDiagnosticError(underlying: .unavailable, host: host, httpStatus: status, errorCode: info.code, sanitizedDetail: info.detail)
        default:
            throw AIProviderDiagnosticError(underlying: .requestRejected(status), host: host, httpStatus: status, errorCode: info.code, sanitizedDetail: info.detail)
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
    public static func authorize(_ request: inout URLRequest, provider: AIProvider, apiKey: String, baseURL: String? = nil) throws {
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw MultiProviderAIError.missingKey }
        guard token.utf8.count <= 512, token.utf8.allSatisfy({ (33...126).contains($0) })
        else { throw MultiProviderAIError.invalidCredential }
        guard let url = request.url, allowed(url, provider: provider, baseURL: baseURL) else {
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
                            baseURL: String? = nil,
                            transport: MultiProviderAIClient.Transport? = nil) async throws -> Data {
        guard let url = request.url, allowed(url, provider: provider, baseURL: baseURL), maxBytes > 0 else {
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
        guard let actual = response.url, allowed(actual, provider: provider, baseURL: baseURL) else {
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

    /// Authorizes OpenAI-compatible relays (such as AIHubMix) that expect Bearer auth regardless of underlying vendor.
    public static func authorizeRelay(_ request: inout URLRequest, provider: AIProvider, apiKey: String, baseURL: String? = nil, forceBearer: Bool = false) throws {
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw MultiProviderAIError.missingKey }
        guard token.utf8.count <= 512, token.utf8.allSatisfy({ (33...126).contains($0) })
        else { throw MultiProviderAIError.invalidCredential }
        guard let url = request.url, allowed(url, provider: provider, baseURL: baseURL) else {
            throw MultiProviderAIError.invalidRequest
        }
        if forceBearer || isOpenAICompatibleRelay(baseURL) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return
        }
        try authorize(&request, provider: provider, apiKey: apiKey, baseURL: baseURL)
    }

    public static func authorizeGeminiNative(_ request: inout URLRequest, apiKey: String, baseURL: String? = nil) throws {
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw MultiProviderAIError.missingKey }
        guard token.utf8.count <= 512, token.utf8.allSatisfy({ (33...126).contains($0) })
        else { throw MultiProviderAIError.invalidCredential }
        guard let url = request.url, allowed(url, provider: .gemini, baseURL: baseURL) else {
            throw MultiProviderAIError.invalidRequest
        }
        request.setValue(token, forHTTPHeaderField: "x-goog-api-key")
    }

    public static func isOpenAICompatibleRelay(_ baseURL: String?) -> Bool {
        guard let raw = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = try? AIProvider.normalizedBaseURL(raw),
              let host = url.host?.lowercased() else { return false }
        return host == "aihubmix.com"
            || host.hasSuffix(".aihubmix.com")
            || host == "api.inferera.com"
            || host.hasSuffix(".inferera.com")
    }

    public static func isOfficialVendorHost(_ baseURL: String?) -> Bool {
        guard let raw = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return true
        }
        guard let url = try? AIProvider.normalizedBaseURL(raw),
              let host = url.host?.lowercased() else {
            return false
        }
        let officialHosts: Set<String> = [
            "api.openai.com",
            "generativelanguage.googleapis.com",
            "api.anthropic.com",
            "api.x.ai",
        ]
        return officialHosts.contains(host)
    }

    /// Transport variant for non-chat media tools (video generation, reference-image edits).
    /// Extracts structured JSON upstream `error.message`/`error.code` (redacting any credentials) and
    /// NEVER maps HTTP 404 to the chat-specific "无法用于文字对话" error string.
    public static func dataWithDiagnostics(
        for request: URLRequest,
        provider: AIProvider,
        maxBytes: Int,
        baseURL: String? = nil,
        transport: MultiProviderAIClient.Transport? = nil
    ) async throws -> (data: Data, statusCode: Int) {
        guard let url = request.url, allowed(url, provider: provider, baseURL: baseURL), maxBytes > 0 else {
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
        guard let actual = response.url, allowed(actual, provider: provider, baseURL: baseURL) else {
            throw MultiProviderAIError.redirectBlocked
        }
        switch response.statusCode {
        case 200..<300:
            guard result.0.count <= maxBytes else { throw MultiProviderAIError.invalidResponse }
            return (result.0, response.statusCode)
        case 300..<400:
            throw MultiProviderAIError.redirectBlocked
        case 401:
            throw MultiProviderAIError.invalidCredential
        case 402:
            throw MultiProviderAIError.quota
        case 429:
            throw MultiProviderAIError.rateLimited
        default:
            let extracted = extractSafeUpstreamError(from: result.0)
            throw AIProviderToolDiagnosticError(
                statusCode: response.statusCode,
                endpointPath: url.path,
                host: url.host ?? provider.apiHost,
                upstreamCode: extracted.code,
                upstreamMessage: extracted.message
            )
        }
    }

    private static func extractSafeUpstreamError(from data: Data) -> (code: String?, message: String?) {
        guard !data.isEmpty, data.count <= 256 * 1024,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        var code: String?
        var message: String?
        if let errObj = obj["error"] as? [String: Any] {
            code = errObj["code"] as? String ?? errObj["type"] as? String
            message = errObj["message"] as? String
        } else if let errStr = obj["error"] as? String {
            message = errStr
        } else if let msg = obj["message"] as? String {
            message = msg
            code = obj["code"] as? String
        }
        let cleanMsg = message.map {
            String(MultiProviderAIClient.redactSecrets(in: $0).trimmingCharacters(in: .whitespacesAndNewlines).prefix(260))
        }
        return (code, (cleanMsg?.isEmpty == false) ? cleanMsg : nil)
    }

    private static func allowed(_ url: URL, provider: AIProvider, baseURL: String? = nil) -> Bool {
        if let raw = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            guard let expected = try? AIProvider.normalizedBaseURL(raw),
                  let expectedHost = expected.host?.lowercased() else { return false }
            return url.scheme?.lowercased() == "https"
                && url.host?.lowercased() == expectedHost
                && (url.port ?? 443) == (expected.port ?? 443)
                && url.user == nil && url.password == nil
                && url.fragment == nil
        }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == provider.apiHost
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
            && url.fragment == nil
    }
}

public struct AIProviderToolDiagnosticError: LocalizedError, Equatable, Sendable {
    public let statusCode: Int
    public let endpointPath: String
    public let host: String
    public let upstreamCode: String?
    public let upstreamMessage: String?

    public init(statusCode: Int, endpointPath: String, host: String, upstreamCode: String?, upstreamMessage: String?) {
        self.statusCode = statusCode
        self.endpointPath = endpointPath
        self.host = host
        self.upstreamCode = upstreamCode
        self.upstreamMessage = upstreamMessage
    }

    public var errorDescription: String? {
        let detail = upstreamMessage ?? {
            switch statusCode {
            case 400, 422: return "参数不被当前模型或接口接受（请核对时长、分辨率或文件格式）"
            case 403: return "当前 API Key 无权调用该模型或接口"
            case 404: return "接口路径 \(endpointPath) 或该模型 ID 在 \(host) 上不存在 / 未开通"
            case 500..<600: return "上游媒体服务暂时不可用"
            default: return "上游媒体接口拒绝请求"
            }
        }()
        let codeTag = upstreamCode.map { " [\($0)]" } ?? ""
        return "HTTP \(statusCode)\(codeTag)（\(host)\(endpointPath)）：\(detail)"
    }
}
