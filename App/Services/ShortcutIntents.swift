import AppIntents

/// iPhone 不允许 App 自己准点在后台运行，但「快捷指令 › 自动化」可以每天准点运行一个动作。
/// 这里提供「发送值班提醒到微信」动作，在自动化里设成 7:30 / 20:30 运行，微信就能准时收到。
enum ReminderDay: String, AppEnum {
    case today
    case tomorrow

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "哪天")
    static var caseDisplayRepresentations: [ReminderDay: DisplayRepresentation] = [
        .today: "今天",
        .tomorrow: "明天",
    ]
}

/// 在「快捷指令 › 自动化」里设成每天 7:00 运行，保证 7:30 的提醒用的是最新排班。
struct SyncScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "同步排班"
    static var description = IntentDescription("从值班网站取最新排班并更新提醒、小组件。可以在「快捷指令 › 自动化」里设成每天早上定时运行。")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        guard store.canSync else { return .result(dialog: "还没有设置排班网址") }
        await store.sync(full: false)
        await store.rescheduleNotifications()
        return .result(dialog: "\(store.settings.lastSyncMessage ?? "已同步")")
    }
}

struct SendWeChatReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "发送值班提醒到微信"
    static var description = IntentDescription("把今天或明天的分工发到微信（PushPlus）。在「快捷指令 › 自动化」里设成每天定时运行，就能准时收到。")

    @Parameter(title: "哪天", default: .today)
    var day: ReminderDay

    static var parameterSummary: some ParameterSummary {
        Summary("发送\(\.$day)的分工到微信")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await AppStore.shared.sendWeChatReminder(morning: day == .today)
        return .result(dialog: "\(text)")
    }
}
