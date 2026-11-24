import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class WuMindFlagshipTests: XCTestCase {
    func testProjectSystemBlockAndKnowledgeSearch() {
        let doc1 = WuMindProjectDoc(
            filename: "Architecture.md",
            kindRaw: "text",
            summaryBadge: "MD · 2KB",
            extractedText: "模块 A 负责 60Hz 对战同步。\n\n模块 B 负责 Cloudflare D1 按 Token 实时计费扣款。"
        )
        let doc2 = WuMindProjectDoc(
            filename: "Pricing.csv",
            kindRaw: "excel",
            summaryBadge: "CSV · 1KB",
            extractedText: "deepseek-reasoner, 12.0, 36.0\ngpt-5, 25.0, 100.0"
        )
        let project = WuMindProject(
            name: "WUMIND 商业化项目",
            customInstructions: "回答严格引用项目文档数据",
            attachedRepoFullName: "wuyong9494-lab/kriswu",
            knowledgeDocs: [doc1, doc2]
        )

        let block = project.formattedProjectSystemBlock()
        XCTAssertTrue(block.contains("WUMIND 商业化项目"))
        XCTAssertTrue(block.contains("wuyong9494-lab/kriswu"))
        XCTAssertTrue(block.contains("Architecture.md"))

        let searchResult = WuMindAgentTools.searchProjectKnowledge(query: "Cloudflare 计费", docs: project.knowledgeDocs)
        XCTAssertTrue(searchResult.succeeded)
        XCTAssertTrue(searchResult.observationText.contains("Architecture.md"))
        XCTAssertTrue(searchResult.observationText.contains("按 Token 实时计费"))
    }

    func testScheduledTaskCadenceNextRunDates() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 10, minute: 0))!

        // Daily at 08:30 (already passed today -> schedules tomorrow 08:30)
        let dailyNext = WuMindScheduleCadence.daily(hour: 8, minute: 30).nextRunDate(after: now, calendar: cal)
        XCTAssertNotNil(dailyNext)
        let comps = cal.dateComponents([.day, .hour, .minute], from: dailyNext!)
        XCTAssertEqual(comps.day, 25)
        XCTAssertEqual(comps.hour, 8)
        XCTAssertEqual(comps.minute, 30)

        // Interval 4 hours
        let intervalNext = WuMindScheduleCadence.intervalHours(4).nextRunDate(after: now, calendar: cal)
        XCTAssertEqual(intervalNext?.timeIntervalSince(now) ?? 0, 14_400, accuracy: 1.0)

        // Once in past returns nil
        let pastOnce = WuMindScheduleCadence.once(now.addingTimeInterval(-60)).nextRunDate(after: now, calendar: cal)
        XCTAssertNil(pastOnce)
    }

    func testAgentToolProtocolParsingBudgetGuardrailsAndCumulativeMetering() {
        let modelReply = """
        我先帮您查询仓库源码并验算费用。
        <wumind_tool>{"tool":"calculator_verify","args":{"expression":"(12.5*2+15)/4"}}</wumind_tool>
        """
        let inv = WuMindAgentProtocol.parseToolInvocation(from: modelReply)
        XCTAssertEqual(inv?.tool, "calculator_verify")
        XCTAssertEqual(inv?.args["expression"], "(12.5*2+15)/4")
        XCTAssertEqual(WuMindAgentProtocol.stripToolTags(from: modelReply), "我先帮您查询仓库源码并验算费用。")

        // Verify exact calculator tool
        let calc = WuMindAgentTools.evaluateMathExpression(inv!.args["expression"]!)
        XCTAssertTrue(calc.succeeded)
        XCTAssertTrue(calc.summary.contains("10"))

        // Verify cumulative multi-step token & cost aggregation
        let steps = [
            WuMindAgentStep(stepIndex: 1, phase: .toolCall, toolName: "github_inspect", toolSummary: "ok",
                            promptTokens: 2_000, completionTokens: 400, reasoningTokens: 300, costYuan: 0.045),
            WuMindAgentStep(stepIndex: 2, phase: .toolCall, toolName: "web_fetch", toolSummary: "ok",
                            promptTokens: 4_500, completionTokens: 600, reasoningTokens: 500, costYuan: 0.095),
        ]
        let totals = WuMindAgentUsageTotals.aggregate(
            steps: steps,
            finalPromptTokens: 6_000,
            finalCompletionTokens: 1_200,
            finalReasoningTokens: 400,
            finalCostYuan: 0.160
        )
        XCTAssertEqual(totals.stepCount, 3)
        XCTAssertEqual(totals.promptTokens, 12_500)
        XCTAssertEqual(totals.completionTokens, 2_200)
        XCTAssertEqual(totals.reasoningTokens, 1_200)
        XCTAssertEqual(totals.totalTokens, 15_900)
        XCTAssertEqual(totals.costYuan, 0.30, accuracy: 0.00001)

        // Verify budget guardrail stops before overspending on managed channel
        XCTAssertNil(WuMindAgentProtocol.budgetStopReason(completedSteps: 2, maxSteps: 6, accumulatedCostYuan: 0.30, maxCostYuan: 2.0, isManagedChannel: true))
        XCTAssertNotNil(WuMindAgentProtocol.budgetStopReason(completedSteps: 2, maxSteps: 6, accumulatedCostYuan: 2.05, maxCostYuan: 2.0, isManagedChannel: true))
        XCTAssertNotNil(WuMindAgentProtocol.budgetStopReason(completedSteps: 6, maxSteps: 6, accumulatedCostYuan: 0.10, maxCostYuan: 2.0, isManagedChannel: false))
    }

    func testWebFetchRejectsLocalhostAndPrivateIPsAndStripsHTML() async {
        XCTAssertNil(WuMindAgentTools.validateExternalHTTPSURL("http://example.com"))
        XCTAssertNil(WuMindAgentTools.validateExternalHTTPSURL("https://localhost/admin"))
        XCTAssertNil(WuMindAgentTools.validateExternalHTTPSURL("https://127.0.0.1/secret"))
        XCTAssertNil(WuMindAgentTools.validateExternalHTTPSURL("https://192.168.1.1/router"))
        XCTAssertNil(WuMindAgentTools.validateExternalHTTPSURL("https://10.0.0.5/internal"))
        XCTAssertNotNil(WuMindAgentTools.validateExternalHTTPSURL("https://developer.apple.com/documentation"))

        let res = await WuMindAgentTools.webFetch(urlString: "https://example.com/doc") { req in
            let html = "<html><head><script>alert(1)</script><style>body{}</style></head><body><h1>WUMIND</h1><p>支持 1M 上下文 &amp; 智能体。</p></body></html>"
            let http = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(html.utf8), http)
        }
        XCTAssertTrue(res.succeeded)
        XCTAssertTrue(res.observationText.contains("WUMIND"))
        XCTAssertTrue(res.observationText.contains("支持 1M 上下文 & 智能体"))
        XCTAssertFalse(res.observationText.contains("alert(1)"))
    }

    func testCustomizationCatalogAndPreferencesProfileBlock() {
        XCTAssertGreaterThanOrEqual(WuMindConnectorSpec.marketplaceCatalog.count, 10)
        XCTAssertTrue(WuMindConnectorSpec.defaultInstalledIDs.contains("dev.github"))
        XCTAssertFalse(WuMindConnectorSpec.defaultInstalledIDs.contains("duty.schedule")) // Opt-in privacy boundary!

        let prefs = WuMindPreferences(userDisplayName: "Kris", userRoleBackground: "航天测控架构师", memoryEnabled: true)
        let block = prefs.formattedSystemProfileBlock(memories: [WuMindMemoryItem(content: "优先输出 Swift 6 无警告代码")])
        XCTAssertNotNil(block)
        XCTAssertTrue(block!.contains("Kris"))
        XCTAssertTrue(block!.contains("Swift 6"))
    }
}
