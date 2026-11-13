import XCTest
import SceneKit
@testable import ShiftReminder

/// Geometry/lifecycle checks use the explicit DEBUG preparation fixture. They
/// neither load source artwork nor replace real-resource visual acceptance.
@MainActor
final class DuelWeaponTrailContinuityTests: XCTestCase {
    func testFirstActiveSampleSeedsOnlyWithinInclusiveAdjacentCeiling() throws {
        for origin in [Float(0), 0.7, 20.3] {
          for step in [Float(0.74), 0.75, 0.76] {
            let root = SCNNode()
            let subject = DuelWeaponEffects.preparationFixture(root: root)
            defer { subject.shutdown() }
            subject.consumeStep(poses: [pose(x: origin, active: false)], animationTick: 0)
            subject.consumeStep(poses: [pose(x: origin + step)], animationTick: 1)
            XCTAssertEqual(subject.renderedVertexCount, step <= 0.75 ? 4 : 0, "origin \(origin), step \(step)")
          }
        }
    }

    func testActiveTeleportStartsAnUnbridgedStripAndNextValidStepResumes() throws {
        let root = SCNNode()
        let effects = DuelWeaponEffects.preparationFixture(root: root)
        defer { effects.shutdown() }
        effects.consumeStep(poses: [pose(x: 0)], animationTick: 0)
        effects.consumeStep(poses: [pose(x: 0.1)], animationTick: 1)
        effects.consumeStep(poses: [pose(x: 0.9)], animationTick: 2)
        let container = try XCTUnwrap(root.childNode(withName: "duel.weapon-effects", recursively: false))
        XCTAssertEqual(container.childNodes.count, 2)
        let retiringRoot = try XCTUnwrap(container.childNodes.first)
        let currentRoot = try XCTUnwrap(container.childNodes.last)
        let currentID = try XCTUnwrap(effects.trailDiagnostics.emitters.first?.stripID)
        XCTAssertNil(container.childNodes.last?.childNodes.first?.geometry,
                     "A teleported point must not bridge to the old ribbon")
        effects.consumeStep(poses: [pose(x: 1)], animationTick: 3)
        XCTAssertEqual(container.childNodes.last?.childNodes.first?.geometry?.sources(for: .vertex).first?.vectorCount, 4)
        for tick in 4...30 {
            effects.consumeStep(poses: [pose(x: 1 + Float(tick - 3) * 0.01)], animationTick: tick)
            XCTAssertEqual(effects.trailDiagnostics.emitters.map(\.stripID), [currentID])
            XCTAssertEqual(effects.retainedTrailCount, 2, "The old strip retains its original 0.5s fade")
        }
        let retiring = try XCTUnwrap(effects.trailDiagnostics.retained.first { $0.id != currentID })
        XCTAssertEqual(retiring.samples.map(\.tick), [1], "Retired samples expire but never receive current endpoints")
        XCTAssertTrue(retiringRoot.parent === container)
        effects.consumeStep(poses: [pose(x: 1.28)], animationTick: 31)
        XCTAssertEqual(effects.retainedTrailCount, 1, "The last old sample expires at exactly 30 ticks")
        XCTAssertNil(retiringRoot.parent)
        XCTAssertTrue(currentRoot.parent === container)
        XCTAssertEqual(effects.trailDiagnostics.emitters.map(\.stripID), [currentID],
                       "Retiring the old strip cannot remove the new owner of the same weapon slot")
        XCTAssertEqual(effects.trailDiagnostics.retained.first?.samples.last?.tick, 31)
        effects.consumeStep(poses: [], animationTick: 32)
        XCTAssertTrue(effects.trailDiagnostics.emitters.isEmpty)
        effects.consumeStep(poses: [], animationTick: 60)
        XCTAssertEqual(effects.retainedTrailCount, 1)
        effects.consumeStep(poses: [], animationTick: 61)
        XCTAssertEqual(effects.retainedTrailCount, 0)
        XCTAssertTrue(container.childNodes.isEmpty)
    }

    func testSkippedSimulationTickCannotJoinOtherwiseNearbySamples() throws {
        let root = SCNNode()
        let effects = DuelWeaponEffects.preparationFixture(root: root)
        defer { effects.shutdown() }
        effects.consumeStep(poses: [pose(x: 0)], animationTick: 0)
        effects.consumeStep(poses: [pose(x: 0.1)], animationTick: 1)
        effects.consumeStep(poses: [pose(x: 0.2)], animationTick: 3)
        let container = try XCTUnwrap(root.childNode(withName: "duel.weapon-effects", recursively: false))
        XCTAssertEqual(container.childNodes.count, 2)
        XCTAssertNil(container.childNodes.last?.childNodes.first?.geometry)
    }

    func testBothHammersKeepIndependentContinuityAndPreparationOwnership() throws {
        let root = SCNNode()
        let effects = DuelWeaponEffects.preparationFixture(root: root)
        let prepared = effects.preparationObjects()
        XCTAssertEqual(prepared.count, 5)
        effects.consumeStep(poses: [pose(x: 0, secondX: 0, family: .dualHammers, active: false)], animationTick: 0)
        effects.consumeStep(poses: [pose(x: 0.2, secondX: 0.9, family: .dualHammers)], animationTick: 1)
        XCTAssertEqual(effects.retainedTrailCount, 2)
        XCTAssertEqual(effects.renderedVertexCount, 4, "Only the continuous hammer may seed a strip")
        XCTAssertTrue(effects.hasLiveContainer(attachedTo: root))
        effects.setPaused(true)
        effects.consumeStep(poses: [pose(x: 0.3, secondX: 1, family: .dualHammers)], animationTick: 2)
        XCTAssertEqual(effects.renderedVertexCount, 4)
        effects.reset()
        XCTAssertEqual(effects.retainedTrailCount, 0)
        XCTAssertEqual(effects.preparationObjects().count, 5, "Reset retains validated prewarmed materials")
        effects.shutdown()
        XCTAssertFalse(effects.hasLiveContainer(attachedTo: root))
        XCTAssertTrue(effects.preparationObjects().isEmpty)
        XCTAssertTrue(root.childNodes.isEmpty)
    }

    private func pose(x: Float, secondX: Float? = nil, family: DuelWeaponEffects.Family = .katana,
                      active: Bool = true) -> DuelWeaponEffects.Pose {
        var endpoints: [DuelWeaponEffects.Endpoints] = [
            .init(slot: 0, base: SCNVector3(x, 0, 0), tip: SCNVector3(x, 1, 0))
        ]
        if let secondX { endpoints.append(.init(slot: 1, base: SCNVector3(secondX, 0, 0), tip: SCNVector3(secondX, 1, 0))) }
        return .init(fighterID: 0, family: family, motionID: active ? "stroke.1" : nil,
                     isShadow: false, endpoints: endpoints)
    }
}
