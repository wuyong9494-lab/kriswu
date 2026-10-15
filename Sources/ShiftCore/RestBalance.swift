import Foundation

/// 人名后面括号里的待休天数（「张三(5)」）：按日期记下来，并说明每次变化前后排了什么。
public enum RestBalanceHistory {
    private static let nameWithNumber = try! NSRegularExpression(
        pattern: #"([\x{4e00}-\x{9fa5}][\x{4e00}-\x{9fa5}·・•]{1,18})\s*[（(]\s*([0-9０-９]{1,3})\s*[)）]"#)

    /// 电脑版周表的文字（每行一天，格子里「张三(5)」）：人名 → 日期 → 那天表上写的待休天数。
    public static func fromTable(_ text: String, reference: DayKey, matcher: ShiftMatcher) -> [String: [DayKey: Int]] {
        let dates = DateTokenParser(reference: reference)
        var result: [String: [DayKey: Int]] = [:]
        for row in ScheduleParser.splitRows(text) {
            // 和全员排班一样：日期在前两列、格子里只有日期
            guard let col = row.prefix(2).firstIndex(where: { dates.parse($0) != nil && $0.trimmingCharacters(in: .whitespaces).count <= 16 }),
                  let day = dates.parse(row[col]) else { continue }
            for (i, cell) in row.enumerated() where i != col {
                let ns = cell as NSString
                for m in nameWithNumber.matches(in: cell, range: NSRange(location: 0, length: ns.length)) {
                    let name = ns.substring(with: m.range(at: 1))
                    let digits = ns.substring(with: m.range(at: 2))
                    guard RosterExtractor.looksLikeName(name), !RosterExtractor.isPost(name, matcher: matcher),
                          let n = Int(digits.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? digits) else { continue }
                    result[name, default: [:]][day] = n
                }
            }
        }
        return result
    }

    public typealias Point = (day: DayKey, value: Int, live: Bool)

    /// 合并新旧记录，按日期排好，只留数字变了的点（第一天也留）。
    /// live：同步时当场读到的数字（true），还是从以前几周的表上读的（false）。
    /// 表上读的不会覆盖当场读到的：有的网站翻到以前几周显示的也是现在的数字。
    public static func merge(_ old: [Point], _ new: [DayKey: Int], live: Bool, limit: Int = 400) -> [Point] {
        var all: [DayKey: (value: Int, live: Bool)] = [:]
        for p in old { all[p.day] = (p.value, p.live) }
        for (day, value) in new where live || all[day]?.live != true { all[day] = (value, live) }
        var result: [Point] = []
        for day in all.keys.sorted() where result.last?.value != all[day]!.value {
            result.append((day, all[day]!.value, all[day]!.live))
        }
        return Array(result.suffix(limit))
    }

    /// 以前几周的表上每个人的数字都一模一样：网站显示的是现在的数字，不是当时的，不能当历史用。
    public static func looksLikeSnapshot(_ byDay: [String: [DayKey: Int]]) -> Bool {
        let people = byDay.values.filter { days in
            guard let lo = days.keys.min(), let hi = days.keys.max() else { return false }
            return hi.adding(days: -14, calendar: .dayMath) >= lo
        }
        guard people.count >= 3 else { return false }
        return people.allSatisfy { Set($0.values).count == 1 }
    }

    /// 一次变化：从 from 天变成 to 天，以及上一次记录之后到这天之间排的遥测、休息、调休、请假、出差。
    public struct Step: Equatable {
        public var day: DayKey
        public var from: Int
        public var to: Int
        public var since: DayKey
        public var events: [Event]
        public var delta: Int { to - from }
    }

    public struct Event: Equatable {
        public var day: DayKey
        public var post: String
        /// 法定节假日 / 周末（工作日为 nil）
        public var tag: String?
    }

    /// points：按日期排好的待休记录；history：这个人的排班。最新的变化在前。
    public static func steps(points: [Point], history: [DayKey: String], matcher: ShiftMatcher,
                             calendar: Calendar = .current) -> [Step] {
        guard points.count >= 2 else { return [] }
        var steps: [Step] = []
        for i in 1..<points.count {
            let prev = points[i - 1], cur = points[i]
            guard prev.value != cur.value else { continue }
            // 往前多看两天：周末、节假日的遥测常常过一两天才加上
            let start = prev.day.adding(days: -2, calendar: calendar)
            var events: [Event] = []
            var day = start
            while day <= cur.day {
                if let raw = history[day] {
                    let posts = raw.split(separator: "+").map { matcher.displayName(String($0)) }
                    let relevant = posts.filter {
                        WorkloadCounter.isDuty($0) || WorkloadCounter.isOff($0, matcher: matcher) || WorkloadCounter.isTrip($0)
                            || $0.contains("加班")
                    }
                    if !relevant.isEmpty {
                        let tag = ChinaHolidays.isHoliday(day) ? "节假日"
                            : (ChinaHolidays.isWorkday(day, calendar: calendar) ? nil : "周末")
                        events.append(Event(day: day, post: relevant.joined(separator: "+"), tag: tag))
                    }
                }
                day = day.adding(days: 1, calendar: calendar)
            }
            steps.append(Step(day: cur.day, from: prev.value, to: cur.value, since: prev.day, events: events))
        }
        return steps.reversed()
    }
}
