import Foundation
import CryptoKit
import SceneKit

/// Strict source asset shared by review and gameplay. It preserves the source
/// rig, all clips and personal head. Combat presentation belongs to
/// DuelOriginalCombatInstance; this loader never substitutes the 42-bone rig.
@MainActor
final class DuelOriginalRigAsset {
    enum Identity: String, CaseIterable {
        case liu = "Liu", sun = "Sun"
        var resourceName: String { rawValue + "_OriginalRig_ActionSet" }
        var byteCount: Int { self == .liu ? 5_351_896 : 5_985_528 }
        var sha256: String {
            self == .liu ? "16381ae1b4d3a8c291ceb883a9bd83474655d90d8e63dcaf1296344a3e3f40d5" :
                "b38d30c4e3afd3bc94b9e62ed40964e8d6fe70548a0f29576dfe07665a2451df"
        }
    }
    enum AssetError: Error { case integrity, incomplete }
    static func identity(for hero: DuelGame.Hero) -> Identity? {
        switch hero { case .liu: return .liu; case .ember: return .sun; case .gale: return nil }
    }
    let identity: Identity
    let model: GLTFModel
    private let starts: [String: Float]

    static func bundledURL(for identity: Identity, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: identity.resourceName, withExtension: "glb") ??
            bundle.url(forResource: identity.resourceName, withExtension: "glb", subdirectory: "FighterPrivate")
    }

    init(url: URL, identity: Identity) throws {
        let bytes = try Data(contentsOf: url)
        guard bytes.count == identity.byteCount,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == identity.sha256 else {
            throw AssetError.integrity
        }
        let decoded = try GLTFModel(url: url, maxTexture: 1024, physicallyBased: true)
        let expected = Set(DuelOriginalRigReview.Clip.allCases.map(\.rawValue))
        guard decoded.hasSkinning, Set(decoded.clips.keys) == expected,
              Self.skeletonNames.allSatisfy({ decoded.node(named: $0) != nil }),
              decoded.node(named: identity.rawValue + "_Personal_Head") != nil else { throw AssetError.incomplete }
        var starts: [String: Float] = [:]
        for clip in DuelOriginalRigReview.Clip.allCases {
            guard let data = decoded.clips[clip.rawValue], !data.channels.isEmpty,
                  let start = data.channels.compactMap({ $0.times.first }).min(),
                  start.isFinite, data.duration.isFinite, data.duration >= start else { throw AssetError.incomplete }
            // TPose is an exporter diagnostic with two identical endpoint keys.
            if clip.source != nil {
                let expectedDuration = Float(clip.frameCount - 1) / Float(DuelOriginalRigReview.previewFramesPerSecond)
                guard abs(data.duration - start - expectedDuration) < 0.0001 else { throw AssetError.incomplete }
            }
            starts[clip.rawValue] = start
        }
        self.identity = identity; model = decoded; self.starts = starts
    }

    func sample(_ selection: DuelOriginalRigReview.Selection, into pose: inout GLTFModel.Pose) {
        pose.reset(from: model.restPose)
        guard let clip = model.clips[selection.clip.rawValue], let start = starts[selection.clip.rawValue] else { return }
        clip.sample(at: selection.assetTime(start: start, end: clip.duration), into: &pose)
    }

    // Original hierarchy names, not translated aliases from the gameplay rig.
    static let skeletonNames: [String] = [
        "skeleton", "Armature", "pelvis", "stomach", "chest", "neck",
        "head", "hair", "hair_01_m_tie1", "hair_agl_01_m_tie2", "hair_agl_01_m_tie3", "hair_agl_01_m_tie4",
        "zero_joint_hand_l", "chest_l", "clavicle_l", "arm_l", "biceps_twist_l", "forearm_l",
        "forearm_twist_l", "hand_l", "f_big1_l", "f_big2_l", "f_big3_l", "f_main1_l",
        "f_main2_l", "f_main3_l", "f_pointer1_l", "f_pointer2_l", "f_pointer3_l", "weapon_l",
        "scapular_l", "zero_joint_hand_r", "chest_r", "clavicle_r", "arm_r", "biceps_twist_r",
        "forearm_r", "forearm_twist_r", "hand_r", "f_big1_r", "f_big2_r", "f_big3_r",
        "f_main1_r", "f_main2_r", "f_main3_r", "f_pointer1_r", "f_pointer2_r", "f_pointer3_r",
        "weapon_r", "scapular_r", "zero_joint_pelvis_l", "back_l", "thigh_l", "calf_l",
        "foot_l", "toe_l", "thigh_twist_l", "zero_joint_pelvis_r", "back_r", "thigh_r",
        "calf_r", "foot_r", "toe_r", "thigh_twist_r"
    ]
}

@MainActor
final class DuelOriginalRigInstance {
    let asset: DuelOriginalRigAsset
    let instance: GLTFModel.Instance
    private var pose: GLTFModel.Pose

    init(_ asset: DuelOriginalRigAsset) {
        self.asset = asset; instance = asset.model.instantiate(); pose = asset.model.restPose
        instance.root.name = "duel.original-review.\(asset.identity.rawValue)"
    }

    /// No transition blending: a requested source frame must remain inspectable.
    /// All transforms reset on every selection, including reverse scrubs and
    /// switches from animated clips to the bind-pose diagnostic.
    func apply(_ selection: DuelOriginalRigReview.Selection) {
        asset.sample(selection, into: &pose)
        for index in asset.model.animated { instance.nodes[index].simdTransform = pose.transform(index) }
    }
}
