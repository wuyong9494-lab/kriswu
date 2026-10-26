import Foundation
#if canImport(Compression)
import Compression
#endif

/// 周会文档是表格（金山 / 腾讯在线表格）时：按列读。
/// 认这几列：分组（合并单元格，下面几行空着的算同一组）、项目或工作内容（这一行是「本周问题」还是「上周问题进展」）、
/// 完成进展（一格里「1. 2. 3.」或「1️⃣2️⃣3️⃣」编号的拆成一条条）、负责人、状态，
/// 和「闭环 / 完成情况」那一列（「完成；2。明确…；3 进行中；4，上线」逐条对应到每一条）。
public enum MeetingTable {
    // MARK: - 复制出来的文字、CSV → 一格一格

    /// 制表符（从表格里复制出来的）或逗号（CSV）分隔的文字。一格里有换行、分隔符时整格带引号，引号写成两个
    public static func rows(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var atFieldStart = true
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && atFieldStart {
                quoted = true
                atFieldStart = false
            } else if c == separator {
                row.append(field); field = ""; atFieldStart = true
            } else if c == "\n" {
                row.append(field); rows.append(row); row = []; field = ""; atFieldStart = true
            } else {
                field.append(c)
                atFieldStart = false
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// 复制出来的网页表格（剪贴板里的 HTML）：一格里的换行保得住。
    /// 合并单元格（rowspan / colspan）盖住的位置补成空格子，和复制出来的文字一样由上面那格往下带
    public static func htmlRows(_ html: String) -> [[String]] {
        func regex(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        }
        let rowPattern = regex(#"<tr\b[^>]*>(.*?)</tr\s*>"#)
        let cellPattern = regex(#"<t([dh])\b([^>]*)>(.*?)</t\1\s*>"#)
        let ns = html as NSString
        var rows: [[String]] = []
        var covered: [Int: Int] = [:]   // 列 → 上面合并下来、还要盖住几行
        for tr in rowPattern.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let inner = ns.substring(with: tr.range(at: 1))
            let innerNS = inner as NSString
            var row: [String] = []
            var next: [Int: Int] = [:]
            func skipCovered() {
                while let n = covered[row.count], n > 0 {
                    if n > 1 { next[row.count] = n - 1 }
                    row.append("")
                }
            }
            for td in cellPattern.matches(in: inner, range: NSRange(location: 0, length: innerNS.length)) {
                skipCovered()
                let attributes = innerNS.substring(with: td.range(at: 2))
                let rowspan = max(1, span("rowspan", in: attributes))
                let colspan = max(1, span("colspan", in: attributes))
                let column = row.count
                row.append(cellText(innerNS.substring(with: td.range(at: 3))))
                row.append(contentsOf: Array(repeating: "", count: colspan - 1))
                if rowspan > 1 { for c in column..<(column + colspan) { next[c] = rowspan - 1 } }
            }
            skipCovered()
            covered = next
            if !row.isEmpty { rows.append(row) }
        }
        return rows
    }

    private static func span(_ name: String, in attributes: String) -> Int {
        let pattern = try! NSRegularExpression(pattern: name + #"\s*=\s*["']?(\d+)"#, options: [.caseInsensitive])
        let ns = attributes as NSString
        guard let m = pattern.firstMatch(in: attributes, range: NSRange(location: 0, length: ns.length)) else { return 1 }
        return Int(ns.substring(with: m.range(at: 1))) ?? 1
    }

    /// 一格的 HTML → 文字：<br>、段落换行，去掉标签，转回 &amp; 这类字符
    static func cellText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"</(p|div|li)\s*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[ \t]*\n[ \t\n]*"#, with: "\n", options: .regularExpression)
        let named = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (entity, char) in named { s = s.replacingOccurrences(of: entity, with: char) }
        let numeric = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|\d+);"#)
        let ns = s as NSString
        var out = ""
        var at = 0
        for m in numeric.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: at, length: m.range.location - at))
            let code = ns.substring(with: m.range(at: 1))
            let value = code.hasPrefix("x") || code.hasPrefix("X") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
            out += value.flatMap { Unicode.Scalar($0) }.map { String(Character($0)) } ?? ns.substring(with: m.range)
            at = m.range.location + m.range.length
        }
        out += ns.substring(from: at)
        return out.replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 表格 → 各组的问题

    private static let groupHeaders = ["分组", "组别", "小组", "部门"]
    private static let topicHeaders = ["项目", "工作内容", "事项", "类别", "类型"]
    private static let contentHeaders = ["进展", "进度", "内容", "问题", "描述", "情况"]
    private static let closureHeaders = ["闭环", "完成情况", "落实", "反馈", "备注"]
    private static let issueWords = ["问题", "困难", "协调", "需支持", "风险", "隐患"]

    /// 找到表头（前几行里有「分组」「组别」的那行）就按表格读；不是这种表格返回 nil
    public static func sections(_ rows: [[String]]) -> [MeetingNotes.Section]? {
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let h = rows.prefix(8).firstIndex(where: { $0.contains { cell in groupHeaders.contains(clean(cell)) } }) else { return nil }
        let header = rows[h].map(clean)
        var used = Set<Int>()
        func column(_ words: [String], exact: Bool = false) -> Int? {
            let i = header.indices.first { i in
                !used.contains(i) && !header[i].isEmpty && words.contains { exact ? header[i] == $0 : header[i].contains($0) }
            }
            if let i { used.insert(i) }
            return i
        }
        guard let groupCol = column(groupHeaders, exact: true) else { return nil }
        let ownerCol = column(["负责人", "责任人"])
        let statusCol = column(["状态"])
        let closureCol = column(closureHeaders)
        let topicCol = column(topicHeaders)
        // 没有「进展」这类列时，内容就在「项目 / 事项」那一列
        guard let contentCol = column(contentHeaders) ?? topicCol else { return nil }

        struct Row { var topic: String; var entries: [MeetingNotes.Entry] }
        var order: [String] = []
        var byGroup: [String: [Row]] = [:]
        var current: String?
        for (offset, raw) in rows.enumerated() where offset > h {
            func cell(_ i: Int?) -> String { guard let i, i < raw.count else { return "" }; return clean(raw[i]) }
            let name = cell(groupCol)
            if !name.isEmpty { current = MeetingNotes.normalizeGroup(name) }
            guard let group = current else { continue }
            let body = contentCol < raw.count ? raw[contentCol] : ""
            let pieces = numberedPieces(body)
            guard !pieces.isEmpty else { continue }
            let topic = contentCol == topicCol ? "" : cell(topicCol)
            let owner = cell(ownerCol)
            let notes = closureNotes(cell(closureCol))
            let rowStatus = cell(statusCol)
            // 这一行别的格子里写着「完成」「进行中」（比如写在「计划完成时间」里）
            let rowDone = isDoneNote(rowStatus)
                || raw.indices.contains { $0 != contentCol && $0 != closureCol && ["完成", "已完成", "已解决", "已闭环"].contains(clean(raw[$0])) }
            var entries: [MeetingNotes.Entry] = []
            // 在表格里的位置（第几行、第几列都从 1 数）和这几格的原文：改了写回金山文档时核对用
            func rawCell(_ i: Int?) -> String { guard let i, i < raw.count else { return "" }; return raw[i] }
            for piece in pieces {
                let note = notes[piece.number] ?? (pieces.count == 1 ? notes.values.first : nil)
                // 「完成情况」写了完成就算解决；写的是别的（「部署更新？」），看这一行别的格子（「计划完成时间」写着「已完成」）
                let done = note.map { isDoneNote($0) || (!isNotDoneNote($0) && rowDone) }
                    ?? (rowDone || MeetingTracker.isMarkedDone(piece.text))
                let detail = [topic.isEmpty ? nil : topic.replacingOccurrences(of: "\n", with: ""),
                              owner.isEmpty ? nil : "负责人：\(owner)",
                              note.map { "进展：\($0)" } ?? (rowStatus.isEmpty ? nil : "状态：\(rowStatus)")]
                    .compactMap { $0 }.joined(separator: " · ")
                let source = MeetingSource(row: offset + 1, contentColumn: contentCol + 1, number: piece.number, content: body,
                                           closureColumn: closureCol.map { $0 + 1 }, closure: rawCell(closureCol),
                                           ownerColumn: ownerCol.map { $0 + 1 }, owner: rawCell(ownerCol),
                                           topic: topic.replacingOccurrences(of: "\n", with: ""))
                entries.append(MeetingNotes.Entry(text: piece.text, done: done, detail: detail.isEmpty ? nil : detail, source: source))
            }
            if byGroup[group] == nil { order.append(group) }
            byGroup[group, default: []].append(Row(topic: topic, entries: entries))
        }
        // 一个组里有「…问题」那几行的，只取那几行；没有的整组都算
        return order.compactMap { group in
            let rows = byGroup[group] ?? []
            let issueRows = rows.filter { r in issueWords.contains(where: r.topic.contains) }
            let entries = (issueRows.isEmpty ? rows : issueRows).flatMap(\.entries)
            return entries.isEmpty ? nil : MeetingNotes.Section(group: group, entries: entries)
        }
    }

    /// 一格里的一条：第几条（从 1 数，「无」这类被去掉的也占号）、文字、在这一格原文里的位置
    struct Piece {
        var number: Int
        var text: String
        var range: NSRange
    }

    /// 一格里的内容拆成一条条：有「1️⃣2️⃣」就按它拆（里面的「1、2、」是小点，不拆）；
    /// 否则按行首的「1.」「2、」拆，没编号的行接在上一条后面
    static func splitNumbered(_ body: String) -> [String] {
        numberedPieces(body).map(\.text)
    }

    static func numberedPieces(_ body: String) -> [Piece] {
        let ns = body as NSString
        var raw: [(text: String, range: NSRange)] = []
        let keycap = try! NSRegularExpression(pattern: "[0-9#*]\u{FE0F}?\u{20E3}")
        let caps = keycap.matches(in: body, range: NSRange(location: 0, length: ns.length))
        if !caps.isEmpty {
            for (i, m) in caps.enumerated() {
                let start = m.range.location + m.range.length
                let end = i + 1 < caps.count ? caps[i + 1].range.location : ns.length
                let range = NSRange(location: start, length: end - start)
                raw.append((ns.substring(with: range), range))
            }
        } else {
            let numbered = try! NSRegularExpression(pattern: #"^[ \t]*[\(（]?\d{1,2}[\.、．\)）][ \t]*"#, options: [.anchorsMatchLines])
            var lineStart = 0
            while lineStart <= ns.length {
                let newline = ns.range(of: "\n", options: [], range: NSRange(location: lineStart, length: ns.length - lineStart))
                let lineEnd = newline.location == NSNotFound ? ns.length : newline.location
                let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                let line = ns.substring(with: lineRange)
                if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let m = numbered.firstMatch(in: body, range: lineRange) {
                        let start = m.range.location + m.range.length
                        let range = NSRange(location: start, length: lineEnd - start)
                        raw.append((ns.substring(with: range), range))
                    } else if let last = raw.last {
                        raw[raw.count - 1] = (last.text + " " + line.trimmingCharacters(in: .whitespacesAndNewlines),
                                              NSRange(location: last.range.location, length: lineEnd - last.range.location))
                    } else {
                        raw.append((line, lineRange))
                    }
                }
                if newline.location == NSNotFound { break }
                lineStart = lineEnd + 1
            }
        }
        let strip = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "；;，,"))
        return raw.enumerated().compactMap { item -> Piece? in
            let (i, piece) = item
            let text = piece.text.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: strip)
            guard text.count >= 2, !["无", "暂无", "无问题"].contains(text) else { return nil }
            return Piece(number: i + 1, text: text, range: trimmedRange(piece.range, in: ns))
        }
    }

    /// 位置去掉头尾的空白、换行（换文字时不把换行也换掉）
    private static func trimmedRange(_ range: NSRange, in ns: NSString) -> NSRange {
        let blank = CharacterSet.whitespacesAndNewlines
        func isBlank(_ i: Int) -> Bool { UnicodeScalar(ns.character(at: i)).map { blank.contains($0) } ?? false }
        var start = range.location, end = range.location + range.length
        while start < end, isBlank(start) { start += 1 }
        while end > start, isBlank(end - 1) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    // MARK: - 改了以后拼回一格

    /// 把一格里第 n 条换成新的文字，别的原样不动
    static func replacingPieces(in body: String, with edits: [Int: String]) -> String {
        guard !edits.isEmpty else { return body }
        let text = NSMutableString(string: body)
        for piece in numberedPieces(body).sorted(by: { $0.range.location > $1.range.location }) {
            if let new = edits[piece.number] { text.replaceCharacters(in: piece.range, with: new) }
        }
        return text as String
    }

    /// 在一格最后接上几条，编号接着往下（原来用 1️⃣ 的也接着用）。返回新的内容和第一条新加的是第几条
    static func appending(_ items: [String], to body: String) -> (text: String, firstNumber: Int) {
        let start = (numberedPieces(body).map(\.number).max() ?? 0) + 1
        let keycaps = body.unicodeScalars.contains("\u{20E3}")
        var text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        for (i, item) in items.enumerated() {
            let n = start + i
            let marker = keycaps && n <= 9 ? "\(n)\u{FE0F}\u{20E3}" : "\(n)."
            text += (text.isEmpty ? "" : "\n") + marker + item
        }
        return (text, start)
    }

    /// 「完成情况」那一格按条重写：「1. 完成；2. 进行中」（「1、2」会被当成两条，所以用「1.」）
    static func closureText(_ notes: [Int: String]) -> String {
        notes.keys.sorted().compactMap { n in notes[n].map { "\(n). \($0)" } }.joined(separator: "；")
    }

    /// 「闭环」那一格：「，完成；2。明确…；3 进行中；4，上线；5，进行中。」→ [1: 完成, 2: 明确…, 3: 进行中, …]
    /// 「1、2再讨论具体情况」→ 1、2 都是「再讨论具体情况」
    static func closureNotes(_ text: String) -> [Int: String] {
        let lead = try! NSRegularExpression(pattern: #"^((?:\d{1,2}\s*[、,，和及]\s*)*\d{1,2})(?!\d)\s*[\.、。，,:：)）\s]*(.*)$"#,
                                            options: [.dotMatchesLineSeparators])
        var result: [Int: String] = [:]
        var last: Int?
        for part in text.components(separatedBy: CharacterSet(charactersIn: "；;\n")) {
            let p = part.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "，,。、.")))
            guard !p.isEmpty else { continue }
            let ns = p as NSString
            if let m = lead.firstMatch(in: p, range: NSRange(location: 0, length: ns.length)) {
                let numbers = ns.substring(with: m.range(at: 1)).split { !$0.isNumber }.compactMap { Int($0) }
                let rest = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "。")))
                for n in numbers { result[n] = rest }
                last = numbers.last
            } else if let last {
                result[last] = (result[last].map { $0 + "；" } ?? "") + p
            } else {
                result[1] = p   // 第一条常常不写「1」
                last = 1
            }
        }
        return result
    }

    /// 进展写明了还没做完
    static func isNotDoneNote(_ note: String) -> Bool {
        ["未完成", "没完成", "进行中", "未解决", "待", "计划", "再讨论", "跟进", "推进中"].contains(where: note.contains)
    }

    /// 进展写的是做完了
    static func isDoneNote(_ note: String) -> Bool {
        guard !isNotDoneNote(note) else { return false }
        return ["完成", "上线", "已解决", "解决", "闭环", "关闭", "已处理", "结束", "落实", "已协调"].contains(where: note.contains)
    }
}

/// 读 Excel（.xlsx）文件的第一张表：只取每一格的文字
public enum XLSXReader {
    /// 第一张表
    public static func rows(_ data: Data) -> [[String]]? {
        sheets(data)?.first
    }

    /// 每一张表，按 sheet1、sheet2… 的顺序
    public static func sheets(_ data: Data) -> [[[String]]]? {
        guard let files = unzip(data, wanted: { $0 == "xl/sharedStrings.xml" || $0.hasPrefix("xl/worksheets/sheet") }) else { return nil }
        let shared = files["xl/sharedStrings.xml"].map(SharedStrings.parse) ?? []
        let names = files.keys.filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted { a, b in (Int(a.filter(\.isNumber)) ?? 0) < (Int(b.filter(\.isNumber)) ?? 0) }
        guard !names.isEmpty else { return nil }
        return names.compactMap { files[$0] }.map { Sheet.parse($0, shared: shared) }
    }

    /// 只解压用得到的几个文件
    static func unzip(_ data: Data, wanted: (String) -> Bool) -> [String: Data]? {
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 1 < bytes.count ? Int(bytes[o]) | Int(bytes[o + 1]) << 8 : 0 }
        func u32(_ o: Int) -> Int { o + 3 < bytes.count ? u16(o) | u16(o + 2) << 16 : 0 }
        // 文件末尾的目录索引
        guard bytes.count > 22, let end = stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1)
            .first(where: { u32($0) == 0x06054b50 }) else { return nil }
        var offset = u32(end + 16)
        let count = u16(end + 10)
        var files: [String: Data] = [:]
        for _ in 0..<count {
            guard u32(offset) == 0x02014b50 else { break }
            let method = u16(offset + 10)
            let compressed = u32(offset + 20), size = u32(offset + 24)
            let nameLength = u16(offset + 28), extra = u16(offset + 30), comment = u16(offset + 32)
            let local = u32(offset + 42)
            let nameEnd = min(bytes.count, offset + 46 + nameLength)
            let name = String(decoding: bytes[min(bytes.count, offset + 46)..<nameEnd], as: UTF8.self)
            offset += 46 + nameLength + extra + comment
            guard wanted(name), u32(local) == 0x04034b50 else { continue }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + compressed <= bytes.count else { continue }
            let raw = Array(bytes[start..<start + compressed])
            if method == 0 {
                files[name] = Data(raw)
            } else if method == 8, let inflated = inflate(raw, size: size) {
                files[name] = inflated
            }
        }
        return files
    }

    static func inflate(_ raw: [UInt8], size: Int) -> Data? {
        #if canImport(Compression)
        guard size > 0, !raw.isEmpty else { return size == 0 ? Data() : nil }
        var out = [UInt8](repeating: 0, count: size)
        let n = raw.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, size, src.baseAddress!, raw.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n == size ? Data(out) : nil
        #else
        return nil
        #endif
    }

    /// xl/sharedStrings.xml：每个 <si> 一段文字（可能分成好几段 <r><t>）
    final class SharedStrings: NSObject, XMLParserDelegate {
        var strings: [String] = []
        private var current: String?
        private var inText = false

        static func parse(_ data: Data) -> [String] {
            let d = SharedStrings()
            let parser = XMLParser(data: data)
            parser.delegate = d
            parser.parse()
            return d.strings
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == "si" { current = "" }
            if name == "t" { inText = true }
            // 注音（rPh）里的字不要
            if name == "rPh" { inText = false }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { current? += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "t" { inText = false }
            if name == "si" { strings.append(current ?? ""); current = nil }
        }
    }

    /// 表格：<row><c r="B2" t="s"><v>3</v></c>…；t="s" 是共享文字的编号，inlineStr 是 <is><t>，别的直接是 <v>
    final class Sheet: NSObject, XMLParserDelegate {
        private let shared: [String]
        private var cells: [Int: [Int: String]] = [:]
        private var ref = "", type = "", value = ""
        private var reading = false
        private var nextRow = 0, nextColumn = 0

        init(shared: [String]) { self.shared = shared }

        static func parse(_ data: Data, shared: [String]) -> [[String]] {
            let s = Sheet(shared: shared)
            let parser = XMLParser(data: data)
            parser.delegate = s
            parser.parse()
            guard let last = s.cells.keys.max() else { return [] }
            return (0...last).map { r in
                let row = s.cells[r] ?? [:]
                guard let width = row.keys.max() else { return [] }
                return (0...width).map { row[$0] ?? "" }
            }
        }

        /// 「B12」→（11, 1）
        static func position(_ ref: String) -> (row: Int, column: Int)? {
            var column = 0, digits = ""
            for ch in ref.uppercased() {
                if let a = ch.asciiValue, a >= 65, a <= 90 { column = column * 26 + Int(a - 64) } else if ch.isNumber { digits.append(ch) }
            }
            guard column > 0, let row = Int(digits) else { return nil }
            return (row - 1, column - 1)
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            switch name {
            case "row":
                if let r = attributes["r"].flatMap(Int.init) { nextRow = r - 1 }
                nextColumn = 0
            case "c":
                ref = attributes["r"] ?? ""
                type = attributes["t"] ?? ""
                value = ""
            case "v", "t":
                reading = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if reading { value += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "v", "t":
                reading = false
            case "c":
                let pos = Self.position(ref) ?? (row: nextRow, column: nextColumn)
                let text = type == "s" ? Int(value).flatMap { $0 < shared.count ? shared[$0] : nil } ?? "" : value
                if !text.isEmpty { cells[pos.row, default: [:]][pos.column] = text }
                nextColumn = pos.column + 1
            case "row":
                nextRow += 1
            default: break
            }
        }
    }
}
