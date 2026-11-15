// Verified rules are deliberately scoped to the publisher source's release track.
// Candidate mechanics from player references do not enable runtime behavior.
public enum DuelErlangReference {
    public enum Track: String, Sendable {
        case domesticFracture30
        case globalTowerTrial202604
    }

    public enum Interruption: Sendable {
        case ordinary
        case shadowMove
        case specialSetAbility
    }

    public static func confirmedMaximumLevel(on track: Track) -> Int? {
        track == .globalTowerTrial202604 ? 8 : nil
    }

    /// Official global level-6 post-fix behavior. This only governs interruption,
    /// not damage mitigation, immunity from damage, or PvP eligibility.
    /// Nil means that this release/level/condition does not have a proven rule.
    public static func preventsInterruption(
        track: Track, tier: Int, phase: DuelErlangState.Phase, cause: Interruption
    ) -> Bool? {
        guard track == .globalTowerTrial202604, tier == 6, phase == .ascended else { return nil }
        switch cause {
        case .shadowMove, .specialSetAbility: return true
        case .ordinary: return nil
        }
    }
}
