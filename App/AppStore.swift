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
    /// 各组工作内容：电脑版网页 > 自己填写的 > 其它页面顺带读到的
    var autoGroupNotes: [String: String] = [:]
    var manualGroupNotes: [String: String] = [:]
    /// 全员排班的读取规则版本；规则改了以后清掉旧数据重新读
    var rosterVersion = 0
    /// 每周日晚上预告下周安排（iPhone 通知 + 微信）
    var weeklyPreview = true
    var weChatWeekSent: DayKey?
    /// 收藏的同事，首页显示他们今天、明天在哪个组
    var favorites: [String] = []
    /// 最近的排班变动（首页显示）
    var changeLog: [ChangeLogEntry] = []
    /// 已经提醒过「很久没同步成功」，同步成功后恢复
    var syncStaleNotified = false
    /// 上次从电脑版页面读各组工作内容的时间（一天读一次）
    var lastDesktopNotesFetch: Date?
    var lastDesktopNotesAttempt: Date?
    var desktopNotesMessage: String?
    /// 电脑版「值班查看」的网址（空 = 用同步网址的 #/duty）
    var desktopNotesURL = ""
    /// 从电脑版「值班查看」读到的各组工作内容，优先级最高
    var desktopGroupNotes: [String: String] = [:]
    /// 最近一次成功同步的结果（失败时 lastSyncMessage 会被覆盖，这里留着方便排查）
    var lastSuccessMessage: String?
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
        weeklyPreview = try c.decodeIfPresent(Bool.self, forKey: .weeklyPreview) ?? d.weeklyPreview
        weChatWeekSent = try c.decodeIfPresent(DayKey.self, forKey: .weChatWeekSent)
        favorites = try c.decodeIfPresent([String].self, forKey: .favorites) ?? []
        changeLog = try c.decodeIfPresent([ChangeLogEntry].self, forKey: .changeLog) ?? []
        syncStaleNotified = try c.decodeIfPresent(Bool.self, forKey: .syncStaleNotified) ?? false
        lastDesktopNotesFetch = try c.decodeIfPresent(Date.self, forKey: .lastDesktopNotesFetch)
        lastDesktopNotesAttempt = try c.decodeIfPresent(Date.self, forKey: .lastDesktopNotesAttempt)
        desktopNotesMessage = try c.decodeIfPresent(String.self, forKey: .desktopNotesMessage)
        desktopNotesURL = try c.decodeIfPresent(String.self, forKey: .desktopNotesURL) ?? ""
        desktopGroupNotes = try c.decodeIfPresent([String: String].self, forKey: .desktopGroupNotes) ?? [:]
        lastSuccessMessage = try c.decodeIfPresent(String.self, forKey: .lastSuccessMessage)
        shiftTypes = try c.decodeIfPresent([ShiftType].self, forKey: .shiftTypes) ?? d.shiftTypes
        lastSync = try c.decodeIfPresent(Date.self, forKey: .lastSync)
        lastSyncMessage = try c.decodeIfPresent(String.self, forKey: .lastSyncMessage)
    }
}

struct ChangeLogEntry: Codable, Hashable {
    var date: Date
    var text: String
}

/// 备份文件：设置、排班、全员排班。密码和 PushPlus token 存在钥匙串里，不在备份中。
struct BackupFile: Codable {
    var version = 1
    var created = Date()
    var settings: AppSettings
    var schedule: [String: String]
    var covered: [String]
    var roster: [String: [String: String]]
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
    /// 上次读电脑版页面时看到的文字（只在内存里，排查用）
    @Published var desktopPageText: String?

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

    private static let rosterVersion = 3

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
        settings.autoGroupNotes
            .merging(settings.manualGroupNotes.filter { !$0.value.isEmpty }) { _, m in m }
            .merging(settings.desktopGroupNotes.filter { !$0.value.isEmpty }) { _, d in d }
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
            case _ where post.hasPrefix("值班") || post.contains("交班"): return (3, post)
            case "休息": return (4, post)
            case "调休": return (5, post)
            case "请假": return (6, post)
            case "出差": return (7, post)
            case "加班": return (8, post)
            default: return (9, post)
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
        var p = NotificationPlanner(
            morning: settings.morningEnabled ? settings.morning : nil,
            evening: settings.eveningEnabled ? settings.evening : nil,
            notifyWhenEmpty: settings.notifyWhenEmpty,
            matcher: matcher,
            calendar: .app)
        p.weekly = settings.weeklyPreview
        return p
    }

    /// 提醒用的排班：已经取到数据、但没给我排班的日子补上「未排班」，这样每天都会提醒。
    var reminderSchedule: [DayKey: String] {
        var s = schedule
        let today = DayKey.today
        for day in covered where day >= today && s[day] == nil { s[day] = "未排班" }
        return s
    }

    func rescheduleNotifications() async {
        // 手机上的通知带上组别工作内容；微信那份不带（只发自己的分工）
        var local = planner
        local.notes = groupNotes
        await NotificationService.reschedule(local.plan(schedule: reminderSchedule, now: Date()), voice: settings.voiceEnabled)
        updateWidget()
        updateAppIcon()
        if settings.calendarSync { CalendarSync.sync(schedule, matcher: matcher) }
        await NotificationService.scheduleSigningReminder(expiry: SigningInfo.expirationDate)
        // App 一直没机会运行（后台刷新被系统停掉）时，到点由系统弹出提醒
        await NotificationService.scheduleStaleReminder(after: canSync ? settings.lastSync : nil)
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
    /// full：同时翻页读取全员排班（较慢，约半分钟），后台和快捷指令里只取自己的排班，避免超过系统给的时间。
    /// userInitiated：用户手动刷新。登录失败过一次后，只有手动刷新才再尝试登录，防止密码错误时反复登录把账号锁住；
    /// 同步结果和之前差别过大时，也只有手动刷新才采用。
    func sync(full: Bool = true, userInitiated: Bool = false) async -> Bool {
        // 放在独立的任务里跑：下拉刷新的界面消失、切换页面时 SwiftUI 会取消调用方，
        // 不能让读到一半的全员排班跟着作废（以前会显示「CancellationError」）
        await Task { await self.performSync(full: full, userInitiated: userInitiated) }.value
    }

    private func performSync(full: Bool, userInitiated: Bool) async -> Bool {
        guard canSync, !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let mayLogin = userInitiated || !settings.loginExpiredNotified
            let outcome = try await SyncService.fetchSchedule(urlString: settings.sourceURL,
                                                              username: settings.sourceUsername,
                                                              password: mayLogin ? (Keychain.get(.sourcePassword) ?? "") : "",
                                                              viaWeb: settings.syncViaWeb,
                                                              includeRoster: full,
                                                              parser: parser,
                                                              aliases: settings.aliases,
                                                              matcher: matcher,
                                                              preferredAPI: settings.apiSignature)
            let result = outcome.result
            if !userInitiated, let range = result.range {
                // 已经知道的日子里，一大半都变了：多半是网站改版读错了，先不采用
                let today = DayKey.today
                let known = covered.filter { $0 >= today && range.contains($0) }
                let changed = known.filter { schedule[$0] != result.entries[$0] }.count
                if known.count >= 5 && changed * 10 > known.count * 6 {
                    settings.lastSyncMessage = "同步结果异常：\(known.count) 天里有 \(changed) 天和之前不同，可能是网站改版，已忽略。下拉刷新可确认采用"
                    return false
                }
            }
            if let signature = outcome.apiSignature { settings.apiSignature = signature }
            let rosterBefore = roster
            let freshDays = Set(outcome.roster.values.flatMap(\.keys))
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
            settings.syncStaleNotified = false
            settings.lastSyncMessage = "同步成功：\(result.format.rawValue)，\(result.entries.count) 天"
                + (changes.isEmpty ? "，没有变动" : "，\(changes.count) 处变动")
                + (outcome.roster.isEmpty ? "" : "，全员 \(outcome.roster.count) 人")
            settings.lastSuccessMessage = settings.lastSyncMessage
            // 第一次导入不算“变动”，之后每次同步发现不同就提醒
            if hadData && !changes.isEmpty && settings.notifyChanges {
                let title = "📢 排班有更新（\(changes.count) 处）"
                let body = ScheduleDiff.summary(changes, matcher: matcher, calendar: .app) {
                    self.swapDetail($0, before: rosterBefore, fresh: freshDays)
                }
                settings.changeLog = Array(([ChangeLogEntry(date: Date(), text: body)] + settings.changeLog).prefix(20))
                await NotificationService.notifyNow(id: "schedule-changed", title: title, body: body)
                // 微信：可以关掉；同样的变动不重复发
                if settings.weChatChanges && settings.lastWeChatChangeDigest != body {
                    settings.lastWeChatChangeDigest = body
                    await pushToWeChat(title: title, content: body)
                }
            }
            // 手机版没有各组工作内容：打开 App 时每天用电脑版页面读一次（读不到不影响同步结果，过 1 小时再试）
            let now = Date()
            if full, settings.syncViaWeb,
               now.timeIntervalSince(settings.lastDesktopNotesFetch ?? .distantPast) > 20 * 3600,
               now.timeIntervalSince(settings.lastDesktopNotesAttempt ?? .distantPast) > 3600 {
                await readDesktopNotes(mayLogin: mayLogin)
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
            await notifyIfSyncStale()
            return false
        }
    }

    /// 用电脑版打开「值班查看」读各组工作内容。读到就整体替换（网页上删掉的组也跟着删）。
    @discardableResult
    func readDesktopNotes(mayLogin: Bool = true) async -> Bool {
        settings.lastDesktopNotesAttempt = Date()
        let result = await Task {
            await SyncService.fetchDesktopGroupNotes(urlString: settings.sourceURL,
                                                     overrideURL: settings.desktopNotesURL,
                                                     username: settings.sourceUsername,
                                                     password: mayLogin ? (Keychain.get(.sourcePassword) ?? "") : "",
                                                     reference: .today)
        }.value
        desktopPageText = "网址：\(result.url)\n\n" + (result.pageText.isEmpty ? "（没有内容）" : result.pageText)
        if result.notes.isEmpty {
            settings.desktopNotesMessage = "没读到（\(Date().formatted(date: .omitted, time: .shortened))）：\(result.reason ?? "没找到说明")"
            return false
        }
        await applyDesktopNotes(result.notes)
        return true
    }

    /// 保存从电脑版页面读到的各组说明。
    func applyDesktopNotes(_ notes: [String: String]) async {
        settings.desktopGroupNotes = notes
        settings.lastDesktopNotesFetch = Date()
        settings.desktopNotesMessage = "读到 \(notes.count) 个组：" + notes.keys.sorted().joined(separator: "、")
        await rescheduleNotifications()
    }

    /// 超过一天没有同步成功（密码改了、网站换了地址或改版）。
    var syncIsStale: Bool {
        guard canSync else { return false }
        guard let last = settings.lastSync else { return settings.lastSyncMessage?.hasPrefix("同步失败") ?? false }
        return Date().timeIntervalSince(last) > 24 * 3600
    }

    /// 很久没同步成功时提醒一次（iPhone 通知 + 微信），同步成功后恢复。
    private func notifyIfSyncStale() async {
        guard syncIsStale, !settings.syncStaleNotified else { return }
        settings.syncStaleNotified = true
        let since = settings.lastSync.map { "从 " + $0.formatted(date: .abbreviated, time: .shortened) + " 起" } ?? ""
        let title = "⚠️ 排班\(since)一直没同步成功"
        let body = "\(settings.lastSyncMessage ?? "同步失败")\n现在的提醒可能不是最新排班。打开值班提醒下拉刷新，或到「设置 › 诊断」查看原因。"
        await NotificationService.notifyNow(id: "sync-stale", title: title, body: body)
        await pushToWeChat(title: title, content: body)
    }

    /// 排班变动的补充说明：新组原来是谁的、我原来的组现在是谁（一天一人一组，多半就是和他换的）。
    /// before：同步前的全员排班；fresh：这次重新读到全员排班的日子（只有这些日子的「现在是谁」可信）。
    func swapDetail(_ change: ScheduleChange, before: Roster, fresh: Set<DayKey>) -> String? {
        func key(_ s: String) -> String { s.filter { !$0.isWhitespace }.uppercased() }
        func groups(_ raw: String?) -> [String] {
            guard let raw else { return [] }
            return matcher.displayName(raw).split(separator: "+").map(String.init)
                .filter { matcher.match($0)?.id != "off" && $0 != "未排班" }
        }
        func holders(_ group: String, in r: Roster) -> [String] {
            r.compactMap { name, days in
                guard !isMe(name), let posts = days[change.day],
                      posts.split(separator: "+").contains(where: { key(String($0)) == key(group) }) else { return nil }
                return name
            }.sorted()
        }
        var parts: [String] = []
        let oldGroups = groups(change.old), newGroups = groups(change.new)
        for g in newGroups where !oldGroups.contains(g) {
            let who = holders(g, in: before)
            if !who.isEmpty { parts.append("\(g)原来是\(who.joined(separator: "、"))") }
        }
        if fresh.contains(change.day) {
            for g in oldGroups where !newGroups.contains(g) {
                let who = holders(g, in: roster)
                if !who.isEmpty { parts.append("\(g)现在是\(who.joined(separator: "、"))") }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "，")
    }

    /// 打开 App 时，距离上次同步超过 3 分钟就自动同步一次。
    func syncIfStale() async {
        guard canSync else { return }
        if let last = settings.lastSync, Date().timeIntervalSince(last) < 3 * 60 { return }
        await sync(full: true)
    }

    /// 系统在后台唤醒 App 时调用（时间由 iOS 决定，不保证准时）。
    func backgroundRefresh() async {
        if canSync { await sync(full: false) }
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
            if let m = p.message(morning: false, on: today, schedule: reminderSchedule) {
                await pushToWeChat(title: m.title, content: m.body)
            }
        } else if settings.morningEnabled, now >= time(settings.morning), settings.weChatMorningSent != today {
            settings.weChatMorningSent = today
            if let m = p.message(morning: true, on: today, schedule: reminderSchedule) {
                await pushToWeChat(title: m.title, content: m.body)
            }
        }
        // 周日晚上：下周安排
        if settings.weeklyPreview, settings.eveningEnabled, now >= time(settings.evening),
           Calendar.app.component(.weekday, from: now) == 1, settings.weChatWeekSent != today {
            settings.weChatWeekSent = today
            if let w = p.weekMessage(on: today, schedule: reminderSchedule) {
                await pushToWeChat(title: w.title, content: w.body)
            }
        }
    }

    /// 立即把下周（从明天起 7 天）的安排发到微信，供快捷指令调用。
    func sendWeChatWeek() async -> String {
        guard !(Keychain.get(.pushPlusToken) ?? "").isEmpty else {
            return "还没有设置 PushPlus token：打开值班提醒 › 设置 › 微信推送"
        }
        let today = DayKey.today
        settings.weChatWeekSent = today
        if canSync { await sync(full: false) }
        guard let w = planner.weekMessage(on: today, schedule: reminderSchedule) else {
            let ok = await pushToWeChat(title: "🗓 接下来一周：暂无排班数据",
                                        content: "没有取到接下来一周的排班（\(settings.lastSyncMessage ?? "还没同步过")）。", force: true)
            return ok ? "已发送到微信：暂无排班数据" : (settings.weChatMessage ?? "微信推送失败")
        }
        let ok = await pushToWeChat(title: w.title, content: w.body, force: true)
        return ok ? "已发送到微信：\(w.title)" : (settings.weChatMessage ?? "微信推送失败")
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
        let label = morning ? "今天" : "明天"
        var m = planner.message(morning: morning, on: today, schedule: reminderSchedule)
        // 没有这天的数据：先同步一次再看（快捷指令自动化里 App 可能很久没打开过）
        if m == nil, canSync {
            await sync(full: false)
            m = planner.message(morning: morning, on: today, schedule: reminderSchedule)
        }
        // 仍然没有也照样发一条，免得以为推送坏了
        let title = m?.title ?? "\(label)：暂无排班数据"
        let body = m?.body ?? "没有取到\(label)的排班（\(settings.lastSyncMessage ?? "还没同步过")）。打开值班提醒下拉刷新一下。"
        let ok = await pushToWeChat(title: title, content: body, force: true)
        return ok ? "已发送到微信：\(title)" : (settings.weChatMessage ?? "微信推送失败")
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

    // MARK: - 收藏的同事

    func isFavorite(_ name: String) -> Bool { settings.favorites.contains(name) }

    func toggleFavorite(_ name: String) {
        if let i = settings.favorites.firstIndex(of: name) {
            settings.favorites.remove(at: i)
        } else {
            settings.favorites.append(name)
        }
    }

    // MARK: - 月度统计

    /// 某月的统计文字，可复制或发到微信。
    func monthReport(year: Int, month: Int) -> String {
        let cal = Calendar.app
        let first = DayKey(year: year, month: month, day: 1)
        let count = cal.range(of: .day, in: .month, for: first.date(calendar: cal, hour: 12))?.count ?? 30
        let days = (1...count).map { DayKey(year: year, month: month, day: $0) }
        var tally: [String: Int] = [:]
        var order: [String] = []
        var unassigned = 0, unknown = 0
        var lines: [String] = []
        for day in days {
            if let raw = schedule[day] {
                let name = matcher.displayName(raw)
                if tally[name] == nil { order.append(name) }
                tally[name, default: 0] += 1
                lines.append("\(day.dateText)  \(name)")
            } else if covered.contains(day) {
                unassigned += 1
                lines.append("\(day.dateText)  未排班")
            } else {
                unknown += 1
            }
        }
        var text = "\(year)年\(month)月排班统计\n"
        for name in order.sorted(by: { tally[$0]! > tally[$1]! }) { text += "\(name)：\(tally[name]!) 天\n" }
        if unassigned > 0 { text += "未排班：\(unassigned) 天\n" }
        if unknown > 0 { text += "暂无数据：\(unknown) 天\n" }
        text += "\n" + lines.joined(separator: "\n")
        return text
    }

    // MARK: - 备份

    func backupData() throws -> Data {
        let file = BackupFile(settings: settings,
                              schedule: Dictionary(uniqueKeysWithValues: schedule.map { ($0.key.description, $0.value) }),
                              covered: covered.map(\.description).sorted(),
                              roster: roster.mapValues { days in Dictionary(uniqueKeysWithValues: days.map { ($0.key.description, $0.value) }) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    /// 写到临时文件，用来分享 / 存到「文件」App。
    func backupFileURL() throws -> URL {
        let stamp = DayKey.today.description
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("值班提醒备份-\(stamp).json")
        try backupData().write(to: url, options: .atomic)
        return url
    }

    /// 从备份恢复：设置、排班、全员排班整体替换。返回恢复了多少天。
    func restore(from data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupFile.self, from: data)
        var restored: [DayKey: String] = [:]
        for (k, v) in file.schedule { if let d = DayKey(string: k) { restored[d] = v } }
        schedule = restored
        covered = Set(file.covered.compactMap(DayKey.init(string:)))
        roster = file.roster.mapValues { days in
            Dictionary(days.compactMap { k, v in DayKey(string: k).map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
        }
        saveRoster()
        var newSettings = file.settings
        newSettings.rosterVersion = max(newSettings.rosterVersion, Self.rosterVersion)
        settings = newSettings
        scheduleChanged()
        return restored.count
    }

    // MARK: - 工作量统计

    struct Workload {
        struct Person {
            var name: String
            var workDays: Int
            var offDays: Int
            var posts: [(post: String, count: Int)]
        }
        var days: [DayKey]
        var people: [Person]
        var text: String
    }

    /// 休息、调休、请假、无分工都不算上班。
    func isOffPost(_ post: String) -> Bool {
        matcher.match(post)?.id == "off" || post.contains("休") || post.contains("假") || post == "无分工"
    }

    /// 某月每个人的工作量（来自全员排班），按上班天数从多到少。
    func workload(year: Int, month: Int) -> Workload {
        var days = Set<DayKey>()
        var people: [Workload.Person] = []
        for (name, schedule) in roster {
            var work = 0, off = 0
            var counts: [String: Int] = [:]
            for (day, raw) in schedule where day.year == year && day.month == month {
                days.insert(day)
                let posts = raw.split(separator: "+").map { matcher.displayName(String($0)) }
                if posts.allSatisfy(isOffPost) { off += 1 } else { work += 1 }
                for p in posts { counts[p, default: 0] += 1 }
            }
            guard work + off > 0 else { continue }
            let posts = counts.map { (post: $0.key, count: $0.value) }
                .sorted { ($0.count, $1.post) > ($1.count, $0.post) }
            people.append(.init(name: name, workDays: work, offDays: off, posts: posts))
        }
        let zh = Locale(identifier: "zh_CN")
        people.sort { a, b in
            a.workDays != b.workDays ? a.workDays > b.workDays : a.name.compare(b.name, locale: zh) == .orderedAscending
        }
        let sortedDays = days.sorted()
        var text = "\(year)年\(month)月工作量统计"
        if let first = sortedDays.first, let last = sortedDays.last {
            text += "（\(first.dateText) – \(last.dateText)，共 \(sortedDays.count) 天）"
        }
        for p in people {
            text += "\n\(p.name)：上班 \(p.workDays) 天，休 \(p.offDays) 天；"
                + p.posts.map { "\($0.post)×\($0.count)" }.joined(separator: " ")
        }
        return Workload(days: sortedDays, people: people, text: text)
    }
}
