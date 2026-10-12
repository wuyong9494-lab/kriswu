import Foundation

/// 节假日值班统计：每个人在法定节假日里值了几次遥测、上了几天班（跨年累计）。
public struct HolidayDuty: Equatable {
    public var name: String
    /// 节假日遥测次数
    public var dutyDays: Int
    /// 节假日上班天数（遥测 + 组别、调度等岗位）
    public var workDays: Int
    /// 节假日遥测的日子
    public var dutyDates: [DayKey]
}

public enum HolidayDutyStats {
    /// days：统计哪些日子（一般是网站已排班、到今天为止的日子）
    public static func count(roster: Roster, days: Set<DayKey>, matcher: ShiftMatcher) -> [HolidayDuty] {
        let holidays = days.filter(ChinaHolidays.isHoliday)
        var result: [HolidayDuty] = []
        for (name, history) in roster {
            var duty: [DayKey] = []
            var work = 0
            for day in holidays {
                guard let raw = history[day] else { continue }
                let posts = raw.split(separator: "+").map { matcher.displayName(String($0)) }
                if posts.contains(where: WorkloadCounter.isDuty) { duty.append(day) }
                if posts.contains(where: { !WorkloadCounter.isOff($0, matcher: matcher) && !WorkloadCounter.isTrip($0) }) { work += 1 }
            }
            if work > 0 { result.append(HolidayDuty(name: name, dutyDays: duty.count, workDays: work, dutyDates: duty.sorted())) }
        }
        return result.sorted { ($0.dutyDays, $0.workDays, $1.name) > ($1.dutyDays, $1.workDays, $0.name) }
    }
}

/// 请假规划：想休的一段日子，要用几天、撞不撞遥测。
public struct LeavePlan: Equatable {
    /// 要请假（用待休）的日子：排了岗位的，或者网站还没排、但是工作日的
    public var needDays: [DayKey]
    /// 本来就不用上班的：周末、法定假日、已经是休息的
    public var freeDays: [DayKey]
    /// 排了遥测的日子（要先换出去）
    public var dutyDays: [DayKey]
    /// 网站还没排班的工作日（先按要请假算）
    public var unknownDays: [DayKey]
}

public enum LeavePlanner {
    /// mine：我的排班；published：网站已经正式排了班的日子。
    public static func plan(from start: DayKey, to end: DayKey, mine: [DayKey: String], published: Set<DayKey>,
                            matcher: ShiftMatcher, calendar: Calendar = .current) -> LeavePlan {
        var plan = LeavePlan(needDays: [], freeDays: [], dutyDays: [], unknownDays: [])
        guard start <= end else { return plan }
        var day = start
        var guardCount = 0
        while day <= end, guardCount < 120 {
            guardCount += 1
            let posts = mine[day].map { $0.split(separator: "+").map { matcher.displayName(String($0)) } } ?? []
            let working = posts.contains { !WorkloadCounter.isOff($0, matcher: matcher) }
            if posts.contains(where: WorkloadCounter.isDuty) { plan.dutyDays.append(day) }
            if working {
                plan.needDays.append(day)
            } else if !posts.isEmpty || ChinaHolidays.isHoliday(day) || !ChinaHolidays.isWorkday(day, calendar: calendar) {
                plan.freeDays.append(day)
            } else if published.contains(day) {
                // 网站排了这天、没给我排：本来就不用去
                plan.freeDays.append(day)
            } else {
                plan.unknownDays.append(day)
                plan.needDays.append(day)
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return plan
    }
}

/// 把组别工作内容拆成一条条，做成当天的任务清单。
public enum TaskList {
    private static let numbering = try! NSRegularExpression(pattern: #"^\s*(?:\d+|[一二三四五六七八九十]+)\s*[、.．)）:：]\s*"#)

    public static func items(from note: String) -> [String] {
        // 先按行，行里再按「；」「。」分
        let pieces = note.components(separatedBy: CharacterSet.newlines)
            .flatMap { $0.split(whereSeparator: { "；;。".contains($0) }).map(String.init) }
        return pieces.compactMap { raw in
            let ns = raw as NSString
            let stripped = numbering.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: "")
            let t = stripped.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "，,")))
            return t.isEmpty ? nil : t
        }
    }
}
