import XCTest
@testable import ShiftCore

final class ArenaImportedMapTests: XCTestCase {
    private typealias Imported = ArenaImportedMap
    private let evidence = "Hand-authored test fixture; no external map data."

    private func fixture() -> Imported {
        let floor = Imported.Terrain(id: "floor", blocksMovement: false, blocksProjectiles: false,
                                     concealsHeroes: false, destructible: false, evidence: evidence)
        let wall = Imported.Terrain(id: "wall", blocksMovement: true, blocksProjectiles: true,
                                    concealsHeroes: false, destructible: false, evidence: evidence)
        let bush = Imported.Terrain(id: "bush", blocksMovement: false, blocksProjectiles: false,
                                    concealsHeroes: true, destructible: false, evidence: evidence)
        return Imported(identity: .init(namespace: "fixture", dataset: "revision1", location: "one", layout: "grid"),
                        title: "Imported fixture", runtimeTheme: "stone",
                        sourceRows: ["ppppp", "pwhpp", "ppppp", "ppppp", "ppppp"],
                        terrain: [floor, wall, bush],
                        bindings: [.init(symbol: "p", terrainID: "floor", evidence: evidence),
                                   .init(symbol: "w", terrainID: "wall", evidence: evidence),
                                   .init(symbol: "h", terrainID: "bush", evidence: evidence)],
                        spawns: [.init(team: 0, cells: [.init(0, 4), .init(2, 4), .init(4, 4)], evidence: evidence),
                                 .init(team: 1, cells: [.init(0, 0), .init(2, 0), .init(4, 0)], evidence: evidence)],
                        objectives: .init(center: V2(2.5, 2.5), evidence: evidence),
                        mode: .init(sourceMode: "fixtureTeams", runtimeMode: "teamFight", teamCount: 2, teamSize: 3, evidence: evidence),
                        mappingEvidence: evidence)
    }

    func testReviewedSubsetPreservesTerrainSpawnsAndStableIdentity() throws {
        let description = fixture()
        let decoded = try JSONDecoder().decode(Imported.self, from: JSONEncoder().encode(description))
        XCTAssertEqual(decoded, description)
        let adapted = try decoded.adapt()
        XCTAssertEqual(adapted.map.id, "imported:fixture:revision1:one")
        XCTAssertEqual(adapted.mode.rawValue, "teamFight")
        XCTAssertTrue(adapted.map.tile(1, 1) == .wall)
        XCTAssertTrue(adapted.map.tile(2, 1) == .bush)
        XCTAssertEqual(adapted.map.spawns[0], [V2(0.5, 4.5), V2(2.5, 4.5), V2(4.5, 4.5)])
        XCTAssertEqual(adapted.map.spawns[1], [V2(0.5, 0.5), V2(2.5, 0.5), V2(4.5, 0.5)])
        XCTAssertEqual(adapted.map.center, V2(2.5, 2.5))
        XCTAssertTrue(adapted.requiresRuntimeRegistration)
        XCTAssertNil(ArenaMap.named(adapted.map.id), "Validation must not mutate existing map pools.")
        XCTAssertNotEqual(adapted.map.id, "custom", "An import must not bypass registry admission.")
        var another = decoded
        another.identity.dataset = "revision2"
        XCTAssertNotEqual(another.stableID, decoded.stableID)
    }

    func testSourceCharactersCannotLeakIntoLegacySpawnOrChestSyntax() throws {
        var source = fixture()
        source.sourceRows[1] = "pCabo"
        for symbol in ["C", "a", "b", "o"] {
            source.bindings.append(.init(symbol: symbol, terrainID: "floor", evidence: evidence))
        }
        let map = try source.adapt().map
        XCTAssertTrue(map.chestSpots.isEmpty)
        XCTAssertEqual(map.spawns.count, 2)
        XCTAssertEqual(map.spawns.map(\.count), [3, 3])
        XCTAssertTrue((1...4).allSatisfy { map.tile($0, 1) == .floor })
    }

    func testUnknownCharacterFailsWithItsCoordinateInsteadOfBecomingFloor() {
        var source = fixture()
        source.sourceRows[2] = "pp?pp"
        XCTAssertThrowsError(try source.adapt()) { error in
            guard let failure = error as? Imported.ValidationFailure else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(failure.issues.contains { $0.code == .unknownSymbol && $0.path == "sourceRows[2][2]" })
        }
    }

    func testWaterDestructionAndUnresolvedBooleansAreNotFlattened() {
        var water = fixture()
        water.terrain[0].blocksMovement = true
        XCTAssertTrue(water.validationIssues().contains { $0.code == .unsupportedTerrain })
        var destructive = fixture()
        destructive.terrain[1].destructible = true
        XCTAssertTrue(destructive.validationIssues().contains { $0.code == .unsupportedTerrain })
        var unresolved = fixture()
        unresolved.terrain[0].blocksProjectiles = nil
        XCTAssertTrue(unresolved.validationIssues().contains { $0.code == .unresolvedTerrain })
        var contradiction = fixture()
        contradiction.terrain[0].rawProperties["BlocksMovement"] = "true"
        XCTAssertTrue(contradiction.validationIssues().contains { $0.code == .contradictoryProperty })
    }

    func testMissingSpawnsObjectivesAndUnreviewedMetadataFailClosed() {
        var source = fixture()
        source.spawns = []
        source.objectives = nil
        source.rawMetadataJSON = "{\"data\":[]}"
        let codes = source.validationIssues().map(\.code)
        XCTAssertTrue(codes.contains(.invalidSpawnGroups))
        XCTAssertTrue(codes.contains(.unresolvedObjectives))
        XCTAssertTrue(codes.contains(.unresolvedMetadata))
        XCTAssertThrowsError(try source.adapt())
    }

    func testExplicitCellOverrideResolvesOneCellButDuplicateBindingsAreRejected() throws {
        var source = fixture()
        source.overrides = [.init(cell: .init(1, 3), terrainID: "wall", evidence: evidence)]
        XCTAssertTrue(try source.adapt().map.tile(1, 3) == .wall)
        XCTAssertEqual(source.sourceRows[3], "ppppp")
        source.bindings.append(.init(symbol: "p", terrainID: "wall", evidence: evidence))
        XCTAssertTrue(source.validationIssues().contains { $0.code == .duplicateBinding })
        XCTAssertThrowsError(try source.adapt())
    }

    func testRaggedGridAndLossyPlacementAreRejected() {
        var ragged = fixture()
        ragged.sourceRows[2] = "pppp"
        XCTAssertTrue(ragged.validationIssues().contains { $0.code == .raggedRows })
        var hiddenSpawn = fixture()
        hiddenSpawn.spawns[0].cells = [.init(2, 1), .init(2, 4), .init(4, 4)]
        XCTAssertTrue(hiddenSpawn.validationIssues().contains { $0.code == .placementChangesTerrain })
        var reordered = fixture()
        reordered.spawns[0].cells.reverse()
        XCTAssertTrue(reordered.validationIssues().contains { $0.code == .unsupportedSpawnOrder })
    }

    func testSourceParticipantCountCannotBeSilentlyReduced() {
        var source = fixture()
        source.mode = .init(sourceMode: "tenParticipants", runtimeMode: "showdown", teamCount: 10, teamSize: 1,
                            rawProperties: ["TeamCount": "10", "TeamSize": "1"], evidence: evidence)
        XCTAssertTrue(source.validationIssues().contains { $0.code == .participantMismatch })
        XCTAssertThrowsError(try source.adapt())
    }

    func testMalformedObjectiveCoordinatesDoNotOverflowOrInventOwnership() {
        var source = fixture()
        source.mode?.runtimeMode = "heist"
        source.objectives?.bases = [.init(team: 0, cells: [.init(Int.max, 2)]),
                                    .init(team: 1, cells: [.init(2, 3)])]
        let codes = source.validationIssues().map(\.code)
        XCTAssertTrue(codes.contains(.outOfBounds))
        XCTAssertTrue(codes.contains(.invalidObjectiveRegion))
        XCTAssertThrowsError(try source.adapt())
    }

    func testRuntimePlanPreservesWaterAndDestructionThatLegacyMapCannotEncode() throws {
        var source = fixture()
        source.terrain[1].destructible = true
        for index in source.terrain.indices {
            source.terrain[index].runtimeBehavior = .init(
                visualKind: index == 1 ? .wall : index == 2 ? .bush : .floor,
                destroyedByNormalWeapons: false, destroyedInOvertime: index == 1, evidence: evidence)
        }
        source.terrain.append(.init(id: "water", blocksMovement: true, blocksProjectiles: false,
                                    concealsHeroes: false, destructible: false, evidence: evidence,
                                    runtimeBehavior: .init(visualKind: .water, destroyedByNormalWeapons: false,
                                                           destroyedInOvertime: false, evidence: evidence)))
        source.bindings.append(.init(symbol: "v", terrainID: "water", evidence: evidence))
        source.sourceRows[1] = "pwhvp"
        source.environmentThemeName = "fixtureSourceEnvironment"
        XCTAssertThrowsError(try source.adapt(), "Legacy-only callers must not lose water or destruction.")
        let decoded = try JSONDecoder().decode(Imported.self, from: JSONEncoder().encode(source))
        var state = try decoded.runtimePlan().terrainState
        XCTAssertTrue(state.blocksMovement(3, 1))
        XCTAssertFalse(state.blocksProjectiles(3, 1))
        XCTAssertTrue(state.destroy(.init(1, 1), cause: .wallBreaker))
        XCTAssertEqual(state.cell(1, 1)?.sourceSymbol, "w")
        XCTAssertEqual(try decoded.runtimePlan().environmentThemeName, "fixtureSourceEnvironment")
    }

    func testRuntimeStillRejectsUnknownCellsUnreviewedDestructionAndContradictoryOverrides() {
        var source = fixture()
        XCTAssertTrue(source.runtimeValidationIssues().contains { $0.code == .unresolvedTerrain })
        for index in source.terrain.indices {
            source.terrain[index].runtimeBehavior = .init(
                visualKind: index == 1 ? .wall : index == 2 ? .bush : .floor,
                destroyedByNormalWeapons: false, destroyedInOvertime: false, evidence: evidence)
        }
        source.sourceRows[2] = "pp?pp"
        XCTAssertTrue(source.runtimeValidationIssues().contains { $0.code == .unknownSymbol })
        source.sourceRows[2] = "ppppp"
        source.mode?.rawProperties["MaxScore"] = "20"
        source.mode?.matchRules = .init(scoreGoal: 21, evidence: ["scoreGoal": evidence])
        XCTAssertTrue(source.runtimeValidationIssues().contains { $0.code == .contradictoryProperty })
    }

    /// Optional local integration gate. The repo contains no private descriptors;
    /// a caller can provide its own directory to validate every generated map.
    func testOptionalLocalImportedMapDirectory() throws {
        guard let path = ProcessInfo.processInfo.environment["ARENA_IMPORTED_MAP_DIRECTORY"] else {
            throw XCTSkip("No local imported map directory was supplied.")
        }
        let files = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path),
                                                               includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".arena-map.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let description = try JSONDecoder().decode(Imported.self, from: Data(contentsOf: file))
            let plan = try description.runtimePlan()
            XCTAssertEqual(plan.map.width, plan.terrainState.width, file.lastPathComponent)
            XCTAssertEqual(plan.map.height, plan.terrainState.height, file.lastPathComponent)
            XCTAssertEqual(plan.spawns.count, plan.modeBinding.teamCount, file.lastPathComponent)
            XCTAssertEqual(plan.spawns.map(\.cells.count), Array(repeating: plan.modeBinding.teamSize, count: plan.modeBinding.teamCount), file.lastPathComponent)
            let entrants = plan.spawns.flatMap { group in
                group.cells.enumerated().map { slot, _ in
                    ArenaGame.Entrant(name: "Synthetic \(group.team):\(slot)", brawler: .ranger, isBot: false, team: group.team)
                }
            }
            var game = try ArenaGame(importedPlan: plan, entrants: entrants, seed: 809)
            XCTAssertEqual(game.fighters.count, entrants.count, file.lastPathComponent)
            for index in game.fighters.indices {
                XCTAssertEqual(game.fighters[index].pos, game.importedInitialSpawn(for: index), file.lastPathComponent)
            }
            if plan.mode == .heist {
                XCTAssertEqual(game.chests.map(\.maxHealth), [plan.matchRules!.safeBaseHealth!, plan.matchRules!.safeBaseHealth!], file.lastPathComponent)
            }
            if plan.mode == .showdown {
                let selected = try plan.seededPowerBoxes(seed: 809)
                XCTAssertEqual(game.boxes.map(\.pos), selected.map { $0.cell.center }, file.lastPathComponent)
                XCTAssertEqual(game.boxes.map(\.health), selected.map(\.health), file.lastPathComponent)
            }
            if plan.mode == .zone { XCTAssertEqual(game.importedZone?.zones, plan.objectives.captureZones, file.lastPathComponent) }
            game.step(0.05, inputs: [:])
            XCTAssertTrue(game.fighters.allSatisfy { $0.pos.x.isFinite && $0.pos.y.isFinite }, file.lastPathComponent)
            for (y, row) in description.sourceRows.enumerated() {
                for (x, char) in row.enumerated() {
                    XCTAssertEqual(plan.terrainState.cell(x, y)?.sourceSymbol, String(char), file.lastPathComponent)
                }
            }
        }
    }
}
