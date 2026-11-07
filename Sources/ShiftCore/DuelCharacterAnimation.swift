import Foundation

/// Samples authored clips using simulation ticks. Rendering cannot extend a
/// hit window or the three-second hold, and no wall-clock time enters a pose.
public struct DuelCharacterAnimation: Equatable, Sendable {
    public enum Clip: String, CaseIterable, Sendable {
        case idle = "Idle", guardPose = "Guard", tPose = "TPose", walk = "Walk"
        case jab = "Jab", cross = "Cross", grab = "Grab", sideLock = "SideLock"
        case release = "Release", hit = "Hit", jump = "Jump", victory = "Victory"
    }
    public let key: String
    public let clip: Clip
    public let progress: Float
    public let secondary: Clip?
    public let secondaryProgress: Float
    public let secondaryWeight: Float
    public let transitionTicks: Int

    private init(_ key: String, _ clip: Clip, _ progress: Float = 0,
                 secondary: Clip? = nil, secondaryProgress: Float = 0,
                 weight: Float = 0, transition: Int = 6) {
        self.key = key; self.clip = clip; self.progress = Self.clamp(progress)
        self.secondary = secondary; self.secondaryProgress = Self.clamp(secondaryProgress)
        self.secondaryWeight = Self.clamp(weight); transitionTicks = transition
    }

    public static func sample(_ fighter: DuelGame.Fighter, animationTick: Int,
                              grapple: DuelGame.Grapple?, index: Int,
                              phase: DuelGame.Phase) -> Self {
        if let hold = grapple {
            guard hold.attacker == index else { return .init("captured", .hit, 0.25, transition: 0) }
            switch hold.stage {
            case .takedown:
                let t = Float(hold.age) / Float(DuelGame.Grapple.takedownTicks)
                return .init("takedown", .grab, 0.5, secondary: .sideLock,
                             weight: t * t * (3 - 2 * t), transition: 0)
            case .hold:
                let ticks = hold.age - DuelGame.Grapple.takedownTicks
                return .init("hold", .sideLock, Float(ticks) / Float(DuelGame.Grapple.holdTicks), transition: 0)
            case .release:
                let ticks = hold.age - DuelGame.Grapple.takedownTicks - DuelGame.Grapple.holdTicks
                return .init("release", .release, Float(ticks) / Float(DuelGame.Grapple.releaseTicks), transition: 0)
            }
        }
        if fighter.knockdown > 0 { return .init("down", .hit, 0.25, transition: 0) }
        if case .matchOver(let winner) = phase {
            return .init("result", winner == index ? .victory : .hit, winner == index ? 1 : 0.25, transition: 0)
        }
        if fighter.stun > 0 {
            // Block stun is still a guard pose. A landed hit starts at the
            // authored impact (frame 4 of 1...13), then recovers over 17 ticks.
            if fighter.guarding { return .init("guard", .guardPose, transition: 0) }
            let recovery = Float(max(0, 17 - fighter.stun)) / 17
            return .init("hurt", .hit, 0.25 + 0.75 * recovery, transition: 0)
        }
        if let attack = fighter.attack {
            let data = DuelGame.data(attack.move, hero: fighter.hero)
            // Simulation time and attack age both freeze during hit stop.
            // Include the start tick so consecutive instances of the same move
            // restart their transition even if no idle frame was rendered.
            let key = "attack.\(attack.move.rawValue).\(animationTick - attack.age)"
            let transition = attack.age < data.startup ? 3 : 0
            if attack.move == .ultimate {
                let ready = Float(min(attack.age, data.startup)) / Float(data.startup) * 0.5
                let recover = Float(max(0, attack.age - data.startup - data.active)) / Float(data.recovery)
                return .init(key, .grab, ready, secondary: .guardPose, weight: recover, transition: transition)
            }
            // The authored punches reach contact at frame 8 and begin recovery
            // after frame 11 of a 1...19 source clip. Time-warp each rule phase
            // separately so heavy attacks keep their longer visible wind-up.
            let contact: Float = 7 / 18, recovery: Float = 10 / 18
            let time: Float
            if attack.age < data.startup {
                time = Float(attack.age) / Float(data.startup) * contact
            } else if attack.age < data.startup + data.active {
                time = contact + Float(attack.age - data.startup) / Float(data.active) * (recovery - contact)
            } else {
                time = recovery + Float(attack.age - data.startup - data.active) / Float(data.recovery) * (1 - recovery)
            }
            // Never blend contact back toward an idle pose when a renderer
            // first observes an attack at impact (including after a skipped draw).
            return .init(key, attack.move == .jab ? .jab : .cross, time, transition: transition)
        }
        if fighter.y > 0 { return .init("air", .jump, 0.5, transition: 3) }
        if fighter.guarding { return .init("guard", .guardPose) }
        if fighter.walking { return .init("walk", .walk, Float(max(0, animationTick) % 48) / 48) }
        return .init("idle", .idle, Float(max(0, animationTick) % 120) / 120)
    }

    private static func clamp(_ value: Float) -> Float { min(1, max(0, value)) }
}
