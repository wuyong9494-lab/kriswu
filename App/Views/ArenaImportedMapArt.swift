import SceneKit
import UIKit
import simd

/// Original environment meshes, source submesh selection and cell placement.
/// The geometry importer retains x/right, -y/down, z/up source coordinates;
/// this one root transform converts them to the App's x/right, z/down, y/up.
@MainActor
final class ArenaImportedMapArt {
    let node = SCNNode()
    private var models: [String: GLTFModel] = [:]
    private var cells: [ArenaImportedMap.Cell: SCNNode] = [:]
    private var animations: [(model: GLTFModel, instance: GLTFModel.Instance, clip: GLTFModel.Clip)] = []
    private var lastRevision: UInt64 = .max
    private var theme: Theme
    private let store: ArenaResourcePackStore
    private var fileKinds: [String: ArenaResourcePackManifest.File.Kind]
    private(set) var missingRoles: Set<String> = []
    private(set) var hasGround = false

    private struct Catalog: Decodable { let schemaVersion: Int; let themes: [Theme] }
    private struct Theme: Decodable { let id: String; let roles: [String: [Part]] }
    private struct Part: Decodable {
        let file: String?
        let status: String
        let submesh: String?
        let angleStep: String?
        let animationName: String?
        let materialOverrides: [ArenaImportedMaterialOverride]?
    }

    init?(themeID: String, terrain: ArenaTerrainState, store: ArenaResourcePackStore = .shared) {
        guard store.enabled, let pack = store.manifest, let path = pack.mapArtworkFile,
              let file = pack.files.first(where: { $0.path == path && $0.kind == .data }), file.bytes <= 8 * 1024 * 1024,
              let url = store.url(for: path), let data = try? Data(contentsOf: url), data.count == file.bytes,
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data), catalog.schemaVersion == 1,
              let theme = catalog.themes.first(where: { $0.id == themeID }) else { return nil }
        self.theme = theme; self.store = store
        fileKinds = Dictionary(uniqueKeysWithValues: pack.files.map { ($0.path, $0.kind) })
        node.name = "source-environment-" + themeID
        node.simdEulerAngles.x = -.pi / 2
        for role in ["GroundModel", "EnvironmentModel", "MaskedEnvironmentModel"] {
            // Source continuation rows add layers (lines, ground, animated
            // details); they are not random alternatives to the first row.
            for index in theme.roles[role]?.indices ?? 0..<0 {
                if let made = make(role: role, variant: index) {
                    node.addChildNode(made)
                    if role == "GroundModel", !made.childNodes.isEmpty { hasGround = true }
                }
            }
        }
        for y in 0..<terrain.height { for x in 0..<terrain.width {
            guard let cell = terrain.cell(x, y), cell.isVisible, !cell.isOutOfBounds,
                  cell.visualKind != .floor || cell.terrainID == "DecoDestructible" else { continue }
            let role = Self.role(for: cell.terrainID, visual: cell.visualKind)
            let seed = x * 31 + y * 17
            let part = make(role: role, variant: seed) ?? fallback(cell.visualKind)
            let placement = SCNNode()
            placement.simdPosition = SIMD3(Float(x) + 0.5, -(Float(y) + 0.5), 0)
            placement.addChildNode(part)
            if let choices = theme.roles[role], !choices.isEmpty,
               let degrees = choices[seed % choices.count].angleStep.flatMap(Double.init), degrees > 0, degrees <= 360 {
                let steps = max(1, Int(360 / degrees))
                placement.simdEulerAngles.z = Float(Double(seed % steps) * degrees * .pi / 180)
            }
            node.addChildNode(placement)
            cells[cell.cell] = placement
        } }
        update(terrain: terrain, time: 0)
    }

    private static func role(for terrain: String, visual: ArenaTerrainState.VisualKind) -> String {
        switch terrain {
        case "Wall1": return "Wall1Model"
        case "Wall2": return "Wall2Model"
        case "Crate": return "CrateModel"
        case "Barrel": return "BarrelModel"
        case "Themed": return "ThemedModel"
        case "Clutter", "DecoDestructible": return "ClutterModel"
        case "Fragile": return "FragileModel"
        case "Indestructible": return "IndestructibleModel"
        case "Fence": return "FenceModel"
        case "IndestructibleFence": return "IndestructibleFenceModel"
        case "RopeFence": return "RopeFenceModel"
        default:
            switch visual {
            case .bush: return "Grass"
            case .water: return "WaterTileModel"
            case .wall: return "Wall1Model"
            case .floor: return "GroundModel"
            }
        }
    }

    private func make(role: String, variant: Int) -> SCNNode? {
        guard let parts = theme.roles[role], !parts.isEmpty else { return nil }
        let part = parts[variant % parts.count]
        if part.status == "empty_source_scene" { return SCNNode() }
        guard part.status == "converted", let path = part.file, fileKinds[path] == .model,
              let url = store.url(for: path) else { missingRoles.insert(role); return nil }
        let model: GLTFModel
        if let existing = models[path] { model = existing }
        else {
            guard let loaded = try? GLTFModel(url: url, maxTexture: 1024, smoothNormals: false) else {
                missingRoles.insert(role); return nil
            }
            model = loaded; models[path] = loaded
        }
        let instance = model.instantiate()
        let pending = ArenaImportedMaterialAdapter.apply(part.materialOverrides ?? [], to: instance.materials)
        missingRoles.formUnion(pending.map { role + ":material:" + $0 })
        if let submesh = part.submesh, !submesh.isEmpty {
            guard instance.root.childNode(withName: submesh, recursively: true) != nil else {
                missingRoles.insert(role + ":" + submesh); return nil
            }
            instance.root.enumerateChildNodes { child, _ in
                guard child.geometry != nil else { return }
                var included = child.name == submesh
                var parent = child.parent
                while let current = parent, current !== instance.root {
                    included = included || current.name == submesh; parent = current.parent
                }
                child.isHidden = !included
            }
        }
        if let name = part.animationName, let clip = model.clips[name] {
            animations.append((model, instance, clip))
        }
        return instance.root
    }

    /// A missing source mesh still has a visible collider. The catalog keeps the
    /// unavailable source role for review, rather than rendering an invisible wall.
    private func fallback(_ kind: ArenaTerrainState.VisualKind) -> SCNNode {
        let geometry: SCNGeometry
        switch kind {
        case .wall: geometry = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.03)
        case .bush: geometry = SCNBox(width: 0.95, height: 0.95, length: 0.35, chamferRadius: 0.08)
        case .water, .floor: geometry = SCNPlane(width: 1, height: 1)
        }
        let material = SCNMaterial()
        material.diffuse.contents = kind == .water ? UIColor.systemBlue : kind == .bush ? UIColor.systemGreen : UIColor.systemGray
        geometry.firstMaterial = material
        let result = SCNNode(geometry: geometry)
        result.position.z = kind == .wall ? 0.5 : kind == .bush ? 0.175 : 0.01
        return result
    }

    func update(terrain: ArenaTerrainState, time: Double) {
        if terrain.revision != lastRevision {
            for (cell, node) in cells { node.isHidden = terrain.cell(cell.x, cell.y)?.isDestroyed == true }
            lastRevision = terrain.revision
        }
        for animation in animations where !animation.instance.root.isHidden {
            var pose = animation.model.restPose
            let duration = animation.clip.duration
            let t = duration > 0 ? Float(time).truncatingRemainder(dividingBy: duration) : 0
            animation.clip.sample(at: t, into: &pose)
            for index in animation.model.animated where animation.instance.nodes.indices.contains(index) {
                animation.instance.nodes[index].simdTransform = pose.transform(index)
            }
        }
    }
}
