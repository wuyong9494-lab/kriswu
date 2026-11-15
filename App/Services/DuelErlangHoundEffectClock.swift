import Foundation

/// Pure source-clock selection. No renderer callback can advance a model.
enum DuelErlangHoundEffectClock {
    struct Binding {
        let effect: String
        let startTick: Int
        let attachToLocal: Bool
        let shiftY: Double
    }
    static let effectNames = ["D15_dog_smoke(spine_root_joint)", "D15_dog_smoke_startEnd(spine_root_joint)"]
    // lock1433: Hide IntervalStart at 0 and IntervalEnd at 56. The loop's
    // original Shift.Y=-120cm is world-axis shift (_rotateAttachToLocal=0).
    static let bindings = [
        Binding(effect: effectNames[0], startTick: 0, attachToLocal: true, shiftY: -1.2),
        Binding(effect: effectNames[1], startTick: 0, attachToLocal: false, shiftY: 0),
        Binding(effect: effectNames[1], startTick: 56, attachToLocal: false, shiftY: 0)
    ]

    static func attachmentAge(modelAge: Int, startTick: Int, delay: Double,
                              duration: Double, loopPeriod: Double?, space: Int) -> Double? {
        guard (0...110).contains(modelAge), (0...110).contains(startTick), modelAge >= startTick,
              [0, 1].contains(space), delay.isFinite, delay >= 0,
              duration.isFinite, duration > 0,
              loopPeriod.map({ $0.isFinite && $0 > 0 && $0 + 0.0001 >= duration }) ?? true else { return nil }
        let time = Double(modelAge - startTick) / 60, elapsed = time - delay
        guard elapsed >= 0 else { return nil }
        let occurrence = loopPeriod.map { floor(elapsed / $0) * $0 } ?? 0
        let local = elapsed - occurrence
        guard local < duration else { return nil }
        // source moveWithTransform=0 is local. 1 is world: retain this
        // occurrence's birth transform, including each repeated emission.
        return space == 0 ? Double(modelAge) : Double(startTick) + (delay + occurrence) * 60
    }
}
