import Foundation

/// Thread-scoped shared material persisted on a conversation so switching AI models mid-thread
/// NEVER requires re-uploading documents or re-explaining background context.
public struct WuMindThreadMaterial: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let filename: String
    public let summaryBadge: String
    public let extractedText: String
    public let byteCount: Int
    public let addedAt: Date

    public init(
        id: UUID = UUID(),
        filename: String,
        summaryBadge: String,
        extractedText: String,
        byteCount: Int,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.filename = filename
        self.summaryBadge = summaryBadge
        self.extractedText = extractedText
        self.byteCount = byteCount
        self.addedAt = addedAt
    }
}

/// Second-model comparison or cross-review attached directly to a single conversation turn.
public struct WuMindComparisonResult: Codable, Identifiable, Equatable, Sendable {
    public enum Mode: String, Codable, Equatable, Sendable, CaseIterable, Identifiable {
        case crossReview
        case independentCompare

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .crossReview: return "交叉复核与挑错"
            case .independentCompare: return "独立同题对比"
            }
        }

        public var subtitle: String {
            switch self {
            case .crossReview: return "让第二家模型对照原文与主答，标出共识、依据、分歧与遗漏风险"
            case .independentCompare: return "让第二家模型基于同样资料独立作答，并排比较两种思路"
            }
        }
    }

    public let id: UUID
    public let mode: Mode
    public let providerRaw: String
    public let modelID: String
    public let modelLabel: String
    public let channelLabel: String
    public var answer: String
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var costYuan: Double?
    public let createdAt: Date
    public var adopted: Bool

    public init(
        id: UUID = UUID(),
        mode: Mode,
        providerRaw: String,
        modelID: String,
        modelLabel: String,
        channelLabel: String,
        answer: String,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        costYuan: Double? = nil,
        createdAt: Date = Date(),
        adopted: Bool = false
    ) {
        self.id = id
        self.mode = mode
        self.providerRaw = providerRaw
        self.modelID = modelID
        self.modelLabel = modelLabel
        self.channelLabel = channelLabel
        self.answer = answer
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.costYuan = costYuan
        self.createdAt = createdAt
        self.adopted = adopted
    }
}

/// Pure-Swift cross-model prompt builder, shared-material context formatter,
/// and transparent pre-flight cost / upgrade-guard calculator for WUMIND.
public enum WuMindMultiModelEngine {
    /// Merges newly uploaded documents into thread-shared materials (deduplicated by filename, bounded).
    public static func mergeThreadMaterials(
        existing: [WuMindThreadMaterial],
        incoming: [WuMindThreadMaterial],
        maxItems: Int = 6,
        maxCharsPerItem: Int = 14_000
    ) -> [WuMindThreadMaterial] {
        var result = existing
        for item in incoming {
            let trimmedText = String(item.extractedText.prefix(maxCharsPerItem))
            let bounded = WuMindThreadMaterial(
                id: item.id,
                filename: item.filename,
                summaryBadge: item.summaryBadge,
                extractedText: trimmedText,
                byteCount: item.byteCount,
                addedAt: item.addedAt
            )
            if let existingIdx = result.firstIndex(where: { $0.filename == item.filename }) {
                result[existingIdx] = bounded
            } else {
                result.append(bounded)
            }
        }
        if result.count > maxItems {
            result = Array(result.suffix(maxItems))
        }
        return result
    }

    /// Formats thread-shared materials so ANY model switched mid-conversation immediately has full access.
    public static func formattedSharedMaterialsBlock(
        materials: [WuMindThreadMaterial],
        maxTotalChars: Int = 36_000
    ) -> String? {
        guard !materials.isEmpty else { return nil }
        var sections: [String] = [
            "[本对话已共享资料（共 \(materials.count) 份，跨模型自动延续，无需用户重新上传）]"
        ]
        var remaining = max(2_000, maxTotalChars)
        let perItemCap = max(1_500, remaining / max(1, materials.count))
        for item in materials {
            let slice = String(item.extractedText.prefix(min(perItemCap, remaining)))
            sections.append("【共享文件：\(item.filename)（\(item.summaryBadge)）】\n\(slice)")
            remaining -= slice.count
            if remaining <= 400 { break }
        }
        return sections.joined(separator: "\n\n")
    }

    /// System prompt for structured second-model cross-review (Consensus / Evidence / Divergence / Risks / Revisions).
    public static func crossReviewSystemPrompt(primaryModel: String, reviewerModel: String) -> String {
        """
        你是 WUMIND 双模型交叉复核专家（当前复核模型：\(reviewerModel)）。
        用户刚才已经使用「\(primaryModel)」回答了同一个问题，现在请你基于相同的原始问题与共享资料进行严格复核，让用户一眼看清两家模型的依据与分歧，而不是简单复述一遍答案。

        请严格按以下 4 个小节输出（简洁、直接、可核查）：
        ### 1. 共识与可采纳依据
        - 明确哪些结论你认同，并给出关键条款/事实依据。
        ### 2. 分歧点与遗漏风险
        - 逐条指出你与「\(primaryModel)」判断不同的地方，以及原回答可能遗漏的风险、前提错误或数据缺口；若基本一致也要说明核验边界。
        ### 3. 修订建议（可直接采纳）
        - 给出修正后的结论、补强条款或更优方案。
        ### 4. 一句话复核结论
        - 用一句话告诉用户应该直接采纳原回答、采纳修订版，还是需要补充哪些原始材料。
        """
    }

    /// User payload passed to the second model during cross-review mode.
    public static func crossReviewUserPrompt(
        question: String,
        primaryModel: String,
        primaryAnswer: String,
        sharedMaterialsBlock: String?
    ) -> String {
        var parts: [String] = []
        if let sharedMaterialsBlock, !sharedMaterialsBlock.isEmpty {
            parts.append(sharedMaterialsBlock)
        }
        parts.append("【用户原始问题】\n\(question)")
        parts.append("【第一模型「\(primaryModel)」的回答】\n\(String(primaryAnswer.prefix(12_000)))")
        parts.append("请严格按交叉复核 4 节格式给出你的独立复核意见、分歧点与修订建议。")
        return parts.joined(separator: "\n\n---\n\n")
    }

    /// System prompt for independent side-by-side comparison mode.
    public static func independentCompareSystemPrompt(reviewerModel: String) -> String {
        """
        你是 WUMIND 同题并排对比中的第二模型（\(reviewerModel)）。
        请完全独立地基于用户原始问题、上下文与共享资料作答，结论先行、列出关键判断依据与风险提示，方便用户与另一家模型并排对照。
        """
    }
}

/// Transparent pre-flight cost estimation and anti-silent-upgrade guardrails.
public enum WuMindCostTransparency {
    public struct PreFlightEstimate: Equatable, Sendable {
        public let estimatedInputTokens: Int
        public let estimatedMinYuan: Double?
        public let estimatedMaxYuan: Double?
        public let hardCapYuan: Double?
        public let isHighCost: Bool
        public let reasonTags: [String]
        public let bannerText: String

        public init(
            estimatedInputTokens: Int,
            estimatedMinYuan: Double?,
            estimatedMaxYuan: Double?,
            hardCapYuan: Double?,
            isHighCost: Bool,
            reasonTags: [String],
            bannerText: String
        ) {
            self.estimatedInputTokens = estimatedInputTokens
            self.estimatedMinYuan = estimatedMinYuan
            self.estimatedMaxYuan = estimatedMaxYuan
            self.hardCapYuan = hardCapYuan
            self.isHighCost = isHighCost
            self.reasonTags = reasonTags
            self.bannerText = bannerText
        }
    }

    /// Estimates cost/tokens BEFORE sending so high-cost tasks (long docs, deep research, agent, deep thinking)
    /// are transparent upfront and never surprise the user.
    public static func estimatePreFlight(
        promptText: String,
        attachmentChars: Int,
        sharedMaterialChars: Int,
        historyTokens: Int,
        isDeepThinking: Bool,
        isAgentMode: Bool,
        agentCapYuan: Double,
        isManagedChannel: Bool,
        inputYuanPer1K: Double,
        outputYuanPer1K: Double
    ) -> PreFlightEstimate {
        let promptTok = WuMindContextEngine.estimateTokens(promptText)
        let docTok = (attachmentChars + sharedMaterialChars) / 2
        let totalIn = max(1, promptTok + docTok + historyTokens)

        var tags: [String] = []
        if attachmentChars + sharedMaterialChars >= 4_000 { tags.append("长文档") }
        if isAgentMode { tags.append("智能体/联网研究") }
        if isDeepThinking { tags.append("深度思考") }
        if totalIn >= 12_000 { tags.append("长上下文") }

        let highCost = !tags.isEmpty
        if isManagedChannel {
            let estOutMin = isDeepThinking ? 1_200.0 : 500.0
            let estOutMax = isAgentMode ? 5_000.0 : (isDeepThinking ? 3_200.0 : 1_800.0)
            let inCost = (Double(totalIn) / 1_000.0) * max(0, inputYuanPer1K)
            let minY = max(0.001, inCost + (estOutMin / 1_000.0) * max(0, outputYuanPer1K))
            var maxY = max(minY * 1.5, inCost * (isAgentMode ? 2.5 : 1.0) + (estOutMax / 1_000.0) * max(0, outputYuanPer1K))
            let cap = isAgentMode ? max(0.1, agentCapYuan) : nil
            if let cap { maxY = min(maxY, cap) }
            let tagText = tags.isEmpty ? "标准对话" : tags.joined(separator: "·")
            let capSuffix = cap.map { String(format: "，单次硬上限 ¥%.2f", $0) } ?? ""
            let banner = String(
                format: "预估消耗（%@）：约 ¥%.3f~¥%.3f%@ · 输入约 %@ tokens",
                tagText, minY, maxY, capSuffix, compactTokens(totalIn)
            )
            return PreFlightEstimate(
                estimatedInputTokens: totalIn,
                estimatedMinYuan: minY,
                estimatedMaxYuan: maxY,
                hardCapYuan: cap,
                isHighCost: highCost || maxY >= 0.05,
                reasonTags: tags,
                bannerText: banner
            )
        } else {
            let tagText = tags.isEmpty ? "标准对话" : tags.joined(separator: "·")
            let banner = "预估规模（\(tagText)）：约 \(compactTokens(totalIn)) tokens · 走自带 API（WUMIND 零加价）"
            return PreFlightEstimate(
                estimatedInputTokens: totalIn,
                estimatedMinYuan: nil,
                estimatedMaxYuan: nil,
                hardCapYuan: nil,
                isHighCost: highCost,
                reasonTags: tags,
                bannerText: banner
            )
        }
    }

    /// Returns true if switching from `fromPricePer1K` to `toPricePer1K` represents a meaningful price tier jump
    /// that must be explicitly explained to the user (never silently upgrade to a pricier model).
    public static func requiresUpgradeConfirmation(fromPricePer1K: Double, toPricePer1K: Double) -> Bool {
        guard fromPricePer1K > 0, toPricePer1K > fromPricePer1K else { return false }
        return toPricePer1K >= fromPricePer1K * 1.5 && (toPricePer1K - fromPricePer1K) >= 0.005
    }

    private static func compactTokens(_ n: Int) -> String {
        if n >= 10_000 {
            return String(format: "%.1fK", Double(n) / 1_000.0)
        }
        return "\(n)"
    }
}
