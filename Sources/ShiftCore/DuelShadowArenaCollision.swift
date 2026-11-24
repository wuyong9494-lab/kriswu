import Foundation

/// Deterministic 3D weapon-capsule sweep vs multi-zone (Head / Torso / Legs) hurt-capsule collision
/// for `.shadowArena` combat, powered by `DuelWeaponCapsule.swept(...)`.
/// Enables authentic Shadow Fight spatial mechanics:
/// - Jumping cleanly vaults OVER low sweeps (`weaponDown` / `kickDown` whiffs beneath airborne legs!)
/// - High slashes (`weaponUp` / `kickUp`) physically intersect the Head hurt capsule (including airborne targets!)
/// - Real hero weapon lengths govern reach (Wu Yong Odachi & Xu Xiao Greatsword > Liu GreatAxe > Sun Deng Dual Ninjato)
/// - Exact 3D world contact point `(x, y, z)` returned for crisp impact sparks & parries!
public enum DuelShadowArenaCollision {
    public struct Contact: Equatable, Sendable {
        public let zone: DuelGame.HitZone
        public let pointX: Int // world millimetres
        public let pointY: Int // world millimetres
        public let pointZ: Int // world millimetres
        public let time: Double
    }

    /// Physical blade / weapon reach in metres measured directly from the 4 new rigged hero GLBs.
    public static func weaponLengthMeters(for hero: DuelGame.Hero) -> Double {
        switch hero {
        case .wuYong: return 1.18   // Shogun Odachi (1.18m)
        case .liu: return 0.96      // Emperor Martial Gauntlets / Shadow Beast Claws
        case .gale: return 1.26     // King of the Legion Two-Handed Greatsword (1.26m)
        case .ember: return 1.15    // Monkey King Extendable Jingu Staff (1.15m)
        }
    }

    /// Three anatomical hurt capsules (Head, Torso, Legs) in world metres for a fighter.
    /// Automatically ducks head/torso during low crouching sweeps and lifts vertically on jumps!
    static func hurtCapsules(for fighter: DuelGame.Fighter) -> [(zone: DuelGame.HitZone, capsule: DuelWeaponCapsule)] {
        let fx = Double(fighter.x) / 1000.0
        let fy = Double(fighter.y) / 1000.0
        let dir = Double(fighter.facing)

        let crouching = fighter.attack.map {
            $0.move == .weaponDown || $0.move == .kickDown
        } ?? false
        let duckOffset = crouching ? -0.34 : 0.0

        let head = DuelWeaponCapsule(
            a: .init(x: fx + dir * 0.04, y: max(0.28, fy + 1.54 + duckOffset), z: 0),
            b: .init(x: fx + dir * 0.04, y: max(0.46, fy + 1.78 + duckOffset), z: 0),
            radius: 0.14
        )
        let torso = DuelWeaponCapsule(
            a: .init(x: fx, y: max(0.22, fy + 0.86 + duckOffset * 0.65), z: 0),
            b: .init(x: fx, y: max(0.45, fy + 1.46 + duckOffset * 0.85), z: 0),
            radius: 0.21
        )
        let legs = DuelWeaponCapsule(
            a: .init(x: fx - dir * 0.06, y: fy + 0.08, z: 0),
            b: .init(x: fx + dir * 0.08, y: max(0.32, fy + 0.80 + duckOffset * 0.35), z: 0),
            radius: 0.18
        )
        return [(.high, head), (.mid, torso), (.low, legs)]
    }

    /// Swept 3D weapon or kick capsule at normalized active-window progress `t ∈ [0, 1]`.
    static func attackCapsule(for attacker: DuelGame.Fighter, move: DuelGame.Move,
                              chargeTicks: Int, progress t: Double) -> DuelWeaponCapsule {
        let fx = Double(attacker.x) / 1000.0
        let fy = Double(attacker.y) / 1000.0
        let dir = Double(attacker.facing)
        let u = min(1.0, max(0.0, t))
        let baseLen = weaponLengthMeters(for: attacker.hero)

        // Determine shoulder/hip origin, reach length, arc elevation sweep (rad), and capsule thickness
        let originY: Double
        let originFwd: Double
        let length: Double
        let startAngle: Double
        let endAngle: Double
        let radius: Double

        switch move {
        case .weaponUp:
            // Rising diagonal uppercut slash — sweeps low-mid straight through opponent's HEAD!
            originY = 1.18; originFwd = 0.16
            length = baseLen * 0.96
            startAngle = -0.35; endAngle = 0.68
            radius = 0.11

        case .weaponDown:
            // Low sweeping crouch slash — hugs floor (y ~ 0.14..0.38m) so jumping opponents vault cleanly over!
            originY = 0.32; originFwd = 0.18
            length = baseLen * 0.94
            startAngle = -0.14; endAngle = 0.06
            radius = 0.10

        case .kickDown:
            // Low sweeping leg trip — strictly low height (y ~ 0.12..0.32m), jumpable!
            originY = 0.24; originFwd = 0.14
            length = 0.82
            startAngle = -0.10; endAngle = 0.04
            radius = 0.10

        case .kickUp:
            // High roundhouse head kick — arcs upward into Head hurt capsule!
            originY = 1.12; originFwd = 0.12
            length = 0.88
            startAngle = 0.18; endAngle = 0.66
            radius = 0.12

        case .kick:
            originY = 0.98; originFwd = 0.14
            length = 0.80
            startAngle = -0.05; endAngle = 0.12
            radius = 0.12

        case .kickForward:
            originY = 1.04; originFwd = 0.20
            length = attacker.hero == .wuYong ? 1.08 : 0.92
            startAngle = -0.06; endAngle = 0.14
            radius = 0.13

        case .kickBack:
            originY = 1.06; originFwd = 0.14
            length = 0.90
            startAngle = 0.02; endAngle = 0.20
            radius = 0.12

        case .heavy:
            let chargedBonus = (attacker.hero == .wuYong && chargeTicks >= DuelShogunState.heavyFullChargeTicks) ? 0.28 : 0.10
            originY = 1.24; originFwd = 0.18
            length = baseLen + chargedBonus
            startAngle = 0.58; endAngle = -0.26
            radius = 0.13

        case .weaponForward:
            originY = 1.16; originFwd = 0.20
            length = baseLen + 0.08
            startAngle = 0.10; endAngle = -0.08
            radius = 0.11

        case .weaponBack:
            originY = 1.14; originFwd = 0.14
            length = baseLen * 0.94
            startAngle = 0.22; endAngle = -0.15
            radius = 0.11

        case .shogunFierceReprisal, .midnightRemoval:
            originY = 1.15; originFwd = 0.22
            length = baseLen + 0.34
            startAngle = 0.28; endAngle = -0.22
            radius = 0.15

        case .shogunDespotism:
            originY = 1.18; originFwd = 0.22
            length = baseLen + 0.42
            startAngle = -0.20; endAngle = 0.48
            radius = 0.15

        case .inquisitorLightSpin:
            originY = 1.48; originFwd = 0.18
            length = baseLen + 0.24
            startAngle = 0.14; endAngle = -0.14
            radius = 0.15

        case .inquisitorLightUp:
            // Soaring upward/neutral fast anti-air holy cleave
            originY = 1.56; originFwd = 0.18
            length = baseLen + 0.12
            startAngle = -0.25; endAngle = 0.65
            radius = 0.13

        case .inquisitorLightForward:
            // Soaring full-arena holy lance thrust
            originY = 1.46; originFwd = 0.28
            length = baseLen + 0.36
            startAngle = 0.08; endAngle = -0.10
            radius = 0.14

        case .inquisitorLightDown:
            // Soaring downward Light slam — dives straight down to floor (hits grounded & knocked-down foes!)
            originY = 1.28; originFwd = 0.22
            length = baseLen + 0.26
            startAngle = -0.35; endAngle = -1.12
            radius = 0.16

        case .skill1:
            originY = 1.12; originFwd = 0.14
            length = min(baseLen * 0.74, 0.78)
            startAngle = 0.22; endAngle = -0.14
            radius = 0.11

        case .skill2, .ultimate:
            originY = 1.12; originFwd = 0.18
            length = baseLen + 0.06
            startAngle = 0.28; endAngle = -0.18
            radius = 0.13

        case .throwForward, .throwBack:
            // Close grapple grab reach
            originY = 1.08; originFwd = 0.12
            length = 0.64
            startAngle = 0.0; endAngle = 0.0
            radius = 0.15

        case .wakeupKick:
            // Low rising ankle sweep from knockdown recovery
            originY = 0.24; originFwd = 0.14
            length = 0.96
            startAngle = -0.18; endAngle = 0.14
            radius = 0.14

        case .rollForward, .rollBack, .dashForward, .dashBack:
            // Non-hitting evasive roll / footwork dash (active == 0)
            originY = 0.45; originFwd = 0.0
            length = 0.05
            startAngle = 0.0; endAngle = 0.0
            radius = 0.01

        case .emperorTransform:
            // Radial 2.65m Shadow Beast transformation shockwave centered on Emperor
            originY = 1.05; originFwd = -0.35
            length = 2.65
            startAngle = 0.0; endAngle = 0.0
            radius = 0.42

        case .emperorBeastShadowJump:
            originY = 1.38; originFwd = 0.20
            length = 1.55
            startAngle = 0.25; endAngle = -0.75
            radius = 0.24

        case .legionShadowChain:
            // 28-link articulated 3D Shadow Chain extending linearly from 0.45m to 4.35m!
            originY = 1.15; originFwd = 0.35
            length = 0.65 + 3.65 * u
            startAngle = 0.0; endAngle = 0.0
            radius = 0.16

        case .legionShadowForward:
            originY = 1.18; originFwd = 0.24
            length = baseLen + 0.36
            startAngle = 0.24; endAngle = -0.22
            radius = 0.16

        case .legionShadowDown:
            originY = 1.32; originFwd = 0.22
            length = baseLen + 0.42
            startAngle = 0.65; endAngle = -0.95
            radius = 0.20

        case .monkeyAscensionPlunge:
            // Descending Jingu staff plunge from Ascension perch
            originY = 1.52; originFwd = 0.24
            length = baseLen + 0.55
            startAngle = 0.20; endAngle = -0.68
            radius = 0.16

        case .monkeyHeavenlyPillar:
            // Giant Jingu Pillar overhead slam
            originY = 1.65; originFwd = 0.26
            length = baseLen + 0.68
            startAngle = 0.72; endAngle = -0.92
            radius = 0.24

        case .jab, .cross, .finisher:
            originY = 1.16; originFwd = 0.16
            length = baseLen * (move == .finisher ? 1.04 : move == .cross ? 0.98 : 0.92)
            startAngle = move == .finisher ? 0.38 : 0.16
            endAngle = move == .finisher ? -0.24 : -0.10
            radius = 0.11
        }

        let angle = startAngle + (endAngle - startAngle) * u
        let bx = fx + dir * originFwd
        let by = fy + originY
        let tx = bx + dir * cos(angle) * length
        let ty = max(0.06, by + sin(angle) * length)
        return DuelWeaponCapsule(
            a: .init(x: bx, y: by, z: 0),
            b: .init(x: tx, y: ty, z: 0),
            radius: radius
        )
    }

    /// Perform continuous swept 3D capsule intersection across the current simulation tick
    /// between `attacker`'s weapon/limb and `defender`'s anatomical hurt zones (Head, Torso, Legs).
    /// Returns the earliest / highest-priority zone hit (Head priority for high strikes!) and exact 3D point.
    public static func evaluateSweep(
        attacker: DuelGame.Fighter,
        defender: DuelGame.Fighter,
        move: DuelGame.Move,
        chargeTicks: Int,
        activeAge: Int,
        activeDuration: Int
    ) -> Contact? {
        let span = Double(max(1, activeDuration))
        let t0 = Double(max(0, activeAge)) / span
        let t1 = Double(min(activeDuration, activeAge + 1)) / span

        let attackBefore = attackCapsule(for: attacker, move: move, chargeTicks: chargeTicks, progress: t0)
        let attackAfter = attackCapsule(for: attacker, move: move, chargeTicks: chargeTicks, progress: t1)
        let hurtZones = hurtCapsules(for: defender)

        var best: Contact?
        for (zone, hurt) in hurtZones {
            guard let hit = DuelWeaponCapsule.swept(
                attackBefore: attackBefore, attackAfter: attackAfter,
                hurtBefore: hurt, hurtAfter: hurt
            ) else { continue }
            let candidate = Contact(
                zone: zone,
                pointX: Int((hit.point.x * 1000.0).rounded()),
                pointY: Int((hit.point.y * 1000.0).rounded()),
                pointZ: Int((hit.point.z * 1000.0).rounded()),
                time: hit.time
            )
            if let existing = best {
                // Prioritize Head hit when both head and torso overlap within the same swept tick,
                // otherwise pick the earliest physical contact along the blade sweep!
                if candidate.zone == .high && existing.zone != .high && candidate.time <= existing.time + 0.35 {
                    best = candidate
                } else if existing.zone != .high && candidate.time < existing.time {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        return best
    }

    /// Detect authentic SF4 weapon-vs-weapon blade clash when both fighters swing active melee weapons
    /// through the same 3D space on the same tick.
    public static func evaluateBladeClash(
        first: DuelGame.Fighter, firstMove: DuelGame.Move, firstCharge: Int, firstAge: Int, firstActive: Int,
        second: DuelGame.Fighter, secondMove: DuelGame.Move, secondCharge: Int, secondAge: Int, secondActive: Int
    ) -> (pointX: Int, pointY: Int)? {
        let s1 = Double(max(1, firstActive)), s2 = Double(max(1, secondActive))
        let a0 = attackCapsule(for: first, move: firstMove, chargeTicks: firstCharge, progress: Double(max(0, firstAge)) / s1)
        let a1 = attackCapsule(for: first, move: firstMove, chargeTicks: firstCharge, progress: Double(min(firstActive, firstAge + 1)) / s1)
        let b0 = attackCapsule(for: second, move: secondMove, chargeTicks: secondCharge, progress: Double(max(0, secondAge)) / s2)
        let b1 = attackCapsule(for: second, move: secondMove, chargeTicks: secondCharge, progress: Double(min(secondActive, secondAge + 1)) / s2)
        guard let hit = DuelWeaponCapsule.swept(attackBefore: a0, attackAfter: a1, hurtBefore: b0, hurtAfter: b1) else {
            return nil
        }
        return (Int((hit.point.x * 1000.0).rounded()), Int((hit.point.y * 1000.0).rounded()))
    }
}
