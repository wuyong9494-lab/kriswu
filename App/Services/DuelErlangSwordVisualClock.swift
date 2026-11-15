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
