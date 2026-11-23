import XCTest
@testable import ShiftCore

final class DuelLegionKingPhase3Tests: XCTestCase {

    func testOriginalLegionKingTrackAndProcedural3DChainSpecIntegrity() {
        XCTAssertEqual(DuelLegionKingPhase3.greatswordHeavyFrames.count, 64)
        XCTAssertEqual(DuelLegionKingPhase3.blockMidHeavyDxMeters.count, 32)
        XCTAssertEqual(DuelLegionKingPhase3.greatswordHeavyFrames.last!.pelvisX, DuelLegionKingPhase3.greatswordNetLungeMeters, accuracy: 0.001)
        XCTAssertEqual(-DuelLegionKingPhase3.blockMidHeavyDxMeters.last!, DuelLegionKingPhase3.blockNetSlideMeters, accuracy: 0.001)

        let chain = DuelLegionKingPhase3.proceduralChainSpec
        XCTAssertEqual(chain.linkCount, 28)
        XCTAssertTrue(chain.alternating90DegTwist)
        XCTAssertEqual(chain.provenance, .independentRecreation)
        XCTAssertEqual(chain.replacesMissingCABs.count, 3)
    }

    func testGreatswordHeavy_HitWhiffGuardAndEarlyInterrupt() {
        // 1. Clean hit
        let hit = DuelLegionKingPhase3.runScenario(.init(
            move: .greatswordHeavySlash, defenderStartX: 2.90, defenderGuarding: false
        ))
        XCTAssertEqual(hit.resolution, .cleanHit)
        XCTAssertEqual(hit.finalPhase, .completed)
        XCTAssertEqual(hit.damageSettlementCount, 1)
        XCTAssertEqual(hit.defenderHPDelta, DuelLegionKingPhase3.CombatParameters.standard.greatswordHeavyDamage)
        let contact = try! XCTUnwrap(hit.contactTick60Hz)
        XCTAssertTrue((40...51).contains(contact))

        // 2. Whiff
        let whiff = DuelLegionKingPhase3.runScenario(.init(
            move: .greatswordHeavySlash, defenderStartX: 4.80, defenderGuarding: false
        ))
        XCTAssertEqual(whiff.resolution, .whiffed)
        XCTAssertEqual(whiff.damageSettlementCount, 0)
        XCTAssertEqual(whiff.defenderHPDelta, 0)
        XCTAssertEqual(whiff.defenderDisplacementMeters, 0.0, accuracy: 1e-6)

        // 3. Guarded (NO guard break, exact original 1.108m mid-block slide)
        let guarded = DuelLegionKingPhase3.runScenario(.init(
            move: .greatswordHeavySlash, defenderStartX: 2.90, defenderGuarding: true
        ))
        XCTAssertEqual(guarded.resolution, .guardedBlock)
        XCTAssertFalse(guarded.causedGuardBreak)
        XCTAssertEqual(guarded.damageSettlementCount, 1)
        XCTAssertEqual(guarded.defenderHPDelta, DuelLegionKingPhase3.CombatParameters.standard.greatswordGuardChip)
        XCTAssertEqual(guarded.defenderDisplacementMeters, DuelLegionKingPhase3.blockNetSlideMeters, accuracy: 0.005)

        // 4. Pre-active interrupt at boundary tick 39 (1 tick before active tick 40)
        let interrupted = DuelLegionKingPhase3.runScenario(.init(
            move: .greatswordHeavySlash, defenderStartX: 2.90, defenderGuarding: false,
            interruptAtTick60Hz: 39, interruptDamageToAttacker: 95
        ))
        XCTAssertEqual(interrupted.resolution, .interruptedBeforeActive)
        XCTAssertEqual(interrupted.damageSettlementCount, 0)
        XCTAssertEqual(interrupted.defenderHPDelta, 0)
        XCTAssertEqual(interrupted.attackerHPDelta, 95)
    }

    func testProceduralShadowChain_HitSnagsAndPullsDefenderTowardKingWhileWhiffAndInterruptDoZeroPull() {
        // 1. Clean ranged chain snag & pull (-1.066m toward caster, lift Y=1.106m)
        let snag = DuelLegionKingPhase3.runScenario(.init(
            move: .shadowRangedChain, defenderStartX: 3.30, defenderGuarding: false
        ))
        XCTAssertEqual(snag.resolution, .cleanHit)
        XCTAssertTrue(snag.chainSnaggedAndPulled)
        XCTAssertEqual(snag.damageSettlementCount, 1)
        XCTAssertEqual(snag.defenderHPDelta, DuelLegionKingPhase3.CombatParameters.standard.chainHitDamage)
        XCTAssertEqual(snag.defenderDisplacementMeters, -DuelLegionKingPhase3.chainVictimPullMeters, accuracy: 0.005,
                       "Chain hit must pull defender -1.066m toward King of the Legion")
        XCTAssertLessThan(snag.defenderEndX, snag.defenderStartX)
        XCTAssertEqual(snag.chainPeakLiftYMeters, DuelLegionKingPhase3.chainVictimLiftYMeters, accuracy: 0.001)
        XCTAssertTrue(snag.sfxTriggers.contains(where: { $0.detail.contains("hero_lk_chains_hit.wav") }))

        // 2. Guarded chain deals chip, does NOT pull defender inward (blocks with standing pushback)
        let guarded = DuelLegionKingPhase3.runScenario(.init(
            move: .shadowRangedChain, defenderStartX: 3.30, defenderGuarding: true
        ))
        XCTAssertEqual(guarded.resolution, .guardedBlock)
        XCTAssertFalse(guarded.chainSnaggedAndPulled)
        XCTAssertEqual(guarded.defenderHPDelta, DuelLegionKingPhase3.CombatParameters.standard.chainGuardChip)
        XCTAssertGreaterThan(guarded.defenderDisplacementMeters, 0.0)

        // 3. Whiff beyond maxReachMeters (4.35m)
        let whiff = DuelLegionKingPhase3.runScenario(.init(
            move: .shadowRangedChain, defenderStartX: 5.30, defenderGuarding: false
        ))
        XCTAssertEqual(whiff.resolution, .whiffed)
        XCTAssertFalse(whiff.chainSnaggedAndPulled)
        XCTAssertEqual(whiff.damageSettlementCount, 0)
        XCTAssertEqual(whiff.defenderHPDelta, 0)

        // 4. Pre-cast interrupt at boundary tick 35 cancels chain cast cleanly
        let interrupted = DuelLegionKingPhase3.runScenario(.init(
            move: .shadowRangedChain, defenderStartX: 3.30, defenderGuarding: false,
            interruptAtTick60Hz: 35, interruptDamageToAttacker: 80
        ))
        XCTAssertEqual(interrupted.resolution, .interruptedBeforeActive)
        XCTAssertFalse(interrupted.chainSnaggedAndPulled)
        XCTAssertEqual(interrupted.defenderHPDelta, 0)
        XCTAssertEqual(interrupted.defenderDisplacementMeters, 0.0, accuracy: 1e-6)
    }

    func testDarkIncarnation_TriggersExactlyOncePerRoundAndNeverDoubleRevives() {
        var state = DuelLegionKingPhase3.DarkIncarnationState(startingHP: 400)

        // Non-lethal hit does not trigger revive
        let step1 = state.applyIncomingDamage(150)
        XCTAssertFalse(step1.triggeredDarkIncarnation)
        XCTAssertEqual(step1.resultingHP, 250)
        XCTAssertFalse(step1.isDefeated)
        XCTAssertEqual(state.reviveTriggerCount, 0)

        // First lethal blow triggers Dark Incarnation (legion_king_ressurection 241t60)
        let step2 = state.applyIncomingDamage(600)
        XCTAssertTrue(step2.triggeredDarkIncarnation)
        XCTAssertEqual(step2.resultingHP, DuelLegionKingPhase3.CombatParameters.standard.darkIncarnationReviveHP)
        XCTAssertEqual(step2.reviveDurationTicks60Hz, DuelLegionKingPhase3.darkIncarnationTicks60Hz)
        XCTAssertGreaterThan(step2.shockwaveKnockbackMeters, 1.0)
        XCTAssertFalse(step2.isDefeated)
        XCTAssertEqual(state.reviveTriggerCount, 1)

        // Second lethal blow MUST defeat King of the Legion (no second revive!)
        let step3 = state.applyIncomingDamage(700)
        XCTAssertFalse(step3.triggeredDarkIncarnation)
        XCTAssertEqual(step3.resultingHP, 0)
        XCTAssertTrue(step3.isDefeated)
        XCTAssertEqual(state.reviveTriggerCount, 1)
    }

    func testNoDoubleSettlementAcrossEveryReachableDistance() {
        for cm in stride(from: 100, through: 500, by: 25) {
            let x = Double(cm) / 100.0
            for move in [DuelLegionKingPhase3.MoveKind.greatswordHeavySlash, .shadowRangedChain] {
                let res = DuelLegionKingPhase3.runScenario(.init(
                    move: move, defenderStartX: x, defenderGuarding: false
                ))
                XCTAssertLessThanOrEqual(res.damageSettlementCount, 1,
                                         "Double settlement for \(move) at x=\(x)m")
            }
        }
    }
}
