import Foundation

/// Gameplay data tables from the supplied client. This is a definition registry,
/// not a native-rule interpreter and never a replacement for `canPlay`.
public enum ArenaSourceRuleTable: String, Codable, CaseIterable, Hashable, Sendable {
    case characters, skills, traits, actions, conditions, cards, accessories, buddies, carryables, globals, bosses
    case projectiles = "projectiles_logic"
    case areas = "area_effects_logic"
    case statuses = "status_effects_logic"
    case components = "components_logic"
    case items = "items_logic"
    case transforms = "transform_hero_confs"
    case gearBoosts = "gear_boosts"
    case gearLevels = "gear_levels"
    case gearRarities = "gear_rarities"
    case companionTriggers = "companion_triggers"
    case rogueliteCards = "roguelite_cards"
    case rogueliteDecks = "roguelite_decks"
    case rogueliteSkillFamilies = "roguelite_skill_families"
    case swarmExperienceLevels = "swarm_exp_levels"
    case enumeratedIDLists = "enumerated_id_lists"
    case eventModifiers = "event_modifiers"
    case bossQuiz = "boss_quiz"
    case bossQuizOdd = "boss_quiz_odd"
    case timeSpawns = "time_spawns"
    case timeSpawnStages = "time_spawn_stages_setup"
    case gameModeVariations = "game_mode_variations"
    case brawlerRarities = "brawler_rarities"
    case classArchetypes = "class_archetypes"
}

public struct ArenaSourceRuleID: Codable, Hashable, Sendable {
    public let table: ArenaSourceRuleTable
    public let id: String
    public init(table: ArenaSourceRuleTable, id: String) { self.table = table; self.id = id }
}

public struct ArenaSourceRuleFieldValue: Equatable, Sendable {
    public let line: Int
    public let value: String
}

public enum ArenaSourceRuleError: Error, Equatable, LocalizedError {
    case invalid(String)
    case ambiguousField(ArenaSourceRuleID, String)
    case invalidScalar(ArenaSourceRuleID, String, String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let detail): return "原资源规则目录无效：\(detail)"
        case .ambiguousField(let id, let field): return "\(id.table.rawValue).\(id.id).\(field) 包含多个源行，需要明确的选择规则"
        case .invalidScalar(let id, let field, _): return "\(id.table.rawValue).\(id.id).\(field) 的原始值无法按请求类型读取"
        }
    }
}

public struct ArenaSourceRuleCatalog: Codable, Sendable {
    public struct Column: Codable, Equatable, Sendable { public let name: String; public let type: String }
    public struct Row: Codable, Equatable, Sendable {
        /// Physical starting line in the original CSV, including its two headers.
        public let line: Int
        /// Original cells, including empty cells. Short trailing rows stay short.
        public let values: [String]
    }
    public struct Record: Codable, Equatable, Sendable { public let id: String; public let rows: [Row] }
    public struct Table: Codable, Sendable {
        public let id: ArenaSourceRuleTable
        public let sourcePath: String
        public let sourceSHA256: String
        public let sourceBytes: Int
        public let columns: [Column]
        public let records: [Record]
    }
    public struct ReferenceRule: Codable, Equatable, Sendable {
        public struct Condition: Codable, Equatable, Sendable { public let field: String; public let values: [String] }
        public let id: String
        public let sourceTable: ArenaSourceRuleTable
        public let field: String
        public let targetTable: ArenaSourceRuleTable
        public let separator: String
        public let condition: Condition?
        public let ignoredTokens: [String]?
    }
    public struct Reference: Codable, Hashable, Sendable {
        public enum Resolution: String, Codable, Sendable { case present; case sourceMissing = "source_missing" }
        public let ruleID: String
        public let source: ArenaSourceRuleID
        public let line: Int
        public let field: String
        public let tokenIndex: Int
        public let target: ArenaSourceRuleID
        /// A source definition being present does not establish runtime support.
        public let resolution: Resolution
    }
    public struct UnresolvedSelector: Codable, Equatable, Sendable {
        public let source: ArenaSourceRuleID
        public let line: Int
        public let field: String
        public let tokenIndex: Int
        public let value: String
        /// Exact name matches only. Native selection semantics are not inferred.
        public let candidates: [ArenaSourceRuleID]
    }
    public struct Roster: Codable, Equatable, Sendable {
        public struct CardGroups: Codable, Equatable, Sendable {
            public let unlocks: [String]
            public let starPowers: [String]
            public let gadgets: [String]
            public let overcharges: [String]
        }
        public let enabledHeroIDs: [String]
        public let independentHeroIDs: [String]
        public let formHeroIDs: [String]
        public let disabledHeroIDs: [String]
        /// Includes disabled cards so source definitions never disappear.
        public let associatedCardIDs: [String]
        public let transformConfigIDs: [String]
        public let cardGroups: CardGroups
    }

    public let schemaVersion: Int
    public let artifactKind: String
    public let executionPolicy: String
    public let sourceIPASHA256: String
    public let tables: [Table]
    public let referenceRules: [ReferenceRule]
    public let references: [Reference]
    public let unresolvedSelectors: [UnresolvedSelector]
    public let roster: Roster

    public static let maximumBytes = 32 * 1024 * 1024
    public static let maximumRecords = 20_000
    public static let maximumRows = 100_000
    public static let maximumReferences = 250_000
    public static let maximumCells = 4_000_000

    /// Use the bounded decoder for untrusted pack data. Archive digest checking
    /// remains the resource pack loader's responsibility.
    public static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumBytes else { throw ArenaSourceRuleError.invalid("目录字节数") }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    public func validate() throws { _ = try ArenaSourceRuleRegistry(catalog: self) }
}

/// A view preserves every source occurrence. Scalar readers reject continuation
/// selections, including repeated identical values, instead of choosing row one.
public struct ArenaSourceRuleRecordView: Sendable {
    public let id: ArenaSourceRuleID
    public let record: ArenaSourceRuleCatalog.Record
    public let columns: [ArenaSourceRuleCatalog.Column]

    public var sourceLine: Int { record.rows.first?.line ?? 0 }
    public func cell(_ field: String, line: Int) -> String? {
        guard let column = columns.firstIndex(where: { $0.name == field }),
              let row = record.rows.first(where: { $0.line == line }), column < row.values.count else { return nil }
        return row.values[column]
    }
    public func values(_ field: String, includeEmpty: Bool = false) -> [ArenaSourceRuleFieldValue] {
        guard let column = columns.firstIndex(where: { $0.name == field }) else { return [] }
        return record.rows.compactMap { row in
            guard column < row.values.count, includeEmpty || !row.values[column].isEmpty else { return nil }
            return ArenaSourceRuleFieldValue(line: row.line, value: row.values[column])
        }
    }
    public func string(_ field: String) throws -> String? {
        let found = values(field)
        guard found.count <= 1 else { throw ArenaSourceRuleError.ambiguousField(id, field) }
        return found.first?.value
    }
    public func integer(_ field: String) throws -> Int? {
        guard let raw = try string(field) else { return nil }
        guard let value = Int(raw) else { throw ArenaSourceRuleError.invalidScalar(id, field, raw) }
        return value
    }
    public func decimal(_ field: String) throws -> Double? {
        guard let raw = try string(field) else { return nil }
        guard let value = Double(raw), value.isFinite else { throw ArenaSourceRuleError.invalidScalar(id, field, raw) }
        return value
    }
    public func boolean(_ field: String) throws -> Bool? {
        guard let raw = try string(field) else { return nil }
        switch raw.lowercased() {
        case "true", "1": return true
        case "false", "0": return false
        default: throw ArenaSourceRuleError.invalidScalar(id, field, raw)
        }
    }
}

public enum ArenaSourceCardCategory: String, Sendable { case unlock, starPower, gadget, overcharge, other }

/// A validated index of all definitions. It intentionally exposes no `canPlay`
/// or `isSupported`: runtime support belongs to the actual combat dispatcher.
public struct ArenaSourceRuleRegistry: Sendable {
    public enum DefinitionAvailability: Equatable, Sendable { case presentDefinition, sourceMissing }
    public struct DependencyClosure: Sendable {
        public let definitions: [ArenaSourceRuleID]
        public let missingRoots: [ArenaSourceRuleID]
        public let missingReferences: [ArenaSourceRuleCatalog.Reference]
        public let unresolvedSelectors: [ArenaSourceRuleCatalog.UnresolvedSelector]
    }
    public let catalog: ArenaSourceRuleCatalog
    private let tableIndex: [ArenaSourceRuleTable: ArenaSourceRuleCatalog.Table]
    private let recordIndex: [ArenaSourceRuleID: ArenaSourceRuleCatalog.Record]
    private let outgoing: [ArenaSourceRuleID: [ArenaSourceRuleCatalog.Reference]]
    private let selectors: [ArenaSourceRuleID: [ArenaSourceRuleCatalog.UnresolvedSelector]]
    private let heroCards: [String: [ArenaSourceRuleID]]

    public init(data: Data) throws { try self.init(catalog: ArenaSourceRuleCatalog.decode(data)) }

    public init(catalog: ArenaSourceRuleCatalog) throws {
        func require(_ condition: Bool, _ detail: String) throws {
            if !condition { throw ArenaSourceRuleError.invalid(detail) }
        }
        try require(catalog.schemaVersion == 1 && catalog.artifactKind == "source_rule_registry", "版本或目录类别")
        try require(catalog.executionPolicy == "definitions_only", "规则目录不能声明可执行能力")
        try require(Self.isSHA256(catalog.sourceIPASHA256), "IPA 校验值")
        try require(catalog.tables.count == ArenaSourceRuleTable.allCases.count, "表数量")
        try require(Set(catalog.tables.map(\.id)) == Set(ArenaSourceRuleTable.allCases), "缺失或重复表")
        try require(catalog.references.count <= ArenaSourceRuleCatalog.maximumReferences, "引用数量")
        try require(catalog.unresolvedSelectors.count <= 20_000, "原生选择器数量")

        var tables: [ArenaSourceRuleTable: ArenaSourceRuleCatalog.Table] = [:]
        var records: [ArenaSourceRuleID: ArenaSourceRuleCatalog.Record] = [:]
        var totalRows = 0, totalCells = 0, totalStringBytes = 0, totalSourceBytes = 0
        for table in catalog.tables {
            try require(table.sourcePath == "Payload/NB.app/res/csv_logic/\(table.id.rawValue).csv", "来源路径")
            try require(Self.isSHA256(table.sourceSHA256), "CSV 校验值")
            try require(table.sourceBytes > 0 && table.sourceBytes <= ArenaSourceRuleCatalog.maximumBytes, "CSV 字节数")
            totalSourceBytes += table.sourceBytes
            try require(totalSourceBytes <= 64 * 1024 * 1024, "CSV 总大小")
            try require((1...256).contains(table.columns.count) && table.columns.first?.name == "Name", "表字段数量或主键")
            try require(Set(table.columns.map(\.name)).count == table.columns.count, "重复字段")
            try require(table.columns.allSatisfy { Self.safeIdentifier($0.name) && ["string", "int", "boolean"].contains($0.type.lowercased()) }, "字段名或类型")
            try require(table.records.count <= ArenaSourceRuleCatalog.maximumRecords, "单表记录数量")
            var lastLine = 2
            for record in table.records {
                let key = ArenaSourceRuleID(table: table.id, id: record.id)
                try require(Self.safeIdentifier(record.id) && records[key] == nil, "重复或无效记录标识")
                try require((1...4096).contains(record.rows.count), "记录行数量")
                for (offset, row) in record.rows.enumerated() {
                    try require(row.line > lastLine && row.line <= 5_000_000, "来源行号或顺序")
                    lastLine = row.line
                    try require(!row.values.isEmpty && row.values.count <= table.columns.count, "来源行宽度")
                    try require(row.values[0] == (offset == 0 ? record.id : ""), "记录主行或续行标识")
                    totalRows += 1; totalCells += row.values.count
                    try require(totalRows <= ArenaSourceRuleCatalog.maximumRows && totalCells <= ArenaSourceRuleCatalog.maximumCells, "来源单元格数量")
                    for value in row.values {
                        try require(value.utf8.count <= 1024 * 1024 && !value.contains("\0"), "来源单元格大小或空字符")
                        totalStringBytes += value.utf8.count
                    }
                    try require(totalStringBytes <= ArenaSourceRuleCatalog.maximumBytes, "来源文本总量")
                }
                records[key] = record
                try require(records.count <= ArenaSourceRuleCatalog.maximumRecords, "总记录数量")
            }
            tables[table.id] = table
        }

        // Reference field policy is compiled into this schema version. A pack
        // cannot hide a missing edge by deleting or weakening its own rule list.
        let schema = Self.referenceSchema
        try require(catalog.referenceRules.sorted { $0.id < $1.id } == schema, "引用字段规则与 schema 不符")
        var expected = Set<ArenaSourceRuleCatalog.Reference>()
        for rule in schema {
            guard let table = tables[rule.sourceTable], tables[rule.targetTable] != nil,
                  let column = table.columns.firstIndex(where: { $0.name == rule.field }) else {
                throw ArenaSourceRuleError.invalid("引用字段不存在：\(rule.id)")
            }
            if let condition = rule.condition {
                try require(table.columns.contains { $0.name == condition.field }, "引用条件字段")
            }
            for record in table.records {
                let source = ArenaSourceRuleID(table: table.id, id: record.id)
                if let condition = rule.condition,
                   Set(Self.values(record, in: table, field: condition.field)).isDisjoint(with: condition.values) { continue }
                for row in record.rows where column < row.values.count {
                    for (index, name) in Self.tokens(row.values[column]) where !(rule.ignoredTokens ?? []).contains(name) {
                        let target = ArenaSourceRuleID(table: rule.targetTable, id: name)
                        try require(Self.safeIdentifier(name), "引用目标标识：\(rule.id)")
                        expected.insert(.init(ruleID: rule.id, source: source, line: row.line, field: rule.field,
                                              tokenIndex: index, target: target, resolution: records[target] == nil ? .sourceMissing : .present))
                        try require(expected.count <= ArenaSourceRuleCatalog.maximumReferences, "推导引用数量")
                    }
                }
            }
        }
        let actual = Set(catalog.references)
        try require(actual.count == catalog.references.count && actual == expected, "引用丢失、重复、坐标或存在性不符")

        var names: [String: [ArenaSourceRuleID]] = [:]
        for key in records.keys { names[key.id, default: []].append(key) }
        var expectedSelectors: [ArenaSourceRuleCatalog.UnresolvedSelector] = []
        for (tableID, fields) in Self.selectorSchema.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let table = tables[tableID] else { throw ArenaSourceRuleError.invalid("选择器表") }
            for field in fields {
                guard let column = table.columns.firstIndex(where: { $0.name == field }) else { throw ArenaSourceRuleError.invalid("选择器字段") }
                for record in table.records {
                    for row in record.rows where column < row.values.count {
                        for (index, value) in Self.tokens(row.values[column]) {
                            expectedSelectors.append(.init(source: .init(table: tableID, id: record.id), line: row.line,
                                                           field: field, tokenIndex: index, value: value,
                                                           candidates: (names[value] ?? []).sorted(by: Self.order)))
                            try require(expectedSelectors.count <= 20_000, "推导原生选择器数量")
                        }
                    }
                }
            }
        }
        try require(catalog.unresolvedSelectors == expectedSelectors, "原生选择器丢失或候选目标不符")
        guard let characters = tables[.characters], let cards = tables[.cards], let transforms = tables[.transforms] else {
            throw ArenaSourceRuleError.invalid("英雄索引表")
        }
        let roster = try Self.deriveRoster(characters: characters, cards: cards, transforms: transforms)
        try require(catalog.roster == roster, "英雄或技能卡索引与完整来源表不符")

        self.catalog = catalog; tableIndex = tables; recordIndex = records
        outgoing = Dictionary(grouping: catalog.references, by: \.source)
        selectors = Dictionary(grouping: catalog.unresolvedSelectors, by: \.source)
        var byHero: [String: [ArenaSourceRuleID]] = [:]
        for record in cards.records {
            let targets = Set(Self.values(record, in: cards, field: "Target").flatMap { Self.tokens($0).map(\.1) })
            for hero in targets { byHero[hero, default: []].append(.init(table: .cards, id: record.id)) }
        }
        heroCards = byHero
    }

    public var sourceMissingReferences: [ArenaSourceRuleCatalog.Reference] { catalog.references.filter { $0.resolution == .sourceMissing } }
    public func table(_ id: ArenaSourceRuleTable) -> ArenaSourceRuleCatalog.Table? { tableIndex[id] }
    public func record(table: ArenaSourceRuleTable, id: String) -> ArenaSourceRuleRecordView? { record(.init(table: table, id: id)) }
    public func record(_ id: ArenaSourceRuleID) -> ArenaSourceRuleRecordView? {
        guard let record = recordIndex[id], let table = tableIndex[id.table] else { return nil }
        return .init(id: id, record: record, columns: table.columns)
    }
    public func hero(_ id: String) -> ArenaSourceRuleRecordView? {
        guard let result = record(table: .characters, id: id), result.values("Type").contains(where: { $0.value == "Hero" }) else { return nil }
        return result
    }
    public func availability(of id: ArenaSourceRuleID) -> DefinitionAvailability { recordIndex[id] == nil ? .sourceMissing : .presentDefinition }
    public func references(from id: ArenaSourceRuleID) -> [ArenaSourceRuleCatalog.Reference] { outgoing[id] ?? [] }

    /// These are source card definitions for inspection; none are marked usable.
    public func cards(forHeroID id: String, category: ArenaSourceCardCategory? = nil,
                      includeDisabled: Bool = false) -> [ArenaSourceRuleRecordView] {
        (heroCards[id] ?? []).compactMap { key in
            guard let view = record(key) else { return nil }
            let disabled = view.values("Disabled").contains { ["true", "1"].contains($0.value.lowercased()) }
            guard includeDisabled || !disabled else { return nil }
            if let category, Self.category(view) != category { return nil }
            return view
        }
    }

    public func dependencyClosure(from roots: [ArenaSourceRuleID]) -> DependencyClosure {
        var queue = roots, seen = Set<ArenaSourceRuleID>(), missingRoots = Set<ArenaSourceRuleID>()
        var missing: [ArenaSourceRuleCatalog.Reference] = [], uncertain: [ArenaSourceRuleCatalog.UnresolvedSelector] = []
        while let key = queue.popLast() {
            guard seen.insert(key).inserted else { continue }
            guard recordIndex[key] != nil else { missingRoots.insert(key); continue }
            uncertain += selectors[key] ?? []
            for reference in outgoing[key] ?? [] {
                if reference.resolution == .sourceMissing { missing.append(reference) }
                else { queue.append(reference.target) }
            }
        }
        return .init(definitions: seen.subtracting(missingRoots).sorted(by: Self.order), missingRoots: missingRoots.sorted(by: Self.order),
                     missingReferences: missing, unresolvedSelectors: uncertain)
    }

    private static func category(_ view: ArenaSourceRuleRecordView) -> ArenaSourceCardCategory {
        switch try? view.string("MetaType") {
        case "0": return .unlock
        case "4": return .starPower
        case "5": return .gadget
        case "6": return .overcharge
        default: return .other
        }
    }
    private static func deriveRoster(characters: ArenaSourceRuleCatalog.Table, cards: ArenaSourceRuleCatalog.Table,
                                     transforms: ArenaSourceRuleCatalog.Table) throws -> ArenaSourceRuleCatalog.Roster {
        for field in ["Type", "Disabled", "ItemName"] where !characters.columns.contains(where: { $0.name == field }) {
            throw ArenaSourceRuleError.invalid("英雄索引字段：\(field)")
        }
        for field in ["MetaType", "Disabled", "Target"] where !cards.columns.contains(where: { $0.name == field }) {
            throw ArenaSourceRuleError.invalid("卡片索引字段：\(field)")
        }
        func disabled(_ record: ArenaSourceRuleCatalog.Record, _ table: ArenaSourceRuleCatalog.Table) throws -> Bool {
            let flags = values(record, in: table, field: "Disabled")
            guard flags.allSatisfy({ ["true", "false", "0", "1"].contains($0.lowercased()) }) else {
                throw ArenaSourceRuleError.invalid("禁用字段不是布尔值")
            }
            return flags.contains { ["true", "1"].contains($0.lowercased()) }
        }
        let heroes = characters.records.filter { values($0, in: characters, field: "Type").contains("Hero") }
        let enabled = try heroes.filter { try !disabled($0, characters) }
        let disabledIDs = try heroes.filter { try disabled($0, characters) }.map(\.id)
        let independent = enabled.filter { !values($0, in: characters, field: "ItemName").isEmpty }.map(\.id)
        let enabledIDs = Set(enabled.map(\.id)), allIDs = Set(heroes.map(\.id))
        func targets(_ card: ArenaSourceRuleCatalog.Record) -> Set<String> {
            Set(values(card, in: cards, field: "Target").flatMap { tokens($0).map(\.1) })
        }
        var groups: [String: [String]] = [:]
        for meta in ["0", "4", "5", "6"] {
            groups[meta] = try cards.records.filter { record in
                guard values(record, in: cards, field: "MetaType").contains(meta) else { return false }
                let isDisabled = try disabled(record, cards)
                return !isDisabled && !targets(record).isDisjoint(with: enabledIDs)
            }.map(\.id)
        }
        return .init(enabledHeroIDs: enabled.map(\.id), independentHeroIDs: independent,
                     formHeroIDs: enabled.map(\.id).filter { !independent.contains($0) }, disabledHeroIDs: disabledIDs,
                     associatedCardIDs: cards.records.filter { !targets($0).isDisjoint(with: allIDs) }.map(\.id),
                     transformConfigIDs: transforms.records.map(\.id),
                     cardGroups: .init(unlocks: groups["0"] ?? [], starPowers: groups["4"] ?? [], gadgets: groups["5"] ?? [], overcharges: groups["6"] ?? []))
    }
    private static func values(_ record: ArenaSourceRuleCatalog.Record, in table: ArenaSourceRuleCatalog.Table, field: String) -> [String] {
        guard let index = table.columns.firstIndex(where: { $0.name == field }) else { return [] }
        return record.rows.compactMap { $0.values.count > index && !$0.values[index].isEmpty ? $0.values[index] : nil }
    }
    private static func tokens(_ value: String) -> [(Int, String)] {
        value.components(separatedBy: ";").enumerated().compactMap { index, raw in
            let name = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n"))
            return name.isEmpty ? nil : (index, name)
        }
    }
    private static func order(_ a: ArenaSourceRuleID, _ b: ArenaSourceRuleID) -> Bool {
        a.table == b.table ? a.id < b.id : a.table.rawValue < b.table.rawValue
    }
    private static func safeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 }
            && !value.contains("/") && !value.contains("\\") && value != "." && value != ".."
    }
    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    // Schema field names only. No proprietary source records or payloads are
    // embedded in code. Keep the private builder and this version in agreement.
    static let selectorSchema: [ArenaSourceRuleTable: [String]] = [
        .accessories: ["CustomObject"], .skills: ["CustomString", "CustomString2"],
        .enumeratedIDLists: ["StringContent"], .gameModeVariations: ["TPInterestCharacter"]
    ]
    static let referenceSchema: [ArenaSourceRuleCatalog.ReferenceRule] = {
        let fields = """
accessories|AreaEffect,PetAreaEffect|area_effects_logic
accessories|BuddyCharacterComponent|components_logic
accessories|Skill|skills
accessories|StatusEffectAlly,StatusEffectEnemy,StatusEffectSelf|status_effects_logic
actions|AreaEffects|area_effects_logic
actions|Characters|characters
actions|Conditions|conditions
actions|Projectiles|projectiles_logic
actions|Skills|skills
actions|StatusEffects|status_effects_logic
area_effects_logic|ActionsAlly,ActionsEnemy,ActionsSelf|actions
area_effects_logic|ChainAreaEffect,ChainAreaEffect2,ChainAreaEffect3,ChildAreaEffect,OverchargedChainAreaEffect,OverchargedChainAreaEffect2,OverchargedChainAreaEffect3,RelatedImmunityAreas|area_effects_logic
area_effects_logic|BulletExplosionItem,SpawnItem|items_logic
area_effects_logic|BulletExplosionBullet|projectiles_logic
area_effects_logic|StatusEffectAlly,StatusEffectEnemy,StatusEffectSelf|status_effects_logic
bosses|AttackIndicatorAreaEffects|area_effects_logic
bosses|SpawnBossOnDeath|characters
bosses|AttackSkills|skills
bosses|VulnerableStatusEffect|status_effects_logic
bosses|BossTraits|traits
buddies|Accessory|accessories
buddies|Components|components_logic
buddies|Traits|traits
cards|AreaEffect|area_effects_logic
cards|Buddies|buddies
cards|LinkedCard|cards
cards|Target|characters
cards|TargetClassArchetype|class_archetypes
cards|Components|components_logic
cards|Projectiles|projectiles_logic
cards|RogueliteDeck|roguelite_decks
cards|StatusEffect,StatusEffectOvercharged|status_effects_logic
cards|Traits|traits
carryables|ThrowSkill,ThrowSkillUlti|skills
carryables|CarryStatusEffect,HitStatusEffect|status_effects_logic
characters|AreaEffect,DeathAreaEffect,DeathOverchargedAreaEffect|area_effects_logic
characters|CarryableType|carryables
characters|AltPet,BuddyCharacter,Pet|characters
characters|ClassArchetype|class_archetypes
characters|Components|components_logic
characters|AutoAttackProjectile,OverchargedAutoAttackProjectile|projectiles_logic
characters|OverchargedUltimateSkill,UltimateSkill,WeaponSkill|skills
characters|StatusEffect|status_effects_logic
characters|Traits|traits
components_logic|AreaEffects|area_effects_logic
components_logic|Characters|characters
components_logic|Items|items_logic
components_logic|Projectiles|projectiles_logic
components_logic|Skills|skills
components_logic|StatusEffects,StatusEffectsOvercharged|status_effects_logic
components_logic|Traits,TraitsOvercharged|traits
conditions|AreaEffects|area_effects_logic
conditions|Characters|characters
conditions|Projectiles|projectiles_logic
conditions|Skills|skills
conditions|StatusEffects|status_effects_logic
event_modifiers|Component|components_logic
game_mode_variations|BotGoalAreaEffect|area_effects_logic
game_mode_variations|BossCharacterData,BossCharacterData2,BossCharacterData3,ModeCarryable,UIBossCharacter|characters
game_mode_variations|BotItemPickup,BotItemPickup2,DroppedItemOnDeath|items_logic
game_mode_variations|StartingTraits|traits
gear_boosts|ExtraHerosAvailableTo|characters
gear_boosts|Rarity|gear_rarities
gear_boosts|StatusEffect|status_effects_logic
items_logic|CustomAreaEffect1,CustomAreaEffect2,DestroyAreaEffect,TriggerAreaEffect|area_effects_logic
items_logic|Components|components_logic
items_logic|StatusEffectAlly,StatusEffectEnemy|status_effects_logic
projectiles_logic|OnAllyHitActions,OnEnemyHitActions|actions
projectiles_logic|OnCreateAreaEffect,SpawnAreaEffectObject,SpawnAreaEffectObject2,SpawnAreaEffectObjectsAdditional,SpawnAreaEffectTrail|area_effects_logic
projectiles_logic|SpawnCharacter|characters
projectiles_logic|SpawnItem|items_logic
projectiles_logic|ChainBullet|projectiles_logic
projectiles_logic|StatusEffectAlly,StatusEffectEnemy,StatusEffectSelfOnHit|status_effects_logic
roguelite_cards|ExcludeBrawlers,LinkedToCharacterProgress|characters
roguelite_cards|Family|roguelite_skill_families
roguelite_cards|Traits|traits
roguelite_decks|RogueliteCard1,RogueliteCard10,RogueliteCard11,RogueliteCard12,RogueliteCard13,RogueliteCard14,RogueliteCard15,RogueliteCard16,RogueliteCard17,RogueliteCard18,RogueliteCard19,RogueliteCard2,RogueliteCard20,RogueliteCard21,RogueliteCard22,RogueliteCard23,RogueliteCard24,RogueliteCard25,RogueliteCard3,RogueliteCard4,RogueliteCard5,RogueliteCard6,RogueliteCard7,RogueliteCard8,RogueliteCard9|roguelite_cards
skills|MeleeAttackOnHitActions|actions
skills|AreaEffectObject,AreaEffectObject2,OverchargedAreaEffectObject,OverchargedAreaEffectObject2|area_effects_logic
skills|OverchargedSummonedCharacters,SummonedCharacters|characters
skills|OverchargedSpawnedItem,SpawnedItem|items_logic
skills|OverchargedChainProjectile,OverchargedProjectiles,Projectiles|projectiles_logic
skills|OverchargedVersion,SecondarySkill,SecondarySkill2,SecondarySkill3,SecondarySkill4|skills
skills|ActivationSelfStatusEffects,ActivationSelfStatusEffectsOvercharged,OnChargeHitSelfStatusEffect,OnChargeHitStatusEffect,OnChargeHitStatusEffectOvercharged|status_effects_logic
status_effects_logic|ActionsOnCancelOnDamage,ActionsOnTrigger|actions
status_effects_logic|SpawnAreaEffectOnDeath|area_effects_logic
status_effects_logic|SpawnCharacterOnDeath|characters
status_effects_logic|Components|components_logic
status_effects_logic|ChainStatusEffect,ChainStatusEffect2,StatusToApplyOnEnd|status_effects_logic
status_effects_logic|Traits|traits
time_spawn_stages_setup|TimeSpawnToUse|time_spawns
time_spawns|PossibleCharacters|characters
traits|Actions|actions
traits|AreaEffect|area_effects_logic
traits|Character|characters
traits|Components|components_logic
traits|Item|items_logic
traits|Projectile|projectiles_logic
traits|Skill|skills
traits|StatusEffect|status_effects_logic
transform_hero_confs|ItemName|items_logic
transform_hero_confs|Traits|traits
"""
        var rules: [ArenaSourceRuleCatalog.ReferenceRule] = fields.split(separator: "\n").flatMap { line -> [ArenaSourceRuleCatalog.ReferenceRule] in
            let parts = line.split(separator: "|").map(String.init)
            guard parts.count == 3, let source = ArenaSourceRuleTable(rawValue: parts[0]),
                  let target = ArenaSourceRuleTable(rawValue: parts[2]) else { preconditionFailure("Invalid compiled reference schema") }
            return parts[1].split(separator: ",").map(String.init).map { field in
                .init(id: "\(source.rawValue).\(field)", sourceTable: source, field: field, targetTable: target,
                      separator: "semicolon", condition: nil,
                      ignoredTokens: source == .bosses && field == "AttackIndicatorAreaEffects" ? ["-", "'-", "''-", "'''-"] : nil)
            }
        }
        for (suffix, types, table) in [("accessory", ["accessory", "default_accessory"], ArenaSourceRuleTable.accessories),
                                       ("character", ["alt_character"], .characters), ("skill", ["skill", "bonus_skill"], .skills)] {
            rules.append(.init(id: "cards.Skill.\(suffix)", sourceTable: .cards, field: "Skill", targetTable: table,
                               separator: "semicolon", condition: .init(field: "Type", values: types), ignoredTokens: nil))
        }
        return rules.sorted { $0.id < $1.id }
    }()
}
