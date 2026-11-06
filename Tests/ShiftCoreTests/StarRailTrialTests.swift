import XCTest
@testable import ShiftCore

final class StarRailTrialTests: XCTestCase {
    private func win(_ trial: StarRail.Trial) throws -> StarRail.Game {
        var game = StarRail.Game(stage: trial.stage)
        guard case .solved(let actions, _) = StarRailSolver.solve(game, nodeLimit: 100_000,
            maxShifts: trial.stage.plannedMoves, maxPeak: trial.stage.targetPeak) else {
            throw NSError(domain: "No three-star route for \(trial.id)", code: 1)
        }
        for action in actions { XCTAssertTrue(game.perform(action), trial.id) }
        XCTAssertEqual(game.status, .won); XCTAssertEqual(game.stars, 3)
        return game
    }
    private func fixture(_ rule: StarRail.TrialRule?) -> StarRail.Stage {
        StarRail.Stage(id: 99, title: "resource constraints", lesson: "", objective: "", tip: "",
            cards: (0..<15).map { .init(id: $0, kind: $0 / 3, x: $0 * 4, y: 0, z: 0, rail: nil) },
            rails: [], requiredArrivals: 0, plannedMoves: 0, targetPeak: 5, revision: 2, trial: rule)
    }

    func testEveryContractHasThreeStarRouteWithExactReplayAndConservation() throws {
        XCTAssertEqual(Set(StarRail.Trial.all.map(\.id)).count, 12)
        var saved = StarRail.TrialSave()
        for trial in StarRail.Trial.all {
            let won = try win(trial)
            var game = StarRail.Game(stage: trial.stage)
            for action in won.actions {
                let before = game.state
                XCTAssertTrue(game.perform(action))
                XCTAssertEqual(StarRail.Game(archive: game.archive), game)
                XCTAssertLessThan(game.state.tray.count, trial.stage.capacity)
                XCTAssertLessThanOrEqual(game.state.energy, trial.stage.energyLimit)
                XCTAssertEqual(game.state.remaining.nonzeroBitCount + game.state.tray.count + game.state.matches * 3, trial.stage.cards.count)
                XCTAssertTrue(game.undo()); XCTAssertEqual(game.state, before)
                XCTAssertTrue(game.perform(action))
            }
            XCTAssertEqual(game.rewinds, won.actions.count)
            XCTAssertTrue(saved.keep(won))
        }
        XCTAssertEqual(saved.completed, 12); XCTAssertEqual(saved.mastered, 12)
        XCTAssertEqual(StarRail.TrialSave(data: try XCTUnwrap(saved.encoded())), saved)
    }

    func testSixthCardMatchesBeforeCapacityCheckAndUnmatchedSixLoses() {
        var compact = StarRail.Game(stage: fixture(.compact))
        for id in [0, 1, 3, 6, 9] { XCTAssertTrue(compact.perform(.pick(id))) }
        XCTAssertEqual(compact.state.tray.count, 5)
        XCTAssertTrue(compact.kindPlans(in: compact.state).first { $0.kind == 0 }!.canComplete)
        XCTAssertTrue(compact.perform(.pick(2)))
        XCTAssertEqual(compact.state.tray.count, 3); XCTAssertEqual(compact.status, .playing)
        XCTAssertTrue(compact.undo()); XCTAssertEqual(compact.state.tray.count, 5)
        XCTAssertTrue(compact.perform(.pick(12)))
        XCTAssertEqual(compact.status, .lost)
        XCTAssertTrue(compact.failureReason(in: compact.state)!.contains("六格"))
        XCTAssertTrue(compact.undo()); XCTAssertEqual(compact.status, .playing)
        var normal = StarRail.Game(stage: fixture(nil))
        for id in [0, 1, 3, 6, 9, 12] { XCTAssertTrue(normal.perform(.pick(id))) }
        XCTAssertEqual(normal.status, .playing)
    }

    func testSingleEnergyIsLostToOverflowUntilSpentAndUndoRestoresIt() {
        var game = StarRail.Game(stage: fixture(.pulse))
        for id in 0..<5 { XCTAssertTrue(game.perform(.pick(id))) }
        let before = game.state
        XCTAssertTrue(game.perform(.pick(5)))
        XCTAssertEqual(game.state.energy, 1); XCTAssertEqual(game.state.overflowEnergy, 1)
        XCTAssertTrue(game.undo()); XCTAssertEqual(game.state, before)
        XCTAssertEqual(game.rewinds, 1)
        XCTAssertEqual(StarRail.Game(stage: fixture(nil)).stage.energyLimit, 2)
    }

    func testMasterShiftBudgetCannotBeBypassedByPreviewOrExtraEnergy() throws {
        let trial = StarRail.Trial(stageID: 6, rule: .master)!
        let game = StarRail.Game(stage: trial.stage)
        var state = game.state; state.energy = 1; state.shifts = trial.stage.plannedMoves
        for rail in trial.stage.rails {
            XCTAssertTrue(try XCTUnwrap(game.rejection(.shift(rail.id), in: state)).contains("预算"))
            XCTAssertFalse(try XCTUnwrap(game.preview(rail.id, in: state)).canMove)
            XCTAssertNil(game.transition(.shift(rail.id), from: state))
        }
        let won = try win(trial)
        XCTAssertEqual(won.state.shifts, trial.stage.plannedMoves)
    }

    func testRewindSurvivesRelaunchAndRestartPreservesContract() throws {
        let trial = StarRail.Trial(stageID: 5, rule: .master)!
        var session = StarRail.Session(game: .init(stage: trial.stage))
        let first = try XCTUnwrap(session.game.legalActions(in: session.game.state).first)
        let stale = try XCTUnwrap(session.submit(first))
        XCTAssertNil(session.submit(first))
        session.setActive(false); XCTAssertFalse(session.undo())
        session.setActive(true); XCTAssertTrue(session.undo())
        let restored = try XCTUnwrap(StarRail.Game(archive: session.game.archive))
        XCTAssertEqual(restored.rewinds, 1); XCTAssertTrue(restored.actions.isEmpty)
        session = StarRail.Session(game: restored)
        session.restart(); XCTAssertEqual(session.game.stage, trial.stage)
        XCTAssertEqual(session.game.rewinds, 0)
        let fresh = try XCTUnwrap(session.submit(first))
        session.finish(stale); XCTAssertEqual(session.pending, fresh)
        session.finish(fresh); XCTAssertTrue(session.canInteract)
    }

    func testBestRecordKeepsOneWinningRunAndSurvivesRetryAndWorseResult() throws {
        let trial = StarRail.Trial(stageID: 4, rule: .pulse)!
        var won = try win(trial)
        var save = StarRail.TrialSave()
        XCTAssertTrue(save.keep(won)); XCTAssertEqual(save.mastered, 1)
        let original = won
        let last = try XCTUnwrap(won.actions.last)
        XCTAssertTrue(won.undo()); XCTAssertTrue(won.perform(last))
        XCTAssertEqual(won.rewinds, 1); XCTAssertTrue(save.keep(won))
        XCTAssertEqual(save.record(for: trial), original)
        XCTAssertEqual(save.game(for: trial), won)
        XCTAssertTrue(save.keep(.init(stage: trial.stage)))
        XCTAssertEqual(save.record(for: trial), original)
        XCTAssertTrue(save.game(for: trial).actions.isEmpty)
        XCTAssertEqual(StarRail.TrialSave(data: try XCTUnwrap(save.encoded())), save)
    }

    func testContractSaveAndCampaignProgressCannotMix() throws {
        let trial = StarRail.Trial(stageID: 3, rule: .compact)!
        let won = try win(trial)
        var campaign = StarRail.Save(); var trials = StarRail.TrialSave()
        XCTAssertFalse(campaign.keep(won))
        XCTAssertFalse(trials.keep(.init(stage: StarRail.stage(1)!)))
        var progress = StarRail.Progress()
        XCTAssertFalse(progress.record(won)); XCTAssertEqual(progress.totalStars, 0)
        XCTAssertTrue(trials.keep(won))
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(trials.encoded())) as? [String: Any])
        value["best"] = [trial.id: ["version": StarRail.version, "stage": 3, "revision": 2, "trial": "N", "actions": []]]
        XCTAssertNil(StarRail.TrialSave(data: try JSONSerialization.data(withJSONObject: value)))
        value["best"] = [:]; value["version"] = 99
        XCTAssertNil(StarRail.TrialSave(data: try JSONSerialization.data(withJSONObject: value)))
    }

    func testArchiveRejectsUnknownContractRevisionAndInvalidRewindCount() throws {
        let game = StarRail.Game(stage: StarRail.Trial(stageID: 3, rule: .master)!.stage)
        var archive = game.archive
        archive.revision = 1; XCTAssertNil(StarRail.Game(archive: archive))
        archive = game.archive; archive.stage = 1; XCTAssertNil(StarRail.Game(archive: archive))
        archive = game.archive; archive.rewinds = -1; XCTAssertNil(StarRail.Game(archive: archive))
        archive = game.archive; archive.rewinds = 10_001; XCTAssertNil(StarRail.Game(archive: archive))
        archive = game.archive; archive.trial = nil; archive.rewinds = 1
        XCTAssertNil(StarRail.Game(archive: archive))
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(game.archive)) as? [String: Any])
        value["trial"] = "FUTURE"
        XCTAssertThrowsError(try JSONDecoder().decode(StarRail.Game.Archive.self, from: JSONSerialization.data(withJSONObject: value)))
    }

    func testChallengeCodesRoundTripWholeSharesAndRejectAmbiguity() {
        XCTAssertEqual(TileGame.displayName, "星了个星")
        for trial in StarRail.Trial.all {
            XCTAssertEqual(StarRail.Trial.decode(trial.shareText), trial)
            XCTAssertEqual(StarRail.Trial.decode(trial.id.lowercased()), trial)
            XCTAssertNil(StarRail.Trial.decode("A" + trial.id))
            XCTAssertNil(StarRail.Trial.decode(trial.id + "-X"))
        }
        for text in ["SX3-03-N", "SX2-01-M", "SX2-07-M", "SX2-3-N", "SX2-03-X", "SX2-03-N SX2-04-M", String(repeating: "x", count: 8_193)] {
            XCTAssertNil(StarRail.Trial.decode(text), text.prefix(30).description)
        }
    }

    func testRenameKeepsOldDailyBoardAndBothOldAndNewShareTextDecodable() {
        let date = DayKey(year: 2026, month: 11, day: 6)
        XCTAssertEqual(TileGame.dailySeed(date), 83_612_375, "Published daily boards cannot change with the display name")
        for rules in [TileGame.RuleSet.classic, .constellation] {
            let game = TileGame(level: .hard, seed: 2026, ruleSet: rules)
            for name in ["叠叠消", TileGame.displayName] {
                let text = "我在「\(name)」通关了！挑战码 \(game.code)，来比比"
                XCTAssertEqual(TileGame.decode(text)?.seed, 2026)
                XCTAssertEqual(TileGame.decode(text)?.ruleSet, rules)
            }
        }
    }

    func testTrialNamespaceDoesNotCaptureLegacyCodesContainingSX() {
        for code in ["2SX234", "ASXABC"] {
            XCTAssertNotNil(TileGame.decode(code))
            XCTAssertFalse(StarRail.Trial.containsCodePrefix(code))
            XCTAssertNil(StarRail.Trial.decode(code))
        }
        for code in ["SX2-03-N", "星约码 sx9-03-n", "SX2-07-Z"] {
            XCTAssertTrue(StarRail.Trial.containsCodePrefix(code))
        }
    }

    func testDailyRotationUsesBeijingMidnightAndCoversAllTwelveContracts() throws {
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: "2026-11-06T16:00:00Z"))
        let before = start.addingTimeInterval(-1)
        XCTAssertNotEqual(StarRail.Trial.daily(at: before), StarRail.Trial.daily(at: start))
        let codes = (0..<12).map { StarRail.Trial.daily(at: start.addingTimeInterval(Double($0) * 86_400)).id }
        XCTAssertEqual(Set(codes), Set(StarRail.Trial.all.map(\.id)))
        XCTAssertEqual(StarRail.Trial.daily(at: start), StarRail.Trial.daily(at: start.addingTimeInterval(12 * 86_400)))
        XCTAssertEqual(StarRail.Trial.daily(at: start), StarRail.Trial.daily(at: start.addingTimeInterval(86_399)))
    }
}
