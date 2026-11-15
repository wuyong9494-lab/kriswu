import Foundation

/// Observation of original model creation is separate from display-frame
/// drawing. This clock never creates a combat model, hit or input command.
struct DuelErlangStompEffectClock {
    enum Failure: Error { case source, capacity }
    struct Key: Hashable { let owner: Int; let model: UInt64 }
    struct Observation: Equatable {
        let key: Key
        let bornAt: Int
    }
    private(set) var liveTick: Int?
    private(set) var active: [Key: Int] = [:]
    private var frame: Int?
    private var seen = Set<Key>()
    static let modelEndTick = 18
    static let lifetimeTicks = 84 // Three original 1.4 s particles at 60 Hz.

    mutating func consume(frame currentFrame: Int, liveTick currentTick: Int,
                          fighting: Bool, models: [Observation]) throws -> [Observation] {
        guard fighting else { reset(); return [] }
        guard currentFrame >= 0, currentTick >= 0, models.count <= 128,
              Set(models.map(\.key)).count == models.count else { throw Failure.source }
        if let frame, currentFrame < frame { reset() }
        if let liveTick, currentTick < liveTick { reset() }
        if frame == currentFrame {
            guard liveTick == currentTick else { throw Failure.source }
            return []
        }
        for model in models {
            guard (0..<2).contains(model.key.owner), model.key.model > 0,
                  model.bornAt >= 0, model.bornAt <= currentTick,
                  currentTick - model.bornAt <= Self.modelEndTick else { throw Failure.source }
        }
        frame = currentFrame; liveTick = currentTick
        active = active.filter { currentTick - $0.value < Self.lifetimeTicks }
        var starts: [Observation] = []
        for model in models where seen.insert(model.key).inserted {
            active[model.key] = model.bornAt; starts.append(model)
        }
        guard seen.count <= 2048, active.count <= 128 else { throw Failure.capacity }
        return starts
    }

    mutating func reset() {
        liveTick = nil; frame = nil
        active.removeAll(keepingCapacity: true); seen.removeAll(keepingCapacity: true)
    }
}
