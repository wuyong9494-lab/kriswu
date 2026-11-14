import Foundation
@testable import ShiftCore

/// Deliberately synthetic unit-test quantities. These are not Nekki data,
/// reference measurements, a retail balance preset, or a playable catalog item.
enum DuelPanguTestFixture {
    static func attack(kind: DuelPanguRules.DamageKind = .shadow, damage: Int = 20,
                       delivery: DuelPanguRules.Delivery = .projectile) -> DuelPanguRules.AttackSpec {
        .init(damageKind: kind, damage: damage, blockedDamage: 2, delivery: delivery,
              rangeMillimeters: 4000, projectileSpeedMillimetersPerTick: 100,
              hitboxBottomMillimeters: 200, hitboxTopMillimeters: 1700, radiusMillimeters: 100,
              impact: .init(distanceMillimeters: 60, durationTicks: 3),
              stunTicks: 0, airHoldTicks: 0, knocksDown: false, hitStopTicks: 3, blockedHitStopTicks: 1)
    }

    static func rules(level: Int = 6) -> DuelPanguRules {
        let abilities = DuelPanguRules.Ability.allCases.map { ability in
            DuelPanguRules.AbilityRule(ability: ability, cooldownTicks: 12, lightCost: 5,
                                      startupTicks: 2, activeTicks: 1, recoveryTicks: 2,
                                      interruptible: true, damageImmune: false,
                                      attack: attack(kind: ability == .splitter ? .weapon : .shadow,
                                                     delivery: ability == .bones || ability == .heavenfall ? .ground : .projectile))
        }
        return .init(
            id: "test-only-pangu-v1", basis: .applicationAdaptation, sourceVersion: "synthetic-tests-only",
            sourceSHA256: nil, evidence: ["Artificial values for deterministic unit tests; no retail claim."], level: level,
            maximumHealth: 1000,
            light: .init(maximum: 100, initial: 80, damageToLightNumerator: 3, damageToLightDenominator: 2,
                         absorbedKinds: [.weapon, .unarmed, .shadow], regularHitGain: 4, primordialHitGain: 7,
                         level3GainBonus: 2, level5BlockedHitGain: 3, level5PrimordialGainBonus: 0),
            combo: .init(maximum: 30, pointsPerHit: 1, holdTicks: 20, level6HoldTicks: 40,
                         damageBonusPerPointBps: 1000, maximumDamageBonusBps: 5000,
                         affectedKinds: [.weapon, .unarmed, .shadow], heavyWindThreshold: 2,
                         allAttackWindThreshold: 3, rangedThreshold: 4, zeroCooldownThreshold: 6,
                         level4SpeedThreshold: 5, level4AttackSpeedBps: 12_500),
            abilities: abilities,
            typhoon: .init(durationTicks: 20, fixedCooldownTicks: 40, damageBonusBps: 2000,
                           lightCostReductionBps: 5000, stormGateUsesPerCycle: 1, stormGateBehindMillimeters: 600),
            hunt: .init(durationTicks: 12, empoweredSpear: attack(damage: 35), pinTicks: 7),
            heavenfall: .init(petrifyPhaseTicks: 2, targetPetrifyTicks: 9, riseTicks: 2, chargeTicks: 3,
                              fallTicks: 2, recoveryTicks: 2, pillarHeightMillimeters: 1800,
                              descentVelocityMillimetersPerTick: 900, lightPerChargeTick: 2,
                              level6LightPerChargeTick: 4, level6DamageBonusBps: 2500,
                              level6ComboGain: 2, level6CooldownMultiplierBps: 5000, tranceTrigger: .landing),
            earth: .init(shardDamageBonusBps: 2500, shardStunTicks: 5, splitterDamageBonusBps: 1500,
                         dreadTicks: 8, dreadDamageTakenBonusBps: 2000, dreadOutgoingReductionBps: 3000,
                         splitterWindCount: 3, splitterWindIntervalTicks: 2,
                         earthquakeWindowTicks: 14, boulderBonusWindowTicks: 10,
                         landingShock: attack(damage: 10, delivery: .landingShock),
                         boulderBonus: attack(kind: .unarmed, damage: 8, delivery: .melee)),
            ranged: .init(maximumCharges: 2, initialCharges: 2, rechargeTicks: 10, level5RechargeMultiplierBps: 20_000),
            trance: .init(durationTicks: 15, attackSpeedBps: 15_000, incomingDamageMultiplierBps: 5000,
                          extraComboChancePerMillion: 500_000, extraComboPoints: 2),
            windBlade: attack(damage: 6, delivery: .windBlade), heavyWindCount: 1, typhoonWindCount: 2,
            tranceWindCount: 3, level4PrimordialCooldownReductionTicks: 0,
            level6PrimordialCooldownReductionTicks: 0, level6CooldownRecoveryBps: 10_000,
            policies: .init(blockedHitsCountCombo: false, blockedPrimordialStartsRhythm: false,
                            blockedSpearCanPin: false, generatedHitsCountCombo: false,
                            generatedHitsRestoreLight: false, blockedDamageResetsCombo: false,
                            lightOnlyDamageResetsCombo: true, level6ReceivedHitRefreshesHold: false,
                            consumeRhythmOnSpearCast: true, windTrigger: .confirmedContact,
                            windSourcesStack: false, thresholdsUseComboBeforeContact: true,
                            typhoonCooldownPriority: .fixedWins, level6RecoveryAffectsTyphoon: false,
                            level4ReductionAffectsTyphoon: false,
                            zeroCooldownClearsExisting: false, shieldRequiresPositiveLight: true,
                            earthWindowTrigger: .confirmedContact, interruptReleasesPetrification: true,
                            attackSpeedStacking: .maximum))
    }
}
