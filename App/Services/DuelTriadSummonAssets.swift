import Foundation
import SceneKit
import simd

/// Original H17 companions have their own skeletons and motion files. They
/// are authenticated with the equipped character but never impersonate it.
@MainActor
final class DuelTriadSummonAssets {
    enum Failure: Error { case identity, manifest, file(String), model(String), motion(String) }
    struct Motion: Decodable {
        let roles: [String]
        let clip: String
        let frames: Int
        let exportFramesPerSecond: Int
        let sourceSHA256: String
        let sourceBundle: String
        /// Samples are source-frame ordered. Pelvis horizontal translation is
        /// zero in the exported skeleton and applied here exactly once.
        let root: [DuelWeaponPoint]
        let groundLift: [Double]
    }
    struct Definition: Decodable {
        struct Fresnel: Decodable {
            let color: [Float]
            let power: Float
            let transitionSeconds: Double
        }
        let sourceModel: String
        let file: DuelFighterAssetRelease.File
        let skinRoots: [DuelFighterAssetRelease.SkinRoot]
        let materials: [DuelFighterAssetRelease.Material]
        let motions: [Motion]
        let sourceFresnel: Fresnel
    }
    private struct Document: Decodable {
        let version: Int
        let profileID: String
        let characterSHA256: String
        let sourceConfigurationSHA256: String
        let evidence: [String]
        let models: [Definition]
    }
    struct Asset {
        let definition: Definition
        let model: GLTFModel
        let starts: [String: Float]
    }
    struct RoleBinding { let model: String; let motion: Motion }
    let profileID: String
    let characterSHA256: String
    let verifiedFiles: [DuelNetworkContentRecord]
    let models: [String: Asset]
    let roles: [String: RoleBinding]
    var sourceFrameCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: roles.map { ($0.key + "/" + $0.value.motion.clip, $0.value.motion.frames) })
    }
    func sourceBoneTransforms(_ names: Set<String>, summon: DuelTriadPresentation.Summon) -> [String: simd_float4x4] {
        guard let binding = roles[summon.motionRole], let asset = models[binding.model],
              let clip = asset.model.clips[binding.motion.clip], let start = asset.starts[binding.motion.clip] else { return [:] }
        let phase = min(1, max(0, Double(summon.motionTick) / Double(max(1, summon.lastSampleTick))))
        var pose = asset.model.restPose
        clip.sample(at: start + Float(phase) * (clip.duration - start), into: &pose)
        let motion = binding.motion, sample = phase * Double(motion.root.count - 1)
        let lower = Int(sample), upper = min(lower + 1, motion.root.count - 1), t = sample - Double(lower)
        let dx = motion.root[lower].x * (1 - t) + motion.root[upper].x * t - motion.root[0].x
        let lift = motion.groundLift[lower] * (1 - t) + motion.groundLift[upper] * t
        var root = simd_float4x4(simd_quatf(angle: -Float(summon.direction) * .pi / 2, axis: SIMD3(0, 1, 0)))
        root.columns.3 = SIMD4(Float(summon.xMillimeters) / 1000 + Float(dx) * Float(summon.direction),
            Float(summon.yMillimeters) / 1000 + Float(lift), Float(summon.zMillimeters) / 1000, 1)
        return Dictionary(uniqueKeysWithValues: names.compactMap { name in
            guard let index = asset.model.node(named: name), let transform = asset.model.sourceTransform(of: index, pose: pose) else { return nil }
            return (name, root * transform)
        })
    }

    init(directory: URL, manifestName: String, expectedSHA256: String,
         profile: DuelWeaponProfile) throws {
        func read(_ file: DuelFighterAssetRelease.File, maximum: Int) throws -> Data {
            try file.validate(maximum: maximum)
            let url = directory.appendingPathComponent(file.name)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  values.fileSize == file.bytes else { throw Failure.file(file.name) }
            let data = try Data(contentsOf: url)
            guard data.count == file.bytes, DuelNetworkContentRecord.digest(data) == file.sha256 else {
                throw Failure.file(file.name)
            }
            return data
        }
        guard profile.isTriad, profile.hero == .ember,
              DuelFighterAssetRelease.File.validName(manifestName), manifestName.hasSuffix(".json"),
              DuelFighterAssetRelease.validDigest(expectedSHA256) else { throw Failure.identity }
        let manifestURL = directory.appendingPathComponent(manifestName)
        let size = try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let data = try read(.init(name: manifestName, bytes: size, sha256: expectedSHA256), maximum: 1_000_000)
        let document = try JSONDecoder().decode(Document.self, from: data)
        let sourceModels = Set(DuelTriadRules.SummonMove.allCases.map(\.modelName))
        var expectedRoles: [String: (model: String, clip: String, frames: Int)] = [:]
        for move in DuelTriadRules.SummonMove.allCases {
            expectedRoles[move.role] = (move.modelName, URL(fileURLWithPath: move.sourceFileName).deletingPathExtension().lastPathComponent, move.sourceFrameCount)
        }
        for animation in [DuelTriadRules.SoulAnimation.ninjatoActiveStart, .ninjatoActiveEnd] {
            expectedRoles[animation.role] = (DuelTriadRules.SummonMove.danceNinjato.modelName,
                URL(fileURLWithPath: animation.sourceFileName).deletingPathExtension().lastPathComponent, animation.sourceFrameCount)
        }
        guard document.version == 1, document.profileID == profile.id,
              document.characterSHA256 == profile.sha256,
              DuelFighterAssetRelease.validDigest(document.sourceConfigurationSHA256),
              (1...32).contains(document.evidence.count),
              document.evidence.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }),
              document.models.count == sourceModels.count, Set(document.models.map(\.sourceModel)) == sourceModels,
              Set(document.models.map { $0.file.name }).count == sourceModels.count else { throw Failure.manifest }
        var models: [String: Asset] = [:], roles: [String: RoleBinding] = [:]
        var records = [DuelNetworkContentRecord(path: manifestName, bytes: data.count, sha256: expectedSHA256)]
        for definition in document.models {
            guard sourceModels.contains(definition.sourceModel), definition.file.name.hasSuffix(".glb"),
                  definition.skinRoots.count <= 16,
                  Set(definition.skinRoots.map(\.skin)).count == definition.skinRoots.count,
                  definition.skinRoots.allSatisfy({ (0..<16).contains($0.skin) &&
                      (0..<1024).contains($0.declared) && (0..<1024).contains($0.corrected) && $0.declared != $0.corrected }),
                  (1...16).contains(definition.materials.count),
                  Set(definition.materials.map(\.name)).count == definition.materials.count,
                  definition.materials.allSatisfy({ !$0.name.isEmpty && $0.name.utf8.count <= 256 && (1...16).contains($0.maxAnisotropy) }),
                  (1...16).contains(definition.motions.count),
                  Set(definition.motions.map(\.clip)).count == definition.motions.count,
                  (3...4).contains(definition.sourceFresnel.color.count),
                  definition.sourceFresnel.color.allSatisfy({ $0.isFinite && (0...16).contains($0) }),
                  definition.sourceFresnel.power.isFinite, (0.001...64).contains(definition.sourceFresnel.power),
                  definition.sourceFresnel.transitionSeconds.isFinite,
                  (0...10).contains(definition.sourceFresnel.transitionSeconds),
                  definition.motions.contains(where: { !$0.roles.isEmpty }) else { throw Failure.manifest }
            let modelData = try read(definition.file, maximum: 8_000_000)
            try DuelFighterAssetReleaseLoader.validateSelfContainedGLB(modelData)
            let corrections = Dictionary(uniqueKeysWithValues: definition.skinRoots.map {
                ($0.skin, GLTFModel.SkinRootCorrection(declared: $0.declared, corrected: $0.corrected))
            })
            let model = try GLTFModel(url: directory.appendingPathComponent(definition.file.name),
                maxTexture: 1024, physicallyBased: true, skinRootCorrections: corrections)
            guard model.hasSkinning, model.node(named: "SF3_Actor_Meters") != nil,
                  model.node(named: "pelvis") != nil,
                  Set(model.clips.keys) == Set(definition.motions.map(\.clip)),
                  Set(definition.materials.map(\.name)) == model.materialNames else { throw Failure.model(definition.file.name) }
            var starts: [String: Float] = [:]
            for motion in definition.motions {
                guard !motion.clip.isEmpty, motion.clip.utf8.count <= 128,
                      motion.roles.count <= expectedRoles.count, Set(motion.roles).count == motion.roles.count,
                      (2...4096).contains(motion.frames), (1...240).contains(motion.exportFramesPerSecond),
                      DuelFighterAssetRelease.validDigest(motion.sourceSHA256),
                      !motion.sourceBundle.isEmpty, motion.sourceBundle.utf8.count <= 512,
                      motion.root.count == 2 * (motion.frames - 1) + 1,
                      motion.groundLift.count == motion.root.count,
                      motion.root.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite &&
                          abs($0.x) < 100 && abs($0.y) < 100 && abs($0.z) < 100 }),
                      motion.groundLift.allSatisfy({ $0.isFinite && abs($0) < 10 }),
                      let clip = model.clips[motion.clip], !clip.channels.isEmpty,
                      let start = clip.channels.compactMap({ $0.times.first }).min(), start.isFinite,
                      abs(clip.duration - start - Float(motion.frames - 1) / Float(motion.exportFramesPerSecond)) < 0.001 else {
                    throw Failure.motion(motion.clip)
                }
                starts[motion.clip] = start
                for role in motion.roles {
                    guard roles[role] == nil, let expected = expectedRoles[role],
                          expected.model == definition.sourceModel, expected.clip == motion.clip,
                          expected.frames == motion.frames,
                          let track = profile.summonTrack(role: role), track.clip == motion.clip,
                          track.frames == motion.frames, track.sourceSHA256 == motion.sourceSHA256,
                          track.sourceBundle == motion.sourceBundle, track.root == motion.root,
                          track.groundLift == motion.groundLift else { throw Failure.motion(role) }
                    roles[role] = .init(model: definition.sourceModel, motion: motion)
                }
            }
            // The loader parses the same immutable bytes fingerprinted above.
            guard DuelNetworkContentRecord.digest(try Data(contentsOf: directory.appendingPathComponent(definition.file.name))) == definition.file.sha256 else {
                throw Failure.file(definition.file.name)
            }
            models[definition.sourceModel] = .init(definition: definition, model: model, starts: starts)
            records.append(.init(path: definition.file.name, bytes: modelData.count, sha256: definition.file.sha256))
        }
        guard Set(roles.keys) == Set(expectedRoles.keys) else { throw Failure.manifest }
        self.profileID = profile.id; characterSHA256 = profile.sha256
        self.models = models; self.roles = roles; verifiedFiles = records.sorted { $0.path < $1.path }
    }
}

/// Draws independently authored companion skins from authoritative snapshots.
/// Redraws and skipped display frames cannot create attacks or advance timers.
@MainActor
final class DuelTriadSummonRenderer {
    private struct Key: Hashable { let owner: Int; let id: UInt64 }
    private struct Instance {
        let root: SCNNode
        let model: GLTFModel.Instance
        var pose: GLTFModel.Pose
    }
    private let root = SCNNode()
    private let assets: DuelTriadSummonAssets
    private var instances: [Key: Instance] = [:]
    init(assets: DuelTriadSummonAssets, parent: SCNNode) {
        self.assets = assets; root.name = "duel.triad.souls"; parent.addChildNode(root)
    }
    func draw(_ snapshot: DuelTriadPresentation, fighting: Bool) {
        guard fighting else { reset(); return }
        let live = Set(snapshot.summons.map { Key(owner: $0.owner, id: $0.id) })
        for key in Array(instances.keys) where !live.contains(key) {
            instances.removeValue(forKey: key)?.root.removeFromParentNode()
        }
        for summon in snapshot.summons {
            let role = summon.motionRole
            guard let binding = assets.roles[role], let asset = assets.models[binding.model] else { continue }
            let motion = binding.motion
            guard
                  let clip = asset.model.clips[motion.clip], let start = asset.starts[motion.clip] else { continue }
            let key = Key(owner: summon.owner, id: summon.id)
            var value: Instance
            if let existing = instances[key] { value = existing }
            else {
                let instance = asset.model.instantiate(), holder = SCNNode()
                holder.name = "duel.triad.\(summon.soul.rawValue).\(summon.owner).\(summon.id)"
                holder.addChildNode(instance.root); root.addChildNode(holder)
                for definition in asset.definition.materials {
                    for material in instance.materials where material.name == definition.name {
                        material.isDoubleSided = definition.doubleSided
                        material.cullMode = definition.cull == .front ? .front : .back
                        material.diffuse.minificationFilter = definition.minification == .linear ? .linear : .nearest
                        material.diffuse.magnificationFilter = definition.magnification == .linear ? .linear : .nearest
                        switch definition.mip {
                        case .none: material.diffuse.mipFilter = .none
                        case .nearest: material.diffuse.mipFilter = .nearest
                        case .linear: material.diffuse.mipFilter = .linear
                        }
                        material.diffuse.wrapS = definition.wrapS == .repeat ? .repeat : .clamp
                        material.diffuse.wrapT = definition.wrapT == .repeat ? .repeat : .clamp
                        material.diffuse.maxAnisotropy = CGFloat(definition.maxAnisotropy)
                        material.lightingModel = .constant
                        material.blendMode = .alpha; material.writesToDepthBuffer = false
                        material.readsFromDepthBuffer = true
                        let fresnel = asset.definition.sourceFresnel
                        material.setValue(NSValue(scnVector4: .init(fresnel.color[0], fresnel.color[1],
                            fresnel.color[2], fresnel.power)), forKey: "sourceFresnel")
                        var modifiers = material.shaderModifiers ?? [:]
                        // Original variant3930 dots the world normal with the
                        // camera's forward axis. SceneKit surface normals are
                        // in view space, so the same absolute dot is normal.z.
                        // Original MainTex is black; the visible RGB is rim
                        // light. Its independent alpha mask survives below.
                        modifiers[.fragment] = """
                        #pragma arguments
                        float4 sourceFresnel;
                        float sourceFresnelMix;
                        #pragma transparent
                        #pragma body
                        float edge = pow(clamp(1.0 - abs(normalize(_surface.normal).z), 0.0, 1.0), sourceFresnel.w);
                        _output.color = float4(edge * sourceFresnel.rgb * sourceFresnelMix, _surface.diffuse.a);
                        """
                        material.shaderModifiers = modifiers
                    }
                }
                value = .init(root: holder, model: instance, pose: asset.model.restPose)
            }
            let phase = min(1, max(0, Double(summon.motionTick) / Double(max(1, summon.lastSampleTick))))
            value.pose.reset(from: asset.model.restPose)
            clip.sample(at: start + Float(phase) * (clip.duration - start), into: &value.pose)
            for index in asset.model.animated { value.model.nodes[index].simdTransform = value.pose.transform(index) }
            let transition = asset.definition.sourceFresnel.transitionSeconds * Double(DuelGame.ticksPerSecond)
            let fade = transition == 0 ? 1 : min(1, Double(summon.age) / transition)
            for material in value.model.materials { material.setValue(NSNumber(value: fade), forKey: "sourceFresnelMix") }
            let sample = phase * Double(motion.root.count - 1), lower = Int(sample)
            let upper = min(lower + 1, motion.root.count - 1), t = sample - Double(lower)
            let dx = motion.root[lower].x * (1 - t) + motion.root[upper].x * t - motion.root[0].x
            let lift = motion.groundLift[lower] * (1 - t) + motion.groundLift[upper] * t
            value.root.position = .init(Float(summon.xMillimeters) / 1000 + Float(dx) * Float(summon.direction),
                Float(summon.yMillimeters) / 1000 + Float(lift), Float(summon.zMillimeters) / 1000)
            value.root.eulerAngles = .init(0, -Float(summon.direction) * .pi / 2, 0)
            instances[key] = value
        }
    }
    func reset() {
        for value in instances.values { value.root.removeFromParentNode() }
        instances.removeAll(keepingCapacity: true)
    }
    func shutdown() { reset(); root.removeFromParentNode() }
}
