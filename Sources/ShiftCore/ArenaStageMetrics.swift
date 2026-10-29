import Foundation

/// Per-operation CPU measurements. Stages may nest; never sum their totals.
/// Constant storage retains cold-start peaks for the entire recording session.
public struct ArenaStageMetrics: Sendable {
    public enum Stage: Int, CaseIterable, Sendable {
        case modelLoad, simulation, ai, animation, sceneUpdate, sceneBuild
        case fighterPhysics, projectilePhysics, actorNodes, projectileNodes, events, textRaster, floaterCreate, audio, audioLoad, hud
    }
    public struct Sample: Equatable, Sendable {
        public fileprivate(set) var count = 0
        public fileprivate(set) var totalSeconds = 0.0
        public fileprivate(set) var peakSeconds = 0.0
        public var meanMilliseconds: Double { count == 0 ? 0 : totalSeconds * 1000 / Double(count) }
        public var peakMilliseconds: Double { peakSeconds * 1000 }
    }
    private var samples = Array(repeating: Sample(), count: Stage.allCases.count)
    public init() {}
    public mutating func record(_ stage: Stage, seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        samples[stage.rawValue].count += 1
        samples[stage.rawValue].totalSeconds += seconds
        samples[stage.rawValue].peakSeconds = max(samples[stage.rawValue].peakSeconds, seconds)
    }
    public subscript(_ stage: Stage) -> Sample { samples[stage.rawValue] }
    public mutating func reset() { self = Self() }
}
