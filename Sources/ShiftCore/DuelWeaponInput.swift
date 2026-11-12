import Foundation

/// A physical-input adapter shared by the original four-button control layout.
/// Commands contain no faction, animation, damage, or laboratory skill mapping;
/// the selected fighter resolves them against its own equipped weapon profile.
///
/// The 18-tick neutral weapon hold and one-tick Up chord grace are explicit app
/// settings. They are not constants recovered from the original game's code.
public struct DuelWeaponInput: Equatable, Sendable {
    public enum Action: String, CaseIterable, Sendable { case weapon, kick, ranged, shadow }
    public static let longPressTicks = 18
    public static let jumpChordGraceTicks = 1
    // Neutral defense must not engage on the same tick as an attack release.
    public static let guardRecoveryTicks = 8
    public private(set) var x = 0
    public private(set) var y = 0

    private struct Press: Equatable, Sendable {
        var ticks = 0
        let order: UInt64
        var resolved = false
    }
    private struct Intent: Equatable, Sendable {
        let action: Action
        let x: Int
        let y: Int
        var heavy = false
    }
    private var presses: [Action: Press] = [:]
    private var nextPressOrder: UInt64 = 0
    private var queued: Intent?
    private var pendingJumpTicks: Int?
    private var guardRecovery = 0
    private var manualGuardHeld = false

    public init() {}

    /// Explicit player intent only; neutral joystick does not engage defense.
    public mutating func setGuardHeld(_ held: Bool) { manualGuardHeld = held }

    /// x points right; y points up. Facing is applied only when consuming the
    /// command, so the UI never needs to decide which equipped move is forward.
    public mutating func direction(x: Int, y: Int) {
        let nextY = min(1, max(-1, y))
        if nextY > 0 && self.y <= 0 { pendingJumpTicks = Self.jumpChordGraceTicks }
        self.x = min(1, max(-1, x))
        self.y = nextY
        // Button-first chords remain live until the neutral tap/hold resolves.
        // Capture the direction now even if both fingers end before the next tick.
        if self.x != 0 || self.y != 0 {
            guardRecovery = Self.guardRecoveryTicks
            resolveHeldDirections()
        }
    }

    public mutating func action(_ action: Action, down: Bool) {
        if down { press(action) } else { release(action) }
    }

    /// Duplicate Down events are coalesced. The view owns physical finger counts.
    public mutating func press(_ action: Action) {
        guard presses[action] == nil else { return }
        guardRecovery = Self.guardRecoveryTicks
        presses[action] = Press(order: nextPressOrder)
        nextPressOrder &+= 1
        if action == .ranged || action == .shadow || x != 0 || y != 0 {
            enqueue(Intent(action: action, x: x, y: y))
            presses[action]?.resolved = true
        }
    }

    public mutating func release(_ action: Action) {
        guard let press = presses.removeValue(forKey: action), !press.resolved else { return }
        enqueue(Intent(action: action, x: x, y: y))
        guardRecovery = Self.guardRecoveryTicks
    }

    /// A cancelled touch is not a completed tap. Already-resolved commands stay
    /// committed; use cancelAll on pause/restart to clear the whole mailbox too.
    public mutating func cancel(action: Action) { presses.removeValue(forKey: action) }

    public func isPressed(_ action: Action) -> Bool { presses[action] != nil }

    public mutating func consume(facing: Int, airborne: Bool) -> DuelGame.Input {
        for action in orderedPresses {
            guard var press = presses[action], !press.resolved else { continue }
            press.ticks = min(Self.longPressTicks, press.ticks + 1)
            if x != 0 || y != 0 || airborne {
                enqueue(Intent(action: action, x: x, y: y))
                press.resolved = true
            } else if press.ticks >= Self.longPressTicks && action == .weapon {
                enqueue(Intent(action: action, x: 0, y: 0, heavy: true))
                press.resolved = true
            }
            // No invented heavy-kick mapping: a neutral kick resolves on release.
            presses[action] = press
        }

        let recoveringGuard = guardRecovery > 0
        if guardRecovery > 0 { guardRecovery -= 1 }
        var jump = false
        if let remaining = pendingJumpTicks {
            if remaining == 0 {
                jump = queued == nil && !airborne
                pendingJumpTicks = nil
            } else { pendingJumpTicks = remaining - 1 }
        }
        let command = queued.map { Self.command(for: $0, facing: facing) }
        let result = DuelGame.Input(
            move: x,
            guardHeld: manualGuardHeld && !recoveringGuard && !airborne && x == 0 && y == 0 && presses.isEmpty && command == nil &&
                !jump && pendingJumpTicks == nil,
            taps: jump ? .jump : [], vertical: y, weaponCommand: command)
        queued = nil
        return result
    }

    /// Clear direction, held buttons, a pending chord, and the one-command mailbox
    /// before pausing, restarting, switching fighters, or losing touch ownership.
    public mutating func cancelAll() {
        x = 0; y = 0
        presses.removeAll(); nextPressOrder = 0
        queued = nil; pendingJumpTicks = nil; guardRecovery = 0; manualGuardHeld = false
    }

    public mutating func reset() { cancelAll() }

    private var orderedPresses: [Action] {
        presses.sorted { $0.value.order < $1.value.order }.map(\.key)
    }

    private mutating func resolveHeldDirections() {
        for action in orderedPresses {
            guard let press = presses[action], !press.resolved else { continue }
            enqueue(Intent(action: action, x: x, y: y))
            presses[action]?.resolved = true
        }
    }

    private mutating func enqueue(_ intent: Intent) {
        // First resolved intent wins this simulation tick. A rejected overlapping
        // intent is consumed at its source, never queued for an unexpected later hit.
        if queued == nil { queued = intent }
        pendingJumpTicks = nil
    }

    private static func command(for intent: Intent, facing: Int) -> DuelWeaponCommand {
        switch intent.action {
        case .ranged: return .ranged
        case .shadow: return .shadow
        case .weapon, .kick:
            let weapon = intent.action == .weapon
            if intent.heavy { return .heavy }
            if intent.y < 0 { return weapon ? .weaponDown : .kickDown }
            if intent.y > 0 { return weapon ? .weaponUp : .kickUp }
            let forward = facing < 0 ? -1 : 1
            if intent.x == -forward { return weapon ? .weaponBack : .kickBack }
            if intent.x == forward { return weapon ? .weaponForward : .kickForward }
            return weapon ? .weapon : .kick
        }
    }
}
