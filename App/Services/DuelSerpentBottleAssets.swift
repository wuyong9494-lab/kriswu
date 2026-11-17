import Foundation
import SceneKit
import simd

/// The actual equipped D13 bottle, authenticated independently from its body.
/// This renders the recovered ordinary-array mesh, not a substitute projectile
/// or a collision primitive. The source cloud's particles/ForceGlow shader and
/// alternate native mirrored-array selection are not claimed by this adapter.
@MainActor
final class DuelSerpentBottleAssets {
    enum Failure: Error { case profile, model }
    let model: GLTFModel
    let verifiedFiles: [DuelNetworkContentRecord]

    init(directory: URL, profile: DuelWeaponProfile) throws {
        guard DuelSerpentBottlePresentation.accepts(profile), let binding = profile.serpentBinding else {
            throw Failure.profile
        }
        try binding.validate(profile: profile)
        let name = DuelSerpentBottlePresentation.fileName
        let data = try DuelFighterAssetReleaseLoader.read(directory: directory, name: name,
            maximum: DuelSerpentBottlePresentation.fileBytes,
            bytes: DuelSerpentBottlePresentation.fileBytes, hash: DuelSerpentBottlePresentation.fileSHA256)
        try DuelFighterAssetReleaseLoader.validateSelfContainedGLB(data)
        let model = try GLTFModel(url: directory.appendingPathComponent(name), maxTexture: 1024,
                                  physicallyBased: true)
        guard model.hasSkinning,
              Set(model.names) == ["r_bottle_01_02", "Armature", "ranged_root", "zero_gun_joint_l",
                "gun_joint_l", "zero_gun_joint_r", "gun_joint_r", "rng__bottle_01_02_l", "rng__bottle_01_02_r"],
              model.materialNames == ["mat_rng__bottle_01_02_base"],
              Set(model.clips.keys) == [DuelSerpentBottlePresentation.animation],
              let clip = model.clips[DuelSerpentBottlePresentation.animation], clip.channels.count == 10,
              abs(clip.duration - 0.8) < 0.000001,
              clip.channels.allSatisfy({ channel in
                  channel.times.count == 25 && zip(channel.times, 0..<25).allSatisfy {
                      abs($0.0 - Float($0.1) / 30) < 0.000001
                  }
              }) else { throw Failure.model }
        // GLTFModel reads by URL: authenticate again after parsing to reject a
        // replaced input. Both checks use the external constant, not JSON data.
        guard DuelNetworkContentRecord.digest(try Data(contentsOf: directory.appendingPathComponent(name))) ==
                DuelSerpentBottlePresentation.fileSHA256 else { throw Failure.model }
        self.model = model
        verifiedFiles = [.init(path: name, bytes: data.count, sha256: DuelSerpentBottlePresentation.fileSHA256)]
    }

    func instantiate() -> GLTFModel.Instance {
        let value = model.instantiate()
        // The externally pinned GLB retains these exact sourceRaster fields.
        // Keep them explicit: SceneKit's defaults must not replace source
        // culling/filtering. The custom ForceGlow shader remains unbound.
        for material in value.materials {
            material.isDoubleSided = false
            material.cullMode = .back
            material.writesToDepthBuffer = true
            material.diffuse.minificationFilter = .linear
            material.diffuse.magnificationFilter = .linear
            material.diffuse.mipFilter = .none
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.maxAnisotropy = 1
            material.blendMode = .replace
        }
        return value
    }
}

/// Display callbacks only sample already authoritative IDs/positions/ticks.
/// They never consume a ranged use, create a cloud or advance gameplay/replay.
@MainActor
final class DuelSerpentBottleRenderer {
    private struct Key: Hashable { let owner: Int; let id: UInt64 }
    private struct Instance {
        let holder: SCNNode
        let model: GLTFModel.Instance
        var pose: GLTFModel.Pose
    }
    private let root = SCNNode()
    private let assets: DuelSerpentBottleAssets
    private var instances: [Key: Instance] = [:]

    init(assets: DuelSerpentBottleAssets, parent: SCNNode) {
        self.assets = assets
        root.name = "duel.serpent.bottles"
        parent.addChildNode(root)
    }

    func draw(_ fight: DuelWeaponFight) {
        let frames = DuelSerpentBottlePresentation.frames(in: fight)
        let live = Set(frames.map { Key(owner: $0.owner, id: $0.id) })
        for key in Array(instances.keys) where !live.contains(key) {
            instances.removeValue(forKey: key)?.holder.removeFromParentNode()
        }
        guard let clip = assets.model.clips[DuelSerpentBottlePresentation.animation] else { return }
        for frame in frames {
            let key = Key(owner: frame.owner, id: frame.id)
            var value: Instance
            if let existing = instances[key] { value = existing }
            else {
                // The authenticated GLB's default scene is its original
                // nonduplicate l mesh. Do not show both mirrored variants or
                // infer alternate-array selection from a display callback.
                let model = assets.instantiate(), holder = SCNNode()
                holder.name = "duel.serpent.bottle.\(frame.owner).\(frame.id)"
                holder.addChildNode(model.root); root.addChildNode(holder)
                value = .init(holder: holder, model: model, pose: assets.model.restPose)
            }
            value.pose.reset(from: assets.model.restPose)
            clip.sample(at: Float(frame.animationTime), into: &value.pose)
            for index in assets.model.animated { value.model.nodes[index].simdTransform = value.pose.transform(index) }
            value.holder.position = .init(Float(frame.origin.x), Float(frame.origin.y), Float(frame.origin.z))
            value.holder.eulerAngles = .init(0, frame.direction == 1 ? 0 : .pi, 0)
            let scale = Float(frame.modelScale)
            value.holder.scale = .init(scale, scale, scale)
            instances[key] = value
        }
    }

    func reset() {
        for value in instances.values { value.holder.removeFromParentNode() }
        instances.removeAll(keepingCapacity: true)
    }
    func shutdown() { reset(); root.removeFromParentNode() }
}
