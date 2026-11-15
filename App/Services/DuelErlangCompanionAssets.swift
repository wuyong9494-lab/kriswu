import Foundation
import SceneKit
import simd

/// D15's dog is an independently authenticated quadruped. It never passes
/// through H17's human pelvis/rig assumptions or replaces a fighter model.
@MainActor
final class DuelErlangCompanionAssets {
    enum Failure: Error { case file(String), model, motion }
    let manifest: DuelErlangCompanionManifest
    let model: GLTFModel
    let start: Float
    let verifiedFiles: [DuelNetworkContentRecord]

    /// Reconstruct an arbitrary original emission birth pose. World-space
    /// particles must not borrow the dog's later display-frame position.
    func sourceBoneTransform(_ bone: String, age: Double, origin: DuelWeaponPoint,
                             direction: Int) -> simd_float4x4? {
        let definition = manifest.models[0], track = definition.track
        guard age.isFinite, (0...Double(definition.endEventTick)).contains(age),
              [-1, 1].contains(direction), let clip = model.clips[track.clip],
              let index = model.node(named: bone) else { return nil }
        var pose = model.restPose
        clip.sample(at: start + Float(age) / Float(DuelGame.ticksPerSecond), into: &pose)
        guard let boneTransform = model.sourceTransform(of: index, pose: pose) else { return nil }
        let lower = Int(age), upper = min(lower + 1, track.root.count - 1), fraction = age - Double(lower)
        let dx = track.root[lower].x * (1 - fraction) + track.root[upper].x * fraction - track.root[0].x
        let lift = track.groundLift[lower] * (1 - fraction) + track.groundLift[upper] * fraction
        var root = simd_float4x4(simd_quatf(angle: -Float(direction) * .pi / 2, axis: SIMD3(0, 1, 0)))
        root.columns.3 = SIMD4(Float(origin.x + dx * Double(direction)), Float(origin.y + lift), Float(origin.z), 1)
        return root * boneTransform
    }

    init(directory: URL, profile: DuelWeaponProfile, expectedSHA256: String) throws {
        func read(_ file: DuelFighterAssetRelease.File, maximum: Int) throws -> Data {
            try file.validate(maximum: maximum)
            let url = directory.appendingPathComponent(file.name)
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true, info.fileSize == file.bytes else {
                throw Failure.file(file.name)
            }
            let data = try Data(contentsOf: url)
            guard data.count == file.bytes, DuelNetworkContentRecord.digest(data) == file.sha256 else {
                throw Failure.file(file.name)
            }
            return data
        }
        let name = DuelErlangCompanionManifest.fileName
        let url = directory.appendingPathComponent(name)
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let file = DuelFighterAssetRelease.File(name: name, bytes: bytes, sha256: expectedSHA256)
        let data = try read(file, maximum: 512_000)
        let document = try JSONDecoder().decode(DuelErlangCompanionManifest.self, from: data)
        try document.validate(profile: profile)
        let definition = document.models[0]
        let modelData = try read(definition.file, maximum: 8_000_000)
        try DuelFighterAssetReleaseLoader.validateSelfContainedGLB(modelData)
        let model = try GLTFModel(url: directory.appendingPathComponent(definition.file.name),
                                  maxTexture: 1024, physicallyBased: true)
        guard model.hasSkinning, model.node(named: "SF3_Actor_Meters") != nil,
              model.node(named: definition.rootBone) != nil,
              Set(model.clips.keys) == [definition.track.clip],
              model.materialNames == Set(definition.materials.map(\.name)),
              let clip = model.clips[definition.track.clip], clip.channels.count == 82,
              let start = clip.channels.compactMap({ $0.times.first }).min(), start.isFinite,
              abs(start) < 0.000001,
              abs(clip.duration - start - Float(definition.track.frames - 1) / 30) < 0.0001 else {
            throw Failure.model
        }
        // The SceneKit loader opens the file by URL. Check that immutable bytes
        // are still the bytes verified before parsing and instantiation.
        guard DuelNetworkContentRecord.digest(try Data(contentsOf: directory.appendingPathComponent(definition.file.name))) == definition.file.sha256 else {
            throw Failure.file(definition.file.name)
        }
        self.manifest = document; self.model = model; self.start = start
        verifiedFiles = [.init(path: name, bytes: data.count, sha256: expectedSHA256),
                         .init(path: definition.file.name, bytes: modelData.count, sha256: definition.file.sha256)]
    }
}

/// Authoritative model IDs, origins and live ticks drive drawing. Rendering
/// cannot spawn the dog, extend its lifetime, confirm a hit, or advance time.
@MainActor
final class DuelErlangCompanionRenderer {
    private struct Key: Hashable { let owner: Int; let id: UInt64 }
    private struct Instance {
        let holder: SCNNode
        let model: GLTFModel.Instance
        var pose: GLTFModel.Pose
    }
    private let root = SCNNode()
    private let assets: DuelErlangCompanionAssets
    private var instances: [Key: Instance] = [:]

    init(assets: DuelErlangCompanionAssets, parent: SCNNode) {
        self.assets = assets
        root.name = "duel.erlang.companions"
        parent.addChildNode(root)
    }

    func draw(_ fight: DuelWeaponFight) {
        guard fight.phase == .fighting else { reset(); return }
        let definition = assets.manifest.models[0], track = definition.track
        let models = fight.erlangModels.filter { value in
            let age = fight.erlangLiveTick - value.bornAt
            return (0..<fight.profiles.count).contains(value.owner) &&
                fight.profiles[value.owner].id == assets.manifest.profileID &&
                fight.profiles[value.owner].sha256 == assets.manifest.characterSHA256 &&
                value.role == track.role && (0...definition.endEventTick).contains(age)
        }
        let live = Set(models.map { Key(owner: $0.owner, id: $0.id) })
        for key in Array(instances.keys) where !live.contains(key) {
            instances.removeValue(forKey: key)?.holder.removeFromParentNode()
        }
        guard let clip = assets.model.clips[track.clip] else { return }
        for source in models {
            let tick = fight.erlangLiveTick - source.bornAt
            let key = Key(owner: source.owner, id: source.id)
            var value: Instance
            if let existing = instances[key] { value = existing }
            else {
                let instance = assets.model.instantiate(), holder = SCNNode()
                holder.name = "duel.erlang.hound.\(source.owner).\(source.id)"
                holder.addChildNode(instance.root)
                root.addChildNode(holder)
                // Original SkinData explicitly selects cullMode 0. Retain the
                // original painted diffuse texture, UVs and source skinning.
                for record in definition.materials {
                    for material in instance.materials where material.name == record.name {
                        material.isDoubleSided = record.doubleSided
                        material.cullMode = record.cull == .front ? .front : .back
                        material.diffuse.minificationFilter = record.minification == .linear ? .linear : .nearest
                        material.diffuse.magnificationFilter = record.magnification == .linear ? .linear : .nearest
                        switch record.mip {
                        case .none: material.diffuse.mipFilter = .none
                        case .nearest: material.diffuse.mipFilter = .nearest
                        case .linear: material.diffuse.mipFilter = .linear
                        }
                        material.diffuse.wrapS = record.wrapS == .repeat ? .repeat : .clamp
                        material.diffuse.wrapT = record.wrapT == .repeat ? .repeat : .clamp
                        material.diffuse.maxAnisotropy = CGFloat(record.maxAnisotropy)
                        material.blendMode = .alpha
                    }
                }
                value = .init(holder: holder, model: instance, pose: assets.model.restPose)
            }
            value.pose.reset(from: assets.model.restPose)
            clip.sample(at: assets.start + Float(tick) / Float(DuelGame.ticksPerSecond), into: &value.pose)
            for index in assets.model.animated { value.model.nodes[index].simdTransform = value.pose.transform(index) }
            let delta = track.root[tick].x - track.root[0].x
            value.holder.position = .init(Float(source.origin.x + delta * Double(source.direction)),
                                          Float(source.origin.y + track.groundLift[tick]), Float(source.origin.z))
            value.holder.eulerAngles = .init(0, -Float(source.direction) * .pi / 2, 0)
            value.holder.opacity = CGFloat(definition.opacity(at: tick))
            instances[key] = value
        }
    }

    func reset() {
        for value in instances.values { value.holder.removeFromParentNode() }
        instances.removeAll(keepingCapacity: true)
    }
    func shutdown() { reset(); root.removeFromParentNode() }
}
