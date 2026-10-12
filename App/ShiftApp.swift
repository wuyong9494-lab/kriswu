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
                Task {
                    await store.syncIfStale()
                    await store.sendDueWeChatReminders()
                    await store.rescheduleNotifications()
                    store.autoBackupIfNeeded()
                }
            case .background:
                BackgroundRefresh.schedule(notBefore: store.nextWeChatReminder)
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
}

struct RootView: View {
    enum Tab: String { case today, calendar, stats, site, settings }
    @EnvironmentObject private var store: AppStore
    @State private var tab: Tab

    init() {
        ChromeAppearance.apply()
        // 截图时用启动参数 -screen xxx 直接打开某一页
        _tab = State(initialValue: Tab(rawValue: UserDefaults.standard.string(forKey: "screen") ?? "") ?? .today)
    }

    var body: some View {
        Group {
            if let screen = UserDefaults.standard.string(forKey: "screen"), Tab(rawValue: screen) == nil {
                NavigationStack { ScreenCatalog.view(screen) }
            } else {
                TabView(selection: $tab) {
                    TodayView()
                        .tabItem { Label("今天", systemImage: "sun.max.fill") }
                        .tag(Tab.today)
                    CalendarView()
                        .tabItem { Label("日历", systemImage: "calendar") }
                        .tag(Tab.calendar)
                    NavigationStack { WorkloadView() }
                        .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }
                        .tag(Tab.stats)
                    SiteView()
                        .tabItem { Label("网站", systemImage: "globe") }
                        .tag(Tab.site)
                    SettingsView()
                        .tabItem { Label("设置", systemImage: "gearshape.fill") }
                        .tag(Tab.settings)
                }
                .onChange(of: tab) { _ in Haptics.select() }
            }
        }
        // 换主题色时整个界面重画一遍
        .id(store.settings.accentTheme)
        .tint(DS.Palette.accent)
        .fontDesign(.rounded)
        .overlay { ToastOverlay() }
    }
}

/// 截图用：按名字打开某一页（只在启动参数 -screen 时用到）
enum ScreenCatalog {
    @MainActor @ViewBuilder
    static func view(_ name: String) -> some View {
        let today = DayKey.today
        switch name {
        case "fairness": FairnessView()
        case "week": WeekRosterView()
        case "swap": SwapHelperView(day: today.adding(days: 1))
        case "ledger": SwapLedgerView()
        case "year": YearStatsView()
        case "summary": YearSummaryView(year: today.year)
        case "check": DataCheckView()
        case "rest": RestTrendView()
        case "forecast": DutyForecastView()
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
