import Foundation

/// Data-driven compatibility rules for source heroes. These types never select a
/// classic Brawler as a substitute for an unsupported source mechanic.
public enum ArenaSourceSkillRole: String, Codable, Equatable, Hashable, Sendable { case weapon, ultimate }

public struct ArenaSourceHero: Codable, Equatable, Sendable, Identifiable {
    /// Add a capability only after both the dispatcher and World adapter have
    /// meaningful verification. Decoding a source field alone does not enable it.
    public static let implementedCapabilities: Set<String> = [
        "projectile_straight", "pellet_fan", "timed_burst", "ground_charge",
        "impact_damage", "wall_break", "projectile_bounce", "indirect_flight",
        "projectile_fuse", "pass_environment", "life_steal", "damage_once_per_volley",
        "projectile_area_impact", "persistent_area", "dot_area", "slow_status",
        "self_pushback", "area_shared_cooldown", "radial_bullet_explosion", "dispersion_seeded"
    ]
    public var id: String
    public var name: String
    public var health: Int
    public var speed: Double
    public var collisionRadius: Double
    public var weapon: ArenaSourceSkill?
    public var ultimate: ArenaSourceSkill?
    public var weaponChargePerDamage: Double
    public var ultimateChargePerDamage: Double
    public var initialSuperCharge: Double
    public var unsupportedReasons: [String]
    public var compatibilityPolicy: String
    public var rawSource: [String: String]
    public var requiredCapabilities: [String]? = nil
    public var damageTakenChargePerDamage: Double? = nil
    public var unavailableCapabilities: [String] {
        var requested = Set(requiredCapabilities ?? [])
        requested.formUnion(weapon?.runtimeCapabilities ?? [])
        requested.formUnion(ultimate?.runtimeCapabilities ?? [])
        return requested.subtracting(Self.implementedCapabilities).sorted()
    }

    public var canPlay: Bool {
        unsupportedReasons.isEmpty && unavailableCapabilities.isEmpty
            && health > 0 && health <= 1_000_000_000 && speed.isFinite && speed > 0 && speed <= 1000
            && collisionRadius.isFinite && collisionRadius > 0 && collisionRadius <= 100
            && weaponChargePerDamage.isFinite && weaponChargePerDamage >= 0
            && ultimateChargePerDamage.isFinite && ultimateChargePerDamage >= 0
            && initialSuperCharge.isFinite && (0...1).contains(initialSuperCharge)
            && weapon?.isSupported == true && ultimate?.isSupported == true
    }
}

public struct ArenaSourceProjectile: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var speed: Double
    public var radius: Double
    public var piercesCharacters: Bool
    public var wallBreak: Bool
    public var pushback: Double
    public var bounces: Int
    public var bounceRangeAdd: Double
    public var areaEffects: [ArenaSourceAreaEffect]
    public var unsupportedReasons: [String]
    public var rawSource: [String: String]
    public var indirect: Bool? = nil
    /// Optional fixed flight duration in seconds, when the source uses a
    /// constant-flight-time projectile. Otherwise distance / source speed.
    public var constantFlightTime: Double? = nil
    /// Minimum time from launch to impact, not an additional landing delay.
    public var impactDelay: Double? = nil
    public var passesEnvironment: Bool? = nil
    public var lifeStealFraction: Double? = nil
    public var damageOncePerVolley: Bool? = nil
    public var directDamage: Bool? = nil
    public var canHitAgainAfterBounce: Bool? = nil
    public var gravity: Double? = nil
    public var minimumSpreadDistance: Double? = nil
    public var isSupported: Bool {
        unsupportedReasons.isEmpty && speed.isFinite && speed > 0 && speed <= 1000
            && radius.isFinite && radius >= 0 && radius <= 100
            && pushback.isFinite && pushback >= 0 && bounces >= 0 && bounces <= 100
            && bounceRangeAdd.isFinite && bounceRangeAdd >= 0
            && [constantFlightTime, impactDelay, lifeStealFraction, gravity, minimumSpreadDistance]
                .compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 600 }
            && areaEffects.allSatisfy(\.isSupported)
    }

    public var runtimeCapabilities: Set<String> {
        var result: Set<String> = [indirect == true ? "indirect_flight" : "projectile_straight"]
        if (impactDelay ?? 0) > 0 { result.insert("projectile_fuse") }
        if passesEnvironment == true { result.insert("pass_environment") }
        if (lifeStealFraction ?? 0) > 0 { result.insert("life_steal") }
        if damageOncePerVolley == true { result.insert("damage_once_per_volley") }
        if directDamage == false { result.insert("projectile_area_impact") }
        if bounces > 0 { result.insert("projectile_bounce") }
        if wallBreak { result.insert("wall_break") }
        for area in areaEffects { result.formUnion(area.runtimeCapabilities) }
        return result
    }
}

public struct ArenaSourceAreaEffect: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// The first adapter implements an immediate radial Damage effect only.
    public var kind: String
    public var radius: Double
    public var damage: Int?
    public var duration: Double
    public var wallBreak: Bool
    public var pushback: Double
    public var unsupportedReasons: [String]
    public var rawSource: [String: String]
    public var tickInterval: Double? = nil
    public var delayFirstTick: Bool? = nil
    public var ownPushback: Double? = nil
    public var statusEnemy: ArenaSourceStatusEffect? = nil
    public var statusTickInterval: Double? = nil
    public var sharedTargetCooldown: Double? = nil
    public var damageMultiplier: Double? = nil
    public var inheritsSkillDamage: Bool? = nil
    public var bulletExplosion: ArenaSourceBulletExplosion? = nil

    public func resolvedDamage(skillDamage: Int) -> Int {
        let base = inheritsSkillDamage != false && skillDamage > 0 ? skillDamage : (damage ?? skillDamage)
        return Int((Double(max(base, 0)) * (damageMultiplier ?? 1)).rounded())
    }

    public var isSupported: Bool {
        unsupportedReasons.isEmpty && ["Damage", "Dot", "StatusEffect", "BulletExplosion"].contains(kind)
            && radius.isFinite && radius > 0 && radius <= 100
            && duration.isFinite && duration >= 0 && duration <= 600
            && pushback.isFinite && pushback >= 0 && (damage ?? 0) >= 0 && (damage ?? 0) <= 10_000_000
            && [ownPushback, sharedTargetCooldown].compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 600 }
            && (tickInterval ?? 1).isFinite && (tickInterval ?? 1) >= ArenaSourceSkillState.tickDuration
            && (statusTickInterval ?? 0.1).isFinite && (statusTickInterval ?? 0.1) >= ArenaSourceSkillState.tickDuration
            && (damageMultiplier ?? 1).isFinite && (damageMultiplier ?? 1) >= 0
            && (damageMultiplier ?? 1) <= 100
            && (statusEnemy?.isSupported ?? true) && (bulletExplosion?.isSupported ?? true)
            && (kind != "StatusEffect" || statusEnemy != nil)
            && (kind != "BulletExplosion" || bulletExplosion != nil)
    }

    public var runtimeCapabilities: Set<String> {
        var result: Set<String> = ["persistent_area"]
        if kind == "Damage" { result.insert("impact_damage") }
        if kind == "Dot" { result.insert("dot_area") }
        if statusEnemy != nil { result.insert("slow_status") }
        if (ownPushback ?? 0) > 0 { result.insert("self_pushback") }
        if (sharedTargetCooldown ?? 0) > 0 { result.insert("area_shared_cooldown") }
        if wallBreak { result.insert("wall_break") }
        if let explosion = bulletExplosion {
            result.insert("radial_bullet_explosion")
            result.formUnion(explosion.projectile.runtimeCapabilities)
        }
        return result
    }
}

public struct ArenaSourceStatusEffect: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var duration: Double
    public var speedReductionAbsolute: Double
    public var speedReductionFraction: Double
    public var refreshable: Bool
    public var unsupportedReasons: [String]
    public var rawSource: [String: String]
    public var isSupported: Bool {
        unsupportedReasons.isEmpty && duration.isFinite && duration > 0 && duration <= 600
            && speedReductionAbsolute.isFinite && speedReductionAbsolute >= 0
            && speedReductionFraction.isFinite && (0...1).contains(speedReductionFraction)
    }
}

public struct ArenaSourceBulletExplosion: Codable, Equatable, Sendable {
    public var projectile: ArenaSourceProjectile
    public var count: Int
    public var range: Double
    public var angleOffset: Double
    public var isSupported: Bool {
        projectile.isSupported && (1...128).contains(count) && range.isFinite && range > 0 && range <= 1000
            && angleOffset.isFinite
    }
    public func directions() -> [V2] {
        guard isSupported else { return [] }
        return (0..<count).map { V2(1, 0).rotated(by: angleOffset + Double($0) * 2 * .pi / Double(count)) }
    }
}

public struct ArenaSourceChargeDefinition: Codable, Equatable, Sendable {
    public var sourceType: Int
    public var speed: Double
    public var wallBreak: Bool
    public var pushback: Double
    public var alwaysAtMaxRange: Bool
    public var endAreas: [ArenaSourceAreaEffect]
}

public struct ArenaSourceSkill: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var role: ArenaSourceSkillRole
    public var behavior: String
    public var range: Double
    public var damage: Int
    /// Source DamageForUlti; -1 is resolved to this skill's source damage.
    public var chargeDamage: Int
    public var ammoCapacity: Int
    public var reload: Double
    public var cooldown: Double
    public var castingTime: Double
    public var activeTime: Double
    public var attackInterval: Double
    public var executeFirstAttackImmediately: Bool
    public var canMove: Bool
    public var projectileCount: Int
    /// Total fan span in radians under the explicitly named compatibility policy.
    public var spread: Double
    public var projectiles: [ArenaSourceProjectile]
    public var areaEffects: [ArenaSourceAreaEffect]
    public var charge: ArenaSourceChargeDefinition?
    public var unsupportedReasons: [String]
    public var rawSource: [String: String]
    /// Optional host adapter for source AttackPattern 1. Its seeded sequence is
    /// reproducible, while the native v69 random generator remains unspecified.
    public var dispersion: String? = nil

    public var runtimeCapabilities: Set<String> {
        var result: Set<String> = behavior == "Attack" ? ["timed_burst"] : []
        if projectileCount > 1 { result.insert("pellet_fan") }
        if dispersion != nil { result.insert("dispersion_seeded") }
        for projectile in projectiles { result.formUnion(projectile.runtimeCapabilities) }
        for area in areaEffects { result.formUnion(area.runtimeCapabilities) }
        if let charge {
            result.insert("ground_charge")
            for area in charge.endAreas { result.formUnion(area.runtimeCapabilities) }
        }
        return result
    }

    public var isSupported: Bool {
        guard unsupportedReasons.isEmpty, range.isFinite, range >= 0, range <= 1000,
              damage >= 0, damage <= 10_000_000, chargeDamage >= 0, chargeDamage <= 10_000_000,
              ammoCapacity >= 0, ammoCapacity <= 1000,
              [reload, cooldown, castingTime, activeTime, attackInterval, spread].allSatisfy(\.isFinite),
              reload >= 0, cooldown >= 0, cooldown <= 600, castingTime >= 0, castingTime <= 600,
              activeTime >= 0, activeTime <= 600, spread >= 0, spread <= Double.pi * 2,
              dispersion == nil || dispersion == "seeded_cone",
              (ammoCapacity == 0 || reload > 0),
              areaEffects.allSatisfy(\.isSupported) else { return false }
        if behavior == "Attack" {
            return projectiles.count == 1 && projectiles[0].isSupported
                && projectileCount > 0 && projectileCount <= 128
                && attackInterval >= ArenaSourceSkillState.tickDuration && attackInterval <= 600
        }
        if behavior == "Charge", let charge {
            return [1, 4].contains(charge.sourceType) && charge.speed.isFinite && charge.speed > 0.01
                && charge.speed <= 1000 && charge.pushback.isFinite && charge.pushback >= 0
                && charge.endAreas.allSatisfy(\.isSupported)
        }
        return false
    }
}

public struct ArenaSourceLaunch: Codable, Equatable, Sendable {
    public var skillID: String
    public var role: ArenaSourceSkillRole
    public var projectile: ArenaSourceProjectile
    public var origin: V2
    public var direction: V2
    public var range: Double
    public var damage: Int
    public var chargeDamage: Int
    public var volleyIndex: Int
    public var pelletIndex: Int
    /// Monotonic within this fighter's skill state; combine owner + role + ID
    /// before grouping projectiles. Volley zero of two casts is not one group.
    public var activationID: UInt64? = nil
    public var target: V2? = nil
    public var flightDuration: Double? = nil
}

public struct ArenaSourceCharge: Codable, Equatable, Sendable {
    public var skillID: String
    public var role: ArenaSourceSkillRole
    public var sourceType: Int
    public var origin: V2
    public var direction: V2
    public var speed: Double
    public var distance: Double
    public var damage: Int
    public var chargeDamage: Int
    public var wallBreak: Bool
    public var pushback: Double
    public var endAreas: [ArenaSourceAreaEffect]
}

public struct ArenaSourceAreaSpawn: Codable, Equatable, Sendable {
    public var skillID: String
    public var role: ArenaSourceSkillRole
    public var area: ArenaSourceAreaEffect
    public var position: V2
    public var damage: Int
    public var chargeDamage: Int
}

public enum ArenaSourceEmission: Codable, Equatable, Sendable {
    case projectile(ArenaSourceLaunch)
    case charge(ArenaSourceCharge)
    case area(ArenaSourceAreaSpawn)
    case finished(skillID: String)
}

/// A fixed-step source-skill dispatcher. World owns collision, movement, damage
/// and the super gauge; this state owns source ammo, casting and burst timing.
public struct ArenaSourceSkillState: Codable, Equatable, Sendable {
    public static let tickDuration = 0.05
    public let skill: ArenaSourceSkill
    public private(set) var ammo: Double
    public private(set) var cooldownRemaining: Double = 0
    public var active: Bool { activation != nil }
    public var canActivate: Bool {
        skill.isSupported && !active && cooldownRemaining <= 1e-9
            && (skill.ammoCapacity == 0 || ammo >= 1 - 1e-9)
    }
    public var blocksMovement: Bool { active && !skill.canMove }
    private var accumulator: Double = 0
    private var activation: Activation?
    private var nextActivationID: UInt64 = 0
    private let dispersionSeed: UInt64

    public enum ActivationError: Error, Equatable {
        case unsupported([String])
        case busy
        case noAmmo
        case invalidAim
    }

    private struct Activation: Codable, Equatable, Sendable {
        var id: UInt64
        var elapsedTicks: Int
        var totalTicks: Int
        var castingTicks: Int
        var volleyTicks: [Int]
        var direction: V2
        var aimedDistance: Double
        var emittedVolleyCount: Int
        var chargeEmitted: Bool
    }

    public init(skill: ArenaSourceSkill) {
        self.init(skill: skill, seed: 0)
    }

    public init(skill: ArenaSourceSkill, seed: UInt64) {
        self.skill = skill
        dispersionSeed = seed
        ammo = Double(max(skill.ammoCapacity, 0))
    }

    /// The immediate branch emits at activation. A 650 ms / 100 ms source
    /// burst has a 12-tick firing window [0,12), hence 6 volleys, not 7.
    /// The reserved terminal tick remains part of the active animation time.
    public mutating func activate(origin: V2, aim: V2) throws -> [ArenaSourceEmission] {
        guard skill.isSupported else { throw ActivationError.unsupported(skill.unsupportedReasons) }
        guard !active, cooldownRemaining <= 1e-9 else { throw ActivationError.busy }
        guard skill.ammoCapacity == 0 || ammo >= 1 - 1e-9 else { throw ActivationError.noAmmo }
        guard origin.x.isFinite, origin.y.isFinite, aim.x.isFinite, aim.y.isFinite,
              aim.length.isFinite, aim.length > 1e-9 else {
            throw ActivationError.invalidAim
        }
        if skill.ammoCapacity > 0 { ammo = max(0, ammo - 1) }
        accumulator = 0
        let castingTicks = Self.ticks(skill.castingTime)
        let duration: Double
        if skill.behavior == "Charge", let charge = skill.charge {
            let distance = charge.alwaysAtMaxRange ? skill.range : min(skill.range, aim.length)
            duration = distance / charge.speed
        } else { duration = skill.activeTime }
        let activeTicks = max(1, Self.ticks(duration))
        // The source interval is quantized by the 20 Hz integer clock. Count
        // volleys in the active window before moving an immediate first shot
        // to tick zero. This preserves 650/100 -> 6 and 600/120 -> 5.
        let intervalTicks = max(1, Int((skill.attackInterval / Self.tickDuration + 1e-8).rounded(.down)))
        let volleyCount = max(1, (activeTicks - 1) / intervalTicks)
        let first = skill.executeFirstAttackImmediately ? 0 : intervalTicks
        let volleyTicks = skill.behavior == "Attack"
            ? (0..<volleyCount).map { castingTicks + first + $0 * intervalTicks }.filter { $0 < castingTicks + activeTicks } : []
        nextActivationID &+= 1
        activation = Activation(id: nextActivationID, elapsedTicks: 0, totalTicks: castingTicks + activeTicks,
                                castingTicks: castingTicks, volleyTicks: volleyTicks,
                                direction: aim.normalized, aimedDistance: aim.length,
                                emittedVolleyCount: 0, chargeEmitted: false)
        cooldownRemaining = Double(castingTicks + activeTicks) * Self.tickDuration + skill.cooldown
        return emitDue(origin: origin)
    }

    public mutating func advance(dt: Double, origin: V2) -> [ArenaSourceEmission] {
        guard dt.isFinite, dt > 0, dt <= 60, origin.x.isFinite, origin.y.isFinite else { return [] }
        accumulator += dt
        var emitted: [ArenaSourceEmission] = []
        while accumulator + 1e-9 >= Self.tickDuration {
            accumulator = max(0, accumulator - Self.tickDuration)
            cooldownRemaining = max(0, cooldownRemaining - Self.tickDuration)
            if activation != nil {
                activation!.elapsedTicks += 1
                emitted.append(contentsOf: emitDue(origin: origin))
                if let state = activation, state.elapsedTicks >= state.totalTicks {
                    activation = nil
                    emitted.append(.finished(skillID: skill.id))
                }
            } else if skill.ammoCapacity > 0, skill.reload > 0 {
                ammo = min(Double(skill.ammoCapacity), ammo + Self.tickDuration / skill.reload)
            }
        }
        return emitted
    }

    /// Death/interruption cancels future emissions and loops; already launched
    /// projectiles remain owned by World. Consumed ammo is not restored.
    public mutating func cancel() { activation = nil; accumulator = 0 }

    /// Respawn restores this source weapon's own capacity, not a classic 3-ammo default.
    public mutating func reset() {
        activation = nil; accumulator = 0; cooldownRemaining = 0
        ammo = Double(max(skill.ammoCapacity, 0))
    }

    private static func ticks(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return max(1, Int((seconds / tickDuration - 1e-8).rounded(.up)))
    }

    private mutating func emitDue(origin: V2) -> [ArenaSourceEmission] {
        guard var state = activation else { return [] }
        var output: [ArenaSourceEmission] = []
        if state.volleyTicks.contains(state.elapsedTicks), let projectile = skill.projectiles.first {
            let count = skill.projectileCount
            for pellet in 0..<count {
                var span = skill.spread
                if projectile.indirect == true, let minimum = projectile.minimumSpreadDistance, minimum > 0 {
                    span *= min(1, state.aimedDistance / minimum)
                }
                let angle: Double
                if skill.dispersion == "seeded_cone" {
                    angle = (Self.dispersionUnit(skillID: skill.id, activation: state.id,
                        volley: state.emittedVolleyCount, pellet: pellet, seed: dispersionSeed) - 0.5) * span
                } else {
                    angle = count == 1 ? 0 : -span / 2 + span * Double(pellet) / Double(count - 1)
                }
                let direction = state.direction.rotated(by: angle)
                var launch = ArenaSourceLaunch(skillID: skill.id, role: skill.role,
                    projectile: projectile, origin: origin, direction: state.direction.rotated(by: angle),
                    range: skill.range, damage: skill.damage, chargeDamage: skill.chargeDamage,
                    volleyIndex: state.emittedVolleyCount, pelletIndex: pellet)
                launch.activationID = state.id
                if projectile.indirect == true {
                    let distance = min(skill.range, state.aimedDistance)
                    launch.target = origin + direction * distance
                    launch.flightDuration = max(Self.tickDuration,
                        max(projectile.constantFlightTime ?? (distance / projectile.speed), projectile.impactDelay ?? 0))
                }
                output.append(.projectile(launch))
            }
            state.emittedVolleyCount += 1
        }
        if state.elapsedTicks == state.castingTicks {
            for area in skill.areaEffects {
                output.append(.area(ArenaSourceAreaSpawn(skillID: skill.id, role: skill.role, area: area,
                    position: origin, damage: area.resolvedDamage(skillDamage: skill.damage), chargeDamage: skill.chargeDamage)))
            }
            if skill.behavior == "Charge", let charge = skill.charge, !state.chargeEmitted {
                output.append(.charge(ArenaSourceCharge(skillID: skill.id, role: skill.role, sourceType: charge.sourceType,
                    origin: origin, direction: state.direction, speed: charge.speed,
                    distance: charge.alwaysAtMaxRange ? skill.range : min(skill.range, state.aimedDistance),
                    damage: skill.damage, chargeDamage: skill.chargeDamage, wallBreak: charge.wallBreak,
                    pushback: charge.pushback, endAreas: charge.endAreas)))
                state.chargeEmitted = true
            }
        }
        activation = state
        return output
    }

    private static func dispersionUnit(skillID: String, activation: UInt64, volley: Int, pellet: Int, seed sourceSeed: UInt64) -> Double {
        var seed: UInt64 = 14695981039346656037 ^ sourceSeed
        for byte in skillID.utf8 { seed = (seed ^ UInt64(byte)) &* 1099511628211 }
        seed ^= activation &* 0x9e3779b97f4a7c15
        seed ^= UInt64(volley) &* 0xbf58476d1ce4e5b9
        seed ^= UInt64(pellet) &* 0x94d049bb133111eb
        seed = (seed ^ (seed >> 30)) &* 0xbf58476d1ce4e5b9
        seed = (seed ^ (seed >> 27)) &* 0x94d049bb133111eb
        seed ^= seed >> 31
        return Double(seed >> 11) / 9007199254740992
    }
}
