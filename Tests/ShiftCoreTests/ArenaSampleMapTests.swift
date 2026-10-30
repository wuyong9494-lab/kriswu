import XCTest
@testable import ShiftCore

final class ArenaSampleMapTests: XCTestCase {
    func testSampleIdentitySymmetryAndPoolIsolation() {
        let map = ArenaMap.twinGates
        XCTAssertEqual(map.width, 21)
        XCTAssertEqual(map.height, 29)
        XCTAssertEqual(map.center, V2(10.5, 14.5))
        XCTAssertEqual(map.spawns.map(\.count), [3, 3])
        XCTAssertTrue(map.spawns[0].allSatisfy { $0.y == 25.5 })
        XCTAssertTrue(map.spawns[1].allSatisfy { $0.y == 3.5 })
        XCTAssertEqual(ArenaMap.named(map.id)?.id, map.id)
        for mode in ArenaGame.Mode.allCases {
            XCTAssertFalse(ArenaMap.playPool(for: mode).contains { $0.id == map.id })
        }
        for y in 0..<map.height {
            for x in 0..<map.width {
                XCTAssertEqual(map.tile(x, y), map.tile(map.width - 1 - x, map.height - 1 - y))
            }
        }
        XCTAssertEqual(ArenaGame(mode: .zone, entrants: [], seed: 1, map: map).map.id, map.id)
    }

    func testEverySpawnCanReachObjectiveAndBothFlanksWithFighterRadius() {
        let map = ArenaMap.twinGates
        for spawn in map.spawns.flatMap({ $0 }) {
            var queue = [spawn], seen: Set<V2> = [spawn], cursor = 0
            XCTAssertFalse(map.collides(spawn, radius: ArenaGame.fighterRadius))
            while cursor < queue.count {
                let p = queue[cursor]; cursor += 1
                for d in [V2(1, 0), V2(-1, 0), V2(0, 1), V2(0, -1)] {
                    let next = p + d
                    guard !seen.contains(next), !map.collides(next, radius: ArenaGame.fighterRadius),
                          !map.collides(p + d * 0.5, radius: ArenaGame.fighterRadius) else { continue }
                    seen.insert(next); queue.append(next)
                }
            }
            for target in [map.center, V2(1.5, 14.5), V2(19.5, 14.5)] {
                XCTAssertTrue(seen.contains(target), "Spawn \(spawn) cannot reach \(target)")
            }
        }
    }
}
