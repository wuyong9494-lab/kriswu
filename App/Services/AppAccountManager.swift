import Foundation
import SwiftUI

struct ExternalUserProfile: Codable, Equatable, Sendable {
    var id: String
    var nickname: String
    var phoneMasked: String
    var loginMethod: String // "phone" | "wechat" | "guest"
    var wumindUserID: String?

    var methodDisplayTitle: String {
        switch loginMethod {
        case "phone": return "手机号登录"
        case "wechat": return "微信登录"
        default: return "外部访客模式"
        }
    }
}

struct ExternalSMSCodeResponse: Decodable, Sendable {
    let ok: Bool
    let maskedPhone: String?
    let cooldownSeconds: Int?
    let expiresInSeconds: Int?
    let testMode: Bool?
    let debugCode: String?
}

enum ExternalAuthError: LocalizedError, Sendable {
    case gatewayNotConfigured
    case invalidPhone
    case invalidCode
    case serverMessage(String)
    case networkFailed(String)

    var errorDescription: String? {
        switch self {
        case .gatewayNotConfigured:
            return "WuMind 内置服务尚未配置，请联系管理员。"
        case .invalidPhone:
            return "请输入有效的 11 位中国大陆手机号。"
        case .invalidCode:
            return "请输入 6 位数字短信验证码。"
        case .serverMessage(let msg):
            return msg
        case .networkFailed(let msg):
            return "网络请求失败：\(msg)"
        }
    }
}

/// Manages App-wide identity tier (`rosterMember` vs `externalUser`) and Phone SMS / WeChat external login.
@MainActor
final class AppAccountManager: ObservableObject {
    static let shared = AppAccountManager()

    private static let roleStorageKey = "app.accessRole.v1"
    private static let profileStorageKey = "app.externalUserProfile.v1"

    @Published private(set) var accessRole: AppUserAccessRole
    @Published private(set) var externalProfile: ExternalUserProfile?

    private var loginAttempt: UUID?

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.roleStorageKey),
           let role = AppUserAccessRole(rawValue: raw) {
            self.accessRole = role
        } else {
            self.accessRole = .rosterMember
        }
        if let data = UserDefaults.standard.data(forKey: Self.profileStorageKey),
           let decoded = try? JSONDecoder().decode(ExternalUserProfile.self, from: data) {
            self.externalProfile = decoded
        } else {
            self.externalProfile = nil
        }
    }

    /// True when the active session is strictly confined to the external boundary
    /// (WUMIND AI + Games + External Account only; all internal duty schedule surfaces hidden & blocked).
    var isExternalRestricted: Bool {
        !AppStore.isDemo && accessRole == .externalUser
    }

    func canAccess(_ surface: AppFeatureSurface) -> Bool {
        if AppStore.isDemo { return true }
        return AppAccessBoundary.canAccess(surface, role: accessRole)
    }

    func canOpenDeepLinkRoute(_ route: String) -> Bool {
        if AppStore.isDemo { return true }
        return AppAccessBoundary.canOpenDeepLinkRoute(route, role: accessRole)
    }

    func enterLocalExternalMode(nickname: String = "外部体验用户") {
        loginAttempt = nil
        let clean = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = ExternalUserProfile(
            id: externalProfile?.id ?? "EXT-LOCAL-\(String(UUID().uuidString.prefix(6)))",
            nickname: clean.isEmpty ? "外部体验用户" : clean,
            phoneMasked: externalProfile?.phoneMasked ?? "",
            loginMethod: externalProfile?.loginMethod ?? "guest",
            wumindUserID: externalProfile?.wumindUserID
        )
        applyExternalSession(profile: profile)
    }

    func switchToRosterMemberMode() {
        signOutExternal()
    }

    func signOutExternal(returnToRosterOnboarding: Bool = false) {
        loginAttempt = nil
        _ = Keychain.setExternalAuthToken("")
        externalProfile = nil
        UserDefaults.standard.removeObject(forKey: Self.profileStorageKey)
        accessRole = .rosterMember
        UserDefaults.standard.set(AppUserAccessRole.rosterMember.rawValue, forKey: Self.roleStorageKey)
        // Strictly wipe Account A's in-memory conversations, projects, attachments & credentials on shared devices!
        WuMindStore.shared.signOutCurrentAccount()
        if returnToRosterOnboarding {
            AppStore.shared.settings.onboardingDone = false
        }
    }

    // MARK: - Gateway Phone SMS & WeChat Auth Calls

    func sendSMSCode(phone: String) async throws -> ExternalSMSCodeResponse {
        guard let normalized = AppAccessBoundary.normalizeMainlandPhone(phone) else {
            throw ExternalAuthError.invalidPhone
        }
        let url = try gatewayEndpoint("/v1/auth/sms/send")
        let data = try await postJSON(url: url, payload: ["phone": normalized])
        guard let decoded = try? JSONDecoder().decode(ExternalSMSCodeResponse.self, from: data) else {
            throw ExternalAuthError.serverMessage("网关返回格式无法解析。")
        }
        return decoded
    }

    func verifySMSCode(phone: String, code: String, nickname: String) async throws {
        guard let normalized = AppAccessBoundary.normalizeMainlandPhone(phone) else {
            throw ExternalAuthError.invalidPhone
        }
        guard AppAccessBoundary.isValidSMSCode(code) else {
            throw ExternalAuthError.invalidCode
        }
        let attempt = UUID()
        loginAttempt = attempt
        let gateway = WuMindStore.shared.gatewayBaseURL
        let url = try gatewayEndpoint("/v1/auth/sms/verify")
        let data = try await postJSON(url: url, payload: [
            "phone": normalized,
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "nickname": nickname.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
        let wire = try decodeAuthResult(data)
        try finishGatewayLogin(wire, gateway: gateway, attempt: attempt)
    }

    func loginWithWeChatCode(code: String, nickname: String) async throws {
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw ExternalAuthError.serverMessage("缺少微信授权码。")
        }
        let attempt = UUID()
        loginAttempt = attempt
        let gateway = WuMindStore.shared.gatewayBaseURL
        let url = try gatewayEndpoint("/v1/auth/wechat/login")
        let data = try await postJSON(url: url, payload: [
            "code": clean,
            "nickname": nickname.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
        let wire = try decodeAuthResult(data)
        try finishGatewayLogin(wire, gateway: gateway, attempt: attempt)
    }

    // MARK: - Private Helpers

    private func finishGatewayLogin(_ wire: AuthResultWire, gateway: String, attempt: UUID) throws {
        let store = WuMindStore.shared
        guard wire.ok, let wallet = wire.user.wumindUserID, !wallet.isEmpty, !wire.sessionToken.isEmpty,
              loginAttempt == attempt, store.gatewayBaseURL == gateway else {
            throw ExternalAuthError.serverMessage("登录配置已更改或会话无效，请重新登录。")
        }
        guard Keychain.setWuMindGatewayUserToken(wire.sessionToken, gateway: store.gatewayBaseURL, accountID: wallet) else {
            throw ExternalAuthError.serverMessage("系统钥匙串无法保存登录会话，请解锁后重试。")
        }
        loginAttempt = nil
        _ = Keychain.setExternalAuthToken("")
        applyExternalSession(profile: wire.user)
        store.didSignInExternalUser(displayName: wire.user.nickname)
    }

    private func applyExternalSession(profile: ExternalUserProfile) {
        let previousOwner = WuMindStore.shared.activeStorageOwnerID
        externalProfile = profile
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: Self.profileStorageKey)
        }
        accessRole = .externalUser
        UserDefaults.standard.set(AppUserAccessRole.externalUser.rawValue, forKey: Self.roleStorageKey)
        AppStore.shared.settings.onboardingDone = true
        if let wm = profile.wumindUserID, !wm.isEmpty, WuMindStore.shared.managedAccountID != wm {
            WuMindStore.shared.managedAccountID = wm
        }
        if WuMindStore.shared.currentStorageOwnerID != previousOwner {
            WuMindStore.shared.reloadForCurrentAccount()
        } else {
            WuMindWorksStore.shared.reloadForCurrentAccount()
        }
    }

    private func gatewayEndpoint(_ path: String) throws -> URL {
        guard let base = try? WuMindGatewayConfiguration.address(WuMindStore.shared.gatewayBaseURL),
              let full = URL(string: base + path) else {
            throw ExternalAuthError.gatewayNotConfigured
        }
        return full
    }

    private func postJSON(url: URL, payload: [String: String]) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response): (Data, URLResponse)
        do {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpShouldSetCookies = false
            (data, response) = try await URLSession(configuration: cfg).data(for: req)
        } catch {
            throw ExternalAuthError.networkFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ExternalAuthError.networkFailed("无有效 HTTP 响应。")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let errObj = try? JSONDecoder().decode(GatewayErrorBody.self, from: data),
               let msg = errObj.error, !msg.isEmpty {
                throw ExternalAuthError.serverMessage(msg)
            }
            throw ExternalAuthError.serverMessage("网关拒绝请求（HTTP \(http.statusCode)）。")
        }
        return data
    }

    private func decodeAuthResult(_ data: Data) throws -> AuthResultWire {
        guard let wire = try? JSONDecoder().decode(AuthResultWire.self, from: data) else {
            throw ExternalAuthError.serverMessage("无法解析登录响应数据。")
        }
        return wire
    }

    private struct GatewayErrorBody: Decodable { let error: String? }
    private struct AuthResultWire: Decodable {
        let ok: Bool
        let sessionToken: String
        let user: ExternalUserProfile
    }
}
