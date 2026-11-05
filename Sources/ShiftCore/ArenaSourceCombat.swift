import Foundation

/// Data-driven compatibility rules for source heroes. These types never select a
/// classic Brawler as a substitute for an unsupported source mechanic.
public enum ArenaSourceSkillRole: String, Codable, Equatable, Hashable, Sendable { case weapon, ultimate }

/// Deliberately bounded host policy for the reviewed long-dash source hero.
/// The archived 90 / 6 parameters have not been proven to encode the native
/// distance/timing formula; do not present this as native behavior.
public struct ArenaSourceLongDash: Codable, Equatable, Sendable {
    public var bonusDistanceFraction: Double
    public var rechargeAfterSeconds: Double
    public init(bonusDistanceFraction: Double, rechargeAfterSeconds: Double) {
        self.bonusDistanceFraction = bonusDistanceFraction
        self.rechargeAfterSeconds = rechargeAfterSeconds
    }
    public var isSupported: Bool {
        bonusDistanceFraction.isFinite && (0...3).contains(bonusDistanceFraction)
            && rechargeAfterSeconds.isFinite && rechargeAfterSeconds > 0 && rechargeAfterSeconds <= 120
    }
}

public struct ArenaSourceHero: Codable, Equatable, Sendable, Identifiable {
    /// Add a capability only after both the dispatcher and World adapter have
    /// meaningful verification. Decoding a source field alone does not enable it.
    public static let implementedCapabilities: Set<String> = [
        "projectile_straight", "pellet_fan", "timed_burst", "ground_charge",
        "impact_damage", "wall_break", "projectile_bounce", "indirect_flight",
        "projectile_fuse", "pass_environment", "life_steal", "damage_once_per_volley",
        "projectile_area_impact", "persistent_area", "dot_area", "slow_status",
        "self_pushback", "area_shared_cooldown", "radial_bullet_explosion", "dispersion_seeded",
        "self_shield", "damage_taken_super_charge", "ally_projectile_heal", "charged_ground_dash",
        "caster_tracked_indirect_flight", "smoke_ally_hide", "area_pull", "delayed_area_damage"
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
    public var longDash: ArenaSourceLongDash? = nil
    public var unavailableCapabilities: [String] {
        var requested = Set(requiredCapabilities ?? [])
        requested.formUnion(weapon?.runtimeCapabilities ?? [])
        requested.formUnion(ultimate?.runtimeCapabilities ?? [])
        if damageTakenChargePerDamage != nil { requested.insert("damage_taken_super_charge") }
        if longDash != nil { requested.insert("charged_ground_dash") }
        return requested.subtracting(Self.implementedCapabilities).sorted()
    }

    public var canPlay: Bool {
        unsupportedReasons.isEmpty && unavailableCapabilities.isEmpty
            && health > 0 && health <= 1_000_000_000 && speed.isFinite && speed > 0 && speed <= 1000
            && collisionRadius.isFinite && collisionRadius > 0 && collisionRadius <= 100
            && weaponChargePerDamage.isFinite && weaponChargePerDamage >= 0
            && ultimateChargePerDamage.isFinite && ultimateChargePerDamage >= 0
            && initialSuperCharge.isFinite && (0...1).contains(initialSuperCharge)
            && (damageTakenChargePerDamage.map { $0.isFinite && $0 >= 0 && $0 <= 1 } ?? true)
            && (longDash.map { $0.isSupported && weapon?.behavior == "Charge" } ?? true)
            && weapon?.isSupported == true && ultimate?.isSupported == true
    }
}

/// Small, evidence-gated compatibility adapters for an already verified source
/// profile. The original CSV fields and rejection reasons are retained in the
/// private archive; this runtime view only clears reasons whose host mechanics
/// are implemented and checked. It never switches to a project hero's skill.
public enum ArenaSourceCompatibility {
    public static func adapt(_ source: ArenaSourceHero) -> ArenaSourceHero {
        var result = source
        var resolved = Set<String>()
        func adaptPatternNine(_ skill: inout ArenaSourceSkill?) {
            guard var candidate = skill, candidate.behavior == "Attack",
                  candidate.rawSource["AttackPattern"] == "9",
                  candidate.rawSource["NumBulletsInOneAttack"] == "1",
                  candidate.projectileCount == 1, candidate.projectiles.count == 1,
                  candidate.spread.isFinite, candidate.spread > 0 else { return }
            let pattern = "skill.\(candidate.id).AttackPattern=9: not yet interpreted"
            let spread = "skill.\(candidate.id).Spread: single-projectile dispersion needs a source pattern adapter"
            guard candidate.unsupportedReasons.contains(pattern), candidate.unsupportedReasons.contains(spread) else { return }
            // Approximate source pattern 9 with the same 20 Hz, seeded-cone
            // dispatcher already used for validated source dispersions. This
            // is a deterministic host compatibility pattern, not a claim to
            // reproduce the original client's RNG sequence bit-for-bit.
            candidate.dispersion = "seeded_cone"
            candidate.unsupportedReasons.removeAll { $0 == pattern || $0 == spread }
            guard candidate.isSupported else { return }
            skill = candidate
            resolved.insert(pattern)
            resolved.insert(spread)
        }
        adaptPatternNine(&result.weapon)
        adaptPatternNine(&result.ultimate)
        // Sandy's archived three-shot pattern uses a fixed spread and its
        // once-per-volley hit guard, both already executed by the host fan.
        // Keep this named as an approximation of the original pattern four.
        if result.id == "Sandstorm", var weapon = result.weapon,
           weapon.id == "SandstormWeapon", weapon.role == .weapon,
           weapon.behavior == "Attack", weapon.rawSource["AttackPattern"] == "4",
           weapon.rawSource["NumBulletsInOneAttack"] == "3",
           weapon.rawSource["Spread"] == "80", weapon.damage == 900,
           weapon.projectileCount == 3, weapon.projectiles.count == 1,
           weapon.projectiles[0].id == "SandstormProjectile",
           weapon.projectiles[0].damageOncePerVolley == true,
           weapon.projectiles[0].piercesCharacters, weapon.spread > 0 {
            let reason = "skill.SandstormWeapon.AttackPattern=4: not yet interpreted"
            if result.unsupportedReasons.contains(reason), weapon.unsupportedReasons == [reason] {
                weapon.unsupportedReasons.removeAll { $0 == reason }
                if weapon.isSupported {
                    result.weapon = weapon
                    resolved.insert(reason)
                }
            }
        }
        // Sandy's 9s smoke circle grants allies concealment while in range.
        // Opposing fighters, boxes, safes and scenery are not affected.
        if result.id == "Sandstorm", var ultimate = result.ultimate,
           ultimate.id == "SandstormUlti", ultimate.role == .ultimate,
           ultimate.behavior == "Attack", ultimate.projectiles.count == 1,
           ultimate.projectiles[0].id == "SandstormUltiProjectile",
           ultimate.projectiles[0].indirect == true,
           ultimate.projectiles[0].areaEffects.count == 1,
           ultimate.projectiles[0].areaEffects[0].id == "Sandy_def_ulti",
           ultimate.projectiles[0].areaEffects[0].kind == "SmokeScreen",
           ultimate.projectiles[0].areaEffects[0].rawSource["Type"] == "SmokeScreen",
           ultimate.projectiles[0].areaEffects[0].duration == 9,
           ultimate.projectiles[0].areaEffects[0].radius == 2000.0 / 300,
           ultimate.damage == 0 {
            let reason = "area.Sandy_def_ulti.Type=SmokeScreen: requires a dedicated area lifecycle"
            if result.unsupportedReasons.contains(reason), ultimate.unsupportedReasons == [reason],
               ultimate.projectiles[0].unsupportedReasons == [reason],
               ultimate.projectiles[0].areaEffects[0].unsupportedReasons == [reason] {
                ultimate.projectiles[0].areaEffects[0].unsupportedReasons.removeAll { $0 == reason }
                ultimate.projectiles[0].unsupportedReasons.removeAll { $0 == reason }
                ultimate.unsupportedReasons.removeAll { $0 == reason }
                if ultimate.isSupported {
                    result.ultimate = ultimate
                    resolved.insert(reason)
                }
            }
        }
        // Tara's archived black hole emits a short inward pull plus a single
        // later blast. This is a bounded host area lifecycle, not an exact
        // recreation of the native suction acceleration or impact tick.
        if result.id == "BlackHole", var ultimate = result.ultimate,
           result.weapon?.isSupported == true,
           ultimate.id == "BlackHoleUlti", ultimate.role == .ultimate,
           ultimate.behavior == "Attack", ultimate.damage == 800,
           ultimate.projectileCount == 1, ultimate.projectiles.count == 1,
           ultimate.projectiles[0].id == "BlackHoleUltiProjectile",
           ultimate.projectiles[0].indirect == true,
           ultimate.projectiles[0].directDamage == false,
           ultimate.projectiles[0].areaEffects.count == 2 {
            let pull = "area.BlackHoleUltiSuck.Type=Pushback: requires a dedicated area lifecycle"
            let explosion = "area.BlackHoleUltiExplosion.Type=DelayedDamage: requires a dedicated area lifecycle"
            let delay = "area.BlackHoleUltiExplosion.CustomValue=700: not yet interpreted"
            var projectile = ultimate.projectiles[0]
            let pullArea = projectile.areaEffects[0]
            let blastArea = projectile.areaEffects[1]
            let reasons = [pull, explosion, delay]
            if reasons.allSatisfy({ result.unsupportedReasons.contains($0) }),
               Set(ultimate.unsupportedReasons) == Set(reasons),
               Set(projectile.unsupportedReasons) == Set(reasons),
               pullArea.id == "BlackHoleUltiSuck", pullArea.kind == "Pushback",
               pullArea.rawSource["Type"] == "Pushback", pullArea.duration == 0.7,
               pullArea.rawSource["PushbackStrength"] == "-150",
               pullArea.radius == 4,
               pullArea.pushback == -0.5, pullArea.unsupportedReasons == [pull],
               blastArea.id == "BlackHoleUltiExplosion", blastArea.kind == "DelayedDamage",
               blastArea.rawSource["Type"] == "DelayedDamage",
               blastArea.rawSource["CustomValue"] == "700",
               blastArea.rawSource["PushbackStrength"] == "50",
               blastArea.radius == 1.5, blastArea.duration == 1.4, blastArea.wallBreak,
               Set(blastArea.unsupportedReasons) == Set([explosion, delay]) {
                projectile.areaEffects[0].unsupportedReasons.removeAll { $0 == pull }
                projectile.areaEffects[1].delayedDamageSeconds = 0.7
                projectile.areaEffects[1].unsupportedReasons.removeAll { $0 == explosion || $0 == delay }
                projectile.unsupportedReasons.removeAll { reasons.contains($0) }
                ultimate.projectiles[0] = projectile
                ultimate.unsupportedReasons.removeAll { reasons.contains($0) }
                if ultimate.isSupported {
                    result.ultimate = ultimate
                    resolved.formUnion(reasons)
                }
            }
        }
        // This archived Brock Super keeps an indirect impact target relative
        // to the moving caster during flight. The native prediction formula is
        // unknown; the host follows caster displacement from launch instead.
        if result.id == "RocketGirl", var ultimate = result.ultimate,
           ultimate.id == "RocketGirlUlti", ultimate.role == .ultimate,
           ultimate.behavior == "Attack", ultimate.projectileCount == 1,
           ultimate.projectiles.count == 1, ultimate.damage == 1040,
           ultimate.rawSource["AttackPattern"] == "9",
           ultimate.rawSource["NumBulletsInOneAttack"] == "1",
           ultimate.projectiles[0].id == "RocketGirlUltiProjectile",
           ultimate.projectiles[0].rawSource["BooleanAttributes"] == "IndirectProjectileTracksSource",
           ultimate.projectiles[0].indirect == true,
           ultimate.projectiles[0].constantFlightTime == 0.9,
           ultimate.projectiles[0].areaEffects.allSatisfy(\.isSupported) {
            let reason = "projectile.RocketGirlUltiProjectile.BooleanAttributes=IndirectProjectileTracksSource: not yet interpreted"
            if result.unsupportedReasons.contains(reason), ultimate.unsupportedReasons.contains(reason),
               ultimate.projectiles[0].unsupportedReasons == [reason] {
                ultimate.projectiles[0].tracksCasterDisplacement = true
                ultimate.projectiles[0].unsupportedReasons.removeAll { $0 == reason }
                ultimate.unsupportedReasons.removeAll { $0 == reason }
                result.ultimate = ultimate
                resolved.insert(reason)
                // Pattern nine is only unblocked once the projectile's own
                // mandatory caster-tracking mechanic has been implemented.
                adaptPatternNine(&result.ultimate)
            }
        }
        // Only the explicitly reviewed self-shield source record is adapted.
        // The host damage multiplier is declared in the policy; unrelated
        // source blockers remain independent of this shield adapter.
        if result.id == "Rosa", var skill = result.ultimate,
           skill.id == "RosaUlti", skill.role == .ultimate, skill.behavior == "Shield",
           skill.rawSource["BehaviorType"] == "Shield", skill.rawSource["ActiveTime"] == "4000",
           skill.activeTime == 4, skill.projectiles.isEmpty, skill.projectileCount == 0,
           skill.charge == nil, skill.areaEffects.isEmpty, skill.damage == 0 {
            let reason = "skill.RosaUlti.BehaviorType=Shield: requires a dedicated behavior adapter"
            if skill.unsupportedReasons == [reason] {
                skill.shieldDamageMultiplier = 0.4
                skill.unsupportedReasons.removeAll { $0 == reason }
                if skill.isSupported {
                    result.ultimate = skill
                    resolved.insert(reason)
                }
            }
        }
        // A bounded host compatibility policy (not a verified native formula):
        // taking a full base-health bar of enemy damage contributes 24% or 28%
        // of a super when the archived source field matches exactly.
        if let raw = result.rawSource["ChargeUltiFromDamage"],
           let perMille = Int(raw), [240, 280].contains(perMille), result.health > 0 {
            let reason = "hero.\(result.id).ChargeUltiFromDamage=\(raw): requires a dedicated hero rule"
            if result.unsupportedReasons.contains(reason), result.damageTakenChargePerDamage == nil {
                let rate = Double(perMille) / (1000 * Double(result.health))
                if rate.isFinite, rate > 0, rate <= 1 {
                    result.damageTakenChargePerDamage = rate
                    resolved.insert(reason)
                }
            }
        }
        // The reviewed healing hero uses a main-attack ally-heal trait and a
        // non-damaging healing Super. These are host gameplay approximations:
        // main attack heals an ally for 5% of their max HP; Super projectiles
        // heal allies for the source skill amount and heal the caster once.
        if result.id == "DeadMariachi", result.rawSource["Traits"] == "DeadMariachiProjectileHealPassive",
           var weapon = result.weapon, var ultimate = result.ultimate,
           weapon.id == "DeadMariachiWeapon", weapon.role == .weapon, weapon.behavior == "Attack",
           weapon.projectiles.count == 1, weapon.projectiles[0].id == "DeadMariachiProjectile",
           weapon.projectiles[0].piercesCharacters, weapon.projectiles[0].damageOncePerVolley == true,
           weapon.damage == 760, weapon.unsupportedReasons.isEmpty,
           ultimate.id == "DeadMariachiUlti", ultimate.role == .ultimate, ultimate.behavior == "Attack",
           ultimate.projectiles.count == 1, ultimate.projectiles[0].id == "DeadMariachiUltiProjectile",
           ultimate.projectiles[0].rawSource["HealOwnPercent"] == "100",
           ultimate.projectiles[0].piercesCharacters, ultimate.projectiles[0].passesEnvironment == true,
           ultimate.projectiles[0].damageOncePerVolley == true,
           ultimate.projectiles[0].areaEffects.isEmpty, ultimate.damage == 2100 {
            let traitReason = "hero.DeadMariachi.Traits=DeadMariachiProjectileHealPassive: requires a dedicated hero rule"
            let healReason = "projectile.DeadMariachiUltiProjectile.HealOwnPercent=100: not yet interpreted"
            if result.unsupportedReasons.contains(traitReason), result.unsupportedReasons.contains(healReason),
               ultimate.unsupportedReasons == [healReason],
               ultimate.projectiles[0].unsupportedReasons == [healReason] {
                weapon.projectiles[0].allyHealMaxHealthFraction = 0.05
                ultimate.projectiles[0].healAlliesInsteadOfDamage = true
                ultimate.projectiles[0].casterHealFraction = 1
                ultimate.projectiles[0].unsupportedReasons.removeAll { $0 == healReason }
                ultimate.unsupportedReasons.removeAll { $0 == healReason }
                if weapon.isSupported && ultimate.isSupported {
                    result.weapon = weapon
                    result.ultimate = ultimate
                    resolved.insert(traitReason)
                    resolved.insert(healReason)
                }
            }
        }
        // The imported Mortis record already has a supported charge weapon and
        // lifesteal Super. Its three identity fields are the only remaining
        // blockers. Map those exact fields to an explicit, non-native charged
        // dash rule; other identity variants remain blocked for review.
        if result.id == "Undertaker", result.rawSource["UniqueProperty"] == "HAS_LONGER_DASH",
           result.rawSource["UniquePropertyValue1"] == "90",
           result.rawSource["UniquePropertyValue2"] == "6",
           let weapon = result.weapon, weapon.id == "UndertakerWeapon",
           weapon.role == .weapon, weapon.behavior == "Charge", weapon.isSupported,
           weapon.castingTime == 0, weapon.damage == 1000, weapon.range == 8.0 / 3,
           let charge = weapon.charge, charge.sourceType == 4,
           charge.speed == 9, charge.alwaysAtMaxRange, !charge.wallBreak,
           let ultimate = result.ultimate, ultimate.id == "UndertakerUlti",
           ultimate.role == .ultimate, ultimate.isSupported,
           ultimate.projectiles.count == 1, ultimate.projectiles[0].lifeStealFraction == 1,
           ultimate.projectiles[0].passesEnvironment == true, result.longDash == nil {
            let reasons = [
                "hero.Undertaker.UniquePropertyValue1=90: requires a dedicated hero rule",
                "hero.Undertaker.UniquePropertyValue2=6: requires a dedicated hero rule",
                "hero.Undertaker.UniqueProperty=HAS_LONGER_DASH: native identity behavior not implemented"
            ]
            if reasons.allSatisfy({ result.unsupportedReasons.contains($0) }) {
                result.longDash = ArenaSourceLongDash(bonusDistanceFraction: 0.9, rechargeAfterSeconds: 6)
                resolved.formUnion(reasons)
            }
        }
        if !resolved.isEmpty {
            result.unsupportedReasons.removeAll { resolved.contains($0) }
            if resolved.contains(where: { $0.contains("AttackPattern=9") }) {
                result.compatibilityPolicy += "+host-pattern9-seeded-cone"
            }
            if resolved.contains("skill.RosaUlti.BehaviorType=Shield: requires a dedicated behavior adapter") {
                result.compatibilityPolicy += "+host-self-shield60"
            }
            if resolved.contains(where: { $0.contains(".ChargeUltiFromDamage=") }) {
                result.compatibilityPolicy += "+host-damage-taken-permille-health"
            }
            if resolved.contains("hero.DeadMariachi.Traits=DeadMariachiProjectileHealPassive: requires a dedicated hero rule") {
                result.compatibilityPolicy += "+host-poco-ally-heal5pct-and-super"
            }
            if resolved.contains("hero.Undertaker.UniqueProperty=HAS_LONGER_DASH: native identity behavior not implemented") {
                result.compatibilityPolicy += "+host-mortis-dash90pct-after6s"
            }
            if resolved.contains("projectile.RocketGirlUltiProjectile.BooleanAttributes=IndirectProjectileTracksSource: not yet interpreted") {
                result.compatibilityPolicy += "+host-brock-caster-tracked-impact"
            }
            if resolved.contains("skill.SandstormWeapon.AttackPattern=4: not yet interpreted") {
                result.compatibilityPolicy += "+host-sandy-three-pellet-fan"
            }
            if resolved.contains("area.Sandy_def_ulti.Type=SmokeScreen: requires a dedicated area lifecycle") {
                result.compatibilityPolicy += "+host-sandy-ally-smoke-nine-seconds"
            }
            if resolved.contains("area.BlackHoleUltiExplosion.CustomValue=700: not yet interpreted") {
                result.compatibilityPolicy += "+host-tara-pull-and-delayed-blast700ms"
            }
        }
        return result
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
    /// A non-native host approximation for main-attack projectiles that can
    /// heal teammates on contact, as a fraction of the recipient's max HP.
    public var allyHealMaxHealthFraction: Double? = nil
    /// Healing waves restore allied HP instead of damaging opposing fighters.
    public var healAlliesInsteadOfDamage: Bool? = nil
    /// Heal the caster once when this healing ultimate is activated.
    public var casterHealFraction: Double? = nil
    /// The rocket's final impact target follows displacement of the hero who
    /// fired it. Bounded host substitute for a reviewed source attribute.
    public var tracksCasterDisplacement: Bool? = nil
    public var isSupported: Bool {
        unsupportedReasons.isEmpty && speed.isFinite && speed > 0 && speed <= 1000
            && radius.isFinite && radius >= 0 && radius <= 100
            && pushback.isFinite && pushback >= 0 && bounces >= 0 && bounces <= 100
            && bounceRangeAdd.isFinite && bounceRangeAdd >= 0
            && [constantFlightTime, impactDelay, lifeStealFraction, gravity, minimumSpreadDistance]
                .compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 600 }
            && [allyHealMaxHealthFraction, casterHealFraction]
                .compactMap { $0 }.allSatisfy { $0.isFinite && (0...1).contains($0) }
            && !(healAlliesInsteadOfDamage == true && (allyHealMaxHealthFraction ?? 0) > 0)
            && (healAlliesInsteadOfDamage != true || (piercesCharacters && areaEffects.isEmpty))
            && (tracksCasterDisplacement != true || (indirect == true && constantFlightTime != nil))
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
        if (allyHealMaxHealthFraction ?? 0) > 0 || healAlliesInsteadOfDamage == true || (casterHealFraction ?? 0) > 0 {
            result.insert("ally_projectile_heal")
        }
        if tracksCasterDisplacement == true { result.insert("caster_tracked_indirect_flight") }
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
    /// One-shot blast time within a longer-lived source area, in seconds.
    public var delayedDamageSeconds: Double? = nil

    public func resolvedDamage(skillDamage: Int) -> Int {
        let base = inheritsSkillDamage != false && skillDamage > 0 ? skillDamage : (damage ?? skillDamage)
        return Int((Double(max(base, 0)) * (damageMultiplier ?? 1)).rounded())
    }

    public var isSupported: Bool {
        unsupportedReasons.isEmpty && ["Damage", "Dot", "StatusEffect", "BulletExplosion", "SmokeScreen", "Pushback", "DelayedDamage"].contains(kind)
            && radius.isFinite && radius > 0 && radius <= 100
            && duration.isFinite && duration >= 0 && duration <= 600
            && pushback.isFinite && (kind == "Pushback" ? (-10...0).contains(pushback) : pushback >= 0)
            && (damage ?? 0) >= 0 && (damage ?? 0) <= 10_000_000
            && [ownPushback, sharedTargetCooldown].compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 600 }
            && (tickInterval ?? 1).isFinite && (tickInterval ?? 1) >= ArenaSourceSkillState.tickDuration
            && (statusTickInterval ?? 0.1).isFinite && (statusTickInterval ?? 0.1) >= ArenaSourceSkillState.tickDuration
            && (damageMultiplier ?? 1).isFinite && (damageMultiplier ?? 1) >= 0
            && (damageMultiplier ?? 1) <= 100
            && (statusEnemy?.isSupported ?? true) && (bulletExplosion?.isSupported ?? true)
            && (kind != "StatusEffect" || statusEnemy != nil)
            && (kind != "BulletExplosion" || bulletExplosion != nil)
            && (kind != "DelayedDamage" || (delayedDamageSeconds.map {
                $0.isFinite && $0 >= 0 && $0 < duration
            } ?? false))
    }

    public var runtimeCapabilities: Set<String> {
        var result: Set<String> = ["persistent_area"]
        if kind == "Damage" { result.insert("impact_damage") }
        if kind == "Dot" { result.insert("dot_area") }
        if kind == "SmokeScreen" { result.insert("smoke_ally_hide") }
        if kind == "Pushback" { result.insert("area_pull") }
        if kind == "DelayedDamage" { result.insert("delayed_area_damage") }
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
    /// Explicit host reduction policy for a self-shield skill. A nil value
    /// means the native shield semantics have not been reviewed or implemented.
    public var shieldDamageMultiplier: Double? = nil

    public var runtimeCapabilities: Set<String> {
        var result: Set<String> = behavior == "Attack" ? ["timed_burst"] : []
        if projectileCount > 1 { result.insert("pellet_fan") }
        if dispersion != nil { result.insert("dispersion_seeded") }
        if behavior == "Shield" { result.insert("self_shield") }
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
              (shieldDamageMultiplier.map { $0.isFinite && $0 > 0 && $0 < 1 } ?? true),
              (ammoCapacity == 0 || reload > 0),
              areaEffects.allSatisfy(\.isSupported) else { return false }
        if behavior == "Attack" {
            return shieldDamageMultiplier == nil && projectiles.count == 1 && projectiles[0].isSupported
                && projectileCount > 0 && projectileCount <= 128
                && (role == .ultimate || (projectiles[0].casterHealFraction ?? 0) == 0)
                && attackInterval >= ArenaSourceSkillState.tickDuration && attackInterval <= 600
        }
        if behavior == "Charge", let charge {
            return shieldDamageMultiplier == nil && [1, 4].contains(charge.sourceType)
                && charge.speed.isFinite && charge.speed > 0.01
                && charge.speed <= 1000 && charge.pushback.isFinite && charge.pushback >= 0
                && charge.endAreas.allSatisfy(\.isSupported)
        }
        if behavior == "Shield" {
            return role == .ultimate && activeTime > 0 && shieldDamageMultiplier != nil
                && projectiles.isEmpty && projectileCount == 0 && charge == nil
                && areaEffects.isEmpty && ammoCapacity == 0 && damage == 0 && chargeDamage == 0
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

public struct ArenaSourceShield: Codable, Equatable, Sendable {
    public var duration: Double
    public var damageMultiplier: Double
}

public enum ArenaSourceEmission: Codable, Equatable, Sendable {
    case projectile(ArenaSourceLaunch)
    case charge(ArenaSourceCharge)
    case area(ArenaSourceAreaSpawn)
    case shield(ArenaSourceShield)
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
            if skill.behavior == "Shield", let multiplier = skill.shieldDamageMultiplier {
                output.append(.shield(ArenaSourceShield(duration: skill.activeTime, damageMultiplier: multiplier)))
            }
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
