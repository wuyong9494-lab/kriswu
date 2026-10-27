import UserNotifications

enum NotificationService {
    private static var center: UNUserNotificationCenter { .current() }
    private static let prefix = "shift-"

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    static func pendingCount() async -> Int {
        await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }.count
    }

    /// 删除旧的提醒，按最新排班重新登记。到点由系统直接弹出，App 不需要在后台运行。
    /// voice = true 时，通知铃声换成读出「今天，组D」的语音。
    @MainActor
    static func reschedule(_ plan: [PlannedNotification], voice: Bool) async {
        // 先把通知内容（包括录语音，比较慢）全部准备好，再一次性替换旧提醒，
        // 避免中途被系统挂起时旧提醒已删、新提醒还没登记完
        var voiceFiles = Set<String>()
        var requests: [UNNotificationRequest] = []
        // 图标跟着班次换时：通知左边的大图用那天的班（App 没打开过时图标还是旧的，见 ShiftNotificationAvatar）
        let store = AppStore.shared
        let avatars = store.settings.dynamicIcon
        if avatars { await ShiftNotificationAvatar.clearDonations() }
        for n in plan {
            let content = UNMutableNotificationContent()
            content.title = n.title
            content.body = n.body
            content.sound = .default
            if voice, let file = await VoiceSound.file(for: n.speech) {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(file))
                voiceFiles.insert(file)
            }
            content.threadIdentifier = "shift"
            // 点提醒直接打开说的那一天（晚上的提醒说的是明天）
            // 接班前提醒（「前一天晚上」那种是在前一天响）：id 里就是要值班的那天
            var about = n.id.hasPrefix("shift-evening") ? n.day.adding(days: 1) : n.day
            if n.id.hasPrefix("shift-lead-"), let d = DayKey(string: String(n.id.dropFirst("shift-lead-".count))) { about = d }
            content.userInfo = ["route": "day:\(about)"]
            // 值遥测的提醒：勿扰、睡眠专注时也弹出（「时效性通知」，在系统设置里每个专注模式可以单独关掉）
            if store.settings.dutyTimeSensitive,
               n.id.hasPrefix("shift-lead-") || DayRules.parts(store.shift(on: about), matcher: store.matcher).contains(.duty) {
                content.interruptionLevel = .timeSensitive
            }
            // 早上的提醒：这天有清单就带一个「清单全部做完」按钮（长按通知就能点）
            if n.id.hasPrefix("shift-morning"), !AppStore.shared.taskItems(on: about).isEmpty {
                content.categoryIdentifier = Self.tasksCategory
            }
            // 指定公历：手机设成日本、佛历等日历时也能按时提醒
            let when = DateComponents(calendar: Calendar(identifier: .gregorian), year: n.day.year, month: n.day.month,
                                      day: n.day.day, hour: n.time.hour, minute: n.time.minute)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            let final: UNNotificationContent = avatars
                ? await ShiftNotificationAvatar.apply(to: content, icon: store.iconName(for: store.shift(on: about)))
                : content
            requests.append(UNNotificationRequest(identifier: n.id, content: final, trigger: trigger))
        }
        // 已经有更新的一次在排队：这次的内容过时了，不要替换
        if Task.isCancelled { return }
        // 先登记新的（同一个 id 直接替换旧内容），再删掉不再需要的：
        // 中途被系统挂起时，最多是多一两条旧提醒，不会出现一条提醒都没有
        for request in requests { try? await center.add(request) }
        let keep = Set(requests.map(\.identifier))
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) && !keep.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        VoiceSound.removeFiles(except: voiceFiles)
    }

    /// 签名到期前 1 天提醒去 SideStore 续签（来不及就提前 2 小时）。
    static func scheduleSigningReminder(expiry: Date?) async {
        let id = "signing-expiry"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let expiry else { return }
        let fire = [expiry.addingTimeInterval(-86_400), expiry.addingTimeInterval(-7_200)]
            .first { $0 > Date().addingTimeInterval(60) }
        guard let fire else { return }
        let content = UNMutableNotificationContent()
        content.title = "⚠️ 值班提醒的签名快到期了"
        content.body = "打开 LocalDevVPN 连接，再打开 SideStore 点「Refresh All」续签。过期后 App 打不开（已登记的提醒照常）。"
        content.sound = .default
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        try? await center.add(UNNotificationRequest(identifier: id, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false)))
    }

    /// 上次同步成功 2 天后还没有新的同步，就由系统弹出提醒（每次同步成功都会往后推）。
    static func scheduleStaleReminder(after lastSync: Date?) async {
        let id = "sync-stale-scheduled"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        // 已经超过两天了：首页红色提示和那一次通知已经提醒过，这里不再每小时重复
        guard let lastSync, lastSync.addingTimeInterval(2 * 86_400) > Date().addingTimeInterval(60) else { return }
        let fire = lastSync.addingTimeInterval(2 * 86_400)
        let content = UNMutableNotificationContent()
        content.title = "⚠️ 已经两天没同步排班了"
        content.body = "现在的提醒可能不是最新排班。打开值班提醒下拉刷新一下；一直失败的话到「设置 › 诊断」看原因。"
        content.sound = .default
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        try? await center.add(UNNotificationRequest(identifier: id, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false)))
    }

    /// 下一条要弹的排班提醒。
    static func nextReminder() async -> (date: Date, title: String)? {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(prefix) }
            .compactMap { r in (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate().map { ($0, r.content.title) } }
            .min { $0.0 < $1.0 }
            .map { (date: $0.0, title: $0.1) }
    }

    static let tasksCategory = "shift-tasks"
    static let tasksDoneAction = "tasks-done"

    /// 启动时登记通知上的按钮
    static func registerCategories() {
        let done = UNNotificationAction(identifier: tasksDoneAction, title: "清单全部做完", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: tasksCategory, actions: [done],
                                                                 intentIdentifiers: [], options: [])])
    }

    /// 立即推送一条通知（排班变动、登录过期）。同一个 id 会替换上一条。
    /// route：点通知后打开哪一页（见 RootView.openRoute），比如「rosterLog」变动历史、「teamChanges」全员换班记录
    @MainActor
    static func notifyNow(id: String, title: String, body: String, route: String? = nil) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let route { content.userInfo = ["route": route] }
        // 一次同步可能接连发好几条（变动、公告、预警……）：归到一组，只有第一条响铃。
        // 只静音几秒内接连发的：以前是 30 秒，同步完半分钟内读电脑版周表又发现的变动就不响了，容易漏看
        content.threadIdentifier = "updates"
        let now = Date()
        content.sound = now.timeIntervalSince(lastSound) > 8 ? .default : nil
        lastSound = now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        // 左边的大图用今天的班（App 在后台时换不了图标，图标可能还是前几天的）
        let store = AppStore.shared
        let final: UNNotificationContent = store.settings.dynamicIcon
            ? await ShiftNotificationAvatar.apply(to: content, icon: store.iconName(for: store.shift(on: .today)))
            : content
        try? await center.add(UNNotificationRequest(identifier: id, content: final, trigger: trigger))
    }

    /// 上一条即时通知响铃的时间
    @MainActor private static var lastSound = Date.distantPast

    static func sendTest(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger))
    }
}
