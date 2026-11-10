import XCTest
@testable import ShiftCore

final class DuelNetworkPulseScheduleTests: XCTestCase {
    private typealias Schedule = DuelNetworkPulseSchedule
    private let interval = Schedule.intervalNanoseconds

    func testInitialWakeAndServiceWorkShareOneIntervalBudget() throws {
        let start: UInt64 = 7_000_000_000
        var schedule = try XCTUnwrap(Schedule(startingAt: start))
        XCTAssertEqual(schedule.sleepNanoseconds(at: start), interval)
        XCTAssertEqual(schedule.sleepNanoseconds(at: start + 500), interval - 500)
        let firstWake = start + interval
        XCTAssertEqual(schedule.sleepNanoseconds(at: firstWake), 0)
        let completed = firstWake + 5_000_000
        XCTAssertTrue(schedule.advance(afterPulseAt: completed))
        XCTAssertEqual(schedule.nextDeadline, start + 2 * interval)
        XCTAssertEqual(schedule.sleepNanoseconds(at: completed), interval - 5_000_000)
    }

    func testServiceCostDoesNotAccumulateClockDrift() throws {
        for cost in [UInt64(0), 1_000_000, 3_000_000, 5_000_000] {
            let start: UInt64 = 99_000_000_000
            var schedule = try XCTUnwrap(Schedule(startingAt: start))
            for pulse in UInt64(1)...600 {
                let wake = start + pulse * interval
                XCTAssertEqual(schedule.nextDeadline, wake)
                XCTAssertEqual(schedule.sleepNanoseconds(at: wake), 0)
                XCTAssertTrue(schedule.advance(afterPulseAt: wake + cost))
                XCTAssertEqual(schedule.sleepNanoseconds(at: wake + cost), interval - cost)
            }
            XCTAssertEqual(schedule.nextDeadline, start + 601 * interval)
            // The previous relative-sleep loop adds the previous 599 service
            // costs to the start of pulse 600. These are modeled, not device times.
            let previousLoopLastWake = start + 600 * interval + 599 * cost
            XCTAssertEqual(previousLoopLastWake - (start + 600 * interval), 599 * cost)
        }
    }

    func testWakeJitterDoesNotMoveTheDeadlineGrid() throws {
        var schedule = try XCTUnwrap(Schedule(startingAt: 0))
        for pulse in UInt64(1)...600 {
            let jitter = (pulse % 5) * 1_000_000
            let wake = pulse * interval + jitter
            XCTAssertEqual(schedule.sleepNanoseconds(at: wake), 0)
            let completed = wake + 2_000_000
            XCTAssertTrue(schedule.advance(afterPulseAt: completed))
            XCTAssertEqual(schedule.nextDeadline, (pulse + 1) * interval)
            XCTAssertEqual(schedule.sleepNanoseconds(at: completed), interval - jitter - 2_000_000)
        }
    }

    func testLateWakeSkipsMissedDeadlinesWithoutCatchup() throws {
        var schedule = try XCTUnwrap(Schedule(startingAt: 0))
        let late = 9 * interval + 3_000_000
        XCTAssertEqual(schedule.sleepNanoseconds(at: late), 0)
        XCTAssertTrue(schedule.advance(afterPulseAt: late))
        XCTAssertEqual(schedule.nextDeadline, 10 * interval)
        XCTAssertEqual(schedule.sleepNanoseconds(at: late), interval - 3_000_000)
        XCTAssertFalse(schedule.advance(afterPulseAt: late), "No second pulse at the same late time")
    }

    func testSlowServiceAndExactBoundarySkipExpiredDeadlines() throws {
        var schedule = try XCTUnwrap(Schedule(startingAt: 0))
        XCTAssertEqual(schedule.sleepNanoseconds(at: interval), 0)
        XCTAssertTrue(schedule.advance(afterPulseAt: 4 * interval))
        XCTAssertEqual(schedule.nextDeadline, 5 * interval)
        XCTAssertEqual(schedule.sleepNanoseconds(at: 4 * interval), interval)
    }

    func testLargeGapIsBoundedAndDoesNotAuthorizeSimulationCatchup() throws {
        var schedule = try XCTUnwrap(Schedule(startingAt: 0))
        let late: UInt64 = 86_400_000_000_000
        XCTAssertEqual(schedule.sleepNanoseconds(at: late), 0)
        // The coordinator's unchanged watchdog rejects a 250 ms-plus running
        // gap before stepping. This helper only computes a bounded future wake.
        XCTAssertTrue(schedule.advance(afterPulseAt: late))
        XCTAssertGreaterThan(schedule.nextDeadline, late)
        XCTAssertLessThanOrEqual(schedule.nextDeadline - late, interval)
        XCTAssertEqual(schedule.nextDeadline % interval, 0)
    }

    func testClockRegressionAndEarlyAdvanceAreAtomic() throws {
        var schedule = try XCTUnwrap(Schedule(startingAt: 1_000))
        let original = schedule
        XCTAssertNil(schedule.sleepNanoseconds(at: 999))
        XCTAssertFalse(schedule.advance(afterPulseAt: 999))
        XCTAssertFalse(schedule.advance(afterPulseAt: 1_000))
        XCTAssertEqual(schedule, original)
        XCTAssertEqual(schedule.sleepNanoseconds(at: 2_000), interval - 1_000)
        let observed = schedule
        XCTAssertNil(schedule.sleepNanoseconds(at: 1_999))
        XCTAssertFalse(schedule.advance(afterPulseAt: 1_999))
        XCTAssertEqual(schedule, observed)
        let completed = 1_000 + interval
        XCTAssertTrue(schedule.advance(afterPulseAt: completed))
        let advanced = schedule
        XCTAssertNil(schedule.sleepNanoseconds(at: completed - 1))
        XCTAssertFalse(schedule.advance(afterPulseAt: completed - 1))
        XCTAssertEqual(schedule, advanced)
    }

    func testDeadlineOverflowIsRejectedWithoutWrapping() throws {
        XCTAssertNil(Schedule(startingAt: UInt64.max))
        XCTAssertNil(Schedule(startingAt: UInt64.max - interval + 1))
        var schedule = try XCTUnwrap(Schedule(startingAt: UInt64.max - interval))
        XCTAssertEqual(schedule.nextDeadline, UInt64.max)
        let original = schedule
        XCTAssertFalse(schedule.advance(afterPulseAt: UInt64.max))
        XCTAssertEqual(schedule, original)
        var nearEnd = try XCTUnwrap(Schedule(startingAt: UInt64.max - 3 * interval))
        XCTAssertTrue(nearEnd.advance(afterPulseAt: UInt64.max - 2 * interval))
        XCTAssertEqual(nearEnd.nextDeadline, UInt64.max - interval)
        XCTAssertTrue(nearEnd.advance(afterPulseAt: UInt64.max - interval))
        XCTAssertEqual(nearEnd.nextDeadline, UInt64.max)
        XCTAssertFalse(nearEnd.advance(afterPulseAt: UInt64.max))
    }
}
