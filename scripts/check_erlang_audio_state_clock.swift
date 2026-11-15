import Foundation

/// Narrow checks for the new persistent-sword animation state clock. Compiles
/// only the production presentation clock and source sample declaration.
@main
struct ErlangAudioStateClockChecks {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    static func main() {
        let births = (1...6).map { slot in
            DuelErlangAudioClock.Marker(category: "birth\(slot)", clip: "d15_hovering_sword",
                modelRole: "erlangSummon_swordBirth\(slot)", sourceTick: 2, duration: 100)
        }
        let attack = DuelErlangAudioClock.Marker(category: "knives", clip: "d15_hovering_sword",
            modelRole: "erlangSummon_sword", sourceTick: 2, duration: 100)
        var clock = DuelErlangAudioClock()
        func consume(_ models: [DuelErlangAudioClock.ModelSample], frame: Int, paused: Bool = false) -> [String] {
            clock.consume(markers: births + [attack], samples: [], models: models,
                frame: frame, fighting: true, paused: paused, owners: [0])
        }
        func slots(age: Int) -> [DuelErlangAudioClock.ModelSample] {
            (1...6).map { .init(owner: 0, id: UInt64($0), role: "erlangSummon_swordBirth\($0)",
                age: age, stateStartedAt: 10) }
        }
        require(consume(slots(age: 1), frame: 11).isEmpty, "birth cue advanced before source tick 2")
        require(consume(slots(age: 2), frame: 12) == (1...6).map { "birth\($0)" },
            "six actual source birth instances did not each cross their own marker")
        require(consume(slots(age: 2), frame: 12).isEmpty, "same birth instances replayed")
        print("PASS six independent sword birth roles at exact source tick 2")

        let idle = DuelErlangAudioClock.ModelSample(owner: 0, id: 1,
            role: "erlangSummon_swordIdle", age: 5, stateStartedAt: 13)
        require(consume([idle], frame: 18).isEmpty, "held state invented an appearance cue")
        let firing = DuelErlangAudioClock.ModelSample(owner: 0, id: 1,
            role: "erlangSummon_sword", age: 2, stateStartedAt: 20)
        require(consume([firing], frame: 22) == ["knives"], "same-id attack lost its own source state clock")
        require(consume([firing], frame: 22).isEmpty, "same attack state replayed")
        let nextFiring = DuelErlangAudioClock.ModelSample(owner: 0, id: 1,
            role: "erlangSummon_sword", age: 2, stateStartedAt: 30)
        require(consume([nextFiring], frame: 32) == ["knives"],
            "new same-role animation state inherited the preceding attack age")
        print("PASS persistent instance Birth/Idle/Attack transitions and same-role state restart")

        let pausedFiring = DuelErlangAudioClock.ModelSample(owner: 0, id: 1,
            role: "erlangSummon_sword", age: 2, stateStartedAt: 40)
        require(consume([pausedFiring], frame: 42, paused: true).isEmpty, "pause consumed new source state")
        require(consume([pausedFiring], frame: 42) == ["knives"], "resume lost the unconsumed state marker")
        require(consume([.init(owner: 0, id: 1, role: "erlangSummon_sword", age: 1,
            stateStartedAt: 40)], frame: 43).isEmpty, "backward state age replayed")
        print("PASS paused state transition and backward animation-age fence")
        print("3 production state-clock checks passed")
    }
}
