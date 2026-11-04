import XCTest
@testable import ShiftCore

final class NotificationMemoTests: XCTestCase {
    func testCanonicalMemoWinsWhenLegacyKeysNameTheSameDay() {
        let day = DayKey(year: 2026, month: 1, day: 1)
        let result = NotificationPlanner.normalizedMemos([
            "2026-1-1": "旧备忘",
            "2026-01-01": "界面中保存的备忘",
        ])
        XCTAssertEqual(result, [day: "界面中保存的备忘"])
    }

    func testLegacyOnlyKeysResolveDeterministicallyAndInvalidDatesAreIgnored() {
        let day = DayKey(year: 2026, month: 1, day: 1)
        let pairs = [("2026-1-01", "日补零"), ("2026-01-1", "月补零"),
                     ("2026-02-30", "无效日期"), ("不是日期", "无效日期")]
        let forward = NotificationPlanner.normalizedMemos(Dictionary(uniqueKeysWithValues: pairs))
        let reverse = NotificationPlanner.normalizedMemos(Dictionary(uniqueKeysWithValues: pairs.reversed()))
        XCTAssertEqual(forward, [day: "月补零"])
        XCTAssertEqual(reverse, forward)
    }

    func testCanonicalEmptyMemoDoesNotResurrectLegacyText() {
        let day = DayKey(year: 2026, month: 10, day: 1)
        let result = NotificationPlanner.normalizedMemos([
            "2026-010-01": "旧备忘",
            "2026-10-01": "",
        ])
        XCTAssertEqual(result, [day: ""])
    }
}
