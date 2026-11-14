import XCTest
import SceneKit
import AVFoundation
@testable import ShiftReminder

#if DEBUG
/// Installed-resource checks for the independently pinned floor-fall revision.
/// Missing resources fail these explicit tests; no synthetic pack or skipped
/// method can satisfy them. The consumer test spies on playback calls and does
/// not establish audible output, spatial defaults or physical-device fidelity.
@MainActor
final class DuelTriadFloorfallIntegrationTests: XCTestCase {
    private let releaseSHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
    private let audioSHA = "d13dbebea26a4759c3b5109ef12de957140b9056e6adc5fdf989b6a3321b3d90"
    private let clips: Set<String> = ["h_hit_head_fall", "h17_root_spike_passive_end"]
    private enum Failure: Error { case unapprovedInstalledRevision }

    private final class Player: DuelEffectLoopPlayback {
        let duration: TimeInterval = 0.1
        var currentTime: TimeInterval = 0
        var isPlaying = false
        var numberOfLoops = 0
        func prepareToPlay() -> Bool { true }
        func play() -> Bool { isPlaying = true; return true }
        func pause() { isPlaying = false }
        func stop() { isPlaying = false }
    }

    private func installed() throws -> (DuelWeaponAssets, DuelTriadAudioBinding) {
        let pin = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: DuelFighterAssetRelease.infoKey) as? String)
        XCTAssertEqual(pin, releaseSHA, "Select this new installed-source revision explicitly")
        guard pin == releaseSHA else { throw Failure.unapprovedInstalledRevision }
        let assets = try DuelWeaponAssets()
        let release = try XCTUnwrap(assets.release)
        XCTAssertEqual(release.definition.triadAudio?.sha256, audioSHA)
        XCTAssertEqual(release.definition.id, "h17-shared-root-floorfall-20261115-v2")
        XCTAssertNil(release.definition.panguAudio)
        XCTAssertEqual(assets.catalog.profile(for: .liu)?.id, "liu_hammers")
        return (assets, try XCTUnwrap(assets.triadAudio))
    }

    private func floorfall(_ binding: DuelTriadAudioBinding) -> [DuelTriadAudioBinding.Marker] {
        binding.markers.filter { $0.id.hasPrefix("source_floorfall_923_97_") }
    }

    func testInstalledReleaseBindsSevenOriginalVariantsAtThreeExactProfileIntervals() throws {
        let (assets, binding) = try installed()
        XCTAssertEqual(binding.verifiedFiles.count, 96, "95 original WAV files plus their bound manifest")
        XCTAssertEqual(binding.markers.count, 115)
        let markers = floorfall(binding)
        XCTAssertEqual(markers.count, 3)
        XCTAssertEqual(Set(markers.map(\.clip)), clips)
        XCTAssertEqual(markers.filter { $0.profileID == nil }.count, 2)
        XCTAssertEqual(markers.filter { $0.profileID == "liu_hammers" }.count, 1)
        let liu = try XCTUnwrap(assets.catalog.profile(for: .liu))
        XCTAssertTrue(DuelTriadRootVictimState.matches(profile: liu))
        XCTAssertEqual(liu.sha256, "a3aada76d336b9c4f9bda3904b5e947711d916f683a2dcbf7b8184377e01a517")
        XCTAssertEqual(liu.clips.count, 59)
        for marker in markers {
            let profile = try XCTUnwrap(assets.catalog.profiles.first {
                $0.id == (marker.profileID ?? "sun_triad")
            })
            XCTAssertEqual(marker.clock, .intervalStart)
            XCTAssertEqual(marker.sourceFrame, 20)
            XCTAssertEqual(marker.playbackFrame, 19)
            XCTAssertEqual(marker.context, "Common")
            XCTAssertNil(marker.summonRole)
            if marker.profileID != nil {
                XCTAssertEqual(marker.profileID, "liu_hammers")
                XCTAssertEqual(marker.clip, DuelTriadRootVictimState.Motion.end.clip)
            }
            XCTAssertEqual(marker.files.count, 7)
            XCTAssertEqual(Set(marker.files).count, 7)
            let clip = try XCTUnwrap(profile.clip(named: marker.clip))
            XCTAssertEqual(clip.frames, marker.clip == "h_hit_head_fall" ? 59 : 48)
            XCTAssertEqual(clip.ticks, 2 * (clip.frames - 1))
            XCTAssertEqual(marker.playbackFrame * clip.ticks / (clip.frames - 1), 38)
            let bytes = try XCTUnwrap(binding.audio[marker.category])
            XCTAssertEqual(bytes.count, marker.files.count)
            for (name, data) in zip(marker.files, bytes) {
                let receipt = try XCTUnwrap(binding.verifiedFiles.first { $0.path == name })
                XCTAssertEqual(data.count, receipt.bytes)
                XCTAssertEqual(DuelNetworkContentRecord.digest(data), receipt.sha256)
            }
        }
        XCTAssertEqual(markers.first?.files, markers.last?.files, "Keep the original variant order")
    }

    func testInstalledIntervalsReachTheExistingConsumerOnceAcrossPauseAndReset() throws {
        let (assets, binding) = try installed()
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: binding) { _ in Player() }
        defer { effects.shutdown() }
        let markers = floorfall(binding)
        XCTAssertEqual(markers.count, 3)
        for marker in markers {
            let profile = try XCTUnwrap(assets.catalog.profiles.first {
                $0.id == (marker.profileID ?? "sun_triad")
            })
            let clip = try XCTUnwrap(profile.clip(named: marker.clip))
            let boundOwner = marker.profileID == nil ? 0 : 1
            func consume(frame: Int, from: Int, to: Int, owner: Int? = nil) {
                let sample = DuelSourceMotionSample(frame: frame, sequence: 0, owner: owner ?? boundOwner,
                    clip: clip.name, previousTick: from, tick: to, duration: clip.ticks)
                effects.consumeTriad(events: [], samples: [sample], frame: frame,
                                     fighting: true, liveTick: frame, owners: [0], motionProfiles: [1: "liu_hammers"])
            }
            effects.reset()
            consume(frame: 10, from: 36, to: 37)
            XCTAssertNil(effects.playedSoundCategories[marker.category])
            consume(frame: 11, from: 37, to: 38)
            consume(frame: 11, from: 37, to: 38)
            consume(frame: 12, from: 38, to: 38)
            XCTAssertEqual(effects.playedSoundCategories[marker.category], 1)
            effects.setPaused(true)
            consume(frame: 13, from: 37, to: 41)
            XCTAssertEqual(effects.playedSoundCategories[marker.category], 1)
            effects.setPaused(false)
            consume(frame: 13, from: 37, to: 41)
            consume(frame: 13, from: 37, to: 41)
            XCTAssertEqual(effects.playedSoundCategories[marker.category], 2)
            consume(frame: 14, from: 37, to: 41, owner: 1 - boundOwner)
            XCTAssertEqual(effects.playedSoundCategories[marker.category], 2, "A matching clip on another profile cannot borrow this actor's marker")
            effects.reset()
            consume(frame: 0, from: 37, to: 38)
            XCTAssertEqual(effects.playedSoundCategories[marker.category], 1, "The new round owns a new sample stream")
        }
    }

    func testInstalledOriginalBodyFallWAVsDecodeWithoutStartingPlayback() throws {
        let (_, binding) = try installed()
        let marker = try XCTUnwrap(floorfall(binding).first)
        let variants = try XCTUnwrap(binding.audio[marker.category])
        XCTAssertEqual(variants.count, 7)
        for data in variants {
            let player = try AVAudioPlayer(data: data)
            XCTAssertTrue(player.duration.isFinite && player.duration > 0 && player.duration < 60)
            XCTAssertGreaterThan(player.numberOfChannels, 0)
            XCTAssertFalse(player.isPlaying)
        }
    }
}
#endif
