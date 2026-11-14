import Foundation
import Metal
import SceneKit
import simd

/// The source projector is independent of the actor's visible material. It
/// draws ordered silhouettes into one non-depth target, applies its five-tap
/// filter once, then multiplies the recovered receiver in Gamma space. In
/// particular, MORPH's per-pixel mask is not a shadow-caster mask.
///
/// Native source: NIDJDKJNBMJ 23564/23565/23570/23574/23575; HideModel's
/// 38405 writes actorValue=1-progress and 23565 uploads 1-clamp(actorValue).
/// The implementation below is an adapter, not an embedded original shader.
@MainActor
final class DuelSourceProjectedShadowRenderer {
    typealias Format = DuelTriadMetalRenderer.Format
    enum Failure: Error, Equatable {
        case device, format, allocation, geometry, skin, transform, clock, stopped, queue
        case shader(String)
    }

    struct FrameInfo {
        let tick: Int
        let aspect: Float
        let sourceCameraPosition: SIMD3<Float>
        let sourceView: simd_float4x4
        let sourceProjection: simd_float4x4
        let sourceShadowMatrix: simd_float4x4
        let casterCount: Int
        let triangleCount: Int
        let factors: [Float]
    }

    private struct Vertex {
        let position: SIMD4<Float>
        let weights: SIMD4<Float>
        let joints: SIMD4<UInt32>
    }
    private struct CasterUniforms {
        let clipFromWorld: simd_float4x4
        let factor: SIMD4<Float>
    }
    private struct ReceiverUniforms {
        let clipFromLocal: simd_float4x4
        let sourceObjectToWorld: simd_float4x4
        let shadowRow0: SIMD4<Float>
        let shadowRow1: SIMD4<Float>
        let color: SIMD4<Float>
    }
    private struct Element {
        let indices: MTLBuffer
        let count: Int
    }
    private struct Part {
        let holder: SCNNode
        let skin: SCNSkinner
        let geometry: SCNGeometry
        let vertices: MTLBuffer
        let elements: [Element]
        let inverseBinds: [simd_float4x4]
        let baseBind: simd_float4x4
        let bones: [SCNNode]
    }
    private struct Caster {
        let root: SCNNode
        let parts: [Part]
        let originalFlags: [(SCNNode, Bool)]
    }
    private struct Packet {
        let part: Part
        let bones: MTLBuffer
        let factor: Float
    }
    private struct Snapshot {
        let tick: Int
        let sourceCameraPosition: SIMD3<Float>
        let sourceView: simd_float4x4
        let worldToSource: simd_float4x4
        let receiverWorld: simd_float4x4
        let packets: [Packet]
        let factors: [Float]
        let casterIDs: [ObjectIdentifier]
        let visibility: [Bool]
    }
    private struct CameraSample {
        let tick: Int
        let position: SIMD3<Float>
        let view: simd_float4x4
    }

    let definition: DuelSourceProjectedShadowDefinition
    let rawMap: MTLTexture
    let blurredMap: MTLTexture
    private let gpu: MTLDevice
    private let stage: DuelSourceProjectedShadowDefinition.BoundStage
    private let mainCasters: [Caster]
    private let worldCenters: () throws -> [SIMD3<Float>]
    private let fade: (Int) -> Float
    private let additionalModels: () -> [GLTFModel.Instance]
    private var additional: [ObjectIdentifier: Caster] = [:]
    private let casterPipeline: MTLRenderPipelineState
    private let blurPipeline: MTLRenderPipelineState
    private let receiverPipelines: [Format: MTLRenderPipelineState]
    private let receiverVertices: MTLBuffer
    private let receiverIndices: MTLBuffer
    private let receiverIndexCount: Int
    private let receiverDepth: MTLDepthStencilState
    private let sampler: MTLSamplerState
    private var snapshot: Snapshot?
    private var cameraSample: CameraSample?
    private var previousRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var commandQueue: ObjectIdentifier?
    private var stopped = false
    private(set) var lastFrame: FrameInfo?

    init(device: MTLDevice, formats: [Format], definition: DuelSourceProjectedShadowDefinition,
         stageRoot: SCNNode, actors: [GLTFModel.Instance],
         worldCenters: @escaping () throws -> [SIMD3<Float>],
         fade: @escaping (Int) -> Float,
         additionalModels: @escaping () -> [GLTFModel.Instance] = { [] }) throws {
        try definition.validate()
        guard actors.count == 2, actors[0].root !== actors[1].root else { throw Failure.geometry }
        guard !formats.isEmpty, formats.count <= 4, Set(formats).count == formats.count,
              formats.allSatisfy({ [.bgra8Unorm, .rgba8Unorm].contains($0.color) &&
                  [1, 2, 4].contains($0.samples) && device.supportsTextureSampleCount($0.samples) }) else {
            throw Failure.format
        }
        let stage = try definition.bindStage(stageRoot)
        let casters = try actors.map { try Self.makeCaster($0, device: device) }
        let options = MTLCompileOptions(); options.fastMathEnabled = false
        let library: MTLLibrary
        do { library = try device.makeLibrary(source: Self.program, options: options) }
        catch { throw Failure.shader(String(describing: error)) }
        func function(_ name: String) throws -> MTLFunction {
            guard let value = library.makeFunction(name: name) else { throw Failure.shader(name) }
            return value
        }
        let casterVertex = try function("projected_caster_vertex")
        let casterFragment = try function("projected_caster_fragment")
        let blurVertex = try function("projected_blur_vertex")
        let blurFragment = try function("projected_blur_fragment")
        let receiverVertex = try function("projected_receiver_vertex")
        let receiverFragment = try function("projected_receiver_fragment")

        // These are the source's ordered supported-format candidates. Metal's
        // R8 target is available on the supported Apple families; a device
        // which cannot allocate it must try the original next format.
        var targets: (MTLTexture, MTLTexture, MTLRenderPipelineState, MTLRenderPipelineState)?
        let sourceFormats: [MTLPixelFormat] = [.r8Unorm, .b5g6r5Unorm, .bgra8Unorm]
        for format in sourceFormats {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                width: definition.map.width, height: definition.map.height, mipmapped: false)
            descriptor.storageMode = .private; descriptor.usage = [.renderTarget, .shaderRead]
            guard let raw = device.makeTexture(descriptor: descriptor),
                  let blurred = device.makeTexture(descriptor: descriptor) else { continue }
            let cast = MTLRenderPipelineDescriptor()
            cast.vertexFunction = casterVertex; cast.fragmentFunction = casterFragment
            cast.colorAttachments[0].pixelFormat = format; cast.rasterSampleCount = 1
            let blur = MTLRenderPipelineDescriptor()
            blur.vertexFunction = blurVertex; blur.fragmentFunction = blurFragment
            blur.colorAttachments[0].pixelFormat = format; blur.rasterSampleCount = 1
            do {
                targets = (raw, blurred, try device.makeRenderPipelineState(descriptor: cast),
                    try device.makeRenderPipelineState(descriptor: blur))
                break
            } catch {
                // Compilation errors are not an unsupported-texture fallback.
                throw Failure.shader(String(describing: error))
            }
        }
        guard let targets else { throw Failure.allocation }
        targets.0.label = "Source ordered shadow silhouettes"
        targets.1.label = "Source single five-tap shadow"
        var receivers: [Format: MTLRenderPipelineState] = [:]
        for format in formats {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = receiverVertex; descriptor.fragmentFunction = receiverFragment
            descriptor.rasterSampleCount = format.samples
            descriptor.depthAttachmentPixelFormat = format.depth
            descriptor.stencilAttachmentPixelFormat = format.stencil
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = format.color; color.isBlendingEnabled = true
            color.rgbBlendOperation = .add; color.alphaBlendOperation = .add
            color.sourceRGBBlendFactor = .destinationColor; color.destinationRGBBlendFactor = .zero
            color.sourceAlphaBlendFactor = .destinationAlpha; color.destinationAlphaBlendFactor = .zero
            do { receivers[format] = try device.makeRenderPipelineState(descriptor: descriptor) }
            catch { throw Failure.shader(String(describing: error)) }
        }
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .lessEqual; depth.isDepthWriteEnabled = false
        let sample = MTLSamplerDescriptor()
        sample.minFilter = .linear; sample.magFilter = .linear; sample.mipFilter = .notMipmapped
        sample.sAddressMode = .clampToEdge; sample.tAddressMode = .clampToEdge
        sample.rAddressMode = .clampToEdge; sample.maxAnisotropy = 1
        guard let depthState = device.makeDepthStencilState(descriptor: depth),
              let sampler = device.makeSamplerState(descriptor: sample) else { throw Failure.allocation }
        let positions = definition.receiver.geometry.positions.map { SIMD4<Float>($0[0], $0[1], $0[2], 1) }
        let indices = definition.receiver.geometry.indices
        self.gpu = device; self.definition = definition; self.stage = stage; self.mainCasters = casters
        self.worldCenters = worldCenters; self.fade = fade; self.additionalModels = additionalModels
        self.rawMap = targets.0; self.blurredMap = targets.1
        self.casterPipeline = targets.2; self.blurPipeline = targets.3
        self.receiverPipelines = receivers; self.receiverDepth = depthState; self.sampler = sampler
        self.receiverVertices = try Self.buffer(positions, device: device)
        self.receiverIndices = try Self.buffer(indices, device: device); self.receiverIndexCount = indices.count
        // Only a fully prepared replacement may disable the prototype shadow.
        for caster in casters { for (node, _) in caster.originalFlags { node.castsShadow = false } }
    }

    /// One source-state snapshot per authoritative tick. A duplicate display
    /// refresh may change viewport aspect, but cannot advance the source's
    /// previous-forward camera state, fade, skinning, or model registrations.
    func encodeMap(on command: MTLCommandBuffer, viewportSize: CGSize, tick: Int) throws {
        try check(command)
        guard (0...2_160_000).contains(tick), viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0 else { throw Failure.clock }
        let aspect = Float(viewportSize.width / viewportSize.height)
        guard aspect.isFinite, aspect > 0, aspect <= 100 else { throw Failure.transform }
        let frame = try sample(tick: tick)
        let projection = Self.orthographic(size: definition.camera.orthographicSize,
            aspect: aspect, near: definition.camera.nearClip, far: definition.camera.farClip)
        let sourcePV = projection * frame.sourceView
        let bias = Self.matrix(definition.camera.projectionBiasColumnMajor)
        let shadowMatrix = bias * sourcePV
        let clip = Self.sourceRenderTargetClip * sourcePV * frame.worldToSource
        guard Self.finite(clip), Self.finite(shadowMatrix) else { throw Failure.transform }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = rawMap
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 1, 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw Failure.allocation }
        encoder.label = "Original shared shadow map"
        encoder.setRenderPipelineState(casterPipeline)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(rawMap.width),
            height: Double(rawMap.height), znear: 0, zfar: 1))
        // The authenticated GLB already reverses source Z and winding. The
        // render-target Y conversion reverses its screen winding once more.
        encoder.setFrontFacing(.clockwise); encoder.setCullMode(.back)
        var triangles = 0
        for packet in frame.packets {
            var uniforms = CasterUniforms(clipFromWorld: clip, factor: SIMD4(repeating: packet.factor))
            encoder.setVertexBuffer(packet.part.vertices, offset: 0, index: 0)
            encoder.setVertexBuffer(packet.bones, offset: 0, index: 1)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<CasterUniforms>.stride, index: 2)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CasterUniforms>.stride, index: 2)
            for element in packet.part.elements {
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: element.count,
                    indexType: .uint32, indexBuffer: element.indices, indexBufferOffset: 0)
                triangles += element.count / 3
            }
        }
        encoder.endEncoding()
        try encodeBlur(on: command)
        lastFrame = FrameInfo(tick: tick, aspect: aspect,
            sourceCameraPosition: frame.sourceCameraPosition, sourceView: frame.sourceView,
            sourceProjection: projection, sourceShadowMatrix: shadowMatrix,
            casterCount: frame.packets.count, triangleCount: triangles, factors: frame.factors)
    }

    /// Also used by the synthetic GPU kernel test after a bounded upload to
    /// rawMap. This is the exact production filter, not a separate CPU path.
    func encodeBlur(on command: MTLCommandBuffer) throws {
        try check(command)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = blurredMap
        pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw Failure.allocation }
        encoder.label = "Original single five-tap filter"
        encoder.setRenderPipelineState(blurPipeline); encoder.setCullMode(.none)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(blurredMap.width),
            height: Double(blurredMap.height), znear: 0, zfar: 1))
        var texel = SIMD2<Float>(1 / Float(rawMap.width), 1 / Float(rawMap.height))
        encoder.setVertexBytes(&texel, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        encoder.setFragmentTexture(rawMap, index: 0); encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    /// Called in the Gamma pass with SceneKit's preserved depth, before the
    /// original-effect packets. The scene's opaque geometry still occludes the
    /// receiver, and the receiver never writes depth or samples MorphMask.
    func encodeReceiver(on encoder: MTLRenderCommandEncoder, format: Format,
                        cameraProjection: simd_float4x4, cameraView: simd_float4x4,
                        viewport: MTLViewport) throws {
        guard !stopped else { throw Failure.stopped }
        guard let pipeline = receiverPipelines[format], let frame = snapshot, let info = lastFrame,
              info.tick == frame.tick, Self.finite(cameraProjection), Self.finite(cameraView),
              viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0,
              viewport.originX == 0, viewport.originY == 0, viewport.znear == 0, viewport.zfar == 1 else {
            throw Failure.transform
        }
        let shadow = info.sourceShadowMatrix
        let sourceObject = frame.worldToSource * frame.receiverWorld * Self.reflectZ
        var uniforms = ReceiverUniforms(clipFromLocal: cameraProjection * cameraView * frame.receiverWorld,
            sourceObjectToWorld: sourceObject,
            shadowRow0: SIMD4(shadow[0].x, shadow[1].x, shadow[2].x, shadow[3].x),
            shadowRow1: SIMD4(shadow[0].y, shadow[1].y, shadow[2].y, shadow[3].y),
            color: SIMD4(definition.sourceLocation.shadowColor[0], definition.sourceLocation.shadowColor[1],
                definition.sourceLocation.shadowColor[2], definition.sourceLocation.shadowColor[3]))
        guard Self.finite(uniforms.clipFromLocal), Self.finite(sourceObject) else { throw Failure.transform }
        encoder.pushDebugGroup("Original Palace projected-shadow receiver")
        encoder.setRenderPipelineState(pipeline); encoder.setDepthStencilState(receiverDepth)
        encoder.setViewport(viewport)
        encoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: Int(viewport.width), height: Int(viewport.height)))
        encoder.setCullMode(.back); encoder.setFrontFacing(.counterClockwise)
        encoder.setVertexBuffer(receiverVertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ReceiverUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ReceiverUniforms>.stride, index: 1)
        encoder.setFragmentTexture(blurredMap, index: 0); encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: receiverIndexCount,
            indexType: .uint32, indexBuffer: receiverIndices, indexBufferOffset: 0)
        encoder.popDebugGroup()
    }

    /// Arena reset restores the projector's initial camera history. It is not
    /// a simulation update and never advances MORPH's completion callback.
    func reset() {
        guard !stopped else { return }
        snapshot = nil; cameraSample = nil; lastFrame = nil
        previousRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    }
    /// Presentation cancellation can change a renderer's visibility without a
    /// new core tick. Invalidate its immutable packets, while keeping the same
    /// tick's camera history. Factor/visibility changes are also detected below.
    func invalidateContent() { snapshot = nil; lastFrame = nil }
    func shutdown() {
        guard !stopped else { return }
        for caster in mainCasters + Array(additional.values) {
            for (node, flag) in caster.originalFlags { node.castsShadow = flag }
        }
        additional.removeAll(); snapshot = nil; cameraSample = nil; lastFrame = nil; stopped = true
    }

    private func check(_ command: MTLCommandBuffer) throws {
        guard !stopped else { throw Failure.stopped }
        guard command.device.registryID == gpu.registryID else { throw Failure.device }
        let identity = ObjectIdentifier(command.commandQueue)
        if let commandQueue, commandQueue != identity { throw Failure.queue }
        commandQueue = identity
    }

    private func sample(tick: Int) throws -> Snapshot {
        if let cameraSample, tick < cameraSample.tick { throw Failure.clock }
        let live = additionalModels()
        guard live.count <= 32, Set(live.map { ObjectIdentifier($0.root) }).count == live.count,
              live.allSatisfy({ value in !mainCasters.contains { $0.root === value.root } }) else {
            throw Failure.geometry
        }
        let currentFactors = [fade(0), fade(1)] + [Float](repeating: 0, count: live.count)
        guard currentFactors.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw Failure.transform }
        let currentIDs = mainCasters.map { ObjectIdentifier($0.root) } + live.map { ObjectIdentifier($0.root) }
        if let snapshot, snapshot.tick == tick, snapshot.factors == currentFactors,
           snapshot.casterIDs == currentIDs {
            let cached = mainCasters + live.compactMap { additional[ObjectIdentifier($0.root)] }
            let visible = cached.flatMap { $0.parts.map { Self.visible($0.holder) } }
            if cached.count == currentIDs.count, visible == snapshot.visibility { return snapshot }
        }
        let centers = try worldCenters()
        guard centers.count == 2, centers.allSatisfy(Self.finite) else { throw Failure.geometry }
        let sourceToWorld = stage.meters.simdWorldTransform * Self.reflectZ
        guard Self.affine(sourceToWorld), abs(simd_determinant(sourceToWorld)) > 1e-12 else {
            throw Failure.transform
        }
        let worldToSource = simd_inverse(sourceToWorld)
        let center0 = worldToSource * SIMD4(centers[0], 1)
        let center1 = worldToSource * SIMD4(centers[1], 1)
        let midpoint = (SIMD3(center0.x, center0.y, center0.z) + SIMD3(center1.x, center1.y, center1.z)) * 0.5
        let angles = definition.sourceLocation.projectorRotationDegrees
        let rotation = Self.unityEuler(SIMD3(angles[0], angles[1], angles[2]))
        let position: SIMD3<Float>, view: simd_float4x4
        if let cameraSample, cameraSample.tick == tick {
            position = cameraSample.position; view = cameraSample.view
        } else {
            position = midpoint - previousRotation.act(SIMD3<Float>(0, 0, 1)) * definition.camera.targetDistance
            var cameraWorld = simd_float4x4(rotation); cameraWorld.columns.3 = SIMD4(position, 1)
            // Unity transform.forward is +Z; its camera view uses OpenGL -Z.
            view = Self.reflectZ * simd_inverse(cameraWorld)
        }
        guard Self.affine(worldToSource), Self.affine(view), Self.finite(position),
              Self.affine(stage.receiver.simdWorldTransform) else { throw Failure.transform }

        let liveIDs = Set(live.map { ObjectIdentifier($0.root) })
        // Build newcomers before changing any flags. A malformed source model
        // fails preparation rather than replacing its shadow with a generic one.
        var nextAdditional = additional
        for instance in live where nextAdditional[ObjectIdentifier(instance.root)] == nil {
            nextAdditional[ObjectIdentifier(instance.root)] = try Self.makeCaster(instance, device: gpu)
        }
        var casters = mainCasters
        for instance in live {
            guard let caster = nextAdditional[ObjectIdentifier(instance.root)] else { throw Failure.geometry }
            casters.append(caster)
        }
        var packets: [Packet] = []
        for (index, caster) in casters.enumerated() {
            let factor = currentFactors[index]
            for part in caster.parts where Self.visible(part.holder) {
                guard part.holder.skinner === part.skin, part.holder.geometry === part.geometry,
                      part.skin.bones.count == part.bones.count,
                      zip(part.skin.bones, part.bones).allSatisfy({ pair in pair.0 === pair.1 }) else { throw Failure.skin }
                let base = simd_float4x4(part.skin.baseGeometryBindTransform)
                guard Self.same(base, part.baseBind) else { throw Failure.skin }
                let matrices = try zip(part.bones, part.inverseBinds).map { bone, inverse -> simd_float4x4 in
                    let world = bone.simdWorldTransform
                    guard Self.affine(world) else { throw Failure.transform }
                    let result = world * inverse * part.baseBind
                    guard Self.affine(result) else { throw Failure.transform }
                    return result
                }
                packets.append(Packet(part: part, bones: try Self.buffer(matrices, device: gpu), factor: factor))
            }
        }
        guard packets.count <= 512 else { throw Failure.geometry }
        for (id, caster) in additional where !liveIDs.contains(id) {
            for (node, flag) in caster.originalFlags { node.castsShadow = flag }
            nextAdditional.removeValue(forKey: id)
        }
        for caster in nextAdditional.values { for (node, _) in caster.originalFlags { node.castsShadow = false } }
        additional = nextAdditional
        let result = Snapshot(tick: tick, sourceCameraPosition: position, sourceView: view,
            worldToSource: worldToSource, receiverWorld: stage.receiver.simdWorldTransform,
            packets: packets, factors: currentFactors, casterIDs: currentIDs,
            visibility: casters.flatMap { $0.parts.map { Self.visible($0.holder) } })
        snapshot = result; cameraSample = CameraSample(tick: tick, position: position, view: view)
        previousRotation = rotation
        return result
    }

    private static func makeCaster(_ instance: GLTFModel.Instance, device: MTLDevice) throws -> Caster {
        guard instance.outlines.isEmpty else { throw Failure.geometry }
        var holders: [SCNNode] = []
        let materialIDs = Set(instance.materials.map { ObjectIdentifier($0) })
        guard !materialIDs.isEmpty else { throw Failure.geometry }
        var mixed = false
        func collect(_ node: SCNNode) {
            guard let geometry = node.geometry else { return }
            let count = geometry.materials.filter { materialIDs.contains(ObjectIdentifier($0)) }.count
            if count == 0 { return } // A separately bound trail/effect is not this source model.
            guard count == geometry.materials.count else { mixed = true; return }
            holders.append(node)
        }
        collect(instance.root)
        instance.root.enumerateChildNodes { node, _ in collect(node) }
        guard !mixed, !holders.isEmpty, holders.count <= 64 else { throw Failure.geometry }
        var vertexTotal = 0, indexTotal = 0
        let parts = try holders.map { holder -> Part in
            guard let skin = holder.skinner, let geometry = skin.baseGeometry,
                  holder.geometry === geometry, let position = geometry.sources(for: .vertex).first,
                  let binds = skin.boneInverseBindTransforms, binds.count == skin.bones.count,
                  (1...512).contains(binds.count), (1...250_000).contains(position.vectorCount) else {
                throw Failure.geometry
            }
            let weights = skin.boneWeights, joints = skin.boneIndices
            guard position.usesFloatComponents, position.bytesPerComponent == 4, position.componentsPerVector == 3,
                  weights.usesFloatComponents, weights.bytesPerComponent == 4, weights.componentsPerVector == 4,
                  !joints.usesFloatComponents, joints.bytesPerComponent == 2, joints.componentsPerVector == 4,
                  weights.vectorCount == position.vectorCount, joints.vectorCount == position.vectorCount else {
                throw Failure.skin
            }
            for source in [position, weights, joints] {
                let width = source.componentsPerVector * source.bytesPerComponent
                guard source.dataOffset >= 0, source.dataStride >= width,
                      source.dataStride <= 1024, source.dataOffset <= source.data.count,
                      source.vectorCount <= (source.data.count - source.dataOffset - min(width, source.data.count - source.dataOffset)) / source.dataStride + 1,
                      source.dataOffset + (source.vectorCount - 1) * source.dataStride + width <= source.data.count else {
                    throw Failure.geometry
                }
            }
            let inverseBinds = binds.map { simd_float4x4($0.scnMatrix4Value) }
            let baseBind = simd_float4x4(skin.baseGeometryBindTransform)
            guard inverseBinds.allSatisfy(affine), affine(baseBind) else { throw Failure.transform }
            var vertices: [Vertex] = []; vertices.reserveCapacity(position.vectorCount)
            let pd = position.data, wd = weights.data, jd = joints.data
            try pd.withUnsafeBytes { (pb: UnsafeRawBufferPointer) in
                try wd.withUnsafeBytes { (wb: UnsafeRawBufferPointer) in
                    try jd.withUnsafeBytes { (jb: UnsafeRawBufferPointer) in
                        func scalar(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> Float {
                            Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
                        }
                        for v in 0..<position.vectorCount {
                            let offset = position.dataOffset + v * position.dataStride
                            let p = SIMD4(scalar(pb, offset), scalar(pb, offset + 4), scalar(pb, offset + 8), 1)
                            var w = SIMD4<Float>.zero, j = SIMD4<UInt32>.zero
                            for c in 0..<4 {
                                w[c] = scalar(wb, weights.dataOffset + v * weights.dataStride + c * 4)
                                j[c] = UInt32(UInt16(littleEndian: jb.loadUnaligned(fromByteOffset:
                                    joints.dataOffset + v * joints.dataStride + c * 2, as: UInt16.self)))
                                guard w[c].isFinite, (0...1).contains(w[c]), Int(j[c]) < binds.count else { throw Failure.skin }
                            }
                            guard finite(p), w.x + w.y + w.z + w.w > 0 else { throw Failure.skin }
                            // Preserve uploaded weights; no second normalization
                            // or personal-character scale is introduced here.
                            vertices.append(Vertex(position: p, weights: w, joints: j))
                        }
                    }
                }
            }
            guard !geometry.elements.isEmpty, geometry.elements.count <= 32 else { throw Failure.geometry }
            let elements = try geometry.elements.map { element -> Element in
                guard element.primitiveType == .triangles, (1...500_000).contains(element.primitiveCount),
                      [1, 2, 4].contains(element.bytesPerIndex),
                      element.primitiveCount * 3 * element.bytesPerIndex == element.data.count else { throw Failure.geometry }
                let count = element.primitiveCount * 3
                let indices: [UInt32] = try element.data.withUnsafeBytes { bytes in
                    try (0..<count).map { index in
                        let offset = index * element.bytesPerIndex
                        let value: UInt32
                        switch element.bytesPerIndex {
                        case 1: value = UInt32(bytes.load(fromByteOffset: offset, as: UInt8.self))
                        case 2: value = UInt32(UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
                        default: value = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                        }
                        guard Int(value) < vertices.count else { throw Failure.geometry }
                        return value
                    }
                }
                indexTotal += count
                return Element(indices: try buffer(indices, device: device), count: count)
            }
            vertexTotal += vertices.count
            guard vertexTotal <= 1_000_000, indexTotal <= 3_000_000 else { throw Failure.geometry }
            return Part(holder: holder, skin: skin, geometry: geometry,
                vertices: try buffer(vertices, device: device), elements: elements,
                inverseBinds: inverseBinds, baseBind: baseBind, bones: skin.bones)
        }
        return Caster(root: instance.root, parts: parts,
            originalFlags: holders.map { ($0, $0.castsShadow) })
    }

    private static func visible(_ node: SCNNode) -> Bool {
        var current: SCNNode? = node
        while let value = current {
            if value.isHidden || value.opacity == 0 { return false }
            current = value.parent
        }
        return true
    }
    private static func buffer<T>(_ values: [T], device: MTLDevice) throws -> MTLBuffer {
        guard !values.isEmpty, values.count <= 16_000_000 / MemoryLayout<T>.stride else { throw Failure.geometry }
        let result = values.withUnsafeBytes { bytes in
            bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
        }
        guard let result else { throw Failure.allocation }
        return result
    }
    private static func finite(_ value: SIMD3<Float>) -> Bool { value.x.isFinite && value.y.isFinite && value.z.isFinite }
    private static func finite(_ value: SIMD4<Float>) -> Bool { finite(SIMD3(value.x, value.y, value.z)) && value.w.isFinite }
    private static func finite(_ value: simd_float4x4) -> Bool { (0..<4).allSatisfy { finite(value[$0]) } }
    private static func affine(_ value: simd_float4x4) -> Bool {
        finite(value) && abs(value[0].w) < 1e-6 && abs(value[1].w) < 1e-6 && abs(value[2].w) < 1e-6 && abs(value[3].w - 1) < 1e-6
    }
    private static func same(_ a: simd_float4x4, _ b: simd_float4x4) -> Bool { (0..<4).allSatisfy { a[$0] == b[$0] } }
    private static func matrix(_ values: [Float]) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(values[0], values[1], values[2], values[3]),
            SIMD4(values[4], values[5], values[6], values[7]), SIMD4(values[8], values[9], values[10], values[11]),
            SIMD4(values[12], values[13], values[14], values[15])))
    }
    static func unityEuler(_ degrees: SIMD3<Float>) -> simd_quatf {
        let radians = degrees * (Float.pi / 180)
        // Unity Quaternion.Euler applies Z, then X, then Y.
        return simd_quatf(angle: radians.y, axis: SIMD3(0, 1, 0)) *
            simd_quatf(angle: radians.x, axis: SIMD3(1, 0, 0)) *
            simd_quatf(angle: radians.z, axis: SIMD3(0, 0, 1))
    }
    private static func orthographic(size: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(1 / (size * aspect), 0, 0, 0), SIMD4(0, 1 / size, 0, 0),
            SIMD4(0, 0, -2 / (far - near), 0), SIMD4(0, 0, -(far + near) / (far - near), 1)))
    }
    private static let reflectZ = simd_float4x4(diagonal: SIMD4<Float>(1, 1, -1, 1))
    private static let sourceRenderTargetClip = simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, -1, 0, 0),
        SIMD4<Float>(0, 0, 0.5, 0), SIMD4<Float>(0, 0, 0.5, 1)))

    private static let program = #"""
    #include <metal_stdlib>
    using namespace metal;
    struct SkinVertex { float4 position; float4 weights; uint4 joints; };
    struct CasterUniforms { float4x4 clipFromWorld; float4 factor; };
    struct CasterVarying { float4 position [[position]]; };
    vertex CasterVarying projected_caster_vertex(uint id [[vertex_id]],
        device const SkinVertex* vertices [[buffer(0)]],
        device const float4x4* bones [[buffer(1)]],
        constant CasterUniforms& u [[buffer(2)]]) {
        SkinVertex v = vertices[id];
        float4 p = (bones[v.joints.x] * v.position) * v.weights.x;
        p += (bones[v.joints.y] * v.position) * v.weights.y;
        p += (bones[v.joints.z] * v.position) * v.weights.z;
        p += (bones[v.joints.w] * v.position) * v.weights.w;
        CasterVarying out; out.position = u.clipFromWorld * float4(p.xyz, 1.0); return out;
    }
    fragment half4 projected_caster_fragment(constant CasterUniforms& u [[buffer(2)]]) {
        return half4(u.factor);
    }
    struct BlurVarying { float4 position [[position]]; half4 first; half4 second; half2 last; };
    vertex BlurVarying projected_blur_vertex(uint id [[vertex_id]], constant float2& texel [[buffer(0)]]) {
        const float2 points[6] = { float2(-1,-1),float2(1,-1),float2(-1,1),
            float2(-1,1),float2(1,-1),float2(1,1) };
        float2 p = points[id]; half2 uv = half2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
        half2 t = half2(texel); BlurVarying out;
        out.position = float4(p,0,1);
        out.first = half4(fma(t,half2(-1,1),uv), fma(t,half2(-0.8,-0.8),uv));
        out.second = half4(uv, fma(t,half2(0.8,0.8),uv));
        out.last = fma(t,half2(1,-1),uv); return out;
    }
    fragment half4 projected_blur_fragment(BlurVarying in [[stage_in]],
        texture2d<half> source [[texture(0)]], sampler s [[sampler(0)]]) {
        half4 first = half4(source.sample(s,float2(in.first.xy)).r,
            source.sample(s,float2(in.first.zw)).r, source.sample(s,float2(in.second.xy)).r,
            source.sample(s,float2(in.second.zw)).r);
        half partial = dot(first, half4(0.2));
        half last = source.sample(s,float2(in.last)).r;
        return half4(fma(float(last), 0.2f, float(partial)));
    }
    struct ReceiverUniforms { float4x4 clipFromLocal; float4x4 sourceObjectToWorld;
        float4 shadowRow0; float4 shadowRow1; float4 color; };
    struct ReceiverVarying { float4 position [[position]]; half2 uv; };
    vertex ReceiverVarying projected_receiver_vertex(uint id [[vertex_id]],
        device const float4* vertices [[buffer(0)]], constant ReceiverUniforms& u [[buffer(1)]]) {
        float4 p = vertices[id]; ReceiverVarying out; out.position = u.clipFromLocal * p;
        p.z = -p.z; // Restore the source local position before original matrix math.
        float4 a = float4(half4(u.shadowRow0)), b = float4(half4(u.shadowRow1));
        float4 localX = float4(dot(a,u.sourceObjectToWorld[0]),dot(a,u.sourceObjectToWorld[1]),
            dot(a,u.sourceObjectToWorld[2]),dot(a,u.sourceObjectToWorld[3]));
        float4 localY = float4(dot(b,u.sourceObjectToWorld[0]),dot(b,u.sourceObjectToWorld[1]),
            dot(b,u.sourceObjectToWorld[2]),dot(b,u.sourceObjectToWorld[3]));
        out.uv = half2(dot(localX,p),dot(localY,p)); // The source never divides by W.
        return out;
    }
    fragment half4 projected_receiver_fragment(ReceiverVarying in [[stage_in]],
        texture2d<half> shadow [[texture(0)]], sampler s [[sampler(0)]],
        constant ReceiverUniforms& u [[buffer(1)]]) {
        half q = shadow.sample(s,float2(in.uv)).r;
        half4 color = half4(u.color);
        return fma(half4(q), half4(1)-color, color);
    }
    """#
}
