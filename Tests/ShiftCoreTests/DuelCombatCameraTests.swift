import XCTest
@testable import ShiftCore

final class DuelCombatCameraTests: XCTestCase {
    func testRepeatedPresentationDoesNotMoveCameraOrReplayContact() {
        var camera = DuelCombatCamera()
        camera.consume(frame: 1, animationTick: 1, firstX: 6, secondX: 9,
                       impacts: [.init(kind: .heavy, direction: -1)])
        let first = camera
        for _ in 0..<120 {
            _ = camera.impactOffsetX; _ = camera.impactOffsetY
            camera.consume(frame: 1, animationTick: 1, firstX: 6, secondX: 9,
                           impacts: [.init(kind: .heavy, direction: -1)])
            XCTAssertEqual(camera, first)
        }
    }

    func testHitStopFreezesFramingWhileContactRecoilSettles() {
        var camera = DuelCombatCamera()
        camera.consume(frame: 12, animationTick: 12, firstX: 6, secondX: 8,
                       impacts: [.init(kind: .heavy, direction: 1)])
        let center = camera.centerX, separation = camera.separation
        let contactOffset = camera.impactOffsetX
        camera.consume(frame: 13, animationTick: 12, firstX: 6, secondX: 8)
        XCTAssertEqual(camera.centerX, center)
        XCTAssertEqual(camera.separation, separation)
        XCTAssertLessThan(abs(camera.impactOffsetX), abs(contactOffset))
        for frame in 14...30 {
            camera.consume(frame: frame, animationTick: 12, firstX: 6, secondX: 8)
        }
        XCTAssertEqual(camera.impactOffsetX, 0)
        XCTAssertEqual(camera.impactOffsetY, 0)
        XCTAssertEqual(camera.centerX, center)
    }

    func testConfirmedImpactStrengthAndDirectionRemainDistinct() {
        func impulse(_ kind: DuelCombatCamera.Impact.Kind, direction: Int) -> Double {
            var camera = DuelCombatCamera()
            camera.consume(frame: 1, animationTick: 1, firstX: 4, secondX: 6,
                           impacts: [.init(kind: kind, direction: direction)])
            return camera.impactOffsetX
        }
        XCTAssertGreaterThan(impulse(.heavy, direction: 1), impulse(.light, direction: 1))
        XCTAssertGreaterThan(impulse(.light, direction: 1), impulse(.block, direction: 1))
        XCTAssertEqual(impulse(.heavy, direction: -1), -impulse(.heavy, direction: 1))
        XCTAssertLessThanOrEqual(abs(impulse(.heavy, direction: 1)), 0.10)
        var idle = DuelCombatCamera()
        idle.consume(frame: 1, animationTick: 1, firstX: 4, secondX: 6)
        XCTAssertEqual(idle.impactOffsetX, 0, "Movement or an attack press alone is not a contact")
    }

    func testNewContactCanRestartSettledImpulseAndWeakBlockCannotEraseHeavyHit() {
        var camera = DuelCombatCamera()
        camera.consume(frame: 1, animationTick: 1, firstX: 4, secondX: 6,
                       impacts: [.init(kind: .heavy, direction: 1), .init(kind: .block, direction: -1)])
        XCTAssertEqual(camera.impactOffsetX, 0.065, accuracy: 0.000001)
        camera.consume(frame: 2, animationTick: 1, firstX: 4, secondX: 6,
                       impacts: [.init(kind: .block, direction: -1)])
        XCTAssertEqual(camera.impactOffsetX, 0.065 * 0.70 * cos(2.4), accuracy: 0.000001)
        camera.consume(frame: 30, animationTick: 22, firstX: 4, secondX: 6,
                       impacts: [.init(kind: .light, direction: -1)])
        XCTAssertEqual(camera.impactOffsetX, -0.028, accuracy: 0.000001)
    }

    func testOpeningShotCentersPairAtEitherStageEdge() {
        var right = DuelCombatCamera()
        right.consume(frame: 0, animationTick: 0, firstX: 8, secondX: 9.65)
        XCTAssertEqual(right.centerX, 8.5, accuracy: 0.000001)
        XCTAssertGreaterThanOrEqual(right.separation * 0.5, 9.65 - right.centerX)

        var left = DuelCombatCamera()
        left.consume(frame: 0, animationTick: 0, firstX: 0.35, secondX: 2)
        XCTAssertEqual(left.centerX, 1.5, accuracy: 0.000001)
        XCTAssertGreaterThanOrEqual(left.separation * 0.5, left.centerX - 0.35)

        // Re-rendering an identical simulation frame must not re-snap or drift.
        let unchanged = right
        right.consume(frame: 0, animationTick: 0, firstX: 0, secondX: 1)
        XCTAssertEqual(right, unchanged)
    }

    func testTrackingLagIsIncludedAndZoomReturnsGradually() {
        var camera = DuelCombatCamera()
        camera.consume(frame: 1, animationTick: 1, firstX: 6, secondX: 8)
        XCTAssertEqual(camera.centerX, 7, accuracy: 0.000001)
        camera.consume(frame: 2, animationTick: 2, firstX: 8, secondX: 9.65)
        XCTAssertGreaterThan(camera.centerX, 7)
        XCTAssertLessThan(camera.centerX, 8.5)
        XCTAssertGreaterThanOrEqual(camera.separation * 0.5, 9.65 - camera.centerX)
        let expanded = camera.separation
        camera.consume(frame: 3, animationTick: 3, firstX: 7.25, secondX: 8.25)
        XCTAssertLessThan(camera.separation, expanded)
        XCTAssertGreaterThan(camera.separation,
                             2 * max(abs(7.25 - camera.centerX), abs(8.25 - camera.centerX)))
        camera.consume(frame: 4, animationTick: 4, firstX: 0.35, secondX: 9.65)
        XCTAssertGreaterThanOrEqual(camera.separation * 0.5,
                                   max(abs(0.35 - camera.centerX), abs(9.65 - camera.centerX)))
    }

    func testRoundRepositionSnapsCameraToTheNewPairCenter() {
        var camera = DuelCombatCamera()
        camera.consume(frame: 10, animationTick: 10, firstX: 7.5, secondX: 9.2)
        XCTAssertEqual(camera.centerX, 8.35, accuracy: 0.000001)

        // Both fighters were placed back in their opening positions together.
        // Stale eased tracking should not leave the new round off center.
        camera.consume(frame: 11, animationTick: 11, firstX: 3.5, secondX: 6.5)
        XCTAssertEqual(camera.centerX, 5, accuracy: 0.000001)
        XCTAssertGreaterThanOrEqual(camera.separation * 0.5,
                                   max(abs(3.5 - camera.centerX), abs(6.5 - camera.centerX)))

        // An isolated dash / knockback is not a round reset.
        var dash = DuelCombatCamera()
        dash.consume(frame: 10, animationTick: 10, firstX: 7, secondX: 8)
        dash.consume(frame: 11, animationTick: 11, firstX: 4, secondX: 8)
        XCTAssertGreaterThan(dash.centerX, 6)
        XCTAssertLessThan(dash.centerX, 7.5)
        XCTAssertGreaterThanOrEqual(dash.separation * 0.5,
                                   max(abs(4 - dash.centerX), abs(8 - dash.centerX)))
    }

    func testRepositionStateResetsAfterRewindAndIgnoresInvalidSamples() {
        var camera = DuelCombatCamera()
        camera.consume(frame: 1, animationTick: 1, firstX: 7.5, secondX: 9)
        let before = camera
        camera.consume(frame: 2, animationTick: 2, firstX: .nan, secondX: 6)
        XCTAssertEqual(camera, before)
        camera.consume(frame: 0, animationTick: 0, firstX: 3.5, secondX: 6.5)
        var fresh = DuelCombatCamera()
        fresh.consume(frame: 0, animationTick: 0, firstX: 3.5, secondX: 6.5)
        XCTAssertEqual(camera, fresh)
    }

    func testSkippedSamplesUseElapsedTicksInsteadOfOneDrawWorthOfMovement() {
        var everyTick = DuelCombatCamera(), batched = DuelCombatCamera()
        for tick in 1...30 {
            everyTick.consume(frame: tick, animationTick: tick, firstX: 6, secondX: 8)
        }
        batched.consume(frame: 30, animationTick: 30, firstX: 6, secondX: 8)
        XCTAssertEqual(everyTick.centerX, batched.centerX, accuracy: 0.000001)
    }

    func testRewindResetsAndInvalidGeometryCannotPoisonPresentation() {
        var camera = DuelCombatCamera()
        camera.consume(frame: 10, animationTick: 10, firstX: 8, secondX: 9,
                       impacts: [.init(kind: .heavy, direction: 1)])
        let before = camera
        for value in [Double.nan, .infinity, -.infinity] {
            camera.consume(frame: 11, animationTick: 11, firstX: value, secondX: 9)
            XCTAssertEqual(camera, before)
        }
        camera.consume(frame: 0, animationTick: 0, firstX: 3.5, secondX: 6.5)
        var fresh = DuelCombatCamera()
        fresh.consume(frame: 0, animationTick: 0, firstX: 3.5, secondX: 6.5)
        XCTAssertEqual(camera, fresh)
        camera.consume(frame: Int.max, animationTick: Int.max,
                       firstX: Double.greatestFiniteMagnitude, secondX: -Double.greatestFiniteMagnitude)
        XCTAssertTrue(camera.centerX.isFinite)
        XCTAssertTrue(camera.separation.isFinite)
        XCTAssertTrue(camera.impactOffsetX.isFinite)
    }
}
