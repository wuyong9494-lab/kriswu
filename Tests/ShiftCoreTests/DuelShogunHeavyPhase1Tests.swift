import XCTest
@testable import ShiftCore

final class DuelShogunHeavyPhase1Tests: XCTestCase {

    func testOriginalSourceTrackIntegrityAndLiveCrossCheck() {
        XCTAssertEqual(DuelShogunHeavyPhase1.sourceFrames.count, 66)
        XCTAssertEqual(DuelShogunHeavyPhase1.simulationTicks60Hz, 131)
        XCTAssertEqual(DuelShogunHeavyPhase1.blockMiddleHeavyDxMeters.count, 41)

        // Verify original w_odati_trail2..4 ribbon extension is strictly > 0 ONLY on source frames 22...25
        let trailActiveFrames = DuelShogunHeavyPhase1.sourceFrames
            .filter { $0.trailLengthCM > 1.0 }
            .map(\.sourceFrame)
        XCTAssertEqual(trailActiveFrames, [22, 23, 24, 25],
                       "Original trail bones must be active exclusively on source frames 22...25 (t60 44...51)")

        // Peak blade-tip velocity must occur at ground-slam frame 25 (~76.07 m/s)
        let peak = DuelShogunHeavyPhase1.sourceFrames.max(by: { $0.tipVelocityMPS < $1.tipVelocityMPS })
        XCTAssertEqual(peak?.sourceFrame, 25)
        XCTAssertGreaterThan(peak?.tipVelocityMPS ?? 0, 75.0)

        // Cross-check shogun_heavy.bytes lunge (+1.919 m) vs live SF4 EV3 ground-plane measurement (+1.98 m)
        let binaryNetLunge = DuelShogunHeavyPhase1.sourceFrames.last!.pelvisX
        XCTAssertEqual(binaryNetLunge, DuelShogunHeavyPhase1.liveEV3UnchargedLungeMeters, accuracy: 0.10)
    }

    func testScenario1_NormalHit_ChargedLiveCalibratedSingleSettlementHitstopAndKnockdown() {
        let result = DuelShogunHeavyPhase1.runScenario(.standard(.normalHit, isCharged: true))

        XCTAssertEqual(result.resolution, .cleanHit)
        XCTAssertEqual(result.finalPhase, .completed)
        XCTAssertTrue(result.causedKnockdown, "Live EV1/EV4 charged clean hit must cause hard knockdown")
        XCTAssertEqual(result.startupTicksObserved, 44)
        XCTAssertEqual(result.activeTicksObserved, 8)
        XCTAssertEqual(result.recoveryTicksObserved, 79)

        let contact = try! XCTUnwrap(result.contactTick60Hz)
        XCTAssertTrue((44...51).contains(contact), "Expected contact inside t60 44...51, got \(contact)")

        // Single settlement invariant
        XCTAssertEqual(result.damageSettlementCount, 1)
        XCTAssertEqual(result.defenderHPDelta, 372, "Scaled from live EV1 921/7177 * 2900 = 372")
        XCTAssertEqual(result.attackerHPDelta, 0)

        // Live-calibrated hitstop (18t) and knockdown launch (2.15m)
        XCTAssertEqual(result.hitStopTicksApplied, 18)
        XCTAssertEqual(result.defenderKnockbackMeters, 2.15, accuracy: 0.01)
        XCTAssertEqual(result.trailActiveTickRange, 44...51)
        XCTAssertTrue(result.sfxTriggers.contains(where: { $0.detail.contains("sfx_Shogun_blade_hit.wav") }))
        XCTAssertTrue(result.vfxTriggers.contains(where: { $0.detail.contains("fx_shogun_heavy_impact(pelvis)") }))
    }

    func testScenario2_Whiff_ZeroDamageZeroHitstopZeroKnockback() {
        let result = DuelShogunHeavyPhase1.runScenario(.standard(.whiff))

        XCTAssertEqual(result.resolution, .whiffed)
        XCTAssertEqual(result.finalPhase, .completed)
        XCTAssertFalse(result.causedKnockdown)
        XCTAssertNil(result.contactTick60Hz)
        XCTAssertEqual(result.damageSettlementCount, 0)
        XCTAssertEqual(result.defenderHPDelta, 0)
        XCTAssertEqual(result.attackerHPDelta, 0)
        XCTAssertEqual(result.hitStopTicksApplied, 0)
        XCTAssertEqual(result.defenderKnockbackMeters, 0.0, accuracy: 1e-6)
        XCTAssertTrue(result.sfxTriggers.contains(where: { $0.detail.contains("sfx_wpn_ODT_scrape_01.wav") }))
        XCTAssertTrue(result.vfxTriggers.contains(where: { $0.detail.contains("fx_shogun_heavy_impact_miss") }))
    }

    func testScenario3A_UnchargedGuard_LiveEV3NoGuardBreakHighChipAndOriginalBlockSlide() {
        let result = DuelShogunHeavyPhase1.runScenario(.standard(.guarded, isCharged: false))

        XCTAssertEqual(result.resolution, .guardedBlock)
        XCTAssertEqual(result.finalPhase, .completed)
        XCTAssertFalse(result.causedKnockdown, "Live EV3 proves uncharged heavy does NOT break guard or knock down")
        let contact = try! XCTUnwrap(result.contactTick60Hz)
        XCTAssertTrue((44...51).contains(contact))
        XCTAssertEqual(result.damageSettlementCount, 1)

        // Live EV3: 313 / 7177 = 4.361% max HP -> 126 / 2900; 4t micro-blockstop
        XCTAssertEqual(result.defenderHPDelta, 126)
        XCTAssertEqual(result.hitStopTicksApplied, 4)
        XCTAssertEqual(result.defenderKnockbackMeters, DuelShogunHeavyPhase1.blockNetSlideMeters, accuracy: 0.005)
    }

    func testScenario3B_ChargedGuard_LiveEV2AlsoBlockedWithoutGuardBreakAt60PercentChip() {
        let result = DuelShogunHeavyPhase1.runScenario(.standard(.guarded, isCharged: true))

        XCTAssertEqual(result.resolution, .guardedBlock)
        XCTAssertFalse(result.causedKnockdown, "Live EV2 proves even charged heavy (攻击已充能!) is blocked without guard break")
        XCTAssertEqual(result.damageSettlementCount, 1)
        // Live EV2: 557 / 7177 = 7.761% max HP -> 225 / 2900 (~60.5% of charged clean hit 372); 5t blockstop
        XCTAssertEqual(result.defenderHPDelta, 225)
        XCTAssertEqual(result.hitStopTicksApplied, 5)
        XCTAssertEqual(result.defenderKnockbackMeters, DuelShogunHeavyPhase1.blockNetSlideMeters, accuracy: 0.005)
    }

    func testScenario4_EarlyInterruptBeforeActive_ZeroDamageToOpponentAndBoundaryAtTick43() {
        let midStartup = DuelShogunHeavyPhase1.runScenario(.standard(.earlyInterrupt))
        XCTAssertEqual(midStartup.resolution, .interruptedBeforeActive)
        XCTAssertEqual(midStartup.finalPhase, .interrupted)
        XCTAssertFalse(midStartup.causedKnockdown)
        XCTAssertEqual(midStartup.activeTicksObserved, 0)
        XCTAssertNil(midStartup.contactTick60Hz)
        XCTAssertEqual(midStartup.damageSettlementCount, 0)
        XCTAssertEqual(midStartup.defenderHPDelta, 0)
        XCTAssertEqual(midStartup.attackerHPDelta, 85)
        XCTAssertEqual(midStartup.defenderKnockbackMeters, 0.0, accuracy: 1e-6)

        // Last-possible startup boundary tick 43 (1 tick before active tick 44) at hit distance 2.85m
        let lastStartup = DuelShogunHeavyPhase1.runScenario(.init(
            kind: .earlyInterrupt,
            defenderStartX: 2.85,
            defenderGuarding: false,
            isCharged: true,
            interruptAtTick60Hz: 43,
            interruptDamageToAttacker: 85,
            parameters: .phase1LiveCalibrated
        ))
        XCTAssertEqual(lastStartup.resolution, .interruptedBeforeActive)
        XCTAssertEqual(lastStartup.activeTicksObserved, 0)
        XCTAssertEqual(lastStartup.damageSettlementCount, 0)
        XCTAssertEqual(lastStartup.defenderHPDelta, 0)
    }

    func testNoDoubleSettlementAcrossEveryReachableDistance() {
        for cm in stride(from: 160, through: 400, by: 25) {
            let x = Double(cm) / 100.0
            let res = DuelShogunHeavyPhase1.runScenario(.init(
                kind: .normalHit,
                defenderStartX: x,
                defenderGuarding: false,
                isCharged: true,
                interruptAtTick60Hz: nil,
                interruptDamageToAttacker: 0,
                parameters: .phase1LiveCalibrated
            ))
            XCTAssertLessThanOrEqual(res.damageSettlementCount, 1,
                                     "Double settlement detected at defenderX=\(x)m: count=\(res.damageSettlementCount)")
            if res.damageSettlementCount == 0 {
                XCTAssertEqual(res.defenderHPDelta, 0)
            } else {
                XCTAssertEqual(res.defenderHPDelta, DuelShogunHeavyPhase1.CombatParameters.phase1LiveCalibrated.chargedCleanHitDamage)
            }
        }
    }
}
