import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Dynamic Model Catalog Types

public struct WuMindCatalogSupportedParams: Codable, Equatable, Hashable, Sendable {
    public var supportsVision: Bool?
    public var sizes: [String]?
    public var qualities: [String]?
    public var seconds: [Int]?
    public var defaultSeconds: Int?
    public var defaultSize: String?
    public var maxRefImages: Int?
    public var protocolName: String?

    enum CodingKeys: String, CodingKey {
        case supportsVision
        case sizes
        case qualities
        case seconds
        case defaultSeconds
        case defaultSize
        case maxRefImages
        case protocolName = "protocol"
    }

    public init(
        supportsVision: Bool? = nil,
        sizes: [String]? = nil,
        qualities: [String]? = nil,
        seconds: [Int]? = nil,
        defaultSeconds: Int? = nil,
        defaultSize: String? = nil,
        maxRefImages: Int? = nil,
        protocolName: String? = nil
    ) {
        self.supportsVision = supportsVision
        self.sizes = sizes
        self.qualities = qualities
        self.seconds = seconds
        self.defaultSeconds = defaultSeconds
        self.defaultSize = defaultSize
        self.maxRefImages = maxRefImages
        self.protocolName = protocolName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.supportsVision = try? c.decode(Bool.self, forKey: .supportsVision)
        self.sizes = try? c.decode([String].self, forKey: .sizes)
        self.qualities = try? c.decode([String].self, forKey: .qualities)
        if let intArr = try? c.decode([Int].self, forKey: .seconds) {
            self.seconds = intArr
        } else if let strArr = try? c.decode([String].self, forKey: .seconds) {
            let parsed = strArr.compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            self.seconds = parsed.isEmpty ? nil : parsed
        } else {
            self.seconds = nil
        }
        if let intVal = try? c.decode(Int.self, forKey: .defaultSeconds) {
            self.defaultSeconds = intVal
        } else if let strVal = try? c.decode(String.self, forKey: .defaultSeconds) {
            self.defaultSeconds = Int(strVal.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            self.defaultSeconds = nil
        }
        self.defaultSize = try? c.decode(String.self, forKey: .defaultSize)
        self.maxRefImages = try? c.decode(Int.self, forKey: .maxRefImages)
        self.protocolName = try? c.decode(String.self, forKey: .protocolName)
    }
}

public struct WuMindCatalogModel: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var upstreamProvider: String?
    public var provider: String?
    public var vendor: String?
    public var displayName: String
    public var capabilities: [String]
    public var pricingMode: String
    public var inputPricePerMillion: Double
    public var outputPricePerMillion: Double
    public var cachePricePerMillion: Double?
    public var unitPriceYuan: Double
    public var officialInputUSDPerMillion: Double?
    public var officialOutputUSDPerMillion: Double?
    public var officialCacheUSDPerMillion: Double?
    public var officialUnitUSD: Double?
    public var fxUsdToCny: Double?
    public var markupMultiplier: Double?
    public var pricingStatus: String?
    public var priceVersion: Int?
    public var lastSyncedAt: String?
    public var officialReferenceNote: String?
    public var supportsThinking: Bool?
    public var supportsReferenceImage: Bool?
    public var supportedParams: WuMindCatalogSupportedParams?
    public var enabled: Bool
    public var probeStatus: String
    public var probeEndpoint: String?
    public var probeMessage: String?
    public var probeLatencyMs: Int?
    public var lastProbedAt: String?
    public var discoveredFrom: String?
    public var deprecated: Bool?
    public var updatedAt: String?

    public var resolvedProvider: String { upstreamProvider ?? provider ?? "aihubmix" }
    public var resolvedVendor: String { vendor ?? resolvedProvider }
    public var supportsChat: Bool { capabilities.contains("chat") }
    public var supportsTextToImage: Bool { capabilities.contains("text_to_image") }
    public var supportsImageEdit: Bool { capabilities.contains("image_edit") || supportsReferenceImage == true }
    public var supportsVideo: Bool { capabilities.contains("video") }
    public var supportsRealtimeVoice: Bool { capabilities.contains("realtime_voice") }
    public var isDeprecated: Bool { deprecated == true }
    public var isVerified: Bool { probeStatus == "verified" }
    public var isPendingPricing: Bool { pricingStatus == "pending_pricing" || !isPriced }
    public var isPriced: Bool {
        if pricingMode == "token" {
            return inputPricePerMillion > 0 || outputPricePerMillion > 0
        }
        return unitPriceYuan > 0
    }
    public var isCallable: Bool { enabled && !isDeprecated && isVerified && isPriced }

    public var billingUnitLabel: String {
        switch pricingMode {
        case "per_image": return "按张"
        case "per_second": return "按秒"
        case "per_minute": return "按分钟"
        case "per_video": return "按条"
        default: return "百万 Token"
        }
    }

    public var officialPriceSummary: String {
        if pricingMode == "token" {
            if let inU = officialInputUSDPerMillion, let outU = officialOutputUSDPerMillion, inU > 0 || outU > 0 {
                if let cU = officialCacheUSDPerMillion, cU > 0 {
                    return String(format: "官方 $%.2f / $%.2f (缓存 $%.2f)", inU, outU, cU)
                }
                return String(format: "官方 $%.2f / $%.2f", inU, outU)
            }
            return "官方价待补充"
        }
        if let uU = officialUnitUSD, uU > 0 {
            let suffix = pricingMode == "per_second" ? "/秒" : pricingMode == "per_minute" ? "/分" : "/张"
            return String(format: "官方 $%.3f%@", uU, suffix)
        }
        return "官方价待补充"
    }

    public var pricingSummary: String {
        if isPendingPricing {
            return "待定价（不可启用）"
        }
        if pricingMode == "per_image" {
            return String(format: "¥%.3f / 张", unitPriceYuan)
        }
        if pricingMode == "per_second" {
            return String(format: "¥%.3f / 秒", unitPriceYuan)
        }
        if pricingMode == "per_minute" {
            return String(format: "¥%.2f / 分", unitPriceYuan)
        }
        if pricingMode == "per_video" {
            return String(format: "¥%.2f / 条", unitPriceYuan)
        }
        if let c = cachePricePerMillion, c > 0 {
            return String(format: "入 ¥%.2f / 出 ¥%.2f / 缓存 ¥%.2f", inputPricePerMillion, outputPricePerMillion, c)
        }
        return String(format: "入 ¥%.2f / 出 ¥%.2f (百万Token)", inputPricePerMillion, outputPricePerMillion)
    }

    public var probeStatusTitle: String {
        switch probeStatus {
        case "verified": return "能力已验证"
        case "permission_denied": return "权限不足"
        case "unsupported_params": return "协议/参数不兼容"
        case "deprecated": return "已下线"
        case "error": return "实测失败"
        default: return "目录可见（待实测）"
        }
    }

    public init(
        id: String,
        upstreamProvider: String? = "aihubmix",
        provider: String? = nil,
        vendor: String? = nil,
        displayName: String,
        capabilities: [String] = ["chat"],
        pricingMode: String = "token",
        inputPricePerMillion: Double = 0,
        outputPricePerMillion: Double = 0,
        cachePricePerMillion: Double? = nil,
        unitPriceYuan: Double = 0,
        officialInputUSDPerMillion: Double? = nil,
        officialOutputUSDPerMillion: Double? = nil,
        officialCacheUSDPerMillion: Double? = nil,
        officialUnitUSD: Double? = nil,
        fxUsdToCny: Double? = nil,
        markupMultiplier: Double? = nil,
        pricingStatus: String? = nil,
        priceVersion: Int? = nil,
        lastSyncedAt: String? = nil,
        officialReferenceNote: String? = nil,
        supportsThinking: Bool? = false,
        supportsReferenceImage: Bool? = false,
        supportedParams: WuMindCatalogSupportedParams? = nil,
        enabled: Bool = false,
        probeStatus: String = "unverified",
        probeEndpoint: String? = nil,
        probeMessage: String? = nil,
        probeLatencyMs: Int? = nil,
        lastProbedAt: String? = nil,
        discoveredFrom: String? = nil,
        deprecated: Bool? = false,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.upstreamProvider = upstreamProvider
        self.provider = provider ?? upstreamProvider
        self.vendor = vendor
        self.displayName = displayName
        self.capabilities = capabilities
        self.pricingMode = pricingMode
        self.inputPricePerMillion = inputPricePerMillion
        self.outputPricePerMillion = outputPricePerMillion
        self.cachePricePerMillion = cachePricePerMillion
        self.unitPriceYuan = unitPriceYuan
        self.officialInputUSDPerMillion = officialInputUSDPerMillion
        self.officialOutputUSDPerMillion = officialOutputUSDPerMillion
        self.officialCacheUSDPerMillion = officialCacheUSDPerMillion
        self.officialUnitUSD = officialUnitUSD
        self.fxUsdToCny = fxUsdToCny
        self.markupMultiplier = markupMultiplier
        self.pricingStatus = pricingStatus
        self.priceVersion = priceVersion
        self.lastSyncedAt = lastSyncedAt
        self.officialReferenceNote = officialReferenceNote
        self.supportsThinking = supportsThinking
        self.supportsReferenceImage = supportsReferenceImage
        self.supportedParams = supportedParams
        self.enabled = enabled
        self.probeStatus = probeStatus
        self.probeEndpoint = probeEndpoint
        self.probeMessage = probeMessage
        self.probeLatencyMs = probeLatencyMs
        self.lastProbedAt = lastProbedAt
        self.discoveredFrom = discoveredFrom
        self.deprecated = deprecated
        self.updatedAt = updatedAt
    }
}

public struct WuMindPricingMeta: Codable, Equatable, Sendable {
    public let markupMultiplier: Double
    public let fxUsdToCny: Double
    public let priceVersion: Int
    public let lastSyncedAt: String?
    public let sourceURL: String?
    public let pricedCount: Int?
    public let pendingPricingCount: Int?
}

public struct WuMindPricingSyncSummary: Codable, Equatable, Sendable {
    public let total: Int
    public let changed: Int
    public let unchanged: Int
    public let pendingPricing: Int
}

public struct WuMindPricingDiffItem: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let vendor: String
    public let capabilities: [String]
    public let pricingMode: String
    public let probeStatus: String
    public let enabled: Bool
    public let changed: Bool
    public let pricingStatus: String
    public let officialInputUSD: Double?
    public let officialOutputUSD: Double?
    public let officialCacheUSD: Double?
    public let officialUnitUSD: Double?
    public let oldInputPricePerMillion: Double
    public let newInputPricePerMillion: Double
    public let oldOutputPricePerMillion: Double
    public let newOutputPricePerMillion: Double
    public let oldCachePricePerMillion: Double?
    public let newCachePricePerMillion: Double?
    public let oldUnitPriceYuan: Double
    public let newUnitPriceYuan: Double
    public let officialReferenceNote: String?
}

public struct WuMindPricingPreviewResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let currentVersion: Int
    public let nextVersion: Int
    public let fxUsdToCny: Double
    public let markupMultiplier: Double
    public let sourceURL: String?
    public let summary: WuMindPricingSyncSummary
    public let diffs: [WuMindPricingDiffItem]
}

public struct WuMindPricingApproveResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let priceVersion: Int
    public let syncedAt: String?
    public let fxUsdToCny: Double
    public let markupMultiplier: Double
    public let sourceURL: String?
    public let summary: WuMindPricingSyncSummary
}

public struct WuMindCatalogProviderReport: Codable, Equatable, Sendable {
    public let provider: String
    public let configured: Bool
    public let discovered: Int
    public let note: String?
}

public struct WuMindCatalogDiscoveryResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let totalDiscovered: Int
    public let totalDeprecated: Int
    public let providerReports: [WuMindCatalogProviderReport]
    public let models: [WuMindCatalogModel]
}

public struct WuMindCatalogListResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let configuredUpstreams: [String]
    public let legacyAIHubMixAllowlist: [String]?
    public let pricingMeta: WuMindPricingMeta?
    public let page: Int?
    public let limit: Int?
    public let totalCount: Int
    public let totalPages: Int?
    public let hasMore: Bool?
    public let enabledVerifiedCount: Int
    public let models: [WuMindCatalogModel]
}

public struct WuMindCatalogProbeResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let results: [WuMindCatalogModel]
}

public struct WuMindCatalogBatchRejected: Codable, Equatable, Sendable {
    public let id: String
    public let code: String
    public let reason: String
}

public struct WuMindCatalogBatchUpdateResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let appliedCount: Int
    public let rejectedCount: Int
    public let applied: [WuMindCatalogModel]
    public let rejected: [WuMindCatalogBatchRejected]
}

public struct WuMindCatalogUpdatePatch: Encodable, Equatable, Sendable {
    public let id: String
    public var displayName: String?
    public var inputPricePerMillion: Double?
    public var outputPricePerMillion: Double?
    public var unitPriceYuan: Double?
    public var officialReferenceNote: String?
    public var enabled: Bool?

    public init(
        id: String,
        displayName: String? = nil,
        inputPricePerMillion: Double? = nil,
        outputPricePerMillion: Double? = nil,
        unitPriceYuan: Double? = nil,
        officialReferenceNote: String? = nil,
        enabled: Bool? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.inputPricePerMillion = inputPricePerMillion
        self.outputPricePerMillion = outputPricePerMillion
        self.unitPriceYuan = unitPriceYuan
        self.officialReferenceNote = officialReferenceNote
        self.enabled = enabled
    }
}

public struct WuMindPublicModelsResponse: Codable, Equatable, Sendable {
    public let ok: Bool?
    public let models: [WuMindCatalogModel]
}

// MARK: - Admin Registry, User Detail, Fee-Waiver & AIHubMix Pool Balance

public struct WuMindAdminUserRecord: Codable, Identifiable, Equatable, Sendable {
    public let userID: String
    public let displayName: String
    public let registeredRole: String?
    public let balanceYuan: Double
    public let reservedYuan: Double?
    public let availableYuan: Double?
    public let sandboxBalanceYuan: Double?
    public let totalRechargedYuan: Double
    public let purchasedRechargedYuan: Double?
    public let adminGrantedYuan: Double?
    public let totalSpentYuan: Double
    public let refundedYuan: Double?
    public let upstreamSpentYuan: Double?
    public let billingExempt: Bool?
    public let dailyCostCapYuan: Double?
    public let requestCount: Int?
    public let totalTokens: Int?
    public let lastActivityAt: String?
    public let createdAt: String?

    public var id: String { userID }
    public var isBillingExempt: Bool { billingExempt == true }
}

public struct WuMindAdminUsersResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let totalUsers: Int
    public let allUsersCount: Int?
    public let todayNewUsers: Int?
    public let rechargedUsersCount: Int
    public let page: Int?
    public let limit: Int?
    public let totalPages: Int?
    public let hasMore: Bool?
    public let users: [WuMindAdminUserRecord]
}

public struct WuMindAdminUserUsageBucket: Codable, Equatable, Sendable {
    public let requests: Int
    public let tokens: Int
    public let spentYuan: Double
    public let upstreamYuan: Double
}

public struct WuMindAdminUserUsageSummary: Codable, Equatable, Sendable {
    public let today: WuMindAdminUserUsageBucket
    public let last7Days: WuMindAdminUserUsageBucket
    public let allTime: WuMindAdminUserUsageBucket
}

public struct WuMindAdminUserModelBreakdown: Codable, Identifiable, Equatable, Sendable {
    public let model: String
    public let kind: String
    public let requests: Int
    public let tokens: Int
    public let spentYuan: Double
    public let upstreamYuan: Double

    public var id: String { "\(model)::\(kind)" }
}

public struct WuMindAdminUserKindBreakdown: Codable, Identifiable, Equatable, Sendable {
    public let kind: String
    public let requests: Int
    public let spentYuan: Double
    public let upstreamYuan: Double

    public var id: String { kind }
}

public struct WuMindAdminUserLedgerItem: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let kind: String
    public let provider: String
    public let model: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let reasoningTokens: Int
    public let costYuan: Double
    public let upstreamCostYuan: Double
    public let balanceBeforeYuan: Double?
    public let balanceAfterYuan: Double
    public let environment: String
    public let operatorID: String?
    public let note: String
    public let createdAt: String
}

public struct WuMindAdminUserDetailResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let scope: String?
    public let scopeNote: String?
    public let user: WuMindAdminUserRecord
    public let usageSummary: WuMindAdminUserUsageSummary
    public let breakdownByModel: [WuMindAdminUserModelBreakdown]
    public let breakdownByKind: [WuMindAdminUserKindBreakdown]
    public let recentLedger: [WuMindAdminUserLedgerItem]
    public let recentAdminCredits: [WuMindAdminCreditAuditRow]
}

public struct WuMindAdminLookupMatch: Codable, Identifiable, Equatable, Sendable {
    public let userID: String
    public let displayName: String
    public let balanceYuan: Double
    public let sandboxBalanceYuan: Double?
    public let purchasedRechargedYuan: Double?
    public let adminGrantedYuan: Double?
    public let totalSpentYuan: Double
    public let createdAt: String?
    public var id: String { userID }
}

public struct WuMindAdminUserLookup: Codable, Equatable, Sendable {
    public let found: Bool
    public let multiple: Bool?
    public let user: WuMindAdminUserRecord?
    public let matches: [WuMindAdminLookupMatch]?
    public let recentAdminCredits: [WuMindAdminCreditAuditRow]?
}

public struct WuMindAdminBillingExemptResult: Codable, Equatable, Sendable {
    public let ok: Bool
    public let userID: String
    public let displayName: String
    public let billingExempt: Bool
    public let dailyCostCapYuan: Double
    public let balanceYuan: Double
    public let upstreamSpentYuan: Double
}

public struct WuMindAdminUpstreamBalance: Codable, Equatable, Sendable {
    public let ok: Bool
    public let provider: String
    public let currency: String
    public let configured: Bool
    public let availableUSD: Double?
    public let usedUSD: Double?
    public let accountName: String?
    public let requestCount: Int?
    public let syncedAt: String?
    public let syncFailed: Bool
    public let syncError: String?
    public let statusLabel: String
    public let lowBalanceAlertUSD: Double
    public let alertTriggered: Bool
    public let topUpURL: String
}

// MARK: - Managed Media (Image & Video)

public struct WuMindManagedImageItem: Codable, Equatable, Sendable {
    public let b64_json: String
    public let mime_type: String?
}

public struct WuMindManagedImageTiming: Codable, Equatable, Sendable {
    public let gatewaySubmitMs: Int?
    public let upstreamGenerateMs: Int?
}

public struct WuMindManagedImageResponse: Codable, Equatable, Sendable {
    public let ok: Bool?
    public let workID: String?
    public let model: String
    public let mode: String?
    public let endpoint: String?
    public let timing: WuMindManagedImageTiming?
    public let data: [WuMindManagedImageItem]
    public let billing: WuMindBillingReceipt?
    public let idempotentReplay: Bool?
}

public struct WuMindManagedVideoJob: Codable, Equatable, Sendable {
    public let id: String
    public let workID: String?
    public let upstreamJobID: String?
    public let model: String
    public let endpoint: String?
    public let status: String
    public let progress: Int?
    public let seconds: String?
    public let size: String?
    public let reservedYuan: Double?
    public let adminExempt: Bool?
    public let error: String?
    public let contentPath: String?
    public let billing: WuMindBillingReceipt?
    public let idempotentReplay: Bool?

    public var isCompleted: Bool { status == "completed" }
    public var isFailed: Bool { status == "failed" }
}

// MARK: - Private Cross-Device "My Works" (我的作品)

public enum WuMindWorkType: String, Codable, CaseIterable, Identifiable, Sendable {
    case image
    case video
    case ppt
    case scene3d
    case document
    case code

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .image: return "生图"
        case .video: return "视频"
        case .ppt: return "PPT"
        case .scene3d: return "3D 场景"
        case .document: return "文档"
        case .code: return "代码"
        }
    }
    public var iconName: String {
        switch self {
        case .image: return "photo.on.rectangle.angled"
        case .video: return "film.stack"
        case .ppt: return "rectangle.on.rectangle.angled"
        case .scene3d: return "cube.transparent"
        case .document: return "doc.text.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

public enum WuMindAssetSyncState: String, Codable, Equatable, Sendable {
    case localOnly = "local_only"
    case uploading = "uploading"
    case synced = "synced"
    case failed = "failed"
    case storageUnconfigured = "storage_unconfigured"

    public var badgeTitle: String {
        switch self {
        case .synced: return "原文件已同步"
        case .uploading: return "原文件上传中…"
        case .failed: return "原文件同步失败"
        case .storageUnconfigured: return "仅本机（未配置 R2）"
        case .localOnly: return "仅本机保存"
        }
    }
}

public struct WuMindWorkAssetUploadResult: Codable, Equatable, Sendable {
    public let ok: Bool
    public let workID: String
    public let kind: String?
    public let objectKey: String?
    public let sizeBytes: Int?
    public let sha256: String?
    public let mimeType: String?
    public let assetSyncState: String?
}

public struct WuMindCloudWorkTiming: Codable, Equatable, Sendable {
    public var uploadPrepareMs: Int?
    public var gatewaySubmitMs: Int?
    public var upstreamGenerateMs: Int?
    public var displayRenderMs: Int?
    public var totalMs: Int?

    public init(
        uploadPrepareMs: Int? = nil,
        gatewaySubmitMs: Int? = nil,
        upstreamGenerateMs: Int? = nil,
        displayRenderMs: Int? = nil,
        totalMs: Int? = nil
    ) {
        self.uploadPrepareMs = uploadPrepareMs
        self.gatewaySubmitMs = gatewaySubmitMs
        self.upstreamGenerateMs = upstreamGenerateMs
        self.displayRenderMs = displayRenderMs
        self.totalMs = totalMs
    }
}

public struct WuMindCloudWork: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let userID: String?
    public let workType: String
    public let title: String
    public let prompt: String
    public let modelID: String
    public let params: [String: String]?
    public let status: String
    public let progress: Int
    public let upstreamJobID: String?
    public let idempotencyKey: String?
    public let errorMessage: String?
    public let previewBase64: String?
    public let assetMime: String?
    public let assetObjectKey: String?
    public let assetSizeBytes: Int?
    public let assetSHA256: String?
    public let assetSyncState: String?
    public let objectStorageConfigured: Bool?
    public let hasAsset: Bool?
    public let hasProject: Bool?
    public let assetBase64: String?
    public let projectJSON: String?
    public let timing: WuMindCloudWorkTiming?
    public let versionNumber: Int
    public let parentWorkID: String?
    public let createdAt: String?
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, userID, workType, title, prompt, modelID, params, status, progress
        case upstreamJobID, idempotencyKey, errorMessage, previewBase64, assetMime
        case assetObjectKey, assetSizeBytes, assetSHA256, assetSyncState, objectStorageConfigured
        case hasAsset, hasProject, assetBase64, projectJSON, timing
        case versionNumber, parentWorkID, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userID = try c.decodeIfPresent(String.self, forKey: .userID)
        workType = try c.decode(String.self, forKey: .workType)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        modelID = try c.decodeIfPresent(String.self, forKey: .modelID) ?? ""
        // Tolerantly decode heterogeneous params JSON into string dictionary
        if let rawDict = try? c.decodeIfPresent([String: AnyCodableScalar].self, forKey: .params) {
            params = rawDict.mapValues(\.stringValue)
        } else {
            params = nil
        }
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "queued"
        progress = try c.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        upstreamJobID = try c.decodeIfPresent(String.self, forKey: .upstreamJobID)
        idempotencyKey = try c.decodeIfPresent(String.self, forKey: .idempotencyKey)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        previewBase64 = try c.decodeIfPresent(String.self, forKey: .previewBase64)
        assetMime = try c.decodeIfPresent(String.self, forKey: .assetMime)
        assetObjectKey = try c.decodeIfPresent(String.self, forKey: .assetObjectKey)
        assetSizeBytes = try c.decodeIfPresent(Int.self, forKey: .assetSizeBytes)
        assetSHA256 = try c.decodeIfPresent(String.self, forKey: .assetSHA256)
        assetSyncState = try c.decodeIfPresent(String.self, forKey: .assetSyncState)
        objectStorageConfigured = try c.decodeIfPresent(Bool.self, forKey: .objectStorageConfigured)
        hasAsset = try c.decodeIfPresent(Bool.self, forKey: .hasAsset)
        hasProject = try c.decodeIfPresent(Bool.self, forKey: .hasProject)
        assetBase64 = try c.decodeIfPresent(String.self, forKey: .assetBase64)
        projectJSON = try c.decodeIfPresent(String.self, forKey: .projectJSON)
        timing = try c.decodeIfPresent(WuMindCloudWorkTiming.self, forKey: .timing)
        versionNumber = try c.decodeIfPresent(Int.self, forKey: .versionNumber) ?? 1
        parentWorkID = try c.decodeIfPresent(String.self, forKey: .parentWorkID)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public init(
        id: String,
        userID: String? = nil,
        workType: String,
        title: String,
        prompt: String,
        modelID: String,
        params: [String: String]? = nil,
        status: String = "queued",
        progress: Int = 0,
        upstreamJobID: String? = nil,
        idempotencyKey: String? = nil,
        errorMessage: String? = nil,
        previewBase64: String? = nil,
        assetMime: String? = nil,
        assetObjectKey: String? = nil,
        assetSizeBytes: Int? = nil,
        assetSHA256: String? = nil,
        assetSyncState: String? = nil,
        objectStorageConfigured: Bool? = nil,
        hasAsset: Bool? = nil,
        hasProject: Bool? = nil,
        assetBase64: String? = nil,
        projectJSON: String? = nil,
        timing: WuMindCloudWorkTiming? = nil,
        versionNumber: Int = 1,
        parentWorkID: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.workType = workType
        self.title = title
        self.prompt = prompt
        self.modelID = modelID
        self.params = params
        self.status = status
        self.progress = progress
        self.upstreamJobID = upstreamJobID
        self.idempotencyKey = idempotencyKey
        self.errorMessage = errorMessage
        self.previewBase64 = previewBase64
        self.assetMime = assetMime
        self.assetObjectKey = assetObjectKey
        self.assetSizeBytes = assetSizeBytes
        self.assetSHA256 = assetSHA256
        self.assetSyncState = assetSyncState
        self.objectStorageConfigured = objectStorageConfigured
        self.hasAsset = hasAsset
        self.hasProject = hasProject
        self.assetBase64 = assetBase64
        self.projectJSON = projectJSON
        self.timing = timing
        self.versionNumber = versionNumber
        self.parentWorkID = parentWorkID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

private struct AnyCodableScalar: Decodable {
    let stringValue: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            stringValue = s
        } else if let b = try? c.decode(Bool.self) {
            stringValue = b ? "true" : "false"
        } else if let i = try? c.decode(Int.self) {
            stringValue = String(i)
        } else if let d = try? c.decode(Double.self) {
            stringValue = String(d)
        } else {
            stringValue = ""
        }
    }
}

public struct WuMindWorkEnvelope: Codable, Equatable, Sendable {
    public let ok: Bool
    public let idempotentReplay: Bool?
    public let versionCreated: Bool?
    public let work: WuMindCloudWork
}

public struct WuMindWorksListResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let userID: String?
    public let works: [WuMindCloudWork]
}

// MARK: - WuMindGatewayClient Extended Endpoints & Pure-Swift Account UUID

extension WuMindGatewayClient {
    /// Deterministic RFC 4122 UUID matching Gateway `wumindAccountUUID(userID)` bit-for-bit.
    /// Used as StoreKit 2 `Product.PurchaseOption.appAccountToken` to bind every IAP transaction to a WM- account.
    public static func accountUUID(for userID: String) -> UUID {
        let normalized = userID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let digest = PureSHA256.hash(Array("wumind:iap:account:\(normalized)".utf8))
        var b = Array(digest.prefix(16))
        b[6] = (b[6] & 0x0f) | 0x50
        b[8] = (b[8] & 0x3f) | 0x80
        let tuple: uuid_t = (
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
            b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
        )
        return UUID(uuid: tuple)
    }

    // MARK: Public & Admin Model Catalog

    public func fetchPublicModels(
        gatewayURL: String,
        capability: String? = nil
    ) async throws -> [WuMindCatalogModel] {
        let path: String
        if let cap = capability?.trimmingCharacters(in: .whitespacesAndNewlines), !cap.isEmpty,
           let encoded = cap.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path = "/v1/public/models?capability=\(encoded)"
        } else {
            path = "/v1/public/models"
        }
        let url = try makeURL(base: gatewayURL, path: path)
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "GET"
        let res: WuMindPublicModelsResponse = try await performJSON(req)
        return res.models
    }

    public func adminFetchCatalog(
        gatewayURL: String,
        adminSecret: String,
        vendor: String? = nil,
        provider: String? = nil,
        capability: String? = nil,
        status: String? = nil,
        pricingStatus: String? = nil,
        query: String? = nil,
        page: Int = 1,
        limit: Int = 50
    ) async throws -> WuMindCatalogListResponse {
        var queryItems: [String] = [
            "page=\(max(1, page))",
            "limit=\(max(1, min(200, limit)))",
        ]
        if let v = vendor, !v.isEmpty, let enc = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryItems.append("vendor=\(enc)")
        }
        if let p = provider, !p.isEmpty, let enc = p.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryItems.append("provider=\(enc)")
        }
        if let c = capability, !c.isEmpty, let enc = c.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryItems.append("capability=\(enc)")
        }
        if let s = status, !s.isEmpty, let enc = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryItems.append("status=\(enc)")
        }
        if let ps = pricingStatus, !ps.isEmpty, let enc = ps.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryItems.append("pricingStatus=\(enc)")
        }
        if let q = query?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty,
           let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryItems.append("q=\(enc)")
        }
        let path = "/v1/admin/models?\(queryItems.joined(separator: "&"))"
        let url = try makeURL(base: gatewayURL, path: path)
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        req.httpMethod = "GET"
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        return try await performJSON(req)
    }

    public func adminPreviewPricingSync(
        gatewayURL: String,
        adminSecret: String,
        fxUsdToCny: Double? = nil,
        markupMultiplier: Double = 1.5
    ) async throws -> WuMindPricingPreviewResponse {
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/pricing/preview")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        var body: [String: Any] = ["markupMultiplier": markupMultiplier]
        if let fx = fxUsdToCny, fx > 0 { body["fxUsdToCny"] = fx }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performJSON(req)
    }

    public func adminApprovePricingSync(
        gatewayURL: String,
        adminSecret: String,
        fxUsdToCny: Double? = nil,
        markupMultiplier: Double = 1.5,
        operatorID: String = "admin"
    ) async throws -> WuMindPricingApproveResponse {
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/pricing/approve")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        var body: [String: Any] = [
            "markupMultiplier": markupMultiplier,
            "operatorID": operatorID,
        ]
        if let fx = fxUsdToCny, fx > 0 { body["fxUsdToCny"] = fx }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performJSON(req)
    }

    public func adminDiscoverModels(
        gatewayURL: String,
        adminSecret: String,
        providers: [String]? = nil
    ) async throws -> WuMindCatalogDiscoveryResponse {
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/models/discover")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        let body: [String: Any] = providers.map { ["providers": $0] } ?? [:]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performJSON(req)
    }

    public func adminProbeModels(
        gatewayURL: String,
        adminSecret: String,
        modelIDs: [String]
    ) async throws -> WuMindCatalogProbeResponse {
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/models/probe")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["modelIDs": modelIDs])
        return try await performJSON(req)
    }

    public func adminBatchUpdateModels(
        gatewayURL: String,
        adminSecret: String,
        updates: [WuMindCatalogUpdatePatch]
    ) async throws -> WuMindCatalogBatchUpdateResponse {
        struct Payload: Encodable { let updates: [WuMindCatalogUpdatePatch] }
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/models/batch-update")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        req.httpBody = try JSONEncoder().encode(Payload(updates: updates))
        return try await performJSON(req)
    }

    // MARK: Admin Users, User Detail, Fee-Waiver & AIHubMix Pool Balance

    public func adminLookupUser(
        gatewayURL: String,
        adminSecret: String,
        query: String
    ) async throws -> WuMindAdminUserLookup {
        let encoded = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/users/lookup?q=\(encoded)")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "GET"
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        return try await performJSON(req)
    }

    public func adminListUsers(
        gatewayURL: String,
        adminSecret: String,
        query: String = "",
        page: Int = 1,
        limit: Int = 50
    ) async throws -> WuMindAdminUsersResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var params = [
            "page=\(max(1, page))",
            "limit=\(max(1, min(200, limit)))",
        ]
        if !trimmed.isEmpty, let enc = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            params.append("q=\(enc)")
        }
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/users?\(params.joined(separator: "&"))")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "GET"
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        return try await performJSON(req)
    }

    public func adminFetchUserDetail(
        gatewayURL: String,
        adminSecret: String,
        userID: String
    ) async throws -> WuMindAdminUserDetailResponse {
        let encoded = userID.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userID
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/users/\(encoded)/detail")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        req.httpMethod = "GET"
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        return try await performJSON(req)
    }

    public func adminSetUserBillingExempt(
        gatewayURL: String,
        adminSecret: String,
        userID: String,
        exempt: Bool,
        dailyCostCapYuan: Double? = nil
    ) async throws -> WuMindAdminBillingExemptResult {
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/users/billing-exempt")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        var body: [String: Any] = [
            "userID": userID.trimmingCharacters(in: .whitespacesAndNewlines),
            "exempt": exempt,
        ]
        if let cap = dailyCostCapYuan {
            body["dailyCostCapYuan"] = max(0, cap)
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performJSON(req)
    }

    public func adminFetchUpstreamBalance(
        gatewayURL: String,
        adminSecret: String,
        refresh: Bool = false
    ) async throws -> WuMindAdminUpstreamBalance {
        let path = refresh ? "/v1/admin/upstream-balance?refresh=1" : "/v1/admin/upstream-balance"
        let url = try makeURL(base: gatewayURL, path: path)
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        req.httpMethod = "GET"
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        return try await performJSON(req)
    }

    public func adminRefreshUpstreamBalance(
        gatewayURL: String,
        adminSecret: String
    ) async throws -> WuMindAdminUpstreamBalance {
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/upstream-balance/refresh")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        req.httpMethod = "POST"
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        return try await performJSON(req)
    }

    public func adminSetUpstreamAlertThreshold(
        gatewayURL: String,
        adminSecret: String,
        lowBalanceAlertUSD: Double
    ) async throws -> WuMindAdminUpstreamBalance {
        let url = try makeURL(base: gatewayURL, path: "/v1/admin/upstream-balance/alert")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminSecret, forHTTPHeaderField: "X-WuMind-Admin-Secret")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "lowBalanceAlertUSD": max(0, lowBalanceAlertUSD)
        ])
        return try await performJSON(req)
    }

    // MARK: Managed Media (Image Gen / Reference-Image Edit & Video)

    public func generateManagedImages(
        gatewayURL: String,
        userToken: String,
        modelID: String,
        prompt: String,
        size: String = "1024x1024",
        quality: String = "high",
        n: Int = 1,
        outputFormat: String = "jpeg",
        referenceImage: AIImageTool.ReferenceImage? = nil,
        idempotencyKey: String? = nil
    ) async throws -> WuMindManagedImageResponse {
        let path = referenceImage != nil ? "/v1/images/edits" : "/v1/images/generations"
        let url = try makeURL(base: gatewayURL, path: path)
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        if let idem = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines), !idem.isEmpty {
            req.setValue(String(idem.prefix(96)), forHTTPHeaderField: "Idempotency-Key")
        }
        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt,
            "size": size,
            "quality": quality,
            "n": max(1, min(4, n)),
            "outputFormat": outputFormat,
        ]
        if let ref = referenceImage {
            body["referenceImage"] = [
                "base64Data": ref.data.base64EncodedString(),
                "mimeType": ref.mimeType,
                "filename": ref.filename,
            ]
        }
        if let idem = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines), !idem.isEmpty {
            body["idempotencyKey"] = String(idem.prefix(96))
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performJSON(req, maxBytes: 32 * 1024 * 1024)
    }

    public func submitManagedVideo(
        gatewayURL: String,
        userToken: String,
        modelID: String,
        prompt: String,
        seconds: Int,
        size: String,
        idempotencyKey: String? = nil
    ) async throws -> WuMindManagedVideoJob {
        let url = try makeURL(base: gatewayURL, path: "/v1/videos")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        if let idem = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines), !idem.isEmpty {
            req.setValue(String(idem.prefix(96)), forHTTPHeaderField: "Idempotency-Key")
        }
        var body: [String: Any] = [
            "model": modelID,
            "prompt": prompt,
            "seconds": String(seconds),
            "size": size,
        ]
        if let idem = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines), !idem.isEmpty {
            body["idempotencyKey"] = String(idem.prefix(96))
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performJSON(req)
    }

    public func fetchManagedVideoStatus(
        gatewayURL: String,
        userToken: String,
        jobID: String
    ) async throws -> WuMindManagedVideoJob {
        let encoded = jobID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobID
        let url = try makeURL(base: gatewayURL, path: "/v1/videos/\(encoded)")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.httpMethod = "GET"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        return try await performJSON(req)
    }

    public func downloadManagedVideoContent(
        gatewayURL: String,
        userToken: String,
        jobID: String
    ) async throws -> Data {
        let encoded = jobID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobID
        let url = try makeURL(base: gatewayURL, path: "/v1/videos/\(encoded)/content")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
        req.httpMethod = "GET"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await dataTransport(req)
        guard let http = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
        if http.statusCode == 200 {
            guard data.count > 1024 else { throw GatewayError.invalidResponse }
            return data
        }
        throw Self.mapHTTPError(statusCode: http.statusCode, data: data)
    }

    // MARK: Private Cross-Device "My Works" (我的作品)

    public func listWorks(
        gatewayURL: String,
        userToken: String,
        type: WuMindWorkType? = nil,
        limit: Int = 60
    ) async throws -> [WuMindCloudWork] {
        var params = ["limit=\(max(1, min(100, limit)))"]
        if let t = type {
            params.append("type=\(t.rawValue)")
        }
        let url = try makeURL(base: gatewayURL, path: "/v1/works?\(params.joined(separator: "&"))")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        req.httpMethod = "GET"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        let res: WuMindWorksListResponse = try await performJSON(req, maxBytes: 16 * 1024 * 1024)
        return res.works
    }

    public func createWork(
        gatewayURL: String,
        userToken: String,
        id: String? = nil,
        workType: WuMindWorkType,
        title: String,
        prompt: String,
        modelID: String,
        params: [String: String] = [:],
        status: String = "queued",
        progress: Int = 0,
        upstreamJobID: String? = nil,
        idempotencyKey: String? = nil,
        errorMessage: String? = nil,
        previewBase64: String? = nil,
        assetMime: String? = nil,
        assetBase64: String? = nil,
        projectJSON: String? = nil,
        timing: WuMindCloudWorkTiming? = nil
    ) async throws -> WuMindCloudWork {
        let url = try makeURL(base: gatewayURL, path: "/v1/works")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "workType": workType.rawValue,
            "title": title,
            "prompt": prompt,
            "modelID": modelID,
            "params": params,
            "status": status,
            "progress": progress,
        ]
        if let id, !id.isEmpty { body["id"] = id }
        if let upstreamJobID, !upstreamJobID.isEmpty { body["upstreamJobID"] = upstreamJobID }
        if let idempotencyKey, !idempotencyKey.isEmpty { body["idempotencyKey"] = idempotencyKey }
        if let errorMessage, !errorMessage.isEmpty { body["errorMessage"] = errorMessage }
        if let previewBase64, !previewBase64.isEmpty { body["previewBase64"] = previewBase64 }
        if let assetMime, !assetMime.isEmpty { body["assetMime"] = assetMime }
        if let assetBase64, !assetBase64.isEmpty { body["assetBase64"] = assetBase64 }
        if let projectJSON, !projectJSON.isEmpty { body["projectJSON"] = projectJSON }
        if let timing, let tData = try? JSONEncoder().encode(timing),
           let tObj = try? JSONSerialization.jsonObject(with: tData) {
            body["timing"] = tObj
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let res: WuMindWorkEnvelope = try await performJSON(req, maxBytes: 16 * 1024 * 1024)
        return res.work
    }

    public func fetchWorkDetail(
        gatewayURL: String,
        userToken: String,
        workID: String
    ) async throws -> WuMindCloudWork {
        let encoded = workID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workID
        let url = try makeURL(base: gatewayURL, path: "/v1/works/\(encoded)")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35)
        req.httpMethod = "GET"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        let res: WuMindWorkEnvelope = try await performJSON(req, maxBytes: 24 * 1024 * 1024)
        return res.work
    }

    public func updateWork(
        gatewayURL: String,
        userToken: String,
        workID: String,
        title: String? = nil,
        prompt: String? = nil,
        status: String? = nil,
        progress: Int? = nil,
        errorMessage: String? = nil,
        previewBase64: String? = nil,
        assetMime: String? = nil,
        assetBase64: String? = nil,
        projectJSON: String? = nil,
        timing: WuMindCloudWorkTiming? = nil,
        createNewVersion: Bool = false
    ) async throws -> WuMindCloudWork {
        let encoded = workID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workID
        let url = try makeURL(base: gatewayURL, path: "/v1/works/\(encoded)")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["createNewVersion": createNewVersion]
        if let title { body["title"] = title }
        if let prompt { body["prompt"] = prompt }
        if let status { body["status"] = status }
        if let progress { body["progress"] = progress }
        if let errorMessage { body["errorMessage"] = errorMessage }
        if let previewBase64 { body["previewBase64"] = previewBase64 }
        if let assetMime { body["assetMime"] = assetMime }
        if let assetBase64 { body["assetBase64"] = assetBase64 }
        if let projectJSON { body["projectJSON"] = projectJSON }
        if let timing, let tData = try? JSONEncoder().encode(timing),
           let tObj = try? JSONSerialization.jsonObject(with: tData) {
            body["timing"] = tObj
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let res: WuMindWorkEnvelope = try await performJSON(req, maxBytes: 24 * 1024 * 1024)
        return res.work
    }

    /// Uploads raw binary work asset (up to 100 MB) to private Cloudflare R2 via `PUT /v1/works/:id/asset`.
    /// Throws `GatewayError.objectStorageUnconfigured` on HTTP 503 when R2 is not bound on the gateway.
    public func uploadWorkAssetBinary(
        gatewayURL: String,
        userToken: String,
        workID: String,
        data: Data,
        mimeType: String,
        kind: String = "asset"
    ) async throws -> WuMindWorkAssetUploadResult {
        let encoded = workID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workID
        let query = kind == "project" ? "?kind=project" : ""
        let url = try makeURL(base: gatewayURL, path: "/v1/works/\(encoded)/asset\(query)")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        req.setValue(mimeType.isEmpty ? "application/octet-stream" : mimeType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        return try await performJSON(req, maxBytes: 4 * 1024 * 1024)
    }

    public func downloadWorkAsset(
        gatewayURL: String,
        userToken: String,
        workID: String,
        kind: String = "asset"
    ) async throws -> (data: Data, mimeType: String) {
        let encoded = workID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workID
        let query = kind == "project" ? "?kind=project" : ""
        let url = try makeURL(base: gatewayURL, path: "/v1/works/\(encoded)/asset\(query)")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        req.httpMethod = "GET"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await dataTransport(req)
        guard let http = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
        if (200..<300).contains(http.statusCode) {
            let mime = http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
            return (data, mime)
        }
        throw Self.mapHTTPError(statusCode: http.statusCode, data: data)
    }

    public func deleteWork(
        gatewayURL: String,
        userToken: String,
        workID: String
    ) async throws {
        struct Ack: Decodable { let ok: Bool }
        let encoded = workID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workID
        let url = try makeURL(base: gatewayURL, path: "/v1/works/\(encoded)")
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        let _: Ack = try await performJSON(req)
    }
}

// MARK: - Pure-Swift FIPS 180-4 SHA-256 (Cross-Platform iOS + Linux, Zero External Dependency)

private enum PureSHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        var bytes = message
        let bitLen = UInt64(bytes.count) &* 8
        bytes.append(0x80)
        while (bytes.count % 64) != 56 { bytes.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLen >> UInt64(shift)) & 0xff))
        }

        var w = [UInt32](repeating: 0, count: 64)
        for chunkStart in stride(from: 0, to: bytes.count, by: 64) {
            for i in 0..<16 {
                let j = chunkStart + i * 4
                w[i] = (UInt32(bytes[j]) << 24)
                    | (UInt32(bytes[j + 1]) << 16)
                    | (UInt32(bytes[j + 2]) << 8)
                    | UInt32(bytes[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ ((~e) & g)
                let temp1 = hh &+ S1 &+ ch &+ k[i] &+ w[i]
                let S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = S0 &+ maj
                hh = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }
            h[0] = h[0] &+ a
            h[1] = h[1] &+ b
            h[2] = h[2] &+ c
            h[3] = h[3] &+ d
            h[4] = h[4] &+ e
            h[5] = h[5] &+ f
            h[6] = h[6] &+ g
            h[7] = h[7] &+ hh
        }

        var out = [UInt8]()
        out.reserveCapacity(32)
        for word in h {
            out.append(UInt8((word >> 24) & 0xff))
            out.append(UInt8((word >> 16) & 0xff))
            out.append(UInt8((word >> 8) & 0xff))
            out.append(UInt8(word & 0xff))
        }
        return out
    }

    @inline(__always)
    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x >> n) | (x << (32 - n))
    }
}
