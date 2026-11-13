import XCTest
@testable import ShiftCore

final class DuelManualGuardTests: XCTestCase {
    func testNeutralDoesNotAutomaticallyGuard() {
        var input = DuelWeaponInput()
        for _ in 0..<120 {
            XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
        }
    }

    func testExplicitGuardRequiresHoldAndResetsOnCancel() {
        var input = DuelWeaponInput()
        input.setGuardHeld(true)
        XCTAssertTrue(input.consume(facing: -1, airborne: false).guardHeld)
        input.setGuardHeld(false)
        XCTAssertFalse(input.consume(facing: -1, airborne: false).guardHeld)
        input.setGuardHeld(true)
        input.cancelAll()
        XCTAssertEqual(input, DuelWeaponInput())
        input.setGuardHeld(false) // A late release cannot rearm defense.
        XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
    }

    func testNoGuardWhileMovingOrAirborneAndRecoveryStillApplies() {
        var input = DuelWeaponInput()
        input.setGuardHeld(true)
        input.direction(x: 1, y: 0)
        XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
        input.direction(x: 0, y: 0)
        for _ in 1..<DuelWeaponInput.guardRecoveryTicks {
            XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
        }
        XCTAssertFalse(input.consume(facing: 1, airborne: true).guardHeld)
        XCTAssertTrue(input.consume(facing: 1, airborne: false).guardHeld)
        input.direction(x: 0, y: 1)
        XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
        XCTAssertTrue(input.consume(facing: 1, airborne: false).taps.contains(.jump))
        input.setGuardHeld(false)
        input.direction(x: 0, y: 0)
        for _ in 0..<DuelWeaponInput.guardRecoveryTicks + 1 {
            XCTAssertFalse(input.consume(facing: 1, airborne: false).guardHeld)
        }
    }

    func testManualGuardSurvivesWireEncodingAsExplicitInputOnly() throws {
        var input = DuelWeaponInput()
        var guest = DuelNetworkCombatGuest(sessionID: "manual-guard", hostID: "host", guestID: "guest")
        for (tick, held) in [false, true, false].enumerated() {
            input.setGuardHeld(held)
            let sample = input.consume(facing: -1, airborne: false)
            let encoded = try XCTUnwrap(guest.input(tick: UInt64(tick), move: sample.move,
                vertical: sample.vertical, guardHeld: sample.guardHeld,
                tapBits: sample.taps.rawValue, weaponCommand: sample.weaponCommand))
            guard case .input(let decoded)? = DuelNetworkCombatWire.decode(encoded) else {
                return XCTFail("Expected a guest input envelope")
            }
            XCTAssertEqual(decoded.guardHeld, held)
            XCTAssertNil(decoded.weaponCommand)
            XCTAssertEqual(decoded.tapBits, 0)
            XCTAssertEqual(decoded.sequence, UInt64(tick + 1))
        }
    }
}
