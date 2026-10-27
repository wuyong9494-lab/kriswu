import Foundation

/// 组别任务清单：勾选、存档（工作留痕里看）、通知上「清单全部做完」
@MainActor
extension AppStore {
    // MARK: - 组别任务清单

    func taskKey(_ day: DayKey, _ group: String) -> String { "\(day.description)|\(group)" }

    func isTaskDone(_ day: DayKey, _ group: String, _ item: String) -> Bool {
        settings.taskChecks[taskKey(day, group)]?.contains(item) ?? false
    }

    func toggleTask(_ day: DayKey, _ group: String, _ item: String) {
        var s = settings
        let key = taskKey(day, group)
        var done = s.taskChecks[key] ?? []
        if let i = done.firstIndex(of: item) { done.remove(at: i) } else { done.append(item) }
        s.taskChecks[key] = done.isEmpty ? nil : done
        // 勾选只留最近两周；做完了哪些另外存档（工作留痕里看）
        let cutoff = DayKey.today.adding(days: -14).description
        s.taskChecks = s.taskChecks.filter { $0.key.prefix(10) >= cutoff }
        archiveTasks(on: day, into: &s)
        settings = s
        tasksChanged()
    }

    /// 这天各组清单的事项（两条以上才算清单，和今天页一样）
    func taskItems(on day: DayKey) -> [(group: String, key: String)] {
        notes(for: shift(on: day)).flatMap { n -> [(group: String, key: String)] in
            let items = TaskList.items(from: n.note)
            guard items.count > 1 else { return [] }
            return items.enumerated().map { (n.group, TaskChecklistCard.key($0.offset, $0.element)) }
        }
    }

    /// 按现在的清单和勾选，这天做了哪些、还差哪些（这天没有清单时为 nil）
    func liveTaskRecord(on day: DayKey, checks: [String: [String]]? = nil) -> TaskDayRecord? {
        let checks = checks ?? settings.taskChecks
        var done: [String] = [], todo: [String] = []
        for n in notes(for: shift(on: day)) {
            let items = TaskList.items(from: n.note)
            guard items.count > 1 else { continue }
            let checked = checks[taskKey(day, n.group)] ?? []
            for (i, item) in items.enumerated() {
                if checked.contains(TaskChecklistCard.key(i, item)) { done.append(item) } else { todo.append(item) }
            }
        }
        guard done.count + todo.count > 0 else { return nil }
        return TaskDayRecord(shift: shift(on: day).map(matcher.displayName), done: done, todo: todo)
    }

    /// 这天的清单情况：勾过的用存档（当时的清单），没勾过的按现在的清单
    func taskRecord(on day: DayKey) -> TaskDayRecord? {
        records.taskHistory[day.description] ?? liveTaskRecord(on: day)
    }

    /// 勾了清单就存一份这天的情况（存在 records.json）；一件都没勾就不存。只留一年。
    private func archiveTasks(on day: DayKey, into s: inout AppSettings) {
        let record = liveTaskRecord(on: day, checks: s.taskChecks)
        var history = records.taskHistory
        history[day.description] = record.flatMap { $0.done.isEmpty ? nil : $0 }
        if history.count > 370 {
            history = TaskDayRecord.pruned(history, keepingFrom: DayKey.today.adding(days: -366))
        }
        records.taskHistory = history
    }

    /// 勾选变了：提醒不用重排，只刷新小组件和锁屏上的值班倒计时
    private func tasksChanged() {
        guard !Self.isDemo else { return }
        updateWidget()
        DutyActivityManager.update(schedule: mySchedule, matcher: matcher, enabled: settings.liveActivity)
    }

    /// 通知上点了「清单全部做完」
    func markAllTasksDone(on day: DayKey) {
        var s = settings
        for (group, items) in Dictionary(grouping: taskItems(on: day), by: \.group) {
            s.taskChecks[taskKey(day, group)] = items.map(\.key)
        }
        archiveTasks(on: day, into: &s)
        settings = s
        tasksChanged()
        flushSave(wait: true)
    }
}
