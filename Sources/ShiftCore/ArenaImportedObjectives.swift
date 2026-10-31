import Foundation

/// Runtime hooks for explicitly reviewed source-map objects. This file contains
/// no source maps or client payload. The caller admits a validated RuntimePlan
/// and supplies the exact roster instead of recovering teams from row order.
extension ArenaGame {
    mutating func configureImportedObjectives(_ plan: ArenaImportedMap.RuntimePlan,
                                              entrants: [Entrant], seed: UInt64) throws {
        let assignments = try plan.initialSpawnAssignments(seed: seed)
        guard entrants.count == fighters.count,
              assignments.count == entrants.count else {
            throw ArenaImportedMap.ValidationFailure(issues: [.init(.participantMismatch, "entrants", "The explicit source roster and spawn assignments differ.")])
        }
        var slots: [Int: Int] = [:]
        var positions: [(team: Int, point: V2)] = []
        for entrant in entrants {
            let slot = slots[entrant.team, default: 0]
            slots[entrant.team] = slot + 1
            guard let assignment = assignments.first(where: { $0.team == entrant.team && $0.slot == slot }) else {
                throw ArenaImportedMap.ValidationFailure(issues: [.init(.invalidSpawnGroups, "spawns", "No explicit source spawn exists for this team and slot.")])
            }
            positions.append((entrant.team, assignment.position))
        }
        // Validate all extra state before changing the game. The public throwing
        // initializer never returns a partially configured imported match.
        let newZone: ArenaZoneObjectiveState?
        if plan.mode == .zone {
            guard let captureSeconds = plan.matchRules?.zoneCaptureSeconds else {
                throw ArenaImportedMap.ValidationFailure(issues: [.init(.unresolvedObjectives, "mode.matchRules.zoneCaptureSeconds", "A source capture match needs an explicit timing policy.")])
            }
            newZone = try ArenaZoneObjectiveState(zones: plan.objectives.captureZones ?? [], captureSeconds: captureSeconds)
        } else { newZone = nil }
        var newChests: [Chest] = []
        if plan.mode == .heist {
            guard let health = plan.matchRules?.safeBaseHealth,
                  let radius = plan.matchRules?.safeCollisionRadius,
                  health > 0, radius.isFinite, radius > 0 else {
                throw ArenaImportedMap.ValidationFailure(issues: [.init(.unresolvedObjectives, "mode.matchRules", "A source safe needs explicit health and collision radius.")])
            }
            // Keep map.chestSpots order, because existing renderer/projectile
            // indexes refer to that array. Ownership was checked by the adapter.
            newChests = plan.map.chestSpots.map {
                Chest(team: $0.team, center: $0.center, health: health, maxHealth: health)
            }
        }
        let sourceBoxes = try plan.seededPowerBoxes(seed: seed)
        importedMapPlan = plan
        importedZone = newZone
        importedOvertimeApplied = false
        teamKills = Array(repeating: 0, count: max(plan.modeBinding.teamCount, 2))
        score = Array(repeating: 0, count: max(plan.modeBinding.teamCount, 2))
        for index in fighters.indices {
            fighters[index].team = positions[index].team
            fighters[index].pos = positions[index].point
            fighters[index].facing = (plan.map.center - positions[index].point).normalized
        }
        if plan.mode == .heist { chests = newChests }
        if plan.mode == .showdown || plan.mode == .duo {
            // Empty is meaningful: a source map with no selected crates must
            // not fall back to the classic procedural ten-box layout.
            boxes = sourceBoxes.map { PowerBox(pos: $0.cell.center, health: $0.health) }
            cubes.removeAll()
        }
        if let newZone { zoneProgress = newZone.teamProgress }
    }

    /// Initial placement and round/goal reset use 1/2 or the reviewed survival
    /// grouping. No nearest-open fallback changes a source spawn coordinate.
    public func importedInitialSpawn(for fighterIndex: Int) -> V2? {
        guard let plan = importedMapPlan else { return nil }
        return importedSpawn(for: fighterIndex, groups: plan.spawns)
    }

    /// Death respawns use a separate 6/7 group when the source mode enables it.
    /// Modes without a secondary group explicitly reuse their initial group.
    public func importedRespawn(for fighterIndex: Int) -> V2? {
        guard let plan = importedMapPlan else { return nil }
        return importedSpawn(for: fighterIndex, groups: plan.respawns.isEmpty ? plan.spawns : plan.respawns)
    }

    private func importedSpawn(for index: Int, groups: [ArenaImportedMap.SpawnGroup]) -> V2? {
        guard fighters.indices.contains(index) else { return nil }
        let team = fighters[index].team
        let slot = fighters[..<index].filter { $0.team == team }.count
        guard let group = groups.first(where: { $0.team == team }), group.cells.indices.contains(slot) else { return nil }
        return group.cells[slot].center
    }

    public func chestCollisionRadius(_ index: Int) -> Double {
        guard chests.indices.contains(index) else { return 0 }
        return importedMapPlan != nil ? importedMatchRules?.safeCollisionRadius ?? 0 : 1.3
    }

    /// Safe actors are circular and disappear from collision when destroyed;
    /// their source marker remains ordinary ground in the mutable terrain grid.
    public func importedSafeIndex(at point: V2, radius: Double = 0, excludingTeam: Int? = nil) -> Int? {
        guard importedMapPlan != nil, mode == .heist, point.x.isFinite, point.y.isFinite,
              radius.isFinite, radius >= 0 else { return nil }
        return chests.indices.first { index in
            chests[index].health > 0 && chests[index].team != excludingTeam
                && point.distance(to: chests[index].center) < radius + chestCollisionRadius(index)
        }
    }

    public func importedSafeCollision(at point: V2, radius: Double) -> Bool {
        guard importedMapPlan != nil, mode == .heist else { return false }
        guard point.x.isFinite, point.y.isFinite, radius.isFinite, radius >= 0 else { return true }
        return importedSafeIndex(at: point, radius: radius) != nil
    }

    /// Swept circle query prevents a fast projectile from crossing a safe
    /// between endpoints. Terrain ordering must still be checked by the caller.
    public func importedSafeHit(from start: V2, to end: V2, projectileRadius: Double,
                                excludingTeam: Int? = nil) -> (index: Int, point: V2)? {
        guard importedMapPlan != nil, mode == .heist,
              start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite,
              projectileRadius.isFinite, projectileRadius >= 0 else { return nil }
        let delta = end - start
        let distanceSquared = delta.x * delta.x + delta.y * delta.y
        guard distanceSquared.isFinite else { return nil }
        var first: (index: Int, fraction: Double)?
        for index in chests.indices where chests[index].health > 0 && chests[index].team != excludingTeam {
            let offset = start - chests[index].center
            let radius = projectileRadius + chestCollisionRadius(index)
            let c = offset.x * offset.x + offset.y * offset.y - radius * radius
            let fraction: Double
            if c <= 0 { fraction = 0 }
            else {
                guard distanceSquared > 0 else { continue }
                let b = 2 * (offset.x * delta.x + offset.y * delta.y)
                let discriminant = b * b - 4 * distanceSquared * c
                guard discriminant >= 0 else { continue }
                fraction = (-b - sqrt(discriminant)) / (2 * distanceSquared)
                guard (0...1).contains(fraction) else { continue }
            }
            if first == nil || fraction < first!.fraction { first = (index, fraction) }
        }
        return first.map { ($0.index, start + delta * $0.fraction) }
    }

    public func powerBoxCollisionRadius(_ box: PowerBox) -> Double {
        importedPowerBoxDefinition(at: box.pos)?.collisionRadius ?? PowerBox.radius
    }

    public func powerBoxMaximumHealth(_ box: PowerBox) -> Int {
        importedPowerBoxDefinition(at: box.pos)?.health ?? PowerBox.fullHealth
    }

    private func importedPowerBoxDefinition(at point: V2) -> ArenaImportedMap.PowerBoxPlacement? {
        importedMapPlan?.objectives.powerBoxes?.first { $0.cell.center == point }
    }

    /// Returns true when this source match owns capture scoring, including after
    /// it has finished. The caller must skip the classic single contested circle.
    @discardableResult
    mutating func updateImportedZones(_ delta: Double) -> Bool {
        guard var objective = importedZone else { return false }
        _ = objective.update(delta: delta, occupants: fighters.filter(\.alive).map {
            ArenaZoneObjectiveState.Occupant(team: $0.team, position: $0.pos)
        })
        if time >= matchDuration { _ = objective.finishAtTimeLimit() }
        importedZone = objective
        zoneProgress = objective.teamProgress
        if result == nil, let outcome = objective.result {
            switch outcome {
            case .winner(let team): result = .team(team)
            case .draw: result = .draw
            }
        }
        return true
    }

    public func importedZoneTarget(for team: Int, from point: V2) -> V2? {
        importedZone?.targetZone(for: team, from: point)?.center
    }

    /// The adapter supplies an explicit phase time and the source terrain flags.
    /// A later frame never repeats the world mutation, even if no tiles changed.
    @discardableResult
    mutating func updateImportedOvertime() -> Bool {
        guard mode == .ball, importedMapPlan != nil, !importedOvertimeApplied,
              let begins = importedMatchRules?.overtimeStartsAt,
              time.isFinite, time >= begins, terrainState != nil else { return false }
        _ = terrainState!.destroyForOvertime()
        importedOvertimeApplied = true
        return true
    }

    public var usesImportedGoldenGoal: Bool {
        importedOvertimeApplied && importedMatchRules?.overtimeGoldenGoal == true
    }
}
