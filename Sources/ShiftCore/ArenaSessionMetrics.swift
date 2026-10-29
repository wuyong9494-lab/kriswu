import Foundation

/// Whole-session callback intervals, with bounded memory even for a 30-minute run.
/// Percentiles use 1 ms histogram buckets; intervals above 1000 ms share the last bucket.
public struct ArenaSessionMetrics: Sendable {
    public static let slowThreshold = 1.0 / 30 + 0.001
    private var histogram = [Int](repeating: 0, count: 1001)
    public private(set) var count = 0
    public private(set) var duration = 0.0
    public private(set) var maximum = 0.0
    public private(set) var slowCount = 0
    public private(set) var overBudgetCount = 0
    public private(set) var callbackWork = 0.0
    public private(set) var peakCallbackWork = 0.0

    public init() {}

    public mutating func record(interval: Double, work: Double) {
        guard interval.isFinite, interval > 0, work.isFinite, work >= 0 else { return }
        count += 1
        duration += interval
        maximum = max(maximum, interval)
        callbackWork += work
        peakCallbackWork = max(peakCallbackWork, work)
        if interval > Self.slowThreshold { slowCount += 1 }
        if interval > 1.0 / 60 + 0.001 { overBudgetCount += 1 }
        histogram[min(1000, Int(min(interval * 1000, 1000).rounded(.up)))] += 1
    }

    public func percentileMilliseconds(_ fraction: Double) -> Int? {
        guard count > 0, fraction.isFinite else { return nil }
        let target = max(1, Int(ceil(Double(count) * min(max(fraction, 0), 1))))
        var cumulative = 0
        for (bucket, samples) in histogram.enumerated() {
            cumulative += samples
            if cumulative >= target { return bucket }
        }
        return 1000
    }
}
