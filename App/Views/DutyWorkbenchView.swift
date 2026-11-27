import SwiftUI
import CryptoKit
import UserNotifications

/// Shows the action for the current duty window alongside the handoff and checklist.
struct DutyWorkbenchCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationStatus: UNAuthorizationStatus?
    let now: Date

    private func telemetryNames(on day: DayKey) -> String? {
        let names = store.dayRoster(day)
            .filter { DutyWorkbench.isStandardTelemetryPost($0.post, matcher: store.matcher) }
            .flatMap(\.names)
        return names.isEmpty ? nil : names.joined(separator: "、")
    }

    var body: some View {
        let today = DayKey(date: now, calendar: .app)
        let knownSchedule = store.mySchedule.filter { day, _ in
            day <= today || store.schedule[day] != nil || store.publishedDays.contains(day)
        }
        let active = DutyWorkbench.current(now: now, schedule: knownSchedule, matcher: store.matcher,
                                           handover: store.settings.dutyStart, calendar: .app)
        let previous = DutyWorkbench.window(on: today.adding(days: -1), schedule: knownSchedule,
                                             matcher: store.matcher, handover: store.settings.dutyStart, calendar: .app)
            .flatMap { $0.end <= now ? $0 : nil }
        let next = DutyWorkbench.next(atOrAfter: active?.end ?? now, schedule: knownSchedule,
                                      matcher: store.matcher, handover: store.settings.dutyStart, calendar: .app)
        let taskDay = active?.day ?? today
        let tasks = store.liveTaskRecord(on: taskDay)
        let handoff = active ?? previous
        let canPrepareHandoff = handoff.map(allPlanRecipientsConfirmed) ?? false
        let todayTelemetry = telemetryNames(on: today)
        let tomorrowTelemetry = telemetryNames(on: today.adding(days: 1))

        VStack(alignment: .leading, spacing: DS.Space.s) {
            if let active {
                status(title: "当前值班时段", value: "\(dutyStamp(active.start)) – \(dutyStamp(active.end))")
            } else if let first = tasks?.todo.first {
                status(title: "待办", value: first)
            } else if let next {
                status(title: "下次接班", value: "\(dutyStamp(next.start)) · \(next.label)")
            }

            Group {
                if let handoff, canPrepareHandoff {
                    NavigationLink {
                        DutyHandoffView(window: handoff, personScope: store.myRosterName ?? store.settings.aliases.first ?? "")
                    } label: {
                        Label(active == nil ? "上一班交班卡" : "准备交班", systemImage: "list.clipboard")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("today.workbench.handoff")
                } else {
                    NavigationLink {
                        PassPlanView()
                    } label: {
                        Label(store.passPlan.rows.isEmpty ? "导入数传计划" : "复核数传计划", systemImage: "paperplane")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("today.workbench.plan")
                }
            }
            .font(DS.Font.headline)
            .buttonStyle(.borderedProminent)

            if let handoff, !canPrepareHandoff {
                workLink("交班卡", "list.clipboard") {
                    DutyHandoffView(window: handoff, personScope: store.myRosterName ?? store.settings.aliases.first ?? "")
                }
                .accessibilityIdentifier("today.workbench.handoff")
            } else {
                workLink("值班表", "tablecells") { DayRosterView(day: today) }
            }

            if let tasks, !tasks.todo.isEmpty {
                workLink("有 \(tasks.todo.count) 项本机清单未勾选", "checklist") {
                    DutyChecklistView(day: taskDay)
                }
            }
            if todayTelemetry != nil || tomorrowTelemetry != nil {
                Divider()
                LabeledContent("今天遥测", value: todayTelemetry ?? "—")
                    .font(DS.Font.callout)
                if let tomorrowTelemetry {
                    LabeledContent("明天遥测", value: tomorrowTelemetry)
                        .font(DS.Font.callout)
                }
            }
            if notificationStatus == .denied {
                workLink("系统通知已关闭 · 查看诊断", "bell.slash") { DiagnosticsView() }
            }
            if store.syncLooksBroken {
                workLink("排班同步可能过期 · 查看诊断", "exclamationmark.arrow.triangle.2.circlepath") { DiagnosticsView() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            let status = await NotificationService.authorizationStatus()
            guard !Task.isCancelled else { return }
            notificationStatus = status
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.dutyWorkbench")
    }

    private func allPlanRecipientsConfirmed(in window: DutyWorkbench.Window) -> Bool {
        let rules = store.settings.passPlanOperators.filter { !$0.name.isEmpty }
        let skipped = Set(store.settings.passPlanSkipped)
        let groups = PassPlan.grouped(store.passPlan.rows, rules: rules, batchRoutes: store.passPlan.batchRoutes)
        guard !groups.contains(where: { $0.name == PassPlan.unassigned }) else { return false }
        let recipients = Set(groups.map(\.name)).subtracting(skipped)
        let verified = Set(DutyWorkbench.confirmed(store.passPlan.confirmedReceipts, in: window, now: Date()))
        return !recipients.isEmpty && recipients.isSubset(of: verified)
    }

    private func status(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(title).font(DS.Font.caption).foregroundStyle(.secondary)
            Text(value).font(DS.Font.headline).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func workLink<Destination: View>(_ title: String, _ image: String,
                                             @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack {
                Label(title, systemImage: image)
                    .font(DS.Font.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Space.xs)
                Image(systemName: "chevron.right").font(DS.Font.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DutyChecklistView: View {
    let day: DayKey

    var body: some View {
        ScrollView { TaskChecklistCard(day: day).padding() }
            .appBackground()
            .navigationTitle("组别任务清单")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct DutyHandoffView: View {
    @EnvironmentObject private var store: AppStore
    @State private var memo = DutyHandoffMemo()
    @State private var savedMemo = DutyHandoffMemo()
    @State private var memoStatus: String?
    @State private var memoReady = false
    let window: DutyWorkbench.Window
    let personScope: String

    private var endDay: DayKey { DayKey(date: window.end, calendar: .app) }

    var body: some View {
        List {
            Section {
                LabeledContent("排班开始", value: dutyStamp(window.start))
                LabeledContent("排班结束", value: dutyStamp(window.end))
            } header: {
                Text("\(window.label) · \(Date() < window.end ? "值班中" : "已下班")")
            } footer: {
                Text("时间来自本机排班和接班设置，实际签到请以值班记录为准。")
            }
            outstanding
            nextSection
            planSection
            confirmationSection
        }
        .appList()
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                AppSaveToolbarButton(isDisabled: !memoReady || memo.normalized == savedMemo,
                                     accessibilityID: "duty.handoff.save", action: saveMemo)
            }
        }
        .navigationTitle("交班卡")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(window.day.description)|\(personScope)") { loadMemo() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("duty.handoff")
    }

    private var outstanding: some View {
        Section("未完成") {
            if let tasks = store.taskRecord(on: window.day) {
                if tasks.todo.isEmpty {
                    Text("本机清单没有未勾选项。")
                } else {
                    ForEach(tasks.todo.indices, id: \.self) { i in
                        Label(tasks.todo[i], systemImage: "circle")
                    }
                }
                NavigationLink("打开本班任务清单") { DutyChecklistView(day: window.day) }
                    .accessibilityIdentifier("duty.handoff.checklist")
            } else {
                Text("本班无可用任务清单，不能判断是否有未完成事项。")
                    .foregroundStyle(.secondary)
            }
            if !savedMemo.outstanding.isEmpty {
                Text("本机手录：\(savedMemo.outstanding)")
            }
        }
    }

    private var nextSection: some View {
        let upcoming = store.publishedDays.contains(endDay)
            ? store.dayRoster(endDay).filter { DutyWorkbench.isStandardTelemetryPost($0.post, matcher: store.matcher) }
            : []
        let evidence = upcoming.flatMap(\.names).filter { !$0.isEmpty }
        return Section {
            if evidence.isEmpty {
                Text("未找到已发布的下一班遥测安排；不推测接班人或其他任务的开始时刻。")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("排班表中下一班开始", value: dutyStamp(window.end))
                Text("排班人员：" + evidence.joined(separator: "、"))
                NavigationLink("查看原排班") { DayRosterView(day: endDay) }
            }
        } header: {
            Text(Date() < window.end ? "下班后即将开始" : "下班后的排班")
        }
    }

    private var planSection: some View {
        let now = Date()
        let changes = DutyWorkbench.changes(store.rosterLog.filter { store.isMe($0.name) }, in: window, now: now)
        let edited = store.passPlan.changesRecordedAt.flatMap { window.contains($0) && $0 <= now ? $0 : nil }
        let receipts = DutyWorkbench.confirmed(store.passPlan.confirmedReceipts, in: window, now: now)
        return Section {
            if let edited {
                Text("\(dutyStamp(edited)) · 本机会话记录到数传计划内容编辑")
                Text("仅当前这一批，不代表已发布、已送达或由谁编辑。").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("当前批次没有本班可确认的数传计划编辑记录。切换批次或重开 App 后的历史不在这里。")
                    .foregroundStyle(.secondary)
            }
            if !savedMemo.planChanges.isEmpty { Text("本机手录：\(savedMemo.planChanges)") }
            if !changes.isEmpty {
                DisclosureGroup("同步发现的本人排班变动 · \(changes.count) 条（非数传计划）") {
                    ForEach(changes.indices, id: \.self) { i in
                        let item = changes[i]
                        Text("\(dutyStamp(item.at)) 发现 \(item.day.description)：\(item.old ?? "空白") → \(item.new ?? "空白")")
                            .font(.footnote)
                    }
                }
            }
            if !receipts.isEmpty {
                Text("当前批次人工确认收到：" + receipts.joined(separator: "、"))
            }
            NavigationLink("查看数传计划") { PassPlanView() }
        } header: {
            Text("本班改过的计划")
        }
    }

    private var confirmationSection: some View {
        Section {
            if !savedMemo.anomalies.isEmpty {
                Label("本机已记异常：\(savedMemo.anomalies)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                Text("没有自动签到或接班回执；未记录不等于无异常。")
                    .foregroundStyle(.secondary)
            }
            TextField("补记未完成事项", text: $memo.outstanding, axis: .vertical).lineLimit(1...4)
            TextField("补记本班计划变更", text: $memo.planChanges, axis: .vertical).lineLimit(1...4)
            TextField("补记接班核对异常", text: $memo.anomalies, axis: .vertical).lineLimit(1...4)
            if !memoReady {
                Button("重新读取本机记录", action: loadMemo)
            }
            if let memoStatus { Text(memoStatus).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("接班确认异常")
        } footer: {
            Text("手录仅供本机查看，不会替他人确认，不会发送给下一班或上传 DeepSeek。")
        }
    }

    private func loadMemo() {
        do {
            memo = try DutyHandoffMemoStorage.read(window.day, personScope: personScope)
            savedMemo = memo
            memoStatus = nil
            memoReady = true
        } catch {
            memoReady = false
            memoStatus = "本机记录暂时无法读取。未覆盖原记录。"
        }
    }

    private func saveMemo() {
        guard memoReady else { return }
        let value = memo.normalized
        do {
            try DutyHandoffMemoStorage.save(value, day: window.day, personScope: personScope)
            savedMemo = value
            memo = value
            memoStatus = "已在这台设备保存。"
        } catch {
            memoStatus = "未保存：每栏最多 2000 字节，并请确认设备已解锁。"
        }
    }
}

private func dutyStamp(_ date: Date) -> String {
    let parts = Calendar.app.dateComponents([.month, .day, .hour, .minute], from: date)
    return "\(parts.month ?? 0)/\(parts.day ?? 0) " + String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
}

private struct DutyHandoffMemo: Codable, Equatable {
    var outstanding = ""
    var planChanges = ""
    var anomalies = ""

    var normalized: Self {
        .init(outstanding: outstanding.trimmingCharacters(in: .whitespacesAndNewlines),
              planChanges: planChanges.trimmingCharacters(in: .whitespacesAndNewlines),
              anomalies: anomalies.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private enum DutyHandoffMemoStorage {
    private static func file(_ day: DayKey, personScope: String, create: Bool) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: create)
        var folder = root.appendingPathComponent("DutyHandoffLocal", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
        }
        let digest = SHA256.hash(data: Data(personScope.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(day.description + "-" + digest + ".json")
    }

    static func read(_ day: DayKey, personScope: String) throws -> DutyHandoffMemo {
        let url = try file(day, personScope: personScope, create: true)
        do {
            return try JSONDecoder().decode(DutyHandoffMemo.self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return DutyHandoffMemo()
        }
    }

    static func save(_ value: DutyHandoffMemo, day: DayKey, personScope: String) throws {
        guard [value.outstanding, value.planChanges, value.anomalies].allSatisfy({ $0.utf8.count <= 2_000 }) else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let url = try file(day, personScope: personScope, create: true)
        if value == DutyHandoffMemo() {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } else {
            try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
}
