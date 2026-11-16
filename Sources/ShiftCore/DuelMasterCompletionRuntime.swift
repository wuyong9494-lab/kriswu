import Foundation

public struct DuelSerpentMasterRuntime: Equatable, Sendable {
    public static let bloomOverloadClipName = "Set_Legion_3_Shadow_Form_In"
    public static let bloomOverloadSourceFrames = 54
    public static let bloomOverloadMarkerTick = 54
    public static let bloomOverloadEndTick = 98
    public static let fifthBloomPoisonAmount = 0.66
    public static let fifthBloomPoisonDurationTicks = 420
    public static let shadowPoisonDurationTicks = 900
    public static let shadowBurnIntervalTicks = 10
    public static let shadowBurnDeltaPerPulse = -1.0
    public static let fallReactionPhysicsTicks = 30
    public static let fallReactionCooldownTicks = 180
    public static let helmetArmorSelfCooldownTicks = 720
    public static let helmetArmorPairLockTicks = 360
    public static let puddleDurationTicks = 900
    public static let witherDistanceThresholdMM = 300.0
    public static let witherGainIntervalTicks = 60
    public static let witherDecayIntervalTicks = 20
    public static let maxWitherStacks = 40

    public private(set) var level: Int
    public private(set) var bloom: Double
    public private(set) var fifthBloomPoisonAmount: Double
    public private(set) var fifthBloomPoisonTicksRemaining: Int
    public private(set) var witherStacks: Int
    private var witherProximityTicks: Int
    private var witherOutsideTicks: Int
    public private(set) var unarmedPoisonBuffActive: Bool
    public private(set) var victimPhysicsTicksRemaining: Int
    public private(set) var victimFallCooldownRemaining: Int
    public private(set) var delayedFallDamagePending: Double
    public private(set) var shadowPoisonTicksRemaining: Int
    public private(set) var targetShadowEnergy: Double
    public private(set) var targetShadowFormActive: Bool

    public init(level: Int = 6, initialBloom: Double = 0.0, targetShadowEnergy: Double = 1.0) {
        self.level = max(1, min(6, level))
        self.bloom = max(0.0, min(1.0, initialBloom))
        self.fifthBloomPoisonAmount = 0.0
        self.fifthBloomPoisonTicksRemaining = 0
        self.witherStacks = 0
        self.witherProximityTicks = 0
        self.witherOutsideTicks = 0
        self.unarmedPoisonBuffActive = false
        self.victimPhysicsTicksRemaining = 0
        self.victimFallCooldownRemaining = 0
        self.delayedFallDamagePending = 0.0
        self.shadowPoisonTicksRemaining = 0
        self.targetShadowEnergy = max(0.0, min(1.0, targetShadowEnergy))
        self.targetShadowFormActive = false
    }

    public var witherAuraActive: Bool { level >= 4 && bloom >= 0.33 }
    public var empowermentActive: Bool { level >= 4 && bloom >= 0.66 }
    public var suppressesTargetShadowGain: Bool { shadowPoisonTicksRemaining > 0 }
    public var victimInPhysicsWindow: Bool { victimPhysicsTicksRemaining > 0 }

    public mutating func triggerRoundFightStartFifthPoison() {
        fifthBloomPoisonAmount = Self.fifthBloomPoisonAmount
        fifthBloomPoisonTicksRemaining = Self.fifthBloomPoisonDurationTicks
    }

    public mutating func updateBloom(_ newBloom: Double) {
        bloom = max(0.0, min(1.0, newBloom))
    }

    public mutating func releaseFifthBloomIndependentModel(targetInvincible: Bool) -> Double {
        guard fifthBloomPoisonTicksRemaining > 0, fifthBloomPoisonAmount > 0 else { return 0.0 }
        let resolved = targetInvincible ? 0.0 : fifthBloomPoisonAmount * (empowermentActive ? 1.25 : 1.0)
        fifthBloomPoisonAmount = 0.0
        fifthBloomPoisonTicksRemaining = 0
        return resolved
    }

    public mutating func activateUnarmedPoisonBuff() { unarmedPoisonBuffActive = true }

    public mutating func queueVictimFallReactionOnAnimationEnd(
        atUninterruptEndOrIdleTransition: Bool,
        deterministicRollPercent: Int,
        delayedDamage: Double = 0.08
    ) -> Bool {
        guard unarmedPoisonBuffActive, atUninterruptEndOrIdleTransition,
              victimFallCooldownRemaining == 0, victimPhysicsTicksRemaining == 0,
              (1...100).contains(deterministicRollPercent), deterministicRollPercent <= 35 else { return false }
        victimPhysicsTicksRemaining = Self.fallReactionPhysicsTicks
        victimFallCooldownRemaining = Self.fallReactionCooldownTicks
        delayedFallDamagePending = max(0.0, delayedDamage)
        return true
    }

    public mutating func activateShadowPoisonImpact(targetCurrentlyInShadowForm: Bool) {
        shadowPoisonTicksRemaining = Self.shadowPoisonDurationTicks
        targetShadowFormActive = targetCurrentlyInShadowForm
    }

    public mutating func applyTargetShadowEnergyGain(_ requestedDelta: Double) -> Double {
        guard requestedDelta > 0, !suppressesTargetShadowGain else { return targetShadowEnergy }
        targetShadowEnergy = min(1.0, targetShadowEnergy + requestedDelta)
        return targetShadowEnergy
    }

    public mutating func stepTick(comDistanceMillimeters: Double) -> (fallDamage: Double, shadowTerminated: Bool) {
        if fifthBloomPoisonTicksRemaining > 0 {
            fifthBloomPoisonTicksRemaining -= 1
            if fifthBloomPoisonTicksRemaining == 0 { fifthBloomPoisonAmount = 0.0 }
        }
        if witherAuraActive {
            if comDistanceMillimeters < Self.witherDistanceThresholdMM {
                witherProximityTicks += 1
                witherOutsideTicks = 0
                if witherProximityTicks >= Self.witherGainIntervalTicks {
                    witherProximityTicks = 0
                    witherStacks = min(Self.maxWitherStacks, witherStacks + 1)
                }
            } else {
                witherOutsideTicks += 1
                witherProximityTicks = 0
                if witherOutsideTicks >= Self.witherDecayIntervalTicks {
                    witherOutsideTicks = 0
                    witherStacks = max(0, witherStacks - 1)
                }
            }
        }
        var fallDamage = 0.0
        if victimPhysicsTicksRemaining > 0 {
            victimPhysicsTicksRemaining -= 1
            if victimPhysicsTicksRemaining == 0 {
                fallDamage = delayedFallDamagePending
                delayedFallDamagePending = 0.0
            }
        }
        if victimFallCooldownRemaining > 0 { victimFallCooldownRemaining -= 1 }
        var terminated = false
        if shadowPoisonTicksRemaining > 0 {
            let elapsed = Self.shadowPoisonDurationTicks - shadowPoisonTicksRemaining + 1
            shadowPoisonTicksRemaining -= 1
            if elapsed % Self.shadowBurnIntervalTicks == 0 {
                targetShadowEnergy = max(0.0, targetShadowEnergy - 0.10)
                if targetShadowEnergy == 0.0 && targetShadowFormActive {
                    targetShadowFormActive = false
                    terminated = true
                }
            }
        }
        return (fallDamage, terminated)
    }
}

public struct DuelErlangMasterRuntime: Equatable, Sendable {
    public static let closedMissingEmitterCount = 12
    public static func sampleSignedStretch(factor: Double, speed: Double, hideProgress: Double) -> (stretch: Double, opacity: Double) {
        let clampedHide = max(0.0, min(1.0, hideProgress))
        return (factor * (1.0 + speed * 0.25), 1.0 - clampedHide * clampedHide)
    }
}

public struct DuelXuXiaoMasterRuntime: Equatable, Sendable {
    public static let fiveEquipmentCandidates = [
        "WPN_IMPERIAL_GLOVES_01", "WPN_IMPERIAL_GLOVES_01a", "ARM_AGL_49", "HLM_AGL_49", "RNG_AGL_KNIVES_06"
    ]
    public static let totalMotionContracts = 58
    public static let recoveredMissingMotions = 37
}

public struct DuelExperienceMasterCoordinator: Equatable, Sendable {
    public static func televisionDynamicScale(casting: Bool, recentFrameTimeMS: Double) -> (msaa: Int, scale: Double) {
        guard casting else { return (2, 1.0) }
        let factor = recentFrameTimeMS > 16.2 ? max(0.85, 16.0 / recentFrameTimeMS) : 1.0
        return (1, factor)
    }
    public static func normalizeThumbstick(x: Double, y: Double, deadzone: Double = 0.18, blocked: Bool = false) -> (dx: Int, dy: Int) {
        guard !blocked, sqrt(x * x + y * y) >= deadzone else { return (0, 0) }
        return (x >= deadzone ? 1 : (x <= -deadzone ? -1 : 0), y >= deadzone ? 1 : (y <= -deadzone ? -1 : 0))
    }
}
