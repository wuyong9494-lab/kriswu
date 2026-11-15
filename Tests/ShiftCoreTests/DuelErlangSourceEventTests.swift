import Foundation
import XCTest
@testable import ShiftCore

final class DuelErlangSourceEventTests: XCTestCase {
    private func catalog() throws -> DuelWeaponCatalog {
        let env = ProcessInfo.processInfo.environment
        guard let actor = env["ERLANG_RUNTIME_PROFILE"], let opponents = env["ERLANG_OPPONENT_CATALOG"] else {
            throw XCTSkip("Authenticated own-rig D15 and H17 source profiles are not staged")
        }
        let decoder = JSONDecoder()
        let wu = try decoder.decode(DuelWeaponProfile.self, from: Data(contentsOf: URL(fileURLWithPath: actor)))
        let prior = try decoder.decode(DuelWeaponCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: opponents)))
        return .init(schemaVersion: 1, previewFramesPerSecond: 30, profiles: [wu, try XCTUnwrap(prior.profile(for: .ember))])
    }
    private func fight(_ catalog: DuelWeaponCatalog, enemyInvulnerable: Bool = false) throws -> DuelWeaponFight {
        var enemy = DuelGame.Fighter(hero: .ember, x: 5500, facing: -1)
        if enemyInvulnerable { enemy.invulnerable = 100_000 }
        var result = try XCTUnwrap(DuelWeaponFight(fighters: [.init(hero: .wuYong, x: 3000, facing: 1), enemy],
            mode: .practice, difficulty: .learning, catalog: catalog, seed: 42))
        for _ in 0..<1000 where result.sourceIntroActive { result.step(.neutral, opponent: .neutral) }
        return result
    }
    func testMeditationEmitsOneStartAndStopsAtTheRealEndEventNotAtButtonRelease() throws {
        var fight = try fight(catalog(), enemyInvulnerable: true)
        for _ in 0..<100 where !fight.canUseErlang(.meditate, index: 0) { fight.step(.neutral, opponent: .neutral) }
        fight.step(.init(weaponCommand: .ranged, rangedHeld: true), opponent: .neutral)
        XCTAssertEqual(fight.erlangAudioEvents.map(\.kind), [.meditationStarted])
        XCTAssertEqual(fight.erlangAudioEvents.first?.owner, 0)
        XCTAssertEqual(fight.erlangAudioEvents.first?.frame, fight.frame)
        XCTAssertEqual(fight.erlangAudioEvents.first?.sequence, 0)
        fight.step(.neutral, opponent: .neutral)
        XCTAssertTrue(fight.erlangAudioEvents.isEmpty, "Releasing the button is not StopSound")
        var stopCount = 0
        for _ in 0..<160 {
            fight.step(.neutral, opponent: .neutral)
            for event in fight.erlangAudioEvents {
                XCTAssertEqual(event.kind, .meditationStopped); stopCount += 1
                let cast = try XCTUnwrap(fight.erlangState(0)?.cast)
                XCTAssertEqual(cast.role, "erlangMeditationEnd"); XCTAssertEqual(cast.tick, cast.duration)
            }
        }
        XCTAssertEqual(stopCount, 1); XCTAssertNil(fight.erlangState(0)?.cast)
        XCTAssertTrue(fight.erlangAudioEvents.isEmpty)
    }
    func testActualSunRootOwnsTheWuSourceVictimPoseAndClearsAnInterruptibleCast() throws {
        let original = try catalog()
        XCTAssertTrue(DuelTriadRootVictimState.matches(profile: original.profiles[0]))
        // Only starting energy is changed as an explicit control fixture;
        // all original own-rig animation and collision bytes remain intact.
        let charged = try DuelWeaponTestFixtures.changing(original) { profiles in
            var rules = profiles[1]["triadRules"] as! [String: Any]
            var mist = rules["mist"] as! [String: Any]
            mist["initial"] = mist["maximum"]; rules["mist"] = mist
            profiles[1]["triadRules"] = rules
        }
        for protected in [false, true] {
            var fight = try fight(charged, enemyInvulnerable: true)
            let held: DuelGame.Input = protected ? .init(rangedHeld: true) : .neutral
            if protected {
                for _ in 0..<100 where !fight.canUseErlang(.meditate, index: 0) { fight.step(.neutral, opponent: .neutral) }
                fight.step(.init(weaponCommand: .ranged, rangedHeld: true), opponent: .neutral)
                XCTAssertEqual(fight.erlangState(0)?.cast?.role, "erlangMeditationStart")
            } else {
                fight.step(.init(taps: [.skill1]), opponent: .neutral)
                XCTAssertEqual(fight.erlangState(0)?.cast?.role, "erlangHound")
                // 42 owner startup + 22 source-model delay reaches Hound's
                // actual AnimationEnd recovery sample (74, before idle at 75).
                for _ in 0..<9 { fight.step(.neutral, opponent: .neutral) }
            }
            XCTAssertTrue(fight.canUseTriad(.branches, index: 1))
            fight.step(held, opponent: .init(weaponCommand: .shadow))
            XCTAssertEqual(fight.triadState(1)?.activeCast?.ability, .branches)
            var castImmediatelyBeforeContact: DuelErlangFightState.Cast?
            for _ in 0..<90 where fight.landedHits[1] == 0 {
                castImmediatelyBeforeContact = fight.erlangState(0)?.cast
                fight.step(held, opponent: .neutral)

            }
            XCTAssertEqual(fight.landedHits[1], 1, "The original root capsule must actually contact")
            let previous = try XCTUnwrap(castImmediatelyBeforeContact, "protected=\(protected)")
            if protected {
                XCTAssertEqual(previous.role, "erlangMeditationLoop")
                XCTAssertNil(fight.rootVictimState(0))
                XCTAssertEqual(fight.triadState(1)?.rootRemainingTicks, 0)
                XCTAssertEqual(fight.erlangState(0)?.cast?.role, "erlangMeditationLoop")
            } else {
                XCTAssertEqual(previous.role, "erlangHound")
                XCTAssertEqual(previous.tick + 1, original.profiles[0].clip(role: "erlangHound")?.sourceEndEventTick)
                XCTAssertNotNil(fight.rootVictimState(0)); XCTAssertNil(fight.erlangState(0)?.cast)
                XCTAssertEqual(fight.fighters[0].weaponPose?.clip, "h17_root_spike_passive_start")
                for _ in 0..<4 { fight.step(.init(weaponCommand: .shadow), opponent: .neutral) }
                XCTAssertNotNil(fight.rootVictimState(0)); XCTAssertNil(fight.erlangState(0)?.cast)
                XCTAssertEqual(fight.fighters[0].weaponPose?.clip, "h17_root_spike_passive_start")
            }
        }
    }
}
