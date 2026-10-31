import Foundation

/// Mutable, grid-based terrain for reviewed imported maps. Movement, projectiles
/// and concealment are independent properties; a water cell is never a wall alias.
/// This is engine code only. No third-party map or art is embedded here.
public struct ArenaTerrainState: Equatable, Sendable {
    public enum DestructionCause: String, Codable, Sendable {
        case normalWeapon, wallBreaker, overtime
    }

    public enum VisualKind: String, Codable, Sendable {
        case floor, wall, bush, water
    }

    public struct Rule: Equatable, Sendable {
        public let id: String
        public let blocksMovement: Bool
        public let blocksProjectiles: Bool
        public let concealsHeroes: Bool
        public let destroyedByNormalWeapons: Bool
        public let destroyedByWallBreakers: Bool
        public let destroyedInOvertime: Bool
        public let visualKind: VisualKind
        public let isVisible: Bool

        public init(id: String, blocksMovement: Bool, blocksProjectiles: Bool,
                    concealsHeroes: Bool, destroyedByNormalWeapons: Bool,
                    destroyedByWallBreakers: Bool, destroyedInOvertime: Bool,
                    visualKind: VisualKind, isVisible: Bool = true) {
            self.id = id; self.blocksMovement = blocksMovement
            self.blocksProjectiles = blocksProjectiles; self.concealsHeroes = concealsHeroes
            self.destroyedByNormalWeapons = destroyedByNormalWeapons
            self.destroyedByWallBreakers = destroyedByWallBreakers
            self.destroyedInOvertime = destroyedInOvertime; self.visualKind = visualKind
            self.isVisible = isVisible
        }

        public func canBeDestroyed(by cause: DestructionCause) -> Bool {
            switch cause {
            case .normalWeapon: return destroyedByNormalWeapons
            case .wallBreaker: return destroyedByWallBreakers
            case .overtime: return destroyedInOvertime
            }
        }
    }

    public struct CellSnapshot: Equatable, Sendable {
        public let cell: ArenaImportedMap.Cell
        public let sourceSymbol: String
        public let terrainID: String
        public let visualKind: VisualKind
        public let isDestroyed: Bool
        public let blocksMovement: Bool
        public let blocksProjectiles: Bool
        public let concealsHeroes: Bool
        public let isVisible: Bool
        public let isOutOfBounds: Bool
    }

    public enum InvalidGrid: Error, Equatable, Sendable {
        case dimensions, cellCount, duplicateRule, invalidRule, missingRule, invalidSymbol
    }

    public let width: Int
    public let height: Int
    public private(set) var revision: UInt64 = 0
    public let rules: [Rule]
    private let cellRules: [Int]
    private let sourceSymbols: [String]
    private var destroyed: [Bool]
    private var bushPatches: [Int]
    private let excluded: [Bool]

    /// Both cell arrays are row-major, have width*height entries and are checked.
    public init(width: Int, height: Int, rules: [Rule], terrainIDs: [String], sourceSymbols: [String],
                excludedCells: [ArenaImportedMap.Cell] = []) throws {
        guard (1...128).contains(width), (1...128).contains(height) else { throw InvalidGrid.dimensions }
        let count = width * height
        guard terrainIDs.count == count, sourceSymbols.count == count else { throw InvalidGrid.cellCount }
        guard sourceSymbols.allSatisfy({ $0.count == 1 }) else { throw InvalidGrid.invalidSymbol }
        var indices: [String: Int] = [:]
        for (index, rule) in rules.enumerated() {
            guard !rule.id.isEmpty, indices[rule.id] == nil else { throw InvalidGrid.duplicateRule }
            // A normal weapon cannot destroy something that an explicit wall-breaker cannot.
            guard !rule.destroyedByNormalWeapons || rule.destroyedByWallBreakers else { throw InvalidGrid.invalidRule }
            let expected: VisualKind
            switch (rule.blocksMovement, rule.blocksProjectiles, rule.concealsHeroes) {
            case (false, false, false): expected = .floor
            case (true, true, false): expected = .wall
            case (false, false, true): expected = .bush
            case (true, false, false): expected = .water
            default: throw InvalidGrid.invalidRule
            }
            let shotPassableFence = rule.blocksMovement && !rule.blocksProjectiles && !rule.concealsHeroes && rule.visualKind == .wall
            guard rule.visualKind == expected || shotPassableFence else { throw InvalidGrid.invalidRule }
            indices[rule.id] = index
        }
        var resolved: [Int] = []
        resolved.reserveCapacity(count)
        for id in terrainIDs {
            guard let index = indices[id] else { throw InvalidGrid.missingRule }
            resolved.append(index)
        }
        self.width = width; self.height = height; self.rules = rules
        self.cellRules = resolved; self.sourceSymbols = sourceSymbols
        self.destroyed = Array(repeating: false, count: count)
        self.bushPatches = Array(repeating: 0, count: count)
        var mask = Array(repeating: false, count: count)
        for cell in excludedCells {
            guard cell.x >= 0, cell.y >= 0, cell.x < width, cell.y < height else { throw InvalidGrid.dimensions }
            let index = cell.y * width + cell.x
            guard !mask[index] else { throw InvalidGrid.cellCount }
            mask[index] = true
        }
        self.excluded = mask
        rebuildBushPatches()
    }

    public func contains(_ cell: ArenaImportedMap.Cell) -> Bool {
        cell.x >= 0 && cell.x < width && cell.y >= 0 && cell.y < height
    }

    public func coordinate(at point: V2) -> ArenaImportedMap.Cell? {
        guard point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.y >= 0, point.x < Double(width), point.y < Double(height) else { return nil }
        return ArenaImportedMap.Cell(Int(point.x.rounded(.down)), Int(point.y.rounded(.down)))
    }

    public func cell(_ x: Int, _ y: Int) -> CellSnapshot? {
        let cell = ArenaImportedMap.Cell(x, y)
        guard contains(cell) else { return nil }
        let index = y * width + x, rule = rules[cellRules[index]]
        let removed = destroyed[index]
        return CellSnapshot(cell: cell, sourceSymbol: sourceSymbols[index], terrainID: rule.id,
                            visualKind: removed ? .floor : rule.visualKind, isDestroyed: removed,
                            blocksMovement: excluded[index] || (!removed && rule.blocksMovement),
                            blocksProjectiles: excluded[index] || (!removed && rule.blocksProjectiles),
                            concealsHeroes: !excluded[index] && !removed && rule.concealsHeroes,
                            isVisible: rule.isVisible, isOutOfBounds: excluded[index])
    }

    public func cell(at point: V2) -> CellSnapshot? {
        guard let coordinate = coordinate(at: point) else { return nil }
        return cell(coordinate.x, coordinate.y)
    }

    /// Outside the grid is solid. Non-finite points are rejected before Int conversion.
    public func blocksMovement(_ x: Int, _ y: Int) -> Bool { cell(x, y)?.blocksMovement ?? true }
    public func blocksMovement(at point: V2) -> Bool { cell(at: point)?.blocksMovement ?? true }
    public func blocksProjectiles(_ x: Int, _ y: Int) -> Bool { cell(x, y)?.blocksProjectiles ?? true }
    public func blocksProjectiles(at point: V2) -> Bool { cell(at: point)?.blocksProjectiles ?? true }
    public func concealsHeroes(at point: V2) -> Bool { cell(at: point)?.concealsHeroes ?? false }

    /// Full-cell circle collision. Imported rules with nonzero collision insets are
    /// rejected by the schema until their source coordinate convention is supported.
    public func intersectsMovement(at point: V2, radius: Double) -> Bool {
        guard point.x.isFinite, point.y.isFinite, radius.isFinite, radius >= 0,
              point.x - radius >= 0, point.y - radius >= 0,
              point.x + radius < Double(width), point.y + radius < Double(height) else { return true }
        if radius == 0 { return blocksMovement(at: point) }
        let minX = Int((point.x - radius).rounded(.down)), maxX = Int((point.x + radius).rounded(.down))
        let minY = Int((point.y - radius).rounded(.down)), maxY = Int((point.y + radius).rounded(.down))
        for y in minY...maxY {
            for x in minX...maxX where blocksMovement(x, y) {
                let nearestX = min(max(point.x, Double(x)), Double(x + 1))
                let nearestY = min(max(point.y, Double(y)), Double(y + 1))
                let dx = point.x - nearestX, dy = point.y - nearestY
                if dx * dx + dy * dy < radius * radius { return true }
            }
        }
        return false
    }

    public func bushID(at point: V2) -> Int {
        guard let cell = coordinate(at: point) else { return 0 }
        return bushPatches[cell.y * width + cell.x]
    }

    public func sameBush(_ first: V2, _ second: V2) -> Bool {
        let firstID = bushID(at: first)
        return firstID > 0 && firstID == bushID(at: second)
    }

    public func canDestroy(_ cell: ArenaImportedMap.Cell, cause: DestructionCause) -> Bool {
        guard contains(cell) else { return false }
        let index = cell.y * width + cell.x
        return !excluded[index] && !destroyed[index] && rules[cellRules[index]].canBeDestroyed(by: cause)
    }

    /// Returns true only on an actual state change. Destruction is idempotent.
    @discardableResult
    public mutating func destroy(_ cell: ArenaImportedMap.Cell, cause: DestructionCause) -> Bool {
        guard canDestroy(cell, cause: cause) else { return false }
        let index = cell.y * width + cell.x
        destroyed[index] = true
        revision &+= 1
        if rules[cellRules[index]].concealsHeroes { rebuildBushPatches() }
        return true
    }

    /// Cell-center radius, matching the reviewed source destruction-area convention.
    /// Callers must use a wall-breaking projectile/effect flag, not "any super".
    @discardableResult
    public mutating func destroy(inRadius radius: Double, around point: V2,
                                 cause: DestructionCause) -> [ArenaImportedMap.Cell] {
        guard radius.isFinite, radius >= 0, point.x.isFinite, point.y.isFinite else { return [] }
        var changed: [ArenaImportedMap.Cell] = []
        var bushesChanged = false
        for y in 0..<height {
            for x in 0..<width {
                let cell = ArenaImportedMap.Cell(x, y)
                let dx = Double(x) + 0.5 - point.x, dy = Double(y) + 0.5 - point.y
                guard hypot(dx, dy) <= radius, canDestroy(cell, cause: cause) else { continue }
                let index = y * width + x
                destroyed[index] = true
                bushesChanged = bushesChanged || rules[cellRules[index]].concealsHeroes
                changed.append(cell)
            }
        }
        if !changed.isEmpty { revision &+= 1 }
        if bushesChanged { rebuildBushPatches() }
        return changed
    }

    /// Overtime uses its own source flag, including walls immune to wall-breakers.
    @discardableResult
    public mutating func destroyForOvertime() -> [ArenaImportedMap.Cell] {
        destroy(inRadius: hypot(Double(width), Double(height)), around: .zero, cause: .overtime)
    }

    private mutating func rebuildBushPatches() {
        bushPatches = Array(repeating: 0, count: cellRules.count)
        var nextID = 1
        for start in cellRules.indices where !excluded[start] && !destroyed[start] && rules[cellRules[start]].concealsHeroes && bushPatches[start] == 0 {
            bushPatches[start] = nextID
            var queue = [start], head = 0
            while head < queue.count {
                let index = queue[head]; head += 1
                let x = index % width, y = index / width
                for next in [ArenaImportedMap.Cell(x - 1, y), ArenaImportedMap.Cell(x + 1, y),
                             ArenaImportedMap.Cell(x, y - 1), ArenaImportedMap.Cell(x, y + 1)] where contains(next) {
                    let ni = next.y * width + next.x
                    if !excluded[ni], !destroyed[ni], rules[cellRules[ni]].concealsHeroes, bushPatches[ni] == 0 {
                        bushPatches[ni] = nextID; queue.append(ni)
                    }
                }
            }
            nextID += 1
        }
    }
}
