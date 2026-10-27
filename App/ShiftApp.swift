import SwiftUI
import UserNotifications

@main
struct ShiftApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(store.settings.appearance.colorScheme)
                .task {
                    guard !AppStore.isDemo else { return }
                    // 以前读错表留下的「同事名字当成我的班」先清掉
                    store.repairNameShifts()
                    _ = await NotificationService.requestAuthorization()
                    await store.rescheduleNotifications()
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                guard !AppStore.isDemo else { break }
                store.applyPendingTaskToggles()
                WorkLogStore.shared.reloadIfNeeded()
                Task {
                    // 图标先换成今天的：iPhone 只许 App 在屏幕上时换图标，等同步完再换，打开一下就离开就换不上了
                    store.updateAppIcon()
                    // 打开就离开也能做完：向系统多要一点后台时间（到时间就停下同步，保存好）
                    let assertion = BackgroundAssertion()
                    assertion.begin { store.cancelRunningSync() }
                    defer { assertion.end() }
                    // 到点的微信先发（几秒钟），再做费时的同步：和后台刷新一样，同步慢也不耽误微信
                    await store.sendDueWeChatReminders()
                    await store.refreshHolidaysIfNeeded()
                    await store.syncIfStale()
                    await store.sendDueWeChatReminders()
                    // 周会文档每周一更新：这周还没读到新的就读一次
                    await store.refreshMeetingIfDue()
                    await store.rescheduleNotifications()
                    store.autoBackupIfNeeded()
                    store.flushSave(wait: true)
                }
            case .background:
                store.flushSave(wait: true)
                BackgroundRefresh.schedule(notBefore: store.nextBackgroundSync)
                // 工作留痕的面容 ID 锁：退到后台就重新锁上
                WorkLogStore.shared.unlocked = false
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await AppStore.shared.backgroundRefresh()
        }
    }
}

// 通知的回调系统在主线程调（@preconcurrency：按主线程的代码对待）
final class AppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationService.registerCategories()
        CrashLog.shared.start()
        return true
    }

    // App 在前台时也显示横幅
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// 点了通知：要打开的页面先记下（App 刚启动时界面可能还没出来），再通知界面去打开
    static var pendingRoute: String?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // 点了「清单全部做完」：在后台勾掉，不打开 App
        if response.actionIdentifier == NotificationService.tasksDoneAction,
           let route = response.notification.request.content.userInfo["route"] as? String,
           route.hasPrefix("day:"), let day = DayKey(string: String(route.dropFirst(4))) {
            Task { @MainActor in
                AppStore.shared.markAllTasksDone(on: day)
                completionHandler()
            }
            return
        }
        if let route = response.notification.request.content.userInfo["route"] as? String {
            DispatchQueue.main.async {
                AppDelegate.pendingRoute = route
                NotificationCenter.default.post(name: .openRoute, object: nil)
            }
        }
        completionHandler()
    }
}

extension Notification.Name {
    /// 点了带「route」的通知
    static let openRoute = Notification.Name("openRoute")
    /// 钥匙串里的账号密码、token 改了
    static let keychainChanged = Notification.Name("keychainChanged")
}

struct RootView: View {
    enum Tab: String, CaseIterable { case today, calendar, stats, site, settings }
    @EnvironmentObject private var store: AppStore
    @State private var tab: Tab
    /// 从「备忘录」等分享进来的录音存好后打开工作留痕；控制中心、操作按钮、小组件来的拍照 / 录音 / 记一笔
    @State private var rootSheet: RootSheet?
    @State private var camera = false
    /// 点小组件打开某一天
    @State private var openDay: DayKey?
    @State private var tabBarTop: CGFloat = .infinity
    /// 打开过的页：没打开过的不建（网站页不会一启动就去登录网站，也少画几页）
    @State private var visited: Set<Tab> = []
    /// 分享过来的数传计划（打开「发数传计划」时带进去）；从快捷指令打开时直接进扫描
    @State private var passPlanReading: PassPlan.Reading?
    @State private var passPlanAutoScan = false
    @State private var inReviewDemo = UserDefaults.standard.bool(forKey: AppStore.demoKey)
    @Environment(\.scenePhase) private var scenePhase

    enum RootSheet: String, Identifiable {
        case workLog, record, note, rosterLog, teamChanges, whatsNew, notices, meeting, meetingMine, passPlan
        var id: String { rawValue }
    }

    /// 更新后第一次打开：弹出「这次更新了什么」（新装的人不弹，向导走完就记成看过了）
    private func showWhatsNewIfNeeded() {
        guard !AppStore.isDemo else { return }
        let seen = UserDefaults.standard.string(forKey: WhatsNew.seenKey)
        if !store.settings.onboardingDone {
            UserDefaults.standard.set(WhatsNew.id, forKey: WhatsNew.seenKey)
        } else if seen != WhatsNew.id, rootSheet == nil, AppDelegate.pendingRoute == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if rootSheet == nil { rootSheet = .whatsNew } }
        }
    }

    /// 点通知进来：打开对应的详情页
    private func openPendingRoute() {
        if let route = AppDelegate.pendingRoute, route.hasPrefix("day:"), let day = DayKey(string: String(route.dropFirst(4))) {
            AppDelegate.pendingRoute = nil
            rootSheet = nil
            camera = false
            tab = .today
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openDay = day }
            return
        }
        guard let route = AppDelegate.pendingRoute, let sheet = RootSheet(rawValue: route) else { return }
        AppDelegate.pendingRoute = nil
        rootSheet = nil
        camera = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { rootSheet = sheet }
    }

    init() {
        ChromeAppearance.apply()
        // 截图时用启动参数 -screen xxx 直接打开某一页
        _tab = State(initialValue: Tab(rawValue: UserDefaults.standard.string(forKey: "screen") ?? "") ?? .today)
    }

    private let tabs: [FloatingTabBar<Tab>.Item] = [
        .init(tab: .today, title: "今天", icon: "sun.max"),
        .init(tab: .calendar, title: "日历", icon: "calendar"),
        .init(tab: .stats, title: "统计", icon: "chart.bar"),
        .init(tab: .site, title: "网站", icon: "globe"),
        .init(tab: .settings, title: "设置", icon: "gearshape"),
    ]

    var body: some View {
        Group {
            if let screen = UserDefaults.standard.string(forKey: "screen"), Tab(rawValue: screen) == nil {
                NavigationStack { ScreenCatalog.view(screen) }
                    .onAppear { ScreenCatalog.scrollIfAsked() }
            } else {
                // 五页一直都在（切回来时导航、滚动位置都还在），只显示选中的那页；底部是悬浮的玻璃标签栏
                ZStack {
                    page(.today) { TodayView() }
                    page(.calendar) { CalendarView() }
                    page(.stats) { NavigationStack { WorkloadView() } }
                    page(.site) { SiteView() }
                    page(.settings) { SettingsView() }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    FloatingTabBar(items: tabs, selection: $tab)
                }
                .onPreferenceChange(TabBarTopKey.self) { tabBarTop = $0 }
                .environment(\.floatingTabBarTop, tabBarTop)
                .onAppear { ScreenCatalog.scrollIfAsked() }
            }
        }
        // 换主题色时整个界面重画一遍
        .id(store.settings.accentTheme)
        .tint(DS.Palette.accent)
        .fontDesign(.rounded)
        .overlay { ToastOverlay() }
        // 点了「先看演示」：顶上一直提示，随时可以退出回到自己的数据
        .overlay(alignment: .top) {
            if inReviewDemo {
                Button {
                    store.exitDemo()
                    inReviewDemo = false
                } label: {
                    Label("演示模式（虚构数据）· 点这里退出", systemImage: "play.rectangle.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(Color.orange))
                        .foregroundStyle(.white)
                }
                .padding(.top, 2)
            }
        }
        .onReceive(store.objectWillChange) { _ in
            let flag = UserDefaults.standard.bool(forKey: AppStore.demoKey)
            if flag != inReviewDemo { DispatchQueue.main.async { inReviewDemo = flag } }
        }
        // 「用值班提醒打开」的录音（比如备忘录里的通话录音）：存进工作留痕；
        // shiftreminder://capture/photo|record|note：小组件上的按钮
        .onOpenURL { url in
            if url.isFileURL, ["xlsx", "csv", "tsv"].contains(url.pathExtension.lowercased()),
               let plan = try? PlanReader.read(file: url) {
                // 导出、分享过来的数传计划：直接打开「发数传计划」
                passPlanReading = plan
                tab = .today
                rootSheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { rootSheet = .passPlan }
            } else if url.isFileURL, ["xlsx", "csv", "tsv"].contains(url.pathExtension.lowercased()) {
                // 金山文档里导出、分享过来的周会表格
                let result = store.importMeetingFile(url)
                ToastCenter.shared.show(result, style: AppStore.meetingImportFailed(result) ? .error : .success)
                tab = .today
                rootSheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { rootSheet = .meeting }
            } else if url.isFileURL {
                if WorkLogStore.shared.importFile(url) != nil {
                    tab = .today
                    rootSheet = .workLog
                    ToastCenter.shared.show("已存进工作留痕", style: .success)
                } else {
                    ToastCenter.shared.show("没能存进工作留痕", style: .error)
                }
            } else if url.scheme == "shiftreminder", url.host == "capture",
                      let action = CaptureAction(rawValue: url.lastPathComponent) {
                startCapture(action)
            } else if url.scheme == "shiftreminder", url.host == "day", let day = DayKey(string: url.lastPathComponent) {
                // 小组件：打开那一天（我的班、全员分工、留痕）
                tab = .today
                rootSheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { openDay = day }
            }
        }
        // 控制中心、操作按钮、快捷指令：动作写在 App Group 里，App 打开后接着做
        .onReceive(NotificationCenter.default.publisher(for: .pendingCapture)) { _ in
            if let action = PendingCapture.take() { startCapture(action) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRoute)) { _ in openPendingRoute() }
        // 过了零点（或换了时区）：所有页面按新的一天重画，图标、小组件、提醒跟着换
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.objectWillChange.send()
            store.requestReschedule()
        }
        .onAppear {
            openPendingRoute()
            showWhatsNewIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pendingTaskToggles)) { _ in
            store.applyPendingTaskToggles()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active, let action = PendingCapture.take() { startCapture(action) }
        }
        .sheet(item: $openDay) { DayEditor(day: $0) }
        .sheet(item: $rootSheet) { sheet in
            switch sheet {
            case .workLog:
                NavigationStack {
                    WorkLogView()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { rootSheet = nil } } }
                }
            case .record: RecorderSheet(autoStart: true)
            case .note: NoteSheet()
            case .whatsNew: WhatsNewView()
            case .notices:
                NavigationStack {
                    SiteNoticesView()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { rootSheet = nil } } }
                }
            case .passPlan:
                NavigationStack {
                    PassPlanView(reading: passPlanReading, autoScan: passPlanAutoScan)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { rootSheet = nil } } }
                }
                .onDisappear {
                    passPlanReading = nil
                    passPlanAutoScan = false
                }
            case .meeting, .meetingMine:
                NavigationStack {
                    MeetingIssuesView(mineOnly: sheet == .meetingMine)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { rootSheet = nil } } }
                }
            case .rosterLog, .teamChanges:
                NavigationStack {
                    Group {
                        if sheet == .rosterLog { RosterLogView() } else { TeamChangesView() }
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { rootSheet = nil } } }
                }
            }
        }
        // 第一次打开：设置向导
        .fullScreenCover(isPresented: Binding(get: { !AppStore.isDemo && !store.settings.onboardingDone },
                                              set: { if !$0 { store.settings.onboardingDone = true } })) {
            OnboardingView()
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in
                if WorkLogStore.shared.addPhoto(image) != nil {
                    ToastCenter.shared.show("照片已存进工作留痕", style: .success)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func startCapture(_ action: CaptureAction) {
        tab = .today
        // 先关掉正在显示的，再打开要的
        rootSheet = nil
        camera = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            switch action {
            case .photo: camera = true
            case .record: rootSheet = .record
            case .note: rootSheet = .note
            case .plan:
                passPlanReading = nil
                passPlanAutoScan = true
                rootSheet = .passPlan
            }
        }
    }

    @ViewBuilder
    private func page<V: View>(_ t: Tab, @ViewBuilder content: () -> V) -> some View {
        let selected = tab == t
        if selected || visited.contains(t) {
            pageBody(selected, content: content)
                .onAppear { visited.insert(t) }
        }
    }

    private func pageBody<V: View>(_ selected: Bool, @ViewBuilder content: () -> V) -> some View {
        content()
            .opacity(selected ? 1 : 0)
            .scaleEffect(selected ? 1 : 0.985)
            .allowsHitTesting(selected)
            .accessibilityHidden(!selected)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tab)
    }
}

/// 截图用：按名字打开某一页（只在启动参数 -screen 时用到）
enum ScreenCatalog {
    /// 截长页面的第二、三屏：启动参数 -scrollPage n，页面出来后把最大的那块滚动区域往下翻 n 屏
    @MainActor
    static func scrollIfAsked() {
        let pages = UserDefaults.standard.integer(forKey: "scrollPage")
        guard pages > 0 else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }
            guard let scroll = windows.compactMap({ largestScrollView(in: $0) }).first else { return }
            let inset = scroll.adjustedContentInset
            let page = scroll.bounds.height - inset.top - inset.bottom
            let bottom = max(-inset.top, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
            scroll.setContentOffset(CGPoint(x: 0, y: min(-inset.top + CGFloat(pages) * page * 0.9, bottom)), animated: false)
        }
    }

    /// 能竖着滚的里面最大的一块（横着滑的一排组名、7 天不算）
    @MainActor
    private static func largestScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func walk(_ view: UIView) {
            if let s = view as? UIScrollView, s.contentSize.height > s.bounds.height + 1, s.bounds.width > 200,
               best.map({ s.bounds.width * s.bounds.height > $0.bounds.width * $0.bounds.height }) ?? true {
                best = s
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return best
    }

    @MainActor @ViewBuilder
    static func view(_ name: String) -> some View {
        let today = DayKey.today
        switch name {
        case "fairness": FairnessView()
        case "preview": RosterPreviewView()
        case "week": WeekRosterView()
        case "swap": SwapHelperView(day: today.adding(days: 1))
        case "ledger": SwapLedgerView()
        case "year": YearStatsView()
        case "summary": YearSummaryView(year: today.year)
        case "check": DataCheckView()
        case "rest": RestTrendView()
        case "forecast": DutyForecastView()
        case "worklog": WorkLogView()
        case "manager": ManagerHomeView()
        case "onboarding": OnboardingView()
        case "profiles": PeopleProfilesView()
        case "rosterlog": RosterLogView()
        case "role": RoleView()
        case "patterns": SchedulePatternsView()
        case "holidays": HolidaysView()
        case "rules": WorkloadRulesView()
        case "team": TeamChangesView()
        case "leave": LeavePlannerView()
        case "automation": AutomationGuideView()
        case "backup": BackupView()
        case "diagnostics": DiagnosticsView()
        case "search": MemberSearchView()
        case "day": DayEditor(day: today)
        case "roster": DayRosterView(day: today)
        case "holidayduty": HolidayDutyView()
        case "meeting": MeetingIssuesView()
        case "meetingEdit": MeetingIssuesView(editing: "调度组")
        case "meetingSource": MeetingSourceView()
        case "meetingTrend": MeetingTrendView()
        case "todayLayout": TodayLayoutView()
        case "years": MultiYearStatsView()
        case "passPlan": PassPlanView(reading: PassPlan.Reading(rows: PassPlanView.demoRows, layout: nil))
        case "rulesExplain": RulesExplainView()
        case "allFeatures": AllFeaturesView()
        case "game": GamesHomeView()
        case "tiles": TileGameHomeView()
        case "gameBoard": TileBoardView(play: TilePlay(level: .normal, seed: 2026, mode: .solo), race: nil)
        case "gomoku": GomokuHomeView()
        case "gomokuBoard":
            GomokuLocalScreen(mode: .computer(.normal, .black),
                              initial: Gomoku(moves: [112, 113, 97, 128, 127, 98, 82, 142, 111, 96]))
        default: TodayView()
        }
    }
}

/// 向系统要一点后台时间（打开 App 马上离开时把同步做完）；时间到了先做 onExpire 再交还
@MainActor
final class BackgroundAssertion {
    private var id = UIBackgroundTaskIdentifier.invalid

    func begin(onExpire: @escaping @MainActor () -> Void) {
        id = UIApplication.shared.beginBackgroundTask(withName: "foreground-sync") { [weak self] in
            MainActor.assumeIsolated {
                onExpire()
                self?.end()
            }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
