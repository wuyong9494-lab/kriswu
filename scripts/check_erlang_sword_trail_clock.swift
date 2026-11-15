import Foundation
import ShiftCore

@main
struct ErlangSwordTrailClockChecks {
    typealias Clock = DuelErlangSwordEffectClock
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw NSError(domain: "SwordTrailClock", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static let key = Clock.Key(owner: 0, model: 1)
    static func observation(_ role: String, _ pose: Int, hidden: Bool = false) -> Clock.Observation {
        .init(key: key, bornAt: 100, role: role, motionTick: pose, hidden: hidden)
    }
    static func main() throws {
        var clock = Clock()
        _ = try clock.consume(frame: 1, liveTick: 100, fighting: true, models: [observation("erlangSummon_swordBirth1", 0)])
        _ = try clock.consume(frame: 93, liveTick: 192, fighting: true, models: [observation("erlangSummon_swordIdle", 0)])
        _ = try clock.consume(frame: 194, liveTick: 285, fighting: true, models: [observation("erlangSummon_swordIdle", 0)])
        _ = try clock.consume(frame: 195, liveTick: 286, fighting: true, models: [observation("erlangSummon_swordRotate", 0)])
        _ = try clock.consume(frame: 196, liveTick: 287, fighting: true, models: [observation("erlangSummon_sword", 0)])
        try require(clock.active[key]?.startedAt == 100, "A source pose transition restarted the particle effect")
        let frozen = clock.active
        _ = try clock.consume(frame: 196, liveTick: 287, fighting: true, models: [observation("erlangSummon_sword", 0)])
        _ = try clock.consume(frame: 197, liveTick: 287, fighting: true, models: [observation("erlangSummon_sword", 0)])
        try require(clock.active == frozen, "Pause/repeated frame advanced the visual clock")
        print("PASS Birth/Idle wrap/Rotate/Attack and frozen fixed steps keep one effect clock")

        _ = try clock.consume(frame: 198, liveTick: 288, fighting: true, models: [observation("erlangSummon_sword", 1, hidden: true)])
        try require(clock.active[key]?.hidden == true && clock.active[key]?.startedAt == 100,
                    "HIDE fabricated a new effect initialization")
        let shown = try clock.consume(frame: 220, liveTick: 310, fighting: true, models: [observation("erlangSummon_sword", 23)])
        try require(shown == [key] && clock.active[key]?.startedAt == 310,
                    "Witnessed source SHOW did not start a separate effect")
        let repeated = try clock.consume(frame: 221, liveTick: 311, fighting: true, models: [observation("erlangSummon_sword", 24)])
        try require(repeated.isEmpty && clock.active[key]?.startedAt == 310, "Visible frame fabricated another SHOW")
        print("PASS only a witnessed persistent HIDE -> SHOW starts a new effect")

        try require(Clock.particle(effectTick: 59, phase: 0)?.emitting == true &&
                    Clock.particle(effectTick: 60, phase: 0)?.emitting == false &&
                    Clock.particle(effectTick: 60, phase: 1) == .init(cycle: 0, ageTicks: 0) &&
                    Clock.particle(effectTick: 79, phase: 0) != nil && Clock.particle(effectTick: 80, phase: 0) == nil &&
                    Clock.particle(effectTick: 120, phase: 0) == .init(cycle: 1, ageTicks: 0),
                    "Particle births/tail expiry were merged into a perpetual ribbon")
        var old = try DuelSourceParticleTrail(lifetimeSeconds: Clock.tailSeconds, minimumVertexDistance: 0.002)
        try old.sample(tick: 58, worldPosition: .init(x: 1, y: 2, z: 0.5), emitting: true)
        try old.sample(tick: 59, worldPosition: .init(x: 1.1, y: 2.1, z: 0.5), emitting: true)
        let original = old.points(at: 59)
        try old.sample(tick: 59, worldPosition: .init(x: 999, y: 999, z: 999), emitting: true)
        try old.sample(tick: 60, worldPosition: nil, emitting: false)
        var next = try DuelSourceParticleTrail(lifetimeSeconds: Clock.tailSeconds, minimumVertexDistance: 0.002)
        try next.sample(tick: 60, worldPosition: .init(x: -3, y: 5, z: -0.5), emitting: true)
        try require(old.points(at: 60) == original && next.points(at: 60).count == 1,
                    "New particle/facing moved or joined a previous world-space tail")
        try old.sample(tick: 79, worldPosition: nil, emitting: false)
        try require(old.points(at: 79).isEmpty, "Dead particle kept expired world points")
        print("PASS independent one-second particles retain world tails for .33 seconds without reparenting")

        _ = try clock.consume(frame: 222, liveTick: 312, fighting: true, models: [])
        try require(clock.active.isEmpty, "Deleted model retained an active source effect")
        _ = try clock.consume(frame: 1, liveTick: 100, fighting: true, models: [observation("erlangSummon_swordBirth2", 0)])
        try require(clock.active[key]?.startedAt == 100, "Round/rollback reused another generation's SHOW clock")
        _ = try clock.consume(frame: 2, liveTick: 101, fighting: false, models: [])
        try require(clock.active.isEmpty && clock.liveTick == nil, "Round end retained visual state")
        do {
            let duplicate = observation("erlangSummon_swordBirth1", 0)
            _ = try clock.consume(frame: 3, liveTick: 102, fighting: true, models: [duplicate, duplicate])
            throw NSError(domain: "SwordTrailClock", code: 2)
        } catch Clock.Failure.source { }
        print("PASS deletion, rollback/round cleanup and duplicate model rejection")
    }
}
