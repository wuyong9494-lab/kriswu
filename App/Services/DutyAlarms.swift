import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

/// 值遥测那天早上响闹钟：iOS 26 起 App 可以设和「时钟」一样的闹钟（静音、专注模式下也会响，要按掉才停）。
/// 每次重排提醒时，把接下来两周值遥测的日子重新登记一遍；没开或系统太旧就什么都不做
enum DutyAlarms {
    private static let idsKey = "dutyAlarmIDs"

    /// 这台手机能不能设闹钟（iOS 26 起）
    static var isSupported: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    /// 打开开关时要一次权限；不给就返回 false
    static func requestPermission() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let manager = AlarmManager.shared
            switch manager.authorizationState {
            case .authorized: return true
            case .denied: return false
            default: return (try? await manager.requestAuthorization()) == .authorized
            }
        }
        #endif
        return false
    }

    /// 重新登记：dates 是要响的时间和闹钟上的标题；传空就是全部取消
    static func reschedule(_ alarms: [(date: Date, title: String)]) async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let manager = AlarmManager.shared
            let old = (UserDefaults.standard.stringArray(forKey: idsKey) ?? []).compactMap(UUID.init(uuidString:))
            for id in old { try? manager.cancel(id: id) }
            guard !alarms.isEmpty, manager.authorizationState == .authorized else {
                UserDefaults.standard.set([String](), forKey: idsKey)
                return
            }
            var ids: [String] = []
            for alarm in alarms where alarm.date > Date() {
                let stop = AlarmButton(text: "起来了", textColor: .white, systemImageName: "sun.max.fill")
                let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: alarm.title), stopButton: stop)
                let attributes = AlarmAttributes<DutyAlarmMetadata>(presentation: AlarmPresentation(alert: alert),
                                                                    metadata: DutyAlarmMetadata(), tintColor: .indigo)
                let configuration = AlarmManager.AlarmConfiguration<DutyAlarmMetadata>(
                    countdownDuration: nil, schedule: .fixed(alarm.date), attributes: attributes)
                let id = UUID()
                if (try? await manager.schedule(id: id, configuration: configuration)) != nil { ids.append(id.uuidString) }
            }
            UserDefaults.standard.set(ids, forKey: idsKey)
        }
        #endif
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct DutyAlarmMetadata: AlarmMetadata {}
#endif
