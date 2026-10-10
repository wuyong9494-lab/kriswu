import Foundation

/// 同步前后排班的差异，用来推送「排班有变动」。
public struct ScheduleChange: Hashable {
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
