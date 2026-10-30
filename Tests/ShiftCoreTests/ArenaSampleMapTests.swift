import XCTest
@testable import ShiftCore

final class ArenaSampleMapTests: XCTestCase {
    func testReleasedMapIdentitySymmetryAndCompatiblePools() {
        let map = ArenaMap.twinGates
        XCTAssertEqual(map.width, 21)
        XCTAssertEqual(map.height, 29)
        XCTAssertEqual(map.center, V2(10.5, 14.5))
        XCTAssertEqual(map.spawns.map(\.count), [3, 3])
        XCTAssertTrue(map.spawns[0].allSatisfy { $0.y == 25.5 })
        XCTAssertTrue(map.spawns[1].allSatisfy { $0.y == 3.5 })
        XCTAssertEqual(ArenaMap.named(map.id)?.id, map.id)
        let compatible: Set<ArenaGame.Mode> = [.teamFight, .stars, .bounty, .zone, .knockout]
        for mode in ArenaGame.Mode.allCases {
            let supported = compatible.contains(mode)
            XCTAssertEqual(ArenaGame(mode: mode, entrants: [], seed: 1, map: map).map.id == map.id, supported,
                           "Twin Gates must be accepted only by compatible released modes: \(mode)")
            XCTAssertEqual(ArenaMap.playPool(for: mode).contains { $0.id == map.id }, supported)
            XCTAssertEqual(ArenaMap.selectionPool(for: mode).contains { $0.id == map.id }, supported)
            XCTAssertFalse(ArenaMap.pool(for: mode).contains { $0.id == map.id },
                           "Legacy peers must keep their original compatible pool")
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

    func testRealTouchApproachLaneClearsWallsWithGestureTolerance() {
        let map = ArenaMap.twinGates
        let radius = ArenaGame.fighterRadius
        // The UI flow approaches from the first southern spawn via x=7,
        // then turns toward the objective at y=14.5. Cover the allowed
        // horizontal alignment error and northward gesture overshoot, not
        // just the ideal waypoint centers.
        for x in stride(from: 6.65, through: 7.35, by: 0.05) {
            for y in stride(from: 14.2, through: 25.5, by: 0.05) {
                XCTAssertFalse(map.collides(V2(x, y), radius: radius),
                               "Approach lane blocks the fighter at \(x), \(y)")
            }
        }
        for y in stride(from: 14.2, through: 15.2, by: 0.05) {
            for x in stride(from: 6.65, through: 10.9, by: 0.05) {
                XCTAssertFalse(map.collides(V2(x, y), radius: radius),
                               "Objective entrance blocks the fighter at \(x), \(y)")
            }
        }
        let spawn = map.spawns[0][0]
        for x in stride(from: spawn.x, through: 7.35, by: 0.05) {
            XCTAssertFalse(map.collides(V2(x, spawn.y), radius: radius))
        }
        XCTAssertTrue(map.inBush(V2(7, 16.5)))
        XCTAssertTrue(map.inBush(V2(7, 17.5)))
    }
}
