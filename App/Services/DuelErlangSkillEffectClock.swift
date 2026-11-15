import Foundation

/// Observes authoritative source model births. It never creates a model or
/// replays an unobserved historical event from a render frame or cast phase.
struct DuelErlangSkillEffectClock {
    enum Failure: Error { case source, capacity }
    struct Key: Hashable { let owner: Int; let model: UInt64 }
    struct Definition: Equatable {
        let role: String
        let modelEndTick: Int
        let lifetimeTicks: Int
    }
    struct Observation: Equatable {
        let key: Key
        let role: String
        let bornAt: Int
    }
    private(set) var liveTick: Int?
    private(set) var active: [Key: Observation] = [:]
    private var frame: Int?
    private var seen = Set<Key>()

    mutating func consume(frame currentFrame: Int, liveTick currentTick: Int,
                          fighting: Bool, models: [Observation], definitions: [Definition]) throws -> [Observation] {
        guard fighting else { reset(); return [] }
        guard currentFrame >= 0, currentTick >= 0, models.count <= 128,
              !definitions.isEmpty, definitions.count <= 8,
              Set(definitions.map(\.role)).count == definitions.count,
              definitions.allSatisfy({ !$0.role.isEmpty && (0...1200).contains($0.modelEndTick) &&
                  (1...1200).contains($0.lifetimeTicks) }),
              Set(models.map(\.key)).count == models.count else { throw Failure.source }
        if let frame, currentFrame < frame { reset() }
        if let liveTick, currentTick < liveTick { reset() }
        if frame == currentFrame {
            guard liveTick == currentTick else { throw Failure.source }
            return []
        }
        let rules = Dictionary(uniqueKeysWithValues: definitions.map { ($0.role, $0) })
        for model in models {
            guard (0..<2).contains(model.key.owner), model.key.model > 0,
                  let rule = rules[model.role], model.bornAt >= 0, model.bornAt <= currentTick,
                  currentTick - model.bornAt <= rule.modelEndTick else { throw Failure.source }
        }
        frame = currentFrame; liveTick = currentTick
        active = active.filter { key, value in
            rules[value.role].map { currentTick - value.bornAt < $0.lifetimeTicks } ?? false
        }
        var starts: [Observation] = []
        for model in models where seen.insert(model.key).inserted {
            // A late first observation has no sampled source attachment at
            // birth. Keep it seen, but do not manufacture a historical burst.
            guard model.bornAt == currentTick else { continue }
            active[model.key] = model; starts.append(model)
        }
        guard seen.count <= 2048, active.count <= 128 else { throw Failure.capacity }
        return starts
    }

    mutating func reset() {
        liveTick = nil; frame = nil
        active.removeAll(keepingCapacity: true); seen.removeAll(keepingCapacity: true)
    }
}
