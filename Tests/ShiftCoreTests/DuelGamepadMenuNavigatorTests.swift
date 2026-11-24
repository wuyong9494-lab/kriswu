import XCTest
@testable import ShiftCore

final class DuelGamepadMenuNavigatorTests: XCTestCase {
    func testHeldInputMustReturnToNeutralBeforeArming() {
        var detector = DuelGamepadMenuEdgeDetector()
        // Entering a menu while A is still held from combat must NOT fire confirm.
        XCTAssertEqual(detector.update(.init(confirm: true)), [])
        XCTAssertEqual(detector.update(.init(x: 1, confirm: true)), [])
        // Release to neutral arms the detector.
        XCTAssertEqual(detector.update(.neutral), [])
        // Subsequent press emits exactly once.
        XCTAssertEqual(detector.update(.init(confirm: true)), [.confirm])
        XCTAssertEqual(detector.update(.init(confirm: true)), [])
        // Release and press again fires again.
        XCTAssertEqual(detector.update(.neutral), [])
        XCTAssertEqual(detector.update(.init(cancel: true, menu: true)), [.cancel, .menu])
    }

    func testDirectionalAndShoulderEdgesFireCleanly() {
        var detector = DuelGamepadMenuEdgeDetector()
        _ = detector.update(.neutral)
        XCTAssertEqual(detector.update(.init(y: 1)), [.up])
        XCTAssertEqual(detector.update(.init(y: 1)), [])
        XCTAssertEqual(detector.update(.init(y: -1)), [.down])
        XCTAssertEqual(detector.update(.init(x: -1)), [.left])
        XCTAssertEqual(detector.update(.init(x: 1)), [.right])
        XCTAssertEqual(detector.update(.init(shoulderLeft: true)), [.shoulderLeft])
        XCTAssertEqual(detector.update(.init(shoulderRight: true)), [.shoulderRight])
        XCTAssertEqual(detector.update(.init(secondary: true, tertiary: true)), [.secondary, .tertiary])
    }

    func testWrapAroundHeroAndDifficultyStepping() {
        let heroes = DuelGame.Hero.allCases
        XCTAssertEqual(DuelGamepadListNavigation.step(in: heroes, current: heroes.first!, delta: -1), heroes.last!)
        XCTAssertEqual(DuelGamepadListNavigation.step(in: heroes, current: heroes.last!, delta: 1), heroes.first!)
        XCTAssertEqual(DuelGamepadListNavigation.step(in: heroes, current: heroes[1], delta: 1), heroes[2])
        XCTAssertNil(DuelGamepadListNavigation.step(in: [DuelGame.Hero](), current: .wuYong, delta: 1))
    }
}
