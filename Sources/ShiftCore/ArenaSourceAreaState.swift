import Foundation

/// Per-target clocks for source areas. World supplies the target IDs currently
/// inside the source radius. A hero entering between Dot ticks can be hit once
/// in that tick window; repeated rendering frames cannot multiply the damage.
public struct ArenaSourceAreaState: Codable, Equatable, Sendable {
    public let definition: ArenaSourceAreaEffect
    public private(set) var elapsed: Double = 0
    private var damageWindows: [Int: Int] = [:]
    private var statusWindows: [Int: Int] = [:]
    private var explosionConsumed = false

    public init(definition: ArenaSourceAreaEffect) { self.definition = definition }
    public var expired: Bool { elapsed + 1e-9 >= max(0.05, definition.duration) }

    public mutating func advance(dt: Double) {
        guard dt.isFinite, dt >= 0, dt <= 60 else { return }
        elapsed = min(max(0.05, definition.duration), elapsed + dt)
    }

    public mutating func damageTargets(_ inside: [Int]) -> [Int] {
        guard !expired, definition.isSupported,
              definition.kind == "Damage" || definition.kind == "Dot" else { return [] }
        let interval = max(0.05, definition.tickInterval ?? 1)
        if definition.delayFirstTick == true && elapsed + 1e-9 < interval { return [] }
        let window = definition.kind == "Damage" ? 0 : Int((elapsed / interval + 1e-8).rounded(.down))
        var selected: [Int] = []
        for target in inside where damageWindows[target] != window {
            selected.append(target)
            damageWindows[target] = window
        }
        return selected
    }

    public mutating func statusTargets(_ inside: [Int]) -> [Int] {
        guard !expired, definition.isSupported, definition.statusEnemy?.isSupported == true else { return [] }
        let interval = max(0.05, definition.statusTickInterval ?? 0.1)
        let window = Int((elapsed / interval + 1e-8).rounded(.down))
        var selected: [Int] = []
        for target in inside where statusWindows[target] != window {
            selected.append(target)
            statusWindows[target] = window
        }
        return selected
    }

    public mutating func takeBulletExplosion() -> ArenaSourceBulletExplosion? {
        guard !expired, definition.isSupported, !explosionConsumed,
              definition.kind == "BulletExplosion", let explosion = definition.bulletExplosion else { return nil }
        explosionConsumed = true
        return explosion
    }
}
