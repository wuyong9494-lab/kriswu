import Foundation

@main
struct ErlangParticleDistanceChecks {
    typealias Item = DuelSourceParticleOrder.Item
    static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw NSError(domain: "ErlangParticleDistance", code: 1, userInfo: [NSLocalizedDescriptionKey:message]) }
    }
    static func item(_ emitter: Int = 0, depth: Double, distance: Double?, mode: Int = 1) -> Item {
        .init(emitter: emitter, sortingLayer: 0, sortingOrder: 0, renderQueue: 3000,
            mode: mode, age: 0, viewDepth: depth, cameraDistanceSquared: distance)
    }
    static func main() throws {
        // Camera at zero: (0,0,-3), (8,0,-2), (0,0,-6). Off-axis
        // smoke is the most distant despite having the nearest depth.
        let values = [item(depth:-3,distance:9),item(depth:-2,distance:68),item(depth:-6,distance:36)]
        try require(try DuelSourceParticleOrder.indices(values)==[1,2,0], "Distance was replaced with camera Depth")
        let depths = values.map { item(depth:$0.viewDepth,distance:nil,mode:4) }
        try require(try DuelSourceParticleOrder.indices(depths)==[2,0,1], "Existing Depth contract changed")
        print("PASS off-axis smoke uses actual camera distance independently of depth")

        let interleaved = [item(0,depth:-2,distance:8),item(1,depth:-3,distance:9),
            item(0,depth:-2,distance:8),item(1,depth:-4,distance:16)]
        try require(try DuelSourceParticleOrder.indices(interleaved)==[0,2,3,1], "Distance broke stable ties or emitter grouping")
        print("PASS equal distances retain source order and distinct emitters stay grouped")

        var rejected = 0
        for value in [item(depth:-1,distance:nil),item(depth:-1,distance:-1),item(depth:-1,distance:.infinity),
                      item(depth:-1,distance:.nan),item(depth:-1,distance:1,mode:4)] {
            do { _ = try DuelSourceParticleOrder.indices([value]) } catch { rejected += 1 }
        }
        try require(rejected==5, "Missing or invalid distance was accepted or leaked into old modes")
        print("PASS missing/nonfinite/negative distances and foreign mode keys reject")
    }
}
