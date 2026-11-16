import XCTest
@testable import ShiftCore

final class DuelLongComboTests: XCTestCase {
    private func catalog() throws -> DuelWeaponCatalog {
        try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { profiles in
            var clips = profiles[0]["clips"] as! [[String: Any]]
            let template = clips.first { $0["name"] as? String == "katana_weapon" }!
            for stage in 2...5 {
                var clip = template
                clip["name"] = "chain_stage_\(stage)"
                clips.append(clip)
            }
            profiles[0]["clips"] = clips
            profiles[0]["comboLinks"] = (1...4).map { stage in
                ["from": stage == 1 ? "katana_weapon" : "chain_stage_\(stage)",
                 "to": "chain_stage_\(stage + 1)", "sourceFrame": stage] as [String: Any]
            }
        }
    }

    func testFiveStagesAcceptInputBeyondTheFormerThreeStageLimitInBothDirections() throws {
        let source = try catalog()
        try source.validate()
        for direction in [-1, 1] {
            let fighters = [DuelGame.Fighter(hero: .ember, x: direction == 1 ? 2000 : 7000, facing: direction),
                            DuelGame.Fighter(hero: .liu, x: direction == 1 ? 7000 : 2000, facing: -direction)]
            var fight = try XCTUnwrap(DuelWeaponFight(fighters: fighters, mode: .practice,
                difficulty: .learning, catalog: source, seed: 19))
            var visited: [String] = []
            for _ in 0..<40 {
                fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
                if let clip = fight.fighters[0].weaponPose?.clip, clip != visited.last { visited.append(clip) }
                if visited.last == "chain_stage_5" { break }
            }
            XCTAssertEqual(visited, ["katana_weapon", "chain_stage_2", "chain_stage_3", "chain_stage_4", "chain_stage_5"])
            XCTAssertEqual(fight.landedHits[0], 0, "Whiffed stages never bank contact damage")
        }
    }

    func testAReleasedButtonDoesNotAutomaticallyContinueFiveStages() throws {
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: .ember, x: 2000, facing: 1), .init(hero: .liu, x: 7000, facing: -1)],
            mode: .practice, difficulty: .learning, catalog: catalog(), seed: 19))
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<40 {
            fight.step(.neutral, opponent: .neutral)
            XCTAssertFalse(fight.fighters[0].weaponPose?.clip.hasPrefix("chain_stage_") ?? false)
        }
    }

    func testCyclesAndAmbiguousBranchesCannotEnterTheSimulation() throws {
        let original = try catalog()
        for cycle in [true, false] {
            let invalid = try DuelWeaponTestFixtures.changing(original) { profiles in
                var links = profiles[0]["comboLinks"] as! [[String: Any]]
                links.append(["from": cycle ? "chain_stage_5" : "katana_weapon",
                              "to": cycle ? "katana_weapon" : "chain_stage_3", "sourceFrame": 1])
                profiles[0]["comboLinks"] = links
            }
            XCTAssertThrowsError(try invalid.validate())
            XCTAssertNil(DuelWeaponFight(fighters: [.init(hero: .ember, x: 2000, facing: 1),
                                                    .init(hero: .liu, x: 7000, facing: -1)],
                mode: .practice, difficulty: .learning, catalog: invalid, seed: 19))
        }
    }
}
