import Foundation

/// Discrete menu navigation actions derived from physical gamepad/keyboard state.
public enum DuelGamepadMenuAction: Equatable, Hashable, Sendable {
    case up, down, left, right
    case confirm      // A / Cross / Return
    case cancel       // B / Circle / Escape
    case secondary    // X / Square (e.g. Practice / Restart)
    case tertiary     // Y / Triangle (e.g. Multiplayer / Ready)
    case shoulderLeft // LB / L1
    case shoulderRight // RB / R1
    case menu         // Menu / Start / Options
}

/// Raw snapshot of menu-relevant physical inputs.
public struct DuelGamepadMenuSnapshot: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var confirm: Bool
    public var cancel: Bool
    public var secondary: Bool
    public var tertiary: Bool
    public var shoulderLeft: Bool
    public var shoulderRight: Bool
    public var menu: Bool

    public init(x: Int = 0, y: Int = 0, confirm: Bool = false, cancel: Bool = false,
                secondary: Bool = false, tertiary: Bool = false,
                shoulderLeft: Bool = false, shoulderRight: Bool = false, menu: Bool = false) {
        self.x = min(1, max(-1, x))
        self.y = min(1, max(-1, y))
        self.confirm = confirm
        self.cancel = cancel
        self.secondary = secondary
        self.tertiary = tertiary
        self.shoulderLeft = shoulderLeft
        self.shoulderRight = shoulderRight
        self.menu = menu
    }

    public static let neutral = DuelGamepadMenuSnapshot()
}

/// Rising-edge detector for gamepad menus. Prevents held sticks/buttons across
/// screen transitions from firing immediately until released to neutral.
public struct DuelGamepadMenuEdgeDetector: Equatable, Sendable {
    private var armed = false
    private var previous = DuelGamepadMenuSnapshot.neutral

    public init() {}

    public mutating func reset() {
        armed = false
        previous = .neutral
    }

    public mutating func update(_ next: DuelGamepadMenuSnapshot) -> [DuelGamepadMenuAction] {
        if !armed {
            // Require neutral before arming so a button held while leaving combat
            // never accidentally activates a menu item on the first sample.
            if next == .neutral {
                armed = true
                previous = .neutral
            }
            return []
        }

        var actions: [DuelGamepadMenuAction] = []
        if next.y > 0 && previous.y <= 0 { actions.append(.up) }
        if next.y < 0 && previous.y >= 0 { actions.append(.down) }
        if next.x < 0 && previous.x >= 0 { actions.append(.left) }
        if next.x > 0 && previous.x <= 0 { actions.append(.right) }
        if next.confirm && !previous.confirm { actions.append(.confirm) }
        if next.cancel && !previous.cancel { actions.append(.cancel) }
        if next.secondary && !previous.secondary { actions.append(.secondary) }
        if next.tertiary && !previous.tertiary { actions.append(.tertiary) }
        if next.shoulderLeft && !previous.shoulderLeft { actions.append(.shoulderLeft) }
        if next.shoulderRight && !previous.shoulderRight { actions.append(.shoulderRight) }
        if next.menu && !previous.menu { actions.append(.menu) }

        previous = next
        return actions
    }
}

/// Pure wrap-around index stepping helper for lobby hero / opponent / difficulty lists.
public enum DuelGamepadListNavigation {
    public static func step<T: Equatable>(in items: [T], current: T, delta: Int) -> T? {
        guard !items.isEmpty else { return nil }
        guard let idx = items.firstIndex(of: current) else { return items.first }
        let count = items.count
        let next = ((idx + delta) % count + count) % count
        return items[next]
    }
}
