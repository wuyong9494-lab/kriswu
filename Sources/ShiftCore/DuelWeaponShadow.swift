import Foundation

/// Provisional native rules, not recovered SF3 event timing. Source animation,
/// rig and materials are retained; discontinuous shadow tracks are never swept.
public enum DuelShadowKind: Equatable, Sendable { case katanaDash, hammerThrow }

/// Read-only presentation derived from the authoritative fixed-step action.
/// A returned hammer is visible but never a second damage source.
public struct DuelShadowVisual: Equatable, Sendable {
    public let kind: DuelShadowKind
    public let tick: Int
    public let duration: Int
    public let isAttacking: Bool
    public let weaponBase: DuelWeaponPoint?
    public let weaponTip: DuelWeaponPoint?
}

enum DuelShadowRules {
    struct HammerSegment: Equatable, Sendable {
        let base: DuelWeaponPoint
        let tip: DuelWeaponPoint
    }
    static let startup = 24
    static let cooldown = 360
    static func duration(katana: Bool) -> Int { katana ? 72 : 96 }
    static func active(_ tick: Int, katana: Bool) -> Bool {
        (startup..<(katana ? 40 : 48)).contains(tick)
    }
    /// A single authoritative path for the real mesh, trails and contact.
    /// Release/catch coincide with the mapped held poses; this is a native
    /// boundary guarantee, not a recovered original skill event table.
    static func hammer(_ tick: Int, origin: Int, direction: Int,
                       release: HammerSegment, catchPose: HammerSegment,
                       length: Double) -> HammerSegment? {
        guard (24..<72).contains(tick), direction == -1 || direction == 1,
              (DuelGame.leftWall...DuelGame.rightWall).contains(origin),
              valid(release), valid(catchPose), length.isFinite, length > 0.000001,
              length <= maximumCoordinate,
              let releaseAxis = unit(difference(release.tip, release.base)),
              let catchAxis = unit(difference(catchPose.tip, catchPose.base)) else { return nil }
        // Preserve the former absolute apex, not an extra 4.8 m measured from
        // a newly shifted hand. Only existing held geometry may lie beyond a
        // wall; do not clip it, shorten the weapon, or add outward throw reach.
        let apex = DuelWeaponPoint(
            x: Double(min(DuelGame.rightWall, max(DuelGame.leftWall, origin + direction * 5250))) / 1000,
            y: 0.82, z: 0.08)
        let outbound = tick < 48
        let weight = Double(outbound ? tick - 24 : tick - 48) / 23
        let held = outbound ? release : catchPose
        let up = DuelWeaponPoint(x: 0, y: 1, z: 0)
        guard let axis = blendAxis(outbound ? releaseAxis : up, outbound ? up : catchAxis,
                                   weight: weight, direction: direction) else { return nil }
        var base = outbound ? release.base.mixed(with: apex, weight: weight)
                            : apex.mixed(with: catchPose.base, weight: weight)
        let offset = scaled(axis, length)
        // One rigid translation keeps both endpoints within the old apex /
        // already-held horizontal extent. min/max are continuous; endpoint
        // anchors are unchanged because that extent includes their full shaft.
        let lower = min(Double(DuelGame.leftWall) / 1000, held.base.x, held.tip.x, apex.x)
        let upper = max(Double(DuelGame.rightWall) / 1000, held.base.x, held.tip.x, apex.x)
        let forwardLimit = direction > 0 ? max(apex.x, held.base.x, held.tip.x)
                                         : min(apex.x, held.base.x, held.tip.x)
        let minimumBase = (direction < 0 ? forwardLimit : lower) - min(0, offset.x)
        let maximumBase = (direction > 0 ? forwardLimit : upper) - max(0, offset.x)
        guard minimumBase <= maximumBase else { return nil }
        base.x = min(maximumBase, max(minimumBase, base.x))
        let result = HammerSegment(base: base, tip: sum(base, offset))
        return valid(result) ? result : nil
    }

    /// Narrow contact against the same successive endpoint samples. Endpoint
    /// paths and analytic rectangle-corner events include folded sweeps without
    /// filling an empty AABB/convex hull. Startup only checks the current shaft.
    static func hammerContact(previous: HammerSegment, current: HammerSegment,
                              sweep: Bool, hurt: DuelGame.Box) -> DuelWeaponPoint? {
        let points = [previous.base, previous.tip, current.base, current.tip]
        guard valid(previous), valid(current), points.allSatisfy({ abs($0.z) < 0.8 }),
              DuelWeaponSweepContinuity.accepts(distance: distance(previous.base, current.base)),
              DuelWeaponSweepContinuity.accepts(distance: distance(previous.tip, current.tip)) else { return nil }
        let radius = 0.18
        // This is numerical tolerance (0.1 nanometres), not an extra collision
        // margin. It admits an analytically computed corner within rounding.
        let epsilon = 0.0000000001
        func contact(_ a: DuelWeaponPoint, _ b: DuelWeaponPoint) -> DuelWeaponPoint? {
            var lo = 0.0, hi = 1.0
            for (start, end, lower, upper) in [
                (a.x, b.x, Double(hurt.minX) / 1000 - radius - epsilon, Double(hurt.maxX) / 1000 + radius + epsilon),
                (a.y, b.y, Double(hurt.minY) / 1000 - radius - epsilon, Double(hurt.maxY) / 1000 + radius + epsilon)
            ] {
                let delta = end - start
                if abs(delta) < 0.0000001 {
                    if start < lower || start > upper { return nil }
                } else {
                    let p = (lower - start) / delta, q = (upper - start) / delta
                    lo = max(lo, min(p, q)); hi = min(hi, max(p, q))
                    if lo > hi { return nil }
                }
            }
            return a.mixed(with: b, weight: lo)
        }
        func onHurt(_ point: DuelWeaponPoint) -> DuelWeaponPoint {
            .init(x: min(Double(hurt.maxX) / 1000, max(Double(hurt.minX) / 1000, point.x)),
                  y: min(Double(hurt.maxY) / 1000, max(Double(hurt.minY) / 1000, point.y)), z: point.z)
        }
        if let point = contact(current.base, current.tip) { return onHurt(point) }
        guard sweep else { return nil }
        for (a, b) in [(previous.base, previous.tip), (previous.base, current.base), (previous.tip, current.tip)] {
            if let point = contact(a, b) { return onHurt(point) }
        }
        // With both moving endpoints and the initial shaft outside the box,
        // any remaining first contact has a fixed box corner on the shaft.
        // A(t)=A0+t*dA; V(t)=B(t)-A(t). cross(V(t), corner-A(t))=0
        // is quadratic, with at most two candidate times per corner. Testing
        // the actual shaft rejects roots on its supporting line only.
        func cross(_ a: DuelWeaponPoint, _ b: DuelWeaponPoint) -> Double { a.x * b.y - a.y * b.x }
        let motion = difference(current.base, previous.base)
        let axis = difference(previous.tip, previous.base)
        let axisMotion = difference(difference(current.tip, previous.tip), motion)
        for x in [Double(hurt.minX) / 1000 - radius, Double(hurt.maxX) / 1000 + radius] {
            for y in [Double(hurt.minY) / 1000 - radius, Double(hurt.maxY) / 1000 + radius] {
                let offset = difference(.init(x: x, y: y), previous.base)
                for time in roots(a: -cross(axisMotion, motion),
                                  b: cross(axisMotion, offset) - cross(axis, motion), c: cross(axis, offset)) {
                    guard time >= -1e-12, time <= 1 + 1e-12 else { continue }
                    let t = min(1, max(0, time))
                    if let point = contact(previous.base.mixed(with: current.base, weight: t),
                                           previous.tip.mixed(with: current.tip, weight: t)) { return onHurt(point) }
                }
            }
        }
        return nil
    }

    static func valid(_ segment: HammerSegment) -> Bool {
        [segment.base, segment.tip].allSatisfy { point in
            [point.x, point.y, point.z].allSatisfy { $0.isFinite && abs($0) <= maximumCoordinate }
        } && distance(segment.base, segment.tip) > 0.000001
    }
    static func distance(_ a: DuelWeaponPoint, _ b: DuelWeaponPoint) -> Double {
        hypot(hypot(b.x - a.x, b.y - a.y), b.z - a.z)
    }
    // Leave padding before conversion to integer millimetres. A catalog only
    // guarantees finite numbers; huge finite coordinates must not trap in Int.
    private static let maximumCoordinate = Double(Int32.max - 1000) / 1000
    private static func difference(_ a: DuelWeaponPoint, _ b: DuelWeaponPoint) -> DuelWeaponPoint {
        .init(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
    }
    private static func sum(_ a: DuelWeaponPoint, _ b: DuelWeaponPoint) -> DuelWeaponPoint {
        .init(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)
    }
    private static func scaled(_ a: DuelWeaponPoint, _ value: Double) -> DuelWeaponPoint {
        .init(x: a.x * value, y: a.y * value, z: a.z * value)
    }
    private static func dot(_ a: DuelWeaponPoint, _ b: DuelWeaponPoint) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }
    private static func roots(a: Double, b: Double, c: Double) -> [Double] {
        let scale = max(abs(a), abs(b), abs(c))
        guard scale.isFinite, scale > 0 else { return [] }
        let a = a / scale, b = b / scale, c = c / scale
        if abs(a) < 1e-12 { return abs(b) < 1e-12 ? [] : [-c / b] }
        let discriminant = b * b - 4 * a * c
        guard discriminant >= -1e-12 else { return [] }
        let squareRoot = sqrt(max(0, discriminant))
        let q = -0.5 * (b + (b >= 0 ? squareRoot : -squareRoot))
        return abs(q) < 1e-15 ? [-b / (2 * a)] : [q / a, c / q]
    }
    private static func unit(_ point: DuelWeaponPoint) -> DuelWeaponPoint? {
        let length = hypot(hypot(point.x, point.y), point.z)
        guard length.isFinite, length > 0.000001 else { return nil }
        return scaled(point, 1 / length)
    }
    private static func blendAxis(_ a: DuelWeaponPoint, _ b: DuelWeaponPoint,
                                  weight: Double, direction: Int) -> DuelWeaponPoint? {
        if weight <= 0 { return a }
        if weight >= 1 { return b }
        if dot(a, b) > -0.999 { return unit(a.mixed(with: b, weight: weight)) }
        // Antiparallel axes cannot be linearly normalized through zero. Pick
        // an orthogonal route deterministically, mirrored with fighter facing.
        let hint = abs(a.x) < 0.9 ? DuelWeaponPoint(x: Double(direction)) : DuelWeaponPoint(z: 1)
        guard let middle = unit(difference(hint, scaled(a, dot(hint, a)))) else { return nil }
        return weight < 0.5 ? unit(a.mixed(with: middle, weight: weight * 2))
                            : unit(middle.mixed(with: b, weight: weight * 2 - 1))
    }
}
