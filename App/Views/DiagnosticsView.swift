import SwiftUI
import UserNotifications

/// 一页看清 App 的状态：出问题时截这一页的图就能知道卡在哪一步。
struct DiagnosticsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var sections: [Section] = []
    @State private var copied = false

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
        List {
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
        .navigationTitle("诊断")
        .task { await load() }
    }

    private func load() async {
        let s = store.settings
        let app = UIApplication.shared
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
        let auth = await NotificationService.authorizationStatus()
        let pending = await NotificationService.pendingCount()
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

        let syncRows = [
            Row(label: "排班网址", value: s.sourceURL.isEmpty ? "未设置" : "已设置", ok: !s.sourceURL.isEmpty),
            Row(label: "账号 / 密码", value: "\(s.sourceUsername.isEmpty ? "无账号" : "有账号") / \(hasPassword ? "有密码" : "无密码")",
                ok: !s.sourceUsername.isEmpty && hasPassword),
            Row(label: "上次成功同步", value: s.lastSync.map(fmt) ?? "从未", ok: s.lastSync.map { Date().timeIntervalSince($0) < 86_400 }),
            Row(label: "最近结果", value: s.lastSyncMessage ?? "—", ok: s.lastSyncMessage.map { $0.hasPrefix("同步成功") }),
            Row(label: "已有排班", value: "\(store.schedule.count) 天，今天：\(today)", ok: !store.schedule.isEmpty),
            Row(label: "数据接口", value: s.apiSignature.map { "已识别：\($0.split(separator: "/").last.map(String.init) ?? $0)" }
                ?? "未识别（读网页内容，只有本周）", ok: s.apiSignature != nil),
            Row(label: "排班最远到", value: store.schedule.keys.max()?.dateText ?? "—", ok: nil),
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

        sections = [
            Section(title: "App", rows: appRows),
            Section(title: "排班同步", rows: syncRows),
            Section(title: "提醒", rows: reminderRows),
            Section(title: "小组件 / 图标", rows: widgetRows),
            Section(title: "微信", rows: weChatRows),
        ]
        copied = false
    }
}
