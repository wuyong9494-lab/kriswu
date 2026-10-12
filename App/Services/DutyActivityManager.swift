import ActivityKit
import UIKit

/// 值遥测（工作到第二天 8:30）时在锁屏显示倒计时。
/// iPhone 只允许 App 在前台时开始实时活动：值班那天打开一次 App 就会出现；系统最多显示约 8 小时，过后再打开 App 会重新显示。
@MainActor
enum DutyActivityManager {
    struct Target {
        var day: DayKey
        var post: String
        var state: DutyAttributes.ContentState
    }

    /// 现在正在值（或今天要值）的遥测
    static func current(schedule: [DayKey: String], matcher: ShiftMatcher, now: Date = Date()) -> Target? {
        let cal = Calendar.app
        let today = DayKey(date: now, calendar: cal)
        func isDuty(_ day: DayKey) -> Bool {
            schedule[day].map { WorkloadCounter.isDuty(matcher.displayName($0)) } ?? false
        }
        let yesterday = today.adding(days: -1, calendar: cal)
        let day: DayKey
        if isDuty(yesterday), now < today.date(calendar: cal, hour: 8, minute: 30) {
            day = yesterday
        } else if isDuty(today) {
            day = today
        } else {
            return nil
        }
        let next = day.adding(days: 1, calendar: cal)
        // 下班后接着的休息、调休
        var rest: [DayKey] = []
        var d = next
        while rest.count < 3, let raw = schedule[d], matcher.match(raw)?.id == "off" {
            rest.append(d)
            d = d.adding(days: 1, calendar: cal)
        }
        let after = rest.isEmpty
            ? "明天 8:30 下班" + (schedule[next].map { "，明天：\(matcher.displayName($0))" } ?? "")
            : "下班后休息：" + rest.map(\.dateText).joined(separator: "、")
        return Target(day: day, post: matcher.displayName(schedule[day] ?? "遥测"),
                      state: .init(start: day.date(calendar: cal, hour: 8, minute: 30),
                                   end: next.date(calendar: cal, hour: 8, minute: 30), after: after))
    }

    static func update(schedule: [DayKey: String], matcher: ShiftMatcher, enabled: Bool) {
        let target = enabled && ActivityAuthorizationInfo().areActivitiesEnabled
            ? current(schedule: schedule, matcher: matcher) : nil
        var showing = false
        for activity in Activity<DutyAttributes>.activities {
            if let target, activity.attributes.day == target.day.description, activity.activityState == .active {
                showing = true
                if activity.content.state != target.state {
                    Task { await activity.update(ActivityContent(state: target.state, staleDate: target.state.end)) }
                }
            } else {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
        guard let target, !showing, UIApplication.shared.applicationState == .active else { return }
        _ = try? Activity.request(attributes: DutyAttributes(day: target.day.description, post: target.post),
                                  content: ActivityContent(state: target.state, staleDate: target.state.end),
                                  pushType: nil)
    }
}
