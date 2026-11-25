import Foundation
import XCTest
@testable import ShiftCore

/// Regression tests for WUMIND's core multi-model differentiator:
/// - Mid-thread shared materials continuity across vendor switches (zero re-upload)
/// - Structured dual-model cross-review (consensus, evidence, divergence, revision)
/// - Pre-flight cost estimation & anti-silent-upgrade guardrails
final class WuMindMultiModelEngineTests: XCTestCase {

    func testSharedMaterialsMergeDeduplicatesAndFormatsAcrossModelSwitches() throws {
        let doc1 = WuMindThreadMaterial(
            filename: "供应商合同.pdf",
            summaryBadge: "PDF · 12 页",
            extractedText: "第 8 条 违约责任：延迟交付每日按合同总额 0.5% 扣款。",
            byteCount: 120_000
        )
        let doc1Updated = WuMindThreadMaterial(
            filename: "供应商合同.pdf",
            summaryBadge: "PDF · 12 页（修订版）",
            extractedText: "第 8 条 违约责任：延迟交付每日按合同总额 0.3% 扣款，上限 5%。",
            byteCount: 122_000
        )
        let doc2 = WuMindThreadMaterial(
            filename: "报价明细.xlsx",
            summaryBadge: "Excel · 2 表",
            extractedText: "总报价：185.0 万元（含税 13%）。",
            byteCount: 45_000
        )

        let merged = WuMindMultiModelEngine.mergeThreadMaterials(existing: [doc1], incoming: [doc1Updated, doc2])
        XCTAssertEqual(merged.count, 2, "同名文件应覆盖更新而非重复堆叠")
        XCTAssertTrue(merged[0].extractedText.contains("0.3%"))

        let block = try XCTUnwrap(WuMindMultiModelEngine.formattedSharedMaterialsBlock(materials: merged))
        XCTAssertTrue(block.contains("跨模型自动延续"))
        XCTAssertTrue(block.contains("供应商合同.pdf"))
        XCTAssertTrue(block.contains("报价明细.xlsx"))
        XCTAssertTrue(block.contains("185.0 万元"))
    }

    func testCrossReviewPromptRequiresConsensusDivergenceAndEvidenceStructure() {
        let sys = WuMindMultiModelEngine.crossReviewSystemPrompt(primaryModel: "DeepSeek V4 Pro", reviewerModel: "Claude Sonnet 4")
        XCTAssertTrue(sys.contains("共识与可采纳依据"))
        XCTAssertTrue(sys.contains("分歧点与遗漏风险"))
        XCTAssertTrue(sys.contains("修订建议"))
        XCTAssertTrue(sys.contains("DeepSeek V4 Pro"))

        let user = WuMindMultiModelEngine.crossReviewUserPrompt(
            question: "这份合同第 8 条违约金上限有没有风险？",
            primaryModel: "DeepSeek V4 Pro",
            primaryAnswer: "原回答认为违约金上限 5% 合理。",
            sharedMaterialsBlock: "【共享文件：供应商合同.pdf】第 8 条..."
        )
        XCTAssertTrue(user.contains("供应商合同.pdf"))
        XCTAssertTrue(user.contains("原回答认为违约金上限 5% 合理"))
    }

    func testCostTransparencyPreFlightAndAntiSilentUpgradeGuard() {
        // High-cost managed task (long doc + agent + deep thinking) produces bounded estimate & hard cap
        let est = WuMindCostTransparency.estimatePreFlight(
            promptText: "请深度审阅这份合同并联网查同类判例",
            attachmentChars: 18_000,
            sharedMaterialChars: 6_000,
            historyTokens: 4_000,
            isDeepThinking: true,
            isAgentMode: true,
            agentCapYuan: 2.0,
            isManagedChannel: true,
            inputYuanPer1K: 0.015,
            outputYuanPer1K: 0.060
        )
        XCTAssertTrue(est.isHighCost)
        XCTAssertEqual(est.hardCapYuan, 2.0)
        XCTAssertNotNil(est.estimatedMinYuan)
        XCTAssertNotNil(est.estimatedMaxYuan)
        XCTAssertLessThanOrEqual(est.estimatedMaxYuan ?? 99, 2.0)
        XCTAssertTrue(est.bannerText.contains("硬上限"))

        // Own-API long-doc notice clearly says zero markup
        let ownEst = WuMindCostTransparency.estimatePreFlight(
            promptText: "分析文档",
            attachmentChars: 10_000,
            sharedMaterialChars: 0,
            historyTokens: 500,
            isDeepThinking: false,
            isAgentMode: false,
            agentCapYuan: 2.0,
            isManagedChannel: false,
            inputYuanPer1K: 0,
            outputYuanPer1K: 0
        )
        XCTAssertTrue(ownEst.isHighCost)
        XCTAssertNil(ownEst.estimatedMaxYuan)
        XCTAssertTrue(ownEst.bannerText.contains("零加价"))

        // Upgrade guard: triggers on meaningful jump, never on equal or cheaper switches
        XCTAssertTrue(WuMindCostTransparency.requiresUpgradeConfirmation(fromPricePer1K: 0.008, toPricePer1K: 0.060))
        XCTAssertFalse(WuMindCostTransparency.requiresUpgradeConfirmation(fromPricePer1K: 0.060, toPricePer1K: 0.008))
        XCTAssertFalse(WuMindCostTransparency.requiresUpgradeConfirmation(fromPricePer1K: 0.010, toPricePer1K: 0.012))
    }
}
