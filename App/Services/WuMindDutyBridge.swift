import Foundation

/// App-layer read-only bridge between `AppStore.shared` / `AppAccountManager.shared` and
/// `WuMindDutyQueryEngine` (in `ShiftCore`).
///
/// Enforces:
/// - External-user permission isolation (`AppAccountManager.shared.isExternalRestricted` → `.denied`).
/// - Authoritative source separation (planned roster vs leave/trip columns vs real clock-in attendance).
/// - Zero external LLM exfiltration (runs 100% deterministically on-device).
@MainActor
enum WuMindDutyBridge {

    static func buildLiveSnapshot(now: Date = Date()) -> WuMindDutyQueryEngine.DutyDataSnapshot {
        let store = AppStore.shared
        let account = AppAccountManager.shared
        let cal = Calendar.app
        let today = DayKey(date: now, calendar: cal)

        if account.isExternalRestricted {
            return WuMindDutyQueryEngine.DutyDataSnapshot(
                permission: .denied(reason: "当前为外部账号（\(account.accessRole.displayTitle)），受权限边界隔离禁止读取内部排班与值班数据。"),
                businessTimezoneID: cal.timeZone.identifier,
                handoverTime: store.settings.dutyStart,
                matcher: store.matcher,
                rosterSource: .unavailable(reason: "权限拒绝"),
                leaveAuthoritySource: .unavailable(reason: "权限拒绝"),
                tripAuthoritySource: .unavailable(reason: "权限拒绝")
            )
        }

        let hasRoster = !store.roster.isEmpty
        let rosterSource: WuMindDutyQueryEngine.DataSourceStatus = hasRoster
            ? .available(sourceName: "App 本机全员排班表（已同步 \(store.roster.count) 人 / \(store.publishedDays.count) 天）", syncedAt: store.settings.lastSync)
            : .unavailable(reason: "本机尚未同步全员排班表，请先在「今天」页下拉同步一次")

        // Leave & business-trip authority ONLY counts as connected if the roster sync recorded explicit leave columns!
        let hasLeaveColumns = !store.settings.leaveSources.isEmpty
        let leaveSource: WuMindDutyQueryEngine.DataSourceStatus = hasLeaveColumns
            ? .available(sourceName: "排班网站休息/请假列（\(store.settings.leaveSources.joined(separator: "、"))）", syncedAt: store.settings.lastSync)
            : .unavailable(reason: "未接入独立 OA/考勤请假系统，且当前同步的排班源未标注包含请假列")

        let tripSource: WuMindDutyQueryEngine.DataSourceStatus = hasLeaveColumns
            ? .available(sourceName: "排班网站出差/休息列（\(store.settings.leaveSources.joined(separator: "、"))）", syncedAt: store.settings.lastSync)
            : .unavailable(reason: "未接入独立出差审批系统，且当前同步的排班源未标注包含出差列")

        // Build active rotating group catalog from known group notes + historical roster posts
        var catalogSet: [String] = []
        for key in store.groupNotes.keys.sorted() {
            let norm = key.filter { !$0.isWhitespace }.uppercased()
            if norm.hasPrefix("组"), !catalogSet.contains(norm) { catalogSet.append(norm) }
        }
        for (_, days) in store.roster {
            for raw in days.values {
                for name in DayRules.names(raw, matcher: store.matcher) {
                    let norm = name.filter { !$0.isWhitespace }.uppercased()
                    if norm.hasPrefix("组") && norm.count <= 3 && !catalogSet.contains(norm) {
                        catalogSet.append(norm)
                    }
                }
            }
        }
        catalogSet.sort()
        let rotationSufficient = catalogSet.count >= 2 && store.publishedDays.count >= 1

        // Build optional domain summaries for broader Duty App queries
        let workloadSummary: String? = {
            let report = store.workload(year: today.year, month: today.month)
            guard !report.people.isEmpty else { return nil }
            let meLine: String = {
                if let me = report.people.first(where: { store.isMe($0.name) }) {
                    return "本人本月工作量 \(me.workDays) 天（上班 \(me.presentDays) 天、遥测 \(me.dutyDays) 次）"
                }
                return "本月共统计 \(report.people.count) 人（覆盖 \(report.days.count) 天）"
            }()
            return meLine
        }()

        let nextTelemetrySummary: String? = {
            guard let me = store.myRosterName else { return nil }
            let future = store.mySchedule
                .filter { $0.key >= today && WorkloadCounter.isDuty(store.matcher.displayName($0.value)) }
                .sorted { $0.key < $1.key }
            if let first = future.first {
                return "已发布排班中，\(me) 下一次遥测值班为 \(first.key.description)（\(store.matcher.displayName(first.value))）"
            }
            if let rot = store.dutyRotation(forecastDays: 30),
               let nextHit = rot.forecast.first(where: { $0.name == me && $0.day >= today }) {
                return "按排班规律推算，\(me) 下一次可能值遥测的日期为 \(nextHit.day.description)（仅供参考，以正式排班为准）"
            }
            return nil
        }()

        let passPlanSummary: String? = {
            let session = store.passPlan
            guard !session.rows.isEmpty else { return nil }
            let rules = store.settings.passPlanOperators.filter { !$0.name.isEmpty }
            let groups = PassPlan.grouped(session.rows, rules: rules, batchRoutes: session.batchRoutes)
            let sent = session.delivery.handedOff.union(Set(session.confirmedReceipts.keys)).count
            return "当前数传计划共 \(session.rows.count) 条、分成 \(groups.count) 家，已发送/确认 \(sent) 家。"
        }()

        let openMeetings = store.meeting.issues
            .filter { $0.status == .open }
            .prefix(8)
            .map { "[\($0.group)] \($0.text)（首见 \($0.firstWeek.description)）" }

        return WuMindDutyQueryEngine.DutyDataSnapshot(
            permission: .authorized(roleTitle: store.role.title),
            businessTimezoneID: cal.timeZone.identifier,
            handoverTime: store.settings.dutyStart,
            matcher: store.matcher,
            rosterSource: rosterSource,
            leaveAuthoritySource: leaveSource,
            tripAuthoritySource: tripSource,
            actualAttendanceSource: .unavailable(reason: "未接入考勤打卡系统（计划排班不可等同于实际刷卡在岗）"),
            roster: store.roster,
            mySchedule: store.mySchedule,
            publishedDays: store.publishedDays,
            teamChanges: store.settings.teamChanges,
            swapRecords: store.settings.swapRecords,
            restBalance: store.settings.restBalance,
            activeGroupCatalog: catalogSet,
            rotationRulesSufficient: rotationSufficient,
            myName: store.myRosterName,
            explicitLeaveRecords: [],
            explicitTripRecords: [],
            explicitAttendanceRecords: [],
            rosterIncludesLeaveColumns: hasLeaveColumns,
            workloadSummary: workloadSummary,
            nextTelemetrySummary: nextTelemetrySummary,
            passPlanSummary: passPlanSummary,
            meetingOpenSummaries: openMeetings,
            siteNotices: store.settings.siteNotices,
            groupNotes: store.groupNotes,
            workLogTodayCount: WorkLogStore.shared.count(on: today)
        )
    }

    /// Evaluates whether `prompt` is a Duty App business query; if so, executes it deterministically
    /// on-device (ZERO external LLM exfiltration) and logs a unified `WuMindTaskRun`.
    static func tryExecuteLocalDutyQuery(
        prompt: String,
        activeModelLabel: String,
        now: Date = Date()
    ) -> WuMindDutyQueryEngine.DutyQueryExecution? {
        let snapshot = buildLiveSnapshot(now: now)
        guard let execution = WuMindDutyQueryEngine.execute(
            prompt: prompt,
            snapshot: snapshot,
            now: now,
            activeModelLabel: activeModelLabel
        ) else {
            return nil
        }

        // Record in shared WuMindAgentCoordinator task ledger so Duty queries share the exact same
        // audit trail as Background Monitor, Cross-App, and Deliverable Revision agents.
        var run = WuMindTaskRun(
            kind: .dutyQuery,
            title: "值班直查：\(String(prompt.prefix(28)))",
            status: .running,
            activeModelLabel: "本机内网只读引擎（独立于 \(activeModelLabel)）",
            dataBoundary: .localIntranetOnly,
            createdAt: now,
            updatedAt: now
        )
        for (idx, call) in execution.toolCalls.enumerated() {
            run.recordCompletedStep(
                title: call.toolName,
                toolName: call.toolName,
                idempotencyKey: "duty:\(execution.intent.resolvedDate.description):\(call.toolName):\(idx)",
                dataSource: call.sourceName,
                modelUsed: "App 内网只读引擎",
                dataBoundary: .localIntranetOnly,
                outputSummary: "\(call.status.chineseLabel) · \(call.summary)",
                now: now
            )
        }
        run.status = execution.toolCalls.contains(where: { $0.status == .queryFailed }) ? .failed : .completed
        WuMindAgentCoordinator.shared.upsertTaskRun(run)
        return execution
    }
}
