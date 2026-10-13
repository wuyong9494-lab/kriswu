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
                    await store.refreshHolidaysIfNeeded()
                    await store.syncIfStale()
                    await store.sendDueWeChatReminders()
                    await store.rescheduleNotifications()
                    store.autoBackupIfNeeded()
                }
            case .background:
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

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
}

struct RootView: View {
    enum Tab: String, CaseIterable { case today, calendar, stats, site, settings }
    @EnvironmentObject private var store: AppStore
    @State private var tab: Tab
    /// 从「备忘录」等分享进来的录音存好后打开工作留痕；控制中心、操作按钮、小组件来的拍照 / 录音 / 记一笔
    @State private var rootSheet: RootSheet?
    @State private var camera = false
    @State private var tabBarTop: CGFloat = .infinity
    @State private var inReviewDemo = UserDefaults.standard.bool(forKey: AppStore.demoKey)
    @Environment(\.scenePhase) private var scenePhase

    enum RootSheet: String, Identifiable {
        case workLog, record, note, rosterLog, teamChanges, whatsNew
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
            if url.isFileURL {
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
            }
        }
        // 控制中心、操作按钮、快捷指令：动作写在 App Group 里，App 打开后接着做
        .onReceive(NotificationCenter.default.publisher(for: .pendingCapture)) { _ in
            if let action = PendingCapture.take() { startCapture(action) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRoute)) { _ in openPendingRoute() }
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
            }
        }
    }

    @ViewBuilder
    private func page<V: View>(_ t: Tab, @ViewBuilder content: () -> V) -> some View {
        let selected = tab == t
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
        default: TodayView()
        }
    }
}
