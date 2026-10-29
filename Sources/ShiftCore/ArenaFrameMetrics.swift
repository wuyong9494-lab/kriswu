import Foundation

/// Display-link cadence and main-thread update time, not GPU render time.
/// Fixed-size rolling window: no growing history or per-frame sorting.
public struct ArenaFrameMetrics: Sendable {
    public struct Report: Equatable, Sendable {
        public let fps: Double
        public let p95Milliseconds: Double
        public let slowFrames: Int
        public let samples: Int
        public let simulationMilliseconds: Double
        public let sceneMilliseconds: Double
    }

    private struct Frame: Sendable {
        var interval = 0.0
        var simulation = 0.0
        var scene = 0.0
    }
    private var frames = [Frame](repeating: Frame(), count: 120)
    private var cursor = 0
    private var count = 0

    public init() {}

    public mutating func reset() { cursor = 0; count = 0 }

    public mutating func record(interval: Double, simulation: Double, scene: Double) {
        guard interval.isFinite, interval > 0, simulation.isFinite, simulation >= 0,
              scene.isFinite, scene >= 0 else { return }
        frames[cursor] = Frame(interval: interval, simulation: simulation, scene: scene)
        cursor = (cursor + 1) % frames.count
        count = min(count + 1, frames.count)
    }

    /// Call at most once per second, outside the simulation loop.
    public func report() -> Report? {
        guard count > 0 else { return nil }
        let sample = frames.prefix(count)
        let intervals = sample.map(\.interval).sorted()
        let total = intervals.reduce(0, +)
        let p95 = intervals[max(0, Int(ceil(Double(count) * 0.95)) - 1)]
        return Report(fps: Double(count) / total, p95Milliseconds: p95 * 1000,
                      slowFrames: intervals.filter { $0 > 1.0 / 30 + 0.001 }.count,
                      samples: count,
                      simulationMilliseconds: sample.reduce(0) { $0 + $1.simulation } * 1000 / Double(count),
                      sceneMilliseconds: sample.reduce(0) { $0 + $1.scene } * 1000 / Double(count))
    }
}
