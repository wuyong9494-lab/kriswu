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
            let when = DateComponents(year: n.day.year, month: n.day.month, day: n.day.day,
                                      hour: n.time.hour, minute: n.time.minute)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            requests.append(UNNotificationRequest(identifier: n.id, content: content, trigger: trigger))
        }
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        for request in requests { try? await center.add(request) }
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
        guard let lastSync else { return }
        let fire = max(lastSync.addingTimeInterval(2 * 86_400), Date().addingTimeInterval(3_600))
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

    /// 立即推送一条通知（排班变动、登录过期）。同一个 id 会替换上一条。
    static func notifyNow(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func sendTest(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger))
    }
}
