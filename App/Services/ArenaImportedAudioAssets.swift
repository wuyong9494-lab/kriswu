import Foundation

/// Source-cue lookup only. ArenaSound owns playback, event timing and the user's
/// mute/volume settings; no audio file is decoded by this resolver.
@MainActor
final class ArenaImportedAudioAssets {
    static let shared = ArenaImportedAudioAssets()

    struct Parameters: Decodable, Sendable {
        let minVolumePercent: Double?
        let maxVolumePercent: Double?
        let minPitchPercent: Double?
        let maxPitchPercent: Double?
        let priority: Int?
        let maximumByType: Int?
        let maxRepeatMs: Double?
        let loop: Bool?
        let sequence: Bool?
        let manualReset: Bool?
        let startDelayMinMs: Double?
        let startDelayMaxMs: Double?
        let onlyWhenInView: Bool?
        let maxVolumeScaleLimit: Double?
        let noSoundScaleLimit: Double?
        let padEmptyToEndMs: Double?
    }

    struct Variant: Sendable {
        /// Original CSV variant index, including gaps for absent background files.
        let index: Int
        let url: URL
        let sourceFile: String
        let parameters: Parameters
        var minVolumePercent: Double? { parameters.minVolumePercent }
        var maxVolumePercent: Double? { parameters.maxVolumePercent }
        var minPitchPercent: Double? { parameters.minPitchPercent }
        var maxPitchPercent: Double? { parameters.maxPitchPercent }
        var loop: Bool? { parameters.loop }
        var maximumByType: Int? { parameters.maximumByType }
        var maxRepeatMs: Double? { parameters.maxRepeatMs }
        var sequence: Bool? { parameters.sequence }
        var manualReset: Bool? { parameters.manualReset }
        var startDelayMinMs: Double? { parameters.startDelayMinMs }
        var startDelayMaxMs: Double? { parameters.startDelayMaxMs }
    }

    struct Cue: Sendable {
        let id: String
        let variants: [Variant]
        let sourceVariantCount: Int
        let unavailableVariantIndices: [Int]
        /// Source first-row values for cue-level budgets. The selected variant's
        /// own parameters take precedence for volume, pitch, loop and delay.
        let parameters: Parameters
        var minVolumePercent: Double? { parameters.minVolumePercent }
        var maxVolumePercent: Double? { parameters.maxVolumePercent }
        var minPitchPercent: Double? { parameters.minPitchPercent }
        var maxPitchPercent: Double? { parameters.maxPitchPercent }
        var loop: Bool? { parameters.loop }
        var maximumByType: Int? { parameters.maximumByType }
        var maxRepeatMs: Double? { parameters.maxRepeatMs }
        var sequence: Bool? { parameters.sequence }
        var manualReset: Bool? { parameters.manualReset }
        var startDelayMinMs: Double? { parameters.startDelayMinMs }
        var startDelayMaxMs: Double? { parameters.startDelayMaxMs }
    }

    private let store: ArenaResourcePackStore
    private var loadedKey: CacheKey?
    private var definitions: [String: Definition] = [:]
    private var bindings: [Binding] = []
    private var fileKinds: [String: ArenaResourcePackManifest.File.Kind] = [:]
    private(set) var errorDescription: String?

    init(store: ArenaResourcePackStore = .shared) { self.store = store }

    /// Resolve during menu/match preparation, then cache the resulting buffers
    /// in the mixer. This method performs validated local URL lookups.
    func cues(event: String, heroID: String? = nil,
              projectileID: String? = nil, areaEffectID: String? = nil) -> [Cue] {
        refreshIfNeeded()
        var seen = Set<String>()
        let ids = bindings.filter {
            $0.event == event && $0.heroID == heroID
                && (projectileID == nil || $0.logicProjectileID == projectileID)
                && (areaEffectID == nil || $0.logicAreaEffectID == areaEffectID)
        }.flatMap(\.cueIDs).filter { seen.insert($0).inserted }
        return ids.compactMap { resolve($0) }
    }

    func cue(id: String) -> Cue? {
        refreshIfNeeded()
        return resolve(id)
    }

    private func resolve(_ id: String) -> Cue? {
        guard let definition = definitions[id], let first = definition.variants.first else { return nil }
        let available: [Variant] = definition.variants.compactMap { variant in
            guard variant.status == "converted", let file = variant.file, fileKinds[file] == .music,
                  let url = store.url(for: file) else { return nil }
            return Variant(index: variant.index, url: url, sourceFile: variant.sourceFile, parameters: variant.parameters)
        }
        guard !available.isEmpty else { return nil }
        let indices = Set(available.map(\.index))
        return Cue(id: definition.id, variants: available, sourceVariantCount: definition.variants.count,
                   unavailableVariantIndices: definition.variants.map(\.index).filter { !indices.contains($0) },
                   parameters: first.parameters)
    }

    private func refreshIfNeeded() {
        guard store.enabled, let pack = store.manifest, let path = pack.gameAudioFile,
              let file = pack.files.first(where: { $0.path == path && $0.kind == .data }),
              file.bytes <= 32 * 1024 * 1024, let url = store.url(for: path) else {
            reset(); return
        }
        let key = CacheKey(url: url, sha256: file.sha256)
        guard key != loadedKey else { return }
        reset()
        loadedKey = key
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count == file.bytes else { throw CocoaError(.fileReadCorruptFile) }
            let catalog = try JSONDecoder().decode(Catalog.self, from: data)
            guard catalog.schemaVersion == 1, catalog.cues.count <= 10_000, catalog.bindings.count <= 30_000,
                  Set(catalog.cues.map(\.id)).count == catalog.cues.count,
                  catalog.cues.allSatisfy({ !$0.id.isEmpty && $0.variants.count <= 1_000
                      && Set($0.variants.map(\.index)).count == $0.variants.count
                      && $0.variants.allSatisfy({ $0.index >= 0 }) }) else { throw CocoaError(.fileReadCorruptFile) }
            definitions = Dictionary(uniqueKeysWithValues: catalog.cues.map { ($0.id, $0) })
            bindings = catalog.bindings
            fileKinds = Dictionary(uniqueKeysWithValues: pack.files.map { ($0.path, $0.kind) })
        } catch { errorDescription = "导入的音效清单暂时无法读取" }
    }

    private func reset() {
        loadedKey = nil
        definitions.removeAll()
        bindings.removeAll()
        fileKinds.removeAll()
        errorDescription = nil
    }

    private struct CacheKey: Equatable { let url: URL; let sha256: String }
    private struct Catalog: Decodable {
        let schemaVersion: Int
        let cues: [Definition]
        let bindings: [Binding]
    }
    private struct Definition: Decodable {
        let id: String
        let variants: [SourceVariant]
    }
    private struct SourceVariant: Decodable {
        let index: Int
        let sourceFile: String
        let file: String?
        let status: String
        let parameters: Parameters
    }
    private struct Binding: Decodable {
        let heroID: String?
        let event: String
        let cueIDs: [String]
        let logicProjectileID: String?
        let logicAreaEffectID: String?
    }
}
