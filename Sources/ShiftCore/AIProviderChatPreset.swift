import Foundation

extension AIProvider {
    /// Used offline on first selection. A preset never certifies account access.
    public var defaultChatModel: AIProviderModel {
        switch self {
        case .openAI: return .init(id: "gpt-5-mini", displayName: "GPT-5 mini", supportsTextChat: true)
        case .gemini: return .init(id: "gemini-flash-latest", displayName: "Gemini Flash", supportsTextChat: true)
        case .claude: return .init(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6", supportsTextChat: true)
        case .grok: return .init(id: "grok-4.7", displayName: "Grok 4.7", supportsTextChat: true)
        }
    }
}

/// Named services supported by the existing OpenAI-compatible connection.
public enum AICompatibleChatService: String, CaseIterable, Identifiable {
    case openAI, aiHubMix, openRouter, siliconFlow

    public var id: Self { self }
    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .aiHubMix: return "AIHubMix"
        case .openRouter: return "OpenRouter"
        case .siliconFlow: return "硅基流动"
        }
    }

    public var baseURL: String? {
        switch self {
        case .openAI: return nil
        case .aiHubMix: return "https://aihubmix.com/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .siliconFlow: return "https://api.siliconflow.cn/v1"
        }
    }

    public var model: AIProviderModel {
        switch self {
        case .openAI, .aiHubMix: return AIProvider.openAI.defaultChatModel
        case .openRouter: return .init(id: "openai/gpt-5-mini", displayName: "GPT-5 mini", supportsTextChat: true)
        case .siliconFlow: return .init(id: "Qwen/Qwen2.5-7B-Instruct", displayName: "Qwen2.5 7B Instruct", supportsTextChat: true)
        }
    }

    public static func matching(_ baseURL: String?) -> Self? {
        guard let scope = try? AIProvider.openAI.personalConnectionID(baseURL: baseURL) else { return nil }
        return allCases.first { (try? AIProvider.openAI.personalConnectionID(baseURL: $0.baseURL)) == scope }
    }
}
