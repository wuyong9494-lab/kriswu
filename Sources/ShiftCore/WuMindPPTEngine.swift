import Foundation

/// Visual presentation themes for WUMIND PPT Studio & native 16:9 PDF deck rendering.
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

/// Structured executive presentation deck produced by any WUMIND LLM and rendered into 16:9 slides + PDF.
public struct WuMindPPTDeck: Codable, Equatable, Identifiable, Sendable {
    public enum SlideLayout: String, Codable, Equatable, Sendable {
        case cover
        case bullets
        case metrics
        case twoColumn
        case summary
    }

    public struct Slide: Codable, Equatable, Identifiable, Sendable {
        public let id: Int
        public var title: String
        public var layout: SlideLayout
        public var bullets: [String]
        public var highlightMetric: String?
        public var highlightLabel: String?
        public var speakerNotes: String
        public var visualHint: String

        public init(
            id: Int,
            title: String,
            layout: SlideLayout = .bullets,
            bullets: [String],
            highlightMetric: String? = nil,
            highlightLabel: String? = nil,
            speakerNotes: String = "",
            visualHint: String = ""
        ) {
            self.id = id
            self.title = title
            self.layout = layout
            self.bullets = bullets
            self.highlightMetric = highlightMetric
            self.highlightLabel = highlightLabel
            self.speakerNotes = speakerNotes
            self.visualHint = visualHint
        }
    }

    public let id: UUID
    public var title: String
    public var subtitle: String
    public var theme: WuMindPPTTheme
    public var slides: [Slide]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        theme: WuMindPPTTheme = .midnightTech,
        slides: [Slide],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.slides = slides
        self.createdAt = createdAt
    }
}

/// Pure-Swift prompt builder, resilient JSON/Markdown parser, and outline exporter for WUMIND PPT Studio.
public enum WuMindPPTEngine {
    public static func systemPrompt(slideCount: Int, theme: WuMindPPTTheme) -> String {
        let clamped = max(4, min(20, slideCount))
        return """
        你是顶级麦肯锡/苹果发布会级别的 PPT 演示架构师。
        请严格根据用户提供的主题与素材，输出一份共 \(clamped) 页、结构清晰、逻辑递进、可直接用于汇报的高管级幻灯片 JSON（不要编造素材未提及的虚假数字；若需要示例数据请标注“参考口径”）。
        视觉主题：\(theme.title)。

        必须且仅返回如下 JSON 结构（可用 ```json 包裹）：
        {
          "title": "主标题（简短有力）",
          "subtitle": "副标题或汇报场景说明",
          "slides": [
            {
              "title": "第 1 页标题",
              "layout": "cover | bullets | metrics | twoColumn | summary",
              "bullets": ["核心要点 1（每条不超过 28 字）", "核心要点 2", "核心要点 3"],
              "highlightMetric": "可选大数字亮点（如 99.9% 或 3.5×）",
              "highlightLabel": "可选大数字说明",
              "speakerNotes": "口播演讲备注（2~3 句自然衔接的话）",
              "visualHint": "建议配图或图表类型"
            }
          ]
        }
        要求：第 1 页 layout 为 cover，最后一页 layout 为 summary，中间合理穿插 bullets / metrics / twoColumn。
        """
    }

    /// Parses structured JSON (even wrapped in markdown fences or prose) with graceful Markdown-heading fallback.
    public static func parseDeck(from rawText: String, fallbackTopic: String, theme: WuMindPPTTheme) -> WuMindPPTDeck {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let jsonCandidate = extractJSONObject(from: trimmed),
           let data = jsonCandidate.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(WireDeck.self, from: data),
           !decoded.slides.isEmpty {
            let slides = decoded.slides.enumerated().map { idx, item in
                let parsedLayout = WuMindPPTDeck.SlideLayout(rawValue: item.layout ?? "") ?? (idx == 0 ? .cover : .bullets)
                let cleanBullets = (item.bullets ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return WuMindPPTDeck.Slide(
                    id: idx + 1,
                    title: item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "第 \(idx + 1) 页" : item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    layout: parsedLayout,
                    bullets: cleanBullets,
                    highlightMetric: item.highlightMetric?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    highlightLabel: item.highlightLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    speakerNotes: (item.speakerNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    visualHint: (item.visualHint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                )
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

    public static func exportMarkdownOutline(_ deck: WuMindPPTDeck) -> String {
        var lines: [String] = [
            "# \(deck.title)",
            "> \(deck.subtitle)",
            ""
        ]
        for slide in deck.slides {
            lines.append("---")
            lines.append("## \(slide.id). \(slide.title)")
            if let metric = slide.highlightMetric, !metric.isEmpty {
                let label = slide.highlightLabel.map { "（\($0)）" } ?? ""
                lines.append("**关键指标：\(metric)**\(label)")
            }
            for b in slide.bullets {
                lines.append("- \(b)")
            }
            if !slide.speakerNotes.isEmpty {
                lines.append("\n> 演讲备注：\(slide.speakerNotes)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") ,
              start < end else { return nil }
        return String(text[start...end])
    }

    private struct WireDeck: Decodable {
        struct WireSlide: Decodable {
            let title: String
            let layout: String?
            let bullets: [String]?
            let highlightMetric: String?
            let highlightLabel: String?
            let speakerNotes: String?
            let visualHint: String?
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
