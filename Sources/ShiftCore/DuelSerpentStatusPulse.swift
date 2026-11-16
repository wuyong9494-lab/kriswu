import Foundation

/// Bounded translation of native status methods 39053, 37018 and 37019.
/// Values and clock arithmetic are Float32, as in the original ARM64 methods.
/// The caller supplies the accepted source update phase; this value does not
/// invent a timer, execute an event queue, or advance during a paused frame.
struct DuelSerpentStatusPulse: Equatable, Sendable {
    private(set) var rate: Float = 0
    private(set) var duration: Float = 0
    private(set) var interval: Float = 10
    private(set) var createdAt: Float = 0
    private(set) var accumulated: Float = 0
    private(set) var active = false

    init() {}
    init(rate: Float, duration: Float, createdAt: Float, interval: Int = 0) {
        self.rate = rate; self.duration = duration; self.createdAt = createdAt
        self.interval = Float(max(10, interval)); active = true
    }

    /// Creation and replacement emit nothing and start with zero accumulated
    /// time. Explicit removal discards that time by replacing this value.
    /// An expiry emits the remaining fraction only if this update did not
    /// already emit an interval pulse. Native code subtracts one interval,
    /// even when a caller supplies a delta larger than that interval.
    mutating func advance(now: Float, delta: Float = 1) -> Float? {
        guard active else { return nil }
        accumulated += delta
        let intervalDue = accumulated >= interval
        var pulse: Float?
        if intervalDue {
            pulse = rate * accumulated
            accumulated -= interval
        }
        if duration >= 0 && createdAt + duration <= now {
            if !intervalDue { pulse = rate * accumulated }
            active = false
        }
        return pulse
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.u32(rate.bitPattern); try writer.u32(duration.bitPattern)
        try writer.u32(interval.bitPattern); try writer.u32(createdAt.bitPattern)
        try writer.u32(accumulated.bitPattern); try writer.bool(active)
    }
}
