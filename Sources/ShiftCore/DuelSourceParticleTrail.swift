import Foundation

/// A world-space history for the recovered H17 single-particle trail emitters.
/// Source bone positions enter once per simulation tick; drawing never advances
/// or transforms an existing point. This is independent of combat collision.
public struct DuelSourceParticleTrail: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public let tick: Int
        public let position: DuelWeaponPoint
    }
    public enum Failure: Error { case configuration, sample, capacity }
    public let lifetimeTicks: Double
    public let minimumVertexDistance: Double
    private var anchors: [Point] = []
    private var head: Point?
    private var lastTick = -1
    private static let capacity = 128

    public init(lifetimeSeconds: Double, minimumVertexDistance: Double) throws {
        guard lifetimeSeconds.isFinite, (0.001...1).contains(lifetimeSeconds),
              minimumVertexDistance.isFinite, (0.000001...10).contains(minimumVertexDistance) else {
            throw Failure.configuration
        }
        lifetimeTicks = lifetimeSeconds * Double(DuelGame.ticksPerSecond)
        self.minimumVertexDistance = minimumVertexDistance
    }

    public mutating func sample(tick: Int, worldPosition: DuelWeaponPoint?, emitting: Bool) throws {
        guard tick >= 0 else { throw Failure.sample }
        guard tick > lastTick else { return }
        if emitting {
            guard let position = worldPosition,
                  [position.x, position.y, position.z].allSatisfy({ $0.isFinite && abs($0) < 100_000 }) else {
                throw Failure.sample
            }
        }
        lastTick = tick
        anchors.removeAll { Double(tick - $0.tick) >= lifetimeTicks }
        if let value = head, Double(tick - value.tick) >= lifetimeTicks { head = nil }
        guard emitting else {
            // DieWithParticles=false: retain the last live tip and let every
            // point expire at its own source lifetime after the emitter dies.
            if let value = head, anchors.last != value {
                if anchors.count == Self.capacity { throw Failure.capacity }
                anchors.append(value)
            }
            head = nil
            return
        }
        let position = worldPosition!
        let point = Point(tick: tick, position: position)
        if let anchor = anchors.last {
            let x = position.x - anchor.position.x, y = position.y - anchor.position.y, z = position.z - anchor.position.z
            if x*x + y*y + z*z >= minimumVertexDistance * minimumVertexDistance {
                if anchors.count == Self.capacity { throw Failure.capacity }
                anchors.append(point)
            }
        } else { anchors.append(point) }
        head = point
    }

    public func points(at tick: Int) -> [Point] {
        var result = anchors.filter { $0.tick <= tick && Double(tick - $0.tick) < lifetimeTicks }
        if let head, head.tick <= tick, Double(tick - head.tick) < lifetimeTicks,
           let last = result.last,
           last.position != head.position { result.append(head) }
        return result
    }
}
