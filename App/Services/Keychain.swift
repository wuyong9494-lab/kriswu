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
        if key == .deepSeekPlanAPIKey {
            _ = setDeepSeekPlanAPIKey(value)
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
        var q = query(.deepSeekPlanAPIKey)
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
        if key == .deepSeekPlanAPIKey { q[kSecAttrSynchronizable as String] = false }
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
