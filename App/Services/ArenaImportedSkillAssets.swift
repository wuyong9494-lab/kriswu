import Foundation
import SceneKit
import UIKit

/// Loads a declarative source display list from the already verified private
/// resource pack. The factory returns nil for an unresolved FX program; a
/// source effect name is never mistaken for a complete drawable animation.
@MainActor
final class ArenaImportedSkillAssets {
    static let shared = ArenaImportedSkillAssets()

    private var manifestKey: String?
    private var specification: ArenaSkillArtworkSpecification?
    private var scenes: [String: ArenaFaceScene] = [:]
    private var validatedRoots = Set<String>()
    private var failures: [String: String] = [:]

    func failureReason(for id: String) -> String? { failures[id] }

    /// Called while entering the match, before the first shot. Traversal follows
    /// exact typed projectile -> area -> split-projectile references, including
    /// the nested children of radial explosions; it does not scan arbitrary IDs.
    /// No SceneKit node is created or retained by this preflight.
    func prepare(heroes: [ArenaSourceHero], unitsPerSourcePoint: Double) {
        do {
            guard unitsPerSourcePoint.isFinite, unitsPerSourcePoint > 0,
                  unitsPerSourcePoint <= 1, heroes.count <= 128 else {
                throw ArenaSkillArtworkError.invalid("Invalid skill artwork preflight")
            }
            let specification = try currentSpecification()
            var projectileIDs = Set<String>()
            var areaIDs = Set<String>()
            func visitProjectile(_ projectile: ArenaSourceProjectile, depth: Int) {
                guard depth <= 32, projectileIDs.count < 2048,
                      projectileIDs.insert(projectile.id).inserted else { return }
                for area in projectile.areaEffects { visitArea(area, depth: depth + 1) }
            }
            func visitArea(_ area: ArenaSourceAreaEffect, depth: Int) {
                guard depth <= 32, areaIDs.count < 2048,
                      areaIDs.insert(area.id).inserted else { return }
                if let nested = area.bulletExplosion?.projectile {
                    visitProjectile(nested, depth: depth + 1)
                }
            }
            for hero in heroes {
                for skill in [hero.weapon, hero.ultimate].compactMap({ $0 }) {
                    for projectile in skill.projectiles { visitProjectile(projectile, depth: 0) }
                    for area in skill.areaEffects { visitArea(area, depth: 0) }
                    for area in skill.charge?.endAreas ?? [] { visitArea(area, depth: 0) }
                }
            }
            for id in projectileIDs.sorted() {
                guard let binding = specification.projectiles.first(where: { $0.id == id }) else {
                    failures[id] = "No exact source projectile export is configured"
                    continue
                }
                prepare(binding: binding, id: id)
            }
            for id in areaIDs.sorted() {
                guard let entry = specification.areas.first(where: { $0.areaID == id }) else {
                    failures[id] = "No source area artwork is configured"
                    continue
                }
                guard entry.status == "ready", let binding = entry.binding else {
                    failures[id] = entry.limitation ?? "The source area FX program is not implemented"
                    continue
                }
                prepare(binding: binding, id: id)
            }
        } catch {
            failures["prepare"] = error.localizedDescription
        }
    }

    private func prepare(binding: ArenaSkillArtworkSpecification.Binding, id: String) {
        do {
            try binding.validate()
            let scene = try sourceScene(for: binding)
            for selected in [binding.blue, binding.red] {
                try validate(selected: selected, binding: binding, scene: scene)
                try ArenaImportedSkillArt.prepare(binding: binding, selected: selected,
                    scene: scene, cacheIdentity: (manifestKey ?? "") + "|" + binding.sceneSHA256)
            }
            failures.removeValue(forKey: id)
        } catch {
            failures[id] = error.localizedDescription
        }
    }

    /// `unitsPerSourcePoint` is an explicit host presentation scale. The source
    /// Scale field is retained and applied as a percentage; neither value is
    /// presented as proof of the original client's world-to-pixel convention.
    func projectile(logicID: String, enemy: Bool,
                    unitsPerSourcePoint: Double) -> ArenaImportedSkillArt? {
        make(id: logicID, enemy: enemy, unitsPerSourcePoint: unitsPerSourcePoint, area: false)
    }

    func area(areaID: String, enemy: Bool,
              unitsPerSourcePoint: Double) -> ArenaImportedSkillArt? {
        make(id: areaID, enemy: enemy, unitsPerSourcePoint: unitsPerSourcePoint, area: true)
    }

    private func make(id: String, enemy: Bool, unitsPerSourcePoint: Double,
                      area: Bool) -> ArenaImportedSkillArt? {
        do {
            guard !id.isEmpty, id.utf8.count <= 200,
                  unitsPerSourcePoint.isFinite, unitsPerSourcePoint > 0,
                  unitsPerSourcePoint <= 1 else {
                throw ArenaSkillArtworkError.invalid("Invalid source skill identity or host presentation scale")
            }
            let specification = try currentSpecification()
            let binding: ArenaSkillArtworkSpecification.Binding
            if area {
                guard let entry = specification.areas.first(where: { $0.areaID == id }) else {
                    throw ArenaSkillArtworkError.invalid("No source area artwork is configured")
                }
                guard entry.status == "ready", let resolved = entry.binding else {
                    throw ArenaSkillArtworkError.invalid(entry.limitation ?? "The source area FX program is not implemented")
                }
                binding = resolved
            } else {
                guard let entry = specification.projectiles.first(where: { $0.id == id }) else {
                    throw ArenaSkillArtworkError.invalid("No exact source projectile export is configured")
                }
                binding = entry
            }
            try binding.validate()
            let selected = enemy ? binding.red : binding.blue
            let scene = try sourceScene(for: binding)
            try validate(selected: selected, binding: binding, scene: scene)
            let result = try ArenaImportedSkillArt(binding: binding, selected: selected,
                scene: scene, cacheIdentity: (manifestKey ?? "") + "|" + binding.sceneSHA256,
                unitsPerSourcePoint: unitsPerSourcePoint)
            failures.removeValue(forKey: id)
            return result
        } catch {
            failures[id] = error.localizedDescription
            return nil
        }
    }

    private func validate(selected: ArenaSkillArtworkSpecification.Export,
                          binding: ArenaSkillArtworkSpecification.Binding,
                          scene: ArenaFaceScene) throws {
        let key = (manifestKey ?? "") + "|" + binding.sceneSHA256 + "|\(selected.objectID)"
        guard selected.status == "ready",
              let source = scene.document.exports[selected.exportName], source.status == "ready",
              source.objectID == selected.objectID else {
            throw ArenaSkillArtworkError.invalid("Skill export identity does not match its shared source scene")
        }
        if !validatedRoots.contains(key) {
            try scene.validate(root: selected.objectID)
            validatedRoots.insert(key)
        }
    }

    private func currentSpecification() throws -> ArenaSkillArtworkSpecification {
        let store = ArenaResourcePackStore.shared
        guard store.enabled, let manifest = store.manifest,
              let file = manifest.skillArtworkFile,
              let entry = manifest.files.first(where: { $0.path == file }),
              let url = store.url(for: file) else {
            throw ArenaSkillArtworkError.invalid("No approved skill artwork manifest is installed")
        }
        let key = url.absoluteString + "|" + entry.sha256
        if manifestKey == key, let specification { return specification }
        // Pack replacement invalidates both the description and decoded scene.
        // No unrelated pack can reuse this pack's path or atlas cache entry.
        let value = try JSONDecoder().decode(ArenaSkillArtworkSpecification.self,
            from: Self.read(url, maximumBytes: 2 * 1024 * 1024))
        guard value.schemaVersion == 1, value.projectiles.count <= 2048,
              value.areas.count <= 2048,
              Set(value.projectiles.map(\.id)).count == value.projectiles.count,
              Set(value.areas.map(\.areaID)).count == value.areas.count else {
            throw ArenaSkillArtworkError.invalid("Unsupported or duplicated skill artwork entries")
        }
        manifestKey = key
        specification = value
        scenes.removeAll()
        validatedRoots.removeAll()
        failures.removeAll()
        return value
    }

    private func sourceScene(for binding: ArenaSkillArtworkSpecification.Binding) throws -> ArenaFaceScene {
        let store = ArenaResourcePackStore.shared
        guard let manifest = store.manifest,
              let entry = manifest.files.first(where: { $0.path == binding.sceneFile }),
              entry.sha256 == binding.sceneSHA256,
              let url = store.url(for: binding.sceneFile) else {
            throw ArenaSkillArtworkError.invalid("Skill scene path or hash is not approved by the current pack")
        }
        let key = url.absoluteString + "|" + binding.sceneSHA256
        let cached = scenes[key]
        let document: ArenaFaceScene.Document
        if let cached { document = cached.document }
        else {
            document = try JSONDecoder().decode(ArenaFaceScene.Document.self,
                from: Self.read(url, maximumBytes: 40 * 1024 * 1024))
        }
        let scale = binding.canvasPixelsPerSourcePoint
        let expectedProjection = [scale, 0, 0, scale,
                                  binding.sourceOriginCanvas[0], binding.sourceOriginCanvas[1]]
        guard document.canvasSize == binding.canvasSize,
              document.projection == expectedProjection else {
            throw ArenaSkillArtworkError.invalid("Skill canvas origin or source scale does not match the scene")
        }
        if let cached { return cached }
        let scene = try ArenaFaceScene(document) { path in
            guard let atlasURL = store.url(for: path) else {
                throw ArenaSkillArtworkError.invalid("Skill atlas is not approved by this resource pack")
            }
            return try ArenaFacePixels(data: Self.read(atlasURL, maximumBytes: 32 * 1024 * 1024))
        }
        // Current packs share a small number of atlases. Reject a description
        // that attempts to make every live projectile retain a new large scene.
        guard scenes.count < 4 else {
            throw ArenaSkillArtworkError.invalid("Too many independent skill artwork scenes")
        }
        scenes[key] = scene
        return scene
    }

    private static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize,
              size > 0, size <= maximumBytes else {
            throw ArenaSkillArtworkError.invalid("Skill artwork exceeds its bounded reading size")
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}

enum ArenaSkillArtworkError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let reason): return reason }
    }
}

/// Generic pack schema only. Original display lists and asset names stay in
/// the private resource pack and are never compiled into the public App source.
struct ArenaSkillArtworkSpecification: Decodable {
    struct Export: Decodable {
        let exportName: String
        let objectID: Int
        let status: String
        /// All independent source-frame bounds, before the canvas projection.
        let sourceBounds: [Double]
    }
    struct Binding: Decodable {
        let id: String
        let status: String
        let sceneFile: String
        let sceneSHA256: String
        let blue: Export
        let red: Export
        let canvasSize: [Int]
        let sourceOriginCanvas: [Double]
        let canvasPixelsPerSourcePoint: Double
        let sourceScaleRaw: String
        let sourceScaleMultiplier: Double
        let sourceRendering: String
        let sourceSpecialVisualStateRaw: String
        let playbackPolicy: String
        let rotationPolicy: String
        let limitations: [String]

        func validate() throws {
            let expectedScale = Double(sourceScaleRaw).map { $0 / 100 }
            let special = sourceSpecialVisualStateRaw.lowercased()
            guard status == "ready", canvasSize == [512, 512],
                  sourceOriginCanvas.count == 2,
                  sourceOriginCanvas.allSatisfy({ $0.isFinite && (0...512).contains($0) }),
                  canvasPixelsPerSourcePoint.isFinite, canvasPixelsPerSourcePoint > 0,
                  canvasPixelsPerSourcePoint <= 32,
                  sourceScaleMultiplier.isFinite, sourceScaleMultiplier > 0,
                  sourceScaleMultiplier <= 10, expectedScale == sourceScaleMultiplier,
                  ["", "false", "true"].contains(special),
                  ["", "UseZFrames", "DoNotRotateClip"].contains(sourceRendering),
                  ["independent_absolute_clip_fps", "static_first_frame"].contains(playbackPolicy),
                  ["source_positive_x_follows_direction", "source_negative_x_follows_direction", "fixed_source_orientation"].contains(rotationPolicy),
                  !(special == "true" || sourceRendering == "UseZFrames") || playbackPolicy == "static_first_frame",
                  sourceRendering != "DoNotRotateClip" || rotationPolicy == "fixed_source_orientation" else {
                throw ArenaSkillArtworkError.invalid("Unsupported source visual-state or presentation policy")
            }
            for entry in [blue, red] {
                let b = entry.sourceBounds
                guard !entry.exportName.isEmpty, entry.exportName.utf8.count <= 500,
                      entry.objectID >= 0, b.count == 4, b.allSatisfy(\.isFinite),
                      b[0] < b[2], b[1] < b[3],
                      b[0] * canvasPixelsPerSourcePoint + sourceOriginCanvas[0] >= 2,
                      b[1] * canvasPixelsPerSourcePoint + sourceOriginCanvas[1] >= 2,
                      b[2] * canvasPixelsPerSourcePoint + sourceOriginCanvas[0] <= 510,
                      b[3] * canvasPixelsPerSourcePoint + sourceOriginCanvas[1] <= 510 else {
                    throw ArenaSkillArtworkError.invalid("Source skill bounds cannot be safely represented on this canvas")
                }
            }
        }
    }
    struct Area: Decodable {
        let areaID: String
        let status: String
        let binding: Binding?
        let limitation: String?
    }
    let schemaVersion: Int
    let projectiles: [Binding]
    let areas: [Area]
}
