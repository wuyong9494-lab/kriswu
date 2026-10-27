import CryptoKit
import Foundation

/// 使用身份：
/// - 普通使用者：看自己的排班和统计，自己的名字、网站账号、提醒等设置能改；排班数据（手动改班、工作量纠正、规则、节假日、各组内容……）不能改
/// - 管理者（领导）：自己没有排班，可以查看所有人的排班和统计，不能改任何信息
/// - 管理员：什么都能改
enum UserRole: String {
    case user, manager, admin

    var title: String {
        switch self {
        case .user: return "普通使用者"
        case .manager: return "管理者（只能查看）"
        case .admin: return "管理员"
        }
    }

    var symbol: String {
        switch self {
        case .user: return "person"
        case .manager: return "eye"
        case .admin: return "key.fill"
        }
    }
}

/// 密码只存「加盐、反复哈希」后的结果，不在代码里写明文。
/// 这只是手机上的一道门：真正的数据安全还要靠不把 App 和代码给外人。
enum RoleAuth {
    private static let salt = "shiftreminder-role-v1|"
    private static let adminHash = "09af71b732b51680058ac13769e9dab232d4dbc143a85ca3276845c57ff6342e"
    private static let managerHash = "09af71b732b51680058ac13769e9dab232d4dbc143a85ca3276845c57ff6342e"

    static func hash(_ password: String) -> String {
        let saltData = Data(salt.utf8)
        var digest = Data(SHA256.hash(data: Data((salt + password).utf8)))
        for _ in 0..<99_999 {
            digest = Data(SHA256.hash(data: digest + saltData))
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 用 password 登录成 role（管理者或管理员）：密码对返回 true
    static func verify(_ password: String, as role: UserRole) async -> Bool {
        let input = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, role != .user else { return false }
        let h = await Task.detached(priority: .userInitiated) { hash(input) }.value
        return h == (role == .admin ? adminHash : managerHash)
    }
}
