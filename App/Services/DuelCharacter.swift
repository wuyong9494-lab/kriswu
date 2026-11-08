import Foundation
import CryptoKit
import SceneKit
import UIKit
import simd

/// One decoded asset per fight. Instances share immutable mesh buffers/textures,
/// but own their skeleton, material feedback and reusable pose buffers.
@MainActor
final class DuelCharacterAsset {
    enum AssetError: Error { case missing, integrity, incomplete }
    static let digest = "ac9c5f1e1186a66466ec37457601b82bfcd654bcac9aee8cde65b36ed173caa9"
    static var bundledURL: URL? { bundledURL(for: .liu) }
    static func bundledURL(for hero: DuelGame.Hero) -> URL? {
        let name: String
        switch hero {
        case .liu: name = "Liu_FullBody_Mobile"
        case .ember: name = "Sun_FullBody_Prototype"
        case .gale: return nil
        }
        return Bundle.main.url(forResource: name, withExtension: "glb") ??
            Bundle.main.url(forResource: name, withExtension: "glb", subdirectory: "FighterPrivate")
    }
    let hero: DuelGame.Hero
    let model: GLTFModel
    let starts: [String: Float]
    init(url: URL, hero: DuelGame.Hero = .liu) throws {
        self.hero = hero
        let expectedBytes: Int, expectedDigest: String
        switch hero {
        case .liu: expectedBytes = 5_043_964; expectedDigest = Self.digest
        case .ember:
            expectedBytes = 7_953_392
            expectedDigest = "87b7b420206e1962e121eb49ac459b19144f66fef9590770b37849adc9576241"
        case .gale: throw AssetError.incomplete
        }
        let bytes = try Data(contentsOf: url)
        guard bytes.count == expectedBytes,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == expectedDigest else {
            throw AssetError.integrity
        }
        let decoded = try GLTFModel(url: url, maxTexture: 1024, physicallyBased: true)
        guard decoded.hasSkinning,
              DuelCharacterAnimation.Clip.allCases.allSatisfy({ decoded.clips[$0.rawValue] != nil }),
              ["head", "hips", "hand.L", "hand.R", "foot.L", "foot.R", "upper_arm.L", "upper_arm.R", "forearm.L", "forearm.R"]
                .allSatisfy({ decoded.node(named: $0) != nil }) else { throw AssetError.incomplete }
        model = decoded
        starts = decoded.clips.mapValues { $0.channels.compactMap { $0.times.first }.min() ?? 0 }
    }
}

@MainActor
final class DuelCharacterInstance {
    let asset: DuelCharacterAsset
    let instance: GLTFModel.Instance
    private var pose: GLTFModel.Pose
    private var secondary: GLTFModel.Pose
    private var transition: GLTFModel.Pose
    private var lastKey: String?
    private var changedAt = 0
    private var lastTick = -1
    private var soles: [SCNNode] = []
    private let originalEmission: [Any?]

    init(_ asset: DuelCharacterAsset) {
        self.asset = asset; instance = asset.model.instantiate()
        pose = asset.model.restPose; secondary = pose; transition = pose
        originalEmission = instance.materials.map { $0.emission.contents }
        instance.root.name = "duel.\(asset.hero.rawValue).skinned"
        // Markers use the authored outsole footprint in the glTF bind space.
        // They follow the actual foot bones, including during blended poses.
        for (suffix, sign) in [("L", Float(-1)), ("R", Float(1))] {
            guard let foot = bone("foot.\(suffix)") else { continue }
            for x in [Float(-0.057), Float(0.057)] {
                for z in [Float(-0.115), Float(0.148)] {
                    let marker = SCNNode(); marker.name = "duel.sole.\(suffix)"
                    marker.position = foot.convertPosition(SCNVector3(sign * 0.102 + x, 0, z), from: instance.root)
                    foot.addChildNode(marker); soles.append(marker)
                }
            }
        }
    }
    func bone(_ name: String) -> SCNNode? {
        asset.model.node(named: name).map { instance.nodes[$0] }
    }
    private func sample(_ clip: DuelCharacterAnimation.Clip, progress: Float, into target: inout GLTFModel.Pose) {
        target.reset(from: asset.model.restPose)
        guard let data = asset.model.clips[clip.rawValue] else { return }
        let start = asset.starts[clip.rawValue] ?? 0
        data.sample(at: start + (data.duration - start) * progress, into: &target)
    }
    func apply(_ selection: DuelCharacterAnimation, tick: Int) {
        if tick < lastTick { lastKey = nil } // restart resets blend history
        if lastKey != selection.key {
            transition.reset(from: pose); changedAt = tick
        }
        let hadPose = lastKey != nil
        sample(selection.clip, progress: selection.progress, into: &pose)
        if let clip = selection.secondary {
            sample(clip, progress: selection.secondaryProgress, into: &secondary)
            pose.blend(toward: secondary, weight: selection.secondaryWeight, nodes: asset.model.animated)
        }
        if hadPose, selection.transitionTicks > 0 {
            let elapsed = max(0, tick - changedAt)
            let weight = max(0, 1 - Float(elapsed) / Float(selection.transitionTicks))
            pose.blend(toward: transition, weight: weight, nodes: asset.model.animated)
        }
        for index in asset.model.animated { instance.nodes[index].simdTransform = pose.transform(index) }
        lastKey = selection.key; lastTick = tick
    }
    func pose(_ fighter: DuelGame.Fighter, tick: Int, grapple: DuelGame.Grapple?, index: Int,
              phase: DuelGame.Phase, root: SCNNode) {
        apply(.sample(fighter, animationTick: tick, grapple: grapple, index: index, phase: phase), tick: tick)
        root.position = SCNVector3(Float(fighter.x) / 1000, Float(fighter.y) / 1000, 0)
        let yaw: Float = fighter.facing > 0 ? .pi / 2 : -.pi / 2
        var roll: Float = 0
        if fighter.knockdown > 0 {
            roll = -Float(fighter.facing) * .pi / 2
            root.position.y = 0.25; root.position.x -= Float(fighter.facing) * 0.95
        }
        var grounded = fighter.y == 0 && fighter.knockdown == 0
        if let hold = grapple {
            let fall = min(1, Float(hold.age) / Float(DuelGame.Grapple.takedownTicks))
            let eased = fall * fall * (3 - 2 * fall)
            let release = max(0, Float(hold.age - DuelGame.Grapple.takedownTicks - DuelGame.Grapple.holdTicks) / Float(DuelGame.Grapple.releaseTicks))
            let direction = Float(hold.direction)
            if hold.attacker == index {
                root.position.x += direction * 0.12 * eased * (1 - release)
                root.position.z = 0.55 * eased
                // The clip contains its own grounded crouch/root translation.
                // Applying the greybox's extra crouch would sink the shoes.
            } else {
                grounded = false
                root.position.x += direction * (1.35 * eased + 0.30 * release)
                root.position.y = 0.25 * eased + sin(fall * .pi) * 0.25
                root.position.z = -0.08 * eased; roll = direction * .pi / 2 * eased
            }
        }
        root.simdOrientation = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1)) *
            simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        if grounded, let low = soles.map({ $0.worldPosition.y }).min() {
            root.position.y += max(0, -0.045 - low)
        }
        for (i, material) in instance.materials.enumerated() {
            material.emission.contents = fighter.flash > 0 ? UIColor(red: 0.12, green: 0.045, blue: 0.01, alpha: 1) : originalEmission[i]
        }
    }

    /// Visual wrist constraint only; rule positions and hitboxes stay untouched.
    /// A short, bounded CCD solve adjusts two arm bones after both actors pose.
    func reach(suffix: String, target: SIMD3<Float>, weight: Float) {
        guard let hand = bone("hand.\(suffix)"), let forearm = bone("forearm.\(suffix)"),
              let upper = bone("upper_arm.\(suffix)"), weight > 0 else { return }
        let goal = hand.simdWorldPosition + (target - hand.simdWorldPosition) * min(1, weight)
        for _ in 0..<8 {
            for joint in [forearm, upper] {
                let a = hand.simdWorldPosition - joint.simdWorldPosition
                let b = goal - joint.simdWorldPosition
                guard simd_length_squared(a) > 0.000001, simd_length_squared(b) > 0.000001 else { continue }
                let delta = simd_quatf(from: simd_normalize(a), to: simd_normalize(b))
                joint.simdWorldOrientation = GLTFModel.unit(delta * joint.simdWorldOrientation)
            }
        }
    }
}
