import XCTest
import SceneKit
import UIKit
import Metal
@testable import ShiftReminder

/// This suite renders the actual hash-bound source textures. No skip and no
/// generated artwork can substitute for a missing private feedback pack.
@MainActor
final class DuelWeaponEffectsTests: XCTestCase {
    func testSourceWeaponTrailsRenderAtRealEndpointsAndFreezeAndRelease() throws {
        _ = try XCTUnwrap(DuelWeaponEffects.manifestURL(), "Stage original SF3WE resources")
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.035, green: 0.045, blue: 0.065, alpha: 1)
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 2
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 20
        camera.camera?.wantsHDR = false; camera.camera?.wantsExposureAdaptation = false
        camera.position = SCNVector3(0, 0, 4); scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        var effects: DuelWeaponEffects? = try DuelWeaponEffects(root: scene.rootNode)
        weak var weakEffects = effects
        defer { effects?.shutdown(); renderer.scene = nil; renderer.pointOfView = nil }
        XCTAssertEqual(effects?.sourceTextureCount, 11)
        let empty = try pixels(renderer, atTime: 0)

        effects?.consumeStep(poses: [pose(tick: 0, family: .katana, active: false)], animationTick: 0)
        XCTAssertEqual(effects?.retainedTrailCount, 0)
        effects?.consumeStep(poses: [pose(tick: 1, family: .katana)], animationTick: 1)
        XCTAssertEqual(effects?.renderedVertexCount, 4, "The prior real idle pose must seed the first active sweep")
        let first = try pixels(renderer, atTime: 1, name: "source-katana-first-active-step")
        XCTAssertGreaterThan(changed(empty, first), 20, "First contact hit-stop must freeze a visible weapon sweep")
        for tick in 2...5 { effects?.consumeStep(poses: [pose(tick: tick, family: .katana)], animationTick: tick) }
        XCTAssertEqual(effects?.retainedTrailCount, 1)
        let katana = try pixels(renderer, atTime: 5, name: "source-katana-original-material")
        XCTAssertGreaterThan(changed(empty, katana), 80)
        let container = try XCTUnwrap(scene.rootNode.childNode(withName: "duel.weapon-effects", recursively: false))
        let frozen = geometryState(container)
        let count = effects?.emittedSampleCount
        // Changing wall time and supplying another pose at the same visual
        // tick cannot scroll noise or add interpolated/extra trail vertices.
        effects?.consumeStep(poses: [pose(tick: 20, family: .katana)], animationTick: 5)
        XCTAssertEqual(geometryState(container), frozen)
        XCTAssertEqual(effects?.emittedSampleCount, count)
        XCTAssertLessThanOrEqual(maximumDelta(katana, try pixels(renderer, atTime: 105)), 1)
        effects?.setPaused(true)
        effects?.consumeStep(poses: [], animationTick: 90)
        XCTAssertEqual(geometryState(container), frozen)
        effects?.setPaused(false)
        effects?.consumeStep(poses: [pose(tick: 6, family: .katana)], animationTick: 6)
        XCTAssertNotEqual(geometryState(container), frozen)
        effects?.consumeStep(poses: [], animationTick: 60)
        XCTAssertEqual(effects?.retainedTrailCount, 0)
        XCTAssertEqual(effects?.renderedVertexCount, 0)
        XCTAssertTrue(container.childNodes.isEmpty)

        effects?.reset()
        for tick in 0...5 {
            effects?.consumeStep(poses: [pose(tick: tick, family: .dualHammers, active: tick > 0)], animationTick: tick)
        }
        XCTAssertEqual(effects?.retainedTrailCount, 2, "Each physical hammer needs an independent history")
        let hammers = try pixels(renderer, atTime: 106, name: "source-double-hammer-original-material")
        XCTAssertGreaterThan(changed(empty, hammers), 80)
        XCTAssertGreaterThan(changed(katana, hammers), 80)

        effects?.reset()
        for tick in 0...25 {
            effects?.consumeStep(poses: [pose(tick: tick, family: .katana, active: tick > 0, shadow: true)], animationTick: tick)
        }
        XCTAssertEqual(container.childNodes.first?.childNodes.count, 2, "Katana dash has distinct source glow and scrolling noise layers")
        let dash = try pixels(renderer, atTime: 107, name: "source-katana-dash-two-materials")
        XCTAssertGreaterThan(changed(empty, dash), 80)
        let frozenDash = geometryState(container)
        effects?.consumeStep(poses: [pose(tick: 26, family: .katana, shadow: true)], animationTick: 25)
        XCTAssertEqual(geometryState(container), frozenDash)
        XCTAssertLessThanOrEqual(maximumDelta(dash, try pixels(renderer, atTime: 307)), 1,
                                 "Shadow shader noise must use simulation time, never renderer wall time")
        effects?.consumeStep(poses: [], animationTick: 90)
        XCTAssertEqual(effects?.retainedTrailCount, 0)

        effects?.reset()
        for tick in 0...6 {
            effects?.consumeStep(poses: [pose(tick: tick, family: .dualHammers, active: tick > 0, shadow: true)], animationTick: tick)
        }
        let shadowHammers = try pixels(renderer, atTime: 308, name: "source-hammer-smooth-trail-material")
        XCTAssertGreaterThan(changed(empty, shadowHammers), 20)
        XCTAssertGreaterThan(changed(hammers, shadowHammers), 30)

        // Rapid action changes stay bounded and never join two unrelated
        // motions into one long strip across an input transition.
        for tick in 7...30 {
            effects?.consumeStep(poses: [pose(tick: tick, family: .katana, shadow: true, action: "action.\(tick)")], animationTick: tick)
        }
        XCTAssertLessThanOrEqual(effects?.retainedTrailCount ?? 99, 16)
        effects?.setPaused(true); effects?.reset()
        XCTAssertEqual(effects?.emittedSampleCount, 0)
        XCTAssertTrue(container.childNodes.isEmpty)
        effects?.setPaused(false)
        effects?.consumeStep(poses: [pose(tick: 0, family: .katana, active: false)], animationTick: 0)
        effects?.consumeStep(poses: [pose(tick: 1, family: .katana)], animationTick: 1)
        weak var finalRoot = container.childNodes.first
        effects?.shutdown()
        SCNTransaction.flush()
        XCTAssertNil(finalRoot, "Closing must release an unrendered final trail subtree")
        XCTAssertNil(container.parent)
        XCTAssertEqual(effects?.sourceTextureCount, 0)
        effects?.consumeStep(poses: [pose(tick: 2, family: .katana)], animationTick: 2)
        XCTAssertEqual(effects?.retainedTrailCount, 0)
        effects = nil; XCTAssertNil(weakEffects)
    }

    func testWeaponTextureIntegrityFailureCannotUseAnotherBundleCopy() throws {
        let source = try XCTUnwrap(DuelWeaponEffects.manifestURL())
        let data = try Data(contentsOf: source)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        try data.write(to: folder.appendingPathComponent(DuelWeaponEffects.manifestName))
        let definition = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let records = try XCTUnwrap(definition["files"] as? [[String: Any]])
        let name = try XCTUnwrap(records.first?["name"] as? String)
        var bytes = try Data(contentsOf: source.deletingLastPathComponent().appendingPathComponent(name))
        bytes[bytes.count - 1] ^= 1; try bytes.write(to: folder.appendingPathComponent(name))
        let root = SCNNode()
        XCTAssertThrowsError(try DuelWeaponEffects(root: root, directory: folder)) { error in
            guard case DuelWeaponEffects.Failure.resource(let file) = error else { return XCTFail("Unexpected integrity error: \(error)") }
            XCTAssertEqual(file, name)
        }
        XCTAssertTrue(root.childNodes.isEmpty, "Failed loading must not attach a partial renderer")
    }

    private func pose(tick: Int, family: DuelWeaponEffects.Family, active: Bool = true,
                      shadow: Bool = false, action: String = "attack.1") -> DuelWeaponEffects.Pose {
        let angle = Double(tick) * 0.23 - 0.8
        func endpoint(slot: Int, center: Float, offset: Double) -> DuelWeaponEffects.Endpoints {
            let length: Float = family == .katana ? 1.15 : 0.7
            let base = SCNVector3(center, -0.35, 0)
            return .init(slot: slot, base: base, tip: SCNVector3(base.x + Float(cos(angle + offset)) * length,
                                                               base.y + Float(sin(angle + offset)) * length, 0))
        }
        let endpoints = family == .katana ? [endpoint(slot: 0, center: -0.35, offset: 0)] :
            [endpoint(slot: 0, center: -0.65, offset: 0), endpoint(slot: 1, center: 0.65, offset: .pi)]
        return .init(fighterID: 0, family: family, motionID: active ? action : nil, isShadow: shadow, endpoints: endpoints)
    }

    private func geometryState(_ root: SCNNode) -> [Data] {
        root.childNodes.flatMap { trail in
            trail.childNodes.flatMap { node -> [Data] in
                guard let geometry = node.geometry else { return [] }
                let time = (geometry.firstMaterial?.value(forKey: "sourceTime") as? NSNumber)?.doubleValue ?? -1
                return geometry.sources.map(\.data) + geometry.elements.map(\.data) + [Data(String(time).utf8)]
            }
        }
    }
    private func pixels(_ renderer: SCNRenderer, atTime: Double, name: String? = nil) throws -> [UInt8] {
        SCNTransaction.flush()
        let side = 256
        let image = renderer.snapshot(atTime: atTime, with: CGSize(width: CGFloat(side), height: CGFloat(side)), antialiasingMode: .multisampling2X)
        if let name { let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment) }
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
        }
        return bytes
    }
    private func changed(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return 0 }
        return stride(from: 0, to: a.count, by: 4).filter { i in (0..<3).contains { abs(Int(a[i + $0]) - Int(b[i + $0])) > 4 } }.count
    }
    private func maximumDelta(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return 255 }
        return zip(a, b).map { abs(Int($0.0) - Int($0.1)) }.max() ?? 0
    }
}
