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
         attachmentNames: [String]? = nil) {
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
         compactedTurnCount: Int? = nil) {
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
    @Published var tick: UInt64 = 0

    func reset() {
        reasoning = ""
        answer = ""
        reasoningSeconds = nil
        tick &+= 1
    }
}

/// Persistent local conversation history, Skills, & model selection memory for WUMIND.
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
    @Published var consentedProviders: Set<String> = []
    @Published var customSkills: [WuMindSkill] = []
    @Published var activeSkillID: String? = nil
    @Published var attachedGitHubContext: WuMindGitHubClient.RepoContext? = nil
    @Published var pendingAttachments: [WuMindAttachment] = []

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

    private let maxStoredConversations = 120
    private var saveTask: Task<Void, Never>?
    private var activeGenerationTask: Task<Void, Never>?
    private var flushTimerTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var pendingReasoning = ""
    private var pendingAnswer = ""
    private var pendingReasoningSeconds: Double? = nil
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

    /// Combines the active Skill prompt, any attached GitHub repository context, and Claude-style compacted memory.
    func composedSystemPrompt(conversationID: UUID? = nil,
                              extraGitHubContext: WuMindGitHubClient.RepoContext? = nil) -> String? {
        var sections: [String] = []
        if let skill = activeSkill {
            sections.append("[当前启用 Skill：\(skill.name)]\n\(skill.prompt)")
        }
        if let repoCtx = extraGitHubContext ?? attachedGitHubContext {
            sections.append(repoCtx.formattedPromptContext())
        }
        let targetConvo = conversationID.flatMap { id in conversations.first(where: { $0.id == id }) } ?? activeConversation
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

    func updateCachedModels(_ list: [AIProviderModel], for provider: WuMindProvider) {
        let mapped = list.map {
            WuMindModelOption(id: $0.id, displayName: $0.displayName, provider: provider, supportsTextChat: $0.supportsTextChat)
        }
        cachedModels[provider] = mapped
        if selectedProvider == provider {
            let textModels = mapped.filter(\.supportsTextChat)
            if !textModels.contains(where: { $0.id == selectedModelID }), let first = textModels.first {
                selectedModelID = first.id
                selectedModelName = first.displayName
            }
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
        scheduleSave()
    }

    @discardableResult
    func ensureActiveConversation(initialPrompt: String) -> UUID {
        if let id = activeConversationID, let idx = conversations.firstIndex(where: { $0.id == id }) {
            if conversations[idx].turns.isEmpty && conversations[idx].title == "新对话" {
                conversations[idx].title = WuMindConversation.autoTitle(from: initialPrompt)
            }
            conversations[idx].provider = selectedProvider
            conversations[idx].modelID = selectedModelID
            conversations[idx].modelDisplayName = selectedModelName
            conversations[idx].deepThinking = deepThinking
            conversations[idx].updatedAt = Date()
            scheduleSave()
            return id
        }
        let convo = WuMindConversation(
            title: WuMindConversation.autoTitle(from: initialPrompt),
            provider: selectedProvider,
            modelID: selectedModelID,
            modelDisplayName: selectedModelName,
            deepThinking: deepThinking
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

    // MARK: - Background-Resilient Streaming & Compaction Engine

    /// Starts streaming generation inside `WuMindStore.shared` so closing WUMIND, switching tabs,
    /// or putting the app into iOS background keeps generation alive cleanly without UI jank.
    func startGeneration(
        displayQuestion: String,
        outgoingPrompt: String,
        attachmentNames: [String]?,
        autoRepoName: String?
    ) {
        guard !isGenerating else { return }

        let activeChannel = channel
        let provider = activeProviderForDisplay
        let isDeep = deepThinking && activeSupportsDeepThinking
        let modelLabel = activeModelDisplayName
        let convoID = ensureActiveConversation(initialPrompt: displayQuestion)
        let turnID = UUID()
        let priorTurns = conversations.first(where: { $0.id == convoID })?.turns ?? []

        // Clear any stale streaming buffer before starting
        pendingReasoning = ""
        pendingAnswer = ""
        pendingReasoningSeconds = nil
        streamDirty = false
        streamBuffer.reset()

        activeTurnID = turnID
        activeGenerationConversationID = convoID
        thinkingStartedAt = Date()

        let turn = WuMindTurn(
            id: turnID,
            question: displayQuestion,
            modelLabel: activeChannel == .managed ? "\(modelLabel) · 内置" : modelLabel,
            provider: provider,
            isDeepThinking: isDeep,
            state: .generating,
            attachmentNames: attachmentNames
        )
        appendTurn(turn, to: convoID)
        beginBackgroundExecution()
        startStreamFlusher(turnID: turnID)

        // Channel 2: WUMIND Managed Real-Time Metered Billing Gateway
        if activeChannel == .managed {
            let gatewayURL = gatewayBaseURL
            let modelID = activeManagedModel?.id ?? "deepseek-reasoner"

            activeGenerationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                var answerStarted = false
                do {
                    let userToken = try await self.ensureManagedAccount()
                    if let repoName = autoRepoName,
                       let fetched = try? await WuMindGitHubClient().fetchRepoContext(fullName: repoName, token: Keychain.githubToken) {
                        self.attachedGitHubContext = fetched
                    }
                    let prepared = await self.prepareContextTurnsAndAutoCompact(
                        conversationID: convoID,
                        priorTurns: priorTurns,
                        outgoingPrompt: outgoingPrompt,
                        channel: .managed,
                        provider: provider,
                        modelID: modelID,
                        apiKey: nil
                    )
                    let history = Self.buildMultiProviderContext(
                        verbatimTurns: prepared.verbatimTurns,
                        prompt: outgoingPrompt,
                        maxBytes: prepared.maxBytes
                    )
                    let sysPrompt = self.composedSystemPrompt(conversationID: convoID)
                    for try await event in WuMindGatewayClient().streamChat(
                        gatewayURL: gatewayURL,
                        userToken: userToken,
                        modelID: modelID,
                        messages: history,
                        systemPrompt: sysPrompt,
                        deepThinking: isDeep
                    ) {
                        guard !Task.isCancelled, self.activeTurnID == turnID else { return }
                        switch event {
                        case .reasoning(let delta):
                            self.pendingReasoning += delta
                            self.streamDirty = true
                        case .content(let delta):
                            if !answerStarted {
                                answerStarted = true
                                if !self.pendingReasoning.isEmpty, self.pendingReasoningSeconds == nil {
                                    self.pendingReasoningSeconds = self.thinkingStartedAt.map { Date().timeIntervalSince($0) }
                                }
                            }
                            self.pendingAnswer += delta
                            self.streamDirty = true
                        case .billing(let receipt):
                            self.managedBalanceYuan = receipt.balanceYuan
                            self.mutateTurn(conversationID: convoID, turnID: turnID, persist: true) { item in
                                item.promptTokens = receipt.promptTokens
                                item.completionTokens = receipt.completionTokens
                                item.reasoningTokens = receipt.reasoningTokens
                                item.costYuan = receipt.costYuan
                            }
                        }
                    }
                    try Task.checkCancellation()
                    self.finishGeneration(conversationID: convoID, turnID: turnID, state: .complete)
                    Task { @MainActor [weak self] in
                        try? await self?.refreshManagedAccount()
                    }
                } catch is CancellationError {
                    self.compactingContext = false
                    self.finishGeneration(conversationID: convoID, turnID: turnID, state: .stopped)
                } catch {
                    self.compactingContext = false
                    let message = (error as? LocalizedError)?.errorDescription ?? "WUMIND 计费网关暂不可用，本次未扣费。"
                    self.finishGeneration(conversationID: convoID, turnID: turnID, state: .failed(message))
                }
            }
            return
        }

        // Channel 1: User's Own API Keys (Direct / Custom Relay)
        guard let apiKey = provider.apiKey(), !apiKey.isEmpty else {
            finishGeneration(conversationID: convoID, turnID: turnID, state: .failed("未配置 \(provider.displayName) API Key。"))
            return
        }

        if provider == .deepSeek {
            let dsModel = DeepSeekChatClient.Model(rawValue: selectedModelID) ?? .pro
            let dsThinking: DeepSeekChatClient.Thinking = isDeep ? .deep : .normal

            activeGenerationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                var answerStarted = false
                do {
                    if let repoName = autoRepoName,
                       let fetched = try? await WuMindGitHubClient().fetchRepoContext(fullName: repoName, token: Keychain.githubToken) {
                        self.attachedGitHubContext = fetched
                    }
                    let prepared = await self.prepareContextTurnsAndAutoCompact(
                        conversationID: convoID,
                        priorTurns: priorTurns,
                        outgoingPrompt: outgoingPrompt,
                        channel: .ownAPI,
                        provider: .deepSeek,
                        modelID: dsModel.rawValue,
                        apiKey: apiKey
                    )
                    let history = Self.buildDeepSeekContext(
                        verbatimTurns: prepared.verbatimTurns,
                        prompt: outgoingPrompt,
                        maxBytes: prepared.maxBytes
                    )
                    let sysPrompt = self.composedSystemPrompt(conversationID: convoID)
                    for try await event in DeepSeekChatClient.streamEvents(
                        messages: history,
                        apiKey: apiKey,
                        model: dsModel,
                        thinking: dsThinking,
                        systemPrompt: sysPrompt,
                        extendedContext: true
                    ) {
                        guard !Task.isCancelled, self.activeTurnID == turnID else { return }
                        switch event {
                        case .reasoning(let delta):
                            self.pendingReasoning += delta
                            self.streamDirty = true
                        case .content(let delta):
                            if !answerStarted {
                                answerStarted = true
                                if !self.pendingReasoning.isEmpty, self.pendingReasoningSeconds == nil {
                                    self.pendingReasoningSeconds = self.thinkingStartedAt.map { Date().timeIntervalSince($0) }
                                }
                            }
                            self.pendingAnswer += delta
                            self.streamDirty = true
                        }
                    }
                    try Task.checkCancellation()
                    self.finishGeneration(conversationID: convoID, turnID: turnID, state: .complete)
                } catch is CancellationError {
                    self.compactingContext = false
                    self.finishGeneration(conversationID: convoID, turnID: turnID, state: .stopped)
                } catch {
                    self.compactingContext = false
                    let message = (error as? LocalizedError)?.errorDescription ?? "未收到完整回复，请检查网络后重试。"
                    self.finishGeneration(conversationID: convoID, turnID: turnID, state: .failed(message))
                }
            }
        } else if let mp = provider.multiProvider {
            let modelObj = AIProviderModel(id: selectedModelID, displayName: modelLabel, supportsTextChat: true)

            activeGenerationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    if let repoName = autoRepoName,
                       let fetched = try? await WuMindGitHubClient().fetchRepoContext(fullName: repoName, token: Keychain.githubToken) {
                        self.attachedGitHubContext = fetched
                    }
                    let prepared = await self.prepareContextTurnsAndAutoCompact(
                        conversationID: convoID,
                        priorTurns: priorTurns,
                        outgoingPrompt: outgoingPrompt,
                        channel: .ownAPI,
                        provider: provider,
                        modelID: modelObj.id,
                        apiKey: apiKey
                    )
                    let history = Self.buildMultiProviderContext(
                        verbatimTurns: prepared.verbatimTurns,
                        prompt: outgoingPrompt,
                        maxBytes: prepared.maxBytes
                    )
                    let sysPrompt = self.composedSystemPrompt(conversationID: convoID)
                    let reply = try await MultiProviderAIClient().sendDetailed(
                        provider: mp,
                        model: modelObj,
                        apiKey: apiKey,
                        messages: history,
                        deepThinking: isDeep,
                        baseURL: AIProviderEndpoints.baseURL(for: mp),
                        systemPrompt: sysPrompt
                    )
                    guard !Task.isCancelled, self.activeTurnID == turnID else { return }
                    if let reasoning = reply.reasoning, !reasoning.isEmpty {
                        self.pendingReasoning = reasoning
                        self.pendingReasoningSeconds = self.thinkingStartedAt.map { Date().timeIntervalSince($0) }
                    }
                    self.pendingAnswer = reply.answer
                    self.finishGeneration(conversationID: convoID, turnID: turnID, state: .complete)
                } catch is CancellationError {
                    self.compactingContext = false
                    self.finishGeneration(conversationID: convoID, turnID: turnID, state: .stopped)
                } catch {
                    self.compactingContext = false
                    let message = (error as? LocalizedError)?.errorDescription ?? "未收到回复，请检查网络或 API Key。"
                    self.finishGeneration(conversationID: convoID, turnID: turnID, state: .failed(message))
                }
            }
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
        let elapsed = pendingReasoningSeconds ?? thinkingStartedAt.map { Date().timeIntervalSince($0) }

        // Commit final buffered text to the conversation turn ONCE (zero per-token array copying)
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
        streamDirty = false
        streamBuffer.reset()

        saveNow()
        if state == .complete && UIApplication.shared.applicationState != .active {
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
            maxWindowTokens: windowTokens
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

    private static func buildDeepSeekContext(
        verbatimTurns: [WuMindContextEngine.TurnSnapshot],
        prompt: String,
        maxBytes: Int
    ) -> [DeepSeekChatClient.Message] {
        var remaining = max(0, maxBytes - prompt.utf8.count)
        var reversedPairs: [DeepSeekChatClient.Message] = []
        for turn in verbatimTurns.lazy.reversed().prefix(118) {
            let cost = turn.question.utf8.count + turn.answer.utf8.count
            guard cost <= remaining else { break }
            remaining -= cost
            reversedPairs.append(.init(role: .assistant, content: turn.answer))
            reversedPairs.append(.init(role: .user, content: turn.question))
        }
        return Array(reversedPairs.reversed()) + [.init(role: .user, content: prompt)]
    }

    private static func buildMultiProviderContext(
        verbatimTurns: [WuMindContextEngine.TurnSnapshot],
        prompt: String,
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
        return Array(reversedPairs.reversed()) + [.init(role: .user, text: prompt)]
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
            autoCompactContext: autoCompactContext
        )
        guard let url = try? Self.storageURL(create: true),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
