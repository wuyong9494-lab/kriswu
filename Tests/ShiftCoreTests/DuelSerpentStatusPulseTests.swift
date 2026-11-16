import XCTest
@testable import ShiftCore

final class DuelSerpentStatusPulseTests: XCTestCase {
    // Independent native proof: UnityFramework SHA 7c192647...62a55b,
    // constructor 39053 @ 0x7157750; updater 37019 @ 0x70edea4.
    // The private oracle pins all 29 factory/clock/receiver method byte ranges.
    func testDefaultTenTickPulsesStartAtTenAndFinishExactlyAtNineHundred() {
        var status = DuelSerpentStatusPulse(rate: -0.1, duration: 900, createdAt: 0)
        XCTAssertEqual(status.accumulated, 0)
        var emitted: [Int] = []
        for tick in 1...900 {
            if let pulse = status.advance(now: Float(tick)) {
                emitted.append(tick)
                XCTAssertEqual(pulse.bitPattern, 0xbf800000, "10 source ticks × -0.1 = -1 normalized unit")
            }
        }
        XCTAssertEqual(emitted, Array(stride(from: 10, through: 900, by: 10)))
        XCTAssertFalse(status.active); XCTAssertNil(status.advance(now: 901))
    }

    func testExpiryFlushesRemainderAndOneTickStatusIsDeferred() {
        var status = DuelSerpentStatusPulse(rate: -0.002, duration: 25, createdAt: 0)
        var emitted: [Int] = [], magnitudes: [Float] = []
        for tick in 1...25 {
            if let pulse = status.advance(now: Float(tick)) { emitted.append(tick); magnitudes.append(pulse) }
        }
        XCTAssertEqual(emitted, [10, 20, 25])
        XCTAssertEqual(magnitudes, [Float(-0.002) * 10, Float(-0.002) * 10, Float(-0.002) * 5])
        var explosion = DuelSerpentStatusPulse(rate: -0.09, duration: 1, createdAt: 30)
        XCTAssertTrue(explosion.active); XCTAssertEqual(explosion.accumulated, 0)
        XCTAssertEqual(explosion.advance(now: 31), Float(-0.09))
        XCTAssertFalse(explosion.active); XCTAssertNil(explosion.advance(now: 32))
    }

    func testReplacementDropsPendingElapsedAndCapturesItsNewRate() {
        var status = DuelSerpentStatusPulse(rate: -0.1, duration: 900, createdAt: 0)
        for tick in 1...7 { XCTAssertNil(status.advance(now: Float(tick))) }
        XCTAssertEqual(status.accumulated, 7)
        status = DuelSerpentStatusPulse(rate: -0.025, duration: 893, createdAt: 7)
        for tick in 8...16 { XCTAssertNil(status.advance(now: Float(tick))) }
        XCTAssertEqual(status.advance(now: 17), Float(-0.25))
        XCTAssertEqual(status.accumulated, 0)
        status = DuelSerpentStatusPulse()
        XCTAssertNil(status.advance(now: 900), "Explicit removal never flushes a remainder")
    }

    func testFractionalAndLargeDeltasFollowTheNativeSingleDispatchBranch() {
        var slow = DuelSerpentStatusPulse(rate: -0.1, duration: 25, createdAt: 0)
        var emitted: [Float] = []
        for step in 1...50 {
            if slow.advance(now: Float(step) * 0.5, delta: 0.5) != nil { emitted.append(Float(step) * 0.5) }
        }
        XCTAssertEqual(emitted, [10, 20, 25])
        var large = DuelSerpentStatusPulse(rate: -0.1, duration: 100, createdAt: 0)
        XCTAssertEqual(large.advance(now: 25, delta: 25), Float(-0.1) * 25)
        XCTAssertEqual(large.accumulated, 15, "Native code subtracts one interval, not a while-loop")
        var beforePhase = DuelSerpentStatusPulse(rate: -0.09, duration: 1, createdAt: 30)
        XCTAssertNil(beforePhase.advance(now: 30))
        XCTAssertEqual(beforePhase.advance(now: 31), Float(-0.09) * 2,
                       "The kernel must not silently clamp a caller's creation-phase difference")
    }
}
