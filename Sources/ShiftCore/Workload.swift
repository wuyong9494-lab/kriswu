import Foundation

/// 每个人一段时间（一般是一个月到今天）的工作量，每一天归到一类：
/// - 值班：遥测（工作到第二天 8:30）
/// - 值班调休：法定节假日值完遥测的第二天，网站上没写休息（还在上班），算工作量
///   （网站上写了休息、调休、请假的，不管节假日还是平时，都算休息，不算工作量）
/// - 日常：各组、调度等其它岗位；工作日（按法定节假日调整）没排岗位、也没写休息的日子（正常上班）
/// - 未排班：调度（最近三个月最常排的岗位是调度的人，以及设置里「只按排班算」的人）工作日网站上没给他排岗位的日子（不算工作量，也不算休息）
/// - 出差（算工作量）
/// - 节假日：中秋、国庆、春节、清明、五一等法定假日，网站上没排任何岗位的日子
/// - 休息：其它写了休息、调休、请假、无分工的日子，以及周末没排岗位的日子
/// 工作量 = 值班 + 值班调休 + 日常 + 出差。
public struct PersonWorkload: Equatable {
    public var name: String
    /// 值班（遥测）天数
    public var dutyDays: Int
    /// 节假日值班后的调休天数（算工作量）
    public var dutyRestDays: Int
    /// 日常班天数：各组、调度等岗位，加上工作日没排岗位的日子
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
    /// 轮组别、遥测、调度的人，工作日没排岗位的天数（不算工作量）
    public var unassignedDays: Int = 0

    /// 工作量 = 值班 + 值班调休 + 日常 + 出差
    public var workDays: Int { dutyDays + dutyRestDays + regularDays + tripDays }
}

/// 工作量规则开关（设置里可以改）
public struct WorkloadRules: Codable, Equatable {
    /// 法定节假日值完遥测后，网站上写了休息、调休的也算工作量（值班调休）。
    /// 默认关：写了休息、调休、请假的，不管节假日还是平时都不算工作量
    public var holidayDutyRestCounts = false
    /// 节假日值完遥测的第二天，网站上没写也算值班调休
    public var blankHolidayAfterDutyIsRest = true
    /// 工作日没排岗位、也没写休息的算正常上班（日常）
    public var blankWorkdayIsWork = true
    /// 调度只算排班表上有名字的日子
    public var dispatchScheduleOnly = true
    /// 规则版本：2 起「写了休息就不算工作量」，旧设置里打开的值班调休开关要关掉
    public var version = WorkloadRules.currentVersion
    public static let currentVersion = 2

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
        version = WorkloadRules.currentVersion
    }
}

public enum WorkloadCounter {
    /// 当前规则（App 启动和改设置时写进来）
    public static var rules = WorkloadRules()
    /// 手动纠正：人名 → 日期 → 类别（Kind 的中文名，或「不算」表示这天不统计）
    public static var overrides: [String: [DayKey: String]] = [:]
    public static let excluded = "不算"

    /// 休息、调休、请假、无分工都不算上班。
    public static func isOff(_ post: String, matcher: ShiftMatcher) -> Bool {
        matcher.match(post)?.id == "off" || post.contains("休") || post.contains("假") || post == "无分工"
    }

    public static func isTrip(_ post: String) -> Bool { post.contains("出差") }

    /// 值班只有遥测
    public static func isDuty(_ post: String) -> Bool { post.contains("遥测") }

    /// 值班换来的休息：休息、调休（请假不算）
    static func isRest(_ post: String) -> Bool { post.contains("休息") || post.contains("调休") }

    /// 一个遥测值班最多换几天调休
    public static let restPerDuty = 2
    /// 最后一次出现在网站上之后，还当作在岗的天数
    public static let activeAfter = 60

    /// 一天归到哪一类
    public enum Kind: String {
        case duty = "值班", dutyRest = "值班调休", regular = "日常", trip = "出差", holiday = "节假日", off = "休息",
             unassigned = "未排班"
    }

    /// 只按排班算的人：调度的人（排班表上有名字才算一天），加上设置里另外加的人。
    /// 调度的人 = asOf（默认这个人最后出现的日子）前三个月里，调度至少 3 天、占他所有岗位（不含休息出差）的一半以上。
    /// 只是偶尔顶一次调度的人（组别、遥测的人）不算，他们没排岗位、没写休息的工作日照样算日常。
    public static func isRotating(name: String, history: [DayKey: String], members: Set<String>?,
                                  matcher: ShiftMatcher, asOf: DayKey? = nil) -> Bool {
        if members?.contains(name) == true { return true }
        guard rules.dispatchScheduleOnly, let end = asOf ?? history.keys.max() else { return false }
        let start = end.adding(days: -90, calendar: .current)
        // 组A、组B… 分开数的话，轮组别的人可能调度反而最多，所以和其它岗位的总数比
        var dispatch = 0, total = 0
        for (day, raw) in history where day >= start && day <= end {
            for part in raw.split(separator: "+") {
                let post = matcher.displayName(String(part))
                guard !isOff(post, matcher: matcher), !isTrip(post) else { continue }
                total += 1
                if post.contains("调度") { dispatch += 1 }
            }
        }
        return dispatch >= 3 && dispatch * 2 >= total
    }

    /// 不看前后日子时这一天的类别（raw：网站上这天的岗位，没排为 nil；rotating：这个人是不是轮班的）
    public static func classify(_ raw: String?, workday: Bool, holiday: Bool, rotating: Bool = false,
                                matcher: ShiftMatcher) -> Kind {
        guard let raw else {
            if holiday { return .holiday }
            return workday ? (rotating || !rules.blankWorkdayIsWork ? .unassigned : .regular) : .off
        }
        let posts = raw.split(separator: "+").map { matcher.displayName(String($0)) }
        if posts.contains(where: isDuty) { return .duty }
        if posts.contains(where: { !isOff($0, matcher: matcher) && !isTrip($0) }) { return .regular }
        if posts.contains(where: isTrip) { return .trip }
        return .off   // 网站上写了休息、调休的，节假日里也算休息
    }

    /// 某人每一天的类别：法定节假日里，遥测后紧接着写了休息、调休的日子（最多 2 天）算值班调休；
    /// 平时的休息不管怎么来的都算休息。
    /// history：这个人全部的排班（用来看统计范围前一两天是不是遥测）。
    public static func kinds(of history: [DayKey: String], days: [DayKey], matcher: ShiftMatcher, rotating: Bool,
                             name: String? = nil, calendar: Calendar = .current) -> [DayKey: Kind] {
        let fixed = name.flatMap { overrides[$0] } ?? [:]
        var result = autoKinds(of: history, days: days, matcher: matcher, rotating: rotating, fixed: fixed, calendar: calendar)
        // 手动纠正优先
        if !fixed.isEmpty {
            for day in days {
                guard let value = fixed[day] else { continue }
                result[day] = value == excluded ? nil : (Kind(rawValue: value) ?? result[day])
            }
        }
        return result
    }

    /// fixed：手动纠正（改成值班 / 不是值班的日子，影响后面一天算不算值班调休）
    static func autoKinds(of history: [DayKey: String], days: [DayKey], matcher: ShiftMatcher, rotating: Bool,
                          fixed: [DayKey: String] = [:], calendar: Calendar) -> [DayKey: Kind] {
        var result: [DayKey: Kind] = [:]
        // 这个人在网站上第一次出现前两周、最后一次出现两个月以后（还没来、已经调走）没数据的日子不算。
        // 不轮组别的人可能好几周都不出现在表上（一直在做日常），所以往后放宽到两个月
        let keys = history.keys
        let active = keys.min().flatMap { lo in keys.max().map {
            lo.adding(days: -14, calendar: calendar)...$0.adding(days: activeAfter, calendar: calendar) } }
        for day in days {
            guard history[day] != nil || active?.contains(day) == true else { continue }
            result[day] = classify(history[day], workday: ChinaHolidays.isWorkday(day, calendar: calendar),
                                   holiday: ChinaHolidays.isHoliday(day), rotating: rotating, matcher: matcher)
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
        // 从统计范围前两天开始找遥测，往后接着的日子看算不算值班调休
        guard rules.holidayDutyRestCounts || rules.blankHolidayAfterDutyIsRest, let first = days.min(), let last = days.max() else { return result }
        var day = first.adding(days: -restPerDuty, calendar: calendar)
        while day <= last {
            if isDutyDay(day) {
                var next = day.adding(days: 1, calendar: calendar)
                // 节假日值完遥测的第二天：网站上没写岗位（没排班）也是值班后的休息，算工作量
                if rules.blankHolidayAfterDutyIsRest, history[next] == nil, result[next] != nil, ChinaHolidays.isHoliday(next) {
                    result[next] = .dutyRest
                }
                for _ in 0..<restPerDuty where rules.holidayDutyRestCounts && restPosts(next) {
                    if result[next] != nil, ChinaHolidays.isHoliday(next) { result[next] = .dutyRest }
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
        return roster.filter { $0.value.keys.contains(where: window.contains) }.map { name, history in
            var p = PersonWorkload(name: name, dutyDays: 0, dutyRestDays: 0, regularDays: 0, offDays: 0, holidayDays: 0,
                                   tripDays: 0, holidayWorkedDays: 0, posts: [:])
            let rotating = isRotating(name: name, history: history, members: members, matcher: matcher, asOf: last)
            let dayKinds = kinds(of: history, days: days, matcher: matcher, rotating: rotating, name: name, calendar: calendar)
            for day in days {
                for post in history[day]?.split(separator: "+") ?? [] { p.posts[matcher.displayName(String(post)), default: 0] += 1 }
                let holiday = ChinaHolidays.isHoliday(day)
                guard let kind = dayKinds[day] else { continue }
                switch kind {
                case .duty: p.dutyDays += 1; if holiday { p.holidayWorkedDays += 1 }
                case .dutyRest: p.dutyRestDays += 1
                case .regular: p.regularDays += 1; if holiday { p.holidayWorkedDays += 1 }
                case .trip: p.tripDays += 1
                case .holiday: p.holidayDays += 1
                case .off: p.offDays += 1
                case .unassigned: p.unassignedDays += 1
                }
            }
            return p
        }
    }
}
