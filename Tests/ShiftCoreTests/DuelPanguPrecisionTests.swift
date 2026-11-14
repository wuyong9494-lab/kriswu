import XCTest
@testable import ShiftCore

/// Explicit synthetic timing/base values. Some individual ratios and bonuses
/// match the newly readable panel, but no complete retail preset is supplied.
final class DuelPanguPrecisionTests: XCTestCase {
    private func rules(chargeTicks: Int = 4, carry: Bool = true, discardAtCapacity: Bool = false) -> DuelPanguRules {
        var value = DuelPanguTestFixture.rules(level: 6)
        value.light.maximum = 1000; value.light.initial = 0
        value.heavenfall.lightPerChargeTick = 1
        value.heavenfall.level6LightPerChargeTick = 99 // distinguish the nil compatibility path
        value.heavenfall.chargeTicks = chargeTicks
        value.heavenfall.level6ComboGain = 0
        value.heavenfall.level6LightChargeRatio = .init(numerator: 5, denominator: 4,
            carryAcrossCasts: carry, discardRemainderAtCapacity: discardAtCapacity)
        for index in value.abilities.indices where value.abilities[index].ability == .heavenfall {
            value.abilities[index].lightCost = 0; value.abilities[index].cooldownTicks = 0
        }
        return value
    }
    private func state(_ rules: DuelPanguRules, seed: UInt64 = 41) throws -> DuelPanguState {
        try XCTUnwrap(DuelPanguState(rules: rules, seed: seed))
    }
    @discardableResult private func advance(_ value: inout DuelPanguState, _ count: Int) -> [DuelPanguState.Effect] {
        var effects: [DuelPanguState.Effect] = []
        for _ in 0..<count { effects += value.step() }
        return effects
    }
    private func beginCharge(_ value: inout DuelPanguState, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(value.start(.heavenfall).isEmpty, file: file, line: line)
        let entryTick = value.rules.heavenfall.petrifyPhaseTicks + value.rules.heavenfall.riseTicks
        advance(&value, entryTick)
        XCTAssertEqual(value.activeCast?.phase, .charging, file: file, line: line)
    }
    private func finish(_ value: inout DuelPanguState) {
        for _ in 0..<value.rules.heavenfall.duration {
            if value.activeCast == nil { break }
            value.step()
        }
        XCTAssertNil(value.activeCast)
    }
    private func bytes(_ value: DuelPanguState) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 2)
        try value.appendReplayState(to: &writer); return writer.data
    }
    private func ruleBytes(_ value: DuelPanguRules) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 3)
        try value.appendReplayState(to: &writer); return writer.data
    }

    func testFiveQuartersChargeAccumulatesExactFractionsOnlyOnCompletedChargeIntervals() throws {
        var value = try state(rules())
        beginCharge(&value)
        XCTAssertEqual(value.light, 0, "Entering charging does not complete a charging interval")
        for expected in [1, 2, 3, 5] {
            value.step(); XCTAssertEqual(value.light, expected)
        }
        XCTAssertEqual(value.activeCast?.phase, .falling)
        finish(&value)
        XCTAssertEqual(value.light, 5, "Rising, falling and recovery do not charge Light")
    }

    func testFractionCarryAcrossCompletedAndInterruptedCastsFollowsItsExplicitPolicy() throws {
        for carry in [false, true] {
            for interrupted in [false, true] {
                var value = try state(rules(chargeTicks: interrupted ? 2 : 1, carry: carry))
                for cast in 0..<4 {
                    beginCharge(&value); value.step()
                    if interrupted {
                        XCTAssertFalse(value.interrupt().isEmpty)
                        XCTAssertNil(value.activeCast)
                    } else { finish(&value) }
                    XCTAssertEqual(value.light, cast == 3 && carry ? 5 : cast + 1,
                                   "carry=\(carry), interrupted=\(interrupted), cast=\(cast)")
                }
            }
        }
    }

    func testResetAlwaysDiscardsCarryAndDeniedInterruptionPreservesIt() throws {
        var configured = rules(chargeTicks: 4)
        let index = try XCTUnwrap(configured.abilities.firstIndex { $0.ability == .heavenfall })
        configured.abilities[index].interruptible = false
        var value = try state(configured)
        beginCharge(&value); advance(&value, 3)
        XCTAssertEqual(value.light, 3)
        let beforeDenied = try bytes(value)
        XCTAssertTrue(value.interrupt().isEmpty)
        XCTAssertEqual(try bytes(value), beforeDenied)
        value.step(); XCTAssertEqual(value.light, 5)
        XCTAssertFalse(value.interrupt(force: true).isEmpty)

        // Establish a three-quarter carry again, then reset instead of allowing
        // it to turn the next first interval into a two-unit gain.
        beginCharge(&value); advance(&value, 3)
        XCTAssertFalse(value.interrupt(force: true).isEmpty)
        value.reset(seed: 41)
        XCTAssertEqual(value.light, 0)
        beginCharge(&value); value.step()
        XCTAssertEqual(value.light, 1)
    }

    func testCapacityPolicyHandlesChargeOverflowAndOtherLightRestoration() throws {
        for discard in [false, true] {
            // 9 reaches capacity by charge; 10 overflows it; 0 reaches capacity
            // through an ordinary confirmed contact after a fractional charge.
            for initial in [9, 10, 0] {
                var configured = rules(discardAtCapacity: discard)
                configured.light.maximum = 10; configured.light.initial = initial
                configured.light.damageToLightNumerator = 1; configured.light.damageToLightDenominator = 1
                configured.light.regularHitGain = 9; configured.light.level3GainBonus = 0
                var value = try state(configured)
                beginCharge(&value); value.step()
                if initial == 0 { value.contact(blocked: false, generated: false, hitID: 1) }
                XCTAssertEqual(value.light, 10)
                XCTAssertEqual(value.receiveDamage(4, kind: .weapon).lightSpent, 4)
                XCTAssertEqual(value.light, 6)
                advance(&value, 3)
                XCTAssertEqual(value.light, discard ? 9 : 10,
                               "discard=\(discard), initial=\(initial)")
            }
        }
    }

    func testLegacyMissingOptionalsKeepIntegralRateAndLandingGrantWhileZeroRatioIsExplicit() throws {
        var configured = rules()
        configured.heavenfall.level6LightChargeRatio = nil
        configured.heavenfall.level6ComboGain = 7
        configured.heavenfall.level6ComboGainTrigger = nil
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(configured)) as? [String: Any])
        var heavenfall = try XCTUnwrap(object["heavenfall"] as? [String: Any])
        heavenfall.removeValue(forKey: "level6LightChargeRatio")
        heavenfall.removeValue(forKey: "level6ComboGainTrigger")
        object["heavenfall"] = heavenfall
        let decoded = try JSONDecoder().decode(DuelPanguRules.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded, configured)
        var value = try state(decoded)
        beginCharge(&value); advance(&value, 4)
        XCTAssertEqual(value.light, 396); XCTAssertEqual(value.combo, 0)
        advance(&value, decoded.heavenfall.fallTicks)
        XCTAssertEqual(value.combo, 7)

        configured.heavenfall.level6LightChargeRatio = .init(numerator: 0, denominator: 4,
            carryAcrossCasts: false, discardRemainderAtCapacity: true)
        value = try state(configured)
        beginCharge(&value); advance(&value, 4)
        XCTAssertEqual(value.light, 0, "A present zero ratio must not fall back to the legacy 99-unit rate")

        configured.level = 5
        configured.heavenfall.level6ComboGainTrigger = .castStarted
        value = try state(configured)
        beginCharge(&value); advance(&value, 4)
        XCTAssertEqual(value.light, 4, "Level 5 retains the unscaled base rate")
        finish(&value); XCTAssertEqual(value.combo, 0)
    }

    func testComboGrantOccursOnceAtOnlyTheSelectedBoundaryAndInterruptionCannotFakeAnEnd() throws {
        let triggers: [DuelPanguRules.TranceTrigger?] = [nil, .castStarted, .chargeStarted, .landing, .castEnded]
        for trigger in triggers {
            var configured = rules()
            configured.heavenfall.level6ComboGain = 7
            configured.heavenfall.level6ComboGainTrigger = trigger
            configured.combo.holdTicks = 1000; configured.combo.level6HoldTicks = 1180
            let h = configured.heavenfall
            let expectedTick: Int
            switch trigger ?? .landing {
            case .castStarted: expectedTick = 0
            case .chargeStarted: expectedTick = h.petrifyPhaseTicks + h.riseTicks
            case .landing: expectedTick = h.petrifyPhaseTicks + h.riseTicks + h.chargeTicks + h.fallTicks
            case .castEnded: expectedTick = h.duration
            }
            var value = try state(configured)
            value.start(.heavenfall)
            XCTAssertEqual(value.combo, expectedTick == 0 ? 7 : 0)
            XCTAssertTrue(value.start(.heavenfall).isEmpty)
            for tick in 1...(h.duration + 2) {
                value.step()
                XCTAssertEqual(value.combo, tick >= expectedTick ? 7 : 0,
                               "trigger=\(String(describing: trigger)), tick=\(tick)")
            }
            var cancelled = try state(configured)
            cancelled.start(.heavenfall)
            advance(&cancelled, max(0, expectedTick - 1))
            let effects = cancelled.interrupt(force: true)
            XCTAssertTrue(effects.contains(.castInterrupted(.heavenfall)))
            XCTAssertFalse(effects.contains(.castEnded(.heavenfall)))
            XCTAssertFalse(advance(&cancelled, h.duration + 2).contains(.castEnded(.heavenfall)))
            XCTAssertEqual(cancelled.combo, expectedTick == 0 ? 7 : 0)
        }
    }

    func testAdditiveSpeedAddsOnlyBonusesAndHonorsTheSharedMaximum() throws {
        let policies: [(DuelPanguRules.AttackSpeedStacking, Int)] = [
            (.maximum, 11_250), (.multiplicative, 12_656), (.additive, 12_500)
        ]
        for (policy, combined) in policies {
            var configured = rules()
            configured.combo.level4SpeedThreshold = 1
            configured.combo.level4AttackSpeedBps = 11_250
            configured.trance.attackSpeedBps = 11_250
            configured.trance.extraComboChancePerMillion = 0
            configured.heavenfall.tranceTrigger = .castStarted
            configured.policies.attackSpeedStacking = policy
            var value = try state(configured)
            XCTAssertEqual(value.attackSpeedBps, 10_000)
            value.contact(blocked: false, generated: false, hitID: 1)
            XCTAssertEqual(value.attackSpeedBps, 11_250)
            value.start(.heavenfall)
            XCTAssertEqual(value.attackSpeedBps, combined)
        }
        var configured = rules()
        configured.policies.attackSpeedStacking = .additive
        configured.combo.level4AttackSpeedBps = 50_000; configured.trance.attackSpeedBps = 60_000
        XCTAssertNoThrow(try configured.validate(), "The exact 100,000 BPS boundary is valid")
        configured.combo.level4AttackSpeedBps += 1
        XCTAssertThrowsError(try configured.validate())
    }

    func testRatioBoundsRequiredStrategiesAndRuleIdentityAreExplicit() throws {
        let valid = rules()
        for (numerator, denominator, base) in [(-1, 4, 1), (Int.max, 4, 1), (5, 0, 1),
                                              (5, -1, 1), (5, 1_000_001, 1), (2, 1, 1_000_000)] {
            var invalid = valid
            invalid.heavenfall.lightPerChargeTick = base
            invalid.heavenfall.level6LightChargeRatio?.numerator = numerator
            invalid.heavenfall.level6LightChargeRatio?.denominator = denominator
            XCTAssertThrowsError(try invalid.validate())
            XCTAssertNil(DuelPanguState(rules: invalid, seed: 1))
        }
        var variants: [DuelPanguRules] = []
        var changed = valid; changed.heavenfall.level6LightChargeRatio?.numerator = 6; variants.append(changed)
        changed = valid; changed.heavenfall.level6LightChargeRatio?.denominator = 5; variants.append(changed)
        changed = valid; changed.heavenfall.level6LightChargeRatio?.carryAcrossCasts = false; variants.append(changed)
        changed = valid; changed.heavenfall.level6LightChargeRatio?.discardRemainderAtCapacity = true; variants.append(changed)
        changed = valid; changed.heavenfall.level6ComboGainTrigger = .landing; variants.append(changed)
        changed = valid; changed.policies.attackSpeedStacking = .additive; variants.append(changed)
        for variant in variants { XCTAssertNotEqual(try ruleBytes(valid), try ruleBytes(variant)) }

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        var heavenfall = try XCTUnwrap(object["heavenfall"] as? [String: Any])
        var ratio = try XCTUnwrap(heavenfall["level6LightChargeRatio"] as? [String: Any])
        ratio.removeValue(forKey: "carryAcrossCasts")
        heavenfall["level6LightChargeRatio"] = ratio; object["heavenfall"] = heavenfall
        XCTAssertThrowsError(try JSONDecoder().decode(DuelPanguRules.self,
            from: JSONSerialization.data(withJSONObject: object)))
    }

    func testFractionalRemainderIsEncodedAtItsAuditedStateSlotAndResetToZero() throws {
        var value = try state(rules())
        beginCharge(&value); advance(&value, 3)
        XCTAssertEqual(value.light, 3)
        var prefix = try DuelReplayStateWriter(kind: 2)
        try value.rules.appendReplayState(to: &prefix)
        // Thirteen Int64 scalars follow the rules. The new remainder is last;
        // a rules-only or visible-Light-only encoder would lose these bytes.
        let offset = prefix.data.count + 4 + 12 * 8
        XCTAssertEqual(try bytes(value).subdata(in: offset..<(offset + 8)), Data([3, 0, 0, 0, 0, 0, 0, 0]))
        value.reset(seed: 41)
        XCTAssertEqual(try bytes(value).subdata(in: offset..<(offset + 8)), Data(repeating: 0, count: 8))
    }

    func testReadableLevelSixBonusesReachRealBranchesWithoutClaimingARetailPreset() throws {
        var configured = rules()
        // Verified individual panel values are combined with deliberately
        // synthetic base CD / Light / phase values and unresolved policies.
        // The fixture remains applicationAdaptation, including neutral incoming
        // damage: a panel's +50% DEFENSE is not a direct 50% damage reduction.
        configured.combo.maximum = 1000
        configured.combo.holdTicks = 120; configured.combo.level6HoldTicks = 300
        configured.combo.zeroCooldownThreshold = 100
        configured.combo.level4SpeedThreshold = 55; configured.combo.level4AttackSpeedBps = 11_250
        configured.combo.affectedKinds = []
        configured.light.initial = 100
        configured.light.regularHitGain = 0; configured.light.level3GainBonus = 0
        configured.level4PrimordialCooldownReductionTicks = 60
        configured.level6PrimordialCooldownReductionTicks = 60
        configured.level6CooldownRecoveryBps = 10_000
        configured.heavenfall.level6ComboGain = 20
        configured.heavenfall.level6ComboGainTrigger = .castStarted // explicit test policy, not panel timing proof
        configured.heavenfall.level6CooldownMultiplierBps = 5000
        configured.heavenfall.level6DamageBonusBps = 5000
        configured.heavenfall.tranceTrigger = .castStarted // explicit test policy
        configured.trance.durationTicks = 900; configured.trance.attackSpeedBps = 11_250
        configured.trance.extraComboChancePerMillion = 500_000; configured.trance.extraComboPoints = 1
        configured.trance.incomingDamageMultiplierBps = 10_000
        configured.heavyWindCount = 0; configured.typhoonWindCount = 0; configured.tranceWindCount = 1
        configured.policies.windTrigger = .attackStarted
        for index in configured.abilities.indices {
            configured.abilities[index].lightCost = 0
            configured.abilities[index].cooldownTicks = configured.abilities[index].ability == .heavenfall ? 1200 : 600
        }
        XCTAssertEqual(configured.basis, .applicationAdaptation)
        var value = try state(configured)
        value.start(.shard)
        XCTAssertEqual(value.cooldownRemaining(.shard), 480, "Two independent 60-tick reductions")
        value.interrupt(force: true)
        for id in UInt64(1)...100 { value.contact(blocked: false, generated: false, hitID: id) }
        XCTAssertEqual(value.combo, 100); XCTAssertEqual(value.comboRemainingTicks, 300)
        value.step()
        value.receiveDamage(1, kind: .weapon)
        XCTAssertEqual(value.combo, 100); XCTAssertEqual(value.comboRemainingTicks, 299)
        value.start(.bones)
        XCTAssertEqual(value.cooldownRemaining(.bones), 0)
        value.interrupt(force: true)
        value.start(.heavenfall)
        XCTAssertEqual(value.cooldownRemaining(.heavenfall), 600)
        XCTAssertEqual(value.combo, 120); XCTAssertEqual(value.tranceRemainingTicks, 900)
        XCTAssertEqual(value.attackSpeedBps, 11_250)
        let initialLight = value.light
        advance(&value, configured.heavenfall.petrifyPhaseTicks + configured.heavenfall.riseTicks)
        advance(&value, 4)
        XCTAssertEqual(value.light, initialLight + 5)
        let landing = advance(&value, configured.heavenfall.fallTicks)
        let strike = try XCTUnwrap(landing.compactMap { effect -> DuelPanguState.Attack? in
            if case .attack(let attack) = effect, !attack.generated { return attack }; return nil
        }.first)
        XCTAssertEqual(strike.damage, 30, "The synthetic 20-point base receives the documented +50% bonus")
        XCTAssertEqual(value.combo, 120, "Selecting castStarted must not also award the landing grant")
        finish(&value)
        XCTAssertEqual(value.combo, 120)
        let wind = value.attackStarted(heavy: false, eventID: 1).compactMap { effect -> DuelPanguState.Attack? in
            if case .attack(let attack) = effect { return attack }; return nil
        }
        XCTAssertEqual(wind.count, 1); XCTAssertTrue(wind.allSatisfy(\.generated))
        var replay = value
        var increments: Set<Int> = []
        for id in UInt64(200)..<264 {
            let previous = value.combo
            value.contact(blocked: false, generated: false, hitID: id)
            replay.contact(blocked: false, generated: false, hitID: id)
            increments.insert(value.combo - previous)
        }
        XCTAssertEqual(increments, Set([1, 2]), "Seeded successful attacks exercise both 50% outcomes")
        XCTAssertEqual(try bytes(value), try bytes(replay))
        let activeTicks = value.tranceRemainingTicks
        advance(&value, activeTicks)
        XCTAssertEqual(value.tranceRemainingTicks, 0)
    }
}
