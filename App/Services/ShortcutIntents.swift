import AppIntents

/// iPhone 不允许 App 自己准点在后台运行，但「快捷指令 › 自动化」可以每天准点运行一个动作。
/// 这里提供「发送值班提醒到微信」动作，在自动化里设成 7:30 / 20:30 运行，微信就能准时收到。
enum ReminderDay: String, AppEnum {
    case today
    case tomorrow
    case week

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "哪天")
    static var caseDisplayRepresentations: [ReminderDay: DisplayRepresentation] = [
        .today: "今天",
        .tomorrow: "明天",
        .week: "下周",
    ]
}

/// 在「快捷指令 › 自动化」里设成每天 7:00 运行，保证 7:30 的提醒用的是最新排班。
struct SyncScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "同步排班"
    static var description = IntentDescription("从值班网站取最新排班，发现变动马上通知，并更新提醒、小组件。iPhone 后台运行 App 的时间不固定，在「快捷指令 › 自动化」里每天设几个时间（如 9:00、12:00、15:00、18:00）运行它，排班变动就能及时知道。")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        guard store.canSync else { return .result(dialog: "还没有设置排班网址") }
        await store.sync(full: false, source: "快捷指令")
        await store.rescheduleNotifications()
        store.autoBackupIfNeeded()
        return .result(dialog: "\(store.settings.lastSyncMessage ?? "已同步")")
    }
}

struct SendWeChatReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "发送值班提醒到微信"
    static var description = IntentDescription("把今天、明天或接下来一周的分工发到微信（PushPlus）。在「快捷指令 › 自动化」里设成每天定时运行，就能准时收到。")

    @Parameter(title: "哪天", default: .today)
    var day: ReminderDay

    static var parameterSummary: some ParameterSummary {
        Summary("发送\(\.$day)的分工到微信")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text: String
        if day == .week {
            text = await AppStore.shared.sendWeChatWeek()
        } else {
            text = await AppStore.shared.sendWeChatReminder(morning: day == .today)
        }
        return .result(dialog: "\(text)")
    }
}

// MARK: - 问 Siri

enum AskDay: String, AppEnum {
    case today, tomorrow, dayAfter

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "哪天")
    static var caseDisplayRepresentations: [AskDay: DisplayRepresentation] = [
        .today: "今天",
        .tomorrow: "明天",
        .dayAfter: "后天",
    ]

    var offset: Int { self == .today ? 0 : (self == .tomorrow ? 1 : 2) }
    var label: String { self == .today ? "今天" : (self == .tomorrow ? "明天" : "后天") }
}

/// 「嘿 Siri，值班提醒明天什么班」
struct AskShiftIntent: AppIntent {
    static var title: LocalizedStringResource = "我什么班"
    static var description = IntentDescription("说出今天、明天或后天你的分工和组别工作内容。")

    @Parameter(title: "哪天", default: .tomorrow)
    var day: AskDay

    static var parameterSummary: some ParameterSummary { Summary("我\(\.$day)什么班") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = AppStore.shared
        let date = DayKey.today.adding(days: day.offset)
        let text: String
        if let raw = store.shift(on: date) {
            let name = store.matcher.displayName(raw)
            let notes = store.notes(for: raw).map { "\($0.group)：\($0.note)" }.joined(separator: "；")
            text = "\(day.label)（\(date.dateText)）是\(name)。" + (notes.isEmpty ? "" : notes)
        } else {
            text = store.isCovered(date) ? "\(day.label)（\(date.dateText)）没给你排班。" : "\(day.label)（\(date.dateText)）还没有排班数据。"
        }
        return .result(value: text, dialog: "\(text)")
    }
}

/// 「值班提醒今天谁值遥测」
struct WhoOnDutyIntent: AppIntent {
    static var title: LocalizedStringResource = "谁值遥测"
    static var description = IntentDescription("说出今天、明天或后天值遥测的人（来自全员排班）。")

    @Parameter(title: "哪天", default: .today)
    var day: AskDay

    static var parameterSummary: some ParameterSummary { Summary("\(\.$day)谁值遥测") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = AppStore.shared
        let date = DayKey.today.adding(days: day.offset)
        let names = store.dayRoster(date).filter { WorkloadCounter.isDuty($0.post) }.flatMap(\.names)
        let text = names.isEmpty ? "\(day.label)（\(date.dateText)）还没看到遥测的安排。"
            : "\(day.label)（\(date.dateText)）值遥测的是\(names.joined(separator: "、"))。"
        return .result(value: text, dialog: "\(text)")
    }
}

/// 「值班提醒我下次遥测哪天」
struct NextDutyIntent: AppIntent {
    static var title: LocalizedStringResource = "我下次遥测"
    static var description = IntentDescription("说出你下一次遥测：网站已经排好就说排好的日子，没排就按过去的间隔估计。")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = AppStore.shared
        let today = DayKey.today
        let text: String
        if let next = store.schedule.filter({ $0.key > today && WorkloadCounter.isDuty(store.matcher.displayName($0.value)) }).keys.min() {
            text = "你下次遥测是\(next.dateText)。"
        } else if let me = store.myRosterName,
                  let f = DutyForecaster.forecast(roster: store.roster, today: today, matcher: store.matcher, calendar: .app)
                    .first(where: { $0.name == me }), let p = f.predicted {
            text = "网站还没排，按过去的间隔估计大约是\(p.dateText)。"
        } else {
            text = "还看不出你下次遥测是哪天。"
        }
        return .result(value: text, dialog: "\(text)")
    }
}

/// 遥测下班后补觉：给「快捷指令 › 自动化」判断要不要打开勿扰 / 睡眠专注模式
struct RestAfterDutyIntent: AppIntent {
    static var title: LocalizedStringResource = "是不是遥测后补觉时间"
    static var description = IntentDescription("昨天值了遥测、现在还没到设定的补觉结束时间时返回「是」。在自动化里每天 8:40 运行：如果是，就打开「勿扰模式」或「睡眠」专注模式。")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let store = AppStore.shared
        let resting = store.isRestingAfterDuty()
        let until = store.settings.restFocusUntil.text
        return .result(value: resting, dialog: resting ? "是，补觉到 \(until)" : "不是")
    }
}

struct ShiftShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskShiftIntent(), phrases: [
            "\(.applicationName)\(\.$day)什么班",
            "\(.applicationName)我\(\.$day)上什么班",
            "问\(.applicationName)\(\.$day)什么班",
        ])
        AppShortcut(intent: WhoOnDutyIntent(), phrases: [
            "\(.applicationName)\(\.$day)谁值遥测",
            "\(.applicationName)\(\.$day)谁遥测",
        ])
        AppShortcut(intent: NextDutyIntent(), phrases: [
            "\(.applicationName)我下次遥测",
            "\(.applicationName)下次遥测哪天",
        ])
        AppShortcut(intent: SyncScheduleIntent(), phrases: [
            "\(.applicationName)同步排班",
        ])
    }
}
