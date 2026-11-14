import Foundation
import Metal
import SceneKit
import UIKit
import XCTest
import simd
@testable import ShiftReminder

/// Entirely synthetic camera, geometry, skins and colors. These tests exercise
/// real Metal without installing, embedding or claiming original game media.
@MainActor
final class DuelProjectedShadowFixture {
    typealias Definition = DuelSourceProjectedShadowDefinition
    typealias Renderer = DuelSourceProjectedShadowRenderer
    let device: MTLDevice
    let queue: MTLCommandQueue
    let definition: Definition
    let stageRoot: SCNNode
    let actors: [GLTFModel.Instance]
    let format: Renderer.Format
    var centers = [SIMD3<Float>.zero, SIMD3<Float>.zero]
    var factors: [Float] = [0, 0]
    var extra: [GLTFModel.Instance] = []
    private(set) var renderer: Renderer!

    static func definition(rotation: [Float] = [0, 0, 0], width: Int = 64) -> Definition {
        let identity: [Float] = [0, 0, 0, 1], zero: [Float] = [0, 0, 0], one: [Float] = [1, 1, 1]
        let digest = String(repeating: "0", count: 64)
        let leaf = Definition.Transform(nodeIndex: 1, name: "synthetic_receiver",
            translation: zero, rotation: identity, scale: one)
        let root = Definition.Transform(nodeIndex: 0, name: "synthetic_stage",
            translation: zero, rotation: identity, scale: one)
        return Definition(complete: true,
            stage: .init(file: "synthetic-stage.glb", bytes: 1, sha256: digest,
                rootNode: root.name, rootTranslation: zero, rootScale: one),
            receiver: .init(node: leaf.name, nodeIndex: leaf.nodeIndex, ancestorChain: [leaf, root],
                geometry: .init(positions: [[-2, -2, 0], [2, -2, 0], [2, 2, 0], [-2, 2, 0]],
                    indices: [0, 1, 2, 0, 2, 3]),
                sourceMeshSHA256: digest, sourceMaterialSHA256: digest, renderQueue: 2501),
            settings: .init(useAdaptiveShadowScale: false, targetTextureFill: 0.64,
                minCameraSize: 2, cinematic: false, useDynamicPositionBetweenPlayerAndEnemy: true),
            sourceLocation: .init(projectorPosition: zero, projectorRotationDegrees: rotation,
                shadowColor: [0.2, 0.4, 0.6, 0.35]),
            camera: .init(orthographic: true, orthographicSize: 2, nearClip: 0.1, farClip: 20,
                targetDistance: 10,
                projectionBiasColumnMajor: [0.5, 0, 0, 0, 0, 0.5, 0, 0, 0, 0, 0.5, 0, 0.5, 0.5, 0.5, 0.5],
                dividesProjectedUVByW: false, halfProjectionRows: true, halfProjectedUV: true,
                follow: .init(source: "actorCenterOfMassWorldXYZ", midpoint: true,
                    positionUsesPreviousForward: true, rotationAfterPosition: true,
                    initialRotationQuaternion: identity), aspectSource: "screen"),
            map: .init(width: width, height: width, sourceFormatPriority: ["R8", "RGB565", "ARGB32"],
                depthBits: 0, sampleCount: 1, filter: 1, wrapS: 1, wrapT: 1,
                clearColor: [1, 1, 1, 1], projectColorSpace: 0,
                drawOrder: ["firstActor", "secondActor", "additionalModels", "extraRenderers"]),
            blur: .init(passes: 1, offsets: [[-1, 1], [-0.8, -0.8], [0, 0], [0.8, 0.8], [1, -1]],
                weights: [0.2, 0.2, 0.2, 0.2, 0.2], sampleChannel: "red", replicateRedToRGBA: true),
            raster: .init(source: 2, destination: 0, zWrite: false, zTest: 4, cull: 2),
            evidence: ["Synthetic contract fixture only; no original scene, models, texture, shader or private bundle is present."])
    }

    static func stage(_ definition: Definition) -> SCNNode {
        let root = SCNNode(); root.name = definition.stage.rootNode
        var current = root
        for (index, entry) in definition.receiver.ancestorChain.reversed().enumerated() {
            if index > 0 { let next = SCNNode(); current.addChildNode(next); current = next }
            current.name = entry.name
            current.simdPosition = SIMD3(entry.translation[0], entry.translation[1], entry.translation[2])
            current.simdScale = SIMD3(entry.scale[0], entry.scale[1], entry.scale[2])
            current.simdOrientation = simd_quatf(vector: SIMD4(entry.rotation[0], entry.rotation[1], entry.rotation[2], entry.rotation[3]))
        }
        return root
    }

    static func actor(name: String = "synthetic_actor", halfSize: Float = 0.45,
                      uv: CGPoint = CGPoint(x: 0.25, y: 0.25), varyingUV: Bool = false) -> GLTFModel.Instance {
        let material = SCNMaterial(); material.name = "synthetic-body"
        material.lightingModel = .constant; material.diffuse.contents = UIColor.red
        material.readsFromDepthBuffer = true; material.writesToDepthBuffer = true
        let p: [SCNVector3] = [SCNVector3(-halfSize, -halfSize, 0), SCNVector3(halfSize, -halfSize, 0),
            SCNVector3(halfSize, halfSize, 0), SCNVector3(-halfSize, halfSize, 0)]
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        let uvs: [CGPoint] = varyingUV ? [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1),
            CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)] : [CGPoint](repeating: uv, count: 4)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: p),
            SCNGeometrySource(normals: [SCNVector3](repeating: SCNVector3(0, 0, 1), count: 4)),
            SCNGeometrySource(textureCoordinates: uvs)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        let root = SCNNode(), holder = SCNNode(geometry: geometry), bone = SCNNode()
        root.name = name; holder.name = name + "_mesh"; bone.name = name + "_bone"
        root.addChildNode(bone); root.addChildNode(holder)
        let weights: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
        let joints = [UInt16](repeating: 0, count: 16)
        let wd = weights.withUnsafeBytes { Data($0) }, jd = joints.withUnsafeBytes { Data($0) }
        let ws = SCNGeometrySource(data: wd, semantic: .boneWeights, vectorCount: 4,
            usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let js = SCNGeometrySource(data: jd, semantic: .boneIndices, vectorCount: 4,
            usesFloatComponents: false, componentsPerVector: 4, bytesPerComponent: 2, dataOffset: 0, dataStride: 8)
        holder.skinner = SCNSkinner(baseGeometry: geometry, bones: [bone],
            boneInverseBindTransforms: [NSValue(scnMatrix4: SCNMatrix4Identity)], boneWeights: ws, boneIndices: js)
        holder.skinner?.skeleton = bone; holder.castsShadow = true
        return .init(root: root, nodes: [holder, bone], materials: [material], outlines: [])
    }

    init(device: MTLDevice, definition: Definition? = nil,
         actors: [GLTFModel.Instance]? = nil, formats: [Renderer.Format]? = nil) throws {
        let definition = definition ?? Self.definition()
        self.device = device; self.definition = definition
        self.queue = try XCTUnwrap(device.makeCommandQueue())
        self.stageRoot = Self.stage(definition)
        self.actors = actors ?? [Self.actor(name: "first"), Self.actor(name: "second")]
        self.format = formats?.first ?? .init(color: .rgba8Unorm, depth: .depth32Float, stencil: .invalid, samples: 1)
        self.renderer = try Renderer(device: device, formats: formats ?? [format], definition: definition,
            stageRoot: stageRoot, actors: self.actors,
            worldCenters: { [weak self] in
                guard let self else { throw Renderer.Failure.geometry }; return self.centers
            }, fade: { [weak self] in self?.factors[$0] ?? .nan }, additionalModels: { [weak self] in self?.extra ?? [] })
        XCTAssertEqual(renderer.rawMap.pixelFormat, .r8Unorm, "The tested Apple device must support the source's first-choice R8 target")
    }

    func command() throws -> MTLCommandBuffer { try XCTUnwrap(queue.makeCommandBuffer()) }
    func finish(_ command: MTLCommandBuffer) throws {
        command.commit(); command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed, String(describing: command.error))
        if command.status != .completed { throw Renderer.Failure.shader(String(describing: command.error)) }
    }
    func readback(_ texture: MTLTexture, on command: MTLCommandBuffer,
                  bytesPerPixel: Int) throws -> (MTLBuffer, Int) {
        let row = ((texture.width * bytesPerPixel + 255) / 256) * 256
        let buffer = try XCTUnwrap(device.makeBuffer(length: row * texture.height, options: .storageModeShared))
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
            destinationOffset: 0, destinationBytesPerRow: row, destinationBytesPerImage: row * texture.height)
        blit.endEncoding(); return (buffer, row)
    }
    func bytes(_ readback: (MTLBuffer, Int), width: Int, height: Int, components: Int) -> [UInt8] {
        let pointer = readback.0.contents().assumingMemoryBound(to: UInt8.self)
        return (0..<height).flatMap { y in Array(UnsafeBufferPointer(start: pointer + y * readback.1, count: width * components)) }
    }
    func map(tick: Int, viewport: CGSize = CGSize(width: 64, height: 64), blurred: Bool = false) throws -> [UInt8] {
        let command = try command()
        try renderer.encodeMap(on: command, viewportSize: viewport, tick: tick)
        let texture = blurred ? renderer.blurredMap : renderer.rawMap
        let result = try readback(texture, on: command, bytesPerPixel: 1)
        try finish(command)
        return bytes(result, width: texture.width, height: texture.height, components: 1)
    }
    func uploadRaw(_ pixels: [UInt8], on command: MTLCommandBuffer) throws {
        let texture = renderer.rawMap
        guard pixels.count == texture.width * texture.height else { throw Renderer.Failure.geometry }
        let row = ((texture.width + 255) / 256) * 256
        var padded = [UInt8](repeating: 0, count: row * texture.height)
        for y in 0..<texture.height { padded.replaceSubrange(y * row..<(y * row + texture.width), with: pixels[y * texture.width..<(y + 1) * texture.width]) }
        let buffer = try XCTUnwrap(padded.withUnsafeBytes { p in
            p.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: p.count, options: .storageModeShared) }
        })
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(from: buffer, sourceOffset: 0, sourceBytesPerRow: row, sourceBytesPerImage: row * texture.height,
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: texture,
            destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
    }

    func receiver(tick: Int, constantMap: UInt8? = nil, depthClear: Double = 1,
                  drawBehind: Bool = false) throws -> [UInt8] {
        let command = try command(), width = 64, height = 64
        try renderer.encodeMap(on: command, viewportSize: CGSize(width: width, height: height), tick: tick)
        if let constantMap {
            try uploadRaw([UInt8](repeating: constantMap, count: definition.map.width * definition.map.height), on: command)
            try renderer.encodeBlur(on: command)
        }
        let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format.color, width: width, height: height, mipmapped: false)
        cd.storageMode = .private; cd.usage = .renderTarget
        let color = try XCTUnwrap(device.makeTexture(descriptor: cd))
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format.depth, width: width, height: height, mipmapped: false)
        dd.storageMode = .private; dd.usage = .renderTarget
        let depth = try XCTUnwrap(device.makeTexture(descriptor: dd))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color; pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store; pass.colorAttachments[0].clearColor = MTLClearColorMake(0.8, 0.6, 0.4, 1)
        pass.depthAttachment.texture = depth; pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store; pass.depthAttachment.clearDepth = depthClear
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
        // Explicit synthetic Metal projection: world x/y +/-2 fill the target.
        // This kernel test does not infer SceneKit's orthographicScale units.
        let near: Float = 0.1, far: Float = 20
        let projection = simd_float4x4(columns: (SIMD4<Float>(0.5, 0, 0, 0), SIMD4<Float>(0, 0.5, 0, 0),
            SIMD4<Float>(0, 0, -1 / (far - near), 0), SIMD4<Float>(0, 0, -near / (far - near), 1)))
        var view = matrix_identity_float4x4; view.columns.3.z = -5
        try renderer.encodeReceiver(on: encoder, format: format,
            cameraProjection: projection,
            cameraView: view, viewport: MTLViewport(originX: 0, originY: 0, width: 64, height: 64, znear: 0, zfar: 1))
        if drawBehind { try overlay(on: encoder) }
        encoder.endEncoding()
        let result = try readback(color, on: command, bytesPerPixel: 4)
        try finish(command); return bytes(result, width: width, height: height, components: 4)
    }
    private func overlay(on encoder: MTLRenderCommandEncoder) throws {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float4 p [[position]]; };
        vertex V behind(uint i [[vertex_id]]) {
            const float2 p[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)};
            V o; o.p=float4(p[i],0.99,1); return o;
        }
        fragment half4 blue() { return half4(0,0,1,1); }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "behind")
        descriptor.fragmentFunction = library.makeFunction(name: "blue")
        descriptor.colorAttachments[0].pixelFormat = format.color; descriptor.depthAttachmentPixelFormat = format.depth
        encoder.setRenderPipelineState(try device.makeRenderPipelineState(descriptor: descriptor))
        let ds = MTLDepthStencilDescriptor(); ds.depthCompareFunction = .lessEqual; ds.isDepthWriteEnabled = true
        encoder.setDepthStencilState(try XCTUnwrap(device.makeDepthStencilState(descriptor: ds)))
        encoder.setCullMode(.none); encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
    func rgba(_ bytes: [UInt8], x: Int = 32, y: Int = 32) -> SIMD4<UInt8> {
        let i = (y * 64 + x) * 4
        return SIMD4(bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }
}

@MainActor
final class DuelSourceProjectedShadowRendererTests: XCTestCase {
    private typealias Fixture = DuelProjectedShadowFixture
    private typealias Renderer = DuelSourceProjectedShadowRenderer
    private func device() throws -> MTLDevice {
        try XCTUnwrap(MTLCreateSystemDefaultDevice(), "Original projector acceptance requires a real Metal device")
    }
    private func changed(_ original: Fixture.Definition, section: String, field: String, value: Any) throws -> Fixture.Definition {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var fields = try XCTUnwrap(object[section] as? [String: Any]); fields[field] = value; object[section] = fields
        return try JSONDecoder().decode(Fixture.Definition.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testDefinitionRejectsUnknownProjectionSamplerBlendAndFakeProductionIdentity() throws {
        let good = Fixture.definition(); try good.validate()
        XCTAssertThrowsError(try good.validatePalaceSource(), "Synthetic geometry must never count as original Palace acceptance")
        for invalid in [try changed(good, section: "map", field: "depthBits", value: 16),
                        try changed(good, section: "map", field: "filter", value: 0),
                        try changed(good, section: "map", field: "wrapS", value: 0),
                        try changed(good, section: "blur", field: "passes", value: 2),
                        try changed(good, section: "camera", field: "dividesProjectedUVByW", value: true),
                        try changed(good, section: "camera", field: "aspectSource", value: "squareMap"),
                        try changed(good, section: "raster", field: "source", value: 5),
                        try changed(good, section: "raster", field: "zWrite", value: true)] {
            XCTAssertThrowsError(try invalid.validate())
        }
    }

    func testStageAndSkinValidationPrecedeFlagChangesAndExcludeSeparateTrails() throws {
        let gpu = try device(), definition = Fixture.definition(), stage = Fixture.stage(definition)
        let a = Fixture.actor(), b = Fixture.actor(name: "other")
        let formats = [Renderer.Format(color: .rgba8Unorm, depth: .depth32Float, stencil: .invalid, samples: 1)]
        func create() throws -> Renderer {
            try Renderer(device: gpu, formats: formats, definition: definition, stageRoot: stage,
                actors: [a, b], worldCenters: { [.zero, .zero] }, fade: { _ in 0 })
        }
        stage.childNodes[0].position.x = 1
        XCTAssertThrowsError(try create()); XCTAssertTrue(a.nodes[0].castsShadow); XCTAssertTrue(b.nodes[0].castsShadow)
        stage.childNodes[0].position.x = 0
        let skin = try XCTUnwrap(a.nodes[0].skinner); a.nodes[0].skinner = nil
        XCTAssertThrowsError(try create()); XCTAssertTrue(a.nodes[0].castsShadow)
        a.nodes[0].skinner = skin
        let trail = SCNNode(geometry: SCNPlane(width: 1, height: 1))
        trail.geometry?.materials = [SCNMaterial()]; trail.castsShadow = false; a.root.addChildNode(trail)
        // A supported nonidentity base bind is applied in the actual skin
        // matrices, rather than assumed away by the projection renderer.
        skin.baseGeometryBindTransform = SCNMatrix4MakeTranslation(0.1, 0, 0)
        let renderer = try create()
        XCTAssertFalse(a.nodes[0].castsShadow); XCTAssertFalse(b.nodes[0].castsShadow)
        XCTAssertFalse(trail.castsShadow)
        renderer.shutdown()
        XCTAssertTrue(a.nodes[0].castsShadow); XCTAssertTrue(b.nodes[0].castsShadow); XCTAssertFalse(trail.castsShadow)
        trail.geometry?.materials = [a.materials[0], SCNMaterial()]
        XCTAssertThrowsError(try create(), "Mixed source/effect geometry cannot silently join the source caster")
    }

    func testProjectionFollowsFullCOMScreenAspectAndAdvancesPreviousForwardOnlyOnce() throws {
        let fixture = try Fixture(device: device(), definition: Fixture.definition(rotation: [20, 30, 10]))
        defer { fixture.renderer.shutdown() }
        fixture.centers = [SIMD3(1, 2, 3), SIMD3(3, 4, 5)]
        _ = try fixture.map(tick: 7, viewport: CGSize(width: 128, height: 64))
        let first = try XCTUnwrap(fixture.renderer.lastFrame)
        // The fixture stage reflects Z when translating world meters back to
        // source coordinates. Both Y and Z must participate in the midpoint.
        XCTAssertEqual(first.sourceCameraPosition, SIMD3<Float>(2, 3, -14))
        XCTAssertEqual(first.aspect, 2)
        XCTAssertEqual(first.sourceProjection[1].y / first.sourceProjection[0].x, 2, accuracy: 1e-6)
        _ = try fixture.map(tick: 7, viewport: CGSize(width: 192, height: 64))
        let duplicate = try XCTUnwrap(fixture.renderer.lastFrame)
        XCTAssertEqual(duplicate.sourceCameraPosition, first.sourceCameraPosition)
        XCTAssertEqual(duplicate.aspect, 3)
        for c in 0..<4 { XCTAssertEqual(duplicate.sourceView[c], first.sourceView[c]) }
        _ = try fixture.map(tick: 8)
        let next = try XCTUnwrap(fixture.renderer.lastFrame)
        let forward = Renderer.unityEuler(SIMD3<Float>(20, 30, 10)).act(SIMD3<Float>(0, 0, 1))
        let expected = SIMD3<Float>(2, 3, -4) - forward * 10
        for c in 0..<3 { XCTAssertEqual(next.sourceCameraPosition[c], expected[c], accuracy: 1e-5) }
        XCTAssertThrowsError(try fixture.map(tick: 6))
        fixture.renderer.reset(); _ = try fixture.map(tick: 0)
        XCTAssertEqual(fixture.renderer.lastFrame?.sourceCameraPosition, first.sourceCameraPosition)
    }

    func testSharedMapReplacesInActorOrderWithoutDepthAndRespondsToSameTickCompletion() throws {
        let fixture = try Fixture(device: device()); defer { fixture.renderer.shutdown() }
        fixture.factors = [0.25, 0.75]
        fixture.actors[0].root.position.z = 2; fixture.actors[1].root.position.z = -2
        let initial = try fixture.map(tick: 0), center = 32 * 64 + 32
        XCTAssertEqual(Float(initial[center]), 0.75 * 255, accuracy: 1)
        XCTAssertEqual(fixture.renderer.lastFrame?.triangleCount, 4)
        let duplicate = try fixture.map(tick: 0); XCTAssertEqual(duplicate, initial)
        fixture.actors[1].nodes[0].isHidden = true // Source completion can run without a new core tick.
        let complete = try fixture.map(tick: 0)
        XCTAssertEqual(Float(complete[center]), 0.25 * 255, accuracy: 1)
        fixture.actors[1].nodes[0].isHidden = false; fixture.factors[1] = 0.5
        let restored = try fixture.map(tick: 0)
        XCTAssertEqual(Float(restored[center]), 0.5 * 255, accuracy: 1)
        XCTAssertEqual(fixture.renderer.lastFrame?.sourceCameraPosition, SIMD3<Float>(0, 0, -10))
        XCTAssertEqual(fixture.renderer.rawMap.sampleCount, 1); XCTAssertEqual(fixture.renderer.rawMap.mipmapLevelCount, 1)
    }

    func testAdditionalModelsAppendAndUnloadWithoutLeakingCasterFlags() throws {
        let fixture = try Fixture(device: device()); defer { fixture.renderer.shutdown() }
        fixture.factors = [0.25, 0.75]
        let additional = Fixture.actor(name: "synthetic_additional")
        additional.nodes[0].castsShadow = true; fixture.extra = [additional]
        let appended = try fixture.map(tick: 0), center = 32 * 64 + 32
        XCTAssertEqual(appended[center], 0, "Additional source models are appended after both initial actors")
        XCTAssertEqual(fixture.renderer.lastFrame?.triangleCount, 6); XCTAssertFalse(additional.nodes[0].castsShadow)
        fixture.extra = []
        let removed = try fixture.map(tick: 0)
        XCTAssertEqual(Float(removed[center]), 0.75 * 255, accuracy: 1)
        XCTAssertTrue(additional.nodes[0].castsShadow)
        fixture.extra = [additional, additional]
        XCTAssertThrowsError(try fixture.map(tick: 1))
        fixture.extra = []
        fixture.renderer.shutdown(); XCTAssertTrue(fixture.actors[0].nodes[0].castsShadow)
        XCTAssertThrowsError(try fixture.map(tick: 2))
    }

    func testOriginalFiveTapHalfKernelAndClampAreMeasuredOnGPU() throws {
        let fixture = try Fixture(device: device(), definition: Fixture.definition(width: 16))
        defer { fixture.renderer.shutdown() }
        let width = 16
        var source = [UInt8](repeating: 255, count: width * width)
        for y in 0..<width { for x in 0..<width {
            source[y * width + x] = UInt8((x * 17 + y * 31 + (x == 0 ? 90 : 0)) % 256)
        } }
        let command = try fixture.command()
        try fixture.uploadRaw(source, on: command); try fixture.renderer.encodeBlur(on: command)
        let read = try fixture.readback(fixture.renderer.blurredMap, on: command, bytesPerPixel: 1)
        try fixture.finish(command)
        let actual = fixture.bytes(read, width: width, height: width, components: 1)
        func half(_ value: Float) -> Float { Float(Float16(value)) }
        func sample(_ u: Float, _ v: Float) -> Float {
            let px = u * Float(width) - 0.5, py = v * Float(width) - 0.5
            let ix = Int(floor(px)), iy = Int(floor(py)), tx = px - floor(px), ty = py - floor(py)
            func texel(_ x: Int, _ y: Int) -> Float { Float(source[min(width - 1, max(0, y)) * width + min(width - 1, max(0, x))]) / 255 }
            return half((texel(ix, iy) * (1 - tx) + texel(ix + 1, iy) * tx) * (1 - ty) +
                (texel(ix, iy + 1) * (1 - tx) + texel(ix + 1, iy + 1) * tx) * ty)
        }
        var maximumError: Float = 0, changed = 0
        for y in 0..<width { for x in 0..<width {
            let u = (Float(x) + 0.5) / Float(width), v = (Float(y) + 0.5) / Float(width)
            let samples: [Float] = fixture.definition.blur.offsets.map { offset in
                func varying(_ base: Float, _ offset: Float) -> Float {
                    let delta = half(1 / Float(width)) * half(offset)
                    let low = half(delta), high = half(1 + delta)
                    return half(low + (high - low) * base)
                }
                return sample(varying(u, offset[0]), varying(v, offset[1]))
            }
            let partial = half(samples.prefix(4).reduce(0, +) * half(0.2))
            let expected = half(samples[4] * 0.2 + partial) * 255
            maximumError = max(maximumError, abs(Float(actual[y * width + x]) - expected))
            if abs(Int(actual[y * width + x]) - Int(source[y * width + x])) > 8 { changed += 1 }
        } }
        XCTAssertLessThanOrEqual(maximumError, 3, "Includes half varyings, bilinear interpolation, R8 quantization and edge clamp")
        XCTAssertGreaterThan(changed, 100, "A copy, nearest sample or disabled blur cannot satisfy this kernel")
        print("Source projector five-tap GPU maxByteError=\(maximumError), changedPixels=\(changed), format=\(fixture.renderer.blurredMap.pixelFormat.rawValue)")
    }

    func testReceiverUsesGammaRGBAHalfMultiplicationAndPreservedSceneDepth() throws {
        let fixture = try Fixture(device: device()); defer { fixture.renderer.shutdown() }
        let background: [Float] = [204, 153, 102, 255]
        for q in [UInt8(0), UInt8(128), UInt8(255)] {
            let value = fixture.rgba(try fixture.receiver(tick: Int(q), constantMap: q))
            for c in 0..<4 {
                let sample = Float(q) / 255, color = fixture.definition.sourceLocation.shadowColor[c]
                let expected = background[c] * (sample * (1 - color) + color)
                XCTAssertEqual(Float(value[c]), expected, accuracy: 3)
            }
        }
        let blocked = fixture.rgba(try fixture.receiver(tick: 256, constantMap: 0, depthClear: 0))
        XCTAssertEqual(blocked, SIMD4<UInt8>(204, 153, 102, 255), "Opaque scene depth must block the receiver")
        let after = fixture.rgba(try fixture.receiver(tick: 257, constantMap: 0, drawBehind: true))
        XCTAssertEqual(after, SIMD4<UInt8>(0, 0, 255, 255), "Receiver depth writes must remain off")
    }

    func testAsymmetricCasterAndHalfProjectedReceiverAgreeWithoutDividingByW() throws {
        let first = Fixture.actor(name: "asymmetric", halfSize: 0.2)
        let second = Fixture.actor(name: "hidden"); second.nodes[0].isHidden = true
        first.root.position = SCNVector3(0.65, 0.85, 0)
        let fixture = try Fixture(device: device(), actors: [first, second]); defer { fixture.renderer.shutdown() }
        let raw = try fixture.map(tick: 0), result = try fixture.receiver(tick: 0)
        let sourceX = Int((0.5 + 0.65 / 4) * 64), sourceY = Int((0.5 + 0.85 / 4) * 64)
        XCTAssertEqual(raw[sourceY * 64 + sourceX], 0)
        XCTAssertEqual(raw[(63 - sourceY) * 64 + sourceX], 255, "The map's Y basis must be unambiguous")
        let projected = fixture.rgba(result, x: sourceX, y: 63 - sourceY)
        let mirrored = fixture.rgba(result, x: sourceX, y: sourceY)
        XCTAssertEqual(Float(projected.x), 204 * 0.2, accuracy: 3)
        XCTAssertEqual(mirrored, SIMD4<UInt8>(204, 153, 102, 255))
        let matrix = try XCTUnwrap(fixture.renderer.lastFrame).sourceShadowMatrix
        XCTAssertEqual(matrix[3].w, 0.5)
        XCTAssertLessThan(projected.x, mirrored.x / 2, "Dividing projected UV by source W=0.5 would miss this silhouette")
        first.nodes[1].position.x += 0.5
        fixture.renderer.invalidateContent()
        let moved = try fixture.map(tick: 0)
        XCTAssertEqual(moved[sourceY * 64 + sourceX], 255, "Actual corrected bones, not a static bind mesh, must reach the GPU")
    }

    func testControlledSurfacePreservesGammaRGBAndPresentsOpaqueAlphaAtAllRequiredSamples() throws {
        let gpu = try device(), formats = try DuelTriadRenderSurface.formats(device: gpu)
        let fixture = try Fixture(device: gpu, formats: formats)
        fixture.actors[1].nodes[0].isHidden = true
        let scene = SCNScene(); scene.rootNode.addChildNode(fixture.stageRoot)
        // These synthetic casters are intentionally independent of SceneKit's
        // visible geometry, so the receiver is measurable without body overlap.
        let plane = SCNNode(geometry: SCNPlane(width: 4, height: 4))
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1)
        plane.geometry?.materials = [material]; plane.position.z = -0.01
        scene.rootNode.addChildNode(plane)
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.position.z = 5
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 2
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 20
        scene.rootNode.addChildNode(camera)
        let packets = try DuelTriadMetalRenderer(device: gpu, formats: formats)
        let surface = try DuelTriadRenderSurface(device: gpu, scene: scene, pointOfView: camera, packets: packets)
        defer { surface.shutdown(); packets.shutdown(); fixture.renderer.shutdown() }
        func capture(tick: Int, samples: Int) throws -> SIMD4<UInt8> {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
            descriptor.storageMode = .private; descriptor.usage = .renderTarget
            let target = try XCTUnwrap(gpu.makeTexture(descriptor: descriptor)), command = try fixture.command()
            try surface.encodeFrame(to: target, atTick: tick, samples: samples, commandBuffer: command)
            let result = try fixture.readback(target, on: command, bytesPerPixel: 4)
            try fixture.finish(command)
            let bytes = fixture.bytes(result, width: 64, height: 64, components: 4), i = (32 * 64 + 32) * 4
            return SIMD4(bytes[i + 2], bytes[i + 1], bytes[i], bytes[i + 3])
        }
        for samples in formats.map(\.samples) {
            surface.projectedShadow = nil
            let before = try capture(tick: 0, samples: samples)
            surface.projectedShadow = fixture.renderer; fixture.renderer.reset(); fixture.factors[0] = 0
            let shadow = try capture(tick: 0, samples: samples)
            for c in 0..<3 {
                XCTAssertEqual(Float(shadow[c]), Float(before[c]) * fixture.definition.sourceLocation.shadowColor[c], accuracy: 3)
            }
            XCTAssertEqual(shadow.w, 255, "Only the final presentation pass makes alpha opaque")
            fixture.factors[0] = 1
            let complete = try capture(tick: 1, samples: samples)
            XCTAssertEqual(complete, before, "Final alpha-only presentation must preserve all RGB bytes")
            surface.setPaused(true)
            XCTAssertThrowsError(try capture(tick: 2, samples: samples))
            surface.setPaused(false)
            print("Source projected surface samples=\(samples), baseline=\(before), shadow=\(shadow), restored=\(complete)")
        }
    }
}
