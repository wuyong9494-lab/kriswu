import XCTest
import SceneKit
import SwiftUI
import Metal
import simd
@testable import ShiftReminder

@MainActor
final class DuelShadowPresentationTests: XCTestCase {
    func testHostedControlsObserveShadowCostCooldownAndRestartForBothFighters() async throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            let session = DuelSession(.init(hero: hero, difficulty: .learning,
                                           mode: .practice, originalWeapons: true))
            XCTAssertNil(session.loadError)
            let host = UIHostingController(rootView: DuelWeaponControls(session: session))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 956, height: 440))
            window.rootViewController = host
            host.view.frame = window.bounds
            window.isHidden = false
            defer {
                session.shutdown()
                window.isHidden = true
                window.rootViewController = nil
            }
            var mounted: DuelSourceControlsView?
            for _ in 0..<80 {
                host.view.layoutIfNeeded()
                mounted = controlsDescendant(in: host.view)
                if mounted != nil { break }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            let controls = try XCTUnwrap(mounted)
            XCTAssertTrue(controls.sourceArtAvailable)
            let shadow = try XCTUnwrap((controls.accessibilityElements as? [UIView])?
                .first { $0.accessibilityIdentifier == "duel.control.shadow" })
            XCTAssertEqual(shadow.accessibilityValue, "可施放")
            XCTAssertTrue(controls.state(for: .shadow).ready)

            // Use the mounted control's normal input callback and session clock.
            // Never call updateReadiness or replace the hosted root: the session
            // publication alone must refresh this same UIKit instance.
            controls.onAction?(.shadow, true)
            controls.onAction?(.shadow, false)
            for _ in 0..<12 { session.advance() }
            XCTAssertEqual(session.localFighter.energy, 0)
            XCTAssertGreaterThan(try XCTUnwrap(session.game.weaponFight).shadowCooldownRemaining(0), 0)
            try await expectShadowValue(shadow, contains: "冷却中")
            XCTAssertFalse(controls.state(for: .shadow).ready)

            session.pause()
            try await expectShadowValue(shadow, contains: "操作已暂停")
            session.resume()
            try await expectShadowValue(shadow, contains: "冷却中")
            for _ in 0..<450 { session.advance() }
            XCTAssertEqual(try XCTUnwrap(session.game.weaponFight).shadowCooldownRemaining(0), 0)
            XCTAssertEqual(session.localFighter.energy, 0)
            try await expectShadowValue(shadow, contains: "需要 100 能量")

            session.restart()
            try await expectShadowValue(shadow, contains: "可施放")
            XCTAssertTrue(controls.state(for: .shadow).ready)
            XCTAssertTrue(controlsDescendant(in: host.view) === controls,
                          "Readiness changes must not recreate the touch owner")
        }
    }

    private func controlsDescendant(in view: UIView) -> DuelSourceControlsView? {
        if let controls = view as? DuelSourceControlsView { return controls }
        for child in view.subviews {
            if let controls = controlsDescendant(in: child) { return controls }
        }
        return nil
    }

    private func expectShadowValue(_ view: UIView, contains text: String,
                                   file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<80 {
            if view.accessibilityValue?.contains(text) == true { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Expected shadow readiness '\(text)', got '\(view.accessibilityValue ?? "missing")'",
                file: file, line: line)
    }

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

    /// Bounded visual evidence for the provisional native timeline. This uses
    /// the real skinned character and source trails in a fixed studio camera;
    /// it does not assert that the original skill choreography has been restored.
    func testRealShadowReleaseAndCatchBoundariesRenderForBothFacings() throws {
        let assets = try DuelWeaponAssets()
        let character = try assets.character(for: .liu)
        let catalogData = try Data(contentsOf: XCTUnwrap(DuelWeaponAssets.catalogURL()))
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: catalogData) as? [String: Any])
        let profile = try XCTUnwrap((catalog["profiles"] as? [[String: Any]])?
            .first { $0["id"] as? String == character.profile.id })
        let landmarks = try XCTUnwrap(profile["weaponLandmarks"] as? [String: [String: Any]])
        typealias WeaponMesh = (holder: SCNNode, skin: SCNSkinner, geometry: SCNGeometry, base: Int, tip: Int)
        func weapon(_ side: String, actor: DuelWeaponCharacterInstance) throws -> WeaponMesh {
            let landmark = try XCTUnwrap(landmarks[side])
            let meshName = try XCTUnwrap(landmark["mesh"] as? String)
            let mesh = actor.instance.nodes[try XCTUnwrap(character.model.node(named: meshName))]
            let holder = try XCTUnwrap(mesh.childNodes.first { $0.skinner != nil })
            let skin = try XCTUnwrap(holder.skinner)
            return (holder, skin, try XCTUnwrap(skin.baseGeometry),
                    try XCTUnwrap(landmark["baseVertex"] as? Int),
                    try XCTUnwrap(landmark["tipVertex"] as? Int))
        }
        func numbers(_ point: SIMD3<Float>) -> [Double] { [Double(point.x), Double(point.y), Double(point.z)] }
        func finite(_ point: SIMD3<Float>) -> Bool { point.x.isFinite && point.y.isFinite && point.z.isFinite }
        var records: [[String: Any]] = []
        var boundaries: [[String: Any]] = []
        // The production DuelShadowRules currently detaches during 24..<72.
        // Assert that observed state rather than silently selecting other ticks.
        let captureTicks: Set<Int> = [23, 24, 71, 72]
        for direction in [1, -1] {
            try autoreleasepool {
                let origin = direction == 1 ? 2000 : 8000
                var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
                    .init(hero: .liu, x: origin, facing: direction),
                    .init(hero: .ember, x: direction == 1 ? 8500 : 1500, facing: -direction)
                ], mode: .practice, difficulty: .learning, catalog: assets.catalog, seed: 7))
                let actor = DuelWeaponCharacterInstance(character), root = SCNNode()
                root.addChildNode(actor.instance.root)
                // Keep an independent held-pose instance off scene. Do not
                // reset the displayed actor before tick 72: its normal pose
                // call must restore the previously detached weapon itself.
                let heldActor = DuelWeaponCharacterInstance(character), heldRoot = SCNNode()
                heldRoot.addChildNode(heldActor.instance.root)
                let right = try weapon("right", actor: actor), left = try weapon("left", actor: actor)
                let heldRight = try weapon("right", actor: heldActor), heldLeft = try weapon("left", actor: heldActor)
                let rightMaterials = right.geometry.materials
                let rightIndex = try XCTUnwrap(character.model.node(named: "weapon_r"))
                let leftIndex = try XCTUnwrap(character.model.node(named: "weapon_l"))
                let handIndex = try XCTUnwrap(character.model.node(named: "hand_r"))
                let scene = SCNScene(); scene.rootNode.addChildNode(root)
                scene.background.contents = UIColor(red: 0.035, green: 0.045, blue: 0.065, alpha: 1)
                let camera = SCNNode(); camera.camera = SCNCamera()
                camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 1.9
                camera.camera?.zNear = 0.1; camera.camera?.zFar = 20
                camera.camera?.wantsHDR = false; camera.camera?.wantsExposureAdaptation = false
                let center = Float(origin) / 1000 + Float(direction) * 0.25
                camera.position = SCNVector3(center, 1.6, 6)
                camera.look(at: SCNVector3(center, 0.95, 0)); scene.rootNode.addChildNode(camera)
                let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
                ambient.light?.intensity = 650; scene.rootNode.addChildNode(ambient)
                let key = SCNNode(); key.light = SCNLight(); key.light?.type = .omni
                key.light?.intensity = 1100; key.position = SCNVector3(center - 3, 4, 4)
                scene.rootNode.addChildNode(key)
                let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
                renderer.scene = scene; renderer.pointOfView = camera
                let effects = try DuelWeaponEffects(root: scene.rootNode)
                defer { effects.shutdown(); renderer.scene = nil; renderer.pointOfView = nil }
                XCTAssertEqual(effects.sourceTextureCount, 11)
                let facing = direction == 1 ? "positive" : "negative"
                var captures: [Int: (base: SIMD3<Float>, tip: SIMD3<Float>)] = [:]
                fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
                for _ in 0..<110 {
                    guard let shadow = fight.shadowVisual(0) else { break }
                    let fighter = fight.fighters[0]
                    let selection = try XCTUnwrap(fighter.weaponPose)
                    heldActor.pose(fighter, root: heldRoot)
                    actor.pose(fighter, root: root, shadow: shadow)
                    let effectPose = try XCTUnwrap(DuelWorldView.weaponEffectPoses(fight, tick: fight.frame).first)
                    effects.consumeStep(poses: [effectPose], animationTick: fight.frame)
                    let actualBase = try vertex(right.base, skinner: right.skin)
                    let actualTip = try vertex(right.tip, skinner: right.skin)
                    let actualLeftBase = try vertex(left.base, skinner: left.skin)
                    let actualLeftTip = try vertex(left.tip, skinner: left.skin)
                    XCTAssertTrue([actualBase, actualTip, actualLeftBase, actualLeftTip].allSatisfy(finite))
                    for node in actor.instance.nodes {
                        for column in 0..<4 {
                            let value = node.simdWorldTransform[column]
                            XCTAssertTrue(value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite)
                        }
                    }
                    XCTAssertTrue(right.holder.skinner === right.skin)
                    XCTAssertTrue(right.skin.baseGeometry === right.geometry)
                    XCTAssertEqual(right.geometry.materials.count, rightMaterials.count)
                    for (a, b) in zip(right.geometry.materials, rightMaterials) { XCTAssertTrue(a === b) }
                    let leftBaseError = simd_distance(actualLeftBase, try vertex(heldLeft.base, skinner: heldLeft.skin))
                    let leftTipError = simd_distance(actualLeftTip, try vertex(heldLeft.tip, skinner: heldLeft.skin))
                    XCTAssertLessThan(leftBaseError, 0.00001)
                    XCTAssertLessThan(leftTipError, 0.00001)
                    for column in 0..<4 {
                        XCTAssertLessThan(simd_distance(actor.instance.nodes[leftIndex].simdWorldTransform[column],
                                                       heldActor.instance.nodes[leftIndex].simdWorldTransform[column]), 0.00001)
                    }
                    if let base = shadow.weaponBase, let tip = shadow.weaponTip {
                        XCTAssertLessThan(simd_distance(actualBase, SIMD3(Float(base.x), Float(base.y), Float(base.z))), 0.003)
                        XCTAssertLessThan(simd_distance(actualTip, SIMD3(Float(tip.x), Float(tip.y), Float(tip.z))), 0.003)
                    } else {
                        // Includes tick 72 immediately after the last detached
                        // pose; source mesh and socket identity must be retained.
                        XCTAssertLessThan(simd_distance(actualBase, try vertex(heldRight.base, skinner: heldRight.skin)), 0.00001)
                        XCTAssertLessThan(simd_distance(actualTip, try vertex(heldRight.tip, skinner: heldRight.skin)), 0.00001)
                        for column in 0..<4 {
                            XCTAssertLessThan(simd_distance(actor.instance.nodes[rightIndex].simdTransform[column],
                                                           heldActor.instance.nodes[rightIndex].simdTransform[column]), 0.00001)
                        }
                    }
                    if captureTicks.contains(shadow.tick), captures[shadow.tick] == nil {
                        XCTAssertEqual(shadow.kind, .hammerThrow)
                        XCTAssertEqual(shadow.duration, 96)
                        XCTAssertEqual(shadow.weaponBase != nil, shadow.tick == 24 || shadow.tick == 71)
                        XCTAssertEqual(shadow.isAttacking, shadow.tick == 24)
                        let label = "shadow-boundary-liu-facing-\(facing)-tick-\(shadow.tick)"
                        SCNTransaction.flush()
                        let image = renderer.snapshot(atTime: Double(fight.frame) / 60,
                            with: CGSize(width: 1200, height: 800), antialiasingMode: .multisampling2X)
                        let png = try XCTUnwrap(image.pngData()); XCTAssertGreaterThan(png.count, 5_000)
                        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                        attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
                        captures[shadow.tick] = (actualBase, actualTip)
                        records.append([
                            "label": label, "fighter": "liu", "facing": direction,
                            "simulationFrame": fight.frame, "shadowTick": shadow.tick,
                            "bodyClip": selection.clip, "bodyClipTick": selection.tick, "bodyClipPhase": selection.phase,
                            "detached": shadow.weaponBase != nil, "attacking": shadow.isAttacking,
                            "rightBaseWorld": numbers(actualBase), "rightTipWorld": numbers(actualTip),
                            "heldRightBaseWorld": numbers(try vertex(heldRight.base, skinner: heldRight.skin)),
                            "heldRightTipWorld": numbers(try vertex(heldRight.tip, skinner: heldRight.skin)),
                            "rightHandWorld": numbers(actor.instance.nodes[handIndex].simdWorldPosition),
                            "rightWeaponSocketWorld": numbers(actor.instance.nodes[rightIndex].simdWorldPosition),
                            "leftBaseErrorMetres": Double(leftBaseError), "leftTipErrorMetres": Double(leftTipError),
                            "trailVertices": effects.renderedVertexCount, "pngSHA256": DuelWeaponAssets.digest(png)
                        ])
                    }
                    fight.step(.neutral, opponent: .neutral)
                }
                XCTAssertEqual(Set(captures.keys), captureTicks)
                XCTAssertEqual(fight.landedHits[0], 0, "The isolated boundary view must not include contact hit-stop")
                for (start, end) in [(23, 24), (71, 72)] {
                    let a = try XCTUnwrap(captures[start]), b = try XCTUnwrap(captures[end])
                    // Record the actual displacement for review. The current
                    // fixed release anchor is provisional; no visual quality
                    // pass or arbitrary maximum-distance assertion is invented.
                    boundaries.append(["facing": direction, "fromTick": start, "toTick": end,
                        "baseDisplacementMetres": Double(simd_distance(a.base, b.base)),
                        "tipDisplacementMetres": Double(simd_distance(a.tip, b.tip))])
                }
            }
        }
        XCTAssertEqual(records.count, 8)
        let evidence: [String: Any] = [
            "schema": 1, "catalogSHA256": DuelWeaponAssets.catalogSHA256,
            "characterSHA256": character.profile.sha256, "effectsManifestSHA256": DuelWeaponEffects.manifestSHA256,
            "camera": ["projection": "orthographic", "orthographicScale": 1.9, "width": 1200, "height": 800,
                       "hdr": false, "exposureAdaptation": false] as [String: Any],
            "scope": "Real source meshes and textures; fixed studio lighting; provisional native skill timeline; visual acceptance pending",
            "samples": records, "boundaryDisplacements": boundaries
        ]
        let data = try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "shadow-boundary-liu-world-evidence"; attachment.lifetime = .keepAlways; add(attachment)
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
