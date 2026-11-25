import Foundation
import XCTest
@testable import ShiftCore

final class WuMindTaskGraphEngineTests: XCTestCase {
    private let day20261125 = DayKey(year: 2026, month: 11, day: 25)

    private func shanghaiDate(year: Int = 2026, month: 11, day: Int = 25, hour: Int = 10, minute: Int = 0) -> Date {
        let cal = WuMindDutyQueryEngine.businessCalendar(timezoneID: "Asia/Shanghai")
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 1. Core Acceptance: Disconnect Leave query -> Roster & Resting Groups STILL deliver via parallel DAG waves;
    /// then reconnect Leave -> Resume runs ONLY `fetch_leave` (+ `aggregate_duty_report`), with ZERO re-run of roster/rules/resting!
    func testDutyGraphDisconnectLeaveDeliversRosterAndReconnectResumesOnlyLeave() async throws {
        let roster: Roster = [
            "陈明": [day20261125: "遥测"],
            "林峰": [day20261125: "组A"],
            "周悦": [day20261125: "组B"],
        ]
        let disconnectedSnap = WuMindDutyQueryEngine.DutyDataSnapshot(
            rosterSource: .available(sourceName: "App 本机全员排班表"),
            leaveAuthoritySource: .unavailable(reason: "OA 请假接口已断开"),
            tripAuthoritySource: .unavailable(reason: "OA 差旅接口未接入"),
            roster: roster,
            publishedDays: [day20261125],
            activeGroupCatalog: ["组A", "组B", "组C"],
            rotationRulesSufficient: true
        )

        let prompt = "今天谁值班、哪组休息、谁请假或出差？"
        let initialGraph = WuMindDutyGraphWorkflow.makeGraph(prompt: prompt, snapshot: disconnectedSnap, now: shanghaiDate())
        let pass1 = await WuMindDutyGraphWorkflow.executeOrResume(
            graph: initialGraph,
            prompt: prompt,
            snapshot: disconnectedSnap,
            now: shanghaiDate()
        )

        // Verify parallel execution wave: roster, rotation rules, leave, and trip ALL share wave 1!
        XCTAssertEqual(pass1.graph.node(id: "resolve_date")?.parallelWaveIndex, 0)
        XCTAssertEqual(pass1.graph.node(id: "fetch_roster")?.parallelWaveIndex, 1)
        XCTAssertEqual(pass1.graph.node(id: "fetch_rotation_rules")?.parallelWaveIndex, 1)
        XCTAssertEqual(pass1.graph.node(id: "fetch_leave")?.parallelWaveIndex, 1)
        XCTAssertEqual(pass1.graph.node(id: "fetch_trip")?.parallelWaveIndex, 1)
        // Dependent resting group waits ONLY for roster + rotation rules (wave 2) — NOT blocked by disconnected leave!
        XCTAssertEqual(pass1.graph.node(id: "calc_resting_groups")?.parallelWaveIndex, 2)
        XCTAssertEqual(pass1.graph.node(id: "calc_resting_groups")?.status, .completed)
        XCTAssertTrue(pass1.graph.node(id: "calc_resting_groups")?.outputPayload.contains("组C") == true)

        // Leave node immediately marked unconnected without guessing or wasting retries
        XCTAssertEqual(pass1.graph.node(id: "fetch_leave")?.status, .unconnectedOrUnauthorized)
        XCTAssertEqual(pass1.graph.node(id: "fetch_leave")?.lastLoopAttempts, 1)
        // Final report delivers confirmed on-duty & resting group immediately!
        XCTAssertEqual(pass1.graph.node(id: "aggregate_duty_report")?.status, .completed)
        XCTAssertTrue(pass1.finalReport.contains("陈明"))
        XCTAssertTrue(pass1.finalReport.contains("组C"))
        XCTAssertTrue(pass1.finalReport.contains("未接入"))

        let rosterHashPass1 = pass1.graph.node(id: "fetch_roster")?.outputHash
        let restingHashPass1 = pass1.graph.node(id: "calc_resting_groups")?.outputHash

        // NOW reconnect Leave source and resume ONLY `fetch_leave` on the SAME graph!
        let reconnectedSnap = WuMindDutyQueryEngine.DutyDataSnapshot(
            rosterSource: .available(sourceName: "App 本机全员排班表"),
            leaveAuthoritySource: .available(sourceName: "OA 请假审批系统"),
            tripAuthoritySource: .unavailable(reason: "OA 差旅接口未接入"),
            roster: roster,
            publishedDays: [day20261125],
            activeGroupCatalog: ["组A", "组B", "组C"],
            rotationRulesSufficient: true,
            explicitLeaveRecords: [.init(person: "孙琪", day: day20261125, category: "年假", source: "OA 请假审批系统")],
            rosterIncludesLeaveColumns: true
        )

        let pass2 = await WuMindDutyGraphWorkflow.resumeLeaveOnly(
            existingGraph: pass1.graph,
            prompt: prompt,
            reconnectedSnapshot: reconnectedSnap,
            now: shanghaiDate()
        )

        // PROVE zero wasted re-runs on upstream/sibling completed nodes!
        XCTAssertEqual(pass2.graph.node(id: "resolve_date")?.executionCount, 1)
        XCTAssertEqual(pass2.graph.node(id: "resolve_date")?.status, .cachedUnchanged)
        XCTAssertEqual(pass2.graph.node(id: "fetch_roster")?.executionCount, 1)
        XCTAssertEqual(pass2.graph.node(id: "fetch_roster")?.status, .cachedUnchanged)
        XCTAssertEqual(pass2.graph.node(id: "fetch_roster")?.outputHash, rosterHashPass1)
        XCTAssertEqual(pass2.graph.node(id: "fetch_rotation_rules")?.executionCount, 1)
        XCTAssertEqual(pass2.graph.node(id: "calc_resting_groups")?.executionCount, 1)
        XCTAssertEqual(pass2.graph.node(id: "calc_resting_groups")?.outputHash, restingHashPass1)

        // PROVE ONLY `fetch_leave` and downstream `aggregate_duty_report` re-executed!
        XCTAssertEqual(pass2.graph.node(id: "fetch_leave")?.executionCount, 2)
        XCTAssertEqual(pass2.graph.node(id: "fetch_leave")?.status, .completed)
        XCTAssertTrue(pass2.graph.node(id: "fetch_leave")?.outputPayload.contains("孙琪") == true)
        XCTAssertEqual(pass2.graph.node(id: "aggregate_duty_report")?.executionCount, 2)
        XCTAssertTrue(pass2.finalReport.contains("孙琪"))
    }

    /// 2. Deterministic Validation Loop: bad date on attempt 1 retries ONLY `resolve_date`,
    /// never touches downstream or calls another LLM to rubber-stamp!
    func testDeterministicValidationLoopRetriesOnlyBrokenDateNode() async {
        let snap = WuMindDutyQueryEngine.DutyDataSnapshot(
            rosterSource: .available(sourceName: "App 全员排班表"),
            leaveAuthoritySource: .unavailable(reason: "未接入"),
            tripAuthoritySource: .unavailable(reason: "未接入"),
            roster: ["陈明": [day20261125: "遥测"]],
            publishedDays: [day20261125]
        )
        let graph = WuMindDutyGraphWorkflow.makeGraph(prompt: "今天谁值班？", snapshot: snap, now: shanghaiDate())
        let outcome = await WuMindDutyGraphWorkflow.executeOrResume(
            graph: graph,
            prompt: "今天谁值班？",
            snapshot: snap,
            now: shanghaiDate(),
            simulateInitialDateGlitch: true
        )

        XCTAssertEqual(outcome.graph.node(id: "resolve_date")?.status, .completed)
        XCTAssertEqual(outcome.graph.node(id: "resolve_date")?.lastLoopAttempts, 2, "Only resolve_date should retry once")
        XCTAssertEqual(outcome.graph.node(id: "resolve_date")?.executionCount, 2)
        XCTAssertEqual(outcome.graph.node(id: "fetch_roster")?.executionCount, 1, "Downstream runs once after validator succeeds")
    }

    /// 3. Human-in-the-Loop ONLY at consequential boundaries + fail-fast when authorization is missing upfront.
    func testConsequentialApprovalBoundaryAndUpfrontMissingPermissionFailFast() async {
        let snap = WuMindDutyQueryEngine.DutyDataSnapshot(
            rosterSource: .available(sourceName: "App 全员排班表"),
            leaveAuthoritySource: .unavailable(reason: "未接入"),
            tripAuthoritySource: .unavailable(reason: "未接入"),
            roster: ["陈明": [day20261125: "遥测"]],
            publishedDays: [day20261125]
        )
        let graph = WuMindDutyGraphWorkflow.makeGraph(
            prompt: "今天谁值班并通知大家",
            snapshot: snap,
            includeSendNotificationStep: true,
            now: shanghaiDate()
        )
        let pass1 = await WuMindDutyGraphWorkflow.executeOrResume(
            graph: graph,
            prompt: "今天谁值班并通知大家",
            snapshot: snap,
            now: shanghaiDate()
        )
        // Read-only report finished, consequential send step paused for explicit human approval!
        XCTAssertEqual(pass1.graph.node(id: "aggregate_duty_report")?.status, .completed)
        XCTAssertEqual(pass1.graph.node(id: "send_summary_notice")?.status, .awaitingApproval)
        XCTAssertEqual(pass1.graph.node(id: "send_summary_notice")?.executionCount, 0)
        XCTAssertEqual(pass1.graph.overallStatus, .awaitingApproval)

        // Approve consequential step -> ONLY `send_summary_notice` runs; all read-only nodes stay cached!
        var approved = pass1.graph
        approved.decideNodeApproval(nodeID: "send_summary_notice", approved: true, now: shanghaiDate())
        let pass2 = await WuMindDutyGraphWorkflow.executeOrResume(
            graph: approved,
            prompt: "今天谁值班并通知大家",
            snapshot: snap,
            now: shanghaiDate()
        )
        XCTAssertEqual(pass2.graph.node(id: "fetch_roster")?.executionCount, 1)
        XCTAssertEqual(pass2.graph.node(id: "send_summary_notice")?.status, .completed)
        XCTAssertEqual(pass2.graph.node(id: "send_summary_notice")?.executionCount, 1)

        // Fail-fast upfront authorization check: root node lacking permission pauses immediately on wave 0!
        let upfrontBlockedGraph = WuMindTaskGraph(
            kind: .crossAppExecution,
            title: "缺少前置写权限测试",
            nodes: [
                WuMindGraphNode(
                    id: "authorize_folder",
                    title: "写入授权目录",
                    inputSummary: "覆盖目标报表",
                    sourceLabel: "本地文件夹",
                    approvalGate: WuMindApprovalGate(actionKind: .overwriteFile, title: "缺少目录写权限", targetResource: "/报价比价表.xlsx", previewText: "请先授权目录写权限")
                ),
                WuMindGraphNode(
                    id: "write_excel",
                    title: "写入 Excel",
                    dependencies: ["authorize_folder"],
                    inputSummary: "写入报价数据",
                    sourceLabel: "Excel 写入器"
                ),
            ]
        )
        let blocked = await WuMindGraphExecutor.run(
            graph: upfrontBlockedGraph,
            handlers: [
                "authorize_folder": { _, _ in .success(payload: "ok") },
                "write_excel": { _, _ in .success(payload: "written") },
            ]
        )
        XCTAssertEqual(blocked.node(id: "authorize_folder")?.status, .awaitingApproval)
        XCTAssertEqual(blocked.node(id: "authorize_folder")?.executionCount, 0)
        XCTAssertEqual(blocked.node(id: "write_excel")?.status, .blockedByDependency)
        XCTAssertEqual(blocked.node(id: "write_excel")?.executionCount, 0)
    }

    /// 4. Same Loops & Graphs Mechanism: Short-Drama "Only Redo Shot 3" keeps Shots 1, 2, 4 cached & untouched!
    func testSameMechanismRedoesOnlyShortDramaShot3() async {
        let shots: [WuMindShortDramaGraphWorkflow.ShotSpec] = [
            .init(shotIndex: 1, framing: "全景", visualPrompt: "天台雨夜", dialogue: "来了？", voiceProfile: "男主低沉"),
            .init(shotIndex: 2, framing: "中景", visualPrompt: "转身对视", dialogue: "带证据了吗？", voiceProfile: "女主冷静"),
            .init(shotIndex: 3, framing: "中景", visualPrompt: "递出U盘", dialogue: "全在这里。", voiceProfile: "男主低沉"),
            .init(shotIndex: 4, framing: "特写", visualPrompt: "警笛逼近", dialogue: "快撤！", voiceProfile: "女主冷静"),
        ]
        let g1 = await WuMindShortDramaGraphWorkflow.execute(
            graph: WuMindShortDramaGraphWorkflow.makeGraph(title: "测试短剧", shots: shots),
            shots: shots
        )
        XCTAssertEqual(g1.node(id: "shot_1")?.parallelWaveIndex, 0)
        XCTAssertEqual(g1.node(id: "shot_3")?.parallelWaveIndex, 0)
        XCTAssertEqual(g1.node(id: "publish_drama")?.status, .awaitingApproval)

        let s1Hash = g1.node(id: "shot_1")?.outputHash
        let s2Hash = g1.node(id: "shot_2")?.outputHash
        let s4Hash = g1.node(id: "shot_4")?.outputHash

        var updatedShot3 = shots[2]
        updatedShot3.framing = "近景"
        let g2 = await WuMindShortDramaGraphWorkflow.redoSingleShot(
            existingGraph: g1,
            shots: shots,
            targetShotIndex: 3,
            updatedShot: updatedShot3
        )

        // Shots 1, 2, 4 NEVER re-executed & hashes byte-identical!
        XCTAssertEqual(g2.node(id: "shot_1")?.executionCount, 1)
        XCTAssertEqual(g2.node(id: "shot_1")?.outputHash, s1Hash)
        XCTAssertEqual(g2.node(id: "shot_2")?.executionCount, 1)
        XCTAssertEqual(g2.node(id: "shot_2")?.outputHash, s2Hash)
        XCTAssertEqual(g2.node(id: "shot_4")?.executionCount, 1)
        XCTAssertEqual(g2.node(id: "shot_4")?.outputHash, s4Hash)

        // ONLY Shot 3 & downstream compose_timeline re-executed!
        XCTAssertEqual(g2.node(id: "shot_3")?.executionCount, 2)
        XCTAssertEqual(g2.node(id: "shot_3")?.status, .completed)
        XCTAssertEqual(g2.node(id: "compose_timeline")?.executionCount, 2)
        XCTAssertEqual(g2.node(id: "publish_drama")?.status, .awaitingApproval)
    }

    /// 5. Same Loops & Graphs Mechanism: Mobile Game "Only Fix Level 2" preserves Level 1 byte-identically
    /// and validates Level 2 solvability + reduced difficulty via deterministic BFS solver!
    func testSameMechanismFixesOnlyMobileGameLevel2WithBFSSolver() async {
        let level1 = WuMindMobileGameGraphWorkflow.RouteLevelSpec(
            levelNumber: 1,
            name: "第一关·启程",
            startStation: "A",
            edges: ["A": ["B", "C"], "B": ["D"], "C": ["D"], "D": ["E"]],
            targetChain: ["B", "D", "E"],
            hopBudget: 5
        )
        let level2Hard = WuMindMobileGameGraphWorkflow.RouteLevelSpec(
            levelNumber: 2,
            name: "第二关·初版",
            startStation: "A",
            edges: ["A": ["B"], "B": ["C", "D"], "C": ["E"], "D": ["E"], "E": ["F"], "F": ["A"]],
            targetChain: ["C", "E", "F", "B"],
            hopBudget: 6 // Exact min hops = 6 (0 slack)
        )
        XCTAssertEqual(WuMindMobileGameGraphWorkflow.shortestChainHops(for: level1), 3)
        XCTAssertEqual(WuMindMobileGameGraphWorkflow.shortestChainHops(for: level2Hard), 6)

        let g1 = await WuMindMobileGameGraphWorkflow.execute(
            graph: WuMindMobileGameGraphWorkflow.makeGraph(title: "最后一跳", level1: level1, level2: level2Hard),
            level1: level1,
            level2: level2Hard
        )
        XCTAssertEqual(g1.node(id: "level_1_build")?.status, .completed)
        XCTAssertEqual(g1.node(id: "level_2_build")?.status, .completed)
        XCTAssertEqual(g1.node(id: "package_game_html")?.status, .completed)
        let l1HashBefore = g1.node(id: "level_1_build")?.outputHash

        // Revise ONLY Level 2 to lower difficulty (increase budget slack to +3)
        var level2Easier = level2Hard
        level2Easier.hopBudget = 9
        let g2 = await WuMindMobileGameGraphWorkflow.reviseLevel2Only(
            existingGraph: g1,
            level1: level1,
            easierLevel2: level2Easier,
            requireSlackAtLeast: 2
        )

        // Level 1 stayed cached with executionCount == 1 and byte-identical outputHash!
        XCTAssertEqual(g2.node(id: "level_1_build")?.executionCount, 1)
        XCTAssertEqual(g2.node(id: "level_1_build")?.status, .cachedUnchanged)
        XCTAssertEqual(g2.node(id: "level_1_build")?.outputHash, l1HashBefore)
        // ONLY Level 2 & package_game_html re-ran and passed BFS validator!
        XCTAssertEqual(g2.node(id: "level_2_build")?.executionCount, 2)
        XCTAssertEqual(g2.node(id: "level_2_build")?.status, .completed)
        XCTAssertEqual(g2.node(id: "package_game_html")?.executionCount, 2)

        // Negative check: broken unsolvable Level 2 is caught deterministically and blocks packaging without touching Level 1!
        let level2Broken = WuMindMobileGameGraphWorkflow.RouteLevelSpec(
            levelNumber: 2,
            name: "第二关·误删边无解",
            startStation: "A",
            edges: ["A": ["B"]], // C/E/F unreachable!
            targetChain: ["C", "E"],
            hopBudget: 9
        )
        let gBroken = await WuMindMobileGameGraphWorkflow.reviseLevel2Only(
            existingGraph: g2,
            level1: level1,
            easierLevel2: level2Broken,
            requireSlackAtLeast: 2
        )
        XCTAssertEqual(gBroken.node(id: "level_1_build")?.executionCount, 1)
        XCTAssertEqual(gBroken.node(id: "level_1_build")?.outputHash, l1HashBefore)
        XCTAssertEqual(gBroken.node(id: "level_2_build")?.status, .failed)
        XCTAssertEqual(gBroken.node(id: "package_game_html")?.status, .blockedByDependency)
    }
}
