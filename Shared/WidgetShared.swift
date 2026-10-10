import SwiftUI
import WidgetKit

/// App 和小组件共用的数据：App 每次同步/修改排班后写入，小组件读取后显示今天、明天的分工。
struct WidgetDay: Codable, Hashable {
    var date: String        // yyyy-MM-dd
    var title: String       // 组D、组A+组E、无分工…
    var emoji: String
    var colorHex: String
}

struct WidgetSnapshot: Codable {
    var days: [WidgetDay]
    var updated: Date
}

enum WidgetStore {
    static let kind = "ShiftWidget"
    private static let defaultGroup = "group.com.kriswu.shiftreminder"

    /// App Group 名称。SideStore / AltStore 安装时会给 App Group 改名，并写在主 App 的 Info.plist 的 ALTAppGroups 里。
    static var groupID: String {
        for bundle in [Bundle.main, mainAppBundle].compactMap({ $0 }) {
            if let groups = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String], let first = groups.first {
                return first
            }
        }
        return defaultGroup
    }

    /// 在小组件里找到主 App 的 bundle（ShiftReminder.app/PlugIns/ShiftWidget.appex）。
    private static var mainAppBundle: Bundle? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "appex" else { return nil }
        return Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent())
    }

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("widget.json")
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func key(for date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x8E8E93
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
