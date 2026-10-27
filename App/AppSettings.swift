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

    /// 当前用的主题色（App 启动、改设置时写进来，设计系统从这里取；小组件、后台也会读，加锁）
    static var current: AccentTheme {
        get { _current.wrappedValue }
        set { _current.wrappedValue = newValue }
    }
    private static let _current = Locked<AccentTheme>(wrappedValue: .system)

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

/// 所有设置和数据都存在 state.json 的一层里（键名就是字段名，从来没变过，旧存档照样能读）。
/// 字段按用途分成七类（下面的 MARK）；新加字段时放进对应的一类，并看一下：
/// - 管理员规则：加进 keepingAdminFields（非管理员改不了）
/// - 同步得到的数据：影响统计、推算的加进 sameData（变了才重算）
/// - 同步状态、去重标记、不影响提醒的开关：加进 onlyBookkeepingChanged（变了不用重排提醒）
/// - 设备本地：从备份恢复时保留这台手机上的值（restore）
struct AppSettings: Codable, Equatable {
    // MARK: 用户偏好（自己在设置里改的）

    /// 我的名字（网站上可能有几种写法）
    var aliases: [String] = []
    /// 每天早上提醒今天、晚上提醒明天
    var morningEnabled = true
    var morning = ClockTime(hour: 7, minute: 30)
    var eveningEnabled = true
    var evening = ClockTime(hour: 20, minute: 30)
    var notifyWhenEmpty = false
    /// 网站排了班、但没给我排的日子也提醒（显示「未排班」）
    var remindUnassigned = true
    /// 到点时用语音读出「今天，组D」（作为通知铃声）
    var voiceEnabled = false
    /// 播报用的声音（空 = 自动选手机上最好的中文声音）
    var voiceIdentifier = ""
    /// 播报语速（0.3–0.6，系统默认 0.5）
    var voiceRate: Float = 0.47
    var appearance: Appearance = .system
    /// 今天页卡片的顺序、藏起来的卡片（TodayCard 的名字；空 = 默认顺序）
    var todayCardOrder: [String] = []
    var hiddenTodayCards: [String] = []
    var accentTheme: AccentTheme = .system
    /// 主屏幕图标显示今天的组（A–E / 休），打开 App 时切换
    var dynamicIcon = true
    /// 把排班写进 iPhone「日历」App
    var calendarSync = false
    /// 值遥测时在锁屏显示倒计时
    var liveActivity: Bool = true
    /// 值班网站
    var sourceURL = ""
    var sourceUsername = ""
    /// 用 App 内置浏览器同步（沿用网页登录状态）；关掉则直接下载文件
    var syncViaWeb = true
    /// 电脑版「值班查看」的网址（空 = 用同步网址的 #/duty）
    var desktopNotesURL = ""
    /// 同步发现排班变动时推送通知
    var notifyChanges = true
    /// 关注的同事排班变了也通知
    var notifyFavorites: Bool = true
    /// 全员排班有变动（今天及以后，谁的都算）也提醒
    var notifyAllChanges: Bool = true
    /// 每周日晚上预告下周安排（iPhone 通知 + 微信）
    var weeklyPreview = true
    /// 每周一给自己的小结：上周上了几天、遥测几次、待休、这周的班、下次遥测
    var personalWeekly: Bool = true
    /// 网站还没排、按顺序推算快轮到我时提前说一声
    var dutyHeadsUp: Bool = true
    /// 我的待休攒到几天提醒一次（0 不提醒）
    var restAlertThreshold: Int = 5
    /// 微信推送（PushPlus）
    var weChatEnabled = false
    /// 每天的提醒也发一份到微信（App 有机会运行时补发，可能比准点晚）
    var weChatDaily = true
    /// 排班变动也发到微信（关掉后只在 iPhone 上通知）
    var weChatChanges = true
    /// 同事的排班变动、网站公告也推到微信（会把同事姓名发给 PushPlus），默认不推
    var weChatTeam = false
    /// 每月 1 号把上个月的工作量发到微信
    var monthlyReport: Bool = true
    /// 每周一推送上周的管理摘要（只有管理者、管理员会发）
    var weeklyDigest: Bool = true
    /// 周一早上提醒我负责的周会问题（负责人里有「我的名字」的）
    var meetingMineReminder = true
    /// 周会文档每周更新后，把各组还挂着的问题发到微信
    var meetingWeChat = false
    /// 遥测下班后补觉到几点（给快捷指令的勿扰自动化用）
    var restFocusUntil = ClockTime(hour: 14, minute: 0)
    /// 遥测接班时间（上一班到这时下班）；接班前多少分钟提醒，0 不提醒
    var dutyStart = ClockTime(hour: 8, minute: 30)
    var dutyLeadMinutes = 0
    /// 值遥测的提醒标成「时效性通知」：勿扰、睡眠专注时也弹出
    var dutyTimeSensitive = true
    /// 值遥测那天早上响闹钟（iOS 26 起；和「时钟」的闹钟一样，静音也会响）
    var dutyAlarm = false
    var dutyAlarmTime = ClockTime(hour: 7, minute: 0)
    /// 工作留痕：录音自动转文字、只在手机上识别（不联网）、打开要面容 ID（面容 ID 锁跟着这台手机，见「设备本地」）
    var workLogAutoTranscribe = true
    var speechOnDeviceOnly = true
    var workLogLock = false
    /// 第一次打开的设置向导走完了没有
    var onboardingDone = false

    // MARK: 自己记的（个人数据）

    /// 收藏的同事，首页显示他们今天、明天在哪个组
    var favorites: [String] = []
    /// 自己给某天写的备注（yyyy-MM-dd → 文字），日历上显示小点，那天的提醒里带上
    var dayMemos: [String: String] = [:]
    /// 换班账本
    var swapRecords: [SwapRecord] = []
    /// 组别任务清单勾选：「yyyy-MM-dd|组A」→ 做完的事项
    var taskChecks: [String: [String]] = [:]
    // 清单历史、「排班有更新」、同步记录存在 records.json（RecordsState）；周会问题存在 meeting.json（MeetingState）

    // MARK: 管理员规则（只有管理员能改，见 keepingAdminFields）

    /// 班次类型（名字、图标、颜色、关键词）
    var shiftTypes: [ShiftType] = ShiftType.defaults
    /// 各组工作内容：自己填写的（电脑版网页上没读到的组才用）
    var manualGroupNotes: [String: String] = [:]
    /// 没排班不算上班的人（除调度外另加的）：工作日网站上没排岗位不算工作量
    var scheduleOnlyMembers: [String] = []
    /// 自己录入的节假日（yyyy-MM-dd）：放假的日子、调休上班的周末
    var customHolidayOff: [String] = []
    var customHolidayWork: [String] = []
    /// 周六是正常工作日（法定节假日除外）：没排岗位、没写休息的周六算上班、算工作量
    var saturdayIsWorkday = true
    /// 人员档案（管理员确认过的角色、来走日期）
    var profiles: [String: PersonProfile] = [:]
    /// 工作量规则开关
    var workloadRules = WorkloadRules()
    /// 规则改动历史（某天以前按当时的规则算）
    var ruleHistory: [RuleVersion] = []
    /// 工作量手动纠正：人名 → yyyy-MM-dd → 类别（或「不算」）
    var workloadOverrides: [String: [String: String]] = [:]

    // MARK: 同步得到的数据（网站上读来的，统计、推算用）

    /// 各组工作内容：电脑版「值班查看」读到的（优先级最高）、其它页面顺带读到的
    var desktopGroupNotes: [String: String] = [:]
    var autoGroupNotes: [String: String] = [:]
    /// 全员排班的读取规则版本；规则改了以后清掉旧数据重新读
    var rosterVersion = 0
    /// 每个人还有几天待休（网页上人名后括号里的数字）
    var restBalance: [String: Int] = [:]
    var restBalanceUpdated: Date?
    /// 每个人待休天数的变化（只在数字变了时记一笔）
    var restHistory: [String: [RestPoint]] = [:]
    /// 网站人员表：谁参加值班、哪几天能值遥测、待休天数（排班规律用）
    var sitePeople: [String: SiteAPI.Person] = [:]
    /// 网站公告里写的排班规则
    var siteNotices: [String] = []
    /// 公告最近一次变化的时间、新出现的几条（今天页显示 7 天）
    var siteNoticesChanged: Date?
    var siteNoticesNew: [String] = []
    /// 网站标了「固定」（手动指定）遥测的日子
    var fixedTelemetryDays: [String] = []
    /// 网站标的「该休没休」（全员，近两个月）：「日期|名字|栏目」
    var siteNoRestFlags: [String] = []
    /// 各组负责的星（网站组表）
    var groupSatellites: [String: String] = [:]
    /// 自动下载的法定节假日安排（公开数据），和上次下载时间
    var downloadedHolidayOff: [String] = []
    var downloadedHolidayWork: [String] = []
    var lastHolidayFetch: Date?
    /// 读到过休息、请假的读取方式（说明带休息列）
    var leaveSources: [String] = []
    /// 网站排出新一周排班的时间（学网站一般什么时候排班）
    var publishTimes: [Date] = []
    /// 全员换班记录
    var teamChanges: [TeamChange] = []
    /// 排班预演：网站还没排的日子猜的遥测（日期 → 名字）；网站排出来后拿来对，结果记在 previewResults
    var previewGuesses: [String: String] = [:]
    var previewResults: [PreviewResult] = []

    // MARK: 同步状态与记录

    var lastSync: Date?
    var lastSyncMessage: String?
    /// 最近一次成功同步的结果（失败时 lastSyncMessage 会被覆盖，这里留着方便排查）
    var lastSuccessMessage: String?
    /// 上次同步的结果（不再从提示文字里猜）、上次尝试的时间、连续失败几次（自动同步按这个退避）
    var syncState: SyncState?
    var lastSyncAttempt: Date?
    var syncFailureCount = 0
    /// 上次系统在后台唤醒 App 的时间
    var lastBackgroundWake: Date?
    /// 认出的网站数据接口（如 "GET http://…/api/duty"），同步时优先用它取多周数据
    var apiSignature: String?
    /// 改了「我的名字」：下一次同步当作重新开始，不提示变动、不做异常检查
    var nextSyncIsBaseline = false
    /// 网站改版自检：每种读取方式最近几次正常的结果、现在的提醒、哪天推送过
    var syncHealth: [String: [SyncHealth.Metrics]] = [:]
    var syncHealthWarning: String?
    var syncHealthWarnedDay: DayKey?
    /// 上次从电脑版页面读各组工作内容的时间（一天读一次）、读的结果
    var lastDesktopNotesFetch: Date?
    var lastDesktopNotesAttempt: Date?
    var desktopNotesMessage: String?
    var desktopRosterMessage: String?
    /// 上次微信推送的结果
    var weChatMessage: String?

    // MARK: 通知去重（已经发过的，不重复发）

    /// 已经提醒过「登录过期」「很久没同步成功」，同步成功后恢复
    var loginExpiredNotified = false
    var syncStaleNotified = false
    /// 每天的微信提醒、周日的下周预告哪天发过
    var weChatMorningSent: DayKey?
    var weChatEveningSent: DayKey?
    var weChatWeekSent: DayKey?
    /// 发过的排班变动微信；还没发出去的那条（下次补发）
    var lastWeChatChangeDigest: String?
    var pendingWeChatChange: ChangeLogEntry?
    /// 月报、管理摘要、个人小结上次发的是哪个月、哪一周
    var lastMonthlyReport: String?
    var lastWeeklyDigest: String?
    var lastPersonalWeekly: String?
    /// 上次提醒时的待休天数（再涨了才再提醒）
    var restAlertNotified: Int?
    /// 待休对账：已经提醒过的那次变化
    var restLedgerNotified: String?
    /// 已经提醒过的「值完遥测该休却排了岗位」
    var warnedRestKeys: [String] = []
    /// 已经提醒过的「该休没休」（日期|栏目）
    var noRestNotified: [String] = []
    /// 上次说「快轮到你值遥测」是什么时候（几天内不重复）
    var dutyHeadsUpSent: Date?

    // MARK: 设备本地（从备份恢复时保留这台手机上的，见 restore）

    /// 自动备份到的文件夹（「文件」App 里选的，存成书签）、上次备份的时间和结果
    var backupFolderBookmark: Data?
    var backupFolderName: String?
    var lastAutoBackup: Date?
    var autoBackupMessage: String?

    init() {}

    // 逐项读取，新版本增加字段时旧存档也能正常打开
    /// 从存档读：每一项单独容错（见 TolerantCoding，新加的项只要有默认值），再做几项老版本的迁移。
    /// stored 是存档里设置那一段（JSONSerialization 读出来的字典）
    static func load(from stored: Any?, encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) -> AppSettings {
        var s = TolerantCoding.decode(AppSettings.self, from: stored, defaults: AppSettings(), encoder: encoder, decoder: decoder)
        let keys = (stored as? [String: Any]).map { Set($0.keys) } ?? []
        // 老用户（已经填过网址）不再弹向导
        if !keys.contains("onboardingDone") { s.onboardingDone = !s.sourceURL.isEmpty }
        // 1.1 以前存的班次类型：「值班交接前」被认成值班（关键字「值」），给休息加上「交接」「交班」
        if let i = s.shiftTypes.firstIndex(where: { $0.id == "off" }), !s.shiftTypes[i].keywords.contains("交接") {
            s.shiftTypes[i].keywords += ["交接", "交班"]
        }
        // 1.1 以前只存了提示文字
        if s.syncState == nil, let m = s.lastSyncMessage {
            s.syncState = m.hasPrefix("同步成功") ? .ok : (m.hasPrefix("同步失败") ? .failed : (m.hasPrefix("同步结果异常") ? .anomaly : nil))
        }
        return s
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

/// 备份文件：设置、排班、全员排班、周会、记录。密码、PushPlus token、写回脚本令牌存在钥匙串里，不在备份中。
/// 只用来写；读备份时一段一段容错地读（AppStore.restore）
struct BackupFile: Encodable {
    var version = 2
    var created = Date()
    var settings: AppSettings
    var schedule: [String: String]
    var covered: [String]
    var roster: [String: [String: String]]
    var meeting: MeetingState?
    var records: RecordsState?
}

/// 上次同步的结果
enum SyncState: String, Codable {
    case ok, failed, needsLogin, anomaly
    var isFailure: Bool { self == .failed || self == .needsLogin }
}

extension AppSettings {
    /// 只有管理员能改的设置（统计口径、手动纠正、节假日、各组内容、班次类型、人员档案、规则历史）换回 o 的
    func keepingAdminFields(of o: AppSettings) -> AppSettings {
        var a = self
        a.workloadRules = o.workloadRules
        a.workloadOverrides = o.workloadOverrides
        a.customHolidayOff = o.customHolidayOff
        a.customHolidayWork = o.customHolidayWork
        a.saturdayIsWorkday = o.saturdayIsWorkday
        a.manualGroupNotes = o.manualGroupNotes
        a.scheduleOnlyMembers = o.scheduleOnlyMembers
        a.shiftTypes = o.shiftTypes
        a.profiles = o.profiles
        a.ruleHistory = o.ruleHistory
        return a
    }

    /// 和 o 比，只有记账类的字段变了（同步记录、已发标记、提示文字、不影响手机提醒的开关）
    func onlyBookkeepingChanged(from o: AppSettings) -> Bool {
        var a = self
        a.lastBackgroundWake = o.lastBackgroundWake
        a.weChatMessage = o.weChatMessage
        a.weChatMorningSent = o.weChatMorningSent
        a.weChatEveningSent = o.weChatEveningSent
        a.weChatWeekSent = o.weChatWeekSent
        a.lastWeChatChangeDigest = o.lastWeChatChangeDigest
        a.pendingWeChatChange = o.pendingWeChatChange
        a.lastDesktopNotesAttempt = o.lastDesktopNotesAttempt
        a.lastDesktopNotesFetch = o.lastDesktopNotesFetch
        a.desktopNotesMessage = o.desktopNotesMessage
        a.desktopRosterMessage = o.desktopRosterMessage
        a.lastSyncMessage = o.lastSyncMessage
        a.lastSuccessMessage = o.lastSuccessMessage
        a.syncHealth = o.syncHealth
        a.syncHealthWarning = o.syncHealthWarning
        a.syncHealthWarnedDay = o.syncHealthWarnedDay
        a.apiSignature = o.apiSignature
        a.teamChanges = o.teamChanges
        a.warnedRestKeys = o.warnedRestKeys
        a.noRestNotified = o.noRestNotified
        a.restAlertNotified = o.restAlertNotified
        a.restLedgerNotified = o.restLedgerNotified
        a.loginExpiredNotified = o.loginExpiredNotified
        a.syncStaleNotified = o.syncStaleNotified
        a.dutyHeadsUpSent = o.dutyHeadsUpSent
        a.lastPersonalWeekly = o.lastPersonalWeekly
        a.lastWeeklyDigest = o.lastWeeklyDigest
        a.lastMonthlyReport = o.lastMonthlyReport
        a.previewGuesses = o.previewGuesses
        a.previewResults = o.previewResults
        a.siteNotices = o.siteNotices
        a.siteNoticesChanged = o.siteNoticesChanged
        a.siteNoticesNew = o.siteNoticesNew
        a.lastHolidayFetch = o.lastHolidayFetch
        a.autoBackupMessage = o.autoBackupMessage
        a.lastAutoBackup = o.lastAutoBackup
        a.publishTimes = o.publishTimes
        a.nextSyncIsBaseline = o.nextSyncIsBaseline
        a.swapRecords = o.swapRecords
        a.favorites = o.favorites
        a.restHistory = o.restHistory
        a.restBalanceUpdated = o.restBalanceUpdated
        a.siteNoRestFlags = o.siteNoRestFlags
        a.leaveSources = o.leaveSources
        a.backupFolderBookmark = o.backupFolderBookmark
        a.backupFolderName = o.backupFolderName
        a.desktopNotesURL = o.desktopNotesURL
        a.workLogAutoTranscribe = o.workLogAutoTranscribe
        a.speechOnDeviceOnly = o.speechOnDeviceOnly
        a.workLogLock = o.workLogLock
        a.restAlertThreshold = o.restAlertThreshold
        a.monthlyReport = o.monthlyReport
        a.weeklyDigest = o.weeklyDigest
        a.personalWeekly = o.personalWeekly
        a.notifyChanges = o.notifyChanges
        a.notifyFavorites = o.notifyFavorites
        a.notifyAllChanges = o.notifyAllChanges
        a.weChatEnabled = o.weChatEnabled
        a.weChatDaily = o.weChatDaily
        a.weChatChanges = o.weChatChanges
        a.weChatTeam = o.weChatTeam
        a.meetingWeChat = o.meetingWeChat
        a.todayCardOrder = o.todayCardOrder
        a.hiddenTodayCards = o.hiddenTodayCards
        a.dutyHeadsUp = o.dutyHeadsUp
        a.syncState = o.syncState
        a.lastSyncAttempt = o.lastSyncAttempt
        a.syncFailureCount = o.syncFailureCount
        // 勾清单：小组件、实时活动由勾选的地方自己刷新，提醒不用重排
        a.taskChecks = o.taskChecks
        return a == o
    }

    /// 统计、推算用到的设置是不是一样（这些变了，工作量、遥测推算、各页统计才要重算）
    func sameData(as o: AppSettings) -> Bool {
        aliases == o.aliases && favorites == o.favorites && scheduleOnlyMembers == o.scheduleOnlyMembers
            && swapRecords == o.swapRecords && customHolidayOff == o.customHolidayOff && customHolidayWork == o.customHolidayWork
            && saturdayIsWorkday == o.saturdayIsWorkday && downloadedHolidayOff == o.downloadedHolidayOff && downloadedHolidayWork == o.downloadedHolidayWork
            && restHistory == o.restHistory && restBalance == o.restBalance && profiles == o.profiles
            && ruleHistory == o.ruleHistory && leaveSources == o.leaveSources && workloadRules == o.workloadRules
            && workloadOverrides == o.workloadOverrides && teamChanges == o.teamChanges && sitePeople == o.sitePeople
            && fixedTelemetryDays == o.fixedTelemetryDays && shiftTypes == o.shiftTypes && siteNoRestFlags == o.siteNoRestFlags
            && groupSatellites == o.groupSatellites && publishTimes == o.publishTimes
            && manualGroupNotes == o.manualGroupNotes && desktopGroupNotes == o.desktopGroupNotes && autoGroupNotes == o.autoGroupNotes
    }
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
    /// 只建一次（时区跟着系统自动变）：日期计算一次渲染要用成千上万次
    static let app: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .autoupdatingCurrent
        c.locale = Locale(identifier: "zh_CN")
        return c
    }()
}

extension DayKey: Identifiable {
    public var id: String { description }
    static var today: DayKey { DayKey(date: Date(), calendar: .app) }
    func adding(days: Int) -> DayKey { adding(days: days, calendar: .app) }
    var dateText: String { NotificationPlanner.dateText(self, calendar: .app) }
}

/// 排班预演猜得对不对（网站排出来以后记下）
struct PreviewResult: Codable, Equatable {
    var day: String
    var guess: String
    var actual: String
    var hit: Bool
}
