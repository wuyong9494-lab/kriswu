import Foundation
import SwiftUI

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

    init(id: UUID = UUID(),
         question: String,
         reasoning: String = "",
         reasoningSeconds: Double? = nil,
         answer: String = "",
         modelLabel: String,
         provider: WuMindProvider,
         isDeepThinking: Bool,
         state: State = .generating,
         createdAt: Date = Date()) {
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

    init(id: UUID = UUID(),
         title: String = "新对话",
         provider: WuMindProvider = .deepSeek,
         modelID: String = DeepSeekChatClient.Model.pro.rawValue,
         modelDisplayName: String = "DeepSeek V4 Pro",
         deepThinking: Bool = true,
         isPinned: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         turns: [WuMindTurn] = []) {
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

/// Persistent local conversation history & model selection memory for WUMIND.
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
    }

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

    private let maxStoredConversations = 120
    private var saveTask: Task<Void, Never>?

    private init() {
        load()
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
        conversations.removeAll { $0.id == id }
        if activeConversationID == id {
            activeConversationID = nil
        }
        scheduleSave()
    }

    func deleteAllConversations() {
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
        let snapshot = DiskSnapshot(
            conversations: conversations,
            cachedModels: encodedCache,
            lastProvider: selectedProvider,
            lastModelID: selectedModelID,
            lastModelName: selectedModelName,
            lastDeepThinking: deepThinking,
            consentedProviders: Array(consentedProviders).sorted()
        )
        guard let url = try? Self.storageURL(create: true),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
