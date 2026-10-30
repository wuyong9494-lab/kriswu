import XCTest
@testable import ShiftCore

final class ArenaMovementPredictionTests: XCTestCase {
    private func fixture() -> ArenaGame {
        let map = ArenaMap(rows: ["#......o", "#.......", "#.......", "#.......", "#.......", "#.......", "#.......", "#......."])
        var game = ArenaGame(mode: .showdown, entrants: [
            .init(name: "player", brawler: .ranger, isBot: false, team: 0)
        ], seed: 1, map: map)
        game.boxes = [.init(pos: V2(3, 3), health: 3600)]
        return game
    }

    func testPredictionAndHostAgreeAlongBoxAndWallPaths() {
        for (start, delta) in [(V2(2, 3), V2(0.2, 0)),
                               (V2(1.45, 2.4), V2(0.03, 0.06)),
                               (V2(2.2, 2.2), V2(0.04, 0.04))] {
            var host = fixture()
            XCTAssertEqual(host.map.id, "custom")
            host.adjust(0) { $0.pos = start }
            var predicted = start
            for _ in 0..<120 {
                predicted = host.walkingPosition(from: predicted, by: delta)
                host.walk(0, by: delta)
                XCTAssertEqual(predicted, host.fighters[0].pos)
                XCTAssertFalse(host.map.collides(predicted, radius: ArenaGame.fighterRadius))
                XCTAssertGreaterThanOrEqual(predicted.distance(to: host.boxes[0].pos), 0.88 - 1e-9)
            }
        }
    }

    func testLiveBoxBlocksButSnapshotDestroyedBoxAllowsPassage() {
        var host = fixture()
        let start = V2(2, 3), delta = V2(0.2, 0)
        let blocked = host.walkingPosition(from: start, by: delta)
        XCTAssertEqual(blocked.x, 2.12, accuracy: 1e-9)
        XCTAssertNotEqual(blocked, ArenaGame.walk(from: start, by: delta, on: host.map))
        host.boxes[0].health = 0
        var client = fixture()
        client.apply(host.snapshot(events: [], acks: [:]))
        XCTAssertEqual(client.walkingPosition(from: start, by: delta), start + delta)
    }
}
