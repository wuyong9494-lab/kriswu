import XCTest
@testable import ShiftCore

final class TileGameTests: XCTestCase {
    /// 同一档、同一个种子摆出来一模一样（几台手机玩同一局）；换个种子就不一样
    func testSameSeedSameBoard() {
        for level in TileGame.Level.allCases {
            XCTAssertEqual(TileGame(level: level, seed: 12345), TileGame(level: level, seed: 12345))
            XCTAssertNotEqual(TileGame(level: level, seed: 12345).board, TileGame(level: level, seed: 54321).board)
        }
    }

    /// 张数、每种牌的张数都是 3 的倍数，不超过这一档最多几张，种类不超过这一档几种
    func testCountsComeInThrees() {
        for level in TileGame.Level.allCases {
            let spec = TileGame.Spec(level)
            for seed in UInt64(0)..<40 {
                let game = TileGame(level: level, seed: seed)
                XCTAssertEqual(game.total % 3, 0)
                XCTAssertLessThanOrEqual(game.total, spec.most)
                XCTAssertGreaterThanOrEqual(game.total, 9, "\(level) \(seed) 太少")
                let counts = Dictionary(grouping: game.board, by: \.kind).mapValues(\.count)
                XCTAssertTrue(counts.values.allSatisfy { $0 % 3 == 0 }, "\(level) \(seed) \(counts)")
                XCTAssertTrue(counts.keys.allSatisfy { (0..<spec.kinds).contains($0) })
                XCTAssertEqual(Set(game.board.map(\.id)).count, game.total, "编号不重复")
                XCTAssertTrue(game.board.allSatisfy { $0.x >= 0 && $0.x + TileGame.size <= TileGame.width && $0.y >= 0 })
            }
        }
    }

    /// 每一局都消得完：照着摆牌时定好的消法一张张拿，每张都拿得起来、中途不会满，最后全消完
    func testEveryBoardCanBeCleared() {
        for level in TileGame.Level.allCases {
            for seed in UInt64(0)..<60 {
                var game = TileGame(level: level, seed: seed)
                XCTAssertEqual(game.solution.count, game.total)
                for id in game.solution {
                    XCTAssertTrue(game.pick(id), "\(level) \(seed)：\(id) 拿不起来")
                    XCTAssertNotEqual(game.status, .lost, "\(level) \(seed)：槽满了")
                }
                game.settle()
                XCTAssertEqual(game.status, .won, "\(level) \(seed)")
                XCTAssertEqual(game.cleared, game.total)
            }
        }
    }

    /// 一张牌一摞的小局：A 压着 B
    private func small(_ kinds: [Int]) -> TileGame {
        TileGame(level: .easy, seed: 0, tiles: kinds.enumerated().map { i, kind in
            TileGame.Tile(id: i, kind: kind, x: (i % 7) * 4, y: (i / 7) * 4, z: 0)
        })
    }

    func testCoveredTilesCannotBePicked() {
        var game = TileGame(level: .easy, seed: 0, tiles: [
            TileGame.Tile(id: 0, kind: 0, x: 0, y: 0, z: 0),
            TileGame.Tile(id: 1, kind: 1, x: 2, y: 2, z: 1),
            TileGame.Tile(id: 2, kind: 2, x: 4, y: 0, z: 0),
        ])
        XCTAssertEqual(game.freeIDs, [1], "错开半张也算压着")
        XCTAssertFalse(game.pick(0))
        XCTAssertTrue(game.pick(1))
        XCTAssertEqual(game.freeIDs, [0, 2])
    }

    /// 放进槽里挨着一样的；凑齐三张先标出来，下一步（或 settle）再消掉
    func testTrayGroupsAndClearsTriples() {
        var game = small([0, 1, 0, 2, 0, 1, 1, 2, 2])
        game.pick(0)
        game.pick(1)
        game.pick(2)
        XCTAssertEqual(game.tray.map(\.kind), [0, 0, 1])
        game.pick(4)
        XCTAssertEqual(game.clearing, [0, 2, 4])
        XCTAssertFalse(game.canUndo, "凑齐消掉的不能撤回")
        XCTAssertEqual(game.waiting, 1)
        game.pick(3)
        XCTAssertEqual(game.tray.map(\.kind), [1, 2], "上一步凑齐的消掉了")
        XCTAssertEqual(game.cleared, 3)
        for id in [5, 6, 7, 8] { game.pick(id) }
        game.settle()
        XCTAssertEqual(game.status, .won)
    }

    /// 槽里放满七张还没凑齐就输了；撤回、移出能接着玩，各只能用一次
    func testFullTrayLosesAndToolsRevive() {
        var game = small([0, 1, 2, 3, 4, 5, 6, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6])
        for id in 0..<7 { game.pick(id) }
        XCTAssertEqual(game.status, .lost)
        XCTAssertFalse(game.pick(7), "输了不能再拿")
        XCTAssertTrue(game.canUndo)
        XCTAssertTrue(game.undo())
        XCTAssertFalse(game.canUndo)
        XCTAssertEqual(game.status, .playing)
        XCTAssertEqual(game.tray.count, 6)
        XCTAssertTrue(game.board.contains { $0.id == 6 }, "撤回的放回牌堆")
        XCTAssertFalse(game.undo(), "撤回只能用一次")
        XCTAssertTrue(game.moveOut())
        XCTAssertEqual(game.parked.map(\.kind), [0, 1, 2])
        XCTAssertEqual(game.tray.map(\.kind), [3, 4, 5])
        XCTAssertFalse(game.moveOut(), "移出只能用一次")
        XCTAssertTrue(game.pick(0), "移出去的能点回槽里")
        XCTAssertEqual(game.tray.map(\.kind), [3, 4, 5, 0], "槽里没有一样的就放最后")
    }

    func testShuffleKeepsKindsAndPlaces() {
        var game = TileGame(level: .normal, seed: 7)
        let before = game.board
        XCTAssertTrue(game.shuffle())
        XCTAssertFalse(game.shuffle(), "洗牌只能用一次")
        XCTAssertEqual(game.board.map(\.id), before.map(\.id))
        XCTAssertEqual(game.board.map(\.x), before.map(\.x))
        XCTAssertEqual(game.board.map(\.kind).sorted(), before.map(\.kind).sorted())
        XCTAssertNotEqual(game.board.map(\.kind), before.map(\.kind))
    }

    func testChallengeCodes() {
        for level in TileGame.Level.allCases {
            for seed: UInt64 in [0, 1, 99_999, TileGame.seedLimit - 1] {
                let code = TileGame.code(level: level, seed: seed)
                XCTAssertEqual(code.count, 6)
                XCTAssertFalse(code.contains { "01IO".contains($0) })
                let decoded = TileGame.decode(code)
                XCTAssertEqual(decoded?.level, level)
                XCTAssertEqual(decoded?.seed, seed)
            }
        }
        let code = TileGame.code(level: .hard, seed: 2026)
        let message = "我在「叠叠消」今日挑战用 2分13秒 通关了！挑战码 \(code)，来比比"
        XCTAssertEqual(TileGame.decode(message)?.seed, 2026, "从别人发的一整段话里认出挑战码")
        XCTAssertEqual(TileGame.decode(" \(code.lowercased()) ")?.level, .hard, "小写、前后空格也行")
        XCTAssertNil(TileGame.decode("ABC"))
        XCTAssertNil(TileGame.decode("ZZZZZZ"), "难度不对")
    }

    func testDailySeed() {
        let today = DayKey(year: 2026, month: 10, day: 27)
        XCTAssertEqual(TileGame.dailySeed(today), TileGame.dailySeed(DayKey(year: 2026, month: 10, day: 27)))
        XCTAssertNotEqual(TileGame.dailySeed(today), TileGame.dailySeed(DayKey(year: 2026, month: 10, day: 28)))
        XCTAssertLessThan(TileGame.dailySeed(today), TileGame.seedLimit)
    }

    func testRaceRanking() {
        let players = [
            TileRace.Player(id: "a", name: "甲", cleared: 30, total: 99, status: .lost, seconds: 50),
            TileRace.Player(id: "b", name: "乙", cleared: 99, total: 99, status: .won, seconds: 120),
            TileRace.Player(id: "c", name: "丙", cleared: 99, total: 99, status: .won, seconds: 95),
            TileRace.Player(id: "d", name: "丁", cleared: 45, total: 99, status: .playing, seconds: 80),
        ]
        XCTAssertEqual(TileRace.ranking(players).map(\.name), ["丙", "乙", "丁", "甲"])
        XCTAssertFalse(TileRace.finished(players))
        XCTAssertTrue(TileRace.finished(players.filter { $0.status != .playing }))
        XCTAssertFalse(TileRace.finished([]))
    }

    func testRaceMessagesRoundTrip() throws {
        let messages: [TileRace.Message] = [
            .hello(TileRace.Player(id: "a", name: "甲")),
            .lobby([TileRace.Player(id: "a", name: "甲"), TileRace.Player(id: "b", name: "乙")]),
            .start(round: 2, level: .normal, seed: 123),
            .progress(round: 2, player: TileRace.Player(id: "a", name: "甲", cleared: 9, total: 99, status: .playing, seconds: 12.5)),
        ]
        for message in messages {
            let data = try JSONEncoder().encode(message)
            XCTAssertEqual(try JSONDecoder().decode(TileRace.Message.self, from: data), message)
        }
    }
}
