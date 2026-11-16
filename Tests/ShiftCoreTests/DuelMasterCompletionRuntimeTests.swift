import XCTest
@testable import ShiftCore

final class DuelMasterCompletionRuntimeTests: XCTestCase {
    func testMasterCompletionAllModules() {
        var serpent = DuelSerpentMasterRuntime(level: 6, initialBloom: 0.35, targetShadowEnergy: 0.25)
        XCTAssertTrue(serpent.witherAuraActive)
        serpent.triggerRoundFightStartFifthPoison()
        for _ in 0..<60 { _ = serpent.stepTick(comDistanceMillimeters: 220.0) }
        XCTAssertEqual(serpent.witherStacks, 1)
        serpent.updateBloom(1.0)
        XCTAssertEqual(serpent.releaseFifthBloomIndependentModel(targetInvincible: false), 0.66 * 1.25, accuracy: 1e-6)
        serpent.activateUnarmedPoisonBuff()
        XCTAssertTrue(serpent.queueVictimFallReactionOnAnimationEnd(atUninterruptEndOrIdleTransition: true, deterministicRollPercent: 20, delayedDamage: 0.09))
        serpent.activateShadowPoisonImpact(targetCurrentlyInShadowForm: true)
        var fallTotal = 0.0
        var terminated = false
        for _ in 0..<30 {
            let step = serpent.stepTick(comDistanceMillimeters: 180.0)
            fallTotal += step.fallDamage
            if step.shadowTerminated { terminated = true }
        }
        XCTAssertEqual(fallTotal, 0.09, accuracy: 1e-6)
        XCTAssertTrue(terminated)

        let erlangSample = DuelErlangMasterRuntime.sampleSignedStretch(factor: -1.35, speed: 2.0, hideProgress: 0.5)
        XCTAssertLessThan(erlangSample.stretch, 0.0)
        XCTAssertEqual(erlangSample.opacity, 0.75, accuracy: 1e-6)

        XCTAssertEqual(DuelXuXiaoMasterRuntime.fiveEquipmentCandidates.count, 5)
        XCTAssertEqual(DuelXuXiaoMasterRuntime.totalMotionContracts, 58)

        let tv = DuelExperienceMasterCoordinator.televisionDynamicScale(casting: true, recentFrameTimeMS: 17.5)
        XCTAssertEqual(tv.msaa, 1)
        XCTAssertLessThan(tv.scale, 1.0)
        let stick = DuelExperienceMasterCoordinator.normalizeThumbstick(x: 0.09, y: -0.11, deadzone: 0.18)
        XCTAssertEqual(stick.dx, 0)
        XCTAssertEqual(stick.dy, 0)

        XCTAssertEqual(DuelGame.Hero.ember.canonicalSetCode, "H17_TRIAD")
        XCTAssertEqual(DuelGame.Hero.gale.canonicalSetCode, "D20_XUXIAO_FOUNDER")
        XCTAssertEqual(DuelGame.Hero.liu.canonicalSetCode, "D13_SERPENT")
        XCTAssertEqual(DuelGame.Hero.wuYong.canonicalSetCode, "D15_ERLANG")

        guard let serpentState = DuelSerpentState(level: 4, raidDamageAmplifier: 1.0) else {
            XCTFail("Expected valid DuelSerpentState")
            return
        }
        let serpentContinuation = serpentState.makeMasterContinuationRuntime()
        XCTAssertFalse(serpentContinuation.witherAuraActive)
        XCTAssertEqual(serpentContinuation.witherStacks, 0)

        let erlangState = DuelErlangFightState(level: 8, seed: 1)
        XCTAssertEqual(erlangState.swordHideFadeOpacity, 1.0, accuracy: 1e-6)
    }
}
