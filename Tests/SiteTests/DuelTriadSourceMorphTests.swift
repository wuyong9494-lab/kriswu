import CryptoKit
import Metal
import SceneKit
import UIKit
import XCTest
@testable import ShiftReminder

/// These small textures and meshes are synthetic contract fixtures. No test
/// here is evidence that the private original character pack was installed.
@MainActor
final class DuelTriadSourceMorphTests: XCTestCase {
    private typealias Morph = DuelTriadSourceMorph

    private func device() throws -> MTLDevice {
        try XCTUnwrap(MTLCreateSystemDefaultDevice(), "MORPH acceptance requires actual Metal")
    }
    private func mask(_ data: Data, width: Int = 1, height: Int = 1,
                      format: Int = 4, colorSpace: Int = 0, filter: Int = 1,
                      file: String = "synthetic-morph.texture") -> Morph.Mask {
        .init(file: file, bytes: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            width: width, height: height, sourceTextureFormat: format,
            sourceColorSpace: colorSpace, mip: 1, filter: filter, wrapS: 0, wrapT: 0)
    }
    private func parameters(name: String = "synthetic-body", item: Int? = 2,
                            base: Bool = false, tile: Float = 1, edge: Float = 0.1,
                            start: [Float] = [0, 0, 0, 1],
                            end: [Float] = [0, 0.34, 0.38, 1]) -> Morph.MaterialBinding {
        .init(name: name, sourceItemType: item, actorBaseGeometry: base,
            tile: tile, edgeSize: edge, edgeStart: start, edgeEnd: end)
    }
    private func quad(uv: CGPoint, material: SCNMaterial) -> SCNNode {
        let vertices: [SCNVector3] = [SCNVector3(-1, -1, 0), SCNVector3(1, -1, 0),
            SCNVector3(1, 1, 0), SCNVector3(-1, 1, 0)]
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        let sources = [SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: [SCNVector3](repeating: SCNVector3(0, 0, 1), count: 4)),
            SCNGeometrySource(textureCoordinates: [CGPoint](repeating: uv, count: 4))]
        let geometry = SCNGeometry(sources: sources,
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
    private func fixture(uv: CGPoint = CGPoint(x: 0.25, y: 0.25),
                         color: UIColor = .red) -> GLTFModel.Instance {
        let material = SCNMaterial(); material.name = "synthetic-body"
        material.lightingModel = .constant; material.diffuse.contents = color
        material.readsFromDepthBuffer = true; material.writesToDepthBuffer = true
        material.blendMode = .alpha
        let node = quad(uv: uv, material: material), root = SCNNode()
        root.addChildNode(node)
        return .init(root: root, nodes: [node], materials: [material], outlines: [])
    }
    private func binding(_ instance: GLTFModel.Instance, device: MTLDevice,
                         red: UInt8 = 128, parameters value: Morph.MaterialBinding? = nil) throws -> Morph.Binding {
        let data = Data([red, 0, 0, 255])
        return try Morph.prepare(mask: mask(data), data: data, device: device)
            .install(on: instance, materials: [value ?? parameters()])
    }

    func testMaskRejectsDigestLayoutColorSpaceAndUnsupportedSampler() throws {
        let gpu = try device(), data = Data([0, 0, 0, 255])
        let good = mask(data)
        XCTAssertEqual(try Morph.prepare(mask: good, data: data, device: gpu).texture.pixelFormat, .rgba8Unorm)
        XCTAssertThrowsError(try Morph.prepare(mask: good, data: Data([1, 0, 0, 255]), device: gpu))
        for bad in [mask(data, width: 2), mask(data, width: 1025), mask(data, format: 47),
                    mask(data, colorSpace: 1), mask(data, filter: 0), mask(data, file: "../mask.texture")] {
            XCTAssertThrowsError(try Morph.prepare(mask: bad, data: data, device: gpu))
        }
    }

    func testBindingsRequireCompleteNamesAndHonestBaseGeometryIdentity() throws {
        let gpu = try device(), instance = fixture(), data = Data([0, 0, 0, 255])
        let prepared = try Morph.prepare(mask: mask(data), data: data, device: gpu)
        for invalid in [parameters(item: nil), parameters(item: 3, base: true), parameters(item: 0),
                        parameters(tile: .nan), parameters(edge: 0), parameters(start: [0, 0, 0, 0.5])] {
            XCTAssertThrowsError(try prepared.install(on: instance, materials: [invalid]))
        }
        XCTAssertThrowsError(try prepared.install(on: instance, materials: [parameters(name: "other")]))
        XCTAssertThrowsError(try prepared.install(on: instance, materials: [parameters(), parameters()]))
        XCTAssertNoThrow(try prepared.install(on: instance, materials: [parameters(item: nil, base: true)]))
        instance.materials[0].diffuse.contentsTransform = SCNMatrix4MakeScale(2, 1, 1)
        XCTAssertThrowsError(try prepared.install(on: instance, materials: [parameters()]))
    }

    func testNormalBoundaryThenExactly140TicksCompletesAndRepeatedRequestsDoNotRestart() throws {
        let instance = fixture(), state = try binding(instance, device: device())
        try state.requestHide(sourceTick: 70)
        XCTAssertTrue(state.hasPendingBoundary); XCTAssertEqual(state.progress, 0)
        try state.update(sourceTick: 70); try state.didRenderFrame(sourceTick: 70)
        XCTAssertFalse(state.hasPendingBoundary)
        try state.update(sourceTick: 209)
        XCTAssertEqual(state.progress, Float(139) / 140, accuracy: 1e-6)
        XCTAssertFalse(instance.nodes[0].isHidden)
        try state.requestHide(sourceTick: 70)
        try state.didRenderFrame(sourceTick: 209); try state.update(sourceTick: 209)
        XCTAssertEqual(state.progress, Float(139) / 140, accuracy: 1e-6)
        try state.update(sourceTick: 210)
        XCTAssertTrue(state.isComplete); XCTAssertTrue(instance.nodes[0].isHidden)
        XCTAssertEqual(state.progress, 1); XCTAssertNil(instance.materials[0].shaderModifiers)
    }

    func testNoRenderBoundaryNoProgressAndPauseDoesNotConsumeSourceTime() throws {
        let instance = fixture(), state = try binding(instance, device: device())
        try state.requestHide(sourceTick: 70); try state.update(sourceTick: 170)
        XCTAssertEqual(state.progress, 0); XCTAssertTrue(state.hasPendingBoundary)
        try state.didRenderFrame(sourceTick: 170); try state.update(sourceTick: 240)
        XCTAssertEqual(state.progress, 0.5)
        let cutoff = instance.materials[0].value(forKey: "triadMorphCutoff") as? NSNumber
        for _ in 0..<4 { try state.didRenderFrame(sourceTick: 240); try state.update(sourceTick: 240) }
        XCTAssertEqual(instance.materials[0].value(forKey: "triadMorphCutoff") as? NSNumber, cutoff)
        try state.update(sourceTick: 300, paused: true)
        XCTAssertEqual(state.progress, 0.5)
        try state.update(sourceTick: 369); XCTAssertFalse(state.isComplete)
        try state.update(sourceTick: 370); XCTAssertTrue(state.isComplete)
        XCTAssertThrowsError(try state.update(sourceTick: 369))
    }

    func testResetRestoresModifiersRasterVisibilityAndCanBeginNextRound() throws {
        let instance = fixture(), material = instance.materials[0]
        material.shaderModifiers = [.surface: "#pragma body\n_surface.diffuse.rgb *= 0.75;",
            .fragment: "#pragma body\n_output.color.a *= 1.0;"]
        let original = material.shaderModifiers
        let state = try binding(instance, device: device())
        try state.requestHide(sourceTick: 0); try state.didRenderFrame(sourceTick: 0)
        try state.update(sourceTick: 70)
        XCTAssertEqual(material.blendMode, .replace)
        XCTAssertTrue(material.shaderModifiers?[.surface]?.contains("_surface.diffuse.rgb *= 0.75;") == true)
        state.reset()
        XCTAssertEqual(material.shaderModifiers, original); XCTAssertEqual(material.blendMode, .alpha)
        XCTAssertTrue(material.readsFromDepthBuffer); XCTAssertTrue(material.writesToDepthBuffer)
        XCTAssertFalse(instance.nodes[0].isHidden); XCTAssertEqual(state.progress, 0)
        try state.requestHide(sourceTick: 0); try state.didRenderFrame(sourceTick: 0); try state.update(sourceTick: 140)
        XCTAssertTrue(instance.nodes[0].isHidden)
        state.reset(); XCTAssertFalse(instance.nodes[0].isHidden)
        state.shutdown(); XCTAssertThrowsError(try state.requestHide(sourceTick: 0))
    }

    func testCancellationHasSourceCompletionSemanticsOnlyAfterTweenStarts() throws {
        let instance = fixture(), state = try binding(instance, device: device())
        try state.requestHide(sourceTick: 0); state.cancel()
        XCTAssertFalse(instance.nodes[0].isHidden); XCTAssertFalse(state.isComplete)
        try state.requestHide(sourceTick: 0); try state.didRenderFrame(sourceTick: 0)
        try state.update(sourceTick: 1); state.cancel()
        XCTAssertTrue(state.isComplete); XCTAssertTrue(instance.nodes[0].isHidden)
        XCTAssertNil(instance.materials[0].shaderModifiers)
        state.reset(); XCTAssertFalse(instance.nodes[0].isHidden)
    }

    func testOriginalVIsRestoredBeforeTileAndDiscardDoesNotOccludeBackground() throws {
        let gpu = try device(), scene = SCNScene()
        let left = fixture(uv: CGPoint(x: 0.25, y: 0.25)), right = fixture(uv: CGPoint(x: 0.25, y: 0.75))
        left.root.position.x = -0.6; right.root.position.x = 0.6
        left.root.scale = SCNVector3(0.45, 0.8, 1); right.root.scale = SCNVector3(0.45, 0.8, 1)
        scene.rootNode.addChildNode(left.root); scene.rootNode.addChildNode(right.root)
        // Original row0 is zero, row1 is one; no upload-time image flip.
        let data = Data([0, 0, 0, 255, 0, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255])
        let prepared = try Morph.prepare(mask: mask(data, width: 2, height: 2), data: data, device: gpu)
        let a = try prepared.install(on: left, materials: [parameters()])
        let b = try prepared.install(on: right, materials: [parameters()])
        let background = SCNMaterial(); background.lightingModel = .constant; background.diffuse.contents = UIColor.green
        let back = quad(uv: .zero, material: background); back.position.z = -1
        back.scale = SCNVector3(3, 3, 1); back.renderingOrder = 10; scene.rootNode.addChildNode(back)
        for state in [a, b] {
            try state.requestHide(sourceTick: 0); try state.didRenderFrame(sourceTick: 0); try state.update(sourceTick: 70)
        }
        let harness = try Harness(device: gpu, scene: scene)
        let pixels = try harness.render()
        let l = harness.pixel(pixels, world: SCNVector3(-0.6, 0, 0))
        let r = harness.pixel(pixels, world: SCNVector3(0.6, 0, 0))
        XCTAssertGreaterThan(l.y, 230); XCTAssertLessThan(l.x, 15, "Clipped fragment must not write depth")
        XCTAssertGreaterThan(r.x, 230); XCTAssertLessThan(r.y, 15, "Surviving fragment must remain opaque in front")
        XCTAssertEqual(l.w, 255); XCTAssertEqual(r.w, 255)
    }

    func testGammaEdgeUsesOriginalSmoothstepAndPreservesOpaqueAlphaOnGPU() throws {
        let gpu = try device(), instance = fixture(), scene = SCNScene()
        scene.rootNode.addChildNode(instance.root)
        let end: [Float] = [0.2, 0.6, 0.8, 1]
        let state = try binding(instance, device: gpu, red: 128,
            parameters: parameters(edge: 1, end: end))
        try state.requestHide(sourceTick: 0, transitionTicks: 2)
        try state.didRenderFrame(sourceTick: 0); try state.update(sourceTick: 1)
        let harness = try Harness(device: gpu, scene: scene), pixels = try harness.render()
        let value = harness.pixel(pixels, world: SCNVector3Zero)
        let t = Float(128) / 255, smooth = t * t * (3 - 2 * t)
        for channel in 0..<3 {
            XCTAssertEqual(Float(value[channel]), end[channel] * smooth * 255, accuracy: 3)
        }
        XCTAssertEqual(value.w, 255)
        XCTAssertTrue(instance.materials[0].writesToDepthBuffer)
    }

    func testExactCutoffBoundaryAddsBaseAndEdgeStartInGammaSpaceOnGPU() throws {
        let gpu = try device(), instance = fixture(color: UIColor(red: 0.2, green: 0.1, blue: 0.05, alpha: 1))
        let scene = SCNScene(); scene.rootNode.addChildNode(instance.root)
        let harness = try Harness(device: gpu, scene: scene)
        let before = harness.pixel(try harness.render(), world: SCNVector3Zero)
        let start: [Float] = [0.1, 0.2, 0.3, 1]
        let state = try binding(instance, device: gpu, red: 0,
            parameters: parameters(edge: 1, start: start, end: [0.8, 0.8, 0.8, 1]))
        try state.requestHide(sourceTick: 0, transitionTicks: 2)
        try state.didRenderFrame(sourceTick: 0); try state.update(sourceTick: 1)
        let after = harness.pixel(try harness.render(), world: SCNVector3Zero)
        for channel in 0..<3 {
            XCTAssertEqual(Float(after[channel]), Float(before[channel]) + start[channel] * 255, accuracy: 3)
        }
        XCTAssertEqual(after.w, before.w)
    }

    func testOpaqueShadowPassUsesTheSameDiscardMask() throws {
        let gpu = try device(), scene = SCNScene(), instance = fixture()
        let caster = instance.nodes[0]
        caster.eulerAngles.x = -.pi / 2; caster.position.y = 1
        caster.scale = SCNVector3(0.4, 0.4, 0.4); caster.castsShadow = true
        scene.rootNode.addChildNode(instance.root)
        let floorMaterial = SCNMaterial(); floorMaterial.diffuse.contents = UIColor.white
        floorMaterial.lightingModel = .lambert
        let floor = quad(uv: .zero, material: floorMaterial)
        floor.eulerAngles.x = -.pi / 2; floor.scale = SCNVector3(4, 4, 4); floor.castsShadow = false
        scene.rootNode.addChildNode(floor)
        let light = SCNNode(); light.light = SCNLight(); light.light?.type = .spot
        light.light?.intensity = 1000; light.light?.castsShadow = true; light.light?.shadowMode = .forward
        light.light?.shadowColor = UIColor.black; light.light?.shadowRadius = 0
        light.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        light.light?.spotInnerAngle = 50; light.light?.spotOuterAngle = 70
        light.light?.zNear = 0.1; light.light?.zFar = 30
        light.position = SCNVector3(5, 6, 0); light.look(at: SCNVector3Zero); scene.rootNode.addChildNode(light)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 80; scene.rootNode.addChildNode(ambient)
        let harness = try Harness(device: gpu, scene: scene)
        harness.camera.position = SCNVector3(0, 5, 7); harness.camera.look(at: SCNVector3Zero)
        harness.camera.camera?.orthographicScale = 4
        let opaque = try harness.render()
        caster.isHidden = true
        let absent = try harness.render()
        caster.isHidden = false
        let state = try binding(instance, device: gpu, red: 255)
        try state.requestHide(sourceTick: 0, transitionTicks: 2)
        try state.didRenderFrame(sourceTick: 0); try state.update(sourceTick: 1)
        let clipped = try harness.render()
        let shadowPoint = SCNVector3(-1, 0, 0)
        let a = harness.pixel(opaque, world: shadowPoint), b = harness.pixel(absent, world: shadowPoint)
        let c = harness.pixel(clipped, world: shadowPoint)
        XCTAssertGreaterThan(Int(b.x) - Int(a.x), 15, "Fixture must prove an actual projected shadow")
        for channel in 0..<3 { XCTAssertEqual(Float(c[channel]), Float(b[channel]), accuracy: 3) }
        let error = zip(absent, clipped).map { abs(Int($0.0) - Int($0.1)) }.reduce(0, +)
        XCTAssertLessThan(Double(error) / Double(absent.count), 1)
        XCTAssertFalse(caster.isHidden); XCTAssertTrue(caster.castsShadow)
        XCTAssertFalse(state.isComplete, "This must test shader discard before renderer completion")
    }

    func testCommittedControlledCaptureProvidesOneBoundaryAndShutdownClearsCallback() throws {
        let gpu = try device(), instance = fixture(), scene = SCNScene()
        scene.rootNode.addChildNode(instance.root)
        let state = try binding(instance, device: gpu)
        let packets = try DuelTriadMetalRenderer(device: gpu, formats: DuelTriadRenderSurface.formats(device: gpu))
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.position.z = 5
        scene.rootNode.addChildNode(camera)
        let surface = try DuelTriadRenderSurface(device: gpu, scene: scene, pointOfView: camera, packets: packets)
        defer { surface.shutdown(); packets.shutdown(); state.shutdown() }
        var boundaryErrors: [Error] = [], callbacks = 0
        surface.didSubmitFrame = {
            callbacks += 1
            do { try state.didRenderFrame(sourceTick: 70) } catch { boundaryErrors.append(error) }
        }
        try state.requestHide(sourceTick: 70)
        _ = try surface.captureFrame(tick: 70, pixelSize: CGSize(width: 16, height: 16), samples: 1)
        XCTAssertFalse(state.hasPendingBoundary); XCTAssertEqual(state.progress, 0)
        _ = try surface.captureFrame(tick: 70, pixelSize: CGSize(width: 16, height: 16), samples: 1)
        XCTAssertEqual(callbacks, 2); XCTAssertEqual(state.progress, 0); XCTAssertTrue(boundaryErrors.isEmpty)
        try state.update(sourceTick: 71); XCTAssertEqual(state.progress, Float(1) / 140, accuracy: 1e-6)
        surface.shutdown(); XCTAssertNil(surface.didSubmitFrame)
    }

    @MainActor private final class Harness {
        let device: MTLDevice, renderer: SCNRenderer, queue: MTLCommandQueue, camera: SCNNode
        let size = 96
        private var tick = 0
        init(device: MTLDevice, scene: SCNScene) throws {
            self.device = device; queue = try XCTUnwrap(device.makeCommandQueue())
            renderer = SCNRenderer(device: device, options: nil)
            renderer.scene = scene; renderer.usesReverseZ = false; renderer.autoenablesDefaultLighting = false
            camera = SCNNode(); camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 1.5
            camera.camera?.wantsHDR = false; camera.camera?.wantsExposureAdaptation = false
            camera.camera?.zNear = 0.1; camera.camera?.zFar = 50
            camera.position = SCNVector3(0, 0, 5)
            scene.rootNode.addChildNode(camera); renderer.pointOfView = camera
        }
        func render() throws -> [UInt8] {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb,
                width: size, height: size, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead]
            let color = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
            let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                width: size, height: size, mipmapped: false)
            depthDescriptor.storageMode = .private; depthDescriptor.usage = .renderTarget
            let depth = try XCTUnwrap(device.makeTexture(descriptor: depthDescriptor))
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = color; pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            pass.depthAttachment.texture = depth; pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = .store; pass.depthAttachment.clearDepth = 1
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            SCNTransaction.flush()
            renderer.render(atTime: Double(tick) / 60, viewport: CGRect(x: 0, y: 0, width: size, height: size),
                commandBuffer: command, passDescriptor: pass)
            tick += 1; command.commit(); command.waitUntilCompleted()
            XCTAssertEqual(command.status, .completed, String(describing: command.error))
            var bytes = [UInt8](repeating: 0, count: size * size * 4)
            bytes.withUnsafeMutableBytes {
                color.getBytes($0.baseAddress!, bytesPerRow: size * 4,
                    from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
            }
            return bytes
        }
        func pixel(_ bytes: [UInt8], world: SCNVector3) -> SIMD4<UInt8> {
            let projected = renderer.projectPoint(world)
            let x = min(size - 1, max(0, Int(projected.x)))
            let y = min(size - 1, max(0, size - 1 - Int(projected.y)))
            let offset = (y * size + x) * 4
            return SIMD4(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
        }
    }
}
