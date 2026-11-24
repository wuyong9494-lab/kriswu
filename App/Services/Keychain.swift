import Foundation
import Security

/// 密码保存在系统钥匙串里，不写进普通文件。
enum Keychain {
    enum Key: String {
        case sourcePassword
        case pushPlusToken
        /// 金山文档的脚本令牌（周会问题写回金山文档用）
        case kdocsScriptToken
        /// 数传识图私钥，只在本机解锁时使用，不同步或迁移。
        case deepSeekPlanAPIKey
        case openAIChatAPIKey, geminiChatAPIKey, claudeChatAPIKey, grokChatAPIKey
        case githubPAT
        case wumindGatewayUserToken
        case wumindGatewayAdminSecret
    }

    private static func chatKey(_ provider: AIProvider) -> Key {
        switch provider {
        case .openAI: return .openAIChatAPIKey
        case .gemini: return .geminiChatAPIKey
        case .claude: return .claudeChatAPIKey
        case .grok: return .grokChatAPIKey
        }
    }

    static func providerChatAPIKey(_ provider: AIProvider) -> String? { get(chatKey(provider)) }
    @discardableResult
    static func setProviderChatAPIKey(_ value: String, provider: AIProvider) -> Bool {
        setDeviceOnly(value, for: chatKey(provider))
    }

    static var githubToken: String? {
        let token = get(.githubPAT)
        return (token?.isEmpty == false) ? token : nil
    }
    @discardableResult
    static func setGitHubToken(_ value: String) -> Bool {
        setDeviceOnly(value, for: .githubPAT)
    }

    static var wumindGatewayUserToken: String? {
        let token = get(.wumindGatewayUserToken)
        return (token?.isEmpty == false) ? token : nil
    }
    @discardableResult
    static func setWuMindGatewayUserToken(_ value: String) -> Bool {
        setDeviceOnly(value, for: .wumindGatewayUserToken)
    }

    static var wumindGatewayAdminSecret: String? {
        let secret = get(.wumindGatewayAdminSecret)
        return (secret?.isEmpty == false) ? secret : nil
    }
    @discardableResult
    static func setWuMindGatewayAdminSecret(_ value: String) -> Bool {
        setDeviceOnly(value, for: .wumindGatewayAdminSecret)
    }

    private static func isDeviceOnly(_ key: Key) -> Bool {
        switch key {
        case .deepSeekPlanAPIKey, .openAIChatAPIKey, .geminiChatAPIKey, .claudeChatAPIKey, .grokChatAPIKey,
             .githubPAT, .wumindGatewayUserToken, .wumindGatewayAdminSecret:
            return true
        default: return false
        }
    }

    private static let service = "com.kriswu.shiftreminder"

    private static func query(_ key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }

    static func set(_ value: String, for key: Key) {
        if isDeviceOnly(key) {
            _ = setDeviceOnly(value, for: key)
            return
        }
        SecItemDelete(query(key) as CFDictionary)
        // 「网站」页一直开着：改了密码要告诉它，自动登录才不会还用旧密码
        defer { NotificationCenter.default.post(name: .keychainChanged, object: nil) }
        guard !value.isEmpty else { return }
        var item = query(key)
        item[kSecValueData as String] = Data(value.utf8)
        // 解锁过一次之后后台同步也能读取
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    /// 不触发已有凭据的换密通知。更新失败时保留原条目。
    @discardableResult
    static func setDeepSeekPlanAPIKey(_ value: String) -> Bool {
        setDeviceOnly(value, for: .deepSeekPlanAPIKey)
    }

    private static func setDeviceOnly(_ value: String, for key: Key) -> Bool {
        var q = query(key)
        q[kSecAttrSynchronizable as String] = false
        if value.isEmpty {
            let status = SecItemDelete(q as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        q.merge(attributes) { _, new in new }
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: Key) -> String? {
        var q = query(key)
        if isDeviceOnly(key) { q[kSecAttrSynchronizable as String] = false }
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func connectorToken(for connectorID: String) -> String? {
        let account = "wumind.connector.\(connectorID)"
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (str?.isEmpty == false) ? str : nil
    }

    @discardableResult
    static func setConnectorToken(_ value: String, for connectorID: String) -> Bool {
        let account = "wumind.connector.\(connectorID)"
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            let status = SecItemDelete(q as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(clean.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        q.merge(attributes) { _, new in new }
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}
