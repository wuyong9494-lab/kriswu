import Foundation

public struct ArenaSourceChargeMotion: Codable, Equatable, Sendable {
    public var definition: ArenaSourceCharge
    public var remaining: Double
    public var hit: Set<Int> = []
}

public struct ArenaSourceSlow: Codable, Equatable, Sendable {
    public var id: String
    public var remaining: Double
    public var absoluteReduction: Double
    public var fractionReduction: Double
}

public struct ArenaSourceLiveArea: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var owner: Int
    public var team: Int
    public var spawn: ArenaSourceAreaSpawn
    public var state: ArenaSourceAreaState
    public var damageMultiplier: Double
    public var lastUpdateTime: Double
    public var position: V2 { spawn.position }
    public var radius: Double { spawn.area.radius }
    public var kind: String { spawn.area.kind }
}

struct ArenaSourceVolleyKey: Codable, Equatable, Hashable, Sendable {
    var owner: Int
    var skillID: String
    var role: ArenaSourceSkillRole
    var activationID: UInt64
    var volleyIndex: Int
}

struct ArenaSourceHitWindow: Codable, Equatable, Sendable {
    var targets: Set<Int>
    var expires: Double
}

struct ArenaSourceAreaTargetKey: Codable, Equatable, Hashable, Sendable {
    var owner: Int
    var areaID: String
    var target: Int
}

extension ArenaGame {
    public enum SourceConfigurationError: Error, LocalizedError {
        case unsupportedHero(String)
        case unsupportedMode
        public var errorDescription: String? {
            switch self {
            case .unsupportedHero(let name): return "\(name)的完整技能规则尚未适配，不能进入对战。"
            case .unsupportedMode: return "原版英雄暂不支持此玩法的阵容与升级规则。"
            }
        }
    }

    static func validateSourceRoster(_ entrants: [Entrant], mode: Mode) throws {
        for hero in entrants.compactMap(\.sourceHero) where !hero.canPlay {
            throw SourceConfigurationError.unsupportedHero(hero.name)
        }
        if entrants.contains(where: { $0.sourceHero != nil }), mode == .duel || mode == .boss {
            throw SourceConfigurationError.unsupportedMode
        }
    }

    /// Source actions run their own fixed-tick dispatcher. Classic loadouts,
    /// player damage advantages and classic attack switches are not involved.
    mutating func updateSourceFighter(_ i: Int, input: ArenaInput, dt: Double) {
        guard dt.isFinite, dt > 0, dt <= 1, fighters[i].sourceHero?.canPlay == true else { return }
        tickStatus(i, dt)
        if fighters[i].shield > 0 { fighters[i].shield = max(0, fighters[i].shield - dt) }
        if fighters[i].sourceCharge != nil {
            updateSourceCharge(i, dt: dt)
        } else {
            let blocked = fighters[i].sourceWeapon?.blocksMovement == true || fighters[i].sourceUltimate?.blocksMovement == true
            let move = blocked ? V2.zero : input.move.clamped(to: 1)
            fighters[i].moving = move * moveSpeed(fighters[i])
            if move.length > 0.05 {
                walk(i, by: fighters[i].moving * dt)
                if input.attack == nil && input.special == nil { fighters[i].facing = move.normalized }
            }
        }
        if ball?.carrier == i {
            if let aim = input.special, fighters[i].superCharge >= 1 { kick(i, aim, power: true) }
            else if let aim = input.attack { kick(i, aim, power: false) }
        } else if fighters[i].sourceCharge == nil {
            // Compatible dispatch is sequential; a cast cannot emit two skills
            // at once or silently use the legacy hero's special ability.
            let active = fighters[i].sourceWeapon?.active == true || fighters[i].sourceUltimate?.active == true
            if !active, let aim = input.special, fighters[i].superCharge >= 1 {
                activateSourceSkill(i, role: .ultimate, aim: aim)
            } else if !active, let aim = input.attack {
                activateSourceSkill(i, role: .weapon, aim: aim)
            }
        }
        let origin = fighters[i].pos
        let weaponEvents = fighters[i].sourceWeapon?.advance(dt: dt, origin: origin) ?? []
        let ultimateEvents = fighters[i].sourceUltimate?.advance(dt: dt, origin: origin) ?? []
        applySourceEmissions(weaponEvents + ultimateEvents, owner: i)
        fighters[i].ammo = fighters[i].sourceWeapon?.ammo ?? 0
        fighters[i].cooldown = fighters[i].sourceWeapon?.cooldownRemaining ?? 0
        // Existing match regeneration is an explicit host-game compatibility
        // policy, independent of source weapon damage or super charge.
        if fighters[i].alive, time - max(fighters[i].lastHurt, fighters[i].lastAttack) > 3 {
            let gain = Int((Double(fighters[i].maxHealth) * 0.13 * dt).rounded(.up))
            fighters[i].health = min(fighters[i].maxHealth, fighters[i].health + gain)
        }
    }

    mutating func activateSourceSkill(_ i: Int, role: ArenaSourceSkillRole, aim: V2) {
        let resolved = aim.length > 0.001 ? aim : fighters[i].facing
        let emitted: [ArenaSourceEmission]
        do {
            if role == .weapon {
                guard fighters[i].sourceWeapon?.canActivate == true else { return }
                emitted = try fighters[i].sourceWeapon!.activate(origin: fighters[i].pos, aim: resolved)
            } else {
                guard fighters[i].sourceUltimate?.canActivate == true else { return }
                emitted = try fighters[i].sourceUltimate!.activate(origin: fighters[i].pos, aim: resolved)
                fighters[i].superCharge = 0
            }
        } catch { return }
        fighters[i].facing = resolved.normalized
        fighters[i].lastAttack = time
        events.append(role == .weapon ? .attack(fighter: i) : .special(fighter: i))
        applySourceEmissions(emitted, owner: i)
    }

    mutating func applySourceEmissions(_ emitted: [ArenaSourceEmission], owner: Int) {
        guard fighters.indices.contains(owner), fighters[owner].alive else { return }
        for emission in emitted {
            switch emission {
            case .projectile(let launch):
                spawnSourceProjectile(launch, owner: owner, team: fighters[owner].team)
            case .charge(let charge):
                fighters[owner].sourceCharge = ArenaSourceChargeMotion(definition: charge, remaining: charge.distance)
            case .area(let area): applySourceArea(area, owner: owner)
            case .finished: break
            }
        }
    }

    /// Unlike activation, a child projectile can spawn after its owner died.
    /// Snapshot the launch damage multiplier so losing cubes on death does not
    /// retroactively weaken already-launched source projectiles and areas.
    mutating func spawnSourceProjectile(_ launch: ArenaSourceLaunch, owner: Int, team: Int,
                                        damageMultiplier: Double? = nil) {
        guard fighters.indices.contains(owner), launch.projectile.isSupported else { return }
        let multiplier = damageMultiplier ?? Double(power(owner, 100_000)) / 100_000
        var projectile = Projectile(id: nextProjectile, owner: owner, team: team,
            pos: launch.origin, velocity: launch.direction * launch.projectile.speed, rangeLeft: launch.range,
            damage: Int((Double(launch.damage) * multiplier).rounded()), radius: launch.projectile.radius,
            pierce: launch.projectile.piercesCharacters, charges: false, isSuper: launch.role == .ultimate)
        projectile.sourceLaunch = launch
        projectile.sourceBouncesRemaining = launch.projectile.bounces
        projectile.sourceElapsed = 0
        projectile.sourceDamageMultiplier = multiplier
        projectile.terrainDestruction = launch.projectile.wallBreak ? .wallBreaker : .normalWeapon
        if launch.projectile.indirect == true, let target = launch.target, let impactTime = launch.flightDuration {
            let flight = max(ArenaSourceSkillState.tickDuration,
                launch.projectile.constantFlightTime ?? launch.origin.distance(to: target) / launch.projectile.speed)
            projectile.lob = Projectile.Lob(from: launch.origin, to: target, duration: flight, elapsed: 0,
                blast: launch.projectile.areaEffects.map(\.radius).max() ?? 0)
            projectile.rangeLeft = impactTime
        }
        projectiles.append(projectile)
        nextProjectile += 1
        if let key = sourceVolleyKey(projectile) {
            let travel = (launch.range + Double(launch.projectile.bounces) * launch.projectile.bounceRangeAdd) / launch.projectile.speed
            let lifetime = max(launch.flightDuration ?? 0, travel) + 2
            var entry = sourceVolleyHits[key] ?? ArenaSourceHitWindow(targets: [], expires: time)
            entry.expires = max(entry.expires, time + min(600, lifetime))
            sourceVolleyHits[key] = entry
        }
    }

    func sourceVolleyKey(_ projectile: Projectile) -> ArenaSourceVolleyKey? {
        guard let launch = projectile.sourceLaunch, launch.projectile.damageOncePerVolley == true,
              let activation = launch.activationID else { return nil }
        return ArenaSourceVolleyKey(owner: projectile.owner, skillID: launch.skillID, role: launch.role,
            activationID: activation, volleyIndex: launch.volleyIndex)
    }

    mutating func claimSourceHit(_ target: Int, projectile: Projectile) -> Bool {
        guard let key = sourceVolleyKey(projectile) else { return true }
        var entry = sourceVolleyHits[key] ?? ArenaSourceHitWindow(targets: [], expires: time + 2)
        guard !entry.targets.contains(target) else { return false }
        entry.targets.insert(target)
        entry.expires = max(entry.expires, time + 2)
        sourceVolleyHits[key] = entry
        return true
    }

    @discardableResult
    mutating func sourceDamage(_ target: Int, amount: Int, owner: Int, role: ArenaSourceSkillRole,
                               chargeDamage: Int, pushback: Double, direction: V2) -> Int {
        guard fighters.indices.contains(target), fighters[target].alive, fighters.indices.contains(owner),
              let hero = fighters[owner].sourceHero else { return 0 }
        let before = fighters[target].health
        hurt(target, amount, by: owner, charges: false)
        if fighters[target].health < before {
            let multiplier = role == .weapon ? hero.weaponChargePerDamage : hero.ultimateChargePerDamage
            fighters[owner].superCharge = min(1, fighters[owner].superCharge + Double(max(chargeDamage, 0)) * multiplier)
        }
        if fighters[target].alive, pushback > 0 {
            fighters[target].pos = walkingPosition(from: fighters[target].pos,
                by: direction.normalized * min(pushback, 20), radius: Self.hitRadius(fighters[target]))
        }
        return max(0, before - fighters[target].health)
    }

    mutating func applySourceArea(_ spawn: ArenaSourceAreaSpawn, owner: Int, damageMultiplier: Double? = nil) {
        guard spawn.area.isSupported, fighters.indices.contains(owner) else { return }
        let team = fighters[owner].team
        if spawn.area.wallBreak || spawn.area.rawSource["DestroysDecorations"]?.lowercased() == "true" {
            _ = destroyTerrain(at: spawn.position, radius: spawn.area.radius,
                cause: spawn.area.wallBreak ? .wallBreaker : .normalWeapon)
        }
        events.append(.explosion(at: spawn.position, radius: spawn.area.radius))
        if let strength = spawn.area.ownPushback, strength > 0, fighters[owner].alive,
           fighters[owner].pos.distance(to: spawn.position) < spawn.area.radius + Self.hitRadius(fighters[owner]) {
            let direction = (fighters[owner].pos - spawn.position).normalized
            fighters[owner].pos = walkingPosition(from: fighters[owner].pos,
                by: direction * min(strength, 20), radius: Self.hitRadius(fighters[owner]))
        }
        var live = ArenaSourceLiveArea(id: nextSourceArea, owner: owner, team: team, spawn: spawn,
            state: ArenaSourceAreaState(definition: spawn.area),
            damageMultiplier: damageMultiplier ?? Double(power(owner, 100_000)) / 100_000,
            lastUpdateTime: time)
        nextSourceArea += 1
        resolveSourceArea(&live)
        if !live.state.expired { sourceAreas.append(live) }
    }

    mutating func updateSourceAreas(dt: Double) {
        guard dt.isFinite, dt >= 0, dt <= 1 else { return }
        sourceVolleyHits = sourceVolleyHits.filter { $0.value.expires > time }
        sourceSharedAreaCooldowns = sourceSharedAreaCooldowns.filter { $0.value > time }
        let activeAreas = sourceAreas
        sourceAreas.removeAll(keepingCapacity: true)
        for var live in activeAreas {
            live.state.advance(dt: max(0, time - live.lastUpdateTime))
            live.lastUpdateTime = time
            guard !live.state.expired else { continue }
            resolveSourceArea(&live)
            sourceAreas.append(live)
        }
    }

    mutating func resolveSourceArea(_ live: inout ArenaSourceLiveArea) {
        let spawn = live.spawn
        var targets = fighters.indices.filter { fighters[$0].alive && fighters[$0].team != live.team
            && fighters[$0].pos.distance(to: spawn.position) < spawn.area.radius + Self.hitRadius(fighters[$0]) }
        targets += boxes.indices.filter { boxes[$0].health > 0
            && boxes[$0].pos.distance(to: spawn.position) < spawn.area.radius + powerBoxCollisionRadius(boxes[$0]) }.map { -1000 - $0 }
        targets += chests.indices.filter { chests[$0].health > 0 && chests[$0].team != live.team
            && chests[$0].center.distance(to: spawn.position) < spawn.area.radius + chestCollisionRadius($0) }.map { -2000 - $0 }
        targets += turrets.filter { $0.health > 0 && $0.team != live.team
            && $0.pos.distance(to: spawn.position) < spawn.area.radius + Turret.radius }.map { -1_000_000 - $0.id }
        let cooldown = spawn.area.sharedTargetCooldown ?? 0
        let eligible = targets.filter { target in
            cooldown <= 0 || (sourceSharedAreaCooldowns[ArenaSourceAreaTargetKey(owner: live.owner,
                areaID: spawn.area.id, target: target)] ?? 0) <= time
        }
        let amount = Int((Double(spawn.damage) * live.damageMultiplier).rounded())
        for target in live.state.damageTargets(eligible) {
            if target >= 0 {
                sourceDamage(target, amount: amount, owner: live.owner, role: spawn.role,
                    chargeDamage: spawn.chargeDamage, pushback: spawn.area.pushback,
                    direction: fighters[target].pos - spawn.position)
            } else if target <= -1_000_000 {
                if let index = turrets.firstIndex(where: { $0.id == -1_000_000 - target }) { turrets[index].health -= amount }
            } else if target <= -2000 {
                hitChest(-2000 - target, amount, by: live.owner)
            } else {
                hitBox(-1000 - target, amount)
            }
            if cooldown > 0 {
                sourceSharedAreaCooldowns[ArenaSourceAreaTargetKey(owner: live.owner, areaID: spawn.area.id, target: target)] = time + cooldown
            }
        }
        if let status = spawn.area.statusEnemy {
            for target in live.state.statusTargets(targets.filter { $0 >= 0 }) { applySourceSlow(status, target: target) }
        }
        if let explosion = live.state.takeBulletExplosion() {
            for (index, direction) in explosion.directions().enumerated() {
                var launch = ArenaSourceLaunch(skillID: spawn.skillID + "/" + spawn.area.id, role: spawn.role,
                    projectile: explosion.projectile, origin: spawn.position, direction: direction,
                    range: explosion.range, damage: spawn.damage, chargeDamage: spawn.chargeDamage,
                    volleyIndex: 0, pelletIndex: index)
                launch.activationID = UInt64(live.id)
                spawnSourceProjectile(launch, owner: live.owner, team: live.team, damageMultiplier: live.damageMultiplier)
            }
        }
    }

    mutating func applySourceSlow(_ definition: ArenaSourceStatusEffect, target: Int) {
        guard definition.isSupported, fighters.indices.contains(target), fighters[target].alive else { return }
        var active = fighters[target].sourceSlows ?? []
        let slow = ArenaSourceSlow(id: definition.id, remaining: definition.duration,
            absoluteReduction: definition.speedReductionAbsolute, fractionReduction: definition.speedReductionFraction)
        if let index = active.firstIndex(where: { $0.id == definition.id }) {
            if definition.refreshable { active[index] = slow }
        } else { active.append(slow) }
        fighters[target].sourceSlows = active
    }

    mutating func tickSourceSlow(_ target: Int, dt: Double) {
        guard dt.isFinite, dt > 0, var active = fighters[target].sourceSlows else { return }
        for index in active.indices { active[index].remaining -= dt }
        active.removeAll { $0.remaining <= 1e-9 }
        fighters[target].sourceSlows = active.isEmpty ? nil : active
    }

    mutating func clearSourceTransientEffects() {
        sourceAreas.removeAll()
        sourceVolleyHits.removeAll()
        sourceSharedAreaCooldowns.removeAll()
        for index in fighters.indices { fighters[index].sourceSlows = nil }
    }

    mutating func healSourceLifeSteal(_ owner: Int, dealt: Int, fraction: Double) {
        guard fighters.indices.contains(owner), fighters[owner].alive, dealt > 0, fraction > 0 else { return }
        let heal = min(fighters[owner].maxHealth - fighters[owner].health, Int((Double(dealt) * fraction).rounded()))
        if heal > 0 {
            fighters[owner].health += heal
            events.append(.heal(target: owner, amount: heal))
        }
    }

    mutating func sourceImpact(_ projectile: Projectile) {
        guard let launch = projectile.sourceLaunch else { return }
        for area in launch.projectile.areaEffects {
            let damage = area.resolvedDamage(skillDamage: launch.damage)
            let chargeDamage = Int((Double(launch.chargeDamage) * (area.damageMultiplier ?? 1)).rounded())
            applySourceArea(ArenaSourceAreaSpawn(skillID: launch.skillID, role: launch.role, area: area,
                position: projectile.pos, damage: damage, chargeDamage: chargeDamage), owner: projectile.owner,
                damageMultiplier: projectile.sourceDamageMultiplier)
        }
    }

    /// Swept substeps prevent fast source bullets skipping thin walls or heroes.
    mutating func advanceSourceProjectile(_ projectile: inout Projectile, dt: Double) -> Bool {
        guard let launch = projectile.sourceLaunch, dt.isFinite, dt > 0, dt <= 1 else { return false }
        projectile.sourceElapsed = (projectile.sourceElapsed ?? 0) + dt
        if launch.projectile.indirect == true {
            guard var lob = projectile.lob, let impactTime = launch.flightDuration else { return false }
            lob.elapsed = min(lob.duration, projectile.sourceElapsed ?? 0)
            projectile.pos = V2.lerp(lob.from, lob.to, min(1, lob.elapsed / lob.duration))
            projectile.lob = lob
            if (projectile.sourceElapsed ?? 0) + 1e-9 >= impactTime {
                projectile.pos = lob.to
                sourceImpact(projectile)
                return false
            }
            return true
        }
        let travel = min(projectile.rangeLeft, projectile.velocity.length * dt)
        guard travel.isFinite, travel > 0, travel <= 100 else { sourceImpact(projectile); return false }
        let count = max(1, Int(ceil(travel / 0.08)))
        let distance = travel / Double(count)
        for _ in 0..<count {
            let previous = projectile.pos
            let proposed = previous + projectile.velocity.normalized * distance
            let cause = projectile.terrainDestruction ?? .normalWeapon
            if let safe = importedSafeHit(from: previous, to: proposed, projectileRadius: projectile.radius,
                excludingTeam: projectile.team), !projectile.hit.contains(-2000 - safe.index) {
                projectile.pos = proposed
                if launch.projectile.directDamage != false && claimSourceHit(-2000 - safe.index, projectile: projectile) {
                    hitChest(safe.index, projectile.damage, by: projectile.owner)
                }
                projectile.hit.append(-2000 - safe.index)
                if !projectile.pierce { sourceImpact(projectile); return false }
            }
            let outside = proposed.x < 0 || proposed.y < 0 || proposed.x >= Double(map.width) || proposed.y >= Double(map.height)
            if outside { sourceImpact(projectile); return false }
            let wall = launch.projectile.passesEnvironment == true ? false
                : (terrainState == nil ? blocksProjectiles(proposed) : traceTerrain(from: previous, to: proposed, cause: cause))
            if wall {
                if (projectile.sourceBouncesRemaining ?? 0) > 0 {
                    let xBlocked = blocksProjectiles(V2(proposed.x, previous.y))
                    let yBlocked = blocksProjectiles(V2(previous.x, proposed.y))
                    if xBlocked || !yBlocked { projectile.velocity.x *= -1 }
                    if yBlocked || !xBlocked { projectile.velocity.y *= -1 }
                    projectile.sourceBouncesRemaining = (projectile.sourceBouncesRemaining ?? 0) - 1
                    projectile.rangeLeft += launch.projectile.bounceRangeAdd
                    if launch.projectile.canHitAgainAfterBounce == true { projectile.hit.removeAll() }
                } else { sourceImpact(projectile); return false }
            } else { projectile.pos = proposed }
            projectile.rangeLeft -= distance
            for index in chests.indices where chests[index].health > 0 && chests[index].team != projectile.team
                && !projectile.hit.contains(-2000 - index) && chests[index].center.distance(to: projectile.pos) < (importedMatchRules?.safeCollisionRadius ?? 0.6) + projectile.radius {
                if launch.projectile.directDamage != false && claimSourceHit(-2000 - index, projectile: projectile) {
                    hitChest(index, projectile.damage, by: projectile.owner)
                }
                projectile.hit.append(-2000 - index)
                if !projectile.pierce { sourceImpact(projectile); return false }
            }
            for index in boxes.indices where boxes[index].health > 0 && !projectile.hit.contains(-1000 - index)
                && boxes[index].pos.distance(to: projectile.pos) < powerBoxCollisionRadius(boxes[index]) + projectile.radius {
                if launch.projectile.directDamage != false && claimSourceHit(-1000 - index, projectile: projectile) { hitBox(index, projectile.damage) }
                projectile.hit.append(-1000 - index)
                if !projectile.pierce { sourceImpact(projectile); return false }
            }
            for target in fighters.indices where fighters[target].alive && fighters[target].team != projectile.team
                && fighters[target].leap == nil
                && !projectile.hit.contains(target) && fighters[target].pos.distance(to: projectile.pos) < Self.hitRadius(fighters[target]) + projectile.radius {
                if launch.projectile.directDamage != false && claimSourceHit(target, projectile: projectile) {
                    let dealt = sourceDamage(target, amount: projectile.damage, owner: projectile.owner, role: launch.role,
                        chargeDamage: launch.chargeDamage, pushback: launch.projectile.pushback, direction: projectile.velocity)
                    healSourceLifeSteal(projectile.owner, dealt: dealt, fraction: launch.projectile.lifeStealFraction ?? 0)
                }
                projectile.hit.append(target)
                if !projectile.pierce { sourceImpact(projectile); return false }
            }
            for index in turrets.indices where turrets[index].health > 0 && turrets[index].team != projectile.team
                && !projectile.hit.contains(-1_000_000 - turrets[index].id)
                && turrets[index].pos.distance(to: projectile.pos) < Turret.radius + projectile.radius {
                let target = -1_000_000 - turrets[index].id
                if launch.projectile.directDamage != false && claimSourceHit(target, projectile: projectile) { turrets[index].health -= projectile.damage }
                projectile.hit.append(target)
                if !projectile.pierce { sourceImpact(projectile); return false }
            }
            if projectile.rangeLeft <= 1e-8 { sourceImpact(projectile); return false }
        }
        return true
    }

    mutating func updateSourceCharge(_ i: Int, dt: Double) {
        guard var motion = fighters[i].sourceCharge else { return }
        let source = motion.definition
        let length = min(motion.remaining, source.speed * dt)
        let count = max(1, Int(ceil(length / 0.1)))
        let distance = length / Double(count)
        for _ in 0..<count {
            let next = fighters[i].pos + source.direction * distance
            if source.wallBreak { _ = destroyTerrain(at: next, radius: Self.hitRadius(fighters[i]), cause: .wallBreaker) }
            if collides(next, radius: Self.hitRadius(fighters[i])) { motion.remaining = 0; break }
            fighters[i].pos = next
            fighters[i].moving = source.direction * source.speed
            motion.remaining -= distance
            for target in fighters.indices where fighters[target].alive && fighters[target].team != fighters[i].team
                && !motion.hit.contains(target) && fighters[target].pos.distance(to: next) < Self.hitRadius(fighters[target]) + Self.hitRadius(fighters[i]) {
                motion.hit.insert(target)
                sourceDamage(target, amount: power(i, source.damage), owner: i, role: source.role,
                    chargeDamage: source.chargeDamage, pushback: source.pushback, direction: source.direction)
            }
        }
        if motion.remaining <= 0.001 {
            fighters[i].sourceCharge = nil
            fighters[i].moving = .zero
            for area in source.endAreas {
                applySourceArea(ArenaSourceAreaSpawn(skillID: source.skillID, role: source.role, area: area,
                    position: fighters[i].pos, damage: area.resolvedDamage(skillDamage: source.damage),
                    chargeDamage: source.chargeDamage), owner: i)
            }
        } else { fighters[i].sourceCharge = motion }
    }
}
