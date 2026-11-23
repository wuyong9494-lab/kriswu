import XCTest
@testable import ShiftCore

final class DutyBurdenUpcomingTests: XCTestCase {
    private let matcher = ShiftMatcher(types: ShiftType.defaults)
    private let today = DayKey(year: 2026, month: 11, day: 23)
    private func d(_ offset: Int) -> DayKey { today.adding(days: offset, calendar: .dayMath) }

    func testMissingAndTentativeEntriesDoNotBridgeAnUpcomingRun() {
        let roster: Roster = [
            "示例甲": [d(0): "白班", d(1): "白班", d(2): "白班", d(3): "白班", d(4): "白班"],
            "占位符": [d(1): "N/A", d(2): "Ｎ／Ａ", d(3): "白班+N/A"],
            "非在岗": [d(1): "非遥测", d(2): "不值班", d(3): "取消遥测"],
            "示例乙": [d(1): "白班", d(2): "白班", d(3): "休息", d(4): "白班", d(5): "白班待定", d(6): "白班"],
        ]
        let runs = DutyBurdenAnalysis.upcomingRuns(roster: roster, today: today, published: Set((1...7).map(d)), matcher: matcher)
        XCTAssertEqual(runs.map(\.member), ["示例甲"])
        XCTAssertEqual(runs.first?.days, [d(1), d(2), d(3), d(4)])
        XCTAssertTrue(DutyBurdenAnalysis.upcomingRuns(roster: roster, today: today,
              published: Set([d(1), d(3), d(4), d(5), d(6)]), matcher: matcher).isEmpty)
    }

    func testCoverRequiresKnownRestAdjacentDaysAndSamePostHistory() throws {
        let roster: Roster = [
            "原排班": [d(2): "白班"],
            "有证据": [d(-28): "白班", d(1): "休息", d(2): "休息", d(3): "休息"],
            "错岗位": [d(-28): "夜班", d(1): "休息", d(2): "休息", d(3): "休息"],
            "缺记录": [d(-28): "白班", d(2): "休息", d(3): "休息"],
            "未知": [d(-28): "白班", d(1): "休息", d(2): "休息", d(3): "休息待定"],
            "请假英文": [d(-28): "白班", d(1): "休息", d(2): "leave", d(3): "休息"],
            "假期英文": [d(-28): "白班", d(1): "休息", d(2): "holiday", d(3): "休息"],
            "不休息": [d(-28): "白班", d(1): "休息", d(2): "不休息", d(3): "休息"],
            "无分工": [d(-28): "白班", d(1): "休息", d(2): "无分工", d(3): "休息"],
            "调休": [d(-28): "白班", d(1): "休息", d(2): "调休", d(3): "休息"],
            "在岗": [d(-28): "白班", d(1): "休息", d(2): "休息", d(3): "夜班"],
            "覆盖冲突": [d(-28): "白班", d(1): "休息", d(2): "休息+白班", d(3): "休息"],
            "上岗太久": [d(-91): "白班", d(1): "休息", d(2): "休息", d(3): "休息"],
        ]
        let published = Set([d(-91), d(-28), d(1), d(2), d(3)])
        let actual = try XCTUnwrap(DutyBurdenAnalysis.coverReview(roster: roster, member: "原排班",
            day: d(2), today: today, published: published, matcher: matcher))
        XCTAssertEqual(actual.post, "白班")
        XCTAssertEqual(actual.candidates.map(\.name), ["有证据"])
        XCTAssertEqual(actual.candidates.first?.previousPostDay, d(-28))
        let missingAdjacent = DutyBurdenAnalysis.coverReview(roster: roster, member: "原排班",
            day: d(2), today: today, published: published.subtracting([d(3)]), matcher: matcher)
        XCTAssertEqual(missingAdjacent?.candidates.count, 0)
    }

    func testNoCoverSuggestionForAmbiguousUnpublishedOrMultiPostRows() {
        let roster = ["原排班": [d(2): "暂定白班", d(3): "白班+组A", d(4): "白班"]]
        for day in (2...4).map(d) {
            XCTAssertNil(DutyBurdenAnalysis.coverReview(roster: roster, member: "原排班", day: day, today: today,
                                                        published: Set([d(2), d(3)]), matcher: matcher))
        }
    }
}
