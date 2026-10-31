import Foundation
import ImageIO
import SceneKit
import UIKit

/// Plays the imported face display list on a fixed texture canvas. The archive
/// contains declarative triangles, matrices, colors and complete clip timelines;
/// it contains no executable client code. Child clocks never expand into an LCM.
///
/// Clock reference: sc-editor MovieClip.gotoAbsoluteTimeRecursive at
/// 0aaa905c7af7f0bfda416c5acb879ff1c36d5054 (MIT). Blend factors are its
/// documented NORMAL / SCREEN / ADDITIVE factors. Source-client phase and shader
/// parity still require device acceptance; unknown operations are rejected.
@MainActor
final class ArenaImportedFaceAnimator {
    private static var scenes: [String: ArenaFaceScene] = [:]
    private static var sceneOrder: [String] = []
    private static let imageCache: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>()
        value.totalCostLimit = 24 * 1024 * 1024
        value.countLimit = 24
        return value
    }()
    private static var failures: [String: String] = [:]

    static func failureReason(for heroID: String) -> String? { failures[heroID] }

    private let specification: ArenaFaceSpecification
    private let scene: ArenaFaceScene
    private struct MaterialGroup {
        let base: ArenaFacePixels
        let materials: [SCNMaterial]
        let cacheSuffix: String
    }
    private let materialGroups: [MaterialGroup]
    private let cachePrefix: String
    private var lastRole: String?
    private var lastRenderTime: Double?
    private var expressionOrigin = 0.0
    private var lastSignature: String?
    private(set) var lastError: String?

    init?(heroID: String, model: GLTFModel, instance: GLTFModel.Instance) {
        do {
            let store = ArenaResourcePackStore.shared
            guard store.enabled, !model.names.isEmpty,
                  let hero = store.manifest?.heroes.first(where: { $0.id == heroID }),
                  let file = hero.faceFile, let specURL = store.url(for: file) else {
                throw ArenaFaceError.invalid("No approved face description for this hero")
            }
            let specification = try JSONDecoder().decode(ArenaFaceSpecification.self,
                from: Self.read(specURL, maximumBytes: 2 * 1024 * 1024))
            guard specification.schemaVersion == 1, specification.heroID == heroID,
                  specification.status == "ready", specification.canvasSize == [512, 512],
                  specification.clockPolicy == "independent_absolute_clip_fps",
                  let baseFile = specification.baseDiffuseFile,
                  let baseURL = store.url(for: baseFile),
                  let sceneURL = store.url(for: specification.sceneFile) else {
                throw ArenaFaceError.invalid("Face material, canvas or source-clock configuration is unsupported")
            }
            let key = sceneURL.absoluteString + "|" + specification.sceneSHA256
            let scene: ArenaFaceScene
            if let cached = Self.scenes[key] {
                scene = cached
            } else {
                let source = try JSONDecoder().decode(ArenaFaceScene.Document.self,
                    from: Self.read(sceneURL, maximumBytes: 40 * 1024 * 1024))
                scene = try ArenaFaceScene(source) { path in
                    guard let url = store.url(for: path) else {
                        throw ArenaFaceError.invalid("Face atlas path is not approved by the resource pack")
                    }
                    return try ArenaFacePixels(data: Self.read(url, maximumBytes: 32 * 1024 * 1024))
                }
                Self.scenes[key] = scene
                Self.sceneOrder.append(key)
                while Self.sceneOrder.count > 2 {
                    Self.scenes.removeValue(forKey: Self.sceneOrder.removeFirst())
                }
            }
            guard !specification.materialBindings.isEmpty,
                  Set(specification.materialBindings.map { $0.originalSourceImageIndex ?? $0.imageIndex }).count == 1 else {
                throw ArenaFaceError.invalid("Face-to-diffuse material selection is ambiguous")
            }
            var groups: [MaterialGroup] = []
            let bindingsByBase = Dictionary(grouping: specification.materialBindings) { $0.baseDiffuseFile ?? baseFile }
            for path in bindingsByBase.keys.sorted() {
                guard let bindings = bindingsByBase[path], let first = bindings.first,
                      let url = path == baseFile ? baseURL : store.url(for: path) else {
                    throw ArenaFaceError.invalid("Face material base image is not approved")
                }
                let base = try ArenaFacePixels(data: Self.read(url, maximumBytes: 8 * 1024 * 1024))
                guard base.width == 512, base.height == 512 else {
                    throw ArenaFaceError.invalid("Face material base image has the wrong canvas")
                }
                let names = Set(bindings.map(\.materialName))
                let bound = instance.materials.filter { names.contains($0.name ?? "") }
                guard names.isSubset(of: Set(bound.map { $0.name ?? "" })), !bound.isEmpty else {
                    throw ArenaFaceError.invalid("Face material names do not match this model instance")
                }
                groups.append(MaterialGroup(base: base, materials: bound,
                    cacheSuffix: path + "|" + (first.baseDiffuseSHA256 ?? specification.baseDiffuseSHA256 ?? "")))
            }
            // Validate every complete referenced timeline once, before a frame is
            // drawn. A ready role cannot conceal an unsupported blend or cycle.
            for role in specification.sourceRoles.values where role.status == "ready" {
                guard let objectID = role.objectID, let export = role.exportName,
                      sourceExport(scene, named: export) == objectID else {
                    throw ArenaFaceError.invalid("Face export identity does not match the shared scene")
                }
                try scene.validate(root: objectID)
            }
            self.specification = specification
            self.scene = scene
            materialGroups = groups
            cachePrefix = key + "|" + heroID + "|" + (specification.baseDiffuseSHA256 ?? "")
            Self.failures.removeValue(forKey: heroID)
        } catch {
            Self.failures[heroID] = error.localizedDescription
            return nil
        }
    }

    /// Accepts a monotonic scene clock, resetting the expression on a role
    /// change or clock reset. Both exact source fields (IdleFace/WalkFace/etc.)
    /// and their declared aliases are accepted; there is no face fallback.
    func update(role: String, time: Double) {
        guard time.isFinite, time >= 0 else {
            lastError = "Face time must be finite and nonnegative"
            return
        }
        guard let selected = specification.roles[role] ?? specification.sourceRoles[role], selected.status == "ready",
              let root = selected.objectID else {
            lastError = "No supported source face binding for role: \(role)"
            return
        }
        if lastRole != role || (lastRenderTime.map { time < $0 } ?? false) { expressionOrigin = time }
        if lastRole == role, let previous = lastRenderTime,
           time >= previous, time - previous < 1.0 / 15.0 { return }
        do {
            let elapsed = max(0, time - expressionOrigin)
            let signature = try scene.signature(root: root, time: elapsed)
            if signature != lastSignature || lastRole != role {
                for group in materialGroups {
                    let key = (cachePrefix + "|" + group.cacheSuffix + "|" + signature) as NSString
                    let image: UIImage
                    if let cached = Self.imageCache.object(forKey: key) {
                        image = cached
                    } else {
                        image = try scene.composite(root: root, time: elapsed, base: group.base)
                        Self.imageCache.setObject(image, forKey: key, cost: 512 * 512 * 4)
                    }
                    // An opaque slot and a premultiplied source slot may share
                    // authored UVs but require different straight PNG bases.
                    // The converter preserves their exact material identities.
                    for material in group.materials { material.diffuse.contents = image }
                }
                // This only changes the source diffuse pixels. glTF alpha/factor,
                // team tint, concealment and hit-flash shader modifiers survive.
                lastSignature = signature
            }
            lastRole = role
            lastRenderTime = time
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Self.failures[specification.heroID] = error.localizedDescription
        }
    }

    private static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumBytes else {
            throw ArenaFaceError.invalid("Face resource exceeds its declared reading limit")
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}

private func sourceExport(_ scene: ArenaFaceScene, named name: String) -> Int? {
    guard let item = scene.document.exports[name], item.status == "ready" else { return nil }
    return item.objectID
}

private struct ArenaFaceSpecification: Decodable {
    struct Binding: Decodable {
        let materialName: String
        let imageIndex: Int
        let originalSourceImageIndex: Int?
        let baseDiffuseFile: String?
        let baseDiffuseSHA256: String?
    }
    struct Role: Decodable {
        let status: String
        let objectID: Int?
        let exportName: String?
    }
    let schemaVersion: Int
    let heroID: String
    let status: String
    let sceneFile: String
    let sceneSHA256: String
    let canvasSize: [Int]
    let baseDiffuseFile: String?
    let baseDiffuseSHA256: String?
    let materialBindings: [Binding]
    let roles: [String: Role]
    let sourceRoles: [String: Role]
    let clockPolicy: String
}
