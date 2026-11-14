import XCTest
@testable import ShiftCore

final class DuelPanguStateTests: XCTestCase {
    private func state(_ rules: DuelPanguRules = DuelPanguTestFixture.rules(), seed: UInt64 = 17) throws -> DuelPanguState {
        try XCTUnwrap(DuelPanguState(rules: rules, seed: seed))
    }
    private func attacks(_ effects: [DuelPanguState.Effect]) -> [DuelPanguState.Attack] {
        effects.compactMap { if case .attack(let value) = $0 { return value }; return nil }
    }
    private func controls(_ effects: [DuelPanguState.Effect]) -> [DuelPanguState.Control] {
        effects.compactMap { if case .control(let value) = $0 { return value }; return nil }
    }
    @discardableResult private func advance(_ state: inout DuelPanguState, _ ticks: Int) -> [DuelPanguState.Effect] {
        var result: [DuelPanguState.Effect] = []
        for _ in 0..<ticks { result += state.step() }
        return result
    }
    private func bytes(_ value: DuelPanguState) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 2)
        try value.appendReplayState(to: &writer); return writer.data
    }

    func testLightConvertsIntegralDamageAndSpillsOnlyUnabsorbedDamageToHealth() throws {
        var rules = DuelPanguTestFixture.rules(level: 1)
        rules.light.initial = 10
        var value = try state(rules)
        XCTAssertFalse(value.canUse(.shard), "Level 1 has not unlocked the four Primordial abilities")
        XCTAssertTrue(value.canUse(.spear), "Initial Light covers this fixture's explicit five-unit spear cost")
        let receipt = value.receiveDamage(9, kind: .weapon)
        XCTAssertEqual(receipt.absorbedDamage, 6)
        XCTAssertEqual(receipt.lightSpent, 9)
        XCTAssertEqual(receipt.healthDamage, 3)
        XCTAssertEqual(value.light, 1)
        let second = value.receiveDamage(1, kind: .unarmed)
        XCTAssertEqual(second.absorbedDamage, 0)
        XCTAssertEqual(second.healthDamage, 1)
        XCTAssertEqual(value.light, 1, "A fractional light capacity cannot erase one full HP")
        XCTAssertTrue(value.throwImmune); XCTAssertFalse(value.canBeThrown)
        XCTAssertFalse(value.canUse(.spear), "One remaining Light cannot pay the configured five-unit cost")
    }

    func testAbsorptionKindsAndInvalidDamageAreExplicitAndDoNotMutateState() throws {
        var rules = DuelPanguTestFixture.rules(level: 1)
        rules.light.absorbedKinds = [.weapon]
        var value = try state(rules)
        XCTAssertEqual(value.receiveDamage(8, kind: .shadow).healthDamage, 8)
        XCTAssertEqual(value.light, 80)
        let snapshot = value
        XCTAssertFalse(value.receiveDamage(-1, kind: .weapon).accepted)
        XCTAssertFalse(value.receiveDamage(Int.max, kind: .weapon).accepted)
        XCTAssertEqual(value, snapshot)
    }

    func testComboGainsCapDamageResetsOnDamageAndExpiresAtTheExactTick() throws {
        var value = try state(DuelPanguTestFixture.rules(level: 1))
        for id in UInt64(1)...8 { value.contact(blocked: false, generated: false, hitID: id) }
        XCTAssertEqual(value.combo, 8)
        XCTAssertEqual(value.outgoingDamage(100, kind: .weapon), 150)
        XCTAssertEqual(value.comboRemainingTicks, 20)
        advance(&value, 19); XCTAssertEqual(value.combo, 8)
        advance(&value, 1); XCTAssertEqual(value.combo, 0)
        value.contact(blocked: false, generated: false, hitID: 9)
        let receipt = value.receiveDamage(2, kind: .weapon)
        XCTAssertTrue(receipt.comboReset)
        XCTAssertEqual(value.combo, 0)
        XCTAssertEqual(receipt.healthDamage, 0, "The fixture explicitly resets combo even on shield-only damage")
    }

    func testBlockedComboAndRegenerationDependOnSelectedPoliciesAndLevel() throws {
        for level in [4, 5] {
            var rules = DuelPanguTestFixture.rules(level: level)
            rules.policies.blockedHitsCountCombo = true
            rules.policies.blockedPrimordialStartsRhythm = true
            var value = try state(rules)
            value.contact(ability: .shard, blocked: true, generated: false, hitID: 1)
            XCTAssertEqual(value.combo, 1)
            XCTAssertEqual(value.light, level == 5 ? 83 : 80)
            XCTAssertEqual(value.rhythmRemainingTicks, 12)
        }
        var value = try state(DuelPanguTestFixture.rules(level: 4))
        value.contact(ability: .shard, blocked: true, generated: false, hitID: 1)
        XCTAssertEqual(value.combo, 0); XCTAssertEqual(value.light, 80); XCTAssertEqual(value.rhythmRemainingTicks, 0)
    }

    func testEveryDirectionalAbilitySpendsLightStartsCooldownAndWaitsForItsRelease() throws {
        for ability in [DuelPanguRules.Ability.shard, .typhoon, .splitter, .bones] {
            var value = try state(DuelPanguTestFixture.rules(level: 2))
            let start = value.start(ability)
            XCTAssertEqual(value.light, 75); XCTAssertEqual(value.activeCast?.tick, 0)
            XCTAssertEqual(value.activeCast?.phase, .startup)
            XCTAssertEqual(value.cooldownRemaining(ability), ability == .typhoon ? 40 : 12)
            XCTAssertTrue(attacks(start).isEmpty)
            XCTAssertFalse(value.canUse(.shard), "A second cast must not replace the current action")
            XCTAssertTrue(attacks(value.step()).isEmpty)
            let released = attacks(value.step())
            XCTAssertEqual(released.count, ability == .typhoon ? 0 : 1)
            XCTAssertEqual(value.combo, 0)
            XCTAssertEqual(value.rhythmRemainingTicks, 0, "A released projectile is not itself a confirmed hit")
            advance(&value, 3)
            XCTAssertNil(value.activeCast)
            XCTAssertFalse(value.canUse(ability))
        }
    }

    func testTyphoonFixedCooldownPriorityIsIndependentOfLevel6NoCooldownThreshold() throws {
        for priority in [DuelPanguRules.TyphoonCooldownPriority.fixedWins, .level6ZeroWins] {
            var rules = DuelPanguTestFixture.rules()
            rules.policies.typhoonCooldownPriority = priority
            var value = try state(rules)
            for id in UInt64(1)...6 { value.contact(blocked: false, generated: false, hitID: id) }
            value.start(.typhoon)
            XCTAssertEqual(value.cooldownRemaining(.typhoon), priority == .fixedWins ? 40 : 0)
            advance(&value, 5)
            XCTAssertFalse(value.canUse(.typhoon), "Zero CD cannot restart an already active Typhoon and reset its gate quota")
            XCTAssertEqual(value.cooldownRemaining(.typhoon), priority == .fixedWins ? 35 : 0)
        }
    }

    func testExistingCooldownClearingIsExplicitAndDoesNotImplicitlyResetTyphoon() throws {
        for clear in [false, true] {
            var rules = DuelPanguTestFixture.rules()
            rules.policies.zeroCooldownClearsExisting = clear
            var value = try state(rules)
            value.start(.shard); advance(&value, 5)
            XCTAssertEqual(value.cooldownRemaining(.shard), 7)
            for id in UInt64(1)...6 { value.contact(blocked: false, generated: false, hitID: id) }
            XCTAssertEqual(value.cooldownRemaining(.shard), clear ? 0 : 7)
        }
    }

    func testLevel4CooldownReductionIsSeparateFromLevel6RecoveryAndTyphoonPriority() throws {
        for level in [3, 4] {
            for affectsTyphoon in [false, true] {
                var rules = DuelPanguTestFixture.rules(level: level)
                rules.level4PrimordialCooldownReductionTicks = 3
                rules.policies.level4ReductionAffectsTyphoon = affectsTyphoon
                var ordinary = try state(rules), wind = try state(rules), heavenfall = try state(rules)
                ordinary.start(.shard); wind.start(.typhoon); heavenfall.start(.heavenfall)
                XCTAssertEqual(ordinary.cooldownRemaining(.shard), level == 4 ? 9 : 12)
                XCTAssertEqual(wind.cooldownRemaining(.typhoon), level == 4 && affectsTyphoon ? 37 : 40)
                XCTAssertEqual(heavenfall.cooldownRemaining(.heavenfall), 12,
                               "Heavenfall is not one of the four Primordial cooldowns")
                ordinary.step()
                XCTAssertEqual(ordinary.cooldownRemaining(.shard), level == 4 ? 8 : 11,
                               "L4 reduces the starting duration; it does not apply L6's tick recovery rate")
            }
        }
    }

    func testLevel5AdditionalPrimordialLightDoesNotAffectOrdinaryOrGeneratedHits() throws {
        for level in [4, 5] {
            var rules = DuelPanguTestFixture.rules(level: level)
            rules.light.initial = 10
            rules.light.level5PrimordialGainBonus = 6
            rules.policies.generatedHitsRestoreLight = true
            var primordial = try state(rules), ordinary = try state(rules), generated = try state(rules)
            primordial.contact(ability: .shard, blocked: false, generated: false, hitID: 1)
            ordinary.contact(blocked: false, generated: false, hitID: 1)
            generated.contact(ability: .shard, blocked: false, generated: true, hitID: 1)
            XCTAssertEqual(primordial.light, level == 5 ? 25 : 19)
            XCTAssertEqual(ordinary.light, 16); XCTAssertEqual(generated.light, 16)
            primordial.contact(ability: .shard, blocked: true, generated: false, hitID: 2)
            XCTAssertEqual(primordial.light, level == 5 ? 28 : 19,
                           "Blocked contacts use their separate L5 gain, without applying the effective-hit bonus")
        }
    }

    func testLevel6FixedCooldownReductionSubtractsTheSameTicksFromDifferentBaseDurations() throws {
        for level in [5, 6] {
            var rules = DuelPanguTestFixture.rules(level: level)
            rules.level6PrimordialCooldownReductionTicks = 3
            let splitterIndex = try XCTUnwrap(rules.abilities.firstIndex { $0.ability == .splitter })
            rules.abilities[splitterIndex].cooldownTicks = 20
            for (ability, base) in [(DuelPanguRules.Ability.shard, 12), (.splitter, 20)] {
                var value = try state(rules)
                value.start(ability)
                let expected = base - (level == 6 ? 3 : 0)
                XCTAssertEqual(value.cooldownRemaining(ability), expected)
                value.step()
                XCTAssertEqual(value.cooldownRemaining(ability), expected - 1,
                               "The fixed subtraction does not also accelerate every recovery tick")
            }
        }
        var rules = DuelPanguTestFixture.rules()
        rules.level6PrimordialCooldownReductionTicks = 3
        rules.level6CooldownRecoveryBps = 20_000
        var rate = try state(rules)
        rate.start(.shard)
        XCTAssertEqual(rate.cooldownRemaining(.shard), 9)
        rate.step()
        XCTAssertEqual(rate.cooldownRemaining(.shard), 7,
                       "An explicitly configured application recovery rate is independent of the fixed reduction")
    }

    func testLevel4AndLevel6FixedCooldownReductionsRespectTyphoonAndZeroCooldownPolicies() throws {
        for affectLevel4 in [false, true] {
            for affectLevel6 in [false, true] {
                for priority in [DuelPanguRules.TyphoonCooldownPriority.fixedWins, .level6ZeroWins] {
                    var rules = DuelPanguTestFixture.rules()
                    rules.level4PrimordialCooldownReductionTicks = 2
                    rules.level6PrimordialCooldownReductionTicks = 3
                    rules.policies.level4ReductionAffectsTyphoon = affectLevel4
                    rules.policies.level6RecoveryAffectsTyphoon = affectLevel6
                    rules.policies.typhoonCooldownPriority = priority
                    var ordinary = try state(rules), wind = try state(rules), thresholdWind = try state(rules)
                    ordinary.start(.shard)
                    XCTAssertEqual(ordinary.cooldownRemaining(.shard), 7,
                                   "The separately supplied two- and three-tick reductions both apply at L6")
                    let fixed = 40 - (affectLevel4 ? 2 : 0) - (affectLevel6 ? 3 : 0)
                    wind.start(.typhoon)
                    XCTAssertEqual(wind.cooldownRemaining(.typhoon), fixed)
                    for id in UInt64(1)...6 {
                        thresholdWind.contact(blocked: false, generated: false, hitID: id)
                    }
                    thresholdWind.start(.typhoon)
                    XCTAssertEqual(thresholdWind.cooldownRemaining(.typhoon), priority == .fixedWins ? fixed : 0)
                }
            }
        }
    }

    func testStormGateRequiresActiveTyphoonAndConsumesItsPerCycleQuota() throws {
        var value = try state(DuelPanguTestFixture.rules(level: 4))
        XCTAssertFalse(value.canUse(.stormGate))
        value.start(.typhoon); advance(&value, 5)
        XCTAssertEqual(value.typhoonCycle, 1)
        XCTAssertTrue(value.canUse(.stormGate))
        value.start(.stormGate)
        XCTAssertEqual(value.stormGateUses, 1)
        XCTAssertTrue(value.step().allSatisfy { if case .teleportBehind = $0 { return false }; return true })
        XCTAssertTrue(value.step().contains(.teleportBehind(distanceMillimeters: 600)))
        advance(&value, 3)
        XCTAssertFalse(value.canUse(.stormGate))
        let damage = value.receiveDamage(10, kind: .weapon)
        XCTAssertEqual(damage.lightSpent, 8, "Level 4 Typhoon's explicit 50% reduction changes shield conversion")
        advance(&value, 30)
        XCTAssertTrue(value.canUse(.typhoon))
        value.start(.typhoon); advance(&value, 5)
        XCTAssertEqual(value.typhoonCycle, 2)
        XCTAssertEqual(value.stormGateUses, 0)
        XCTAssertTrue(value.canUse(.stormGate))
    }

    func testRhythmSpearSnapshotsEmpowermentAndPinsOnlyAfterActualContact() throws {
        var value = try state(DuelPanguTestFixture.rules(level: 2))
        value.contact(ability: .shard, blocked: false, generated: false, hitID: 1)
        XCTAssertEqual(value.rhythmRemainingTicks, 12)
        XCTAssertEqual(value.light, 87)
        XCTAssertTrue(controls(value.start(.spear)).isEmpty)
        XCTAssertEqual(value.rhythmRemainingTicks, 0)
        let spear = try XCTUnwrap(attacks(advance(&value, 2)).first)
        XCTAssertTrue(spear.empowered); XCTAssertEqual(spear.damageKind, .shadow)
        advance(&value, 12)
        let pin = controls(value.contact(ability: .spear, blocked: false, generated: false,
                                         hitID: 2, empowered: spear.empowered))
        XCTAssertEqual(pin.map(\.kind), [.pinned]); XCTAssertEqual(pin.first?.durationTicks, 7)
        XCTAssertTrue(value.contact(ability: .spear, blocked: false, generated: false, hitID: 2,
                                    empowered: true).isEmpty)
        XCTAssertTrue(controls(value.contact(ability: .spear, blocked: true, generated: false, hitID: 3,
                                             empowered: true)).isEmpty)
    }

    func testHeavenfallPhasesChargeExactlyOncePerTickAndEmitSpatialDamageAtLanding() throws {
        var value = try state(DuelPanguTestFixture.rules(level: 6))
        let start = value.start(.heavenfall)
        let petrify = try XCTUnwrap(controls(start).first)
        XCTAssertEqual(petrify.kind, .petrify); XCTAssertEqual(petrify.durationTicks, 9)
        XCTAssertTrue(attacks(start).isEmpty); XCTAssertEqual(value.light, 75)
        XCTAssertTrue(advance(&value, 2).contains(.pillarRise(heightMillimeters: 1800, durationTicks: 2)))
        XCTAssertEqual(value.activeCast?.phase, .rising)
        advance(&value, 2)
        XCTAssertEqual(value.activeCast?.phase, .charging); XCTAssertEqual(value.light, 75)
        let charge = advance(&value, 3)
        XCTAssertEqual(value.light, 87)
        XCTAssertTrue(charge.contains(.descend(velocityMillimetersPerTick: 900)))
        XCTAssertEqual(value.activeCast?.phase, .falling)
        let landing = advance(&value, 2)
        XCTAssertEqual(attacks(landing).filter { !$0.generated }.count, 1)
        XCTAssertEqual(attacks(landing).first?.ability, .heavenfall)
        XCTAssertEqual(value.activeCast?.phase, .landing)
        XCTAssertEqual(value.combo, 2)
        XCTAssertEqual(value.tranceRemainingTicks, 15)
        XCTAssertEqual(value.attackSpeedBps, 15_000)
        XCTAssertTrue(advance(&value, 2).contains(.castEnded(.heavenfall)))
        XCTAssertNil(value.activeCast)
    }

    func testHeavenfallInterruptionCancelsFutureDamageAndReleasesOnlyItsOwnPetrification() throws {
        var value = try state(DuelPanguTestFixture.rules(level: 2))
        let original = try XCTUnwrap(controls(value.start(.heavenfall)).first)
        advance(&value, 3)
        let cancellation = controls(value.interrupt())
        XCTAssertEqual(cancellation.first?.sourceID, original.sourceID)
        XCTAssertEqual(cancellation.first?.durationTicks, 0)
        XCTAssertNil(value.activeCast)
        XCTAssertTrue(attacks(advance(&value, 20)).isEmpty)
        var rules = DuelPanguTestFixture.rules(level: 2)
        let index = try XCTUnwrap(rules.abilities.firstIndex { $0.ability == .heavenfall })
        rules.abilities[index].interruptible = false; rules.abilities[index].damageImmune = true
        value = try state(rules)
        value.start(.heavenfall)
        XCTAssertTrue(value.interrupt().isEmpty); XCTAssertNotNil(value.activeCast)
        XCTAssertEqual(value.receiveDamage(100, kind: .weapon).adjustedDamage, 0)
        XCTAssertFalse(value.interrupt(force: true).isEmpty)
    }

    func testHeavenfallLandingCannotPrecedePhysicalDescentOrDelayAfterIt() throws {
        var rules = DuelPanguTestFixture.rules()
        rules.heavenfall.pillarHeightMillimeters = 1801
        XCTAssertThrowsError(try rules.validate(), "Two 900 mm ticks leave the caster one millimeter airborne")
        rules.heavenfall.fallTicks = 4
        XCTAssertThrowsError(try rules.validate(), "An extra nominal fall tick would desynchronize the grounded strike")
        rules.heavenfall.fallTicks = 3
        var value = try state(rules)
        value.start(.heavenfall)
        advance(&value, 9)
        XCTAssertEqual(value.activeCast?.phase, .falling)
        XCTAssertEqual(value.tranceRemainingTicks, 0)
        XCTAssertTrue(value.step().contains(.castPhase(.heavenfall, .landing)))
        XCTAssertEqual(value.tranceRemainingTicks, rules.trance.durationTicks)
    }

    func testLevel4SplitterDreadAndWindScheduleRequireContactAndDoNotRecurse() throws {
        var value = try state(DuelPanguTestFixture.rules(level: 4))
        value.start(.splitter)
        let release = attacks(advance(&value, 2))
        XCTAssertEqual(release.first?.damage, 23)
        XCTAssertEqual(value.rhythmRemainingTicks, 0)
        let hit = value.contact(ability: .splitter, blocked: false, generated: false, hitID: 1)
        let dread = try XCTUnwrap(controls(hit).first)
        XCTAssertEqual(dread.kind, .dread); XCTAssertEqual(dread.durationTicks, 8)
        XCTAssertEqual(dread.damageTakenBonusBps, 2000); XCTAssertEqual(dread.outgoingReductionBps, 3000)
        XCTAssertEqual(attacks(hit).count, 1)
        XCTAssertTrue(attacks(value.step()).isEmpty)
        XCTAssertEqual(attacks(value.step()).count, 1)
        XCTAssertTrue(attacks(value.step()).isEmpty)
        XCTAssertEqual(attacks(value.step()).count, 1)
        let beforeCombo = value.combo, beforeLight = value.light, beforeRhythm = value.rhythmRemainingTicks
        XCTAssertTrue(value.contact(ability: .splitter, blocked: false, generated: true, hitID: 2).isEmpty)
        XCTAssertEqual(value.combo, beforeCombo); XCTAssertEqual(value.light, beforeLight)
        XCTAssertEqual(value.rhythmRemainingTicks, beforeRhythm)
    }

    func testPendingSplitterWindsCanBeCancelledAfterCastEndsWithoutChangingResources() throws {
        for forceInterrupt in [false, true] {
            var rules = DuelPanguTestFixture.rules(level: 4)
            rules.earth.splitterWindIntervalTicks = 10
            var value = try state(rules)
            value.start(.splitter); advance(&value, 2)
            let first = attacks(value.contact(ability: .splitter, blocked: false, generated: false, hitID: 1))
            XCTAssertEqual(first.count, 1, "The first wind has already been emitted and belongs to the spatial layer")
            XCTAssertTrue(attacks(advance(&value, 3)).isEmpty)
            XCTAssertNil(value.activeCast, "The follow-up schedule outlives this short synthetic cast")
            let resources = [value.light, value.combo, value.comboRemainingTicks,
                             value.rhythmRemainingTicks, value.rangedCharges]
            let cooldowns = DuelPanguRules.Ability.allCases.map(value.cooldownRemaining)
            if forceInterrupt { XCTAssertTrue(value.interrupt(force: true).isEmpty) }
            else { value.cancelPendingDerivedAttacks() }
            XCTAssertEqual([value.light, value.combo, value.comboRemainingTicks,
                            value.rhythmRemainingTicks, value.rangedCharges], resources)
            XCTAssertEqual(DuelPanguRules.Ability.allCases.map(value.cooldownRemaining), cooldowns)
            XCTAssertTrue(attacks(advance(&value, 30)).isEmpty,
                          "Neither cancelled delayed wind may be emitted after a knockdown or round-end cancellation")
        }
    }

    func testBonesCreatesSeparateLandingAndBoulderWindowsAndLandingIsDeduplicated() throws {
        var value = try state(DuelPanguTestFixture.rules(level: 4))
        value.start(.bones); advance(&value, 5)
        XCTAssertEqual(value.earthquakeRemainingTicks, 0)
        value.contact(ability: .bones, blocked: false, generated: false, hitID: 1)
        XCTAssertEqual(value.earthquakeRemainingTicks, 14); XCTAssertEqual(value.boulderBonusRemainingTicks, 10)
        let landing = attacks(value.landed(eventID: 1))
        XCTAssertEqual(landing.count, 1); XCTAssertEqual(landing.first?.delivery, .landingShock)
        XCTAssertTrue(value.landed(eventID: 1).isEmpty)
        let bonus = attacks(value.contact(ability: .shard, blocked: false, generated: false, hitID: 2))
        XCTAssertEqual(bonus.filter { $0.damageKind == .unarmed }.count, 1)
        XCTAssertTrue(bonus.allSatisfy(\.generated))
        advance(&value, 10)
        XCTAssertEqual(value.boulderBonusRemainingTicks, 0); XCTAssertEqual(value.earthquakeRemainingTicks, 4)
        XCTAssertTrue(attacks(value.contact(ability: .shard, blocked: false, generated: false, hitID: 3))
            .allSatisfy { $0.damageKind != .unarmed })
        XCTAssertEqual(attacks(value.landed(eventID: 2)).count, 1)
        advance(&value, 4)
        XCTAssertTrue(value.landed(eventID: 3).isEmpty)
    }

    func testLevel5RangedChargesUseExactAcceleratedRechargeAndContinuousEmpowerment() throws {
        var rules = DuelPanguTestFixture.rules(level: 5)
        rules.ranged.initialCharges = 0
        var normal = try state(rules), accelerated = try state(rules)
        XCTAssertFalse(normal.canUse(.spear))
        for id in UInt64(1)...4 { accelerated.contact(blocked: false, generated: false, hitID: id) }
        advance(&normal, 5); advance(&accelerated, 5)
        XCTAssertEqual(normal.rangedCharges, 0); XCTAssertEqual(accelerated.rangedCharges, 1)
        XCTAssertEqual(accelerated.rhythmRemainingTicks, 0)
        accelerated.start(.spear)
        XCTAssertTrue(try XCTUnwrap(attacks(advance(&accelerated, 2)).first).empowered)
        advance(&normal, 5)
        XCTAssertEqual(normal.rangedCharges, 1)
        advance(&accelerated, 3)
        XCTAssertEqual(accelerated.rangedCharges, 1)
        XCTAssertTrue(accelerated.canUse(.spear) == false, "Charges and ability cooldown are separate gates")
    }

    func testLevel6RetainsComboOnDamageAndExistingHoldPolicyIsExplicit() throws {
        for refresh in [false, true] {
            var rules = DuelPanguTestFixture.rules()
            rules.policies.level6ReceivedHitRefreshesHold = refresh
            var value = try state(rules)
            value.contact(blocked: false, generated: false, hitID: 1)
            advance(&value, 9)
            let receipt = value.receiveDamage(10, kind: .weapon)
            XCTAssertFalse(receipt.comboReset); XCTAssertEqual(value.combo, 1)
            XCTAssertEqual(value.comboRemainingTicks, refresh ? 40 : 31)
        }
    }

    func testLevel4AttackSpeedAndTranceUseExplicitStackingPolicy() throws {
        let policies: [(DuelPanguRules.AttackSpeedStacking, Int)] = [
            (.maximum, 15_000), (.multiplicative, 18_750), (.additive, 17_500)
        ]
        for (stacking, combined) in policies {
            var rules = DuelPanguTestFixture.rules()
            rules.policies.attackSpeedStacking = stacking
            rules.heavenfall.tranceTrigger = .castStarted
            var value = try state(rules)
            XCTAssertEqual(value.attackSpeedBps, 10_000)
            for id in UInt64(1)...5 { value.contact(blocked: false, generated: false, hitID: id) }
            XCTAssertEqual(value.attackSpeedBps, 12_500)
            value.start(.heavenfall)
            XCTAssertEqual(value.attackSpeedBps, combined)
            XCTAssertEqual(value.receiveDamage(20, kind: .weapon).adjustedDamage, 10)
        }
        var lowerLevel = try state(DuelPanguTestFixture.rules(level: 3))
        for id in UInt64(1)...8 { lowerLevel.contact(blocked: false, generated: false, hitID: id) }
        XCTAssertEqual(lowerLevel.attackSpeedBps, 10_000)
    }

    func testTranceExtraComboIsSeededAndGeneratedHitsCannotCreateAnInfiniteChain() throws {
        var rules = DuelPanguTestFixture.rules()
        rules.heavenfall.tranceTrigger = .castStarted
        rules.trance.extraComboChancePerMillion = 1_000_000
        rules.policies.generatedHitsCountCombo = true
        rules.policies.generatedHitsRestoreLight = true
        var left = try state(rules, seed: 42), right = try state(rules, seed: 42)
        left.start(.heavenfall); right.start(.heavenfall)
        let a = left.contact(blocked: false, generated: false, hitID: 1)
        let b = right.contact(blocked: false, generated: false, hitID: 1)
        XCTAssertEqual(a, b); XCTAssertEqual(left.combo, 3); XCTAssertEqual(try bytes(left), try bytes(right))
        XCTAssertEqual(attacks(a).count, 3)
        XCTAssertTrue(left.contact(blocked: false, generated: true, hitID: 2).isEmpty)
        XCTAssertEqual(left.combo, 4, "Generated hits use the configured base gain but cannot roll another Trance proc")
        let after = try bytes(left)
        XCTAssertTrue(left.contact(blocked: false, generated: true, hitID: 2).isEmpty)
        XCTAssertEqual(try bytes(left), after)
    }

    func testStartupWindTriggerCanWhiffWithoutConfirmingComboAndIsDeduplicated() throws {
        var rules = DuelPanguTestFixture.rules(level: 2)
        rules.policies.windTrigger = .attackStarted
        var value = try state(rules)
        value.contact(blocked: false, generated: false, hitID: 1)
        value.contact(blocked: false, generated: false, hitID: 2)
        let wind = attacks(value.attackStarted(heavy: true, eventID: 1))
        XCTAssertEqual(wind.count, 1); XCTAssertNil(wind.first?.ability)
        XCTAssertEqual(value.combo, 2)
        XCTAssertTrue(value.attackStarted(heavy: true, eventID: 1).isEmpty)
        XCTAssertTrue(value.contact(blocked: false, generated: false, hitID: 3, heavy: true).isEmpty)
    }

    func testStateReplayIncludesPrivateRNGPendingWindsAndDeduplicationMarkers() throws {
        let rules = DuelPanguTestFixture.rules(level: 4)
        var first = try state(rules, seed: 1), second = try state(rules, seed: 2)
        XCTAssertNotEqual(try bytes(first), try bytes(second))
        second = first
        second.contact(blocked: true, generated: true, hitID: 17)
        XCTAssertEqual(first.combo, second.combo); XCTAssertEqual(first.light, second.light)
        XCTAssertNotEqual(try bytes(first), try bytes(second), "An ignored generated contact still advances its replayed duplicate guard")
        first.contact(ability: .splitter, blocked: false, generated: false, hitID: 18)
        let pending = try bytes(first)
        first.step()
        XCTAssertNotEqual(pending, try bytes(first))
        first.reset(seed: 1)
        XCTAssertEqual(first, try state(rules, seed: 1))
    }

    func testValidationRejectsOverflowRangesAmbiguousSourcesAndImpossibleSpeedBeforeStateCreation() throws {
        let valid = DuelPanguTestFixture.rules()
        XCTAssertNoThrow(try valid.validate())
        var cases: [DuelPanguRules] = []
        var value = valid; value.maximumHealth = 0; cases.append(value)
        value = valid; value.maximumHealth = 1_000_001; cases.append(value)
        value = valid; value.maximumHealth = Int.max; cases.append(value)
        value = valid; value.light.maximum = Int.max; cases.append(value)
        value = valid; value.light.damageToLightDenominator = 0; cases.append(value)
        value = valid; value.combo.pointsPerHit = -1; cases.append(value)
        value = valid; value.combo.level4AttackSpeedBps = 9999; cases.append(value)
        value = valid; value.trance.attackSpeedBps = 9999; cases.append(value)
        value = valid; value.policies.attackSpeedStacking = .multiplicative
        value.combo.level4AttackSpeedBps = 100_000; value.trance.attackSpeedBps = 100_000; cases.append(value)
        value = valid; value.abilities[0].startupTicks = Int.max; cases.append(value)
        value = valid; value.abilities[0].attack.radiusMillimeters = 0; cases.append(value)
        value = valid; value.abilities[0].attack.hitboxTopMillimeters = value.abilities[0].attack.hitboxBottomMillimeters; cases.append(value)
        value = valid; value.abilities[0].attack.projectileSpeedMillimetersPerTick = 0; cases.append(value)
        value = valid; value.heavenfall.chargeTicks = Int.max; cases.append(value)
        value = valid; value.trance.extraComboChancePerMillion = 1_000_001; cases.append(value)
        value = valid; value.level6PrimordialCooldownReductionTicks = -1; cases.append(value)
        value = valid; value.level6PrimordialCooldownReductionTicks = Int.max; cases.append(value)
        value = valid; value.basis = .sourceConfiguration; cases.append(value)
        value = valid; value.basis = .referenceMeasurement; value.evidence = []; cases.append(value)
        for invalid in cases {
            XCTAssertThrowsError(try invalid.validate())
            XCTAssertNil(DuelPanguState(rules: invalid, seed: 0))
        }
    }
}
