import Foundation

@main
struct ErlangStompClockChecks {
    static func require(_ test: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !test() { throw NSError(domain: "StompClock", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func observation(_ owner: Int = 0, _ id: UInt64 = 1, _ birth: Int = 100) -> DuelErlangStompEffectClock.Observation {
        .init(key: .init(owner: owner, model: id), bornAt: birth)
    }
    static func main() throws {
        var clock = DuelErlangStompEffectClock()
        let model = observation()
        try require(try clock.consume(frame: 10, liveTick: 100, fighting: true, models: [model]) == [model], "birth was not observed")
        try require(try clock.consume(frame: 10, liveTick: 100, fighting: true, models: [model]).isEmpty, "same fixed step replayed birth")
        try require(try clock.consume(frame: 11, liveTick: 101, fighting: true, models: [model]).isEmpty, "existing model replayed birth")
        print("PASS one source creation across repeated steps and display observations")

        _ = try clock.consume(frame: 29, liveTick: 119, fighting: true, models: [])
        try require(clock.active[model.key] == 100, "deleting collision model truncated original 1.4-second particles")
        _ = try clock.consume(frame: 93, liveTick: 183, fighting: true, models: [])
        try require(clock.active.count == 1, "last living source tick was removed early")
        _ = try clock.consume(frame: 94, liveTick: 184, fighting: true, models: [])
        try require(clock.active.isEmpty, "source lifetime was extended")
        print("PASS source 84-tick effect survives 18-tick model and expires exactly")

        clock.reset()
        _ = try clock.consume(frame: 1, liveTick: 100, fighting: true, models: [model])
        for frame in 2...30 { _ = try clock.consume(frame: frame, liveTick: 100, fighting: true, models: [model]) }
        try require(clock.active[model.key] == 100 && clock.liveTick == 100, "hit stop advanced FX clock")
        print("PASS paused live clock and hit stop do not advance or restart particles")

        clock.reset()
        let other = observation(1)
        _ = try clock.consume(frame: 1, liveTick: 100, fighting: true, models: [model, other])
        try require(clock.active.count == 2, "opposing owner's identical ID collided")
        _ = try clock.consume(frame: 2, liveTick: 101, fighting: false, models: [])
        try require(clock.active.isEmpty && clock.liveTick == nil, "round end retained source particles")
        let next = observation(0, 1, 0)
        try require(try clock.consume(frame: 0, liveTick: 0, fighting: true, models: [next]) == [next], "new round ID was not reusable")
        print("PASS independent owners and round reset")

        var caught = 0
        for invalid in [[observation(0, 1, 101)], [observation(0, 1, 80)], [model, model]] {
            var rejected = DuelErlangStompEffectClock()
            do { _ = try rejected.consume(frame: 0, liveTick: 100, fighting: true, models: invalid) }
            catch { caught += 1 }
        }
        try require(caught == 3, "future, already deleted or duplicate model was invented")
        print("PASS unsupported future, expired and duplicate observations reject")

        clock.reset()
        var observed = 0
        for tick in 0...90 {
            observed += try clock.consume(frame: tick, liveTick: tick, fighting: true,
                models: tick <= 18 ? [next] : []).count
            if tick == 60 { try require(clock.active.count == 1, "catch-up steps lost the long-lived leg") }
        }
        try require(observed == 1 && clock.active.isEmpty, "catch-up steps replayed or extended the effect")
        print("PASS fixed-step catch-up retains birth without any display frame")
    }
}
