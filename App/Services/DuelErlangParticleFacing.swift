import Foundation

/// Unity's View, Facing and Horizontal modes are distinct. This small pure
/// basis helper has no simulation clock, attachment state or particle motion.
enum DuelErlangParticleFacing {
    typealias Vector = SIMD3<Float>
    struct Basis: Equatable { let right: Vector; let up: Vector; let normal: Vector }
    static let horizontal = Basis(right: Vector(1, 0, 0), up: Vector(0, 0, -1), normal: Vector(0, 1, 0))
    private static func dot(_ a: Vector, _ b: Vector) -> Float { a.x*b.x + a.y*b.y + a.z*b.z }
    private static func cross(_ a: Vector, _ b: Vector) -> Vector {
        Vector(a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x)
    }
    private static func unit(_ vector: Vector) -> Vector? {
        let length = dot(vector, vector)
        guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite,
              length.isFinite, length > 1e-12 else { return nil }
        return vector / sqrt(length)
    }
    /// Unlike View's single camera-plane basis, Facing points each particle
    /// toward the eye. Camera right resolves the pole without changing clock.
    static func facing(camera: Vector, particle: Vector, cameraUp: Vector, cameraRight: Vector) -> Basis? {
        guard let normal = unit(camera-particle) else { return nil }
        let right = unit(cross(cameraUp, normal)) ?? unit(cameraRight-normal*dot(cameraRight, normal))
        guard let right, let up = unit(cross(normal, right)) else { return nil }
        return .init(right: right, up: up, normal: normal)
    }
}
