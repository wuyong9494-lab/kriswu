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

    /// Physical blade / limb length in metres measured directly from the rigged 3D weapon GLBs.
    public static func weaponLengthMeters(for hero: DuelGame.Hero) -> Double {
        switch hero {
        case .wuYong: return 1.18   // Long Odachi (DuelWeapon_wuYong.glb = 1.181m)
        case .liu: return 1.05      // Two-Handed Great Axe (DuelWeapon_liuQuanwei.glb = 1.053m)
        case .gale: return 1.02     // Crusader Greatsword (DuelWeapon_xuXiao.glb = 1.015m)
        case .ember: return 0.64    // Dual Short Ninjato (DuelWeapon_sunDeng.glb = 0.605m)
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
            originY = 1.14; originFwd = 0.18
            length = baseLen + 0.20
            startAngle = 0.12; endAngle = -0.12
            radius = 0.14

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

        case .rollForward, .rollBack:
            // Non-hitting evasive roll (active == 0)
            originY = 0.45; originFwd = 0.0
            length = 0.05
            startAngle = 0.0; endAngle = 0.0
            radius = 0.01

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
}
