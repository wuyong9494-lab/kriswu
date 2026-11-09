import XCTest
@testable import ShiftCore

final class DuelWeaponInputTests: XCTestCase {
    func testNeutralTapAndHeavyHoldAreExclusiveAndNeverRepeatWhileHeld() {
        var input = DuelWeaponInput()
        input.press(.weapon)
        XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
        input.release(.weapon)
        XCTAssertEqual(input.consume(facing: 1, airborne: false).weaponCommand, .weapon)
        XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)

        input.press(.weapon)
        for _ in 1..<DuelWeaponInput.longPressTicks {
            XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
        }
        XCTAssertEqual(input.consume(facing: 1, airborne: false).weaponCommand, .heavy)
        for _ in 0..<60 { XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand) }
        input.release(.weapon)
        XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand,
                     "Releasing a completed hold must not emit another light attack")
    }

    func testDirectionsResolveRelativeToFacingAndVerticalChordsDoNotJump() {
        for facing in [-1, 1] {
            let cases: [(DuelWeaponInput.Action, Int, Int, DuelWeaponCommand)] = [
                (.weapon, 0, -1, .weaponDown), (.weapon, 0, 1, .weaponUp),
                (.weapon, -facing, 0, .weaponBack), (.weapon, facing, 0, .weaponForward),
                (.kick, 0, -1, .kickDown), (.kick, 0, 1, .kickUp),
                (.kick, -facing, 0, .kickBack), (.kick, facing, 0, .kickForward),
                (.weapon, facing, -1, .weaponDown), (.kick, -facing, 1, .kickUp)
            ]
            for (action, x, y, expected) in cases {
                var input = DuelWeaponInput()
                input.direction(x: x, y: y)
                input.press(action)
                let result = input.consume(facing: facing, airborne: false)
                XCTAssertEqual(result.weaponCommand, expected)
                XCTAssertFalse(result.taps.contains(.jump))
                input.release(action)
                for _ in 0..<3 {
                    let subsequent = input.consume(facing: facing, airborne: false)
                    XCTAssertNil(subsequent.weaponCommand)
                    XCTAssertFalse(subsequent.taps.contains(.jump))
                }
            }
        }
    }

    func testButtonFirstChordUsesTheLiveDirectionBeforeHeavyThreshold() {
        for action in [DuelWeaponInput.Action.weapon, .kick] {
            var input = DuelWeaponInput()
            input.press(action)
            for _ in 1..<DuelWeaponInput.longPressTicks {
                XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
            }
            input.direction(x: 0, y: -1)
            XCTAssertEqual(input.consume(facing: 1, airborne: false).weaponCommand,
                           action == .weapon ? .weaponDown : .kickDown)
            input.release(action)
            XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
        }
    }

    func testChordRemainsCapturedWhenBothFingersReleaseBeforeTheNextTick() {
        var input = DuelWeaponInput()
        input.press(.weapon)
        input.direction(x: 0, y: 1)
        input.direction(x: 0, y: 0)
        input.release(.weapon)
        let result = input.consume(facing: 1, airborne: false)
        XCTAssertEqual(result.weaponCommand, .weaponUp)
        XCTAssertEqual(result.move, 0)
        XCTAssertFalse(result.taps.contains(.jump))
        XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
    }

    func testFirstResolvedCommandWinsWithoutReplayingTheOtherFinger() {
        for first in [DuelWeaponInput.Action.weapon, .kick] {
            var input = DuelWeaponInput()
            input.direction(x: 0, y: -1)
            let second: DuelWeaponInput.Action = first == .weapon ? .kick : .weapon
            input.press(first)
            input.press(second)
            XCTAssertEqual(input.consume(facing: 1, airborne: false).weaponCommand,
                           first == .weapon ? .weaponDown : .kickDown)
            input.release(second)
            input.release(first)
            for _ in 0..<30 { XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand) }
        }
    }

    func testPendingButtonsResolveInPressOrderWhenDirectionArrives() {
        var input = DuelWeaponInput()
        input.press(.kick)
        input.press(.weapon)
        input.direction(x: -1, y: 0)
        XCTAssertEqual(input.consume(facing: 1, airborne: false).weaponCommand, .kickBack)
        input.release(.weapon)
        input.release(.kick)
        XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
    }

    func testAlreadyQueuedTapCannotBeOverwrittenByMaturingHeavyHold() {
        var input = DuelWeaponInput()
        input.press(.weapon)
        for _ in 1..<DuelWeaponInput.longPressTicks { _ = input.consume(facing: 1, airborne: false) }
        input.press(.kick)
        input.release(.kick)
        XCTAssertEqual(input.consume(facing: 1, airborne: false).weaponCommand, .kick)
        for _ in 0..<30 { XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand) }
        input.release(.weapon)
        XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
    }

    func testUpAllowsOneSimulationTickForASecondFingerChord() {
        var input = DuelWeaponInput()
        input.direction(x: 0, y: 1)
        for _ in 0..<DuelWeaponInput.jumpChordGraceTicks {
            XCTAssertFalse(input.consume(facing: 1, airborne: false).taps.contains(.jump))
        }
        input.press(.kick)
        let result = input.consume(facing: 1, airborne: false)
        XCTAssertEqual(result.weaponCommand, .kickUp)
        XCTAssertFalse(result.taps.contains(.jump))
        input.release(.kick)
        for _ in 0..<30 { XCTAssertFalse(input.consume(facing: 1, airborne: false).taps.contains(.jump)) }
    }

    func testStandaloneUpIsEdgeTriggeredAndDoesNotBounceOnLanding() {
        var input = DuelWeaponInput()
        for _ in 0..<2 {
            input.direction(x: 0, y: 1)
            for _ in 0..<DuelWeaponInput.jumpChordGraceTicks {
                XCTAssertFalse(input.consume(facing: 1, airborne: false).taps.contains(.jump))
            }
            XCTAssertTrue(input.consume(facing: 1, airborne: false).taps.contains(.jump))
            for airborne in [true, false] {
                for _ in 0..<30 { XCTAssertFalse(input.consume(facing: 1, airborne: airborne).taps.contains(.jump)) }
            }
            input.direction(x: 0, y: 0)
        }
    }

    func testQuickUpReleaseSurvivesTheGracePeriodButAirborneUpCannotJumpAgain() {
        var input = DuelWeaponInput()
        input.direction(x: 0, y: 1)
        input.direction(x: 0, y: 0)
        XCTAssertFalse(input.consume(facing: 1, airborne: false).taps.contains(.jump))
        XCTAssertTrue(input.consume(facing: 1, airborne: false).taps.contains(.jump))
        input.direction(x: 0, y: 1)
        for _ in 0...DuelWeaponInput.jumpChordGraceTicks {
            XCTAssertFalse(input.consume(facing: 1, airborne: true).taps.contains(.jump))
        }
        XCTAssertFalse(input.consume(facing: 1, airborne: false).taps.contains(.jump))
    }

    func testFullCancellationClearsButtonsDirectionMailboxAndJumpBeforeLateRelease() {
        for queued in [false, true] {
            var input = DuelWeaponInput()
            input.press(.weapon)
            if queued { input.release(.weapon) }
            input.direction(x: 1, y: 1)
            input.cancelAll()
            XCTAssertEqual(input, DuelWeaponInput())
            input.release(.weapon)
            input.release(.kick)
            for _ in 0..<30 {
                let result = input.consume(facing: 1, airborne: false)
                XCTAssertNil(result.weaponCommand)
                XCTAssertEqual(result.move, 0)
                XCTAssertEqual(result.vertical, 0)
                XCTAssertFalse(result.taps.contains(.jump))
                XCTAssertTrue(result.guardHeld)
            }
        }
    }

    func testCancellingOneButtonDoesNotCompleteATapOrEraseACommittedCommand() {
        var input = DuelWeaponInput()
        input.press(.weapon)
        input.press(.kick)
        input.cancel(action: .weapon)
        input.release(.weapon)
        XCTAssertFalse(input.isPressed(.weapon))
        XCTAssertTrue(input.isPressed(.kick))
        XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
        input.release(.kick)
        input.cancel(action: .kick)
        XCTAssertEqual(input.consume(facing: 1, airborne: false).weaponCommand, .kick)
        XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
    }

    func testDirectionChangesCannotRepeatAnAlreadyResolvedHeldAttack() {
        var input = DuelWeaponInput()
        input.direction(x: -1, y: 0)
        input.press(.weapon)
        XCTAssertEqual(input.consume(facing: 1, airborne: false).weaponCommand, .weaponBack)
        input.direction(x: 1, y: 0)
        for _ in 0..<30 { XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand) }
        input.release(.weapon)
        XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
    }

    func testNeutralKickHasNoInventedHeavyMappingAndSpecialsKeepTheirIdentity() {
        var input = DuelWeaponInput()
        input.press(.kick)
        for _ in 0..<60 { XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand) }
        input.release(.kick)
        XCTAssertEqual(input.consume(facing: 1, airborne: false).weaponCommand, .kick)
        for action in [DuelWeaponInput.Action.ranged, .shadow] {
            input.press(action)
            let result = input.consume(facing: 1, airborne: false)
            XCTAssertEqual(result.weaponCommand, action == .ranged ? .ranged : .shadow)
            XCTAssertTrue(result.taps.isEmpty, "A source action must never become a laboratory skill button")
            input.release(action)
            XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
        }
    }

    func testStandingGuardRequiresNeutralGroundedInputWithNoHeldActionOrPendingTap() {
        var input = DuelWeaponInput()
        XCTAssertTrue(input.consume(facing: 1, airborne: false).guardHeld)
        XCTAssertFalse(input.consume(facing: 1, airborne: true).guardHeld)
        input.direction(x: 1, y: 0)
        XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
        input.direction(x: 0, y: 0)
        input.press(.weapon)
        XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
        input.release(.weapon)
        XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
        for _ in 0..<DuelWeaponInput.guardRecoveryTicks - 1 {
            XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld,
                           "Automatic guard must not interrupt attack recovery")
        }
        XCTAssertTrue(input.consume(facing: 1, airborne: false).guardHeld)
        input.direction(x: 0, y: 1)
        XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
        XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
    }

    func testAttackReleaseDoesNotImmediatelyRaiseAutomaticGuard() {
        var input = DuelWeaponInput()
        input.press(.weapon)
        input.release(.weapon)
        XCTAssertEqual(input.consume(facing: 1, airborne: false).weaponCommand, .weapon)
        for _ in 1..<DuelWeaponInput.guardRecoveryTicks {
            XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
        }
        XCTAssertTrue(input.consume(facing: 1, airborne: false).guardHeld)
        input.reset()
        XCTAssertTrue(input.consume(facing: 1, airborne: false).guardHeld)
    }

    func testAxesAreClampedAndAirborneNeutralActionsStayGeneric() {
        var input = DuelWeaponInput()
        input.direction(x: Int.max, y: Int.min)
        input.press(.weapon)
        let malformed = input.consume(facing: Int.min, airborne: false)
        XCTAssertEqual(malformed.move, 1)
        XCTAssertEqual(malformed.vertical, -1)
        XCTAssertEqual(malformed.weaponCommand, .weaponDown)
        input.reset()
        XCTAssertEqual(input, DuelWeaponInput())
        input.press(.kick)
        let airborne = input.consume(facing: 1, airborne: true)
        XCTAssertEqual(airborne.weaponCommand, .kick)
        XCTAssertFalse(airborne.guardHeld)
        XCTAssertFalse(airborne.taps.contains(.jump))
    }

    func testDuplicateButtonEdgesDoNotResetHoldOrRepeatRelease() {
        var input = DuelWeaponInput()
        input.action(.weapon, down: true)
        for _ in 1..<DuelWeaponInput.longPressTicks {
            input.action(.weapon, down: true)
            XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
        }
        XCTAssertEqual(input.consume(facing: 1, airborne: false).weaponCommand, .heavy)
        input.action(.weapon, down: false)
        input.action(.weapon, down: false)
        XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
    }
}
