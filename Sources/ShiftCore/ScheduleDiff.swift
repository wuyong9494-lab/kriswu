import Foundation

/// 同步前后排班的差异，用来推送「排班有变动」。
public struct ScheduleChange: Hashable, Sendable {
    public var day: DayKey
    public var old: String?
    public var new: String?

    public init(day: DayKey, old: String?, new: String?) {
        self.day = day
        self.old = old
        self.new = new
    }
}

public enum ScheduleDiff {
    /// 只比较今天及以后的日子（过去的变动没有提醒意义）。
    public static func changes(old: [DayKey: String], new: [DayKey: String], from today: DayKey) -> [ScheduleChange] {
        Set(old.keys).union(new.keys)
            .filter { $0 >= today }
            .sorted()
            .compactMap { day in
                let o = old[day], n = new[day]
                return o == n ? nil : ScheduleChange(day: day, old: o, new: n)
            }
    }

    /// 通知正文，例如「10月12日 周一：白班 → 夜班」，最多列 5 条。
    /// detail：附加说明（例如「组B 原来是张三」），写在这一条后面。
    public static func summary(_ changes: [ScheduleChange], matcher: ShiftMatcher, calendar: Calendar = .current,
                               detail: (ScheduleChange) -> String? = { _ in nil }) -> String {
        var lines = changes.prefix(5).map { c -> String in
            let o = c.old.map(matcher.displayName) ?? "无"
            let n = c.new.map(matcher.displayName) ?? "无"
            let extra = detail(c).map { "（\($0)）" } ?? ""
            return "\(NotificationPlanner.dateText(c.day, calendar: calendar))：\(o) → \(n)\(extra)"
        }
        if changes.count > 5 { lines.append("……共 \(changes.count) 处变动") }
        return lines.joined(separator: "\n")
    }
}

/// 我的班组变了时，说明是和谁换的：「和李四对换：李四原来是组B，现在是组D」。
public enum SwapExplainer {
    /// before / after：变动前后的全员排班；fresh：after 里这一天是不是这次刚读到的（不是的话只能说「原来是谁」）。
    public static func describe(_ change: ScheduleChange, before: Roster, after: Roster, fresh: Bool,
                                matcher: ShiftMatcher, isMe: (String) -> Bool) -> String? {
        func key(_ s: String) -> String { s.filter { !$0.isWhitespace }.uppercased() }
        /// 真正的岗位（不含休息、未排班；出差也算，规则在 DayRules）
        func groups(_ raw: String?) -> [String] {
            DayRules.names(raw, matcher: matcher).filter { DayRules.part($0, matcher: matcher).isWork }
        }
        func holders(_ group: String, in r: Roster) -> [String] {
            r.compactMap { name, days in
                guard !isMe(name), let posts = days[change.day],
                      posts.split(separator: "+").contains(where: { key(String($0)) == key(group) }) else { return nil }
                return name
            }.sorted()
        }
        func post(of name: String, in r: Roster) -> String {
            r[name]?[change.day].map(matcher.displayName) ?? "没排班"
        }
        let oldGroups = groups(change.old), newGroups = groups(change.new)
        let gained = newGroups.filter { g in !oldGroups.contains { key($0) == key(g) } }
        let lost = oldGroups.filter { g in !newGroups.contains { key($0) == key(g) } }
        var parts: [String] = []
        var mentioned = Set<String>()

        // 我新接的组原来是谁的
        for g in gained {
            for x in holders(g, in: before) {
                mentioned.insert(x)
                if fresh {
                    let now = post(of: x, in: after)
                    if lost.contains(where: { o in groups(now).contains { key($0) == key(o) } }) {
                        parts.append("和\(x)对换：\(x)原来是\(g)，现在是\(now)")
                    } else {
                        parts.append("\(g)原来是\(x)（\(x)现在是\(now)）")
                    }
                } else {
                    parts.append("\(g)原来是\(x)，可能是和\(x)换的")
                }
            }
        }
        // 我原来的组现在是谁、他原来是哪个组
        if fresh {
            for o in lost {
                for y in holders(o, in: after) where !mentioned.contains(y) {
                    mentioned.insert(y)
                    parts.append("\(o)现在是\(y)（\(y)原来是\(post(of: y, in: before))）")
                }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "；")
    }
}
