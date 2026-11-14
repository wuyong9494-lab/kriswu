import XCTest
@testable import ShiftCore

final class DuelImpactMotionTests: XCTestCase {
    func testIntegerRecoilSpreadsTheExactDistanceAcrossTicksAndMirrors() throws {
        for (distance, duration) in [(65, 6), (200, 10), (1, 7), (0, 3)] {
            for direction in [-1, 1] {
                let response = DuelImpactResponse(distanceMillimeters: distance, durationTicks: duration)
                var motion = try XCTUnwrap(DuelImpactMotion(response: response, direction: direction))
                var x = 5000
                var samples: [Int] = []
                for _ in 0..<duration {
                    let sample = motion.advance(x: x, y: 0, velocityY: 0)
                    XCTAssertGreaterThanOrEqual((sample.x - x) * direction, 0)
                    XCTAssertEqual(sample.y, 0); XCTAssertEqual(sample.velocityY, 0)
                    XCTAssertFalse(sample.landed)
                    x = sample.x; samples.append(x)
                }
                XCTAssertEqual(x, 5000 + direction * distance)
                XCTAssertEqual(motion.appliedHorizontalDistance, distance)
                XCTAssertTrue(motion.horizontalFinished)
                if distance > 1 { XCTAssertNotEqual(samples.first, samples.last) }
                for _ in 0..<20 {
                    XCTAssertEqual(motion.advance(x: x, y: 0, velocityY: 0).x, x)
                }
            }
        }
    }

    func testWallCancelsRemainingImpulseInsteadOfSavingItForLater() throws {
        for direction in [-1, 1] {
            let response = DuelImpactResponse(distanceMillimeters: 200, durationTicks: 10)
            var motion = try XCTUnwrap(DuelImpactMotion(response: response, direction: direction))
            let wall = direction > 0 ? DuelGame.rightWall : DuelGame.leftWall
            let first = motion.advance(x: wall - direction * 10, y: 0, velocityY: 0)
            XCTAssertEqual(first.x, wall)
            XCTAssertTrue(motion.horizontalStopped)
            XCTAssertEqual(motion.appliedHorizontalDistance, 10)
            // A later push/root-motion step away from the wall must not
            // resurrect the discarded horizontal impulse.
            XCTAssertEqual(motion.advance(x: wall - direction * 100, y: 0, velocityY: 0).x,
                           wall - direction * 100)
        }
    }

    func testExplicitBallisticResponseLandsExactlyOnce() throws {
        let response = DuelImpactResponse(distanceMillimeters: 0, durationTicks: 4,
                                          launchVelocityMillimetersPerTick: 80,
                                          gravityMillimetersPerTickSquared: 20)
        var motion = try XCTUnwrap(DuelImpactMotion(response: response, direction: 1))
        var y = 0, velocity = response.launchVelocityMillimetersPerTick
        var heights: [Int] = [], landings = 0
        for _ in 0..<12 {
            let sample = motion.advance(x: 5000, y: y, velocityY: velocity)
            y = sample.y; velocity = sample.velocityY; heights.append(y)
            if sample.landed { landings += 1 }
        }
        XCTAssertEqual(heights, [80, 140, 180, 200, 200, 180, 140, 80, 0, 0, 0, 0])
        XCTAssertEqual(landings, 1); XCTAssertEqual(velocity, 0)
    }

    func testInvalidResponseAndDirectionFailBeforeAnyArithmetic() {
        let invalid = [
            DuelImpactResponse(distanceMillimeters: -1, durationTicks: 6),
            .init(distanceMillimeters: Int.max, durationTicks: 6),
            .init(distanceMillimeters: 65, durationTicks: 0),
            .init(distanceMillimeters: 65, durationTicks: Int.max),
            .init(distanceMillimeters: 65, durationTicks: 6, launchVelocityMillimetersPerTick: -1),
            .init(distanceMillimeters: 65, durationTicks: 6, gravityMillimetersPerTickSquared: 0),
            .init(distanceMillimeters: 65, durationTicks: 6,
                  launchVelocityMillimetersPerTick: 1000, gravityMillimetersPerTickSquared: 1)
        ]
        for response in invalid {
            XCTAssertFalse(response.isValid)
            XCTAssertNil(DuelImpactMotion(response: response, direction: 1))
        }
        XCTAssertNil(DuelImpactMotion(response: .init(distanceMillimeters: 65, durationTicks: 6), direction: 0))
    }

    func testReplayIncludesInvisibleMotionProgress() throws {
        var motion = try XCTUnwrap(DuelImpactMotion(response: .init(distanceMillimeters: 0, durationTicks: 6), direction: 1))
        var first = try DuelReplayStateWriter(kind: 2)
        try motion.appendReplayState(to: &first)
        let sample = motion.advance(x: 5000, y: 0, velocityY: 0)
        XCTAssertEqual(sample.x, 5000); XCTAssertEqual(sample.y, 0)
        var second = try DuelReplayStateWriter(kind: 2)
        try motion.appendReplayState(to: &second)
        XCTAssertNotEqual(first.data, second.data, "A later remaining impulse must not share the same replay state")
    }
}
