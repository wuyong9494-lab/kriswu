import XCTest
@testable import ShiftCore

final class TileDepthTests: XCTestCase {
    func testSeparatePhasesHaveIndependentWinningAndLosingWitnesses() {
        let stacks = [[5, 3, 0, 4, 2, 3], [4, 3, 5, 5, 2, 0], [1, 2, 4, 1, 1, 0]]
        let route = [5, 17, 16, 15, 14, 13, 12, 4, 11, 10, 3, 2, 1, 0, 9, 8, 7, 6]
        let tiles = (0..<3).flatMap { part in
            stacks.enumerated().flatMap { column, kinds in
                kinds.enumerated().map { height, kind in
                    TileGame.Tile(id: part * 100 + column * 6 + height, kind: part * 6 + kind,
                                  x: part * 32 + column * 8, y: 0, z: height)
                }
            }
        }
        let path = (0..<3).flatMap { part in route.map { $0 + part * 100 } }
        let game = TileGame(level: .hard, seed: 0, tiles: tiles)
        let forks = game.planningPhaseForks(along: path, nodeLimit: 48000)
        XCTAssertGreaterThanOrEqual(forks.count, 2)
        XCTAssertEqual(Set(forks.map { ($0.pickNumber - 1) * 3 / path.count }).count, forks.count)
        for (left, right) in zip(forks, forks.dropFirst()) {
            XCTAssertGreaterThanOrEqual(right.pickNumber - left.pickNumber, path.count / 4)
        }
        // Independently enumerate every branch for each reported witness.
        func loses(_ state: TileGame, remaining: Int) -> Bool {
            if state.status == .lost { return true }
            if state.status == .won || remaining == 0 { return false }
            let ids = state.freeIDs.sorted()
            guard !ids.isEmpty else { return false }
            return ids.allSatisfy { id in
                var child = state
                guard child.pick(id) else { return false }
                child.settle()
                return loses(child, remaining: remaining - 1)
            }
        }
        for fork in forks {
            var alternative = game
            for id in path.prefix(fork.pickNumber - 1) { XCTAssertTrue(alternative.pick(id)); alternative.settle() }
            XCTAssertTrue(alternative.pick(fork.losingTile)); alternative.settle()
            XCTAssertEqual(alternative.status, .playing)
            XCTAssertTrue(loses(alternative, remaining: 2))
        }
        XCTAssertTrue(game.planningPhaseForks(along: Array(path.dropLast())).isEmpty)
        XCTAssertTrue(game.planningPhaseForks(along: path, nodeLimit: 0).isEmpty)
    }

    func testAlreadyPublishedDaysKeepTheirBoardAndRecordNamespace() {
        let days: [(Int, UInt64)] = [(7, 84135585), (8, 84550586), (9, 83817048), (10, 84616059),
                                    (11, 83778662), (12, 84198013), (13, 83988990)]
        for (number, seed) in days {
            let day = DayKey(year: 2026, month: 11, day: number)
            XCTAssertEqual(TileGame.dailyPlanningSeed(day), seed)
            XCTAssertEqual(TileGame.dailyPlanningRecordKey(day), "master-v2:" + day.description)
        }
        XCTAssertEqual(TileGame.dailyPlanningRecordKey(TileGame.dailyDepthStart), "master-v3:2026-11-14")
    }
}
