import XCTest
@testable import ShiftReminder

extension DuelWeaponGameplayTests {
    /// Uses the authenticated catalog and its existing splice anchors. Contact
    /// budgets remain app rules; this does not certify original combat events.
    func testActualSourcePrimaryCombosKeepTheirAnchorsAndPerStageContactLimit() throws {
        let assets = try DuelWeaponAssets()
        for hero in [DuelGame.Hero.ember, .liu] {
            let profile = try XCTUnwrap(assets.catalog.profile(for: hero))
            let first = try XCTUnwrap(profile.clip(command: .weapon))
            let link = try XCTUnwrap(profile.combo(from: first.name), "Both original weapon profiles need their primary continuation")
            let second = try XCTUnwrap(profile.clip(named: link.to))
            let other: DuelGame.Hero = hero == .ember ? .liu : .ember
            for direction in [1, -1] {
                for distance in [1200, 8000] {
                    for guarded in [false, true] {
                        let label = "\(hero)/\(direction)/\(distance)/guard=\(guarded)"
                        var fight = try XCTUnwrap(DuelWeaponFight(
                            fighters: [.init(hero: hero, x: 5000 - direction * distance / 2, facing: direction),
                                       .init(hero: other, x: 5000 + direction * distance / 2, facing: -direction)],
                            mode: .practice, difficulty: .learning, catalog: assets.catalog, seed: 7))
                        let opponent = DuelGame.Input(guardHeld: guarded)
                        fight.step(.init(weaponCommand: .weapon), opponent: opponent)
                        fight.step(.init(weaponCommand: .weapon), opponent: opponent)
                        var firstContinuationTick: Int?
                        var contactsByStage: [String: Int] = [:]
                        var reachedFinalFrame = false
                        for _ in 0..<(first.ticks + second.ticks + 120) {
                            fight.step(.neutral, opponent: opponent)
                            if let pose = fight.fighters[0].weaponPose {
                                if pose.clip == second.name {
                                    if firstContinuationTick == nil { firstContinuationTick = pose.tick }
                                    reachedFinalFrame = reachedFinalFrame || pose.tick == second.ticks
                                }
                                for contact in fight.contacts where contact.attacker == 0 {
                                    contactsByStage[pose.clip, default: 0] += 1
                                    XCTAssertEqual(contact.kind, guarded ? .block : .hit, label)
                                }
                            }
                            if fight.fighters[0].attack == nil { break }
                        }
                        XCTAssertEqual(firstContinuationTick, link.sourceFrame * 2, label)
                        XCTAssertTrue(reachedFinalFrame, "\(label): recovery must retain the complete source clip")
                        XCTAssertTrue(Set(contactsByStage.keys).isSubset(of: [first.name, second.name]), label)
                        XCTAssertTrue(contactsByStage.values.allSatisfy { $0 == 1 }, "\(label): one opportunity per stage")
                        XCTAssertNil(fight.fighters[0].attack, "\(label): the combo must recover")
                        XCTAssertEqual(fight.profiles[0], profile, "The original tracks and equipment must not be rewritten")
                        if distance == 1200 {
                            XCTAssertFalse(contactsByStage.isEmpty, "\(label): the real close-range combo must still connect")
                        }
                    }
                }
            }
        }
    }
}
