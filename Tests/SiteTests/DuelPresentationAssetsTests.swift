import XCTest
import SceneKit
import Metal
import AVFoundation
import UIKit
import simd
@testable import ShiftReminder

/// These methods require the authenticated presentation pack and both actual
/// equipped models. A primitive or an absent optional pack cannot pass.
@MainActor
final class DuelPresentationAssetsTests: XCTestCase {
    private final class Player: DuelEffectPlayback {
        var duration: TimeInterval = 1.595
        var currentTime: TimeInterval = 0
        var isPlaying = false
        var starts = 0
        func prepareToPlay() -> Bool { true }
        func play() -> Bool { starts += 1; isPlaying = true; return true }
        func pause() { isPlaying = false }
        func stop() { isPlaying = false }
    }

    func testActualMasksAndEnvironmentMatcapsRenderWithoutChangingSkeletons() throws {
        let assets = try DuelWeaponAssets()
        _ = try XCTUnwrap(assets.presentation, "Stage the authenticated presentation pack")
        var environmentImages: [[UInt8]] = []
        for environment in [DuelPresentationAssets.Environment.palace, .autumn] {
            let scene = SCNScene()
            scene.background.contents = UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
            let camera = SCNNode(); camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 2.1
            camera.camera?.wantsHDR = false; camera.camera?.wantsExposureAdaptation = false
            camera.position = SCNVector3(0, 1.8, 7); camera.look(at: SCNVector3(0, 0.95, 0))
            scene.rootNode.addChildNode(camera)
            let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
            ambient.light?.intensity = 650; scene.rootNode.addChildNode(ambient)
            let key = SCNNode(); key.light = SCNLight(); key.light?.type = .omni
            key.light?.intensity = 1100; key.position = SCNVector3(-3, 4, 4); scene.rootNode.addChildNode(key)
            let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
            renderer.scene = scene; renderer.pointOfView = camera
            defer { renderer.scene = nil; renderer.pointOfView = nil }
            let empty = try capture(renderer).1
            var actors: [DuelWeaponCharacterInstance] = []
            var originalModifiers: [[SCNShaderModifierEntryPoint: String]?] = []
            var sourceMaterials: [SCNMaterial] = []
            for hero in [DuelGame.Hero.ember, .liu] {
                let asset = try assets.character(for: hero)
                let actor = DuelWeaponCharacterInstance(asset, environment: environment)
                XCTAssertEqual(actor.materialBinding?.materialCount, 2)
                let root = SCNNode(); root.addChildNode(actor.instance.root); scene.rootNode.addChildNode(root)
                root.position.x = hero == .ember ? -0.85 : 0.85; root.eulerAngles.y = .pi
                let clip = try XCTUnwrap(asset.profile.clip(role: "idle"))
                actor.apply(.init(clip: clip.name, tick: 0, duration: clip.ticks, groundLift: clip.tracks.lift(phase: 0)))
                actor.materialBinding?.update(viewTransform: simd_inverse(camera.simdWorldTransform))
                for material in actor.instance.materials where material.name?.hasPrefix("mat_arm__") == true || material.name?.hasPrefix("mat_wpn__") == true {
                    XCTAssertEqual(material.lightingModel, .constant)
                    XCTAssertFalse(material.isDoubleSided)
                    XCTAssertEqual(material.cullMode, .back)
                    sourceMaterials.append(material); originalModifiers.append(material.shaderModifiers)
                }
                actors.append(actor)
            }
            let before = actors.map { $0.instance.nodes.map(\.simdTransform) }
            let rendered = try capture(renderer)
            XCTAssertGreaterThan(changed(empty, rendered.1), 5_000, "Both real characters must contribute rendered pixels")
            environmentImages.append(rendered.1)
            let attachment = XCTAttachment(image: rendered.0)
            attachment.name = "fidelity-materials-\(environment.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
            // Same meshes, same camera and source diffuse textures. Removing
            // just the new material composition must visibly change the result.
            for material in sourceMaterials { material.shaderModifiers = nil }
            let baseOnly = try capture(renderer).1
            XCTAssertGreaterThan(changed(baseOnly, rendered.1), 1_000, "A bound but inactive shader is not a material restoration")
            for (index, material) in sourceMaterials.enumerated() { material.shaderModifiers = originalModifiers[index] }
            for (index, actor) in actors.enumerated() {
                XCTAssertEqual(actor.instance.nodes.map(\.simdTransform), before[index], "Material changes must not alter source bone transforms")
            }
        }
        XCTAssertGreaterThan(changed(environmentImages[0], environmentImages[1]), 1_000,
                             "Palace and autumn must retain their distinct source MatCap/light bindings")
    }

    func testCalloutDecodesAndFollowsOneActionThroughPauseCancellationAndRestart() throws {
        let directory = try XCTUnwrap(DuelSourceEffects.manifestURL()).deletingLastPathComponent()
        let data = try XCTUnwrap(DuelPresentationAssets.verifiedVoice(directory: directory))
        let decoded = try AVAudioPlayer(data: data)
        XCTAssertEqual(decoded.duration, 1.595, accuracy: 0.002)
        let voice = Player()
        let effects = try DuelSourceEffects(root: SCNNode(), directory: directory, center: NotificationCenter(), makePlayer: { bytes in
            bytes == data ? voice : Player()
        })
        defer { effects.shutdown() }
        XCTAssertTrue(effects.hasLiuShadowVoice); XCTAssertEqual(effects.sourceAudioCount, 29)
        func step(_ frame: Int, _ shadow: Int?) { effects.consumeStep(contacts: [], swings: [], animationTick: frame, liuShadowTick: shadow) }
        step(1, 18); XCTAssertEqual(voice.starts, 0, "Attaching during a skill must not invent its start")
        step(2, nil); step(3, 0); step(3, 0)
        XCTAssertEqual(voice.starts, 1, "Hit-stop/repeated draws must not restart the shout")
        voice.currentTime = 0.3; effects.setPaused(true)
        step(4, 0); XCTAssertFalse(voice.isPlaying); XCTAssertEqual(voice.starts, 1)
        effects.setPaused(false)
        XCTAssertTrue(voice.isPlaying); XCTAssertEqual(voice.currentTime, 0.3)
        XCTAssertEqual(effects.playedSoundCategories["liuShadow"], 1)
        step(4, 1); step(5, nil)
        XCTAssertFalse(voice.isPlaying); XCTAssertEqual(voice.currentTime, 0)
        step(6, 0); XCTAssertEqual(effects.playedSoundCategories["liuShadow"], 2)
        effects.reset(); XCTAssertFalse(voice.isPlaying)
        step(0, 0); XCTAssertEqual(effects.playedSoundCategories["liuShadow"], 1)
        effects.shutdown(); step(1, 0); XCTAssertFalse(voice.isPlaying)
    }

    func testAlteredMaskAndVoiceAreRejectedBeforeRenderingOrPlayback() throws {
        let source = try DuelWeaponAssets().directory
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for name in [DuelPresentationAssets.manifestName, DuelPresentationAssets.voiceName,
                     "Fidelity_matcap_palace.png", "Fidelity_matcap_autumn.png"] + (0..<4).map({ "Fidelity_mask_\($0).png" }) {
            try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: temporary.appendingPathComponent(name))
        }
        _ = try DuelPresentationAssets(directory: temporary)
        let mask = temporary.appendingPathComponent("Fidelity_mask_0.png")
        var bytes = try Data(contentsOf: mask); bytes[bytes.count / 2] ^= 1; try bytes.write(to: mask)
        XCTAssertThrowsError(try DuelPresentationAssets(directory: temporary))
        let voice = temporary.appendingPathComponent(DuelPresentationAssets.voiceName)
        bytes = try Data(contentsOf: voice); bytes[100] ^= 1; try bytes.write(to: voice)
        XCTAssertThrowsError(try DuelPresentationAssets.verifiedVoice(directory: temporary))
    }

    private func capture(_ renderer: SCNRenderer) throws -> (UIImage, [UInt8]) {
        SCNTransaction.flush()
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1000, height: 700), antialiasingMode: .multisampling2X)
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return (image, bytes)
    }
    private func changed(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return 0 }
        return stride(from: 0, to: a.count, by: 4).reduce(0) { result, index in
            result + ((0..<3).contains { abs(Int(a[index + $0]) - Int(b[index + $0])) > 8 } ? 1 : 0)
        }
    }
}
