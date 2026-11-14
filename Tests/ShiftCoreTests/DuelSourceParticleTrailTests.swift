import XCTest
@testable import ShiftCore

final class DuelSourceParticleTrailTests: XCTestCase {
    func testStoredWorldPointsDoNotFollowLaterWeaponMovement() throws {
        var trail = try DuelSourceParticleTrail(lifetimeSeconds: 0.2, minimumVertexDistance: 0.002)
        try trail.sample(tick: 0, worldPosition: .init(x: 1, y: 2), emitting: true)
        try trail.sample(tick: 1, worldPosition: .init(x: 4, y: 3), emitting: true)
        XCTAssertEqual(trail.points(at: 1).map(\.position), [.init(x: 1, y: 2), .init(x: 4, y: 3)])
    }
    func testRepeatedDrawAndFrozenTickCannotAdvanceTrail() throws {
        var trail = try DuelSourceParticleTrail(lifetimeSeconds: 0.24, minimumVertexDistance: 0.002)
        try trail.sample(tick: 7, worldPosition: .init(x: 1), emitting: true)
        let frozen = trail
        for _ in 0..<20 {
            _ = trail.points(at: 7)
            try trail.sample(tick: 7, worldPosition: .init(x: 20), emitting: true)
        }
        XCTAssertEqual(trail, frozen)
    }
    func testTailOutlivesParticleThenExpiresAtFractionalSourceLifetime() throws {
        var trail = try DuelSourceParticleTrail(lifetimeSeconds: 0.225, minimumVertexDistance: 0.002)
        try trail.sample(tick: 0, worldPosition: .init(), emitting: true)
        try trail.sample(tick: 1, worldPosition: .init(x: 0.01), emitting: true)
        try trail.sample(tick: 2, worldPosition: nil, emitting: false)
        XCTAssertEqual(trail.points(at: 13).count, 2)
        XCTAssertEqual(trail.points(at: 14).count, 1)
        XCTAssertTrue(trail.points(at: 15).isEmpty)
    }
    func testMinimumDistanceIsAppliedInWorldMetresOnce() throws {
        var trail = try DuelSourceParticleTrail(lifetimeSeconds: 0.2, minimumVertexDistance: 0.2 * 0.01)
        try trail.sample(tick: 0, worldPosition: .init(), emitting: true)
        try trail.sample(tick: 1, worldPosition: .init(x: 0.001), emitting: true)
        try trail.sample(tick: 2, worldPosition: .init(x: 0.003), emitting: true)
        XCTAssertEqual(trail.points(at: 2).map(\.position.x), [0, 0.003])
    }
    func testMissingIntermediateFramesAreNotInventedAndInvalidInputFails() throws {
        var trail = try DuelSourceParticleTrail(lifetimeSeconds: 0.2, minimumVertexDistance: 0.002)
        try trail.sample(tick: 0, worldPosition: .init(), emitting: true)
        try trail.sample(tick: 4, worldPosition: .init(x: 0.04), emitting: true)
        XCTAssertEqual(trail.points(at: 4).map(\.tick), [0, 4])
        let unchanged = trail
        XCTAssertThrowsError(try trail.sample(tick: 5, worldPosition: .init(x: .nan), emitting: true))
        XCTAssertEqual(trail, unchanged)
        try trail.sample(tick: 5, worldPosition: .init(x: 0.05), emitting: true)
        XCTAssertEqual(trail.points(at: 5).last?.position.x, 0.05)
        XCTAssertThrowsError(try DuelSourceParticleTrail(lifetimeSeconds: .infinity, minimumVertexDistance: 0.002))
    }
}
