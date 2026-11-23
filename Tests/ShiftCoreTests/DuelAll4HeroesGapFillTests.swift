import XCTest
@testable import ShiftCore

final class DuelAll4HeroesGapFillTests: XCTestCase {

    func testAll4HeroesCompletedWithZeroBlockingGapsAndExactAuditTotals() {
        let profiles = DuelAll4HeroesGapFillRegistry.allHeroProfiles
        XCTAssertEqual(profiles.count, 4)
        XCTAssertEqual(Set(profiles.map(\.heroID)), [
            "wuYong_shogun",
            "liuQuanwei_emperor",
            "xuXiao_legionKing",
            "sunDeng_monkeyKing",
        ])

        // Exact cross-check against read-only audit (`01872f0`): 278 local .bin bundles, 474 unresolved core CAB PPtrs replaced
        XCTAssertEqual(DuelAll4HeroesGapFillRegistry.totalSourceBundlesAudited, 278)
        XCTAssertEqual(DuelAll4HeroesGapFillRegistry.totalMissingExternalCABRefsReplaced, 474)
        XCTAssertEqual(DuelAll4HeroesGapFillRegistry.totalRemainingBlockingGaps, 0)

        for p in profiles {
            XCTAssertTrue(p.hasRealBaseModelAnd1KPBR, "\(p.heroID) must retain real base model & 1K PBR textures")
            XCTAssertTrue(p.hasRealOriginalSFX, "\(p.heroID) must retain real extracted original WAV SFX")
            XCTAssertTrue(p.hasVerifiedGuardTrack, "\(p.heroID) must have a complete verified guard state")
            XCTAssertFalse(p.completedGapFillIDs.isEmpty, "\(p.heroID) must explicitly record independent gap-fills")
            XCTAssertEqual(p.remainingBlockingGaps, 0, "\(p.heroID) has unresolved blocking gaps")
        }

        // Strict provenance honesty: Monkey King & Emperor mid-guards MUST be marked independentRecreation (never misrepresented as original)
        let emperor = profiles.first(where: { $0.heroID == "liuQuanwei_emperor" })!
        let monkey = profiles.first(where: { $0.heroID == "sunDeng_monkeyKing" })!
        let shogun = profiles.first(where: { $0.heroID == "wuYong_shogun" })!
        let kotl = profiles.first(where: { $0.heroID == "xuXiao_legionKing" })!
        XCTAssertEqual(shogun.guardTrackProvenance, .originalBinaryMeasured)
        XCTAssertEqual(kotl.guardTrackProvenance, .originalBinaryMeasured)
        XCTAssertEqual(emperor.guardTrackProvenance, .independentRecreation)
        XCTAssertEqual(monkey.guardTrackProvenance, .independentRecreation)
    }

    func testEndToEndFourHeroCombatSanitySmoke() {
        let s1 = DuelShogunHeavyPhase1.runScenario(.standard(.normalHit))
        let s2 = DuelEmperorPhase2.runScenario(.init(move: .shadowTransformation, initialForm: .human, defenderStartX: 1.85, defenderGuarding: false))
        let s3 = DuelLegionKingPhase3.runScenario(.init(move: .shadowRangedChain, defenderStartX: 3.30, defenderGuarding: false))
        let s4 = DuelMonkeyKingPhase4.runScenario(.init(move: .ascensionPerchAndPlunge, defenderStartX: 3.25, defenderGuarding: false,
                                                        incomingStrikeWhilePerched: .init(atPerchTick60Hz: 28, strikeHeightMeters: 0.95, damageToAttacker: 130)))

        XCTAssertEqual(s1.resolution, .cleanHit)
        XCTAssertEqual(s2.finalForm, .shadowBeast)
        XCTAssertTrue(s3.chainSnaggedAndPulled)
        XCTAssertTrue(s4.evadedLowAttackWhilePerched)
        XCTAssertEqual(s4.resolution, .cleanHit)
    }
}
