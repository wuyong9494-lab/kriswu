import Foundation
import CryptoKit
import SceneKit

/// A separately staged scenery asset. The application never downloads or
/// unpacks an APK. Converted geometry and textures live for one match only.
@MainActor
final class DuelStageAsset {
    enum AssetError: Error { case integrity, incomplete }
    static let digest = "185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8"
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

    init(url: URL, kind: Kind = .palace) throws {
        self.kind = kind
        let expectedBytes = kind == .palace ? 9_292_540 : 11_164_484
        let expectedDigest = kind == .palace ? Self.digest : "616d5cb125f49c6b378cf280c90cf10e927b5b71aa461ecb34d7cdaad08c62c1"
        let bytes = try Data(contentsOf: url)
        guard bytes.count == expectedBytes,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == expectedDigest else {
            throw AssetError.integrity
        }
        let decoded = try GLTFModel(url: url, animations: [], maxTexture: 2048, physicallyBased: true,
                                    sourceLocationMaterials: kind == .palace ? Self.palaceSourceLocationMaterials : Self.autumnSourceLocationMaterials)
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
