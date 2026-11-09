import XCTest
import CryptoKit
import SceneKit
import simd
@testable import ShiftReminder

/// Runs only with the real private equipped-character pack. Missing assets are
/// failures: a shared body, a primitive weapon, or a synthetic clip cannot pass.
@MainActor
final class DuelWeaponAssetTests: XCTestCase {
    private struct Evidence: Decodable {
        struct Profile: Decodable {
            struct Binding: Decodable { let name: String; let targetNode: Int; let sourceID: Int? }
            struct Landmark: Decodable { let mesh: String; let baseVertex: Int; let tipVertex: Int }
            struct Clip: Decodable {
                let name: String
                let sourceBytesBase64: String
                let sourceArrayCount: Int
                let sourceBoneIDs: [Int]
            }
            let id: String
            let sourceSkinNodeCount: Int
            let sourceBoneBindings: [Binding]
            let weaponLandmarks: [String: Landmark]
            let clips: [Clip]
        }
        let profiles: [Profile]
    }

    private struct VertexMarker {
        let point: SIMD4<Float>
        let bones: [SCNNode]
        let inverse: [simd_float4x4]
        let weights: [Float]

        var worldPosition: SIMD3<Float> {
            var value = SIMD4<Float>.zero
            for index in bones.indices {
                value += weights[index] * (bones[index].simdWorldTransform * inverse[index] * point)
            }
            return SIMD3(value.x, value.y, value.z)
        }
    }

    private func float(_ source: SCNGeometrySource, vertex: Int, component: Int) -> Float {
        XCTAssertTrue(source.usesFloatComponents)
        XCTAssertEqual(source.bytesPerComponent, 4)
        let offset = source.dataOffset + vertex * source.dataStride + component * 4
        return source.data.withUnsafeBytes {
            Float(bitPattern: UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
        }
    }

    private func joint(_ source: SCNGeometrySource, vertex: Int, component: Int) -> Int {
        XCTAssertFalse(source.usesFloatComponents)
        XCTAssertEqual(source.bytesPerComponent, 2)
        let offset = source.dataOffset + vertex * source.dataStride + component * 2
        return source.data.withUnsafeBytes {
            Int(UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
        }
    }

    private func matrix(_ value: SCNMatrix4) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(value.m11, value.m12, value.m13, value.m14),
            SIMD4(value.m21, value.m22, value.m23, value.m24),
            SIMD4(value.m31, value.m32, value.m33, value.m34),
            SIMD4(value.m41, value.m42, value.m43, value.m44)))
    }

    private func marker(in actor: DuelWeaponCharacterInstance, mesh: String, vertex: Int) throws -> VertexMarker {
        let index = try XCTUnwrap(actor.asset.model.node(named: mesh))
        let holder = try XCTUnwrap(actor.instance.nodes[index].childNodes.first { $0.skinner != nil })
        let skinner = try XCTUnwrap(holder.skinner)
        let source = try XCTUnwrap(skinner.baseGeometry?.sources(for: .vertex).first)
        let inverse = try XCTUnwrap(skinner.boneInverseBindTransforms)
        XCTAssertGreaterThan(source.vectorCount, vertex)
        let position = SIMD4(float(source, vertex: vertex, component: 0),
                             float(source, vertex: vertex, component: 1),
                             float(source, vertex: vertex, component: 2), 1)
        var bones: [SCNNode] = [], matrices: [simd_float4x4] = [], weights: [Float] = []
        for component in 0..<4 {
            let index = joint(skinner.boneIndices, vertex: vertex, component: component)
            XCTAssertLessThan(index, skinner.bones.count)
            XCTAssertLessThan(index, inverse.count)
            bones.append(skinner.bones[index])
            matrices.append(matrix(inverse[index].scnMatrix4Value))
            weights.append(float(skinner.boneWeights, vertex: vertex, component: component))
        }
        XCTAssertEqual(weights.reduce(0, +), 1, accuracy: 0.00001)
        return VertexMarker(point: position, bones: bones, inverse: matrices, weights: weights)
    }

    private func read16(_ data: Data, _ offset: Int) -> Int {
        data.withUnsafeBytes { Int(UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self))) }
    }
    private func read32(_ data: Data, _ offset: Int) -> Int {
        data.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))) }
    }
    private func read64(_ data: Data, _ offset: Int) -> UInt64 {
        data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
    }

    private func verifySource(_ clip: DuelWeaponClip, evidence: Evidence.Profile.Clip,
                              bindings: [Int: Int], native: GLTFModel.Clip) throws {
        let data = try XCTUnwrap(Data(base64Encoded: evidence.sourceBytesBase64))
        XCTAssertEqual(DuelWeaponAssets.digest(data), clip.sha256)
        XCTAssertEqual(evidence.sourceArrayCount, 2)
        XCTAssertEqual(read64(data, 0), 457_546_134_634_734)
        XCTAssertEqual(read16(data, 8), 2)
        var offset = 26
        for arrayIndex in 0..<2 {
            let frames = read32(data, offset), bones = read32(data, offset + 4)
            XCTAssertEqual(frames, clip.frames)
            XCTAssertEqual(bones, evidence.sourceBoneIDs.count)
            let packed = 8 + 2 * bones + 12 * frames * bones
            let expanded = 8 + 2 * bones + 28 * frames * bones
            let declared = read64(data, 10 + arrayIndex * 8)
            XCTAssertTrue(declared == UInt64(packed) || declared == UInt64(expanded))
            let ids = (0..<bones).map { read16(data, offset + 8 + $0 * 2) }
            XCTAssertEqual(ids, evidence.sourceBoneIDs)
            XCTAssertEqual(Set(ids).count, ids.count)
            offset += packed
        }
        XCTAssertEqual(offset, data.count, "Both source arrays must remain intact")
        XCTAssertEqual(native.channels.count, evidence.sourceBoneIDs.count * 2)
        for id in evidence.sourceBoneIDs {
            let node = try XCTUnwrap(bindings[id])
            let channels = native.channels.filter { $0.node == node }
            XCTAssertEqual(channels.count, 2, "No original body or weapon channel may be dropped")
            XCTAssertEqual(channels.filter { if case .translation = $0.path { return true }; return false }.count, 1)
            XCTAssertEqual(channels.filter { if case .rotation = $0.path { return true }; return false }.count, 1)
            for channel in channels {
                XCTAssertEqual(channel.times.count, clip.frames)
                XCTAssertEqual(channel.times.first ?? -1, 0, accuracy: 0.000001)
                XCTAssertEqual(channel.times.last ?? -1, Float(clip.frames - 1) / 30, accuracy: 0.000001)
            }
        }
    }

    private func expect(_ native: SIMD3<Float>, _ point: DuelWeaponPoint,
                        direction: Int, actorX: Float, lift: Double,
                        maximum: inout Float) {
        let expected = SIMD3(actorX + Float(direction) * Float(point.x),
                             Float(point.y + lift), Float(direction) * Float(point.z))
        let distance = simd_distance(native, expected)
        XCTAssertTrue(distance.isFinite)
        maximum = max(maximum, distance)
    }

    func testRealDistinctAssetsPreserveAllSourceFramesAndNativeHalfFrameWeaponGeometry() throws {
        let url = try XCTUnwrap(DuelWeaponAssets.catalogURL(), "The real equipped-character pack is required")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 13_211_630)
        XCTAssertEqual(DuelWeaponAssets.digest(data), "c4ee840d89cf1b2b8b82db0aebce878dbc5c2f2f60a52cf5b5a77b84f139ed5f")
        let extra = try JSONDecoder().decode(Evidence.self, from: data)
        let assets = try DuelWeaponAssets()
        XCTAssertNil(assets.catalog.sourceFramesPerSecond)
        XCTAssertEqual(assets.catalog.previewFramesPerSecond, 30)
        let expected: [(DuelGame.Hero, String, String, String, Int, Int)] = [
            (.ember, "arm__prc_02", "wpn__katana_01_01",
             "5a1a64c9986b0d5284a7986efc1589dbfc1f00f91ac9477cdae45930612ac553", 84, 52),
            (.liu, "arm__str_03", "wpn__hammers_01_01",
             "9ff998118a69b1d089694e97b2623cf6d6fb81e64451a8462dddaff756b6a09f", 76, 50)
        ]
        var totalSamples = 0, totalFrames = 0
        var maximum: Float = 0, maximumLift: Float = 0
        for (hero, body, weapon, digest, boneCount, clipCount) in expected {
            let asset = try assets.character(for: hero), profile = asset.profile
            let cached = try assets.character(for: hero)
            XCTAssertTrue(asset === cached, "One session must share each immutable model")
            XCTAssertThrowsError(try GLTFModel(
                url: assets.directory.appendingPathComponent(profile.resourceName + ".glb"),
                maxTexture: 1024, physicallyBased: true)) { error in
                guard case GLTFModel.LoadError.badFormat = error else {
                    return XCTFail("Unexpected strict-load error: \(error)")
                }
            }
            XCTAssertEqual(profile.bodyID, body); XCTAssertEqual(profile.weaponID, weapon)
            XCTAssertEqual(profile.sha256, digest); XCTAssertEqual(profile.clips.count, clipCount)
            let evidence = try XCTUnwrap(extra.profiles.first { $0.id == profile.id })
            XCTAssertEqual(evidence.sourceSkinNodeCount, boneCount)
            let bindings = Dictionary(uniqueKeysWithValues: evidence.sourceBoneBindings.compactMap {
                item -> (Int, Int)? in item.sourceID.map { ($0, item.targetNode) }
            })
            for binding in evidence.sourceBoneBindings {
                XCTAssertEqual(asset.model.names[binding.targetNode], binding.name)
            }
            let actor = DuelWeaponCharacterInstance(asset), untouched = asset.model.instantiate()
            let skeletonRoot = try XCTUnwrap(asset.model.node(named: "skeleton"))
            XCTAssertEqual(skeletonRoot, 0)
            XCTAssertEqual(asset.model.node(named: "Armature"), 1)
            let skinners = actor.instance.nodes.flatMap { $0.childNodes.compactMap(\.skinner) }
            XCTAssertFalse(skinners.isEmpty)
            for skinner in skinners {
                XCTAssertTrue(skinner.skeleton === actor.instance.nodes[skeletonRoot],
                              "The verified root correction must include the ancestor joint")
                XCTAssertEqual(skinner.bones.count, boneCount)
                XCTAssertTrue(skinner.bones[0] === actor.instance.nodes[skeletonRoot])
            }
            let untouchedTransforms = untouched.nodes.map(\.simdTransform)
            let root = SCNNode(); root.addChildNode(actor.instance.root)
            let handsFeet = try ["hand_l", "hand_r", "foot_l", "foot_r"].map {
                actor.instance.nodes[try XCTUnwrap(asset.model.node(named: $0))]
            }
            let pelvis = actor.instance.nodes[try XCTUnwrap(asset.model.node(named: "pelvis"))]
            var weapons: [(String, VertexMarker, VertexMarker)] = []
            for side in profile.activeWeaponSides {
                let value = try XCTUnwrap(evidence.weaponLandmarks[side])
                weapons.append((side, try marker(in: actor, mesh: value.mesh, vertex: value.baseVertex),
                                try marker(in: actor, mesh: value.mesh, vertex: value.tipVertex)))
            }
            if profile.isKatana {
                XCTAssertNotNil(asset.model.node(named: "wpn__katana_01_01__scabbard__l"))
                XCTAssertNil(asset.model.node(named: "wpn__katana_01_01__r"), "A single katana must not become dual swords")
            } else {
                XCTAssertNotNil(asset.model.node(named: "wpn__hammers_01_01__l"))
                XCTAssertNotNil(asset.model.node(named: "wpn__hammers_01_01__r"))
            }
            var soles: [(SCNNode, SIMD4<Float>)] = []
            for side in ["l", "r"] {
                let foot = actor.instance.nodes[try XCTUnwrap(asset.model.node(named: "foot_" + side))]
                let toe = actor.instance.nodes[try XCTUnwrap(asset.model.node(named: "toe_" + side))]
                let a = foot.simdWorldPosition, b = toe.simdWorldPosition
                for x in [min(a.x, b.x) - 0.055, max(a.x, b.x) + 0.055] {
                    for z in [min(a.z, b.z) - 0.055, max(a.z, b.z) + 0.055] {
                        soles.append((foot, simd_inverse(foot.simdWorldTransform) * SIMD4(x, -0.02, z, 1)))
                    }
                }
            }
            var fighter = DuelGame(hero: hero).fighters[0]
            fighter.x = 350
            for clip in profile.clips {
                let original = try XCTUnwrap(evidence.clips.first { $0.name == clip.name })
                try verifySource(clip, evidence: original, bindings: bindings,
                                 native: XCTUnwrap(asset.model.clips[clip.name]))
                totalFrames += clip.frames
                for sample in 0...clip.ticks {
                    let phase = clip.phase(at: sample), lift = clip.tracks.lift(phase: phase)
                    fighter.weaponPose = .init(clip: clip.name, tick: sample, duration: clip.ticks, groundLift: lift)
                    // Every half-frame is checked facing right. The beginning,
                    // middle half-frame and ending are also checked mirrored.
                    let directions = [0, clip.ticks / 2 + 1, clip.ticks].contains(sample) ? [1, -1] : [1]
                    for direction in directions {
                        fighter.facing = direction; actor.pose(fighter, root: root)
                        XCTAssertEqual(pelvis.position.x, 0, accuracy: 0.000001)
                        XCTAssertEqual(pelvis.position.z, 0, accuracy: 0.000001)
                        let tracks = [clip.tracks.handL, clip.tracks.handR, clip.tracks.footL, clip.tracks.footR]
                        for (node, track) in zip(handsFeet, tracks) {
                            expect(node.simdWorldPosition, clip.tracks.sample(track, phase: phase),
                                   direction: direction, actorX: 0.35, lift: lift, maximum: &maximum)
                        }
                        for (side, base, tip) in weapons {
                            let baseTrack = side == "left" ? clip.tracks.weaponBaseL : clip.tracks.weaponBaseR
                            let tipTrack = side == "left" ? clip.tracks.weaponTipL : clip.tracks.weaponTipR
                            expect(base.worldPosition, clip.tracks.sample(baseTrack, phase: phase),
                                   direction: direction, actorX: 0.35, lift: lift, maximum: &maximum)
                            expect(tip.worldPosition, clip.tracks.sample(tipTrack, phase: phase),
                                   direction: direction, actorX: 0.35, lift: lift, maximum: &maximum)
                        }
                        let low = soles.map { ($0.0.simdWorldTransform * $0.1).y - Float(lift) }.min() ?? 0
                        maximumLift = max(maximumLift, abs(max(0, -0.035 - low) - Float(lift)))
                    }
                    totalSamples += 1
                }
            }
            XCTAssertEqual(untouched.nodes.map(\.simdTransform), untouchedTransforms,
                           "Sampling one fighter must not mutate another instance")
            root.removeFromParentNode(); SCNTransaction.flush()
        }
        XCTAssertEqual(totalFrames, 5_237)
        XCTAssertEqual(totalSamples, 10_372)
        XCTAssertLessThan(maximum, 0.0002, "Native skinned weapon geometry must match exported contact tracks")
        XCTAssertLessThan(maximumLift, 0.0002, "Native ground correction must match the exported sole markers")
        let attachment = XCTAttachment(string: "frames=\(totalFrames) halfFrames=\(totalSamples) maximumContactMetres=\(maximum) maximumLiftMetres=\(maximumLift)")
        attachment.name = "distinct-source-native-geometry"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testEquippedRecoveryBlendsToIdleWithoutChangingSourceSample() throws {
        let assets = try DuelWeaponAssets()
        for hero in [DuelGame.Hero.ember, .liu] {
            let character = try assets.character(for: hero)
            let actor = DuelWeaponCharacterInstance(character)
            let attack = try XCTUnwrap(character.profile.clip(role: "weapon1"))
            let idle = try XCTUnwrap(character.profile.clip(role: "idle"))
            actor.apply(.init(clip: attack.name, tick: attack.ticks, duration: attack.ticks, groundLift: 0))
            let idleStart = DuelWeaponPose(clip: idle.name, tick: 0, duration: idle.ticks, groundLift: 0)
            var unblended = character.model.restPose
            character.sample(idleStart, into: &unblended)
            actor.apply(idleStart)
            // Re-rendering the same simulation frame must not advance the
            // transition or accumulate a second interpolation.
            let firstFrame = character.model.animated.map { actor.instance.nodes[$0].simdTransform }
            actor.apply(idleStart)
            for (offset, index) in character.model.animated.enumerated() {
                let expected = firstFrame[offset]
                let actual = actor.instance.nodes[index].simdTransform
                XCTAssertLessThan(simd_length(actual.columns.3 - expected.columns.3), 0.00001,
                                  "\(hero): repeated frame must keep bone translation stable")
            }
            // SceneKit may canonicalize q to -q. Both represent the same
            // rotation, so compare the nearer quaternion representative.
            func rotationDistance(_ a: simd_quatf, _ b: simd_quatf) -> Float {
                min(simd_length(a.vector - b.vector), simd_length(a.vector + b.vector))
            }
            let firstDistances = character.model.animated.map { index in
                rotationDistance(actor.instance.nodes[index].simdOrientation, unblended.rotation[index])
            }
            XCTAssertTrue(firstDistances.contains { $0 > 0.001 }, "\(hero): first idle frame should retain recovery motion")
            for tick in 1..<6 {
                actor.apply(.init(clip: idle.name, tick: tick, duration: idle.ticks, groundLift: 0))
            }
            let end = DuelWeaponPose(clip: idle.name, tick: 5, duration: idle.ticks, groundLift: 0)
            character.sample(end, into: &unblended)
            for index in character.model.animated {
                let node = actor.instance.nodes[index]
                XCTAssertLessThan(rotationDistance(node.simdOrientation, unblended.rotation[index]), 0.001,
                                  "\(hero): blend must finish at the exact source idle orientation")
                XCTAssertLessThan(simd_length(node.simdPosition - unblended.translation[index]), 0.001,
                                  "\(hero): blend must finish at the exact source idle translation")
                XCTAssertLessThan(simd_length(node.simdScale - unblended.scale[index]), 0.001,
                                  "\(hero): blend must finish at the exact source idle scale")
            }
        }
    }

    func testShowroomSwitchesBetweenDistinctAssetsAndReleasesOldModel() throws {
        let lobby = DuelLobbySceneView(hero: .ember)
        let initialRoot = try XCTUnwrap(lobby.scene?.rootNode.childNode(
            withName: "duel.lobby.character.ember", recursively: false))
        let before = initialRoot.position.y
        lobby.renderIdle(at: 1)
        XCTAssertEqual(lobby.showroomFrameCount, 1, "One source idle sample should render")
        XCTAssertTrue(initialRoot.position.y.isFinite)
        XCTAssertLessThan(abs(initialRoot.position.y - before), 0.2,
                          "Idle must update ground lift without jumping off the stage")
        lobby.select(.liu)
        XCTAssertNil(initialRoot.parent, "The previous 3D actor must detach on selection")
        XCTAssertNotNil(lobby.scene?.rootNode.childNode(
            withName: "duel.lobby.character.liu", recursively: false))
        XCTAssertEqual(lobby.yaw, .pi)
        XCTAssertEqual(lobby.zoom, 1)
        lobby.shutdown()
        XCTAssertNil(lobby.scene)
    }

    func testPersonalHeadFollowsBodyFacingAndSourceNeckAnimation() throws {
        let assets = try DuelWeaponAssets()
        for hero in [DuelGame.Hero.ember, .liu] {
            let character = try assets.character(for: hero)
            let actor = DuelWeaponCharacterInstance(character)
            let headIndex = try XCTUnwrap(character.model.node(named: "head"))
            let personalIndex = try XCTUnwrap(character.model.node(named:
                (hero == .ember ? "Sun" : "Liu") + "_Personal_Head"))
            let head = actor.instance.nodes[headIndex]
            let personalHead = actor.instance.nodes[personalIndex]
            let idle = try XCTUnwrap(character.profile.clip(role: "idle"))
            let root = SCNNode(); root.addChildNode(actor.instance.root)
            actor.apply(.init(clip: idle.name, tick: 0, duration: idle.ticks, groundLift: 0))
            let initialHead = head.simdWorldPosition
            let initialPersonal = personalHead.simdWorldPosition
            // Rotating the whole fighter must carry both the skinned head bone
            // and the personal face, not leave a camera-facing face behind.
            root.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
            let turnedHead = head.simdWorldPosition
            let turnedPersonal = personalHead.simdWorldPosition
            XCTAssertLessThan(simd_length(turnedHead - simd_act(root.simdOrientation, initialHead)), 0.002)
            XCTAssertLessThan(simd_length(turnedPersonal - simd_act(root.simdOrientation, initialPersonal)), 0.002)
            XCTAssertTrue(personalHead.parent != nil, "\(hero): face mesh must belong to the animated hierarchy")
        }
    }

    func testRenderBothDistinctSourceBodiesWeaponsAndPersonalHeads() throws {
        let assets = try DuelWeaponAssets(), scene = SCNScene()
        let actors = try [DuelGame.Hero.ember, .liu].map { hero -> (DuelWeaponCharacterInstance, SCNNode) in
            let actor = DuelWeaponCharacterInstance(try assets.character(for: hero))
            let root = SCNNode(); root.addChildNode(actor.instance.root); scene.rootNode.addChildNode(root)
            root.position.x = hero == .ember ? -1.05 : 1.05
            root.eulerAngles.y = .pi + (hero == .ember ? 0.15 : -0.15)
            return (actor, root)
        }
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 2.5
        camera.position = SCNVector3(0, 2.2, 7); camera.look(at: SCNVector3(0, 0.95, 0)); scene.rootNode.addChildNode(camera)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 650; scene.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .omni
        key.light?.intensity = 1100; key.position = SCNVector3(-3, 4, 4); scene.rootNode.addChildNode(key)
        let renderer = SCNRenderer(device: nil, options: nil); renderer.scene = scene; renderer.pointOfView = camera
        var digests = Set<String>()
        for (role, sample) in [("idle", 0), ("weapon1", 25), ("heavy", 47), ("kick", 25)] {
            for (actor, root) in actors {
                let clip = try XCTUnwrap(actor.asset.profile.clip(role: role))
                let tick = min(sample, clip.ticks), phase = clip.phase(at: tick)
                let lift = clip.tracks.lift(phase: phase)
                actor.apply(.init(clip: clip.name, tick: tick, duration: clip.ticks, groundLift: lift))
                root.position.y = Float(lift)
            }
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1200, height: 800), antialiasingMode: .multisampling2X)
            let data = try XCTUnwrap(image.pngData()); XCTAssertGreaterThan(data.count, 5_000)
            digests.insert(DuelWeaponAssets.digest(data))
            let attachment = XCTAttachment(image: image)
            attachment.name = "distinct-source-render-\(role)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(digests.count, 4)
    }
}
