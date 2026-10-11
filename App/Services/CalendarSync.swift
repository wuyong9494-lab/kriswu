import EventKit
import UIKit

/// 把排班写进 iPhone「日历」App 里单独的「值班提醒」日历：每天一个全天事件（如「组D」）。
/// 只动这个日历里的事件，不碰其它日程。
@MainActor
enum CalendarSync {
    private static let store = EKEventStore()
    private static let calendarTitle = "值班提醒"
    private static let idKey = "calendarSync.calendarID"

    static var authorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) { return status == .fullAccess }
        return status == .authorized
    }

    static func requestAccess() async -> Bool {
        if authorized { return true }
        if #available(iOS 17.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        }
        return (try? await store.requestAccess(to: .event)) ?? false
    }

    /// 上次同步失败的原因（设置、诊断页显示）
    static var lastError: String?

    private static func calendar(create: Bool) -> EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: idKey), let c = store.calendar(withIdentifier: id) {
            return c
        }
        if let c = store.calendars(for: .event).first(where: { $0.title == calendarTitle && $0.allowsContentModifications }) {
            UserDefaults.standard.set(c.calendarIdentifier, forKey: idKey)
            return c
        }
        guard create else { return nil }
        // 依次试：默认日历所在的账户、iCloud、本机。谷歌、Exchange 这类账户往往不让新建日历，要换下一个
        var candidates: [EKSource] = []
        if let s = store.defaultCalendarForNewEvents?.source { candidates.append(s) }
        candidates += store.sources.filter { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
        candidates += store.sources.filter { $0.sourceType == .local }
        candidates += store.sources
        var tried = Set<String>()
        for source in candidates where tried.insert(source.sourceIdentifier).inserted {
            let c = EKCalendar(for: .event, eventStore: store)
            c.title = calendarTitle
            c.cgColor = UIColor.systemBlue.cgColor
            c.source = source
            if (try? store.saveCalendar(c, commit: true)) != nil {
                UserDefaults.standard.set(c.calendarIdentifier, forKey: idKey)
                lastError = nil
                return c
            }
        }
        lastError = "没法在 iPhone 日历里新建「\(calendarTitle)」日历（各个账户都不允许）"
        return nil
    }

    /// 让日历和排班一致：过去 2 周到未来约 2 个月，有排班的日子一个全天事件，没有的删掉。
    static func sync(_ schedule: [DayKey: String], matcher: ShiftMatcher) {
        guard authorized, let cal = calendar(create: true) else { return }
        let today = DayKey.today
        let first = today.adding(days: -14), last = today.adding(days: 62)
        let predicate = store.predicateForEvents(withStart: first.date(calendar: .app),
                                                 end: last.adding(days: 1).date(calendar: .app), calendars: [cal])
        var existing: [DayKey: EKEvent] = [:]
        for event in store.events(matching: predicate) {
            let day = DayKey(date: event.startDate, calendar: .app)
            if existing[day] == nil {
                existing[day] = event
            } else {
                try? store.remove(event, span: .thisEvent, commit: false)   // 同一天重复的
            }
        }

        var day = first
        while day <= last {
            let wanted = schedule[day].map(matcher.displayName)
            switch (wanted, existing[day]) {
            case (nil, let event?):
                try? store.remove(event, span: .thisEvent, commit: false)
            case (let title?, let event?) where event.title != title:
                event.title = title
                try? store.save(event, span: .thisEvent, commit: false)
            case (let title?, nil):
                let event = EKEvent(eventStore: store)
                event.calendar = cal
                event.title = title
                event.isAllDay = true
                event.startDate = day.date(calendar: .app)
                event.endDate = day.date(calendar: .app, hour: 23, minute: 59)
                try? store.save(event, span: .thisEvent, commit: false)
            default:
                break
            }
            day = day.adding(days: 1)
        }
        try? store.commit()
    }

    /// 关掉同步时删除整个「值班提醒」日历。
    static func removeCalendar() {
        guard authorized, let cal = calendar(create: false) else { return }
        try? store.removeCalendar(cal, commit: true)
        UserDefaults.standard.removeObject(forKey: idKey)
    }
}
