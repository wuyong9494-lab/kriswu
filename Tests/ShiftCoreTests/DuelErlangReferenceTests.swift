import XCTest
@testable import ShiftCore

final class DuelErlangReferenceTests: XCTestCase {
    func testGlobalTierDoesNotGuessDomesticCeiling() {
        XCTAssertEqual(DuelErlangReference.confirmedMaximumLevel(on: .globalTowerTrial202604), 8)
        XCTAssertNil(DuelErlangReference.confirmedMaximumLevel(on: .domesticFracture30))
    }

    func testAvatarRuleProtectsOnlyVerifiedInterruptions() {
        XCTAssertEqual(DuelErlangReference.preventsInterruption(track: .globalTowerTrial202604, tier: 6, phase: .ascended, cause: .shadowMove), true)
        XCTAssertEqual(DuelErlangReference.preventsInterruption(track: .globalTowerTrial202604, tier: 6, phase: .ascended, cause: .specialSetAbility), true)
        XCTAssertNil(DuelErlangReference.preventsInterruption(track: .globalTowerTrial202604, tier: 8, phase: .ascended, cause: .shadowMove))
        XCTAssertNil(DuelErlangReference.preventsInterruption(track: .globalTowerTrial202604, tier: 8, phase: .ascended, cause: .ordinary))
        XCTAssertNil(DuelErlangReference.preventsInterruption(track: .globalTowerTrial202604, tier: 8, phase: .base, cause: .shadowMove))
        XCTAssertNil(DuelErlangReference.preventsInterruption(track: .globalTowerTrial202604, tier: 5, phase: .ascended, cause: .shadowMove))
        XCTAssertNil(DuelErlangReference.preventsInterruption(track: .globalTowerTrial202604, tier: 9, phase: .ascended, cause: .shadowMove))
        XCTAssertNil(DuelErlangReference.preventsInterruption(track: .domesticFracture30, tier: 8, phase: .ascended, cause: .shadowMove))
    }
}
