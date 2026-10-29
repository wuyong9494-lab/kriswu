import XCTest
@testable import ShiftCore

final class ArenaStageMetricsTests: XCTestCase {
    func testColdPeakSurvivesLongSessionAndStagesRemainIndependent() {
        var metrics = ArenaStageMetrics()
        metrics.record(.modelLoad, seconds: 0.4)
        for _ in 0..<108_000 {
            metrics.record(.simulation, seconds: 0.002)
            metrics.record(.ai, seconds: 0.001)
        }
        XCTAssertEqual(metrics[.modelLoad].peakMilliseconds, 400)
        XCTAssertEqual(metrics[.simulation].count, 108_000)
        XCTAssertEqual(metrics[.simulation].meanMilliseconds, 2, accuracy: 0.0001)
        XCTAssertEqual(metrics[.ai].meanMilliseconds, 1, accuracy: 0.0001)
        XCTAssertEqual(metrics[.animation].count, 0)
        metrics.reset()
        XCTAssertEqual(metrics[.modelLoad].count, 0)
        XCTAssertEqual(metrics[.simulation].peakMilliseconds, 0)
    }
    func testInvalidDurationsDoNotPoisonSummary() {
        var metrics = ArenaStageMetrics()
        for value in [Double.nan, .infinity, -.infinity, -1] {
            metrics.record(.sceneUpdate, seconds: value)
        }
        XCTAssertEqual(metrics[.sceneUpdate].count, 0)
        metrics.record(.sceneUpdate, seconds: 0)
        XCTAssertEqual(metrics[.sceneUpdate].count, 1)
        XCTAssertEqual(metrics[.sceneUpdate].meanMilliseconds, 0)
    }
}
