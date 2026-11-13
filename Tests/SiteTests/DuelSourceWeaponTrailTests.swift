import XCTest
import SceneKit
import Metal
import simd
@testable import ShiftReminder

@MainActor
final class DuelSourceWeaponTrailTests: XCTestCase {
    func testOriginalSkinBindingsRenderBothFacingsAndRemainFrozen() throws {
        let assets = try DuelWeaponAssets()
        let source = try XCTUnwrap(assets.sourceTrails, "Require the actual new encrypted source-skin pack")
        XCTAssertEqual(source.profiles.flatMap(\.meshes).map { $0.positions.count / 3 }.sorted(), [12, 12, 32, 32])
        for hero in [DuelGame.Hero.ember, .liu] {
            let asset = try assets.character(for: hero)
            let actor = DuelWeaponCharacterInstance(asset)
            let binding = try XCTUnwrap(actor.sourceTrailBinding)
            XCTAssertEqual(binding.holders.count, hero == .ember ? 1 : 2)
            let reference = try XCTUnwrap(source.profiles.first { $0.id == asset.profile.id })
            XCTAssertEqual(reference.characterSHA256, asset.profile.sha256)
            for holder in binding.holders {
                let mesh = try XCTUnwrap(reference.meshes.first { $0.name == holder.name })
                let skin = try XCTUnwrap(holder.skinner)
                XCTAssertEqual(skin.bones.map(\.name), mesh.bones.map(Optional.some))
                XCTAssertEqual(skin.bones.count, 4)
                XCTAssertEqual(skin.baseGeometry?.sources(for: .vertex).first?.vectorCount, mesh.positions.count / 3)
                XCTAssertEqual(skin.baseGeometry?.elements.first?.primitiveCount, mesh.indices.count / 3)
                XCTAssertEqual(skin.boneInverseBindTransforms?.count, 4)
                for (bone, name) in zip(skin.bones, mesh.bones) {
                    let index = try XCTUnwrap(asset.model.node(named: name))
                    XCTAssertTrue(bone === actor.instance.nodes[index], "Bind the existing animated skeleton, not a clone")
                }
            }
            let scene = SCNScene(); scene.background.contents = UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1)
            let root = SCNNode(); root.addChildNode(actor.instance.root); scene.rootNode.addChildNode(root)
            let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true
            camera.camera?.orthographicScale = 1.65; camera.camera?.wantsHDR = false
            camera.camera?.wantsExposureAdaptation = false; camera.position = SCNVector3(0, 1.2, 5)
            camera.look(at: SCNVector3(0, 1.2, 0)); scene.rootNode.addChildNode(camera)
            let light = SCNNode(); light.light = SCNLight(); light.light?.type = .ambient; light.light?.intensity = 500
            scene.rootNode.addChildNode(light)
            let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
            renderer.scene = scene; renderer.pointOfView = camera
            defer { renderer.scene = nil; renderer.pointOfView = nil }
            for (role, frame) in [("weapon1", hero == .ember ? 13 : 16), ("heavy", hero == .ember ? 17 : 24)] {
                let clip = try XCTUnwrap(asset.profile.clip(role: role))
                XCTAssertTrue(binding.supports(clip.name))
                for facing in [1, -1] {
                    var fighter = DuelGame(hero: hero).fighters[0]
                    fighter.x = 0; fighter.facing = facing
                    let tick = frame * 2
                    fighter.weaponPose = .init(clip: clip.name, tick: tick, duration: clip.ticks,
                                              groundLift: clip.tracks.lift(phase: clip.phase(at: tick)))
                    actor.pose(fighter, root: root)
                    binding.update(clip: clip.name, active: true)
                    XCTAssertFalse(binding.root.isHidden)
                    let frozen = binding.holders.flatMap { $0.skinner?.bones ?? [] }.map(\.simdWorldTransform)
                    let withSkin = try capture(renderer, name: "source-skin-\(hero.rawValue)-\(role)-\(facing > 0 ? "positive" : "negative")")
                    binding.root.isHidden = true
                    let withoutSkin = try capture(renderer)
                    binding.root.isHidden = false
                    XCTAssertGreaterThan(changedPixels(withSkin, withoutSkin), 20, "The original GPU skin must contribute pixels in both facings")
                    actor.pose(fighter, root: root)
                    XCTAssertEqual(binding.holders.flatMap { $0.skinner?.bones ?? [] }.map(\.simdWorldTransform), frozen)
                    binding.update(clip: clip.name, active: false)
                    XCTAssertTrue(binding.root.isHidden)
                }
            }
            binding.update(clip: "unavailable-source-track", active: true)
            XCTAssertTrue(binding.root.isHidden)
            XCTAssertFalse(binding.supports("unavailable-source-track"))
        }
    }

    private func capture(_ renderer: SCNRenderer, name: String? = nil) throws -> [UInt8] {
        SCNTransaction.flush()
        let width = 956, height = 440
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: CGFloat(width), height: CGFloat(height)), antialiasingMode: .multisampling2X)
        if let name {
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }
    private func changedPixels(_ a: [UInt8], _ b: [UInt8]) -> Int {
        stride(from: 0, to: min(a.count, b.count), by: 4).filter { index in
            (0..<3).contains { abs(Int(a[index + $0]) - Int(b[index + $0])) > 4 }
        }.count
    }
}
