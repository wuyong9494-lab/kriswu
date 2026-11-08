import Foundation
import CryptoKit
import SceneKit

/// A separately staged scenery asset. The application never downloads or
/// unpacks an APK. Converted geometry and textures live for one match only.
@MainActor
final class DuelStageAsset {
    enum AssetError: Error { case integrity, incomplete }
    static let digest = "185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8"
    // Verified against the palace's original location shader and this exact
    // export. Other scenery and all characters retain their existing shading.
    private static let palaceSourceLocationMaterials: Set<String> = [
        "home_01", "gold_01", "back", "alfa_gold", "alfa_back",
        "cust05", "back_home", "cust04", "floor_01", "metal_01"
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
                                    sourceLocationMaterials: kind == .palace ? Self.palaceSourceLocationMaterials : [])
        guard !decoded.hasSkinning, decoded.node(named: "SF3_Stage_Meters") != nil,
              decoded.node(named: kind == .palace ? "palace_exterior_raid" : "dojo_autumn_lobby") != nil else { throw AssetError.incomplete }
        model = decoded
    }

    func makeRoot() -> SCNNode {
        let root = model.instantiate().root
        root.name = kind == .palace ? "duel.stage.palace" : "duel.stage.autumnLobby"
        // The source environment is already lit. Casting its geometry's
        // shadows again would darken the characters under the baked roof.
        root.enumerateChildNodes { node, _ in node.castsShadow = false }
        return root
    }
}
