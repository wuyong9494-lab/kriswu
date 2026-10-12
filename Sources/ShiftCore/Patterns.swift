import Foundation

/// 从全员排班反推网站的排班规律：
/// - 遥测（调度）是不是按顺序轮、请假出差是不是自动往后顺延、哪些是指定日期或换班
/// - 值完遥测休几天（按值班那天是星期几）
/// - 组A–E 是怎么轮的、哪些日子是手动调整的
/// 都是按已有数据统计出来的，不是网站真正的程序。
public enum SchedulePatterns {
    /// 这天的岗位（「值班交班前」不算）
    static func posts(_ raw: String?, matcher: ShiftMatcher) -> [String] {
        raw?.split(separator: "+").map { matcher.displayName(String($0)) }.filter { !WorkloadCounter.isIgnored($0) } ?? []
    }

    static func weekdayIndex(_ day: DayKey, calendar: Calendar) -> Int {
        calendar.component(.weekday, from: day.date(calendar: calendar, hour: 12))   // 1 = 周日
    }

    static let weekdayChars = ["日", "一", "二", "三", "四", "五", "六"]

    public static func weekdayName(_ weekday: Int) -> String { "周" + weekdayChars[(weekday - 1) % 7] }

    // MARK: - 轮转（遥测、调度）

    public struct Deferral: Equatable {
        public var day: DayKey
        public var name: String
        /// 请假、出差、休息……
        public var reason: String
    }

    public struct Exception: Equatable {
        public var day: DayKey
        /// 实际值班的人
        public var actual: String
        /// 按顺序应该是谁
        public var expected: String
    }

    public struct ForecastDay: Equatable {
        public var day: DayKey
        public var name: String
    }

    public struct Rotation: Equatable {
        public var post: String
        /// 现在的顺序：排在最前面的是下一个
        public var order: [String]
        /// 统计了多少人次
        public var slots: Int
        /// 按「顺序 + 请假出差顺延」猜对的人次
        public var matched: Int
        /// 只按顺序、不管请假出差时猜对的人次（用来看是不是真的顺延）
        public var strictMatched: Int
        public var deferrals: [Deferral]
        public var exceptions: [Exception]
        /// 网站还没排的日子，按顺序推下去
        public var forecast: [ForecastDay]
        /// 平均每人隔几天轮一次
        public var cycleDays: Double

        public var rate: Double { slots == 0 ? 0 : Double(matched) / Double(slots) }
        public var strictRate: Double { slots == 0 ? 0 : Double(strictMatched) / Double(slots) }
    }

    /// 这个岗位算不算 post：「遥测」也认「值班」（同一个意思）
    static func matches(_ name: String, _ post: String) -> Bool {
        post == "遥测" ? WorkloadCounter.isDuty(name) : name.contains(post)
    }

    /// 为什么这天轮不到他（nil = 可以排）。leave：是不是请假、出差、休息这类。
    static func unavailable(_ raw: String?, post: String, matcher: ShiftMatcher) -> (reason: String, leave: Bool)? {
        guard let raw = WorkloadCounter.effective(raw, matcher: matcher) else { return nil }
        let list = posts(raw, matcher: matcher)
        if list.contains(where: { matches($0, post) }) { return nil }
        if RosterExtractor.isLeave(raw, matcher: matcher) {
            if list.contains(where: WorkloadCounter.isTrip) { return ("出差", true) }
            if list.contains(where: { $0.contains("请假") || ($0.contains("假") && !$0.contains("休")) }) { return ("请假", true) }
            return (list.first(where: { $0.contains("调休") }) != nil ? "调休" : "休息", true)
        }
        // 这天排了别的岗位
        return (list.joined(separator: "+"), false)
    }

    /// post：「遥测」或「调度」；days：网站上有数据的日子（统计范围，可以包括以后已经排好的）。
    public static func rotation(post: String, roster: Roster, days: [DayKey], matcher: ShiftMatcher,
                                forecastDays: Int = 14, calendar: Calendar = .current) -> Rotation? {
        let sorted = days.sorted()
        guard let start = sorted.first, let end = sorted.last else { return nil }
        func holds(_ name: String, _ day: DayKey) -> Bool {
            posts(roster[name]?[day], matcher: matcher).contains { matches($0, post) }
        }
        // 轮转的人：统计范围里至少值过两次
        var counts: [String: Int] = [:]
        var firstSeen: [String: DayKey] = [:]
        for (name, history) in roster {
            for day in sorted where history[day] != nil && holds(name, day) {
                counts[name, default: 0] += 1
                if firstSeen[name] == nil { firstSeen[name] = day }
            }
        }
        let pool = Set(counts.filter { $0.value >= 2 }.keys)
        guard pool.count >= 2 else { return nil }

        // 统计开始前最后一次值班（往前最多看 90 天）
        let lookback = start.adding(days: -90, calendar: calendar)
        var initial: [String: DayKey] = [:]
        for name in pool {
            initial[name] = roster[name]?.filter { $0.key < start && $0.key >= lookback && holds(name, $0.key) }.keys.max()
        }

        func queue(_ last: [String: DayKey]) -> [String] {
            pool.sorted { a, b in
                switch (last[a], last[b]) {
                case let (x?, y?) where x != y: return x < y
                case (nil, _?): return true
                case (_?, nil): return false
                default:
                    let fa = firstSeen[a] ?? end, fb = firstSeen[b] ?? end
                    return fa != fb ? fa < fb : a < b
                }
            }
        }

        struct Run { var matched = 0; var slots = 0; var deferrals: [Deferral] = []; var exceptions: [Exception] = []
                     var last: [String: DayKey] = [:] }

        func simulate(leaveAware: Bool) -> Run {
            var run = Run(last: initial)
            var deferredYesterday: Set<String> = []
            for day in sorted {
                let holders = roster.keys.filter { holds($0, day) }
                guard !holders.isEmpty else { continue }
                let q = queue(run.last)
                var predicted: [String] = []
                var deferredToday: Set<String> = []
                for name in q where predicted.count < holders.count {
                    if leaveAware, let why = unavailable(roster[name]?[day], post: post, matcher: matcher) {
                        if why.leave {
                            deferredToday.insert(name)
                            if !deferredYesterday.contains(name) {
                                run.deferrals.append(Deferral(day: day, name: name, reason: why.reason))
                            }
                        }
                        continue
                    }
                    predicted.append(name)
                }
                deferredYesterday = deferredToday
                run.slots += holders.count
                run.matched += holders.filter { predicted.contains($0) }.count
                let missed = predicted.filter { !holders.contains($0) }
                for (i, actual) in holders.filter({ !predicted.contains($0) }).sorted().enumerated() {
                    run.exceptions.append(Exception(day: day, actual: actual, expected: i < missed.count ? missed[i] : "—"))
                }
                for name in holders where pool.contains(name) { run.last[name] = day }
            }
            return run
        }

        let run = simulate(leaveAware: true)
        let strict = simulate(leaveAware: false)

        // 网站还没排的日子：按现在的顺序一天一个推下去（已知的请假出差跳过）
        var last = run.last
        var forecast: [ForecastDay] = []
        var day = end
        for _ in 0..<forecastDays {
            day = day.adding(days: 1, calendar: calendar)
            guard let next = queue(last).first(where: { unavailable(roster[$0]?[day], post: post, matcher: matcher) == nil })
            else { continue }
            forecast.append(ForecastDay(day: day, name: next))
            last[next] = day
        }
        let perDay = Double(run.slots) / Double(max(1, sorted.filter { d in roster.keys.contains { holds($0, d) } }.count))
        return Rotation(post: post, order: queue(run.last), slots: run.slots, matched: run.matched,
                        strictMatched: strict.matched, deferrals: Array(run.deferrals.reversed()),
                        exceptions: Array(run.exceptions.reversed()), forecast: forecast,
                        cycleDays: Double(pool.count) / max(perDay, 1))
    }

    // MARK: - 值完遥测休几天

    public struct RestRow: Equatable {
        /// 1 = 周日 … 7 = 周六
        public var weekday: Int
        public var duties: Int
        /// 和规则一致的次数
        public var matched: Int
        /// 规则：休哪几天（「六日一」）
        public var expected: String
        /// 实际最常见的（「六日一」）以及出现几次
        public var typical: String
        public var typicalCount: Int
    }

    public struct RestException: Equatable {
        public var day: DayKey
        public var name: String
        public var expected: String
        public var actual: String
    }

    public struct RestRule: Equatable {
        public var rows: [RestRow]
        public var exceptions: [RestException]
        public var duties: Int { rows.reduce(0) { $0 + $1.duties } }
        public var matched: Int { rows.reduce(0) { $0 + $1.matched } }
        public var rate: Double { duties == 0 ? 0 : Double(matched) / Double(duties) }
    }

    /// 规则：值完遥测休两天；值班那天或第二天不上班（周五、周六、周日、节假日）的多休一天。
    /// 周一值 → 休二三；周五值 → 休六日一；周六值 → 休日一二；周日值 → 休一二三。
    public static func expectedRest(after day: DayKey, calendar: Calendar) -> [DayKey] {
        let next = day.adding(days: 1, calendar: calendar)
        let extra = !ChinaHolidays.isWorkday(day, calendar: calendar) || !ChinaHolidays.isWorkday(next, calendar: calendar)
        return (1...(extra ? 3 : 2)).map { day.adding(days: $0, calendar: calendar) }
    }

    static func describe(_ days: [DayKey], calendar: Calendar) -> String {
        days.isEmpty ? "不休" : days.map { weekdayChars[weekdayIndex($0, calendar: calendar) - 1] }.joined()
    }

    /// published：网站上有数据的日子（没数据的日子看不出休没休，跳过）
    public static func restRule(roster: Roster, days: [DayKey], published: Set<DayKey>, matcher: ShiftMatcher,
                                calendar: Calendar = .current) -> RestRule {
        var byWeekday: [Int: (duties: Int, matched: Int, expected: [String: Int], actual: [String: Int])] = [:]
        var exceptions: [RestException] = []
        for (name, history) in roster {
            for day in days.sorted() where posts(history[day], matcher: matcher).contains(where: WorkloadCounter.isDuty) {
                let rest = expectedRest(after: day, calendar: calendar)
                // 规则上哪天回来上班：休完后的第一个工作日
                var back = rest.last!.adding(days: 1, calendar: calendar)
                while !ChinaHolidays.isWorkday(back, calendar: calendar) { back = back.adding(days: 1, calendar: calendar) }
                // 实际：第一天有岗位（不是休息请假），或者工作日网站上没写（正常上班）
                var actualBack: DayKey?
                var off: [DayKey] = []
                var d = day.adding(days: 1, calendar: calendar)
                for _ in 0..<10 {
                    guard published.contains(d) else { break }
                    let raw = WorkloadCounter.effective(history[d], matcher: matcher)
                    let works = raw.map { !RosterExtractor.isLeave($0, matcher: matcher) }
                        ?? ChinaHolidays.isWorkday(d, calendar: calendar)
                    if works { actualBack = d; break }
                    off.append(d)
                    d = d.adding(days: 1, calendar: calendar)
                }
                guard let actualBack else { continue }
                let weekday = weekdayIndex(day, calendar: calendar)
                let expectedText = describe(rest, calendar: calendar)
                let actualText = describe(off, calendar: calendar)
                var row = byWeekday[weekday] ?? (0, 0, [:], [:])
                row.duties += 1
                row.expected[expectedText, default: 0] += 1
                row.actual[actualText, default: 0] += 1
                if actualBack == back {
                    row.matched += 1
                } else {
                    exceptions.append(RestException(day: day, name: name, expected: expectedText, actual: actualText))
                }
                byWeekday[weekday] = row
            }
        }
        // 周一在前
        let rows = [2, 3, 4, 5, 6, 7, 1].compactMap { w -> RestRow? in
            guard let r = byWeekday[w] else { return nil }
            let typical = r.actual.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }!
            let expected = r.expected.max { a, b in a.value < b.value }!.key
            return RestRow(weekday: w, duties: r.duties, matched: r.matched, expected: expected,
                           typical: typical.key, typicalCount: typical.value)
        }
        return RestRule(rows: rows, exceptions: exceptions.sorted { $0.day > $1.day })
    }

    // MARK: - 组A–E

    public struct GroupModel: Equatable {
        public var title: String
        public var hits: Int
        public var total: Int
        public var rate: Double { total == 0 ? 0 : Double(hits) / Double(total) }
    }

    public struct GroupAdjustment: Equatable {
        public var day: DayKey
        public var name: String
        public var expected: String
        public var actual: String
    }

    public struct GroupPattern: Equatable {
        public var groups: [String]
        public var people: Int
        /// 各种可能的排法，按符合率从高到低
        public var models: [GroupModel]
        /// 请假、出差回来后：接着上次的组往下排（顺延）符合几次，按日历跳过去符合几次
        public var resumeHits: Int
        public var calendarHits: Int
        public var resumeTotal: Int
        /// 不符合最可能排法的日子（多半是手动调整）
        public var adjustments: [GroupAdjustment]
        public var best: GroupModel? { models.first }
    }

    public static func groupPattern(roster: Roster, days: [DayKey], matcher: ShiftMatcher,
                                    calendar: Calendar = .current) -> GroupPattern? {
        var weekCal = calendar
        weekCal.firstWeekday = 2
        let sorted = days.sorted()
        let window = Set(sorted)
        func group(_ raw: String?) -> String? {
            let g = posts(raw, matcher: matcher).filter(WorkloadBalance.isGroup)
            return g.count == 1 ? g[0].replacingOccurrences(of: " ", with: "").uppercased() : nil
        }
        var groups = Set<String>()
        var seqs: [String: [(day: DayKey, group: String)]] = [:]
        for (name, history) in roster {
            for day in sorted {
                guard let g = group(history[day]) else { continue }
                groups.insert(g)
                seqs[name, default: []].append((day, g))
            }
        }
        let list = groups.sorted()
        guard list.count >= 2, !seqs.isEmpty else { return nil }
        let n = list.count
        let index = Dictionary(uniqueKeysWithValues: list.enumerated().map { ($1, $0) })
        func week(_ d: DayKey) -> Int {
            let date = d.date(calendar: weekCal, hour: 12)
            return weekCal.component(.yearForWeekOfYear, from: date) * 100 + weekCal.component(.weekOfYear, from: date)
        }

        // 每种排法：给前一个组别日，猜下一个组别日是哪组
        typealias Predict = (_ prev: (day: DayKey, group: String), _ cur: DayKey) -> String?
        var candidates: [(String, Predict)] = [("和前一个上班日同一组", { prev, _ in prev.group })]
        for k in 1..<n {
            let title = k == 1 ? "每个上班日往后挪一组（\(list.prefix(3).joined(separator: "→"))…）" : "每个上班日往后挪 \(k) 组"
            candidates.append((title, { prev, _ in list[(index[prev.group]! + k) % n] }))
        }
        for k in 1..<n {
            candidates.append(("一周内不变，每周往后挪 \(k == 1 ? "一" : String(k)) 组", { prev, cur in
                week(prev.day) == week(cur) ? prev.group : list[(index[prev.group]! + k) % n]
            }))
        }

        var models: [GroupModel] = []
        var predictors: [Predict] = []
        for (title, predict) in candidates {
            var hits = 0, total = 0
            for seq in seqs.values where seq.count >= 2 {
                for i in 1..<seq.count {
                    total += 1
                    if predict(seq[i - 1], seq[i].day) == seq[i].group { hits += 1 }
                }
            }
            models.append(GroupModel(title: title, hits: hits, total: total))
            predictors.append(predict)
        }
        // 和上周同一天同组（单独算：不看前一个上班日）
        var weeklyHits = 0, weeklyTotal = 0
        for seq in seqs.values {
            let byDay = Dictionary(seq.map { ($0.day, $0.group) }, uniquingKeysWith: { a, _ in a })
            for (day, g) in byDay {
                guard let before = byDay[day.adding(days: -7, calendar: calendar)] else { continue }
                weeklyTotal += 1
                if before == g { weeklyHits += 1 }
            }
        }
        models.append(GroupModel(title: "和上周同一天同一组", hits: weeklyHits, total: weeklyTotal))

        let order = models.indices.sorted { models[$0].rate > models[$1].rate }
        let bestIndex = order[0]

        // 请假出差回来后：顺延（接着排）还是按日历跳过（中间请假的工作日也算在轮次里）
        var resumeHits = 0, calendarHits = 0, resumeTotal = 0
        var adjustments: [GroupAdjustment] = []
        if bestIndex < predictors.count {
            let predict = predictors[bestIndex]
            for (name, seq) in seqs where seq.count >= 2 {
                for i in 1..<seq.count {
                    let prev = seq[i - 1], cur = seq[i]
                    let expected = predict(prev, cur.day)
                    if expected != cur.group, cur.day >= (sorted.last ?? cur.day).adding(days: -60, calendar: calendar) {
                        adjustments.append(GroupAdjustment(day: cur.day, name: name, expected: expected ?? "—", actual: cur.group))
                    }
                    // 中间有请假、出差的工作日
                    var skipped = 0
                    var d = prev.day.adding(days: 1, calendar: calendar)
                    var hadLeave = false
                    while d < cur.day {
                        if ChinaHolidays.isWorkday(d, calendar: calendar), window.contains(d) {
                            skipped += 1
                            if let raw = roster[name]?[d], RosterExtractor.isLeave(raw, matcher: matcher) { hadLeave = true }
                        }
                        d = d.adding(days: 1, calendar: calendar)
                    }
                    guard hadLeave, skipped > 0 else { continue }
                    resumeTotal += 1
                    if expected == cur.group { resumeHits += 1 }
                    // 按日历：中间每个工作日都算轮了一次
                    var p = prev
                    var step = prev.day
                    for _ in 0...skipped {
                        step = step.adding(days: 1, calendar: calendar)
                        while !ChinaHolidays.isWorkday(step, calendar: calendar) && step < cur.day {
                            step = step.adding(days: 1, calendar: calendar)
                        }
                        p = (step, predict(p, step) ?? p.group)
                    }
                    if p.group == cur.group { calendarHits += 1 }
                }
            }
        }
        return GroupPattern(groups: list, people: seqs.count, models: order.map { models[$0] },
                            resumeHits: resumeHits, calendarHits: calendarHits, resumeTotal: resumeTotal,
                            adjustments: Array(adjustments.sorted { $0.day > $1.day }.prefix(40)))
    }
}

// MARK: - 排班预警

extension SchedulePatterns {
    public struct Warning: Equatable, Hashable {
        public enum Kind: String { case assigned, unmarked }
        public var duty: DayKey
        public var day: DayKey
        public var kind: Kind
        public var text: String
        /// 用来记「已经提醒过」
        public var key: String { "\(duty)|\(day)|\(kind.rawValue)" }
    }

    static func monthDay(_ day: DayKey, calendar: Calendar) -> String {
        "\(day.month)月\(day.day)日（\(weekdayName(weekdayIndex(day, calendar: calendar)))）"
    }

    /// 某人 from 前后的遥测：按规则该休的日子，网站上却排了岗位（assigned），或者工作日什么都没写（unmarked，按规则算上班）。
    public static func restWarnings(name: String, roster: Roster, published: Set<DayKey>, from: DayKey,
                                    matcher: ShiftMatcher, calendar: Calendar = .current) -> [Warning] {
        guard let history = roster[name] else { return [] }
        let start = from.adding(days: -3, calendar: calendar)
        var result: [Warning] = []
        for (duty, raw) in history where duty >= start && posts(raw, matcher: matcher).contains(where: WorkloadCounter.isDuty) {
            let rest = expectedRest(after: duty, calendar: calendar)
            let restText = describe(rest, calendar: calendar)
            for day in rest where day >= from && published.contains(day) {
                let head = "\(monthDay(duty, calendar: calendar))遥测，按规则应休\(restText)，"
                if let raw = WorkloadCounter.effective(history[day], matcher: matcher) {
                    guard !RosterExtractor.isLeave(raw, matcher: matcher) else { continue }
                    let what = posts(raw, matcher: matcher).joined(separator: "+")
                    result.append(Warning(duty: duty, day: day, kind: .assigned,
                                          text: head + "但\(monthDay(day, calendar: calendar))排了\(what)"))
                } else if ChinaHolidays.isWorkday(day, calendar: calendar) {
                    result.append(Warning(duty: duty, day: day, kind: .unmarked,
                                          text: head + "但\(monthDay(day, calendar: calendar))网站上没写休息（会算上班）"))
                }
            }
        }
        return result.sorted { $0.day < $1.day }
    }
}

// MARK: - 待休核对

/// 反推待休天数是怎么加减的：拿每个人记录里第一次和最后一次的待休，和这段时间排的遥测、加班、休息、调休、请假对比，
/// 找一条最吻合的简单规则（比如「周五到周日值遥测 +1，调休 −1」），再列出对不上的人。
public enum RestBalanceAudit {
    public struct Rule: Equatable {
        /// 周五到周日、节假日（多休一天的）值遥测
        public var longDuty: Int
        /// 平时值遥测
        public var shortDuty: Int
        public var overtime: Int
        public var compRest: Int
        public var rest: Int
        public var leave: Int

        var coefficients: [Int] { [longDuty, shortDuty, overtime, compRest, rest, leave] }

        public var text: String {
            let names = ["周五到周日、节假日值遥测", "平时值遥测", "加班", "调休", "休息", "请假"]
            let parts = zip(names, coefficients).filter { $0.1 != 0 }.map { "\($0.0) \($0.1 > 0 ? "+" : "−")\(abs($0.1))" }
            return parts.isEmpty ? "看不出和排班有关" : parts.joined(separator: "，")
        }
    }

    public struct Row: Equatable {
        public var name: String
        public var from: DayKey
        public var to: DayKey
        /// 网站上的变化
        public var observed: Int
        /// 按规则算的变化
        public var expected: Int
        public var diff: Int { observed - expected }
    }

    public struct Result: Equatable {
        public var rule: Rule
        public var rows: [Row]
        public var matched: Int { rows.filter { $0.diff == 0 }.count }
    }

    /// (from, to] 之间的：多休一天的遥测、平时遥测、加班、调休、休息、请假 天数
    static func features(_ history: [DayKey: String], from: DayKey, to: DayKey, matcher: ShiftMatcher,
                         calendar: Calendar) -> [Int] {
        var f = [0, 0, 0, 0, 0, 0]
        for (day, raw) in history where day > from && day <= to {
            let posts = SchedulePatterns.posts(raw, matcher: matcher)
            if posts.contains(where: WorkloadCounter.isDuty) {
                if SchedulePatterns.expectedRest(after: day, calendar: calendar).count == 3 { f[0] += 1 } else { f[1] += 1 }
            }
            if posts.contains(where: { $0.contains("加班") }) { f[2] += 1 }
            if posts.contains(where: { $0.contains("调休") }) { f[3] += 1 }
            else if posts.contains(where: { $0.contains("休息") }) { f[4] += 1 }
            if posts.contains(where: { $0.contains("请假") || ($0.contains("假") && !$0.contains("休")) }) { f[5] += 1 }
        }
        return f
    }

    /// points：每个人的待休记录（按日期排好）；记录跨度不到 minSpan 天的人不算。
    public static func analyze(points: [String: [RestBalanceHistory.Point]], roster: Roster, matcher: ShiftMatcher,
                               minSpan: Int = 21, calendar: Calendar = .current) -> Result? {
        var samples: [(name: String, from: DayKey, to: DayKey, observed: Int, features: [Int])] = []
        for (name, list) in points {
            guard let first = list.first, let last = list.last,
                  last.day >= first.day.adding(days: minSpan, calendar: calendar) else { continue }
            samples.append((name, first.day, last.day, last.value - first.value,
                            features(roster[name] ?? [:], from: first.day, to: last.day, matcher: matcher, calendar: calendar)))
        }
        guard samples.count >= 2 else { return nil }
        var best: (rule: Rule, error: Int, size: Int)?
        for a in 0...3 { for b in 0...2 { for c in 0...1 { for d in -1...0 { for e in -1...0 { for g in -1...0 {
            let rule = Rule(longDuty: a, shortDuty: b, overtime: c, compRest: d, rest: e, leave: g)
            let k = rule.coefficients
            let error = samples.reduce(0) { sum, s in
                sum + abs(s.observed - zip(k, s.features).reduce(0) { $0 + $1.0 * $1.1 })
            }
            let size = k.reduce(0) { $0 + abs($1) }
            if best == nil || error < best!.error || (error == best!.error && size < best!.size) {
                best = (rule, error, size)
            }
        } } } } } }
        let rule = best!.rule
        let rows = samples.map { s in
            Row(name: s.name, from: s.from, to: s.to, observed: s.observed,
                expected: zip(rule.coefficients, s.features).reduce(0) { $0 + $1.0 * $1.1 })
        }.sorted { abs($0.diff) != abs($1.diff) ? abs($0.diff) > abs($1.diff) : $0.name < $1.name }
        return Result(rule: rule, rows: rows)
    }
}
