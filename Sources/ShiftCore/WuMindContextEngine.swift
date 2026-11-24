import Foundation

/// Context window & Claude-style automatic context compaction engine for WUMIND.
/// Supports up to 1,000,000 (1M) token context windows with automatic semantic compaction
/// when active history approaches the budget (preserving recent turns verbatim).
public enum WuMindContextEngine {
    public static let maxSupportedContextTokens = 1_000_000
    public static let defaultAutoCompactRatio = 0.80
    public static let defaultKeepRecentTurns = 6

    public struct TurnSnapshot: Equatable, Sendable {
        public let question: String
        public let answer: String

        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }

    public struct ContextPlan: Equatable, Sendable {
        public let estimatedTokens: Int
        public let maxWindowTokens: Int
        public let usageRatio: Double
        public let needsCompaction: Bool
        public let turnsToCompact: [TurnSnapshot]
        public let verbatimTurns: [TurnSnapshot]
        public let newCompactedTurnCount: Int
    }

    /// Returns the supported context budget (up to 1M tokens) for a model/provider.
    public static func supportedWindowTokens(provider: String, modelID: String, preferredCap: Int = maxSupportedContextTokens) -> Int {
        let clampedCap = min(maxSupportedContextTokens, max(32_000, preferredCap))
        let lower = modelID.lowercased()
        let modelNative: Int
        if provider == "gemini" || lower.contains("gemini") || lower.contains("gpt-4.1") || lower.contains("gpt-5")
            || lower.contains("claude-sonnet-4") || lower.contains("claude-opus-4") || lower.contains("1m") {
            modelNative = 1_000_000
        } else if provider == "claude" || provider == "grok" || provider == "openAI" || provider == "deepSeek" {
            // Allow full user-selected budget up to 1M (auto-compaction safely trims when needed)
            modelNative = 1_000_000
        } else {
            modelNative = 256_000
        }
        return min(modelNative, clampedCap)
    }

    /// Fast bilingual (CJK + Latin/Code) token estimator.
    public static func estimateTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var asciiBytes = 0
        var nonASCIIUnits = 0
        for scalar in text.unicodeScalars {
            if scalar.value < 128 {
                asciiBytes += 1
            } else {
                nonASCIIUnits += 1
            }
        }
        // English/code averages ~4 bytes/token; Chinese characters average ~1.3–1.6 tokens/char
        let est = (asciiBytes + 3) / 4 + Int((Double(nonASCIIUnits) * 1.45).rounded(.up))
        return max(1, est)
    }

    /// Computes live token usage & determines whether Claude-style automatic compaction should trigger.
    public static func planContext(
        turns: [TurnSnapshot],
        existingSummary: String?,
        compactedTurnCount: Int,
        pendingPrompt: String,
        systemPrompt: String?,
        maxWindowTokens: Int = maxSupportedContextTokens,
        autoCompactRatio: Double = defaultAutoCompactRatio,
        keepRecentTurns: Int = defaultKeepRecentTurns
    ) -> ContextPlan {
        let safeCompacted = min(max(0, compactedTurnCount), turns.count)
        let activeTurns = Array(turns.dropFirst(safeCompacted))
        let baseTokens =
            estimateTokens(systemPrompt ?? "")
            + estimateTokens(existingSummary ?? "")
            + estimateTokens(pendingPrompt)
        let activeTurnTokens = activeTurns.reduce(0) { $0 + estimateTokens($1.question) + estimateTokens($1.answer) }
        let total = baseTokens + activeTurnTokens
        let window = max(16_000, min(maxSupportedContextTokens, maxWindowTokens))
        let ratio = min(1.0, Double(total) / Double(window))
        let threshold = Int(Double(window) * autoCompactRatio)

        let canCompact = activeTurns.count > keepRecentTurns
        let needsCompaction = canCompact && total >= threshold

        if needsCompaction {
            let splitIndex = max(1, activeTurns.count - keepRecentTurns)
            let toCompact = Array(activeTurns.prefix(splitIndex))
            let tail = Array(activeTurns.suffix(activeTurns.count - splitIndex))
            return ContextPlan(
                estimatedTokens: total,
                maxWindowTokens: window,
                usageRatio: ratio,
                needsCompaction: true,
                turnsToCompact: toCompact,
                verbatimTurns: tail,
                newCompactedTurnCount: safeCompacted + splitIndex
            )
        }

        return ContextPlan(
            estimatedTokens: total,
            maxWindowTokens: window,
            usageRatio: ratio,
            needsCompaction: false,
            turnsToCompact: [],
            verbatimTurns: activeTurns,
            newCompactedTurnCount: safeCompacted
        )
    }

    /// Plans an on-demand manual compaction (just like Claude's `/compact`), keeping the latest turns verbatim.
    public static func planManualCompaction(
        turns: [TurnSnapshot],
        compactedTurnCount: Int,
        keepRecentTurns: Int = 4
    ) -> (turnsToCompact: [TurnSnapshot], newCompactedTurnCount: Int)? {
        let safeCompacted = min(max(0, compactedTurnCount), turns.count)
        let activeTurns = Array(turns.dropFirst(safeCompacted))
        guard activeTurns.count > max(1, keepRecentTurns) else {
            guard activeTurns.count >= 2 else { return nil }
            let split = activeTurns.count - 1
            return (Array(activeTurns.prefix(split)), safeCompacted + split)
        }
        let split = activeTurns.count - keepRecentTurns
        return (Array(activeTurns.prefix(split)), safeCompacted + split)
    }

    /// Builds a Claude-style semantic compaction prompt for live AI summarization of older turns.
    public static func compactionInstruction(existingSummary: String?, turnsToCompact: [TurnSnapshot]) -> String {
        var sections: [String] = []
        sections.append("""
        你是 WUMIND 上下文自动压缩引擎。请将下方历史对话压缩为一份高密度、结构化的连续记忆摘要，供后续对话无缝衔接（类似 Claude 自动上下文压缩）：
        要求：
        1. 严格保留所有关键事实、用户目标与约束、明确做出的决策、精确数字/金额/日期、代码文件名与接口符号、以及尚未完成的待办事项；
        2. 删除寒暄、重复阐述与中间试错废话；
        3. 使用简洁清晰的 Markdown 分节输出：【核心目标与约束】【已确认事实与决策】【关键文件/代码/数据】【未完成事项】，总长度控制在 1500 字以内。
        """)
        if let existingSummary, !existingSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("【此前已压缩的更早记忆】\n\(String(existingSummary.prefix(8_000)))")
        }
        var transcriptLines: [String] = ["【本次待压缩的对话记录】"]
        for (idx, t) in turnsToCompact.enumerated() {
            let q = String(t.question.prefix(2_000))
            let a = String(t.answer.prefix(4_000))
            transcriptLines.append("第 \(idx + 1) 轮\n用户：\(q)\n助手：\(a)")
        }
        sections.append(transcriptLines.joined(separator: "\n\n"))
        return sections.joined(separator: "\n\n---\n\n")
    }

    /// Deterministic local fallback compaction when AI semantic compaction is unavailable or offline.
    public static func localCompact(existingSummary: String?, turnsToCompact: [TurnSnapshot], maxChars: Int = 14_000) -> String {
        var parts: [String] = []
        if let existing = existingSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            parts.append(String(existing.prefix(maxChars / 2)))
        }
        var bullets: [String] = []
        for turn in turnsToCompact {
            let cleanQ = turn.question
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanA = turn.answer
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let qSnippet = cleanQ.count > 160 ? String(cleanQ.prefix(160)) + "…" : cleanQ
            let aSnippet = cleanA.count > 320 ? String(cleanA.prefix(320)) + "…" : cleanA
            bullets.append("- 问：\(qSnippet)\n  答：\(aSnippet)")
        }
        if !bullets.isEmpty {
            parts.append("【自动压缩对话要点】\n" + bullets.joined(separator: "\n"))
        }
        let merged = parts.joined(separator: "\n\n")
        if merged.count <= maxChars { return merged }
        return String(merged.suffix(maxChars))
    }

    /// Wraps compacted memory cleanly for injection into the system prompt across all 5 providers.
    public static func formatCompactedSystemBlock(summary: String, compactedTurnCount: Int) -> String {
        """
        [WUMIND 历史上下文自动压缩记忆（已自动压缩前 \(compactedTurnCount) 轮历史，请无缝延续上下文）]
        \(summary)
        """
    }
}
