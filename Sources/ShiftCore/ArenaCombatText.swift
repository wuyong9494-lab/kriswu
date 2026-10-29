import Foundation

/// Presentation-only coalescing. Never used to calculate health or damage.
public struct ArenaCombatText: Sendable {
    public enum Kind: Int, Sendable { case damage, healing }
    public struct Entry: Sendable {
        public let target: Int
        public let kind: Kind
        public var amount: Int
        public let firstTime: Double
    }
    private var entries: [Entry] = []
    public init() {}
    public mutating func add(target: Int, kind: Kind, amount: Int, time: Double) {
        guard amount > 0, time.isFinite else { return }
        if let index = entries.firstIndex(where: { $0.target == target && $0.kind == kind && time - $0.firstTime < 0.12 }) {
            entries[index].amount += amount
        } else if entries.count < 24 {
            entries.append(Entry(target: target, kind: kind, amount: amount, firstTime: time))
        }
    }
    public mutating func drain(at time: Double) -> [Entry] {
        let ready = entries.filter { time - $0.firstTime >= 0.12 }
        entries.removeAll { time - $0.firstTime >= 0.12 }
        return ready
    }
}
