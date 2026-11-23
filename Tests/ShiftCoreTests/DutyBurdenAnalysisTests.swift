import Foundation
import XCTest
@testable import ShiftCore

final class DutyBurdenAnalysisTests: XCTestCase {
    private let matcher = ShiftMatcher(types: ShiftType.defaults)

    func testRollingWindowCrossesYearAndExcludesTodayFutureAndBeforeWindow() throws {
        let today = day("2026-01-10")
        let report = DutyBurdenAnalysis.analyze(roster: ["示例": [
            day("2025-12-10"): "夜班", day("2025-12-11"): "夜班",
            day("2026-01-09"): "白班", today: "夜班", day("2026-01-11"): "夜班"
        ]], today: today, matcher: matcher)
        XCTAssertEqual(report.start, day("2025-12-11"))
        XCTAssertEqual(report.end, day("2026-01-09"))
        XCTAssertEqual(report.rosterDates, [report.start, report.end])
        let found = try XCTUnwrap(report.members.first)
        XCTAssertEqual(found.nightDates, [report.start])
        XCTAssertEqual(found.recordedDates.count + found.unknownDates.count, DutyBurdenAnalysis.windowDays)
        XCTAssertEqual(found.confirmedNightDays, 1)
        XCTAssertTrue(found.nightCountIsMinimum)
    }

    func testNightRequiresExplicitMarkerAndDoesNotGuessUnlabelledDutyOrSupport() throws {
        let report = DutyBurdenAnalysis.analyze(roster: ["示例": [
            day("2026-06-01"): "遥测",
            day("2026-06-02"): "夜班支持",
            day("2026-06-03"): "夜班请假",
            day("2026-06-04"): "N",
            day("2026-06-05"): "遥测（夜班）",
            day("2026-06-06"): "夜班+组A",
            day("2026-06-07"): "白班+中班",
            day("2026-06-08"): "夜班待定"
        ]], today: day("2026-06-09"), matcher: matcher)
        let found = try XCTUnwrap(report.members.first)
        XCTAssertEqual(found.nightDates, [day("2026-06-04"), day("2026-06-05"), day("2026-06-06")])
        XCTAssertEqual(found.nightUnknownDates, [day("2026-06-01")])
        XCTAssertTrue(found.unknownDates.contains(day("2026-06-02")))
        XCTAssertTrue(found.unknownDates.contains(day("2026-06-08")))
        XCTAssertEqual(found.confirmedNightDays, 3)
        XCTAssertTrue(found.nightCountIsMinimum)
    }

    func testAmbiguousCustomShiftCodeDoesNotCountAsNight() throws {
        let conflict = ShiftType(id: "special", name: "其他", emoji: "", colorHex: "", codes: ["N"])
        let input = ["示例": [day("2026-06-02"): "N"]]
        let found = try XCTUnwrap(DutyBurdenAnalysis.analyze(roster: input, today: day("2026-06-03"),
                                         matcher: ShiftMatcher(types: ShiftType.defaults + [conflict])).members.first)
        XCTAssertNil(found.confirmedNightDays)
        XCTAssertTrue(found.nightDates.isEmpty)
        XCTAssertEqual(found.nightUnknownDates, [day("2026-06-02")])
    }

    func testInsufficientNightAndHolidayDataAreDifferentFromZero() throws {
        let report = DutyBurdenAnalysis.analyze(roster: [
            "仅有岗位": [day("2026-10-12"): "遥测", day("2026-10-13"): "休息"],
            "有明确白班": [day("2026-10-01"): "休息", day("2026-10-02"): "白班"],
        ], today: day("2026-10-22"), matcher: matcher, names: ["仅有岗位", "有明确白班", "无数据"])
        let byName = Dictionary(uniqueKeysWithValues: report.members.map { ($0.name, $0) })
        let unknown = try XCTUnwrap(byName["仅有岗位"])
        XCTAssertNil(unknown.confirmedNightDays)
        XCTAssertNil(unknown.confirmedHolidayWorkDays)
        let dayShift = try XCTUnwrap(byName["有明确白班"])
        XCTAssertEqual(dayShift.confirmedNightDays, 0)
        XCTAssertTrue(dayShift.nightCountIsMinimum)
        XCTAssertEqual(dayShift.confirmedHolidayWorkDays, 1)
        XCTAssertTrue(dayShift.holidayCountIsMinimum)
        let absent = try XCTUnwrap(byName["无数据"])
        XCTAssertNil(absent.longestDutyDays)
        XCTAssertTrue(absent.recordedDates.isEmpty)
    }

    func testOnlyPublishedRowsCountAndGapsOrUnknownNeverBridgeAStreak() throws {
        let history = (1...8).reduce(into: [DayKey: String]()) { rows, value in
            rows[DayKey(year: 2026, month: 6, day: value)] = value == 6 ? "待定遥测" : "遥测"
        }
        let published = Set(history.keys.filter { d in d.day != 3 })
        let found = try XCTUnwrap(DutyBurdenAnalysis.analyze(roster: ["示例": history], today: day("2026-06-10"),
                                        matcher: matcher, publishedDays: published).members.first)
        XCTAssertEqual(found.longestDutyDays, 2)
        XCTAssertEqual(found.longestDutyStreaks, [
            [day("2026-06-01"), day("2026-06-02")],
            [day("2026-06-04"), day("2026-06-05")],
            [day("2026-06-07"), day("2026-06-08")]
        ])
        XCTAssertTrue(found.unknownDates.contains(day("2026-06-03")))
        XCTAssertTrue(found.unknownDates.contains(day("2026-06-06")))
        XCTAssertTrue(found.dutyCountIsMinimum)
    }

    func testHolidayWorkDoesNotCountHolidayAttendanceOrCompensatoryRest() throws {
        let input = ["样表人员": [
            day("2026-10-01"): "遥测",
            day("2026-10-02"): "值班交接前",
            day("2026-10-03"): "调休",
            day("2026-10-04"): "节假日加班",
            day("2026-10-05"): "出差",
            day("2026-10-10"): "遥测"
        ]]
        let report = DutyBurdenAnalysis.analyze(roster: input, today: day("2026-10-11"), matcher: matcher)
        XCTAssertTrue(report.holidayDates.contains(day("2026-10-02")), "the rest date really is a holiday")
        let found = try XCTUnwrap(report.members.first)
        XCTAssertEqual(found.holidayWorkDates, [day("2026-10-01"), day("2026-10-04")])
        XCTAssertEqual(found.dutyDates, [day("2026-10-01"), day("2026-10-10")])
        XCTAssertTrue(found.recordedDates.contains(day("2026-10-02")), "documented rest is coverage, not workload")
    }

    func testUnconfiguredHolidayYearDoesNotProduceAFalseZero() throws {
        let today = day("2199-08-15")
        let report = DutyBurdenAnalysis.analyze(roster: ["示例": [day("2199-08-13"): "夜班"]],
                                                today: today, matcher: matcher)
        XCTAssertEqual(report.holidayCalendarYearsWithoutData, [2199])
        let found = try XCTUnwrap(report.members.first)
        XCTAssertNil(found.confirmedHolidayWorkDays)
        XCTAssertTrue(found.holidayCountIsMinimum)
    }

    private func day(_ value: String) -> DayKey { DayKey(string: value)! }
}
