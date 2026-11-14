import XCTest
import SceneKit
import UIKit
@testable import ShiftReminder

/// Synthetic triangles, textures and a tiny skeleton verify target binding and
/// rejection paths. They are not original Pangu geometry, trails or materials.
@MainActor
final class DuelPanguSourceTrailBindingTests: XCTestCase {
    private struct Fixture {
        let directory: URL
        let url: URL
        let catalog: DuelWeaponCatalog
        var document: [String: Any]
        var digest: String
    }

    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pangu-trail-contract-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let zero = Array(repeating: DuelWeaponPoint(), count: 3)
        let clip = DuelWeaponClip(name: "synthetic_swing", frames: 2, sha256: String(repeating: "c", count: 64),
            bundle: "synthetic-native-binding", tracks: .init(samplesPerSourceFrame: 2, root: zero,
                handL: zero, handR: zero, footL: zero, footR: zero, weaponBaseL: [], weaponTipL: [],
                weaponBaseR: zero, weaponTipR: zero, groundLift: [0, 0, 0]))
        var profiles: [DuelWeaponProfile] = [], sourceProfiles: [[String: Any]] = []
        for (index, id) in ["sun_katana", "liu_pangu"].enumerated() {
            let profile = DuelWeaponProfile(id: id, hero: index == 0 ? .ember : .liu,
                faction: "synthetic", resourceName: "Synthetic_\(index)", bytes: 1,
                sha256: String(repeating: index == 0 ? "a" : "b", count: 64),
                bodyID: "synthetic-body-\(index)", weaponID: "synthetic-weapon-\(index)",
                activeWeaponSides: ["right"], roles: ["weapon1": clip.name], clips: [clip], comboLinks: nil)
            profiles.append(profile)
            let textureName = "SF3PG_Synthetic_\(index)_alpha.png"
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format).image { context in
                UIColor(white: index == 0 ? 1 : 0.5, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
            let png = try XCTUnwrap(image.pngData()); try png.write(to: directory.appendingPathComponent(textureName))
            let identity: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
            let mesh: [String: Any] = [
                "name": "synthetic-trail-\(index)", "side": "right",
                "bones": ["bone0", "bone1", "bone2", "bone3"], "sourceBoneIDs": [20, 21, 22, 23],
                "positions": [0, 0, 0, 1, 0, 0, 0, 1, 0],
                "normals": [0, 0, 1, 0, 0, 1, 0, 0, 1], "uv": [0, 0, 1, 0, 0, 1],
                "weights": [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
                "joints": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "indices": [0, 1, 2],
                "inverseBinds": Array(repeating: identity, count: 4),
                "material": ["shader": "alpha-mask", "alphaChannel": "alpha", "blend": "add",
                    "doubleSided": false, "cullMode": "front", "readsDepth": false, "writesDepth": false,
                    "wrapS": 0, "wrapT": 1, "filter": "nearest", "tint": [1, 0.75, 0.25, 0.5]]
            ]
            sourceProfiles.append(["id": id, "characterSHA256": profile.sha256, "meshes": [mesh],
                "clips": [clip.name], "skeletonNode": "syntheticSkeleton", "attachmentNode": "syntheticActor",
                "clipWindows": [["clip": clip.name, "startPhaseBps": 2500, "endPhaseBps": 7500]],
                "alpha": ["name": textureName, "bytes": png.count, "sha256": DuelNetworkContentRecord.digest(png),
                          "width": 2, "height": 2]])
        }
        // The binding loader consumes identities from a catalog that the caller
        // has already authenticated. This reduced fixture is not a playable set.
        let catalog = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
                                        sourceFramesPerSecond: nil, profiles: profiles)
        var result = Fixture(directory: directory, url: directory.appendingPathComponent("Synthetic_TargetTrails.json"),
            catalog: catalog, document: ["version": 2, "profiles": sourceProfiles], digest: "")
        try write(&result); return result
    }

    private func write(_ fixture: inout Fixture) throws {
        let data = try JSONSerialization.data(withJSONObject: fixture.document, options: [.sortedKeys])
        try data.write(to: fixture.url); fixture.digest = DuelNetworkContentRecord.digest(data)
    }
    private func load(_ fixture: Fixture) throws -> DuelSourceWeaponTrails {
        try .init(url: fixture.url, expectedSHA256: fixture.digest, catalog: fixture.catalog)
    }
    private func mutatePangu(_ fixture: inout Fixture, _ change: (inout [String: Any]) -> Void) throws {
        var profiles = try XCTUnwrap(fixture.document["profiles"] as? [[String: Any]])
        change(&profiles[1]); fixture.document["profiles"] = profiles; try write(&fixture)
    }
    private func mutateMesh(_ fixture: inout Fixture, _ change: (inout [String: Any]) -> Void) throws {
        try mutatePangu(&fixture) { profile in
            var meshes = profile["meshes"] as! [[String: Any]]
            change(&meshes[0]); profile["meshes"] = meshes
        }
    }

    func testTargetProfilesUseTheirOwnVerifiedTexturesAndCompleteReceipts() throws {
        let fixture = try fixture(), trails = try load(fixture)
        XCTAssertEqual(Set(trails.profiles.map(\.id)), ["sun_katana", "liu_pangu"])
        XCTAssertEqual(Set(trails.profiles.compactMap { $0.alpha?.sha256 }).count, 2)
        XCTAssertEqual(trails.verifiedFiles.count, 3)
        XCTAssertEqual(trails.verifiedFiles.map(\.path), trails.verifiedFiles.map(\.path).sorted())
        for record in trails.verifiedFiles {
            let data = try Data(contentsOf: fixture.directory.appendingPathComponent(record.path))
            XCTAssertEqual(record.bytes, data.count)
            XCTAssertEqual(record.sha256, DuelNetworkContentRecord.digest(data))
        }
    }

    func testTargetManifestCannotUseLegacyPinOrIgnoreItsReleasePin() throws {
        let fixture = try fixture()
        XCTAssertThrowsError(try DuelSourceWeaponTrails(url: fixture.url))
        XCTAssertThrowsError(try DuelSourceWeaponTrails(url: fixture.url,
            expectedSHA256: String(repeating: "0", count: 64), catalog: fixture.catalog))
        try Data("unrelated old pack".utf8).write(to: fixture.directory.appendingPathComponent(DuelSourceWeaponTrails.fileName))
        XCTAssertNoThrow(try load(fixture), "Only the explicitly pinned target path is authoritative")
    }

    func testUnknownProfileWrongModelAndMissingClipFailClosed() throws {
        for mutation in ["profile", "character", "clip", "duplicate"] {
            var fixture = try fixture()
            try mutatePangu(&fixture) { profile in
                switch mutation {
                case "profile": profile["id"] = "liu_hammers"
                case "character": profile["characterSHA256"] = String(repeating: "0", count: 64)
                case "clip": profile["clips"] = ["unbound-source-clip"]
                default: profile["id"] = "sun_katana"
                }
            }
            XCTAssertThrowsError(try load(fixture), mutation)
        }
    }

    func testMissingOrUnsupportedMaterialCannotChooseLegacyDefaults() throws {
        for mutation in ["missing", "shader", "channel", "blend", "cull", "filter", "tint"] {
            var fixture = try fixture()
            try mutateMesh(&fixture) { mesh in
                if mutation == "missing" { mesh.removeValue(forKey: "material"); return }
                var material = mesh["material"] as! [String: Any]
                switch mutation {
                case "shader": material["shader"] = "unimplemented-source-shader"
                case "channel": material["alphaChannel"] = "green"
                case "blend": material["blend"] = "multiply"
                case "cull": material["cullMode"] = "unknown"
                case "filter": material["filter"] = "trilinear"
                default: material["tint"] = [1, 1, 1, 4]
                }
                mesh["material"] = material
            }
            XCTAssertThrowsError(try load(fixture), mutation)
        }
    }

    func testMissingActiveSideInvalidBoneIndexAndBadWeightsFailClosed() throws {
        for mutation in ["side", "joint", "weight", "sourceID", "skeleton"] {
            var fixture = try fixture()
            if mutation == "skeleton" {
                try mutatePangu(&fixture) { $0.removeValue(forKey: "skeletonNode") }
            } else {
                try mutateMesh(&fixture) { mesh in
                    switch mutation {
                    case "side": mesh["side"] = "left"
                    case "joint": mesh["joints"] = [4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
                    case "weight": mesh["weights"] = [2, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
                    default: mesh["sourceBoneIDs"] = [20, 20, 22, 23]
                    }
                }
            }
            XCTAssertThrowsError(try load(fixture), mutation)
        }
    }

    func testCorruptWrongSizeSymlinkAndEscapingTextureFailClosed() throws {
        for mutation in ["corrupt", "size", "symlink", "path", "prefix"] {
            var fixture = try fixture()
            let url = fixture.directory.appendingPathComponent("SF3PG_Synthetic_1_alpha.png")
            switch mutation {
            case "corrupt": try Data("corrupt".utf8).write(to: url)
            case "symlink":
                try FileManager.default.removeItem(at: url)
                try FileManager.default.createSymbolicLink(at: url,
                    withDestinationURL: fixture.directory.appendingPathComponent("SF3PG_Synthetic_0_alpha.png"))
            default:
                if mutation == "prefix" {
                    try FileManager.default.copyItem(at: url, to: fixture.directory.appendingPathComponent("Unprotected_alpha.png"))
                }
                try mutatePangu(&fixture) { profile in
                    var alpha = profile["alpha"] as! [String: Any]
                    if mutation == "size" { alpha["width"] = 5 }
                    else if mutation == "prefix" { alpha["name"] = "Unprotected_alpha.png" }
                    else { alpha["name"] = "../SF3PG_Synthetic_1_alpha.png" }
                    profile["alpha"] = alpha
                }
            }
            XCTAssertThrowsError(try load(fixture), mutation)
        }
    }

    func testAuthoredMaterialAndSkeletonAreInstalledWithoutLegacySubstitution() throws {
        let fixture = try fixture(), trails = try load(fixture), model = try model(in: fixture.directory)
        let profile = try XCTUnwrap(fixture.catalog.profile(for: .liu))
        try trails.validate(model: model, profile: profile)
        let instance = model.instantiate(), binding = trails.install(on: instance, model: model, profile: profile)
        defer { withExtendedLifetime(instance) {} }
        let material = try XCTUnwrap(binding.holders.first?.geometry?.firstMaterial)
        XCTAssertEqual(binding.holders.count, 1)
        XCTAssertEqual(material.blendMode, .add)
        XCTAssertEqual(material.cullMode, .front)
        XCTAssertFalse(material.isDoubleSided)
        XCTAssertFalse(material.readsFromDepthBuffer)
        XCTAssertFalse(material.writesToDepthBuffer)
        let texture = try XCTUnwrap(material.value(forKey: "sourceAlpha") as? SCNMaterialProperty)
        XCTAssertEqual(texture.wrapS, .repeat); XCTAssertEqual(texture.wrapT, .clamp)
        XCTAssertEqual(texture.minificationFilter, .nearest)
        XCTAssertTrue(material.shaderModifiers?[.fragment]?.contains(").a") == true)
        let skin = try XCTUnwrap(binding.holders.first?.skinner)
        XCTAssertEqual(skin.bones.map(\.name), ["bone0", "bone1", "bone2", "bone3"])
        XCTAssertTrue(skin.skeleton === instance.nodes[try XCTUnwrap(model.node(named: "syntheticSkeleton"))])
        XCTAssertTrue(binding.root.parent === instance.nodes[try XCTUnwrap(model.node(named: "syntheticActor"))])
        binding.update(clip: "synthetic_swing", active: false, phaseBps: 5000); XCTAssertFalse(binding.root.isHidden)
        binding.update(clip: "old_hammer_clip", active: true, phaseBps: 5000); XCTAssertTrue(binding.root.isHidden)
        binding.root.removeFromParentNode()
        XCTAssertFalse(binding.supports("synthetic_swing"))
    }

    func testModelBindingRejectsMissingBonesAndClips() throws {
        var fixture = try fixture()
        let model = try model(in: fixture.directory), profile = try XCTUnwrap(fixture.catalog.profile(for: .liu))
        try mutateMesh(&fixture) { $0["bones"] = ["missing", "bone1", "bone2", "bone3"] }
        XCTAssertThrowsError(try load(fixture).validate(model: model, profile: profile))
        var clipFixture = try self.fixture()
        let otherClip = DuelWeaponClip(name: "synthetic_other", frames: 2, sha256: profile.clips[0].sha256,
                                      bundle: "synthetic", tracks: profile.clips[0].tracks)
        let modified = DuelWeaponProfile(id: profile.id, hero: .liu, faction: "synthetic", resourceName: profile.resourceName,
            bytes: profile.bytes, sha256: profile.sha256, bodyID: profile.bodyID, weaponID: profile.weaponID,
            activeWeaponSides: ["right"], roles: ["weapon1": otherClip.name], clips: [otherClip], comboLinks: nil)
        try mutatePangu(&clipFixture) {
            $0["clips"] = [otherClip.name]
            $0["clipWindows"] = [["clip": otherClip.name, "startPhaseBps": 2500, "endPhaseBps": 7500]]
        }
        let catalog = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30, sourceFramesPerSecond: nil,
            profiles: [clipFixture.catalog.profiles[0], modified])
        let trails = try DuelSourceWeaponTrails(url: clipFixture.url, expectedSHA256: clipFixture.digest, catalog: catalog)
        XCTAssertThrowsError(try trails.validate(model: model, profile: modified))
    }

    func testTargetPhaseWindowsIncludeExactBoundariesAndIgnoreLegacySpeed() throws {
        let fixture = try fixture(), trails = try load(fixture), model = try model(in: fixture.directory)
        let profile = try XCTUnwrap(fixture.catalog.profile(for: .liu))
        try trails.validate(model: model, profile: profile)
        let instance = model.instantiate()
        defer { withExtendedLifetime(instance) {} }
        let binding = trails.install(on: instance, model: model, profile: profile)
        for (phase, visible) in [(2499, false), (2500, true), (5000, true), (7500, true), (7501, false)] {
            binding.update(clip: "synthetic_swing", active: false, phaseBps: phase)
            XCTAssertEqual(!binding.root.isHidden, visible, "phase=\(phase)")
            binding.update(clip: "synthetic_swing", active: false, phaseBps: phase)
            XCTAssertEqual(!binding.root.isHidden, visible, "Repeated draw must not advance the authored phase")
        }
        binding.update(clip: "synthetic_swing", active: true, phaseBps: 5000, enabled: false)
        XCTAssertTrue(binding.root.isHidden)
        binding.update(clip: "synthetic_swing", active: true)
        XCTAssertTrue(binding.root.isHidden, "A target phase cannot be guessed from the old active flag")
        binding.update(clip: "synthetic_swing", active: true, phaseBps: 10_001)
        XCTAssertTrue(binding.root.isHidden)
    }

    func testTargetWindowsRequireEveryClipAndRejectOverlapsOrInvalidPhases() throws {
        for mutation in ["missing", "unknown", "overlap", "duplicate", "negative", "tooLarge", "reversed"] {
            var fixture = try fixture()
            try mutatePangu(&fixture) { profile in
                if mutation == "missing" { profile.removeValue(forKey: "clipWindows"); return }
                var windows: [[String: Any]] = [["clip": "synthetic_swing", "startPhaseBps": 2500, "endPhaseBps": 7500]]
                switch mutation {
                case "unknown": windows[0]["clip"] = "old_hammer_clip"
                case "overlap": windows.append(["clip": "synthetic_swing", "startPhaseBps": 7500, "endPhaseBps": 9000])
                case "duplicate": windows.append(windows[0])
                case "negative": windows[0]["startPhaseBps"] = -1
                case "tooLarge": windows[0]["endPhaseBps"] = 10_001
                default: windows[0]["endPhaseBps"] = 2499
                }
                profile["clipWindows"] = windows
            }
            XCTAssertThrowsError(try load(fixture), mutation)
        }
        var valid = try fixture()
        try mutatePangu(&valid) {
            $0["clipWindows"] = [["clip": "synthetic_swing", "startPhaseBps": 0, "endPhaseBps": 2499],
                                  ["clip": "synthetic_swing", "startPhaseBps": 2500, "endPhaseBps": 10_000]]
        }
        XCTAssertNoThrow(try load(valid))
    }

    func testLegacyBindingStillUsesItsOriginalActiveFlag() {
        let parent = SCNNode(), root = SCNNode(); parent.addChildNode(root)
        let binding = DuelSourceWeaponTrails.Binding(root: root, holders: [], clips: ["legacy"])
        binding.update(clip: "legacy", active: false, phaseBps: 5000); XCTAssertTrue(root.isHidden)
        binding.update(clip: "legacy", active: true); XCTAssertFalse(root.isHidden)
        binding.update(clip: "legacy", active: true, enabled: false); XCTAssertTrue(root.isHidden)
    }

    /// Only enough glTF to supply real SceneKit nodes and one decoded channel.
    /// The trail itself owns the synthetic triangle; this is not a character.
    private func model(in directory: URL) throws -> GLTFModel {
        let values: [Float] = [0, 1.0 / 30.0, 0, 0, 0, 0.1, 0, 0]
        let binary = values.withUnsafeBufferPointer { Data(buffer: $0) }
        try binary.write(to: directory.appendingPathComponent("Synthetic_skeleton.bin"))
        let document: [String: Any] = [
            "asset": ["version": "2.0"], "scene": 0, "scenes": [["nodes": [0]]],
            "nodes": [["name": "syntheticSkeleton", "children": [1]],
                      ["name": "syntheticActor", "children": [2, 3, 4, 5]],
                      ["name": "bone0"], ["name": "bone1"], ["name": "bone2"], ["name": "bone3"]],
            "buffers": [["uri": "Synthetic_skeleton.bin", "byteLength": binary.count]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": 8],
                            ["buffer": 0, "byteOffset": 8, "byteLength": 24]],
            "accessors": [["bufferView": 0, "componentType": 5126, "count": 2, "type": "SCALAR"],
                          ["bufferView": 1, "componentType": 5126, "count": 2, "type": "VEC3"]],
            "animations": [["name": "synthetic_swing",
                "samplers": [["input": 0, "output": 1, "interpolation": "LINEAR"]],
                "channels": [["sampler": 0, "target": ["node": 2, "path": "translation"]]]]]
        ]
        let url = directory.appendingPathComponent("Synthetic_skeleton.gltf")
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]).write(to: url)
        return try GLTFModel(url: url)
    }
}
