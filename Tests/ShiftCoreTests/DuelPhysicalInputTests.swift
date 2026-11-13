import XCTest
@testable import ShiftCore

final class DuelPhysicalInputTests: XCTestCase {
    func testSimultaneousOppositeDirectionsNeutralize() {
        var input = DuelPhysicalInput()
        input.set(.init(x: -1, y: 1), source: "touch")
        input.set(.init(x: 1, y: -1), source: "keyboard")
        XCTAssertEqual(input.combined.x, 0)
        XCTAssertEqual(input.combined.y, 0)
        input.set(.neutral, source: "keyboard")
        XCTAssertEqual(input.combined.x, -1)
        XCTAssertEqual(input.combined.y, 1)
    }
    func testSameButtonIsOwnedUntilLastSourceReleases() {
        var input = DuelPhysicalInput()
        input.set(.init(actions: [.weapon]), source: "touch")
        input.set(.init(actions: [.weapon, .shadow]), source: "pad")
        input.set(.neutral, source: "pad")
        XCTAssertEqual(input.combined.actions, [.weapon])
        input.set(.neutral, source: "touch")
        XCTAssertEqual(input.combined, .neutral)
    }
    func testNeutralPadCannotMultiplyDirectionOrEraseKeyboard() {
        var input = DuelPhysicalInput()
        input.set(.init(x: 1, guardHeld: true), source: "keyboard")
        input.set(.init(x: 1), source: "pad1")
        input.set(.init(x: -1), source: "pad2")
        XCTAssertEqual(input.combined.x, 0)
        XCTAssertTrue(input.combined.guardHeld)
        input.reset()
        XCTAssertEqual(input.combined, .neutral)
    }
    func testDeadZoneAndNonFiniteInput() {
        XCTAssertEqual(DuelPhysicalInput.digitalAxis(.nan), 0)
        XCTAssertEqual(DuelPhysicalInput.digitalAxis(.infinity), 0)
        XCTAssertEqual(DuelPhysicalInput.digitalAxis(0.25), 0)
        XCTAssertEqual(DuelPhysicalInput.digitalAxis(-0.25), 0)
        XCTAssertEqual(DuelPhysicalInput.digitalAxis(-0.251), -1)
        XCTAssertEqual(DuelPhysicalInput.digitalAxis(0.251), 1)
    }
    func testSourceLossCancelsQueuedAttackAndJumpWithoutNewEdge() {
        var input = DuelWeaponInput()
        input.direction(x: 0, y: 1)
        input.press(.ranged)
        input.cancelPendingMotion(x: 0, y: 1)
        for _ in 0..<20 {
            let sample = input.consume(facing: 1, airborne: false)
            XCTAssertNil(sample.weaponCommand)
            XCTAssertFalse(sample.taps.contains(.jump))
        }
        input.release(.ranged)
        XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
    }
    func testSourceLossPreservesDirectionButCannotFinishAnOldHold() {
        var input = DuelWeaponInput()
        input.press(.weapon)
        input.cancelPendingMotion(x: 1, y: 0)
        XCTAssertEqual(input.consume(facing: 1, airborne: false).move, 1)
        input.release(.weapon)
        XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
        input.direction(x: 0, y: 0)
        input.press(.weapon); input.release(.weapon)
        XCTAssertEqual(input.consume(facing: 1, airborne: false).weaponCommand, .weapon)
    }
}
