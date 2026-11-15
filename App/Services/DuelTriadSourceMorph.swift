import CryptoKit
import Foundation
import Metal
import SceneKit
import simd
import UIKit

/// The authenticated release supplies the mask and each affected material's
/// parameters. This adapter implements only the recovered MORPH operation; it
/// does not claim that SceneKit's underlying character lighting matches Unity.
///
/// Source methods: HideModel 29984/29988; frame clock 36930 -> 35977;
/// tween 35946/35947; character cutoff 38410 -> 38838; completion 38411.
/// https://developer.apple.com/documentation/scenekit/scnshadable
/// https://developer.apple.com/documentation/scenekit/scnmaterialproperty/contents
enum DuelTriadSourceMorph {
    enum Failure: Error, Equatable {
        case mask, material(String), geometry, clock, stopped, allocation, sampling
    }

    struct Mask: Codable, Equatable, Sendable {
        let file: String
        let bytes: Int
        let sha256: String
        let width: Int
        let height: Int
        let sourceTextureFormat: Int
        let sourceColorSpace: Int
        let mip: Int
        let filter: Int
        let wrapS: Int
        let wrapT: Int

        func validate() throws {
            guard !file.isEmpty, file == (file as NSString).lastPathComponent,
                  !file.contains("\\"), file != ".", file != "..",
                  (1...1024).contains(width), (1...1024).contains(height),
                  [4, 45].contains(sourceTextureFormat), sourceColorSpace == 0,
                  mip == 1, filter == 1, wrapS == 0, wrapT == 0,
                  sha256.count == 64, sha256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
                throw Failure.mask
            }
            let expected = sourceTextureFormat == 4 ? width * height * 4 :
                ((width + 3) / 4) * ((height + 3) / 4) * 8
            guard bytes == expected else { throw Failure.mask }
        }
    }

    struct MaterialBinding: Codable, Equatable, Sendable {
        let name: String
        /// Nil is allowed only for explicitly identified actor base geometry.
        /// A personal head is not assigned an invented source equipment ID.
        let sourceItemType: Int?
        let actorBaseGeometry: Bool
        let tile: Float
        let edgeSize: Float
        let edgeStart: [Float]
        let edgeEnd: [Float]

        func validate() throws {
            let equipment = sourceItemType.map { (1...6).contains($0) } ?? false
            guard !name.isEmpty, name.utf8.count <= 160,
                  (equipment && !actorBaseGeometry) || (sourceItemType == nil && actorBaseGeometry),
                  tile.isFinite, tile > 0, tile <= 16,
                  edgeSize.isFinite, edgeSize > 0, edgeSize <= 1,
                  edgeStart.count == 4, edgeEnd.count == 4,
                  (edgeStart + edgeEnd).allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  edgeStart[3] == 1, edgeEnd[3] == 1 else { throw Failure.material(name) }
        }
    }

    static func prepare(mask: Mask, data: Data, device: MTLDevice) throws -> Prepared {
        try mask.validate()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == mask.bytes, digest == mask.sha256 else { throw Failure.mask }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: mask.sourceTextureFormat == 45 ? .etc2_rgb8 : .rgba8Unorm,
            width: mask.width, height: mask.height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw Failure.allocation }
        let row = mask.sourceTextureFormat == 45 ? ((mask.width + 3) / 4) * 8 : mask.width * 4
        data.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, mask.width, mask.height), mipmapLevel: 0,
                withBytes: bytes.baseAddress!, bytesPerRow: row)
        }
        return Prepared(texture: texture)
    }

    final class Prepared {
        let texture: MTLTexture
        @MainActor private var sourceOriginRed: Float?
        fileprivate init(texture: MTLTexture) { self.texture = texture }

        @MainActor
        func install(on instance: GLTFModel.Instance, materials definitions: [MaterialBinding]) throws -> Binding {
            guard !definitions.isEmpty, definitions.count <= 32,
                  Set(definitions.map(\.name)).count == definitions.count,
                  Set(instance.materials.compactMap(\.name)) == Set(definitions.map(\.name)),
                  instance.outlines.isEmpty else { throw Failure.geometry }
            for definition in definitions { try definition.validate() }
            let byName = Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0) })
            var materialIDs = Set<ObjectIdentifier>()
            for material in instance.materials {
                guard let name = material.name, byName[name] != nil,
                      materialIDs.insert(ObjectIdentifier(material)).inserted,
                      material.program == nil, material.transparency == 1,
                      material.readsFromDepthBuffer, material.writesToDepthBuffer,
                      material.diffuse.mappingChannel == 0,
                      Self.identity(material.diffuse.contentsTransform),
                      !(material.shaderModifiers?.values.contains(where: {
                          $0.contains("triadMorph") || $0.contains("#pragma transparent")
                      }) ?? false) else { throw Failure.material(material.name ?? "") }
            }
            var nodes: [SCNNode] = []
            var boundMaterialIDs = Set<ObjectIdentifier>()
            var authoredUVByMaterial: [ObjectIdentifier: Bool] = [:]
            var invalidGeometry = false
            instance.root.enumerateChildNodes { node, _ in
                guard let geometry = node.geometry else { return }
                let matched = geometry.materials.filter { materialIDs.contains(ObjectIdentifier($0)) }
                guard !matched.isEmpty else { return }
                guard matched.count == geometry.materials.count,
                      let vertices = geometry.sources(for: .vertex).first, vertices.vectorCount > 0 else {
                    invalidGeometry = true; return
                }
                let uv = geometry.sources(for: .texcoord).first
                if let uv {
                    guard uv.componentsPerVector == 2, uv.vectorCount > 0,
                          uv.vectorCount == vertices.vectorCount else {
                        invalidGeometry = true; return
                    }
                }
                for material in matched {
                    let id = ObjectIdentifier(material), hasUV = uv != nil
                    guard let name = material.name, let definition = byName[name],
                          hasUV || (["Liu_Neck_Skin", "Personal_Neck_Bridge_Derived_Skin"].contains(name) && definition.actorBaseGeometry &&
                            definition.sourceItemType == nil && material.diffuse.contents is UIColor &&
                            Self.hasOnlyConstantContents(material)),
                          authoredUVByMaterial[id].map({ $0 == hasUV }) ?? true else {
                        invalidGeometry = true; return
                    }
                    authoredUVByMaterial[id] = hasUV
                    boundMaterialIDs.insert(id)
                }
                nodes.append(node)
            }
            // GLTFModel instances put their mesh holders beneath root. A
            // malformed binding must not leave an unhandled solid renderer.
            guard !invalidGeometry, !nodes.isEmpty, boundMaterialIDs == materialIDs else { throw Failure.geometry }
            // SceneKit can require texcoord0 for a custom texture sampler even
            // when its shader expression uses a constant coordinate. Only the
            // authenticated untextured neck may replace that sampler with its
            // real, immutable GPU sample. No geometry attribute is invented.
            let constantSample = authoredUVByMaterial.values.contains(false) ? try sampleSourceOrigin() : nil
            let installed = try instance.materials.map { material -> Binding.Material in
                guard let name = material.name, let definition = byName[name],
                      let hasUV = authoredUVByMaterial[ObjectIdentifier(material)],
                      hasUV || constantSample != nil else { throw Failure.geometry }
                return .init(material: material, parameters: definition,
                    constantSourceMaskValue: hasUV ? nil : constantSample)
            }
            return Binding(texture: texture, materials: installed, nodes: nodes)
        }

        @MainActor
        private func sampleSourceOrigin() throws -> Float {
            if let sourceOriginRed { return sourceOriginRed }
            let device = texture.device
            let options = MTLCompileOptions(); options.fastMathEnabled = false
            let library = try device.makeLibrary(source: """
            #include <metal_stdlib>
            using namespace metal;
            kernel void triad_morph_source_origin(
                texture2d<float, access::sample> mask [[texture(0)]],
                sampler sourceSampler [[sampler(0)]],
                device float* result [[buffer(0)]]) {
                result[0] = mask.sample(sourceSampler, float2(0.0), level(0.0)).r;
            }
            """, options: options)
            guard let function = library.makeFunction(name: "triad_morph_source_origin") else {
                throw Failure.sampling
            }
            let pipeline = try device.makeComputePipelineState(function: function)
            let descriptor = MTLSamplerDescriptor()
            descriptor.normalizedCoordinates = true
            descriptor.sAddressMode = .repeat; descriptor.tAddressMode = .repeat
            descriptor.minFilter = .linear; descriptor.magFilter = .linear
            descriptor.mipFilter = .notMipmapped; descriptor.maxAnisotropy = 1
            guard let sampler = device.makeSamplerState(descriptor: descriptor),
                  let result = device.makeBuffer(length: MemoryLayout<Float>.size, options: .storageModeShared),
                  let queue = device.makeCommandQueue(), let command = queue.makeCommandBuffer(),
                  let encoder = command.makeComputeCommandEncoder() else { throw Failure.allocation }
            result.contents().storeBytes(of: Float.nan, as: Float.self)
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(texture, index: 0); encoder.setSamplerState(sampler, index: 0)
            encoder.setBuffer(result, offset: 0, index: 0)
            encoder.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            guard command.status == .completed, command.error == nil else { throw Failure.sampling }
            let value = result.contents().load(as: Float.self)
            guard value.isFinite, (0...1).contains(value) else { throw Failure.sampling }
            sourceOriginRed = value
            return value
        }

        private static func identity(_ value: SCNMatrix4) -> Bool {
            let matrix = simd_float4x4(value)
            return (0..<4).allSatisfy { matrix[$0] == matrix_identity_float4x4[$0] }
        }

        @MainActor private static func hasOnlyConstantContents(_ material: SCNMaterial) -> Bool {
            // Cover every public SCNMaterialProperty, including secondary
            // normal/coat maps. A solid diffuse color alone proves no such
            // absence; textures and unknown content types fail closed.
            let properties = [material.diffuse, material.ambient, material.specular,
                material.emission, material.transparent, material.reflective,
                material.multiply, material.normal, material.displacement,
                material.ambientOcclusion, material.metalness, material.roughness,
                material.selfIllumination, material.clearCoat, material.clearCoatNormal,
                material.clearCoatRoughness]
            return properties.allSatisfy { property in
                guard let contents = property.contents else { return true }
                return contents is UIColor || contents is NSNumber
            }
        }
    }

    @MainActor final class Binding {
        fileprivate struct Material {
            let material: SCNMaterial
            let parameters: MaterialBinding
            let originalModifiers: [SCNShaderModifierEntryPoint: String]?
            let originalBlend: SCNBlendMode
            let originalReadsDepth: Bool
            let originalWritesDepth: Bool
            let constantSourceMaskValue: Float?
            var constantSourceUV: Bool { constantSourceMaskValue != nil }
            init(material: SCNMaterial, parameters: MaterialBinding, constantSourceMaskValue: Float?) {
                self.material = material; self.parameters = parameters
                self.constantSourceMaskValue = constantSourceMaskValue
                originalModifiers = material.shaderModifiers; originalBlend = material.blendMode
                originalReadsDepth = material.readsFromDepthBuffer
                originalWritesDepth = material.writesToDepthBuffer
            }
        }
        private enum Phase: Equatable { case idle, pendingBoundary, running, complete }
        private let texture: MTLTexture
        private let materials: [Material]
        private let visibility: [(node: SCNNode, hidden: Bool)]
        private var phase: Phase = .idle
        private var lastTick: Int?
        private var requestTick: Int?
        private var duration = 140
        private var elapsed = 0
        private var stopped = false
        private(set) var progress: Float = 0
        var hasPendingBoundary: Bool { phase == .pendingBoundary }
        var isComplete: Bool { phase == .complete }

        fileprivate init(texture: MTLTexture, materials: [Material], nodes: [SCNNode]) {
            self.texture = texture; self.materials = materials
            visibility = nodes.map { ($0, $0.isHidden) }
        }

        /// Original 29988 waits once for EndOfFrame in the normal case. The
        /// special pending-shadow-exit dictionary does not exist in this arena;
        /// its 46 render-boundary waits are never invented as 45 logical ticks.
        func requestHide(sourceTick: Int, transitionTicks: Int = 140) throws {
            guard !stopped else { throw Failure.stopped }
            guard Self.valid(sourceTick), (1...36_000).contains(transitionTicks) else { throw Failure.clock }
            if requestTick == sourceTick, duration == transitionTicks, phase != .idle { return }
            guard phase == .idle, lastTick.map({ sourceTick >= $0 }) ?? true else { throw Failure.clock }
            duration = transitionTicks; elapsed = 0; progress = 0
            requestTick = sourceTick; lastTick = sourceTick; phase = .pendingBoundary
        }

        /// Called only after a real scene command buffer is committed. Repeated
        /// display draws do not change the source clock or the cutoff snapshot.
        func didRenderFrame(sourceTick: Int) throws {
            guard !stopped else { throw Failure.stopped }
            guard Self.valid(sourceTick), lastTick.map({ sourceTick >= $0 }) ?? true else {
                throw Failure.clock
            }
            guard phase == .pendingBoundary else { return }
            // Source 29988 yields EndOfFrame before calling 38357/38369,
            // which enable MORPH. Even cutoff=1 can add the weapon's nonzero
            // edgeStart where mask=1, so the waiting frame keeps its shader.
            installModifiers()
            setProgress(0)
            lastTick = sourceTick; phase = .running
        }

        func update(sourceTick: Int, paused: Bool = false) throws {
            guard !stopped else { throw Failure.stopped }
            guard Self.valid(sourceTick), lastTick.map({ sourceTick >= $0 }) ?? true else {
                throw Failure.clock
            }
            let delta = lastTick.map { sourceTick - $0 } ?? 0
            lastTick = sourceTick
            guard phase == .running, !paused else { return }
            elapsed = min(duration, elapsed + delta)
            progress = Float(elapsed) / Float(duration)
            if elapsed == duration { finish() } else { setProgress(progress) }
        }

        /// Source tween cancellation invokes its outstanding completion.
        /// A coroutine cancelled before its first boundary has no tween yet.
        func cancel() {
            guard !stopped else { return }
            if phase == .running { finish() }
            else if phase == .pendingBoundary { reset() }
        }

        /// Arena lifecycle restoration for persistent actors. Original Dispose
        /// cancels transitions; it does not imply that a hidden actor is shown.
        func reset() {
            guard !stopped else { return }
            restoreMaterials()
            for item in visibility { item.node.isHidden = item.hidden }
            phase = .idle; lastTick = nil; requestTick = nil; elapsed = 0; progress = 0
        }

        func shutdown() { guard !stopped else { return }; reset(); stopped = true }

        private static func valid(_ tick: Int) -> Bool { (0...2_160_000).contains(tick) }

        private func installModifiers() {
            for item in materials {
                let material = item.material, parameter = item.parameters
                if let value = item.constantSourceMaskValue {
                    // Removing the sampler declaration alone is insufficient
                    // if a texture property still participates in SceneKit's
                    // generated vertex descriptor. This branch owns no sampler.
                    material.setValue(nil, forKey: "triadMorphMask")
                    material.setValue(nil, forKey: "triadMorphSurfaceMask")
                    material.setValue(NSNumber(value: value), forKey: "triadMorphSourceValue")
                    material.setValue(NSNumber(value: value), forKey: "triadMorphSurfaceSourceValue")
                } else {
                    let mask = SCNMaterialProperty(contents: texture)
                    mask.wrapS = .repeat; mask.wrapT = .repeat
                    mask.minificationFilter = .linear; mask.magnificationFilter = .linear
                    mask.mipFilter = .none; mask.maxAnisotropy = 1
                    material.setValue(mask, forKey: "triadMorphMask")
                    material.setValue(mask, forKey: "triadMorphSurfaceMask")
                }
                material.setValue(NSNumber(value: parameter.tile), forKey: "triadMorphTile")
                material.setValue(NSNumber(value: parameter.tile), forKey: "triadMorphSurfaceTile")
                material.setValue(NSNumber(value: parameter.edgeSize), forKey: "triadMorphEdge")
                material.setValue(NSNumber(value: parameter.edgeSize), forKey: "triadMorphSurfaceEdge")
                func color(_ value: [Float]) -> NSValue {
                    NSValue(scnVector3: SCNVector3(value[0], value[1], value[2]))
                }
                material.setValue(color(parameter.edgeStart), forKey: "triadMorphStart")
                material.setValue(color(parameter.edgeEnd), forKey: "triadMorphEnd")
                var modifiers = item.originalModifiers ?? [:]
                modifiers[.surface] = GLTFModel.combiningShaderModifiers(modifiers[.surface] ?? "",
                    DuelTriadSourceMorph.surface(constantSourceUV: item.constantSourceUV))
                modifiers[.fragment] = GLTFModel.combiningShaderModifiers(modifiers[.fragment] ?? "",
                    DuelTriadSourceMorph.fragment(constantSourceUV: item.constantSourceUV))
                material.shaderModifiers = modifiers
                material.blendMode = .replace
                material.readsFromDepthBuffer = true; material.writesToDepthBuffer = true
            }
        }

        private func setProgress(_ value: Float) {
            for item in materials {
                // Source 38838: cutoff=(1+edge)*(1-progress)-edge.
                let edge = item.parameters.edgeSize
                let cutoff = (1 + edge) * (1 - value) - edge
                item.material.setValue(NSNumber(value: cutoff), forKey: "triadMorphCutoff")
                item.material.setValue(NSNumber(value: cutoff), forKey: "triadMorphSurfaceCutoff")
            }
        }

        private func finish() {
            progress = 1; elapsed = duration; phase = .complete
            // Source 38411 disables MORPH and then the renderer. Preserve the
            // original modifiers so the next round can restore the same actor.
            restoreMaterials()
            for item in visibility { item.node.isHidden = true }
        }

        private func restoreMaterials() {
            for item in materials {
                item.material.shaderModifiers = item.originalModifiers
                item.material.blendMode = item.originalBlend
                item.material.readsFromDepthBuffer = item.originalReadsDepth
                item.material.writesToDepthBuffer = item.originalWritesDepth
            }
        }
    }

    // The mask is original linear data, uploaded without flipping its rows.
    // Imported glTF UV0 was flipped in the exporter; undo V before source tile.
    // Surface discard controls the main color/depth pass. The original
    // projected shadow has a separate whole-silhouette fade: 38405 writes
    // actorValue=1-progress, then 23565 passes progress to ShadowcasterUnlit.
    // It never samples this mask, so its contract must be verified separately.
    // SceneKit parses each line after #pragma arguments as a Metal argument.
    // Keep global functions and the documented GLSL sampler compatibility
    // declaration before it; SCNMaterialProperty owns repeat/linear/no-mip.
    // Keep the KVC names and the distinct stage-local names unchanged.
    private static func sourceUV() -> String {
        // Only authored glTF UVs enter this path. The authenticated untextured
        // neck uses its independently sampled original mask value instead.
        "float2(_surface.diffuseTexcoord.x, 1.0 - _surface.diffuseTexcoord.y)"
    }

    private static func surface(constantSourceUV: Bool) -> String {
        let sampler = constantSourceUV ? "" : "uniform sampler2D triadMorphSurfaceMask;"
        let declaration = constantSourceUV ? "float triadMorphSurfaceSourceValue;" :
            "float triadMorphSurfaceTile;"
        let sample = constantSourceUV ? "float triadMorphSurfaceValue = triadMorphSurfaceSourceValue;" : """
    float2 triadMorphSurfaceUV = \(sourceUV()) * triadMorphSurfaceTile;
    float triadMorphSurfaceValue = texture2D(triadMorphSurfaceMask, triadMorphSurfaceUV).r;
    """
        return """
    \(sampler)
    #pragma arguments
    \(declaration)
    float triadMorphSurfaceEdge;
    float triadMorphSurfaceCutoff;
    #pragma opaque
    #pragma body
    \(sample)
    if (triadMorphSurfaceValue > triadMorphSurfaceCutoff + triadMorphSurfaceEdge) { discard_fragment(); }
    """
    }

    private static func fragment(constantSourceUV: Bool) -> String {
        let sampler = constantSourceUV ? "" : "uniform sampler2D triadMorphMask;"
        let declaration = constantSourceUV ? "float triadMorphSourceValue;" :
            "float triadMorphTile;"
        let sample = constantSourceUV ? "float triadMorphFragmentValue = triadMorphSourceValue;" : """
    float2 triadMorphFragmentUV = \(sourceUV()) * triadMorphTile;
    float triadMorphFragmentValue = texture2D(triadMorphMask, triadMorphFragmentUV).r;
    """
        return """
    \(sampler)
    float3 triadMorphToLinear(float3 c) {
        return mix(c / 12.92, pow((c + 0.055) / 1.055, float3(2.4)), step(float3(0.04045), c));
    }
    float3 triadMorphToGamma(float3 c) {
        c = max(c, float3(0.0));
        return mix(c * 12.92, 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, step(float3(0.0031308), c));
    }
    #pragma arguments
    \(declaration)
    float triadMorphEdge;
    float triadMorphCutoff;
    float3 triadMorphStart;
    float3 triadMorphEnd;
    #pragma opaque
    #pragma body
    \(sample)
    if (triadMorphFragmentValue >= triadMorphCutoff && triadMorphFragmentValue <= triadMorphCutoff + triadMorphEdge) {
        float triadMorphFragmentT = clamp((triadMorphFragmentValue - triadMorphCutoff) / triadMorphEdge, 0.0, 1.0);
        float3 triadMorphFragmentColor = mix(triadMorphStart, triadMorphEnd,
            triadMorphFragmentT * triadMorphFragmentT * (3.0 - 2.0 * triadMorphFragmentT));
        // Both original comparisons include equality. At mask==cutoff the
        // base and edgeStart are added in source Gamma space, not replaced.
        if (triadMorphFragmentValue <= triadMorphCutoff) { triadMorphFragmentColor += triadMorphToGamma(_output.color.rgb); }
        _output.color.rgb = triadMorphToLinear(triadMorphFragmentColor);
    }
    """
    }
}
