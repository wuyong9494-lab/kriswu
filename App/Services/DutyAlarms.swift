import CryptoKit
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
            let defaults = UserDefaults.standard
            let old = Set((defaults.stringArray(forKey: idsKey) ?? []).compactMap(UUID.init(uuidString:)))
            let existing = try? Set(manager.alarms.map(\.id))
            let upcoming = alarms.filter { $0.date > Date() }
            // Loss of permission must not silently discard the IDs needed for
            // cleanup if the person enables AlarmKit again later.
            guard upcoming.isEmpty || manager.authorizationState == .authorized else { return }
            var registered = old
            var desired = Set<UUID>()
            var failed = false
            for alarm in upcoming {
                let id = stableID(for: alarm.date, title: alarm.title)
                guard desired.insert(id).inserted else { continue }
                // A previous scheduling call may have been suspended after the
                // daemon accepted its alarm. Reuse it rather than duplicating it.
                if existing?.contains(id) == true || (existing == nil && old.contains(id)) {
                    registered.insert(id)
                    continue
                }
                let stop = AlarmButton(text: "起来了", textColor: .white, systemImageName: "sun.max.fill")
                let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: alarm.title), stopButton: stop)
                let attributes = AlarmAttributes<DutyAlarmMetadata>(presentation: AlarmPresentation(alert: alert),
                                                                    metadata: DutyAlarmMetadata(), tintColor: .indigo)
                let configuration = AlarmManager.AlarmConfiguration<DutyAlarmMetadata>(
                    countdownDuration: nil, schedule: .fixed(alarm.date), attributes: attributes)
                do {
                    _ = try await manager.schedule(id: id, configuration: configuration)
                    registered.insert(id)
                    // Save each successful alarm: suspension at any point can
                    // still be reconciled on the next foreground run.
                    defaults.set(registered.map(\.uuidString).sorted(), forKey: idsKey)
                } catch { failed = true }
            }
            // Register all replacement alarms first. When even one fails, keep
            // the previous generation instead of leaving duty mornings silent.
            if !failed {
                for id in old.subtracting(desired) {
                    if existing?.contains(id) == false {
                        registered.remove(id)
                        continue
                    }
                    do {
                        try manager.cancel(id: id)
                        registered.remove(id)
                    } catch { /* Keep the ID so another refresh can retry. */ }
                }
            }
            defaults.set(registered.map(\.uuidString).sorted(), forKey: idsKey)
        }
        #endif
    }

    #if canImport(AlarmKit)
    /// The same duty slot gets the same identifier across retries and launches.
    private static func stableID(for date: Date, title: String) -> UUID {
        let payload = Data("duty-alarm-v1|\(Int(date.timeIntervalSince1970))|\(title)".utf8)
        let bytes = Array(SHA256.hash(data: payload))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    #endif
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct DutyAlarmMetadata: AlarmMetadata {}
#endif
