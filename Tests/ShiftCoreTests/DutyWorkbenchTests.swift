import XCTest
@testable import ShiftCore

final class DutyWorkbenchTests: XCTestCase {
    private let day = DayKey(year: 2026, month: 11, day: 23)
    private let cal = Calendar.dayMath
    private let matcher = ShiftMatcher(types: ShiftType.defaults)
    private let handover = ClockTime(hour: 8, minute: 30)

    func testBeforeHandoverKeepsYesterdayWithoutClaimingTodayHasStarted() throws {
        let previous = day.adding(days: -1, calendar: cal)
        let schedule = [previous: "遥测", day: "遥测"]
        let before = day.date(calendar: cal, hour: 8, minute: 29)
        let at = day.date(calendar: cal, hour: 8, minute: 30)
        XCTAssertEqual(DutyWorkbench.rosterDay(asOf: before, handover: handover), previous)
        XCTAssertEqual(DutyWorkbench.rosterDay(asOf: at, handover: handover), day)
        XCTAssertNil(DutyWorkbench.rosterDay(asOf: at, handover: .init(hour: 24, minute: 0)))
        XCTAssertEqual(DutyWorkbench.current(now: before, schedule: schedule, matcher: matcher, handover: handover)?.day, previous)
        XCTAssertEqual(DutyWorkbench.current(now: at, schedule: schedule, matcher: matcher, handover: handover)?.day, day)
        XCTAssertNil(DutyWorkbench.current(now: before, schedule: [day: "遥测"], matcher: matcher, handover: handover))
        XCTAssertEqual(DutyWorkbench.next(atOrAfter: before, schedule: schedule, matcher: matcher, handover: handover)?.start, at)
    }

    func testDoesNotInventClockTimeForOfficeOrRestPosts() {
        let schedule = [day: "组A", day.adding(days: 1, calendar: cal): "值班交接前"]
        let date = day.date(calendar: cal, hour: 10)
        XCTAssertNil(DutyWorkbench.current(now: date, schedule: schedule, matcher: matcher, handover: handover))
        XCTAssertNil(DutyWorkbench.next(atOrAfter: date, schedule: schedule, matcher: matcher, handover: handover))
    }

    func testNoTwentyFourHourWindowForCancelledTentativeOrExplicitNightDuty() {
        for raw in ["非遥测", "待定遥测", "遥测（夜班）", "遥测+休息", "N/A"] {
            XCTAssertNil(DutyWorkbench.window(on: day, schedule: [day: raw], matcher: matcher, handover: handover), raw)
        }
        XCTAssertNotNil(DutyWorkbench.window(on: day, schedule: [day: "遥测+组C"], matcher: matcher, handover: handover))
    }

    func testChangesAndReceiptsBoundedByShiftAndPresent() throws {
        let window = try XCTUnwrap(DutyWorkbench.window(on: day, schedule: [day: "遥测"], matcher: matcher, handover: handover))
        let now = window.start.addingTimeInterval(90)
        func edit(_ at: Date, _ name: String) -> RosterEdit {
            RosterEdit(at: at, day: day, name: name, old: "组A", new: "组B", source: "demo")
        }
        let records = [edit(window.start.addingTimeInterval(-1), "old"), edit(window.end, "next"),
                       edit(now.addingTimeInterval(1), "future"), edit(now, "later"), edit(window.start, "first")]
        XCTAssertEqual(DutyWorkbench.changes(records, in: window, now: now).map(\.name), ["later", "first"])
        XCTAssertEqual(DutyWorkbench.confirmed(Dictionary(uniqueKeysWithValues: records.map { ($0.name, $0.at) }),
                                               in: window, now: now), ["first", "later"])
    }
}
