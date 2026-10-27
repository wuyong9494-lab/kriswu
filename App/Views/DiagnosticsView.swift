import SwiftUI
import UserNotifications

/// 一页看清 App 的状态：上面是每条对外连接通不通（自检），下面是细节。出问题时截这一页的图就能知道卡在哪一步。
struct DiagnosticsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var sections: [Section] = []
    @State private var copied = false
    /// 点「全部检查一遍」当场测出来的结果（名字 → 结果），盖过按记录推断的
    @State private var tested: [String: Check] = [:]
    @State private var checking: String?
    /// 通知权限、已登记的提醒条数（load 里读）
    @State private var notifications: (allowed: Bool, pending: Int)?

    /// 自检的一条：一条对外连接（或者系统权限）现在通不通
    struct Check: Identifiable {
        enum Status { case ok, warn, fail, off }
        var id: String { name }
        var name: String
        var status: Status
        var detail: String
    }

    struct Row: Identifiable {
        let id = UUID()
        var label: String
        var value: String
        var ok: Bool?
    }

    struct Section: Identifiable {
        let id = UUID()
        var title: String
        var rows: [Row]
    }

    var body: some View {
        let checks = selfChecks()
        List {
            SwiftUI.Section {
                ForEach(checks) { check in
                    HStack(alignment: .top, spacing: DS.Space.s) {
                        Image(systemName: symbol(check.status)).foregroundStyle(color(check.status)).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.name).font(.subheadline.weight(.medium))
                            Text(check.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                        Spacer(minLength: 0)
                        if checking == check.name { ProgressView() }
                    }
                }
                Button {
                    Task { await runChecks() }
                } label: {
                    Label(checking == nil ? "全部检查一遍" : "正在检查：\(checking ?? "")", systemImage: "checklist")
                }
                .disabled(checking != nil)
            } header: {
                Text(summary(checks))
            } footer: {
                Text("「全部检查一遍」会真的去连一次：同步一次网站、下载一次周会表格、测一次写回脚本。出问题截这一屏就够了。")
            }
            ForEach(sections) { section in
                SwiftUI.Section(section.title) {
                    ForEach(section.rows) { row in
                        HStack(alignment: .firstTextBaseline) {
                            if let ok = row.ok {
                                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(ok ? Color.green : Color.orange)
                            }
                            Text(row.label)
                            Spacer()
                            Text(row.value)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.subheadline)
                    }
                }
            }
            SwiftUI.Section {
                Button(copied ? "已复制" : "复制全部诊断信息") {
                    UIPasteboard.general.string = sections.map { s in
                        "【\(s.title)】\n" + s.rows.map { "\($0.label)：\($0.value)" }.joined(separator: "\n")
                    }.joined(separator: "\n\n")
                    copied = true
                }
                Button("重新检查") { Task { await load() } }
            } footer: {
                Text("复制的内容不包含密码和 token，可以直接发给帮你排查问题的人。")
            }
        }
        .appList()
        .navigationTitle("自检与诊断")
        .task { await load() }
    }

    // MARK: - 自检

    private func symbol(_ s: Check.Status) -> String {
        switch s {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        case .off: return "minus.circle"
        }
    }

    private func color(_ s: Check.Status) -> Color {
        switch s {
        case .ok: return DS.Palette.success
        case .warn: return DS.Palette.warning
        case .fail: return DS.Palette.danger
        case .off: return Color.secondary
        }
    }

    private func summary(_ checks: [Check]) -> String {
        let bad = checks.filter { $0.status == .fail }.count, warn = checks.filter { $0.status == .warn }.count
        if bad == 0 && warn == 0 { return "自检：都正常" }
        return "自检：" + [bad > 0 ? "\(bad) 项不通" : nil, warn > 0 ? "\(warn) 项要留意" : nil].compactMap { $0 }.joined(separator: "，")
    }

    /// 按现在记下的状态推断每条连接通不通；当场测过的用测的结果
    private func selfChecks() -> [Check] {
        let s = store.settings
        let ago: (Date?) -> String = { $0.map { "，\($0.formatted(.relative(presentation: .named)))" } ?? "" }
        var list: [Check] = []

        if s.sourceURL.isEmpty {
            list.append(Check(name: "值班网站", status: .fail, detail: "还没填排班网址（设置 › 账号与同步）"))
        } else {
            let fresh = s.lastSync.map { Date().timeIntervalSince($0) < 86_400 } ?? false
            let status: Check.Status = s.syncState == .ok ? (fresh ? .ok : .warn) : (s.syncState == nil ? .warn : .fail)
            let when = s.lastSync.map { $0.formatted(.relative(presentation: .named)) } ?? "从没成功过"
            list.append(Check(name: "值班网站", status: status,
                              detail: (s.lastSyncMessage ?? "还没同步过") + "（上次成功：\(when)）"))
        }
        let woke = s.lastBackgroundWake.map { Date().timeIntervalSince($0) < 6 * 3600 } ?? false
        list.append(Check(name: "后台自动同步", status: woke ? .ok : .warn,
                          detail: woke ? "系统按时在后台唤醒" + ago(s.lastBackgroundWake)
                                       : "6 小时内没在后台同步过：打开「后台 App 刷新」，或者按设置里「自动同步设置向导」加个快捷指令"))
        list.append(Check(name: "全员排班", status: store.roster.isEmpty ? .warn : .ok,
                          detail: store.roster.isEmpty ? "还没读到全员排班（找人换班、工作量要用）" : rosterSummary))

        let link = s.meetingDocURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if link.isEmpty {
            list.append(Check(name: "周会文档", status: .off, detail: "没设置（今天页「周会问题」里导入）"))
        } else {
            let recent = s.meetingLastImport.map { Date().timeIntervalSince($0) < 8 * 86_400 } ?? false
            list.append(Check(name: "周会文档", status: recent ? .ok : .warn,
                              detail: s.meetingMessage ?? (recent ? "这周读到过" : "一周多没读到新的一版")))
            if URL(string: link).map(DocDownload.isSupported) == true {
                let last = s.meetingDownloadLog.last ?? ""
                list.append(Check(name: "周会表格自动下载",
                                  status: s.meetingDownloadLog.isEmpty ? .warn : (last.hasPrefix("✗") ? .fail : .ok),
                                  detail: s.meetingDownloadLog.isEmpty ? "还没自动下载过" : last))
            }
        }
        if !store.meetingWritebackReady {
            list.append(Check(name: "写回金山文档", status: .off, detail: "没设置（周会问题 › 导入 › 写回金山文档）"))
        } else {
            let last = s.meetingWriteLog.first(where: { $0.hasPrefix("✓") || $0.hasPrefix("✗") })
            list.append(Check(name: "写回金山文档", status: last?.hasPrefix("✗") == true ? .fail : .ok,
                              detail: last ?? "设置好了，还没写过"))
        }
        if s.weChatEnabled {
            let hasToken = !(Keychain.get(.pushPlusToken) ?? "").isEmpty
            let failed = s.weChatMessage?.contains("失败") == true
            list.append(Check(name: "微信推送", status: !hasToken || failed ? .fail : .ok,
                              detail: !hasToken ? "没填 token" : (s.weChatMessage ?? "开着")))
        }
        if let n = notifications {
            list.append(Check(name: "提醒", status: !n.allowed ? .fail : (n.pending > 0 ? .ok : .warn),
                              detail: !n.allowed ? "通知被关了：设置 › 通知 › 值班提醒"
                                                 : (n.pending > 0 ? "已登记 \(n.pending) 条提醒" : "通知开着，但没有登记的提醒（排班同步过来后会有）")))
        }
        let widget = WidgetStore.load()
        list.append(Check(name: "小组件", status: widget == nil ? .fail : .ok,
                          detail: widget.map { "数据更新于 \($0.updated.formatted(date: .omitted, time: .shortened))" } ?? "读不到小组件数据（App Group 没生效）"))
        return list.map { tested[$0.name] ?? $0 }
    }

    /// 当场测一遍：同步网站、下载周会表格、测写回脚本、看通知权限
    private func runChecks() async {
        tested = [:]
        checking = "值班网站"
        let ok = await store.sync(full: false, userInitiated: true, source: "自检")
        tested["值班网站"] = Check(name: "值班网站", status: ok ? .ok : .fail,
                                    detail: (ok ? "刚才同步成功：" : "刚才同步失败：") + (store.settings.lastSyncMessage ?? ""))
        let link = store.settings.meetingDocURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: link), DocDownload.isSupported(url) {
            checking = "周会表格自动下载"
            let r = await store.downloadMeeting(link: url)
            tested["周会表格自动下载"] = Check(name: "周会表格自动下载", status: r.ok ? .ok : .fail,
                                                detail: (r.ok ? "刚才下载成功：" : "刚才下载失败：") + r.message)
        }
        if store.meetingWritebackReady {
            checking = "写回金山文档"
            let r = await store.testMeetingScript()
            tested["写回金山文档"] = Check(name: "写回金山文档", status: r.ok ? .ok : .fail, detail: "刚才测试：" + r.message)
        }
        checking = "提醒"
        let auth = await NotificationService.authorizationStatus()
        let allowed = [.authorized, .provisional, .ephemeral].contains(auth)
        tested["提醒"] = Check(name: "提醒", status: allowed ? .ok : .fail,
                              detail: allowed ? "通知权限已允许" : "通知被关了：设置 › 通知 › 值班提醒")
        checking = nil
        await load()
    }

    private var rosterSummary: String {
        let days = Set(store.roster.values.flatMap(\.keys))
        guard let lo = days.min(), let hi = days.max() else { return "没有（同步时没读到「值班查看」）" }
        return "\(store.roster.count) 人，\(days.count) 天（\(lo.dateText) – \(hi.dateText)）"
    }

    private func load() async {
        let s = store.settings
        let app = UIApplication.shared
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
        let auth = await NotificationService.authorizationStatus()
        let pending = await NotificationService.pendingCount()
        notifications = ([.authorized, .provisional, .ephemeral].contains(auth), pending)
        let next = await NotificationService.nextReminder()
        let widget = WidgetStore.load()
        let hasPassword = !(Keychain.get(.sourcePassword) ?? "").isEmpty
        let hasToken = !(Keychain.get(.pushPlusToken) ?? "").isEmpty
        let fmt: (Date) -> String = { $0.formatted(date: .abbreviated, time: .shortened) }
        let today = store.shift(on: .today).map(store.matcher.displayName) ?? "未排班"

        var appRows = [Row(label: "版本", value: version, ok: nil)]
        let days = SigningInfo.daysLeft
        appRows.append(Row(label: "签名到期", value: SigningInfo.expiryText, ok: days.map { $0 >= 2 }))
        let refresh: (String, Bool) = {
            switch app.backgroundRefreshStatus {
            case .available: return ("已开启", true)
            case .denied: return ("已关闭（设置 › 通用 › 后台 App 刷新）", false)
            default: return ("受限制", false)
            }
        }()
        appRows.append(Row(label: "后台 App 刷新", value: refresh.0, ok: refresh.1))
        // 主屏幕图标：现在是哪个、今天应该是哪个（只有 App 打开着时能换）
        let wantedIcon = store.wantedAppIcon
        appRows.append(Row(label: "主屏幕图标",
                           value: "现在「\(AppStore.iconTitle(app.alternateIconName))」，今天应该「\(AppStore.iconTitle(wantedIcon))」"
                               + (store.appIconError.map { "；上次没换成：\($0)" } ?? ""),
                           ok: app.alternateIconName == wantedIcon))

        let syncRows = [
            Row(label: "排班网址", value: s.sourceURL.isEmpty ? "未设置" : "已设置", ok: !s.sourceURL.isEmpty),
            Row(label: "账号 / 密码", value: "\(s.sourceUsername.isEmpty ? "无账号" : "有账号") / \(hasPassword ? "有密码" : "无密码")",
                ok: !s.sourceUsername.isEmpty && hasPassword),
            Row(label: "上次成功同步", value: s.lastSync.map(fmt) ?? "从未", ok: s.lastSync.map { Date().timeIntervalSince($0) < 86_400 }),
            Row(label: "最近结果", value: s.lastSyncMessage ?? "—", ok: s.syncState.map { $0 == .ok }),
            Row(label: "已有排班", value: "\(store.schedule.count) 天，今天：\(today)", ok: !store.schedule.isEmpty),
            Row(label: "数据接口", value: s.apiSignature.map { "已识别：\($0.split(separator: "/").last.map(String.init) ?? $0)" }
                ?? "未识别（读网页内容，只有本周）", ok: s.apiSignature != nil),
            Row(label: "排班最远到", value: store.schedule.keys.max()?.dateText ?? "—", ok: nil),
            Row(label: "上次成功结果", value: s.lastSuccessMessage ?? "—", ok: nil),
            Row(label: "全员排班", value: rosterSummary, ok: !store.roster.isEmpty),
            Row(label: "节假日安排", value: ChinaHolidays.knownYears.contains(DayKey.today.year)
                ? "已有 \(DayKey.today.year) 年" : "缺 \(DayKey.today.year) 年的法定节假日，工作量统计会把假期算成工作日，请更新 App",
                ok: ChinaHolidays.knownYears.contains(DayKey.today.year)),
        ]

        let authText: (String, Bool) = {
            switch auth {
            case .authorized, .provisional, .ephemeral: return ("已允许", true)
            case .denied: return ("已关闭（设置 › 通知 › 值班提醒）", false)
            default: return ("未询问", false)
            }
        }()
        let reminderRows = [
            Row(label: "通知权限", value: authText.0, ok: authText.1),
            Row(label: "已登记提醒", value: "\(pending) 条", ok: pending > 0),
            Row(label: "下一条", value: next.map { "\(fmt($0.date)) \($0.title)" } ?? "无", ok: next != nil),
            Row(label: "语音播报", value: s.voiceEnabled ? "开" : "关", ok: nil),
            Row(label: "网站一般排班时间", value: PublishPattern.describe(s.publishTimes, calendar: .app) ?? "还在学（发现新排班 \(s.publishTimes.count) 次）",
                ok: nil),
            Row(label: "排班变动记录", value: "\(store.rosterLog.count) 条", ok: nil),
            Row(label: "网站改版自检", value: s.syncHealthWarning ?? "正常（已记 \(s.syncHealth.values.map(\.count).reduce(0, +)) 次）",
                ok: s.syncHealthWarning == nil),
            Row(label: "同步到日历", value: s.calendarSync
                    ? (!CalendarSync.authorized ? "开，但没有日历权限" : (CalendarSync.lastError ?? "开"))
                    : "关",
                ok: s.calendarSync ? (CalendarSync.authorized && CalendarSync.lastError == nil) : nil),
        ]

        let widgetRows = [
            Row(label: "小组件数据", value: widget.map { "\($0.days.count) 天，更新于 \(fmt($0.updated))" } ?? "读不到（App Group 未生效）",
                ok: widget != nil),
            Row(label: "App Group", value: WidgetStore.groupID, ok: nil),
            Row(label: "当前图标", value: app.alternateIconName ?? "默认（值）", ok: nil),
        ]

        var weChatRows = [Row(label: "微信推送", value: s.weChatEnabled ? "开" : "关", ok: nil)]
        if s.weChatEnabled {
            weChatRows.append(Row(label: "token", value: hasToken ? "已填写" : "未填写", ok: hasToken))
            weChatRows.append(Row(label: "最近结果", value: s.weChatMessage ?? "—",
                                  ok: s.weChatMessage.map { !$0.contains("失败") }))
        }

        // 后台同步到底有没有跑：系统多久唤醒一次、最近每次同步的结果
        let dayAgo = Date().addingTimeInterval(-86_400)
        let backgroundRuns = s.syncLog.filter { $0.date > dayAgo && ($0.source.hasPrefix("后台") || $0.source.hasPrefix("快捷指令")) }
        var logRows = [
            Row(label: "上次后台唤醒", value: s.lastBackgroundWake.map(fmt) ?? "从未",
                ok: s.lastBackgroundWake.map { Date().timeIntervalSince($0) < 6 * 3600 }),
            Row(label: "24 小时内后台/快捷指令同步", value: "\(backgroundRuns.count) 次", ok: !backgroundRuns.isEmpty),
        ]
        logRows += s.syncLog.prefix(15).map { e in
            Row(label: "\(e.date.formatted(date: .numeric, time: .shortened)) \(e.source)",
                value: "\(e.message.isEmpty ? (e.ok ? "成功" : "失败") : e.message)（\(e.seconds) 秒）", ok: e.ok)
        }

        sections = [
            Section(title: "App", rows: appRows),
            Section(title: "排班同步", rows: syncRows),
            Section(title: "最近同步记录（新的在前）", rows: logRows),
            Section(title: "提醒", rows: reminderRows),
            Section(title: "小组件 / 图标", rows: widgetRows),
            Section(title: "微信", rows: weChatRows),
        ]
        copied = false
    }
}
