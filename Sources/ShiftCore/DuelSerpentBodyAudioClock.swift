import Foundation

/// Cosmetic projection of source pose intervals. The fight owns every clock;
/// this consumer only fences delivery and preserves the authenticated marker.
public struct DuelSerpentBodyAudioClock: Sendable {
    public static let palaceStageSHA256 = "185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8"
    public struct Marker: Equatable, Sendable {
        public let id, clip: String
        public let tick, duration: Int
        public let requiresPalaceStone: Bool
        public init(id: String, clip: String, tick: Int, duration: Int, requiresPalaceStone: Bool = false) {
            self.id = id; self.clip = clip; self.tick = tick; self.duration = duration
            self.requiresPalaceStone = requiresPalaceStone
        }
    }
    public struct Cue: Equatable, Sendable {
        public let owner: Int
        public let markerID: String
        public init(owner: Int, markerID: String) { self.owner = owner; self.markerID = markerID }
    }
    private var lastFrame: Int?
    private var consumedSamples: Set<Int> = []
    public init() {}
    public mutating func reset() { self = Self() }

    public mutating func consume(markers: [Marker], samples: [DuelSourceMotionSample],
                                 frame: Int, paused: Bool, owners: Set<Int>,
                                 stageSHA256: String?) -> [Cue] {
        guard !paused, frame >= 0, lastFrame.map({ frame >= $0 }) ?? true else { return [] }
        if lastFrame != frame { lastFrame = frame; consumedSamples.removeAll(keepingCapacity: true) }
        var result: [Cue] = []
        for sample in samples.prefix(256) {
            guard sample.frame == frame, (0..<2).contains(sample.owner), owners.contains(sample.owner),
                  (0..<256).contains(sample.sequence), sample.duration > 0,
                  sample.tick >= 0, sample.tick <= sample.duration,
                  sample.previousTick >= -1, sample.previousTick < sample.tick,
                  consumedSamples.insert(sample.sequence).inserted else { continue }
            // Fence the accepted sample even when its floor route is absent.
            // Installing a stage later cannot replay an old footstep.
            for marker in markers where marker.clip == sample.clip && marker.duration == sample.duration &&
                marker.tick >= 0 && marker.tick <= marker.duration &&
                sample.previousTick < marker.tick && marker.tick <= sample.tick &&
                (!marker.requiresPalaceStone || stageSHA256 == Self.palaceStageSHA256) {
                result.append(.init(owner: sample.owner, markerID: marker.id))
            }
        }
        return result
    }
}
