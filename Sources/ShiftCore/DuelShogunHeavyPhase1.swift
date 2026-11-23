import Foundation

/// Phase 1 isolated acceptance prototype for Wu Yong (head-swapped Shogun) Heavy Slash (`shogun_heavy`).
///
/// Scope & Isolation:
/// - Isolated exclusively for Phase 1 Wu Yong Shogun Heavy Slash verification.
/// - Does NOT modify `main`, shift-duty scheduling features, `DuelGame` rules for other heroes,
///   or any of the other three heroes (Liu Quanwei, Xu Xiao, Sun Deng).
/// - Every numeric parameter records its exact provenance (`originalBinaryMeasured`,
///   `independentRecreation`, or `unconfirmed`) so recreated or unverified values are never
///   misrepresented as original game algorithms.
public enum DuelShogunHeavyPhase1 {

    /// Honest provenance classification for every timing, geometry, physics, VFX, and audio value.
    public enum Provenance: String, Codable, Sendable, Equatable {
        /// Directly decoded/measured from unencrypted data inside `shogun.rar`.
        case originalBinaryMeasured
        /// Independently recreated because the original shader/texture CAB or combat config is missing/encrypted.
        case independentRecreation
        /// Cannot be proven without an original live gameplay recording or unencrypted combat balance table.
        case unconfirmed
    }

    /// One 30 FPS source frame sampled from `animations-base-shogun.bin :: shogun_heavy.bytes`
    /// (`PathID = -1565575211346705244`, 66 frames, 79 bones) after verified Unity->glTF fight-space FK
    /// (`+X` forward, `+Y` up, `+Z` toward fixed side camera; pelvis X anchored to 0 at frame 0).
    public struct SourceFrameSample: Equatable, Sendable {
        public let sourceFrame: Int
        public let pelvisX: Double
        public let pelvisY: Double
        public let hilt: DuelWeaponPoint
        public let mid: DuelWeaponPoint
        public let tip: DuelWeaponPoint
        public let tipVelocityMPS: Double
        public let trailLengthCM: Double
    }

    /// Fixed side-camera acceptance rig spec (identical for Original Shogun & Wu Yong prototype).
    public struct FixedCameraSpec: Equatable, Sendable {
        public let eye: DuelWeaponPoint
        public let target: DuelWeaponPoint
        public let focalLengthMM: Double
        public let attackerStartX: Double
        public let initialHP: Int
    }

    public static let fixedSideCamera = FixedCameraSpec(
        eye: .init(x: 1.85, y: 1.42, z: 6.20),
        target: .init(x: 1.85, y: 1.15, z: 0.0),
        focalLengthMM: 42.0,
        attackerStartX: 0.0,
        initialHP: 2900
    )

    // MARK: - Provenance-Tagged Specifications

    /// Source identity of `shogun_heavy.bytes` inside `shogun.rar`.
    public static let sourceMotionName = "shogun_heavy"
    public static let sourceMotionPathID: Int64 = -1565575211346705244
    public static let sourceMotionFrames30FPS = 66          // Provenance: originalBinaryMeasured
    public static let simulationTicks60Hz = 131             // Provenance: originalBinaryMeasured (MidFrames=1 -> 2*66-1)
    public static let activeStartSourceFrame = 22           // Provenance: originalBinaryMeasured (w_odati_trail2..4 > 0 & vel 18.37 m/s)
    public static let activeEndSourceFrame = 25             // Provenance: originalBinaryMeasured (peak vel 76.07 m/s, ground impact)
    public static let activeStartTick60Hz = 44              // Provenance: originalBinaryMeasured (22 * 2)
    public static let activeEndTick60Hz = 51                // Provenance: originalBinaryMeasured (25 * 2 + 1)
    public static let recoveryStartTick60Hz = 52            // Provenance: originalBinaryMeasured (trail returns to 0.00 cm)
    public static let blockReactionTicks60Hz = 81           // Provenance: originalBinaryMeasured (b_shogun_middle_heavy.bytes 41f)
    public static let blockPeakSlideMeters = 1.5191         // Provenance: originalBinaryMeasured (b_shogun_middle_heavy.bytes pelvis_dx)
    public static let blockNetSlideMeters = 1.2791          // Provenance: originalBinaryMeasured (b_shogun_middle_heavy.bytes end pelvis_dx)
    public static let odachiBladeRadiusMeters = 0.065       // Provenance: independentRecreation (weapons config.xml encrypted)
    public static let defenderBodyRadiusMeters = 0.24       // Provenance: independentRecreation (armor config.xml encrypted)
    public static let defenderHeadRadiusMeters = 0.14       // Provenance: independentRecreation (helm config.xml encrypted)

    /// Guard consequence policy: live SF4 live-recording confirmation is still required (`unconfirmed`).
    public enum GuardPolicy: String, Codable, Sendable, Equatable {
        /// Recreated frontal block with chip damage & original 41f `b_shogun_middle_heavy` slide (`unconfirmed` live chip %).
        case recreatedBlockWithChip
        /// Unconfirmed alternative if live recording shows guard-break on uncharged heavy (`unconfirmed`).
        case unconfirmedGuardBreak
    }

    public struct CombatParameters: Equatable, Sendable {
        public let baseDamage: Int                          // Provenance: unconfirmed (no live balance table in shogun.rar)
        public let chipDamageBps: Int                       // Provenance: unconfirmed
        public let hitStopTicks60Hz: Int                    // Provenance: unconfirmed (recreated alignment)
        public let blockHitStopTicks60Hz: Int               // Provenance: unconfirmed (recreated alignment)
        public let hitKnockbackMeters: Double               // Provenance: unconfirmed (recreated alignment)
        public let guardPolicy: GuardPolicy                 // Provenance: unconfirmed (requires live gameplay video)

        public static let phase1Default = CombatParameters(
            baseDamage: 320,
            chipDamageBps: 1500,
            hitStopTicks60Hz: 10,
            blockHitStopTicks60Hz: 6,
            hitKnockbackMeters: 1.65,
            guardPolicy: .recreatedBlockWithChip
        )
    }

    public enum Phase: String, Codable, Sendable, Equatable {
        case idle
        case startup
        case active
        case recovery
        case interrupted
        case completed
    }

    public enum ScenarioKind: String, Codable, Sendable, Equatable {
        case normalHit
        case whiff
        case guarded
        case earlyInterrupt
    }

    public enum ResolutionKind: String, Codable, Sendable, Equatable {
        case none
        case cleanHit
        case guardedBlock
        case guardBrokenHit
        case whiffed
        case interruptedBeforeActive
    }

    public struct ScenarioConfig: Equatable, Sendable {
        public let kind: ScenarioKind
        public let defenderStartX: Double
        public let defenderGuarding: Bool
        /// Optional tick (`0..<activeStartTick60Hz`) at which opponent lands a fast interrupt strike.
        public let interruptAtTick60Hz: Int?
        public let interruptDamageToAttacker: Int
        public let parameters: CombatParameters

        public static func standard(_ kind: ScenarioKind,
                                    parameters: CombatParameters = .phase1Default) -> ScenarioConfig {
            switch kind {
            case .normalHit:
                return .init(kind: .normalHit, defenderStartX: 2.85, defenderGuarding: false,
                             interruptAtTick60Hz: nil, interruptDamageToAttacker: 0, parameters: parameters)
            case .whiff:
                return .init(kind: .whiff, defenderStartX: 4.65, defenderGuarding: false,
                             interruptAtTick60Hz: nil, interruptDamageToAttacker: 0, parameters: parameters)
            case .guarded:
                return .init(kind: .guarded, defenderStartX: 2.85, defenderGuarding: true,
                             interruptAtTick60Hz: nil, interruptDamageToAttacker: 0, parameters: parameters)
            case .earlyInterrupt:
                return .init(kind: .earlyInterrupt, defenderStartX: 1.35, defenderGuarding: false,
                             interruptAtTick60Hz: 24, interruptDamageToAttacker: 85, parameters: parameters)
            }
        }
    }

    public struct TickEvent: Equatable, Sendable {
        public let tick60Hz: Int
        public let sourceFrame30FPS: Double
        public let kind: String
        public let detail: String
    }

    public struct ScenarioResult: Equatable, Sendable {
        public let kind: ScenarioKind
        public let resolution: ResolutionKind
        public let finalPhase: Phase
        public let totalSimulatedTicks60Hz: Int
        public let startupTicksObserved: Int
        public let activeTicksObserved: Int
        public let recoveryTicksObserved: Int
        public let contactTick60Hz: Int?
        public let contactPoint: DuelWeaponPoint?
        public let damageSettlementCount: Int
        public let attackerStartHP: Int
        public let attackerEndHP: Int
        public let defenderStartHP: Int
        public let defenderEndHP: Int
        public let hitStopTicksApplied: Int
        public let defenderStartX: Double
        public let defenderEndX: Double
        public let defenderKnockbackMeters: Double
        public let trailActiveTickRange: ClosedRange<Int>?
        public let sfxTriggers: [TickEvent]
        public let vfxTriggers: [TickEvent]
        public let events: [TickEvent]

        public var defenderHPDelta: Int { defenderStartHP - defenderEndHP }
        public var attackerHPDelta: Int { attackerStartHP - attackerEndHP }
    }

    // MARK: - Interpolated 60 Hz Kinematics

    /// Linearly interpolates `shogun_heavy.bytes` (30 FPS) to 60 Hz (`MidFrames = 1`).
    public static func sample(atTick60Hz tick: Int) -> SourceFrameSample {
        let clamped = max(0, min(simulationTicks60Hz - 1, tick))
        let f0 = clamped / 2
        let f1 = min(sourceFrames.count - 1, f0 + 1)
        let alpha = (clamped % 2 == 0) ? 0.0 : 0.5
        let a = sourceFrames[f0]
        let b = sourceFrames[f1]
        if alpha == 0.0 { return a }
        return SourceFrameSample(
            sourceFrame: f0,
            pelvisX: a.pelvisX + (b.pelvisX - a.pelvisX) * alpha,
            pelvisY: a.pelvisY + (b.pelvisY - a.pelvisY) * alpha,
            hilt: a.hilt.mixed(with: b.hilt, weight: alpha),
            mid: a.mid.mixed(with: b.mid, weight: alpha),
            tip: a.tip.mixed(with: b.tip, weight: alpha),
            tipVelocityMPS: a.tipVelocityMPS + (b.tipVelocityMPS - a.tipVelocityMPS) * alpha,
            trailLengthCM: a.trailLengthCM + (b.trailLengthCM - a.trailLengthCM) * alpha
        )
    }

    /// Defender hurt capsules (body + head) anchored at world X in `shogun_idle` standing posture.
    private static func defenderHurtCapsules(atX x: Double) -> [DuelWeaponCapsule] {
        let body = DuelWeaponCapsule(
            a: .init(x: x, y: 0.48, z: 0.0),
            b: .init(x: x, y: 1.24, z: 0.0),
            radius: defenderBodyRadiusMeters
        )
        let head = DuelWeaponCapsule(
            a: .init(x: x, y: 1.32, z: 0.0),
            b: .init(x: x, y: 1.56, z: 0.0),
            radius: defenderHeadRadiusMeters
        )
        return [body, head]
    }

    /// Swept-capsule intersection across both Odachi blade segments (`hilt -> mid`, `mid -> tip`).
    private static func testBladeSweep(before: SourceFrameSample,
                                       after: SourceFrameSample,
                                       defenderXBefore: Double,
                                       defenderXAfter: Double) -> DuelWeaponCapsule.Contact? {
        let segsBefore = [
            DuelWeaponCapsule(a: before.hilt, b: before.mid, radius: odachiBladeRadiusMeters),
            DuelWeaponCapsule(a: before.mid, b: before.tip, radius: odachiBladeRadiusMeters),
        ]
        let segsAfter = [
            DuelWeaponCapsule(a: after.hilt, b: after.mid, radius: odachiBladeRadiusMeters),
            DuelWeaponCapsule(a: after.mid, b: after.tip, radius: odachiBladeRadiusMeters),
        ]
        let hurtsBefore = defenderHurtCapsules(atX: defenderXBefore)
        let hurtsAfter = defenderHurtCapsules(atX: defenderXAfter)

        var earliest: DuelWeaponCapsule.Contact?
        for sIdx in 0..<2 {
            for hIdx in 0..<hurtsBefore.count {
                if let hit = DuelWeaponCapsule.swept(
                    attackBefore: segsBefore[sIdx],
                    attackAfter: segsAfter[sIdx],
                    hurtBefore: hurtsBefore[hIdx],
                    hurtAfter: hurtsAfter[hIdx]
                ) {
                    if earliest == nil || hit.time < earliest!.time {
                        earliest = hit
                    }
                }
            }
        }
        return earliest
    }

    // MARK: - Deterministic 60 Hz Prototype Runner

    public static func runScenario(_ config: ScenarioConfig) -> ScenarioResult {
        let startHP = fixedSideCamera.initialHP
        var attackerHP = startHP
        var defenderHP = startHP
        var defenderX = config.defenderStartX
        let defenderStartX = config.defenderStartX

        var phase: Phase = .startup
        var resolution: ResolutionKind = .none
        var settledSegment = false
        var damageSettlementCount = 0
        var contactTick: Int? = nil
        var contactPoint: DuelWeaponPoint? = nil

        var animTick = 0
        var hitStopRemaining = 0
        var hitStopApplied = 0
        var totalTicks = 0
        var startupObserved = 0
        var activeObserved = 0
        var recoveryObserved = 0
        var trailFirstTick: Int? = nil
        var trailLastTick: Int? = nil

        var blockSlideTick: Int? = nil
        var hitKnockbackRemaining = 0
        var hitKnockbackStepPerTick = 0.0

        var events: [TickEvent] = []
        var sfx: [TickEvent] = []
        var vfx: [TickEvent] = []

        // Tick 0 launch cues (original audio + sword charge VFX)
        sfx.append(.init(tick60Hz: 0, sourceFrame30FPS: 0.0, kind: "sfx", detail: "sfx_Shogun_heavy_load.wav [originalBinaryMeasured]"))
        sfx.append(.init(tick60Hz: 0, sourceFrame30FPS: 0.0, kind: "sfx", detail: "sfx_vo_Shogun_heavy_attack_01.wav [originalBinaryMeasured]"))
        vfx.append(.init(tick60Hz: 0, sourceFrame30FPS: 0.0, kind: "vfx", detail: "fx_shogun_heavy_sword(weapon_r_0) [independentRecreation: missing CAB shaders/tex]"))

        while totalTicks < 260 {
            // 1. Freeze both animation & knockback during hitstop frames!
            if hitStopRemaining > 0 {
                hitStopRemaining -= 1
                totalTicks += 1
                continue
            }

            // 2. Apply post-hitstop knockback / original block slide
            if let bTick = blockSlideTick {
                let idx = min(blockMiddleHeavyDxMeters.count - 1, bTick / 2)
                // Positive world delta (+X pushes defender right, away from attacker at X=0)
                let slideMeters = -blockMiddleHeavyDxMeters[idx]
                defenderX = defenderStartX + slideMeters
                blockSlideTick = (bTick + 1 < blockReactionTicks60Hz) ? (bTick + 1) : nil
            } else if hitKnockbackRemaining > 0 {
                defenderX += hitKnockbackStepPerTick
                hitKnockbackRemaining -= 1
            }

            // 3. Check early interrupt during startup (strictly BEFORE activeStartTick60Hz!)
            if let interruptTick = config.interruptAtTick60Hz,
               phase == .startup,
               animTick == interruptTick,
               animTick < activeStartTick60Hz {
                phase = .interrupted
                resolution = .interruptedBeforeActive
                attackerHP = max(0, attackerHP - config.interruptDamageToAttacker)
                events.append(.init(
                    tick60Hz: totalTicks,
                    sourceFrame30FPS: Double(animTick) * 0.5,
                    kind: "interrupt",
                    detail: "Interrupted during startup before active tick \(activeStartTick60Hz); heavy cancelled, defender HP delta = 0"
                ))
                sfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "sfx", detail: "sfx_vo_Shogun_light_damage_01.wav [originalBinaryMeasured]"))
                totalTicks += 1
                break
            }

            // 4. Advance shogun_heavy animation tick
            if animTick >= simulationTicks60Hz {
                if resolution == .none {
                    resolution = .whiffed
                }
                if blockSlideTick == nil && hitKnockbackRemaining == 0 {
                    phase = .completed
                    break
                }
                totalTicks += 1
                continue
            }

            let prevSample = sample(atTick60Hz: max(0, animTick - 1))
            let currSample = sample(atTick60Hz: animTick)

            if animTick < activeStartTick60Hz {
                phase = .startup
                startupObserved += 1
            } else if animTick <= activeEndTick60Hz {
                phase = .active
                activeObserved += 1
                if animTick == activeStartTick60Hz {
                    sfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "sfx", detail: "sfx_Shogun_shadow_whoosh_heavy_01.wav [originalBinaryMeasured]"))
                    vfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "vfx", detail: "wpn_Shogun_base_trail_r + fx_shogun_heavy_slash [recreated shader + original mesh/tex]"))
                }
                if currSample.trailLengthCM > 1.0 {
                    if trailFirstTick == nil { trailFirstTick = animTick }
                    trailLastTick = animTick
                }

                // Single-segment damage settlement gate: NEVER double-settle across ticks 44...51!
                if !settledSegment,
                   let hit = testBladeSweep(before: prevSample, after: currSample, defenderXBefore: defenderX, defenderXAfter: defenderX) {
                    settledSegment = true
                    damageSettlementCount += 1
                    contactTick = animTick
                    contactPoint = hit.point

                    if config.defenderGuarding {
                        switch config.parameters.guardPolicy {
                        case .recreatedBlockWithChip:
                            resolution = .guardedBlock
                            let chip = max(1, (config.parameters.baseDamage * config.parameters.chipDamageBps) / 10000)
                            defenderHP = max(0, defenderHP - chip)
                            hitStopRemaining = config.parameters.blockHitStopTicks60Hz
                            hitStopApplied = config.parameters.blockHitStopTicks60Hz
                            blockSlideTick = 0
                            events.append(.init(
                                tick60Hz: totalTicks,
                                sourceFrame30FPS: Double(animTick) * 0.5,
                                kind: "guard_block",
                                detail: "Blocked heavy: chip=\(chip) [unconfirmed], b_shogun_middle_heavy 81t slide [originalBinaryMeasured]"
                            ))
                            sfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "sfx", detail: "sfx_Shogun_blade_hit.wav [originalBinaryMeasured]"))
                            vfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "vfx", detail: "guard_sparks [independentRecreation]"))
                        case .unconfirmedGuardBreak:
                            resolution = .guardBrokenHit
                            defenderHP = max(0, defenderHP - config.parameters.baseDamage)
                            hitStopRemaining = config.parameters.hitStopTicks60Hz
                            hitStopApplied = config.parameters.hitStopTicks60Hz
                            hitKnockbackRemaining = 24
                            hitKnockbackStepPerTick = config.parameters.hitKnockbackMeters / 24.0
                            events.append(.init(
                                tick60Hz: totalTicks,
                                sourceFrame30FPS: Double(animTick) * 0.5,
                                kind: "guard_break",
                                detail: "Guard break [unconfirmed]: dmg=\(config.parameters.baseDamage)"
                            ))
                        }
                    } else {
                        resolution = .cleanHit
                        defenderHP = max(0, defenderHP - config.parameters.baseDamage)
                        hitStopRemaining = config.parameters.hitStopTicks60Hz
                        hitStopApplied = config.parameters.hitStopTicks60Hz
                        hitKnockbackRemaining = 24
                        hitKnockbackStepPerTick = config.parameters.hitKnockbackMeters / 24.0
                        events.append(.init(
                            tick60Hz: totalTicks,
                            sourceFrame30FPS: Double(animTick) * 0.5,
                            kind: "hit",
                            detail: "Clean heavy hit: dmg=\(config.parameters.baseDamage) [unconfirmed], hitstop=\(hitStopApplied)t [unconfirmed]"
                        ))
                        sfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "sfx", detail: "sfx_Shogun_blade_hit.wav + sfx_wpn_blood_01.wav [originalBinaryMeasured]"))
                        vfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "vfx", detail: "fx_shogun_heavy_impact(pelvis) [independentRecreation: missing CAB shaders/tex]"))
                    }
                }
            } else {
                phase = .recovery
                recoveryObserved += 1
                // Ground slam miss impact at tick 52 (f30 = 26) if whiffed
                if animTick == recoveryStartTick60Hz && !settledSegment {
                    resolution = .whiffed
                    events.append(.init(
                        tick60Hz: totalTicks,
                        sourceFrame30FPS: Double(animTick) * 0.5,
                        kind: "whiff_ground_impact",
                        detail: "Odachi struck floor with zero defender intersection; defender HP delta = 0"
                    ))
                    sfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "sfx", detail: "sfx_wpn_ODT_scrape_01.wav [originalBinaryMeasured]"))
                    vfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "vfx", detail: "fx_shogun_heavy_impact_miss(pelvis) [independentRecreation: missing CAB shaders/tex]"))
                }
            }

            animTick += 1
            totalTicks += 1
        }

        let trailRange: ClosedRange<Int>? = (trailFirstTick != nil && trailLastTick != nil)
            ? (trailFirstTick!...trailLastTick!) : nil

        return ScenarioResult(
            kind: config.kind,
            resolution: resolution,
            finalPhase: phase,
            totalSimulatedTicks60Hz: totalTicks,
            startupTicksObserved: startupObserved,
            activeTicksObserved: activeObserved,
            recoveryTicksObserved: recoveryObserved,
            contactTick60Hz: contactTick,
            contactPoint: contactPoint,
            damageSettlementCount: damageSettlementCount,
            attackerStartHP: startHP,
            attackerEndHP: attackerHP,
            defenderStartHP: startHP,
            defenderEndHP: defenderHP,
            hitStopTicksApplied: hitStopApplied,
            defenderStartX: defenderStartX,
            defenderEndX: defenderX,
            defenderKnockbackMeters: defenderX - defenderStartX,
            trailActiveTickRange: trailRange,
            sfxTriggers: sfx,
            vfxTriggers: vfx,
            events: events
        )
    }

    // MARK: - Measured Original Track Data (`shogun_heavy.bytes`, 66f @ 30 FPS)

    public static let sourceFrames: [SourceFrameSample] = [
        .init(sourceFrame: 0, pelvisX: 0.0000, pelvisY: 0.8350, hilt: .init(x: -0.5531, y: 1.1596, z: 0.0694), mid: .init(x: -0.8612, y: 0.7305, z: 0.5916), tip: .init(x: -1.0516, y: 0.2976, z: 1.1308), tipVelocityMPS: 0.00, trailLengthCM: 0.00),
        .init(sourceFrame: 1, pelvisX: -0.0250, pelvisY: 0.8375, hilt: .init(x: -0.5922, y: 1.2345, z: 0.2084), mid: .init(x: -0.8730, y: 0.9793, z: 0.8469), tip: .init(x: -1.0368, y: 0.7033, z: 1.4883), tipVelocityMPS: 16.23, trailLengthCM: 0.00),
        .init(sourceFrame: 2, pelvisX: -0.0713, pelvisY: 0.8375, hilt: .init(x: -0.6408, y: 1.4171, z: 0.4008), mid: .init(x: -0.8587, y: 1.6185, z: 1.0817), tip: .init(x: -0.9789, y: 1.7535, z: 1.7758), tipVelocityMPS: 32.71, trailLengthCM: 0.00),
        .init(sourceFrame: 3, pelvisX: -0.1038, pelvisY: 0.8263, hilt: .init(x: -0.6277, y: 1.6079, z: 0.4027), mid: .init(x: -0.8165, y: 2.2020, z: 0.8065), tip: .init(x: -0.8918, y: 2.7715, z: 1.2359), tipVelocityMPS: 34.67, trailLengthCM: 0.00),
        .init(sourceFrame: 4, pelvisX: -0.1219, pelvisY: 0.8075, hilt: .init(x: -0.5655, y: 1.7568, z: 0.2891), mid: .init(x: -0.7178, y: 2.4830, z: 0.3252), tip: .init(x: -0.7642, y: 3.1985, z: 0.3082), tipVelocityMPS: 30.88, trailLengthCM: 0.00),
        .init(sourceFrame: 5, pelvisX: -0.1338, pelvisY: 0.7881, hilt: .init(x: -0.5032, y: 1.8474, z: 0.1877), mid: .init(x: -0.6303, y: 2.5531, z: -0.0062), tip: .init(x: -0.6598, y: 3.2238, z: -0.2586), tipVelocityMPS: 17.31, trailLengthCM: 0.00),
        .init(sourceFrame: 6, pelvisX: -0.1449, pelvisY: 0.7725, hilt: .init(x: -0.4568, y: 1.9052, z: 0.1374), mid: .init(x: -0.5709, y: 2.5809, z: -0.1492), tip: .init(x: -0.5858, y: 3.2140, z: -0.4858), tipVelocityMPS: 7.18, trailLengthCM: 0.00),
        .init(sourceFrame: 7, pelvisX: -0.1519, pelvisY: 0.7588, hilt: .init(x: -0.4485, y: 1.9184, z: 0.0955), mid: .init(x: -0.5599, y: 2.5632, z: -0.2559), tip: .init(x: -0.5665, y: 3.1660, z: -0.6446), tipVelocityMPS: 5.01, trailLengthCM: 0.00),
        .init(sourceFrame: 8, pelvisX: -0.1494, pelvisY: 0.7431, hilt: .init(x: -0.4493, y: 1.8917, z: 0.0528), mid: .init(x: -0.5585, y: 2.5081, z: -0.3470), tip: .init(x: -0.5581, y: 3.0860, z: -0.7718), tipVelocityMPS: 4.52, trailLengthCM: 0.00),
        .init(sourceFrame: 9, pelvisX: -0.1318, pelvisY: 0.7213, hilt: .init(x: -0.4460, y: 1.8394, z: 0.0016), mid: .init(x: -0.5506, y: 2.4350, z: -0.4298), tip: .init(x: -0.5414, y: 2.9978, z: -0.8742), tipVelocityMPS: 4.08, trailLengthCM: 0.00),
        .init(sourceFrame: 10, pelvisX: -0.0949, pelvisY: 0.6919, hilt: .init(x: -0.4384, y: 1.7736, z: -0.0512), mid: .init(x: -0.5401, y: 2.3488, z: -0.5101), tip: .init(x: -0.5251, y: 2.9006, z: -0.9680), tipVelocityMPS: 4.08, trailLengthCM: 0.00),
        .init(sourceFrame: 11, pelvisX: -0.0385, pelvisY: 0.6606, hilt: .init(x: -0.4186, y: 1.6949, z: -0.0995), mid: .init(x: -0.5256, y: 2.2528, z: -0.5781), tip: .init(x: -0.5151, y: 2.8012, z: -1.0402), tipVelocityMPS: 3.70, trailLengthCM: 0.00),
        .init(sourceFrame: 12, pelvisX: 0.0359, pelvisY: 0.6359, hilt: .init(x: -0.3817, y: 1.6252, z: -0.1311), mid: .init(x: -0.5064, y: 2.1703, z: -0.6200), tip: .init(x: -0.5160, y: 2.7208, z: -1.0796), tipVelocityMPS: 2.69, trailLengthCM: 0.00),
        .init(sourceFrame: 13, pelvisX: 0.1270, pelvisY: 0.6241, hilt: .init(x: -0.3218, y: 1.5850, z: -0.1351), mid: .init(x: -0.4813, y: 2.1215, z: -0.6235), tip: .init(x: -0.5290, y: 2.6763, z: -1.0754), tipVelocityMPS: 1.40, trailLengthCM: 0.00),
        .init(sourceFrame: 14, pelvisX: 0.2338, pelvisY: 0.6338, hilt: .init(x: -0.2330, y: 1.5963, z: -0.0996), mid: .init(x: -0.4498, y: 2.1264, z: -0.5726), tip: .init(x: -0.5557, y: 2.6832, z: -1.0120), tipVelocityMPS: 2.07, trailLengthCM: 0.00),
        .init(sourceFrame: 15, pelvisX: 0.3545, pelvisY: 0.6681, hilt: .init(x: -0.1279, y: 1.6395, z: -0.0398), mid: .init(x: -0.4133, y: 2.1606, z: -0.4855), tip: .init(x: -0.5870, y: 2.7144, z: -0.9070), tipVelocityMPS: 3.42, trailLengthCM: 0.00),
        .init(sourceFrame: 16, pelvisX: 0.4865, pelvisY: 0.7188, hilt: .init(x: 0.0057, y: 1.7207, z: 0.0429), mid: .init(x: -0.3268, y: 2.2210, z: -0.3939), tip: .init(x: -0.5446, y: 2.7519, z: -0.8241), tipVelocityMPS: 3.01, trailLengthCM: 0.00),
        .init(sourceFrame: 17, pelvisX: 0.6268, pelvisY: 0.7694, hilt: .init(x: 0.1858, y: 1.8159, z: 0.0950), mid: .init(x: -0.1840, y: 2.2730, z: -0.3588), tip: .init(x: -0.4385, y: 2.7398, z: -0.8403), tipVelocityMPS: 3.24, trailLengthCM: 0.00),
        .init(sourceFrame: 18, pelvisX: 0.7718, pelvisY: 0.8063, hilt: .init(x: 0.3952, y: 1.8853, z: 0.0970), mid: .init(x: -0.0203, y: 2.3322, z: -0.3266), tip: .init(x: -0.3552, y: 2.7285, z: -0.8217), tipVelocityMPS: 2.58, trailLengthCM: 0.00),
        .init(sourceFrame: 19, pelvisX: 0.9224, pelvisY: 0.8156, hilt: .init(x: 0.6357, y: 1.9571, z: 0.0155), mid: .init(x: 0.1690, y: 2.3873, z: -0.3704), tip: .init(x: -0.3020, y: 2.7091, z: -0.8051), tipVelocityMPS: 1.77, trailLengthCM: 0.00),
        .init(sourceFrame: 20, pelvisX: 1.0768, pelvisY: 0.7919, hilt: .init(x: 0.8444, y: 1.9626, z: -0.1145), mid: .init(x: 0.2877, y: 2.3485, z: -0.4193), tip: .init(x: -0.3159, y: 2.6339, z: -0.6812), tipVelocityMPS: 4.37, trailLengthCM: 0.00),
        .init(sourceFrame: 21, pelvisX: 1.2356, pelvisY: 0.7375, hilt: .init(x: 0.9583, y: 1.9753, z: -0.0652), mid: .init(x: 0.3021, y: 2.2881, z: -0.2178), tip: .init(x: -0.3767, y: 2.4985, z: -0.3143), tipVelocityMPS: 11.87, trailLengthCM: 0.00),
        .init(sourceFrame: 22, pelvisX: 1.3899, pelvisY: 0.6663, hilt: .init(x: 1.3248, y: 1.9684, z: 0.0969), mid: .init(x: 0.6823, y: 2.3398, z: 0.1290), tip: .init(x: 0.0127, y: 2.5960, z: 0.1481), tipVelocityMPS: 18.37, trailLengthCM: 17.02),
        .init(sourceFrame: 23, pelvisX: 1.5387, pelvisY: 0.5913, hilt: .init(x: 1.9364, y: 1.7818, z: 0.0443), mid: .init(x: 1.5740, y: 2.4025, z: 0.2316), tip: .init(x: 1.1293, y: 2.9431, z: 0.3880), tipVelocityMPS: 35.81, trailLengthCM: 45.52),
        .init(sourceFrame: 24, pelvisX: 1.6824, pelvisY: 0.5359, hilt: .init(x: 2.4644, y: 1.2147, z: -0.1507), mid: .init(x: 2.8991, y: 1.8028, z: -0.0207), tip: .init(x: 3.2218, y: 2.4306, z: 0.1061), tipVelocityMPS: 65.18, trailLengthCM: 66.90),
        .init(sourceFrame: 25, pelvisX: 1.8512, pelvisY: 0.4900, hilt: .init(x: 2.4816, y: 0.3936, z: -0.2793), mid: .init(x: 3.1825, y: 0.1542, z: -0.3341), tip: .init(x: 3.8878, y: 0.0334, z: -0.3831), tipVelocityMPS: 76.07, trailLengthCM: 64.31),
        .init(sourceFrame: 26, pelvisX: 2.0399, pelvisY: 0.4006, hilt: .init(x: 2.4563, y: 0.3573, z: -0.3447), mid: .init(x: 3.1700, y: 0.1595, z: -0.4016), tip: .init(x: 3.8810, y: 0.0806, z: -0.4532), tipVelocityMPS: 2.54, trailLengthCM: 0.00),
        .init(sourceFrame: 27, pelvisX: 2.0374, pelvisY: 0.4753, hilt: .init(x: 2.3881, y: 0.3504, z: -0.3451), mid: .init(x: 3.0995, y: 0.1466, z: -0.4096), tip: .init(x: 3.8083, y: 0.0617, z: -0.4783), tipVelocityMPS: 2.38, trailLengthCM: 0.00),
        .init(sourceFrame: 28, pelvisX: 2.0412, pelvisY: 0.4941, hilt: .init(x: 2.3244, y: 0.3597, z: -0.3090), mid: .init(x: 3.0255, y: 0.1359, z: -0.4097), tip: .init(x: 3.7274, y: 0.0311, z: -0.5129), tipVelocityMPS: 2.79, trailLengthCM: 0.00),
        .init(sourceFrame: 29, pelvisX: 2.0387, pelvisY: 0.5056, hilt: .init(x: 2.2801, y: 0.3728, z: -0.2977), mid: .init(x: 2.9766, y: 0.1408, z: -0.4105), tip: .init(x: 3.6755, y: 0.0277, z: -0.5257), tipVelocityMPS: 1.61, trailLengthCM: 0.00),
        .init(sourceFrame: 30, pelvisX: 2.0287, pelvisY: 0.5072, hilt: .init(x: 2.2373, y: 0.3887, z: -0.2880), mid: .init(x: 2.9294, y: 0.1490, z: -0.4112), tip: .init(x: 3.6252, y: 0.0281, z: -0.5364), tipVelocityMPS: 1.54, trailLengthCM: 0.00),
        .init(sourceFrame: 31, pelvisX: 2.0174, pelvisY: 0.5075, hilt: .init(x: 2.2078, y: 0.4007, z: -0.2834), mid: .init(x: 2.8965, y: 0.1548, z: -0.4133), tip: .init(x: 3.5900, y: 0.0277, z: -0.5449), tipVelocityMPS: 1.08, trailLengthCM: 0.00),
        .init(sourceFrame: 32, pelvisX: 2.0124, pelvisY: 0.5091, hilt: .init(x: 2.1888, y: 0.4080, z: -0.2848), mid: .init(x: 2.8760, y: 0.1587, z: -0.4163), tip: .init(x: 3.5687, y: 0.0281, z: -0.5491), tipVelocityMPS: 0.65, trailLengthCM: 0.00),
        .init(sourceFrame: 33, pelvisX: 2.0062, pelvisY: 0.5094, hilt: .init(x: 2.1736, y: 0.4149, z: -0.2880), mid: .init(x: 2.8597, y: 0.1622, z: -0.4192), tip: .init(x: 3.5518, y: 0.0283, z: -0.5512), tipVelocityMPS: 0.51, trailLengthCM: 0.00),
        .init(sourceFrame: 34, pelvisX: 1.9999, pelvisY: 0.5103, hilt: .init(x: 2.1591, y: 0.4258, z: -0.2894), mid: .init(x: 2.8429, y: 0.1681, z: -0.4223), tip: .init(x: 3.5338, y: 0.0291, z: -0.5553), tipVelocityMPS: 0.55, trailLengthCM: 0.00),
        .init(sourceFrame: 35, pelvisX: 1.9912, pelvisY: 0.5119, hilt: .init(x: 2.1499, y: 0.4394, z: -0.2905), mid: .init(x: 2.8309, y: 0.1753, z: -0.4255), tip: .init(x: 3.5203, y: 0.0299, z: -0.5598), tipVelocityMPS: 0.43, trailLengthCM: 0.00),
        .init(sourceFrame: 36, pelvisX: 1.9774, pelvisY: 0.5172, hilt: .init(x: 2.1407, y: 0.4527, z: -0.2917), mid: .init(x: 2.8188, y: 0.1824, z: -0.4287), tip: .init(x: 3.5066, y: 0.0307, z: -0.5641), tipVelocityMPS: 0.43, trailLengthCM: 0.00),
        .init(sourceFrame: 37, pelvisX: 1.9612, pelvisY: 0.5238, hilt: .init(x: 2.1143, y: 0.4855, z: -0.2946), mid: .init(x: 2.7865, y: 0.2016, z: -0.4334), tip: .init(x: 3.4710, y: 0.0360, z: -0.5691), tipVelocityMPS: 1.09, trailLengthCM: 0.00),
        .init(sourceFrame: 38, pelvisX: 1.9412, pelvisY: 0.5328, hilt: .init(x: 2.0892, y: 0.5297, z: -0.2993), mid: .init(x: 2.7529, y: 0.2276, z: -0.4403), tip: .init(x: 3.4325, y: 0.0433, z: -0.5767), tipVelocityMPS: 1.20, trailLengthCM: 0.00),
        .init(sourceFrame: 39, pelvisX: 1.9112, pelvisY: 0.5587, hilt: .init(x: 2.0467, y: 0.5751, z: -0.3027), mid: .init(x: 2.6988, y: 0.2502, z: -0.4474), tip: .init(x: 3.3712, y: 0.0423, z: -0.5854), tipVelocityMPS: 1.86, trailLengthCM: 0.00),
        .init(sourceFrame: 40, pelvisX: 1.8674, pelvisY: 0.6091, hilt: .init(x: 2.0016, y: 0.6232, z: -0.3053), mid: .init(x: 2.6398, y: 0.2745, z: -0.4566), tip: .init(x: 3.3030, y: 0.0418, z: -0.5992), tipVelocityMPS: 2.09, trailLengthCM: 0.00),
        .init(sourceFrame: 41, pelvisX: 1.8287, pelvisY: 0.6663, hilt: .init(x: 1.9452, y: 0.6722, z: -0.3133), mid: .init(x: 2.5675, y: 0.2996, z: -0.4733), tip: .init(x: 3.2198, y: 0.0416, z: -0.6227), tipVelocityMPS: 2.59, trailLengthCM: 0.00),
        .init(sourceFrame: 42, pelvisX: 1.8137, pelvisY: 0.7144, hilt: .init(x: 1.8912, y: 0.7319, z: -0.3166), mid: .init(x: 2.4896, y: 0.3303, z: -0.4965), tip: .init(x: 3.1245, y: 0.0411, z: -0.6631), tipVelocityMPS: 3.11, trailLengthCM: 0.00),
        .init(sourceFrame: 43, pelvisX: 1.8174, pelvisY: 0.7544, hilt: .init(x: 1.8455, y: 0.7958, z: -0.3173), mid: .init(x: 2.4116, y: 0.3688, z: -0.5385), tip: .init(x: 3.0216, y: 0.0507, z: -0.7412), tipVelocityMPS: 3.88, trailLengthCM: 0.00),
        .init(sourceFrame: 44, pelvisX: 1.8312, pelvisY: 0.7906, hilt: .init(x: 1.8112, y: 0.8450, z: -0.3234), mid: .init(x: 2.3428, y: 0.4105, z: -0.6069), tip: .init(x: 2.9255, y: 0.0798, z: -0.8628), tipVelocityMPS: 4.73, trailLengthCM: 0.00),
        .init(sourceFrame: 45, pelvisX: 1.8499, pelvisY: 0.8225, hilt: .init(x: 1.7791, y: 0.8857, z: -0.3306), mid: .init(x: 2.2668, y: 0.4558, z: -0.6899), tip: .init(x: 2.8137, y: 0.1225, z: -1.0127), tipVelocityMPS: 5.75, trailLengthCM: 0.00),
        .init(sourceFrame: 46, pelvisX: 1.8699, pelvisY: 0.8469, hilt: .init(x: 1.7357, y: 0.9287, z: -0.3330), mid: .init(x: 2.1576, y: 0.5043, z: -0.7729), tip: .init(x: 2.6491, y: 0.1675, z: -1.1722), tipVelocityMPS: 7.01, trailLengthCM: 0.00),
        .init(sourceFrame: 47, pelvisX: 1.8862, pelvisY: 0.8625, hilt: .init(x: 1.6703, y: 0.9840, z: -0.3245), mid: .init(x: 1.9953, y: 0.5591, z: -0.8398), tip: .init(x: 2.4022, y: 0.2121, z: -1.3177), tipVelocityMPS: 8.70, trailLengthCM: 0.00),
        .init(sourceFrame: 48, pelvisX: 1.8974, pelvisY: 0.8700, hilt: .init(x: 1.5911, y: 1.0440, z: -0.3036), mid: .init(x: 1.7932, y: 0.6176, z: -0.8773), tip: .init(x: 2.0894, y: 0.2585, z: -1.4229), tipVelocityMPS: 10.00, trailLengthCM: 0.00),
        .init(sourceFrame: 49, pelvisX: 1.9062, pelvisY: 0.8719, hilt: .init(x: 1.5141, y: 1.0987, z: -0.2694), mid: .init(x: 1.5777, y: 0.6737, z: -0.8753), tip: .init(x: 1.7457, y: 0.3038, z: -1.4664), tipVelocityMPS: 10.48, trailLengthCM: 0.00),
        .init(sourceFrame: 50, pelvisX: 1.9124, pelvisY: 0.8700, hilt: .init(x: 1.4528, y: 1.1377, z: -0.2216), mid: .init(x: 1.3763, y: 0.7180, z: -0.8297), tip: .init(x: 1.4113, y: 0.3397, z: -1.4380), tipVelocityMPS: 10.12, trailLengthCM: 0.00),
        .init(sourceFrame: 51, pelvisX: 1.9174, pelvisY: 0.8675, hilt: .init(x: 1.4059, y: 1.1666, z: -0.1659), mid: .init(x: 1.1970, y: 0.7593, z: -0.7509), tip: .init(x: 1.1031, y: 0.3781, z: -1.3511), tipVelocityMPS: 9.68, trailLengthCM: 0.00),
        .init(sourceFrame: 52, pelvisX: 1.9212, pelvisY: 0.8631, hilt: .init(x: 1.3731, y: 1.1720, z: -0.0961), mid: .init(x: 1.0422, y: 0.7655, z: -0.6225), tip: .init(x: 0.8254, y: 0.3705, z: -1.1805), tipVelocityMPS: 9.78, trailLengthCM: 0.00),
        .init(sourceFrame: 53, pelvisX: 1.9249, pelvisY: 0.8594, hilt: .init(x: 1.3544, y: 1.1651, z: -0.0266), mid: .init(x: 0.9276, y: 0.7497, z: -0.4705), tip: .init(x: 0.6107, y: 0.3319, z: -0.9598), tipVelocityMPS: 9.31, trailLengthCM: 0.00),
        .init(sourceFrame: 54, pelvisX: 1.9262, pelvisY: 0.8550, hilt: .init(x: 1.3425, y: 1.1528, z: 0.0272), mid: .init(x: 0.8539, y: 0.7252, z: -0.3336), tip: .init(x: 0.4705, y: 0.2826, z: -0.7478), tipVelocityMPS: 7.77, trailLengthCM: 0.00),
        .init(sourceFrame: 55, pelvisX: 1.9262, pelvisY: 0.8513, hilt: .init(x: 1.3346, y: 1.1407, z: 0.0647), mid: .init(x: 0.8093, y: 0.7027, z: -0.2251), tip: .init(x: 0.3856, y: 0.2389, z: -0.5712), tipVelocityMPS: 6.02, trailLengthCM: 0.00),
        .init(sourceFrame: 56, pelvisX: 1.9262, pelvisY: 0.8475, hilt: .init(x: 1.3295, y: 1.1292, z: 0.0897), mid: .init(x: 0.7840, y: 0.6826, z: -0.1443), tip: .init(x: 0.3377, y: 0.2020, z: -0.4346), tipVelocityMPS: 4.48, trailLengthCM: 0.00),
        .init(sourceFrame: 57, pelvisX: 1.9249, pelvisY: 0.8444, hilt: .init(x: 1.3263, y: 1.1192, z: 0.1075), mid: .init(x: 0.7716, y: 0.6650, z: -0.0866), tip: .init(x: 0.3146, y: 0.1716, z: -0.3360), tipVelocityMPS: 3.17, trailLengthCM: 0.00),
        .init(sourceFrame: 58, pelvisX: 1.9224, pelvisY: 0.8413, hilt: .init(x: 1.3253, y: 1.1107, z: 0.1237), mid: .init(x: 0.7685, y: 0.6488, z: -0.0447), tip: .init(x: 0.3087, y: 0.1457, z: -0.2681), tipVelocityMPS: 2.19, trailLengthCM: 0.00),
        .init(sourceFrame: 59, pelvisX: 1.9212, pelvisY: 0.8394, hilt: .init(x: 1.3280, y: 1.1036, z: 0.1385), mid: .init(x: 0.7743, y: 0.6330, z: -0.0156), tip: .init(x: 0.3175, y: 0.1213, z: -0.2252), tipVelocityMPS: 1.50, trailLengthCM: 0.00),
        .init(sourceFrame: 60, pelvisX: 1.9199, pelvisY: 0.8375, hilt: .init(x: 1.3317, y: 1.0976, z: 0.1507), mid: .init(x: 0.7834, y: 0.6186, z: 0.0035), tip: .init(x: 0.3319, y: 0.0999, z: -0.2002), tipVelocityMPS: 1.08, trailLengthCM: 0.00),
        .init(sourceFrame: 61, pelvisX: 1.9187, pelvisY: 0.8363, hilt: .init(x: 1.3352, y: 1.0934, z: 0.1585), mid: .init(x: 0.7920, y: 0.6082, z: 0.0131), tip: .init(x: 0.3456, y: 0.0848, z: -0.1900), tipVelocityMPS: 0.69, trailLengthCM: 0.00),
        .init(sourceFrame: 62, pelvisX: 1.9187, pelvisY: 0.8363, hilt: .init(x: 1.3367, y: 1.0927, z: 0.1618), mid: .init(x: 0.7957, y: 0.6049, z: 0.0165), tip: .init(x: 0.3515, y: 0.0798, z: -0.1869), tipVelocityMPS: 0.25, trailLengthCM: 0.00),
        .init(sourceFrame: 63, pelvisX: 1.9187, pelvisY: 0.8363, hilt: .init(x: 1.3368, y: 1.0927, z: 0.1619), mid: .init(x: 0.7957, y: 0.6050, z: 0.0165), tip: .init(x: 0.3515, y: 0.0799, z: -0.1869), tipVelocityMPS: 0.00, trailLengthCM: 0.00),
        .init(sourceFrame: 64, pelvisX: 1.9187, pelvisY: 0.8363, hilt: .init(x: 1.3368, y: 1.0927, z: 0.1619), mid: .init(x: 0.7957, y: 0.6050, z: 0.0165), tip: .init(x: 0.3515, y: 0.0799, z: -0.1869), tipVelocityMPS: 0.00, trailLengthCM: 0.00),
        .init(sourceFrame: 65, pelvisX: 1.9187, pelvisY: 0.8363, hilt: .init(x: 1.3368, y: 1.0926, z: 0.1619), mid: .init(x: 0.7958, y: 0.6049, z: 0.0166), tip: .init(x: 0.3516, y: 0.0798, z: -0.1868), tipVelocityMPS: 0.01, trailLengthCM: 0.00),
    ]

    /// Measured original `b_shogun_middle_heavy.bytes` (41f @ 30 FPS) pelvis X displacement in meters.
    public static let blockMiddleHeavyDxMeters: [Double] = [
        0.0000, -0.0821, -0.2050, -0.3697, -0.5454, -0.7079, -0.8572, -0.9997, -1.1341, -1.2516, -1.3454, -1.4116, -1.4554, -1.4816, -1.4991, -1.5129, -1.5191, -1.5191, -1.5104, -1.4941, -1.4729, -1.4466, -1.4154, -1.3854, -1.3604, -1.3404, -1.3241, -1.3091, -1.2979, -1.2904, -1.2841, -1.2804, -1.2779, -1.2766, -1.2766, -1.2766, -1.2791, -1.2791, -1.2791, -1.2791, -1.2791
    ]
}
