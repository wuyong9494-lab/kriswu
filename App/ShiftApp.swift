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
                .task {
                    guard !AppStore.isDemo else { return }
                    // 以前读错表留下的「同事名字当成我的班」先清掉
                    store.repairNameShifts()
                    _ = await NotificationService.requestAuthorization()
                    await store.rescheduleNotifications()
                    await WuMindIAPManager.shared.recoverUnfinishedTransactions(store: WuMindStore.shared, silent: true)
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                guard !AppStore.isDemo else { break }
                // 老用户一次性恢复默认 WUMIND 品牌主图标（已迁移则直接跳过，不再按日切换）
                store.migrateToFixedBrandIconIfNeeded()
                if AppAccountManager.shared.isExternalRestricted {
                    Task {
                        await WuMindIAPManager.shared.recoverUnfinishedTransactions(store: WuMindStore.shared, silent: true)
                        await WuMindStore.shared.runDueScheduledTasksIfNeeded()
                        _ = try? await WuMindStore.shared.pullCloudCronResults()
                    }
                    break
                }
                store.applyPendingTaskToggles()
                WorkLogStore.shared.reloadIfNeeded()
                Task {
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
                    await WuMindIAPManager.shared.recoverUnfinishedTransactions(store: WuMindStore.shared, silent: true)
                    await WuMindStore.shared.runDueScheduledTasksIfNeeded()
                    _ = try? await WuMindStore.shared.pullCloudCronResults()
                    await WuMindAgentCoordinator.shared.runBackgroundMonitorsIfDue()
                }
            case .background:
                store.flushSave(wait: true)
                WuMindStore.shared.flushSave()
                WuMindAgentCoordinator.shared.saveToDisk()
                if !AppAccountManager.shared.isExternalRestricted {
                    BackgroundRefresh.schedule(notBefore: store.nextBackgroundSync)
                    // 工作留痕的面容 ID 锁：退到后台就重新锁上
                    WorkLogStore.shared.unlocked = false
                }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            let restricted = await MainActor.run { AppAccountManager.shared.isExternalRestricted }
            if !restricted {
                await AppStore.shared.backgroundRefresh()
            }
            await WuMindStore.shared.runDueScheduledTasksIfNeeded()
            await WuMindAgentCoordinator.shared.runBackgroundMonitorsIfDue()
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

    @MainActor
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        Self.sceneConfiguration(for: session.role)
    }

    @MainActor
    static func sceneConfiguration(for role: UISceneSession.Role) -> UISceneConfiguration {
        // Return only our configuration contribution. Passing back the session's
        // existing SwiftUI AppSceneDelegate makes it a custom delegate to be
        // wrapped again by UIApplicationDelegateAdaptor during app launch.
        let configuration = UISceneConfiguration(name: nil, sessionRole: role)
        if role == .windowExternalDisplayNonInteractive {
            configuration.delegateClass = DuelTelevisionSceneDelegate.self
        }
        return configuration
    }

    /// 平时竖着用；乱斗对局里横过来（ArenaOrientation）；iPad 随便转
    @MainActor
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if window?.windowScene?.session.role == .windowExternalDisplayNonInteractive { return .landscape }
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        return ArenaOrientation.landscape ? .landscape : .portrait
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
                if !AppAccountManager.shared.isExternalRestricted {
                    AppStore.shared.markAllTasksDone(on: day)
                }
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
    enum ActiveWorkspace: String, Hashable { case home, duty, wumind }
    enum Tab: String, CaseIterable { case today, calendar, stats, games, site, settings }
    enum ExternalTab: String, CaseIterable { case wumind, games, profile }
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var account = AppAccountManager.shared
    @ObservedObject private var tabBarVisibility = AppTabBarVisibility.shared
    @State private var activeWorkspace: ActiveWorkspace
    @State private var visitedWorkspaces: Set<ActiveWorkspace> = []
    @State private var tab: Tab
    @State private var externalTab: ExternalTab = .wumind
    @State private var visitedExternal: Set<ExternalTab> = [.wumind]
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

    /// 更新后第一次打开：进入值班工作区时才弹「这次更新了什么」，绝不遮挡冷启动双卡工作区首页
    private func showWhatsNewIfNeeded() {
        guard activeWorkspace == .duty, !AppStore.isDemo, !account.isExternalRestricted else { return }
        let seen = UserDefaults.standard.string(forKey: WhatsNew.seenKey)
        if !store.settings.onboardingDone {
            UserDefaults.standard.set(WhatsNew.id, forKey: WhatsNew.seenKey)
        } else if seen != WhatsNew.id, rootSheet == nil, openDay == nil, !camera, AppDelegate.pendingRoute == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if activeWorkspace == .duty, rootSheet == nil, openDay == nil, !camera,
                   AppDelegate.pendingRoute == nil, UserDefaults.standard.string(forKey: WhatsNew.seenKey) != WhatsNew.id {
                    rootSheet = .whatsNew
                }
            }
        }
    }

    /// 切换工作区：仅改当前展示层，绝不销毁另一个工作区的视图树、草稿或进行中生成任务
    private func switchWorkspace(to target: ActiveWorkspace, considerWhatsNew: Bool = true) {
        if target == .duty && account.isExternalRestricted {
            ToastCenter.shared.show("当前为外部用户权限界限，无法进入内部 On Duty 值班工作区", style: .error)
            return
        }
        if target == .duty && store.settings.wumindStandaloneMode {
            store.settings.wumindStandaloneMode = false
        }
        visitedWorkspaces.insert(target)
        withAnimation(.easeInOut(duration: 0.22)) {
            activeWorkspace = target
        }
        if target == .duty && considerWhatsNew {
            showWhatsNewIfNeeded()
        }
    }

    private func returnToLauncherHome() {
        WuMindStore.shared.flushSave()
        withAnimation(.easeInOut(duration: 0.22)) {
            activeWorkspace = .home
        }
    }

    /// 点通知进来：自动切入值班工作区并打开对应的详情页
    private func openPendingRoute() {
        guard let route = AppDelegate.pendingRoute else { return }
        guard account.canOpenDeepLinkRoute(route) else {
            AppDelegate.pendingRoute = nil
            ToastCenter.shared.show("当前为外部用户权限界限，无法打开内部值班页面", style: .error)
            return
        }
        switchWorkspace(to: .duty, considerWhatsNew: false)
        if route.hasPrefix("day:"), let day = DayKey(string: String(route.dropFirst(4))) {
            AppDelegate.pendingRoute = nil
            rootSheet = nil
            camera = false
            tab = .today
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openDay = day }
            return
        }
        guard let sheet = RootSheet(rawValue: route) else { return }
        AppDelegate.pendingRoute = nil
        rootSheet = nil
        camera = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { rootSheet = sheet }
    }

    init() {
        ChromeAppearance.apply()
        let screenArg = UserDefaults.standard.string(forKey: "screen")
        let initialTab = Tab(rawValue: screenArg ?? "") ?? .today
        _tab = State(initialValue: initialTab)
        if let screenArg, !screenArg.isEmpty {
            if screenArg == "home" || screenArg == "launcher" {
                _activeWorkspace = State(initialValue: .home)
            } else if screenArg == "wumind" {
                _activeWorkspace = State(initialValue: .wumind)
                _visitedWorkspaces = State(initialValue: [.wumind])
            } else if Tab(rawValue: screenArg) != nil {
                _activeWorkspace = State(initialValue: .duty)
                _visitedWorkspaces = State(initialValue: [.duty])
            } else {
                _activeWorkspace = State(initialValue: .home)
            }
        } else {
            // 正常冷启动默认落在双卡工作区选择首页（On Duty / WuMind）
            _activeWorkspace = State(initialValue: .home)
        }
    }

    private let tabs: [FloatingTabBar<Tab>.Item] = [
        .init(tab: .today, title: "今天", icon: "sun.max"),
        .init(tab: .calendar, title: "日历", icon: "calendar"),
        .init(tab: .stats, title: "统计", icon: "chart.bar"),
        .init(tab: .games, title: "游戏", icon: "gamecontroller"),
        .init(tab: .site, title: "网站", icon: "globe"),
        .init(tab: .settings, title: "设置", icon: "gearshape"),
    ]

    private let externalTabs: [FloatingTabBar<ExternalTab>.Item] = [
        .init(tab: .wumind, title: "WUMIND", icon: "sparkles"),
        .init(tab: .games, title: "游戏", icon: "gamecontroller"),
        .init(tab: .profile, title: "我的", icon: "person.crop.circle"),
    ]

    private var customCatalogScreen: String? {
        guard let screen = UserDefaults.standard.string(forKey: "screen"),
              !screen.isEmpty,
              screen != "home",
              screen != "launcher",
              screen != "wumind",
              Tab(rawValue: screen) == nil else {
            return nil
        }
        return screen
    }

    var body: some View {
        Group {
            if let screen = customCatalogScreen {
                NavigationStack { ScreenCatalog.view(screen) }
                    .onAppear { ScreenCatalog.scrollIfAsked() }
            } else {
                // 三层持久化 ZStack（工作区选择首页 / On Duty / WuMind）：
                // 任一工作区返回首页时绝不卸载视图树，所有草稿、图片/视频后台生成任务与导航进度原样保留。
                ZStack {
                    WorkspaceLauncherHomeView(
                        onSelectDuty: { switchWorkspace(to: .duty) },
                        onSelectWuMind: { switchWorkspace(to: .wumind) }
                    )
                    .opacity(activeWorkspace == .home ? 1 : 0)
                    .zIndex(activeWorkspace == .home ? 2 : 0)
                    .allowsHitTesting(activeWorkspace == .home)
                    .accessibilityHidden(activeWorkspace != .home)

                    if !account.isExternalRestricted && (activeWorkspace == .duty || visitedWorkspaces.contains(.duty)) {
                        dutyWorkspaceContent
                            .opacity(activeWorkspace == .duty ? 1 : 0)
                            .zIndex(activeWorkspace == .duty ? 2 : 0)
                            .allowsHitTesting(activeWorkspace == .duty)
                            .accessibilityHidden(activeWorkspace != .duty)
                    }

                    if activeWorkspace == .wumind || visitedWorkspaces.contains(.wumind) {
                        wumindWorkspaceContent
                            .opacity(activeWorkspace == .wumind ? 1 : 0)
                            .zIndex(activeWorkspace == .wumind ? 2 : 0)
                            .allowsHitTesting(activeWorkspace == .wumind)
                            .accessibilityHidden(activeWorkspace != .wumind)
                    }
                }
            }
        }
        // 换主题色时整个界面重画一遍
        .id(store.settings.accentTheme)
        .tint(DS.Palette.accent)
        .preferredColorScheme(store.settings.appearance.colorScheme)
        .overlay { ToastOverlay() }
        // 点了「先看演示」：仅在进入工作区后提示（绝不叠加在纯净双卡工作区首页上）
        .overlay(alignment: .top) {
            if inReviewDemo && activeWorkspace != .home {
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
            if url.isFileURL, url.pathExtension.lowercased() == "arenapack" {
                Task {
                    await ArenaResourcePackStore.shared.install(from: url)
                    if let error = ArenaResourcePackStore.shared.error {
                        ToastCenter.shared.show(error, style: .error)
                    } else {
                        ToastCenter.shared.show("乱斗资源包已导入，可在大厅的英雄或设置页面查看", style: .success)
                    }
                }
            } else if account.isExternalRestricted {
                ToastCenter.shared.show("当前为外部账号权限界限，无法导入或查看内部值班数据", style: .error)
                return
            } else if url.isFileURL, ["xlsx", "csv", "tsv"].contains(url.pathExtension.lowercased()),
               let plan = try? PlanReader.read(file: url) {
                // 导出、分享过来的数传计划：自动切入值班工作区并打开「发数传计划」
                switchWorkspace(to: .duty, considerWhatsNew: false)
                passPlanReading = plan
                tab = .today
                rootSheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { rootSheet = .passPlan }
            } else if url.isFileURL, ["xlsx", "csv", "tsv"].contains(url.pathExtension.lowercased()) {
                // 金山文档里导出、分享过来的周会表格
                switchWorkspace(to: .duty, considerWhatsNew: false)
                let result = store.importMeetingFile(url)
                ToastCenter.shared.show(result, style: AppStore.meetingImportFailed(result) ? .error : .success)
                tab = .today
                rootSheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { rootSheet = .meeting }
            } else if url.isFileURL {
                switchWorkspace(to: .duty, considerWhatsNew: false)
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
            } else if url.scheme == "shiftreminder", url.host == "day" || url.host == "managed-calendar",
                      let day = DayKey(string: url.lastPathComponent) {
                // 小组件或本版生成的日历日程：自动切入值班工作区并打开那一天
                switchWorkspace(to: .duty, considerWhatsNew: false)
                tab = .today
                rootSheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { openDay = day }
            }
        }
        // 控制中心、操作按钮、快捷指令：动作写在 App Group 里，App 打开后接着做
        .onReceive(NotificationCenter.default.publisher(for: .pendingCapture)) { _ in
            if !account.isExternalRestricted, let action = PendingCapture.take() { startCapture(action) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRoute)) { _ in openPendingRoute() }
        // 过了零点（或换了时区）：所有页面按新的一天重画，图标、小组件、提醒跟着换
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            if !account.isExternalRestricted {
                store.objectWillChange.send()
                store.requestReschedule()
            }
        }
        .onAppear {
            openPendingRoute()
            showWhatsNewIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pendingTaskToggles)) { _ in
            if !account.isExternalRestricted {
                store.applyPendingTaskToggles()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active, !account.isExternalRestricted, let action = PendingCapture.take() { startCapture(action) }
        }
        .onChange(of: account.isExternalRestricted) { restricted in
            if restricted {
                visitedWorkspaces.remove(.duty)
                if activeWorkspace == .duty {
                    visitedWorkspaces.insert(.wumind)
                    activeWorkspace = .wumind
                }
            }
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
        // 第一次进入值班工作区：设置向导（冷启动停在双卡工作区首页时不弹窗遮挡）
        .fullScreenCover(isPresented: Binding(get: { activeWorkspace == .duty && !AppStore.isDemo && !store.settings.onboardingDone },
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

    /// 内部 On Duty 值班工作区（保持六标签持久化，左上角返回工作区首页）
    private var dutyWorkspaceContent: some View {
        ZStack {
            page(.today) { TodayView(onReturnHome: { returnToLauncherHome() }) }
            page(.calendar) { CalendarView() }
            page(.stats) { NavigationStack { WorkloadView().observeTabRootNavigationDepth(tabID: "stats") } }
            page(.games) { NavigationStack { GamesHomeView().observeTabRootNavigationDepth(tabID: "games") } }
            page(.site) { SiteView() }
            page(.settings) { SettingsView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !tabBarVisibility.shouldHideTabBar(for: tab.rawValue) {
                FloatingTabBar(items: tabs, selection: $tab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onPreferenceChange(TabBarTopKey.self) { value in
            if abs(value - tabBarTop) > 0.5 || value.isInfinite != tabBarTop.isInfinite {
                tabBarTop = value
            }
        }
        .environment(\.floatingTabBarTop, tabBarVisibility.shouldHideTabBar(for: tab.rawValue) ? .infinity : tabBarTop)
        .onAppear {
            ScreenCatalog.scrollIfAsked()
        }
    }

    /// WuMind 工作区（外部账号严格保留三标签权限界限；内部账号直达全屏 WuMind；均带左上角返回首页）
    @ViewBuilder
    private var wumindWorkspaceContent: some View {
        if account.isExternalRestricted {
            ZStack {
                externalPage(.wumind) { WuMindWorkspaceView(onClose: nil, onReturnHome: { returnToLauncherHome() }) }
                externalPage(.games) { NavigationStack { GamesHomeView().observeTabRootNavigationDepth(tabID: "ext.games") } }
                externalPage(.profile) { ExternalAccountProfileView() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !tabBarVisibility.shouldHideTabBar(for: "ext.\(externalTab.rawValue)") {
                    FloatingTabBar(items: externalTabs, selection: $externalTab)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onPreferenceChange(TabBarTopKey.self) { tabBarTop = $0 }
            .environment(\.floatingTabBarTop, tabBarVisibility.shouldHideTabBar(for: "ext.\(externalTab.rawValue)") ? .infinity : tabBarTop)
        } else {
            WuMindWorkspaceView(
                onClose: nil,
                onReturnHome: { returnToLauncherHome() }
            )
        }
    }

    private func startCapture(_ action: CaptureAction) {
        guard !account.isExternalRestricted else {
            ToastCenter.shared.show("外部用户权限界限：无法使用内部工作留痕", style: .error)
            return
        }
        switchWorkspace(to: .duty, considerWhatsNew: false)
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
                .environment(\.floatingTabScope, t.rawValue)
                .onAppear { visited.insert(t) }
        }
    }

    @ViewBuilder
    private func externalPage<V: View>(_ t: ExternalTab, @ViewBuilder content: () -> V) -> some View {
        let selected = externalTab == t
        if selected || visitedExternal.contains(t) {
            content()
                .environment(\.floatingTabScope, "ext.\(t.rawValue)")
                .opacity(selected ? 1 : 0)
                .zIndex(selected ? 1 : 0)
                .allowsHitTesting(selected)
                .accessibilityHidden(!selected)
                .onAppear { visitedExternal.insert(t) }
        }
    }

    private func pageBody<V: View>(_ selected: Bool, @ViewBuilder content: () -> V) -> some View {
        content()
            .opacity(selected ? 1 : 0)
            .zIndex(selected ? 1 : 0)
            .allowsHitTesting(selected)
            .accessibilityHidden(!selected)
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
        case "passPlanOperators": PassPlanOperatorsView()
        case "rulesExplain": RulesExplainView()
        case "allFeatures": AllFeaturesView()
        case "game": GamesHomeView()
        case "fighter": DuelHomeView()
        case "tiles": TileGameHomeView()
        case "gameBoard": TileBoardView(play: TilePlay(level: .normal, seed: 2026, mode: .solo), race: nil)
        case "arena": ArenaHomeView()
        // Preserve the original/legacy asset comparison fixture independently
        // from the three-hero lobby used by the real entry flow.
        case "arenaRangerComparison": ArenaHomeView(threeHeroSample: false)
        #if DEBUG
        case "arenaRoomReady", "arenaRoomWaiting":
            ArenaRoomView(lobby: ArenaLobby(room: GameRoom.arenaPreview(waiting: name == "arenaRoomWaiting"),
                                           mode: .teamFight, brawler: .ranger), previewOnly: true)
        #endif
        case "arenaSampleReview", "arenaSampleMapReview": ArenaSampleReview(onClose: {}, onPlay: {}, initialPage: name == "arenaSampleMapReview" ? 1 : 0)
        case "arenaDiagnostics": ArenaDiagnosticSuiteView()
        case "arenaBenchmark": ArenaPlayView(setup: ArenaController.Setup(mode: .zone, brawler: .ranger, name: "压测", level: 3,
                                                                           loadout: ArenaLoadout.basic(.ranger, level: 3), benchmark: true))
        case "arenaSampleBenchmark", "arenaHarborBenchmark": ArenaPlayView(setup: ArenaController.Setup(mode: .zone, brawler: .ranger, name: "样板对照", level: 3,
            loadout: ArenaLoadout.basic(.ranger, level: 3), benchmark: true, qualitySample: true, benchmarkTwinGates: name == "arenaHarborBenchmark"))
        case "arenaPlay": ArenaPlayView(setup: ArenaController.Setup(mode: .teamFight, brawler: .knight, name: "我", level: 3,
                                                                     loadout: ArenaLoadout.basic(.knight, level: 3)))
        case "arenaShowdown": ArenaPlayView(setup: ArenaController.Setup(mode: .showdown, brawler: .mage, name: "我"))
        case "arenaZone": ArenaPlayView(setup: ArenaController.Setup(mode: .zone, brawler: .necromancer, name: "我", level: 5,
                                                                     loadout: ArenaLoadout.basic(.necromancer, level: 5)))
        case "arenaBall": ArenaPlayView(setup: ArenaController.Setup(mode: .ball, brawler: .ranger, name: "我"))
        case "arenaHeist": ArenaPlayView(setup: ArenaController.Setup(mode: .heist, brawler: .mage, name: "我"))
        case "arenaBoss": ArenaPlayView(setup: ArenaController.Setup(mode: .boss, brawler: .knight, name: "我", level: 9,
                                                                     loadout: ArenaLoadout.basic(.knight, level: 9)))
        case "arenaVersus": ArenaPlayView(setup: ArenaController.Setup(mode: .teamFight, brawler: .knight, name: "我", level: 7,
                                                                       loadout: ArenaLoadout.basic(.knight, level: 7), demo: .versus))
        case "arenaResult": ArenaPlayView(setup: ArenaController.Setup(mode: .teamFight, brawler: .ranger, name: "我", level: 4,
                                                                       loadout: ArenaLoadout.basic(.ranger, level: 4), demo: .result))
        case "arenaStory": ArenaStoryView(brawler: .knight, partners: [.ranger, .mage], name: "我")
        case "arenaTalk": ArenaStoryView(brawler: .knight, partners: [.ranger, .mage], name: "我", showIntro: true)
        case "arenaSeason": NavigationStack { ArenaSeasonSheet() }
        case "wumindAdminBilling": WuMindAdminBillingView()
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
