import XCTest
@testable import ShiftCore

final class DuelMonkeyKingPhase4Tests: XCTestCase {

    func testOriginalMonkeyKingTrackAndSynthesizedGuardIntegrity() {
        XCTAssertEqual(DuelMonkeyKingPhase4.staffHeavyFrames.count, 52)
        XCTAssertEqual(DuelMonkeyKingPhase4.climbForwardFrames.count, 68)
        XCTAssertEqual(DuelMonkeyKingPhase4.synthesizedBlockDxMeters.count, 36)
        XCTAssertEqual(DuelMonkeyKingPhase4.staffHeavyFrames.last!.pelvisX, DuelMonkeyKingPhase4.staffHeavyNetLungeMeters, accuracy: 0.001)
        XCTAssertEqual(DuelMonkeyKingPhase4.climbForwardFrames.last!.pelvisX, DuelMonkeyKingPhase4.climbForwardNetLungeMeters, accuracy: 0.001)
        XCTAssertEqual(-DuelMonkeyKingPhase4.synthesizedBlockDxMeters.last!, DuelMonkeyKingPhase4.synthesizedBlockNetSlideMeters, accuracy: 0.001)
        XCTAssertTrue(DuelMonkeyKingPhase4.gapFillManifest.contains(where: { $0.id == "rec_monkey_king_mid_block_heavy" && $0.provenance == .independentRecreation }))
    }

    func testStaffHeavy_HitWhiffSynthesizedGuardAndEarlyInterrupt() {
        // 1. Clean leaping staff heavy hit
        let hit = DuelMonkeyKingPhase4.runScenario(.init(
            move: .staffHeavySlash, defenderStartX: 3.15, defenderGuarding: false
        ))
        XCTAssertEqual(hit.resolution, .cleanHit)
        XCTAssertEqual(hit.damageSettlementCount, 1)
        XCTAssertEqual(hit.defenderHPDelta, DuelMonkeyKingPhase4.CombatParameters.standard.staffHeavyDamage)
        XCTAssertGreaterThanOrEqual(hit.peakAttackerPelvisYMeters, 1.41)

        // 2. Whiff
        let whiff = DuelMonkeyKingPhase4.runScenario(.init(
            move: .staffHeavySlash, defenderStartX: 5.10, defenderGuarding: false
        ))
        XCTAssertEqual(whiff.resolution, .whiffed)
        XCTAssertEqual(whiff.damageSettlementCount, 0)
        XCTAssertEqual(whiff.defenderHPDelta, 0)
        XCTAssertEqual(whiff.defenderKnockbackMeters, 0.0, accuracy: 1e-6)

        // 3. Synthesized Guard (`rec_monkey_king_mid_block_heavy` replacing 0 b_* gap!)
        let guarded = DuelMonkeyKingPhase4.runScenario(.init(
            move: .staffHeavySlash, defenderStartX: 3.15, defenderGuarding: true
        ))
        XCTAssertEqual(guarded.resolution, .guardedBlock)
        XCTAssertTrue(guarded.usedSynthesizedGuard)
        XCTAssertFalse(guarded.causedGuardBreak)
        XCTAssertEqual(guarded.damageSettlementCount, 1)
        XCTAssertEqual(guarded.defenderHPDelta, DuelMonkeyKingPhase4.CombatParameters.standard.staffHeavyGuardChip)
        XCTAssertEqual(guarded.defenderKnockbackMeters, DuelMonkeyKingPhase4.synthesizedBlockNetSlideMeters, accuracy: 0.005)
        XCTAssertTrue(guarded.events.contains(where: { $0.detail.contains("rec_monkey_king_mid_block_heavy") }))

        // 4. Pre-active interrupt at boundary tick 43 (1 tick before active tick 44)
        let interrupted = DuelMonkeyKingPhase4.runScenario(.init(
            move: .staffHeavySlash, defenderStartX: 3.15, defenderGuarding: false,
            interruptAtTick60Hz: 43, interruptDamageToAttacker: 85
        ))
        XCTAssertEqual(interrupted.resolution, .interruptedBeforeActive)
        XCTAssertEqual(interrupted.damageSettlementCount, 0)
        XCTAssertEqual(interrupted.defenderHPDelta, 0)
        XCTAssertEqual(interrupted.attackerHPDelta, 85)
    }

    func testAscensionStaffPerch_EvadesLowAttackAndLandsSinglePlungeHit() {
        let res = DuelMonkeyKingPhase4.runScenario(.init(
            move: .ascensionPerchAndPlunge,
            defenderStartX: 3.25,
            defenderGuarding: false,
            incomingStrikeWhilePerched: .init(atPerchTick60Hz: 28, strikeHeightMeters: 0.95, damageToAttacker: 130)
        ))
        XCTAssertTrue(res.evadedLowAttackWhilePerched, "Perched pelvisY=2.123m must cleanly evade ground strike <= 1.25m")
        XCTAssertFalse(res.knockedOffPillarByAntiAir)
        XCTAssertEqual(res.attackerHPDelta, 0, "Evaded ground strike must deal 0 HP to perched Monkey King")
        XCTAssertGreaterThanOrEqual(res.peakAttackerPelvisYMeters, 2.43)
        XCTAssertEqual(res.resolution, .cleanHit)
        XCTAssertEqual(res.damageSettlementCount, 1)
        XCTAssertEqual(res.defenderHPDelta, DuelMonkeyKingPhase4.CombatParameters.standard.ascensionPlungeDamage)
        XCTAssertTrue(res.sfxTriggers.contains(where: { $0.detail.contains("hero_monkey_king_column_switch.wav") }))
    }

    func testAscensionStaffPerch_AntiAirStrikeKnocksOffPillarAndCancelsPlunge() {
        let res = DuelMonkeyKingPhase4.runScenario(.init(
            move: .ascensionPerchAndPlunge,
            defenderStartX: 3.25,
            defenderGuarding: false,
            incomingStrikeWhilePerched: .init(atPerchTick60Hz: 28, strikeHeightMeters: 2.05, damageToAttacker: 145)
        ))
        XCTAssertFalse(res.evadedLowAttackWhilePerched)
        XCTAssertTrue(res.knockedOffPillarByAntiAir)
        XCTAssertEqual(res.resolution, .interruptedOnPillar)
        XCTAssertEqual(res.finalPhase, .interrupted)
        XCTAssertEqual(res.attackerHPDelta, 145)
        XCTAssertEqual(res.damageSettlementCount, 0)
        XCTAssertEqual(res.defenderHPDelta, 0, "Anti-air perch interrupt must cancel plunge with 0 opponent damage")
    }

    func testNoDoubleSettlementAcrossEveryReachableDistance() {
        for cm in stride(from: 180, through: 500, by: 25) {
            let x = Double(cm) / 100.0
            for move in [DuelMonkeyKingPhase4.MoveKind.staffHeavySlash, .ascensionPerchAndPlunge] {
                let res = DuelMonkeyKingPhase4.runScenario(.init(
                    move: move, defenderStartX: x, defenderGuarding: false
                ))
                XCTAssertLessThanOrEqual(res.damageSettlementCount, 1,
                                         "Double settlement for \(move) at x=\(x)m")
            }
        }
    }
}
