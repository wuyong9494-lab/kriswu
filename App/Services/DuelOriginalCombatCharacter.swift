import SceneKit
import UIKit
import simd

/// Runtime presentation using the original hierarchy and skin, not retargeting.
@MainActor
final class DuelOriginalCombatInstance {
    let asset: DuelOriginalRigAsset
    let instance: GLTFModel.Instance
    private var pose: GLTFModel.Pose
    private var secondary: GLTFModel.Pose
    private var transition: GLTFModel.Pose
    private var lastKey: String?
    private var changedAt = 0
    private var transitionEnabled = false
    private var lastTick = -1
    private var soles: [SCNNode] = []
    private var idlePelvisHeight: Float = 0
    private let originalEmission: [Any?]
    private static let aliases = ["hips": "pelvis", "hand.L": "hand_l", "hand.R": "hand_r",
                                  "upper_arm.L": "arm_l", "upper_arm.R": "arm_r",
                                  "forearm.L": "forearm_l", "forearm.R": "forearm_r"]

    init(_ asset: DuelOriginalRigAsset) {
        self.asset = asset; instance = asset.model.instantiate()
        pose = asset.model.restPose; secondary = pose; transition = pose
        originalEmission = instance.materials.map { $0.emission.contents }
        instance.root.name = "duel.\(asset.identity == .liu ? "liu" : "ember").original"
        for side in ["l", "r"] {
            guard let foot = sourceBone("foot_" + side), let toe = sourceBone("toe_" + side) else { continue }
            let a = instance.root.convertPosition(foot.worldPosition, from: nil)
            let b = instance.root.convertPosition(toe.worldPosition, from: nil)
            for x in [min(a.x, b.x) - 0.055, max(a.x, b.x) + 0.055] {
                for z in [min(a.z, b.z) - 0.055, max(a.z, b.z) + 0.055] {
                    let marker = SCNNode(); marker.name = "duel.source.sole.\(side)"
                    marker.position = foot.convertPosition(SCNVector3(x, -0.02, z), from: instance.root)
                    foot.addChildNode(marker); soles.append(marker)
                }
            }
        }
        asset.sample(.init(clip: .idle, phase: 0), into: &pose)
        for index in asset.model.animated { instance.nodes[index].simdTransform = pose.transform(index) }
        if let pelvis = sourceBone("pelvis") {
            idlePelvisHeight = instance.root.convertPosition(pelvis.worldPosition, from: nil).y
        }
    }
    private func sourceBone(_ name: String) -> SCNNode? {
        asset.model.node(named: name).map { instance.nodes[$0] }
    }
    /// Semantic lookup for the shared grip constraint; node names are preserved.
    func bone(_ name: String) -> SCNNode? {
        return sourceBone(Self.aliases[name] ?? name)
    }
    func apply(_ selection: DuelOriginalCombatAnimation, tick: Int) {
        if tick < lastTick { lastKey = nil }
        let hadPose = lastKey != nil
        if lastKey != selection.key {
            transition.reset(from: pose); changedAt = tick
            transitionEnabled = hadPose && selection.transitionTicks > 0
        }
        asset.sample(selection.selection, into: &pose)
        if let selected = selection.secondary {
            asset.sample(selected, into: &secondary)
            pose.blend(toward: secondary, weight: selection.secondaryWeight, nodes: asset.model.animated)
        }
        if transitionEnabled, selection.transitionTicks > 0 {
            pose.blend(toward: transition,
                       weight: max(0, 1 - Float(max(0, tick - changedAt)) / Float(selection.transitionTicks)),
                       nodes: asset.model.animated)
        }
        for index in asset.model.animated { instance.nodes[index].simdTransform = pose.transform(index) }
        lastKey = selection.key; lastTick = tick
    }
    func pose(_ fighter: DuelGame.Fighter, tick: Int, grapple: DuelGame.Grapple?, index: Int,
              phase: DuelGame.Phase, root: SCNNode) {
        let selection = DuelOriginalCombatAnimation.sample(fighter, animationTick: tick, grapple: grapple, index: index, phase: phase)
        apply(selection, tick: tick)
        root.position = SCNVector3(Float(fighter.x) / 1000, Float(fighter.y) / 1000, 0)
        // The source actor faces -Z in this glTF (Blender +Y), unlike the old rig.
        root.eulerAngles = SCNVector3(0, -Float(fighter.facing) * .pi / 2, 0)
        if selection.selection.clip == .jump, let pelvis = sourceBone("pelvis") {
            // Physics already supplies vertical travel. Keep the source joint
            // pose but do not add the clip's root lift a second time.
            let sourceHeight = instance.root.convertPosition(pelvis.worldPosition, from: nil).y
            root.position.y -= sourceHeight - idlePelvisHeight
        }
        var grounded = fighter.y == 0 && fighter.knockdown == 0
        if let hold = grapple {
            let fall = min(1, Float(hold.age) / Float(DuelGame.Grapple.takedownTicks))
            let eased = fall * fall * (3 - 2 * fall)
            if hold.attacker == index { root.position.z = 0.55 * eased }
            else {
                grounded = false
                root.position.x += Float(hold.direction) * 0.30 * eased
                root.position.y = 0.03 * eased
            }
        }
        if grounded, let low = soles.map({ $0.worldPosition.y }).min() {
            root.position.y += max(0, -0.035 - low)
        }
        for (index, material) in instance.materials.enumerated() {
            material.emission.contents = fighter.flash > 0 ? UIColor(red: 0.12, green: 0.045, blue: 0.01, alpha: 1) : originalEmission[index]
        }
    }
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
