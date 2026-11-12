import XCTest
@testable import ShiftCore

final class DuelManualGuardTests: XCTestCase {
    func testNeutralDoesNotAutomaticallyGuard() {
        var input = DuelWeaponInput()
        for _ in 0..<20 {
            XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
        }
    }

    func testExplicitGuardRequiresHoldAndResetsOnCancel() {
        var input = DuelWeaponInput()
        input.setGuardHeld(true)
        XCTAssertTrue(input.consume(facing: 1, airborne: false).guardHeld)
        input.setGuardHeld(false)
        XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
        input.setGuardHeld(true)
        input.cancelAll()
        XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
    }

    func testNoGuardWhileMovingOrAirborne() {
        var input = DuelWeaponInput()
        input.setGuardHeld(true)
        input.direction(x: 1, y: 0)
        XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
        input.direction(x: 0, y: 0)
        XCTAssertFalse(input.consume(facing: 1, airborne: true).guardHeld)
    }
}
