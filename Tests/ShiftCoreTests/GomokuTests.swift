import XCTest
@testable import ShiftCore

final class GomokuTests: XCTestCase {
    private func at(_ row: Int, _ column: Int) -> Int { row * Gomoku.size + column }

    /// 黑下 blacks、白下 whites，交替着下（白的先下完了就只下黑的，反过来也一样）
    private func play(black: [Int], white: [Int]) -> Gomoku {
        var game = Gomoku()
        var b = black[...], w = white[...]
        while !b.isEmpty || !w.isEmpty {
            if game.next == .black, let move = b.popFirst() {
                XCTAssertTrue(game.place(move))
            } else if game.next == .white, let move = w.popFirst() {
                XCTAssertTrue(game.place(move))
            } else {
                break
            }
        }
        return game
    }

    func testFiveInEveryDirectionWins() {
        let lines: [[Int]] = [
            (0..<5).map { at(7, 3 + $0) },
            (0..<5).map { at(2 + $0, 9) },
            (0..<5).map { at(3 + $0, 3 + $0) },
            (0..<5).map { at(3 + $0, 11 - $0) },
        ]
        for line in lines {
            let whites = (0..<4).map { at(14, $0 * 2) }
            let game = play(black: line, white: whites)
            XCTAssertEqual(game.winner, .black)
            XCTAssertEqual(game.line, line.sorted())
            XCTAssertTrue(game.isOver)
        }
    }

    func testOverlineWinsAndFourDoesNot() {
        var game = play(black: [at(7, 1), at(7, 2), at(7, 3), at(7, 5), at(7, 6)],
                        white: [at(0, 0), at(0, 2), at(0, 4), at(0, 6)])
        XCTAssertNil(game.winner, "中间空着一个，还没连上")
        game.place(at(1, 1))
        game.place(at(7, 4))
        XCTAssertEqual(game.winner, .black, "中间补上连成六个也算赢（不设禁手）")
        XCTAssertEqual(game.line.count, 6)
    }

    func testIllegalMoves() {
        var game = Gomoku()
        XCTAssertTrue(game.place(Gomoku.center))
        XCTAssertFalse(game.place(Gomoku.center), "有子的地方不能下")
        XCTAssertFalse(game.place(-1))
        XCTAssertFalse(game.place(Gomoku.size * Gomoku.size))
        XCTAssertEqual(game.next, .white)
        game.resign(.white)
        XCTAssertEqual(game.winner, .black)
        XCTAssertFalse(game.place(0), "结束了不能再下")
    }

    func testUndoAndCoding() throws {
        var game = play(black: [at(7, 7), at(7, 8)], white: [at(8, 8)])
        game.undo()
        XCTAssertEqual(game.moves, [at(7, 7), at(8, 8)])
        XCTAssertEqual(game.next, .black)
        XCTAssertNil(game[7, 8])
        game.resign(.black)
        let decoded = try JSONDecoder().decode(Gomoku.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(decoded, game)
        XCTAssertEqual(decoded.winner, .white)
        XCTAssertEqual(decoded.resigned, .black)
    }

    func testComputerTakesTheWinAndBlocks() {
        var random = SeededRandom(seed: 1)
        for level in Gomoku.Level.allCases {
            // 黑走：自己连着四个，直接赢
            let winning = play(black: [at(7, 3), at(7, 4), at(7, 5), at(7, 6)], white: [at(0, 0), at(0, 5), at(14, 14), at(3, 3)])
            XCTAssertTrue([at(7, 2), at(7, 7)].contains(winning.suggestion(level: level, random: &random)!), "\(level)")
            // 白走：黑连着四个只剩一头，堵上
            if level != .easy {
                let blocking = play(black: [at(7, 3), at(7, 4), at(7, 5), at(7, 6)], white: [at(7, 2), at(0, 5), at(14, 14)])
                XCTAssertEqual(blocking.suggestion(level: level, random: &random), at(7, 7), "\(level)")
            }
            // 白走：黑连着活三，堵一头
            let three = play(black: [at(7, 5), at(7, 6), at(7, 7)], white: [at(0, 0), at(14, 14)])
            XCTAssertTrue([at(7, 4), at(7, 8), at(7, 3), at(7, 9)].contains(three.suggestion(level: level == .easy ? .normal : level, random: &random)!))
        }
        XCTAssertEqual(Gomoku().suggestion(level: .hard, random: &random), Gomoku.center, "第一步下天元")
    }

    /// 电脑和电脑下完一盘：不出错、能分出胜负或下满
    func testComputerPlaysWholeGames() {
        var random = SeededRandom(seed: 7)
        for (black, white) in [(Gomoku.Level.hard, Gomoku.Level.easy), (.normal, .normal), (.easy, .hard)] {
            var game = Gomoku()
            while !game.isOver {
                let level = game.next == .black ? black : white
                guard let move = game.suggestion(level: level, random: &random) else { return XCTFail("没给出下一步") }
                XCTAssertTrue(game.place(move))
            }
            XCTAssertTrue(game.winner != nil || game.isDraw)
        }
    }
}
