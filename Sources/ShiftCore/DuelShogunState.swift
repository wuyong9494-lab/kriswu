import Foundation

/// Wu Yong's original 60 Hz Shogun combat state (inspired by Shadow Fight 4's
/// Odachi, dual-threshold Shadow Cataclysm, charged critical execution,
/// unbreakable advancing kick and asynchronous retinue companion).
/// Pure integer deterministic state; zero third-party assets or external rules.
public struct DuelShogunState: Equatable, Sendable {
    public enum ShadowPhase: UInt8, Codable, Equatable, Sendable {
        case normal = 0
        case shadowForm = 1
        case cataclysm = 2
    }

    public enum CompanionPhase: UInt8, Codable, Equatable, Sendable {
        case follow = 0
        case windup = 1
        case strike = 2
        case recover = 3
        case unconscious = 4
    }

    // Core thresholds and tuning constants (60 Hz ticks, millimeter coordinates).
    public static let shadowFormThreshold = 100
    public static let cataclysmThreshold = 200
    public static let maxShadowEnergy = 200
    public static let cataclysmMaxTicks = 600
    public static let cataclysmEruptionRange = 2200
    public static let cataclysmEruptionPush = 520
    public static let shadowAbilityCooldownTicks = 180
    public static let ruthlessKickCooldownTicks = 90
    public static let heavyFullChargeTicks = 75
    public static let heavyMaxChargeTicks = 120
    public static let companionFollowSpeed = 46
    public static let companionAgonyFollowSpeed = 84
    public static let companionTargetGap = 780
    public static let companionWindupTicks = 10
    public static let companionStrikeTicks = 8
    public static let companionRecoverTicks = 16
    public static let companionStrikeReach = 1080
    public static let companionStrikeDamage = 75
    public static let companionStunTicks = 54
    public static let companionCooldownTicks = 240
    public static let companionAgonyCooldownTicks = 120
    public static let companionEnergyDrain = 18
    public static let companionShadowGain = 24
    public static let agonyDurationTicks = 360
    public static let reviveHealth = 180
    public static let possessedBuffTicks = 300

    public var shadowPhase: ShadowPhase = .normal
    public var shadowEnergy: Int = 0
    public var shadowAbilityCooldown: Int = 0
    public var ruthlessKickCooldown: Int = 0
    public var heavyChargeTicks: Int = 0
    public var cataclysmTicks: Int = 0
    public var cataclysmPulseTicks: Int = 0
    public var defenseBonusTicks: Int = 0
    public var opponentDefenseDebuffTicks: Int = 0

    // Asynchronous battle companion (死士随从 / Absolute Power).
    public var companionX: Int = 2750
    public var companionFacing: Int = 1
    public var companionPhase: CompanionPhase = .follow
    public var companionTimer: Int = 0
    public var companionCooldown: Int = 0
    public var companionHitApplied: Bool = false
    public var agonyRemainingTicks: Int = 0
    public var reviveUsed: Bool = false

    public init(ownerX: Int = 3500, ownerFacing: Int = 1) {
        companionX = min(DuelGame.rightWall, max(DuelGame.leftWall, ownerX - ownerFacing * 750))
        companionFacing = ownerFacing
    }

    public var isInShadow: Bool { shadowPhase != .normal }
    public var isCataclysm: Bool { shadowPhase == .cataclysm }
    public var isCompanionAvailable: Bool {
        companionPhase == .follow && companionCooldown == 0
    }
    public var canUseShadowAbility: Bool {
        shadowPhase != .normal && shadowAbilityCooldown == 0
    }
    public var canUseRuthlessKick: Bool { ruthlessKickCooldown == 0 }
    public var isHeavyFullyCharged: Bool { heavyChargeTicks >= Self.heavyFullChargeTicks }

    @discardableResult
    public mutating func gainShadowEnergy(_ amount: Int) -> ShadowPhase? {
        guard amount > 0 else { return nil }
        let previous = shadowPhase
        shadowEnergy = min(Self.maxShadowEnergy, shadowEnergy + amount)
        if shadowPhase == .normal && shadowEnergy >= Self.shadowFormThreshold {
            shadowPhase = .shadowForm
        }
        if shadowPhase != .cataclysm && shadowEnergy >= Self.cataclysmThreshold {
            enterCataclysm()
        }
        return shadowPhase != previous ? shadowPhase : nil
    }

    public mutating func enterCataclysm() {
        shadowEnergy = Self.cataclysmThreshold
        shadowPhase = .cataclysm
        cataclysmTicks = 0
        cataclysmPulseTicks = 18
        // Foreshadowing the End: shadow abilities reload immediately on Cataclysm.
        shadowAbilityCooldown = 0
    }

    public mutating func consumeCataclysm(shogunLandedFirst: Bool) {
        shadowPhase = .normal
        shadowEnergy = 0
        cataclysmTicks = 0
        cataclysmPulseTicks = 12
        if shogunLandedFirst {
            opponentDefenseDebuffTicks = Self.possessedBuffTicks
        } else {
            defenseBonusTicks = Self.possessedBuffTicks
        }
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.u8(shadowPhase.rawValue)
        try writer.int(shadowEnergy)
        try writer.int(shadowAbilityCooldown)
        try writer.int(ruthlessKickCooldown)
        try writer.int(heavyChargeTicks)
        try writer.int(cataclysmTicks)
        try writer.int(cataclysmPulseTicks)
        try writer.int(defenseBonusTicks)
        try writer.int(opponentDefenseDebuffTicks)
        try writer.int(companionX)
        try writer.int(companionFacing)
        try writer.u8(companionPhase.rawValue)
        try writer.int(companionTimer)
        try writer.int(companionCooldown)
        try writer.bool(companionHitApplied)
        try writer.int(agonyRemainingTicks)
        try writer.bool(reviveUsed)
    }
}
