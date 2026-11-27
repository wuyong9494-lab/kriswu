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
