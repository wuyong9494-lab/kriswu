import XCTest
import SceneKit
@testable import ShiftReminder

#if DEBUG
/// Synthetic PCM tests the native acceptance boundary and authoritative clock.
/// It is deliberately unrelated to recovered H17 sound contents.
@MainActor
final class DuelTriadSourceAudioBindingTests: XCTestCase {
    private final class Player: DuelEffectLoopPlayback {
        let duration: TimeInterval = 0.1
        var currentTime: TimeInterval = 0
        var isPlaying = false
        var numberOfLoops = 0
        var plays = 0
        func prepareToPlay() -> Bool { true }
        func play() -> Bool { isPlaying = true; plays += 1; return true }
        func pause() { isPlaying = false }
        func stop() { isPlaying = false }
    }
    private struct Fixture {
        let directory: URL
        let profile: DuelWeaponProfile
        let name = "Synthetic_TriadAudio.json"
        var document: [String: Any]
        var hash = ""
    }
    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("triad-audio-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let points = Array(repeating: DuelWeaponPoint(), count: 21)
        let tracks = DuelWeaponTracks(samplesPerSourceFrame: 2, root: points, handL: points, handR: points,
            footL: points, footR: points, weaponBaseL: points, weaponTipL: points,
            weaponBaseR: points, weaponTipR: points, groundLift: Array(repeating: 0, count: 21))
        let clip = DuelWeaponClip(name: "synthetic_ninjato_slash", frames: 11,
            sha256: String(repeating: "c", count: 64), bundle: "synthetic-only", tracks: tracks)
        let profile = DuelWeaponProfile(id: "sun_triad", hero: .ember, faction: "Herald",
            resourceName: "Synthetic_Triad", bytes: 1, sha256: String(repeating: "b", count: 64),
            bodyID: "synthetic-body", weaponID: "synthetic-dual-blades", activeWeaponSides: ["left", "right"],
            roles: ["weapon1": clip.name], clips: [clip])
        var files: [[String: Any]] = []
        for name in ["Synthetic_Hit.wav", "Synthetic_Forest.wav", "Synthetic_Marker.wav"] {
            let data = wav(); try data.write(to: directory.appendingPathComponent(name))
            files.append(["name": name, "bytes": data.count, "sha256": DuelNetworkContentRecord.digest(data)])
        }
        var value = Fixture(directory: directory, profile: profile, document: [
            "version": 1, "profileID": profile.id, "characterSHA256": profile.sha256,
            "sourceConfigurationSHA256": String(repeating: "d", count: 64), "evidence": ["synthetic acceptance fixture"],
            "files": files, "audio": ["ninjatoHit": ["Synthetic_Hit.wav"]],
            "cues": [["id": "forest", "event": "forestStarted", "loopUntil": "forestEnded", "files": ["Synthetic_Forest.wav"]]],
            "markers": [["id": "slash", "clip": clip.name, "sourceFrame": 7, "files": ["Synthetic_Marker.wav"]]]])
        try write(&value); return value
    }
    private func wav() -> Data {
        var result = Data()
        func word(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { result.append(contentsOf: $0) } }
        func long(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { result.append(contentsOf: $0) } }
        result.append(contentsOf: "RIFF".utf8); long(1636); result.append(contentsOf: "WAVEfmt ".utf8)
        long(16); word(1); word(1); long(8000); long(16000); word(2); word(16)
        result.append(contentsOf: "data".utf8); long(1600); result.append(Data(repeating: 2, count: 1600))
        return result
    }
    private func write(_ value: inout Fixture) throws {
        let data = try JSONSerialization.data(withJSONObject: value.document, options: [.sortedKeys])
        try data.write(to: value.directory.appendingPathComponent(value.name))
        value.hash = DuelNetworkContentRecord.digest(data)
    }
    private func load(_ value: Fixture, additionalProfiles: [DuelWeaponProfile] = []) throws -> DuelTriadAudioBinding {
        try .load(directory: value.directory, manifestName: value.name, expectedSHA256: value.hash,
            profile: value.profile, additionalProfiles: additionalProfiles)
    }
    private func event(_ effect: DuelTriadState.Effect, frame: Int = 10, sequence: Int = 0) -> DuelTriadPresentation.Event {
        .init(id: .init(frame: frame, sequence: sequence), liveTick: 3, kind: .effect(owner: 0, effect: effect))
    }
    private func sample(frame: Int = 10, sequence: Int = 0, from: Int, to: Int) -> DuelSourceMotionSample {
        .init(frame: frame, sequence: sequence, owner: 0, clip: "synthetic_ninjato_slash",
              previousTick: from, tick: to, duration: 20)
    }
    private func source(_ value: DuelTriadPresentation.SourceEvent, frame: Int = 10, tick: Int = 3,
                        owner: Int = 0, sequence: Int = 0) -> DuelTriadPresentation.Event {
        .init(id: .init(frame: frame, sequence: sequence), liveTick: tick, kind: .source(owner: owner, event: value))
    }
    private func sourceFixture(cues: [[String: Any]]) throws -> Fixture {
        var value = try fixture()
        value.document["version"] = 2
        value.document["context"] = ["gender": "Male", "floor": "Stone"]
        value.document["cues"] = cues
        try write(&value); return value
    }

    private func sharedFixture() throws -> (Fixture, DuelWeaponProfile) {
        var value = try fixture()
        var roles: [String: String] = [:], clips: [DuelWeaponClip] = []
        var motions: [String: DuelSourceThrowMotion] = [:]
        let frames = [51, 42, 83, 81, 82, 61], ends = [92, 74, 156, 152, 154, 112]
        for (index, key) in DuelSourceThrowRules.Motion.allCases.enumerated() {
            let count = 2 * frames[index] - 1, role = "synthetic_throw_role_" + key.rawValue
            // Intentionally share a basename with Sun while using another
            // frame count and source hash: ownership must disambiguate them.
            let name = index == 0 ? "synthetic_ninjato_slash" : "synthetic_common_" + key.rawValue
            let points = Array(repeating: DuelWeaponPoint(), count: count)
            let hash = String(repeating: String(index + 1), count: 64)
            roles[role] = name
            clips.append(.init(name: name, frames: frames[index], sha256: hash, bundle: "synthetic-only",
                tracks: .init(samplesPerSourceFrame: 2, root: points, handL: points, handR: points,
                    footL: points, footR: points, weaponBaseL: points, weaponTipL: points,
                    weaponBaseR: points, weaponTipR: points, groundLift: Array(repeating: 0, count: count),
                    centerOfMass: points)))
            motions[key.rawValue] = .init(role: role, sourceSHA256: hash, lastSampleTick: count - 1,
                animationEndTick: ends[index], uninterruptEndTick: count,
                rootMillimeters: Array(repeating: 0, count: count), footLeftMillimeters: 0, pelvisMillimeters: 0)
        }
        let rules = DuelSourceThrowRules(motions: motions, normalizedUnarmedPower: 1000,
            millimetersPerSourceUnitNumerator: 92, millimetersPerSourceUnitDenominator: 10,
            maximumRangeSourceUnits: 102, forwardWallThresholdSourceUnits: 150,
            backWallThresholdSourceUnits: 100, throwDisabledAfterVictimEndTicks: 105)
        let shared = DuelWeaponProfile(id: "liu_hammers", hero: .liu, faction: "Synthetic",
            resourceName: "Synthetic_Liu", bytes: 1, sha256: String(repeating: "f", count: 64),
            bodyID: "synthetic-liu-body", weaponID: "synthetic-hammers", activeWeaponSides: ["left", "right"],
            roles: roles, clips: clips, ordinaryThrows: .init(id: "synthetic-common-audio",
                basis: .applicationAdaptation, sourceVersion: "Synthetic geometry, not original media",
                sourceSHA256: nil, evidence: [], simultaneousContactPolicy: .sourceComplementaryLottery,
                attempts: [], source: rules))
        value.document["version"] = 2
        value.document["context"] = ["gender": "Male", "floor": "Stone"]
        value.document["motionProfiles"] = [shared.id: shared.sha256]
        var markers = value.document["markers"] as! [[String: Any]]
        markers.append(["id": "liu_throw", "profileID": shared.id, "clip": clips[0].name,
            "sourceFrame": 7, "clock": "soundFrame", "context": "Common", "files": ["Synthetic_Marker.wav"]])
        value.document["markers"] = markers
        try write(&value); return (value, shared)
    }

    func testCharacterSourceConfigurationAndEveryAudioFileArePinned() throws {
        var value = try fixture(); let binding = try load(value)
        XCTAssertEqual(binding.verifiedFiles.count, 4)
        XCTAssertEqual(binding.sourceFrameCounts["synthetic_ninjato_slash"], 11)
        XCTAssertEqual(binding.loopCategories, ["triadCue:forest"])
        for file in binding.verifiedFiles {
            let data = try Data(contentsOf: value.directory.appendingPathComponent(file.path))
            XCTAssertEqual(file.sha256, DuelNetworkContentRecord.digest(data)); XCTAssertEqual(file.bytes, data.count)
        }
        for key in ["characterSHA256", "profileID", "sourceConfigurationSHA256"] {
            let original = value.document[key]; value.document[key] = "invalid"; try write(&value)
            XCTAssertThrowsError(try load(value)); value.document[key] = original
        }
    }

    func testSharedMotionProfileRequiresItsOwnCharacterAndSourceClipPins() throws {
        var (value, shared) = try sharedFixture()
        let accepted = try load(value, additionalProfiles: [shared])
        XCTAssertEqual(accepted.motionProfileIDs, ["liu_hammers"])
        XCTAssertEqual(accepted.sourceFrameCounts["liu_hammers/synthetic_ninjato_slash"], 51)
        XCTAssertEqual(accepted.sourceFrameCounts["synthetic_ninjato_slash"], 11)
        XCTAssertThrowsError(try load(value))
        value.document["motionProfiles"] = [shared.id: String(repeating: "e", count: 64)]
        try write(&value); XCTAssertThrowsError(try load(value, additionalProfiles: [shared]))
        value.document["motionProfiles"] = [shared.id: shared.sha256]; try write(&value)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(shared)) as? [String: Any])
        var clips = object["clips"] as! [[String: Any]]
        clips[0]["sha256"] = String(repeating: "a", count: 64); object["clips"] = clips
        let mismatched = try JSONDecoder().decode(DuelWeaponProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try load(value, additionalProfiles: [mismatched]))
    }

    func testSharedMotionBindingRejectsH17SoulLoopsAndUnboundClips() throws {
        for field in ["clip", "summonRole", "loopUntil", "profileID"] {
            var (value, shared) = try sharedFixture()
            var markers = value.document["markers"] as! [[String: Any]]
            switch field {
            case "clip": markers[1][field] = "h17_fight_start_stance"
            case "summonRole": markers[1][field] = "triadSummon_heraldDash"
            case "loopUntil": markers[1][field] = "sourceRoundFightEnded"
            default: markers[1][field] = "sun_triad"
            }
            value.document["markers"] = markers; try write(&value)
            XCTAssertThrowsError(try load(value, additionalProfiles: [shared]))
        }
    }

    func testSharedThrowMarkerPlaysWithNoSunOwnerAndCannotStartForest() throws {
        let (value, shared) = try sharedFixture()
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(),
            binding: load(value, additionalProfiles: [shared])) { _ in Player() }
        defer { effects.shutdown() }
        let other = DuelSourceMotionSample(frame: 10, sequence: 0, owner: 1, clip: "synthetic_ninjato_slash",
            previousTick: 13, tick: 14, duration: 100)
        let forest = DuelTriadPresentation.Event(id: .init(frame: 10, sequence: 0), liveTick: 3,
            kind: .effect(owner: 1, effect: .forestStarted(roundID: 1)))
        effects.consumeTriad(events: [forest], samples: [other], frame: 10, fighting: true,
            owners: [], motionProfiles: [1: shared.id])
        XCTAssertEqual(effects.playedSoundCategories, ["triadMarker:liu_throw": 1])
    }

    func testBothActorsKeepSeparateMarkerClocksAndDuplicatePauseFences() throws {
        let (value, shared) = try sharedFixture()
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(),
            binding: load(value, additionalProfiles: [shared])) { _ in Player() }
        defer { effects.shutdown() }
        let both = [sample(sequence: 0, from: 13, to: 14),
            DuelSourceMotionSample(frame: 10, sequence: 1, owner: 1, clip: "synthetic_ninjato_slash",
                previousTick: 13, tick: 14, duration: 100)]
        effects.setPaused(true)
        effects.consumeTriad(events: [], samples: both, frame: 10, fighting: true, owners: [0], motionProfiles: [1: shared.id])
        XCTAssertEqual(effects.playedSounds, 0)
        effects.setPaused(false)
        for _ in 0..<2 {
            effects.consumeTriad(events: [], samples: both, frame: 10, fighting: true, owners: [0], motionProfiles: [1: shared.id])
        }
        XCTAssertEqual(effects.playedSoundCategories, ["triadMarker:slash": 1, "triadMarker:liu_throw": 1])
    }

    func testChangingSharedRoleAndResetCannotKeepThePreviousBindingAlive() throws {
        let (value, shared) = try sharedFixture()
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(),
            binding: load(value, additionalProfiles: [shared])) { _ in Player() }
        defer { effects.shutdown() }
        func sharedSample(_ frame: Int) -> DuelSourceMotionSample {
            .init(frame: frame, sequence: 0, owner: 1, clip: "synthetic_ninjato_slash",
                previousTick: 13, tick: 14, duration: 100)
        }
        effects.consumeTriad(events: [], samples: [sharedSample(10)], frame: 10, fighting: true,
            owners: [], motionProfiles: [1: shared.id])
        effects.consumeTriad(events: [], samples: [sharedSample(11)], frame: 11, fighting: true,
            owners: [], motionProfiles: [1: "unverified_profile"])
        XCTAssertEqual(effects.playedSoundCategories, ["triadMarker:liu_throw": 1])
        XCTAssertEqual(effects.playingAudioPlayerCount, 0)
        effects.reset()
        effects.consumeTriad(events: [], samples: [sharedSample(10)], frame: 10, fighting: true,
            owners: [], motionProfiles: [1: shared.id])
        XCTAssertEqual(effects.playedSoundCategories, ["triadMarker:liu_throw": 1])
    }

    func testUnknownClipOutOfRangeAndUnverifiedCompanionMarkersAreRejected() throws {
        for change in ["clip", "sourceFrame", "summonRole"] {
            var value = try fixture()
            var marker = try XCTUnwrap((value.document["markers"] as? [[String: Any]])?.first)
            if change == "sourceFrame" { marker[change] = 11 }
            else { marker[change] = change == "summonRole" ? "triadHerald" : "unbound_clip" }
            value.document["markers"] = [marker]; try write(&value)
            XCTAssertThrowsError(try load(value))
        }
    }

    func testTamperedPCMAndSymbolicLinksCannotReplaceAcceptedSource() throws {
        let value = try fixture(), url = value.directory.appendingPathComponent("Synthetic_Hit.wav")
        var data = try Data(contentsOf: url); data[data.count - 1] ^= 1; try data.write(to: url)
        XCTAssertThrowsError(try load(value))
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: value.directory.appendingPathComponent("Synthetic_Marker.wav"))
        XCTAssertThrowsError(try load(value))
    }

    func testMarkerUsesUnshiftedSourceFrameAndCannotReplayFromADuplicateDraw() throws {
        let value = try fixture()
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: load(value)) { _ in Player() }
        defer { effects.shutdown() }
        // Sound.Frame=7 means tick14, whereas an Attack.Start=7 means tick12.
        effects.consumeTriad(events: [], samples: [sample(from: 11, to: 13)], frame: 10, fighting: true, owners: [0])
        XCTAssertEqual(effects.playedSounds, 0)
        let hit = sample(frame: 11, from: 13, to: 14)
        effects.consumeTriad(events: [], samples: [hit], frame: 11, fighting: true, owners: [0])
        effects.consumeTriad(events: [], samples: [hit], frame: 11, fighting: true, owners: [0])
        effects.consumeTriad(events: [], samples: [sample(from: -1, to: 20)], frame: 10, fighting: true, owners: [0])
        XCTAssertEqual(effects.playedSoundCategories, ["triadMarker:slash": 1])
    }

    func testAllCrossedMicrostepsAndPausedIntervalsAreHandledOnce() throws {
        let value = try fixture()
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: load(value)) { _ in Player() }
        defer { effects.shutdown() }
        let samples = [sample(sequence: 0, from: 11, to: 12), sample(sequence: 1, from: 12, to: 13),
                       sample(sequence: 2, from: 13, to: 14), sample(sequence: 3, from: 14, to: 15)]
        effects.setPaused(true); effects.consumeTriad(events: [], samples: samples, frame: 10, fighting: true, owners: [0])
        XCTAssertEqual(effects.playedSounds, 0)
        effects.setPaused(false); effects.consumeTriad(events: [], samples: samples, frame: 10, fighting: true, owners: [0])
        XCTAssertEqual(effects.playedSounds, 1)
        effects.consumeTriad(events: [], samples: samples, frame: 10, fighting: true, owners: [0])
        XCTAssertEqual(effects.playedSounds, 1)
    }

    func testForestLoopEndsOnAuthoritativeRoundEventAndNeverRestartsFromDuplicate() throws {
        let value = try fixture(); var players: [Player] = []
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: load(value)) { _ in
            let player = Player(); players.append(player); return player
        }
        defer { effects.shutdown() }
        let loop = try XCTUnwrap(players.first { $0.numberOfLoops == -1 })
        let start = event(.forestStarted(roundID: 1))
        effects.consumeTriad(events: [start, start], samples: [], frame: 10, fighting: true, owners: [0])
        XCTAssertEqual(loop.plays, 1); XCTAssertTrue(loop.isPlaying)
        effects.setPaused(true); XCTAssertFalse(loop.isPlaying)
        effects.setPaused(false); XCTAssertTrue(loop.isPlaying)
        effects.consumeTriad(events: [event(.forestEnded, frame: 11)], samples: [], frame: 11, fighting: false, owners: [0])
        XCTAssertFalse(loop.isPlaying)
        effects.consumeTriad(events: [start], samples: [], frame: 10, fighting: true, owners: [0])
        XCTAssertFalse(loop.isPlaying)
        effects.shutdown(); XCTAssertTrue(players.allSatisfy { !$0.isPlaying })
    }

    func testSourceSoulCueDoesNotTreatAppearanceAsAnAttackOrAnotherOrigin() throws {
        var value = try fixture()
        value.document["cues"] = [["id": "spirit", "event": "soulAppeared", "ability": "herald",
            "origin": "manual", "files": ["Synthetic_Forest.wav"]]]
        try write(&value)
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: load(value)) { _ in Player() }
        defer { effects.shutdown() }
        let events = [event(.soulSummoned(.herald, .manual, attackID: 8), sequence: 0),
            event(.soulAppeared(.herald, .forestRain, summonID: 9), sequence: 1),
            event(.soulAppeared(.herald, .manual, summonID: 10), sequence: 2)]
        effects.consumeTriad(events: events, samples: [], frame: 10, fighting: true, owners: [0])
        XCTAssertEqual(effects.playedSoundCategories, ["triadCue:spirit": 1])
    }

    func testWaveFrameOneUsesTwoLiveTicksAndCannotAdvanceDuringHitStopOrPause() throws {
        let value = try sourceFixture(cues: [["id": "wave", "event": "sourceWaveFirstFrame", "files": ["Synthetic_Forest.wav"]]])
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: load(value)) { _ in Player() }
        defer { effects.shutdown() }
        let birth = source(.modelCreated(id: 7, kind: .mistWave, origin: .manual))
        effects.consumeTriad(events: [birth, birth], samples: [], frame: 10, fighting: true, liveTick: 3, owners: [0])
        effects.consumeTriad(events: [], samples: [], frame: 11, fighting: true, liveTick: 3, owners: [0])
        XCTAssertEqual(effects.playedSounds, 0)
        effects.setPaused(true)
        effects.consumeTriad(events: [], samples: [], frame: 12, fighting: true, liveTick: 4, owners: [0])
        effects.setPaused(false)
        effects.consumeTriad(events: [], samples: [], frame: 12, fighting: true, liveTick: 4, owners: [0])
        XCTAssertEqual(effects.playedSounds, 0)
        effects.consumeTriad(events: [], samples: [], frame: 13, fighting: true, liveTick: 5, owners: [0])
        effects.consumeTriad(events: [], samples: [], frame: 13, fighting: true, liveTick: 5, owners: [0])
        XCTAssertEqual(effects.playedSoundCategories, ["triadCue:wave": 1])
    }

    func testIndependentModelsInOneStepEachReceiveTheirOwnDelayedCue() throws {
        let value = try sourceFixture(cues: [["id": "wave", "event": "sourceWaveFirstFrame", "files": ["Synthetic_Forest.wav"]]])
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: load(value)) { _ in Player() }
        defer { effects.shutdown() }
        let births = [source(.modelCreated(id: 7, kind: .mistWave, origin: .manual)),
                      source(.modelCreated(id: 8, kind: .mistWave, origin: .lastWave), sequence: 1)]
        effects.consumeTriad(events: births, samples: [], frame: 10, fighting: true, liveTick: 3, owners: [0])
        effects.consumeTriad(events: births, samples: [], frame: 10, fighting: true, liveTick: 3, owners: [0])
        effects.consumeTriad(events: [], samples: [], frame: 11, fighting: true, liveTick: 5, owners: [0])
        XCTAssertEqual(effects.playedSoundCategories, ["triadCue:wave": 2])
    }

    func testRootEndRequiresItsActualModelAndCannotPlayTwice() throws {
        let value = try sourceFixture(cues: [
            ["id": "root_in", "event": "sourceRootModelCreated", "files": ["Synthetic_Forest.wav"]],
            ["id": "root_out", "event": "sourceRootModelEnded", "files": ["Synthetic_Forest.wav"]]])
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: load(value)) { _ in Player() }
        defer { effects.shutdown() }
        effects.consumeTriad(events: [source(.rootModelEnded(id: 8))], samples: [], frame: 10, fighting: true, liveTick: 3, owners: [0])
        XCTAssertEqual(effects.playedSounds, 0)
        effects.consumeTriad(events: [source(.modelCreated(id: 8, kind: .roots, origin: .entangled), frame: 11, tick: 4)],
            samples: [], frame: 11, fighting: true, liveTick: 4, owners: [0])
        let end = source(.rootModelEnded(id: 8), frame: 12, tick: 64)
        effects.consumeTriad(events: [end, end], samples: [], frame: 12, fighting: true, liveTick: 64, owners: [0])
        effects.consumeTriad(events: [source(.rootModelEnded(id: 8), frame: 13, tick: 65)],
            samples: [], frame: 13, fighting: true, liveTick: 65, owners: [0])
        XCTAssertEqual(effects.playedSoundCategories, ["triadCue:root_in": 1, "triadCue:root_out": 1])
    }

    func testSoulAppearanceAndEachOriginalAnimationEndAreDistinctFromHits() throws {
        let value = try sourceFixture(cues: [
            ["id": "soul_in", "event": "sourceSoulModelCreated", "sourceRoles": ["triadSummon_danceNinjato"], "files": ["Synthetic_Forest.wav"]],
            ["id": "soul_out", "event": "sourceSoulAnimationEnded", "sourceRoles": ["triadSummon_ninjatoActiveStart", "triadSummon_ninjatoActiveEnd"], "files": ["Synthetic_Forest.wav"]]])
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: load(value)) { _ in Player() }
        defer { effects.shutdown() }
        effects.consumeTriad(events: [event(.soulSummoned(.herald, .dance, attackID: 20)),
            source(.soulModelCreated(id: 8, move: .danceNinjato), sequence: 1),
            source(.soulModelCreated(id: 9, move: .heraldDash), sequence: 2)],
            samples: [], frame: 10, fighting: true, liveTick: 3, owners: [0])
        XCTAssertEqual(effects.playedSoundCategories, ["triadCue:soul_in": 1])
        effects.consumeTriad(events: [source(.soulAnimationEnded(id: 8, role: "triadSummon_ninjatoActiveStart"), frame: 11, tick: 53),
            source(.soulAnimationEnded(id: 8, role: "triadSummon_ninjatoActiveEnd"), frame: 11, tick: 53, sequence: 1)],
            samples: [], frame: 11, fighting: true, liveTick: 53, owners: [0])
        effects.consumeTriad(events: [source(.soulAnimationEnded(id: 8, role: "triadSummon_ninjatoActiveStart"), frame: 12, tick: 54)],
            samples: [], frame: 12, fighting: true, liveTick: 54, owners: [0])
        XCTAssertEqual(effects.playedSoundCategories, ["triadCue:soul_in": 1, "triadCue:soul_out": 2])
    }

    func testBlastCueCannotBeTriggeredByOwnerCastOrAnotherProjectile() throws {
        let value = try sourceFixture(cues: [["id": "blast", "event": "sourceBlastModelCreated", "files": ["Synthetic_Forest.wav"]]])
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: load(value)) { _ in Player() }
        defer { effects.shutdown() }
        effects.consumeTriad(events: [event(.castPhase(.cryingDance, .active)),
            source(.modelCreated(id: 1, kind: .mistWave, origin: .manual), sequence: 1),
            source(.modelCreated(id: 2, kind: .heraldBlast, origin: .dance), sequence: 2)],
            samples: [], frame: 10, fighting: true, liveTick: 3, owners: [0])
        XCTAssertEqual(effects.playedSoundCategories, ["triadCue:blast": 1])
    }

    func testArenaForestStartDoesNotImpersonateTheOriginalIntroMarker() throws {
        var value = try sourceFixture(cues: [
            ["id": "arena", "event": "arenaForestLoopStarted",
             "loopUntil": "sourceRoundFightEnded", "files": ["Synthetic_Forest.wav"]],
            ["id": "round", "event": "sourceRoundStarted",
             "loopUntil": "sourceRoundFightEnded", "files": ["Synthetic_Forest.wav"]]])
        var markers = try XCTUnwrap(value.document["markers"] as? [[String: Any]])
        markers.append(["id": "original_intro", "clip": "synthetic_ninjato_slash", "sourceFrame": 7,
            "clock": "intervalStart", "loopUntil": "sourceRoundFightEnded", "files": ["Synthetic_Forest.wav"]])
        value.document["markers"] = markers; try write(&value)
        var players: [Player] = []
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: load(value)) { _ in
            let p = Player(); players.append(p); return p
        }
        defer { effects.shutdown() }
        effects.consumeTriad(events: [event(.forestStarted(roundID: 1))], samples: [], frame: 10, fighting: true, liveTick: 3, owners: [0])
        XCTAssertEqual(effects.playedSounds, 0)
        // First-round presentation now emits the real RoundStart. Its forest
        // ambience still belongs to the original intro marker, not lock1800.
        effects.consumeTriad(events: [source(.roundStarted(roundID: 1), sequence: 1)],
            samples: [], frame: 10, fighting: true, liveTick: 3, owners: [0])
        XCTAssertEqual(effects.playedSounds, 0)
        effects.consumeTriad(events: [source(.arenaForestLoopStarted(roundID: 1), frame: 11, tick: 4)],
            samples: [], frame: 11, fighting: true, liveTick: 4, owners: [0])
        XCTAssertEqual(effects.playedSoundCategories, ["triadCue:arena": 1])
        // Original interval Start=7 begins at source index6/tick12. Sounds
        // Frame=7 in the existing marker remains tick14.
        effects.consumeTriad(events: [], samples: [sample(frame: 12, from: 11, to: 12)],
            frame: 12, fighting: true, liveTick: 5, owners: [0])
        XCTAssertEqual(effects.playedSoundCategories, ["triadCue:arena": 1, "triadMarker:original_intro": 1])
        XCTAssertEqual(players.filter { $0.numberOfLoops == -1 && $0.isPlaying }.count, 1)
        effects.consumeTriad(events: [source(.roundFightEnded, frame: 13, tick: 6)],
            samples: [], frame: 13, fighting: false, liveTick: 6, owners: [0])
        XCTAssertTrue(players.filter { $0.numberOfLoops == -1 }.allSatisfy { !$0.isPlaying })
        let nextRound = source(.roundStarted(roundID: 2), frame: 14, tick: 7)
        effects.consumeTriad(events: [nextRound], samples: [], frame: 14, fighting: true, liveTick: 7, owners: [0])
        effects.consumeTriad(events: [nextRound], samples: [], frame: 14, fighting: true, liveTick: 7, owners: [0])
        XCTAssertEqual(effects.playedSoundCategories,
            ["triadCue:arena": 1, "triadMarker:original_intro": 1, "triadCue:round": 1])
        XCTAssertEqual(players.filter { $0.numberOfLoops == -1 && $0.isPlaying }.count, 1)

        // FX shares Cue but preserves the authenticated binding's first-round
        // scope: lock1799 energy/threads must not inherit the ambience gate.
        var definition: [String: Any] = ["id": "first_energy", "event": "sourceRoundStarted",
            "effect": "synthetic", "anchor": "owner", "follow": false, "sourceRoundScope": "first"]
        let first = try JSONDecoder().decode(DuelTriadEffectAssets.Binding.self,
            from: JSONSerialization.data(withJSONObject: definition))
        for round in [0, 1, 2] {
            XCTAssertEqual(first.cue.matches(.source(owner: 0, event: .roundStarted(roundID: round))), round == 1)
        }
        definition.removeValue(forKey: "sourceRoundScope")
        let subsequent = try JSONDecoder().decode(DuelTriadEffectAssets.Binding.self,
            from: JSONSerialization.data(withJSONObject: definition))
        for round in [0, 1, 2] {
            XCTAssertEqual(subsequent.cue.matches(.source(owner: 0, event: .roundStarted(roundID: round))), round == 2)
        }
    }

    func testUnboundOwnerAndEquippedRoleChangeCannotLeakSoundOrPendingWave() throws {
        let value = try sourceFixture(cues: [["id": "wave", "event": "sourceWaveFirstFrame", "files": ["Synthetic_Forest.wav"]]])
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: load(value)) { _ in Player() }
        defer { effects.shutdown() }
        effects.consumeTriad(events: [source(.modelCreated(id: 7, kind: .mistWave, origin: .manual), owner: 1)],
            samples: [.init(frame: 10, sequence: 0, owner: 1, clip: "synthetic_ninjato_slash", previousTick: 13, tick: 14, duration: 20)],
            frame: 10, fighting: true, liveTick: 3, owners: [0])
        effects.consumeTriad(events: [source(.modelCreated(id: 8, kind: .mistWave, origin: .manual), frame: 11, tick: 4)],
            samples: [], frame: 11, fighting: true, liveTick: 4, owners: [0])
        effects.consumeTriad(events: [], samples: [], frame: 12, fighting: true, liveTick: 6, owners: [])
        effects.consumeTriad(events: [], samples: [], frame: 13, fighting: true, liveTick: 7, owners: [0])
        XCTAssertEqual(effects.playedSounds, 0)
    }

    func testRoundEndAndResetDiscardPendingModelSounds() throws {
        let value = try sourceFixture(cues: [["id": "wave", "event": "sourceWaveFirstFrame", "files": ["Synthetic_Forest.wav"]]])
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: load(value)) { _ in Player() }
        defer { effects.shutdown() }
        effects.consumeTriad(events: [source(.modelCreated(id: 7, kind: .mistWave, origin: .manual))],
            samples: [], frame: 10, fighting: true, liveTick: 3, owners: [0])
        effects.consumeTriad(events: [source(.roundFightEnded, frame: 11, tick: 4)],
            samples: [], frame: 11, fighting: false, liveTick: 4, owners: [0])
        effects.consumeTriad(events: [], samples: [], frame: 12, fighting: true, liveTick: 5, owners: [0])
        XCTAssertEqual(effects.playedSounds, 0)
        effects.consumeTriad(events: [source(.modelCreated(id: 8, kind: .mistWave, origin: .manual), frame: 13, tick: 6)],
            samples: [], frame: 13, fighting: true, liveTick: 6, owners: [0])
        effects.reset()
        effects.consumeTriad(events: [], samples: [], frame: 0, fighting: true, liveTick: 10, owners: [0])
        XCTAssertEqual(effects.playedSounds, 0)
    }

    func testSourceContextUnknownSoulRoleAndInvalidIntervalClockAreRejected() throws {
        for change in ["context", "sourceRole", "interval", "schema"] {
            var value = try sourceFixture(cues: [["id": "soul", "event": "sourceSoulModelCreated",
                "sourceRoles": ["triadLegionary"], "files": ["Synthetic_Forest.wav"]]])
            switch change {
            case "context": value.document["context"] = ["gender": "Female", "floor": "Wood"]
            case "sourceRole": value.document["cues"] = [["id": "soul", "event": "sourceSoulModelCreated",
                "sourceRoles": ["panguSpear"], "files": ["Synthetic_Forest.wav"]]]
            case "interval": value.document["markers"] = [["id": "slash", "clip": "synthetic_ninjato_slash",
                "sourceFrame": 0, "clock": "intervalStart", "files": ["Synthetic_Marker.wav"]]]
            default: value.document["version"] = 3
            }
            try write(&value); XCTAssertThrowsError(try load(value), change)
        }
    }

    func testOriginalWeightedVariantArrayIsRetainedWithoutDuplicatingFileRecords() throws {
        var value = try sourceFixture(cues: [["id": "wave", "event": "sourceWaveFirstFrame",
            "files": ["Synthetic_Forest.wav", "Synthetic_Forest.wav", "Synthetic_Marker.wav"]]])
        value.document["markers"] = []
        try write(&value)
        let binding = try load(value)
        XCTAssertEqual(binding.verifiedFiles.count, 4)
        XCTAssertEqual(binding.cues[0].files, ["Synthetic_Forest.wav", "Synthetic_Forest.wav", "Synthetic_Marker.wav"])
        XCTAssertEqual(binding.audio["triadCue:wave"]?.count, 3)
    }
}
#endif
