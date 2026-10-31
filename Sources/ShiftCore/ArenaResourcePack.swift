import Foundation

/// A data-only resource pack. A decoded asset is deliberately distinct from a
/// registered, playable hero or map. The existing roster and save IDs are unchanged.
public struct ArenaResourcePackManifest: Codable, Sendable {
    public struct File: Codable, Sendable {
        public enum Kind: String, Codable, Sendable, Hashable { case model, image, music, data, notice, font }
        public let path: String
        public let bytes: Int
        public let sha256: String
        public let kind: Kind
    }

    public struct Hero: Codable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let modelFile: String?
        public let idleAnimation: String?
        public let modelHeight: Double?
        /// CPU-skinned source first-frame world bounds: min xyz, max xyz.
        public let modelBounds: [Double]?
        public let faceComposed: Bool
        public let notes: [String]
        public let primarySkill: String?
        public let ultimateSkill: String?
        /// Exact source clips, ranges and role bindings for this model.
        public let animationFile: String?
        public let faceFile: String?
    }

    public struct Theme: Codable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let backgroundFile: String
        public let musicCue: String?
        /// Complete nested timelines; backgroundFile remains the still preview.
        public let sceneFile: String?
        public let sceneExport: String?
        public let sceneSourceRect: [Double]?
        public let loadingSceneFile: String?
        public let loadingSceneExport: String?
        public let loadingJingleID: String?
    }

    public struct Font: Codable, Identifiable, Sendable {
        public let id: String
        public let file: String
        public let postScriptName: String
    }

    public struct Music: Codable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let file: String
        public let cues: [String]
        public let volumePercent: Double?
        public let loop: Bool?
    }

    public struct Map: Codable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let layoutFile: String
        public let width: Int
        public let height: Int
        public let modes: [String]
        public let unresolvedCells: Int
    }

    public let schemaVersion: Int
    public let id: String
    public let title: String
    public let sourceDescription: String
    public let sourceSHA256: String
    public let files: [File]
    public let heroes: [Hero]
    public let themes: [Theme]
    public let defaultThemeID: String?
    public let music: [Music]
    /// Keys: lobby, battle, win, lose. Values are exact Music IDs.
    public let musicBindings: [String: String]
    public let maps: [Map]
    public let gameAudioFile: String?
    public let menuArtworkFile: String?
    public let combatFile: String?
    public let playableMapsFile: String?
    public let mapArtworkFile: String?
    public let skillArtworkFile: String?
    /// Complete source definitions are distinct from executable combat support.
    public let sourceRulesFile: String?
    public let sourceMapCatalogFile: String?
    public let sourceAssetIndexFile: String?
    public let lobbyLayoutFile: String?
    public let fonts: [Font]?

    public enum ValidationError: Error, Equatable, LocalizedError {
        case invalid(String)
        public var errorDescription: String? {
            switch self { case .invalid(let detail): return "资源包无效：\(detail)" }
        }
    }

    // Schema 2 accommodates the measured full audio/layout/timeline catalogue.
    // Both limits are bounded; schema 1 retains its original acceptance limits.
    public static let maximumHeaderBytes = 16 * 1024 * 1024
    public static let maximumPayloadBytes = 2 * 1024 * 1024 * 1024
    public var headerByteLimit: Int { schemaVersion == 1 ? 8 * 1024 * 1024 : Self.maximumHeaderBytes }
    public var payloadByteLimit: Int { schemaVersion == 1 ? 1024 * 1024 * 1024 : Self.maximumPayloadBytes }
    public var fileCountLimit: Int { schemaVersion == 1 ? 10_000 : 20_000 }

    /// This validates the manifest and every reference. Archive extraction also
    /// verifies exact byte counts, each SHA-256, and the absence of trailing bytes.
    public func validate() throws {
        func require(_ condition: Bool, _ detail: String) throws {
            if !condition { throw ValidationError.invalid(detail) }
        }
        try require(schemaVersion == 1 || schemaVersion == 2, "不支持的版本")
        try require(Self.safeIdentifier(id), "包标识")
        try require(!title.isEmpty && title.count <= 200 && sourceDescription.count <= 2_000, "包说明")
        try require(Self.isSHA256(sourceSHA256), "来源校验值")
        try require(!files.isEmpty && files.count <= fileCountLimit, "文件数量")
        var seen = Set<String>()
        var byPath: [String: File] = [:]
        var total = 0
        for file in files {
            try require(Self.safePath(file.path), "文件路径")
            let normalized = file.path.precomposedStringWithCanonicalMapping.lowercased()
            try require(normalized.split(separator: "/").first != "manifest.json", "保留文件路径")
            try require(seen.insert(normalized).inserted, "重复文件路径")
            try require(file.bytes > 0 && file.bytes <= 128 * 1024 * 1024, "文件大小")
            try require(Self.isSHA256(file.sha256), "文件校验值")
            total += file.bytes
            try require(total <= payloadByteLimit, "资源包超过大小限制")
            let suffix = (file.path as NSString).pathExtension.lowercased()
            let allowed: [File.Kind: Set<String>] = [
                .model: ["glb"], .image: ["png", "jpg", "jpeg"], .music: ["m4a", "wav"],
                .data: ["json"], .notice: ["txt"], .font: ["ttf", "otf"]
            ]
            try require(allowed[file.kind]?.contains(suffix) == true, "文件类型")
            byPath[file.path] = file
        }
        for path in seen {
            let parts = path.split(separator: "/")
            if parts.count > 1 {
                for count in 1..<parts.count {
                    try require(!seen.contains(parts.prefix(count).joined(separator: "/")), "文件与目录路径冲突")
                }
            }
        }
        func reference(_ path: String, _ kind: File.Kind) throws {
            try require(byPath[path]?.kind == kind, "未登记的\(kind.rawValue)文件")
        }
        func identifiers(_ values: [String], _ group: String, maximum: Int) throws {
            try require(values.count <= maximum && Set(values).count == values.count,
                        "\(group)数量或重复标识")
            try require(values.allSatisfy(Self.safeIdentifier), "\(group)标识")
        }
        try identifiers(heroes.map(\.id), "英雄", maximum: 1_000)
        try identifiers(themes.map(\.id), "主题", maximum: 100)
        try identifiers(music.map(\.id), "音乐", maximum: 1_000)
        try identifiers(maps.map(\.id), "地图", maximum: 2_000)
        for hero in heroes {
            try require(!hero.name.isEmpty && hero.name.count <= 150 && hero.notes.count <= 20, "英雄说明")
            if let path = hero.modelFile { try reference(path, .model) }
            if let path = hero.animationFile { try reference(path, .data) }
            if let path = hero.faceFile { try reference(path, .data) }
            if let height = hero.modelHeight { try require(height.isFinite && height > 0 && height <= 10_000, "模型尺寸") }
            if let bounds = hero.modelBounds {
                try require(bounds.count == 6 && bounds.allSatisfy({ $0.isFinite && abs($0) < 100_000 }), "模型包围盒")
                try require((0..<3).allSatisfy { bounds[$0 + 3] >= bounds[$0] }, "模型包围盒方向")
            }
            if let animation = hero.idleAnimation { try require(animation.count <= 200, "动作标识") }
        }
        for theme in themes {
            try require(!theme.title.isEmpty && theme.title.count <= 150, "主题名称")
            try reference(theme.backgroundFile, .image)
            try require((theme.sceneFile == nil) == (theme.sceneExport == nil), "大厅动画引用不完整")
            if let path = theme.sceneFile { try reference(path, .data) }
            if let name = theme.sceneExport { try require(!name.isEmpty && name.utf8.count <= 240, "大厅动画名称") }
            if let rect = theme.sceneSourceRect {
                try require(theme.sceneFile != nil && rect.count == 4
                            && rect.allSatisfy { $0.isFinite && abs($0) <= 100_000 }, "大厅画面范围")
                try require(rect[2] > rect[0] && rect[3] > rect[1], "大厅画面范围方向")
            }
            try require((theme.loadingSceneFile == nil) == (theme.loadingSceneExport == nil), "加载动画引用不完整")
            if let path = theme.loadingSceneFile { try reference(path, .data) }
            if let name = theme.loadingSceneExport { try require(!name.isEmpty && name.utf8.count <= 240, "加载动画名称") }
            if let cue = theme.loadingJingleID { try require(!cue.isEmpty && cue.utf8.count <= 240, "加载音效名称") }
        }
        if let fonts {
            try identifiers(fonts.map(\.id), "字体", maximum: 100)
            for font in fonts {
                try reference(font.file, .font)
                try require(!font.postScriptName.isEmpty && font.postScriptName.utf8.count <= 240, "字体名称")
            }
        }
        if let defaultThemeID { try require(themes.contains { $0.id == defaultThemeID }, "默认主题") }
        for track in music {
            try require(!track.title.isEmpty && track.title.count <= 200 && track.cues.count <= 100, "音乐说明")
            try reference(track.file, .music)
            if let volume = track.volumePercent { try require(volume.isFinite && (0...100).contains(volume), "音乐音量") }
        }
        let trackIDs = Set(music.map(\.id))
        for (role, trackID) in musicBindings {
            try require(["lobby", "battle", "win", "lose"].contains(role) && trackIDs.contains(trackID), "音乐事件")
        }
        for map in maps {
            try require(!map.title.isEmpty && map.title.count <= 200, "地图名称")
            try require((1...128).contains(map.width) && (1...128).contains(map.height), "地图尺寸")
            try require((0...(map.width * map.height)).contains(map.unresolvedCells) && map.modes.count <= 100, "地图信息")
            try reference(map.layoutFile, .data)
        }
        for path in [gameAudioFile, menuArtworkFile, combatFile, playableMapsFile, mapArtworkFile, skillArtworkFile,
                     sourceRulesFile, sourceMapCatalogFile, sourceAssetIndexFile, lobbyLayoutFile].compactMap({ $0 }) {
            try reference(path, .data)
        }
    }

    public static func safeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 160 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0)
        } && value != "." && value != ".."
    }

    public static func safePath(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 240, !value.hasPrefix("/"),
              !value.contains("\\"), !value.contains(":"), !value.contains("%"),
              value.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else { return false }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }
    }

    public static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

/// Source tile semantics for the layout browser, not an ArenaMap/playability claim.
public struct ArenaResourceMapLayout: Codable, Sendable {
    public struct Legend: Codable, Sendable {
        public let name: String
        public let blocksMovement: Bool
        public let blocksProjectiles: Bool
        public let destructible: Bool
        public let bush: Bool
        public let water: Bool
    }
    public let id: String
    public let rows: [String]
    public let legend: [String: Legend]

    public func validate(width: Int, height: Int) throws {
        guard (1...128).contains(width), (1...128).contains(height), rows.count == height,
              rows.allSatisfy({ $0.count == width }), legend.count <= 256,
              legend.keys.allSatisfy({ $0.count == 1 }) else {
            throw ArenaResourcePackManifest.ValidationError.invalid("地图布局")
        }
    }
}
