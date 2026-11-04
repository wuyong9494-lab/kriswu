import Foundation
import XCTest
@testable import ShiftCore

final class DayKeyParsingTests: XCTestCase {
    func testRejectsExtraOrMissingComponentsInsteadOfDroppingThem() {
        for raw in ["2026-x-11-04", "2026-11-ignore-04", "2026-11-04-extra",
                    "-2026-11-04", "2026--11-04", "2026-11-04-", "2026-11", "+2026-11-04"] {
            XCTAssertNil(DayKey(string: raw), raw)
        }
    }

    func testKeepsValidLegacyUnpaddedDatesAndCalendarValidation() {
        XCTAssertEqual(DayKey(string: "2026-1-2")?.description, "2026-01-02")
        XCTAssertEqual(DayKey(string: "2028-02-29")?.description, "2028-02-29")
        for raw in ["2026-02-29", "2026-04-31", "2026-13-01", "2026-00-01", "2026-11-00"] {
            XCTAssertNil(DayKey(string: raw), raw)
        }
    }

    func testMalformedPersistedDayFailsDecodingInsteadOfChangingItsDate() {
        XCTAssertThrowsError(try JSONDecoder().decode(DayKey.self, from: Data("\"2026-bad-11-04\"".utf8)))
        XCTAssertEqual(try JSONDecoder().decode(DayKey.self, from: Data("\"2026-11-04\"".utf8)),
                       DayKey(year: 2026, month: 11, day: 4))
    }
}
