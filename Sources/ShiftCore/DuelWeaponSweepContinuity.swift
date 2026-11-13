import Foundation

/// Application-side limit for adjacent weapon samples, in metres per simulation
/// tick. This is a discontinuity guard, not a recovered source-game event table.
/// Combat, swing onset and rendered ribbons use the same inclusive ceiling.
public enum DuelWeaponSweepContinuity {
    public static let maximumAdjacentDistance: Double = 0.75

    public static func accepts(distance: Double) -> Bool {
        distance.isFinite && distance >= 0 && distance <= maximumAdjacentDistance
    }

    /// SceneKit endpoints are Float world positions (bounded to +/-50m by the
    /// renderer). Ten micrometres cover their subtraction/length roundoff;
    /// gameplay's Double samples retain the exact ceiling above.
    public static func acceptsRendered(distance: Float) -> Bool {
        distance.isFinite && distance >= 0 && distance <= Float(maximumAdjacentDistance) + 0.00001
    }

    public static func distance(from a: DuelWeaponPoint, to b: DuelWeaponPoint) -> Double {
        hypot(hypot(b.x - a.x, b.y - a.y), b.z - a.z)
    }
}
