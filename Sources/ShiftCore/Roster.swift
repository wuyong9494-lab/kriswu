import Foundation

/// 全员排班：姓名 → 日期 → 岗位（如「组D」，一天多个用 + 连接）。
public typealias Roster = [String: [DayKey: String]]

/// 从网页表格或接口数据里读出所有人的排班，用于「搜索成员」。
public enum RosterExtractor {
    private static let suffix = try! NSRegularExpression(pattern: #"[（(][^)）]*[)）]"#)
    private static let chineseName = try! NSRegularExpression(pattern: #"^[\x{4e00}-\x{9fa5}·]{2,5}$"#)
    private static let latinName = try! NSRegularExpression(pattern: #"^[A-Za-z][A-Za-z .'-]{1,24}$"#)

    /// 「张伟(1)」→「张伟」
    public static func cleanName(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        return suffix.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// 网页上的按钮、分区标题，不是人名
    private static let uiWords: Set<String> = [
        "上一天", "下一天", "我的分工", "值班查看", "排班系统", "值班管理系统", "基础分工", "组别分工",
        "交班与休息", "其他", "今天", "明天", "无分工", "暂无", "无",
    ]

    /// 常见岗位名：即使「班次类型」里没有，也当作岗位
    private static let postWords = ["遥测", "调度", "值班", "交班", "休息", "调休", "请假", "出差", "加班", "组"]

    static func looksLikeName(_ s: String) -> Bool {
        guard !s.isEmpty, !uiWords.contains(s), DateTokenParser.cleaned(s) == s else { return false }   // 排除「周一」这类
        let r = NSRange(s.startIndex..., in: s)
        return chineseName.firstMatch(in: s, range: r) != nil || latinName.firstMatch(in: s, range: r) != nil
    }

    static func names(inCell cell: String, matcher: ShiftMatcher) -> [String] {
        cell.components(separatedBy: CharacterSet(charactersIn: " 、,，;；/\t"))
            .map(cleanName)
            .filter { looksLikeName($0) && !isPost($0, matcher: matcher) }
    }

    /// 像岗位的词：遥测、调度、组A、值班交班前、休息、调休……（人名不算）
    static func isPost(_ s: String, matcher: ShiftMatcher) -> Bool {
        let t = cleanName(s)
        guard !t.isEmpty, !uiWords.contains(t) else { return false }
        return matcher.match(t) != nil || postWords.contains { t.contains($0) }
    }

    static func add(_ post: String, for name: String, on day: DayKey, to roster: inout Roster) {
        let post = post.trimmingCharacters(in: .whitespaces)
        guard !post.isEmpty else { return }
        if let existing = roster[name]?[day] {
            if !existing.components(separatedBy: "+").contains(post) { roster[name]?[day] = existing + "+" + post }
        } else {
            roster[name, default: [:]][day] = post
        }
    }

    public static func merge(_ new: Roster, into roster: inout Roster) {
        for (name, days) in new {
            roster[name, default: [:]].merge(days) { _, n in n }
        }
    }

    /// 岗位表：表头是岗位（组A、组B、调度…），每行一天，格子里是这个岗位当天的人。
    /// 表头里不像岗位的列（比如表头对错了位置、读到了人名）直接跳过。
    public static func fromTable(_ text: String, reference: DayKey, matcher: ShiftMatcher) -> Roster {
        let rows = ScheduleParser.splitRows(text)
        let dates = DateTokenParser(reference: reference)
        var roster: Roster = [:]
        var header: [String]?
        for row in rows {
            guard let dateCol = row.firstIndex(where: { dates.parse($0) != nil }), let day = dates.parse(row[dateCol]) else {
                // 没有日期的行：至少 3 个格子的当作表头
                if row.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count >= 3 { header = row }
                continue
            }
            guard let header else { continue }
            for (col, cell) in row.enumerated() where col != dateCol && col < header.count {
                let post = header[col].trimmingCharacters(in: .whitespaces)
                guard isPost(post, matcher: matcher) else { continue }
                for name in names(inCell: cell, matcher: matcher) { add(post, for: name, on: day, to: &roster) }
            }
        }
        return roster
    }

    /// 卡片式页面（手机版「值班查看」）：一行日期，下面每行「岗位 人名 人名…」，
    /// 或者岗位单独一行、人名紧接在下一行（多个人用「、」隔开）。
    public static func fromCards(_ text: String, reference: DayKey, matcher: ShiftMatcher) -> Roster {
        let rows = ScheduleParser.splitRows(text)
        let dates = DateTokenParser(reference: reference)
        var roster: Roster = [:]
        var day: DayKey?
        var pendingPost: String?
        var pendingRow = -1
        for (index, row) in rows.enumerated() {
            let cells = row.flatMap { $0.components(separatedBy: CharacterSet(charactersIn: "：:")) }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if let d = cells.lazy.compactMap({ dates.parse($0) }).first {
                day = d
                pendingPost = nil
                continue
            }
            guard let day, let first = cells.first else { continue }
            if isPost(first, matcher: matcher) {
                let found = cells.dropFirst().flatMap { names(inCell: $0, matcher: matcher) }
                if found.isEmpty {
                    pendingPost = cleanName(first)
                    pendingRow = index
                } else {
                    for name in found { add(cleanName(first), for: name, on: day, to: &roster) }
                    pendingPost = nil
                }
            } else if let post = pendingPost, index == pendingRow + 1 {
                // 只认岗位下面紧挨着的一行；空岗位（请假、出差…）后面的按钮文字不会被当成人名
                for name in cells.flatMap({ names(inCell: $0, matcher: matcher) }) { add(post, for: name, on: day, to: &roster) }
                pendingPost = nil
            } else {
                pendingPost = nil
            }
        }
        return roster
    }

    /// 接口数据：每条记录有日期、人名、岗位三个字段（字段名不限）。
    public static func fromJSON(_ text: String, reference: DayKey, matcher: ShiftMatcher) -> Roster {
        guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first, first == "{" || first == "[",
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return [:] }
        let dates = DateTokenParser(reference: reference)
        var roster: Roster = [:]
        for rows in JSONScheduleExtractor.tables(in: json) {
            guard let dateKey = JSONScheduleExtractor.dateKey(in: rows, dates: dates) else { continue }
            let keys = Set(rows.flatMap(\.keys)).subtracting([dateKey])
            // 人名字段：大多数值像人名，而且有好几个不同的人
            let personKey = keys.map { k -> (String, Int) in
                let values = rows.compactMap { $0[k] }.map(cleanName)
                let names = values.filter(looksLikeName)
                return (k, names.count * 2 >= max(values.count, 1) && Set(names).count >= 3 ? names.count : 0)
            }.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
            guard let personKey else { continue }
            // 岗位字段：值最像班次的
            let postKey = keys.subtracting([personKey]).map { k -> (String, Int) in
                let values = rows.compactMap { $0[k] }.filter { !$0.isEmpty }
                return (k, values.filter { matcher.match($0) != nil }.count)
            }.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
            guard let postKey else { continue }
            for row in rows {
                guard let day = row[dateKey].flatMap({ JSONScheduleExtractor.day(from: $0, dates: dates) }),
                      let name = row[personKey].map(cleanName), looksLikeName(name), !isPost(name, matcher: matcher),
                      let post = row[postKey], isPost(post, matcher: matcher) else { continue }
                add(post, for: name, on: day, to: &roster)
            }
        }
        return roster
    }
}

/// 各组的工作内容（电脑版网页上「组E　●当日应急……」这样的说明）。
public enum GroupNotes {
    private static let groupName = try! NSRegularExpression(pattern: #"^组\s*[A-Za-z0-9一二三四五六七八九十]{1,2}$"#)
    static let minLength = 8

    static func isGroup(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return groupName.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }

    static func normalizeGroup(_ s: String) -> String {
        s.filter { !$0.isWhitespace }.uppercased()
    }

    /// 表格文字：一行开头是「组E」，后面的格子是说明；或者「组E」单独一行，下一行是说明。
    public static func fromText(_ text: String, reference: DayKey) -> [String: String] {
        let rows = ScheduleParser.splitRows(text)
        let dates = DateTokenParser(reference: reference)
        var notes: [String: String] = [:]
        func isNote(_ s: String) -> Bool {
            s.count >= minLength && dates.parse(s) == nil && !isGroup(s)
        }
        for (i, row) in rows.enumerated() {
            guard let first = row.first, isGroup(first) else { continue }
            var note = row.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
            if note.isEmpty, i + 1 < rows.count, !rows[i + 1].contains(where: { dates.parse($0) != nil }) {
                note = rows[i + 1].joined(separator: " ")
            }
            if isNote(note) { notes[normalizeGroup(first)] = note }
        }
        return notes
    }

    /// 电脑版「值班查看」页面：上方「组A｜要做的事｜注意事项」那一块。
    /// 保留单元格里的换行，去掉划了删除线的内容（已经不做的星）；
    /// 不是表格时，按「组A」单独一行、下面几行是说明来读。
    public static func fromDesktopHTML(_ html: String) -> [String: String] {
        var s = html
        func replace(_ pattern: String, _ with: String) {
            s = s.replacingOccurrences(of: pattern, with: with, options: [.regularExpression, .caseInsensitive])
        }
        replace(#"<(script|style|noscript|template)\b[^>]*>[\s\S]*?</\1\s*>"#, " ")
        replace(#"<(del|s|strike)\b[^>]*>[\s\S]*?</\1\s*>"#, " ")
        replace(#"<(span|font|b|i|em|strong)\b[^>]*line-through[^>]*>[^<]*</\1\s*>"#, " ")
        replace(#"\s+"#, " ")
        replace(#"<br\s*/?>|</(p|div|li|h[1-6])\s*>"#, "\n")

        func clean(_ fragment: String) -> String {
            let text = HTMLText.decodeEntities(fragment.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression))
            return text.components(separatedBy: "\n")
                .map { $0.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }

        var notes: [String: String] = [:]
        for row in HTMLText.captures(#"<tr\b[^>]*>([\s\S]*?)</tr\s*>"#, in: s) {
            let cells = HTMLText.captures(#"<t[dh]\b[^>]*>([\s\S]*?)</t[dh]\s*>"#, in: row).map(clean)
            guard let first = cells.first, isGroup(first) else { continue }
            let note = cells.dropFirst().filter { !$0.isEmpty }.joined(separator: "\n")
            if note.count >= minLength { notes[normalizeGroup(first)] = note }
        }
        if !notes.isEmpty { return notes }

        // 不是表格：「组A」单独一行，后面到下一个「组X」为止
        let lines = clean(s).components(separatedBy: "\n")
        var current: String?
        var body: [String] = []
        func flush() {
            if let g = current, body.joined().count >= minLength { notes[normalizeGroup(g)] = body.joined(separator: "\n") }
            body = []
        }
        for line in lines {
            if isGroup(line) {
                flush()
                current = line
            } else if current != nil {
                // 到了排班表（日期、星期那一行）就结束
                if line.hasPrefix("日期") || line.range(of: #"^\d{4}-\d{1,2}-\d{1,2}"#, options: .regularExpression) != nil {
                    flush()
                    current = nil
                } else if body.count < 20 {
                    body.append(line)
                }
            }
        }
        flush()
        return notes
    }

    private static let pasteHeader = try! NSRegularExpression(
        pattern: #"^(组\s*[A-Za-z0-9一二三四五六七八九十]{1,2})\s*(?:[：:]\s*(.*))?$"#)

    /// 自己粘贴的说明：「组A：……」开始一个组，之后的行都属于这个组，直到下一个「组X：」。
    public static func fromPaste(_ text: String) -> [String: String] {
        var notes: [String: String] = [:]
        var current: String?
        var lines: [String] = []
        func flush() {
            if let g = current {
                let note = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty { notes[normalizeGroup(g)] = note }
            }
            lines = []
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let range = NSRange(line.startIndex..., in: line)
            if let m = pasteHeader.firstMatch(in: line, range: range), let g = Range(m.range(at: 1), in: line) {
                flush()
                current = String(line[g])
                if let r = Range(m.range(at: 2), in: line), !line[r].isEmpty { lines.append(String(line[r])) }
            } else if current != nil, !line.isEmpty {
                lines.append(line)
            }
        }
        flush()
        return notes
    }

    /// 接口数据：某个字段是「组E」，另一个字段是较长的说明文字。
    public static func fromJSON(_ text: String) -> [String: String] {
        guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first, first == "{" || first == "[",
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return [:] }
        var notes: [String: String] = [:]
        for rows in JSONScheduleExtractor.tables(in: json) {
            let keys = Set(rows.flatMap(\.keys))
            guard let groupKey = keys.first(where: { k in
                let values = rows.compactMap { $0[k] }
                return !values.isEmpty && values.filter(isGroup).count * 2 > values.count
            }) else { continue }
            // 说明字段：平均最长的文字字段
            let noteKey = keys.subtracting([groupKey]).map { k -> (String, Int) in
                let values = rows.compactMap { $0[k] }
                return (k, values.isEmpty ? 0 : values.map(\.count).reduce(0, +) / values.count)
            }.filter { $0.1 >= minLength }.max { $0.1 < $1.1 }?.0
            guard let noteKey else { continue }
            for row in rows {
                guard let g = row[groupKey], isGroup(g), let n = row[noteKey], n.count >= minLength else { continue }
                notes[normalizeGroup(g)] = n.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return notes
    }
}
