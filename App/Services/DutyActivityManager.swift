import ActivityKit
import UIKit

/// 值遥测（工作到第二天接班时间，默认 8:30）时在锁屏显示倒计时。
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
        let handover = AppStore.shared.settings.dutyStart
        func isDuty(_ day: DayKey) -> Bool {
            schedule[day].map { WorkloadCounter.isDuty(matcher.displayName($0)) } ?? false
        }
        let yesterday = today.adding(days: -1, calendar: cal)
        let day: DayKey
        if isDuty(yesterday), now < today.date(calendar: cal, hour: handover.hour, minute: handover.minute) {
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
        // 「值班交接前」「调休」也算休息；出差不算
        while rest.count < 3, let raw = schedule[d], SchedulePatterns.isRestDay(raw, matcher: matcher) {
            rest.append(d)
            d = d.adding(days: 1, calendar: cal)
        }
        // 锁屏上的字不会每分钟更新：用「次日」（值班那天的下一天），过了零点也不会错说成「明天」
        let after = rest.isEmpty
            ? "次日 \(handover.text) 下班" + (schedule[next].map { "，次日：\(matcher.displayName($0))" } ?? "")
            : "下班后休息：" + rest.map(\.dateText).joined(separator: "、")
        // 这天的清单（交接前看一眼还差什么）
        let tasks = AppStore.shared.liveTaskRecord(on: day)
        return Target(day: day, post: matcher.displayName(schedule[day] ?? "遥测"),
                      state: .init(start: day.date(calendar: cal, hour: handover.hour, minute: handover.minute),
                                   end: next.date(calendar: cal, hour: handover.hour, minute: handover.minute), after: after,
                                   tasksDone: tasks?.done.count, tasksTotal: tasks?.total, nextTask: tasks?.todo.first))
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
        // 你划掉了就不再弹出来；系统显示满 8 小时收起后，再打开 App 时重新显示（夜里那段也能看到）
        let dayKey = "dutyActivityShownDay", timeKey = "dutyActivityShownAt"
        guard let target, !showing, UIApplication.shared.applicationState == .active else { return }
        if UserDefaults.standard.string(forKey: dayKey) == target.day.description,
           let shown = UserDefaults.standard.object(forKey: timeKey) as? Date,
           Date().timeIntervalSince(shown) < 8 * 3600 { return }
        UserDefaults.standard.set(target.day.description, forKey: dayKey)
        UserDefaults.standard.set(Date(), forKey: timeKey)
        _ = try? Activity.request(attributes: DutyAttributes(day: target.day.description, post: target.post),
                                  content: ActivityContent(state: target.state, staleDate: target.state.end),
                                  pushType: nil)
    }
}
