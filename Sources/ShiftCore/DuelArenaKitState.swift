import Foundation

/// Pure-integer 60 Hz deterministic combat states for the remaining three
/// Shadow Fight 4: Arena-inspired playable heroes:
/// - Xu Xiao (.gale): Grand Inquisitor (Power of Light, Salvation Pillar, Stigmata, Form of Light)
/// - Liu Quanwei (.liu): Nonna (Unbreakable Great Axe, Spirit Wolf, Spirit Owl, Flame Form & True Shape)
/// - Sun Deng (.ember): Midnight (Shadow Shift vanish, Precise Shift, Blink counter, Removal execute)
public enum DuelArenaKitState: Equatable, Sendable {
    case inquisitor(DuelInquisitorState)
    case nonna(DuelNonnaState)
    case midnight(DuelMidnightState)
    case emperor(DuelEmperorState)
    case legionKing(DuelLegionKingState)
    case monkeyKing(DuelMonkeyKingState)

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        switch self {
        case .inquisitor(let state):
            try writer.u8(1)
            try state.appendReplayState(to: &writer)
        case .nonna(let state):
            try writer.u8(2)
            try state.appendReplayState(to: &writer)
        case .midnight(let state):
            try writer.u8(3)
            try state.appendReplayState(to: &writer)
        case .emperor(let state):
            try writer.u8(4)
            try state.appendReplayState(to: &writer)
        case .legionKing(let state):
            try writer.u8(5)
            try state.appendReplayState(to: &writer)
        case .monkeyKing(let state):
            try writer.u8(6)
            try state.appendReplayState(to: &writer)
        }
    }
}

// MARK: - Xu Xiao (Grand Inquisitor Ingvar / 大审判官)

public struct DuelInquisitorState: Equatable, Sendable {
    public static let maxLightPower = 100
    public static let formOfLightDurationTicks = 300
    public static let entryInvulnerableTicks = 18
    public static let stigmataDurationTicks = 120
    public static let stigmataBaseDamage = 115
    public static let stigmataHitBonusDamage = 20
    public static let stigmataEnergyBurn = 25
    public static let salvationHeal = 45
    public static let rangedCooldownTicks = 270
    public static let deliveranceCooldownTicks = 300
    public static let salvationEchoDelayTicks = 32
    public static let salvationEchoDamage = 80
    public static let maxBlessings = 12
    public static let martyrdomThresholdHP = 250
    public static let martyrdomRestoreDuration = 60
    public static let salvationTelegraphTicks = 12
    public static let salvationPillarRadius = 820

    public var lightPower: Int = 0
    public var formOfLightTicks: Int = 0
    public var stigmataTicks: Int = 0
    public var stigmataHits: Int = 0
    public var blessings: Int = 0
    public var martyrdomUsed: Bool = false
    public var martyrdomRestoreTicks: Int = 0
    public var rangedCooldown: Int = 0
    public var deliveranceCooldown: Int = 0
    public var salvationEchoTicks: Int = 0
    public var salvationEchoX: Int = 0
    public var salvationCastTicks: Int = 0
    public var salvationCastX: Int = 0

    public init() {}

    public var isInFormOfLight: Bool { formOfLightTicks > 0 }
    public var canEnterFormOfLight: Bool { formOfLightTicks == 0 && lightPower >= Self.maxLightPower }
    public var hasStigmataOnOpponent: Bool { stigmataTicks > 0 }
    public var canCastSalvation: Bool { rangedCooldown == 0 && salvationCastTicks == 0 }
    public var canCastDeliverance: Bool { deliveranceCooldown == 0 }

    public mutating func gainLight(_ amount: Int) {
        guard amount > 0 else { return }
        lightPower = min(Self.maxLightPower, lightPower + amount)
    }

    public mutating func enterFormOfLight() {
        lightPower = Self.maxLightPower
        formOfLightTicks = Self.formOfLightDurationTicks
    }

    public mutating func knockOutOfFormOfLight() {
        guard formOfLightTicks > 0 else { return }
        formOfLightTicks = 0
        lightPower = lightPower / 2
    }

    public mutating func applyStigmata() {
        stigmataTicks = Self.stigmataDurationTicks
        stigmataHits = 0
        blessings = min(Self.maxBlessings, blessings + 1)
    }

    public mutating func dispelStigmata() {
        stigmataTicks = 0
        stigmataHits = 0
    }

    public var stigmataFlashDamage: Int {
        Self.stigmataBaseDamage + min(6, stigmataHits) * Self.stigmataHitBonusDamage
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(lightPower)
        try writer.int(formOfLightTicks)
        try writer.int(stigmataTicks)
        try writer.int(stigmataHits)
        try writer.int(blessings)
        try writer.bool(martyrdomUsed)
        try writer.int(martyrdomRestoreTicks)
        try writer.int(rangedCooldown)
        try writer.int(deliveranceCooldown)
        try writer.int(salvationEchoTicks)
        try writer.int(salvationEchoX)
        try writer.int(salvationCastTicks)
        try writer.int(salvationCastX)
    }
}

// MARK: - Liu Quanwei (Nonna / 诺娜 · 花焰巨斧)

public struct DuelNonnaState: Equatable, Sendable {
    public enum OwlPhase: UInt8, Codable, Equatable, Sendable {
        case idle = 0
        case outbound = 1
        case latched = 2
        case returning = 3
    }

    public static let maxFlamePower = 100
    public static let flameFormMinPower = 30
    public static let flameFormMaxTicks = 240
    public static let executeThresholdHP = 250
    public static let hotBloodThresholdHP = 350
    public static let wolfSpeed = 145
    public static let wolfDamage = 105
    public static let wolfFlameGain = 22
    public static let wolfMaxTicks = 64
    public static let owlSpeed = 155
    public static let owlOutDamage = 75
    public static let owlReturnDamage = 70
    public static let owlReturnStunTicks = 42
    public static let owlLatchMaxTicks = 45
    public static let owlCooldownTicks = 210
    public static let maxRunesOfAsh = 6
    public static let ancientFuryDurationTicks = 240
    public static let spiritHealPermille = 60

    public var flamePower: Int = 0
    public var flameFormTicks: Int = 0
    public var flameEntryPower: Int = 0
    public var empoweredStrikeReady: Bool = false
    public var attackSeriesCount: Int = 0
    public var runesOfAsh: Int = 0
    public var ancientFuryTicks: Int = 0

    // Blazing Hunt autonomous Spirit Wolf (花焰灵狼).
    public var wolfActive: Bool = false
    public var wolfX: Int = 0
    public var wolfFacing: Int = 1
    public var wolfTimer: Int = 0
    public var wolfHitApplied: Bool = false

    // Fire Grip flying Spirit Owl (灵枭).
    public var owlPhase: OwlPhase = .idle
    public var owlX: Int = 0
    public var owlFacing: Int = 1
    public var owlTimer: Int = 0
    public var owlCooldown: Int = 0
    public var owlHitOut: Bool = false
    public var owlHitBack: Bool = false

    public init() {}

    public var isInFlameForm: Bool { flameFormTicks > 0 }
    public var isAncientFuryActive: Bool { ancientFuryTicks > 0 }
    public var canEnterFlameForm: Bool { flameFormTicks == 0 && flamePower >= Self.flameFormMinPower }
    public var canLaunchOwl: Bool { owlPhase == .idle && owlCooldown == 0 }
    public var breaksBlockNow: Bool { flameFormTicks > 0 || empoweredStrikeReady }

    public mutating func gainFlame(_ amount: Int) {
        guard amount > 0 else { return }
        flamePower = min(Self.maxFlamePower, flamePower + amount)
    }

    public mutating func gainRuneOfAsh() {
        runesOfAsh = min(Self.maxRunesOfAsh, runesOfAsh + 1)
    }

    public mutating func enterFlameForm() {
        flameEntryPower = flamePower
        flameFormTicks = max(90, (flamePower * Self.flameFormMaxTicks) / Self.maxFlamePower)
        empoweredStrikeReady = false
    }

    public mutating func summonWolf(from ownerX: Int, facing: Int) {
        wolfActive = true
        wolfX = min(DuelGame.rightWall, max(DuelGame.leftWall, ownerX + facing * 360))
        wolfFacing = facing
        wolfTimer = 0
        wolfHitApplied = false
        attackSeriesCount = 0
        gainRuneOfAsh()
    }

    public mutating func launchOwl(from ownerX: Int, facing: Int) {
        owlPhase = .outbound
        owlX = min(DuelGame.rightWall, max(DuelGame.leftWall, ownerX + facing * 420))
        owlFacing = facing
        owlTimer = 0
        owlHitOut = false
        owlHitBack = false
        gainRuneOfAsh()
    }

    public mutating func recallOwl() {
        guard owlPhase == .latched || owlPhase == .outbound else { return }
        owlPhase = .returning
        owlTimer = 0
        owlHitBack = false
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(flamePower)
        try writer.int(flameFormTicks)
        try writer.int(flameEntryPower)
        try writer.bool(empoweredStrikeReady)
        try writer.int(attackSeriesCount)
        try writer.int(runesOfAsh)
        try writer.int(ancientFuryTicks)
        try writer.bool(wolfActive)
        try writer.int(wolfX)
        try writer.int(wolfFacing)
        try writer.int(wolfTimer)
        try writer.bool(wolfHitApplied)
        try writer.u8(owlPhase.rawValue)
        try writer.int(owlX)
        try writer.int(owlFacing)
        try writer.int(owlTimer)
        try writer.int(owlCooldown)
        try writer.bool(owlHitOut)
        try writer.bool(owlHitBack)
    }
}

// MARK: - Sun Deng (Midnight / 午夜 · 影移双刃)

public struct DuelMidnightState: Equatable, Sendable {
    public static let maxShadowEnergy = 100
    public static let shadowShiftDurationTicks = 42
    public static let preciseShiftSpeed = 102
    public static let dodgeShadowReward = 30
    public static let whiffShadowReward = 22
    public static let rangedCooldownTicks = 240
    public static let kunaiDamage = 75
    public static let blinkShadowCost = 50
    public static let blinkStanceDurationTicks = 28
    public static let blinkCounterDamage = 150
    public static let blinkCounterHeal = 95
    public static let blinkCounterHealPermille = 180
    public static let blinkCounterFreezeTicks = 28
    public static let blinkCounterShadowReward = 35
    public static let blinkCooldownTicks = 120
    public static let removalDamage = 245
    public static let corneredBeastThresholdPermille = 350
    public static let shadowFormDurationTicks = 180
    public static let maxNocturneCharges = 4

    public var shadowEnergy: Int = 0
    public var shadowShiftTicks: Int = 0
    public var shadowFormTicks: Int = 0
    public var blinkStanceTicks: Int = 0
    public var blinkCooldown: Int = 0
    public var shiftDodgeRewarded: Bool = false
    public var rangedCooldown: Int = 0
    public var nocturneCharges: Int = 0

    public init() {}

    public var isPhasedOut: Bool { shadowShiftTicks > 0 }
    public var isInShadowForm: Bool { shadowFormTicks > 0 }
    public var isInBlinkStance: Bool { blinkStanceTicks > 0 }
    public var isNocturneReady: Bool { nocturneCharges >= Self.maxNocturneCharges }
    public var canUseRemoval: Bool { shadowEnergy >= Self.maxShadowEnergy }
    public var canUseBlink: Bool { blinkCooldown == 0 && shadowEnergy >= Self.blinkShadowCost }
    public var canCastKunai: Bool { rangedCooldown == 0 }

    public mutating func gainShadow(_ amount: Int) {
        guard amount > 0 else { return }
        shadowEnergy = min(Self.maxShadowEnergy, shadowEnergy + amount)
    }

    public mutating func enterShadowShift() {
        shadowShiftTicks = Self.shadowShiftDurationTicks
        shiftDodgeRewarded = false
        nocturneCharges = min(Self.maxNocturneCharges, nocturneCharges + 1)
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(shadowEnergy)
        try writer.int(shadowShiftTicks)
        try writer.int(shadowFormTicks)
        try writer.int(blinkStanceTicks)
        try writer.int(blinkCooldown)
        try writer.bool(shiftDodgeRewarded)
        try writer.int(rangedCooldown)
        try writer.int(nocturneCharges)
    }
}

// MARK: - Liu Quanwei (Emperor / 暗影君主 <-> 暗影兽)

public struct DuelEmperorState: Equatable, Sendable {
    public static let maxShadowEnergy = 100
    public static let rangedCooldownTicks = 180
    public static let beastHitLifestealHP = DuelEmperorPhase2.CombatParameters.standard.beastClawHitLifestealHP
    public static let beastGuardLifestealHP = DuelEmperorPhase2.CombatParameters.standard.beastClawGuardLifestealHP
    public static let transformBurstRadius = 2650
    public static let transformBurstDamage = 105
    public static let rangedBurstDamage = 68
    public static let beastShadowExplosionDamage = 155

    public var shadowEnergy: Int = 0
    public var isBeastForm: Bool = false
    public var rangedCooldown: Int = 0
    public var transformBurstTicks: Int = 0
    public var lifestealTotalHP: Int = 0

    public init() {}

    public var canTransformToBeast: Bool { !isBeastForm && shadowEnergy >= Self.maxShadowEnergy }
    public var canCastBeastShadow: Bool { isBeastForm && shadowEnergy >= Self.maxShadowEnergy }
    public var canCastRanged: Bool { rangedCooldown == 0 }

    public mutating func gainShadow(_ amount: Int) {
        guard amount > 0 else { return }
        shadowEnergy = min(Self.maxShadowEnergy, shadowEnergy + amount)
    }

    public mutating func completeTransformation() {
        isBeastForm = true
        shadowEnergy = 0
        transformBurstTicks = 28
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(shadowEnergy)
        try writer.bool(isBeastForm)
        try writer.int(rangedCooldown)
        try writer.int(transformBurstTicks)
        try writer.int(lifestealTotalHP)
    }
}

// MARK: - Xu Xiao (King of the Legion / 军团之王 · 巨剑与3D暗影锁链)

public struct DuelLegionKingState: Equatable, Sendable {
    public static let maxShadowEnergy = 100
    public static let chainCooldownTicks = 210
    public static let chainMaxReach = 4350
    public static let chainPullDistance = 1066
    public static let chainLiftVelocityY = 175
    public static let chainHitDamage = 64
    public static let darkIncarnationReviveHP = DuelLegionKingPhase3.CombatParameters.standard.darkIncarnationReviveHP
    public static let darkIncarnationNovaPush = 1450
    public static let darkIncarnationInvulnerableTicks = 42
    public static let shadowEmpoweredDurationTicks = 360

    public var shadowEnergy: Int = 0
    public var hasRevivedThisRound: Bool = false
    public var reviveAnimTicks: Int = 0
    public var chainCooldown: Int = 0
    public var chainActiveTicks: Int = 0
    public var chainTargetX: Int = 0
    public var chainSnagged: Bool = false
    public var shadowEmpoweredTicks: Int = 0

    public init() {}

    public var isInDarkIncarnation: Bool { hasRevivedThisRound }
    public var isShadowEmpowered: Bool { shadowEmpoweredTicks > 0 }
    public var canCastChain: Bool { chainCooldown == 0 && chainActiveTicks == 0 }
    public var canCastShadowAbility: Bool { shadowEnergy >= Self.maxShadowEnergy }

    public mutating func gainShadow(_ amount: Int) {
        guard amount > 0 else { return }
        shadowEnergy = min(Self.maxShadowEnergy, shadowEnergy + amount)
    }

    public mutating func triggerDarkIncarnation() {
        hasRevivedThisRound = true
        reviveAnimTicks = Self.darkIncarnationInvulnerableTicks
        shadowEmpoweredTicks = Self.shadowEmpoweredDurationTicks
        gainShadow(50)
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(shadowEnergy)
        try writer.bool(hasRevivedThisRound)
        try writer.int(reviveAnimTicks)
        try writer.int(chainCooldown)
        try writer.int(chainActiveTicks)
        try writer.int(chainTargetX)
        try writer.bool(chainSnagged)
        try writer.int(shadowEmpoweredTicks)
    }
}

// MARK: - Sun Deng (Monkey King / 齐天大圣 · 如意金箍棒与腾云攀棍)

public struct DuelMonkeyKingState: Equatable, Sendable {
    public static let maxShadowEnergy = 100
    public static let ascensionMaxTicks = 150
    public static let ascensionCooldownTicks = 180
    public static let ascensionPerchHeightMM = 2120
    public static let heavenlyAuraDurationTicks = 240
    public static let plungeDamage = 104
    public static let pillarSlamDamage = 122

    public var shadowEnergy: Int = 0
    public var ascensionTicks: Int = 0
    public var ascensionCooldown: Int = 0
    public var pillarX: Int = 0
    public var pillarShowTicks: Int = 0
    public var heavenlyAuraTicks: Int = 0

    public init() {}

    public var isPerchedOnPillar: Bool { ascensionTicks > 0 }
    public var hasHeavenlyAura: Bool { heavenlyAuraTicks > 0 }
    public var canEnterAscension: Bool { ascensionTicks == 0 && ascensionCooldown == 0 }
    public var canCastHeavenlyPillar: Bool { isPerchedOnPillar || shadowEnergy >= Self.maxShadowEnergy }

    public mutating func gainShadow(_ amount: Int) {
        guard amount > 0 else { return }
        shadowEnergy = min(Self.maxShadowEnergy, shadowEnergy + amount)
    }

    public mutating func enterAscension(at x: Int) {
        ascensionTicks = Self.ascensionMaxTicks
        ascensionCooldown = Self.ascensionCooldownTicks
        pillarX = x
        pillarShowTicks = Self.ascensionMaxTicks + 24
    }

    public mutating func exitAscension(keepPillarTicks: Int = 18) {
        ascensionTicks = 0
        pillarShowTicks = max(pillarShowTicks, keepPillarTicks)
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(shadowEnergy)
        try writer.int(ascensionTicks)
        try writer.int(ascensionCooldown)
        try writer.int(pillarX)
        try writer.int(pillarShowTicks)
        try writer.int(heavenlyAuraTicks)
    }
}
