import Foundation
import XCTest
@testable import ShiftCore

final class WuMindDutyQueryEngineTests: XCTestCase {
    private let matcher = ShiftMatcher(types: ShiftType.defaults)
    private let day20261125 = DayKey(year: 2026, month: 11, day: 25)
    private let day20261124 = DayKey(year: 2026, month: 11, day: 24)

    private func shanghaiDate(year: Int = 2026, month: Int = 11, day: Int = 25, hour: Int = 10, minute: Int = 0) -> Date {
        let cal = WuMindDutyQueryEngine.businessCalendar(timezoneID: "Asia/Shanghai")
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 1. Normal schedule + explicit authoritative leave & trip records.
    func testNormalScheduleAndExplicitLeaveTrip() {
        let roster: Roster = [
            "陈明": [day20261125: "遥测"],
            "林峰": [day20261125: "组A"],
            "周悦": [day20261125: "组B"],
            "赵航": [day20261125: "休息"],
            "孙琪": [day20261125: "年假"],
            "吴磊": [day20261125: "出差"],
        ]
        let snap = WuMindDutyQueryEngine.DutyDataSnapshot(
            rosterSource: .available(sourceName: "测试全员排班表"),
            leaveAuthoritySource: .available(sourceName: "OA 请假审批系统"),
            tripAuthoritySource: .available(sourceName: "OA 差旅审批系统"),
            roster: roster,
            publishedDays: [day20261125],
            activeGroupCatalog: ["组A", "组B", "组C"],
            rotationRulesSufficient: true,
            explicitLeaveRecords: [.init(person: "孙琪", day: day20261125, category: "年假", source: "OA 请假系统")],
            explicitTripRecords: [.init(person: "吴磊", day: day20261125, destinationOrNote: "北京出差", source: "OA 差旅系统")],
            rosterIncludesLeaveColumns: true
        )

        let exec = WuMindDutyQueryEngine.execute(
            prompt: "今天谁值班、哪组休息、谁请假或出差？",
            snapshot: snap,
            now: shanghaiDate(),
            activeModelLabel: "DeepSeek-R1"
        )
        XCTAssertNotNil(exec)
        XCTAssertEqual(exec?.intent.resolvedDate, day20261125)
        XCTAssertEqual(exec?.intent.businessTimezoneID, "Asia/Shanghai")
        XCTAssertEqual(exec?.exfiltratedToExternalModel, false)

        let onDuty = exec?.section(for: .onDuty)
        XCTAssertEqual(onDuty?.status, .confirmed)
        XCTAssertTrue(onDuty?.headline.contains("陈明") == true)

        let resting = exec?.section(for: .restingGroups)
        XCTAssertEqual(resting?.status, .confirmed)
        XCTAssertTrue(resting?.headline.contains("组C") == true)
        XCTAssertTrue(resting?.details.joined().contains("赵航") == true)

        let leave = exec?.section(for: .leave)
        XCTAssertEqual(leave?.status, .confirmed)
        XCTAssertTrue(leave?.headline.contains("孙琪") == true)

        let trip = exec?.section(for: .trip)
        XCTAssertEqual(trip?.status, .confirmed)
        XCTAssertTrue(trip?.headline.contains("吴磊") == true)

        // Verify actual tool call audit log recorded all 4 sub-queries
        let tools = Set(exec?.toolCalls.map(\.toolName) ?? [])
        XCTAssertTrue(tools.contains("duty_roster_lookup"))
        XCTAssertTrue(tools.contains("duty_resting_groups_lookup"))
        XCTAssertTrue(tools.contains("duty_leave_records_lookup"))
        XCTAssertTrue(tools.contains("duty_trip_records_lookup"))
    }

    /// 2. Temporary swap (`TeamChange`) is surfaced clearly alongside active roster.
    func testTemporarySwapReflectedInOnDutyResult() {
        let roster: Roster = [
            "王凯": [day20261125: "遥测"],
            "李敏": [day20261125: "组A"],
        ]
        let swap = TeamChange(day: day20261125, post: "遥测", from: ["张伟"], to: ["王凯"])
        let snap = WuMindDutyQueryEngine.DutyDataSnapshot(
            rosterSource: .available(sourceName: "测试全员排班表"),
            leaveAuthoritySource: .unavailable(reason: "未接入请假系统"),
            tripAuthoritySource: .unavailable(reason: "未接入出差系统"),
            roster: roster,
            publishedDays: [day20261125],
            teamChanges: [swap]
        )

        let exec = WuMindDutyQueryEngine.execute(prompt: "今天谁值班？有没有临时调班？", snapshot: snap, now: shanghaiDate())
        XCTAssertNotNil(exec)
        let onDuty = exec?.section(for: .onDuty)
        XCTAssertEqual(onDuty?.status, .confirmed)
        XCTAssertTrue(onDuty?.headline.contains("王凯") == true)
        XCTAssertTrue(onDuty?.details.contains(where: { $0.contains("张伟") && $0.contains("王凯") }) == true)
        XCTAssertEqual(exec?.section(for: .swaps)?.status, .confirmed)
    }

    /// 3. Roster does NOT write the literal word "休息", but rotation rules ARE sufficient to derive resting groups.
    func testRestingGroupDerivedFromRotationRulesWithoutLiteralRestWord() {
        let roster: Roster = [
            "陈明": [day20261125: "遥测"],
            "林峰": [day20261125: "组A"],
            "周悦": [day20261125: "组B"],
            "何强": [day20261125: "组D"],
            // Notice: zero literal "休息" cells anywhere on 2026-11-25!
            // Even if 2026-11-29 has "休息", engine MUST NOT jump to Nov 29!
            "郭峰": [DayKey(year: 2026, month: 11, day: 29): "休息"],
        ]
        let snap = WuMindDutyQueryEngine.DutyDataSnapshot(
            rosterSource: .available(sourceName: "App 全员排班表"),
            leaveAuthoritySource: .unavailable(reason: "未接入 OA 请假系统"),
            tripAuthoritySource: .unavailable(reason: "未接入 OA 出差系统"),
            roster: roster,
            publishedDays: [day20261125],
            activeGroupCatalog: ["组A", "组B", "组C", "组D", "组E"],
            rotationRulesSufficient: true
        )

        let exec = WuMindDutyQueryEngine.execute(prompt: "今天哪组休息？", snapshot: snap, now: shanghaiDate())
        XCTAssertNotNil(exec)
        XCTAssertEqual(exec?.intent.resolvedDate, day20261125)
        let resting = exec?.section(for: .restingGroups)
        XCTAssertEqual(resting?.status, .confirmed)
        XCTAssertTrue(resting?.headline.contains("组C") == true)
        XCTAssertTrue(resting?.headline.contains("组E") == true)
        XCTAssertFalse(exec?.formattedReport.contains("11-29") == true)
    }

    /// 4. Roster has no literal "休息" AND rotation rules are insufficient → MUST NOT say "nobody is resting".
    func testInsufficientRotationRulesNeverFabricatesNobodyResting() {
        let roster: Roster = [
            "陈明": [day20261125: "遥测"],
            "林峰": [day20261125: "组A"],
        ]
        let snap = WuMindDutyQueryEngine.DutyDataSnapshot(
            rosterSource: .available(sourceName: "App 全员排班表"),
            leaveAuthoritySource: .unavailable(reason: "未接入请假源"),
            tripAuthoritySource: .unavailable(reason: "未接入出差源"),
            roster: roster,
            publishedDays: [day20261125],
            activeGroupCatalog: ["组A"],
            rotationRulesSufficient: false
        )

        let exec = WuMindDutyQueryEngine.execute(prompt: "今天哪组休息？", snapshot: snap, now: shanghaiDate())
        let resting = exec?.section(for: .restingGroups)
        XCTAssertEqual(resting?.status, .unauthorizedOrUnconnected)
        XCTAssertTrue(resting?.headline.contains("未确认") == true)
        XCTAssertTrue(resting?.headline.contains("不能推定无人休息") == true)
    }

    /// 5. KEY ACCEPTANCE CASE: Roster confirmed, Leave source missing →
    /// MUST accurately list on-duty personnel FIRST and mark ONLY leave/trip as unconfirmed,
    /// NEVER asking the user to upload a spreadsheet or provide a project path.
    func testKeyCaseRosterConfirmedWhileLeaveSourceMissing() {
        let roster: Roster = [
            "陈明": [day20261125: "遥测"],
            "林峰": [day20261125: "组A"],
            "周悦": [day20261125: "组B"],
        ]
        let snap = WuMindDutyQueryEngine.DutyDataSnapshot(
            rosterSource: .available(sourceName: "App 本机全员排班表"),
            leaveAuthoritySource: .unavailable(reason: "未接入 OA/考勤请假系统"),
            tripAuthoritySource: .unavailable(reason: "未接入差旅系统"),
            roster: roster,
            publishedDays: [day20261125],
            activeGroupCatalog: ["组A", "组B", "组C"],
            rotationRulesSufficient: true
        )

        let exec = WuMindDutyQueryEngine.execute(
            prompt: "今天谁值班、哪组休息、谁请假或出差？",
            snapshot: snap,
            now: shanghaiDate(),
            activeModelLabel: "DeepSeek-V3"
        )
        XCTAssertNotNil(exec)
        // Confirmed items appear FIRST in ordered sections
        XCTAssertEqual(exec?.sections.first?.topic, .onDuty)
        XCTAssertEqual(exec?.section(for: .onDuty)?.status, .confirmed)
        XCTAssertTrue(exec?.section(for: .onDuty)?.headline.contains("陈明") == true)
        XCTAssertEqual(exec?.section(for: .restingGroups)?.status, .confirmed)
        XCTAssertTrue(exec?.section(for: .restingGroups)?.headline.contains("组C") == true)
        // Leave & trip strictly marked unconfirmed (NOT fabricated as empty!)
        XCTAssertEqual(exec?.section(for: .leave)?.status, .unauthorizedOrUnconnected)
        XCTAssertEqual(exec?.section(for: .trip)?.status, .unauthorizedOrUnconnected)
        // Never asks user to upload Excel or give file path
        XCTAssertFalse(exec?.formattedReport.contains("请上传") == true)
        XCTAssertFalse(exec?.formattedReport.contains("提供路径") == true)
    }

    /// 6. True empty result from an available authoritative source is distinguished from missing source or query failure.
    func testTrueEmptyResultDistinguishedFromMissingAndFailedSources() {
        let roster: Roster = [
            "陈明": [day20261125: "遥测"],
        ]
        let snap = WuMindDutyQueryEngine.DutyDataSnapshot(
            rosterSource: .available(sourceName: "App 全员排班表"),
            leaveAuthoritySource: .available(sourceName: "OA 请假系统"),
            tripAuthoritySource: .failed(sourceName: "差旅接口", error: "内网 HTTP 503 超时"),
            roster: roster,
            publishedDays: [day20261125],
            explicitLeaveRecords: [], // Checked & truly empty!
            rosterIncludesLeaveColumns: true
        )

        let exec = WuMindDutyQueryEngine.execute(prompt: "今天谁值班、谁请假、谁出差？", snapshot: snap, now: shanghaiDate())
        XCTAssertEqual(exec?.section(for: .onDuty)?.status, .confirmed)
        XCTAssertEqual(exec?.section(for: .leave)?.status, .checkedEmpty)
        XCTAssertTrue(exec?.section(for: .leave)?.headline.contains("确无请假记录") == true)
        XCTAssertEqual(exec?.section(for: .trip)?.status, .queryFailed)
        XCTAssertTrue(exec?.section(for: .trip)?.headline.contains("503") == true)
    }

    /// 7. Permission denied (External restricted user) blocks ALL internal roster reading.
    func testPermissionDeniedBlocksAllInternalData() {
        let roster: Roster = ["陈明": [day20261125: "遥测"]]
        let snap = WuMindDutyQueryEngine.DutyDataSnapshot(
            permission: .denied(reason: "外部访客账号无权访问内部排班"),
            rosterSource: .available(sourceName: "内部排班"),
            leaveAuthoritySource: .available(sourceName: "OA"),
            tripAuthoritySource: .available(sourceName: "OA"),
            roster: roster,
            publishedDays: [day20261125]
        )

        let exec = WuMindDutyQueryEngine.execute(prompt: "今天谁值班？", snapshot: snap, now: shanghaiDate())
        XCTAssertNotNil(exec)
        XCTAssertEqual(exec?.sections.count, 1)
        XCTAssertEqual(exec?.sections.first?.status, .unauthorizedOrUnconnected)
        XCTAssertFalse(exec?.formattedReport.contains("陈明") == true)
        XCTAssertEqual(exec?.exfiltratedToExternalModel, false)
    }

    /// 8. Cross-midnight query (01:30 AM before 08:30 handover) reports BOTH the active overnight shift
    /// from the previous roster day AND the calendar day's schedule.
    func testCrossMidnightTelemetryWindow() {
        let roster: Roster = [
            "刘洋": [day20261124: "遥测"],
            "陈明": [day20261125: "遥测"],
        ]
        let snap = WuMindDutyQueryEngine.DutyDataSnapshot(
            handoverTime: ClockTime(hour: 8, minute: 30),
            rosterSource: .available(sourceName: "App 全员排班表"),
            leaveAuthoritySource: .unavailable(reason: "未接入"),
            tripAuthoritySource: .unavailable(reason: "未接入"),
            roster: roster,
            publishedDays: [day20261124, day20261125]
        )

        let earlyMorning = shanghaiDate(year: 2026, month: 11, day: 25, hour: 1, minute: 30)
        let exec = WuMindDutyQueryEngine.execute(prompt: "今天谁值班？", snapshot: snap, now: earlyMorning)
        XCTAssertEqual(exec?.intent.resolvedDate, day20261125)
        XCTAssertEqual(exec?.activeHandoverDay, day20261124)
        XCTAssertEqual(exec?.isCrossMidnightWindow, true)
        let details = exec?.section(for: .onDuty)?.details.joined(separator: "\n") ?? ""
        XCTAssertTrue(details.contains("刘洋"), "Must include active overnight duty person from 2026-11-24")
        XCTAssertTrue(details.contains("陈明"), "Must also include calendar-day 2026-11-25 duty person")
    }

    /// 9. Switching models (DeepSeek → Claude → Gemini) yields IDENTICAL deterministic tool calls & answers
    /// with ZERO external data exfiltration.
    func testModelIndependenceAndZeroExternalExfiltration() {
        let roster: Roster = [
            "陈明": [day20261125: "遥测"],
            "林峰": [day20261125: "组A"],
        ]
        let snap = WuMindDutyQueryEngine.DutyDataSnapshot(
            rosterSource: .available(sourceName: "App 全员排班表"),
            leaveAuthoritySource: .unavailable(reason: "未接入请假系统"),
            tripAuthoritySource: .unavailable(reason: "未接入出差系统"),
            roster: roster,
            publishedDays: [day20261125],
            activeGroupCatalog: ["组A", "组B"],
            rotationRulesSufficient: true
        )

        let runDeepSeek = WuMindDutyQueryEngine.execute(prompt: "今天谁值班、哪组休息、谁请假？", snapshot: snap, now: shanghaiDate(), activeModelLabel: "DeepSeek-R1")
        let runClaude = WuMindDutyQueryEngine.execute(prompt: "今天谁值班、哪组休息、谁请假？", snapshot: snap, now: shanghaiDate(), activeModelLabel: "Claude-Sonnet-4.5")
        let runGemini = WuMindDutyQueryEngine.execute(prompt: "今天谁值班、哪组休息、谁请假？", snapshot: snap, now: shanghaiDate(), activeModelLabel: "Gemini-2.5-Pro")

        XCTAssertEqual(runDeepSeek?.toolCalls, runClaude?.toolCalls)
        XCTAssertEqual(runClaude?.toolCalls, runGemini?.toolCalls)
        XCTAssertEqual(runDeepSeek?.sections, runClaude?.sections)
        XCTAssertEqual(runClaude?.sections, runGemini?.sections)
        XCTAssertEqual(runDeepSeek?.exfiltratedToExternalModel, false)
        XCTAssertEqual(runClaude?.exfiltratedToExternalModel, false)
        XCTAssertEqual(runGemini?.exfiltratedToExternalModel, false)
    }

    /// 10. Normal non-duty chat NEVER triggers internal Duty App queries.
    func testNormalChatNeverTriggersInternalDutyQueries() {
        let normalPrompts = [
            "帮我写一段 Swift 快速排序代码",
            "做一份 8 页年终工作总结 PPT",
            "做一个三种套餐的报价计算器",
            "今天北京天气怎么样？",
            "帮我盯公开招标网站更正公告",
        ]
        let snap = WuMindDutyQueryEngine.DutyDataSnapshot(
            rosterSource: .available(sourceName: "App 全员排班表"),
            leaveAuthoritySource: .available(sourceName: "OA"),
            tripAuthoritySource: .available(sourceName: "OA"),
            roster: ["陈明": [day20261125: "遥测"]],
            publishedDays: [day20261125]
        )
        for prompt in normalPrompts {
            XCTAssertNil(WuMindDutyQueryEngine.execute(prompt: prompt, snapshot: snap, now: shanghaiDate()),
                         "Normal chat '\(prompt)' must NOT trigger internal Duty queries")
        }
    }

    /// 11. Broader Duty App questions (workload, forecast, pass-plan, meetings, notices, work log) all work.
    func testAllDutyAppDomainsCovered() {
        let snap = WuMindDutyQueryEngine.DutyDataSnapshot(
            rosterSource: .available(sourceName: "App 全员排班表"),
            leaveAuthoritySource: .unavailable(reason: "未接入"),
            tripAuthoritySource: .unavailable(reason: "未接入"),
            roster: ["陈明": [day20261125: "遥测"]],
            publishedDays: [day20261125],
            workloadSummary: "本人本月工作量 16 天（上班 18 天、遥测 3 次）",
            nextTelemetrySummary: "下一次遥测为 2026-11-30",
            passPlanSummary: "当前数传计划共 8 条、分成 4 家，已发 2 家。",
            meetingOpenSummaries: ["[组A] 天线馈源校准未闭环（首见 2026-11-16）"],
            siteNotices: ["12 月起值班交接时间维持 08:30"],
            groupNotes: ["组A": "日常巡检与数据备份"],
            workLogTodayCount: 3
        )
        let exec = WuMindDutyQueryEngine.execute(
            prompt: "帮我看下本月工作量、下次遥测、发数传计划进度、周会问题、网站公告和今天工作留痕",
            snapshot: snap,
            now: shanghaiDate()
        )
        XCTAssertNotNil(exec)
        XCTAssertEqual(exec?.section(for: .workload)?.status, .confirmed)
        XCTAssertEqual(exec?.section(for: .forecast)?.status, .confirmed)
        XCTAssertEqual(exec?.section(for: .passPlan)?.status, .confirmed)
        XCTAssertEqual(exec?.section(for: .meeting)?.status, .confirmed)
        XCTAssertEqual(exec?.section(for: .noticesAndGroupNotes)?.status, .confirmed)
        XCTAssertEqual(exec?.section(for: .workLog)?.status, .confirmed)
    }
}
