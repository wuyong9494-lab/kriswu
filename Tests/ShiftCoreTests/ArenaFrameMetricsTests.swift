import XCTest
@testable import ShiftCore

final class ArenaFrameMetricsTests: XCTestCase {
    func testSmoothAndStalledFrames() throws {
        var meter = ArenaFrameMetrics()
        for _ in 0..<114 { meter.record(interval: 1.0 / 60, simulation: 0.002, scene: 0.004) }
        for _ in 0..<6 { meter.record(interval: 0.1, simulation: 0.002, scene: 0.004) }
        let report = try XCTUnwrap(meter.report())
        XCTAssertEqual(report.samples, 120)
        XCTAssertEqual(report.slowFrames, 6)
        XCTAssertEqual(report.fps, 48, accuracy: 0.001)
        XCTAssertEqual(report.p95Milliseconds, 1000.0 / 60, accuracy: 0.001)
        XCTAssertEqual(report.simulationMilliseconds, 2, accuracy: 0.001)
        XCTAssertEqual(report.sceneMilliseconds, 4, accuracy: 0.001)
    }

    func testWindowEvictsOldStallAndResetDropsHistory() throws {
        var meter = ArenaFrameMetrics()
        meter.record(interval: 2, simulation: 0, scene: 0)
        for _ in 0..<120 { meter.record(interval: 1.0 / 60, simulation: 0, scene: 0) }
        let report = try XCTUnwrap(meter.report())
        XCTAssertEqual(report.samples, 120)
        XCTAssertEqual(report.slowFrames, 0)
        XCTAssertEqual(report.fps, 60, accuracy: 0.001)
        meter.reset()
        XCTAssertNil(meter.report())
        meter.record(interval: 0.05, simulation: 0.001, scene: 0.002)
        XCTAssertEqual(meter.report()?.samples, 1)
    }

    func testRejectsInvalidSamples() {
        var meter = ArenaFrameMetrics()
        for interval in [0, -1, Double.nan, .infinity] {
            meter.record(interval: interval, simulation: 0, scene: 0)
        }
        meter.record(interval: 0.02, simulation: -.infinity, scene: 0)
        meter.record(interval: 0.02, simulation: 0, scene: .nan)
        XCTAssertNil(meter.report())
    }
}
