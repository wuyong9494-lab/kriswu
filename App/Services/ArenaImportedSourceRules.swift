import Combine
import Foundation

/// The complete source rule registry is loaded once per verified payload.
/// It never changes which combat mechanics the executable actually supports.
@MainActor
final class ArenaImportedSourceRules: ObservableObject {
    static let shared = ArenaImportedSourceRules()
    @Published private(set) var registry: ArenaSourceRuleRegistry?
    @Published private(set) var loading = false
    @Published private(set) var errorDescription: String?
    private var requestKey: String?

    func loadIfNeeded(store: ArenaResourcePackStore = .shared) async {
        guard store.enabled, let pack = store.manifest, let path = pack.sourceRulesFile,
              let file = pack.files.first(where: { $0.path == path && $0.kind == .data }),
              file.bytes <= 32 * 1024 * 1024, let url = store.url(for: path) else {
            requestKey = nil
            registry = nil
            loading = false
            errorDescription = nil
            return
        }
        let key = url.path + "@" + file.sha256
        guard key != requestKey else { return }
        requestKey = key
        registry = nil
        errorDescription = nil
        loading = true
        let sourceSHA256 = pack.sourceSHA256
        do {
            let loaded = try await Task.detached(priority: .utility) {
                let raw = try Data(contentsOf: url, options: .mappedIfSafe)
                guard raw.count == file.bytes else { throw CocoaError(.fileReadCorruptFile) }
                let registry = try ArenaSourceRuleRegistry(data: raw)
                guard registry.catalog.sourceIPASHA256 == sourceSHA256 else { throw CocoaError(.fileReadCorruptFile) }
                return registry
            }.value
            guard requestKey == key else { return }
            registry = loaded
            loading = false
        } catch {
            guard requestKey == key else { return }
            errorDescription = "英雄技能资料未能完整读取。"
            loading = false
        }
    }

    func retry(store: ArenaResourcePackStore = .shared) async {
        requestKey = nil
        await loadIfNeeded(store: store)
    }
}
