import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var aliasText = ""
    @State private var password = ""
    @State private var pushToken = ""
    @State private var sendingWeChatTest = false
    @State private var showingWebLogin = false
    @State private var confirmClear = false
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount = 0
    @State private var calendarMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        Form { sourceSection; nameSection }.navigationTitle("账号与同步")
                    } label: {
                        row("账号与同步", icon: "arrow.triangle.2.circlepath", detail: syncSummary)
                    }
                    NavigationLink {
                        Form { reminderSection; calendarSection }.navigationTitle("提醒")
                    } label: {
                        row("提醒", icon: "bell", detail: reminderSummary)
                    }
                    NavigationLink {
                        Form { weChatSection }.navigationTitle("微信推送")
                    } label: {
                        row("微信推送", icon: "message", detail: store.settings.weChatEnabled ? "已开启" : "未开启")
                    }
                    NavigationLink {
                        Form { displaySection }.navigationTitle("显示")
                    } label: {
                        row("显示", icon: "paintpalette", detail: store.settings.appearance.title)
                    }
                    NavigationLink {
                        ImportView()
                    } label: {
                        row("导入排班表", icon: "square.and.arrow.down", detail: "粘贴 / 文件")
                    }
                }
                Section {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        row("诊断", icon: "stethoscope", detail: "出问题时看这里")
                    }
                    Button("清空所有排班", role: .destructive) { confirmClear = true }
                }
            }
            .navigationTitle("设置")
            .onAppear {
                aliasText = store.settings.aliases.joined(separator: ", ")
                password = Keychain.get(.sourcePassword) ?? ""
                pushToken = Keychain.get(.pushPlusToken) ?? ""
            }
            .task(id: scenePhase) { await refreshStatus() }
            .confirmationDialog("确定清空所有排班吗？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) { store.clearSchedule() }
            }
            .fullScreenCover(isPresented: $showingWebLogin) {
                WebLoginView()
            }
        }
    }

    private func row(_ title: String, icon: String, detail: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var syncSummary: String {
        if store.settings.sourceURL.isEmpty { return "未设置" }
        guard let last = store.settings.lastSync else { return "未同步" }
        return "同步于 " + last.formatted(date: .omitted, time: .shortened)
    }

    private var reminderSummary: String {
        let s = store.settings
        let times = [s.morningEnabled ? s.morning.text : nil, s.eveningEnabled ? s.evening.text : nil].compactMap { $0 }
        return times.isEmpty ? "已关闭" : times.joined(separator: " / ")
    }

    private var displaySection: some View {
        Section {
            NavigationLink {
                ShiftTypesView()
            } label: {
                Label("班次类型与颜色", systemImage: "paintpalette")
            }
            NavigationLink {
                GroupNotesView()
            } label: {
                Label("各组工作内容", systemImage: "list.bullet.rectangle")
            }
            Toggle("图标显示今天的组", isOn: $store.settings.dynamicIcon)
                .onChange(of: store.settings.dynamicIcon) { _ in store.updateAppIcon() }
            Picker("外观", selection: $store.settings.appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
        } footer: {
            Text("图标只能在打开 App 时更换，每次更换系统会弹出提示；想不打开 App 也每天更新，用主屏幕小组件「今日班组」。")
        }
    }

    private var calendarSection: some View {
        Section {
            Toggle("同步到 iPhone 日历", isOn: Binding(
                get: { store.settings.calendarSync },
                set: { on in
                    Task {
                        if on {
                            guard await CalendarSync.requestAccess() else {
                                calendarMessage = "没有日历权限：请到「设置 › 隐私与安全性 › 日历 › 值班提醒」选「完全访问」"
                                return
                            }
                            calendarMessage = nil
                            store.settings.calendarSync = true
                            CalendarSync.sync(store.schedule, matcher: store.matcher)
                        } else {
                            store.settings.calendarSync = false
                            CalendarSync.removeCalendar()
                        }
                    }
                }))
            if let calendarMessage {
                Text(calendarMessage).font(.footnote).foregroundStyle(.orange)
            }
        } footer: {
            Text("在系统「日历」App 里新建一个「值班提醒」日历，每天一个全天事件（如「组D」），Apple Watch 上也能看到。只改动这个日历，关掉开关会删除它。")
        }
    }

    private var nameSection: some View {
        Section {
            TextField("例如：张三, zhangsan", text: $aliasText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: aliasText) { text in
                    store.settings.aliases = text
                        .components(separatedBy: CharacterSet(charactersIn: ",，、/;；\n"))
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
        } header: {
            Text("我的名字")
        } footer: {
            Text("多人排班表里用这些名字找到你，多个写法用逗号分开（中文名、拼音、工号都可以）。")
        }
    }

    private var reminderSection: some View {
        Section {
            if authStatus == .denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label("通知已关闭，点这里去系统设置打开", systemImage: "bell.slash")
                        .foregroundStyle(.red)
                }
            }
            Toggle("早上提醒今天的班", isOn: $store.settings.morningEnabled)
            if store.settings.morningEnabled {
                DatePicker("提醒时间", selection: time(\.morning), displayedComponents: .hourAndMinute)
            }
            Toggle("晚上提醒明天的班", isOn: $store.settings.eveningEnabled)
            if store.settings.eveningEnabled {
                DatePicker("提醒时间", selection: time(\.evening), displayedComponents: .hourAndMinute)
            }
            Toggle("没排班的日子也提醒", isOn: $store.settings.notifyWhenEmpty)
            Toggle("到点语音播报", isOn: $store.settings.voiceEnabled)
            if store.settings.voiceEnabled {
                Button("试听") {
                    let name = ShiftDisplay(raw: store.shift(on: .today), matcher: store.matcher)?.name ?? "未排班"
                    VoiceSound.speakNow("今天，\(name.replacingOccurrences(of: "+", with: "和"))")
                }
            }
            Button("发送一条测试通知") {
                Task {
                    await NotificationService.requestAuthorization()
                    let today = DayKey.today
                    let name = ShiftDisplay(raw: store.shift(on: today), matcher: store.matcher)
                    await NotificationService.sendTest(title: "\(name.map { $0.emoji + " " } ?? "")今天：\(name?.name ?? "未排班")",
                                                       body: "这是一条测试通知，3 秒后出现")
                    await refreshStatus()
                }
            }
        } header: {
            Text("推送提醒")
        } footer: {
            Text("已登记 \(pendingCount) 条提醒（最多提前登记约 30 天）。提醒由系统准时弹出，不需要打开 App；每次打开 App 或同步后会自动续上。\n语音播报是通知的铃声：手机静音（侧边静音键）或开了专注模式时不会出声。")
        }
    }

    private var weChatSection: some View {
        Section {
            Toggle("推送到微信", isOn: $store.settings.weChatEnabled)
            if store.settings.weChatEnabled {
                SecureField("PushPlus token", text: $pushToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: pushToken) { Keychain.set($0.trimmingCharacters(in: .whitespacesAndNewlines), for: .pushPlusToken) }
                Toggle("每天的提醒也发到微信", isOn: $store.settings.weChatDaily)
                Toggle("排班变动也发到微信", isOn: $store.settings.weChatChanges)
                Button {
                    sendingWeChatTest = true
                    Task {
                        let today = DayKey.today
                        let name = ShiftDisplay(raw: store.shift(on: today), matcher: store.matcher)
                        await store.pushToWeChat(title: "\(name.map { $0.emoji + " " } ?? "")今天：\(name?.name ?? "未排班")",
                                                 content: "这是一条来自「值班提醒」的测试消息", force: true)
                        sendingWeChatTest = false
                    }
                } label: {
                    HStack {
                        Text("发送一条测试消息到微信")
                        if sendingWeChatTest { Spacer(); ProgressView() }
                    }
                }
                .disabled(pushToken.isEmpty || sendingWeChatTest)
                if let message = store.settings.weChatMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("微信推送")
        } footer: {
            Text("""
            在电脑或手机浏览器打开 pushplus.plus，用微信扫码登录并关注公众号，复制「一对一推送」里的 token 填到这里。
            排班变动、登录过期会立即发到微信。
            每天准点发微信：打开「快捷指令」App › 自动化 › 新建 › 特定时间（如 7:30，每天，选「立即运行」）› 添加操作，搜索「值班提醒」，选「发送值班提醒到微信」，哪天选「今天」；20:30 再建一个，选「明天」。
            没设自动化时，App 会在有机会运行时补发，可能比准点晚。
            只发送你自己的分工，不发送网页上的其它内容。
            """)
        }
    }

    private var sourceSection: some View {
        Section {
            Button {
                showingWebLogin = true
            } label: {
                Label("① 登录值班网站，打开排班页面", systemImage: "globe")
            }
            TextField("② 排班页面网址（在网页里点「设为同步地址」自动填入）", text: $store.settings.sourceURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("值班网站账号", text: $store.settings.sourceUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("值班网站密码（保存在钥匙串）", text: $password)
                .onChange(of: password) {
                    Keychain.set($0, for: .sourcePassword)
                    store.settings.loginExpiredNotified = false   // 改了密码，允许重新自动登录
                }
            Toggle("用内置浏览器同步（沿用登录状态）", isOn: $store.settings.syncViaWeb)
            Toggle("排班有变动时通知我", isOn: $store.settings.notifyChanges)
            Button {
                Task { await store.sync(userInitiated: true) }
            } label: {
                HStack {
                    Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                    if store.isSyncing { Spacer(); ProgressView() }
                }
            }
            .disabled(!store.canSync || store.isSyncing)
            if let message = store.settings.lastSyncMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("自动同步")
        } footer: {
            Text("""
            填好排班页面网址和账号密码就行，不用手动同步：打开 App、下拉刷新、iPhone 后台空闲时都会自动取最新排班，登录过期会自动重新登录，发现变动立即通知你。
            网址可以在「① 登录值班网站」里进到排班页面后点「设为同步地址」自动填入。网站要图形验证码时没法自动登录，会通知你手动登录一次。
            如果网址是 CSV / ICS 日历订阅文件，可以关掉「用内置浏览器同步」。
            """)
        }
    }

    private func time(_ keyPath: WritableKeyPath<AppSettings, ClockTime>) -> Binding<Date> {
        Binding {
            let t = store.settings[keyPath: keyPath]
            return Calendar.app.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: t.hour, minute: t.minute)) ?? Date()
        } set: { date in
            let c = Calendar.app.dateComponents([.hour, .minute], from: date)
            store.settings[keyPath: keyPath] = ClockTime(hour: c.hour ?? 0, minute: c.minute ?? 0)
        }
    }

    private func refreshStatus() async {
        authStatus = await NotificationService.authorizationStatus()
        // 等重新登记完成再统计
        try? await Task.sleep(nanoseconds: 500_000_000)
        pendingCount = await NotificationService.pendingCount()
    }
}

struct ShiftTypesView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List {
            Section {
                ForEach($store.settings.shiftTypes) { $type in
                    NavigationLink {
                        ShiftTypeEditor(type: $type)
                    } label: {
                        HStack {
                            Circle().fill(Color(hex: type.colorHex)).frame(width: 14, height: 14)
                            Text("\(type.emoji) \(type.name)")
                            Spacer()
                            Text((type.keywords + type.codes).joined(separator: " "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .onDelete { store.settings.shiftTypes.remove(atOffsets: $0) }
                .onMove { store.settings.shiftTypes.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text("排班表里的文字只要包含「关键字」（或完全等于「代码」）就会显示成对应的班次和颜色。")
            }
            Section {
                Button("添加班次类型") {
                    store.settings.shiftTypes.append(ShiftType(name: "新班次", emoji: "📌", colorHex: "#8E8E93"))
                }
                Button("恢复默认") { store.settings.shiftTypes = ShiftType.defaults }
            }
        }
        .navigationTitle("班次类型")
        .toolbar { EditButton() }
    }
}

private struct ShiftTypeEditor: View {
    @Binding var type: ShiftType
    @State private var keywords = ""
    @State private var codes = ""

    var body: some View {
        Form {
            Section("名称") {
                TextField("名称", text: $type.name)
                TextField("图标（emoji）", text: $type.emoji)
                ColorPicker("颜色", selection: Binding(get: { Color(hex: type.colorHex) },
                                                     set: { type.colorHex = $0.hexString }),
                            supportsOpacity: false)
            }
            Section {
                TextField("例如：白, 早, day", text: $keywords)
                    .onChange(of: keywords) { type.keywords = Self.split($0) }
            } header: {
                Text("关键字")
            } footer: {
                Text("排班文字包含任意一个就算这个班次。")
            }
            Section {
                TextField("例如：D, A", text: $codes)
                    .textInputAutocapitalization(.characters)
                    .onChange(of: codes) { type.codes = Self.split($0) }
            } header: {
                Text("代码")
            } footer: {
                Text("排班文字完全等于其中一个才算，适合 D / N 这样的单字母。")
            }
        }
        .navigationTitle(type.name)
        .onAppear {
            keywords = type.keywords.joined(separator: ", ")
            codes = type.codes.joined(separator: ", ")
        }
    }

    static func split(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet(charactersIn: ",，、;；"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// 各组工作内容：同步时从网页读到的会自动填上；也可以自己改，改过的优先显示。
struct GroupNotesView: View {
    @EnvironmentObject private var store: AppStore

    private var groups: [String] {
        let fromSchedule = store.schedule.values.flatMap { store.matcher.displayName($0).split(separator: "+").map(String.init) }
            .filter { $0.hasPrefix("组") }
        let all = Set(fromSchedule + ["组A", "组B", "组C", "组D", "组E"])
            .union(store.settings.autoGroupNotes.keys)
            .union(store.settings.manualGroupNotes.keys)
        return all.sorted()
    }

    var body: some View {
        Form {
            ForEach(groups, id: \.self) { group in
                Section {
                    TextField(store.settings.autoGroupNotes[group] ?? "例如：负责设备巡检和日志记录",
                              text: Binding(
                                get: { store.settings.manualGroupNotes[group] ?? store.settings.autoGroupNotes[group] ?? "" },
                                set: { store.settings.manualGroupNotes[group] = $0.isEmpty ? nil : $0 }),
                              axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text(group)
                } footer: {
                    if store.settings.autoGroupNotes[group] != nil {
                        Text(store.settings.manualGroupNotes[group] == nil ? "从网页读到" : "已手动修改（清空后恢复网页上的说明）")
                    }
                }
            }
        }
        .navigationTitle("各组工作内容")
        .onDisappear { Task { await store.rescheduleNotifications() } }
    }
}
