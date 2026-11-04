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
        guard await pushToWeChat(title: parts[0], content: parts.count > 1 ? parts[1] : "") else { return }
        if settings.pendingWeChatChange == pending {
            settings.pendingWeChatChange = nil
        } else if let current = settings.pendingWeChatChange, parts.count > 1, current.text.hasSuffix("\n" + parts[1]) {
            // 发送途中又来了新的变动、和这条合在了一起：这条已经发出去了，只留新的
            settings.pendingWeChatChange = ChangeLogEntry(date: current.date, text: String(current.text.dropLast(parts[1].count + 1)))
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
        // 和我对换的同事：我自己的「排班有更新」里已经写了（「组A原来是某某」），这里不再重复一条
        func posts(_ raw: String?) -> Set<String> { Set(raw.map { matcher.posts($0).map(matcher.displayName) } ?? []) }
        let mine = Dictionary(edits.filter { isMe($0.name) }.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        func swappedWithMe(_ e: RosterEdit) -> Bool {
            guard settings.notifyChanges, let my = mine[e.day] else { return false }
            // 他让出来的正是我新接的，或者他新接的正是我让出来的
            let myAdded = posts(my.new).subtracting(posts(my.old)), myRemoved = posts(my.old).subtracting(posts(my.new))
            let hisAdded = posts(e.new).subtracting(posts(e.old)), hisRemoved = posts(e.old).subtracting(posts(e.new))
            return !hisRemoved.isDisjoint(with: myAdded) || !hisAdded.isDisjoint(with: myRemoved)
        }
        // 关注的同事另有「⭐」提醒，这里不再重复
        let upcoming = edits.filter { e in
            e.day >= today && published.contains(e.day) && !isMe(e.name)
                && !(settings.notifyFavorites && isFavorite(e.name)) && !swappedWithMe(e)
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
        // 月报里是全员的名字：开了「同事的…也发到微信」才发
        guard settings.monthlyReport, settings.weChatEnabled, settings.weChatTeam, !Self.isDemo else { return }
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
        // 轮组别的人：上了多少天班，其中多少天网站上没给排岗位
        let members = report.people.filter(\.isGroupMember)
        if !members.isEmpty {
            lines.append("\n轮组别的人（上班 / 其中没排班）：" + members.map { "\($0.name) \($0.presentDays)/\($0.blankWorkDays)" }.joined(separator: "，"))
        }
        let sent = await pushToWeChat(title: "📊 \(m)月工作量月报", content: lines.joined(separator: "\n"))
        if !sent { settings.lastMonthlyReport = last }
    }

    /// 每周一（这周第一次运行时）把上周的管理摘要发到微信：遥测、工作量最多、待休最多、该休没休
    func sendWeeklyDigestIfDue() async {
        guard settings.weeklyDigest, settings.weChatEnabled, settings.weChatTeam, role != .user, !Self.isDemo else { return }
        var cal = Calendar.app
        cal.firstWeekday = 2
        let now = Date()
        let key = WeChatSchedule.weekKey(now, calendar: .app)
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
        let noRest = DigestText.noRestLines(settings.siteNoRestFlags, from: monday)
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
        let key = WeChatSchedule.weekKey(now, calendar: .app)
        guard let last = settings.lastPersonalWeekly else { settings.lastPersonalWeekly = key; return }
        guard last != key, let thisMonday = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return }
        let monday = DayKey(date: thisMonday, calendar: cal)
        let lastWeek = (0..<7).map { monday.adding(days: $0 - 7) }
        guard let mine = WorkloadCounter.count(roster: roster, days: lastWeek, matcher: matcher,
                                               members: rotationMembers, calendar: .app).first(where: { $0.name == me }) else { return }
        settings.lastPersonalWeekly = key
        let week = (0..<7).map { monday.adding(days: $0) }.compactMap { d -> String? in
            guard let raw = shift(on: d) else { return nil }
            return "\(d.weekdayText)\(matcher.displayName(raw))"
        }
        let turn = myDutyTurn()
        let next = turn?.day.flatMap { $0 >= monday ? "\($0.dateText)（\($0.weekdayText)）" : nil }
        let title = "🗓️ 你的一周小结"
        let body = DigestText.personalWeekly(workDays: mine.workDays, dutyDays: mine.dutyDays, rest: settings.restBalance[me],
                                             week: week, nextDuty: next, nextDutyScheduled: turn?.scheduled ?? true)
        await NotificationService.notifyNow(id: "personal-weekly", title: title, body: body)
        if settings.weChatEnabled { _ = await pushToWeChat(title: title, content: body) }
    }

    func sendDueWeChatReminders() async {
        await sendPendingWeChatChange()
        await sendPersonalWeeklyIfDue()
        await sendMonthlyReportIfDue()
        await sendWeeklyDigestIfDue()
        guard !Task.isCancelled, settings.weChatEnabled, settings.weChatDaily else { return }
        let now = Date()
        let today = DayKey.today
        let due = WeChatSchedule.dailyDue(now: now, today: today,
                                          morning: settings.morningEnabled ? settings.morning : nil,
                                          evening: settings.eveningEnabled ? settings.evening : nil,
                                          morningSent: settings.weChatMorningSent, eveningSent: settings.weChatEveningSent,
                                          calendar: .app)
        // 自动补发和快捷指令共用内存占位；网络成功、有数据之后才记「已发」。
        if due == .evening {
            _ = await deliverWeChatReminder(.evening, on: today, force: false, synchronize: false)
        } else if due == .morning {
            _ = await deliverWeChatReminder(.morning, on: today, force: false, synchronize: false)
        }
        // 周日晚上：下周安排
        let weekDay = DayKey.today
        if !Task.isCancelled, settings.weChatEnabled, settings.weChatDaily, settings.weeklyPreview,
           WeChatSchedule.weekPreviewDue(now: Date(), today: weekDay, evening: settings.eveningEnabled ? settings.evening : nil,
                                         sent: settings.weChatWeekSent, calendar: .app) {
            _ = await deliverWeChatReminder(.week, on: weekDay, force: false, synchronize: false)
        }
    }

    /// 立即把下周（从明天起 7 天）的安排发到微信，供快捷指令调用。
    func sendWeChatWeek() async -> String {
        guard !(Keychain.get(.pushPlusToken) ?? "").isEmpty else {
            return "还没有设置 PushPlus token：打开值班提醒 › 设置 › 微信推送"
        }
        switch await deliverWeChatReminder(.week, on: .today, force: true, synchronize: true) {
        case .sent(let title, let hasData): return "已发送到微信：\(hasData ? title : "暂无排班数据")"
        case .alreadySent: return "今天已经发过下周安排了"
        case .inProgress: return "下周安排正在发送，请稍候"
        case .stopped: return "发送已取消或配置已变化，未记录为已发"
        case .failed: return settings.weChatMessage ?? "微信推送失败"
        case .noData: return "接下来一周暂无排班数据"
        }
    }

    /// 立即把今天（morning）或明天的分工发到微信，供快捷指令自动化准点调用。返回给用户看的结果。
    func sendWeChatReminder(morning: Bool) async -> String {
        guard !(Keychain.get(.pushPlusToken) ?? "").isEmpty else {
            return "还没有设置 PushPlus token：打开值班提醒 › 设置 › 微信推送"
        }
        let label = morning ? "今天" : "明天"
        switch await deliverWeChatReminder(morning ? .morning : .evening, on: .today, force: true, synchronize: true) {
        case .sent(let title, _): return "已发送到微信：\(title)"
        case .alreadySent: return "\(label)的分工今天已经发过微信了"
        case .inProgress: return "\(label)的分工正在发送，请稍候"
        case .stopped: return "发送已取消或配置已变化，未记录为已发"
        case .failed: return settings.weChatMessage ?? "微信推送失败"
        case .noData: return "\(label)暂无排班数据"
        }
    }

    private enum ReminderDelivery {
        case sent(title: String, hasData: Bool)
        case alreadySent, inProgress, stopped, failed, noData
    }

    private var weChatReminderIdentity: WeChatReminderGate.Identity {
        .init(aliases: settings.aliases, sourceURL: settings.sourceURL, sourceUsername: settings.sourceUsername,
              recipientToken: Keychain.get(.pushPlusToken) ?? "")
    }

    private var weChatReminderSentDates: WeChatReminderGate.SentDates {
        .init(morning: settings.weChatMorningSent, evening: settings.weChatEveningSent, week: settings.weChatWeekSent)
    }

    /// 领取占位后再同步，避免 App 自动补发与快捷指令重入；任何早退都会释放自己的占位。
    private func deliverWeChatReminder(_ kind: WeChatReminderGate.Kind, on day: DayKey,
                                      force: Bool, synchronize: Bool) async -> ReminderDelivery {
        guard !Self.isDemo, !Task.isCancelled, force || (settings.weChatEnabled && settings.weChatDaily) else { return .stopped }
        let identity = weChatReminderIdentity
        let sent = weChatReminderSentDates
        if sent.contains(kind, on: day) { return .alreadySent }
        guard let request = weChatReminderGate.begin(kind, on: day, identity: identity, sent: sent) else { return .inProgress }
        defer { weChatReminderGate.abandon(request) }
        if synchronize, canSync {
            await syncWithin(seconds: 15, source: kind == .week ? "快捷指令（下周）" : "快捷指令（微信）")
        }
        guard !Self.isDemo, !Task.isCancelled, identity == weChatReminderIdentity, day == .today else { return .stopped }
        // 等待期间另一种提醒可能已经完成（例如晚提醒成功后不再补早提醒）。
        if weChatReminderSentDates.contains(kind, on: day) { return .alreadySent }
        let message: PlannedNotification?
        switch kind {
        case .morning: message = planner.message(morning: true, on: day, schedule: reminderSchedule)
        case .evening: message = planner.message(morning: false, on: day, schedule: reminderSchedule)
        case .week: message = planner.weekMessage(on: day, schedule: reminderSchedule)
        }
        guard message != nil || force else { return .noData }
        let label = kind == .morning ? "今天" : "明天"
        let fallbackTitle = kind == .week ? "🗓 接下来一周：暂无排班数据" : "\(label)：暂无排班数据"
        let fallbackBody = kind == .week
            ? "没有取到接下来一周的排班（\(settings.lastSyncMessage ?? "还没同步过")）。"
            : "没有取到\(label)的排班（\(settings.lastSyncMessage ?? "还没同步过")）。打开值班提醒下拉刷新一下。"
        let title = message?.title ?? fallbackTitle
        let body = message?.body ?? fallbackBody
        let succeeded: Bool
        let failure: String?
        do {
            // 使用领取时的 token，不能在 await 后把旧身份的内容送到新配置的目标。
            try await WeChatPush.send(title: title, content: body, token: identity.recipientToken)
            succeeded = true
            failure = nil
        } catch {
            succeeded = false
            failure = error.localizedDescription
        }
        let currentIdentity = weChatReminderIdentity
        let currentDay = DayKey.today
        let cancelled = Task.isCancelled || Self.isDemo
        let committed = weChatReminderGate.finish(request, succeeded: succeeded, hasData: message != nil,
                                                  cancelled: cancelled, currentIdentity: currentIdentity,
                                                  currentDay: currentDay, sent: weChatReminderSentDates)
        guard !cancelled, identity == currentIdentity, day == currentDay else { return .stopped }
        if let committed {
            settings.weChatMorningSent = committed.morning
            settings.weChatEveningSent = committed.evening
            settings.weChatWeekSent = committed.week
        }
        settings.weChatMessage = succeeded
            ? "上次微信推送成功：\(Date().formatted(date: .omitted, time: .shortened))"
            : "微信推送失败：\(failure ?? "未知错误")"
        return succeeded ? .sent(title: title, hasData: message != nil) : .failed
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
        // 周日的下周预告也算（晚上提醒关掉时按 20:00）
        return WeChatSchedule.nextReminder(now: Date(), today: .today,
                                           morning: settings.morningEnabled ? settings.morning : nil,
                                           evening: settings.eveningEnabled ? settings.evening : nil,
                                           weeklyPreview: settings.weeklyPreview, calendar: .app)
    }

}
