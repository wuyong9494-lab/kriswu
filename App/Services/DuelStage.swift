import Foundation
import CryptoKit
import SceneKit

/// A separately staged scenery asset. The application never downloads or
/// unpacks an APK. Converted geometry and textures live for one match only.
@MainActor
final class DuelStageAsset {
    enum AssetError: Error { case integrity, incomplete }
    static let digest = "185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8"
    static var bundledURL: URL? {
        Bundle.main.url(forResource: "SF3_Palace_Exterior", withExtension: "glb") ??
        Bundle.main.url(forResource: "SF3_Palace_Exterior", withExtension: "glb", subdirectory: "FighterPrivate")
    }
    let model: GLTFModel

    init(url: URL) throws {
        let bytes = try Data(contentsOf: url)
        guard bytes.count == 9_292_540,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == Self.digest else {
            throw AssetError.integrity
        }
        let decoded = try GLTFModel(url: url, animations: [], maxTexture: 2048, physicallyBased: true)
        guard !decoded.hasSkinning, decoded.node(named: "SF3_Stage_Meters") != nil,
              decoded.node(named: "palace_exterior_raid") != nil else { throw AssetError.incomplete }
        model = decoded
    }

    func makeRoot() -> SCNNode {
        let root = model.instantiate().root
        root.name = "duel.stage.palace"
        // The source environment is already lit. Casting its geometry's
        // shadows again would darken the characters under the baked roof.
        root.enumerateChildNodes { node, _ in node.castsShadow = false }
        return root
    }
}
