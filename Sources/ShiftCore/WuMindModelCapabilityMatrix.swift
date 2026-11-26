import Foundation

/// Authoritative Connection × Model × Capability truth matrix, pre-flight honesty guard,
/// phase-split latency telemetry, and anti-fight scroll-follow policy for WUMIND.
///
/// Design invariants:
/// 1. Text chat passing NEVER implies vision, deep thinking, web tools, realtime voice, or media generation work.
/// 2. Unsupported capabilities MUST be explicitly surfaced BEFORE calling upstream — NEVER silently swap models,
///    drop attached images, disable deep thinking, or fall back across billing channels.
/// 3. Latency is strictly decomposed into client prep, attachment prep, gateway wait, upstream TTFT, and UI render
///    so App performance is never conflated with upstream provider latency.

public enum WuMindThinkingWireProtocol: String, Codable, Equatable, Sendable {
    case deepseekThinking       // { thinking: { type: "enabled" | "disabled" } }
    case openaiReasoningEffort  // { reasoning_effort: "high" } (+ max_completion_tokens on direct OpenAI)
    case claudeThinkingBudget   // { thinking: { type: "enabled", budget_tokens: N } }
    case geminiThinkingConfig   // { generationConfig: { thinkingConfig: { includeThoughts: true } } }
    case unsupported

    public var isSupported: Bool { self != .unsupported }

    public var wireParamSummary: String {
        switch self {
        case .deepseekThinking: return "thinking={type:enabled}"
        case .openaiReasoningEffort: return "reasoning_effort=high"
        case .claudeThinkingBudget: return "thinking={type:enabled,budget_tokens}"
        case .geminiThinkingConfig: return "thinkingConfig={includeThoughts:true}"
        case .unsupported: return "none (unsupported)"
        }
    }
}

public struct WuMindModelCapabilities: Codable, Equatable, Sendable {
    public let textStreaming: Bool
    public let thinkingProtocol: WuMindThinkingWireProtocol
    public let visionAttachments: Bool
    public let webSearchTool: Bool
    public let realtimeVoice: Bool
    public let mediaGeneration: Bool
    public let usesMaxCompletionTokens: Bool
    public let notes: String

    public var supportsDeepThinking: Bool { thinkingProtocol.isSupported }

    public init(
        textStreaming: Bool = true,
        thinkingProtocol: WuMindThinkingWireProtocol,
        visionAttachments: Bool,
        webSearchTool: Bool = true,
        realtimeVoice: Bool = false,
        mediaGeneration: Bool = false,
        usesMaxCompletionTokens: Bool = false,
        notes: String = ""
    ) {
        self.textStreaming = textStreaming
        self.thinkingProtocol = thinkingProtocol
        self.visionAttachments = visionAttachments
        self.webSearchTool = webSearchTool
        self.realtimeVoice = realtimeVoice
        self.mediaGeneration = mediaGeneration
        self.usesMaxCompletionTokens = usesMaxCompletionTokens
        self.notes = notes
    }
}

public enum WuMindPreflightViolation: Equatable, Sendable {
    case visionNotSupported(modelID: String, connectionLabel: String)
    case deepThinkingNotSupported(modelID: String, connectionLabel: String)
    case nonChatModelInChat(modelID: String, connectionLabel: String)

    public var errorCode: String {
        switch self {
        case .visionNotSupported: return "vision_not_supported"
        case .deepThinkingNotSupported: return "thinking_not_supported"
        case .nonChatModelInChat: return "non_chat_modality"
        }
    }

    public var userMessage: String {
        switch self {
        case .visionNotSupported(let modelID, let conn):
            return "当前所选模型「\(modelID)」（\(conn)）不支持直接识图，已阻止发送（未丢弃图片、未静默换模型、未扣费）。请移除图片附件，或手动切换到支持识图的模型（如 GPT-4o / GPT-5 / Gemini 2.5 / Claude 3.7+ / Grok 4）。"
        case .deepThinkingNotSupported(let modelID, let conn):
            return "当前所选模型「\(modelID)」（\(conn)）不支持深度思考参数，已阻止发送（未静默关闭深度思考、未换模型、未扣费）。请关闭「深度思考」开关，或手动切换到推理模型（如 DeepSeek R1 / GPT-5 / o3 / Claude 3.7+ / Gemini 2.5+ / Grok 4）。"
        case .nonChatModelInChat(let modelID, let conn):
            return "「\(modelID)」（\(conn)）是专用生图/生视频/语音模型，不支持聊天对话，请从对应工坊调用。"
        }
    }
}

public enum WuMindModelCapabilityMatrix {
    /// Resolves truthful capabilities for a given `(providerRaw, modelID, isRelayBaseURL)` tuple.
    /// `providerRaw`: "deepSeek" | "openAI" | "gemini" | "claude" | "grok"
    public static func capabilities(
        providerRaw: String,
        modelID rawModelID: String,
        isRelayBaseURL: Bool = false
    ) -> WuMindModelCapabilities {
        let id = rawModelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Dedicated non-chat media / voice models
        let isDedicatedImage = id.contains("gpt-image") || id.contains("dall-e") || id.contains("imagen-")
            || id.contains("flux") || id.contains("ideogram") || id.contains("imagine-image")
            || (id.contains("gemini") && id.contains("image"))
        let isDedicatedVideo = id.hasPrefix("sora-") || id.hasPrefix("veo-") || id.contains("kling")
            || id.contains("seedance") || id.contains("hailuo") || id.contains("runway")
        let isRealtimeVoice = id.contains("realtime") || id.contains("native-audio") || id.contains("live-preview")

        if isDedicatedImage || isDedicatedVideo {
            return WuMindModelCapabilities(
                textStreaming: false,
                thinkingProtocol: .unsupported,
                visionAttachments: isDedicatedImage || isDedicatedVideo,
                webSearchTool: false,
                realtimeVoice: false,
                mediaGeneration: true,
                notes: "专用视觉/视频生成模型，仅限画室或视频工坊调用"
            )
        }
        if isRealtimeVoice {
            return WuMindModelCapabilities(
                textStreaming: false,
                thinkingProtocol: .unsupported,
                visionAttachments: false,
                webSearchTool: false,
                realtimeVoice: true,
                mediaGeneration: false,
                notes: "专用实时语音通话模型，仅限实时语音通话入口调用"
            )
        }

        let p = providerRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // DeepSeek family (direct API OR via relay such as AIHubMix)
        if p == "deepseek" || id.contains("deepseek") {
            let supportsThinking = id.contains("reasoner") || id.contains("r1")
                || id.contains("v3") || id == "deepseek-chat" || id.contains("speciale")
            // DeepSeek text chat/reasoner models do NOT natively accept OpenAI image_url vision blocks!
            let supportsVision = id.contains("vl") || id.contains("ocr")
            return WuMindModelCapabilities(
                textStreaming: true,
                thinkingProtocol: supportsThinking ? .deepseekThinking : .unsupported,
                visionAttachments: supportsVision,
                webSearchTool: true,
                realtimeVoice: false,
                mediaGeneration: false,
                usesMaxCompletionTokens: false,
                notes: supportsVision ? "DeepSeek 多模态识图模型" : "DeepSeek 文本/推理模型（不支持图片输入）"
            )
        }

        // Claude family (direct Anthropic OR via relay)
        if p == "claude" || id.hasPrefix("claude-") || id.contains("/claude-") {
            let supportsThinking = id.contains("3-7") || id.contains("3.7")
                || id.contains("claude-4") || id.contains("sonnet-4") || id.contains("opus-4") || id.contains("haiku-4")
                || id.contains("4-5") || id.contains("4.5") || id.contains("4-6") || id.contains("4.6")
                || id.contains("thinking")
            let proto: WuMindThinkingWireProtocol = supportsThinking
                ? (isRelayBaseURL && p == "openai" ? .openaiReasoningEffort : .claudeThinkingBudget)
                : .unsupported
            return WuMindModelCapabilities(
                textStreaming: true,
                thinkingProtocol: proto,
                visionAttachments: true,
                webSearchTool: true,
                realtimeVoice: false,
                mediaGeneration: false,
                usesMaxCompletionTokens: false,
                notes: "Claude 原生流式 + 识图" + (supportsThinking ? " + 扩展思考" : "")
            )
        }

        // Gemini family (direct Google OR via relay)
        if p == "gemini" || id.hasPrefix("gemini-") || id.contains("/gemini-") {
            let supportsThinking = id.contains("2.5") || id.contains("gemini-3") || id.contains("thinking")
            let proto: WuMindThinkingWireProtocol = supportsThinking
                ? (isRelayBaseURL && p == "openai" ? .openaiReasoningEffort : .geminiThinkingConfig)
                : .unsupported
            return WuMindModelCapabilities(
                textStreaming: true,
                thinkingProtocol: proto,
                visionAttachments: true,
                webSearchTool: true,
                realtimeVoice: false,
                mediaGeneration: false,
                usesMaxCompletionTokens: false,
                notes: "Gemini 原生 SSE 流式 + 多模态识图" + (supportsThinking ? " + 思考链" : "")
            )
        }

        // Grok / xAI family
        if p == "grok" || id.hasPrefix("grok-") || id.contains("/grok-") {
            let supportsThinking = id.contains("grok-3-mini") || id.contains("grok-4")
                || id.contains("reasoning") || id.contains("think")
            let supportsVision = id.contains("vision") || id.contains("grok-4") || id.contains("grok-2-vision")
                || id.contains("grok-3")
            return WuMindModelCapabilities(
                textStreaming: true,
                thinkingProtocol: supportsThinking ? .openaiReasoningEffort : .unsupported,
                visionAttachments: supportsVision,
                webSearchTool: true,
                realtimeVoice: false,
                mediaGeneration: false,
                usesMaxCompletionTokens: false,
                notes: "Grok 流式对话" + (supportsThinking ? " + reasoning_effort" : "")
            )
        }

        // OpenAI GPT / o-series (or OpenAI-compatible relay models)
        let isOSeries = id == "o1" || id.hasPrefix("o1-") || id == "o3" || id.hasPrefix("o3-")
            || id == "o4" || id.hasPrefix("o4-") || id.contains("/o1") || id.contains("/o3") || id.contains("/o4")
        let isGPT5 = id.hasPrefix("gpt-5") || id.contains("/gpt-5")
        let isThinkingOther = id.contains("qwq") || id.contains("qwen3") || id.contains("kimi-k2-thinking")
            || id.contains("reasoning") || id.contains("thinking")
        let supportsThinking = isOSeries || isGPT5 || isThinkingOther
        let isTextOnlyOpenAI = id == "o1-mini" || id.hasPrefix("o1-mini-") || id.hasPrefix("o3-mini")
            || id.contains("gpt-3.5")
        let supportsVision = !isTextOnlyOpenAI
        return WuMindModelCapabilities(
            textStreaming: true,
            thinkingProtocol: supportsThinking ? .openaiReasoningEffort : .unsupported,
            visionAttachments: supportsVision,
            webSearchTool: true,
            realtimeVoice: false,
            mediaGeneration: false,
            usesMaxCompletionTokens: isOSeries || isGPT5,
            notes: "OpenAI 兼容接口" + (supportsThinking ? " + reasoning_effort" : "") + (supportsVision ? " + 识图" : "（纯文本）")
        )
    }

    /// Strict pre-flight request validation: catches unsupported vision or deep-thinking combinations
    /// BEFORE network submission so WUMIND NEVER silently drops images or turns off deep thinking.
    public static func validateChatRequest(
        providerRaw: String,
        modelID: String,
        connectionLabel: String,
        isRelayBaseURL: Bool = false,
        deepThinking: Bool,
        attachedImageCount: Int
    ) -> WuMindPreflightViolation? {
        let caps = capabilities(providerRaw: providerRaw, modelID: modelID, isRelayBaseURL: isRelayBaseURL)
        if !caps.textStreaming {
            return .nonChatModelInChat(modelID: modelID, connectionLabel: connectionLabel)
        }
        if attachedImageCount > 0 && !caps.visionAttachments {
            return .visionNotSupported(modelID: modelID, connectionLabel: connectionLabel)
        }
        if deepThinking && !caps.supportsDeepThinking {
            return .deepThinkingNotSupported(modelID: modelID, connectionLabel: connectionLabel)
        }
        return nil
    }
}

// MARK: - Phase-Split Latency Breakdown & Call Trace Audit

public struct WuMindPhaseTimingMetrics: Codable, Equatable, Sendable {
    public var clientPrepMs: Int
    public var attachmentPrepMs: Int
    public var gatewayWaitMs: Int?
    public var upstreamTTFTMs: Int?
    public var firstRenderMs: Int?
    public var totalMs: Int?
    public var stopLatencyMs: Int?

    public init(
        clientPrepMs: Int = 0,
        attachmentPrepMs: Int = 0,
        gatewayWaitMs: Int? = nil,
        upstreamTTFTMs: Int? = nil,
        firstRenderMs: Int? = nil,
        totalMs: Int? = nil,
        stopLatencyMs: Int? = nil
    ) {
        self.clientPrepMs = max(0, clientPrepMs)
        self.attachmentPrepMs = max(0, attachmentPrepMs)
        self.gatewayWaitMs = gatewayWaitMs.map { max(0, $0) }
        self.upstreamTTFTMs = upstreamTTFTMs.map { max(0, $0) }
        self.firstRenderMs = firstRenderMs.map { max(0, $0) }
        self.totalMs = totalMs.map { max(0, $0) }
        self.stopLatencyMs = stopLatencyMs.map { max(0, $0) }
    }

    public var compactSummary: String {
        var parts: [String] = ["端侧准备 \(clientPrepMs)ms"]
        if attachmentPrepMs > 0 { parts.append("附件 \(attachmentPrepMs)ms") }
        if let gw = gatewayWaitMs { parts.append("网关/响应头 \(gw)ms") }
        if let ttft = upstreamTTFTMs { parts.append("首字 \(ttft)ms") }
        if let render = firstRenderMs { parts.append("首帧渲染 \(render)ms") }
        if let stop = stopLatencyMs { parts.append("停止响应 \(stop)ms") }
        return parts.joined(separator: " · ")
    }
}

public struct WuMindCallTraceRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let clientRequestID: String
    // Foreground user choices
    public let selectedChannel: String       // "WuMind 内置" | "自有 API"
    public let selectedProvider: String
    public let selectedModelID: String
    public let requestedDeepThinking: Bool
    public let attachedImageCount: Int
    public let requestedWebSearch: Bool
    // Actual wire execution
    public var actualModelID: String
    public var upstreamRoute: String         // "official" | "aihubmix" | "own_direct" | "own_relay"
    public var host: String
    public var endpointPath: String
    public var thinkingParamSent: String
    public var imagesSentCount: Int
    public var recoveredFromOriginalTask: Bool
    public var succeeded: Bool
    public var failureCode: String?
    public var timing: WuMindPhaseTimingMetrics

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        clientRequestID: String,
        selectedChannel: String,
        selectedProvider: String,
        selectedModelID: String,
        requestedDeepThinking: Bool,
        attachedImageCount: Int,
        requestedWebSearch: Bool,
        actualModelID: String,
        upstreamRoute: String,
        host: String,
        endpointPath: String,
        thinkingParamSent: String,
        imagesSentCount: Int,
        recoveredFromOriginalTask: Bool = false,
        succeeded: Bool = false,
        failureCode: String? = nil,
        timing: WuMindPhaseTimingMetrics = WuMindPhaseTimingMetrics()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.clientRequestID = clientRequestID
        self.selectedChannel = selectedChannel
        self.selectedProvider = selectedProvider
        self.selectedModelID = selectedModelID
        self.requestedDeepThinking = requestedDeepThinking
        self.attachedImageCount = attachedImageCount
        self.requestedWebSearch = requestedWebSearch
        self.actualModelID = actualModelID
        self.upstreamRoute = upstreamRoute
        self.host = host
        self.endpointPath = endpointPath
        self.thinkingParamSent = thinkingParamSent
        self.imagesSentCount = imagesSentCount
        self.recoveredFromOriginalTask = recoveredFromOriginalTask
        self.succeeded = succeeded
        self.failureCode = failureCode
        self.timing = timing
    }

    /// True if foreground selections match actual wire execution with zero silent degradation.
    public var isFidelityExact: Bool {
        let modelMatch = selectedModelID.caseInsensitiveCompare(actualModelID) == .orderedSame
        let imagesMatch = imagesSentCount == attachedImageCount
        let thinkingMatch = !requestedDeepThinking || (thinkingParamSent != "none" && !thinkingParamSent.isEmpty)
        return modelMatch && imagesMatch && thinkingMatch
    }
}

public struct WuMindLatencyPercentiles: Equatable, Sendable {
    public let count: Int
    public let p50Ms: Int
    public let p95Ms: Int
    public let minMs: Int
    public let maxMs: Int

    public static func compute(from samples: [Int]) -> WuMindLatencyPercentiles {
        let sorted = samples.filter { $0 >= 0 }.sorted()
        guard !sorted.isEmpty else {
            return WuMindLatencyPercentiles(count: 0, p50Ms: 0, p95Ms: 0, minMs: 0, maxMs: 0)
        }
        func percentile(_ p: Double) -> Int {
            let idx = Int(ceil(p * Double(sorted.count))) - 1
            return sorted[max(0, min(sorted.count - 1, idx))]
        }
        return WuMindLatencyPercentiles(
            count: sorted.count,
            p50Ms: percentile(0.50),
            p95Ms: percentile(0.95),
            minMs: sorted.first ?? 0,
            maxMs: sorted.last ?? 0
        )
    }
}

// MARK: - Anti-Fight Scroll Auto-Follow Policy

/// Pure state machine preventing streaming output from yanking the user back to the bottom
/// once they scroll upward to read earlier messages.
public struct WuMindScrollFollowState: Equatable, Sendable {
    public private(set) var isFollowing: Bool = true
    public private(set) var userDetached: Bool = false

    public init(isFollowing: Bool = true, userDetached: Bool = false) {
        self.isFollowing = isFollowing
        self.userDetached = userDetached
    }

    /// Called when the user drags downward (reading upward) by `translationY` points.
    public mutating func handleUserDrag(translationY: Double, isGenerating: Bool) {
        guard isGenerating else { return }
        if translationY > 8.0 {
            isFollowing = false
            userDetached = true
        }
    }

    /// Called whenever the bottom sentinel's distance below the ScrollView's visible bottom changes.
    /// `distanceBelowViewportBottom <= 0` means the bottom anchor is visible inside the viewport.
    public mutating func handleBottomDistance(_ distanceBelowViewportBottom: Double, isGenerating: Bool) {
        guard isGenerating else { return }
        if distanceBelowViewportBottom > 48.0 {
            isFollowing = false
            userDetached = true
        } else if userDetached && distanceBelowViewportBottom <= 16.0 {
            // User deliberately scrolled all the way back to the bottom -> re-enable follow
            isFollowing = true
            userDetached = false
        }
    }

    /// Called when user taps "回到最新" or sends a brand new prompt.
    public mutating func jumpToLatest() {
        isFollowing = true
        userDetached = false
    }

    /// Called when user taps "暂停滚动".
    public mutating func pauseFollow() {
        isFollowing = false
        userDetached = true
    }

    /// Whether a periodic streaming tick is permitted to call `scroller.scrollTo(bottom)`.
    public var shouldAutoScrollOnStreamTick: Bool {
        isFollowing && !userDetached
    }
}
