import SwiftUI

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppSettings: Codable, Equatable {
    var aliases: [String] = []
    var morningEnabled = true
    var morning = ClockTime(hour: 7, minute: 30)
    var eveningEnabled = true
    var evening = ClockTime(hour: 20, minute: 30)
    var notifyWhenEmpty = false
    /// 到点时用语音读出「今天，组D」（作为通知铃声）
    var voiceEnabled = false
    var appearance: Appearance = .system
    var sourceURL = ""
    var sourceUsername = ""
    /// 用 App 内置浏览器同步（沿用网页登录状态）；关掉则直接下载文件
    var syncViaWeb = true
    /// 同步发现排班变动时推送通知
    var notifyChanges = true
    var loginExpiredNotified = false
    /// 微信推送（PushPlus）
    var weChatEnabled = false
    /// 每天的提醒也发一份到微信（App 有机会运行时补发，可能比准点晚）
    var weChatDaily = true
    var weChatMorningSent: DayKey?
    var weChatEveningSent: DayKey?
    var weChatMessage: String?
    /// 主屏幕图标显示今天的组（A–E / 休），打开 App 时切换
    var dynamicIcon = true
    var shiftTypes: [ShiftType] = ShiftType.defaults
    var lastSync: Date?
    var lastSyncMessage: String?

    init() {}

    // 逐项读取，新版本增加字段时旧存档也能正常打开
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? d.aliases
        morningEnabled = try c.decodeIfPresent(Bool.self, forKey: .morningEnabled) ?? d.morningEnabled
        morning = try c.decodeIfPresent(ClockTime.self, forKey: .morning) ?? d.morning
        eveningEnabled = try c.decodeIfPresent(Bool.self, forKey: .eveningEnabled) ?? d.eveningEnabled
        evening = try c.decodeIfPresent(ClockTime.self, forKey: .evening) ?? d.evening
        notifyWhenEmpty = try c.decodeIfPresent(Bool.self, forKey: .notifyWhenEmpty) ?? d.notifyWhenEmpty
        voiceEnabled = try c.decodeIfPresent(Bool.self, forKey: .voiceEnabled) ?? d.voiceEnabled
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL) ?? d.sourceURL
        sourceUsername = try c.decodeIfPresent(String.self, forKey: .sourceUsername) ?? d.sourceUsername
        syncViaWeb = try c.decodeIfPresent(Bool.self, forKey: .syncViaWeb) ?? d.syncViaWeb
        notifyChanges = try c.decodeIfPresent(Bool.self, forKey: .notifyChanges) ?? d.notifyChanges
        loginExpiredNotified = try c.decodeIfPresent(Bool.self, forKey: .loginExpiredNotified) ?? d.loginExpiredNotified
        weChatEnabled = try c.decodeIfPresent(Bool.self, forKey: .weChatEnabled) ?? d.weChatEnabled
        weChatDaily = try c.decodeIfPresent(Bool.self, forKey: .weChatDaily) ?? d.weChatDaily
        weChatMorningSent = try c.decodeIfPresent(DayKey.self, forKey: .weChatMorningSent)
        weChatEveningSent = try c.decodeIfPresent(DayKey.self, forKey: .weChatEveningSent)
        weChatMessage = try c.decodeIfPresent(String.self, forKey: .weChatMessage)
        dynamicIcon = try c.decodeIfPresent(Bool.self, forKey: .dynamicIcon) ?? d.dynamicIcon
        shiftTypes = try c.decodeIfPresent([ShiftType].self, forKey: .shiftTypes) ?? d.shiftTypes
        lastSync = try c.decodeIfPresent(Date.self, forKey: .lastSync)
        lastSyncMessage = try c.decodeIfPresent(String.self, forKey: .lastSyncMessage)
    }
}

private struct PersistedState: Codable {
    var settings: AppSettings
    var schedule: [String: String]
}

extension Calendar {
    /// App 内统一使用公历，避免系统设置成其它历法时日期错乱。
    static var app: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .autoupdatingCurrent
        c.locale = Locale(identifier: "zh_CN")
        return c
    }
}

extension DayKey: Identifiable {
    public var id: String { description }
    static var today: DayKey { DayKey(date: Date(), calendar: .app) }
    func adding(days: Int) -> DayKey { adding(days: days, calendar: .app) }
    var dateText: String { NotificationPlanner.dateText(self, calendar: .app) }
}

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            Task { await rescheduleNotifications() }
        }
    }
    @Published private(set) var schedule: [DayKey: String]
    @Published private(set) var isSyncing = false

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }()

    private init() {
        let state = (try? Data(contentsOf: Self.fileURL)).flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
        settings = state?.settings ?? AppSettings()
        var schedule: [DayKey: String] = [:]
        for (k, v) in state?.schedule ?? [:] {
            if let day = DayKey(string: k) { schedule[day] = v }
        }
        self.schedule = schedule
    }

    private func save() {
        let state = PersistedState(settings: settings,
                                   schedule: Dictionary(uniqueKeysWithValues: schedule.map { ($0.key.description, $0.value) }))
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    // MARK: - 排班

    var matcher: ShiftMatcher { ShiftMatcher(types: settings.shiftTypes) }

    var parser: ScheduleParser {
        ScheduleParser(aliases: settings.aliases, reference: .today, timeZone: .current)
    }

    func shift(on day: DayKey) -> String? { schedule[day] }

    func setShift(_ value: String?, on day: DayKey) {
        let v = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule[day] = (v?.isEmpty ?? true) ? nil : v
        scheduleChanged()
    }

    /// 导入/同步：用新数据整体替换它覆盖的那段日期（这段时间里被删掉的班次也会同步删除）。
    @discardableResult
    func apply(_ result: ParseResult) -> [ScheduleChange] {
        let old = schedule
        var new = schedule
        if let range = result.range {
            new = new.filter { !range.contains($0.key) }
        }
        new.merge(result.entries) { _, n in n }
        schedule = new
        scheduleChanged()
        return ScheduleDiff.changes(old: old, new: new, from: .today)
    }

    func clearSchedule() {
        schedule = [:]
        scheduleChanged()
    }

    private func scheduleChanged() {
        save()
        Task { await rescheduleNotifications() }
    }

    // MARK: - 提醒

    private var planner: NotificationPlanner {
        NotificationPlanner(
            morning: settings.morningEnabled ? settings.morning : nil,
            evening: settings.eveningEnabled ? settings.evening : nil,
            notifyWhenEmpty: settings.notifyWhenEmpty,
            matcher: matcher,
            calendar: .app)
    }

    func rescheduleNotifications() async {
        await NotificationService.reschedule(planner.plan(schedule: schedule, now: Date()), voice: settings.voiceEnabled)
        updateWidget()
        updateAppIcon()
        await NotificationService.scheduleSigningReminder(expiry: SigningInfo.expirationDate)
    }

    /// 今天该用哪个图标：组A–组E 用对应字母（一天多个组取第一个），无分工/休息用「休」，其它用默认的「值」。
    func iconName(for raw: String?) -> String? {
        guard let raw else { return nil }
        if let r = raw.range(of: #"组\s*[A-Ea-e]"#, options: .regularExpression), let letter = raw[r].last {
            return "Icon" + letter.uppercased()
        }
        return matcher.match(raw)?.id == "off" ? "IconRest" : nil
    }

    /// iPhone 只允许 App 在前台时换图标，每次换系统会弹一个「已更改图标」的提示。
    func updateAppIcon() {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.applicationState == .active else { return }
        let wanted = settings.dynamicIcon ? iconName(for: schedule[.today]) : nil
        guard app.alternateIconName != wanted else { return }
        app.setAlternateIconName(wanted) { _ in }
    }

    /// 把昨天到未来一个月的分工写给主屏幕小组件。
    func updateWidget() {
        let today = DayKey.today
        let days = (-1...31).compactMap { offset -> WidgetDay? in
            let day = today.adding(days: offset)
            guard let raw = schedule[day] else { return nil }
            let type = matcher.match(raw)
            return WidgetDay(date: day.description, title: matcher.displayName(raw),
                             emoji: type?.emoji ?? "📌", colorHex: type?.colorHex ?? "#8E8E93")
        }
        WidgetStore.save(WidgetSnapshot(days: days, updated: Date()))
    }

    // MARK: - 同步

    var canSync: Bool { !settings.sourceURL.trimmingCharacters(in: .whitespaces).isEmpty }

    @discardableResult
    func sync() async -> Bool {
        guard canSync, !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let text = try await SyncService.fetchText(urlString: settings.sourceURL,
                                                       username: settings.sourceUsername,
                                                       password: Keychain.get(.sourcePassword) ?? "",
                                                       viaWeb: settings.syncViaWeb)
            let result = try parser.parse(text)
            let hadData = !schedule.isEmpty
            let changes = apply(result)
            settings.lastSync = Date()
            settings.loginExpiredNotified = false
            settings.lastSyncMessage = "同步成功：\(result.format.rawValue)，\(result.entries.count) 天"
                + (changes.isEmpty ? "，没有变动" : "，\(changes.count) 处变动")
            // 第一次导入不算“变动”，之后每次同步发现不同就提醒
            if hadData && !changes.isEmpty && settings.notifyChanges {
                let title = "📢 排班有更新（\(changes.count) 处）"
                let body = ScheduleDiff.summary(changes, matcher: matcher, calendar: .app)
                await NotificationService.notifyNow(id: "schedule-changed", title: title, body: body)
                await pushToWeChat(title: title, content: body)
            }
            return true
        } catch {
            settings.lastSyncMessage = "同步失败：\(error.localizedDescription)"
            // 登录过期只提醒一次，重新登录同步成功后恢复
            if case SyncError.needsLogin = error, !settings.loginExpiredNotified {
                settings.loginExpiredNotified = true
                let title = "⚠️ 值班网站登录已过期"
                let body = "打开「值班提醒 › 设置 › 网页登录」重新登录一次，之后会继续自动更新。"
                await NotificationService.notifyNow(id: "login-expired", title: title, body: body)
                await pushToWeChat(title: title, content: body)
            }
            return false
        }
    }

    /// 打开 App 时，距离上次同步超过 3 分钟就自动同步一次。
    func syncIfStale() async {
        guard canSync else { return }
        if let last = settings.lastSync, Date().timeIntervalSince(last) < 3 * 60 { return }
        await sync()
    }

    /// 系统在后台唤醒 App 时调用（时间由 iOS 决定，不保证准时）。
    func backgroundRefresh() async {
        if canSync { await sync() }
        await sendDueWeChatReminders()
        await rescheduleNotifications()
        BackgroundRefresh.schedule(notBefore: nextWeChatReminder)
    }

    // MARK: - 微信

    /// 发到微信；失败只记录原因，不影响其它功能。
    @discardableResult
    func pushToWeChat(title: String, content: String, force: Bool = false) async -> Bool {
        guard settings.weChatEnabled || force else { return false }
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
    func sendDueWeChatReminders() async {
        guard settings.weChatEnabled, settings.weChatDaily else { return }
        let now = Date()
        let today = DayKey.today
        let p = planner
        func time(_ t: ClockTime) -> Date { today.date(calendar: .app, hour: t.hour, minute: t.minute) }

        if settings.eveningEnabled, now >= time(settings.evening), settings.weChatEveningSent != today {
            settings.weChatEveningSent = today
            settings.weChatMorningSent = today
            if let m = p.message(morning: false, on: today, schedule: schedule) {
                await pushToWeChat(title: m.title, content: m.body)
            }
        } else if settings.morningEnabled, now >= time(settings.morning), settings.weChatMorningSent != today {
            settings.weChatMorningSent = today
            if let m = p.message(morning: true, on: today, schedule: schedule) {
                await pushToWeChat(title: m.title, content: m.body)
            }
        }
    }

    /// 立即把今天（morning）或明天的分工发到微信，供快捷指令自动化准点调用。返回给用户看的结果。
    func sendWeChatReminder(morning: Bool) async -> String {
        guard !(Keychain.get(.pushPlusToken) ?? "").isEmpty else {
            return "还没有设置 PushPlus token：打开值班提醒 › 设置 › 微信推送"
        }
        let today = DayKey.today
        // 记下已发送，App 之后运行时就不会再补发同一条
        if morning {
            settings.weChatMorningSent = today
        } else {
            settings.weChatMorningSent = today
            settings.weChatEveningSent = today
        }
        guard let m = planner.message(morning: morning, on: today, schedule: schedule) else {
            return "\(morning ? "今天" : "明天")没有排班，未发送"
        }
        let ok = await pushToWeChat(title: m.title, content: m.body, force: true)
        return ok ? "已发送到微信：\(m.title)" : (settings.weChatMessage ?? "微信推送失败")
    }

    /// 下一次该发微信提醒的时间，用来请求系统在那之后尽快唤醒 App。
    var nextWeChatReminder: Date? {
        guard settings.weChatEnabled, settings.weChatDaily else { return nil }
        let now = Date()
        let times = [settings.morningEnabled ? settings.morning : nil, settings.eveningEnabled ? settings.evening : nil].compactMap { $0 }
        return [DayKey.today, DayKey.today.adding(days: 1)]
            .flatMap { day in times.map { day.date(calendar: .app, hour: $0.hour, minute: $0.minute) } }
            .filter { $0 > now }
            .min()
    }
}
