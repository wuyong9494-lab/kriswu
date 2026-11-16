import Foundation
import XCTest
@testable import ShiftCore

final class DuelSerpentAbilityModelsTests: XCTestCase {
    private func directory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["SERPENT_ABILITY_MODELS_DIR"] else {
            throw XCTSkip("Authenticated original independent D13 models are required")
        }
        return URL(fileURLWithPath: path)
    }
    private func data() throws -> Data {
        try Data(contentsOf: directory().appendingPathComponent(DuelSerpentAbilityModels.documentName))
    }
    private func binding() throws -> DuelSerpentAbilityModels { try .init(document: data()) }
    private let owner = DuelWeaponPoint(x: 3.5, y: 1.1, z: 0.2)
    private let enemy = DuelWeaponPoint(x: 5.3, y: 1.2, z: -0.1)

    func testActualFiveModelSourceClocksCropsRadiiAndAttackWindows() throws {
        let models = try binding()
        let last = [42, 10, 20, 174, 182], firstAttack = [0, 0, 0, 8, 8], lastAttack = [42, 10, 20, 149, 149]
        let radii = [[1.5], [0.4], [0.75], [0.07, 0.07, 0.07], [0.07, 0.07, 0.07]]
        for (index, kind) in DuelSerpentAbilityModels.Kind.allCases.enumerated() {
            let birth = try XCTUnwrap(models.birth(kind: kind, ownerPelvis: owner, targetPelvis: enemy, direction: 1))
            for tick in 0...last[index] {
                let snapshot = try XCTUnwrap(models.sourceSnapshot(birth: birth, motionTick: tick))
                XCTAssertEqual(snapshot.kind, kind)
                XCTAssertEqual(snapshot.capsules.map(\.radiusMeters), radii[index])
                XCTAssertEqual(snapshot.insideSourceAttackInterval, (firstAttack[index]...lastAttack[index]).contains(tick))
                XCTAssertTrue(snapshot.sourceHitTags.contains("Hit_Shadow_Attack"))
                XCTAssertTrue(snapshot.sourceHitTags.contains("Unblockable"))
            }
            XCTAssertNil(models.sourceSnapshot(birth: birth, motionTick: -1))
            XCTAssertNil(models.sourceSnapshot(birth: birth, motionTick: last[index] + 1))
            XCTAssertNil(models.sourceSnapshot(birth: birth, motionTick: Int.max))
        }
    }

    func testBirthUsesOnlyAuthoredAlignAxesAndOriginalFixedBloomFacing() throws {
        let models = try binding()
        for facing in [-1, 1] {
            let helmet = try XCTUnwrap(models.birth(kind: .helmet, ownerPelvis: owner, targetPelvis: enemy, direction: facing))
            let vine1 = try XCTUnwrap(models.birth(kind: .vine1, ownerPelvis: owner, targetPelvis: enemy, direction: facing))
            let vine2 = try XCTUnwrap(models.birth(kind: .vine2, ownerPelvis: owner, targetPelvis: enemy, direction: facing))
            let push = try XCTUnwrap(models.birth(kind: .push, ownerPelvis: owner, targetPelvis: enemy, direction: facing))
            let bloom = try XCTUnwrap(models.birth(kind: .bloom, ownerPelvis: owner, targetPelvis: enemy, direction: facing))
            XCTAssertEqual(helmet.origin, .init(x: owner.x + 1.6 * Double(facing)))
            XCTAssertEqual(vine1.origin, .init(x: owner.x - 2.5 * Double(facing)))
            XCTAssertEqual(vine2.origin, .init(x: owner.x - 1.75 * Double(facing)))
            XCTAssertEqual(push.origin, .init(x: enemy.x, y: enemy.y))
            XCTAssertEqual(bloom.origin, push.origin)
            XCTAssertEqual(bloom.direction, -1)
            let previous = models.sourceSnapshot(birth: vine1, motionTick: 60)
            _ = models.birth(kind: .vine1, ownerPelvis: .init(x: 80), targetPelvis: enemy, direction: -facing)
            XCTAssertEqual(models.sourceSnapshot(birth: vine1, motionTick: 60), previous,
                           "Rendering and another birth cannot relocate an existing source model")
        }
        XCTAssertNil(models.birth(kind: .helmet, ownerPelvis: owner, targetPelvis: enemy, direction: 0))
        XCTAssertNil(models.birth(kind: .helmet, ownerPelvis: .init(x: .infinity), targetPelvis: enemy, direction: 1))
    }

    func testWorldCapsulesMatchIndependentOriginalArrayAndXMLOracleInBothFacings() throws {
        struct Oracle: Decodable {
            struct Case: Decodable {
                struct Capsule: Decodable {
                    let id: String
                    let radiusMeters: Double
                    let base, tip: DuelWeaponPoint
                }
                let role: String
                let requestedDirection, direction, tick: Int
                let attackActive: Bool
                let birthOriginMeters: DuelWeaponPoint
                let capsules: [Capsule]
            }
            let schema: String
            let ownerPelvisMeters, enemyPelvisMeters: DuelWeaponPoint
            let cases: [Case]
        }
        let models = try binding()
        let raw = try Data(contentsOf: directory().appendingPathComponent("world-capsules-oracle-private.json"))
        let oracle = try JSONDecoder().decode(Oracle.self, from: raw)
        XCTAssertEqual(oracle.schema, "d13-world-capsules-source-oracle-v1")
        XCTAssertEqual(oracle.cases.count, 38)
        XCTAssertEqual(Set(oracle.cases.map(\.role)).count, 5)
        var endpoints = 0
        func point(_ actual: DuelWeaponPoint, _ expected: DuelWeaponPoint) {
            XCTAssertEqual(actual.x, expected.x, accuracy: 4e-8)
            XCTAssertEqual(actual.y, expected.y, accuracy: 4e-8)
            XCTAssertEqual(actual.z, expected.z, accuracy: 4e-8)
        }
        for row in oracle.cases {
            let kind = try XCTUnwrap(DuelSerpentAbilityModels.Kind(rawValue: String(row.role.dropFirst("serpentSummon_".count))))
            let birth = try XCTUnwrap(models.birth(kind: kind, ownerPelvis: oracle.ownerPelvisMeters,
                targetPelvis: oracle.enemyPelvisMeters, direction: row.requestedDirection))
            XCTAssertEqual(birth.direction, row.direction)
            point(birth.origin, row.birthOriginMeters)
            let snapshot = try XCTUnwrap(models.sourceSnapshot(birth: birth, motionTick: row.tick))
            XCTAssertEqual(snapshot.insideSourceAttackInterval, row.attackActive)
            XCTAssertEqual(snapshot.capsules.count, row.capsules.count)
            for (actual, expected) in zip(snapshot.capsules, row.capsules) {
                XCTAssertEqual(actual.id, expected.id)
                XCTAssertEqual(actual.radiusMeters, expected.radiusMeters)
                point(actual.base, expected.base); point(actual.tip, expected.tip)
                endpoints += 2
            }
        }
        XCTAssertEqual(endpoints, 156)
    }

    func testChangedModelIdentityOrUnreviewedCollisionAndTimingCannotPass() throws {
        let actual = try data()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: actual) as? [String: Any])
        func rejected(_ mutate: (inout [String: Any]) -> Void, file: StaticString = #filePath, line: UInt = #line) throws {
            var changed = object; mutate(&changed)
            let bytes = try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys])
            XCTAssertLessThan(bytes.count, DuelSerpentAbilityModels.maximumDocumentBytes, file: file, line: line)
            XCTAssertThrowsError(try DuelSerpentAbilityModels(document: bytes), file: file, line: line)
        }
        try rejected { $0["sourceConfigurationSHA256"] = String(repeating: "0", count: 64) }
        try rejected { object in
            var tracks = object["summonTracks"] as! [[String: Any]]
            tracks[1]["frames"] = 31; object["summonTracks"] = tracks
        }
        try rejected { object in
            var tracks = object["summonTracks"] as! [[String: Any]]
            var edges = tracks[0]["collisionEdges"] as! [[String: Any]]
            edges[0]["radiusMillimeters"] = 750; tracks[0]["collisionEdges"] = edges; object["summonTracks"] = tracks
        }
        try rejected { object in
            var models = object["models"] as! [[String: Any]]
            var origin = models[3]["origin"] as! [String: Any]
            origin["selectedAlignAxes"] = ["X", "Y"]; models[3]["origin"] = origin; object["models"] = models
        }
        try rejected { object in
            var models = object["models"] as! [[String: Any]]
            var intervals = models[3]["sourceAttackIntervals"] as! [[String: Any]]
            intervals[0]["effective"] = ["startTick": 0, "endTick": 174]
            models[3]["sourceAttackIntervals"] = intervals; object["models"] = models
        }
    }
}
