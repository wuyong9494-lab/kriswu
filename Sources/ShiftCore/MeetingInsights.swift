import Foundation

/// 周会问题的几种看法：我负责的、发到群里的一段话、各组每周还挂着几个
public enum MeetingInsights {
    // MARK: - 我负责的

    /// 负责人里有没有我。名字写法不一：「甲乙」「甲乙（组A）」「组A甲乙」都算；
    /// 单字的名字只认一模一样的，免得「张」把所有姓张的都算进来
    public static func isMine(_ issue: MeetingIssue, names: [String]) -> Bool {
        let mine = names.map(squeeze).filter { !$0.isEmpty }
        guard !mine.isEmpty else { return false }
        return issue.owners.map(squeeze).contains { owner in
            mine.contains { name in
                owner == name || (name.count >= 2 && owner.contains(name)) || (owner.count >= 2 && name.contains(owner))
            }
        }
    }

    /// 我负责的、还没解决的（待确认的也算：可能还要我去确认），挂得久的在前
    public static func mine(_ issues: [MeetingIssue], names: [String]) -> [MeetingIssue] {
        issues.filter { $0.status != .resolved && isMine($0, names: names) }
            .sorted { ($0.status == .open ? 0 : 1, $0.firstWeek, $0.text) < ($1.status == .open ? 0 : 1, $1.firstWeek, $1.text) }
    }

    private static func squeeze(_ s: String) -> String {
        s.filter { !$0.isWhitespace }
    }

    // MARK: - 发群用的一段话

    /// 「周会问题（10/26 那周）：还有 5 个没解决」+ 每组挂着的几条（挂得久的在前，每组最多 limit 条）
    public static func digest(_ issues: [MeetingIssue], week: DayKey, limit: Int = 5) -> String {
        let open = issues.filter { $0.status == .open }
        let quiet = issues.filter { $0.status == .quiet }.count
        var head = "周会问题（\(week.month)/\(week.day) 那周）："
        head += open.isEmpty ? "没有没解决的问题" : "还有 \(open.count) 个没解决"
        if quiet > 0 { head += "，\(quiet) 个这周没再提、待确认" }
        var lines = [head]
        for group in groupOrder(issues) {
            let items = open.filter { $0.group == group }.sorted { ($0.firstWeek, $0.text) < ($1.firstWeek, $1.text) }
            guard !items.isEmpty else { continue }
            lines.append("")
            lines.append("【\(group)】\(items.count) 个")
            for issue in items.prefix(limit) {
                var notes: [String] = []
                if !issue.owners.isEmpty { notes.append(issue.owners.joined(separator: "、")) }
                let weeks = issue.weeks(through: week)
                if weeks >= 2 { notes.append("第 \(weeks) 周") }
                lines.append("· " + issue.text + (notes.isEmpty ? "" : "（\(notes.joined(separator: "，"))）"))
            }
            if items.count > limit { lines.append("· 还有 \(items.count - limit) 个") }
        }
        return lines.joined(separator: "\n")
    }

    /// 组按文档里的先后（第一次出现的顺序）
    public static func groupOrder(_ issues: [MeetingIssue]) -> [String] {
        var seen = Set<String>()
        return issues.map(\.group).filter { seen.insert($0).inserted }
    }

    // MARK: - 各组趋势

    /// 某一周某个组：那周还挂着几个、新提几个、解决几个
    public struct WeekPoint: Equatable {
        public var week: DayKey
        public var group: String
        public var open: Int
        public var new: Int
        public var resolved: Int
    }

    /// 一个组现在的样子：挂着几个、挂得最久的几周、解决一个平均用几周
    public struct GroupStat: Equatable {
        public var group: String
        public var open: Int
        public var quiet: Int
        public var resolved: Int
        public var oldestWeeks: Int?
        public var averageWeeksToResolve: Double?
    }

    /// 那一周还挂着没有：提出来以后、解决（或者不再提）之前
    public static func isOpen(_ issue: MeetingIssue, at week: DayKey) -> Bool {
        guard issue.firstWeek <= week else { return false }
        switch issue.status {
        case .open: return true
        case .quiet: return week <= issue.lastWeek
        case .resolved: return week < (issue.resolvedWeek ?? issue.lastWeek)
        }
    }

    /// 最近 maxWeeks 周（从有记录的第一周起）每个组每周的数
    public static func trend(_ issues: [MeetingIssue], through week: DayKey, maxWeeks: Int = 12,
                             calendar: Calendar = .dayMath) -> [WeekPoint] {
        guard let first = issues.map(\.firstWeek).min(), maxWeeks > 0 else { return [] }
        let end = MeetingTracker.monday(of: week, calendar: calendar)
        var start = max(MeetingTracker.monday(of: first, calendar: calendar), end.adding(days: -7 * (maxWeeks - 1), calendar: calendar))
        var weeks: [DayKey] = []
        while start <= end {
            weeks.append(start)
            start = start.adding(days: 7, calendar: calendar)
        }
        let groups = groupOrder(issues)
        return weeks.flatMap { w in
            groups.map { g in
                let inGroup = issues.filter { $0.group == g }
                return WeekPoint(week: w, group: g,
                                 open: inGroup.filter { isOpen($0, at: w) }.count,
                                 new: inGroup.filter { $0.firstWeek == w }.count,
                                 resolved: inGroup.filter { $0.status == .resolved && $0.resolvedWeek == w }.count)
            }
        }
    }

    /// 每个组现在的情况，挂着的多的在前
    public static func groupStats(_ issues: [MeetingIssue], week: DayKey) -> [GroupStat] {
        let order = Dictionary(uniqueKeysWithValues: groupOrder(issues).enumerated().map { ($1, $0) })
        return Dictionary(grouping: issues, by: \.group).map { group, items in
            let open = items.filter { $0.status == .open }
            let done = items.filter { $0.status == .resolved }
            let spans = done.map { Double($0.weeks(through: week)) }
            return GroupStat(group: group, open: open.count,
                             quiet: items.filter { $0.status == .quiet }.count,
                             resolved: done.count,
                             oldestWeeks: open.map { $0.weeks(through: week) }.max(),
                             averageWeeksToResolve: spans.isEmpty ? nil : spans.reduce(0, +) / Double(spans.count))
        }
        .sorted { (-$0.open, order[$0.group] ?? .max) < (-$1.open, order[$1.group] ?? .max) }
    }
}
