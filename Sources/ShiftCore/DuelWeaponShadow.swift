import Foundation

/// Provisional native rules, not recovered SF3 event timing. Source animation,
/// rig and materials are retained; discontinuous shadow tracks are never swept.
public enum DuelShadowKind: Equatable, Sendable { case katanaDash, hammerThrow }

/// Read-only presentation derived from the authoritative fixed-step action.
/// A returned hammer is visible but never a second damage source.
public struct DuelShadowVisual: Equatable, Sendable {
    public let kind: DuelShadowKind
    public let tick: Int
    public let duration: Int
    public let isAttacking: Bool
    public let weaponBase: DuelWeaponPoint?
    public let weaponTip: DuelWeaponPoint?
}

enum DuelShadowRules {
    static let startup = 24
    static let cooldown = 360
    static func duration(katana: Bool) -> Int { katana ? 72 : 96 }
    static func active(_ tick: Int, katana: Bool) -> Bool {
        (startup..<(katana ? 40 : 48)).contains(tick)
    }
    static func hammer(_ tick: Int, origin: Int, direction: Int) -> (DuelWeaponPoint, DuelWeaponPoint)? {
        guard (24..<72).contains(tick) else { return nil }
        // Integer millimetres keep travel repeatable and bounded. Tick 47 is
        // the outbound tip, tick 71 returns to the release point. No teleport.
        let distance = tick < 48 ? (tick - 24) * 4800 / 23 : (71 - tick) * 4800 / 23
        let x = Double(min(DuelGame.rightWall, max(DuelGame.leftWall, origin + direction * (450 + distance)))) / 1000
        return (.init(x: x, y: 0.82, z: 0.08), .init(x: x, y: 1.28, z: 0.08))
    }
}
