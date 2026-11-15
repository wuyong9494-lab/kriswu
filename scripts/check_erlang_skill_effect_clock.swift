import Foundation

@main
struct ErlangSkillClockChecks {
    typealias Clock = DuelErlangSkillEffectClock
    static let rules = [Clock.Definition(role: "erlangSummon_eye", modelEndTick: 122, lifetimeTicks: 150)]
    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw NSError(domain: "ErlangSkillClock", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func model(_ owner: Int = 0, _ id: UInt64 = 1, _ birth: Int = 100) -> Clock.Observation {
        .init(key: .init(owner: owner, model: id), role: "erlangSummon_eye", bornAt: birth)
    }
    static func main() throws {
        var clock = Clock(); let first = model()
        try require(try clock.consume(frame: 10, liveTick: 100, fighting: true, models: [first], definitions: rules) == [first], "source birth missing")
        try require(try clock.consume(frame: 10, liveTick: 100, fighting: true, models: [first], definitions: rules).isEmpty, "same frame repeated source event")
        try require(try clock.consume(frame: 11, liveTick: 101, fighting: true, models: [first], definitions: rules).isEmpty, "living model restarted burst")
        print("PASS one authoritative source birth, independent of repeated presentation")

        _ = try clock.consume(frame: 133, liveTick: 223, fighting: true, models: [], definitions: rules)
        try require(clock.active[first.key] == first, "model deletion truncated particles")
        _ = try clock.consume(frame: 159, liveTick: 249, fighting: true, models: [], definitions: rules)
        try require(clock.active.count == 1, "last living FX tick dropped")
        _ = try clock.consume(frame: 160, liveTick: 250, fighting: true, models: [], definitions: rules)
        try require(clock.active.isEmpty, "FX extended past authenticated lifetime")
        print("PASS effect lifetime remains independent of the earlier collision-model end")

        clock.reset()
        try require(try clock.consume(frame: 1, liveTick: 110, fighting: true, models: [first], definitions: rules).isEmpty && clock.active.isEmpty,
            "late observation invented a past source head attachment")
        _ = try clock.consume(frame: 2, liveTick: 111, fighting: true, models: [first], definitions: rules)
        try require(clock.active.isEmpty, "late model later replayed a missing source event")
        print("PASS first observed model after birth cannot synthesize a historical burst")

        clock.reset()
        _ = try clock.consume(frame: 1, liveTick: 100, fighting: true, models: [first], definitions: rules)
        for frame in 2...30 { _ = try clock.consume(frame: frame, liveTick: 100, fighting: true, models: [first], definitions: rules) }
        try require(clock.liveTick == 100 && clock.active[first.key] == first, "hit stop changed source age")
        print("PASS stopped live clock does not advance or restart source effects")

        clock.reset(); let second = model(1)
        _ = try clock.consume(frame: 1, liveTick: 100, fighting: true, models: [first, second], definitions: rules)
        try require(clock.active.count == 2, "two owners with equal model IDs collided")
        _ = try clock.consume(frame: 2, liveTick: 101, fighting: false, models: [], definitions: rules)
        try require(clock.active.isEmpty && clock.liveTick == nil, "round end retained effects")
        let next = model(0, 1, 0)
        try require(try clock.consume(frame: 0, liveTick: 0, fighting: true, models: [next], definitions: rules) == [next], "next round could not reuse source model ID")
        print("PASS independent owners and complete round cleanup")

        var rejected = 0
        let wrong = Clock.Observation(key: .init(owner: 0, model: 1), role: "erlangSummon_stomp", bornAt: 100)
        for observation in [[model(0, 1, 124)], [model(0, 1, 0)], [first, first], [wrong]] {
            var invalid = Clock()
            do { _ = try invalid.consume(frame: 1, liveTick: 123, fighting: true, models: observation, definitions: rules) }
            catch { rejected += 1 }
        }
        try require(rejected == 4, "invalid source role, age, duplicate or future was accepted")
        print("PASS source-role, expiry, duplicate and future observations reject")
    }
}
