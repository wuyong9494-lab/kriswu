import XCTest
@testable import ShiftCore

final class DuelEmperorPhase2Tests: XCTestCase {

    func testOriginalEmperorTrackIntegrityAndGapFillProvenance() {
        XCTAssertEqual(DuelEmperorPhase2.humanHeavyFrames.count, 51)
        XCTAssertEqual(DuelEmperorPhase2.beastSlashFrames.count, 46)
        XCTAssertEqual(DuelEmperorPhase2.blockLowHeavyDxMeters.count, 39)
        XCTAssertEqual(DuelEmperorPhase2.humanHeavyFrames.last!.pelvisX, DuelEmperorPhase2.humanHeavyNetLungeMeters, accuracy: 0.001)
        XCTAssertEqual(DuelEmperorPhase2.beastSlashFrames.last!.pelvisX, DuelEmperorPhase2.beastSlashNetLungeMeters, accuracy: 0.001)
        XCTAssertEqual(-DuelEmperorPhase2.blockLowHeavyDxMeters.last!, DuelEmperorPhase2.blockNetSlideMeters, accuracy: 0.001)
        XCTAssertTrue(DuelEmperorPhase2.gapFillManifest.allSatisfy { $0.provenance == .independentRecreation })
    }

    func testHumanHeavyPunch_HitWhiffGuardAndEarlyInterrupt() {
        // 1. Clean hit
        let hit = DuelEmperorPhase2.runScenario(.init(
            move: .humanHeavyPunch, initialForm: .human, defenderStartX: 2.95, defenderGuarding: false
        ))
        XCTAssertEqual(hit.resolution, .cleanHit)
        XCTAssertEqual(hit.finalForm, .human)
        XCTAssertEqual(hit.damageSettlementCount, 1)
        XCTAssertEqual(hit.defenderHPDelta, DuelEmperorPhase2.CombatParameters.standard.humanHeavyDamage)
        XCTAssertEqual(hit.attackerLifestealHealedHP, 0)

        // 2. Whiff
        let whiff = DuelEmperorPhase2.runScenario(.init(
            move: .humanHeavyPunch, initialForm: .human, defenderStartX: 5.10, defenderGuarding: false
        ))
        XCTAssertEqual(whiff.resolution, .whiffed)
        XCTAssertEqual(whiff.damageSettlementCount, 0)
        XCTAssertEqual(whiff.defenderHPDelta, 0)
        XCTAssertEqual(whiff.defenderKnockbackMeters, 0.0, accuracy: 1e-6)

        // 3. Guarded (NO guard break, exact 1.181m original block slide)
        let guarded = DuelEmperorPhase2.runScenario(.init(
            move: .humanHeavyPunch, initialForm: .human, defenderStartX: 2.95, defenderGuarding: true
        ))
        XCTAssertEqual(guarded.resolution, .guardedBlock)
        XCTAssertFalse(guarded.causedGuardBreak)
        XCTAssertEqual(guarded.damageSettlementCount, 1)
        XCTAssertEqual(guarded.defenderHPDelta, DuelEmperorPhase2.CombatParameters.standard.humanHeavyGuardChip)
        XCTAssertEqual(guarded.defenderKnockbackMeters, DuelEmperorPhase2.blockNetSlideMeters, accuracy: 0.005)

        // 4. Pre-active interrupt at boundary tick 33 (1 tick before active tick 34)
        let interrupted = DuelEmperorPhase2.runScenario(.init(
            move: .humanHeavyPunch, initialForm: .human, defenderStartX: 2.95, defenderGuarding: false,
            interruptAtTick60Hz: 33, interruptDamageToAttacker: 90
        ))
        XCTAssertEqual(interrupted.resolution, .interruptedBeforeActive)
        XCTAssertEqual(interrupted.finalPhase, .interrupted)
        XCTAssertEqual(interrupted.damageSettlementCount, 0)
        XCTAssertEqual(interrupted.defenderHPDelta, 0)
        XCTAssertEqual(interrupted.attackerNetHPLost, 90)
    }

    func testShadowTransformation_ExplosionHitLocksBeastFormAndInterruptCancelsTransform() {
        // 1. Transformation burst hit at close range
        let burstHit = DuelEmperorPhase2.runScenario(.init(
            move: .shadowTransformation, initialForm: .human, defenderStartX: 1.85, defenderGuarding: false
        ))
        XCTAssertEqual(burstHit.initialForm, .human)
        XCTAssertEqual(burstHit.finalForm, .shadowBeast)
        XCTAssertTrue(burstHit.didTransformToBeast)
        XCTAssertEqual(burstHit.resolution, .cleanHit)
        XCTAssertEqual(burstHit.contactTick60Hz, DuelEmperorPhase2.transitionBurstStartTick60Hz)
        XCTAssertEqual(burstHit.damageSettlementCount, 1)
        XCTAssertEqual(burstHit.defenderHPDelta, DuelEmperorPhase2.CombatParameters.standard.transformBurstDamage)
        XCTAssertTrue(burstHit.sfxTriggers.contains(where: { $0.detail.contains("monster_morph.wav") }))
        XCTAssertTrue(burstHit.vfxTriggers.contains(where: { $0.detail.contains("rec_vfx_emperor_transform_explosion") }))

        // 2. Transformation whiff at far range STILL completes form transition cleanly with 0 opponent damage
        let burstWhiff = DuelEmperorPhase2.runScenario(.init(
            move: .shadowTransformation, initialForm: .human, defenderStartX: 4.50, defenderGuarding: false
        ))
        XCTAssertEqual(burstWhiff.finalForm, .shadowBeast)
        XCTAssertTrue(burstWhiff.didTransformToBeast)
        XCTAssertEqual(burstWhiff.resolution, .whiffed)
        XCTAssertEqual(burstWhiff.damageSettlementCount, 0)
        XCTAssertEqual(burstWhiff.defenderHPDelta, 0)

        // 3. Interrupt BEFORE burst tick 100 (at tick 99) cancels form switch & causes 0 opponent damage
        let interrupted = DuelEmperorPhase2.runScenario(.init(
            move: .shadowTransformation, initialForm: .human, defenderStartX: 1.40, defenderGuarding: false,
            interruptAtTick60Hz: 99, interruptDamageToAttacker: 110
        ))
        XCTAssertEqual(interrupted.finalForm, .human, "Pre-burst interrupt must keep Emperor in Human form")
        XCTAssertFalse(interrupted.didTransformToBeast)
        XCTAssertEqual(interrupted.resolution, .interruptedBeforeActive)
        XCTAssertEqual(interrupted.damageSettlementCount, 0)
        XCTAssertEqual(interrupted.defenderHPDelta, 0)
    }

    func testShadowBeastClawSlash_LifestealHealsOnContactAndZeroOnWhiffOrInterrupt() {
        let startHP = 2300

        // Clean hit heals +68 HP
        let hit = DuelEmperorPhase2.runScenario(.init(
            move: .beastClawSlash, initialForm: .shadowBeast, attackerInitialHP: startHP,
            defenderStartX: 1.55, defenderGuarding: false
        ))
        XCTAssertEqual(hit.resolution, .cleanHit)
        XCTAssertEqual(hit.damageSettlementCount, 1)
        XCTAssertEqual(hit.defenderHPDelta, DuelEmperorPhase2.CombatParameters.standard.beastClawDamage)
        XCTAssertEqual(hit.attackerLifestealHealedHP, DuelEmperorPhase2.CombatParameters.standard.beastClawHitLifestealHP)
        XCTAssertEqual(hit.attackerEndHP, startHP + DuelEmperorPhase2.CombatParameters.standard.beastClawHitLifestealHP)

        // Guarded hit heals reduced chip lifesteal (+18 HP)
        let guarded = DuelEmperorPhase2.runScenario(.init(
            move: .beastClawSlash, initialForm: .shadowBeast, attackerInitialHP: startHP,
            defenderStartX: 1.55, defenderGuarding: true
        ))
        XCTAssertEqual(guarded.resolution, .guardedBlock)
        XCTAssertEqual(guarded.attackerLifestealHealedHP, DuelEmperorPhase2.CombatParameters.standard.beastClawGuardLifestealHP)

        // Whiff MUST heal 0 HP!
        let whiff = DuelEmperorPhase2.runScenario(.init(
            move: .beastClawSlash, initialForm: .shadowBeast, attackerInitialHP: startHP,
            defenderStartX: 3.60, defenderGuarding: false
        ))
        XCTAssertEqual(whiff.resolution, .whiffed)
        XCTAssertEqual(whiff.attackerLifestealHealedHP, 0)
        XCTAssertEqual(whiff.attackerEndHP, startHP)

        // Pre-active interrupt MUST heal 0 HP and deal 0 defender damage!
        let interrupted = DuelEmperorPhase2.runScenario(.init(
            move: .beastClawSlash, initialForm: .shadowBeast, attackerInitialHP: startHP,
            defenderStartX: 1.55, defenderGuarding: false, interruptAtTick60Hz: 19, interruptDamageToAttacker: 75
        ))
        XCTAssertEqual(interrupted.resolution, .interruptedBeforeActive)
        XCTAssertEqual(interrupted.attackerLifestealHealedHP, 0)
        XCTAssertEqual(interrupted.defenderHPDelta, 0)
    }

    func testNoDoubleSettlementAcrossEveryReachableDistanceForBothForms() {
        for cm in stride(from: 60, through: 440, by: 25) {
            let x = Double(cm) / 100.0
            for (move, form) in [(DuelEmperorPhase2.MoveKind.humanHeavyPunch, DuelEmperorPhase2.Form.human),
                                 (.beastClawSlash, .shadowBeast),
                                 (.shadowTransformation, .human)] {
                let res = DuelEmperorPhase2.runScenario(.init(
                    move: move, initialForm: form, defenderStartX: x, defenderGuarding: false
                ))
                XCTAssertLessThanOrEqual(res.damageSettlementCount, 1,
                                         "Double settlement for \(move) at x=\(x)m")
            }
        }
    }
}
