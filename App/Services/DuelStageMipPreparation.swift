import Foundation
import CryptoKit
import SceneKit

/// Dormant stage-only preparation. No Metal import, texture allocation, material
/// assignment, activation flag or invented sampling-proof token exists here.
enum DuelStageMipPreparation {
    enum Failure: Error, Equatable {
        case stageIdentity, stageStructure, binding(String), archiveMismatch
    }
    enum RetentionReason: Equatable {
        case archiveAbsent, archiveRejected, preflightRejected, unresolvedSamplingContracts
    }
    struct Target {
        let material, property, imageName: String
        let textureFile: String
        /// Exported channel, not a replacement for the loader's uniform-map decision.
        let exportedChannel: Int
    }
    struct BindingPlan {
        let stageFile: String
        let targets: [Target]
        let textureFiles: Set<String>
        fileprivate init(stageFile: String, targets: [Target]) {
            self.stageFile = stageFile; self.targets = targets
            textureFiles = Set(targets.map(\.textureFile))
        }
    }
    struct PreparedBytes {
        let bindings: BindingPlan
        let payloads: [DuelStageMipArchive.Payload]
        fileprivate init(bindings: BindingPlan, payloads: [DuelStageMipArchive.Payload]) {
            self.bindings = bindings; self.payloads = payloads
        }
        /// Original compressed level bytes only, with no flipping, premultiplication,
        /// color conversion, interpolation, decompression or generated mip content.
        func level(textureFile: String, index: Int) -> Data? {
            guard let payload = payloads.first(where: { $0.texture.file == textureFile }),
                  payload.texture.levels.indices.contains(index) else { return nil }
            let level = payload.texture.levels[index]
            return Data(payload.bytes).subdata(in: level.offset..<(level.offset + level.byteCount))
        }
    }
    struct RetainedStage {
        let root: SCNNode
        let reason: RetentionReason
        let preparedBytes: PreparedBytes?
        /// Actual loader-selected channels retained for later review; never applied here.
        let mappingChannels: [String: Int]
        fileprivate init(root: SCNNode, reason: RetentionReason,
                         preparedBytes: PreparedBytes? = nil, mappingChannels: [String: Int] = [:]) {
            self.root = root; self.reason = reason
            self.preparedBytes = preparedBytes; self.mappingChannels = mappingChannels
        }
    }

    /// Pure manifest/GLB binding preflight. Both byte identities are checked
    /// before using names, offsets or references. Does not load images or SceneKit.
    static func preflight(stageData: Data, kind: DuelStageAsset.Kind,
                          manifestData: Data) throws -> BindingPlan {
        let manifest = try DuelStageMipArchive.decodePinnedManifest(manifestData)
        let file = kind == .palace ? "SF3_Palace_Exterior.glb" : "SF3_Autumn_Lobby.glb"
        guard let stage = manifest.stages.first(where: { $0.file == file }),
              stageData.count == stage.bytes,
              SHA256.hash(data: stageData).map({ String(format: "%02x", $0) }).joined() == stage.sha256 else {
            throw Failure.stageIdentity
        }
        let bytes = Data(stageData)
        func word(_ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 | (Int(bytes[offset + $1]) << ($1 * 8)) }
        }
        guard bytes.count >= 20, bytes.prefix(4) == Data("glTF".utf8),
              word(4) == 2, word(8) == bytes.count, word(16) == 0x4E4F534A,
              word(12) <= bytes.count - 20 else { throw Failure.stageStructure }
        guard let json = try JSONSerialization.jsonObject(with: bytes.subdata(in: 20..<(20 + word(12)))) as? [String: Any],
              let materials = json["materials"] as? [[String: Any]],
              let textures = json["textures"] as? [[String: Any]],
              let images = json["images"] as? [[String: Any]] else { throw Failure.stageStructure }
        let names = materials.compactMap { $0["name"] as? String }
        guard names.count == materials.count, Set(names).count == names.count else { throw Failure.stageStructure }
        var targets: [Target] = []
        for texture in manifest.textures {
            for binding in texture.bindings where binding.file == file {
                guard let material = materials.first(where: { $0["name"] as? String == binding.material }) else {
                    throw Failure.binding(binding.material)
                }
                let reference: [String: Any]?
                let channel: Int
                switch binding.property {
                case "_MainTex":
                    reference = (material["pbrMetallicRoughness"] as? [String: Any])?["baseColorTexture"] as? [String: Any]
                    channel = 0
                case "_LightMapDefault":
                    reference = (material["extras"] as? [String: Any])?["sf3Lightmap"] as? [String: Any]
                    channel = 1
                default: throw Failure.binding(binding.material)
                }
                guard let reference, (reference["texCoord"] as? Int ?? 0) == channel,
                      let index = reference["index"] as? Int, textures.indices.contains(index),
                      let source = textures[index]["source"] as? Int, images.indices.contains(source),
                      let imageName = images[source]["name"] as? String else { throw Failure.binding(binding.material) }
                // The authenticated exporter names duplicate image references
                // with _ext_<image index>. Do not conflate a different base name.
                guard imageName == texture.name || imageName == "\(texture.name)_ext_\(source)" else {
                    throw Failure.binding(binding.material)
                }
                targets.append(.init(material: binding.material, property: binding.property,
                    imageName: imageName, textureFile: texture.file, exportedChannel: channel))
            }
        }
        guard targets.count == (kind == .palace ? 19 : 12),
              Set(targets.map(\.material)) == Set(names),
              Set(targets.map(\.textureFile)).count == (kind == .palace ? 3 : 4) else {
            throw Failure.stageStructure
        }
        return BindingPlan(stageFile: file, targets: targets)
    }

    /// Resolves every selected chain before returning any result. Verified's
    /// construction is confined to the digest-pinned archive reader.
    static func prepareBytes(_ plan: BindingPlan, archive: DuelStageMipArchive.Verified) throws -> PreparedBytes {
        let selected = archive.payloads.filter { plan.textureFiles.contains($0.texture.file) }
        guard selected.count == plan.textureFiles.count,
              Set(selected.map { $0.texture.file }) == plan.textureFiles else { throw Failure.archiveMismatch }
        for payload in selected {
            try DuelStageMipArchive.validatePayload(payload.bytes, texture: payload.texture)
            for target in plan.targets where target.textureFile == payload.texture.file {
                guard payload.texture.bindings.contains(.init(file: plan.stageFile,
                    material: target.material, property: target.property)) else { throw Failure.archiveMismatch }
            }
        }
        return PreparedBytes(bindings: plan, payloads: selected)
    }

    /// Creates the ordinary complete, independent stage FIRST. Every failure,
    /// and successful byte preparation with unresolved contracts, retains it.
    /// No caller can supply an "approved" boolean to install these textures.
    @MainActor
    static func retainStage(asset: DuelStageAsset, stageData: Data, manifestData: Data,
                            readArchive: () throws -> DuelStageMipArchive.Verified?) -> RetainedStage {
        let root = asset.makeRoot()
        let archive: DuelStageMipArchive.Verified
        do {
            guard let value = try readArchive() else { return .init(root: root, reason: .archiveAbsent) }
            archive = value
        } catch { return .init(root: root, reason: .archiveRejected) }
        do {
            let plan = try preflight(stageData: stageData, kind: asset.kind, manifestData: manifestData)
            let prepared = try prepareBytes(plan, archive: archive)
            var byName: [String: [SCNMaterial]] = [:]
            root.enumerateChildNodes { node, _ in
                for material in node.geometry?.materials ?? [] {
                    if let name = material.name { byName[name, default: []].append(material) }
                }
            }
            var channels: [String: Int] = [:]
            for target in plan.targets {
                guard let materials = byName[target.material], !materials.isEmpty else { throw Failure.binding(target.material) }
                for material in materials {
                    let property = target.property == "_MainTex" ? material.diffuse : material.multiply
                    guard property.contents != nil else { throw Failure.binding(target.material) }
                    let key = target.material + ":" + target.property
                    if let channel = channels[key], channel != property.mappingChannel { throw Failure.binding(key) }
                    channels[key] = property.mappingChannel
                }
            }
            return .init(root: root, reason: .unresolvedSamplingContracts,
                         preparedBytes: prepared, mappingChannels: channels)
        } catch { return .init(root: root, reason: .preflightRejected) }
    }
}
