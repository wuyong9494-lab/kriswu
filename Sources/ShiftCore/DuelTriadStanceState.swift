import Foundation

/// The recovered H17 host stance sequence. These are source animation facts;
/// when this arena emits RoundStart / opens combat / closes a match remains an
/// explicit application lifecycle. In particular the original PLAYER versus
/// NOT_PLAYER lock selection is unresolved, so no local/network index is
/// treated as evidence for the original 20-tick opponent-start timer.
public struct DuelTriadStanceState: Equatable, Sendable {
    public enum Purpose: String, Sendable {
        case firstIntro, roundIntro, roundVictory, finalVictory
        public var isIntro: Bool { self == .firstIntro || self == .roundIntro }
    }

    public enum Motion: String, CaseIterable, Sendable {
        case firstBirth, firstIntro, roundBirth, roundIntro, startIdle, roundWin, win, winIdle

        public var clip: String {
            switch self {
            case .firstBirth: return "h17_fight_start_stance_birth"
            case .firstIntro: return "h17_fight_start_stance"
            case .roundBirth: return "h17_round_start_stance_birth"
            case .roundIntro: return "h17_round_start_stance"
            case .startIdle: return "h17_start_stance_idle"
            case .roundWin: return "h17_stance_round_win"
            case .win: return "h17_stance_win"
            case .winIdle: return "h17_stance_win_idle"
            }
        }
        public var frames: Int {
            switch self {
            case .firstBirth: return 31
            case .firstIntro: return 201
            case .roundBirth: return 48
            case .roundIntro: return 55
            case .startIdle: return 105
            case .roundWin: return 104
            case .win: return 162
            case .winIdle: return 41
            }
        }
        /// Sampling always retains the entire original clip. AnimationEnd is
        /// a separate source event and must not shrink pose.duration.
        public var lastSampleTick: Int { (frames - 1) * 2 }
        public var isBirth: Bool { self == .firstBirth || self == .roundBirth }
        public var endEventTick: Int? { isBirth ? nil : (frames - 1 - 4) * 2 }
        public var sourceSHA256: String {
            switch self {
            case .firstBirth: return "02b376b06eebf6566335c3c9631875a81fd639e5040104f96da92f247befb929"
            case .firstIntro: return "65d5f450ae7d4b912c594cb95627f27969c2cd4924fddca8c3bdfd447f26be0a"
            case .roundBirth: return "f341942b0474ffc71185baf5ebce8f60039b4bc570114fdaffb30d7164916147"
            case .roundIntro: return "394515f6016f90dec58c0166e92ca26ea2051f8657abb1913c61da04a79c5b0a"
            case .startIdle: return "63a2d1640be379d287311e6afe9d5a1dffc11e79d0d5cc41cd4484288a86886d"
            case .roundWin: return "e0942bada319c9f043e2f0f5ea90902e6ad9e50783d91139f0aca98e0c6e04ef"
            case .win: return "f4ca38a84dc50549ba1f5aa8c96269526feb09d037773d7c64933591092e531e"
            case .winIdle: return "36bb49e502eaf9ad3cb7fe07de8c1ecf0fbafd031c019f228a981dba91917ea6"
            }
        }
        /// Original MoveAlign axes contain X only. The actor-space conversion
        /// is the same explicit 0.92 presentation scale as its authored tracks.
        var alignToFoot: Bool { self == .roundBirth || self == .roundIntro || self == .roundWin || self == .win || self == .winIdle }
        var sourceShiftX: Int { self == .firstBirth ? -100 : self == .roundBirth ? -80 : 0 }
        var setsDirectionToEnemy: Bool { self == .roundIntro || self == .startIdle || self == .roundWin || self == .win }
    }

    public static let configurationSHA256 = "64bd77afa0edacdc7b672047222fb4261771f08b835367bc3aeeb5b02e668f5a"
    public static let runtimeConfigurationSHA256 = "02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a"
    public static let evidence = [
        "user-ipa-1.46.1/config-1.46.0.16.16733-prod/settings_sets_heralds records 88...96",
        "H17 locks 1797...1802: ModelCreated birth; RoundStart intro; AnimationEnd start idle",
        "H17 lock 1796 t0/t1/t8: round/final victory and AnimationEnd win idle",
        "native 16534/16537 -> 39549 -> 39732: MoveAlign rotation/index0 and shift/index3; 39421 direction sign"
    ]

    public let purpose: Purpose
    public private(set) var motion: Motion
    public private(set) var tick: Int = 0
    public private(set) var originXMillimeters: Double
    public private(set) var direction: Int

    init(round: Int, originXMillimeters: Double, direction: Int) {
        purpose = round <= 1 ? .firstIntro : .roundIntro
        motion = round <= 1 ? .firstBirth : .roundBirth
        self.originXMillimeters = originXMillimeters; self.direction = direction
    }
    init(finalVictory: Bool, originXMillimeters: Double, direction: Int) {
        purpose = finalVictory ? .finalVictory : .roundVictory
        motion = finalVictory ? .win : .roundWin
        self.originXMillimeters = originXMillimeters; self.direction = direction
    }

    /// Missing/other source motions cannot acquire an H17 intro by name alone.
    /// Old or small synthetic catalogs retain their existing arena lifecycle.
    static func accepts(_ profile: DuelWeaponProfile) -> Bool {
        guard profile.isTriad,
              profile.triadRules?.runtime?.configurationSHA256 == runtimeConfigurationSHA256 else { return false }
        return Motion.allCases.allSatisfy { motion in
            guard let clip = profile.clip(named: motion.clip) else { return false }
            return clip.frames == motion.frames && clip.ticks == motion.lastSampleTick &&
                clip.sha256 == motion.sourceSHA256 && clip.tracks.pelvis != nil
        }
    }

    /// Birth remains a loop until an actual lifecycle event. The arena calls
    /// this on its first authoritative tick rather than waiting for the loop.
    @discardableResult mutating func beginRound() -> Bool {
        guard motion.isBirth else { return false }
        motion = purpose == .firstIntro ? .firstIntro : .roundIntro; tick = 0
        return true
    }

    struct Transition: Equatable, Sendable {
        let from: Motion
        let finalTick: Int
    }
    /// On a transition, the caller publishes the old end sample before the new
    /// tick-zero sample, retaining marker order even on the shared source tick.
    @discardableResult mutating func advance() -> Transition? {
        let old = motion
        tick += 1
        if motion.isBirth {
            guard tick > motion.lastSampleTick else { return nil }
            tick = 0; return .init(from: old, finalTick: old.lastSampleTick)
        }
        guard tick >= (motion.endEventTick ?? Int.max) else { return nil }
        let finalTick = motion.endEventTick!
        switch motion {
        case .firstIntro, .roundIntro, .startIdle: motion = .startIdle
        case .roundWin, .win, .winIdle: motion = .winIdle
        case .firstBirth, .roundBirth: break
        }
        tick = 0; return .init(from: old, finalTick: finalTick)
    }
    mutating func align(originXMillimeters: Double, direction: Int) {
        self.originXMillimeters = originXMillimeters; self.direction = direction
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string(purpose.rawValue); try writer.string(motion.rawValue)
        try writer.int(tick); try writer.double(originXMillimeters); try writer.int(direction)
    }
}
