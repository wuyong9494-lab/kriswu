import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications

/// Stores optional custom HTTPS API base URLs per third-party provider (e.g. OpenRouter, SiliconFlow,
/// One-API/New-API relays, or reverse proxies). Empty/nil always uses the official provider endpoint.
/// Never stores API keys (keys stay device-only in iOS Keychain).
enum AIProviderEndpoints {
    private static func storageKey(for provider: AIProvider) -> String {
        "wumind.customBaseURL.\(provider.rawValue)"
    }

    static func baseURL(for provider: AIProvider) -> String? {
        guard let raw = UserDefaults.standard.string(forKey: storageKey(for: provider)) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func setBaseURL(_ raw: String?, for provider: AIProvider) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: storageKey(for: provider))
        } else {
            UserDefaults.standard.set(trimmed, forKey: storageKey(for: provider))
        }
    }

    static func displayHost(for provider: AIProvider) -> String? {
        guard let raw = baseURL(for: provider), let url = URL(string: raw) else { return nil }
        return url.host
    }

    private static let aihubmixBaseURLKey = "wumind.customBaseURL.aihubmix"
    private static let imageOwnConnectionModeKey = "wumind.imageStudio.ownConnectionMode"

    static var aihubmixBaseURL: String? {
        guard let raw = UserDefaults.standard.string(forKey: aihubmixBaseURLKey) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func setAIHubMixBaseURL(_ raw: String?) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: aihubmixBaseURLKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: aihubmixBaseURLKey)
        }
    }

    static var imageStudioOwnConnectionPreference: AIImageOwnConnectionPreference {
        get {
            guard let raw = UserDefaults.standard.string(forKey: imageOwnConnectionModeKey),
                  let pref = AIImageOwnConnectionPreference(rawValue: raw) else {
                return .auto
            }
            return pref
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: imageOwnConnectionModeKey)
        }
    }

    /// Resolves active AIHubMix connection (dedicated slot first; reuses GPT `.openAI` slot ONLY if its Base URL is verified AIHubMix/Inferera).
    static func resolvedAIHubMixConnection() -> AIImageAIHubMixConnection? {
        AIImageAIHubMixConnection.resolve(
            dedicatedKey: Keychain.aihubmixAPIKey,
            dedicatedBaseURL: aihubmixBaseURL,
            openAIKey: Keychain.providerChatAPIKey(.openAI),
            openAIBaseURL: baseURL(for: .openAI)
        )
    }

    /// Single authoritative credential & catalog snapshot shared by Model Center and Image Studio.
    @MainActor
    static func currentImageCredentialSnapshot(
        store: WuMindStore,
        isCatalogSyncing: Bool = false
    ) -> AIImageCredentialSnapshot {
        let directKeys = Set(AIProvider.allCases.filter { Keychain.providerChatAPIKey($0) != nil })
        var directURLs: [AIProvider: String] = [:]
        for p in AIProvider.allCases {
            if let u = baseURL(for: p) {
                directURLs[p] = u
            }
        }
        let loggedIn = store.isRegisteredWuMindUser
            || (Keychain.wumindGatewayUserToken?.isEmpty == false)
            || !store.managedAccountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return AIImageCredentialSnapshot(
            useManagedGateway: store.channel == .managed,
            isGatewayConfigured: store.hasGatewayURL,
            isGatewayLoggedIn: loggedIn,
            isGatewayCatalogSyncing: isCatalogSyncing,
            enabledManagedImageModels: store.enabledManagedImageModels,
            ownPreference: imageStudioOwnConnectionPreference,
            aihubmixConnection: resolvedAIHubMixConnection(),
            directProviderKeys: directKeys,
            directProviderBaseURLs: directURLs
        )
    }
}

/// Unified provider enum for the WUMIND multi-model AI workspace.
enum WuMindProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case deepSeek
    case openAI
    case gemini
    case claude
    case grok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .openAI: return "OpenAI / GPT"
        case .gemini: return "Google Gemini"
        case .claude: return "Anthropic Claude"
        case .grok: return "xAI Grok"
        }
    }

    var shortName: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .openAI: return "GPT"
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        case .grok: return "Grok"
        }
    }

    var subtitle: String {
        switch self {
        case .deepSeek: return "V4 Pro 旗舰 · Flash 极速 · 深度思考"
        case .openAI: return "GPT-5 / GPT-4 / o3 / o4 系列"
        case .gemini: return "Gemini 2.5 Pro / Flash 多模态推理"
        case .claude: return "Claude Sonnet / Opus 深度写作与编程"
        case .grok: return "xAI Grok 实时推理与对话"
        }
    }

    var iconName: String {
        switch self {
        case .deepSeek: return "sparkles"
        case .openAI: return "circle.hexagongrid.fill"
        case .gemini: return "diamond.fill"
        case .claude: return "sun.max.fill"
        case .grok: return "bolt.fill"
        }
    }

    var brandColor: Color {
        switch self {
        case .deepSeek: return Color(red: 0.30, green: 0.45, blue: 1.00)
        case .openAI: return Color(red: 0.08, green: 0.68, blue: 0.52)
        case .gemini: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .claude: return Color(red: 0.85, green: 0.48, blue: 0.28)
        case .grok: return Color(red: 0.58, green: 0.44, blue: 0.94)
        }
    }

    var multiProvider: AIProvider? {
        switch self {
        case .deepSeek: return nil
        case .openAI: return .openAI
        case .gemini: return .gemini
        case .claude: return .claude
        case .grok: return .grok
        }
    }

    static func from(_ provider: AIProvider) -> WuMindProvider? {
        switch provider {
        case .openAI: return .openAI
        case .gemini: return .gemini
        case .claude: return .claude
        case .grok: return .grok
        }
    }

    var supportsDeepThinkingToggle: Bool {
        switch self {
        case .deepSeek, .openAI, .gemini, .claude, .grok: return true
        }
    }

    func apiKey() -> String? {
        switch self {
        case .deepSeek:
            let key = Keychain.get(.deepSeekPlanAPIKey)
            return (key?.isEmpty == false) ? key : nil
        case .openAI, .gemini, .claude, .grok:
            guard let p = multiProvider else { return nil }
            let key = Keychain.providerChatAPIKey(p)
            return (key?.isEmpty == false) ? key : nil
        }
    }

    var hasKey: Bool { apiKey() != nil }
}

struct WuMindModelOption: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let provider: WuMindProvider
    let supportsTextChat: Bool

    var capability: AIProviderModel.Capability {
        AIProviderModel.classify(id: id, supportsTextChat: supportsTextChat)
    }

    static let deepSeekDefaults: [WuMindModelOption] = [
        WuMindModelOption(id: DeepSeekChatClient.Model.pro.rawValue,
                          displayName: "DeepSeek V4 Pro",
                          provider: .deepSeek,
                          supportsTextChat: true),
        WuMindModelOption(id: DeepSeekChatClient.Model.flash.rawValue,
                          displayName: "DeepSeek Flash",
                          provider: .deepSeek,
                          supportsTextChat: true),
    ]
}

struct WuMindTurn: Codable, Identifiable, Equatable, Sendable {
    enum State: Codable, Equatable, Sendable {
        case generating
        case complete
        case stopped
        case failed(String)

        private enum CodingKeys: String, CodingKey { case kind, message }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(String.self, forKey: .kind)
            switch kind {
            case "complete": self = .complete
            case "stopped", "generating": self = .stopped
            case "failed":
                let msg = (try? container.decode(String.self, forKey: .message)) ?? "生成未完成"
                self = .failed(msg)
            default: self = .stopped
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .generating: try container.encode("generating", forKey: .kind)
            case .complete: try container.encode("complete", forKey: .kind)
            case .stopped: try container.encode("stopped", forKey: .kind)
            case .failed(let msg):
                try container.encode("failed", forKey: .kind)
                try container.encode(msg, forKey: .message)
            }
        }
    }

    let id: UUID
    let question: String
    var reasoning: String
    var reasoningSeconds: Double?
    var answer: String
    var modelLabel: String
    var provider: WuMindProvider
    var isDeepThinking: Bool
    var state: State
    var createdAt: Date
    var promptTokens: Int?
    var completionTokens: Int?
    var reasoningTokens: Int?
    var costYuan: Double?
    var attachmentNames: [String]?
    var agentSteps: [WuMindAgentStep]?
    var actualChannelLabel: String?
    var failureStage: String?
    var comparisons: [WuMindComparisonResult]?
    var firstTokenMs: Int?
    var totalLatencyMs: Int?
    var taskChainID: String?
    var modelCapabilityBadge: String?
    var webCitations: [WuMindWebCitation]?
    var agentCitations: [WuMindAgentCitation]?
    var toolFailureNotices: [WuMindToolFailureNotice]?
    var assistantIntroLead: String?
    var clientRequestID: String?
    var callTrace: WuMindCallTraceRecord?
    var chatBuildWorkID: String? = nil

    init(id: UUID = UUID(),
         question: String,
         reasoning: String = "",
         reasoningSeconds: Double? = nil,
         answer: String = "",
         modelLabel: String,
         provider: WuMindProvider,
         isDeepThinking: Bool,
         state: State = .generating,
         createdAt: Date = Date(),
         promptTokens: Int? = nil,
         completionTokens: Int? = nil,
         reasoningTokens: Int? = nil,
         costYuan: Double? = nil,
         attachmentNames: [String]? = nil,
         agentSteps: [WuMindAgentStep]? = nil,
         actualChannelLabel: String? = nil,
         failureStage: String? = nil,
         comparisons: [WuMindComparisonResult]? = nil,
         firstTokenMs: Int? = nil,
         totalLatencyMs: Int? = nil,
         taskChainID: String? = nil,
         modelCapabilityBadge: String? = nil,
         webCitations: [WuMindWebCitation]? = nil,
         agentCitations: [WuMindAgentCitation]? = nil,
         toolFailureNotices: [WuMindToolFailureNotice]? = nil,
         assistantIntroLead: String? = nil,
         clientRequestID: String? = nil,
         callTrace: WuMindCallTraceRecord? = nil) {
        self.id = id
        self.question = question
        self.reasoning = reasoning
        self.reasoningSeconds = reasoningSeconds
        self.answer = answer
        self.modelLabel = modelLabel
        self.provider = provider
        self.isDeepThinking = isDeepThinking
        self.state = state
        self.createdAt = createdAt
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.costYuan = costYuan
        self.attachmentNames = attachmentNames
        self.agentSteps = agentSteps
        self.actualChannelLabel = actualChannelLabel
        self.failureStage = failureStage
        self.comparisons = comparisons
        self.firstTokenMs = firstTokenMs
        self.totalLatencyMs = totalLatencyMs
        self.taskChainID = taskChainID
        self.modelCapabilityBadge = modelCapabilityBadge
        self.webCitations = webCitations
        self.agentCitations = agentCitations
        self.toolFailureNotices = toolFailureNotices
        self.assistantIntroLead = assistantIntroLead
        self.clientRequestID = clientRequestID
        self.callTrace = callTrace
    }
}

/// Dual-channel execution mode in WUMIND:
/// - `ownAPI`: User supplies their own API keys (zero markup, direct to provider or custom relay).
/// - `managed`: User connects via WUMIND's Managed Billing Gateway (real-time token metering & recharge).
enum WuMindChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case ownAPI
    case managed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ownAPI: return "自带 API"
        case .managed: return "WUMIND 内置"
        }
    }

    var badgeText: String {
        switch self {
        case .ownAPI: return "自配密钥 · 直连厂商"
        case .managed: return "免配 Key · 充值按量实时计费"
        }
    }
}

struct WuMindAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let document: WuMindAttachmentParser.ExtractedDocument

    init(id: UUID = UUID(), document: WuMindAttachmentParser.ExtractedDocument) {
        self.id = id
        self.document = document
    }

    var iconName: String {
        switch document.kind {
        case .pdf: return "doc.richtext.fill"
        case .word: return "doc.text.fill"
        case .excel: return "tablecells.fill"
        case .code: return "curlybraces"
        case .text: return "doc.plaintext.fill"
        case .image: return "photo.fill"
        }
    }

    var tintColor: Color {
        switch document.kind {
        case .pdf: return .red
        case .word: return .blue
        case .excel: return .green
        case .code: return .orange
        case .text: return .secondary
        case .image: return .purple
        }
    }
}

struct WuMindConversation: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var provider: WuMindProvider
    var modelID: String
    var modelDisplayName: String
    var deepThinking: Bool
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date
    var turns: [WuMindTurn]
    var compactedSummary: String?
    var compactedTurnCount: Int?
    var projectID: UUID?
    var sharedMaterials: [WuMindThreadMaterial]?
    var isArchived: Bool
    var archivedAt: Date?
    var archiveStateUpdatedAt: Date?

    var safeCompactedTurnCount: Int {
        min(max(0, compactedTurnCount ?? 0), turns.count)
    }

    init(id: UUID = UUID(),
         title: String = "新对话",
         provider: WuMindProvider = .deepSeek,
         modelID: String = DeepSeekChatClient.Model.pro.rawValue,
         modelDisplayName: String = "DeepSeek V4 Pro",
         deepThinking: Bool = true,
         isPinned: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         turns: [WuMindTurn] = [],
         compactedSummary: String? = nil,
         compactedTurnCount: Int? = nil,
         projectID: UUID? = nil,
         sharedMaterials: [WuMindThreadMaterial]? = nil,
         isArchived: Bool = false,
         archivedAt: Date? = nil,
         archiveStateUpdatedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.provider = provider
        self.modelID = modelID
        self.modelDisplayName = modelDisplayName
        self.deepThinking = deepThinking
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.turns = turns
        self.compactedSummary = compactedSummary
        self.compactedTurnCount = compactedTurnCount
        self.projectID = projectID
        self.sharedMaterials = sharedMaterials
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.archiveStateUpdatedAt = archiveStateUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, provider, modelID, modelDisplayName, deepThinking, isPinned
        case createdAt, updatedAt, turns, compactedSummary, compactedTurnCount
        case projectID, sharedMaterials, isArchived, archivedAt, archiveStateUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        provider = try c.decode(WuMindProvider.self, forKey: .provider)
        modelID = try c.decode(String.self, forKey: .modelID)
        modelDisplayName = try c.decode(String.self, forKey: .modelDisplayName)
        deepThinking = try c.decode(Bool.self, forKey: .deepThinking)
        isPinned = try c.decode(Bool.self, forKey: .isPinned)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        turns = try c.decode([WuMindTurn].self, forKey: .turns)
        compactedSummary = try c.decodeIfPresent(String.self, forKey: .compactedSummary)
        compactedTurnCount = try c.decodeIfPresent(Int.self, forKey: .compactedTurnCount)
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        sharedMaterials = try c.decodeIfPresent([WuMindThreadMaterial].self, forKey: .sharedMaterials)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        archiveStateUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .archiveStateUpdatedAt)
    }

    static func autoTitle(from prompt: String) -> String {
        let singleLine = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return "新对话" }
        if singleLine.count <= 24 { return singleLine }
        return String(singleLine.prefix(24)) + "…"
    }
}

/// Reusable AI Skill (role/system prompt preset) for WUMIND — supports both built-in flagship skills
/// and user-created custom skills persisted locally.
struct WuMindSkill: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var name: String
    var icon: String
    var summary: String
    var prompt: String
    var isBuiltIn: Bool

    static let builtIn: [WuMindSkill] = [
        WuMindSkill(
            id: "builtin.deep_research",
            name: "全网深度调研（Deep Research）",
            icon: "magnifyingglass.circle.fill",
            summary: "自主拆解问题 → 联网搜索多源交叉验证 → 输出带引用链接的研究报告",
            prompt: "你是旗舰级 Deep Research 深度调研智能体。面对复杂问题时：1) 先拆解 2–3 个关键检索维度；2) 主动调用 web_search 检索权威最新资料，并对核心来源调用 web_fetch 核实细节；3) 交叉比对不同信源并剔除矛盾；4) 输出结构化深度研报（核心结论、分维度证据与对比表、可点击原始参考来源链接）。",
            isBuiltIn: true
        ),
        WuMindSkill(
            id: "builtin.architect",
            name: "全栈编程与排错",
            icon: "chevron.left.forwardslash.chevron.right",
            summary: "Swift / Python / 架构评审与精准修复",
            prompt: "你是一位资深全栈与移动端架构师。回答问题先给核心结论，再给可直接运行的完整代码与边界条件检查；如果上下文附带了 GitHub 仓库、附件源码或报错日志，严格基于真实文件名与内容分析，不要凭空编造不存在的 API。",
            isBuiltIn: true
        ),
        WuMindSkill(
            id: "builtin.docs",
            name: "文档与表格精读",
            icon: "doc.text.magnifyingglass",
            summary: "精读上传的 PDF / Word / Excel / 截图并提炼结论",
            prompt: "你是顶尖文档与数据审阅专家。请严格依据用户上传的 PDF、Word、Excel 表格或图片 OCR 内容作答：先用 3 条核心要点总结全貌，再按章节/表格指标精准提取关键数据、风险条款与待办事项；任何原文件未提及的信息须明确注明「未在附件中出现」。",
            isBuiltIn: true
        ),
        WuMindSkill(
            id: "builtin.github",
            name: "GitHub 仓库架构师",
            icon: "hammer.fill",
            summary: "结合已连接 GitHub 仓库做代码审查与方案拆解",
            prompt: "你是 GitHub 工程审阅与代码架构专家。请结合已附加的 GitHub 仓库结构、README、提交记录和源码文件，输出清晰的模块关系、潜在缺陷定位以及最小侵入式的可执行改造步骤。",
            isBuiltIn: true
        ),
        WuMindSkill(
            id: "builtin.contract",
            name: "标书与合同风控",
            icon: "checkmark.shield.fill",
            summary: "逐条排查招标书/合同陷阱、废标项与商务风险",
            prompt: "你是资深招投标与法务合规审阅专家。请对用户粘贴或上传的标书/合同文本进行逐项风险排查，按「致命废标/违约项」「商务与工期风险」「技术响应缺口」「逐条修改建议」四部分清晰输出。",
            isBuiltIn: true
        ),
        WuMindSkill(
            id: "builtin.duty",
            name: "值班保障与公文",
            icon: "doc.richtext",
            summary: "运行保障总结、交班复盘、正式汇报润色",
            prompt: "你是一位熟悉卫星测控与值班运行保障的资深文字与汇报专家。输出结构清晰、用语克制专业、重点突出（现状 / 风险 / 处置 / 下一步计划），不夸大不杜撰未提供的数据。",
            isBuiltIn: true
        ),
        WuMindSkill(
            id: "builtin.research",
            name: "深度研报与决策",
            icon: "chart.xyaxis.line",
            summary: "第一性原理拆解、多方案量化对比",
            prompt: "你是顶级战略与技术分析师。请使用第一性原理剖析问题，列出清晰假设、正反权衡矩阵、关键风险点与分阶段可执行行动清单。",
            isBuiltIn: true
        ),
        WuMindSkill(
            id: "builtin.translate",
            name: "中英专业精翻",
            icon: "globe",
            summary: "技术文档、标书与学术论文地道双语互译",
            prompt: "你是专业双语技术翻译与润色专家。中文输入译为地道专业英文，英文输入译为流畅准确中文；保留专有名词与代码块原貌，必要时附简要术语说明。",
            isBuiltIn: true
        ),
        WuMindSkill(
            id: "builtin.concise",
            name: "极速精简直答",
            icon: "bolt.fill",
            summary: "去废话、直奔答案与关键步骤",
            prompt: "请用最简洁、直接、高信息密度的方式回答问题：先给 1 句话直接结论，再用不超过 5 条要点列出关键步骤，不写客套话。",
            isBuiltIn: true
        ),
    ]
}

/// Isolated high-frequency streaming buffer observed ONLY by the single currently-streaming turn view.
/// Prevents per-token SSE updates from invalidating the entire `WuMindStore` and `WuMindWorkspaceView` tree.
@MainActor
final class WuMindStreamBuffer: ObservableObject {
    enum InlineStatusKind: String, Equatable, Sendable {
        case searching
        case reading
        case agent
        case warning
    }

    var reasoning: String = ""
    var answer: String = ""
    var reasoningSeconds: Double? = nil
    var agentSteps: [WuMindAgentStep] = []
    var activeAgentPhase: String? = nil
    var inlineStatusKind: InlineStatusKind? = nil
    var inlineStatusText: String? = nil
    var inlineIntroLead: String? = nil
    var liveWebCitations: [WuMindWebCitation] = []
    var liveAgentCitations: [WuMindAgentCitation] = []
    var liveToolFailures: [WuMindToolFailureNotice] = []
    var liveElapsedSeconds: Int = 0
    let answerLayoutChanges = PassthroughSubject<Void, Never>()
    @Published var tick: UInt64 = 0

    func reset() {
        reasoning = ""
        answer = ""
        reasoningSeconds = nil
        agentSteps = []
        activeAgentPhase = nil
        inlineStatusKind = nil
        inlineStatusText = nil
        inlineIntroLead = nil
        liveWebCitations = []
        liveAgentCitations = []
        liveToolFailures = []
        liveElapsedSeconds = 0
        tick &+= 1
    }
}

/// Honest, non-secret per-provider connection verification state (never stores API keys).
/// Strictly separates "catalog readable (/v1/models succeeded)" from "real chat inference succeeded".
struct WuMindProviderVerification: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case saved            // Key saved locally, not yet probed (amber)
        case catalogReadable  // Listing /v1/models succeeded, individual models not yet smoke-tested (blue)
        case verified         // Real inference or live model smoke test succeeded (green)
        case failed           // Live probe or chat failed with host + sanitized code (red)
    }

    var status: Status
    var host: String
    var summary: String
    var updatedAt: Date

    var badgeText: String {
        switch status {
        case .saved: return "已保存"
        case .catalogReadable: return "目录可读"
        case .verified: return "已试跑可用"
        case .failed: return "验证失败"
        }
    }

    var dotColor: Color {
        switch status {
        case .saved: return .orange
        case .catalogReadable: return .blue
        case .verified: return .green
        case .failed: return .red
        }
    }
}

/// Per-model real inference smoke-test / runtime status (keyed by provider + modelID).
struct WuMindModelSmokeRecord: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case passed
        case failed
    }

    var status: Status
    var host: String
    var endpointPath: String?
    var httpStatus: Int?
    var errorCode: String?
    var detail: String
    var latencyMs: Int?
    var testedAt: Date

    var badgeText: String {
        switch status {
        case .passed:
            if let latencyMs {
                return "已试跑 · \(latencyMs)ms"
            }
            return "已试跑可用"
        case .failed:
            if let httpStatus {
                return "不可用 HTTP \(httpStatus)"
            }
            return "调用失败"
        }
    }

    var dotColor: Color {
        status == .passed ? .green : .red
    }
}

private struct WuMindDiskSnapshot: Codable, Sendable {
    var conversations: [WuMindConversation]
    var cachedModels: [String: [WuMindModelOption]]
    var lastProvider: WuMindProvider
    var lastModelID: String
    var lastModelName: String
    var lastDeepThinking: Bool
    var consentedProviders: [String]
    var customSkills: [WuMindSkill]?
    var activeSkillID: String?
    var channel: WuMindChannel?
    var gatewayBaseURL: String?
    var managedAccountID: String?
    var managedBalanceYuan: Double?
    var managedSelectedModelID: String?
    var managedConfig: WuMindCommercialConfig?
    var maxContextTokens: Int?
    var autoCompactContext: Bool?
    var projects: [WuMindProject]?
    var activeProjectID: UUID?
    var installedConnectorIDs: [String]?
    var connectorEndpoints: [String: String]?
    var scheduledTasks: [WuMindScheduledTask]?
    var memories: [WuMindMemoryItem]?
    var preferences: WuMindPreferences?
    var agentModeEnabled: Bool?
    var providerVerifications: [String: WuMindProviderVerification]?
    var modelSmokeRecords: [String: WuMindModelSmokeRecord]?
    var registeredDisplayName: String?
    var registeredRole: String?
    var managedCatalogModels: [WuMindCatalogModel]?
}

private struct WuMindAccountPrivateSnapshot: Codable, Sendable {
    var conversations: [WuMindConversation]
    var projects: [WuMindProject]
    var activeProjectID: UUID?
    var memories: [WuMindMemoryItem]
    var scheduledTasks: [WuMindScheduledTask]
    var customSkills: [WuMindSkill]
    var activeSkillID: String?
}

/// Persistent local conversation history, Projects, Customizations, Scheduled Tasks,
/// Multi-Step Agent Engine, & Flagship Settings for WUMIND.
/// Never stores API keys; keys stay strictly device-only in iOS Keychain.
@MainActor
final class WuMindStore: ObservableObject {
    static let shared = WuMindStore()

    /// High-frequency streaming display buffer (intentionally NOT `@Published` on WuMindStore).
    let streamBuffer = WuMindStreamBuffer()

    @Published var conversations: [WuMindConversation] = []
    @Published var activeConversationID: UUID?
    @Published var selectedProvider: WuMindProvider = .deepSeek
    @Published var selectedModelID: String = DeepSeekChatClient.Model.pro.rawValue
    @Published var selectedModelName: String = "DeepSeek V4 Pro"
    @Published var deepThinking: Bool = true
    @Published var cachedModels: [WuMindProvider: [WuMindModelOption]] = [
        .deepSeek: WuMindModelOption.deepSeekDefaults
    ]
    @Published var providerVerifications: [String: WuMindProviderVerification] = [:]
    @Published var modelSmokeRecords: [String: WuMindModelSmokeRecord] = [:]
    @Published var consentedProviders: Set<String> = []
    @Published var customSkills: [WuMindSkill] = []
    @Published var activeSkillID: String? = nil
    @Published var attachedGitHubContext: WuMindGitHubClient.RepoContext? = nil
    @Published var pendingAttachments: [WuMindAttachment] = []

    // Flagship Workspaces, Customizations, Automations, Memory, & Agent Mode
    @Published var projects: [WuMindProject] = []
    @Published var activeProjectID: UUID? = nil
    @Published var installedConnectorIDs: Set<String> = WuMindConnectorSpec.defaultInstalledIDs
    @Published var connectorEndpoints: [String: String] = [:]
    @Published var scheduledTasks: [WuMindScheduledTask] = []
    @Published var memories: [WuMindMemoryItem] = []
    @Published var preferences: WuMindPreferences = WuMindPreferences()
    @Published var agentModeEnabled: Bool = false
    @Published var webSearchEnabled: Bool = false
    @Published var runningScheduleID: UUID? = nil

    // Background-resilient generation lifecycle state (persists across view close / tab switch / iOS backgrounding)
    @Published var activeTurnID: UUID? = nil
    @Published var activeGenerationConversationID: UUID? = nil
    @Published var thinkingStartedAt: Date? = nil
    @Published var compactingContext: Bool = false

    // 1M Context & Claude-Style Auto-Compaction settings
    @Published var maxContextTokens: Int = WuMindContextEngine.maxSupportedContextTokens
    @Published var autoCompactContext: Bool = true

    // Dual-Channel Managed Billing Gateway state
    @Published var channel: WuMindChannel = .ownAPI
    @Published var gatewayBaseURL: String = ""
    @Published var managedAccountID: String = ""
    @Published var registeredDisplayName: String = ""
    @Published var registeredRole: String = ""
    @Published var managedBalanceYuan: Double? = nil
    @Published var managedAccountStatus: WuMindAccountStatus? = nil
    @Published var managedSelectedModelID: String = "deepseek-reasoner"
    @Published var managedConfig: WuMindCommercialConfig = WuMindCommercialConfig()
    @Published var managedCatalogModels: [WuMindCatalogModel] = []
    @Published var managedPaymentOrders: [WuMindPaymentOrder] = []
    @Published var lastUpstreamBalanceNotice: String? = nil

    // Cross-Device Zero-Knowledge Sync state
    @Published var isSyncingCloud: Bool = false
    @Published var lastCloudSyncAt: Date? = nil
    @Published var cloudSyncVersion: Int = 0
    @Published var lastCloudSyncDevice: String? = nil

    @Published var recentCallTraces: [WuMindCallTraceRecord] = []

    private let maxStoredConversations = 120
    private let saveIOQueue = DispatchQueue(label: "com.kriswu.wumind.diskio", qos: .utility)
    private var saveTask: Task<Void, Never>?
    private var activeGenerationTask: Task<Void, Never>?
    private var flushTimerTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var pendingReasoning = ""
    private var pendingAnswer = ""
    private var pendingReasoningSeconds: Double? = nil
    private var pendingFirstTokenMs: Int? = nil
    private var pendingFirstRenderMs: Int? = nil
    private var pendingCallTrace: WuMindCallTraceRecord? = nil
    private var pendingDeferredBalanceYuan: Double? = nil
    private var generationStartedAt: Date? = nil
    private var pendingAgentSteps: [WuMindAgentStep] = []
    private var pendingActiveAgentPhase: String? = nil
    private var pendingInlineStatusKind: WuMindStreamBuffer.InlineStatusKind? = nil
    private var pendingInlineStatusText: String? = nil
    private var pendingIntroLead: String? = nil
    private var pendingWebCitations: [WuMindWebCitation] = []
    private var pendingAgentCitations: [WuMindAgentCitation] = []
    struct SearchContinuationPrompt: Equatable {
        let turnID: UUID
        let message: String
        let gatewayAction: String?
    }

    @Published private(set) var searchContinuationPrompt: SearchContinuationPrompt?
    private var searchChoiceContinuation: CheckedContinuation<WuMindSearchRouting.Choice, Never>?

    func resolveSearchContinuation(turnID: UUID, choice: WuMindSearchRouting.Choice) {
        guard let prompt = searchContinuationPrompt, prompt.turnID == turnID,
              choice != .tryGateway || prompt.gatewayAction != nil,
              let continuation = searchChoiceContinuation else { return }
        searchChoiceContinuation = nil
        searchContinuationPrompt = nil
        continuation.resume(returning: choice)
    }

    private func askSearchContinuation(
        turnID: UUID,
        message: String,
        gatewayAction: String? = nil
    ) async -> WuMindSearchRouting.Choice {
        guard !Task.isCancelled, activeTurnID == turnID, searchChoiceContinuation == nil else { return .cancel }
        return await withCheckedContinuation { continuation in
            searchChoiceContinuation = continuation
            searchContinuationPrompt = SearchContinuationPrompt(
                turnID: turnID, message: message, gatewayAction: gatewayAction
            )
        }
    }

    private var pendingToolFailures: [WuMindToolFailureNotice] = []
    private var streamDirty = false
    private(set) var activeStorageOwnerID: String = "local"

    private func setInlineStatus(_ kind: WuMindStreamBuffer.InlineStatusKind?, text: String?) {
        pendingInlineStatusKind = kind
        pendingInlineStatusText = text
        streamBuffer.inlineStatusKind = kind
        streamBuffer.inlineStatusText = text
        streamBuffer.tick &+= 1
        streamDirty = true
    }

    var currentStorageOwnerID: String {
        WuMindAccountStorageScope.resolvedOwnerID(
            managedAccountID: managedAccountID,
            externalWuMindUserID: AppAccountManager.shared.externalProfile?.wumindUserID,
            externalProfileID: AppAccountManager.shared.externalProfile?.id
        )
    }

    func modelCapabilityBadge(
        channel: WuMindChannel,
        provider: WuMindProvider,
        modelID: String,
        hasUsedToolsOrMultimodal: Bool = false
    ) -> String {
        if channel == .managed {
            if let catalog = managedCatalogModels.first(where: { $0.id == modelID }),
               catalog.enabled && !catalog.isPendingPricing {
                return hasUsedToolsOrMultimodal ? "能力已验证" : "文字已通过"
            }
            return "目录可见"
        }
        let rec = modelSmokeRecords[smokeKey(provider: provider, modelID: modelID)]
        if rec?.status == .passed {
            return hasUsedToolsOrMultimodal ? "能力已验证" : "文字已通过"
        }
        return "目录可见"
    }

    var isGenerating: Bool { activeTurnID != nil }

    var isBillingExempt: Bool {
        managedAccountStatus?.isBillingExempt == true
    }

    /// True once the current user (internal duty staff OR external user) has registered a WUMIND user profile.
    var isRegisteredWuMindUser: Bool {
        let hasName = !registeredDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAccount = !managedAccountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (Keychain.wumindGatewayUserToken?.isEmpty == false)
        return hasName && hasAccount
    }

    /// Mandatory WUMIND registration gate for ALL users (internal duty roster staff & external users alike).
    /// Bypassed only in automated UI test/screenshot demo launch mode.
    var requiresWuMindRegistration: Bool {
        if AppStore.isDemo || UserDefaults.standard.string(forKey: "screen") != nil {
            return false
        }
        return !isRegisteredWuMindUser
    }

    var activeGenerationConversationTitle: String? {
        guard let id = activeGenerationConversationID else { return nil }
        return conversations.first(where: { $0.id == id })?.title
    }

    private init() {
        load()
        if gatewayBaseURL.isEmpty,
           let bundled = Bundle.main.object(forInfoDictionaryKey: "WuMindGatewayURL") as? String,
           let address = try? WuMindGatewayConfiguration.address(bundled) {
            gatewayBaseURL = address
        }
    }

    /// Authoritative verified + priced + enabled catalog models from Gateway.
    var callableCatalogModels: [WuMindCatalogModel] {
        let source = managedCatalogModels.isEmpty ? (managedConfig.callableModels ?? []) : managedCatalogModels
        return source.filter { $0.enabled && !$0.isDeprecated && $0.isVerified && $0.isPriced }
    }

    /// Strictly CHAT-capable managed models (never exposes image-only or video-only models in Chat picker!).
    var enabledManagedModels: [WuMindPricingItem] {
        let chatCatalog = callableCatalogModels.filter(\.supportsChat)
        if !chatCatalog.isEmpty {
            return chatCatalog.map { m in
                WuMindPricingItem(
                    id: m.id,
                    provider: m.resolvedProvider,
                    displayName: m.displayName,
                    inputPricePerMillion: m.inputPricePerMillion,
                    outputPricePerMillion: m.outputPricePerMillion,
                    officialReferenceNote: m.officialReferenceNote ?? "",
                    supportsThinking: m.supportsThinking ?? false,
                    enabled: true
                )
            }
        }
        return managedConfig.pricing.filter(\.enabled)
    }

    /// Strictly IMAGE-capable managed models (text-to-image + reference-image edit).
    var enabledManagedImageModels: [WuMindCatalogModel] {
        callableCatalogModels.filter { $0.supportsTextToImage || $0.supportsImageEdit }
    }

    /// Strictly REFERENCE-IMAGE-EDIT-capable managed models.
    var enabledManagedImageEditModels: [WuMindCatalogModel] {
        callableCatalogModels.filter(\.supportsImageEdit)
    }

    /// Strictly VIDEO-capable managed models.
    var enabledManagedVideoModels: [WuMindCatalogModel] {
        callableCatalogModels.filter(\.supportsVideo)
    }

    var activeManagedModel: WuMindPricingItem? {
        enabledManagedModels.first(where: { $0.id == managedSelectedModelID }) ?? enabledManagedModels.first
    }

    var activeModelDisplayName: String {
        if channel == .managed {
            return activeManagedModel?.displayName ?? "WUMIND 内置模型"
        }
        let name = selectedModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? selectedProvider.displayName : name
    }

    var activeProviderForDisplay: WuMindProvider {
        if channel == .managed, let raw = activeManagedModel?.provider, let p = WuMindProvider(rawValue: raw) {
            return p
        }
        return selectedProvider
    }

    var activeModelCapabilities: WuMindModelCapabilities {
        let modelID = channel == .managed
            ? (activeManagedModel?.id ?? managedSelectedModelID)
            : selectedModelID
        let provider = activeProviderForDisplay
        let isRelay: Bool = {
            guard channel == .ownAPI, let mp = provider.multiProvider else { return false }
            return ((try? AIProvider.normalizedBaseURL(AIProviderEndpoints.baseURL(for: mp))) ?? nil) != nil
        }()
        return WuMindModelCapabilityMatrix.capabilities(
            providerRaw: provider.rawValue,
            modelID: modelID,
            isRelayBaseURL: isRelay
        )
    }

    var activeSupportsDeepThinking: Bool {
        if channel == .managed, let m = activeManagedModel {
            return m.supportsThinking && activeModelCapabilities.supportsDeepThinking
        }
        return activeModelCapabilities.supportsDeepThinking
    }

    /// True ONLY when the active Connection × Model genuinely supports multimodal image input.
    var activeSupportsNativeVision: Bool {
        activeModelCapabilities.visionAttachments
    }

    var hasGatewayURL: Bool {
        (try? WuMindGatewayConfiguration.address(gatewayBaseURL)) != nil
    }

    func setChannel(_ newChannel: WuMindChannel) {
        channel = newChannel
        scheduleSave()
    }

    func selectManagedModel(_ item: WuMindPricingItem) {
        channel = .managed
        managedSelectedModelID = item.id
        scheduleSave()
    }

    /// A user-initiated Save must acknowledge the disk write, not merely queue it.
    func updateGatewayURL(_ raw: String) throws {
        let saved = try WuMindGatewayConfiguration.persistAddress(raw) { address in
            let snapshot = makeSettingsSnapshot(gatewayURLOverride: address)
            let url = try Self.settingsURL(create: true)
            let data = try JSONEncoder().encode(snapshot)
            try saveIOQueue.sync {
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            }
        }
        gatewayBaseURL = saved
    }

    func updateManagedConfigLocally(_ config: WuMindCommercialConfig) {
        managedConfig = config
        if let callable = config.callableModels {
            managedCatalogModels = callable
        }
        if !enabledManagedModels.contains(where: { $0.id == managedSelectedModelID }),
           let first = enabledManagedModels.first {
            managedSelectedModelID = first.id
        }
        scheduleSave()
    }

    func addAttachment(_ doc: WuMindAttachmentParser.ExtractedDocument) {
        if pendingAttachments.count >= 6 {
            pendingAttachments.removeFirst()
        }
        pendingAttachments.append(WuMindAttachment(document: doc))
    }

    func removeAttachment(_ id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func clearAttachments() {
        pendingAttachments.removeAll()
    }

    func syncManagedGatewayConfig() async throws {
        guard hasGatewayURL else { throw WuMindGatewayClient.GatewayError.invalidGatewayURL }
        let fetched = try await WuMindGatewayClient().fetchPublicConfig(gatewayURL: gatewayBaseURL)
        updateManagedConfigLocally(fetched)
        if let models = try? await WuMindGatewayClient().fetchPublicModels(gatewayURL: gatewayBaseURL) {
            managedCatalogModels = models
            if !enabledManagedModels.contains(where: { $0.id == managedSelectedModelID }),
               let first = enabledManagedModels.first {
                managedSelectedModelID = first.id
            }
            scheduleSave()
        }
    }

    /// Registers a WUMIND user (mandatory for BOTH internal duty staff and external users before entering WUMIND).
    /// Records the user into Cloudflare D1 `users` (when gateway URL is set) so Admin sees every registered member.
    @discardableResult
    func registerWuMindUser(displayName: String, role: String? = nil) async throws -> String {
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw WuMindGatewayClient.GatewayError.serverMessage("请先输入您的姓名或昵称以完成 WUMIND 用户注册。")
        }
        let resolvedRole = role ?? (AppAccountManager.shared.isExternalRestricted ? "external" : "internal_duty")

        if hasGatewayURL {
            if let existingToken = Keychain.wumindGatewayUserToken, !existingToken.isEmpty {
                registeredDisplayName = cleanName
                registeredRole = resolvedRole
                if managedAccountID.isEmpty {
                    try? await refreshManagedAccount()
                }
                scheduleSave()
                WuMindWorksStore.shared.reloadForCurrentAccount()
                return existingToken
            }
            let reg = try await WuMindGatewayClient().registerAccount(
                gatewayURL: gatewayBaseURL,
                displayName: cleanName,
                registeredRole: resolvedRole
            )
            guard Keychain.setWuMindGatewayUserToken(reg.userToken) else {
                throw WuMindGatewayClient.GatewayError.unauthorized
            }
            managedAccountID = reg.userID
            managedBalanceYuan = reg.balanceYuan
            registeredDisplayName = cleanName
            registeredRole = reg.registeredRole ?? resolvedRole
            if activeStorageOwnerID != currentStorageOwnerID {
                reloadForCurrentAccount()
            } else {
                WuMindWorksStore.shared.reloadForCurrentAccount()
            }
            scheduleSave()
            Task { @MainActor in
                await WuMindIAPManager.shared.recoverUnfinishedTransactions(store: self, silent: true)
            }
            return reg.userToken
        }

        // Offline / gateway-not-yet-configured fallback: create local registration profile so user can use Own API
        // and auto-bind to D1 once gateway URL is configured.
        registeredDisplayName = cleanName
        registeredRole = resolvedRole
        if managedAccountID.isEmpty {
            let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).uppercased()
            managedAccountID = "WM-LOC-\(suffix)"
        }
        if activeStorageOwnerID != currentStorageOwnerID {
            reloadForCurrentAccount()
        } else {
            WuMindWorksStore.shared.reloadForCurrentAccount()
        }
        scheduleSave()
        return ""
    }

    @discardableResult
    func ensureManagedAccount(displayName: String = "") async throws -> String {
        guard hasGatewayURL else { throw WuMindGatewayClient.GatewayError.invalidGatewayURL }
        if let existing = Keychain.wumindGatewayUserToken, !existing.isEmpty {
            return existing
        }
        let effectiveName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? registeredDisplayName
            : displayName
        let role = registeredRole.isEmpty
            ? (AppAccountManager.shared.isExternalRestricted ? "external" : "internal_duty")
            : registeredRole
        let reg = try await WuMindGatewayClient().registerAccount(
            gatewayURL: gatewayBaseURL,
            displayName: effectiveName,
            registeredRole: role
        )
        guard Keychain.setWuMindGatewayUserToken(reg.userToken) else {
            throw WuMindGatewayClient.GatewayError.unauthorized
        }
        managedAccountID = reg.userID
        managedBalanceYuan = reg.balanceYuan
        if registeredDisplayName.isEmpty && !effectiveName.isEmpty {
            registeredDisplayName = effectiveName
        }
        if registeredRole.isEmpty {
            registeredRole = reg.registeredRole ?? role
        }
        if activeStorageOwnerID != currentStorageOwnerID {
            reloadForCurrentAccount()
        } else {
            WuMindWorksStore.shared.reloadForCurrentAccount()
        }
        scheduleSave()
        return reg.userToken
    }

    func refreshManagedAccount() async throws {
        let token = try await ensureManagedAccount()
        let status = try await WuMindGatewayClient().fetchAccountStatus(gatewayURL: gatewayBaseURL, userToken: token)
        managedAccountID = status.userID
        managedBalanceYuan = status.balanceYuan
        managedAccountStatus = status
        if let name = status.displayName, !name.isEmpty, registeredDisplayName.isEmpty {
            registeredDisplayName = name
        }
        if let role = status.registeredRole, !role.isEmpty, registeredRole.isEmpty {
            registeredRole = role
        }
        if activeStorageOwnerID != currentStorageOwnerID {
            reloadForCurrentAccount()
        } else {
            WuMindWorksStore.shared.reloadForCurrentAccount()
        }
        scheduleSave()
    }

    func redeemManagedVoucher(_ code: String) async throws -> WuMindAccountStatus {
        let token = try await ensureManagedAccount()
        let status = try await WuMindGatewayClient().redeemVoucher(gatewayURL: gatewayBaseURL, userToken: token, code: code)
        managedAccountID = status.userID
        managedBalanceYuan = status.balanceYuan
        managedAccountStatus = status
        scheduleSave()
        return status
    }

    var allSkills: [WuMindSkill] {
        customSkills + WuMindSkill.builtIn
    }

    var activeSkill: WuMindSkill? {
        guard let id = activeSkillID else { return nil }
        return allSkills.first { $0.id == id }
    }

    func selectSkill(_ skill: WuMindSkill?) {
        activeSkillID = skill?.id
        if skill?.id == "builtin.deep_research" {
            agentModeEnabled = true
        }
        scheduleSave()
    }

    func saveCustomSkill(id: String? = nil, name: String, icon: String = "wand.and.stars", summary: String, prompt: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanPrompt.isEmpty else { return }
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id, let idx = customSkills.firstIndex(where: { $0.id == id }) {
            customSkills[idx].name = cleanName
            customSkills[idx].icon = icon
            customSkills[idx].summary = cleanSummary.isEmpty ? "自定义 Skill" : cleanSummary
            customSkills[idx].prompt = cleanPrompt
        } else {
            let newSkill = WuMindSkill(
                id: "custom.\(UUID().uuidString)",
                name: cleanName,
                icon: icon,
                summary: cleanSummary.isEmpty ? "自定义 Skill" : cleanSummary,
                prompt: cleanPrompt,
                isBuiltIn: false
            )
            customSkills.insert(newSkill, at: 0)
            activeSkillID = newSkill.id
        }
        scheduleSave()
    }

    func deleteCustomSkill(_ id: String) {
        customSkills.removeAll { $0.id == id }
        if activeSkillID == id { activeSkillID = nil }
        scheduleSave()
    }

    func setMaxContextTokens(_ tokens: Int) {
        maxContextTokens = min(WuMindContextEngine.maxSupportedContextTokens, max(32_000, tokens))
        scheduleSave()
    }

    func setAutoCompactContext(_ enabled: Bool) {
        autoCompactContext = enabled
        scheduleSave()
    }

    var maxContextLabel: String {
        if maxContextTokens >= 1_000_000 { return "1M" }
        return "\(maxContextTokens / 1_000)K"
    }

    func updateCompaction(conversationID: UUID, summary: String, compactedTurnCount: Int) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[idx].compactedSummary = summary
        conversations[idx].compactedTurnCount = min(max(0, compactedTurnCount), conversations[idx].turns.count)
        conversations[idx].updatedAt = Date()
        scheduleSave()
    }

    func clearCompaction(conversationID: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[idx].compactedSummary = nil
        conversations[idx].compactedTurnCount = 0
        scheduleSave()
    }

    // MARK: - Projects (Workspaces)

    var activeProject: WuMindProject? {
        guard let id = activeProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    func project(for conversation: WuMindConversation?) -> WuMindProject? {
        if let pid = conversation?.projectID, let p = projects.first(where: { $0.id == pid }) {
            return p
        }
        return activeProject
    }

    func selectProject(_ id: UUID?, startFreshChat: Bool = false) {
        activeProjectID = id
        if startFreshChat {
            activeConversationID = nil
        }
        scheduleSave()
    }

    @discardableResult
    func saveProject(_ project: WuMindProject) -> WuMindProject {
        var updated = project
        updated.updatedAt = Date()
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = updated
        } else {
            projects.insert(updated, at: 0)
        }
        scheduleSave()
        return updated
    }

    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        if activeProjectID == id { activeProjectID = nil }
        for idx in conversations.indices where conversations[idx].projectID == id {
            conversations[idx].projectID = nil
        }
        scheduleSave()
    }

    func addDocument(_ extracted: WuMindAttachmentParser.ExtractedDocument, toProject projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let doc = WuMindProjectDoc(
            filename: extracted.filename,
            kindRaw: extracted.kind.rawValue,
            summaryBadge: extracted.summaryBadge,
            extractedText: extracted.extractedText
        )
        if projects[idx].knowledgeDocs.count >= 20 {
            projects[idx].knowledgeDocs.removeFirst()
        }
        projects[idx].knowledgeDocs.append(doc)
        projects[idx].updatedAt = Date()
        scheduleSave()
    }

    func removeDocument(_ docID: UUID, fromProject projectID: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[idx].knowledgeDocs.removeAll { $0.id == docID }
        projects[idx].updatedAt = Date()
        scheduleSave()
    }

    // MARK: - Customizations Marketplace & Connectors

    var installedConnectors: [WuMindConnectorSpec] {
        WuMindConnectorSpec.marketplaceCatalog.filter { installedConnectorIDs.contains($0.id) }
    }

    func isConnectorInstalled(_ id: String) -> Bool {
        installedConnectorIDs.contains(id)
    }

    func toggleConnector(_ id: String) {
        if installedConnectorIDs.contains(id) {
            installedConnectorIDs.remove(id)
        } else {
            installedConnectorIDs.insert(id)
        }
        scheduleSave()
    }

    func setConnectorEndpoint(_ urlString: String, for connectorID: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            connectorEndpoints.removeValue(forKey: connectorID)
        } else {
            connectorEndpoints[connectorID] = trimmed
        }
        scheduleSave()
    }

    // MARK: - Scheduled Tasks / Automations

    func saveScheduledTask(_ task: WuMindScheduledTask) {
        var copy = task
        if copy.enabled && copy.nextRunAt == nil && copy.serverStatus != "completed" && copy.serverStatus != "cancelled" {
            copy.nextRunAt = copy.cadence.nextRunDate(after: Date())
        }
        copy.nextRunBeijingText = copy.nextRunAt.map { WuMindScheduleCadence.formatBeijingDate($0) }
        if copy.isManagedCloudTask {
            // NEVER display 「已安排」 before server ACK returns `serverConfirmed == true`!
            copy.serverConfirmed = false
            copy.cloudSynced = false
            copy.syncError = nil
            copy.serverStatus = copy.enabled ? "pending_sync" : "paused"
        } else {
            // Own API Key: explicitly local-only, NEVER silently switched to managed paid gateway!
            copy.serverConfirmed = false
            copy.cloudSynced = false
            copy.syncError = nil
            copy.serverStatus = copy.enabled ? "local_only" : "paused"
        }
        if let idx = scheduledTasks.firstIndex(where: { $0.id == task.id }) {
            scheduledTasks[idx] = copy
        } else {
            scheduledTasks.insert(copy, at: 0)
        }
        scheduleSave()
        if copy.isManagedCloudTask {
            syncScheduleToCloudIfApplicable(copy)
        }
    }

    func toggleScheduledTask(_ id: UUID) {
        guard let idx = scheduledTasks.firstIndex(where: { $0.id == id }) else { return }
        if scheduledTasks[idx].enabled {
            pauseScheduledTask(id)
        } else {
            resumeScheduledTask(id)
        }
    }

    func pauseScheduledTask(_ id: UUID) {
        guard let idx = scheduledTasks.firstIndex(where: { $0.id == id }) else { return }
        scheduledTasks[idx].enabled = false
        scheduledTasks[idx].serverStatus = "paused"
        let copy = scheduledTasks[idx]
        scheduleSave()
        if copy.isManagedCloudTask {
            applyCloudScheduleStateAction(id: id, action: "pause", fallbackTask: copy)
        }
    }

    func resumeScheduledTask(_ id: UUID) {
        guard let idx = scheduledTasks.firstIndex(where: { $0.id == id }) else { return }
        if case .once = scheduledTasks[idx].cadence, scheduledTasks[idx].serverStatus == "completed" {
            ToastCenter.shared.show("该单次任务已执行完毕，如需再次运行请新建任务", style: .info)
            return
        }
        scheduledTasks[idx].enabled = true
        let next = scheduledTasks[idx].cadence.nextRunDate(after: Date())
        scheduledTasks[idx].nextRunAt = next
        scheduledTasks[idx].nextRunBeijingText = next.map { WuMindScheduleCadence.formatBeijingDate($0) }
        scheduledTasks[idx].serverStatus = scheduledTasks[idx].isManagedCloudTask ? "pending_sync" : "local_only"
        scheduledTasks[idx].syncError = nil
        let copy = scheduledTasks[idx]
        scheduleSave()
        if copy.isManagedCloudTask {
            applyCloudScheduleStateAction(id: id, action: "resume", fallbackTask: copy)
        }
    }

    func cancelScheduledTask(_ id: UUID) {
        guard let idx = scheduledTasks.firstIndex(where: { $0.id == id }) else { return }
        scheduledTasks[idx].enabled = false
        scheduledTasks[idx].serverStatus = "cancelled"
        scheduledTasks[idx].nextRunAt = nil
        scheduledTasks[idx].nextRunBeijingText = nil
        let copy = scheduledTasks[idx]
        scheduleSave()
        if copy.isManagedCloudTask {
            applyCloudScheduleStateAction(id: id, action: "cancel", fallbackTask: copy)
        }
    }

    func retrySyncScheduledTask(_ id: UUID) {
        guard let idx = scheduledTasks.firstIndex(where: { $0.id == id }),
              scheduledTasks[idx].isManagedCloudTask else { return }
        scheduledTasks[idx].syncError = nil
        scheduledTasks[idx].serverStatus = scheduledTasks[idx].enabled ? "pending_sync" : "paused"
        let copy = scheduledTasks[idx]
        scheduleSave()
        syncScheduleToCloudIfApplicable(copy)
    }

    func deleteScheduledTask(_ id: UUID) {
        scheduledTasks.removeAll { $0.id == id }
        scheduleSave()
        if hasGatewayURL, let token = Keychain.wumindGatewayUserToken, !token.isEmpty {
            let gw = gatewayBaseURL
            let idStr = id.uuidString
            Task {
                try? await WuMindGatewayClient().deleteCloudSchedule(gatewayURL: gw, userToken: token, id: idStr)
            }
        }
    }

    private func applyCloudScheduleStateAction(id: UUID, action: String, fallbackTask: WuMindScheduledTask) {
        guard hasGatewayURL else {
            if let idx = scheduledTasks.firstIndex(where: { $0.id == id }) {
                scheduledTasks[idx].serverConfirmed = false
                scheduledTasks[idx].syncError = "未配置 WUMIND 网关地址，无法同步到云端。"
                scheduleSave()
            }
            return
        }
        let gw = gatewayBaseURL
        let idStr = id.uuidString
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = try await self.ensureManagedAccount()
                let ack = try await WuMindGatewayClient().updateCloudScheduleState(
                    gatewayURL: gw,
                    userToken: token,
                    id: idStr,
                    action: action
                )
                self.applyCloudScheduleAck(id: id, ack: ack)
            } catch {
                // If schedule wasn't created remotely yet, upsert with updated state
                self.syncScheduleToCloudIfApplicable(fallbackTask)
            }
        }
    }

    private func syncScheduleToCloudIfApplicable(_ task: WuMindScheduledTask) {
        guard task.isManagedCloudTask else { return }
        guard hasGatewayURL else {
            if let idx = scheduledTasks.firstIndex(where: { $0.id == task.id }) {
                scheduledTasks[idx].serverConfirmed = false
                scheduledTasks[idx].cloudSynced = false
                scheduledTasks[idx].serverStatus = "sync_failed"
                scheduledTasks[idx].syncError = "未配置 WUMIND 网关地址，任务尚未在云端安排。"
                scheduleSave()
            }
            return
        }
        let gw = gatewayBaseURL
        let parts = task.cadence.scheduleTimeComponents
        let nextEpoch: Int = {
            if task.serverStatus == "cancelled" || task.serverStatus == "completed" { return 0 }
            if case .once(let d) = task.cadence { return Int(d.timeIntervalSince1970) }
            return Int((task.nextRunAt ?? task.cadence.nextRunDate(after: Date()) ?? Date().addingTimeInterval(3600)).timeIntervalSince1970)
        }()
        let requestedStatus: String = {
            if task.serverStatus == "cancelled" { return "cancelled" }
            if task.serverStatus == "completed" { return "completed" }
            return task.enabled ? "active" : "paused"
        }()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = try await self.ensureManagedAccount()
                let ack = try await WuMindGatewayClient().upsertCloudSchedule(
                    gatewayURL: gw,
                    userToken: token,
                    id: task.id.uuidString,
                    title: task.title,
                    prompt: task.prompt,
                    modelID: task.modelID,
                    intervalMinutes: parts.intervalMinutes,
                    recurrenceKind: task.cadence.recurrenceKindRaw,
                    timezone: task.timezoneID,
                    scheduleHour: parts.hour,
                    scheduleMinute: parts.minute,
                    scheduleWeekday: parts.weekday,
                    executionMode: task.executionMode.rawValue,
                    status: requestedStatus,
                    enabled: task.enabled,
                    nextRunEpoch: nextEpoch
                )
                self.applyCloudScheduleAck(id: task.id, ack: ack)
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if let idx = self.scheduledTasks.firstIndex(where: { $0.id == task.id }) {
                    self.scheduledTasks[idx].serverConfirmed = false
                    self.scheduledTasks[idx].cloudSynced = false
                    self.scheduledTasks[idx].serverStatus = "sync_failed"
                    self.scheduledTasks[idx].syncError = "云端确认失败（未安排）：\(msg)"
                    self.scheduleSave()
                }
            }
        }
    }

    private func applyCloudScheduleAck(id: UUID, ack: WuMindCloudScheduleAck) {
        guard let idx = scheduledTasks.firstIndex(where: { $0.id == id }) else { return }
        scheduledTasks[idx].serverConfirmed = ack.ok && ack.serverConfirmed
        scheduledTasks[idx].cloudSynced = ack.ok && ack.serverConfirmed
        scheduledTasks[idx].syncError = ack.ok ? nil : "云端未确认该任务"
        if let s = ack.schedule {
            scheduledTasks[idx].serverStatus = s.status
            scheduledTasks[idx].enabled = s.enabled
            scheduledTasks[idx].nextRunAt = s.nextRunEpoch > 0 ? Date(timeIntervalSince1970: TimeInterval(s.nextRunEpoch)) : nil
            if !s.nextRunBeijingText.isEmpty {
                scheduledTasks[idx].nextRunBeijingText = s.nextRunBeijingText
            }
        }
        scheduleSave()
    }

    // MARK: - Long-Term Memory, Preferences & Export

    /// Transparent destination label showing exactly which provider/host receives messages and private attachments.
    var activeDataDestinationLabel: String {
        if channel == .managed {
            let host = URL(string: gatewayBaseURL)?.host ?? "未配置网关"
            return "WUMIND 托管网关 (\(host))"
        }
        if let ext = selectedProvider.multiProvider,
           let customHost = AIProviderEndpoints.displayHost(for: ext), !customHost.isEmpty {
            return "\(selectedProvider.displayName) 自定义中转 (\(customHost))"
        }
        switch selectedProvider {
        case .deepSeek: return "DeepSeek 官方 (api.deepseek.com)"
        case .openAI: return "OpenAI 官方 (api.openai.com)"
        case .gemini: return "Google Gemini (generativelanguage.googleapis.com)"
        case .claude: return "Anthropic Claude (api.anthropic.com)"
        case .grok: return "xAI Grok (api.x.ai)"
        }
    }

    func addMemory(
        content: String,
        category: String = "偏好",
        ruleVersion: String? = nil,
        projectID: UUID? = nil,
        isTemporaryChat: Bool = false
    ) {
        // Strict privacy guarantee: temporary chats NEVER write to long-term memory!
        guard !isTemporaryChat else { return }
        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        memories.insert(
            WuMindMemoryItem(
                content: String(clean.prefix(300)),
                category: category,
                ruleVersion: ruleVersion,
                projectID: projectID,
                updatedAt: Date()
            ),
            at: 0
        )
        if memories.count > 50 { memories = Array(memories.prefix(50)) }
        scheduleSave()
    }

    func updateMemory(
        _ id: UUID,
        content: String,
        category: String,
        ruleVersion: String?,
        projectID: UUID?
    ) {
        guard let idx = memories.firstIndex(where: { $0.id == id }) else { return }
        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        memories[idx].content = String(clean.prefix(300))
        memories[idx].category = category
        let v = ruleVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        memories[idx].ruleVersion = (v?.isEmpty == false) ? v : nil
        memories[idx].projectID = projectID
        memories[idx].updatedAt = Date()
        scheduleSave()
    }

    func deleteMemory(_ id: UUID) {
        memories.removeAll { $0.id == id }
        scheduleSave()
    }

    func updatePreferences(_ mutate: (inout WuMindPreferences) -> Void) {
        mutate(&preferences)
        scheduleSave()
    }

    func toggleAgentMode() {
        agentModeEnabled.toggle()
        scheduleSave()
    }

    func exportConversationsMarkdown() -> String {
        var out: [String] = ["# WUMIND 对话记录导出（\(Date().formatted(date: .abbreviated, time: .shortened))）"]
        for convo in sortedConversations {
            out.append("\n## \(convo.title)（\(convo.modelDisplayName)）")
            for turn in convo.turns {
                out.append("\n**用户**：\(turn.question)")
                if !turn.answer.isEmpty {
                    out.append("\n**助手**：\(turn.answer)")
                }
            }
        }
        return out.joined(separator: "\n")
    }

    /// Combines User Personalization/Memories (strictly project-isolated with rule-version conflict resolution),
    /// active Project workspace (instructions + knowledge docs), active Skill, attached GitHub repo,
    /// active Agent tool directive, and Claude-style compacted memory.
    func composedSystemPrompt(conversationID: UUID? = nil,
                              extraGitHubContext: WuMindGitHubClient.RepoContext? = nil,
                              includeAgentDirective: Bool = false,
                              isTemporaryChat: Bool = false) -> String? {
        var sections: [String] = []
        let targetConvo = conversationID.flatMap { id in conversations.first(where: { $0.id == id }) } ?? activeConversation
        let scopedProjectID = isTemporaryChat ? nil : (targetConvo?.projectID ?? activeProjectID)

        if let profile = preferences.formattedSystemProfileBlock(
            memories: memories,
            activeProjectID: scopedProjectID,
            isTemporaryChat: isTemporaryChat
        ) {
            sections.append(profile)
        }
        if !isTemporaryChat, let proj = project(for: targetConvo) {
            sections.append(proj.formattedProjectSystemBlock())
        }
        if !isTemporaryChat,
           let shared = targetConvo?.sharedMaterials,
           let sharedBlock = WuMindMultiModelEngine.formattedSharedMaterialsBlock(materials: shared) {
            sections.append(sharedBlock)
        }
        if let skill = activeSkill {
            sections.append("[当前启用 Skill：\(skill.name)]\n\(skill.prompt)")
        }
        if let repoCtx = extraGitHubContext ?? attachedGitHubContext {
            sections.append(repoCtx.formattedPromptContext())
        }
        if includeAgentDirective {
            let activeSpecs: [WuMindConnectorSpec] = {
                if let proj = project(for: targetConvo), !proj.enabledConnectorIDs.isEmpty {
                    let allowed = installedConnectorIDs.union(proj.enabledConnectorIDs)
                    return WuMindConnectorSpec.marketplaceCatalog.filter { allowed.contains($0.id) }
                }
                return installedConnectors
            }()
            sections.append(WuMindAgentProtocol.agentSystemDirective(
                enabledConnectors: activeSpecs,
                maxSteps: preferences.agentMaxSteps
            ))
        }
        if let convo = targetConvo,
           let summary = convo.compactedSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            sections.append(
                WuMindContextEngine.formatCompactedSystemBlock(
                    summary: summary,
                    compactedTurnCount: max(1, convo.safeCompactedTurnCount)
                )
            )
        }
        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n---\n\n")
    }

    var activeConversation: WuMindConversation? {
        guard let id = activeConversationID else { return nil }
        return conversations.first { $0.id == id }
    }

    var sortedConversations: [WuMindConversation] {
        conversations.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var activeConversations: [WuMindConversation] {
        sortedConversations.filter { !$0.isArchived }
    }

    var archivedConversations: [WuMindConversation] {
        conversations
            .filter(\.isArchived)
            .sorted { lhs, rhs in
                let lDate = lhs.archivedAt ?? lhs.updatedAt
                let rDate = rhs.archivedAt ?? rhs.updatedAt
                if lDate != rDate { return lDate > rDate }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func models(for provider: WuMindProvider) -> [WuMindModelOption] {
        if provider == .deepSeek { return WuMindModelOption.deepSeekDefaults }
        return cachedModels[provider] ?? []
    }

    func updateCachedModels(_ list: [AIProviderModel], for provider: WuMindProvider, verifiedHost: String? = nil) {
        let mapped = list.map {
            WuMindModelOption(id: $0.id, displayName: $0.displayName, provider: provider, supportsTextChat: $0.supportsTextChat)
        }
        cachedModels[provider] = mapped
        if let verifiedHost {
            markProviderCatalogReadable(provider, host: verifiedHost, modelCount: mapped.filter(\.supportsTextChat).count)
        }
        if selectedProvider == provider {
            let textModels = mapped.filter(\.supportsTextChat)
            if !textModels.contains(where: { $0.id == selectedModelID }), let first = textModels.first {
                selectedModelID = first.id
                selectedModelName = first.displayName
            }
        }
        scheduleSave()
    }

    func resolvedHost(for provider: WuMindProvider) -> String {
        if let mp = provider.multiProvider {
            return mp.resolvedHost(baseURL: AIProviderEndpoints.baseURL(for: mp))
        }
        return "api.deepseek.com"
    }

    func verification(for provider: WuMindProvider) -> WuMindProviderVerification? {
        guard provider.hasKey else { return nil }
        let currentHost = resolvedHost(for: provider)
        if let stored = providerVerifications[provider.rawValue], stored.host == currentHost {
            return stored
        }
        return WuMindProviderVerification(
            status: .saved,
            host: currentHost,
            summary: "已保存 · 待验证（\(currentHost)）",
            updatedAt: Date()
        )
    }

    private func smokeKey(provider: WuMindProvider, modelID: String) -> String {
        "\(provider.rawValue)::\(modelID)"
    }

    func smokeRecord(for provider: WuMindProvider, modelID: String) -> WuMindModelSmokeRecord? {
        let currentHost = resolvedHost(for: provider)
        guard let record = modelSmokeRecords[smokeKey(provider: provider, modelID: modelID)],
              record.host == currentHost else { return nil }
        return record
    }

    func verifiedModelCount(for provider: WuMindProvider) -> Int {
        let currentHost = resolvedHost(for: provider)
        let prefix = "\(provider.rawValue)::"
        return modelSmokeRecords.reduce(0) { acc, entry in
            acc + (entry.key.hasPrefix(prefix) && entry.value.host == currentHost && entry.value.status == .passed ? 1 : 0)
        }
    }

    func markProviderSaved(_ provider: WuMindProvider) {
        let host = resolvedHost(for: provider)
        providerVerifications[provider.rawValue] = WuMindProviderVerification(
            status: .saved,
            host: host,
            summary: "已保存 · 待校验目录与试跑模型（\(host)）",
            updatedAt: Date()
        )
        scheduleSave()
    }

    /// Marks the provider as "catalog readable" (/v1/models succeeded).
    /// Preserves green `.verified` only if at least one model on the same host has already passed live inference.
    func markProviderCatalogReadable(_ provider: WuMindProvider, host: String? = nil, modelCount: Int? = nil) {
        let h = host ?? resolvedHost(for: provider)
        let passedCount = verifiedModelCount(for: provider)
        if passedCount > 0 {
            let totalPart = modelCount.map { "目录 \($0) · " } ?? ""
            providerVerifications[provider.rawValue] = WuMindProviderVerification(
                status: .verified,
                host: h,
                summary: "\(h) · \(totalPart)已试跑可用 \(passedCount) 个",
                updatedAt: Date()
            )
        } else {
            let summary = modelCount.map { "\(h) · 目录可读（\($0) 个聊天模型，待试跑验证）" } ?? "\(h) · 目录可读"
            providerVerifications[provider.rawValue] = WuMindProviderVerification(
                status: .catalogReadable,
                host: h,
                summary: summary,
                updatedAt: Date()
            )
        }
        scheduleSave()
    }

    func markProviderVerified(_ provider: WuMindProvider, host: String? = nil, modelCount: Int? = nil) {
        let h = host ?? resolvedHost(for: provider)
        let summary = modelCount.map { "\(h) · 已试跑可用（目录 \($0)）" } ?? "\(h) · 已试跑可用"
        providerVerifications[provider.rawValue] = WuMindProviderVerification(
            status: .verified,
            host: h,
            summary: summary,
            updatedAt: Date()
        )
        scheduleSave()
    }

    func markModelSmokePassed(_ provider: WuMindProvider, modelID: String, host: String, endpointPath: String, latencyMs: Int?) {
        let key = smokeKey(provider: provider, modelID: modelID)
        modelSmokeRecords[key] = WuMindModelSmokeRecord(
            status: .passed,
            host: host,
            endpointPath: endpointPath,
            httpStatus: 200,
            errorCode: nil,
            detail: "\(host)\(endpointPath) 真实调用成功",
            latencyMs: latencyMs,
            testedAt: Date()
        )
        let passedCount = verifiedModelCount(for: provider)
        providerVerifications[provider.rawValue] = WuMindProviderVerification(
            status: .verified,
            host: host,
            summary: "\(host) · 已试跑可用 \(passedCount) 个模型",
            updatedAt: Date()
        )
        scheduleSave()
    }

    func markModelSmokeFailed(_ provider: WuMindProvider, modelID: String, host: String,
                              httpStatus: Int?, errorCode: String?, detail: String) {
        let key = smokeKey(provider: provider, modelID: modelID)
        let safeDetail = MultiProviderAIClient.redactSecrets(in: detail)
        modelSmokeRecords[key] = WuMindModelSmokeRecord(
            status: .failed,
            host: host,
            endpointPath: nil,
            httpStatus: httpStatus,
            errorCode: errorCode,
            detail: safeDetail.isEmpty ? "调用失败" : safeDetail,
            latencyMs: nil,
            testedAt: Date()
        )
        scheduleSave()
    }

    func markProviderFailed(_ provider: WuMindProvider, host: String? = nil, summary: String) {
        let h = host ?? resolvedHost(for: provider)
        let safeSummary = MultiProviderAIClient.redactSecrets(in: summary)
        providerVerifications[provider.rawValue] = WuMindProviderVerification(
            status: .failed,
            host: h,
            summary: safeSummary.isEmpty ? "\(h) · 验证失败" : safeSummary,
            updatedAt: Date()
        )
        scheduleSave()
    }

    func markProviderRemoved(_ provider: WuMindProvider) {
        providerVerifications.removeValue(forKey: provider.rawValue)
        let prefix = "\(provider.rawValue)::"
        modelSmokeRecords = modelSmokeRecords.filter { !$0.key.hasPrefix(prefix) }
        if provider != .deepSeek {
            cachedModels[provider] = []
        }
        scheduleSave()
    }

    func addManualModel(_ rawID: String, for provider: WuMindProvider) {
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, provider != .deepSeek else { return }
        let option = WuMindModelOption(id: id, displayName: id, provider: provider, supportsTextChat: true)
        var list = cachedModels[provider] ?? []
        if !list.contains(where: { $0.id == id }) {
            list.insert(option, at: 0)
            cachedModels[provider] = list
        }
        selectModel(option)
    }

    func selectModel(_ option: WuMindModelOption) {
        selectedProvider = option.provider
        selectedModelID = option.id
        selectedModelName = option.displayName
        if let id = activeConversationID, let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].provider = option.provider
            conversations[idx].modelID = option.id
            conversations[idx].modelDisplayName = option.displayName
        }
        scheduleSave()
    }

    func selectProvider(_ provider: WuMindProvider) {
        selectedProvider = provider
        let list = models(for: provider).filter(\.supportsTextChat)
        if let existing = list.first(where: { $0.id == selectedModelID }) {
            selectedModelName = existing.displayName
        } else if let first = list.first {
            selectedModelID = first.id
            selectedModelName = first.displayName
        } else {
            selectedModelID = ""
            selectedModelName = provider.displayName
        }
        if let id = activeConversationID, let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].provider = provider
            conversations[idx].modelID = selectedModelID
            conversations[idx].modelDisplayName = selectedModelName
        }
        scheduleSave()
    }

    func toggleDeepThinking() {
        deepThinking.toggle()
        if let id = activeConversationID, let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].deepThinking = deepThinking
        }
        scheduleSave()
    }

    func startNewConversation() {
        activeConversationID = nil
    }

    func openConversation(_ id: UUID) {
        guard let convo = conversations.first(where: { $0.id == id }) else { return }
        activeConversationID = id
        selectedProvider = convo.provider
        selectedModelID = convo.modelID
        selectedModelName = convo.modelDisplayName
        deepThinking = convo.deepThinking
        activeProjectID = convo.projectID
        scheduleSave()
    }

    @discardableResult
    func ensureActiveConversation(initialPrompt: String, projectIDOverride: UUID? = nil) -> UUID {
        let targetProject = projectIDOverride ?? activeProjectID
        if projectIDOverride == nil, let id = activeConversationID, let idx = conversations.firstIndex(where: { $0.id == id }) {
            if conversations[idx].turns.isEmpty && conversations[idx].title == "新对话" {
                conversations[idx].title = WuMindConversation.autoTitle(from: initialPrompt)
            }
            conversations[idx].provider = selectedProvider
            conversations[idx].modelID = selectedModelID
            conversations[idx].modelDisplayName = selectedModelName
            conversations[idx].deepThinking = deepThinking
            if conversations[idx].projectID == nil, let targetProject {
                conversations[idx].projectID = targetProject
            }
            conversations[idx].updatedAt = Date()
            scheduleSave()
            return id
        }
        let convo = WuMindConversation(
            title: WuMindConversation.autoTitle(from: initialPrompt),
            provider: selectedProvider,
            modelID: selectedModelID,
            modelDisplayName: selectedModelName,
            deepThinking: deepThinking,
            projectID: targetProject
        )
        conversations.insert(convo, at: 0)
        if conversations.count > maxStoredConversations {
            // Drop oldest unpinned conversations past limit
            let unpinned = conversations.indices.filter { !conversations[$0].isPinned }
            if let drop = unpinned.last { conversations.remove(at: drop) }
        }
        activeConversationID = convo.id
        scheduleSave()
        return convo.id
    }

    func appendTurn(_ turn: WuMindTurn, to conversationID: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[idx].turns.append(turn)
        conversations[idx].updatedAt = Date()
        scheduleSave()
    }

    func mutateTurn(conversationID: UUID, turnID: UUID, persist: Bool = false, _ body: (inout WuMindTurn) -> Void) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationID }),
              let tIdx = conversations[cIdx].turns.firstIndex(where: { $0.id == turnID }) else { return }
        body(&conversations[cIdx].turns[tIdx])
        if persist {
            conversations[cIdx].updatedAt = Date()
            scheduleSave()
        }
    }

    func togglePin(_ id: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].isPinned.toggle()
        scheduleSave()
    }

    func renameConversation(_ id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].title = String(trimmed.prefix(48))
        scheduleSave()
    }

    /// Archives a conversation without altering its original `updatedAt`, `createdAt`, turns, or attachments.
    /// Updates `archiveStateUpdatedAt` so cloud sync propagates archive status across devices cleanly.
    @discardableResult
    func archiveConversation(_ id: UUID) -> WuMindConversation? {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return nil }
        let now = Date()
        conversations[idx].isArchived = true
        conversations[idx].archivedAt = now
        conversations[idx].archiveStateUpdatedAt = now
        if activeConversationID == id {
            activeConversationID = nil
        }
        let snapshot = conversations[idx]
        scheduleSave()
        return snapshot
    }

    /// Restores an archived conversation to the main history list in its exact original sort order
    /// without losing messages, attachments, or creating duplicates.
    @discardableResult
    func unarchiveConversation(_ id: UUID) -> WuMindConversation? {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return nil }
        let now = Date()
        conversations[idx].isArchived = false
        conversations[idx].archivedAt = nil
        conversations[idx].archiveStateUpdatedAt = now
        let snapshot = conversations[idx]
        scheduleSave()
        return snapshot
    }

    func deleteConversation(_ id: UUID) {
        if activeGenerationConversationID == id {
            stopGeneration()
        }
        conversations.removeAll { $0.id == id }
        if activeConversationID == id {
            activeConversationID = nil
        }
        scheduleSave()
    }

    func deleteAllConversations() {
        stopGeneration()
        conversations.removeAll()
        activeConversationID = nil
        saveNow()
    }

    func markConsented(_ provider: WuMindProvider) {
        consentedProviders.insert(provider.rawValue)
        scheduleSave()
    }

    func hasConsented(_ provider: WuMindProvider) -> Bool {
        consentedProviders.contains(provider.rawValue)
    }

    func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        saveNow()
    }

    // MARK: - Background-Resilient Multi-Step Agent & 60 FPS Streaming Engine

    private struct StepOutput {
        let reasoning: String
        let answer: String
        let promptTokens: Int
        let completionTokens: Int
        let reasoningTokens: Int
        let costYuan: Double
        let billedByGateway: Bool
    }

    /// Run the user-selected artifact tool in the same conversation, with its own work receipt.
    @discardableResult
    func startChatBuild(_ tool: WuMindChatBuild, question: String, prompt: String, attachments: [WuMindAttachment], mediaRoute: WuMindChatBuildService.MediaRoute?) -> Bool {
        guard !isGenerating else { return false }
        let conversationID = ensureActiveConversation(initialPrompt: question)
        let turnID = UUID()
        let owner = currentStorageOwnerID
        let modelID = mediaRoute?.id ?? (channel == .managed ? (activeManagedModel?.id ?? managedSelectedModelID) : selectedModelID)
        let works = WuMindWorksStore.shared
        let buildChannel = mediaRoute?.id == "local-avfoundation" ? "local" : (channel == .managed ? "managed" : "own_api")
        let work = works.recordSubmittedTask(
            workType: tool.workType, title: String(question.prefix(42)), prompt: question,
            modelID: modelID, params: ["channel": buildChannel, "origin": "chat_build"],
            idempotencyKey: "chat-build-\(turnID.uuidString)", syncToCloud: false
        )
        var turn = WuMindTurn(id: turnID, question: question, modelLabel: (mediaRoute?.id ?? activeModelDisplayName) + " · " + tool.title,
                              provider: activeProviderForDisplay, isDeepThinking: false,
                              attachmentNames: attachments.isEmpty ? nil : attachments.map(\.document.filename))
        turn.chatBuildWorkID = work.id
        appendTurn(turn, to: conversationID)
        streamBuffer.reset()
        activeGenerationConversationID = conversationID
        activeTurnID = turnID
        thinkingStartedAt = Date()
        generationStartedAt = thinkingStartedAt
        setInlineStatus(.agent, text: tool == .ppt ? "正在准备演示文稿" : "正在准备\(tool.title)")
        beginBackgroundExecution()
        startStreamFlusher(turnID: turnID)
        saveNow()
        activeGenerationTask = Task { [weak self] in
            guard let self else { return }
            var remoteJobID: String? { works.works.first { $0.id == work.id }?.upstreamJobID }
            do {
                let status: (String) -> Void = { stage in
                    guard self.activeTurnID == turnID else { return }
                    self.setInlineStatus(.agent, text: stage)
                }
                let output: WuMindChatBuildService.Artifact
                if let mediaRoute {
                    output = try await WuMindChatBuildService.generateMedia(
                        mediaRoute, prompt: question, attachments: attachments,
                        idempotency: "chat-build-\(turnID.uuidString)",
                        jobAccepted: { id, origin in
                            guard self.activeTurnID == turnID, self.currentStorageOwnerID == owner,
                                  works.works.first(where: { $0.id == work.id })?.upstreamJobID != id else { return }
                            works.updateProgress(id: work.id, status: "in_progress", progress: 10, upstreamJobID: id, videoJobOrigin: origin)
                        }, status: status
                    )
                } else {
                    output = try await WuMindChatBuildService.generate(
                        tool, question: question, prompt: prompt, attachments: attachments, using: self, status: status
                    )
                }
                try Task.checkCancellation()
                guard self.activeTurnID == turnID, self.currentStorageOwnerID == owner else { return }
                guard let saved = works.completeWork(
                    id: work.id, title: output.title, assetData: output.bytes, assetMime: output.mime,
                    assetExtension: output.fileExtension, projectJSON: output.projectJSON,
                    remoteWorkID: output.remoteWorkID, syncToCloud: false
                ), works.localAssetURL(for: saved) != nil else {
                    throw WuMindChatBuildService.BuildError.invalidArtifact
                }
                self.mutateTurn(conversationID: conversationID, turnID: turnID, persist: false) { $0.chatBuildWorkID = saved.id }
                self.pendingAnswer = output.detail
                self.finishGeneration(conversationID: conversationID, turnID: turnID, state: .complete)
            } catch is CancellationError {
                if self.currentStorageOwnerID == owner {
                    if let remoteJobID {
                        works.markStatusUnconfirmed(id: work.id, upstreamJobID: remoteJobID, message: "已停止等待，服务商原任务可能仍在运行。不会自动重发。")
                    } else {
                        works.failWork(id: work.id, errorMessage: "已停止等待，不会自动重发。", syncToCloud: false)
                    }
                }
                self.finishGeneration(conversationID: conversationID, turnID: turnID, state: .stopped)
            } catch {
                guard self.activeTurnID == turnID, self.currentStorageOwnerID == owner else { return }
                let detail = MultiProviderAIClient.redactSecrets(in: error.localizedDescription)
                let phase = remoteJobID == nil ? "提交" : "查询或获取成片"
                let clean = tool == .video && buildChannel != "local" ? "视频" + phase + "失败（" + modelID + "）：" + detail : detail
                if let buildError = error as? WuMindChatBuildService.BuildError, case .providerFailed = buildError {
                    works.failWork(id: work.id, errorMessage: clean, syncToCloud: false)
                } else if let remoteJobID {
                    works.markStatusUnconfirmed(id: work.id, upstreamJobID: remoteJobID, message: clean)
                } else {
                    works.failWork(id: work.id, errorMessage: clean, syncToCloud: false)
                }
                self.finishGeneration(conversationID: conversationID, turnID: turnID, state: .failed(clean))
            }
        }
        return true
    }

    /// Starts streaming generation inside `WuMindStore.shared` so closing WUMIND, switching tabs,
    /// or briefly putting the app in the background does not cancel it. The OS may suspend long local tasks.
    /// Supports both single-turn 60 FPS streaming and Multi-Step Agent tool calling with exact cumulative metering.
    func startGeneration(
        displayQuestion: String,
        outgoingPrompt: String,
        attachmentNames: [String]?,
        imageAttachments: [AIProviderMessage.ImageAttachment] = [],
        autoRepoName: String?,
        agentOverride: Bool? = nil,
        sessionTagPrefix: String? = nil,
        forceNewConversationInProject: UUID? = nil,
        sendTriggeredAt: Date = Date(),
        attachmentPrepMs: Int = 0
    ) {
        guard !isGenerating else { return }
        let activeChannel = channel
        let provider = activeProviderForDisplay
        let requestedDeepThinking = deepThinking
        let isDeep = deepThinking && activeSupportsDeepThinking
        let useAgent = agentOverride ?? agentModeEnabled
        let modelLabel = activeModelDisplayName
        let convoID = ensureActiveConversation(
            initialPrompt: displayQuestion,
            projectIDOverride: forceNewConversationInProject
        )
        let turnID = UUID()
        let stableClientRequestID = "turn-\(turnID.uuidString)-s1"
        let priorTurns = conversations.first(where: { $0.id == convoID })?.turns ?? []

        // Clear any stale streaming buffer before starting
        pendingReasoning = ""
        pendingAnswer = ""
        pendingReasoningSeconds = nil
        pendingFirstTokenMs = nil
        pendingFirstRenderMs = nil
        pendingDeferredBalanceYuan = nil
        generationStartedAt = sendTriggeredAt
        pendingAgentSteps = []
        pendingWebCitations = []
        pendingAgentCitations = []
        pendingToolFailures = []
        let activeSkillName = activeSkill?.name
        let willUseSearchOrAgent = useAgent || (activeSkillName != nil)
        pendingIntroLead = willUseSearchOrAgent ? "我帮你查一下并核对相关来源。" : nil
        pendingActiveAgentPhase = useAgent ? "正在调用：\(activeSkillName ?? "WUMIND 智能体")" : nil
        pendingInlineStatusKind = useAgent ? .agent : nil
        pendingInlineStatusText = useAgent ? "正在调用：\(activeSkillName ?? "WUMIND 智能体")" : nil
        streamDirty = true
        streamBuffer.reset()
        streamBuffer.inlineIntroLead = pendingIntroLead
        streamBuffer.activeAgentPhase = pendingActiveAgentPhase
        streamBuffer.inlineStatusKind = pendingInlineStatusKind
        streamBuffer.inlineStatusText = pendingInlineStatusText

        activeTurnID = turnID
        activeGenerationConversationID = convoID
        thinkingStartedAt = sendTriggeredAt

        let foregroundModelID = activeChannel == .managed ? managedSelectedModelID : selectedModelID
        let resolvedModelID = activeChannel == .managed
            ? (activeManagedModel?.id ?? managedSelectedModelID)
            : selectedModelID
        let ownIsRelay: Bool = {
            guard activeChannel == .ownAPI, let mp = provider.multiProvider else { return false }
            return ((try? AIProvider.normalizedBaseURL(AIProviderEndpoints.baseURL(for: mp))) ?? nil) != nil
        }()
        let resolvedCaps = WuMindModelCapabilityMatrix.capabilities(
            providerRaw: provider.rawValue,
            modelID: resolvedModelID,
            isRelayBaseURL: ownIsRelay
        )
        let initialCapabilityBadge = modelCapabilityBadge(
            channel: activeChannel,
            provider: provider,
            modelID: resolvedModelID,
            hasUsedToolsOrMultimodal: !imageAttachments.isEmpty || webSearchEnabled || useAgent
        )
        let chainID = "chat-\(convoID.uuidString)"

        let badgeSuffix: String = {
            var tags: [String] = []
            if activeChannel == .managed { tags.append("内置") }
            if useAgent { tags.append("智能体") }
            if !imageAttachments.isEmpty && resolvedCaps.visionAttachments { tags.append("视觉") }
            return tags.isEmpty ? "" : " · " + tags.joined(separator: "·")
        }()

        let destinationLabel = activeDataDestinationLabel
        pendingCallTrace = WuMindCallTraceRecord(
            clientRequestID: stableClientRequestID,
            selectedChannel: activeChannel == .managed ? "WuMind 内置" : "自有 API",
            selectedProvider: provider.rawValue,
            selectedModelID: foregroundModelID.isEmpty ? resolvedModelID : foregroundModelID,
            requestedDeepThinking: requestedDeepThinking,
            attachedImageCount: imageAttachments.count,
            requestedWebSearch: webSearchEnabled,
            actualModelID: resolvedModelID,
            upstreamRoute: activeChannel == .managed ? "gateway_pending" : (ownIsRelay ? "own_relay" : "own_direct"),
            host: activeChannel == .managed ? (URL(string: gatewayBaseURL)?.host ?? gatewayBaseURL) : (provider.multiProvider?.resolvedHost(baseURL: provider.multiProvider.flatMap { AIProviderEndpoints.baseURL(for: $0) }) ?? "api.deepseek.com"),
            endpointPath: activeChannel == .managed ? "/v1/chat/completions" : "/v1/chat/completions",
            thinkingParamSent: isDeep ? resolvedCaps.thinkingProtocol.wireParamSummary : "none",
            imagesSentCount: imageAttachments.count,
            timing: WuMindPhaseTimingMetrics(
                clientPrepMs: max(1, Int(Date().timeIntervalSince(sendTriggeredAt) * 1000)),
                attachmentPrepMs: attachmentPrepMs
            )
        )

        let turn = WuMindTurn(
            id: turnID,
            question: displayQuestion,
            modelLabel: modelLabel + badgeSuffix,
            provider: provider,
            isDeepThinking: isDeep,
            state: .generating,
            attachmentNames: attachmentNames,
            actualChannelLabel: destinationLabel,
            taskChainID: chainID,
            modelCapabilityBadge: initialCapabilityBadge,
            clientRequestID: stableClientRequestID,
            callTrace: pendingCallTrace
        )
        appendTurn(turn, to: convoID)

        // Programmatic-first intranet Duty query path:
        // Only triggers on Duty App questions (normal chat returns nil and never touches internal data).
        // Executes 100% deterministically on-device regardless of selected model and NEVER sends intranet data to external LLMs.
        if imageAttachments.isEmpty,
           let dutyExec = WuMindDutyBridge.tryExecuteLocalDutyQuery(prompt: displayQuestion, activeModelLabel: modelLabel) {
            pendingAgentSteps = dutyExec.toolCalls.enumerated().map { idx, call in
                WuMindAgentStep(
                    stepIndex: idx + 1,
                    phase: .toolCall,
                    toolName: call.toolName,
                    toolSummary: "\(call.sourceName)（\(call.status.chineseLabel)）",
                    resultPreview: call.summary,
                    promptTokens: 0,
                    completionTokens: 0,
                    reasoningTokens: 0,
                    costYuan: 0,
                    durationSeconds: 0.01,
                    succeeded: call.status != .queryFailed
                )
            }
            pendingAnswer = dutyExec.formattedReport
            pendingActiveAgentPhase = nil
            pendingFirstTokenMs = 10
            mutateTurn(conversationID: convoID, turnID: turnID, persist: false) { item in
                item.modelLabel = "本机内网直查 · 零外发"
                item.actualChannelLabel = "App 内网只读引擎（独立于 \(modelLabel)）"
                item.modelCapabilityBadge = "能力已验证"
                item.agentSteps = self.pendingAgentSteps
            }
            finishGeneration(conversationID: convoID, turnID: turnID, state: .complete)
            return
        }

        // Strict Pre-Flight Capability Honesty: NEVER silently drop attached images or silently swap models!
        if let violation = WuMindModelCapabilityMatrix.validateChatRequest(
            providerRaw: provider.rawValue,
            modelID: resolvedModelID,
            connectionLabel: destinationLabel,
            isRelayBaseURL: ownIsRelay,
            deepThinking: requestedDeepThinking && activeSupportsDeepThinking,
            attachedImageCount: imageAttachments.count
        ) {
            pendingCallTrace?.failureCode = violation.errorCode
            pendingCallTrace?.imagesSentCount = 0
            mutateTurn(conversationID: convoID, turnID: turnID, persist: false) { item in
                item.failureStage = "发送前能力校验（未扣费）"
                item.callTrace = self.pendingCallTrace
            }
            finishGeneration(conversationID: convoID, turnID: turnID, state: .failed(violation.userMessage))
            return
        }

        beginBackgroundExecution()
        startStreamFlusher(turnID: turnID)

        let modelID = resolvedModelID
        let apiKey = activeChannel == .ownAPI ? provider.apiKey() : nil

        if activeChannel == .ownAPI && (apiKey?.isEmpty != false) {
            mutateTurn(conversationID: convoID, turnID: turnID, persist: false) { item in
                item.failureStage = "API Key 校验"
            }
            finishGeneration(conversationID: convoID, turnID: turnID, state: .failed("未配置 \(provider.displayName) API Key。"))
            return
        }

        let maxSteps = useAgent ? min(10, max(2, preferences.agentMaxSteps)) : 1
        let maxCostYuan = preferences.agentMaxCostYuanPerRun
        let useWebSearch = webSearchEnabled

        activeGenerationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var currentStage = activeChannel == .managed ? "WUMIND 钱包鉴权与余额校验" : "准备上下文与通道连接"
            do {
                let userToken: String? = activeChannel == .managed
                    ? try await self.ensureManagedAccount()
                    : Keychain.wumindGatewayUserToken

                if let repoName = autoRepoName,
                   let fetched = try? await WuMindGitHubClient().fetchRepoContext(fullName: repoName, token: Keychain.githubToken) {
                    self.attachedGitHubContext = fetched
                }

                var enrichedPrompt = outgoingPrompt
                var preSearchCostYuan = 0.0
                var continueWithoutWeb = false
                if useWebSearch {
                    currentStage = "程序化拆解问题并联网核验来源原文"
                    let researchPlan = WuMindDeepResearchEngine.buildResearchPlan(
                        for: displayQuestion,
                        maxSubQueries: isDeep ? 3 : 2
                    )
                    let subQueries = researchPlan.subQueries.isEmpty ? [displayQuestion] : researchPlan.subQueries
                    if subQueries.count > 1 {
                        self.pendingAgentSteps.append(
                            WuMindAgentStep(
                                stepIndex: 0,
                                phase: .planning,
                                toolName: "research_plan",
                                toolSummary: "拆解 \(subQueries.count) 个检索维度",
                                resultPreview: subQueries.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"),
                                promptTokens: 0,
                                completionTokens: 0,
                                reasoningTokens: 0,
                                costYuan: 0,
                                durationSeconds: 0.01,
                                succeeded: true
                            )
                        )
                    }

                    var observations: [WuMindDeepResearchEngine.SubQueryObservation] = []
                    let personalKeys = self.personalWebSearchKeys()
                    let gatewayURL = self.gatewayBaseURL
                    let validGatewayURL = self.hasGatewayURL
                    var route = WuMindSearchRouting.firstRoute(
                        usesOwnChat: activeChannel == .ownAPI,
                        hasPersonalKey: personalKeys.tavily != nil || personalKeys.brave != nil,
                        hasGatewaySession: validGatewayURL && userToken?.isEmpty == false
                    )
                    var readyGateway: SearchGatewayReadiness?
                    if route == .gateway, let userToken {
                        readyGateway = await self.searchGatewayReadiness(url: gatewayURL, token: userToken)
                    }

                    searchPass: while true {
                        var lastFailure = validGatewayURL
                            ? "请登录 WuMind 后使用内置联网搜索。"
                            : "当前版本的内置搜索网关尚未配置，请联系管理员。"
                        if let reason = readyGateway?.failure, route == .gateway {
                            lastFailure = reason
                        } else if route != .unavailable {
                            for (qIdx, subQuery) in subQueries.enumerated() {
                                try Task.checkCancellation()
                                guard self.activeTurnID == turnID else { return }
                                let searchStart = Date()
                                let searchRes = await self.performVerifiedWebSearch(
                                    query: subQuery,
                                    channel: activeChannel,
                                    userToken: userToken,
                                    depth: isDeep ? "advanced" : "basic",
                                    selectedRoute: route,
                                    gatewayURLOverride: gatewayURL
                                )
                                try Task.checkCancellation()
                                guard self.activeTurnID == turnID else { return }
                                preSearchCostYuan += searchRes.extraCostYuan
                                if searchRes.extraCostYuan > 0 {
                                    // Keep an acknowledged search charge even if the user stops before chat.
                                    self.mutateTurn(conversationID: convoID, turnID: turnID, persist: false) { item in
                                        item.costYuan = preSearchCostYuan
                                    }
                                }
                                let fullTextCount = searchRes.searchResults.filter(\.isFullTextRead).count
                                observations.append(.init(
                                    query: subQuery,
                                    succeeded: searchRes.succeeded,
                                    summary: searchRes.summary,
                                    observationText: searchRes.observationText,
                                    fullTextCount: fullTextCount
                                ))
                                self.pendingAgentSteps.append(.init(
                                    stepIndex: self.pendingAgentSteps.count + 1,
                                    phase: .toolCall,
                                    toolName: "web_search",
                                    toolSummary: subQueries.count > 1 ? "[\(qIdx + 1)/\(subQueries.count)] \(searchRes.summary)" : searchRes.summary,
                                    resultPreview: String(searchRes.observationText.prefix(500)),
                                    promptTokens: 0,
                                    completionTokens: 0,
                                    reasoningTokens: 0,
                                    costYuan: searchRes.extraCostYuan,
                                    durationSeconds: Date().timeIntervalSince(searchStart),
                                    succeeded: searchRes.succeeded
                                ))
                                if !searchRes.succeeded {
                                    lastFailure = searchRes.summary
                                    // Another distinct planned query may find results. Do not replay
                                    // when the connection itself failed or a charge is uncertain.
                                    if searchRes.searchStatus != "no_results" { break }
                                }
                            }
                        }
                        try Task.checkCancellation()
                        guard self.activeTurnID == turnID else { return }
                        let hasSearchEvidence = observations.contains(where: \.succeeded)
                        if !hasSearchEvidence, route == .personal, validGatewayURL, let userToken, !userToken.isEmpty {
                            readyGateway = await self.searchGatewayReadiness(url: gatewayURL, token: userToken)
                        }
                        try Task.checkCancellation()
                        guard self.activeTurnID == turnID else { return }
                        let decision = WuMindSearchRouting.decision(
                            hasSearchEvidence: hasSearchEvidence, route: route,
                            gatewayReady: readyGateway?.failure == nil && readyGateway != nil
                        )
                        guard decision.shouldAsk else { break searchPass }
                        let gatewayAction: String? = decision.offerGateway
                            ? readyGateway?.actionLabel(maxSearches: subQueries.count) : nil
                        var choiceMessage = lastFailure + "\n未调用聊天模型。"
                        if let gatewayAction {
                            choiceMessage += "\n备用通道：\(gatewayAction)。"
                        } else if route == .personal, let reason = readyGateway?.failure {
                            choiceMessage += "\n备用网关：\(reason)"
                        }
                        self.pendingIntroLead = nil
                        self.pendingActiveAgentPhase = nil
                        self.setInlineStatus(.warning, text: "联网搜索未完成，等待你的选择")
                        if !self.pendingToolFailures.contains(where: { $0.toolKind == "web_search" && $0.message == lastFailure }) {
                            self.pendingToolFailures.append(.init(toolKind: "web_search", targetName: displayQuestion, message: lastFailure))
                        }
                        let choice = await self.askSearchContinuation(
                            turnID: turnID, message: choiceMessage, gatewayAction: gatewayAction
                        )
                        try Task.checkCancellation()
                        guard self.activeTurnID == turnID else { return }
                        switch choice {
                        case .tryGateway:
                            route = .gateway
                        case .continueOffline:
                            continueWithoutWeb = true
                            break searchPass
                        case .cancel:
                            self.finishGeneration(conversationID: convoID, turnID: turnID, state: .stopped)
                            return
                        }
                    }

                    if continueWithoutWeb {
                        self.setInlineStatus(.warning, text: "已选择不联网继续")
                        enrichedPrompt = "【本轮用户已选择不联网继续。明确说明未进行联网核验，不提供未经验证的实时事实或来源。】\n\n\(outgoingPrompt)"
                    } else {
                        self.pendingActiveAgentPhase = "已收到联网搜索结果，正在汇总回答…"
                        self.streamDirty = true
                        let wrappedEvidence = WuMindDeepResearchEngine.wrapUntrustedWebEvidence(
                            plan: researchPlan,
                            observations: observations
                        )
                        enrichedPrompt = "\(wrappedEvidence)\n\n【用户问题】\n\(outgoingPrompt)"
                    }
                }

                currentStage = "整理上下文与项目规则"
                let prepared = await self.prepareContextTurnsAndAutoCompact(
                    conversationID: convoID,
                    priorTurns: priorTurns,
                    outgoingPrompt: enrichedPrompt,
                    channel: activeChannel,
                    provider: provider,
                    modelID: modelID,
                    apiKey: apiKey
                )
                var workingMessages = Self.buildMultiProviderContext(
                    verbatimTurns: prepared.verbatimTurns,
                    prompt: enrichedPrompt,
                    images: imageAttachments,
                    maxBytes: prepared.maxBytes
                )
                currentStage = "调用上游模型与流式接收"

                var totalPromptTokens = 0
                var totalCompletionTokens = 0
                var totalReasoningTokens = 0
                var totalCostYuan = preSearchCostYuan
                var billedByGateway = preSearchCostYuan > 0

                for stepIndex in 1...maxSteps {
                    try Task.checkCancellation()
                    guard self.activeTurnID == turnID else { return }

                    let isFinalForcedStep = useAgent && stepIndex == maxSteps
                    let allowToolsThisStep = useAgent && !isFinalForcedStep && !continueWithoutWeb
                    let sysPrompt = self.composedSystemPrompt(
                        conversationID: convoID,
                        includeAgentDirective: allowToolsThisStep
                    )
                    let stepTag: String? = {
                        if let prefix = sessionTagPrefix, !prefix.isEmpty {
                            return useAgent ? "\(prefix) · 第 \(stepIndex) 步" : prefix
                        }
                        return useAgent ? "Agent 第 \(stepIndex) 步" : nil
                    }()

                    if useAgent {
                        self.pendingActiveAgentPhase = stepIndex == 1
                            ? "智能体规划中…"
                            : "正在综合观察结果（第 \(stepIndex) 步）…"
                        self.streamDirty = true
                    }

                    let stepStart = Date()
                    let stepRequestID = stepIndex == 1 ? stableClientRequestID : "turn-\(turnID.uuidString)-s\(stepIndex)"
                    let stepOut = try await self.runSingleModelStep(
                        turnID: turnID,
                        channel: activeChannel,
                        provider: provider,
                        modelID: modelID,
                        apiKey: apiKey,
                        userToken: userToken,
                        messages: workingMessages,
                        systemPrompt: sysPrompt,
                        isDeep: isDeep,
                        sessionTag: stepTag,
                        clientRequestID: stepRequestID
                    )
                    let stepElapsed = Date().timeIntervalSince(stepStart)

                    totalPromptTokens += stepOut.promptTokens
                    totalCompletionTokens += stepOut.completionTokens
                    totalReasoningTokens += stepOut.reasoningTokens
                    totalCostYuan += stepOut.costYuan
                    if stepOut.billedByGateway { billedByGateway = true }

                    // Check if Agent emitted a structured tool call
                    if allowToolsThisStep,
                       let invocation = WuMindAgentProtocol.parseToolInvocation(from: stepOut.answer) {
                        // Budget & step guardrail check BEFORE running next tool
                        if let stopReason = WuMindAgentProtocol.budgetStopReason(
                            completedSteps: stepIndex,
                            maxSteps: maxSteps,
                            accumulatedCostYuan: totalCostYuan,
                            maxCostYuan: maxCostYuan,
                            isManagedChannel: activeChannel == .managed
                        ) {
                            self.pendingAgentSteps.append(
                                WuMindAgentStep(
                                    stepIndex: stepIndex,
                                    phase: .budgetStopped,
                                    toolName: invocation.tool,
                                    toolSummary: stopReason,
                                    resultPreview: "",
                                    promptTokens: stepOut.promptTokens,
                                    completionTokens: stepOut.completionTokens,
                                    reasoningTokens: stepOut.reasoningTokens,
                                    costYuan: stepOut.costYuan,
                                    durationSeconds: stepElapsed,
                                    succeeded: true
                                )
                            )
                            self.pendingActiveAgentPhase = "已触发费用/步数保护，正在输出最终总结…"
                            self.pendingAnswer = ""
                            self.streamDirty = true
                            workingMessages.append(.init(role: .assistant, text: stepOut.answer))
                            workingMessages.append(.init(role: .user, text: "系统提示：\(stopReason) 请立即直接汇总给用户最终答案，不要再调用工具。"))
                            let finalOut = try await self.runSingleModelStep(
                                turnID: turnID,
                                channel: activeChannel,
                                provider: provider,
                                modelID: modelID,
                                apiKey: apiKey,
                                userToken: userToken,
                                messages: workingMessages,
                                systemPrompt: self.composedSystemPrompt(conversationID: convoID, includeAgentDirective: false),
                                isDeep: false,
                                sessionTag: (sessionTagPrefix ?? "Agent") + " · 最终汇总",
                                clientRequestID: "turn-\(turnID.uuidString)-final"
                            )
                            totalPromptTokens += finalOut.promptTokens
                            totalCompletionTokens += finalOut.completionTokens
                            totalReasoningTokens += finalOut.reasoningTokens
                            totalCostYuan += finalOut.costYuan
                            if finalOut.billedByGateway { billedByGateway = true }
                            self.pendingAnswer = WuMindAgentProtocol.stripToolTags(from: finalOut.answer)
                            break
                        }

                        // Execute live Agent tool asynchronously
                        let toolDisplayName: String = {
                            switch invocation.tool {
                            case "web_search": return "联网搜索"
                            case "web_fetch": return "网页原文核验"
                            case "calculator_verify": return "精准计算核验"
                            case "project_search": return "项目资料检索"
                            case "github_read": return "GitHub 仓库助手"
                            default: return self.activeSkill?.name ?? invocation.tool
                            }
                        }()
                        if invocation.tool == "web_search" {
                            let q = invocation.args["query"] ?? ""
                            self.pendingActiveAgentPhase = "正在搜索：\(q)"
                            self.setInlineStatus(.searching, text: "正在搜索：\(q)")
                        } else if invocation.tool == "web_fetch" {
                            let host = URL(string: invocation.args["url"] ?? "")?.host ?? (invocation.args["url"] ?? "网页")
                            self.pendingActiveAgentPhase = "正在阅读：\(host)"
                            self.setInlineStatus(.reading, text: "正在阅读：\(host)")
                        } else {
                            self.pendingActiveAgentPhase = "正在调用：\(toolDisplayName)"
                            self.setInlineStatus(.agent, text: "正在调用：\(toolDisplayName)")
                        }
                        self.streamDirty = true
                        let toolStart = Date()
                        let toolResult = await self.executeAgentTool(
                            invocation,
                            conversationID: convoID,
                            channel: activeChannel,
                            userToken: userToken
                        )
                        let totalStepSec = stepElapsed + Date().timeIntervalSince(toolStart)
                        if toolResult.extraCostYuan > 0 {
                            totalCostYuan += toolResult.extraCostYuan
                            billedByGateway = true
                        }

                        if invocation.tool != "web_search" {
                            let citation = WuMindAgentCitation(
                                agentID: invocation.tool,
                                agentName: toolDisplayName,
                                summary: toolResult.summary,
                                succeeded: toolResult.succeeded,
                                errorMessage: toolResult.succeeded ? nil : toolResult.summary
                            )
                            self.pendingAgentCitations.append(citation)
                            if !toolResult.succeeded {
                                self.pendingToolFailures.append(
                                    WuMindToolFailureNotice(
                                        toolKind: invocation.tool == "web_fetch" ? "web_fetch" : "agent",
                                        targetName: toolDisplayName,
                                        message: toolResult.summary
                                    )
                                )
                            }
                        }

                        self.pendingAgentSteps.append(
                            WuMindAgentStep(
                                stepIndex: stepIndex,
                                phase: .toolCall,
                                toolName: invocation.tool,
                                toolSummary: toolResult.summary,
                                resultPreview: String(toolResult.observationText.prefix(280)),
                                promptTokens: stepOut.promptTokens,
                                completionTokens: stepOut.completionTokens,
                                reasoningTokens: stepOut.reasoningTokens,
                                costYuan: stepOut.costYuan + toolResult.extraCostYuan,
                                durationSeconds: totalStepSec,
                                succeeded: toolResult.succeeded
                            )
                        )
                        // Reset visible answer buffer for the next synthesis step cleanly
                        self.pendingAnswer = ""
                        self.streamDirty = true

                        workingMessages.append(.init(role: .assistant, text: stepOut.answer))
                        workingMessages.append(.init(
                            role: .user,
                            text: "[工具 \(invocation.tool) 返回结果]\n\(toolResult.observationText)\n\n请基于以上真实观察结果继续推理；如信息已足够，请直接输出最终回答。"
                        ))
                        continue
                    }

                    // Final visible answer produced!
                    let cleanedAnswer = useAgent
                        ? WuMindAgentProtocol.stripToolTags(from: stepOut.answer)
                        : stepOut.answer
                    self.pendingAnswer = cleanedAnswer
                    if useAgent && !self.pendingAgentSteps.isEmpty {
                        self.pendingAgentSteps.append(
                            WuMindAgentStep(
                                stepIndex: stepIndex,
                                phase: .synthesizing,
                                toolName: "final_synthesis",
                                toolSummary: "汇总最终交付内容",
                                resultPreview: "",
                                promptTokens: stepOut.promptTokens,
                                completionTokens: stepOut.completionTokens,
                                reasoningTokens: stepOut.reasoningTokens,
                                costYuan: stepOut.costYuan,
                                durationSeconds: stepElapsed,
                                succeeded: true
                            )
                        )
                    }
                    break
                }

                // Commit exact cumulative token & billing metrics across ALL steps!
                self.mutateTurn(conversationID: convoID, turnID: turnID, persist: false) { item in
                    if totalPromptTokens > 0 || totalCompletionTokens > 0 {
                        item.promptTokens = totalPromptTokens
                        item.completionTokens = totalCompletionTokens
                        item.reasoningTokens = totalReasoningTokens
                    }
                    if billedByGateway {
                        item.costYuan = (totalCostYuan * 1_000_000).rounded() / 1_000_000
                    }
                    if !self.pendingAgentSteps.isEmpty {
                        item.agentSteps = self.pendingAgentSteps
                    }
                }

                try Task.checkCancellation()
                self.finishGeneration(conversationID: convoID, turnID: turnID, state: .complete)
                if activeChannel == .managed {
                    Task { @MainActor [weak self] in
                        try? await self?.refreshManagedAccount()
                    }
                }
            } catch is CancellationError {
                self.compactingContext = false
                self.finishGeneration(conversationID: convoID, turnID: turnID, state: .stopped)
            } catch {
                self.compactingContext = false
                if case WuMindGatewayClient.GatewayError.upstreamBalanceInsufficient(let upMsg) = error {
                    self.lastUpstreamBalanceNotice = upMsg
                }

                let modelRefused = (error as? WuMindGatewayClient.GatewayError) == .modelRefused
                    || (error as? MultiProviderAIError) == .modelRefused
                    || (error as? AIProviderDiagnosticError)?.underlying == .modelRefused
                if modelRefused {
                    self.pendingAnswer = ""
                    self.pendingReasoning = ""
                    self.pendingCallTrace?.succeeded = false
                    self.pendingCallTrace?.failureCode = "model_refused"
                    self.mutateTurn(conversationID: convoID, turnID: turnID, persist: false) {
                        $0.failureStage = "上游模型拒答"
                    }
                    self.finishGeneration(conversationID: convoID, turnID: turnID,
                                          state: .failed("模型拒绝了本次请求，未自动重发或切换模型。"))
                    return
                }

                // Network-drop safe recovery: before marking a managed request failed,
                // query the original clientRequestID so settled answers recover with ¥0 extra charge
                // and in-progress requests NEVER trigger duplicate submission.
                let isAuthOrBalanceErr: Bool = {
                    if case WuMindGatewayClient.GatewayError.unauthorized = error { return true }
                    if case WuMindGatewayClient.GatewayError.insufficientBalance = error { return true }
                    if case WuMindGatewayClient.GatewayError.upstreamBalanceInsufficient = error { return true }
                    return false
                }()
                if activeChannel == .managed && !isAuthOrBalanceErr && self.hasGatewayURL,
                   let token = Keychain.wumindGatewayUserToken, !token.isEmpty {
                    if let rec = try? await WuMindGatewayClient().recoverChatTask(
                        gatewayURL: self.gatewayBaseURL,
                        userToken: token,
                        clientRequestID: stableClientRequestID
                    ) {
                        if rec.status == "settled" {
                            if let recReasoning = rec.reasoning, !recReasoning.isEmpty {
                                self.pendingReasoning = recReasoning
                            }
                            if let recContent = rec.content, !recContent.isEmpty {
                                self.pendingAnswer = recContent
                            }
                            self.pendingCallTrace?.recoveredFromOriginalTask = true
                            self.pendingCallTrace?.succeeded = rec.outputComplete != false
                            if let b = rec.billing {
                                self.pendingDeferredBalanceYuan = b.balanceYuan
                                self.mutateTurn(conversationID: convoID, turnID: turnID, persist: false) { item in
                                    item.promptTokens = b.promptTokens
                                    item.completionTokens = b.completionTokens
                                    item.reasoningTokens = b.reasoningTokens
                                    item.costYuan = b.costYuan
                                }
                            } else if let cost = rec.costYuan {
                                self.mutateTurn(conversationID: convoID, turnID: turnID, persist: false) { item in
                                    item.costYuan = cost
                                }
                            }
                            if rec.failureCode == "model_refused" {
                                self.pendingAnswer = ""
                                self.pendingReasoning = ""
                                self.pendingCallTrace?.failureCode = "model_refused"
                                self.mutateTurn(conversationID: convoID, turnID: turnID, persist: false) {
                                    $0.failureStage = "上游模型拒答"
                                }
                                self.finishGeneration(conversationID: convoID, turnID: turnID,
                                                      state: .failed("原任务被模型拒绝，未重新提交。"))
                                return
                            }
                            if rec.outputComplete == false {
                                self.pendingCallTrace?.failureCode = "stream_interrupted_partial"
                                self.mutateTurn(conversationID: convoID, turnID: turnID, persist: false) {
                                    $0.failureStage = "原任务中断 · 仅恢复片段"
                                }
                                self.finishGeneration(conversationID: convoID, turnID: turnID,
                                                      state: .failed("已保留原任务生成的片段。这不是完整答案，未重新提交。"))
                                return
                            }
                            if !self.pendingAnswer.isEmpty || !self.pendingReasoning.isEmpty {
                                self.finishGeneration(conversationID: convoID, turnID: turnID, state: .complete)
                                return
                            }
                        } else if rec.status == "in_progress" {
                            self.pendingCallTrace?.failureCode = "network_interrupted_in_progress"
                            let holdMsg = rec.message ?? "网络连接已中断，但原任务仍在云端生成中（未重新提交、不重复扣费）。请稍候点击「查询原任务结果」恢复，不要重复发送。"
                            self.mutateTurn(conversationID: convoID, turnID: turnID, persist: false) { item in
                                item.failureStage = "网络中断 · 原任务仍在云端生成"
                            }
                            self.finishGeneration(conversationID: convoID, turnID: turnID, state: .failed(holdMsg))
                            return
                        }
                    }
                }

                let hadPartialOutput = !self.pendingAnswer.isEmpty || !self.pendingReasoning.isEmpty
                let fallbackMsg = activeChannel == .managed
                    ? (hadPartialOutput
                        ? "流式接收中途断开，已保留已收到的片段（为避免重复计费不会自动重发）。请先点击「查询原任务结果」，确认未完成后再重发。"
                        : "WUMIND 计费网关暂不可用，本次未扣费。")
                    : (hadPartialOutput
                        ? "流式接收中途断开，已保留已收到的片段（未自动重发）。如需重跑请点击「立即重试发送」。"
                        : "未收到完整回复，请检查网络或 API Key。")
                let rawMessage = (error as? LocalizedError)?.errorDescription ?? fallbackMsg
                let message = (hadPartialOutput && !rawMessage.contains("已保留"))
                    ? "\(rawMessage)（已保留已收到片段，不会自动重发以防重复计费）"
                    : rawMessage
                let diagnostic = error as? AIProviderDiagnosticError
                self.pendingCallTrace?.failureCode = diagnostic?.isDisabledAPIKey == true
                    ? "provider_key_disabled" : diagnostic?.errorCode ?? "stream_error"
                self.mutateTurn(conversationID: convoID, turnID: turnID, persist: false) { item in
                    item.failureStage = hadPartialOutput ? "流式接收中途中断（未自动重发）" : currentStage
                }
                self.finishGeneration(conversationID: convoID, turnID: turnID, state: .failed(message))
            }
        }
    }

    /// Reconnect on foreground without sending a model request or changing connectivity route.
    func reconcileBackgroundTasks() async {
        let owner = currentStorageOwnerID
        guard let conversation = activeConversation else { return }
        let recentTurns = Array(conversation.turns.suffix(10).reversed())
        let videoWorkIDs = recentTurns.filter { $0.id != activeTurnID }.compactMap(\.chatBuildWorkID)
        let works = WuMindWorksStore.shared
        if !videoWorkIDs.isEmpty {
            await works.reconcileBackgroundVideos(preferredWorkIDs: videoWorkIDs)
            guard !Task.isCancelled, currentStorageOwnerID == owner else { return }
            for turn in recentTurns where turn.state != .complete && turn.id != activeTurnID {
                guard let id = turn.chatBuildWorkID,
                      let work = works.works.first(where: { $0.id == id && $0.workType == .video }),
                      work.isCompleted, works.localAssetURL(for: work) != nil else { continue }
                mutateTurn(conversationID: conversation.id, turnID: turn.id, persist: true) {
                    $0.state = .complete
                    $0.failureStage = nil
                    $0.answer = "已恢复原视频任务，可以在对话中打开或分享。"
                }
            }
        }
        guard !Task.isCancelled, currentStorageOwnerID == owner,
              let interrupted = recentTurns.first(where: {
                  $0.id != activeTurnID && $0.state != .complete
                      && $0.callTrace?.failureCode == "network_interrupted_in_progress"
              }) else { return }
        _ = await recoverInterruptedTurn(conversationID: conversation.id, turnID: interrupted.id)
    }

    /// Queries the original Gateway task status by `clientRequestID` for an interrupted/failed managed turn
    /// so the user can recover settled output with ¥0 duplicate billing instead of resubmitting blindly.
    @discardableResult
    func recoverInterruptedTurn(conversationID: UUID, turnID: UUID) async -> String {
        guard let convo = conversations.first(where: { $0.id == conversationID }),
              let turn = convo.turns.first(where: { $0.id == turnID }),
              let requestID = turn.clientRequestID, !requestID.isEmpty else {
            return "该轮次没有可查询的原任务编号，请直接重新发送。"
        }
        guard hasGatewayURL, let token = Keychain.wumindGatewayUserToken, !token.isEmpty else {
            return "未连接到 WUMIND 内置网关，无法查询原任务状态。"
        }
        let owner = currentStorageOwnerID
        let gateway = gatewayBaseURL
        do {
            let rec = try await WuMindGatewayClient().recoverChatTask(
                gatewayURL: gateway,
                userToken: token,
                clientRequestID: requestID
            )
            guard !Task.isCancelled, currentStorageOwnerID == owner,
                  gatewayBaseURL == gateway, Keychain.wumindGatewayUserToken == token else {
                return "账号或网关已切换，没有写入查询结果。"
            }
            switch rec.status {
            case "settled":
                if let bal = rec.billing?.balanceYuan {
                    managedBalanceYuan = bal
                }
                mutateTurn(conversationID: conversationID, turnID: turnID, persist: true) { item in
                    if let r = rec.reasoning, !r.isEmpty { item.reasoning = r }
                    if let c = rec.content, !c.isEmpty { item.answer = c }
                    if let b = rec.billing {
                        item.promptTokens = b.promptTokens
                        item.completionTokens = b.completionTokens
                        item.reasoningTokens = b.reasoningTokens
                        item.costYuan = b.costYuan
                    } else if let cost = rec.costYuan {
                        item.costYuan = cost
                    }
                    item.callTrace?.recoveredFromOriginalTask = true
                    item.callTrace?.succeeded = rec.outputComplete != false
                    item.callTrace?.failureCode = rec.outputComplete == false ? "stream_interrupted_partial" : nil
                    item.failureStage = rec.outputComplete == false ? "原任务中断 · 仅恢复片段" : nil
                    if rec.failureCode == "model_refused" {
                        item.answer = ""
                        item.reasoning = ""
                        item.callTrace?.failureCode = "model_refused"
                        item.failureStage = "上游模型拒答"
                        item.state = .failed("原任务被模型拒绝，未重新提交。")
                        item.modelCapabilityBadge = "上游模型拒答"
                    } else if rec.outputComplete == false {
                        item.state = .failed("已保留原任务生成的片段。这不是完整答案，未重新提交。")
                        item.modelCapabilityBadge = "原任务仅恢复片段"
                    } else if !item.answer.isEmpty || !item.reasoning.isEmpty {
                        item.state = .complete
                        item.modelCapabilityBadge = "原任务已恢复"
                    }
                }
                if rec.failureCode == "model_refused" {
                    return "原任务被模型拒绝，未重新提交。"
                }
                if rec.outputComplete == false {
                    return "已保留原任务生成的片段，不是完整答案。未重新提交。"
                }
                if (rec.content?.isEmpty == false) || (rec.reasoning?.isEmpty == false) {
                    return "已从原任务恢复完整结果（未重新提交、未重复扣费）。"
                }
                return "原任务已在服务端完成结算（¥\(String(format: "%.4f", rec.costYuan ?? 0))），但未缓存正文副本；为防重复计费未自动重发。"
            case "in_progress":
                return rec.message ?? "原任务仍在云端生成中，请稍候再次点击「查询原任务结果」，不要重复发送。"
            case "released":
                return rec.message ?? "原任务未完成且预扣额已退回，可安全重新发送。"
            default:
                return rec.message ?? "服务端未找到该任务记录（可能未到达网关或未扣费），可安全重新发送。"
            }
        } catch {
            return "暂时无法连接网关查询原任务状态，请待网络恢复后再点「查询原任务结果」。"
        }
    }

    private func appendStreamingAnswer(_ delta: String) {
        pendingAnswer += delta
        streamDirty = true
        guard pendingFirstRenderMs == nil, let started = generationStartedAt,
              !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        streamBuffer.answer = pendingAnswer
        streamBuffer.tick &+= 1
        streamBuffer.answerLayoutChanges.send()
        pendingFirstRenderMs = max(0, Int(Date().timeIntervalSince(started) * 1000))
    }

    #if DEBUG
    private(set) var streamBenchmark: WuMindFrameProbe?
    @Published private(set) var streamBenchmarkResult = ""

    func startStreamBenchmark(batched: Bool) {
        guard !isGenerating else { return }
        let question = "长回答滚动与主动中断"
        let conversation = ensureActiveConversation(initialPrompt: question)
        let turn = WuMindTurn(question: question, reasoning: "", answer: "", modelLabel: "离线流样例",
                              provider: .deepSeek, isDeepThinking: true, state: .generating)
        appendTurn(turn, to: conversation)
        pendingFirstRenderMs = nil
        pendingAnswer = ""
        pendingReasoning = "测试用思考摘要"
        streamBuffer.reset()
        streamDirty = true
        generationStartedAt = Date()
        thinkingStartedAt = generationStartedAt
        activeGenerationConversationID = conversation
        activeTurnID = turn.id
        streamBenchmarkResult = ""
        let probe = WuMindFrameProbe()
        streamBenchmark = probe
        probe.start()
        startStreamFlusher(turnID: turn.id)
        activeGenerationTask = Task { @MainActor in
            for index in 1...1500 {
                do { try await Task.sleep(nanoseconds: 12_000_000) } catch { return }
                guard activeTurnID == turn.id else { return }
                let delta = "第" + String(index) + "段：核对输入、处理过程和输出结果。\n\n"
                if batched {
                    pendingAnswer += delta
                    streamDirty = true
                } else { appendStreamingAnswer(delta) }
            }
            finishGeneration(conversationID: conversation, turnID: turn.id, state: .complete)
        }
    }
    #endif

    private func recordFirstTokenLatencyIfNeeded() {
        guard pendingFirstTokenMs == nil, let started = generationStartedAt else { return }
        pendingFirstTokenMs = max(1, Int(Date().timeIntervalSince(started) * 1000))
    }

    private func runSingleModelStep(
        turnID: UUID,
        channel: WuMindChannel,
        provider: WuMindProvider,
        modelID: String,
        apiKey: String?,
        userToken: String?,
        messages: [AIProviderMessage],
        systemPrompt: String?,
        isDeep: Bool,
        sessionTag: String?,
        clientRequestID: String? = nil
    ) async throws -> StepOutput {
        let estPrompt = WuMindContextEngine.estimateTokens(
            (systemPrompt ?? "") + messages.map(\.text).joined(separator: "\n")
        )

        if channel == .managed {
            guard let token = userToken else { throw WuMindGatewayClient.GatewayError.unauthorized }
            var stepReasoning = ""
            var stepAnswer = ""
            var answerStarted = false
            var receipt: WuMindBillingReceipt? = nil

            for try await event in WuMindGatewayClient().streamChat(
                gatewayURL: gatewayBaseURL,
                userToken: token,
                modelID: modelID,
                messages: messages,
                systemPrompt: systemPrompt,
                deepThinking: isDeep,
                sessionTag: sessionTag,
                idempotencyKey: clientRequestID ?? "turn-\(turnID.uuidString)-\(messages.count)"
            ) {
                guard !Task.isCancelled, activeTurnID == turnID else { throw CancellationError() }
                switch event {
                case .trace(let tr):
                    pendingCallTrace?.actualModelID = tr.actualModel
                    if let reported = tr.providerReportedModel { recordReportedModel(reported) }
                    if tr.providerModelConflict == true { pendingCallTrace?.providerModelConflict = true }
                    if tr.reasoningObserved == true { pendingCallTrace?.reasoningObserved = true }
                    pendingCallTrace?.upstreamRoute = tr.upstreamRoute
                    pendingCallTrace?.thinkingParamSent = tr.thinkingParam
                    pendingCallTrace?.imagesSentCount = tr.imagesSent
                    pendingCallTrace?.recoveredFromOriginalTask = tr.recoveredFromOriginalTask
                    pendingCallTrace?.timing.gatewayWaitMs = tr.gatewayPrepMs + tr.upstreamHeaderMs
                case .reasoning(let delta):
                    recordFirstTokenLatencyIfNeeded()
                    stepReasoning += delta
                    pendingReasoning += delta
                    streamDirty = true
                case .content(let delta):
                    recordFirstTokenLatencyIfNeeded()
                    if !answerStarted {
                        answerStarted = true
                        if !pendingReasoning.isEmpty, pendingReasoningSeconds == nil {
                            pendingReasoningSeconds = thinkingStartedAt.map { Date().timeIntervalSince($0) }
                        }
                    }
                    stepAnswer += delta
                    appendStreamingAnswer(delta)
                case .billing(let b):
                    receipt = b
                    // Defer balance @Published update until finishGeneration so mid-stream doesn't redraw whole page
                    pendingDeferredBalanceYuan = b.balanceYuan
                case .warning(let warn):
                    if !warn.isEmpty {
                        stepAnswer += "\n\n> ⚠️ \(warn)"
                        pendingAnswer += "\n\n> ⚠️ \(warn)"
                        streamDirty = true
                    }
                }
            }
            return StepOutput(
                reasoning: stepReasoning,
                answer: stepAnswer,
                promptTokens: receipt?.promptTokens ?? estPrompt,
                completionTokens: receipt?.completionTokens ?? WuMindContextEngine.estimateTokens(stepAnswer),
                reasoningTokens: receipt?.reasoningTokens ?? WuMindContextEngine.estimateTokens(stepReasoning),
                costYuan: receipt?.costYuan ?? 0,
                billedByGateway: receipt != nil
            )
        }

        guard let key = apiKey, !key.isEmpty else {
            throw DeepSeekChatClient.Failure.missingKey
        }

        if provider == .deepSeek {
            let dsModel = DeepSeekChatClient.Model(rawValue: modelID) ?? .pro
            let dsThinking: DeepSeekChatClient.Thinking = isDeep ? .deep : .normal
            pendingCallTrace?.actualModelID = dsModel.rawValue
            pendingCallTrace?.upstreamRoute = "own_direct"
            pendingCallTrace?.host = "api.deepseek.com"
            pendingCallTrace?.endpointPath = "/chat/completions"
            pendingCallTrace?.thinkingParamSent = isDeep ? "thinking={type:enabled}" : "none"
            let dsMessages: [DeepSeekChatClient.Message] = messages.map {
                .init(role: $0.role == .assistant ? .assistant : .user, content: $0.text)
            }
            var stepReasoning = ""
            var stepAnswer = ""
            var answerStarted = false

            for try await event in DeepSeekChatClient.streamEvents(
                messages: dsMessages,
                apiKey: key,
                model: dsModel,
                thinking: dsThinking,
                systemPrompt: systemPrompt,
                extendedContext: true
            ) {
                guard !Task.isCancelled, activeTurnID == turnID else { throw CancellationError() }
                switch event {
                case .reportedModel(let model):
                    recordReportedModel(model)
                case .reasoning(let delta):
                    recordFirstTokenLatencyIfNeeded()
                    stepReasoning += delta
                    pendingReasoning += delta
                    streamDirty = true
                case .content(let delta):
                    recordFirstTokenLatencyIfNeeded()
                    if !answerStarted {
                        answerStarted = true
                        if !pendingReasoning.isEmpty, pendingReasoningSeconds == nil {
                            pendingReasoningSeconds = thinkingStartedAt.map { Date().timeIntervalSince($0) }
                        }
                    }
                    stepAnswer += delta
                    appendStreamingAnswer(delta)
                }
            }
            markModelSmokePassed(.deepSeek, modelID: modelID, host: "api.deepseek.com", endpointPath: "/chat/completions", latencyMs: pendingFirstTokenMs)
            return StepOutput(
                reasoning: stepReasoning,
                answer: stepAnswer,
                promptTokens: estPrompt,
                completionTokens: WuMindContextEngine.estimateTokens(stepAnswer),
                reasoningTokens: WuMindContextEngine.estimateTokens(stepReasoning),
                costYuan: 0,
                billedByGateway: false
            )
        }

        guard let mp = provider.multiProvider else {
            throw DeepSeekChatClient.Failure.network
        }
        let modelObj = AIProviderModel(id: modelID, displayName: modelID, supportsTextChat: true)
        let startedAt = Date()
        let baseURL = AIProviderEndpoints.baseURL(for: mp)
        var stepReasoning = ""
        var stepAnswer = ""
        var answerStarted = false
        var resolvedHost = mp.resolvedHost(baseURL: baseURL)
        var resolvedPath = "/v1/chat/completions"

        do {
            for try await event in MultiProviderAIClient().streamChatDiagnosed(
                provider: mp,
                model: modelObj,
                apiKey: key,
                messages: messages,
                deepThinking: isDeep,
                baseURL: baseURL,
                systemPrompt: systemPrompt,
                strictFidelity: true
            ) {
                guard !Task.isCancelled, activeTurnID == turnID else { throw CancellationError() }
                switch event {
                case .reasoning(let delta):
                    recordFirstTokenLatencyIfNeeded()
                    stepReasoning += delta
                    pendingReasoning += delta
                    streamDirty = true
                case .content(let delta):
                    recordFirstTokenLatencyIfNeeded()
                    if !answerStarted {
                        answerStarted = true
                        if !pendingReasoning.isEmpty, pendingReasoningSeconds == nil {
                            pendingReasoningSeconds = thinkingStartedAt.map { Date().timeIntervalSince($0) }
                        }
                    }
                    stepAnswer += delta
                    appendStreamingAnswer(delta)
                case .reportedModel(let model):
                    recordReportedModel(model)
                case .finished(let host, let endpointPath):
                    resolvedHost = host
                    resolvedPath = endpointPath
                    pendingCallTrace?.host = host
                    pendingCallTrace?.endpointPath = endpointPath
                    pendingCallTrace?.upstreamRoute = (AIProviderEndpoints.displayHost(for: mp) != nil) ? "own_relay" : "own_direct"
                }
            }
        } catch let diag as AIProviderDiagnosticError {
            markModelSmokeFailed(
                provider,
                modelID: modelID,
                host: diag.host,
                httpStatus: diag.httpStatus,
                errorCode: diag.errorCode,
                detail: diag.sanitizedDetail ?? diag.shortBadgeSummary
            )
            throw diag
        }
        guard !Task.isCancelled, activeTurnID == turnID else { throw CancellationError() }
        let elapsedMs = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
        markModelSmokePassed(
            provider,
            modelID: modelID,
            host: resolvedHost,
            endpointPath: resolvedPath,
            latencyMs: elapsedMs
        )
        return StepOutput(
            reasoning: stepReasoning,
            answer: stepAnswer,
            promptTokens: estPrompt,
            completionTokens: WuMindContextEngine.estimateTokens(stepAnswer),
            reasoningTokens: WuMindContextEngine.estimateTokens(stepReasoning),
            costYuan: 0,
            billedByGateway: false
        )
    }

    private struct SearchGatewayReadiness {
        let failure: String?
        let perSearchCostYuan: Double?

        func actionLabel(maxSearches: Int) -> String {
            guard let cost = perSearchCostYuan else {
                return "改用网关搜索（可能按次扣费）"
            }
            if cost == 0 { return "改用网关搜索（免扣）" }
            return "改用网关搜索（每次 ¥\(String(format: "%.2f", cost))，最多 \(maxSearches) 次）"
        }
    }

    private func searchGatewayReadiness(url: String, token: String) async -> SearchGatewayReadiness {
        let client = WuMindGatewayClient()
        do {
            let config = try await client.fetchPublicConfig(gatewayURL: url)
            if config.searchConfigured == false {
                return .init(failure: "网关已连接，但服务端尚未开启搜索。请联系管理员配置。", perSearchCostYuan: nil)
            }
            guard url == gatewayBaseURL, token == managedSessionToken else {
                return .init(failure: "内置搜索登录状态已更改，请重新登录。", perSearchCostYuan: nil)
            }
            let account = try await client.fetchAccountStatus(gatewayURL: url, userToken: token)
            let cost = account.isBillingExempt ? 0 : config.webSearchCostYuan
            return .init(failure: nil, perSearchCostYuan: cost)
        } catch let error as WuMindGatewayClient.GatewayError {
            let reason = error == .unauthorized ? "WUMIND 网关登录已失效，请重新登录。" : (error.errorDescription ?? "无法检查网关搜索状态。")
            return .init(failure: reason, perSearchCostYuan: nil)
        } catch {
            return .init(failure: "暂时无法连接内置搜索，请检查网络或联系管理员。", perSearchCostYuan: nil)
        }
    }

    private func personalWebSearchKeys() -> (tavily: String?, brave: String?) {
        let rawKey = Keychain.connectorToken(for: "dev.websearch")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawKey, !rawKey.isEmpty else { return (nil, nil) }
        return rawKey.hasPrefix("tvly-") ? (rawKey, nil) : (nil, rawKey)
    }

    private func appendSearchCitations(_ results: [WuMindWebSearchResult]) {
        for item in results {
            let url = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard WuMindAgentTools.isUsableSearchURL(url),
                  !pendingWebCitations.contains(where: { $0.url == url }) else { continue }
            let host = URL(string: url)?.host?.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression) ?? url
            pendingWebCitations.append(.init(
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? host : item.title,
                domain: host,
                url: url,
                snippet: String(item.snippet.prefix(240)),
                verifiedRead: item.isFullTextRead
            ))
        }
        streamBuffer.liveWebCitations = pendingWebCitations
        streamBuffer.tick &+= 1
    }

    func performVerifiedWebSearch(
        query: String,
        channel: WuMindChannel,
        userToken: String?,
        depth: String = "basic",
        selectedRoute: WuMindSearchRouting.Route? = nil,
        gatewayURLOverride: String? = nil,
        updateChat: Bool = true
    ) async -> WuMindAgentTools.ToolResult {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func fail(_ status: String, _ detail: String, cost: Double = 0) -> WuMindAgentTools.ToolResult {
            if updateChat && !Task.isCancelled {
                setInlineStatus(.warning, text: detail)
                pendingToolFailures.append(.init(toolKind: "web_search", targetName: cleanQuery, message: detail))
            }
            return .init(
                succeeded: false,
                summary: detail,
                observationText: WuMindAgentTools.formatSearchFailureObservation(query: cleanQuery, status: status, error: detail),
                extraCostYuan: cost,
                searchStatus: status
            )
        }
        guard !cleanQuery.isEmpty else { return fail("invalid_query", "搜索关键词为空。") }

        let keys = channel == .ownAPI ? personalWebSearchKeys() : (tavily: nil, brave: nil)
        let route = selectedRoute ?? WuMindSearchRouting.firstRoute(
            usesOwnChat: channel == .ownAPI, hasPersonalKey: keys.tavily != nil || keys.brave != nil,
            hasGatewaySession: hasGatewayURL && userToken?.isEmpty == false
        )
        if route == .personal {
            guard keys.tavily != nil || keys.brave != nil else {
                return fail("search_not_configured", "个人搜索配置已更改，请重新选择搜索通道。")
            }
            if updateChat { setInlineStatus(.searching, text: "正在搜索：\(cleanQuery)") }
            let result = await WuMindAgentTools.directWebSearch(
                query: cleanQuery, maxResults: 5, depth: depth,
                tavilyKey: keys.tavily, braveKey: keys.brave,
                allowPublicFallback: false
            )
            if Task.isCancelled { return fail("cancelled", "联网搜索已取消。") }
            if result.succeeded {
                if updateChat { appendSearchCitations(result.searchResults) }
                return result
            }
            return fail(result.searchStatus ?? "upstream_error", result.summary)
        }

        let gatewayURL = gatewayURLOverride ?? gatewayBaseURL
        guard (try? WuMindGatewayClient.normalizedGatewayURL(gatewayURL)) != nil else {
            return fail("search_not_configured", "当前版本的内置搜索网关尚未配置，请联系管理员。")
        }
        guard route == .gateway, let token = userToken, !token.isEmpty,
              gatewayURL == gatewayBaseURL, token == managedSessionToken else {
            return fail("unauthorized", "请登录 WuMind 后使用内置联网搜索。")
        }

        do {
            let events = WuMindGatewayClient().streamWebSearch(
                gatewayURL: gatewayURL, userToken: token,
                query: cleanQuery, maxResults: 5, depth: depth,
                readTopPages: 2, allowFallback: false
            )
            var finalResponse: WuMindWebSearchResponse?
            for try await event in events {
                try Task.checkCancellation()
                switch event {
                case .searching(let realQuery):
                    if updateChat { setInlineStatus(.searching, text: "正在搜索：\(realQuery.isEmpty ? cleanQuery : realQuery)") }
                case .reading(let title, let domain, let url, _, _):
                    guard updateChat else { continue }
                    let source = [domain, title, URL(string: url)?.host ?? ""]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first { !$0.isEmpty } ?? "来源网页"
                    setInlineStatus(.reading, text: "正在阅读：\(source)")
                case .done(let response):
                    finalResponse = response
                case .error(let httpStatus, let code, let detail):
                    if httpStatus == 401 || code == "unauthorized" {
                        return fail(code, "WUMIND 网关登录已失效，请重新登录。")
                    }
                    return fail(code, detail)
                case .searchResults, .pageResult:
                    break
                }
            }
            try Task.checkCancellation()
            guard gatewayURL == gatewayBaseURL, token == managedSessionToken else {
                return fail("unauthorized", "内置搜索登录状态已更改，请重新登录。")
            }
            // An interrupted stream may already have been billed. Do not POST a second search.
            guard let response = finalResponse else {
                return fail("upstream_error", "网关未返回完整的搜索结果。本轮没有自动重复提交。")
            }

            if let balance = response.balanceYuan { managedBalanceYuan = balance }
            let results = response.results.filter { WuMindAgentTools.isUsableSearchURL($0.url) }
            let status = response.evidenceStatus
            if status != "ok" && status != "no_results" {
                return fail(status, response.error ?? "WUMIND 网关搜索不可用。", cost: response.costYuan)
            }
            guard status == "ok", !results.isEmpty else {
                return fail("no_results", "联网搜索未搜到有效结果。", cost: response.costYuan)
            }
            if updateChat { appendSearchCitations(results) }
            let fullCount = results.filter(\.isFullTextRead).count
            let failedCount = results.filter(\.isFetchFailed).count
            let label = response.provider.isEmpty ? "WUMIND 网关" : "WUMIND · \(response.provider)"
            var summary = "\(label) 搜得 \(results.count) 条"
            if fullCount > 0 { summary += " · 已读原文 \(fullCount) 篇" }
            else if failedCount > 0 { summary += " · 仅摘要（原文打不开）" }
            else { summary += " · 仅摘要" }
            return .init(
                succeeded: true,
                summary: summary,
                observationText: WuMindAgentTools.formatSearchObservation(query: cleanQuery, provider: label, results: results),
                extraCostYuan: response.costYuan,
                searchResults: results
            )
        } catch let error as WuMindGatewayClient.GatewayError {
            let reason = error == .unauthorized ? "WUMIND 网关登录已失效，请重新登录。" : (error.errorDescription ?? "联网搜索受阻。")
            return fail("upstream_error", reason)
        } catch is CancellationError {
            return fail("cancelled", "联网搜索已取消。")
        } catch {
            return fail("upstream_error", "联网搜索连接失败，请检查网络。")
        }
    }

    private func executeAgentTool(
        _ invocation: WuMindAgentProtocol.ToolInvocation,
        conversationID: UUID,
        channel: WuMindChannel,
        userToken: String?
    ) async -> WuMindAgentTools.ToolResult {
        switch invocation.tool {
        case "web_search":
            let query = invocation.args["query"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let depth = invocation.args["depth"] ?? "basic"
            return await performVerifiedWebSearch(
                query: query,
                channel: channel,
                userToken: userToken,
                depth: depth
            )

        case "web_fetch":
            let url = invocation.args["url"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let token = userToken, !token.isEmpty, token == managedSessionToken, hasGatewayURL, !url.isEmpty {
                if let res = try? await WuMindGatewayClient().webFetch(
                    gatewayURL: gatewayBaseURL,
                    userToken: token,
                    url: url
                ) {
                    if res.isFullTextRead {
                        return WuMindAgentTools.ToolResult(
                            succeeded: true,
                            summary: "已读取原文（\(res.extractedText.count) 字）",
                            observationText: "【网页原文已核实：\(res.url)】\n\(res.extractedText)"
                        )
                    } else {
                        let reason = res.fetchError ?? "原文无法打开"
                        return WuMindAgentTools.ToolResult(
                            succeeded: false,
                            summary: reason,
                            observationText: "【网页原文读取失败：\(res.url)】\(reason)。请勿编造该网页正文内容。"
                        )
                    }
                }
            }
            return await WuMindAgentTools.webFetch(urlString: url)

        case "calculator_verify":
            let expr = invocation.args["expression"] ?? ""
            return WuMindAgentTools.evaluateMathExpression(expr)

        case "project_search":
            let query = invocation.args["query"] ?? ""
            let convo = conversations.first(where: { $0.id == conversationID })
            let docs = project(for: convo)?.knowledgeDocs ?? []
            return WuMindAgentTools.searchProjectKnowledge(query: query, docs: docs)

        case "github_inspect":
            let repoArg = invocation.args["repo"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let convo = conversations.first(where: { $0.id == conversationID })
            let targetRepo = !repoArg.isEmpty
                ? repoArg
                : (attachedGitHubContext?.repo.fullName ?? project(for: convo)?.attachedRepoFullName ?? "")
            guard !targetRepo.isEmpty else {
                return WuMindAgentTools.ToolResult(succeeded: false, summary: "未指定 GitHub 仓库", observationText: "请提供 owner/repo 参数或先在 WUMIND 连接 GitHub 仓库。")
            }
            let token = Keychain.githubToken
            let client = WuMindGitHubClient()
            if let filePath = invocation.args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines), !filePath.isEmpty {
                do {
                    let file = try await client.fetchFileContent(fullName: targetRepo, path: filePath, ref: nil, token: token)
                    return WuMindAgentTools.ToolResult(
                        succeeded: true,
                        summary: "已读取 \(targetRepo)/\(file.path)",
                        observationText: "【GitHub 源码：\(targetRepo)/\(file.path)】\n\(String(file.content.prefix(16_000)))"
                    )
                } catch {
                    return WuMindAgentTools.ToolResult(succeeded: false, summary: "读取源码失败", observationText: "无法读取 \(targetRepo)/\(filePath)，请检查路径或授权。")
                }
            } else {
                do {
                    let ctx = try await client.fetchRepoContext(fullName: targetRepo, token: token)
                    attachedGitHubContext = ctx
                    return WuMindAgentTools.ToolResult(
                        succeeded: true,
                        summary: "已拉取仓库 \(ctx.repo.fullName)",
                        observationText: ctx.formattedPromptContext()
                    )
                } catch {
                    return WuMindAgentTools.ToolResult(succeeded: false, summary: "仓库访问失败", observationText: "无法访问 GitHub 仓库 \(targetRepo)。")
                }
            }

        case "duty_schedule_lookup":
            if AppAccountManager.shared.isExternalRestricted {
                return WuMindAgentTools.ToolResult(
                    succeeded: false,
                    summary: "外部账号无权读取内部排班",
                    observationText: "权限拒绝：当前为外部账号，受隔离边界禁止访问内部排班与值班记录。"
                )
            }
            return WuMindAgentTools.ToolResult(
                succeeded: true,
                summary: "内网值班查询已受零外发保护",
                observationText: "内网值班与排班数据禁止发送给外部公共模型；用户直接提问值班相关问题时，将由 App 本机内网只读引擎直接查全员排班、调班、轮休与权威请假源并在本地合成答复。"
            )

        case "webhook_call":
            let cid = invocation.args["connector_id"] ?? "dev.webhook"
            let endpoint = connectorEndpoints[cid] ?? connectorEndpoints["dev.webhook"] ?? ""
            let token = Keychain.connectorToken(for: cid) ?? Keychain.connectorToken(for: "dev.webhook")
            let action = invocation.args["action"] ?? "run"
            let payload = invocation.args["payload"] ?? ""
            return await WuMindAgentTools.callCustomWebhook(
                endpointURL: endpoint,
                authToken: token,
                action: action,
                payload: payload
            )

        default:
            return WuMindAgentTools.ToolResult(
                succeeded: false,
                summary: "未知工具 \(invocation.tool)",
                observationText: "不支持的工具名称：\(invocation.tool)。"
            )
        }
    }

    // MARK: - Local + Background Scheduled Task Execution Engine

    /// Checks enabled LOCAL (Own API Key) scheduled tasks and executes any due tasks cleanly.
    /// IMPORTANT: Cloud-managed (`channelRaw == "managed"`) tasks execute EXCLUSIVELY on Cloudflare Cron
    /// and are NEVER double-executed locally on iOS!
    func runDueScheduledTasksIfNeeded() async {
        guard !isGenerating, runningScheduleID == nil else { return }
        let now = Date()
        let dueTasks = scheduledTasks.filter { task in
            guard task.enabled,
                  task.serverStatus != "paused",
                  task.serverStatus != "completed",
                  task.serverStatus != "cancelled" else { return false }
            // Never double-run cloud-managed schedules locally!
            guard !task.isManagedCloudTask else { return false }
            return (task.nextRunAt ?? .distantFuture) <= now
        }
        for task in dueTasks.prefix(2) {
            await runScheduledTaskNow(task, manualTrigger: false)
        }
    }

    func runScheduledTaskNow(_ task: WuMindScheduledTask, manualTrigger: Bool = true) async {
        guard runningScheduleID == nil else { return }
        runningScheduleID = task.id
        beginBackgroundExecution()
        defer {
            runningScheduleID = nil
            endBackgroundExecution()
        }

        let startedAt = Date()
        let runStamp = WuMindScheduleCadence.formatBeijingDate(startedAt)
        let runIdemKey = "local:\(task.id.uuidString):\(Int(startedAt.timeIntervalSince1970))"

        // Pre-claim non-manual runs BEFORE network call so a one-time task can NEVER execute twice!
        if !manualTrigger, let idx = scheduledTasks.firstIndex(where: { $0.id == task.id }) {
            if case .once = scheduledTasks[idx].cadence {
                scheduledTasks[idx].enabled = false
                scheduledTasks[idx].serverStatus = "completed"
                scheduledTasks[idx].nextRunAt = nil
                scheduledTasks[idx].nextRunBeijingText = nil
            } else {
                let nextDate = scheduledTasks[idx].cadence.nextRunDate(after: startedAt)
                scheduledTasks[idx].nextRunAt = nextDate
                scheduledTasks[idx].nextRunBeijingText = nextDate.map { WuMindScheduleCadence.formatBeijingDate($0) }
            }
            saveNow()
        }

        // Reminder-only mode: explicitly record `reminderSent`, zero LLM call & ¥0 cost!
        if task.executionMode == .reminderOnly {
            let reminderText = "⏰ 到点提醒已送达：\(task.title)\n\(task.prompt)"
            let convo = WuMindConversation(
                title: "⏰ \(task.title)",
                provider: selectedProvider,
                modelID: "reminder_only",
                modelDisplayName: "仅到点提醒",
                deepThinking: false,
                projectID: task.projectID
            )
            var fullConvo = convo
            fullConvo.turns = [
                WuMindTurn(
                    question: task.prompt,
                    answer: reminderText,
                    modelLabel: "到点提醒已送达（未调用 AI）",
                    provider: selectedProvider,
                    isDeepThinking: false,
                    state: .complete,
                    costYuan: 0
                )
            ]
            conversations.insert(fullConvo, at: 0)
            if let idx = scheduledTasks.firstIndex(where: { $0.id == task.id }) {
                let rec = WuMindScheduleRunRecord(
                    idempotencyKey: runIdemKey,
                    executedAtText: runStamp,
                    status: .reminderSent,
                    executionMode: .reminderOnly,
                    modelID: "",
                    costYuan: 0,
                    answerPreview: reminderText,
                    conversationID: fullConvo.id
                )
                scheduledTasks[idx].runs.insert(rec, at: 0)
                if scheduledTasks[idx].runs.count > 20 { scheduledTasks[idx].runs = Array(scheduledTasks[idx].runs.prefix(20)) }
                scheduledTasks[idx].lastRunAt = startedAt
                scheduledTasks[idx].lastStatus = WuMindScheduleRunStatus.reminderSent.badgeLabel
                scheduledTasks[idx].lastCostYuan = 0
                scheduledTasks[idx].lastConversationID = fullConvo.id
            }
            saveNow()
            if preferences.backgroundNotificationsEnabled {
                postBackgroundCompletionNotification(title: "到点提醒：\(task.title)", preview: task.prompt)
            }
            return
        }

        let targetChannel = WuMindChannel(rawValue: task.channelRaw) ?? channel
        let provider: WuMindProvider = {
            if targetChannel == .managed,
               let item = managedConfig.pricing.first(where: { $0.id == task.modelID }),
               let p = WuMindProvider(rawValue: item.provider) {
                return p
            }
            return selectedProvider
        }()
        let modelID = task.modelID.isEmpty ? selectedModelID : task.modelID

        let convo = WuMindConversation(
            title: "⏰ \(task.title)",
            provider: provider,
            modelID: modelID,
            modelDisplayName: task.title,
            deepThinking: false,
            projectID: task.projectID
        )
        conversations.insert(convo, at: 0)
        let turnID = UUID()
        let turn = WuMindTurn(
            id: turnID,
            question: task.prompt,
            modelLabel: "定时任务 · \(modelID)",
            provider: provider,
            isDeepThinking: false,
            state: .generating
        )
        appendTurn(turn, to: convo.id)

        do {
            let userToken: String? = targetChannel == .managed ? try await ensureManagedAccount() : nil
            let apiKey = targetChannel == .ownAPI ? provider.apiKey() : nil
            let sysPrompt = composedSystemPrompt(conversationID: convo.id, includeAgentDirective: false)
            let estPrompt = WuMindContextEngine.estimateTokens((sysPrompt ?? "") + task.prompt)
            var answerText = ""
            var promptTokens = estPrompt
            var completionTokens = 0
            var reasoningTokens = 0
            var costYuan: Double? = nil

            if targetChannel == .managed, let token = userToken, hasGatewayURL {
                for try await ev in WuMindGatewayClient().streamChat(
                    gatewayURL: gatewayBaseURL,
                    userToken: token,
                    modelID: modelID,
                    messages: [.init(role: .user, text: task.prompt)],
                    systemPrompt: sysPrompt,
                    deepThinking: false,
                    sessionTag: "定时任务 · \(task.title)"
                ) {
                    switch ev {
                    case .trace: break
                    case .reasoning: break
                    case .content(let delta): answerText += delta
                    case .billing(let b):
                        managedBalanceYuan = b.balanceYuan
                        promptTokens = b.promptTokens
                        completionTokens = b.completionTokens
                        reasoningTokens = b.reasoningTokens
                        costYuan = b.costYuan
                    case .warning(let warn):
                        if !warn.isEmpty { answerText += "\n⚠️ \(warn)" }
                    }
                }
            } else if let key = apiKey, !key.isEmpty {
                if provider == .deepSeek {
                    let dsModel = DeepSeekChatClient.Model(rawValue: modelID) ?? .flash
                    for try await ev in DeepSeekChatClient.streamEvents(
                        messages: [.init(role: .user, content: task.prompt)],
                        apiKey: key,
                        model: dsModel,
                        thinking: .normal,
                        systemPrompt: sysPrompt,
                        extendedContext: true
                    ) {
                        if case .content(let delta) = ev { answerText += delta }
                    }
                    completionTokens = WuMindContextEngine.estimateTokens(answerText)
                } else if let mp = provider.multiProvider {
                    let reply = try await MultiProviderAIClient().sendDetailed(
                        provider: mp,
                        model: AIProviderModel(id: modelID, displayName: modelID, supportsTextChat: true),
                        apiKey: key,
                        messages: [.init(role: .user, text: task.prompt)],
                        deepThinking: false,
                        baseURL: AIProviderEndpoints.baseURL(for: mp),
                        systemPrompt: sysPrompt
                    )
                    answerText = reply.answer
                    completionTokens = WuMindContextEngine.estimateTokens(answerText)
                }
            } else {
                throw DeepSeekChatClient.Failure.missingKey
            }

            mutateTurn(conversationID: convo.id, turnID: turnID, persist: true) { item in
                item.answer = answerText
                item.promptTokens = promptTokens
                item.completionTokens = completionTokens
                item.reasoningTokens = reasoningTokens
                item.costYuan = costYuan
                item.state = .complete
            }

            if let idx = scheduledTasks.firstIndex(where: { $0.id == task.id }) {
                let rec = WuMindScheduleRunRecord(
                    idempotencyKey: runIdemKey,
                    executedAtText: runStamp,
                    status: .aiCompleted,
                    executionMode: .aiRun,
                    modelID: modelID,
                    costYuan: costYuan ?? 0,
                    answerPreview: String(answerText.prefix(160)),
                    conversationID: convo.id
                )
                scheduledTasks[idx].runs.insert(rec, at: 0)
                if scheduledTasks[idx].runs.count > 20 { scheduledTasks[idx].runs = Array(scheduledTasks[idx].runs.prefix(20)) }
                scheduledTasks[idx].lastRunAt = Date()
                scheduledTasks[idx].lastStatus = WuMindScheduleRunStatus.aiCompleted.badgeLabel
                scheduledTasks[idx].lastCostYuan = costYuan
                scheduledTasks[idx].lastTokens = promptTokens + completionTokens + reasoningTokens
                scheduledTasks[idx].lastConversationID = convo.id
            }
            saveNow()
            if preferences.backgroundNotificationsEnabled {
                postBackgroundCompletionNotification(title: "AI 定时任务完成：\(task.title)", preview: answerText)
            }
        } catch {
            let errMsg = (error as? LocalizedError)?.errorDescription ?? "定时任务执行失败"
            let isInsufficient = errMsg.contains("余额") || errMsg.lowercased().contains("insufficient")
            let runStatus: WuMindScheduleRunStatus = isInsufficient ? .failedInsufficientBalance : .failedUpstream
            mutateTurn(conversationID: convo.id, turnID: turnID, persist: true) { item in
                item.state = .failed(errMsg)
            }
            if let idx = scheduledTasks.firstIndex(where: { $0.id == task.id }) {
                let rec = WuMindScheduleRunRecord(
                    idempotencyKey: runIdemKey,
                    executedAtText: runStamp,
                    status: runStatus,
                    executionMode: .aiRun,
                    modelID: modelID,
                    costYuan: 0,
                    failureReason: errMsg,
                    conversationID: convo.id
                )
                scheduledTasks[idx].runs.insert(rec, at: 0)
                if scheduledTasks[idx].runs.count > 20 { scheduledTasks[idx].runs = Array(scheduledTasks[idx].runs.prefix(20)) }
                scheduledTasks[idx].lastRunAt = Date()
                scheduledTasks[idx].lastStatus = "\(runStatus.badgeLabel)：\(errMsg)"
                scheduledTasks[idx].lastConversationID = convo.id
            }
            saveNow()
        }
    }

    func stopGeneration() {
        let stopPressedAt = Date()
        activeGenerationTask?.cancel()
        if let cID = activeGenerationConversationID, let tID = activeTurnID {
            finishGeneration(conversationID: cID, turnID: tID, state: .stopped, stopPressedAt: stopPressedAt)
        } else {
            flushTimerTask?.cancel()
            flushTimerTask = nil
            activeGenerationTask = nil
            activeTurnID = nil
            activeGenerationConversationID = nil
            thinkingStartedAt = nil
            compactingContext = false
            pendingAgentSteps = []
            pendingActiveAgentPhase = nil
            pendingCallTrace = nil
            pendingDeferredBalanceYuan = nil
            streamBuffer.reset()
            endBackgroundExecution()
        }
    }

    /// Aggregated P50 / P95 phase-split latency metrics across recent real calls (never conflating client vs upstream).
    var latencySummaryForDiagnostics: (
        clientPrep: WuMindLatencyPercentiles,
        gatewayWait: WuMindLatencyPercentiles,
        upstreamTTFT: WuMindLatencyPercentiles,
        firstRender: WuMindLatencyPercentiles,
        stopLatency: WuMindLatencyPercentiles
    ) {
        (
            clientPrep: WuMindLatencyPercentiles.compute(from: recentCallTraces.map(\.timing.clientPrepMs)),
            gatewayWait: WuMindLatencyPercentiles.compute(from: recentCallTraces.compactMap(\.timing.gatewayWaitMs)),
            upstreamTTFT: WuMindLatencyPercentiles.compute(from: recentCallTraces.compactMap(\.timing.upstreamTTFTMs)),
            firstRender: WuMindLatencyPercentiles.compute(from: recentCallTraces.compactMap(\.timing.firstRenderMs)),
            stopLatency: WuMindLatencyPercentiles.compute(from: recentCallTraces.compactMap(\.timing.stopLatencyMs))
        )
    }

    func triggerManualCompaction(conversationID: UUID) {
        guard !isGenerating, !compactingContext,
              let convo = conversations.first(where: { $0.id == conversationID }) else { return }
        let snapshots = convo.turns
            .filter { $0.state == .complete && !$0.answer.isEmpty }
            .map { WuMindContextEngine.TurnSnapshot(question: $0.question, answer: $0.answer) }
        guard let manualPlan = WuMindContextEngine.planManualCompaction(
            turns: snapshots,
            compactedTurnCount: convo.safeCompactedTurnCount
        ) else {
            ToastCenter.shared.show("当前对话轮次较少，暂无需压缩", style: .info)
            return
        }
        let existingSummary = convo.compactedSummary
        let activeChannel = channel
        let provider = activeProviderForDisplay
        let modelID = activeChannel == .managed
            ? (activeManagedModel?.id ?? "deepseek-reasoner")
            : selectedModelID
        let apiKey = provider.apiKey()

        compactingContext = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.compactingContext = false }
            let summary = await self.runSemanticCompaction(
                existingSummary: existingSummary,
                turnsToCompact: manualPlan.turnsToCompact,
                channel: activeChannel,
                provider: provider,
                modelID: modelID,
                apiKey: apiKey
            )
            self.updateCompaction(
                conversationID: conversationID,
                summary: summary,
                compactedTurnCount: manualPlan.newCompactedTurnCount
            )
            ToastCenter.shared.show("已压缩前 \(manualPlan.newCompactedTurnCount) 轮上下文", style: .success)
        }
    }

    private func recordReportedModel(_ reported: String) {
        if let previous = pendingCallTrace?.providerReportedModelID {
            if previous != reported { pendingCallTrace?.providerModelConflict = true }
        } else {
            pendingCallTrace?.providerReportedModelID = reported
        }
    }

    private func startStreamFlusher(turnID: UUID) {
        flushTimerTask?.cancel()
        flushTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 80_000_000) // ~12.5 Hz smooth batched UI updates
                guard !Task.isCancelled, let self, self.activeTurnID == turnID else { break }

                // Monotonic 1Hz thinking/connecting clock independent of streamDirty so timer NEVER stalls
                // even during quiet upstream TTFT or reasoning-only pauses inside LazyVStack.
                var clockChanged = false
                if let started = self.thinkingStartedAt {
                    let sec = max(1, Int(Date().timeIntervalSince(started).rounded(.down)) + 1)
                    if self.streamBuffer.liveElapsedSeconds != sec {
                        self.streamBuffer.liveElapsedSeconds = sec
                        clockChanged = true
                    }
                }

                if self.streamDirty {
                    self.streamDirty = false
                    if self.pendingFirstRenderMs == nil,
                       !self.pendingAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let started = self.generationStartedAt {
                        self.pendingFirstRenderMs = max(1, Int(Date().timeIntervalSince(started) * 1000))
                    }
                    let answerChanged = self.streamBuffer.answer.utf8.count != self.pendingAnswer.utf8.count
                    self.streamBuffer.reasoning = self.pendingReasoning
                    self.streamBuffer.answer = self.pendingAnswer
                    self.streamBuffer.reasoningSeconds = self.pendingReasoningSeconds
                    self.streamBuffer.agentSteps = self.pendingAgentSteps
                    self.streamBuffer.activeAgentPhase = self.pendingActiveAgentPhase
                    self.streamBuffer.inlineStatusKind = self.pendingInlineStatusKind
                    self.streamBuffer.inlineStatusText = self.pendingInlineStatusText
                    self.streamBuffer.inlineIntroLead = self.pendingIntroLead
                    self.streamBuffer.liveWebCitations = self.pendingWebCitations
                    self.streamBuffer.liveAgentCitations = self.pendingAgentCitations
                    self.streamBuffer.liveToolFailures = self.pendingToolFailures
                    self.streamBuffer.tick &+= 1
                    if answerChanged { self.streamBuffer.answerLayoutChanges.send() }
                } else if clockChanged {
                    self.streamBuffer.tick &+= 1
                }
            }
        }
    }

    private func finishGeneration(
        conversationID: UUID,
        turnID: UUID,
        state: WuMindTurn.State,
        stopPressedAt: Date? = nil
    ) {
        guard activeTurnID == turnID else { return }
        resolveSearchContinuation(turnID: turnID, choice: .cancel)
        flushTimerTask?.cancel()
        flushTimerTask = nil

        #if DEBUG
        if let probe = streamBenchmark {
            streamBenchmarkResult = probe.finish(firstBodyMs: pendingFirstRenderMs, bytes: pendingAnswer.utf8.count)
            streamBenchmark = nil
        }
        #endif
        let finalReasoning = pendingReasoning
        let finalAnswer = pendingAnswer
        let finalSteps = pendingAgentSteps
        let finalWebCitations = pendingWebCitations
        let finalAgentCitations = pendingAgentCitations
        let finalToolFailures = pendingToolFailures
        let finalIntroLead = pendingIntroLead
        let elapsed = pendingReasoningSeconds ?? thinkingStartedAt.map { Date().timeIntervalSince($0) }
        let finalTTFT = pendingFirstTokenMs
        let finalFirstRender = pendingFirstRenderMs
        let finalTotalMs = generationStartedAt.map { max(1, Int(Date().timeIntervalSince($0) * 1000)) }
        let finalStopLatencyMs = stopPressedAt.map { max(1, Int(Date().timeIntervalSince($0) * 1000)) }

        var finalizedTrace = pendingCallTrace
        finalizedTrace?.timing.upstreamTTFTMs = finalTTFT
        finalizedTrace?.timing.firstRenderMs = finalFirstRender
        finalizedTrace?.timing.totalMs = finalTotalMs
        finalizedTrace?.timing.stopLatencyMs = finalStopLatencyMs
        finalizedTrace?.succeeded = (state == .complete)
        if !finalReasoning.isEmpty { finalizedTrace?.reasoningObserved = true }
        if let finalizedTrace {
            recentCallTraces.insert(finalizedTrace, at: 0)
            if recentCallTraces.count > 30 {
                recentCallTraces = Array(recentCallTraces.prefix(30))
            }
        }
        if let deferredBal = pendingDeferredBalanceYuan {
            managedBalanceYuan = deferredBal
        }

        let anyStepFailed = finalSteps.contains(where: { !$0.succeeded })
        let hasToolFailure = anyStepFailed || WuMindToolTruthfulnessPolicy.hasAnyToolFailure(
            agentCitations: finalAgentCitations,
            failureNotices: finalToolFailures
        )

        // Commit final buffered text, citations, trace & failure notices to the conversation turn ONCE
        mutateTurn(conversationID: conversationID, turnID: turnID, persist: false) { item in
            if !finalReasoning.isEmpty {
                item.reasoning = finalReasoning
            }
            if !item.reasoning.isEmpty && item.reasoningSeconds == nil {
                item.reasoningSeconds = elapsed
            }
            if !finalAnswer.isEmpty {
                item.answer = finalAnswer
            }
            if !finalSteps.isEmpty {
                item.agentSteps = finalSteps
            }
            if !finalWebCitations.isEmpty {
                item.webCitations = finalWebCitations
            }
            if !finalAgentCitations.isEmpty {
                item.agentCitations = finalAgentCitations
            }
            if !finalToolFailures.isEmpty {
                item.toolFailureNotices = finalToolFailures
            }
            if let finalIntroLead, !finalIntroLead.isEmpty {
                item.assistantIntroLead = finalIntroLead
            }
            if let finalTTFT {
                item.firstTokenMs = finalTTFT
            }
            if let finalTotalMs {
                item.totalLatencyMs = finalTotalMs
            }
            if let finalizedTrace {
                item.callTrace = finalizedTrace
            }
            if state == .complete {
                // Strict Failure Honesty: if ANY search or agent step failed, NEVER mark "能力已验证"!
                if hasToolFailure {
                    item.modelCapabilityBadge = nil
                } else {
                    let usedAdvanced = !finalSteps.isEmpty || (item.attachmentNames?.isEmpty == false)
                    item.modelCapabilityBadge = usedAdvanced ? "能力已验证" : "文字已通过"
                }
            }
            item.state = state
        }

        let convoTitle = conversations.first(where: { $0.id == conversationID })?.title ?? "WUMIND"
        activeTurnID = nil
        activeGenerationConversationID = nil
        activeGenerationTask = nil
        thinkingStartedAt = nil
        generationStartedAt = nil
        compactingContext = false
        pendingReasoning = ""
        pendingAnswer = ""
        pendingReasoningSeconds = nil
        pendingFirstTokenMs = nil
        pendingFirstRenderMs = nil
        pendingCallTrace = nil
        pendingDeferredBalanceYuan = nil
        pendingAgentSteps = []
        pendingActiveAgentPhase = nil
        pendingInlineStatusKind = nil
        pendingInlineStatusText = nil
        pendingIntroLead = nil
        pendingWebCitations = []
        pendingAgentCitations = []
        pendingToolFailures = []
        streamDirty = false
        streamBuffer.reset()

        saveNow()
        if state == .complete && preferences.backgroundNotificationsEnabled && UIApplication.shared.applicationState != .active {
            postBackgroundCompletionNotification(title: convoTitle, preview: finalAnswer)
        }
        endBackgroundExecution()
    }

    private func beginBackgroundExecution() {
        endBackgroundExecution()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "WUMIND.StreamGeneration") { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleBackgroundTimeExpiring()
            }
        }
    }

    private func handleBackgroundTimeExpiring() {
        // Persist whatever has been generated so far before iOS suspends the process.
        saveNow()
        endBackgroundExecution()
    }

    private func endBackgroundExecution() {
        guard backgroundTaskID != .invalid else { return }
        let taskID = backgroundTaskID
        backgroundTaskID = .invalid
        UIApplication.shared.endBackgroundTask(taskID)
    }

    private func postBackgroundCompletionNotification(title: String, preview: String) {
        let cleanPreview = preview
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyText = cleanPreview.isEmpty
            ? "回复已生成，回到 WUMIND 查看。"
            : String(cleanPreview.prefix(64)) + (cleanPreview.count > 64 ? "…" : "")
        let notifTitle = "WUMIND · \(title)"
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            let content = UNMutableNotificationContent()
            content.title = notifTitle
            content.body = bodyText
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "wumind.bg.done.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func runSemanticCompaction(
        existingSummary: String?,
        turnsToCompact: [WuMindContextEngine.TurnSnapshot],
        channel: WuMindChannel,
        provider: WuMindProvider,
        modelID: String,
        apiKey: String?
    ) async -> String {
        let instruction = WuMindContextEngine.compactionInstruction(
            existingSummary: existingSummary,
            turnsToCompact: turnsToCompact
        )
        let fallback = WuMindContextEngine.localCompact(
            existingSummary: existingSummary,
            turnsToCompact: turnsToCompact
        )

        do {
            if channel == .managed, hasGatewayURL {
                let userToken = try await ensureManagedAccount()
                var collected = ""
                for try await event in WuMindGatewayClient().streamChat(
                    gatewayURL: gatewayBaseURL,
                    userToken: userToken,
                    modelID: modelID,
                    messages: [.init(role: .user, text: instruction)],
                    systemPrompt: "你是高精度对话上下文压缩引擎，只输出压缩后的结构化记忆摘要。",
                    deepThinking: false
                ) {
                    if case .content(let delta) = event {
                        collected += delta
                    }
                }
                let clean = collected.trimmingCharacters(in: .whitespacesAndNewlines)
                return clean.isEmpty ? fallback : clean
            }

            if let key = apiKey, !key.isEmpty {
                if provider == .deepSeek {
                    var collected = ""
                    for try await event in DeepSeekChatClient.streamEvents(
                        messages: [.init(role: .user, content: instruction)],
                        apiKey: key,
                        model: .flash,
                        thinking: .normal,
                        systemPrompt: "你是高精度对话上下文压缩引擎，只输出压缩后的结构化记忆摘要。",
                        extendedContext: true
                    ) {
                        if case .content(let delta) = event {
                            collected += delta
                        }
                    }
                    let clean = collected.trimmingCharacters(in: .whitespacesAndNewlines)
                    return clean.isEmpty ? fallback : clean
                } else if let mp = provider.multiProvider, !modelID.isEmpty {
                    let reply = try await MultiProviderAIClient().sendDetailed(
                        provider: mp,
                        model: AIProviderModel(id: modelID, displayName: modelID, supportsTextChat: true),
                        apiKey: key,
                        messages: [.init(role: .user, text: instruction)],
                        deepThinking: false,
                        baseURL: AIProviderEndpoints.baseURL(for: mp),
                        systemPrompt: "你是高精度对话上下文压缩引擎，只输出压缩后的结构化记忆摘要。"
                    )
                    let clean = reply.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                    return clean.isEmpty ? fallback : clean
                }
            }
        } catch {
            // Fall through smoothly to deterministic local compaction so chat never blocks.
        }
        return fallback
    }

    private func prepareContextTurnsAndAutoCompact(
        conversationID: UUID,
        priorTurns: [WuMindTurn],
        outgoingPrompt: String,
        channel: WuMindChannel,
        provider: WuMindProvider,
        modelID: String,
        apiKey: String?
    ) async -> (verbatimTurns: [WuMindContextEngine.TurnSnapshot], maxBytes: Int) {
        let completeSnapshots = priorTurns
            .filter { $0.state == .complete && !$0.answer.isEmpty }
            .map { WuMindContextEngine.TurnSnapshot(question: $0.question, answer: $0.answer) }
        let convo = conversations.first(where: { $0.id == conversationID })
        let windowTokens = WuMindContextEngine.supportedWindowTokens(
            provider: provider.rawValue,
            modelID: modelID,
            preferredCap: maxContextTokens
        )
        let plan = WuMindContextEngine.planContext(
            turns: completeSnapshots,
            existingSummary: convo?.compactedSummary,
            compactedTurnCount: convo?.safeCompactedTurnCount ?? 0,
            pendingPrompt: outgoingPrompt,
            systemPrompt: composedSystemPrompt(conversationID: conversationID),
            maxWindowTokens: windowTokens,
            autoCompactRatio: preferences.autoCompactRatio
        )
        let maxBytes = min(windowTokens * 3, 3_600_000)

        if autoCompactContext && plan.needsCompaction && !plan.turnsToCompact.isEmpty {
            compactingContext = true
            let summary = await runSemanticCompaction(
                existingSummary: convo?.compactedSummary,
                turnsToCompact: plan.turnsToCompact,
                channel: channel,
                provider: provider,
                modelID: modelID,
                apiKey: apiKey
            )
            updateCompaction(
                conversationID: conversationID,
                summary: summary,
                compactedTurnCount: plan.newCompactedTurnCount
            )
            compactingContext = false
            return (plan.verbatimTurns, maxBytes)
        }
        return (plan.verbatimTurns, maxBytes)
    }

    private static func buildMultiProviderContext(
        verbatimTurns: [WuMindContextEngine.TurnSnapshot],
        prompt: String,
        images: [AIProviderMessage.ImageAttachment] = [],
        maxBytes: Int
    ) -> [AIProviderMessage] {
        var remaining = max(0, maxBytes - prompt.utf8.count)
        var reversedPairs: [AIProviderMessage] = []
        for turn in verbatimTurns.lazy.reversed().prefix(118) {
            let cost = turn.question.utf8.count + turn.answer.utf8.count
            guard cost <= remaining else { break }
            remaining -= cost
            reversedPairs.append(.init(role: .assistant, text: turn.answer))
            reversedPairs.append(.init(role: .user, text: turn.question))
        }
        return Array(reversedPairs.reversed()) + [.init(role: .user, text: prompt, images: images)]
    }

    // MARK: - Cross-Device Zero-Knowledge Encrypted Cloud Sync, Pairing & Cloud Cron Pull

    private struct SyncVaultPayload: Codable {
        var exportedAt: Date
        var conversations: [WuMindConversation]
        var projects: [WuMindProject]
        var memories: [WuMindMemoryItem]
        var preferences: WuMindPreferences
        var customSkills: [WuMindSkill]
        var scheduledTasks: [WuMindScheduledTask]
        var installedConnectorIDs: [String]
    }

    func exportEncryptedBackupEnvelope(passphrase: String) throws -> String {
        let activeBatch = Array(activeConversations.prefix(60))
        let archivedBatch = Array(archivedConversations.prefix(60))
        let vault = SyncVaultPayload(
            exportedAt: Date(),
            conversations: activeBatch + archivedBatch,
            projects: projects,
            memories: memories,
            preferences: preferences,
            customSkills: customSkills,
            scheduledTasks: scheduledTasks,
            installedConnectorIDs: Array(installedConnectorIDs).sorted()
        )
        let data = try JSONEncoder().encode(vault)
        return try WuMindSyncCrypto.encrypt(data, passphrase: passphrase)
    }

    @discardableResult
    func importEncryptedBackupEnvelope(_ envelope: String, passphrase: String) throws -> Int {
        let plaintext = try WuMindSyncCrypto.decrypt(envelope, passphrase: passphrase)
        let vault = try JSONDecoder().decode(SyncVaultPayload.self, from: plaintext)

        // Non-destructive merge by ID: content follows newest updatedAt/turns, archive state follows newest archiveStateUpdatedAt.
        var addedOrUpdated = 0
        for incoming in vault.conversations {
            if let idx = conversations.firstIndex(where: { $0.id == incoming.id }) {
                let local = conversations[idx]
                let decision = WuMindConversationArchivePolicy.resolveMerge(
                    localUpdatedAt: local.updatedAt,
                    localTurnCount: local.turns.count,
                    localIsArchived: local.isArchived,
                    localArchivedAt: local.archivedAt,
                    localArchiveStateUpdatedAt: local.archiveStateUpdatedAt,
                    incomingUpdatedAt: incoming.updatedAt,
                    incomingTurnCount: incoming.turns.count,
                    incomingIsArchived: incoming.isArchived,
                    incomingArchivedAt: incoming.archivedAt,
                    incomingArchiveStateUpdatedAt: incoming.archiveStateUpdatedAt
                )
                var merged = decision.preferIncomingContent ? incoming : local
                // Union attachments so neither side drops shared thread materials
                let existingMats = merged.sharedMaterials ?? []
                let otherMats = (decision.preferIncomingContent ? local.sharedMaterials : incoming.sharedMaterials) ?? []
                if !otherMats.isEmpty {
                    let existingIDs = Set(existingMats.map(\.id))
                    let combined = existingMats + otherMats.filter { !existingIDs.contains($0.id) }
                    merged.sharedMaterials = combined.isEmpty ? nil : combined
                }
                merged.isArchived = decision.isArchived
                merged.archivedAt = decision.archivedAt
                merged.archiveStateUpdatedAt = decision.archiveStateUpdatedAt
                if merged != local {
                    conversations[idx] = merged
                    if merged.isArchived && activeConversationID == merged.id {
                        activeConversationID = nil
                    }
                    addedOrUpdated += 1
                }
            } else {
                conversations.append(incoming)
                addedOrUpdated += 1
            }
        }
        if conversations.count > maxStoredConversations {
            conversations = Array(sortedConversations.prefix(maxStoredConversations))
        }

        for incomingProj in vault.projects {
            if let idx = projects.firstIndex(where: { $0.id == incomingProj.id }) {
                if incomingProj.updatedAt > projects[idx].updatedAt {
                    projects[idx] = incomingProj
                    addedOrUpdated += 1
                }
            } else {
                projects.append(incomingProj)
                addedOrUpdated += 1
            }
        }

        for mem in vault.memories where !memories.contains(where: { $0.id == mem.id || $0.content == mem.content }) {
            memories.append(mem)
            addedOrUpdated += 1
        }
        for skill in vault.customSkills where !customSkills.contains(where: { $0.id == skill.id }) {
            customSkills.append(skill)
            addedOrUpdated += 1
        }
        for sched in vault.scheduledTasks {
            if let idx = scheduledTasks.firstIndex(where: { $0.id == sched.id }) {
                if (sched.lastRunAt ?? .distantPast) > (scheduledTasks[idx].lastRunAt ?? .distantPast) {
                    scheduledTasks[idx] = sched
                    addedOrUpdated += 1
                }
            } else {
                scheduledTasks.append(sched)
                addedOrUpdated += 1
            }
        }
        installedConnectorIDs.formUnion(vault.installedConnectorIDs)
        if preferences.userDisplayName.isEmpty && !vault.preferences.userDisplayName.isEmpty {
            preferences = vault.preferences
        }
        saveNow()
        return addedOrUpdated
    }

    func pushEncryptedCloudSync(passphrase: String) async throws -> WuMindCloudSyncAck {
        guard hasGatewayURL else { throw WuMindGatewayClient.GatewayError.invalidGatewayURL }
        isSyncingCloud = true
        defer { isSyncingCloud = false }
        let token = try await ensureManagedAccount()
        let encrypted = try exportEncryptedBackupEnvelope(passphrase: passphrase)
        let nextVersion = cloudSyncVersion + 1
        let devName = UIDevice.current.name
        let ack = try await WuMindGatewayClient().pushCloudSyncSnapshot(
            gatewayURL: gatewayBaseURL,
            userToken: token,
            encryptedPayload: encrypted,
            version: nextVersion,
            deviceName: devName
        )
        cloudSyncVersion = ack.version
        lastCloudSyncAt = Date()
        lastCloudSyncDevice = devName
        return ack
    }

    @discardableResult
    func pullEncryptedCloudSync(passphrase: String) async throws -> Int {
        guard hasGatewayURL else { throw WuMindGatewayClient.GatewayError.invalidGatewayURL }
        isSyncingCloud = true
        defer { isSyncingCloud = false }
        let token = try await ensureManagedAccount()
        let env = try await WuMindGatewayClient().pullCloudSyncSnapshot(gatewayURL: gatewayBaseURL, userToken: token)
        guard env.hasSnapshot, let payload = env.encryptedPayload, !payload.isEmpty else {
            return 0
        }
        let merged = try importEncryptedBackupEnvelope(payload, passphrase: passphrase)
        cloudSyncVersion = max(cloudSyncVersion, env.version)
        lastCloudSyncAt = Date()
        lastCloudSyncDevice = env.deviceName
        return merged
    }

    func createDevicePairingCode() async throws -> WuMindSyncPairingCode {
        let token = try await ensureManagedAccount()
        return try await WuMindGatewayClient().createPairingCode(gatewayURL: gatewayBaseURL, userToken: token)
    }

    func claimDevicePairingCode(_ code: String) async throws -> WuMindRegistration {
        guard hasGatewayURL else { throw WuMindGatewayClient.GatewayError.invalidGatewayURL }
        let reg = try await WuMindGatewayClient().claimPairingCode(gatewayURL: gatewayBaseURL, code: code)
        guard Keychain.setWuMindGatewayUserToken(reg.userToken) else {
            throw WuMindGatewayClient.GatewayError.unauthorized
        }
        managedAccountID = reg.userID
        managedBalanceYuan = reg.balanceYuan
        scheduleSave()
        try? await refreshManagedAccount()
        return reg
    }

    /// Pulls Cloudflare Cron scheduled task state and independent `schedule_runs` records from `/v1/schedules`,
    /// syncing status/nextRunBeijingText and materializing each new execution into local history cleanly without duplicates.
    @discardableResult
    func pullCloudCronResults() async throws -> Int {
        guard hasGatewayURL else { return 0 }
        let token = try await ensureManagedAccount()
        let remote = try await WuMindGatewayClient().fetchCloudSchedules(gatewayURL: gatewayBaseURL, userToken: token)
        var imported = 0
        var stateChanged = false

        for rec in remote {
            if let idx = scheduledTasks.firstIndex(where: { $0.id.uuidString == rec.id }) {
                scheduledTasks[idx].cloudSynced = true
                scheduledTasks[idx].serverConfirmed = true
                scheduledTasks[idx].syncError = nil
                scheduledTasks[idx].serverStatus = rec.status
                scheduledTasks[idx].enabled = rec.enabled
                scheduledTasks[idx].nextRunAt = rec.nextRunEpoch > 0 ? Date(timeIntervalSince1970: TimeInterval(rec.nextRunEpoch)) : nil
                if !rec.nextRunBeijingText.isEmpty {
                    scheduledTasks[idx].nextRunBeijingText = rec.nextRunBeijingText
                }
                if let lastStatusRaw = rec.lastRunStatus,
                   let parsedStatus = WuMindScheduleRunStatus(rawValue: lastStatusRaw) {
                    if let err = rec.lastError, !err.isEmpty {
                        scheduledTasks[idx].lastStatus = "\(parsedStatus.badgeLabel)：\(err)"
                    } else {
                        scheduledTasks[idx].lastStatus = parsedStatus.badgeLabel
                    }
                }
                stateChanged = true

                // Sync each independent server run record (deduped by idempotencyKey)
                for run in rec.runs.reversed() {
                    if scheduledTasks[idx].runs.contains(where: { $0.idempotencyKey == run.idempotencyKey }) {
                        continue
                    }
                    let parsedStatus = WuMindScheduleRunStatus(rawValue: run.status) ?? .aiCompleted
                    let parsedMode = WuMindScheduleExecutionMode(rawValue: run.executionMode) ?? .aiRun
                    var linkedConvoID: UUID? = nil

                    if let ans = run.answerText?.trimmingCharacters(in: .whitespacesAndNewlines), !ans.isEmpty {
                        let convo = WuMindConversation(
                            title: parsedStatus == .reminderSent ? "⏰ \(rec.title)" : "☁️ ⏰ \(rec.title)",
                            provider: .deepSeek,
                            modelID: run.modelID.isEmpty ? rec.modelID : run.modelID,
                            modelDisplayName: parsedStatus == .reminderSent ? "仅到点提醒" : (run.modelID.isEmpty ? rec.modelID : run.modelID),
                            deepThinking: false
                        )
                        let turn = WuMindTurn(
                            question: rec.prompt,
                            answer: ans,
                            modelLabel: "\(parsedStatus.badgeLabel)（\(run.executedAt)）",
                            provider: .deepSeek,
                            isDeepThinking: false,
                            state: .complete,
                            costYuan: run.costYuan > 0 ? run.costYuan : nil
                        )
                        var fullConvo = convo
                        fullConvo.turns = [turn]
                        conversations.insert(fullConvo, at: 0)
                        linkedConvoID = fullConvo.id
                        scheduledTasks[idx].lastConversationID = fullConvo.id
                    }

                    let localRun = WuMindScheduleRunRecord(
                        id: run.id,
                        idempotencyKey: run.idempotencyKey,
                        executedAtText: run.executedAt,
                        status: parsedStatus,
                        executionMode: parsedMode,
                        modelID: run.modelID,
                        costYuan: run.costYuan,
                        failureReason: run.failureReason,
                        answerPreview: run.answerText.map { String($0.prefix(160)) },
                        conversationID: linkedConvoID
                    )
                    scheduledTasks[idx].runs.insert(localRun, at: 0)
                    if scheduledTasks[idx].runs.count > 20 {
                        scheduledTasks[idx].runs = Array(scheduledTasks[idx].runs.prefix(20))
                    }
                    if run.costYuan > 0 {
                        scheduledTasks[idx].lastCostYuan = run.costYuan
                    }
                    imported += 1
                }
            }
        }
        if imported > 0 || stateChanged { saveNow() }
        return imported
    }

    func createManagedPaymentOrder(amountYuan: Double, channel: String) async throws -> WuMindPaymentOrder {
        let token = try await ensureManagedAccount()
        let order = try await WuMindGatewayClient().createPaymentOrder(
            gatewayURL: gatewayBaseURL,
            userToken: token,
            amountYuan: amountYuan,
            channel: channel
        )
        managedPaymentOrders.insert(order, at: 0)
        return order
    }

    func refreshManagedPaymentOrders() async throws {
        let token = try await ensureManagedAccount()
        managedPaymentOrders = try await WuMindGatewayClient().fetchPaymentOrders(
            gatewayURL: gatewayBaseURL,
            userToken: token
        )
    }

    func checkManagedPaymentOrderStatus(_ orderID: String) async throws -> WuMindPaymentOrderStatus {
        let token = try await ensureManagedAccount()
        let result = try await WuMindGatewayClient().fetchPaymentOrderStatus(
            gatewayURL: gatewayBaseURL,
            userToken: token,
            orderID: orderID
        )
        managedBalanceYuan = result.balanceYuan
        if let idx = managedPaymentOrders.firstIndex(where: { $0.id == orderID }) {
            let old = managedPaymentOrders[idx]
            managedPaymentOrders[idx] = WuMindPaymentOrder(
                id: old.id,
                amountYuan: result.amountYuan,
                channel: result.channel,
                status: result.status,
                note: result.isPaid ? "已自动到账" : old.note,
                checkoutURL: old.checkoutURL,
                createdAt: old.createdAt,
                paidAt: result.paidAt ?? old.paidAt
            )
        }
        if result.isPaid {
            try? await refreshManagedAccount()
        }
        return result
    }

    // MARK: - Per-Account Isolated Persistence & Account Switching

    private static func baseFolderURL(create: Bool) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: create)
        var folder = root.appendingPathComponent("WuMindLocal", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
        }
        return folder
    }

    private static func legacySharedStorageURL(create: Bool) throws -> URL {
        try baseFolderURL(create: create).appendingPathComponent("conversations.json")
    }

    private static func settingsURL(create: Bool) throws -> URL {
        try baseFolderURL(create: create).appendingPathComponent("settings.json")
    }

    private static func accountStorageURL(ownerID: String, create: Bool) throws -> URL {
        let base = try baseFolderURL(create: create)
        let url = WuMindAccountStorageScope.conversationsFileURL(baseFolder: base, ownerID: ownerID)
        if create {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        return url
    }

    /// Cancels any active generation and wipes ALL in-memory private chat, project, memory,
    /// attachment, and stream buffer state before reloading the active account's isolated store.
    func reloadForCurrentAccount() {
        let targetOwner = currentStorageOwnerID
        saveTask?.cancel()
        saveTask = nil
        clearInMemoryPrivateState()
        activeStorageOwnerID = targetOwner
        loadAccountPrivateState(for: targetOwner)
        WuMindWorksStore.shared.reloadForCurrentAccount()
    }

    /// Signs out the current WUMIND account on a shared device (e.g. office iPad):
    /// flushes current account data to its own isolated file, wipes credentials and ALL in-memory
    /// conversations/projects/attachments/memories, and switches cleanly to a fresh empty scope.
    func signOutCurrentAccount() {
        saveNow()
        clearInMemoryPrivateState()
        _ = Keychain.setWuMindGatewayUserToken("")
        managedAccountID = ""
        managedBalanceYuan = nil
        managedAccountStatus = nil
        managedPaymentOrders = []
        registeredDisplayName = ""
        registeredRole = ""
        activeStorageOwnerID = currentStorageOwnerID
        saveSettingsOnly()
        loadAccountPrivateState(for: activeStorageOwnerID)
        WuMindWorksStore.shared.reloadForCurrentAccount()
    }

    private func clearInMemoryPrivateState() {
        activeGenerationTask?.cancel()
        if let pending = searchContinuationPrompt {
            resolveSearchContinuation(turnID: pending.turnID, choice: .cancel)
        }
        activeGenerationTask = nil
        flushTimerTask?.cancel()
        flushTimerTask = nil
        endBackgroundExecution()
        AIImageStudioSessionStore.shared.resetForAccountSwitch()
        AIVideoStudioSessionStore.shared.resetForAccountSwitch()

        conversations = []
        activeConversationID = nil
        projects = []
        activeProjectID = nil
        memories = []
        scheduledTasks = []
        customSkills = []
        activeSkillID = nil
        pendingAttachments = []
        attachedGitHubContext = nil
        activeTurnID = nil
        activeGenerationConversationID = nil
        thinkingStartedAt = nil
        generationStartedAt = nil
        compactingContext = false
        pendingReasoning = ""
        pendingAnswer = ""
        pendingReasoningSeconds = nil
        pendingFirstTokenMs = nil
        pendingFirstRenderMs = nil
        pendingCallTrace = nil
        pendingDeferredBalanceYuan = nil
        recentCallTraces = []
        pendingAgentSteps = []
        pendingActiveAgentPhase = nil
        pendingInlineStatusKind = nil
        pendingInlineStatusText = nil
        pendingIntroLead = nil
        pendingWebCitations = []
        pendingAgentCitations = []
        pendingToolFailures = []
        streamDirty = false
        streamBuffer.reset()
        lastCloudSyncAt = nil
        cloudSyncVersion = 0
        lastCloudSyncDevice = nil
    }

    private func applySettings(from snapshot: WuMindDiskSnapshot) {
        var restoredModels: [WuMindProvider: [WuMindModelOption]] = [
            .deepSeek: WuMindModelOption.deepSeekDefaults
        ]
        for (raw, list) in snapshot.cachedModels {
            if let provider = WuMindProvider(rawValue: raw), provider != .deepSeek {
                restoredModels[provider] = list
            }
        }
        cachedModels = restoredModels
        selectedProvider = snapshot.lastProvider
        selectedModelID = snapshot.lastModelID
        selectedModelName = snapshot.lastModelName
        deepThinking = snapshot.lastDeepThinking
        consentedProviders = Set(snapshot.consentedProviders)
        channel = snapshot.channel ?? .ownAPI
        gatewayBaseURL = (try? WuMindGatewayConfiguration.address(snapshot.gatewayBaseURL ?? "")) ?? ""
        managedAccountID = snapshot.managedAccountID ?? ""
        managedBalanceYuan = snapshot.managedBalanceYuan
        managedSelectedModelID = snapshot.managedSelectedModelID ?? "deepseek-reasoner"
        if let cfg = snapshot.managedConfig, !cfg.pricing.isEmpty {
            managedConfig = cfg
        }
        if let savedMax = snapshot.maxContextTokens {
            maxContextTokens = min(WuMindContextEngine.maxSupportedContextTokens, max(32_000, savedMax))
        }
        autoCompactContext = snapshot.autoCompactContext ?? true
        if let savedConnectors = snapshot.installedConnectorIDs {
            installedConnectorIDs = Set(savedConnectors)
        }
        connectorEndpoints = snapshot.connectorEndpoints ?? [:]
        if let prefs = snapshot.preferences {
            preferences = prefs
        }
        agentModeEnabled = snapshot.agentModeEnabled ?? preferences.agentEnabledByDefault
        providerVerifications = snapshot.providerVerifications ?? [:]
        modelSmokeRecords = snapshot.modelSmokeRecords ?? [:]
        registeredDisplayName = snapshot.registeredDisplayName ?? ""
        registeredRole = snapshot.registeredRole ?? ""
        if let savedCatalog = snapshot.managedCatalogModels, !savedCatalog.isEmpty {
            managedCatalogModels = savedCatalog
        }
    }

    private func loadAccountPrivateState(for ownerID: String) {
        // Ensure any queued background disk write finishes before reading on account switch/reload.
        saveIOQueue.sync {}
        guard let url = try? Self.accountStorageURL(ownerID: ownerID, create: false),
              let data = try? Data(contentsOf: url),
              let priv = try? JSONDecoder().decode(WuMindAccountPrivateSnapshot.self, from: data) else {
            return
        }
        conversations = priv.conversations
        projects = priv.projects
        activeProjectID = priv.activeProjectID
        memories = priv.memories
        scheduledTasks = priv.scheduledTasks
        customSkills = priv.customSkills
        activeSkillID = priv.activeSkillID
    }

    private func load() {
        // 1. Load device-level settings from settings.json if present
        if let sURL = try? Self.settingsURL(create: false),
           let sData = try? Data(contentsOf: sURL),
           let sSnap = try? JSONDecoder().decode(WuMindDiskSnapshot.self, from: sData) {
            applySettings(from: sSnap)
            let owner = currentStorageOwnerID
            activeStorageOwnerID = owner
            loadAccountPrivateState(for: owner)
            return
        }

        // 2. One-time safe migration from legacy single-file conversations.json into original owner's isolated folder
        guard let legacyURL = try? Self.legacySharedStorageURL(create: false),
              let data = try? Data(contentsOf: legacyURL),
              let legacy = try? JSONDecoder().decode(WuMindDiskSnapshot.self, from: data) else {
            activeStorageOwnerID = currentStorageOwnerID
            return
        }
        applySettings(from: legacy)
        let owner = currentStorageOwnerID
        activeStorageOwnerID = owner
        conversations = legacy.conversations
        projects = legacy.projects ?? []
        activeProjectID = legacy.activeProjectID
        memories = legacy.memories ?? []
        scheduledTasks = legacy.scheduledTasks ?? []
        customSkills = legacy.customSkills ?? []
        activeSkillID = legacy.activeSkillID

        // Do not remove the only legacy copy after a failed migration write.
        saveNow(migratingLegacyURL: legacyURL)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func makeSettingsSnapshot(gatewayURLOverride: String? = nil) -> WuMindDiskSnapshot {
        var encodedCache: [String: [WuMindModelOption]] = [:]
        for (provider, list) in cachedModels where provider != .deepSeek {
            encodedCache[provider.rawValue] = list
        }
        // Device settings file intentionally stores ZERO conversations, projects, memories, or private skills!
        return WuMindDiskSnapshot(
            conversations: [],
            cachedModels: encodedCache,
            lastProvider: selectedProvider,
            lastModelID: selectedModelID,
            lastModelName: selectedModelName,
            lastDeepThinking: deepThinking,
            consentedProviders: Array(consentedProviders).sorted(),
            customSkills: nil,
            activeSkillID: nil,
            channel: channel,
            gatewayBaseURL: gatewayURLOverride ?? gatewayBaseURL,
            managedAccountID: managedAccountID,
            managedBalanceYuan: managedBalanceYuan,
            managedSelectedModelID: managedSelectedModelID,
            managedConfig: managedConfig,
            maxContextTokens: maxContextTokens,
            autoCompactContext: autoCompactContext,
            projects: nil,
            activeProjectID: nil,
            installedConnectorIDs: Array(installedConnectorIDs).sorted(),
            connectorEndpoints: connectorEndpoints,
            scheduledTasks: nil,
            memories: nil,
            preferences: preferences,
            agentModeEnabled: agentModeEnabled,
            providerVerifications: providerVerifications,
            modelSmokeRecords: modelSmokeRecords,
            registeredDisplayName: registeredDisplayName,
            registeredRole: registeredRole,
            managedCatalogModels: managedCatalogModels
        )
    }

    private func saveSettingsOnly() {
        let settingsSnap = makeSettingsSnapshot()
        guard let sURL = try? Self.settingsURL(create: true) else { return }
        saveIOQueue.async {
            if let sData = try? JSONEncoder().encode(settingsSnap) {
                try? sData.write(to: sURL, options: [.atomic, .completeFileProtection])
            }
        }
    }

    private func saveNow(migratingLegacyURL: URL? = nil) {
        if migratingLegacyURL == nil { saveSettingsOnly() }

        // Snapshot in-flight streaming buffers to disk safely without mutating `@Published conversations`.
        var conversationsToSave = conversations
        if let cID = activeGenerationConversationID,
           let tID = activeTurnID,
           let cIdx = conversationsToSave.firstIndex(where: { $0.id == cID }),
           let tIdx = conversationsToSave[cIdx].turns.firstIndex(where: { $0.id == tID }) {
            if !pendingReasoning.isEmpty {
                conversationsToSave[cIdx].turns[tIdx].reasoning = pendingReasoning
            }
            if !pendingAnswer.isEmpty {
                conversationsToSave[cIdx].turns[tIdx].answer = pendingAnswer
            }
            if !pendingAgentSteps.isEmpty {
                conversationsToSave[cIdx].turns[tIdx].agentSteps = pendingAgentSteps
            }
            if !pendingWebCitations.isEmpty {
                conversationsToSave[cIdx].turns[tIdx].webCitations = pendingWebCitations
            }
            if !pendingAgentCitations.isEmpty {
                conversationsToSave[cIdx].turns[tIdx].agentCitations = pendingAgentCitations
            }
            if !pendingToolFailures.isEmpty {
                conversationsToSave[cIdx].turns[tIdx].toolFailureNotices = pendingToolFailures
            }
        }
        let owner = activeStorageOwnerID.isEmpty ? currentStorageOwnerID : activeStorageOwnerID
        let privSnap = WuMindAccountPrivateSnapshot(
            conversations: conversationsToSave,
            projects: projects,
            activeProjectID: activeProjectID,
            memories: memories,
            scheduledTasks: scheduledTasks,
            customSkills: customSkills,
            activeSkillID: activeSkillID
        )
        guard let url = try? Self.accountStorageURL(ownerID: owner, create: true) else { return }
        if let legacy = migratingLegacyURL {
            guard let settingsURL = try? Self.settingsURL(create: true) else { return }
            let settingsSnap = makeSettingsSnapshot()
            saveIOQueue.async {
                try? WuMindGatewayConfiguration.finalizeLegacyMigration(
                    writePrivateData: {
                        try JSONEncoder().encode(privSnap).write(to: url, options: [.atomic, .completeFileProtection])
                    },
                    writeSettings: {
                        try JSONEncoder().encode(settingsSnap).write(to: settingsURL, options: [.atomic, .completeFileProtection])
                    },
                    removeLegacy: { try FileManager.default.removeItem(at: legacy) }
                )
            }
            return
        }
        // Encode and write off MainActor on a dedicated serial queue so long chat histories NEVER hitch UI/scrolling.
        saveIOQueue.async {
            if let data = try? JSONEncoder().encode(privSnap) {
                try? data.write(to: url, options: [.atomic, .completeFileProtection])
            }
        }
    }

    // MARK: - Stateless Ephemeral Execution (Temporary Chat / PPT Studio / Gemini Voice)

    /// Executes a completion against the currently selected WUMIND channel & model without mutating
    /// `conversations`, disk snapshots, cloud sync, or long-term `memories`.
    func runStatelessChat(
        messages: [AIProviderMessage],
        systemPrompt: String?,
        deepThinking: Bool = false,
        onReasoningDelta: ((String) -> Void)? = nil,
        onAnswerDelta: ((String) -> Void)? = nil
    ) async throws -> (reasoning: String, answer: String) {
        let activeChannel = channel
        let provider = selectedProvider
        let modelID = activeChannel == .managed ? managedSelectedModelID : selectedModelID

        if activeChannel == .managed {
            guard hasGatewayURL else { throw WuMindGatewayClient.GatewayError.invalidGatewayURL }
            guard let token = Keychain.wumindGatewayUserToken, !token.isEmpty else {
                throw WuMindGatewayClient.GatewayError.unauthorized
            }
            var reasoning = ""
            var answer = ""
            for try await event in WuMindGatewayClient().streamChat(
                gatewayURL: gatewayBaseURL,
                userToken: token,
                modelID: modelID,
                messages: messages,
                systemPrompt: systemPrompt,
                deepThinking: deepThinking,
                sessionTag: "stateless"
            ) {
                try Task.checkCancellation()
                switch event {
                case .trace: break
                case .reasoning(let d):
                    reasoning += d
                    onReasoningDelta?(reasoning)
                case .content(let d):
                    answer += d
                    onAnswerDelta?(answer)
                case .billing(let b):
                    managedBalanceYuan = b.balanceYuan
                case .warning(let warn):
                    if !warn.isEmpty {
                        answer += "\n\n⚠️ \(warn)"
                        onAnswerDelta?(answer)
                    }
                }
            }
            return (reasoning, answer)
        }

        guard let key = provider.apiKey(), !key.isEmpty else {
            throw DeepSeekChatClient.Failure.missingKey
        }

        if provider == .deepSeek {
            let dsModel = DeepSeekChatClient.Model(rawValue: modelID) ?? .pro
            let dsThinking: DeepSeekChatClient.Thinking = deepThinking ? .deep : .normal
            let dsMessages: [DeepSeekChatClient.Message] = messages.map {
                .init(role: $0.role == .assistant ? .assistant : .user, content: $0.text)
            }
            var reasoning = ""
            var answer = ""
            for try await event in DeepSeekChatClient.streamEvents(
                messages: dsMessages,
                apiKey: key,
                model: dsModel,
                thinking: dsThinking,
                systemPrompt: systemPrompt,
                extendedContext: true
            ) {
                try Task.checkCancellation()
                switch event {
                case .reportedModel: break
                case .reasoning(let d):
                    reasoning += d
                    onReasoningDelta?(reasoning)
                case .content(let d):
                    answer += d
                    onAnswerDelta?(answer)
                }
            }
            markModelSmokePassed(.deepSeek, modelID: modelID, host: "api.deepseek.com", endpointPath: "/chat/completions", latencyMs: nil)
            return (reasoning, answer)
        }

        guard let mp = provider.multiProvider else {
            throw DeepSeekChatClient.Failure.network
        }
        let modelObj = AIProviderModel(id: modelID, displayName: modelID, supportsTextChat: true)
        let startedAt = Date()
        do {
            let diagnosed = try await MultiProviderAIClient().sendDetailedDiagnosed(
                provider: mp,
                model: modelObj,
                apiKey: key,
                messages: messages,
                deepThinking: deepThinking,
                baseURL: AIProviderEndpoints.baseURL(for: mp),
                systemPrompt: systemPrompt
            )
            let elapsedMs = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
            markModelSmokePassed(provider, modelID: modelID, host: diagnosed.host, endpointPath: diagnosed.endpointPath, latencyMs: elapsedMs)
            let r = diagnosed.reply.reasoning ?? ""
            let a = diagnosed.reply.answer
            if !r.isEmpty { onReasoningDelta?(r) }
            if !a.isEmpty { onAnswerDelta?(a) }
            return (r, a)
        } catch let diag as AIProviderDiagnosticError {
            markModelSmokeFailed(
                provider,
                modelID: modelID,
                host: diag.host,
                httpStatus: diag.httpStatus,
                errorCode: diag.errorCode,
                detail: diag.sanitizedDetail ?? diag.shortBadgeSummary
            )
            throw diag
        }
    }

    /// Builds multimodal seed context from the active conversation and pending attachments
    /// so full-screen voice can seamlessly follow up on already-uploaded images, PDFs, or chats.
    func voiceSeedContext() -> (
        recentMessages: [AIProviderMessage],
        attachmentSummary: String?,
        nativeImages: [AIProviderMessage.ImageAttachment],
        priorTurnCount: Int,
        attachmentCount: Int
    ) {
        let completed = (activeConversation?.turns ?? []).filter { $0.state == .complete && !$0.answer.isEmpty }
        let tail = Array(completed.suffix(6))
        var msgs: [AIProviderMessage] = []
        for t in tail {
            var qText = t.question
            if let names = t.attachmentNames, !names.isEmpty {
                qText = "[已附带文件：\(names.joined(separator: "、"))]\n" + qText
            }
            msgs.append(AIProviderMessage(role: .user, text: String(qText.prefix(2_400))))
            msgs.append(AIProviderMessage(role: .assistant, text: String(t.answer.prefix(3_000))))
        }
        let items = pendingAttachments
        var docBlocks: [String] = []
        var images: [AIProviderMessage.ImageAttachment] = []
        for item in items {
            let doc = item.document
            if let img = doc.makeAIImageAttachment() {
                images.append(img)
            }
            let body = String(doc.extractedText.prefix(3_000))
            docBlocks.append("【当前对话框已附加文件：\(doc.filename)（\(doc.summaryBadge)）】\n\(body)")
        }
        let summary = docBlocks.isEmpty ? nil : docBlocks.joined(separator: "\n\n")
        return (msgs, summary, images, tail.count, items.count)
    }

    /// Commits a completed full-screen Gemini Live Voice Q&A turn into the active conversation
    /// so the user can seamlessly continue typing, uploading files, or asking follow-up questions.
    func appendCompletedVoiceExchange(question: String, answer: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !a.isEmpty else { return }
        let convoID = ensureActiveConversation(initialPrompt: q)
        let attachedNames = pendingAttachments.isEmpty ? nil : pendingAttachments.map(\.document.filename)
        var turn = WuMindTurn(
            id: UUID(),
            question: q,
            modelLabel: "\(activeModelDisplayName) · 语音",
            provider: activeProviderForDisplay,
            isDeepThinking: false,
            state: .complete,
            attachmentNames: attachedNames,
            actualChannelLabel: activeDataDestinationLabel
        )
        turn.answer = a
        appendTurn(turn, to: convoID)
        flushSave()
    }

    // MARK: - Cross-Model Shared Materials, Pre-Flight Cost & Dual-Model Comparison / Cross-Review

    struct ComparisonTarget: Identifiable, Equatable, Hashable {
        let id: String
        let channel: WuMindChannel
        let provider: WuMindProvider
        let modelID: String
        let displayName: String
        let channelLabel: String
        let priceNote: String?
    }

    func destinationLabel(for targetChannel: WuMindChannel, provider targetProvider: WuMindProvider) -> String {
        if targetChannel == .managed {
            let host = URL(string: gatewayBaseURL)?.host ?? "未配置网关"
            return "WUMIND 托管网关 (\(host))"
        }
        if let ext = targetProvider.multiProvider,
           let customHost = AIProviderEndpoints.displayHost(for: ext), !customHost.isEmpty {
            return "\(targetProvider.displayName) 自定义中转 (\(customHost))"
        }
        switch targetProvider {
        case .deepSeek: return "DeepSeek 官方 (api.deepseek.com)"
        case .openAI: return "OpenAI 官方 (api.openai.com)"
        case .gemini: return "Google Gemini (generativelanguage.googleapis.com)"
        case .claude: return "Anthropic Claude (api.anthropic.com)"
        case .grok: return "xAI Grok (api.x.ai)"
        }
    }

    /// Archives staged attachments into the active conversation's persistent `sharedMaterials`
    /// so switching to ANY other model on subsequent turns or cross-review NEVER requires re-uploading.
    func archiveAttachmentsToActiveConversation(_ attachments: [WuMindAttachment], initialPrompt: String) {
        guard !attachments.isEmpty else { return }
        let convoID = ensureActiveConversation(initialPrompt: initialPrompt)
        guard let idx = conversations.firstIndex(where: { $0.id == convoID }) else { return }
        let incoming = attachments.map { item in
            WuMindThreadMaterial(
                filename: item.document.filename,
                summaryBadge: item.document.summaryBadge,
                extractedText: item.document.extractedText,
                byteCount: item.document.byteCount
            )
        }
        let merged = WuMindMultiModelEngine.mergeThreadMaterials(
            existing: conversations[idx].sharedMaterials ?? [],
            incoming: incoming
        )
        conversations[idx].sharedMaterials = merged
        conversations[idx].updatedAt = Date()
        scheduleSave()
    }

    func removeSharedMaterial(_ materialID: UUID, from conversationID: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        var list = conversations[idx].sharedMaterials ?? []
        list.removeAll { $0.id == materialID }
        conversations[idx].sharedMaterials = list.isEmpty ? nil : list
        scheduleSave()
    }

    /// Computes live pre-flight token/cost estimate before sending high-cost tasks (long docs, deep thinking, agent).
    func preFlightEstimate(draftText: String, historyTokens: Int) -> WuMindCostTransparency.PreFlightEstimate {
        let pendingChars = pendingAttachments.reduce(0) { $0 + $1.document.extractedText.count }
        let sharedChars = (activeConversation?.sharedMaterials ?? []).reduce(0) { $0 + $1.extractedText.count }
        let inPer1K = (activeManagedModel?.inputPricePerMillion ?? 4.0) / 1_000.0
        let outPer1K = (activeManagedModel?.outputPricePerMillion ?? 12.0) / 1_000.0
        return WuMindCostTransparency.estimatePreFlight(
            promptText: draftText,
            attachmentChars: pendingChars,
            sharedMaterialChars: sharedChars,
            historyTokens: historyTokens,
            isDeepThinking: deepThinking && activeSupportsDeepThinking,
            isAgentMode: agentModeEnabled,
            agentCapYuan: preferences.agentMaxCostYuanPerRun,
            isManagedChannel: channel == .managed,
            inputYuanPer1K: inPer1K,
            outputYuanPer1K: outPer1K
        )
    }

    /// Lists all other ready models (across configured Own-API providers & enabled Managed Gateway models)
    /// for 1-tap same-question side-by-side comparison or cross-review.
    func availableComparisonTargets(excludingModelLabel: String) -> [ComparisonTarget] {
        var targets: [ComparisonTarget] = []
        var seenIDs: Set<String> = []

        if channel == .managed && hasGatewayURL {
            for item in enabledManagedModels {
                let p = WuMindProvider(rawValue: item.provider) ?? .openAI
                let key = "managed:\(item.id)"
                guard !seenIDs.contains(key) else { continue }
                seenIDs.insert(key)
                let note = String(format: "约 ¥%.3f/1K 输入", item.inputPricePerMillion / 1_000.0)
                targets.append(ComparisonTarget(
                    id: key,
                    channel: .managed,
                    provider: p,
                    modelID: item.id,
                    displayName: item.displayName,
                    channelLabel: destinationLabel(for: .managed, provider: p),
                    priceNote: note
                ))
            }
        }

        for provider in WuMindProvider.allCases where provider.hasKey {
            let options = models(for: provider).filter { $0.capability == .chat }
            let primaryChoice: (id: String, name: String)
            if let first = options.first {
                primaryChoice = (first.id, first.displayName)
            } else if provider == .deepSeek {
                primaryChoice = (DeepSeekChatClient.Model.pro.rawValue, "DeepSeek V4 Pro")
            } else {
                continue
            }
            let key = "own:\(provider.rawValue):\(primaryChoice.id)"
            guard !seenIDs.contains(key) else { continue }
            seenIDs.insert(key)
            targets.append(ComparisonTarget(
                id: key,
                channel: .ownAPI,
                provider: provider,
                modelID: primaryChoice.id,
                displayName: primaryChoice.name,
                channelLabel: destinationLabel(for: .ownAPI, provider: provider),
                priceNote: "自带 API · 零加价"
            ))
        }

        // Put different models first so comparing two distinct vendors is always 1 tap away.
        return targets.sorted { lhs, rhs in
            let lSame = excludingModelLabel.localizedCaseInsensitiveContains(lhs.displayName)
            let rSame = excludingModelLabel.localizedCaseInsensitiveContains(rhs.displayName)
            if lSame != rSame { return !lSame }
            return lhs.displayName < rhs.displayName
        }
    }

    /// Runs a second model on an existing completed turn for either structured Cross-Review (consensus + divergence)
    /// or Independent Side-by-Side Comparison, reusing the thread's full shared materials without re-uploading.
    func runModelComparison(
        conversationID: UUID,
        turnID: UUID,
        mode: WuMindComparisonResult.Mode,
        target: ComparisonTarget
    ) async throws -> WuMindComparisonResult {
        guard let convo = conversations.first(where: { $0.id == conversationID }),
              let turn = convo.turns.first(where: { $0.id == turnID }) else {
            throw DeepSeekChatClient.Failure.network
        }

        let sharedBlock = WuMindMultiModelEngine.formattedSharedMaterialsBlock(materials: convo.sharedMaterials ?? [])
        let baseSystem = composedSystemPrompt(conversationID: conversationID, includeAgentDirective: false, isTemporaryChat: false)

        let sysPrompt: String
        let messages: [AIProviderMessage]
        switch mode {
        case .crossReview:
            let reviewDirective = WuMindMultiModelEngine.crossReviewSystemPrompt(
                primaryModel: turn.modelLabel,
                reviewerModel: target.displayName
            )
            sysPrompt = [baseSystem, reviewDirective].compactMap { $0 }.joined(separator: "\n\n")
            let userPayload = WuMindMultiModelEngine.crossReviewUserPrompt(
                question: turn.question,
                primaryModel: turn.modelLabel,
                primaryAnswer: turn.answer,
                sharedMaterialsBlock: sharedBlock
            )
            messages = [AIProviderMessage(role: .user, text: userPayload)]
        case .independentCompare:
            let indDirective = WuMindMultiModelEngine.independentCompareSystemPrompt(reviewerModel: target.displayName)
            sysPrompt = [baseSystem, indDirective].compactMap { $0 }.joined(separator: "\n\n")
            var historyMsgs: [AIProviderMessage] = []
            for prior in convo.turns where prior.id != turnID && prior.state == .complete && !prior.answer.isEmpty {
                historyMsgs.append(.init(role: .user, text: String(prior.question.prefix(1_800))))
                historyMsgs.append(.init(role: .assistant, text: String(prior.answer.prefix(2_400))))
            }
            historyMsgs.append(.init(role: .user, text: turn.question))
            messages = Array(historyMsgs.suffix(12))
        }

        var answer = ""
        var promptTok: Int? = nil
        var completionTok: Int? = nil
        var costY: Double? = nil

        if target.channel == .managed {
            guard hasGatewayURL else { throw WuMindGatewayClient.GatewayError.invalidGatewayURL }
            let token = try await ensureManagedAccount()
            for try await event in WuMindGatewayClient().streamChat(
                gatewayURL: gatewayBaseURL,
                userToken: token,
                modelID: target.modelID,
                messages: messages,
                systemPrompt: sysPrompt,
                deepThinking: false,
                sessionTag: "compare-\(mode.rawValue)"
            ) {
                try Task.checkCancellation()
                switch event {
                case .trace: break
                case .reasoning: break
                case .content(let d): answer += d
                case .billing(let b):
                    managedBalanceYuan = b.balanceYuan
                    promptTok = b.promptTokens
                    completionTok = b.completionTokens
                    costY = b.costYuan
                case .warning(let warn):
                    if !warn.isEmpty { answer += "\n⚠️ \(warn)" }
                }
            }
        } else {
            guard let key = target.provider.apiKey(), !key.isEmpty else {
                throw DeepSeekChatClient.Failure.missingKey
            }
            if target.provider == .deepSeek {
                let dsModel = DeepSeekChatClient.Model(rawValue: target.modelID) ?? .pro
                let dsMsgs: [DeepSeekChatClient.Message] = messages.map {
                    .init(role: $0.role == .assistant ? .assistant : .user, content: $0.text)
                }
                for try await event in DeepSeekChatClient.streamEvents(
                    messages: dsMsgs,
                    apiKey: key,
                    model: dsModel,
                    thinking: .normal,
                    systemPrompt: sysPrompt,
                    extendedContext: true
                ) {
                    try Task.checkCancellation()
                    if case .content(let d) = event { answer += d }
                }
            } else if let mp = target.provider.multiProvider {
                let modelObj = AIProviderModel(id: target.modelID, displayName: target.displayName, supportsTextChat: true)
                let diagnosed = try await MultiProviderAIClient().sendDetailedDiagnosed(
                    provider: mp,
                    model: modelObj,
                    apiKey: key,
                    messages: messages,
                    deepThinking: false,
                    baseURL: AIProviderEndpoints.baseURL(for: mp),
                    systemPrompt: sysPrompt
                )
                answer = diagnosed.reply.answer
            }
        }

        let cleanAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAnswer.isEmpty else { throw DeepSeekChatClient.Failure.network }

        let result = WuMindComparisonResult(
            mode: mode,
            providerRaw: target.provider.rawValue,
            modelID: target.modelID,
            modelLabel: target.displayName,
            channelLabel: target.channelLabel,
            answer: cleanAnswer,
            promptTokens: promptTok,
            completionTokens: completionTok,
            costYuan: costY
        )

        mutateTurn(conversationID: conversationID, turnID: turnID, persist: true) { item in
            var list = item.comparisons ?? []
            list.append(result)
            item.comparisons = list
        }
        return result
    }

    func adoptComparison(conversationID: UUID, turnID: UUID, comparisonID: UUID) {
        mutateTurn(conversationID: conversationID, turnID: turnID, persist: true) { item in
            guard var list = item.comparisons else { return }
            for idx in list.indices {
                list[idx].adopted = (list[idx].id == comparisonID)
            }
            item.comparisons = list
        }
    }
}

#if DEBUG
@MainActor
final class WuMindFrameProbe: NSObject {
    private var displayLink: CADisplayLink?
    private var previous: CFTimeInterval?
    private var frameCount = 0
    private var slowFrames = 0
    private var longest = 0.0

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(sample(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func sample(_ link: CADisplayLink) {
        defer { previous = link.timestamp }
        guard let previous else { return }
        let gap = link.timestamp - previous
        frameCount += 1
        longest = max(longest, gap)
        if gap > 1.5 * (link.targetTimestamp - link.timestamp) { slowFrames += 1 }
    }

    func finish(firstBodyMs: Int?, bytes: Int) -> String {
        displayLink?.invalidate()
        displayLink = nil
        return "firstBodyMs=\(firstBodyMs ?? -1) slowFrames=\(slowFrames)/\(frameCount) longestMs=\(Int(longest * 1000)) bytes=\(bytes)"
    }
}
#endif
