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
                func posts(_ d: DayKey) -> [String] {
                    (WorkloadCounter.effective(history[d], matcher: matcher) ?? "").split(separator: "+").map { matcher.displayName(String($0)) }
                }
                let today = posts(day)
                // 假期里值完遥测的第二天（还在假期里）休息：也算节假日上班（不算工作量，见 WorkloadCounter.autoKinds）
                let previous = day.adding(days: -1, calendar: .current)
                if ChinaHolidays.isHoliday(previous), posts(previous).contains(where: WorkloadCounter.isDuty),
                   today.allSatisfy({ WorkloadCounter.isOff($0, matcher: matcher) }),
                   today.isEmpty || today.contains(where: WorkloadCounter.isRest) {
                    work += 1
                    continue
                }
                guard !today.isEmpty else { continue }
                if today.contains(where: WorkloadCounter.isDuty) { duty.append(day) }
                if today.contains(where: { !WorkloadCounter.isOff($0, matcher: matcher) && !WorkloadCounter.isTrip($0) }) { work += 1 }
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

/// 一天的清单做了哪些。按当时的清单存档：以后组别工作内容改了，旧记录不变。
public struct TaskDayRecord: Codable, Equatable, Hashable {
    /// 那天的班（显示用）
    public var shift: String?
    public var done: [String]
    public var todo: [String]

    public init(shift: String? = nil, done: [String], todo: [String]) {
        self.shift = shift
        self.done = done
        self.todo = todo
    }

    public var total: Int { done.count + todo.count }
    public var isComplete: Bool { todo.isEmpty && !done.isEmpty }

    /// 「清单 5/6」「清单 6/6 全部做完」
    public var progress: String {
        "清单 \(done.count)/\(total)" + (isComplete ? " 全部做完" : "")
    }

    /// 交接、汇总用的两行：已完成……；未完成……
    public var lines: [String] {
        var lines: [String] = []
        if !done.isEmpty { lines.append("已完成：" + done.joined(separator: "；")) }
        if !todo.isEmpty { lines.append("未完成：" + todo.joined(separator: "；")) }
        return lines
    }

    /// 只留 cutoff 那天及以后的（key 是 yyyy-MM-dd）
    public static func pruned(_ history: [String: TaskDayRecord], keepingFrom cutoff: DayKey) -> [String: TaskDayRecord] {
        let first = cutoff.description
        return history.filter { $0.key >= first }
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
        // 工作日和周末、假日分开比（周末本来就只有遥测、休息的人）
        for workday in [true, false] {
            let counts = recent.filter { ChinaHolidays.isWorkday($0, calendar: calendar) == workday }
                .map { d in (d, roster.values.filter { $0[d] != nil }.count) }
            let sorted = counts.map(\.1).sorted()
            guard sorted.count >= 5 else { continue }
            let median = sorted[sorted.count / 2]
            for (d, n) in counts.sorted(by: { $0.0 > $1.0 }) where n * 2 < median {
                result.append(DataIssue(kind: .thinDay, day: d, name: nil, text: "\(d.month)月\(d.day)日只读到 \(n) 人（平时约 \(median) 人），可能没读全"))
            }
        }
        return result.sorted { ($0.day ?? today) > ($1.day ?? today) }
    }
}

/// 节假日值班预测：网站公告的规则——「预先两周排出前一次（节假日）未值班的和值班次数少的人员名单（预留人员）；
/// 然后询问是否有自愿报名的同事顶替（无人报名就按名单执行）」。
/// 这里按这条规则排出下一个节假日的预留名单（不知道谁会自愿报名，所以只是参考）。
public enum HolidayDutyPlanner {
    public struct Candidate: Equatable {
        public var name: String
        /// 上一个节假日值没值遥测
        public var servedLastHoliday: Bool
        /// 近一年节假日值遥测的次数
        public var holidayDuties: Int
        /// 近一年值遥测的总次数
        public var duties: Int
    }

    public struct Plan: Equatable {
        /// 下一个节假日（连续放假的日子）
        public var days: [DayKey]
        /// 上一个节假日
        public var lastHoliday: [DayKey]
        /// 预留名单：按规则排在前面的，人数 = 假期天数
        public var reserve: [Candidate]
        /// 其余人，按同样的顺序
        public var others: [Candidate]
        /// 名单大约哪天排出（假期前两周）
        public var listDate: DayKey
    }

    /// 从 from 往后（back = true 时往前）找第一段连续的法定节假日
    static func holidayRun(from: DayKey, back: Bool, calendar: Calendar) -> [DayKey] {
        var day = from
        let step = back ? -1 : 1
        for _ in 0..<400 {
            if ChinaHolidays.isHoliday(day) {
                var run = [day]
                var d = day.adding(days: step, calendar: calendar)
                while ChinaHolidays.isHoliday(d) { run.append(d); d = d.adding(days: step, calendar: calendar) }
                return run.sorted()
            }
            day = day.adding(days: step, calendar: calendar)
        }
        return []
    }

    /// pool：参加遥测轮转的人（不传就用近一年值过遥测的人）
    public static func plan(roster: Roster, today: DayKey, matcher: ShiftMatcher, pool: Set<String>? = nil,
                            people: [String: SiteAPI.Person] = [:], calendar: Calendar = .current) -> Plan? {
        // 正在放假：看这个假期（从假期第一天算起）；否则看下一个
        var start = today
        while ChinaHolidays.isHoliday(start), ChinaHolidays.isHoliday(start.adding(days: -1, calendar: calendar)) {
            start = start.adding(days: -1, calendar: calendar)
        }
        let next = holidayRun(from: start, back: false, calendar: calendar)
        guard let first = next.first else { return nil }
        let last = holidayRun(from: first.adding(days: -1, calendar: calendar), back: true, calendar: calendar)
        let since = today.adding(days: -365, calendar: calendar)
        func isDuty(_ raw: String?) -> Bool {
            (WorkloadCounter.effective(raw, matcher: matcher) ?? "").split(separator: "+")
                .contains { WorkloadCounter.isDuty(matcher.displayName(String($0))) }
        }
        let names = pool ?? Set(roster.filter { _, h in h.contains { $0.key >= since && isDuty($0.value) } }.keys)
        let candidates = names.filter { people[$0]?.onDuty != false }.map { name -> Candidate in
            let history = roster[name] ?? [:]
            let duties = history.filter { $0.key >= since && $0.key < first && isDuty($0.value) }.keys
            return Candidate(name: name,
                             servedLastHoliday: last.contains { isDuty(history[$0]) },
                             holidayDuties: duties.filter(ChinaHolidays.isHoliday).count,
                             duties: duties.count)
        }
        // 上次没值的在前；节假日值得少的在前；总共值得少的在前
        let sorted = candidates.sorted {
            ($0.servedLastHoliday ? 1 : 0, $0.holidayDuties, $0.duties, $0.name)
                < ($1.servedLastHoliday ? 1 : 0, $1.holidayDuties, $1.duties, $1.name)
        }
        let n = min(next.count, sorted.count)
        return Plan(days: next, lastHoliday: last, reserve: Array(sorted.prefix(n)), others: Array(sorted.dropFirst(n)),
                    listDate: first.adding(days: -14, calendar: calendar))
    }
}
