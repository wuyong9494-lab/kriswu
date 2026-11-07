import XCTest
@testable import ShiftCore

final class TileMasterTests: XCTestCase {
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
