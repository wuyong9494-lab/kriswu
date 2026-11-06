import Foundation

/// Keep lobby selections compatible with both map families and the actual
/// source-roster restrictions. Missing imported maps do not disable project maps.
public struct ArenaMapSelection: Equatable, Sendable {
    public let mode: ArenaGame.Mode
    public let mapID: String?

    public static func supportsImportedHero(_ mode: ArenaGame.Mode) -> Bool {
        true
    }

    public static func resolve(mode requestedMode: ArenaGame.Mode, mapID: String?,
                               importedHero: Bool,
                               importedMaps: [ArenaGame.Mode: [String]]) -> Self {
        let mode = importedHero && !supportsImportedHero(requestedMode) ? .stars : requestedMode
        let imported = importedMaps[mode] ?? []
        let project = ArenaMap.selectionPool(for: mode)
        if let mapID, imported.contains(mapID) || project.contains(where: { $0.id == mapID }) {
            return Self(mode: mode, mapID: mapID)
        }
        // Project heroes may use random rotation. Imported heroes need an
        // explicit map so the lobby preview and the match use the same layout.
        return Self(mode: mode, mapID: importedHero ? (imported.first ?? project.first?.id) : nil)
    }
}
