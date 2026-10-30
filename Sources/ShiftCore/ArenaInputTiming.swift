import Foundation

/// A latest-state channel, not a queue of fixed simulation steps. Uses monotonic
/// wall time so 30/60/120 Hz render callbacks have the same nominal send rate.
public struct ArenaInputCadence: Sendable {
    public static let interval = 1.0 / 30
    private var lastSent: Double?
    public init() {}

    /// Never emits catch-up bursts after a stall. Forced sends are for touch
    /// cancellation/backgrounding, where a reliable zero must leave immediately.
    public mutating func takeSend(at now: Double, force: Bool = false) -> Bool {
        guard now.isFinite else { return false }
        if let lastSent, !force, now - lastSent + 1e-9 < Self.interval { return false }
        lastSent = now
        return true
    }
}

/// Holds the newest received movement until the host simulates it. The ack is
/// deliberately separate: receiving an input does not mean a tick consumed it.
public struct ArenaRemoteMovement: Sendable {
    public static let timeout = 0.25
    public private(set) var receivedSequence = 0
    public private(set) var appliedSequence = 0
    private var direction = V2.zero
    private var receivedAt: Double?
    public init() {}

    @discardableResult
    public mutating func receive(sequence: Int, move: V2, at now: Double) -> Bool {
        guard sequence > receivedSequence, now.isFinite,
              move.x.isFinite, move.y.isFinite else { return false }
        receivedSequence = sequence
        direction = move.clamped(to: 1)
        receivedAt = now
        return true
    }

    public mutating func consume(at now: Double) -> V2 {
        appliedSequence = receivedSequence
        guard let receivedAt, now.isFinite, now >= receivedAt,
              now - receivedAt <= Self.timeout else { return .zero }
        return direction
    }
}
