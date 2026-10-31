import XCTest
@testable import ShiftCore

final class ArenaImportedRuntimeTests: XCTestCase {
    private let evidence = "Synthetic integration fixture; no external client records."

    private func fixture(_ mode: ArenaGame.Mode) -> ArenaImportedMap {
        let floor = ArenaImportedMap.Terrain(id: "floor", blocksMovement: false, blocksProjectiles: false,
            concealsHeroes: false, destructible: false, evidence: evidence,
            runtimeBehavior: .init(visualKind: .floor, destroyedByNormalWeapons: false, destroyedInOvertime: false, evidence: evidence))
        let spawns = [ArenaImportedMap.SpawnGroup(team: 0, cells: [.init(1, 9), .init(5, 9), .init(9, 9)], evidence: evidence),
                      .init(team: 1, cells: [.init(1, 1), .init(5, 1), .init(9, 1)], evidence: evidence)]
        return ArenaImportedMap(identity: .init(namespace: "fixture", dataset: "runtime", location: mode.rawValue, layout: "grid"),
            title: "Synthetic runtime map", runtimeTheme: "stone", sourceRows: Array(repeating: "...........", count: 11),
            terrain: [floor], bindings: [.init(symbol: ".", terrainID: "floor", evidence: evidence)], spawns: spawns,
            objectives: .init(center: V2(5.5, 5.5), evidence: evidence),
            mode: .init(sourceMode: "fixture", runtimeMode: mode.rawValue, teamCount: 2, teamSize: 3, evidence: evidence),
            mappingEvidence: evidence)
    }

    private func entrants(_ plan: ArenaImportedMap.RuntimePlan, reversed: Bool = false) -> [ArenaGame.Entrant] {
        let result = plan.spawns.flatMap { group in
            group.cells.enumerated().map { slot, _ in
                ArenaGame.Entrant(name: "\(group.team):\(slot)", brawler: .ranger, isBot: false, team: group.team)
            }
        }
        return reversed ? result.reversed() : result
    }

    func testTenSoloTeamsKeepExplicitRosterPositionsAndSourceBoxes() throws {
        var source = fixture(.showdown)
        source.mode?.teamCount = 10
        source.mode?.teamSize = 1
        source.spawns = (0..<10).map { .init(team: $0, cells: [.init($0, 0)], evidence: evidence) }
        source.objectives?.powerBoxes = [
            .init(cell: .init(3, 5), health: 4300, collisionRadius: 145.0 / 300, spawnProbability: 1, evidence: evidence),
            .init(cell: .init(7, 5), health: 4300, collisionRadius: 145.0 / 300, spawnProbability: 0, evidence: evidence)]
        let plan = try source.runtimePlan()
        let game = try ArenaGame(importedPlan: plan, entrants: entrants(plan, reversed: true), seed: 99)
        XCTAssertEqual(game.fighters.count, 10)
        XCTAssertEqual(game.fighters.map(\.team), Array((0..<10).reversed()))
        XCTAssertEqual(game.fighters.first?.pos, V2(9.5, 0.5), "The original explicit team survives the classic constructor's index-based assignment.")
        XCTAssertEqual(game.teamKills.count, 10)
        XCTAssertEqual(game.score.count, 10)
        XCTAssertEqual(game.boxes.count, 1, "No procedural host boxes may be added to a reviewed source layout.")
        XCTAssertEqual(game.boxes[0].pos, V2(3.5, 5.5))
        XCTAssertEqual(game.boxes[0].health, 4300)
        XCTAssertEqual(game.powerBoxMaximumHealth(game.boxes[0]), 4300)
        XCTAssertEqual(game.powerBoxCollisionRadius(game.boxes[0]), 145.0 / 300, accuracy: 1e-12)
        XCTAssertThrowsError(try ArenaGame(importedPlan: plan, entrants: Array(entrants(plan).prefix(6)), seed: 99))
    }

    func testSafeUsesSourceHealthCircularCollisionAndSweptProjectileHit() throws {
        var source = fixture(.heist)
        source.objectives?.bases = [.init(team: 1, cells: [.init(5, 2)]), .init(team: 0, cells: [.init(5, 8)])]
        source.mode?.matchRules = .init(evidence: ["safeBaseHealth": evidence, "safeCollisionRadius": evidence],
                                       safeBaseHealth: 40000, safeCollisionRadius: 160.0 / 300)
        let plan = try source.runtimePlan()
        var game = try ArenaGame(importedPlan: plan, entrants: entrants(plan), seed: 99)
        let index = try XCTUnwrap(game.chests.firstIndex { $0.team == 1 })
        let center = game.chests[index].center
        XCTAssertEqual(game.chests[index].health, 40000)
        XCTAssertFalse(game.terrainState!.blocksMovement(at: center), "The live safe, not a fabricated terrain wall, owns collision.")
        XCTAssertTrue(game.importedSafeCollision(at: center + V2(0.6, 0), radius: 0.2))
        XCTAssertFalse(game.importedSafeCollision(at: center + V2(0.9, 0), radius: 0.2))
        XCTAssertNil(game.importedSafeIndex(at: center, excludingTeam: 1))
        let hit = game.importedSafeHit(from: center + V2(-3, 0), to: center + V2(3, 0), projectileRadius: 0.1, excludingTeam: 0)
        XCTAssertEqual(hit?.index, index)
        XCTAssertEqual(try XCTUnwrap(hit?.point.x), center.x - 160.0 / 300 - 0.1, accuracy: 1e-10)
        game.chests[index].health = 0
        XCTAssertFalse(game.importedSafeCollision(at: center, radius: 0.2))
        XCTAssertNil(game.importedSafeHit(from: center + V2(-3, 0), to: center + V2(3, 0), projectileRadius: 0.1))
    }

    func testFootballKeepsSeparateDeathRespawnsAndRunsOvertimeOnce() throws {
        var source = fixture(.ball)
        source.objectives?.goals = [.init(team: 1, cells: (3...7).map { .init($0, 0) }),
                                    .init(team: 0, cells: (3...7).map { .init($0, 10) })]
        source.respawns = [.init(team: 0, cells: [.init(3, 10), .init(5, 10), .init(7, 10)], evidence: evidence),
                           .init(team: 1, cells: [.init(3, 0), .init(5, 0), .init(7, 0)], evidence: evidence)]
        source.terrain.append(.init(id: "overtimeWall", blocksMovement: true, blocksProjectiles: true,
            concealsHeroes: false, destructible: false, evidence: evidence,
            runtimeBehavior: .init(visualKind: .wall, destroyedByNormalWeapons: false, destroyedInOvertime: true, evidence: evidence)))
        source.bindings.append(.init(symbol: "I", terrainID: "overtimeWall", evidence: evidence))
        source.sourceRows[4] = "....I......"
        source.mode?.rawProperties["OvertimeHasGoldenGoal"] = "true"
        source.mode?.matchRules = .init(matchDuration: 210, evidence: ["matchDuration": evidence, "overtimeStartsAt": evidence,
            "overtimeGoldenGoal": evidence], overtimeStartsAt: 150, overtimeGoldenGoal: true)
        let plan = try source.runtimePlan()
        var game = try ArenaGame(importedPlan: plan, entrants: entrants(plan), seed: 99)
        XCTAssertEqual(game.importedInitialSpawn(for: 0), V2(1.5, 9.5))
        XCTAssertEqual(game.importedRespawn(for: 0), V2(3.5, 10.5))
        XCTAssertFalse(game.terrainState!.blocksMovement(at: V2(3.5, 10.5)), "A goal cell must not turn a real respawn into a wall.")
        game.time = 149.99
        XCTAssertFalse(game.updateImportedOvertime())
        XCTAssertFalse(game.usesImportedGoldenGoal)
        game.time = 150
        XCTAssertTrue(game.updateImportedOvertime())
        XCTAssertFalse(game.terrainState!.blocksMovement(4, 4))
        XCTAssertTrue(game.usesImportedGoldenGoal)
        let revision = game.terrainState!.revision
        XCTAssertFalse(game.updateImportedOvertime())
        XCTAssertEqual(game.terrainState!.revision, revision)
        source.mode?.matchRules?.overtimeGoldenGoal = false
        XCTAssertTrue(source.runtimeValidationIssues().contains { $0.code == .contradictoryProperty })
    }

    func testGameHotZoneHookUsesAllOriginalCirclesAndDeclaresWinner() throws {
        var source = fixture(.zone)
        source.objectives?.captureZones = [.init(id: "left", center: V2(2.5, 5.5), radius: 1, evidence: evidence),
                                           .init(id: "right", center: V2(8.5, 5.5), radius: 1, evidence: evidence)]
        source.mode?.matchRules = .init(evidence: ["zoneCaptureSeconds": evidence], zoneCaptureSeconds: 10)
        let plan = try source.runtimePlan()
        var game = try ArenaGame(importedPlan: plan, entrants: entrants(plan), seed: 99)
        game.fighters[0].pos = V2(2.5, 5.5)
        game.fighters[1].pos = V2(8.5, 5.5)
        game.fighters[3].pos = V2(2.5, 5.5)
        XCTAssertTrue(game.updateImportedZones(5))
        XCTAssertEqual(game.zoneProgress, [50, 25])
        XCTAssertNil(game.result)
        XCTAssertTrue(game.updateImportedZones(5))
        XCTAssertEqual(game.zoneProgress, [100, 50])
        XCTAssertEqual(game.result, .team(0))
    }
}
