import XCTest
@testable import ShiftCore

final class DuelErlangCompanionManifestTests: XCTestCase {
    private func fixture() throws -> (DuelErlangCompanionManifest, DuelWeaponProfile) {
        let zero = Array(repeating: DuelWeaponPoint(), count: 119)
        let radii = ["Dog_Head_Attacking_Edge": 200, "Dog_Body_Attacking_Edge": 100,
                     "Dog_Front_Attacking_Edge_l": 120, "Dog_Front_Attacking_Edge_r": 120,
                     "Dog_Back_Attacking_Edge_l": 120, "Dog_Back_Attacking_Edge_r": 120]
        let track = DuelSummonMotionTrack(role: DuelErlangCompanionManifest.role,
            clip: "d15_dog_attack", frames: 60, sourceSHA256: DuelErlangCompanionManifest.sourceMotionSHA256,
            sourceBundle: "2a784bc550bc06541a38a4c1c53b69f3.bin", root: zero,
            groundLift: Array(repeating: 0, count: 119),
            boneConfigurationSHA256: DuelErlangCompanionManifest.sourceBonesSHA256,
            collisionEdges: radii.keys.sorted().map { .init(id: $0, side: $0.hasSuffix("_l") ? "left" : "right",
                radiusMillimeters: radii[$0]!, base: zero, tip: zero) }, hurtCapsules: [],
            attackParts: ["primary": DuelErlangCompanionManifest.attackParts], sourceEndEventTick: 110)
        let profile = DuelWeaponProfile(id: "wuyong_erlang", hero: .wuYong, faction: "Dynasty",
            resourceName: "synthetic_manifest_test", bytes: 1, sha256: String(repeating: "a", count: 64),
            bodyID: "synthetic", weaponID: "synthetic", activeWeaponSides: ["right"],
            roles: [:], clips: [], summonTracks: [track])
        let material = DuelFighterAssetRelease.Material(name: "mat_mgc__d15_dog_base", doubleSided: true,
            cull: .back, minification: .linear, magnification: .linear, mip: .none,
            wrapS: .repeat, wrapT: .repeat, maxAnisotropy: 1)
        let value = DuelErlangCompanionManifest.Model(sourceModel: "mgc__d15_dog", rootBone: "spine_root_joint",
            file: .init(name: "SF3WE_D15_Hound.glb", bytes: 1, sha256: String(repeating: "b", count: 64)),
            materials: [material], track: track, originalMotionFrames: 141, firstSourceFrame: 1,
            lastSourceFrame: 60, exportFramesPerSecond: 30, endEventTick: 110,
            hideStartTick: 0, hideEndTick: 55, fadeOutTicks: 10, fadeInTicks: 15)
        return (.init(version: 1, profileID: profile.id, characterSHA256: profile.sha256,
                      sourceConfigurationSHA256: DuelErlangCompanionManifest.sourceConfigurationSHA256,
                      models: [value]), profile)
    }

    func testSourceWindowRigIdentityAndPhysicsJoinAreStrict() throws {
        let (manifest, profile) = try fixture()
        XCTAssertNoThrow(try manifest.validate(profile: profile))
        for change in ["window", "root", "source", "physics", "character"] {
            var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any])
            var models = value["models"] as! [[String: Any]]
            if change == "window" { models[0]["lastSourceFrame"] = 141 }
            if change == "root" { models[0]["rootBone"] = "pelvis" }
            if change == "character" { value["characterSHA256"] = String(repeating: "c", count: 64) }
            if change == "source" || change == "physics" {
                var track = models[0]["track"] as! [String: Any]
                if change == "source" { track["sourceSHA256"] = String(repeating: "d", count: 64) }
                else {
                    var roots = track["root"] as! [[Double]]
                    roots[17][0] = 0.1; track["root"] = roots
                }
                models[0]["track"] = track
            }
            value["models"] = models
            let altered = try JSONDecoder().decode(DuelErlangCompanionManifest.self,
                from: JSONSerialization.data(withJSONObject: value))
            XCTAssertThrowsError(try altered.validate(profile: profile), change)
        }
    }

    func testHideTimingIsPureAndDoesNotExtendNativeEndEvent() throws {
        let model = try fixture().0.models[0]
        for (tick, opacity) in [(-1, 0.0), (0, 1), (5, 0.5), (10, 0), (55, 0), (56, 0),
                                (71, 1), (110, 1), (111, 0), (118, 0)] {
            XCTAssertEqual(model.opacity(at: tick), opacity, accuracy: 0.000001)
        }
        let early = model.opacity(at: 5)
        _ = model.opacity(at: 100)
        XCTAssertEqual(model.opacity(at: 5), early)
    }

    func testActualPrivateCandidateDecodesAndJoinsExactSourceGeometryWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["ERLANG_HOUND_CANDIDATE"] else {
            throw XCTSkip("Actual private source candidate is supplied by the offline build.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let source = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let track = try JSONDecoder().decode(DuelSummonMotionTrack.self,
            from: JSONSerialization.data(withJSONObject: try XCTUnwrap(source["track"])))
        let (base, originalProfile) = try fixture()
        var profileJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(originalProfile)) as? [String: Any])
        profileJSON["summonTracks"] = [source["track"]!]
        let profile = try JSONDecoder().decode(DuelWeaponProfile.self,
            from: JSONSerialization.data(withJSONObject: profileJSON))
        var manifestJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
        var models = manifestJSON["models"] as! [[String: Any]]
        models[0]["track"] = source["track"]
        models[0]["file"] = source["modelFile"]
        models[0]["materials"] = source["materials"]
        manifestJSON["models"] = models
        let manifest = try JSONDecoder().decode(DuelErlangCompanionManifest.self,
            from: JSONSerialization.data(withJSONObject: manifestJSON))
        XCTAssertNoThrow(try manifest.validate(profile: profile))
        XCTAssertEqual(track.root.count, 119)
        XCTAssertEqual(track.collisionEdges?.count, 6)
        XCTAssertEqual(track.attackParts?["primary"], DuelErlangCompanionManifest.attackParts)
        XCTAssertTrue(track.collisionEdges!.contains { $0.base[0] != $0.base[22] })
        XCTAssertNotEqual(track.offsetX(at: 22), track.offsetX(at: 67))
        let release = try XCTUnwrap(source["releaseBinding"] as? [String: Any])
        let offset = try JSONDecoder().decode(DuelWeaponPoint.self,
            from: JSONSerialization.data(withJSONObject: try XCTUnwrap(release["offset"])))
        XCTAssertEqual(offset, DuelWeaponPoint())
    }
}
