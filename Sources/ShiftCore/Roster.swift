import Foundation

/// 全员排班：姓名 → 日期 → 岗位（如「组D」，一天多个用 + 连接）。
public typealias Roster = [String: [DayKey: String]]

/// 从网页表格或接口数据里读出所有人的排班，用于「搜索成员」。
public enum RosterExtractor {
    private static let suffix = try! NSRegularExpression(pattern: #"[（(][^)）]*[)）]"#)
    /// 2–5 个汉字，或者带间隔号的少数民族名字（阿依古丽·买买提）
    private static let chineseName = try! NSRegularExpression(
        pattern: #"^(?:[\x{4e00}-\x{9fa5}]{2,5}|[\x{4e00}-\x{9fa5}]{1,8}(?:[·・•][\x{4e00}-\x{9fa5}]{1,10})+)$"#)
    private static let gluedNames = try! NSRegularExpression(pattern: #"^[\x{4e00}-\x{9fa5}]{6,40}$"#)
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
    private static let postWords = ["遥测", "调度", "值班", "交班", "交接", "休息", "调休", "请假", "出差", "加班", "组",
                                    "休", "假", "班"]   // 年假、补休、早班这类

    private static let dayWord = try! NSRegularExpression(
        pattern: #"^(?:(?:周|星期|礼拜)[一二三四五六日天]|今天|明天|昨天|今日)$"#)

    static func looksLikeName(_ s: String) -> Bool {
        // 排除「周一」「今天」这类，但「周天宇」这样的真名字要保留
        guard !s.isEmpty, !uiWords.contains(s),
              dayWord.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) == nil else { return false }
        let r = NSRange(s.startIndex..., in: s)
        return chineseName.firstMatch(in: s, range: r) != nil || latinName.firstMatch(in: s, range: r) != nil
    }

    static func names(inCell cell: String, matcher: ShiftMatcher) -> [String] {
        // 「张三(5)李四(3)」挨在一起：在右括号后面断开
        let spaced = cell.replacingOccurrences(of: ")", with: ") ").replacingOccurrences(of: "）", with: "） ")
        // 空格、换行、各种标点都可能隔开两个人（「休息：张三 李四」「张三|李四」）
        var tokens = spaced.components(separatedBy: CharacterSet(charactersIn: "、,，;；/：:|｜．。")
            .union(.whitespacesAndNewlines))
            .map(cleanName)
            .filter { !$0.isEmpty }
        // 名字常被排版成「王　五」「欧 阳 娜」：一串连着的单字合回名字。
        // 3 个单字是一个三字名；2、4、6 个两两一组；5 个按 2 + 3
        var merged: [String] = []
        var i = 0
        while i < tokens.count {
            guard tokens[i].count == 1 else { merged.append(tokens[i]); i += 1; continue }
            var run: [String] = []
            while i < tokens.count, tokens[i].count == 1 { run.append(tokens[i]); i += 1 }
            var k = 0
            while k < run.count {
                let left = run.count - k
                let size = left == 1 ? 1 : (left == 3 ? 3 : 2)
                merged.append(run[k..<(k + size)].joined())
                k += size
            }
        }
        tokens = merged
        // 6 个字以上的一串汉字可能是几个名字挨在一起：先留着，读完整页后能拆成认识的人就拆开（见 splitJoinedNames）
        return tokens.filter { (looksLikeName($0) || gluedNames.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil)
            && !isPost($0, matcher: matcher) }
    }

    /// 像岗位的词：遥测、调度、组A、值班交班前、休息、调休……（人名不算）
    static func isPost(_ s: String, matcher: ShiftMatcher) -> Bool {
        let t = cleanName(s)
        guard !t.isEmpty, !uiWords.contains(t) else { return false }
        // 单个字的代码（白、夜、早）是岗位；人名至少两个字，不会被单字关键字误判（王建中）
        return matcher.isStrictMatch(t) || postWords.contains { t.contains($0) }
            || (t.count == 1 && matcher.match(t) != nil)
    }

    static func add(_ post: String, for name: String, on day: DayKey, to roster: inout Roster) {
        // 「组A,组E」「组A/组E」拆开，统一用 + 连接
        let parts = post.split(whereSeparator: ShiftMatcher.isSeparator)
        if parts.count > 1 {
            for part in parts { add(String(part), for: name, on: day, to: &roster) }
            return
        }
        let post = post.trimmingCharacters(in: .whitespaces)
        guard !post.isEmpty else { return }
        if let existing = roster[name]?[day] {
            if !existing.components(separatedBy: "+").contains(post) { roster[name]?[day] = existing + "+" + post }
        } else {
            roster[name, default: [:]][day] = post
        }
    }

    private static let nameWithNumber = try! NSRegularExpression(
        pattern: #"([\x{4e00}-\x{9fa5}][\x{4e00}-\x{9fa5}·・•]{1,18})\s*[（(]\s*(\d{1,3})\s*[)）]"#)

    /// 「张三(5)」括号里的数字：还有几天待休。同一个人出现多次时取第一次（当前这一页）。
    public static func restBalances(_ text: String, matcher: ShiftMatcher) -> [String: Int] {
        var result: [String: Int] = [:]
        let ns = text as NSString
        for m in nameWithNumber.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            guard result[name] == nil, looksLikeName(name), !isPost(name, matcher: matcher),
                  // 全角数字「（５）」也认
                  let n = Int(ns.substring(with: m.range(at: 2)).applyingTransform(.fullwidthToHalfwidth, reverse: false)
                              ?? ns.substring(with: m.range(at: 2))) else { continue }
            result[name] = n
        }
        return result
    }

    /// 这条是不是休息、调休、请假、出差这类（不是具体岗位）
    static func isLeave(_ raw: String, matcher: ShiftMatcher) -> Bool {
        DayRules.isLeaveOrTrip(raw, matcher: matcher)
    }

    /// 把这次读到的全员排班合并进已保存的：读到的日子整天替换（换人、取消的以新数据为准）。
    /// 例外：有的读取方式（手机版页面、数据接口）根本不带「休息」「调休」「请假」这几列，
    /// 这次读到的所有日子里一个休息、请假都没有，就保留之前读到的休息、请假，不能被冲掉。
    /// 只要这次读到的有休息列（哪天有人休息），就整天以新的为准（取消的请假也会去掉）。
    public static func replacingDays(of old: Roster, with new: Roster, matcher: ShiftMatcher) -> Roster {
        RosterMerger.merge(old: old, oldSources: [:], new: new, source: "", at: Date(),
                           carriesLeave: RosterMerger.hasLeave(new, matcher: matcher),
                           carriedKinds: RosterMerger.leaveKinds(new, matcher: matcher), matcher: matcher).roster
    }

    public static func merge(_ new: Roster, into roster: inout Roster) {
        for (name, days) in new {
            roster[name, default: [:]].merge(days) { _, n in n }
        }
    }

    /// 岗位表：表头是岗位（组A、组B、调度…），每行一天，格子里是这个岗位当天的人。
    /// 表头里不像岗位的列（比如表头对错了位置、读到了人名）直接跳过。
    /// strict：只认带「日期」或「星期」列的表头、日期在前两列且格子里只有日期的行
    /// （电脑版页面上方的各组说明里也有「9月20日发射」这类文字，不能当成排班）。
    public static func fromTable(_ text: String, reference: DayKey, matcher: ShiftMatcher, strict: Bool = false) -> Roster {
        let rows = ScheduleParser.splitRows(text)
        let dates = DateTokenParser(reference: reference)
        var roster: Roster = [:]
        var header: [String]?
        func isDateCell(_ cell: String) -> Bool {
            guard dates.parse(cell) != nil else { return false }
            return !strict || cell.trimmingCharacters(in: .whitespaces).count <= 16
        }
        for row in rows {
            guard let dateCol = row.firstIndex(where: isDateCell), !strict || dateCol <= 1,
                  let day = dates.parse(row[dateCol]) else {
                // 没有日期的行：至少 3 个格子的当作表头
                let cells = row.map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.filter({ !$0.isEmpty }).count >= 3 {
                    if !strict || cells.contains(where: { $0.hasPrefix("日期") || $0.hasPrefix("星期") }) {
                        header = row
                    } else if strict {
                        header = nil
                    }
                }
                continue
            }
            guard let header else { continue }
            for (col, cell) in row.enumerated() where col != dateCol && col < header.count {
                let post = header[col].trimmingCharacters(in: .whitespaces)
                guard isPost(post, matcher: matcher) else { continue }
                for name in names(inCell: cell, matcher: matcher) { add(post, for: name, on: day, to: &roster) }
            }
        }
        return splitJoinedNames(roster)
    }

    /// 电脑版「值班查看」：一周一张表，表头「日期 星期 遥测 调度 组A … 休息 调休 加班」，格子里「张三(5)」。
    public static func fromDesktopHTML(_ html: String, reference: DayKey, matcher: ShiftMatcher) -> Roster {
        fromTable(HTMLText.tablesOnly(html), reference: reference, matcher: matcher, strict: true)
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
            // 日期行：日期加上「上一天」「周六」这类短词；夹在长句子里的日期（通知文字）不算
            if let d = cells.lazy.compactMap({ dates.parse($0) }).first,
               cells.count <= 5, cells.allSatisfy({ dates.parse($0) != nil || $0.count <= 4 }) {
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
        return splitJoinedNames(roster)
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
            }.filter { $0.1 > 0 }.max { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 > $1.0 }?.0
            guard let personKey else { continue }
            // 岗位字段：值最像班次的
            let postKey = keys.subtracting([personKey]).map { k -> (String, Int) in
                let values = rows.compactMap { $0[k] }.filter { !$0.isEmpty }
                return (k, values.filter { matcher.match($0) != nil }.count)
            }.filter { $0.1 > 0 }.max { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 > $1.0 }?.0
            guard let postKey else { continue }
            for row in rows {
                guard let day = row[dateKey].flatMap({ JSONScheduleExtractor.day(from: $0, dates: dates) }),
                      let cell = row[personKey],
                      let post = row[postKey], isPost(post, matcher: matcher) else { continue }
                // 一条记录里可能有好几个人（休息「张三,李四」）：每个人都记上
                for name in names(inCell: cell, matcher: matcher) { add(post, for: name, on: day, to: &roster) }
            }
        }
        return splitJoinedNames(roster)
    }

    /// 「我是谁」：网站上「我的分工」（mine）和全员排班里谁的班对得上。至少 5 天对上、八成以上一致，而且明显比别人像才算。
    public static func identify(mine: [DayKey: String], roster: Roster, matcher: ShiftMatcher) -> String? {
        func posts(_ raw: String) -> Set<String> {
            Set((WorkloadCounter.effective(raw, matcher: matcher) ?? "").split(separator: "+").map { matcher.displayName(String($0)) })
        }
        let scored = roster.map { name, days -> (name: String, hits: Int, overlap: Int) in
            var hits = 0, overlap = 0
            for (day, raw) in mine {
                guard let theirs = days[day] else { continue }
                overlap += 1
                if posts(theirs) == posts(raw) { hits += 1 }
            }
            return (name, hits, overlap)
        }.sorted { $0.hits > $1.hits }
        guard let best = scored.first, best.hits >= 5, Double(best.hits) >= Double(best.overlap) * 0.8 else { return nil }
        if scored.count > 1, Double(scored[1].hits) >= Double(best.hits) * 0.7 { return nil }
        return best.name
    }

    /// 几个名字挨在一起没隔开（「张三李四」「张三李四王五」）会被当成一个人：
    /// 能唯一地拆成这次读到（或以前读到过）的几个人，就拆开；拆不开、又太长不像名字的丢掉（多半是一句话）。
    /// known：另外认识的人（合并时加上以前读到过的）
    public static func splitJoinedNames(_ roster: Roster, known extra: Set<String> = []) -> Roster {
        // 单个的人：自己拆不成别人的（从短到长看）
        var base = Set<String>()
        for name in Set(roster.keys).union(extra).filter(looksLikeName).sorted(by: { ($0.count, $0) < ($1.count, $1) }) {
            if segmentations(of: name, using: base) == 0 { base.insert(name) }
        }
        var result = roster
        for (name, days) in roster where !base.contains(name) {
            var parts: [String] = []
            if segmentations(of: name, using: base, first: &parts) == 1 {
                result[name] = nil
                for (day, post) in days {
                    for person in parts {
                        for part in post.split(separator: "+") { add(String(part), for: person, on: day, to: &result) }
                    }
                }
            } else if !looksLikeName(name) {
                result[name] = nil
            }
        }
        return result
    }

    /// 能拆成至少两个 base 里的名字的方法有几种（最多数到 2）
    static func segmentations(of name: String, using base: Set<String>) -> Int {
        var ignored: [String] = []
        return segmentations(of: name, using: base, first: &ignored)
    }

    static func segmentations(of name: String, using base: Set<String>, first: inout [String]) -> Int {
        let chars = Array(name)
        guard chars.count >= 4, !base.isEmpty else { return 0 }
        var found = 0
        var firstPath: [String] = []
        func walk(_ start: Int, _ path: [String]) {
            guard found < 2 else { return }
            if start == chars.count {
                if path.count >= 2 { found += 1; if found == 1 { firstPath = path } }
                return
            }
            for end in stride(from: start + 2, through: min(chars.count, start + 12), by: 1) {
                let piece = String(chars[start..<end])
                if base.contains(piece) && piece != name { walk(end, path + [piece]) }
            }
        }
        walk(0, [])
        first = firstPath
        return found
    }
}

/// 各组的工作内容（电脑版网页上「组E　●当日应急……」这样的说明）。
public enum GroupNotes {
    private static let groupName = try! NSRegularExpression(pattern: #"^组\s*[A-Za-z0-9一二三四五六七八九十]{1,2}$"#)
    static let minLength = 8
    /// 电脑版表格右边那列（注意事项）存在这一行后面，和要做的事分开
    public static let cautionMarker = "【注意事项】"

    /// 只是一串人名（「何强(4)、郭峰(2)」「组A 何强 郭峰」）：手机版「值班查看」里组别后面跟的是谁，不是这个组干什么
    public static func isNameList(_ text: String, matcher: ShiftMatcher) -> Bool {
        let names = RosterExtractor.names(inCell: text, matcher: matcher)
        guard !names.isEmpty else { return false }
        var rest = text.replacingOccurrences(of: #"[（(]\s*-?\d+\s*[)）]"#, with: "", options: .regularExpression)
        for n in names.sorted(by: { $0.count > $1.count }) { rest = rest.replacingOccurrences(of: n, with: "") }
        rest = rest.replacingOccurrences(of: #"组\s*[A-Ea-e]|[\s、,，;；:：|｜/.。·]"#, with: "", options: .regularExpression)
        return rest.count < 4
    }

    /// 要做的事、注意事项分开（没有注意事项时 caution 为 nil）
    public static func split(_ note: String) -> (work: String, caution: String?) {
        guard let r = note.range(of: cautionMarker) else { return (note, nil) }
        let work = note[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let caution = note[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (work, caution.isEmpty ? nil : caution)
    }

    /// 显示用：一条一行。网站上用「●」隔开的拆开（前面加「•」），句号后面、空格后面的「2.」「②」这类编号另起一行；
    /// 「08/10」「9.5」这种不拆
    public static func displayLines(_ text: String) -> [String] {
        var t = text.replacingOccurrences(of: #"\s*[●•]+\s*"#, with: "\n• ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<=[。；;！!])\s*(?=\d{1,2}[.．、](?!\d)|[①-⑳])"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[ \t]+(?=\d{1,2}[.．、](?!\d)|[①-⑳])"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?<=\S)(?=[①-⑳])"#, with: "\n", options: .regularExpression)
        return t.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "•" }
    }

    static func isGroup(_ s: String) -> Bool {
        let t = s.halfwidthAlnum.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "：:")))
        return groupName.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }

    static func normalizeGroup(_ s: String) -> String {
        s.halfwidthAlnum.filter { !$0.isWhitespace && $0 != "：" && $0 != ":" }.uppercased()
    }

    /// 表格文字：一行开头是「组E」，后面的格子是说明；或者「组E」单独一行，下一行是说明。
    public static func fromText(_ text: String, reference: DayKey,
                                matcher: ShiftMatcher = ShiftMatcher(types: ShiftType.defaults)) -> [String: String] {
        let rows = ScheduleParser.splitRows(text)
        let dates = DateTokenParser(reference: reference)
        var notes: [String: String] = [:]
        // 一串人名（手机版「值班查看」里这组是谁）不是说明
        func isNote(_ s: String) -> Bool {
            s.count >= minLength && dates.parse(s) == nil && !isGroup(s) && !isNameList(s, matcher: matcher)
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
            var cells = HTMLText.captures(#"<t[dh]\b[^>]*>([\s\S]*?)</t[dh]\s*>"#, in: row).map(clean)
            // 第一个格子是「组A」，或者「组A」后面换行接着说明
            if let head = cells.first?.components(separatedBy: "\n"), head.count > 1, isGroup(head[0]) {
                cells[0] = head[0]
                cells.insert(head.dropFirst().joined(separator: "\n"), at: 1)
            }
            guard let first = cells.first, isGroup(first) else { continue }
            // 第二格是要做的事，后面的格子是注意事项（存在「【注意事项】」后面，显示时分开）
            let work = cells.count > 1 ? cells[1] : ""
            let caution = cells.dropFirst(2).filter { !$0.isEmpty }.joined(separator: "\n")
            let note = ([work] + (caution.isEmpty ? [] : [cautionMarker, caution])).filter { !$0.isEmpty }.joined(separator: "\n")
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
