import XCTest
@testable import ShiftCore

final class TileDailyAttemptsTests: XCTestCase {
    private let day = DayKey(year: 2026, month: 11, day: 7)
    func testRetryAndRescueCannotRewriteFirstAttempt() {
        var ledger = TileDailyAttempts()
        ledger.begin(day: day, attemptID: "first")
        ledger.begin(day: day, attemptID: "first")
        ledger.observe(day: day, attemptID: "first", won: false, lost: true, toolsUsed: false)
        ledger.observe(day: day, attemptID: "first", won: true, lost: false, toolsUsed: true)
        ledger.begin(day: day, attemptID: "retry")
        ledger.observe(day: day, attemptID: "retry", won: true, lost: false, toolsUsed: false)
        let entry = ledger.entries[TileGame.dailyPlanningRecordKey(day)]
        XCTAssertEqual(entry?.attempts, 2)
        XCTAssertEqual(entry?.firstOutcome, .lost)
    }
    func testToolsDoNotCountAsUnassistedWin() {
        var ledger = TileDailyAttempts()
        ledger.begin(day: day, attemptID: "a")
        ledger.observe(day: day, attemptID: "a", won: true, lost: false, toolsUsed: true)
        XCTAssertEqual(ledger.entries[TileGame.dailyPlanningRecordKey(day)]?.firstOutcome, .usedTools)
    }
    func testInterruptedAttemptSurvivesStorageAndStaysSeparateFromNextDay() throws {
        var ledger = TileDailyAttempts()
        ledger.begin(day: day, attemptID: "interrupted")
        ledger = try JSONDecoder().decode(TileDailyAttempts.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(ledger.entries[TileGame.dailyPlanningRecordKey(day)]?.firstOutcome, .pending)
        ledger.begin(day: day, attemptID: "restart")
        XCTAssertEqual(ledger.entries[TileGame.dailyPlanningRecordKey(day)]?.firstOutcome, .abandoned)
        let tomorrow = day.adding(days: 1, calendar: .dayMath)
        ledger.begin(day: tomorrow, attemptID: "new-day")
        ledger.observe(day: tomorrow, attemptID: "new-day", won: true, lost: false, toolsUsed: false)
        XCTAssertEqual(ledger.entries[TileGame.dailyPlanningRecordKey(tomorrow)]?.firstOutcome, .wonWithoutTools)
        XCTAssertEqual(ledger.entries.count, 2)
    }
    func testQuitAndDuplicateObservationsAreIdempotent() {
        var ledger = TileDailyAttempts()
        ledger.begin(day: day, attemptID: "quit")
        ledger.observe(day: day, attemptID: "quit", won: false, lost: false, toolsUsed: false, abandoned: true)
        ledger.observe(day: day, attemptID: "quit", won: true, lost: false, toolsUsed: false)
        XCTAssertEqual(ledger.entries[TileGame.dailyPlanningRecordKey(day)]?.firstOutcome, .abandoned)
    }
}
