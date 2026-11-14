import Foundation

extension DuelPanguRules {
    /// Distinguishes the original hit tags. Several attacks share one button
    /// but have different Light gains, damage attributes and follow-ups.
    public enum SourceStrike: String, Codable, CaseIterable, Sendable {
        case shardLift, shardThrown, shardKick, splitter, upperWind, upperFall
        case bones, landingShock, spearInitial, spearFlight, normalSpear
        case windBlade, heavenfallAxe, heavenfallExplosion

        public var ability: Ability {
            switch self {
            case .shardLift, .shardThrown, .shardKick: return .shard
            case .splitter, .upperWind, .upperFall: return .splitter
            case .bones, .landingShock: return .bones
            case .spearInitial, .spearFlight, .normalSpear: return .spear
            case .windBlade: return .typhoon
            case .heavenfallAxe, .heavenfallExplosion: return .heavenfall
            }
        }
        public var damageKind: DamageKind {
            switch self {
            case .shardKick, .upperFall: return .unarmed
            case .splitter, .heavenfallAxe, .normalSpear: return .weapon
            default: return .shadow
            }
        }
        public var isWind: Bool { self == .windBlade || self == .upperWind }
        public var hasAbilityHitTag: Bool {
            [.shardLift, .shardThrown, .splitter, .bones, .heavenfallAxe].contains(self)
        }
        public var hasEmpoweredSpearTag: Bool { self == .spearInitial || self == .spearFlight }
        public var sourceAnimation: String {
            switch self {
            case .shardLift, .shardThrown: return "D19_Forward_Rock_Model_Attack"
            case .shardKick: return "D19_Forward"
            case .splitter: return "D19_Upper"
            case .upperWind: return "D19_Upper_Wind_Blade_Model_Attack"
            case .upperFall: return "D19_Up_Fall_Model_Attack"
            case .bones: return "D19_Low_Stones_Model_Attack"
            case .landingShock: return "D19_Low_Quake_Model_Attack"
            case .spearInitial: return "D19_Missile_Model_Create"
            case .spearFlight: return "D19_Missile_Model_Miss"
            case .normalSpear: return "D19_Missile_Model_Miss_No_Wall"
            case .windBlade: return "D19_Wind_Blade_Model_Attack"
            case .heavenfallAxe: return "D19_Ultimate"
            case .heavenfallExplosion: return "D19_Ultimate_Model_Attack"
            }
        }
    }

    /// Recovered normal-player D19 production rules. This stores ratios and
    /// named event ticks separately from application HP/stat/geometry scales.
    /// It is not a claim that missing dedicated D19 animation bytes were found.
    public struct RuntimeProfile: Codable, Equatable, Sendable {
        public var version: String
        public var configurationSHA256: String
        public var evidence: [String]
        public var unresolved: [String]
        public var tickRate: Int
        public var sourceFramesPerSecond: Int
        public var normalizedWeaponPower: Int
        public var normalizedUnarmedPower: Int
        public var normalizedMagicPower: Int
        public var normalizedRangedPower: Int
        public var comboMultiplierCapBps: Int
        public var spearEmpowerThreshold: Int
        public var heavenfallCooldownThreshold: Int
        public var spearLightGain: Int
        public var heavenfallLightGain: Int
        public var tranceDefenseBonusBps: Int
        public var windIntervalTicks: Int
        public var freezeStartTick: Int
        public var freezeEndTick: Int
        public var lightGainTick: Int
        public var axeHitTick: Int
        public var explosionTick: Int
        public var sourceShardStunExtensionTicks: Int

        func validate() throws {
            guard version == "user-ipa-1.46.1/config-1.46.0.16.16733-prod/D19",
                  configurationSHA256 == "02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a",
                  tickRate == 60, sourceFramesPerSecond == 30,
                  !evidence.isEmpty, evidence.count <= 24,
                  evidence.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }),
                  unresolved.count <= 16,
                  unresolved.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }) else { throw ValidationError.provenance }
            guard [normalizedWeaponPower, normalizedUnarmedPower, normalizedMagicPower, normalizedRangedPower]
                .allSatisfy({ (1...1_000_000).contains($0) }),
                  (10_000...1_250_000).contains(comboMultiplierCapBps),
                  (1...1_000_000).contains(spearEmpowerThreshold),
                  (1...1_000_000).contains(heavenfallCooldownThreshold),
                  (0...10_000).contains(spearLightGain), (0...10_000).contains(heavenfallLightGain),
                  (0...100_000).contains(tranceDefenseBonusBps),
                  (1...36_000).contains(windIntervalTicks),
                  0 < freezeStartTick, freezeStartTick < lightGainTick,
                  lightGainTick < axeHitTick, axeHitTick < explosionTick,
                  explosionTick < freezeEndTick, freezeEndTick <= 36_000,
                  (0...36_000).contains(sourceShardStunExtensionTicks) else { throw ValidationError.timing }
        }

        func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
            try writer.string(version); try writer.string(configurationSHA256)
            try writer.array(evidence) { try $0.string($1) }
            try writer.array(unresolved) { try $0.string($1) }
            try writer.array([tickRate, sourceFramesPerSecond, normalizedWeaponPower, normalizedUnarmedPower,
                normalizedMagicPower, normalizedRangedPower, comboMultiplierCapBps, spearEmpowerThreshold,
                heavenfallCooldownThreshold, spearLightGain, heavenfallLightGain, tranceDefenseBonusBps,
                windIntervalTicks, freezeStartTick, freezeEndTick, lightGainTick, axeHitTick, explosionTick,
                sourceShardStunExtensionTicks]) { try $0.int($1) }
        }
    }

    /// The explicit stat inputs are application damage normalizations, not
    /// raw MagicPower/WeaponDamage attributes (the original uses a power-delta
    /// formula). Geometry and unresolved full-clip tails stay adaptations.
    public static func d19HeavenlyKing(level: Int, maximumHealth: Int,
        weaponPower: Int, unarmedPower: Int, magicPower: Int, rangedPower: Int,
        spatialTemplate: Self) throws -> Self {
        guard (1...6).contains(level) else { throw ValidationError.level }
        guard [maximumHealth, weaponPower, unarmedPower, magicPower, rangedPower]
            .allSatisfy({ (1...1_000_000).contains($0) }) else { throw ValidationError.health }
        try spatialTemplate.validate()
        var value = spatialTemplate
        value.id = "d19-prod-14601616733-l\(level)"
        value.basis = .applicationAdaptation
        value.sourceVersion = "user-ipa-1.46.1/config-1.46.0.16.16733-prod/D19"
        value.sourceSHA256 = "02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a"
        value.evidence = [
            "collections.js:collection141/leveling1...6;sha256=27acd4f4e000b44806f2c19e8f49c4be08e0574298e0ce4be00015bd9f84ed6d",
            "split_battle_triggers:lock1544;sha256=ec56d114b475aa7546fb056595edcb167156e458423dbb82967a02a49f9351ca",
            "split_battle_triggers:lock1546;sha256=398e22eb17d605e6177a29d8dbf76ab704183b19cfcc784db100947e1909b7aa",
            "split_battle_triggers:lock1547-1557;lock1560-1562;common combo lock923/926",
            "split_animation_settings:settings_sets_dynasty.bytes/D19_Upper...D19_Unthrow_Passive",
            "native:25564/36942 core60Hz;39552 MidFrames+1;39602 interval frame-1;39182 AnimationEnd",
            "formulas.js:calculatePlayerDamage/calcInputFactor;sha256=3abce6e3729aabadc7a5ea18e4bef61c703d818cf204e7609dc0b12e5fc16b80",
            "native:23787/23800/157744/157745 normalized HP 0...1;source Light uses the same Hit.damage units",
            "Application supplies HP/attack scales, hit reactions, spatial template and missing dedicated motion tails"
        ]
        value.level = level; value.maximumHealth = maximumHealth
        value.runtime = .init(version: value.sourceVersion, configurationSHA256: value.sourceSHA256!,
            evidence: value.evidence, unresolved: [
                "Dedicated D19 owner clip frame counts remain unavailable. Input unlock ticks are source Uninterrupt ends; cast completion/Rhythm projection uses that boundary until exact animation-end samples are bound.",
                "Arena geometry, launch trajectory, pillar height and normalized damage scales are application adaptations.",
                "Generic ranged charge recharge time remains the explicit spatial-template adaptation; the D19 source establishes three charges and the level-5 multiplier.",
                "D19_FALL_DEBUFF reads a target-local damage multiplier; propagation from the caster is not yet proven and is not silently invented.",
                "Source shard stun begins after the target's current Uninterrupt phase; the adapter must supply reaction eligibility."
            ], tickRate: 60, sourceFramesPerSecond: 30,
            normalizedWeaponPower: weaponPower, normalizedUnarmedPower: unarmedPower,
            normalizedMagicPower: magicPower, normalizedRangedPower: rangedPower,
            comboMultiplierCapBps: 1_250_000, spearEmpowerThreshold: 75, heavenfallCooldownThreshold: 100,
            spearLightGain: 1000, heavenfallLightGain: level >= 6 ? 5000 : 2500,
            tranceDefenseBonusBps: 5000, windIntervalTicks: 10,
            freezeStartTick: 24, freezeEndTick: 250, lightGainTick: 140,
            axeHitTick: 242, explosionTick: 248, sourceShardStunExtensionTicks: 60)
        value.light.maximum = 10_000; value.light.initial = 0
        value.light.damageToLightNumerator = 1; value.light.damageToLightDenominator = 1
        value.light.absorbedKinds = [.weapon, .unarmed, .shadow]
        value.light.regularHitGain = level >= 5 ? 750 : level >= 3 ? 500 : 300
        value.light.primordialHitGain = level >= 6 ? 3500 : level >= 5 ? 2500 : 1500
        value.light.level3GainBonus = 0; value.light.level5PrimordialGainBonus = 0
        value.light.level5BlockedHitGain = value.light.regularHitGain
        // A bounded application counter; the original damage formula itself
        // caps min(125, 1 + combo * .01), not the displayed combo at 125.
        value.combo.maximum = 1_000_000; value.combo.pointsPerHit = 1
        value.combo.holdTicks = 255; value.combo.level6HoldTicks = 435
        value.combo.damageBonusPerPointBps = 100; value.combo.maximumDamageBonusBps = 1_240_000
        value.combo.affectedKinds = [.weapon, .unarmed, .shadow]
        // The executable PostHit comparisons are strict >, despite rounded
        // display thresholds. Spear upgrade and ultimate CD use separate >=.
        value.combo.heavyWindThreshold = 16; value.combo.allAttackWindThreshold = 31
        value.combo.level4SpeedThreshold = 56; value.combo.rangedThreshold = 76
        value.combo.zeroCooldownThreshold = 101; value.combo.level4AttackSpeedBps = 11_250
        value.typhoon.durationTicks = 600; value.typhoon.fixedCooldownTicks = 600
        value.typhoon.damageBonusBps = 5000; value.typhoon.lightCostReductionBps = 5000
        value.typhoon.stormGateUsesPerCycle = 1
        value.hunt.durationTicks = 300; value.hunt.pinTicks = 186
        value.hunt.empoweredSpear.damage = magicPower * 4500 / 10_000
        value.hunt.empoweredSpear.blockedDamage = 0
        value.heavenfall.petrifyPhaseTicks = 24; value.heavenfall.targetPetrifyTicks = 226
        value.heavenfall.riseTicks = 116; value.heavenfall.chargeTicks = 102
        value.heavenfall.fallTicks = 6; value.heavenfall.recoveryTicks = 72
        value.heavenfall.descentVelocityMillimetersPerTick = (value.heavenfall.pillarHeightMillimeters + 5) / 6
        value.heavenfall.lightPerChargeTick = 0; value.heavenfall.level6LightPerChargeTick = 0
        value.heavenfall.level6LightChargeRatio = nil
        value.heavenfall.level6DamageBonusBps = 5000; value.heavenfall.level6ComboGain = 25
        value.heavenfall.level6CooldownMultiplierBps = 5000
        value.heavenfall.tranceTrigger = .landing
        value.earth.shardDamageBonusBps = 2500; value.earth.shardStunTicks = 90
        value.earth.splitterDamageBonusBps = 0
        // The value .5 exists, but the victim-local variable read must not be
        // replaced with a guessed transfer from the caster.
        value.earth.dreadTicks = 600; value.earth.dreadDamageTakenBonusBps = 0
        value.earth.dreadOutgoingReductionBps = 0
        value.earth.splitterWindCount = 5; value.earth.splitterWindIntervalTicks = 10
        value.earth.earthquakeWindowTicks = 540; value.earth.boulderBonusWindowTicks = 540
        value.earth.landingShock.damage = magicPower * 1500 / 10_000
        value.earth.landingShock.blockedDamage = 0
        value.earth.boulderBonus.damage = unarmedPower * 2500 / 10_000
        value.earth.boulderBonus.blockedDamage = 0
        value.ranged.maximumCharges = 3; value.ranged.initialCharges = 3
        value.ranged.level5RechargeMultiplierBps = 20_000
        value.trance.durationTicks = 900; value.trance.attackSpeedBps = 11_250
        // Display only: runtime divides by the exact 1 + defense bonus.
        value.trance.incomingDamageMultiplierBps = 6666
        value.trance.extraComboChancePerMillion = 330_000; value.trance.extraComboPoints = 1
        value.windBlade.damage = magicPower * 2500 / 10_000; value.windBlade.blockedDamage = 0
        value.heavyWindCount = 1; value.typhoonWindCount = 1; value.tranceWindCount = 1
        value.level4PrimordialCooldownReductionTicks = 0; value.level6PrimordialCooldownReductionTicks = 0
        value.level6CooldownRecoveryBps = 10_000
        value.policies.blockedHitsCountCombo = false; value.policies.generatedHitsCountCombo = true
        value.policies.generatedHitsRestoreLight = true; value.policies.blockedDamageResetsCombo = true
        value.policies.lightOnlyDamageResetsCombo = true; value.policies.level6ReceivedHitRefreshesHold = false
        value.policies.consumeRhythmOnSpearCast = false; value.policies.windTrigger = .confirmedContact
        value.policies.windSourcesStack = true; value.policies.thresholdsUseComboBeforeContact = false
        value.policies.typhoonCooldownPriority = .fixedWins
        value.policies.level6RecoveryAffectsTyphoon = false; value.policies.level4ReductionAffectsTyphoon = false
        value.policies.zeroCooldownClearsExisting = false; value.policies.shieldRequiresPositiveLight = true
        value.policies.earthWindowTrigger = .castReleased; value.policies.attackSpeedStacking = .additive
        for i in value.abilities.indices {
            let ability = value.abilities[i].ability
            value.abilities[i].lightCost = 0
            value.abilities[i].cooldownTicks = ability == .heavenfall ? 1200 :
                ability == .typhoon ? 600 : ability == .spear || ability == .stormGate ? 0 :
                level >= 6 ? 480 : level >= 4 ? 540 : 600
            value.abilities[i].damageImmune = false
            value.abilities[i].interruptible = ability != .heavenfall
            let startup: Int, active: Int, duration: Int, damage: Int, kind: DamageKind, delivery: Delivery
            switch ability {
            case .shard: startup = 56; active = 8; duration = 110; damage = magicPower * 5500 / 10_000; kind = .shadow; delivery = .projectile
            case .typhoon: startup = 42; active = 1; duration = 80; damage = 0; kind = .shadow; delivery = .ground
            case .splitter: startup = 38; active = 8; duration = 126; damage = weaponPower * 5500 / 10_000; kind = .weapon; delivery = .melee
            case .bones: startup = 42; active = 1; duration = 94; damage = magicPower * 4500 / 10_000; kind = .shadow; delivery = .ground
            case .spear: startup = 46; active = 50; duration = 100; damage = rangedPower * 2000 / 10_000; kind = .weapon; delivery = .projectile
            case .heavenfall: startup = 242; active = 8; duration = 320; damage = magicPower; kind = .shadow; delivery = .ground
            case .stormGate: startup = 34; active = 1; duration = 62; damage = 0; kind = .shadow; delivery = .ground
            }
            value.abilities[i].startupTicks = startup; value.abilities[i].activeTicks = active
            value.abilities[i].recoveryTicks = duration - startup - active
            value.abilities[i].attack.damage = damage; value.abilities[i].attack.blockedDamage = 0
            value.abilities[i].attack.damageKind = kind; value.abilities[i].attack.delivery = delivery
        }
        try value.validate()
        return value
    }
}
