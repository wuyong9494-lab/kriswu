import Foundation

/// Ordinary D13 level-four aura, projected from authenticated lock 1396/3–9.
/// The affected stacks belong to this owner's current opponent. Distances
/// use original COM-X coordinates, not millimetres or the pelvis anchor.
/// There is no poison damage, healing, Physics or ShadowCharge in this value.
public struct DuelSerpentWitheringState: Equatable, Sendable {
    public private(set) var liveTick = 0
    public private(set) var auraActive = false
    public private(set) var targetStacks = 0

    public init() {}

    /// RoundFightStart / accepted BLOOM_CHECK. The source activation is a
    /// persistent variable, not a Boolean recomputed from the displayed bar.
    mutating func observeBloom(_ bloom: Double, level: Int) {
        guard level >= 4, bloom.isFinite, bloom >= 0.33 else { return }
        auraActive = true
    }

    /// a11 supplies independent periodic events. Leaving and re-entering the
    /// radius never restarts either clock; a condition is checked when its
    /// event is delivered. The authoritative host never calls while frozen.
    @discardableResult
    mutating func advance(liveTick nextTick: Int, ownerCOMX: Double, targetCOMX: Double) -> Bool {
        guard liveTick < Int.max, nextTick == liveTick + 1,
              ownerCOMX.isFinite, targetCOMX.isFinite,
              abs(ownerCOMX) <= 10_000_000, abs(targetCOMX) <= 10_000_000 else { return false }
        liveTick = nextTick
        guard auraActive else { return true }
        let distance = abs(ownerCOMX - targetCOMX)
        if nextTick.isMultiple(of: 60), distance < 300 {
            targetStacks = min(40, targetStacks + 1)
        }
        if nextTick.isMultiple(of: 20), distance >= 300, targetStacks > 0 {
            targetStacks -= 1
        }
        return true
    }

    /// Lock 1396/9 changes the four attack-power factors during PreHit. A
    /// status ModHP write and a final SetHit replacement bypass those factors.
    /// Existing arena ranged attacks retain their declared weapon/shadow kind;
    /// all four original power factors share the same source expression.
    public func targetDamageFactor(_ kind: DuelTriadRules.DamageKind) -> Double {
        switch kind {
        case .weapon, .unarmed, .shadow: return 1 - Double(targetStacks) * 0.02
        case .trueDamage: return 1
        }
    }

    /// Lock 1396/4 sets FORCE_NO_CRITICAL before ordinary damage calculation.
    public var suppressesTargetCritical: Bool { targetStacks > 0 }

    /// Arena round replacement gives this owner a new target instance. Keep
    /// the owner's activation and periodic clock separate from target state.
    mutating func clearTarget() { targetStacks = 0 }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(liveTick); try writer.bool(auraActive); try writer.int(targetStacks)
    }
}
