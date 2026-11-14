import Foundation
import XCTest
@testable import ShiftCore

/// Source ratios and event ticks use the user IPA's packaged D19 configuration.
/// The 1,000 HP/attack scales and collision dimensions below are explicit test
/// adaptations, not a retail character build or original asset fixture.
final class DuelPanguRuntimeTests: XCTestCase {
    private typealias S = DuelPanguState
    private typealias R = DuelPanguRules

    private func rules(_ level: Int = 6, maximumHealth: Int = 1000) throws -> R {
        try .d19HeavenlyKing(level: level, maximumHealth: maximumHealth,
            weaponPower: 1000, unarmedPower: 1000, magicPower: 1000, rangedPower: 1000,
            spatialTemplate: DuelPanguTestFixture.rules())
    }
    private func state(_ rules: R, seed: UInt64 = 17) throws -> S {
        try XCTUnwrap(S(rules: rules, seed: seed))
    }
    private func attacks(_ effects: [S.Effect]) -> [S.Attack] {
        effects.compactMap { if case .attack(let value) = $0 { return value }; return nil }
    }
    private func controls(_ effects: [S.Effect]) -> [S.Control] {
        effects.compactMap { if case .control(let value) = $0 { return value }; return nil }
    }
    @discardableResult private func advance(_ state: inout S, _ ticks: Int) -> [S.Effect] {
        var result: [S.Effect] = []
        for _ in 0..<ticks { result += state.step() }
        return result
    }
    private func fillCombo(_ state: inout S, count: Int, startID: UInt64 = 1) {
        for offset in 0..<count {
            state.contact(blocked: false, generated: false, hitID: startID + UInt64(offset))
        }
    }
    private func bytes(_ state: S) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 2)
        try state.appendReplayState(to: &writer)
        return writer.data
    }

    func testProductionLevelsKeepSourceRatiosAndExplicitApplicationNormalizations() throws {
        for level in 1...6 {
            let value = try rules(level)
            try value.validate()
            XCTAssertEqual(value.basis, .applicationAdaptation)
            XCTAssertEqual(value.runtime?.tickRate, 60)
            XCTAssertEqual(value.runtime?.sourceFramesPerSecond, 30)
            XCTAssertEqual(value.runtime?.normalizedMagicPower, 1000)
            XCTAssertEqual(value.light.maximum, 10_000)
            XCTAssertEqual(value.light.initial, 0)
            XCTAssertEqual(value.light.regularHitGain, level >= 5 ? 750 : level >= 3 ? 500 : 300)
            XCTAssertEqual(value.light.primordialHitGain, level >= 6 ? 3500 : level >= 5 ? 2500 : 1500)
            XCTAssertEqual(value.ability(.shard)?.cooldownTicks, level >= 6 ? 480 : level >= 4 ? 540 : 600)
            XCTAssertEqual(value.ability(.heavenfall)?.cooldownTicks, 1200)
            XCTAssertEqual(value.typhoon.fixedCooldownTicks, 600)
            XCTAssertEqual(value.combo.holdTicks, 255)
            XCTAssertEqual(value.combo.level6HoldTicks, 435)
            XCTAssertEqual(value.combo.heavyWindThreshold, 16)
            XCTAssertEqual(value.combo.allAttackWindThreshold, 31)
            XCTAssertEqual(value.combo.level4SpeedThreshold, 56)
            XCTAssertEqual(value.combo.rangedThreshold, 76)
            XCTAssertEqual(value.combo.zeroCooldownThreshold, 101)
            XCTAssertEqual(value.runtime?.spearEmpowerThreshold, 75)
            XCTAssertEqual(value.runtime?.heavenfallCooldownThreshold, 100)
            XCTAssertEqual(value.runtime?.heavenfallLightGain, level >= 6 ? 5000 : 2500)
            XCTAssertEqual(value.earth.dreadDamageTakenBonusBps, 0,
                           "An unresolved target-local variable is not replaced by the caster's panel value")
            XCTAssertTrue(value.abilities.allSatisfy { $0.lightCost == 0 && !$0.damageImmune })
            XCTAssertEqual(try JSONDecoder().decode(R.self, from: JSONEncoder().encode(value)), value)
        }
    }

    func testSourceProfileRejectsWrongVersionClockHashAndInvalidExplicitScales() throws {
        for level in [0, 7, 8] { XCTAssertThrowsError(try rules(level)) }
        XCTAssertThrowsError(try rules(maximumHealth: 0))
        var version = try rules(); version.runtime?.version = "unverified-later-patch"
        XCTAssertThrowsError(try version.validate())
        var clock = try rules(); clock.runtime?.tickRate = 30
        XCTAssertThrowsError(try clock.validate())
        var hash = try rules(); hash.runtime?.configurationSHA256 = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try hash.validate())
        var stat = try rules(); stat.runtime?.normalizedWeaponPower = -1
        XCTAssertThrowsError(try stat.validate())
    }

    func testPreHitIncludesCurrentContactInDamageAndPostHitDoesNotCountItTwice() throws {
        var value = try state(rules(1))
        XCTAssertTrue(value.prepareOrdinaryContact(blocked: false, kind: .weapon, hitID: 1))
        XCTAssertEqual(value.combo, 1)
        XCTAssertEqual(value.outgoingDamage(100, kind: .weapon), 101)
        XCTAssertEqual(value.light, 0, "Light is a PostHit effect")
        value.contact(blocked: false, generated: false, hitID: 1)
        XCTAssertEqual(value.combo, 1); XCTAssertEqual(value.light, 300)
        let snapshot = value
        XCTAssertFalse(value.prepareOrdinaryContact(blocked: false, kind: .weapon, hitID: 1))
        value.contact(blocked: false, generated: false, hitID: 1)
        XCTAssertEqual(value, snapshot)
    }

    func testComboDamageCapsAtSourceFactor125NotAt125PercentOrCombo125() throws {
        var value = try state(rules(1))
        fillCombo(&value, count: 12_500)
        XCTAssertEqual(value.combo, 12_500)
        XCTAssertEqual(value.outgoingDamage(100, kind: .weapon), 12_500)
    }

    func testDamageHitFactorMultipliesTyphoonBeforeComboAndBlockedHitOmitsTyphoon() throws {
        var value = try state(rules(4))
        fillCombo(&value, count: 10)
        value.start(.typhoon); advance(&value, 42)
        XCTAssertEqual(value.outgoingDamage(100, kind: .weapon), 165)
        XCTAssertEqual(value.outgoingDamage(100, kind: .weapon, blocked: true), 110)
    }

    func testSourceComboExpiresAtExactFullDynastyHoldAndL6ReceivedHitDoesNotRefreshIt() throws {
        for (level, hold) in [(5, 255), (6, 435)] {
            var value = try state(rules(level))
            fillCombo(&value, count: 1)
            XCTAssertEqual(value.comboRemainingTicks, hold)
            advance(&value, 1)
            if level == 6 {
                value.receiveDamage(0, kind: .weapon, blocked: true)
                XCTAssertEqual(value.combo, 1)
                XCTAssertEqual(value.comboRemainingTicks, hold - 1)
            }
            advance(&value, hold - 2); XCTAssertEqual(value.combo, 1)
            value.step(); XCTAssertEqual(value.combo, 0)
        }
    }

    func testOrdinaryPreHitResetsLowerLevelComboEvenAtZeroDamageButStatusDoesNot() throws {
        var value = try state(rules(5))
        fillCombo(&value, count: 1)
        XCTAssertFalse(value.receiveStatusDamage(10).comboReset)
        XCTAssertEqual(value.combo, 1)
        XCTAssertTrue(value.receiveDamage(0, kind: .weapon, blocked: true).comboReset)
        XCTAssertEqual(value.combo, 0)
    }

    func testLightUsesExactHitTagsIncludingSpearAdditiveGainAndWindExclusion() throws {
        for level in [2, 3, 5, 6] {
            let r = try rules(level)
            var ordinary = try state(r), primordial = try state(r), spear = try state(r)
            var wind = try state(r), normalSpear = try state(r), kick = try state(r)
            ordinary.contact(blocked: false, generated: false, hitID: 1)
            primordial.contact(blocked: false, generated: true, hitID: 1, sourceStrike: .shardThrown)
            spear.contact(blocked: false, generated: true, hitID: 1, sourceStrike: .spearFlight)
            wind.contact(blocked: false, generated: true, hitID: 1, sourceStrike: .windBlade)
            normalSpear.contact(blocked: false, generated: true, hitID: 1, sourceStrike: .normalSpear)
            kick.contact(blocked: false, generated: false, hitID: 1, sourceStrike: .shardKick)
            XCTAssertEqual(ordinary.light, r.light.regularHitGain)
            XCTAssertEqual(primordial.light, r.light.primordialHitGain)
            XCTAssertEqual(spear.light, 1000 + r.light.regularHitGain)
            XCTAssertEqual(wind.light, 0); XCTAssertEqual(normalSpear.light, 0)
            XCTAssertEqual(kick.light, r.light.regularHitGain)
            XCTAssertEqual(wind.combo, 1, "The Light exclusion is not a combo exclusion")
        }
    }

    func testLevel5BlockedOrdinaryHitRestoresLightWithoutAddingCombo() throws {
        for level in [4, 5] {
            var value = try state(rules(level))
            value.contact(blocked: true, generated: false, hitID: 1)
            XCTAssertEqual(value.combo, 0)
            XCTAssertEqual(value.light, level == 5 ? 750 : 0)
        }
    }

    func testNormalizedLightSpendsHpEquivalentAndRetainsFractionalPool() throws {
        var r = try rules(1, maximumHealth: 997); r.light.initial = 100
        var value = try state(r)
        for _ in 0..<9 { XCTAssertEqual(value.receiveDamage(1, kind: .weapon).healthDamage, 0) }
        XCTAssertEqual(value.light, 9)
        let last = value.receiveDamage(1, kind: .weapon)
        XCTAssertEqual(last.healthDamage, 1, "9.97 application HP of Light cannot erase ten HP")
        XCTAssertEqual(value.light, 0)
    }

    func testTyphoonReducesWholeIncomingDamageBeforeLightOverflowAndRequiresPositivePool() throws {
        var r = try rules(4); r.light.initial = 2000
        var value = try state(r)
        value.start(.typhoon); advance(&value, 42)
        let receipt = value.receiveDamage(600, kind: .weapon)
        XCTAssertEqual(receipt.adjustedDamage, 300)
        XCTAssertEqual(receipt.absorbedDamage, 200)
        XCTAssertEqual(receipt.healthDamage, 100)
        XCTAssertEqual(value.light, 0)
        XCTAssertEqual(value.receiveDamage(600, kind: .weapon).healthDamage, 600,
                       "Typhoon's Light reduction is not an empty-shield defense buff")
    }

    func testTranceAddsHalfDefenseUsingDivisionAndStatusBypassesDefense() throws {
        var value = try state(rules())
        value.start(.heavenfall); advance(&value, 248)
        XCTAssertEqual(value.tranceRemainingTicks, 900)
        value.receiveStatusDamage(1000) // Consume the half-HP Light grant.
        let hit = value.receiveDamage(1200, kind: .weapon)
        XCTAssertEqual(hit.adjustedDamage, 800)
        XCTAssertEqual(hit.healthDamage, 800)
        XCTAssertEqual(value.receiveStatusDamage(1200).healthDamage, 1200)
        XCTAssertTrue(value.impactImmune)
        XCTAssertFalse(value.damageImmune, "The ultimate prevents hit reaction, not HP loss")
    }

    func testHeavenfallSourceMarkersSeparateFreezeOneTimeLightAxeAndExplosion() throws {
        var r = try rules(); r.trance.extraComboChancePerMillion = 0
        var value = try state(r)
        XCTAssertTrue(controls(value.start(.heavenfall)).isEmpty)
        XCTAssertTrue(controls(advance(&value, 23)).isEmpty)
        let freeze = try XCTUnwrap(controls(value.step()).first)
        XCTAssertEqual(freeze.kind, .petrify); XCTAssertEqual(freeze.durationTicks, 226)
        advance(&value, 115); XCTAssertEqual(value.light, 0)
        value.step(); XCTAssertEqual(value.light, 5000)
        advance(&value, 101); XCTAssertEqual(value.light, 5000)
        let axe = try XCTUnwrap(attacks(value.step()).first)
        XCTAssertEqual(axe.sourceStrike, .heavenfallAxe)
        XCTAssertEqual(axe.sourceBaseDamage, 700)
        XCTAssertEqual(axe.sourceLifetimeTicks, 8)
        XCTAssertEqual(value.combo, 0, "Release without contact grants no combo")
        advance(&value, 5)
        let explosion = try XCTUnwrap(attacks(value.step()).first)
        XCTAssertEqual(explosion.sourceStrike, .heavenfallExplosion)
        XCTAssertTrue(explosion.anchorAtOpponent)
        XCTAssertEqual(value.tranceRemainingTicks, 900)
        XCTAssertEqual(value.prepareContact(attack: explosion, blocked: false, hitID: 1), 1890)
        XCTAssertEqual(value.combo, 26, "PreHit adds the actual hit plus the L6 ground bonus before damage")
        value.contact(attack: explosion, blocked: false, hitID: 1)
        XCTAssertEqual(value.combo, 26)
        value.step()
        XCTAssertEqual(controls(value.step()).first?.durationTicks, 0)
    }

    func testLevel2HeavenfallOneTimeLightGrantIsTwentyFivePercent() throws {
        var value = try state(rules(2))
        value.start(.heavenfall); advance(&value, 139)
        XCTAssertEqual(value.light, 0)
        value.step(); XCTAssertEqual(value.light, 2500)
        advance(&value, 180); XCTAssertEqual(value.light, 2500)
        XCTAssertEqual(value.tranceRemainingTicks, 0)
    }

    func testTyphoonCooldownStartsBeforeBuffAndGateQuotaFollowsCooldownCycle() throws {
        var value = try state(rules(4))
        value.start(.typhoon)
        XCTAssertEqual(value.light, 0)
        XCTAssertEqual(value.cooldownRemaining(.typhoon), 600)
        advance(&value, 41); XCTAssertEqual(value.typhoonRemainingTicks, 0)
        value.step(); XCTAssertEqual(value.typhoonRemainingTicks, 600)
        advance(&value, 38); XCTAssertTrue(value.canUse(.stormGate))
        value.start(.stormGate); advance(&value, 62)
        XCTAssertFalse(value.canUse(.stormGate)); XCTAssertEqual(value.stormGateUses, 1)
        advance(&value, 458)
        XCTAssertEqual(value.cooldownRemaining(.typhoon), 0)
        XCTAssertEqual(value.typhoonRemainingTicks, 42)
        XCTAssertTrue(value.canUse(.typhoon), "The original cooldown and buff start at different events")
    }

    func testStrictWindThresholdAndRefreshableSingleTimerQueue() throws {
        var value = try state(rules(2))
        fillCombo(&value, count: 15)
        XCTAssertTrue(attacks(advance(&value, 10)).isEmpty)
        value.contact(blocked: false, generated: false, hitID: 16, heavy: true)
        XCTAssertTrue(attacks(advance(&value, 5)).isEmpty)
        value.contact(blocked: false, generated: false, hitID: 17, heavy: true)
        XCTAssertTrue(attacks(advance(&value, 9)).isEmpty)
        let first = try XCTUnwrap(attacks(value.step()).first)
        XCTAssertEqual(first.sourceStrike, .windBlade)
        XCTAssertTrue(first.anchorAtOpponent)
        XCTAssertEqual(first.sourceBaseDamage, 250)
        XCTAssertTrue(attacks(advance(&value, 9)).isEmpty)
        XCTAssertEqual(attacks(value.step()).map(\.sourceStrike), [.windBlade])
        XCTAssertTrue(attacks(advance(&value, 10)).isEmpty)
    }

    func testTyphoonAndThresholdWindContributionsStackAndGeneratedWindDoesNotLoop() throws {
        var value = try state(rules(3))
        value.start(.typhoon); advance(&value, 80)
        // Ordinary unarmed contacts build combo without the Typhoon weapon counter.
        for id in UInt64(1)...30 { value.contact(blocked: false, generated: false, hitID: id, kind: .shadow) }
        value.contact(blocked: false, generated: false, hitID: 31, kind: .weapon)
        let first = try XCTUnwrap(attacks(advance(&value, 10)).first)
        let light = value.light
        value.contact(attack: first, blocked: false, hitID: 32)
        XCTAssertEqual(value.light, light)
        XCTAssertEqual(attacks(advance(&value, 10)).count, 1)
        XCTAssertTrue(attacks(advance(&value, 40)).isEmpty)
    }

    func testSplitterFollowUpsUsePassiveAnimationMarkersAndRequireActualReaction() throws {
        for reactable in [false, true] {
            var value = try state(rules(4))
            value.start(.splitter)
            let attack = try XCTUnwrap(attacks(advance(&value, 38)).first)
            XCTAssertEqual(attack.sourceBaseDamage, 550)
            XCTAssertEqual(attack.sourceLifetimeTicks, 8)
            value.prepareContact(attack: attack, blocked: false, hitID: 1)
            value.contact(attack: attack, blocked: false, hitID: 1, reactable: reactable)
            var emitted: [(Int, R.SourceStrike)] = []
            var debuffs: [S.Control] = []
            for tick in 1...78 {
                let effects = value.step()
                emitted += attacks(effects).compactMap { attack in attack.sourceStrike.map { (tick, $0) } }
                debuffs += controls(effects)
            }
            XCTAssertEqual(emitted.map { $0.0 }, reactable ? [8, 18, 28, 58, 68, 78] : [])
            XCTAssertEqual(emitted.map { $0.1 }, reactable ? [.upperWind, .upperWind, .upperWind, .upperWind, .upperWind, .upperFall] : [])
            XCTAssertEqual(debuffs.first?.durationTicks, reactable ? 600 : nil)
            XCTAssertEqual(debuffs.first?.damageTakenBonusBps, reactable ? 0 : nil)
        }
    }

    func testShardUsesSeparateLiftThrownAndKickPacketsWithContactTimeEarthBonus() throws {
        var value = try state(rules(4))
        value.start(.bones); advance(&value, 94)
        let lift = try XCTUnwrap(attacks(value.start(.shard)).first)
        XCTAssertEqual(lift.sourceStrike, .shardLift)
        XCTAssertEqual(lift.sourceBaseDamage, 250, "Bones selects the large rock at model creation")
        let released = attacks(advance(&value, 56))
        XCTAssertEqual(released.map(\.sourceStrike), [.shardThrown, .shardKick])
        let thrown = released[0]
        XCTAssertEqual(thrown.sourceBaseDamage, 750)
        XCTAssertEqual(value.prepareContact(attack: thrown, blocked: false, hitID: 1), 1278,
                       "750 × 1.01 × 1.25 × 1.35 is rounded only after all source factors")
        let stun = controls(value.contact(attack: thrown, blocked: false, hitID: 1)).first
        XCTAssertEqual(stun?.durationTicks, 150)
        XCTAssertEqual(released[1].sourceBaseDamage, 250)
        XCTAssertEqual(released[1].damageKind, .unarmed)
    }

    func testSpearInitialReactionCancelsFlightButUnreactableContactDoesNot() throws {
        for reactable in [false, true] {
            var value = try state(rules(5))
            fillCombo(&value, count: 75)
            value.cancelPendingDerivedAttacks()
            value.start(.spear)
            XCTAssertEqual(value.activeCast?.empowered, true)
            let initial = try XCTUnwrap(attacks(advance(&value, 46)).first)
            XCTAssertEqual(initial.sourceStrike, .spearInitial)
            XCTAssertEqual(initial.sourceLifetimeTicks, 4)
            let effects = value.contact(attack: initial, blocked: false, hitID: 76, reactable: reactable)
            XCTAssertEqual(controls(effects).first?.durationTicks, reactable ? 186 : nil)
            XCTAssertEqual(attacks(advance(&value, 4)).map(\.sourceStrike), reactable ? [] : [.spearFlight])
        }
    }

    func testSpearModelSurvivesOwnerInterruptionOnlyAfterCreationMarker() throws {
        for tick in [7, 8] {
            var value = try state(rules(1))
            value.start(.spear); advance(&value, tick)
            value.interrupt()
            let released = attacks(advance(&value, 46 - tick))
            XCTAssertEqual(released.map(\.sourceStrike), tick == 8 ? [.normalSpear] : [])
        }
    }

    func testSpearRhythmIsNotConsumedByCastingAndNormalSpearHasNoLightGain() throws {
        var value = try state(rules(2))
        value.start(.typhoon); advance(&value, 80)
        XCTAssertEqual(value.rhythmRemainingTicks, 300)
        value.start(.spear)
        XCTAssertEqual(value.rhythmRemainingTicks, 300)
        XCTAssertEqual(value.activeCast?.empowered, true)
        var normal = try state(rules(1))
        normal.start(.spear)
        let projectile = try XCTUnwrap(attacks(advance(&normal, 46)).first)
        XCTAssertEqual(projectile.sourceStrike, .normalSpear)
        XCTAssertEqual(projectile.sourceBaseDamage, 200)
        normal.contact(attack: projectile, blocked: false, hitID: 1)
        XCTAssertEqual(normal.light, 0)
    }

    func testSeparateSpearAndUltimateInclusiveThresholdsAndZeroCooldownStrictThreshold() throws {
        for combo in [99, 100, 101] {
            var value = try state(rules())
            fillCombo(&value, count: combo)
            value.start(.heavenfall)
            XCTAssertEqual(value.cooldownRemaining(.heavenfall), combo >= 100 ? 600 : 1200)
        }
        var value = try state(rules())
        value.start(.bones); advance(&value, 94)
        fillCombo(&value, count: 100)
        XCTAssertFalse(value.canUse(.bones))
        value.contact(blocked: false, generated: false, hitID: 101)
        XCTAssertTrue(value.canUse(.bones))
        let remaining = value.cooldownRemaining(.bones)
        value.start(.bones)
        XCTAssertEqual(value.cooldownRemaining(.bones), remaining,
                       "Zero-CD permission does not erase the existing cooldown timer")
    }

    func testNextRoundPreservesLightButClearsTemporaryEffectsAndDoesNotReuseSourceIDs() throws {
        var value = try state(rules())
        value.start(.shard)
        let oldID = try XCTUnwrap(value.activeCast?.id)
        value.contact(blocked: false, generated: false, hitID: 1)
        let retained = value.light
        value.beginNextRound(seed: 22)
        XCTAssertEqual(value.light, retained)
        XCTAssertEqual(value.combo, 0); XCTAssertNil(value.activeCast)
        XCTAssertEqual(value.typhoonRemainingTicks, 0); XCTAssertEqual(value.tranceRemainingTicks, 0)
        XCTAssertTrue(attacks(advance(&value, 100)).isEmpty)
        value.start(.shard)
        XCTAssertGreaterThan(try XCTUnwrap(value.activeCast?.id), oldID)
    }

    func testSourceReplayIncludesPendingQueuesPreHitIdentityAndFractionalLight() throws {
        var a = try state(rules()), b = try state(rules())
        a.start(.heavenfall); b.start(.heavenfall)
        for _ in 0..<248 { XCTAssertEqual(a.step(), b.step()) }
        XCTAssertEqual(try bytes(a), try bytes(b))
        a.prepareOrdinaryContact(blocked: true, kind: .weapon, hitID: 1)
        XCTAssertNotEqual(try bytes(a), try bytes(b), "Even a blocked prepared contact changes duplicate suppression")
        b.prepareOrdinaryContact(blocked: true, kind: .weapon, hitID: 1)
        XCTAssertEqual(try bytes(a), try bytes(b))
        for id in UInt64(2)...20 {
            XCTAssertEqual(a.contact(blocked: false, generated: false, hitID: id),
                           b.contact(blocked: false, generated: false, hitID: id))
            XCTAssertEqual(a.step(), b.step())
        }
        XCTAssertEqual(try bytes(a), try bytes(b))
    }
}
