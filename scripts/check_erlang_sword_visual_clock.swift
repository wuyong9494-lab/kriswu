import Foundation

@main
struct ErlangSwordVisualClockChecks {
    typealias Clock = DuelErlangSwordVisualClock
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "SwordVisualClock", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func sample(_ role: String, _ live: Int, _ pose: Int, hidden: Bool = false) -> Clock.Sample? {
        Clock.sample(role: role, liveTick: live, bornAt: 100, motionTick: pose, hidden: hidden)
    }
    static func main() throws {
        let birth = sample("erlangSummon_swordBirth1", 100, 0)
        let idle = sample("erlangSummon_swordIdle", 192, 0)
        let attack = sample("erlangSummon_sword", 300, 0)
        try require(birth == .init(poseTick: 0, effectTick: 0) &&
                    idle == .init(poseTick: 0, effectTick: 92) &&
                    attack == .init(poseTick: 0, effectTick: 200), "role change restarted mesh initialization")
        print("PASS Birth -> Idle -> Attack changes source pose without replaying particle birth")

        let beforeWrap = sample("erlangSummon_swordIdle", 284, 92)
        let afterWrap = sample("erlangSummon_swordIdle", 285, 0)
        try require(beforeWrap?.effectTick == 184 && afterWrap?.effectTick == 185 &&
                    sample("erlangSummon_swordIdle", 285, 0) == afterWrap,
                    "source Idle wrap or repeated frozen draw changed effect age")
        print("PASS deferred Idle wrap and repeated frozen display preserve the separate birth clock")

        try require(sample("erlangSummon_swordRotate", 286, 0) != nil &&
                    sample("erlangSummon_swordRotate", 287, 1) == nil &&
                    sample("erlangSummon_sword", 370, 70) != nil &&
                    sample("erlangSummon_sword", 371, 71) == nil,
                    "Rotate acquired another frame or deleted sword acquired another sample")
        print("PASS one-sample Rotate and original attack DeleteModel boundary")

        try require(sample("erlangSummon_swordIdle", 300, 15, hidden: true) == nil &&
                    sample("erlangSummon_swordIdle", 301, 16)?.effectTick == 201,
                    "visibility state fabricated an effect SHOW/start event")
        print("PASS application visibility is honored without inventing a source SHOW event")

        try require(sample("erlangSummon_swordBirth6", 100, 0) != nil &&
                    sample("erlangSummon_swordBirth7", 100, 0) == nil &&
                    sample("erlangSummon_hound", 100, 0) == nil &&
                    sample("erlangSummon_swordIdle", 99, 0) == nil &&
                    sample("erlangSummon_swordIdle", 100 + Clock.sourceDurationTicks, 0) == nil,
                    "another companion or future/expired model entered sword renderer")
        print("PASS exact role scope, future model rejection and original 9999-second duration cap")
    }
}
