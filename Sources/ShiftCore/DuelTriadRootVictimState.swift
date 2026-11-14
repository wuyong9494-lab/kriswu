import Foundation

/// Recovered H17 lock_1777 victim transitions. The source duration variable
/// ending is a condition, not an immediate animation transition. Sampling of
/// the final End clip and the arena's subsequent get-up are separate policies.
public struct DuelTriadRootVictimState: Equatable, Sendable {
    public enum Motion: String, CaseIterable, Sendable {
        case start, loop, end

        public var clip: String { "h17_root_spike_passive_" + rawValue }
        public var frames: Int {
            switch self { case .start: return 44; case .loop: return 61; case .end: return 48 }
        }
        public var lastSampleTick: Int { 2 * (frames - 1) }
        public var endEventTick: Int { 2 * (frames - 1 - 4) }
        public var sourceSHA256: String {
            switch self {
            case .start: return "69d01bc2d1cc6be69188be006582598bf3551c88db3f7446078fcda63583382c"
            case .loop: return "a3f13059f3eeedd057e14d738894667a77b04279109d1544f0e2b34ad12502ce"
            case .end: return "7d9b8572ae67cd8f344f16478cc50a56e17c0646191c7f2306ff2724453cf5e2"
            }
        }
    }

    public static let configurationSHA256 = DuelTriadStanceState.configurationSHA256
    public static let triggerSHA256 = "d0732e8ca62baf42f6125d24d1c347f9054ae7d0dc9ce163fc0a458b096944c6"
    /// The interval reader subtracts one from the configured positive End;
    /// the native dispatcher ends it only when floor(position) > EndIndex.
    /// Thus IntervalEnd 1/25/45 is tick 2/50/90, whereas IntervalStart 20
    /// (the Floorfall cue in End) is tick 38. These are different clocks.
    public static let loopCheckTicks = [2, 50, 90]

    public let sourceID: UInt64
    public let owner: Int
    public private(set) var motion: Motion = .start
    public private(set) var tick = 0
    public private(set) var durationActive = true
    public private(set) var originXMillimeters: Double
    public private(set) var direction: Int

    init(sourceID: UInt64, owner: Int, originXMillimeters: Double, direction: Int) {
        self.sourceID = sourceID; self.owner = owner
        self.originXMillimeters = originXMillimeters; self.direction = direction
    }

    /// This is an authenticated-catalog capability check, not proof that
    /// arbitrary caller-supplied tracks are original media. Release loading
    /// separately pins the complete catalog and character bytes. Shared victim
    /// motions may belong to the old Liu reference rig without becoming D19.
    public static func matches(profile: DuelWeaponProfile) -> Bool {
        Motion.allCases.allSatisfy { motion in
            guard let clip = profile.clip(named: motion.clip) else { return false }
            return clip.sha256 == motion.sourceSHA256 && clip.frames == motion.frames &&
                clip.ticks == motion.lastSampleTick && clip.tracks.samplesPerSourceFrame == 2 &&
                clip.tracks.pelvis?.count == motion.lastSampleTick + 1
        }
    }

    /// A delayed/stale release from another root must not unlock this one.
    @discardableResult mutating func release(sourceID: UInt64, owner: Int) -> Bool {
        guard self.sourceID == sourceID, self.owner == owner, durationActive else { return false }
        durationActive = false; return true
    }

    struct Advance: Equatable, Sendable {
        let previousMotion: Motion
        let finalTick: Int
        let transitioned: Bool
        let completed: Bool
    }

    /// Exactly one authoritative live tick. Hit-stop never calls this method.
    /// A transition publishes the old boundary sample before new tick zero.
    mutating func advance() -> Advance {
        let previous = motion
        tick += 1
        let reachedEnd = tick == motion.endEventTick
        if motion == .start && reachedEnd || motion == .loop && reachedEnd {
            let final = tick
            motion = durationActive ? .loop : .end; tick = 0
            return .init(previousMotion: previous, finalTick: final, transitioned: true, completed: false)
        }
        if motion == .loop && !durationActive && Self.loopCheckTicks.contains(tick) {
            let final = tick
            motion = .end; tick = 0
            return .init(previousMotion: previous, finalTick: final, transitioned: true, completed: false)
        }
        // lock_1777 has no End→get-up AnimationEnd action. Retain the entire
        // End sample range, then let the arena select its existing get-up.
        return .init(previousMotion: previous, finalTick: min(tick, motion.lastSampleTick),
            transitioned: false, completed: motion == .end && tick > motion.lastSampleTick)
    }

    mutating func align(originXMillimeters: Double, direction: Int) {
        self.originXMillimeters = originXMillimeters; self.direction = direction
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.u64(sourceID); try writer.int(owner); try writer.string(motion.rawValue)
        try writer.int(tick); try writer.bool(durationActive)
        try writer.double(originXMillimeters); try writer.int(direction)
    }
}
