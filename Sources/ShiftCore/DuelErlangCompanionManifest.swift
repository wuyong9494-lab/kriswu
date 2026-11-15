import Foundation

/// A companion keeps its own rig and original source window. This manifest is
/// bound to the local Wu profile, independently of the H17 companion release.
public struct DuelErlangCompanionManifest: Codable, Equatable, Sendable {
    public static let fileName = "SF3_D15_Companions.json"
    public static let role = "erlangSummon_hound"
    public static let sourceMotionSHA256 = "6443c760202bf084ae030d81b419f8494db1f4aa2e7c7904c40054bdf924b712"
    public static let sourceBonesSHA256 = "72f0791d0bd777caa31d7616feee71e737ccc67aa40f4827c49b1203f639c82d"
    public static let sourceConfigurationSHA256 = "3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701"
    public static let attackParts = ["Dog_Head_Attacking_Edge", "Dog_Body_Attacking_Edge",
                                   "Dog_Front_Attacking_Edge_l", "Dog_Front_Attacking_Edge_r"]
    public struct Model: Codable, Equatable, Sendable {
        public let sourceModel: String
        public let rootBone: String
        public let file: DuelFighterAssetRelease.File
        public let materials: [DuelFighterAssetRelease.Material]
        public let track: DuelSummonMotionTrack
        public let originalMotionFrames: Int
        public let firstSourceFrame: Int
        public let lastSourceFrame: Int
        public let exportFramesPerSecond: Int
        public let endEventTick: Int
        public let hideStartTick: Int
        public let hideEndTick: Int
        public let fadeOutTicks: Int
        public let fadeInTicks: Int

        /// Deterministic visibility adapter for source HideModel events. It is
        /// sampled from simulation time, never advanced by a display callback.
        /// Opacity preserves event timing; it does not claim the original
        /// custom morph/shader is equivalent to an alpha blend.
        public func opacity(at motionTick: Int) -> Double {
            guard (0...endEventTick).contains(motionTick) else { return 0 }
            if motionTick < hideStartTick { return 1 }
            if motionTick <= hideEndTick {
                return max(0, 1 - Double(motionTick - hideStartTick) / Double(max(1, fadeOutTicks)))
            }
            return min(1, Double(motionTick - hideEndTick - 1) / Double(max(1, fadeInTicks)))
        }
    }
    public let version: Int
    public let profileID: String
    public let characterSHA256: String
    public let sourceConfigurationSHA256: String
    public let models: [Model]
    public enum Failure: Error, Equatable { case identity, model, track, material }

    public func validate(profile: DuelWeaponProfile) throws {
        guard version == 1, profileID == "wuyong_erlang", profileID == profile.id,
              characterSHA256 == profile.sha256,
              DuelFighterAssetRelease.validDigest(characterSHA256),
              sourceConfigurationSHA256 == Self.sourceConfigurationSHA256,
              models.count == 1 else { throw Failure.identity }
        let value = models[0], track = value.track
        try value.file.validate(maximum: 8_000_000)
        guard value.sourceModel == "mgc__d15_dog", value.rootBone == "spine_root_joint",
              value.file.name == "SF3WE_D15_Hound.glb",
              value.originalMotionFrames == 141, value.firstSourceFrame == 1,
              value.lastSourceFrame == 60, value.exportFramesPerSecond == 30,
              value.endEventTick == 110, value.hideStartTick == 0, value.hideEndTick == 55,
              value.fadeOutTicks == 10, value.fadeInTicks == 15 else { throw Failure.model }
        try track.validate()
        let expectedIDs = Set(Self.attackParts + ["Dog_Back_Attacking_Edge_l", "Dog_Back_Attacking_Edge_r"])
        let radii = ["Dog_Head_Attacking_Edge": 200, "Dog_Body_Attacking_Edge": 100,
                     "Dog_Front_Attacking_Edge_l": 120, "Dog_Front_Attacking_Edge_r": 120,
                     "Dog_Back_Attacking_Edge_l": 120, "Dog_Back_Attacking_Edge_r": 120]
        guard track == profile.summonTrack(role: Self.role), track.role == Self.role,
              track.clip == "d15_dog_attack", track.frames == 60, track.root.count == 119,
              track.sourceEndEventTick == value.endEventTick,
              track.sourceSHA256 == Self.sourceMotionSHA256,
              track.sourceBundle == "2a784bc550bc06541a38a4c1c53b69f3.bin",
              track.boneConfigurationSHA256 == Self.sourceBonesSHA256,
              track.groundLift.allSatisfy({ $0 == 0 }),
              track.attackParts == ["primary": Self.attackParts],
              track.hurtCapsules?.isEmpty == true,
              Set(track.collisionEdges?.map(\.id) ?? []) == expectedIDs,
              track.collisionEdges?.allSatisfy({ edge in
                  edge.radiusMillimeters == radii[edge.id] &&
                    edge.side == (edge.id.hasSuffix("_l") ? "left" : "right")
              }) == true else { throw Failure.track }
        guard value.materials.count == 1,
              value.materials[0].name == "mat_mgc__d15_dog_base",
              value.materials[0].doubleSided,
              value.materials[0].cull == .back,
              (1...16).contains(value.materials[0].maxAnisotropy) else { throw Failure.material }
    }
}
