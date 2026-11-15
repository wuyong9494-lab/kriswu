import Foundation

/// D15 state owned by the normal two-fighter simulation. The v23 sparring
/// fixture remains separate: its dummy, damage and PreviewTuning never drive
/// a Sun/Liu/Wu match. Source ratios use fixed-point units; authored animation
/// samples and source flag timers are intentionally separate clocks.
public struct DuelErlangFightState: Equatable, Sendable {
    public enum Form: String, Sendable { case human, avatar }
    public enum Ability: String, Codable, CaseIterable, Sendable {
        case meditate, hound, ascend, stomp, axe, eye, earth, swords, judgement
        public var title: String {
            switch self {
            case .meditate: return "冥想"
            case .hound: return "哮天犬"
            case .ascend: return "金身"
            case .stomp: return "踏击"
            case .axe: return "开山斧"
            case .eye: return "天眼"
            case .earth: return "裂地枪"
            case .swords: return "飞剑"
            case .judgement: return "终末裁决"
            }
        }
        public var role: String {
            switch self {
            case .meditate: return "erlangMeditationStart"
            case .hound: return "erlangHound"
            case .ascend: return "erlangTransform"
            case .stomp: return "erlangStep"
            case .axe: return "erlangAxe"
            case .eye: return "erlangEye"
            case .earth: return "erlangEarthshaker"
            case .swords: return "erlangSwords"
            case .judgement: return "erlangJudgment"
            }
        }
    }
    public struct Cast: Equatable, Sendable {
        public let ability: Ability
        public var role: String
        public var tick: Int
        public var duration: Int
        public let direction: Int
        public let originX: Int
        public var released = false
        public var spentSwords = 0
        public var acceptedContact = false
        public var sourceEndProcessed = false
    }
    public struct Emission: Equatable, Sendable {
        public let ability: Ability
        public let id: UInt64
        public let count: Int
        public let direction: Int
        public let originX: Int
    }

    /// Values below are transcribed from authenticated global
    /// 1.46.0.16.16733-prod lock1432/1427/1437/1440/1454/1469/1470.
    /// A timer unit is adapted to the application's 60 Hz clock explicitly;
    /// this does not infer it from the GLB's 30 FPS export sampling rate.
    public static let sourceVersion = "1.46.0.16.16733-prod"
    public static let maximumLight = 10_000
    public static let weaponHitLight = 250
    public static let meditationPulseLight = 50
    public static let meditationPulseUnits = 3
    public static let meditationMaximumUnits = 300
    public static let sourceTimerTicksPerUnit = 1
    public static let maximumSwords = 6
    /// Native 23787 writes this exact Float before CriticalHpReached. The
    /// arena's integer HUD value is not used as the underlying health floor.
    public static let criticalHealthFloor = Float(bitPattern: 0x3727c5ac)
    public let level: Int
    public private(set) var form: Form = .human
    public private(set) var light = 0
    public private(set) var liveTick = 0
    public private(set) var cast: Cast?
    public private(set) var cooldowns = Array(repeating: 0, count: Ability.allCases.count)
    public private(set) var meditationUnits = 0
    public private(set) var meditationPulse = 0
    public private(set) var meditationReleaseRequested = false
    public private(set) var meditationRechargeStarted = false
    public private(set) var swords = 0
    public private(set) var pendingSwords = 0
    public private(set) var swordReleaseTicks = 0
    public private(set) var swordSpawnSlots: [Int] = []
    public private(set) var swordAttackPending = false
    public private(set) var swordConsumeTicks = 0
    public private(set) var swordConsumePending = false
    /// D15_SWORDS_HIDEN is a persistent source variable, not a cast phase.
    public private(set) var swordsHidden = false
    public private(set) var wrathTicks = 0
    public private(set) var wrathRefillTicks = 0
    public private(set) var lightDrainTicks = 0
    public private(set) var meditationStacks = 0
    public private(set) var meditationStackTicks = 0
    public private(set) var explosionStacksHalf = 0
    public private(set) var explosionStackTicks = 0
    public private(set) var explosionCooldownTicks = 0
    public private(set) var holiness = 0
    public private(set) var holinessTicks = 0
    public private(set) var avatarSwordSummonsPending = 0
    public private(set) var avatarSwordSummonTicks = 0
    public private(set) var lethalProtectionSpent = false
    public private(set) var normalizedHealth: Float = 1
    public private(set) var immortalActive = false
    public private(set) var criticalHealTicks = 0
    public private(set) var immortalDisableTicks = 0
    public private(set) var returnToHumanPending = false
    private var random: UInt64
    private var nextEmissionID: UInt64 = 0

    public init(level: Int = 8, seed: UInt64) {
        self.level = min(8, max(2, level)); random = seed == 0 ? 1 : seed
        // The native ranged recharge curve is not recovered here. This initial
        // 60-tick button charge is an explicit application control adaptation.
        cooldowns[index(.meditate)] = 60
    }
    private func index(_ ability: Ability) -> Int { Ability.allCases.firstIndex(of: ability)! }
    public func cooldown(_ ability: Ability) -> Int { cooldowns[index(ability)] }
    public var mayGuard: Bool { form == .human && cast == nil && !returnToHumanPending }
    public var isMeditating: Bool { cast?.ability == .meditate && cast?.role != "erlangMeditationEnd" }
    public var energyPercent: Int { light * 100 / Self.maximumLight }
    public var damageImpactImmune: Bool { form == .avatar }

    /// Nearest integer for the application's health HUD, with any positive
    /// source fraction displayed as at least one. Subsequent damage always
    /// consumes normalizedHealth, so this never turns 1e-5 into a real 1 HP.
    public func displayedHealth(maximum: Int) -> Int {
        guard maximum > 0, normalizedHealth > 0 else { return 0 }
        return min(maximum, max(1, Int((Double(normalizedHealth) * Double(maximum)).rounded())))
    }

    @discardableResult
    public mutating func receiveDamage(_ amount: Int, maximumHealth: Int, canKill: Bool = true) -> Int {
        guard amount > 0, amount <= 1_000_000_000, maximumHealth > 0 else { return 0 }
        return receiveNormalizedDamage(Float(amount) / Float(maximumHealth),
                                       maximumHealth: maximumHealth, canKill: canKill)
    }
    /// A native SetHit.Damage replacement is already a normalized HP fraction.
    /// It must reach the health store without rounding through the integer HUD.
    @discardableResult
    public mutating func receiveNormalizedDamage(_ amount: Float, maximumHealth: Int, canKill: Bool = true) -> Int {
        guard amount.isFinite, amount > 0, amount <= 1_000_000_000,
              maximumHealth > 0, normalizedHealth > 0 else { return 0 }
        let before = displayedHealth(maximum: maximumHealth)
        let floor: Float = canKill ? 0 : min(normalizedHealth, 1 / Float(maximumHealth))
        normalizedHealth = max(floor, normalizedHealth - amount)
        if normalizedHealth <= 0, immortalActive {
            normalizedHealth = Self.criticalHealthFloor
            // lock1454/t57 ignores further CriticalHpReached events while
            // its existing three-tick disable variable is still alive.
            if form == .avatar && !lethalProtectionSpent && immortalDisableTicks == 0 {
                lethalProtectionSpent = true
                criticalHealTicks = 1
                immortalDisableTicks = 3
            }
        }
        return max(0, before - displayedHealth(maximum: maximumHealth))
    }

    /// Original meditation and holiness modifiers apply to an accepted
    /// outgoing damage amount. Fixed-point factors preserve the source ratios
    /// without treating the normalized power as a percentage of target HP.
    public func outgoingDamage(_ amount: Int, lightAbility: Bool) -> Int {
        guard amount > 0 else { return 0 }
        let meditationBps = 10_000 + meditationStacks * (level >= 7 ? 120 : 100)
        let holinessBps = lightAbility && level >= 8 ? 10_000 + holiness * 215 : 10_000
        let first = Int64(amount) * Int64(meditationBps) / 10_000
        return Int(min(Int64(Int.max), first * Int64(holinessBps) / 10_000))
    }

    public func canUse(_ ability: Ability) -> Bool {
        if ability == .swords {
            return level >= 4 && normalizedHealth > 0 && !returnToHumanPending &&
                swords > 0 && !swordsHidden && pendingSwords == 0 && !swordAttackPending && cooldown(.swords) == 0 &&
                cast?.ability != .ascend && cast?.ability != .judgement
        }
        guard cast == nil, !returnToHumanPending, normalizedHealth > 0, cooldown(ability) == 0 else { return false }
        switch ability {
        case .meditate: return form == .human && light < Self.maximumLight
        case .hound: return form == .human
        case .ascend: return form == .human && light == Self.maximumLight
        case .stomp, .axe, .eye, .earth: return form == .avatar
        case .swords: return level >= 4 && swords > 0 && pendingSwords == 0 && !swordAttackPending
        case .judgement: return form == .avatar && level >= 6 && light == Self.maximumLight && swords > 0
        }
    }
    /// Delivered once from a real PostHit-equivalent contact, including its
    /// defense/kind. The source energy rule excludes MagicPower, while its
    /// sword proc separately requires Imperial Spear WeaponDamage.
    public mutating func acceptedPhysicalContact(kind: DuelPanguRules.DamageKind,
                                                imperialSpear: Bool, generated: Bool,
                                                targetHasDogDebuff: Bool) {
        guard kind != .shadow, !generated else { return }
        light = min(Self.maximumLight, light + Self.weaponHitLight)
        if level >= 4, kind == .weapon, imperialSpear {
            random ^= random << 13; random ^= random >> 7; random ^= random << 17
            if random % 100 < 50 { createSword() }
        }
        if level >= 8, form == .human, targetHasDogDebuff {
            holiness = min(72, holiness + 1); holinessTicks = 480 * Self.sourceTimerTicksPerUnit
        }
    }
    public mutating func meditationExplosionContact() {
        guard level >= 3 else { return }
        let reduction = level >= 8 ? 8000 : 3400
        cooldowns[index(.meditate)] = cooldown(.meditate) * (10_000 - reduction) / 10_000
    }
    /// lock1437/t10 replaces the already calculated hit damage, so the source
    /// PreHit power factors are not multiplied into this fraction again.
    public var meditationExplosionFraction: Float {
        Float(min(100, max(0, explosionStacksHalf))) * 0.5 * 0.001
    }
    @discardableResult
    public mutating func claimMeditationExplosion() -> Bool {
        guard level >= 3, cast?.ability == .meditate, explosionCooldownTicks == 0 else { return false }
        explosionCooldownTicks = 90 * Self.sourceTimerTicksPerUnit
        return true
    }
    @discardableResult
    public mutating func start(_ ability: Ability, duration: Int, direction: Int, x: Int) -> Bool {
        guard ability != .swords, canUse(ability), duration > 0 else { return false }
        let units: Int
        switch ability {
        case .hound: units = 600
        case .stomp: units = 600
        case .axe: units = 900
        case .eye: units = 1200
        case .earth: units = 360
        case .swords: units = wrathTicks > 0 ? 30 : 140
        case .judgement: units = 30
        case .meditate, .ascend: units = 0
        }
        let multiplier = wrathTicks > 0 && [.stomp, .axe, .eye, .earth].contains(ability) ? 6000 : 10_000
        cooldowns[index(ability)] = max(0, units * Self.sourceTimerTicksPerUnit * multiplier / 10_000)
        cast = Cast(ability: ability, role: ability.role, tick: 0, duration: duration,
                    direction: direction < 0 ? -1 : 1, originX: x)
        if level >= 4, ability == .ascend || ability == .judgement {
            // lock1440/t11: actual AVATARA_START / Ultimate AnimationStart.
            swordsHidden = true
        }
        if ability == .meditate {
            meditationUnits = 0; meditationPulse = 0; meditationReleaseRequested = false
            meditationRechargeStarted = false
        }
        if ability == .judgement, swords > 0 {
            // lock1454/t31 destroys the existing models one source tick after
            // Ultimate starts. Their source deletion events supply the count.
            swordConsumeTicks = Self.sourceTimerTicksPerUnit
        }
        if level >= 4 && [.stomp, .axe, .eye, .earth].contains(ability) {
            createSword()
            avatarSwordSummonsPending = 1; avatarSwordSummonTicks = Self.sourceTimerTicksPerUnit
        }
        return true
    }
    /// lock1440/t13-14 schedules a model event; it does not replace the owner's
    /// body animation. The source uses Form2 (not the temporary Ultimate buff)
    /// to select the 30/140-tick delay.
    @discardableResult
    public mutating func requestSwords() -> Bool {
        guard canUse(.swords) else { return false }
        pendingSwords = swords
        swordReleaseTicks = (form == .avatar ? 30 : 140) * Self.sourceTimerTicksPerUnit
        cooldowns[index(.swords)] = swordReleaseTicks
        return true
    }
    private mutating func createSword() {
        guard swords < Self.maximumSwords, swordSpawnSlots.count < 64 else { return }
        swords += 1; swordSpawnSlots.append(swords)
    }
    private mutating func fillSwords() { for _ in swords..<Self.maximumSwords { createSword() } }
    mutating func takeSwordSpawnSlots() -> [Int] {
        let result = swordSpawnSlots; swordSpawnSlots.removeAll(keepingCapacity: true); return result
    }
    mutating func takeSwordAttackEvent() -> Bool {
        let result = swordAttackPending; swordAttackPending = false; return result
    }
    mutating func takeSwordConsumeEvent() -> Bool {
        let result = swordConsumePending; swordConsumePending = false; return result
    }
    /// Source D15_Spear_FX IntervalStart creates a zero-frame destruction
    /// variable. This is separate from the later Wave model release.
    mutating func consumeSwordsForWave() {
        guard level >= 6, cast?.ability == .earth, swords > 0 else { return }
        swordConsumePending = true
    }
    mutating func consumedSwordModels(_ count: Int) {
        cast?.spentSwords += count
        swords = max(0, swords - count)
    }
    mutating func swordAttackModelDeleted() { swords = 0 }
    @discardableResult
    public mutating func requestMeditationRelease() -> Bool {
        guard isMeditating else { return false }
        let first = !meditationReleaseRequested
        meditationReleaseRequested = true
        beginMeditationRecharge()
        return first
    }
    private mutating func beginMeditationRecharge() {
        guard !meditationRechargeStarted else { return }
        meditationRechargeStarted = true
        cooldowns[index(.meditate)] = 120 // explicit application recharge, not the native weapon curve
    }

    /// Called once for a live authoritative step. The Fight returns for hit-stop,
    /// intros, pause and round-break before calling this method.
    public mutating func advance() {
        liveTick += 1
        for i in cooldowns.indices { cooldowns[i] = max(0, cooldowns[i] - 1) }
        if swordReleaseTicks > 0 {
            swordReleaseTicks -= 1
            if swordReleaseTicks == 0 { swordAttackPending = true; pendingSwords = 0 }
        }
        if swordConsumeTicks > 0 {
            swordConsumeTicks -= 1
            if swordConsumeTicks == 0 { swordConsumePending = true }
        }
        if form == .human, meditationStackTicks > 0 {
            meditationStackTicks -= 1; if meditationStackTicks == 0 { meditationStacks = 0 }
        }
        if explosionStackTicks > 0 {
            explosionStackTicks -= 1; if explosionStackTicks == 0 { explosionStacksHalf = 0 }
        }
        explosionCooldownTicks = max(0, explosionCooldownTicks - 1)
        if form == .human, holinessTicks > 0 {
            holinessTicks -= 1; if holinessTicks == 0 { holiness = 0 }
        }
        if avatarSwordSummonsPending > 0 {
            avatarSwordSummonTicks -= 1
            if avatarSwordSummonTicks <= 0 {
                createSword()
                avatarSwordSummonsPending -= 1; avatarSwordSummonTicks = Self.sourceTimerTicksPerUnit
            }
        }
        if cast != nil { cast?.tick += 1 }
        if cast?.role == "erlangMeditationLoop" {
            meditationUnits += 1; meditationPulse += 1
            if meditationPulse >= Self.meditationPulseUnits * Self.sourceTimerTicksPerUnit {
                meditationPulse = 0; meditationEnergyPulse()
            }
            if meditationUnits >= Self.meditationMaximumUnits * Self.sourceTimerTicksPerUnit {
                meditationReleaseRequested = true
            }
        }
        if wrathTicks > 0 {
            wrathTicks -= 1; wrathRefillTicks -= 1
            if wrathRefillTicks <= 0 { fillSwords(); wrathRefillTicks = 180 * Self.sourceTimerTicksPerUnit }
            if wrathTicks == 0 { lightDrainTicks = 1 }
        }
        if lightDrainTicks > 0 {
            lightDrainTicks -= 1
            // lock1454/t28: subtract .06, then schedule the next pulse in 3
            // source ticks. This is distinct from meditation's .005 gain.
            if lightDrainTicks == 0 { light = max(0, light - 600); if light > 0 { lightDrainTicks = 3 * Self.sourceTimerTicksPerUnit } }
        }
        if criticalHealTicks > 0 {
            criticalHealTicks -= 1
            if criticalHealTicks == 0, normalizedHealth > 0 {
                // ApplyStatus ModHP .5 / Frames1. The native status consumer
                // applies the residual tick even though its default Step=10.
                normalizedHealth = min(1, normalizedHealth + 0.5)
            }
        }
        if immortalDisableTicks > 0 {
            immortalDisableTicks -= 1
            if immortalDisableTicks == 0 {
                immortalActive = false; form = .human
                meditationStacks = 0; meditationStackTicks = 0
                holiness = 0; holinessTicks = 0
                returnToHumanPending = true
                lightDrainTicks = 1
            }
        }
        // Apply source AnimationEnd exactly once, before the later arena
        // transition to idle. New 901/180 timers must not lose a tick here.
        if let cast, cast.tick == cast.duration { processSourceAnimationEnd() }
    }
    /// The source return is requested at t+3, but an active Uninterrupt
    /// interval owns its animation until IntervalEnd or the next idle entry.
    @discardableResult
    public mutating func beginHumanReturn(duration: Int, direction: Int, x: Int) -> Bool {
        guard returnToHumanPending, form == .human, normalizedHealth > 0, duration >= 0 else { return false }
        interrupt()
        cast = Cast(ability: .ascend, role: "erlangTransformOut", tick: 0, duration: duration,
                    direction: direction < 0 ? -1 : 1, originX: x, released: true)
        returnToHumanPending = false
        return true
    }
    public mutating func transition(role: String, duration: Int) {
        guard cast != nil else { return }
        let previousRole = cast?.role
        cast?.role = role; cast?.tick = 0; cast?.duration = duration; cast?.released = false
        cast?.sourceEndProcessed = false
        if role == "erlangMeditationEnd" {
            beginMeditationRecharge()
        } else if role == "erlangMeditationLoop" {
            if previousRole == "erlangMeditationStart" { meditationUnits = 0 }
            meditationPulse = 0
            meditationEnergyPulse()
        }
    }
    private mutating func meditationEnergyPulse() {
        let beforeFull = light < Self.maximumLight
        if beforeFull { light = min(Self.maximumLight, light + Self.meditationPulseLight) }
        if level >= 3, beforeFull || level >= 7 {
            meditationStacks = min(100, meditationStacks + 1)
            meditationStackTicks = form == .avatar ? 0 : (level >= 7 ? 600 : 360) * Self.sourceTimerTicksPerUnit
        }
        if level >= 3, beforeFull {
            explosionStacksHalf = min(100, explosionStacksHalf + 1)
            explosionStackTicks = 30 * Self.sourceTimerTicksPerUnit
        }
    }
    private mutating func processSourceAnimationEnd() {
        guard let current = cast, !current.sourceEndProcessed else { return }
        cast?.sourceEndProcessed = true
        guard current.role != "erlangTransformOut",
              current.ability == .ascend || current.ability == .judgement else { return }
        // lock1440/t12 SHOW is an End event. An interruption is not SHOW.
        if level >= 4 { swordsHidden = false }
        if level >= 6 { fillSwords() }
        if current.ability == .judgement {
            wrathTicks = 901 * Self.sourceTimerTicksPerUnit
            wrathRefillTicks = 180 * Self.sourceTimerTicksPerUnit
        }
    }
    /// Explicit completion also supports source-event control fixtures. The
    /// normal Fight has already delivered AnimationEnd at its bound tick.
    public mutating func completeCast() {
        processSourceAnimationEnd()
        avatarSwordSummonsPending = 0; avatarSwordSummonTicks = 0
        cast = nil
    }
    public mutating func interrupt() {
        if isMeditating { beginMeditationRecharge() }
        // A weapon reaction does not destroy the parent's already scheduled
        // sword variable. Round/KO cleanup clears it through resetRound.
        cast = nil; meditationReleaseRequested = false
        avatarSwordSummonsPending = 0; avatarSwordSummonTicks = 0
    }
    public mutating func confirmContact() { cast?.acceptedContact = true }
    /// Emits once at the authenticated animation marker. Damage still requires
    /// the separate spatial adapter to overlap an actual opponent capsule.
    public mutating func release() -> Emission? {
        guard var current = cast, !current.released else { return nil }
        current.released = true; cast = current
        if current.ability == .ascend {
            form = .avatar
            if level >= 6 {
                immortalActive = true; lethalProtectionSpent = false
                criticalHealTicks = 0; immortalDisableTicks = 0; returnToHumanPending = false
            }
            for ability in [Ability.stomp, .axe, .eye, .earth] { cooldowns[index(ability)] = 60 * Self.sourceTimerTicksPerUnit }
            holinessTicks = 0; meditationStackTicks = 0
            return nil
        }
        if current.ability == .judgement {
            light = 0
            for ability in [Ability.stomp, .axe, .eye, .earth] { cooldowns[index(ability)] = 60 * Self.sourceTimerTicksPerUnit }
        }
        nextEmissionID &+= 1
        return .init(ability: current.ability, id: nextEmissionID,
                     count: current.spentSwords > 0 ? current.spentSwords : 1,
                     direction: current.direction, originX: current.originX)
    }
    /// Ordinary duel rounds always clear avatar/casts/timers. Raid persistence
    /// is deliberately not imported into the app's versus/practice rules.
    public mutating func resetRound(seed: UInt64, retainingHealth: Bool = false) {
        let health = normalizedHealth
        self = .init(level: level, seed: seed)
        if retainingHealth { normalizedHealth = health }
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string(Self.sourceVersion); try writer.int(Self.sourceTimerTicksPerUnit)
        try writer.int(level); try writer.string(form.rawValue); try writer.int(light); try writer.int(liveTick)
        try writer.optional(cast) { writer, cast in
            try writer.string(cast.ability.rawValue); try writer.string(cast.role); try writer.int(cast.tick)
            try writer.int(cast.duration); try writer.int(cast.direction); try writer.int(cast.originX)
            try writer.bool(cast.released); try writer.int(cast.spentSwords); try writer.bool(cast.acceptedContact)
            try writer.bool(cast.sourceEndProcessed)
        }
        try writer.array(cooldowns, limit: 9) { try $0.int($1) }
        try writer.int(meditationUnits); try writer.int(meditationPulse); try writer.bool(meditationReleaseRequested)
        try writer.bool(meditationRechargeStarted)
        try writer.int(swords); try writer.int(pendingSwords); try writer.int(swordReleaseTicks)
        try writer.array(swordSpawnSlots, limit: 64) { try $0.int($1) }
        try writer.bool(swordAttackPending); try writer.int(swordConsumeTicks); try writer.bool(swordConsumePending)
        try writer.bool(swordsHidden)
        try writer.int(wrathTicks); try writer.int(wrathRefillTicks); try writer.int(lightDrainTicks)
        try writer.int(meditationStacks); try writer.int(meditationStackTicks)
        try writer.int(explosionStacksHalf); try writer.int(explosionStackTicks); try writer.int(explosionCooldownTicks)
        try writer.int(holiness); try writer.int(holinessTicks)
        try writer.int(avatarSwordSummonsPending); try writer.int(avatarSwordSummonTicks)
        try writer.bool(lethalProtectionSpent)
        try writer.double(Double(normalizedHealth)); try writer.bool(immortalActive)
        try writer.int(criticalHealTicks); try writer.int(immortalDisableTicks); try writer.bool(returnToHumanPending)
        try writer.u64(random); try writer.u64(nextEmissionID)
    }
}
