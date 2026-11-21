import Foundation
import CryptoKit
import SceneKit

/// A separately staged scenery asset. The application never downloads or
/// unpacks an APK. Converted geometry and textures live for one match only.
@MainActor
final class DuelStageAsset {
    enum AssetError: Error { case integrity, incomplete }
    nonisolated static let digest = "185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8"
    // Each list is verified against original source materials and the exact
    // export gated below. Characters retain their existing shading.
    private static let palaceSourceLocationMaterials: Set<String> = [
        "home_01", "gold_01", "back", "alfa_gold", "alfa_back",
        "cust05", "back_home", "cust04", "floor_01", "metal_01"
    ]
    // These autumn materials use MainTex * (2 * vertex RGB) * baked lightmap.
    // Matcup_mat has an additional MatCap term and is deliberately excluded.
    private static let autumnSourceLocationMaterials: Set<String> = [
        "ALFA", "BG", "ALFA_BG", "Base_mat", "Leavs_mat"
    ]
    enum Kind { case palace, autumnLobby }
    static var bundledURL: URL? { bundledURL(for: .palace) }
    static func bundledURL(for kind: Kind) -> URL? {
        let name = kind == .palace ? "SF3_Palace_Exterior" : "SF3_Autumn_Lobby"
        return Bundle.main.url(forResource: name, withExtension: "glb") ??
            Bundle.main.url(forResource: name, withExtension: "glb", subdirectory: "FighterPrivate")
    }
    let kind: Kind
    let model: GLTFModel

    /// Only value bytes cross the task boundary. Material and SceneKit construction stays on main.
    struct PreparedAutumnLobby: Sendable {
        fileprivate let url: URL
        fileprivate let bytes: Data
        fileprivate let opaquePixels: [Int: ArenaOpaquePNG.Image]
        var opaqueTextureCount: Int { opaquePixels.count }
        var decodedPixelBytes: Int { opaquePixels.values.reduce(0) { $0 + $1.rgba.count } }
    }

    /// One local match may prepare this value before it owns a SceneKit world.
    /// Only the bundled, pinned GLB and bounded embedded opaque PNG pixels cross.
    struct PreparedPalace: Sendable {
        fileprivate let url: URL
        fileprivate let bytes: Data
        fileprivate let opaquePixels: [Int: ArenaOpaquePNG.Image]
        var opaqueTextureCount: Int { opaquePixels.count }
        var decodedPixelBytes: Int { opaquePixels.values.reduce(0) { $0 + $1.rgba.count } }
    }

    nonisolated static let palaceOpaquePixelBudget = 32 * 1024 * 1024

    nonisolated static func prepareOptionalPalace(url: URL?) async -> PreparedPalace? {
        guard let url else { return nil }
        return try? await preparePalace(url: url)
    }

    nonisolated static func preparePalace(url: URL) async throws -> PreparedPalace {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let bytes = try verifiedBytes(url: url, kind: .palace)
            try Task.checkCancellation()
            // Do not interpret a file outside the authenticated Palace GLB.
            let pixels = try opaquePixels(bytes, externalDirectory: nil, pixelBudget: palaceOpaquePixelBudget)
            try Task.checkCancellation()
            return PreparedPalace(url: url, bytes: bytes, opaquePixels: pixels)
        }
        return try await withTaskCancellationHandler {
            let value = try await worker.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated static func prepareAutumnLobby(url: URL) async throws -> PreparedAutumnLobby {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let bytes = try verifiedBytes(url: url, kind: .autumnLobby)
            try Task.checkCancellation()
            let pixels = try opaquePixels(bytes, externalDirectory: url.deletingLastPathComponent(),
                                          pixelBudget: 64 * 1024 * 1024)
            try Task.checkCancellation()
            return PreparedAutumnLobby(url: url, bytes: bytes, opaquePixels: pixels)
        }
        return try await withTaskCancellationHandler {
            let value = try await worker.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated private static func verifiedBytes(url: URL, kind: Kind) throws -> Data {
        let expectedBytes = kind == .palace ? 9_292_540 : 11_164_484
        let expectedDigest = kind == .palace ? Self.digest : "616d5cb125f49c6b378cf280c90cf10e927b5b71aa461ecb34d7cdaad08c62c1"
        guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == expectedBytes else { throw AssetError.integrity }
        let bytes = try Data(contentsOf: url)
        guard bytes.count == expectedBytes,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == expectedDigest else {
            throw AssetError.integrity
        }
        return bytes
    }

    /// Prepare only opaque PNGs used by the pinned stage. Other formats, translucent
    /// variants and external-buffer views continue through the original loader.
    nonisolated private static func opaquePixels(_ bytes: Data, externalDirectory: URL?,
                                                  pixelBudget: Int) throws -> [Int: ArenaOpaquePNG.Image] {
        let (json, binary) = try GLTFModel.unpack(bytes)
        let textures = json["textures"] as? [[String: Any]] ?? []
        let images = json["images"] as? [[String: Any]] ?? []
        let views = json["bufferViews"] as? [[String: Any]] ?? []
        let buffers = json["buffers"] as? [[String: Any]] ?? []
        var indices = Set<Int>()
        func include(_ ref: Any?) {
            guard let ref = ref as? [String: Any], let i = ref["index"] as? Int, textures.indices.contains(i),
                  let source = textures[i]["source"] as? Int, images.indices.contains(source) else { return }
            indices.insert(source)
        }
        for material in json["materials"] as? [[String: Any]] ?? [] {
            let pbr = material["pbrMetallicRoughness"] as? [String: Any]
            let alpha = material["alphaMode"] as? String ?? "OPAQUE"
            if alpha == "OPAQUE" || (alpha == "MASK" && material["alphaCutoff"] as? Double == 0) {
                include(pbr?["baseColorTexture"])
            }
            include((material["extras"] as? [String: Any])?["sf3Lightmap"])
        }

        var remaining = pixelBudget
        var result = [Int: ArenaOpaquePNG.Image]()
        for index in indices.sorted() {
            try Task.checkCancellation()
            let image = images[index]
            let source: Data
            if let uri = image["uri"] as? String {
                // Do not let prefetch traverse beyond the stage directory. The original
                // renderer still handles any other URI form it already supported.
                guard let directory = externalDirectory,
                      !uri.isEmpty, uri == (uri as NSString).lastPathComponent, uri != ".", uri != ".." else { continue }
                let url = directory.appendingPathComponent(uri)
                guard let info = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                      info.isRegularFile == true, info.isSymbolicLink == false, let size = info.fileSize,
                      (1...(64 * 1024 * 1024)).contains(size), let data = try? Data(contentsOf: url), data.count == size else { continue }
                source = data
            } else {
                guard let viewIndex = image["bufferView"] as? Int, views.indices.contains(viewIndex),
                      views[viewIndex]["buffer"] as? Int == 0, buffers.first?["uri"] == nil, let binary,
                      let length = views[viewIndex]["byteLength"] as? Int, length > 0 else { continue }
                let offset = views[viewIndex]["byteOffset"] as? Int ?? 0
                guard offset >= 0, offset <= binary.count, length <= binary.count - offset else { continue }
                let start = binary.startIndex + offset
                source = binary.subdata(in: start..<(start + length))
            }
            if let decoded = ArenaOpaquePNG.decode(source, maximumPixelBytes: remaining, isCancelled: { Task.isCancelled }) {
                result[index] = decoded
                remaining -= decoded.rgba.count
                if remaining == 0 { break }
            }
        }
        return result
    }

    convenience init(url: URL, kind: Kind = .palace) throws {
        try self.init(url: url, kind: kind, bytes: Self.verifiedBytes(url: url, kind: kind), opaquePixels: [:])
    }

    convenience init(preparedAutumnLobby prepared: PreparedAutumnLobby) throws {
        try self.init(url: prepared.url, kind: .autumnLobby, bytes: prepared.bytes, opaquePixels: prepared.opaquePixels)
    }

    convenience init(preparedPalace prepared: PreparedPalace) throws {
        try self.init(url: prepared.url, kind: .palace, bytes: prepared.bytes, opaquePixels: prepared.opaquePixels)
    }

    private init(url: URL, kind: Kind, bytes: Data, opaquePixels: [Int: ArenaOpaquePNG.Image]) throws {
        self.kind = kind
        let decoded = try GLTFModel(url: url, sourceData: bytes, animations: [], maxTexture: 2048, physicallyBased: true,
                                    sourceLocationMaterials: kind == .palace ? Self.palaceSourceLocationMaterials : Self.autumnSourceLocationMaterials,
                                    preparedOpaquePixels: opaquePixels)
        guard !decoded.hasSkinning, decoded.node(named: "SF3_Stage_Meters") != nil,
              decoded.node(named: kind == .palace ? "palace_exterior_raid" : "dojo_autumn_lobby") != nil else { throw AssetError.incomplete }
        model = decoded
    }

    func makeRoot() -> SCNNode {
        let instance = model.instantiate()
        // Only these digest-verified stage exports forced transparent surfaces
        // double-sided. LocationShader's FORWARDBASE pass uses constant Back
        // culling independently of its alpha blend and depth-write settings.
        let transparentBackFaces: Set<String> = kind == .palace
            ? ["alfa_gold", "alfa_back", "cust05", "cust04"]
            : ["ALFA", "ALFA_BG", "Leavs_mat"]
        // Texture filtering is a source descriptor independent of whether the
        // recovered original mip payloads are installed. UIImage supplies host-generated levels;
        // restoring nearest-level selection does not claim pixel equivalence.
        let sourceMipMaterials = kind == .palace
            ? Self.palaceSourceLocationMaterials
            : Self.autumnSourceLocationMaterials.union(["Matcup_mat"])
        func sourceBilinear(_ property: SCNMaterialProperty) {
            property.minificationFilter = .linear
            property.magnificationFilter = .linear
            property.mipFilter = .nearest
            property.wrapS = .repeat
            property.wrapT = .repeat
            property.maxAnisotropy = 1
        }
        for material in instance.materials {
            if sourceMipMaterials.contains(material.name ?? "") {
                sourceBilinear(material.diffuse)
                if !(kind == .palace && material.name == "back") {
                    sourceBilinear(material.multiply)
                }
            }
            if transparentBackFaces.contains(material.name ?? "") {
                material.isDoubleSided = false
                material.cullMode = .back
            }
            if kind == .palace && material.name == "back" {
                // The original background placeholder has one mip only. Do
                // not apply the exporter-wide trilinear sampler to it.
                material.multiply.minificationFilter = .linear
                material.multiply.magnificationFilter = .linear
                material.multiply.mipFilter = .none
                material.multiply.wrapS = .repeat
                material.multiply.wrapT = .repeat
                material.multiply.maxAnisotropy = 1
            }
        }
        let root = instance.root
        root.name = kind == .palace ? "duel.stage.palace" : "duel.stage.autumnLobby"
        // The source environment is already lit. Casting its geometry's
        // shadows again would darken the characters under the baked roof.
        root.enumerateChildNodes { node, _ in node.castsShadow = false }
        return root
    }
}
