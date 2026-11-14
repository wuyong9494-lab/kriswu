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
        let uploadLayout = "weights=\(Renderer.sourceLayout(ws));indices=\(Renderer.sourceLayout(js))"
        GLTFModel.installSkinner(on: holder, geometry: geometry, bones: [bone],
            inverseBinds: [NSValue(scnMatrix4: SCNMatrix4Identity)], weights: ws, indices: js, skeleton: bone)
        holder.castsShadow = true
        if let skin = holder.skinner, let positions = geometry.sources(for: .vertex).first {
            print("Synthetic SceneKit skin upload: \(uploadLayout)")
            print("Synthetic SceneKit skin returned: position=\(Renderer.sourceLayout(positions));weights=\(Renderer.sourceLayout(skin.boneWeights));indices=\(Renderer.sourceLayout(skin.boneIndices))")
        }
        if let retained = GLTFModel.skinSources(for: holder) {
            print("Synthetic SceneKit retained inputs: weights=\(Renderer.sourceLayout(retained.weights));indices=\(Renderer.sourceLayout(retained.indices))")
            XCTAssertEqual(retained.weights.data, weights.withUnsafeBytes { Data($0) })
            XCTAssertEqual(retained.indices.data, joints.withUnsafeBytes { Data($0) })
            XCTAssertFalse(retained.weights === ws); XCTAssertFalse(retained.indices === js)
        } else { XCTFail("A source-created holder must retain the exact constructor inputs") }
        return .init(root: root, nodes: [holder, bone], materials: [material], outlines: [])
    }

    /// Deliberately padded, offset and unaligned synthetic source buffers.
    /// No SCNSkinner optimization can hide an unsupported reader format here.
    static func packedSkinSources(weights: [Float], indices: [UInt32], indexBytes: Int,
                                  floatIndices: Bool = false) -> (position: SCNGeometrySource, weights: SCNGeometrySource, indices: SCNGeometrySource) {
        let positionStride = 20, weightStride = weights.count * 4 + 8
        let indexStride = indices.count * indexBytes + 5
        var positions = Data(repeating: 0xa5, count: 4 + 2 * positionStride)
        var weightData = Data(repeating: 0xa5, count: 4 + 2 * weightStride)
        var indexData = Data(repeating: 0xa5, count: 3 + 2 * indexStride)
        for v in 0..<2 {
            let point: [Float] = [Float(v) + 0.5, -0.25, 0.75]
            for c in 0..<3 { for b in 0..<4 {
                positions[4 + v * positionStride + c * 4 + b] = UInt8(truncatingIfNeeded: point[c].bitPattern >> (b * 8))
            } }
            for c in weights.indices { for b in 0..<4 {
                weightData[4 + v * weightStride + c * 4 + b] = UInt8(truncatingIfNeeded: weights[c].bitPattern >> (b * 8))
            } }
            for c in indices.indices { for b in 0..<indexBytes {
                indexData[3 + v * indexStride + c * indexBytes + b] = UInt8(truncatingIfNeeded: indices[c] >> (b * 8))
            } }
        }
        return (SCNGeometrySource(data: positions, semantic: .vertex, vectorCount: 2,
                    usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 4, dataStride: positionStride),
                SCNGeometrySource(data: weightData, semantic: .boneWeights, vectorCount: 2,
                    usesFloatComponents: true, componentsPerVector: weights.count, bytesPerComponent: 4, dataOffset: 4, dataStride: weightStride),
                SCNGeometrySource(data: indexData, semantic: .boneIndices, vectorCount: 2,
                    usesFloatComponents: floatIndices, componentsPerVector: indices.count, bytesPerComponent: indexBytes,
                    dataOffset: 3, dataStride: indexStride))
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
    /// Synthetic source-queue-3000 packet. The fixed numeric shader is
    /// independent of the SceneKit soul modifier and its expected blend math.
    func sourcePacket(formats: [Renderer.Format]) throws -> DuelTriadSourceMaterial.Draw {
        let library = try device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float4 p [[position]]; };
        vertex V sourceEffect(const device float4 *p [[buffer(0)]], uint i [[vertex_id]]) {
            V o; o.p=p[i]; return o;
        }
        fragment float4 effectGamma() { return float4(0.1,0.4,0.8,0.25); }
        """, options: nil)
        var pipelines: [Renderer.Format: MTLRenderPipelineState] = [:]
        for format in formats {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "sourceEffect")
            descriptor.fragmentFunction = library.makeFunction(name: "effectGamma")
            descriptor.rasterSampleCount = format.samples
            descriptor.depthAttachmentPixelFormat = format.depth
            descriptor.stencilAttachmentPixelFormat = format.stencil
            let color = try XCTUnwrap(descriptor.colorAttachments[0])
            color.pixelFormat = format.color; color.isBlendingEnabled = true
            color.rgbBlendOperation = .add; color.alphaBlendOperation = .add
            color.sourceRGBBlendFactor = .sourceAlpha; color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .sourceAlpha; color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipelines[format] = try device.makeRenderPipelineState(descriptor: descriptor)
        }
        let vertices: [SIMD4<Float>] = [SIMD4(-0.65, -0.65, 0.2, 1), SIMD4(0.65, -0.65, 0.2, 1),
            SIMD4(0.65, 0.65, 0.2, 1), SIMD4(-0.65, 0.65, 0.2, 1)]
        let indices: [UInt32] = [0, 1, 2, 0, 2, 3]
        let vertex = try XCTUnwrap(vertices.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) })
        let index = try XCTUnwrap(indices.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) })
        let description = MTLDepthStencilDescriptor()
        description.depthCompareFunction = .lessEqual; description.isDepthWriteEnabled = false
        return .init(pipelines: pipelines, depth: try XCTUnwrap(device.makeDepthStencilState(descriptor: description)),
            cull: .none, winding: .counterClockwise, vertex: vertex, index: index, indexCount: indices.count,
            textures: [], samplers: [], uniforms: Data(count: 96 * 16))
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
        let sourceHolder = b.nodes[0]
        let sourceGeometry = try XCTUnwrap(sourceHolder.geometry)
        let sourceSkin = try XCTUnwrap(sourceHolder.skinner)
        let captured = try XCTUnwrap(GLTFModel.skinSources(for: sourceHolder))
        let capturedWeights = captured.weights.data.withUnsafeBytes { Data($0) }
        let capturedIndices = captured.indices.data.withUnsafeBytes { Data($0) }
        let clone = sourceHolder.clone()
        // A cloned SceneKit holder has no construction record of its own.
        // It cannot inherit the original holder's private association.
        XCTAssertNil(GLTFModel.skinSources(for: clone))
        GLTFModel.installSkinner(on: clone, geometry: sourceGeometry, bones: sourceSkin.bones,
            inverseBinds: sourceSkin.boneInverseBindTransforms,
            weights: captured.weights, indices: captured.indices, skeleton: sourceSkin.skeleton)
        let cloneInputs = try XCTUnwrap(GLTFModel.skinSources(for: clone))
        XCTAssertNotNil(GLTFModel.skinSources(for: sourceHolder))
        XCTAssertFalse(cloneInputs.weights === captured.weights)
        XCTAssertFalse(cloneInputs.indices === captured.indices)
        XCTAssertEqual(cloneInputs.weights.data, capturedWeights)
        XCTAssertEqual(cloneInputs.indices.data, capturedIndices)
        XCTAssertTrue(sourceHolder.skinner === sourceSkin)
        XCTAssertEqual(GLTFModel.skinSources(for: sourceHolder)?.weights.data, capturedWeights)
        XCTAssertEqual(GLTFModel.skinSources(for: sourceHolder)?.indices.data, capturedIndices)
        clone.geometry = try XCTUnwrap(sourceGeometry.copy() as? SCNGeometry)
        XCTAssertNil(GLTFModel.skinSources(for: clone), "A different geometry cannot borrow the retained input")
        let correctedBinds = [NSValue(scnMatrix4: SCNMatrix4MakeTranslation(0.25, 0, 0))]
        GLTFModel.installSkinner(on: clone, geometry: sourceGeometry, bones: sourceSkin.bones,
            inverseBinds: correctedBinds, weights: captured.weights, indices: captured.indices,
            skeleton: sourceSkin.skeleton)
        let reboundSkin = try XCTUnwrap(clone.skinner)
        XCTAssertEqual(try XCTUnwrap(reboundSkin.boneInverseBindTransforms?.first).scnMatrix4Value.m41, 0.25)
        XCTAssertEqual(GLTFModel.skinSources(for: clone)?.weights.data, capturedWeights)
        XCTAssertEqual(GLTFModel.skinSources(for: clone)?.indices.data, capturedIndices)
        let stranger = Fixture.actor(name: "unrelated_binding")
        clone.skinner = stranger.nodes[0].skinner
        XCTAssertNil(GLTFModel.skinSources(for: clone), "A replacement skinner cannot inherit a previous binding")
        clone.geometry = sourceGeometry; clone.skinner = reboundSkin
        XCTAssertNotNil(GLTFModel.skinSources(for: clone))
        // Optical fitting and projection consume the same exact constructor
        // inputs, and follow bones without modifying the corrected model.
        let originalGeometry = b.nodes[0].geometry, originalSkin = b.nodes[0].skinner
        let originalNodes = b.nodes.map(ObjectIdentifier.init)
        let bounds = try DuelDisplayedSkinBounds(root: b.root)
        let camera = SCNNode(); camera.position.z = 5
        let before = try bounds.cameraPoints(camera: camera)
        XCTAssertFalse(before.isEmpty)
        b.nodes[1].position.x += 0.25
        let after = try bounds.cameraPoints(camera: camera)
        XCTAssertEqual(after.count, before.count)
        for index in before.indices {
            XCTAssertEqual(after[index].x - before[index].x, 0.25, accuracy: 0.00001)
            XCTAssertEqual(after[index].y, before[index].y, accuracy: 0.00001)
            XCTAssertEqual(after[index].z, before[index].z, accuracy: 0.00001)
        }
        b.nodes[1].position.x -= 0.25
        XCTAssertTrue(b.nodes[0].geometry === originalGeometry)
        XCTAssertTrue(b.nodes[0].skinner === originalSkin)
        XCTAssertEqual(b.nodes.map(ObjectIdentifier.init), originalNodes)

        // Exercise each documented integer width and <=4 influence count
        // directly, with nonzero offsets, gaps and values crossing byte 255.
        let sourceWeights: [Float] = [0.125, 0.25, 0.5, 0.125]
        for indexBytes in [1, 2, 4] {
            let sourceIndices: [UInt32] = indexBytes == 1 ? [0, 127, 128, 255] : [0, 255, 256, 511]
            for count in 1...4 {
                let sources = Fixture.packedSkinSources(weights: Array(sourceWeights.prefix(count)),
                    indices: Array(sourceIndices.prefix(count)), indexBytes: indexBytes)
                let vertices = try Renderer.readSkinSources(position: sources.position, weights: sources.weights,
                    indices: sources.indices, boneCount: 512)
                XCTAssertEqual(vertices.count, 2)
                for v in vertices.indices {
                    XCTAssertEqual(vertices[v].position, SIMD4<Float>(Float(v) + 0.5, -0.25, 0.75, 1))
                    for c in 0..<4 {
                        XCTAssertEqual(vertices[v].weights[c], c < count ? sourceWeights[c] : 0)
                        XCTAssertEqual(vertices[v].joints[c], c < count ? sourceIndices[c] : 0)
                    }
                }
            }
        }
        for invalidWeights: [Float] in [[.nan], [-0.25], [1.25], [0]] {
            let sources = Fixture.packedSkinSources(weights: invalidWeights, indices: [0], indexBytes: 1)
            XCTAssertThrowsError(try Renderer.readSkinSources(position: sources.position, weights: sources.weights,
                indices: sources.indices, boneCount: 1))
        }
        let outside = Fixture.packedSkinSources(weights: [1], indices: [512], indexBytes: 4)
        XCTAssertThrowsError(try Renderer.readSkinSources(position: outside.position, weights: outside.weights,
            indices: outside.indices, boneCount: 512))
        let mismatch = Fixture.packedSkinSources(weights: [0.5, 0.5], indices: [0], indexBytes: 1)
        XCTAssertThrowsError(try Renderer.readSkinSources(position: mismatch.position, weights: mismatch.weights,
            indices: mismatch.indices, boneCount: 1))
        let floating = Fixture.packedSkinSources(weights: [1], indices: [0], indexBytes: 4, floatIndices: true)
        XCTAssertThrowsError(try Renderer.readSkinSources(position: floating.position, weights: floating.weights,
            indices: floating.indices, boneCount: 1))
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
        func sample(_ u: Float, _ v: Float) -> Float {
            let px = u * Float(width) - 0.5, py = v * Float(width) - 0.5
            let ix = Int(floor(px)), iy = Int(floor(py)), tx = px - floor(px), ty = py - floor(py)
            func texel(_ x: Int, _ y: Int) -> Float { Float(source[min(width - 1, max(0, y)) * width + min(width - 1, max(0, x))]) / 255 }
            return Float(Float16((texel(ix, iy) * (1 - tx) + texel(ix + 1, iy) * tx) * (1 - ty) +
                (texel(ix, iy + 1) * (1 - tx) + texel(ix + 1, iy + 1) * tx) * ty))
        }
        var maximumError: Float = 0, changed = 0
        for y in 0..<width { for x in 0..<width {
            let u = (Float(x) + 0.5) / Float(width), v = (Float(y) + 0.5) / Float(width)
            let samples: [Float] = fixture.definition.blur.offsets.map { offset in
                func varying(_ base: Float, _ offset: Float) -> Float {
                    // Keep the pure half conversion local: a nested function
                    // must not call an actor-isolated local helper in Swift 6.
                    let delta = Float(Float16(1 / Float(width))) * Float(Float16(offset))
                    let low = Float(Float16(delta)), high = Float(Float16(1 + delta))
                    return Float(Float16(low + (high - low) * base))
                }
                return sample(varying(u, offset[0]), varying(v, offset[1]))
            }
            let partial = Float(Float16(samples.prefix(4).reduce(0, +) * Float(Float16(Float(0.2)))))
            let expected = Float(Float16(samples[4] * 0.2 + partial)) * 255
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
        let backgroundColor = UIColor(red: 0.13, green: 0.17, blue: 0.19, alpha: 1)
        scene.background.contents = backgroundColor
        // These synthetic casters are intentionally independent of SceneKit's
        // visible geometry, so the receiver is measurable without body overlap.
        let plane = SCNNode(geometry: SCNPlane(width: 2, height: 2))
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1)
        plane.geometry?.materials = [material]; plane.position.z = -0.01
        scene.rootNode.addChildNode(plane)
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.position.z = 5
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 2
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 20
        let originalCameraMask = 1 | DuelTriadRenderSurface.lateSourceCategory | (1 << 10)
        camera.camera?.categoryBitMask = originalCameraMask
        scene.rootNode.addChildNode(camera)
        let soul = SCNNode(geometry: SCNPlane(width: 1, height: 1))
        let soulMaterial = SCNMaterial(); soulMaterial.lightingModel = .constant
        soulMaterial.diffuse.contents = UIColor.white
        soulMaterial.blendMode = .alpha; soulMaterial.readsFromDepthBuffer = true
        soulMaterial.writesToDepthBuffer = false
        soulMaterial.shaderModifiers = [.fragment: """
        #pragma transparent
        #pragma body
        _output.color = float4(0.7, 0.15, 0.45, 0.5);
        """]
        soul.geometry?.materials = [soulMaterial]; soul.position.z = 1
        soul.categoryBitMask = DuelTriadRenderSurface.lateSourceCategory
        soul.castsShadow = false; soul.isHidden = true; scene.rootNode.addChildNode(soul)
        let occluder = SCNNode(geometry: SCNPlane(width: 0.6, height: 0.6))
        let opaqueMaterial = SCNMaterial(); opaqueMaterial.lightingModel = .constant
        opaqueMaterial.diffuse.contents = UIColor(red: 0.2, green: 0.7, blue: 0.1, alpha: 1)
        occluder.geometry?.materials = [opaqueMaterial]; occluder.position.z = 2
        occluder.isHidden = true; scene.rootNode.addChildNode(occluder)
        let packets = try DuelTriadMetalRenderer(device: gpu, formats: formats)
        let sourcePacket = try fixture.sourcePacket(formats: formats)
        let surface = try DuelTriadRenderSurface(device: gpu, scene: scene, pointOfView: camera, packets: packets)
        defer { surface.shutdown(); packets.shutdown(); fixture.renderer.shutdown() }
        var lateGeometry: [SCNNode] = []
        surface.lateSourceGeometry = { lateGeometry }
        func capture(tick: Int, samples: Int) throws -> [UInt8] {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
            descriptor.storageMode = .private; descriptor.usage = .renderTarget
            let target = try XCTUnwrap(gpu.makeTexture(descriptor: descriptor)), command = try fixture.command()
            try surface.encodeFrame(to: target, atTick: tick, samples: samples, commandBuffer: command)
            let result = try fixture.readback(target, on: command, bytesPerPixel: 4)
            try fixture.finish(command)
            return fixture.bytes(result, width: 64, height: 64, components: 4)
        }
        func pixel(_ bytes: [UInt8], x: Int = 32, y: Int = 32) -> SIMD4<UInt8> {
            let i = (y * 64 + x) * 4
            return SIMD4(bytes[i + 2], bytes[i + 1], bytes[i], bytes[i + 3])
        }
        let soulRGB = SIMD3<Float>(0.7, 0.15, 0.45), soulAlpha: Float = 0.5
        let effectRGB = SIMD3<Float>(0.1, 0.4, 0.8), effectAlpha: Float = 0.25
        for format in formats {
            let samples = format.samples
            lateGeometry = []; soul.isHidden = true; occluder.isHidden = true; packets.clear()
            surface.projectedShadow = nil
            let baseline = try capture(tick: 0, samples: samples), before = pixel(baseline)
            surface.projectedShadow = fixture.renderer; fixture.renderer.reset(); fixture.factors[0] = 0
            let shadow = pixel(try capture(tick: 0, samples: samples))
            for c in 0..<3 {
                XCTAssertEqual(Float(shadow[c]), Float(before[c]) * fixture.definition.sourceLocation.shadowColor[c], accuracy: 3)
            }
            XCTAssertEqual(shadow.w, 255, "Only the final presentation pass makes alpha opaque")
            fixture.factors[0] = 1
            let complete = pixel(try capture(tick: 1, samples: samples))
            XCTAssertEqual(complete, before, "Final alpha-only presentation must preserve all RGB bytes")
            surface.setPaused(true)
            XCTAssertThrowsError(try capture(tick: 2, samples: samples))
            surface.setPaused(false)

            // A late-only frame must still preserve source Gamma, blend just
            // once, and present A=1 even without an installed projector.
            surface.projectedShadow = nil; soul.isHidden = false; lateGeometry = [soul]
            let lateOnly = try capture(tick: 2, samples: samples), soulOnly = pixel(lateOnly)
            for c in 0..<3 {
                let expected = soulRGB[c] * 255 * soulAlpha + Float(before[c]) * (1 - soulAlpha)
                XCTAssertEqual(Float(soulOnly[c]), expected, accuracy: 3)
            }
            XCTAssertEqual(soulOnly.w, 255)
            XCTAssertEqual(pixel(lateOnly, x: 3, y: 3), pixel(baseline, x: 3, y: 3),
                "The late SceneKit pass must not clear or repaint the background")

            // This independent numeric order detects receiver-after-soul,
            // FX-after-soul, sRGB re-encoding and drawing a soul twice.
            surface.projectedShadow = fixture.renderer; fixture.renderer.reset(); fixture.factors[0] = 0
            try packets.submit(.init(format: format, draws: [sourcePacket]))
            let layered = try capture(tick: 3, samples: samples), combined = pixel(layered)
            for c in 0..<3 {
                let afterShadow = Float(before[c]) * fixture.definition.sourceLocation.shadowColor[c]
                let afterEffect = effectRGB[c] * 255 * effectAlpha + afterShadow * (1 - effectAlpha)
                let expected = soulRGB[c] * 255 * soulAlpha + afterEffect * (1 - soulAlpha)
                XCTAssertEqual(Float(combined[c]), expected, accuracy: 3)
            }
            XCTAssertEqual(combined.w, 255)
            XCTAssertEqual(pixel(layered, x: 3, y: 3), pixel(baseline, x: 3, y: 3))
            let cameraPosition = fixture.renderer.lastFrame?.sourceCameraPosition
            XCTAssertEqual(try capture(tick: 3, samples: samples), layered)
            XCTAssertEqual(fixture.renderer.lastFrame?.sourceCameraPosition, cameraPosition)
            XCTAssertEqual(camera.camera?.categoryBitMask, originalCameraMask)
            XCTAssertTrue((scene.background.contents as? UIColor) === backgroundColor)

            // An opaque foreground surface from the FIRST pass must occlude
            // both source FX and the late soul through the preserved depth.
            occluder.isHidden = false; soul.isHidden = true; lateGeometry = []
            packets.clear(); surface.projectedShadow = nil
            let opaque = pixel(try capture(tick: 4, samples: samples))
            soul.isHidden = false; lateGeometry = [soul]; surface.projectedShadow = fixture.renderer
            try packets.submit(.init(format: format, draws: [sourcePacket]))
            XCTAssertEqual(pixel(try capture(tick: 4, samples: samples)), opaque)

            // A source cancellation/removal can occur at the same tick. The
            // normal no-soul path must neither replay a cached soul nor retain
            // its camera mask/background changes.
            occluder.isHidden = true; soul.isHidden = true; lateGeometry = []
            let removed = pixel(try capture(tick: 4, samples: samples))
            for c in 0..<3 {
                let afterShadow = Float(before[c]) * fixture.definition.sourceLocation.shadowColor[c]
                let expected = effectRGB[c] * 255 * effectAlpha + afterShadow * (1 - effectAlpha)
                XCTAssertEqual(Float(removed[c]), expected, accuracy: 3)
            }
            packets.clear(); surface.projectedShadow = nil
            XCTAssertEqual(try capture(tick: 4, samples: samples), baseline)

            soul.isHidden = false; lateGeometry = [soul]
            var boundaries = 0; surface.didSubmitFrame = { boundaries += 1 }
            let pose = soul.simdTransform
            let firstCapture = try surface.captureFrame(tick: 5, pixelSize: CGSize(width: 64, height: 64), samples: samples)
            XCTAssertEqual(boundaries, 1, "Two scene passes form exactly one committed render boundary")
            let secondCapture = try surface.captureFrame(tick: 5, pixelSize: CGSize(width: 64, height: 64), samples: samples)
            XCTAssertEqual(boundaries, 2)
            let firstData = try XCTUnwrap(firstCapture.cgImage?.dataProvider?.data)
            let secondData = try XCTUnwrap(secondCapture.cgImage?.dataProvider?.data)
            XCTAssertEqual(firstData as Data, secondData as Data)
            for c in 0..<4 { XCTAssertEqual(soul.simdTransform[c], pose[c]) }
            surface.setPaused(true)
            XCTAssertThrowsError(try surface.captureFrame(tick: 6, pixelSize: CGSize(width: 64, height: 64), samples: samples))
            XCTAssertEqual(boundaries, 2)
            surface.setPaused(false)
            _ = try surface.captureFrame(tick: 5, pixelSize: CGSize(width: 64, height: 64), samples: samples)
            XCTAssertEqual(boundaries, 3)
            XCTAssertEqual(camera.camera?.categoryBitMask, originalCameraMask)
            XCTAssertTrue((scene.background.contents as? UIColor) === backgroundColor)
            lateGeometry = [soul, soul]
            XCTAssertThrowsError(try capture(tick: 6, samples: samples))
            XCTAssertEqual(camera.camera?.categoryBitMask, originalCameraMask)
            surface.didSubmitFrame = nil; lateGeometry = []; soul.isHidden = true
            print("Source projected surface samples=\(samples), baseline=\(before), shadow=\(shadow), lateOnly=\(soulOnly), layered=\(combined), canceled=\(removed)")
        }
    }
}
