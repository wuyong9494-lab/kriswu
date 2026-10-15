import Foundation

/// 每条全员排班是从哪读来的、什么时候读的
public struct Provenance: Codable, Equatable {
    /// 「sync」同步（手机版页面 + 数据接口）、「desktop」电脑版周表
    public var source: String
    public var at: Date

    public init(source: String, at: Date) {
        self.source = source
        self.at = at
    }

    public var sourceTitle: String {
        switch source {
        case "desktop": return "电脑版周表"
        case "sync": return "同步"
        default: return source
        }
    }
}

public typealias RosterSources = [String: [DayKey: Provenance]]

/// 一条排班变动（网站上某人某天的岗位变了）
public struct RosterEdit: Codable, Equatable {
    public var at: Date
    public var day: DayKey
    public var name: String
    public var old: String?
    public var new: String?
    public var source: String

    public init(at: Date, day: DayKey, name: String, old: String?, new: String?, source: String) {
        self.at = at
        self.day = day
        self.name = name
        self.old = old
        self.new = new
        self.source = source
    }
}

public enum RosterMerger {
    public struct Result {
        public var roster: Roster
        public var sources: RosterSources
        /// 以前读到过的日子里变了的（第一次读到的日子不算变动）
        public var edits: [RosterEdit]
    }

    /// 这次读到的有没有休息、请假、出差（有就说明这种读取方式带休息列）
    public static func hasLeave(_ roster: Roster, matcher: ShiftMatcher) -> Bool {
        roster.values.contains { $0.values.contains { RosterExtractor.isLeave($0, matcher: matcher) } }
    }

    /// 是不是同一回事、只是写法或读取方式不同（不记成变动、不提醒）：
    /// 电脑版写「值班交班前」、数据接口是「值班交接前」；有的页面把值完遥测后那天放在「休息」、有的放在「值班交接前」；
    /// 一天几个岗位只是先后顺序不同（「组A+组E」和「组E+组A」）
    public static func sameMeaning(_ a: String?, _ b: String?, matcher: ShiftMatcher) -> Bool {
        guard let a, let b else { return a == b }
        func key(_ raw: String) -> String {
            (WorkloadCounter.effective(raw, matcher: matcher) ?? raw).split(separator: "+")
                .map { part -> String in
                    let name = matcher.displayName(String(part).trimmingCharacters(in: .whitespaces))
                    return name == WorkloadCounter.handoverRest ? "休息" : name
                }
                .sorted().joined(separator: "+")
        }
        return key(a) == key(b)
    }

    /// 把这次读到的合并进已保存的：读到的日子整天以新的为准；
    /// 但这种读取方式不带休息列（carriesLeave = false）时，保留之前读到的休息、请假（来源也保留）。
    public static func merge(old: Roster, oldSources: RosterSources, new: Roster, source: String, at: Date,
                             carriesLeave: Bool, matcher: ShiftMatcher) -> Result {
        guard !new.isEmpty else { return Result(roster: old, sources: oldSources, edits: []) }
        let days = Set(new.values.flatMap(\.keys))
        let knownDays = Set(old.values.flatMap(\.keys))
        var roster = old
        var sources = oldSources
        var edits: [RosterEdit] = []
        let names = Set(old.keys).union(new.keys)
        for name in names {
            for day in days {
                let oldValue = old[name]?[day]
                let newValue = new[name]?[day]
                var final: String?
                if let newValue {
                    final = newValue
                    sources[name, default: [:]][day] = Provenance(source: source, at: at)
                } else if !carriesLeave, let oldValue, RosterExtractor.isLeave(oldValue, matcher: matcher) {
                    final = oldValue   // 来源不变
                } else {
                    final = nil
                    sources[name]?[day] = nil
                }
                if final != oldValue {
                    if let final { roster[name, default: [:]][day] = final } else { roster[name]?[day] = nil }
                    // 只是写法不同（「值班交班前」和「值班交接前」、两种休息）：存新的，不算变动
                    if knownDays.contains(day), !sameMeaning(oldValue, final, matcher: matcher) {
                        edits.append(RosterEdit(at: at, day: day, name: name, old: oldValue, new: final, source: source))
                    }
                }
            }
        }
        roster = roster.filter { !$0.value.isEmpty }
        sources = sources.filter { !$0.value.isEmpty }
        return Result(roster: roster, sources: sources,
                      edits: edits.sorted { ($0.day, $0.name) < ($1.day, $1.name) })
    }
}

/// 网站一般什么时候排出新的一周：记下每次发现新排班的时间，找出常见的「星期几 + 几点」
public enum PublishPattern {
    public struct Slot: Equatable, Hashable {
        /// 1 = 周日 … 7 = 周六
        public var weekday: Int
        public var hour: Int
    }

    /// 出现过至少 2 次的时段（同一天前后一小时算一个），按次数排
    public static func hotSlots(_ times: [Date], calendar: Calendar = .current) -> [(slot: Slot, count: Int)] {
        var counts: [Slot: Int] = [:]
        for t in times {
            let c = calendar.dateComponents([.weekday, .hour], from: t)
            guard let w = c.weekday, let h = c.hour else { continue }
            counts[Slot(weekday: w, hour: h), default: 0] += 1
        }
        // 相邻一小时合并计数
        var merged: [Slot: Int] = [:]
        for (slot, _) in counts {
            let near = (-1...1).reduce(0) { $0 + (counts[Slot(weekday: slot.weekday, hour: slot.hour + $1)] ?? 0) }
            merged[slot] = near
        }
        return merged.filter { $0.value >= 2 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : ($0.key.weekday, $0.key.hour) < ($1.key.weekday, $1.key.hour) }
            .map { ($0.key, $0.value) }
    }

    /// date 前后一小时是不是网站常排班的时段
    public static func isHot(_ date: Date, times: [Date], calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.weekday, .hour], from: date)
        guard let w = c.weekday, let h = c.hour else { return false }
        return hotSlots(times, calendar: calendar).contains { $0.slot.weekday == w && abs($0.slot.hour - h) <= 1 }
    }

    /// 从 now 起，下一个常排班时段的开始（找不到返回 nil）
    public static func nextHot(after now: Date, times: [Date], calendar: Calendar = .current) -> Date? {
        let slots = hotSlots(times, calendar: calendar).map(\.slot)
        guard !slots.isEmpty else { return nil }
        // 从这个小时的整点开始找（这个小时本身也算，不能跳过）
        var t = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        for i in 0..<(24 * 8) {
            if i > 0 { t = t.addingTimeInterval(3600) }
            let c = calendar.dateComponents([.weekday, .hour], from: t)
            if slots.contains(where: { $0.weekday == c.weekday && $0.hour == c.hour }) {
                return max(now, t.addingTimeInterval(-1800))   // 提前半小时（已经过了就从现在起）
            }
        }
        return nil
    }

    public static func describe(_ times: [Date], calendar: Calendar = .current) -> String? {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let top = hotSlots(times, calendar: calendar).prefix(2)
        guard !top.isEmpty else { return nil }
        return top.map { "周\(names[$0.slot.weekday - 1]) \($0.slot.hour):00 前后（\($0.count) 次）" }.joined(separator: "、")
    }
}
