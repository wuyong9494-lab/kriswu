import Foundation
import XCTest
@testable import ShiftCore

final class DuelSerpentStateTests: XCTestCase {
    private func state(level: Int = 6, amplifier: Double = 1) throws -> DuelSerpentState {
        var value = try XCTUnwrap(DuelSerpentState(level: level, raidDamageAmplifier: amplifier))
        value.beginRound(); return value
    }
    func testFourStoresUseIndependentClocksAndPerksBeforeTheirOwnCoefficient() throws {
        var value = try state()
        value.outgoingContact(channel: .weapon, sourceDamage: 0.1, perks: .init(poison: 0.02, cobraDance: 0.03))
        XCTAssertEqual(value.poison(.weapon).amount, 0.15 * 0.455, accuracy: 1e-12)
        for _ in 0..<100 { _ = value.advanceStatusTick() }
        value.outgoingContact(channel: .ranged, sourceDamage: 0.1, perks: .init(poison: 100))
        XCTAssertEqual(value.poison(.ranged).amount, 0.0585, accuracy: 1e-12)
        XCTAssertEqual(value.poison(.weapon).remainingTicks, 800)
        XCTAssertEqual(value.poison(.ranged).remainingTicks, 900)
        XCTAssertEqual(value.poison(.unarmed).amount, 0)
        XCTAssertEqual(value.lastPoisonChannel, .ranged)
    }
    func testCapRefreshExpiryAndFractionalDamageDoNotDrainTheAccumulationStore() throws {
        var value = try state(amplifier: 2)
        value.outgoingContact(channel: .weapon, sourceDamage: 100)
        XCTAssertEqual(value.poison(.weapon).amount, 0.4)
        var applied = 0.0
        for _ in 0..<899 { applied += value.advanceStatusTick() }
        XCTAssertEqual(value.poison(.weapon).amount, 0.4)
        XCTAssertEqual(value.poison(.weapon).remainingTicks, 1)
        applied += value.advanceStatusTick()
        XCTAssertEqual(applied, 0.4, accuracy: 1e-12)
        XCTAssertEqual(value.poison(.weapon).amount, 0)
        XCTAssertEqual(value.advanceStatusTick(), 0)
    }
    func testHitGuardsPreventDuplicateContactsAndRecursivePoisonExplosion() throws {
        var value = try state()
        let initial = value
        XCTAssertFalse(value.outgoingContact(channel: .weapon, sourceDamage: 0.1, first: false))
        XCTAssertEqual(value, initial)
        XCTAssertTrue(value.outgoingContact(channel: .shadow, sourceDamage: 0.1, hitTag: "Hit_D13_Bloom"))
        XCTAssertEqual(value, initial)
        XCTAssertTrue(value.outgoingContact(channel: .weapon, sourceDamage: 0.1, first: false, invisible: true))
        XCTAssertGreaterThan(value.poison(.weapon).amount, 0)
        XCTAssertTrue(value.outgoingContact(channel: .unarmed, sourceDamage: 0.1, event: .otherSourceEvent, first: false))
    }
    func testBloomUsesDifferentIncomingAndOutgoingSourceDomains() throws {
        var value = try state(amplifier: 2)
        value.outgoingContact(channel: .weapon, sourceDamage: 1)
        XCTAssertEqual(value.bloom, 0.225, accuracy: 1e-12)
        XCTAssertEqual(value.bloomTier, .empty)
        value.incomingContact(sourceDamage: 1)
        XCTAssertEqual(value.bloom, 0.675, accuracy: 1e-12)
        XCTAssertEqual(value.bloomTier, .barkskin)
        value.incomingContact(sourceDamage: 1)
        XCTAssertEqual(value.bloom, 1); XCTAssertEqual(value.bloomTier, .full)
    }
    func testBarkskinUsesOldSourceLayerCountAndDoesNotPostponeItsRecharge() throws {
        var value = try state()
        for _ in 0..<5 { value.outgoingContact(channel: .weapon, sourceDamage: 0.2) }
        XCTAssertEqual(value.barkskinStacks, 0)
        value.outgoingContact(channel: .weapon, sourceDamage: 0.2)
        XCTAssertEqual(value.barkskinStacks, 6)
        XCTAssertEqual(value.prepareIncomingContact(blocked: true), 1)
        XCTAssertEqual(value.barkskinStacks, 6)
        XCTAssertEqual(value.barkskinRechargeRemaining, 0)
        XCTAssertEqual(value.prepareIncomingContact(blocked: false), 2.98, accuracy: 1e-12)
        XCTAssertEqual(value.barkskinStacks, 5)
        XCTAssertEqual(value.barkskinRechargeRemaining, 300)
        for _ in 0..<100 { _ = value.advanceStatusTick() }
        XCTAssertEqual(value.prepareIncomingContact(blocked: false), 2.65, accuracy: 1e-12)
        XCTAssertEqual(value.barkskinStacks, 4)
        XCTAssertEqual(value.barkskinRechargeRemaining, 200)
        value.incomingContact(sourceDamage: 0.1)
        XCTAssertEqual(value.barkskinStacks, 4, "A later Bloom check cannot refill the shield")
        for _ in 0..<199 { _ = value.advanceStatusTick() }
        XCTAssertEqual(value.barkskinStacks, 4)
        _ = value.advanceStatusTick()
        XCTAssertEqual(value.barkskinStacks, 5)
        XCTAssertEqual(value.barkskinRechargeRemaining, 300)
        for _ in 0..<300 { _ = value.advanceStatusTick() }
        XCTAssertEqual(value.barkskinStacks, 6)
        XCTAssertEqual(value.barkskinRechargeRemaining, 0)
    }
    func testLifeDrainUsesThirtyTickSourceSegmentsWithoutDrainingPoison() throws {
        var value = try state()
        for _ in 0..<8 { value.outgoingContact(channel: .weapon, sourceDamage: 0.2) }
        XCTAssertFalse(value.lifeDrainActive)
        value.outgoingContact(channel: .weapon, sourceDamage: 0.2)
        XCTAssertTrue(value.lifeDrainActive)
        let poison = value.poison(.weapon).amount
        for _ in 0..<30 {
            _ = value.advanceStatusTick()
            XCTAssertEqual(value.healingThisTick, 0)
        }
        let sourceRate = (0.01 + poison / 900 * 0.01) / 30
        _ = value.advanceStatusTick()
        XCTAssertEqual(value.healingThisTick, sourceRate, accuracy: 1e-15)
        XCTAssertEqual(value.poison(.weapon).amount, poison)
        value.clearPoisonStores()
        for _ in 0..<29 {
            _ = value.advanceStatusTick()
            XCTAssertEqual(value.healingThisTick, sourceRate, accuracy: 1e-15,
                           "A running source status keeps the rate captured at creation")
        }
        _ = value.advanceStatusTick()
        XCTAssertEqual(value.healingThisTick, 0.01 / 30, accuracy: 1e-15)
    }
    func testBloomPassivesFreezeWithRoundAndResetWithMatch() throws {
        var value = try state()
        for _ in 0..<9 { value.outgoingContact(channel: .weapon, sourceDamage: 0.2) }
        _ = value.prepareIncomingContact(blocked: false)
        for _ in 0..<31 { _ = value.advanceStatusTick() }
        XCTAssertGreaterThan(value.healingThisTick, 0)
        value.endRound()
        XCTAssertEqual(value.healingThisTick, 0)
        let ended = value
        for _ in 0..<50 { XCTAssertEqual(value.advanceStatusTick(), 0) }
        XCTAssertEqual(value.prepareIncomingContact(blocked: false), 1)
        XCTAssertEqual(value, ended)
        value.beginRound()
        XCTAssertEqual(value.barkskinStacks, ended.barkskinStacks)
        XCTAssertEqual(value.barkskinRechargeRemaining, ended.barkskinRechargeRemaining)
        _ = value.advanceStatusTick()
        XCTAssertEqual(value.barkskinRechargeRemaining, ended.barkskinRechargeRemaining - 1)
        XCTAssertGreaterThan(value.healingThisTick, 0)
        value.resetMatch(); value.beginRound()
        XCTAssertEqual(value.bloom, 0); XCTAssertEqual(value.barkskinStacks, 0)
        XCTAssertEqual(value.barkskinRechargeRemaining, 0)
        XCTAssertFalse(value.lifeDrainActive); XCTAssertEqual(value.healingThisTick, 0)
    }
    func testFinalHitScaleUsesOriginalFirstInvisibleAndPositiveDamageGuards() throws {
        var value = try state()
        let unchanged = value
        XCTAssertEqual(value.outgoingHitDamage(0.025), 0.0165, accuracy: 1e-15)
        XCTAssertEqual(value.outgoingHitDamage(0.025, first: false), 0.025)
        XCTAssertEqual(value.outgoingHitDamage(0.025, first: false, invisible: true), 0.0165, accuracy: 1e-15)
        XCTAssertEqual(value.outgoingHitDamage(0.025, event: .otherSourceEvent, first: false),
                       0.0165, accuracy: 1e-15)
        XCTAssertEqual(value.outgoingHitDamage(0), 0)
        XCTAssertEqual(value.outgoingHitDamage(-0.1), -0.1)
        XCTAssertEqual(value, unchanged, "A Hit replacement does not advance or mutate passive state")
        value.endRound()
        XCTAssertEqual(value.outgoingHitDamage(0.025), 0.025)
    }
    func testCloudAndExplosionUseExplicitSourceEventsWithoutConsumingOrGrantingAllChannels() throws {
        var value = try state()
        XCTAssertFalse(value.poisonBombCloudPulse(.ranged, targetInvincible: true))
        XCTAssertTrue(value.poisonBombCloudPulse(.ranged, targetInvincible: false))
        XCTAssertEqual(value.poison(.ranged).amount, 0.02)
        XCTAssertEqual(value.poison(.weapon).amount, 0)
        XCTAssertEqual(value.poisonExplosionDamage(targetInvincible: false), 0.09, accuracy: 1e-12)
        XCTAssertEqual(value.poisonExplosionDamage(targetInvincible: true), 0)
        XCTAssertEqual(value.poison(.ranged).amount, 0.02)
        value.clearPoisonStores()
        XCTAssertEqual(value.poisonExplosionDamage(targetInvincible: false), 0)
    }
    func testBottleConsumesAtAnimationStartAndReleasesOnceWithNoInterruptRefund() throws {
        var value = try state()
        XCTAssertFalse(value.acceptBottleReleaseMarker())
        XCTAssertFalse(value.acceptBottleAnimationStart(rangedUsagesLeft: 0))
        XCTAssertFalse(value.bottleUsed)
        XCTAssertTrue(value.acceptBottleAnimationStart(rangedUsagesLeft: 1))
        XCTAssertFalse(value.acceptBottleAnimationStart(rangedUsagesLeft: 1))
        value.interruptBottle()
        XCTAssertFalse(value.acceptBottleReleaseMarker())
        XCTAssertTrue(value.bottleUsed)
        value.resetMatch(); value.beginRound()
        XCTAssertTrue(value.acceptBottleAnimationStart(rangedUsagesLeft: 1))
        XCTAssertTrue(value.acceptBottleReleaseMarker())
        XCTAssertFalse(value.acceptBottleReleaseMarker())
    }
    func testLevelBoundariesAndInactiveOrInvalidEventsAreAtomic() throws {
        XCTAssertNil(DuelSerpentState(level: 7, raidDamageAmplifier: 1))
        for number in [Double.nan, .infinity, 0, -1] {
            XCTAssertNil(DuelSerpentState(level: 6, raidDamageAmplifier: number))
        }
        var value = try state(level: 2)
        XCTAssertEqual(value.coefficient(.weapon), 0.35)
        XCTAssertEqual(value.poisonAbilityCooldownTicks, 960)
        XCTAssertEqual(value.explosionMultiplier, 2.75)
        XCTAssertFalse(value.acceptBottleAnimationStart(rangedUsagesLeft: 1))
        let original = value
        for number in [Double.nan, .infinity, 0, -1] {
            XCTAssertFalse(value.outgoingContact(channel: .weapon, sourceDamage: number))
            XCTAssertEqual(value, original)
        }
        value.outgoingContact(channel: .weapon, sourceDamage: 0.1)
        value.endRound(); let ended = value
        XCTAssertEqual(value.advanceStatusTick(), 0)
        XCTAssertFalse(value.incomingContact(sourceDamage: 1))
        XCTAssertEqual(value, ended)
        value.resetMatch()
        XCTAssertFalse(value.roundActive); XCTAssertEqual(value.bloom, 0)
        XCTAssertNil(value.lastPoisonChannel)
    }
}
