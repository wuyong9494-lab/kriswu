import Foundation

/// Presentation only: follows the pair and samples confirmed contact impulses.
/// Consumed simulation steps, never draw calls, own this state. The original
/// skeletons, animation samples, collision geometry and combat rules are unchanged.
public struct DuelCombatCamera: Equatable, Sendable {
    public struct Impact: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case block, light, heavy }
        public let kind: Kind
        public let direction: Int
        public init(kind: Kind, direction: Int) { self.kind = kind; self.direction = direction }
        fileprivate var strength: Double {
            switch kind { case .block: return 0.012; case .light: return 0.028; case .heavy: return 0.065 }
        }
    }

    public private(set) var centerX: Double = 5
    /// Twice the farthest fighter's distance from the tracked center. Including
    /// tracking lag prevents a fighter near a stage edge slipping out of shot.
    public private(set) var separation: Double = 3
    private var lastFrame: Int?
    private var lastAnimationTick: Int?
    private var impactStrength: Double = 0
    private var impactDirection: Double = 1
    private var impactAge: Double = 18

    public init() {}

    private var envelope: Double {
        impactAge < 18 ? impactStrength * pow(0.70, impactAge) : 0
    }
    public var impactOffsetX: Double { impactDirection * envelope * cos(impactAge * 2.4) }
    public var impactOffsetY: Double { envelope * sin(impactAge * 1.9) * 0.55 }

    public mutating func consume(frame: Int, animationTick: Int,
                                 firstX: Double, secondX: Double, impacts: [Impact] = []) {
        guard frame >= 0, animationTick >= 0, firstX.isFinite, secondX.isFinite else { return }
        if let lastFrame, frame < lastFrame { self = .init() }
        if let lastAnimationTick, animationTick < lastAnimationTick { self = .init() }
        guard lastFrame != frame else { return }
        let isFirstPose = lastAnimationTick == nil
        let elapsed = min(60, max(0, Double(frame) - Double(lastFrame ?? 0)))
        let animationElapsed = min(60, max(0, Double(animationTick) - Double(lastAnimationTick ?? 0)))
        lastFrame = frame; lastAnimationTick = animationTick

        let a = min(10, max(0, firstX)), b = min(10, max(0, secondX))
        // A bounded stage-edge opening must start on the fighters, not at the
        // default world center. Preserve smooth tracking after the first pose.
        let target = min(8.5, max(1.5, (a + b) * 0.5))
        if isFirstPose { centerX = target }
        else { centerX += (target - centerX) * (1 - pow(0.88, animationElapsed)) }
        let required = 2 * max(abs(a - centerX), abs(b - centerX))
        // Expand immediately to protect the silhouettes. Ease back in over
        // animation ticks so a dash/knockback does not produce zoom pumping.
        if required > separation { separation = required }
        else if animationElapsed > 0 {
            separation = required + (separation - required) * pow(0.92, animationElapsed)
        }

        // The presentation frame advances during hit-stop, while animationTick
        // does not: a short contact recoil can settle around the frozen pose.
        impactAge = min(18, impactAge + elapsed)
        if let impact = impacts.max(by: { $0.strength < $1.strength }), impact.strength >= envelope {
            impactStrength = impact.strength
            impactDirection = impact.direction < 0 ? -1 : 1
            impactAge = 0
        }
    }
}
