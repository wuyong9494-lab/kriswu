import XCTest
import SceneKit
@testable import ShiftReminder

#if DEBUG
/// Synthetic players exercise native pool ownership and lifecycle, independently
/// of the separate tests which decode and verify actual recovered source PCM.
@MainActor
final class DuelSerpentAudioPlaybackTests: XCTestCase {
    private final class Player: DuelEffectLoopPlayback {
        let duration: TimeInterval = 4.5
        var currentTime: TimeInterval = 0
        var isPlaying = false
        var numberOfLoops = 0
        var plays = 0
        func prepareToPlay() -> Bool { true }
        func play() -> Bool { isPlaying = true; plays += 1; return true }
        func pause() { isPlaying = false }
        func stop() { isPlaying = false }
    }
    private func fixture(includeBody: Bool = false) throws -> (DuelSourceEffects, [Player], DuelSerpentSourceAudio) {
        let binding = DuelSerpentSourceAudio.playbackFixture(pcm: Data([0, 1]), includeBody: includeBody)
        var players: [Player] = []
        let effects = try DuelSourceEffects.serpentAudioFixture(root: SCNNode(), binding: binding) { _ in
            let player = Player(); players.append(player); return player
        }
        return (effects, players, binding)
    }
    private func sound(_ identifier: String, owner: Int = 0, stop: Bool = false) -> DuelSerpentMatchEvent {
        .init(owner: owner, liveTick: 60, effect: .model(stop ? .soundStopped(identifier) : .soundStarted(identifier)))
    }

    func testOriginalLoopFlagAndIndependentOwnerStopsReachPreparedPlayers() throws {
        let (effects, players, binding) = try fixture()
        defer { effects.shutdown() }
        XCTAssertEqual(players.count, 12)
        XCTAssertEqual(players.filter { $0.numberOfLoops == -1 }.count, 2)
        let rain = DuelSerpentRainRuntime.rainSound
        effects.consumeSerpent(events: [sound(rain), sound(rain, owner: 1)], frame: 1, fighting: true, owners: [0, 1])
        XCTAssertEqual(players.filter(\.isPlaying).count, 2)
        effects.consumeSerpent(events: [sound(rain, stop: true)], frame: 2, fighting: true, owners: [0, 1])
        XCTAssertEqual(players.filter(\.isPlaying).count, 1)
        XCTAssertEqual(effects.playedSoundCategories[try XCTUnwrap(binding.category(identifier: rain, owner: 0))], 1)
        XCTAssertEqual(effects.playedSoundCategories[try XCTUnwrap(binding.category(identifier: rain, owner: 1))], 1)
        effects.consumeSerpent(events: [], frame: 3, fighting: true, owners: [])
        XCTAssertFalse(players.contains(where: \.isPlaying))
    }

    func testPauseResumeAndRepeatedDisplayDoNotReplayTheSourceEvent() throws {
        let (effects, players, _) = try fixture()
        defer { effects.shutdown() }
        let events = [sound(DuelSerpentRainRuntime.rainSound)]
        effects.consumeSerpent(events: events, frame: 1, fighting: true, owners: [0])
        effects.setPaused(true)
        XCTAssertFalse(players.contains(where: \.isPlaying))
        effects.consumeSerpent(events: events, frame: 1, fighting: true, owners: [0])
        effects.setPaused(false)
        XCTAssertEqual(players.filter(\.isPlaying).count, 1)
        for _ in 0..<60 { effects.consumeSerpent(events: events, frame: 1, fighting: true, owners: [0]) }
        XCTAssertEqual(effects.playedSounds, 1)
        XCTAssertEqual(players.reduce(0) { $0 + $1.plays }, 2, "One play and one resume; no repeated source start")
    }

    func testRoundCompletionPlaysRealOutroOnceAndTeardownReleasesLoops() throws {
        let (effects, players, binding) = try fixture()
        defer { effects.shutdown() }
        let rain = DuelSerpentRainRuntime.rainSound, outro = DuelSerpentRainRuntime.rainOutSound
        effects.consumeSerpent(events: [sound(rain)], frame: 1, fighting: true, owners: [0])
        let events = [sound(rain, stop: true), sound(outro)]
        effects.consumeSerpent(events: events, frame: 2, fighting: false, owners: [0])
        effects.consumeSerpent(events: events, frame: 2, fighting: false, owners: [0])
        XCTAssertFalse(players.contains { $0.numberOfLoops == -1 && $0.isPlaying })
        XCTAssertEqual(effects.playedSoundCategories[try XCTUnwrap(binding.category(identifier: outro, owner: 0))], 1)
        effects.shutdown()
        XCTAssertFalse(players.contains(where: \.isPlaying))
        effects.consumeSerpent(events: [sound(rain)], frame: 3, fighting: true, owners: [0])
        XCTAssertFalse(players.contains(where: \.isPlaying))
    }

    func testResetStopsOldLoopAndAllowsFreshMatchToUseFrameZero() throws {
        let (effects, players, _) = try fixture()
        defer { effects.shutdown() }
        let events = [sound(DuelSerpentRainRuntime.rainSound)]
        effects.consumeSerpent(events: events, frame: 90, fighting: true, owners: [0])
        effects.reset()
        XCTAssertFalse(players.contains(where: \.isPlaying))
        effects.consumeSerpent(events: events, frame: 0, fighting: true, owners: [0])
        XCTAssertEqual(effects.playedSounds, 1)
        XCTAssertEqual(players.filter(\.isPlaying).count, 1)
    }

    func testBodySourceIntervalsPlayEachOwnerOnceAndRequireTheVerifiedFloor() throws {
        let (effects, players, binding) = try fixture(includeBody: true)
        defer { effects.shutdown() }
        let samples = (0..<2).map { owner in
            DuelSourceMotionSample(frame: 1, sequence: owner, owner: owner, clip: "fixture-motion",
                                   previousTick: 19, tick: 22, duration: 60)
        }
        effects.consumeSerpent(events: [], samples: samples, frame: 1, fighting: true, owners: [0, 1])
        XCTAssertEqual(effects.playedSounds, 2)
        XCTAssertEqual(players.filter(\.isPlaying).count, 2)
        for owner in 0..<2 {
            XCTAssertEqual(effects.playedSoundCategories[try XCTUnwrap(binding.bodyCategory(markerID: "fixture-swing", owner: owner))], 1)
        }
        effects.consumeSerpent(events: [], samples: samples,
            stageSHA256: DuelSerpentBodyAudioClock.palaceStageSHA256, frame: 1, fighting: true, owners: [0, 1])
        XCTAssertEqual(effects.playedSounds, 2, "Late stage authentication cannot replay the consumed footstep")
        let next = DuelSourceMotionSample(frame: 2, sequence: 0, owner: 0, clip: "fixture-motion",
                                         previousTick: 21, tick: 22, duration: 60)
        effects.consumeSerpent(events: [], samples: [next],
            stageSHA256: DuelSerpentBodyAudioClock.palaceStageSHA256, frame: 2, fighting: false, owners: [0, 1])
        XCTAssertEqual(effects.playedSoundCategories[try XCTUnwrap(binding.bodyCategory(markerID: "fixture-stone", owner: 0))], 1)
        XCTAssertEqual(effects.playedSounds, 3, "The final real pose interval survives the round's phase transition")
    }

    func testBodyOwnershipPauseAndResetDoNotCarryOldAudioIntoANewMatch() throws {
        let (effects, players, _) = try fixture(includeBody: true)
        defer { effects.shutdown() }
        let sample = DuelSourceMotionSample(frame: 40, sequence: 0, owner: 0, clip: "fixture-motion",
                                           previousTick: 19, tick: 20, duration: 60)
        effects.setPaused(true)
        effects.consumeSerpent(events: [], samples: [sample], frame: 40, fighting: true, owners: [0])
        XCTAssertEqual(effects.playedSounds, 0)
        effects.setPaused(false)
        effects.consumeSerpent(events: [], samples: [sample], frame: 40, fighting: true, owners: [0])
        XCTAssertEqual(effects.playedSounds, 1)
        effects.consumeSerpent(events: [], frame: 41, fighting: true, owners: [])
        XCTAssertFalse(players.contains(where: \.isPlaying))
        effects.reset()
        let fresh = DuelSourceMotionSample(frame: 0, sequence: 0, owner: 1, clip: "fixture-motion",
                                          previousTick: 19, tick: 20, duration: 60)
        effects.consumeSerpent(events: [], samples: [fresh], frame: 0, fighting: true, owners: [1])
        XCTAssertEqual(effects.playedSounds, 1)
        XCTAssertEqual(players.filter(\.isPlaying).count, 1)
    }
}
#endif
