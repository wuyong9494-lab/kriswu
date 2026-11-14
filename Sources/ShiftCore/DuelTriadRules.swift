import Foundation

/// DFT / H17 is a separate Ninjato interpreter. The supplied IPA's decoded
/// production triggers establish L1–L6 runtime values independently of the
/// localization's display substitutions.
/// Every numerical group below carries its own provenance. `debug` is an
/// explicit application profile, never a recovered original-game balance table.
public struct DuelTriadRules: Codable, Equatable, Sendable {
    public enum Ability: String, Codable, CaseIterable, Sendable {
        case branches, mistBlade, mistOnslaught, legionary, herald, dynast, cryingDance
        public var minimumLevel: Int { self == .cryingDance ? 6 : 2 }
        public var sourceRole: String {
            switch self {
            case .branches: return "triadBranches"
            case .mistBlade: return "triadMistBlade"
            case .mistOnslaught: return "triadMistOnslaught"
            case .legionary: return "triadLegionary"
            case .herald: return "triadHerald"
            case .dynast: return "triadDynast"
            case .cryingDance: return "triadCryingDance"
            }
        }
        public var motionRole: String { sourceRole }
        /// Application UI translations; these are not quoted retail CN labels.
        public var title: String {
            switch self {
            case .branches: return "枝蔓囚笼"
            case .mistBlade: return "雾刃"
            case .mistOnslaught: return "雾潮"
            case .legionary: return "军团魂魄"
            case .herald: return "先锋魂魄"
            case .dynast: return "王朝魂魄"
            case .cryingDance: return "恸哭之舞"
            }
        }
        public var soul: Soul? {
            switch self {
            case .legionary: return .legionary
            case .herald: return .herald
            case .dynast: return .dynast
            default: return nil
            }
        }
    }
    public enum Soul: String, Codable, CaseIterable, Sendable { case legionary, herald, dynast }
    public enum DamageKind: String, Codable, CaseIterable, Sendable { case weapon, unarmed, shadow, trueDamage }
    public enum Delivery: String, Codable, Sendable { case mistWave, roots, soulMelee, soulDash, soulArrow }
    public enum Faction: String, Codable, Sendable { case legion, dynasty, herald, unknown }
    public enum Basis: String, Codable, Sendable { case applicationAdaptation, referenceMeasurement, sourceConfiguration }

    public struct Evidence: Codable, Equatable, Sendable {
        public var basis: Basis
        public var version: String
        public var references: [String]
        public init(basis: Basis, version: String, references: [String]) {
            self.basis = basis; self.version = version; self.references = references
        }
    }
    public struct AttackSpec: Codable, Equatable, Sendable {
        public var evidence: Evidence
        public var damage: Int
        public var blockedDamage: Int
        public var delivery: Delivery
        public var rangeMillimeters: Int
        public var speedMillimetersPerTick: Int
        public var bottomMillimeters: Int
        public var topMillimeters: Int
        public var radiusMillimeters: Int
        public var lifetimeTicks: Int
        public var impact: DuelImpactResponse
        public var stunTicks: Int
        public var hitStopTicks: Int
        public var blockedHitStopTicks: Int
        public var knocksDown: Bool
        public init(evidence: Evidence, damage: Int, blockedDamage: Int, delivery: Delivery,
                    rangeMillimeters: Int, speedMillimetersPerTick: Int, bottomMillimeters: Int,
                    topMillimeters: Int, radiusMillimeters: Int, lifetimeTicks: Int,
                    impact: DuelImpactResponse, stunTicks: Int, hitStopTicks: Int,
                    blockedHitStopTicks: Int, knocksDown: Bool) {
            self.evidence = evidence; self.damage = damage; self.blockedDamage = blockedDamage
            self.delivery = delivery; self.rangeMillimeters = rangeMillimeters
            self.speedMillimetersPerTick = speedMillimetersPerTick; self.bottomMillimeters = bottomMillimeters
            self.topMillimeters = topMillimeters; self.radiusMillimeters = radiusMillimeters
            self.lifetimeTicks = lifetimeTicks; self.impact = impact; self.stunTicks = stunTicks
            self.hitStopTicks = hitStopTicks; self.blockedHitStopTicks = blockedHitStopTicks; self.knocksDown = knocksDown
        }
    }
    public struct AbilityRule: Codable, Equatable, Sendable {
        public var evidence: Evidence
        public var ability: Ability
        public var startupTicks: Int
        public var activeTicks: Int
        public var recoveryTicks: Int
        public var cooldownTicks: Int
        public var mistCost: Int
        public var interruptible: Bool
        public var attack: AttackSpec?
        public var duration: Int { startupTicks + activeTicks + recoveryTicks }
        public init(evidence: Evidence, ability: Ability, startupTicks: Int, activeTicks: Int,
                    recoveryTicks: Int, cooldownTicks: Int, mistCost: Int,
                    interruptible: Bool, attack: AttackSpec?) {
            self.evidence = evidence; self.ability = ability; self.startupTicks = startupTicks
            self.activeTicks = activeTicks; self.recoveryTicks = recoveryTicks
            self.cooldownTicks = cooldownTicks; self.mistCost = mistCost
            self.interruptible = interruptible; self.attack = attack
        }
    }
    public struct Mist: Codable, Equatable, Sendable {
        public var evidence: Evidence
        public var maximum: Int
        public var initial: Int
        public var suppressedHitGain: Int
        public var gainDurationTicks: Int
        public var level5GainBonusBps: Int
        public var feastGain: Int
        public var betweenRoundsRetainedBps: Int
        public init(evidence: Evidence, maximum: Int, initial: Int, suppressedHitGain: Int,
                    gainDurationTicks: Int, level5GainBonusBps: Int, feastGain: Int, betweenRoundsRetainedBps: Int) {
            self.evidence = evidence; self.maximum = maximum; self.initial = initial
            self.suppressedHitGain = suppressedHitGain; self.gainDurationTicks = gainDurationTicks
            self.level5GainBonusBps = level5GainBonusBps; self.feastGain = feastGain
            self.betweenRoundsRetainedBps = betweenRoundsRetainedBps
        }
    }
    public struct Forest: Codable, Equatable, Sendable {
        public var evidence: Evidence
        public var curseChanceBps: Int
        public var stunTicks: Int
        public var physicalReductionBps: Int
        public var debuffTicks: Int
        public var curseMistGain: Int
        public var triggerCooldownTicks: Int
        public init(evidence: Evidence, curseChanceBps: Int, stunTicks: Int, physicalReductionBps: Int,
                    debuffTicks: Int, curseMistGain: Int, triggerCooldownTicks: Int) {
            self.evidence = evidence; self.curseChanceBps = curseChanceBps; self.stunTicks = stunTicks
            self.physicalReductionBps = physicalReductionBps; self.debuffTicks = debuffTicks
            self.curseMistGain = curseMistGain; self.triggerCooldownTicks = triggerCooldownTicks
        }
    }
    public struct Suppression: Codable, Equatable, Sendable {
        public var evidence: Evidence
        public var durationTicks: Int
        public var totalTrueDamage: Int
        public var outgoingReductionPerStackBps: Int
        public var maximumStacks: Int
        public var maximumOutgoingReductionBps: Int
        public var level6ShadowDefenseReductionBps: Int
        public init(evidence: Evidence, durationTicks: Int, totalTrueDamage: Int,
                    outgoingReductionPerStackBps: Int, maximumStacks: Int,
                    maximumOutgoingReductionBps: Int, level6ShadowDefenseReductionBps: Int) {
            self.evidence = evidence; self.durationTicks = durationTicks; self.totalTrueDamage = totalTrueDamage
            self.outgoingReductionPerStackBps = outgoingReductionPerStackBps; self.maximumStacks = maximumStacks
            self.maximumOutgoingReductionBps = maximumOutgoingReductionBps
            self.level6ShadowDefenseReductionBps = level6ShadowDefenseReductionBps
        }
    }
    public struct Blade: Codable, Equatable, Sendable {
        public var evidence: Evidence
        public var durationTicks: Int
        public var weaponBonusBps: Int
        public var shadowConversionBps: Int
        public var waveAndSoulBonusBps: Int
        public var initialOnslaughtCharges: Int
        public var doubleWaveDelayTicks: Int
        public var chainWindowTicks: Int
        public init(evidence: Evidence, durationTicks: Int, weaponBonusBps: Int,
                    shadowConversionBps: Int, waveAndSoulBonusBps: Int,
                    initialOnslaughtCharges: Int, doubleWaveDelayTicks: Int, chainWindowTicks: Int) {
            self.evidence = evidence; self.durationTicks = durationTicks; self.weaponBonusBps = weaponBonusBps
            self.shadowConversionBps = shadowConversionBps; self.waveAndSoulBonusBps = waveAndSoulBonusBps
            self.initialOnslaughtCharges = initialOnslaughtCharges; self.doubleWaveDelayTicks = doubleWaveDelayTicks
            self.chainWindowTicks = chainWindowTicks
        }
    }
    public struct Branches: Codable, Equatable, Sendable {
        public var evidence: Evidence
        public var holdTicks: Int
        public var pulseIntervalTicks: Int
        public var pulseDamage: Int
        public var escapingBurstDamage: Int
        public var suppressedDamageBonusBps: Int
        public var rootedSoulBonusBps: Int
        public var entangledHoldReductionTicks: Int
        public init(evidence: Evidence, holdTicks: Int, pulseIntervalTicks: Int, pulseDamage: Int,
                    escapingBurstDamage: Int, suppressedDamageBonusBps: Int,
                    rootedSoulBonusBps: Int, entangledHoldReductionTicks: Int) {
            self.evidence = evidence; self.holdTicks = holdTicks; self.pulseIntervalTicks = pulseIntervalTicks
            self.pulseDamage = pulseDamage; self.escapingBurstDamage = escapingBurstDamage
            self.suppressedDamageBonusBps = suppressedDamageBonusBps; self.rootedSoulBonusBps = rootedSoulBonusBps
            self.entangledHoldReductionTicks = entangledHoldReductionTicks
        }
    }
    public struct Souls: Codable, Equatable, Sendable {
        public var evidence: Evidence
        /// Shared gate between manually requested souls. The supplied runtime
        /// sets SET_H17_SPIRIT_CD to 30 ticks independently of each soul's CD.
        public var sharedCooldownTicks: Int
        public var hungryDeflectCooldownTicks: Int
        public var poisonDurationTicks: Int
        public var poisonDamageBps: Int
        public var maximumPoisonStacks: Int
        public var forestRainCount: Int
        public var forestRainIntervalTicks: Int
        public var danceCount: Int
        public var danceIntervalTicks: Int
        public var notchCost: Int
        public var maximumNotches: Int
        /// This is an explicit application/source profile order, not one guessed
        /// from the localization's statement that souls use different moves.
        public var sequence: [Soul]
        public init(evidence: Evidence, hungryDeflectCooldownTicks: Int, poisonDurationTicks: Int,
                    poisonDamageBps: Int, maximumPoisonStacks: Int, forestRainCount: Int,
                    forestRainIntervalTicks: Int, danceCount: Int, danceIntervalTicks: Int,
                    notchCost: Int, maximumNotches: Int, sequence: [Soul], sharedCooldownTicks: Int = 0) {
            self.evidence = evidence; self.hungryDeflectCooldownTicks = hungryDeflectCooldownTicks
            self.sharedCooldownTicks = sharedCooldownTicks
            self.poisonDurationTicks = poisonDurationTicks; self.poisonDamageBps = poisonDamageBps
            self.maximumPoisonStacks = maximumPoisonStacks; self.forestRainCount = forestRainCount
            self.forestRainIntervalTicks = forestRainIntervalTicks; self.danceCount = danceCount
            self.danceIntervalTicks = danceIntervalTicks; self.notchCost = notchCost
            self.maximumNotches = maximumNotches; self.sequence = sequence
        }
    }
    public struct Flavours: Codable, Equatable, Sendable {
        public var evidence: Evidence
        public var legionWeaponReductionBps: Int
        public var legionShadowReductionBps: Int
        public var dynastyUnarmedReductionBps: Int
        public var dynastyShadowReductionBps: Int
        public var heraldCriticalCooldownBonusBps: Int
        public var heraldShadowGainReductionBps: Int
        public init(evidence: Evidence, legionWeaponReductionBps: Int, legionShadowReductionBps: Int,
                    dynastyUnarmedReductionBps: Int, dynastyShadowReductionBps: Int,
                    heraldCriticalCooldownBonusBps: Int, heraldShadowGainReductionBps: Int) {
            self.evidence = evidence; self.legionWeaponReductionBps = legionWeaponReductionBps
            self.legionShadowReductionBps = legionShadowReductionBps
            self.dynastyUnarmedReductionBps = dynastyUnarmedReductionBps
            self.dynastyShadowReductionBps = dynastyShadowReductionBps
            self.heraldCriticalCooldownBonusBps = heraldCriticalCooldownBonusBps
            self.heraldShadowGainReductionBps = heraldShadowGainReductionBps
        }
    }
    public struct Policies: Codable, Equatable, Sendable {
        public var evidence: Evidence
        public var blockedHitsRestoreMist: Bool
        public var generatedHitsRestoreMist: Bool
        public var stackMistRegeneration: Bool
        public var suppressionOnBlockedWave: Bool
        public var resetChainOnOtherAbility: Bool
        public var resetChainOnWeaponStart: Bool
        public var resetCooldownsBetweenRounds: Bool
        public var poisonCanKill: Bool
        public init(evidence: Evidence, blockedHitsRestoreMist: Bool, generatedHitsRestoreMist: Bool,
                    stackMistRegeneration: Bool, suppressionOnBlockedWave: Bool,
                    resetChainOnOtherAbility: Bool, resetChainOnWeaponStart: Bool,
                    resetCooldownsBetweenRounds: Bool, poisonCanKill: Bool) {
            self.evidence = evidence; self.blockedHitsRestoreMist = blockedHitsRestoreMist
            self.generatedHitsRestoreMist = generatedHitsRestoreMist; self.stackMistRegeneration = stackMistRegeneration
            self.suppressionOnBlockedWave = suppressionOnBlockedWave
            self.resetChainOnOtherAbility = resetChainOnOtherAbility; self.resetChainOnWeaponStart = resetChainOnWeaponStart
            self.resetCooldownsBetweenRounds = resetCooldownsBetweenRounds; self.poisonCanKill = poisonCanKill
        }
    }

    public var id: String
    public var evidence: Evidence
    public var level: Int
    public var maximumHealth: Int
    public var level1ShadowBonusBps: Int
    public var mist: Mist
    public var forest: Forest
    public var suppression: Suppression
    public var blade: Blade
    public var branches: Branches
    public var souls: Souls
    public var flavours: Flavours
    public var policies: Policies
    public var abilities: [AbilityRule]
    /// Present only for the decoded production runtime. The application still
    /// supplies arena geometry and its explicit MagicPower-to-health scale.
    public var runtime: RuntimeProfile? = nil
    public var basis: Basis { evidence.basis }
    public var sourceVersion: String { evidence.version }
    public static let maximumOnslaughtCharges = 3 // Explicit literal in H17 L2 text.
    public static let semanticSourceIDs = ["user-ipa-1.46.1:H17_set_upgrade_1_desc",
        "user-ipa-1.46.1:H17_set_upgrade_2_desc", "user-ipa-1.46.1:H17_set_upgrade_3_desc",
        "user-ipa-1.46.1:H17_set_upgrade_4_desc", "user-ipa-1.46.1:H17_set_upgrade_5_desc",
        "user-ipa-1.46.1:H17_set_upgrade_6_desc"]
    public func ability(_ ability: Ability) -> AbilityRule? { abilities.first { $0.ability == ability } }
    public enum ValidationError: Error, Equatable { case identity, provenance, level, resource, timing, damage, ability, capacity }

    public func validate() throws {
        func bounded(_ value: Int, _ upper: Int = 36_000) -> Bool { (0...upper).contains(value) }
        func bps(_ value: Int) -> Bool { bounded(value, 10_000) }
        func provenance(_ value: Evidence) -> Bool {
            !value.version.isEmpty && value.version.utf8.count <= 256 && (1...32).contains(value.references.count) &&
                value.references.allSatisfy { !$0.isEmpty && $0.utf8.count <= 1024 }
        }
        guard !id.isEmpty, id.utf8.count <= 128, (1...1_000_000).contains(maximumHealth) else { throw ValidationError.identity }
        // The local source contains no L7/L8 description. Public beta footage
        // and an official release announcement do not supply a numeric profile.
        guard (1...6).contains(level) else { throw ValidationError.level }
        guard [evidence, mist.evidence, forest.evidence, suppression.evidence, blade.evidence,
               branches.evidence, souls.evidence, flavours.evidence, policies.evidence].allSatisfy(provenance),
              abilities.allSatisfy({ provenance($0.evidence) && ($0.attack.map { provenance($0.evidence) } ?? true) }) else {
            throw ValidationError.provenance
        }
        guard (1...1_000_000).contains(mist.maximum), (0...mist.maximum).contains(mist.initial),
              bounded(mist.suppressedHitGain, mist.maximum), bounded(mist.feastGain, mist.maximum),
              bps(mist.betweenRoundsRetainedBps), bounded(mist.level5GainBonusBps, 100_000),
              (1...36_000).contains(mist.gainDurationTicks), bps(forest.curseChanceBps),
              bounded(forest.curseMistGain, mist.maximum) else { throw ValidationError.resource }
        guard [forest.stunTicks, forest.debuffTicks, forest.triggerCooldownTicks,
               blade.doubleWaveDelayTicks, blade.chainWindowTicks, souls.hungryDeflectCooldownTicks,
               souls.sharedCooldownTicks].allSatisfy({ bounded($0) }),
              [suppression.durationTicks, blade.durationTicks, branches.holdTicks, branches.pulseIntervalTicks,
               souls.poisonDurationTicks, souls.forestRainIntervalTicks, souls.danceIntervalTicks].allSatisfy({ (1...36_000).contains($0) }),
              (0..<branches.holdTicks).contains(branches.entangledHoldReductionTicks) else { throw ValidationError.timing }
        guard [level1ShadowBonusBps, mist.level5GainBonusBps, blade.weaponBonusBps, blade.waveAndSoulBonusBps,
               branches.suppressedDamageBonusBps, branches.rootedSoulBonusBps, souls.poisonDamageBps,
               flavours.heraldCriticalCooldownBonusBps].allSatisfy({ bounded($0, 100_000) }),
              [forest.physicalReductionBps, suppression.outgoingReductionPerStackBps,
               suppression.maximumOutgoingReductionBps, suppression.level6ShadowDefenseReductionBps,
               blade.shadowConversionBps, flavours.legionWeaponReductionBps, flavours.legionShadowReductionBps,
               flavours.dynastyUnarmedReductionBps, flavours.dynastyShadowReductionBps,
               flavours.heraldShadowGainReductionBps].allSatisfy(bps),
              [suppression.totalTrueDamage, branches.pulseDamage, branches.escapingBurstDamage].allSatisfy({ bounded($0, 1_000_000) }) else {
            throw ValidationError.damage
        }
        guard (1...64).contains(suppression.maximumStacks), (1...64).contains(souls.maximumPoisonStacks),
              (0...Self.maximumOnslaughtCharges).contains(blade.initialOnslaughtCharges),
              (1...32).contains(souls.forestRainCount), (1...32).contains(souls.danceCount),
              (1...1000).contains(souls.maximumNotches), (1...souls.maximumNotches).contains(souls.notchCost),
              (1...32).contains(souls.sequence.count) else { throw ValidationError.capacity }
        guard abilities.count == Ability.allCases.count, Set(abilities.map(\.ability)) == Set(Ability.allCases) else { throw ValidationError.ability }
        if let runtime { try runtime.validate() }
        for rule in abilities {
            guard bounded(rule.startupTicks), (1...36_000).contains(rule.activeTicks), bounded(rule.recoveryTicks),
                  bounded(rule.cooldownTicks), bounded(rule.mistCost, mist.maximum), rule.duration <= 36_000,
                  rule.ability != .cryingDance || !rule.interruptible else { throw ValidationError.timing }
            let needsAttack = [.branches, .mistOnslaught, .legionary, .herald, .dynast].contains(rule.ability)
            guard (rule.attack != nil) == needsAttack else { throw ValidationError.ability }
            if let a = rule.attack {
                guard bounded(a.damage, 1_000_000), bounded(a.blockedDamage, a.damage),
                      (1...20_000).contains(a.rangeMillimeters), bounded(a.speedMillimetersPerTick, 20_000),
                      (-10_000...10_000).contains(a.bottomMillimeters), (a.bottomMillimeters...10_000).contains(a.topMillimeters),
                      (1...10_000).contains(a.radiusMillimeters), (1...36_000).contains(a.lifetimeTicks),
                      bounded(a.stunTicks), bounded(a.hitStopTicks, 120), bounded(a.blockedHitStopTicks, 120),
                      bounded(a.impact.distanceMillimeters, 20_000), (1...36_000).contains(a.impact.durationTicks),
                      bounded(a.impact.launchVelocityMillimetersPerTick, 20_000),
                      (1...20_000).contains(a.impact.gravityMillimetersPerTickSquared) else { throw ValidationError.damage }
                let expected: Delivery = rule.ability == .branches ? .roots : rule.ability == .mistOnslaught ? .mistWave :
                    rule.ability == .legionary ? .soulMelee : rule.ability == .herald ? .soulDash : .soulArrow
                guard a.delivery == expected, expected == .roots || a.speedMillimetersPerTick > 0 else { throw ValidationError.ability }
            }
        }
        guard let dance = ability(.cryingDance), runtime != nil ||
              dance.activeTicks >= (souls.danceCount - 1) * souls.danceIntervalTicks + 1 else { throw ValidationError.timing }
    }

    /// A reproducible playable tuning profile. All balance and event timings
    /// here are application choices; the public/private references above only
    /// establish the relationships implemented by DuelTriadState.
    public static func debug(level: Int = 6) -> Self {
        let e = Evidence(basis: .applicationAdaptation, version: "triad-debug-v1-60hz",
                         references: ["Application tuning; not the separately decoded H17 production runtime"])
        let impact = DuelImpactResponse(distanceMillimeters: 160, durationTicks: 8,
            launchVelocityMillimetersPerTick: 0, gravityMillimetersPerTickSquared: DuelGame.gravity)
        func attack(_ delivery: Delivery, _ damage: Int) -> AttackSpec {
            .init(evidence: e, damage: damage, blockedDamage: damage / 5, delivery: delivery,
                rangeMillimeters: 4800, speedMillimetersPerTick: delivery == .roots ? 0 : 180,
                bottomMillimeters: 0, topMillimeters: 1900, radiusMillimeters: 220, lifetimeTicks: 90,
                impact: impact, stunTicks: 12, hitStopTicks: 4, blockedHitStopTicks: 2, knocksDown: delivery == .soulDash)
        }
        let specs: [Ability: AttackSpec] = [.branches: attack(.roots, 0), .mistOnslaught: attack(.mistWave, 90),
            .legionary: attack(.soulMelee, 130), .herald: attack(.soulDash, 110), .dynast: attack(.soulArrow, 95)]
        let abilities = Ability.allCases.map { kind in
            AbilityRule(evidence: e, ability: kind, startupTicks: kind == .branches ? 20 : 10,
                activeTicks: kind == .cryingDance ? 91 : 2, recoveryTicks: 12,
                cooldownTicks: kind == .branches ? 600 : kind.soul != nil ? 360 : kind == .mistOnslaught ? 18 : 0,
                mistCost: kind.soul != nil ? 1800 : 0, interruptible: kind != .cryingDance, attack: specs[kind])
        }
        return Self(id: "sun-triad-application-debug-v1", evidence: e, level: level,
            maximumHealth: 2000, level1ShadowBonusBps: 1000,
            mist: .init(evidence: e, maximum: 10_000, initial: 0, suppressedHitGain: 800,
                gainDurationTicks: 60, level5GainBonusBps: 2500, feastGain: 2500, betweenRoundsRetainedBps: 10_000),
            forest: .init(evidence: e, curseChanceBps: 10_000, stunTicks: 35, physicalReductionBps: 2000,
                debuffTicks: 180, curseMistGain: 1800, triggerCooldownTicks: 30),
            suppression: .init(evidence: e, durationTicks: 240, totalTrueDamage: 60, outgoingReductionPerStackBps: 1200,
                maximumStacks: 6, maximumOutgoingReductionBps: 6000, level6ShadowDefenseReductionBps: 2000),
            blade: .init(evidence: e, durationTicks: 420, weaponBonusBps: 2000, shadowConversionBps: 4000,
                waveAndSoulBonusBps: 2500, initialOnslaughtCharges: 3, doubleWaveDelayTicks: 10, chainWindowTicks: 240),
            branches: .init(evidence: e, holdTicks: 180, pulseIntervalTicks: 30, pulseDamage: 28,
                escapingBurstDamage: 90, suppressedDamageBonusBps: 2000, rootedSoulBonusBps: 2500,
                entangledHoldReductionTicks: 60),
            souls: .init(evidence: e, hungryDeflectCooldownTicks: 600, poisonDurationTicks: 180,
                poisonDamageBps: 2500, maximumPoisonStacks: 8, forestRainCount: 3, forestRainIntervalTicks: 18,
                danceCount: 6, danceIntervalTicks: 18, notchCost: 18, maximumNotches: 30,
                sequence: [.legionary, .herald, .dynast]),
            flavours: .init(evidence: e, legionWeaponReductionBps: 1000, legionShadowReductionBps: 1000,
                dynastyUnarmedReductionBps: 1000, dynastyShadowReductionBps: 1000,
                heraldCriticalCooldownBonusBps: 1500, heraldShadowGainReductionBps: 1000),
            policies: .init(evidence: e, blockedHitsRestoreMist: true, generatedHitsRestoreMist: true,
                stackMistRegeneration: false, suppressionOnBlockedWave: true, resetChainOnOtherAbility: true,
                resetChainOnWeaponStart: true, resetCooldownsBetweenRounds: true, poisonCanKill: true),
            abilities: abilities)
    }
}

extension DuelTriadRules.Evidence {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string(basis.rawValue); try writer.string(version)
        try writer.array(references) { try $0.string($1) }
    }
}
extension DuelTriadRules.AttackSpec {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try evidence.appendReplayState(to: &writer); try writer.string(delivery.rawValue)
        try writer.array([damage, blockedDamage, rangeMillimeters, speedMillimetersPerTick,
            bottomMillimeters, topMillimeters, radiusMillimeters, lifetimeTicks,
            impact.distanceMillimeters, impact.durationTicks, impact.launchVelocityMillimetersPerTick,
            impact.gravityMillimetersPerTickSquared, stunTicks, hitStopTicks, blockedHitStopTicks]) { try $0.int($1) }
        try writer.bool(knocksDown)
    }
}
extension DuelTriadRules {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string(id); try evidence.appendReplayState(to: &writer)
        try writer.int(level); try writer.int(maximumHealth); try writer.int(level1ShadowBonusBps)
        for value in [mist.evidence, forest.evidence, suppression.evidence, blade.evidence,
                      branches.evidence, souls.evidence, flavours.evidence, policies.evidence] {
            try value.appendReplayState(to: &writer)
        }
        try writer.array([mist.maximum, mist.initial, mist.suppressedHitGain, mist.gainDurationTicks,
            mist.level5GainBonusBps, mist.feastGain, mist.betweenRoundsRetainedBps,
            forest.curseChanceBps, forest.stunTicks, forest.physicalReductionBps, forest.debuffTicks,
            forest.curseMistGain, forest.triggerCooldownTicks,
            suppression.durationTicks, suppression.totalTrueDamage, suppression.outgoingReductionPerStackBps,
            suppression.maximumStacks, suppression.maximumOutgoingReductionBps, suppression.level6ShadowDefenseReductionBps,
            blade.durationTicks, blade.weaponBonusBps, blade.shadowConversionBps, blade.waveAndSoulBonusBps,
            blade.initialOnslaughtCharges, blade.doubleWaveDelayTicks, blade.chainWindowTicks,
            branches.holdTicks, branches.pulseIntervalTicks, branches.pulseDamage, branches.escapingBurstDamage,
            branches.suppressedDamageBonusBps, branches.rootedSoulBonusBps, branches.entangledHoldReductionTicks,
            souls.hungryDeflectCooldownTicks, souls.sharedCooldownTicks, souls.poisonDurationTicks, souls.poisonDamageBps,
            souls.maximumPoisonStacks, souls.forestRainCount, souls.forestRainIntervalTicks,
            souls.danceCount, souls.danceIntervalTicks, souls.notchCost, souls.maximumNotches,
            flavours.legionWeaponReductionBps, flavours.legionShadowReductionBps,
            flavours.dynastyUnarmedReductionBps, flavours.dynastyShadowReductionBps,
            flavours.heraldCriticalCooldownBonusBps, flavours.heraldShadowGainReductionBps]) { try $0.int($1) }
        try writer.array(souls.sequence) { try $0.string($1.rawValue) }
        for value in [policies.blockedHitsRestoreMist, policies.generatedHitsRestoreMist,
                      policies.stackMistRegeneration, policies.suppressionOnBlockedWave,
                      policies.resetChainOnOtherAbility, policies.resetChainOnWeaponStart,
                      policies.resetCooldownsBetweenRounds, policies.poisonCanKill] { try writer.bool(value) }
        // Ability array order does not change gameplay; canonicalize it.
        for kind in Ability.allCases {
            try writer.optional(ability(kind)) { writer, value in
                try writer.string(value.ability.rawValue); try value.evidence.appendReplayState(to: &writer)
                try writer.array([value.startupTicks, value.activeTicks, value.recoveryTicks,
                                  value.cooldownTicks, value.mistCost]) { try $0.int($1) }
                try writer.bool(value.interruptible)
                try writer.optional(value.attack) { try $1.appendReplayState(to: &$0) }
            }
        }
        try writer.optional(runtime) { try $1.appendReplayState(to: &$0) }
    }
}
