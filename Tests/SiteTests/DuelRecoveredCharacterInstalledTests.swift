import Foundation
import XCTest
import SceneKit
import UIKit
import Metal
import simd
@testable import ShiftReminder

/// Mandatory private-resource checks. Every input comes from the installed,
/// independently pinned app release; absent resources fail instead of skipping.
/// These checks do not certify complete gameplay, audible playback or GPU pixels.
@MainActor
final class DuelRecoveredCharacterInstalledTests: XCTestCase {
    private enum Failure: Error { case missingReleasePin, invalidNode, nonFinitePose }
    private struct Expected {
        let hero: DuelGame.Hero
        let id, title, body, weapon, sha256, head: String
        let clips, joints, skinMeshes, skinVertices, skinTriangles: Int
        let rigidMeshes, rigidVertices, rigidTriangles: Int
        let equipmentNodes: [String]
    }
    private let expected: [Expected] = [
        .init(hero: .ember, id: "sun_triad", title: "孙登",
              body: "arm__prc_43", weapon: "wpn__ninjato_01_06",
              sha256: "7c9ebfe285f637cbd002f717d80b859a57d3ab11ef491f15930dc4f3eb50d96a",
              head: "Sun_Personal_Head", clips: 70, joints: 87,
              skinMeshes: 7, skinVertices: 53_660, skinTriangles: 56_051,
              rigidMeshes: 0, rigidVertices: 0, rigidTriangles: 0,
              equipmentNodes: ["arm__prc_43_m", "wpn__ninjato_01_06__l", "wpn__ninjato_01_06__r"]),
        .init(hero: .liu, id: "liu_serpent", title: "刘泉纬",
              body: "arm__agl_41", weapon: "wpn__shuangou_01_04",
              sha256: "f25b35dec9bf335bbe01ceee557389f47165c3d0b45b54502017fda394a8bd70",
              head: "Liu_Personal_Head", clips: 66, joints: 80,
              skinMeshes: 8, skinVertices: 21_936, skinTriangles: 31_356,
              rigidMeshes: 0, rigidVertices: 0, rigidTriangles: 0,
              equipmentNodes: ["arm__agl_41_m", "wpn__shuangou_01_04__l", "wpn__shuangou_01_04__r"]),
        .init(hero: .wuYong, id: "wuyong_erlang", title: "吴庸",
              body: "arm__agl_44", weapon: "wpn__agl_spear_01_01",
              sha256: "2957d7861b2ee7656945259dd273f241591ce55f71d364dab007a9bc372d76f6",
              head: "WuYong_Personal_Head", clips: 62, joints: 80,
              skinMeshes: 10, skinVertices: 18_833, skinTriangles: 14_217,
              rigidMeshes: 1, rigidVertices: 59_878, rigidTriangles: 55_000,
              equipmentNodes: ["arm__agl_44_m", "wpn__agl_spear_01_01__l"])
    ]

    private func installed() throws -> DuelWeaponAssets {
        guard let pin = Bundle.main.object(forInfoDictionaryKey: DuelFighterAssetRelease.infoKey) as? String,
              DuelFighterAssetRelease.validDigest(pin) else {
            XCTFail("The dedicated recovered-resource build must install its reviewed release pin")
            throw Failure.missingReleasePin
        }
        XCTAssertEqual(pin, "527e0195b7911e5b532aec92c37057f36a633952768670518565bde65605cbd3")
        let assets = try DuelWeaponAssets()
        XCTAssertEqual(assets.purpose, .combat)
        let installedRelease = try XCTUnwrap(assets.release)
        XCTAssertEqual(installedRelease.definition.id, "shared-imperial-victim-reconstructed-20261117-v1")
        let release = try Data(contentsOf: assets.directory.appendingPathComponent(DuelFighterAssetRelease.fileName))
        XCTAssertEqual(DuelNetworkContentRecord.digest(release), pin)
        return assets
    }

    private func finite(_ matrix: simd_float4x4) -> Bool {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3].allSatisfy {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite
        }
    }

    private func geometryNodes(_ root: SCNNode) -> [SCNNode] {
        var nodes = root.geometry == nil ? [] : [root]
        root.enumerateChildNodes { node, _ in if node.geometry != nil { nodes.append(node) } }
        return nodes
    }

    private func audit(_ files: [DuelNetworkContentRecord], in directory: URL) throws {
        XCTAssertFalse(files.isEmpty)
        XCTAssertEqual(Set(files.map(\.path)).count, files.count)
        for file in files {
            let data = try Data(contentsOf: directory.appendingPathComponent(file.path))
            XCTAssertEqual(data.count, file.bytes)
            XCTAssertEqual(DuelNetworkContentRecord.digest(data), file.sha256)
        }
    }

    /// Only numeric/boolean aggregates leave the test. No source JSON, model,
    /// audio, textures, local resource path or download URL is attached.
    private func attach(_ numbers: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: numbers, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLocalTriadEffectsPrepareOnlyForTheChosenPair() async throws {
        let index = try await DuelWeaponAssetIndex.loadBundled()
        let other = try await index.preparingLocalEffects(player: .liu, opponent: .wuYong)
        XCTAssertNil(other.preparedTriadEffects)
        let showroom = try DuelWeaponAssets(verifiedIndex: index, purpose: .showroom)
        let displayed = try showroom.character(for: .liu)
        let otherReservation = index.reservingShowroomModel(for: .ember)
        XCTAssertNil(otherReservation.showroomModel.take(for: .liu))
        let matchIndex = index.reservingShowroomModel(for: .liu)
        XCTAssertNil(matchIndex.showroomModel.take(for: .ember))
        showroom.releaseCharacters()
        let beforePreparation = ProcessInfo.processInfo.systemUptime
        let ready = try await matchIndex.preparingLocalEffects(player: .liu, opponent: .ember)
        let afterPreparation = ProcessInfo.processInfo.systemUptime
        XCTAssertNil(index.preparedTriadEffects)
        XCTAssertNotNil(ready.preparedTriadEffects)
        let assets = try DuelWeaponAssets(verifiedIndex: ready, purpose: .localMatch(.liu, .ember))
        let afterCombatAssets = ProcessInfo.processInfo.systemUptime
        let equipped = try assets.character(for: .liu)
        XCTAssertFalse(equipped === displayed)
        XCTAssertTrue(equipped.model === displayed.model)
        XCTAssertNil(matchIndex.showroomModel.take(for: .liu))
        let lobbyInstance = displayed.model.instantiate()
        let matchInstance = equipped.model.instantiate()
        XCTAssertFalse(lobbyInstance.root === matchInstance.root)
        let node = try XCTUnwrap(equipped.model.node(named: "Liu_Personal_Head"))
        XCTAssertFalse(lobbyInstance.nodes[node] === matchInstance.nodes[node])

        try DuelLocalProfileTestFixtures.withDirectory { directory in
            let file = directory.appendingPathComponent(displayed.profile.resourceName + ".glb")
            let original = index.directory.appendingPathComponent(file.lastPathComponent)
            try FileManager.default.copyItem(at: original, to: file)
            let writer = try FileHandle(forUpdating: file)
            let first = try XCTUnwrap(try writer.read(upToCount: 1)?.first)
            try writer.seek(toOffset: 0)
            try writer.write(contentsOf: Data([first ^ 1]))
            try writer.close()
            XCTAssertThrowsError(try DuelWeaponCharacterAsset(url: file, profile: displayed.profile,
                                                               displayed: displayed)) { error in
                guard case DuelWeaponAssets.AssetError.integrity = error else {
                    return XCTFail("Expected the changed character file to fail verification")
                }
            }
        }
        let expected = try XCTUnwrap(index.release?.definition.triadEffects)
        let record = try XCTUnwrap(assets.triadEffects?.verifiedFiles.first(where: { $0.path == expected.name }))
        XCTAssertEqual(record.sha256, expected.sha256)
        XCTAssertEqual(record.bytes, expected.bytes)
        try attach(["compressedEffectBytes": expected.bytes,
                    "backgroundPreparationMilliseconds": (afterPreparation - beforePreparation) * 1000,
                    "combatAssetConstructionMilliseconds": (afterCombatAssets - afterPreparation) * 1000],
                   name: "local-sun-liu-effect-preparation")
        let profile = try XCTUnwrap(index.resolution.profiles.first(where: \.isTriad))
        let prepared = try XCTUnwrap(ready.preparedTriadEffects?.manifest)
        try DuelLocalProfileTestFixtures.withDirectory { directory in
            let copy = directory.appendingPathComponent(expected.name)
            try FileManager.default.copyItem(at: index.directory.appendingPathComponent(expected.name), to: copy)
            let writer = try FileHandle(forUpdating: copy)
            var byte = try XCTUnwrap(try writer.read(upToCount: 1))
            byte[0] ^= 1
            try writer.seek(toOffset: 0)
            try writer.write(contentsOf: byte)
            try writer.close()
            XCTAssertThrowsError(try DuelTriadEffectAssets(directory: directory, manifestName: expected.name,
                expectedSHA256: expected.sha256, profile: profile, preparedManifest: prepared)) { error in
                guard case let DuelTriadEffectAssets.Failure.resource(path) = error, path == expected.name else {
                    return XCTFail("Expected changed effect bytes to fail verification: \(error)")
                }
            }
        }
    }

    func testInstalledRecoveredRosterUsesEachPersonsExactHeadAndSourceEquipment() throws {
        let assets = try installed()
        defer { assets.releaseCharacters() }
        XCTAssertEqual(Set(assets.localProfiles.map(\.id)), Set(expected.map(\.id)))
        XCTAssertFalse(assets.localProfiles.contains(where: \.isFounder),
                       "The current package contains no authenticated complete D20 actor")
        var metrics: [[String: Int]] = []
        for wanted in expected {
            let character = try assets.character(for: wanted.hero)
            let profile = character.profile, model = character.model
            XCTAssertEqual(profile.id, wanted.id)
            XCTAssertEqual(profile.hero, wanted.hero)
            XCTAssertEqual(profile.title, wanted.title)
            XCTAssertEqual(profile.bodyID, wanted.body)
            XCTAssertEqual(profile.weaponID, wanted.weapon)
            XCTAssertEqual(profile.sha256, wanted.sha256)
            XCTAssertTrue(profile.isIntendedCharacter)
            XCTAssertEqual(profile.clips.count, wanted.clips)
            XCTAssertEqual(Set(model.clips.keys), Set(profile.clips.map(\.name)))
            XCTAssertTrue(model.hasSkinning)
            XCTAssertEqual(model.names.filter { $0 == wanted.head }.count, 1)
            let actualHeads = Set(model.names.filter {
                ["Sun_Personal_Head", "Liu_Personal_Head", "WuYong_Personal_Head", "XuXiao_Personal_Head"].contains($0)
            })
            XCTAssertEqual(actualHeads, [wanted.head])

            if wanted.hero == .ember {
                XCTAssertEqual(character.releaseBinding?.characterSHA256, wanted.sha256)
                XCTAssertNotNil(character.sourceTrails)
            } else {
                XCTAssertNil(character.releaseBinding, "A local source actor cannot inherit the old two-character binding")
                XCTAssertNil(character.sourceTrails, "The old Liu hammer trail binding must not reach D13")
            }
            let actor = DuelWeaponCharacterInstance(character)
            let bounds = try XCTUnwrap(actor.displayedBounds,
                                       "Every actual mesh, including a rigid personal head, must reach camera bounds")
            XCTAssertNil(actor.displayedBoundsFailure)
            let trails = Set((actor.sourceTrailBinding?.holders ?? []).map(ObjectIdentifier.init))
            let nodes = geometryNodes(actor.instance.root).filter { !trails.contains(ObjectIdentifier($0)) }
            let skinned = nodes.filter { $0.skinner != nil }, rigid = nodes.filter { $0.skinner == nil }
            XCTAssertEqual(skinned.count, wanted.skinMeshes)
            XCTAssertEqual(rigid.count, wanted.rigidMeshes)
            var vertices = 0, triangles = 0, rigidVertices = 0, rigidTriangles = 0
            for node in skinned {
                let skin = try XCTUnwrap(node.skinner)
                let geometry = try XCTUnwrap(skin.baseGeometry)
                let positions = try XCTUnwrap(geometry.sources(for: .vertex).first)
                let sources = try XCTUnwrap(GLTFModel.skinSources(for: node))
                XCTAssertGreaterThan(positions.vectorCount, 0)
                XCTAssertEqual(skin.bones.count, wanted.joints)
                XCTAssertNotNil(skin.skeleton)
                let binds = try XCTUnwrap(skin.boneInverseBindTransforms)
                XCTAssertEqual(binds.count, skin.bones.count)
                XCTAssertTrue(binds.allSatisfy { finite(simd_float4x4($0.scnMatrix4Value)) })
                XCTAssertEqual(sources.weights.vectorCount, positions.vectorCount)
                XCTAssertEqual(sources.indices.vectorCount, positions.vectorCount)
                vertices += positions.vectorCount
                triangles += geometry.elements.reduce(0) { $0 + $1.primitiveCount }
            }
            for node in rigid {
                let geometry = try XCTUnwrap(node.geometry)
                rigidVertices += try XCTUnwrap(geometry.sources(for: .vertex).first).vectorCount
                rigidTriangles += geometry.elements.reduce(0) { $0 + $1.primitiveCount }
            }
            // The D13 file still stores all nine source meshes. The helmet
            // remains in the file but is outside the personalized scene.
            var storedVertices = vertices, storedTriangles = triangles
            if wanted.hero == .liu {
                let index = try XCTUnwrap(model.node(named: "helm__agl_41_m"))
                let helmet = actor.instance.nodes[index]
                XCTAssertNil(helmet.parent)
                let geo = try XCTUnwrap(helmet.childNodes.first?.geometry)
                storedVertices += try XCTUnwrap(geo.sources(for: .vertex).first).vectorCount
                storedTriangles += geo.elements.reduce(0) { $0 + $1.primitiveCount }
            }
            XCTAssertEqual(storedVertices, wanted.skinVertices)
            XCTAssertEqual(storedTriangles, wanted.skinTriangles)
            XCTAssertEqual(rigidVertices, wanted.rigidVertices)
            XCTAssertEqual(rigidTriangles, wanted.rigidTriangles)
            for name in wanted.equipmentNodes {
                let index = try XCTUnwrap(model.node(named: name))
                XCTAssertFalse(geometryNodes(actor.instance.nodes[index]).filter { $0.skinner != nil }.isEmpty)
            }
            let head = try XCTUnwrap(model.node(named: wanted.head))
            let headParts = geometryNodes(actor.instance.nodes[head])
            XCTAssertFalse(headParts.isEmpty)
            if wanted.hero == .wuYong {
                // The authenticated contour export preserves this rigid head
                // as a direct child of the original head bone. Do not invent a skin.
                let bone = try XCTUnwrap(model.node(named: "head"))
                XCTAssertTrue(actor.instance.nodes[head].parent === actor.instance.nodes[bone])
                XCTAssertTrue(headParts.allSatisfy { $0.skinner == nil })
                let camera = SCNNode(); camera.position.z = 10
                let allPoints = try bounds.cameraPoints(camera: camera)
                actor.instance.nodes[head].isHidden = true
                let withoutHead = try bounds.cameraPoints(camera: camera)
                actor.instance.nodes[head].isHidden = false
                XCTAssertEqual(allPoints.count - withoutHead.count, 16,
                               "The authentic rigid head must add its own complete camera envelope")
                let previousVisibility = nodes.map { ($0, $0.isHidden) }
                defer { for (node, hidden) in previousVisibility { node.isHidden = hidden } }
                let headIDs = Set(headParts.map(ObjectIdentifier.init))
                for node in nodes { node.isHidden = !headIDs.contains(ObjectIdentifier(node)) }
                let headPoints = try bounds.cameraPoints(camera: camera)
                XCTAssertEqual(headPoints.count, 16)
                let holder = try XCTUnwrap(headParts.first)
                let geometry = try XCTUnwrap(holder.geometry)
                let (low, high) = geometry.boundingBox
                XCTAssertGreaterThan(high.y, low.y)
                if headPoints.count == 16 {
                    for corner in 0..<8 {
                        let local = SCNVector3(corner & 1 == 0 ? low.x : high.x,
                            corner & 2 == 0 ? low.y : high.y, corner & 4 == 0 ? low.z : high.z)
                        let native = holder.convertPosition(local, to: camera)
                        for endpoint in 0..<2 {
                            let actual = headPoints[corner * 2 + endpoint]
                            XCTAssertEqual(actual.x, native.x, accuracy: 0.00001)
                            XCTAssertEqual(actual.y, native.y, accuracy: 0.00001)
                            XCTAssertEqual(actual.z, native.z, accuracy: 0.00001)
                        }
                    }
                }
            } else {
                XCTAssertTrue(headParts.allSatisfy { $0.skinner != nil })
            }
            metrics.append(["clips": wanted.clips, "skinJoints": wanted.joints,
                "skinMeshes": skinned.count, "skinVertices": vertices, "skinTriangles": triangles,
                "rigidMeshes": rigid.count, "rigidVertices": rigidVertices, "rigidTriangles": rigidTriangles])
            assets.releaseCharacter(for: wanted.hero)
        }
        let pairs: [(DuelGame.Hero, DuelGame.Hero)] = [(.ember, .liu), (.ember, .wuYong), (.liu, .wuYong)]
        for (first, second) in pairs {
            let selected = try assets.localCatalog(hero: first, opponent: second)
            XCTAssertEqual(Set(selected.profiles.map(\.hero)), [first, second])
            XCTAssertTrue(selected.profiles.allSatisfy(\.isIntendedCharacter))
        }
        try attach(["characters": metrics, "completeD20Accepted": false, "renderedPixelsVerified": false],
                   name: "recovered-character-installed-metrics")
    }

    func testLiuPersonalHeadIsDisplayedAndFollowsRecoveredRig() throws {
        let assets = try installed()
        defer { assets.releaseCharacters() }
        let character = try assets.character(for: .liu)
        let model = character.model
        XCTAssertEqual(character.profile.sha256, DuelSerpentAssetIdentity.characterSHA256)
        let outer = try XCTUnwrap(model.node(named: "SF3_Actor_Meters"))
        let helmet = try XCTUnwrap(model.node(named: "helm__agl_41_m"))
        let head = try XCTUnwrap(model.node(named: "Liu_Personal_Head"))
        let neck = try XCTUnwrap(model.node(named: "Liu_Neck_Bridge"))
        let headBone = try XCTUnwrap(model.node(named: "head"))
        let neckBone = try XCTUnwrap(model.node(named: "neck"))
        let source = model.instantiate()
        XCTAssertNil(source.nodes[head].parent)
        XCTAssertNil(source.nodes[neck].parent)
        XCTAssertTrue(source.nodes[helmet].parent === source.nodes[outer])
        let broken = model.instantiate()
        broken.nodes[neck].childNodes.first?.removeFromParentNode()
        XCTAssertFalse(DuelSerpentHeadlessMorphScene.showPersonalHead(asset: character, instance: broken))
        XCTAssertTrue(broken.nodes[helmet].parent === broken.nodes[outer])
        XCTAssertNil(broken.nodes[head].parent)

        for environment in [DuelPresentationAssets.Environment.autumn, .palace] {
            let actor = DuelWeaponCharacterInstance(character, environment: environment)
            let nodes = actor.instance.nodes
            XCTAssertTrue(actor.displaysSerpentPersonalHead)
            XCTAssertTrue(nodes[head].parent === nodes[outer])
            XCTAssertTrue(nodes[neck].parent === nodes[outer])
            XCTAssertNil(nodes[helmet].parent)
            XCTAssertEqual(geometryNodes(actor.instance.root).count, 8)
            let holder = try XCTUnwrap(nodes[head].childNodes.first)
            let material = try XCTUnwrap(holder.geometry?.firstMaterial)
            XCTAssertEqual(material.name, "tripo_mat_c4757646")
            XCTAssertTrue(material.diffuse.contents is UIImage)
            XCTAssertNotNil(holder.skinner)
            let bounds = try DuelDisplayedSkinBounds(root: nodes[head])
            let identityCamera = SCNNode()
            let idle = try XCTUnwrap(character.profile.clip(role: "idle"))
            let attack = try XCTUnwrap(character.profile.clip(command: .weapon))
            var initialCenter: SIMD3<Float>?
            var maxTravel: Float = 0
            for clip in [idle, attack] {
                for tick in [0, clip.ticks / 2, clip.ticks] {
                    actor.apply(.init(clip: clip.name, tick: tick, duration: clip.ticks,
                                      groundLift: clip.tracks.lift(phase: Double(tick) / Double(clip.ticks))))
                    let points = try bounds.cameraPoints(camera: identityCamera)
                    let first = try XCTUnwrap(points.first)
                    let low = points.reduce(first) { simd_min($0, $1) }
                    let high = points.reduce(first) { simd_max($0, $1) }
                    let center = (low + high) * 0.5
                    let joint = nodes[headBone].simdWorldPosition, neckJoint = nodes[neckBone].simdWorldPosition
                    XCTAssertGreaterThan(simd_distance(low, high), 0.05)
                    XCTAssertLessThan(simd_distance(center, joint), 0.35)
                    XCTAssertLessThan(simd_distance(center, neckJoint), 0.45)
                    if let initialCenter { maxTravel = max(maxTravel, simd_distance(center, initialCenter)) }
                    else { initialCenter = center }
                }
            }
            XCTAssertGreaterThan(maxTravel, 0.005)
        }
    }

    func testWuPortraitHasShorterNeckAndKeepsAnimatedCollarSeams() throws {
        let assets = try installed()
        defer { assets.releaseCharacters() }
        let character = try assets.character(for: .wuYong)
        XCTAssertEqual(character.profile.sha256, DuelErlangAssetIdentity.characterSHA256)
        let model = character.model, source = model.instantiate(), actor = DuelWeaponCharacterInstance(character)
        let head = try XCTUnwrap(model.node(named: "head"))
        let neck = try XCTUnwrap(model.node(named: "neck"))
        let portrait = try XCTUnwrap(model.node(named: "WuYong_Personal_Head"))
        let oldFace = source.nodes[portrait], newFace = actor.instance.nodes[portrait]
        XCTAssertTrue(newFace.parent === actor.instance.nodes[head])
        XCTAssertNil(newFace.childNodes.first?.skinner)
        let shift = newFace.simdPosition - oldFace.simdPosition
        let down = source.nodes[neck].simdWorldPosition - source.nodes[head].simdWorldPosition
        let restDelta = newFace.simdWorldPosition - oldFace.simdWorldPosition
        XCTAssertGreaterThan(simd_length(restDelta), 0.002)
        XCTAssertLessThanOrEqual(simd_length(restDelta), 0.02501)
        XCTAssertGreaterThan(simd_dot(simd_normalize(restDelta), simd_normalize(down)), 0.9999)

        var headBinds: [(source: simd_float4x4, fitted: simd_float4x4)] = []
        for name in ["arm__agl_44_m", "Personal_Neck_Bridge"] {
            let index = try XCTUnwrap(model.node(named: name))
            let originalParts = source.nodes[index].childNodes, fittedParts = actor.instance.nodes[index].childNodes
            XCTAssertEqual(originalParts.count, fittedParts.count)
            for (old, new) in zip(originalParts, fittedParts) {
                let before = try XCTUnwrap(old.skinner), after = try XCTUnwrap(new.skinner)
                let a = try XCTUnwrap(before.boneInverseBindTransforms), b = try XCTUnwrap(after.boneInverseBindTransforms)
                let weights = try XCTUnwrap(GLTFModel.skinSources(for: old))
                let fittedWeights = try XCTUnwrap(GLTFModel.skinSources(for: new))
                XCTAssertTrue(weights.indices.data == fittedWeights.indices.data)
                XCTAssertTrue(weights.weights.data == fittedWeights.weights.data)
                let slot = try XCTUnwrap(after.bones.firstIndex { $0 === actor.instance.nodes[head] })
                XCTAssertTrue(before.bones[slot] === source.nodes[head])
                XCTAssertEqual(a.count, b.count)
                for j in a.indices where j != slot {
                    XCTAssertTrue(SCNMatrix4EqualToMatrix4(a[j].scnMatrix4Value, b[j].scnMatrix4Value))
                }
                headBinds.append((simd_float4x4(a[slot].scnMatrix4Value), simd_float4x4(b[slot].scnMatrix4Value)))
            }
        }
        XCTAssertEqual(headBinds.count, 4)
        let idle = try XCTUnwrap(character.profile.clip(role: "idle"))
        let attack = try XCTUnwrap(character.profile.clip(command: .weapon))
        for clip in [idle, attack] {
            for tick in [0, clip.ticks / 2, clip.ticks] {
                let selection = DuelWeaponPose(clip: clip.name, tick: tick, duration: clip.ticks,
                    groundLift: clip.tracks.lift(phase: Double(tick) / Double(clip.ticks)))
                var pose = model.restPose
                character.sample(selection, into: &pose)
                for index in model.animated { source.nodes[index].simdTransform = pose.transform(index) }
                actor.apply(selection)
                let expected = actor.instance.nodes[head].simdConvertVector(shift, to: nil)
                let actual = newFace.simdWorldPosition - oldFace.simdWorldPosition
                XCTAssertLessThan(simd_distance(actual, expected), 0.0001)
                let sourceJoint = source.nodes[head].simdWorldTransform
                let fittedJoint = actor.instance.nodes[head].simdWorldTransform
                for column in 0..<4 { XCTAssertLessThan(simd_length(sourceJoint[column] - fittedJoint[column]), 0.0001) }
                // Exact equality of these influence deltas across body and
                // bridge keeps their shared weighted collar seam together.
                // The unit-weight upper rim follows the rigid face exactly.
                for pair in headBinds {
                    let old = sourceJoint * pair.source, new = fittedJoint * pair.fitted
                    for column in 0..<3 { XCTAssertLessThan(simd_length(new[column] - old[column]), 0.0001) }
                    XCTAssertLessThan(simd_length(new.columns.3 - old.columns.3 - SIMD4<Float>(expected, 0)), 0.0001)
                }
            }
        }
    }

    func testInstalledRecoveredSourceClipsHaveFiniteFirstMiddleAndLastNativePoses() throws {
        let assets = try installed()
        defer { assets.releaseCharacters() }
        var clipCount = 0, poseCount = 0, nodeSamples = 0
        for wanted in expected {
            let character = try assets.character(for: wanted.hero)
            XCTAssertEqual(character.profile.sha256, wanted.sha256)
            let model = character.model, actor = DuelWeaponCharacterInstance(character)
            XCTAssertEqual(model.names.count, actor.instance.nodes.count)
            // Idle runs first, so the renderer's legitimate recovery-to-idle
            // smoothing never changes the exact source samples in this check.
            let idle = character.profile.roles["idle"]
            let clips = character.profile.clips.sorted {
                if ($0.name == idle) != ($1.name == idle) { return $0.name == idle }
                return $0.name < $1.name
            }
            XCTAssertEqual(clips.count, wanted.clips)
            for clip in clips {
                let native = try XCTUnwrap(model.clips[clip.name])
                XCTAssertTrue(DuelFighterAssetRelease.validDigest(clip.sha256))
                XCTAssertFalse(native.channels.isEmpty)
                XCTAssertTrue(native.duration.isFinite && native.duration > 0)
                XCTAssertGreaterThan(clip.frames, 1)
                XCTAssertGreaterThan(clip.ticks, 0)
                for tick in [0, clip.ticks / 2, clip.ticks] {
                    let selection = DuelWeaponPose(clip: clip.name, tick: tick, duration: clip.ticks,
                        groundLift: clip.tracks.lift(phase: Double(tick) / Double(clip.ticks)))
                    var pose = model.restPose
                    character.sample(selection, into: &pose)
                    actor.apply(selection)
                    for index in model.names.indices {
                        guard actor.instance.nodes.indices.contains(index),
                              let source = model.sourceTransform(of: index, pose: pose) else {
                            XCTFail("A loaded source node disappeared while sampling")
                            throw Failure.invalidNode
                        }
                        guard finite(pose.transform(index)), finite(source),
                              finite(actor.instance.nodes[index].simdWorldTransform) else {
                            XCTFail("An authenticated source clip produced a non-finite native pose")
                            throw Failure.nonFinitePose
                        }
                        nodeSamples += 1
                    }
                    poseCount += 1
                }
                clipCount += 1
            }
            assets.releaseCharacter(for: wanted.hero)
        }
        XCTAssertEqual(clipCount, 198)
        XCTAssertEqual(poseCount, 594)
        try attach(["characters": 3, "clips": clipCount, "nativePoses": poseCount,
                    "nodeSamples": nodeSamples, "renderedPixelsVerified": false],
                   name: "recovered-source-native-pose-metrics")
    }

    func testErlangAudioChecksDiskChangesAndSuppliedProfilesAgainstTheInstalledPin() throws {
        let index = try DuelWeaponAssetIndex()
        let verified = try XCTUnwrap(index.erlangProfile)
        let installed = verified.profile
        let other = DuelWeaponProfile(id: installed.id, hero: installed.hero, faction: installed.faction,
            resourceName: installed.resourceName, bytes: installed.bytes, sha256: installed.sha256,
            bodyID: installed.bodyID, weaponID: installed.weaponID, activeWeaponSides: installed.activeWeaponSides,
            roles: [:], clips: [])
        try DuelLocalProfileTestFixtures.withDirectory { directory in
            let destination = directory.appendingPathComponent(verified.name)
            try FileManager.default.copyItem(at: index.directory.appendingPathComponent(verified.name),
                                             to: destination)
            XCTAssertThrowsError(try DuelErlangSourceAudio.load(directory: directory,
                manifestName: DuelErlangAssetIdentity.audioManifestName,
                expectedSHA256: DuelErlangAssetIdentity.audioManifestSHA256,
                profileName: verified.name, profileSHA256: verified.sha256, profile: other)) { error in
                guard case DuelErlangSourceAudio.Failure.identity = error else {
                    return XCTFail("Expected a different supplied profile to be rejected: \(error)")
                }
            }
            var bytes = try Data(contentsOf: destination)
            bytes[0] ^= 1
            try bytes.write(to: destination)
            XCTAssertThrowsError(try DuelErlangSourceAudio.load(directory: directory,
                manifestName: DuelErlangAssetIdentity.audioManifestName,
                expectedSHA256: DuelErlangAssetIdentity.audioManifestSHA256,
                source: .indexed(verified))) { error in
                guard case let DuelErlangSourceAudio.Failure.file(name) = error, name == verified.name else {
                    return XCTFail("Expected changed profile bytes to be rejected: \(error)")
                }
            }
        }
    }

    func testInstalledD15HoundAndSchemaFiveAudioBindTheActualContourActor() throws {
        let assets = try installed()
        defer { assets.releaseCharacters() }
        let actor = try assets.character(for: .wuYong)
        XCTAssertEqual(actor.profile.sha256, expected[2].sha256)
        XCTAssertEqual(actor.profile.clips.count, 62)
        let companions = try XCTUnwrap(assets.erlangCompanions)
        XCTAssertEqual(companions.manifest.profileID, actor.profile.id)
        XCTAssertEqual(companions.manifest.characterSHA256, actor.profile.sha256)
        XCTAssertEqual(companions.manifest.models.count, 1)
        try companions.manifest.validate(profile: actor.profile)
        try audit(companions.verifiedFiles, in: assets.directory)
        let definition = try XCTUnwrap(companions.manifest.models.first)
        XCTAssertEqual(definition.sourceModel, "mgc__d15_dog")
        XCTAssertEqual(definition.track.clip, "d15_dog_attack")
        XCTAssertEqual(definition.track.frames, 60)
        XCTAssertEqual(Set(companions.model.clips.keys), [definition.track.clip])
        XCTAssertTrue(companions.model.hasSkinning)
        let model = companions.model, instance = model.instantiate()
        let skinNodes = geometryNodes(instance.root).filter { $0.skinner != nil }
        XCTAssertFalse(skinNodes.isEmpty)
        for node in skinNodes {
            let skin = try XCTUnwrap(node.skinner)
            let geometry = try XCTUnwrap(skin.baseGeometry)
            let positions = try XCTUnwrap(geometry.sources(for: .vertex).first)
            let sources = try XCTUnwrap(GLTFModel.skinSources(for: node))
            XCTAssertGreaterThan(skin.bones.count, 0)
            XCTAssertGreaterThan(positions.vectorCount, 0)
            XCTAssertEqual(sources.weights.vectorCount, positions.vectorCount)
            XCTAssertEqual(sources.indices.vectorCount, positions.vectorCount)
        }
        let clip = try XCTUnwrap(model.clips[definition.track.clip])
        XCTAssertEqual(clip.channels.count, 82)
        for fraction: Float in [0, 0.5, 1] {
            var pose = model.restPose
            clip.sample(at: companions.start + (clip.duration - companions.start) * fraction, into: &pose)
            for index in model.animated { instance.nodes[index].simdTransform = pose.transform(index) }
            for index in model.names.indices {
                XCTAssertTrue(finite(pose.transform(index)))
                XCTAssertTrue(finite(instance.nodes[index].simdWorldTransform))
            }
        }
        let audio = try XCTUnwrap(assets.erlangAudio)
        XCTAssertEqual(audio.profileID, actor.profile.id)
        XCTAssertEqual(audio.characterSHA256, actor.profile.sha256)
        try audit(audio.verifiedFiles, in: assets.directory)
        let documentData = try Data(contentsOf: assets.directory.appendingPathComponent(DuelErlangAssetIdentity.audioManifestName))
        XCTAssertEqual(DuelNetworkContentRecord.digest(documentData), DuelErlangAssetIdentity.audioManifestSHA256)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: documentData) as? [String: Any])
        XCTAssertEqual(document["schemaVersion"] as? Int, 5)
        XCTAssertEqual(document["profileSHA256"] as? String, DuelErlangAssetIdentity.profileSHA256)
        XCTAssertEqual(document["characterSHA256"] as? String, actor.profile.sha256)
        XCTAssertEqual(audio.verifiedFiles.count, 83) // 82 independently authenticated PCM files + manifest.
        XCTAssertEqual(audio.markers.count, 119)
        XCTAssertEqual(audio.markers.filter { $0.route == "Floor.Stone" }.count, 21)
        XCTAssertEqual(audio.pendingModelMarkerCount, 0)
        XCTAssertTrue(audio.hasMeditationTrigger)
        XCTAssertEqual(audio.clocks(stageSHA256: nil).count, 98)
        XCTAssertTrue(audio.audio.values.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.count > 44 } })
        let stage = try Data(contentsOf: assets.directory.appendingPathComponent("SF3_Palace_Exterior.glb"))
        let stageHash = DuelNetworkContentRecord.digest(stage)
        XCTAssertEqual(stageHash, DuelErlangSourceAudio.palaceStageSHA256)
        XCTAssertEqual(audio.clocks(stageSHA256: stageHash).count, 119)
        try attach(["actorClips": 62, "houndClips": 1, "houndChannels": clip.channels.count,
                    "houndSourceFrames": definition.track.frames, "houndNativePoses": 3,
                    "audioSchema": 5, "verifiedAudioFiles": 82, "audioMarkers": audio.markers.count,
                    "pendingModelMarkers": audio.pendingModelMarkerCount, "audiblePlaybackVerified": false],
                   name: "recovered-d15-companion-audio-metrics")
    }

    func testInstalledD15VictoryMorphUsesNewSunOwnerAndActualContourGeometry() throws {
        let assets = try installed()
        defer { assets.releaseCharacters() }
        let sun = try assets.character(for: .ember)
        let wu = try assets.character(for: .wuYong)
        let serpent = try assets.character(for: .liu)
        XCTAssertEqual(sun.profile.sha256, expected[0].sha256)
        XCTAssertEqual(wu.profile.sha256, expected[2].sha256)
        let morph = try XCTUnwrap(assets.erlangVictoryMorph)
        XCTAssertEqual(morph.ownerProfileID, sun.profile.id)
        XCTAssertEqual(morph.targetProfileID, wu.profile.id)
        XCTAssertEqual(morph.targetCharacterSHA256, wu.profile.sha256)
        let selected = try XCTUnwrap(assets.sourceMorph(for: [sun.profile, wu.profile]))
        XCTAssertTrue(selected === morph)
        let serpentMorph = try XCTUnwrap(assets.sourceMorph(for: [sun.profile, serpent.profile]))
        XCTAssertTrue(serpentMorph === assets.serpentVictoryMorph)
        XCTAssertFalse(serpentMorph === assets.triadMorph,
                       "The old hammer morph cannot authorize a D13 target")
        XCTAssertEqual(serpentMorph.targetProfileID, "liu_serpent")
        XCTAssertEqual(serpentMorph.targetCharacterSHA256, DuelSerpentAssetIdentity.characterSHA256)
        try audit(morph.verifiedFiles, in: assets.directory)
        let source = try Data(contentsOf: assets.directory.appendingPathComponent(DuelErlangAssetIdentity.victoryMorphManifestName))
        XCTAssertEqual(DuelNetworkContentRecord.digest(source), DuelErlangAssetIdentity.victoryMorphManifestSHA256)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: source) as? [String: Any])
        XCTAssertEqual(document["ownerCharacterSHA256"] as? String, sun.profile.sha256)
        XCTAssertEqual(document["targetCharacterSHA256"] as? String, wu.profile.sha256)
        XCTAssertEqual(Set(morph.materials.map(\.name)), ["mat_arm__agl_44_base", "mat_arm__agl_44_tie_base",
            "mat_wpn__agl_spear_01_01_base", "Material.001", "Personal_Neck_Bridge_Derived_Skin"])
        XCTAssertEqual(morph.trigger.sourceFrame, 36)
        XCTAssertEqual(morph.trigger.triggerTick, 70)
        XCTAssertEqual(morph.trigger.transitionTicks, 140)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "Private native acceptance requires its actual Metal device")
        let prepared = try morph.prepare(device: device)
        XCTAssertEqual(prepared.texture.width, 256)
        XCTAssertEqual(prepared.texture.height, 256)
        XCTAssertEqual(prepared.texture.pixelFormat, .etc2_rgb8)
        let instance = DuelWeaponCharacterInstance(wu)
        let binding = try prepared.install(on: instance.instance, materials: morph.materials)
        defer { binding.shutdown() }
        XCTAssertEqual(binding.progress, 0)
        XCTAssertFalse(binding.isComplete)
        // No fabricated render callback: the dedicated UI capture must commit
        // a real scene command buffer before advancing the source morph boundary.
        try attach(["boundMaterials": morph.materials.count, "maskWidth": prepared.texture.width,
                    "maskHeight": prepared.texture.height, "targetClips": wu.profile.clips.count,
                    "metalMaskAllocated": true, "actualGeometryInstalled": true,
                    "morphRenderedPixelsVerified": false, "physicalDeviceVerified": false],
                   name: "recovered-d15-native-morph-binding-metrics")
    }
}
