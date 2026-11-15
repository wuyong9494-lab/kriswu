/// Renderer-facing pose selection. Authored clip names/counts come from the
/// verified CN asset; one sample per fixture tick and the crossfade are preview
/// choices. This has no right to generate damage, cooldown changes or audio cues.
public struct DuelErlangMeditationPresentation: Equatable, Sendable {
    public enum Status: String, Encodable, Sendable { case inactive, entering, holding, releasing, interrupted }
    public enum Clip: String, Encodable, Sendable {
        case start = "d15_meditation_start"
        case loop = "d15_meditation_loop"
        case end = "d15_meditation_end"

        fileprivate var sampleCount: Int {
            switch self { case .start: 18; case .loop: 73; case .end: 22 }
        }
    }
    public struct Pose: Equatable, Sendable {
        public let clip: Clip
        public let sample: Int
    }
    public struct Blend: Equatable, Encodable, Sendable {
        public let clip: Clip
        public let sample: Int
        /// Fraction of the previous pose, not of the destination.
        public let weight: Double
    }

    public private(set) var animationStatus: Status = .inactive
    public private(set) var pose: Pose?
    public private(set) var blendFrom: Blend?
    private var phaseStart = 0
    private var releaseOrigin: Pose?

    public init() {}

    /// Called once, after all combat contacts are adjudicated for the tick.
    /// A normal end relinquishes pose priority immediately if another action was
    /// accepted. A hit reaction is owned by combat presentation, not by this clip.
    mutating func observe(tick: Int, began: Bool, holding: Bool,
                          ended: Bool, interrupted: Bool, overridePose: Bool) {
        if interrupted {
            self = .init()
            animationStatus = .interrupted
            return
        }
        if overridePose {
            self = .init()
            return
        }
        if began && holding {
            self = .init()
            phaseStart = tick
        }
        if holding {
            let age = max(0, tick - phaseStart)
            if age < Clip.start.sampleCount {
                animationStatus = .entering
                pose = Pose(clip: .start, sample: age)
            } else {
                animationStatus = .holding
                // Loop sample 72 duplicates 0; start sample 17 already matches 0.
                pose = Pose(clip: .loop, sample: (age - Clip.start.sampleCount + 1) % (Clip.loop.sampleCount - 1))
            }
            return
        }
        if ended {
            releaseOrigin = pose
            phaseStart = tick
            animationStatus = .releasing
        }
        if animationStatus == .releasing {
            let age = max(0, tick - phaseStart)
            if age < Clip.end.sampleCount {
                pose = Pose(clip: .end, sample: age)
                // Quick release can exit halfway through the start animation. The
                // source end clip starts upright; keep the last displayed pose
                // briefly to avoid teleporting to the authored exit pose.
                if let origin = releaseOrigin, age < 4 {
                    blendFrom = Blend(clip: origin.clip, sample: origin.sample,
                                      weight: Double(4 - age) / 4)
                } else { blendFrom = nil }
                return
            }
        }
        self = .init()
    }
}
