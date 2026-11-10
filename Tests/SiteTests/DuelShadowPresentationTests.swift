import XCTest
import SceneKit
import simd
@testable import ShiftReminder

@MainActor
final class DuelShadowPresentationTests: XCTestCase {
    /// Evaluates a real source skinned vertex, not a substitute weapon node.
    private func vertex(_ index: Int, skinner: SCNSkinner) throws -> SIMD3<Float> {
        let positions = try XCTUnwrap(skinner.baseGeometry?.sources(for: .vertex).first)
        func scalar(_ source: SCNGeometrySource, _ component: Int) -> Float {
            source.data.withUnsafeBytes {
                Float(bitPattern: UInt32(littleEndian: $0.loadUnaligned(fromByteOffset:
                    source.dataOffset + index * source.dataStride + component * 4, as: UInt32.self)))
            }
        }
        let p = SIMD4(scalar(positions, 0), scalar(positions, 1), scalar(positions, 2), 1)
        let inverses = try XCTUnwrap(skinner.boneInverseBindTransforms)
        var value = SIMD4<Float>.zero
        for component in 0..<4 {
            let source = skinner.boneIndices
            let joint = source.data.withUnsafeBytes {
                Int(UInt16(littleEndian: $0.loadUnaligned(fromByteOffset:
                    source.dataOffset + index * source.dataStride + component * 2, as: UInt16.self)))
            }
            let m = inverses[joint].scnMatrix4Value
            let inverse = simd_float4x4(columns: (
                SIMD4(m.m11, m.m12, m.m13, m.m14), SIMD4(m.m21, m.m22, m.m23, m.m24),
                SIMD4(m.m31, m.m32, m.m33, m.m34), SIMD4(m.m41, m.m42, m.m43, m.m44)))
            value += scalar(skinner.boneWeights, component) * (skinner.bones[joint].simdWorldTransform * inverse * p)
        }
        return SIMD3(value.x, value.y, value.z)
    }

    func testRealHammerTravelsBothWaysAndRestoresWithoutAccumulatingOrReplacingMesh() throws {
        let assets = try DuelWeaponAssets()
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(DuelWeaponAssets.catalogURL()))) as! [String: Any]
        let character = try assets.character(for: .liu)
        let profile = try XCTUnwrap((json["profiles"] as? [[String: Any]])?.first { $0["id"] as? String == character.profile.id })
        let landmarks = try XCTUnwrap(profile["weaponLandmarks"] as? [String: [String: Any]])
        let landmark = try XCTUnwrap(landmarks["right"])
        let meshName = try XCTUnwrap(landmark["mesh"] as? String)
        let baseVertex = try XCTUnwrap(landmark["baseVertex"] as? Int)
        let tipVertex = try XCTUnwrap(landmark["tipVertex"] as? Int)
        for direction in [1, -1] {
            let fighters = [DuelGame.Fighter(hero: .liu, x: direction == 1 ? 2000 : 8000, facing: direction),
                            DuelGame.Fighter(hero: .ember, x: direction == 1 ? 8500 : 1500, facing: -direction)]
            var fight = try XCTUnwrap(DuelWeaponFight(fighters: fighters, mode: .practice,
                difficulty: .learning, catalog: assets.catalog, seed: 7))
            let actor = DuelWeaponCharacterInstance(character), root = SCNNode()
            root.addChildNode(actor.instance.root)
            let mesh = actor.instance.nodes[try XCTUnwrap(character.model.node(named: meshName))]
            let skinner = try XCTUnwrap(mesh.childNodes.compactMap(\.skinner).first)
            let geometry = try XCTUnwrap(skinner.baseGeometry)
            let materials = geometry.materials
            let right = actor.instance.nodes[try XCTUnwrap(character.model.node(named: "weapon_r"))]
            let left = actor.instance.nodes[try XCTUnwrap(character.model.node(named: "weapon_l"))]
            var outbound = false, returned = false
            fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
            for _ in 0..<160 {
                let fighter = fight.fighters[0], shadow = fight.shadowVisual(0)
                actor.pose(fighter, root: root)
                let heldRight = right.simdTransform, heldLeft = left.simdWorldTransform
                actor.pose(fighter, root: root, shadow: shadow)
                if let base = shadow?.weaponBase, let tip = shadow?.weaponTip {
                    let actualBase = try vertex(baseVertex, skinner: skinner)
                    let actualTip = try vertex(tipVertex, skinner: skinner)
                    XCTAssertLessThan(simd_distance(actualBase, SIMD3(Float(base.x), Float(base.y), Float(base.z))), 0.003)
                    XCTAssertLessThan(simd_distance(actualTip, SIMD3(Float(tip.x), Float(tip.y), Float(tip.z))), 0.003)
                    outbound = outbound || shadow!.tick < 48
                    returned = returned || shadow!.tick >= 48
                    let first = right.simdWorldTransform
                    actor.pose(fighter, root: root, shadow: shadow)
                    for column in 0..<4 { XCTAssertLessThan(simd_distance(first[column], right.simdWorldTransform[column]), 0.00001) }
                    for column in 0..<4 { XCTAssertLessThan(simd_distance(heldLeft[column], left.simdWorldTransform[column]), 0.00001) }
                    // Interruption/recovery uses the same nil-shadow draw path.
                    actor.pose(fighter, root: root)
                    for column in 0..<4 { XCTAssertLessThan(simd_distance(heldRight[column], right.simdTransform[column]), 0.00001) }
                }
                XCTAssertTrue(skinner.baseGeometry === geometry)
                XCTAssertEqual(geometry.materials.count, materials.count)
                for (a, b) in zip(geometry.materials, materials) { XCTAssertTrue(a === b) }
                fight.step(.neutral, opponent: .neutral)
            }
            XCTAssertTrue(outbound); XCTAssertTrue(returned)
            XCTAssertNil(fight.shadowVisual(0))
        }
    }
    func testBothShadowFamiliesUseVerifiedSourceEffectsAndReleaseTheirTrails() throws {
        let assets = try DuelWeaponAssets()
        for hero in [DuelGame.Hero.ember, .liu] {
            let root = SCNNode()
            let live = try DuelWeaponEffects(root: root)
            defer { live.shutdown() }
            XCTAssertEqual(live.sourceTextureCount, 11)
            let other: DuelGame.Hero = hero == .ember ? .liu : .ember
            var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
                .init(hero: hero, x: 2000, facing: 1), .init(hero: other, x: 9000, facing: -1)],
                mode: .practice, difficulty: .learning, catalog: assets.catalog, seed: 7))
            fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
            var emitted = false
            var previousMotion: String?
            for tick in 0..<200 {
                let rendered = try XCTUnwrap(DuelWorldView.weaponEffectPoses(fight, tick: tick).first)
                if let motion = rendered.motionID {
                    XCTAssertTrue(motion.hasPrefix("shadow:0:"))
                    if let previousMotion { XCTAssertEqual(motion, previousMotion) }
                    previousMotion = motion
                }
                live.consumeStep(poses: [rendered], animationTick: tick)
                emitted = emitted || live.renderedVertexCount > 0
                let count = live.emittedSampleCount
                let trailCount = live.retainedTrailCount
                live.consumeStep(poses: [rendered], animationTick: tick)
                XCTAssertEqual(live.emittedSampleCount, count, "Repeated rendering / hitstop cannot advance source effects")
                XCTAssertEqual(live.retainedTrailCount, trailCount)
                if hero == .liu, let visual = fight.shadowVisual(0), (30..<70).contains(visual.tick) {
                    XCTAssertEqual(live.retainedTrailCount, 2, "One source ribbon per hammer persists through apex and return")
                }
                fight.step(.neutral, opponent: .neutral)
            }
            XCTAssertTrue(emitted)
            live.consumeStep(poses: [], animationTick: 400)
            XCTAssertEqual(live.retainedTrailCount, 0)
            live.shutdown()
            XCTAssertTrue(root.childNodes.isEmpty)
        }
    }

}
