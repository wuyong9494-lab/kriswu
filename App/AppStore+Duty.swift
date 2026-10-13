import SwiftUI

/// 遥测推算（后台算好再用）、排班预演、下次遥测、待休预警和对账
@MainActor
extension AppStore {
    // MARK: 遥测轮转（排班规律、下次遥测、排班预演共用）
    // 推算很费时（几百天 × 几十人、五种推法都要往回验证）：同一份数据、同一天只算一次；
    // 数据变了以后先在后台线程算好（warmRotation），界面、提醒随后直接取。缓存放在 AppStore 里（扩展里不能放存储属性）

    /// 至少往后推这么多天：各处共用一份结果（推得长一点只是多几行，前面的不变）
    private static let rotationForecast = 60

    private func rotationKey(_ forecastDays: Int) -> String {
        "\(DayKey.today)-\(dataRevision)-\(max(forecastDays, Self.rotationForecast))"
    }

    /// 后台已经算好（或者已经当场算过）
    var rotationReady: Bool { rotationCache[rotationKey(Self.rotationForecast)] != nil }

    func dutyRotation(forecastDays: Int = 60) -> SchedulePatterns.Rotation? {
        let key = rotationKey(forecastDays)
        if let cached = rotationCache[key] { return cached }
        // 后台还没算好：当场算
        let value = Self.computeRotation(rotationInput(forecastDays))
        cacheRotation(value, key: key)
        return value
    }

    /// 在后台线程把遥测推算算好放进缓存。同步完、重排提醒前、今天页出现时调用；已经有了就直接返回
    func warmRotation() async {
        let key = rotationKey(Self.rotationForecast)
        if rotationCache[key] != nil { return }
        if let running = rotationWarmup, running.key == key { await running.task.value; return }
        let input = rotationInput(Self.rotationForecast)
        let task = Task {
            let value = await Task.detached(priority: .userInitiated) { AppStore.computeRotation(input) }.value
            // 算的时候数据又变了（或者已经当场算过）：这份不用
            guard self.rotationKey(Self.rotationForecast) == key, self.rotationCache[key] == nil else { return }
            self.cacheRotation(value, key: key)
            // 今天页「下次遥测」在等它
            self.objectWillChange.send()
        }
        rotationWarmup = (key, task)
        await task.value
        if rotationWarmup?.key == key { rotationWarmup = nil }
    }

    private func cacheRotation(_ value: SchedulePatterns.Rotation?, key: String) {
        if rotationCache.count > 8 { rotationCache.removeAll() }
        rotationCache[key] = value
    }

    struct RotationInput {
        var roster: Roster
        var days: [DayKey]
        var matcher: ShiftMatcher
        var forecastDays: Int
        var people: [String: SiteAPI.Person]
        var fixed: Set<DayKey>
    }

    private func rotationInput(_ forecastDays: Int) -> RotationInput {
        RotationInput(roster: roster, days: publishedDays.filter { $0 >= DayKey.today.adding(days: -180) }.sorted(),
                      matcher: matcher, forecastDays: max(forecastDays, Self.rotationForecast),
                      people: settings.sitePeople, fixed: fixedTelemetryDaySet)
    }

    /// 只用传进来的数据，可以在后台线程算
    nonisolated static func computeRotation(_ i: RotationInput) -> SchedulePatterns.Rotation? {
        SchedulePatterns.rotation(post: "遥测", roster: i.roster, days: i.days, matcher: i.matcher, forecastDays: i.forecastDays,
                                  calendar: .app, people: i.people, fixedDays: i.fixed)
    }

    /// 排班预演：网站还没排的 days 天
    func rosterPreview(days: Int = 14) -> [RosterPreview.Day] {
        guard let rotation = dutyRotation(forecastDays: days + 14) else { return [] }
        return RosterPreview.build(rotation: rotation, roster: roster, published: publishedDays, from: .today, days: days,
                                   matcher: matcher, calendar: .app)
    }

    /// 同步后：网站新排出来的日子，和之前预演猜的对一对；再记下这次对还没排的日子的预演
    func scorePreview() {
        var s = settings
        var results = s.previewResults
        for (key, guess) in s.previewGuesses {
            guard let day = DayKey(string: key), publishedDays.contains(day) else { continue }
            let actual = roster.filter { $0.value[day].map { SchedulePatterns.isDutyPost($0, matcher: matcher) } ?? false }.keys.sorted()
            if !actual.isEmpty, !results.contains(where: { $0.day == key }) {
                results.append(PreviewResult(day: key, guess: guess, actual: actual.joined(separator: "、"), hit: actual.contains(guess)))
            }
            s.previewGuesses[key] = nil
        }
        for d in rosterPreview() { if let name = d.telemetry { s.previewGuesses[d.day.description] = name } }
        s.previewResults = Array(results.sorted { $0.day < $1.day }.suffix(120))
        if s != settings { settings = s }
    }

    var fixedTelemetryDaySet: Set<DayKey> { Set(settings.fixedTelemetryDays.compactMap(DayKey.init(string:))) }

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

    /// computeIfNeeded = false：要推算、后台又还没算好时先返回 nil（今天页用，不在主线程上等推算；算好后页面自己刷新）
    func myDutyTurn(computeIfNeeded: Bool = true) -> DutyTurn? {
        guard let me = myRosterName else { return nil }
        let today = DayKey.today
        // 数据一变（排班、设置）版本号就变，不靠人数、天数判断
        let key = "\(today)-\(me)-\(dataRevision)-\(schedule.count)"
        if let cache = dutyTurnCache, cache.key == key { return cache.value }
        let value: DutyTurn?
        let mine = (roster[me] ?? [:]).merging(schedule) { a, _ in a }
        if let next = mine.filter({ $0.key >= today && matcher.posts($0.value).contains { WorkloadCounter.isDuty(matcher.displayName($0)) } }).keys.min() {
            value = DutyTurn(day: next, ahead: 0, scheduled: true, total: 0)
        } else {
            guard computeIfNeeded || rotationReady else { return nil }
            // 和排班规律、排班预演用同一个推算
            if let r = dutyRotation(forecastDays: 60), let index = r.order.firstIndex(of: me) {
                value = DutyTurn(day: r.forecast.first { $0.name == me }?.day, ahead: index, scheduled: false, total: r.order.count)
            } else {
                value = nil
            }
        }
        dutyTurnCache = (key, value)
        return value
    }

    /// 网站还没排、推算我 7 天内可能轮到遥测：提前说一声（5 天内只说一次，只是推算）
    func notifyDutyHeadsUp() async {
        guard !Self.isDemo, settings.dutyHeadsUp,
              let turn = myDutyTurn(), !turn.scheduled, let day = turn.day else { return }
        guard (1...7).contains(where: { DayKey.today.adding(days: $0) == day }),
              Date().timeIntervalSince(settings.dutyHeadsUpSent ?? .distantPast) > 5 * 86_400 else { return }
        settings.dutyHeadsUpSent = Date()
        let ahead = turn.ahead == 0 ? "下一个就是你" : "前面还有 \(turn.ahead) 个人"
        await NotificationService.notifyNow(id: "duty-heads-up", title: "🛰️ 快轮到你值遥测了（推算）",
                                            body: "网站还没排。按遥测顺序\(ahead)，推算大约在 \(day.dateText)（\(day.weekdayText)）前后。只是推算，以网站为准。")
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
    /// 待休对账：全员几百天，同一份数据只算一次
    func restBalanceAudit() -> RestBalanceAudit.Result? {
        if let cached = auditCache, cached.revision == dataRevision { return cached.value }
        let value = RestBalanceAudit.analyze(points: settings.restHistory.mapValues { $0.map(\.point) }, roster: roster,
                                             matcher: matcher, calendar: .app)
        auditCache = (dataRevision, value)
        return value
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
}
