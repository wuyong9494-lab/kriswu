import Foundation

@main
struct ErlangHoundEffectClockChecks {
    static func main() {
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, name)
            print("PASS " + name)
        }
        func sample(_ age: Int, _ start: Int, _ delay: Double, _ duration: Double,
                    _ period: Double?, _ space: Int) -> Double? {
            DuelErlangHoundEffectClock.attachmentAge(modelAge: age, startTick: start,
                delay: delay, duration: duration, loopPeriod: period, space: space)
        }
        let bindings = DuelErlangHoundEffectClock.bindings
        check(bindings.map(\.startTick) == [0, 0, 56] && bindings[0].shiftY == -1.2 &&
              bindings[0].attachToLocal && !bindings[1].attachToLocal,
              "source HideStart, HideEnd and world-axis -120cm shift")
        check(sample(55, 56, 0, 1, nil, 0) == nil && sample(56, 56, 0, 1, nil, 0) == 56,
              "transition burst begins only at source IntervalEnd56")
        check(sample(30, 0, 0.1, 1, nil, 0) == 30 && sample(30, 0, 0.1, 1, nil, 1) == 6,
              "local follows current model; world retains original particle birth")
        check(sample(42, 0, 0.1, 0.4, 0.5, 1) == 36 && sample(35, 0, 0.1, 0.4, 0.5, 1) == nil,
              "world particle recurrence gets its own birth, with dead gap preserved")
        check(sample(110, 0, 0, 2, nil, 0) == 110 && sample(111, 0, 0, 2, nil, 0) == nil &&
              sample(-1, 0, 0, 2, nil, 0) == nil && sample(10, 0, .nan, 2, nil, 0) == nil &&
              sample(10, 0, 0, 2, 0, 0) == nil && sample(10, 0, 0, 2, nil, 2) == nil,
              "source lifetime and invalid clocks fail closed")
        print("5 D15 hound effect clock checks passed")
    }
}
