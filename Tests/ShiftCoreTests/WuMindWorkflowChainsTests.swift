import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
@testable import ShiftCore

/// Deterministic end-to-end regression suite for WUMIND's two flagship workflow chains
/// and context/memory reliability contracts (runs on both Linux and macOS CI every build).
final class WuMindWorkflowChainsTests: XCTestCase {

    // MARK: - Golden Chain A: 值班截图 -> 站名表与发送规则核对 -> 标出疑点 -> 可分享结果

    func testGoldenChainA_DutyScreenshotStationTableRulesDoubtFlaggingAndShareableOutput() {
        let rules = [
            PassPlan.OperatorRule(name: "星网测控", prefixes: ["星网-"], exactStations: ["北站-01"]),
            PassPlan.OperatorRule(name: "中科站", prefixes: ["中科-"])
        ]

        let okRow = PassPlanRow(
            orbit: "1024",
            satelliteID: "S01",
            satellite: "SAT-01",
            station: "北站－０１",
            start: "2026-11-25 08:10:00",
            end: "2026-11-25 08:22:00",
            info: "数传",
            status: "正常"
        )
        let testRow = PassPlanRow(
            orbit: "1025",
            satelliteID: "S02",
            satellite: "SAT-02",
            station: "星网-03",
            start: "2026-11-25 09:00:00",
            end: "2026-11-25 09:10:00",
            info: "测试",
            status: "test"
        )
        let suspectRow = PassPlanRow(
            orbit: "1026",
            satelliteID: "S03",
            satellite: "SAT-03",
            station: "未知站-99",
            start: "2026-11-25 10:00:00",
            end: "2026-11-25 09:50:00", // intentionally invalid end < start
            info: "数传",
            status: "正常"
        )

        // 1. Station table exact alias routes cleanly; unmapped station stays unassigned
        XCTAssertEqual(PassPlan.operatorName(of: okRow.station, rules: rules), "星网测控")
        XCTAssertNil(PassPlan.operatorName(of: suspectRow.station, rules: rules))

        // 2. Sending rules strictly flag test rows and suspect rows (never silently send doubts)
        let testIssues = PassPlan.deliveryProblems(testRow, format: .recognizedContent, rules: rules)
        XCTAssertTrue(testIssues.contains(where: { $0.contains("test") }), "test 状态行必须被发送规则拦截")

        let suspectIssues = PassPlan.deliveryProblems(suspectRow, format: .recognizedContent, rules: rules)
        XCTAssertFalse(suspectIssues.isEmpty, "异常/未映射站名与时间倒挂必须标出疑点")

        // 3. Grouping & shareable output only counts verified sendable rows
        let groups = PassPlan.grouped([okRow, testRow, suspectRow], rules: rules)
        let xingwang = groups.first(where: { $0.name == "星网测控" })
        XCTAssertNotNil(xingwang)
        let shareTitle = PassPlan.originalImageTitle(name: "星网测控", rows: xingwang?.rows ?? [])
        XCTAssertEqual(shareTitle, "数传计划（星网测控）共 1 条")
        XCTAssertTrue(groups.contains(where: { $0.name == PassPlan.unassigned }), "未命中站名表的疑点行应单独归入未分组待核对")
    }

    // MARK: - Golden Chain B: 招标文件 -> 条款核对 + 标缺项 + 保留出处 -> 可编辑 Word (.docx)

    func testGoldenChainB_TenderClauseCheckMissingChecklistVerifiedSourceAndEditableDOCX() throws {
        let verifiedClause = DeepSeekTenderClient.Source(
            location: "第 4 页（PDF 本机核对）",
            quote: "投标人须提供近三年同类项目验收报告及原厂授权书",
            verified: true
        )
        let unverifiedClause = DeepSeekTenderClient.Source(
            location: "第888页",
            quote: "需提供备用电源参数",
            verified: false
        )

        let draft = DeepSeekTenderClient.Draft(
            title: "某测控通信系统升级采购投标书",
            sections: [
                .init(
                    title: "一、技术偏离与响应方案",
                    body: "本项目严格响应招标文件第 4 页核心指标要求，交付周期 30 个自然日。",
                    sources: [verifiedClause]
                )
            ],
            requirements: [
                .init(requirement: "交付周期响应", response: "承诺 30 天内到货并完成联调。", status: .drafted, source: verifiedClause),
                .init(requirement: "原厂授权书扫描件", response: "待补充加盖公章的原厂授权书。", status: .missing, source: verifiedClause),
                .init(requirement: "备用电源规格确认", response: "需人工核对原文参数。", status: .verify, source: unverifiedClause)
            ],
            missingFacts: [
                "缺失：原厂授权书（须加盖原厂公章）",
                "缺失：近三年同类项目验收报告扫描件"
            ],
            warnings: [
                "报价明细与盖章页需提交前人工复核"
            ]
        )

        let docxData = try TenderDOCXExporter.make(draft: draft)
        let entries = unpackStoredZIP(docxData)
        XCTAssertEqual(
            Set(entries.keys),
            ["[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/_rels/document.xml.rels", "word/styles.xml"]
        )
        for xml in entries.values {
            XCTAssertTrue(XMLParser(data: xml).parse(), "导出的 Word OpenXML 必须合法可编辑")
        }

        let documentXML = String(decoding: try XCTUnwrap(entries["word/document.xml"]), as: UTF8.self)
        XCTAssertTrue(documentXML.contains("某测控通信系统升级采购投标书"))
        XCTAssertTrue(documentXML.contains("逐项响应表"))
        XCTAssertTrue(documentXML.contains("缺材料"))
        XCTAssertTrue(documentXML.contains("原厂授权书（须加盖原厂公章）"))
        XCTAssertTrue(documentXML.contains("第 4 页（PDF 本机核对）"))
        XCTAssertFalse(documentXML.contains("第888页"), "未核实的模型猜测页码绝不能写入 Word 依据栏")
    }

    // MARK: - Context Reliability: 站名/规则版本冲突 + 项目隔离 + 临时聊天不串记忆

    func testContextReliability_ProjectIsolationRuleVersionConflictAndTempChatBoundary() throws {
        let projectA = UUID()
        let projectB = UUID()
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_100_000)

        let memories: [WuMindMemoryItem] = [
            WuMindMemoryItem(content: "旧站名表：北站-01 归属旧运维组", category: "站名表", ruleVersion: "v1.0", projectID: nil, updatedAt: older),
            WuMindMemoryItem(content: "新站名表：北站-01 改归星网测控", category: "站名表", ruleVersion: "v2.1", projectID: nil, updatedAt: newer),
            WuMindMemoryItem(content: "项目 A 专属标书报价规则：含税 13%", category: "标书", ruleVersion: "A-v1", projectID: projectA, updatedAt: newer),
            WuMindMemoryItem(content: "项目 B 机密规则：采用独立交付口径", category: "标书", ruleVersion: "B-v1", projectID: projectB, updatedAt: newer)
        ]

        let prefs = WuMindPreferences(userDisplayName: "值班员", memoryEnabled: true)

        // 1. Project A sees global + Project A memories ONLY, never Project B
        let promptA = try XCTUnwrap(prefs.formattedSystemProfileBlock(memories: memories, activeProjectID: projectA, isTemporaryChat: false))
        XCTAssertTrue(promptA.contains("项目 A 专属标书报价规则"))
        XCTAssertFalse(promptA.contains("项目 B 机密规则"), "不同项目的记忆和规则绝不能互串")

        // 2. Conflicting rule versions explicitly label 最新生效 vs 历史旧版 and require version disclosure
        XCTAssertTrue(promptA.contains("【规则与版本冲突准则】"))
        XCTAssertTrue(promptA.contains("本次采用规则版本"))
        XCTAssertTrue(promptA.contains("【最新生效】[全局·站名表 · 版本 v2.1]"))
        XCTAssertTrue(promptA.contains("【历史旧版】[全局·站名表 · 版本 v1.0]"))

        // 3. Temporary chat strictly blocks reading personal/project memories
        let tempPrompt = try XCTUnwrap(prefs.formattedSystemProfileBlock(memories: memories, activeProjectID: projectA, isTemporaryChat: true))
        XCTAssertTrue(tempPrompt.contains("无痕临时聊天"))
        XCTAssertFalse(tempPrompt.contains("项目 A 专属标书报价规则"))
        XCTAssertFalse(tempPrompt.contains("新站名表"))

        // 4. Legacy Codable payload without ruleVersion / projectID decodes cleanly
        let legacyJSON = #"{"id":"00000000-0000-0000-0000-000000000001","content":"旧版偏好","category":"偏好","updatedAt":1700000000}"#
        let decoded = try JSONDecoder().decode(WuMindMemoryItem.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.content, "旧版偏好")
        XCTAssertNil(decoded.ruleVersion)
        XCTAssertNil(decoded.projectID)
    }

    private func unpackStoredZIP(_ data: Data) -> [String: Data] {
        let bytes = Array(data)
        func le(_ start: Int, _ count: Int) -> Int {
            (0..<count).reduce(0) { $0 | (Int(bytes[start + $1]) << (8 * $1)) }
        }
        var index = 0
        var out: [String: Data] = [:]
        while index + 30 <= bytes.count, le(index, 4) == 0x04034B50 {
            let nameLen = le(index + 26, 2)
            let extraLen = le(index + 28, 2)
            let size = le(index + 18, 4)
            let bodyStart = index + 30 + nameLen + extraLen
            guard bodyStart + size <= bytes.count else { return [:] }
            let name = String(decoding: bytes[(index + 30)..<(index + 30 + nameLen)], as: UTF8.self)
            out[name] = Data(bytes[bodyStart..<(bodyStart + size)])
            index = bodyStart + size
        }
        return out
    }
}
