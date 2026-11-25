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

        // Record a resumable Loops & Graphs DAG directly in the shared WuMindAgentCoordinator ledger
        // so disconnected sources (e.g. Leave/Trip) can be resumed later without re-running completed roster steps.
        let rosterCall = execution.toolCalls.first(where: { $0.toolName == "duty_roster_lookup" })
        let restCall = execution.toolCalls.first(where: { $0.toolName == "duty_resting_groups_lookup" })
        let leaveCall = execution.toolCalls.first(where: { $0.toolName == "duty_leave_records_lookup" })
        let tripCall = execution.toolCalls.first(where: { $0.toolName == "duty_trip_records_lookup" })

        func mapStatus(_ s: WuMindDutyQueryEngine.QueryStatus?) -> WuMindGraphNodeStatus {
            switch s {
            case .confirmed, .checkedEmpty: return .completed
            case .unauthorizedOrUnconnected: return .unconnectedOrUnauthorized
            case .queryFailed: return .failed
            case nil: return .cachedUnchanged
            }
        }

        let liveGraph = WuMindTaskGraph(
            kind: .dutyQuery,
            title: "值班可恢复任务图：\(String(prompt.prefix(22)))",
            dataBoundary: .localIntranetOnly,
            activeModelLabel: "本机内网任务图（独立于 \(activeModelLabel)）",
            nodes: [
                WuMindGraphNode(
                    id: "resolve_date",
                    title: "解析业务时区日期",
                    dependencies: [],
                    inputSummary: "业务日期 \(execution.intent.resolvedDate.description) · 时区 \(execution.intent.businessTimezoneID)",
                    sourceLabel: "App 业务日历",
                    status: .completed,
                    executionCount: 1,
                    lastLoopAttempts: 1,
                    parallelWaveIndex: 0,
                    outputPayload: "\(execution.intent.resolvedDate.description)|\(execution.intent.businessTimezoneID)",
                    outputHash: stableDigest("\(execution.intent.resolvedDate.description)|\(execution.intent.businessTimezoneID)"),
                    validatorSummary: "日期与业务时区校验通过",
                    updatedAt: now
                ),
                WuMindGraphNode(
                    id: "fetch_roster",
                    title: "查询全员排班与临时调班",
                    dependencies: ["resolve_date"],
                    inputSummary: "全员排班 + TeamChange 调班记录",
                    sourceLabel: rosterCall?.sourceName ?? "App 全员排班表",
                    status: mapStatus(rosterCall?.status),
                    executionCount: rosterCall == nil ? 0 : 1,
                    lastLoopAttempts: rosterCall == nil ? 0 : 1,
                    parallelWaveIndex: 1,
                    outputPayload: execution.section(for: .onDuty)?.headline ?? "",
                    outputHash: stableDigest(execution.section(for: .onDuty)?.headline ?? ""),
                    validatorSummary: rosterCall?.summary ?? "已完成",
                    updatedAt: now
                ),
                WuMindGraphNode(
                    id: "fetch_rotation_rules",
                    title: "读取轮班组别目录与规则",
                    dependencies: ["resolve_date"],
                    inputSummary: "已知轮班组（\(snapshot.activeGroupCatalog.count) 组）",
                    sourceLabel: "App 轮班规则引擎",
                    status: .completed,
                    executionCount: 1,
                    lastLoopAttempts: 1,
                    parallelWaveIndex: 1,
                    outputPayload: snapshot.activeGroupCatalog.joined(separator: "、"),
                    outputHash: stableDigest(snapshot.activeGroupCatalog.joined(separator: "、")),
                    validatorSummary: snapshot.rotationRulesSufficient ? "规则完备" : "规则不足，不推定无人休息",
                    updatedAt: now
                ),
                WuMindGraphNode(
                    id: "fetch_leave",
                    title: "查询权威请假记录源",
                    dependencies: ["resolve_date"],
                    inputSummary: "独立只读查询权威请假源",
                    sourceLabel: leaveCall?.sourceName ?? "权威请假记录源",
                    status: mapStatus(leaveCall?.status),
                    executionCount: leaveCall == nil ? 0 : 1,
                    lastLoopAttempts: leaveCall == nil ? 0 : 1,
                    parallelWaveIndex: 1,
                    outputPayload: execution.section(for: .leave)?.headline ?? "",
                    outputHash: stableDigest(execution.section(for: .leave)?.headline ?? ""),
                    validatorSummary: leaveCall?.summary ?? "未查询",
                    errorMessage: leaveCall?.status == .unauthorizedOrUnconnected ? execution.section(for: .leave)?.headline : nil,
                    updatedAt: now
                ),
                WuMindGraphNode(
                    id: "fetch_trip",
                    title: "查询权威出差记录源",
                    dependencies: ["resolve_date"],
                    inputSummary: "独立只读查询权威出差源",
                    sourceLabel: tripCall?.sourceName ?? "权威出差记录源",
                    status: mapStatus(tripCall?.status),
                    executionCount: tripCall == nil ? 0 : 1,
                    lastLoopAttempts: tripCall == nil ? 0 : 1,
                    parallelWaveIndex: 1,
                    outputPayload: execution.section(for: .trip)?.headline ?? "",
                    outputHash: stableDigest(execution.section(for: .trip)?.headline ?? ""),
                    validatorSummary: tripCall?.summary ?? "未查询",
                    errorMessage: tripCall?.status == .unauthorizedOrUnconnected ? execution.section(for: .trip)?.headline : nil,
                    updatedAt: now
                ),
                WuMindGraphNode(
                    id: "calc_resting_groups",
                    title: "推算计划休息组",
                    dependencies: ["fetch_roster", "fetch_rotation_rules"],
                    inputSummary: "等待排班与规则齐备后推算计划休息组",
                    sourceLabel: restCall?.sourceName ?? "排班表 + 轮班规则",
                    status: mapStatus(restCall?.status),
                    executionCount: restCall == nil ? 0 : 1,
                    lastLoopAttempts: restCall == nil ? 0 : 1,
                    parallelWaveIndex: 2,
                    outputPayload: execution.section(for: .restingGroups)?.headline ?? "",
                    outputHash: stableDigest(execution.section(for: .restingGroups)?.headline ?? ""),
                    validatorSummary: restCall?.summary ?? "未查询",
                    updatedAt: now
                ),
                WuMindGraphNode(
                    id: "aggregate_duty_report",
                    title: "按来源与状态汇总答复",
                    dependencies: ["resolve_date", "fetch_roster"],
                    optionalDependencies: ["calc_resting_groups", "fetch_leave", "fetch_trip"],
                    inputSummary: "已确认项优先输出，未接入项明确标注来源与状态",
                    sourceLabel: "本机内网只读聚合器（零外发）",
                    status: .completed,
                    executionCount: 1,
                    lastLoopAttempts: 1,
                    parallelWaveIndex: 3,
                    outputPayload: execution.formattedReport,
                    outputHash: stableDigest(execution.formattedReport),
                    validatorSummary: "已确认项优先输出 · 共 \(execution.toolCalls.count) 次只读查询",
                    updatedAt: now
                ),
            ],
            runGeneration: 1,
            createdAt: now,
            updatedAt: now
        )
        WuMindAgentCoordinator.shared.upsertTaskGraph(liveGraph)
        return execution
    }
}
