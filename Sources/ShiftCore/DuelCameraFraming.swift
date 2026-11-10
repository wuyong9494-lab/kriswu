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
        let closeUpFOV = min(47, 31 + max(0, separation - 4.5) * 3)
        // Separation already includes any lag from tracking the pair. Reserve
        // room for their silhouettes rather than fitting only the root points.
        let requiredHalfWidth = max(wide ? 0 : 5.8, separation * 0.5 + 0.8)
        let overviewFOV = 2 * atan(requiredHalfWidth / (7.7 * aspect)) * 180 / .pi
        verticalFieldOfView = wide ? closeUpFOV : min(100, max(closeUpFOV, overviewFOV))
        // Preserve the safe overview even after the FOV cap is reached.
        // At 3:2 landscape the 47-degree cap alone cannot contain a fully
        // separated pair. Back away when necessary in either orientation.
        perspectiveDistance = max(7.7,
            requiredHalfWidth / (aspect * tan(verticalFieldOfView * .pi / 360)))
        let combatScale = max(2.85, separation * 0.56 + 0.8)
        orthographicScale = wide ? combatScale : max(combatScale, max(3.2, 5.8 / aspect))
    }
}
