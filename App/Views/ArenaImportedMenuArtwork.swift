import SwiftUI
import UIKit

/// Independent artwork selected from a named source button descendant. Text,
/// counters, enabled state and actions continue to come from the actual App.
@MainActor
final class ArenaImportedMenuAssets: ObservableObject {
    static let shared = ArenaImportedMenuAssets()
    private let store: ArenaResourcePackStore
    private var loadedKey: CacheKey?
    private var items: [String: Item] = [:]
    private var images: [String: UIImage] = [:]

    init(store: ArenaResourcePackStore = .shared) { self.store = store }

    /// Roles: heroes, shop, friends, settings, play. The play artwork is an
    /// unlabelled button background; other roles are independent icon graphics.
    func image(for role: String) -> UIImage? {
        guard store.enabled else { return nil }
        refreshIfNeeded()
        if let image = images[role] { return image }
        guard let item = items[role], let url = store.url(for: item.file),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        guard (item.sourcePixelScale ?? 1).isFinite, (1...16).contains(item.sourcePixelScale ?? 1) else { return nil }
        let scaled = image.cgImage.map { UIImage(cgImage: $0, scale: CGFloat(item.sourcePixelScale ?? 1), orientation: image.imageOrientation) } ?? image
        images[role] = scaled
        return scaled
    }

    func capInsets(for role: String) -> EdgeInsets {
        refreshIfNeeded()
        guard let item = items[role], let inset = item.capInsetsPixels else { return EdgeInsets() }
        let scale = CGFloat(max(item.sourcePixelScale ?? 1, 1))
        return EdgeInsets(top: CGFloat(inset.top) / scale, leading: CGFloat(inset.left) / scale,
                          bottom: CGFloat(inset.bottom) / scale, trailing: CGFloat(inset.right) / scale)
    }

    private func refreshIfNeeded() {
        guard let pack = store.manifest, let path = pack.menuArtworkFile,
              let file = pack.files.first(where: { $0.path == path && $0.kind == .data }),
              file.bytes <= 1_048_576, let url = store.url(for: path) else {
            reset(); return
        }
        let key = CacheKey(url: url, sha256: file.sha256)
        guard key != loadedKey else { return }
        reset()
        loadedKey = key
        guard let data = try? Data(contentsOf: url), data.count == file.bytes,
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
              catalog.schemaVersion == 1, catalog.items.count <= 100,
              Set(catalog.items.map(\.role)).count == catalog.items.count else { return }
        let imagePaths = Set(pack.files.filter { $0.kind == .image }.map(\.path))
        items = Dictionary(uniqueKeysWithValues: catalog.items.filter { imagePaths.contains($0.file) }.map { ($0.role, $0) })
    }

    private func reset() { loadedKey = nil; items.removeAll(); images.removeAll() }
    private struct CacheKey: Equatable { let url: URL; let sha256: String }
    private struct Catalog: Decodable { let schemaVersion: Int; let items: [Item] }
    private struct Insets: Decodable { let top: Double; let left: Double; let bottom: Double; let right: Double }
    private struct Item: Decodable {
        let role: String; let file: String
        let sourcePixelScale: Double?
        let capInsetsPixels: Insets?
    }
}

/// Optional non-interactive layer for existing buttons. Its store observation
/// refreshes artwork after installing a different approved local resource pack.
@MainActor
struct ArenaImportedMenuIcon: View {
    let role: String
    @ObservedObject private var store: ArenaResourcePackStore
    @StateObject private var artwork: ArenaImportedMenuAssets

    init(role: String, store: ArenaResourcePackStore = .shared) {
        self.role = role
        self.store = store
        _artwork = StateObject(wrappedValue: ArenaImportedMenuAssets(store: store))
    }

    var body: some View {
        Group {
            if store.manifest != nil, let image = artwork.image(for: role) {
                Image(uiImage: image).resizable().scaledToFit()
            } else { Color.clear }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
