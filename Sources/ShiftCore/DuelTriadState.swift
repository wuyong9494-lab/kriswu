import Foundation

/// Deterministic H17 L1–L6 event interpreter. Space is resolved by the fight;
/// releasing a wave, root or consumed soul alone never confirms a hit.
public struct DuelTriadState: Equatable, Sendable {
    public typealias Ability = DuelTriadRules.Ability
    public typealias Soul = DuelTriadRules.Soul
    public typealias DamageKind = DuelTriadRules.DamageKind
    public enum Phase: String, Codable, Sendable { case startup, active, recovery }
    public enum Origin: String, Codable, Sendable { case manual, lastWave, entangled, forestRain, dance, hungrySoul }
    public enum OwnerAnimation: String, Codable, CaseIterable, Sendable {
        case branchesStart, branchesLoop, branchesEnd, mistBlade
        case mistOnslaught1, mistOnslaught2, mistOnslaught3
        case cryingDanceIn, cryingDanceLoop, cryingDanceOut
        public var role: String {
            switch self {
            case .branchesStart: return "triadBranches"
            case .branchesLoop: return "triadBranchesLoop"
            case .branchesEnd: return "triadBranchesEnd"
            case .mistBlade: return "triadMistBlade"
            case .mistOnslaught1: return "triadMistOnslaught"
            case .mistOnslaught2: return "triadMistOnslaught2"
            case .mistOnslaught3: return "triadMistOnslaught3"
            case .cryingDanceIn: return "triadCryingDance"
            case .cryingDanceLoop: return "triadCryingDanceLoop"
            case .cryingDanceOut: return "triadCryingDanceOut"
            }
        }
        public var sourceAnimation: String {
            switch self {
            case .branchesStart: return "H17_Root_Spike_Start"
            case .branchesLoop: return "H17_Root_Spike_Loop"
            case .branchesEnd: return "H17_Root_Spike_End"
            case .mistBlade: return "H17_Blade_Ability"
            case .mistOnslaught1: return "H17_Illusion_Wave_1"
            case .mistOnslaught2: return "H17_Illusion_Wave_2"
            case .mistOnslaught3: return "H17_Illusion_Wave_3"
            case .cryingDanceIn: return "H17_Trans_In"
            case .cryingDanceLoop: return "H17_Trans_Loop"
            case .cryingDanceOut: return "H17_Trans_Out"
            }
        }
        public var sourceFrameCount: Int {
            switch self {
            case .branchesStart: return 39
            case .branchesLoop, .mistOnslaught1: return 51
            case .branchesEnd, .mistBlade: return 31
            case .mistOnslaught2: return 67
            case .mistOnslaught3: return 87
            case .cryingDanceIn: return 16
            case .cryingDanceLoop: return 49
            case .cryingDanceOut: return 33
            }
        }
        public var lastSampleTick: Int { 2 * (sourceFrameCount - 1) }
        /// Native AnimationEnd is dispatched four source frames before the
        /// last sample. H17 transition triggers listen to that early event.
        public var endEventTick: Int { 2 * (sourceFrameCount - 1 - 4) }
        public var loops: Bool { self == .branchesLoop || self == .cryingDanceLoop }
    }
    public struct OwnerMotion: Equatable, Sendable {
        public let animation: OwnerAnimation
        public internal(set) var tick: Int
        public var role: String { animation.role }
        public var sourceAnimation: String { animation.sourceAnimation }
        public var lastSampleTick: Int { animation.lastSampleTick }
        public var endEventTick: Int { animation.endEventTick }
        public var loops: Bool { animation.loops }
    }
    public struct Cast: Equatable, Sendable {
        public let id: UInt64
        public let ability: Ability
        public internal(set) var tick: Int
        public internal(set) var duration: Int
        public internal(set) var phase: Phase
        public let empowered: Bool
        public internal(set) var finalWave: Bool
        public internal(set) var entangled: Bool
    }
    public struct Attack: Equatable, Sendable {
        public let id: UInt64
        public let ability: Ability
        public let origin: Origin
        public let damageKind: DamageKind
        /// Base snapshot; use contact(...) for root/suppression-dependent damage.
        public let damage: Int
        public let blockedDamage: Int
        public let delivery: DuelTriadRules.Delivery
        public let rangeMillimeters: Int
        public let projectileSpeedMillimetersPerTick: Int
        public let hitboxBottomMillimeters: Int
        public let hitboxTopMillimeters: Int
        public let radiusMillimeters: Int
        public let activeTicks: Int
        public let impact: DuelImpactResponse
        public let stunTicks: Int
        public let hitStopTicks: Int
        public let blockedHitStopTicks: Int
        public let knocksDown: Bool
        public let blockable: Bool
        public let generated: Bool
        public let empowered: Bool
        public let critical: Bool
        /// Identifies the independently spawned soul whose windup preceded
        /// this attack. Space anchors that soul when soulAppeared is emitted.
        public internal(set) var summonID: UInt64? = nil
        public internal(set) var summonMove: DuelTriadRules.SummonMove? = nil
        public internal(set) var summonStage: DuelTriadRules.SummonStage? = nil
        /// Model windup is included in activeTicks. Soul attacks already
        /// released at their source hit frame retain the default zero.
        public internal(set) var activationDelayTicks: Int = 0
    }
    public struct Control: Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case root, stun }
        public let sourceID: UInt64
        public let kind: Kind
        public let durationTicks: Int
        public init(sourceID: UInt64, kind: Kind, durationTicks: Int) {
            self.sourceID = sourceID; self.kind = kind; self.durationTicks = durationTicks
        }
    }
    public struct DamagePulse: Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case suppression, branches, poison }
        public let id: UInt64
        public let sourceID: UInt64
        public let kind: Kind
        public let damageKind: DamageKind
        public let damage: Int
        public let canKill: Bool
        public var nonlethal: Bool { !canKill }
        /// Suppression always leaves at least one health point. Other immunity
        /// and shield handling remains the caller's authoritative damage path.
        public func healthDamage(health: Int) -> Int {
            min(damage, max(0, health - (canKill ? 0 : 1)))
        }
    }
    public struct DamageSplit: Equatable, Sendable {
        public let weapon: Int
        public let shadow: Int
        public let critical: Bool
        public let bypassesBlock: Bool
        public var total: Int { weapon + shadow }
    }
    public struct ContactContext: Equatable, Sendable {
        public var blocked: Bool
        public var airborne: Bool
        public var rolling: Bool
        public var shadowDamageUnbreakable: Bool
        public var rootImmune: Bool
        public init(blocked: Bool = false, airborne: Bool = false, rolling: Bool = false,
                    shadowDamageUnbreakable: Bool = false, rootImmune: Bool = false) {
            self.blocked = blocked; self.airborne = airborne; self.rolling = rolling
            self.shadowDamageUnbreakable = shadowDamageUnbreakable; self.rootImmune = rootImmune
        }
    }
    public struct ContactReceipt: Equatable, Sendable {
        public let accepted: Bool
        public let attack: Attack?
        public let blocked: Bool
        public let damage: Int
        public let damageKind: DamageKind
        public let critical: Bool
        public let canKill: Bool
        public let effects: [Effect]
        fileprivate static let rejected = Self(accepted: false, attack: nil, blocked: false,
            damage: 0, damageKind: .shadow, critical: false, canKill: true, effects: [])
    }
    public struct DefenceReceipt: Equatable, Sendable {
        public let accepted: Bool
        public let deflected: Bool
        public let effects: [Effect]
    }
    public enum Effect: Equatable, Sendable {
        case attack(Attack)
        case control(Control)
        case controlReleased(sourceID: UInt64, kind: Control.Kind)
        case damagePulse(DamagePulse)
        case castPhase(Ability, Phase)
        case castEnded(Ability)
        case castInterrupted(Ability)
        case forestStarted(roundID: Int)
        case forestEnded
        case mistBladeStarted(durationTicks: Int)
        case mistBladeEnded
        case suppressionApplied(sourceID: UInt64, durationTicks: Int)
        case suppressionEnded(sourceID: UInt64)
        case soulAppeared(Soul, Origin, summonID: UInt64)
        case sourceSoulAppeared(SoulAppearance)
        case sourceSoulMotion(summonID: UInt64, animation: DuelTriadRules.SoulAnimation)
        case sourceRootModelEnded(sourceID: UInt64)
        case soulSummoned(Soul, Origin, attackID: UInt64)
        case feast(mistGained: Int)
        case deflected(sourceID: UInt64)
    }

    public let rules: DuelTriadRules
    public private(set) var mist: Int
    public private(set) var notches = 0
    public private(set) var onslaughtCharges: Int
    public private(set) var breakthroughReady = false
    public private(set) var mistBladeUnlocked = false
    public private(set) var mistBladeRemainingTicks = 0
    public private(set) var rootRemainingTicks = 0
    public private(set) var curseDebuffRemainingTicks = 0
    public private(set) var sharedSoulCooldownRemainingTicks = 0
    public private(set) var activeCast: Cast?
    public private(set) var ownerMotion: OwnerMotion?
    public private(set) var roundID: Int?
    public private(set) var roundActive = false
    public private(set) var opponentArmor: DuelTriadRules.Faction = .unknown
    public private(set) var opponentWeapon: DuelTriadRules.Faction = .unknown
    /// Explicit application scale for normalized production ModHP fractions.
    /// The source function f213 is RaidDamageAmplifier, not a maxHP getter.
    /// Missing scale is never replaced by this fighter's or current health.
    public private(set) var opponentMaximumHealth: Int?
    public private(set) var opponentFrontRoomSourceUnits: Int?
    public private(set) var opponentBackRoomSourceUnits: Int?
    public var usesMistEnergy: Bool { rules.level >= 2 }
    public var mistCannotBeBurned: Bool { usesMistEnergy }
    public var isCursed: Bool { roundActive && rules.level >= 2 }
    public var suppressionStacks: Int { suppression.count }
    public var suppressionRemainingTicks: Int { suppression.map { $0.duration - $0.elapsed }.max() ?? 0 }
    public var opponentCanBlock: Bool { !(rules.level >= 4 && !suppression.isEmpty) }
    public var weaponAttacksLocked: Bool {
        if let motion = ownerMotion {
            switch motion.animation {
            case .branchesEnd: return motion.tick < 52
            case .mistBlade: return motion.tick < 56
            case .mistOnslaught1: return motion.tick < 92
            case .mistOnslaught2: return motion.tick < 124
            case .mistOnslaught3: return motion.tick < 166
            default: return true
            }
        }
        if rules.runtime != nil { return false }
        return movementLocked || (rules.level < 4 && rootRemainingTicks > 0)
    }
    public var movementLocked: Bool {
        if let motion = ownerMotion {
            switch motion.animation {
            case .branchesStart, .branchesLoop, .cryingDanceIn, .cryingDanceLoop, .cryingDanceOut: return true
            case .branchesEnd: return motion.tick < 28
            default: return false
            }
        }
        if rules.runtime != nil { return false }
        return activeCast?.ability == .cryingDance || (rules.level < 4 && rootRemainingTicks > 0)
    }
    public var impactImmune: Bool {
        if sourceDefenderProtectionRemainingTicks > 0 { return true }
        if let motion = ownerMotion { return motion.animation == .cryingDanceLoop }
        return activeCast?.ability == .cryingDance
    }
    public var damageImmune: Bool { false }
    public var opponentShadowDefenseReductionBps: Int {
        rules.level >= 6 && !suppression.isEmpty ? rules.suppression.level6ShadowDefenseReductionBps : 0
    }

    private struct TimedAmount: Equatable, Sendable {
        let sourceID: UInt64
        let total: Int
        let duration: Int
        var elapsed: Int
        var lastPulseElapsed: Int = 0
    }
    private struct Flight: Equatable, Sendable { let attack: Attack; var remaining: Int }
    private struct MistPulseGain: Equatable, Sendable {
        var remainingTicks: Int
        var pulseRemainingTicks: Int
        var remainder: Int
    }
    private struct Scheduled: Equatable, Sendable {
        let ability: Ability
        let origin: Origin
        var remaining: Int
        let empowered: Bool
        let castID: UInt64?
        var summonID: UInt64? = nil
    }
    private struct SourceScheduled: Equatable, Sendable {
        enum Kind: String, Sendable { case appearance, attack, ninjatoEndMotion }
        let kind: Kind
        let move: DuelTriadRules.SummonMove
        let origin: Origin
        var remainingTicks: Int
        let summonID: UInt64?
        let stage: DuelTriadRules.SummonStage
        let requiresRoot: Bool
    }
    private var suppression: [TimedAmount] = []
    private var poison: [TimedAmount] = []
    private var mistGains: [TimedAmount] = []
    private var failedRootDamage: [TimedAmount] = []
    private var sourceHitMistGain: MistPulseGain?
    private var sourceForestMistGain: MistPulseGain?
    private var sourceRootOwnerRemainingTicks = 0
    private var sourceRootModelRemainingTicks = 0
    private var sourceRootModelID: UInt64?
    private var sourceDanceActiveRemainingTicks = 0
    private var sourceWaveContinuationRequested = false
    private var sourceDefenderProtectionRemainingTicks = 0
    private var sourceForestRainCooldown = 0
    private var sourceForestRainWindow = 0
    private var sourceScheduled: [SourceScheduled] = []
    private var flights: [Flight] = []
    private var scheduled: [Scheduled] = []
    private var cooldowns = Array(repeating: 0, count: Ability.allCases.count)
    private var curseCooldown = 0
    private var deflectCooldown = 0
    private var rootSourceID: UInt64?
    private var rootPulseRemaining = 0
    private var chainCount = 0
    private var chainRemaining = 0
    private var nextID: UInt64 = 1
    private var randomState: UInt64
    private var lastContactID: UInt64?
    private var lastWeaponEventID: UInt64?
    private var lastWeaponStartID: UInt64?
    private var lastShadowEventID: UInt64?
    private var lastDefenceEventID: UInt64?
    private var lastRoundEventID: UInt64?
    /// Resource/event stream bounds; these are not source balance quantities.
    public static let maximumPendingEvents = 256
    private static let maximumDamage = 1_000_000_000
    public private(set) var rejectedPendingEventCount = 0

    public init?(rules: DuelTriadRules, seed: UInt64) {
        guard (try? rules.validate()) != nil else { return nil }
        self.rules = rules; mist = rules.mist.initial
        onslaughtCharges = rules.blade.initialOnslaughtCharges; randomState = seed
    }

    public mutating func configureOpponent(armor: DuelTriadRules.Faction, weapon: DuelTriadRules.Faction,
                                           maximumHealth: Int? = nil) {
        opponentArmor = armor; opponentWeapon = weapon
        if let maximumHealth, (1...1_000_000).contains(maximumHealth) { opponentMaximumHealth = maximumHealth }
    }
    /// Call from the deterministic spatial adapter before step/start. Rain's
    /// six bowmen use original wall-room gates before consuming a Notch.
    public mutating func configureSummonSpace(opponentFrontRoomSourceUnits: Int,
                                              opponentBackRoomSourceUnits: Int) {
        guard (0...1_000_000).contains(opponentFrontRoomSourceUnits),
              (0...1_000_000).contains(opponentBackRoomSourceUnits) else { return }
        self.opponentFrontRoomSourceUnits = opponentFrontRoomSourceUnits
        self.opponentBackRoomSourceUnits = opponentBackRoomSourceUnits
    }
    public func cooldownRemaining(_ ability: Ability) -> Int { cooldowns[index(ability)] }
    public func canUse(_ ability: Ability) -> Bool {
        guard roundActive, rules.level >= ability.minimumLevel,
              let rule = rules.ability(ability), cooldownRemaining(ability) == 0,
              mist >= rule.mistCost, nextID < UInt64.max else { return false }
        // The original manual-soul triggers create a separate model and do
        // not test the owner's Uninterrupt interval or grounded state. The
        // fight still enforces external ALL_CONTROLS_DISABLED-style locks.
        if ability.soul != nil {
            return sharedSoulCooldownRemainingTicks == 0 &&
                flights.count + scheduled.count < Self.maximumPendingEvents && nextID < UInt64.max - 1
        }
        guard activeCast == nil || (rules.runtime != nil && !weaponAttacksLocked), !weaponAttacksLocked else { return false }
        switch ability {
        case .branches: return rootRemainingTicks == 0 && !hasUnresolvedRoot
        case .mistBlade: return mistBladeUnlocked && mistBladeRemainingTicks == 0
        case .mistOnslaught: return onslaughtCharges > 0
        case .cryingDance: return notches >= rules.souls.notchCost
        default: return true
        }
    }

    /// Enter exactly once for a new round. Mist retention is an explicit
    /// profile choice; the H17 L6 text explicitly carries Notches across rounds.
    @discardableResult public mutating func beginRound(roundID newRound: Int) -> [Effect] {
        guard newRound >= 0, roundID.map({ newRound > $0 }) ?? true else { return [] }
        var effects = clearRoundEffects()
        if roundID != nil { mist = mist * rules.mist.betweenRoundsRetainedBps / 10_000 }
        roundID = newRound; roundActive = true
        breakthroughReady = rules.level >= 2
        onslaughtCharges = rules.blade.initialOnslaughtCharges
        if rules.policies.resetCooldownsBetweenRounds {
            cooldowns = Array(repeating: 0, count: Ability.allCases.count)
            deflectCooldown = 0; sharedSoulCooldownRemainingTicks = 0
        }
        if rules.level >= 2 { effects.append(.forestStarted(roundID: newRound)) }
        return effects
    }

    @discardableResult public mutating func finishRound(won: Bool, eventID: UInt64) -> [Effect] {
        guard roundActive, accepts(eventID, after: lastRoundEventID) else { return [] }
        lastRoundEventID = eventID
        var effects = clearRoundEffects()
        roundActive = false
        if won && rules.level >= 2 {
            let before = mist; gainMist(rules.mist.feastGain)
            effects.append(.feast(mistGained: mist - before))
        }
        return effects
    }

    /// A source-independent request; caller maps controls into the stable
    /// ability identity. Invalid requests cannot consume resource or event IDs.
    @discardableResult public mutating func start(_ ability: Ability) -> [Effect] {
        if rules.runtime != nil { return startSourceAbility(ability) }
        guard canUse(ability), let rule = rules.ability(ability), let castID = takeID() else { return [] }
        if ability != .mistOnslaught && rules.policies.resetChainOnOtherAbility { resetChain() }
        let empowered = mistBladeRemainingTicks > 0
        let finalWave = ability == .mistOnslaught && onslaughtCharges == 1
        if ability == .mistOnslaught {
            onslaughtCharges -= 1
            chainCount += 1; chainRemaining = rules.blade.chainWindowTicks
        }
        let entangled = ability == .mistOnslaught && chainCount == 3 && rules.level >= 6
        if chainCount == 3 { chainCount = 0 }
        mist -= rule.mistCost; cooldowns[index(ability)] = rule.cooldownTicks
        if let soul = ability.soul {
            sharedSoulCooldownRemainingTicks = rules.souls.sharedCooldownTicks
            var effects = soulAppeared(soul, origin: .manual, summonID: castID)
            if rule.startupTicks == 0 {
                effects += emit(ability: ability, origin: .manual, empowered: empowered, summonID: castID)
            } else {
                schedule(.init(ability: ability, origin: .manual, remaining: rule.startupTicks,
                    empowered: empowered, castID: nil, summonID: castID))
            }
            return effects
        }
        if ability == .mistBlade { mistBladeUnlocked = false }
        if ability == .cryingDance { notches -= rules.souls.notchCost }
        let phase: Phase = rule.startupTicks == 0 ? .active : .startup
        let cast = Cast(id: castID, ability: ability, tick: 0, duration: rule.duration,
                        phase: phase, empowered: empowered, finalWave: finalWave, entangled: entangled)
        activeCast = cast
        var effects: [Effect] = [.castPhase(ability, phase)]
        if phase == .active { effects += release(cast) }
        return effects
    }

    public var canContinueOnslaught: Bool {
        guard rules.runtime != nil, roundActive, onslaughtCharges > 0, !sourceWaveContinuationRequested,
              let motion = ownerMotion else { return false }
        return (motion.animation == .mistOnslaught1 && motion.tick < 52) ||
            (motion.animation == .mistOnslaught2 && motion.tick < 92)
    }
    /// A neutral ranged continuation is buffered for the original
    /// Transitional interval end. It neither restarts the clip nor spends a
    /// charge before that transition actually occurs.
    @discardableResult public mutating func requestOnslaughtContinuation() -> Bool {
        guard canContinueOnslaught else { return false }
        sourceWaveContinuationRequested = true; return true
    }

    /// Advance only on a live simulation tick, after hit-stop/pause gating.
    /// Every interval uses integer counters. Fractional DOT and mist gains are
    /// distributed by cumulative integer differences, preserving their totals.
    @discardableResult public mutating func step() -> [Effect] {
        guard roundActive else { return [] }
        for i in cooldowns.indices { cooldowns[i] = max(0, cooldowns[i] - 1) }
        sharedSoulCooldownRemainingTicks = max(0, sharedSoulCooldownRemainingTicks - 1)
        curseCooldown = max(0, curseCooldown - 1); deflectCooldown = max(0, deflectCooldown - 1)
        curseDebuffRemainingTicks = max(0, curseDebuffRemainingTicks - 1)
        sourceRootOwnerRemainingTicks = max(0, sourceRootOwnerRemainingTicks - 1)
        sourceDanceActiveRemainingTicks = max(0, sourceDanceActiveRemainingTicks - 1)
        sourceDefenderProtectionRemainingTicks = max(0, sourceDefenderProtectionRemainingTicks - 1)
        sourceForestRainCooldown = max(0, sourceForestRainCooldown - 1)
        sourceForestRainWindow = max(0, sourceForestRainWindow - 1)
        var effects: [Effect] = []
        if sourceRootModelRemainingTicks > 0 {
            sourceRootModelRemainingTicks -= 1
            if sourceRootModelRemainingTicks == 0 && rootRemainingTicks == 0 {
                sourceRootOwnerRemainingTicks = 0
                if let id = sourceRootModelID { effects.append(.sourceRootModelEnded(sourceID: id)) }
                sourceRootModelID = nil
            }
        }
        if chainRemaining > 0 {
            chainRemaining -= 1
            if chainRemaining == 0 { resetChain() }
        }
        if mistBladeRemainingTicks > 0 {
            mistBladeRemainingTicks -= 1
            if mistBladeRemainingTicks == 0 {
                breakthroughReady = true; effects.append(.mistBladeEnded)
            }
        }
        for i in flights.indices { flights[i].remaining -= 1 }
        flights.removeAll { $0.remaining <= 0 }
        effects += advanceSourceSchedule()
        effects += advanceAmounts()
        if rootRemainingTicks > 0, let sourceID = rootSourceID {
            rootRemainingTicks -= 1; rootPulseRemaining -= 1
            if rootPulseRemaining == 0 {
                let value = adjustedBranchDamage(rules.branches.pulseDamage)
                effects += pulse(sourceID: sourceID, kind: .branches, damageKind: .shadow, damage: value, canKill: true)
                if rules.runtime != nil && rules.level >= 6 && sourceForestRainWindow > 0 && sourceForestRainCooldown == 0 {
                    sourceForestRainWindow = 0; sourceForestRainCooldown = 300
                    scheduleSourceRain()
                }
                rootPulseRemaining = rules.branches.pulseIntervalTicks
            }
            if rootRemainingTicks == 0 {
                rootSourceID = nil; rootPulseRemaining = 0
                effects.append(.controlReleased(sourceID: sourceID, kind: .root))
                if let id = sourceRootModelID { effects.append(.sourceRootModelEnded(sourceID: id)) }
                sourceRootModelID = nil; sourceRootModelRemainingTicks = 0
            }
        }
        // Copy due work before producing new work; a spawned event never gets
        // a second tick in its birth step because it was appended during a loop.
        for i in scheduled.indices { scheduled[i].remaining -= 1 }
        let due = scheduled.filter { $0.remaining <= 0 }
        scheduled.removeAll { $0.remaining <= 0 }
        for event in due {
            if let castID = event.castID, activeCast?.id != castID { continue }
            effects += emit(ability: event.ability, origin: event.origin,
                            empowered: event.empowered, summonID: event.summonID)
        }
        if rules.runtime != nil { return effects + advanceSourceOwnerMotion() }
        guard var cast = activeCast, let rule = rules.ability(cast.ability) else { return effects }
        cast.tick += 1
        if cast.tick >= cast.duration {
            activeCast = nil
            effects.append(.castEnded(cast.ability))
            return effects
        }
        let phase: Phase = cast.tick < rule.startupTicks ? .startup :
            cast.tick < rule.startupTicks + rule.activeTicks ? .active : .recovery
        let changed = cast.phase != phase
        cast.phase = phase; activeCast = cast
        if changed {
            effects.append(.castPhase(cast.ability, phase))
            if phase == .active { effects += release(cast) }
        }
        return effects
    }

    /// Returning a split does not spend Breakthrough. A whiff cannot unlock
    /// Mist Blade; only the later accepted contact consumes the prepared charge.
    public func weaponDamage(_ base: Int, blocked: Bool = false) -> DamageSplit {
        guard (0...Self.maximumDamage).contains(base) else {
            return .init(weapon: 0, shadow: 0, critical: false, bypassesBlock: false)
        }
        let active = mistBladeRemainingTicks > 0
        var total = scaled(base, bonusBps: active ? rules.blade.weaponBonusBps : 0)
        if let runtime = rules.runtime, breakthroughReady && !blocked {
            total = total * runtime.weaponCriticalMultiplierBps * runtime.criticalPhysicalRetentionBps / 100_000_000
        }
        let compensation = rules.runtime != nil && blocked ? 4 : 1
        let converted = active ? total * rules.blade.shadowConversionBps * compensation / 10_000 : 0
        return .init(weapon: rules.runtime?.shadowDamageIsAdditional == true ? total : total - converted,
            // Original trigger 24 uses SetHit.Damage to overwrite the model's
            // resolved damage with trigger 23's copied physical-hit amount.
            // It must not receive the MagicPower bonus for a second time.
            shadow: rules.runtime != nil ? converted : shadowDamage(converted),
            critical: breakthroughReady, bypassesBlock: breakthroughReady || !opponentCanBlock)
    }

    @discardableResult public mutating func weaponAttackStarted(eventID: UInt64) -> [Effect] {
        guard roundActive, !weaponAttacksLocked, accepts(eventID, after: lastWeaponStartID) else { return [] }
        lastWeaponStartID = eventID
        if rules.policies.resetChainOnWeaponStart { resetChain() }
        return []
    }

    @discardableResult public mutating func weaponContact(blocked: Bool, critical: Bool, eventID: UInt64) -> [Effect] {
        guard roundActive, accepts(eventID, after: lastWeaponEventID) else { return [] }
        lastWeaponEventID = eventID
        if !blocked && rules.level >= 2 {
            let actualCritical = critical || breakthroughReady
            breakthroughReady = false
            if actualCritical {
                onslaughtCharges = min(DuelTriadRules.maximumOnslaughtCharges, onslaughtCharges + 1)
                if mistBladeRemainingTicks == 0 { mistBladeUnlocked = true }
            }
        }
        restoreMistFromContact(blocked: blocked, generated: false, sourceID: eventID)
        return []
    }

    /// Call for other confirmed ordinary attacks without inventing a weapon
    /// critical. Suppression DOT itself must never be sent back as a contact.
    @discardableResult public mutating func ordinaryContact(blocked: Bool, eventID: UInt64) -> [Effect] {
        guard roundActive, accepts(eventID, after: lastWeaponEventID) else { return [] }
        lastWeaponEventID = eventID
        restoreMistFromContact(blocked: blocked, generated: false, sourceID: eventID)
        return []
    }

    public mutating func contact(attackID: UInt64, context: ContactContext, eventID: UInt64) -> ContactReceipt {
        guard roundActive, accepts(eventID, after: lastContactID),
              let at = flights.firstIndex(where: { $0.attack.id == attackID }),
              flights[at].attack.activeTicks - flights[at].remaining >= flights[at].attack.activationDelayTicks else { return .rejected }
        let attack = flights.remove(at: at).attack
        lastContactID = eventID
        let blocked = context.blocked && attack.blockable && opponentCanBlock
        var damage = blocked ? attack.blockedDamage : attack.damage
        if rules.runtime != nil && !blocked {
            // The original Hit trigger evaluates the current buff. Model
            // identity (including an intangible wave) remains the birth-time
            // choice, while a tangible hit can outlive its damage bonus.
            if let move = attack.summonMove, let stage = attack.summonStage {
                damage = sourceSoulDamage(move, origin: attack.origin, stage: stage,
                                          empowered: mistBladeRemainingTicks > 0)
            } else if attack.delivery == .mistWave && attack.empowered,
                      let spec = rules.ability(.mistOnslaught)?.attack {
                damage = shadowDamage(scaled(spec.damage, bonusBps:
                    mistBladeRemainingTicks > 0 ? rules.blade.waveAndSoulBonusBps : 0))
            }
        }
        var effects: [Effect] = []
        switch attack.delivery {
        case .mistWave:
            if !blocked || rules.policies.suppressionOnBlockedWave {
                effects += applySuppression(sourceID: attack.id)
            }
            // A normal wave is intangible. It may suppress, but contributes no
            // direct health damage, hit-stop, knockdown or stun to the adapter.
            if !attack.empowered { damage = 0 }
            if rules.runtime != nil && rules.level >= 6 && attack.origin == .lastWave &&
                rootRemainingTicks == 0 && sourceRootOwnerRemainingTicks == 0 && !hasUnresolvedRoot {
                effects += emit(ability: .branches, origin: .entangled, empowered: false)
                queueSourceAppearance(.entangledBow, origin: .entangled, delay: 100, requiresRoot: true)
            }
        case .roots:
            if rules.runtime != nil {
                // A caught root retains its initial MagicPower hit. Failure
                // adds damage based on that hit; it does not replace it.
                damage = scaled(attack.damage, bonusBps: suppression.isEmpty ? 0 : rules.branches.suppressedDamageBonusBps)
            }
            if context.airborne || context.rolling || context.shadowDamageUnbreakable || context.rootImmune {
                if let runtime = rules.runtime {
                    let extra = damage * runtime.rootFailedExtraDamageBps / 10_000
                    // Native applies this one tick later, after confirming the
                    // passive root reaction failed. Preserve that boundary.
                    Self.appendAmount(.init(sourceID: attack.id, total: extra, duration: 1, elapsed: 0),
                                      to: &failedRootDamage, maximum: Self.maximumPendingEvents)
                } else if !context.rootImmune {
                damage = adjustedBranchDamage(rules.branches.escapingBurstDamage)
                } else { damage = 0 }
            } else if !context.rootImmune && rootRemainingTicks == 0 {
                if rules.runtime == nil { damage = 0 }
                let duration = rules.branches.holdTicks - (attack.origin == .entangled ? rules.branches.entangledHoldReductionTicks : 0)
                rootSourceID = attack.id; rootRemainingTicks = duration
                if rules.runtime != nil && attack.origin == .manual { sourceRootOwnerRemainingTicks = duration }
                rootPulseRemaining = rules.branches.pulseIntervalTicks
                effects.append(.control(.init(sourceID: attack.id, kind: .root, durationTicks: duration)))
                if rules.level >= 6 && rules.runtime == nil {
                    if attack.origin == .entangled {
                        effects += emit(ability: .dynast, origin: .entangled, empowered: mistBladeRemainingTicks > 0)
                    } else {
                        effects += summonSequence(count: rules.souls.forestRainCount,
                            interval: rules.souls.forestRainIntervalTicks, origin: .forestRain, castID: nil)
                        onslaughtCharges = min(DuelTriadRules.maximumOnslaughtCharges, onslaughtCharges + 1)
                    }
                }
            } else if rules.runtime == nil { damage = 0 }
        case .soulMelee, .soulDash, .soulArrow:
            if rootRemainingTicks > 0 && attack.summonStage != .earthquake {
                damage = scaled(damage, bonusBps: rules.branches.rootedSoulBonusBps)
            }
            let dynastyHit = attack.summonMove.map { $0.soul == .dynast } ?? (attack.delivery == .soulArrow)
            if dynastyHit && rules.level >= 4 && !blocked && damage > 0 {
                let total = min(Self.maximumDamage, damage * rules.souls.poisonDamageBps / 10_000)
                Self.appendAmount(.init(sourceID: attack.id, total: total, duration: rules.souls.poisonDurationTicks, elapsed: 0),
                             to: &poison, maximum: rules.souls.maximumPoisonStacks)
            }
            if attack.summonMove == .legionHammer && attack.summonStage == .primary {
                onslaughtCharges = min(DuelTriadRules.maximumOnslaughtCharges, onslaughtCharges + 1)
            }
            if attack.summonMove == .danceNinjato && attack.summonStage == .primary,
               let summonID = attack.summonID {
                if !blocked && !context.shadowDamageUnbreakable && !context.rootImmune && !context.rolling {
                    sourceDanceActiveRemainingTicks = 180
                    queueSourceAppearance(.danceWhirl, origin: .dance, delay: 90)
                    effects.append(.sourceSoulMotion(summonID: summonID, animation: .ninjatoActiveStart))
                    queueSource(.init(kind: .ninjatoEndMotion, move: .danceNinjato, origin: .dance,
                        remainingTicks: 50, summonID: summonID, stage: .ninjatoFinal, requiresRoot: false))
                    queueSourceAttack(.danceNinjato, origin: .dance, id: summonID, delay: 64, stage: .ninjatoFinal)
                    // Original paired passive animation has 82 source frames,
                    // and its AnimationEnd notification occurs at tick 154.
                    effects.append(.control(.init(sourceID: summonID, kind: .stun, durationTicks: 154)))
                } else {
                    Self.appendAmount(.init(sourceID: attack.id, total: damage, duration: 1, elapsed: 0),
                                      to: &failedRootDamage, maximum: Self.maximumPendingEvents)
                }
            }
            if rules.runtime != nil && attack.critical && !blocked {
                onslaughtCharges = min(DuelTriadRules.maximumOnslaughtCharges, onslaughtCharges + 1)
                if mistBladeRemainingTicks == 0 { mistBladeUnlocked = true }
            }
        }
        if rules.runtime == nil || attack.delivery != .mistWave || attack.empowered {
            restoreMistFromContact(blocked: blocked, generated: attack.generated, sourceID: eventID)
        }
        return .init(accepted: true, attack: attack, blocked: blocked, damage: damage,
                     damageKind: attack.damageKind, critical: attack.critical, canKill: true, effects: effects)
    }

    /// Only a genuinely accepted opponent shadow-move start may roll Curse.
    /// Duplicate/polling events neither reroll RNG nor restart the debuff.
    @discardableResult public mutating func opponentUsedShadowMove(eventID: UInt64) -> [Effect] {
        guard isCursed, accepts(eventID, after: lastShadowEventID) else { return [] }
        lastShadowEventID = eventID
        guard curseCooldown == 0, roll(rules.forest.curseChanceBps), let id = takeID() else { return [] }
        curseCooldown = rules.forest.triggerCooldownTicks
        curseDebuffRemainingTicks = rules.forest.debuffTicks
        if let runtime = rules.runtime {
            sourceForestMistGain = .init(remainingTicks: runtime.forestGainPulseCount,
                                        pulseRemainingTicks: 1, remainder: 0)
        } else { gainMist(rules.forest.curseMistGain) }
        return [.control(.init(sourceID: id, kind: .stun, durationTicks: rules.forest.stunTicks))]
    }

    public mutating func defendAgainstIncomingAttack(whileAttacking: Bool, canDeflect: Bool = true,
                                                     eventID: UInt64) -> DefenceReceipt {
        guard roundActive, accepts(eventID, after: lastDefenceEventID) else {
            return .init(accepted: false, deflected: false, effects: [])
        }
        lastDefenceEventID = eventID
        guard rules.level >= 4, (whileAttacking || rules.runtime != nil), canDeflect, deflectCooldown == 0,
              let id = takeID() else { return .init(accepted: true, deflected: false, effects: []) }
        deflectCooldown = rules.souls.hungryDeflectCooldownTicks
        if rules.runtime != nil {
            sourceDefenderProtectionRemainingTicks = 1
            return .init(accepted: true, deflected: false,
                         effects: appearSourceSoul(.legionDefender, origin: .hungrySoul, existingID: id))
        }
        let effects: [Effect] = [.deflected(sourceID: id)] +
            emit(ability: .legionary, origin: .hungrySoul, empowered: mistBladeRemainingTicks > 0)
        return .init(accepted: true, deflected: true, effects: effects)
    }

    public func opponentOutgoingDamage(_ damage: Int, kind: DamageKind) -> Int {
        guard (0...Self.maximumDamage).contains(damage) else { return 0 }
        guard kind != .trueDamage else { return damage }
        if rules.runtime != nil {
            // H17 writes these attributes into the same personal factor
            // group. Original calcInputFactor sums (factor - 1), then clamps
            // each group to at least 0.1 before multiplying separate groups.
            var reduction = suppression.isEmpty ? 0 : rules.suppression.outgoingReductionPerStackBps
            if curseDebuffRemainingTicks > 0 && (kind == .weapon || kind == .unarmed) {
                reduction += rules.forest.physicalReductionBps
            }
            if rules.level >= 3 {
                for faction in [opponentArmor, opponentWeapon] {
                    if faction == .legion && kind == .weapon { reduction += rules.flavours.legionWeaponReductionBps }
                    else if faction == .legion && kind == .shadow { reduction += rules.flavours.legionShadowReductionBps }
                    else if faction == .dynasty && kind == .unarmed { reduction += rules.flavours.dynastyUnarmedReductionBps }
                    else if faction == .dynasty && kind == .shadow { reduction += rules.flavours.dynastyShadowReductionBps }
                }
            }
            return damage * max(1000, 10_000 - reduction) / 10_000
        }
        var value = damage
        if !suppression.isEmpty {
            let reduction = min(rules.suppression.maximumOutgoingReductionBps,
                                (rules.runtime == nil ? suppression.count : 1) * rules.suppression.outgoingReductionPerStackBps)
            value = value * (10_000 - reduction) / 10_000
        }
        if curseDebuffRemainingTicks > 0 && (kind == .weapon || kind == .unarmed) {
            value = value * (10_000 - rules.forest.physicalReductionBps) / 10_000
        }
        if rules.level >= 3 {
            // Separate equipped armor and weapon applications, with explicit
            // multiplicative arithmetic in this application rule profile.
            for faction in [opponentArmor, opponentWeapon] {
                let reduction: Int
                if faction == .legion && kind == .weapon { reduction = rules.flavours.legionWeaponReductionBps }
                else if faction == .legion && kind == .shadow { reduction = rules.flavours.legionShadowReductionBps }
                else if faction == .dynasty && kind == .unarmed { reduction = rules.flavours.dynastyUnarmedReductionBps }
                else if faction == .dynasty && kind == .shadow { reduction = rules.flavours.dynastyShadowReductionBps }
                else { reduction = 0 }
                value = value * (10_000 - reduction) / 10_000
            }
        }
        return value
    }
    public var opponentShadowEnergyGainMultiplierBps: Int {
        guard rules.level >= 3 else { return 10_000 }
        let equipment = rules.runtime == nil ? [opponentArmor, opponentWeapon] : [opponentArmor]
        return equipment.reduce(10_000) { value, faction in
            faction == .herald ? value * (10_000 - rules.flavours.heraldShadowGainReductionBps) / 10_000 : value
        }
    }
    public var opponentCriticalCooldownMultiplierBps: Int {
        rules.level >= 3 && opponentWeapon == .herald ? 10_000 + rules.flavours.heraldCriticalCooldownBonusBps : 10_000
    }

    @discardableResult public mutating func interrupt() -> [Effect] {
        if rules.runtime != nil {
            guard let cast = activeCast, !impactImmune else { return [] }
            activeCast = nil; ownerMotion = nil; sourceWaveContinuationRequested = false
            return [.castInterrupted(cast.ability)]
        }
        guard let cast = activeCast, rules.ability(cast.ability)?.interruptible == true else { return [] }
        activeCast = nil
        scheduled.removeAll { $0.castID == cast.id }
        return [.castInterrupted(cast.ability)]
    }

    private var hasUnresolvedRoot: Bool {
        flights.contains { $0.attack.delivery == .roots } || scheduled.contains { $0.ability == .branches }
    }
    private func index(_ ability: Ability) -> Int { Ability.allCases.firstIndex(of: ability)! }
    private func accepts(_ eventID: UInt64, after previous: UInt64?) -> Bool { previous.map { eventID > $0 } ?? true }
    private mutating func takeID() -> UInt64? {
        guard nextID < UInt64.max else { return nil }
        let result = nextID; nextID += 1; return result
    }
    private func scaled(_ damage: Int, bonusBps: Int) -> Int {
        min(Self.maximumDamage, damage * (10_000 + bonusBps) / 10_000)
    }
    private func shadowDamage(_ damage: Int) -> Int { scaled(damage, bonusBps: rules.level1ShadowBonusBps) }
    private func adjustedBranchDamage(_ damage: Int) -> Int {
        shadowDamage(scaled(damage, bonusBps: suppression.isEmpty ? 0 : rules.branches.suppressedDamageBonusBps))
    }
    private mutating func gainMist(_ amount: Int) { mist = min(rules.mist.maximum, mist + amount) }
    private mutating func resetChain() { chainCount = 0; chainRemaining = 0 }
    private mutating func roll(_ chance: Int) -> Bool {
        // SplitMix64: a private fixed sequence, never wall time/SystemRandom.
        randomState &+= 0x9e3779b97f4a7c15
        var value = randomState
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        value ^= value >> 31
        return value % 10_000 < UInt64(chance)
    }
    private mutating func clearRoundEffects() -> [Effect] {
        var effects: [Effect] = []
        if isCursed { effects.append(.forestEnded) }
        if let id = sourceRootModelID { effects.append(.sourceRootModelEnded(sourceID: id)) }
        if let id = rootSourceID { effects.append(.controlReleased(sourceID: id, kind: .root)) }
        if let cast = activeCast { effects.append(.castInterrupted(cast.ability)) }
        if mistBladeRemainingTicks > 0 { effects.append(.mistBladeEnded) }
        effects += suppression.map { .suppressionEnded(sourceID: $0.sourceID) }
        activeCast = nil; rootSourceID = nil; rootRemainingTicks = 0; rootPulseRemaining = 0
        curseDebuffRemainingTicks = 0; curseCooldown = 0; mistBladeRemainingTicks = 0; mistBladeUnlocked = false
        suppression.removeAll(); poison.removeAll(); mistGains.removeAll(); failedRootDamage.removeAll()
        sourceHitMistGain = nil; sourceForestMistGain = nil; flights.removeAll(); scheduled.removeAll()
        ownerMotion = nil; sourceScheduled.removeAll(); sourceWaveContinuationRequested = false
        sourceRootOwnerRemainingTicks = 0; sourceRootModelRemainingTicks = 0; sourceRootModelID = nil
        sourceDanceActiveRemainingTicks = 0; sourceDefenderProtectionRemainingTicks = 0
        sourceForestRainCooldown = 0; sourceForestRainWindow = 0
        resetChain()
        return effects
    }

    private mutating func startSourceAbility(_ ability: Ability) -> [Effect] {
        guard canUse(ability), let rule = rules.ability(ability), let id = takeID() else { return [] }
        mist -= rule.mistCost; cooldowns[index(ability)] = rule.cooldownTicks
        if let soul = ability.soul {
            sharedSoulCooldownRemainingTicks = rules.souls.sharedCooldownTicks
            let move: DuelTriadRules.SummonMove = soul == .legionary ? .legionSword : soul == .herald ? .heraldDash : .dynastyBow
            return appearSourceSoul(move, origin: .manual, existingID: id)
        }
        var effects: [Effect] = []
        if let old = activeCast { effects.append(.castInterrupted(old.ability)) }
        let animation: OwnerAnimation
        switch ability {
        case .branches:
            animation = .branchesStart; sourceRootOwnerRemainingTicks = rules.branches.holdTicks
        case .mistBlade:
            animation = .mistBlade; mistBladeUnlocked = false
        case .mistOnslaught:
            animation = .mistOnslaught1; onslaughtCharges -= 1; sourceWaveContinuationRequested = false
        case .cryingDance:
            animation = .cryingDanceIn; notches -= rules.souls.notchCost
        default: return effects
        }
        ownerMotion = .init(animation: animation, tick: 0)
        activeCast = .init(id: id, ability: ability, tick: 0, duration: animation.lastSampleTick + 1,
            phase: .startup, empowered: mistBladeRemainingTicks > 0, finalWave: false, entangled: false)
        effects.append(.castPhase(ability, .startup))
        if ability == .cryingDance { effects += appearSourceSoul(.danceNinjato, origin: .dance) }
        return effects
    }

    private mutating func changeSourceOwnerMotion(_ animation: OwnerAnimation, preservingTick: Bool = false) -> [Effect] {
        guard var cast = activeCast else { return [] }
        let tick = preservingTick ? ownerMotion?.tick ?? 0 : 0
        ownerMotion = .init(animation: animation, tick: tick)
        cast.duration = cast.tick + animation.lastSampleTick - tick + 1
        let phase: Phase
        switch animation {
        case .branchesEnd, .cryingDanceOut: phase = .recovery
        case .branchesLoop, .cryingDanceLoop, .mistOnslaught2, .mistOnslaught3: phase = .active
        default: phase = cast.phase
        }
        let changed = cast.phase != phase
        cast.phase = phase; activeCast = cast
        if animation == .branchesEnd && rules.level >= 6 { sourceForestRainWindow = 35 }
        return changed ? [.castPhase(cast.ability, phase)] : []
    }

    private mutating func advanceSourceOwnerMotion() -> [Effect] {
        guard var cast = activeCast, var motion = ownerMotion else { return [] }
        cast.tick += 1; motion.tick += 1
        activeCast = cast; ownerMotion = motion
        var effects: [Effect] = []
        switch motion.animation {
        case .branchesStart:
            if motion.tick == 42 {
                sourceRootOwnerRemainingTicks = rules.branches.holdTicks
            }
            if motion.tick == 42 { effects += emit(ability: .branches, origin: .manual, empowered: false) }
            if motion.tick == motion.endEventTick {
                effects += changeSourceOwnerMotion(rules.level < 4 && sourceRootOwnerRemainingTicks > 0 ? .branchesLoop : .branchesEnd)
            }
        case .branchesLoop:
            // Original IntervalEnd checks at source frames 1 and 25, plus
            // AnimationEnd. Looping uses the actual early end event.
            if [2, 50, motion.endEventTick].contains(motion.tick), sourceRootOwnerRemainingTicks == 0 {
                effects += changeSourceOwnerMotion(.branchesEnd)
            } else if motion.tick == motion.endEventTick {
                effects += changeSourceOwnerMotion(.branchesLoop)
            }
        case .mistBlade:
            if motion.tick == 24 {
                mistBladeRemainingTicks = rules.blade.durationTicks
                effects.append(.mistBladeStarted(durationTicks: rules.blade.durationTicks))
            }
        case .mistOnslaught1, .mistOnslaught2, .mistOnslaught3:
            if motion.tick == 26 || (motion.animation != .mistOnslaught1 && motion.tick == 74) ||
                (motion.animation == .mistOnslaught3 && motion.tick == 112) {
                effects += emit(ability: .mistOnslaught, origin: .manual, empowered: mistBladeRemainingTicks > 0)
            }
            if motion.animation == .mistOnslaught3 && motion.tick == 114 {
                effects += emit(ability: .mistOnslaught, origin: .lastWave, empowered: mistBladeRemainingTicks > 0)
            }
            if sourceWaveContinuationRequested && onslaughtCharges > 0 &&
                ((motion.animation == .mistOnslaught1 && motion.tick == 52) ||
                 (motion.animation == .mistOnslaught2 && motion.tick == 92)) {
                onslaughtCharges -= 1; sourceWaveContinuationRequested = false
                let next: OwnerAnimation = motion.animation == .mistOnslaught1 ? .mistOnslaught2 : .mistOnslaught3
                effects += changeSourceOwnerMotion(next, preservingTick: true)
                if next == .mistOnslaught3 {
                    activeCast?.finalWave = true; activeCast?.entangled = rules.level >= 6
                }
            }
        case .cryingDanceIn, .cryingDanceLoop:
            if motion.tick == motion.endEventTick {
                effects += changeSourceOwnerMotion(sourceDanceActiveRemainingTicks > 0 ? .cryingDanceLoop : .cryingDanceOut)
            }
        case .branchesEnd, .cryingDanceOut: break
        }
        // A transition replaced/reset the projection; do not terminate it
        // using the old clip's clock or release its markers for a second time.
        if let current = ownerMotion, current.animation == motion.animation && current.tick == motion.tick {
            let phase: Phase
            if [.branchesEnd, .cryingDanceOut].contains(current.animation) { phase = .recovery }
            else if [.branchesLoop, .cryingDanceLoop].contains(current.animation) { phase = .active }
            else if current.animation == .mistBlade { phase = current.tick < 24 ? .startup : current.tick == 24 ? .active : .recovery }
            else if current.animation == .branchesStart { phase = current.tick < 64 ? .startup : .active }
            else { phase = current.tick < 26 ? .startup : .active }
            if let active = activeCast, active.phase != phase {
                activeCast?.phase = phase; effects.append(.castPhase(active.ability, phase))
            }
            if current.tick > current.lastSampleTick {
                activeCast = nil; ownerMotion = nil; sourceWaveContinuationRequested = false
                effects.append(.castEnded(cast.ability))
            }
        }
        return effects
    }

    private mutating func queueSource(_ event: SourceScheduled) {
        guard sourceScheduled.count + scheduled.count + flights.count < Self.maximumPendingEvents else {
            rejectedPendingEventCount = min(Int.max - 1, rejectedPendingEventCount) + 1; return
        }
        sourceScheduled.append(event)
    }
    private mutating func queueSourceAppearance(_ move: DuelTriadRules.SummonMove, origin: Origin,
                                                delay: Int, requiresRoot: Bool = false) {
        queueSource(.init(kind: .appearance, move: move, origin: origin, remainingTicks: delay,
            summonID: nil, stage: .primary, requiresRoot: requiresRoot))
    }
    private mutating func queueSourceAttack(_ move: DuelTriadRules.SummonMove, origin: Origin,
                                            id: UInt64, delay: Int, stage: DuelTriadRules.SummonStage = .primary) {
        queueSource(.init(kind: .attack, move: move, origin: origin, remainingTicks: delay,
            summonID: id, stage: stage, requiresRoot: false))
    }
    private mutating func scheduleSourceRain() {
        let sequence: [(DuelTriadRules.SummonMove, Int)] = [(.rainCloseFront, 1), (.rainCloseBack, 1),
            (.rainMediumFront, 30), (.rainMediumBack, 30), (.rainFarFront, 60), (.rainFarBack, 60), (.legionHammer, 112)]
        for (move, delay) in sequence {
            queueSourceAppearance(move, origin: .forestRain, delay: delay)
        }
    }
    private mutating func advanceSourceSchedule() -> [Effect] {
        for i in sourceScheduled.indices { sourceScheduled[i].remainingTicks -= 1 }
        let due = sourceScheduled.filter { $0.remainingTicks <= 0 }
        sourceScheduled.removeAll { $0.remainingTicks <= 0 }
        var effects: [Effect] = []
        for event in due {
            if event.requiresRoot && rootRemainingTicks == 0 { continue }
            switch event.kind {
            case .appearance: effects += appearSourceSoul(event.move, origin: event.origin)
            case .attack:
                if let id = event.summonID {
                    effects += emitSourceSoulAttack(event.move, origin: event.origin, summonID: id, stage: event.stage)
                }
            case .ninjatoEndMotion:
                if let id = event.summonID { effects.append(.sourceSoulMotion(summonID: id, animation: .ninjatoActiveEnd)) }
            }
        }
        return effects
    }
    private func sourceSoulFitsArena(_ move: DuelTriadRules.SummonMove) -> Bool {
        let threshold: Int
        switch move {
        case .rainCloseFront, .rainCloseBack: threshold = 150
        case .rainMediumFront, .rainMediumBack: threshold = 250
        case .rainFarFront, .rainFarBack: threshold = 350
        default: return true
        }
        guard let room = move.reverseFacing ? opponentBackRoomSourceUnits : opponentFrontRoomSourceUnits else { return false }
        return room > threshold
    }
    private mutating func appearSourceSoul(_ move: DuelTriadRules.SummonMove, origin: Origin,
                                           existingID: UInt64? = nil) -> [Effect] {
        guard sourceSoulFitsArena(move), sourceScheduled.count + flights.count + scheduled.count < Self.maximumPendingEvents,
              let id = existingID ?? takeID() else { return [] }
        if rules.level >= 6 { notches = min(rules.souls.maximumNotches, notches + 1) }
        let appearance = SoulAppearance(summonID: id, origin: origin, move: move)
        let delay: Int
        switch move {
        case .legionDefender: return [.sourceSoulAppeared(appearance)]
        case .heraldDash, .danceNinjato: delay = 4
        case .legionSword: delay = 34
        case .legionHammer, .danceRift1, .danceRift2: delay = 48
        case .danceWhirl: delay = 40
        case .danceBlast: delay = 24
        case .danceThud: delay = 42
        default: delay = 34
        }
        queueSourceAttack(move, origin: origin, id: id, delay: delay)
        if move == .legionHammer { queueSourceAttack(move, origin: origin, id: id, delay: 58, stage: .earthquake) }
        if move == .danceRift1 || move == .danceRift2 {
            queueSourceAttack(move, origin: origin, id: id, delay: 56, stage: .riftWave)
        }
        switch move {
        case .danceWhirl:
            sourceDanceActiveRemainingTicks = 180; queueSourceAppearance(.danceBlast, origin: .dance, delay: 90)
        case .danceBlast:
            sourceDanceActiveRemainingTicks = 180; queueSourceAppearance(.danceThud, origin: .dance, delay: 90)
        case .danceThud:
            sourceDanceActiveRemainingTicks = 180; queueSourceAppearance(.danceRift1, origin: .dance, delay: 90)
        case .danceRift1:
            sourceDanceActiveRemainingTicks = 180; queueSourceAppearance(.danceRift2, origin: .dance, delay: 3)
        default: break
        }
        return [.sourceSoulAppeared(appearance)]
    }

    private mutating func emitSourceSoulAttack(_ move: DuelTriadRules.SummonMove, origin: Origin,
                                              summonID: UInt64, stage: DuelTriadRules.SummonStage) -> [Effect] {
        guard rules.runtime != nil, let spec = rules.ability(move.ability)?.attack,
              flights.count + sourceScheduled.count + scheduled.count < Self.maximumPendingEvents,
              let id = takeID() else { return [] }
        let lifetime: Int
        switch (move, stage) {
        case (_, .earthquake): lifetime = 16
        case (_, .riftWave): lifetime = 50
        case (_, .ninjatoFinal): lifetime = 6
        case (.legionSword, _): lifetime = 18
        case (.heraldDash, _): lifetime = 36
        case (.dynastyBow, _): lifetime = 34
        case (.legionHammer, _), (.danceRift1, _), (.danceRift2, _): lifetime = 8
        case (.danceNinjato, _): lifetime = 12
        case (.danceWhirl, _): lifetime = 26
        case (.danceBlast, _): lifetime = 62
        case (.danceThud, _): lifetime = 18
        case (.legionDefender, _): return []
        default: lifetime = 34
        }
        let empowered = mistBladeRemainingTicks > 0 && stage != .earthquake
        let damage = sourceSoulDamage(move, origin: origin, stage: stage, empowered: empowered)
        let critical = move.soul == .herald && rules.level >= 4
        let delivery: DuelTriadRules.Delivery
        switch move {
        case .heraldDash, .danceNinjato: delivery = .soulDash
        case .dynastyBow, .rainCloseFront, .rainCloseBack, .rainMediumFront, .rainMediumBack,
             .rainFarFront, .rainFarBack, .entangledBow, .danceBlast: delivery = .soulArrow
        default: delivery = stage == .riftWave ? .soulArrow : .soulMelee
        }
        let attack = Attack(id: id, ability: move.ability, origin: origin, damageKind: .shadow,
            damage: damage, blockedDamage: 0, delivery: delivery, rangeMillimeters: spec.rangeMillimeters,
            projectileSpeedMillimetersPerTick: spec.speedMillimetersPerTick,
            hitboxBottomMillimeters: spec.bottomMillimeters, hitboxTopMillimeters: spec.topMillimeters,
            radiusMillimeters: spec.radiusMillimeters, activeTicks: lifetime, impact: spec.impact,
            stunTicks: spec.stunTicks, hitStopTicks: spec.hitStopTicks, blockedHitStopTicks: spec.blockedHitStopTicks,
            knocksDown: spec.knocksDown, blockable: move == .legionHammer,
            generated: true, empowered: empowered, critical: critical,
            summonID: summonID, summonMove: move, summonStage: stage)
        flights.append(.init(attack: attack, remaining: lifetime))
        return [.attack(attack), .soulSummoned(move.soul, origin, attackID: id)]
    }

    private func sourceSoulDamage(_ move: DuelTriadRules.SummonMove, origin: Origin,
                                  stage: DuelTriadRules.SummonStage, empowered: Bool) -> Int {
        guard let runtime = rules.runtime else { return 0 }
        let coefficient: Int
        switch (move, stage) {
        case (_, .earthquake), (_, .ninjatoFinal): coefficient = 1000
        case (_, .riftWave): coefficient = 2500
        case (.legionSword, _): coefficient = 2200
        case (.heraldDash, _): coefficient = 1500
        case (.dynastyBow, _): coefficient = 3000
        case (.legionHammer, _), (.danceRift1, _), (.danceRift2, _): coefficient = 1000
        case (.danceNinjato, _): coefficient = 1200
        case (.danceWhirl, _), (.danceBlast, _): coefficient = 2000
        case (.danceThud, _): coefficient = 2700
        case (.legionDefender, _): return 0
        default: coefficient = 400
        }
        var damage = shadowDamage(runtime.normalizedMagicPower * coefficient / 10_000)
        if origin == .dance && stage != .riftWave { damage *= 2 }
        if empowered && stage != .earthquake { damage = scaled(damage, bonusBps: rules.blade.waveAndSoulBonusBps) }
        if move.soul == .herald && rules.level >= 4 {
            damage = damage * runtime.commonCriticalMultiplierBps / 10_000
        }
        return damage
    }
    private mutating func release(_ cast: Cast) -> [Effect] {
        if cast.ability == .mistBlade {
            mistBladeRemainingTicks = rules.blade.durationTicks
            return [.mistBladeStarted(durationTicks: rules.blade.durationTicks)]
        }
        if cast.ability == .cryingDance {
            return summonSequence(count: rules.souls.danceCount, interval: rules.souls.danceIntervalTicks,
                                  origin: .dance, castID: cast.id)
        }
        var result = emit(ability: cast.ability, origin: .manual, empowered: cast.empowered)
        if cast.ability == .mistOnslaught {
            if cast.finalWave {
                if rules.blade.doubleWaveDelayTicks == 0 {
                    result += emit(ability: .mistOnslaught, origin: .lastWave, empowered: cast.empowered)
                } else {
                    schedule(.init(ability: .mistOnslaught, origin: .lastWave,
                        remaining: rules.blade.doubleWaveDelayTicks, empowered: cast.empowered, castID: nil))
                }
            }
            if cast.entangled && rootRemainingTicks == 0 && !hasUnresolvedRoot {
                result += emit(ability: .branches, origin: .entangled, empowered: false)
            }
        }
        return result
    }
    private mutating func soulAppeared(_ soul: Soul, origin: Origin, summonID: UInt64) -> [Effect] {
        if rules.level >= 6 { notches = min(rules.souls.maximumNotches, notches + 1) }
        return [.soulAppeared(soul, origin, summonID: summonID)]
    }
    private mutating func emit(ability: Ability, origin: Origin, empowered: Bool,
                               summonID existingSummonID: UInt64? = nil) -> [Effect] {
        guard let spec = rules.ability(ability)?.attack else { return [] }
        guard flights.count + scheduled.count < Self.maximumPendingEvents else {
            rejectedPendingEventCount = min(Int.max - 1, rejectedPendingEventCount) + 1; return []
        }
        var result: [Effect] = []
        var summonID = existingSummonID
        if let soul = ability.soul, summonID == nil {
            guard nextID < UInt64.max - 1, let newID = takeID() else { return [] }
            summonID = newID
            result += soulAppeared(soul, origin: origin, summonID: newID)
        }
        guard let id = takeID() else { return [] }
        if rules.runtime != nil && ability == .branches {
            // The 31-frame root model explicitly sets SelfEndFrame=0. Its
            // unlatched AnimationEnd is tick 60, not the default early tick52.
            sourceRootModelID = id; sourceRootModelRemainingTicks = 60
        }
        let wave = ability == .mistOnslaught
        let tangible = !wave || empowered
        let bonus = empowered && (wave || ability.soul != nil) ? rules.blade.waveAndSoulBonusBps : 0
        let attack = Attack(id: id, ability: ability, origin: origin, damageKind: .shadow,
            damage: tangible ? shadowDamage(scaled(spec.damage, bonusBps: bonus)) : 0,
            blockedDamage: tangible ? shadowDamage(scaled(spec.blockedDamage, bonusBps: bonus)) : 0,
            delivery: spec.delivery, rangeMillimeters: spec.rangeMillimeters,
            projectileSpeedMillimetersPerTick: spec.speedMillimetersPerTick,
            hitboxBottomMillimeters: spec.bottomMillimeters, hitboxTopMillimeters: spec.topMillimeters,
            radiusMillimeters: spec.radiusMillimeters, activeTicks: spec.lifetimeTicks, impact: spec.impact,
            stunTicks: tangible ? spec.stunTicks : 0, hitStopTicks: tangible ? spec.hitStopTicks : 0,
            blockedHitStopTicks: tangible ? spec.blockedHitStopTicks : 0, knocksDown: tangible && spec.knocksDown,
            blockable: spec.delivery != .roots && tangible && rules.runtime?.commonSoulAndWaveUnblockable != true,
            generated: ability.soul != nil || origin != .manual,
            empowered: empowered, critical: ability == .herald && rules.level >= 4, summonID: summonID,
            activationDelayTicks: rules.runtime == nil ? 0 : ability == .branches ? 22 : ability == .mistOnslaught ? 4 : 0)
        flights.append(.init(attack: attack, remaining: attack.activeTicks))
        result.append(.attack(attack))
        if let soul = ability.soul {
            result.append(.soulSummoned(soul, origin, attackID: id))
        }
        return result
    }
    private mutating func schedule(_ event: Scheduled) {
        guard flights.count + scheduled.count < Self.maximumPendingEvents else {
            rejectedPendingEventCount = min(Int.max - 1, rejectedPendingEventCount) + 1; return
        }
        scheduled.append(event)
    }
    private mutating func summonSequence(count: Int, interval: Int, origin: Origin, castID: UInt64?) -> [Effect] {
        var result: [Effect] = []
        for i in 0..<count {
            let soul = rules.souls.sequence[i % rules.souls.sequence.count]
            let ability: Ability = soul == .legionary ? .legionary : soul == .herald ? .herald : .dynast
            if i == 0 { result += emit(ability: ability, origin: origin, empowered: mistBladeRemainingTicks > 0) }
            else {
                schedule(.init(ability: ability, origin: origin, remaining: i * interval,
                               empowered: mistBladeRemainingTicks > 0, castID: castID))
            }
        }
        return result
    }
    private mutating func applySuppression(sourceID: UInt64) -> [Effect] {
        var result: [Effect] = []
        if suppression.count == rules.suppression.maximumStacks {
            result.append(.suppressionEnded(sourceID: suppression.removeFirst().sourceID))
        }
        let total: Int
        if let runtime = rules.runtime {
            let bonus = mistBladeRemainingTicks > 0 ? runtime.suppressionBladeBonusBps : 0
            total = (opponentMaximumHealth ?? 0) * runtime.suppressionHealthFractionBps * (10_000 + bonus) / 100_000_000
        } else { total = rules.suppression.totalTrueDamage }
        suppression.append(.init(sourceID: sourceID, total: total,
                                 duration: rules.suppression.durationTicks, elapsed: 0))
        result.append(.suppressionApplied(sourceID: sourceID, durationTicks: rules.suppression.durationTicks))
        return result
    }
    private static func appendAmount(_ entry: TimedAmount, to entries: inout [TimedAmount], maximum: Int) {
        if entries.count == maximum { entries.removeFirst() }
        entries.append(entry)
    }
    private mutating func restoreMistFromContact(blocked: Bool, generated: Bool, sourceID: UInt64) {
        guard !suppression.isEmpty, !blocked || rules.policies.blockedHitsRestoreMist,
              !generated || rules.policies.generatedHitsRestoreMist else { return }
        let amount = rules.mist.suppressedHitGain * (10_000 + (rules.level >= 5 ? rules.mist.level5GainBonusBps : 0)) / 10_000
        if let runtime = rules.runtime {
            if sourceHitMistGain != nil {
                // A hit refreshes the single expiry timer. It does not reset
                // the in-progress pulse or create another recovery stream.
                sourceHitMistGain?.remainingTicks = rules.mist.gainDurationTicks
            } else {
                sourceHitMistGain = .init(remainingTicks: rules.mist.gainDurationTicks,
                    pulseRemainingTicks: runtime.mistGainFirstPulseDelayTicks, remainder: 0)
            }
            return
        }
        if !rules.policies.stackMistRegeneration { mistGains.removeAll() }
        Self.appendAmount(.init(sourceID: sourceID, total: amount, duration: rules.mist.gainDurationTicks, elapsed: 0),
                     to: &mistGains, maximum: 64)
    }
    private mutating func pulse(sourceID: UInt64, kind: DamagePulse.Kind, damageKind: DamageKind,
                                damage: Int, canKill: Bool) -> [Effect] {
        guard damage > 0, let id = takeID() else { return [] }
        return [.damagePulse(.init(id: id, sourceID: sourceID, kind: kind, damageKind: damageKind,
                                  damage: damage, canKill: canKill))]
    }
    private mutating func advanceAmounts() -> [Effect] {
        let statusStep = rules.runtime?.statusPulseStepTicks ?? 1
        func advance(_ value: inout TimedAmount, interval: Int = 1) -> Int {
            let before = value.total * value.lastPulseElapsed / value.duration
            value.elapsed += 1
            guard value.elapsed % interval == 0 || value.elapsed == value.duration else { return 0 }
            value.lastPulseElapsed = value.elapsed
            return value.total * value.elapsed / value.duration - before
        }
        var result: [Effect] = []
        for i in suppression.indices {
            let amount = advance(&suppression[i], interval: statusStep), source = suppression[i].sourceID
            result += pulse(sourceID: source, kind: .suppression, damageKind: .trueDamage, damage: amount, canKill: false)
            if suppression[i].elapsed == suppression[i].duration { result.append(.suppressionEnded(sourceID: source)) }
        }
        suppression.removeAll { $0.elapsed >= $0.duration }
        for i in poison.indices {
            let amount = advance(&poison[i], interval: statusStep), source = poison[i].sourceID
            result += pulse(sourceID: source, kind: .poison, damageKind: .trueDamage,
                            damage: amount, canKill: rules.policies.poisonCanKill)
        }
        poison.removeAll { $0.elapsed >= $0.duration }
        for i in mistGains.indices { let amount = advance(&mistGains[i]); gainMist(amount) }
        mistGains.removeAll { $0.elapsed >= $0.duration }
        for i in failedRootDamage.indices {
            let sourceID = failedRootDamage[i].sourceID, amount = advance(&failedRootDamage[i])
            result += pulse(sourceID: sourceID, kind: .branches,
                            damageKind: .trueDamage, damage: amount, canKill: true)
        }
        failedRootDamage.removeAll { $0.elapsed >= $0.duration }
        if let runtime = rules.runtime {
            if var gain = sourceHitMistGain {
                gain.remainingTicks -= 1; gain.pulseRemainingTicks -= 1
                if gain.pulseRemainingTicks <= 0 {
                    let numerator = rules.mist.suppressedHitGain + gain.remainder
                    gainMist(numerator / runtime.mistGainPulseCount)
                    gain.remainder = numerator % runtime.mistGainPulseCount
                    gain.pulseRemainingTicks = runtime.mistGainPulseIntervalTicks
                }
                sourceHitMistGain = gain.remainingTicks > 0 ? gain : nil
            }
            if var gain = sourceForestMistGain {
                gain.pulseRemainingTicks -= 1
                if gain.pulseRemainingTicks <= 0 {
                    let numerator = rules.forest.curseMistGain + gain.remainder
                    gainMist(numerator / runtime.forestGainPulseCount)
                    gain.remainder = numerator % runtime.forestGainPulseCount
                    gain.pulseRemainingTicks = runtime.forestGainPulseIntervalTicks
                    gain.remainingTicks -= 1
                }
                sourceForestMistGain = gain.remainingTicks > 0 ? gain : nil
            }
        }
        return result
    }
}

extension DuelTriadState.Attack {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.u64(id); try writer.string(ability.rawValue); try writer.string(origin.rawValue)
        try writer.string(damageKind.rawValue); try writer.string(delivery.rawValue)
        try writer.array([damage, blockedDamage, rangeMillimeters, projectileSpeedMillimetersPerTick,
            hitboxBottomMillimeters, hitboxTopMillimeters, radiusMillimeters, activeTicks,
            impact.distanceMillimeters, impact.durationTicks, impact.launchVelocityMillimetersPerTick,
            impact.gravityMillimetersPerTickSquared, stunTicks, hitStopTicks, blockedHitStopTicks]) { try $0.int($1) }
        try writer.bool(knocksDown); try writer.bool(blockable); try writer.bool(generated)
        try writer.bool(empowered); try writer.bool(critical)
        try writer.optional(summonID) { try $0.u64($1) }
        try writer.optional(summonMove) { try $0.string($1.rawValue) }
        try writer.optional(summonStage) { try $0.string($1.rawValue) }
        try writer.int(activationDelayTicks)
    }
}
extension DuelTriadState.Control {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.u64(sourceID); try writer.string(kind.rawValue); try writer.int(durationTicks)
    }
}
extension DuelTriadState.DamagePulse {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.u64(id); try writer.u64(sourceID); try writer.string(kind.rawValue)
        try writer.string(damageKind.rawValue); try writer.int(damage); try writer.bool(canKill)
    }
}
extension DuelTriadState.Effect {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        switch self {
        case .attack(let value): try writer.u8(0); try value.appendReplayState(to: &writer)
        case .control(let value): try writer.u8(1); try value.appendReplayState(to: &writer)
        case .controlReleased(let id, let kind): try writer.u8(2); try writer.u64(id); try writer.string(kind.rawValue)
        case .damagePulse(let value): try writer.u8(3); try value.appendReplayState(to: &writer)
        case .castPhase(let ability, let phase): try writer.u8(4); try writer.string(ability.rawValue); try writer.string(phase.rawValue)
        case .castEnded(let ability): try writer.u8(5); try writer.string(ability.rawValue)
        case .castInterrupted(let ability): try writer.u8(6); try writer.string(ability.rawValue)
        case .forestStarted(let round): try writer.u8(7); try writer.int(round)
        case .forestEnded: try writer.u8(8)
        case .mistBladeStarted(let ticks): try writer.u8(9); try writer.int(ticks)
        case .mistBladeEnded: try writer.u8(10)
        case .suppressionApplied(let id, let ticks): try writer.u8(11); try writer.u64(id); try writer.int(ticks)
        case .suppressionEnded(let id): try writer.u8(12); try writer.u64(id)
        case .soulSummoned(let soul, let origin, let id):
            try writer.u8(13); try writer.string(soul.rawValue); try writer.string(origin.rawValue); try writer.u64(id)
        case .feast(let gain): try writer.u8(14); try writer.int(gain)
        case .deflected(let id): try writer.u8(15); try writer.u64(id)
        case .soulAppeared(let soul, let origin, let id):
            try writer.u8(16); try writer.string(soul.rawValue); try writer.string(origin.rawValue); try writer.u64(id)
        case .sourceSoulAppeared(let appearance):
            try writer.u8(17); try appearance.appendReplayState(to: &writer)
        case .sourceSoulMotion(let id, let animation):
            try writer.u8(18); try writer.u64(id); try writer.string(animation.rawValue)
        case .sourceRootModelEnded(let id): try writer.u8(19); try writer.u64(id)
        }
    }
}
extension DuelTriadState {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try rules.appendReplayState(to: &writer)
        try writer.array([mist, notches, onslaughtCharges, mistBladeRemainingTicks, rootRemainingTicks,
            curseDebuffRemainingTicks, curseCooldown, deflectCooldown, rootPulseRemaining,
            chainCount, chainRemaining, rejectedPendingEventCount, sharedSoulCooldownRemainingTicks]) { try $0.int($1) }
        try writer.array([sourceRootOwnerRemainingTicks, sourceRootModelRemainingTicks,
            sourceDanceActiveRemainingTicks, sourceDefenderProtectionRemainingTicks,
            sourceForestRainCooldown, sourceForestRainWindow]) { try $0.int($1) }
        try writer.bool(sourceWaveContinuationRequested)
        try writer.optional(sourceRootModelID) { try $0.u64($1) }
        try writer.optional(ownerMotion) { writer, value in
            try writer.string(value.animation.rawValue); try writer.int(value.tick)
        }
        try writer.bool(breakthroughReady); try writer.bool(mistBladeUnlocked); try writer.bool(roundActive)
        try writer.optional(roundID) { try $0.int($1) }
        try writer.string(opponentArmor.rawValue); try writer.string(opponentWeapon.rawValue)
        try writer.optional(opponentMaximumHealth) { try $0.int($1) }
        try writer.optional(opponentFrontRoomSourceUnits) { try $0.int($1) }
        try writer.optional(opponentBackRoomSourceUnits) { try $0.int($1) }
        try writer.u64(nextID); try writer.u64(randomState)
        for fence in [rootSourceID, lastContactID, lastWeaponEventID, lastWeaponStartID,
                      lastShadowEventID, lastDefenceEventID, lastRoundEventID] {
            try writer.optional(fence) { try $0.u64($1) }
        }
        try writer.array(cooldowns) { try $0.int($1) }
        try writer.optional(activeCast) { writer, value in
            try writer.u64(value.id); try writer.string(value.ability.rawValue)
            try writer.int(value.tick); try writer.int(value.duration); try writer.string(value.phase.rawValue)
            try writer.bool(value.empowered); try writer.bool(value.finalWave); try writer.bool(value.entangled)
        }
        for amounts in [suppression, poison, mistGains, failedRootDamage] {
            try writer.array(amounts) { writer, value in
                try writer.u64(value.sourceID); try writer.int(value.total)
                try writer.int(value.duration); try writer.int(value.elapsed); try writer.int(value.lastPulseElapsed)
            }
        }
        for gain in [sourceHitMistGain, sourceForestMistGain] {
            try writer.optional(gain) { writer, value in
                try writer.int(value.remainingTicks); try writer.int(value.pulseRemainingTicks)
                try writer.int(value.remainder)
            }
        }
        try writer.array(flights, limit: Self.maximumPendingEvents) { writer, value in
            try value.attack.appendReplayState(to: &writer); try writer.int(value.remaining)
        }
        try writer.array(scheduled, limit: Self.maximumPendingEvents) { writer, value in
            try writer.string(value.ability.rawValue); try writer.string(value.origin.rawValue)
            try writer.int(value.remaining); try writer.bool(value.empowered)
            try writer.optional(value.castID) { try $0.u64($1) }
            try writer.optional(value.summonID) { try $0.u64($1) }
        }
        try writer.array(sourceScheduled, limit: Self.maximumPendingEvents) { writer, value in
            try writer.string(value.kind.rawValue); try writer.string(value.move.rawValue)
            try writer.string(value.origin.rawValue); try writer.int(value.remainingTicks)
            try writer.optional(value.summonID) { try $0.u64($1) }
            try writer.string(value.stage.rawValue); try writer.bool(value.requiresRoot)
        }
    }
}
