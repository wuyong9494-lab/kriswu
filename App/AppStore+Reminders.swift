import UIKit

/// 提醒、主屏幕图标、小组件：排班一变就按这里重排
@MainActor
extension AppStore {
    // MARK: - 提醒

    var planner: NotificationPlanner {
        var p = NotificationPlanner(
            morning: settings.morningEnabled ? settings.morning : nil,
            evening: settings.eveningEnabled ? settings.evening : nil,
            // 还没取到数据的日子不提醒；排了班但没给我排的日子由 reminderSchedule 补「未排班」
            notifyWhenEmpty: false,
            matcher: matcher,
            calendar: .app)
        p.weekly = settings.weeklyPreview
        p.memos = Dictionary(uniqueKeysWithValues: settings.dayMemos.compactMap { k, v in DayKey(string: k).map { ($0, v) } })
        p.dutyStart = settings.dutyStart
        p.dutyLeadMinutes = settings.dutyLeadMinutes
        return p
    }

    /// 提醒用的排班：已经取到数据、但没给我排班的日子补上「未排班」，这样每天都会提醒。
    var reminderSchedule: [DayKey: String] {
        var s = mySchedule
        let today = DayKey.today
        // 网站还没排到的日子不提醒「未排班」
        if settings.remindUnassigned {
            for day in covered where day >= today && s[day] == nil && isCovered(day) { s[day] = "未排班" }
        }
        return s
    }

    /// 发数传计划的提醒（没开就取消）
    func schedulePlanReminder() async {
        await NotificationService.schedulePlanReminder(at: settings.passPlanReminder && !Self.isDemo ? settings.passPlanReminderTime : nil,
                                                       sentDay: settings.passPlanSentDay)
    }

    func performReschedule() async {
        // 小组件、日历要用「下次遥测」：先在后台算好，下面直接取
        await warmRotation()
        // 手机上的通知带上组别工作内容；微信那份不带（只发自己的分工）
        var local = planner
        local.notes = groupNotes
        await NotificationService.reschedule(local.plan(schedule: reminderSchedule, now: Date()), voice: settings.voiceEnabled)
        updateWidget()
        updateAppIcon()
        let mine = mySchedule
        DutyActivityManager.update(schedule: mine, matcher: matcher, enabled: settings.liveActivity)
        if settings.calendarSync {
            var predicted: [DayKey: String] = [:]
            if let turn = myDutyTurn(), !turn.scheduled, let day = turn.day, mine[day] == nil { predicted[day] = "遥测（预测）" }
            CalendarSync.sync(mine, matcher: matcher, predicted: predicted)
        }
        // 值遥测那天早上的闹钟（iOS 26 起；关着就全部取消）
        if DutyAlarms.isSupported {
            var alarms: [(date: Date, title: String)] = []
            if settings.dutyAlarm {
                let today = DayKey.today
                for offset in 0..<14 {
                    let day = today.adding(days: offset)
                    guard DayRules.parts(mine[day], matcher: matcher).contains(.duty) else { continue }
                    let t = settings.dutyAlarmTime
                    alarms.append((day.date(calendar: .app, hour: t.hour, minute: t.minute),
                                   "今天值遥测，\(settings.dutyStart.text) 接班"))
                }
            }
            await DutyAlarms.reschedule(alarms)
        }
        await scheduleMeetingReminder()
        await schedulePlanReminder()
        await NotificationService.scheduleSigningReminder(expiry: SigningInfo.expirationDate)
        // App 一直没机会运行（后台刷新被系统停掉）时，到点由系统弹出提醒
        await NotificationService.scheduleStaleReminder(after: canSync ? settings.lastSync : nil)
    }

    /// 今天该用哪个图标：遥测「遥」，组A–组E 用对应字母（一天多个组取第一个），调度「调」，出差「差」，
    /// 无分工/休息/调休/请假「休」，其它用默认的「值」。
    func iconName(for raw: String?) -> String? { ShiftIcon.name(for: raw, matcher: matcher) }

    /// 今天该用的图标（nil = 默认的「值」）
    var wantedAppIcon: String? { settings.dynamicIcon ? iconName(for: shift(on: .today)) : nil }

    /// iPhone 只允许 App 在前台时换图标，每次换系统会弹一个「已更改图标」的提示。
    /// 刚回到前台的一瞬间换，系统偶尔会报「暂时不可用」：隔一秒再试，最多再试两次
    func updateAppIcon(retries: Int = 2) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.applicationState == .active else { return }
        let wanted = wantedAppIcon
        guard app.alternateIconName != wanted else { appIconError = nil; return }
        app.setAlternateIconName(wanted) { error in
            Task { @MainActor in
                let store = AppStore.shared
                store.appIconError = error?.localizedDescription
                guard error != nil, retries > 0 else { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                store.updateAppIcon(retries: retries - 1)
            }
        }
    }

    /// 诊断页用：图标名换成看得懂的字
    static func iconTitle(_ name: String?) -> String {
        guard let name else { return "值（默认）" }
        switch name {
        case "IconDuty": return "遥"
        case "IconDispatch": return "调"
        case "IconTrip": return "差"
        case "IconRest": return "休"
        default: return name.hasPrefix("Icon") ? String(name.dropFirst(4)) : name
        }
    }

    /// 把昨天到未来一个月的分工写给主屏幕小组件。
    func updateWidget() {
        // 演示的虚构数据不写给小组件（手机上原来的小组件内容留着）
        guard !Self.isDemo else { return }
        // 小组件上勾过、App 还没合并的先合并，免得后台刷新时用旧的勾选把小组件上的勾冲掉
        applyPendingTaskToggles()
        let today = DayKey.today
        let days = (-1...31).compactMap { offset -> WidgetDay? in
            let day = today.adding(days: offset)
            guard let raw = shift(on: day) else {
                // 取到过、但没给我排班
                return isCovered(day) ? WidgetDay(date: day.description, title: "未排班", emoji: "", colorHex: "#8E8E93") : nil
            }
            let type = matcher.match(raw)
            return WidgetDay(date: day.description, title: matcher.displayName(raw),
                             emoji: type?.emoji ?? "📌", colorHex: type?.colorHex ?? "#8E8E93")
        }
        // 下次遥测：和今天页同一个结果（网站排好的，或者按顺序推算的），小组件不再自己另算
        let turn = myDutyTurn()
        // 明天的清单也写上：过了零点 App 还没打开时，小组件直接显示新一天的清单
        WidgetStore.save(WidgetSnapshot(days: days, updated: Date(),
                                        tasks: widgetTasks(for: today) + widgetTasks(for: today.adding(days: 1)),
                                        nextDuty: turn?.day?.description, nextDutyPredicted: turn.map { !$0.scheduled },
                                        lastSync: settings.lastSync,
                                        restBalance: myRosterName.flatMap { settings.restBalance[$0] },
                                        teamDuty: teamDutyForWidget(from: today)))
    }

    /// 昨天到 7 天后，每天谁值遥测
    private func teamDutyForWidget(from today: DayKey) -> [String: String] {
        var result: [String: String] = [:]
        for offset in -1...7 {
            let day = today.adding(days: offset)
            let names = dayRoster(day).filter { WorkloadCounter.isDuty($0.post) }.flatMap(\.names)
            if !names.isEmpty { result[day.description] = names.joined(separator: "、") }
        }
        return result
    }

    /// 今天组别的任务清单（和首页「今天要做」一样）
    func widgetTasks(for day: DayKey) -> [WidgetTask] {
        notes(for: shift(on: day)).flatMap { g -> [WidgetTask] in
            let items = TaskList.items(from: g.note)
            guard items.count > 1 else { return [] }
            return items.enumerated().map { i, item in
                let key = TaskChecklistCard.key(i, item)
                return WidgetTask(day: day.description, group: g.group, key: key, title: item,
                                  done: isTaskDone(day, g.group, key))
            }
        }
    }

    /// 小组件上勾过的任务合并进来
    func applyPendingTaskToggles() {
        let pending = PendingTaskToggles.load()
        guard !pending.isEmpty else { return }
        PendingTaskToggles.clear()
        for item in pending {
            guard let day = DayKey(string: item.day), isTaskDone(day, item.group, item.key) != item.done else { continue }
            toggleTask(day, item.group, item.key)
        }
    }
}
