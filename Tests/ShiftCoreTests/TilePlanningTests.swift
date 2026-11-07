import XCTest
@testable import ShiftCore

final class TilePlanningTests: XCTestCase {
    private var fixture: TileGame {
        let stacks = [[5, 3, 0, 4, 2, 3], [4, 3, 5, 5, 2, 0], [1, 2, 4, 1, 1, 0]]
        let tiles = stacks.enumerated().flatMap { column, kinds in
            kinds.enumerated().map { height, kind in
                TileGame.Tile(id: column * 6 + height, kind: kind, x: column * 8, y: 0, z: height)
            }
        }
        return TileGame(level: .hard, seed: 0, tiles: tiles)
    }
    private let path = [5, 17, 16, 15, 14, 13, 12, 4, 11, 10, 3, 2, 1, 0, 9, 8, 7, 6]

    func testSearchReturnsOnlyReplayableWinningPaths() {
        var game = fixture
        let report = game.planningProbe(width: 32, nodeLimit: 10000)
        XCTAssertTrue(report.won)
        XCTAssertFalse(report.budgetReached)
        XCTAssertEqual(report.solution.count, game.total)
        for id in report.solution {
            XCTAssertTrue(game.pick(id))
            game.settle()
            XCTAssertNotEqual(game.status, .lost)
        }
        XCTAssertEqual(game.status, .won)
    }

    func testBudgetDoesNotBecomeAnImpossibilityClaim() {
        let zero = fixture.planningProbe(width: 32, nodeLimit: 0)
        XCTAssertTrue(zero.budgetReached)
        XCTAssertFalse(zero.won)
        XCTAssertEqual(zero.expanded, 0)
        XCTAssertTrue(zero.solution.isEmpty)
        let bounded = fixture.planningProbe(width: 32, nodeLimit: 7)
        XCTAssertLessThanOrEqual(bounded.expanded, 7)
        XCTAssertTrue(bounded.budgetReached)
    }

    func testForkHasWinningRouteAndForcedDelayedLoss() {
        let forks = fixture.planningForks(along: path)
        XCTAssertTrue(forks.contains { $0.pickNumber == 5 && $0.winningTile == 14 && $0.losingTile == 4 })
        XCTAssertTrue(fixture.planningForks(along: Array(path.dropLast())).isEmpty)
        XCTAssertTrue(fixture.planningForks(along: path, nodeLimit: 0).isEmpty)
        // Independently enumerate the witnessed alternative: it isn't an
        // immediately full tray, but every legal continuation loses in two picks.
        var game = fixture
        for id in path.prefix(4) { XCTAssertTrue(game.pick(id)); game.settle() }
        XCTAssertTrue(game.pick(4)); game.settle()
        XCTAssertEqual(game.status, .playing)
        func loses(_ state: TileGame, depth: Int) -> Bool {
            if state.status == .lost { return true }
            if depth == 0 || state.status == .won { return false }
            let free = state.board.filter { state.isFree($0) }
            guard !free.isEmpty else { return false }
            return free.allSatisfy { tile in
                var child = state
                _ = child.pick(tile.id); child.settle()
                return loses(child, depth: depth - 1)
            }
        }
        XCTAssertTrue(loses(game, depth: 2))
    }

    func testParkedRescueTilesAreNotIgnoredByForcedLossProof() {
        var game = fixture
        for id in path.prefix(3) { XCTAssertTrue(game.pick(id)); game.settle() }
        XCTAssertTrue(game.moveOut())
        XCTAssertFalse(game.parked.isEmpty)
        XCTAssertTrue(game.planningForks(along: path).isEmpty)
    }

    func testMasksCrossBothWordBoundaries() {
        let tiles = (0..<171).map { TileGame.Tile(id: $0 * 2, kind: ($0 / 3) % 12, x: $0 * 8, y: 0, z: 0) }
        var game = TileGame(level: .hard, seed: 0, tiles: tiles)
        let report = game.planningProbe(width: 1, nodeLimit: 30000)
        XCTAssertTrue(report.won)
        for id in report.solution { XCTAssertTrue(game.pick(id)); game.settle() }
        XCTAssertEqual(game.status, .won)
    }

    func testDailyEditionDoesNotCollideWithExistingRecords() {
        let day = DayKey(year: 2026, month: 11, day: 7)
        let selection = TileGame.dailyPlanningSelection(day)
        XCTAssertEqual(selection, TileGame.dailyPlanningSelection(day))
        XCTAssertEqual(TileGame.dailyPlanningSeed(day), selection.seed)
        XCTAssertNotEqual(TileGame.dailyPlanningRecordKey(day), TileGame.dailyMasterRecordKey(day))
        XCTAssertLessThanOrEqual(selection.candidatesChecked, 8)
        XCTAssertLessThanOrEqual(selection.expanded, 428000)
        var game = TileGame(level: .hard, seed: selection.seed, ruleSet: .constellation)
        if selection.planningGapVerified {
            XCTAssertGreaterThan(selection.criticalForks, 0)
            XCTAssertFalse(game.planningProbe(width: 4, nodeLimit: 16000).won)
            let wide = game.planningProbe(width: 32, nodeLimit: 100000)
            XCTAssertTrue(wide.won)
            XCTAssertFalse(game.planningForks(along: wide.solution).isEmpty)
        }
        for id in game.solution { XCTAssertTrue(game.pick(id)); game.settle() }
        XCTAssertEqual(game.status, .won)
    }
}
