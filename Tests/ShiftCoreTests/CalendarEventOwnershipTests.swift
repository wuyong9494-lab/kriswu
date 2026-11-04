import Foundation
import XCTest
@testable import ShiftCore

final class CalendarEventOwnershipTests: XCTestCase {
    private let identity = CalendarEventOwnership(
        calendarIdentifier: "created-calendar",
        ownerToken: UUID(uuidString: "1D973E24-5DB9-4E0F-B024-A121C9BAC233")!)
    private let day = DayKey(year: 2026, month: 11, day: 4)

    func testExactManagedEventCanBeReconciled() {
        XCTAssertEqual(identity.managedDay(eventURL: identity.eventURL(for: day),
                                          calendarIdentifier: identity.calendarIdentifier), day)
    }

    func testLegacyAndUserEventsStayUnmanagedEvenInTheSameCalendar() {
        for url in [nil, URL(string: "https://example.com/2026-11-04"),
                    URL(string: "shiftreminder://calendar/2026-11-04")] as [URL?] {
            XCTAssertNil(identity.managedDay(eventURL: url, calendarIdentifier: identity.calendarIdentifier))
        }
    }

    func testAnotherCalendarOrOwnerCannotBeAdopted() {
        let otherOwner = CalendarEventOwnership(calendarIdentifier: identity.calendarIdentifier,
                                               ownerToken: UUID())
        XCTAssertNil(identity.managedDay(eventURL: otherOwner.eventURL(for: day),
                                         calendarIdentifier: identity.calendarIdentifier))
        XCTAssertNil(identity.managedDay(eventURL: identity.eventURL(for: day),
                                         calendarIdentifier: "same-title-user-calendar"))
    }

    func testSimilarOrExtendedMarkersCannotAuthorizeChanges() {
        let marker = identity.eventURL(for: day).absoluteString
        let altered = [marker + "?copy=1", marker + "#copy", marker + "/extra", marker + "/",
                       marker.replacingOccurrences(of: "managed-calendar", with: "managed-calendar-copy"),
                       marker.replacingOccurrences(of: "/v2/", with: "/v1/"),
                       marker.replacingOccurrences(of: "2026-11-04", with: "2026-11-4"),
                       marker.replacingOccurrences(of: "2026-11-04", with: "2026-02-30")]
        for raw in altered {
            XCTAssertNil(identity.managedDay(eventURL: URL(string: raw),
                                             calendarIdentifier: identity.calendarIdentifier), raw)
        }
    }

    func testOnlyMarkedEventIsSelectedAmongSameDayUserAndLegacyEvents() {
        let urls: [URL?] = [nil, URL(string: "https://example.com/meeting"), identity.eventURL(for: day), nil]
        let selected = urls.enumerated().compactMap { index, url in
            identity.managedDay(eventURL: url, calendarIdentifier: identity.calendarIdentifier) == nil ? nil : index
        }
        XCTAssertEqual(selected, [2])
    }

    func testPersistedIdentityRequiresBothCalendarAndOwner() throws {
        let data = try JSONEncoder().encode(identity)
        XCTAssertEqual(try JSONDecoder().decode(CalendarEventOwnership.self, from: data), identity)
        for raw in [#"{"calendarIdentifier":"created-calendar"}"#,
                    #"{"calendarIdentifier":"created-calendar","ownerToken":"not-a-uuid"}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(CalendarEventOwnership.self, from: Data(raw.utf8)))
        }
    }
}
