import Foundation

public enum ScheduleParseError: Error, Equatable, LocalizedError {
    case empty
    case noDates
    case nameNotFound([String])

    public var errorDescription: String? {
        switch self {
        case .empty: return "内容为空"
        case .noDates: return "没有识别到任何日期"
        case .nameNotFound(let aliases): return "排班表里没有找到「\(aliases.joined(separator: " / "))」"
        }
    }
}

public struct ParseResult: Equatable {
    public enum Format: String { case ics = "日历 (ICS)", json = "JSON", matrix = "月度排班表", column = "按列排班表", roster = "岗位排班表", list = "日期列表", api = "数据接口" }

    public var entries: [DayKey: String]
    public var format: Format

    public init(entries: [DayKey: String], format: Format) {
        self.entries = entries
        self.format = format
    }

    /// 解析出的日期范围；同步时用新数据整体替换这一段。
    public var range: ClosedRange<DayKey>? {
        guard let lo = entries.keys.min(), let hi = entries.keys.max() else { return nil }
        return lo...hi
    }
}

/// 把各种排班数据（ICS 日历、JSON、CSV/Excel 粘贴、随手写的文字）解析成「日期 → 班次」。
/// 如果是多人排班表，用 aliases（例如 ["张伟", "zhangwei"]）找出属于自己的那一行/列。
public struct ScheduleParser {
    public var aliases: [String]
    public var reference: DayKey
    public var timeZone: TimeZone

    public init(aliases: [String], reference: DayKey, timeZone: TimeZone = .current) {
        self.aliases = aliases.map(Self.normalize).filter { !$0.isEmpty }
        self.reference = reference
        self.timeZone = timeZone
    }

    private var dates: DateTokenParser { DateTokenParser(reference: reference) }

    public func parse(_ text: String) throws -> ParseResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{FEFF}", with: "")
        guard !trimmed.isEmpty else { throw ScheduleParseError.empty }

        let result: ParseResult
        if trimmed.range(of: "BEGIN:VCALENDAR", options: .caseInsensitive) != nil {
            result = try parseICS(trimmed)
        } else if let first = trimmed.first, first == "[" || first == "{",
                  let json = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) {
            result = try parseJSON(json)
        } else {
            result = try parseTable(Self.splitRows(trimmed))
        }
        guard !result.entries.isEmpty else { throw ScheduleParseError.noDates }
        return result
    }

    // MARK: - 名字匹配

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace }
    }

    func isMe(_ cell: String) -> Bool {
        let c = Self.normalize(cell)
        guard !c.isEmpty else { return false }
        return aliases.contains { c == $0 || c.contains($0) }
    }

    /// 去掉文字里的名字，例如 "张伟-夜班" → "夜班"。
    func removingAliases(_ s: String) -> String {
        var out = s
        for alias in aliases {
            out = out.replacingOccurrences(of: alias, with: "", options: .caseInsensitive)
        }
        let junk = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—:：,，|/()（）[]【】"))
        return out.trimmingCharacters(in: junk)
    }

    // MARK: - 合并

    private static func add(_ value: String, to day: DayKey, in entries: inout [DayKey: String]) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        if let existing = entries[day] {
            if !existing.components(separatedBy: "+").contains(v) { entries[day] = existing + "+" + v }
        } else {
            entries[day] = v
        }
    }

    // MARK: - 表格（CSV / TSV / 空格分隔 / 粘贴文字）

    static func splitRows(_ text: String) -> [[String]] {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let sample = lines.prefix(20)
        let delimiter: Character?
        if sample.contains(where: { $0.contains("\t") }) {
            delimiter = "\t"
        } else if sample.contains(where: { $0.contains(",") || $0.contains("，") }) {
            delimiter = ","
        } else if sample.contains(where: { $0.contains(";") }) {
            delimiter = ";"
        } else {
            delimiter = nil
        }
        return lines.map { line in
            guard let d = delimiter else {
                return line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            }
            let normalized = d == "," ? line.replacingOccurrences(of: "，", with: ",") : line
            // 网页里表格和普通文字混在一起时，没有分隔符的行按空格拆
            if !normalized.contains(d) {
                return line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            }
            return splitCSVLine(normalized, delimiter: d).map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    static func splitCSVLine(_ line: String, delimiter: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { current.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == delimiter {
                cells.append(current); current = ""
            } else {
                current.append(ch)
            }
            i += 1
        }
        cells.append(current)
        return cells
    }

    private static let shiftHeaders = ["班次", "班别", "班型", "排班", "值班", "shift", "type", "类型", "状态"]
    private static let nameHeaders = ["姓名", "名字", "员工", "人员", "值班人", "name", "employee", "staff"]

    /// 不可能是班次的单元格：空、纯星期、纯数字/时间。
    private func isFiller(_ cell: String) -> Bool {
        let c = DateTokenParser.cleaned(cell)
        if c.isEmpty { return true }
        return c.allSatisfy { $0.isNumber || ":-~.：至 ".contains($0) }
    }

    func parseTable(_ rows: [[String]]) throws -> ParseResult {
        if let r = try parseMatrix(rows) { return r }
        if let r = parseColumn(rows) { return r }
        if let r = parseRoster(rows) { return r }
        return try parseList(rows)
    }

    /// 表头一行是日期，下面每行一个人：
    ///   姓名, 10/1, 10/2, …
    ///   张伟, 白,   夜,   …
    private func parseMatrix(_ rows: [[String]]) throws -> ParseResult? {
        for (h, header) in rows.prefix(10).enumerated() {
            guard let columns = dateColumns(header, context: rows.prefix(h + 1).flatMap { $0 }.joined(separator: " ")) else { continue }
            let body = rows[(h + 1)...]
            let candidates = body.filter { row in columns.keys.contains { $0 < row.count && !DateTokenParser.cleaned(row[$0]).isEmpty } }
            let mine: [String]
            if let row = body.first(where: { row in row.contains(where: isMe) }) {
                mine = row
            } else if candidates.count == 1 {
                mine = candidates[0]
            } else if candidates.isEmpty {
                continue
            } else {
                throw ScheduleParseError.nameNotFound(aliases)
            }
            var entries: [DayKey: String] = [:]
            for (col, day) in columns where col < mine.count && !isMe(mine[col]) {
                Self.add(mine[col], to: day, in: &entries)
            }
            return ParseResult(entries: entries, format: .matrix)
        }
        return nil
    }

    /// 找出表头里的日期列。支持完整日期，或只写 1…31 的日号（年月取自表格标题或参考日期，跨月自动进位）。
    private func dateColumns(_ header: [String], context: String) -> [Int: DayKey]? {
        var full: [Int: DayKey] = [:]
        for (i, cell) in header.enumerated() {
            if let d = dates.parse(cell) { full[i] = d }
        }
        // 日期要占表头的大多数，避免把 "10/11 休 10/12 白 10/13 夜" 这种一行多条的列表当成表头
        let nonEmpty = header.filter { !DateTokenParser.cleaned($0).isEmpty }.count
        if full.count >= 3 && full.count * 2 > nonEmpty { return full }
        if full.count >= 3 { return nil }

        let ym = DateTokenParser.findYearMonth(in: context) ?? (reference.year, reference.month)
        var year = ym.year, month = ym.month
        var lastDay = 0
        var dayOnly: [Int: DayKey] = [:]
        for (i, cell) in header.enumerated() {
            let c = DateTokenParser.cleaned(cell)
            guard let n = Int(c.hasSuffix("日") ? String(c.dropLast()) : c), (1...31).contains(n) else { continue }
            if n < lastDay {
                month += 1
                if month > 12 { month = 1; year += 1 }
            }
            lastDay = n
            if let d = dates.parseDayOnly(c, year: year, month: month) { dayOnly[i] = d }
        }
        return dayOnly.count >= 7 ? dayOnly : nil
    }

    /// 表头是人名，第一列是日期：
    ///   日期,  张三, 张伟, 李四
    ///   10/1,  白,   夜,   休
    private func parseColumn(_ rows: [[String]]) -> ParseResult? {
        for (h, header) in rows.prefix(10).enumerated() {
            // 表头要紧挨着日期行，人名格子要短（排除表格上方提到名字的通知文字）
            guard h + 1 < rows.count, rows[h + 1].contains(where: { dates.parse($0) != nil }),
                  header.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count >= 2,
                  let col = header.firstIndex(where: { isMe($0) && $0.count <= 16 }),
                  !header.contains(where: { dates.parse($0) != nil }) else { continue }
            var entries: [DayKey: String] = [:]
            for row in rows[(h + 1)...] where col < row.count {
                guard let day = row.lazy.compactMap({ self.dates.parse($0) }).first, dates.parse(row[col]) == nil else { continue }
                Self.add(row[col], to: day, in: &entries)
            }
            if !entries.isEmpty { return ParseResult(entries: entries, format: .column) }
        }
        return nil
    }

    /// 每行一天，每列一个岗位，单元格里是这个岗位当天的人（可以有多个）：
    ///   日期,       星期, 遥测,      调度,                 组A,      组B
    ///   2026-10-05, 周一, 刘洋(5), 陈静(3),            张伟(1),  杨帆(5)
    ///   2026-10-08, 周四, 马超(1),   陈静(3) 朱丽(3),    郭峰,   杨帆(5)
    /// 名字出现在哪一列，那一列的表头就是自己当天的岗位；同一天多个岗位用 "+" 连接。
    private func parseRoster(_ rows: [[String]]) -> ParseResult? {
        guard let firstDated = rows.firstIndex(where: { $0.contains { dates.parse($0) != nil } }) else { return nil }
        // 表头 = 第一行日期之前、最近的一行（至少 3 个格子、没有日期）
        guard let h = rows[..<firstDated].lastIndex(where: { row in
            row.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count >= 3
        }) else { return nil }
        let header = rows[h]
        // "日期, 姓名, 班次" 这种是普通列表，不是岗位表
        if header.contains(where: { cell in Self.nameHeaders.contains { Self.normalize(cell).contains($0) } }) { return nil }

        var entries: [DayKey: String] = [:]
        for row in rows[firstDated...] {
            guard let dateCol = row.firstIndex(where: { dates.parse($0) != nil }), let day = dates.parse(row[dateCol]) else { continue }
            for (col, cell) in row.enumerated() where col != dateCol && col < header.count && isMe(cell) {
                let post = header[col].trimmingCharacters(in: .whitespaces)
                if !post.isEmpty { Self.add(post, to: day, in: &entries) }
            }
        }
        return entries.isEmpty ? nil : ParseResult(entries: entries, format: .roster)
    }

    /// 每行一条记录：
    ///   2026-10-09 白班
    ///   10/10, 张伟, 夜班
    ///   10月11日 周六 休息   10月12日 周日 白班   （一行多个也可以）
    private func parseList(_ rows: [[String]]) throws -> ParseResult {
        let headerIndex = rows.prefix(3).firstIndex { row in
            row.contains { cell in Self.shiftHeaders.contains(where: { Self.normalize(cell).contains($0) }) }
                && !row.contains { dates.parse($0) != nil }
        }
        let header = headerIndex.map { rows[$0] }
        let shiftCol = header?.firstIndex { cell in Self.shiftHeaders.contains(where: { Self.normalize(cell).contains($0) }) }
        let nameCol = header?.firstIndex { cell in Self.nameHeaders.contains(where: { Self.normalize(cell).contains($0) }) }

        let body = rows.enumerated().filter { $0.offset != headerIndex }.map(\.element)
        let anyMine = body.contains { $0.contains(where: isMe) }
        if nameCol != nil && !anyMine && !aliases.isEmpty {
            throw ScheduleParseError.nameNotFound(aliases)
        }

        var entries: [DayKey: String] = [:]
        // 由「日期一行、内容下一行」配对得到的日子；之后出现同一天的更准确内容时覆盖它
        var fromNextLine = Set<DayKey>()
        for (r, row) in body.enumerated() {
            if anyMine && !row.contains(where: isMe) { continue }
            let dated = row.enumerated().compactMap { i, cell in dates.parse(cell).map { (i, $0) } }
            if dated.count == 1, let col = shiftCol, col < row.count, col != dated[0].0 {
                Self.add(removingAliases(row[col]), to: dated[0].1, in: &entries)
                continue
            }
            for (n, (i, day)) in dated.enumerated() {
                let end = n + 1 < dated.count ? dated[n + 1].0 : row.count
                let value = row[(i + 1)..<end]
                    .enumerated()
                    .first { offset, cell in
                        let col = i + 1 + offset
                        return col != nameCol && !isFiller(cell) && !removingAliases(cell).isEmpty
                    }
                    .map { removingAliases($0.element) }
                if let value {
                    if fromNextLine.remove(day) != nil { entries[day] = nil }
                    Self.add(value, to: day, in: &entries)
                } else if dated.count == 1, r + 1 < body.count,
                          !body[r + 1].contains(where: { dates.parse($0) != nil }) {
                    // 手机网页的卡片：一行 "2026-10-05 周一"，下一行 "组A、组E"
                    let parts = body[r + 1].filter { !isFiller($0) }.map(removingAliases).filter { !$0.isEmpty }
                    let text = parts.joined(separator: " ")
                    if !text.isEmpty && text.count <= 40 {
                        entries[day] = text
                        fromNextLine.insert(day)
                    }
                }
            }
        }
        if entries.isEmpty { throw ScheduleParseError.noDates }
        return ParseResult(entries: entries, format: .list)
    }

    // MARK: - JSON

    private static let dateKeys = ["date", "day", "日期", "start", "dtstart", "startdate", "start_date", "starttime", "start_time"]
    private static let shiftKeys = ["shift", "班次", "班别", "shiftname", "shift_name", "type", "title", "summary", "label", "value"]
    private static let personKeys = ["name", "姓名", "employee", "person", "user", "staff", "人员", "username", "worker"]

    func parseJSON(_ json: Any) throws -> ParseResult {
        if let dict = json as? [String: Any] {
            // {"2026-10-09": "白班", …}
            var entries: [DayKey: String] = [:]
            for (k, v) in dict {
                if let day = dates.parse(k), let s = v as? String { Self.add(s, to: day, in: &entries) }
            }
            if !entries.isEmpty { return ParseResult(entries: entries, format: .json) }
            // {"data": [...]} 之类的外层包装
            for v in dict.values where v is [Any] || v is [String: Any] {
                if let r = try? parseJSON(v), !r.entries.isEmpty { return r }
            }
            throw ScheduleParseError.noDates
        }
        guard let array = json as? [Any] else { throw ScheduleParseError.noDates }

        if let rows = array as? [[Any]] {
            return try parseTable(rows.map { $0.map { "\($0)" } })
        }

        let objects = array.compactMap { $0 as? [String: Any] }.map { obj in
            Dictionary(obj.map { (Self.normalize($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
        }
        func string(_ obj: [String: Any], _ keys: [String]) -> String? {
            for k in keys { if let v = obj[k] { return v is NSNull ? nil : "\(v)" } }
            return nil
        }
        let anyMine = objects.contains { obj in string(obj, Self.personKeys).map(isMe) ?? false }
        var entries: [DayKey: String] = [:]
        for obj in objects {
            guard let dateText = string(obj, Self.dateKeys), let day = dates.parse(dateText) else { continue }
            if anyMine && !(string(obj, Self.personKeys).map(isMe) ?? false) { continue }
            guard let shift = string(obj, Self.shiftKeys) else { continue }
            let stripped = removingAliases(shift)
            Self.add(stripped.isEmpty ? shift : stripped, to: day, in: &entries)
        }
        if objects.contains(where: { string($0, Self.personKeys) != nil }) && !anyMine && !aliases.isEmpty && entries.isEmpty {
            throw ScheduleParseError.nameNotFound(aliases)
        }
        return ParseResult(entries: entries, format: .json)
    }

    // MARK: - ICS 日历订阅

    struct ICSEvent {
        var start: DayKey?
        var allDay = false
        var endExclusive: DayKey?
        var summary = ""
        var description = ""
    }

    func parseICS(_ text: String) throws -> ParseResult {
        // RFC 5545 折行：以空格或 Tab 开头的行接到上一行
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            if let first = line.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else if !line.isEmpty {
                lines.append(line)
            }
        }

        var events: [ICSEvent] = []
        var current: ICSEvent?
        for line in lines {
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" { current = ICSEvent(); continue }
            if upper == "END:VEVENT" { if let e = current { events.append(e) }; current = nil; continue }
            guard current != nil, let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].uppercased()
            let value = String(line[line.index(after: colon)...])
            let prop = name.split(separator: ";").first.map(String.init) ?? ""
            switch prop {
            case "DTSTART":
                current?.start = icsDay(value)
                current?.allDay = name.contains("VALUE=DATE") && !name.contains("DATE-TIME") || !value.contains("T")
            case "DTEND":
                current?.endExclusive = icsDay(value)
            case "SUMMARY": current?.summary = Self.unescapeICS(value)
            case "DESCRIPTION": current?.description = Self.unescapeICS(value)
            default: break
            }
        }

        let anyMine = events.contains { isMe($0.summary) || isMe($0.description) }
        var entries: [DayKey: String] = [:]
        for e in events {
            guard let start = e.start else { continue }
            if anyMine && !(isMe(e.summary) || isMe(e.description)) { continue }
            let stripped = removingAliases(e.summary)
            let value = stripped.isEmpty ? e.summary : stripped
            // 全天事件可能跨多天（DTEND 不含当天），最多展开 31 天；
            // 带时间的事件（如 20:00–次日 08:00 的夜班）只算开始那天
            var day = start
            var count = 0
            repeat {
                Self.add(value, to: day, in: &entries)
                day = day.adding(days: 1, calendar: calendar)
                count += 1
            } while e.allDay && (e.endExclusive.map { day < $0 } ?? false) && count < 31
        }
        return ParseResult(entries: entries, format: .ics)
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    /// 取 ICS 时间值的日期；UTC 时间（以 Z 结尾）换算到本地时区。
    private func icsDay(_ value: String) -> DayKey? {
        let v = value.trimmingCharacters(in: .whitespaces)
        let digits = v.prefix(8)
        guard digits.count == 8, let y = Int(digits.prefix(4)), let m = Int(digits.dropFirst(4).prefix(2)),
              let d = Int(digits.suffix(2)), DayKey.isValid(year: y, month: m, day: d) else { return nil }
        guard v.hasSuffix("Z"), let t = v.firstIndex(of: "T") else { return DayKey(year: y, month: m, day: d) }

        let time = v[v.index(after: t)...]
        let hh = Int(time.prefix(2)) ?? 0, mm = Int(time.dropFirst(2).prefix(2)) ?? 0
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: y, month: m, day: d, hour: hh, minute: mm))!
        return DayKey(date: date, calendar: calendar)
    }

    static func unescapeICS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\N", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespaces)
    }
}
