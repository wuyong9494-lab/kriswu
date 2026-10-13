import Foundation
import Security

/// 密码保存在系统钥匙串里，不写进普通文件。
enum Keychain {
    enum Key: String {
        case sourcePassword
        case pushPlusToken
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
        SecItemDelete(query(key) as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query(key)
        item[kSecValueData as String] = Data(value.utf8)
        // 解锁过一次之后后台同步也能读取
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(_ key: Key) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
