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
            let fixed = WorkloadCounter.overrides[name] ?? [:]
            for day in holidays {
                // 手动纠正过的日子按纠正的算
                if let value = fixed[day] {
                    if value == WorkloadCounter.Kind.duty.rawValue { duty.append(day) }
                    if value == WorkloadCounter.Kind.duty.rawValue || value == WorkloadCounter.Kind.regular.rawValue { work += 1 }
                    continue
                }
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

/// 数据核对：找出可能读漏、读错的地方
public struct DataIssue: Hashable {
    public enum Kind: String { case noRestAfterDuty = "遥测后没写休息", unknownPost = "认不出的岗位", thinDay = "这天人数偏少" }
    public var kind: Kind
    public var day: DayKey?
    public var name: String?
    public var text: String
}

public enum DataCheck {
    /// roster：全员排班；published：网站已排班的日子；members：只按排班算的人；看最近 days 天
    public static func issues(roster: Roster, published: Set<DayKey>, matcher: ShiftMatcher, members: Set<String>?,
                              today: DayKey, lookback: Int = 60, calendar: Calendar = .current) -> [DataIssue] {
        var result: [DataIssue] = []
        let start = today.adding(days: -lookback, calendar: calendar)
        let recent = published.filter { $0 >= start && $0 <= today }

        // 1. 遥测后接下来的工作日网站上什么都没写：按规则算上班，可能是没读到「休息」
        for (name, history) in roster where WorkloadCounter.rules.blankWorkdayIsWork
            && !WorkloadCounter.isRotating(name: name, history: history, members: members, matcher: matcher) {
            for (day, raw) in history where day >= start && day <= today
                && raw.split(separator: "+").contains(where: { WorkloadCounter.isDuty(matcher.displayName(String($0))) }) {
                for offset in 1...3 {
                    let d = day.adding(days: offset, calendar: calendar)
                    guard d <= today, recent.contains(d) else { break }
                    if history[d] != nil { break }
                    if ChinaHolidays.isWorkday(d, calendar: calendar) {
                        result.append(DataIssue(kind: .noRestAfterDuty, day: d, name: name,
                                                text: "\(name) \(day.month)月\(day.day)日遥测，\(d.month)月\(d.day)日网站上什么都没写，现在按上班算"))
                        break
                    }
                }
            }
        }

        // 2. 认不出的岗位：既不是组别、遥测、调度，也不是休息、出差，也不在班次设置里
        var unknown: [String: Int] = [:]
        for history in roster.values {
            for (day, raw) in history where day >= start && day <= today {
                for part in raw.split(separator: "+") {
                    let post = matcher.displayName(String(part))
                    if matcher.match(post) == nil && !GroupNotes.isGroup(post) && !WorkloadCounter.isDuty(post)
                        && !WorkloadCounter.isOff(post, matcher: matcher) && !WorkloadCounter.isTrip(post) {
                        unknown[post, default: 0] += 1
                    }
                }
            }
        }
        for (post, n) in unknown.sorted(by: { $0.value > $1.value }) {
            result.append(DataIssue(kind: .unknownPost, day: nil, name: nil, text: "岗位「\(post)」出现 \(n) 次，App 不认识，按日常班算"))
        }

        // 3. 某天读到的人明显比平时少：可能这天没读全
        let counts = recent.map { d in (d, roster.values.filter { $0[d] != nil }.count) }
        let sorted = counts.map(\.1).sorted()
        if sorted.count >= 5 {
            let median = sorted[sorted.count / 2]
            for (d, n) in counts.sorted(by: { $0.0 > $1.0 }) where n * 2 < median {
                result.append(DataIssue(kind: .thinDay, day: d, name: nil, text: "\(d.month)月\(d.day)日只读到 \(n) 人（平时约 \(median) 人），可能没读全"))
            }
        }
        return result.sorted { ($0.day ?? today) > ($1.day ?? today) }
    }
}
