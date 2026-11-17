import Foundation
import XCTest
import SceneKit
@testable import ShiftReminder

/// Actual private inputs are staged by the source acceptance job. These tests
/// must not be advertised as a source-only gate or accepted with skips.
@MainActor
final class DuelSerpentBottleSourceTests: XCTestCase {
    private struct Oracle: Decodable {
        struct Sample: Decodable { let root, left, right: [Double] }
        let modelSHA256: String
        let samples: [Sample]
    }
    private func path(_ key: String) throws -> URL {
        if let path = ProcessInfo.processInfo.environment[key] {
            return URL(fileURLWithPath: path)
        }
        let names = ["SERPENT_MATCH_PROFILE": "SF3_Serpent_Profile.json",
                     "ERLANG_MATCH_PROFILE": "SF3_Erlang_Profile.json",
                     "SERPENT_BOTTLE_PRESENTATION_ORACLE": "Validation_D13_Bottle_Source_Oracle.json",
                     "SERPENT_BOTTLE_SOURCE_DIRECTORY": "SF3_D13_Bottle_Source.glb"]
        let name = try XCTUnwrap(names[key], "Unknown private source input")
        let file = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: nil) ??
            Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "FighterPrivate"),
            "The authenticated native resource must be installed: \(name)")
        return key == "SERPENT_BOTTLE_SOURCE_DIRECTORY" ? file.deletingLastPathComponent() : file
    }
    private func profile(_ key: String = "SERPENT_MATCH_PROFILE") throws -> DuelWeaponProfile {
        try JSONDecoder().decode(DuelWeaponProfile.self, from: Data(contentsOf: path(key)))
    }
    private func assets() throws -> DuelSerpentBottleAssets {
        try .init(directory: path("SERPENT_BOTTLE_SOURCE_DIRECTORY"), profile: profile())
    }
    private func fight(direction: Int) throws -> DuelWeaponFight {
        let catalog = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
            sourceFramesPerSecond: 60, profiles: [try profile(), try profile("ERLANG_MATCH_PROFILE")])
        try catalog.validate()
        let x = direction == 1 ? 3500 : 6500
        return try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: .liu, x: x, facing: direction),
            .init(hero: .wuYong, x: x + 1800 * direction, facing: -direction)
        ], mode: .practice, difficulty: .learning, catalog: catalog, seed: 19))
    }

    func testOriginalBottleUsesOneSourceMeshAndPreservesSourceRasterSettings() throws {
        let assets = try assets(), instance = assets.instantiate()
        XCTAssertEqual(assets.verifiedFiles.count, 1)
        XCTAssertEqual(assets.verifiedFiles[0].sha256, "5ccf41b00f10b3e504012a33e8f6212c7935a2ff4ac65b831eedfab2d91626cd")
        XCTAssertEqual(assets.verifiedFiles[0].bytes, 291_180)
        XCTAssertNotNil(instance.root.childNode(withName: "rng__bottle_01_02_l", recursively: true))
        XCTAssertNil(instance.root.childNode(withName: "rng__bottle_01_02_r", recursively: true),
                     "Alternate MirroringDuplicate mesh must not be double-drawn")
        XCTAssertEqual(instance.materials.count, 1)
        let material = try XCTUnwrap(instance.materials.first)
        XCTAssertEqual(material.name, "mat_rng__bottle_01_02_base")
        XCTAssertFalse(material.isDoubleSided)
        XCTAssertEqual(material.cullMode, .back)
        XCTAssertEqual(material.blendMode, .replace)
        XCTAssertTrue(material.writesToDepthBuffer)
        XCTAssertEqual(material.diffuse.minificationFilter, .linear)
        XCTAssertEqual(material.diffuse.magnificationFilter, .linear)
        XCTAssertEqual(material.diffuse.mipFilter, .none)
        XCTAssertEqual(material.diffuse.wrapS, .repeat)
        XCTAssertEqual(material.diffuse.wrapT, .repeat)
        XCTAssertEqual(material.diffuse.maxAnisotropy, 1)
    }

    func testSceneKitPoseMatchesOriginalMotionOracleAndSharesAuthoritativeLifetime() throws {
        let assets = try assets()
        let oracle = try JSONDecoder().decode(Oracle.self,
            from: Data(contentsOf: path("SERPENT_BOTTLE_PRESENTATION_ORACLE")))
        XCTAssertEqual(oracle.modelSHA256, DuelSerpentBottlePresentation.fileSHA256)
        for direction in [-1, 1] {
            let parent = SCNNode()
            let renderer = DuelSerpentBottleRenderer(assets: assets, parent: parent)
            let root = try XCTUnwrap(parent.childNode(withName: "duel.serpent.bottles", recursively: false))
            var fight = try fight(direction: direction)
            renderer.draw(fight)
            XCTAssertTrue(root.childNodes.isEmpty)
            fight.step(.init(weaponCommand: .ranged), opponent: .neutral)
            var firstHolder: SCNNode?
            for tick in 1...56 {
                fight.step(.neutral, opponent: .neutral)
                let replay = try [8, 31, 56].contains(tick) ? DuelReplayStateEncoding.encode(fight) : nil
                renderer.draw(fight)
                guard (8..<56).contains(tick) else {
                    XCTAssertTrue(root.childNodes.isEmpty); continue
                }
                XCTAssertEqual(root.childNodes.count, 1)
                let holder = try XCTUnwrap(root.childNodes.first)
                if let firstHolder { XCTAssertTrue(holder === firstHolder) }
                else { firstHolder = holder }
                let bottle = try XCTUnwrap(fight.serpentRuntime(0)?.bottle)
                let sample = oracle.samples[tick - 8]
                for (name, expected) in [("ranged_root", sample.root), ("gun_joint_l", sample.left),
                                         ("gun_joint_r", sample.right)] {
                    let bone = try XCTUnwrap(holder.childNode(withName: name, recursively: true))
                    let actual = bone.convertPosition(SCNVector3Zero, to: parent)
                    XCTAssertEqual(Double(actual.x), bottle.originX * 0.0092 + expected[0] * 0.92 * Double(direction), accuracy: 0.00002)
                    XCTAssertEqual(Double(actual.y), expected[1] * 0.92, accuracy: 0.00002)
                    XCTAssertEqual(Double(actual.z), expected[2] * 0.92 * Double(direction), accuracy: 0.00002)
                }
                for _ in 0..<3 { renderer.draw(fight) }
                XCTAssertEqual(root.childNodes.count, 1)
                XCTAssertTrue(root.childNodes[0] === holder)
                if let replay { XCTAssertEqual(try DuelReplayStateEncoding.encode(fight), replay) }
            }
            XCTAssertTrue(root.childNodes.isEmpty)
            renderer.reset()
            renderer.shutdown()
            XCTAssertTrue(parent.childNodes.isEmpty)
        }
    }

    func testMissingChangedAndSymlinkBottleBytesAreRejectedBeforeLoading() throws {
        let source = try path("SERPENT_BOTTLE_SOURCE_DIRECTORY")
            .appendingPathComponent(DuelSerpentBottlePresentation.fileName)
        let profile = try profile()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try DuelSerpentBottleAssets(directory: directory, profile: profile))
        let target = directory.appendingPathComponent(DuelSerpentBottlePresentation.fileName)
        var changed = try Data(contentsOf: source)
        changed[changed.count - 1] ^= 1
        try changed.write(to: target)
        XCTAssertThrowsError(try DuelSerpentBottleAssets(directory: directory, profile: profile))
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: source)
        XCTAssertThrowsError(try DuelSerpentBottleAssets(directory: directory, profile: profile))
    }
}
