import Foundation

@main
struct ErlangParticleFacingChecks {
    typealias Facing = DuelErlangParticleFacing
    typealias Vector = SIMD3<Float>
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "ErlangParticleFacing", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func dot(_ a: Vector, _ b: Vector) -> Float { a.x*b.x + a.y*b.y + a.z*b.z }
    static func cross(_ a: Vector, _ b: Vector) -> Vector {
        Vector(a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x)
    }
    static func validate(_ b: Facing.Basis) throws {
        try require(abs(dot(b.right,b.right)-1) < 1e-6 && abs(dot(b.up,b.up)-1) < 1e-6 &&
            abs(dot(b.normal,b.normal)-1) < 1e-6, "orientation has scale")
        try require(abs(dot(b.right,b.up)) < 1e-6 && abs(dot(b.right,b.normal)) < 1e-6 &&
            abs(dot(b.up,b.normal)) < 1e-6 && dot(cross(b.right,b.up),b.normal) > 0.999999,
            "orientation is skewed or mirrored")
    }
    static func main() throws {
        let up = Vector(0,1,0), right = Vector(1,0,0), camera = Vector(0,0,10)
        guard let left = Facing.facing(camera: camera, particle: Vector(-5,0,0), cameraUp: up, cameraRight: right),
              let center = Facing.facing(camera: camera, particle: .zero, cameraUp: up, cameraRight: right),
              let opposite = Facing.facing(camera: camera, particle: Vector(5,0,0), cameraUp: up, cameraRight: right) else {
            throw NSError(domain: "missing facing", code: 1)
        }
        for basis in [left,center,opposite] { try validate(basis) }
        try require(left.normal.x > 0 && center.normal == Vector(0,0,1) && opposite.normal.x < 0,
            "Facing reused one View plane for different particle positions")
        print("PASS individual dust particles face the eye with independent orthonormal bases")

        guard let pole = Facing.facing(camera: Vector(0,10,0), particle: .zero, cameraUp: up, cameraRight: right) else {
            throw NSError(domain: "missing pole basis", code: 1)
        }
        try validate(pole)
        try require(pole.normal == up && pole.right == right, "camera-up pole lost the original camera-right fallback")
        print("PASS eye-overhead pole remains finite and has a stable source orientation")

        try validate(Facing.horizontal)
        try require(Facing.horizontal.right.y == 0 && Facing.horizontal.up.y == 0 &&
            Facing.horizontal.normal == up, "horizontal source ring left its world ground plane")
        print("PASS horizontal ring stays in world X/Z independently of camera facing")

        try require(Facing.facing(camera: .zero, particle: .zero, cameraUp: up, cameraRight: right) == nil &&
            Facing.facing(camera: Vector(.nan,0,0), particle: .zero, cameraUp: up, cameraRight: right) == nil &&
            Facing.facing(camera: camera, particle: .zero, cameraUp: .zero, cameraRight: .zero) == nil,
            "degenerate orientation was silently invented")
        print("PASS coincident, nonfinite and degenerate camera vectors reject")
    }
}
