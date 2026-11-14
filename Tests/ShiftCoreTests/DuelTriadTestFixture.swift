import Foundation
@testable import ShiftCore

/// Small integer application fixtures exercise boundaries, never original DFT
/// balance. No source-game media, plaintext localization or retail numbers.
enum DuelTriadTestFixture {
    /// Recovered source ratios with explicitly synthetic arena/stat inputs.
    static func runtimeRules(level: Int = 6) throws -> DuelTriadRules {
        try .h17BlackNinjato(level: level, maximumHealth: 900, magicPower: 1000,
                            spatialTemplate: rules(level: level))
    }

    static func rules(level: Int = 6) -> DuelTriadRules {
        var value = DuelTriadRules.debug(level: level)
        value.id = "synthetic-triad-state-tests"
        value.level1ShadowBonusBps = 0
        value.mist.maximum = 1000; value.mist.initial = 500
        value.mist.suppressedHitGain = 5; value.mist.gainDurationTicks = 4
        value.mist.level5GainBonusBps = 0; value.mist.feastGain = 100
        value.forest.curseChanceBps = 10_000; value.forest.stunTicks = 2
        value.forest.debuffTicks = 5; value.forest.curseMistGain = 7
        value.forest.physicalReductionBps = 2000; value.forest.triggerCooldownTicks = 0
        value.suppression.durationTicks = 8; value.suppression.totalTrueDamage = 5
        value.suppression.maximumStacks = 3; value.suppression.outgoingReductionPerStackBps = 1000
        value.suppression.maximumOutgoingReductionBps = 3000
        value.blade.durationTicks = 6; value.blade.weaponBonusBps = 2000
        value.blade.shadowConversionBps = 2500; value.blade.waveAndSoulBonusBps = 5000
        value.blade.doubleWaveDelayTicks = 1; value.blade.chainWindowTicks = 30
        value.branches.holdTicks = 6; value.branches.pulseIntervalTicks = 2
        value.branches.pulseDamage = 10; value.branches.escapingBurstDamage = 40
        value.branches.suppressedDamageBonusBps = 2000; value.branches.rootedSoulBonusBps = 5000
        value.branches.entangledHoldReductionTicks = 2
        value.souls.hungryDeflectCooldownTicks = 5; value.souls.poisonDurationTicks = 4
        value.souls.poisonDamageBps = 5000; value.souls.maximumPoisonStacks = 2
        value.souls.forestRainCount = 3; value.souls.forestRainIntervalTicks = 2
        value.souls.danceCount = 3; value.souls.danceIntervalTicks = 2
        value.souls.notchCost = 3; value.souls.maximumNotches = 8
        for i in value.abilities.indices {
            let kind = value.abilities[i].ability
            value.abilities[i].startupTicks = 1
            value.abilities[i].activeTicks = kind == .cryingDance ? 5 : 1
            value.abilities[i].recoveryTicks = 1
            value.abilities[i].cooldownTicks = kind.soul == nil ? 0 : 5
            value.abilities[i].mistCost = kind.soul == nil ? 0 : 10
            value.abilities[i].attack?.damage = kind == .branches ? 0 : 20
            value.abilities[i].attack?.blockedDamage = kind == .branches ? 0 : 4
            value.abilities[i].attack?.lifetimeTicks = 40
            value.abilities[i].attack?.stunTicks = 2
        }
        return value
    }
}
