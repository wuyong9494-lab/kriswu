import Foundation

/// 每个人一段时间（一般是一个月到今天）的工作量，每一天归到一类：
/// - 值班：遥测（工作到第二天 8:30）
/// - 值班调休：遥测后紧接着的休息、调休（最多 2 天）。这是值班换来的，算工作量
/// - 日常：各组、调度等其它岗位；工作日（按法定节假日调整）没排岗位的日子
/// - 出差
/// - 节假日：中秋、国庆、春节、清明、五一等法定假日，网站上没排任何岗位的日子
/// - 休息：其它写了休息、调休、请假、无分工的日子，以及周末没排岗位的日子
/// 工作量 = 值班 + 值班调休 + 日常。
public struct PersonWorkload: Equatable {
    public var name: String
    /// 值班（遥测）天数
    public var dutyDays: Int
    /// 值班后的调休天数（算工作量）
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

    /// 工作量 = 值班 + 值班调休 + 日常
    public var workDays: Int { dutyDays + dutyRestDays + regularDays }
}

public enum WorkloadCounter {
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

    /// 一天归到哪一类
    public enum Kind: String {
        case duty = "值班", dutyRest = "值班调休", regular = "日常", trip = "出差", holiday = "节假日", off = "休息"
    }

    /// 不看前后日子时这一天的类别（raw：网站上这天的岗位，没排为 nil）
    public static func classify(_ raw: String?, workday: Bool, holiday: Bool, matcher: ShiftMatcher) -> Kind {
        guard let raw else { return workday ? .regular : (holiday ? .holiday : .off) }
        let posts = raw.split(separator: "+").map { matcher.displayName(String($0)) }
        if posts.contains(where: isDuty) { return .duty }
        if posts.contains(where: { !isOff($0, matcher: matcher) && !isTrip($0) }) { return .regular }
        if posts.contains(where: isTrip) { return .trip }
        return .off   // 网站上写了休息、调休的，节假日里也算休息
    }

    /// 某人每一天的类别：遥测后紧接着写了休息、调休的日子（最多 2 天）算值班调休。
    /// history：这个人全部的排班（用来看统计范围前一两天是不是遥测）。
    public static func kinds(of history: [DayKey: String], days: [DayKey], matcher: ShiftMatcher,
                             calendar: Calendar = .current) -> [DayKey: Kind] {
        var result: [DayKey: Kind] = [:]
        for day in days {
            result[day] = classify(history[day], workday: ChinaHolidays.isWorkday(day, calendar: calendar),
                                   holiday: ChinaHolidays.isHoliday(day), matcher: matcher)
        }
        func restPosts(_ day: DayKey) -> Bool {
            guard let raw = history[day] else { return false }
            let posts = raw.split(separator: "+").map { matcher.displayName(String($0)) }
            return !posts.contains(where: { !isOff($0, matcher: matcher) && !isTrip($0) }) && posts.contains(where: isRest)
        }
        func isDutyDay(_ day: DayKey) -> Bool {
            history[day]?.split(separator: "+").contains { isDuty(matcher.displayName(String($0))) } ?? false
        }
        // 从统计范围前两天开始找遥测，往后接着的休息算调休
        guard let first = days.min(), let last = days.max() else { return result }
        var day = first.adding(days: -restPerDuty, calendar: calendar)
        while day <= last {
            if isDutyDay(day) {
                var next = day.adding(days: 1, calendar: calendar)
                for _ in 0..<restPerDuty where restPosts(next) {
                    if result[next] != nil { result[next] = .dutyRest }
                    next = next.adding(days: 1, calendar: calendar)
                }
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return result
    }

    /// days：统计哪些日子（已读到全员排班的日子）；名单是全员排班里出现过的所有人。
    public static func count(roster: Roster, days: [DayKey], matcher: ShiftMatcher,
                             calendar: Calendar = .current) -> [PersonWorkload] {
        guard !days.isEmpty else { return [] }
        return roster.map { name, history in
            var p = PersonWorkload(name: name, dutyDays: 0, dutyRestDays: 0, regularDays: 0, offDays: 0, holidayDays: 0,
                                   tripDays: 0, holidayWorkedDays: 0, posts: [:])
            let dayKinds = kinds(of: history, days: days, matcher: matcher, calendar: calendar)
            for day in days {
                for post in history[day]?.split(separator: "+") ?? [] { p.posts[matcher.displayName(String(post)), default: 0] += 1 }
                let holiday = ChinaHolidays.isHoliday(day)
                switch dayKinds[day] ?? .off {
                case .duty: p.dutyDays += 1; if holiday { p.holidayWorkedDays += 1 }
                case .dutyRest: p.dutyRestDays += 1
                case .regular: p.regularDays += 1; if holiday { p.holidayWorkedDays += 1 }
                case .trip: p.tripDays += 1
                case .holiday: p.holidayDays += 1
                case .off: p.offDays += 1
                }
            }
            return p
        }
    }
}
