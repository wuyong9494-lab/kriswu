import Foundation
import XCTest
@testable import ShiftCore

final class PlanReminderDateTests: XCTestCase {
    private func calendar(_ identifier: Calendar.Identifier = .gregorian,
                          timeZone: String = "Asia/Shanghai") -> Calendar {
        var value = Calendar(identifier: identifier)
        value.timeZone = TimeZone(identifier: timeZone)!
        return value
    }

    private func date(_ day: Int, hour: Int, minute: Int = 0) -> Date {
        DayKey(year: 2026, month: 11, day: day).date(calendar: calendar(), hour: hour, minute: minute)
    }

    func testSystemCalendarChoiceCannotChangeTheReminderYear() {
        for identifier in [Calendar.Identifier.gregorian, .buddhist, .japanese] {
            let components = NotificationPlanner.nextPlanReminderComponents(
                at: ClockTime(hour: 15, minute: 0), sentDay: nil, now: date(4, hour: 14),
                calendar: calendar(identifier))
            XCTAssertEqual(components.calendar?.identifier, .gregorian)
            XCTAssertEqual(components.year, 2026)
            XCTAssertEqual(components.date, date(4, hour: 15))
        }
    }

    func testSentTodayOrPassedTimeStillSelectsOnlyTheNextDay() {
        let sent = DayKey(year: 2026, month: 11, day: 4)
        for identifier in [Calendar.Identifier.gregorian, .buddhist, .japanese] {
            let beforeTime = NotificationPlanner.nextPlanReminderComponents(
                at: ClockTime(hour: 15, minute: 0), sentDay: sent, now: date(4, hour: 14),
                calendar: calendar(identifier))
            let atTime = NotificationPlanner.nextPlanReminderComponents(
                at: ClockTime(hour: 15, minute: 0), sentDay: nil, now: date(4, hour: 15),
                calendar: calendar(identifier))
            XCTAssertEqual(beforeTime.date, date(5, hour: 15))
            XCTAssertEqual(atTime.date, date(5, hour: 15))
        }
    }

    func testLocalDayComesFromTheInjectedTimeZone() {
        let now = date(5, hour: 0, minute: 30) // 同时是 UTC 的 11 月 4 日 16:30。
        let shanghai = NotificationPlanner.nextPlanReminderComponents(
            at: ClockTime(hour: 8, minute: 0), sentDay: nil, now: now, calendar: calendar(.buddhist))
        let utc = NotificationPlanner.nextPlanReminderComponents(
            at: ClockTime(hour: 18, minute: 0), sentDay: nil, now: now,
            calendar: calendar(.japanese, timeZone: "UTC"))
        XCTAssertEqual(shanghai.day, 5)
        XCTAssertEqual(shanghai.date, date(5, hour: 8))
        XCTAssertEqual(utc.day, 4)
        XCTAssertEqual(utc.date, date(5, hour: 2))
    }
}
