import AppIntents
import Foundation
import WidgetKit

/// 工作留痕的快捷入口：控制中心、操作按钮、快捷指令、Siri、小组件都用这几个动作。
/// App 和小组件里都编进了这份代码；动作先把「要做什么」写进 App Group，再打开 App，App 打开后接着做。
enum CaptureAction: String, Codable {
    case photo, record, note

    var url: URL { URL(string: "shiftreminder://capture/\(rawValue)")! }
}

enum PendingCapture {
    private static let key = "pendingCapture"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetStore.groupID) }

    static func set(_ action: CaptureAction) {
        defaults?.set(action.rawValue, forKey: key)
        defaults?.set(Date(), forKey: key + "At")
        // 动作是在 App 里运行的：马上通知界面
        NotificationCenter.default.post(name: .pendingCapture, object: nil)
    }

    /// 取出并清掉（只认 1 分钟内的，免得很久以后打开 App 突然弹出相机）
    static func take() -> CaptureAction? {
        guard let d = defaults, let raw = d.string(forKey: key) else { return nil }
        let at = d.object(forKey: key + "At") as? Date ?? .distantPast
        d.removeObject(forKey: key)
        guard Date().timeIntervalSince(at) < 60 else { return nil }
        return CaptureAction(rawValue: raw)
    }
}

extension Notification.Name {
    static let pendingCapture = Notification.Name("pendingCapture")
    static let pendingTaskToggles = Notification.Name("pendingTaskToggles")
}

struct CapturePhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "拍照留痕"
    static let description = IntentDescription("打开值班提醒的相机，拍完存进工作留痕。")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingCapture.set(.photo)
        return .result()
    }
}

struct CaptureRecordIntent: AppIntent {
    static let title: LocalizedStringResource = "录音留痕"
    static let description = IntentDescription("打开值班提醒马上开始录音，停下就存进工作留痕。")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingCapture.set(.record)
        return .result()
    }
}

struct CaptureNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "记一笔留痕"
    static let description = IntentDescription("打开值班提醒写一笔文字记录。")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingCapture.set(.note)
        return .result()
    }
}

// MARK: - 小组件上勾选今天的任务

/// 小组件上勾的任务先记在 App Group 里（小组件马上显示勾上），App 打开时合并进任务清单。
enum PendingTaskToggles {
    struct Item: Codable, Hashable {
        var day: String
        var group: String
        var key: String
        var done: Bool
    }

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetStore.groupID)?
            .appendingPathComponent("task-toggles.json")
    }

    static func load() -> [Item] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    static func append(_ item: Item) {
        guard let url else { return }
        var list = load().filter { !($0.day == item.day && $0.group == item.group && $0.key == item.key) }
        list.append(item)
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: url, options: .atomic) }
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

@available(iOS 17.0, *)
struct ToggleWidgetTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "勾选今天的任务"
    static let isDiscoverable = false

    @Parameter(title: "日期") var day: String
    @Parameter(title: "组") var group: String
    @Parameter(title: "事项") var key: String

    init() {}

    init(day: String, group: String, key: String) {
        self.day = day
        self.group = group
        self.key = key
    }

    func perform() async throws -> some IntentResult {
        guard var snapshot = WidgetStore.load(), var tasks = snapshot.tasks,
              let i = tasks.firstIndex(where: { $0.day == day && $0.group == group && $0.key == key }) else { return .result() }
        tasks[i].done.toggle()
        snapshot.tasks = tasks
        PendingTaskToggles.append(.init(day: day, group: group, key: key, done: tasks[i].done))
        WidgetStore.save(snapshot)
        NotificationCenter.default.post(name: .pendingTaskToggles, object: nil)
        return .result()
    }
}
