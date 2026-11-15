/// L4–L6 event semantics from D15_set_upgrade_4_desc _5_desc and _6_desc, preview-only numbers.
/// Collision truth and deterministic random rolls belong to the caller.
public struct DuelErlangLightSwords: Equatable, Sendable {
    public enum AvatarMove: Equatable, Sendable { case step, splitter, eye, earthshaker }
    public enum Contact: Equatable, Sendable { case landed, blocked, missed }
    public enum Cue: Equatable, Sendable {
        case summoned(count: Int)
        case launchQueued(count: Int)
        case launchReleased(count: Int)
        case retribution(hits: Int)
        case earthshakerConsumed(count: Int)
        case earthshakerBarrageReleased(count: Int)
    }
    public struct PreviewTuning: Equatable, Sendable {
        public let swordCap = 6
        public let weaponProcEvery = 2
        public let swordsPerAvatarMove = 2
        public let releaseDelayTicks = 14
        public let rangedCooldownTicks = 54
        public let retributionMinimumHits = 4
        public let retributionWindowTicks = 20
        public let retributionDurationTicks = 36
        public let retributionPercentPerHit = 5
        public init() {}
    }
    public private(set) var active = 0
    public private(set) var launchDelay = 0
    public private(set) var rangedCooldown = 0
    public private(set) var pending = 0
    public private(set) var retributionHits = 0
    public private(set) var retributionTicks = 0
    private var eligibleHitsUntilProc = 0
    private var clock = 0
    private var landedSwordTicks: [Int] = []

    public init() {}

    /// Qualifying actual spear contact only. Deterministic alternating fixture
    /// is not the original random roll and is never called for another weapon.
    @discardableResult
    public mutating func recordSpearContact(_ contact: Contact, tuning: PreviewTuning = .init()) -> Cue? {
        guard contact == .landed else { return nil }
        eligibleHitsUntilProc += 1
        guard eligibleHitsUntilProc >= tuning.weaponProcEvery else { return nil }
        eligibleHitsUntilProc = 0
        return summon(1, tuning: tuning)
    }

    /// Called once per accepted move activation, independently of later hit.
    @discardableResult
    public mutating func recordAvatarActivation(_ move: AvatarMove, tuning: PreviewTuning = .init()) -> Cue? {
        summon(tuning.swordsPerAvatarMove, tuning: tuning)
    }

    /// L6 stock-consuming attacks spend only existing summoned stock. A manual volley
    /// reserves its swords when queued, so they cannot be spent a second time.
    public mutating func consumeSummonedStock() -> Int {
        let consumed = active
        active = 0
        return consumed
    }

    @discardableResult
    public mutating func refillSummonedStock(tuning: PreviewTuning = .init()) -> Cue? {
        summon(tuning.swordCap, tuning: tuning)
    }

    public mutating func shortenRangedCooldownForWrath(maximum: Int) {
        rangedCooldown = min(rangedCooldown, maximum)
    }

    public mutating func enterAvatar() {
        rangedCooldown = 0
    }

    @discardableResult
    public mutating func requestLaunch(tuning: PreviewTuning = .init(), cooldownOverride: Int? = nil) -> Cue? {
        guard active > 0, pending == 0, rangedCooldown == 0 else { return nil }
        pending = active
        active = 0
        launchDelay = tuning.releaseDelayTicks
        rangedCooldown = cooldownOverride ?? tuning.rangedCooldownTicks
        return .launchQueued(count: pending)
    }

    /// L5 counts hits inside a window, never stocked swords, launches, whiffs or blocks.
    @discardableResult
    public mutating func recordSwordContact(_ contact: Contact, tuning: PreviewTuning = .init()) -> Cue? {
        guard contact == .landed else { return nil }
        trimRetributionWindow(tuning)
        landedSwordTicks.append(clock)
        // Use at most fixture stock cap for a bounded reference count.
        if landedSwordTicks.count > tuning.swordCap { landedSwordTicks.removeFirst() }
        let qualifyingHits = landedSwordTicks.count
        guard qualifyingHits >= tuning.retributionMinimumHits else { return nil }
        retributionHits = max(retributionHits, qualifyingHits)
        retributionTicks = tuning.retributionDurationTicks
        return .retribution(hits: retributionHits)
    }

    public func retributionPercent(tuning: PreviewTuning = .init()) -> Int {
        retributionHits * tuning.retributionPercentPerHit
    }

    private mutating func trimRetributionWindow(_ tuning: PreviewTuning) {
        landedSwordTicks.removeAll { clock - $0 >= tuning.retributionWindowTicks }
    }

    public mutating func step(tuning: PreviewTuning = .init()) -> Cue? {
        clock += 1
        trimRetributionWindow(tuning)
        retributionTicks = max(0, retributionTicks - 1)
        if retributionTicks == 0 { retributionHits = 0 }
        rangedCooldown = max(0, rangedCooldown - 1)
        guard pending > 0 else { return nil }
        launchDelay -= 1
        guard launchDelay == 0 else { return nil }
        let count = pending
        pending = 0
        return .launchReleased(count: count)
    }

    public mutating func clearRound() { self = .init() }

    @discardableResult
    private mutating func summon(_ amount: Int, tuning: PreviewTuning) -> Cue? {
        let newCount = min(tuning.swordCap - active, amount)
        guard newCount > 0 else { return nil }
        active += newCount
        return .summoned(count: newCount)
    }
}
