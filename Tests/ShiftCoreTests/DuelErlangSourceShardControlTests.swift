import Foundation
import XCTest
@testable import ShiftCore

/// Real Wu own-rig clocks/capsules and the existing explicitly synthetic D19
/// caster fixture. This exercises the control adapter, not native rendering.
final class DuelErlangSourceShardControlTests: XCTestCase {
    func testSourceShardWaitsForWuUninterruptThenOwnsTheWholeStunWithoutResumingTheCast() throws {
        guard let path = ProcessInfo.processInfo.environment["ERLANG_RUNTIME_PROFILE"] else {
            throw XCTSkip("Authenticated D15 runtime profile is not staged")
        }
        let raw = try Data(contentsOf: URL(fileURLWithPath: path))
        var sourceWu = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        // The synthetic caster has no authenticated paired throw victims.
        // Remove only that unrelated capability from this control fixture;
        // original D15 poses, capsules, timers and ability rules stay exact.
        sourceWu.removeValue(forKey: "ordinaryThrows")
        let wu = try JSONDecoder().decode(DuelWeaponProfile.self,
            from: JSONSerialization.data(withJSONObject: sourceWu))
        XCTAssertTrue(DuelSourceStunMotion.matches(profile: wu))
        let rules = try DuelPanguRules.d19HeavenlyKing(level: 2, maximumHealth: 10_000,
            weaponPower: 100, unarmedPower: 100, magicPower: 100, rangedPower: 100,
            spatialTemplate: DuelPanguTestFixture.rules(level: 2))
        let source = try DuelPanguFightFixture.catalog(rules: rules, ordinaryDamage: 1)
        let pangu = try XCTUnwrap(source.profile(for: .liu))
        let catalog = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
            profiles: [wu, pangu])
        try catalog.validate()
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: .wuYong, x: 4300, facing: -1),
            .init(hero: .liu, x: 3500, facing: 1)
        ], mode: .practice, difficulty: .learning, catalog: catalog, seed: 42))
        for _ in 0..<1000 where fight.sourceIntroActive { fight.step(.neutral, opponent: .neutral) }
        for _ in 0..<100 where !fight.canUseErlang(.meditate, index: 0) { fight.step(.neutral, opponent: .neutral) }
        XCTAssertTrue(fight.canUseErlang(.meditate, index: 0))
        fight.step(.init(weaponCommand: .ranged, rangedHeld: true), opponent: .neutral)
        for _ in 0..<40 { fight.step(.init(rangedHeld: true), opponent: .neutral) }
        XCTAssertEqual(fight.erlangState(0)?.cast?.role, "erlangMeditationLoop")
        fight.step(.init(rangedHeld: true), opponent: .init(move: 1, weaponCommand: .shadow))
        XCTAssertEqual(fight.panguState(1)?.activeCast?.ability, .shard)
        var contacted = false
        for _ in 0..<120 where !contacted {
            fight.step(.init(rangedHeld: true), opponent: .neutral)
            contacted = fight.panguPresentationEvents.contains {
                if case .contact(let contact) = $0.kind {
                    return contact.target == 0 && contact.ability == .shard &&
                        contact.delivery == .projectile && contact.kind == .hit
                }
                return false
            }
        }
        XCTAssertTrue(contacted, "The source projectile must make a real capsule contact")
        XCTAssertEqual(fight.erlangState(0)?.cast?.role, "erlangMeditationLoop")
        XCTAssertFalse(fight.panguPresentation.controls.contains { $0.target == 0 && $0.kind == .stun })
        let protectedTick = fight.erlangState(0)?.cast?.tick
        for _ in 0..<fight.hitStop { fight.step(.init(rangedHeld: true), opponent: .neutral) }
        XCTAssertEqual(fight.erlangState(0)?.cast?.tick, protectedTick)
        for _ in 0..<10 {
            fight.step(.init(rangedHeld: true), opponent: .neutral)
            XCTAssertEqual(fight.erlangState(0)?.cast?.role, "erlangMeditationLoop")
            XCTAssertFalse(fight.panguPresentation.controls.contains { $0.target == 0 && $0.kind == .stun })
        }
        var beforeStun: DuelErlangFightState.Cast?
        for _ in 0..<190 where fight.fighters[0].weaponPose?.clip != DuelSourceStunMotion.start.clip {
            beforeStun = fight.erlangState(0)?.cast
            fight.step(.neutral, opponent: .neutral)
        }
        let previous = try XCTUnwrap(beforeStun)
        XCTAssertEqual(previous.role, "erlangMeditationEnd"); XCTAssertEqual(previous.tick, 29)
        XCTAssertEqual(fight.fighters[0].weaponPose?.clip, DuelSourceStunMotion.start.clip)
        XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 0)
        XCTAssertEqual(fight.fighters[0].stun, 90)
        XCTAssertNil(fight.erlangState(0)?.cast, "The source Stun must cancel the prior body owner")
        let damage = fight.damageDealt[1]
        var sawLoop = false, sawEnd = false
        for _ in 0..<220 {
            guard let motion = DuelSourceStunMotion.allCases.first(where: { $0.clip == fight.fighters[0].weaponPose?.clip }) else { break }
            sawLoop = sawLoop || motion == .loop; sawEnd = sawEnd || motion == .end
            XCTAssertFalse(fight.canUseErlang(.meditate, index: 0))
            XCTAssertFalse(fight.canUseErlang(.hound, index: 0))
            XCTAssertFalse(fight.canUseErlang(.swords, index: 0))
            fight.step(.init(taps: [.skill1], weaponCommand: .ranged, rangedHeld: true), opponent: .neutral)
            XCTAssertNil(fight.erlangState(0)?.cast, "Inputs cannot replace a source Stun or revive the canceled cast")
        }
        XCTAssertTrue(sawLoop); XCTAssertTrue(sawEnd)
        XCTAssertEqual(fight.fighters[0].stun, 0)
        XCTAssertTrue(fight.canUseErlang(.hound, index: 0))
        XCTAssertEqual(fight.damageDealt[1], damage, "Starting deferred control cannot replay the rock damage")
    }
}
