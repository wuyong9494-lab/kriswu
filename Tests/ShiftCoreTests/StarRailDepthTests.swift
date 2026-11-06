import XCTest
@testable import ShiftCore

final class StarRailDepthTests: XCTestCase {
    func testAnchorRefusesAccidentalLossAndPreviewUnlocksItAfterArrival() throws {
        var game = StarRail.Game(stage: StarRail.stage(1)!)
        XCTAssertTrue(game.perform(.pick(10)))
        XCTAssertTrue(game.isAnchor(11, in: game.state))
        let before = game
        XCTAssertFalse(game.perform(.pick(11)))
        XCTAssertEqual(game, before)
        XCTAssertFalse(game.legalActions(in: game.state).contains(.pick(11)))
        for id in [0, 1, 2] { XCTAssertTrue(game.perform(.pick(id))) }
        let preview = try XCTUnwrap(game.preview(0, in: game.state))
        XCTAssertTrue(preview.canMove)
        XCTAssertFalse(game.isAnchor(11, in: preview.proposed))
        XCTAssertTrue(game.perform(.shift(0)))
        XCTAssertEqual(game.state, preview.proposed)
        XCTAssertTrue(game.perform(.pick(11)))
    }

    func testForecastReservesFutureAnchorAndSeventhSlot() throws {
        let first = StarRail.Game(stage: StarRail.stage(1)!)
        let earth = try XCTUnwrap(first.kindPlans(in: first.state).first { $0.kind == 3 })
        XCTAssertEqual(earth.remaining, 3)
        XCTAssertEqual(earth.available, 2)
        XCTAssertFalse(earth.canComplete, "Two identical rail cards cannot both be collected before their goal")
        let cards = (0..<15).map { StarRail.Card(id: $0, kind: $0 / 3, x: $0 * 4, y: 0, z: 0, rail: nil) }
        let stage = StarRail.Stage(id: 99, title: "slot fixture", lesson: "", objective: "", tip: "",
                                  cards: cards, rails: [], requiredArrivals: 0, plannedMoves: 0, targetPeak: 6, revision: 2)
        var game = StarRail.Game(stage: stage)
        for id in [0, 3, 4, 6, 7, 9] { XCTAssertTrue(game.perform(.pick(id))) }
        let plans = game.kindPlans(in: game.state)
        XCTAssertEqual(game.state.tray.count, 6)
        XCTAssertFalse(try XCTUnwrap(plans.first { $0.kind == 0 }).canComplete)
        XCTAssertTrue(try XCTUnwrap(plans.first { $0.kind == 1 }).canComplete)
        XCTAssertTrue(game.perform(.pick(5)))
        XCTAssertEqual(game.state.tray.count, 4)
    }

    func testNoLegalMoveEndsWithExplanationAndUndoRemainsAvailable() {
        let cards: [StarRail.Card] = [
            .init(id: 0, kind: 0, x: 0, y: 0, z: 1, rail: 0),
            .init(id: 1, kind: 0, x: 8, y: 0, z: 0, rail: nil),
            .init(id: 2, kind: 0, x: 12, y: 0, z: 0, rail: nil)
        ]
        let stage = StarRail.Stage(id: 99, title: "stranded fixture", lesson: "", objective: "", tip: "", cards: cards,
                                  rails: [.init(id: 0, name: "A", delta: .init(x: 4, y: 0))],
                                  requiredArrivals: 2, plannedMoves: 1, targetPeak: 3, revision: 2)
        var game = StarRail.Game(stage: stage)
        XCTAssertTrue(game.perform(.pick(1))); XCTAssertTrue(game.perform(.pick(2)))
        XCTAssertEqual(game.status, .lost)
        XCTAssertTrue(game.legalActions(in: game.state).isEmpty)
        XCTAssertTrue(game.failureReason(in: game.state)!.contains("能量"))
        XCTAssertTrue(game.undo()); XCTAssertEqual(game.status, .playing)
    }

    func testStaggeredRailsCoverMultipleRowsWithoutMoreCardsOrLayers() {
        for id in [5, 6] {
            let stage = StarRail.stage(id)!, old = StarRail.stage(id, revision: 1)!
            XCTAssertEqual(stage.cards.count, old.cards.count)
            XCTAssertEqual(stage.cards.map(\.z).max(), old.cards.map(\.z).max())
            let game = StarRail.Game(stage: stage)
            let counts = stage.cards.filter { $0.rail != nil }.map { railCard in
                stage.cards.filter { $0.z < railCard.z && game.overlaps(railCard, $0, in: game.state) }.count
            }
            XCTAssertGreaterThan(counts.max() ?? 0, 1)
        }
    }

    func testLegacySaveMigratesScoresButReplaysUnfinishedBoardUnderOldRules() throws {
        var won = StarRail.Game(stage: StarRail.stage(1, revision: 1)!)
        for action in [StarRail.Action.pick(0), .pick(1), .pick(2), .shift(0), .pick(9), .pick(10), .pick(11),
                       .pick(3), .pick(4), .pick(6), .pick(5), .pick(7), .pick(8)] { XCTAssertTrue(won.perform(action)) }
        var pending = StarRail.Game(stage: StarRail.stage(2, revision: 1)!)
        XCTAssertTrue(pending.perform(.pick(15))); XCTAssertTrue(pending.perform(.pick(9)))
        func oldArchive(_ game: StarRail.Game) throws -> [String: Any] {
            var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(game.archive)) as? [String: Any])
            value.removeValue(forKey: "revision")
            return value
        }
        let old: [String: Any] = ["version": StarRail.version, "selectedStage": 2,
            "progress": ["version": StarRail.version, "stars": ["1": won.stars],
                         "bestMoves": ["1": won.state.shifts], "bestPeak": ["1": won.state.peak]],
            "runs": ["1": try oldArchive(won), "2": try oldArchive(pending)]]
        var migrated = try XCTUnwrap(StarRail.Save(data: JSONSerialization.data(withJSONObject: old)))
        XCTAssertEqual(migrated.progress.legacyStars[1], won.stars)
        XCTAssertEqual(migrated.progress.legacyMoves[1], won.state.shifts)
        XCTAssertEqual(migrated.progress.legacyPeak[1], won.state.peak)
        XCTAssertTrue(migrated.progress.stars.isEmpty)
        XCTAssertTrue(migrated.progress.unlocked(2)); XCTAssertFalse(migrated.progress.unlocked(3))
        XCTAssertEqual(migrated.game(for: 2), pending)
        var session = StarRail.Session(game: pending)
        session.restart()
        XCTAssertEqual(session.game.stage.revision, StarRail.catalogRevision)
        XCTAssertTrue(migrated.keep(session.game))
        XCTAssertEqual(migrated.progress.legacyStars[1], won.stars)
        XCTAssertEqual(StarRail.Save(data: try XCTUnwrap(migrated.encoded())), migrated)
    }

    func testLegacySixStageSolutionsStillReplayAndUnknownRevisionsFail() throws {
        for stage in StarRail.originalStages {
            var game = StarRail.Game(stage: stage)
            guard case .solved(let actions, _) = StarRailSolver.solve(game, maxShifts: stage.plannedMoves, maxPeak: stage.targetPeak) else {
                XCTFail("Legacy stage changed"); continue
            }
            for action in actions { XCTAssertTrue(game.perform(action)) }
            XCTAssertEqual(game.status, .won)
            XCTAssertEqual(StarRail.Game(archive: game.archive), game)
        }
        XCTAssertNil(StarRail.Game(archive: .init(stage: 1, actions: [], revision: 999)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(StarRail.Save().encoded())) as? [String: Any])
        var progress = try XCTUnwrap(object["progress"] as? [String: Any])
        progress["catalogRevision"] = 999; object["progress"] = progress
        XCTAssertNil(StarRail.Save(data: try JSONSerialization.data(withJSONObject: object)))
    }
}
