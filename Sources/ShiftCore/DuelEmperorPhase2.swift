import Foundation

/// Phase 2 isolated completion module for Liu Quanwei / Emperor (`emperor.rar`) — Dual-Form Combat
/// (`human` <-> `shadowBeast`), Transformation Shockwave (`emperor_transition`), Human Heavy Lunge
/// (`p_agl_heavy_punch`), Shadow Beast Claw Slash + Lifesteal (`claws_spinning_slash_1`), and
/// provenance-tagged independent gap-fills (`rec_emperor_human_idle`, `rec_emperor_mid_block_heavy`,
/// `rec_emperor_step_forward_cycle`, and recreated transformation/claw VFX replacing 47 missing external CAB refs).
public enum DuelEmperorPhase2 {

    public typealias Provenance = DuelShogunHeavyPhase1.Provenance

    public enum Form: String, Codable, Sendable, Equatable {
        case human
        case shadowBeast
    }

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

    // MARK: - Measured Original Track Constants (`emperor.rar`)

    public static let initialHP = 2900                                   // Provenance: independentRecreation (unified 4-hero arena baseline)
    public static let humanHeavyFrames30FPS = 51                         // Provenance: originalBinaryMeasured (`p_agl_heavy_punch.bytes`)
    public static let humanHeavyTicks60Hz = 101                          // Provenance: originalBinaryMeasured (MidFrames=1)
    public static let humanHeavyActiveStartTick60Hz = 34                 // Provenance: originalBinaryMeasured (f17..f21 lunge strike)
    public static let humanHeavyActiveEndTick60Hz = 43                   // Provenance: originalBinaryMeasured
    public static let humanHeavyNetLungeMeters = 2.2122                  // Provenance: originalBinaryMeasured

    public static let transitionFrames30FPS = 86                         // Provenance: originalBinaryMeasured (`emperor_transition.bytes`, 118 bones)
    public static let transitionTicks60Hz = 171                          // Provenance: originalBinaryMeasured
    public static let transitionBurstStartTick60Hz = 100                 // Provenance: originalBinaryMeasured (f50..f51 burst peak 13.67 m/s)
    public static let transitionBurstEndTick60Hz = 103                   // Provenance: originalBinaryMeasured
    public static let transitionBurstRadiusMeters = 2.65                 // Provenance: independentRecreation (47 VFX CAB refs missing)

    public static let beastSlashFrames30FPS = 46                         // Provenance: originalBinaryMeasured (`claws_spinning_slash_1.bytes`, 118 bones)
    public static let beastSlashTicks60Hz = 91                           // Provenance: originalBinaryMeasured
    public static let beastSlashActiveStartTick60Hz = 20                 // Provenance: originalBinaryMeasured (f10..f16 claw sweep)
    public static let beastSlashActiveEndTick60Hz = 33                   // Provenance: originalBinaryMeasured
    public static let beastSlashNetLungeMeters = 1.0515                  // Provenance: originalBinaryMeasured

    public static let blockLowHeavyFrames30FPS = 39                      // Provenance: originalBinaryMeasured (`b_claws_low_block_heavy.bytes`)
    public static let blockLowHeavyTicks60Hz = 77                        // Provenance: originalBinaryMeasured
    public static let blockNetSlideMeters = 1.1806                       // Provenance: originalBinaryMeasured

    public static let fistCapsuleRadiusMeters = 0.14                     // Provenance: independentRecreation (weapons config encrypted)
    public static let clawCapsuleRadiusMeters = 0.16                     // Provenance: independentRecreation (weapons config encrypted)
    public static let defenderBodyRadiusMeters = 0.24                    // Provenance: independentRecreation
    public static let defenderHeadRadiusMeters = 0.14                    // Provenance: independentRecreation

    /// Explicit provenance ledger for every Emperor gap-fill completed independently.
    public static let gapFillManifest: [GapFillItem] = [
        .init(id: "head_swap_liuQuanwei", category: "3DModel",
              description: "Replaced emperor_base_head with CleanHead_liuQuanwei.glb + skin-matched collar neck bridge",
              provenance: .independentRecreation, replacesMissingSource: "Custom likeness requirement"),
        .init(id: "rec_emperor_human_idle", category: "Animation",
              description: "Synthesized 60f/119t60 human breathing martial idle stance anchored to p_agl_punch_1 f0",
              provenance: .independentRecreation, replacesMissingSource: "Missing animations-stances-base-emperor.bin"),
        .init(id: "rec_emperor_mid_block_heavy", category: "Animation",
              description: "Synthesized 39f/77t60 standing cross-guard reusing original b_claws_low_block_heavy 1.181m slide curve",
              provenance: .independentRecreation, replacesMissingSource: "Missing mid/high guard clips (only b_claws_low_block* present)"),
        .init(id: "rec_emperor_step_forward_cycle", category: "Animation",
              description: "Synthesized 30f/59t60 Dynasty footwork step transition cycle",
              provenance: .independentRecreation, replacesMissingSource: "Missing shared Dynasty locomotion bundle"),
        .init(id: "rec_vfx_emperor_transform_explosion", category: "VFXShader",
              description: "Procedural Shadow-energy burst ring, volumetric smoke pulse, and purple-black rim shader",
              provenance: .independentRecreation, replacesMissingSource: "47 unresolved VFX/Shader CAB refs (cab-ccbc0b..., cab-3b33c5...)"),
        .init(id: "rec_emperor_combat_scalars", category: "CombatBalance",
              description: "Balanced human punch / transformation burst / beast claw damage, hitstop, and beast lifesteal scalars",
              provenance: .independentRecreation, replacesMissingSource: "Encrypted weapons/armor XML & unverified live video"),
    ]

    public struct CombatParameters: Equatable, Sendable {
        public let humanHeavyDamage: Int                                 // Provenance: independentRecreation
        public let humanHeavyGuardChip: Int                              // Provenance: independentRecreation
        public let humanHeavyHitStopTicks60Hz: Int                       // Provenance: independentRecreation
        public let guardBlockStopTicks60Hz: Int                          // Provenance: independentRecreation
        public let humanHeavyKnockbackMeters: Double                     // Provenance: independentRecreation
        public let transformBurstDamage: Int                             // Provenance: independentRecreation
        public let transformBurstGuardChip: Int                          // Provenance: independentRecreation
        public let transformBurstKnockbackMeters: Double                 // Provenance: independentRecreation
        public let beastClawDamage: Int                                  // Provenance: independentRecreation
        public let beastClawGuardChip: Int                               // Provenance: independentRecreation
        public let beastClawHitLifestealHP: Int                          // Provenance: independentRecreation
        public let beastClawGuardLifestealHP: Int                        // Provenance: independentRecreation
        public let beastClawHitStopTicks60Hz: Int                        // Provenance: independentRecreation
        public let beastClawKnockbackMeters: Double                      // Provenance: independentRecreation

        public static let standard = CombatParameters(
            humanHeavyDamage: 182,
            humanHeavyGuardChip: 54,
            humanHeavyHitStopTicks60Hz: 8,
            guardBlockStopTicks60Hz: 4,
            humanHeavyKnockbackMeters: 1.45,
            transformBurstDamage: 245,
            transformBurstGuardChip: 78,
            transformBurstKnockbackMeters: 2.10,
            beastClawDamage: 215,
            beastClawGuardChip: 66,
            beastClawHitLifestealHP: 68,
            beastClawGuardLifestealHP: 18,
            beastClawHitStopTicks60Hz: 9,
            beastClawKnockbackMeters: 1.35
        )
    }

    public enum MoveKind: String, Codable, Sendable, Equatable {
        case humanHeavyPunch
        case shadowTransformation
        case beastClawSlash
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
        public let initialForm: Form
        public let attackerInitialHP: Int
        public let defenderStartX: Double
        public let defenderGuarding: Bool
        public let interruptAtTick60Hz: Int?
        public let interruptDamageToAttacker: Int
        public let parameters: CombatParameters

        public init(move: MoveKind,
                    initialForm: Form,
                    attackerInitialHP: Int = DuelEmperorPhase2.initialHP,
                    defenderStartX: Double,
                    defenderGuarding: Bool,
                    interruptAtTick60Hz: Int? = nil,
                    interruptDamageToAttacker: Int = 0,
                    parameters: CombatParameters = .standard) {
            self.move = move
            self.initialForm = initialForm
            self.attackerInitialHP = attackerInitialHP
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
        public let initialForm: Form
        public let finalForm: Form
        public let didTransformToBeast: Bool
        public let resolution: ResolutionKind
        public let finalPhase: Phase
        public let causedGuardBreak: Bool
        public let contactTick60Hz: Int?
        public let damageSettlementCount: Int
        public let attackerStartHP: Int
        public let attackerEndHP: Int
        public let attackerLifestealHealedHP: Int
        public let defenderStartHP: Int
        public let defenderEndHP: Int
        public let hitStopTicksApplied: Int
        public let defenderKnockbackMeters: Double
        public let sfxTriggers: [TickEvent]
        public let vfxTriggers: [TickEvent]
        public let events: [TickEvent]

        public var defenderHPDelta: Int { defenderStartHP - defenderEndHP }
        public var attackerNetHPLost: Int { max(0, attackerStartHP - attackerEndHP) }
    }

    // MARK: - 60 Hz Sampling Helpers

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

    private static func testSweep(before: SourceFrameSample,
                                  after: SourceFrameSample,
                                  radius: Double,
                                  defenderX: Double) -> DuelWeaponCapsule.Contact? {
        let segBefore = DuelWeaponCapsule(a: before.hilt, b: before.tip, radius: radius)
        let segAfter = DuelWeaponCapsule(a: after.hilt, b: after.tip, radius: radius)
        let hurts = defenderHurtCapsules(atX: defenderX)
        var earliest: DuelWeaponCapsule.Contact?
        for h in hurts {
            if let hit = DuelWeaponCapsule.swept(attackBefore: segBefore, attackAfter: segAfter, hurtBefore: h, hurtAfter: h) {
                if earliest == nil || hit.time < earliest!.time { earliest = hit }
            }
        }
        return earliest
    }

    // MARK: - Deterministic 60 Hz Runner

    public static func runScenario(_ config: ScenarioConfig) -> ScenarioResult {
        var form = config.initialForm
        var didTransform = false
        var attackerHP = config.attackerInitialHP
        let defenderStartHP = initialHP
        var defenderHP = defenderStartHP
        var healedHP = 0
        var defenderX = config.defenderStartX
        let defenderStartX = config.defenderStartX

        var phase: Phase = .startup
        var resolution: ResolutionKind = .none
        var settledSegment = false
        var damageSettlementCount = 0
        var contactTick: Int? = nil

        let totalAnimTicks: Int
        let activeStart: Int
        let activeEnd: Int
        switch config.move {
        case .humanHeavyPunch:
            totalAnimTicks = humanHeavyTicks60Hz
            activeStart = humanHeavyActiveStartTick60Hz
            activeEnd = humanHeavyActiveEndTick60Hz
        case .shadowTransformation:
            totalAnimTicks = transitionTicks60Hz
            activeStart = transitionBurstStartTick60Hz
            activeEnd = transitionBurstEndTick60Hz
        case .beastClawSlash:
            totalAnimTicks = beastSlashTicks60Hz
            activeStart = beastSlashActiveStartTick60Hz
            activeEnd = beastSlashActiveEndTick60Hz
        }

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
        case .humanHeavyPunch:
            sfx.append(.init(tick60Hz: 0, sourceFrame30FPS: 0.0, kind: "sfx", detail: "hero_Emperor_Heavy_Attack_1.wav [originalBinaryMeasured]"))
        case .shadowTransformation:
            sfx.append(.init(tick60Hz: 0, sourceFrame30FPS: 0.0, kind: "sfx", detail: "sfx_emperor_transform_start.wav [originalBinaryMeasured]"))
            vfx.append(.init(tick60Hz: 0, sourceFrame30FPS: 0.0, kind: "vfx", detail: "rec_vfx_emperor_transform_charge [independentRecreation]"))
        case .beastClawSlash:
            sfx.append(.init(tick60Hz: 0, sourceFrame30FPS: 0.0, kind: "sfx", detail: "ShadowBeast_Attack_Heavy_5.wav [originalBinaryMeasured]"))
        }

        while totalTicks < 340 {
            if hitStopRemaining > 0 {
                hitStopRemaining -= 1
                totalTicks += 1
                continue
            }

            if let bTick = blockSlideTick {
                let idx = min(blockLowHeavyDxMeters.count - 1, bTick / 2)
                defenderX = defenderStartX + (-blockLowHeavyDxMeters[idx])
                blockSlideTick = (bTick + 1 < blockLowHeavyTicks60Hz) ? (bTick + 1) : nil
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
                                    detail: "Interrupted before active tick \(activeStart); form remains \(form.rawValue), defender HP delta = 0"))
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
                // Transformation locks Shadow Beast form at burst onset (t60 = 100)
                if config.move == .shadowTransformation && !didTransform {
                    form = .shadowBeast
                    didTransform = true
                    sfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "sfx",
                                     detail: "sfx_emperor_transform.wav + monster_morph.wav [originalBinaryMeasured]"))
                    vfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "vfx",
                                     detail: "rec_vfx_emperor_transform_explosion(r=\(transitionBurstRadiusMeters)m) [independentRecreation]"))
                    events.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "transform",
                                        detail: "Form transitioned human -> shadowBeast (permanent for round)"))
                }

                if !settledSegment {
                    let hitTriggered: Bool
                    switch config.move {
                    case .humanHeavyPunch:
                        let prev = sample(frames: humanHeavyFrames, atTick60Hz: max(0, animTick - 1))
                        let curr = sample(frames: humanHeavyFrames, atTick60Hz: animTick)
                        hitTriggered = testSweep(before: prev, after: curr, radius: fistCapsuleRadiusMeters, defenderX: defenderX) != nil
                    case .shadowTransformation:
                        // Radial shockwave centered on Emperor pelvis (X ~ +0.05m at f50)
                        hitTriggered = abs(defenderX - 0.05) <= (transitionBurstRadiusMeters + defenderBodyRadiusMeters)
                    case .beastClawSlash:
                        let prev = sample(frames: beastSlashFrames, atTick60Hz: max(0, animTick - 1))
                        let curr = sample(frames: beastSlashFrames, atTick60Hz: animTick)
                        hitTriggered = testSweep(before: prev, after: curr, radius: clawCapsuleRadiusMeters, defenderX: defenderX) != nil
                    }

                    if hitTriggered {
                        settledSegment = true
                        damageSettlementCount += 1
                        contactTick = animTick

                        if config.defenderGuarding {
                            resolution = .guardedBlock
                            let chip: Int
                            switch config.move {
                            case .humanHeavyPunch: chip = config.parameters.humanHeavyGuardChip
                            case .shadowTransformation: chip = config.parameters.transformBurstGuardChip
                            case .beastClawSlash:
                                chip = config.parameters.beastClawGuardChip
                                let heal = min(initialHP - attackerHP, config.parameters.beastClawGuardLifestealHP)
                                attackerHP += heal
                                healedHP += heal
                            }
                            defenderHP = max(0, defenderHP - chip)
                            hitStopRemaining = config.parameters.guardBlockStopTicks60Hz
                            hitStopApplied = config.parameters.guardBlockStopTicks60Hz
                            blockSlideTick = 0
                            events.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "guard_block",
                                                detail: "Blocked \(config.move.rawValue) (NO guard break): chip=\(chip) [independentRecreation], b_claws_low_block_heavy 77t slide [originalBinaryMeasured]"))
                        } else {
                            resolution = .cleanHit
                            let dmg: Int
                            let hStop: Int
                            let kb: Double
                            switch config.move {
                            case .humanHeavyPunch:
                                dmg = config.parameters.humanHeavyDamage
                                hStop = config.parameters.humanHeavyHitStopTicks60Hz
                                kb = config.parameters.humanHeavyKnockbackMeters
                            case .shadowTransformation:
                                dmg = config.parameters.transformBurstDamage
                                hStop = 10
                                kb = config.parameters.transformBurstKnockbackMeters
                            case .beastClawSlash:
                                dmg = config.parameters.beastClawDamage
                                hStop = config.parameters.beastClawHitStopTicks60Hz
                                kb = config.parameters.beastClawKnockbackMeters
                                let heal = min(initialHP - attackerHP, config.parameters.beastClawHitLifestealHP)
                                attackerHP += heal
                                healedHP += heal
                                sfx.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "sfx",
                                                 detail: "sfx_weapon_claw_long_04.wav [originalBinaryMeasured]"))
                            }
                            defenderHP = max(0, defenderHP - dmg)
                            hitStopRemaining = hStop
                            hitStopApplied = hStop
                            hitKnockbackRemaining = 22
                            hitKnockbackStep = kb / 22.0
                            events.append(.init(tick60Hz: totalTicks, sourceFrame30FPS: Double(animTick) * 0.5, kind: "hit",
                                                detail: "Clean hit \(config.move.rawValue): dmg=\(dmg), lifesteal=\(healedHP), kb=\(kb)m [independentRecreation]"))
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
            initialForm: config.initialForm,
            finalForm: form,
            didTransformToBeast: didTransform,
            resolution: resolution,
            finalPhase: phase,
            causedGuardBreak: false,
            contactTick60Hz: contactTick,
            damageSettlementCount: damageSettlementCount,
            attackerStartHP: config.attackerInitialHP,
            attackerEndHP: attackerHP,
            attackerLifestealHealedHP: healedHP,
            defenderStartHP: defenderStartHP,
            defenderEndHP: defenderHP,
            hitStopTicksApplied: hitStopApplied,
            defenderKnockbackMeters: defenderX - defenderStartX,
            sfxTriggers: sfx,
            vfxTriggers: vfx,
            events: events
        )
    }

    // MARK: - Measured Original Track Data (`emperor.rar`)

    /// Measured `p_agl_heavy_punch.bytes` (51f @ 30 FPS) fight-space kinematics.
    public static let humanHeavyFrames: [SourceFrameSample] = [
        .init(sourceFrame: 0, pelvisX: 0.0000, pelvisY: 0.8094, hilt: .init(x: -0.0808, y: 1.0327, z: 0.2538), tip: .init(x: -0.2691, y: 0.8278, z: 0.2850), tipVelocityMPS: 0.00),
        .init(sourceFrame: 1, pelvisX: 0.0208, pelvisY: 0.8013, hilt: .init(x: -0.0652, y: 1.0179, z: 0.2843), tip: .init(x: -0.2964, y: 0.9057, z: 0.3956), tipVelocityMPS: 4.14),
        .init(sourceFrame: 2, pelvisX: 0.0711, pelvisY: 0.7931, hilt: .init(x: 0.0124, y: 0.9851, z: 0.3360), tip: .init(x: -0.1276, y: 1.0355, z: 0.5732), tipVelocityMPS: 8.32),
        .init(sourceFrame: 3, pelvisX: 0.1298, pelvisY: 0.8013, hilt: .init(x: 0.1767, y: 0.9541, z: 0.3632), tip: .init(x: 0.1118, y: 1.0153, z: 0.6287), tipVelocityMPS: 7.40),
        .init(sourceFrame: 4, pelvisX: 0.1948, pelvisY: 0.8225, hilt: .init(x: 0.3943, y: 0.9182, z: 0.3690), tip: .init(x: 0.3815, y: 0.9472, z: 0.6472), tipVelocityMPS: 8.36),
        .init(sourceFrame: 5, pelvisX: 0.2906, pelvisY: 0.8800, hilt: .init(x: 0.6891, y: 0.9632, z: 0.3411), tip: .init(x: 0.7319, y: 0.9735, z: 0.6177), tipVelocityMPS: 10.58),
        .init(sourceFrame: 6, pelvisX: 0.3987, pelvisY: 0.9537, hilt: .init(x: 0.9414, y: 1.0547, z: 0.2924), tip: .init(x: 1.0173, y: 1.1146, z: 0.5552), tipVelocityMPS: 9.73),
        .init(sourceFrame: 7, pelvisX: 0.5034, pelvisY: 0.9988, hilt: .init(x: 1.1479, y: 1.2500, z: 0.2319), tip: .init(x: 1.1637, y: 1.2153, z: 0.5093), tipVelocityMPS: 5.51),
        .init(sourceFrame: 8, pelvisX: 0.6003, pelvisY: 1.0063, hilt: .init(x: 1.3176, y: 1.4462, z: 0.1966), tip: .init(x: 1.2969, y: 1.2773, z: 0.4190), tipVelocityMPS: 5.17),
        .init(sourceFrame: 9, pelvisX: 0.7034, pelvisY: 0.9831, hilt: .init(x: 1.3595, y: 1.5698, z: 0.2389), tip: .init(x: 1.4368, y: 1.3302, z: 0.3614), tipVelocityMPS: 4.81),
        .init(sourceFrame: 10, pelvisX: 0.8047, pelvisY: 0.9363, hilt: .init(x: 1.3585, y: 1.5208, z: 0.3025), tip: .init(x: 1.5008, y: 1.2797, z: 0.3026), tipVelocityMPS: 3.02),
        .init(sourceFrame: 11, pelvisX: 0.9203, pelvisY: 0.8700, hilt: .init(x: 1.4041, y: 1.3492, z: 0.2889), tip: .init(x: 1.4000, y: 1.1045, z: 0.1529), tipVelocityMPS: 7.54),
        .init(sourceFrame: 12, pelvisX: 1.0322, pelvisY: 0.7788, hilt: .init(x: 1.4818, y: 1.0999, z: 0.2372), tip: .init(x: 1.4449, y: 0.8614, z: 0.0952), tipVelocityMPS: 7.62),
        .init(sourceFrame: 13, pelvisX: 1.1109, pelvisY: 0.6831, hilt: .init(x: 1.5591, y: 0.8459, z: 0.1789), tip: .init(x: 1.4416, y: 0.6218, z: 0.0589), tipVelocityMPS: 7.27),
        .init(sourceFrame: 14, pelvisX: 1.2172, pelvisY: 0.5941, hilt: .init(x: 1.6512, y: 0.6835, z: 0.1489), tip: .init(x: 1.4632, y: 0.5018, z: 0.0486), tipVelocityMPS: 3.67),
        .init(sourceFrame: 15, pelvisX: 1.3634, pelvisY: 0.5106, hilt: .init(x: 1.7581, y: 0.6132, z: 0.1592), tip: .init(x: 1.5416, y: 0.4799, z: 0.0419), tipVelocityMPS: 2.45),
        .init(sourceFrame: 16, pelvisX: 1.5609, pelvisY: 0.4903, hilt: .init(x: 1.9402, y: 0.5574, z: 0.1972), tip: .init(x: 1.7582, y: 0.4023, z: 0.0516), tipVelocityMPS: 6.91),
        .init(sourceFrame: 17, pelvisX: 1.8434, pelvisY: 0.5309, hilt: .init(x: 2.2235, y: 0.5930, z: 0.2659), tip: .init(x: 2.0783, y: 0.3797, z: 0.1571), tipVelocityMPS: 10.13),
        .init(sourceFrame: 18, pelvisX: 2.0322, pelvisY: 0.5475, hilt: .init(x: 2.5738, y: 0.5837, z: 0.2528), tip: .init(x: 2.4710, y: 0.3576, z: 0.1237), tipVelocityMPS: 11.84),
        .init(sourceFrame: 19, pelvisX: 2.1909, pelvisY: 0.5600, hilt: .init(x: 3.0860, y: 0.6643, z: 0.1605), tip: .init(x: 3.1366, y: 0.4341, z: 0.0093), tipVelocityMPS: 20.39),
        .init(sourceFrame: 20, pelvisX: 2.2422, pelvisY: 0.5816, hilt: .init(x: 3.4606, y: 0.7322, z: 0.0972), tip: .init(x: 3.4052, y: 0.5081, z: -0.0612), tipVelocityMPS: 8.62),
        .init(sourceFrame: 21, pelvisX: 2.3047, pelvisY: 0.6031, hilt: .init(x: 3.4222, y: 0.6944, z: 0.1305), tip: .init(x: 3.3488, y: 0.4770, z: -0.0300), tipVelocityMPS: 2.15),
        .init(sourceFrame: 22, pelvisX: 2.3359, pelvisY: 0.6094, hilt: .init(x: 3.4172, y: 0.7215, z: 0.1269), tip: .init(x: 3.3198, y: 0.5016, z: -0.0163), tipVelocityMPS: 1.21),
        .init(sourceFrame: 23, pelvisX: 2.3484, pelvisY: 0.6106, hilt: .init(x: 3.4304, y: 0.7163, z: 0.1323), tip: .init(x: 3.3185, y: 0.5010, z: -0.0074), tipVelocityMPS: 0.27),
        .init(sourceFrame: 24, pelvisX: 2.3534, pelvisY: 0.6109, hilt: .init(x: 3.4330, y: 0.7148, z: 0.1339), tip: .init(x: 3.3196, y: 0.4973, z: -0.0011), tipVelocityMPS: 0.22),
        .init(sourceFrame: 25, pelvisX: 2.3572, pelvisY: 0.6112, hilt: .init(x: 3.4338, y: 0.7092, z: 0.1361), tip: .init(x: 3.3169, y: 0.4946, z: -0.0007), tipVelocityMPS: 0.11),
        .init(sourceFrame: 26, pelvisX: 2.3622, pelvisY: 0.6138, hilt: .init(x: 3.4305, y: 0.6998, z: 0.1387), tip: .init(x: 3.3123, y: 0.4863, z: 0.0014), tipVelocityMPS: 0.29),
        .init(sourceFrame: 27, pelvisX: 2.3709, pelvisY: 0.6181, hilt: .init(x: 3.4244, y: 0.6877, z: 0.1401), tip: .init(x: 3.3237, y: 0.4607, z: 0.0108), tipVelocityMPS: 0.89),
        .init(sourceFrame: 28, pelvisX: 2.3909, pelvisY: 0.6266, hilt: .init(x: 3.4144, y: 0.6764, z: 0.1478), tip: .init(x: 3.3198, y: 0.4450, z: 0.0218), tipVelocityMPS: 0.59),
        .init(sourceFrame: 29, pelvisX: 2.4059, pelvisY: 0.6381, hilt: .init(x: 3.4016, y: 0.6693, z: 0.1583), tip: .init(x: 3.3041, y: 0.4404, z: 0.0298), tipVelocityMPS: 0.54),
        .init(sourceFrame: 30, pelvisX: 2.4122, pelvisY: 0.6556, hilt: .init(x: 3.3830, y: 0.6690, z: 0.1743), tip: .init(x: 3.2723, y: 0.4522, z: 0.0359), tipVelocityMPS: 1.03),
        .init(sourceFrame: 31, pelvisX: 2.4109, pelvisY: 0.6769, hilt: .init(x: 3.3548, y: 0.6743, z: 0.1936), tip: .init(x: 3.2289, y: 0.4727, z: 0.0456), tipVelocityMPS: 1.47),
        .init(sourceFrame: 32, pelvisX: 2.4047, pelvisY: 0.7013, hilt: .init(x: 3.3149, y: 0.6858, z: 0.2134), tip: .init(x: 3.1769, y: 0.4939, z: 0.0633), tipVelocityMPS: 1.77),
        .init(sourceFrame: 33, pelvisX: 2.3947, pelvisY: 0.7275, hilt: .init(x: 3.2596, y: 0.7039, z: 0.2314), tip: .init(x: 3.1153, y: 0.5070, z: 0.0942), tipVelocityMPS: 2.10),
        .init(sourceFrame: 34, pelvisX: 2.3822, pelvisY: 0.7531, hilt: .init(x: 3.1863, y: 0.7278, z: 0.2443), tip: .init(x: 3.0420, y: 0.5096, z: 0.1446), tipVelocityMPS: 2.67),
        .init(sourceFrame: 35, pelvisX: 2.3659, pelvisY: 0.7788, hilt: .init(x: 3.1000, y: 0.7580, z: 0.2481), tip: .init(x: 2.9579, y: 0.5204, z: 0.2065), tipVelocityMPS: 3.15),
        .init(sourceFrame: 36, pelvisX: 2.3472, pelvisY: 0.8019, hilt: .init(x: 3.0123, y: 0.7896, z: 0.2428), tip: .init(x: 2.8719, y: 0.5480, z: 0.2616), tipVelocityMPS: 3.17),
        .init(sourceFrame: 37, pelvisX: 2.3234, pelvisY: 0.8219, hilt: .init(x: 2.9292, y: 0.8185, z: 0.2307), tip: .init(x: 2.7901, y: 0.5848, z: 0.2975), tipVelocityMPS: 2.90),
        .init(sourceFrame: 38, pelvisX: 2.2984, pelvisY: 0.8375, hilt: .init(x: 2.8563, y: 0.8438, z: 0.2123), tip: .init(x: 2.7196, y: 0.6214, z: 0.3136), tipVelocityMPS: 2.43),
        .init(sourceFrame: 39, pelvisX: 2.2734, pelvisY: 0.8469, hilt: .init(x: 2.7950, y: 0.8644, z: 0.1886), tip: .init(x: 2.6598, y: 0.6511, z: 0.3096), tipVelocityMPS: 2.01),
        .init(sourceFrame: 40, pelvisX: 2.2497, pelvisY: 0.8500, hilt: .init(x: 2.7467, y: 0.8792, z: 0.1629), tip: .init(x: 2.6080, y: 0.6702, z: 0.2873), tipVelocityMPS: 1.79),
        .init(sourceFrame: 41, pelvisX: 2.2297, pelvisY: 0.8475, hilt: .init(x: 2.7121, y: 0.8891, z: 0.1386), tip: .init(x: 2.5656, y: 0.6809, z: 0.2550), tipVelocityMPS: 1.63),
        .init(sourceFrame: 42, pelvisX: 2.2134, pelvisY: 0.8413, hilt: .init(x: 2.6882, y: 0.8961, z: 0.1180), tip: .init(x: 2.5331, y: 0.6871, z: 0.2214), tipVelocityMPS: 1.42),
        .init(sourceFrame: 43, pelvisX: 2.2034, pelvisY: 0.8337, hilt: .init(x: 2.6744, y: 0.9033, z: 0.1041), tip: .init(x: 2.5150, y: 0.6917, z: 0.1947), tipVelocityMPS: 0.98),
        .init(sourceFrame: 44, pelvisX: 2.1997, pelvisY: 0.8263, hilt: .init(x: 2.6677, y: 0.9116, z: 0.0982), tip: .init(x: 2.5114, y: 0.6945, z: 0.1808), tipVelocityMPS: 0.44),
        .init(sourceFrame: 45, pelvisX: 2.2009, pelvisY: 0.8194, hilt: .init(x: 2.6665, y: 0.9203, z: 0.0986), tip: .init(x: 2.5185, y: 0.6961, z: 0.1774), tipVelocityMPS: 0.24),
        .init(sourceFrame: 46, pelvisX: 2.2059, pelvisY: 0.8137, hilt: .init(x: 2.6697, y: 0.9280, z: 0.1024), tip: .init(x: 2.5316, y: 0.6972, z: 0.1804), tipVelocityMPS: 0.40),
        .init(sourceFrame: 47, pelvisX: 2.2097, pelvisY: 0.8106, hilt: .init(x: 2.6722, y: 0.9341, z: 0.1068), tip: .init(x: 2.5423, y: 0.6988, z: 0.1854), tipVelocityMPS: 0.36),
        .init(sourceFrame: 48, pelvisX: 2.2122, pelvisY: 0.8094, hilt: .init(x: 2.6744, y: 0.9363, z: 0.1089), tip: .init(x: 2.5477, y: 0.6994, z: 0.1880), tipVelocityMPS: 0.18),
        .init(sourceFrame: 49, pelvisX: 2.2122, pelvisY: 0.8094, hilt: .init(x: 2.6744, y: 0.9363, z: 0.1089), tip: .init(x: 2.5477, y: 0.6994, z: 0.1880), tipVelocityMPS: 0.00),
        .init(sourceFrame: 50, pelvisX: 2.2122, pelvisY: 0.8094, hilt: .init(x: 2.6744, y: 0.9363, z: 0.1089), tip: .init(x: 2.5477, y: 0.6994, z: 0.1880), tipVelocityMPS: 0.00),
    ]

    /// Measured `claws_spinning_slash_1.bytes` (46f @ 30 FPS) fight-space kinematics.
    public static let beastSlashFrames: [SourceFrameSample] = [
        .init(sourceFrame: 0, pelvisX: 0.0000, pelvisY: 0.8081, hilt: .init(x: -0.0821, y: 1.0322, z: 0.2537), tip: .init(x: -0.4320, y: 0.6519, z: 0.3116), tipVelocityMPS: 0.00),
        .init(sourceFrame: 1, pelvisX: -0.0062, pelvisY: 0.8000, hilt: .init(x: -0.1220, y: 1.0291, z: 0.2659), tip: .init(x: -0.4955, y: 0.6691, z: 0.3016), tipVelocityMPS: 2.00),
        .init(sourceFrame: 2, pelvisX: -0.0290, pelvisY: 0.7900, hilt: .init(x: -0.2291, y: 1.0322, z: 0.2932), tip: .init(x: -0.6490, y: 0.7264, z: 0.2683), tipVelocityMPS: 5.02),
        .init(sourceFrame: 3, pelvisX: -0.0708, pelvisY: 0.7788, hilt: .init(x: -0.3823, y: 1.0372, z: 0.3218), tip: .init(x: -0.8306, y: 0.7922, z: 0.2248), tipVelocityMPS: 5.94),
        .init(sourceFrame: 4, pelvisX: -0.1221, pelvisY: 0.7838, hilt: .init(x: -0.5477, y: 1.0626, z: 0.3422), tip: .init(x: -1.0023, y: 0.8545, z: 0.1994), tipVelocityMPS: 5.53),
        .init(sourceFrame: 5, pelvisX: -0.1632, pelvisY: 0.8125, hilt: .init(x: -0.6786, y: 1.1319, z: 0.3649), tip: .init(x: -1.1331, y: 0.9452, z: 0.1946), tipVelocityMPS: 4.78),
        .init(sourceFrame: 6, pelvisX: -0.1507, pelvisY: 0.8550, hilt: .init(x: -0.7084, y: 1.2525, z: 0.4072), tip: .init(x: -1.1312, y: 1.0556, z: 0.1771), tipVelocityMPS: 3.35),
        .init(sourceFrame: 7, pelvisX: -0.0935, pelvisY: 0.8806, hilt: .init(x: -0.5937, y: 1.3922, z: 0.4554), tip: .init(x: -0.8193, y: 0.9858, z: 0.2224), tipVelocityMPS: 9.68),
        .init(sourceFrame: 8, pelvisX: -0.0198, pelvisY: 0.8962, hilt: .init(x: -0.3500, y: 1.4930, z: 0.4853), tip: .init(x: -0.4573, y: 0.9843, z: 0.4939), tipVelocityMPS: 13.58),
        .init(sourceFrame: 9, pelvisX: 0.0660, pelvisY: 0.9119, hilt: .init(x: 0.0762, y: 1.5875, z: 0.5540), tip: .init(x: 0.0805, y: 1.0978, z: 0.7288), tipVelocityMPS: 17.93),
        .init(sourceFrame: 10, pelvisX: 0.1634, pelvisY: 0.9156, hilt: .init(x: 0.5880, y: 1.5837, z: 0.4729), tip: .init(x: 0.7598, y: 1.1132, z: 0.6125), tipVelocityMPS: 20.68),
        .init(sourceFrame: 11, pelvisX: 0.3029, pelvisY: 0.9025, hilt: .init(x: 1.0538, y: 1.4855, z: 0.2516), tip: .init(x: 1.2303, y: 0.9964, z: 0.2574), tipVelocityMPS: 18.03),
        .init(sourceFrame: 12, pelvisX: 0.4590, pelvisY: 0.8825, hilt: .init(x: 1.4256, y: 1.3537, z: 0.0038), tip: .init(x: 1.3974, y: 0.8571, z: 0.1556), tipVelocityMPS: 7.21),
        .init(sourceFrame: 13, pelvisX: 0.5887, pelvisY: 0.8556, hilt: .init(x: 1.5924, y: 1.2081, z: -0.2321), tip: .init(x: 1.4954, y: 0.8172, z: 0.0969), tipVelocityMPS: 3.63),
        .init(sourceFrame: 14, pelvisX: 0.7421, pelvisY: 0.8069, hilt: .init(x: 1.6145, y: 1.0088, z: -0.5073), tip: .init(x: 1.7175, y: 0.7273, z: -0.0824), tipVelocityMPS: 8.98),
        .init(sourceFrame: 15, pelvisX: 0.8765, pelvisY: 0.7462, hilt: .init(x: 1.4264, y: 0.7929, z: -0.6398), tip: .init(x: 1.8072, y: 0.5956, z: -0.3457), tipVelocityMPS: 9.23),
        .init(sourceFrame: 16, pelvisX: 1.0415, pelvisY: 0.6638, hilt: .init(x: 0.8593, y: 0.7797, z: -0.5986), tip: .init(x: 0.9138, y: 0.2852, z: -0.4470), tipVelocityMPS: 28.53),
        .init(sourceFrame: 17, pelvisX: 1.1590, pelvisY: 0.6303, hilt: .init(x: 0.8644, y: 0.8327, z: -0.5039), tip: .init(x: 0.7989, y: 0.3259, z: -0.4073), tipVelocityMPS: 3.85),
        .init(sourceFrame: 18, pelvisX: 1.2228, pelvisY: 0.6172, hilt: .init(x: 0.9273, y: 0.8251, z: -0.4679), tip: .init(x: 0.8528, y: 0.3154, z: -0.3969), tipVelocityMPS: 1.68),
        .init(sourceFrame: 19, pelvisX: 1.2515, pelvisY: 0.6188, hilt: .init(x: 1.0014, y: 0.7895, z: -0.4616), tip: .init(x: 0.9917, y: 0.2722, z: -0.4095), tipVelocityMPS: 4.38),
        .init(sourceFrame: 20, pelvisX: 1.2590, pelvisY: 0.6278, hilt: .init(x: 1.0662, y: 0.7664, z: -0.4519), tip: .init(x: 1.1201, y: 0.2514, z: -0.4039), tipVelocityMPS: 3.91),
        .init(sourceFrame: 21, pelvisX: 1.2628, pelvisY: 0.6384, hilt: .init(x: 1.1019, y: 0.7610, z: -0.4477), tip: .init(x: 1.2003, y: 0.2544, z: -0.3836), tipVelocityMPS: 2.48),
        .init(sourceFrame: 22, pelvisX: 1.2628, pelvisY: 0.6488, hilt: .init(x: 1.1293, y: 0.7541, z: -0.4445), tip: .init(x: 1.2498, y: 0.2550, z: -0.3620), tipVelocityMPS: 1.62),
        .init(sourceFrame: 23, pelvisX: 1.2603, pelvisY: 0.6581, hilt: .init(x: 1.1634, y: 0.7459, z: -0.4393), tip: .init(x: 1.2993, y: 0.2501, z: -0.3614), tipVelocityMPS: 1.49),
        .init(sourceFrame: 24, pelvisX: 1.2565, pelvisY: 0.6669, hilt: .init(x: 1.2158, y: 0.7382, z: -0.4320), tip: .init(x: 1.3813, y: 0.2493, z: -0.3685), tipVelocityMPS: 2.47),
        .init(sourceFrame: 25, pelvisX: 1.2490, pelvisY: 0.6750, hilt: .init(x: 1.2811, y: 0.7319, z: -0.4168), tip: .init(x: 1.4901, y: 0.2609, z: -0.3468), tipVelocityMPS: 3.35),
        .init(sourceFrame: 26, pelvisX: 1.2403, pelvisY: 0.6837, hilt: .init(x: 1.3555, y: 0.7286, z: -0.3934), tip: .init(x: 1.5885, y: 0.2675, z: -0.3342), tipVelocityMPS: 2.98),
        .init(sourceFrame: 27, pelvisX: 1.2278, pelvisY: 0.6925, hilt: .init(x: 1.4313, y: 0.7293, z: -0.3599), tip: .init(x: 1.6971, y: 0.2876, z: -0.2913), tipVelocityMPS: 3.55),
        .init(sourceFrame: 28, pelvisX: 1.2128, pelvisY: 0.7031, hilt: .init(x: 1.5048, y: 0.7371, z: -0.3196), tip: .init(x: 1.7976, y: 0.3209, z: -0.2129), tipVelocityMPS: 3.95),
        .init(sourceFrame: 29, pelvisX: 1.1953, pelvisY: 0.7156, hilt: .init(x: 1.5712, y: 0.7529, z: -0.2614), tip: .init(x: 1.8850, y: 0.3807, z: -0.0784), tipVelocityMPS: 5.14),
        .init(sourceFrame: 30, pelvisX: 1.1765, pelvisY: 0.7294, hilt: .init(x: 1.6256, y: 0.7755, z: -0.2035), tip: .init(x: 1.9334, y: 0.4514, z: 0.0623), tipVelocityMPS: 4.94),
        .init(sourceFrame: 31, pelvisX: 1.1578, pelvisY: 0.7444, hilt: .init(x: 1.6636, y: 0.8030, z: -0.1438), tip: .init(x: 1.9077, y: 0.5286, z: 0.2243), tipVelocityMPS: 5.44),
        .init(sourceFrame: 32, pelvisX: 1.1390, pelvisY: 0.7594, hilt: .init(x: 1.6848, y: 0.8323, z: -0.0873), tip: .init(x: 1.8008, y: 0.5755, z: 0.3497), tipVelocityMPS: 5.14),
        .init(sourceFrame: 33, pelvisX: 1.1203, pelvisY: 0.7738, hilt: .init(x: 1.6927, y: 0.8629, z: -0.0369), tip: .init(x: 1.6422, y: 0.5782, z: 0.3953), tipVelocityMPS: 4.95),
        .init(sourceFrame: 34, pelvisX: 1.1040, pelvisY: 0.7863, hilt: .init(x: 1.6874, y: 0.8922, z: 0.0058), tip: .init(x: 1.5375, y: 0.5747, z: 0.3893), tipVelocityMPS: 3.15),
        .init(sourceFrame: 35, pelvisX: 1.0903, pelvisY: 0.7956, hilt: .init(x: 1.6664, y: 0.9175, z: 0.0383), tip: .init(x: 1.4667, y: 0.5758, z: 0.3756), tipVelocityMPS: 2.16),
        .init(sourceFrame: 36, pelvisX: 1.0790, pelvisY: 0.8025, hilt: .init(x: 1.6346, y: 0.9374, z: 0.0613), tip: .init(x: 1.4075, y: 0.5779, z: 0.3606), tipVelocityMPS: 1.83),
        .init(sourceFrame: 37, pelvisX: 1.0703, pelvisY: 0.8063, hilt: .init(x: 1.5989, y: 0.9500, z: 0.0769), tip: .init(x: 1.3427, y: 0.5694, z: 0.3217), tipVelocityMPS: 2.28),
        .init(sourceFrame: 38, pelvisX: 1.0628, pelvisY: 0.8087, hilt: .init(x: 1.5651, y: 0.9557, z: 0.0879), tip: .init(x: 1.2885, y: 0.5522, z: 0.2642), tipVelocityMPS: 2.43),
        .init(sourceFrame: 39, pelvisX: 1.0578, pelvisY: 0.8094, hilt: .init(x: 1.5406, y: 0.9532, z: 0.0967), tip: .init(x: 1.2732, y: 0.5344, z: 0.2499), tipVelocityMPS: 0.83),
        .init(sourceFrame: 40, pelvisX: 1.0540, pelvisY: 0.8094, hilt: .init(x: 1.5245, y: 0.9464, z: 0.1035), tip: .init(x: 1.2692, y: 0.5144, z: 0.2399), tipVelocityMPS: 0.68),
        .init(sourceFrame: 41, pelvisX: 1.0528, pelvisY: 0.8094, hilt: .init(x: 1.5170, y: 0.9397, z: 0.1081), tip: .init(x: 1.2764, y: 0.5020, z: 0.2527), tipVelocityMPS: 0.58),
        .init(sourceFrame: 42, pelvisX: 1.0515, pelvisY: 0.8087, hilt: .init(x: 1.5139, y: 0.9362, z: 0.1096), tip: .init(x: 1.2791, y: 0.4969, z: 0.2588), tipVelocityMPS: 0.25),
        .init(sourceFrame: 43, pelvisX: 1.0515, pelvisY: 0.8087, hilt: .init(x: 1.5138, y: 0.9361, z: 0.1094), tip: .init(x: 1.2790, y: 0.4967, z: 0.2586), tipVelocityMPS: 0.01),
        .init(sourceFrame: 44, pelvisX: 1.0515, pelvisY: 0.8087, hilt: .init(x: 1.5138, y: 0.9361, z: 0.1094), tip: .init(x: 1.2790, y: 0.4967, z: 0.2586), tipVelocityMPS: 0.00),
        .init(sourceFrame: 45, pelvisX: 1.0515, pelvisY: 0.8087, hilt: .init(x: 1.5138, y: 0.9361, z: 0.1094), tip: .init(x: 1.2790, y: 0.4967, z: 0.2586), tipVelocityMPS: 0.00),
    ]

    /// Measured original `b_claws_low_block_heavy.bytes` (39f @ 30 FPS) pelvis X displacement in meters.
    public static let blockLowHeavyDxMeters: [Double] = [
        0.0000, -0.0695, -0.1956, -0.3397, -0.4706, -0.5862, -0.6912, -0.7881, -0.8794, -0.9688,
        -1.0588, -1.1519, -1.2394, -1.3106, -1.3594, -1.3831, -1.3881, -1.3819, -1.3706, -1.3544,
        -1.3306, -1.2981, -1.2606, -1.2231, -1.1931, -1.1706, -1.1581, -1.1531, -1.1519, -1.1544,
        -1.1581, -1.1644, -1.1694, -1.1744, -1.1781, -1.1806, -1.1806, -1.1806, -1.1806,
    ]
}
