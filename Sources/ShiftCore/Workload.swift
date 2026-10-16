import Foundation

/// 每个人一段时间（一般是一个月到今天）的工作量，每一天归到一类：
/// - 值班：遥测（工作到第二天 8:30）
/// - 值班调休：只有管理员手动改成「值班调休」的日子（规则版本 3 起，休息一律不算工作量）
///   （网站上写了休息、调休、请假的，不管节假日还是平时，都算休息，不算工作量）
/// - 日常：各组、调度等其它岗位；除了调度，不管轮不轮组别，工作日没排岗位、也没写休息的日子（正常上班）
/// - 上班（不算工作量）：假期里值完遥测的第二天休息（算上班天数、节假日上班，不算工作量）
/// - 未排班：调度（最近三个月一半以上排的是调度的人，以及设置里「只按排班算」的人）工作日网站上没给他排岗位的日子（不算工作量，也不算休息）
/// - 出差（算工作量）
/// - 节假日：中秋、国庆、春节、清明、五一等法定假日，网站上没排任何岗位的日子
/// - 休息：其它写了休息、调休、请假、无分工的日子，以及周末没排岗位的日子
/// 工作量 = 值班 + 值班调休 + 日常 + 出差；
/// 上班天数 = 工作量 + 没排岗位的上班日。
public struct PersonWorkload: Equatable {
    public var name: String
    /// 值班（遥测）天数
    public var dutyDays: Int
    /// 节假日值班后的调休天数（算工作量）
    public var dutyRestDays: Int
    /// 日常班天数：各组、调度等岗位（有岗位的日子）
    public var regularDays: Int
    /// 休息：和值班无关的休息、调休、请假、无分工，周末没排岗位
    public var offDays: Int
    /// 法定节假日没上班的天数
    public var holidayDays: Int
    public var tripDays: Int
    /// 其中在法定节假日上班（值班或日常）的天数
    public var holidayWorkedDays: Int
    /// 各岗位天数（不含日常班）
    public var posts: [String: Int]
    /// 调度（只按排班算的人）工作日没排岗位的天数（不算工作量，也不算上班）
    public var unassignedDays: Int = 0
    /// 上班但不算工作量的天数（假期里值完遥测的第二天休息、手动改成「上班」的日子）
    public var attendanceDays: Int = 0
    /// 日常里工作日网站上没排岗位、也没写休息的天数（正常上班、算工作量，单独数出来看）
    public var blankWorkDays: Int = 0
    /// 这段时间是不是轮组别（组A–E）的人：有档案按档案，没有的按最近三个月的排班认
    public var isGroupMember = false

    /// 工作量 = 值班 + 值班调休 + 日常 + 出差
    public var workDays: Int { dutyDays + dutyRestDays + regularDays + tripDays }
    /// 上班天数 = 工作量 + 没排岗位的上班日
    public var presentDays: Int { workDays + attendanceDays }
}

/// 工作量规则开关（设置里可以改）
public struct WorkloadRules: Codable, Equatable {
    /// 法定节假日值完遥测后，网站上写了休息、调休的也算工作量（值班调休）。
    /// 默认关：写了休息、调休、请假的，不管节假日还是平时都不算工作量
    public var holidayDutyRestCounts = false
    /// 节假日值完遥测的第二天，网站上没写也算值班调休。
    /// 默认关（规则版本 3 起统一）：休息的日子不管节假日还是平时、怎么写的，都不算工作量
    public var blankHolidayAfterDutyIsRest = false
    /// 工作日没排岗位、也没写休息的算正常上班、算工作量（调度除外）
    public var blankWorkdayIsWork = true
    /// 调度只算排班表上有名字的日子
    public var dispatchScheduleOnly = true
    /// 规则版本：2 起「写了休息就不算工作量」，旧设置里打开的值班调休开关要关掉；
    /// 3 起节假日值班后没写的那天也不算（休息一律不算工作量）
    public var version = WorkloadRules.currentVersion
    public static let currentVersion = 3

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WorkloadRules()
        holidayDutyRestCounts = try c.decodeIfPresent(Bool.self, forKey: .holidayDutyRestCounts) ?? d.holidayDutyRestCounts
        blankHolidayAfterDutyIsRest = try c.decodeIfPresent(Bool.self, forKey: .blankHolidayAfterDutyIsRest) ?? d.blankHolidayAfterDutyIsRest
        blankWorkdayIsWork = try c.decodeIfPresent(Bool.self, forKey: .blankWorkdayIsWork) ?? d.blankWorkdayIsWork
        dispatchScheduleOnly = try c.decodeIfPresent(Bool.self, forKey: .dispatchScheduleOnly) ?? d.dispatchScheduleOnly
        let stored = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        if stored < 2 { holidayDutyRestCounts = false }
        if stored < 3 { holidayDutyRestCounts = false; blankHolidayAfterDutyIsRest = false }
        version = WorkloadRules.currentVersion
    }
}

public enum WorkloadCounter {
    /// 当前规则（App 启动和改设置时写进来）
    @Locked public static var rules = WorkloadRules()
    /// 规则改动历史：某天以前按当时的规则算
    @Locked public static var ruleHistory: [RuleVersion] = []
    /// 人员档案（管理员确认过的角色、来走日期）
    @Locked public static var profiles: [String: PersonProfile] = [:]

    /// 某天用哪套规则
    public static func rules(on day: DayKey) -> WorkloadRules {
        RuleVersion.rules(on: day, versions: ruleHistory, current: rules)
    }
    /// 手动纠正：人名 → 日期 → 类别（Kind 的中文名，或「不算」表示这天不统计）
    @Locked public static var overrides: [String: [DayKey: String]] = [:]
    public static let excluded = "不算"

    /// 休息、调休、请假、无分工都不算上班。
    /// 「节假日值班」「假期加班」这类带「假」字的仍是上班：值班、出差、加班（不是「加班调休」）先排除
    public static func isOff(_ post: String, matcher: ShiftMatcher) -> Bool {
        if isDuty(post) || isTrip(post) || (post.contains("加班") && !post.contains("休")) { return false }
        return matcher.match(post)?.id == "off" || post.contains("休") || post.contains("假") || post == "无分工"
    }

    public static func isTrip(_ post: String) -> Bool { post.contains("出差") }

    /// 值班只有遥测
    /// 「值班交接前」（也有写成「值班交班前」的）：网站上单独一列，这一列的人前一天值了遥测，今天是休息
    public static func isIgnored(_ post: String) -> Bool { post.contains("交班") || post.contains("交接") }

    /// 统计时「值班交接前」统一换成这个：算休息（值完遥测后的第一天休息）
    public static let handoverRest = "交接休息"

    /// 统计用的岗位：「值班交接前」换成「交接休息」（休息），其它不变
    public static func effective(_ raw: String?, matcher: ShiftMatcher) -> String? {
        guard let raw else { return nil }
        return matcher.cachedEffective(raw) { uncachedEffective(raw, matcher: matcher) }
    }

    private static func uncachedEffective(_ raw: String, matcher: ShiftMatcher) -> String? {
        let parts = raw.split(separator: "+").map(String.init)
            .map { isIgnored(matcher.displayName($0)) ? handoverRest : $0 }
        var seen = Set<String>()
        let kept = parts.filter { seen.insert($0).inserted }
        return kept.isEmpty ? nil : kept.joined(separator: "+")
    }

    /// 值班就是遥测：网站上写「遥测」或「值班」都算；「值班交接前」是网站上单独的一列，不算
    /// 「值班调休」「值班休息」「值班请假」是值完班后的休息、请假，不算值班
    public static func isDuty(_ post: String) -> Bool {
        if post.contains("遥测") { return true }
        guard post.contains("值班"), !isIgnored(post) else { return false }
        return !["调休", "休息", "请假", "休假"].contains { post.contains($0) }
    }

    /// 值班换来的休息：休息、调休（请假不算）
    static func isRest(_ post: String) -> Bool { post.contains("休息") || post.contains("调休") }

    /// 一个遥测值班最多换几天调休
    public static let restPerDuty = 2
    /// 最后一次出现在网站上之后，还当作在岗的天数
    public static let activeAfter = 60

    /// 一天归到哪一类
    public enum Kind: String {
        case duty = "值班", dutyRest = "值班调休", regular = "日常", trip = "出差", holiday = "节假日", off = "休息",
             unassigned = "未排班", attendance = "上班"

        /// 算不算工作量
        public var isWorkload: Bool { [.duty, .dutyRest, .regular, .trip].contains(self) }
    }

    /// 只按排班算的人：调度的人（排班表上有名字才算一天），加上设置里另外加的人。
    /// 有档案的按档案；没有的自动判断（见 autoIsDispatch）。
    public static func isRotating(name: String, history: [DayKey: String], members: Set<String>?,
                                  matcher: ShiftMatcher, asOf: DayKey? = nil) -> Bool {
        if members?.contains(name) == true { return true }
        guard let end = asOf ?? history.keys.max() else { return false }
        guard rules(on: end).dispatchScheduleOnly else { return false }
        if let role = profiles[name]?.role(on: end) { return role == .dispatch }
        return autoIsDispatch(history: history, matcher: matcher, asOf: end)
    }

    /// 自动判断是不是调度：asOf（默认最后出现的日子）前三个月里，调度至少 3 天、占他所有岗位（不含休息出差）的一半以上。
    /// 只是偶尔顶一次调度的人（组别、遥测的人）不算。
    public static func autoIsDispatch(history: [DayKey: String], matcher: ShiftMatcher, asOf: DayKey? = nil) -> Bool {
        guard let end = asOf ?? history.keys.max() else { return false }
        let start = end.adding(days: -90, calendar: .dayMath)
        // 组A、组B… 分开数的话，轮组别的人可能调度反而最多，所以和其它岗位的总数比
        var dispatch = 0, total = 0
        for (day, raw) in history where day >= start && day <= end {
            for part in effective(raw, matcher: matcher)?.split(separator: "+") ?? [] {
                let post = matcher.displayName(String(part))
                guard !isOff(post, matcher: matcher), !isTrip(post) else { continue }
                total += 1
                if post.contains("调度") { dispatch += 1 }
            }
        }
        return dispatch >= 3 && dispatch * 2 >= total
    }

    /// 是不是轮组别（组A–E）的人：有档案按档案，没有的自动判断（见 autoIsGroupMember）。
    /// 这些人没排岗位的工作日是正常上班，但不算工作量；不轮组别的人那些日子在做别的日常工作，算工作量。
    public static func isGroupMember(history: [DayKey: String], matcher: ShiftMatcher, asOf: DayKey? = nil,
                                     name: String? = nil) -> Bool {
        if let name, let end = asOf ?? history.keys.max(), let role = profiles[name]?.role(on: end) { return role == .group }
        return autoIsGroupMember(history: history, matcher: matcher, asOf: asOf)
    }

    /// 自动判断是不是轮组别的人：asOf 前三个月里，组别占他所有岗位（不含休息、出差）的一半以上。
    public static func autoIsGroupMember(history: [DayKey: String], matcher: ShiftMatcher, asOf: DayKey? = nil) -> Bool {
        guard let end = asOf ?? history.keys.max() else { return false }
        let start = end.adding(days: -90, calendar: .dayMath)
        var group = 0, total = 0
        for (day, raw) in history where day >= start && day <= end {
            for part in effective(raw, matcher: matcher)?.split(separator: "+") ?? [] {
                let post = matcher.displayName(String(part))
                guard !isOff(post, matcher: matcher), !isTrip(post) else { continue }
                total += 1
                if WorkloadBalance.isGroup(post) { group += 1 }
            }
        }
        return group >= 1 && group * 2 >= total
    }

    /// 某一天怎么算的：类别和原因
    public struct DayExplanation: Equatable {
        public var kind: Kind
        public var reason: String
    }

    /// 不看前后日子时这一天的类别（raw：网站上这天的岗位，没排为 nil；rotating：这个人是不是只按排班算（调度）；
    /// groupMember：是不是轮组别的人）
    public static func classify(_ raw: String?, workday: Bool, holiday: Bool, rotating: Bool = false,
                                groupMember: Bool = false, matcher: ShiftMatcher) -> Kind {
        explain(raw, workday: workday, holiday: holiday, rotating: rotating, groupMember: groupMember,
                rules: rules, matcher: matcher).kind
    }

    /// 同 classify，另外给出原因
    static func explain(_ raw: String?, workday: Bool, holiday: Bool, rotating: Bool, groupMember: Bool,
                        rules r: WorkloadRules, matcher: ShiftMatcher, roleNote: String = "") -> DayExplanation {
        guard let raw else {
            if holiday { return DayExplanation(kind: .holiday, reason: "法定节假日，网站上没排岗位") }
            guard workday else { return DayExplanation(kind: .off, reason: "周末，网站上没排岗位") }
            if !r.blankWorkdayIsWork {
                return DayExplanation(kind: .unassigned, reason: "工作日没排岗位（规则：没排岗位不算上班）")
            }
            if rotating {
                return DayExplanation(kind: .unassigned, reason: "调度只按排班表算：这天网站上没排他" + roleNote)
            }
            // 除了调度，不管轮不轮组别：没排岗位、没写休息就是正常上班，算工作量
            return DayExplanation(kind: .regular, reason: "工作日没排岗位、没写休息：正常上班，算工作量" + roleNote)
        }
        let posts = raw.split(separator: "+").map { matcher.displayName(String($0)) }
        if posts.contains(where: isDuty) { return DayExplanation(kind: .duty, reason: "网站上排了遥测（值班）") }
        if let post = posts.first(where: { !isOff($0, matcher: matcher) && !isTrip($0) }) {
            return DayExplanation(kind: .regular, reason: "网站上排了\(post)")
        }
        if posts.contains(where: isTrip) { return DayExplanation(kind: .trip, reason: "网站上写了出差（算工作量）") }
        if posts.contains(handoverRest) {
            return DayExplanation(kind: .off, reason: "在「值班交接前」一列：前一天值了遥测，今天休息，不算工作量")
        }
        return DayExplanation(kind: .off, reason: "网站上写了\(posts.joined(separator: "+"))：休息，不算工作量")
    }

    /// 某人每一天的类别：法定节假日里，遥测后紧接着写了休息、调休的日子（最多 2 天）算值班调休；
    /// 平时的休息不管怎么来的都算休息。
    /// history：这个人全部的排班（用来看统计范围前一两天是不是遥测）。
    /// groupMember：是不是轮组别的人（nil = 按这段时间最后一天往前三个月判断，有档案按档案）
    public static func kinds(of history: [DayKey: String], days: [DayKey], matcher: ShiftMatcher, rotating: Bool,
                             groupMember: Bool? = nil, name: String? = nil, forced: Bool = false,
                             calendar: Calendar = .current) -> [DayKey: Kind] {
        explained(of: history, days: days, matcher: matcher, rotating: rotating, groupMember: groupMember,
                  name: name, forced: forced, calendar: calendar).mapValues(\.kind)
    }

    /// 是不是调度（不管规则开没开）：有档案按档案，没有的自动判断。规则按每天生效的在 autoKinds 里套。
    public static func isDispatchPerson(name: String, history: [DayKey: String], matcher: ShiftMatcher, asOf: DayKey? = nil) -> Bool {
        guard let end = asOf ?? history.keys.max() else { return false }
        if let role = profiles[name]?.role(on: end) { return role == .dispatch }
        return autoIsDispatch(history: history, matcher: matcher, asOf: end)
    }

    /// 同 kinds，每天另外给出原因（每日明细里显示「为什么这样算」）
    /// rotating：是不是调度（没档案时用）；forced：设置里「只按排班算」名单上的人（不管档案和规则都只按排班算）
    public static func explained(of history: [DayKey: String], days: [DayKey], matcher: ShiftMatcher, rotating: Bool,
                                 groupMember: Bool? = nil, name: String? = nil, forced: Bool = false,
                                 calendar: Calendar = .current) -> [DayKey: DayExplanation] {
        let fixed = name.flatMap { overrides[$0] } ?? [:]
        let member = groupMember ?? isGroupMember(history: history, matcher: matcher, asOf: days.max(), name: name)
        let profile = name.flatMap { profiles[$0] }
        let history = history.compactMapValues { effective($0, matcher: matcher) }
        var result = autoKinds(of: history, days: days, matcher: matcher, rotating: rotating, groupMember: member,
                               profile: profile, forced: forced, fixed: fixed, calendar: calendar)
        // 手动纠正优先
        for day in days {
            guard let value = fixed[day] else { continue }
            if value == excluded {
                result[day] = nil
            } else if let kind = Kind(rawValue: value) {
                result[day] = DayExplanation(kind: kind, reason: "管理员手动改成「\(value)」")
            }
        }
        return result
    }

    /// 同 explained，但一个月一个月地判断这个人是调度、轮组别还是不轮组别（各自按那个月往前三个月）。
    /// 全年统计和每个月的统计因此对得上：年初轮组别、后来改做调度的人，1 月份照样按轮组别算。
    public static func explainedByMonth(name: String, history: [DayKey: String], days: [DayKey], matcher: ShiftMatcher,
                                        forced: Bool = false, calendar: Calendar = .current) -> [DayKey: DayExplanation] {
        let months = Dictionary(grouping: days) { $0.year * 100 + $0.month }
        var result: [DayKey: DayExplanation] = [:]
        for chunk in months.values {
            let dispatcher = isDispatchPerson(name: name, history: history, matcher: matcher, asOf: chunk.max())
            result.merge(explained(of: history, days: chunk, matcher: matcher, rotating: dispatcher, name: name,
                                   forced: forced, calendar: calendar)) { _, new in new }
        }
        return result
    }

    /// fixed：手动纠正（改成值班 / 不是值班的日子，影响后面一天算不算值班调休）
    /// profile：人员档案（每天的角色、来走日期）；没有档案时用 rotating、groupMember
    static func autoKinds(of history: [DayKey: String], days: [DayKey], matcher: ShiftMatcher, rotating: Bool,
                          groupMember: Bool = false, profile: PersonProfile? = nil, forced: Bool = false,
                          fixed: [DayKey: String] = [:], calendar: Calendar) -> [DayKey: DayExplanation] {
        var result: [DayKey: DayExplanation] = [:]
        // 这个人在网站上第一次出现前两周、最后一次出现两个月以后（还没来、已经调走）没数据的日子不算。
        // 不轮组别的人可能好几周都不出现在表上（一直在做日常），所以往后放宽到两个月；档案里填了来走日期的按档案
        let keys = history.keys
        let active = keys.min().flatMap { lo in keys.max().map {
            lo.adding(days: -14, calendar: calendar)...$0.adding(days: activeAfter, calendar: calendar) } }
        for day in days {
            if let inPost = profile?.isActive(on: day) {
                guard inPost else { continue }
            } else {
                guard history[day] != nil || active?.contains(day) == true else { continue }
            }
            let role = profile?.role(on: day)
            if role == .leader { continue }   // 领导自己没有排班，不统计
            let dayRules = rules(on: day)
            // 名单上的人一直只按排班算；调度（档案或自动判断）按那天的规则决定
            let isDispatcher = role.map { $0 == .dispatch } ?? rotating
            let dayRotating = forced || (isDispatcher && dayRules.dispatchScheduleOnly)
            let dayMember = role.map { $0 == .group } ?? groupMember
            let note = role.map { "（档案：\($0.rawValue)）" }
                ?? "（按最近排班认：\(dayRotating ? "调度" : (dayMember ? "轮组别" : "不轮组别"))）"
            result[day] = explain(history[day], workday: ChinaHolidays.isWorkday(day, calendar: calendar),
                                  holiday: ChinaHolidays.isHoliday(day), rotating: dayRotating, groupMember: dayMember,
                                  rules: dayRules, matcher: matcher, roleNote: note)
        }
        func restPosts(_ day: DayKey) -> Bool {
            guard let raw = history[day] else { return false }
            let posts = raw.split(separator: "+").map { matcher.displayName(String($0)) }
            return !posts.contains(where: { !isOff($0, matcher: matcher) && !isTrip($0) }) && posts.contains(where: isRest)
        }
        func isDutyDay(_ day: DayKey) -> Bool {
            if let value = fixed[day] { return value == Kind.duty.rawValue }
            return history[day]?.split(separator: "+").contains { isDuty(matcher.displayName(String($0))) } ?? false
        }
        // 从统计范围前两天开始找遥测，往后接着的日子看算不算值班调休（规则按那天生效的算）
        guard let first = days.min(), let last = days.max() else { return result }
        var day = first.adding(days: -restPerDuty, calendar: calendar)
        while day <= last {
            if isDutyDay(day) {
                var next = day.adding(days: 1, calendar: calendar)
                let r = rules(on: next)
                // 假期里（不是假期最后一天）值了遥测，第二天还在假期里、是值班后的休息（写了休息、值班交接前，或没写）：
                // 不算工作量，但算上班天数，也算进节假日上班
                if ChinaHolidays.isHoliday(day), ChinaHolidays.isHoliday(next), result[next] != nil,
                   history[next] == nil || restPosts(next) {
                    result[next] = DayExplanation(kind: .attendance,
                                                  reason: "假期里值完遥测的第二天休息：不算工作量，算上班天数和节假日上班")
                }
                // 旧规则（默认关）：节假日值完遥测第二天没写岗位算值班调休
                if r.blankHolidayAfterDutyIsRest, history[next] == nil, result[next] != nil, ChinaHolidays.isHoliday(next) {
                    result[next] = DayExplanation(kind: .dutyRest, reason: "节假日值完遥测的第二天，网站上没写休息：算值班调休（工作量）")
                }
                for _ in 0..<restPerDuty where r.holidayDutyRestCounts && restPosts(next) {
                    if result[next] != nil, ChinaHolidays.isHoliday(next) {
                        result[next] = DayExplanation(kind: .dutyRest, reason: "节假日值完遥测后的休息（规则：算工作量）")
                    }
                    next = next.adding(days: 1, calendar: calendar)
                }
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return result
    }

    /// days：统计哪些日子（已读到全员排班的日子）；名单是全员排班里出现过的所有人。
    /// members：设置里「只按排班算」的人（见 isRotating）
    public static func count(roster: Roster, days: [DayKey], matcher: ShiftMatcher, members: Set<String>? = nil,
                             calendar: Calendar = .current) -> [PersonWorkload] {
        guard let first = days.min(), let last = days.max() else { return [] }
        // 只算这段时间前两个月到后两周里在网站上出现过的人（调走的、还没来的不算，免得把没排班的日子都算成日常）
        let window = first.adding(days: -activeAfter, calendar: calendar)...last.adding(days: 14, calendar: calendar)
        // 节假日先查好（每人每天都要问）
        let holidays = Set(days.filter(ChinaHolidays.isHoliday))
        return roster.filter { $0.value.keys.contains(where: window.contains) }.compactMap { name, history -> PersonWorkload? in
            var p = PersonWorkload(name: name, dutyDays: 0, dutyRestDays: 0, regularDays: 0, offDays: 0, holidayDays: 0,
                                   tripDays: 0, holidayWorkedDays: 0, posts: [:])
            let dayKinds = explainedByMonth(name: name, history: history, days: days, matcher: matcher,
                                            forced: members?.contains(name) == true, calendar: calendar).mapValues(\.kind)
            // 这段时间一天都不统计（领导、已经走了、还没来）：不列出来
            if dayKinds.isEmpty { return nil }
            p.isGroupMember = isGroupMember(history: history, matcher: matcher, asOf: last, name: name)
            for day in days {
                let holiday = holidays.contains(day)
                // 不统计的日子（手动改成不算、已经调走）岗位也不计
                guard let kind = dayKinds[day] else { continue }
                for post in effective(history[day], matcher: matcher)?.split(separator: "+") ?? [] {
                    p.posts[matcher.displayName(String(post)), default: 0] += 1
                }
                switch kind {
                case .duty: p.dutyDays += 1; if holiday { p.holidayWorkedDays += 1 }
                case .dutyRest: p.dutyRestDays += 1
                case .regular:
                    p.regularDays += 1
                    if holiday { p.holidayWorkedDays += 1 }
                    // 网站上没排岗位、没写休息：正常上班（算工作量），另外数一下
                    if effective(history[day], matcher: matcher) == nil { p.blankWorkDays += 1 }
                case .trip: p.tripDays += 1
                case .holiday: p.holidayDays += 1
                case .off: p.offDays += 1
                case .unassigned: p.unassignedDays += 1
                // 节假日里的「上班」只有值班后那天休息（见 autoKinds），也算节假日上班
                case .attendance: p.attendanceDays += 1; if holiday { p.holidayWorkedDays += 1 }
                }
            }
            return p
        }
        // 按名字排好（字典顺序每次启动都不一样，同样多的人先后会乱跳）
        .sorted { $0.name < $1.name }
    }
}
