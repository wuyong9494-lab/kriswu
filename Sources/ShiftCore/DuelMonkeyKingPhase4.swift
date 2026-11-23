import Foundation

/// Phase 4 isolated completion module for Sun Deng / Monkey King (`monkey_king.rar`) —
/// Extendable Jingu Staff (`staff_heavy_slash`, `monkey_king_heavy_slash`), Ascension Staff-Perch
/// (`monkey_king_climb_stance`, `pelvisY = 2.123 m`) with Low-Attack Evasion + Plunge Strike
/// (`monkey_king_climb_forward_attack`, `+2.729 m`), and critical synthesized Guard
/// (`rec_monkey_king_mid_block_heavy`, 36f/71t60, 1.15m slide) filling the `0 b_*` block gap in `monkey_king.rar`.
public enum DuelMonkeyKingPhase4 {

    public typealias Provenance = DuelShogunHeavyPhase1.Provenance

    public struct SourceFrameSample: Equatable, Sendable {
        public let sourceFrame: Int
        public let pelvisX: Double
        public let pelvisY: Double
        public let hilt: DuelWeaponPoint
        public let tip: DuelWeaponPoint
        public let tipVelocityMPS: Double
    }

    public struct GapFillItem: Equatable, Codable, Sendable {
        public let id: String
        public let category: String
        public let description: String
        public let provenance: Provenance
        public let replacesMissingSource: String
    }

    public static let gapFillManifest: [GapFillItem] = [
        .init(id: "head_swap_sunDeng", category: "3DModel",
              description: "Replaced Monkeyking_head_base with CleanHead_sunDeng.glb + skin-matched collar neck bridge",
              provenance: .independentRecreation, replacesMissingSource: "Custom likeness requirement"),
        .init(id: "rec_monkey_king_mid_block_heavy", category: "Animation",
              description: "Synthesized 36f/71t60 braced two-handed Jingu staff guard with 1.15m damped slide curve",
              provenance: .independentRecreation, replacesMissingSource: "0 b_* block tracks inside monkey_king.rar"),
        .init(id: "rec_monkey_king_locomotion_kick", category: "Animation",
              description: "Synthesized Dynasty step-forward/back locomotion and low sweep kick transitions",
              provenance: .independentRecreation, replacesMissingSource: "Missing animations-stances-base-monkey_king.bin & shared Dynasty locomotion"),
        .init(id: "rec_vfx_jingu_golden_pillar_aura", category: "VFXShader",
              description: "Procedural golden Jingu Bang tip radiance and Ascension pillar-switch shockwave ring",
              provenance: .independentRecreation, replacesMissingSource: "36 unresolved external VFX/Shader CAB refs (cab-774a96..., cab-e3c7c4...)"),
        .init(id: "rec_monkey_king_combat_scalars", category: "CombatBalance",
              description: "Balanced staff heavy, Ascension plunge, low-evade threshold, and synthesized guard chip scalars",
              provenance: .independentRecreation, replacesMissingSource: "Encrypted weapons/armor XML & unverified live video"),
    ]

    // MARK: - Measured Original Track Constants (`monkey_king.rar`) & Synthesized Guard Spec

    public static let initialHP = 2900                                   // Provenance: independentRecreation
    public static let staffHeavyFrames30FPS = 52                         // Provenance: originalBinaryMeasured (`staff_heavy_slash.bytes`)
    public static let staffHeavyTicks60Hz = 103                          // Provenance: originalBinaryMeasured
    public static let staffHeavyActiveStartTick60Hz = 44                 // Provenance: originalBinaryMeasured (f22..f26 leaping slam)
    public static let staffHeavyActiveEndTick60Hz = 53                   // Provenance: originalBinaryMeasured
    public static let staffHeavyNetLungeMeters = 3.4062                  // Provenance: originalBinaryMeasured
    public static let staffHeavyPeakPelvisYMeters = 1.4163               // Provenance: originalBinaryMeasured (f15 apex)

    public static let climbStanceFrames30FPS = 103                       // Provenance: originalBinaryMeasured (`monkey_king_climb_stance.bytes`)
    public static let climbStanceTicks60Hz = 205                         // Provenance: originalBinaryMeasured
    public static let climbStancePeakPelvisYMeters = 2.1230              // Provenance: originalBinaryMeasured (f14 perch atop 5.01m pillar)
    public static let climbStanceElevatedStartTick60Hz = 18              // Provenance: originalBinaryMeasured (pelvisY >= 1.54m)
    public static let climbStanceLowAttackEvadeMaxHeightMeters = 1.25    // Provenance: independentRecreation (feet clear ground attacks <= 1.25m)
    public static let climbStanceAntiAirMinHeightMeters = 1.75           // Provenance: independentRecreation (anti-air >= 1.75m knocks off pillar)

    public static let climbForwardAttackFrames30FPS = 68                 // Provenance: originalBinaryMeasured (`monkey_king_climb_forward_attack.bytes`)
    public static let climbForwardAttackTicks60Hz = 135                  // Provenance: originalBinaryMeasured
    public static let climbForwardActiveStartTick60Hz = 48               // Provenance: originalBinaryMeasured (f24..f29 plunge sweep)
    public static let climbForwardActiveEndTick60Hz = 59                 // Provenance: originalBinaryMeasured
    public static let climbForwardNetLungeMeters = 2.7287                // Provenance: originalBinaryMeasured
    public static let climbForwardPeakPelvisYMeters = 2.4388             // Provenance: originalBinaryMeasured (f14 launch height)

    public static let climbPillarAttackPeakYMeters = 3.4820              // Provenance: originalBinaryMeasured (`monkey_king_climb_pillar_attack.bytes`, 96f)

    // Synthesized Guard filling the `0 b_*` missing block gap in `monkey_king.rar`!
    public static let synthesizedBlockFrames30FPS = 36                   // Provenance: independentRecreation (`rec_monkey_king_mid_block_heavy`)
    public static let synthesizedBlockTicks60Hz = 71                     // Provenance: independentRecreation
    public static let synthesizedBlockNetSlideMeters = 1.1500            // Provenance: independentRecreation

    public static let staffCapsuleRadiusMeters = 0.085                   // Provenance: independentRecreation
    public static let defenderBodyRadiusMeters = 0.24                    // Provenance: independentRecreation
    public static let defenderHeadRadiusMeters = 0.14                    // Provenance: independentRecreation

    public struct CombatParameters: Equatable, Sendable {
        public let staffHeavyDamage: Int                                 // Provenance: independentRecreation
        public let staffHeavyGuardChip: Int                              // Provenance: independentRecreation
        public let staffHeavyHitStopTicks60Hz: Int                       // Provenance: independentRecreation
        public let synthesizedGuardBlockStopTicks60Hz: Int               // Provenance: independentRecreation
        public let staffHeavyKnockbackMeters: Double                     // Provenance: independentRecreation
        public let ascensionPlungeDamage: Int                            // Provenance: independentRecreation
        public let ascensionPlungeGuardChip: Int                         // Provenance: independentRecreation
        public let ascensionPlungeHitStopTicks60Hz: Int                  // Provenance: independentRecreation
        public let ascensionPlungeKnockbackMeters: Double                // Provenance: independentRecreation

        public static let standard = CombatParameters(
            staffHeavyDamage: 198,
            staffHeavyGuardChip: 62,
            staffHeavyHitStopTicks60Hz: 9,
            synthesizedGuardBlockStopTicks60Hz: 4,
            staffHeavyKnockbackMeters: 1.50,
            ascensionPlungeDamage: 248,
            ascensionPlungeGuardChip: 84,
            ascensionPlungeHitStopTicks60Hz: 11,
            ascensionPlungeKnockbackMeters: 1.85
        )
    }

    public enum MoveKind: String, Codable, Sendable, Equatable {
        case staffHeavySlash
        case ascensionPerchAndPlunge
    }

    public enum Phase: String, Codable, Sendable, Equatable {
        case idle
        case startup
        case perchedOnPillar
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
        case interruptedOnPillar
    }

    public struct IncomingPerchStrike: Equatable, Sendable {
        public let atPerchTick60Hz: Int
        public let strikeHeightMeters: Double
        public let damageToAttacker: Int

        public init(atPerchTick60Hz: Int, strikeHeightMeters: Double, damageToAttacker: Int) {
            self.atPerchTick60Hz = atPerchTick60Hz
            self.strikeHeightMeters = strikeHeightMeters
            self.damageToAttacker = damageToAttacker
        }
    }

    public struct ScenarioConfig: Equatable, Sendable {
        public let move: MoveKind
        public let defenderStartX: Double
        public let defenderGuarding: Bool
        public let interruptAtTick60Hz: Int?
        public let interruptDamageToAttacker: Int
        public let incomingStrikeWhilePerched: IncomingPerchStrike?
        public let parameters: CombatParameters

        public init(move: MoveKind,
                    defenderStartX: Double,
                    defenderGuarding: Bool,
                    interruptAtTick60Hz: Int? = nil,
                    interruptDamageToAttacker: Int = 0,
                    incomingStrikeWhilePerched: IncomingPerchStrike? = nil,
                    parameters: CombatParameters = .standard) {
            self.move = move
            self.defenderStartX = defenderStartX
            self.defenderGuarding = defenderGuarding
            self.interruptAtTick60Hz = interruptAtTick60Hz
            self.interruptDamageToAttacker = interruptDamageToAttacker
            self.incomingStrikeWhilePerched = incomingStrikeWhilePerched
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
        public let usedSynthesizedGuard: Bool
        public let peakAttackerPelvisYMeters: Double
        public let evadedLowAttackWhilePerched: Bool
        public let knockedOffPillarByAntiAir: Bool
        public let contactTick60Hz: Int?
        public let damageSettlementCount: Int
        public let attackerStartHP: Int
        public let attackerEndHP: Int
        public let defenderStartHP: Int
        public let defenderEndHP: Int
        public let hitStopTicksApplied: Int
        public let defenderKnockbackMeters: Double
        public let sfxTriggers: [TickEvent]
        public let vfxTriggers: [TickEvent]
        public let events: [TickEvent]

        public var defenderHPDelta: Int { defenderStartHP - defenderEndHP }
        public var attackerHPDelta: Int { attackerStartHP - attackerEndHP }
    }

    // MARK: - 60 Hz Sampling & Swept Collision

    public static func sample(frames: [SourceFrameSample], atTick60Hz tick: Int) -> SourceFrameSample {
        let maxTick = max(0, frames.count * 2 - 2)
        let clamped = max(0, min(maxTick, tick))
        let f0 = clamped / 2
        let f1 = min(frames.count - 1, f0 + 1)
        let alpha = (clamped % 2 == 0) ? 0.0 : 0.5
        let a = frames[f0]
        let b = frames[f1]
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
            DuelWeaponCapsule(a: .init(x: x, y: 0.45, z: 0.0), b: .init(x: x, y: 1.24, z: 0.0), radius: defenderBodyRadiusMeters),
            DuelWeaponCapsule(a: .init(x: x, y: 1.32, z: 0.0), b: .init(x: x, y: 1.56, z: 0.0), radius: defenderHeadRadiusMeters),
        ]
    }

    private static func testStaffSweep(before: SourceFrameSample, after: SourceFrameSample, defenderX: Double) -> DuelWeaponCapsule.Contact? {
        let segBefore = DuelWeaponCapsule(a: before.hilt, b: before.tip, radius: staffCapsuleRadiusMeters)
        let segAfter = DuelWeaponCapsule(a: after.hilt, b: after.tip, radius: staffCapsuleRadiusMeters)
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
        var usedSynthesizedGuard = false
        var peakPelvisY = 0.81
        var evadedLow = false
        var knockedOffPillar = false
        var settledSegment = false
        var damageSettlementCount = 0
        var contactTick: Int? = nil

        var events: [TickEvent] = []
        var sfx: [TickEvent] = []
        var vfx: [TickEvent] = []

        // Stage 0 (Ascension Perch): climb pillar to pelvisY = 2.123m before plunging!
        if config.move == .ascensionPerchAndPlunge {
            sfx.append(.init(tick60Hz: 0, sourceFrame30FPS: 0.0, kind: "sfx", detail: "hero_monkey_king_column_switch.wav [originalBinaryMeasured]"))
            vfx.append(.init(tick60Hz: 0, sourceFrame30FPS: 0.0, kind: "vfx", detail: "rec_vfx_jingu_golden_pillar_aura [independentRecreation]"))
            peakPelvisY = max(peakPelvisY, climbStancePeakPelvisYMeters)
            phase = .perchedOnPillar

            if let incoming = config.incomingStrikeWhilePerched {
                if incoming.strikeHeightMeters <= climbStanceLowAttackEvadeMaxHeightMeters {
                    evadedLow = true
                    events.append(.init(tick60Hz: incoming.atPerchTick60Hz, sourceFrame30FPS: Double(incoming.atPerchTick60Hz) * 0.5,
                                        kind: "perch_evade_low",
                                        detail: "Evaded ground strike (h=\(incoming.strikeHeightMeters)m <= \(climbStanceLowAttackEvadeMaxHeightMeters)m) while perched at pelvisY=\(climbStancePeakPelvisYMeters)m"))
                } else if incoming.strikeHeightMeters >= climbStanceAntiAirMinHeightMeters {
                    knockedOffPillar = true
                    phase = .interrupted
                    resolution = .interruptedOnPillar
                    attackerHP = max(0, attackerHP - incoming.damageToAttacker)
                    events.append(.init(tick60Hz: incoming.atPerchTick60Hz, sourceFrame30FPS: Double(incoming.atPerchTick60Hz) * 0.5,
                                        kind: "perch_anti_air_interrupt",
                                        detail: "Anti-air strike (h=\(incoming.strikeHeightMeters)m >= \(climbStanceAntiAirMinHeightMeters)m) knocked Monkey King off Ascension pillar; plunge cancelled, defender HP delta = 0"))
                    return ScenarioResult(
                        move: config.move, resolution: resolution, finalPhase: phase, causedGuardBreak: false,
                        usedSynthesizedGuard: false, peakAttackerPelvisYMeters: peakPelvisY,
                        evadedLowAttackWhilePerched: false, knockedOffPillarByAntiAir: true,
                        contactTick60Hz: nil, damageSettlementCount: 0,
                        attackerStartHP: initialHP, attackerEndHP: attackerHP,
                        defenderStartHP: initialHP, defenderEndHP: defenderHP,
                        hitStopTicksApplied: 0, defenderKnockbackMeters: 0.0,
                        sfxTriggers: sfx, vfxTriggers: vfx, events: events
                    )
                }
            }
        } else {
            sfx.append(.init(tick60Hz: 0, sourceFrame30FPS: 0.0, kind: "sfx", detail: "hero_Monkey_King_Heavy_Attack_8.wav [originalBinaryMeasured]"))
        }

        let frames = (config.move == .staffHeavySlash) ? staffHeavyFrames : climbForwardFrames
        let totalAnimTicks = (config.move == .staffHeavySlash) ? staffHeavyTicks60Hz : climbForwardAttackTicks60Hz
        let activeStart = (config.move == .staffHeavySlash) ? staffHeavyActiveStartTick60Hz : climbForwardActiveStartTick60Hz
        let activeEnd = (config.move == .staffHeavySlash) ? staffHeavyActiveEndTick60Hz : climbForwardActiveEndTick60Hz

        var animTick = 0
        var hitStopRemaining = 0
        var hitStopApplied = 0
        var totalTicks = 0
        var blockSlideTick: Int? = nil
        var hitKnockbackRemaining = 0
        var hitKnockbackStep = 0.0

        while totalTicks < 300 {
            if hitStopRemaining > 0 {
                hitStopRemaining -= 1
                totalTicks += 1
                continue
            }

            if let bTick = blockSlideTick {
                let idx = min(synthesizedBlockDxMeters.count - 1, bTick / 2)
                defenderX = defenderStartX + (-synthesizedBlockDxMeters[idx])
                blockSlideTick = (bTick + 1 < synthesizedBlockTicks60Hz) ? (bTick + 1) : nil
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
                                    detail: "Interrupted during startup before tick \(activeStart); staff strike cancelled, defender HP delta = 0"))
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

            let prev = sample(frames: frames, atTick60Hz: max(0, animTick - 1))
            let curr = sample(frames: frames, atTick60Hz: animTick)
            peakPelvisY = max(peakPelvisY, curr.pelvisY)

            if animTick < activeStart {
                phase = .startup
            } else if animTick <= activeEnd {
                phase = .active
                if animTick == activeStart {
                    sfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "sfx", detail: "hero_monkey_king_column_whoosh.wav [originalBinaryMeasured]"))
                }
                if !settledSegment,
                   testStaffSweep(before: prev, after: curr, defenderX: defenderX) != nil {
                    settledSegment = true
                    damageSettlementCount += 1
                    contactTick = animTick

                    if config.defenderGuarding {
                        resolution = .guardedBlock
                        usedSynthesizedGuard = true
                        let chip = (config.move == .staffHeavySlash) ? config.parameters.staffHeavyGuardChip : config.parameters.ascensionPlungeGuardChip
                        defenderHP = max(0, defenderHP - chip)
                        hitStopRemaining = config.parameters.synthesizedGuardBlockStopTicks60Hz
                        hitStopApplied = config.parameters.synthesizedGuardBlockStopTicks60Hz
                        blockSlideTick = 0
                        events.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "synthesized_guard_block",
                                            detail: "Blocked via synthesized rec_monkey_king_mid_block_heavy (NO guard break): chip=\(chip), slide=1.150m [independentRecreation replacing 0 b_* gap]"))
                    } else {
                        resolution = .cleanHit
                        let dmg = (config.move == .staffHeavySlash) ? config.parameters.staffHeavyDamage : config.parameters.ascensionPlungeDamage
                        let hStop = (config.move == .staffHeavySlash) ? config.parameters.staffHeavyHitStopTicks60Hz : config.parameters.ascensionPlungeHitStopTicks60Hz
                        let kb = (config.move == .staffHeavySlash) ? config.parameters.staffHeavyKnockbackMeters : config.parameters.ascensionPlungeKnockbackMeters
                        defenderHP = max(0, defenderHP - dmg)
                        hitStopRemaining = hStop
                        hitStopApplied = hStop
                        hitKnockbackRemaining = 22
                        hitKnockbackStep = kb / 22.0
                        sfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "sfx", detail: "hero_monkey_king_earthquake.wav [originalBinaryMeasured]"))
                        events.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "hit",
                                            detail: "Clean hit \(config.move.rawValue): dmg=\(dmg), kb=\(kb)m [independentRecreation]"))
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
            usedSynthesizedGuard: usedSynthesizedGuard,
            peakAttackerPelvisYMeters: peakPelvisY,
            evadedLowAttackWhilePerched: evadedLow,
            knockedOffPillarByAntiAir: knockedOffPillar,
            contactTick60Hz: contactTick,
            damageSettlementCount: damageSettlementCount,
            attackerStartHP: initialHP,
            attackerEndHP: attackerHP,
            defenderStartHP: initialHP,
            defenderEndHP: defenderHP,
            hitStopTicksApplied: hitStopApplied,
            defenderKnockbackMeters: defenderX - defenderStartX,
            sfxTriggers: sfx,
            vfxTriggers: vfx,
            events: events
        )
    }

    // MARK: - Measured Original Track Data (`monkey_king.rar`) & Synthesized Guard Curve

    /// Measured `staff_heavy_slash.bytes` (52f @ 30 FPS) fight-space kinematics.
    public static let staffHeavyFrames: [SourceFrameSample] = [
        .init(sourceFrame: 0, pelvisX: 0.0000, pelvisY: 0.8094, hilt: .init(x: 0.4987, y: 1.0720, z: -0.1512), tip: .init(x: -0.4454, y: 0.6476, z: 0.5495), tipVelocityMPS: 0.00),
        .init(sourceFrame: 1, pelvisX: -0.0031, pelvisY: 0.7913, hilt: .init(x: 0.5482, y: 1.0415, z: -0.1641), tip: .init(x: -0.4298, y: 0.6411, z: 0.5035), tipVelocityMPS: 1.47),
        .init(sourceFrame: 2, pelvisX: -0.0063, pelvisY: 0.7512, hilt: .init(x: 0.6260, y: 0.9407, z: -0.1252), tip: .init(x: -0.4410, y: 0.6158, z: 0.4390), tipVelocityMPS: 2.11),
        .init(sourceFrame: 3, pelvisX: 0.0037, pelvisY: 0.7081, hilt: .init(x: 0.6311, y: 0.7691, z: 0.0475), tip: .init(x: -0.5632, y: 0.5989, z: 0.3749), tipVelocityMPS: 4.17),
        .init(sourceFrame: 4, pelvisX: 0.0381, pelvisY: 0.6794, hilt: .init(x: 0.5501, y: 0.6225, z: 0.3401), tip: .init(x: -0.6765, y: 0.7194, z: 0.1201), tipVelocityMPS: 9.11),
        .init(sourceFrame: 5, pelvisX: 0.1131, pelvisY: 0.6819, hilt: .init(x: 0.4174, y: 0.4819, z: 0.6968), tip: .init(x: -0.3722, y: 0.9063, z: -0.1743), tipVelocityMPS: 13.88),
        .init(sourceFrame: 6, pelvisX: 0.2425, pelvisY: 0.7319, hilt: .init(x: 0.1405, y: 0.4559, z: 0.9027), tip: .init(x: -0.0085, y: 1.0734, z: -0.1739), tipVelocityMPS: 12.01),
        .init(sourceFrame: 7, pelvisX: 0.4038, pelvisY: 0.8163, hilt: .init(x: -0.2134, y: 0.5521, z: 0.8965), tip: .init(x: 0.2558, y: 1.2566, z: -0.0233), tipVelocityMPS: 10.65),
        .init(sourceFrame: 8, pelvisX: 0.5462, pelvisY: 0.9019, hilt: .init(x: -0.4105, y: 0.9024, z: 0.6787), tip: .init(x: 0.5551, y: 1.4646, z: 0.1183), tipVelocityMPS: 11.73),
        .init(sourceFrame: 9, pelvisX: 0.6650, pelvisY: 0.9938, hilt: .init(x: -0.4723, y: 1.3798, z: 0.4821), tip: .init(x: 0.7450, y: 1.6002, z: 0.3030), tipVelocityMPS: 8.93),
        .init(sourceFrame: 10, pelvisX: 0.7775, pelvisY: 1.1125, hilt: .init(x: -0.3748, y: 1.9018, z: 0.3326), tip: .init(x: 0.8633, y: 1.7441, z: 0.4017), tipVelocityMPS: 6.33),
        .init(sourceFrame: 11, pelvisX: 0.9075, pelvisY: 1.2144, hilt: .init(x: -0.1278, y: 2.3151, z: 0.2472), tip: .init(x: 1.0615, y: 1.9911, z: 0.4546), tipVelocityMPS: 9.63),
        .init(sourceFrame: 12, pelvisX: 1.0462, pelvisY: 1.2863, hilt: .init(x: 0.2019, y: 2.6173, z: 0.1660), tip: .init(x: 1.3470, y: 2.2016, z: 0.4458), tipVelocityMPS: 10.64),
        .init(sourceFrame: 13, pelvisX: 1.2013, pelvisY: 1.3438, hilt: .init(x: 0.4904, y: 2.7630, z: 0.1133), tip: .init(x: 1.6110, y: 2.3023, z: 0.4207), tipVelocityMPS: 8.51),
        .init(sourceFrame: 14, pelvisX: 1.3738, pelvisY: 1.3900, hilt: .init(x: 0.6604, y: 2.7823, z: 0.0675), tip: .init(x: 1.8012, y: 2.3378, z: 0.3196), tipVelocityMPS: 6.55),
        .init(sourceFrame: 15, pelvisX: 1.5437, pelvisY: 1.4163, hilt: .init(x: 0.8576, y: 2.7794, z: 0.0330), tip: .init(x: 2.0043, y: 2.3223, z: 0.2300), tipVelocityMPS: 6.67),
        .init(sourceFrame: 16, pelvisX: 1.7213, pelvisY: 1.4163, hilt: .init(x: 1.0666, y: 2.7416, z: 0.0233), tip: .init(x: 2.2278, y: 2.2897, z: 0.1235), tipVelocityMPS: 7.49),
        .init(sourceFrame: 17, pelvisX: 1.8738, pelvisY: 1.3900, hilt: .init(x: 1.2344, y: 2.6180, z: 0.0570), tip: .init(x: 2.4599, y: 2.3721, z: 0.0404), tipVelocityMPS: 7.80),
        .init(sourceFrame: 18, pelvisX: 2.0462, pelvisY: 1.3388, hilt: .init(x: 1.4012, y: 2.4056, z: 0.0587), tip: .init(x: 2.6504, y: 2.4503, z: 0.0614), tipVelocityMPS: 6.21),
        .init(sourceFrame: 19, pelvisX: 2.2162, pelvisY: 1.2588, hilt: .init(x: 1.5628, y: 2.2237, z: 0.0725), tip: .init(x: 2.8090, y: 2.3217, z: 0.0775), tipVelocityMPS: 6.14),
        .init(sourceFrame: 20, pelvisX: 2.3563, pelvisY: 1.1294, hilt: .init(x: 1.7271, y: 2.0638, z: 0.1085), tip: .init(x: 2.9756, y: 2.1208, z: 0.0828), tipVelocityMPS: 7.83),
        .init(sourceFrame: 21, pelvisX: 2.4688, pelvisY: 0.9906, hilt: .init(x: 1.8804, y: 1.9835, z: 0.1579), tip: .init(x: 3.1260, y: 1.8808, z: 0.1354), tipVelocityMPS: 8.64),
        .init(sourceFrame: 22, pelvisX: 2.5488, pelvisY: 0.8369, hilt: .init(x: 2.0518, y: 1.9088, z: 0.1888), tip: .init(x: 3.2403, y: 1.5215, z: 0.1861), tipVelocityMPS: 11.41),
        .init(sourceFrame: 23, pelvisX: 2.6413, pelvisY: 0.6906, hilt: .init(x: 2.3436, y: 1.9030, z: 0.1819), tip: .init(x: 3.2578, y: 1.0506, z: 0.1800), tipVelocityMPS: 14.14),
        .init(sourceFrame: 24, pelvisX: 2.7512, pelvisY: 0.5631, hilt: .init(x: 2.7458, y: 1.8006, z: 0.1872), tip: .init(x: 3.1180, y: 0.6075, z: 0.1668), tipVelocityMPS: 13.94),
        .init(sourceFrame: 25, pelvisX: 2.8262, pelvisY: 0.4781, hilt: .init(x: 3.3065, y: 1.3526, z: 0.1828), tip: .init(x: 2.9335, y: 0.1601, z: 0.1467), tipVelocityMPS: 14.53),
        .init(sourceFrame: 26, pelvisX: 2.8887, pelvisY: 0.4500, hilt: .init(x: 3.6177, y: 0.6002, z: 0.2269), tip: .init(x: 2.4919, y: 0.0600, z: 0.1695), tipVelocityMPS: 13.60),
        .init(sourceFrame: 27, pelvisX: 2.9413, pelvisY: 0.4331, hilt: .init(x: 3.6808, y: 0.0224, z: 0.2326), tip: .init(x: 2.4345, y: 0.0993, z: 0.1732), tipVelocityMPS: 2.09),
        .init(sourceFrame: 28, pelvisX: 2.9863, pelvisY: 0.4309, hilt: .init(x: 3.7101, y: 0.0942, z: 0.2241), tip: .init(x: 2.4890, y: -0.1669, z: 0.1675), tipVelocityMPS: 8.15),
        .init(sourceFrame: 29, pelvisX: 3.0163, pelvisY: 0.4375, hilt: .init(x: 3.7573, y: 0.1020, z: 0.2210), tip: .init(x: 2.5179, y: 0.2555, z: 0.1680), tipVelocityMPS: 12.70),
        .init(sourceFrame: 30, pelvisX: 3.0412, pelvisY: 0.4478, hilt: .init(x: 3.8064, y: 0.0139, z: 0.2184), tip: .init(x: 2.5586, y: -0.0418, z: 0.1688), tipVelocityMPS: 9.00),
        .init(sourceFrame: 31, pelvisX: 3.0563, pelvisY: 0.4572, hilt: .init(x: 3.8303, y: 0.0224, z: 0.2166), tip: .init(x: 2.5819, y: 0.0612, z: 0.1686), tipVelocityMPS: 3.17),
        .init(sourceFrame: 32, pelvisX: 3.0713, pelvisY: 0.4688, hilt: .init(x: 3.8536, y: 0.0347, z: 0.2108), tip: .init(x: 2.6062, y: 0.0936, z: 0.1539), tipVelocityMPS: 1.30),
        .init(sourceFrame: 33, pelvisX: 3.0938, pelvisY: 0.4859, hilt: .init(x: 3.9154, y: 0.0880, z: 0.2109), tip: .init(x: 2.6731, y: 0.2069, z: 0.1396), tipVelocityMPS: 3.97),
        .init(sourceFrame: 34, pelvisX: 3.1212, pelvisY: 0.5131, hilt: .init(x: 3.9955, y: 0.1873, z: 0.2097), tip: .init(x: 2.7728, y: 0.4365, z: 0.1355), tipVelocityMPS: 7.51),
        .init(sourceFrame: 35, pelvisX: 3.1588, pelvisY: 0.5556, hilt: .init(x: 4.0820, y: 0.2864, z: 0.2169), tip: .init(x: 2.8975, y: 0.6826, z: 0.1654), tipVelocityMPS: 8.32),
        .init(sourceFrame: 36, pelvisX: 3.1913, pelvisY: 0.6041, hilt: .init(x: 4.1744, y: 0.4110, z: 0.2340), tip: .init(x: 3.0484, y: 0.9535, z: 0.2201), tipVelocityMPS: 9.45),
        .init(sourceFrame: 37, pelvisX: 3.2263, pelvisY: 0.6519, hilt: .init(x: 4.2261, y: 0.4934, z: 0.2546), tip: .init(x: 3.1199, y: 1.0731, z: 0.3065), tipVelocityMPS: 4.92),
        .init(sourceFrame: 38, pelvisX: 3.2663, pelvisY: 0.7081, hilt: .init(x: 4.2699, y: 0.6344, z: 0.2279), tip: .init(x: 3.1522, y: 1.1837, z: 0.3351), tipVelocityMPS: 3.56),
        .init(sourceFrame: 39, pelvisX: 3.3013, pelvisY: 0.7556, hilt: .init(x: 4.3097, y: 0.7933, z: 0.1882), tip: .init(x: 3.1467, y: 1.2151, z: 0.3665), tipVelocityMPS: 1.34),
        .init(sourceFrame: 40, pelvisX: 3.3312, pelvisY: 0.7919, hilt: .init(x: 4.3312, y: 0.9477, z: 0.1167), tip: .init(x: 3.1252, y: 1.1639, z: 0.3644), tipVelocityMPS: 1.67),
        .init(sourceFrame: 41, pelvisX: 3.3538, pelvisY: 0.8156, hilt: .init(x: 4.3024, y: 1.1022, z: 0.0242), tip: .init(x: 3.1107, y: 0.9847, z: 0.3826), tipVelocityMPS: 5.42),
        .init(sourceFrame: 42, pelvisX: 3.3738, pelvisY: 0.8244, hilt: .init(x: 4.1951, y: 1.1827, z: -0.0757), tip: .init(x: 3.1221, y: 0.7779, z: 0.4215), tipVelocityMPS: 6.32),
        .init(sourceFrame: 43, pelvisX: 3.3913, pelvisY: 0.8225, hilt: .init(x: 4.0687, y: 1.1691, z: -0.1253), tip: .init(x: 3.0782, y: 0.6761, z: 0.4563), tipVelocityMPS: 3.49),
        .init(sourceFrame: 44, pelvisX: 3.4013, pelvisY: 0.8181, hilt: .init(x: 3.9781, y: 1.1363, z: -0.1710), tip: .init(x: 3.0457, y: 0.6242, z: 0.4853), tipVelocityMPS: 2.03),
        .init(sourceFrame: 45, pelvisX: 3.4062, pelvisY: 0.8144, hilt: .init(x: 3.9302, y: 1.1031, z: -0.1966), tip: .init(x: 3.0167, y: 0.6241, z: 0.5096), tipVelocityMPS: 1.14),
        .init(sourceFrame: 46, pelvisX: 3.4062, pelvisY: 0.8119, hilt: .init(x: 3.9090, y: 1.0813, z: -0.1960), tip: .init(x: 2.9935, y: 0.6319, z: 0.5267), tipVelocityMPS: 0.90),
        .init(sourceFrame: 47, pelvisX: 3.4062, pelvisY: 0.8106, hilt: .init(x: 3.9031, y: 1.0726, z: -0.1796), tip: .init(x: 2.9787, y: 0.6360, z: 0.5397), tipVelocityMPS: 0.60),
        .init(sourceFrame: 48, pelvisX: 3.4062, pelvisY: 0.8100, hilt: .init(x: 3.9039, y: 1.0692, z: -0.1610), tip: .init(x: 2.9664, y: 0.6409, z: 0.5462), tipVelocityMPS: 0.44),
        .init(sourceFrame: 49, pelvisX: 3.4062, pelvisY: 0.8094, hilt: .init(x: 3.9050, y: 1.0720, z: -0.1512), tip: .init(x: 2.9608, y: 0.6476, z: 0.5495), tipVelocityMPS: 0.28),
        .init(sourceFrame: 50, pelvisX: 3.4062, pelvisY: 0.8094, hilt: .init(x: 3.9050, y: 1.0720, z: -0.1512), tip: .init(x: 2.9608, y: 0.6476, z: 0.5495), tipVelocityMPS: 0.00),
        .init(sourceFrame: 51, pelvisX: 3.4062, pelvisY: 0.8094, hilt: .init(x: 3.9050, y: 1.0720, z: -0.1512), tip: .init(x: 2.9608, y: 0.6476, z: 0.5495), tipVelocityMPS: 0.00),
    ]

    /// Measured `monkey_king_climb_forward_attack.bytes` (68f @ 30 FPS) fight-space kinematics.
    public static let climbForwardFrames: [SourceFrameSample] = [
        .init(sourceFrame: 0, pelvisX: 0.0000, pelvisY: 1.8400, hilt: .init(x: -0.1352, y: 1.3238, z: 0.3403), tip: .init(x: -0.2038, y: 2.5692, z: 0.4227), tipVelocityMPS: 0.00),
        .init(sourceFrame: 1, pelvisX: 0.0466, pelvisY: 1.8613, hilt: .init(x: -0.1475, y: 1.3305, z: 0.3199), tip: .init(x: -0.1793, y: 2.5754, z: 0.4273), tipVelocityMPS: 0.77),
        .init(sourceFrame: 2, pelvisX: 0.1263, pelvisY: 1.8962, hilt: .init(x: -0.1619, y: 1.3352, z: 0.3111), tip: .init(x: -0.1539, y: 2.5771, z: 0.4526), tipVelocityMPS: 1.08),
        .init(sourceFrame: 3, pelvisX: 0.2384, pelvisY: 1.9413, hilt: .init(x: -0.1670, y: 1.3268, z: 0.3480), tip: .init(x: -0.1357, y: 2.5633, z: 0.5288), tipVelocityMPS: 2.39),
        .init(sourceFrame: 4, pelvisX: 0.3875, pelvisY: 2.0000, hilt: .init(x: -0.1526, y: 1.3179, z: 0.4004), tip: .init(x: -0.1124, y: 2.5528, z: 0.5898), tipVelocityMPS: 1.99),
        .init(sourceFrame: 5, pelvisX: 0.5594, pelvisY: 2.0638, hilt: .init(x: -0.1271, y: 1.3079, z: 0.4502), tip: .init(x: -0.0824, y: 2.5438, z: 0.6318), tipVelocityMPS: 1.57),
        .init(sourceFrame: 6, pelvisX: 0.7437, pelvisY: 2.1338, hilt: .init(x: -0.0704, y: 1.3020, z: 0.4709), tip: .init(x: -0.0287, y: 2.5418, z: 0.6245), tipVelocityMPS: 1.63),
        .init(sourceFrame: 7, pelvisX: 0.9087, pelvisY: 2.1987, hilt: .init(x: 0.0267, y: 1.2884, z: 0.4225), tip: .init(x: 0.0646, y: 2.5304, z: 0.5581), tipVelocityMPS: 3.45),
        .init(sourceFrame: 8, pelvisX: 1.0281, pelvisY: 2.2550, hilt: .init(x: 0.1565, y: 1.2694, z: 0.2989), tip: .init(x: 0.1950, y: 2.5110, z: 0.4379), tipVelocityMPS: 5.35),
        .init(sourceFrame: 9, pelvisX: 1.1219, pelvisY: 2.3025, hilt: .init(x: 0.2551, y: 1.2503, z: 0.1873), tip: .init(x: 0.3112, y: 2.4906, z: 0.3326), tipVelocityMPS: 4.74),
        .init(sourceFrame: 10, pelvisX: 1.2075, pelvisY: 2.3388, hilt: .init(x: 0.2675, y: 1.2354, z: 0.1730), tip: .init(x: 0.3654, y: 2.4742, z: 0.3089), tipVelocityMPS: 1.84),
        .init(sourceFrame: 11, pelvisX: 1.2775, pelvisY: 2.3712, hilt: .init(x: 0.2432, y: 1.2371, z: 0.2155), tip: .init(x: 0.3941, y: 2.4719, z: 0.3384), tipVelocityMPS: 1.24),
        .init(sourceFrame: 12, pelvisX: 1.3512, pelvisY: 2.4087, hilt: .init(x: 0.2457, y: 1.2473, z: 0.2374), tip: .init(x: 0.4477, y: 2.4754, z: 0.3529), tipVelocityMPS: 1.67),
        .init(sourceFrame: 13, pelvisX: 1.4262, pelvisY: 2.4337, hilt: .init(x: 0.2609, y: 1.2571, z: 0.2347), tip: .init(x: 0.5131, y: 2.4762, z: 0.3474), tipVelocityMPS: 1.97),
        .init(sourceFrame: 14, pelvisX: 1.5112, pelvisY: 2.4388, hilt: .init(x: 0.2972, y: 1.2565, z: 0.2168), tip: .init(x: 0.5995, y: 2.4640, z: 0.3310), tipVelocityMPS: 2.66),
        .init(sourceFrame: 15, pelvisX: 1.5987, pelvisY: 2.4250, hilt: .init(x: 0.3320, y: 1.2519, z: 0.2016), tip: .init(x: 0.6841, y: 2.4457, z: 0.3173), tipVelocityMPS: 2.63),
        .init(sourceFrame: 16, pelvisX: 1.6887, pelvisY: 2.3838, hilt: .init(x: 0.3615, y: 1.2458, z: 0.1960), tip: .init(x: 0.7648, y: 2.4236, z: 0.3089), tipVelocityMPS: 2.52),
        .init(sourceFrame: 17, pelvisX: 1.7762, pelvisY: 2.3225, hilt: .init(x: 0.3967, y: 1.2452, z: 0.1910), tip: .init(x: 0.8560, y: 2.4027, z: 0.2993), tipVelocityMPS: 2.82),
        .init(sourceFrame: 18, pelvisX: 1.8625, pelvisY: 2.2388, hilt: .init(x: 0.4293, y: 1.2358, z: 0.1768), tip: .init(x: 0.9518, y: 2.3676, z: 0.2695), tipVelocityMPS: 3.19),
        .init(sourceFrame: 19, pelvisX: 1.9575, pelvisY: 2.1212, hilt: .init(x: 0.4820, y: 1.2734, z: 0.1463), tip: .init(x: 1.0717, y: 2.3735, z: 0.2129), tipVelocityMPS: 3.98),
        .init(sourceFrame: 20, pelvisX: 2.0575, pelvisY: 1.9875, hilt: .init(x: 0.5666, y: 1.3914, z: 0.0984), tip: .init(x: 1.2191, y: 2.4566, z: 0.1446), tipVelocityMPS: 5.47),
        .init(sourceFrame: 21, pelvisX: 2.1687, pelvisY: 1.8450, hilt: .init(x: 0.6955, y: 1.5614, z: 0.0309), tip: .init(x: 1.4255, y: 2.5753, z: 0.0704), tipVelocityMPS: 7.48),
        .init(sourceFrame: 22, pelvisX: 2.2875, pelvisY: 1.6750, hilt: .init(x: 0.8664, y: 1.7215, z: -0.0591), tip: .init(x: 1.7172, y: 2.6361, z: -0.0133), tipVelocityMPS: 9.29),
        .init(sourceFrame: 23, pelvisX: 2.4250, pelvisY: 1.4850, hilt: .init(x: 1.0738, y: 1.9017, z: -0.1734), tip: .init(x: 2.0999, y: 2.6136, z: -0.1218), tipVelocityMPS: 11.95),
        .init(sourceFrame: 24, pelvisX: 2.5575, pelvisY: 1.2812, hilt: .init(x: 1.3126, y: 2.0993, z: -0.3531), tip: .init(x: 2.5359, y: 2.3246, z: -0.2291), tipVelocityMPS: 16.02),
        .init(sourceFrame: 25, pelvisX: 2.6562, pelvisY: 1.0494, hilt: .init(x: 1.6972, y: 2.1646, z: -0.4951), tip: .init(x: 2.8920, y: 1.8920, z: -0.2487), tipVelocityMPS: 16.82),
        .init(sourceFrame: 26, pelvisX: 2.7262, pelvisY: 0.7519, hilt: .init(x: 2.2725, y: 2.1190, z: -0.5683), tip: .init(x: 3.2237, y: 1.3648, z: -0.2698), tipVelocityMPS: 18.70),
        .init(sourceFrame: 27, pelvisX: 2.7937, pelvisY: 0.4697, hilt: .init(x: 3.0107, y: 1.8091, z: -0.5525), tip: .init(x: 3.4919, y: 0.7365, z: -0.1274), tipVelocityMPS: 20.93),
        .init(sourceFrame: 28, pelvisX: 2.8087, pelvisY: 0.3478, hilt: .init(x: 3.8130, y: 1.0216, z: -0.2769), tip: .init(x: 3.3062, y: -0.0393, z: 0.1475), tipVelocityMPS: 25.31),
        .init(sourceFrame: 29, pelvisX: 2.8087, pelvisY: 0.3209, hilt: .init(x: 3.9383, y: 0.0407, z: 0.0648), tip: .init(x: 2.7053, y: -0.1583, z: 0.1156), tipVelocityMPS: 18.40),
        .init(sourceFrame: 30, pelvisX: 2.8087, pelvisY: 0.3253, hilt: .init(x: 3.9478, y: 0.0229, z: 0.0902), tip: .init(x: 2.6993, y: 0.0734, z: 0.1252), tipVelocityMPS: 6.96),
        .init(sourceFrame: 31, pelvisX: 2.8137, pelvisY: 0.3484, hilt: .init(x: 3.9357, y: 0.1056, z: 0.1129), tip: .init(x: 2.6862, y: 0.1151, z: 0.1456), tipVelocityMPS: 1.45),
        .init(sourceFrame: 32, pelvisX: 2.8187, pelvisY: 0.3672, hilt: .init(x: 3.9461, y: 0.1110, z: 0.1283), tip: .init(x: 2.7022, y: -0.0119, z: 0.1322), tipVelocityMPS: 3.86),
        .init(sourceFrame: 33, pelvisX: 2.8212, pelvisY: 0.3809, hilt: .init(x: 3.9531, y: 0.0632, z: 0.1430), tip: .init(x: 2.7131, y: -0.0925, z: 0.1212), tipVelocityMPS: 2.46),
        .init(sourceFrame: 34, pelvisX: 2.8187, pelvisY: 0.3894, hilt: .init(x: 3.9472, y: 0.0267, z: 0.1579), tip: .init(x: 2.6976, y: 0.0079, z: 0.1329), tipVelocityMPS: 3.07),
        .init(sourceFrame: 35, pelvisX: 2.8137, pelvisY: 0.3922, hilt: .init(x: 3.9490, y: 0.0265, z: 0.1587), tip: .init(x: 2.6991, y: 0.0359, z: 0.1480), tipVelocityMPS: 0.95),
        .init(sourceFrame: 36, pelvisX: 2.8037, pelvisY: 0.3891, hilt: .init(x: 3.9393, y: 0.0268, z: 0.1656), tip: .init(x: 2.6894, y: 0.0362, z: 0.1548), tipVelocityMPS: 0.36),
        .init(sourceFrame: 37, pelvisX: 2.7962, pelvisY: 0.3825, hilt: .init(x: 3.9280, y: 0.0265, z: 0.1763), tip: .init(x: 2.6781, y: 0.0359, z: 0.1654), tipVelocityMPS: 0.47),
        .init(sourceFrame: 38, pelvisX: 2.7887, pelvisY: 0.3778, hilt: .init(x: 3.9050, y: 0.0264, z: 0.2013), tip: .init(x: 2.6551, y: 0.0358, z: 0.1904), tipVelocityMPS: 1.02),
        .init(sourceFrame: 39, pelvisX: 2.7762, pelvisY: 0.3816, hilt: .init(x: 3.8485, y: 0.0258, z: 0.2197), tip: .init(x: 2.5987, y: 0.0473, z: 0.2224), tipVelocityMPS: 1.98),
        .init(sourceFrame: 40, pelvisX: 2.7662, pelvisY: 0.3994, hilt: .init(x: 3.7453, y: 0.0385, z: 0.2495), tip: .init(x: 2.4965, y: 0.0924, z: 0.2453), tipVelocityMPS: 3.42),
        .init(sourceFrame: 41, pelvisX: 2.7537, pelvisY: 0.4359, hilt: .init(x: 3.6203, y: 0.0672, z: 0.2977), tip: .init(x: 2.3747, y: 0.1609, z: 0.2529), tipVelocityMPS: 4.20),
        .init(sourceFrame: 42, pelvisX: 2.7412, pelvisY: 0.4853, hilt: .init(x: 3.4688, y: 0.1165, z: 0.3268), tip: .init(x: 2.2320, y: 0.2656, z: 0.2237), tipVelocityMPS: 5.38),
        .init(sourceFrame: 43, pelvisX: 2.7337, pelvisY: 0.5484, hilt: .init(x: 3.3100, y: 0.1805, z: 0.3284), tip: .init(x: 2.0920, y: 0.3969, z: 0.1488), tipVelocityMPS: 6.18),
        .init(sourceFrame: 44, pelvisX: 2.7262, pelvisY: 0.6175, hilt: .init(x: 3.1638, y: 0.2502, z: 0.3223), tip: .init(x: 1.9814, y: 0.5680, z: 0.0703), tipVelocityMPS: 6.55),
        .init(sourceFrame: 45, pelvisX: 2.7187, pelvisY: 0.6806, hilt: .init(x: 3.0544, y: 0.3215, z: 0.3208), tip: .init(x: 1.9222, y: 0.7576, z: 0.0204), tipVelocityMPS: 6.14),
        .init(sourceFrame: 46, pelvisX: 2.7137, pelvisY: 0.7394, hilt: .init(x: 2.9242, y: 0.4121, z: 0.3158), tip: .init(x: 1.8585, y: 0.9664, z: -0.0300), tipVelocityMPS: 6.72),
        .init(sourceFrame: 47, pelvisX: 2.7112, pelvisY: 0.7931, hilt: .init(x: 2.7632, y: 0.5111, z: 0.3046), tip: .init(x: 1.7689, y: 1.1620, z: -0.0832), tipVelocityMPS: 6.65),
        .init(sourceFrame: 48, pelvisX: 2.7112, pelvisY: 0.8425, hilt: .init(x: 2.6507, y: 0.6083, z: 0.2994), tip: .init(x: 1.6904, y: 1.2959, z: -0.1102), tipVelocityMPS: 4.73),
        .init(sourceFrame: 49, pelvisX: 2.7112, pelvisY: 0.8862, hilt: .init(x: 2.6096, y: 0.7228, z: 0.3000), tip: .init(x: 1.6400, y: 1.4037, z: -0.0985), tipVelocityMPS: 3.59),
        .init(sourceFrame: 50, pelvisX: 2.7162, pelvisY: 0.9194, hilt: .init(x: 2.7142, y: 0.8707, z: 0.3162), tip: .init(x: 1.6894, y: 1.5112, z: -0.0033), tipVelocityMPS: 4.56),
        .init(sourceFrame: 51, pelvisX: 2.7187, pelvisY: 0.9313, hilt: .init(x: 2.8123, y: 1.0125, z: 0.3297), tip: .init(x: 1.7428, y: 1.6184, z: 0.1029), tipVelocityMPS: 4.80),
        .init(sourceFrame: 52, pelvisX: 2.7237, pelvisY: 0.9337, hilt: .init(x: 2.9329, y: 1.1486, z: 0.3301), tip: .init(x: 1.8077, y: 1.6812, z: 0.2171), tipVelocityMPS: 4.37),
        .init(sourceFrame: 53, pelvisX: 2.7287, pelvisY: 0.9281, hilt: .init(x: 3.0314, y: 1.2306, z: 0.3114), tip: .init(x: 1.8511, y: 1.6421, z: 0.3166), tipVelocityMPS: 3.46),
        .init(sourceFrame: 54, pelvisX: 2.7362, pelvisY: 0.9138, hilt: .init(x: 3.1049, y: 1.2815, z: 0.2787), tip: .init(x: 1.8869, y: 1.5293, z: 0.4110), tipVelocityMPS: 4.54),
        .init(sourceFrame: 55, pelvisX: 2.7412, pelvisY: 0.8931, hilt: .init(x: 3.1742, y: 1.2997, z: 0.2295), tip: .init(x: 1.9546, y: 1.3511, z: 0.4985), tipVelocityMPS: 6.29),
        .init(sourceFrame: 56, pelvisX: 2.7487, pelvisY: 0.8644, hilt: .init(x: 3.2462, y: 1.2783, z: 0.1564), tip: .init(x: 2.0770, y: 1.1339, z: 0.5744), tipVelocityMPS: 7.82),
        .init(sourceFrame: 57, pelvisX: 2.7562, pelvisY: 0.8337, hilt: .init(x: 3.3050, y: 1.2297, z: 0.0734), tip: .init(x: 2.2185, y: 0.9439, z: 0.6215), tipVelocityMPS: 7.25),
        .init(sourceFrame: 58, pelvisX: 2.7587, pelvisY: 0.8050, hilt: .init(x: 3.3377, y: 1.1468, z: -0.0079), tip: .init(x: 2.3307, y: 0.8113, z: 0.6523), tipVelocityMPS: 5.29),
        .init(sourceFrame: 59, pelvisX: 2.7562, pelvisY: 0.7831, hilt: .init(x: 3.3187, y: 1.0571, z: -0.0756), tip: .init(x: 2.3788, y: 0.7240, z: 0.6782), tipVelocityMPS: 3.09),
        .init(sourceFrame: 60, pelvisX: 2.7537, pelvisY: 0.7700, hilt: .init(x: 3.2934, y: 1.0156, z: -0.1201), tip: .init(x: 2.3945, y: 0.6942, z: 0.6869), tipVelocityMPS: 1.04),
        .init(sourceFrame: 61, pelvisX: 2.7487, pelvisY: 0.7669, hilt: .init(x: 3.2519, y: 0.9768, z: -0.1475), tip: .init(x: 2.3693, y: 0.6649, z: 0.6809), tipVelocityMPS: 1.18),
        .init(sourceFrame: 62, pelvisX: 2.7462, pelvisY: 0.7700, hilt: .init(x: 3.2267, y: 0.9754, z: -0.1598), tip: .init(x: 2.3351, y: 0.6542, z: 0.6553), tipVelocityMPS: 1.32),
        .init(sourceFrame: 63, pelvisX: 2.7412, pelvisY: 0.7788, hilt: .init(x: 3.2208, y: 0.9907, z: -0.1621), tip: .init(x: 2.3099, y: 0.6456, z: 0.6213), tipVelocityMPS: 1.30),
        .init(sourceFrame: 64, pelvisX: 2.7362, pelvisY: 0.7875, hilt: .init(x: 3.2196, y: 1.0146, z: -0.1615), tip: .init(x: 2.2944, y: 0.6440, z: 0.5929), tipVelocityMPS: 0.97),
        .init(sourceFrame: 65, pelvisX: 2.7337, pelvisY: 0.7963, hilt: .init(x: 3.2230, y: 1.0432, z: -0.1596), tip: .init(x: 2.2888, y: 0.6472, z: 0.5705), tipVelocityMPS: 0.70),
        .init(sourceFrame: 66, pelvisX: 2.7312, pelvisY: 0.8037, hilt: .init(x: 3.2256, y: 1.0625, z: -0.1549), tip: .init(x: 2.2840, y: 0.6464, z: 0.5542), tipVelocityMPS: 0.51),
        .init(sourceFrame: 67, pelvisX: 2.7287, pelvisY: 0.8087, hilt: .init(x: 3.2273, y: 1.0714, z: -0.1513), tip: .init(x: 2.2834, y: 0.6465, z: 0.5495), tipVelocityMPS: 0.14),
    ]

    /// Synthesized `rec_monkey_king_mid_block_heavy` (36f @ 30 FPS) damped slide curve in meters (`independentRecreation`).
    public static let synthesizedBlockDxMeters: [Double] = [
        0.0000, -0.1616, -0.3046, -0.4310, -0.5427, -0.6413, -0.7283, -0.8050, -0.8726, -0.9319,
        -0.9838, -1.0291, -1.0684, -1.1023, -1.1312, -1.1555, -1.1756, -1.1917, -1.2041, -1.2130,
        -1.2185, -1.2208, -1.2200, -1.2164, -1.2102, -1.2016, -1.1910, -1.1788, -1.1680, -1.1600,
        -1.1550, -1.1520, -1.1505, -1.1500, -1.1500, -1.1500,
    ]
}
