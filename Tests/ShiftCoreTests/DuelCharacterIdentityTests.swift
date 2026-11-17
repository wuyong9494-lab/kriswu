import XCTest
@testable import ShiftCore

final class DuelCharacterIdentityTests: XCTestCase {
    private typealias Choice = DuelMultiplayerSelection.Choice
    private struct Expected {
        let identity: DuelCharacterIdentity
        let hero: DuelGame.Hero
        let profileID, setID, role, name, head, body, weaponTitle: String
        let weapons: [String]
    }
    private let expected: [Expected] = [
        .init(identity: .blackBlades, hero: .ember, profileID: "sun_triad", setID: "H17",
            role: "黑色双刀", name: "孙登", head: "Sun_Personal_Head", body: "arm__prc_43",
            weaponTitle: "黑色双刀", weapons: ["wpn__ninjato_01_06"]),
        .init(identity: .serpent, hero: .liu, profileID: "liu_serpent", setID: "D13",
            role: "蛇王", name: "刘泉纬", head: "Liu_Personal_Head", body: "arm__agl_41",
            weaponTitle: "毒牙双钩", weapons: ["wpn__shuangou_01_04"]),
        .init(identity: .erlang, hero: .wuYong, profileID: "wuyong_erlang", setID: "D15",
            role: "二郎神", name: "吴庸", head: "WuYong_Personal_Head", body: "arm__agl_44",
            weaponTitle: "天律长枪", weapons: ["wpn__agl_spear_01_01"]),
        .init(identity: .founder, hero: .gale, profileID: "xuxiao_founder", setID: "D20",
            role: "嬴政", name: "徐骁", head: "XuXiao_Personal_Head", body: "arm__agl_49",
            weaponTitle: "帝国御拳", weapons: ["wpn__imperial_gloves_01_01", "wpn__imperial_gloves_01_01a"])
    ]

    /// Metadata predicate fixtures only. Their deliberately synthetic tracks,
    /// bytes and missing source bindings cannot prove resource acceptance.
    private func profile(_ row: Expected, profileID: String? = nil,
                         hero: DuelGame.Hero? = nil, body: String? = nil,
                         weapon: String? = nil) -> DuelWeaponProfile {
        let template = DuelWeaponTestFixtures.profile(hero: row.hero == .ember ? .ember : .liu,
            stroke: .straight, aerialKick: true)
        return .init(id: profileID ?? row.profileID, hero: hero ?? row.hero,
            faction: "Synthetic", resourceName: "Synthetic_Identity_Contract",
            bytes: 512, sha256: String(repeating: "e", count: 64),
            bodyID: body ?? row.body, weaponID: weapon ?? row.weapons[0],
            activeWeaponSides: template.activeWeaponSides, roles: template.roles, clips: template.clips)
    }

    /// Reuse the existing, explicitly synthetic interpreter fixtures. Only
    /// their equipment metadata is set to the authenticated source identity
    /// vocabulary; no original motion, model or D20 rule is manufactured.
    private func structurallyValidIntendedCatalog() throws -> DuelWeaponCatalog {
        let triadFixture = try DuelTriadFightFixture.catalog()
        let triadCatalog = try DuelWeaponTestFixtures.changing(triadFixture) { profiles in
            profiles[0]["bodyID"] = "arm__prc_43"
            profiles[0]["weaponID"] = "wpn__ninjato_01_06"
        }
        let founderCatalog = try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.founderCatalog()) { profiles in
            profiles[1]["bodyID"] = "arm__agl_49"
            profiles[1]["weaponID"] = "wpn__imperial_gloves_01_01"
        }
        let triad = try XCTUnwrap(triadCatalog.profile(for: .ember))
        let founder = try XCTUnwrap(founderCatalog.profile(for: .gale))
        return .init(schemaVersion: 1, previewFramesPerSecond: 30, profiles: [triad, founder])
    }

    func testFourFixedPersonSetRoleAndHeadBindings() {
        XCTAssertEqual(DuelCharacterIdentity.allCases.count, 4)
        XCTAssertEqual(Set(DuelCharacterIdentity.allCases.map(\.rawValue)), Set(expected.map(\.profileID)))
        for row in expected {
            XCTAssertEqual(row.identity.hero, row.hero)
            XCTAssertEqual(row.identity.rawValue, row.profileID)
            XCTAssertEqual(row.identity.sourceSetID, row.setID)
            XCTAssertEqual(row.identity.roleName, row.role)
            XCTAssertEqual(row.identity.title, row.name)
            XCTAssertEqual(row.identity.personalHeadNode, row.head)
            XCTAssertEqual(DuelCharacterIdentity.intended(for: row.hero), row.identity)
            XCTAssertEqual(row.hero.characterIdentity, row.identity)
            XCTAssertEqual(DuelCharacterIdentity(hero: row.hero, profileID: row.profileID), row.identity)
        }
    }

    func testFourBySevenChoiceMatrixHasExactlyFourIntendedPairs() {
        XCTAssertEqual(DuelGame.Hero.allCases.count, 4)
        XCTAssertEqual(DuelMultiplayerSelection.Weapon.allCases.count, 7)
        var intendedCount = 0
        for hero in DuelGame.Hero.allCases {
            for weapon in DuelMultiplayerSelection.Weapon.allCases {
                let row = expected.first { $0.hero == hero && $0.profileID == weapon.rawValue }
                let choice = Choice(hero: hero, weapon: weapon)
                XCTAssertEqual(choice.isIntendedCharacter, row != nil, "\(hero)/\(weapon)")
                XCTAssertEqual(DuelCharacterIdentity(hero: hero, profileID: weapon.rawValue), row?.identity)
                if choice.isIntendedCharacter {
                    intendedCount += 1
                    XCTAssertTrue(choice.isValid)
                }
            }
        }
        XCTAssertEqual(intendedCount, 4)
    }

    func testExactSourceEquipmentRejectsSwapsPrefixesAndUnknownIDs() {
        for row in expected {
            for weapon in row.weapons {
                XCTAssertTrue(row.identity.matches(hero: row.hero, profileID: row.profileID,
                    bodyID: row.body, weaponID: weapon))
                for body in ["", "unreviewed_body", "Top100/" + row.body, row.body.uppercased()] {
                    XCTAssertFalse(row.identity.matches(hero: row.hero, profileID: row.profileID,
                        bodyID: body, weaponID: weapon))
                }
                for other in expected where other.identity != row.identity {
                    XCTAssertFalse(row.identity.matches(hero: row.hero, profileID: row.profileID,
                        bodyID: other.body, weaponID: weapon))
                    XCTAssertFalse(row.identity.matches(hero: row.hero, profileID: row.profileID,
                        bodyID: row.body, weaponID: other.weapons[0]))
                    XCTAssertFalse(row.identity.matches(hero: other.hero, profileID: row.profileID,
                        bodyID: row.body, weaponID: weapon))
                    XCTAssertFalse(row.identity.matches(hero: row.hero, profileID: other.profileID,
                        bodyID: row.body, weaponID: weapon))
                }
            }
            for weapon in ["", "unreviewed_weapon", "Top100/" + row.weapons[0]] {
                XCTAssertFalse(row.identity.matches(hero: row.hero, profileID: row.profileID,
                    bodyID: row.body, weaponID: weapon))
            }
            XCTAssertNil(DuelCharacterIdentity(hero: row.hero, profileID: row.profileID + "_renamed"))
        }
    }

    func testFounderAcceptsBothOriginalGloveAlternativesAndNoSubstitute() throws {
        let founder = try XCTUnwrap(expected.first { $0.identity == .founder })
        for weapon in ["wpn__imperial_gloves_01_01", "wpn__imperial_gloves_01_01a"] {
            XCTAssertTrue(profile(founder, weapon: weapon).isIntendedCharacter)
        }
        for weapon in ["wpn__imperial_gloves_01", "wpn__imperial_gloves_01_01b",
                       "wpn__agl_spear_01_01", "wpn__hammers_01_01"] {
            XCTAssertFalse(profile(founder, weapon: weapon).isIntendedCharacter)
        }
        XCTAssertFalse(profile(founder, body: "arm__str_03").isIntendedCharacter)
    }

    func testLegacyIDsRemainRejectedWithTheRightPersonAndSourceEquipment() throws {
        let sun = try XCTUnwrap(expected.first { $0.identity == .blackBlades })
        let liu = try XCTUnwrap(expected.first { $0.identity == .serpent })
        for (row, oldID, choice, weaponTitle) in [(sun, "sun_katana", Choice.sun, "武士刀"),
                                                 (liu, "liu_hammers", Choice.liu, "双锤"),
                                                 (liu, "liu_pangu", Choice.liuPangu, "盘古大斧")] {
            let labelled = profile(row, profileID: oldID)
            XCTAssertEqual(labelled.hero.name, row.name)
            XCTAssertEqual(labelled.title, row.name)
            XCTAssertEqual(labelled.weaponTitle, weaponTitle)
            XCTAssertEqual(labelled.hero.characterIdentity.roleName, row.role)
            XCTAssertEqual(labelled.bodyID, row.body)
            XCTAssertEqual(labelled.weaponID, row.weapons[0])
            XCTAssertNil(labelled.characterIdentity)
            XCTAssertFalse(labelled.isIntendedCharacter)
            XCTAssertTrue(choice.isValid, "Legacy transport compatibility is retained")
            XCTAssertFalse(choice.isIntendedCharacter)
        }
    }

    func testCanonicalDisplayTitlesContainOnlyPersonalNamesAndKeepWeaponMetadata() {
        for row in expected {
            let value = profile(row)
            XCTAssertEqual(value.characterIdentity, row.identity)
            XCTAssertTrue(value.isIntendedCharacter)
            XCTAssertEqual(value.title, row.name)
            XCTAssertFalse(value.title.contains(row.role))
            XCTAssertFalse(value.title.contains(row.setID))
            XCTAssertEqual(value.weaponTitle, row.weaponTitle)
        }
        let triad = expected[0]
        XCTAssertTrue(profile(triad).isTriad)
        XCTAssertFalse(profile(triad, hero: .liu).isTriad)
        XCTAssertNil(profile(triad, hero: .liu).characterIdentity)
    }

    func testAvailableIntendedRequiresBothValidatedProfilesAndPreservesSeatOrder() throws {
        let catalog = try structurallyValidIntendedCatalog()
        XCTAssertNoThrow(try catalog.validate())
        XCTAssertTrue(catalog.profiles.allSatisfy(\.isIntendedCharacter))
        XCTAssertEqual(Choice.availableIntended(in: catalog), [.sunTriad, .xuXiao])
        let reversed = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
            profiles: Array(catalog.profiles.reversed()))
        XCTAssertEqual(Choice.availableIntended(in: reversed), [.xuXiao, .sunTriad])
        let missingRules = try DuelWeaponTestFixtures.changing(catalog) { profiles in
            profiles[1].removeValue(forKey: "combatRules")
        }
        XCTAssertTrue(missingRules.profiles.allSatisfy(\.isIntendedCharacter))
        XCTAssertThrowsError(try missingRules.validate())
        XCTAssertEqual(Choice.availableIntended(in: missingRules), [])
        let partial = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
            profiles: [catalog.profiles[0]])
        XCTAssertEqual(Choice.availableIntended(in: partial), [])
    }

    func testAvailableIntendedRejectsMixedLegacyOrMismatchedEquipmentWithoutPartialChoices() throws {
        let catalog = try structurallyValidIntendedCatalog()
        let legacyLiu = try XCTUnwrap(DuelWeaponTestFixtures.catalog().profile(for: .liu))
        let mixed = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
            profiles: [catalog.profiles[0], legacyLiu])
        XCTAssertNoThrow(try mixed.validate())
        XCTAssertEqual(Choice.available(in: mixed), [.sunTriad, .liu])
        XCTAssertEqual(Choice.availableIntended(in: mixed), [])
        for key in ["bodyID", "weaponID"] {
            let mismatch = try DuelWeaponTestFixtures.changing(catalog) { profiles in
                profiles[1][key] = "unreviewed_" + key
            }
            XCTAssertNoThrow(try mismatch.validate(), "Generic catalog validation stays compatible")
            XCTAssertEqual(Choice.available(in: mismatch), [.sunTriad, .xuXiao])
            XCTAssertEqual(Choice.availableIntended(in: mismatch), [])
        }
    }

    func testExistingHeroWeaponWireValuesAndLegacyCatalogStayCompatible() throws {
        XCTAssertEqual(DuelGame.Hero.allCases.map(\.rawValue), ["ember", "gale", "liu", "wuyong_erlang"])
        XCTAssertEqual(DuelMultiplayerSelection.Weapon.allCases.map(\.rawValue),
            ["sun_katana", "sun_triad", "liu_hammers", "liu_pangu", "liu_serpent", "wuyong_erlang", "xuxiao_founder"])
        XCTAssertEqual(DuelMultiplayerSelection.protocolVersion, 1)
        let wires: [(String, Choice)] = [
            (#"{"hero":"ember","weapon":"sun_katana"}"#, .sun),
            (#"{"hero":"liu","weapon":"liu_hammers"}"#, .liu),
            (#"{"hero":"gale","weapon":"xuxiao_founder"}"#, .xuXiao),
            (#"{"hero":"wuyong_erlang","weapon":"wuyong_erlang"}"#, .wuYong)
        ]
        for (wire, choice) in wires {
            XCTAssertEqual(try JSONDecoder().decode(Choice.self, from: Data(wire.utf8)), choice)
            XCTAssertEqual(try JSONDecoder().decode(Choice.self, from: JSONEncoder().encode(choice)), choice)
        }
        let legacy = DuelWeaponTestFixtures.catalog()
        XCTAssertNoThrow(try legacy.validate())
        XCTAssertEqual(legacy.profiles.map(\.title), ["孙登", "刘泉纬"])
        XCTAssertEqual(legacy.profiles.map(\.weaponTitle), ["武士刀", "双锤"])
        XCTAssertEqual(Choice.available(in: legacy), [.sun, .liu])
        XCTAssertEqual(Choice.availableIntended(in: legacy), [])
    }
}
