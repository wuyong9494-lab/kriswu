import SwiftUI

/// 第一次打开的设置向导：连接值班网站 → 选我是谁 → 打开提醒 → 完成，三分钟就能用。
struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var step = 0
    @State private var password = Keychain.get(.sourcePassword) ?? ""
    @State private var showingWebLogin = false
    @State private var query = ""
    @State private var notificationsAllowed: Bool?
    @State private var checking = false
    /// 从设置里重新打开的（已经同步过）
    private var reopened: Bool { store.settings.lastSync != nil }
    @State private var showURL = AppStore.builtInSiteURL == nil
    private let steps = 5

    var body: some View {
        VStack(spacing: 0) {
            // 进度点
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? DS.Palette.accent : DS.Palette.hairline)
                        .frame(width: i == step ? 22 : 8, height: 8)
                }
            }
            .animation(DS.Motion.spring, value: step)
            .padding(.top, DS.Space.l)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                // 以前设置好过、又从设置里重新打开的：随时可以关掉
                if reopened {
                    Button("关闭") { store.settings.onboardingDone = true }
                        .padding(.top, DS.Space.l)
                        .padding(.trailing, DS.Space.l)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    switch step {
                    case 0: welcome
                    case 1: connect
                    case 2: whoAmI
                    case 3: reminders
                    default: done
                    }
                }
                .padding(DS.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }

            footer
        }
        .background(AppBackground())
        .fullScreenCover(isPresented: $showingWebLogin) { WebLoginView() }
        .interactiveDismissDisabled()
    }

    // MARK: 各步

    private var welcome: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            IconBadge(icon: "calendar.badge.clock", size: 72)
            Text("欢迎使用值班提醒").font(DS.Font.display)
            Text("跟着下面几步设置好，以后不用管它：").font(DS.Font.body).foregroundStyle(.secondary)
            feature("arrow.triangle.2.circlepath", "自动从值班网站取排班", "打开 App、后台空闲时都会同步，排班一变就通知你")
            feature("bell.badge", "到点提醒", "早上提醒今天的班，晚上提醒明天的班")
            feature("chart.bar", "工作量和均衡", "每人工作量、上班天数、遥测次数一目了然")
            feature("camera", "工作留痕", "拍照、录音、记一笔，按日期和班次存好")
            // 没有值班网站账号（比如 App 审核员）：用虚构数据看看所有功能
            Button {
                Haptics.tap()
                store.enterDemo()
            } label: {
                Label("先看演示（不用登录，全是虚构数据）", systemImage: "play.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: true))
            .padding(.top, DS.Space.s)
        }
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            title("连接值班网站", "用你自己的值班网站账号。账号密码只存在这台手机上。")
            if showURL {
                Button {
                    showingWebLogin = true
                } label: {
                    Label("① 登录值班网站，打开排班页面", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DSButtonStyle(kind: .secondary, fullWidth: true))
                Text("进到「我的分工」那一页后，点右上角「设为同步地址」，网址会自动填到下面。")
                    .font(.footnote).foregroundStyle(.secondary)
                field("② 排班页面网址", text: $store.settings.sourceURL, keyboard: .URL)
            } else {
                // 网址已经内置：只填账号密码
                Button { withAnimation { showURL = true } } label: {
                    Label("值班网站地址已内置（点这里可以改）", systemImage: "checkmark.circle")
                        .font(.footnote)
                }
                .foregroundStyle(DS.Palette.success)
            }
            field("值班网站账号", text: $store.settings.sourceUsername)
            VStack(alignment: .leading, spacing: 4) {
                Text("值班网站密码").font(DS.Font.caption).foregroundStyle(.secondary)
                SecureField("密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: password) {
                        Keychain.set($0, for: .sourcePassword)
                        store.settings.loginExpiredNotified = false
                    }
            }
            Button {
                Task { await store.sync(userInitiated: true, source: "设置向导") }
            } label: {
                HStack {
                    Label("③ 同步试试", systemImage: "arrow.triangle.2.circlepath")
                    if store.isSyncing { Spacer(); DSSpinner() }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DSButtonStyle(kind: .primary, fullWidth: true))
            .disabled(!store.canSync || store.isSyncing)
            if let message = store.settings.lastSyncMessage {
                Label(message, systemImage: synced ? "checkmark.circle.fill" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(synced ? DS.Palette.success : .secondary)
            }
        }
    }

    private var whoAmI: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            title("选一下你是谁", "全员排班里点你自己的名字，提醒、统计、预测就都是你的。")
            if store.roster.isEmpty {
                Text("还没读到全员名单：回上一步「同步试试」，成功后这里就能选。也可以先跳过，以后在「设置 › 账号与同步 › 我的名字」里选。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                TextField("搜名字", text: $query).textFieldStyle(.roundedBorder)
                let names = store.roster.keys
                    .filter { query.isEmpty || $0.contains(query) }
                    .sorted { $0.compare($1, locale: Locale(identifier: "zh_CN")) == .orderedAscending }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: DS.Space.xs)], spacing: DS.Space.xs) {
                    ForEach(names, id: \.self) { name in
                        let picked = store.myRosterName == name
                        Button {
                            Haptics.tap()
                            store.setMe(name)
                        } label: {
                            HStack(spacing: 6) {
                                Avatar(name: name, size: 24)
                                Text(name).font(DS.Font.callout).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Space.xs)
                            .background((picked ? DS.Palette.accent : DS.Palette.surface).opacity(picked ? 0.25 : 1),
                                        in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                                .strokeBorder(picked ? DS.Palette.accent : DS.Palette.hairline, lineWidth: picked ? 1.5 : 1))
                        }
                        .buttonStyle(PressableStyle())
                        .foregroundStyle(.primary)
                    }
                }
                if let me = store.myRosterName {
                    Label("已选：\(me)", systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.success).font(.footnote)
                }
            }
        }
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            title("打开提醒", "到点推送今天、明天的班；排班变了也马上告诉你。")
            Button {
                Task { notificationsAllowed = await NotificationService.requestAuthorization() }
            } label: {
                Label(notificationsAllowed == true ? "已允许通知" : "允许通知", systemImage: notificationsAllowed == true ? "checkmark" : "bell")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DSButtonStyle(kind: notificationsAllowed == true ? .secondary : .primary, fullWidth: true))
            if notificationsAllowed == false {
                Text("没允许：到 iPhone「设置 › 通知 › 值班提醒」里打开。").font(.footnote).foregroundStyle(DS.Palette.warning)
            }
            VStack(spacing: 0) {
                Toggle("早上提醒今天的班", isOn: $store.settings.morningEnabled)
                    .padding(.vertical, DS.Space.xs)
                Divider()
                Toggle("晚上提醒明天的班", isOn: $store.settings.eveningEnabled)
                    .padding(.vertical, DS.Space.xs)
                Divider()
                Toggle("排班有变动时通知我", isOn: $store.settings.notifyChanges)
                    .padding(.vertical, DS.Space.xs)
            }
            .card()
            Text("提醒时间（默认 7:30 和 20:30）、语音播报、微信推送以后都能在「设置」里改。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            IconBadge(icon: "checkmark.seal.fill", color: DS.Palette.success, size: 72)
            Text("设置好了").font(DS.Font.display)
            feature("hand.draw", "下拉刷新", "首页往下拉就马上同步一次")
            feature("square.grid.2x2", "加小组件", "长按主屏幕 › 左上角 ＋ › 搜「值班提醒」，今天的班、下次遥测、工作留痕都能放桌面")
            feature("switch.2", "控制中心", "iOS 18 起可以把「录音留痕」「拍照留痕」放进控制中心")
            feature("person.badge.key", "身份", "领导查看全员、管理员修改信息，在「设置 › 身份」登录")
        }
    }

    // MARK: 底部按钮

    private var footer: some View {
        HStack(spacing: DS.Space.s) {
            if step > 0 && step < steps - 1 {
                Button("上一步") { withAnimation(DS.Motion.spring) { step -= 1 } }
                    .buttonStyle(DSButtonStyle(kind: .ghost))
            }
            if step == 1 || step == 2 {
                Button("跳过") { withAnimation(DS.Motion.spring) { step += 1 } }
                    .buttonStyle(DSButtonStyle(kind: .ghost))
            }
            Button(nextTitle) {
                Haptics.tap()
                if step == steps - 1 {
                    store.settings.onboardingDone = true
                } else {
                    Task { await next() }
                }
            }
            .buttonStyle(DSButtonStyle(kind: .primary, fullWidth: true))
            .disabled((step == 1 && !store.canSync) || checking || store.isSyncing)
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.m)
        .background(.bar)
    }

    private var nextTitle: String {
        if step == 0 { return "开始设置" }
        if step == steps - 1 { return "开始使用" }
        if step == 1 && !synced { return checking ? "正在连接…" : "连接并下一步" }
        return "下一步"
    }

    /// 下一步之前先把这一步做实：连接这一步先同步成功；提醒这一步没点过允许就问一次
    private func next() async {
        if step == 1 && !synced {
            checking = true
            _ = await store.sync(userInitiated: true, source: "设置向导")
            checking = false
            // 没连上：留在这一步，下面会显示原因（实在连不上可以点「跳过」）
            guard synced else { Haptics.warning(); return }
        }
        if step == 3 && notificationsAllowed == nil {
            notificationsAllowed = await NotificationService.requestAuthorization()
        }
        withAnimation(DS.Motion.spring) { step += 1 }
    }

    // MARK: 小部件

    private var synced: Bool { !store.roster.isEmpty || !store.schedule.isEmpty }

    private func title(_ text: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(text).font(DS.Font.display)
            Text(detail).font(DS.Font.body).foregroundStyle(.secondary)
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            IconBadge(icon: icon, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Font.headline)
                Text(detail).font(DS.Font.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(DS.Font.caption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}
