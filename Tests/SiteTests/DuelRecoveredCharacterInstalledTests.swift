import Foundation
import XCTest
import SceneKit
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
              skinMeshes: 9, skinVertices: 21_936, skinTriangles: 31_356,
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
            XCTAssertEqual(vertices, wanted.skinVertices)
            XCTAssertEqual(triangles, wanted.skinTriangles)
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
