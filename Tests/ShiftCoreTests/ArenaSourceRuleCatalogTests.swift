import Foundation
import XCTest
@testable import ShiftCore

final class ArenaSourceRuleCatalogTests: XCTestCase {
    private let sha = String(repeating: "a", count: 64)

    /// Synthetic records exercise the format without putting private tables in
    /// this repository. Every declared schema table is present, even when empty.
    private func fixture() throws -> [String: Any] {
        let rules = ArenaSourceRuleRegistry.referenceSchema
        var columns: [ArenaSourceRuleTable: [String]] = [:]
        var records: [ArenaSourceRuleTable: [[String: Any]]] = [:]
        for table in ArenaSourceRuleTable.allCases {
            var fields: Set<String> = ["Name", "Type", "Disabled", "ItemName", "MetaType", "Values", "Number", "BadNumber", "Flag", "Float", "Empty"]
            for rule in rules where rule.sourceTable == table {
                fields.insert(rule.field)
                if let condition = rule.condition { fields.insert(condition.field) }
            }
            fields.formUnion(ArenaSourceRuleRegistry.selectorSchema[table] ?? [])
            columns[table] = ["Name"] + fields.subtracting(["Name"]).sorted()
            records[table] = []
        }
        func add(_ table: ArenaSourceRuleTable, _ id: String, _ rows: [[String: String]]) {
            let next = 3 + (records[table] ?? []).reduce(0) { $0 + (($1["rows"] as? [[String: Any]])?.count ?? 0) }
            let values: [[String: Any]] = rows.enumerated().map { offset, row in
                ["line": next + offset, "values": columns[table]!.map { name in name == "Name" ? (offset == 0 ? id : "") : row[name] ?? "" }]
            }
            records[table, default: []].append(["id": id, "rows": values])
        }
        add(.characters, "HeroA", [["Type": "Hero", "ItemName": "hero_a", "WeaponSkill": "SkillA", "UltimateSkill": "SkillB", "Number": "27", "Flag": "TRUE", "Float": "2.5", "BadNumber": "nan"]])
        add(.characters, "HeroAForm", [["Type": "Hero", "WeaponSkill": "SkillA", "UltimateSkill": "SkillB"]])
        add(.characters, "DisabledHero", [["Type": "Hero", "Disabled": "true", "ItemName": "disabled_hero", "WeaponSkill": "SkillA", "UltimateSkill": "SkillB"]])
        add(.skills, "SkillA", [["SecondarySkill": "SkillB", "Projectiles": "ProjectileA"]])
        add(.skills, "SkillB", [["SecondarySkill": "SkillA", "AreaEffectObject": "BurstA"]])
        add(.projectiles, "ProjectileA", [["SpawnAreaEffectObject": "MissingArea"]])
        add(.areas, "BurstA", [["BulletExplosionItem": "MineA"]])
        add(.items, "MineA", [[:]])
        add(.components, "ComponentA", [["Values": "10", "Skills": "SkillA"], ["Values": "20", "Skills": "SkillB"]])
        add(.accessories, "AccessoryA", [["Skill": "SkillB", "CustomObject": "UnknownNativeValue"]])
        add(.traits, "TraitA", [["Skill": "SkillA"]])
        add(.cards, "UnlockA", [["Type": "unlock", "MetaType": "0", "Target": "HeroA"]])
        add(.cards, "StarA", [["Type": "trait_star_power", "MetaType": "4", "Target": "HeroA", "Traits": "TraitA"]])
        add(.cards, "GadgetA", [["Type": "accessory", "MetaType": "5", "Target": "HeroA", "Skill": "AccessoryA"]])
        add(.cards, "OverchargeA", [["Type": "overcharge_default", "MetaType": "6", "Target": "HeroA"]])
        add(.cards, "DisabledStar", [["Type": "trait_star_power", "MetaType": "4", "Target": "HeroA", "Disabled": "true"]])

        let tables: [[String: Any]] = ArenaSourceRuleTable.allCases.sorted { $0.rawValue < $1.rawValue }.map { table in
            ["id": table.rawValue, "sourcePath": "Payload/NB.app/res/csv_logic/\(table.rawValue).csv", "sourceSHA256": sha,
             "sourceBytes": 100, "columns": columns[table]!.map { ["name": $0, "type": "string"] }, "records": records[table]!]
        }
        var references: [[String: Any]] = []
        for rule in rules {
            let fields = columns[rule.sourceTable]!
            let fieldIndex = fields.firstIndex(of: rule.field)!
            for record in records[rule.sourceTable]! {
                let rows = record["rows"] as! [[String: Any]]
                if let condition = rule.condition {
                    let conditionIndex = fields.firstIndex(of: condition.field)!
                    let values = rows.map { ($0["values"] as! [String])[conditionIndex] }
                    if Set(values).isDisjoint(with: condition.values) { continue }
                }
                for row in rows {
                    let raw = (row["values"] as! [String])[fieldIndex]
                    for (index, name) in raw.components(separatedBy: ";").enumerated() where !name.isEmpty {
                        let present = records[rule.targetTable]!.contains { ($0["id"] as? String) == name }
                        references.append(["ruleID": rule.id, "source": ["table": rule.sourceTable.rawValue, "id": record["id"] as! String],
                                           "line": row["line"]!, "field": rule.field, "tokenIndex": index,
                                           "target": ["table": rule.targetTable.rawValue, "id": name], "resolution": present ? "present" : "source_missing"])
                    }
                }
            }
        }
        return ["schemaVersion": 1, "artifactKind": "source_rule_registry", "executionPolicy": "definitions_only", "sourceIPASHA256": sha,
                "tables": tables, "referenceRules": try JSONSerialization.jsonObject(with: JSONEncoder().encode(rules)), "references": references,
                "unresolvedSelectors": [["source": ["table": "accessories", "id": "AccessoryA"], "line": 3,
                                           "field": "CustomObject", "tokenIndex": 0, "value": "UnknownNativeValue", "candidates": []]],
                "roster": ["enabledHeroIDs": ["HeroA", "HeroAForm"], "independentHeroIDs": ["HeroA"], "formHeroIDs": ["HeroAForm"],
                           "disabledHeroIDs": ["DisabledHero"], "associatedCardIDs": ["UnlockA", "StarA", "GadgetA", "OverchargeA", "DisabledStar"],
                           "transformConfigIDs": [], "cardGroups": ["unlocks": ["UnlockA"], "starPowers": ["StarA"], "gadgets": ["GadgetA"], "overcharges": ["OverchargeA"]]]]
    }

    private func read(_ value: [String: Any]) throws -> ArenaSourceRuleRegistry {
        try ArenaSourceRuleRegistry(data: JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }

    func testContinuationRowsRemainOrderedAndCannotMasqueradeAsScalar() throws {
        let registry = try read(fixture())
        let component = try XCTUnwrap(registry.record(table: .components, id: "ComponentA"))
        XCTAssertEqual(component.values("Values").map(\.value), ["10", "20"])
        XCTAssertEqual(component.values("Values").map(\.line), [3, 4])
        XCTAssertEqual(component.cell("Values", line: 4), "20")
        XCTAssertThrowsError(try component.integer("Values")) { error in
            XCTAssertEqual(error as? ArenaSourceRuleError, .ambiguousField(component.id, "Values"))
        }
        XCTAssertEqual(registry.references(from: component.id).map(\.target.id), ["SkillA", "SkillB"])
    }

    func testTypedReadsPreserveEmptyAndRejectInvalidNumbers() throws {
        let hero = try XCTUnwrap(try read(fixture()).hero("HeroA"))
        XCTAssertEqual(try hero.integer("Number"), 27)
        XCTAssertEqual(try hero.boolean("Flag"), true)
        XCTAssertEqual(try hero.decimal("Float"), 2.5)
        XCTAssertNil(try hero.string("Empty"))
        XCTAssertEqual(hero.values("Empty", includeEmpty: true).map(\.value), [""])
        XCTAssertNil(hero.cell("UnknownColumn", line: 3))
        XCTAssertThrowsError(try hero.integer("BadNumber"))
        XCTAssertThrowsError(try hero.decimal("BadNumber"))
    }

    func testConditionalCardTargetsAccessoryWithoutCallingItPlayable() throws {
        let registry = try read(fixture())
        XCTAssertEqual(registry.catalog.executionPolicy, "definitions_only")
        let gadget = try XCTUnwrap(registry.cards(forHeroID: "HeroA", category: .gadget).first)
        let link = try XCTUnwrap(registry.references(from: gadget.id).first { $0.field == "Skill" })
        XCTAssertEqual(link.target, .init(table: .accessories, id: "AccessoryA"))
        XCTAssertEqual(link.resolution, .present)
        XCTAssertEqual(registry.cards(forHeroID: "HeroA", category: .starPower).map(\.id.id), ["StarA"])
        XCTAssertEqual(registry.cards(forHeroID: "HeroA", category: .overcharge).map(\.id.id), ["OverchargeA"])
    }

    func testDisabledDefinitionsRemainAvailableAndCardsHideThemByDefault() throws {
        let registry = try read(fixture())
        XCTAssertNotNil(registry.hero("DisabledHero"))
        XCTAssertEqual(registry.catalog.roster.disabledHeroIDs, ["DisabledHero"])
        XCTAssertNotNil(registry.record(table: .cards, id: "DisabledStar"))
        XCTAssertEqual(registry.cards(forHeroID: "HeroA", category: .starPower, includeDisabled: true).map(\.id.id), ["StarA", "DisabledStar"])
    }

    func testClosureTerminatesCyclesAndSeparatesSourceGapsFromNativeSelectors() throws {
        let registry = try read(fixture())
        let root = ArenaSourceRuleID(table: .characters, id: "HeroA")
        let unknown = ArenaSourceRuleID(table: .characters, id: "NotProvided")
        let closure = registry.dependencyClosure(from: [root, unknown, .init(table: .accessories, id: "AccessoryA")])
        XCTAssertEqual(Set(closure.definitions).count, closure.definitions.count)
        XCTAssertTrue(closure.definitions.contains(.init(table: .skills, id: "SkillA")))
        XCTAssertTrue(closure.definitions.contains(.init(table: .items, id: "MineA")))
        XCTAssertEqual(closure.missingRoots, [unknown])
        XCTAssertEqual(closure.missingReferences.map(\.target.id), ["MissingArea"])
        XCTAssertEqual(closure.unresolvedSelectors.map(\.value), ["UnknownNativeValue"])
        XCTAssertEqual(registry.availability(of: root), .presentDefinition)
        XCTAssertEqual(registry.availability(of: unknown), .sourceMissing)
        XCTAssertFalse(registry.sourceMissingReferences.contains { $0.target.id == "UnknownNativeValue" })
    }

    func testItemExplosionNeverInventsAnEmptyProjectileReference() throws {
        let registry = try read(fixture())
        let links = registry.references(from: .init(table: .areas, id: "BurstA"))
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.field, "BulletExplosionItem")
        XCTAssertEqual(links.first?.target, .init(table: .items, id: "MineA"))
        XCTAssertFalse(registry.catalog.references.contains { $0.target.id.isEmpty })
    }

    func testRejectsDeletedDuplicatedOrFalsifiedReferenceEvidence() throws {
        let original = try fixture()
        for mutation in 0..<4 {
            var value = original
            var refs = value["references"] as! [[String: Any]]
            if mutation == 0 { refs.removeLast() }
            if mutation == 1 { refs.append(refs[0]) }
            if mutation == 2 { refs[0]["line"] = 999 }
            if mutation == 3 { refs[0]["resolution"] = "source_missing" }
            value["references"] = refs
            XCTAssertThrowsError(try read(value), "Mutation \(mutation) was accepted")
        }
    }

    func testRejectsOmittedTableRepeatedRecordAndAlteredSourcePath() throws {
        let original = try fixture()
        for mutation in 0..<3 {
            var value = original
            var tables = value["tables"] as! [[String: Any]]
            let i = tables.firstIndex { ($0["id"] as? String) == "characters" }!
            if mutation == 0 { tables.removeLast() }
            if mutation == 1 {
                var records = tables[i]["records"] as! [[String: Any]]; records.append(records[0]); tables[i]["records"] = records
            }
            if mutation == 2 { tables[i]["sourcePath"] = "../../outside.csv" }
            value["tables"] = tables
            XCTAssertThrowsError(try read(value), "Mutation \(mutation) was accepted")
        }
    }

    func testRejectsWeakenedReferenceRulesAndExecutionClaims() throws {
        let original = try fixture()
        for mutation in 0..<3 {
            var value = original
            if mutation == 0 { value["executionPolicy"] = "all_heroes_playable" }
            if mutation == 1 { value["schemaVersion"] = 2 }
            if mutation == 2 { var rules = value["referenceRules"] as! [[String: Any]]; rules.removeLast(); value["referenceRules"] = rules }
            XCTAssertThrowsError(try read(value), "Mutation \(mutation) was accepted")
        }
    }

    func testRejectsForgedRosterAndUnresolvedSelectorCandidates() throws {
        let original = try fixture()
        var wrongRoster = original
        var roster = wrongRoster["roster"] as! [String: Any]; roster["independentHeroIDs"] = ["HeroA", "HeroAForm"]; wrongRoster["roster"] = roster
        XCTAssertThrowsError(try read(wrongRoster))
        var wrongSelector = original
        var selectors = wrongSelector["unresolvedSelectors"] as! [[String: Any]]
        selectors[0]["candidates"] = [["table": "skills", "id": "SkillA"]]
        wrongSelector["unresolvedSelectors"] = selectors
        XCTAssertThrowsError(try read(wrongSelector))
    }

    func testRejectsInvalidSourceRowsAndOverlargeDecode() throws {
        var value = try fixture()
        var tables = value["tables"] as! [[String: Any]]
        let i = tables.firstIndex { ($0["id"] as? String) == "components_logic" }!
        var records = tables[i]["records"] as! [[String: Any]]
        var rows = records[0]["rows"] as! [[String: Any]]; rows[1]["line"] = 3
        records[0]["rows"] = rows; tables[i]["records"] = records; value["tables"] = tables
        XCTAssertThrowsError(try read(value))
        XCTAssertThrowsError(try ArenaSourceRuleRegistry(data: Data(repeating: 32, count: ArenaSourceRuleCatalog.maximumBytes + 1)))
    }

    #if ARENA_PRIVATE_RULE_CATALOG_VALIDATION
    func testActualPrivateCatalogPreservesAllDefinitionsAndCompleteHeroCardGroups() throws {
        guard let path = ProcessInfo.processInfo.environment["ARENA_SOURCE_RULE_CATALOG"] else {
            throw ArenaSourceRuleError.invalid("Private rule validation requires ARENA_SOURCE_RULE_CATALOG")
        }
        let registry = try ArenaSourceRuleRegistry(data: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(registry.catalog.tables.count, 34)
        XCTAssertEqual(registry.catalog.tables.reduce(0) { $0 + $1.records.count }, 7_999)
        XCTAssertEqual(registry.catalog.tables.reduce(0) { $0 + $1.records.reduce(0) { $0 + $1.rows.count } }, 8_454)
        XCTAssertEqual(registry.catalog.roster.independentHeroIDs.count, 108)
        XCTAssertEqual(registry.catalog.roster.enabledHeroIDs.count, 118)
        XCTAssertEqual(registry.catalog.roster.formHeroIDs.count, 10)
        XCTAssertEqual(registry.catalog.roster.disabledHeroIDs.count, 6)
        XCTAssertEqual(registry.catalog.roster.cardGroups.starPowers.count, 216)
        XCTAssertEqual(registry.catalog.roster.cardGroups.gadgets.count, 216)
        XCTAssertEqual(registry.catalog.roster.cardGroups.overcharges.count, 106)
        XCTAssertEqual(registry.cards(forHeroID: "ShotgunGirl", category: .gadget).count, 2)
        XCTAssertEqual(registry.cards(forHeroID: "ShotgunGirl", category: .starPower).count, 2)
        let tick = registry.references(from: .init(table: .areas, id: "ClusterBombExplosion"))
        XCTAssertTrue(tick.contains { $0.field == "BulletExplosionItem" && $0.target == .init(table: .items, id: "ClusterMine") && $0.resolution == .present })
        XCTAssertFalse(tick.contains { $0.field == "BulletExplosionBullet" })
        XCTAssertTrue(registry.sourceMissingReferences.contains { $0.target == .init(table: .projectiles, id: "Godzilla1UltiProjectile") })
        XCTAssertTrue(registry.sourceMissingReferences.contains { $0.target == .init(table: .areas, id: "FuryWarningCrit") })
        let component = try XCTUnwrap(registry.record(table: .components, id: "Brawler_MechaDude"))
        XCTAssertEqual(component.values("Values").map(\.value), ["0", "120", "0", "0"])
        XCTAssertThrowsError(try component.integer("Values"))
        let roots = registry.catalog.roster.enabledHeroIDs.map { ArenaSourceRuleID(table: .characters, id: $0) }
            + registry.catalog.roster.associatedCardIDs.map { ArenaSourceRuleID(table: .cards, id: $0) }
            + registry.catalog.roster.transformConfigIDs.map { ArenaSourceRuleID(table: .transforms, id: $0) }
        let closure = registry.dependencyClosure(from: roots)
        XCTAssertTrue(closure.missingRoots.isEmpty)
        XCTAssertEqual(closure.definitions.filter { $0.table == .characters }.count, 199)
        XCTAssertEqual(closure.missingReferences.count, 19)
    }
    #endif
}
