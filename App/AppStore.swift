import SwiftUI

/// state.json：设置、我的排班。只用来写；读的时候一段一段容错地读（AppStore.init）
private struct PersistedState: Encodable {
    var settings: AppSettings
    var schedule: [String: String]
    /// 已经取到过排班结果的日子（包括没给我排班的日子）
    var covered: [String]?
}

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            // 只有影响统计、推算的设置变了才清缓存：勾清单、同步记录、提醒开关这些不用重算
            if !settings.sameData(as: oldValue) {
                workloadCache = [:]
                dataRevision &+= 1
            }
            // 不是管理员：统计口径、班次类型这些改不了（同步自动更新的不受影响）。
            // 界面上这些地方本来就是灰的；万一从别处改到了，换回原样并明说，不悄悄跳回去
            if !canEdit {
                let fixed = settings.keepingAdminFields(of: oldValue)
                if fixed != settings {
                    settings = fixed
                    ToastCenter.shared.show(role == .manager ? "管理者只能查看，这项没有改" : "这项只有管理员能改，已恢复原样",
                                            style: .error)
                }
                guard settings != oldValue else { return }
            }
            if settings.aliases != oldValue.aliases { settings.nextSyncIsBaseline = true }
            if settings.shiftTypes != oldValue.shiftTypes {
                matcher = ShiftMatcher(types: settings.shiftTypes)
                publishedDays = Self.published(in: roster, matcher: matcher)
            }
            if settings.customHolidayOff != oldValue.customHolidayOff || settings.customHolidayWork != oldValue.customHolidayWork
                || settings.saturdayIsWorkday != oldValue.saturdayIsWorkday
                || settings.downloadedHolidayOff != oldValue.downloadedHolidayOff
                || settings.downloadedHolidayWork != oldValue.downloadedHolidayWork
                || settings.workloadRules != oldValue.workloadRules || settings.workloadOverrides != oldValue.workloadOverrides
                || settings.accentTheme != oldValue.accentTheme
                || settings.voiceIdentifier != oldValue.voiceIdentifier || settings.voiceRate != oldValue.voiceRate
                || settings.profiles != oldValue.profiles || settings.ruleHistory != oldValue.ruleHistory {
                applyCustomHolidays()
            }
            save()
            // 只是记账（同步记录、已发标记、提示文字）：不用重排提醒、刷新小组件（小组件每天刷新次数有限）
            if !settings.onlyBookkeepingChanged(from: oldValue) { requestReschedule() }
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
                let posts = matcher.posts(raw).map(matcher.displayName)
                if posts.contains(where: { WorkloadBalance.isGroup($0) || WorkloadCounter.isDuty($0) }) { result.insert(day) }
            }
        }
        return result
    }
    @Published private(set) var isSyncing = false
    /// 上次读电脑版页面时看到的文字（只在内存里，排查用）
    @Published var desktopPageText: String?
    /// 上次读周会文档读到的文字（没认出各组时给人看读到了什么）
    @Published var meetingPageText: String?

    /// 周会问题跟进（单独存在 meeting.json）
    @Published var meeting = MeetingState() {
        didSet {
            guard meeting != oldValue else { return }
            saveSide(meeting, to: Self.meetingURL, blocked: meetingBlocked)
            if meeting.issues != oldValue.issues { Task { await scheduleMeetingReminder() } }
        }
    }
    /// 同步记录、「排班有更新」、清单历史（单独存在 records.json）
    @Published var records = RecordsState() {
        didSet { if records != oldValue { saveSide(records, to: Self.recordsURL, blocked: recordsBlocked) } }
    }
    /// 这两份文件在、却读不出来（手机还没解锁过）：这次不写，免得用空的盖掉
    private var meetingBlocked = false
    private var recordsBlocked = false

    private static let meetingURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("meeting.json")
    }()
    private static let recordsURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("records.json")
    }()

    private func saveSide<T: Encodable & Sendable>(_ value: T, to url: URL, blocked: Bool) {
        if Self.isDemo || persistenceBlocked || blocked { return }
        StateWriter.shared.write(to: url) { try? JSONEncoder().encode(value) }
    }

    /// 读单独存的一份（周会、记录）。还没有这个文件、旧的设置存档里有这些字段时，从旧设置搬过来，马上写成文件
    /// （写进去之前设置存档里的旧字段还在，写不进去就这次都不存盘，旧字段不会丢）。
    /// 返回：读到的值、文件在却读不出来（这次不写）
    private static func loadSide<T: Codable>(_ type: T.Type, url: URL, legacySettings: Any?, names: [String: String],
                                             defaults: T, migrationFailed: inout Bool) -> (T, blocked: Bool) {
        let exists = FileManager.default.fileExists(atPath: url.path)
        if exists {
            guard let data = try? Data(contentsOf: url) else { return (defaults, true) }
            return (TolerantCoding.decode(type, data: data, defaults: defaults), false)
        }
        guard let legacy = LegacySettings.extract(names, from: legacySettings) else { return (defaults, false) }
        let value = TolerantCoding.decode(type, from: legacy, defaults: defaults)
        // 演示模式下也写：搬的是手机上真实的旧数据（不写的话，退出演示后存设置会把旧字段丢掉）
        do {
            try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            migrationFailed = true
        }
        return (value, false)
    }

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
        let log = (try? JSONDecoder().decode([RosterEdit].self, from: data)) ?? []
        // 以前把只是写法不同的（「值班交班前」→「值班交接前」）也记成了变动：读出来时去掉
        let matcher = ShiftMatcher(types: ShiftType.defaults)
        return log.filter { !RosterMerger.sameMeaning($0.old, $0.new, matcher: matcher) }
    }

    private func saveSourcesAndLog() {
        if Self.isDemo || persistenceBlocked { return }
        let sources = rosterSources, log = rosterLog
        // 几百天 × 几十人：编码、写盘都放到后台
        StateWriter.shared.write(to: Self.sourcesURL) {
            try? JSONEncoder().encode(sources.mapValues { days in
                Dictionary(uniqueKeysWithValues: days.map { ($0.key.description, $0.value) })
            })
        }
        StateWriter.shared.write(to: Self.logURL) { try? JSONEncoder().encode(log) }
    }

    private static func loadRoster() -> Roster {
        guard let data = try? Data(contentsOf: rosterURL),
              let raw = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return raw.mapValues { days in
            Dictionary(days.compactMap { k, v in DayKey(string: k).map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
        }
    }

    private func saveRoster() {
        if Self.isDemo || persistenceBlocked { return }
        let roster = roster
        StateWriter.shared.write(to: Self.rosterURL) {
            try? JSONEncoder().encode(roster.mapValues { days in
                Dictionary(uniqueKeysWithValues: days.map { ($0.key.description, $0.value) })
            })
        }
    }

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }()

    private init() {
        let data = try? Data(contentsOf: Self.fileURL)
        let state = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        // 文件在、却读不出来（手机重启后还没解锁过，文件受保护）：这次不存盘，免得用空数据把真数据盖掉
        persistenceBlocked = data == nil && FileManager.default.fileExists(atPath: Self.fileURL.path)
        // 读出来了但解析不了：带时间另存一份（不覆盖以前存的），别让下次保存把它覆盖掉
        if let data, state == nil {
            let stamp = Int(Date().timeIntervalSince1970)
            try? data.write(to: Self.fileURL.deletingLastPathComponent().appendingPathComponent("state.bad-\(stamp).json"))
        }
        // 设置一项一项容错地读：某一项坏了只有那一项用默认值
        settings = state.map { AppSettings.load(from: $0["settings"]) } ?? AppSettings()
        var schedule: [DayKey: String] = [:]
        for (k, v) in state?["schedule"] as? [String: String] ?? [:] {
            if let day = DayKey(string: k) { schedule[day] = v }
        }
        self.schedule = schedule
        // 周会、记录各存一份；以前在设置里的，第一次打开时搬过去
        var migrationFailed = false
        let legacy = state?["settings"]
        let loadedMeeting = Self.loadSide(MeetingState.self, url: Self.meetingURL, legacySettings: legacy,
                                          names: LegacySettings.meeting, defaults: MeetingState(), migrationFailed: &migrationFailed)
        meeting = loadedMeeting.0
        meetingBlocked = loadedMeeting.blocked
        let loadedRecords = Self.loadSide(RecordsState.self, url: Self.recordsURL, legacySettings: legacy,
                                          names: LegacySettings.records, defaults: RecordsState(), migrationFailed: &migrationFailed)
        records = loadedRecords.0
        recordsBlocked = loadedRecords.blocked
        // 搬的时候没写进去：这次都不存盘（设置存档里的旧字段还在，下次再搬）
        if migrationFailed { persistenceBlocked = true }
        if let saved = state?["covered"] as? [String] {
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
        // 存档读不出来（损坏、手机还没解锁过）时设置是默认的，版本号看不出新旧：不能因此把全员排班清掉
        if state == nil { settings.rosterVersion = Self.rosterVersion }
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
        matcher = ShiftMatcher(types: settings.shiftTypes)
        publishedDays = Self.published(in: roster, matcher: matcher)
        applyCustomHolidays()
        // 打包时内置的值班网站地址（只在 TestFlight 版里有，不在公开的代码和安装包里）：还没填网址的直接用上
        if settings.sourceURL.trimmingCharacters(in: .whitespaces).isEmpty, let builtIn = Self.builtInSiteURL {
            settings.sourceURL = builtIn
            settings.syncViaWeb = true
        }
        if Self.isDemo { loadDemoData() }
    }

    /// 截图用的演示模式（启动参数 -demo）：全是虚构数据，不读写手机上的文件、不联网
    /// 演示模式：截图用的启动参数 -demo，或者首次打开时点了「先看演示」（给 App 审核员等不能登录值班网站的人看）
    static let launchDemo = ProcessInfo.processInfo.arguments.contains("-demo")
    static var isDemo: Bool { launchDemo || UserDefaults.standard.bool(forKey: demoKey) }
    static let demoKey = "reviewDemo"

    /// 打包时写进去的值班网站地址（GitHub 机密 SITE_URL → Info.plist 的 DefaultSiteURL）；没写就是 nil
    static var builtInSiteURL: String? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "DefaultSiteURL") as? String ?? "").trimmingCharacters(in: .whitespaces)
        return raw.isEmpty || raw.hasPrefix("$(") ? nil : raw
    }

    /// 进入演示：全是虚构数据，不读写手机上的文件、不联网（真实数据原样留着，退出后回来）
    func enterDemo() {
        flushSave(wait: true)   // 先把还没写的真实数据存好，进了演示就不再写
        UserDefaults.standard.set(true, forKey: Self.demoKey)
        role = .admin
        loadDemoData()
    }

    /// 退出演示：从手机上重新读回真实数据
    func exitDemo() {
        // 读回的过程中还算演示（不往手机上写），全部换回真实数据后才关掉，免得把虚构数据存进去
        let state = (try? Data(contentsOf: Self.fileURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        settings = state.map { AppSettings.load(from: $0["settings"]) } ?? AppSettings()
        var restored: [DayKey: String] = [:]
        for (k, v) in state?["schedule"] as? [String: String] ?? [:] { if let day = DayKey(string: k) { restored[day] = v } }
        schedule = restored
        covered = Set((state?["covered"] as? [String] ?? []).compactMap(DayKey.init(string:)))
        var migrationFailed = false
        let loadedMeeting = Self.loadSide(MeetingState.self, url: Self.meetingURL, legacySettings: state?["settings"],
                                          names: LegacySettings.meeting, defaults: MeetingState(), migrationFailed: &migrationFailed)
        meetingBlocked = loadedMeeting.blocked
        meeting = loadedMeeting.0
        let loadedRecords = Self.loadSide(RecordsState.self, url: Self.recordsURL, legacySettings: state?["settings"],
                                          names: LegacySettings.records, defaults: RecordsState(), migrationFailed: &migrationFailed)
        recordsBlocked = loadedRecords.blocked
        records = loadedRecords.0
        roster = Self.loadRoster()
        rosterSources = Self.loadSources()
        rosterLog = Self.loadLog()
        publishedDays = Self.published(in: roster, matcher: matcher)
        role = UserRole(rawValue: UserDefaults.standard.string(forKey: "userRole") ?? "") ?? .user
        applyCustomHolidays()
        UserDefaults.standard.set(false, forKey: Self.demoKey)
        requestReschedule()
    }

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
        // 工作留痕是真实记录（演示时照常能看）：面容 ID 锁照旧，文件也不挪地方
        s.workLogLock = settings.workLogLock
        s.aliases = [me]
        s.favorites = ["林夏", "周远"]
        s.restBalance = ["陈晨": 3, "林夏": 5, "周远": 1, "孙悦": 2, "赵一凡": 4, "钱程": 0, "苏桐": 6, "郑宁": 2]
        s.restHistory = [me: [RestPoint(day: today.adding(days: -30), value: 1), RestPoint(day: today.adding(days: -18), value: 2),
                              RestPoint(day: today.adding(days: -9), value: 4), RestPoint(day: today, value: 3)]]
        s.manualGroupNotes = ["组A": "1、巡检机房；2、填写运行日志；3、16:30 前交接", "组B": "数据处理与归档",
                              "组C": "设备维护", "组D": "值守监控", "组E": "外场保障"]
        records = RecordsState(changeLog: [ChangeLogEntry(date: Date().addingTimeInterval(-3600),
                                                          text: "\(today.adding(days: 2).dateText)：组B → 组D（和周远对换：周远原来是组D，现在是组B）")])
        s.swapRecords = [SwapRecord(day: today.adding(days: -6), person: "林夏", myOld: "遥测", myNew: "休息", effect: -1)]
        s.teamChanges = [TeamChange(day: today.adding(days: 2), post: "组B", from: ["周远"], to: [me])]
        s.lastSync = Date().addingTimeInterval(-600)
        s.lastSyncMessage = "同步成功：30 天，没有变动，这次读到 9 人有排班（全年累计 12 人）"
        records.yearArchives = Self.demoYearArchives(people: people, today: today)
        meeting = MeetingState(docURL: "https://www.kdocs.cn/l/demo", issues: Self.demoMeetingIssues(week: MeetingTracker.monday(of: today)),
                               lastImport: Date().addingTimeInterval(-3 * 3600), week: MeetingTracker.monday(of: today))
        settings = s
        roster = r
        schedule = r[me] ?? [:]
        covered = Set((-40...14).map { today.adding(days: $0) })
    }

    /// 演示用的往年统计（虚构）：前两年，每人数字有高有低
    private static func demoYearArchives(people: [String], today: DayKey) -> [YearArchive] {
        (1...2).map { back in
            let year = today.year - back
            let days = [DayKey(year: year, month: 1, day: 1), DayKey(year: year, month: 12, day: 31)]
            let workloads = people.enumerated().map { i, name in
                let duty = 38 + (i * 5 + back * 3) % 9
                let regular = 190 + (i * 7 + back * 11) % 25
                return PersonWorkload(name: name, dutyDays: duty, dutyRestDays: 0, regularDays: regular,
                                      offDays: 365 - duty - regular - 12, holidayDays: 9, tripDays: (i + back) % 4,
                                      holidayWorkedDays: 2 + (i + back) % 3, posts: [:])
            }
            var archive = YearArchive(year: year, days: days, people: workloads)
            archive.days = 365
            return archive
        }
    }

    /// 演示用的周会问题（虚构）：三个组，没解决、本周新提、待确认、已解决各有
    private static func demoMeetingIssues(week: DayKey) -> [MeetingIssue] {
        let last = week.adding(days: -7), earlier = week.adding(days: -21)
        let dispatch = "1.接入新站后排队规则不清\n2.接口改造\n3.增加不参与合并的标识"
        func source(_ row: Int, _ n: Int, _ content: String, _ topic: String, _ owner: String, _ closure: String) -> MeetingSource {
            MeetingSource(row: row, contentColumn: 3, number: n, content: content, closureColumn: 6, closure: closure,
                          ownerColumn: 5, owner: owner, topic: topic)
        }
        func issue(_ id: String, _ group: String, _ text: String, first: DayKey, status: MeetingIssue.Status,
                   detail: String, source: MeetingSource?) -> MeetingIssue {
            MeetingIssue(id: id, group: group, text: text, firstWeek: first, lastWeek: status == .quiet ? last : week, status: status,
                         resolvedWeek: status == .resolved ? week : nil, detail: detail, source: source)
        }
        // 早几周已经解决的（各组趋势里看得出走势）
        let solved = [
            MeetingIssue(id: "d0", group: "调度组", text: "交接表格式统一", firstWeek: week.adding(days: -42), lastWeek: week.adding(days: -21),
                         status: .resolved, resolvedWeek: week.adding(days: -21), detail: "本周问题 · 负责人：周远"),
            MeetingIssue(id: "m0", group: "管理组", text: "夜间巡检记录补全", firstWeek: week.adding(days: -35), lastWeek: week.adding(days: -14),
                         status: .resolved, resolvedWeek: week.adding(days: -14), detail: "本周问题 · 负责人：孙悦"),
        ]
        return solved + [
            issue("d1", "调度组", "接入新站后排队规则不清", first: earlier, status: .open,
                  detail: "上上周问题进展 · 负责人：林夏 · 进展：进行中", source: source(2, 1, dispatch, "上上周问题进展", "林夏", "1. 进行中；2. 完成")),
            issue("d2", "调度组", "接口改造", first: last, status: .resolved,
                  detail: "上上周问题进展 · 负责人：林夏 · 进展：完成", source: source(2, 2, dispatch, "上上周问题进展", "林夏", "1. 进行中；2. 完成")),
            issue("d3", "调度组", "增加不参与合并的标识", first: last, status: .open,
                  detail: "上上周问题进展 · 负责人：林夏", source: source(2, 3, dispatch, "上上周问题进展", "林夏", "1. 进行中；2. 完成")),
            issue("d4", "调度组", "参数位置不能修改", first: week, status: .open,
                  detail: "本周问题 · 负责人：陈晨", source: source(3, 1, "参数位置不能修改", "本周问题", "陈晨", "")),
            issue("m1", "管理组", "异常结果判断标准不清，需要给出结论", first: earlier, status: .open,
                  detail: "（上周）异常处置问题 · 负责人：孙悦、陈晨 · 进展：再讨论", source: nil),
            issue("m2", "管理组", "重传两次后仍有缺失", first: last, status: .quiet,
                  detail: "（上周）异常处置问题 · 负责人：孙悦", source: nil),
            issue("r1", "遥控组", "回放功能开发", first: last, status: .resolved,
                  detail: "系统开发 · 负责人：钱程 · 进展：上线", source: nil),
            issue("r2", "遥控组", "表格核对", first: week, status: .open,
                  detail: "系统开发 · 负责人：苏桐 · 状态：进行中", source: nil),
        ]
    }

    /// 以前读错过表、把同事的名字当成了我的班（「戴明」「韩松」）：清掉这些日子，下次同步当作重新开始（不提醒变动、不重复记），
    /// 因此记下的假变动、换班账一起去掉
    func repairNameShifts() {
        guard !Self.isDemo else { return }
        let colleagues = colleagueNames()
        var s = settings
        // 以前把「值班查看」里一行人名当成了组别说明
        s.autoGroupNotes = s.autoGroupNotes.filter { !GroupNotes.isNameList($0.value, matcher: matcher) }
        let bad = schedule.compactMapValues { colleagueName(in: $0, colleagues: colleagues) }
        if !bad.isEmpty {
            let wrongNames = Set(bad.values)
            var fixed = schedule
            for day in bad.keys { fixed[day] = nil }
            schedule = fixed
            covered.subtract(bad.keys)
            s.nextSyncIsBaseline = true
            // 当时多半是卡在了读错的那个数据接口上：重新认
            s.apiSignature = nil
            // 只删假变动那几行，同一条里真的变动留着
            func isFake(_ line: Substring) -> Bool { wrongNames.contains { line.contains("→ \($0)") || line.contains("\($0) →") } }
            self.records.changeLog = self.records.changeLog.compactMap { e in
                let lines = e.text.split(separator: "\n").filter { !isFake($0) }
                return lines.isEmpty ? nil : ChangeLogEntry(date: e.date, text: lines.joined(separator: "\n"))
            }
            s.swapRecords = s.swapRecords.filter { !wrongNames.contains($0.myOld) && !wrongNames.contains($0.myNew) }
        }
        if s != settings { settings = s }
    }

    /// 同事的名字：网站人员表里的人（没有人员表时用全员排班里排过至少 3 天的人），不算我，也不算像岗位的词
    func colleagueNames(extra: Set<String> = []) -> Set<String> {
        let site = Set(settings.sitePeople.keys).union(extra)
        let known = site.isEmpty ? Set(roster.filter { $0.value.count >= 3 }.keys) : site
        return known.filter { !isMe($0) && !matcher.isStrictMatch($0) && !GroupNotes.isGroup($0) }
    }

    /// 这条「我的班」里出现的同事名字（「戴明」「戴明(5)」「戴明 韩松」都认得出）；没有返回 nil
    func colleagueName(in raw: String, colleagues: Set<String>) -> String? {
        let cleaned = raw.replacingOccurrences(of: #"[（(]\s*-?\d+\s*[)）]"#, with: " ", options: .regularExpression)
        return cleaned.split(whereSeparator: { "+、,，;；/ \t\n".contains($0) }).map(String.init).first(where: colleagues.contains)
    }

    /// 把自己录入的节假日交给统计用的节假日表
    func applyCustomHolidays() {
        AccentTheme.current = settings.accentTheme
        VoiceSound.voiceIdentifier = settings.voiceIdentifier
        VoiceSound.rate = min(max(settings.voiceRate, 0.3), 0.6)
        ChinaHolidays.customOff = Set(settings.customHolidayOff)
        ChinaHolidays.customWork = Set(settings.customHolidayWork)
        ChinaHolidays.saturdayIsWorkday = settings.saturdayIsWorkday
        ChinaHolidays.downloadedOff = Set(settings.downloadedHolidayOff)
        ChinaHolidays.downloadedWork = Set(settings.downloadedHolidayWork)
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

    /// 存盘：同一时间连续改好几处（一次同步要改十几处）只写一次，而且在后台线程写，不卡界面
    private var saveTask: Task<Void, Never>?
    /// 启动时存档文件读不出来（受保护）：不存盘，下次正常启动再说
    private var persistenceBlocked = false

    private func save() {
        if Self.isDemo { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.flushSave()
        }
    }

    /// 马上把还没写的存下来（退到后台、后台任务结束时调用，免得被系统结束时丢改动）
    func flushSave(wait: Bool = false) {
        saveTask?.cancel()
        saveTask = nil
        if Self.isDemo || persistenceBlocked { return }
        let state = PersistedState(settings: settings,
                                   schedule: Dictionary(uniqueKeysWithValues: schedule.map { ($0.key.description, $0.value) }),
                                   covered: covered.map(\.description).sorted())
        StateWriter.shared.write(state, to: Self.fileURL)
        if wait { StateWriter.shared.waitUntilDone() }
    }

    // MARK: - 排班

    /// 班次识别：只在班次类型变了时重建（以前每次用都重建一个）
    private(set) var matcher = ShiftMatcher(types: ShiftType.defaults)

    var parser: ScheduleParser {
        ScheduleParser(aliases: settings.aliases, reference: .today, timeZone: .current)
    }

    func shift(on day: DayKey) -> String? { mySchedule[day] }

    /// 看的、提醒用的「我的班」：「我的分工」接口里没有休息、值班交接前、调休、请假、出差这些，
    /// 全员排班里我这天有这些就补上（以前日历上这些日子只剩一个点，像是我的信息没了）；
    /// 「我的分工」还没取到的日子（以前的月份），全员排班里我的岗位也补上。比较变动、存档仍然只用 schedule
    var mySchedule: [DayKey: String] {
        let key = "\(dataRevision)-\(covered.count)"
        if let cached = myScheduleCache, cached.key == key { return cached.value }
        var s = schedule
        if let me = myRosterName, let mine = roster[me] {
            for (day, raw) in mine where s[day] == nil
                && (RosterExtractor.isLeave(raw, matcher: matcher) || !covered.contains(day)) {
                s[day] = raw
            }
        }
        myScheduleCache = (key, s)
        return s
    }

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
        // 只是写法不同（「组A、组E」和「组A+组E」、两种休息）不算变动
        return ScheduleDiff.changes(old: old, new: new, from: .today)
            .filter { knownBefore.contains($0.day) || $0.old != nil }
            .filter { !RosterMerger.sameMeaning($0.old, $0.new, matcher: matcher) }
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
        // 只放网站「值班查看」上写的内容（和自己填的）。网站后台组表里的「负责的星」网页上不显示，
        // 以前放在最前面，既和网站对不上，还会被当成清单的一项，所以不再加进来（数据仍照常读取保存）
        return matcher.displayName(raw).split(separator: "+").compactMap { part in
            let key = String(part).filter { !$0.isWhitespace }.uppercased()
            guard let text = notes[key], !text.isEmpty else { return nil }
            return (group: String(part), note: text)
        }
    }

    /// 某一天所有岗位各是谁（来自全员排班），按网页上的习惯排序：遥测、调度、组A–E、其它、休息、调休。
    /// 日历每个格子、今天页都要问「这天谁值什么」：同一份数据只算一次
    private var dayRosterCache: (revision: Int, days: [DayKey: [(post: String, names: [String])]]) = (-1, [:])

    func dayRoster(_ day: DayKey) -> [(post: String, names: [String])] {
        if dayRosterCache.revision != dataRevision { dayRosterCache = (dataRevision, [:]) }
        if let cached = dayRosterCache.days[day] { return cached }
        let value = computeDayRoster(day)
        dayRosterCache.days[day] = value
        return value
    }

    private func computeDayRoster(_ day: DayKey) -> [(post: String, names: [String])] {
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
        if mySchedule[day] != nil { return true }
        // 网站已经排了这天（全员排班里有人排了组别、遥测）、全员排班里也有我，却没给我排：就是没排班
        if publishedDays.contains(day), myRosterName != nil { return true }
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
        // 演示数据不排提醒（手机上原来排好的真实提醒原样留着）
        guard !Self.isDemo else { return }
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
            // 手动下拉时正在跑的是自动同步：那次可能在网站刚改之前就读过了，等它做完再读一次最新的
            //（自动同步不会重试登录、不采用异常结果，这一次也会补上）
            guard renamed || (userInitiated && !runningWasUser) else { return ok }
            // 等待期间别人已经开始了新的一次：用那一次
            if let next = syncTask { return await next.value }
        }
        // 放在独立的任务里跑：下拉刷新的界面消失、切换页面时 SwiftUI 会取消调用方，
        // 不能让读到一半的全员排班跟着作废（以前会显示「CancellationError」）
        let task = Task { () -> Bool in
            let start = Date()
            let ok = await self.performSync(full: full, userInitiated: userInitiated)
            // 被系统中途收回的不记（不是失败）
            if self.canSync, !Task.isCancelled {
                let entry = SyncLogEntry(date: start, source: source, ok: ok,
                                         message: self.settings.lastSyncMessage ?? "", seconds: Int(Date().timeIntervalSince(start)))
                self.records.syncLog = Array(([entry] + self.records.syncLog).prefix(30))
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

    /// 网站接口里的人员设置、公告、固定遥测日子：存下来给排班规律用
    @discardableResult
    func applySiteInfo(_ site: SiteAPI.Result) -> [String] {
        var s = settings
        if !site.people.isEmpty { s.sitePeople = site.people }
        // 公告变了：记下新出现的几条（第一次读到不算变化）
        var newNotices: [String] = []
        if !site.notices.isEmpty, site.notices != s.siteNotices {
            if !s.siteNotices.isEmpty {
                let old = Set(s.siteNotices.map(Self.noticeKey))
                newNotices = site.notices.filter { !old.contains(Self.noticeKey($0)) }
                if !newNotices.isEmpty {
                    s.siteNoticesChanged = Date()
                    s.siteNoticesNew = newNotices
                }
            }
            s.siteNotices = site.notices
        }
        if !site.groupSatellites.isEmpty { s.groupSatellites = site.groupSatellites }
        // 这次接口里读到的日子：「该休没休」「固定」以网站这次为准（网站取消了的要去掉），别的日子保留以前的
        let freshDays = Set(site.roster.values.flatMap(\.keys)).map(\.description)
        let fresh = Set(freshDays)
        if !site.noRest.isEmpty || !fresh.isEmpty {
            let cutoff = DayKey.today.adding(days: -60).description
            let kept = s.siteNoRestFlags.filter { !fresh.contains(String($0.prefix(10))) }
            let flags = Set(kept + site.noRest.map { "\($0.day)|\($0.name)|\($0.column)" })
            s.siteNoRestFlags = flags.filter { $0 >= cutoff }.sorted()
        }
        if !site.fixedTelemetryDays.isEmpty || !fresh.isEmpty {
            let cutoff = DayKey.today.adding(days: -400)
            let kept = Set(s.fixedTelemetryDays.compactMap(DayKey.init(string:))).filter { !fresh.contains($0.description) }
            let all = kept.union(site.fixedTelemetryDays).filter { $0 >= cutoff }
            s.fixedTelemetryDays = all.sorted().map(\.description)
        }
        if s != settings { settings = s }
        // 待休天数：网站人员表里直接有（unrestDays），比从人名后的括号里读更准
        let balances = site.people.compactMapValues(\.unrestDays)
        if !balances.isEmpty { updateRestBalance(balances) }
        return newNotices
    }

    /// 比较公告时不管空白：网站只是换了换行、空格不算新公告
    private static func noticeKey(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    /// 网站公告出现了新内容：通知一次，点开看全部公告
    func notifyNoticeChange(_ fresh: [String]) async {
        guard !Self.isDemo, !fresh.isEmpty else { return }
        let title = "📌 值班网站公告有更新"
        let body = fresh.map { $0.count > 120 ? String($0.prefix(120)) + "…" : $0 }.joined(separator: "\n")
        await NotificationService.notifyNow(id: "site-notice", title: title, body: body, route: "notices")
        if settings.weChatEnabled && settings.weChatTeam { _ = await pushToWeChat(title: title, content: fresh.joined(separator: "\n\n")) }
    }

    /// 网站标了我「该休没休」（今天及以后）：每处提醒一次
    func notifySiteNoRest(_ flags: [SiteAPI.NoRest]) async {
        guard !Self.isDemo else { return }
        let today = DayKey.today
        let mine = flags.filter { $0.day >= today && isMe($0.name) }
            .filter { !settings.noRestNotified.contains("\($0.day)|\($0.column)") }
        guard !mine.isEmpty else { return }
        let lines = mine.sorted { $0.day < $1.day }.map { "\($0.day.month)月\($0.day.day)日 本该在「\($0.column)」，网站标了没休" }
        settings.noRestNotified = Array((settings.noRestNotified + mine.map { "\($0.day)|\($0.column)" }).suffix(100))
        let title = "⚠️ 网站标了你该休没休"
        let body = lines.joined(separator: "\n") + "\n记得找时间补休，或者和排班的同事确认。"
        await NotificationService.notifyNow(id: "site-norest-\(UUID().uuidString)", title: title, body: body)
        if settings.weChatEnabled { _ = await pushToWeChat(title: title, content: body) }
    }

    /// 每周一次：下载今年、明年的法定节假日安排（国家公布后自动有，不用手动录入）
    func refreshHolidaysIfNeeded() async {
        guard !Self.isDemo, Date().timeIntervalSince(settings.lastHolidayFetch ?? .distantPast) > 7 * 86400 else { return }
        let year = DayKey.today.year
        var off = Set(settings.downloadedHolidayOff), work = Set(settings.downloadedHolidayWork)
        var gotAny = false
        for y in [year, year + 1] {
            var request = URLRequest(url: HolidayFeed.url(year: y), timeoutInterval: 20)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, let parsed = HolidayFeed.parse(data) else { continue }
            // 这一年的整套替换（国家调整过安排时跟着变）
            off = off.filter { !$0.hasPrefix("\(y)-") }.union(parsed.off)
            work = work.filter { !$0.hasPrefix("\(y)-") }.union(parsed.work)
            gotAny = true
        }
        guard gotAny else { return }
        var s = settings
        s.downloadedHolidayOff = off.sorted()
        s.downloadedHolidayWork = work.sorted()
        s.lastHolidayFetch = Date()
        if s != settings { settings = s }
    }

    /// 还没设「我是谁」时：拿网站上「我的分工」和全员排班比，对得上的那个人就是我
    func identifyMeIfNeeded() {
        guard settings.aliases.isEmpty, !Self.isDemo else { return }
        guard let name = RosterExtractor.identify(mine: schedule, roster: roster, matcher: matcher) else { return }
        setMe(name)
        ToastCenter.shared.show("认出你是「\(name)」，已设为使用者", style: .success)
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
        settings.lastSyncAttempt = Date()
        // 正在读电脑版页面：让它停下，等它的浏览器关掉再开始（最多等 15 秒）
        if let cancel = desktopFetch {
            cancel()
            for _ in 0..<50 where desktopFetch != nil { try? await Task.sleep(nanoseconds: 300_000_000) }
        }
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
            // 读到的「我的班」里一半以上是同事的名字（读错了网页上的表，比如全员排班表）：这次不改我的班、不提醒变动，
            // 全员排班、公告这些照常更新
            let colleagues = colleagueNames(extra: Set(outcome.site.people.keys))
            let named = result.entries.values.compactMap { colleagueName(in: $0, colleagues: colleagues) }
            let wrongName = !named.isEmpty && named.count * 2 >= result.entries.count ? named.first : nil
            if wrongName == nil, !userInitiated, !settings.nextSyncIsBaseline, result.range != nil {
                // 已经知道的日子里，一大半都变了：多半是网站改版读错了，先不采用
                // 和 apply() 同一个规则：网站还没正式排班、只有请假调休记录的以后日子不算「已经知道」
                let known = SyncPolicy.knownDays(covered: covered, replaced: result.replacedDays(calendar: .app), today: .today,
                                                 published: publishedDays, rosterDays: Set(roster.values.flatMap(\.keys)))
                let changed = known.filter { schedule[$0] != result.entries[$0] }.count
                if SyncPolicy.looksBroken(known: known.count, changed: changed) {
                    let alreadyTold = settings.syncState == .anomaly
                    settings.syncState = .anomaly
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
            // 什么都没读到（网络慢、后台时间不够）：这次不合并，也不当成网站改版；
            // 后台快速同步只读到一部分时不报警（时间有限，读不全很正常），只是不合并
            let healthy = outcome.roster.isEmpty ? false
                : await checkSyncHealth(outcome.roster, source: full ? "sync-full" : "sync-quick", title: "同步",
                                        accept: userInitiated, quiet: !full && !userInitiated)
            if healthy || userInitiated {
                let edits = mergeRoster(outcome.roster, source: "sync")
                if !baselineRun { await notifyRosterEdits(edits, published: publishedBefore) }
                if !baselineRun { await recordTeamChanges(before: rosterBefore, days: freshDays.intersection(publishedBefore)) }
            }
            await notifyRestWarnings()
            await notifyDutyHeadsUp()
            updateRestBalance(outcome.restBalance)
            let freshNotices = applySiteInfo(outcome.site)
            await notifyNoticeChange(freshNotices)
            await notifySiteNoRest(outcome.site.noRest)
            if !outcome.groupNotes.isEmpty { settings.autoGroupNotes.merge(outcome.groupNotes) { _, n in n } }

            if let wrongName {
                var failed = settings
                failed.syncState = .anomaly
                failed.lastSyncMessage = "同步结果异常：读到的「我的班」里是同事的名字（\(wrongName)），可能读错了网页上的表，这次没有改你的班"
                failed.syncFailureCount += 1
                // 下次重新找「我的班」的数据接口
                failed.apiSignature = nil
                settings = failed
                await notifyIfSyncStale()
                return false
            }
            let hadData = !schedule.isEmpty && !settings.nextSyncIsBaseline
            // 同步途中又改了名字：这次用的是旧名字，下次还要当作重新开始
            if settings.aliases == aliasesAtStart { settings.nextSyncIsBaseline = false }
            let changes = apply(result, publishedBefore: publishedBefore,
                                rosterDaysBefore: Set(rosterBefore.values.flatMap(\.keys)))
            identifyMeIfNeeded()
            // 预演打分、「快轮到你」都要用遥测推算：先在后台算好
            await warmRotation()
            scorePreview()
            // 同步状态一次改完：只触发一次比较、存盘和界面刷新
            var status = settings
            status.lastSync = Date()
            status.loginExpiredNotified = false
            status.syncStaleNotified = false
            // 给人看的不提读取方式（「数据接口」「JSON」这些）；诊断页的「上次成功结果」带上
            status.lastSyncMessage = "同步成功：\(result.entries.count) 天"
                + (changes.isEmpty ? "，没有变动" : "，\(changes.count) 处变动")
                + (outcome.roster.isEmpty ? "" : "，这次读到 \(outcome.roster.count) 人有排班（全年累计 \(roster.count) 人）")
            status.lastSuccessMessage = (status.lastSyncMessage ?? "") + "（读取方式：\(result.format.rawValue)）"
            status.syncState = .ok
            status.syncFailureCount = 0
            settings = status
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
                self.records.changeLog = Array(([ChangeLogEntry(date: Date(), text: body)] + self.records.changeLog).prefix(20))
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
            // 系统收回后台时间、用户离开页面：不是同步失败，不改状态、不报警
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled { return false }
            var failed = settings
            failed.lastSyncMessage = "同步失败：\(error.localizedDescription)"
            if case SyncError.needsLogin = error { failed.syncState = .needsLogin } else { failed.syncState = .failed }
            failed.syncFailureCount += 1
            settings = failed
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

    /// 「读取以前的全员排班」最早能读到哪天：最多往前 60 周，全员排班也只留 400 天
    func historyLabel(since year: Int) -> String {
        let jan1 = DayKey(year: year, month: 1, day: 1)
        let earliest = DayKey.today.adding(days: -399)
        guard earliest > jan1 else { return "\(String(year)) 年 1 月以来全部" }
        return "\(String(earliest.year)) 年 \(earliest.month) 月 \(earliest.day) 日以来（最多一年多）"
    }

    /// 从电脑版页面一周周往前翻，读到某年 1 月 1 日为止（App 只留一年多的全员排班）
    @discardableResult
    func readHistory(since year: Int) async -> Bool {
        let start = DayKey(year: year, month: 1, day: 1).date(calendar: .app, hour: 12)
        let days = Calendar.app.dateComponents([.day], from: start, to: Date()).day ?? 0
        return await readDesktopNotes(weeksBack: min(60, max(1, days / 7 + 1)))
    }

    @Published private(set) var isReadingDesktop = false
    /// 正在读电脑版页面时，取消它（同步优先：两个隐藏浏览器同时登录网站会互相挤下线）
    private var desktopFetch: (() -> Void)?

    @discardableResult
    private func readDesktopNotesNow(mayLogin: Bool, weeksBack: Int = 9) async -> Bool {
        let readStarted = Date()
        settings.lastDesktopNotesAttempt = readStarted
        let fetch = Task {
            await SyncService.fetchDesktopGroupNotes(urlString: settings.sourceURL,
                                                     overrideURL: settings.desktopNotesURL,
                                                     username: settings.sourceUsername,
                                                     password: mayLogin ? (Keychain.get(.sourcePassword) ?? "") : "",
                                                     reference: .today,
                                                     matcher: matcher, weeksBack: weeksBack)
        }
        desktopFetch = { fetch.cancel() }
        let result = await fetch.value
        desktopFetch = nil
        // 同步要用网站，把这次读取让掉了：不合并读了一半的数据，过一会儿再读
        if fetch.isCancelled {
            settings.lastDesktopNotesAttempt = nil
            return false
        }
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
        await notifyDutyHeadsUp()
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
    func checkSyncHealth(_ roster: Roster, source: String, title: String, accept: Bool = false, quiet: Bool = false) async -> Bool {
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
        if quiet { return false }
        let text = "\(title)读到的全员排班和平时不一样：" + problems.joined(separator: "；")
            + "。可能是网站改版了，工作量统计、休息核对可能不准。"
        settings.syncHealthWarning = text
        guard settings.syncHealthWarnedDay != .today else { return false }
        settings.syncHealthWarnedDay = .today
        await NotificationService.notifyNow(id: "sync-health", title: "⚠️ 值班网站可能改版了", body: text)
        return false
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

    /// 昨天值了遥测、现在是今天接班时间（默认 8:30）到设定的补觉结束时间之间
    func isRestingAfterDuty(now: Date = Date()) -> Bool {
        let today = DayKey(date: now, calendar: .app)
        guard let raw = schedule[today.adding(days: -1)], WorkloadCounter.isDuty(matcher.displayName(raw)) else { return false }
        let start = today.date(calendar: .app, hour: settings.dutyStart.hour, minute: settings.dutyStart.minute)
        let end = today.date(calendar: .app, hour: settings.restFocusUntil.hour, minute: settings.restFocusUntil.minute)
        return now >= start && now < end
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
        guard !Self.isDemo, let bookmark = settings.backupFolderBookmark else { return }
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
        return !self.records.syncLog.contains { $0.date > since && $0.source.hasPrefix("快捷指令") }
    }

    /// 我在网站上的名字（全员排班里认出是我的那个）
    /// 全员排班里哪个名字是我（很多页面每行都要问，按数据版本缓存）
    var myRosterName: String? {
        let key = "\(dataRevision)-\(role.rawValue)"
        if let cached = myNameCache, cached.key == key { return cached.value }
        let value = roster.keys.first(where: isMe) ?? settings.restBalance.keys.first(where: isMe)
        myNameCache = (key, value)
        return value
    }
    private var myNameCache: (key: String, value: String?)?
    private var myScheduleCache: (key: String, value: [DayKey: String])?

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
                                        carriesLeave: carries, carriedKinds: RosterMerger.leaveKinds(new, matcher: matcher),
                                        today: .today, matcher: matcher)
        // 留一年多，全年统计用
        let cutoff = DayKey.today.adding(days: -400)
        // 以前没拆开存下的「张三李四」也一起拆开
        roster = RosterExtractor.splitJoinedNames(result.roster).mapValues { $0.filter { $0.key >= cutoff } }.filter { !$0.value.isEmpty }
        rosterSources = result.sources.mapValues { $0.filter { $0.key >= cutoff } }.filter { !$0.value.isEmpty }
        if !result.edits.isEmpty { rosterLog = Array((rosterLog + result.edits).suffix(3000)) }
        // 网站排出了新的一周：记下时间，学网站一般什么时候排班
        // 重新开始的那次同步（刚恢复备份、改了名字）不算：恢复的旧数据后面接上新读到的，不是网站刚排出来的
        if !settings.nextSyncIsBaseline, let before = lastPublished, let after = publishedDays.max(), after > before.adding(days: 3) {
            s.publishTimes = Array((s.publishTimes + [Date()]).suffix(40))
            let fresh = publishedDays.filter { $0 > before }.sorted()
            Task { [weak self] in await self?.notifyNewWeek(fresh) }
        }
        if s != settings { settings = s }
        saveRoster()
        saveSourcesAndLog()
        // 已排班的日子变了，「未排班」提醒也要跟着变
        requestReschedule()
        return result.edits
    }

    /// 网站排出了新的一周：告诉我这几天我是什么班（有遥测的特别标出来）
    func notifyNewWeek(_ days: [DayKey]) async {
        guard !Self.isDemo, settings.notifyChanges, let first = days.first, let last = days.last else { return }
        let me = myRosterName
        var lines: [String] = []
        var duty: [DayKey] = []
        for d in days {
            guard let raw = (me.flatMap { roster[$0]?[d] }) ?? schedule[d] else { continue }
            let name = matcher.displayName(raw)
            if WorkloadCounter.isDuty(name) { duty.append(d) }
            lines.append("\(d.month)/\(d.day) \(d.weekdayText) \(name)")
        }
        let title = duty.isEmpty ? "📅 新排班出来了（\(first.month)/\(first.day)–\(last.month)/\(last.day)）"
            : "📅 新排班出来了：你 \(duty.map { "\($0.month)/\($0.day)" }.joined(separator: "、")) 值遥测"
        let body = lines.isEmpty ? "这几天没有给你排班。" : lines.joined(separator: "\n")
        await NotificationService.notifyNow(id: "new-week-\(first)", title: title, body: body)
        if settings.weChatEnabled && settings.weChatChanges { _ = await pushToWeChat(title: title, content: body) }
    }

    /// 保存从电脑版页面读到的各组说明。
    func applyDesktopNotes(_ notes: [String: String]) async {
        settings.desktopGroupNotes = notes
        settings.lastDesktopNotesFetch = Date()
        settings.desktopNotesMessage = "读到 \(notes.count) 个组：" + notes.keys.sorted().joined(separator: "、")
        await rescheduleNotifications()
    }

    /// 超过一天没有同步成功（密码改了、网站换了地址或改版）。
    /// 今天页显示红色横幅：上次同步失败、而且超过 6 小时没成功过（以前要等 24 小时）
    var syncLooksBroken: Bool {
        guard canSync else { return false }
        if syncIsStale { return true }
        guard let last = settings.lastSync, settings.syncState?.isFailure == true else { return false }
        return Date().timeIntervalSince(last) > 6 * 3600
    }

    var syncIsStale: Bool {
        guard canSync else { return false }
        guard let last = settings.lastSync else { return settings.syncState?.isFailure ?? false }
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
        // 3 分钟内成功过不再同步；连续失败时隔得越来越久（2、4、8 分钟……最多 2 小时）；手动下拉不受影响
        guard SyncPolicy.shouldAutoSync(now: Date(), lastSync: settings.lastSync, lastAttempt: settings.lastSyncAttempt,
                                        failures: settings.syncFailureCount) else { return }
        await sync(full: true)
    }

    /// 系统在后台唤醒 App 时调用（时间由 iOS 决定，不保证准时）。
    func backgroundRefresh() async {
        guard !Self.isDemo else { return }
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
        flushSave(wait: true)   // 后台时间随时会被收回，写完再交还
    }

    func cancelRunningSync() { syncTask?.cancel() }

    // 微信推送、日报周报月报在 AppStore+WeChat.swift
    /// 正在补发排班变动的微信（不重复发）
    var isSendingWeChatChange = false

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
                              roster: roster.mapValues { days in Dictionary(uniqueKeysWithValues: days.map { ($0.key.description, $0.value) }) },
                              meeting: meeting, records: records)
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
        // 一段一段容错地读：哪一项坏了只有那一项用默认值（备份里的日期是 ISO 8601）
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], file["settings"] is [String: Any] else {
            throw NSError(domain: "backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "这不是值班提醒的备份文件"])
        }
        var restored: [DayKey: String] = [:]
        for (k, v) in file["schedule"] as? [String: String] ?? [:] { if let d = DayKey(string: k) { restored[d] = v } }
        schedule = restored
        covered = Set((file["covered"] as? [String] ?? []).compactMap(DayKey.init(string:)))
        roster = (file["roster"] as? [String: [String: String]] ?? [:]).mapValues { days in
            Dictionary(days.compactMap { k, v in DayKey(string: k).map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
        }
        saveRoster()
        // 周会、记录：新备份单独一段；旧备份在设置那一段里
        let meetingSource: Any? = file["meeting"] ?? LegacySettings.extract(LegacySettings.meeting, from: file["settings"])
        let recordsSource: Any? = file["records"] ?? LegacySettings.extract(LegacySettings.records, from: file["settings"])
        if let meetingSource {
            meeting = TolerantCoding.decode(MeetingState.self, from: meetingSource, defaults: MeetingState(), encoder: encoder, decoder: decoder)
        }
        if let recordsSource {
            records = TolerantCoding.decode(RecordsState.self, from: recordsSource, defaults: RecordsState(), encoder: encoder, decoder: decoder)
        }
        var newSettings = AppSettings.load(from: file["settings"], encoder: encoder, decoder: decoder)
        // 旧格式的全员排班可能读错过，清掉，同步时重新读
        if newSettings.rosterVersion < Self.rosterVersion { roster = [:]; saveRoster() }
        newSettings.rosterVersion = Self.rosterVersion
        // 备份时的同步状态已经过时：清掉，马上重新同步（也会重新尝试登录）
        newSettings.lastSync = nil
        newSettings.lastSyncMessage = nil
        newSettings.syncState = nil
        newSettings.syncFailureCount = 0
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
        // 「今天的微信发过没有」这些是这台手机上的记号：用备份里的旧记号会把今天已经发过的再发一遍
        newSettings.weChatMorningSent = settings.weChatMorningSent
        newSettings.weChatEveningSent = settings.weChatEveningSent
        newSettings.weChatWeekSent = settings.weChatWeekSent
        newSettings.lastPersonalWeekly = settings.lastPersonalWeekly
        newSettings.lastWeeklyDigest = settings.lastWeeklyDigest
        newSettings.lastMonthlyReport = settings.lastMonthlyReport
        newSettings.dutyHeadsUpSent = settings.dutyHeadsUpSent
        // 备份里没发出去的变动早就过时了，不再发
        newSettings.pendingWeChatChange = nil
        settings = newSettings
        scheduleChanged()
        Task { [weak self] in await self?.sync(userInitiated: true) }
        return restored.count
    }

    // MARK: - 工作量统计

    struct Workload: Sendable {
        var days: [DayKey]
        var people: [PersonWorkload]
        var text: String
    }

    /// 某月每个人的工作量（来自全员排班），按上班天数从多到少。
    /// month 为 nil 时统计全年（App 里留着的全员排班，最多一年多）
    /// 统计结果缓存：全员排班、我的排班、设置变了就清掉（全年统计不用每次重算）
    var workloadCache: [String: Workload] = [:]

    func invalidateWorkloadCache() { workloadCache = [:] }

    /// 统计用的数据（全员排班、我的排班、设置）每变一次加一，页面用它判断要不要重算
    /// 上次换主屏幕图标没成功的原因（诊断页显示）
    var appIconError: String?

    // 遥测推算、下次遥测、待休对账的缓存（AppStore+Duty.swift 用）
    var rotationCache: [String: SchedulePatterns.Rotation?] = [:]
    var rotationWarmup: (key: String, task: Task<Void, Never>)?
    var dutyTurnCache: (key: String, value: DutyTurn?)?
    var auditCache: (revision: Int, value: RestBalanceAudit.Result?)?

    @Published private(set) var dataRevision = 0

    // 工作量统计、表格导出在 AppStore+Stats.swift
}


/// 在后台串行写 state.json：按先后顺序写，后面的覆盖前面的（都在一个串行队列里，可以跨线程用）
final class StateWriter: @unchecked Sendable {
    static let shared = StateWriter()
    private let queue = DispatchQueue(label: "state-writer", qos: .utility)

    fileprivate func write(_ state: PersistedState, to url: URL) {
        queue.async {
            do {
                let data = try JSONEncoder().encode(state)
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                // 写不进去（比如锁屏时文件受保护）：记一笔，下次改动时会再写
                NSLog("state.json 写入失败：\(error.localizedDescription)")
            }
        }
    }

    /// 别的文件（全员排班、来源、变动历史）：在后台编码再写
    func write(to url: URL, encode: @escaping @Sendable () -> Data?) {
        queue.async {
            guard let data = encode() else { return }
            do {
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                NSLog("\(url.lastPathComponent) 写入失败：\(error.localizedDescription)")
            }
        }
    }

    /// 等前面排着的都写完
    func waitUntilDone() { queue.sync {} }
}
