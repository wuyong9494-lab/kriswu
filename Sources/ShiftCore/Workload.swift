import Foundation

/// 每个人一个月的工作量。
/// 只有「遥测」算值班；各组、调度等其它岗位，和工作日（周一到周五）没写在任何岗位上的日子，都算日常班。
/// 出差、休息（调休、请假、无分工）另外统计。
public struct PersonWorkload: Equatable {
    public var name: String
    /// 值班（遥测）天数
    public var dutyDays: Int
    /// 日常班天数：各组、调度等岗位，加上工作日没排岗位的日子
    public var regularDays: Int
    /// 休息、调休、请假、无分工
    public var offDays: Int
    public var tripDays: Int
    /// 各岗位天数（不含日常班）
    public var posts: [String: Int]
}

public enum WorkloadCounter {
    /// 休息、调休、请假、无分工都不算上班。
    public static func isOff(_ post: String, matcher: ShiftMatcher) -> Bool {
        matcher.match(post)?.id == "off" || post.contains("休") || post.contains("假") || post == "无分工"
    }

    public static func isTrip(_ post: String) -> Bool { post.contains("出差") }

    /// 值班只有遥测
    public static func isDuty(_ post: String) -> Bool { post.contains("遥测") }

    /// days：统计哪些日子（已读到全员排班的日子）；名单是全员排班里出现过的所有人。
    public static func count(roster: Roster, days: [DayKey], matcher: ShiftMatcher,
                             calendar: Calendar = .current) -> [PersonWorkload] {
        let weekdays = Set(days.filter {
            let w = calendar.component(.weekday, from: $0.date(calendar: calendar, hour: 12))
            return w != 1 && w != 7
        })
        return roster.keys.compactMap { name in
            var p = PersonWorkload(name: name, dutyDays: 0, regularDays: 0, offDays: 0, tripDays: 0, posts: [:])
            for day in days {
                guard let raw = roster[name]?[day] else {
                    if weekdays.contains(day) { p.regularDays += 1 }
                    continue
                }
                let posts = raw.split(separator: "+").map { matcher.displayName(String($0)) }
                for post in posts { p.posts[post, default: 0] += 1 }
                if posts.contains(where: isDuty) {
                    p.dutyDays += 1
                } else if posts.contains(where: { !isOff($0, matcher: matcher) && !isTrip($0) }) {
                    p.regularDays += 1
                } else if posts.contains(where: isTrip) {
                    p.tripDays += 1
                } else {
                    p.offDays += 1
                }
            }
            return p.dutyDays + p.regularDays + p.offDays + p.tripDays > 0 ? p : nil
        }
    }
}
