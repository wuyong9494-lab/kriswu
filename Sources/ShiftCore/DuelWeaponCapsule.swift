import Foundation

/// Geometry shared by recovered bone-bound attack and hurt capsules. Source
/// radii are metres here; tracks and replay retain exact integer millimetres.
struct DuelWeaponCapsule: Equatable, Sendable {
    let a: DuelWeaponPoint
    let b: DuelWeaponPoint
    let radius: Double

    struct Contact: Equatable, Sendable {
        let time: Double
        let point: DuelWeaponPoint
    }
    private static func sub(_ a: DuelWeaponPoint, _ b: DuelWeaponPoint) -> DuelWeaponPoint {
        .init(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
    }
    private static func dot(_ a: DuelWeaponPoint, _ b: DuelWeaponPoint) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
    private static func length(_ a: DuelWeaponPoint) -> Double { sqrt(dot(a, a)) }
    private func mixed(with other: Self, at t: Double) -> Self {
        .init(a: a.mixed(with: other.a, weight: t), b: b.mixed(with: other.b, weight: t), radius: radius)
    }
    /// Closest points of finite 3D segments, including zero-length hands/feet.
    private static func closest(_ p: Self, _ q: Self) -> (Double, DuelWeaponPoint) {
        let u = sub(p.b, p.a), v = sub(q.b, q.a), r = sub(p.a, q.a)
        let aa = dot(u, u), ee = dot(v, v), ff = dot(v, r)
        var s = 0.0, t = 0.0
        let epsilon = 1e-14
        if aa <= epsilon && ee <= epsilon { return (length(sub(p.a, q.a)), q.a) }
        if aa <= epsilon { t = min(1, max(0, ff / ee)) }
        else {
            let cc = dot(u, r)
            if ee <= epsilon { s = min(1, max(0, -cc / aa)) }
            else {
                let bb = dot(u, v), denominator = aa * ee - bb * bb
                if denominator > epsilon { s = min(1, max(0, (bb * ff - cc * ee) / denominator)) }
                t = (bb * s + ff) / ee
                if t < 0 { t = 0; s = min(1, max(0, -cc / aa)) }
                else if t > 1 { t = 1; s = min(1, max(0, (bb - cc) / aa)) }
            }
        }
        let pPoint = p.a.mixed(with: p.b, weight: s), qPoint = q.a.mixed(with: q.b, weight: t)
        return (length(sub(pPoint, qPoint)), qPoint)
    }
    func overlaps(_ other: Self) -> Bool { Self.closest(self, other).0 <= radius + other.radius + 1e-9 }

    /// Conservative advancement for linearly interpolated source samples.
    /// The sum of maximum endpoint speeds bounds how quickly the segment
    /// distance can close, so a fast moving blade cannot skip a thin forearm.
    /// The small tolerance is numerical (one micrometre), not extra hit reach.
    static func swept(attackBefore: Self, attackAfter: Self,
                      hurtBefore: Self, hurtAfter: Self) -> Contact? {
        let speed = max(length(sub(attackAfter.a, attackBefore.a)), length(sub(attackAfter.b, attackBefore.b))) +
            max(length(sub(hurtAfter.a, hurtBefore.a)), length(sub(hurtAfter.b, hurtBefore.b)))
        let radius = max(attackBefore.radius, attackAfter.radius) + max(hurtBefore.radius, hurtAfter.radius)
        var time = 0.0
        for _ in 0..<1024 {
            let attack = attackBefore.mixed(with: attackAfter, at: time)
            let hurt = hurtBefore.mixed(with: hurtAfter, at: time)
            let (distance, point) = closest(attack, hurt)
            let gap = distance - radius
            if gap <= 1e-6 { return .init(time: time, point: point) }
            guard speed > 1e-12 else { return nil }
            let advance = gap / speed
            if time + advance > 1 { return nil }
            time += max(advance * 0.95, 1e-10)
            if time > 1 { break }
        }
        let end = closest(attackAfter, hurtAfter)
        return end.0 <= radius + 1e-6 ? .init(time: 1, point: end.1) : nil
    }
}
