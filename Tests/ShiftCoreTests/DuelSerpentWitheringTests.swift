import XCTest
@testable import ShiftCore

final class DuelSerpentWitheringTests: XCTestCase {
    private func active(level: Int = 4) -> DuelSerpentWitheringState {
        var value = DuelSerpentWitheringState()
        value.observeBloom(0.33, level: level)
        return value
    }

    private func advance(_ value: inout DuelSerpentWitheringState, to end: Int,
                         distance: Double = 200) {
        guard end > value.liveTick else { return }
        for tick in (value.liveTick + 1)...end {
            XCTAssertTrue(value.advance(liveTick: tick, ownerCOMX: 500, targetCOMX: 500 + distance))
        }
    }

    func testActivationUsesLevelFourAndAcceptedBloomThresholdRatherThanOtherPassives() {
        var lower = active(level: 3)
        advance(&lower, to: 120)
        XCTAssertFalse(lower.auraActive); XCTAssertEqual(lower.targetStacks, 0)
        var value = DuelSerpentWitheringState()
        value.observeBloom(0.329, level: 4)
        XCTAssertFalse(value.auraActive)
        value.observeBloom(0.33, level: 4)
        XCTAssertTrue(value.auraActive)
        value.observeBloom(0, level: 4)
        XCTAssertTrue(value.auraActive, "Source activation is a persistent variable, not a display predicate")
    }

    func testPeriodicEventsUseTheirOwnClockAndExactThreeHundredSourceUnitBoundary() {
        var value = active()
        advance(&value, to: 59, distance: 1000)
        XCTAssertEqual(value.targetStacks, 0)
        advance(&value, to: 60, distance: 299.999)
        XCTAssertEqual(value.targetStacks, 1, "Entering just before an a11 event must not restart its timer")
        advance(&value, to: 79, distance: 200)
        XCTAssertEqual(value.targetStacks, 1)
        advance(&value, to: 80, distance: -300)
        XCTAssertEqual(value.targetStacks, 0, "Exactly 300 belongs to decay, in either facing")
        advance(&value, to: 119, distance: 500)
        advance(&value, to: 120, distance: -299.999)
        XCTAssertEqual(value.targetStacks, 1)
        advance(&value, to: 140, distance: 300)
        XCTAssertEqual(value.targetStacks, 0)
    }

    func testActivationDoesNotRestartAlreadyRunningPeriodicClock() {
        var value = DuelSerpentWitheringState()
        advance(&value, to: 59)
        value.observeBloom(0.33, level: 6)
        advance(&value, to: 60)
        XCTAssertEqual(value.targetStacks, 1)
    }

    func testFortyLayerCapAffectsEveryArenaAttackKindButNeverTrueDamage() {
        var value = active()
        advance(&value, to: 2400)
        XCTAssertEqual(value.targetStacks, 40)
        advance(&value, to: 2460)
        XCTAssertEqual(value.targetStacks, 40)
        for kind in [DuelTriadRules.DamageKind.weapon, .unarmed, .shadow] {
            XCTAssertEqual(value.targetDamageFactor(kind), 0.2, accuracy: 1e-12)
        }
        XCTAssertEqual(value.targetDamageFactor(.trueDamage), 1)
        XCTAssertTrue(value.suppressesTargetCritical)
        advance(&value, to: 3260, distance: 300)
        XCTAssertEqual(value.targetStacks, 0)
        XCTAssertFalse(value.suppressesTargetCritical)
        XCTAssertEqual(value.targetDamageFactor(.weapon), 1)
    }

    func testInvalidOrRepeatedUpdatesCannotSpendAClockOrAStack() {
        var value = active()
        advance(&value, to: 59)
        let before = value
        for tick in [58, 59, 61] {
            XCTAssertFalse(value.advance(liveTick: tick, ownerCOMX: 0, targetCOMX: 0))
            XCTAssertEqual(value, before)
        }
        for invalid in [Double.nan, .infinity, -Double.infinity, 10_000_001] {
            XCTAssertFalse(value.advance(liveTick: 60, ownerCOMX: invalid, targetCOMX: 0))
            XCTAssertEqual(value, before)
        }
        advance(&value, to: 60)
        XCTAssertEqual(value.targetStacks, 1)
        let accepted = value
        XCTAssertFalse(value.advance(liveTick: 60, ownerCOMX: 0, targetCOMX: 0))
        XCTAssertEqual(value, accepted)
    }

    func testTargetReplacementClearsOnlyTargetLayersAndCanonicalBytesTrackTheState() throws {
        var value = active()
        advance(&value, to: 120)
        XCTAssertEqual(value.targetStacks, 2)
        func bytes(_ state: DuelSerpentWitheringState) throws -> Data {
            var writer = try DuelReplayStateWriter(kind: 2)
            try state.appendReplayState(to: &writer)
            return writer.data
        }
        let occupied = try bytes(value)
        value.clearTarget()
        XCTAssertEqual(value.targetStacks, 0)
        XCTAssertEqual(value.liveTick, 120); XCTAssertTrue(value.auraActive)
        XCTAssertNotEqual(try bytes(value), occupied)
        advance(&value, to: 180)
        XCTAssertEqual(value.targetStacks, 1)
        XCTAssertEqual(Set(Mirror(reflecting: value).children.compactMap(\.label)),
                       Set(["liveTick", "auraActive", "targetStacks"]))
    }
}
