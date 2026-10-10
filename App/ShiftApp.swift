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
                    _ = await NotificationService.requestAuthorization()
                    await store.rescheduleNotifications()
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                Task {
                    await store.syncIfStale()
                    await store.sendDueWeChatReminders()
                    await store.rescheduleNotifications()
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
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("今天", systemImage: "sun.max") }
            CalendarView()
                .tabItem { Label("日历", systemImage: "calendar") }
            SiteView()
                .tabItem { Label("网站", systemImage: "globe") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
