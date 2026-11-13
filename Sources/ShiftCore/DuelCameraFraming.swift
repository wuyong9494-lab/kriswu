import Foundation

/// Shared projection policy for layout and every rendered combat frame.
/// Keeps the wide-screen close-up while retaining a safe overview in narrow
/// windows and during portrait-to-landscape transitions.
public struct DuelCameraFraming: Equatable, Sendable {
    public let verticalFieldOfView: Double
    public let orthographicScale: Double
    public let perspectiveDistance: Double

    private static func smoothstep(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    public init(aspect: Double, separation: Double) {
        let aspect = aspect.isFinite ? max(0.1, aspect) : 1
        // Fighters are clamped to the ten-unit stage before tracking. Limit
        // unexpected finite input to the largest representable pair envelope
        // instead of letting an overflow create an infinite SceneKit distance.
        let separation = separation.isFinite ? min(20, max(0, separation)) : 3
        // Blend out the full-stage safety overview as the viewport becomes
        // landscape. A hard 1.5 aspect cut made rotation change the lens
        // abruptly, even when the fighters had not moved.
        let landscapeBlend = Self.smoothstep((aspect - 1.2) / 0.6)
        let closeUpFOV = min(47, 29 + max(0, separation - 4.5) * 3)
        let requiredHalfWidth = max(separation * 0.5 + 0.8, 5.8 * (1 - landscapeBlend))
        let overviewFOV = 2 * atan(requiredHalfWidth / (7.7 * aspect)) * 180 / .pi
        // The portrait FOV allowance tapers into the 47-degree landscape
        // cap continuously; distance compensates whenever that cap is reached.
        let fovCap = 47 + 53 * (1 - Self.smoothstep((aspect - 1) / 0.5))
        verticalFieldOfView = min(fovCap, max(closeUpFOV, overviewFOV))
        perspectiveDistance = max(7.7,
            requiredHalfWidth / (aspect * tan(verticalFieldOfView * .pi / 360)))
        let combatScale = max(2.85, separation * 0.56 + 0.8)
        orthographicScale = max(combatScale,
                                max(3.2, 5.8 / aspect) * (1 - landscapeBlend))
    }
}

    
/// Keeps the real skin/weapon projection safe while avoiding an abrupt zoom-in
/// every time an animated blade returns to its idle silhouette. This filter is
/// presentation-only: required FOV can always expand immediately.
public struct DuelCameraOpticalFOV: Equatable, Sendable {
    private var lastFrame: Int?
    // Anchor minor UIKit layout variation; do not mistake a gradual device
    // rotation for harmless jitter by comparing only consecutive callbacks.
    private var aspectAnchor: Double?
    private var lastValue: Double?

    public init() {}
    public mutating func reset() { self = Self() }

    /// When measured source geometry fails, never replace the last proven
    /// wide projection with the narrower pair-only estimate. This is a
    /// presentation fallback, NOT proof that the unknown pose fits the screen.
    /// Do not advance the optical clock during a failed measurement: a later
    /// valid pose can still widen immediately or resume normal contraction.
    public func retainedAfterFailedFit(minimum: Double) -> Double {
        guard minimum.isFinite, minimum > 0, minimum < 180 else {
            return lastValue ?? 47
        }
        return max(minimum, lastValue ?? minimum)
    }

    /// Consuming the same simulation frame more than once may widen the view,
    /// but never narrow it. Layout passes must not speed up the transition.
    public mutating func consume(required: Double, frame: Int, aspect: Double) -> Double {
        guard required.isFinite, required > 0, required < 180,
              frame >= 0, aspect.isFinite, aspect > 0 else {
            return lastValue ?? 47
        }
        if let previous = lastFrame, let anchor = aspectAnchor,
           frame >= previous, abs(aspect - anchor) <= 0.04,
           let current = lastValue {
            if frame == previous {
                lastValue = max(current, required)
            } else if required >= current {
                lastValue = required
            } else {
                let elapsed = min(60, Double(frame - previous))
                lastValue = required + (current - required) * pow(0.92, elapsed)
            }
        } else {
            // A new bout, rewind or material orientation change starts from
            // the actual safe fit, not the previous animation's wide pose.
            lastValue = required
            aspectAnchor = aspect
        }
        lastFrame = frame
        return lastValue!
    }
}
