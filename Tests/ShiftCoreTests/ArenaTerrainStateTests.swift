import Foundation
import XCTest
@testable import ShiftCore

final class ArenaTerrainStateTests: XCTestCase {
    private func rule(_ id: String, _ kind: ArenaTerrainState.VisualKind, normal: Bool = false,
                      breaker: Bool = false, overtime: Bool = false) -> ArenaTerrainState.Rule {
        .init(id: id, blocksMovement: kind == .wall || kind == .water,
              blocksProjectiles: kind == .wall, concealsHeroes: kind == .bush,
              destroyedByNormalWeapons: normal, destroyedByWallBreakers: breaker,
              destroyedInOvertime: overtime, visualKind: kind)
    }

    private func grid() throws -> ArenaTerrainState {
        try .init(width: 3, height: 3,
                  rules: [rule("floor", .floor), rule("water", .water),
                          rule("wall", .wall, breaker: true, overtime: true),
                          rule("fragile", .wall, normal: true, breaker: true, overtime: true),
                          rule("bush", .bush, breaker: true, overtime: true),
                          rule("hard", .wall, overtime: true)],
                  terrainIDs: ["floor", "water", "wall", "fragile", "bush", "floor", "hard", "bush", "bush"],
                  sourceSymbols: [".", "W", "M", "B", "F", ".", "I", "F", "F"])
    }

    func testWaterPreservesSplitCollisionAndCannotBeDestroyed() throws {
        var state = try grid()
        XCTAssertTrue(state.blocksMovement(1, 0))
        XCTAssertFalse(state.blocksProjectiles(1, 0))
        XCTAssertEqual(state.cell(1, 0)?.visualKind, .water)
        XCTAssertFalse(state.destroy(.init(1, 0), cause: .wallBreaker))
        XCTAssertFalse(state.destroy(.init(1, 0), cause: .overtime))
        XCTAssertEqual(state.cell(1, 0)?.sourceSymbol, "W")
        XCTAssertEqual(state.revision, 0)
    }

    func testNormalAttackWallBreakerAndOvertimeAreDifferentRules() throws {
        var state = try grid()
        XCTAssertFalse(state.destroy(.init(2, 0), cause: .normalWeapon))
        XCTAssertTrue(state.destroy(.init(0, 1), cause: .normalWeapon))
        XCTAssertTrue(state.destroy(.init(2, 0), cause: .wallBreaker))
        XCTAssertFalse(state.destroy(.init(2, 0), cause: .wallBreaker), "Destroying a removed cell is idempotent.")
        XCTAssertFalse(state.destroy(.init(0, 2), cause: .wallBreaker))
        XCTAssertTrue(state.destroy(.init(0, 2), cause: .overtime), "An overtime-only wall must not be treated as a normal destructible wall.")
        XCTAssertFalse(state.blocksMovement(2, 0))
        XCTAssertFalse(state.blocksProjectiles(2, 0))
        XCTAssertEqual(state.cell(2, 0)?.terrainID, "wall", "The original identity survives destruction.")
        XCTAssertEqual(state.cell(2, 0)?.visualKind, .floor)
        XCTAssertEqual(state.revision, 3)
    }

    func testDestroyingBushBridgeUpdatesConcealmentAndConnectedPatches() throws {
        var state = try grid()
        let first = V2(1.5, 1.5), last = V2(2.5, 2.5)
        XCTAssertTrue(state.sameBush(first, last))
        XCTAssertTrue(state.destroy(.init(1, 2), cause: .wallBreaker))
        XCTAssertFalse(state.sameBush(first, last))
        XCTAssertFalse(state.concealsHeroes(at: V2(1.5, 2.5)))
        XCTAssertEqual(state.bushID(at: V2(1.5, 2.5)), 0)
    }

    func testRadiusDestructionIsCenteredAndPreservesOutOfRangeCells() throws {
        var state = try grid()
        let changed = state.destroy(inRadius: 0, around: V2(0.5, 1.5), cause: .normalWeapon)
        XCTAssertEqual(changed, [.init(0, 1)])
        XCTAssertTrue(state.blocksProjectiles(2, 0))
        XCTAssertTrue(state.destroy(inRadius: .nan, around: .zero, cause: .wallBreaker).isEmpty)
        XCTAssertEqual(state.revision, 1)
    }

    func testInvalidCoordinatesAndUnknownRulesNeverBecomeFloor() throws {
        let state = try grid()
        XCTAssertTrue(state.blocksMovement(Int.max, 0))
        XCTAssertTrue(state.blocksProjectiles(at: V2(.infinity, 0)))
        XCTAssertNil(state.cell(at: V2(.nan, 0)))
        XCTAssertTrue(state.intersectsMovement(at: V2(0.5, 0.5), radius: .infinity))
        XCTAssertTrue(state.intersectsMovement(at: V2(0.85, 0.5), radius: 0.2))
        XCTAssertFalse(state.intersectsMovement(at: V2(0.5, 0.5), radius: 0.2))
        XCTAssertThrowsError(try ArenaTerrainState(width: 1, height: 1, rules: [rule("floor", .floor)],
                                                 terrainIDs: ["unknown"], sourceSymbols: ["?"]))
    }

    func testFenceDecorationAndExcludedMaskRetainIndependentSourceSemantics() throws {
        let fence = ArenaTerrainState.Rule(id: "rope", blocksMovement: true, blocksProjectiles: false,
            concealsHeroes: false, destroyedByNormalWeapons: false, destroyedByWallBreakers: true,
            destroyedInOvertime: true, visualKind: .wall)
        let decoration = ArenaTerrainState.Rule(id: "decoration", blocksMovement: false, blocksProjectiles: false,
            concealsHeroes: false, destroyedByNormalWeapons: true, destroyedByWallBreakers: true,
            destroyedInOvertime: true, visualKind: .floor)
        let invisible = ArenaTerrainState.Rule(id: "invisible", blocksMovement: true, blocksProjectiles: true,
            concealsHeroes: false, destroyedByNormalWeapons: false, destroyedByWallBreakers: false,
            destroyedInOvertime: false, visualKind: .wall, isVisible: false)
        var state = try ArenaTerrainState(width: 4, height: 1, rules: [fence, decoration, invisible, rule("floor", .floor)],
            terrainIDs: ["rope", "decoration", "invisible", "floor"], sourceSymbols: ["a", "D", "J", "."],
            excludedCells: [.init(3, 0)])
        XCTAssertEqual(state.cell(0, 0)?.visualKind, .wall)
        XCTAssertTrue(state.blocksMovement(0, 0))
        XCTAssertFalse(state.blocksProjectiles(0, 0))
        XCTAssertFalse(state.blocksMovement(1, 0))
        XCTAssertTrue(state.destroy(.init(1, 0), cause: .normalWeapon))
        XCTAssertEqual(state.cell(2, 0)?.isVisible, false)
        XCTAssertEqual(state.cell(3, 0)?.isOutOfBounds, true)
        XCTAssertTrue(state.blocksMovement(3, 0))
        XCTAssertTrue(state.blocksProjectiles(3, 0))
        XCTAssertFalse(state.destroy(.init(3, 0), cause: .overtime))
        XCTAssertEqual(state.cell(3, 0)?.sourceSymbol, ".", "An excluded source floor cell remains traceable.")
    }
}
