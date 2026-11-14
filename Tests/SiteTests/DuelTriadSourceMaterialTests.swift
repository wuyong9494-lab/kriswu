import XCTest
import Metal
import SceneKit
import simd
@testable import ShiftReminder

/// All shader and pixel contents in this file are synthetic, author-owned
/// fixtures. They exercise the native adapter, not recovered game artwork.
@MainActor
final class DuelTriadSourceMaterialTests: XCTestCase {
    typealias Source = DuelTriadSourceMaterial
    private let format = Source.Format(color: .rgba8Unorm, depth: .depth32Float_stencil8, stencil: .depth32Float_stencil8, samples: 1)
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 position, normal, tangent, color, uv0, uv1; };
    struct U { float4 data[96]; };
    struct O { float4 position [[position]]; };
    vertex O triad_fixture_v(uint id [[vertex_id]], const device V* vertices [[buffer(0)]], constant U& u [[buffer(2)]]) {
        float4x4 model(u.data[0],u.data[1],u.data[2],u.data[3]);
        float4x4 vp(u.data[16],u.data[17],u.data[18],u.data[19]);
        float4 p=float4(vertices[id].position.xyz*float3(1,1,-1)/u.data[27].x,1);
        O result; result.position=vp*model*p; return result;
    }
    fragment float4 triad_fixture_f(O in [[stage_in]], constant U& u [[buffer(2)]]) { return u.data[22]; }
    """
    private var programData: Data { Data(Self.shader.utf8) }
    private func descriptor(source: Int = 1, destination: Int = 10, cull: Int = 0,
                            zWrite: Bool = false, zTest: Int = 4, colorMask: Int = 15,
                            uniforms: [Source.Uniform] = [], textures: [String: Source.Texture] = [:]) -> Source.Descriptor {
        .init(sourceName: "Synthetic adapter fixture", shaderPathID: "1",
            sourceShaderSHA256: String(repeating: "a", count: 64), variantSHA256: String(repeating: "b", count: 64),
            projectColorSpace: 0, projectAnisotropicFiltering: 0, keywords: [], floats: [:], colors: [:], textures: textures,
            program: .init(file: "Synthetic_Triad.metal", bytes: programData.count,
                sha256: DuelNetworkContentRecord.digest(programData), vertexFunction: "triad_fixture_v",
                fragmentFunction: "triad_fixture_f", uniforms: uniforms, textures: textures.keys.sorted(), layoutVersion: 1),
            raster: .init(source: source, destination: destination, cull: cull, zWrite: zWrite, zTest: zTest, colorMask: colorMask))
    }
    private func device() throws -> MTLDevice { try XCTUnwrap(MTLCreateSystemDefaultDevice(), "Native acceptance requires a Metal device") }
    private func factory(_ descriptor: Source.Descriptor, textureData: [String: Data] = [:],
                         device: MTLDevice? = nil, format: Source.Format? = nil) throws -> Source.Factory {
        try .init(materials: ["fixture": descriptor], programData: ["Synthetic_Triad.metal": programData],
            textureData: textureData, device: device ?? self.device(), formats: [format ?? self.format])
    }
    private func quad(z: Float = 0.5, extent: Float = 1, clockwise: Bool = false) -> Source.Geometry {
        .init(positions: [-extent, -extent, z, extent, -extent, z, extent, extent, z, -extent, extent, z],
            normals: [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], uv: [0, 1, 1, 1, 1, 0, 0, 0],
            uv1: nil, colors: nil, tangents: nil, indices: [0, 1, 2, 0, 2, 3], clockwise: clockwise)
    }
    private func packet(_ instance: Source.Instance, color: SIMD4<Float>, tick: Int = 60,
                        projection: simd_float4x4 = matrix_identity_float4x4,
                        sourceTransparency: Float? = nil) throws -> Source.Draw {
        try instance.packet(modelTransform: matrix_identity_float4x4, viewTransform: matrix_identity_float4x4,
            projectionTransform: projection, cameraPosition: .zero, tick: tick,
            color: color, custom1: .zero, custom2: .zero, stableRandom: .zero, uvTransform: SIMD4(0, 0, 1, 1),
            sourceTransparency: sourceTransparency)
    }
    private func draw(_ descriptor: Source.Descriptor, color: SIMD4<Float>, device: MTLDevice,
                      z: Float = 0.5, clockwise: Bool = false) throws -> Source.Draw {
        let factory = try factory(descriptor, device: device)
        let instance = try factory.make(id: "fixture", geometry: quad(z: z, clockwise: clockwise),
            vertexStreams: [0, 1, 3, 4], units: 1)
        return try packet(instance, color: color)
    }
    private func render(_ draws: [Source.Draw], clear: SIMD4<Float>, device: MTLDevice) throws -> SIMD4<Float> {
        let color = try XCTUnwrap(device.makeTexture(descriptor: {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
            d.usage = [.renderTarget]; d.storageMode = .shared; return d
        }()))
        let depth = try XCTUnwrap(device.makeTexture(descriptor: {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float_stencil8, width: 4, height: 4, mipmapped: false)
            d.usage = [.renderTarget]; d.storageMode = .private; return d
        }()))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color; pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(clear.x), green: Double(clear.y), blue: Double(clear.z), alpha: Double(clear.w))
        pass.depthAttachment.texture = depth; pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare; pass.depthAttachment.clearDepth = 1
        pass.stencilAttachment.texture = depth; pass.stencilAttachment.loadAction = .clear
        pass.stencilAttachment.storeAction = .dontCare; pass.stencilAttachment.clearStencil = 0
        let queue = try XCTUnwrap(device.makeCommandQueue()), command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
        for draw in draws { try draw.encode(on: encoder, format: format) }
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed, String(describing: command.error))
        var bytes = [UInt8](repeating: 0, count: 4 * 4 * 4)
        bytes.withUnsafeMutableBytes {
            color.getBytes($0.baseAddress!, bytesPerRow: 16, from: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0)
        }
        return SIMD4(Float(bytes[40]), Float(bytes[41]), Float(bytes[42]), Float(bytes[43])) / 255
    }
    private func assertColor(_ result: SIMD4<Float>, _ expected: SIMD4<Float>, file: StaticString = #filePath, line: UInt = #line) {
        for channel in 0..<4 { XCTAssertEqual(result[channel], expected[channel], accuracy: 2.0 / 255, file: file, line: line) }
    }
    private func checkBlend(source: Int, destination: Int) throws {
        let device = try device(), clear = SIMD4<Float>(0.12, 0.24, 0.36, 0.48)
        for alpha in [Float(0.25), 0] {
            let value = SIMD4<Float>(0.20, 0.30, 0.10, alpha)
            let draw = try draw(descriptor(source: source, destination: destination), color: value, device: device)
            let result = try render([draw], clear: clear, device: device)
            let expected = value * (source == 1 ? 1 : alpha) + clear * (destination == 1 ? 1 : 1 - alpha)
            assertColor(result, expected)
        }
    }

    func testOriginalVertexStreamPackingPreservesInterleavedCustomAndMissingW() throws {
        let common = try Source.StreamLayout([0, 1, 3, 4, 5, 34, 38])
        XCTAssertEqual(common.selectors, [SIMD4(2, 3, 4, 5), SIMD4(6, 7, 8, 9), SIMD4(10, 11, 12, 13), SIMD4(0, 0, 0, 1)])
        let random = try Source.StreamLayout([0, 1, 3, 4, 5, 34, 38, 26])
        XCTAssertEqual(random.selectors[3], SIMD4(14, 15, 16, 17))
        let interleaved = try Source.StreamLayout([0, 1, 3, 4, 32, 5, 36])
        XCTAssertEqual(Array(interleaved.selectors.prefix(2)), [SIMD4(2, 3, 6, 7), SIMD4(4, 5, 10, 11)])
        let basic = try Source.StreamLayout([0, 1, 3, 4])
        XCTAssertEqual(basic.selectors[0], SIMD4(2, 3, 0, 1))
        XCTAssertEqual(try Source.StreamLayout([0, 1, 3, 4, 5, 34]).selectors[2], SIMD4(0, 0, 0, 1))
        XCTAssertEqual(try Source.StreamLayout([0, 1, 3, 4, 5, 34, 26]).selectors[2], SIMD4(14, 15, 16, 17))
    }

    func testUnknownDuplicateAndOverfullStreamsFailClosed() {
        for streams in [[0, 1, 99], [0, 4, 4], [1, 4], [0, 4, 5, 34, 38, 26, 32]] {
            XCTAssertThrowsError(try Source.StreamLayout(streams))
        }
    }

    private func texture(format: Int = 4, width: Int = 2, height: Int = 2, mip: Int = 2) -> Source.Texture {
        .init(file: "Synthetic_Texture.png", dataFile: "Synthetic_Texture.texture", width: width, height: height,
            sourceTextureFormat: format, scale: [1, 1], offset: [0, 0], wrapS: 0, wrapT: 1,
            filter: 2, mip: mip, maxAnisotropy: 1, sourceColorSpace: 1)
    }

    func testOriginalMipByteLayoutAndGammaSamplingPreserveImporterMeaning() throws {
        let value = texture(format: 47, width: 5, height: 3, mip: 3)
        XCTAssertEqual(try value.levels().map(\.bytes), [32, 16, 16])
        XCTAssertEqual(try value.levels().map(\.offset), [0, 32, 48])
        XCTAssertEqual(value.pixelFormat(projectColorSpace: 0), .eac_rgba8)
        XCTAssertEqual(value.pixelFormat(projectColorSpace: 1), .eac_rgba8_srgb)
        XCTAssertEqual(texture(format: 45).pixelFormat(projectColorSpace: 0), .etc2_rgb8)
        XCTAssertEqual(texture().pixelFormat(projectColorSpace: 0), .rgba8Unorm)
        XCTAssertThrowsError(try texture(width: 1, height: 1, mip: 2).levels())
        XCTAssertThrowsError(try texture(format: 999).levels())
        XCTAssertEqual(try value.effectiveMaxAnisotropy(projectFiltering: 0), 1)
        XCTAssertThrowsError(try value.effectiveMaxAnisotropy(projectFiltering: 2))
    }

    func testOriginalMipPixelsAndAlphaZeroRGBReachGPUUnmodified() throws {
        let original = Data([200, 80, 10, 0, 9, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 17, 29, 43, 59])
        let value = descriptor(textures: ["_MainTex": texture()])
        let factory = try factory(value, textureData: ["Synthetic_Texture.texture": original])
        let instance = try factory.make(id: "fixture", geometry: quad(), vertexStreams: [0, 1, 3, 4], units: 1)
        let texture = try XCTUnwrap(try packet(instance, color: .zero).textures.first)
        XCTAssertEqual(texture.mipmapLevelCount, 2); XCTAssertEqual(texture.pixelFormat, .rgba8Unorm)
        var main = [UInt8](repeating: 0, count: 16), mip = [UInt8](repeating: 0, count: 4)
        main.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: 8, from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0) }
        mip.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: 4, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 1) }
        XCTAssertEqual(Data(main + mip), original)
    }

    func testMissingOrTruncatedOriginalMipDataCannotPrepare() throws {
        let value = descriptor(textures: ["_MainTex": texture()])
        XCTAssertThrowsError(try factory(value))
        XCTAssertThrowsError(try factory(value, textureData: ["Synthetic_Texture.texture": Data(repeating: 0, count: 16)]))
        XCTAssertThrowsError(try factory(value, textureData: ["Synthetic_Texture.texture": Data(repeating: 0, count: 21)]))
    }

    func testUnknownRasterMissingUniformAndGammaSRGBTargetFailClosed() throws {
        XCTAssertThrowsError(try descriptor(source: 2).validate())
        XCTAssertThrowsError(try descriptor(cull: 3).validate())
        XCTAssertThrowsError(try descriptor(uniforms: [.init(name: "_Unbound", width: 1, defaultValue: nil)]).validate())
        XCTAssertThrowsError(try factory(descriptor(), format: .init(color: .rgba8Unorm_srgb, depth: .depth32Float, stencil: .invalid, samples: 1)))
    }

    func testChangedProgramBytesAndUnavailableMetalCannotPrepare() throws {
        let device = try device()
        XCTAssertThrowsError(try Source.Factory(materials: ["fixture": descriptor()],
            programData: ["Synthetic_Triad.metal": programData + Data([32])], textureData: [:], device: device, formats: [format]))
        XCTAssertThrowsError(try Source.Factory(materials: ["fixture": descriptor()],
            programData: ["Synthetic_Triad.metal": programData], textureData: [:], device: nil, formats: [format]))
    }

    func testRepeatedGeometryReusesImmutableNativeBuffers() throws {
        let factory = try factory(descriptor())
        let first = try factory.make(id: "fixture", geometry: quad(), vertexStreams: [0, 1, 3, 4], units: 1)
        let second = try factory.make(id: "fixture", geometry: quad(), vertexStreams: [0, 1, 3, 4, 5, 34, 38], units: 1)
        let a = try packet(first, color: .zero), b = try packet(second, color: .zero)
        XCTAssertTrue(a.vertex === b.vertex); XCTAssertTrue(a.index === b.index)
        XCTAssertEqual(factory.geometryBufferCount, 1)
        let dynamic = try factory.make(id: "fixture", geometry: quad(), vertexStreams: [0, 1, 3, 4], units: 1, cacheGeometry: false)
        let c = try packet(dynamic, color: .zero)
        XCTAssertFalse(a.vertex === c.vertex); XCTAssertEqual(factory.geometryBufferCount, 1)
    }

    func testFixedTickUniformSnapshotPreservesOriginalTimeAndSpace() throws {
        let layout = try Source.StreamLayout([0, 1, 3, 4, 5, 34, 38, 26])
        var model = matrix_identity_float4x4; model[3] = SIMD4(2, 3, 4, 1)
        func data() throws -> Data {
            try Source.Instance.uniformData(modelTransform: model, viewTransform: matrix_identity_float4x4,
                projectionTransform: matrix_identity_float4x4, cameraPosition: SIMD3(1, 2, 3), tick: 1200,
                color: SIMD4(0.2, 0.3, 0.4, 0), custom1: SIMD4(1, 2, 3, 4), custom2: SIMD4(5, 6, 7, 8),
                stableRandom: SIMD4(0.1, 0.2, 0.3, 0.4), uvTransform: SIMD4(0.25, 0.5, 0.25, 0.5),
                units: 0.01, layout: layout, material: [])
        }
        let first = try data(); XCTAssertEqual(first, try data())
        let values = first.withUnsafeBytes { bytes in (0..<96).map { bytes.loadUnaligned(fromByteOffset: $0 * 16, as: SIMD4<Float>.self) } }
        XCTAssertEqual(values[21], SIMD4(1, 20, 40, 60))
        XCTAssertEqual(values[23], SIMD4(1, 2, 3, 4)); XCTAssertEqual(values[24], SIMD4(5, 6, 7, 8))
        XCTAssertEqual(values[26], SIMD4(0.25, 0.5, 0.25, 0.5))
        XCTAssertEqual(values[20], SIMD4(100, 200, -300, 1))
        let m = simd_float4x4(columns: (values[0], values[1], values[2], values[3]))
        let vp = simd_float4x4(columns: (values[16], values[17], values[18], values[19]))
        let nativePoint = SIMD4<Float>(0.4, 0.6, 0.8, 1), originalPoint = SIMD4<Float>(40, 60, -80, 1)
        let result = vp * m * originalPoint, expected = model * nativePoint
        for component in 0..<4 { XCTAssertEqual(result[component], expected[component], accuracy: 1e-5) }
    }

    func testSourceStopFramesOnlyOverridesAnExistingTransparentScalar() throws {
        let color = SIMD4<Float>(0.6, 0.4, 0.2, 0)
        func values(_ draw: Source.Draw) -> [SIMD4<Float>] {
            draw.uniforms.withUnsafeBytes { bytes in
                (0..<96).map { bytes.loadUnaligned(fromByteOffset: $0 * 16, as: SIMD4<Float>.self) }
            }
        }
        for width in [1, 4] {
            let descriptor = descriptor(uniforms: [
                .init(name: "_Other", width: 1, defaultValue: [3, 0, 0, 0]),
                .init(name: "_Transparent", width: width, defaultValue: [0.8, 0.2, 0.3, 0.4])])
            let instance = try factory(descriptor).make(id: "fixture", geometry: quad(),
                vertexStreams: [0, 1, 3, 4], units: 1)
            let original = values(try packet(instance, color: color))
            var expected = original
            if width == 1 { expected[33].x = 0.25 }
            XCTAssertEqual(values(try packet(instance, color: color, sourceTransparency: 0.25)), expected)
            XCTAssertEqual(values(try packet(instance, color: color)), original, "Prepared defaults remain immutable")
            XCTAssertEqual(expected[22], color, "Alpha-zero emission must not receive a generic RGBA fade")
        }
        let absent = try factory(descriptor()).make(id: "fixture", geometry: quad(), vertexStreams: [0, 1, 3, 4], units: 1)
        XCTAssertEqual(try packet(absent, color: color).uniforms,
            try packet(absent, color: color, sourceTransparency: 0).uniforms)
        for invalid in [Float(-0.1), 1.1, .infinity, .nan] {
            XCTAssertThrowsError(try packet(absent, color: color, sourceTransparency: invalid))
        }
    }

    func testGPUBlendOneOneMinusAlphaRetainsZeroAlphaEmission() throws { try checkBlend(source: 1, destination: 10) }
    func testGPUBlendOneOneRetainsZeroAlphaEmission() throws { try checkBlend(source: 1, destination: 1) }
    func testGPUBlendSourceAlphaOneMinusAlphaUsesSourceAlphaTwice() throws { try checkBlend(source: 5, destination: 10) }
    func testGPUBlendSourceAlphaOneUsesFourthOriginalCombination() throws { try checkBlend(source: 5, destination: 1) }

    func testGPURGBOnlyColorMaskPreservesDestinationAlpha() throws {
        let device = try device(), clear = SIMD4<Float>(0.1, 0.2, 0.3, 0.6), source = SIMD4<Float>(0.2, 0.3, 0.1, 0.25)
        let draw = try draw(descriptor(colorMask: 14), color: source, device: device)
        var expected = source + clear * (1 - source.w); expected.w = clear.w
        assertColor(try render([draw], clear: clear, device: device), expected)
    }

    func testGPUOriginalDepthCompareAndDepthWriteAreHonored() throws {
        let device = try device(), clear = SIMD4<Float>(0, 0, 0, 0)
        let front = try draw(descriptor(zWrite: true), color: SIMD4(1, 0, 0, 1), device: device, z: 0.2)
        let behind = try draw(descriptor(zWrite: true), color: SIMD4(0, 1, 0, 1), device: device, z: 0.8)
        assertColor(try render([front, behind], clear: clear, device: device), SIMD4(1, 0, 0, 1))
        let noWrite = try draw(descriptor(zWrite: false), color: SIMD4(0, 0, 1, 1), device: device, z: 0.1)
        let middle = try draw(descriptor(zWrite: true), color: SIMD4(1, 1, 0, 1), device: device, z: 0.15)
        assertColor(try render([front, noWrite, middle], clear: clear, device: device), SIMD4(1, 1, 0, 1))
    }

    func testGPUOriginalCullModesRespectGeometryWinding() throws {
        let device = try device(), clear = SIMD4<Float>(0, 0, 0, 0), value = SIMD4<Float>(1, 0, 0, 1)
        let front = try draw(descriptor(cull: 2), color: value, device: device)
        let back = try draw(descriptor(cull: 1), color: value, device: device)
        let frontResult = try render([front], clear: clear, device: device)
        let backResult = try render([back], clear: clear, device: device)
        // Exactly one source face remains, and reversing native winding swaps it.
        assertColor(frontResult + backResult, value)
        let reversed = try draw(descriptor(cull: 2), color: value, device: device, clockwise: true)
        assertColor(try render([reversed], clear: clear, device: device), backResult)
    }

    func testGPUOrderedPacketsAreNotRegroupedByBlendState() throws {
        let device = try device(), a = SIMD4<Float>(0.1, 0.2, 0, 0.25), b = SIMD4<Float>(0, 0.1, 0.2, 0.2)
        let first = try draw(descriptor(source: 1, destination: 1), color: a, device: device)
        let second = try draw(descriptor(source: 5, destination: 10), color: b, device: device)
        let result = try render([first, second], clear: .zero, device: device)
        assertColor(result, b * b.w + a * (1 - b.w))
        let reverse = try render([second, first], clear: .zero, device: device)
        XCTAssertGreaterThan(simd_length(result - reverse), 0.02)
    }

    func testControlledSurfacePreservesSceneColorDepthAndGammaBlendsAtOneAndPlatformMSAASamples() throws {
        let device = try device(), scene = SCNScene(), cameraNode = SCNNode(), camera = SCNCamera()
        camera.zNear = 0.1; camera.zFar = 10; camera.fieldOfView = 90
        camera.projectionDirection = .vertical; camera.automaticallyAdjustsZRange = false
        cameraNode.camera = camera; scene.rootNode.addChildNode(cameraNode)
        let plane = SCNPlane(width: 4, height: 4), material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.15, green: 0.28, blue: 0.42, alpha: 1)
        material.lightingModel = .constant; material.isDoubleSided = true
        material.writesToDepthBuffer = true; material.readsFromDepthBuffer = true
        plane.materials = [material]
        let occluder = SCNNode(geometry: plane); occluder.position.z = -1
        scene.rootNode.addChildNode(occluder)
        let formats = try DuelTriadRenderSurface.formats(device: device)
        let packets = try DuelTriadMetalRenderer(device: device, formats: formats)
        let surface = try DuelTriadRenderSurface(device: device, scene: scene, pointOfView: cameraNode, packets: packets)
        defer { surface.shutdown(); packets.shutdown() }
        let projection = try DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: CGSize(width: 16, height: 16))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let targetDescription = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 16, height: 16, mipmapped: false)
        targetDescription.storageMode = .shared; targetDescription.usage = .renderTarget
        let target = try XCTUnwrap(device.makeTexture(descriptor: targetDescription))
        func result(samples: Int) throws -> SIMD4<Float> {
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            try surface.encodeFrame(to: target, atTick: 60, samples: samples, commandBuffer: command)
            command.commit(); command.waitUntilCompleted()
            XCTAssertEqual(command.status, .completed, String(describing: command.error))
            XCTAssertNil(packets.lastFailure); XCTAssertNil(surface.lastFailure)
            var bytes = [UInt8](repeating: 0, count: 16 * 16 * 4)
            bytes.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: 64,
                from: MTLRegionMake2D(0, 0, 16, 16), mipmapLevel: 0) }
            let offset = (8 * 16 + 8) * 4
            return SIMD4(Float(bytes[offset + 2]), Float(bytes[offset + 1]),
                Float(bytes[offset]), Float(bytes[offset + 3])) / 255
        }
        var previousScene: SIMD4<Float>?
        for samples in [1, 2] {
            let format = DuelTriadRenderSurface.format(samples: samples)
            packets.clear()
            let sceneColor = try result(samples: samples)
            // Flat interior colour must survive sRGB scene storage, unorm
            // reinterpretation and the final unorm copy without a second transfer.
            XCTAssertTrue((0.05...0.9).contains(sceneColor.x))
            XCTAssertTrue(sceneColor.x < sceneColor.y && sceneColor.y < sceneColor.z)
            XCTAssertEqual(sceneColor.w, 1, accuracy: 2.0 / 255)
            if let previousScene { assertColor(sceneColor, previousScene) }
            previousScene = sceneColor
            for pair in [(1, 10), (1, 1), (5, 10), (5, 1)] {
                let value = descriptor(source: pair.0, destination: pair.1)
                let factory = try factory(value, device: device, format: format)
                for alpha in [Float(0.25), 0] {
                    let sourceColor = SIMD4<Float>(0.20, 0.10, 0.05, alpha)
                    for z in [Float(-2), -0.5] {
                        let instance = try factory.make(id: "fixture", geometry: quad(z: z, extent: 3),
                            vertexStreams: [0, 1, 3, 4], units: 1)
                        let draw = try packet(instance, color: sourceColor, projection: projection)
                        try packets.submit(.init(format: format, draws: [draw]))
                        let observed = try result(samples: samples)
                        let mixed = sourceColor * (pair.0 == 1 ? 1 : alpha) + sceneColor * (pair.1 == 1 ? 1 : 1 - alpha)
                        let expected = z < -1 ? sceneColor : simd_clamp(mixed, .zero, SIMD4(repeating: 1))
                        assertColor(observed, expected)
                    }
                }
            }
            packets.clear(); assertColor(try result(samples: samples), sceneColor)
        }
    }
}
