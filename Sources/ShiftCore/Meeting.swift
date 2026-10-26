import Foundation

/// 周会文档里各组提的问题：每周导入一次，逐条对比上一周，看哪些解决了、哪些还挂着。
public struct MeetingIssue: Codable, Equatable, Hashable, Identifiable {
    public enum Status: String, Codable, CaseIterable {
        case open = "未解决"
        case resolved = "已解决"
        /// 上一周还在提、这一周文档里没有了：多半解决了，等自己确认
        case quiet = "没再提"
    }

    public var id: String
    public var group: String
    /// 最近一次文档里的写法
    public var text: String
    /// 第一次、最近一次出现在哪一周（那周的周一）
    public var firstWeek: DayKey
    public var lastWeek: DayKey
    public var status: Status
    public var resolvedWeek: DayKey?
    /// 自己手动改过状态
    public var manual: Bool
    /// 文档里最近一次的补充：这一行属于什么（「本周问题」）、负责人、进展
    public var detail: String?
    /// 在表格里的位置和导入时那几格的原文（从表格导入的才有）：改了写回金山文档时用
    public var source: MeetingSource?

    public init(id: String, group: String, text: String, firstWeek: DayKey, lastWeek: DayKey,
                status: Status, resolvedWeek: DayKey? = nil, manual: Bool = false, detail: String? = nil,
                source: MeetingSource? = nil) {
        self.id = id
        self.group = group
        self.text = text
        self.firstWeek = firstWeek
        self.lastWeek = lastWeek
        self.status = status
        self.resolvedWeek = resolvedWeek
        self.manual = manual
        self.detail = detail
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        group = try c.decode(String.self, forKey: .group)
        text = try c.decode(String.self, forKey: .text)
        firstWeek = try c.decode(DayKey.self, forKey: .firstWeek)
        lastWeek = try c.decodeIfPresent(DayKey.self, forKey: .lastWeek) ?? firstWeek
        status = (try? c.decodeIfPresent(Status.self, forKey: .status)) ?? .open
        resolvedWeek = try? c.decodeIfPresent(DayKey.self, forKey: .resolvedWeek)
        manual = (try? c.decodeIfPresent(Bool.self, forKey: .manual)) ?? false
        detail = try? c.decodeIfPresent(String.self, forKey: .detail)
        source = try? c.decodeIfPresent(MeetingSource.self, forKey: .source)
    }

    /// 从第一次提出到 week 挂了几周（同一周提出算第 1 周）
    public func weeks(through week: DayKey, calendar: Calendar = .dayMath) -> Int {
        let end = status == .resolved ? (resolvedWeek ?? lastWeek) : week
        let days = calendar.dateComponents([.day], from: firstWeek.date(calendar: calendar, hour: 12),
                                           to: end.date(calendar: calendar, hour: 12)).day ?? 0
        return max(1, days / 7 + 1)
    }

    // 补充说明是「本周问题 · 负责人：甲、乙 · 进展：进行中」这样拼起来的，拆开来按人筛、单独显示

    /// 负责人（「甲、乙」拆成两个人）
    public var owners: [String] {
        guard let raw = detailPart("负责人：") else { return [] }
        return raw.split { "、,，/／;； ".contains($0) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 文档里写的进展（「完成情况」那一列对上这一条的）或状态
    public var progress: String? { detailPart("进展：") ?? detailPart("状态：") }

    /// 这一条在文档里属于哪一项（「本周问题」「上上周问题进展」）
    public var topic: String? {
        guard let first = detail?.components(separatedBy: " · ").first, !first.isEmpty,
              !["负责人：", "进展：", "状态："].contains(where: { first.hasPrefix($0) }) else { return nil }
        return first
    }

    private func detailPart(_ prefix: String) -> String? {
        guard let part = detail?.components(separatedBy: " · ").first(where: { $0.hasPrefix(prefix) }) else { return nil }
        let value = part.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

/// 把周会文档的文字拆成「组 → 问题」
public enum MeetingNotes {
    /// 一条：文字、文档里是不是写了已经解决、补充说明（这一行属于什么、负责人、进展）
    public struct Entry: Equatable {
        public var text: String
        public var done: Bool
        public var detail: String?
        public var source: MeetingSource?
        public init(text: String, done: Bool? = nil, detail: String? = nil, source: MeetingSource? = nil) {
            self.text = text
            self.done = done ?? MeetingTracker.isMarkedDone(text)
            self.detail = detail
            self.source = source
        }
    }

    public struct Section: Equatable {
        public var group: String
        public var entries: [Entry]
        public var items: [String] { entries.map(\.text) }
        public init(group: String, items: [String]) {
            self.group = group
            self.entries = items.map { Entry(text: $0) }
        }
        public init(group: String, entries: [Entry]) {
            self.group = group
            self.entries = entries
        }
    }

    /// 行首的编号、符号：「1.」「1、」「(1)」「（一）」「一、」「①」「•」「-」「#」「【」
    private static let bullet = try! NSRegularExpression(
        pattern: #"^\s*(?:[#>*\-–—•·▪●○◆◇■□√✓]+|[\(（]?[0-9一二三四五六七八九十]{1,3}[\)）\.、．:：]|[①-⑳])\s*"#)
    /// 组名：「组A」「组 B」「A组」「研发组」「测控一组」……（后面可以跟冒号、括号，再接内容）
    private static let header = try! NSRegularExpression(
        pattern: #"^[【\[]?\s*(组\s*[A-Za-z0-9一二三四五六七八九十]{1,3}|[A-Za-z0-9]{1,3}\s*组|[一-龥]{1,6}组)\s*[】\]]?\s*(?:[:：]\s*(.*))?$"#)
    /// 不是组名的「…组」
    private static let notGroups: Set<String> = ["各组", "本组", "每组", "该组", "全组", "分组", "其他组", "其它组", "小组", "各小组", "两组", "几组", "同组"]
    /// 组里的小标题：带这些字的下面是问题
    private static let issueWords = ["问题", "困难", "需协调", "需要协调", "需支持", "需要支持", "待解决", "风险", "隐患", "建议"]
    /// 组里别的小标题（下面不是问题）
    private static let otherHeadings = ["本周工作", "上周工作", "工作总结", "工作情况", "完成情况", "下周计划", "下周工作", "工作计划", "计划", "进展", "总结"]

    /// 没有内容的写法
    private static let emptyWords: Set<String> = ["无", "暂无", "无问题", "没有", "暂无问题", "无。", "/", "-", "—"]

    static func stripBullet(_ line: String) -> String {
        var s = line
        // 编号可能叠着写（「一、1.」）
        for _ in 0..<2 {
            let ns = s as NSString
            guard let m = bullet.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), m.range.length > 0 else { break }
            s = ns.substring(from: m.range.length)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// 「组 a」「A组」→「组A」；其它组名原样
    static func normalizeGroup(_ raw: String) -> String {
        let t = raw.filter { !$0.isWhitespace }
        if t.hasPrefix("组") { return "组" + t.dropFirst().uppercased() }
        if t.hasSuffix("组"), t.dropLast().allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            return "组" + t.dropLast().uppercased()
        }
        return t
    }

    /// 这一行是不是组名（可能带着内容：「组A：设备告警两次」）
    static func groupHeader(_ line: String) -> (group: String, rest: String)? {
        let s = stripBullet(line)
        guard s.count <= 40 else { return nil }
        let ns = s as NSString
        guard let m = header.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let group = normalizeGroup(ns.substring(with: m.range(at: 1)))
        guard !notGroups.contains(group) else { return nil }
        let rest = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces) : ""
        return (group, rest)
    }

    /// 组里的小标题：是问题那一类（isIssue = true）还是别的；rest 是同一行冒号后面跟着的内容。不是小标题返回 nil。
    /// 「存在问题：」「问题」「下周计划」算；「数据处理问题较多」这种长句是问题本身，不算
    static func subheading(_ line: String) -> (isIssue: Bool, rest: String)? {
        let s = stripBullet(line).trimmingCharacters(in: CharacterSet(charactersIn: "【】[] "))
        let head: String, rest: String
        if let r = s.range(of: "[:：]", options: .regularExpression) {
            head = String(s[..<r.lowerBound])
            rest = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            guard s.count <= 6 else { return nil }
            head = s
            rest = ""
        }
        guard !head.isEmpty, head.count <= 8 else { return nil }
        if issueWords.contains(where: head.contains) { return (true, rest) }
        if otherHeadings.contains(where: head.contains) { return (false, rest) }
        return nil
    }

    /// 周会文档的文字：表格（复制出来的格子之间是制表符，第一行有「分组」）按表格读，别的按一行一行读
    public static func parse(_ text: String) -> [Section] {
        if text.contains("\t"), let sections = MeetingTable.sections(MeetingTable.rows(text, separator: "\t")), !sections.isEmpty {
            return sections
        }
        return parseLines(text)
    }

    static func parseLines(_ text: String) -> [Section] {
        struct Draft { var group: String; var all: [String] = []; var issues: [String] = []; var hasIssueHeading = false }
        var drafts: [Draft] = []
        var inIssues = false
        func add(_ raw: String) {
            let item = stripBullet(raw)
            guard !drafts.isEmpty, item.count >= 2, !emptyWords.contains(item) else { return }
            drafts[drafts.count - 1].all.append(item)
            if inIssues { drafts[drafts.count - 1].issues.append(item) }
        }
        func startGroup(_ group: String) {
            if let i = drafts.firstIndex(where: { $0.group == group }) {
                // 同一个组又出现（表格里一组几行）：接着往里加
                drafts.append(drafts.remove(at: i))
            } else {
                drafts.append(Draft(group: group))
            }
            inIssues = false
        }
        let lines = text.replacingOccurrences(of: "\u{200B}", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for line in lines {
            // 表格一行（格子之间是制表符）：第一格是组名的，后面几格合成一条
            let cells = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if cells.count > 1, let h = groupHeader(cells[0]), h.rest.isEmpty {
                startGroup(h.group)
                add(cells.dropFirst().joined(separator: "，"))
                continue
            }
            let flat = cells.joined(separator: "，")
            if let h = groupHeader(flat) {
                startGroup(h.group)
                if !h.rest.isEmpty { add(h.rest) }
                continue
            }
            guard !drafts.isEmpty else { continue }   // 第一个组之前的标题、日期不要
            if let sub = subheading(flat) {
                inIssues = sub.isIssue
                if sub.isIssue { drafts[drafts.count - 1].hasIssueHeading = true }
                if !sub.rest.isEmpty { add(sub.rest) }
                continue
            }
            add(flat)
        }
        // 有「问题」小标题的组只取那下面的；没有的整组都算
        return drafts.compactMap { d in
            let items = d.hasIssueHeading ? d.issues : d.all
            return items.isEmpty ? nil : Section(group: d.group, items: items)
        }
    }
}

/// 一周一周地跟进问题
public enum MeetingTracker {
    private static let doneWords = ["已解决", "已处理", "已完成", "已修复", "已闭环", "已落实", "已关闭", "已协调", "解决完毕", "✅", "☑", "（解决）", "(解决)"]

    /// 文档里写了已经解决
    public static func isMarkedDone(_ text: String) -> Bool { doneWords.contains(where: text.contains) }

    /// 比较用：去掉状态字样、标点、空格
    public static func normalized(_ text: String) -> String {
        var s = text
        for w in doneWords + ["未解决", "待解决", "处理中", "跟进中"] { s = s.replacingOccurrences(of: w, with: "") }
        return String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init)).lowercased()
    }

    /// 两句话有多像（0–1，按相邻两个字的组合比）
    public static func similarity(_ a: String, _ b: String) -> Double {
        func grams(_ s: String) -> Set<String> {
            let c = Array(s)
            guard c.count > 1 else { return Set(c.map(String.init)) }
            return Set((0..<(c.count - 1)).map { String(c[$0...$0 + 1]) })
        }
        let x = grams(a), y = grams(b)
        guard !x.isEmpty, !y.isEmpty else { return a == b ? 1 : 0 }
        return 2 * Double(x.intersection(y).count) / Double(x.count + y.count)
    }

    /// 文字内容的指纹（文档没变就不当成新的一周）
    public static func fingerprint(_ text: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in normalized(text).utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    /// 用这一周的文档更新问题清单。week：这一周的周一
    /// 文档还是同一版时：只补上每条在表格里的位置（旧版本导入的没记位置，重新导入一次就能写回金山文档），别的不动
    public static func refreshSources(_ issues: [MeetingIssue], with sections: [MeetingNotes.Section]) -> [MeetingIssue] {
        var result = issues
        var touched = Set<String>()
        for section in sections {
            for entry in section.entries where entry.source != nil {
                let key = normalized(entry.text)
                guard !key.isEmpty else { continue }
                let best = result.indices
                    .filter { result[$0].group == section.group && !touched.contains(result[$0].id) }
                    .map { (index: $0, score: similarity(key, normalized(result[$0].text))) }
                    .filter { $0.score >= 0.6 }
                    .max { $0.score < $1.score }
                guard let i = best?.index else { continue }
                result[i].source = entry.source
                touched.insert(result[i].id)
            }
        }
        return result
    }

    public static func update(_ issues: [MeetingIssue], with sections: [MeetingNotes.Section], week: DayKey) -> [MeetingIssue] {
        var result = issues
        var touched = Set<String>()
        for section in sections {
            for entry in section.entries {
                let item = entry.text
                let done = entry.done
                let key = normalized(item)
                guard !key.isEmpty else { continue }
                // 同一组里最像的那条（这一周还没对上的）；没解决的优先
                let best = result.indices
                    .filter { result[$0].group == section.group && !touched.contains(result[$0].id) }
                    .map { (index: $0, score: similarity(key, normalized(result[$0].text))) }
                    .filter { $0.score >= 0.6 }
                    .max { a, b in
                        let ra = result[a.index].status == .resolved, rb = result[b.index].status == .resolved
                        return ra != rb ? ra : a.score < b.score
                    }
                if let i = best?.index {
                    result[i].text = item
                    result[i].detail = entry.detail ?? result[i].detail
                    result[i].source = entry.source ?? result[i].source
                    result[i].lastWeek = max(result[i].lastWeek, week)
                    if done {
                        if result[i].status != .resolved { result[i].resolvedWeek = week }
                        result[i].status = .resolved
                    } else if result[i].status != .open, !(result[i].manual && result[i].resolvedWeek == week) {
                        // 没写解决、又出现了：还没解决（这一周自己刚标了解决的，同一周的文档里还列着不算）
                        result[i].status = .open
                        result[i].resolvedWeek = nil
                        result[i].manual = false
                    }
                    touched.insert(result[i].id)
                } else {
                    let id = "\(section.group)|\(week)|\(key.prefix(32))"
                    let issue = MeetingIssue(id: id, group: section.group, text: item, firstWeek: week, lastWeek: week,
                                             status: done ? .resolved : .open, resolvedWeek: done ? week : nil,
                                             detail: entry.detail, source: entry.source)
                    result.append(issue)
                    touched.insert(id)
                }
            }
        }
        // 以前还挂着、这一周没再提的：多半解决了
        for i in result.indices where result[i].status == .open && result[i].lastWeek < week && !touched.contains(result[i].id) {
            result[i].status = .quiet
        }
        // 解决了、没再提的留半年
        let cutoff = week.adding(days: -182, calendar: .dayMath)
        return result.filter { $0.status == .open || $0.lastWeek >= cutoff }
    }

    /// 某天所在那一周的周一
    public static func monday(of day: DayKey, calendar: Calendar = .dayMath) -> DayKey {
        let weekday = calendar.component(.weekday, from: day.date(calendar: calendar, hour: 12))   // 1 = 周日
        return day.adding(days: -((weekday + 5) % 7), calendar: calendar)
    }
}
