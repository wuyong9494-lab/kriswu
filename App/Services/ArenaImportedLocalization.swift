import Combine
import CryptoKit
import Foundation

@MainActor
final class ArenaImportedLocalization: ObservableObject {
    static let shared = ArenaImportedLocalization()
    @Published private(set) var catalog: ArenaSourceLocalization?
    private var generation = UUID()

    func load(store: ArenaResourcePackStore = .shared) async {
        let token = UUID()
        generation = token
        catalog = nil
        guard store.enabled, let pack = store.manifest, let path = pack.interfaceLocalizationFile,
              let file = pack.files.first(where: { $0.path == path && $0.kind == .data }),
              file.bytes <= 8 * 1024 * 1024, let url = store.url(for: path) else { return }
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count == file.bytes,
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let result = try ArenaSourceLocalization(data: data, expectedSourceSHA256: pack.sourceSHA256)
            try Task.checkCancellation()
            return result
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
            guard generation == token, !Task.isCancelled, store.enabled else { return }
            catalog = result
        } catch {
            // Keep the functional native label if a pack is disabled or invalid.
        }
    }

    func menuTitle(_ title: String) -> String {
        guard catalog?.locale == "CN" else { return title }
        let keys = ["商店":"TID_BUTTON_NAVI_SHOP", "英雄":"TID_BUTTON_NAVI_BRAWLERS",
                    "好友":"TID_BUTTON_NAVI_FRIENDS", "组队":"TID_TEAM_UP_TITLE",
                    "任务":"TID_BUTTON_QUESTS", "对战":"TID_BATTLE"]
        guard let key = keys[title] else { return title }
        return catalog?.plainText(key) ?? title
    }
}
