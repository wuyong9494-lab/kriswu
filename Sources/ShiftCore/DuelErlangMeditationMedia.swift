/// Preview-owned playback targets, independent of pose sampling and combat.
/// Renderers can read the desired state repeatedly; any edge consumption
/// must key on transitionID, which stays unique across round resets.
public struct DuelErlangMeditationMedia: Equatable, Sendable {
    public enum Transition: String, Encodable, Sendable { case started, released, interrupted, cancelled }

    public private(set) var loopMediaActive = false
    public var releaseEffectActive: Bool { releaseTicksRemaining > 0 }
    public private(set) var transition: Transition?
    public private(set) var transitionID: UInt64 = 0
    private var releaseTicksRemaining = 0

    /// Offline visual marker lifetime only. No original-source timing claim.
    static let releasePreviewTicks = 10

    public init() {}

    mutating func clearEdge() { transition = nil }

    mutating func advance(holding: Bool, released: Bool, interrupted: Bool, roundFinished: Bool) {
        clearEdge()
        if roundFinished {
            cancel()
        } else if interrupted {
            loopMediaActive = false
            releaseTicksRemaining = 0
            publish(.interrupted)
        } else if released {
            loopMediaActive = false
            releaseTicksRemaining = Self.releasePreviewTicks
            publish(.released)
        } else {
            releaseTicksRemaining = max(0, releaseTicksRemaining - 1)
            if loopMediaActive != holding {
                loopMediaActive = holding
                if holding { publish(.started) }
                else { publish(.cancelled) }
            }
        }
    }

    mutating func cancel() {
        clearEdge()
        let hadMedia = loopMediaActive || releaseEffectActive
        loopMediaActive = false
        releaseTicksRemaining = 0
        if hadMedia { publish(.cancelled) }
    }

    private mutating func publish(_ value: Transition) {
        transitionID &+= 1
        transition = value
    }
}
