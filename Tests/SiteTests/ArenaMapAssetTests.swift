import XCTest
import SceneKit
@testable import ShiftReminder

@MainActor
final class ArenaMapAssetTests: XCTestCase {
    func testEveryPlayableMapHasBundledDressingWithinItsTileEnvelope() throws {
        let maps = Dictionary((ArenaMap.all + ArenaMap.expandedMaps + [.twinGates]).map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first }).values
        for map in maps {
            XCTAssertNotNil(ArenaMapAssets.palettes[ArenaMapAssets.baseID(map.id)], map.id)
            let palette = ArenaMapAssets.palette(for: map)
            for file in palette.files {
                XCTAssertNotNil(ArenaModels.shared.prop(file), "\(map.id): \(file)")
            }
            let scenery = ArenaMapAssets.scenery(map)
            XCTAssertLessThanOrEqual(scenery.childNodes.count,
                ArenaMapAssets.borderLimit + ArenaMapAssets.detailLimit, map.id)
            let placements = ArenaMapAssets.detailPlacements(in: map)
            XCTAssertEqual(Set(placements.map { $0.y * map.width + $0.x }).count, placements.count)
            for place in placements {
                XCTAssertEqual(map.tile(place.x, place.y), .floor, map.id)
                let p = V2(Double(place.x) + 0.5, Double(place.y) + 0.5)
                XCTAssertGreaterThanOrEqual((map.center - p).length, 2.5, map.id)
                for spawn in map.spawns.flatMap({ $0 }) {
                    XCTAssertGreaterThanOrEqual((spawn - p).length, 2.5, map.id)
                }
            }
            for node in scenery.childNodes {
                XCTAssertNil(node.physicsBody)
                let (low, high) = node.boundingBox
                let p = node.simdPosition
                if node.name?.hasPrefix("vendor-ground-detail-") == true {
                    XCTAssertLessThanOrEqual(high.y - low.y, 0.1601)
                    XCTAssertLessThanOrEqual(high.x - low.x, 0.3001)
                    XCTAssertLessThanOrEqual(high.z - low.z, 0.3001)
                } else if node.name?.hasPrefix("vendor-paving-") == true {
                    XCTAssertLessThanOrEqual(high.y - low.y, 0.0121)
                    XCTAssertLessThanOrEqual(high.x - low.x, 0.8801)
                    XCTAssertLessThanOrEqual(high.z - low.z, 0.8801)
                } else {
                    XCTAssertTrue(p.x < 0 || p.x > Float(map.width) || p.z < 0 || p.z > Float(map.height))
                }
            }
            let wood = ArenaMapAssets.woodPavingCells(in: map)
            if palette.pavingIsWood {
                XCTAssertEqual(wood, Set(placements.filter(\.paving).map { $0.y * map.width + $0.x }))
            } else {
                XCTAssertTrue(wood.isEmpty)
            }
        }
    }

    func testMapWallPalettesKeepImportedObstaclesInsideExistingSolidCells() throws {
        for map in ArenaMap.all + ArenaMap.expandedMaps {
            var cells: [(x: Int, y: Int, kind: ArenaArt.Wall)] = []
            for y in 0..<map.height {
                for x in 0..<map.width where map.tile(x, y) == .wall && !map.isChest(x, y) {
                    cells.append((x, y, .stone))
                }
            }
            let walls = ArenaArt.walls(cells, palette: ArenaMapAssets.palette(for: map))
            XCTAssertLessThanOrEqual(walls.childNodes.count, ArenaMapAssets.wallLimit)
            for node in walls.childNodes {
                let p = node.simdPosition
                XCTAssertEqual(map.tile(Int(p.x), Int(p.z)), .wall)
                XCTAssertFalse(map.isChest(Int(p.x), Int(p.z)))
                let (low, high) = node.boundingBox
                XCTAssertLessThanOrEqual(high.x - low.x, 0.9601)
                XCTAssertLessThanOrEqual(high.z - low.z, 0.9601)
                XCTAssertLessThanOrEqual(high.y - low.y, 1.0201)
                XCTAssertEqual(low.y, 0, accuracy: 0.0001)
            }
        }
    }
}
