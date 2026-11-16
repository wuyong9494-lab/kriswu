import Foundation
import XCTest
@testable import ShiftCore

final class DuelSerpentBodyAudioFightTests: XCTestCase {
    func testActualWalkAndWhiffedShuangouReachOnlyTheirAcceptedSourceAudioIntervals() throws {
        let env = ProcessInfo.processInfo.environment
        guard let serpentPath = env["SERPENT_MATCH_PROFILE"], let erlangPath = env["ERLANG_MATCH_PROFILE"],
              let audioDirectory = env["SERPENT_BODY_AUDIO_DIRECTORY"] else {
            throw XCTSkip("Authenticated body profiles and actual D13 audio required")
        }
        func profile(_ path: String) throws -> DuelWeaponProfile {
            try JSONDecoder().decode(DuelWeaponProfile.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        }
        let serpent = try profile(serpentPath), erlang = try profile(erlangPath)
        let manifest = try JSONDecoder().decode(DuelSerpentBodyAudioManifest.self, from:
            Data(contentsOf: URL(fileURLWithPath: audioDirectory).appendingPathComponent("SF3_Serpent_Body_Audio.json")))
        try manifest.validate(profile: serpent)
        let catalog = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30, sourceFramesPerSecond: 60,
                                        profiles: [serpent, erlang])
        try catalog.validate()
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: .liu, x: 2500, facing: 1), .init(hero: .wuYong, x: 7500, facing: -1)
        ], mode: .practice, difficulty: .learning, catalog: catalog, seed: 19))
        var clock = DuelSerpentBodyAudioClock(), cues: [DuelSerpentBodyAudioClock.Cue] = []
        let markers = manifest.markers.map(\.clock)
        func consume(_ fight: DuelWeaponFight, _ clock: inout DuelSerpentBodyAudioClock) -> [DuelSerpentBodyAudioClock.Cue] {
            clock.consume(markers: markers, samples: fight.sourceMotionSamples, frame: fight.frame,
                          paused: false, owners: [0], stageSHA256: DuelSerpentBodyAudioClock.palaceStageSHA256)
        }
        for _ in 0..<45 {
            fight.step(.init(move: 1), opponent: .neutral)
            cues += consume(fight, &clock)
        }
        fight.step(.neutral, opponent: .neutral); cues += consume(fight, &clock)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral); cues += consume(fight, &clock)
        for _ in 0..<100 {
            fight.step(.neutral, opponent: .neutral)
            cues += consume(fight, &clock)
            XCTAssertTrue(consume(fight, &clock).isEmpty, "Display callbacks cannot replay accepted source intervals")
        }
        let ids = Set(cues.map(\.markerID))
        let emitted = manifest.markers.filter { ids.contains($0.id) }
        XCTAssertTrue(emitted.contains { $0.route == "Floor.Stone" }, "Actual source walk must deliver its Stone step")
        let weapon = try XCTUnwrap(serpent.clip(command: .weapon))
        XCTAssertTrue(emitted.contains { $0.clip == weapon.name && $0.route == "Common" },
                      "An actual whiff must retain its authored shuangou swing")
        XCTAssertTrue(cues.allSatisfy { $0.owner == 0 })
        XCTAssertEqual(fight.landedHits[0], 0, "The distant target cannot be used to invent an audio contact")
        XCTAssertTrue(ids.isDisjoint(with: Set(manifest.excludedExistingBodyMarkers.map(\.id))))
    }
}
