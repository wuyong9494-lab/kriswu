import Foundation

extension AIProvider {
    /// Scope the credential to the exact HTTPS origin and API mount (including a relay tenant).
    public func personalConnectionID(baseURL: String?) throws -> String {
        let url = try Self.normalizedBaseURL(baseURL) ?? URL(string: defaultBaseURLString)!
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host?.lowercased() else { throw MultiProviderAIError.invalidRequest }
        parts.scheme = "https"
        parts.host = host
        if parts.port == 443 { parts.port = nil }
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        if path == (self == .gemini ? "/v1beta" : "/v1") { path = "" }
        parts.percentEncodedPath = path
        guard let endpoint = parts.string else { throw MultiProviderAIError.invalidRequest }
        return rawValue + "|" + endpoint
    }
}

/// A versioned value kept in the original device-only Keychain item. Updating this
/// single value binds a legacy key to its old route before the settings can switch.
struct AIProviderCredentialSet {
    private static let prefix = "wumind-provider-keys-v1\n"
    private(set) var keys: [String: String]
    let requiresMigration: Bool

    init(stored: String?, provider: AIProvider, previousBaseURL: String?) throws {
        if let stored, stored.hasPrefix(Self.prefix) {
            keys = try JSONDecoder().decode([String: String].self, from: Data(stored.dropFirst(Self.prefix.count).utf8))
            requiresMigration = false
        } else if let stored, !stored.isEmpty {
            keys = [try provider.personalConnectionID(baseURL: previousBaseURL): stored]
            requiresMigration = true
        } else {
            keys = [:]
            requiresMigration = false
        }
    }

    mutating func set(_ key: String, for id: String) {
        keys[id] = key.isEmpty ? nil : key
    }

    func encoded() throws -> String {
        if keys.isEmpty { return "" }
        return Self.prefix + String(decoding: try JSONEncoder().encode(keys), as: UTF8.self)
    }
}
