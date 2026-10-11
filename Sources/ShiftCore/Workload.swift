import Foundation

/// 每个人一段时间（一般是一个月到今天）的工作量，每一天归到一类：
/// - 值班：遥测
/// - 日常：各组、调度等其它岗位；工作日（按法定节假日调整）没排岗位的日子
/// - 出差
/// - 节假日：中秋、国庆、春节、清明、五一等法定假日，网站上没排任何岗位的日子
/// - 休息：网站上写了休息、调休、请假、无分工的日子（节假日里也算休息），以及周末没排岗位的日子
/// 上班 = 值班 + 日常。
public struct PersonWorkload: Equatable {
    public var name: String
    /// 值班（遥测）天数
    public var dutyDays: Int
    /// 日常班天数：各组、调度等岗位，加上工作日没排岗位的日子
    public var regularDays: Int
    /// 休息：休息、调休、请假、无分工，周末没排岗位
    public var offDays: Int
    /// 法定节假日没上班的天数
    public var holidayDays: Int
    public var tripDays: Int
    /// 其中在法定节假日上班（值班或日常）的天数
    public var holidayWorkedDays: Int
    /// 各岗位天数（不含日常班）
    public var posts: [String: Int]

    /// 上班天数 = 值班 + 日常
    public var workDays: Int { dutyDays + regularDays }
}

public enum WorkloadCounter {
    /// 休息、调休、请假、无分工都不算上班。
    public static func isOff(_ post: String, matcher: ShiftMatcher) -> Bool {
        matcher.match(post)?.id == "off" || post.contains("休") || post.contains("假") || post == "无分工"
    }

    public static func isTrip(_ post: String) -> Bool { post.contains("出差") }

    /// 值班只有遥测
    public static func isDuty(_ post: String) -> Bool { post.contains("遥测") }

    /// 一天归到哪一类
    public enum Kind: String {
        case duty = "值班", regular = "日常", trip = "出差", holiday = "节假日", off = "休息"
    }

    /// raw：网站上这天的岗位（没排为 nil）
    public static func classify(_ raw: String?, workday: Bool, holiday: Bool, matcher: ShiftMatcher) -> Kind {
        guard let raw else { return workday ? .regular : (holiday ? .holiday : .off) }
        let posts = raw.split(separator: "+").map { matcher.displayName(String($0)) }
        if posts.contains(where: isDuty) { return .duty }
        if posts.contains(where: { !isOff($0, matcher: matcher) && !isTrip($0) }) { return .regular }
        if posts.contains(where: isTrip) { return .trip }
        return .off   // 网站上写了休息、调休的，节假日里也算休息
    }

    /// days：统计哪些日子（已读到全员排班的日子）；名单是全员排班里出现过的所有人。
    public static func count(roster: Roster, days: [DayKey], matcher: ShiftMatcher,
                             calendar: Calendar = .current) -> [PersonWorkload] {
        guard !days.isEmpty else { return [] }
        // 工作日：周一到周五，去掉法定假日，加上调休上班的周末
        let workdays = Set(days.filter { ChinaHolidays.isWorkday($0, calendar: calendar) })
        let holidays = Set(days.filter(ChinaHolidays.isHoliday))
        return roster.keys.map { name in
            var p = PersonWorkload(name: name, dutyDays: 0, regularDays: 0, offDays: 0, holidayDays: 0,
                                   tripDays: 0, holidayWorkedDays: 0, posts: [:])
            for day in days {
                let raw = roster[name]?[day]
                for post in raw?.split(separator: "+") ?? [] { p.posts[matcher.displayName(String(post)), default: 0] += 1 }
                let holiday = holidays.contains(day)
                switch classify(raw, workday: workdays.contains(day), holiday: holiday, matcher: matcher) {
                case .duty: p.dutyDays += 1; if holiday { p.holidayWorkedDays += 1 }
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
