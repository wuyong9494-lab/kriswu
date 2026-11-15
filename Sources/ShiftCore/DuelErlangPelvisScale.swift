import Foundation

/// Exact settings_sets_dynasty TweenScale intervals. Source frames are not
/// audio markers: the native interval constructor subtracts one from Start.
public enum DuelErlangPelvisScaleMotion: String, CaseIterable, Sendable {
    case stance, transform2, transform4, transform4Mirrored, transformOut

    public static let configurationSHA256 = "3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701"
    public static let enlargedScale = Float(bitPattern: 0x3f8f5c29)
    public var role: String {
        switch self {
        case .stance: return "erlangAvatarStance"
        case .transform2: return "erlangTransform2Start"
        case .transform4: return "erlangTransform"
        case .transform4Mirrored: return "erlangTransformMirror"
        case .transformOut: return "erlangTransformOut"
        }
    }
    public var record: Int {
        switch self { case .stance: return 90; case .transform2: return 97
        case .transform4: return 107; case .transform4Mirrored: return 108; case .transformOut: return 133 }
    }
    public var startTick: Int {
        switch self { case .stance, .transformOut: return 0; case .transform2: return 18
        case .transform4, .transform4Mirrored: return 70 }
    }
    public var floorEventTick: Int { self == .stance ? 2 : self == .transformOut ? 0 : 48 }
    public var inFrames: Int { self == .transformOut ? 0 : self == .transform2 ? 20 : 10 }
    public var outFrames: Int { self == .transformOut ? 1 : 5 }
    public var startScale: Float { self == .transformOut ? Self.enlargedScale : 1 }
    public var targetScale: Float { self == .transformOut ? 1 : Self.enlargedScale }
    public var frames: Int {
        switch self { case .stance: return 44; case .transform2: return 33
        case .transform4, .transform4Mirrored: return 85; case .transformOut: return 1 }
    }
    public var endTick: Int { self == .transformOut ? 0 : (frames - 1 - 4) * 2 }
    public var sourceSHA256: String {
        switch self {
        case .stance: return "877a16cf40b951de58222a371933bbca43009561e3abe6b467893b2a7eeed251"
        case .transform2: return "bfecc0eeebee01936956c2bf751f365987a512510305f44cf0f91113f6026869"
        case .transform4: return "8f4fc294ffa9f181d0d3abdc1eebeb98d0d40bd5fbcfa6bd3f2547c42a98ff8e"
        case .transform4Mirrored: return "f6ff2a80dfa1859f0dff82c161345907f89918d80139a1e935eaf85b79332236"
        case .transformOut: return DuelErlangTransformOutMotion.sourceSHA256
        }
    }
    public var bundle: String {
        switch self {
        case .transform2: return "9893dca6e10355eb9c3c79d1613f08b1.bin"
        case .transformOut: return DuelErlangTransformOutMotion.sourceBundle
        default: return "2a784bc550bc06541a38a4c1c53b69f3.bin"
        }
    }
    public static func binding(clip: DuelWeaponClip, profile: DuelWeaponProfile) -> Self? {
        guard profile.isErlang else { return nil }
        return allCases.first {
            profile.roles[$0.role] == clip.name && clip.sha256 == $0.sourceSHA256 &&
                clip.bundle == $0.bundle && clip.frames == $0.frames &&
                clip.playbackTicks == ($0.frames - 1) * 2 && clip.sourceEndEventTick == $0.endTick &&
                clip.tracks.pelvis?.count == ($0.frames - 1) * 2 + 1
        }
    }
}

/// The bone value survives animation replacement. It is neither a form flag
/// nor a display interpolation. Native 38983 writes BEFORE advancing elapsed;
/// 38988(false) and replacement cleanup are separate operations.
public struct DuelErlangPelvisScaleState: Equatable, Sendable {
    public struct Tween: Equatable, Sendable {
        public let start: Float
        public let target: Float
        public let duration: Float
        public let outFrames: Int
        public let inOnly: Bool
        public var elapsed: Float = 0
    }
    public private(set) var scale: Float = 1
    /// SetModelFloorOffset stores source centimetres on the actor. It changes
    /// the next pelvis pose sample, and is not scaled by TweenScale itself.
    public private(set) var floorOffsetCentimeters = 0
    /// Native LocationScene queues the external lock action until after all
    /// actors and collisions. Even replacement cleanup cannot change the
    /// already sampled new pose in that same simulation step.
    public private(set) var pendingFloorOffsetCentimeters: Int?
    public private(set) var floorIntervalStarted = false
    public private(set) var floorIntervalEnded = false
    public private(set) var motion: DuelErlangPelvisScaleMotion?
    public private(set) var intervalStarted = false
    public private(set) var intervalEnded = false
    public private(set) var tween: Tween?

    public init() {}

    /// One real animation step, before replacement/interval dispatch. The
    /// caller supplies the active animation's playback stride, not export FPS.
    public mutating func advance(stride: Float) {
        guard stride.isFinite, stride > 0, var value = tween else { return }
        if value.elapsed <= value.duration {
            let t: Float = value.duration == 0 ? 1 : min(1, max(0, value.elapsed / value.duration))
            scale = value.start + (value.target - value.start) * t
        }
        value.elapsed += 1 / stride
        if value.inOnly && value.elapsed >= value.duration { tween = nil }
        else { tween = value }
    }

    /// This arena uses an explicit replacement: first close the old interval,
    /// then run cleanup. The native pending-change branch which skips interval
    /// end is available separately, and is not silently treated as equivalent.
    public mutating func replaceMotion(_ next: DuelErlangPelvisScaleMotion?, closeIntervalFirst: Bool = true) {
        if closeIntervalFirst { endInterval(); endFloorInterval() }
        finish(force: true)
        motion = next; intervalStarted = false; intervalEnded = false
        floorIntervalStarted = false; floorIntervalEnded = false
    }

    public mutating func sample(tick: Int) {
        guard let motion else { return }
        // SelfEnd only emits AnimationEnd. Null TweenScale.End remains open
        // until the actual last source frame is exceeded or a replacement
        // closes it. Native 39182 tests position > last, including one-frame
        // Out: its first pose at zero precedes interval Start and End.
        if tick > (motion.frames - 1) * 2 {
            endInterval(); endFloorInterval(); return
        }
        // Native 39191 ends active intervals whose EndIndex < floor(position)
        // before starting new ones. Start == End therefore spans one source
        // frame (two simulation ticks), not one simulation tick.
        if floorIntervalStarted && tick >= motion.floorEventTick + 2 { endFloorInterval() }
        if !floorIntervalStarted && tick >= motion.floorEventTick && tick < motion.floorEventTick + 2 {
            floorIntervalStarted = true
            // lock1432/t25; this arena is not the BossHimmelstein branch.
            // The Out interval's Start is deliberately not its reset event.
            if motion != .transformOut { pendingFloorOffsetCentimeters = 14 }
        }
        if !intervalStarted && tick >= motion.startTick {
            finish(force: false)
            tween = .init(start: motion.startScale, target: motion.targetScale,
                duration: Float(motion.inFrames), outFrames: motion.outFrames, inOnly: false)
            intervalStarted = true
        }
    }

    public mutating func endInterval() {
        guard intervalStarted && !intervalEnded else { return }
        intervalEnded = true; finish(force: false)
    }

    private mutating func endFloorInterval() {
        guard floorIntervalStarted && !floorIntervalEnded else { return }
        floorIntervalEnded = true
        // lock1454/t63 listens to the actual Out IntervalEnd, including the
        // zero-frame animation's close-all path, not its AnimationStart.
        if motion == .transformOut { pendingFloorOffsetCentimeters = 0 }
    }

    public mutating func flushFloorOffsetEvents() {
        guard let value = pendingFloorOffsetCentimeters else { return }
        floorOffsetCentimeters = value
        pendingFloorOffsetCentimeters = nil
    }

    private mutating func finish(force: Bool) {
        guard let value = tween else { return }
        if value.outFrames > 0 {
            tween = .init(start: value.target, target: value.start,
                duration: force ? 0 : Float(value.outFrames), outFrames: 0, inOnly: true)
        } else if value.inOnly {
            tween = nil
        }
        // All five authenticated intervals have nonzero OutFrames. The
        // native out=0/non-InOnly actor-root fallback is outside this scope.
    }

    public static func transform(_ point: DuelWeaponPoint, about pelvis: DuelWeaponPoint, scale: Float) -> DuelWeaponPoint {
        guard scale != 1 else { return point }
        let s = Double(scale)
        return .init(x: pelvis.x + (point.x - pelvis.x) * s,
                     y: pelvis.y + (point.y - pelvis.y) * s,
                     z: pelvis.z + (point.z - pelvis.z) * s)
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.double(Double(scale))
        try writer.int(floorOffsetCentimeters)
        try writer.optional(pendingFloorOffsetCentimeters) { try $0.int($1) }
        try writer.bool(floorIntervalStarted); try writer.bool(floorIntervalEnded)
        try writer.optional(motion) { try $0.string($1.rawValue) }
        try writer.bool(intervalStarted); try writer.bool(intervalEnded)
        try writer.optional(tween) { writer, value in
            try writer.double(Double(value.start)); try writer.double(Double(value.target))
            try writer.double(Double(value.duration)); try writer.int(value.outFrames)
            try writer.bool(value.inOnly); try writer.double(Double(value.elapsed))
        }
    }
}
