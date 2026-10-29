import Foundation

/// Bounded voice leases; no framework polling or completion callbacks in the hot path.
public struct ArenaVoiceBudget {
    private struct Lease {
        var effect = ""
        var until: TimeInterval = 0
    }
    private var leases = Array(repeating: Lease(), count: 12)
    private var last: [String: TimeInterval] = [:]
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func reserve(effect: String, limit: Int, critical: Bool,
                                 duration: TimeInterval, now: TimeInterval) -> Int? {
        if let previous = last[effect], now - previous < 0.03 { return nil }
        let active = leases.filter { $0.until > now }
        guard active.count < (critical ? 12 : 8),
              active.filter({ $0.effect == effect }).count < limit,
              let index = leases.firstIndex(where: { $0.until <= now }) else { return nil }
        leases[index] = Lease(effect: effect, until: now + max(duration, 0) + 0.02)
        last[effect] = now
        return index
    }
}
