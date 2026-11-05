import XCTest
@testable import ShiftCore

final class TileJourneyTests: XCTestCase {
    func testNewBoardsRemainSolvableAndKeepDistinctLayers() {
        for level in TileGame.Level.allCases {
            for seed in UInt64(0)..<80 {
                var game = TileGame(level: level, seed: seed, ruleSet: .constellation)
                XCTAssertEqual(game, TileGame(level: level, seed: seed, ruleSet: .constellation))
                XCTAssertEqual(game.total % 3, 0)
                XCTAssertTrue(Dictionary(grouping: game.board, by: \.kind).values.allSatisfy { $0.count % 3 == 0 })
                XCTAssertGreaterThanOrEqual(Set(game.board.map(\.z)).count, level == .hard ? 7 : 4)
                XCTAssertTrue(game.board.allSatisfy { $0.x >= 0 && $0.x + 4 <= TileGame.width && $0.y >= 0 })
                XCTAssertLessThan(game.freeIDs.count, game.total / 2, "\(level) / \(seed)：关卡应当保留真实遮挡，而非平铺凑数量")
                for id in game.solution {
                    XCTAssertTrue(game.pick(id), "\(level) / \(seed) / \(id)")
                    XCTAssertNotEqual(game.status, .lost)
                }
                game.settle()
                XCTAssertEqual(game.status, .won)
                XCTAssertEqual(game.toolsUsed, 0)
                XCTAssertEqual(game.cleared, game.total)
            }
        }
    }

    func testFallbackGeometryIsBoundedLayeredAndSolvable() {
        for level in TileGame.Level.allCases {
            let spec = TileGame.Spec.constellation(level)
            var tiles = TileGame.compactLayout(spec)
            var random = SeededRandom(seed: 917)
            let order = TileGame.removalOrder(tiles, using: &random)
            let kinds = TileGame.kindSequence(count: tiles.count, spec: spec, using: &random)
            for (step, index) in order.enumerated() { tiles[index].kind = kinds[step] }
            var game = TileGame(level: level, seed: 917, tiles: tiles, ruleSet: .constellation)
            XCTAssertLessThan(game.freeIDs.count, game.total / 2)
            XCTAssertLessThanOrEqual(game.total, spec.most)
            XCTAssertEqual(game.total % 3, 0)
            XCTAssertTrue(tiles.allSatisfy { $0.x >= 0 && $0.x + 4 <= TileGame.width && $0.y >= 0 })
            for index in order { XCTAssertTrue(game.pick(tiles[index].id)); XCTAssertNotEqual(game.status, .lost) }
            game.settle()
            XCTAssertEqual(game.status, .won)
        }
    }

    func testCampaignUnlocksSequentiallyAndKeepsBestStarsAndScore() throws {
        var progress = TileJourney.Progress()
        XCTAssertEqual(progress.nextStage.id, 1)
        XCTAssertFalse(progress.isUnlocked(0))
        XCTAssertFalse(progress.isUnlocked(2))
        XCTAssertFalse(progress.isUnlocked(13))
        for stage in TileJourney.stages {
            var game = stage.game
            XCTAssertFalse(progress.record(stage: stage.id, game: game), "未通关不能解锁")
            for id in game.solution { XCTAssertTrue(game.pick(id)) }
            game.settle()
            XCTAssertEqual(game.stars, 3, "第 \(stage.id) 关必须有一条可实现三星的完整路径")
            print("TILESTAGE|id=\(stage.id)|tiles=\(game.total)|combo=\(game.bestCombo)|stars=\(game.stars)|score=\(game.score)")
            XCTAssertTrue(progress.record(stage: stage.id, game: game))
            XCTAssertGreaterThanOrEqual(progress.stars[stage.id] ?? 0, 2)
            XCTAssertEqual(progress.scores[stage.id], game.score)
            XCTAssertEqual(progress.nextStage.id, min(stage.id + 1, 12))
        }
        let encoded = try JSONEncoder().encode(progress)
        XCTAssertEqual(try JSONDecoder().decode(TileJourney.Progress.self, from: encoded), progress)
        XCTAssertGreaterThanOrEqual(progress.totalStars, 24)
        let first = TileJourney.stages[0]
        var lower = first.game
        XCTAssertTrue(lower.pick(lower.solution[0]))
        XCTAssertTrue(lower.undo())
        for id in lower.solution { XCTAssertTrue(lower.pick(id)) }
        lower.settle()
        XCTAssertEqual(lower.stars, 1)
        XCTAssertTrue(progress.record(stage: first.id, game: lower))
        XCTAssertEqual(progress.stars[first.id], 3, "低星重玩不能覆盖最高星级")
        let saved = progress
        XCTAssertFalse(progress.record(stage: 1, game: TileGame(level: .easy, seed: 1)))
        XCTAssertEqual(progress, saved)
    }

    func testNewCodesReplayNewRulesAndOldCodesStillReplayOldRules() {
        for level in TileGame.Level.allCases {
            for seed: UInt64 in [0, 1, 11_301, TileGame.seedLimit - 1] {
                let old = TileGame(level: level, seed: seed)
                let new = TileGame(level: level, seed: seed, ruleSet: .constellation)
                XCTAssertEqual(old.code.count, 6)
                XCTAssertTrue(new.code.hasPrefix("V2-"))
                for source in [old, new] {
                    let decoded = TileGame.decode("我已通关！挑战码 \(source.code.lowercased())，试试看")!
                    XCTAssertEqual(TileGame(level: decoded.level, seed: decoded.seed, ruleSet: decoded.ruleSet).board, source.board)
                    XCTAssertEqual(decoded.ruleSet, source.ruleSet)
                }
                XCTAssertNotEqual(old.board, new.board)
            }
        }
        XCTAssertNil(TileGame.decode("V3-K7Q2MX"))
        XCTAssertNil(TileGame.decode("V2-ABC K7Q2MX"))
        XCTAssertNil(TileGame.decode("V2-K7Q2MXX"))
    }

    func testComboUsesMovesNotSpeedAndCannotBeFarmedWithUndoOrSettle() {
        let kinds = [0,0,0,1,1,1,2,2,2,3,3,3]
        var game = TileGame(level: .easy, seed: 0, tiles: kinds.enumerated().map {
            .init(id: $0.offset, kind: $0.element, x: $0.offset % 7 * 4, y: $0.offset / 7 * 4, z: 0)
        })
        for id in 0..<3 { game.pick(id) }
        XCTAssertEqual(game.score, 100)
        game.settle(); game.settle()
        XCTAssertEqual(game.score, 100)
        XCTAssertFalse(game.undo())
        for id in 3..<6 { game.pick(id) }
        XCTAssertEqual(game.combo, 2)
        XCTAssertEqual(game.score, 300)
        game.pick(6)
        XCTAssertTrue(game.undo())
        XCTAssertEqual(game.combo, 0)
        XCTAssertEqual(game.score, 300)
        for id in 6..<12 { game.pick(id) }
        game.settle()
        XCTAssertEqual(game.status, .won)
        XCTAssertEqual(game.stars, 1, "用过道具不再算无道具三星")
    }

    /// 固定贪心：先凑三张、再凑对子，再拿覆盖牌数更多的牌；不读取隐藏牌种或生成器解法。
    func testDifficultyAgainstVisibleInformationGreedyPlayer() {
        func wins(_ level: TileGame.Level, _ rules: TileGame.RuleSet) -> Int {
            var wins = 0
            for seed in UInt64(0)..<60 {
                var game = TileGame(level: level, seed: seed, ruleSet: rules)
                while game.status == .playing {
                    game.settle()
                    let free = game.board.filter(game.isFree)
                    let ranked = free.map { tile in
                        (tile: tile, matches: game.tray.filter { $0.kind == tile.kind }.count,
                         covers: game.board.filter { $0.z < tile.z && tile.overlaps($0) }.count)
                    }
                    guard let choice = ranked.max(by: { a, b in
                        (a.matches, a.covers, -a.tile.id) < (b.matches, b.covers, -b.tile.id)
                    })?.tile else { break }
                    XCTAssertTrue(game.pick(choice.id))
                }
                game.settle()
                if game.status == .won { wins += 1 }
            }
            return wins
        }
        let easy = wins(.easy, .constellation)
        let normal = wins(.normal, .constellation)
        let hard = wins(.hard, .constellation)
        let old = wins(.hard, .classic)
        print("TILEDIFFICULTY|seeds=60|easy=\(easy)|normal=\(normal)|hard=\(hard)|oldHard=\(old)")
        XCTAssertLessThan(hard, 30, "困难不应被只看眼前的策略轻易扫过")
        XCTAssertGreaterThan(easy, hard, "入门与困难必须实际拉开")
    }
}
