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
        let separation = separation.isFinite ? max(0, separation) : 3
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
