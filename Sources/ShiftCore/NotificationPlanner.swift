import Foundation

public struct ClockTime: Hashable, Codable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public var text: String { String(format: "%02d:%02d", hour, minute) }
}

public struct PlannedNotification: Hashable {
    public var id: String
    public var day: DayKey
    public var time: ClockTime
    public var title: String
    public var body: String
    /// 语音播报的文字，例如「今天，组D」
    public var speech: String
}

/// 根据排班计算未来要发的本地通知。
/// iPhone 不允许 App 在后台定时联网，但允许提前登记“到点就弹”的本地通知，
/// 所以每次打开 App / 同步 / 修改排班后，都把接下来几周的提醒全部重新登记一遍。
public struct NotificationPlanner {
    public var morning: ClockTime?
    public var evening: ClockTime?
    /// 没有排班的日子是否也提醒（显示“未排班”）。
    public var notifyWhenEmpty: Bool
    public var matcher: ShiftMatcher
    public var calendar: Calendar
    /// 各组工作内容（「组D」→ 说明），有的话写进通知正文
    public var notes: [String: String] = [:]

    /// 每周日晚上预告下周一到周日的安排
    public var weekly = false

    /// iOS 最多保留 64 条待发通知，留一点余量。
    public static let maxPending = 60

    public init(morning: ClockTime?, evening: ClockTime?, notifyWhenEmpty: Bool,
                matcher: ShiftMatcher, calendar: Calendar = .current) {
        self.morning = morning
        self.evening = evening
        self.notifyWhenEmpty = notifyWhenEmpty
        self.matcher = matcher
        self.calendar = calendar
    }

    public func plan(schedule: [DayKey: String], now: Date, days: Int = 40) -> [PlannedNotification] {
        let today = DayKey(date: now, calendar: calendar)
        var result: [PlannedNotification] = []

        for offset in 0..<days {
            let day = today.adding(days: offset, calendar: calendar)
            if let t = morning, let n = make(kind: "morning", label: "今天", fireDay: day, aboutDay: day, time: t, schedule: schedule) {
                result.append(n)
            }
            if let t = evening, let n = make(kind: "evening", label: "明天", fireDay: day,
                                             aboutDay: day.adding(days: 1, calendar: calendar), time: t, schedule: schedule) {
                result.append(n)
            }
            if weekly, calendar.component(.weekday, from: day.date(calendar: calendar, hour: 12)) == 1,
               let w = weekMessage(on: day, schedule: schedule) {
                result.append(w)
            }
        }
        return result
            .filter { $0.day.date(calendar: calendar, hour: $0.time.hour, minute: $0.time.minute) > now }
            .sorted { ($0.day, $0.time.hour, $0.time.minute) < ($1.day, $1.time.hour, $1.time.minute) }
            .prefix(Self.maxPending)
            .map { $0 }
    }

    /// 某一天早上（今天的班）或晚上（明天的班）那条提醒的内容；不需要提醒时返回 nil。
    public func message(morning isMorning: Bool, on day: DayKey, schedule: [DayKey: String]) -> PlannedNotification? {
        isMorning
            ? make(kind: "morning", label: "今天", fireDay: day, aboutDay: day, time: morning ?? ClockTime(hour: 0, minute: 0), schedule: schedule)
            : make(kind: "evening", label: "明天", fireDay: day, aboutDay: day.adding(days: 1, calendar: calendar),
                   time: evening ?? ClockTime(hour: 0, minute: 0), schedule: schedule)
    }

    /// 下周预告：fireDay 当天（一般是周日）晚上发，列出之后 7 天的分工。一天都没有数据时返回 nil。
    public func weekMessage(on fireDay: DayKey, schedule: [DayKey: String]) -> PlannedNotification? {
        let days = (1...7).map { fireDay.adding(days: $0, calendar: calendar) }
        guard days.contains(where: { schedule[$0] != nil }) else { return nil }
        let lines = days.map { day -> String in
            let name = schedule[day].map(matcher.displayName) ?? "—"
            return "\(Self.dateText(day, calendar: calendar))  \(name)"
        }
        let first = days[0], last = days[6]
        return PlannedNotification(
            id: "shift-week-\(fireDay)",
            day: fireDay,
            time: evening ?? ClockTime(hour: 20, minute: 0),
            title: "🗓 下周安排（\(first.month)/\(first.day)–\(last.month)/\(last.day)）",
            body: lines.joined(separator: "\n"),
            speech: "下周安排已更新"
        )
    }

    private func make(kind: String, label: String, fireDay: DayKey, aboutDay: DayKey, time: ClockTime,
                      schedule: [DayKey: String]) -> PlannedNotification? {
        let raw = schedule[aboutDay]
        guard raw != nil || notifyWhenEmpty else { return nil }
        let name = raw.map(matcher.displayName) ?? "未排班"
        let emoji = raw.flatMap(matcher.match).map { $0.emoji + " " } ?? ""
        // 排班里写了更多工作内容（如 "白班 门诊二楼"）时，正文里显示原文
        var detail = raw.flatMap { $0.count > name.count ? "\n\($0)" : nil } ?? ""
        for part in name.split(separator: "+") {
            if let note = notes[String(part).filter { !$0.isWhitespace }.uppercased()] { detail += "\n\(part)：\(note)" }
        }
        return PlannedNotification(
            id: "shift-\(kind)-\(fireDay)",
            day: fireDay,
            time: time,
            title: "\(emoji)\(label)：\(name)",
            body: "\(Self.dateText(aboutDay, calendar: calendar))  \(name)\(detail)",
            speech: "\(label)，\(name.replacingOccurrences(of: "+", with: "和"))"
        )
    }

    public static func dateText(_ day: DayKey, calendar: Calendar = .current) -> String {
        let weekday = calendar.component(.weekday, from: day.date(calendar: calendar, hour: 12))
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return "\(day.month)月\(day.day)日 周\(names[weekday - 1])"
    }
}
