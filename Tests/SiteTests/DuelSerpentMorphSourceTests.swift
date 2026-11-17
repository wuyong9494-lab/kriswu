import Foundation
import Metal
import SceneKit
import XCTest
@testable import ShiftReminder

/// Actual authenticated D13 inputs are required; absence fails rather than
/// skipping. These checks exercise native installation and its source clock,
/// while rendered victory footage remains a separate acceptance requirement.
@MainActor
final class DuelSerpentMorphSourceTests: XCTestCase {
    private struct Inputs {
        let directory: URL
        let owner: DuelWeaponProfile
        let target: DuelWeaponProfile
        let document: Data
        let mask: Data
    }

    private func inputs() throws -> Inputs {
        let directory: URL
        if let path = ProcessInfo.processInfo.environment["SERPENT_MORPH_DIRECTORY"] {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            let file = try XCTUnwrap(Bundle.main.url(forResource: DuelSerpentAssetIdentity.victoryMorphManifestName,
                withExtension: nil) ?? Bundle.main.url(forResource: DuelSerpentAssetIdentity.victoryMorphManifestName,
                withExtension: nil, subdirectory: "FighterPrivate"),
                "The authenticated D13 victory morph must be installed")
            directory = file.deletingLastPathComponent()
        }
        let catalogData = try Data(contentsOf: directory.appendingPathComponent("SF3_DistinctFighters.json"))
        XCTAssertEqual(DuelWeaponAssets.digest(catalogData),
            "77f7dd57c512aed3091fbedf8815ea5c6fc4b80725e9785cb2953bce2a47b6f4")
        let catalog = try JSONDecoder().decode(DuelWeaponCatalog.self, from: catalogData)
        try catalog.validate()
        let owner = try XCTUnwrap(catalog.profiles.first(where: \.isTriad))
        XCTAssertEqual(owner.sha256, "7c9ebfe285f637cbd002f717d80b859a57d3ab11ef491f15930dc4f3eb50d96a")
        let profileData = try Data(contentsOf: directory.appendingPathComponent(DuelSerpentAssetIdentity.profileName))
        XCTAssertEqual(DuelWeaponAssets.digest(profileData), DuelSerpentAssetIdentity.profileSHA256)
        let target = try JSONDecoder().decode(DuelWeaponProfile.self, from: profileData)
        let document = try Data(contentsOf: directory.appendingPathComponent(DuelSerpentAssetIdentity.victoryMorphManifestName))
        XCTAssertEqual(DuelWeaponAssets.digest(document), DuelSerpentAssetIdentity.victoryMorphManifestSHA256)
        return Inputs(directory: directory, owner: owner, target: target, document: document,
            mask: try Data(contentsOf: directory.appendingPathComponent("SF3_H17_MorphMask.texture")))
    }

    private func load(_ input: Inputs, directory: URL? = nil, digest: String? = nil) throws -> DuelTriadSourceMorphAssets {
        try DuelTriadSourceMorphAssets(directory: directory ?? input.directory,
            manifestName: DuelSerpentAssetIdentity.victoryMorphManifestName,
            expectedSHA256: digest ?? DuelSerpentAssetIdentity.victoryMorphManifestSHA256,
            owner: input.owner, target: input.target)
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    func testPinnedD13MorphCoversHelmetArmorWeaponAndBothPersonalMaterials() throws {
        let input = try inputs(), assets = try load(input)
        XCTAssertTrue(DuelTriadSourceMorphAssets.acceptsReviewedTarget(input.target))
        XCTAssertEqual(assets.ownerProfileID, "sun_triad")
        XCTAssertEqual(assets.targetProfileID, "liu_serpent")
        XCTAssertEqual(assets.targetCharacterSHA256, DuelSerpentAssetIdentity.characterSHA256)
        XCTAssertEqual(assets.trigger.clip, "h17_stance_win")
        XCTAssertEqual(assets.trigger.sourceFrame, 36)
        XCTAssertEqual(assets.trigger.triggerTick, 70)
        XCTAssertEqual(assets.trigger.transitionTicks, 140)
        XCTAssertEqual(assets.trigger.normalRenderBoundaries, 1)
        let expected: [String: Int?] = ["mat_arm__agl_41_base": 2, "mat_arm__agl_41_tie_base": 2,
            "mat_helm__agl_41_base": 1, "mat_wpn__shuangou_01_04_base": 3,
            "Liu_Neck_Skin": nil, "tripo_mat_c4757646": nil]
        XCTAssertEqual(Set(assets.materials.map(\.name)), Set(expected.keys))
        for material in assets.materials {
            let type = try XCTUnwrap(expected[material.name])
            XCTAssertEqual(material.sourceItemType, type)
            XCTAssertEqual(material.actorBaseGeometry, type == nil)
            XCTAssertEqual(material.tile, type == 3 ? 0.1 : 0.2, accuracy: 1e-7)
        }
        XCTAssertTrue(assets.verifiedFiles.contains {
            $0.path == DuelSerpentAssetIdentity.victoryMorphManifestName &&
                $0.bytes == 12_479 && $0.sha256 == DuelSerpentAssetIdentity.victoryMorphManifestSHA256
        })
        XCTAssertTrue(assets.verifiedFiles.contains {
            $0.path == "SF3_H17_MorphMask.texture" && $0.bytes == 32_768 &&
                $0.sha256 == "f5572cfbbe87bd2feb2e9aa93843815b0acdf1b71c0dd7ab584df24ce3ede514"
        })
    }

    func testChangedIdentityMissingHelmetWrongItemTypeAndCorruptMaskFailClosed() throws {
        let input = try inputs()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: input.document) as? [String: Any])
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["targetProfileID"] = "liu_hammers" },
            { $0["targetCharacterSHA256"] = "d873864549fd7c7c3f2e9450aba12725c1d488f68ccf5c775ef5e889a4c4fe80" },
            { $0["ownerCharacterSHA256"] = "ce9e1b77c59fa63116af73409173fcd8922f2063ab2e0624534691fa00195ef6" },
            { document in
                var materials = document["materials"] as! [[String: Any]]
                materials.removeAll { $0["name"] as? String == "mat_helm__agl_41_base" }
                document["materials"] = materials
            },
            { document in
                var materials = document["materials"] as! [[String: Any]]
                let index = materials.firstIndex { $0["name"] as? String == "mat_helm__agl_41_base" }!
                materials[index]["sourceItemType"] = 2
                document["materials"] = materials
            },
            { document in
                var materials = document["materials"] as! [[String: Any]]
                let index = materials.firstIndex { $0["name"] as? String == "mat_wpn__shuangou_01_04_base" }!
                materials[index]["name"] = "mat_wpn__hammers_01_01_base"
                document["materials"] = materials
            }
        ]
        try withDirectory { root in
            try input.mask.write(to: root.appendingPathComponent("SF3_H17_MorphMask.texture"))
            for mutate in mutations {
                var document = original; mutate(&document)
                let changed = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
                try changed.write(to: root.appendingPathComponent(DuelSerpentAssetIdentity.victoryMorphManifestName))
                // The supplied digest matches the changed bytes so this checks
                // semantic identity/material rejection beyond the outer pin.
                XCTAssertThrowsError(try load(input, directory: root, digest: DuelWeaponAssets.digest(changed)))
            }
            try input.document.write(to: root.appendingPathComponent(DuelSerpentAssetIdentity.victoryMorphManifestName))
            var corrupt = input.mask; corrupt[0] ^= 1
            try corrupt.write(to: root.appendingPathComponent("SF3_H17_MorphMask.texture"))
            XCTAssertThrowsError(try load(input, directory: root))
        }
    }

    func testActualD13GeometryInstallsCompleteMorphAndRestoresAfterHideAndCancellation() throws {
        let input = try inputs(), assets = try load(input)
        let gpu = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "D13 morph acceptance requires actual Metal")
        let actor = try DuelWeaponCharacterAsset(url: input.directory.appendingPathComponent(input.target.resourceName + ".glb"),
            profile: input.target)
        let instance = actor.model.instantiate()
        XCTAssertEqual(Set(instance.materials.compactMap(\.name)), Set(assets.materials.map(\.name)))
        var geometries: [SCNNode] = []
        instance.root.enumerateChildNodes { node, _ in if node.geometry != nil { geometries.append(node) } }
        XCTAssertEqual(geometries.count, 9)
        let neck = try XCTUnwrap(geometries.first {
            $0.geometry?.materials.contains { $0.name == "Liu_Neck_Skin" } == true
        })
        XCTAssertTrue(try XCTUnwrap(neck.geometry).sources(for: .texcoord).isEmpty,
                      "The existing constant-origin adapter must not invent neck UVs")
        let originalVisibility = geometries.map(\.isHidden)
        let prepared = try assets.prepare(device: gpu)
        let binding = try prepared.install(on: instance, materials: assets.materials)
        try binding.requestHide(sourceTick: 70, transitionTicks: 140)
        try binding.update(sourceTick: 139)
        XCTAssertEqual(binding.progress, 0, "A simulation step cannot replace the source render boundary")
        try binding.didRenderFrame(sourceTick: 139)
        try binding.update(sourceTick: 209)
        XCTAssertEqual(binding.progress, 0.5, accuracy: 1e-6)
        try binding.update(sourceTick: 279)
        XCTAssertTrue(binding.isComplete)
        XCTAssertTrue(geometries.allSatisfy(\.isHidden))
        binding.reset()
        XCTAssertEqual(geometries.map(\.isHidden), originalVisibility)
        XCTAssertEqual(binding.progress, 0)
        try binding.requestHide(sourceTick: 0, transitionTicks: 140)
        try binding.didRenderFrame(sourceTick: 0)
        try binding.update(sourceTick: 70)
        binding.shutdown()
        XCTAssertEqual(geometries.map(\.isHidden), originalVisibility)
        XCTAssertTrue(try XCTUnwrap(neck.geometry).sources(for: .texcoord).isEmpty)
        XCTAssertThrowsError(try binding.requestHide(sourceTick: 140))
    }
}
