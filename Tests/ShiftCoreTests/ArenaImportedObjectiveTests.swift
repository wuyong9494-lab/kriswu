import XCTest
@testable import ShiftCore

final class ArenaImportedObjectiveTests: XCTestCase {
    func testGemCountdownRequiresContinuousUncontestedLead() throws {
        var state = try ArenaGemGrabObjectiveState(target: 10, holdDuration: 15, matchDuration: 210)
        XCTAssertTrue(state.update(delta: 0, elapsed: 20, heldByTeam: [10, 9]))
        XCTAssertEqual(state.countdownTeam, 0)
        XCTAssertEqual(state.countdownRemaining, 15)
        state.update(delta: 5, elapsed: 25, heldByTeam: [10, 9])
        XCTAssertEqual(state.countdownRemaining, 10)
        state.update(delta: 1, elapsed: 26, heldByTeam: [10, 10])
        XCTAssertNil(state.countdownTeam)
        state.update(delta: 1, elapsed: 27, heldByTeam: [9, 10])
        XCTAssertEqual(state.countdownTeam, 1)
        XCTAssertEqual(state.countdownRemaining, 15)
        state.update(delta: 15, elapsed: 42, heldByTeam: [9, 10])
        XCTAssertEqual(state.result, .winner(team: 1))
        XCTAssertFalse(state.update(delta: 1, elapsed: 43, heldByTeam: [12, 0]))
        XCTAssertEqual(state.result, .winner(team: 1))
    }

    func testGemTimeLimitUsesHeldTotalsAndRejectsInvalidTime() throws {
        var state = try ArenaGemGrabObjectiveState(target: 10, holdDuration: 15, matchDuration: 210)
        XCTAssertFalse(state.update(delta: .nan, elapsed: 20, heldByTeam: [10, 0]))
        XCTAssertFalse(state.update(delta: 1, elapsed: 20, heldByTeam: [10, -1]))
        state.update(delta: 1, elapsed: 210, heldByTeam: [5, 7])
        XCTAssertEqual(state.result, .winner(team: 1))
    }

    func testBlueStarIsUniqueAndTransfersWithoutAnExtraPickupPoint() throws {
        var state = try ArenaBountyObjectiveState(teams: [0, 0, 1, 1], scoreGoal: 20, startingBounty: 2, maximumBounty: 7)
        XCTAssertTrue(state.claimBlueStar(by: 0))
        XCTAssertFalse(state.claimBlueStar(by: 2))
        XCTAssertEqual(state.score, [1, 0])
        let change = state.recordElimination(victim: 0, attacker: 2)
        XCTAssertEqual(change?.awardedStars, 2)
        XCTAssertEqual(change?.transferredBlueStar, true)
        XCTAssertEqual(state.score, [1, 2])
        XCTAssertEqual(state.blueStarCarrier, 2)
        XCTAssertEqual(state.bounties, [2, 2, 3, 2])
        XCTAssertNil(state.recordElimination(victim: 3, attacker: 2), "Team kills cannot award a bounty.")
        XCTAssertNil(state.recordElimination(victim: Int.max, attacker: 0))
    }

    func testBountyGoalEndsImmediatelyAndUnclaimedTieDraws() throws {
        var state = try ArenaBountyObjectiveState(teams: [0, 1], scoreGoal: 4, startingBounty: 2, maximumBounty: 7)
        state.recordElimination(victim: 1, attacker: 0)
        state.recordElimination(victim: 1, attacker: 0)
        XCTAssertEqual(state.result, .winner(team: 0))
        XCTAssertNil(state.recordElimination(victim: 0, attacker: 1))
        var tied = try ArenaBountyObjectiveState(teams: [0, 1], scoreGoal: 20, startingBounty: 2, maximumBounty: 7)
        XCTAssertEqual(tied.finishAtTimeLimit(), .draw)
    }

    func testBlueStarHolderWinsTimedTie() throws {
        // Small synthetic bounties make an exact tie without importing game records.
        var state = try ArenaBountyObjectiveState(teams: [0, 1], scoreGoal: 20, startingBounty: 1, maximumBounty: 1)
        state.claimBlueStar(by: 0)
        state.recordElimination(victim: 0, attacker: 1)
        XCTAssertEqual(state.score, [1, 1])
        XCTAssertEqual(state.finishAtTimeLimit(), .winner(team: 1))
    }

    func testOverridesRequireFieldSpecificEvidenceAndCorrectMode() {
        let missing = ArenaImportedMatchRules(matchDuration: 120, evidence: [:])
        XCTAssertFalse(missing.validationProblems(runtimeMode: .bounty).isEmpty)
        let invalid = ArenaImportedMatchRules(respawnDelay: -1, usesBlueStarTieBreak: true,
                                             evidence: ["respawnDelay": "fixture", "usesBlueStarTieBreak": "fixture"])
        XCTAssertEqual(invalid.validationProblems(runtimeMode: .stars).count, 2)
    }

    func testHotZonesCaptureIndependentlyForBothTeamsAndRequireEveryZone() throws {
        let zones = [ArenaImportedMap.CaptureZone(id: "west", center: V2(2, 2), radius: 1, evidence: "synthetic"),
                     .init(id: "east", center: V2(8, 2), radius: 1, evidence: "synthetic")]
        var state = try ArenaZoneObjectiveState(zones: zones, captureSeconds: 10)
        state.update(delta: 5, occupants: [.init(team: 0, position: V2(2, 2)), .init(team: 0, position: V2(2, 2)),
                                         .init(team: 1, position: V2(2, 2))])
        XCTAssertEqual(state.teamProgress, [25, 25], "Opponents can capture together; extra teammates do not accelerate.")
        state.update(delta: 10, occupants: [.init(team: 0, position: V2(8, 2))])
        XCTAssertEqual(state.teamProgress, [75, 25])
        XCTAssertNil(state.result, "One completed zone cannot finish a two-zone match.")
        XCTAssertEqual(state.targetZone(for: 0, from: V2(8, 2))?.id, "west")
        state.update(delta: 5, occupants: [.init(team: 0, position: V2(2, 2))])
        XCTAssertEqual(state.result, .winner(team: 0))
        XCTAssertNil(state.targetZone(for: 0, from: .zero))
    }

    func testHotZoneTimeLimitAndSimultaneousCompletionDoNotPickArrayOrder() throws {
        let zone = ArenaImportedMap.CaptureZone(id: "one", center: V2(2, 2), radius: 1, evidence: "synthetic")
        var simultaneous = try ArenaZoneObjectiveState(zones: [zone], captureSeconds: 10)
        XCTAssertFalse(simultaneous.update(delta: .nan, occupants: []))
        simultaneous.update(delta: 10, occupants: [.init(team: 1, position: V2(2, 2)), .init(team: 0, position: V2(2, 2))])
        XCTAssertEqual(simultaneous.result, .draw)
        var timed = try ArenaZoneObjectiveState(zones: [zone], captureSeconds: 10)
        timed.update(delta: 2, occupants: [.init(team: 1, position: V2(2, 2))])
        XCTAssertEqual(timed.finishAtTimeLimit(), .winner(team: 1))
        XCTAssertFalse(timed.update(delta: 10, occupants: [.init(team: 0, position: V2(2, 2))]))
    }

    func testSourceCrateSelectionIsStableUnderReorderingAndPreservesParameters() throws {
        let candidates = (0..<64).map { index in
            ArenaImportedMap.PowerBoxPlacement(cell: .init(index, 2), health: 4300,
                                               collisionRadius: 145.0 / 300, spawnProbability: 0.5, evidence: "synthetic policy")
        }
        let selected = try ArenaImportedRuntimeSelection.powerBoxes(candidates, seed: 99)
        XCTAssertFalse(selected.isEmpty)
        XCTAssertLessThan(selected.count, candidates.count)
        XCTAssertEqual(selected, try ArenaImportedRuntimeSelection.powerBoxes(candidates.reversed(), seed: 99))
        let retained = try ArenaImportedRuntimeSelection.powerBoxes(Array(candidates[0..<10]), seed: 99)
        XCTAssertEqual(retained, selected.filter { $0.cell.x < 10 })
        XCTAssertTrue(selected.allSatisfy { $0.health == 4300 && $0.collisionRadius == 145.0 / 300 })
        var guaranteed = candidates[0]
        guaranteed.spawnProbability = 1
        XCTAssertEqual(try ArenaImportedRuntimeSelection.powerBoxes([guaranteed], seed: 99), [guaranteed])
        guaranteed.spawnProbability = 0
        XCTAssertTrue(try ArenaImportedRuntimeSelection.powerBoxes([guaranteed], seed: 99).isEmpty)
        XCTAssertThrowsError(try ArenaImportedRuntimeSelection.powerBoxes([candidates[0], candidates[0]], seed: 99))
    }
}
