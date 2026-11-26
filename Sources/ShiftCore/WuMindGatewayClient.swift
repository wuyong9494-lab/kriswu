import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Commercial pricing row for one model served through the WUMIND Managed Billing Gateway.
/// Editable only in Admin Mode and synced to Cloudflare Workers + D1.
public struct WuMindPricingItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var provider: String
    public var displayName: String
    public var inputPricePerMillion: Double
    public var outputPricePerMillion: Double
    public var officialReferenceNote: String
    public var supportsThinking: Bool
    public var enabled: Bool

    public init(id: String, provider: String, displayName: String,
                inputPricePerMillion: Double, outputPricePerMillion: Double,
                officialReferenceNote: String = "", supportsThinking: Bool = false, enabled: Bool = true) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.inputPricePerMillion = inputPricePerMillion
        self.outputPricePerMillion = outputPricePerMillion
        self.officialReferenceNote = officialReferenceNote
        self.supportsThinking = supportsThinking
        self.enabled = enabled
    }

    public static let defaultCatalog: [WuMindPricingItem] = [
        WuMindPricingItem(
            id: "deepseek-reasoner",
            provider: "deepSeek",
            displayName: "DeepSeek V4 Pro（深度思考）",
            inputPricePerMillion: 5.0,
            outputPricePerMillion: 20.0,
            officialReferenceNote: "官方参考约 ¥2 / ¥8",
            supportsThinking: true,
            enabled: true
        ),
        WuMindPricingItem(
            id: "deepseek-chat",
            provider: "deepSeek",
            displayName: "DeepSeek Flash（极速）",
            inputPricePerMillion: 2.5,
            outputPricePerMillion: 8.0,
            officialReferenceNote: "官方参考约 ¥1 / ¥4",
            supportsThinking: false,
            enabled: true
        ),
        WuMindPricingItem(
            id: "gpt-4o",
            provider: "openAI",
            displayName: "OpenAI GPT-4o",
            inputPricePerMillion: 36.0,
            outputPricePerMillion: 144.0,
            officialReferenceNote: "官方参考约 ¥18 / ¥72",
            supportsThinking: false,
            enabled: true
        ),
        WuMindPricingItem(
            id: "gemini-2.5-pro",
            provider: "gemini",
            displayName: "Google Gemini 2.5 Pro",
            inputPricePerMillion: 18.0,
            outputPricePerMillion: 120.0,
            officialReferenceNote: "官方参考约 ¥9 / ¥72",
            supportsThinking: true,
            enabled: true
        ),
        WuMindPricingItem(
            id: "claude-sonnet-4-20250514",
            provider: "claude",
            displayName: "Anthropic Claude Sonnet 4",
            inputPricePerMillion: 42.0,
            outputPricePerMillion: 210.0,
            officialReferenceNote: "官方参考约 ¥22 / ¥108",
            supportsThinking: true,
            enabled: true
        ),
        WuMindPricingItem(
            id: "grok-3",
            provider: "grok",
            displayName: "xAI Grok 3",
            inputPricePerMillion: 40.0,
            outputPricePerMillion: 180.0,
            officialReferenceNote: "官方参考约 ¥22 / ¥108",
            supportsThinking: false,
            enabled: true
        ),
    ]
}

/// Billing compliance channel mode configurable only by Admin.
public enum WuMindBillingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case hybrid = "hybrid"
    case appStoreIAP = "app_store_iap"
    case directQR = "direct_qr"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .hybrid: return "混合模式（Apple 内购 + 免费兑换码/站外）"
        case .appStoreIAP: return "仅 Apple 应用内购（App Store 审核合规）"
        case .directQR: return "仅兑换码 / 站外渠道（TestFlight 严禁收费）"
        }
    }
}

/// Configurable Apple StoreKit 2 Consumable Pack mapped to WUMIND credit balance.
public struct WuMindIAPPack: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String          // StoreKit Product ID, e.g. com.kriswu.wumind.credit.18
    public var title: String
    public var creditYuan: Double
    public var fallbackPriceLabel: String
    public var badge: String?

    public init(id: String, title: String, creditYuan: Double, fallbackPriceLabel: String, badge: String? = nil) {
        self.id = id
        self.title = title
        self.creditYuan = creditYuan
        self.fallbackPriceLabel = fallbackPriceLabel
        self.badge = badge
    }

    public static let defaultPacks: [WuMindIAPPack] = [
        WuMindIAPPack(id: "com.kriswu.wumind.credit.6", title: "轻量流量包", creditYuan: 6.0, fallbackPriceLabel: "¥6", badge: nil),
        WuMindIAPPack(id: "com.kriswu.wumind.credit.18", title: "常用流量包", creditYuan: 18.0, fallbackPriceLabel: "¥18", badge: "推荐"),
        WuMindIAPPack(id: "com.kriswu.wumind.credit.68", title: "深度研发包", creditYuan: 68.0, fallbackPriceLabel: "¥68", badge: "划算"),
        WuMindIAPPack(id: "com.kriswu.wumind.credit.198", title: "重度旗舰包", creditYuan: 198.0, fallbackPriceLabel: "¥198", badge: "超值"),
    ]
}

/// Public commercial configuration fetched from the WUMIND Gateway (never contains secrets).
public struct WuMindCommercialConfig: Codable, Equatable, Sendable {
    public var pricing: [WuMindPricingItem]
    public var wechatQRBase64: String?
    public var alipayQRBase64: String?
    public var rechargeNote: String
    public var contactNote: String
    public var announcement: String
    public var webSearchCostYuan: Double?
    public var billingMode: String?
    public var iapPacks: [WuMindIAPPack]?
    public var paymentWebhookNote: String?
    public var autoCheckoutEnabled: Bool?
    public var autoCreditPaused: Bool?
    public var appleIAPProductionEnabled: Bool?
    public var appleIAPSandboxTestEnabled: Bool?
    public var objectStorageConfigured: Bool?
    public var searchConfigured: Bool?
    public var callableModels: [WuMindCatalogModel]?

    public var resolvedWebSearchCostYuan: Double {
        max(0, webSearchCostYuan ?? 0.03)
    }

    public var resolvedBillingMode: WuMindBillingMode {
        WuMindBillingMode(rawValue: billingMode ?? "") ?? .hybrid
    }

    public var resolvedIAPPacks: [WuMindIAPPack] {
        if let packs = iapPacks, !packs.isEmpty { return packs }
        return WuMindIAPPack.defaultPacks
    }

    public var isAutoCheckoutEnabled: Bool {
        autoCheckoutEnabled == true && !isAutoCreditPaused
    }

    public var isAutoCreditPaused: Bool {
        autoCreditPaused == true
    }

    public init(pricing: [WuMindPricingItem] = WuMindPricingItem.defaultCatalog,
                wechatQRBase64: String? = nil,
                alipayQRBase64: String? = nil,
                rechargeNote: String = "请使用免费测试兑换码或通过官方合规渠道充值。",
                contactNote: String = "",
                announcement: String = "WUMIND 内置旗舰通道按真实 Token 实时计费，余额永久有效。",
                webSearchCostYuan: Double? = 0.03,
                billingMode: String? = WuMindBillingMode.appStoreIAP.rawValue,
                iapPacks: [WuMindIAPPack]? = WuMindIAPPack.defaultPacks,
                paymentWebhookNote: String? = "支持 Apple StoreKit 2 服务端签名验签入账（TestFlight 严禁向测试者收取真实费用）。",
                autoCheckoutEnabled: Bool? = nil,
                autoCreditPaused: Bool? = nil,
                appleIAPProductionEnabled: Bool? = nil,
                appleIAPSandboxTestEnabled: Bool? = nil,
                objectStorageConfigured: Bool? = nil,
                searchConfigured: Bool? = nil,
                callableModels: [WuMindCatalogModel]? = nil) {
        self.pricing = pricing
        self.wechatQRBase64 = wechatQRBase64
        self.alipayQRBase64 = alipayQRBase64
        self.rechargeNote = rechargeNote
        self.contactNote = contactNote
        self.announcement = announcement
        self.webSearchCostYuan = webSearchCostYuan
        self.billingMode = billingMode
        self.iapPacks = iapPacks
        self.paymentWebhookNote = paymentWebhookNote
        self.autoCheckoutEnabled = autoCheckoutEnabled
        self.autoCreditPaused = autoCreditPaused
        self.appleIAPProductionEnabled = appleIAPProductionEnabled
        self.appleIAPSandboxTestEnabled = appleIAPSandboxTestEnabled
        self.objectStorageConfigured = objectStorageConfigured
        self.searchConfigured = searchConfigured
        self.callableModels = callableModels
    }
}

public struct WuMindWebSearchResult: Codable, Identifiable, Equatable, Sendable {
    public let title: String
    public let url: String
    public let snippet: String
    public let publishedDate: String?
    public let readStatus: String?      // "full_text" | "snippet_only" | "fetch_failed"
    public let extractedText: String?
    public let fetchError: String?
    public var id: String { url + title }

    public var isFullTextRead: Bool { readStatus == "full_text" }
    public var isFetchFailed: Bool { readStatus == "fetch_failed" }

    public var readStatusBadge: String {
        switch readStatus {
        case "full_text": return "已读取原文"
        case "fetch_failed": return fetchError ?? "原文无法打开"
        default: return "仅搜到摘要"
        }
    }

    public init(
        title: String,
        url: String,
        snippet: String,
        publishedDate: String? = nil,
        readStatus: String? = "snippet_only",
        extractedText: String? = nil,
        fetchError: String? = nil
    ) {
        self.title = title
        self.url = url
        self.snippet = snippet
        self.publishedDate = publishedDate
        self.readStatus = readStatus
        self.extractedText = extractedText
        self.fetchError = fetchError
    }
}

public struct WuMindWebSearchResponse: Codable, Equatable, Sendable {
    public let ok: Bool?
    public let status: String?          // "ok" | "search_not_configured" | "timeout" | "no_results" | "upstream_error"
    public let code: String?
    public let error: String?
    public let query: String
    public let provider: String
    public let results: [WuMindWebSearchResult]
    public let fullTextCount: Int?
    public let fetchFailedCount: Int?
    public let costYuan: Double
    public let balanceYuan: Double?
    public let adminExempt: Bool?
}

public struct WuMindWebFetchResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let url: String
    public let readStatus: String
    public let extractedText: String
    public let fetchError: String?

    public var isFullTextRead: Bool { ok && readStatus == "full_text" }
}

public struct WuMindCloudScheduleRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let prompt: String
    public let modelID: String
    public let intervalMinutes: Int
    public let enabled: Bool
    public let nextRunEpoch: Int
    public let lastRunAt: String?
    public let lastAnswer: String?
    public let lastCostYuan: Double
}

public struct WuMindCloudSyncAck: Codable, Equatable, Sendable {
    public let ok: Bool
    public let version: Int
    public let updatedAt: String
}

public struct WuMindCloudSyncEnvelope: Codable, Equatable, Sendable {
    public let hasSnapshot: Bool
    public let encryptedPayload: String?
    public let version: Int
    public let deviceName: String?
    public let updatedAt: String?
}

public struct WuMindSyncPairingCode: Codable, Equatable, Sendable {
    public let code: String
    public let expiresAt: String
}

public struct WuMindPaymentOrder: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let amountYuan: Double
    public let channel: String
    public let status: String
    public let note: String
    public let checkoutURL: String?
    public let createdAt: String
    public let paidAt: String?

    public init(id: String, amountYuan: Double, channel: String, status: String, note: String,
                checkoutURL: String? = nil, createdAt: String, paidAt: String? = nil) {
        self.id = id
        self.amountYuan = amountYuan
        self.channel = channel
        self.status = status
        self.note = note
        self.checkoutURL = checkoutURL
        self.createdAt = createdAt
        self.paidAt = paidAt
    }
}

public struct WuMindPaymentOrderStatus: Codable, Equatable, Sendable {
    public let id: String
    public let status: String
    public let amountYuan: Double
    public let channel: String
    public let balanceYuan: Double
    public let paidAt: String?

    public var isPaid: Bool { status == "paid" }
}

public struct WuMindIAPVerifyResult: Codable, Equatable, Sendable {
    public let ok: Bool
    public let environment: String?
    public let isSandbox: Bool?
    public let accountUUID: String?
    public let creditedYuan: Double
    public let balanceYuan: Double
    public let sandboxBalanceYuan: Double?
    public let alreadyCredited: Bool

    public var isSandboxTransaction: Bool {
        isSandbox == true || environment == "Sandbox"
    }
}

public struct WuMindLedgerEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let kind: String
    public let provider: String
    public let model: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let reasoningTokens: Int
    public let costYuan: Double
    public let upstreamCostYuan: Double?
    public let balanceBeforeYuan: Double?
    public let balanceAfterYuan: Double
    public let environment: String?
    public let operatorID: String?
    public let note: String
    public let createdAt: String
}

public struct WuMindAccountStatus: Codable, Equatable, Sendable {
    public let userID: String
    public let displayName: String?
    public let registeredRole: String?
    public let accountUUID: String?
    public let billingExempt: Bool?
    public let dailyCostCapYuan: Double?
    public let balanceYuan: Double
    public let reservedYuan: Double?
    public let availableYuan: Double?
    public let sandboxBalanceYuan: Double?
    public let sandboxRechargedYuan: Double?
    public let totalRechargedYuan: Double
    public let purchasedRechargedYuan: Double?
    public let adminGrantedYuan: Double?
    public let totalSpentYuan: Double
    public let upstreamSpentYuan: Double?
    public let totalRequests: Int?
    public let totalPromptTokens: Int?
    public let totalCompletionTokens: Int?
    public let totalReasoningTokens: Int?
    public let todaySpentYuan: Double?
    public let todayUpstreamSpentYuan: Double?
    public let todayTokens: Int?
    public let ledger: [WuMindLedgerEntry]

    public var isBillingExempt: Bool { billingExempt == true }
    public var resolvedAvailableYuan: Double { availableYuan ?? max(0, balanceYuan - (reservedYuan ?? 0)) }

    public var totalTokens: Int {
        (totalPromptTokens ?? 0) + (totalCompletionTokens ?? 0) + (totalReasoningTokens ?? 0)
    }

    public static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.2fM", Double(count) / 1_000_000.0)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(max(0, count))"
    }
}

public struct WuMindRegistration: Codable, Equatable, Sendable {
    public let userID: String
    public let userToken: String
    public let displayName: String?
    public let registeredRole: String?
    public let balanceYuan: Double

    public init(userID: String, userToken: String, displayName: String? = nil, registeredRole: String? = nil, balanceYuan: Double) {
        self.userID = userID
        self.userToken = userToken
        self.displayName = displayName
        self.registeredRole = registeredRole
        self.balanceYuan = balanceYuan
    }
}

public struct WuMindBillingReceipt: Codable, Equatable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let reasoningTokens: Int
    public let costYuan: Double
    public let balanceYuan: Double
    public let adminExempt: Bool?
    public let upstreamCostYuan: Double?
    public let reservedYuan: Double?
    public let releasedYuan: Double?

    public init(promptTokens: Int, completionTokens: Int, reasoningTokens: Int, costYuan: Double, balanceYuan: Double,
                adminExempt: Bool? = nil, upstreamCostYuan: Double? = nil, reservedYuan: Double? = nil, releasedYuan: Double? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.costYuan = costYuan
        self.balanceYuan = balanceYuan
        self.adminExempt = adminExempt
        self.upstreamCostYuan = upstreamCostYuan
        self.reservedYuan = reservedYuan
        self.releasedYuan = releasedYuan
    }

    public var totalTokens: Int { promptTokens + completionTokens + reasoningTokens }
}

public struct WuMindVoucher: Codable, Identifiable, Equatable, Sendable {
    public let code: String
    public let amountYuan: Double
    public let note: String
    public let redeemedBy: String?
    public let createdAt: String
    public var id: String { code }
}

public struct WuMindAdminUserRow: Codable, Identifiable, Equatable, Sendable {
    public let userID: String
    public let displayName: String
    public let balanceYuan: Double
    public let reservedYuan: Double?
    public let sandboxBalanceYuan: Double?
    public let totalRechargedYuan: Double
    public let purchasedRechargedYuan: Double?
    public let adminGrantedYuan: Double?
    public let totalSpentYuan: Double
    public var id: String { userID }
}

public struct WuMindAdminCreditAuditRow: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let operatorID: String
    public let targetUserID: String?
    public let environment: String
    public let amountYuan: Double
    public let balanceBeforeYuan: Double
    public let balanceAfterYuan: Double
    public let note: String
    public let createdAt: String
}

public struct WuMindAdminSummary: Codable, Equatable, Sendable {
    public let userCount: Int
    public let totalBalanceYuan: Double
    public let totalReservedYuan: Double?
    public let totalSandboxBalanceYuan: Double?
    public let totalRechargedYuan: Double
    public let totalPurchasedYuan: Double?
    public let totalAdminGrantedYuan: Double?
    public let totalSpentYuan: Double
    public let recentVouchers: [WuMindVoucher]
    public let recentUsers: [WuMindAdminUserRow]
    public let recentAdminCredits: [WuMindAdminCreditAuditRow]?
}

public struct WuMindAdminTopUpResult: Codable, Equatable, Sendable {
    public let ok: Bool?
    public let alreadyApplied: Bool?
    public let auditID: String?
    public let userID: String
    public let environment: String?
    public let operatorID: String?
    public let amountYuan: Double?
    public let balanceBeforeYuan: Double?
    public let balanceAfterYuan: Double?
    public let balanceYuan: Double
    public let sandboxBalanceYuan: Double?
    public let totalRechargedYuan: Double
    public let purchasedRechargedYuan: Double?
    public let adminGrantedYuan: Double?
    public let note: String?
    public let createdAt: String?
}

/// HTTPS client for the WUMIND Managed Real-Time Billing Gateway (Cloudflare Workers + D1).
public struct WuMindGatewayClient: Sendable {
    public typealias DataTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public typealias StreamTransport = @Sendable (URLRequest, @escaping @Sendable (Int) throws -> Void,
                                                  @escaping @Sendable (String) async throws -> Void) async throws -> Void

    public enum StreamEvent: Equatable, Sendable {
        case reasoning(String)
        case content(String)
        case billing(WuMindBillingReceipt)
        case warning(String)
    }

    public enum GatewayError: LocalizedError, Equatable, Sendable {
        case invalidGatewayURL
        case unauthorized
        case insufficientBalance
        case upstreamBalanceInsufficient(String)
        case objectStorageUnconfigured(String)
        case serverMessage(String)
        case network
        case invalidResponse

        public var errorDescription: String? {
            switch self {
            case .invalidGatewayURL:
                return "WUMIND 计费网关地址格式不正确，请使用 https:// 开头的域名。"
            case .unauthorized:
                return "网关认证失败（401），请检查账号凭据或管理员密钥。"
            case .insufficientBalance:
                return "WUMIND 内置通道余额不足，请先充值或输入兑换码。"
            case .upstreamBalanceInsufficient(let msg):
                return msg
            case .objectStorageUnconfigured(let msg):
                return msg
            case .serverMessage(let msg):
                return msg
            case .network:
                return "无法连接到 WUMIND 计费网关，请检查网络或网关地址。"
            case .invalidResponse:
                return "未能解析 WUMIND 计费网关返回的数据。"
            }
        }
    }

    internal let dataTransport: DataTransport
    private let streamTransport: StreamTransport

    public init() {
        self.dataTransport = { request in
            try await WuMindGatewaySession.shared.data(for: request)
        }
        self.streamTransport = { request, onStatus, onLine in
            try await Self.defaultStreamSend(request, status: onStatus, line: onLine)
        }
    }

    public init(dataTransport: @escaping DataTransport, streamTransport: @escaping StreamTransport) {
        self.dataTransport = dataTransport
        self.streamTransport = streamTransport
    }

    public static func normalizedGatewayURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "https",
              let host = comps.host, !host.isEmpty,
              comps.user == nil, comps.password == nil,
              comps.query == nil, comps.fragment == nil,
              let url = comps.url else {
            throw GatewayError.invalidGatewayURL
        }
        return url
    }

    internal func makeURL(base: String, path: String) throws -> URL {
        let baseURL = try Self.normalizedGatewayURL(base)
        let baseStr = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let finalURL = URL(string: baseStr + path) else { throw GatewayError.invalidGatewayURL }
        return finalURL
    }

    // MARK: - Public & End-User APIs

    public func fetchPublicConfig(gatewayURL: String) async throws -> WuMindCommercialConfig {
        let url = try makeURL(base: gatewayURL, path: "/v1/public/config")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "GET"
        return try await performJSON(req)
    }

    public func registerAccount(
        gatewayURL: String,
        displayName: String = "",
        registeredRole: String = "user"
    ) async throws -> WuMindRegistration {
        let url = try makeURL(base: gatewayURL, path: "/v1/account/register")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "displayName": displayName,
            "registeredRole": registeredRole,
        ])
        return try await performJSON(req)
    }

    public func fetchAccountStatus(gatewayURL: String, userToken: String) async throws -> WuMindAccountStatus {
        let url = try makeURL(base: gatewayURL, path: "/v1/account/me")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "GET"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        return try await performJSON(req)
    }

    public func redeemVoucher(gatewayURL: String, userToken: String, code: String) async throws -> WuMindAccountStatus {
        let url = try makeURL(base: gatewayURL, path: "/v1/account/redeem")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["code": code.trimmingCharacters(in: .whitespacesAndNewlines)])
        return try await performJSON(req)
    }

    public func streamChat(
        gatewayURL: String,
        userToken: String,
        modelID: String,
        messages: [AIProviderMessage],
        systemPrompt: String?,
        deepThinking: Bool,
        sessionTag: String? = nil,
        idempotencyKey: String? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let transport = self.streamTransport
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = try makeURL(base: gatewayURL, path: "/v1/chat/completions")
                    let wireMessages: [[String: Any]] = messages.map { msg in
                        var item: [String: Any] = ["role": msg.role.rawValue, "content": msg.text]
                        if !msg.images.isEmpty {
                            item["images"] = msg.images.prefix(4).map {
                                ["mimeType": $0.mimeType, "base64Data": $0.base64Data]
                            }
                        }
                        return item
                    }
                    var payload: [String: Any] = [
                        "model": modelID,
                        "messages": wireMessages,
                        "deepThinking": deepThinking,
                    ]
                    if let sys = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !sys.isEmpty {
                        payload["systemPrompt"] = sys
                    }
                    if let tag = sessionTag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
                        payload["sessionTag"] = String(tag.prefix(80))
                    }
                    var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
                    if let idem = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines), !idem.isEmpty {
                        req.setValue(String(idem.prefix(96)), forHTTPHeaderField: "Idempotency-Key")
                    }
                    req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let parser = SSECollector(continuation: continuation)
                    try await transport(req, { code in
                        switch code {
                        case 200: return
                        case 401, 403: throw GatewayError.unauthorized
                        case 402: throw GatewayError.insufficientBalance
                        default: throw GatewayError.serverMessage("网关服务暂不可用（HTTP \(code)），本次未扣费。")
                        }
                    }, { line in
                        await parser.consume(line)
                    })
                    try Task.checkCancellation()
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let err as GatewayError {
                    continuation.finish(throwing: err)
                } catch {
                    continuation.finish(throwing: GatewayError.network)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func webSearch(
        gatewayURL: String,
        userToken: String,
        query: String,
        maxResults: Int = 5,
        depth: String = "basic",
        readTopPages: Int = 2,
        allowFallback: Bool = false
    ) async throws -> WuMindWebSearchResponse {
        let url = try makeURL(base: gatewayURL, path: "/v1/tools/web-search")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)),
            "maxResults": min(10, max(1, maxResults)),
            "depth": depth == "advanced" ? "advanced" : "basic",
            "readTopPages": min(3, max(0, readTopPages)),
            "allowFallback": allowFallback,
        ])
        let data: Data
        let response: URLResponse
        do {
            try Task.checkCancellation()
            (data, response) = try await dataTransport(req)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GatewayError.network
        }
        guard let http = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
        if (200..<300).contains(http.statusCode) {
            guard data.count <= 8 * 1024 * 1024,
                  let decoded = try? JSONDecoder().decode(WuMindWebSearchResponse.self, from: data) else {
                throw GatewayError.invalidResponse
            }
            return decoded
        }
        // Preserve structured search_not_configured (503) / timeout (504) / upstream_error (502) responses
        // so the UI and agent can report exact truthful status instead of losing failure codes.
        if [502, 503, 504].contains(http.statusCode),
           let structured = try? JSONDecoder().decode(WuMindWebSearchResponse.self, from: data) {
            return structured
        }
        throw Self.mapHTTPError(statusCode: http.statusCode, data: data)
    }

    public func webFetch(
        gatewayURL: String,
        userToken: String,
        url targetURL: String
    ) async throws -> WuMindWebFetchResponse {
        let url = try makeURL(base: gatewayURL, path: "/v1/tools/web-fetch")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "url": targetURL.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        return try await performJSON(req)
    }

    public func fetchCloudSchedules(gatewayURL: String, userToken: String) async throws -> [WuMindCloudScheduleRecord] {
        struct SchedulesWrap: Decodable { let schedules: [WuMindCloudScheduleRecord] }
        let url = try makeURL(base: gatewayURL, path: "/v1/schedules")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "GET"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        let wrap: SchedulesWrap = try await performJSON(req)
        return wrap.schedules
    }

    public func upsertCloudSchedule(
        gatewayURL: String,
        userToken: String,
        id: String,
        title: String,
        prompt: String,
        modelID: String,
        intervalMinutes: Int,
        enabled: Bool,
        nextRunEpoch: Int
    ) async throws {
        struct Ack: Decodable { let ok: Bool }
        let url = try makeURL(base: gatewayURL, path: "/v1/schedules")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": id,
            "title": title,
            "prompt": prompt,
            "modelID": modelID,
            "intervalMinutes": max(15, intervalMinutes),
            "enabled": enabled,
            "nextRunEpoch": nextRunEpoch,
        ])
        let _: Ack = try await performJSON(req)
    }

    public func deleteCloudSchedule(gatewayURL: String, userToken: String, id: String) async throws {
        struct Ack: Decodable { let ok: Bool }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let url = try makeURL(base: gatewayURL, path: "/v1/schedules/\(encoded)")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        let _: Ack = try await performJSON(req)
    }

    // MARK: - Cross-Device Encrypted Cloud Sync & Pairing

    public func pushCloudSyncSnapshot(
        gatewayURL: String,
        userToken: String,
        encryptedPayload: String,
        version: Int,
        deviceName: String
    ) async throws -> WuMindCloudSyncAck {
        let url = try makeURL(base: gatewayURL, path: "/v1/sync/push")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "encryptedPayload": encryptedPayload,
            "version": version,
            "deviceName": String(deviceName.prefix(64)),
        ])
        return try await performJSON(req)
    }

    public func pullCloudSyncSnapshot(gatewayURL: String, userToken: String) async throws -> WuMindCloudSyncEnvelope {
        let url = try makeURL(base: gatewayURL, path: "/v1/sync/pull")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.httpMethod = "GET"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        return try await performJSON(req)
    }

    public func createPairingCode(gatewayURL: String, userToken: String) async throws -> WuMindSyncPairingCode {
        let url = try makeURL(base: gatewayURL, path: "/v1/sync/pair/create")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        return try await performJSON(req)
    }

    public func claimPairingCode(gatewayURL: String, code: String) async throws -> WuMindRegistration {
        let url = try makeURL(base: gatewayURL, path: "/v1/sync/pair/claim")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        ])
        return try await performJSON(req)
    }

    // MARK: - Automated Payment Orders & StoreKit 2 Apple IAP Verification

    public func createPaymentOrder(
        gatewayURL: String,
        userToken: String,
        amountYuan: Double,
        channel: String
    ) async throws -> WuMindPaymentOrder {
        let url = try makeURL(base: gatewayURL, path: "/v1/payments/create-order")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "amountYuan": amountYuan,
            "channel": channel,
        ])
        return try await performJSON(req)
    }

    public func fetchPaymentOrders(gatewayURL: String, userToken: String) async throws -> [WuMindPaymentOrder] {
        struct OrdersWrap: Decodable { let orders: [WuMindPaymentOrder] }
        let url = try makeURL(base: gatewayURL, path: "/v1/payments/orders")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "GET"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        let wrap: OrdersWrap = try await performJSON(req)
        return wrap.orders
    }

    public func fetchPaymentOrderStatus(
        gatewayURL: String,
        userToken: String,
        orderID: String
    ) async throws -> WuMindPaymentOrderStatus {
        let encoded = orderID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? orderID
        let url = try makeURL(base: gatewayURL, path: "/v1/payments/orders/\(encoded)")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.httpMethod = "GET"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        return try await performJSON(req)
    }

    public func verifyAppleIAP(
        gatewayURL: String,
        userToken: String,
        productID: String,
        transactionID: String,
        originalTransactionID: String,
        jwsRepresentation: String
    ) async throws -> WuMindIAPVerifyResult {
        let url = try makeURL(base: gatewayURL, path: "/v1/iap/verify")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "productID": productID,
            "transactionID": transactionID,
            "originalTransactionID": originalTransactionID,
            "jwsRepresentation": jwsRepresentation,
        ])
        return try await performJSON(req)
    }

    // MARK: - Admin-Only APIs (Require X-WuMind-Admin-Secret)

    public func adminSaveConfig(gatewayURL: String, adminSecret: String,
                                config: WuMindCommercialConfig) async throws -> WuMindCommercialConfig {
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/config")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        req.httpBody = try JSONEncoder().encode(config)
        return try await performJSON(req)
    }

    public func adminCreateVouchers(gatewayURL: String, adminSecret: String,
                                    amountYuan: Double, count: Int, note: String) async throws -> [WuMindVoucher] {
        struct VoucherResponse: Decodable { let vouchers: [WuMindVoucher] }
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/vouchers")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "amountYuan": amountYuan,
            "count": count,
            "note": note,
        ])
        let res: VoucherResponse = try await performJSON(req)
        return res.vouchers
    }

    public func adminTopUpUser(
        gatewayURL: String,
        adminSecret: String,
        userID: String,
        amountYuan: Double,
        note: String,
        environment: String = "production",
        operatorID: String = "admin",
        idempotencyKey: String? = nil
    ) async throws -> WuMindAdminTopUpResult {
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/topup")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        if let idem = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines), !idem.isEmpty {
            req.setValue(String(idem.prefix(96)), forHTTPHeaderField: "Idempotency-Key")
        }
        var payload: [String: Any] = [
            "userID": userID.trimmingCharacters(in: .whitespacesAndNewlines),
            "amountYuan": amountYuan,
            "note": note,
            "environment": environment == "sandbox" ? "sandbox" : "production",
            "operatorID": operatorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "admin" : operatorID,
        ]
        if let idem = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines), !idem.isEmpty {
            payload["idempotencyKey"] = String(idem.prefix(96))
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try await performJSON(req)
    }

    public func adminFetchSummary(gatewayURL: String, adminSecret: String) async throws -> WuMindAdminSummary {
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/summary")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "GET"
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        return try await performJSON(req)
    }

    // MARK: - Internal Helpers

    internal struct ErrorBody: Decodable {
        let error: String?
        let code: String?
        let message: String?
    }

    internal static func mapHTTPError(statusCode: Int, data: Data) -> GatewayError {
        let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
        let rawError = parsed?.error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawMessage = parsed?.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let code = parsed?.code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let msg = !rawMessage.isEmpty ? rawMessage : rawError

        if code == "upstream_balance_insufficient" || rawError == "upstream_balance_insufficient" {
            let displayMsg = (!rawMessage.isEmpty ? rawMessage : (rawError == "upstream_balance_insufficient" ? "" : rawError))
            return .upstreamBalanceInsufficient(displayMsg.isEmpty ? "上游 API 余额不足，请前往 AIHubMix 充值（不扣您的 App 余额）。" : displayMsg)
        }
        if code == "object_storage_unconfigured" || rawError == "object_storage_unconfigured" {
            let displayMsg = (!rawMessage.isEmpty ? rawMessage : (rawError == "object_storage_unconfigured" ? "" : rawError))
            return .objectStorageUnconfigured(displayMsg.isEmpty ? "服务端尚未绑定 Cloudflare R2 对象存储（WORKS_BUCKET），大文件仅保存在本机。" : displayMsg)
        }
        switch statusCode {
        case 401:
            return .unauthorized
        case 402:
            return .insufficientBalance
        case 403:
            if !msg.isEmpty && code != "admin_forbidden" {
                return .serverMessage(msg)
            }
            return .unauthorized
        default:
            if !msg.isEmpty {
                return .serverMessage(msg)
            }
            return .serverMessage("网关返回错误（HTTP \(statusCode)）。")
        }
    }

    internal func performJSON<T: Decodable>(_ request: URLRequest, maxBytes: Int = 8 * 1024 * 1024) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            try Task.checkCancellation()
            (data, response) = try await dataTransport(request)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GatewayError.network
        }

        guard let http = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
        if (200..<300).contains(http.statusCode) {
            guard data.count <= maxBytes,
                  let decoded = try? JSONDecoder().decode(T.self, from: data) else {
                throw GatewayError.invalidResponse
            }
            return decoded
        }
        throw Self.mapHTTPError(statusCode: http.statusCode, data: data)
    }

    private struct WireStreamError: Decodable {
        let code: String?
        let message: String?
    }

    private struct WireFrame: Decodable {
        let reasoning: String?
        let content: String?
        let wumind_billing: WuMindBillingReceipt?
        let wumind_error: WireStreamError?
    }

    private actor SSECollector {
        let continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation

        init(continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) {
            self.continuation = continuation
        }

        func consume(_ rawLine: String) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { return }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let frame = try? JSONDecoder().decode(WireFrame.self, from: data) else { return }
            if let r = frame.reasoning, !r.isEmpty {
                continuation.yield(.reasoning(r))
            }
            if let c = frame.content, !c.isEmpty {
                continuation.yield(.content(c))
            }
            if let receipt = frame.wumind_billing {
                continuation.yield(.billing(receipt))
            }
            if let warn = frame.wumind_error?.message, !warn.isEmpty {
                continuation.yield(.warning(warn))
            }
        }
    }

    private static func defaultStreamSend(
        _ request: URLRequest,
        status: @escaping @Sendable (Int) throws -> Void,
        line: @escaping @Sendable (String) async throws -> Void
    ) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config, delegate: GatewayBlockRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        #if canImport(Darwin)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
        if http.statusCode != 200 {
            var errBytes = Data()
            for try await b in bytes {
                errBytes.append(b)
                if errBytes.count >= 16_384 { break }
            }
            if !errBytes.isEmpty {
                throw Self.mapHTTPError(statusCode: http.statusCode, data: errBytes)
            }
            try status(http.statusCode)
            return
        }
        try status(http.statusCode)
        for try await eventLine in bytes.lines {
            try Task.checkCancellation()
            try await line(eventLine)
        }
        #else
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
        if http.statusCode != 200 {
            if !data.isEmpty {
                throw Self.mapHTTPError(statusCode: http.statusCode, data: data)
            }
            try status(http.statusCode)
            return
        }
        try status(http.statusCode)
        guard let text = String(data: data, encoding: .utf8) else { throw GatewayError.invalidResponse }
        for eventLine in text.components(separatedBy: .newlines) {
            try Task.checkCancellation()
            try await line(eventLine)
        }
        #endif
    }
}

private final class GatewayBlockRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private enum WuMindGatewaySession {
    static let shared: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForResource = 45
        return URLSession(configuration: config, delegate: GatewayBlockRedirects(), delegateQueue: nil)
    }()
}
