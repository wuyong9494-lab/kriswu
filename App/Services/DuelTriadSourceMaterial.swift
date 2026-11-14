import Foundation
import Metal
import SceneKit
import simd

/// Original H17 equations live in digest-verified private Metal resources. This
/// adapter owns their data ABI and actual GPU blend/depth states; it never maps
/// premultiplied output to SceneKit's straight-alpha material mode.
enum DuelTriadSourceMaterial {
    enum Failure: Error, Equatable {
        case descriptor(String), resource(String), unavailableMetal
        case shader(String), geometry, frame, unsupportedFormat
    }

    struct Uniform: Codable, Sendable {
        let name: String
        let width: Int
        let defaultValue: [Float]?
    }
    struct Program: Codable, Sendable {
        let file: String
        let bytes: Int
        let sha256: String
        let vertexFunction: String
        let fragmentFunction: String
        let uniforms: [Uniform]
        let textures: [String]
        let layoutVersion: Int
    }
    struct Texture: Codable, Sendable {
        /// PNG is retained as an inspection artifact, not sampled by the GPU.
        let file: String
        let dataFile: String
        let width: Int
        let height: Int
        let sourceTextureFormat: Int
        let scale: [Float]
        let offset: [Float]
        let wrapS: Int
        let wrapT: Int
        let filter: Int
        let mip: Int
        let maxAnisotropy: Int
        /// Unity TextureColorSpace: Linear = 0, sRGB = 1.
        let sourceColorSpace: Int

        struct Level: Equatable, Sendable {
            let width, height, offset, bytes, bytesPerRow: Int
        }
        func levels() throws -> [Level] {
            guard (1...4096).contains(width), (1...4096).contains(height),
                  (1...16).contains(mip), [4, 45, 47].contains(sourceTextureFormat) else {
                throw Failure.descriptor("Original texture layout")
            }
            var result: [Level] = [], offset = 0, w = width, h = height
            for index in 0..<mip {
                guard index == 0 || result.last!.width > 1 || result.last!.height > 1 else {
                    throw Failure.descriptor("Extra texture mip level")
                }
                let row = sourceTextureFormat == 4 ? w * 4 : ((w + 3) / 4) * (sourceTextureFormat == 45 ? 8 : 16)
                let bytes = row * (sourceTextureFormat == 4 ? h : (h + 3) / 4)
                result.append(Level(width: w, height: h, offset: offset, bytes: bytes, bytesPerRow: row))
                offset += bytes; w = max(1, w / 2); h = max(1, h / 2)
            }
            guard offset <= 8_000_000 else { throw Failure.descriptor("Texture byte limit") }
            return result
        }
        func pixelFormat(projectColorSpace: Int) -> MTLPixelFormat {
            // Unity imports may be marked sRGB even in a Gamma project. Only a
            // Linear project requests the corresponding sampling conversion.
            let srgb = projectColorSpace == 1 && sourceColorSpace == 1
            switch sourceTextureFormat {
            case 4: return srgb ? .rgba8Unorm_srgb : .rgba8Unorm
            case 45: return srgb ? .etc2_rgb8_srgb : .etc2_rgb8
            default: return srgb ? .eac_rgba8_srgb : .eac_rgba8
            }
        }
        func effectiveMaxAnisotropy(projectFiltering: Int) throws -> Int {
            switch projectFiltering {
            case 0: return 1
            case 1: return max(1, maxAnisotropy)
            default: throw Failure.descriptor("Unverified project anisotropy mode")
            }
        }
    }
    struct Raster: Codable, Equatable, Sendable {
        let source: Int
        let destination: Int
        let cull: Int
        let zWrite: Bool
        let zTest: Int
        /// Unity ColorWriteMask bits: R=8, G=4, B=2, A=1.
        let colorMask: Int

        func validate() throws {
            guard [1, 5].contains(source), [1, 10].contains(destination),
                  (0...2).contains(cull), (0...8).contains(zTest), (0...15).contains(colorMask) else {
                throw Failure.descriptor("raster")
            }
        }
        var sourceFactor: MTLBlendFactor { source == 1 ? .one : .sourceAlpha }
        var destinationFactor: MTLBlendFactor { destination == 1 ? .one : .oneMinusSourceAlpha }
        var cullMode: MTLCullMode { cull == 0 ? .none : cull == 1 ? .front : .back }
        var depthFunction: MTLCompareFunction {
            // Unity CompareFunction, with reverse-Z deliberately disabled.
            switch zTest {
            case 0, 8: return .always
            case 1: return .never
            case 2: return .less
            case 3: return .equal
            case 4: return .lessEqual
            case 5: return .greater
            case 6: return .notEqual
            case 7: return .greaterEqual
            default: return .never
            }
        }
        func configure(_ attachment: MTLRenderPipelineColorAttachmentDescriptor) {
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = sourceFactor
            attachment.sourceAlphaBlendFactor = sourceFactor
            attachment.destinationRGBBlendFactor = destinationFactor
            attachment.destinationAlphaBlendFactor = destinationFactor
            var channels: MTLColorWriteMask = []
            if colorMask & 8 != 0 { channels.insert(.red) }
            if colorMask & 4 != 0 { channels.insert(.green) }
            if colorMask & 2 != 0 { channels.insert(.blue) }
            if colorMask & 1 != 0 { channels.insert(.alpha) }
            attachment.writeMask = channels
        }
    }
    struct Descriptor: Codable, Sendable {
        let sourceName: String
        let shaderPathID: String
        let sourceShaderSHA256: String
        let variantSHA256: String
        /// PlayerSettings.m_ActiveColorSpace: Gamma = 0, Linear = 1.
        let projectColorSpace: Int
        /// Explicit exported project quality choice, independent of the
        /// texture importer's anisotropy request. 0=disabled, 1=per-texture.
        let projectAnisotropicFiltering: Int
        let keywords: [String]
        let floats: [String: Float]
        let colors: [String: [Float]]
        let textures: [String: Texture]
        let program: Program
        let raster: Raster

        func validate() throws {
            guard !sourceName.isEmpty, sourceName.utf8.count <= 256,
                  shaderPathID.range(of: "^-?[0-9]{1,20}$", options: .regularExpression) != nil,
                  digest(sourceShaderSHA256), digest(variantSHA256), (0...1).contains(projectColorSpace),
                  (0...1).contains(projectAnisotropicFiltering),
                  keywords.count <= 64, Set(keywords).count == keywords.count,
                  keywords.allSatisfy(symbol), floats.count <= 128, colors.count <= 64,
                  textures.count <= 16, floats.allSatisfy({ symbol($0.key) && $0.value.isFinite }),
                  colors.allSatisfy({ symbol($0.key) && $0.value.count == 4 && $0.value.allSatisfy(\.isFinite) }),
                  program.layoutVersion == 1, basename(program.file), program.file.hasSuffix(".metal"),
                  (1...256_000).contains(program.bytes), digest(program.sha256),
                  function(program.vertexFunction), function(program.fragmentFunction),
                  program.vertexFunction != program.fragmentFunction,
                  program.uniforms.count <= 64, Set(program.uniforms.map(\.name)).count == program.uniforms.count,
                  program.uniforms.allSatisfy({ symbol($0.name) && (1...4).contains($0.width) &&
                      ($0.defaultValue.map { $0.count == 4 && $0.allSatisfy(\.isFinite) } ?? true) }),
                  program.textures.count <= 8, Set(program.textures).count == program.textures.count,
                  program.textures.allSatisfy({ symbol($0) && textures[$0] != nil }) else {
                throw Failure.descriptor(sourceName)
            }
            try raster.validate()
            for (name, texture) in textures {
                guard symbol(name), basename(texture.file), texture.file.hasSuffix(".png"),
                      basename(texture.dataFile), texture.dataFile.hasSuffix(".texture"),
                      texture.scale.count == 2, texture.offset.count == 2,
                      texture.scale.allSatisfy(\.isFinite), texture.offset.allSatisfy(\.isFinite),
                      (0...3).contains(texture.wrapS), (0...3).contains(texture.wrapT),
                      (0...2).contains(texture.filter), (1...16).contains(texture.mip),
                      (0...16).contains(texture.maxAnisotropy), (0...1).contains(texture.sourceColorSpace) else {
                    throw Failure.descriptor(name)
                }
                _ = try texture.levels()
            }
            _ = try materialUniforms()
        }

        func materialUniforms() throws -> [SIMD4<Float>] {
            try program.uniforms.map { uniform in
                if uniform.name.hasSuffix("_ST"),
                   let texture = textures[String(uniform.name.dropLast(3))] {
                    return SIMD4(texture.scale[0], texture.scale[1], texture.offset[0], texture.offset[1])
                }
                if uniform.width == 1, let value = floats[uniform.name] {
                    return SIMD4(value, 0, 0, 0)
                }
                if let value = colors[uniform.name], value.count == 4 {
                    return SIMD4(value[0], value[1], value[2], value[3])
                }
                if let value = uniform.defaultValue, value.count == 4 {
                    return SIMD4(value[0], value[1], value[2], value[3])
                }
                throw Failure.descriptor("Missing original uniform: " + uniform.name)
            }
        }
    }

    /// Source mesh data after the exporter has reflected Z, flipped UV V and
    /// converted positions to SceneKit units. Indices must have matching winding.
    struct Geometry: Sendable {
        let positions: [Float]
        let normals: [Float]
        let uv: [Float]
        let uv1: [Float]?
        let colors: [Float]?
        let tangents: [Float]?
        let indices: [UInt32]
        var clockwise = false
    }

    struct StreamLayout: Equatable, Sendable {
        /// Sixteen selectors for four TEXCOORD registers; 0/1 are constants,
        /// 2...5 UV0/UV1, 6...9 Custom1, 10...13 Custom2, 14...17 StableRandom.
        let selectors: [SIMD4<Float>]
        let hasNormal: Bool
        let hasTangent: Bool
        let hasColor: Bool
        init(_ streams: [Int]) throws {
            guard !streams.isEmpty, streams.count <= 12, streams.first == 0,
                  Set(streams).count == streams.count else { throw Failure.geometry }
            var packed: [Float] = []
            for stream in streams {
                switch stream {
                case 0, 1, 2, 3: break
                case 4: packed += [2, 3]
                case 5: packed += [4, 5]
                case 31...34: packed += (0..<(stream - 30)).map { Float(6 + $0) }
                case 35...38: packed += (0..<(stream - 34)).map { Float(10 + $0) }
                case 26: packed += [14, 15, 16, 17]
                default: throw Failure.descriptor("Unsupported original vertex stream \(stream)")
                }
            }
            guard packed.count <= 16 else { throw Failure.geometry }
            // Unity supplies zero for missing components and one for missing W.
            var values = (0..<16).map { Float($0 % 4 == 3 ? 1 : 0) }
            for (index, value) in packed.enumerated() { values[index] = value }
            selectors = stride(from: 0, to: 16, by: 4).map {
                SIMD4(values[$0], values[$0 + 1], values[$0 + 2], values[$0 + 3])
            }
            hasNormal = streams.contains(1); hasTangent = streams.contains(2); hasColor = streams.contains(3)
        }
    }

    struct Format: Hashable, Sendable {
        let color: MTLPixelFormat
        let depth: MTLPixelFormat
        let stencil: MTLPixelFormat
        let samples: Int
    }
    private struct Vertex {
        var position, normal, tangent, color, uv0, uv1: SIMD4<Float>
    }

    @MainActor
    final class Factory {
        let device: MTLDevice
        private let descriptors: [String: Descriptor]
        private let prepared: [String: Prepared]
        private let textureData: [String: Data]
        private var cachedTextures: [String: MTLTexture] = [:]
        private var cachedSamplers: [String: MTLSamplerState] = [:]
        private struct GeometryBuffers {
            let vertex, index: MTLBuffer
            let indexCount: Int
        }
        private var cachedGeometry: [String: GeometryBuffers] = [:]
        private(set) var geometryBufferBytes = 0
        var geometryBufferCount: Int { cachedGeometry.count }

        init(materials: [String: Descriptor], programData: [String: Data], textureData: [String: Data],
             device: MTLDevice?, formats: [Format]) throws {
            guard let device, !formats.isEmpty, formats.count <= 4,
                  !materials.isEmpty, materials.count <= 128,
                  Set(formats).count == formats.count else { throw Failure.unavailableMetal }
            self.device = device; descriptors = materials; self.textureData = textureData
            var libraries: [String: MTLLibrary] = [:], values: [String: Prepared] = [:]
            for (id, descriptor) in materials.sorted(by: { $0.key < $1.key }) {
                try descriptor.validate()
                guard let data = programData[descriptor.program.file], data.count == descriptor.program.bytes,
                      DuelNetworkContentRecord.digest(data) == descriptor.program.sha256,
                      let source = String(data: data, encoding: .utf8) else {
                    throw Failure.resource(descriptor.program.file)
                }
                let library: MTLLibrary
                if let cached = libraries[descriptor.program.sha256] { library = cached }
                else {
                    let options = MTLCompileOptions(); options.fastMathEnabled = false
                    do { library = try device.makeLibrary(source: source, options: options) }
                    catch { throw Failure.shader(descriptor.program.file + ": " + String(describing: error)) }
                    libraries[descriptor.program.sha256] = library
                }
                guard let vertex = library.makeFunction(name: descriptor.program.vertexFunction),
                      let fragment = library.makeFunction(name: descriptor.program.fragmentFunction) else {
                    throw Failure.shader(descriptor.program.file)
                }
                var pipelines: [Format: MTLRenderPipelineState] = [:]
                for format in formats {
                    guard [1, 2, 4].contains(format.samples), device.supportsTextureSampleCount(format.samples),
                          format.color != .invalid else { throw Failure.unsupportedFormat }
                    // A Gamma source blends encoded values. An sRGB render
                    // attachment would instead decode the destination before
                    // blending, changing the original equation's operands.
                    if descriptor.projectColorSpace == 0 {
                        guard [.rgba8Unorm, .bgra8Unorm].contains(format.color) else {
                            throw Failure.unsupportedFormat
                        }
                    }
                    let pipeline = MTLRenderPipelineDescriptor()
                    pipeline.label = "Original H17 " + descriptor.sourceName
                    pipeline.vertexFunction = vertex; pipeline.fragmentFunction = fragment
                    pipeline.rasterSampleCount = format.samples
                    pipeline.isAlphaToCoverageEnabled = false
                    pipeline.colorAttachments[0].pixelFormat = format.color
                    descriptor.raster.configure(pipeline.colorAttachments[0])
                    pipeline.depthAttachmentPixelFormat = format.depth
                    pipeline.stencilAttachmentPixelFormat = format.stencil
                    do { pipelines[format] = try device.makeRenderPipelineState(descriptor: pipeline) }
                    catch { throw Failure.shader(descriptor.program.file + ": " + String(describing: error)) }
                }
                let depth = MTLDepthStencilDescriptor()
                depth.depthCompareFunction = descriptor.raster.depthFunction
                depth.isDepthWriteEnabled = descriptor.raster.zWrite
                guard let state = device.makeDepthStencilState(descriptor: depth) else { throw Failure.unavailableMetal }
                values[id] = Prepared(pipelines: pipelines, depth: state, raster: descriptor.raster,
                    materialUniforms: try descriptor.materialUniforms(),
                    transparencyUniform: descriptor.program.uniforms.firstIndex {
                        $0.name == "_Transparent" && $0.width == 1
                    })
            }
            prepared = values
            // Decode every actually sampled texture at preparation, so missing
            // images or unsupported sampler state cannot fail during a fight.
            for descriptor in materials.values {
                for name in descriptor.program.textures {
                    guard let texture = descriptor.textures[name] else { throw Failure.resource(name) }
                    _ = try loadTexture(texture, projectColorSpace: descriptor.projectColorSpace)
                    _ = try loadSampler(texture, projectFiltering: descriptor.projectAnisotropicFiltering)
                }
            }
        }

        func make(id: String, geometry: Geometry, vertexStreams: [Int], units: Float,
                  cacheGeometry: Bool = true) throws -> Instance {
            guard let descriptor = descriptors[id], let resource = prepared[id], units.isFinite,
                  (0.0001...1).contains(units) else { throw Failure.descriptor(id) }
            let layout = try StreamLayout(vertexStreams)
            let count = geometry.positions.count / 3
            guard (3...50_000).contains(count), geometry.positions.count == count * 3,
                  geometry.normals.count == count * 3, geometry.uv.count == count * 2,
                  geometry.positions.allSatisfy(\.isFinite), geometry.normals.allSatisfy(\.isFinite),
                  geometry.uv.allSatisfy(\.isFinite),
                  geometry.uv1.map({ $0.count == count * 2 && $0.allSatisfy(\.isFinite) }) ?? true,
                  geometry.colors.map({ $0.count == count * 4 && $0.allSatisfy(\.isFinite) }) ?? true,
                  geometry.tangents.map({ $0.count == count * 4 && $0.allSatisfy(\.isFinite) }) ?? true,
                  !geometry.indices.isEmpty, geometry.indices.count <= 150_000,
                  geometry.indices.count % 3 == 0, geometry.indices.allSatisfy({ Int($0) < count }) else {
                throw Failure.geometry
            }
            func vector(_ values: [Float], _ i: Int, _ width: Int, _ w: Float) -> SIMD4<Float> {
                .init(values[i * width], values[i * width + 1], width >= 3 ? values[i * width + 2] : 0,
                      width == 4 ? values[i * width + 3] : w)
            }
            let vertices = (0..<count).map { i in
                Vertex(position: vector(geometry.positions, i, 3, 1), normal: vector(geometry.normals, i, 3, 0),
                    tangent: geometry.tangents.map { vector($0, i, 4, 1) } ?? SIMD4(0, 0, 0, -1),
                    color: geometry.colors.map { vector($0, i, 4, 1) } ?? SIMD4(repeating: 1),
                    uv0: vector(geometry.uv, i, 2, 1),
                    uv1: geometry.uv1.map { vector($0, i, 2, 1) } ?? SIMD4(0, 1, 0, 1))
            }
            let vertexData = vertices.withUnsafeBytes { Data($0) }
            let indexData = geometry.indices.withUnsafeBytes { Data($0) }
            let key = cacheGeometry ? DuelNetworkContentRecord.digest(vertexData) + DuelNetworkContentRecord.digest(indexData) : ""
            let buffers: GeometryBuffers
            if cacheGeometry, let existing = cachedGeometry[key] { buffers = existing }
            else {
                guard (!cacheGeometry || (cachedGeometry.count < 256 && geometryBufferBytes + vertexData.count + indexData.count <= 32_000_000)),
                      let vertex = vertexData.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }),
                      let index = indexData.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }) else {
                    throw Failure.unavailableMetal
                }
                buffers = GeometryBuffers(vertex: vertex, index: index, indexCount: geometry.indices.count)
                if cacheGeometry {
                    cachedGeometry[key] = buffers; geometryBufferBytes += vertexData.count + indexData.count
                }
            }
            let textures = try descriptor.program.textures.map {
                try loadTexture(descriptor.textures[$0]!, projectColorSpace: descriptor.projectColorSpace)
            }
            let samplers = try descriptor.program.textures.map {
                try loadSampler(descriptor.textures[$0]!, projectFiltering: descriptor.projectAnisotropicFiltering)
            }
            return Instance(name: descriptor.sourceName, resource: resource, vertex: buffers.vertex, index: buffers.index,
                indexCount: buffers.indexCount, textures: textures, samplers: samplers, layout: layout,
                units: units, winding: geometry.clockwise ? .clockwise : .counterClockwise)
        }

        private func loadTexture(_ specification: Texture, projectColorSpace: Int) throws -> MTLTexture {
            let pixelFormat = specification.pixelFormat(projectColorSpace: projectColorSpace)
            let key = specification.dataFile + "|\(pixelFormat.rawValue)|\(specification.width)|\(specification.height)|\(specification.mip)"
            if let value = cachedTextures[key] { return value }
            let levels = try specification.levels()
            guard let data = textureData[specification.dataFile], let last = levels.last,
                  data.count == last.offset + last.bytes else { throw Failure.resource(specification.dataFile) }
            let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                width: specification.width, height: specification.height, mipmapped: specification.mip > 1)
            description.mipmapLevelCount = specification.mip
            description.storageMode = .shared; description.usage = .shaderRead
            guard let value = device.makeTexture(descriptor: description) else { throw Failure.resource(specification.dataFile) }
            // Preserve every original compressed block and mip level. Source
            // rows retain Unity's origin; the private program samples source UV
            // directly. No PNG conversion, premultiplication or generated mip.
            data.withUnsafeBytes { bytes in
                for (index, level) in levels.enumerated() {
                    value.replace(region: MTLRegionMake2D(0, 0, level.width, level.height), mipmapLevel: index,
                        withBytes: bytes.baseAddress!.advanced(by: level.offset), bytesPerRow: level.bytesPerRow)
                }
            }
            cachedTextures[key] = value; return value
        }
        private func loadSampler(_ specification: Texture, projectFiltering: Int) throws -> MTLSamplerState {
            let anisotropy = try specification.effectiveMaxAnisotropy(projectFiltering: projectFiltering)
            let key = "\(specification.wrapS)|\(specification.wrapT)|\(specification.filter)|\(specification.mip)|\(anisotropy)"
            if let value = cachedSamplers[key] { return value }
            func address(_ value: Int) -> MTLSamplerAddressMode {
                switch value { case 0: return .repeat; case 1: return .clampToEdge
                case 2: return .mirrorRepeat; default: return .mirrorClampToEdge }
            }
            let sampler = MTLSamplerDescriptor()
            sampler.sAddressMode = address(specification.wrapS); sampler.tAddressMode = address(specification.wrapT)
            sampler.minFilter = specification.filter == 0 ? .nearest : .linear
            sampler.magFilter = sampler.minFilter
            sampler.mipFilter = specification.mip == 1 ? .notMipmapped : specification.filter == 2 ? .linear : .nearest
            sampler.maxAnisotropy = anisotropy
            sampler.lodMaxClamp = Float(specification.mip - 1)
            guard let value = device.makeSamplerState(descriptor: sampler) else { throw Failure.resource("sampler") }
            cachedSamplers[key] = value; return value
        }
    }

    fileprivate struct Prepared {
        let pipelines: [Format: MTLRenderPipelineState]
        let depth: MTLDepthStencilState
        let raster: Raster
        let materialUniforms: [SIMD4<Float>]
        let transparencyUniform: Int?
    }

    @MainActor
    final class Instance {
        /// Spatial placeholder only. Source output is drawn once by Metal.
        let material: SCNMaterial
        private let resource: Prepared
        private let vertex, index: MTLBuffer
        private let indexCount: Int
        private let textures: [MTLTexture]
        private let samplers: [MTLSamplerState]
        private let layout: StreamLayout
        private let units: Float
        private let winding: MTLWinding
        fileprivate init(name: String, resource: Prepared, vertex: MTLBuffer, index: MTLBuffer, indexCount: Int,
                         textures: [MTLTexture], samplers: [MTLSamplerState], layout: StreamLayout,
                         units: Float, winding: MTLWinding) {
            material = SCNMaterial(); material.name = "duel.triad.source." + name
            material.colorBufferWriteMask = []; material.writesToDepthBuffer = false
            material.readsFromDepthBuffer = false
            self.resource = resource; self.vertex = vertex; self.index = index; self.indexCount = indexCount
            self.textures = textures; self.samplers = samplers; self.layout = layout; self.units = units; self.winding = winding
        }

        func packet(modelTransform: simd_float4x4, viewTransform: simd_float4x4,
                    projectionTransform: simd_float4x4, cameraPosition: SIMD3<Float>, tick: Int,
                    color: SIMD4<Float>, custom1: SIMD4<Float>, custom2: SIMD4<Float>,
                    stableRandom: SIMD4<Float>, uvTransform: SIMD4<Float>,
                    sourceTransparency: Float? = nil) throws -> Draw {
            var materialUniforms = resource.materialUniforms
            if let sourceTransparency {
                guard sourceTransparency.isFinite, (0...1).contains(sourceTransparency) else { throw Failure.frame }
                // The source StopFrames tween only sets this declared scalar.
                // It neither creates a missing property nor fades vertex RGBA.
                if let index = resource.transparencyUniform { materialUniforms[index].x = sourceTransparency }
            }
            let uniforms = try Self.uniformData(modelTransform: modelTransform, viewTransform: viewTransform,
                projectionTransform: projectionTransform, cameraPosition: cameraPosition, tick: tick,
                color: color, custom1: custom1, custom2: custom2, stableRandom: stableRandom,
                uvTransform: uvTransform, units: units, layout: layout, material: materialUniforms)
            return Draw(pipelines: resource.pipelines, depth: resource.depth, cull: resource.raster.cullMode,
                winding: winding, vertex: vertex, index: index, indexCount: indexCount, textures: textures,
                samplers: samplers, uniforms: uniforms)
        }

        static func uniformData(modelTransform: simd_float4x4, viewTransform: simd_float4x4,
                                projectionTransform: simd_float4x4, cameraPosition: SIMD3<Float>, tick: Int,
                                color: SIMD4<Float>, custom1: SIMD4<Float>, custom2: SIMD4<Float>,
                                stableRandom: SIMD4<Float>, uvTransform: SIMD4<Float>, units: Float,
                                layout: StreamLayout, material: [SIMD4<Float>]) throws -> Data {
            guard tick >= 0, tick <= 2_160_000, units.isFinite, units > 0, material.count <= 64,
                  [modelTransform, viewTransform, projectionTransform].allSatisfy(finite),
                  abs(simd_determinant(modelTransform)) > 1e-12,
                  [color, custom1, custom2, stableRandom, uvTransform, SIMD4(cameraPosition, 1)].allSatisfy(finite),
                  material.allSatisfy(finite) else { throw Failure.frame }
            // S maps original Unity world coordinates to the exported SceneKit
            // coordinates. View-space uses uniform positive scaling, retaining
            // the camera's handedness and original CamOffset distance unit.
            let s = simd_float4x4(diagonal: SIMD4(units, units, -units, 1))
            let si = simd_float4x4(diagonal: SIMD4(1 / units, 1 / units, -1 / units, 1))
            let d = simd_float4x4(diagonal: SIMD4(units, units, units, 1))
            let di = simd_float4x4(diagonal: SIMD4(1 / units, 1 / units, 1 / units, 1))
            let model = si * modelTransform * s
            let view = di * viewTransform * s
            let projection = projectionTransform * d
            let matrices = [model, simd_inverse(model), view, projection, projection * view]
            var values = [SIMD4<Float>](repeating: .zero, count: 96)
            for (i, matrix) in matrices.enumerated() {
                for j in 0..<4 { values[i * 4 + j] = matrix[j] }
            }
            values[20] = si * SIMD4(cameraPosition, 1)
            let seconds = Float(tick) / 60
            values[21] = SIMD4(seconds / 20, seconds, seconds * 2, seconds * 3)
            values[22] = color; values[23] = custom1; values[24] = custom2; values[25] = stableRandom
            values[26] = uvTransform
            values[27] = SIMD4(units, layout.hasNormal ? 1 : 0, layout.hasTangent ? 1 : 0, layout.hasColor ? 1 : 0)
            for i in 0..<4 { values[28 + i] = layout.selectors[i] }
            for (i, value) in material.enumerated() { values[32 + i] = value }
            guard values.allSatisfy(finite) else { throw Failure.frame }
            return values.withUnsafeBytes { Data($0) }
        }
    }

    /// Immutable snapshot. Its Metal resources are prepared once; encoding only
    /// reads them and may run on SceneKit's render thread.
    struct Draw: @unchecked Sendable {
        let pipelines: [Format: MTLRenderPipelineState]
        let depth: MTLDepthStencilState
        let cull: MTLCullMode
        let winding: MTLWinding
        let vertex, index: MTLBuffer
        let indexCount: Int
        let textures: [MTLTexture]
        let samplers: [MTLSamplerState]
        let uniforms: Data

        func encode(on encoder: MTLRenderCommandEncoder, format: Format) throws {
            guard let pipeline = pipelines[format], uniforms.count == 96 * 16 else { throw Failure.unsupportedFormat }
            encoder.setRenderPipelineState(pipeline)
            encoder.setDepthStencilState(depth); encoder.setCullMode(cull); encoder.setFrontFacing(winding)
            encoder.setDepthBias(0, slopeScale: 0, clamp: 0)
            encoder.setDepthClipMode(.clip); encoder.setTriangleFillMode(.fill)
            encoder.setVertexBuffer(vertex, offset: 0, index: 0)
            uniforms.withUnsafeBytes { bytes in
                encoder.setVertexBytes(bytes.baseAddress!, length: bytes.count, index: 2)
                encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 2)
            }
            for i in textures.indices {
                encoder.setFragmentTexture(textures[i], index: i)
                encoder.setFragmentSamplerState(samplers[i], index: i)
            }
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32,
                indexBuffer: index, indexBufferOffset: 0)
        }
    }

    private static func digest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isASCII && ("0123456789abcdef".contains($0)) }
    }
    private static func basename(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil && !value.contains("..")
    }
    private static func symbol(_ value: String) -> Bool {
        value.range(of: "^_[A-Za-z0-9_]{1,95}$", options: .regularExpression) != nil
    }
    private static func function(_ value: String) -> Bool {
        value.range(of: "^triad_[a-z0-9_]{1,96}$", options: .regularExpression) != nil
    }
    static func finite(_ value: SIMD4<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
    }
    static func finite(_ value: simd_float4x4) -> Bool {
        (0..<4).allSatisfy { finite(value[$0]) }
    }
}
