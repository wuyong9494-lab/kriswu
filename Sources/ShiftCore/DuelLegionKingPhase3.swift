import Foundation

/// Phase 3 isolated completion module for Xu Xiao / King of the Legion (`legion_king.rar`) —
/// Two-Handed Greatsword (`twohanded_sword_heavy_slash`), Independently Built Procedural 3D Shadow Chains
/// (`Procedural_KOTL_ShadowChain` replacing missing CABs `cab-4491db...`, `cab-131b8f...`, `cab-ddcfef...`),
/// Shadow Ranged Chain Pull (`shadow_ranged_chain` + `shadow_ranged_chain_passive`), and Dark Incarnation
/// single-trigger second life (`legion_king_ressurection`).
public enum DuelLegionKingPhase3 {

    public typealias Provenance = DuelShogunHeavyPhase1.Provenance

    public struct SourceFrameSample: Equatable, Sendable {
        public let sourceFrame: Int
        public let pelvisX: Double
        public let pelvisY: Double
        public let hilt: DuelWeaponPoint
        public let tip: DuelWeaponPoint
        public let tipVelocityMPS: Double
    }

    /// Parametric specification of the independently constructed articulated 3D Shadow Chain mesh & shader
    /// replacing the unresolved external chain geometry/shader CABs in `legion_king.rar`.
    public struct ProceduralChainMeshSpec: Equatable, Codable, Sendable {
        public let meshIdentifier: String
        public let linkCount: Int
        public let torusMajorRadiusMeters: Double
        public let torusMinorRadiusMeters: Double
        public let alternating90DegTwist: Bool
        public let shackleCollarRadiusMeters: Double
        public let maxReachMeters: Double
        public let darkIronBaseHex: String
        public let ghostlyRimHex: String
        public let provenance: Provenance
        public let replacesMissingCABs: [String]
    }

    public static let proceduralChainSpec = ProceduralChainMeshSpec(
        meshIdentifier: "Procedural_KOTL_ShadowChain",
        linkCount: 28,
        torusMajorRadiusMeters: 0.052,
        torusMinorRadiusMeters: 0.014,
        alternating90DegTwist: true,
        shackleCollarRadiusMeters: 0.22,
        maxReachMeters: 4.35,
        darkIronBaseHex: "#1E222B",
        ghostlyRimHex: "#5DE4FF",
        provenance: .independentRecreation,
        replacesMissingCABs: [
            "cab-4491db62d37b594494cc32746ba9fc1e",
            "cab-131b8f1273b2f6fb5fb85c6b0efcb0de",
            "cab-ddcfef8798a7c7a0b4764c9e0b1ef88a",
        ]
    )

    public struct GapFillItem: Equatable, Codable, Sendable {
        public let id: String
        public let category: String
        public let description: String
        public let provenance: Provenance
        public let replacesMissingSource: String
    }

    public static let gapFillManifest: [GapFillItem] = [
        .init(id: "head_swap_xuXiao", category: "3DModel",
              description: "Replaced skin_hero_King_Default_helmet with CleanHead_xuXiao.glb + skin-matched collar bridge",
              provenance: .independentRecreation, replacesMissingSource: "Custom likeness requirement"),
        .init(id: "procedural_kotl_3d_shadow_chain", category: "3DModelAndShader",
              description: "Built 28-link interlocking dark-iron torus chain + spectral shackle collar + cyan-violet ghostly rim shader",
              provenance: .independentRecreation, replacesMissingSource: "Missing 3D chain meshes/shaders in cab-4491db/cab-131b8f/cab-ddcfef"),
        .init(id: "rec_legion_king_generic_kick_hop", category: "Animation",
              description: "Synthesized generic Legion kick & evasive hop/roll recovery transitions",
              provenance: .independentRecreation, replacesMissingSource: "Missing shared Legion generic kicks/jumps/rolls bundle"),
        .init(id: "rec_vfx_dark_incarnation_nova", category: "VFXShader",
              description: "Procedural spectral soul-fire shockwave & greatsword shadow edge glow",
              provenance: .independentRecreation, replacesMissingSource: "193 unresolved external VFX/Shader CAB PPtrs"),
        .init(id: "rec_legion_king_combat_scalars", category: "CombatBalance",
              description: "Balanced greatsword heavy, shadow chain pull, and Dark Incarnation second-life revive scalars",
              provenance: .independentRecreation, replacesMissingSource: "Encrypted weapons/armor XML & unverified live video"),
    ]

    // MARK: - Measured Original Track Constants (`legion_king.rar`)

    public static let initialHP = 2900                                   // Provenance: independentRecreation
    public static let greatswordHeavyFrames30FPS = 64                    // Provenance: originalBinaryMeasured (`twohanded_sword_heavy_slash.bytes`)
    public static let greatswordHeavyTicks60Hz = 127                     // Provenance: originalBinaryMeasured
    public static let greatswordActiveStartTick60Hz = 40                 // Provenance: originalBinaryMeasured (f20..f25 chest-height thrust/cleave)
    public static let greatswordActiveEndTick60Hz = 51                   // Provenance: originalBinaryMeasured
    public static let greatswordNetLungeMeters = 0.9719                  // Provenance: originalBinaryMeasured

    public static let blockMidHeavyFrames30FPS = 32                      // Provenance: originalBinaryMeasured (`b_twohanded_sword_mid_block_heavy.bytes`)
    public static let blockMidHeavyTicks60Hz = 63                        // Provenance: originalBinaryMeasured
    public static let blockNetSlideMeters = 1.1083                       // Provenance: originalBinaryMeasured

    public static let chainCastFrames30FPS = 69                          // Provenance: originalBinaryMeasured (`shadow_ranged_chain.bytes`)
    public static let chainCastTicks60Hz = 137                           // Provenance: originalBinaryMeasured
    public static let chainActiveStartTick60Hz = 36                      // Provenance: originalBinaryMeasured (f18 hand cast release)
    public static let chainActiveEndTick60Hz = 56                        // Provenance: originalBinaryMeasured (procedural chain projectile flight)
    public static let chainPassiveVictimFrames30FPS = 118                // Provenance: originalBinaryMeasured (`shadow_ranged_chain_passive.bytes`)
    public static let chainPassiveVictimTicks60Hz = 235                  // Provenance: originalBinaryMeasured
    public static let chainVictimPullMeters = 1.0660                     // Provenance: originalBinaryMeasured (pulls defender -1.066m toward caster)
    public static let chainVictimLiftYMeters = 1.1060                    // Provenance: originalBinaryMeasured

    public static let darkIncarnationFrames30FPS = 121                   // Provenance: originalBinaryMeasured (`legion_king_ressurection.bytes`)
    public static let darkIncarnationTicks60Hz = 241                     // Provenance: originalBinaryMeasured

    public static let greatswordBladeRadiusMeters = 0.08                 // Provenance: independentRecreation
    public static let defenderBodyRadiusMeters = 0.24                    // Provenance: independentRecreation
    public static let defenderHeadRadiusMeters = 0.14                    // Provenance: independentRecreation

    public struct CombatParameters: Equatable, Sendable {
        public let greatswordHeavyDamage: Int                            // Provenance: independentRecreation
        public let greatswordGuardChip: Int                              // Provenance: independentRecreation
        public let greatswordHitStopTicks60Hz: Int                       // Provenance: independentRecreation
        public let guardBlockStopTicks60Hz: Int                          // Provenance: independentRecreation
        public let greatswordKnockbackMeters: Double                     // Provenance: independentRecreation
        public let chainHitDamage: Int                                   // Provenance: independentRecreation
        public let chainGuardChip: Int                                   // Provenance: independentRecreation
        public let darkIncarnationReviveHP: Int                          // Provenance: independentRecreation
        public let darkIncarnationNovaKnockbackMeters: Double            // Provenance: independentRecreation

        public static let standard = CombatParameters(
            greatswordHeavyDamage: 224,
            greatswordGuardChip: 72,
            greatswordHitStopTicks60Hz: 11,
            guardBlockStopTicks60Hz: 5,
            greatswordKnockbackMeters: 1.55,
            chainHitDamage: 148,
            chainGuardChip: 42,
            darkIncarnationReviveHP: 520,
            darkIncarnationNovaKnockbackMeters: 1.45
        )
    }

    public enum MoveKind: String, Codable, Sendable, Equatable {
        case greatswordHeavySlash
        case shadowRangedChain
    }

    public enum Phase: String, Codable, Sendable, Equatable {
        case idle
        case startup
        case active
        case recovery
        case interrupted
        case completed
    }

    public enum ResolutionKind: String, Codable, Sendable, Equatable {
        case none
        case cleanHit
        case guardedBlock
        case whiffed
        case interruptedBeforeActive
    }

    public struct ScenarioConfig: Equatable, Sendable {
        public let move: MoveKind
        public let defenderStartX: Double
        public let defenderGuarding: Bool
        public let interruptAtTick60Hz: Int?
        public let interruptDamageToAttacker: Int
        public let parameters: CombatParameters

        public init(move: MoveKind,
                    defenderStartX: Double,
                    defenderGuarding: Bool,
                    interruptAtTick60Hz: Int? = nil,
                    interruptDamageToAttacker: Int = 0,
                    parameters: CombatParameters = .standard) {
            self.move = move
            self.defenderStartX = defenderStartX
            self.defenderGuarding = defenderGuarding
            self.interruptAtTick60Hz = interruptAtTick60Hz
            self.interruptDamageToAttacker = interruptDamageToAttacker
            self.parameters = parameters
        }
    }

    public struct TickEvent: Equatable, Sendable {
        public let tick60Hz: Int
        public let sourceFrame30FPS: Double
        public let kind: String
        public let detail: String
    }

    public struct ScenarioResult: Equatable, Sendable {
        public let move: MoveKind
        public let resolution: ResolutionKind
        public let finalPhase: Phase
        public let causedGuardBreak: Bool
        public let contactTick60Hz: Int?
        public let damageSettlementCount: Int
        public let attackerStartHP: Int
        public let attackerEndHP: Int
        public let defenderStartHP: Int
        public let defenderEndHP: Int
        public let hitStopTicksApplied: Int
        public let defenderStartX: Double
        public let defenderEndX: Double
        public let defenderDisplacementMeters: Double
        public let chainSnaggedAndPulled: Bool
        public let chainPeakLiftYMeters: Double
        public let sfxTriggers: [TickEvent]
        public let vfxTriggers: [TickEvent]
        public let events: [TickEvent]

        public var defenderHPDelta: Int { defenderStartHP - defenderEndHP }
        public var attackerHPDelta: Int { attackerStartHP - attackerEndHP }
    }

    /// Stateful Dark Incarnation single-trigger second-life evaluator (`legion_king_ressurection`, 121f/241t60).
    public struct DarkIncarnationState: Equatable, Sendable {
        public private(set) var currentHP: Int
        public private(set) var hasRevivedThisRound: Bool
        public private(set) var reviveTriggerCount: Int
        public private(set) var isDefeated: Bool

        public init(startingHP: Int = DuelLegionKingPhase3.initialHP) {
            self.currentHP = startingHP
            self.hasRevivedThisRound = false
            self.reviveTriggerCount = 0
            self.isDefeated = false
        }

        public struct DamageOutcome: Equatable, Sendable {
            public let triggeredDarkIncarnation: Bool
            public let resultingHP: Int
            public let isDefeated: Bool
            public let shockwaveKnockbackMeters: Double
            public let reviveDurationTicks60Hz: Int
        }

        public mutating func applyIncomingDamage(_ amount: Int, parameters: CombatParameters = .standard) -> DamageOutcome {
            guard !isDefeated else {
                return .init(triggeredDarkIncarnation: false, resultingHP: 0, isDefeated: true, shockwaveKnockbackMeters: 0, reviveDurationTicks60Hz: 0)
            }
            let remaining = currentHP - max(0, amount)
            if remaining > 0 {
                currentHP = remaining
                return .init(triggeredDarkIncarnation: false, resultingHP: currentHP, isDefeated: false, shockwaveKnockbackMeters: 0, reviveDurationTicks60Hz: 0)
            }
            if !hasRevivedThisRound {
                hasRevivedThisRound = true
                reviveTriggerCount += 1
                currentHP = parameters.darkIncarnationReviveHP
                isDefeated = false
                return .init(
                    triggeredDarkIncarnation: true,
                    resultingHP: currentHP,
                    isDefeated: false,
                    shockwaveKnockbackMeters: parameters.darkIncarnationNovaKnockbackMeters,
                    reviveDurationTicks60Hz: DuelLegionKingPhase3.darkIncarnationTicks60Hz
                )
            } else {
                currentHP = 0
                isDefeated = true
                return .init(triggeredDarkIncarnation: false, resultingHP: 0, isDefeated: true, shockwaveKnockbackMeters: 0, reviveDurationTicks60Hz: 0)
            }
        }
    }

    // MARK: - 60 Hz Sampling & Swept Collision

    public static func sampleGreatsword(atTick60Hz tick: Int) -> SourceFrameSample {
        let clamped = max(0, min(greatswordHeavyTicks60Hz - 1, tick))
        let f0 = clamped / 2
        let f1 = min(greatswordHeavyFrames.count - 1, f0 + 1)
        let alpha = (clamped % 2 == 0) ? 0.0 : 0.5
        let a = greatswordHeavyFrames[f0]
        let b = greatswordHeavyFrames[f1]
        if alpha == 0.0 { return a }
        return SourceFrameSample(
            sourceFrame: f0,
            pelvisX: a.pelvisX + (b.pelvisX - a.pelvisX) * alpha,
            pelvisY: a.pelvisY + (b.pelvisY - a.pelvisY) * alpha,
            hilt: a.hilt.mixed(with: b.hilt, weight: alpha),
            tip: a.tip.mixed(with: b.tip, weight: alpha),
            tipVelocityMPS: a.tipVelocityMPS + (b.tipVelocityMPS - a.tipVelocityMPS) * alpha
        )
    }

    private static func defenderHurtCapsules(atX x: Double) -> [DuelWeaponCapsule] {
        [
            DuelWeaponCapsule(a: .init(x: x, y: 0.48, z: 0.0), b: .init(x: x, y: 1.28, z: 0.0), radius: defenderBodyRadiusMeters),
            DuelWeaponCapsule(a: .init(x: x, y: 1.35, z: 0.0), b: .init(x: x, y: 1.60, z: 0.0), radius: defenderHeadRadiusMeters),
        ]
    }

    private static func testBladeSweep(before: SourceFrameSample, after: SourceFrameSample, defenderX: Double) -> DuelWeaponCapsule.Contact? {
        let segBefore = DuelWeaponCapsule(a: before.hilt, b: before.tip, radius: greatswordBladeRadiusMeters)
        let segAfter = DuelWeaponCapsule(a: after.hilt, b: after.tip, radius: greatswordBladeRadiusMeters)
        var earliest: DuelWeaponCapsule.Contact?
        for h in defenderHurtCapsules(atX: defenderX) {
            if let hit = DuelWeaponCapsule.swept(attackBefore: segBefore, attackAfter: segAfter, hurtBefore: h, hurtAfter: h) {
                if earliest == nil || hit.time < earliest!.time { earliest = hit }
            }
        }
        return earliest
    }

    // MARK: - Deterministic 60 Hz Runner

    public static func runScenario(_ config: ScenarioConfig) -> ScenarioResult {
        var attackerHP = initialHP
        var defenderHP = initialHP
        var defenderX = config.defenderStartX
        let defenderStartX = config.defenderStartX

        var phase: Phase = .startup
        var resolution: ResolutionKind = .none
        var settledSegment = false
        var damageSettlementCount = 0
        var contactTick: Int? = nil
        var chainPulled = false
        var chainPeakLiftY = 0.80

        let totalAnimTicks = (config.move == .greatswordHeavySlash) ? greatswordHeavyTicks60Hz : chainCastTicks60Hz
        let activeStart = (config.move == .greatswordHeavySlash) ? greatswordActiveStartTick60Hz : chainActiveStartTick60Hz
        let activeEnd = (config.move == .greatswordHeavySlash) ? greatswordActiveEndTick60Hz : chainActiveEndTick60Hz

        var animTick = 0
        var hitStopRemaining = 0
        var hitStopApplied = 0
        var totalTicks = 0
        var blockSlideTick: Int? = nil
        var hitKnockbackRemaining = 0
        var hitKnockbackStep = 0.0

        var events: [TickEvent] = []
        var sfx: [TickEvent] = []
        var vfx: [TickEvent] = []

        switch config.move {
        case .greatswordHeavySlash:
            sfx.append(.init(tick60Hz: 0, sourceFrame30FPS: 0.0, kind: "sfx", detail: "sfx_wpn_E_Castle_whoosh_03.wav [originalBinaryMeasured]"))
        case .shadowRangedChain:
            sfx.append(.init(tick60Hz: 0, sourceFrame30FPS: 0.0, kind: "sfx", detail: "sfx_vo_KL_L_Castle_chains_01.wav [originalBinaryMeasured]"))
            vfx.append(.init(tick60Hz: 0, sourceFrame30FPS: 0.0, kind: "vfx", detail: "Procedural_KOTL_ShadowChain summon [independentRecreation: 28 links]"))
        }

        while totalTicks < 340 {
            if hitStopRemaining > 0 {
                hitStopRemaining -= 1
                totalTicks += 1
                continue
            }

            if let bTick = blockSlideTick {
                let idx = min(blockMidHeavyDxMeters.count - 1, bTick / 2)
                defenderX = defenderStartX + (-blockMidHeavyDxMeters[idx])
                blockSlideTick = (bTick + 1 < blockMidHeavyTicks60Hz) ? (bTick + 1) : nil
            } else if hitKnockbackRemaining > 0 {
                defenderX += hitKnockbackStep
                hitKnockbackRemaining -= 1
            }

            // Pre-active interrupt gate
            if let interruptTick = config.interruptAtTick60Hz,
               phase == .startup,
               animTick == interruptTick,
               animTick < activeStart {
                phase = .interrupted
                resolution = .interruptedBeforeActive
                attackerHP = max(0, attackerHP - config.interruptDamageToAttacker)
                events.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "interrupt",
                                    detail: "Interrupted during startup before tick \(activeStart); move cancelled, defender HP delta = 0"))
                totalTicks += 1
                break
            }

            if animTick >= totalAnimTicks {
                if resolution == .none { resolution = .whiffed }
                if blockSlideTick == nil && hitKnockbackRemaining == 0 {
                    phase = .completed
                    break
                }
                totalTicks += 1
                continue
            }

            if animTick < activeStart {
                phase = .startup
            } else if animTick <= activeEnd {
                phase = .active
                if animTick == activeStart && config.move == .shadowRangedChain {
                    sfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "sfx", detail: "hero_lk_chains_shot.wav [originalBinaryMeasured]"))
                }

                if !settledSegment {
                    let hit: Bool
                    switch config.move {
                    case .greatswordHeavySlash:
                        let prev = sampleGreatsword(atTick60Hz: max(0, animTick - 1))
                        let curr = sampleGreatsword(atTick60Hz: animTick)
                        hit = testBladeSweep(before: prev, after: curr, defenderX: defenderX) != nil
                    case .shadowRangedChain:
                        // Procedural 28-link chain extends linearly from 0.80m to proceduralChainSpec.maxReachMeters (4.35m)
                        let fracPrev = Double(max(0, animTick - activeStart)) / Double(max(1, activeEnd - activeStart))
                        let fracCurr = Double(min(activeEnd - activeStart, animTick - activeStart + 1)) / Double(max(1, activeEnd - activeStart))
                        let x0 = 0.80 + (proceduralChainSpec.maxReachMeters - 0.80) * fracPrev
                        let x1 = 0.80 + (proceduralChainSpec.maxReachMeters - 0.80) * fracCurr
                        let cBefore = DuelWeaponCapsule(a: .init(x: 0.45, y: 1.15, z: 0), b: .init(x: x0, y: 1.15, z: 0), radius: 0.14)
                        let cAfter = DuelWeaponCapsule(a: .init(x: 0.45, y: 1.15, z: 0), b: .init(x: x1, y: 1.15, z: 0), radius: 0.14)
                        hit = defenderHurtCapsules(atX: defenderX).contains {
                            DuelWeaponCapsule.swept(attackBefore: cBefore, attackAfter: cAfter, hurtBefore: $0, hurtAfter: $0) != nil
                        }
                    }

                    if hit {
                        settledSegment = true
                        damageSettlementCount += 1
                        contactTick = animTick

                        if config.defenderGuarding {
                            resolution = .guardedBlock
                            let chip = (config.move == .greatswordHeavySlash) ? config.parameters.greatswordGuardChip : config.parameters.chainGuardChip
                            defenderHP = max(0, defenderHP - chip)
                            hitStopRemaining = config.parameters.guardBlockStopTicks60Hz
                            hitStopApplied = config.parameters.guardBlockStopTicks60Hz
                            blockSlideTick = 0
                            sfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "sfx", detail: "sfx_wpn_E_Castle_shield_02.wav [originalBinaryMeasured]"))
                            events.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "guard_block",
                                                detail: "Blocked \(config.move.rawValue) (NO guard break): chip=\(chip), b_twohanded_sword_mid_block_heavy 63t slide (+1.108m) [originalBinaryMeasured]"))
                        } else {
                            resolution = .cleanHit
                            switch config.move {
                            case .greatswordHeavySlash:
                                defenderHP = max(0, defenderHP - config.parameters.greatswordHeavyDamage)
                                hitStopRemaining = config.parameters.greatswordHitStopTicks60Hz
                                hitStopApplied = config.parameters.greatswordHitStopTicks60Hz
                                hitKnockbackRemaining = 24
                                hitKnockbackStep = config.parameters.greatswordKnockbackMeters / 24.0
                                sfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "sfx", detail: "hero_lk_earthsplitter_boom.wav [originalBinaryMeasured]"))
                                events.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "hit",
                                                    detail: "Greatsword heavy hit: dmg=\(config.parameters.greatswordHeavyDamage) [independentRecreation]"))
                            case .shadowRangedChain:
                                defenderHP = max(0, defenderHP - config.parameters.chainHitDamage)
                                hitStopRemaining = 6
                                hitStopApplied = 6
                                chainPulled = true
                                chainPeakLiftY = chainVictimLiftYMeters
                                // Negative displacement pulls defender toward King of the Legion by exact original shadow_ranged_chain_passive 1.066m!
                                hitKnockbackRemaining = 24
                                hitKnockbackStep = -chainVictimPullMeters / 24.0
                                sfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "sfx", detail: "hero_lk_chains_hit.wav [originalBinaryMeasured]"))
                                vfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "vfx", detail: "Procedural_KOTL_ShadowChain shackle pull (-1.066m, Y=1.106m) [independentRecreation+originalBinaryMeasured]"))
                                events.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "chain_pull",
                                                    detail: "Shadow chain snagged & pulled defender -1.066m (shadow_ranged_chain_passive 235t)"))
                            }
                        }
                    }
                }
            } else {
                phase = .recovery
            }

            animTick += 1
            totalTicks += 1
        }

        return ScenarioResult(
            move: config.move,
            resolution: resolution,
            finalPhase: phase,
            causedGuardBreak: false,
            contactTick60Hz: contactTick,
            damageSettlementCount: damageSettlementCount,
            attackerStartHP: initialHP,
            attackerEndHP: attackerHP,
            defenderStartHP: initialHP,
            defenderEndHP: defenderHP,
            hitStopTicksApplied: hitStopApplied,
            defenderStartX: defenderStartX,
            defenderEndX: defenderX,
            defenderDisplacementMeters: defenderX - defenderStartX,
            chainSnaggedAndPulled: chainPulled,
            chainPeakLiftYMeters: chainPeakLiftY,
            sfxTriggers: sfx,
            vfxTriggers: vfx,
            events: events
        )
    }

    // MARK: - Measured Original Track Data (`legion_king.rar`)

    /// Measured `twohanded_sword_heavy_slash.bytes` (64f @ 30 FPS) with exact `wpn_King_C_Default_r` 1.26m blade tip.
    public static let greatswordHeavyFrames: [SourceFrameSample] = [
        .init(sourceFrame: 0, pelvisX: 0.0000, pelvisY: 0.8075, hilt: .init(x: 0.1954, y: 1.3792, z: 0.1801), tip: .init(x: -0.9068, y: 1.8118, z: -0.2507), tipVelocityMPS: 0.00),
        .init(sourceFrame: 1, pelvisX: 0.0000, pelvisY: 0.8075, hilt: .init(x: 0.1954, y: 1.3792, z: 0.1800), tip: .init(x: -0.9069, y: 1.8117, z: -0.2507), tipVelocityMPS: 0.00),
        .init(sourceFrame: 2, pelvisX: -0.0188, pelvisY: 0.8137, hilt: .init(x: 0.2012, y: 1.3519, z: 0.1966), tip: .init(x: -0.8746, y: 1.9010, z: -0.1623), tipVelocityMPS: 3.89),
        .init(sourceFrame: 3, pelvisX: -0.0594, pelvisY: 0.8175, hilt: .init(x: 0.2043, y: 1.2801, z: 0.2306), tip: .init(x: -0.7504, y: 2.0743, z: 0.0174), tipVelocityMPS: 8.37),
        .init(sourceFrame: 4, pelvisX: -0.1044, pelvisY: 0.8019, hilt: .init(x: 0.1855, y: 1.1780, z: 0.2615), tip: .init(x: -0.5136, y: 2.2233, z: 0.1832), tipVelocityMPS: 9.76),
        .init(sourceFrame: 5, pelvisX: -0.1475, pelvisY: 0.7706, hilt: .init(x: 0.1573, y: 1.0586, z: 0.2817), tip: .init(x: -0.1764, y: 2.2732, z: 0.3129), tipVelocityMPS: 10.94),
        .init(sourceFrame: 6, pelvisX: -0.1887, pelvisY: 0.7331, hilt: .init(x: 0.1382, y: 0.9289, z: 0.2896), tip: .init(x: 0.1777, y: 2.1841, z: 0.3919), tipVelocityMPS: 11.21),
        .init(sourceFrame: 7, pelvisX: -0.2225, pelvisY: 0.6981, hilt: .init(x: 0.1440, y: 0.7915, z: 0.2839), tip: .init(x: 0.4854, y: 1.9970, z: 0.4173), tipVelocityMPS: 10.83),
        .init(sourceFrame: 8, pelvisX: -0.2462, pelvisY: 0.6706, hilt: .init(x: 0.1640, y: 0.6620, z: 0.2702), tip: .init(x: 0.7441, y: 1.7720, z: 0.4079), tipVelocityMPS: 10.29),
        .init(sourceFrame: 9, pelvisX: -0.2556, pelvisY: 0.6525, hilt: .init(x: 0.1879, y: 0.5613, z: 0.2545), tip: .init(x: 0.9522, y: 1.5551, z: 0.3805), tipVelocityMPS: 9.06),
        .init(sourceFrame: 10, pelvisX: -0.2481, pelvisY: 0.6425, hilt: .init(x: 0.2050, y: 0.5096, z: 0.2448), tip: .init(x: 1.0978, y: 1.3921, z: 0.3534), tipVelocityMPS: 6.61),
        .init(sourceFrame: 11, pelvisX: -0.2319, pelvisY: 0.6372, hilt: .init(x: 0.2150, y: 0.4905, z: 0.2400), tip: .init(x: 1.2012, y: 1.2693, z: 0.3313), tipVelocityMPS: 4.86),
        .init(sourceFrame: 12, pelvisX: -0.2050, pelvisY: 0.6369, hilt: .init(x: 0.2323, y: 0.4753, z: 0.2316), tip: .init(x: 1.2876, y: 1.1598, z: 0.3048), tipVelocityMPS: 4.26),
        .init(sourceFrame: 13, pelvisX: -0.1544, pelvisY: 0.6469, hilt: .init(x: 0.2663, y: 0.4697, z: 0.2161), tip: .init(x: 1.3648, y: 1.0844, z: 0.2722), tipVelocityMPS: 3.38),
        .init(sourceFrame: 14, pelvisX: -0.0737, pelvisY: 0.6675, hilt: .init(x: 0.3229, y: 0.4791, z: 0.1960), tip: .init(x: 1.4503, y: 1.0403, z: 0.2380), tipVelocityMPS: 3.06),
        .init(sourceFrame: 15, pelvisX: 0.0388, pelvisY: 0.6944, hilt: .init(x: 0.4072, y: 0.5055, z: 0.1721), tip: .init(x: 1.5558, y: 1.0224, z: 0.2050), tipVelocityMPS: 3.36),
        .init(sourceFrame: 16, pelvisX: 0.1719, pelvisY: 0.7231, hilt: .init(x: 0.5201, y: 0.5439, z: 0.1429), tip: .init(x: 1.6836, y: 1.0266, z: 0.1730), tipVelocityMPS: 3.95),
        .init(sourceFrame: 17, pelvisX: 0.3094, pelvisY: 0.7512, hilt: .init(x: 0.6597, y: 0.5901, z: 0.1070), tip: .init(x: 1.8309, y: 1.0533, z: 0.1410), tipVelocityMPS: 4.60),
        .init(sourceFrame: 18, pelvisX: 0.4394, pelvisY: 0.7756, hilt: .init(x: 0.8284, y: 0.6383, z: 0.0640), tip: .init(x: 1.9993, y: 1.1016, z: 0.1087), tipVelocityMPS: 5.34),
        .init(sourceFrame: 19, pelvisX: 0.5606, pelvisY: 0.7956, hilt: .init(x: 1.0118, y: 0.6838, z: 0.0147), tip: .init(x: 2.1768, y: 1.1597, z: 0.0760), tipVelocityMPS: 5.69),
        .init(sourceFrame: 20, pelvisX: 0.6731, pelvisY: 0.7894, hilt: .init(x: 1.2282, y: 0.7704, z: -0.0469), tip: .init(x: 2.4013, y: 1.2208, z: 0.0446), tipVelocityMPS: 7.04),
        .init(sourceFrame: 21, pelvisX: 0.7831, pelvisY: 0.7344, hilt: .init(x: 1.4772, y: 0.9428, z: -0.1324), tip: .init(x: 2.6848, y: 1.2689, z: 0.0190), tipVelocityMPS: 8.66),
        .init(sourceFrame: 22, pelvisX: 0.9006, pelvisY: 0.6512, hilt: .init(x: 1.7456, y: 1.1738, z: -0.1482), tip: .init(x: 2.9902, y: 1.2966, z: 0.0048), tipVelocityMPS: 9.21),
        .init(sourceFrame: 23, pelvisX: 0.9744, pelvisY: 0.5991, hilt: .init(x: 2.0236, y: 1.2200, z: -0.1278), tip: .init(x: 3.2758, y: 1.2972, z: -0.0110), tipVelocityMPS: 8.58),
        .init(sourceFrame: 24, pelvisX: 1.0106, pelvisY: 0.5669, hilt: .init(x: 2.0924, y: 1.1998, z: -0.0986), tip: .init(x: 3.3480, y: 1.2740, z: -0.0244), tipVelocityMPS: 2.31),
        .init(sourceFrame: 25, pelvisX: 1.0269, pelvisY: 0.5497, hilt: .init(x: 2.1056, y: 1.1866, z: -0.0921), tip: .init(x: 3.3619, y: 1.2616, z: -0.0315), tipVelocityMPS: 0.60),
        .init(sourceFrame: 26, pelvisX: 1.0306, pelvisY: 0.5369, hilt: .init(x: 2.1145, y: 1.1708, z: -0.0773), tip: .init(x: 3.3713, y: 1.2464, z: -0.0281), tipVelocityMPS: 0.54),
        .init(sourceFrame: 27, pelvisX: 1.0319, pelvisY: 0.5316, hilt: .init(x: 2.1177, y: 1.1503, z: -0.0661), tip: .init(x: 3.3742, y: 1.2365, z: -0.0262), tipVelocityMPS: 0.32),
        .init(sourceFrame: 28, pelvisX: 1.0306, pelvisY: 0.5294, hilt: .init(x: 2.1085, y: 1.1268, z: -0.0722), tip: .init(x: 3.3640, y: 1.2244, z: -0.0284), tipVelocityMPS: 0.48),
        .init(sourceFrame: 29, pelvisX: 1.0269, pelvisY: 0.5319, hilt: .init(x: 2.0819, y: 1.0984, z: -0.1004), tip: .init(x: 3.3352, y: 1.2116, z: -0.0366), tipVelocityMPS: 0.98),
        .init(sourceFrame: 30, pelvisX: 1.0219, pelvisY: 0.5375, hilt: .init(x: 2.0464, y: 1.0663, z: -0.1326), tip: .init(x: 3.2963, y: 1.2010, z: -0.0483), tipVelocityMPS: 1.26),
        .init(sourceFrame: 31, pelvisX: 1.0181, pelvisY: 0.5438, hilt: .init(x: 2.0107, y: 1.0310, z: -0.1537), tip: .init(x: 3.2566, y: 1.1944, z: -0.0609), tipVelocityMPS: 1.27),
        .init(sourceFrame: 32, pelvisX: 1.0156, pelvisY: 0.5513, hilt: .init(x: 1.9745, y: 0.9957, z: -0.1646), tip: .init(x: 3.2155, y: 1.1932, z: -0.0724), tipVelocityMPS: 1.28),
        .init(sourceFrame: 33, pelvisX: 1.0131, pelvisY: 0.5597, hilt: .init(x: 1.9356, y: 0.9620, z: -0.1685), tip: .init(x: 3.1707, y: 1.1948, z: -0.0794), tipVelocityMPS: 1.36),
        .init(sourceFrame: 34, pelvisX: 1.0119, pelvisY: 0.5694, hilt: .init(x: 1.8947, y: 0.9326, z: -0.1687), tip: .init(x: 3.1230, y: 1.1994, z: -0.0803), tipVelocityMPS: 1.44),
        .init(sourceFrame: 35, pelvisX: 1.0106, pelvisY: 0.5803, hilt: .init(x: 1.8514, y: 0.9077, z: -0.1650), tip: .init(x: 3.0726, y: 1.2051, z: -0.0767), tipVelocityMPS: 1.52),
        .init(sourceFrame: 36, pelvisX: 1.0094, pelvisY: 0.5950, hilt: .init(x: 1.8023, y: 0.8863, z: -0.1542), tip: .init(x: 3.0163, y: 1.2124, z: -0.0683), tipVelocityMPS: 1.72),
        .init(sourceFrame: 37, pelvisX: 1.0081, pelvisY: 0.6125, hilt: .init(x: 1.7554, y: 0.8725, z: -0.1357), tip: .init(x: 2.9643, y: 1.2191, z: -0.0588), tipVelocityMPS: 1.60),
        .init(sourceFrame: 38, pelvisX: 1.0069, pelvisY: 0.6322, hilt: .init(x: 1.7121, y: 0.8659, z: -0.1084), tip: .init(x: 2.9183, y: 1.2254, z: -0.0489), tipVelocityMPS: 1.43),
        .init(sourceFrame: 39, pelvisX: 1.0069, pelvisY: 0.6544, hilt: .init(x: 1.6735, y: 0.8681, z: -0.0738), tip: .init(x: 2.8768, y: 1.2399, z: -0.0362), tipVelocityMPS: 1.37),
        .init(sourceFrame: 40, pelvisX: 1.0056, pelvisY: 0.6781, hilt: .init(x: 1.6365, y: 0.8798, z: -0.0338), tip: .init(x: 2.8338, y: 1.2720, z: -0.0188), tipVelocityMPS: 1.69),
        .init(sourceFrame: 41, pelvisX: 1.0056, pelvisY: 0.7037, hilt: .init(x: 1.6031, y: 0.9029, z: 0.0107), tip: .init(x: 2.7879, y: 1.3316, z: 0.0079), tipVelocityMPS: 2.39),
        .init(sourceFrame: 42, pelvisX: 1.0044, pelvisY: 0.7281, hilt: .init(x: 1.5703, y: 0.9359, z: 0.0579), tip: .init(x: 2.7321, y: 1.4234, z: 0.0469), tipVelocityMPS: 3.43),
        .init(sourceFrame: 43, pelvisX: 1.0044, pelvisY: 0.7525, hilt: .init(x: 1.5394, y: 0.9811, z: 0.1061), tip: .init(x: 2.6625, y: 1.5523, z: 0.0979), tipVelocityMPS: 4.65),
        .init(sourceFrame: 44, pelvisX: 1.0044, pelvisY: 0.7719, hilt: .init(x: 1.5103, y: 1.0268, z: 0.1478), tip: .init(x: 2.5802, y: 1.6923, z: 0.1475), tipVelocityMPS: 5.10),
        .init(sourceFrame: 45, pelvisX: 1.0031, pelvisY: 0.7881, hilt: .init(x: 1.4759, y: 1.0731, z: 0.1864), tip: .init(x: 2.4627, y: 1.8565, z: 0.1912), tipVelocityMPS: 6.20),
        .init(sourceFrame: 46, pelvisX: 1.0019, pelvisY: 0.8000, hilt: .init(x: 1.4363, y: 1.1150, z: 0.2201), tip: .init(x: 2.2862, y: 2.0452, z: 0.2223), tipVelocityMPS: 7.81),
        .init(sourceFrame: 47, pelvisX: 1.0006, pelvisY: 0.8063, hilt: .init(x: 1.3933, y: 1.1488, z: 0.2470), tip: .init(x: 2.0092, y: 2.2479, z: 0.2321), tipVelocityMPS: 10.30),
        .init(sourceFrame: 48, pelvisX: 0.9981, pelvisY: 0.8087, hilt: .init(x: 1.3513, y: 1.1787, z: 0.2652), tip: .init(x: 1.6326, y: 2.4062, z: 0.2230), tipVelocityMPS: 12.26),
        .init(sourceFrame: 49, pelvisX: 0.9956, pelvisY: 0.8075, hilt: .init(x: 1.3124, y: 1.2075, z: 0.2729), tip: .init(x: 1.2320, y: 2.4629, z: 0.2019), tipVelocityMPS: 12.16),
        .init(sourceFrame: 50, pelvisX: 0.9931, pelvisY: 0.8044, hilt: .init(x: 1.2756, y: 1.2346, z: 0.2686), tip: .init(x: 0.8984, y: 2.4332, z: 0.1756), tipVelocityMPS: 10.08),
        .init(sourceFrame: 51, pelvisX: 0.9906, pelvisY: 0.8000, hilt: .init(x: 1.2432, y: 1.2550, z: 0.2530), tip: .init(x: 0.6575, y: 2.3653, z: 0.1449), tipVelocityMPS: 7.56),
        .init(sourceFrame: 52, pelvisX: 0.9894, pelvisY: 0.7950, hilt: .init(x: 1.2184, y: 1.2690, z: 0.2304), tip: .init(x: 0.4806, y: 2.2827, z: 0.1053), tipVelocityMPS: 5.98),
        .init(sourceFrame: 53, pelvisX: 0.9869, pelvisY: 0.7906, hilt: .init(x: 1.1988, y: 1.2808, z: 0.2063), tip: .init(x: 0.3430, y: 2.1930, z: 0.0544), tipVelocityMPS: 5.16),
        .init(sourceFrame: 54, pelvisX: 0.9844, pelvisY: 0.7881, hilt: .init(x: 1.1852, y: 1.2943, z: 0.1859), tip: .init(x: 0.2383, y: 2.1022, z: -0.0099), tipVelocityMPS: 4.58),
        .init(sourceFrame: 55, pelvisX: 0.9819, pelvisY: 0.7881, hilt: .init(x: 1.1751, y: 1.3119, z: 0.1730), tip: .init(x: 0.1643, y: 2.0177, z: -0.0870), tipVelocityMPS: 4.09),
        .init(sourceFrame: 56, pelvisX: 0.9781, pelvisY: 0.7906, hilt: .init(x: 1.1670, y: 1.3319, z: 0.1670), tip: .init(x: 0.1177, y: 1.9459, z: -0.1637), tipVelocityMPS: 3.45),
        .init(sourceFrame: 57, pelvisX: 0.9756, pelvisY: 0.7944, hilt: .init(x: 1.1628, y: 1.3508, z: 0.1663), tip: .init(x: 0.0932, y: 1.8888, z: -0.2264), tipVelocityMPS: 2.65),
        .init(sourceFrame: 58, pelvisX: 0.9744, pelvisY: 0.7988, hilt: .init(x: 1.1622, y: 1.3656, z: 0.1690), tip: .init(x: 0.0817, y: 1.8483, z: -0.2633), tipVelocityMPS: 1.68),
        .init(sourceFrame: 59, pelvisX: 0.9731, pelvisY: 0.8031, hilt: .init(x: 1.1638, y: 1.3747, z: 0.1736), tip: .init(x: 0.0736, y: 1.8249, z: -0.2694), tipVelocityMPS: 0.77),
        .init(sourceFrame: 60, pelvisX: 0.9719, pelvisY: 0.8063, hilt: .init(x: 1.1658, y: 1.3785, z: 0.1779), tip: .init(x: 0.0672, y: 1.8143, z: -0.2587), tipVelocityMPS: 0.49),
        .init(sourceFrame: 61, pelvisX: 0.9719, pelvisY: 0.8075, hilt: .init(x: 1.1672, y: 1.3793, z: 0.1800), tip: .init(x: 0.0648, y: 1.8117, z: -0.2505), tipVelocityMPS: 0.27),
        .init(sourceFrame: 62, pelvisX: 0.9719, pelvisY: 0.8075, hilt: .init(x: 1.1672, y: 1.3793, z: 0.1800), tip: .init(x: 0.0648, y: 1.8117, z: -0.2505), tipVelocityMPS: 0.00),
        .init(sourceFrame: 63, pelvisX: 0.9719, pelvisY: 0.8075, hilt: .init(x: 1.1672, y: 1.3793, z: 0.1800), tip: .init(x: 0.0648, y: 1.8117, z: -0.2505), tipVelocityMPS: 0.00),
    ]

    /// Measured original `b_twohanded_sword_mid_block_heavy.bytes` (32f @ 30 FPS) pelvis X displacement in meters.
    public static let blockMidHeavyDxMeters: [Double] = [
        0.0000, -0.1348, -0.2577, -0.3892, -0.5177, -0.6333, -0.7427, -0.8533, -0.9614, -1.0495,
        -1.1145, -1.1708, -1.2070, -1.2195, -1.2208, -1.2158, -1.2058, -1.1933, -1.1783, -1.1633,
        -1.1483, -1.1345, -1.1245, -1.1183, -1.1133, -1.1108, -1.1083, -1.1083, -1.1083, -1.1083,
        -1.1083, -1.1083,
    ]
}
