import XCTest
import SceneKit
import simd
@testable import ShiftReminder

#if DEBUG
/// The final installed release must reach the real character loader and native
/// skin construction. Binding metadata or a successful app launch is insufficient.
/// This method does not certify rendered pixels, audible output or a device.
@MainActor
final class DuelSharedRootInstalledModelTests: XCTestCase {
    private enum Failure: Error { case unapprovedInstalledRevision }

    func testFinalSharedRootReleaseLoadsBothOriginalCharactersAndAllThreeLiuVictimMotions() throws {
        let releaseSHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
        let pin = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: DuelFighterAssetRelease.infoKey) as? String)
        XCTAssertEqual(pin, releaseSHA, "This check requires the final shared-root v2 installed resources")
        guard pin == releaseSHA else { throw Failure.unapprovedInstalledRevision }
        let assets = try DuelWeaponAssets()
        defer { assets.releaseCharacters() }
        let release = try XCTUnwrap(assets.release)
        XCTAssertEqual(release.definition.id, "h17-shared-root-floorfall-20261115-v2")
        XCTAssertEqual(Set(assets.catalog.profiles.map(\.id)), Set(["sun_triad", "liu_hammers"]))
        XCTAssertNil(release.definition.panguAudio)
        XCTAssertNil(assets.panguAudio)

        var characters: [[String: Any]] = []
        var motions: [[String: Any]] = []
        defer {
            let report: [String: Any] = [
                "releaseSHA256": releaseSHA,
                "characters": characters, "liuVictimMotions": motions,
                "scope": "Installed GLB loading, native skin construction and finite pose samples; XCTest owns the outcome",
                "renderedPixelsVerified": false, "audiblePlaybackVerified": false,
                "physicalDeviceVerified": false, "panguEquipmentActivated": false
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "shared-root-installed-model-report"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }

        let expected: [(DuelGame.Hero, String, String, String, String, Int, Int)] = [
            (.ember, "sun_triad", "arm__prc_43", "wpn__ninjato_01_06",
             "ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6", 65, 87),
            (.liu, "liu_hammers", "arm__str_03", "wpn__hammers_01_01",
             "a3aada76d336b9c4f9bda3904b5e947711d916f683a2dcbf7b8184377e01a517", 59, 76)
        ]
        let boneNames = ["pelvis", "head", "hand_l", "hand_r", "foot_l", "foot_r", "weapon_l", "weapon_r"]
        for (hero, id, body, weapon, hash, clipCount, skinJointCount) in expected {
            // This call authenticates and decodes the actual GLB; the ordinary
            // DuelWeaponAssets initializer only confirms its path exists.
            let character = try assets.character(for: hero)
            let profile = character.profile
            XCTAssertEqual(profile.id, id)
            XCTAssertEqual(profile.hero, hero)
            XCTAssertEqual(profile.bodyID, body)
            XCTAssertEqual(profile.weaponID, weapon)
            XCTAssertEqual(profile.sha256, hash)
            XCTAssertEqual(profile.clips.count, clipCount)
            XCTAssertEqual(character.model.clips.count, clipCount)
            XCTAssertEqual(Set(character.model.clips.keys), Set(profile.clips.map(\.name)))
            XCTAssertTrue(character.model.hasSkinning)
            XCTAssertEqual(character.releaseBinding?.characterSHA256, hash)
            XCTAssertEqual(profile.isTriad, hero == .ember)
            XCTAssertFalse(profile.isPangu, "A shared victim animation cannot authorize D19 equipment")
            for name in boneNames {
                XCTAssertNotNil(character.model.node(named: name), "\(id): missing source bone \(name)")
            }
            XCTAssertNotNil(character.model.node(named: hero == .ember ? "Sun_Personal_Head" : "Liu_Personal_Head"))

            let actor = DuelWeaponCharacterInstance(character)
            var holders: [SCNNode] = []
            actor.instance.root.enumerateChildNodes { node, _ in
                if node.skinner != nil { holders.append(node) }
            }
            // The instance also installs separately bound source trail meshes.
            // Their smaller skeletons are not the GLB character's joint table.
            let trailHolders = Set((actor.sourceTrailBinding?.holders ?? []).map(ObjectIdentifier.init))
            let bodyHolders = holders.filter { !trailHolders.contains(ObjectIdentifier($0)) }
            XCTAssertFalse(bodyHolders.isEmpty, "A loaded character must instantiate actual skinned geometry")
            var vertices = 0
            for holder in holders {
                let skin = try XCTUnwrap(holder.skinner)
                let geometry = try XCTUnwrap(skin.baseGeometry)
                let positions = try XCTUnwrap(geometry.sources(for: .vertex).first)
                XCTAssertGreaterThan(positions.vectorCount, 0)
                XCTAssertGreaterThan(geometry.elements.reduce(0) { $0 + $1.primitiveCount }, 0)
                XCTAssertGreaterThan(skin.bones.count, 0)
                if !trailHolders.contains(ObjectIdentifier(holder)) {
                    XCTAssertEqual(skin.bones.count, skinJointCount)
                    vertices += positions.vectorCount
                }
                XCTAssertNotNil(skin.skeleton)
                XCTAssertEqual(skin.boneInverseBindTransforms?.count, skin.bones.count)
                // iOS may expose empty boneWeights/boneIndices getters after
                // construction. Use the existing exact native-input receipt.
                let inputs = try XCTUnwrap(GLTFModel.skinSources(for: holder))
                XCTAssertEqual(inputs.weights.vectorCount, positions.vectorCount)
                XCTAssertEqual(inputs.indices.vectorCount, positions.vectorCount)
            }
            characters.append(["profileID": id, "characterSHA256": hash,
                "catalogClips": profile.clips.count, "loadedClips": character.model.clips.count,
                "skinJointCount": skinJointCount, "skinnedMeshes": bodyHolders.count,
                "sourceTrailSkinnedMeshes": holders.count - bodyHolders.count,
                "skinnedVertices": vertices, "isPangu": profile.isPangu])

            guard hero == .liu else { continue }
            XCTAssertTrue(DuelTriadRootVictimState.matches(profile: profile))
            for motion in DuelTriadRootVictimState.Motion.allCases {
                let clip = try XCTUnwrap(profile.clip(named: motion.clip))
                let native = try XCTUnwrap(character.model.clips[motion.clip])
                XCTAssertEqual(clip.sha256, motion.sourceSHA256)
                XCTAssertEqual(clip.frames, motion.frames)
                XCTAssertEqual(clip.ticks, motion.lastSampleTick)
                XCTAssertFalse(native.channels.isEmpty)
                XCTAssertTrue(native.duration.isFinite && native.duration > 0)
                let ticks = motion == .end ? [0, 37, 38, motion.lastSampleTick] :
                    [0, motion.lastSampleTick / 2, motion.lastSampleTick]
                for tick in ticks {
                    let selection = DuelWeaponPose(clip: clip.name, tick: tick, duration: clip.ticks,
                        groundLift: clip.tracks.lift(phase: Double(tick) / Double(clip.ticks)), reaction: true)
                    actor.apply(selection)
                    var pose = character.model.restPose
                    character.sample(selection, into: &pose)
                    for name in boneNames {
                        let index = try XCTUnwrap(character.model.node(named: name))
                        let source = try XCTUnwrap(character.model.sourceTransform(of: index, pose: pose))
                        for transform in [source, actor.instance.nodes[index].simdWorldTransform] {
                            let columns = [transform.columns.0, transform.columns.1, transform.columns.2, transform.columns.3]
                            XCTAssertTrue(columns.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite },
                                          "\(motion.clip) tick\(tick): invalid \(name) transform")
                        }
                    }
                }
                motions.append(["clip": motion.clip, "sourceSHA256": clip.sha256,
                    "sourceFrames": clip.frames, "lastSampleTick": clip.ticks,
                    "loadedChannels": native.channels.count, "sampledTicks": ticks])
            }
        }
        XCTAssertEqual(characters.count, 2)
        XCTAssertEqual(motions.count, 3)
    }
}
#endif
