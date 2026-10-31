import Foundation
import SceneKit
import simd

/// Named source actions retain their authored timing. A comma/semicolon source
/// selection is not automatically substituted with the first available clip.
struct ArenaImportedAnimationCatalog: Decodable {
    struct Role: Decodable {
        let status: String
        let recordNames: [String]
        let selectionRule: String
    }
    struct Record: Decodable {
        let recordName: String
        let clipName: String?
        let status: String
        let sourcePriority: String
        let loop: Bool
        let timingBaked: Bool?
        let durationSeconds: Double?
        let transitionInSeconds: Double?
        let transitionOutSeconds: Double?
        let autoFadeSeconds: Double?
    }
    let schemaVersion: Int
    let heroID: String
    let roles: [String: Role]
    let clips: [Record]
    let materialOverrides: [ArenaImportedMaterialOverride]?
}

@MainActor
final class ArenaImportedHeroAssets {
    static let shared = ArenaImportedHeroAssets()
    struct Asset {
        let hero: ArenaResourcePackManifest.Hero
        let model: GLTFModel
        let animations: ArenaImportedAnimationCatalog?
    }
    private var cache: [String: Asset] = [:]
    private var cacheOrder: [String] = []
    private var packKey: String?

    func asset(id: String) -> Asset? {
        let store = ArenaResourcePackStore.shared
        guard store.enabled, let pack = store.manifest,
              let hero = pack.heroes.first(where: { $0.id == id }), let path = hero.modelFile,
              let file = pack.files.first(where: { $0.path == path && $0.kind == .model }),
              let url = store.url(for: path) else { return nil }
        let key = pack.id + "@" + pack.sourceSHA256 + "@" + String(url.path.dropLast(path.count))
        if key != packKey { cache.removeAll(); cacheOrder.removeAll(); packKey = key }
        let assetKey = id + "@" + file.sha256
        if let cached = cache[assetKey] {
            cacheOrder.removeAll { $0 == assetKey }; cacheOrder.append(assetKey)
            return cached
        }
        guard let model = try? GLTFModel(url: url, maxTexture: 1024, smoothNormals: false) else { return nil }
        var catalog: ArenaImportedAnimationCatalog?
        if let animationPath = hero.animationFile,
           let definition = pack.files.first(where: { $0.path == animationPath && $0.kind == .data }),
           definition.bytes <= 2 * 1024 * 1024, let animationURL = store.url(for: animationPath),
           let data = try? Data(contentsOf: animationURL), data.count == definition.bytes,
           let parsed = try? JSONDecoder().decode(ArenaImportedAnimationCatalog.self, from: data),
           parsed.schemaVersion == 1, parsed.heroID == id, parsed.clips.count <= 500 {
            catalog = parsed
        }
        let result = Asset(hero: hero, model: model, animations: catalog)
        cache[assetKey] = result
        cacheOrder.append(assetKey)
        while cacheOrder.count > 8 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
        return result
    }
}

/// Per-bone priorities use the named source hierarchy. Lower-priority legs keep
/// walking while a high-priority recoil affects the source chest/arm subtree.
/// All CSV ranges/speeds have already been baked into the named GLB clips.
@MainActor
final class ArenaImportedHeroAnimator {
    private struct Playing {
        let record: ArenaImportedAnimationCatalog.Record
        let clip: GLTFModel.Clip
        let priority: [Int: Int]
        var minimumDuration: Float = 0
        var elapsed: Float = 0
    }
    private let asset: ArenaImportedHeroAssets.Asset
    private let instance: GLTFModel.Instance
    private var baseRole = ""
    private var displayedRole = ""
    private var base: Playing?
    private var layers: [Playing] = []
    private var pose: GLTFModel.Pose
    private var layerPose: GLTFModel.Pose
    private var face: ArenaImportedFaceAnimator?
    private var clock = 0.0
    private(set) var unavailableRoles: Set<String> = []

    init(asset: ArenaImportedHeroAssets.Asset, instance: GLTFModel.Instance) {
        self.asset = asset; self.instance = instance
        pose = asset.model.restPose; layerPose = asset.model.restPose
        ArenaImportedMaterialAdapter.apply(asset.animations?.materialOverrides ?? [], to: instance.materials)
        face = ArenaImportedFaceAnimator(heroID: asset.hero.id, model: asset.model, instance: instance)
    }

    func trigger(_ role: String, holdFor duration: Double? = nil) {
        guard var selected = playing(role) else { unavailableRoles.insert(role); return }
        if let duration, duration.isFinite { selected.minimumDuration = Float(min(max(duration, 0), 30)) }
        layers.removeAll { $0.record.recordName == selected.record.recordName }
        layers.append(selected)
        if role == "attack", let recoil = playing("attackRecoil") { layers.append(recoil) }
        if role == "ultimate", let recoil = playing("ultimateRecoil") { layers.append(recoil) }
        if layers.count > 6 { layers.removeFirst(layers.count - 6) }
    }

    func reset() { base = nil; baseRole = ""; displayedRole = ""; layers.removeAll(); clock = 0 }

    func update(base role: String, delta: Float, visible: Bool) {
        let dt = max(0, delta)
        clock += Double(dt)
        if baseRole != role {
            baseRole = role
            displayedRole = role
            base = playing(role) ?? playing("idle")
        }
        base?.elapsed += dt
        if ["lobby", "win", "lose"].contains(displayedRole), let current = base,
           !current.record.loop, current.elapsed >= current.clip.duration,
           var next = playing(displayedRole + "Loop"), next.record.loop {
            next.elapsed = max(0, current.elapsed - current.clip.duration)
            base = next
            displayedRole += "Loop"
        }
        for index in layers.indices { layers[index].elapsed += dt }
        layers.removeAll {
            let length = max(max($0.clip.duration, $0.minimumDuration), 1 / 30)
            return $0.elapsed >= length + Float($0.record.transitionOutSeconds ?? 0)
        }
        guard visible else { return }
        pose.reset(from: asset.model.restPose)
        var priorities = [Int: Int]()
        if let base {
            sample(base, into: &pose)
            priorities = base.priority
        }
        for layer in layers {
            layerPose.reset(from: asset.model.restPose)
            sample(layer, into: &layerPose)
            let fadeIn = Float(layer.record.transitionInSeconds ?? 0)
            let fadeOut = Float(layer.record.transitionOutSeconds ?? 0)
            let weightIn: Float = fadeIn > 0 ? min(1, layer.elapsed / fadeIn) : 1
            let remaining = max(layer.clip.duration, layer.minimumDuration) + fadeOut - layer.elapsed
            let weightOut: Float = fadeOut > 0 ? min(1, max(0, remaining / fadeOut)) : 1
            let selected = asset.model.animated.filter { node in
                guard let rank = layer.priority[node] else { return false }
                return rank >= (priorities[node] ?? 0)
            }
            pose.blend(toward: layerPose, weight: weightIn * weightOut, nodes: selected)
            for node in selected { priorities[node] = layer.priority[node] ?? 0 }
        }
        for index in asset.model.animated where instance.nodes.indices.contains(index) {
            instance.nodes[index].simdTransform = pose.transform(index)
        }
        let faceRole: String
        switch displayedRole {
        case "lobby": faceRole = "LobbyFace"
        case "lobbyLoop": faceRole = "LobbyLoopFace"
        case "walk": faceRole = "WalkFace"
        case "win": faceRole = "HappyFace"
        case "winLoop": faceRole = "HappyLoopFace"
        case "lose": faceRole = "SadFace"
        case "loseLoop": faceRole = "SadLoopFace"
        default: faceRole = "IdleFace"
        }
        face?.update(role: faceRole, time: clock)
    }

    private func sample(_ playing: Playing, into pose: inout GLTFModel.Pose) {
        let duration = playing.clip.duration
        let time = playing.record.loop && duration > 0
            ? playing.elapsed.truncatingRemainder(dividingBy: duration)
            : min(playing.elapsed, duration)
        playing.clip.sample(at: time, into: &pose)
    }

    private func playing(_ role: String) -> Playing? {
        guard let catalog = asset.animations, let binding = catalog.roles[role],
              ["ready", "static_pose"].contains(binding.status), binding.recordNames.count == 1,
              let record = catalog.clips.first(where: { $0.recordName == binding.recordNames[0] }),
              let name = record.clipName, let clip = asset.model.clips[name] else { return nil }
        var ranks = [Int: Int]()
        let definition = record.sourcePriority
        if let rank = Int(definition) {
            for node in asset.model.animated { ranks[node] = rank }
        } else if definition.isEmpty {
            for node in asset.model.animated { ranks[node] = 0 }
        } else {
            for entry in definition.split(separator: "+") {
                let pair = entry.split(separator: "#", omittingEmptySubsequences: false)
                guard pair.count == 2, let rank = Int(pair[1]), let node = asset.model.node(named: String(pair[0])) else { return nil }
                for descendant in asset.model.subtree(of: node) { ranks[descendant] = rank }
            }
        }
        return Playing(record: record, clip: clip, priority: ranks)
    }
}
