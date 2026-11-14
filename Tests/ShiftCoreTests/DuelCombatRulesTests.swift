import XCTest
@testable import ShiftCore

final class DuelCombatRulesTests: XCTestCase {
    private func withRules(_ catalog: DuelWeaponCatalog = DuelWeaponTestFixtures.catalog(),
                           index: Int = 0,
                           _ change: (inout [String: Any]) -> Void = { _ in }) throws -> DuelWeaponCatalog {
        let rules = catalog.profiles[index].resolvedCombatRules
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(rules)) as? [String: Any])
        change(&object)
        return try DuelWeaponTestFixtures.changing(catalog) { profiles in profiles[index]["combatRules"] = object }
    }

    private func changingWeapon(_ object: inout [String: Any],
                                _ change: (inout [String: Any]) -> Void) {
        var attacks = object["attacks"] as! [[String: Any]]
        let index = attacks.firstIndex { $0["command"] as? String == "weapon" }!
        change(&attacks[index]); object["attacks"] = attacks
    }

    func testOldCatalogDecodesWithoutInventingRecoveredRulesAndPreservesDamage() throws {
        let catalog = DuelWeaponTestFixtures.catalog()
        let decoded = try JSONDecoder().decode(DuelWeaponCatalog.self, from: JSONEncoder().encode(catalog))
        for (index, normal, heavy) in [(0, 80, 145), (1, 105, 190)] {
            let profile = decoded.profiles[index]
            XCTAssertNil(profile.combatRules)
            let rules = profile.resolvedCombatRules
            XCTAssertEqual(rules.basis, .applicationAdaptation)
            XCTAssertNil(rules.sourceSHA256)
            XCTAssertNoThrow(try rules.validate(for: profile))
            let normalRule = try XCTUnwrap(profile.resolvedCombatRule(command: .weapon,
                clipName: XCTUnwrap(profile.clip(command: .weapon)).name))
            let heavyRule = try XCTUnwrap(profile.resolvedCombatRule(command: .heavy,
                clipName: XCTUnwrap(profile.clip(command: .heavy)).name))
            XCTAssertEqual(normalRule.strikes[0].damage, normal)
            XCTAssertEqual(heavyRule.strikes[0].damage, heavy)
            XCTAssertEqual(normalRule.strikes[0].impact.distanceMillimeters, 65)
            XCTAssertEqual(heavyRule.strikes[0].impact.distanceMillimeters, 200)
            XCTAssertEqual(heavyRule.strikes[0].impact.launchVelocityMillimetersPerTick, 0,
                           "A legacy heavy attack is not evidence of a source-game launcher")
        }
    }

    func testShadowRuleBindsToSafeBodyClipAndAerialKickRetainsItsOwnRule() throws {
        let catalog = DuelWeaponTestFixtures.catalog()
        for profile in catalog.profiles {
            let body = try XCTUnwrap(profile.clip(command: .heavy))
            let shadow = try XCTUnwrap(profile.resolvedCombatRule(command: .shadow, clipName: body.name))
            XCTAssertEqual(shadow.strikes[0].startTick, 24)
            XCTAssertEqual(shadow.strikes[0].endTick, profile.isKatana ? 39 : 47)
            XCTAssertTrue(shadow.strikes[0].weaponSides.isEmpty)
            let aerial = try XCTUnwrap(profile.clip(role: "kickJump"))
            XCTAssertNotNil(profile.resolvedCombatRule(command: .kick, clipName: aerial.name))
        }
    }

    func testExplicitMissingOrDuplicateRuleFailsClosedInsteadOfFallingBack() throws {
        let missing = try withRules { object in
            var attacks = object["attacks"] as! [[String: Any]]
            attacks.removeAll { $0["command"] as? String == "weapon" }
            object["attacks"] = attacks
        }
        XCTAssertThrowsError(try missing.validate())
        let profile = missing.profiles[0]
        XCTAssertNil(profile.resolvedCombatRule(command: .weapon, clipName: profile.roles["weapon1"]!))
        XCTAssertNil(DuelGame(weaponCatalog: missing).weaponFight)
        let duplicate = try withRules { object in
            var attacks = object["attacks"] as! [[String: Any]]
            attacks.append(attacks[0]); object["attacks"] = attacks
        }
        XCTAssertThrowsError(try duplicate.validate())
    }

    func testUnknownSidesBadWindowsAndUnboundedValuesCannotEnterSimulation() throws {
        for (key, value) in [("damage", Int.max as Any), ("startTick", -1 as Any),
                             ("endTick", 4001 as Any), ("hitStopTicks", 61 as Any),
                             ("weaponSides", ["left"] as Any)] {
            let invalid = try withRules { object in
                changingWeapon(&object) { attack in
                    var strikes = attack["strikes"] as! [[String: Any]]
                    strikes[0][key] = value; attack["strikes"] = strikes
                }
            }
            XCTAssertThrowsError(try invalid.validate(), key)
            XCTAssertNil(DuelGame(weaponCatalog: invalid).weaponFight, key)
        }
    }

    func testDeclaredSourceConfigurationRequiresVersionReceiptAndDigest() throws {
        for change in [
            { (o: inout [String: Any]) in o["basis"] = "sourceConfiguration" },
            { (o: inout [String: Any]) in o["basis"] = "referenceMeasurement"; o["evidence"] = [] },
            { (o: inout [String: Any]) in o["sourceVersion"] = "" },
            { (o: inout [String: Any]) in o["sourceSHA256"] = String(repeating: "z", count: 64) }
        ] {
            XCTAssertThrowsError(try withRules(DuelWeaponTestFixtures.catalog(), index: 0, change).validate())
        }
        // A receipt is retained, not promoted into a visual/source acceptance claim.
        let declared = try withRules { object in
            object["basis"] = "sourceConfiguration"
            object["sourceSHA256"] = String(repeating: "a", count: 64)
            object["evidence"] = ["synthetic fixture only"]
        }
        XCTAssertNoThrow(try declared.validate())
    }

    func testProvisionalShadowRejectsWindowsOutsideItsSupportedMotionTimeline() throws {
        for index in [0, 1] {
            let invalid = try withRules(index: index) { object in
                var attacks = object["attacks"] as! [[String: Any]]
                let shadow = attacks.firstIndex { $0["command"] as? String == "shadow" }!
                var strikes = attacks[shadow]["strikes"] as! [[String: Any]]
                strikes[0]["startTick"] = 1
                strikes[0]["endTick"] = 10
                attacks[shadow]["strikes"] = strikes
                object["attacks"] = attacks
            }
            XCTAssertThrowsError(try invalid.validate())
            XCTAssertNil(DuelGame(weaponCatalog: invalid).weaponFight)
        }
    }

    func testTwoDistinctStrikeWindowsApplyTheirOwnDamageOnceEach() throws {
        let catalog = try withRules { object in
            changingWeapon(&object) { attack in
                let old = (attack["strikes"] as! [[String: Any]])[0]
                var first = old, second = old
                var noPush = old["impact"] as! [String: Any]
                noPush["distanceMillimeters"] = 0
                first["id"] = 10; first["startTick"] = 3; first["endTick"] = 4; first["damage"] = 9
                second["id"] = 20; second["startTick"] = 8; second["endTick"] = 10; second["damage"] = 17
                first["impact"] = noPush; second["impact"] = noPush
                attack["strikes"] = [first, second]
            }
        }
        XCTAssertNoThrow(try catalog.validate())
        var fight = try DuelWeaponTestFixtures.fight(catalog: catalog)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<40 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.fighters[1].health, 974)
        XCTAssertEqual(fight.landedHits[0], 2)
        XCTAssertEqual(fight.damageDealt[0], 26)
    }

    func testChangedRuleBytesAffectReplayWithUnchangedAssetIdentity() throws {
        let baseline = try withRules()
        let changed = try withRules { object in
            changingWeapon(&object) { attack in
                var strikes = attack["strikes"] as! [[String: Any]]
                strikes[0]["damage"] = 81; attack["strikes"] = strikes
            }
        }
        XCTAssertEqual(baseline.profiles.map(\.sha256), changed.profiles.map(\.sha256))
        XCTAssertNotEqual(try DuelReplayStateEncoding.encodeCatalog(baseline),
                          try DuelReplayStateEncoding.encodeCatalog(changed))
        XCTAssertNotEqual(try DuelReplayStateEncoding.encode(DuelGame(weaponCatalog: baseline)),
                          try DuelReplayStateEncoding.encode(DuelGame(weaponCatalog: changed)))
    }

    func testExplicitOneTickStrikeAtComboAnchorIsResolvedBeforeTheNextStage() throws {
        let base = try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { profiles in
            profiles[0]["comboLinks"] = [["from": "katana_weapon", "to": "katana_weapon2", "sourceFrame": 4]]
        }
        let catalog = try withRules(base) { object in
            changingWeapon(&object) { attack in
                var strikes = attack["strikes"] as! [[String: Any]]
                strikes[0]["startTick"] = 8; strikes[0]["endTick"] = 8
                strikes[0]["damage"] = 9; strikes[0]["hitStopTicks"] = 3
                var impact = strikes[0]["impact"] as! [String: Any]
                impact["distanceMillimeters"] = 0; strikes[0]["impact"] = impact
                attack["strikes"] = strikes
            }
        }
        try catalog.validate()
        for queueDuringHitStop in [false, true] {
            var fight = try DuelWeaponTestFixtures.fight(catalog: catalog)
            fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
            if !queueDuringHitStop { fight.step(.init(weaponCommand: .weapon), opponent: .neutral) }
            for _ in 0..<16 where fight.landedHits[0] == 0 { fight.step(.neutral, opponent: .neutral) }
            XCTAssertEqual(fight.landedHits[0], 1)
            XCTAssertEqual(fight.fighters[1].health, 991)
            XCTAssertEqual(fight.fighters[0].weaponPose?.clip, "katana_weapon")
            XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 8)
            XCTAssertEqual(fight.hitStop, 3)
            if queueDuringHitStop {
                fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
                XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 8)
            }
            while fight.hitStop > 0 { fight.step(.neutral, opponent: .neutral) }
            fight.step(.neutral, opponent: .neutral)
            XCTAssertEqual(fight.fighters[0].weaponPose?.clip, "katana_weapon2")
            XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 9,
                           "The resolved anchor continues forward instead of replaying a stage prefix")
            XCTAssertEqual(fight.landedHits[0], 1, "Shared continuous contact cannot immediately damage again")
        }
    }
}
