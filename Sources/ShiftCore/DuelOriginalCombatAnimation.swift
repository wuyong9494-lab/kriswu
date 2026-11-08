import Foundation

/// Binds the existing deterministic combat rules to the unchanged source rig.
/// These are application-authored visual windows, not recovered SF3 hit data.
/// No source frame rate or original damage/skill equivalence is implied.
public struct DuelOriginalCombatAnimation: Equatable, Sendable {
    public typealias Clip = DuelOriginalRigReview.Clip
    public let key: String
    public let selection: DuelOriginalRigReview.Selection
    public let secondary: DuelOriginalRigReview.Selection?
    public let secondaryWeight: Float
    public let transitionTicks: Int

    private init(_ key: String, _ clip: Clip, _ phase: Double = 0,
                 secondary: Clip? = nil, secondaryPhase: Double = 0,
                 weight: Float = 0, transition: Int = 5) {
        self.key = key; selection = .init(clip: clip, phase: phase)
        self.secondary = secondary.map { .init(clip: $0, phase: secondaryPhase) }
        secondaryWeight = min(1, max(0, weight)); transitionTicks = transition
    }

    /// Zero-based source frames selected after inspecting the actual clips.
    /// Cross/finisher start after their earlier punches so a queued combo does
    /// not replay its previous strikes. The rule clock still decides all hits.
    public struct AttackWindow: Equatable, Sendable {
        public let clip: Clip
        public let first: Int, contact: Int, recovery: Int, last: Int
        public func frame(age: Int, timing: DuelGame.MoveData) -> Double {
            if age < timing.startup {
                return Double(first) + Double(max(0, age)) / Double(timing.startup) * Double(contact - first)
            }
            if age < timing.startup + timing.active {
                return Double(contact) + Double(age - timing.startup) / Double(timing.active) * Double(recovery - contact)
            }
            return min(Double(last), Double(recovery) + Double(age - timing.startup - timing.active) /
                Double(timing.recovery) * Double(last - recovery))
        }
    }
    public static func window(_ move: DuelGame.Move) -> AttackWindow {
        switch move {
        case .jab: return .init(clip: .jab, first: 0, contact: 9, recovery: 11, last: 33)
        case .cross: return .init(clip: .cross, first: 15, contact: 22, recovery: 25, last: 52)
        case .finisher: return .init(clip: .comboFinish, first: 27, contact: 32, recovery: 35, last: 55)
        case .heavy: return .init(clip: .heavy, first: 0, contact: 21, recovery: 24, last: 53)
        case .skill1: return .init(clip: .spinStrike, first: 0, contact: 13, recovery: 16, last: 47)
        case .skill2: return .init(clip: .uppercut, first: 0, contact: 13, recovery: 16, last: 38)
        case .ultimate: return .init(clip: .backThrowActive, first: 0, contact: 8, recovery: 10, last: 10)
        }
    }

    public static func sample(_ fighter: DuelGame.Fighter, animationTick: Int,
                              grapple: DuelGame.Grapple?, index: Int, phase: DuelGame.Phase) -> Self {
        if let hold = grapple {
            let fall = min(1, Float(hold.age) / Float(DuelGame.Grapple.takedownTicks))
            let eased = fall * fall * (3 - 2 * fall)
            let release = max(0, Float(hold.age - DuelGame.Grapple.takedownTicks - DuelGame.Grapple.holdTicks) /
                Float(DuelGame.Grapple.releaseTicks))
            if hold.attacker != index {
                return .init("captured", .idle, secondary: .backThrowPassive, secondaryPhase: 1,
                             weight: eased, transition: 0)
            }
            // The app's three-second arm hold is retained. Source crouch/fall
            // poses are blended on their own bones; this is not the original
            // game's complete back-throw sequence or a retarget to another rig.
            return .init("grapple", .guardPose, secondary: .backThrowActive,
                         secondaryPhase: 32.0 / 51, weight: eased * (1 - release), transition: 0)
        }
        if fighter.knockdown > 0 {
            if fighter.knockdown <= 20 {
                return .init("getUp", .getUp, Double(20 - fighter.knockdown) / 20, transition: 4)
            }
            return .init("down", .backThrowPassive, 1, transition: 3)
        }
        if case .matchOver(let winner) = phase {
            return .init("result", winner == index ? .victory : .backThrowPassive, 1, transition: 6)
        }
        if fighter.stun > 0 {
            return fighter.guarding ? .init("guard", .guardPose, transition: 0) :
                .init("hurt", .hit, Double(max(0, 17 - fighter.stun)) / 17, transition: 0)
        }
        if let attack = fighter.attack {
            let window = window(attack.move), timing = DuelGame.data(attack.move, hero: fighter.hero)
            let frame = window.frame(age: attack.age, timing: timing)
            return .init("attack.\(attack.move.rawValue).\(animationTick - attack.age)", window.clip,
                         frame / Double(window.clip.frameCount - 1),
                         transition: attack.age < timing.startup ? 3 : 0)
        }
        if fighter.y > 0 || fighter.velocityY > 0 {
            let progress = Double(DuelGame.jumpVelocity - fighter.velocityY) /
                Double(2 * DuelGame.jumpVelocity + DuelGame.gravity)
            return .init("air", .jump, progress, transition: 3)
        }
        if fighter.guarding { return .init("guard", .guardPose) }
        let clip: Clip = fighter.walking ? (fighter.movementDirection * fighter.facing >= 0 ? .walk : .backStep) : .idle
        let period = max(1, (clip.frameCount - 1) * 2)
        return .init(clip.rawValue, clip, Double(max(0, animationTick) % period) / Double(period))
    }
}
