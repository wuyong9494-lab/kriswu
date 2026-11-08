import Foundation

/// Separate from DuelCharacterAnimation: source poses for inspection, never hit rules.
/// 30 FPS is an export/preview assumption, not recovered game timing. Source
/// contacts, actor forward direction and combo boundaries remain unverified.
public enum DuelOriginalRigReview {
    public static let previewFramesPerSecond: Double = 30
    public static let sourceFramesPerSecond: Double? = nil
    public static let combatTimingVerified = false
    public static let horizontalRootMotionRemoved = true

    public enum Clip: String, CaseIterable, Sendable {
        case idle = "Idle"
        case enter = "Enter"
        case walk = "Walk"
        case backStep = "BackStep"
        case forwardHop = "ForwardHop"
        case backwardHop = "BackwardHop"
        case guardPose = "Guard"
        case highGuard = "HighGuard"
        case dodge = "Dodge"
        case jump = "Jump"
        case jab = "Jab"
        case cross = "Cross"
        case comboFinish = "ComboFinish"
        case heavy = "Heavy"
        case uppercut = "Uppercut"
        case lowPunch = "LowPunch"
        case spinStart = "SpinStart"
        case spinStrike = "SpinStrike"
        case spinRecover = "SpinRecover"
        case hit = "Hit"
        case knockdown = "Knockdown"
        case getUp = "GetUp"
        case victory = "Victory"
        case backThrowActive = "BackThrowActive"
        case backThrowPassive = "BackThrowPassive"
        case tPose = "TPose"

        public var source: Source? {
            switch self {
            case .idle: return Source(name: "m_agl_stance_idle", sha256: "ef1ad3f58c8f303e911fb151f9a6155523aed529776a4d15b1fbacbc42172292", frameCount: 88)
            case .enter: return Source(name: "m_agl_stance_birth", sha256: "ad942f797b843d3ceb18c0b95315236de8a16677e7d562232c00d764bdbd7917", frameCount: 61)
            case .walk: return Source(name: "m_step_forward", sha256: "05fcbe23b2e34162facc0bdafa53cce2adfb28d6f0d80ba39f3397cfa02d1e0f", frameCount: 18)
            case .backStep: return Source(name: "m_step_back", sha256: "889650fcd0794728c8e698784f4655c37491c87e7aa7365368cada6d14c21b3e", frameCount: 21)
            case .forwardHop: return Source(name: "m_forward_hop", sha256: "a705408119f3374d2892de8b48206ec057dee6254eff3dee22ae5d2b70f9f3a3", frameCount: 17)
            case .backwardHop: return Source(name: "m_backward_hop", sha256: "5b7d1e2ef77eee38c77bd46bcfa6f7968058cb308fd4e7198d809376ab293b47", frameCount: 21)
            case .guardPose: return Source(name: "b_mid_block", sha256: "1078d13b5408db41093f1bd7a83516c6b1c03886e3a1876eb4c03230efc6d1f6", frameCount: 23)
            case .highGuard: return Source(name: "b_high_block", sha256: "3eb7df4ba1d2121c8dee5db9437b772f7a78402cc15e22480b583f3e011b80f5", frameCount: 36)
            case .dodge: return Source(name: "m_low_stance_dodge", sha256: "e0a8285cf5543c8996c427921d6b024b7ce704de6f5e9047c78443e187ffbba4", frameCount: 38)
            case .jump: return Source(name: "m_agl_jump_up", sha256: "f9ebee6d605849c6b80c5adec2aa5b81a182c2b00204dc9642e03a27495c1976", frameCount: 50)
            case .jab: return Source(name: "p_agl_punch_1", sha256: "bc83feb6585980216e13da7355c9c10d02abc0563c0af1f97c8f096164bf2166", frameCount: 34)
            case .cross: return Source(name: "p_agl_punch_2", sha256: "bc9670dae533a8085c407482bbe28eef49e6c76fda3091c0783d5beb4b129024", frameCount: 53)
            case .comboFinish: return Source(name: "p_agl_punch_3", sha256: "f90cebbba024940be0dd45c6b845f74b6976cf2ef370d1b717c7f689344c6154", frameCount: 56)
            case .heavy: return Source(name: "p_agl_heavy_punch", sha256: "153e4196e7a91152a5a0d3e41004af4be0abd8a23011c07ea5dc8117110253d1", frameCount: 54)
            case .uppercut: return Source(name: "p_agl_uppercut", sha256: "dff15546bbd0ecc6e194fa9de87d1004d4c647bbb468dc79ab9b071efb14d228", frameCount: 39)
            case .lowPunch: return Source(name: "p_agl_low_punch", sha256: "8e2985d9647362737f8adfd1d5fd6ae4d1f667dc0db1ab99516bec9a23fca987", frameCount: 47)
            case .spinStart: return Source(name: "p_agl_spinning_punch_1", sha256: "f6c8b5d0e3d3d368e5adb26c2a2abd57575e538ad17a916c063e538f32c894bb", frameCount: 43)
            case .spinStrike: return Source(name: "p_agl_spinning_punch_2", sha256: "76afd32144fc8f642e65a6e8efa2b2037699ec948575724a6acc0a91fa725529", frameCount: 48)
            case .spinRecover: return Source(name: "p_agl_spinning_punch_3", sha256: "6c167c00aed557f528c1a315c28098a9fb9820eb3d5279487cacedb542299714", frameCount: 72)
            case .hit: return Source(name: "h_chest_short_fast", sha256: "a41be3f18e6606fac3be02ba65a12c65e48ee24492d547aaa0214a8a3e64d5da", frameCount: 26)
            case .knockdown: return Source(name: "h_hit_head_fall", sha256: "9fda1b85f59b5ff7a6b6406ad3720347ab0b43f9330108d249892ec2ce08fef2", frameCount: 59)
            case .getUp: return Source(name: "m_agl_stand_up_back_forward", sha256: "59dcc0444d0fdc355b07b1c9be39d2a1301174a0dfa8eda5b4001c5d8b970ed9", frameCount: 50)
            case .victory: return Source(name: "m_agl_win_stance", sha256: "4d9e990740ff52a71ffc4ed98fd8c3b691e271c0f41a923035ed1583aec90ba2", frameCount: 61)
            case .backThrowActive: return Source(name: "agl_throw_back_active", sha256: "d1977b1478dd40ff9ae85b5819b11e7744ff2883e40fe1601d44d9f96b33b40b", frameCount: 52)
            case .backThrowPassive: return Source(name: "agl_throw_back_passive", sha256: "f2975086ec03e41cb769f92a697d51c6c94e2fb6cc0d1b3c774ec0caa6f7d9e4", frameCount: 52)
            case .tPose: return nil // Generated bind-pose diagnostic, not a source move.
            }
        }
        public var frameCount: Int { source?.frameCount ?? 1 }
    }

    public struct Source: Equatable, Sendable {
        public let name: String
        public let sha256: String
        public let frameCount: Int
    }

    /// Stateless controls make scrubbing, pausing and restarting deterministic.
    /// Phase is the whole source clip, NOT startup/contact/recovery in combat.
    public struct Selection: Equatable, Sendable {
        public let clip: Clip
        public let phase: Double
        public init(clip: Clip, phase: Double) {
            self.clip = clip
            self.phase = phase.isFinite ? min(1, max(0, phase)) : 0
        }
        public init(clip: Clip, sourceFrame: Int) {
            self.init(clip: clip, phase: Double(max(0, sourceFrame)) / Double(max(1, clip.frameCount - 1)))
        }
        /// Preview elapsed time only. Callers own the clock and freeze it to pause.
        /// One-shot playback holds the last frame. Looping is explicitly opt-in;
        /// source clips are not certified seamless loops.
        public init(clip: Clip, previewElapsed: Double, looping: Bool = false) {
            let duration = Double(clip.frameCount - 1) / DuelOriginalRigReview.previewFramesPerSecond
            guard previewElapsed.isFinite, previewElapsed >= 0, duration > 0 else {
                self.init(clip: clip, phase: 0); return
            }
            let elapsed = looping ? previewElapsed.truncatingRemainder(dividingBy: duration) : previewElapsed
            self.init(clip: clip, phase: elapsed / duration)
        }
        /// Use the decoded asset's actual interval: Blender export begins at
        /// 1/30, not zero, and constant channels may have just two keyframes.
        public func assetTime(start: Float, end: Float) -> Float {
            guard start.isFinite, end.isFinite, end >= start else { return 0 }
            return start + (end - start) * Float(phase)
        }
    }
}
