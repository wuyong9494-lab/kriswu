import Foundation
import XCTest
@testable import ShiftCore

final class WuMindContextEngineTests: XCTestCase {
    func testSupports1MContextWindow() {
        XCTAssertEqual(WuMindContextEngine.maxSupportedContextTokens, 1_000_000)
        XCTAssertEqual(
            WuMindContextEngine.supportedWindowTokens(provider: "gemini", modelID: "gemini-2.5-pro", preferredCap: 1_000_000),
            1_000_000
        )
        XCTAssertEqual(
            WuMindContextEngine.supportedWindowTokens(provider: "claude", modelID: "claude-sonnet-4-20250514", preferredCap: 1_000_000),
            1_000_000
        )
        XCTAssertEqual(
            WuMindContextEngine.supportedWindowTokens(provider: "deepSeek", modelID: "deepseek-reasoner", preferredCap: 1_000_000),
            1_000_000
        )
        XCTAssertEqual(
            WuMindContextEngine.supportedWindowTokens(provider: "openAI", modelID: "gpt-4.1", preferredCap: 256_000),
            256_000
        )
    }

    func testAutoCompactionTriggersAtThresholdAndPreservesRecentTurns() {
        let longChunk = String(repeating: "深度上下文测试内容ABCD1234", count: 200)
        let turns = (1...12).map { idx in
            WuMindContextEngine.TurnSnapshot(
                question: "第 \(idx) 轮问题：\(longChunk)",
                answer: "第 \(idx) 轮完整回答：\(longChunk)"
            )
        }

        // With a 32K window and 80% threshold, 12 heavy turns exceed 25.6K tokens -> triggers compaction!
        let plan = WuMindContextEngine.planContext(
            turns: turns,
            existingSummary: nil,
            compactedTurnCount: 0,
            pendingPrompt: "请总结刚才的全部讨论并给出最终步骤",
            systemPrompt: "你是架构师",
            maxWindowTokens: 32_000,
            autoCompactRatio: 0.80,
            keepRecentTurns: 6
        )

        XCTAssertTrue(plan.needsCompaction)
        XCTAssertEqual(plan.turnsToCompact.count, 6)
        XCTAssertEqual(plan.verbatimTurns.count, 6)
        XCTAssertEqual(plan.newCompactedTurnCount, 6)
        XCTAssertTrue(plan.verbatimTurns.first?.question.contains("第 7 轮") == true)
        XCTAssertTrue(plan.verbatimTurns.last?.question.contains("第 12 轮") == true)

        // After compaction is persisted, a second pass over the same turns with 1M budget needs no compaction.
        let summary = WuMindContextEngine.localCompact(existingSummary: nil, turnsToCompact: plan.turnsToCompact)
        XCTAssertTrue(summary.contains("第 1 轮"))
        XCTAssertTrue(summary.contains("第 6 轮"))

        let afterPlan = WuMindContextEngine.planContext(
            turns: turns,
            existingSummary: summary,
            compactedTurnCount: plan.newCompactedTurnCount,
            pendingPrompt: "继续",
            systemPrompt: nil,
            maxWindowTokens: 1_000_000
        )
        XCTAssertFalse(afterPlan.needsCompaction)
        XCTAssertEqual(afterPlan.verbatimTurns.count, 6)
        XCTAssertEqual(afterPlan.newCompactedTurnCount, 6)
    }

    func testManualCompactionAndPromptBlockFormatting() {
        let turns = (1...8).map {
            WuMindContextEngine.TurnSnapshot(question: "问题 \($0)", answer: "回答 \($0)")
        }
        let manual = WuMindContextEngine.planManualCompaction(turns: turns, compactedTurnCount: 0, keepRecentTurns: 4)
        XCTAssertNotNil(manual)
        XCTAssertEqual(manual?.turnsToCompact.count, 4)
        XCTAssertEqual(manual?.newCompactedTurnCount, 4)

        let instruction = WuMindContextEngine.compactionInstruction(existingSummary: "旧摘要：使用 Swift 6", turnsToCompact: manual!.turnsToCompact)
        XCTAssertTrue(instruction.contains("此前已压缩的更早记忆"))
        XCTAssertTrue(instruction.contains("问题 1"))
        XCTAssertTrue(instruction.contains("问题 4"))

        let sysBlock = WuMindContextEngine.formatCompactedSystemBlock(summary: "核心决定：1M 上下文", compactedTurnCount: 4)
        XCTAssertTrue(sysBlock.contains("已自动压缩前 4 轮历史"))
        XCTAssertTrue(sysBlock.contains("1M 上下文"))
    }

    private final class AtomicIntBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0
        func set(_ value: Int) {
            lock.lock(); defer { lock.unlock() }
            storage = value
        }
        func get() -> Int {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
    }

    func testDeepSeekExtendedContextAllowsLongPayloadsWhileDefaultRemainsStrict() async throws {
        // 30,000 CJK chars = 90,000 UTF-8 bytes (> 64KB default limit, well within 1M extendedContext limit)
        let hugePrompt = String(repeating: "长", count: 30_000)

        let capturedBodySize = AtomicIntBox()
        let stream = DeepSeekChatClient.streamEvents(
            messages: [.init(role: .user, content: hugePrompt)],
            apiKey: "sk-test-extended-1m",
            model: .pro,
            thinking: .normal,
            systemPrompt: String(repeating: "系", count: 15_000),
            extendedContext: true,
            transport: { request, status, line in
                capturedBodySize.set(request.httpBody?.count ?? 0)
                try status(200)
                try await line("data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"收到超长上下文\"},\"finish_reason\":\"stop\"}]}")
                try await line("data: [DONE]")
            }
        )

        var output = ""
        for try await ev in stream {
            if case .content(let delta) = ev { output += delta }
        }
        XCTAssertEqual(output, "收到超长上下文")
        XCTAssertGreaterThan(capturedBodySize.get(), 120_000)
    }
}
