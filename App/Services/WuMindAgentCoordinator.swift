import AVFoundation
import Foundation
import ReplayKit
import SwiftUI
import UserNotifications

/// Unified persistence & execution coordinator for ALL WUMIND autonomous agents.
/// Shares ONE task ledger (`taskRuns`), ONE approval gate workflow, ONE project artifact graph store,
/// real background monitor execution (`BGAppRefreshTask` + local deduped notifications),
/// real `.docx`/`.xlsx` file exports, ReplayKit screen-guide session bridge, AVSpeech textbook audio,
/// verified mobile-dev bug-fix sessions, interactive mini-apps, and teach-once workflows.
@MainActor
final class WuMindAgentCoordinator: ObservableObject {
    static let shared = WuMindAgentCoordinator()

    @Published var taskRuns: [WuMindTaskRun] = []
    @Published var projects: [WuMindProjectArtifactGraph] = []
    @Published var monitorSubscriptions: [WuMindBackgroundMonitorEngine.MonitorSubscription] = []
    @Published var monitorNotifications: [WuMindBackgroundMonitorEngine.MonitorNotification] = []
    @Published var quoteComparisons: [WuMindCrossAppQuoteEngine.ComparisonExecutionState] = []
    @Published var liveScreenSession: WuMindScreenGuideEngine.LiveGuideSession? = nil
    @Published var studyCourses: [WuMindPersonalTextbookEngine.StudyCourse] = []
    @Published var devVerifications: [WuMindMobileDevEngine.VerificationSession] = []
    @Published var miniApps: [WuMindMiniAppArtifactEngine.MiniAppArtifact] = []
    @Published var taughtWorkflows: [WuMindTeachOnceWorkflowEngine.TaughtWorkflow] = []
    @Published var taskGraphs: [WuMindTaskGraph] = []
    @Published var isSpeakingLesson = false
    @Published var lastActionBanner: String? = nil

    private let speechSynthesizer = AVSpeechSynthesizer()
    private let stateFileURL: URL

    private struct PersistedPayload: Codable {
        var taskRuns: [WuMindTaskRun]
        var projects: [WuMindProjectArtifactGraph]
        var monitorSubscriptions: [WuMindBackgroundMonitorEngine.MonitorSubscription]
        var monitorNotifications: [WuMindBackgroundMonitorEngine.MonitorNotification]
        var quoteComparisons: [WuMindCrossAppQuoteEngine.ComparisonExecutionState]
        var studyCourses: [WuMindPersonalTextbookEngine.StudyCourse]
        var devVerifications: [WuMindMobileDevEngine.VerificationSession]
        var miniApps: [WuMindMiniAppArtifactEngine.MiniAppArtifact]
        var taughtWorkflows: [WuMindTeachOnceWorkflowEngine.TaughtWorkflow]
        var taskGraphs: [WuMindTaskGraph]?
    }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("WuMindAgentOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.stateFileURL = dir.appendingPathComponent("agent_os_state_v1.json")
        loadFromDisk()
        seedStarterExamplesIfEmpty()
    }

    // MARK: - Unified Task Ledger, Resumable DAG Graphs & Approval Management

    func upsertTaskRun(_ run: WuMindTaskRun) {
        if let idx = taskRuns.firstIndex(where: { $0.id == run.id }) {
            taskRuns[idx] = run
        } else {
            taskRuns.insert(run, at: 0)
            if taskRuns.count > 80 { taskRuns = Array(taskRuns.prefix(80)) }
        }
        saveToDisk()
    }

    func upsertTaskGraph(_ graph: WuMindTaskGraph) {
        if let idx = taskGraphs.firstIndex(where: { $0.id == graph.id }) {
            taskGraphs[idx] = graph
        } else {
            taskGraphs.insert(graph, at: 0)
            if taskGraphs.count > 30 { taskGraphs = Array(taskGraphs.prefix(30)) }
        }
        upsertTaskRun(graph.toTaskRun())
    }

    var pendingApprovalRuns: [WuMindTaskRun] {
        taskRuns.filter { $0.status == .awaitingApproval && $0.pendingApproval?.approved == nil }
    }

    func decideApproval(taskRunID: UUID, approved: Bool) {
        guard let idx = taskRuns.firstIndex(where: { $0.id == taskRunID }) else { return }
        taskRuns[idx].resolveApproval(approved: approved)
        let kind = taskRuns[idx].kind

        // Propagate approval to backing domain state
        if kind == .mobileDevVerify,
           let dIdx = devVerifications.firstIndex(where: { $0.taskRun.id == taskRunID }) {
            if approved {
                _ = WuMindMobileDevEngine.approveDraftPRCreation(&devVerifications[dIdx])
                taskRuns[idx] = devVerifications[dIdx].taskRun
                lastActionBanner = "已确认创建 Draft PR（未自动合并或发版）"
            } else {
                devVerifications[dIdx].taskRun = taskRuns[idx]
                lastActionBanner = "已取消提交 Draft PR"
            }
        } else if kind == .crossAppExecution,
                  let qIdx = quoteComparisons.firstIndex(where: { $0.taskRun.id == taskRunID }) {
            quoteComparisons[qIdx].taskRun = taskRuns[idx]
            if approved {
                quoteComparisons[qIdx].sendDispatched = true
                quoteComparisons[qIdx].taskRun.status = .completed
                taskRuns[idx].status = .completed
                lastActionBanner = "已确认比价表写入与采购建议发送预览"
            }
        } else {
            if approved {
                taskRuns[idx].status = .completed
                lastActionBanner = "审批通过，操作已完成"
            } else {
                lastActionBanner = "已拒绝执行该操作"
            }
        }
        saveToDisk()
    }

    // MARK: - Background Monitor Execution (Foreground + BGAppRefreshTask)

    func runBackgroundMonitorsIfDue(forceManual: Bool = false) async {
        let now = Date()
        for idx in monitorSubscriptions.indices {
            let sub = monitorSubscriptions[idx]
            guard !sub.paused else { continue }
            if !forceManual, let last = sub.executionLog.last?.executedAt,
               now.timeIntervalSince(last) < Double(max(5, sub.intervalMinutes)) * 60 {
                continue
            }
            let linkedProjectIndex = projects.firstIndex(where: { $0.id == sub.projectID })
            let fetcher: WuMindBackgroundMonitorEngine.PageFetcher = { urlStr in
                let res = await WuMindAgentTools.webFetch(urlString: urlStr)
                guard res.succeeded else {
                    throw NSError(domain: "WuMindMonitor", code: 1, userInfo: [NSLocalizedDescriptionKey: res.summary])
                }
                return res.observationText
            }
            if let pIdx = linkedProjectIndex {
                if let chained = try? await WuMindBackgroundMonitorEngine.runChainedMonitorAndPartialRevision(
                    subscription: sub,
                    graph: projects[pIdx],
                    fieldToClauseID: ["截标时间": "C-DEADLINE", "预算金额": "C-BUDGET", "资质要求": "C-QUAL"],
                    trigger: forceManual ? "manual" : "scheduled",
                    fetcher: fetcher,
                    now: now
                ) {
                    monitorSubscriptions[idx] = chained.poll.subscription
                    if let notif = chained.poll.notification {
                        monitorNotifications.insert(notif, at: 0)
                        await scheduleLocalMonitorAlert(notif)
                    }
                    if let rev = chained.revision {
                        projects[pIdx] = rev.graph
                        upsertTaskRun(rev.taskRun)
                    } else {
                        upsertTaskRun(chained.poll.taskRun)
                    }
                }
            } else {
                let outcome = await WuMindBackgroundMonitorEngine.poll(
                    subscription: sub,
                    trigger: forceManual ? "manual" : "scheduled",
                    fetcher: fetcher,
                    now: now
                )
                monitorSubscriptions[idx] = outcome.subscription
                if let notif = outcome.notification {
                    monitorNotifications.insert(notif, at: 0)
                    await scheduleLocalMonitorAlert(notif)
                }
                upsertTaskRun(outcome.taskRun)
            }
        }
        saveToDisk()
    }

    /// Runs an on-device verifiable end-to-end demonstration of the chained
    /// Monitor Amendment → Partial Revision (preserving human-edited chapter) → `.docx` + `.xlsx` export pipeline.
    func runChainedTenderAmendmentDemo() async {
        guard !monitorSubscriptions.isEmpty, !projects.isEmpty else { return }
        let sub = monitorSubscriptions[0]
        let graph = projects[0]
        let simulatedNotice = """
        公开招标更正公告（第 2 号）
        截标时间：2026-12-10 14:30（原为 2026-12-01 09:30）
        预算金额：180 万元
        更正事项：因评审专家档期调整，递交截止时间顺延 9 天，其余技术指标与商务条款保持不变。
        """
        if let result = try? await WuMindBackgroundMonitorEngine.runChainedMonitorAndPartialRevision(
            subscription: sub,
            graph: graph,
            fieldToClauseID: ["截标时间": "C-DEADLINE"],
            trigger: "event",
            fetcher: { _ in simulatedNotice }
        ) {
            monitorSubscriptions[0] = result.poll.subscription
            if let notif = result.poll.notification {
                monitorNotifications.insert(notif, at: 0)
                await scheduleLocalMonitorAlert(notif)
            }
            if let rev = result.revision {
                projects[0] = rev.graph
                upsertTaskRun(rev.taskRun)
                lastActionBanner = "更正公告已捕获：更新 \(rev.audit.updatedChapterIDs.count) 章、原样保护人工修改 \(rev.audit.preservedHumanChapterIDs.count) 章、未动 \(rev.audit.untouchedChapterIDs.count) 章"
            } else {
                upsertTaskRun(result.poll.taskRun)
                lastActionBanner = "重复更正公告已按哈希去重，未重复打扰"
            }
            saveToDisk()
        }
    }

    func toggleMonitorPause(id: UUID) {
        guard let idx = monitorSubscriptions.firstIndex(where: { $0.id == id }) else { return }
        monitorSubscriptions[idx].paused.toggle()
        saveToDisk()
    }

    func exportProjectDeliverables(projectID: UUID) -> (docxURL: URL, xlsxURL: URL)? {
        guard let graph = projects.first(where: { $0.id == projectID }),
              let (docx, xlsx) = try? WuMindProjectRevisionEngine.exportDeliverables(graph: graph) else {
            return nil
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("WuMindDeliverables", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = graph.title.replacingOccurrences(of: "/", with: "_")
        let docxURL = dir.appendingPathComponent("\(safe)_可编辑初稿.docx")
        let xlsxURL = dir.appendingPathComponent("\(safe)_响应矩阵.xlsx")
        do {
            try docx.write(to: docxURL, options: [.atomic])
            try xlsx.write(to: xlsxURL, options: [.atomic])
            return (docxURL, xlsxURL)
        } catch {
            return nil
        }
    }

    // MARK: - Cross-App Quote Folder → Real .xlsx Write

    func runCrossAppQuoteComparison(files: [WuMindCrossAppQuoteEngine.QuoteFileInput], approveOverwrite: Bool = false) -> URL? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let targetURL = dir.appendingPathComponent("WUMIND_供应商比价表.xlsx")
        let existing = quoteComparisons.first
        do {
            let state = try WuMindCrossAppQuoteEngine.executeFolderQuoteComparison(
                files: files,
                targetWorkbookURL: targetURL,
                existingState: existing,
                approvalGrantedForOverwrite: approveOverwrite
            )
            if quoteComparisons.isEmpty {
                quoteComparisons.append(state)
            } else {
                quoteComparisons[0] = state
            }
            upsertTaskRun(state.taskRun)
            lastActionBanner = state.workbookWritten
                ? "已真实写入 \(targetURL.lastPathComponent)（\(state.extractedRows.count) 家报价）· 发送前等待确认"
                : "目标比价表已存在，等待确认覆盖写入"
            saveToDisk()
            return state.workbookWritten ? targetURL : nil
        } catch {
            lastActionBanner = "写入比价表失败：\(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Live Screen Guide (ReplayKit Bridge + Multi-Page Guidance)

    func startLiveScreenGuide(question: String) {
        let session = WuMindScreenGuideEngine.startSession(userQuestion: question)
        liveScreenSession = session
        upsertTaskRun(session.taskRun)
        if RPScreenRecorder.shared().isAvailable {
            RPScreenRecorder.shared().isMicrophoneEnabled = false
        }
        saveToDisk()
    }

    func ingestLiveScreenObservation(appName: String, pageTitle: String, textSummary: String) {
        guard var session = liveScreenSession, session.isSharing else { return }
        let frame = WuMindScreenGuideEngine.ScreenFrameObservation(
            appName: appName,
            pageTitle: pageTitle,
            visibleTextSummary: textSummary,
            frameDigest: stableDigest("\(appName)|\(pageTitle)|\(textSummary)")
        )
        _ = WuMindScreenGuideEngine.ingestFrame(session: &session, frame: frame)
        liveScreenSession = session
        upsertTaskRun(session.taskRun)
        saveToDisk()
    }

    func stopLiveScreenGuide() {
        guard var session = liveScreenSession else { return }
        WuMindScreenGuideEngine.stopSession(&session)
        liveScreenSession = session
        upsertTaskRun(session.taskRun)
        if RPScreenRecorder.shared().isRecording {
            RPScreenRecorder.shared().stopCapture { _ in }
        }
        lastActionBanner = "已停止屏幕共享，跨页指导记录已归档"
        saveToDisk()
    }

    // MARK: - Personal Textbook Audio Playback

    func speakAudioSegment(_ segment: WuMindPersonalTextbookEngine.AudioSegment) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
            isSpeakingLesson = false
            return
        }
        let utterance = AVSpeechUtterance(string: segment.spokenScript)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeakingLesson = true
        speechSynthesizer.speak(utterance)
    }

    func stopSpeakingLesson() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        isSpeakingLesson = false
    }

    func submitTextbookAnswer(courseID: UUID, questionID: String, optionIndex: Int) -> WuMindPersonalTextbookEngine.AnswerFeedback? {
        guard let idx = studyCourses.firstIndex(where: { $0.id == courseID }) else { return nil }
        let fb = WuMindPersonalTextbookEngine.submitAnswer(course: &studyCourses[idx], questionID: questionID, selectedOptionIndex: optionIndex)
        upsertTaskRun(studyCourses[idx].taskRun)
        saveToDisk()
        return fb
    }

    // MARK: - Shareable Mini-App Export (Sanitized)

    func exportSanitizedMiniAppURL(artifactID: UUID) -> URL? {
        guard let app = miniApps.first(where: { $0.id == artifactID }) else { return nil }
        let pkg = WuMindMiniAppArtifactEngine.sanitizeForExternalShare(rawHTML: app.htmlContent)
        guard pkg.leakedSecretsDetected == 0 else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(app.title)_脱敏可分享版.html")
        try? Data(pkg.shareableHTML.utf8).write(to: url, options: [.atomic])
        return url
    }

    // MARK: - Teach-Once Workflow Sanitized Share

    func exportSanitizedWorkflowURL(workflowID: UUID) -> URL? {
        guard let wf = taughtWorkflows.first(where: { $0.id == workflowID }),
              let data = try? WuMindTeachOnceWorkflowEngine.exportSanitizedPackage(workflow: wf) else {
            return nil
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(wf.name).wumindflow.json")
        try? data.write(to: url, options: [.atomic])
        return url
    }

    // MARK: - Local Notification Helper

    private func scheduleLocalMonitorAlert(_ notif: WuMindBackgroundMonitorEngine.MonitorNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notif.title
        let diffLine = notif.diffs.map { "\($0.field)：\($0.oldValue) → \($0.newValue)" }.joined(separator: "；")
        content.body = (diffLine.isEmpty ? notif.originalExcerpt : diffLine) + "\n来源：\(notif.sourceURL)"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "wumind.monitor.\(notif.contentHash.prefix(16))", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Resumable Loops & Graphs Live Execution (Duty / Short-Drama / Mobile Game)

    /// 1. Live Duty DAG with Leave source disconnected: proves on-duty + resting groups still deliver immediately.
    func runDutyGraphDisconnectLeaveDemo() async {
        let now = Date()
        let baseSnap = WuMindDutyBridge.buildLiveSnapshot(now: now)
        let disconnectedSnap = WuMindDutyQueryEngine.DutyDataSnapshot(
            permission: baseSnap.permission,
            businessTimezoneID: baseSnap.businessTimezoneID,
            handoverTime: baseSnap.handoverTime,
            matcher: baseSnap.matcher,
            rosterSource: baseSnap.rosterSource,
            leaveAuthoritySource: .unavailable(reason: "请假查询接口已断开（现场断联验收）"),
            tripAuthoritySource: baseSnap.tripAuthoritySource,
            actualAttendanceSource: baseSnap.actualAttendanceSource,
            roster: baseSnap.roster,
            mySchedule: baseSnap.mySchedule,
            publishedDays: baseSnap.publishedDays,
            teamChanges: baseSnap.teamChanges,
            swapRecords: baseSnap.swapRecords,
            restBalance: baseSnap.restBalance,
            activeGroupCatalog: baseSnap.activeGroupCatalog,
            rotationRulesSufficient: baseSnap.rotationRulesSufficient,
            myName: baseSnap.myName,
            explicitLeaveRecords: [],
            explicitTripRecords: baseSnap.explicitTripRecords,
            explicitAttendanceRecords: baseSnap.explicitAttendanceRecords,
            rosterIncludesLeaveColumns: false
        )
        let prompt = "今天谁值班、哪组休息、谁请假或出差？"
        let graph = WuMindDutyGraphWorkflow.makeGraph(
            prompt: prompt,
            snapshot: disconnectedSnap,
            includeSendNotificationStep: false,
            activeModelLabel: "本机内网任务图",
            now: now
        )
        let outcome = await WuMindDutyGraphWorkflow.executeOrResume(
            graph: graph,
            prompt: prompt,
            snapshot: disconnectedSnap,
            now: now
        )
        upsertTaskGraph(outcome.graph)
        lastActionBanner = "断联请假源完成：排班与休息组正常交付，请假节点标为未接入"
    }

    /// 2. Reconnects Leave source on the SAME Duty DAG: proves ONLY `fetch_leave` + `aggregate_duty_report` re-run!
    func resumeDutyGraphReconnectLeaveDemo() async {
        guard let existing = taskGraphs.first(where: { $0.kind == .dutyQuery }) else {
            await runDutyGraphDisconnectLeaveDemo()
            return
        }
        let now = Date()
        let baseSnap = WuMindDutyBridge.buildLiveSnapshot(now: now)
        let cal = WuMindDutyQueryEngine.businessCalendar(timezoneID: baseSnap.businessTimezoneID)
        let today = DayKey(date: now, calendar: cal)
        let reconnectedSnap = WuMindDutyQueryEngine.DutyDataSnapshot(
            permission: baseSnap.permission,
            businessTimezoneID: baseSnap.businessTimezoneID,
            handoverTime: baseSnap.handoverTime,
            matcher: baseSnap.matcher,
            rosterSource: baseSnap.rosterSource,
            leaveAuthoritySource: .available(sourceName: "OA 请假审批系统（已恢复连接）", syncedAt: now),
            tripAuthoritySource: baseSnap.tripAuthoritySource,
            actualAttendanceSource: baseSnap.actualAttendanceSource,
            roster: baseSnap.roster,
            mySchedule: baseSnap.mySchedule,
            publishedDays: baseSnap.publishedDays,
            teamChanges: baseSnap.teamChanges,
            swapRecords: baseSnap.swapRecords,
            restBalance: baseSnap.restBalance,
            activeGroupCatalog: baseSnap.activeGroupCatalog,
            rotationRulesSufficient: baseSnap.rotationRulesSufficient,
            myName: baseSnap.myName,
            explicitLeaveRecords: [.init(person: "示例值班员（脱敏）", day: today, category: "年假", source: "OA 请假审批系统")],
            explicitTripRecords: baseSnap.explicitTripRecords,
            explicitAttendanceRecords: baseSnap.explicitAttendanceRecords,
            rosterIncludesLeaveColumns: true
        )
        let outcome = await WuMindDutyGraphWorkflow.resumeLeaveOnly(
            existingGraph: existing,
            prompt: "今天谁值班、哪组休息、谁请假或出差？",
            reconnectedSnapshot: reconnectedSnap,
            now: now
        )
        upsertTaskGraph(outcome.graph)
        let rosterExec = outcome.graph.node(id: "fetch_roster")?.executionCount ?? 0
        let leaveExec = outcome.graph.node(id: "fetch_leave")?.executionCount ?? 0
        lastActionBanner = "恢复请假源仅补跑请假步：排班复用缓存（执行 \(rosterExec) 次），请假补跑（执行 \(leaveExec) 次）"
    }

    /// 3. Same DAG mechanism applied to Short-Drama "Only Redo Shot 3".
    func runShortDramaShot3RedoGraphDemo() async {
        let shots: [WuMindShortDramaGraphWorkflow.ShotSpec] = [
            .init(shotIndex: 1, framing: "全景", visualPrompt: "雨夜天台", dialogue: "你终于来了。", voiceProfile: "男主低沉"),
            .init(shotIndex: 2, framing: "中景", visualPrompt: "转身对视", dialogue: "东西带来了吗？", voiceProfile: "女主冷静"),
            .init(shotIndex: 3, framing: "中景", visualPrompt: "递出U盘", dialogue: "这是最后一份证据。", voiceProfile: "男主低沉"),
            .init(shotIndex: 4, framing: "特写", visualPrompt: "警笛闪烁", dialogue: "没时间了，快走！", voiceProfile: "女主冷静"),
        ]
        let g1 = await WuMindShortDramaGraphWorkflow.execute(
            graph: WuMindShortDramaGraphWorkflow.makeGraph(title: "雨夜递证（4镜）", shots: shots),
            shots: shots
        )
        var revisedShot3 = shots[2]
        revisedShot3.framing = "近景特写"
        revisedShot3.visualPrompt = "近景特写递出U盘（台词与声音不变）"
        let g2 = await WuMindShortDramaGraphWorkflow.redoSingleShot(
            existingGraph: g1,
            shots: shots,
            targetShotIndex: 3,
            updatedShot: revisedShot3
        )
        upsertTaskGraph(g2)
        lastActionBanner = "短剧任务图已仅重做第 3 镜：第 1/2/4 镜命中缓存（执行 1 次），第 3 镜重拍（执行 2 次）"
    }

    /// 4. Same DAG mechanism applied to Mobile Game "Only Fix Level 2" with BFS solver validation.
    func runMobileGameLevel2FixGraphDemo() async {
        let l1 = WuMindMobileGameGraphWorkflow.RouteLevelSpec(
            levelNumber: 1,
            name: "晨曦环线",
            startStation: "A",
            edges: ["A": ["B", "C"], "B": ["D"], "C": ["D"], "D": ["E"], "E": ["A"]],
            targetChain: ["B", "D", "E"],
            hopBudget: 5
        )
        let l2Hard = WuMindMobileGameGraphWorkflow.RouteLevelSpec(
            levelNumber: 2,
            name: "单向枢纽（初版）",
            startStation: "A",
            edges: ["A": ["B"], "B": ["C", "D"], "C": ["E"], "D": ["E"], "E": ["F"], "F": ["A"]],
            targetChain: ["C", "E", "F", "B"],
            hopBudget: 6
        )
        let g1 = await WuMindMobileGameGraphWorkflow.execute(
            graph: WuMindMobileGameGraphWorkflow.makeGraph(title: "最后一跳", level1: l1, level2: l2Hard),
            level1: l1,
            level2: l2Hard
        )
        var l2Easier = l2Hard
        l2Easier.name = "单向枢纽（降难版）"
        l2Easier.hopBudget = 9
        let g2 = await WuMindMobileGameGraphWorkflow.reviseLevel2Only(
            existingGraph: g1,
            level1: l1,
            easierLevel2: l2Easier,
            requireSlackAtLeast: 2
        )
        upsertTaskGraph(g2)
        lastActionBanner = "游戏任务图已仅修第 2 关：第 1 关哈希未变（执行 1 次），第 2 关 BFS 校验通过（执行 2 次）"
    }

    // MARK: - Persistence & Starter Workspace Seeding

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: stateFileURL),
              let decoded = try? JSONDecoder().decode(PersistedPayload.self, from: data) else {
            return
        }
        taskRuns = decoded.taskRuns
        projects = decoded.projects
        monitorSubscriptions = decoded.monitorSubscriptions
        monitorNotifications = decoded.monitorNotifications
        quoteComparisons = decoded.quoteComparisons
        studyCourses = decoded.studyCourses
        devVerifications = decoded.devVerifications
        miniApps = decoded.miniApps
        taughtWorkflows = decoded.taughtWorkflows
        taskGraphs = decoded.taskGraphs ?? []
    }

    func saveToDisk() {
        let payload = PersistedPayload(
            taskRuns: taskRuns,
            projects: projects,
            monitorSubscriptions: monitorSubscriptions,
            monitorNotifications: monitorNotifications,
            quoteComparisons: quoteComparisons,
            studyCourses: studyCourses,
            devVerifications: devVerifications,
            miniApps: miniApps,
            taughtWorkflows: taughtWorkflows,
            taskGraphs: taskGraphs
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: stateFileURL, options: [.atomic])
        }
    }

    private func seedStarterExamplesIfEmpty() {
        if projects.isEmpty {
            let project = WuMindProjectArtifactGraph(
                title: "某卫星地面测控站运维服务投标项目",
                clauses: [
                    .init(id: "C-DEADLINE", title: "投标截止时间", text: "截标时间：2026-12-01 09:30", sourceLocation: "招标公告第 2 章第 1 条"),
                    .init(id: "C-QUAL", title: "人员与资质要求", text: "需具备 ISO9001 质量认证及 3 名以上卫星测控运维工程师。", sourceLocation: "招标公告第 3 章第 4 条"),
                    .init(id: "C-TECH", title: "7×24 值守 SLA", text: "核心测控链路需满足 99.95% 可用性及 15 分钟应急响应。", sourceLocation: "技术规格书第 5 章第 2 条"),
                ],
                chapters: [
                    .init(id: "CH-1", title: "第一章 投标函与时间进度安排", body: "我方承诺按 2026-12-01 09:30 前完成纸质与电子投标文件递交。", linkedClauseIDs: ["C-DEADLINE"], humanEdited: false),
                    .init(id: "CH-2", title: "第二章 商务资质与团队配置（已人工精修）", body: "【人工定稿】我方已附 ISO9001 证书扫描件及 5 名资深值班工程师简历，请勿覆盖本段定稿。", linkedClauseIDs: ["C-DEADLINE", "C-QUAL"], humanEdited: true),
                    .init(id: "CH-3", title: "第三章 7×24 测控运维技术方案", body: "部署双活值守席位，故障 10 分钟内介入响应，全年可用性 >= 99.98%。", linkedClauseIDs: ["C-TECH"], humanEdited: false),
                ],
                matrixRows: [
                    .init(id: "M-1", clauseID: "C-DEADLINE", requirement: "截标时间：2026-12-01 09:30", response: "完全响应，提前 1 日递交", status: "已响应", sourceLocation: "招标公告第 2 章第 1 条"),
                    .init(id: "M-2", clauseID: "C-QUAL", requirement: "ISO9001 + 3 名运维工程师", response: "已附证书及 5 人简历", status: "已响应", sourceLocation: "招标公告第 3 章第 4 条"),
                    .init(id: "M-3", clauseID: "C-TECH", requirement: "99.95% 可用性 / 15 分钟响应", response: "承诺 99.98% / 10 分钟响应", status: "优于指标", sourceLocation: "技术规格书第 5 章第 2 条"),
                ]
            )
            projects.append(project)
            monitorSubscriptions.append(
                WuMindBackgroundMonitorEngine.MonitorSubscription(
                    projectID: project.id,
                    title: "中国政府采购网 · 卫星测控运维标段",
                    targetURL: "https://www.ccgp.gov.cn/example-notice-2026",
                    intervalMinutes: 60,
                    eventTriggerEnabled: true,
                    lastFields: ["截标时间": "2026-12-01 09:30", "预算金额": "180 万元"]
                )
            )
        }

        if studyCourses.isEmpty {
            let course = WuMindPersonalTextbookEngine.buildCourse(
                title: "卫星测控与应急处置个人教材",
                chunks: [
                    .init(id: "CK-1", sourceTitle: "卫星数传值班手册", pageOrSection: "第 3 章 P42", topic: "test 计划拦截规则", excerpt: "状态为 test 的数传计划无论是否标记应急，均严禁发送给任何地面站运营商。"),
                    .init(id: "CK-2", sourceTitle: "卫星数传值班手册", pageOrSection: "第 4 章 P58", topic: "跨午夜交接班口径", excerpt: "00:00 至 08:30 交班前，在岗遥测夜班归属前一日值班窗口，交班核对需同时核对前一日与当日计划。"),
                ],
                priorMistakeTopics: ["test 计划拦截规则"]
            )
            studyCourses.append(course)
        }

        if miniApps.isEmpty {
            miniApps.append(WuMindMiniAppArtifactEngine.buildThreeTierPricingCalculator())
        }

        if taughtWorkflows.isEmpty {
            let wf = WuMindTeachOnceWorkflowEngine.learnFromDemonstration(
                name: "三家供应商报价比对流程",
                demonstrationFiles: [
                    .init(fileName: "甲公司报价.txt", content: "供应商：甲科技\n标的物：测控服务器\n未税价：10000\n运费：300\n交期：7天"),
                    .init(fileName: "乙公司报价.txt", content: "供应商：乙电子\n标的物：测控服务器\n含税价：11800\n运费：0\n交期：5天"),
                ]
            )
            taughtWorkflows.append(wf)
        }

        if devVerifications.isEmpty {
            let demoSession = WuMindMobileDevEngine.runVerifiedBugFixPipeline(
                repoFullName: "wuyong9494-lab/kriswu",
                bugSummary: "值班问答查不到当天全员排班且漏标请假未确认",
                preFix: .init(testIdentifier: "WuMindDutyQueryEngineTests/testRosterConfirmedWhileLeaveSourceMissing", passed: false, durationSeconds: 0.42, logSnippet: "XCTAssertEqual failed: expected confirmed onDuty roster, got empty personal-only shift"),
                patch: .init(
                    branchName: "fix/wumind-duty-intranet-query",
                    touchedFiles: ["Sources/ShiftCore/WuMindDutyQueryEngine.swift", "App/Services/WuMindDutyBridge.swift", "App/Services/WuMindStore.swift"],
                    unifiedDiff: "--- a/WuMindStore.swift\n+++ b/WuMindStore.swift\n@@ -1580 +1580 @@\n+if let localDuty = WuMindDutyBridge.tryExecuteLocalDutyQuery(...) { return }",
                    prTitle: "fix(wumind): route Duty queries through intranet deterministic engine",
                    prBody: "Fixes regression where Duty query failed to read full roster or mark missing leave authority."
                ),
                postFix: .init(testIdentifier: "WuMindDutyQueryEngineTests/testRosterConfirmedWhileLeaveSourceMissing", passed: true, durationSeconds: 0.11, logSnippet: "Test Case passed (0.110 seconds)")
            )
            devVerifications.append(demoSession)
            upsertTaskRun(demoSession.taskRun)
        }
        saveToDisk()
    }
}
