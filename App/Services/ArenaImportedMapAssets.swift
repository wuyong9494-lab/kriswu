import Foundation

/// The validated value is passed into a match. Replacing a resource pack after
/// selection cannot silently replace the selected layout with a classic map.
struct ArenaImportedMapChoice: Equatable {
    let descriptor: ArenaImportedMap
    let plan: ArenaImportedMap.RuntimePlan
    let environmentThemeID: String
    init(descriptor: ArenaImportedMap, environmentThemeID: String) throws {
        self.plan = try descriptor.runtimePlan()
        self.descriptor = descriptor
        self.environmentThemeID = environmentThemeID
    }
    static func == (a: Self, b: Self) -> Bool {
        a.descriptor == b.descriptor && a.environmentThemeID == b.environmentThemeID
    }
}

@MainActor
final class ArenaImportedMapAssets {
    static let shared = ArenaImportedMapAssets()
    struct Entry: Decodable, Identifiable {
        let id: String
        let title: String
        let file: String
        let environmentThemeID: String
        let runtimeMode: String
    }
    private struct Catalog: Decodable { let schemaVersion: Int; let maps: [Entry] }
    private var loadedKey: String?
    private var entries: [Entry] = []
    private var choices: [String: ArenaImportedMapChoice] = [:]
    private(set) var lastError: String?

    func maps(for mode: ArenaGame.Mode) -> [Entry] {
        refresh()
        return entries.filter { $0.runtimeMode == mode.rawValue }
    }

    func choice(id: String) throws -> ArenaImportedMapChoice {
        refresh()
        if let cached = choices[id] { return cached }
        let store = ArenaResourcePackStore.shared
        guard let entry = entries.first(where: { $0.id == id }),
              let asset = store.manifest?.files.first(where: { $0.path == entry.file && $0.kind == .data }),
              asset.bytes <= 4 * 1024 * 1024, let url = store.url(for: entry.file) else {
            throw ArenaResourcePackManifest.ValidationError.invalid("这张地图的资源暂时不可用")
        }
        let data = try Data(contentsOf: url)
        guard data.count == asset.bytes else { throw CocoaError(.fileReadCorruptFile) }
        let descriptor = try JSONDecoder().decode(ArenaImportedMap.self, from: data)
        let selected = try ArenaImportedMapChoice(descriptor: descriptor, environmentThemeID: entry.environmentThemeID)
        guard selected.plan.mode.rawValue == entry.runtimeMode, selected.plan.map.id == entry.id else {
            throw ArenaResourcePackManifest.ValidationError.invalid("地图规则与清单不一致")
        }
        choices[id] = selected
        return selected
    }

    private func refresh() {
        let store = ArenaResourcePackStore.shared
        guard store.enabled, let pack = store.manifest, let path = pack.playableMapsFile,
              let asset = pack.files.first(where: { $0.path == path && $0.kind == .data }),
              asset.bytes <= 8 * 1024 * 1024, let url = store.url(for: path) else {
            loadedKey = nil; entries.removeAll(); choices.removeAll(); return
        }
        let key = url.path + "@" + asset.sha256
        guard key != loadedKey else { return }
        loadedKey = key; entries.removeAll(); choices.removeAll(); lastError = nil
        do {
            let data = try Data(contentsOf: url)
            guard data.count == asset.bytes else { throw CocoaError(.fileReadCorruptFile) }
            let catalog = try JSONDecoder().decode(Catalog.self, from: data)
            guard catalog.schemaVersion == 1, catalog.maps.count <= 2_000,
                  Set(catalog.maps.map(\.id)).count == catalog.maps.count else { throw CocoaError(.fileReadCorruptFile) }
            let paths = Set(pack.files.filter { $0.kind == .data }.map(\.path))
            entries = catalog.maps.filter { paths.contains($0.file) && ArenaGame.Mode(rawValue: $0.runtimeMode) != nil }
        } catch { lastError = "地图清单暂时无法读取" }
    }
}
