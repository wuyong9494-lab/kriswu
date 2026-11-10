/// Absolute monotonic deadlines for the nearby coordinator's nominal 60 Hz task.
/// This schedules wakes, not simulation ticks. A wake still calls service once;
/// the coordinator keeps authority over watchdogs, cancellation and stepping.
public struct DuelNetworkPulseSchedule: Equatable, Sendable {
    public static let intervalNanoseconds: UInt64 = 16_666_667
    public private(set) var nextDeadline: UInt64
    private var lastObservedTime: UInt64

    public init?(startingAt now: UInt64) {
        let (deadline, overflow) = now.addingReportingOverflow(Self.intervalNanoseconds)
        guard !overflow else { return nil }
        nextDeadline = deadline
        lastObservedTime = now
    }

    /// Recompute the remaining wait rather than sleeping a whole interval after
    /// service work. A late wake may service once, never once per missed deadline.
    /// Invalid clock observations leave the schedule unchanged.
    public mutating func sleepNanoseconds(at now: UInt64) -> UInt64? {
        guard now >= lastObservedTime else { return nil }
        lastObservedTime = now
        return now < nextDeadline ? nextDeadline - now : 0
    }

    /// Called AFTER synchronous service work. Keep the original deadline grid,
    /// skipping all elapsed deadlines in constant time, with no catch-up loop.
    /// The next deadline is strictly in the future even at an exact boundary.
    @discardableResult
    public mutating func advance(afterPulseAt now: UInt64) -> Bool {
        guard now >= lastObservedTime, now >= nextDeadline else { return false }
        let remaining = Self.intervalNanoseconds - (now - nextDeadline) % Self.intervalNanoseconds
        let (deadline, overflow) = now.addingReportingOverflow(remaining)
        guard !overflow else { return false }
        nextDeadline = deadline
        lastObservedTime = now
        return true
    }
}
