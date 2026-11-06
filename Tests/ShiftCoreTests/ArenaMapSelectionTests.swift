import XCTest
@testable import ShiftCore

final class ArenaMapSelectionTests: XCTestCase {
    func testSwitchingHeroKeepsProjectMapWithoutImportedMapsInThatMode() throws {
        for mode in ArenaGame.Mode.allCases  {
            let map = try XCTUnwrap(ArenaMap.selectionPool(for: mode).last)
            let selected = ArenaMapSelection.resolve(mode: mode, mapID: map.id, importedHero: true,
                                                     importedMaps: [.stars: ["imported:fixture:one:stars"]])
            XCTAssertEqual(selected.mode, mode, "Missing imported maps must not force a different mode")
            XCTAssertEqual(selected.mapID, map.id)
        }
    }

    func testBothHeroFamiliesKeepAnExplicitImportedSelection() {
        let map = "imported:fixture:one:ball"
        for source in [false, true] {
            let selected = ArenaMapSelection.resolve(mode: .ball, mapID: map, importedHero: source,
                                                     importedMaps: [.ball: [map]])
            XCTAssertEqual(selected.mode, .ball)
            XCTAssertEqual(selected.mapID, map)
        }
    }

    func testDisabledOrRemovedPackDoesNotBlockProjectMatches() {
        let selected = ArenaMapSelection.resolve(mode: .heist, mapID: "imported:fixture:one:heist",
                                                 importedHero: false, importedMaps: [:])
        XCTAssertEqual(selected.mode, .heist)
        XCTAssertNil(selected.mapID, "Project heroes resume their normal random map rotation")
        let project = ArenaMap.selectionPool(for: .heist)[0]
        XCTAssertEqual(ArenaMapSelection.resolve(mode: .heist, mapID: project.id, importedHero: false,
                                                importedMaps: [:]).mapID, project.id)
    }

    func testAdventureRosterModesKeepSelectedMapForImportedHero() {
        for mode in [ArenaGame.Mode.duel, .boss] {
            let map = ArenaMap.selectionPool(for: mode)[0]
            let classic = ArenaMapSelection.resolve(mode: mode, mapID: map.id, importedHero: false,
                                                    importedMaps: [:])
            XCTAssertEqual(classic.mode, mode)
            XCTAssertEqual(classic.mapID, map.id)
            let source = ArenaMapSelection.resolve(mode: mode, mapID: map.id, importedHero: true,
                                                   importedMaps: [.stars: ["imported:fixture:one:stars"]])
            XCTAssertEqual(source.mode, mode)
            XCTAssertEqual(source.mapID, map.id)
        }
    }

    func testMapFromAnotherModeCannotRemainSelected() {
        let ball = ArenaMap.selectionPool(for: .ball)[0]
        let source = ArenaMapSelection.resolve(mode: .heist, mapID: ball.id, importedHero: true,
                                               importedMaps: [.heist: ["imported:fixture:one:heist"]])
        XCTAssertEqual(source.mapID, "imported:fixture:one:heist")
        XCTAssertNil(ArenaMapSelection.resolve(mode: .heist, mapID: ball.id, importedHero: false,
                                              importedMaps: [:]).mapID)
    }

    func testImportedHeroGetsConcreteProjectMapWhenNoImportedMapIsAvailable() {
        let source = ArenaMapSelection.resolve(mode: .zone, mapID: nil, importedHero: true, importedMaps: [:])
        XCTAssertEqual(source.mode, .zone)
        XCTAssertEqual(source.mapID, ArenaMap.selectionPool(for: .zone).first?.id)
        XCTAssertNil(ArenaMapSelection.resolve(mode: .zone, mapID: nil, importedHero: false,
                                              importedMaps: [:]).mapID)
    }
}
