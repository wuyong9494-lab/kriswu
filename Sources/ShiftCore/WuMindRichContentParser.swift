import Foundation

/// Pure-Swift rich content parser for WUMIND flagship answers:
/// - Splits Markdown responses into prose, fenced code blocks, Mermaid diagrams, and display LaTeX math (`$$...$$`, `\[...\]`).
/// - Formats inline LaTeX math (`$...$`, `\(...\)`) into clean Unicode mathematical typography while never breaking currency (`¥100`, `$100`).
/// - Parses Mermaid `flowchart` / `graph`, `sequenceDiagram`, and `pie` charts into structured ASTs for native 60 FPS SwiftUI Canvas rendering.
public enum WuMindRichContentParser {
    public enum Segment: Equatable, Sendable {
        case prose(String)
        case code(language: String, code: String)
        case displayMath(latex: String, pretty: String)
        case mermaid(source: String, diagram: WuMindMermaidDiagram)
        case table(headers: [String], rows: [[String]])
    }

    public static func splitSegments(_ markdown: String) -> [Segment] {
        let lines = markdown.components(separatedBy: "\n")
        var segments: [Segment] = []
        var proseBuffer: [String] = []
        var idx = 0

        func flushProse() {
            guard !proseBuffer.isEmpty else { return }
            let joined = proseBuffer.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.prose(formatInlineMath(in: joined)))
            }
            proseBuffer.removeAll(keepingCapacity: true)
        }

        while idx < lines.count {
            let line = lines[idx]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 1. Fenced code block (or ```mermaid diagram)
            if trimmed.hasPrefix("```") {
                flushProse()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
                idx += 1
                var body: [String] = []
                while idx < lines.count {
                    let cur = lines[idx]
                    if cur.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        idx += 1
                        break
                    }
                    body.append(cur)
                    idx += 1
                }
                let codeStr = body.joined(separator: "\n")
                if lang == "mermaid" {
                    let parsed = WuMindMermaidParser.parse(codeStr)
                    segments.append(.mermaid(source: codeStr, diagram: parsed))
                } else {
                    segments.append(.code(language: lang, code: codeStr))
                }
                continue
            }

            // 2. Display LaTeX math block: $$ ... $$ (single-line or multi-line) or \[ ... \]
            if trimmed.hasPrefix("$$") {
                if trimmed.count > 4 && trimmed.hasSuffix("$$") {
                    flushProse()
                    let inner = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !inner.isEmpty {
                        segments.append(.displayMath(latex: inner, pretty: WuMindMathFormatter.pretty(inner)))
                    }
                    idx += 1
                    continue
                } else if trimmed == "$$" || trimmed.hasPrefix("$$") {
                    flushProse()
                    var mathLines: [String] = []
                    let firstTail = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if !firstTail.isEmpty { mathLines.append(firstTail) }
                    idx += 1
                    while idx < lines.count {
                        let curTrim = lines[idx].trimmingCharacters(in: .whitespaces)
                        if curTrim == "$$" || curTrim.hasSuffix("$$") {
                            let head = String(curTrim.dropLast(2)).trimmingCharacters(in: .whitespaces)
                            if !head.isEmpty { mathLines.append(head) }
                            idx += 1
                            break
                        }
                        mathLines.append(lines[idx])
                        idx += 1
                    }
                    let latex = mathLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        segments.append(.displayMath(latex: latex, pretty: WuMindMathFormatter.pretty(latex)))
                    }
                    continue
                }
            }

            if trimmed.hasPrefix("\\[") {
                if trimmed.hasSuffix("\\]") && trimmed.count > 4 {
                    flushProse()
                    let inner = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !inner.isEmpty {
                        segments.append(.displayMath(latex: inner, pretty: WuMindMathFormatter.pretty(inner)))
                    }
                    idx += 1
                    continue
                } else {
                    flushProse()
                    var mathLines: [String] = []
                    let firstTail = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if !firstTail.isEmpty { mathLines.append(firstTail) }
                    idx += 1
                    while idx < lines.count {
                        let curTrim = lines[idx].trimmingCharacters(in: .whitespaces)
                        if curTrim.hasSuffix("\\]") {
                            let head = String(curTrim.dropLast(2)).trimmingCharacters(in: .whitespaces)
                            if !head.isEmpty { mathLines.append(head) }
                            idx += 1
                            break
                        }
                        mathLines.append(lines[idx])
                        idx += 1
                    }
                    let latex = mathLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        segments.append(.displayMath(latex: latex, pretty: WuMindMathFormatter.pretty(latex)))
                    }
                    continue
                }
            }

            // 3. Markdown GFM Table: header row + delimiter row (| --- | --- |) + body rows
            if idx + 1 < lines.count,
               trimmed.contains("|"),
               isTableSeparatorLine(lines[idx + 1]) {
                let headers = parseTableCells(line).map { formatInlineMath(in: $0) }
                if headers.count >= 2 {
                    flushProse()
                    idx += 2
                    var rows: [[String]] = []
                    while idx < lines.count {
                        let rowTrim = lines[idx].trimmingCharacters(in: .whitespaces)
                        if rowTrim.isEmpty || !rowTrim.contains("|") { break }
                        let cells = parseTableCells(lines[idx]).map { formatInlineMath(in: $0) }
                        if cells.isEmpty { break }
                        var normalized = cells
                        while normalized.count < headers.count { normalized.append("") }
                        rows.append(Array(normalized.prefix(headers.count)))
                        idx += 1
                    }
                    segments.append(.table(headers: headers, rows: rows))
                    continue
                }
            }

            proseBuffer.append(line)
            idx += 1
        }

        flushProse()
        return segments
    }

    private static func isTableSeparatorLine(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|"), trimmed.contains("-") else { return false }
        let cells = parseTableCells(trimmed)
        guard cells.count >= 2 else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell.replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespaces)
            return stripped.isEmpty && cell.contains("-")
        }
    }

    private static func parseTableCells(_ raw: String) -> [String] {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Formats inline LaTeX `\(...\)` and `$...$` outside inline backtick spans without touching currency like `$100`.
    public static func formatInlineMath(in text: String) -> String {
        guard text.contains("$") || text.contains("\\(") else { return text }
        // Split around inline code backticks so code spans remain untouched.
        let parts = text.split(separator: "`", omittingEmptySubsequences: false)
        var rebuilt: [String] = []
        for (i, part) in parts.enumerated() {
            if i % 2 == 1 {
                rebuilt.append("`\(part)`")
            } else {
                var s = String(part)
                s = replaceInlineParenMath(in: s)
                s = replaceInlineDollarMath(in: s)
                rebuilt.append(s)
            }
        }
        return rebuilt.joined()
    }

    private static func replaceInlineParenMath(in input: String) -> String {
        var result = ""
        var cursor = input.startIndex
        while let open = input.range(of: "\\(", range: cursor..<input.endIndex),
              let close = input.range(of: "\\)", range: open.upperBound..<input.endIndex) {
            result += input[cursor..<open.lowerBound]
            let inner = String(input[open.upperBound..<close.lowerBound])
            result += WuMindMathFormatter.pretty(inner)
            cursor = close.upperBound
        }
        result += input[cursor..<input.endIndex]
        return result
    }

    private static func replaceInlineDollarMath(in input: String) -> String {
        let chars = Array(input)
        var out = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "$", (i == 0 || chars[i - 1] != "\\"), (i + 1 < chars.count && chars[i + 1] != "$") {
                // Find matching closing $ on same line
                var j = i + 1
                var foundEnd: Int? = nil
                while j < chars.count {
                    if chars[j] == "\n" { break }
                    if chars[j] == "$" && chars[j - 1] != "\\" {
                        foundEnd = j
                        break
                    }
                    j += 1
                }
                if let end = foundEnd, end > i + 1 {
                    let candidate = String(chars[(i + 1)..<end])
                    // Guard against prose currency like "$100 to $200" (leading/trailing spaces or pure numeric price)
                    let trimmed = candidate.trimmingCharacters(in: .whitespaces)
                    let startsOrEndsWithSpace = candidate.first == " " || candidate.last == " "
                    let looksLikePrice = trimmed.allSatisfy { $0.isNumber || $0 == "." || $0 == "," }
                    if !startsOrEndsWithSpace && !looksLikePrice && !trimmed.isEmpty {
                        out += WuMindMathFormatter.pretty(trimmed)
                        i = end + 1
                        continue
                    }
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }
}

// MARK: - Native LaTeX Mathematical Typography Formatter

public enum WuMindMathFormatter {
    private static let symbolMap: [(String, String)] = [
        // Multi-char operators & relations first
        ("\\Longleftrightarrow", "⟺"), ("\\Longrightarrow", "⟹"), ("\\Longleftarrow", "⟸"),
        ("\\leftrightarrow", "↔"), ("\\Rightarrow", "⇒"), ("\\Leftarrow", "⇐"),
        ("\\rightarrow", "→"), ("\\leftarrow", "←"), ("\\mapsto", "↦"), ("\\to", "→"),
        ("\\leqslant", "≤"), ("\\geqslant", "≥"), ("\\approx", "≈"), ("\\equiv", "≡"),
        ("\\propto", "∝"), ("\\subset", "⊂"), ("\\subseteq", "⊆"), ("\\supset", "⊃"),
        ("\\supseteq", "⊇"), ("\\notin", "∉"), ("\\times", "×"), ("\\cdot", "·"),
        ("\\oplus", "⊕"), ("\\otimes", "⊗"), ("\\infty", "∞"), ("\\partial", "∂"),
        ("\\nabla", "∇"), ("\\forall", "∀"), ("\\exists", "∃"), ("\\emptyset", "∅"),
        ("\\degree", "°"), ("\\angle", "∠"), ("\\perp", "⊥"), ("\\parallel", "∥"),
        ("\\cdots", "⋯"), ("\\ldots", "…"), ("\\dots", "…"), ("\\vdots", "⋮"),
        ("\\lfloor", "⌊"), ("\\rfloor", "⌋"), ("\\lceil", "⌈"), ("\\rceil", "⌉"),
        ("\\langle", "⟨"), ("\\rangle", "⟩"),
        ("\\sum", "∑"), ("\\prod", "∏"), ("\\int", "∫"), ("\\oint", "∮"),
        ("\\neq", "≠"), ("\\ne", "≠"), ("\\leq", "≤"), ("\\le", "≤"),
        ("\\geq", "≥"), ("\\ge", "≥"), ("\\pm", "±"), ("\\mp", "∓"),
        ("\\div", "÷"), ("\\cap", "∩"), ("\\cup", "∪"), ("\\in", "∈"),
        ("\\sim", "∼"), ("\\cong", "≅"), ("\\ll", "≪"), ("\\gg", "≫"),
        // Greek letters (uppercase & lowercase)
        ("\\Gamma", "Γ"), ("\\Delta", "Δ"), ("\\Theta", "Θ"), ("\\Lambda", "Λ"),
        ("\\Xi", "Ξ"), ("\\Pi", "Π"), ("\\Sigma", "Σ"), ("\\Phi", "Φ"),
        ("\\Psi", "Ψ"), ("\\Omega", "Ω"),
        ("\\varepsilon", "ε"), ("\\varphi", "φ"), ("\\vartheta", "θ"),
        ("\\alpha", "α"), ("\\beta", "β"), ("\\gamma", "γ"), ("\\delta", "δ"),
        ("\\epsilon", "ε"), ("\\zeta", "ζ"), ("\\eta", "η"), ("\\theta", "θ"),
        ("\\iota", "ι"), ("\\kappa", "κ"), ("\\lambda", "λ"), ("\\mu", "μ"),
        ("\\nu", "ν"), ("\\xi", "ξ"), ("\\pi", "π"), ("\\rho", "ρ"),
        ("\\sigma", "σ"), ("\\tau", "τ"), ("\\upsilon", "υ"), ("\\phi", "φ"),
        ("\\chi", "χ"), ("\\psi", "ψ"), ("\\omega", "ω"),
        ("\\mathbb{R}", "ℝ"), ("\\mathbb{N}", "ℕ"), ("\\mathbb{Z}", "ℤ"),
        ("\\mathbb{Q}", "ℚ"), ("\\mathbb{C}", "ℂ"),
        ("\\left", ""), ("\\right", ""), ("\\,", " "), ("\\;", " "), ("\\quad", "  "), ("\\qquad", "    "),
    ]

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "n": "ⁿ", "i": "ⁱ", "x": "ˣ", "y": "ʸ", "k": "ᵏ", "T": "ᵀ"
    ]

    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ",
        "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ",
        "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ"
    ]

    public static func pretty(_ rawLatex: String) -> String {
        var s = rawLatex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        // Handle \text{...}, \mathrm{...}, \mathbf{...}, \operatorname{...}
        for wrapper in ["\\text", "\\mathrm", "\\mathbf", "\\mathit", "\\mathcal", "\\operatorname"] {
            s = unwrapSingleArg(wrapper, in: s) { $0 }
        }
        // Handle \vec{x} -> x⃗, \hat{x} -> x̂, \bar{x} -> x̄
        s = unwrapSingleArg("\\vec", in: s) { "\($0)\u{20D7}" }
        s = unwrapSingleArg("\\hat", in: s) { "\($0)\u{0302}" }
        s = unwrapSingleArg("\\bar", in: s) { "\($0)\u{0304}" }
        // Handle \sqrt{x} -> √(x)
        s = unwrapSingleArg("\\sqrt", in: s) { inner in
            inner.count <= 2 ? "√\(inner)" : "√(\(inner))"
        }
        // Handle \frac{a}{b} and \dfrac{a}{b}
        s = unwrapTwoArgs("\\dfrac", in: s) { num, den in
            let n = num.count <= 3 ? num : "(\(num))"
            let d = den.count <= 3 ? den : "(\(den))"
            return "\(n)/\(d)"
        }
        s = unwrapTwoArgs("\\frac", in: s) { num, den in
            let n = num.count <= 3 ? num : "(\(num))"
            let d = den.count <= 3 ? den : "(\(den))"
            return "\(n)/\(d)"
        }

        // Replace LaTeX commands with crisp Unicode math symbols
        for (cmd, sym) in symbolMap {
            s = s.replacingOccurrences(of: cmd, with: sym)
        }

        // Convert ^{...} / ^x and _{...} / _x to Unicode superscripts/subscripts where representable
        s = convertScripts(in: s, trigger: "^", table: superscripts)
        s = convertScripts(in: s, trigger: "_", table: subscripts)

        // Clean leftover simple grouping braces and line breaks
        s = s.replacingOccurrences(of: "\\\\", with: "\n")
        s = s.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unwrapSingleArg(_ command: String, in input: String, transform: (String) -> String) -> String {
        var s = input
        while let range = s.range(of: command + "{") {
            guard let closeIdx = matchingBrace(in: s, openBrace: s.index(before: range.upperBound)) else { break }
            let inner = String(s[range.upperBound..<closeIdx])
            let replacement = transform(inner)
            s.replaceSubrange(range.lowerBound...closeIdx, with: replacement)
        }
        return s
    }

    private static func unwrapTwoArgs(_ command: String, in input: String, transform: (String, String) -> String) -> String {
        var s = input
        while let range = s.range(of: command + "{") {
            guard let close1 = matchingBrace(in: s, openBrace: s.index(before: range.upperBound)) else { break }
            let after1 = s.index(after: close1)
            guard after1 < s.endIndex, s[after1] == "{",
                  let close2 = matchingBrace(in: s, openBrace: after1) else { break }
            let arg1 = String(s[range.upperBound..<close1])
            let arg2 = String(s[s.index(after: after1)..<close2])
            s.replaceSubrange(range.lowerBound...close2, with: transform(arg1, arg2))
        }
        return s
    }

    private static func matchingBrace(in s: String, openBrace: String.Index) -> String.Index? {
        var depth = 0
        var idx = openBrace
        while idx < s.endIndex {
            let ch = s[idx]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return idx }
            }
            idx = s.index(after: idx)
        }
        return nil
    }

    private static func convertScripts(in input: String, trigger: Character, table: [Character: Character]) -> String {
        let chars = Array(input)
        var out = ""
        var i = 0
        while i < chars.count {
            if chars[i] == trigger, i + 1 < chars.count {
                if chars[i + 1] == "{" {
                    var j = i + 2
                    var depth = 1
                    while j < chars.count && depth > 0 {
                        if chars[j] == "{" { depth += 1 }
                        else if chars[j] == "}" { depth -= 1 }
                        j += 1
                    }
                    if depth == 0 {
                        let inner = Array(chars[(i + 2)..<(j - 1)])
                        if !inner.isEmpty && inner.allSatisfy({ table[$0] != nil }) {
                            out.append(contentsOf: inner.compactMap { table[$0] })
                            i = j
                            continue
                        }
                    }
                } else if let mapped = table[chars[i + 1]] {
                    out.append(mapped)
                    i += 2
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }
}

// MARK: - Native Mermaid Diagram AST & Parser

public enum WuMindMermaidDiagram: Equatable, Sendable {
    public enum Direction: String, Equatable, Sendable {
        case topDown = "TD"
        case leftRight = "LR"
    }

    public enum NodeShape: Equatable, Sendable {
        case rect, rounded, diamond, circle
    }

    public struct FlowNode: Identifiable, Equatable, Sendable {
        public let id: String
        public let label: String
        public let shape: NodeShape
        public let layer: Int

        public init(id: String, label: String, shape: NodeShape, layer: Int = 0) {
            self.id = id
            self.label = label
            self.shape = shape
            self.layer = layer
        }
    }

    public struct FlowEdge: Identifiable, Equatable, Sendable {
        public let id: String
        public let from: String
        public let to: String
        public let label: String?
        public let dashed: Bool

        public init(from: String, to: String, label: String? = nil, dashed: Bool = false) {
            self.id = "\(from)->\(to):\(label ?? "")"
            self.from = from
            self.to = to
            self.label = label
            self.dashed = dashed
        }
    }

    public struct SequenceMessage: Identifiable, Equatable, Sendable {
        public let id: Int
        public let from: String
        public let to: String
        public let label: String
        public let dashed: Bool
    }

    public struct PieSlice: Identifiable, Equatable, Sendable {
        public let id: String
        public let label: String
        public let value: Double
    }

    case flowchart(direction: Direction, nodes: [FlowNode], edges: [FlowEdge])
    case sequence(actors: [String], messages: [SequenceMessage])
    case pie(title: String, slices: [PieSlice])
    case unsupported(kind: String)
}

public enum WuMindMermaidParser {
    public static func parse(_ source: String) -> WuMindMermaidDiagram {
        let lines = source.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
        guard let header = lines.first else {
            return .unsupported(kind: "empty")
        }
        let lower = header.lowercased()
        if lower.hasPrefix("flowchart") || lower.hasPrefix("graph") {
            let dir: WuMindMermaidDiagram.Direction = (lower.contains(" lr") || lower.contains(" rl")) ? .leftRight : .topDown
            return parseFlowchart(lines: Array(lines.dropFirst()), direction: dir)
        }
        if lower.hasPrefix("sequencediagram") {
            return parseSequence(lines: Array(lines.dropFirst()))
        }
        if lower.hasPrefix("pie") {
            return parsePie(header: header, lines: Array(lines.dropFirst()))
        }
        return .unsupported(kind: String(header.prefix(32)))
    }

    private static func parseFlowchart(lines: [String], direction: WuMindMermaidDiagram.Direction) -> WuMindMermaidDiagram {
        var nodeOrder: [String] = []
        var nodeLabels: [String: (String, WuMindMermaidDiagram.NodeShape)] = [:]
        var edges: [WuMindMermaidDiagram.FlowEdge] = []

        func registerNode(_ rawToken: String) -> String? {
            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }
            let (id, label, shape) = parseNodeToken(token)
            guard !id.isEmpty else { return nil }
            if !nodeOrder.contains(id) { nodeOrder.append(id) }
            if nodeLabels[id] == nil || label != id {
                nodeLabels[id] = (label, shape)
            }
            return id
        }

        let arrowTokens = ["-.->", "==>", "-->", "---", "->"]
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "; "))
            let low = line.lowercased()
            if low.hasPrefix("subgraph ") || low == "end" || low.hasPrefix("style ") || low.hasPrefix("classdef ") || low.hasPrefix("class ") {
                continue
            }
            // Find an arrow operator
            var matchedArrow: (range: Range<String.Index>, token: String)? = nil
            for tok in arrowTokens {
                if let r = line.range(of: tok) {
                    if matchedArrow == nil || r.lowerBound < matchedArrow!.range.lowerBound {
                        matchedArrow = (r, tok)
                    }
                }
            }
            if let arrow = matchedArrow {
                let left = String(line[..<arrow.range.lowerBound]).trimmingCharacters(in: .whitespaces)
                var right = String(line[arrow.range.upperBound...]).trimmingCharacters(in: .whitespaces)
                var edgeLabel: String? = nil
                if right.hasPrefix("|"), let secondBar = right.dropFirst().firstIndex(of: "|") {
                    edgeLabel = String(right[right.index(after: right.startIndex)..<secondBar]).trimmingCharacters(in: .whitespaces)
                    right = String(right[right.index(after: secondBar)...]).trimmingCharacters(in: .whitespaces)
                }
                if let fromID = registerNode(left), let toID = registerNode(right) {
                    edges.append(.init(from: fromID, to: toID, label: edgeLabel, dashed: arrow.token.contains(".")))
                }
            } else {
                _ = registerNode(line)
            }
        }

        // Assign topological layers via BFS from roots for clean layout
        var inDegree: [String: Int] = Dictionary(uniqueKeysWithValues: nodeOrder.map { ($0, 0) })
        var adj: [String: [String]] = [:]
        for e in edges {
            inDegree[e.to, default: 0] += 1
            adj[e.from, default: []].append(e.to)
        }
        var layers: [String: Int] = [:]
        var queue = nodeOrder.filter { (inDegree[$0] ?? 0) == 0 }
        if queue.isEmpty, let first = nodeOrder.first { queue = [first] }
        for q in queue { layers[q] = 0 }
        var head = 0
        while head < queue.count {
            let cur = queue[head]; head += 1
            let curLayer = layers[cur] ?? 0
            for nxt in adj[cur] ?? [] {
                let candidate = min(12, curLayer + 1)
                if candidate > (layers[nxt] ?? -1) {
                    layers[nxt] = candidate
                    if queue.count < 80 { queue.append(nxt) }
                }
            }
        }

        let nodes: [WuMindMermaidDiagram.FlowNode] = nodeOrder.map { id in
            let info = nodeLabels[id] ?? (id, .rect)
            return .init(id: id, label: info.0, shape: info.1, layer: layers[id] ?? 0)
        }
        guard !nodes.isEmpty else { return .unsupported(kind: "flowchart") }
        return .flowchart(direction: direction, nodes: nodes, edges: edges)
    }

    private static func parseNodeToken(_ token: String) -> (String, String, WuMindMermaidDiagram.NodeShape) {
        let patterns: [(open: String, close: String, shape: WuMindMermaidDiagram.NodeShape)] = [
            ("((", "))", .circle),
            ("([", "])", .rounded),
            ("{", "}", .diamond),
            ("[", "]", .rect),
            ("(", ")", .rounded),
        ]
        for p in patterns {
            if let openRange = token.range(of: p.open),
               token.hasSuffix(p.close),
               openRange.upperBound <= token.index(token.endIndex, offsetBy: -p.close.count) {
                let id = String(token[..<openRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let endIdx = token.index(token.endIndex, offsetBy: -p.close.count)
                let rawLabel = String(token[openRange.upperBound..<endIdx])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                let cleanID = id.isEmpty ? rawLabel : id
                return (cleanID, rawLabel.isEmpty ? cleanID : rawLabel, p.shape)
            }
        }
        return (token, token, .rect)
    }

    private static func parseSequence(lines: [String]) -> WuMindMermaidDiagram {
        var actors: [String] = []
        var messages: [WuMindMermaidDiagram.SequenceMessage] = []
        func addActor(_ name: String) {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && !actors.contains(clean) { actors.append(clean) }
        }
        let arrows = ["-->>", "->>", "-->", "->"]
        for line in lines {
            if line.lowercased().hasPrefix("participant ") || line.lowercased().hasPrefix("actor ") {
                let rest = line.split(separator: " ", maxSplits: 1).last.map(String.init) ?? ""
                let name = rest.components(separatedBy: " as ").first ?? rest
                addActor(name)
                continue
            }
            for arrow in arrows {
                if let r = line.range(of: arrow) {
                    let from = String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let after = String(line[r.upperBound...])
                    let parts = after.split(separator: ":", maxSplits: 1)
                    let to = String(parts[0]).trimmingCharacters(in: CharacterSet(charactersIn: "+- "))
                    let label = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
                    if !from.isEmpty && !to.isEmpty {
                        addActor(from); addActor(to)
                        messages.append(.init(id: messages.count, from: from, to: to, label: label, dashed: arrow.hasPrefix("--")))
                    }
                    break
                }
            }
        }
        guard !actors.isEmpty else { return .unsupported(kind: "sequenceDiagram") }
        return .sequence(actors: actors, messages: messages)
    }

    private static func parsePie(header: String, lines: [String]) -> WuMindMermaidDiagram {
        var title = ""
        if let tRange = header.range(of: "title ", options: .caseInsensitive) {
            title = String(header[tRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        var slices: [WuMindMermaidDiagram.PieSlice] = []
        for line in lines {
            if line.lowercased().hasPrefix("title ") {
                title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let label = String(parts[0]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            let valStr = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if !label.isEmpty, let val = Double(valStr), val > 0 {
                slices.append(.init(id: "\(slices.count)-\(label)", label: label, value: val))
            }
        }
        guard !slices.isEmpty else { return .unsupported(kind: "pie") }
        return .pie(title: title.isEmpty ? "占比分布" : title, slices: slices)
    }
}
