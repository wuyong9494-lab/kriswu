import Foundation

/// Shared projection policy for layout and every rendered combat frame.
/// Keeps the wide-screen close-up while retaining a safe overview in narrow
/// windows and during portrait-to-landscape transitions.
public struct DuelCameraFraming: Equatable, Sendable {
    public let verticalFieldOfView: Double
    public let orthographicScale: Double
    public let perspectiveDistance: Double

    public init(aspect: Double, separation: Double) {
        let aspect = aspect.isFinite ? max(0.1, aspect) : 1
        let separation = separation.isFinite ? max(0, separation) : 3
        let wide = aspect >= 1.5
        let closeUpFOV = min(46, 27 + max(0, separation - 3.8) * 4)
        let overviewFOV = 2 * atan(5.8 / (7.7 * aspect)) * 180 / .pi
        verticalFieldOfView = wide ? closeUpFOV : min(100, max(closeUpFOV, overviewFOV))
        // Preserve the safe overview even after the FOV cap is reached.
        // Back away only for narrow windows, avoiding extreme perspective.
        perspectiveDistance = wide ? 7.3 : max(7.3,
            5.8 / (aspect * tan(verticalFieldOfView * .pi / 360)))
        let combatScale = max(2.65, separation * 0.56 + 0.65)
        orthographicScale = wide ? combatScale : max(combatScale, max(3.2, 5.8 / aspect))
    }
}
