import XCTest
@testable import ShiftCore

final class StarRailTests: XCTestCase {
    private func game(_ id: Int = 1) -> StarRail.Game { .init(stage: StarRail.stage(id)!) }
    private func perform(_ actions: [StarRail.Action], on game: inout StarRail.Game,
                         file: StaticString = #filePath, line: UInt = #line) {
        for action in actions { XCTAssertTrue(game.perform(action), "Rejected \(action)", file: file, line: line) }
    }
    private func win(_ id: Int) throws -> StarRail.Game {
        var result = game(id)
        switch StarRailSolver.solve(result, nodeLimit: 300_000, maxShifts: result.stage.plannedMoves, maxPeak: result.stage.targetPeak) {
        case .solved(let actions, _): perform(actions, on: &result)
        case .budgetExceeded(let nodes): XCTFail("Stage \(id) exceeded solver budget: \(nodes)")
        case .noPathWithinConstraints(let nodes): XCTFail("Stage \(id) has no three-star route: \(nodes)")
        }
        XCTAssertEqual(result.status, .won)
        XCTAssertEqual(result.stars, 3)
        return result
    }

    func testSixAuthoredStagesHaveBalancedKindsAndDifferentLessons() {
        XCTAssertEqual(StarRail.stages.map(\.id), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(Set(StarRail.stages.map(\.lesson)).count, 6)
        XCTAssertEqual(StarRail.stages.map(\.requiredArrivals), [2, 3, 2, 3, 11, 15])
        for stage in StarRail.stages {
            XCTAssertTrue(Dictionary(grouping: stage.cards, by: \.kind).values.allSatisfy { $0.count.isMultiple(of: 3) })
            let g = game(stage.id)
            for pose in 0..<(1 << stage.rails.count) {
                var state = g.state
                for rail in stage.rails { state.positions[rail.id] = (pose >> rail.id) & 1 }
                for card in stage.cards {
                    let p = g.point(card, in: state)
                    XCTAssertGreaterThanOrEqual(p.x, 0); XCTAssertGreaterThanOrEqual(p.y, 0)
                    XCTAssertLessThanOrEqual(p.x + 4, stage.width); XCTAssertLessThanOrEqual(p.y + 4, stage.height)
                }
            }
        }
    }

    func testEveryStageHasIndependentThreeStarSolutionAndReplayAtEveryStep() throws {
        var save = StarRail.Save()
        for stage in StarRail.stages {
            let won = try win(stage.id)
            var replay = game(stage.id)
            for action in won.actions {
                let before = replay
                XCTAssertTrue(replay.perform(action))
                let decoded = try JSONDecoder().decode(StarRail.Game.Archive.self, from: JSONEncoder().encode(replay.archive))
                XCTAssertEqual(StarRail.Game(archive: decoded), replay)
                XCTAssertTrue(replay.undo()); XCTAssertEqual(replay, before)
                XCTAssertTrue(replay.perform(action))
                XCTAssertTrue((0...2).contains(replay.state.energy))
                XCTAssertEqual(replay.state.remaining.nonzeroBitCount + replay.state.tray.count + replay.state.matches * 3, stage.cards.count)
                let remaining = replay.board(in: replay.state)
                for a in remaining {
                    for b in remaining where a.id < b.id && a.z == b.z {
                        XCTAssertFalse(replay.overlaps(a, b, in: replay.state), "Same-layer collision after \(action)")
                    }
                }
            }
            XCTAssertTrue(save.keep(won))
            XCTAssertTrue(save.isValid)
            XCTAssertEqual(StarRail.Save(data: try XCTUnwrap(save.encoded())), save)
        }
        XCTAssertEqual(save.progress.totalStars, 18)
    }

    func testPreviewDoesNotSpendEnergyOrAlterHistoryAndMatchesRealOcclusion() throws {
        var g = game()
        let original = g
        let blocked = try XCTUnwrap(g.preview(0, in: g.state))
        XCTAssertFalse(blocked.canMove)
        XCTAssertEqual(blocked.revealed, [3, 4]); XCTAssertEqual(blocked.covered, [5])
        XCTAssertFalse(g.perform(.shift(0))); XCTAssertEqual(g, original)
        perform([.pick(0), .pick(1), .pick(2)], on: &g)
        let before = g
        let preview = try XCTUnwrap(g.preview(0, in: g.state))
        XCTAssertTrue(preview.canMove); XCTAssertEqual(g, before)
        XCTAssertTrue(g.perform(.shift(0)))
        XCTAssertEqual(g.freeIDs(in: g.state), g.freeIDs(in: preview.proposed))
        XCTAssertEqual(g.state.energy, 0); XCTAssertEqual(g.state.positions, [1])
        XCTAssertEqual(g.state.arrivals, 2)
        XCTAssertFalse(g.perform(.pick(5)))
        XCTAssertTrue(g.undo()); XCTAssertEqual(g, before)
    }

    func testSameLayerTerminalMustBeVacatedFirst() {
        let g = game(5)
        var charged = g.state; charged.energy = 2 // Isolate geometry from the stage's energy puzzle.
        XCTAssertTrue(g.rejection(.shift(0), in: charged)!.contains("终点"))
        XCTAssertNil(g.transition(.shift(0), from: charged))
        let bMoved = g.transition(.shift(1), from: charged)!
        let bothMoved = g.transition(.shift(0), from: bMoved)!
        XCTAssertEqual(bothMoved.positions, [1, 1]); XCTAssertEqual(bothMoved.energy, 0)
    }

    func testReportedFirstStageAnchorPositionCanMoveAndFinishWithoutRestart() throws {
        var g = game()
        perform([0, 1, 2, 11, 4, 6, 5, 7, 8, 9].map(StarRail.Action.pick), on: &g)
        XCTAssertEqual(g.state.matches, 2)
        XCTAssertEqual(g.state.shifts, 0)
        XCTAssertEqual(g.state.energy, 2)
        XCTAssertEqual(g.state.tray.map { g.stage.cards[$0].kind }, [1, 1, 3, 3])
        XCTAssertEqual(g.board(in: g.state).map(\.id), [3, 10])
        XCTAssertTrue(g.isAnchor(10, in: g.state))
        XCTAssertFalse(g.perform(.pick(10)), "Opening the anchor in the UI must not remove it")
        let restored = try XCTUnwrap(StarRail.Game(archive: g.archive))
        XCTAssertEqual(restored, g, "The existing save must remain playable")
        let preview = try XCTUnwrap(g.preview(0, in: g.state))
        XCTAssertTrue(preview.canMove)
        XCTAssertEqual(preview.proposed.energy, 1)
        XCTAssertEqual(preview.revealed, [3])
        perform([.shift(0), .pick(3), .pick(10)], on: &g)
        XCTAssertEqual(g.status, .won)
        XCTAssertTrue(g.state.tray.isEmpty)
        XCTAssertEqual(g.state.shifts, 1)
    }

    func testUpperRailLocksLowerRailUntilItMovesAway() {
        let g = game(6)
        var charged = g.state; charged.energy = 2
        let aMoved = g.transition(.shift(0), from: charged)!
        XCTAssertTrue(g.rejection(.shift(0), in: aMoved)!.contains("上方"))
        XCTAssertNil(g.transition(.shift(0), from: aMoved))
        var bMoved = g.transition(.shift(1), from: aMoved)!
        XCTAssertTrue(g.stage.cards.filter { $0.rail == 0 }.allSatisfy { g.blockers(of: $0.id, in: bMoved).isEmpty })
        bMoved.energy = 1
        let returned = g.transition(.shift(0), from: bMoved)!
        XCTAssertEqual(returned.positions, [0, 1]); XCTAssertEqual(returned.arrivals & 3, 3)
    }

    func testEnergyCapsAtTwoAndUndoRestoresMatchAndOverflow() {
        var g = game()
        perform([.pick(0), .pick(1), .pick(2), .shift(0), .pick(9), .pick(10), .pick(11),
                 .pick(3), .pick(4), .pick(6), .pick(5), .pick(7)], on: &g)
        let before = g
        XCTAssertEqual(g.state.energy, 2)
        XCTAssertTrue(g.perform(.pick(8)))
        XCTAssertEqual(g.state.energy, 2); XCTAssertEqual(g.state.overflowEnergy, 1)
        XCTAssertTrue(g.undo()); XCTAssertEqual(g, before)
        XCTAssertEqual(g.state.tray.count, 2)
    }

    func testSeventhCardCanCompleteTripleBeforeCapacityLoss() {
        var g = game()
        perform([0, 1, 6, 7, 8, 9].map(StarRail.Action.pick), on: &g)
        XCTAssertEqual(g.state.tray.count, 6)
        XCTAssertTrue(g.perform(.pick(5)))
        XCTAssertEqual(g.state.tray.count, 4); XCTAssertEqual(g.state.energy, 1)
        XCTAssertEqual(g.status, .playing); XCTAssertEqual(g.state.peak, 6)
    }

    func testSevenUnmatchedCardsLoseAndUndoRecovers() {
        let stage = StarRail.Stage(id: 99, title: "capacity fixture", lesson: "", objective: "", tip: "",
            cards: (0..<7).map { .init(id: $0, kind: $0, x: $0 * 4, y: 0, z: 0, rail: nil) },
            rails: [], requiredArrivals: 0, plannedMoves: 0, targetPeak: 6)
        var g = StarRail.Game(stage: stage)
        perform((0..<7).map(StarRail.Action.pick), on: &g)
        XCTAssertEqual(g.status, .lost); XCTAssertTrue(g.failureReason(in: g.state)!.contains("七格"))
        XCTAssertFalse(g.perform(.shift(0)))
        XCTAssertTrue(g.undo()); XCTAssertEqual(g.status, .playing); XCTAssertEqual(g.state.tray.count, 6)
    }

    func testTakingLastRailCardBeforeGoalLosesWithRecoverableExplanation() {
        var g = StarRail.Game(stage: StarRail.stage(1, revision: 1)!)
        perform([.pick(10), .pick(11)], on: &g)
        XCTAssertEqual(g.status, .lost); XCTAssertTrue(g.failureReason(in: g.state)!.contains("航线"))
        XCTAssertTrue(g.undo()); XCTAssertEqual(g.status, .playing)
    }

    func testInvalidActionsDoNotMutateState() {
        var g = game()
        for action in [StarRail.Action.pick(-1), .pick(99), .pick(3), .shift(-1), .shift(2), .shift(0)] {
            let original = g
            XCTAssertFalse(g.perform(action)); XCTAssertEqual(g, original)
        }
        XCTAssertTrue(g.perform(.pick(0)))
        let once = g
        XCTAssertFalse(g.perform(.pick(0))); XCTAssertEqual(g, once)
    }

    func testRapidTapAndOldAnimationCompletionCannotChangeRestartedGame() throws {
        var session = StarRail.Session(game: game())
        let old = try XCTUnwrap(session.submit(.pick(0)))
        XCTAssertNil(session.submit(.pick(1))); XCTAssertFalse(session.undo())
        session.restart()
        let fresh = try XCTUnwrap(session.submit(.pick(1)))
        session.finish(old)
        XCTAssertEqual(session.pending, fresh); XCTAssertEqual(session.game.actions, [.pick(1)])
        session.finish(fresh); XCTAssertTrue(session.canInteract)
        XCTAssertTrue(session.undo()); XCTAssertEqual(session.game, game())
    }

    func testBackgroundCommitsActionOnceAndResumeRejectsStaleCompletion() throws {
        var session = StarRail.Session(game: game())
        let old = try XCTUnwrap(session.submit(.pick(0)))
        session.setActive(false)
        XCTAssertNil(session.pending); XCTAssertNil(session.submit(.pick(1)))
        let restored = try XCTUnwrap(StarRail.Game(archive: session.game.archive))
        XCTAssertEqual(restored.actions, [.pick(0)])
        session.setActive(true)
        let new = try XCTUnwrap(session.submit(.pick(1)))
        session.finish(old); XCTAssertEqual(session.pending, new)
        session.finish(new)
        XCTAssertEqual(session.game.actions, [.pick(0), .pick(1)])
    }

    func testSaveSeparatesRunsAndBestStarsSurviveRestart() throws {
        var save = StarRail.Save()
        let won = try win(1)
        XCTAssertTrue(save.keep(won))
        var second = game(2); XCTAssertTrue(second.perform(.pick(0))); XCTAssertTrue(save.keep(second))
        XCTAssertEqual(save.game(for: 1), won); XCTAssertEqual(save.game(for: 2), second)
        XCTAssertTrue(save.keep(game(1)))
        XCTAssertEqual(save.progress.stars[1], 3)
        XCTAssertEqual(save.game(for: 2), second)
        XCTAssertEqual(StarRail.Save(data: try XCTUnwrap(save.encoded())), save)
        XCTAssertNil(save.game(for: 3)); XCTAssertFalse(save.keep(game(6)))
    }

    func testArchiveRejectsUnknownVersionsCorruptActionsAndOversizedInput() throws {
        XCTAssertNil(StarRail.Game(archive: .init(version: "star-rails-v99", stage: 1, actions: [])))
        XCTAssertNil(StarRail.Game(archive: .init(stage: 7, actions: [])))
        XCTAssertNil(StarRail.Game(archive: .init(stage: 1, actions: [.shift(0)])))
        XCTAssertNil(StarRail.Game(archive: .init(stage: 1, actions: [.pick(0), .pick(0)])))
        XCTAssertNil(StarRail.Game(archive: .init(stage: 1, actions: Array(repeating: .pick(0), count: 257))))
        XCTAssertNil(StarRail.Save(data: Data("broken".utf8)))
        XCTAssertNil(StarRail.Save(data: Data(repeating: 0, count: 131_073)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(StarRail.Save().encoded())) as? [String: Any])
        object["version"] = "future"
        XCTAssertNil(StarRail.Save(data: try JSONSerialization.data(withJSONObject: object)))
        object["version"] = StarRail.version; object["selectedStage"] = 6
        XCTAssertNil(StarRail.Save(data: try JSONSerialization.data(withJSONObject: object)))
    }

    func testSolverBudgetIsNotReportedAsImpossible() {
        XCTAssertEqual(StarRailSolver.solve(game(), nodeLimit: 0), .budgetExceeded(nodes: 0))
        if case .solved = StarRailSolver.solve(game(), maxShifts: 0) { XCTFail("Goal requires a shift") }
    }

    func testOldChallengeVersionsRemainDistinctFromStarRails() {
        XCTAssertNil(TileGame.decode(StarRail.version))
        XCTAssertNotEqual(StarRail.Save.storageKey, "tileGame.journey.v2")
        XCTAssertNotEqual(StarRail.Save.storageKey, "tileGame.records")
    }
}
