import Foundation

/// Unified provenance & completion registry across all 4 heroes of《裂隙对决》:
/// 1. 吴庸 / 幕府将军 (`shogun.rar` -> `DuelShogunHeavyPhase1`)
/// 2. 刘泉纬 / 君主 (`emperor.rar` -> `DuelEmperorPhase2`)
/// 3. 徐骁 / 军团之王 (`legion_king.rar` -> `DuelLegionKingPhase3`)
/// 4. 孙登 / 孙悟空 (`monkey_king.rar` -> `DuelMonkeyKingPhase4`)
///
/// Enforces strict provenance honesty: every original binary asset/kinematics measurement is separated
/// from independently built gap-fills (`independentRecreation`) and live mobile observations.
public enum DuelAll4HeroesGapFillRegistry {

    public typealias Provenance = DuelShogunHeavyPhase1.Provenance

    public struct HeroCompletionProfile: Equatable, Codable, Sendable {
        public let heroID: String
        public let displayNameZH: String
        public let sourceArchive: String
        public let cleanHeadGLB: String
        public let localBundleCount: Int
        public let missingExternalCABRefs: Int
        public let hasRealBaseModelAnd1KPBR: Bool
        public let hasRealOriginalSFX: Bool
        public let hasVerifiedGuardTrack: Bool
        public let guardTrackProvenance: Provenance
        public let signatureMechanics: [String]
        public let completedGapFillIDs: [String]
        public let remainingBlockingGaps: Int
    }

    public static let allHeroProfiles: [HeroCompletionProfile] = [
        .init(
            heroID: "wuYong_shogun",
            displayNameZH: "吴庸 / 幕府将军",
            sourceArchive: "shogun.rar",
            cleanHeadGLB: "CleanHead_wuYong.glb",
            localBundleCount: 38,
            missingExternalCABRefs: 74,
            hasRealBaseModelAnd1KPBR: true,
            hasRealOriginalSFX: true,
            hasVerifiedGuardTrack: true,
            guardTrackProvenance: .originalBinaryMeasured,
            signatureMechanics: [
                "Odachi Heavy Slash (shogun_heavy 66f/131t60, +1.919m lunge, active t60 44...51)",
                "Original Middle Heavy Guard (b_shogun_middle_heavy 41f/81t60, 1.279m slide)",
                "Head-Swapped CleanHead_wuYong + Recreated Odachi Trail & Impact Shaders",
            ],
            completedGapFillIDs: [
                "head_swap_wuYong",
                "rec_vfx_shogun_heavy_trail_shader",
                "rec_vfx_shogun_heavy_impact_and_guard_shield",
                "rec_shogun_ordinary_heavy_scalars",
            ],
            remainingBlockingGaps: 0
        ),
        .init(
            heroID: "liuQuanwei_emperor",
            displayNameZH: "刘泉纬 / 君主",
            sourceArchive: "emperor.rar",
            cleanHeadGLB: "CleanHead_liuQuanwei.glb",
            localBundleCount: 86,
            missingExternalCABRefs: 150,
            hasRealBaseModelAnd1KPBR: true,
            hasRealOriginalSFX: true,
            hasVerifiedGuardTrack: true,
            guardTrackProvenance: .independentRecreation,
            signatureMechanics: [
                "Dual-Form Transformation (emperor_transition 86f/171t60, burst t60 100...103, human -> shadowBeast)",
                "Human Heavy Lunge (p_agl_heavy_punch 51f/101t60, +2.212m)",
                "Shadow Beast Claw Slash + Lifesteal (claws_spinning_slash_1 46f/91t60)",
                "Synthesized Human Idle + Mid-Guard (reusing original b_claws_low_block_heavy 1.181m slide)",
            ],
            completedGapFillIDs: DuelEmperorPhase2.gapFillManifest.map(\.id),
            remainingBlockingGaps: 0
        ),
        .init(
            heroID: "xuXiao_legionKing",
            displayNameZH: "徐骁 / 军团之王",
            sourceArchive: "legion_king.rar",
            cleanHeadGLB: "CleanHead_xuXiao.glb",
            localBundleCount: 72,
            missingExternalCABRefs: 193,
            hasRealBaseModelAnd1KPBR: true,
            hasRealOriginalSFX: true,
            hasVerifiedGuardTrack: true,
            guardTrackProvenance: .originalBinaryMeasured,
            signatureMechanics: [
                "Two-Handed Greatsword Heavy (twohanded_sword_heavy_slash 64f/127t60, +0.972m, 1.26m blade)",
                "Procedural 3D Shadow Chain (28 interlocking dark-iron links + ghostly shader) & Pull (-1.066m, Y=1.106m)",
                "Dark Incarnation Single-Trigger Revive (legion_king_ressurection 121f/241t60)",
                "Original Mid Heavy Guard (b_twohanded_sword_mid_block_heavy 32f/63t60, 1.108m slide)",
            ],
            completedGapFillIDs: DuelLegionKingPhase3.gapFillManifest.map(\.id),
            remainingBlockingGaps: 0
        ),
        .init(
            heroID: "sunDeng_monkeyKing",
            displayNameZH: "孙登 / 孙悟空",
            sourceArchive: "monkey_king.rar",
            cleanHeadGLB: "CleanHead_sunDeng.glb",
            localBundleCount: 82,
            missingExternalCABRefs: 57,
            hasRealBaseModelAnd1KPBR: true,
            hasRealOriginalSFX: true,
            hasVerifiedGuardTrack: true,
            guardTrackProvenance: .independentRecreation,
            signatureMechanics: [
                "Leaping Jingu Staff Heavy (staff_heavy_slash 52f/103t60, +3.406m lunge, Y=1.416m)",
                "Ascension Staff-Perch (monkey_king_climb_stance pelvisY=2.123m) Low-Attack Evasion + Plunge Strike (+2.729m)",
                "Synthesized Two-Handed Staff Guard (rec_monkey_king_mid_block_heavy 36f/71t60, 1.150m slide filling 0 b_* gap)",
                "Giant Pillar & Column Meshes (5.01m / 4.32m) + Procedural Golden Jingu Aura",
            ],
            completedGapFillIDs: DuelMonkeyKingPhase4.gapFillManifest.map(\.id),
            remainingBlockingGaps: 0
        ),
    ]

    public static var totalSourceBundlesAudited: Int {
        allHeroProfiles.reduce(0) { $0 + $1.localBundleCount }
    }

    public static var totalMissingExternalCABRefsReplaced: Int {
        allHeroProfiles.reduce(0) { $0 + $1.missingExternalCABRefs }
    }

    public static var totalRemainingBlockingGaps: Int {
        allHeroProfiles.reduce(0) { $0 + $1.remainingBlockingGaps }
    }
}
