import Foundation

/// Versioned, explicitly supplied Heavenly King rules. There is intentionally
/// no production default: the reference footage does not establish all retail
/// values or interaction priorities. Tests provide their own synthetic values.
public struct DuelPanguRules: Codable, Equatable, Sendable {
    public enum Ability: String, Codable, CaseIterable, Sendable {
        case shard, typhoon, splitter, bones, spear, heavenfall, stormGate
        public var isPrimordial: Bool { [.shard, .typhoon, .splitter, .bones].contains(self) }
        public var minimumLevel: Int { self == .spear ? 1 : self == .stormGate ? 4 : 2 }
    }
    public enum DamageKind: String, Codable, CaseIterable, Sendable { case weapon, unarmed, shadow }
    public enum Delivery: String, Codable, Sendable { case melee, projectile, ground, windBlade, landingShock }
    public enum Basis: String, Codable, Sendable { case applicationAdaptation, referenceMeasurement, sourceConfiguration }
    public enum WindTrigger: String, Codable, Sendable { case attackStarted, confirmedContact }
    public enum TyphoonCooldownPriority: String, Codable, Sendable { case fixedWins, level6ZeroWins }
    public enum EarthWindowTrigger: String, Codable, Sendable { case castStarted, castReleased, confirmedContact }
    public enum TranceTrigger: String, Codable, Sendable { case castStarted, chargeStarted, landing, castEnded }
    public enum AttackSpeedStacking: String, Codable, Sendable { case maximum, multiplicative, additive }

    public struct AttackSpec: Codable, Equatable, Sendable {
        public var damageKind: DamageKind
        public var damage: Int
        public var blockedDamage: Int
        public var delivery: Delivery
        public var rangeMillimeters: Int
        public var projectileSpeedMillimetersPerTick: Int
        public var hitboxBottomMillimeters: Int
        public var hitboxTopMillimeters: Int
        public var radiusMillimeters: Int
        public var impact: DuelImpactResponse
        public var stunTicks: Int
        public var airHoldTicks: Int
        public var knocksDown: Bool
        public var hitStopTicks: Int
        public var blockedHitStopTicks: Int

        public init(damageKind: DamageKind, damage: Int, blockedDamage: Int, delivery: Delivery,
                    rangeMillimeters: Int, projectileSpeedMillimetersPerTick: Int,
                    hitboxBottomMillimeters: Int, hitboxTopMillimeters: Int, radiusMillimeters: Int,
                    impact: DuelImpactResponse, stunTicks: Int, airHoldTicks: Int, knocksDown: Bool,
                    hitStopTicks: Int, blockedHitStopTicks: Int) {
            self.damageKind = damageKind; self.damage = damage; self.blockedDamage = blockedDamage
            self.delivery = delivery; self.rangeMillimeters = rangeMillimeters
            self.projectileSpeedMillimetersPerTick = projectileSpeedMillimetersPerTick
            self.hitboxBottomMillimeters = hitboxBottomMillimeters; self.hitboxTopMillimeters = hitboxTopMillimeters
            self.radiusMillimeters = radiusMillimeters; self.impact = impact
            self.stunTicks = stunTicks; self.airHoldTicks = airHoldTicks; self.knocksDown = knocksDown
            self.hitStopTicks = hitStopTicks; self.blockedHitStopTicks = blockedHitStopTicks
        }
    }

    public struct AbilityRule: Codable, Equatable, Sendable {
        public var ability: Ability
        public var cooldownTicks: Int
        public var lightCost: Int
        public var startupTicks: Int
        public var activeTicks: Int
        public var recoveryTicks: Int
        public var interruptible: Bool
        public var damageImmune: Bool
        public var attack: AttackSpec

        public init(ability: Ability, cooldownTicks: Int, lightCost: Int, startupTicks: Int,
                    activeTicks: Int, recoveryTicks: Int, interruptible: Bool, damageImmune: Bool,
                    attack: AttackSpec) {
            self.ability = ability; self.cooldownTicks = cooldownTicks; self.lightCost = lightCost
            self.startupTicks = startupTicks; self.activeTicks = activeTicks; self.recoveryTicks = recoveryTicks
            self.interruptible = interruptible; self.damageImmune = damageImmune; self.attack = attack
        }
        public var duration: Int { startupTicks + activeTicks + recoveryTicks }
        public var damageKind: DamageKind { attack.damageKind }
        public var damage: Int { attack.damage }
        public var blockedDamage: Int { attack.blockedDamage }
        public var delivery: Delivery { attack.delivery }
        public var rangeMillimeters: Int { attack.rangeMillimeters }
        public var projectileSpeedMillimetersPerTick: Int { attack.projectileSpeedMillimetersPerTick }
        public var hitboxBottomMillimeters: Int { attack.hitboxBottomMillimeters }
        public var hitboxTopMillimeters: Int { attack.hitboxTopMillimeters }
        public var radiusMillimeters: Int { attack.radiusMillimeters }
        public var impact: DuelImpactResponse { attack.impact }
        public var stunTicks: Int { attack.stunTicks }
        public var airHoldTicks: Int { attack.airHoldTicks }
        public var knocksDown: Bool { attack.knocksDown }
        public var hitStopTicks: Int { attack.hitStopTicks }
        public var blockedHitStopTicks: Int { attack.blockedHitStopTicks }
    }

    public struct LightRules: Codable, Equatable, Sendable {
        public var maximum: Int
        public var initial: Int
        public var damageToLightNumerator: Int
        public var damageToLightDenominator: Int
        public var absorbedKinds: [DamageKind]
        public var regularHitGain: Int
        public var primordialHitGain: Int
        public var level3GainBonus: Int
        public var level5BlockedHitGain: Int
        public var level5PrimordialGainBonus: Int
        public init(maximum: Int, initial: Int, damageToLightNumerator: Int, damageToLightDenominator: Int,
                    absorbedKinds: [DamageKind], regularHitGain: Int, primordialHitGain: Int,
                    level3GainBonus: Int, level5BlockedHitGain: Int, level5PrimordialGainBonus: Int) {
            self.maximum = maximum; self.initial = initial
            self.damageToLightNumerator = damageToLightNumerator; self.damageToLightDenominator = damageToLightDenominator
            self.absorbedKinds = absorbedKinds; self.regularHitGain = regularHitGain
            self.primordialHitGain = primordialHitGain; self.level3GainBonus = level3GainBonus
            self.level5BlockedHitGain = level5BlockedHitGain
            self.level5PrimordialGainBonus = level5PrimordialGainBonus
        }
    }

    public struct ComboRules: Codable, Equatable, Sendable {
        public var maximum: Int
        public var pointsPerHit: Int
        public var holdTicks: Int
        public var level6HoldTicks: Int
        public var damageBonusPerPointBps: Int
        public var maximumDamageBonusBps: Int
        public var affectedKinds: [DamageKind]
        public var heavyWindThreshold: Int
        public var allAttackWindThreshold: Int
        public var rangedThreshold: Int
        public var zeroCooldownThreshold: Int
        public var level4SpeedThreshold: Int
        public var level4AttackSpeedBps: Int
        public init(maximum: Int, pointsPerHit: Int, holdTicks: Int, level6HoldTicks: Int,
                    damageBonusPerPointBps: Int, maximumDamageBonusBps: Int, affectedKinds: [DamageKind],
                    heavyWindThreshold: Int, allAttackWindThreshold: Int, rangedThreshold: Int,
                    zeroCooldownThreshold: Int, level4SpeedThreshold: Int, level4AttackSpeedBps: Int) {
            self.maximum = maximum; self.pointsPerHit = pointsPerHit; self.holdTicks = holdTicks
            self.level6HoldTicks = level6HoldTicks; self.damageBonusPerPointBps = damageBonusPerPointBps
            self.maximumDamageBonusBps = maximumDamageBonusBps; self.affectedKinds = affectedKinds
            self.heavyWindThreshold = heavyWindThreshold; self.allAttackWindThreshold = allAttackWindThreshold
            self.rangedThreshold = rangedThreshold; self.zeroCooldownThreshold = zeroCooldownThreshold
            self.level4SpeedThreshold = level4SpeedThreshold; self.level4AttackSpeedBps = level4AttackSpeedBps
        }
    }

    public struct TyphoonRules: Codable, Equatable, Sendable {
        public var durationTicks: Int
        public var fixedCooldownTicks: Int
        public var damageBonusBps: Int
        public var lightCostReductionBps: Int
        public var stormGateUsesPerCycle: Int
        public var stormGateBehindMillimeters: Int
        public init(durationTicks: Int, fixedCooldownTicks: Int, damageBonusBps: Int, lightCostReductionBps: Int,
                    stormGateUsesPerCycle: Int, stormGateBehindMillimeters: Int) {
            self.durationTicks = durationTicks; self.fixedCooldownTicks = fixedCooldownTicks
            self.damageBonusBps = damageBonusBps; self.lightCostReductionBps = lightCostReductionBps
            self.stormGateUsesPerCycle = stormGateUsesPerCycle; self.stormGateBehindMillimeters = stormGateBehindMillimeters
        }
    }

    public struct HuntRules: Codable, Equatable, Sendable {
        public var durationTicks: Int
        public var empoweredSpear: AttackSpec
        public var pinTicks: Int
        public init(durationTicks: Int, empoweredSpear: AttackSpec, pinTicks: Int) {
            self.durationTicks = durationTicks; self.empoweredSpear = empoweredSpear; self.pinTicks = pinTicks
        }
    }

    /// Exact scaling of the base Heavenfall charge rate. Remainder lifetime is
    /// explicit because the reference percentage alone does not establish
    /// cross-cast carry or what happens to a fractional gain at full Light.
    public struct LightChargeRatio: Codable, Equatable, Sendable {
        public var numerator: Int
        public var denominator: Int
        public var carryAcrossCasts: Bool
        public var discardRemainderAtCapacity: Bool
        public init(numerator: Int, denominator: Int, carryAcrossCasts: Bool,
                    discardRemainderAtCapacity: Bool) {
            self.numerator = numerator; self.denominator = denominator
            self.carryAcrossCasts = carryAcrossCasts
            self.discardRemainderAtCapacity = discardRemainderAtCapacity
        }
    }

    public struct HeavenfallRules: Codable, Equatable, Sendable {
        public var petrifyPhaseTicks: Int
        public var targetPetrifyTicks: Int
        public var riseTicks: Int
        public var chargeTicks: Int
        public var fallTicks: Int
        public var recoveryTicks: Int
        public var pillarHeightMillimeters: Int
        public var descentVelocityMillimetersPerTick: Int
        public var lightPerChargeTick: Int
        public var level6LightPerChargeTick: Int
        public var level6DamageBonusBps: Int
        public var level6ComboGain: Int
        public var level6CooldownMultiplierBps: Int
        public var tranceTrigger: TranceTrigger
        /// Nil retains the original explicitly configured integral L6 rate.
        public var level6LightChargeRatio: LightChargeRatio?
        /// Nil retains the previous landing grant. Each selected boundary is
        /// entered at most once in a cast; interruption is not cast completion.
        public var level6ComboGainTrigger: TranceTrigger?
        public init(petrifyPhaseTicks: Int, targetPetrifyTicks: Int, riseTicks: Int, chargeTicks: Int,
                    fallTicks: Int, recoveryTicks: Int, pillarHeightMillimeters: Int,
                    descentVelocityMillimetersPerTick: Int, lightPerChargeTick: Int,
                    level6LightPerChargeTick: Int, level6DamageBonusBps: Int, level6ComboGain: Int,
                    level6CooldownMultiplierBps: Int, tranceTrigger: TranceTrigger,
                    level6LightChargeRatio: LightChargeRatio? = nil,
                    level6ComboGainTrigger: TranceTrigger? = nil) {
            self.petrifyPhaseTicks = petrifyPhaseTicks; self.targetPetrifyTicks = targetPetrifyTicks
            self.riseTicks = riseTicks; self.chargeTicks = chargeTicks; self.fallTicks = fallTicks
            self.recoveryTicks = recoveryTicks; self.pillarHeightMillimeters = pillarHeightMillimeters
            self.descentVelocityMillimetersPerTick = descentVelocityMillimetersPerTick
            self.lightPerChargeTick = lightPerChargeTick; self.level6LightPerChargeTick = level6LightPerChargeTick
            self.level6DamageBonusBps = level6DamageBonusBps; self.level6ComboGain = level6ComboGain
            self.level6CooldownMultiplierBps = level6CooldownMultiplierBps; self.tranceTrigger = tranceTrigger
            self.level6LightChargeRatio = level6LightChargeRatio
            self.level6ComboGainTrigger = level6ComboGainTrigger
        }
        public var duration: Int { petrifyPhaseTicks + riseTicks + chargeTicks + fallTicks + recoveryTicks }
    }

    public struct EarthRules: Codable, Equatable, Sendable {
        public var shardDamageBonusBps: Int
        public var shardStunTicks: Int
        public var splitterDamageBonusBps: Int
        public var dreadTicks: Int
        public var dreadDamageTakenBonusBps: Int
        public var dreadOutgoingReductionBps: Int
        public var splitterWindCount: Int
        public var splitterWindIntervalTicks: Int
        public var earthquakeWindowTicks: Int
        public var boulderBonusWindowTicks: Int
        public var landingShock: AttackSpec
        public var boulderBonus: AttackSpec
        public init(shardDamageBonusBps: Int, shardStunTicks: Int, splitterDamageBonusBps: Int,
                    dreadTicks: Int, dreadDamageTakenBonusBps: Int, dreadOutgoingReductionBps: Int,
                    splitterWindCount: Int, splitterWindIntervalTicks: Int, earthquakeWindowTicks: Int,
                    boulderBonusWindowTicks: Int, landingShock: AttackSpec, boulderBonus: AttackSpec) {
            self.shardDamageBonusBps = shardDamageBonusBps; self.shardStunTicks = shardStunTicks
            self.splitterDamageBonusBps = splitterDamageBonusBps; self.dreadTicks = dreadTicks
            self.dreadDamageTakenBonusBps = dreadDamageTakenBonusBps; self.dreadOutgoingReductionBps = dreadOutgoingReductionBps
            self.splitterWindCount = splitterWindCount; self.splitterWindIntervalTicks = splitterWindIntervalTicks
            self.earthquakeWindowTicks = earthquakeWindowTicks; self.boulderBonusWindowTicks = boulderBonusWindowTicks
            self.landingShock = landingShock; self.boulderBonus = boulderBonus
        }
    }

    public struct RangedRules: Codable, Equatable, Sendable {
        public var maximumCharges: Int
        public var initialCharges: Int
        public var rechargeTicks: Int
        public var level5RechargeMultiplierBps: Int
        public init(maximumCharges: Int, initialCharges: Int, rechargeTicks: Int, level5RechargeMultiplierBps: Int) {
            self.maximumCharges = maximumCharges; self.initialCharges = initialCharges
            self.rechargeTicks = rechargeTicks; self.level5RechargeMultiplierBps = level5RechargeMultiplierBps
        }
    }

    public struct TranceRules: Codable, Equatable, Sendable {
        public var durationTicks: Int
        public var attackSpeedBps: Int
        public var incomingDamageMultiplierBps: Int
        public var extraComboChancePerMillion: Int
        public var extraComboPoints: Int
        public init(durationTicks: Int, attackSpeedBps: Int, incomingDamageMultiplierBps: Int,
                    extraComboChancePerMillion: Int, extraComboPoints: Int) {
            self.durationTicks = durationTicks; self.attackSpeedBps = attackSpeedBps
            self.incomingDamageMultiplierBps = incomingDamageMultiplierBps
            self.extraComboChancePerMillion = extraComboChancePerMillion; self.extraComboPoints = extraComboPoints
        }
    }

    /// These disputed interactions must be selected by the supplied profile,
    /// not silently decided by the engine or inferred from translated names.
    public struct Policies: Codable, Equatable, Sendable {
        public var blockedHitsCountCombo: Bool
        public var blockedPrimordialStartsRhythm: Bool
        public var blockedSpearCanPin: Bool
        public var generatedHitsCountCombo: Bool
        public var generatedHitsRestoreLight: Bool
        public var blockedDamageResetsCombo: Bool
        public var lightOnlyDamageResetsCombo: Bool
        public var level6ReceivedHitRefreshesHold: Bool
        public var consumeRhythmOnSpearCast: Bool
        public var windTrigger: WindTrigger
        public var windSourcesStack: Bool
        public var thresholdsUseComboBeforeContact: Bool
        public var typhoonCooldownPriority: TyphoonCooldownPriority
        public var level6RecoveryAffectsTyphoon: Bool
        public var level4ReductionAffectsTyphoon: Bool
        public var zeroCooldownClearsExisting: Bool
        public var shieldRequiresPositiveLight: Bool
        public var earthWindowTrigger: EarthWindowTrigger
        public var interruptReleasesPetrification: Bool
        public var attackSpeedStacking: AttackSpeedStacking
        public init(blockedHitsCountCombo: Bool, blockedPrimordialStartsRhythm: Bool, blockedSpearCanPin: Bool,
                    generatedHitsCountCombo: Bool, generatedHitsRestoreLight: Bool, blockedDamageResetsCombo: Bool,
                    lightOnlyDamageResetsCombo: Bool, level6ReceivedHitRefreshesHold: Bool, consumeRhythmOnSpearCast: Bool,
                    windTrigger: WindTrigger, windSourcesStack: Bool, thresholdsUseComboBeforeContact: Bool,
                    typhoonCooldownPriority: TyphoonCooldownPriority, level6RecoveryAffectsTyphoon: Bool,
                    level4ReductionAffectsTyphoon: Bool,
                    zeroCooldownClearsExisting: Bool, shieldRequiresPositiveLight: Bool,
                    earthWindowTrigger: EarthWindowTrigger, interruptReleasesPetrification: Bool,
                    attackSpeedStacking: AttackSpeedStacking) {
            self.blockedHitsCountCombo = blockedHitsCountCombo; self.blockedPrimordialStartsRhythm = blockedPrimordialStartsRhythm
            self.blockedSpearCanPin = blockedSpearCanPin; self.generatedHitsCountCombo = generatedHitsCountCombo
            self.generatedHitsRestoreLight = generatedHitsRestoreLight; self.blockedDamageResetsCombo = blockedDamageResetsCombo
            self.lightOnlyDamageResetsCombo = lightOnlyDamageResetsCombo; self.level6ReceivedHitRefreshesHold = level6ReceivedHitRefreshesHold
            self.consumeRhythmOnSpearCast = consumeRhythmOnSpearCast; self.windTrigger = windTrigger
            self.windSourcesStack = windSourcesStack; self.thresholdsUseComboBeforeContact = thresholdsUseComboBeforeContact
            self.typhoonCooldownPriority = typhoonCooldownPriority; self.level6RecoveryAffectsTyphoon = level6RecoveryAffectsTyphoon
            self.level4ReductionAffectsTyphoon = level4ReductionAffectsTyphoon
            self.zeroCooldownClearsExisting = zeroCooldownClearsExisting; self.shieldRequiresPositiveLight = shieldRequiresPositiveLight
            self.earthWindowTrigger = earthWindowTrigger; self.interruptReleasesPetrification = interruptReleasesPetrification
            self.attackSpeedStacking = attackSpeedStacking
        }
    }

    public var id: String
    public var basis: Basis
    public var sourceVersion: String
    public var sourceSHA256: String?
    public var evidence: [String]
    public var level: Int
    public var maximumHealth: Int
    public var light: LightRules
    public var combo: ComboRules
    public var abilities: [AbilityRule]
    public var typhoon: TyphoonRules
    public var hunt: HuntRules
    public var heavenfall: HeavenfallRules
    public var earth: EarthRules
    public var ranged: RangedRules
    public var trance: TranceRules
    public var windBlade: AttackSpec
    public var heavyWindCount: Int
    public var typhoonWindCount: Int
    public var tranceWindCount: Int
    public var level6CooldownRecoveryBps: Int
    public var level4PrimordialCooldownReductionTicks: Int
    public var level6PrimordialCooldownReductionTicks: Int
    public var policies: Policies
    /// Nil preserves the explicitly supplied legacy/application interpreter.
    public var runtime: RuntimeProfile? = nil

    public init(id: String, basis: Basis, sourceVersion: String, sourceSHA256: String?, evidence: [String], level: Int,
                maximumHealth: Int,
                light: LightRules, combo: ComboRules, abilities: [AbilityRule], typhoon: TyphoonRules, hunt: HuntRules,
                heavenfall: HeavenfallRules, earth: EarthRules, ranged: RangedRules, trance: TranceRules,
                windBlade: AttackSpec, heavyWindCount: Int, typhoonWindCount: Int, tranceWindCount: Int,
                level4PrimordialCooldownReductionTicks: Int, level6PrimordialCooldownReductionTicks: Int,
                level6CooldownRecoveryBps: Int, policies: Policies) {
        self.id = id; self.basis = basis; self.sourceVersion = sourceVersion; self.sourceSHA256 = sourceSHA256
        self.evidence = evidence; self.level = level; self.maximumHealth = maximumHealth
        self.light = light; self.combo = combo; self.abilities = abilities
        self.typhoon = typhoon; self.hunt = hunt; self.heavenfall = heavenfall; self.earth = earth
        self.ranged = ranged; self.trance = trance; self.windBlade = windBlade; self.heavyWindCount = heavyWindCount
        self.typhoonWindCount = typhoonWindCount; self.tranceWindCount = tranceWindCount
        self.level6CooldownRecoveryBps = level6CooldownRecoveryBps; self.policies = policies
        self.level4PrimordialCooldownReductionTicks = level4PrimordialCooldownReductionTicks
        self.level6PrimordialCooldownReductionTicks = level6PrimordialCooldownReductionTicks
    }

    public func ability(_ value: Ability) -> AbilityRule? { abilities.first { $0.ability == value } }
    public enum ValidationError: Error, Equatable { case provenance, level, health, light, combo, ability, timing, bonus, policy }

    public func validate() throws {
        func bounded(_ value: Int, _ maximum: Int = 36_000) -> Bool { (0...maximum).contains(value) }
        func ticks(_ value: Int) -> Bool { (1...36_000).contains(value) }
        func bps(_ value: Int) -> Bool { bounded(value, 1_000_000) }
        func spec(_ value: AttackSpec) -> Bool {
            bounded(value.damage, 1_000_000) && bounded(value.blockedDamage, 1_000_000)
            && bounded(value.rangeMillimeters, 30_000) && bounded(value.projectileSpeedMillimetersPerTick, 10_000)
            && (-10_000...30_000).contains(value.hitboxBottomMillimeters)
            && value.hitboxTopMillimeters > value.hitboxBottomMillimeters && value.hitboxTopMillimeters <= 30_000
            && (1...5_000).contains(value.radiusMillimeters) && value.impact.isValid
            && bounded(value.stunTicks) && bounded(value.airHoldTicks)
            && bounded(value.hitStopTicks, 60) && bounded(value.blockedHitStopTicks, 60)
            && ((value.delivery != .projectile && value.delivery != .windBlade) || value.projectileSpeedMillimetersPerTick > 0)
        }
        guard !id.isEmpty, id.utf8.count <= 128, !sourceVersion.isEmpty, sourceVersion.utf8.count <= 256,
              evidence.count <= 16, evidence.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }),
              basis == .applicationAdaptation || !evidence.isEmpty else { throw ValidationError.provenance }
        if let hash = sourceSHA256 {
            guard hash.utf8.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw ValidationError.provenance
            }
        } else if basis == .sourceConfiguration { throw ValidationError.provenance }
        guard (1...6).contains(level) else { throw ValidationError.level }
        guard (1...1_000_000).contains(maximumHealth) else { throw ValidationError.health }
        guard (1...1_000_000).contains(light.maximum), (0...light.maximum).contains(light.initial),
              (1...10_000).contains(light.damageToLightNumerator), (1...10_000).contains(light.damageToLightDenominator),
              Set(light.absorbedKinds).count == light.absorbedKinds.count,
              [light.regularHitGain, light.primordialHitGain, light.level3GainBonus,
               light.level5BlockedHitGain, light.level5PrimordialGainBonus].allSatisfy({ bounded($0, 1_000_000) }) else { throw ValidationError.light }
        guard (1...(runtime == nil ? 10_000 : 1_000_000)).contains(combo.maximum), (1...combo.maximum).contains(combo.pointsPerHit),
              ticks(combo.holdTicks), ticks(combo.level6HoldTicks), combo.level6HoldTicks >= combo.holdTicks,
              bps(combo.damageBonusPerPointBps), bounded(combo.maximumDamageBonusBps, runtime == nil ? 1_000_000 : 1_240_000),
              Set(combo.affectedKinds).count == combo.affectedKinds.count,
              [combo.heavyWindThreshold, combo.allAttackWindThreshold, combo.rangedThreshold, combo.zeroCooldownThreshold,
               combo.level4SpeedThreshold].allSatisfy({ (1...combo.maximum).contains($0) }),
              (10_000...100_000).contains(combo.level4AttackSpeedBps) else { throw ValidationError.combo }
        guard abilities.count == Ability.allCases.count, Set(abilities.map(\.ability)) == Set(Ability.allCases),
              abilities.allSatisfy({ bounded($0.cooldownTicks) && (0...light.maximum).contains($0.lightCost)
                  && bounded($0.startupTicks) && ticks($0.activeTicks) && bounded($0.recoveryTicks)
                  && $0.startupTicks <= 36_000 - $0.activeTicks && $0.recoveryTicks <= 36_000 - $0.startupTicks - $0.activeTicks
                  && spec($0.attack) }) else { throw ValidationError.ability }
        guard ticks(typhoon.durationTicks), ticks(typhoon.fixedCooldownTicks), bps(typhoon.damageBonusBps),
              bounded(typhoon.lightCostReductionBps, 10_000), (1...32).contains(typhoon.stormGateUsesPerCycle),
              (1...10_000).contains(typhoon.stormGateBehindMillimeters), ticks(hunt.durationTicks), ticks(hunt.pinTicks),
              spec(hunt.empoweredSpear), hunt.empoweredSpear.damageKind == .shadow else { throw ValidationError.timing }
        guard [heavenfall.petrifyPhaseTicks, heavenfall.targetPetrifyTicks, heavenfall.riseTicks,
               heavenfall.chargeTicks, heavenfall.fallTicks, heavenfall.recoveryTicks].allSatisfy(ticks),
              heavenfall.duration <= 36_000, (1...10_000).contains(heavenfall.pillarHeightMillimeters),
              (1...10_000).contains(heavenfall.descentVelocityMillimetersPerTick),
              [heavenfall.lightPerChargeTick, heavenfall.level6LightPerChargeTick].allSatisfy({ bounded($0, 1_000_000) }),
              bps(heavenfall.level6DamageBonusBps), bounded(heavenfall.level6ComboGain, combo.maximum),
              (1...10_000).contains(heavenfall.level6CooldownMultiplierBps) else { throw ValidationError.timing }
        if let ratio = heavenfall.level6LightChargeRatio {
            guard (0...1_000_000).contains(ratio.numerator), (1...1_000_000).contains(ratio.denominator) else {
                throw ValidationError.timing
            }
            // All operands are bounded before multiplication. The maximum
            // integral gain including carry stays within the existing rate
            // bound, with the product evaluated in Int64 rather than Int.
            let product = Int64(heavenfall.lightPerChargeTick) * Int64(ratio.numerator)
            let maximumGain = (product + Int64(ratio.denominator) - 1) / Int64(ratio.denominator)
            guard maximumGain <= 1_000_000 else { throw ValidationError.timing }
        }
        // The spatial interpreter descends by this exact amount each tick.
        // Reject a nominal landing phase that precedes or follows its physical
        // ground contact; Trance and the landing strike share that boundary.
        let descentTicks = (heavenfall.pillarHeightMillimeters + heavenfall.descentVelocityMillimetersPerTick - 1)
            / heavenfall.descentVelocityMillimetersPerTick
        guard heavenfall.fallTicks == descentTicks else { throw ValidationError.timing }
        guard [earth.shardDamageBonusBps, earth.splitterDamageBonusBps, earth.dreadDamageTakenBonusBps].allSatisfy(bps),
              bounded(earth.dreadOutgoingReductionBps, 10_000),
              [earth.shardStunTicks, earth.dreadTicks, earth.splitterWindIntervalTicks,
               earth.earthquakeWindowTicks, earth.boulderBonusWindowTicks].allSatisfy({ bounded($0) }),
              (0...16).contains(earth.splitterWindCount), spec(earth.landingShock), spec(earth.boulderBonus),
              earth.boulderBonus.damageKind == .unarmed else { throw ValidationError.bonus }
        guard (1...32).contains(ranged.maximumCharges), (0...ranged.maximumCharges).contains(ranged.initialCharges),
              ticks(ranged.rechargeTicks), (1...100_000).contains(ranged.level5RechargeMultiplierBps),
              ticks(trance.durationTicks), (10_000...100_000).contains(trance.attackSpeedBps),
              bounded(trance.incomingDamageMultiplierBps, 10_000), bounded(trance.extraComboChancePerMillion, 1_000_000),
              bounded(trance.extraComboPoints, combo.maximum), spec(windBlade), windBlade.damageKind == .shadow,
              [heavyWindCount, typhoonWindCount, tranceWindCount].allSatisfy({ (0...16).contains($0) }),
              bounded(level4PrimordialCooldownReductionTicks), bounded(level6PrimordialCooldownReductionTicks),
              (1...100_000).contains(level6CooldownRecoveryBps) else { throw ValidationError.bonus }
        switch policies.attackSpeedStacking {
        case .maximum: break
        case .multiplicative:
            guard Int64(combo.level4AttackSpeedBps) * Int64(trance.attackSpeedBps) / 10_000 <= 100_000 else {
                throw ValidationError.bonus
            }
        case .additive:
            guard Int64(combo.level4AttackSpeedBps) + Int64(trance.attackSpeedBps) - 10_000 <= 100_000 else {
                throw ValidationError.bonus
            }
        }
        try runtime?.validate()
    }

    /// Field names and scalar values are explicitly encoded; JSON dictionary
    /// order, native memory layout, and runtime reflection never enter replay.
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string(id); try writer.string(basis.rawValue); try writer.string(sourceVersion)
        try writer.optional(sourceSHA256) { try $0.string($1) }; try writer.array(evidence, limit: 16) { try $0.string($1) }
        try writer.int(level)
        try writer.int(maximumHealth)
        try writer.array([light.maximum, light.initial, light.damageToLightNumerator, light.damageToLightDenominator,
                          light.regularHitGain, light.primordialHitGain, light.level3GainBonus,
                          light.level5BlockedHitGain, light.level5PrimordialGainBonus]) { try $0.int($1) }
        try writer.array(light.absorbedKinds.sorted { $0.rawValue < $1.rawValue }) { try $0.string($1.rawValue) }
        try writer.array([combo.maximum, combo.pointsPerHit, combo.holdTicks, combo.level6HoldTicks,
                          combo.damageBonusPerPointBps, combo.maximumDamageBonusBps, combo.heavyWindThreshold,
                          combo.allAttackWindThreshold, combo.rangedThreshold, combo.zeroCooldownThreshold,
                          combo.level4SpeedThreshold, combo.level4AttackSpeedBps]) { try $0.int($1) }
        try writer.array(combo.affectedKinds.sorted { $0.rawValue < $1.rawValue }) { try $0.string($1.rawValue) }
        try writer.array(abilities.sorted { $0.ability.rawValue < $1.ability.rawValue }, limit: 7) { writer, rule in
            try writer.string(rule.ability.rawValue)
            try writer.array([rule.cooldownTicks, rule.lightCost, rule.startupTicks, rule.activeTicks, rule.recoveryTicks]) { try $0.int($1) }
            try writer.bool(rule.interruptible); try writer.bool(rule.damageImmune); try rule.attack.appendReplayState(to: &writer)
        }
        try writer.array([typhoon.durationTicks, typhoon.fixedCooldownTicks, typhoon.damageBonusBps,
                          typhoon.lightCostReductionBps, typhoon.stormGateUsesPerCycle, typhoon.stormGateBehindMillimeters,
                          hunt.durationTicks, hunt.pinTicks]) { try $0.int($1) }
        try hunt.empoweredSpear.appendReplayState(to: &writer)
        try writer.array([heavenfall.petrifyPhaseTicks, heavenfall.targetPetrifyTicks, heavenfall.riseTicks,
                          heavenfall.chargeTicks, heavenfall.fallTicks, heavenfall.recoveryTicks, heavenfall.pillarHeightMillimeters,
                          heavenfall.descentVelocityMillimetersPerTick, heavenfall.lightPerChargeTick,
                          heavenfall.level6LightPerChargeTick, heavenfall.level6DamageBonusBps, heavenfall.level6ComboGain,
                          heavenfall.level6CooldownMultiplierBps]) { try $0.int($1) }
        try writer.string(heavenfall.tranceTrigger.rawValue)
        try writer.optional(heavenfall.level6LightChargeRatio) { writer, ratio in
            try writer.int(ratio.numerator); try writer.int(ratio.denominator)
            try writer.bool(ratio.carryAcrossCasts); try writer.bool(ratio.discardRemainderAtCapacity)
        }
        try writer.optional(heavenfall.level6ComboGainTrigger) { try $0.string($1.rawValue) }
        try writer.array([earth.shardDamageBonusBps, earth.shardStunTicks, earth.splitterDamageBonusBps, earth.dreadTicks,
                          earth.dreadDamageTakenBonusBps, earth.dreadOutgoingReductionBps, earth.splitterWindCount,
                          earth.splitterWindIntervalTicks, earth.earthquakeWindowTicks, earth.boulderBonusWindowTicks]) { try $0.int($1) }
        try earth.landingShock.appendReplayState(to: &writer); try earth.boulderBonus.appendReplayState(to: &writer)
        try writer.array([ranged.maximumCharges, ranged.initialCharges, ranged.rechargeTicks, ranged.level5RechargeMultiplierBps,
                          trance.durationTicks, trance.attackSpeedBps, trance.incomingDamageMultiplierBps,
                          trance.extraComboChancePerMillion, trance.extraComboPoints,
                          heavyWindCount, typhoonWindCount, tranceWindCount,
                          level4PrimordialCooldownReductionTicks, level6PrimordialCooldownReductionTicks,
                          level6CooldownRecoveryBps]) { try $0.int($1) }
        try windBlade.appendReplayState(to: &writer)
        try writer.array([policies.blockedHitsCountCombo, policies.blockedPrimordialStartsRhythm,
                          policies.blockedSpearCanPin, policies.generatedHitsCountCombo, policies.generatedHitsRestoreLight,
                          policies.blockedDamageResetsCombo, policies.lightOnlyDamageResetsCombo,
                          policies.level6ReceivedHitRefreshesHold, policies.consumeRhythmOnSpearCast,
                          policies.windSourcesStack, policies.thresholdsUseComboBeforeContact,
                          policies.level6RecoveryAffectsTyphoon, policies.level4ReductionAffectsTyphoon,
                          policies.zeroCooldownClearsExisting,
                          policies.shieldRequiresPositiveLight, policies.interruptReleasesPetrification]) { try $0.bool($1) }
        try writer.string(policies.windTrigger.rawValue); try writer.string(policies.typhoonCooldownPriority.rawValue)
        try writer.string(policies.earthWindowTrigger.rawValue)
        try writer.string(policies.attackSpeedStacking.rawValue)
        try writer.optional(runtime) { try $1.appendReplayState(to: &$0) }
    }
}

extension DuelPanguRules.AttackSpec {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string(damageKind.rawValue); try writer.string(delivery.rawValue)
        try writer.array([damage, blockedDamage, rangeMillimeters, projectileSpeedMillimetersPerTick,
                          hitboxBottomMillimeters, hitboxTopMillimeters, radiusMillimeters,
                          stunTicks, airHoldTicks, hitStopTicks, blockedHitStopTicks]) { try $0.int($1) }
        try writer.bool(knocksDown)
        try writer.int(impact.distanceMillimeters); try writer.int(impact.durationTicks)
        try writer.int(impact.launchVelocityMillimetersPerTick); try writer.int(impact.gravityMillimetersPerTickSquared)
    }
}
