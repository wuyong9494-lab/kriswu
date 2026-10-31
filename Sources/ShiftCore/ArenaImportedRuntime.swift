import Foundation

/// Deterministic selection from explicit source positions. This RNG is a local
/// compatibility policy; it does not claim to reproduce a remote server's seed.
public enum ArenaImportedRuntimeSelection {
    public struct SpawnAssignment: Equatable, Sendable {
        public let team: Int
        public let slot: Int
        public let cell: ArenaImportedMap.Cell
        public var position: V2 { cell.center }
    }

    public enum InvalidSelection: Error, Sendable { case invalidValue, duplicatePosition }

    private struct StableRandom {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9e3779b97f4a7c15
            var value = state
            value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
            value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
            return value ^ (value >> 31)
        }
        mutating func fraction() -> Double { Double(next() >> 11) / 9_007_199_254_740_992 }
    }

    public static func spawns(_ groups: [ArenaImportedMap.SpawnGroup], seed: UInt64,
                              shuffleSlots: Bool = false) throws -> [SpawnAssignment] {
        var teams = Set<Int>(), occupied = Set<ArenaImportedMap.Cell>()
        var result: [SpawnAssignment] = []
        for group in groups.sorted(by: { $0.team < $1.team }) {
            guard (0..<64).contains(group.team), teams.insert(group.team).inserted,
                  (1...64).contains(group.cells.count) else { throw InvalidSelection.invalidValue }
            var cells = group.cells
            for cell in cells {
                guard (0..<128).contains(cell.x), (0..<128).contains(cell.y) else { throw InvalidSelection.invalidValue }
                guard occupied.insert(cell).inserted else { throw InvalidSelection.duplicatePosition }
            }
            if shuffleSlots && cells.count > 1 {
                var random = StableRandom(state: seed ^ UInt64(group.team))
                for index in stride(from: cells.count - 1, through: 1, by: -1) {
                    let other = Int(random.next() % UInt64(index + 1))
                    cells.swapAt(index, other)
                }
            }
            result += cells.enumerated().map { SpawnAssignment(team: group.team, slot: $0.offset, cell: $0.element) }
        }
        return result
    }

    /// Each cell has its own deterministic draw, so sorting a source list or
    /// adding another candidate never changes a retained cell's random decision.
    public static func powerBoxes(_ candidates: [ArenaImportedMap.PowerBoxPlacement], seed: UInt64) throws -> [ArenaImportedMap.PowerBoxPlacement] {
        guard candidates.count <= 16_384 else { throw InvalidSelection.invalidValue }
        var seen = Set<ArenaImportedMap.Cell>()
        var result: [ArenaImportedMap.PowerBoxPlacement] = []
        for box in candidates.sorted(by: { $0.cell.y == $1.cell.y ? $0.cell.x < $1.cell.x : $0.cell.y < $1.cell.y }) {
            guard (0..<128).contains(box.cell.x), (0..<128).contains(box.cell.y),
                  (1...10_000_000).contains(box.health), box.collisionRadius.isFinite,
                  box.collisionRadius > 0, box.collisionRadius <= 2,
                  box.spawnProbability.isFinite, (0...1).contains(box.spawnProbability) else { throw InvalidSelection.invalidValue }
            guard seen.insert(box.cell).inserted else { throw InvalidSelection.duplicatePosition }
            let coordinateKey = UInt64(box.cell.y) << 32 | UInt64(box.cell.x)
            var random = StableRandom(state: seed ^ coordinateKey ^ 0x4352415445534545)
            if random.fraction() < box.spawnProbability { result.append(box) }
        }
        return result
    }
}

extension ArenaImportedMap.RuntimePlan {
    public func initialSpawnAssignments(seed: UInt64, shuffleSlots: Bool = false) throws -> [ArenaImportedRuntimeSelection.SpawnAssignment] {
        try ArenaImportedRuntimeSelection.spawns(spawns, seed: seed, shuffleSlots: shuffleSlots)
    }

    public func seededPowerBoxes(seed: UInt64) throws -> [ArenaImportedMap.PowerBoxPlacement] {
        try ArenaImportedRuntimeSelection.powerBoxes(objectives.powerBoxes ?? [], seed: seed)
    }
}

/// Each team owns independent progress in every source circle. Extra teammates do
/// not multiply capture speed, and opponents do not block simultaneous capture.
/// Capture seconds are supplied explicitly by the selected compatibility profile.
public struct ArenaZoneObjectiveState: Equatable, Sendable {
    public struct Occupant: Equatable, Sendable {
        public var team: Int
        public var position: V2
        public init(team: Int, position: V2) { self.team = team; self.position = position }
    }
    public enum InvalidRules: Error, Sendable { case invalidValue }
    public let zones: [ArenaImportedMap.CaptureZone]
    public let captureSeconds: Double
    /// [team][zone], from 0 to 1. Completed zones stay completed.
    public private(set) var fractions: [[Double]]
    public private(set) var result: ArenaImportedObjectiveResult?

    public init(zones: [ArenaImportedMap.CaptureZone], captureSeconds: Double) throws {
        guard (1...16).contains(zones.count), captureSeconds.isFinite, captureSeconds > 0,
              Set(zones.map(\.id)).count == zones.count,
              zones.allSatisfy({ !$0.id.isEmpty && $0.radius.isFinite && $0.radius > 0
                  && $0.center.x.isFinite && $0.center.y.isFinite }) else { throw InvalidRules.invalidValue }
        self.zones = zones; self.captureSeconds = captureSeconds
        self.fractions = Array(repeating: Array(repeating: 0, count: zones.count), count: 2)
    }

    public var teamProgress: [Double] {
        fractions.map { 100 * $0.reduce(0, +) / Double(zones.count) }
    }

    @discardableResult
    public mutating func update(delta: Double, occupants: [Occupant]) -> Bool {
        guard result == nil, delta.isFinite, delta >= 0,
              occupants.allSatisfy({ ($0.team == 0 || $0.team == 1) && $0.position.x.isFinite && $0.position.y.isFinite }) else { return false }
        for (index, zone) in zones.enumerated() {
            let teams = Set(occupants.filter { $0.position.distance(to: zone.center) < zone.radius }.map(\.team))
            for team in teams { fractions[team][index] = min(1, fractions[team][index] + delta / captureSeconds) }
        }
        let winners = [0, 1].filter { fractions[$0].allSatisfy { $0 >= 1 } }
        if winners.count == 2 { result = .draw }
        else if let winner = winners.first { result = .winner(team: winner) }
        return true
    }

    /// Bots can switch to another original capture circle after finishing one.
    public func targetZone(for team: Int, from position: V2) -> ArenaImportedMap.CaptureZone? {
        guard (0...1).contains(team), position.x.isFinite, position.y.isFinite else { return nil }
        return zones.enumerated().filter { fractions[team][$0.offset] < 1 }
            .min { $0.element.center.distance(to: position) < $1.element.center.distance(to: position) }?.element
    }

    @discardableResult
    public mutating func finishAtTimeLimit() -> ArenaImportedObjectiveResult {
        if let result { return result }
        let progress = teamProgress
        let outcome: ArenaImportedObjectiveResult = abs(progress[0] - progress[1]) < 1e-9
            ? .draw : .winner(team: progress[0] > progress[1] ? 0 : 1)
        result = outcome
        return outcome
    }
}
