import XCTest
@testable import ShiftCore

final class DuelTriadRulesTests: XCTestCase {
    func testEverySupportedLevelHasAnExplicitApplicationProfileAndSevenDistinctMotionRoles() throws {
        for level in 1...6 {
            let value = DuelTriadRules.debug(level: level)
            try value.validate()
            XCTAssertEqual(value.basis, .applicationAdaptation)
            XCTAssertTrue(value.abilities.allSatisfy { $0.evidence.basis == .applicationAdaptation })
            XCTAssertTrue(value.abilities.compactMap(\.attack).allSatisfy { $0.evidence.basis == .applicationAdaptation })
        }
        XCTAssertEqual(Set(DuelTriadRules.Ability.allCases.map(\.motionRole)),
            ["triadBranches", "triadMistBlade", "triadMistOnslaught", "triadLegionary", "triadHerald", "triadDynast", "triadCryingDance"])
    }
    func testAbsentL7L8RetailRulesCannotBeInventedFromTheReleaseAnnouncement() {
        for level in [0, 7, 8, Int.max] {
            XCTAssertThrowsError(try DuelTriadRules.debug(level: level).validate()) {
                XCTAssertEqual($0 as? DuelTriadRules.ValidationError, .level)
            }
        }
    }
    func testTuningAndTimingProvenanceSurvivesJSONRoundTrip() throws {
        var value = DuelTriadTestFixture.rules()
        value.branches.evidence = .init(basis: .referenceMeasurement, version: "synthetic-measurement-version",
                                       references: ["synthetic-measurement-only"])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(DuelTriadRules.self, from: data)
        XCTAssertEqual(decoded, value); try decoded.validate()
        XCTAssertEqual(decoded.mist.evidence.basis, .applicationAdaptation)
        XCTAssertEqual(decoded.branches.evidence.basis, .referenceMeasurement)
    }
    func testMissingGroupProvenanceAndMissingAttackProvenanceAreRejected() {
        var group = DuelTriadTestFixture.rules(); group.souls.evidence.references = []
        XCTAssertThrowsError(try group.validate())
        var attack = DuelTriadTestFixture.rules(); attack.abilities[0].attack?.evidence.version = ""
        XCTAssertThrowsError(try attack.validate())
    }
    func testMissingDuplicateAndWrongDeliveryAbilitiesCannotBecomePlayable() {
        var missing = DuelTriadTestFixture.rules(); missing.abilities.removeLast()
        XCTAssertThrowsError(try missing.validate())
        var duplicate = DuelTriadTestFixture.rules(); duplicate.abilities[1] = duplicate.abilities[0]
        XCTAssertThrowsError(try duplicate.validate())
        var wrong = DuelTriadTestFixture.rules(); wrong.abilities[0].attack?.delivery = .soulArrow
        XCTAssertThrowsError(try wrong.validate())
        var absent = DuelTriadTestFixture.rules(); absent.abilities[0].attack = nil
        XCTAssertThrowsError(try absent.validate())
    }
    func testMalformedResourceDamageAndGeometryBoundsFailBeforeStateCreation() {
        var values: [DuelTriadRules] = []
        var value = DuelTriadTestFixture.rules(); value.mist.initial = -1; values.append(value)
        value = DuelTriadTestFixture.rules(); value.mist.initial = value.mist.maximum + 1; values.append(value)
        value = DuelTriadTestFixture.rules(); value.blade.initialOnslaughtCharges = 4; values.append(value)
        value = DuelTriadTestFixture.rules(); value.suppression.totalTrueDamage = Int.max; values.append(value)
        value = DuelTriadTestFixture.rules(); value.blade.shadowConversionBps = 10_001; values.append(value)
        value = DuelTriadTestFixture.rules(); value.abilities[0].attack?.topMillimeters = -20_000; values.append(value)
        value = DuelTriadTestFixture.rules(); value.abilities[2].attack?.speedMillimetersPerTick = 0; values.append(value)
        for invalid in values {
            XCTAssertThrowsError(try invalid.validate())
            XCTAssertNil(DuelTriadState(rules: invalid, seed: 1))
        }
    }
    func testTimersQueuesAndDanceWindowAreBounded() {
        var value = DuelTriadTestFixture.rules(); value.branches.pulseIntervalTicks = 0
        XCTAssertThrowsError(try value.validate())
        value = DuelTriadTestFixture.rules(); value.souls.sequence = []
        XCTAssertThrowsError(try value.validate())
        value = DuelTriadTestFixture.rules(); value.souls.forestRainCount = 1000
        XCTAssertThrowsError(try value.validate())
        value = DuelTriadTestFixture.rules(); value.souls.notchCost = value.souls.maximumNotches + 1
        XCTAssertThrowsError(try value.validate())
        value = DuelTriadTestFixture.rules(); value.abilities[6].activeTicks = 2
        XCTAssertThrowsError(try value.validate())
        value = DuelTriadTestFixture.rules(); value.abilities[6].interruptible = true
        XCTAssertThrowsError(try value.validate())
        value = DuelTriadTestFixture.rules(); value.souls.sharedCooldownTicks = -1
        XCTAssertThrowsError(try value.validate())
        value.souls.sharedCooldownTicks = 36_001
        XCTAssertThrowsError(try value.validate())
    }
    func testRuleReplayIncludesProvenanceAndCanonicalizesAbilityOrder() throws {
        func bytes(_ value: DuelTriadRules) throws -> Data {
            var writer = try DuelReplayStateWriter(kind: 2)
            try value.appendReplayState(to: &writer); return writer.data
        }
        let original = DuelTriadTestFixture.rules()
        var reversed = original; reversed.abilities.reverse()
        XCTAssertEqual(try bytes(original), try bytes(reversed))
        var changed = original; changed.branches.evidence.version += "-other"
        XCTAssertNotEqual(try bytes(original), try bytes(changed))
    }

    func testRecoveredBlackNinjatoFactoryPreservesSourceAndApplicationBoundariesForEverySuppliedLevel() throws {
        for level in 1...6 {
            let value = try DuelTriadTestFixture.runtimeRules(level: level)
            try value.validate()
            XCTAssertEqual(value.level, level)
            XCTAssertEqual(value.basis, .applicationAdaptation)
            XCTAssertEqual(value.runtime?.evidence.basis, .sourceConfiguration)
            XCTAssertEqual(value.runtime?.tickRate, 60)
            XCTAssertEqual(value.runtime?.sourceFramesPerSecond, 30)
            XCTAssertEqual(value.ability(.branches)?.cooldownTicks, 900)
            XCTAssertEqual(value.ability(.legionary)?.cooldownTicks, 300)
            XCTAssertEqual(value.ability(.legionary)?.mistCost, 3300)
            XCTAssertEqual(value.souls.sharedCooldownTicks, 30)
            XCTAssertEqual(value.souls.maximumNotches, 36)
            XCTAssertEqual(value.souls.notchCost, 18)
            XCTAssertEqual(value.mist.suppressedHitGain, level >= 5 ? 4500 : 3300)
            XCTAssertEqual(value.mist.level5GainBonusBps, 0)
            XCTAssertEqual(value.suppression.totalTrueDamage, 0)
            XCTAssertEqual(value.runtime?.suppressionHealthFractionBps, 400)
            XCTAssertEqual(value.ability(.dynast)?.attack?.damage, 300)
            let data = try JSONEncoder().encode(value)
            XCTAssertEqual(try JSONDecoder().decode(DuelTriadRules.self, from: data), value)
        }
    }

    func testRecoveredFactoryRejectsUnsuppliedLevelsAndInvalidStatNormalization() throws {
        let template = DuelTriadTestFixture.rules()
        for level in [0, 7, 8] {
            XCTAssertThrowsError(try DuelTriadRules.h17BlackNinjato(level: level,
                maximumHealth: 1000, magicPower: 1000, spatialTemplate: template))
        }
        XCTAssertThrowsError(try DuelTriadRules.h17BlackNinjato(level: 6,
            maximumHealth: 0, magicPower: 1000, spatialTemplate: template))
        XCTAssertThrowsError(try DuelTriadRules.h17BlackNinjato(level: 6,
            maximumHealth: 1000, magicPower: Int.max, spatialTemplate: template))
        var value = try DuelTriadTestFixture.runtimeRules()
        value.runtime?.mistGainPulseCount = 0
        XCTAssertThrowsError(try value.validate())
        value = try DuelTriadTestFixture.runtimeRules(); value.runtime?.configurationSHA256 = "not-a-hash"
        XCTAssertThrowsError(try value.validate())
        value = try DuelTriadTestFixture.runtimeRules(); value.runtime?.tickRate = 30
        XCTAssertThrowsError(try value.validate())
    }
}
