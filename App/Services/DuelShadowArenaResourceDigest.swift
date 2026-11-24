import CryptoKit
import Foundation

/// Computes and caches a deterministic SHA-256 compatibility fingerprint for the
/// bundled 4-hero Shadow Arena assets (Wu Yong, Liu Quanwei, Xu Xiao, Sun Deng,
/// their weapons, configs, and Sanctuary stage) plus the ShiftCore rules version.
/// Requires zero legacy 707 FighterPrivate files.
enum DuelShadowArenaResourceDigest {
    private actor Cache {
        private var value: String?
        func get() -> String? { value }
        func set(_ newValue: String) { value = newValue }
    }
    private static let cache = Cache()

    static func computeAsync(bundle: Bundle = .main) async -> String {
        if bundle == .main, let cached = await cache.get() {
            return cached
        }
        let urls = collectAssetURLs(bundle: bundle)
        let digest = await Task.detached(priority: .userInitiated) {
            Self.hash(urls: urls)
        }.value
        if bundle == .main {
            await cache.set(digest)
        }
        return digest
    }

    private static func collectAssetURLs(bundle: Bundle) -> [(label: String, url: URL?)] {
        let names: [(String, String)] = [
            ("DuelChar_wuYong", "glb"), ("DuelChar_wuYong", "json"), ("DuelWeapon_wuYong", "glb"),
            ("DuelChar_liuQuanwei", "glb"), ("DuelChar_liuQuanwei", "json"), ("DuelWeapon_liuQuanwei", "glb"),
            ("DuelChar_xuXiao", "glb"), ("DuelChar_xuXiao", "json"), ("DuelWeapon_xuXiao", "glb"),
            ("DuelChar_sunDeng", "glb"), ("DuelChar_sunDeng", "json"),
            ("DuelWeapon_sunDeng", "glb"), ("DuelWeaponL_sunDeng", "glb"),
            ("DuelStage_Sanctuary", "glb")
        ]
        return names.map { name, ext in
            let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "DuelCharacters")
                ?? bundle.url(forResource: name, withExtension: ext)
            return ("\(name).\(ext)", url)
        }
    }

    private static func hash(urls: [(label: String, url: URL?)]) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("shadow-arena-net-v\(DuelShadowArenaNetworkProtocol.protocolVersion)-r\(DuelShadowArenaNetworkProtocol.rulesVersion)\n".utf8))
        for item in urls {
            hasher.update(data: Data("\(item.label):".utf8))
            if let url = item.url, let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                let fileDigest = SHA256.hash(data: data)
                hasher.update(data: Data(fileDigest))
            } else {
                hasher.update(data: Data("missing".utf8))
            }
            hasher.update(data: Data("\n".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
