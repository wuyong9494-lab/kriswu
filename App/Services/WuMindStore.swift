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
        case .deepSeek, .openAI, .gemini, .claude: return true
        case .grok: return false
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
         agentSteps: [WuMindAgentStep]? = nil) {
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
         projectID: UUID? = nil) {
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
    @Published var reasoning: String = ""
    @Published var answer: String = ""
    @Published var reasoningSeconds: Double? = nil
    @Published var agentSteps: [WuMindAgentStep] = []
    @Published var activeAgentPhase: String? = nil
    @Published var tick: UInt64 = 0

    func reset() {
        reasoning = ""
        answer = ""
        reasoningSeconds = nil
        agentSteps = []
        activeAgentPhase = nil
        tick &+= 1
    }
}

/// Honest, non-secret per-provider connection verification state (never stores API keys).
/// Strictly separates "catalog readable (/v1/models succeeded)" from "real chat inference succeeded".
struct WuMindProviderVerification: Codable, Equatable {
    enum Status: String, Codable {
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
struct WuMindModelSmokeRecord: Codable, Equatable {
    enum Status: String, Codable {
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

/// Persistent local conversation history, Projects, Customizations, Scheduled Tasks,
/// Multi-Step Agent Engine, & Flagship Settings for WUMIND.
/// Never stores API keys; keys stay strictly device-only in iOS Keychain.
@MainActor
final class WuMindStore: ObservableObject {
    static let shared = WuMindStore()

    private struct DiskSnapshot: Codable {
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
    }

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
    @Published var managedBalanceYuan: Double? = nil
    @Published var managedAccountStatus: WuMindAccountStatus? = nil
    @Published var managedSelectedModelID: String = "deepseek-reasoner"
    @Published var managedConfig: WuMindCommercialConfig = WuMindCommercialConfig()
    @Published var managedPaymentOrders: [WuMindPaymentOrder] = []

    // Cross-Device Zero-Knowledge Sync state
    @Published var isSyncingCloud: Bool = false
    @Published var lastCloudSyncAt: Date? = nil
    @Published var cloudSyncVersion: Int = 0
    @Published var lastCloudSyncDevice: String? = nil

    private let maxStoredConversations = 120
    private var saveTask: Task<Void, Never>?
    private var activeGenerationTask: Task<Void, Never>?
    private var flushTimerTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var pendingReasoning = ""
    private var pendingAnswer = ""
    private var pendingReasoningSeconds: Double? = nil
    private var pendingAgentSteps: [WuMindAgentStep] = []
    private var pendingActiveAgentPhase: String? = nil
    private var streamDirty = false

    var isGenerating: Bool { activeTurnID != nil }

    var activeGenerationConversationTitle: String? {
        guard let id = activeGenerationConversationID else { return nil }
        return conversations.first(where: { $0.id == id })?.title
    }

    private init() {
        load()
        if gatewayBaseURL.isEmpty,
           let bundled = Bundle.main.object(forInfoDictionaryKey: "WuMindGatewayURL") as? String {
            let trimmed = bundled.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("https://") {
                gatewayBaseURL = trimmed
            }
        }
    }

    var enabledManagedModels: [WuMindPricingItem] {
        managedConfig.pricing.filter(\.enabled)
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

    var activeSupportsDeepThinking: Bool {
        if channel == .managed {
            return activeManagedModel?.supportsThinking ?? false
        }
        return selectedProvider.supportsDeepThinkingToggle
    }

    /// True when the active model supports native multimodal image pixel passthrough (GPT / Gemini / Claude / Grok).
    /// DeepSeek gracefully falls back to on-device Vision OCR text extraction.
    var activeSupportsNativeVision: Bool {
        activeProviderForDisplay != .deepSeek
    }

    var hasGatewayURL: Bool {
        (try? WuMindGatewayClient.normalizedGatewayURL(gatewayBaseURL)) != nil
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

    func updateGatewayURL(_ raw: String) {
        gatewayBaseURL = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        scheduleSave()
    }

    func updateManagedConfigLocally(_ config: WuMindCommercialConfig) {
        managedConfig = config
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
    }

    @discardableResult
    func ensureManagedAccount(displayName: String = "") async throws -> String {
        guard hasGatewayURL else { throw WuMindGatewayClient.GatewayError.invalidGatewayURL }
        if let existing = Keychain.wumindGatewayUserToken, !existing.isEmpty {
            return existing
        }
        let reg = try await WuMindGatewayClient().registerAccount(gatewayURL: gatewayBaseURL, displayName: displayName)
        guard Keychain.setWuMindGatewayUserToken(reg.userToken) else {
            throw WuMindGatewayClient.GatewayError.unauthorized
        }
        managedAccountID = reg.userID
        managedBalanceYuan = reg.balanceYuan
        scheduleSave()
        return reg.userToken
    }

    func refreshManagedAccount() async throws {
        let token = try await ensureManagedAccount()
        let status = try await WuMindGatewayClient().fetchAccountStatus(gatewayURL: gatewayBaseURL, userToken: token)
        managedAccountID = status.userID
        managedBalanceYuan = status.balanceYuan
        managedAccountStatus = status
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
        if copy.enabled && copy.nextRunAt == nil {
            copy.nextRunAt = copy.cadence.nextRunDate(after: Date())
        }
        if let idx = scheduledTasks.firstIndex(where: { $0.id == task.id }) {
            scheduledTasks[idx] = copy
        } else {
            scheduledTasks.insert(copy, at: 0)
        }
        scheduleSave()
        syncScheduleToCloudIfApplicable(copy)
    }

    func toggleScheduledTask(_ id: UUID) {
        guard let idx = scheduledTasks.firstIndex(where: { $0.id == id }) else { return }
        scheduledTasks[idx].enabled.toggle()
        if scheduledTasks[idx].enabled {
            scheduledTasks[idx].nextRunAt = scheduledTasks[idx].cadence.nextRunDate(after: Date())
        }
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

    private func syncScheduleToCloudIfApplicable(_ task: WuMindScheduledTask) {
        guard task.channelRaw == WuMindChannel.managed.rawValue, hasGatewayURL else { return }
        let gw = gatewayBaseURL
        let intervalMins: Int = {
            switch task.cadence {
            case .daily: return 1440
            case .weekly: return 10080
            case .intervalHours(let h): return max(15, h * 60)
            case .once: return 1440
            }
        }()
        let nextEpoch = Int((task.nextRunAt ?? Date().addingTimeInterval(3600)).timeIntervalSince1970)
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = try? await self.ensureManagedAccount() else { return }
            do {
                try await WuMindGatewayClient().upsertCloudSchedule(
                    gatewayURL: gw,
                    userToken: token,
                    id: task.id.uuidString,
                    title: task.title,
                    prompt: task.prompt,
                    modelID: task.modelID,
                    intervalMinutes: intervalMins,
                    enabled: task.enabled,
                    nextRunEpoch: nextEpoch
                )
                if let idx = self.scheduledTasks.firstIndex(where: { $0.id == task.id }) {
                    self.scheduledTasks[idx].cloudSynced = true
                    self.scheduleSave()
                }
            } catch {
                // Local execution remains active even if cloud sync fails.
            }
        }
    }

    // MARK: - Long-Term Memory, Preferences & Export

    func addMemory(content: String, category: String = "偏好") {
        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        memories.insert(WuMindMemoryItem(content: String(clean.prefix(300)), category: category), at: 0)
        if memories.count > 50 { memories = Array(memories.prefix(50)) }
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

    /// Combines User Personalization/Memories, active Project workspace (instructions + knowledge docs),
    /// active Skill, attached GitHub repo, active Agent tool directive, and Claude-style compacted memory.
    func composedSystemPrompt(conversationID: UUID? = nil,
                              extraGitHubContext: WuMindGitHubClient.RepoContext? = nil,
                              includeAgentDirective: Bool = false) -> String? {
        var sections: [String] = []
        if let profile = preferences.formattedSystemProfileBlock(memories: memories) {
            sections.append(profile)
        }
        let targetConvo = conversationID.flatMap { id in conversations.first(where: { $0.id == id }) } ?? activeConversation
        if let proj = project(for: targetConvo) {
            sections.append(proj.formattedProjectSystemBlock())
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

    /// Starts streaming generation inside `WuMindStore.shared` so closing WUMIND, switching tabs,
    /// or putting the app into iOS background keeps generation alive cleanly without UI jank.
    /// Supports both single-turn 60 FPS streaming and Multi-Step Agent tool calling with exact cumulative metering.
    func startGeneration(
        displayQuestion: String,
        outgoingPrompt: String,
        attachmentNames: [String]?,
        imageAttachments: [AIProviderMessage.ImageAttachment] = [],
        autoRepoName: String?,
        agentOverride: Bool? = nil,
        sessionTagPrefix: String? = nil,
        forceNewConversationInProject: UUID? = nil
    ) {
        guard !isGenerating else { return }

        let activeChannel = channel
        let provider = activeProviderForDisplay
        let isDeep = deepThinking && activeSupportsDeepThinking
        let useAgent = agentOverride ?? agentModeEnabled
        let modelLabel = activeModelDisplayName
        let convoID = ensureActiveConversation(
            initialPrompt: displayQuestion,
            projectIDOverride: forceNewConversationInProject
        )
        let turnID = UUID()
        let priorTurns = conversations.first(where: { $0.id == convoID })?.turns ?? []

        // Clear any stale streaming buffer before starting
        pendingReasoning = ""
        pendingAnswer = ""
        pendingReasoningSeconds = nil
        pendingAgentSteps = []
        pendingActiveAgentPhase = useAgent ? "智能体规划与分析中…" : nil
        streamDirty = true
        streamBuffer.reset()
        streamBuffer.activeAgentPhase = pendingActiveAgentPhase

        activeTurnID = turnID
        activeGenerationConversationID = convoID
        thinkingStartedAt = Date()

        let badgeSuffix: String = {
            var tags: [String] = []
            if activeChannel == .managed { tags.append("内置") }
            if useAgent { tags.append("智能体") }
            if !imageAttachments.isEmpty && provider != .deepSeek { tags.append("视觉") }
            return tags.isEmpty ? "" : " · " + tags.joined(separator: "·")
        }()

        let turn = WuMindTurn(
            id: turnID,
            question: displayQuestion,
            modelLabel: modelLabel + badgeSuffix,
            provider: provider,
            isDeepThinking: isDeep,
            state: .generating,
            attachmentNames: attachmentNames
        )
        appendTurn(turn, to: convoID)
        beginBackgroundExecution()
        startStreamFlusher(turnID: turnID)

        let modelID = activeChannel == .managed
            ? (activeManagedModel?.id ?? "deepseek-reasoner")
            : selectedModelID
        let apiKey = activeChannel == .ownAPI ? provider.apiKey() : nil

        if activeChannel == .ownAPI && (apiKey?.isEmpty != false) {
            finishGeneration(conversationID: convoID, turnID: turnID, state: .failed("未配置 \(provider.displayName) API Key。"))
            return
        }

        let maxSteps = useAgent ? min(10, max(2, preferences.agentMaxSteps)) : 1
        let maxCostYuan = preferences.agentMaxCostYuanPerRun

        activeGenerationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let userToken: String? = activeChannel == .managed ? try await self.ensureManagedAccount() : nil

                if let repoName = autoRepoName,
                   let fetched = try? await WuMindGitHubClient().fetchRepoContext(fullName: repoName, token: Keychain.githubToken) {
                    self.attachedGitHubContext = fetched
                }

                let prepared = await self.prepareContextTurnsAndAutoCompact(
                    conversationID: convoID,
                    priorTurns: priorTurns,
                    outgoingPrompt: outgoingPrompt,
                    channel: activeChannel,
                    provider: provider,
                    modelID: modelID,
                    apiKey: apiKey
                )
                var workingMessages = Self.buildMultiProviderContext(
                    verbatimTurns: prepared.verbatimTurns,
                    prompt: outgoingPrompt,
                    images: provider != .deepSeek ? imageAttachments : [],
                    maxBytes: prepared.maxBytes
                )

                var totalPromptTokens = 0
                var totalCompletionTokens = 0
                var totalReasoningTokens = 0
                var totalCostYuan = 0.0
                var billedByGateway = false

                for stepIndex in 1...maxSteps {
                    try Task.checkCancellation()
                    guard self.activeTurnID == turnID else { return }

                    let isFinalForcedStep = useAgent && stepIndex == maxSteps
                    let allowToolsThisStep = useAgent && !isFinalForcedStep
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
                        sessionTag: stepTag
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
                                sessionTag: (sessionTagPrefix ?? "Agent") + " · 最终汇总"
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
                        self.pendingActiveAgentPhase = invocation.tool == "web_search"
                            ? "正在联网深度搜索：\(invocation.args["query"] ?? "")…"
                            : "正在调用工具：\(invocation.tool)…"
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
                let fallbackMsg = activeChannel == .managed
                    ? "WUMIND 计费网关暂不可用，本次未扣费。"
                    : "未收到完整回复，请检查网络或 API Key。"
                let message = (error as? LocalizedError)?.errorDescription ?? fallbackMsg
                self.finishGeneration(conversationID: convoID, turnID: turnID, state: .failed(message))
            }
        }
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
        sessionTag: String?
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
                sessionTag: sessionTag
            ) {
                guard !Task.isCancelled, activeTurnID == turnID else { throw CancellationError() }
                switch event {
                case .reasoning(let delta):
                    stepReasoning += delta
                    pendingReasoning += delta
                    streamDirty = true
                case .content(let delta):
                    if !answerStarted {
                        answerStarted = true
                        if !pendingReasoning.isEmpty, pendingReasoningSeconds == nil {
                            pendingReasoningSeconds = thinkingStartedAt.map { Date().timeIntervalSince($0) }
                        }
                    }
                    stepAnswer += delta
                    pendingAnswer += delta
                    streamDirty = true
                case .billing(let b):
                    receipt = b
                    managedBalanceYuan = b.balanceYuan
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
                case .reasoning(let delta):
                    stepReasoning += delta
                    pendingReasoning += delta
                    streamDirty = true
                case .content(let delta):
                    if !answerStarted {
                        answerStarted = true
                        if !pendingReasoning.isEmpty, pendingReasoningSeconds == nil {
                            pendingReasoningSeconds = thinkingStartedAt.map { Date().timeIntervalSince($0) }
                        }
                    }
                    stepAnswer += delta
                    pendingAnswer += delta
                    streamDirty = true
                }
            }
            markModelSmokePassed(.deepSeek, modelID: modelID, host: "api.deepseek.com", endpointPath: "/chat/completions", latencyMs: nil)
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
        let diagnosed: (reply: AIProviderReply, host: String, endpointPath: String)
        do {
            diagnosed = try await MultiProviderAIClient().sendDetailedDiagnosed(
                provider: mp,
                model: modelObj,
                apiKey: key,
                messages: messages,
                deepThinking: isDeep,
                baseURL: AIProviderEndpoints.baseURL(for: mp),
                systemPrompt: systemPrompt
            )
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
            host: diagnosed.host,
            endpointPath: diagnosed.endpointPath,
            latencyMs: elapsedMs
        )
        let reply = diagnosed.reply
        let stepReasoning = reply.reasoning ?? ""
        if !stepReasoning.isEmpty {
            pendingReasoning += (pendingReasoning.isEmpty ? "" : "\n") + stepReasoning
            if pendingReasoningSeconds == nil {
                pendingReasoningSeconds = thinkingStartedAt.map { Date().timeIntervalSince($0) }
            }
        }
        pendingAnswer = reply.answer
        streamDirty = true
        return StepOutput(
            reasoning: stepReasoning,
            answer: reply.answer,
            promptTokens: estPrompt,
            completionTokens: WuMindContextEngine.estimateTokens(reply.answer),
            reasoningTokens: WuMindContextEngine.estimateTokens(stepReasoning),
            costYuan: 0,
            billedByGateway: false
        )
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
            guard !query.isEmpty else {
                return WuMindAgentTools.ToolResult(succeeded: false, summary: "搜索关键词为空", observationText: "请提供非空搜索关键词 query。")
            }
            if channel == .managed, let token = userToken, hasGatewayURL {
                do {
                    let res = try await WuMindGatewayClient().webSearch(
                        gatewayURL: gatewayBaseURL,
                        userToken: token,
                        query: query,
                        maxResults: 5,
                        depth: depth
                    )
                    if let bal = res.balanceYuan {
                        managedBalanceYuan = bal
                    }
                    let obs = WuMindAgentTools.formatSearchObservation(
                        query: query,
                        provider: "WUMIND · \(res.provider)",
                        results: res.results
                    )
                    return WuMindAgentTools.ToolResult(
                        succeeded: !res.results.isEmpty,
                        summary: "\(res.provider) 搜得 \(res.results.count) 条",
                        observationText: obs,
                        extraCostYuan: res.costYuan
                    )
                } catch {
                    // Gracefully fall back to direct public search without charging gateway
                    return await WuMindAgentTools.directWebSearch(query: query, maxResults: 5, depth: depth)
                }
            }
            let rawKey = Keychain.connectorToken(for: "dev.websearch")
            let tavilyKey = (rawKey?.hasPrefix("tvly-") == true) ? rawKey : nil
            let braveKey = (rawKey != nil && tavilyKey == nil) ? rawKey : nil
            return await WuMindAgentTools.directWebSearch(
                query: query,
                maxResults: 5,
                depth: depth,
                tavilyKey: tavilyKey,
                braveKey: braveKey
            )

        case "web_fetch":
            let url = invocation.args["url"] ?? ""
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
            guard isConnectorInstalled("duty.schedule") || isConnectorInstalled("ws.calendar") else {
                return WuMindAgentTools.ToolResult(
                    succeeded: false,
                    summary: "未授权值班排班连接器",
                    observationText: "用户尚未在「定制中心」安装并授权「值班排班实时读取」连接器，出于隐私边界不可读取本地排班。"
                )
            }
            let days = min(30, max(1, Int(invocation.args["days"] ?? "7") ?? 7))
            let today = DayKey(date: Date(), calendar: .app)
            var rows: [String] = []
            for offset in 0..<days {
                let d = today.adding(days: offset, calendar: .app)
                let label = AppStore.shared.shift(on: d) ?? "未排/休"
                rows.append("\(d.description)：\(label)")
            }
            return WuMindAgentTools.ToolResult(
                succeeded: true,
                summary: "已查询近 \(days) 天值班排班",
                observationText: "【本机近 \(days) 天值班排班】\n" + rows.joined(separator: "\n")
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

    /// Checks enabled scheduled tasks and executes any due tasks cleanly in the background.
    func runDueScheduledTasksIfNeeded() async {
        guard !isGenerating, runningScheduleID == nil else { return }
        let now = Date()
        let dueTasks = scheduledTasks.filter { task in
            task.enabled && (task.nextRunAt ?? .distantFuture) <= now
        }
        for task in dueTasks.prefix(2) {
            await runScheduledTaskNow(task)
        }
    }

    func runScheduledTaskNow(_ task: WuMindScheduledTask) async {
        guard runningScheduleID == nil else { return }
        runningScheduleID = task.id
        beginBackgroundExecution()
        defer {
            runningScheduleID = nil
            endBackgroundExecution()
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
                    case .reasoning: break
                    case .content(let delta): answerText += delta
                    case .billing(let b):
                        managedBalanceYuan = b.balanceYuan
                        promptTokens = b.promptTokens
                        completionTokens = b.completionTokens
                        reasoningTokens = b.reasoningTokens
                        costYuan = b.costYuan
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
                scheduledTasks[idx].lastRunAt = Date()
                scheduledTasks[idx].lastStatus = "执行成功"
                scheduledTasks[idx].lastCostYuan = costYuan
                scheduledTasks[idx].lastTokens = promptTokens + completionTokens + reasoningTokens
                scheduledTasks[idx].lastConversationID = convo.id
                let nextDate = scheduledTasks[idx].cadence.nextRunDate(after: Date())
                scheduledTasks[idx].nextRunAt = nextDate
                if nextDate == nil { scheduledTasks[idx].enabled = false }
            }
            saveNow()
            if preferences.backgroundNotificationsEnabled {
                postBackgroundCompletionNotification(title: "定时任务：\(task.title)", preview: answerText)
            }
        } catch {
            let errMsg = (error as? LocalizedError)?.errorDescription ?? "定时任务执行失败"
            mutateTurn(conversationID: convo.id, turnID: turnID, persist: true) { item in
                item.state = .failed(errMsg)
            }
            if let idx = scheduledTasks.firstIndex(where: { $0.id == task.id }) {
                scheduledTasks[idx].lastRunAt = Date()
                scheduledTasks[idx].lastStatus = "失败：\(errMsg)"
                scheduledTasks[idx].lastConversationID = convo.id
                scheduledTasks[idx].nextRunAt = scheduledTasks[idx].cadence.nextRunDate(after: Date())
            }
            saveNow()
        }
    }

    func stopGeneration() {
        activeGenerationTask?.cancel()
        if let cID = activeGenerationConversationID, let tID = activeTurnID {
            finishGeneration(conversationID: cID, turnID: tID, state: .stopped)
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
            streamBuffer.reset()
            endBackgroundExecution()
        }
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

    private func startStreamFlusher(turnID: UUID) {
        flushTimerTask?.cancel()
        flushTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 80_000_000) // ~12.5 Hz smooth batched UI updates
                guard !Task.isCancelled, let self, self.activeTurnID == turnID else { break }
                if self.streamDirty {
                    self.streamDirty = false
                    self.streamBuffer.reasoning = self.pendingReasoning
                    self.streamBuffer.answer = self.pendingAnswer
                    self.streamBuffer.reasoningSeconds = self.pendingReasoningSeconds
                    self.streamBuffer.agentSteps = self.pendingAgentSteps
                    self.streamBuffer.activeAgentPhase = self.pendingActiveAgentPhase
                    self.streamBuffer.tick &+= 1
                }
            }
        }
    }

    private func finishGeneration(conversationID: UUID, turnID: UUID, state: WuMindTurn.State) {
        guard activeTurnID == turnID else { return }
        flushTimerTask?.cancel()
        flushTimerTask = nil

        let finalReasoning = pendingReasoning
        let finalAnswer = pendingAnswer
        let finalSteps = pendingAgentSteps
        let elapsed = pendingReasoningSeconds ?? thinkingStartedAt.map { Date().timeIntervalSince($0) }

        // Commit final buffered text & agent trace to the conversation turn ONCE (zero per-token array copying)
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
            item.state = state
        }

        let convoTitle = conversations.first(where: { $0.id == conversationID })?.title ?? "WUMIND"
        activeTurnID = nil
        activeGenerationConversationID = nil
        activeGenerationTask = nil
        thinkingStartedAt = nil
        compactingContext = false
        pendingReasoning = ""
        pendingAnswer = ""
        pendingReasoningSeconds = nil
        pendingAgentSteps = []
        pendingActiveAgentPhase = nil
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
        let vault = SyncVaultPayload(
            exportedAt: Date(),
            conversations: Array(sortedConversations.prefix(60)),
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

        // Non-destructive merge by ID / newest updatedAt so no device loses local work!
        var addedOrUpdated = 0
        for incoming in vault.conversations {
            if let idx = conversations.firstIndex(where: { $0.id == incoming.id }) {
                if incoming.updatedAt > conversations[idx].updatedAt || incoming.turns.count > conversations[idx].turns.count {
                    conversations[idx] = incoming
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

    /// Pulls completed Cloudflare Cron scheduled task answers from `/v1/schedules`
    /// and materializes any new offline cloud executions into local WUMIND conversations.
    @discardableResult
    func pullCloudCronResults() async throws -> Int {
        guard hasGatewayURL else { return 0 }
        let token = try await ensureManagedAccount()
        let remote = try await WuMindGatewayClient().fetchCloudSchedules(gatewayURL: gatewayBaseURL, userToken: token)
        var imported = 0
        for rec in remote {
            guard let ans = rec.lastAnswer?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ans.isEmpty,
                  let runStamp = rec.lastRunAt, !runStamp.isEmpty else { continue }
            let marker = "云端定时执行（\(runStamp)）"
            let alreadyExists = conversations.contains { convo in
                convo.title.contains(rec.title) && convo.turns.contains { $0.modelLabel.contains(runStamp) }
            }
            if !alreadyExists {
                let convo = WuMindConversation(
                    title: "☁️ ⏰ \(rec.title)",
                    provider: .deepSeek,
                    modelID: rec.modelID,
                    modelDisplayName: rec.modelID,
                    deepThinking: false
                )
                let turn = WuMindTurn(
                    question: rec.prompt,
                    answer: ans,
                    modelLabel: "\(marker) · \(rec.modelID)",
                    provider: .deepSeek,
                    isDeepThinking: false,
                    state: .complete,
                    costYuan: rec.lastCostYuan > 0 ? rec.lastCostYuan : nil
                )
                var fullConvo = convo
                fullConvo.turns = [turn]
                conversations.insert(fullConvo, at: 0)
                if let idx = scheduledTasks.firstIndex(where: { $0.id.uuidString == rec.id }) {
                    scheduledTasks[idx].lastStatus = "云端已执行（\(runStamp)）"
                    scheduledTasks[idx].lastCostYuan = rec.lastCostYuan > 0 ? rec.lastCostYuan : scheduledTasks[idx].lastCostYuan
                    scheduledTasks[idx].lastConversationID = fullConvo.id
                    scheduledTasks[idx].cloudSynced = true
                }
                imported += 1
            }
        }
        if imported > 0 { saveNow() }
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

    // MARK: - Persistence

    private static func storageURL(create: Bool) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: create)
        var folder = root.appendingPathComponent("WuMindLocal", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
        }
        return folder.appendingPathComponent("conversations.json")
    }

    private func load() {
        guard let url = try? Self.storageURL(create: false),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(DiskSnapshot.self, from: data) else {
            return
        }
        conversations = snapshot.conversations
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
        customSkills = snapshot.customSkills ?? []
        activeSkillID = snapshot.activeSkillID
        channel = snapshot.channel ?? .ownAPI
        gatewayBaseURL = snapshot.gatewayBaseURL ?? ""
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
        projects = snapshot.projects ?? []
        activeProjectID = snapshot.activeProjectID
        if let savedConnectors = snapshot.installedConnectorIDs {
            installedConnectorIDs = Set(savedConnectors)
        }
        connectorEndpoints = snapshot.connectorEndpoints ?? [:]
        scheduledTasks = snapshot.scheduledTasks ?? []
        memories = snapshot.memories ?? []
        if let prefs = snapshot.preferences {
            preferences = prefs
        }
        agentModeEnabled = snapshot.agentModeEnabled ?? preferences.agentEnabledByDefault
        providerVerifications = snapshot.providerVerifications ?? [:]
        modelSmokeRecords = snapshot.modelSmokeRecords ?? [:]
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        var encodedCache: [String: [WuMindModelOption]] = [:]
        for (provider, list) in cachedModels where provider != .deepSeek {
            encodedCache[provider.rawValue] = list
        }
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
        }
        let snapshot = DiskSnapshot(
            conversations: conversationsToSave,
            cachedModels: encodedCache,
            lastProvider: selectedProvider,
            lastModelID: selectedModelID,
            lastModelName: selectedModelName,
            lastDeepThinking: deepThinking,
            consentedProviders: Array(consentedProviders).sorted(),
            customSkills: customSkills,
            activeSkillID: activeSkillID,
            channel: channel,
            gatewayBaseURL: gatewayBaseURL,
            managedAccountID: managedAccountID,
            managedBalanceYuan: managedBalanceYuan,
            managedSelectedModelID: managedSelectedModelID,
            managedConfig: managedConfig,
            maxContextTokens: maxContextTokens,
            autoCompactContext: autoCompactContext,
            projects: projects,
            activeProjectID: activeProjectID,
            installedConnectorIDs: Array(installedConnectorIDs).sorted(),
            connectorEndpoints: connectorEndpoints,
            scheduledTasks: scheduledTasks,
            memories: memories,
            preferences: preferences,
            agentModeEnabled: agentModeEnabled,
            providerVerifications: providerVerifications,
            modelSmokeRecords: modelSmokeRecords
        )
        guard let url = try? Self.storageURL(create: true),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
