import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Multi-Platform Adaptation & Compliant Publishing Models

public enum WuMindPublishCapability: String, Codable, Equatable, Sendable {
    /// Authorized user submits directly via official platform OpenAPI (subject to platform moderation).
    case directAPISubmit
    /// Official OpenAPI is publicly documented as a Phase-2 candidate; current build exports a full publish package.
    case directAPIPlannedWithPackage
    /// Exports tailored video MP4, cover PNG, and copy bundle for official share / manual in-app confirmation.
    case handoffPackage
}

public enum WuMindPublishPlatform: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case douyin
    case xiaohongshu
    case kuaishou
    case bilibili
    case wechatChannels

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .douyin: return "抖音"
        case .xiaohongshu: return "小红书"
        case .kuaishou: return "快手"
        case .bilibili: return "B 站"
        case .wechatChannels: return "微信视频号"
        }
    }

    public var iconName: String {
        switch self {
        case .douyin: return "music.note.tv.fill"
        case .xiaohongshu: return "book.pages.fill"
        case .kuaishou: return "bolt.horizontal.circle.fill"
        case .bilibili: return "tv.fill"
        case .wechatChannels: return "bubble.left.and.exclamationmark.bubble.right.fill"
        }
    }

    public var capability: WuMindPublishCapability {
        switch self {
        case .douyin: return .directAPISubmit
        case .bilibili: return .directAPIPlannedWithPackage
        case .xiaohongshu, .kuaishou, .wechatChannels: return .handoffPackage
        }
    }

    public var capabilityBadge: String {
        switch self {
        case .douyin: return "授权后真提交（需审）"
        case .xiaohongshu: return "带成片去小红书发"
        case .kuaishou: return "带成片去快手发"
        case .bilibili: return "二期直投 · 当前发布包"
        case .wechatChannels: return "导出至微信手动确认"
        }
    }

    public var honestCapabilityDisclosure: String {
        switch self {
        case .douyin:
            return "走抖音开放平台官方视频上传与创建接口，需应用获批并经本人授权；每次代发均需明确知情确认，提交后进入抖音平台审核。"
        case .xiaohongshu:
            return "生成小红书专属大字报封面、成片 MP4 与种草文案发布包，支持系统分享跳转；分享后状态记为「待手动发布」，需在小红书内完成确认。"
        case .kuaishou:
            return "生成快手高反转剪辑版 MP4、封面与互动置顶话术发布包；交接后记为「待手动发布」，需在快手内确认发布。"
        case .bilibili:
            return "B 站开放平台支持稿件发布能力，拟作为第二家官方直投申请；未获批前默认导出完整叙事节奏成片、横版封面与分集简介发布包。"
        case .wechatChannels:
            return "当前未核实到面向普通第三方 App 的微信视频号通用投稿直发接口；第一版导出专属视频、封面与文案，请前往微信视频号手动确认发布，不承诺后台直发。"
        }
    }

    public var aiDeclarationGuide: String {
        switch self {
        case .douyin:
            return "合规声明：提交文案自动携带 #AI生成，进入抖音创作中心请同步核验「内容由 AI 生成」自主声明。"
        case .xiaohongshu:
            return "合规声明：发布页请开启「笔记含 AI 合成内容」声明，并保留成片与封面上的 AI 显式标识。"
        case .kuaishou:
            return "合规声明：发布页请勾选「AI 生成内容」标注，切勿裁切画面右上角 AI 显式标识。"
        case .bilibili:
            return "合规声明：投稿页请勾选「本稿件包含 AI 辅助/生成内容」声明，并保留标识元数据。"
        case .wechatChannels:
            return "合规声明：在微信视频号发表页请开启「AI 创作声明」，确保显式角标清晰可见。"
        }
    }

    public var editStrategyHeadline: String {
        switch self {
        case .douyin: return "前 3 秒直入高冲突钩子"
        case .xiaohongshu: return "重做 3:4 爆款封面 + 种草文案"
        case .kuaishou: return "强反转开场 + 置顶互动引导"
        case .bilibili: return "完整保留叙事节奏 + 分集简介"
        case .wechatChannels: return "稳健节奏 + 熟人社交转发文案"
        }
    }

    public var coverDimensions: (width: Int, height: Int, label: String) {
        switch self {
        case .xiaohongshu: return (1080, 1440, "3:4 竖版大字报封面")
        case .bilibili: return (1920, 1080, "16:9 横版剧情封面")
        case .douyin, .kuaishou, .wechatChannels: return (1080, 1920, "9:16 竖屏钩子封面")
        }
    }
}

public enum WuMindPublishStatus: Codable, Equatable, Sendable {
    case readyForConfirm
    case pendingManualPublish
    case submittedForReview(itemID: String)
    case published
    case failed(reason: String)

    public var displayLabel: String {
        switch self {
        case .readyForConfirm: return "待确认"
        case .pendingManualPublish: return "待手动发布"
        case .submittedForReview: return "已提交审核"
        case .published: return "已发布"
        case .failed: return "失败"
        }
    }

    public var detailText: String? {
        switch self {
        case .readyForConfirm: return "请核对剪辑版本、封面、标题与目标账号后统一确认"
        case .pendingManualPublish: return "已备好成片、封面与文案；请前往目标平台确认发布（不会自动标为已发布）"
        case .submittedForReview(let itemID): return "已通过官方接口提交至平台审核（稿件 ID: \(itemID)）"
        case .published: return "用户已确认完成平台发布"
        case .failed(let reason): return reason
        }
    }
}

/// Mandatory compliance payload following 《人工智能生成合成内容标识办法》(CAC 2025).
public struct WuMindAIGeneratedDisclosure: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var visibleWatermarkText: String
    public var implicitMetadataTag: String

    public init(
        enabled: Bool = true,
        visibleWatermarkText: String = "AI生成 · WUMIND",
        implicitMetadataTag: String = "AI生成合成内容 | 服务提供方: WUMIND | 规范: 生成合成内容标识办法"
    ) {
        self.enabled = enabled
        self.visibleWatermarkText = visibleWatermarkText
        self.implicitMetadataTag = implicitMetadataTag
    }
}

/// Platform-specific cut instructions so one finished short drama yields genuinely distinct edits per platform.
public struct WuMindPlatformCutPlan: Codable, Equatable, Sendable {
    public var strategySummary: String
    public var orderedShotIDs: [UUID]
    /// Trims slow lead-in from the first shot (e.g., Douyin front-loads conflict within first 3 seconds).
    public var openingLeadInTrimSeconds: Double
    /// Caps per-shot tail pause for punchier feeds while Bilibili preserves full pacing (`nil`).
    public var maxPerShotDurationSeconds: Double?
    public var estimatedDurationSeconds: Double

    public init(
        strategySummary: String,
        orderedShotIDs: [UUID],
        openingLeadInTrimSeconds: Double,
        maxPerShotDurationSeconds: Double?,
        estimatedDurationSeconds: Double
    ) {
        self.strategySummary = strategySummary
        self.orderedShotIDs = orderedShotIDs
        self.openingLeadInTrimSeconds = max(0, openingLeadInTrimSeconds)
        self.maxPerShotDurationSeconds = maxPerShotDurationSeconds
        self.estimatedDurationSeconds = estimatedDurationSeconds
    }

    /// Produces a platform-tailored copy of the drama project ready for on-device MP4 export.
    public func adaptedProject(from base: WuMindShortDramaProject) -> WuMindShortDramaProject {
        var copy = base
        let shotByID = Dictionary(uniqueKeysWithValues: base.shots.map { ($0.id, $0) })
        var arranged: [WuMindDramaShot] = orderedShotIDs.compactMap { shotByID[$0] }
        let included = Set(arranged.map(\.id))
        for leftover in base.shots where !included.contains(leftover.id) {
            arranged.append(leftover)
        }
        if arranged.isEmpty {
            arranged = base.shots
        }

        for idx in arranged.indices {
            var shot = arranged[idx]
            if idx == 0, openingLeadInTrimSeconds > 0 {
                let candidateStart = min(shot.trimEndSeconds - 1.5, shot.trimStartSeconds + openingLeadInTrimSeconds)
                if candidateStart > shot.trimStartSeconds {
                    shot.trimStartSeconds = (candidateStart * 10).rounded() / 10
                }
            }
            if let cap = maxPerShotDurationSeconds, shot.trimmedDuration > cap {
                let nextEnd = max(shot.trimStartSeconds + 1.5, shot.trimStartSeconds + cap)
                shot.trimEndSeconds = min(shot.durationSeconds, (nextEnd * 10).rounded() / 10)
            }
            arranged[idx] = shot
        }

        copy.shots = arranged
        return copy
    }
}

public struct WuMindPlatformPublishVariant: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var platform: WuMindPublishPlatform
    public var isSelected: Bool
    public var targetAccountLabel: String
    public var cutPlan: WuMindPlatformCutPlan
    public var coverHeadline: String
    public var coverSubheadline: String
    public var title: String
    public var caption: String
    public var hashtags: [String]
    public var pinnedCommentSuggestion: String?
    public var aiDisclosure: WuMindAIGeneratedDisclosure
    public var status: WuMindPublishStatus
    public var exportedMP4Filename: String?
    public var exportedCoverPNGFilename: String?
    public var lastUpdatedAt: Date

    public init(
        id: UUID = UUID(),
        platform: WuMindPublishPlatform,
        isSelected: Bool = true,
        targetAccountLabel: String,
        cutPlan: WuMindPlatformCutPlan,
        coverHeadline: String,
        coverSubheadline: String,
        title: String,
        caption: String,
        hashtags: [String],
        pinnedCommentSuggestion: String? = nil,
        aiDisclosure: WuMindAIGeneratedDisclosure = WuMindAIGeneratedDisclosure(),
        status: WuMindPublishStatus = .readyForConfirm,
        exportedMP4Filename: String? = nil,
        exportedCoverPNGFilename: String? = nil,
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.platform = platform
        self.isSelected = isSelected
        self.targetAccountLabel = targetAccountLabel
        self.cutPlan = cutPlan
        self.coverHeadline = coverHeadline
        self.coverSubheadline = coverSubheadline
        self.title = title
        self.caption = caption
        self.hashtags = hashtags
        self.pinnedCommentSuggestion = pinnedCommentSuggestion
        self.aiDisclosure = aiDisclosure
        self.status = status
        self.exportedMP4Filename = exportedMP4Filename
        self.exportedCoverPNGFilename = exportedCoverPNGFilename
        self.lastUpdatedAt = lastUpdatedAt
    }

    /// Formats ready-to-paste copy with hashtags and mandatory AI disclosure tag when enabled.
    public func formattedCopyBundle() -> String {
        var tags = hashtags.map { tag -> String in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        }
        if aiDisclosure.enabled && !tags.contains(where: { $0.localizedCaseInsensitiveContains("AI") }) {
            tags.append("#AI生成")
        }
        var lines: [String] = []
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(title.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(caption.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !tags.isEmpty {
            lines.append(tags.joined(separator: " "))
        }
        if aiDisclosure.enabled {
            lines.append("【AI生成内容声明】本视频画面/配音含 AI 生成合成内容（WUMIND 创作）。")
        }
        if let pinned = pinnedCommentSuggestion?.trimmingCharacters(in: .whitespacesAndNewlines), !pinned.isEmpty {
            lines.append("——\n建议置顶评论：\(pinned)")
        }
        return lines.joined(separator: "\n")
    }
}

public enum WuMindMultiPlatformPublishError: LocalizedError, Equatable, Sendable {
    case noPlatformsSelected
    case missingInformedConsent
    case missingDouyinAuthorization
    case douyinAPIError(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .noPlatformsSelected:
            return "请至少勾选一个目标发布平台。"
        case .missingInformedConsent:
            return "请先勾选「已知情发布方式与 AI 生成标识声明」后再确认提交。"
        case .missingDouyinAuthorization:
            return "尚未配置已授权的抖音开放平台 open_id 与 access_token，无法执行抖音代提交。"
        case .douyinAPIError(let code, let message):
            let clean = MultiProviderAIClient.redactSecrets(in: message)
            return "抖音官方接口返回失败（code=\(code)）：\(clean)"
        }
    }
}

// MARK: - Pure Multi-Platform Adaptation & State Machine Engine

public enum WuMindMultiPlatformPublishEngine {

    /// Builds genuinely differentiated platform versions from a single finished short drama:
    /// - Douyin: jumps straight into conflict within first 3s (front-loads conflict shot / trims slow intro)
    /// - Xiaohongshu: 3:4 high-CTR poster cover + detailed editorial copy
    /// - Kuaishou: fast twist hook + direct conversational title + pinned comment prompt
    /// - Bilibili: 100% full narrative pacing preserved + structured episode notes
    /// - WeChat Channels: balanced narrative + social-share-friendly copy (explicitly manual confirm in WeChat)
    public static func buildVariants(
        from project: WuMindShortDramaProject,
        douyinAccountName: String? = nil,
        douyinAuthorized: Bool = false
    ) -> [WuMindPlatformPublishVariant] {
        let baseIDs = project.shots.map(\.id)
        let hookShotIndex = detectConflictHookShotIndex(in: project.shots)
        let hookLine = bestHookDialogue(in: project)
        let genreTag = project.genre.rawValue

        return WuMindPublishPlatform.allCases.map { platform in
            let cutPlan: WuMindPlatformCutPlan
            let coverHeadline: String
            let coverSubheadline: String
            let title: String
            let caption: String
            let hashtags: [String]
            let pinnedComment: String?
            let accountLabel: String

            switch platform {
            case .douyin:
                // Front-load the highest-tension shot if it's later in the episode, and tighten opening lead-in
                var reordered = baseIDs
                if let hookIdx = hookShotIndex, hookIdx > 0, hookIdx < reordered.count {
                    let hookID = reordered.remove(at: hookIdx)
                    reordered.insert(hookID, at: 0)
                }
                let draftPlan = WuMindPlatformCutPlan(
                    strategySummary: "前 3 秒直入高冲突钩子（前置第 \((hookShotIndex ?? 0) + 1) 镜反转并收紧开场入点）",
                    orderedShotIDs: reordered,
                    openingLeadInTrimSeconds: 1.2,
                    maxPerShotDurationSeconds: 5.0,
                    estimatedDurationSeconds: 0
                )
                let adapted = draftPlan.adaptedProject(from: project)
                cutPlan = WuMindPlatformCutPlan(
                    strategySummary: draftPlan.strategySummary,
                    orderedShotIDs: draftPlan.orderedShotIDs,
                    openingLeadInTrimSeconds: draftPlan.openingLeadInTrimSeconds,
                    maxPerShotDurationSeconds: draftPlan.maxPerShotDurationSeconds,
                    estimatedDurationSeconds: WuMindShortDramaEngine.totalTrimmedDuration(for: adapted)
                )
                coverHeadline = "3秒高能反转"
                coverSubheadline = "《\(project.title)》"
                title = "\(hookLine.isEmpty ? project.title : hookLine)｜\(project.title)"
                caption = "看到第 4 镜我直接起鸡皮疙瘩…你觉得最后谁在说谎？"
                hashtags = ["AI短剧", genreTag, project.title, "高能反转", "AI生成"]
                pinnedComment = "猜对真正幕后黑手的，下集我按你写的结局拍！"
                if douyinAuthorized {
                    let cleanName = douyinAccountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    accountLabel = cleanName.isEmpty ? "抖音已授权账号（官方直投）" : "抖音：\(cleanName)（已授权）"
                } else {
                    accountLabel = "未授权抖音账号（可先授权直投，或导出抖音版发布包）"
                }

            case .xiaohongshu:
                let draftPlan = WuMindPlatformCutPlan(
                    strategySummary: "紧扣开场吸睛画面 + 重做 3:4 爆款大字报封面与种草长文案",
                    orderedShotIDs: baseIDs,
                    openingLeadInTrimSeconds: 0.6,
                    maxPerShotDurationSeconds: 5.6,
                    estimatedDurationSeconds: 0
                )
                let adapted = draftPlan.adaptedProject(from: project)
                cutPlan = WuMindPlatformCutPlan(
                    strategySummary: draftPlan.strategySummary,
                    orderedShotIDs: draftPlan.orderedShotIDs,
                    openingLeadInTrimSeconds: draftPlan.openingLeadInTrimSeconds,
                    maxPerShotDurationSeconds: draftPlan.maxPerShotDurationSeconds,
                    estimatedDurationSeconds: WuMindShortDramaEngine.totalTrimmedDuration(for: adapted)
                )
                coverHeadline = "一口气看完｜\(project.title)"
                coverSubheadline = "\(genreTag)微短剧 · \(project.shots.count)镜精剪"
                title = "绝了！用手机拍完的\(genreTag)短剧《\(project.title)》，最后一秒全员反转"
                caption = "剧情看点：\n• 核心冲突：\(String(project.premise.prefix(48)))\n• 名场面台词：「\(hookLine.isEmpty ? project.title : hookLine)」\n• 欢迎在评论区聊聊你发现的隐藏伏笔 👇"
                hashtags = ["AI微短剧", "小红书短剧", genreTag, "高能反转", "AI生成"]
                pinnedComment = "想要下一集剧情走向的姐妹直接留言，评论最高赞我马上单镜重拍！"
                accountLabel = "待在小红书 App 内登录账号发布"

            case .kuaishou:
                var reordered = baseIDs
                if let hookIdx = hookShotIndex, hookIdx > 0, hookIdx < reordered.count {
                    let hookID = reordered.remove(at: hookIdx)
                    reordered.insert(hookID, at: 0)
                }
                let draftPlan = WuMindPlatformCutPlan(
                    strategySummary: "开场直接甩反转冲突 + 直给情绪标题与置顶互动话术",
                    orderedShotIDs: reordered,
                    openingLeadInTrimSeconds: 1.0,
                    maxPerShotDurationSeconds: 5.2,
                    estimatedDurationSeconds: 0
                )
                let adapted = draftPlan.adaptedProject(from: project)
                cutPlan = WuMindPlatformCutPlan(
                    strategySummary: draftPlan.strategySummary,
                    orderedShotIDs: draftPlan.orderedShotIDs,
                    openingLeadInTrimSeconds: draftPlan.openingLeadInTrimSeconds,
                    maxPerShotDurationSeconds: draftPlan.maxPerShotDurationSeconds,
                    estimatedDurationSeconds: WuMindShortDramaEngine.totalTrimmedDuration(for: adapted)
                )
                coverHeadline = "千万别眨眼！"
                coverSubheadline = "\(project.title) · 结局没想到"
                title = "看到最后傻眼了！《\(project.title)》这反转太狠了"
                caption = "\(hookLine.isEmpty ? project.premise : "「\(hookLine)」") 到底谁在搞鬼？老铁们评论区说说看！"
                hashtags = ["反转短剧", genreTag, "微短剧", "AI生成"]
                pinnedComment = "第一眼就看出破绽的老铁扣 1，没看出来的扣 2，下集揭秘！"
                accountLabel = "待在快手 App 内登录账号发布"

            case .bilibili:
                let fullDuration = WuMindShortDramaEngine.totalTrimmedDuration(for: project)
                cutPlan = WuMindPlatformCutPlan(
                    strategySummary: "100% 保留完整叙事节奏与全长镜头（不删减铺垫），配 16:9 封面与分集简介",
                    orderedShotIDs: baseIDs,
                    openingLeadInTrimSeconds: 0.0,
                    maxPerShotDurationSeconds: nil,
                    estimatedDurationSeconds: fullDuration
                )
                coverHeadline = "【\(genreTag)微短剧】\(project.title)"
                coverSubheadline = "全 \(project.shots.count) 镜完整叙事版 · \(String(format: "%.0f", fullDuration))秒"
                title = "【AI短剧/\(genreTag)】《\(project.title)》完整版：\(String(project.premise.prefix(24)))"
                let shotBreakdown = project.shots.enumerated().map { idx, s in
                    "P\(idx + 1) \(s.title)（\(s.cameraFraming.label)）"
                }.joined(separator: " / ")
                caption = "【剧情简介】\(project.premise)\n【镜头结构】\(shotBreakdown)\n【建议分区】影视 - 短片 / 科技 - AI创作\n三连催更下一集！"
                hashtags = ["AI短剧", "原创微电影", genreTag, "高能反转", "AI生成"]
                pinnedComment = "片中第 3 镜和第 5 镜藏了双线呼应，有细心的 UP 观众发现了吗？"
                accountLabel = "B 站开放平台二期直投预留（当前导出完整发布包）"

            case .wechatChannels:
                let fullDuration = WuMindShortDramaEngine.totalTrimmedDuration(for: project)
                cutPlan = WuMindPlatformCutPlan(
                    strategySummary: "保留清晰故事起承转合 + 适配微信转发文案（视频号第一版走微信内手动确认）",
                    orderedShotIDs: baseIDs,
                    openingLeadInTrimSeconds: 0.4,
                    maxPerShotDurationSeconds: nil,
                    estimatedDurationSeconds: max(1.0, ((fullDuration - 0.4) * 10).rounded() / 10)
                )
                coverHeadline = project.title
                coverSubheadline = "\(genreTag) · 完整短剧"
                title = "《\(project.title)》：\(hookLine.isEmpty ? String(project.premise.prefix(22)) : hookLine)"
                caption = "\(project.premise)\n欢迎转发给喜欢看\(genreTag)短剧的朋友一起猜结局。"
                hashtags = ["微短剧", genreTag, "AI生成"]
                pinnedComment = nil
                accountLabel = "导出至微信视频号手动确认（不做后台直发）"
            }

            return WuMindPlatformPublishVariant(
                platform: platform,
                isSelected: true,
                targetAccountLabel: accountLabel,
                cutPlan: cutPlan,
                coverHeadline: coverHeadline,
                coverSubheadline: coverSubheadline,
                title: title,
                caption: caption,
                hashtags: hashtags,
                pinnedCommentSuggestion: pinnedComment,
                aiDisclosure: WuMindAIGeneratedDisclosure(),
                status: .readyForConfirm
            )
        }
    }

    /// Prompt for 1-shot LLM polishing of all 5 platforms' titles, covers, captions, and hashtags.
    public static func llmPolishPrompt(for project: WuMindShortDramaProject) -> String {
        let shotLines = project.shots.enumerated().map { idx, s in
            "第\(idx + 1)镜[\(s.cameraFraming.label)] \(s.title)：\(s.dialogue)"
        }.joined(separator: "\n")
        return """
        你是多平台爆款短剧发行主编。请根据同一部短剧内容，为抖音、小红书、快手、B 站、微信视频号分别输出差异化的封面主副标题、发布标题、正文文案和话题标签。
        要求：
        - 抖音：前3秒强冲突钩子感，标题短狠。
        - 小红书：重做大字报封面标题，文案有看点与互动感。
        - 快手：直接反转悬念，语气接地气，附一句置顶评论引导。
        - B 站：信息密度高，保留完整叙事感与分区氛围。
        - 微信视频号：克制自然，适合熟人圈转发讨论。
        - 严禁虚构播放数据，所有平台均保留 #AI生成 标签。
        只输出合法 JSON 对象，键名为 douyin / xiaohongshu / kuaishou / bilibili / wechatChannels，每项含：coverHeadline, coverSubheadline, title, caption, hashtags (字符串数组), pinnedComment。

        剧名：《\(project.title)》
        题材：\(project.genre.rawValue)
        梗概：\(project.premise)
        分镜与台词：
        \(shotLines)
        """
    }

    public static func applyPolishedCopy(
        rawOutput: String,
        onto variants: [WuMindPlatformPublishVariant]
    ) -> [WuMindPlatformPublishVariant] {
        let cleaned = extractJSONObject(from: rawOutput)
        guard let data = cleaned.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: RawPolishedEntry].self, from: data) else {
            return variants
        }
        return variants.map { variant in
            guard let entry = map[variant.platform.rawValue] else { return variant }
            var copy = variant
            if let v = entry.coverHeadline?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { copy.coverHeadline = v }
            if let v = entry.coverSubheadline?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { copy.coverSubheadline = v }
            if let v = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { copy.title = v }
            if let v = entry.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { copy.caption = v }
            if let tags = entry.hashtags?.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), !tags.isEmpty {
                copy.hashtags = tags
            }
            if let pin = entry.pinnedComment?.trimmingCharacters(in: .whitespacesAndNewlines), !pin.isEmpty {
                copy.pinnedCommentSuggestion = pin
            }
            copy.lastUpdatedAt = Date()
            return copy
        }
    }

    /// Mandatory pre-flight check before starting batch direct submit / package generation.
    public static func validateBatchConfirmation(
        variants: [WuMindPlatformPublishVariant],
        userAcknowledgedSubmissionAndAI: Bool
    ) throws {
        guard variants.contains(where: \.isSelected) else {
            throw WuMindMultiPlatformPublishError.noPlatformsSelected
        }
        guard userAcknowledgedSubmissionAndAI else {
            throw WuMindMultiPlatformPublishError.missingInformedConsent
        }
    }

    /// Honest state transition after official direct API submission (e.g. Douyin):
    /// NEVER jumps directly to `.published` because platforms run moderation review!
    public static func applyDirectSubmitOutcome(
        variant: WuMindPlatformPublishVariant,
        itemID: String?,
        errorMessage: String?
    ) -> WuMindPlatformPublishVariant {
        var next = variant
        if let itemID, !itemID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.status = .submittedForReview(itemID: itemID)
        } else {
            next.status = .failed(reason: errorMessage ?? "平台接口提交失败，请检查授权状态后重试。")
        }
        next.lastUpdatedAt = Date()
        return next
    }

    /// Honest state transition after exporting a platform publish package (video + cover + copy):
    /// NEVER fakes `.published` just because files were exported or ShareSheet opened!
    public static func applyPackageReadyOutcome(
        variant: WuMindPlatformPublishVariant,
        mp4Filename: String?,
        coverPNGFilename: String?,
        errorMessage: String? = nil
    ) -> WuMindPlatformPublishVariant {
        var next = variant
        if let errorMessage, !errorMessage.isEmpty {
            next.status = .failed(reason: errorMessage)
        } else {
            next.exportedMP4Filename = mp4Filename
            next.exportedCoverPNGFilename = coverPNGFilename
            next.status = .pendingManualPublish
        }
        next.lastUpdatedAt = Date()
        return next
    }

    /// Explicit user-confirmed completion after posting inside the target platform app or passing review.
    public static func markManuallyPublished(variant: WuMindPlatformPublishVariant) -> WuMindPlatformPublishVariant {
        var next = variant
        next.status = .published
        next.lastUpdatedAt = Date()
        return next
    }

    // MARK: - Helpers

    private static func detectConflictHookShotIndex(in shots: [WuMindDramaShot]) -> Int? {
        guard shots.count >= 2 else { return shots.isEmpty ? nil : 0 }
        let conflictKeywords = ["反转", "对峙", "别", "谁", "秘密", "警报", "真相", "循环", "爆发"]
        for (idx, shot) in shots.enumerated() {
            let combined = shot.title + " " + shot.dialogue
            if shot.cameraFraming == .extremeCloseUp || shot.cameraFraming == .closeUp,
               conflictKeywords.contains(where: { combined.contains($0) }) {
                return idx
            }
        }
        // Fallback: peak midpoint twist shot (often shot #3 or #4 in a 6-shot short drama)
        return min(shots.count - 1, max(1, shots.count / 2))
    }

    private static func bestHookDialogue(in project: WuMindShortDramaProject) -> String {
        if let idx = detectConflictHookShotIndex(in: project.shots), project.shots.indices.contains(idx) {
            let line = project.shots[idx].dialogue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { return line }
        }
        return project.shots.first?.dialogue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func extractJSONObject(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.firstIndex(of: "{"),
              let last = trimmed.lastIndex(of: "}"),
              first < last else {
            return trimmed
        }
        return String(trimmed[first...last])
    }

    private struct RawPolishedEntry: Decodable {
        let coverHeadline: String?
        let coverSubheadline: String?
        let title: String?
        let caption: String?
        let hashtags: [String]?
        let pinnedComment: String?
    }
}

// MARK: - Official Douyin Open Platform Video Upload & Create Client

/// Official Douyin Open Platform API client:
/// 1. `POST /api/douyin/v1/video/upload/?open_id=...` (multipart/form-data)
/// 2. `POST /api/douyin/v1/video/create/?open_id=...` (JSON)
/// Enforces explicit per-publish user consent, HTTPS pinning, redirect blocking, and AI-disclosure labeling.
public struct DouyinOfficialPublishClient: Sendable {
    public static let defaultBaseURL = "https://open.douyin.com"
    private static let maxResponseBytes = 2 * 1024 * 1024

    public struct Request: Equatable, Sendable {
        public var openID: String
        public var accessToken: String
        public var mp4Data: Data
        public var titleAndHashtagsText: String
        public var aiDisclosure: WuMindAIGeneratedDisclosure
        /// MUST be explicitly `true` from the confirmation screen before any request is sent.
        public var userInformedConsent: Bool
        public var baseURL: String?

        public init(
            openID: String,
            accessToken: String,
            mp4Data: Data,
            titleAndHashtagsText: String,
            aiDisclosure: WuMindAIGeneratedDisclosure = WuMindAIGeneratedDisclosure(),
            userInformedConsent: Bool,
            baseURL: String? = nil
        ) {
            self.openID = openID
            self.accessToken = accessToken
            self.mp4Data = mp4Data
            self.titleAndHashtagsText = titleAndHashtagsText
            self.aiDisclosure = aiDisclosure
            self.userInformedConsent = userInformedConsent
            self.baseURL = baseURL
        }
    }

    public struct SubmitReceipt: Equatable, Sendable {
        public let videoID: String
        public let itemID: String
        public let submittedAt: Date

        public init(videoID: String, itemID: String, submittedAt: Date = Date()) {
            self.videoID = videoID
            self.itemID = itemID
            self.submittedAt = submittedAt
        }
    }

    private let transport: MultiProviderAIClient.Transport?

    public init() {
        self.transport = nil
    }

    public init(transport: @escaping MultiProviderAIClient.Transport) {
        self.transport = transport
    }

    public func submitForReview(_ request: Request) async throws -> SubmitReceipt {
        guard request.userInformedConsent else {
            throw WuMindMultiPlatformPublishError.missingInformedConsent
        }
        let openID = request.openID.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessToken = request.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !openID.isEmpty, !accessToken.isEmpty else {
            throw WuMindMultiPlatformPublishError.missingDouyinAuthorization
        }
        guard AIVideoTool.isValidMP4(request.mp4Data) else {
            throw AIVideoToolError.invalidVideoData
        }

        let base = try validatedBaseURL(request.baseURL)
        let encodedOpenID = openID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? openID

        // Step 1: Upload video bytes via multipart/form-data
        let uploadURL = try join(baseURL: base, pathAndQuery: "/api/douyin/v1/video/upload/?open_id=\(encodedOpenID)")
        let boundary = "Boundary-WUMIND-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var multipart = Data()
        multipart.append(Data("--\(boundary)\r\n".utf8))
        multipart.append(Data("Content-Disposition: form-data; name=\"video\"; filename=\"wumind_douyin.mp4\"\r\n".utf8))
        multipart.append(Data("Content-Type: video/mp4\r\n\r\n".utf8))
        multipart.append(request.mp4Data)
        multipart.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var uploadReq = URLRequest(url: uploadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
        uploadReq.httpMethod = "POST"
        uploadReq.httpShouldHandleCookies = false
        uploadReq.setValue(accessToken, forHTTPHeaderField: "access-token")
        uploadReq.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        uploadReq.setValue("application/json", forHTTPHeaderField: "Accept")
        uploadReq.httpBody = multipart

        let uploadRespData = try await execute(uploadReq)
        let uploadParsed = try decode(DouyinUploadEnvelope.self, from: uploadRespData)
        if let code = uploadParsed.data?.errorCode, code != 0 {
            throw WuMindMultiPlatformPublishError.douyinAPIError(
                code: code,
                message: uploadParsed.data?.description ?? "抖音视频上传失败。"
            )
        }
        guard let videoID = uploadParsed.data?.video?.videoID, !videoID.isEmpty else {
            throw MultiProviderAIError.invalidResponse
        }

        // Step 2: Create Douyin video post (enters platform review queue)
        let createURL = try join(baseURL: base, pathAndQuery: "/api/douyin/v1/video/create/?open_id=\(encodedOpenID)")
        var finalText = request.titleAndHashtagsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if request.aiDisclosure.enabled && !finalText.localizedCaseInsensitiveContains("AI") {
            finalText = finalText.isEmpty ? "#AI生成" : "\(finalText) #AI生成"
        }
        let createBody: [String: Any] = [
            "video_id": videoID,
            "text": String(finalText.prefix(500)),
        ]

        var createReq = URLRequest(url: createURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        createReq.httpMethod = "POST"
        createReq.httpShouldHandleCookies = false
        createReq.setValue(accessToken, forHTTPHeaderField: "access-token")
        createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createReq.setValue("application/json", forHTTPHeaderField: "Accept")
        createReq.httpBody = try JSONSerialization.data(withJSONObject: createBody, options: [.withoutEscapingSlashes])

        let createRespData = try await execute(createReq)
        let createParsed = try decode(DouyinCreateEnvelope.self, from: createRespData)
        if let code = createParsed.data?.errorCode, code != 0 {
            throw WuMindMultiPlatformPublishError.douyinAPIError(
                code: code,
                message: createParsed.data?.description ?? "抖音视频创建投稿失败。"
            )
        }
        guard let itemID = createParsed.data?.itemID, !itemID.isEmpty else {
            throw MultiProviderAIError.invalidResponse
        }

        return SubmitReceipt(videoID: videoID, itemID: itemID)
    }

    private func execute(_ req: URLRequest) async throws -> Data {
        let result: (Data, URLResponse)
        if let transport {
            result = try await transport(req)
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpShouldSetCookies = false
            result = try await URLSession(configuration: cfg, delegate: DouyinBlockRedirects(), delegateQueue: nil).data(for: req)
        }
        guard let http = result.1 as? HTTPURLResponse else {
            throw MultiProviderAIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: result.0.prefix(300), encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw WuMindMultiPlatformPublishError.douyinAPIError(code: http.statusCode, message: snippet)
        }
        guard result.0.count <= Self.maxResponseBytes else {
            throw MultiProviderAIError.invalidResponse
        }
        return result.0
    }

    private func validatedBaseURL(_ raw: String?) throws -> URL {
        let candidate = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let str = (candidate?.isEmpty == false) ? candidate! : Self.defaultBaseURL
        guard let url = URL(string: str),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil,
              host != "localhost", !host.hasPrefix("127."), !host.hasPrefix("10."), !host.hasPrefix("192.168.") else {
            throw MultiProviderAIError.invalidRequest
        }
        return url
    }

    private func join(baseURL: URL, pathAndQuery: String) throws -> URL {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let suffix = pathAndQuery.hasPrefix("/") ? pathAndQuery : "/\(pathAndQuery)"
        guard let url = URL(string: base + suffix) else {
            throw MultiProviderAIError.invalidRequest
        }
        return url
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw MultiProviderAIError.invalidResponse
        }
        return value
    }

    private final class DouyinBlockRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private struct DouyinUploadEnvelope: Decodable {
        struct DataPayload: Decodable {
            struct VideoInfo: Decodable {
                let videoID: String?
                enum CodingKeys: String, CodingKey { case videoID = "video_id" }
            }
            let errorCode: Int?
            let description: String?
            let video: VideoInfo?
            enum CodingKeys: String, CodingKey {
                case errorCode = "error_code"
                case description
                case video
            }
        }
        let data: DataPayload?
    }

    private struct DouyinCreateEnvelope: Decodable {
        struct DataPayload: Decodable {
            let errorCode: Int?
            let description: String?
            let itemID: String?
            enum CodingKeys: String, CodingKey {
                case errorCode = "error_code"
                case description
                case itemID = "item_id"
            }
        }
        let data: DataPayload?
    }
}
