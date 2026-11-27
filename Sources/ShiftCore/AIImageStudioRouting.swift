import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Explicit execution route for Image Studio requests (never ambiguous, never silent fallback).
public enum AIImageRouteKind: String, Codable, Equatable, Hashable, Sendable {
    case managedGateway
    case ownAIHubMix
    case ownDirectVendor

    public var badgeText: String {
        switch self {
        case .managedGateway: return "WuMind 内置"
        case .ownAIHubMix: return "自有 API · AIHubMix"
        case .ownDirectVendor: return "自有 API · 官方直连"
        }
    }

    public var billingDescription: String {
        switch self {
        case .managedGateway: return "走 WuMind 登录凭证与余额结算，不读取本机厂商 Key"
        case .ownAIHubMix: return "直连已保存的 AIHubMix，按 AIHubMix 账户计费（不扣 WuMind 余额）"
        case .ownDirectVendor: return "直连对应厂商官方接口（不扣 WuMind 余额）"
        }
    }
}

/// User preference for Own-API Image Studio connection mode (decoupled from model vendor).
public enum AIImageOwnConnectionPreference: String, Codable, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case auto
    case aihubmix
    case directVendor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "自动选用 AIHubMix"
        case .aihubmix: return "AIHubMix 统一连接"
        case .directVendor: return "厂商官方直连"
        }
    }
}

/// Identifies which saved credential slot supplied an Own-API connection.
public enum AIImageConnectionSourceSlot: String, Codable, Equatable, Hashable, Sendable {
    case dedicatedAIHubMix
    case reusedOpenAISlot
    case directVendor

    public var shortLabel: String {
        switch self {
        case .dedicatedAIHubMix: return "AIHubMix 专属连接"
        case .reusedOpenAISlot: return "复用 GPT 栏 AIHubMix 连接"
        case .directVendor: return "本机厂商直连 Key"
        }
    }
}

/// Verified AIHubMix connection decoupled from model vendor (shared across GPT Image & Nano Banana 2).
public struct AIImageAIHubMixConnection: Equatable, Hashable, Sendable {
    public let apiKey: String
    public let baseURL: String
    public let sourceSlot: AIImageConnectionSourceSlot

    public init(apiKey: String, baseURL: String, sourceSlot: AIImageConnectionSourceSlot) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.sourceSlot = sourceSlot
    }

    public var resolvedHost: String {
        if let url = try? AIProvider.normalizedBaseURL(baseURL), let host = url.host, !host.isEmpty {
            return host
        }
        return "aihubmix.com"
    }

    /// Strict domain isolation: an aggregator key MUST ONLY target a verified aggregator HTTPS host,
    /// NEVER official api.openai.com, generativelanguage.googleapis.com, api.anthropic.com, or api.x.ai.
    public var isSafeAggregatorHost: Bool {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { return false }
        return AIProviderToolHTTP.isOpenAICompatibleRelay(baseURL)
            && !AIProviderToolHTTP.isOfficialVendorHost(baseURL)
    }

    /// Resolves an active AIHubMix connection without disturbing existing OpenAI official chat configs.
    /// Reuses legacy `.openAI` slot ONLY when `.openAI` Base URL is a verified AIHubMix/Inferera host.
    public static func resolve(
        dedicatedKey: String?,
        dedicatedBaseURL: String?,
        openAIKey: String?,
        openAIBaseURL: String?
    ) -> AIImageAIHubMixConnection? {
        if let key = dedicatedKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            let rawURL = dedicatedBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let effectiveURL = rawURL.isEmpty ? "https://aihubmix.com/v1" : rawURL
            let candidate = AIImageAIHubMixConnection(
                apiKey: key,
                baseURL: effectiveURL,
                sourceSlot: .dedicatedAIHubMix
            )
            if candidate.isSafeAggregatorHost {
                return candidate
            }
        }
        if let key = openAIKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty,
           let rawURL = openAIBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty,
           AIProviderToolHTTP.isOpenAICompatibleRelay(rawURL),
           !AIProviderToolHTTP.isOfficialVendorHost(rawURL) {
            let candidate = AIImageAIHubMixConnection(
                apiKey: key,
                baseURL: rawURL,
                sourceSlot: .reusedOpenAISlot
            )
            if candidate.isSafeAggregatorHost {
                return candidate
            }
        }
        return nil
    }
}

/// Pure-value credential & catalog snapshot consumed by the single shared Image Studio availability engine.
public struct AIImageCredentialSnapshot: Equatable, Sendable {
    public let useManagedGateway: Bool
    public let isGatewayConfigured: Bool
    public let isGatewayLoggedIn: Bool
    public let isGatewayCatalogSyncing: Bool
    public let enabledManagedImageModels: [WuMindCatalogModel]
    public let ownPreference: AIImageOwnConnectionPreference
    public let aihubmixConnection: AIImageAIHubMixConnection?
    public let directProviderKeys: Set<AIProvider>
    public let directProviderBaseURLs: [AIProvider: String]

    public init(
        useManagedGateway: Bool,
        isGatewayConfigured: Bool,
        isGatewayLoggedIn: Bool,
        isGatewayCatalogSyncing: Bool = false,
        enabledManagedImageModels: [WuMindCatalogModel],
        ownPreference: AIImageOwnConnectionPreference = .auto,
        aihubmixConnection: AIImageAIHubMixConnection?,
        directProviderKeys: Set<AIProvider>,
        directProviderBaseURLs: [AIProvider: String] = [:]
    ) {
        self.useManagedGateway = useManagedGateway
        self.isGatewayConfigured = isGatewayConfigured
        self.isGatewayLoggedIn = isGatewayLoggedIn
        self.isGatewayCatalogSyncing = isGatewayCatalogSyncing
        self.enabledManagedImageModels = enabledManagedImageModels
        self.ownPreference = ownPreference
        self.aihubmixConnection = aihubmixConnection
        self.directProviderKeys = directProviderKeys
        self.directProviderBaseURLs = directProviderBaseURLs
    }
}

public enum AIImageMissingConnectionAction: Equatable, Sendable {
    case configureAIHubMix
    case configureDirectVendor(AIProvider)
    case openGatewayAccount
}

/// Single authoritative availability state shared by Model Center, Studio Model Picker, Status Banner, and Submit Button.
public enum AIImageAvailabilityState: Equatable, Sendable {
    case ready(
        route: AIImageRouteKind,
        routeBadge: String,
        detail: String,
        sourceSlot: AIImageConnectionSourceSlot?,
        managedCatalogModel: WuMindCatalogModel?
    )
    case managedCatalogSyncing(routeBadge: String)
    case managedGatewayConfigInvalid(detail: String)
    case managedModelNotEnabled(modelID: String, modelName: String, hasOtherManagedModels: Bool)
    case managedLoginRequired(detail: String)
    case missingConnection(
        route: AIImageRouteKind,
        title: String,
        detail: String,
        action: AIImageMissingConnectionAction
    )
    case referenceImageUnsupported(route: AIImageRouteKind, modelName: String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var routeKind: AIImageRouteKind {
        switch self {
        case .ready(let route, _, _, _, _): return route
        case .managedCatalogSyncing, .managedGatewayConfigInvalid, .managedModelNotEnabled, .managedLoginRequired:
            return .managedGateway
        case .missingConnection(let route, _, _, _): return route
        case .referenceImageUnsupported(let route, _): return route
        }
    }

    public var routeBadge: String {
        switch self {
        case .ready(_, let badge, _, _, _): return badge
        case .managedCatalogSyncing(let badge): return badge
        case .managedGatewayConfigInvalid, .managedModelNotEnabled, .managedLoginRequired:
            return AIImageRouteKind.managedGateway.badgeText
        case .missingConnection(let route, _, _, _): return route.badgeText
        case .referenceImageUnsupported(let route, _): return route.badgeText
        }
    }

    /// Compact action pill text for Model Center cards (always consistent with Studio).
    public var modelCenterPillTitle: String {
        switch self {
        case .ready(let route, _, _, _, _):
            switch route {
            case .managedGateway: return "进入画室"
            case .ownAIHubMix: return "进入画室"
            case .ownDirectVendor: return "进入画室"
            }
        case .managedCatalogSyncing:
            return "同步目录中"
        case .managedGatewayConfigInvalid:
            return "网关配置无效"
        case .managedModelNotEnabled:
            return "内置暂未开通"
        case .managedLoginRequired:
            return "需登录账号"
        case .missingConnection:
            return "需配置连接"
        case .referenceImageUnsupported:
            return "仅文生图"
        }
    }

    public var bannerTitle: String? {
        switch self {
        case .ready:
            return nil
        case .managedCatalogSyncing:
            return "正在同步 WuMind 内置生图目录…"
        case .managedGatewayConfigInvalid:
            return "WuMind 网关地址无效或未配置"
        case .managedModelNotEnabled(_, let name, _):
            return "\(name) 内置暂未开通"
        case .managedLoginRequired:
            return "需登录 WuMind 账号"
        case .missingConnection(_, let title, _, _):
            return title
        case .referenceImageUnsupported(_, let name):
            return "\(name) 不支持参考图编辑"
        }
    }

    public var bannerDetail: String? {
        switch self {
        case .ready:
            return nil
        case .managedCatalogSyncing:
            return "正在拉取网关实际启用的生图能力清单，请稍候。"
        case .managedGatewayConfigInvalid(let detail):
            return detail
        case .managedModelNotEnabled(_, _, let hasOther):
            return hasOther
                ? "当前为 WuMind 内置模式，不会要求填写厂商 Key 或自动切换自有 API；请切换其他已开通的内置模型，或由管理员在后台实测启用。"
                : "当前网关尚未启用任何内置生图模型（不会要求填写 Google/OpenAI 本机 Key）。请联系管理员在商业计费后台实测并启用生图模型，或手动切至自有 API。"
        case .managedLoginRequired(let detail):
            return detail
        case .missingConnection(_, _, let detail, _):
            return detail
        case .referenceImageUnsupported(_, let name):
            return "「\(name)」仅支持纯文生图，请清除参考图或切换支持参考图的模型（如 GPT Image / Nano Banana 2）。"
        }
    }
}

public struct AIImageOwnExecutionTarget: Equatable, Sendable {
    public let apiKey: String
    public let baseURL: String?
    public let route: AIImageRouteKind
    public let sourceSlot: AIImageConnectionSourceSlot
    public let requireAggregatorHost: Bool

    public init(
        apiKey: String,
        baseURL: String?,
        route: AIImageRouteKind,
        sourceSlot: AIImageConnectionSourceSlot,
        requireAggregatorHost: Bool
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.route = route
        self.sourceSlot = sourceSlot
        self.requireAggregatorHost = requireAggregatorHost
    }
}

public struct AIImageManagedSelectionResolution: Equatable, Sendable {
    public let catalogModel: WuMindCatalogModel?
    public let displayModel: AIImageTool.Model

    public init(catalogModel: WuMindCatalogModel?, displayModel: AIImageTool.Model) {
        self.catalogModel = catalogModel
        self.displayModel = displayModel
    }
}

public enum AIImageStudioAvailability {
    /// Finds a matching enabled gateway model for a studio model ID (exact case-insensitive match).
    public static func matchingManagedModel(
        for modelID: String,
        enabledManagedImageModels: [WuMindCatalogModel]
    ) -> WuMindCatalogModel? {
        let target = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return nil }
        return enabledManagedImageModels.first { $0.id.lowercased() == target && $0.isCallable }
            ?? enabledManagedImageModels.first { $0.id.lowercased() == target && $0.enabled }
    }

    private static func studioModel(for catalogModel: WuMindCatalogModel) -> AIImageTool.Model {
        if let known = AIImageTool.models.first(where: { $0.id.lowercased() == catalogModel.id.lowercased() }) {
            return known
        }
        let lower = catalogModel.id.lowercased()
        let inferredProvider: AIProvider = lower.contains("gemini") || lower.contains("imagen")
            ? .gemini
            : (lower.contains("grok") ? .grok : .openAI)
        return AIImageTool.Model(
            id: catalogModel.id,
            displayName: catalogModel.displayName,
            provider: inferredProvider,
            supportsReferenceImage: catalogModel.supportsImageEdit
        )
    }

    /// Resolves the active Managed Mode selection WITHOUT EVER silently substituting `enabledManagedImageModels.first`
    /// when the user explicitly selected a model (e.g. Nano Banana 2) that is absent from the managed catalog!
    public static func resolveManagedSelection(
        requestedModelID: String?,
        fallbackModel: AIImageTool.Model?,
        enabledManagedImageModels: [WuMindCatalogModel]
    ) -> AIImageManagedSelectionResolution {
        let trimmedID = requestedModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedID.isEmpty {
            if let hit = matchingManagedModel(for: trimmedID, enabledManagedImageModels: enabledManagedImageModels) {
                return AIImageManagedSelectionResolution(catalogModel: hit, displayModel: studioModel(for: hit))
            }
            if let known = AIImageTool.models.first(where: { $0.id.lowercased() == trimmedID.lowercased() }) {
                return AIImageManagedSelectionResolution(catalogModel: nil, displayModel: known)
            }
            if let fallbackModel, fallbackModel.id.lowercased() == trimmedID.lowercased() {
                return AIImageManagedSelectionResolution(catalogModel: nil, displayModel: fallbackModel)
            }
            let lower = trimmedID.lowercased()
            let inferredProvider: AIProvider = lower.contains("gemini") || lower.contains("imagen")
                ? .gemini
                : (lower.contains("grok") ? .grok : .openAI)
            return AIImageManagedSelectionResolution(
                catalogModel: nil,
                displayModel: AIImageTool.Model(id: trimmedID, displayName: trimmedID, provider: inferredProvider, supportsReferenceImage: false)
            )
        }

        if let fallbackModel {
            if let hit = matchingManagedModel(for: fallbackModel.id, enabledManagedImageModels: enabledManagedImageModels) {
                return AIImageManagedSelectionResolution(catalogModel: hit, displayModel: studioModel(for: hit))
            }
            // Keep the explicitly selected fallback model so UI shows "model unavailable" instead of silently replacing it with list.first!
            return AIImageManagedSelectionResolution(catalogModel: nil, displayModel: fallbackModel)
        }

        // Only when there is ZERO prior selection at all may we default to the first enabled catalog model.
        if let first = enabledManagedImageModels.first {
            return AIImageManagedSelectionResolution(catalogModel: first, displayModel: studioModel(for: first))
        }
        return AIImageManagedSelectionResolution(catalogModel: nil, displayModel: AIImageTool.models[0])
    }

    /// Single source of truth for Model Center, Studio Model Picker, Status Banner, and Generate Button.
    public static func evaluate(
        model: AIImageTool.Model,
        hasReferenceImage: Bool,
        snapshot: AIImageCredentialSnapshot
    ) -> AIImageAvailabilityState {
        // PATH 1: WuMind 内置 (Managed Gateway) — strictly driven by Gateway catalog; NEVER checks local vendor keys!
        if snapshot.useManagedGateway {
            guard snapshot.isGatewayConfigured else {
                return .managedGatewayConfigInvalid(
                    detail: "当前已选择 WuMind 内置，但网关地址未配置或格式无效（需 https:// 域名）。请前往设置修复 WuMind 网关配置，不会跳到配置 Google Gemini / 厂商 Key，也不会静默切至自有 API。"
                )
            }
            guard snapshot.isGatewayLoggedIn else {
                return .managedLoginRequired(detail: "当前为 WuMind 内置模式，请先登录或激活 WuMind 账号后使用内置余额出图（无需配置本机厂商 Key）。")
            }
            if let managed = matchingManagedModel(for: model.id, enabledManagedImageModels: snapshot.enabledManagedImageModels) {
                if hasReferenceImage && !managed.supportsImageEdit {
                    return .referenceImageUnsupported(route: .managedGateway, modelName: managed.displayName)
                }
                if !hasReferenceImage && !managed.supportsTextToImage {
                    return .managedModelNotEnabled(
                        modelID: model.id,
                        modelName: managed.displayName,
                        hasOtherManagedModels: snapshot.enabledManagedImageModels.contains(where: \.supportsTextToImage)
                    )
                }
                let priceText = managed.unitPriceYuan > 0 ? String(format: "¥%.3f/张", managed.unitPriceYuan) : "内置计费"
                return .ready(
                    route: .managedGateway,
                    routeBadge: AIImageRouteKind.managedGateway.badgeText,
                    detail: "\(managed.displayName) · \(priceText) · 走服务端通道",
                    sourceSlot: nil,
                    managedCatalogModel: managed
                )
            }
            if snapshot.isGatewayCatalogSyncing && snapshot.enabledManagedImageModels.isEmpty {
                return .managedCatalogSyncing(routeBadge: AIImageRouteKind.managedGateway.badgeText)
            }
            return .managedModelNotEnabled(
                modelID: model.id,
                modelName: model.shortStudioName,
                hasOtherManagedModels: !snapshot.enabledManagedImageModels.isEmpty
            )
        }

        // PATH 2: 自有 API — decouples connection (AIHubMix vs Direct Vendor) from model vendor!
        let shouldUseAIHubMix: Bool = {
            switch snapshot.ownPreference {
            case .aihubmix:
                return true
            case .directVendor:
                return false
            case .auto:
                if let conn = snapshot.aihubmixConnection, conn.isSafeAggregatorHost {
                    return true
                }
                return false
            }
        }()

        if shouldUseAIHubMix {
            if let conn = snapshot.aihubmixConnection, conn.isSafeAggregatorHost {
                if hasReferenceImage && !model.supportsReferenceImage {
                    return .referenceImageUnsupported(route: .ownAIHubMix, modelName: model.shortStudioName)
                }
                return .ready(
                    route: .ownAIHubMix,
                    routeBadge: AIImageRouteKind.ownAIHubMix.badgeText,
                    detail: "\(conn.resolvedHost) · \(conn.sourceSlot.shortLabel) · 0 扣 WuMind 余额",
                    sourceSlot: conn.sourceSlot,
                    managedCatalogModel: nil
                )
            }
            return .missingConnection(
                route: .ownAIHubMix,
                title: "需配置 AIHubMix 连接",
                detail: "保存一次 AIHubMix Base URL 与 API Key，即可在画室同时调用 GPT Image 与 Nano Banana 2，无需按厂商重复填写 Key。",
                action: .configureAIHubMix
            )
        }

        // Direct vendor slot (preserves existing official vendor keys; detects if that slot itself points to AIHubMix)
        if snapshot.directProviderKeys.contains(model.provider) {
            let slotBaseURL = snapshot.directProviderBaseURLs[model.provider]
            let isSlotRelay = AIProviderToolHTTP.isOpenAICompatibleRelay(slotBaseURL)
            let route: AIImageRouteKind = isSlotRelay ? .ownAIHubMix : .ownDirectVendor
            if hasReferenceImage && !model.supportsReferenceImage {
                return .referenceImageUnsupported(route: route, modelName: model.shortStudioName)
            }
            let host = model.provider.resolvedHost(baseURL: slotBaseURL)
            return .ready(
                route: route,
                routeBadge: route.badgeText,
                detail: "\(host) · \(isSlotRelay ? "聚合中转" : model.provider.displayName) · 0 扣 WuMind 余额",
                sourceSlot: .directVendor,
                managedCatalogModel: nil
            )
        }

        return .missingConnection(
            route: .ownDirectVendor,
            title: "需配置连接（AIHubMix 或 \(model.provider.displayName)）",
            detail: "推荐配置一套 AIHubMix 连接同时调用 GPT Image 与 Nano Banana 2，或配置 \(model.provider.displayName) 官方 API Key。",
            action: snapshot.aihubmixConnection != nil ? .configureAIHubMix : .configureDirectVendor(model.provider)
        )
    }

    /// Resolves the concrete Own-API execution target while enforcing strict domain isolation.
    public static func resolveOwnExecutionTarget(
        model: AIImageTool.Model,
        snapshot: AIImageCredentialSnapshot,
        directAPIKeyProvider: (AIProvider) -> String?
    ) -> AIImageOwnExecutionTarget? {
        guard !snapshot.useManagedGateway else { return nil }

        let preferAIHubMix: Bool = {
            switch snapshot.ownPreference {
            case .aihubmix: return true
            case .directVendor: return false
            case .auto: return snapshot.aihubmixConnection?.isSafeAggregatorHost == true
            }
        }()

        if preferAIHubMix {
            guard let conn = snapshot.aihubmixConnection, conn.isSafeAggregatorHost else { return nil }
            return AIImageOwnExecutionTarget(
                apiKey: conn.apiKey,
                baseURL: conn.baseURL,
                route: .ownAIHubMix,
                sourceSlot: conn.sourceSlot,
                requireAggregatorHost: true
            )
        }

        guard let rawKey = directAPIKeyProvider(model.provider)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawKey.isEmpty else {
            return nil
        }
        let baseURL = snapshot.directProviderBaseURLs[model.provider]
        let isRelay = AIProviderToolHTTP.isOpenAICompatibleRelay(baseURL)
        return AIImageOwnExecutionTarget(
            apiKey: rawKey,
            baseURL: baseURL,
            route: isRelay ? .ownAIHubMix : .ownDirectVendor,
            sourceSlot: .directVendor,
            requireAggregatorHost: isRelay
        )
    }
}

/// Deterministic 5+2 error categories for Image Studio UI & sanitized diagnostics.
public enum AIImageErrorCategory: String, Codable, Equatable, Hashable, Sendable {
    case missingConnection
    case modelNotEnabled
    case insufficientWuMindBalance
    case insufficientUpstreamBalance
    case authFailed
    case networkTimeout
    case apiError

    public var label: String {
        switch self {
        case .missingConnection: return "缺连接"
        case .modelNotEnabled: return "模型未开通"
        case .insufficientWuMindBalance: return "WuMind 余额不足"
        case .insufficientUpstreamBalance: return "上游余额不足"
        case .authFailed: return "鉴权失败"
        case .networkTimeout: return "网络超时"
        case .apiError: return "接口错误"
        }
    }
}

public struct AIImageClassifiedError: Equatable, Sendable {
    public let category: AIImageErrorCategory
    public let title: String
    public let message: String
    public let httpStatus: Int?
    public let isRetryableWithSameIdempotencyKey: Bool

    public init(
        category: AIImageErrorCategory,
        title: String,
        message: String,
        httpStatus: Int? = nil,
        isRetryableWithSameIdempotencyKey: Bool = false
    ) {
        self.category = category
        self.title = title
        self.message = message
        self.httpStatus = httpStatus
        self.isRetryableWithSameIdempotencyKey = isRetryableWithSameIdempotencyKey
    }
}

public enum AIImageErrorClassifier {
    public static func classify(error: Error, route: AIImageRouteKind) -> AIImageClassifiedError {
        if let gwErr = error as? WuMindGatewayClient.GatewayError {
            switch gwErr {
            case .invalidGatewayURL:
                return AIImageClassifiedError(
                    category: .missingConnection,
                    title: "缺连接",
                    message: gwErr.localizedDescription,
                    httpStatus: nil,
                    isRetryableWithSameIdempotencyKey: false
                )
            case .unauthorized:
                return AIImageClassifiedError(
                    category: .authFailed,
                    title: "鉴权失败",
                    message: "WuMind 账号凭证已过期或无效，请重新登录 WuMind 账号。",
                    httpStatus: 401,
                    isRetryableWithSameIdempotencyKey: false
                )
            case .insufficientBalance:
                return AIImageClassifiedError(
                    category: .insufficientWuMindBalance,
                    title: "WuMind 余额不足",
                    message: gwErr.localizedDescription,
                    httpStatus: 402,
                    isRetryableWithSameIdempotencyKey: false
                )
            case .upstreamBalanceInsufficient(let msg):
                return AIImageClassifiedError(
                    category: .insufficientUpstreamBalance,
                    title: "上游 API 余额不足",
                    message: msg,
                    httpStatus: 502,
                    isRetryableWithSameIdempotencyKey: false
                )
            case .modelNotEnabled(let msg):
                return AIImageClassifiedError(
                    category: .modelNotEnabled,
                    title: "模型未开通",
                    message: msg,
                    httpStatus: 403,
                    isRetryableWithSameIdempotencyKey: false
                )
            case .upstreamAuthFailed(let msg):
                return AIImageClassifiedError(
                    category: .authFailed,
                    title: "上游鉴权失败",
                    message: msg,
                    httpStatus: 502,
                    isRetryableWithSameIdempotencyKey: false
                )
            case .network:
                return AIImageClassifiedError(
                    category: .networkTimeout,
                    title: "网络异常 / 超时",
                    message: "与 WuMind 网关通信中断。点击重试将自动复用原幂等键，不会重复生图或重复扣费。",
                    httpStatus: nil,
                    isRetryableWithSameIdempotencyKey: true
                )
            case .invalidResponse, .objectStorageUnconfigured, .serverMessage, .modelRefused:
                return AIImageClassifiedError(
                    category: .apiError,
                    title: "接口错误",
                    message: gwErr.localizedDescription,
                    httpStatus: nil,
                    isRetryableWithSameIdempotencyKey: false
                )
            }
        }

        if let diagErr = error as? AIProviderToolDiagnosticError {
            let lowerMsg = (diagErr.upstreamMessage ?? "").lowercased()
            let lowerCode = (diagErr.upstreamCode ?? "").lowercased()
            if lowerCode.contains("insufficient") || lowerMsg.contains("insufficient") || lowerMsg.contains("quota") || lowerMsg.contains("balance") {
                return AIImageClassifiedError(
                    category: .insufficientUpstreamBalance,
                    title: route == .ownAIHubMix ? "AIHubMix 余额不足" : "厂商账户余额不足",
                    message: diagErr.localizedDescription,
                    httpStatus: diagErr.statusCode,
                    isRetryableWithSameIdempotencyKey: false
                )
            }
            if diagErr.statusCode == 401 || diagErr.statusCode == 403 {
                if lowerCode.contains("model") || lowerMsg.contains("not allowed") || lowerMsg.contains("not enabled") || lowerMsg.contains("not_enabled") {
                    return AIImageClassifiedError(
                        category: .modelNotEnabled,
                        title: "模型未开通",
                        message: diagErr.localizedDescription,
                        httpStatus: diagErr.statusCode,
                        isRetryableWithSameIdempotencyKey: false
                    )
                }
                return AIImageClassifiedError(
                    category: .authFailed,
                    title: "鉴权失败",
                    message: diagErr.localizedDescription,
                    httpStatus: diagErr.statusCode,
                    isRetryableWithSameIdempotencyKey: false
                )
            }
            if diagErr.statusCode == 404 {
                return AIImageClassifiedError(
                    category: .modelNotEnabled,
                    title: "模型未开通 / 不可用",
                    message: diagErr.localizedDescription,
                    httpStatus: 404,
                    isRetryableWithSameIdempotencyKey: false
                )
            }
            return AIImageClassifiedError(
                category: .apiError,
                title: "接口错误",
                message: diagErr.localizedDescription,
                httpStatus: diagErr.statusCode,
                isRetryableWithSameIdempotencyKey: diagErr.statusCode >= 500
            )
        }

        if let aiErr = error as? MultiProviderAIError {
            switch aiErr {
            case .missingKey:
                return AIImageClassifiedError(category: .missingConnection, title: "缺连接", message: aiErr.localizedDescription, httpStatus: nil, isRetryableWithSameIdempotencyKey: false)
            case .invalidCredential, .forbidden:
                return AIImageClassifiedError(category: .authFailed, title: "鉴权失败", message: aiErr.localizedDescription, httpStatus: aiErr == .invalidCredential ? 401 : 403, isRetryableWithSameIdempotencyKey: false)
            case .quota:
                return AIImageClassifiedError(
                    category: .insufficientUpstreamBalance,
                    title: route == .ownAIHubMix ? "AIHubMix 余额不足" : "厂商余额不足",
                    message: aiErr.localizedDescription,
                    httpStatus: 402,
                    isRetryableWithSameIdempotencyKey: false
                )
            case .unsupportedModel:
                return AIImageClassifiedError(category: .modelNotEnabled, title: "模型未开通", message: aiErr.localizedDescription, httpStatus: 404, isRetryableWithSameIdempotencyKey: false)
            case .timedOut, .networkError:
                return AIImageClassifiedError(
                    category: .networkTimeout,
                    title: "网络超时",
                    message: aiErr.localizedDescription,
                    httpStatus: nil,
                    isRetryableWithSameIdempotencyKey: true
                )
            default:
                return AIImageClassifiedError(category: .apiError, title: "接口错误", message: aiErr.localizedDescription, httpStatus: nil, isRetryableWithSameIdempotencyKey: false)
            }
        }

        if let toolErr = error as? AIImageToolError {
            switch toolErr {
            case .domainIsolationBlocked:
                return AIImageClassifiedError(category: .authFailed, title: "安全域名隔离拦截", message: toolErr.localizedDescription, httpStatus: nil, isRetryableWithSameIdempotencyKey: false)
            default:
                return AIImageClassifiedError(category: .apiError, title: "接口错误", message: toolErr.localizedDescription, httpStatus: nil, isRetryableWithSameIdempotencyKey: false)
            }
        }

        if let urlErr = error as? URLError, urlErr.code == .timedOut || urlErr.code == .networkConnectionLost || urlErr.code == .notConnectedToInternet {
            return AIImageClassifiedError(
                category: .networkTimeout,
                title: "网络超时",
                message: "请求超时或连接断开。重试将复用原幂等键，不会重复扣费。",
                httpStatus: nil,
                isRetryableWithSameIdempotencyKey: true
            )
        }

        return AIImageClassifiedError(
            category: .apiError,
            title: "接口错误",
            message: MultiProviderAIClient.redactSecrets(in: error.localizedDescription),
            httpStatus: nil,
            isRetryableWithSameIdempotencyKey: false
        )
    }
}

/// Strictly sanitized diagnostic log entry: retains ONLY requestID, model, route, statusCode, and billingResult.
/// NEVER stores API keys, user prompts, or reference image payloads.
public struct AIImageRequestDiagnostic: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let requestID: String
    public let timestamp: Date
    public let route: AIImageRouteKind
    public let routeBadge: String
    public let modelID: String
    public let mode: String
    public let endpointDisplay: String
    public let httpStatus: Int?
    public let errorCategory: AIImageErrorCategory?
    public let billingResult: String
    public let idempotencyKeyPrefix: String?
    public let succeeded: Bool

    public static func sanitized(
        requestID: String,
        route: AIImageRouteKind,
        modelID: String,
        mode: String,
        endpointDisplay: String,
        httpStatus: Int?,
        errorCategory: AIImageErrorCategory?,
        billingResult: String,
        idempotencyKey: String? = nil,
        succeeded: Bool,
        timestamp: Date = Date()
    ) -> AIImageRequestDiagnostic {
        // Strip any query string & redact any token-like substring defensively
        let cleanEndpoint = MultiProviderAIClient.redactSecrets(
            in: endpointDisplay.components(separatedBy: "?").first ?? endpointDisplay
        )
        let cleanBilling = MultiProviderAIClient.redactSecrets(in: billingResult)
        let cleanReqID = MultiProviderAIClient.redactSecrets(in: requestID)
        let prefix = idempotencyKey.map { String($0.prefix(16)) }
        return AIImageRequestDiagnostic(
            id: "\(cleanReqID)-\(Int(timestamp.timeIntervalSince1970 * 1000))",
            requestID: cleanReqID,
            timestamp: timestamp,
            route: route,
            routeBadge: route.badgeText,
            modelID: modelID,
            mode: mode,
            endpointDisplay: cleanEndpoint,
            httpStatus: httpStatus,
            errorCategory: errorCategory,
            billingResult: cleanBilling,
            idempotencyKeyPrefix: prefix,
            succeeded: succeeded
        )
    }
}
