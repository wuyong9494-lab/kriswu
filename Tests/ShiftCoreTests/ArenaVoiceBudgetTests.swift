import XCTest
@testable import ShiftCore

final class ArenaVoiceBudgetTests: XCTestCase {
    func testCrowdedFrameReservesCriticalCapacityAndReusesExpiredVoices() {
        var budget = ArenaVoiceBudget()
        var slots = Set<Int>()
        for i in 0..<8 {
            slots.insert(budget.reserve(effect: "shot\(i)", limit: 5, critical: false, duration: 1, now: 10)!)
        }
        XCTAssertEqual(slots.count, 8)
        XCTAssertNil(budget.reserve(effect: "boom", limit: 3, critical: false, duration: 1, now: 10))
        for i in 0..<4 {
            XCTAssertNotNil(budget.reserve(effect: "hit\(i)", limit: 5, critical: true, duration: 1, now: 10))
        }
        XCTAssertNil(budget.reserve(effect: "respawn", limit: 2, critical: true, duration: 1, now: 10))
        XCTAssertNotNil(budget.reserve(effect: "shot", limit: 5, critical: false, duration: 1, now: 11.1))
    }
    func testThrottlePerEffectAndPauseReset() {
        var budget = ArenaVoiceBudget()
        XCTAssertNotNil(budget.reserve(effect: "shot", limit: 2, critical: false, duration: 1, now: 10))
        XCTAssertNil(budget.reserve(effect: "shot", limit: 2, critical: false, duration: 1, now: 10.01))
        XCTAssertNotNil(budget.reserve(effect: "shot", limit: 2, critical: false, duration: 1, now: 10.04))
        XCTAssertNil(budget.reserve(effect: "shot", limit: 2, critical: false, duration: 1, now: 10.08))
        budget.reset()
        XCTAssertNotNil(budget.reserve(effect: "shot", limit: 2, critical: false, duration: 1, now: 10.09))
    }
}
