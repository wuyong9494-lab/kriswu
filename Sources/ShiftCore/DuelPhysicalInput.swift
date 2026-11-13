import Foundation

/// Source-aware physical state. Opposing directions neutralize (SOCD); button
/// ownership is a union, so releasing a pad cannot release a finger's attack.
public struct DuelPhysicalInput: Equatable, Sendable {
    public struct State: Equatable, Sendable {
        public var x: Int
        public var y: Int
        public var actions: Set<DuelWeaponInput.Action>
        public var guardHeld: Bool
        public init(x: Int = 0, y: Int = 0,
                    actions: Set<DuelWeaponInput.Action> = [], guardHeld: Bool = false) {
            self.x = min(1, max(-1, x)); self.y = min(1, max(-1, y))
            self.actions = actions; self.guardHeld = guardHeld
        }
        public static let neutral = State()
    }
    private var sources: [String: State] = [:]
    public init() {}
    public subscript(source: String) -> State { sources[source] ?? .neutral }
    public var combined: State {
        let values = Array(sources.values)
        func axis(_ key: KeyPath<State, Int>) -> Int {
            let negative = values.contains { $0[keyPath: key] < 0 }
            let positive = values.contains { $0[keyPath: key] > 0 }
            return (positive ? 1 : 0) - (negative ? 1 : 0)
        }
        return State(x: axis(\.x), y: axis(\.y),
                     actions: values.reduce(into: []) { $0.formUnion($1.actions) },
                     guardHeld: values.contains { $0.guardHeld })
    }
    public mutating func set(_ state: State, source: String) { sources[source] = state }
    public mutating func reset() { sources.removeAll() }
    public static func digitalAxis(_ value: Float, deadZone: Float = 0.25) -> Int {
        guard value.isFinite else { return 0 }
        return value > deadZone ? 1 : value < -deadZone ? -1 : 0
    }
}
