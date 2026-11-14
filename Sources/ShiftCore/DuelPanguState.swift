import Foundation

/// Fixed-tick resource and ability interpreter. Spatial contacts are supplied by
/// DuelWeaponFight; a cast never damages an opponent merely because time passed.
/// All gameplay quantities come from the validated, versioned rule profile.
public struct DuelPanguState: Equatable, Sendable {
    public typealias Ability = DuelPanguRules.Ability
    public typealias DamageKind = DuelPanguRules.DamageKind

    public enum Phase: String, Codable, Sendable {
        case startup, active, recovery, petrifying, rising, charging, falling, landing
    }
    public struct Cast: Equatable, Sendable {
        public let id: UInt64
        public let ability: Ability
        public internal(set) var tick: Int
        public let duration: Int
        public internal(set) var phase: Phase
        public let empowered: Bool
    }
    public struct Control: Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case stun, petrify, pinned, dread }
        public let sourceID: UInt64
        public let kind: Kind
        public let durationTicks: Int
        public let damageTakenBonusBps: Int
        public let outgoingReductionBps: Int

        public init(sourceID: UInt64, kind: Kind, durationTicks: Int,
                    damageTakenBonusBps: Int = 0, outgoingReductionBps: Int = 0) {
            self.sourceID = sourceID; self.kind = kind; self.durationTicks = durationTicks
            self.damageTakenBonusBps = damageTakenBonusBps; self.outgoingReductionBps = outgoingReductionBps
        }
        func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
            try writer.u64(sourceID); try writer.string(kind.rawValue); try writer.int(durationTicks)
            try writer.int(damageTakenBonusBps); try writer.int(outgoingReductionBps)
        }
    }
    public struct Attack: Equatable, Sendable {
        public let id: UInt64
        public let ability: Ability?
        public let damageKind: DamageKind
        /// Own combo and temporary damage buffs are already applied exactly once.
        public let damage: Int
        public let blockedDamage: Int
        public let delivery: DuelPanguRules.Delivery
        public let rangeMillimeters: Int
        public let projectileSpeedMillimetersPerTick: Int
        public let hitboxBottomMillimeters: Int
        public let hitboxTopMillimeters: Int
        public let radiusMillimeters: Int
        public let impact: DuelImpactResponse
        public let stunTicks: Int
        public let airHoldTicks: Int
        public let knocksDown: Bool
        public let hitStopTicks: Int
        public let blockedHitStopTicks: Int
        public let generated: Bool
        /// Snapshot at spear cast: Rhythm expiring during flight does not change it.
        public let empowered: Bool

        func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
            try writer.u64(id); try writer.optional(ability) { try $0.string($1.rawValue) }
            try writer.string(damageKind.rawValue); try writer.string(delivery.rawValue)
            try writer.array([damage, blockedDamage, rangeMillimeters, projectileSpeedMillimetersPerTick,
                              hitboxBottomMillimeters, hitboxTopMillimeters, radiusMillimeters,
                              stunTicks, airHoldTicks, hitStopTicks, blockedHitStopTicks]) { try $0.int($1) }
            try writer.int(impact.distanceMillimeters); try writer.int(impact.durationTicks)
            try writer.int(impact.launchVelocityMillimetersPerTick); try writer.int(impact.gravityMillimetersPerTickSquared)
            try writer.bool(knocksDown); try writer.bool(generated); try writer.bool(empowered)
        }
    }
    public enum Effect: Equatable, Sendable {
        case attack(Attack)
        case control(Control)
        case teleportBehind(distanceMillimeters: Int)
        case pillarRise(heightMillimeters: Int, durationTicks: Int)
        case descend(velocityMillimetersPerTick: Int)
        case castPhase(Ability, Phase)
        case castEnded(Ability)
        case castInterrupted(Ability)

        func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
            switch self {
            case .attack(let attack): try writer.u8(0); try attack.appendReplayState(to: &writer)
            case .control(let control): try writer.u8(1); try control.appendReplayState(to: &writer)
            case .teleportBehind(let distance): try writer.u8(2); try writer.int(distance)
            case .pillarRise(let height, let duration):
                try writer.u8(3); try writer.int(height); try writer.int(duration)
            case .descend(let velocity): try writer.u8(4); try writer.int(velocity)
            case .castPhase(let ability, let phase):
                try writer.u8(5); try writer.string(ability.rawValue); try writer.string(phase.rawValue)
            case .castEnded(let ability): try writer.u8(6); try writer.string(ability.rawValue)
            case .castInterrupted(let ability): try writer.u8(7); try writer.string(ability.rawValue)
            }
        }
    }
    public struct DamageReceipt: Equatable, Sendable {
        public let accepted: Bool
        public let incomingDamage: Int
        public let adjustedDamage: Int
        public let absorbedDamage: Int
        public let lightSpent: Int
        public let healthDamage: Int
        public let comboReset: Bool
    }

    public let rules: DuelPanguRules
    public private(set) var light: Int
    public private(set) var combo = 0
    public private(set) var comboRemainingTicks = 0
    public private(set) var typhoonRemainingTicks = 0
    public private(set) var rhythmRemainingTicks = 0
    public private(set) var tranceRemainingTicks = 0
    public private(set) var earthquakeRemainingTicks = 0
    public private(set) var boulderBonusRemainingTicks = 0
    public private(set) var rangedCharges: Int
    public private(set) var activeCast: Cast?
    public private(set) var stormGateUses = 0
    public private(set) var typhoonCycle: UInt64 = 0
    public var attackSpeedBps: Int {
        let earth = rules.level >= 4 && combo >= rules.combo.level4SpeedThreshold ? rules.combo.level4AttackSpeedBps : 10_000
        let trance = tranceRemainingTicks > 0 ? rules.trance.attackSpeedBps : 10_000
        switch rules.policies.attackSpeedStacking {
        case .maximum: return max(earth, trance)
        case .multiplicative: return earth * trance / 10_000
        case .additive: return earth + trance - 10_000
        }
    }
    public var throwImmune: Bool { true }
    public var canBeThrown: Bool { false }
    public var damageImmune: Bool { activeCast.flatMap { rules.ability($0.ability)?.damageImmune } ?? false }

    // Cooldowns use exact integer ten-thousandths of a tick. This retains
    // fractional recovery instead of rounding a boosted cooldown every frame.
    private var cooldownUnits: [Int]
    private var rangedRechargeUnits: Int
    /// Fractional Light numerator, always below the configured denominator.
    /// This is gameplay state: a later completed charge interval may turn it
    /// into an integral resource unit even after an explicitly allowed carry.
    private var lightChargeRemainder = 0
    private var randomState: UInt64
    private var nextEffectID: UInt64 = 1
    private var lastContactID: UInt64?
    private var lastAttackEventID: UInt64?
    private var lastLandingEventID: UInt64?
    private struct PendingWind: Equatable, Sendable {
        var remainingTicks: Int
        var ability: Ability?
    }
    // A protocol/resource bound, not an original-game balance value. The normal
    // fight has at most two actors; this bounds hostile event streams as well.
    private static let maximumPendingWinds = 256
    private var pendingWinds: [PendingWind] = []
    public private(set) var rejectedPendingWindCount = 0
    private static let maximumDamage = 1_000_000_000

    public init?(rules: DuelPanguRules, seed: UInt64) {
        guard (try? rules.validate()) != nil else { return nil }
        self.rules = rules; light = rules.light.initial; rangedCharges = rules.ranged.initialCharges
        cooldownUnits = Array(repeating: 0, count: Ability.allCases.count)
        rangedRechargeUnits = rangedCharges < rules.ranged.maximumCharges ? rules.ranged.rechargeTicks * 10_000 : 0
        randomState = seed
    }

    public func cooldownRemaining(_ ability: Ability) -> Int {
        let units = cooldownUnits[index(ability)]
        return units / 10_000 + (units % 10_000 == 0 ? 0 : 1)
    }
    public func canUse(_ ability: Ability) -> Bool {
        guard activeCast == nil, rules.level >= ability.minimumLevel,
              let rule = rules.ability(ability), cooldownUnits[index(ability)] == 0,
              light >= rule.lightCost else { return false }
        if ability == .spear && rangedCharges == 0 { return false }
        if ability == .typhoon && typhoonRemainingTicks > 0 { return false }
        if ability == .stormGate && (typhoonRemainingTicks == 0 || stormGateUses >= rules.typhoon.stormGateUsesPerCycle) {
            return false
        }
        return true
    }

    @discardableResult public mutating func start(_ ability: Ability) -> [Effect] {
        guard canUse(ability), let rule = rules.ability(ability), let castID = takeEffectID() else { return [] }
        light -= rule.lightCost
        cooldownUnits[index(ability)] = startingCooldown(ability, rule: rule) * 10_000
        let empowered = ability == .spear && (rhythmRemainingTicks > 0 ||
            (rules.level >= 5 && combo >= rules.combo.rangedThreshold))
        if ability == .spear {
            rangedCharges -= 1
            if rangedRechargeUnits == 0 { rangedRechargeUnits = rules.ranged.rechargeTicks * 10_000 }
            if empowered && rules.policies.consumeRhythmOnSpearCast { rhythmRemainingTicks = 0 }
        }
        if ability == .stormGate { stormGateUses += 1 }
        let phase: Phase = ability == .heavenfall ? .petrifying : rule.startupTicks == 0 ? .active : .startup
        let duration = ability == .heavenfall ? rules.heavenfall.duration : rule.duration
        activeCast = Cast(id: castID, ability: ability, tick: 0, duration: duration, phase: phase, empowered: empowered)
        var effects: [Effect] = [.castPhase(ability, phase)]
        if ability == .heavenfall {
            finishLightChargeBoundary()
            grantHeavenfallCombo(at: .castStarted)
            effects.append(.control(.init(sourceID: castID, kind: .petrify,
                                          durationTicks: rules.heavenfall.targetPetrifyTicks)))
            if rules.heavenfall.tranceTrigger == .castStarted { activateTrance() }
        } else {
            if ability == .bones && rules.policies.earthWindowTrigger == .castStarted { activateEarthWindows() }
            if rule.startupTicks == 0 { effects += release(ability, castID: castID, empowered: empowered) }
        }
        return effects
    }

    /// Call only on a live simulation tick; hit-stop pauses this interpreter too.
    @discardableResult public mutating func step() -> [Effect] {
        decrementTimers()
        advanceCooldowns()
        advanceRangedRecharge()
        var effects = advancePendingWinds()
        guard var cast = activeCast, let rule = rules.ability(cast.ability) else { return effects }
        // Charge belongs to the interval being completed, not its entry frame.
        if cast.ability == .heavenfall && cast.phase == .charging {
            restoreHeavenfallCharge()
        }
        cast.tick += 1
        if cast.tick >= cast.duration {
            activeCast = nil
            if cast.ability == .heavenfall {
                finishLightChargeBoundary()
                grantHeavenfallCombo(at: .castEnded)
                if rules.heavenfall.tranceTrigger == .castEnded { activateTrance() }
            }
            effects.append(.castEnded(cast.ability))
            return effects
        }
        let newPhase = phase(for: cast.ability, tick: cast.tick, rule: rule)
        let changed = newPhase != cast.phase
        cast.phase = newPhase; activeCast = cast
        if changed {
            effects.append(.castPhase(cast.ability, newPhase))
            if cast.ability == .heavenfall { effects += enterHeavenfallPhase(newPhase, castID: cast.id) }
            else if newPhase == .active { effects += release(cast.ability, castID: cast.id, empowered: cast.empowered) }
        }
        return effects
    }

    /// Event IDs are monotonically increasing *contact* sequence numbers, not
    /// projectile birth IDs. Rejecting duplicates uses bounded constant memory.
    @discardableResult public mutating func contact(ability: Ability? = nil, blocked: Bool, generated: Bool,
                                                    hitID: UInt64, heavy: Bool = false, empowered: Bool = false) -> [Effect] {
        guard Self.accept(hitID, after: &lastContactID) else { return [] }
        let comboBefore = combo
        if !generated || rules.policies.generatedHitsRestoreLight {
            if blocked {
                if rules.level >= 5 { restoreLight(rules.light.level5BlockedHitGain) }
            } else {
                let primordial = !generated && (ability?.isPrimordial ?? false)
                let base = primordial ? rules.light.primordialHitGain : rules.light.regularHitGain
                let level5 = rules.level >= 5 && primordial ? rules.light.level5PrimordialGainBonus : 0
                restoreLight(base + (rules.level >= 3 ? rules.light.level3GainBonus : 0) + level5)
            }
        }
        let countsCombo = (!blocked || rules.policies.blockedHitsCountCombo)
            && (!generated || rules.policies.generatedHitsCountCombo)
        if countsCombo {
            addCombo(rules.combo.pointsPerHit)
            if !generated && tranceRemainingTicks > 0 && randomRoll() < rules.trance.extraComboChancePerMillion {
                addCombo(rules.trance.extraComboPoints)
            }
        }
        // A generated attack can use explicit combo/light policies but never
        // creates Rhythm, wind, bonus boulders, Dread or another generated hit.
        guard !generated else { return [] }
        var effects: [Effect] = []
        if rules.level >= 2, ability?.isPrimordial == true,
           !blocked || rules.policies.blockedPrimordialStartsRhythm {
            rhythmRemainingTicks = rules.hunt.durationTicks
        }
        if ability == .spear, empowered, !blocked || rules.policies.blockedSpearCanPin,
           let id = takeEffectID() {
            effects.append(.control(.init(sourceID: id, kind: .pinned, durationTicks: rules.hunt.pinTicks)))
        }
        if rules.level >= 4 && !blocked {
            if ability == .bones && rules.policies.earthWindowTrigger == .confirmedContact { activateEarthWindows() }
            if ability == .splitter {
                if rules.earth.dreadTicks > 0, let id = takeEffectID() {
                    effects.append(.control(.init(sourceID: id, kind: .dread, durationTicks: rules.earth.dreadTicks,
                                                  damageTakenBonusBps: rules.earth.dreadDamageTakenBonusBps,
                                                  outgoingReductionBps: rules.earth.dreadOutgoingReductionBps)))
                }
                effects += scheduleSplitterWinds()
            }
            if ability == .shard && boulderBonusRemainingTicks > 0,
               let attack = makeAttack(rules.earth.boulderBonus, ability: .shard, generated: true, empowered: false) {
                effects.append(.attack(attack))
            }
        }
        if rules.policies.windTrigger == .confirmedContact {
            let thresholdCombo = rules.policies.thresholdsUseComboBeforeContact ? comboBefore : combo
            effects += windEffects(ability: ability, heavy: heavy, thresholdCombo: thresholdCombo)
        }
        return effects
    }

    /// Ordinary weapon/unarmed attacks call this at startup. Ability casts use
    /// their own release path. Contact-trigger profiles return no startup wind.
    @discardableResult public mutating func attackStarted(ability: Ability? = nil, heavy: Bool,
                                                         eventID: UInt64) -> [Effect] {
        guard Self.accept(eventID, after: &lastAttackEventID), rules.policies.windTrigger == .attackStarted else { return [] }
        return windEffects(ability: ability, heavy: heavy, thresholdCombo: combo)
    }

    /// Dread belongs to the target-control layer and is deliberately not applied
    /// here. Cast-emitted Attack.damage values already use this function once.
    public func outgoingDamage(_ base: Int, kind: DamageKind, generated: Bool = false) -> Int {
        guard (0...Self.maximumDamage).contains(base) else { return 0 }
        let comboBonus = rules.combo.affectedKinds.contains(kind)
            ? min(rules.combo.maximumDamageBonusBps, combo * rules.combo.damageBonusPerPointBps) : 0
        let typhoonBonus = typhoonRemainingTicks > 0 ? rules.typhoon.damageBonusBps : 0
        return scaledDamage(base, multiplierBps: 10_000 + comboBonus + typhoonBonus)
    }

    @discardableResult public mutating func receiveDamage(_ amount: Int, kind: DamageKind,
                                                          blocked: Bool = false) -> DamageReceipt {
        guard (0...Self.maximumDamage).contains(amount) else {
            return .init(accepted: false, incomingDamage: amount, adjustedDamage: 0, absorbedDamage: 0,
                         lightSpent: 0, healthDamage: 0, comboReset: false)
        }
        let adjusted = damageImmune ? 0 : scaledDamage(amount, multiplierBps:
            tranceRemainingTicks > 0 ? rules.trance.incomingDamageMultiplierBps : 10_000)
        var absorbed = 0, spent = 0
        if adjusted > 0 && rules.light.absorbedKinds.contains(kind)
            && (light > 0 || !rules.policies.shieldRequiresPositiveLight) {
            let reduction = rules.level >= 4 && typhoonRemainingTicks > 0 ? rules.typhoon.lightCostReductionBps : 0
            let numerator = rules.light.damageToLightNumerator * (10_000 - reduction)
            let denominator = rules.light.damageToLightDenominator * 10_000
            if numerator == 0 { absorbed = adjusted }
            else {
                // Capacity rounds down; the light consumed for that integral
                // damage rounds up. An empty shield cannot absorb a partial HP.
                absorbed = min(adjusted, Int(Int64(light) * Int64(denominator) / Int64(numerator)))
                let product = Int64(absorbed) * Int64(numerator)
                spent = Int((product + Int64(denominator) - 1) / Int64(denominator))
            }
            light -= spent
        }
        let health = adjusted - absorbed
        let shouldAffectCombo = adjusted > 0 && (!blocked || rules.policies.blockedDamageResetsCombo)
            && (health > 0 || rules.policies.lightOnlyDamageResetsCombo)
        var didReset = false
        if shouldAffectCombo {
            if rules.level >= 6 {
                if combo > 0 && rules.policies.level6ReceivedHitRefreshesHold { comboRemainingTicks = holdDuration }
            } else {
                didReset = combo > 0; combo = 0; comboRemainingTicks = 0
            }
        }
        return .init(accepted: true, incomingDamage: amount, adjustedDamage: adjusted,
                     absorbedDamage: absorbed, lightSpent: spent, healthDamage: health, comboReset: didReset)
    }

    @discardableResult public mutating func landed(eventID: UInt64) -> [Effect] {
        guard Self.accept(eventID, after: &lastLandingEventID), rules.level >= 4, earthquakeRemainingTicks > 0,
              let attack = makeAttack(rules.earth.landingShock, ability: .bones, generated: true, empowered: false) else { return [] }
        return [.attack(attack)]
    }

    /// Cancels only not-yet-emitted follow-ups. Released spatial projectiles,
    /// light, combo, cooldowns and other resources remain owned by their layers.
    public mutating func cancelPendingDerivedAttacks() {
        pendingWinds.removeAll(keepingCapacity: true)
    }
    @discardableResult public mutating func interrupt(force: Bool = false) -> [Effect] {
        if force { cancelPendingDerivedAttacks() }
        guard let cast = activeCast, force || rules.ability(cast.ability)?.interruptible == true else { return [] }
        cancelPendingDerivedAttacks()
        activeCast = nil
        if cast.ability == .heavenfall { finishLightChargeBoundary() }
        var effects: [Effect] = [.castInterrupted(cast.ability)]
        if cast.ability == .heavenfall && rules.policies.interruptReleasesPetrification {
            effects.append(.control(.init(sourceID: cast.id, kind: .petrify, durationTicks: 0)))
        }
        return effects
    }
    public mutating func reset(seed: UInt64) {
        // The immutable rules have already passed validation.
        self = DuelPanguState(rules: rules, seed: seed)!
    }

    private var holdDuration: Int { rules.level >= 6 ? rules.combo.level6HoldTicks : rules.combo.holdTicks }
    private func index(_ ability: Ability) -> Int { Ability.allCases.firstIndex(of: ability)! }
    private static func accept(_ id: UInt64, after last: inout UInt64?) -> Bool {
        guard last == nil || id > last! else { return false }
        last = id; return true
    }
    private mutating func takeEffectID() -> UInt64? {
        guard nextEffectID < UInt64.max else { return nil }
        defer { nextEffectID += 1 }; return nextEffectID
    }
    private func scaledDamage(_ base: Int, multiplierBps: Int) -> Int {
        Int(min(Int64(Self.maximumDamage), Int64(base) * Int64(multiplierBps) / 10_000))
    }
    private mutating func restoreLight(_ amount: Int) {
        light = min(rules.light.maximum, light + amount)
        if light == rules.light.maximum,
           rules.heavenfall.level6LightChargeRatio?.discardRemainderAtCapacity == true {
            lightChargeRemainder = 0
        }
    }
    private mutating func restoreHeavenfallCharge() {
        let h = rules.heavenfall
        guard rules.level >= 6 else { restoreLight(h.lightPerChargeTick); return }
        guard let ratio = h.level6LightChargeRatio else { restoreLight(h.level6LightPerChargeTick); return }
        let total = Int64(h.lightPerChargeTick) * Int64(ratio.numerator) + Int64(lightChargeRemainder)
        let denominator = Int64(ratio.denominator)
        lightChargeRemainder = Int(total % denominator)
        restoreLight(Int(total / denominator))
    }
    /// Used at an accepted Heavenfall start, normal end and permitted
    /// interruption. Reset reconstructs the state and always clears carry.
    private mutating func finishLightChargeBoundary() {
        if rules.heavenfall.level6LightChargeRatio?.carryAcrossCasts != true { lightChargeRemainder = 0 }
    }
    private mutating func grantHeavenfallCombo(at trigger: DuelPanguRules.TranceTrigger) {
        guard rules.level >= 6, (rules.heavenfall.level6ComboGainTrigger ?? .landing) == trigger else { return }
        addCombo(rules.heavenfall.level6ComboGain)
    }
    private mutating func addCombo(_ amount: Int) {
        guard amount > 0 else { return }
        combo = min(rules.combo.maximum, combo + amount); comboRemainingTicks = holdDuration
        if rules.level >= 6 && combo >= rules.combo.zeroCooldownThreshold && rules.policies.zeroCooldownClearsExisting {
            for ability in Ability.allCases where ability.isPrimordial {
                if ability != .typhoon || rules.policies.typhoonCooldownPriority == .level6ZeroWins { cooldownUnits[index(ability)] = 0 }
            }
        }
    }
    private mutating func activateTrance() {
        if rules.level >= 6 { tranceRemainingTicks = rules.trance.durationTicks }
    }
    private mutating func activateEarthWindows() {
        if rules.level >= 4 {
            earthquakeRemainingTicks = rules.earth.earthquakeWindowTicks
            boulderBonusRemainingTicks = rules.earth.boulderBonusWindowTicks
        }
    }
    private mutating func randomRoll() -> Int {
        // SplitMix64 has an explicitly encoded state; wrapping is intentional
        // algorithm arithmetic, independent of platforms and Swift Hasher seeds.
        randomState &+= 0x9e3779b97f4a7c15
        var value = randomState
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        value ^= value >> 31
        return Int(value % 1_000_000)
    }
    private func startingCooldown(_ ability: Ability, rule: DuelPanguRules.AbilityRule) -> Int {
        let zero = rules.level >= 6 && combo >= rules.combo.zeroCooldownThreshold
        let level4 = rules.level >= 4 && ability.isPrimordial ? rules.level4PrimordialCooldownReductionTicks : 0
        let level6 = rules.level >= 6 && ability.isPrimordial ? rules.level6PrimordialCooldownReductionTicks : 0
        if ability == .typhoon {
            if zero && rules.policies.typhoonCooldownPriority == .level6ZeroWins { return 0 }
            // This explicit exception controls both the L6 fixed reduction and
            // any additional application recovery rate. Neither silently
            // replaces Typhoon's separate fixed-CD / zero-CD priority rule.
            let reduction = (rules.policies.level4ReductionAffectsTyphoon ? level4 : 0)
                + (rules.policies.level6RecoveryAffectsTyphoon ? level6 : 0)
            return max(0, rules.typhoon.fixedCooldownTicks - reduction)
        }
        if zero && ability.isPrimordial { return 0 }
        if zero && ability == .heavenfall {
            return Int((Int64(rule.cooldownTicks) * Int64(rules.heavenfall.level6CooldownMultiplierBps) + 9_999) / 10_000)
        }
        return max(0, rule.cooldownTicks - level4 - level6)
    }
    private mutating func decrementTimers() {
        comboRemainingTicks = max(0, comboRemainingTicks - 1)
        if comboRemainingTicks == 0 { combo = 0 }
        typhoonRemainingTicks = max(0, typhoonRemainingTicks - 1)
        rhythmRemainingTicks = max(0, rhythmRemainingTicks - 1)
        tranceRemainingTicks = max(0, tranceRemainingTicks - 1)
        earthquakeRemainingTicks = max(0, earthquakeRemainingTicks - 1)
        boulderBonusRemainingTicks = max(0, boulderBonusRemainingTicks - 1)
    }
    private mutating func advanceCooldowns() {
        for ability in Ability.allCases {
            let boosted = rules.level >= 6 && ability.isPrimordial &&
                (ability != .typhoon || rules.policies.level6RecoveryAffectsTyphoon)
            cooldownUnits[index(ability)] = max(0, cooldownUnits[index(ability)] - (boosted ? rules.level6CooldownRecoveryBps : 10_000))
        }
    }
    private mutating func advanceRangedRecharge() {
        guard rangedCharges < rules.ranged.maximumCharges else { rangedRechargeUnits = 0; return }
        let accelerated = rules.level >= 5 && combo >= rules.combo.rangedThreshold
        var budget = accelerated ? rules.ranged.level5RechargeMultiplierBps : 10_000
        let full = rules.ranged.rechargeTicks * 10_000
        while budget >= rangedRechargeUnits && rangedCharges < rules.ranged.maximumCharges {
            budget -= rangedRechargeUnits; rangedCharges += 1; rangedRechargeUnits = full
        }
        if rangedCharges == rules.ranged.maximumCharges { rangedRechargeUnits = 0 }
        else { rangedRechargeUnits -= budget }
    }
    private func phase(for ability: Ability, tick: Int, rule: DuelPanguRules.AbilityRule) -> Phase {
        if ability != .heavenfall {
            if tick < rule.startupTicks { return .startup }
            return tick < rule.startupTicks + rule.activeTicks ? .active : .recovery
        }
        let h = rules.heavenfall
        if tick < h.petrifyPhaseTicks { return .petrifying }
        if tick < h.petrifyPhaseTicks + h.riseTicks { return .rising }
        if tick < h.petrifyPhaseTicks + h.riseTicks + h.chargeTicks { return .charging }
        if tick < h.petrifyPhaseTicks + h.riseTicks + h.chargeTicks + h.fallTicks { return .falling }
        return .landing
    }
    private mutating func release(_ ability: Ability, castID: UInt64, empowered: Bool) -> [Effect] {
        guard let rule = rules.ability(ability) else { return [] }
        if ability == .typhoon {
            typhoonRemainingTicks = rules.typhoon.durationTicks; stormGateUses = 0
            if typhoonCycle < UInt64.max { typhoonCycle += 1 }
            return []
        }
        if ability == .stormGate { return [.teleportBehind(distanceMillimeters: rules.typhoon.stormGateBehindMillimeters)] }
        if ability == .bones && rules.policies.earthWindowTrigger == .castReleased { activateEarthWindows() }
        let spec = ability == .spear && empowered ? rules.hunt.empoweredSpear : rule.attack
        var effects: [Effect] = []
        if let attack = makeAttack(spec, ability: ability, generated: false, empowered: empowered) { effects.append(.attack(attack)) }
        if rules.policies.windTrigger == .attackStarted { effects += windEffects(ability: ability, heavy: false, thresholdCombo: combo) }
        return effects
    }
    private mutating func enterHeavenfallPhase(_ phase: Phase, castID: UInt64) -> [Effect] {
        let h = rules.heavenfall
        switch phase {
        case .rising: return [.pillarRise(heightMillimeters: h.pillarHeightMillimeters, durationTicks: h.riseTicks)]
        case .charging:
            grantHeavenfallCombo(at: .chargeStarted)
            if h.tranceTrigger == .chargeStarted { activateTrance() }; return []
        case .falling: return [.descend(velocityMillimetersPerTick: h.descentVelocityMillimetersPerTick)]
        case .landing:
            var effects: [Effect] = []
            if let spec = rules.ability(.heavenfall)?.attack,
               let attack = makeAttack(spec, ability: .heavenfall, generated: false, empowered: false) { effects.append(.attack(attack)) }
            grantHeavenfallCombo(at: .landing)
            if h.tranceTrigger == .landing { activateTrance() }
            if rules.policies.windTrigger == .attackStarted { effects += windEffects(ability: .heavenfall, heavy: false, thresholdCombo: combo) }
            return effects
        default: return []
        }
    }
    private mutating func makeAttack(_ spec: DuelPanguRules.AttackSpec, ability: Ability?, generated: Bool,
                                     empowered: Bool) -> Attack? {
        guard let id = takeEffectID() else { return nil }
        var bonus = 0
        if !generated && rules.level >= 4 {
            if ability == .shard { bonus = rules.earth.shardDamageBonusBps }
            if ability == .splitter { bonus = rules.earth.splitterDamageBonusBps }
        }
        if !generated && rules.level >= 6 && ability == .heavenfall { bonus += rules.heavenfall.level6DamageBonusBps }
        let damage = outgoingDamage(scaledDamage(spec.damage, multiplierBps: 10_000 + bonus), kind: spec.damageKind, generated: generated)
        let blocked = outgoingDamage(scaledDamage(spec.blockedDamage, multiplierBps: 10_000 + bonus), kind: spec.damageKind, generated: generated)
        let stun = !generated && ability == .shard && rules.level >= 4 ? max(spec.stunTicks, rules.earth.shardStunTicks) : spec.stunTicks
        return Attack(id: id, ability: ability, damageKind: spec.damageKind, damage: damage, blockedDamage: blocked,
                      delivery: spec.delivery, rangeMillimeters: spec.rangeMillimeters,
                      projectileSpeedMillimetersPerTick: spec.projectileSpeedMillimetersPerTick,
                      hitboxBottomMillimeters: spec.hitboxBottomMillimeters, hitboxTopMillimeters: spec.hitboxTopMillimeters,
                      radiusMillimeters: spec.radiusMillimeters, impact: spec.impact, stunTicks: stun,
                      airHoldTicks: spec.airHoldTicks, knocksDown: spec.knocksDown,
                      hitStopTicks: spec.hitStopTicks, blockedHitStopTicks: spec.blockedHitStopTicks,
                      generated: generated, empowered: empowered)
    }
    private mutating func windEffects(ability: Ability?, heavy: Bool, thresholdCombo: Int) -> [Effect] {
        guard rules.level >= 2, ability != .typhoon, ability != .stormGate else { return [] }
        let threshold = (heavy && thresholdCombo >= rules.combo.heavyWindThreshold)
            || (rules.level >= 3 && thresholdCombo >= rules.combo.allAttackWindThreshold)
        let counts = [threshold ? rules.heavyWindCount : 0,
                      typhoonRemainingTicks > 0 ? rules.typhoonWindCount : 0,
                      tranceRemainingTicks > 0 ? rules.tranceWindCount : 0]
        let count = rules.policies.windSourcesStack ? counts.reduce(0, +) : (counts.max() ?? 0)
        return (0..<count).compactMap { _ in
            makeAttack(rules.windBlade, ability: ability, generated: true, empowered: false).map(Effect.attack)
        }
    }
    private mutating func scheduleSplitterWinds() -> [Effect] {
        var effects: [Effect] = []
        for index in 0..<rules.earth.splitterWindCount {
            let delay = index * rules.earth.splitterWindIntervalTicks
            if delay == 0 {
                if let attack = makeAttack(rules.windBlade, ability: .splitter, generated: true, empowered: false) { effects.append(.attack(attack)) }
            } else if pendingWinds.count < Self.maximumPendingWinds {
                pendingWinds.append(.init(remainingTicks: delay, ability: .splitter))
            } else {
                rejectedPendingWindCount = min(1_000_000, rejectedPendingWindCount + 1)
            }
        }
        return effects
    }
    private mutating func advancePendingWinds() -> [Effect] {
        var effects: [Effect] = [], remaining: [PendingWind] = []
        for var pending in pendingWinds {
            pending.remainingTicks -= 1
            if pending.remainingTicks <= 0 {
                if let attack = makeAttack(rules.windBlade, ability: pending.ability, generated: true, empowered: false) { effects.append(.attack(attack)) }
            } else { remaining.append(pending) }
        }
        pendingWinds = remaining; return effects
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try rules.appendReplayState(to: &writer)
        try writer.array([light, combo, comboRemainingTicks, typhoonRemainingTicks, rhythmRemainingTicks,
                          tranceRemainingTicks, earthquakeRemainingTicks, boulderBonusRemainingTicks,
                          rangedCharges, rangedRechargeUnits, stormGateUses, rejectedPendingWindCount,
                          lightChargeRemainder]) { try $0.int($1) }
        try writer.u64(typhoonCycle); try writer.u64(randomState); try writer.u64(nextEffectID)
        try writer.array(cooldownUnits, limit: 7) { try $0.int($1) }
        try writer.optional(lastContactID) { try $0.u64($1) }
        try writer.optional(lastAttackEventID) { try $0.u64($1) }
        try writer.optional(lastLandingEventID) { try $0.u64($1) }
        try writer.optional(activeCast) { writer, cast in
            try writer.u64(cast.id); try writer.string(cast.ability.rawValue); try writer.int(cast.tick)
            try writer.int(cast.duration); try writer.string(cast.phase.rawValue); try writer.bool(cast.empowered)
        }
        try writer.array(pendingWinds, limit: Self.maximumPendingWinds) { writer, pending in
            try writer.int(pending.remainingTicks); try writer.optional(pending.ability) { try $0.string($1.rawValue) }
        }
    }
}
