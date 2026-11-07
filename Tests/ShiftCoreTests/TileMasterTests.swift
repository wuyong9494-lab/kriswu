import XCTest
@testable import ShiftCore

final class TileMasterTests: XCTestCase {
    func testDailyEditionIsDeterministicSolvableAndNotEasierForGreedyPlayers() {
        for day in [DayKey(year: 2026, month: 11, day: 7), DayKey(year: 2026, month: 11, day: 8)] {
            let seed = TileGame.dailyMasterSeed(day)
            XCTAssertEqual(seed, TileGame.dailyMasterSeed(day))
            XCTAssertLessThan(seed, TileGame.seedLimit)
            XCTAssertNotEqual(TileGame.dailyMasterRecordKey(day), day.description)
            var game = TileGame(level: .hard, seed: seed, ruleSet: .constellation)
            let original = TileGame(level: .hard, seed: TileGame.dailySeed(day), ruleSet: .constellation)
            let wins = (0..<3).filter { game.greedyClear(policy: $0) }.count
            let oldWins = (0..<3).filter { original.greedyClear(policy: $0) }.count
            XCTAssertLessThanOrEqual(wins, oldWins)
            print("Daily master audit: \(day), seed=\(seed), greedyWins=\(wins)/3, baseline=\(oldWins)/3")
            for id in game.solution {
                XCTAssertTrue(game.pick(id))
                game.settle()
            }
            XCTAssertEqual(game.status, .won)
        }
    }

    func testScreenPreservesReplayAndGuaranteedSolution() {
        for rule in [TileGame.RuleSet.classic, .constellation] {
            for base: UInt64 in [0, 73, TileGame.seedLimit - 1] {
                let chosen = TileGame.masterSeed(startingAt: base, ruleSet: rule)
                XCTAssertLessThan(chosen, TileGame.seedLimit)
                XCTAssertEqual(chosen, TileGame.masterSeed(startingAt: base, ruleSet: rule))
                var game = TileGame(level: .hard, seed: chosen, ruleSet: rule)
                let initial = TileGame(level: .hard, seed: base, ruleSet: rule)
                let chosenWins = (0..<3).filter { game.greedyClear(policy: $0) }.count
                let initialWins = (0..<3).filter { initial.greedyClear(policy: $0) }.count
                XCTAssertLessThanOrEqual(chosenWins, initialWins)
                for id in game.solution {
                    XCTAssertTrue(game.pick(id))
                    game.settle()
                }
                XCTAssertEqual(game.status, .won)
            }
        }
    }
}
