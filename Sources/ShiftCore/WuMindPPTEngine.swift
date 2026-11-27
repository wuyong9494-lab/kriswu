import Foundation

/// Visual presentation themes for WUMIND PPT Studio, native `.pptx` export, and 16:9 PDF rendering.
public enum WuMindPPTTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case midnightTech
    case executiveBlue
    case minimalIvory
    case easternInk

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .midnightTech: return "午夜科技"
        case .executiveBlue: return "商务深蓝"
        case .minimalIvory: return "极简雅白"
        case .easternInk: return "东方墨韵"
        }
    }
}

/// Target audience presets guiding depth, tone, and executive framing.
public enum WuMindPPTAudience: String, CaseIterable, Identifiable, Codable, Sendable {
    case executive
    case client
    case technical
    case general

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .executive: return "管理层"
        case .client: return "客户汇报"
        case .technical: return "技术团队"
        case .general: return "通用受众"
        }
    }

    public var guidance: String {
        switch self {
        case .executive: return "结论先行，突出经营指标、风险决策与资源诉求"
        case .client: return "突出客户价值、交付保障、差异化优势与实施路径"
        case .technical: return "突出架构逻辑、关键指标、瓶颈拆解与演进方案"
        case .general: return "结构清晰、语言精炼、重点突出、易于现场演示"
        }
    }
}

/// Automated post-generation quality & layout inspection report.
public struct WuMindPPTQualityReport: Codable, Equatable, Sendable {
    public var checkedAt: Date
    public var slideCount: Int
    public var overflowFixedCount: Int
    public var overlapFixedCount: Int
    public var blankSlidesFixedCount: Int
    public var dataConsistencyFixedCount: Int
    public var pendingPlaceholderCount: Int
    public var editableTablesCount: Int
    public var editableChartsCount: Int
    public var citationsCount: Int
    public var fixesApplied: [String]

    public init(
        checkedAt: Date = Date(),
        slideCount: Int,
        overflowFixedCount: Int = 0,
        overlapFixedCount: Int = 0,
        blankSlidesFixedCount: Int = 0,
        dataConsistencyFixedCount: Int = 0,
        pendingPlaceholderCount: Int = 0,
        editableTablesCount: Int = 0,
        editableChartsCount: Int = 0,
        citationsCount: Int = 0,
        fixesApplied: [String] = []
    ) {
        self.checkedAt = checkedAt
        self.slideCount = slideCount
        self.overflowFixedCount = overflowFixedCount
        self.overlapFixedCount = overlapFixedCount
        self.blankSlidesFixedCount = blankSlidesFixedCount
        self.dataConsistencyFixedCount = dataConsistencyFixedCount
        self.pendingPlaceholderCount = pendingPlaceholderCount
        self.editableTablesCount = editableTablesCount
        self.editableChartsCount = editableChartsCount
        self.citationsCount = citationsCount
        self.fixesApplied = fixesApplied
    }

    public var summaryBadge: String {
        var parts: [String] = ["\(slideCount) 页已自检"]
        if editableChartsCount > 0 { parts.append("\(editableChartsCount) 个可编辑图表") }
        if editableTablesCount > 0 { parts.append("\(editableTablesCount) 个可编辑表格") }
        if citationsCount > 0 { parts.append("\(citationsCount) 处来源引用") }
        if pendingPlaceholderCount > 0 { parts.append("\(pendingPlaceholderCount) 项待补") }
        if !fixesApplied.isEmpty { parts.append("自动修复 \(fixesApplied.count) 处") }
        return parts.joined(separator: " · ")
    }
}

/// Structured executive presentation deck produced by any WUMIND LLM and exported into
/// native editable `.pptx` (with real OpenXML tables, charts + embedded Excel data, and notes) & 16:9 PDF.
public struct WuMindPPTDeck: Codable, Equatable, Identifiable, Sendable {
    public enum SlideLayout: String, Codable, Equatable, Sendable, CaseIterable {
        case cover
        case agenda
        case bullets
        case metrics
        case twoColumn
        case table
        case chart
        case summary

        public var title: String {
            switch self {
            case .cover: return "封面"
            case .agenda: return "目录"
            case .bullets: return "核心要点"
            case .metrics: return "指标亮点"
            case .twoColumn: return "双栏对比"
            case .table: return "数据表格"
            case .chart: return "数据图表"
            case .summary: return "总结行动"
            }
        }
    }

    public struct TableData: Codable, Equatable, Sendable {
        public var headers: [String]
        public var rows: [[String]]
        public var caption: String?

        public init(headers: [String], rows: [[String]], caption: String? = nil) {
            self.headers = headers
            self.rows = rows
            self.caption = caption
        }
    }

    public enum ChartKind: String, Codable, Equatable, Sendable, CaseIterable {
        case bar
        case line
        case pie

        public var title: String {
            switch self {
            case .bar: return "柱状图"
            case .line: return "折线图"
            case .pie: return "饼图"
            }
        }
    }

    public struct ChartSeries: Codable, Equatable, Sendable {
        public var name: String
        public var values: [Double?]
        public var isPercentage: Bool?

        public init(name: String, values: [Double?], isPercentage: Bool? = nil) {
            self.name = name
            self.values = values
            self.isPercentage = isPercentage
        }
    }

    public struct ChartData: Codable, Equatable, Sendable {
        public var kind: ChartKind
        public var title: String
        public var unit: String?
        public var categories: [String]
        public var series: [ChartSeries]
        public var sourceRange: String?

        public init(
            kind: ChartKind = .bar,
            title: String,
            unit: String? = nil,
            categories: [String],
            series: [ChartSeries],
            sourceRange: String? = nil
        ) {
            self.kind = kind
            self.title = title
            self.unit = unit
            self.categories = categories
            self.series = series
            self.sourceRange = sourceRange
        }
    }

    public struct Slide: Codable, Equatable, Identifiable, Sendable {
        public var id: Int
        public var title: String
        public var layout: SlideLayout
        public var bullets: [String]
        public var highlightMetric: String?
        public var highlightLabel: String?
        public var speakerNotes: String
        public var visualHint: String
        public var table: TableData?
        public var chart: ChartData?
        public var citations: [String]?
        public var pendingItems: [String]?
        public var imageDataBase64: String?

        public init(
            id: Int,
            title: String,
            layout: SlideLayout = .bullets,
            bullets: [String],
            highlightMetric: String? = nil,
            highlightLabel: String? = nil,
            speakerNotes: String = "",
            visualHint: String = "",
            table: TableData? = nil,
            chart: ChartData? = nil,
            citations: [String]? = nil,
            pendingItems: [String]? = nil,
            imageDataBase64: String? = nil
        ) {
            self.id = id
            self.title = title
            self.layout = layout
            self.bullets = bullets
            self.highlightMetric = highlightMetric
            self.highlightLabel = highlightLabel
            self.speakerNotes = speakerNotes
            self.visualHint = visualHint
            self.table = table
            self.chart = chart
            self.citations = citations
            self.pendingItems = pendingItems
            self.imageDataBase64 = imageDataBase64
        }
    }

    public let id: UUID
    public var title: String
    public var subtitle: String
    public var theme: WuMindPPTTheme
    public var slides: [Slide]
    public var createdAt: Date
    public var audience: WuMindPPTAudience?
    public var qualityReport: WuMindPPTQualityReport?
    public var sourceFiles: [String]?
    public var webSearchUsed: Bool?
    public var logoDataBase64: String?
    public var targetDurationMinutes: Int?

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        theme: WuMindPPTTheme = .midnightTech,
        slides: [Slide],
        createdAt: Date = Date(),
        audience: WuMindPPTAudience? = nil,
        qualityReport: WuMindPPTQualityReport? = nil,
        sourceFiles: [String]? = nil,
        webSearchUsed: Bool? = nil,
        logoDataBase64: String? = nil,
        targetDurationMinutes: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.slides = slides
        self.createdAt = createdAt
        self.audience = audience
        self.qualityReport = qualityReport
        self.sourceFiles = sourceFiles
        self.webSearchUsed = webSearchUsed
        self.logoDataBase64 = logoDataBase64
        self.targetDurationMinutes = targetDurationMinutes
    }
}

/// Pure-Swift autonomous PPT planner prompt builder, resilient JSON/Markdown parser,
/// automated quality & layout self-repair inspector, and outline exporter.
public enum WuMindPPTEngine {
    /// Automatically extracts an explicit page count from a single-sentence prompt (e.g. "做一份 8 页年终工作总结").
    public static func extractRequestedSlideCount(from prompt: String, fallback: Int) -> Int {
        let clampedFallback = max(4, min(20, fallback))
        let pattern = #"(\d{1,2})\s*(?:页|张|slides?|pages?)"#
        if let range = prompt.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            let match = String(prompt[range])
            let digits = match.filter(\.isNumber)
            if let num = Int(digits), (4...20).contains(num) {
                return num
            }
        }
        let cnMap: [(String, Int)] = [
            ("十五页", 15), ("十二页", 12), ("十页", 10),
            ("九页", 9), ("八页", 8), ("七页", 7), ("六页", 6), ("五页", 5)
        ]
        for (token, count) in cnMap where prompt.contains(token) {
            return count
        }
        return clampedFallback
    }

    public static func systemPrompt(slideCount: Int, theme: WuMindPPTTheme) -> String {
        systemPrompt(
            slideCount: slideCount,
            theme: theme,
            audience: .general,
            hasSourceMaterials: false,
            webSearchEnabled: false
        )
    }

    public static func systemPrompt(
        slideCount: Int,
        theme: WuMindPPTTheme,
        audience: WuMindPPTAudience,
        hasSourceMaterials: Bool,
        webSearchEnabled: Bool
    ) -> String {
        let clamped = max(4, min(20, slideCount))
        let groundingRule: String
        if hasSourceMaterials {
            groundingRule = """
            【事实追溯与反编造铁律（已提供原始资料）】
            1. 所有数字、指标、表格、图表和结论必须严格来源于用户上传的 PDF/Word/Excel/图片素材，并在该页 `citations` 数组中注明出处（例如 `"来源：Q4经营数据.xlsx · 收入表"` 或 `"来源：项目方案.pdf · 第3节"`）。
            2. 必须至少规划 1 页 `layout: "chart"`（真实提取素材中的数值生成可编辑图表，包含 `categories` 和 `series` 数值数组）和 1 页 `layout: "table"`（提取素材关键明细或对比表）。
            3. 资料里缺失但汇报必需的信息，明确写 `"【待补】..."` 并记录在 `pendingItems`，严禁凭空编造数字。
            """
        } else {
            groundingRule = """
            【反编造铁律（用户仅提供一句话主题，未上传原始数据文件）】
            1. 严禁虚构任何具体业绩数字、营收金额、增长百分比、用户数或项目指标！
            2. 凡涉及需要真实数据的指标卡片、表格单元格或对比项，必须填写 `"【待补】"`（如 `"【待补】年度营收/核心 KPI"`），并在 `pendingItems` 列出待补清单，方便用户在 PowerPoint / WPS 打开后直接替换。
            3. 未上传数据时，请使用 `table` 呈现清晰的结构化复盘/计划填报表（含 `"【待补】"` 栏位），不要为 chart 编造虚假统计数字。
            """
        }

        let webRule = webSearchEnabled
            ? "【已开启联网补资料】若上方提供了联网检索摘要，可引用其中的公开事实，并在对应页的 `citations` 中附带来源标题或 URL。"
            : "【未开启联网补资料】不要假装联网检索，也不要编造外部 URL。"

        return """
        你是顶级麦肯锡/苹果发布会级别的自主 PPT 架构与交付专家。
        不要只输出大纲或向用户反问确认——请一次性直接完成整套共 \(clamped) 页、可直接导出为 PowerPoint/WPS 可编辑 `.pptx` 的完整演示文稿 JSON。
        视觉风格：\(theme.title)；目标受众：\(audience.title)（\(audience.guidance)）。

        \(groundingRule)
        \(webRule)

        【版面与字数控制（严防文字溢出与遮挡）】
        - 每页标题 <= 24 字；正文要点每页 3~5 条，每条 <= 34 字，精炼有力。
        - 第 1 页必须为 `cover`，最后 1 页必须为 `summary`，中间合理组合 `agenda` / `bullets` / `metrics` / `twoColumn` / `table` / `chart`。
        - 每页必须包含自然流畅的 `speakerNotes`（2~3 句演讲口播稿）。

        必须且仅返回如下 JSON 结构（可用 ```json 包裹）：
        {
          "title": "主标题（简短有力）",
          "subtitle": "副标题或汇报场景说明",
          "slides": [
            {
              "title": "本页标题",
              "layout": "cover | agenda | bullets | metrics | twoColumn | table | chart | summary",
              "bullets": ["核心要点 1", "核心要点 2", "核心要点 3"],
              "highlightMetric": "可选大数字亮点（无数据时填 【待补】 或省略）",
              "highlightLabel": "可选大数字说明",
              "table": {
                "caption": "可选表格说明",
                "headers": ["列1", "列2", "列3"],
                "rows": [["内容A", "内容B", "内容C"]]
              },
              "chart": {
                "kind": "bar | line | pie",
                "title": "图表标题（仅当有真实可追溯数值时填写）",
                "unit": "万元 / % / 次",
                "categories": ["Q1", "Q2", "Q3", "Q4"],
                "series": [
                  { "name": "指标名称", "values": [120, 145, 168, 210] }
                ]
              },
              "citations": ["来源：文件名或章节（如有）"],
              "pendingItems": ["待补：具体缺失数据项（如有）"],
              "speakerNotes": "口播演讲备注（2~3 句自然衔接的话）",
              "visualHint": "建议配图或视觉重点"
            }
          ]
        }
        注意：不要在同一页同时填写 `table` 和 `chart`；每页只聚焦一种核心版式。
        """
    }

    /// Prompt for regenerating ONE specific slide while keeping overall deck narrative & grounding consistent.
    public static func singleSlideRegeneratePrompt(
        deck: WuMindPPTDeck,
        slideIndex: Int,
        instruction: String,
        hasSourceMaterials: Bool
    ) -> String {
        let safeIdx = max(0, min(deck.slides.count - 1, slideIndex))
        let target = deck.slides[safeIdx]
        let outline = deck.slides.map { "第 \($0.id) 页（\($0.layout.title)）：\($0.title)" }.joined(separator: "\n")
        let noFake = hasSourceMaterials
            ? "所有数字必须追溯到提供的资料并在 citations 标注来源，缺失项标「待补」。"
            : "未上传原始数据时绝不编造业绩数字，缺口处明确标「【待补】」。"
        return """
        你是 WUMIND PPT 单页精修专家。请仅重做第 \(target.id) 页，保持与整套演示文稿一致的叙事连贯性。
        整套标题：\(deck.title)（\(deck.subtitle)）
        当前完整页序：
        \(outline)

        当前第 \(target.id) 页原标题：\(target.title)（版式：\(target.layout.rawValue)）
        用户重做指令：\(instruction.isEmpty ? "全面优化本页逻辑、表达精炼度、演讲备注与可视化版式" : instruction)
        约束：\(noFake)

        必须且仅返回单个 Slide JSON 对象（可用 ```json 包裹）：
        {
          "title": "新版页标题",
          "layout": "cover | agenda | bullets | metrics | twoColumn | table | chart | summary",
          "bullets": ["要点1", "要点2", "要点3"],
          "highlightMetric": null,
          "highlightLabel": null,
          "table": null,
          "chart": null,
          "citations": [],
          "pendingItems": [],
          "speakerNotes": "2~3 句自然演讲备注",
          "visualHint": "视觉说明"
        }
        """
    }

    /// Infer a useful starting point from the brief without relying on an extra paid model request.
    public static func chatDesignProfile(for brief: String) -> (theme: WuMindPPTTheme, audience: WuMindPPTAudience) {
        let text = brief.lowercased()
        func matches(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        let audience: WuMindPPTAudience
        if matches(["年终", "复盘", "管理层", "董事会", "经营", "季度汇报"]) { audience = .executive }
        else if matches(["客户", "招商", "产品发布", "路演", "提案"]) { audience = .client }
        else if matches(["架构", "技术团队", "研发", "工程师"]) { audience = .technical }
        else { audience = .general }
        let theme: WuMindPPTTheme
        if matches(["国风", "水墨", "东方墨韵"]) { theme = .easternInk }
        else if matches(["极简", "雅白", "白底", "浅色"]) { theme = .minimalIvory }
        else if matches(["深色", "科技感", "午夜科技"]) { theme = .midnightTech }
        else if matches(["商务", "深蓝"]) || audience == .executive || audience == .client { theme = .executiveBlue }
        else { theme = audience == .technical ? .midnightTech : .minimalIvory }
        return (theme, audience)
    }

    /// Chat shouldn't report success by converting a partial answer into generic filler slides.
    /// Keep meaningful partial drafts and let the caller label missing pages explicitly.
    public static func validatedChatDeck(
        from rawText: String, fallbackTopic: String, theme: WuMindPPTTheme,
        expectedSlideCount: Int, audience: WuMindPPTAudience, sourceFiles: [String]
    ) -> WuMindPPTDeck? {
        guard let json = extractJSONObject(from: rawText),
              let decoded = try? JSONDecoder().decode(WireDeck.self, from: Data(json.utf8)) else { return nil }
        var deck = parseDeck(from: json, fallbackTopic: fallbackTopic, theme: theme)
        let incoming = deck.slides
        guard !decoded.slides.isEmpty else { return nil }
        var seen = Set<String>()
        deck.slides = Array(incoming.filter { slide in
            let title = slide.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = title.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
            let meaningfulPoints = slide.bullets.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.hasPrefix("【待补】")
            }
            let hasStructuredBody = (slide.table?.rows.isEmpty == false) || (slide.chart?.series.isEmpty == false)
            guard !key.isEmpty, !key.hasPrefix("补充专题与待补事项"),
                  (slide.layout == .cover || meaningfulPoints || hasStructuredBody),
                  seen.insert(key).inserted else { return false }
            return true
        }.prefix(max(4, min(20, expectedSlideCount))))
        guard deck.slides.count >= 2 else { return nil }
        deck.audience = audience
        deck.sourceFiles = sourceFiles
        deck.webSearchUsed = false
        return inspectAndRepair(deck, hasSourceMaterials: !sourceFiles.isEmpty, webSearchUsed: false)
    }

    /// Parses structured JSON (even wrapped in markdown fences or prose) with graceful Markdown-heading fallback.
    public static func parseDeck(from rawText: String, fallbackTopic: String, theme: WuMindPPTTheme) -> WuMindPPTDeck {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let jsonCandidate = extractJSONObject(from: trimmed),
           let data = jsonCandidate.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(WireDeck.self, from: data),
           !decoded.slides.isEmpty {
            let slides = decoded.slides.enumerated().map { idx, item in
                convertWireSlide(item, id: idx + 1, defaultLayout: idx == 0 ? .cover : .bullets)
            }
            return WuMindPPTDeck(
                title: decoded.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTopic : decoded.title.trimmingCharacters(in: .whitespacesAndNewlines),
                subtitle: (decoded.subtitle ?? "WUMIND 智能演示文稿").trimmingCharacters(in: .whitespacesAndNewlines),
                theme: theme,
                slides: slides
            )
        }

        // Resilient fallback: split Markdown headings (`#` / `##`) into slides so valid output is ALWAYS produced.
        var slides: [WuMindPPTDeck.Slide] = []
        var currentTitle: String? = nil
        var currentBullets: [String] = []

        func flushSlide() {
            guard let t = currentTitle, !t.isEmpty else { return }
            let idx = slides.count + 1
            slides.append(WuMindPPTDeck.Slide(
                id: idx,
                title: t,
                layout: idx == 1 ? .cover : .bullets,
                bullets: currentBullets.isEmpty ? ["聚焦核心目标与关键路径"] : currentBullets,
                speakerNotes: "",
                visualHint: ""
            ))
            currentTitle = nil
            currentBullets = []
        }

        for rawLine in trimmed.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                flushSlide()
                currentTitle = line.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
            } else {
                let bullet = line.replacingOccurrences(of: #"^[-*•\d.]+\s*"#, with: "", options: .regularExpression)
                if currentTitle == nil {
                    currentTitle = fallbackTopic.isEmpty ? "演示概览" : fallbackTopic
                }
                if !bullet.isEmpty {
                    currentBullets.append(bullet)
                }
            }
        }
        flushSlide()

        if slides.isEmpty {
            slides = [
                WuMindPPTDeck.Slide(
                    id: 1,
                    title: fallbackTopic.isEmpty ? "WUMIND 演示文稿" : fallbackTopic,
                    layout: .cover,
                    bullets: [String(trimmed.prefix(120))],
                    speakerNotes: ""
                )
            ]
        }

        return WuMindPPTDeck(
            title: slides[0].title,
            subtitle: "WUMIND PPT 工坊自动生成",
            theme: theme,
            slides: slides
        )
    }

    /// Parses a single regenerated slide JSON safely.
    public static func parseSingleSlide(from rawText: String, fallback: WuMindPPTDeck.Slide) -> WuMindPPTDeck.Slide {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let jsonCandidate = extractJSONObject(from: trimmed),
           let data = jsonCandidate.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(WireDeck.WireSlide.self, from: data) {
            var rebuilt = convertWireSlide(decoded, id: fallback.id, defaultLayout: fallback.layout)
            if rebuilt.imageDataBase64 == nil {
                rebuilt.imageDataBase64 = fallback.imageDataBase64
            }
            return rebuilt
        }
        return fallback
    }

    /// Automatic post-generation quality & layout inspection + self-repair engine:
    /// fixes text overflow, layout element overlap, blank slides, data/chart inconsistency,
    /// and ungrounded metric fabrication when no source data was provided.
    public static func inspectAndRepair(
        _ input: WuMindPPTDeck,
        expectedSlideCount: Int? = nil,
        hasSourceMaterials: Bool = false,
        webSearchUsed: Bool = false
    ) -> WuMindPPTDeck {
        var deck = input
        var fixes: [String] = []
        var overflowFixed = 0
        var overlapFixed = 0
        var blankFixed = 0
        var dataFixed = 0

        if deck.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deck.title = "WUMIND 演示文稿"
            blankFixed += 1
            fixes.append("补齐缺失的演示主标题")
        }
        if deck.title.count > 36 {
            deck.title = String(deck.title.prefix(34)) + "…"
            overflowFixed += 1
            fixes.append("主标题超长已精简防溢出")
        }
        if deck.subtitle.count > 68 {
            deck.subtitle = String(deck.subtitle.prefix(66)) + "…"
            overflowFixed += 1
        }

        // 1. Remove completely empty slides & ensure minimum cover + summary structure
        var slides = deck.slides.filter { s in
            let hasTitle = !s.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasBody = !s.bullets.isEmpty || s.table != nil || s.chart != nil || s.highlightMetric != nil
            return hasTitle || hasBody
        }
        if slides.count < deck.slides.count {
            let removed = deck.slides.count - slides.count
            blankFixed += removed
            fixes.append("清理 \(removed) 页空白页")
        }
        if slides.isEmpty {
            slides = [
                WuMindPPTDeck.Slide(id: 1, title: deck.title, layout: .cover, bullets: [deck.subtitle]),
                WuMindPPTDeck.Slide(id: 2, title: "总结与后续行动", layout: .summary, bullets: ["【待补】明确后续负责人与里程碑节点"])
            ]
            blankFixed += 2
            fixes.append("检测到空文稿，已自动补齐封面与总结页")
        }

        // Respect requested slide count if model under-generated a few pages
        if let expected = expectedSlideCount, (4...20).contains(expected), slides.count < expected {
            let missing = expected - slides.count
            for offset in 0..<missing {
                let insertPos = max(1, slides.count - 1)
                let filler = WuMindPPTDeck.Slide(
                    id: insertPos + 1,
                    title: "补充专题与待补事项（\(offset + 1)）",
                    layout: .bullets,
                    bullets: [
                        "【待补】补充该模块的关键事实、案例或业务结论",
                        "【待补】明确本阶段核心风险与对应责任人",
                        "【待补】对齐下一步交付节奏与验收口径"
                    ],
                    speakerNotes: "本页用于补充核心专题细节，建议在 PowerPoint 或 WPS 中替换待补数据。",
                    pendingItems: ["待补：补充专题 \(offset + 1) 真实业务数据"]
                )
                slides.insert(filler, at: insertPos)
            }
            blankFixed += missing
            fixes.append("模型输出页数不足 \(expected) 页，已自动补齐 \(missing) 页结构化待补页")
        }

        let groundedMode = hasSourceMaterials || webSearchUsed
        var editableTables = 0
        var editableCharts = 0
        var totalCitations = 0
        var totalPending = 0

        for idx in slides.indices {
            var s = slides[idx]
            s.id = idx + 1

            // Enforce first = cover, last = summary when multi-slide
            if idx == 0 && s.layout != .cover {
                s.layout = .cover
            } else if idx == slides.count - 1 && slides.count >= 2 && s.layout != .summary && s.layout != .table && s.layout != .chart {
                s.layout = .summary
            }

            // Title overflow clamp
            s.title = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.title.isEmpty {
                s.title = idx == 0 ? deck.title : "第 \(s.id) 页核心内容"
                blankFixed += 1
            }
            if s.title.count > 34 {
                s.title = String(s.title.prefix(32)) + "…"
                overflowFixed += 1
                fixes.append("第 \(s.id) 页标题过长已自动压缩防溢出")
            }

            // Overlap guard: never render BOTH a full table AND a chart simultaneously on one slide
            if s.table != nil && s.chart != nil {
                if s.layout == .table {
                    s.chart = nil
                } else {
                    s.table = nil
                    s.layout = .chart
                }
                overlapFixed += 1
                fixes.append("第 \(s.id) 页同时含表格与图表，已保留主视觉元素避免遮挡")
            }

            // Sanitize & validate ChartData
            if var chart = s.chart {
                if !groundedMode {
                    // Strict anti-hallucination: never keep fabricated numeric charts when user supplied zero data!
                    let headers = ["维度 / 项目", chart.series.first?.name ?? "核心指标", "数据状态"]
                    let rows = chart.categories.prefix(5).map { cat in
                        [cat, "【待补】", "请填入真实数据"]
                    }
                    s.chart = nil
                    if !rows.isEmpty {
                        s.table = WuMindPPTDeck.TableData(
                            headers: headers,
                            rows: rows,
                            caption: "\(chart.title)（未上传数据，待补真实值）"
                        )
                        s.layout = .table
                    } else {
                        s.layout = .bullets
                    }
                    var p = s.pendingItems ?? []
                    p.append("待补：\(chart.title) 真实统计数据")
                    s.pendingItems = Array(Set(p)).sorted()
                    dataFixed += 1
                    fixes.append("第 \(s.id) 页无原始数据支撑，已将虚构图表转为可编辑待补表格")
                } else {
                    chart.categories = Array(chart.categories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(8))
                    let catCount = chart.categories.count
                    var cleanSeries: [WuMindPPTDeck.ChartSeries] = []
                    for ser in chart.series.prefix(4) {
                        var vals: [Double?] = ser.values.map { opt in
                            guard let v = opt, v.isFinite else { return nil }
                            return v
                        }
                        if vals.count != catCount {
                            dataFixed += 1
                            if vals.count > catCount {
                                vals = Array(vals.prefix(catCount))
                            } else if catCount > 0 {
                                vals.append(contentsOf: repeatElement(nil, count: catCount - vals.count))
                            }
                            fixes.append("第 \(s.id) 页图表序列「\(ser.name)」长度已对齐类目数")
                        }
                        if vals.contains(where: { $0 != nil }) {
                            cleanSeries.append(.init(
                                name: ser.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "指标" : ser.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                values: vals,
                                isPercentage: ser.isPercentage
                            ))
                        }
                    }
                    if chart.kind == .pie, cleanSeries.count > 1 {
                        cleanSeries = [cleanSeries[0]]
                        dataFixed += 1
                    }
                    if catCount >= 2 && !cleanSeries.isEmpty {
                        chart.series = cleanSeries
                        if chart.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            chart.title = s.title
                        }
                        s.chart = chart
                        s.layout = .chart
                        editableCharts += 1
                    } else {
                        s.chart = nil
                        if s.layout == .chart { s.layout = .bullets }
                        dataFixed += 1
                        fixes.append("第 \(s.id) 页图表数据不足，已降级为清晰要点排版")
                    }
                }
            }

            // Sanitize & validate TableData
            if var tbl = s.table {
                tbl.headers = Array(tbl.headers.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(18)) }.filter { !$0.isEmpty }.prefix(5))
                let colCount = tbl.headers.count
                if colCount >= 2 {
                    var normalizedRows: [[String]] = []
                    for rawRow in tbl.rows.prefix(7) {
                        var row = rawRow.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(34)) }
                        if row.count != colCount {
                            dataFixed += 1
                            if row.count > colCount {
                                row = Array(row.prefix(colCount))
                            } else {
                                row.append(contentsOf: repeatElement("【待补】", count: colCount - row.count))
                            }
                        }
                        normalizedRows.append(row)
                    }
                    if normalizedRows.isEmpty {
                        normalizedRows = [Array(repeating: "【待补】", count: colCount)]
                        blankFixed += 1
                    }
                    tbl.rows = normalizedRows
                    s.table = tbl
                    if s.layout != .table { s.layout = .table }
                    editableTables += 1
                } else {
                    s.table = nil
                    if s.layout == .table { s.layout = .bullets }
                    dataFixed += 1
                }
            }

            // Anti-fabrication guard on highlightMetric when no source files / web search provided
            if !groundedMode, let metric = s.highlightMetric, !metric.isEmpty {
                let looksNumeric = metric.range(of: #"\d"#, options: .regularExpression) != nil
                let isStructural = metric.contains("待补") || metric.contains("阶段") || metric.contains("Q1")
                    || metric.contains("Q2") || metric.contains("Q3") || metric.contains("Q4")
                    || metric.contains("页") || metric.contains("大") || metric.contains("项")
                    || metric.range(of: #"^20\d{2}年?$"#, options: .regularExpression) != nil
                if looksNumeric && !isStructural {
                    s.highlightMetric = "【待补】"
                    var p = s.pendingItems ?? []
                    let lbl = s.highlightLabel ?? s.title
                    p.append("待补：\(lbl) 真实数值")
                    s.pendingItems = Array(Set(p)).sorted()
                    dataFixed += 1
                    fixes.append("第 \(s.id) 页未提供原始业绩数据时出现具体数字「\(metric)」，已替换为「【待补】」")
                }
            }

            // Bullet overflow clamp based on layout safe bounding box
            let maxBullets: Int
            let maxCharsPerBullet: Int
            switch s.layout {
            case .cover: maxBullets = 2; maxCharsPerBullet = 44
            case .table: maxBullets = 2; maxCharsPerBullet = 46
            case .chart: maxBullets = 4; maxCharsPerBullet = 32
            case .metrics: maxBullets = 4; maxCharsPerBullet = 38
            case .twoColumn: maxBullets = 6; maxCharsPerBullet = 34
            case .bullets, .agenda, .summary: maxBullets = 5; maxCharsPerBullet = 46
            }

            var cleanedBullets = s.bullets
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if cleanedBullets.count > maxBullets {
                cleanedBullets = Array(cleanedBullets.prefix(maxBullets))
                overflowFixed += 1
                fixes.append("第 \(s.id) 页要点超过版式容量，已裁剪至 \(maxBullets) 条防溢出")
            }
            for bIdx in cleanedBullets.indices {
                if cleanedBullets[bIdx].count > maxCharsPerBullet {
                    cleanedBullets[bIdx] = String(cleanedBullets[bIdx].prefix(maxCharsPerBullet - 1)) + "…"
                    overflowFixed += 1
                }
            }
            if cleanedBullets.isEmpty && s.layout != .cover && s.table == nil && s.chart == nil {
                cleanedBullets = ["【待补】补充本页核心论据与执行要点"]
                blankFixed += 1
                fixes.append("第 \(s.id) 页正文为空，已补齐结构化要点")
            }
            s.bullets = cleanedBullets

            // Ensure non-empty speaker notes on every slide
            if s.speakerNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let firstPoint = s.bullets.first ?? s.title
                s.speakerNotes = "这一页聚焦「\(s.title)」，建议围绕「\(firstPoint)」向听众展开说明并结合实际案例补充。"
            }

            // Clean & count citations and pending placeholders
            let cleanCitations = (s.citations ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            s.citations = cleanCitations.isEmpty ? nil : Array(Set(cleanCitations)).sorted()
            totalCitations += s.citations?.count ?? 0

            let cleanPending = (s.pendingItems ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            s.pendingItems = cleanPending.isEmpty ? nil : Array(Set(cleanPending)).sorted()

            let slideTextBlob = ([s.title, s.highlightMetric ?? ""] + s.bullets + (s.table?.rows.flatMap { $0 } ?? []) + (s.pendingItems ?? [])).joined(separator: " ")
            if slideTextBlob.contains("待补") {
                totalPending += max(1, s.pendingItems?.count ?? 1)
            }

            slides[idx] = s
        }

        deck.slides = slides
        deck.webSearchUsed = webSearchUsed
        deck.qualityReport = WuMindPPTQualityReport(
            checkedAt: Date(),
            slideCount: slides.count,
            overflowFixedCount: overflowFixed,
            overlapFixedCount: overlapFixed,
            blankSlidesFixedCount: blankFixed,
            dataConsistencyFixedCount: dataFixed,
            pendingPlaceholderCount: totalPending,
            editableTablesCount: editableTables,
            editableChartsCount: editableCharts,
            citationsCount: totalCitations,
            fixesApplied: fixes
        )
        return deck
    }

    public static func exportMarkdownOutline(_ deck: WuMindPPTDeck) -> String {
        var lines: [String] = [
            "# \(deck.title)",
            "> \(deck.subtitle)",
            ""
        ]
        for slide in deck.slides {
            lines.append("---")
            lines.append("## \(slide.id). \(slide.title)（\(slide.layout.title)）")
            if let metric = slide.highlightMetric, !metric.isEmpty {
                let label = slide.highlightLabel.map { "（\($0)）" } ?? ""
                lines.append("**关键指标：\(metric)**\(label)")
            }
            for b in slide.bullets {
                lines.append("- \(b)")
            }
            if let tbl = slide.table, !tbl.headers.isEmpty {
                lines.append("")
                lines.append("| " + tbl.headers.joined(separator: " | ") + " |")
                lines.append("| " + tbl.headers.map { _ in "---" }.joined(separator: " | ") + " |")
                for r in tbl.rows {
                    lines.append("| " + r.joined(separator: " | ") + " |")
                }
            }
            if let chart = slide.chart {
                lines.append("")
                lines.append("**图表（\(chart.kind.title)）：\(chart.title)**")
                for ser in chart.series {
                    let isPct = ser.isPercentage == true
                    let pairs = zip(chart.categories, ser.values).map { cat, val in
                        "\(cat): \(val.map { formatChartValue($0, isPercentage: isPct) } ?? "—")"
                    }.joined(separator: " · ")
                    lines.append("- \(ser.name)：\(pairs)")
                }
            }
            if let cites = slide.citations, !cites.isEmpty {
                lines.append("\n来源：\(cites.joined(separator: "；"))")
            }
            if !slide.speakerNotes.isEmpty {
                lines.append("\n> 演讲备注：\(slide.speakerNotes)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public static func formatChartNumber(_ v: Double) -> String {
        if v.rounded() == v && abs(v) < 1_000_000_000 {
            return String(Int(v))
        }
        return String(format: "%.2f", v).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    public static func formatChartValue(_ v: Double, isPercentage: Bool) -> String {
        if isPercentage {
            return formatChartNumber(v * 100.0) + "%"
        }
        return formatChartNumber(v)
    }

    private static func convertWireSlide(
        _ item: WireDeck.WireSlide,
        id: Int,
        defaultLayout: WuMindPPTDeck.SlideLayout
    ) -> WuMindPPTDeck.Slide {
        let parsedLayout = WuMindPPTDeck.SlideLayout(rawValue: item.layout ?? "") ?? defaultLayout
        let cleanBullets = (item.bullets ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let table: WuMindPPTDeck.TableData? = item.table.flatMap { wt in
            let headers = (wt.headers ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let rows = (wt.rows ?? []).map { r in r.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            guard !headers.isEmpty else { return nil }
            return WuMindPPTDeck.TableData(headers: headers, rows: rows, caption: wt.caption?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
        }
        let chart: WuMindPPTDeck.ChartData? = item.chart.flatMap { wc in
            let cats = (wc.categories ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let series = (wc.series ?? []).compactMap { ws -> WuMindPPTDeck.ChartSeries? in
                let vals: [Double?] = (ws.values ?? []).map(\.doubleValue)
                guard vals.contains(where: { $0 != nil }) else { return nil }
                return WuMindPPTDeck.ChartSeries(name: ws.name ?? "指标", values: vals)
            }
            guard !cats.isEmpty, !series.isEmpty else { return nil }
            let kind = WuMindPPTDeck.ChartKind(rawValue: (wc.kind ?? "bar").lowercased()) ?? .bar
            return WuMindPPTDeck.ChartData(
                kind: kind,
                title: (wc.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                unit: wc.unit?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                categories: cats,
                series: series
            )
        }
        let citations = (item.citations ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let pending = (item.pendingItems ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return WuMindPPTDeck.Slide(
            id: id,
            title: item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "第 \(id) 页" : item.title.trimmingCharacters(in: .whitespacesAndNewlines),
            layout: parsedLayout,
            bullets: cleanBullets,
            highlightMetric: item.highlightMetric?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            highlightLabel: item.highlightLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            speakerNotes: (item.speakerNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            visualHint: (item.visualHint ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            table: table,
            chart: chart,
            citations: citations.isEmpty ? nil : citations,
            pendingItems: pending.isEmpty ? nil : pending
        )
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        return String(text[start...end])
    }

    private struct FlexibleNumber: Decodable {
        let doubleValue: Double?

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) {
                doubleValue = d
            } else if let i = try? c.decode(Int.self) {
                doubleValue = Double(i)
            } else if let s = try? c.decode(String.self) {
                let cleaned = s.replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: "%", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                doubleValue = Double(cleaned)
            } else {
                doubleValue = nil
            }
        }
    }

    private struct WireDeck: Decodable {
        struct WireTable: Decodable {
            let caption: String?
            let headers: [String]?
            let rows: [[String]]?
        }

        struct WireChartSeries: Decodable {
            let name: String?
            let values: [FlexibleNumber]?
        }

        struct WireChart: Decodable {
            let kind: String?
            let title: String?
            let unit: String?
            let categories: [String]?
            let series: [WireChartSeries]?
        }

        struct WireSlide: Decodable {
            let title: String
            let layout: String?
            let bullets: [String]?
            let highlightMetric: String?
            let highlightLabel: String?
            let speakerNotes: String?
            let visualHint: String?
            let table: WireTable?
            let chart: WireChart?
            let citations: [String]?
            let pendingItems: [String]?
        }
        let title: String
        let subtitle: String?
        let slides: [WireSlide]
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
