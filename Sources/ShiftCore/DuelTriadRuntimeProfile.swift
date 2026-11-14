import Foundation

extension DuelTriadRules {
    /// Normal player H17 with the black 06 / 06a Ninjato. This excludes the
    /// clan 07 weapon's alternate flag and encounter-specific boss overrides.
    /// Values describe executable production triggers, not FakeValue text.
    public struct RuntimeProfile: Codable, Equatable, Sendable {
        public var evidence: Evidence
        public var configurationSHA256: String
        public var tickRate: Int
        public var sourceFramesPerSecond: Int
        /// Explicit application normalization of the original MagicPower
        /// attribute. BaseDamage coefficients are multiplied by this value.
        public var normalizedMagicPower: Int
        /// The original ModHP coefficient (.04) multiplies the runtime's
        /// RaidDamageAmplifier. The application converts its normalized HP
        /// fraction using an explicitly supplied opponent health scale.
        public var suppressionHealthFractionBps: Int
        public var suppressionBladeBonusBps: Int
        public var mistGainFirstPulseDelayTicks: Int
        public var mistGainPulseIntervalTicks: Int
        public var mistGainPulseCount: Int
        public var forestGainPulseIntervalTicks: Int
        public var forestGainPulseCount: Int
        public var rootFailedExtraDamageBps: Int
        public var criticalPhysicalRetentionBps: Int
        public var weaponCriticalMultiplierBps: Int
        public var commonCriticalMultiplierBps: Int
        public var statusPulseStepTicks: Int
        public var shadowDamageIsAdditional: Bool
        public var commonSoulAndWaveUnblockable: Bool
        /// Optional authenticated independent-model samples. Their metre
        /// basis has unit scale; it does not inherit the character's 0.92
        /// presentation scale, pose height or projectile-speed approximation.
        /// Absence retains the explicitly adapted legacy spatial template.
        public var modelTracks: [String: DuelSummonMotionTrack]? = nil

        func validate() throws {
            guard evidence.basis == .sourceConfiguration,
                  evidence.version == "user-ipa-1.46.1/config-1.46.0.16.16733-prod/H17-06-06a",
                  !evidence.references.isEmpty, evidence.references.count <= 32,
                  evidence.references.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }),
                  configurationSHA256.count == 64,
                  configurationSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  tickRate == 60, sourceFramesPerSecond == 30,
                  (1...1_000_000).contains(normalizedMagicPower),
                  (0...10_000).contains(suppressionHealthFractionBps),
                  (0...100_000).contains(suppressionBladeBonusBps),
                  (0...36_000).contains(mistGainFirstPulseDelayTicks),
                  (1...36_000).contains(mistGainPulseIntervalTicks),
                  (1...1000).contains(mistGainPulseCount),
                  (1...36_000).contains(forestGainPulseIntervalTicks),
                  (1...1000).contains(forestGainPulseCount),
                  (0...100_000).contains(rootFailedExtraDamageBps),
                  (0...10_000).contains(criticalPhysicalRetentionBps) else {
                throw ValidationError.provenance
            }
            guard (10_000...100_000).contains(weaponCriticalMultiplierBps),
                  (10_000...100_000).contains(commonCriticalMultiplierBps),
                  (1...36_000).contains(statusPulseStepTicks) else { throw ValidationError.damage }
            if let modelTracks {
                guard Set(modelTracks.keys) == Set(["roots", "mistWave"]) else { throw ValidationError.ability }
                for (key, clip, frames, capsuleID, radius) in [
                    ("roots", "h17_root_spike_model", 31, "Common_Model_40_bottom_top", 300),
                    ("mistWave", "h17_wave_model", 22, "Common_Model_40_Attacking_Edge_Big", 1600)
                ] {
                    guard let track = modelTracks[key] else { throw ValidationError.ability }
                    try track.validate()
                    guard track.role == "triadModel_" + key, track.clip == clip, track.frames == frames,
                          track.groundLift.allSatisfy({ $0 == 0 }),
                          track.collisionEdges?.isEmpty == true,
                          let capsules = track.hurtCapsules, capsules.count == 1,
                          capsules[0].id == capsuleID, capsules[0].radiusMillimeters == radius,
                          capsules[0].defense == .body,
                          track.attackParts == ["primary": [capsuleID]] else { throw ValidationError.ability }
                }
            }
        }

        func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
            try evidence.appendReplayState(to: &writer)
            try writer.string(configurationSHA256)
            try writer.array([tickRate, sourceFramesPerSecond, normalizedMagicPower,
                suppressionHealthFractionBps, suppressionBladeBonusBps,
                mistGainFirstPulseDelayTicks, mistGainPulseIntervalTicks, mistGainPulseCount,
                forestGainPulseIntervalTicks, forestGainPulseCount, rootFailedExtraDamageBps,
                criticalPhysicalRetentionBps, weaponCriticalMultiplierBps,
                commonCriticalMultiplierBps, statusPulseStepTicks]) { try $0.int($1) }
            try writer.bool(shadowDamageIsAdditional)
            try writer.bool(commonSoulAndWaveUnblockable)
            try writer.optional(modelTracks) { writer, tracks in
                try writer.array(tracks.keys.sorted(), limit: 2) { writer, key in
                    try writer.string(key); try tracks[key]!.appendReplayState(to: &writer)
                }
            }
        }
    }

    /// Build a loadable application rule profile from recovered production
    /// timers and ratios. Arena units, hit reactions and HP/MagicPower scaling
    /// remain explicitly supplied application adaptations. No raw asset or
    /// original trigger script is embedded in this normalized profile.
    public static func h17BlackNinjato(level: Int, maximumHealth: Int,
                                      magicPower: Int, spatialTemplate: Self) throws -> Self {
        guard (1...6).contains(level) else { throw ValidationError.level }
        guard (1...1_000_000).contains(maximumHealth), (1...1_000_000).contains(magicPower) else {
            throw ValidationError.identity
        }
        try spatialTemplate.validate()
        let source = Evidence(basis: .sourceConfiguration,
            version: "user-ipa-1.46.1/config-1.46.0.16.16733-prod/H17-06-06a",
            references: [
                "split_battle_triggers:lock_1779/SET_HERALDS_17/trigger0,6,15,18,21-26,36-46;sha256=3d9dfc91bd0a0af621c0f5c784d1f9e1020867f2e87fe64dcbab52c1358cd6bc",
                "split_battle_triggers:lock_1775/trigger1-2;lock_1776/trigger2-3;lock_1777/trigger1-3",
                "split_battle_triggers:lock_1803-1808;lock_1809/trigger0,3-5",
                "split_battle_triggers:lock_1811/trigger0;sha256=0247f3afc6e762a44ef281a7a450f70a61a92ee4b13bdfabb3acc48a6c0eaec2",
                "split_battle_triggers:lock_1812/trigger0,17-18,30-33;sha256=2227efb4d08fecec910ef34665b297c97ddd292863713d58bca74f827bda6878",
                "split_animation_settings:settings_sets_heralds.bytes;sha256=64bd77afa0edacdc7b672047222fb4261771f08b835367bc3aeeb5b02e668f5a",
                "native:25564,25582,36929,36940,36942,39320,39323,39182;stepHz=60;39552:MidFrames+1;39602:intervalFrame-1"
            ])
        var value = spatialTemplate
        value.id = "h17-06-06a-prod-14601616733-l\(level)"
        value.level = level; value.maximumHealth = maximumHealth
        // The whole profile cannot be called a byte-identical original damage
        // environment while the application supplies geometry and stat scale.
        value.evidence = .init(basis: .applicationAdaptation, version: source.version,
            references: source.references + ["Application supplies spatialTemplate and normalized MagicPower; runtime fields below retain source provenance"])
        value.runtime = .init(evidence: source,
            configurationSHA256: "02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a",
            tickRate: 60, sourceFramesPerSecond: 30, normalizedMagicPower: magicPower,
            suppressionHealthFractionBps: 400, suppressionBladeBonusBps: 3300,
            mistGainFirstPulseDelayTicks: 1, mistGainPulseIntervalTicks: 10, mistGainPulseCount: 30,
            forestGainPulseIntervalTicks: 2, forestGainPulseCount: 10,
            rootFailedExtraDamageBps: 12_500, criticalPhysicalRetentionBps: 4800,
            weaponCriticalMultiplierBps: 25_000, commonCriticalMultiplierBps: 17_500,
            statusPulseStepTicks: 10,
            shadowDamageIsAdditional: true, commonSoulAndWaveUnblockable: true)
        value.level1ShadowBonusBps = 1000
        value.mist.evidence = source
        value.mist.maximum = 10_000; value.mist.initial = 0
        // L5 writes .45 directly; it does not multiply .33 by a display bonus.
        value.mist.suppressedHitGain = level >= 5 ? 4500 : 3300
        value.mist.gainDurationTicks = 300; value.mist.level5GainBonusBps = 0
        value.mist.feastGain = 3300; value.mist.betweenRoundsRetainedBps = 10_000
        value.forest.curseChanceBps = 6600; value.forest.physicalReductionBps = 3300
        value.forest.debuffTicks = 1200; value.forest.curseMistGain = 6600
        value.forest.triggerCooldownTicks = 0
        // The stun reaction remains the arena's explicitly named adaptation.
        value.forest.evidence = value.evidence
        value.suppression.evidence = source
        value.suppression.durationTicks = 480; value.suppression.totalTrueDamage = 0
        value.suppression.outgoingReductionPerStackBps = 3000
        value.suppression.maximumOutgoingReductionBps = 3000
        value.suppression.level6ShadowDefenseReductionBps = 2000
        // This is a storage bound, not a source gameplay stack limit.
        value.suppression.maximumStacks = 64
        value.blade.durationTicks = 720; value.blade.weaponBonusBps = 10_000
        value.blade.shadowConversionBps = 9000; value.blade.waveAndSoulBonusBps = 10_000
        value.blade.initialOnslaughtCharges = 3
        value.branches.holdTicks = 180; value.branches.pulseIntervalTicks = 30
        value.branches.pulseDamage = magicPower * 1000 / 10_000
        value.branches.escapingBurstDamage = 0 // Extra damage is based on the resolved initial hit.
        value.branches.suppressedDamageBonusBps = 10_000
        value.branches.rootedSoulBonusBps = 20_000
        value.branches.entangledHoldReductionTicks = 60
        value.souls.sharedCooldownTicks = 30; value.souls.hungryDeflectCooldownTicks = 600
        value.souls.poisonDurationTicks = 480; value.souls.poisonDamageBps = 2000
        value.souls.maximumPoisonStacks = 64
        value.souls.maximumNotches = 36; value.souls.notchCost = 18
        value.souls.forestRainCount = 7; value.souls.forestRainIntervalTicks = 30
        value.souls.danceCount = 6; value.souls.danceIntervalTicks = 90
        value.flavours.evidence = source
        value.flavours.legionWeaponReductionBps = 1600; value.flavours.legionShadowReductionBps = 2000
        value.flavours.dynastyUnarmedReductionBps = 1600; value.flavours.dynastyShadowReductionBps = 2000
        value.flavours.heraldCriticalCooldownBonusBps = 10_000
        value.flavours.heraldShadowGainReductionBps = 1500
        value.policies.stackMistRegeneration = false
        value.policies.generatedHitsRestoreMist = true; value.policies.blockedHitsRestoreMist = true
        value.policies.suppressionOnBlockedWave = true
        for i in value.abilities.indices {
            let ability = value.abilities[i].ability
            value.abilities[i].evidence = value.evidence
            value.abilities[i].mistCost = ability.soul == nil ? 0 : 3300
            value.abilities[i].cooldownTicks = ability == .branches ? 900 : ability.soul == nil ? 0 : 300
            let coefficient: Int
            switch ability {
            case .branches: coefficient = 1500
            case .mistOnslaught: coefficient = 1200
            case .legionary: coefficient = 2200
            case .herald: coefficient = 1500
            case .dynast: coefficient = 3000
            default: coefficient = 0
            }
            if value.abilities[i].attack != nil {
                value.abilities[i].attack?.damage = magicPower * coefficient / 10_000
                value.abilities[i].attack?.blockedDamage = 0
                value.abilities[i].attack?.evidence = value.evidence
            }
            // Manual soul windup belongs to its independent original model.
            if ability == .legionary { value.abilities[i].startupTicks = 34 }
            if ability == .herald { value.abilities[i].startupTicks = 4 }
            if ability == .dynast { value.abilities[i].startupTicks = 34 }
            if ability == .mistBlade { value.abilities[i].startupTicks = 24 }
            if ability == .mistOnslaught { value.abilities[i].startupTicks = 26 }
            if ability == .branches {
                value.abilities[i].startupTicks = 42
                // This independent model also supplies SelfEndFrame=0.
                // Its open-ended attack interval includes source sample 60.
                value.abilities[i].attack?.lifetimeTicks = 61
            }
            // The 22-frame model explicitly supplies SelfEndFrame=0, rather
            // than the nullable owner's default of four source frames.
            if ability == .mistOnslaught { value.abilities[i].attack?.lifetimeTicks = 43 }
        }
        try value.validate()
        return value
    }
}
