import EventKit
import UIKit

/// 把排班写进 iPhone「日历」App 里单独的「值班提醒」日历：每天一个全天事件（如「组D」）。
/// 只改动本版生成且带专属标记的事件；旧版和用户原有日程都保留。
@MainActor
enum CalendarSync {
    private static let store = EKEventStore()
    private static let calendarTitle = "值班提醒"
    // 独立于旧版 calendarSync.calendarID：旧版可能只是按同名认领，不能当作所有权凭据。
    private static let ownershipKey = "calendarSync.managed.v2"

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

    private static func calendar(create: Bool) -> (calendar: EKCalendar, ownership: CalendarEventOwnership)? {
        if let saved = UserDefaults.standard.object(forKey: ownershipKey) {
            guard let data = saved as? Data,
                  let ownership = try? JSONDecoder().decode(CalendarEventOwnership.self, from: data),
                  !ownership.calendarIdentifier.isEmpty else {
                lastError = "日历同步记录暂时无法读取，为保护原有日程，本次没有修改日历。"
                return nil
            }
            if let c = store.calendar(withIdentifier: ownership.calendarIdentifier) {
                guard c.allowsContentModifications else {
                    lastError = "之前创建的排班日历暂时不能编辑，请检查 iPhone 的日历账户设置。原有日程已保留。"
                    return nil
                }
                return (c, ownership)
            }
            if !create {
                lastError = "找不到之前创建的排班日历，本次没有清理日程。"
                return nil
            }
        }
        guard create else { return nil }
        // 依次试：默认日历所在的账户、iCloud、本机。谷歌、Exchange 这类账户往往不让新建日历，要换下一个
        var candidates: [EKSource] = []
        if let s = store.defaultCalendarForNewEvents?.source { candidates.append(s) }
        candidates += store.sources.filter { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
        candidates += store.sources.filter { $0.sourceType == .local }
        candidates += store.sources
        var tried = Set<String>()
        let sourceIDs = candidates.map(\.sourceIdentifier).filter { tried.insert($0).inserted }
        var creationError: Error?
        for sourceID in sourceIDs {
            guard let source = store.source(withIdentifier: sourceID) else { continue }
            let c = EKCalendar(for: .event, eventStore: store)
            c.title = calendarTitle
            c.cgColor = UIColor.systemBlue.cgColor
            c.source = source
            do {
                try store.saveCalendar(c, commit: true)
                let ownership = CalendarEventOwnership(calendarIdentifier: c.calendarIdentifier, ownerToken: UUID())
                let data = try JSONEncoder().encode(ownership)
                UserDefaults.standard.set(data, forKey: ownershipKey)
                lastError = nil
                return (c, ownership)
            } catch {
                creationError = error
                store.reset()
            }
        }
        lastError = "没法在 iPhone 日历里新建「\(calendarTitle)」日历。"
            + (creationError.map { $0.localizedDescription } ?? "请检查日历账户是否允许新建日历。")
        return nil
    }

    /// 让日历和排班一致：过去 2 周到未来约 2 个月，有排班的日子一个全天事件，没有的删掉。
    /// predicted：网站还没排、推算出来的日子（标题自己带「预测」），网站排出来后自动换成正式的
    static func sync(_ schedule: [DayKey: String], matcher: ShiftMatcher, predicted: [DayKey: String] = [:]) {
        lastError = nil
        guard authorized else { lastError = "没有日历的完全访问权限，本次未同步。"; return }
        guard let managed = calendar(create: true) else { return }
        let cal = managed.calendar
        let today = DayKey.today
        let first = today.adding(days: -14), last = today.adding(days: 62)
        let predicate = store.predicateForEvents(withStart: first.date(calendar: .app),
                                                 end: last.adding(days: 1).date(calendar: .app), calendars: [cal])
        do {
            var existing: [DayKey: EKEvent] = [:]
            for event in store.events(matching: predicate) {
                guard managed.ownership.managedDay(eventURL: event.url,
                                                   calendarIdentifier: event.calendar.calendarIdentifier) != nil else { continue }
                let day = DayKey(date: event.startDate, calendar: .app)
                guard day >= first && day <= last else { continue }
                if existing[day] == nil {
                    existing[day] = event
                } else {
                    try store.remove(event, span: .thisEvent, commit: false)
                }
            }

            var day = first
            while day <= last {
                let wanted = schedule[day].map(matcher.displayName) ?? predicted[day]
                switch (wanted, existing[day]) {
                case (nil, let event?):
                    try store.remove(event, span: .thisEvent, commit: false)
                case (let title?, let event?) where event.title != title:
                    event.title = title
                    try store.save(event, span: .thisEvent, commit: false)
                case (let title?, nil):
                    let event = EKEvent(eventStore: store)
                    event.calendar = cal
                    event.title = title
                    event.url = managed.ownership.eventURL(for: day)
                    event.isAllDay = true
                    event.startDate = day.date(calendar: .app)
                    event.endDate = day.date(calendar: .app, hour: 23, minute: 59)
                    try store.save(event, span: .thisEvent, commit: false)
                default:
                    break
                }
                day = day.adding(days: 1)
            }
            try store.commit()
        } catch {
            store.reset()
            lastError = "日历同步未完成，原有日程已保留：\(error.localizedDescription)"
        }
    }

    /// 关闭只清理近期本版生成的事件；不删除日历、旧事件或管理记录，重新开启时继续使用。
    static func removeRecentManagedEvents() {
        lastError = nil
        guard authorized else { lastError = "已停止同步，但没有日历权限，未能清理近期排班。"; return }
        guard let managed = calendar(create: false) else { return }
        let today = DayKey.today
        let first = today.adding(days: -14), last = today.adding(days: 62)
        let predicate = store.predicateForEvents(withStart: first.date(calendar: .app),
                                                 end: last.adding(days: 1).date(calendar: .app), calendars: [managed.calendar])
        do {
            for event in store.events(matching: predicate) {
                guard managed.ownership.managedDay(eventURL: event.url,
                                                   calendarIdentifier: event.calendar.calendarIdentifier) != nil else { continue }
                let day = DayKey(date: event.startDate, calendar: .app)
                guard day >= first && day <= last else { continue }
                try store.remove(event, span: .thisEvent, commit: false)
            }
            try store.commit()
        } catch {
            store.reset()
            lastError = "已停止同步，但近期排班未能清理完成：\(error.localizedDescription)"
        }
    }
}
