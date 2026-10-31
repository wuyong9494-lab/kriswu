import Foundation

extension ArenaGame {
    public var matchDuration: Double { importedMatchRules?.matchDuration ?? mode.duration }
    public var respawnDelay: Double { importedMatchRules?.respawnDelay ?? mode.respawnDelay }

    public func collides(_ point: V2, radius: Double = ArenaGame.fighterRadius, ball: Bool = false) -> Bool {
        guard let terrainState else { return map.collides(point, radius: radius, ball: ball) }
        return terrainState.intersectsMovement(at: point, radius: radius) || (!ball && importedSafeCollision(at: point, radius: radius))
    }

    public func blocksProjectiles(_ point: V2) -> Bool {
        terrainState?.blocksProjectiles(at: point) ?? map.blocks(point)
    }

    public func inBush(_ point: V2) -> Bool {
        terrainState?.concealsHeroes(at: point) ?? map.inBush(point)
    }

    public func sameBush(_ first: V2, _ second: V2) -> Bool {
        terrainState?.sameBush(first, second) ?? map.sameBush(first, second)
    }

    public func lineOfSight(_ first: V2, _ second: V2) -> Bool {
        guard terrainState != nil else { return map.lineOfSight(first, second) }
        let delta = second - first
        guard delta.length.isFinite else { return false }
        let steps = max(1, Int(ceil(delta.length / 0.15)))
        return (0...steps).allSatisfy { !blocksProjectiles(first + delta * (Double($0) / Double(steps))) }
    }

    public func nearestOpen(to point: V2, radius: Double = ArenaGame.fighterRadius) -> V2 {
        guard terrainState != nil else { return map.nearestOpen(to: point, radius: radius) }
        guard point.x.isFinite, point.y.isFinite else { return map.center }
        let bounded = V2(min(max(point.x, radius), Double(map.width) - radius - 0.001),
                         min(max(point.y, radius), Double(map.height) - radius - 0.001))
        if !collides(bounded, radius: radius) { return bounded }
        let x = Int(bounded.x), y = Int(bounded.y)
        for ring in 1...max(map.width, map.height) {
            for yy in max(0, y - ring)...min(map.height - 1, y + ring) {
                for xx in max(0, x - ring)...min(map.width - 1, x + ring) where abs(xx - x) == ring || abs(yy - y) == ring {
                    let candidate = V2(Double(xx) + 0.5, Double(yy) + 0.5)
                    if !collides(candidate, radius: radius) { return candidate }
                }
            }
        }
        return map.center
    }

    func terrainWalkingPosition(from start: V2, by delta: V2, radius: Double = fighterRadius) -> V2 {
        if terrainState == nil && radius == Self.fighterRadius { return Self.walk(from: start, by: delta, on: map) }
        guard delta.length.isFinite, delta.length <= 100, radius.isFinite, radius > 0 else { return start }
        let steps = max(1, Int(ceil(delta.length / 0.2)))
        let amount = delta * (1 / Double(steps))
        var point = start
        for _ in 0..<steps {
            let next = point + amount
            if !collides(next, radius: radius) { point = next; continue }
            let horizontal = V2(next.x, point.y), vertical = V2(point.x, next.y)
            if !collides(horizontal, radius: radius) { point = horizontal }
            else if !collides(vertical, radius: radius) { point = vertical }
        }
        return point
    }

    /// Route planning reads the same water/wall/destruction state as movement.
    public func path(from start: V2, to destination: V2) -> [V2] {
        guard let terrainState else { return map.path(from: start, to: destination) }
        let source = nearestOpen(to: start), target = nearestOpen(to: destination)
        let first = Int(source.y) * map.width + Int(source.x)
        let last = Int(target.y) * map.width + Int(target.x)
        if first == last { return [target] }
        var previous = Array(repeating: -1, count: map.width * map.height)
        previous[first] = first
        var queue = [first], cursor = 0
        while cursor < queue.count && previous[last] == -1 {
            let here = queue[cursor]; cursor += 1
            let x = here % map.width, y = here / map.width
            for (dx, dy) in [(0, -1), (-1, 0), (1, 0), (0, 1)] {
                let xx = x + dx, yy = y + dy
                guard !terrainState.blocksMovement(xx, yy),
                      !importedSafeCollision(at: V2(Double(xx) + 0.5, Double(yy) + 0.5), radius: Self.fighterRadius) else { continue }
                let next = yy * map.width + xx
                guard previous[next] == -1 else { continue }
                previous[next] = here; queue.append(next)
            }
        }
        guard previous[last] != -1 else { return [] }
        var points: [V2] = [], current = last
        while current != first {
            points.append(V2(Double(current % map.width) + 0.5, Double(current / map.width) + 0.5))
            current = previous[current]
        }
        return points.reversed()
    }

    @discardableResult
    public mutating func destroyTerrain(at point: V2, radius: Double,
                                        cause: ArenaTerrainState.DestructionCause) -> [ArenaImportedMap.Cell] {
        guard terrainState != nil else { return [] }
        return terrainState!.destroy(inRadius: radius, around: point, cause: cause)
    }

    /// Traverse every crossed cell so a fast projectile cannot skip a thin wall.
    /// Destruction affects later movement/projectiles in this same simulation step.
    mutating func traceTerrain(from start: V2, to end: V2, cause: ArenaTerrainState.DestructionCause) -> Bool {
        guard terrainState != nil else { return blocksProjectiles(end) }
        let delta = end - start
        guard delta.length.isFinite else { return true }
        let steps = max(1, Int(ceil(delta.length / 0.1)))
        for index in 0...steps {
            let point = start + delta * (Double(index) / Double(steps))
            guard let cell = terrainState!.coordinate(at: point) else { return true }
            _ = terrainState!.destroy(cell, cause: cause)
            if terrainState!.blocksProjectiles(at: point) { return true }
        }
        return false
    }

    mutating func updateImportedBounty() {
        guard var objective = importedBounty else { return }
        if objective.blueStarAvailable,
           let fighter = fighters.first(where: { $0.alive && $0.pos.distance(to: map.center) < 0.75 }),
           objective.claimBlueStar(by: fighter.id) {
            events.append(.pickup(fighter: fighter.id))
        }
        if time >= matchDuration { _ = objective.finishAtTimeLimit() }
        importedBounty = objective
        synchronizeImportedBounty()
    }

    mutating func synchronizeImportedBounty() {
        guard let objective = importedBounty else { return }
        score = objective.score
        for index in fighters.indices where objective.bounties.indices.contains(index) {
            fighters[index].stars = objective.bounties[index]
        }
        if let outcome = objective.result {
            switch outcome {
            case .winner(let team): result = .team(team)
            case .draw: result = .draw
            }
        }
    }
}
