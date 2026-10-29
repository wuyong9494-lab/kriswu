import XCTest
@testable import ShiftCore

final class ArenaSessionMetricsTests: XCTestCase {
    func testSessionRetainsEarlyStallsBeyondRollingWindow() {
        var metrics = ArenaSessionMetrics()
        metrics.record(interval: 0.0563, work: 0.0085)
        for _ in 0..<1800 { metrics.record(interval: 1.0 / 60, work: 0.003) }
        XCTAssertEqual(metrics.count, 1801)
        XCTAssertEqual(metrics.slowCount, 1)
        XCTAssertEqual(metrics.maximum, 0.0563)
        XCTAssertEqual(metrics.percentileMilliseconds(0.95), 17)
        XCTAssertEqual(metrics.percentileMilliseconds(1), 57)
        XCTAssertEqual(metrics.duration, 30.0563, accuracy: 0.00001)
    }
    func testInvalidAndLongIntervals() {
        var metrics = ArenaSessionMetrics()
        metrics.record(interval: .infinity, work: 0)
        metrics.record(interval: 0, work: 0)
        XCTAssertNil(metrics.percentileMilliseconds(0.95))
        metrics.record(interval: 3, work: 0.01)
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics.percentileMilliseconds(0.95), 1000)
        XCTAssertEqual(metrics.maximum, 3)
    }
    func testBenchmarkHasStableTeamsMapAndSeed() {
        let a = ArenaBenchmark.game(), b = ArenaBenchmark.game()
        XCTAssertEqual(a.map.id, "canyon")
        XCTAssertEqual(a.fighters.map(\.brawler), b.fighters.map(\.brawler))
        XCTAssertEqual(a.fighters.map(\.pos), b.fighters.map(\.pos))
        XCTAssertEqual(a.fighters.map(\.team), [0, 0, 0, 1, 1, 1])
        XCTAssertTrue(a.fighters.allSatisfy(\.isBot))
    }
}
