import Foundation

/// 把推算遥测要用的数据导出成一个 JSON，交给开发者分析网站到底怎么排遥测。
/// 人名全部换成代号（P01、P02…），岗位文字里出现的人名也换掉；不含组别说明、公告、网址、账号。
public enum RotationExport {
    public struct Person: Codable, Equatable {
        public var code: String
        /// 是不是我自己
        public var me: Bool
        /// 网站人员表：研发岗 / 生产岗、参不参加值班、哪几天能值遥测（1 = 周一 … 7 = 周日）
        public var category: String?
        public var onDuty: Bool?
        public var telemetryWeekdays: [Int]?
        /// 现在的待休天数、待休的变化记录（yyyy-MM-dd → 天数）
        public var restNow: Int?
        public var restHistory: [String: Int]
    }

    public struct Day: Codable, Equatable {
        public var date: String
        /// 1 = 周一 … 7 = 周日
        public var weekday: Int
        public var workday: Bool
        public var holiday: Bool
        /// 网站正式排了班（不只是请假记录）
        public var published: Bool
        /// 网站标了「固定」（手动指定）遥测
        public var fixedTelemetry: Bool
        /// 代号 → 这天的岗位
        public var posts: [String: String]
    }

    public struct File: Codable, Equatable {
        public var version = 1
        public var generated: String
        public var people: [Person]
        public var days: [Day]
    }

    public static func make(roster: Roster, from: DayKey, to: DayKey, published: Set<DayKey>, fixedDays: Set<DayKey>,
                            people: [String: SiteAPI.Person], restHistory: [String: [DayKey: Int]], restNow: [String: Int],
                            me: String?, matcher: ShiftMatcher, calendar: Calendar, today: DayKey) -> File {
        // 这段时间排班里出现过的人，加上网站人员表里的人；按名字排好编号，同一份文件里代号不变
        let inRange = roster.filter { $0.value.keys.contains { $0 >= from && $0 <= to } }.keys
        let names = Set(inRange).union(people.keys).sorted()
        let width = max(2, String(names.count).count)
        var codes: [String: String] = [:]
        for (i, name) in names.enumerated() {
            let n = String(i + 1)
            codes[name] = "P" + String(repeating: "0", count: max(0, width - n.count)) + n
        }
        // 岗位文字里偶尔带人名（「组A（替张三）」）：长名字先换，免得「张三丰」被换成「P01丰」
        let byLength = names.sorted { $0.count > $1.count }
        func scrub(_ text: String) -> String {
            byLength.reduce(text) { t, name in t.replacingOccurrences(of: name, with: codes[name] ?? "") }
        }

        let list = names.map { name -> Person in
            let p = people[name]
            return Person(code: codes[name] ?? "", me: name == me, category: p?.category, onDuty: p?.onDuty,
                          telemetryWeekdays: p?.telemetryWeekdays.map { $0.sorted() },
                          restNow: restNow[name] ?? p?.unrestDays,
                          restHistory: Dictionary(uniqueKeysWithValues: (restHistory[name] ?? [:]).map { ($0.key.description, $0.value) }))
        }

        var days: [Day] = []
        var day = from
        while day <= to {
            var posts: [String: String] = [:]
            for name in names {
                guard let raw = roster[name]?[day], let code = codes[name] else { continue }
                posts[code] = scrub(matcher.displayName(raw))
            }
            days.append(Day(date: day.description, weekday: SiteAPI.siteWeekday(day, calendar: calendar),
                            workday: ChinaHolidays.isWorkday(day, calendar: calendar), holiday: ChinaHolidays.isHoliday(day),
                            published: published.contains(day), fixedTelemetry: fixedDays.contains(day), posts: posts))
            day = day.adding(days: 1, calendar: calendar)
        }
        return File(generated: today.description, people: list, days: days)
    }

    public static func encode(_ file: File) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(file)
    }
}
