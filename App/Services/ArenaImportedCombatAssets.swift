import Foundation

@MainActor
final class ArenaImportedCombatAssets {
    static let shared = ArenaImportedCombatAssets()
    private struct Catalog: Decodable {
        let schemaVersion: Int
        let heroes: [ArenaSourceHero]
    }
    private var key: String?
    private var entries: [String: ArenaSourceHero] = [:]
    var playable: [ArenaSourceHero] {
        refresh()
        return entries.values.filter(\.canPlay).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func hero(id: String) -> ArenaSourceHero? { refresh(); return entries[id] }

    private func refresh() {
        let store = ArenaResourcePackStore.shared
        guard store.enabled, let pack = store.manifest, let path = pack.combatFile,
              let file = pack.files.first(where: { $0.path == path && $0.kind == .data }),
              file.bytes <= 16 * 1024 * 1024, let url = store.url(for: path) else {
            entries.removeAll(); key = nil; return
        }
        let current = url.path + "@" + file.sha256
        guard current != key else { return }
        key = current; entries.removeAll()
        guard let data = try? Data(contentsOf: url), data.count == file.bytes,
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data), catalog.schemaVersion == 1,
              catalog.heroes.count <= 1_000, Set(catalog.heroes.map(\.id)).count == catalog.heroes.count else { return }
        let declared = Set(pack.heroes.filter { $0.modelFile != nil && $0.modelHeight != nil }.map(\.id))
        for hero in catalog.heroes where declared.contains(hero.id) {
            entries[hero.id] = hero
        }
    }
}
