import XCTest
@testable import ShiftCore

final class DuelSourceThrowFightTests: XCTestCase {
    typealias F = DuelSourceThrowFixture

    func testBackThrowStartsAtZeroAndDamagesOnceAt54ThenReleasesIndependently() throws {
        var fight = try F.fight()
        fight.step(.init(weaponCommand: .weaponBack), opponent: .init(guardHeld: true))
        XCTAssertEqual(fight.sourceThrow(0)?.variant, .back)
        XCTAssertEqual(fight.sourceThrow(0)?.tick, 0)
        XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 0)
        XCTAssertEqual(Set(fight.sourceMotionSamples.map(\.owner)), [0, 1],
            "Both real paired actors publish their own source sound intervals")
        F.advance(&fight, 53); XCTAssertEqual(fight.fighters[1].health, 1000)
        F.advance(&fight, 1); XCTAssertEqual(fight.fighters[1].health, 900)
        XCTAssertEqual(fight.landedHits, [1, 0]); XCTAssertEqual(fight.hitStop, 0)
        F.advance(&fight, 20)
        XCTAssertNil(fight.sourceThrow(1)); XCTAssertNotNil(fight.sourceThrow(0))
        XCTAssertEqual(fight.sourceThrowDisabledRemaining(0), 105)
        F.advance(&fight, 18)
        XCTAssertNil(fight.sourceThrow(0)); XCTAssertEqual(fight.landedHits, [1, 0])
        XCTAssertEqual(fight.sourceThrowDisabledRemaining(0), 87)
    }

    func testForwardThrowUsesDifferentFacingAndMarker92() throws {
        var fight = try F.fight()
        fight.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
        XCTAssertEqual(fight.sourceThrow(0)?.variant, .forward)
        XCTAssertEqual(fight.fighters.map(\.facing), [-1, 1])
        F.advance(&fight, 91); XCTAssertEqual(fight.fighters[1].health, 1000)
        F.advance(&fight, 1); XCTAssertEqual(fight.fighters[1].health, 900)
    }

    func testOutOfRangeLeavesTargetFreeAndDoesNotInventMissAnimation() throws {
        var fight = try F.fight(distance: 1400)
        fight.step(.init(weaponCommand: .weaponBack), opponent: .neutral)
        XCTAssertNil(fight.sourceThrow(0)); XCTAssertNil(fight.sourceThrow(1))
        XCTAssertNotEqual(fight.fighters[0].weaponPose?.clip, "synthetic_source_backActive")
        XCTAssertEqual(fight.fighters[1].health, 1000)
    }

    func testThrowRangeUsesBothMassCentresRatherThanActorOrigins() throws {
        var accepted = try F.fight(distance: 1200, com: 0.2)
        XCTAssertEqual(try XCTUnwrap(accepted.sourceCenterOfMass(0)).x, 4.2, accuracy: 0.000001)
        accepted.step(.init(weaponCommand: .weaponBack), opponent: .neutral)
        XCTAssertNotNil(accepted.sourceThrow(0), "COM separation is 800 mm despite actor origins 1,200 mm apart")
        var rejected = try F.fight(distance: 800, com: -0.2)
        rejected.step(.init(weaponCommand: .weaponBack), opponent: .neutral)
        XCTAssertNil(rejected.sourceThrow(0), "COM separation is 1,200 mm despite actor origins 800 mm apart")
    }

    func testRoundingTheTwoCOMsIndividuallyCannotCreateAnIllegalGrab() throws {
        var fight = try F.fight(distance: 939, com: 0.00075, liuCOM: -0.0002)
        let a = try XCTUnwrap(fight.sourceCenterOfMass(0)).x * 1000
        let b = try XCTUnwrap(fight.sourceCenterOfMass(1)).x * 1000
        XCTAssertEqual(b - a, 938.45, accuracy: 0.0000001)
        XCTAssertEqual(Int(b.rounded()) - Int(a.rounded()), 938, "The old early rounding would incorrectly grab")
        fight.step(.init(weaponCommand: .weaponBack), opponent: .neutral)
        XCTAssertNil(fight.sourceThrow(0))
    }

    func testPanguSourceEscapeSwapsDamageOwnerAndRunsNormalPreHitAt98() throws {
        var fight = try F.fight(pangu: true)
        fight.step(.init(weaponCommand: .weaponBack), opponent: .neutral)
        XCTAssertEqual(fight.sourceThrow(0)?.variant, .panguEscape)
        XCTAssertEqual(fight.fighters[1].weaponPose?.clip, "synthetic_source_panguActive")
        F.advance(&fight, 97); XCTAssertEqual(fight.fighters.map(\.health), [1000, 1000])
        F.advance(&fight, 1)
        XCTAssertEqual(fight.landedHits, [0, 1]); XCTAssertEqual(fight.fighters[1].health, 1000)
        XCTAssertLessThan(fight.fighters[0].health, 1000)
        XCTAssertEqual(fight.panguState(1)?.combo, 1)
        F.advance(&fight, 14)
        XCTAssertNil(fight.sourceThrow(0)); XCTAssertNotNil(fight.sourceThrow(1))
    }

    func testLegacyHammerIdentityDoesNotAcquirePanguEscapeFromSharedClips() throws {
        var fight = try F.fight(pangu: false)
        XCTAssertEqual(fight.profiles[1].id, "liu_hammers")
        fight.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
        XCTAssertEqual(fight.sourceThrow(0)?.variant, .forward)
        XCTAssertNil(fight.panguState(1))
    }

    func testSimultaneousSourceInputsUseOneDeterministicPairWithBothPossibleOwners() throws {
        var owners = Set<Int>()
        for seed in UInt64(1)...16 {
            var a = try F.fight(seed: seed), b = try F.fight(seed: seed)
            let input = DuelGame.Input(weaponCommand: .weaponBack)
            a.step(input, opponent: input); b.step(input, opponent: input)
            let state = try XCTUnwrap(a.sourceThrow(0))
            owners.insert(state.initiator)
            XCTAssertEqual(a.sourceThrow(0), a.sourceThrow(1))
            XCTAssertEqual(try DuelReplayStateEncoding.encode(a), try DuelReplayStateEncoding.encode(b))
        }
        XCTAssertEqual(owners, [0, 1])
    }

    func testMirroredPairKeepsItsRootOffsetsWithinTheArena() throws {
        for facing in [-1, 1] {
            var fight = try F.fight(facing: facing, firstX: facing > 0 ? 4000 : 6000)
            fight.step(.init(weaponCommand: .weaponBack), opponent: .neutral)
            let state = try XCTUnwrap(fight.sourceThrow(0))
            F.advance(&fight, 12)
            XCTAssertEqual(fight.fighters[0].x, state.origins[0] + 12 * facing)
            XCTAssertEqual(fight.fighters[1].x, state.origins[1] - 12 * facing)
            XCTAssertTrue(fight.fighters.allSatisfy { (DuelGame.leftWall...DuelGame.rightWall).contains($0.x) })
        }
    }
}
