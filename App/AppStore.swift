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

/// 主题色：默认跟随系统（iOS 系统蓝，自动适配浅色 / 深色），也可以选一种喜欢的颜色
enum AccentTheme: String, Codable, CaseIterable, Identifiable {
    case system, indigo, blue, teal, green, orange, pink, purple
    var id: String { rawValue }

    /// 当前用的主题色（App 启动、改设置时写进来，设计系统从这里取）
    static var current: AccentTheme = .system

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .indigo: return "靛蓝"
        case .blue: return "海蓝"
        case .teal: return "青碧"
        case .green: return "松绿"
        case .orange: return "暖橙"
        case .pink: return "樱粉"
        case .purple: return "葡萄紫"
        }
    }

    var color: Color {
        switch self {
        case .system: return Color(uiColor: .systemBlue)
        case .indigo: return Color(light: 0x5E6AD2, dark: 0x8A93FF)
        case .blue: return Color(light: 0x2F6FED, dark: 0x5B9BFF)
        case .teal: return Color(light: 0x0E9AA7, dark: 0x3DD1DB)
        case .green: return Color(light: 0x22A06B, dark: 0x4CC38A)
        case .orange: return Color(light: 0xE5730B, dark: 0xFF9F43)
        case .pink: return Color(light: 0xD6407A, dark: 0xFF6FA5)
        case .purple: return Color(light: 0x8E4EC6, dark: 0xB57BEE)
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
    /// 播报用的声音（空 = 自动选手机上最好的中文声音）
    var voiceIdentifier = ""
    /// 播报语速（0.3–0.6，系统默认 0.5）
    var voiceRate: Float = 0.47
    var appearance: Appearance = .system
    var accentTheme: AccentTheme = .system
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
    /// 只按排班算的人（除调度外另加的）：工作日网站上没排岗位不算工作量
    var scheduleOnlyMembers: [String] = []
    /// 换班账本
    var swapRecords: [SwapRecord] = []
    /// 自己录入的节假日（yyyy-MM-dd）：放假的日子、调休上班的周末
    var customHolidayOff: [String] = []
    var customHolidayWork: [String] = []
    /// 每个人待休天数的变化（只在数字变了时记一笔）
    var restHistory: [String: [RestPoint]] = [:]
    /// 我的待休攒到几天提醒一次（0 不提醒）
    var restAlertThreshold: Int = 5
    /// 上次提醒时的待休天数（再涨了才再提醒）
    var restAlertNotified: Int?
    /// 已经提醒过的「值完遥测该休却排了岗位」（避免重复提醒）
    var warnedRestKeys: [String] = []
    /// 工作留痕：录音自动转文字、只在手机上识别（不联网）、打开要面容 ID
    var workLogAutoTranscribe = true
    var speechOnDeviceOnly = true
    var workLogLock = false
    /// 第一次打开的设置向导走完了没有
    var onboardingDone = false
    /// 网站改版自检：每种读取方式最近几次正常的结果、现在的提醒、哪天推送过
    var syncHealth: [String: [SyncHealth.Metrics]] = [:]
    var syncHealthWarning: String?
    var syncHealthWarnedDay: DayKey?
    /// 人员档案（管理员确认过的角色、来走日期）
    var profiles: [String: PersonProfile] = [:]
    /// 规则改动历史（某天以前按当时的规则算）
    var ruleHistory: [RuleVersion] = []
    /// 读到过休息、请假的读取方式（说明带休息列）
    var leaveSources: [String] = []
    /// 网站排出新一周排班的时间（学网站一般什么时候排班）
    var publishTimes: [Date] = []
    /// 待休对账：已经提醒过的那次变化
    var restLedgerNotified: String?
    /// 值遥测时在锁屏显示倒计时
    var liveActivity: Bool = true
    /// 工作量规则开关
    var workloadRules = WorkloadRules()
    /// 工作量手动纠正：人名 → yyyy-MM-dd → 类别（或「不算」）
    var workloadOverrides: [String: [String: String]] = [:]
    /// 每月 1 号把上个月的工作量发到微信
    var monthlyReport: Bool = true
    var lastMonthlyReport: String?
    /// 关注的同事排班变了也通知
    var notifyFavorites: Bool = true
    /// 全员排班有变动（今天及以后，谁的都算）也提醒
    var notifyAllChanges: Bool = true
    /// 全员换班记录
    var teamChanges: [TeamChange] = []
    /// 遥测下班后补觉到几点（给快捷指令的勿扰自动化用）
    var restFocusUntil = ClockTime(hour: 14, minute: 0)
    /// 组别任务清单勾选：「yyyy-MM-dd|组A」→ 做完的事项
    var taskChecks: [String: [String]] = [:]
    /// 自动备份到的文件夹（「文件」App 里选的，存成书签）
    var backupFolderBookmark: Data?
    var backupFolderName: String?
    var lastAutoBackup: Date?
    var autoBackupMessage: String?
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
    var desktopRosterMessage: String?
    /// 每个人还有几天待休（网页上人名后括号里的数字）
    var restBalance: [String: Int] = [:]
    var restBalanceUpdated: Date?
    /// 改了「我的名字」：下一次同步当作重新开始，不提示变动、不做异常检查
    var nextSyncIsBaseline = false
    /// 网站排了班、但没给我排的日子也提醒（显示「未排班」）
    var remindUnassigned = true
    /// 还没发到微信的排班变动
    var pendingWeChatChange: ChangeLogEntry?
    /// 最近 30 次同步（诊断用）
    var syncLog: [SyncLogEntry] = []
    /// 上次系统在后台唤醒 App 的时间
    var lastBackgroundWake: Date?
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
        voiceIdentifier = try c.decodeIfPresent(String.self, forKey: .voiceIdentifier) ?? d.voiceIdentifier
        voiceRate = try c.decodeIfPresent(Float.self, forKey: .voiceRate) ?? d.voiceRate
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
        accentTheme = try c.decodeIfPresent(AccentTheme.self, forKey: .accentTheme) ?? .system
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
        scheduleOnlyMembers = try c.decodeIfPresent([String].self, forKey: .scheduleOnlyMembers) ?? []
        swapRecords = try c.decodeIfPresent([SwapRecord].self, forKey: .swapRecords) ?? []
        customHolidayOff = try c.decodeIfPresent([String].self, forKey: .customHolidayOff) ?? []
        customHolidayWork = try c.decodeIfPresent([String].self, forKey: .customHolidayWork) ?? []
        restHistory = try c.decodeIfPresent([String: [RestPoint]].self, forKey: .restHistory) ?? [:]
        restAlertThreshold = try c.decodeIfPresent(Int.self, forKey: .restAlertThreshold) ?? 5
        restAlertNotified = try c.decodeIfPresent(Int.self, forKey: .restAlertNotified)
        warnedRestKeys = try c.decodeIfPresent([String].self, forKey: .warnedRestKeys) ?? []
        workLogAutoTranscribe = try c.decodeIfPresent(Bool.self, forKey: .workLogAutoTranscribe) ?? d.workLogAutoTranscribe
        speechOnDeviceOnly = try c.decodeIfPresent(Bool.self, forKey: .speechOnDeviceOnly) ?? d.speechOnDeviceOnly
        workLogLock = try c.decodeIfPresent(Bool.self, forKey: .workLogLock) ?? d.workLogLock
        syncHealth = try c.decodeIfPresent([String: [SyncHealth.Metrics]].self, forKey: .syncHealth) ?? [:]
        syncHealthWarning = try c.decodeIfPresent(String.self, forKey: .syncHealthWarning)
        syncHealthWarnedDay = try c.decodeIfPresent(DayKey.self, forKey: .syncHealthWarnedDay)
        profiles = try c.decodeIfPresent([String: PersonProfile].self, forKey: .profiles) ?? [:]
        ruleHistory = try c.decodeIfPresent([RuleVersion].self, forKey: .ruleHistory) ?? []
        leaveSources = try c.decodeIfPresent([String].self, forKey: .leaveSources) ?? []
        publishTimes = try c.decodeIfPresent([Date].self, forKey: .publishTimes) ?? []
        restLedgerNotified = try c.decodeIfPresent(String.self, forKey: .restLedgerNotified)
        // 老用户（已经填过网址）不再弹向导
        let savedURL = try c.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        onboardingDone = try c.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? !savedURL.isEmpty
        liveActivity = try c.decodeIfPresent(Bool.self, forKey: .liveActivity) ?? true
        workloadRules = try c.decodeIfPresent(WorkloadRules.self, forKey: .workloadRules) ?? WorkloadRules()
        workloadOverrides = try c.decodeIfPresent([String: [String: String]].self, forKey: .workloadOverrides) ?? [:]
        monthlyReport = try c.decodeIfPresent(Bool.self, forKey: .monthlyReport) ?? true
        lastMonthlyReport = try c.decodeIfPresent(String.self, forKey: .lastMonthlyReport)
        notifyFavorites = try c.decodeIfPresent(Bool.self, forKey: .notifyFavorites) ?? true
        notifyAllChanges = try c.decodeIfPresent(Bool.self, forKey: .notifyAllChanges) ?? true
        teamChanges = try c.decodeIfPresent([TeamChange].self, forKey: .teamChanges) ?? []
        restFocusUntil = try c.decodeIfPresent(ClockTime.self, forKey: .restFocusUntil) ?? ClockTime(hour: 14, minute: 0)
        taskChecks = try c.decodeIfPresent([String: [String]].self, forKey: .taskChecks) ?? [:]
        backupFolderBookmark = try c.decodeIfPresent(Data.self, forKey: .backupFolderBookmark)
        backupFolderName = try c.decodeIfPresent(String.self, forKey: .backupFolderName)
        lastAutoBackup = try c.decodeIfPresent(Date.self, forKey: .lastAutoBackup)
        autoBackupMessage = try c.decodeIfPresent(String.self, forKey: .autoBackupMessage)
        changeLog = try c.decodeIfPresent([ChangeLogEntry].self, forKey: .changeLog) ?? []
        syncStaleNotified = try c.decodeIfPresent(Bool.self, forKey: .syncStaleNotified) ?? false
        lastDesktopNotesFetch = try c.decodeIfPresent(Date.self, forKey: .lastDesktopNotesFetch)
        lastDesktopNotesAttempt = try c.decodeIfPresent(Date.self, forKey: .lastDesktopNotesAttempt)
        desktopNotesMessage = try c.decodeIfPresent(String.self, forKey: .desktopNotesMessage)
        desktopNotesURL = try c.decodeIfPresent(String.self, forKey: .desktopNotesURL) ?? ""
        desktopRosterMessage = try c.decodeIfPresent(String.self, forKey: .desktopRosterMessage)
        restBalance = try c.decodeIfPresent([String: Int].self, forKey: .restBalance) ?? [:]
        restBalanceUpdated = try c.decodeIfPresent(Date.self, forKey: .restBalanceUpdated)
        nextSyncIsBaseline = try c.decodeIfPresent(Bool.self, forKey: .nextSyncIsBaseline) ?? false
        remindUnassigned = try c.decodeIfPresent(Bool.self, forKey: .remindUnassigned) ?? true
        pendingWeChatChange = try c.decodeIfPresent(ChangeLogEntry.self, forKey: .pendingWeChatChange)
        syncLog = try c.decodeIfPresent([SyncLogEntry].self, forKey: .syncLog) ?? []
        lastBackgroundWake = try c.decodeIfPresent(Date.self, forKey: .lastBackgroundWake)
        desktopGroupNotes = try c.decodeIfPresent([String: String].self, forKey: .desktopGroupNotes) ?? [:]
        lastSuccessMessage = try c.decodeIfPresent(String.self, forKey: .lastSuccessMessage)
        shiftTypes = try c.decodeIfPresent([ShiftType].self, forKey: .shiftTypes) ?? d.shiftTypes
        lastSync = try c.decodeIfPresent(Date.self, forKey: .lastSync)
        lastSyncMessage = try c.decodeIfPresent(String.self, forKey: .lastSyncMessage)
    }
}

/// 一次同步的记录（诊断页「最近同步」），用来看后台到底有没有同步
struct SyncLogEntry: Codable, Hashable {
    var date: Date
    /// 打开 App / 下拉刷新 / 后台刷新 / 快捷指令…
    var source: String
    var ok: Bool
    var message: String
    var seconds: Int
}

/// 某天的待休天数
struct RestPoint: Codable, Hashable {
    var day: DayKey
    var value: Int
    /// false = 从以前几周的表上读的；nil / true = 同步时当场读到的
    var live: Bool? = nil

    var point: RestBalanceHistory.Point { (day, value, live ?? true) }
    init(day: DayKey, value: Int, live: Bool? = nil) { self.day = day; self.value = value; self.live = live }
    init(_ p: RestBalanceHistory.Point) { self.init(day: p.day, value: p.value, live: p.live ? nil : false) }
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

extension ClockTime {
    /// 给时间选择器用的 Date（日期部分无意义）
    var date: Date {
        Calendar.app.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hour, minute: minute)) ?? Date()
    }

    init(date: Date) {
        let c = Calendar.app.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }
}

extension DayKey {
    /// 周一…周日
    var weekdayText: String {
        let w = Calendar.app.component(.weekday, from: date(calendar: .app, hour: 12))
        return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][w - 1]
    }
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
            workloadCache = [:]
            dataRevision &+= 1
            // 不是管理员：排班数据改不了（同步自动更新的不受影响）
            if !canEdit {
                var fixed = settings
                fixed.workloadRules = oldValue.workloadRules
                fixed.workloadOverrides = oldValue.workloadOverrides
                fixed.customHolidayOff = oldValue.customHolidayOff
                fixed.customHolidayWork = oldValue.customHolidayWork
                fixed.manualGroupNotes = oldValue.manualGroupNotes
                fixed.scheduleOnlyMembers = oldValue.scheduleOnlyMembers
                fixed.shiftTypes = oldValue.shiftTypes
                fixed.profiles = oldValue.profiles
                fixed.ruleHistory = oldValue.ruleHistory
                if fixed != settings { settings = fixed }
                guard settings != oldValue else { return }
            }
            if settings.aliases != oldValue.aliases { settings.nextSyncIsBaseline = true }
            if settings.shiftTypes != oldValue.shiftTypes {
                publishedDays = Self.published(in: roster, matcher: matcher)
            }
            if settings.customHolidayOff != oldValue.customHolidayOff || settings.customHolidayWork != oldValue.customHolidayWork
                || settings.workloadRules != oldValue.workloadRules || settings.workloadOverrides != oldValue.workloadOverrides
                || settings.accentTheme != oldValue.accentTheme
                || settings.voiceIdentifier != oldValue.voiceIdentifier || settings.voiceRate != oldValue.voiceRate
                || settings.profiles != oldValue.profiles || settings.ruleHistory != oldValue.ruleHistory {
                applyCustomHolidays()
            }
            save()
            requestReschedule()
        }
    }
    @Published private(set) var schedule: [DayKey: String] {
        didSet {
            dutyTurnCache = nil
            workloadCache = [:]
            dataRevision &+= 1
        }
    }
    /// 已经取到过结果的日子：有排班的显示班次，没排班的显示「未排班」；不在这里的日子还没有数据
    @Published private(set) var covered: Set<DayKey>
    /// 全员排班（姓名 → 日期 → 岗位），只存在手机上，用于搜索成员
    @Published private(set) var roster: Roster = [:] {
        didSet {
            publishedDays = Self.published(in: roster, matcher: matcher)
            dutyTurnCache = nil
            workloadCache = [:]
            dataRevision &+= 1
        }
    }
    /// 网站上已经正式排了班的日子：这一天有人排了组别（组A–E）或遥测。
    /// 只有提前申请的请假、调休、出差的日子还没排班，不能当成「这天大家都在上日常班」。
    @Published private(set) var publishedDays: Set<DayKey> = []

    static func published(in roster: Roster, matcher: ShiftMatcher) -> Set<DayKey> {
        var result = Set<DayKey>()
        for days in roster.values {
            for (day, raw) in days where !result.contains(day) {
                let posts = raw.split(separator: "+").map { matcher.displayName(String($0)) }
                if posts.contains(where: { WorkloadBalance.isGroup($0) || WorkloadCounter.isDuty($0) }) { result.insert(day) }
            }
        }
        return result
    }
    @Published private(set) var isSyncing = false
    /// 上次读电脑版页面时看到的文字（只在内存里，排查用）
    @Published var desktopPageText: String?

    private static let rosterURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("roster.json")
    }()

    private static let sourcesURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("roster-sources.json")
    }()
    private static let logURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("roster-log.json")
    }()

    /// 每条全员排班的来源（从哪读的、什么时候）
    private(set) var rosterSources: RosterSources = AppStore.loadSources()
    /// 排班变动历史（网站上谁哪天的岗位变了），最近 3000 条
    @Published private(set) var rosterLog: [RosterEdit] = AppStore.loadLog()

    private static func loadSources() -> RosterSources {
        guard let data = try? Data(contentsOf: sourcesURL),
              let raw = try? JSONDecoder().decode([String: [String: Provenance]].self, from: data) else { return [:] }
        return raw.mapValues { days in
            Dictionary(days.compactMap { k, v in DayKey(string: k).map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
        }
    }

    private static func loadLog() -> [RosterEdit] {
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        return (try? JSONDecoder().decode([RosterEdit].self, from: data)) ?? []
    }

    private func saveSourcesAndLog() {
        if Self.isDemo { return }
        let raw = rosterSources.mapValues { days in Dictionary(uniqueKeysWithValues: days.map { ($0.key.description, $0.value) }) }
        if let data = try? JSONEncoder().encode(raw) {
            try? data.write(to: Self.sourcesURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        if let data = try? JSONEncoder().encode(rosterLog) {
            try? data.write(to: Self.logURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private static func loadRoster() -> Roster {
        guard let data = try? Data(contentsOf: rosterURL),
              let raw = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return raw.mapValues { days in
            Dictionary(days.compactMap { k, v in DayKey(string: k).map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
        }
    }

    private func saveRoster() {
        if Self.isDemo { return }
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
        let data = try? Data(contentsOf: Self.fileURL)
        let state = data.flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
        // 读不出来（比如新版本改了格式）：先把原文件另存一份，别让下次保存把它覆盖掉
        if let data, state == nil {
            try? data.write(to: Self.fileURL.deletingLastPathComponent().appendingPathComponent("state.bad.json"))
        }
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
            rosterSources = [:]
            rosterLog = []
            saveSourcesAndLog()
            settings.leaveSources = []
            settings.rosterVersion = Self.rosterVersion
            settings.lastSync = nil   // 打开 App 后马上重新同步
            save()
        }
        // init 里赋值不会触发 didSet，手动算一次
        publishedDays = Self.published(in: roster, matcher: ShiftMatcher(types: settings.shiftTypes))
        applyCustomHolidays()
        if Self.isDemo { loadDemoData() }
    }

    /// 截图用的演示模式（启动参数 -demo）：全是虚构数据，不读写手机上的文件、不联网
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    private func loadDemoData() {
        let me = "陈晨"
        let people = [me, "林夏", "周远", "孙悦", "赵一凡", "钱程", "苏桐", "郑宁"]
        let groups = ["组A", "组B", "组C", "组D", "组E"]
        let today = DayKey.today
        var r: Roster = [:]
        for offset in -40...14 {
            let day = today.adding(days: offset)
            let weekday = Calendar.app.component(.weekday, from: day.date(calendar: .app, hour: 12))
            let workday = weekday != 1 && weekday != 7
            let duty = people[((offset % 8) + 8) % 8]
            r[duty, default: [:]][day] = "遥测"
            // 值完遥测的第二天休息
            let resting = people[((offset - 1) % 8 + 8) % 8]
            r[resting, default: [:]][day] = "休息"
            if workday {
                var g = 0
                for (i, p) in people.enumerated() where p != duty && p != resting && g < groups.count {
                    if (i + offset) % 7 == 0 { continue }   // 有人没排岗位：正常上班
                    r[p, default: [:]][day] = groups[(g + offset + 50) % groups.count]
                    g += 1
                }
                r["何安", default: [:]][day] = "调度"
            }
            if offset == 3 { r["钱程", default: [:]][day] = "出差" }
        }
        var s = AppSettings()
        s.aliases = [me]
        s.favorites = ["林夏", "周远"]
        s.restBalance = ["陈晨": 3, "林夏": 5, "周远": 1, "孙悦": 2, "赵一凡": 4, "钱程": 0, "苏桐": 6, "郑宁": 2]
        s.restHistory = [me: [RestPoint(day: today.adding(days: -30), value: 1), RestPoint(day: today.adding(days: -18), value: 2),
                              RestPoint(day: today.adding(days: -9), value: 4), RestPoint(day: today, value: 3)]]
        s.manualGroupNotes = ["组A": "1、巡检机房；2、填写运行日志；3、16:30 前交接", "组B": "数据处理与归档",
                              "组C": "设备维护", "组D": "值守监控", "组E": "外场保障"]
        s.changeLog = [ChangeLogEntry(date: Date().addingTimeInterval(-3600),
                                      text: "\(today.adding(days: 2).dateText)：组B → 组D（和周远对换：周远原来是组D，现在是组B）")]
        s.swapRecords = [SwapRecord(day: today.adding(days: -6), person: "林夏", myOld: "遥测", myNew: "休息", effect: -1)]
        s.teamChanges = [TeamChange(day: today.adding(days: 2), post: "组B", from: ["周远"], to: [me])]
        s.lastSync = Date().addingTimeInterval(-600)
        s.lastSyncMessage = "同步成功：网页接口，30 天，没有变动，这次读到 9 人有排班（全年累计 12 人）"
        settings = s
        roster = r
        schedule = r[me] ?? [:]
        covered = Set((-40...14).map { today.adding(days: $0) })
    }

    /// 把自己录入的节假日交给统计用的节假日表
    func applyCustomHolidays() {
        AccentTheme.current = settings.accentTheme
        VoiceSound.voiceIdentifier = settings.voiceIdentifier
        VoiceSound.rate = min(max(settings.voiceRate, 0.3), 0.6)
        ChinaHolidays.customOff = Set(settings.customHolidayOff)
        ChinaHolidays.customWork = Set(settings.customHolidayWork)
        WorkloadCounter.rules = settings.workloadRules
        WorkloadCounter.ruleHistory = settings.ruleHistory
        WorkloadCounter.profiles = settings.profiles
        WorkloadCounter.overrides = settings.workloadOverrides.mapValues { days in
            Dictionary(days.compactMap { k, v in DayKey(string: k).map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
        }
    }

    /// 工作量手动纠正：value 为 nil 时恢复自动
    func setOverride(_ name: String, _ day: DayKey, _ value: String?) {
        guard canEdit else { ToastCenter.shared.show("只有管理员能修改", style: .error); return }
        var all = settings.workloadOverrides
        var days = all[name] ?? [:]
        days[day.description] = value
        all[name] = days.isEmpty ? nil : days
        settings.workloadOverrides = all
    }

    func override(_ name: String, _ day: DayKey) -> String? { settings.workloadOverrides[name]?[day.description] }

    private static let rosterVersion = 3

    private func save() {
        if Self.isDemo { return }
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
        guard canEdit else { ToastCenter.shared.show("只有管理员能修改排班", style: .error); return }
        let v = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule[day] = (v?.isEmpty ?? true) ? nil : v
        covered.insert(day)
        scheduleChanged()
    }

    /// 导入/同步：用新数据整体替换它覆盖的那段日期（这段时间里被删掉的班次也会同步删除）。
    @discardableResult
    /// publishedBefore：同步前网站已经排了班的日子。以后的日子在网站正式排班前取到的只是请假、调休，
    /// 网站第一次排出这一周时不算「变动」。
    func apply(_ result: ParseResult, publishedBefore: Set<DayKey>? = nil, rosterDaysBefore: Set<DayKey> = []) -> [ScheduleChange] {
        let old = schedule
        let today = DayKey.today
        // 只有这种情况不算「之前就知道」：以后的某天，全员排班里只有请假、调休这些提前申请的记录，
        // 还没人排组别、遥测（网站还没排到那天）。全员排班里根本没有那天的数据时，照常算变动。
        let knownBefore = covered.filter { day in
            guard let published = publishedBefore, !published.isEmpty else { return true }
            return day <= today || published.contains(day) || !rosterDaysBefore.contains(day)
        }
        var new = schedule
        let replaced = result.replacedDays(calendar: .app)
        if !replaced.isEmpty {
            new = new.filter { !replaced.contains($0.key) }
            covered.formUnion(replaced)
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
            case _ where post.hasPrefix("值班") || post.contains("交班") || post.contains("交接"): return (3, post)
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

    /// 是不是我自己（按「我的名字」判断）。管理者自己没有排班，谁都不是「我」。
    func isMe(_ name: String) -> Bool { role != .manager && parser.isMe(name) }

    // MARK: - 身份

    /// 当前身份（存在本机，不随备份走）
    @Published private(set) var role: UserRole = AppStore.isDemo
        ? .admin : (UserRole(rawValue: UserDefaults.standard.string(forKey: "userRole") ?? "") ?? .user)

    /// 只有管理员能改排班数据（手动改班、工作量纠正、规则、节假日、各组内容、班次类型、导入、恢复备份）
    var canEdit: Bool { role == .admin }

    /// 以管理者或管理员身份登录；密码不对返回 false
    func login(password: String, as role: UserRole) async -> Bool {
        guard await RoleAuth.verify(password, as: role) else { return false }
        setRole(role)
        return true
    }

    func logout() { setRole(.user) }

    private func setRole(_ r: UserRole) {
        role = r
        UserDefaults.standard.set(r.rawValue, forKey: "userRole")
        dutyTurnCache = nil
        requestReschedule()
    }

    /// 这一天是否已经取到过排班结果（没排班也算）。
    /// 以后的日子，全员排班里还没人排组别、遥测（网站还没排到那天）时，不算取到了
    func isCovered(_ day: DayKey) -> Bool {
        if schedule[day] != nil { return true }
        guard covered.contains(day) else { return false }
        return day <= .today || roster.isEmpty || publishedDays.contains(day)
    }

    func clearSchedule() {
        guard canEdit else { ToastCenter.shared.show("只有管理员能清空排班", style: .error); return }
        schedule = [:]
        covered = []
        roster = [:]
        saveRoster()
        resetRosterTracking()
        scheduleChanged()
    }

    /// 全员排班清空后，来源、变动历史、「哪种读取带休息列」也一起清掉，下次读到的当作第一次（不提醒）
    private func resetRosterTracking() {
        rosterSources = [:]
        rosterLog = []
        saveSourcesAndLog()
        settings.leaveSources = []
    }

    private func scheduleChanged() {
        save()
        requestReschedule()
    }

    private var rescheduleTask: Task<Void, Never>?

    /// 设置、排班一次同步会改好几处：等 0.3 秒合并成一次重新登记提醒，后来的取消前面没做完的，
    /// 免得慢的那次（录语音）最后完成、用旧排班覆盖新排班。
    func requestReschedule() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.rescheduleNotifications()
        }
    }

    private var debounceTask: Task<Void, Never>?

    /// 马上重新登记（等它做完）。一次接一次排队做，绝不同时进行：
    /// 每次开始时读的都是当时最新的排班，不会有慢的旧任务最后完成、把新提醒盖掉。
    func rescheduleNotifications() async {
        // 这一次会读最新的状态，排着的「0.3 秒后再做一次」不需要了（后台时间到了也不会多做一半）
        debounceTask?.cancel()
        debounceTask = nil
        let previous = rescheduleTask
        let task = Task { [weak self] in
            await previous?.value
            await self?.performReschedule()
        }
        rescheduleTask = task
        await task.value
    }

    // MARK: - 提醒

    private var planner: NotificationPlanner {
        var p = NotificationPlanner(
            morning: settings.morningEnabled ? settings.morning : nil,
            evening: settings.eveningEnabled ? settings.evening : nil,
            // 还没取到数据的日子不提醒；排了班但没给我排的日子由 reminderSchedule 补「未排班」
            notifyWhenEmpty: false,
            matcher: matcher,
            calendar: .app)
        p.weekly = settings.weeklyPreview
        return p
    }

    /// 提醒用的排班：已经取到数据、但没给我排班的日子补上「未排班」，这样每天都会提醒。
    var reminderSchedule: [DayKey: String] {
        var s = schedule
        let today = DayKey.today
        // 网站还没排到的日子不提醒「未排班」
        if settings.remindUnassigned {
            for day in covered where day >= today && s[day] == nil && isCovered(day) { s[day] = "未排班" }
        }
        return s
    }

    private func performReschedule() async {
        // 手机上的通知带上组别工作内容；微信那份不带（只发自己的分工）
        var local = planner
        local.notes = groupNotes
        await NotificationService.reschedule(local.plan(schedule: reminderSchedule, now: Date()), voice: settings.voiceEnabled)
        updateWidget()
        updateAppIcon()
        DutyActivityManager.update(schedule: schedule, matcher: matcher, enabled: settings.liveActivity)
        if settings.calendarSync { CalendarSync.sync(schedule, matcher: matcher) }
        await NotificationService.scheduleSigningReminder(expiry: SigningInfo.expirationDate)
        // App 一直没机会运行（后台刷新被系统停掉）时，到点由系统弹出提醒
        await NotificationService.scheduleStaleReminder(after: canSync ? settings.lastSync : nil)
    }

    /// 今天该用哪个图标：遥测「遥」，组A–组E 用对应字母（一天多个组取第一个），调度「调」，出差「差」，
    /// 无分工/休息/调休/请假「休」，其它用默认的「值」。
    func iconName(for raw: String?) -> String? {
        guard let raw else { return nil }
        let posts = raw.split(separator: "+").map { matcher.displayName(String($0)) }
        if posts.contains(where: WorkloadCounter.isDuty) { return "IconDuty" }
        if let r = raw.range(of: #"组\s*[A-Ea-e]"#, options: .regularExpression), let letter = raw[r].last {
            return "Icon" + letter.uppercased()
        }
        if posts.contains(where: { $0.contains("调度") }) { return "IconDispatch" }
        if posts.contains(where: WorkloadCounter.isTrip) { return "IconTrip" }
        if posts.allSatisfy({ WorkloadCounter.isOff($0, matcher: matcher) }) || matcher.match(raw)?.id == "off" { return "IconRest" }
        return nil
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
            guard let raw = schedule[day] else {
                // 取到过、但没给我排班
                return isCovered(day) ? WidgetDay(date: day.description, title: "未排班", emoji: "", colorHex: "#8E8E93") : nil
            }
            let type = matcher.match(raw)
            return WidgetDay(date: day.description, title: matcher.displayName(raw),
                             emoji: type?.emoji ?? "📌", colorHex: type?.colorHex ?? "#8E8E93")
        }
        WidgetStore.save(WidgetSnapshot(days: days, updated: Date(), tasks: widgetTasks(for: today)))
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

    // MARK: - 同步

    var canSync: Bool { !Self.isDemo && !settings.sourceURL.trimmingCharacters(in: .whitespaces).isEmpty }

    @discardableResult
    /// full：一页页翻「值班查看」读全员排班（较慢，约半分钟）；后台和快捷指令里不翻页，只用网站接口补取全员排班，避免超过系统给的时间。
    /// userInitiated：用户手动刷新。登录失败过一次后，只有手动刷新才再尝试登录，防止密码错误时反复登录把账号锁住；
    /// 同步结果和之前差别过大时，也只有手动刷新才采用。
    func sync(full: Bool = true, userInitiated: Bool = false, source: String? = nil) async -> Bool {
        let source = source ?? (userInitiated ? "手动刷新" : (full ? "打开 App" : "后台"))
        // 正在同步：等它做完，用它的结果（快捷指令不会因为撞上自动同步而说「没有数据」）
        if let running = syncTask {
            let runningWasUser = syncTaskUserInitiated
            let runningAliases = syncTaskAliases
            let ok = await running.value
            // 等的时候换了人、改了名字：那次是按旧名字读的，要重新来一次
            let renamed = settings.aliases != runningAliases
            // 自动同步不会重试登录、不采用异常结果；手动下拉要自己再来一次
            // 只有那次自动同步失败（没登录上、结果异常被忽略）时才再来一次
            guard renamed || (userInitiated && !runningWasUser && !ok) else { return ok }
            // 等待期间别人已经开始了新的一次：用那一次
            if let next = syncTask { return await next.value }
        }
        // 放在独立的任务里跑：下拉刷新的界面消失、切换页面时 SwiftUI 会取消调用方，
        // 不能让读到一半的全员排班跟着作废（以前会显示「CancellationError」）
        let task = Task { () -> Bool in
            let start = Date()
            let ok = await self.performSync(full: full, userInitiated: userInitiated)
            if self.canSync {
                let entry = SyncLogEntry(date: start, source: source, ok: ok,
                                         message: self.settings.lastSyncMessage ?? "", seconds: Int(Date().timeIntervalSince(start)))
                self.settings.syncLog = Array(([entry] + self.settings.syncLog).prefix(30))
            }
            // 在任务里面清掉：所有在等它的人醒来时，都能看到「已经没有正在进行的同步」
            self.syncTask = nil
            return ok
        }
        syncTask = task
        syncTaskUserInitiated = userInitiated
        syncTaskAliases = settings.aliases
        return await task.value
    }

    /// 上次同步看到的网站数据接口字段（只在内存里，「设置 › 接口字段查看」用）
    @Published private(set) var apiFields: [APIFieldTable] = []
    @Published private(set) var apiFieldsDate: Date?

    private var syncTask: Task<Bool, Never>?
    private var syncTaskUserInitiated = false
    private var syncTaskAliases: [String] = []

    private func performSync(full: Bool, userInitiated: Bool) async -> Bool {
        guard canSync, !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }
        let aliasesAtStart = settings.aliases
        do {
            let mayLogin = userInitiated || !settings.loginExpiredNotified
            let outcome = try await SyncService.fetchSchedule(urlString: settings.sourceURL,
                                                              username: settings.sourceUsername,
                                                              password: mayLogin ? (Keychain.get(.sourcePassword) ?? "") : "",
                                                              viaWeb: settings.syncViaWeb,
                                                              // 后台和快捷指令也读全员排班，只是不一页页翻（时间有限）
                                                              includeRoster: true,
                                                              pageThroughRoster: full,
                                                              parser: parser,
                                                              aliases: settings.aliases,
                                                              matcher: matcher,
                                                              preferredAPI: settings.apiSignature)
            let result = outcome.result
            // 同步途中换了人、改了名字：这次是按旧名字读的，不能当成现在这个人的班。交给下一次同步
            guard settings.aliases == aliasesAtStart else { return false }
            if !userInitiated, !settings.nextSyncIsBaseline, result.range != nil {
                // 已经知道的日子里，一大半都变了：多半是网站改版读错了，先不采用
                let today = DayKey.today
                let replaced = result.replacedDays(calendar: .app)
                // 和 apply() 同一个规则：网站还没正式排班、只有请假调休记录的以后日子不算「已经知道」，
                // 不然网站第一次排出新一周时会被当成异常一直挡住
                let rosterDays = Set(roster.values.flatMap(\.keys))
                let known = covered.filter { day in
                    guard day >= today, replaced.contains(day) else { return false }
                    return publishedDays.isEmpty || day == today || publishedDays.contains(day) || !rosterDays.contains(day)
                }
                let changed = known.filter { schedule[$0] != result.entries[$0] }.count
                if known.count >= 5 && changed * 10 > known.count * 6 {
                    let alreadyTold = settings.lastSyncMessage?.hasPrefix("同步结果异常") == true
                    settings.lastSyncMessage = "同步结果异常：\(known.count) 天里有 \(changed) 天和之前不同，可能是网站改版，已忽略。下拉刷新可确认采用"
                    if !alreadyTold {
                        await NotificationService.notifyNow(id: "sync-anomaly",
                                                            title: "排班变化很大，没有自动采用",
                                                            body: "\(known.count) 天里有 \(changed) 天和之前不同。打开值班提醒下拉刷新确认。")
                    }
                    return false
                }
            }
            if let signature = outcome.apiSignature { settings.apiSignature = signature }
            if !outcome.apiFields.isEmpty { apiFields = outcome.apiFields; apiFieldsDate = Date() }
            let rosterBefore = roster
            let publishedBefore = publishedDays
            let freshDays = Set(outcome.roster.values.flatMap(\.keys))
            let baselineRun = settings.nextSyncIsBaseline || rosterBefore.isEmpty
            // 读到的全员排班明显不对（读了一半、网站改版）：自动同步先不合并，免得冲掉数据、乱提醒；手动下拉照常采用
            let healthy = await checkSyncHealth(outcome.roster, source: full ? "sync-full" : "sync-quick", title: "同步",
                                                accept: userInitiated)
            if healthy || userInitiated {
                let edits = mergeRoster(outcome.roster, source: "sync")
                if !baselineRun { await notifyRosterEdits(edits, published: publishedBefore) }
                if !baselineRun { await recordTeamChanges(before: rosterBefore, days: freshDays.intersection(publishedBefore)) }
            }
            await notifyRestWarnings()
            updateRestBalance(outcome.restBalance)
            if !outcome.groupNotes.isEmpty { settings.autoGroupNotes.merge(outcome.groupNotes) { _, n in n } }

            let hadData = !schedule.isEmpty && !settings.nextSyncIsBaseline
            // 同步途中又改了名字：这次用的是旧名字，下次还要当作重新开始
            if settings.aliases == aliasesAtStart { settings.nextSyncIsBaseline = false }
            let changes = apply(result, publishedBefore: publishedBefore,
                                rosterDaysBefore: Set(rosterBefore.values.flatMap(\.keys)))
            settings.lastSync = Date()
            settings.loginExpiredNotified = false
            settings.syncStaleNotified = false
            settings.lastSyncMessage = "同步成功：\(result.format.rawValue)，\(result.entries.count) 天"
                + (changes.isEmpty ? "，没有变动" : "，\(changes.count) 处变动")
                + (outcome.roster.isEmpty ? "" : "，这次读到 \(outcome.roster.count) 人有排班（全年累计 \(roster.count) 人）")
            settings.lastSuccessMessage = settings.lastSyncMessage
            // 第一次导入不算“变动”，之后每次同步发现不同就提醒
            if hadData && !changes.isEmpty {
                let title = "📢 排班有更新（\(changes.count) 处）"
                let body = ScheduleDiff.summary(changes, matcher: matcher, calendar: .app) {
                    self.swapDetail($0, before: rosterBefore, fresh: freshDays)
                }
                // 换班账本：谁替我上了、我替谁上了
                var records = settings.swapRecords
                for change in changes {
                    SwapLedger.merge(SwapLedger.detect(change, before: rosterBefore, after: roster,
                                                       fresh: freshDays.contains(change.day), matcher: matcher, isMe: isMe),
                                     into: &records)
                }
                if records != settings.swapRecords { settings.swapRecords = Array(records.prefix(300)) }
                // 首页「最近排班变动」总是记下；通知、微信看开关
                settings.changeLog = Array(([ChangeLogEntry(date: Date(), text: body)] + settings.changeLog).prefix(20))
                if settings.notifyChanges {
                    // 每次变动一条，后一次不会把前一次顶掉
                    await NotificationService.notifyNow(id: "schedule-changed-\(UUID().uuidString)", title: title, body: body)
                }
                do {
                    // 微信有自己的开关，和 iPhone 通知分开；同样的变动不重复发；没发出去的留着下次补发
                    if settings.weChatEnabled && settings.weChatChanges && settings.lastWeChatChangeDigest != body {
                        settings.lastWeChatChangeDigest = body
                        // 上次没发出去的先补发；还是发不出去就合在一起，不丢掉前一次的变动
                        await sendPendingWeChatChange()
                        if let older = settings.pendingWeChatChange {
                            let olderBody = older.text.split(separator: "\n", maxSplits: 1).dropFirst().joined()
                            settings.pendingWeChatChange = ChangeLogEntry(date: Date(), text: title + "\n" + body + "\n" + olderBody)
                        } else {
                            settings.pendingWeChatChange = ChangeLogEntry(date: Date(), text: title + "\n" + body)
                        }
                        await sendPendingWeChatChange()
                    }
                }
            }
            // 手机版没有各组工作内容：打开 App 时每天用电脑版页面读一次（读不到不影响同步结果，过 1 小时再试）
            let now = Date()
            if full, settings.syncViaWeb,
               now.timeIntervalSince(settings.lastDesktopNotesFetch ?? .distantPast) > 20 * 3600,
               now.timeIntervalSince(settings.lastDesktopNotesAttempt ?? .distantPast) > 3600 {
                // 同步结束后再单独读（约半分钟），不拖慢同步、不让快捷指令等它
                settings.lastDesktopNotesAttempt = now
                Task { [weak self] in await self?.readDesktopNotes(mayLogin: mayLogin) }
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
    /// 设置、工作量页上的按钮：和同步共用一个「正在进行」标记，两个隐藏浏览器不会同时登录
    @discardableResult
    /// 读电脑版页面要半分钟左右：不占用「正在同步」，快捷指令、后台同步不用等它；
    /// 但等正在进行的同步结束后再开始，两个隐藏浏览器不会同时登录。
    /// weeksBack：电脑版页面往前翻几周（默认 9 周，约两个月）
    func readDesktopNotes(mayLogin: Bool = true, weeksBack: Int = 9) async -> Bool {
        guard !isReadingDesktop else { return false }
        isReadingDesktop = true
        defer { isReadingDesktop = false }
        while isSyncing { try? await Task.sleep(nanoseconds: 500_000_000) }
        return await readDesktopNotesNow(mayLogin: mayLogin, weeksBack: weeksBack)
    }

    /// 从电脑版页面一周周往前翻，读到某年 1 月 1 日为止（App 只留一年多的全员排班）
    @discardableResult
    func readHistory(since year: Int) async -> Bool {
        let start = DayKey(year: year, month: 1, day: 1).date(calendar: .app, hour: 12)
        let days = Calendar.app.dateComponents([.day], from: start, to: Date()).day ?? 0
        return await readDesktopNotes(weeksBack: min(60, max(1, days / 7 + 1)))
    }

    @Published private(set) var isReadingDesktop = false

    @discardableResult
    private func readDesktopNotesNow(mayLogin: Bool, weeksBack: Int = 9) async -> Bool {
        let readStarted = Date()
        settings.lastDesktopNotesAttempt = readStarted
        let result = await Task {
            await SyncService.fetchDesktopGroupNotes(urlString: settings.sourceURL,
                                                     overrideURL: settings.desktopNotesURL,
                                                     username: settings.sourceUsername,
                                                     password: mayLogin ? (Keychain.get(.sourcePassword) ?? "") : "",
                                                     reference: .today,
                                                     matcher: matcher, weeksBack: weeksBack)
        }.value
        desktopPageText = "网址：\(result.url)\n\n" + (result.pageText.isEmpty ? "（没有内容）" : result.pageText)
        // 读的这半分钟里如果开始了同步，等它做完再合并
        while isSyncing { try? await Task.sleep(nanoseconds: 500_000_000) }
        var healthy = true
        // 页面打不开、没登录上（不是改版）不比；翻的周数不同读到的天数也不同，分开比
        if !(result.roster.isEmpty && result.reason != nil) {
            healthy = await checkSyncHealth(result.roster, source: "desktop-\(weeksBack)", title: "电脑版页面")
        }
        if healthy {
            let rosterBefore = roster
            let publishedBefore = publishedDays
            // 之前还没有哪种读取带过休息列（刚装、刚重置、刚恢复后第一次读电脑版）：读到的请假、休息都会像「新变动」，不提醒
            let baseline = settings.nextSyncIsBaseline || rosterBefore.isEmpty || settings.leaveSources.isEmpty
            // 读的途中同步过：电脑版数据比同步的旧，只合并不提醒（变动由同步提醒过了）
            let stale = (settings.lastSync ?? .distantPast) > readStarted
            let edits = mergeRoster(result.roster, source: "desktop")
            if !baseline && !stale {
                await notifyRosterEdits(edits, published: publishedBefore)
                let days = Set(result.roster.values.flatMap(\.keys))
                await recordTeamChanges(before: rosterBefore, days: days.intersection(publishedBefore))
            }
        }
        mergeRestHistory(result.restByDay)
        await notifyRestWarnings()
        updateRestBalance(result.restBalance)
        let days = Set(result.roster.values.flatMap(\.keys))
        if let lo = days.min(), let hi = days.max() {
            settings.desktopRosterMessage = "读到 \(result.roster.count) 人、\(days.count) 天（\(lo.dateText) – \(hi.dateText)）"
        } else {
            settings.desktopRosterMessage = "没读到全员排班（\(Date().formatted(date: .omitted, time: .shortened))）"
        }
        if result.notes.isEmpty {
            settings.desktopNotesMessage = "没读到（\(Date().formatted(date: .omitted, time: .shortened))）：\(result.reason ?? "没找到说明")"
            return false
        }
        await applyDesktopNotes(result.notes)
        return true
    }

    /// 把这个 App 设成某个人用：名字换成他，清掉和上一个人有关的提醒记录，马上按新名字同步
    func setMe(_ name: String) {
        var s = settings
        s.aliases = [name]
        s.warnedRestKeys = []
        s.restAlertNotified = nil
        settings = s
        // 换人：先用全员排班里这个人的班顶上，不留上一个人的；同步后再用网站上「我的分工」更新
        schedule = roster[name] ?? [:]
        covered = publishedDays.union(schedule.keys)
        dutyTurnCache = nil
        scheduleChanged()
        guard canSync else { return }
        Task { await sync(userInitiated: true, source: "换了使用者") }
    }

    // MARK: 网站改版自检

    /// 这次读到的全员排班和平时比：人数、天数、休息条数、组别条数突然少很多就提醒（一天最多推送一次）。
    /// 不正常的结果不记进「平时」，免得把错的当成正常。
    /// 返回读到的是否正常。accept：用户手动确认采用的，这次也记进「平时」，网站真改版了以后就不再一直报
    @discardableResult
    func checkSyncHealth(_ roster: Roster, source: String, title: String, accept: Bool = false) async -> Bool {
        guard !Self.isDemo else { return true }
        let metrics = SyncHealth.metrics(roster, matcher: matcher)
        var all = settings.syncHealth
        let history = all[source] ?? []
        let problems = SyncHealth.problems(metrics, history: history)
        if problems.isEmpty || accept {
            all[source] = Array((history + [metrics]).suffix(10))
            var s = settings
            s.syncHealth = all
            s.syncHealthWarning = nil
            settings = s
            return true
        }
        let text = "\(title)读到的全员排班和平时不一样：" + problems.joined(separator: "；")
            + "。可能是网站改版了，工作量统计、休息核对可能不准。"
        settings.syncHealthWarning = text
        guard settings.syncHealthWarnedDay != .today else { return false }
        settings.syncHealthWarnedDay = .today
        await NotificationService.notifyNow(id: "sync-health", title: "⚠️ 值班网站可能改版了", body: text)
        return false
    }

    // MARK: 排班规律：下次遥测、排班预警

    /// 按「顺序 + 请假出差顺延」推算的下次遥测
    struct DutyTurn {
        /// 网站已经排好的日子，或者按顺序推算的日子（推不出来为 nil）
        var day: DayKey?
        /// 前面还有几个人
        var ahead: Int
        /// 是不是网站上已经排好的
        var scheduled: Bool
        /// 一共几个人轮
        var total: Int
    }

    private var dutyTurnCache: (key: String, value: DutyTurn?)?

    func myDutyTurn() -> DutyTurn? {
        guard let me = myRosterName else { return nil }
        let today = DayKey.today
        let key = "\(today)-\(me)-\(roster.count)-\(publishedDays.count)-\(roster[me]?.count ?? 0)-\(schedule.count)"
        if let cache = dutyTurnCache, cache.key == key { return cache.value }
        let value: DutyTurn?
        let mine = (roster[me] ?? [:]).merging(schedule) { a, _ in a }
        if let next = mine.filter({ $0.key >= today && $0.value.split(separator: "+").contains { WorkloadCounter.isDuty(matcher.displayName(String($0))) } }).keys.min() {
            value = DutyTurn(day: next, ahead: 0, scheduled: true, total: 0)
        } else {
            let days = publishedDays.filter { $0 >= today.adding(days: -180) }.sorted()
            if let r = SchedulePatterns.rotation(post: "遥测", roster: roster, days: days, matcher: matcher, forecastDays: 60, calendar: .app),
               let index = r.order.firstIndex(of: me) {
                value = DutyTurn(day: r.forecast.first { $0.name == me }?.day, ahead: index, scheduled: false, total: r.order.count)
            } else {
                value = nil
            }
        }
        dutyTurnCache = (key, value)
        return value
    }

    /// 我最近和以后的遥测：按规则该休的日子排了岗位、或者工作日没写休息
    func myRestWarnings() -> [SchedulePatterns.Warning] {
        guard let me = myRosterName else { return [] }
        return SchedulePatterns.restWarnings(name: me, roster: roster, published: publishedDays, from: .today,
                                             matcher: matcher, calendar: .app)
    }

    /// 同步后：新出现的「该休却排了岗位」提醒一次（没写休息的只在首页显示，不推送）
    func notifyRestWarnings() async {
        guard !Self.isDemo else { return }
        let new = myRestWarnings().filter { $0.kind == .assigned && !settings.warnedRestKeys.contains($0.key) }
        guard !new.isEmpty else { return }
        settings.warnedRestKeys = Array((settings.warnedRestKeys + new.map(\.key)).suffix(100))
        await NotificationService.notifyNow(id: "rest-warning-\(new[0].key)", title: "⚠️ 排班可能和规则不一致",
                                            body: new.map(\.text).joined(separator: "\n") + "\n去网站上核对一下。")
    }

    /// 待休核对：按待休记录反推加减规则，列出对不上的人
    func restBalanceAudit() -> RestBalanceAudit.Result? {
        RestBalanceAudit.analyze(points: settings.restHistory.mapValues { $0.map(\.point) }, roster: roster,
                                 matcher: matcher, calendar: .app)
    }

    /// 电脑版周表上每天的待休天数（往前翻的几周）补进待休记录，用来说明数字是怎么变的。
    func mergeRestHistory(_ byDay: [String: [DayKey: Int]]) {
        let today = DayKey.today
        // 以后几周表上的数字还没发生，不记
        let past = byDay.mapValues { $0.filter { $0.key <= today } }.filter { !$0.value.isEmpty }
        // 每个人以前几周的数字都和现在一样：网站显示的是现在的数字，不当历史用
        guard !past.isEmpty, !RestBalanceHistory.looksLikeSnapshot(past) else { return }
        var s = settings
        for (name, days) in past {
            let old = (s.restHistory[name] ?? []).map(\.point)
            s.restHistory[name] = RestBalanceHistory.merge(old, days, live: false).map { RestPoint($0) }
        }
        settings = s
    }

    /// 人名后括号里的待休天数：这次读到的人以新数字为准。
    func updateRestBalance(_ new: [String: Int]) {
        guard !new.isEmpty else { return }
        var s = settings
        let today = DayKey.today
        for (name, value) in new {
            let old = (s.restHistory[name] ?? []).filter { $0.day <= today }.map(\.point)
            s.restHistory[name] = RestBalanceHistory.merge(old, [today: value], live: true).map { RestPoint($0) }
        }
        s.restBalance.merge(new) { _, n in n }
        s.restBalanceUpdated = Date()
        settings = s
        Task {
            await notifyRestIfNeeded()
            await reconcileMyRestBalance()
        }
    }

    /// 待休对账：我的待休这次变了，按反推的规律算一遍应该变多少，对不上就提醒一次
    func reconcileMyRestBalance() async {
        guard !Self.isDemo, let me = myRosterName, let audit = restBalanceAudit(),
              let points = settings.restHistory[me], points.count >= 2 else { return }
        let prev = points[points.count - 2], cur = points[points.count - 1]
        let key = "\(cur.day)|\(cur.value)"
        guard settings.restLedgerNotified != key else { return }
        let expected = RestBalanceAudit.expectedChange(roster[me] ?? [:], from: prev.day, to: cur.day, rule: audit.rule,
                                                       matcher: matcher, calendar: .app)
        let observed = cur.value - prev.value
        guard expected != observed else { return }
        settings.restLedgerNotified = key
        func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }
        await NotificationService.notifyNow(id: "rest-ledger", title: "待休对不上",
                                            body: "网站上你的待休从 \(prev.value) 变成 \(cur.value) 天（\(signed(observed))），按规律（\(audit.rule.text)）应该是 \(signed(expected))。去网站上核对一下。")
    }

    /// 语音转文字的常用词：同事名字、岗位、组别、各组工作内容里的星名和编号、值班常用词
    var speechVocabulary: [String] {
        var words: [String] = ["遥测", "调度", "值班", "交接班", "交班", "接班", "值班长", "组A", "组B", "组C", "组D", "组E",
                               "数传", "过境", "测控", "上行", "下行", "遥控", "轨道", "卫星", "故障", "应急", "备份", "休息", "调休", "请假", "出差"]
        words += settings.shiftTypes.map(\.name)
        words += roster.keys.sorted()
        // 各组工作内容里的编号（JXGF07A02）、「一号星」这类词
        let notes = groupNotes.values.joined(separator: " ")
        let patterns = [#"[A-Za-z]{2,}[A-Za-z0-9/]*\d[A-Za-z0-9/]*"#, #"[\x{4e00}-\x{9fa5}]{1,4}号星"#]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = notes as NSString
            words += re.matches(in: notes, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        }
        var seen = Set<String>()
        return words.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 没建档案时自动判断的角色
    func suggestedRole(_ name: String) -> PersonRole {
        PersonDirectory.suggest(name: name, history: roster[name] ?? [:], matcher: matcher)
    }

    /// 某人某天这条排班的来源
    func provenance(_ name: String, _ day: DayKey) -> Provenance? { rosterSources[name]?[day] }

    /// 下次后台同步最早什么时候：微信提醒前、网站常排班的时段前（取较早的）
    var nextBackgroundSync: Date? {
        let hot = PublishPattern.nextHot(after: Date(), times: settings.publishTimes, calendar: .app)
        return [nextWeChatReminder, hot].compactMap { $0 }.min()
    }

    /// 昨天值了遥测、现在是今天 8:30 到设定的补觉结束时间之间
    func isRestingAfterDuty(now: Date = Date()) -> Bool {
        let today = DayKey(date: now, calendar: .app)
        guard let raw = schedule[today.adding(days: -1)], WorkloadCounter.isDuty(matcher.displayName(raw)) else { return false }
        let start = today.date(calendar: .app, hour: 8, minute: 30)
        let end = today.date(calendar: .app, hour: settings.restFocusUntil.hour, minute: settings.restFocusUntil.minute)
        return now >= start && now < end
    }

    // MARK: - 组别任务清单

    func taskKey(_ day: DayKey, _ group: String) -> String { "\(day.description)|\(group)" }

    func isTaskDone(_ day: DayKey, _ group: String, _ item: String) -> Bool {
        settings.taskChecks[taskKey(day, group)]?.contains(item) ?? false
    }

    func toggleTask(_ day: DayKey, _ group: String, _ item: String) {
        var checks = settings.taskChecks
        let key = taskKey(day, group)
        var done = checks[key] ?? []
        if let i = done.firstIndex(of: item) { done.remove(at: i) } else { done.append(item) }
        checks[key] = done.isEmpty ? nil : done
        // 只留最近两周
        let cutoff = DayKey.today.adding(days: -14).description
        checks = checks.filter { $0.key.prefix(10) >= cutoff }
        settings.taskChecks = checks
        updateWidget()
    }

    // MARK: - 自动备份

    /// 在「文件」App 里选一个文件夹（建议 iCloud 云盘），以后每天自动存一份备份；删掉 App 也还在。
    func setBackupFolder(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            settings.backupFolderBookmark = try url.bookmarkData()
            settings.backupFolderName = url.lastPathComponent
            settings.lastAutoBackup = nil
            autoBackupIfNeeded(force: true)
        } catch {
            settings.autoBackupMessage = "没法记住这个文件夹：\(error.localizedDescription)"
        }
    }

    /// 每天最多一次，存「值班提醒备份-日期.json」，只留最近 8 份
    func autoBackupIfNeeded(force: Bool = false) {
        guard let bookmark = settings.backupFolderBookmark else { return }
        if !force, let last = settings.lastAutoBackup, Date().timeIntervalSince(last) < 20 * 3600 { return }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) else {
            settings.autoBackupMessage = "找不到备份文件夹了，请重新选一次"
            return
        }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            let file = folder.appendingPathComponent("值班提醒备份-\(DayKey.today.description).json")
            try backupData().write(to: file, options: .atomic)
            let fm = FileManager.default
            let old = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in old.filter({ $0.lastPathComponent.hasPrefix("值班提醒备份-") && $0.pathExtension == "json" })
                .sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(8) {
                try? fm.removeItem(at: url)
            }
            if stale { settings.backupFolderBookmark = try? folder.bookmarkData() }
            settings.lastAutoBackup = Date()
            settings.autoBackupMessage = "已备份到「\(settings.backupFolderName ?? folder.lastPathComponent)」"
        } catch {
            settings.autoBackupMessage = "自动备份失败：\(error.localizedDescription)"
        }
    }

    /// 两天里没有一次快捷指令同步：多半还没设自动化
    var automationLooksMissing: Bool {
        guard canSync else { return false }
        let since = Date().addingTimeInterval(-2 * 86_400)
        return !settings.syncLog.contains { $0.date > since && $0.source.hasPrefix("快捷指令") }
    }

    /// 我在网站上的名字（全员排班里认出是我的那个）
    var myRosterName: String? { roster.keys.first(where: isMe) ?? settings.restBalance.keys.first(where: isMe) }

    /// 我的待休攒到设定的天数时提醒一次，之后再涨才再提醒；休掉了就重新计
    func notifyRestIfNeeded() async {
        guard settings.restAlertThreshold > 0, let me = myRosterName, let rest = settings.restBalance[me] else { return }
        if rest < settings.restAlertThreshold {
            if settings.restAlertNotified != nil { settings.restAlertNotified = nil }
            return
        }
        guard rest > (settings.restAlertNotified ?? 0) else { return }
        settings.restAlertNotified = rest
        await NotificationService.notifyNow(id: "rest-balance", title: "🛌 你已经攒了 \(rest) 天待休",
                                            body: "网站上你名字后面的待休是 \(rest) 天，找个时间安排休息吧。")
    }

    /// 合并全员排班：这次读到的日子整天替换（换人、取消的都以新数据为准），
    /// 但不带休息列的读取不会冲掉之前读到的休息、请假（见 RosterExtractor.replacingDays）。
    /// source：「sync」同步、「desktop」电脑版周表。每条记下来源；不带休息列的读取方式不会冲掉以前读到的休息、请假。
    @discardableResult
    func mergeRoster(_ incoming: Roster, source: String = "sync") -> [RosterEdit] {
        guard !incoming.isEmpty else { return [] }
        // 一页里两个名字挨在一起（「张三李四」）、两半是别的页或以前读到过的人：拆开
        let new = RosterExtractor.splitJoinedNames(incoming, known: Set(roster.keys))
        // 这种读取方式带不带休息列：读到过休息、请假就记住
        var s = settings
        // 每次读的范围、方式可能不同（后台快速同步不翻页），所以按这次读到的有没有休息判断
        let carries = RosterMerger.hasLeave(new, matcher: matcher)
        if carries && !s.leaveSources.contains(source) { s.leaveSources.append(source) }
        let lastPublished = publishedDays.max()
        // 先在副本上算好，只赋值一次（每次赋值都会重算已排班的日子、刷新界面）
        let result = RosterMerger.merge(old: roster, oldSources: rosterSources, new: new, source: source, at: Date(),
                                        carriesLeave: carries, matcher: matcher)
        // 留一年多，全年统计用
        let cutoff = DayKey.today.adding(days: -400)
        // 以前没拆开存下的「张三李四」也一起拆开
        roster = RosterExtractor.splitJoinedNames(result.roster).mapValues { $0.filter { $0.key >= cutoff } }.filter { !$0.value.isEmpty }
        rosterSources = result.sources.mapValues { $0.filter { $0.key >= cutoff } }.filter { !$0.value.isEmpty }
        if !result.edits.isEmpty { rosterLog = Array((rosterLog + result.edits).suffix(3000)) }
        // 网站排出了新的一周：记下时间，学网站一般什么时候排班
        if let before = lastPublished, let after = publishedDays.max(), after > before.adding(days: 3) {
            s.publishTimes = Array((s.publishTimes + [Date()]).suffix(40))
        }
        if s != settings { settings = s }
        saveRoster()
        saveSourcesAndLog()
        // 已排班的日子变了，「未排班」提醒也要跟着变
        requestReschedule()
        return result.edits
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
        SwapExplainer.describe(change, before: before, after: roster, fresh: fresh.contains(change.day),
                               matcher: matcher, isMe: isMe)
    }

    /// 打开 App 时，距离上次同步超过 3 分钟就自动同步一次。
    func syncIfStale() async {
        guard canSync else { return }
        if let last = settings.lastSync, Date().timeIntervalSince(last) < 3 * 60 { return }
        await sync(full: true)
    }

    /// 系统在后台唤醒 App 时调用（时间由 iOS 决定，不保证准时）。
    func backgroundRefresh() async {
        BackgroundRefresh.schedule(notBefore: nextBackgroundSync)   // 先约好下一次，万一这次被系统打断
        settings.lastBackgroundWake = Date()
        await withTaskCancellationHandler {
            // 先发到点的微信（只需要几秒），再同步；同步用完后台时间也不耽误微信
            await sendDueWeChatReminders()
            if canSync {
                await sync(full: false, source: "后台刷新")
                // 同步前还没有数据、没发出去的，同步后再试一次
                await sendDueWeChatReminders()
            }
            await rescheduleNotifications()
            autoBackupIfNeeded()
        } onCancel: {
            // 系统收回后台时间：让正在进行的同步马上停下（等待中的网页会抛出取消），不被系统强行杀掉
            Task { @MainActor in AppStore.shared.cancelRunningSync() }
        }
        BackgroundRefresh.schedule(notBefore: nextBackgroundSync)
    }

    func cancelRunningSync() { syncTask?.cancel() }

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
    /// 排班变动的微信通知：发成功才清掉，没发出去（网络、后台时间到了）下次 App 运行时补发
    private var isSendingWeChatChange = false

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
    private func recordTeamChanges(before: Roster, days: Set<DayKey>) async {
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
            await NotificationService.notifyNow(id: "favorites-\(UUID().uuidString)", title: "⭐ 关注的同事排班有变", body: body)
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
        await NotificationService.notifyNow(id: "roster-edits-\(UUID().uuidString)", title: title, body: body)
        if settings.weChatEnabled && settings.weChatChanges {
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

    func sendDueWeChatReminders() async {
        await sendPendingWeChatChange()
        await sendMonthlyReportIfDue()
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

    // MARK: - 收藏的同事

    /// 设置里另加的「只按排班算」的人（调度自动算在内）
    var rotationMembers: Set<String>? {
        settings.scheduleOnlyMembers.isEmpty ? nil : Set(settings.scheduleOnlyMembers)
    }

    /// asOf：按哪一天往前三个月判断是不是调度的人（统计哪个月就传那个月最后一天，和列表一致）
    func isRotating(_ name: String, asOf: DayKey? = nil) -> Bool {
        WorkloadCounter.isRotating(name: name, history: roster[name] ?? [:], members: rotationMembers, matcher: matcher,
                                   asOf: asOf)
    }

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
            } else if isCovered(day) {
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
        guard canEdit else { throw NSError(domain: "role", code: 1, userInfo: [NSLocalizedDescriptionKey: "只有管理员能从备份恢复"]) }
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
        // 旧格式的全员排班可能读错过，清掉，同步时重新读
        if newSettings.rosterVersion < Self.rosterVersion { roster = [:]; saveRoster() }
        newSettings.rosterVersion = Self.rosterVersion
        // 备份时的同步状态已经过时：清掉，马上重新同步（也会重新尝试登录）
        newSettings.lastSync = nil
        newSettings.lastSyncMessage = nil
        newSettings.loginExpiredNotified = false
        newSettings.syncStaleNotified = false
        newSettings.nextSyncIsBaseline = true
        newSettings.leaveSources = []
        rosterSources = [:]
        rosterLog = []
        saveSourcesAndLog()
        // 重装后日历权限要重新给，没给就先关掉
        if newSettings.calendarSync && !CalendarSync.authorized { newSettings.calendarSync = false }
        // 自动备份的文件夹是这台手机上选的，不用备份里的
        // 工作留痕的面容 ID 锁跟着这台手机上的文件放在哪，不用备份里的（否则文件夹对不上，记录全显示丢失）
        newSettings.workLogLock = settings.workLogLock
        newSettings.backupFolderBookmark = settings.backupFolderBookmark
        newSettings.backupFolderName = settings.backupFolderName
        newSettings.lastAutoBackup = settings.lastAutoBackup
        newSettings.autoBackupMessage = settings.autoBackupMessage
        settings = newSettings
        scheduleChanged()
        Task { [weak self] in await self?.sync(userInitiated: true) }
        return restored.count
    }

    // MARK: - 工作量统计

    struct Workload {
        var days: [DayKey]
        var people: [PersonWorkload]
        var text: String
    }

    /// 某月每个人的工作量（来自全员排班），按上班天数从多到少。
    /// month 为 nil 时统计全年（App 里留着的全员排班，最多一年多）
    /// 统计结果缓存：全员排班、我的排班、设置变了就清掉（全年统计不用每次重算）
    private var workloadCache: [String: Workload] = [:]

    func invalidateWorkloadCache() { workloadCache = [:] }

    /// 统计用的数据（全员排班、我的排班、设置）每变一次加一，页面用它判断要不要重算
    @Published private(set) var dataRevision = 0

    func workload(year: Int, month: Int?) -> Workload {
        let key = "\(year)-\(month ?? 0)-\(DayKey.today)"
        if let cached = workloadCache[key] { return cached }
        let value = computeWorkload(year: year, month: month)
        workloadCache[key] = value
        return value
    }

    private func computeWorkload(year: Int, month: Int?) -> Workload {
        // 只统计到今天：网站上提前排好的以后的日子还没上，不算
        let today = DayKey.today
        let days = publishedDays.filter { $0.year == year && (month == nil || $0.month == month) && $0 <= today }.sorted()
        let zh = Locale(identifier: "zh_CN")
        let people = WorkloadCounter.count(roster: roster, days: days, matcher: matcher, members: rotationMembers,
                                           calendar: .app).sorted { a, b in
            a.workDays != b.workDays ? a.workDays > b.workDays : a.name.compare(b.name, locale: zh) == .orderedAscending
        }
        var text = "\(year)年" + (month.map { "\($0)月" } ?? "全年") + "工作量统计"
        if let first = days.first, let last = days.last {
            text += "（\(first.dateText) – \(last.dateText)，共 \(days.count) 天；工作量 = 值班（遥测）+ 日常（各组、调度等岗位；不轮组别的人没排岗位、没写休息的工作日也算）+ 出差；休息、调休、请假、值班交接前一律不算；上班 = 工作量 + 轮组别的人没排岗位、没写休息的工作日）"
        }
        for p in people {
            text += "\n\(p.name)：工作量 \(p.workDays) 天（值班 \(p.dutyDays)\(p.dutyRestDays > 0 ? "，值班调休 \(p.dutyRestDays)" : "")，日常 \(p.regularDays)，出差 \(p.tripDays)），上班 \(p.presentDays) 天"
                + (p.attendanceDays > 0 ? "（其中没排岗位 \(p.attendanceDays) 天，不算工作量）" : "")
                + "，休息 \(p.offDays) 天，节假日 \(p.holidayDays) 天" + (p.unassignedDays > 0 ? "，没排班 \(p.unassignedDays) 天" : "")
                + (settings.restBalance[p.name].map { "，待休 \($0) 天" } ?? "")
                + (p.holidayWorkedDays > 0 ? "，节假日上班 \(p.holidayWorkedDays) 天" : "") + "；"
                + Self.sortedPosts(p).map { "\($0.post)×\($0.count)" }.joined(separator: " ")
        }
        return Workload(days: days, people: people, text: text)
    }

    /// 把一段 CSV 文字存成临时文件（带 BOM，Excel 才认得出中文）
    func csvFile(named name: String, text: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }

    /// 导出成表格文件（CSV，Excel / WPS / Numbers 能直接打开），返回临时文件地址
    func workloadCSVFile(year: Int, month: Int?, report: Workload? = nil) -> URL? {
        let report = report ?? workload(year: year, month: month)
        let name = "工作量\(year)年" + (month.map { "\($0)月" } ?? "全年") + ".csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        // 带 BOM，Excel 才认得出中文
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(WorkloadCSV.make(report.people, restBalance: settings.restBalance).utf8)
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }

    static func sortedPosts(_ p: PersonWorkload) -> [(post: String, count: Int)] {
        p.posts.map { (post: $0.key, count: $0.value) }.sorted { ($0.count, $1.post) > ($1.count, $0.post) }
    }
}
