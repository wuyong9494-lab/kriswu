import Foundation

/// A reviewed, source-preserving map description. Raw client map rows are not
/// ArenaMap's ASCII format: every source symbol needs an explicit binding.
/// Decoding this type does not register a map or certify its gameplay rules.
public struct ArenaImportedMap: Codable, Equatable, Sendable {
    public struct Identity: Codable, Equatable, Sendable {
        public var namespace: String
        public var dataset: String
        public var location: String
        public var layout: String
        public var archiveSHA256: String?

        public init(namespace: String, dataset: String, location: String, layout: String, archiveSHA256: String? = nil) {
            self.namespace = namespace; self.dataset = dataset; self.location = location
            self.layout = layout; self.archiveSHA256 = archiveSHA256
        }

        /// Location is included because one layout can have different modes/themes.
        /// Components are validated before adaptation; no process-random hash is used.
        public var stableID: String { "imported:\(namespace):\(dataset):\(location)" }
    }

    public struct Cell: Codable, Hashable, Sendable {
        public var x: Int
        public var y: Int
        public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
        public var center: V2 { V2(Double(x) + 0.5, Double(y) + 0.5) }
    }

    public struct Terrain: Codable, Equatable, Sendable {
        public var id: String
        public var blocksMovement: Bool?
        public var blocksProjectiles: Bool?
        public var concealsHeroes: Bool?
        public var destructible: Bool?
        /// Nonempty entries require engine behavior that this adapter cannot supply.
        public var requiredMechanics: [String]
        public var unresolvedProperties: [String]
        public var rawProperties: [String: String]
        /// Reference to the actual rule/default interpretation; empty is unresolved.
        public var evidence: String
        /// Required for mutable runtime imports, including explicit false values.
        /// Missing values must not be manufactured from unreviewed blank CSV cells.
        public var runtimeBehavior: TerrainRuntimeBehavior?

        public init(id: String, blocksMovement: Bool?, blocksProjectiles: Bool?, concealsHeroes: Bool?,
                    destructible: Bool?, requiredMechanics: [String] = [], unresolvedProperties: [String] = [],
                    rawProperties: [String: String] = [:], evidence: String,
                    runtimeBehavior: TerrainRuntimeBehavior? = nil) {
            self.id = id; self.blocksMovement = blocksMovement; self.blocksProjectiles = blocksProjectiles
            self.concealsHeroes = concealsHeroes; self.destructible = destructible
            self.requiredMechanics = requiredMechanics; self.unresolvedProperties = unresolvedProperties
            self.rawProperties = rawProperties; self.evidence = evidence
            self.runtimeBehavior = runtimeBehavior
        }
    }

    public struct TerrainRuntimeBehavior: Codable, Equatable, Sendable {
        public var visualKind: ArenaTerrainState.VisualKind
        public var destroyedByNormalWeapons: Bool
        public var destroyedInOvertime: Bool
        public var evidence: String
        public var isVisible: Bool?
        public init(visualKind: ArenaTerrainState.VisualKind, destroyedByNormalWeapons: Bool,
                    destroyedInOvertime: Bool, evidence: String, isVisible: Bool? = nil) {
            self.visualKind = visualKind; self.destroyedByNormalWeapons = destroyedByNormalWeapons
            self.destroyedInOvertime = destroyedInOvertime; self.evidence = evidence
            self.isVisible = isVisible
        }
    }

    public struct SymbolBinding: Codable, Equatable, Sendable {
        public var symbol: String
        public var terrainID: String
        public var evidence: String
        public init(symbol: String, terrainID: String, evidence: String) {
            self.symbol = symbol; self.terrainID = terrainID; self.evidence = evidence
        }
    }

    public struct CellOverride: Codable, Equatable, Sendable {
        public var cell: Cell
        public var terrainID: String
        public var evidence: String
        public init(cell: Cell, terrainID: String, evidence: String) {
            self.cell = cell; self.terrainID = terrainID; self.evidence = evidence
        }
    }

    public struct SpawnGroup: Codable, Equatable, Sendable {
        public var team: Int
        /// Explicit slot order. The current row parser can preserve row-major order only.
        public var cells: [Cell]
        public var evidence: String
        public init(team: Int, cells: [Cell], evidence: String) {
            self.team = team; self.cells = cells; self.evidence = evidence
        }
    }

    public struct Region: Codable, Equatable, Sendable {
        public var team: Int
        public var cells: [Cell]
        public init(team: Int, cells: [Cell]) { self.team = team; self.cells = cells }
    }

    public struct Objectives: Codable, Equatable, Sendable {
        /// Grid units, x right/y down. Nil is unresolved, never an inferred midpoint.
        public var center: V2?
        public var goals: [Region]
        public var bases: [Region]
        public var unresolved: [String]
        public var evidence: String
        public var captureZones: [CaptureZone]?
        public var powerBoxes: [PowerBoxPlacement]?
        public init(center: V2?, goals: [Region] = [], bases: [Region] = [],
                    unresolved: [String] = [], evidence: String, captureZones: [CaptureZone]? = nil,
                    powerBoxes: [PowerBoxPlacement]? = nil) {
            self.center = center; self.goals = goals; self.bases = bases
            self.unresolved = unresolved; self.evidence = evidence
            self.captureZones = captureZones; self.powerBoxes = powerBoxes
        }
    }

    public struct CaptureZone: Codable, Equatable, Sendable {
        public var id: String
        public var center: V2
        public var radius: Double
        public var evidence: String
        public init(id: String, center: V2, radius: Double, evidence: String) {
            self.id = id; self.center = center; self.radius = radius; self.evidence = evidence
        }
    }

    public struct PowerBoxPlacement: Codable, Equatable, Sendable {
        public var cell: Cell
        public var health: Int
        public var collisionRadius: Double
        public var spawnProbability: Double
        public var evidence: String
        public init(cell: Cell, health: Int, collisionRadius: Double, spawnProbability: Double, evidence: String) {
            self.cell = cell; self.health = health; self.collisionRadius = collisionRadius
            self.spawnProbability = spawnProbability; self.evidence = evidence
        }
    }

    public struct ModeBinding: Codable, Equatable, Sendable {
        public var sourceMode: String
        public var runtimeMode: String
        public var teamCount: Int
        public var teamSize: Int
        public var rawProperties: [String: String]
        /// An explicit compatibility review, not a match based on similar names.
        public var evidence: String
        public var matchRules: ArenaImportedMatchRules?
        public init(sourceMode: String, runtimeMode: String, teamCount: Int, teamSize: Int,
                    rawProperties: [String: String] = [:], evidence: String,
                    matchRules: ArenaImportedMatchRules? = nil) {
            self.sourceMode = sourceMode; self.runtimeMode = runtimeMode
            self.teamCount = teamCount; self.teamSize = teamSize
            self.rawProperties = rawProperties; self.evidence = evidence
            self.matchRules = matchRules
        }
    }

    public enum IssueCode: String, Codable, Sendable {
        case unsupportedSchema, invalidIdentity, invalidDimensions, raggedRows
        case unresolvedMapping, duplicateDefinition, duplicateBinding, unknownTerrain, unknownSymbol
        case unresolvedTerrain, contradictoryProperty, unsupportedTerrain, unresolvedMetadata
        case unresolvedMode, unsupportedMode, participantMismatch
        case unresolvedSpawns, invalidSpawnGroups, unsupportedSpawnOrder
        case unresolvedObjectives, unexpectedObjectives, invalidObjectiveRegion, unsupportedCoordinate
        case outOfBounds, overlappingPlacement, placementChangesTerrain
    }

    public struct Issue: Codable, Equatable, Sendable {
        public var code: IssueCode
        public var path: String
        public var message: String
        public init(_ code: IssueCode, _ path: String, _ message: String) {
            self.code = code; self.path = path; self.message = message
        }
    }

    public struct ValidationFailure: Error, Equatable, Sendable {
        public let issues: [Issue]
    }

    public struct Adaptation: Sendable {
        public let map: ArenaMap
        public let mode: ArenaGame.Mode
        public let identity: Identity
        /// The caller still needs an explicit registry entry and matching game rules.
        public let requiresRuntimeRegistration = true
    }

    /// The map is an initial legacy renderer/spawn snapshot. All gameplay terrain
    /// queries and drawing must use terrainState, because the snapshot cannot encode
    /// water or destruction. This plan never registers itself as an existing map.
    public struct RuntimePlan: Sendable {
        public let map: ArenaMap
        public let mode: ArenaGame.Mode
        public let identity: Identity
        public let terrainState: ArenaTerrainState
        public let spawns: [SpawnGroup]
        public let respawns: [SpawnGroup]
        public let objectives: Objectives
        public let modeBinding: ModeBinding
        public var matchRules: ArenaImportedMatchRules? { modeBinding.matchRules }
        public let environmentThemeName: String?
        public let requiresRuntimeRegistration = true
        public let requiresTerrainState = true
        public let requiresExplicitSpawns = true
    }

    public var schemaVersion: Int
    public var identity: Identity
    public var title: String
    public var runtimeTheme: String
    /// Exact source environment name. runtimeTheme is only a host renderer fallback.
    public var environmentThemeName: String?
    /// Lossless original characters. Row 0 is the normalized top row.
    public var sourceRows: [String]
    public var terrain: [Terrain]
    public var bindings: [SymbolBinding]
    public var overrides: [CellOverride]
    public var spawns: [SpawnGroup]
    public var respawns: [SpawnGroup]?
    public var excludedCells: [Cell]?
    public var objectives: Objectives?
    public var mode: ModeBinding?
    public var mappingEvidence: String
    public var unresolvedFeatures: [String]
    public var rawMetadataJSON: String?
    public var metadataReviewed: Bool

    public init(schemaVersion: Int = 1, identity: Identity, title: String, runtimeTheme: String,
                sourceRows: [String], terrain: [Terrain], bindings: [SymbolBinding],
                overrides: [CellOverride] = [], spawns: [SpawnGroup], objectives: Objectives?,
                mode: ModeBinding?, mappingEvidence: String, unresolvedFeatures: [String] = [],
                rawMetadataJSON: String? = nil, metadataReviewed: Bool = false,
                environmentThemeName: String? = nil, respawns: [SpawnGroup]? = nil, excludedCells: [Cell]? = nil) {
        self.schemaVersion = schemaVersion; self.identity = identity; self.title = title
        self.runtimeTheme = runtimeTheme; self.sourceRows = sourceRows; self.terrain = terrain
        self.bindings = bindings; self.overrides = overrides; self.spawns = spawns
        self.objectives = objectives; self.mode = mode; self.mappingEvidence = mappingEvidence
        self.unresolvedFeatures = unresolvedFeatures; self.rawMetadataJSON = rawMetadataJSON
        self.metadataReviewed = metadataReviewed
        self.environmentThemeName = environmentThemeName
        self.respawns = respawns; self.excludedCells = excludedCells
    }

    public var stableID: String { identity.stableID }
    public func validationIssues() -> [Issue] { prepare().issues }
    public func runtimeValidationIssues() -> [Issue] { prepare(forRuntime: true).issues }

    /// Adapts only explicitly resolved behavior supported by ArenaMap today.
    /// This never substitutes the special "custom" ID to bypass registry checks.
    public func adapt() throws -> Adaptation {
        let prepared = prepare()
        guard prepared.issues.isEmpty, let mode = prepared.mode, let theme = prepared.theme else {
            throw ValidationFailure(issues: prepared.issues)
        }
        return Adaptation(map: ArenaMap(id: stableID, title: title, theme: theme, rows: prepared.rows),
                          mode: mode, identity: identity)
    }

    /// Resolves the supported mutable terrain subset without losing source cells.
    /// Mode bindings still describe an explicit reviewed implementation; this does
    /// not certify equivalence to a remote or version-specific game server.
    public func runtimePlan() throws -> RuntimePlan {
        let prepared = prepare(forRuntime: true)
        guard prepared.issues.isEmpty, let runtimeMode = prepared.mode, let theme = prepared.theme,
              let state = prepared.terrainState, let objectives, let mode else {
            throw ValidationFailure(issues: prepared.issues)
        }
        return RuntimePlan(map: ArenaMap(id: stableID, title: title, theme: theme, rows: prepared.rows),
                           mode: runtimeMode, identity: identity, terrainState: state,
                           spawns: spawns, respawns: respawns ?? [], objectives: objectives, modeBinding: mode,
                           environmentThemeName: environmentThemeName)
    }

    private struct Prepared {
        var issues: [Issue] = []
        var rows: [String] = []
        var mode: ArenaGame.Mode?
        var theme: ArenaMap.Theme?
        var terrainState: ArenaTerrainState?
    }

    private static func reviewed(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func component(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 160 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || $0 == 45 || $0 == 46 || $0 == 95
        }
    }

    private static func rowOrder(_ a: Cell, _ b: Cell) -> Bool {
        a.y == b.y ? a.x < b.x : a.y < b.y
    }

    private func prepare(forRuntime: Bool = false) -> Prepared {
        var result = Prepared()
        if schemaVersion != 1 { result.issues.append(Issue(.unsupportedSchema, "schemaVersion", "Only schema version 1 is supported.")) }
        for (key, value) in [("namespace", identity.namespace), ("dataset", identity.dataset),
                             ("location", identity.location), ("layout", identity.layout)] where !Self.component(value) {
            result.issues.append(Issue(.invalidIdentity, "identity.\(key)", "Use a nonempty ASCII identifier with letters, digits, period, dash or underscore."))
        }
        if let hash = identity.archiveSHA256,
           hash.utf8.count != 64 || !hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) {
            result.issues.append(Issue(.invalidIdentity, "identity.archiveSHA256", "Expected a lowercase SHA256 digest."))
        }
        if !Self.reviewed(mappingEvidence) || !unresolvedFeatures.isEmpty {
            result.issues.append(Issue(.unresolvedMapping, "mappingEvidence", "Coordinate/feature mapping needs evidence and no unresolved features."))
        }
        if let metadata = rawMetadataJSON, !metadata.isEmpty {
            let validJSON = metadata.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } != nil
            if !metadataReviewed || !validJSON {
                result.issues.append(Issue(.unresolvedMetadata, "rawMetadataJSON", "Raw metadata must be valid JSON and explicitly reviewed before adaptation."))
            }
        }
        result.theme = ArenaMap.Theme(rawValue: runtimeTheme)
        if result.theme == nil { result.issues.append(Issue(.unresolvedMapping, "runtimeTheme", "No explicit existing renderer theme is selected.")) }
        let height = sourceRows.count
        let width = sourceRows.first?.count ?? 0
        guard (1...128).contains(width), (1...128).contains(height) else {
            result.issues.append(Issue(.invalidDimensions, "sourceRows", "Expected a nonempty grid no larger than 128 by 128."))
            return result
        }
        guard sourceRows.allSatisfy({ $0.count == width }) else {
            result.issues.append(Issue(.raggedRows, "sourceRows", "Rows must have equal lengths; no padding or truncation is allowed."))
            return result
        }
        let source = sourceRows.map { Array($0) }
        var output = Array(repeating: Array(repeating: Character("."), count: width), count: height)
        func inside(_ cell: Cell) -> Bool { cell.x >= 0 && cell.x < width && cell.y >= 0 && cell.y < height }

        var definitions: [String: Terrain] = [:]
        var symbols: [String: Character] = [:]
        var runtimeRules: [ArenaTerrainState.Rule] = []
        for (index, definition) in terrain.enumerated() {
            let path = "terrain[\(index)]"
            if definition.id.isEmpty || definitions[definition.id] != nil {
                result.issues.append(Issue(.duplicateDefinition, path, "Terrain IDs must be nonempty and unique."))
                continue
            }
            definitions[definition.id] = definition
            guard Self.reviewed(definition.evidence), definition.unresolvedProperties.isEmpty,
                  let move = definition.blocksMovement, let shot = definition.blocksProjectiles,
                  let forest = definition.concealsHeroes, let destructible = definition.destructible else {
                result.issues.append(Issue(.unresolvedTerrain, path, "Blank source properties must be resolved explicitly, not treated as false."))
                continue
            }
            let explicit: [(String, Bool)] = [("BlocksMovement", move), ("BlocksProjectiles", shot),
                                               ("IsForest", forest), ("IsDestructible", destructible)]
            for (key, expected) in explicit {
                let raw = definition.rawProperties[key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let supplied: Bool? = ["true", "1"].contains(raw) ? true : ["false", "0"].contains(raw) ? false : nil
                if let supplied, supplied != expected {
                    result.issues.append(Issue(.contradictoryProperty, path + "." + key, "Normalized behavior contradicts an explicit source property."))
                } else if !raw.isEmpty && supplied == nil {
                    result.issues.append(Issue(.unresolvedTerrain, path + "." + key, "The source boolean value is not recognized."))
                }
            }
            let specialFlags = forRuntime ? ["IsBouncer", "RestoreAfterDynamicOverlap"]
                : ["IsDestructibleNormalWeapon", "IsDestructibleOvertime", "IsBouncer", "RestoreAfterDynamicOverlap"]
            let hasSpecialFlag = specialFlags.contains {
                let raw = definition.rawProperties[$0, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !raw.isEmpty && !["false", "0"].contains(raw)
            }
            let numericMechanics = ["Damage", "Health", "RespawnSeconds", "SpeedChange", "CollisionMargin", "Lifetime", "DynamicCode"]
            let hasNumericMechanic = numericMechanics.contains {
                let raw = definition.rawProperties[$0, default: ""]
                return !raw.isEmpty && Double(raw) != 0
            }
            if (!forRuntime && destructible) || !definition.requiredMechanics.isEmpty || hasSpecialFlag || hasNumericMechanic {
                result.issues.append(Issue(.unsupportedTerrain, path, "Destruction, dynamic tiles or other source mechanics need engine implementation."))
                continue
            }
            if forRuntime {
                guard let behavior = definition.runtimeBehavior, Self.reviewed(behavior.evidence) else {
                    result.issues.append(Issue(.unresolvedTerrain, path + ".runtimeBehavior", "Normal-weapon and overtime destruction need explicit reviewed values."))
                    continue
                }
                for (key, expected) in [("IsDestructibleNormalWeapon", behavior.destroyedByNormalWeapons),
                                        ("IsDestructibleOvertime", behavior.destroyedInOvertime)] {
                    let raw = definition.rawProperties[key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let supplied: Bool? = ["true", "1"].contains(raw) ? true : ["false", "0"].contains(raw) ? false : nil
                    if let supplied, supplied != expected {
                        result.issues.append(Issue(.contradictoryProperty, path + "." + key, "Destruction behavior contradicts the explicit source flag."))
                    } else if !raw.isEmpty && supplied == nil {
                        result.issues.append(Issue(.unresolvedTerrain, path + "." + key, "The source boolean value is not recognized."))
                    }
                }
                runtimeRules.append(ArenaTerrainState.Rule(id: definition.id, blocksMovement: move,
                    blocksProjectiles: shot, concealsHeroes: forest,
                    destroyedByNormalWeapons: behavior.destroyedByNormalWeapons,
                    destroyedByWallBreakers: destructible || behavior.destroyedByNormalWeapons,
                    destroyedInOvertime: behavior.destroyedInOvertime,
                    visualKind: behavior.visualKind, isVisible: behavior.isVisible ?? true))
            }
            switch (move, shot, forest) {
            case (false, false, false): symbols[definition.id] = "."
            case (true, true, false): symbols[definition.id] = "#"
            case (false, false, true): symbols[definition.id] = "*"
            case (true, false, false) where forRuntime:
                // Movement snapshot only; projectile queries must use terrainState.
                symbols[definition.id] = "#"
            default:
                result.issues.append(Issue(.unsupportedTerrain, path, "The current terrain type cannot preserve these movement/projectile/concealment properties."))
            }
        }
        var bySymbol: [Character: String] = [:]
        for (index, binding) in bindings.enumerated() {
            let path = "bindings[\(index)]"
            guard binding.symbol.count == 1, let symbol = binding.symbol.first, bySymbol[symbol] == nil else {
                result.issues.append(Issue(.duplicateBinding, path, "Each source character needs at most one unambiguous binding."))
                continue
            }
            bySymbol[symbol] = binding.terrainID
            if !Self.reviewed(binding.evidence) { result.issues.append(Issue(.unresolvedMapping, path, "Symbol interpretation needs explicit evidence.")) }
            if definitions[binding.terrainID] == nil { result.issues.append(Issue(.unknownTerrain, path, "The referenced terrain definition is missing.")) }
        }
        var byCell: [Cell: String] = [:]
        for (index, override) in overrides.enumerated() {
            let path = "overrides[\(index)]"
            guard inside(override.cell) else { result.issues.append(Issue(.outOfBounds, path, "Cell override is outside the source grid.")); continue }
            if byCell[override.cell] != nil { result.issues.append(Issue(.duplicateBinding, path, "Multiple overrides target this cell.")); continue }
            byCell[override.cell] = override.terrainID
            if !Self.reviewed(override.evidence) { result.issues.append(Issue(.unresolvedMapping, path, "Cell interpretation needs explicit evidence.")) }
            if definitions[override.terrainID] == nil { result.issues.append(Issue(.unknownTerrain, path, "The referenced terrain definition is missing.")) }
        }
        var cellTerrainIDs: [String] = []
        var sourceSymbols: [String] = []
        for y in 0..<height {
            for x in 0..<width {
                let cell = Cell(x, y)
                guard let id = byCell[cell] ?? bySymbol[source[y][x]] else {
                    result.issues.append(Issue(.unknownSymbol, "sourceRows[\(y)][\(x)]", "No explicit binding for source character \(source[y][x])."))
                    continue
                }
                cellTerrainIDs.append(id)
                sourceSymbols.append(String(source[y][x]))
                if let symbol = symbols[id] { output[y][x] = symbol }
            }
        }
        var excludedSet = Set<Cell>()
        for cell in excludedCells ?? [] {
            guard inside(cell) else { result.issues.append(Issue(.outOfBounds, "excludedCells", "An excluded cell is outside the source grid.")); continue }
            if !excludedSet.insert(cell).inserted { result.issues.append(Issue(.duplicateBinding, "excludedCells", "An excluded cell is duplicated.")) }
            output[cell.y][cell.x] = "#"
        }
        if !forRuntime && (!excludedSet.isEmpty || !(respawns ?? []).isEmpty) {
            result.issues.append(Issue(.unsupportedTerrain, "runtimeFeatures", "Excluded regions and separate respawns require the runtime plan."))
        }
        if forRuntime, result.issues.isEmpty {
            do {
                result.terrainState = try ArenaTerrainState(width: width, height: height, rules: runtimeRules,
                                                           terrainIDs: cellTerrainIDs, sourceSymbols: sourceSymbols,
                                                           excludedCells: excludedCells ?? [])
            } catch {
                result.issues.append(Issue(.unsupportedTerrain, "terrain.runtimeBehavior", "The resolved terrain state is inconsistent: \(error)."))
            }
        }

        guard let binding = mode, Self.reviewed(binding.sourceMode), Self.reviewed(binding.evidence),
              let runtimeMode = ArenaGame.Mode(rawValue: binding.runtimeMode) else {
            result.issues.append(Issue(.unresolvedMode, "mode", "A reviewed source-to-runtime mode binding is required."))
            return result
        }
        result.mode = runtimeMode
        if let matchRules = binding.matchRules {
            for problem in matchRules.validationProblems(runtimeMode: runtimeMode) {
                result.issues.append(Issue(.unresolvedMode, "mode.matchRules", problem))
            }
            for (sourceKey, supplied) in [("RespawnSeconds", matchRules.respawnDelay),
                                          ("MaxScore", matchRules.scoreGoal.map(Double.init))] {
                let raw = binding.rawProperties[sourceKey, default: ""]
                if let supplied, !raw.isEmpty, Double(raw) != supplied {
                    result.issues.append(Issue(.contradictoryProperty, "mode.matchRules." + sourceKey,
                                               "The runtime override contradicts the explicit source mode value."))
                }
            }
            if let goldenGoal = matchRules.overtimeGoldenGoal {
                let raw = binding.rawProperties["OvertimeHasGoldenGoal", default: ""].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !raw.isEmpty {
                    let supplied: Bool? = ["true", "1"].contains(raw) ? true : ["false", "0"].contains(raw) ? false : nil
                    if supplied != goldenGoal {
                        result.issues.append(Issue(.contradictoryProperty, "mode.matchRules.overtimeGoldenGoal", "Golden-goal behavior contradicts or cannot decode the explicit source flag."))
                    }
                }
            }
        }
        let expectedTeams: Int
        let expectedSize: Int
        switch runtimeMode {
        case .showdown:
            if forRuntime {
                guard (2...64).contains(binding.teamCount), binding.teamSize == 1 else {
                    result.issues.append(Issue(.participantMismatch, "mode", "A solo runtime plan requires 2...64 explicit one-player teams."))
                    return result
                }
                expectedTeams = binding.teamCount; expectedSize = 1
            } else { expectedTeams = 6; expectedSize = 1 }
        case .duel: expectedTeams = 2; expectedSize = 1
        case .duo:
            guard forRuntime, (2...32).contains(binding.teamCount), binding.teamSize == 2 else {
                result.issues.append(Issue(.unsupportedMode, "mode", "Duo requires a runtime plan with explicit two-player spawn groups."))
                return result
            }
            expectedTeams = binding.teamCount; expectedSize = 2
        case .boss:
            result.issues.append(Issue(.unsupportedMode, "mode", "This adapter cannot preserve the current mode's derived duo anchors or asymmetric boss setup."))
            return result
        case .teamFight, .stars, .ball, .heist, .bounty, .zone, .knockout:
            expectedTeams = 2; expectedSize = 3
        }
        if binding.teamCount != expectedTeams || binding.teamSize != expectedSize {
            result.issues.append(Issue(.participantMismatch, "mode", "Source team count/size does not match the explicitly supported runtime mode."))
        }
        for (key, expected) in [("TeamCount", binding.teamCount), ("TeamSize", binding.teamSize)] {
            let raw = binding.rawProperties[key, default: ""]
            if !raw.isEmpty && Int(raw) != expected {
                result.issues.append(Issue(.contradictoryProperty, "mode." + key, "Normalized participants contradict the raw source mode."))
            }
        }
        var occupied = Set<Cell>()
        func place(_ cell: Cell, symbol: Character, path: String) {
            guard inside(cell) else { result.issues.append(Issue(.outOfBounds, path, "Placement is outside the grid.")); return }
            guard occupied.insert(cell).inserted else { result.issues.append(Issue(.overlappingPlacement, path, "Two spawn/objective placements share a cell.")); return }
            guard output[cell.y][cell.x] == "." else {
                result.issues.append(Issue(.placementChangesTerrain, path, "Encoding this placement would erase terrain behavior; an engine extension is required."))
                return
            }
            output[cell.y][cell.x] = symbol
        }
        let groups = spawns.sorted { $0.team < $1.team }
        if groups.map(\.team) != Array(0..<expectedTeams) || groups.contains(where: { $0.cells.count != expectedSize }) {
            result.issues.append(Issue(.invalidSpawnGroups, "spawns", "Every expected team needs an explicit group with exactly its supported slot count."))
        }
        for (index, group) in groups.enumerated() {
            let path = "spawns[\(index)]"
            if !Self.reviewed(group.evidence) { result.issues.append(Issue(.unresolvedSpawns, path, "Spawn roles must be verified, not inferred from marker names.")) }
            if !forRuntime && group.cells != group.cells.sorted(by: Self.rowOrder) {
                result.issues.append(Issue(.unsupportedSpawnOrder, path, "The current parser cannot preserve a non-row-major spawn slot order."))
            }
            for cell in group.cells { place(cell, symbol: runtimeMode == .showdown || runtimeMode == .duo ? "o" : group.team == 0 ? "a" : "b", path: path) }
        }
        if runtimeMode == .showdown && !forRuntime {
            let cells = groups.flatMap(\.cells)
            if cells != cells.sorted(by: Self.rowOrder) {
                result.issues.append(Issue(.unsupportedSpawnOrder, "spawns", "Solo team order must match the current parser's row-major spawn order."))
            }
        }
        if let respawns, !respawns.isEmpty {
            if !forRuntime || respawns.map(\.team).sorted() != Array(0..<expectedTeams)
                || respawns.contains(where: { $0.cells.count != expectedSize }) {
                result.issues.append(Issue(.invalidSpawnGroups, "respawns", "Separate respawns need every explicit runtime team and slot."))
            }
            var respawnCells = Set<Cell>()
            for group in respawns {
                if !Self.reviewed(group.evidence) { result.issues.append(Issue(.unresolvedSpawns, "respawns", "Respawn roles need their own evidence.")) }
                for cell in group.cells {
                    guard inside(cell) else { result.issues.append(Issue(.outOfBounds, "respawns", "Respawn is outside the grid.")); continue }
                    if !respawnCells.insert(cell).inserted { result.issues.append(Issue(.overlappingPlacement, "respawns", "Two respawns share a cell.")) }
                    if excludedSet.contains(cell) || result.terrainState?.blocksMovement(cell.x, cell.y) != false {
                        result.issues.append(Issue(.placementChangesTerrain, "respawns", "A respawn is blocked by source terrain."))
                    }
                }
            }
        }
        guard let objectives, Self.reviewed(objectives.evidence), objectives.unresolved.isEmpty,
              let center = objectives.center, center.x.isFinite, center.y.isFinite else {
            result.issues.append(Issue(.unresolvedObjectives, "objectives", "An explicit reviewed center and resolved objective list are required."))
            return result
        }
        if center.x < 0 || center.x >= Double(width) || center.y < 0 || center.y >= Double(height) {
            result.issues.append(Issue(.outOfBounds, "objectives.center", "Center is outside the grid."))
        } else {
            let centerMustBeWalkable = !forRuntime || runtimeMode == .stars || runtimeMode == .bounty || runtimeMode == .ball
            if centerMustBeWalkable && output[Int(center.y)][Int(center.x)] == "#" {
                result.issues.append(Issue(.placementChangesTerrain, "objectives.center", "The center is blocked by terrain."))
            }
            if center != V2(Double(width) / 2, Double(height) / 2) {
                let x = center.x - 0.5, y = center.y - 0.5
                if x != x.rounded(.down) || y != y.rounded(.down) {
                    result.issues.append(Issue(.unsupportedCoordinate, "objectives.center", "A non-midpoint center must coincide with a cell center for the current row parser."))
                } else {
                    place(Cell(Int(x), Int(y)), symbol: "s", path: "objectives.center")
                }
            }
        }
        let captureZones = objectives.captureZones ?? []
        if !captureZones.isEmpty && (!forRuntime || runtimeMode != .zone) {
            result.issues.append(Issue(.unexpectedObjectives, "objectives.captureZones", "Capture zones need a zone runtime plan."))
        }
        if forRuntime && runtimeMode == .zone && captureZones.isEmpty {
            result.issues.append(Issue(.unresolvedObjectives, "objectives.captureZones", "A zone match needs explicit source capture areas."))
        }
        var zoneIDs = Set<String>()
        for zone in captureZones {
            guard Self.reviewed(zone.id), zoneIDs.insert(zone.id).inserted, Self.reviewed(zone.evidence),
                  zone.center.x.isFinite, zone.center.y.isFinite, zone.radius.isFinite, zone.radius > 0, zone.radius <= 64,
                  zone.center.x >= 0, zone.center.y >= 0, zone.center.x < Double(width), zone.center.y < Double(height) else {
                result.issues.append(Issue(.invalidObjectiveRegion, "objectives.captureZones", "A capture area has invalid geometry, identity or evidence."))
                continue
            }
            if result.terrainState?.blocksMovement(at: zone.center) != false {
                result.issues.append(Issue(.placementChangesTerrain, "objectives.captureZones", "A capture-area marker is blocked by terrain."))
            }
        }
        let powerBoxes = objectives.powerBoxes ?? []
        if !powerBoxes.isEmpty && (!forRuntime || (runtimeMode != .showdown && runtimeMode != .duo)) {
            result.issues.append(Issue(.unexpectedObjectives, "objectives.powerBoxes", "Source power boxes need a survival runtime plan."))
        }
        var boxCells = Set<Cell>()
        for box in powerBoxes {
            guard inside(box.cell), boxCells.insert(box.cell).inserted, !occupied.contains(box.cell),
                  (1...10_000_000).contains(box.health), box.collisionRadius.isFinite,
                  box.collisionRadius > 0, box.collisionRadius <= 2,
                  box.spawnProbability.isFinite, (0...1).contains(box.spawnProbability), Self.reviewed(box.evidence) else {
                result.issues.append(Issue(.invalidObjectiveRegion, "objectives.powerBoxes", "Power-box positions and probability/health need explicit valid rules."))
                continue
            }
            if result.terrainState?.blocksMovement(box.cell.x, box.cell.y) != false {
                result.issues.append(Issue(.placementChangesTerrain, "objectives.powerBoxes", "A source box marker is blocked by terrain."))
            }
        }
        if (runtimeMode != .ball && !objectives.goals.isEmpty) || (runtimeMode != .heist && !objectives.bases.isEmpty) {
            result.issues.append(Issue(.unexpectedObjectives, "objectives", "Goals or bases do not belong to the reviewed runtime mode."))
        }
        let regions = runtimeMode == .ball ? objectives.goals : runtimeMode == .heist ? objectives.bases : []
        if runtimeMode == .ball || runtimeMode == .heist {
            if regions.map(\.team).sorted() != [0, 1] || regions.contains(where: { $0.cells.isEmpty }) {
                result.issues.append(Issue(.invalidObjectiveRegion, "objectives", "Exactly one nonempty objective region per team is required."))
            }
            for region in regions {
                let members = Set(region.cells)
                guard members.allSatisfy(inside) else {
                    result.issues.append(Issue(.outOfBounds, "objectives", "An objective region contains out-of-bounds cells."))
                    continue
                }
                if members.count != region.cells.count {
                    result.issues.append(Issue(.invalidObjectiveRegion, "objectives", "Objective cells must be unique."))
                }
                if runtimeMode == .heist && !Self.connected(members) {
                    result.issues.append(Issue(.invalidObjectiveRegion, "objectives.bases", "Each base must form one four-connected region."))
                }
                for cell in region.cells {
                    let parserTeam = Double(cell.y) + 0.5 < Double(height) / 2 ? 1 : 0
                    if parserTeam != region.team {
                        result.issues.append(Issue(.invalidObjectiveRegion, "objectives", "The current parser would assign this region to a different team."))
                    }
                    place(cell, symbol: runtimeMode == .ball ? "G" : "C", path: "objectives")
                }
            }
            if runtimeMode == .heist, regions.count == 2, regions.allSatisfy({ $0.cells.allSatisfy(inside) }),
               regions[0].cells.contains(where: { a in regions[1].cells.contains { abs(a.x - $0.x) + abs(a.y - $0.y) == 1 } }) {
                result.issues.append(Issue(.invalidObjectiveRegion, "objectives.bases", "Adjacent opposing bases would be merged by the current parser."))
            }
        }
        result.rows = output.map { String($0) }
        return result
    }

    private static func connected(_ cells: Set<Cell>) -> Bool {
        guard let first = cells.first else { return false }
        var seen: Set<Cell> = [first]
        var queue = [first]
        var head = 0
        while head < queue.count {
            let cell = queue[head]; head += 1
            for next in [Cell(cell.x - 1, cell.y), Cell(cell.x + 1, cell.y), Cell(cell.x, cell.y - 1), Cell(cell.x, cell.y + 1)] {
                if cells.contains(next), seen.insert(next).inserted { queue.append(next) }
            }
        }
        return seen.count == cells.count
    }
}
