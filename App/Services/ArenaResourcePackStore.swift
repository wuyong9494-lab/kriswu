import Combine
import CryptoKit
import Foundation

/// Single local source for imported assets. Content is installed transactionally;
/// choosing a pack never changes the game's Brawler IDs, saves, or network rules.
@MainActor
final class ArenaResourcePackStore: ObservableObject {
    static let shared = ArenaResourcePackStore()
    @Published private(set) var manifest: ArenaResourcePackManifest?
    @Published private(set) var importing = false
    @Published private(set) var loadingBundledPack = false
    @Published private(set) var progress = 0.0
    @Published private(set) var error: String?
    @Published private(set) var lobbySceneError: String?
    @Published private(set) var lobbySceneReload = 0
    @Published private(set) var themeID: String?
    @Published private(set) var lobbyMusicID: String?
    @Published private(set) var selectedHeroID: String?
    @Published private(set) var combatHeroID: String?
    @Published private(set) var enabled = true
    private var root: URL?
    private var approvedPaths = Set<String>()
    private let defaults: UserDefaults
    private let directory: URL

    var hasBundledPack: Bool {
        Bundle.main.url(forResource: "arena-original-resources", withExtension: "arenapack") != nil
    }

    var preparingResources: Bool { loadingBundledPack || importing }

    var currentTheme: ArenaResourcePackManifest.Theme? {
        guard enabled, let manifest else { return nil }
        return manifest.themes.first { $0.id == themeID }
            ?? manifest.themes.first { $0.id == manifest.defaultThemeID }
            ?? manifest.themes.first
    }

    var selectedHero: ArenaResourcePackManifest.Hero? {
        guard let manifest else { return nil }
        return manifest.heroes.first { $0.id == selectedHeroID }
    }

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArenaResourcePacks", isDirectory: true)
        enabled = defaults.object(forKey: "arena.resources.enabled") as? Bool ?? true
        themeID = defaults.string(forKey: "arena.resources.theme")
        lobbyMusicID = defaults.string(forKey: "arena.resources.lobbyMusic")
        selectedHeroID = defaults.string(forKey: "arena.resources.hero")
        combatHeroID = defaults.string(forKey: "arena.resources.combatHero")
        restore()
    }

    func url(for relativePath: String) -> URL? {
        guard let root, approvedPaths.contains(relativePath), ArenaResourcePackManifest.safePath(relativePath) else { return nil }
        let result = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: result.path) else { return nil }
        return result
    }

    func selectTheme(id: String) {
        guard manifest?.themes.contains(where: { $0.id == id }) == true else { return }
        themeID = id
        lobbySceneError = nil
        lobbyMusicID = nil
        defaults.set(id, forKey: "arena.resources.theme")
        defaults.removeObject(forKey: "arena.resources.lobbyMusic")
        ArenaSound.shared.themeChanged()
    }

    func selectLobbyMusic(id: String?) {
        guard id == nil || manifest?.music.contains(where: { $0.id == id }) == true else { return }
        lobbyMusicID = id
        defaults.set(id, forKey: "arena.resources.lobbyMusic")
        ArenaSound.shared.themeChanged()
    }

    func selectHero(id: String) {
        guard manifest?.heroes.contains(where: { $0.id == id && $0.modelFile != nil }) == true else { return }
        selectedHeroID = id
        defaults.set(id, forKey: "arena.resources.hero")
    }

    func selectCombatHero(id: String?) {
        if let id {
            guard ArenaImportedCombatAssets.shared.hero(id: id)?.canPlay == true else { return }
            selectHero(id: id)
        }
        combatHeroID = id
        defaults.set(id, forKey: "arena.resources.combatHero")
        defaults.set(true, forKey: "arena.resources.hasChosenCombatHero")
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: "arena.resources.enabled")
        Task { await ArenaImportedSourceRules.shared.loadIfNeeded(store: self) }
        ArenaSound.shared.themeChanged()
    }

    func music(for role: String) -> (track: ArenaResourcePackManifest.Music, url: URL)? {
        guard enabled, let manifest else { return nil }
        var track: ArenaResourcePackManifest.Music?
        if role == "lobby" {
            if let lobbyMusicID { track = manifest.music.first { $0.id == lobbyMusicID } }
            if track == nil, let cue = currentTheme?.musicCue {
                track = manifest.music.first { $0.cues.contains(cue) }
            }
        }
        if track == nil, let id = manifest.musicBindings[role] { track = manifest.music.first { $0.id == id } }
        guard let track, let url = url(for: track.file) else { return nil }
        return (track, url)
    }

    func clearError() { error = nil }

    func reportLobbySceneFailure(themeID: String) {
        guard currentTheme?.id == themeID else { return }
        lobbySceneError = "大厅动画暂未加载，当前显示静态背景。"
    }

    func retryLobbyScene() {
        lobbySceneError = nil
        lobbySceneReload &+= 1
    }

    /// The same verified archive can be injected into an authorized private build
    /// or picked in Files. No network token or remote download URL enters the App.
    func loadBundledPackIfNeeded() async {
        guard !preparingResources,
              let url = Bundle.main.url(forResource: "arena-original-resources", withExtension: "arenapack") else { return }
        loadingBundledPack = true
        error = nil
        defer { loadingBundledPack = false }
        do {
            let bundled = try await Task.detached(priority: .utility) {
                try ArenaResourcePackArchive.readManifest(from: url)
            }.value
            let identity = try Self.identity(bundled)
            // A new bundled payload is installed even when an older version of
            // the same IPA was imported before. Respect a later manual choice
            // after this exact bundled version has already been handled.
            if manifest != nil, defaults.string(forKey: "arena.resources.bundledIdentity") == identity { return }
            if let manifest, try Self.identity(manifest) == identity {
                defaults.set(identity, forKey: "arena.resources.bundledIdentity")
                return
            }
            await install(from: url)
            if let manifest, try Self.identity(manifest) == identity {
                defaults.set(identity, forKey: "arena.resources.bundledIdentity")
            }
        } catch { self.error = error.localizedDescription }
    }

    private static func identity(_ value: ArenaResourcePackManifest) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }

    func install(from source: URL) async {
        guard !importing else { return }
        importing = true
        progress = 0
        error = nil
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped { source.stopAccessingSecurityScopedResource() }
            importing = false
        }
        let destination = directory
        let owner = self
        do {
            let installed = try await Task.detached(priority: .userInitiated) {
                try ArenaResourcePackArchive.install(from: source, directory: destination) { value in
                    Task { @MainActor in owner.progress = max(owner.progress, value) }
                }
            }.value
            activate(installed.manifest, at: installed.root)
            if enabled, !defaults.bool(forKey: "arena.resources.hasChosenCombatHero"),
               let first = ArenaImportedCombatAssets.shared.playable.first {
                selectCombatHero(id: first.id)
            }
            progress = 1
            ArenaSound.shared.themeChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func activate(_ value: ArenaResourcePackManifest, at root: URL) {
        self.root = root
        approvedPaths = Set(value.files.map(\.path))
        manifest = value
        lobbySceneError = nil
        ArenaImportedFonts.prepare(manifest: value, resourceURL: url(for:))
        Task { await ArenaImportedSourceRules.shared.loadIfNeeded(store: self) }
        if !value.themes.contains(where: { $0.id == themeID }) { themeID = value.defaultThemeID ?? value.themes.first?.id }
        if !value.heroes.contains(where: { $0.id == selectedHeroID }) { selectedHeroID = nil }
        if value.combatFile == nil || !value.heroes.contains(where: { $0.id == combatHeroID }) {
            combatHeroID = nil
            defaults.removeObject(forKey: "arena.resources.combatHero")
        }
        if !value.music.contains(where: { $0.id == lobbyMusicID }) { lobbyMusicID = nil }
    }

    private func restore() {
        let pointer = directory.appendingPathComponent("active.json")
        guard let data = try? Data(contentsOf: pointer),
              let entry = try? JSONDecoder().decode(ArenaResourcePackArchive.Pointer.self, from: data),
              UUID(uuidString: entry.folder) != nil else { return }
        let location = directory.appendingPathComponent(entry.folder, isDirectory: true)
        guard let raw = try? Data(contentsOf: location.appendingPathComponent("manifest.json")),
              raw.count <= ArenaResourcePackManifest.maximumHeaderBytes,
              let value = try? JSONDecoder().decode(ArenaResourcePackManifest.self, from: raw),
              raw.count <= value.headerByteLimit,
              (try? value.validate()) != nil else { return }
        // The marker is written only after every asset was hashed. Check size here
        // without rereading hundreds of megabytes on every lobby entry.
        guard value.files.allSatisfy({ item in
            let file = location.appendingPathComponent(item.path)
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
            return values?.isRegularFile == true && values?.isSymbolicLink != true && values?.fileSize == item.bytes
        }) else { return }
        activate(value, at: location)
    }
}
