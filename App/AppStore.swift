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
    /// 认出的网站数据接口（如 "GET http://…/api/duty"），同步时优先用它取多周数据
    var apiSignature: String?
    /// 微信推送（PushPlus）
    var weChatEnabled = false
    /// 每天的提醒也发一份到微信（App 有机会运行时补发，可能比准点晚）
    var weChatDaily = true
    var weChatMorningSent: DayKey?
    var weChatEveningSent: DayKey?
    var weChatMessage: String?
    /// 主屏幕图标显示今天的组（A–E / 休），打开 App 时切换
    var dynamicIcon = true
    /// 把排班写进 iPhone「日历」App
    var calendarSync = false
    /// 排班变动也发到微信（关掉后只在 iPhone 上通知）
    var weChatChanges = true
    var lastWeChatChangeDigest: String?
    /// 各组工作内容：网页上读到的 / 自己填写的（填写的优先）
    var autoGroupNotes: [String: String] = [:]
    var manualGroupNotes: [String: String] = [:]
    /// 全员排班的读取规则版本；规则改了以后清掉旧数据重新读
    var rosterVersion = 0
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
        apiSignature = try c.decodeIfPresent(String.self, forKey: .apiSignature)
        weChatEnabled = try c.decodeIfPresent(Bool.self, forKey: .weChatEnabled) ?? d.weChatEnabled
        weChatDaily = try c.decodeIfPresent(Bool.self, forKey: .weChatDaily) ?? d.weChatDaily
        weChatMorningSent = try c.decodeIfPresent(DayKey.self, forKey: .weChatMorningSent)
        weChatEveningSent = try c.decodeIfPresent(DayKey.self, forKey: .weChatEveningSent)
        weChatMessage = try c.decodeIfPresent(String.self, forKey: .weChatMessage)
        dynamicIcon = try c.decodeIfPresent(Bool.self, forKey: .dynamicIcon) ?? d.dynamicIcon
        calendarSync = try c.decodeIfPresent(Bool.self, forKey: .calendarSync) ?? d.calendarSync
        weChatChanges = try c.decodeIfPresent(Bool.self, forKey: .weChatChanges) ?? d.weChatChanges
        lastWeChatChangeDigest = try c.decodeIfPresent(String.self, forKey: .lastWeChatChangeDigest)
        autoGroupNotes = try c.decodeIfPresent([String: String].self, forKey: .autoGroupNotes) ?? [:]
        manualGroupNotes = try c.decodeIfPresent([String: String].self, forKey: .manualGroupNotes) ?? [:]
        rosterVersion = try c.decodeIfPresent(Int.self, forKey: .rosterVersion) ?? 0
        shiftTypes = try c.decodeIfPresent([ShiftType].self, forKey: .shiftTypes) ?? d.shiftTypes
        lastSync = try c.decodeIfPresent(Date.self, forKey: .lastSync)
        lastSyncMessage = try c.decodeIfPresent(String.self, forKey: .lastSyncMessage)
    }
}

private struct PersistedState: Codable {
    var settings: AppSettings
    var schedule: [String: String]
    /// 已经取到过排班结果的日子（包括没给我排班的日子）
    var covered: [String]?
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
    /// 已经取到过结果的日子：有排班的显示班次，没排班的显示「未排班」；不在这里的日子还没有数据
    @Published private(set) var covered: Set<DayKey>
    /// 全员排班（姓名 → 日期 → 岗位），只存在手机上，用于搜索成员
    @Published private(set) var roster: Roster = [:]
    @Published private(set) var isSyncing = false

    private static let rosterURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("roster.json")
    }()

    private static func loadRoster() -> Roster {
        guard let data = try? Data(contentsOf: rosterURL),
              let raw = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return raw.mapValues { days in
            Dictionary(days.compactMap { k, v in DayKey(string: k).map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
        }
    }

    private func saveRoster() {
        let raw = roster.mapValues { days in Dictionary(uniqueKeysWithValues: days.map { ($0.key.description, $0.value) }) }
        if let data = try? JSONEncoder().encode(raw) {
            try? data.write(to: Self.rosterURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

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
        if let saved = state?.covered {
            covered = Set(saved.compactMap(DayKey.init(string:)))
        } else if let lo = schedule.keys.min(), let hi = schedule.keys.max() {
            // 旧版本没记录：把已有排班的首尾之间都算作取到过
            var days = Set<DayKey>()
            var d = lo
            while d <= hi { days.insert(d); d = d.adding(days: 1) }
            covered = days
        } else {
            covered = []
        }
        roster = Self.loadRoster()
        // 旧版本把手机版「值班查看」读错了（人名当成岗位），清掉重新读
        if settings.rosterVersion < Self.rosterVersion {
            roster = [:]
            saveRoster()
            settings.rosterVersion = Self.rosterVersion
            settings.lastSync = nil   // 打开 App 后马上重新同步
            save()
        }
    }

    private static let rosterVersion = 2

    private func save() {
        let state = PersistedState(settings: settings,
                                   schedule: Dictionary(uniqueKeysWithValues: schedule.map { ($0.key.description, $0.value) }),
                                   covered: covered.map(\.description).sorted())
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
        covered.insert(day)
        scheduleChanged()
    }

    /// 导入/同步：用新数据整体替换它覆盖的那段日期（这段时间里被删掉的班次也会同步删除）。
    @discardableResult
    func apply(_ result: ParseResult) -> [ScheduleChange] {
        let old = schedule
        let knownBefore = covered
        var new = schedule
        if let range = result.range {
            new = new.filter { !range.contains($0.key) }
            var d = range.lowerBound
            while d <= range.upperBound { covered.insert(d); d = d.adding(days: 1) }
            // 只保留最近一年，文件不会越来越大
            let cutoff = DayKey.today.adding(days: -366)
            covered = covered.filter { $0 >= cutoff }
        }
        new.merge(result.entries) { _, n in n }
        schedule = new
        scheduleChanged()
        // 之前就取到过的日子改了才算变动；新一周第一次取到不算
        return ScheduleDiff.changes(old: old, new: new, from: .today)
            .filter { knownBefore.contains($0.day) || $0.old != nil }
    }

    /// 组别的工作内容（自己填写的优先）。key 如「组D」。
    var groupNotes: [String: String] {
        settings.autoGroupNotes.merging(settings.manualGroupNotes.filter { !$0.value.isEmpty }) { _, m in m }
    }

    /// 某天分工对应的工作内容，例如「组A+组E」→ [("组A", "…"), ("组E", "…")]。
    func notes(for raw: String?) -> [(group: String, note: String)] {
        guard let raw else { return [] }
        let notes = groupNotes
        return matcher.displayName(raw).split(separator: "+").compactMap { part in
            let key = String(part).filter { !$0.isWhitespace }.uppercased()
            return notes[key].map { (group: String(part), note: $0) }
        }
    }

    /// 某一天所有岗位各是谁（来自全员排班），按网页上的习惯排序：遥测、调度、组A–E、其它、休息、调休。
    func dayRoster(_ day: DayKey) -> [(post: String, names: [String])] {
        var byPost: [String: [String]] = [:]
        for (name, days) in roster {
            guard let posts = days[day] else { continue }
            for post in posts.split(separator: "+").map(String.init) { byPost[post, default: []].append(name) }
        }
        func rank(_ post: String) -> (Int, String) {
            switch post {
            case "遥测": return (0, post)
            case "调度": return (1, post)
            case _ where post.hasPrefix("组"): return (2, post)
            case "休息": return (5, post)
            case "调休": return (6, post)
            case _ where post.hasPrefix("值班"): return (3, post)
            default: return (4, post)
            }
        }
        let zh = Locale(identifier: "zh_CN")
        return byPost
            .map { (post: $0.key, names: $0.value.sorted { $0.compare($1, locale: zh) == .orderedAscending }) }
            .sorted { rank($0.post) < rank($1.post) }
    }

    /// 是不是我自己（按「我的名字」判断）。
    func isMe(_ name: String) -> Bool { parser.isMe(name) }

    /// 这一天是否已经取到过排班结果（没排班也算）。
    func isCovered(_ day: DayKey) -> Bool { covered.contains(day) || schedule[day] != nil }

    func clearSchedule() {
        schedule = [:]
        covered = []
        roster = [:]
        saveRoster()
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
        // 手机上的通知带上组别工作内容；微信那份不带（只发自己的分工）
        var local = planner
        local.notes = groupNotes
        await NotificationService.reschedule(local.plan(schedule: schedule, now: Date()), voice: settings.voiceEnabled)
        updateWidget()
        updateAppIcon()
        if settings.calendarSync { CalendarSync.sync(schedule, matcher: matcher) }
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
            let outcome = try await SyncService.fetchSchedule(urlString: settings.sourceURL,
                                                              username: settings.sourceUsername,
                                                              password: Keychain.get(.sourcePassword) ?? "",
                                                              viaWeb: settings.syncViaWeb,
                                                              parser: parser,
                                                              aliases: settings.aliases,
                                                              matcher: matcher,
                                                              preferredAPI: settings.apiSignature)
            let result = outcome.result
            if let signature = outcome.apiSignature { settings.apiSignature = signature }
            if !outcome.roster.isEmpty {
                // 这次读到的日子整天替换（换人、取消的都以新数据为准）
                let days = Set(outcome.roster.values.flatMap(\.keys))
                roster = roster.mapValues { $0.filter { !days.contains($0.key) } }
                RosterExtractor.merge(outcome.roster, into: &roster)
                let cutoff = DayKey.today.adding(days: -120)
                roster = roster.mapValues { $0.filter { $0.key >= cutoff } }.filter { !$0.value.isEmpty }
                saveRoster()
            }
            if !outcome.groupNotes.isEmpty { settings.autoGroupNotes.merge(outcome.groupNotes) { _, n in n } }
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
                // 微信：可以关掉；同样的变动不重复发
                if settings.weChatChanges && settings.lastWeChatChangeDigest != body {
                    settings.lastWeChatChangeDigest = body
                    await pushToWeChat(title: title, content: body)
                }
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
