import AVFoundation
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
    @State private var syncingName = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { RoleView() } label: {
                        row("身份", icon: store.role.symbol, detail: store.role.title)
                    }
                    Button {
                        store.settings.onboardingDone = false
                    } label: {
                        row("设置向导", icon: "wand.and.rays", detail: "一步步重新设置一遍")
                    }
                    .foregroundStyle(.primary)
                }
                Section {
                    NavigationLink {
                        Form { sourceSection; nameSection }.appList().navigationTitle("账号与同步")
                    } label: {
                        row("账号与同步", icon: "arrow.triangle.2.circlepath", detail: syncSummary)
                    }
                    NavigationLink {
                        Form { reminderSection; calendarSection }.appList().navigationTitle("提醒")
                    } label: {
                        row("提醒", icon: "bell", detail: reminderSummary)
                    }
                    NavigationLink {
                        Form { weChatSection }.appList().navigationTitle("微信推送")
                    } label: {
                        row("微信推送", icon: "message", detail: store.settings.weChatEnabled ? "已开启" : "未开启")
                    }
                    NavigationLink {
                        GroupNotesView()
                    } label: {
                        row("各组工作内容", icon: "list.bullet.rectangle", detail: groupNotesSummary)
                    }
                    NavigationLink {
                        AutomationGuideView()
                    } label: {
                        row("自动同步设置向导", icon: "wand.and.stars",
                            detail: store.automationLooksMissing ? "还没设置" : "已在运行")
                    }
                    NavigationLink {
                        SwapLedgerView()
                    } label: {
                        row("换班账本", icon: "book.closed", detail: ledgerSummary)
                    }
                    NavigationLink {
                        HolidaysView()
                    } label: {
                        row("法定节假日", icon: "calendar.badge.exclamationmark",
                            detail: ChinaHolidays.knownYears.sorted().map(String.init).joined(separator: "、"))
                    }
                    NavigationLink {
                        Form { displaySection }.appList().navigationTitle("显示")
                    } label: {
                        row("显示", icon: "paintpalette", detail: store.settings.appearance == .system && store.settings.accentTheme == .system
                            ? "跟随系统" : "\(store.settings.appearance.title) · \(store.settings.accentTheme.title)")
                    }
                    NavigationLink {
                        ImportView()
                    } label: {
                        row("导入排班表", icon: "square.and.arrow.down", detail: "粘贴 / 文件")
                    }
                    NavigationLink {
                        BackupView()
                    } label: {
                        row("备份与恢复", icon: "externaldrive", detail: "换手机 / 重装用")
                    }
                }
                Section {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        row("诊断", icon: "stethoscope", detail: "出问题时看这里")
                    }
                    if store.canEdit {
                        Button("清空所有排班", role: .destructive) { confirmClear = true }
                    }
                }
            }
            .appList()
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

    /// 统一的单色玻璃图标 + 标题 + 右边的状态
    private func row(_ title: String, icon: String, detail: String) -> some View {
        HStack(spacing: DS.Space.s) {
            IconBadge(icon: icon, size: 30)
            Text(title).font(DS.Font.body)
            Spacer()
            Text(detail).font(DS.Font.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, DS.Space.xxs)
    }


    private var syncSummary: String {
        if store.settings.sourceURL.isEmpty { return "未设置" }
        guard let last = store.settings.lastSync else { return "未同步" }
        return "同步于 " + last.formatted(date: .omitted, time: .shortened)
    }

    private var ledgerSummary: String {
        let open = SwapLedger.balances(store.settings.swapRecords).filter { $0.value != 0 }
        return open.isEmpty ? "两清" : "\(open.count) 人没还清"
    }

    private var groupNotesSummary: String {
        if let date = store.settings.lastDesktopNotesFetch, !store.settings.desktopGroupNotes.isEmpty {
            return "电脑版 · " + date.formatted(date: .numeric, time: .shortened)
        }
        return store.settings.manualGroupNotes.isEmpty ? "未读到" : "自己填写"
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
            Toggle("图标显示今天的班（遥、A–E、调、差、休）", isOn: $store.settings.dynamicIcon)
                .onChange(of: store.settings.dynamicIcon) { _ in store.updateAppIcon() }
            Picker("外观", selection: $store.settings.appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack {
                    Text("主题色")
                    Spacer()
                    Text(store.settings.accentTheme.title).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s) {
                        ForEach(AccentTheme.allCases) { theme in
                            Button {
                                Haptics.select()
                                withAnimation(DS.Motion.spring) { store.settings.accentTheme = theme }
                            } label: {
                                ZStack {
                                    Circle().fill(theme.color).frame(width: 34, height: 34)
                                    if theme == .system {
                                        Image(systemName: "iphone").font(.caption.bold()).foregroundStyle(.white)
                                    }
                                    if store.settings.accentTheme == theme {
                                        Circle().strokeBorder(theme.color, lineWidth: 2).frame(width: 44, height: 44)
                                    }
                                }
                                .frame(width: 46, height: 46)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel(theme.title)
                        }
                    }
                }
            }
            .padding(.vertical, DS.Space.xxs)
        } footer: {
            Text("外观（浅色 / 深色）和主题色默认都跟随系统：系统切换深色模式时 App 一起变，主题色用系统蓝。也可以固定成喜欢的颜色。\n图标只能在打开 App 时更换，每次更换系统会弹出提示；想不打开 App 也每天更新，用主屏幕小组件「今日班组」。")
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
            if store.settings.calendarSync, let error = CalendarSync.lastError {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
            if let calendarMessage {
                Text(calendarMessage).font(.footnote).foregroundStyle(.orange)
            }
        } footer: {
            Text("在系统「日历」App 里新建一个「值班提醒」日历，每天一个全天事件（如「组D」），Apple Watch 上也能看到。只改动这个日历，关掉开关会删除它。")
        }
    }

    private static func names(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",，、/;；\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var nameSection: some View {
        Section {
            TextField("例如：张三, zhangsan", text: $aliasText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: aliasText) { text in
                    let names = Self.names(in: text)
                    if names != store.settings.aliases { store.settings.aliases = names }
                }
                // 在别处（首次设置、今天页「我是谁」）换了人：这里跟着显示新名字，不把旧名字写回去
                .onChange(of: store.settings.aliases) { names in
                    if Self.names(in: aliasText) != names { aliasText = names.joined(separator: ", ") }
                }
            NavigationLink {
                WhoAmIView { aliasText = $0 }
            } label: {
                Label("从全员名单里选我是谁", systemImage: "person.crop.circle.badge.checkmark")
            }
            Button {
                syncingName = true
                Task { @MainActor in
                    let ok = await store.sync(userInitiated: true, source: "改名字后同步")
                    syncingName = false
                    ToastCenter.shared.show(store.settings.lastSyncMessage ?? (ok ? "已同步" : "同步失败"), style: ok ? .success : .error)
                }
            } label: {
                HStack {
                    Label("用这个名字同步", systemImage: "arrow.triangle.2.circlepath")
                    if syncingName || store.isSyncing { Spacer(); DSSpinner() }
                }
            }
            .disabled(!store.canSync || syncingName || store.isSyncing || store.settings.aliases.isEmpty)
            if let me = store.myRosterName {
                Label("全员排班里认出你是：\(me)", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.footnote)
            } else if !store.settings.aliases.isEmpty && !store.roster.isEmpty {
                Label("全员排班里还没找到这个名字：检查写法，或者从名单里选", systemImage: "questionmark.circle")
                    .foregroundStyle(DS.Palette.warning).font(.footnote)
            }
        } header: {
            Text("我的名字")
        } footer: {
            Text("谁用这个 App，就把名字设成谁：多人排班表里用这些名字找到你，多个写法用逗号分开（中文名、拼音、工号都可以）。改完点「用这个名字同步」，提醒、统计、预测都会换成这个人的。")
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
            Toggle("网站排了班但没给我排的日子也提醒", isOn: $store.settings.remindUnassigned)
            Toggle("周日晚上预告下周安排", isOn: $store.settings.weeklyPreview)
            Toggle("值遥测时锁屏显示倒计时", isOn: $store.settings.liveActivity)
            Toggle("收藏的同事排班变了也通知我", isOn: $store.settings.notifyFavorites)
            Toggle("全员排班有变动也提醒我", isOn: $store.settings.notifyAllChanges)
            Toggle("到点语音播报", isOn: $store.settings.voiceEnabled)
            if store.settings.voiceEnabled {
                NavigationLink {
                    VoicePickerView()
                } label: {
                    LabeledContent("播报声音", value: VoiceSound.currentVoice.map { "\($0.name)（\(VoiceSound.qualityText($0))）" } ?? "系统默认")
                }
                Button("试听") {
                    VoiceSound.speakNow(VoicePickerView.sample(store))
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
                Toggle("每月 1 号发上个月的工作量月报", isOn: $store.settings.monthlyReport)
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
                        if sendingWeChatTest { Spacer(); DSSpinner() }
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
            下周预告：周日 20:30 再建一个自动化，同一个操作，哪天选「下周」。
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
                    if store.isSyncing { Spacer(); DSSpinner() }
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
            注意：iPhone 什么时候在后台运行 App 由系统决定，可能几个小时才一次；从多任务界面划掉 App、低电量模式、关掉「后台 App 刷新」时完全不会运行。想及时知道排班变动，在「快捷指令 › 自动化」里每隔两三个小时加一个「同步排班」（如 9:00、12:00、15:00、18:00），选「立即运行」。「设置 › 诊断」里能看到每次同步的记录。
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
                            Image(systemName: type.symbol).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: type.colorHex)).frame(width: 20)
                            Text(type.name)
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
        .appList()
        .adminOnly()
        .navigationTitle("班次类型")
        .toolbar { EditButton() }
        // 工具栏按钮也只有管理员能用
        .disabled(!store.canEdit)
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
        .appList()
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
    @State private var pasting = false
    @State private var pasteText = ""
    @State private var reading = false
    @State private var browsing = false

    private var groups: [String] {
        let fromSchedule = store.schedule.values.flatMap { store.matcher.displayName($0).split(separator: "+").map(String.init) }
            .filter { $0.hasPrefix("组") }
        let all = Set(fromSchedule + ["组A", "组B", "组C", "组D", "组E"])
            .union(store.settings.desktopGroupNotes.keys)
            .union(store.settings.autoGroupNotes.keys)
            .union(store.settings.manualGroupNotes.keys)
        return all.sorted()
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("上次读到", value: store.settings.lastDesktopNotesFetch
                    .map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "还没有")
                if let message = store.settings.desktopNotesMessage {
                    LabeledContent("最近结果", value: message)
                }
                if let message = store.settings.desktopRosterMessage {
                    LabeledContent("全员排班", value: message)
                }
                Button {
                    reading = true
                    Task {
                        await store.readDesktopNotes()
                        reading = false
                    }
                } label: {
                    HStack {
                        Text("现在从电脑版网页读取")
                        if reading || store.isReadingDesktop { Spacer(); DSSpinner() }
                    }
                }
                .disabled(reading || store.isReadingDesktop || !store.canSync)
                Button("自己打开电脑版网页读取") { browsing = true }
                    .disabled(!store.canSync)
                TextField(SyncService.desktopDutyURL(from: store.settings.sourceURL)?.absoluteString ?? "电脑版「值班查看」网址",
                          text: $store.settings.desktopNotesURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote)
                if let text = store.desktopPageText {
                    NavigationLink("查看 App 读到的页面内容") {
                        ScrollView {
                            Text(text)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .appList()
                        .navigationTitle("读到的页面")
                    }
                }
            } header: {
                Text("电脑版网页（优先）")
            } footer: {
                Text("每天第一次打开 App 同步时，自动用电脑版打开网站「值班查看」，读上面每组该干什么。读到的内容优先显示；网页上没有的组，才用下面自己填写的。\n自动读不到时，点「自己打开电脑版网页读取」，在网页里打开「值班查看」后点「读取本页」，App 会记住这个网址，以后每天自动从这里读。网址框留空就用同步网址的 #/duty。")
            }
            ForEach(groups, id: \.self) { group in
                let desktop = store.settings.desktopGroupNotes[group]
                Section {
                    if let desktop {
                        Text(desktop)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                    TextField(desktop == nil ? (store.settings.autoGroupNotes[group] ?? "例如：负责设备巡检和日志记录")
                                             : "备用：电脑版读不到时显示",
                              text: Binding(
                                get: { store.settings.manualGroupNotes[group] ?? "" },
                                set: { store.settings.manualGroupNotes[group] = $0.isEmpty ? nil : $0 }),
                              axis: .vertical)
                        .lineLimit(2...6)
                        .foregroundStyle(desktop == nil ? Color.primary : Color.secondary)
                } header: {
                    Text(group)
                } footer: {
                    if desktop != nil {
                        Text("来自电脑版网页")
                    } else if store.settings.manualGroupNotes[group] != nil {
                        Text("自己填写（电脑版网页上没读到这个组）")
                    } else if store.settings.autoGroupNotes[group] != nil {
                        Text("从其它页面读到")
                    }
                }
            }
        }
        .appList()
        .adminOnly()
        .navigationTitle("各组工作内容")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("一次粘贴") {
                    pasteText = UIPasteboard.general.string ?? ""
                    pasting = true
                }
            }
        }
        // 工具栏按钮也只有管理员能用
        .disabled(!store.canEdit)
        .fullScreenCover(isPresented: $browsing) { DesktopNotesBrowser() }
        .sheet(isPresented: $pasting) {
            NavigationStack {
                Form {
                    Section {
                        TextEditor(text: $pasteText)
                            .frame(minHeight: 320)
                    } footer: {
                        Text("每个组用「组A：」开头，下面几行都算这个组的内容，直到下一个「组B：」。会替换这些组现在的说明。")
                    }
                }
                .appList()
                .navigationTitle("粘贴各组工作内容")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { pasting = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            store.settings.manualGroupNotes.merge(GroupNotes.fromPaste(pasteText)) { _, n in n }
                            pasting = false
                        }
                        .disabled(GroupNotes.fromPaste(pasteText).isEmpty)
                    }
                }
            }
        }
        .onDisappear { Task { await store.rescheduleNotifications() } }
    }
}


/// 选播报用的声音和语速。手机上下载的「增强」「高级」中文声音比自带的标准声音自然得多。
struct VoicePickerView: View {
    @EnvironmentObject private var store: AppStore
    @State private var voices: [AVSpeechSynthesisVoice] = []

    static func sample(_ store: AppStore) -> String {
        let name = ShiftDisplay(raw: store.shift(on: .today), matcher: store.matcher)?.name ?? "未排班"
        return "今天，\(name.replacingOccurrences(of: "+", with: "和"))"
    }

    var body: some View {
        let selected = store.settings.voiceIdentifier
        List {
            Section {
                row(title: "自动（用手机上最好的）",
                    detail: VoiceSound.automaticVoice.map { "现在是 \($0.name) · \(VoiceSound.qualityText($0))" } ?? "",
                    checked: selected.isEmpty) {
                    store.settings.voiceIdentifier = ""
                    VoiceSound.speakNow(Self.sample(store), voice: VoiceSound.automaticVoice)
                }
                ForEach(voices, id: \.identifier) { voice in
                    row(title: voice.name,
                        detail: "\(VoiceSound.languageText(voice)) · \(VoiceSound.qualityText(voice))",
                        checked: selected == voice.identifier) {
                        store.settings.voiceIdentifier = voice.identifier
                        VoiceSound.speakNow(Self.sample(store), voice: voice)
                    }
                }
            } header: {
                Text("声音（点一下试听并选中）")
            }
            Section {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack {
                        Text("语速")
                        Spacer()
                        Text(rateText).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $store.settings.voiceRate, in: 0.35...0.6, step: 0.01) {
                        Text("语速")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    } onEditingChanged: { editing in
                        if !editing { VoiceSound.speakNow(Self.sample(store)) }
                    }
                }
            }
            Section {
                Text("自带的「标准」声音比较生硬。到 iPhone「设置 › 辅助功能 › 朗读内容 › 声音 › 中文」，下载名字后面标着「增强」或「高级」的声音（几十到几百 MB，建议连 Wi-Fi），下载完回到这里就能选。")
                    .font(.footnote)
                Button("打开 iPhone 设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } header: {
                Text("想要更好听的声音")
            } footer: {
                Text("换了声音或语速后，下一次提醒就会用新的声音。")
            }
        }
        .appList()
        .navigationTitle("播报声音")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { voices = VoiceSound.chineseVoices }
        // 从系统设置下载完声音回来时刷新列表
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            voices = VoiceSound.chineseVoices
        }
    }

    private var rateText: String {
        let r = store.settings.voiceRate
        return r < 0.43 ? "慢" : (r > 0.52 ? "快" : "适中")
    }

    private func row(title: String, detail: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color.primary)
                    if !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if checked {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
    }
}


/// 从全员排班的名单里点一下，把这个 App 设成这个人用
struct WhoAmIView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var onPick: (String) -> Void = { _ in }

    var body: some View {
        let zh = Locale(identifier: "zh_CN")
        let today = DayKey.today
        let names = store.roster.keys
            .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
            .sorted { $0.compare($1, locale: zh) == .orderedAscending }
        List {
            if store.roster.isEmpty {
                Section {
                    Text("还没有全员名单。先在「账号与同步」里填好网址和账号，同步一次就能在这里选。")
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await store.sync(userInitiated: true, source: "选我是谁") }
                    } label: {
                        HStack {
                            Label("现在同步", systemImage: "arrow.triangle.2.circlepath")
                            if store.isSyncing { Spacer(); DSSpinner() }
                        }
                    }
                    .disabled(!store.canSync || store.isSyncing)
                }
            } else {
                Section {
                    ForEach(names, id: \.self) { name in
                        Button {
                            Haptics.tap()
                            store.setMe(name)
                            onPick(name)
                            ToastCenter.shared.show("已设为 \(name)，正在同步", style: .success)
                            dismiss()
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Avatar(name: name, size: 30)
                                Text(name).foregroundStyle(Color.primary)
                                Spacer()
                                if let post = store.roster[name]?[today] {
                                    Text("今天 " + store.matcher.displayName(post)).font(.caption).foregroundStyle(.secondary)
                                }
                                if store.myRosterName == name {
                                    Image(systemName: "checkmark").foregroundStyle(DS.Palette.accent).fontWeight(.semibold)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("选好后提醒、工作量、遥测预测、排班预警都会换成这个人的，并马上重新同步一次。")
                }
            }
        }
        .searchable(text: $query, prompt: "搜名字")
        .appList()
        .navigationTitle("我是谁")
        .navigationBarTitleDisplayMode(.inline)
    }
}


/// 身份：普通使用者 / 管理者（输入密码只能查看所有人）/ 管理员（输入密码能修改）
struct RoleView: View {
    @EnvironmentObject private var store: AppStore
    @State private var password = ""
    @State private var checking = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                Label(store.role.title, systemImage: store.role.symbol).font(DS.Font.headline)
                Text(describe(store.role)).font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("当前身份")
            }
            if store.role == .user {
                Section {
                    SecureField("密码", text: $password)
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                        .focused($focused)
                    loginButton(.manager, "以管理者登录（只能查看）")
                    loginButton(.admin, "以管理员登录（可以修改）")
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(DS.Palette.warning)
                    }
                } header: {
                    Text("管理者 / 管理员登录")
                } footer: {
                    Text("输入密码后选登录方式：管理者可以查看所有人的排班，不能修改；管理员可以修改信息。")
                }
            } else {
                Section {
                    Button("退出登录，回到普通使用者", role: .destructive) {
                        store.logout()
                        ToastCenter.shared.show("已退出登录", style: .success)
                    }
                }
            }
        }
        .appList()
        .navigationTitle("身份")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func loginButton(_ role: UserRole, _ title: String) -> some View {
        Button {
            Task { @MainActor in
                checking = true
                let ok = await store.login(password: password, as: role)
                checking = false
                if ok {
                    error = nil
                    password = ""
                    ToastCenter.shared.show("已登录：\(role.title)", style: .success)
                } else {
                    error = "密码不对"
                    Haptics.warning()
                }
            }
        } label: {
            HStack {
                Label(title, systemImage: role.symbol)
                if checking { Spacer(); DSSpinner() }
            }
        }
        .disabled(password.isEmpty || checking)
    }

    private func describe(_ role: UserRole) -> String {
        switch role {
        case .user:
            return "可以看自己的排班、统计，改自己的名字、网站账号、提醒和显示设置；排班数据（手动改班、工作量纠正、规则、节假日、各组工作内容、班次类型、导入、恢复备份）只能看不能改。"
        case .manager:
            return "领导查看用：自己没有排班，首页显示全员今天的分工，可以看所有人的排班、工作量、均衡分析、排班规律，不能修改任何信息。"
        case .admin:
            return "可以修改所有信息。"
        }
    }
}
