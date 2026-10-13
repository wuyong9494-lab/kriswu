import Foundation

/// 微信推送（PushPlus）、到点的微信提醒、日报 / 周报 / 月报、全员变动推送
@MainActor
extension AppStore {
    // MARK: - 微信

    /// 发到微信；失败只记录原因，不影响其它功能。
    @discardableResult
    func pushToWeChat(title: String, content: String, force: Bool = false) async -> Bool {
        guard !Self.isDemo, settings.weChatEnabled || force else { return false }
        do {
            try await WeChatPush.send(title: title, content: content, token: Keychain.get(.pushPlusToken) ?? "")
            settings.weChatMessage = "上次微信推送成功：\(Date().formatted(date: .omitted, time: .shortened))"
            return true
        } catch {
            settings.weChatMessage = "微信推送失败：\(error.localizedDescription)"
            return false
        }
    }

    /// iPhone 不能准点在后台运行，所以每天的微信提醒在 App 有机会运行时补发：
    /// 过了早上提醒时间、今天还没发过 → 发「今天」；过了晚上提醒时间 → 发「明天」。
    /// 早上那条过了晚上提醒时间就不再补发。
    /// 排班变动的微信通知：发成功才清掉，没发出去（网络、后台时间到了）下次 App 运行时补发
    func sendPendingWeChatChange() async {
        // 已经有一次在发了就不重复发同一条
        guard settings.weChatEnabled, !isSendingWeChatChange, let pending = settings.pendingWeChatChange else { return }
        isSendingWeChatChange = true
        defer { isSendingWeChatChange = false }
        let parts = pending.text.split(separator: "\n", maxSplits: 1).map(String.init)
        if await pushToWeChat(title: parts[0], content: parts.count > 1 ? parts[1] : ""),
           settings.pendingWeChatChange == pending {
            // 发送途中又来了新的变动就留着，下次再发
            settings.pendingWeChatChange = nil
        }
    }

    /// 全员谁和谁换了班：记下来；关注的同事以后的班变了就通知
    func recordTeamChanges(before: Roster, days: Set<DayKey>) async {
        let found = RosterDiff.changes(before: before, after: roster, days: days, matcher: matcher)
        guard !found.isEmpty else { return }
        var log = settings.teamChanges
        // 同一天同一岗位只和最近记下的那条比，一样就不重复记（换过去又换回来再换过去也能记上）
        for c in found {
            let latest = log.filter { $0.day == c.day && $0.post == c.post }.max { $0.detected < $1.detected }
            if latest.map({ $0.from == c.from && $0.to == c.to }) != true { log.insert(c, at: 0) }
        }
        settings.teamChanges = Array(log.sorted { ($0.detected, $0.day) > ($1.detected, $1.day) }.prefix(500))
        let today = DayKey.today
        let watched = found.filter { c in c.day >= today && settings.favorites.contains(where: c.involves) }
        if settings.notifyFavorites, !watched.isEmpty {
            let body = watched.map { "\($0.day.dateText) \($0.summary)" }.joined(separator: "\n")
            await NotificationService.notifyNow(id: "favorites-\(UUID().uuidString)", title: "⭐ 关注的同事排班有变", body: body,
                                                route: "teamChanges")
        }
    }

    /// 全员排班有变动（今天及以后的日子，别人的；自己的另有提醒）：一次同步发一条通知，开了微信推送也发微信
    /// published：合并前已经正式排班的日子。网站新排出的一周（之前只有请假记录）不算变动，不然每周都会来一大串
    func notifyRosterEdits(_ edits: [RosterEdit], published: Set<DayKey>) async {
        guard !Self.isDemo, settings.notifyAllChanges else { return }
        let today = DayKey.today
        // 关注的同事另有「⭐」提醒，这里不再重复
        let upcoming = edits.filter { e in
            e.day >= today && published.contains(e.day) && !isMe(e.name)
                && !(settings.notifyFavorites && isFavorite(e.name))
        }.sorted { ($0.day, $0.name) < ($1.day, $1.name) }
        guard !upcoming.isEmpty else { return }
        func show(_ raw: String?) -> String { raw.map(matcher.displayName) ?? "没排" }
        var lines = upcoming.prefix(8).map { "\($0.day.month)/\($0.day.day) \($0.name)：\(show($0.old)) → \(show($0.new))" }
        if upcoming.count > 8 { lines.append("等 \(upcoming.count) 处，打开 App 看「变动历史」") }
        let title = "📋 全员排班有 \(upcoming.count) 处变动"
        let body = lines.joined(separator: "\n")
        await NotificationService.notifyNow(id: "roster-edits-\(UUID().uuidString)", title: title, body: body, route: "rosterLog")
        if settings.weChatEnabled && settings.weChatChanges && settings.weChatTeam {
            _ = await pushToWeChat(title: title, content: body)
        }
    }

    /// 每月 1 号起第一次运行时，把上个月全员工作量发到微信
    func sendMonthlyReportIfDue() async {
        guard settings.monthlyReport, settings.weChatEnabled else { return }
        let today = DayKey.today
        let key = String(format: "%04d-%02d", today.year, today.month)
        // 第一次（刚升级、刚打开）不补发上个月的，从下个月 1 号开始
        guard let last = settings.lastMonthlyReport else { settings.lastMonthlyReport = key; return }
        guard last != key else { return }
        // 先记上，免得同时运行两次发两遍；没发出去再改回来
        settings.lastMonthlyReport = key
        let (y, m) = today.month == 1 ? (today.year - 1, 12) : (today.year, today.month - 1)
        let report = workload(year: y, month: m)
        guard !report.people.isEmpty else { settings.lastMonthlyReport = last; return }
        let balance = WorkloadBalance.analyze(roster: roster, days: report.days, matcher: matcher, tolerance: 3,
                                              members: rotationMembers, calendar: .app)
        var lines = ["\(y)年\(m)月（\(report.days.count) 天）工作量从多到少："]
        lines += report.people.map { p in
            "\(p.name)：\(p.workDays) 天（遥测 \(p.dutyDays)，休息 \(p.offDays)）" + (settings.restBalance[p.name].map { "，待休 \($0)" } ?? "")
        }
        if !balance.rows.isEmpty { lines.append("\n有组别的人：\(balance.verdict)。" + balance.findings.joined(separator: "；")) }
        let sent = await pushToWeChat(title: "📊 \(m)月工作量月报", content: lines.joined(separator: "\n"))
        if !sent { settings.lastMonthlyReport = last }
    }

    /// 每周一（这周第一次运行时）把上周的管理摘要发到微信：遥测、工作量最多、待休最多、该休没休
    func sendWeeklyDigestIfDue() async {
        guard settings.weeklyDigest, settings.weChatEnabled, role != .user, !Self.isDemo else { return }
        var cal = Calendar.app
        cal.firstWeekday = 2
        let now = Date()
        let key = "\(cal.component(.yearForWeekOfYear, from: now))-W\(cal.component(.weekOfYear, from: now))"
        // 第一次（刚打开开关）不补发，从下周一开始
        guard let last = settings.lastWeeklyDigest else { settings.lastWeeklyDigest = key; return }
        guard last != key, let thisMonday = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return }
        settings.lastWeeklyDigest = key
        let monday = DayKey(date: thisMonday, calendar: cal).adding(days: -7)
        let days = (0..<7).map { monday.adding(days: $0) }
        let people = WorkloadCounter.count(roster: roster, days: days, matcher: matcher, members: rotationMembers, calendar: .app)
        guard !people.isEmpty else { settings.lastWeeklyDigest = last; return }
        func short(_ d: DayKey) -> String { "\(d.month)/\(d.day)" }
        var lines: [String] = []
        // 遥测
        let duty = days.compactMap { d -> String? in
            let names = roster.filter { $0.value[d].map { SchedulePatterns.isDutyPost($0, matcher: matcher) } ?? false }.keys.sorted()
            return names.isEmpty ? nil : "\(short(d)) \(names.joined(separator: "、"))"
        }
        if !duty.isEmpty { lines.append("【遥测】" + duty.joined(separator: "；")) }
        // 工作量最多
        let top = people.sorted { $0.workDays > $1.workDays }.prefix(5).map { "\($0.name) \($0.workDays) 天" }
        lines.append("【工作量最多】" + top.joined(separator: "，"))
        // 待休最多
        let rest = settings.restBalance.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key) \($0.value) 天" }
        if !rest.isEmpty { lines.append("【待休最多】" + rest.joined(separator: "，")) }
        // 网站标了该休没休（上周一以后）
        let from = monday.description
        let noRest = settings.siteNoRestFlags.filter { $0 >= from }.map { flag -> String in
            let parts = flag.split(separator: "|").map(String.init)
            guard parts.count == 3, let d = DayKey(string: parts[0]) else { return flag }
            return "\(parts[1]) \(short(d))（\(parts[2])）"
        }
        if !noRest.isEmpty { lines.append("【该休没休】" + noRest.joined(separator: "，")) }
        let sent = await pushToWeChat(title: "📋 上周值班摘要（\(short(days[0]))–\(short(days[6]))）", content: lines.joined(separator: "\n"))
        if !sent { settings.lastWeeklyDigest = last }
    }

    /// 每周第一次运行时（周一起）给自己发一条小结通知；开了微信推送也发到微信
    func sendPersonalWeeklyIfDue() async {
        guard settings.personalWeekly, !Self.isDemo, let me = myRosterName else { return }
        var cal = Calendar.app
        cal.firstWeekday = 2
        let now = Date()
        let key = "\(cal.component(.yearForWeekOfYear, from: now))-W\(cal.component(.weekOfYear, from: now))"
        guard let last = settings.lastPersonalWeekly else { settings.lastPersonalWeekly = key; return }
        guard last != key, let thisMonday = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return }
        let monday = DayKey(date: thisMonday, calendar: cal)
        let lastWeek = (0..<7).map { monday.adding(days: $0 - 7) }
        guard let mine = WorkloadCounter.count(roster: roster, days: lastWeek, matcher: matcher,
                                               members: rotationMembers, calendar: .app).first(where: { $0.name == me }) else { return }
        settings.lastPersonalWeekly = key
        var lines = ["上周上了 \(mine.workDays) 天" + (mine.dutyDays > 0 ? "，其中遥测 \(mine.dutyDays) 次" : "") + "。"]
        if let rest = settings.restBalance[me], rest > 0 { lines.append("还有 \(rest) 天待休。") }
        let week = (0..<7).map { monday.adding(days: $0) }.compactMap { d -> String? in
            guard let raw = shift(on: d) else { return nil }
            return "\(d.weekdayText)\(matcher.displayName(raw))"
        }
        if !week.isEmpty { lines.append("这周：" + week.joined(separator: "，") + "。") }
        if let turn = myDutyTurn(), let day = turn.day, day >= monday {
            lines.append((turn.scheduled ? "下次遥测：" : "下次遥测（推算）：约 ") + "\(day.dateText)（\(day.weekdayText)）。")
        }
        let title = "🗓️ 你的一周小结"
        let body = lines.joined(separator: "\n")
        await NotificationService.notifyNow(id: "personal-weekly", title: title, body: body)
        if settings.weChatEnabled { _ = await pushToWeChat(title: title, content: body) }
    }

    func sendDueWeChatReminders() async {
        await sendPendingWeChatChange()
        await sendPersonalWeeklyIfDue()
        await sendMonthlyReportIfDue()
        await sendWeeklyDigestIfDue()
        guard settings.weChatEnabled, settings.weChatDaily else { return }
        let now = Date()
        let today = DayKey.today
        let p = planner
        func time(_ t: ClockTime) -> Date { today.date(calendar: .app, hour: t.hour, minute: t.minute) }

        // 还没有这天的数据就先不记「已发」，同步拿到数据后再发；
        // 有内容时先记下「已发」防止重复，发送失败再改回去，下次 App 运行时重发
        if settings.eveningEnabled, now >= time(settings.evening), settings.weChatEveningSent != today {
            if let m = p.message(morning: false, on: today, schedule: reminderSchedule) {
                let before = (settings.weChatEveningSent, settings.weChatMorningSent)
                settings.weChatEveningSent = today
                settings.weChatMorningSent = today
                if !(await pushToWeChat(title: m.title, content: m.body)) {
                    (settings.weChatEveningSent, settings.weChatMorningSent) = before
                }
            }
        } else if settings.morningEnabled, now >= time(settings.morning), settings.weChatMorningSent != today {
            if let m = p.message(morning: true, on: today, schedule: reminderSchedule) {
                let before = settings.weChatMorningSent
                settings.weChatMorningSent = today
                if !(await pushToWeChat(title: m.title, content: m.body)) {
                    settings.weChatMorningSent = before
                }
            }
        }
        // 周日晚上：下周安排
        if settings.weeklyPreview, now >= time(settings.eveningEnabled ? settings.evening : ClockTime(hour: 20, minute: 0)),
           Calendar.app.component(.weekday, from: now) == 1, settings.weChatWeekSent != today,
           let w = p.weekMessage(on: today, schedule: reminderSchedule) {
            let before = settings.weChatWeekSent
            settings.weChatWeekSent = today
            if !(await pushToWeChat(title: w.title, content: w.body)) {
                settings.weChatWeekSent = before
            }
        }
    }

    /// 立即把下周（从明天起 7 天）的安排发到微信，供快捷指令调用。
    func sendWeChatWeek() async -> String {
        guard !(Keychain.get(.pushPlusToken) ?? "").isEmpty else {
            return "还没有设置 PushPlus token：打开值班提醒 › 设置 › 微信推送"
        }
        let today = DayKey.today
        let before = settings.weChatWeekSent
        settings.weChatWeekSent = today
        if canSync { await syncWithin(seconds: 15, source: "快捷指令（下周）") }
        guard let w = planner.weekMessage(on: today, schedule: reminderSchedule) else {
            let ok = await pushToWeChat(title: "🗓 接下来一周：暂无排班数据",
                                        content: "没有取到接下来一周的排班（\(settings.lastSyncMessage ?? "还没同步过")）。", force: true)
            // 没数据时让 App 之后有了数据再补发
            settings.weChatWeekSent = before
            return ok ? "已发送到微信：暂无排班数据" : (settings.weChatMessage ?? "微信推送失败")
        }
        let ok = await pushToWeChat(title: w.title, content: w.body, force: true)
        if !ok { settings.weChatWeekSent = before }
        return ok ? "已发送到微信：\(w.title)" : (settings.weChatMessage ?? "微信推送失败")
    }

    /// 立即把今天（morning）或明天的分工发到微信，供快捷指令自动化准点调用。返回给用户看的结果。
    func sendWeChatReminder(morning: Bool) async -> String {
        guard !(Keychain.get(.pushPlusToken) ?? "").isEmpty else {
            return "还没有设置 PushPlus token：打开值班提醒 › 设置 › 微信推送"
        }
        let today = DayKey.today
        let label = morning ? "今天" : "明天"
        // 先同步再发，但最多等 15 秒：快捷指令有时间限制，同步太慢就用手上的数据先发，别让提醒丢了
        if canSync { await syncWithin(seconds: 15, source: "快捷指令（微信）") }
        let m = planner.message(morning: morning, on: today, schedule: reminderSchedule)
        // 仍然没有也照样发一条，免得以为推送坏了
        let title = m?.title ?? "\(label)：暂无排班数据"
        let body = m?.body ?? "没有取到\(label)的排班（\(settings.lastSyncMessage ?? "还没同步过")）。打开值班提醒下拉刷新一下。"
        let ok = await pushToWeChat(title: title, content: body, force: true)
        // 发出去了才记「已发」，App 之后运行时就不会再补发同一条
        if ok {
            settings.weChatMorningSent = today
            if !morning { settings.weChatEveningSent = today }
        }
        return ok ? "已发送到微信：\(title)" : (settings.weChatMessage ?? "微信推送失败")
    }

    /// 同步，但最多等 seconds 秒；超时就先返回（同步自己继续在后台做完）。
    func syncWithin(seconds: Double, source: String) async {
        final class Once { var done = false }
        let once = Once()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                _ = await self.sync(full: false, source: source)
                if !once.done { once.done = true; c.resume() }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if !once.done { once.done = true; c.resume() }
            }
        }
    }

    /// 下一次该发微信提醒的时间，用来请求系统在那之后尽快唤醒 App。
    var nextWeChatReminder: Date? {
        guard settings.weChatEnabled, settings.weChatDaily else { return nil }
        let now = Date()
        let times = [settings.morningEnabled ? settings.morning : nil, settings.eveningEnabled ? settings.evening : nil].compactMap { $0 }
        var candidates = [DayKey.today, DayKey.today.adding(days: 1)]
            .flatMap { day in times.map { day.date(calendar: .app, hour: $0.hour, minute: $0.minute) } }
        // 周日的下周预告（晚上提醒关掉时按 20:00）
        if settings.weeklyPreview {
            let t = settings.eveningEnabled ? settings.evening : ClockTime(hour: 20, minute: 0)
            for day in [DayKey.today, DayKey.today.adding(days: 1)]
            where Calendar.app.component(.weekday, from: day.date(calendar: .app, hour: 12)) == 1 {
                candidates.append(day.date(calendar: .app, hour: t.hour, minute: t.minute))
            }
        }
        return candidates.filter { $0 > now }.min()
    }

}
