import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
@testable import ShiftCore

/// Full OpenXML structural & functional regression tests for WUMIND's autonomous `.pptx` PowerPoint engine:
/// - Acceptance Scenario 1: Single-sentence "做一份 8 页年终工作总结" (zero fabricated metrics, real editable .pptx)
/// - Acceptance Scenario 2: PDF + Excel grounded report with citations, editable tables, and native charts backed by embedded .xlsx
/// - Automated quality self-repair (text overflow, element overlap, blank slides, chart/table alignment)
final class WuMindPPTXExporterTests: XCTestCase {

    // MARK: - Acceptance Scenario 1: 一句话「做一份 8 页年终工作总结」不虚构业绩数字 + 真 .pptx

    func testAcceptanceScenario1_EightSlideYearEndSummaryNoFabricationAndValidPPTX() throws {
        let prompt = "做一份 8 页年终工作总结"
        XCTAssertEqual(WuMindPPTEngine.extractRequestedSlideCount(from: prompt, fallback: 6), 8)

        // Simulate an LLM response that accidentally hallucinates a concrete revenue number and a chart despite zero uploaded data.
        let simulatedJSON = """
        ```json
        {
          "title": "2026 年度工作总结与 2027 规划",
          "subtitle": "聚焦重点任务复盘、能力沉淀与来年目标对齐",
          "slides": [
            { "title": "2026 年度工作总结", "layout": "cover", "bullets": ["年度复盘与来年行动规划"], "speakerNotes": "各位领导、同事大家好，今天汇报我 2026 年度的核心工作复盘。" },
            { "title": "目录与汇报框架", "layout": "agenda", "bullets": ["年度核心任务回顾", "关键成果与亮点", "问题复盘与改进", "2027 年重点规划"], "speakerNotes": "整体汇报分为四个部分，重点交代真实产出与来年改进计划。" },
            { "title": "年度核心业绩指标", "layout": "metrics", "highlightMetric": "¥1,280万", "highlightLabel": "年度完成营收", "bullets": ["主线项目按期交付，保障核心业务平稳运行", "【待补】请填入实际完成率与考核口径"], "speakerNotes": "本页展示核心 KPI 指标，具体数字将在会前按财务口径核对填入。" },
            { "title": "季度推进趋势", "layout": "chart", "bullets": ["各季度节奏保持稳定推进"], "chart": { "kind": "bar", "title": "季度完成额", "unit": "万元", "categories": ["Q1","Q2","Q3","Q4"], "series": [{"name": "完成额", "values": [260, 310, 340, 370]}] }, "speakerNotes": "各季度推进节奏与关键节点说明。" },
            { "title": "重点项目与协同成果", "layout": "twoColumn", "bullets": ["建立标准化交付流程，缩短交接耗时", "跨团队协作打通关键阻塞环节", "沉淀复用文档与操作规范", "【待补】补充代表性项目名称与验收结果"], "speakerNotes": "重点汇报跨团队协同与方法沉淀。" },
            { "title": "问题剖析与反思", "layout": "table", "bullets": ["聚焦可落地的根因与改进措施"], "table": { "headers": ["问题类别", "现状描述", "改进措施"], "rows": [["需求变更", "中期需求波动导致返工", "建立冻结与评审机制"], ["进度监控", "【待补】具体延期环节", "引入周度风险预警"]] }, "speakerNotes": "直面不足，聚焦机制优化。" },
            { "title": "2027 年度目标与行动计划", "layout": "bullets", "bullets": ["明确 Q1 核心上线里程碑与责任分工", "【待补】核定年度 KPI 考核指标", "强化自动化测试与质量门禁建设"], "speakerNotes": "介绍明年一季度起跑计划与资源需求。" },
            { "title": "总结与致谢", "layout": "summary", "bullets": ["感谢团队支持，以上【待补】指标将在提交前补齐真实数据", "欢迎各位领导提出宝贵建议"], "speakerNotes": "感谢聆听，请各位领导批评指正。" }
          ]
        }
        ```
        """

        let parsed = WuMindPPTEngine.parseDeck(from: simulatedJSON, fallbackTopic: prompt, theme: .executiveBlue)
        let inspected = WuMindPPTEngine.inspectAndRepair(
            parsed,
            expectedSlideCount: 8,
            hasSourceMaterials: false,
            webSearchUsed: false
        )

        // 1. Exact 8 slides, zero fabricated business numbers!
        XCTAssertEqual(inspected.slides.count, 8)
        XCTAssertEqual(inspected.slides[2].highlightMetric, "【待补】", "无原始资料时绝不允许保留虚构营收数字")
        XCTAssertNil(inspected.slides[3].chart, "无原始资料时应把虚构图表降级为待补可编辑表格")
        XCTAssertNotNil(inspected.slides[3].table)
        XCTAssertGreaterThanOrEqual(inspected.qualityReport?.pendingPlaceholderCount ?? 0, 2)

        // 2. Export real `.pptx` & perform strict OpenXML package integrity audit
        let pptxData = try WuMindPPTXExporter.make(deck: inspected)
        let parts = try assertValidOpenXMLPPTX(pptxData, expectedSlides: 8, expectedCharts: 0)

        // Verify fabricated figure never enters slide XML and editable tables + notes exist
        let slide3XML = String(decoding: try XCTUnwrap(parts["ppt/slides/slide3.xml"]), as: UTF8.self)
        XCTAssertFalse(slide3XML.contains("1,280万"))
        XCTAssertTrue(slide3XML.contains("【待补】"))
        let slide6XML = String(decoding: try XCTUnwrap(parts["ppt/slides/slide6.xml"]), as: UTF8.self)
        XCTAssertTrue(slide6XML.contains("<a:tbl>"), "表格页必须输出 PowerPoint/WPS 原生可编辑 DrawingML 表格")
        let notes1XML = String(decoding: try XCTUnwrap(parts["ppt/notesSlides/notesSlide1.xml"]), as: UTF8.self)
        XCTAssertTrue(notes1XML.contains("2026 年度的核心工作复盘"))
    }

    // MARK: - Acceptance Scenario 2: PDF + Excel 资料 -> 带引用 + 可编辑表格 + 真 Excel 驱动图表 .pptx

    func testAcceptanceScenario2_PDFAndExcelSourcesEditableChartEmbeddedXLSXAndCitations() throws {
        // 1. Parse real CSV/Excel-like source + PDF-like text via WuMindAttachmentParser
        let csvRaw = "季度,实际营收(万元),目标营收(万元)\nQ1,128.5,120\nQ2,156.0,150\nQ3,189.2,180\nQ4,234.8,210\n"
        let csvDoc = try WuMindAttachmentParser.extract(data: Data(csvRaw.utf8), filename: "2026经营台账.csv")
        XCTAssertTrue(csvDoc.extractedText.contains("234.8"))

        // 2. Build grounded presentation referencing uploaded PDF & Excel
        var deck = WuMindPPTDeck(
            title: "2026 年度经营分析与项目复盘汇报",
            subtitle: "数据来源：2026经营台账.xlsx · 年度项目审计报告.pdf",
            theme: .minimalIvory,
            slides: [
                .init(
                    id: 1,
                    title: "2026 年度经营分析汇报",
                    layout: .cover,
                    bullets: ["基于财务台账与项目审计原文生成，全部数字可溯源"],
                    speakerNotes: "本次汇报全部数据严格引用 2026 经营台账与项目审计报告。",
                    citations: ["来源：2026经营台账.xlsx", "来源：年度项目审计报告.pdf"]
                ),
                .init(
                    id: 2,
                    title: "各季度营收达成与目标对比",
                    layout: .chart,
                    bullets: [
                        "全年四个季度均超额完成目标，Q4 达到 234.8 万元",
                        "Q4 同比 Q1 增长 82.7%，增长斜率持续抬升",
                        "建议在 PowerPoint / WPS 中点击「编辑数据」直接联动更新"
                    ],
                    speakerNotes: "从右侧柱状图可见，四个季度实际营收均高于预算目标，Q4 突破 234.8 万元。",
                    chart: .init(
                        kind: .bar,
                        title: "2026 季度实际营收 vs 目标",
                        unit: "万元",
                        categories: ["Q1", "Q2", "Q3", "Q4"],
                        series: [
                            .init(name: "实际营收", values: [128.5, 156.0, 189.2, 234.8]),
                            .init(name: "目标营收", values: [120.0, 150.0, 180.0, 210.0])
                        ]
                    ),
                    citations: ["来源：2026经营台账.xlsx · Sheet1"]
                ),
                .init(
                    id: 3,
                    title: "重点项目交付核查表",
                    layout: .table,
                    bullets: ["核心里程碑均按审计报告节点验收，缺失发票项已标待补"],
                    speakerNotes: "下表逐项核对三大重点项目交付状态与原文出处。",
                    table: .init(
                        headers: ["项目名称", "合同额(万)", "验收状态", "出处"],
                        rows: [
                            ["测控平台一期", "180.0", "已验收", "审计报告.pdf 第 3 页"],
                            ["数据中台升级", "210.5", "试运行", "审计报告.pdf 第 7 页"],
                            ["备件保供协议", "【待补】", "待签章", "需补充盖章扫描件"]
                        ]
                    ),
                    citations: ["来源：年度项目审计报告.pdf · 第 3-7 页"],
                    pendingItems: ["待补：备件保供协议最终合同金额"]
                ),
                .init(
                    id: 4,
                    title: "各业务线占比与趋势（折线图）",
                    layout: .chart,
                    bullets: ["核心测控业务占比稳步提升"],
                    speakerNotes: "展示核心业务占比变化趋势。",
                    chart: .init(
                        kind: .line,
                        title: "毛利率变化趋势",
                        unit: "%",
                        categories: ["Q1", "Q2", "Q3", "Q4"],
                        series: [.init(name: "综合毛利率", values: [41.2, 43.5, 45.8, 48.1])]
                    ),
                    citations: ["来源：2026经营台账.xlsx · 利润率表"]
                ),
                .init(
                    id: 5,
                    title: "总结与下阶段行动建议",
                    layout: .summary,
                    bullets: [
                        "保持高毛利测控产品线投入，延续 Q4 增长动能",
                        "优先补齐备件保供协议合同额并完成归档"
                    ],
                    speakerNotes: "总结本年度经营亮点与下一步落地分工。",
                    citations: ["来源：年度项目审计报告.pdf · 第 12 页"]
                )
            ],
            audience: .executive,
            sourceFiles: ["2026经营台账.xlsx", "年度项目审计报告.pdf"]
        )

        deck = WuMindPPTEngine.inspectAndRepair(deck, expectedSlideCount: nil, hasSourceMaterials: true, webSearchUsed: false)
        XCTAssertEqual(deck.qualityReport?.editableChartsCount, 2)
        XCTAssertEqual(deck.qualityReport?.editableTablesCount, 1)
        XCTAssertGreaterThanOrEqual(deck.qualityReport?.citationsCount ?? 0, 5)

        // 3. Export `.pptx` and verify EVERY OpenXML part + nested Excel `.xlsx` workbook!
        let pptxData = try WuMindPPTXExporter.make(deck: deck)
        let parts = try assertValidOpenXMLPPTX(pptxData, expectedSlides: 5, expectedCharts: 2)

        // Check chart1.xml links to Microsoft_Excel_Worksheet1.xlsx and embeds live editable workbook!
        let chart1XML = String(decoding: try XCTUnwrap(parts["ppt/charts/chart1.xml"]), as: UTF8.self)
        XCTAssertTrue(chart1XML.contains("<c:barChart>"))
        XCTAssertTrue(chart1XML.contains("<c:externalData r:id=\"rId1\">"))
        XCTAssertTrue(chart1XML.contains("234.8"))

        let xlsx1Data = try XCTUnwrap(parts["ppt/embeddings/Microsoft_Excel_Worksheet1.xlsx"], "图表必须内嵌可编辑 Excel 工作簿")
        let xlsx1Parts = unpackZIP(xlsx1Data)
        XCTAssertEqual(
            Set(xlsx1Parts.keys),
            ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml"]
        )
        for (_, xmlBytes) in xlsx1Parts {
            XCTAssertTrue(XMLParser(data: xmlBytes).parse(), "内嵌 Excel 工作簿中每个 XML 必须严格合法")
        }
        let sheet1XML = String(decoding: try XCTUnwrap(xlsx1Parts["xl/worksheets/sheet1.xml"]), as: UTF8.self)
        XCTAssertTrue(sheet1XML.contains("实际营收"))
        XCTAssertTrue(sheet1XML.contains("<v>234.8</v>"))
        XCTAssertTrue(sheet1XML.contains("<v>210</v>"))

        // 4. Simulate user editing 1 slide title + 1 chart numeric value and re-exporting!
        deck.slides[1].title = "各季度营收达成（已人工复核）"
        deck.slides[1].chart?.series[0].values[3] = 260.5
        let editedData = try WuMindPPTXExporter.make(deck: deck)
        let editedParts = try assertValidOpenXMLPPTX(editedData, expectedSlides: 5, expectedCharts: 2)
        let editedSlide2 = String(decoding: try XCTUnwrap(editedParts["ppt/slides/slide2.xml"]), as: UTF8.self)
        XCTAssertTrue(editedSlide2.contains("各季度营收达成（已人工复核）"))
        let editedSheet1 = String(
            decoding: try XCTUnwrap(unpackZIP(try XCTUnwrap(editedParts["ppt/embeddings/Microsoft_Excel_Worksheet1.xlsx"]))["xl/worksheets/sheet1.xml"]),
            as: UTF8.self
        )
        XCTAssertTrue(editedSheet1.contains("<v>260.5</v>"))
    }

    // MARK: - Automated Quality Inspector Self-Repair Test

    func testQualityInspectorRepairsOverflowOverlapBlankSlidesAndMismatchedChartSeries() throws {
        let malformed = WuMindPPTDeck(
            title: "这是一份非常非常非常非常非常非常非常长而且明显会溢出的超长演示文稿主标题用于测试自动压缩防溢出",
            subtitle: "测试副标题",
            theme: .midnightTech,
            slides: [
                .init(id: 1, title: "封面", layout: .cover, bullets: ["副说明"]),
                .init(id: 2, title: "", layout: .bullets, bullets: []), // completely blank slide!
                .init(
                    id: 3,
                    title: "碰撞与溢出测试页",
                    layout: .chart,
                    bullets: ["1", "2", "3", "4", "5", "6", "7"], // exceeds max bullets!
                    table: .init(headers: ["A", "B"], rows: [["1"]]), // collides with chart + mismatched col count!
                    chart: .init(
                        kind: .pie,
                        title: "占比",
                        categories: ["甲", "乙", "丙"],
                        series: [
                            .init(name: "S1", values: [50, 30]), // missing 3rd value!
                            .init(name: "S2", values: [10, 20, 30]) // pie only allows 1 series!
                        ]
                    )
                ),
                .init(id: 4, title: "总结", layout: .summary, bullets: ["收尾要点"])
            ]
        )

        let repaired = WuMindPPTEngine.inspectAndRepair(malformed, expectedSlideCount: nil, hasSourceMaterials: true, webSearchUsed: false)
        let report = try XCTUnwrap(repaired.qualityReport)

        XCTAssertEqual(repaired.slides.count, 3, "空白页必须自动剔除")
        XCTAssertGreaterThan(report.blankSlidesFixedCount, 0)
        XCTAssertGreaterThan(report.overflowFixedCount, 0)
        XCTAssertGreaterThan(report.overlapFixedCount, 0)
        XCTAssertGreaterThan(report.dataConsistencyFixedCount, 0)

        let chartSlide = repaired.slides[1]
        XCTAssertNil(chartSlide.table, "同页表格与图表冲突必须保留主视觉元素避免遮挡")
        XCTAssertEqual(chartSlide.chart?.series.count, 1, "饼图只保留单序列")
        XCTAssertEqual(chartSlide.chart?.series.first?.values.count, 3, "序列长度必须对齐类目数")
        XCTAssertLessThanOrEqual(chartSlide.bullets.count, 4)

        // Export pie chart `.pptx` and verify strict XML validity
        let pptx = try WuMindPPTXExporter.make(deck: repaired)
        let parts = try assertValidOpenXMLPPTX(pptx, expectedSlides: 3, expectedCharts: 1)
        let pieXML = String(decoding: try XCTUnwrap(parts["ppt/charts/chart1.xml"]), as: UTF8.self)
        XCTAssertTrue(pieXML.contains("<c:pieChart>"))
        XCTAssertFalse(pieXML.contains("<c:catAx>"), "ECMA-376 规定饼图不得包含 catAx/valAx")
    }

    // MARK: - Strict OpenXML Package Integrity Validator

    @discardableResult
    private func assertValidOpenXMLPPTX(
        _ data: Data,
        expectedSlides: Int,
        expectedCharts: Int
    ) throws -> [String: Data] {
        let parts = unpackZIP(data)
        XCTAssertFalse(parts.isEmpty, "PPTX ZIP 解包为空")

        let required = [
            "[Content_Types].xml", "_rels/.rels", "docProps/core.xml", "docProps/app.xml",
            "ppt/presentation.xml", "ppt/_rels/presentation.xml.rels",
            "ppt/presProps.xml", "ppt/viewProps.xml", "ppt/tableStyles.xml",
            "ppt/theme/theme1.xml", "ppt/slideMasters/slideMaster1.xml",
            "ppt/slideMasters/_rels/slideMaster1.xml.rels",
            "ppt/slideLayouts/slideLayout1.xml", "ppt/slideLayouts/_rels/slideLayout1.xml.rels",
            "ppt/notesMasters/notesMaster1.xml", "ppt/notesMasters/_rels/notesMaster1.xml.rels"
        ]
        for req in required {
            XCTAssertNotNil(parts[req], "缺少必需 OpenXML 部件：\(req)")
        }

        // 1. Every XML & .rels part must strictly parse cleanly
        for (path, bytes) in parts where path.hasSuffix(".xml") || path.hasSuffix(".rels") {
            XCTAssertTrue(XMLParser(data: bytes).parse(), "XML 语法非法：\(path)")
        }

        // 2. Verify exact slide & notesSlide & chart counts
        for i in 1...expectedSlides {
            XCTAssertNotNil(parts["ppt/slides/slide\(i).xml"], "缺少 slide\(i).xml")
            XCTAssertNotNil(parts["ppt/slides/_rels/slide\(i).xml.rels"], "缺少 slide\(i).xml.rels")
            XCTAssertNotNil(parts["ppt/notesSlides/notesSlide\(i).xml"], "缺少 notesSlide\(i).xml")
            XCTAssertNotNil(parts["ppt/notesSlides/_rels/notesSlide\(i).xml.rels"], "缺少 notesSlide\(i).xml.rels")
        }
        if expectedCharts > 0 {
            for c in 1...expectedCharts {
                XCTAssertNotNil(parts["ppt/charts/chart\(c).xml"], "缺少 chart\(c).xml")
                XCTAssertNotNil(parts["ppt/charts/_rels/chart\(c).xml.rels"], "缺少 chart\(c).xml.rels")
                XCTAssertNotNil(parts["ppt/embeddings/Microsoft_Excel_Worksheet\(c).xlsx"], "缺少内嵌 Excel 工作簿 \(c)")
            }
        }

        // 3. Verify EVERY Relationship Target in EVERY .rels file resolves to an existing ZIP entry!
        let targetRegex = try NSRegularExpression(pattern: #"Target="([^"]+)""#)
        for (relsPath, bytes) in parts where relsPath.hasSuffix(".rels") {
            let xml = String(decoding: bytes, as: UTF8.self)
            let baseDir: String
            if relsPath == "_rels/.rels" {
                baseDir = ""
            } else {
                // e.g. "ppt/slides/_rels/slide1.xml.rels" -> "ppt/slides"
                baseDir = ((relsPath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
            }
            let ns = xml as NSString
            for match in targetRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
                let target = ns.substring(with: match.range(at: 1))
                let resolved = resolveRelativeOPCPath(baseDir: baseDir, target: target)
                XCTAssertNotNil(parts[resolved], "断链关系：\(relsPath) -> \(target)（解析为 \(resolved)）")
            }
        }

        // 4. Verify EVERY Override PartName in [Content_Types].xml exists in the ZIP!
        let ctXML = String(decoding: try XCTUnwrap(parts["[Content_Types].xml"]), as: UTF8.self)
        let partRegex = try NSRegularExpression(pattern: #"PartName="/([^"]+)""#)
        let ctNS = ctXML as NSString
        for match in partRegex.matches(in: ctXML, range: NSRange(location: 0, length: ctNS.length)) {
            let partPath = ctNS.substring(with: match.range(at: 1))
            XCTAssertNotNil(parts[partPath], "[Content_Types].xml 声明了不存在的部件：\(partPath)")
        }

        // 5. Verify unique cNvPr id per slide (duplicate shape IDs trigger PowerPoint Repair!)
        let idRegex = try NSRegularExpression(pattern: #"<p:cNvPr id="(\d+)""#)
        for i in 1...expectedSlides {
            let sXML = String(decoding: try XCTUnwrap(parts["ppt/slides/slide\(i).xml"]), as: UTF8.self)
            let ns = sXML as NSString
            let ids = idRegex.matches(in: sXML, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
            XCTAssertEqual(ids.count, Set(ids).count, "slide\(i).xml 存在重复的 cNvPr id，会触发 PowerPoint 修复弹窗")
        }

        return parts
    }

    private func resolveRelativeOPCPath(baseDir: String, target: String) -> String {
        var components = baseDir.isEmpty ? [] : baseDir.split(separator: "/").map(String.init)
        for seg in target.split(separator: "/").map(String.init) {
            if seg == ".." {
                if !components.isEmpty { components.removeLast() }
            } else if seg != "." && !seg.isEmpty {
                components.append(seg)
            }
        }
        return components.joined(separator: "/")
    }

    private func unpackZIP(_ data: Data) -> [String: Data] {
        let bytes = Array(data)
        func le(_ start: Int, _ count: Int) -> Int {
            (0..<count).reduce(0) { $0 | (Int(bytes[start + $1]) << (8 * $1)) }
        }
        var index = 0
        var out: [String: Data] = [:]
        while index + 30 <= bytes.count, le(index, 4) == 0x0403_4B50 {
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
