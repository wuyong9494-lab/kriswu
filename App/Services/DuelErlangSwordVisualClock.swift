import Foundation

/// A read-only projection of the authoritative model clocks. A source motion
/// change or Idle wrap never creates a new particle-system initialization.
struct DuelErlangSwordVisualClock {
    struct Sample: Equatable { let poseTick: Int; let effectTick: Int }
    static let birthRoles = Set((1...6).map { "erlangSummon_swordBirth\($0)" })
    static let roles = birthRoles.union(["erlangSummon_swordIdle", "erlangSummon_swordRotate", "erlangSummon_sword"])
    static let sourceDurationTicks = 9999 * 60

    static func sample(role: String, liveTick: Int, bornAt: Int, motionTick: Int,
                       hidden: Bool) -> Sample? {
        guard roles.contains(role), liveTick >= 0, bornAt >= 0, bornAt <= liveTick,
              motionTick >= 0, !hidden else { return nil }
        let last = role == "erlangSummon_swordRotate" ? 0 : role == "erlangSummon_sword" ? 70 : 92
        guard motionTick <= last, liveTick - bornAt < sourceDurationTicks else { return nil }
        return .init(poseTick: motionTick, effectTick: liveTick - bornAt)
    }
}

/// Fixed-step observation of the model's real persistent HIDE/SHOW state.
/// Birth/Idle/Rotate/Attack changes do not restart an effect. A witnessed
/// hidden -> visible transition does: source lock1447/t3 attaches on SHOW.
/// This is render state only and cannot create a combat model or source event.
struct DuelErlangSwordEffectClock {
    enum Failure: Error { case source }
    struct Key: Hashable { let owner: Int; let model: UInt64 }
    struct Observation: Equatable {
        let key: Key
        let bornAt: Int
        let role: String
        let motionTick: Int
        let hidden: Bool
    }
    struct State: Equatable {
        let bornAt: Int
        var startedAt: Int
        var hidden: Bool
    }
    struct Particle: Equatable {
        let cycle: Int
        let ageTicks: Int
        var emitting: Bool { ageTicks < 60 }
    }
    static let tailSeconds = 0.33000001311302185
    private(set) var liveTick: Int?
    private(set) var active: [Key: State] = [:]
    private var frame: Int?

    /// Each original system bursts once per second. The exporter preserves two
    /// alternating particles with period120, so a new head never joins the
    /// previous particle's still living world-space tail.
    static func particle(effectTick: Int, phase: Int) -> Particle? {
        guard (0...1).contains(phase), effectTick >= phase * 60 else { return nil }
        let relative = effectTick - phase * 60, age = relative % 120
        guard Double(age) < 60 + tailSeconds * 60 else { return nil }
        return .init(cycle: relative / 120, ageTicks: age)
    }

    mutating func consume(frame currentFrame: Int, liveTick currentTick: Int,
                          fighting: Bool, models: [Observation]) throws -> Set<Key> {
        guard fighting else { reset(); return [] }
        guard currentFrame >= 0, currentTick >= 0, models.count <= 128,
              Set(models.map(\.key)).count == models.count else { throw Failure.source }
        if frame.map({ currentFrame < $0 }) == true || liveTick.map({ currentTick < $0 }) == true { reset() }
        if frame == currentFrame {
            guard liveTick == currentTick else { throw Failure.source }
            return []
        }
        var current: [Key: State] = [:], restarted = Set<Key>()
        for model in models {
            guard (0..<2).contains(model.key.owner), model.key.model > 0,
                  model.bornAt >= 0, model.bornAt <= currentTick,
                  DuelErlangSwordVisualClock.roles.contains(model.role), model.motionTick >= 0,
                  model.motionTick <= (model.role == "erlangSummon_swordRotate" ? 0 :
                    model.role == "erlangSummon_sword" ? 70 : 92) else { throw Failure.source }
            var state: State
            if let old = active[model.key] {
                guard old.bornAt == model.bornAt else { throw Failure.source }
                state = old
                if old.hidden && !model.hidden {
                    state.startedAt = currentTick; restarted.insert(model.key)
                }
                state.hidden = model.hidden
            } else {
                state = .init(bornAt: model.bornAt, startedAt: model.bornAt, hidden: model.hidden)
                restarted.insert(model.key)
            }
            current[model.key] = state
        }
        frame = currentFrame; liveTick = currentTick; active = current
        return restarted
    }

    mutating func reset() {
        frame = nil; liveTick = nil; active.removeAll(keepingCapacity: true)
    }
}
