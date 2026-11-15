import Foundation

/// A presentation-only projection of accepted source pose intervals. It never
/// advances a fight, guesses a cast phase, or changes an audio marker's origin.
struct DuelErlangAudioClock {
    struct Marker: Equatable {
        let category: String
        let clip: String
        let modelRole: String?
        let sourceTick: Int
        let duration: Int
    }
    struct ModelSample {
        let owner: Int
        let id: UInt64
        let role: String
        let age: Int
        let stateStartedAt: Int

        init(owner: Int, id: UInt64, role: String, age: Int, stateStartedAt: Int = 0) {
            self.owner = owner; self.id = id; self.role = role
            self.age = age; self.stateStartedAt = stateStartedAt
        }
    }
    private struct ModelID: Hashable {
        let owner: Int; let id: UInt64; let role: String; let stateStartedAt: Int
        init(_ model: ModelSample) {
            owner = model.owner; id = model.id; role = model.role; stateStartedAt = model.stateStartedAt
        }
    }
    private var lastFrame: Int?
    private var consumedSamples: Set<Int> = []
    private var modelAges: [ModelID: Int] = [:]
    private var owners: Set<Int> = []

    mutating func reset() { self = Self() }

    mutating func consume(markers: [Marker], samples: [DuelSourceMotionSample], models: [ModelSample],
                          frame: Int, fighting: Bool, paused: Bool, owners selected: Set<Int>) -> [String] {
        guard !paused, frame >= 0, lastFrame.map({ frame >= $0 }) ?? true else { return [] }
        let accepted = Set(selected.filter { (0..<2).contains($0) })
        if accepted != owners { modelAges.removeAll(); owners = accepted }
        if lastFrame != frame { lastFrame = frame; consumedSamples.removeAll(keepingCapacity: true) }
        var result: [String] = []
        // A finishing step can retain its actual samples after phase becomes
        // roundBreak. The frame/sequence fence still permits that step once.
        for sample in samples.prefix(256) {
            guard sample.frame == frame, accepted.contains(sample.owner),
                  (0..<256).contains(sample.sequence), sample.duration > 0,
                  sample.tick >= 0, sample.tick <= sample.duration,
                  sample.previousTick >= -1, sample.previousTick < sample.tick,
                  consumedSamples.insert(sample.sequence).inserted else { continue }
            for marker in markers where marker.modelRole == nil && marker.clip == sample.clip &&
                marker.duration == sample.duration && sample.previousTick < marker.sourceTick && marker.sourceTick <= sample.tick {
                result.append(marker.category)
            }
        }
        // Projectiles cannot start new sounds after the authoritative round
        // end. A new round cannot inherit the previous round's model clocks.
        guard fighting else { modelAges.removeAll(keepingCapacity: true); return result }
        // A hovering sword keeps its instance identity across Birth, Idle and
        // Attack. Its actual animation state starts a new source clock; birth
        // age must never replay an appearance cue when that sword attacks.
        let active = models.prefix(64).filter { accepted.contains($0.owner) && $0.age >= 0 && $0.stateStartedAt >= 0 }
        let live = Set(active.map(ModelID.init))
        modelAges = modelAges.filter { live.contains($0.key) }
        for model in active {
            let key = ModelID(model)
            let previous = modelAges[key] ?? -1
            guard model.age > previous else { continue }
            modelAges[key] = model.age
            for marker in markers where marker.modelRole == model.role && model.age <= marker.duration &&
                previous < marker.sourceTick && marker.sourceTick <= model.age {
                result.append(marker.category)
            }
        }
        return result
    }
}
