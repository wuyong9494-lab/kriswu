import XCTest
@testable import ShiftCore

final class DuelShogunHeavyPhase1Tests: XCTestCase {

    func testOriginalSourceTrackIntegrityAndActiveWindowDerivation() {
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
    }

    func testScenario1_NormalHit_SingleSettlementHitstopKnockbackAndEffects() {
        let result = DuelShogunHeavyPhase1.runScenario(.standard(.normalHit))

        XCTAssertEqual(result.resolution, .cleanHit)
        XCTAssertEqual(result.finalPhase, .completed)
        XCTAssertEqual(result.startupTicksObserved, 44)
        XCTAssertEqual(result.activeTicksObserved, 8)
        XCTAssertEqual(result.recoveryTicksObserved, 79)

        // Contact must occur strictly within active window [44, 51]
        let contact = try! XCTUnwrap(result.contactTick60Hz)
        XCTAssertTrue((44...51).contains(contact), "Expected contact inside t60 44...51, got \(contact)")

        // Hard rule: same damage segment must NEVER double-settle across the 8 active ticks!
        XCTAssertEqual(result.damageSettlementCount, 1, "Single heavy slash segment must settle damage exactly once")
        XCTAssertEqual(result.defenderHPDelta, DuelShogunHeavyPhase1.CombatParameters.phase1Default.baseDamage)
        XCTAssertEqual(result.attackerHPDelta, 0)

        // Hitstop, knockback, trail, VFX, and original SFX alignment
        XCTAssertEqual(result.hitStopTicksApplied, DuelShogunHeavyPhase1.CombatParameters.phase1Default.hitStopTicks60Hz)
        XCTAssertGreaterThan(result.defenderKnockbackMeters, 1.50)
        XCTAssertEqual(result.trailActiveTickRange, 44...51)
        XCTAssertTrue(result.sfxTriggers.contains(where: { $0.detail.contains("sfx_Shogun_blade_hit.wav") }))
        XCTAssertTrue(result.vfxTriggers.contains(where: { $0.detail.contains("fx_shogun_heavy_impact(pelvis)") }))
    }

    func testScenario2_Whiff_ZeroDamageZeroHitstopZeroKnockback() {
        let result = DuelShogunHeavyPhase1.runScenario(.standard(.whiff))

        XCTAssertEqual(result.resolution, .whiffed)
        XCTAssertEqual(result.finalPhase, .completed)
        XCTAssertNil(result.contactTick60Hz)
        XCTAssertEqual(result.damageSettlementCount, 0, "Whiff must never settle damage")
        XCTAssertEqual(result.defenderHPDelta, 0, "Whiff must deduct 0 HP")
        XCTAssertEqual(result.attackerHPDelta, 0)
        XCTAssertEqual(result.hitStopTicksApplied, 0, "Whiff must apply 0 hitstop")
        XCTAssertEqual(result.defenderKnockbackMeters, 0.0, accuracy: 1e-6, "Whiff must apply 0 knockback")
        XCTAssertTrue(result.sfxTriggers.contains(where: { $0.detail.contains("sfx_wpn_ODT_scrape_01.wav") }))
        XCTAssertTrue(result.vfxTriggers.contains(where: { $0.detail.contains("fx_shogun_heavy_impact_miss") }))
    }

    func testScenario3_Guard_SingleGuardedSettlementAndOriginalBlockSlide() {
        let result = DuelShogunHeavyPhase1.runScenario(.standard(.guarded))

        XCTAssertEqual(result.resolution, .guardedBlock)
        XCTAssertEqual(result.finalPhase, .completed)
        let contact = try! XCTUnwrap(result.contactTick60Hz)
        XCTAssertTrue((44...51).contains(contact))
        XCTAssertEqual(result.damageSettlementCount, 1, "Guarded heavy slash must settle exactly once")

        // Chip damage under recreatedBlockWithChip (explicitly tagged unconfirmed in report)
        let expectedChip = (DuelShogunHeavyPhase1.CombatParameters.phase1Default.baseDamage *
                            DuelShogunHeavyPhase1.CombatParameters.phase1Default.chipDamageBps) / 10000
        XCTAssertEqual(result.defenderHPDelta, expectedChip)
        XCTAssertLessThan(result.defenderHPDelta, DuelShogunHeavyPhase1.CombatParameters.phase1Default.baseDamage)
        XCTAssertEqual(result.hitStopTicksApplied, DuelShogunHeavyPhase1.CombatParameters.phase1Default.blockHitStopTicks60Hz)

        // Block slide must match exact measured b_shogun_middle_heavy.bytes net displacement (~1.2791 m)
        XCTAssertEqual(result.defenderKnockbackMeters, DuelShogunHeavyPhase1.blockNetSlideMeters, accuracy: 0.005)
    }

    func testScenario4_EarlyInterruptBeforeActive_ZeroDamageToOpponentAndBoundaryAtTick43() {
        // Case 4A: Standard interrupt at startup tick 24 (source frame 12)
        let midStartup = DuelShogunHeavyPhase1.runScenario(.standard(.earlyInterrupt))
        XCTAssertEqual(midStartup.resolution, .interruptedBeforeActive)
        XCTAssertEqual(midStartup.finalPhase, .interrupted)
        XCTAssertEqual(midStartup.activeTicksObserved, 0, "Interrupted heavy must never enter active window")
        XCTAssertNil(midStartup.contactTick60Hz)
        XCTAssertEqual(midStartup.damageSettlementCount, 0)
        XCTAssertEqual(midStartup.defenderHPDelta, 0, "Pre-active interrupt must deduct 0 HP from opponent")
        XCTAssertEqual(midStartup.attackerHPDelta, 85)
        XCTAssertEqual(midStartup.defenderKnockbackMeters, 0.0, accuracy: 1e-6)

        // Case 4B: Last-possible startup boundary tick 43 (1 tick BEFORE active tick 44!) even at close hit distance
        let lastStartup = DuelShogunHeavyPhase1.runScenario(.init(
            kind: .earlyInterrupt,
            defenderStartX: 2.85,
            defenderGuarding: false,
            interruptAtTick60Hz: 43,
            interruptDamageToAttacker: 85,
            parameters: .phase1Default
        ))
        XCTAssertEqual(lastStartup.resolution, .interruptedBeforeActive)
        XCTAssertEqual(lastStartup.activeTicksObserved, 0)
        XCTAssertEqual(lastStartup.damageSettlementCount, 0)
        XCTAssertEqual(lastStartup.defenderHPDelta, 0, "Interrupt at boundary tick 43 must still prevent heavy damage")
    }

    func testNoDoubleSettlementAcrossEveryReachableDistance() {
        // Sweep defender across the entire reachable blade arc [1.60m ... 4.00m]
        for cm in stride(from: 160, through: 400, by: 25) {
            let x = Double(cm) / 100.0
            let res = DuelShogunHeavyPhase1.runScenario(.init(
                kind: .normalHit,
                defenderStartX: x,
                defenderGuarding: false,
                interruptAtTick60Hz: nil,
                interruptDamageToAttacker: 0,
                parameters: .phase1Default
            ))
            XCTAssertLessThanOrEqual(res.damageSettlementCount, 1,
                                     "Double settlement detected at defenderX=\(x)m: count=\(res.damageSettlementCount)")
            if res.damageSettlementCount == 0 {
                XCTAssertEqual(res.defenderHPDelta, 0)
            } else {
                XCTAssertEqual(res.defenderHPDelta, DuelShogunHeavyPhase1.CombatParameters.phase1Default.baseDamage)
            }
        }
    }
}
