import Foundation

extension DuelTriadRules {
    public enum SummonStage: String, Codable, Sendable { case primary, ninjatoFinal, earthquake, riftWave }
    public enum SoulAnimation: String, Codable, Sendable {
        case ninjatoActiveStart, ninjatoActiveEnd
        public var role: String { "triadSummon_" + rawValue }
        public var sourceAnimation: String {
            self == .ninjatoActiveStart ? "H17_Spirit_Herald_Ninjato_Active_Start" : "H17_Spirit_Herald_Ninjato_Active_End"
        }
        public var sourceFileName: String {
            self == .ninjatoActiveStart ? "w_ninjato/s_ninjato_slash_1_active.bin" : "w_ninjato/s_ninjato_slash_2.bin"
        }
        public var sourceFrameCount: Int { self == .ninjatoActiveStart ? 30 : 21 }
        public var lastSampleTick: Int { 2 * (sourceFrameCount - 1) }
        public var endEventTick: Int { 2 * (sourceFrameCount - 1 - 4) }
    }
    /// Distinct production models/moves. Appearance identity is independent
    /// of the owner's animation and of any projectile released by this model.
    public enum SummonMove: String, Codable, CaseIterable, Sendable {
        case legionSword, heraldDash, dynastyBow, legionDefender
        case rainCloseFront, rainCloseBack, rainMediumFront, rainMediumBack, rainFarFront, rainFarBack
        case legionHammer, entangledBow
        case danceNinjato, danceWhirl, danceBlast, danceThud, danceRift1, danceRift2

        public var soul: Soul {
            switch self {
            case .heraldDash, .danceNinjato, .danceBlast: return .herald
            case .legionSword, .legionDefender, .legionHammer, .danceThud, .danceRift1, .danceRift2: return .legionary
            default: return .dynast
            }
        }
        public var ability: Ability {
            switch soul { case .legionary: return .legionary; case .herald: return .herald; case .dynast: return .dynast }
        }
        public var role: String {
            switch self {
            case .legionSword: return "triadLegionary"
            case .heraldDash: return "triadHerald"
            case .dynastyBow: return "triadDynast"
            default: return "triadSummon_" + rawValue
            }
        }
        public var modelName: String {
            switch self {
            case .legionSword, .danceRift1, .danceRift2: return "mgc__h17_spirit_legion_sword"
            case .heraldDash, .danceBlast: return "mgc__h17_spirit_heralds_naginata"
            case .dynastyBow, .rainMediumFront, .rainFarBack: return "mgc__h17_spirit_dynasty2"
            case .rainCloseBack, .rainMediumBack, .entangledBow: return "mgc__h17_spirit_dynasty1"
            case .rainCloseFront, .rainFarFront, .danceWhirl: return "mgc__h17_spirit_dynasty3"
            case .legionDefender: return "mgc__h17_spirit_legion_giant_sword"
            case .legionHammer, .danceThud: return "mgc__h17_spirit_legion_hammer"
            case .danceNinjato: return "mgc__h17_spirit_heralds_ninjato"
            }
        }
        public var sourceAnimation: String {
            switch self {
            case .legionSword: return "H17_Spirit_Legion_Twohanded_Sword_Heavy_Slash"
            case .heraldDash: return "H17_Spirit_Herald_Shadow_Dash"
            case .dynastyBow: return "H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow"
            case .legionDefender: return "H17_Spirit_Legion_Block"
            case .rainCloseFront: return "H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Close"
            case .rainCloseBack: return "H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Close_Back"
            case .rainMediumFront: return "H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Medium"
            case .rainMediumBack: return "H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Medium_Back"
            case .rainFarFront, .entangledBow: return "H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Long"
            case .rainFarBack: return "H17_Spirit_Dynasty_Shadow_Ranged_Agile_Bow_Long_Back"
            case .legionHammer: return "H17_Spirit_Legion_Hammer"
            case .danceNinjato: return "H17_Spirit_Herald_Ninjato_Slash_Miss"
            case .danceWhirl: return "H17_Spirit_Dynasty_Helmet"
            case .danceBlast: return "H17_Spirit_Precise_Armor"
            case .danceThud: return "H17_Spirit_Thud"
            case .danceRift1: return "H17_Spirit_Rift_1"
            case .danceRift2: return "H17_Spirit_Rift_2"
            }
        }
        public var sourceFileName: String {
            switch self {
            case .legionSword: return "w_twohanded_sword/twohanded_sword_heavy_slash.bin"
            case .heraldDash: return "s_prc_universal/p_shadow_dash.bin"
            case .legionDefender: return "w_giant_sword/b_giant_sword_mid_low.bin"
            case .legionHammer: return "w_twohanded_hammer/twohanded_hammer_heavy_slash.bin"
            case .danceNinjato: return "w_ninjato/s_ninjato_slash_1.bin"
            case .danceWhirl: return "s_agl_universal/s_agl_helm.bin"
            case .danceBlast: return "s_prc_universal/s_prc_arm.bin"
            case .danceThud: return "s_str_universal/s_str_arm_shadow_jump.bin"
            case .danceRift1, .danceRift2: return "w_twohanded_sword/shadow_twohanded_heavy_slash.bin"
            default: return "ranged/agl_bow/s_rng_agl_bow.bin"
            }
        }
        public enum Anchor: String, Codable, Sendable { case owner, opponent }
        public var anchor: Anchor {
            switch self {
            case .legionSword, .heraldDash, .dynastyBow, .legionDefender: return .owner
            default: return .opponent
            }
        }
        /// Original Align offset, in source units. Conversion to the arena's
        /// units belongs to its source-model scale, not guessed millimeters.
        public var offsetXSourceUnits: Int {
            switch self {
            case .legionSword, .dynastyBow, .rainCloseFront: return -150
            case .heraldDash: return 150
            case .legionDefender: return 40
            case .rainCloseBack: return -180
            case .rainMediumFront: return -250
            case .rainMediumBack: return -280
            case .rainFarFront, .entangledBow: return -350
            case .rainFarBack: return -380
            case .legionHammer: return -330
            case .danceNinjato: return 200
            case .danceBlast: return 0
            case .danceWhirl, .danceThud, .danceRift1, .danceRift2: return -200
            }
        }
        public var offsetZSourceUnits: Int { self == .legionDefender ? -15 : 0 }
        public var reverseFacing: Bool {
            [.rainCloseBack, .rainMediumBack, .rainFarBack, .danceRift2].contains(self)
        }
        /// Align explicitly selects X only. It does not copy the parent's
        /// animated pelvis Y; CreateModel's model defaults supply that axis.
        public var inheritsAnchorHeight: Bool { false }
        public var sourceFrameCount: Int {
            switch self {
            case .legionSword: return 65
            case .heraldDash: return 43
            case .legionDefender: return 31
            case .legionHammer: return 84
            case .danceNinjato: return 26
            case .danceWhirl: return 52
            case .danceBlast: return 72
            case .danceThud: return 49
            case .danceRift1, .danceRift2: return 71
            default: return 34
            }
        }
        public var lastSampleTick: Int { 2 * (sourceFrameCount - 1) }
        public var endEventTick: Int { 2 * (sourceFrameCount - 1 - 4) }
    }
}

extension DuelTriadState {
    public struct SoulAppearance: Equatable, Sendable {
        public let summonID: UInt64
        public let origin: Origin
        public let move: DuelTriadRules.SummonMove
        public var soul: Soul { move.soul }
        public var role: String { move.role }
        public var anchor: DuelTriadRules.SummonMove.Anchor { move.anchor }
        public var offsetXSourceUnits: Int { move.offsetXSourceUnits }
        public var offsetZSourceUnits: Int { move.offsetZSourceUnits }
        public var reverseFacing: Bool { move.reverseFacing }
        public var inheritsAnchorHeight: Bool { move.inheritsAnchorHeight }
        public var lifetimeTicks: Int { move.endEventTick + 1 }

        func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
            try writer.u64(summonID); try writer.string(origin.rawValue); try writer.string(move.rawValue)
        }
    }
}
