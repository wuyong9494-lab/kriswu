import XCTest
import SceneKit
@testable import ShiftReminder

#if DEBUG
/// Synthetic PCM and tracks exercise the shared-root acceptance boundary.
/// Source digests below are identity tokens only; no original media is reused.
/// Apple execution is required before these methods count as native evidence.
@MainActor
final class DuelTriadRootVictimAudioTests: XCTestCase {
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
        let sun: DuelWeaponProfile
        let liu: DuelWeaponProfile
        let throwClip: String
        let name = "Synthetic_RootVictimAudio.json"
        var document: [String: Any]
        var digest = ""
    }
    private let root = DuelTriadRootVictimState.Motion.end

    private func tracks(frames: Int) -> DuelWeaponTracks {
        let count = 2 * frames - 1
        let points = Array(repeating: DuelWeaponPoint(), count: count)
        let pelvis = Array(repeating: DuelWeaponPoint(y: 1), count: count)
        return .init(samplesPerSourceFrame: 2, root: points, handL: points, handR: points,
            footL: points, footR: points, weaponBaseL: points, weaponTipL: points,
            weaponBaseR: points, weaponTipR: points, groundLift: Array(repeating: 0, count: count),
            centerOfMass: points, pelvis: pelvis)
    }
    private func pcm(variant: UInt8) -> Data {
        var result = Data()
        func word(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { result.append(contentsOf: $0) }
        }
        func long(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { result.append(contentsOf: $0) }
        }
        result.append(contentsOf: "RIFF".utf8); long(1636)
        result.append(contentsOf: "WAVEfmt ".utf8)
        long(16); word(1); word(1); long(8000); long(16000); word(2); word(16)
        result.append(contentsOf: "data".utf8); long(1600)
        result.append(Data(repeating: variant, count: 1600))
        return result
    }
    private func write(_ value: inout Fixture) throws {
        let data = try JSONSerialization.data(withJSONObject: value.document, options: [.sortedKeys])
        try data.write(to: value.directory.appendingPathComponent(value.name))
        value.digest = DuelNetworkContentRecord.digest(data)
    }
    private func load(_ value: Fixture, liu: DuelWeaponProfile? = nil) throws -> DuelTriadAudioBinding {
        try .load(directory: value.directory, manifestName: value.name, expectedSHA256: value.digest,
                  profile: value.sun, additionalProfiles: [liu ?? value.liu])
    }
    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("root-audio-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // Sun deliberately has the same root-end basename and frame count.
        // An owner/profile bug must not accidentally play Liu's shared marker.
        let sunClip = DuelWeaponClip(name: root.clip, frames: root.frames,
            sha256: String(repeating: "c", count: 64), bundle: "synthetic-only", tracks: tracks(frames: root.frames))
        let sun = DuelWeaponProfile(id: "sun_triad", hero: .ember, faction: "Synthetic",
            resourceName: "Synthetic_Sun", bytes: 1, sha256: String(repeating: "b", count: 64),
            bodyID: "synthetic-sun-body", weaponID: "synthetic-dual-blades", activeWeaponSides: ["left", "right"],
            roles: ["idle": sunClip.name], clips: [sunClip])
        var roles: [String: String] = [:], clips: [DuelWeaponClip] = []
        var motions: [String: DuelSourceThrowMotion] = [:]
        let frames = [51, 42, 83, 81, 82, 61], ends = [92, 74, 156, 152, 154, 112]
        for (index, motion) in DuelSourceThrowRules.Motion.allCases.enumerated() {
            let role = "synthetic_throw_" + motion.rawValue, name = "synthetic_shared_" + motion.rawValue
            let count = 2 * frames[index] - 1, hash = String(repeating: String(index + 1), count: 64)
            roles[role] = name
            clips.append(.init(name: name, frames: frames[index], sha256: hash,
                               bundle: "synthetic-only", tracks: tracks(frames: frames[index])))
            motions[motion.rawValue] = .init(role: role, sourceSHA256: hash, lastSampleTick: count - 1,
                animationEndTick: ends[index], uninterruptEndTick: count,
                rootMillimeters: Array(repeating: 0, count: count), footLeftMillimeters: 0, pelvisMillimeters: 0)
        }
        let throwClip = try XCTUnwrap(clips.first).name
        let throwRules = DuelSourceThrowRules(motions: motions, normalizedUnarmedPower: 1000,
            millimetersPerSourceUnitNumerator: 92, millimetersPerSourceUnitDenominator: 10,
            maximumRangeSourceUnits: 102, forwardWallThresholdSourceUnits: 150,
            backWallThresholdSourceUnits: 100, throwDisabledAfterVictimEndTicks: 105)
        for motion in DuelTriadRootVictimState.Motion.allCases {
            clips.append(.init(name: motion.clip, frames: motion.frames, sha256: motion.sourceSHA256,
                               bundle: "synthetic-identity-contract-only", tracks: tracks(frames: motion.frames)))
        }
        let liu = DuelWeaponProfile(id: "liu_hammers", hero: .liu, faction: "Synthetic",
            resourceName: "Synthetic_Liu", bytes: 1, sha256: String(repeating: "f", count: 64),
            bodyID: "synthetic-liu-body", weaponID: "synthetic-hammers", activeWeaponSides: ["left", "right"],
            roles: roles, clips: clips, ordinaryThrows: .init(id: "synthetic-root-audio-common-throws",
                basis: .applicationAdaptation, sourceVersion: "Synthetic geometry; no original media",
                sourceSHA256: nil, evidence: [], simultaneousContactPolicy: .sourceComplementaryLottery,
                attempts: [], source: throwRules))
        var files: [[String: Any]] = [], names: [String] = []
        for index in 1...7 {
            let name = "Synthetic_Root_\(index).wav", data = pcm(variant: UInt8(index))
            try data.write(to: directory.appendingPathComponent(name)); names.append(name)
            files.append(["name": name, "bytes": data.count, "sha256": DuelNetworkContentRecord.digest(data)])
        }
        var value = Fixture(directory: directory, sun: sun, liu: liu, throwClip: throwClip, document: [
            "version": 2, "profileID": sun.id, "characterSHA256": sun.sha256,
            "sourceConfigurationSHA256": String(repeating: "d", count: 64),
            "evidence": ["Synthetic PCM and tracks; identity-contract test, not source media acceptance"],
            "context": ["gender": "Male", "floor": "Stone"], "motionProfiles": [liu.id: liu.sha256],
            "files": files, "audio": [String: [String]](), "cues": [[String: Any]](),
            "markers": [
                ["id": "liu_root_end", "profileID": liu.id, "clip": root.clip, "sourceFrame": 20,
                 "clock": "intervalStart", "context": "Common", "files": names],
                ["id": "liu_throw", "profileID": liu.id, "clip": throwClip, "sourceFrame": 7,
                 "clock": "soundFrame", "context": "Common", "files": [names[0]]]
            ]])
        try write(&value)
        return value
    }
    private func changingClips(_ profile: DuelWeaponProfile,
                               _ change: (inout [[String: Any]]) -> Void) throws -> DuelWeaponProfile {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        var clips = try XCTUnwrap(object["clips"] as? [[String: Any]])
        change(&clips); object["clips"] = clips
        return try JSONDecoder().decode(DuelWeaponProfile.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testVerifiedRootEndUsesLiuOwnershipAtTick38AndDeduplicatesTheSameFrame() throws {
        let value = try fixture(), binding = try load(value)
        XCTAssertEqual(binding.motionProfileIDs, [value.liu.id])
        XCTAssertEqual(binding.sourceFrameCounts[value.liu.id + "/" + root.clip], 48)
        XCTAssertEqual(binding.sourceFrameCounts[root.clip], 48)
        let marker = try XCTUnwrap(binding.markers.first { $0.id == "liu_root_end" })
        XCTAssertEqual(marker.playbackFrame, 19)
        XCTAssertEqual(binding.audio[marker.category]?.count, 7)
        var players: [Player] = []
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: binding) { _ in
            let player = Player(); players.append(player); return player
        }
        defer { effects.shutdown() }
        func sample(frame: Int, owner: Int, from: Int, to: Int) -> DuelSourceMotionSample {
            .init(frame: frame, sequence: 0, owner: owner, clip: root.clip,
                  previousTick: from, tick: to, duration: root.lastSampleTick)
        }
        effects.consumeTriad(events: [], samples: [sample(frame: 10, owner: 0, from: 37, to: 38)],
                             frame: 10, fighting: true, owners: [0], motionProfiles: [1: value.liu.id])
        XCTAssertEqual(effects.playedSounds, 0, "Sun cannot borrow Liu's explicit marker despite the same basename")
        effects.consumeTriad(events: [], samples: [sample(frame: 11, owner: 1, from: 36, to: 37)],
                             frame: 11, fighting: true, owners: [], motionProfiles: [1: value.liu.id])
        XCTAssertEqual(effects.playedSounds, 0, "IntervalStart20 has not crossed at tick37")
        let crossing = sample(frame: 12, owner: 1, from: 37, to: 38)
        effects.consumeTriad(events: [], samples: [crossing], frame: 12, fighting: true, owners: [])
        XCTAssertEqual(effects.playedSounds, 0, "An unbound Liu owner cannot emit the marker")
        for _ in 0..<2 {
            effects.consumeTriad(events: [], samples: [crossing], frame: 12, fighting: true,
                                 owners: [], motionProfiles: [1: value.liu.id])
        }
        effects.consumeTriad(events: [], samples: [sample(frame: 13, owner: 1, from: 38, to: 38)],
                             frame: 13, fighting: true, owners: [], motionProfiles: [1: value.liu.id])
        XCTAssertEqual(effects.playedSoundCategories, [marker.category: 1])
        XCTAssertEqual(players.reduce(0) { $0 + $1.plays }, 1)
    }

    func testRootEndRejectsWrongClockFrameContextVariantCountAndSunImpersonation() throws {
        let base = try fixture()
        for change in ["soundFrame", "missingClock", "frame19", "frame21", "context", "missingContext", "sixFiles", "duplicateFile", "sunProfile"] {
            var value = base
            var markers = value.document["markers"] as! [[String: Any]]
            switch change {
            case "soundFrame": markers[0]["clock"] = "soundFrame"
            case "missingClock": markers[0].removeValue(forKey: "clock")
            case "frame19": markers[0]["sourceFrame"] = 19
            case "frame21": markers[0]["sourceFrame"] = 21
            case "context": markers[0]["context"] = "Gender.Male"
            case "missingContext": markers[0].removeValue(forKey: "context")
            case "sixFiles": markers[0]["files"] = Array((markers[0]["files"] as! [String]).prefix(6))
            case "duplicateFile":
                var names = markers[0]["files"] as! [String]; names[6] = names[0]; markers[0]["files"] = names
            default: markers[0]["profileID"] = "sun_triad"
            }
            value.document["markers"] = markers; try write(&value)
            XCTAssertThrowsError(try load(value), "Must reject root-end contract drift: \(change)")
        }
    }

    func testEveryVictimClipMustMatchSourceSHAFramesTicksGridAndPelvisBeforeSharing() throws {
        let value = try fixture()
        XCTAssertTrue(DuelTriadRootVictimState.matches(profile: value.liu))
        for motion in DuelTriadRootVictimState.Motion.allCases {
            for change in ["sha", "frames", "ticks", "sampleGrid", "missingPelvis", "shortPelvis", "missingClip"] {
                let other = try changingClips(value.liu) { clips in
                    let index = clips.firstIndex { $0["name"] as? String == motion.clip }!
                    switch change {
                    case "sha": clips[index]["sha256"] = String(repeating: "a", count: 64)
                    case "frames": clips[index]["frames"] = motion.frames + 1
                    case "ticks": clips[index]["playbackTicks"] = motion.lastSampleTick + 1
                    case "missingClip": clips.remove(at: index)
                    default:
                        var tracks = clips[index]["tracks"] as! [String: Any]
                        if change == "sampleGrid" { tracks["samplesPerSourceFrame"] = 1 }
                        else if change == "missingPelvis" { tracks.removeValue(forKey: "pelvis") }
                        else { tracks["pelvis"] = Array((tracks["pelvis"] as! [[Double]]).dropLast()) }
                        clips[index]["tracks"] = tracks
                    }
                }
                XCTAssertFalse(DuelTriadRootVictimState.matches(profile: other), "\(motion.clip): \(change)")
                XCTAssertThrowsError(try load(value, liu: other), "\(motion.clip): \(change)")
            }
        }
    }

    func testOrdinarySharedThrowsKeepSoundFrameClockWithoutTheRootEndException() throws {
        var value = try fixture()
        let binding = try load(value)
        let marker = try XCTUnwrap(binding.markers.first { $0.id == "liu_throw" })
        XCTAssertEqual(marker.clock, .soundFrame); XCTAssertEqual(marker.playbackFrame, 7)
        let effects = try DuelSourceEffects.triadAudioFixture(root: SCNNode(), binding: binding) { _ in Player() }
        defer { effects.shutdown() }
        for (frame, before, tick) in [(10, 11, 12), (11, 13, 14)] {
            let sample = DuelSourceMotionSample(frame: frame, sequence: 0, owner: 1, clip: value.throwClip,
                                                previousTick: before, tick: tick, duration: 100)
            effects.consumeTriad(events: [], samples: [sample], frame: frame, fighting: true,
                                 owners: [], motionProfiles: [1: value.liu.id])
            XCTAssertEqual(effects.playedSounds, frame == 10 ? 0 : 1)
        }
        XCTAssertEqual(effects.playedSoundCategories, [marker.category: 1])
        let original = value.document
        for clock in ["intervalStart", "animationStart", "missing"] {
            value.document = original
            var markers = value.document["markers"] as! [[String: Any]]
            if clock == "missing" { markers[1].removeValue(forKey: "clock") }
            else { markers[1]["clock"] = clock }
            value.document["markers"] = markers; try write(&value)
            XCTAssertThrowsError(try load(value), "Shared ordinary throw must remain soundFrame: \(clock)")
        }
    }

    func testMorphTargetMetadataAcceptsOnlyReviewedHammersAndCompleteNewVictimCapability() throws {
        // Pure metadata gate. These synthetic tracks do not authenticate a
        // GLB, render a morph, or establish that D19 equipment was supplied.
        let oldHash = "f83d8cbbd7b2158604dad9eff28398bcf57c64fdcb4146e5c142608484a5a472"
        let newHash = "a3aada76d336b9c4f9bda3904b5e947711d916f683a2dcbf7b8184377e01a517"
        let clips = DuelTriadRootVictimState.Motion.allCases.map { motion in
            DuelWeaponClip(name: motion.clip, frames: motion.frames, sha256: motion.sourceSHA256,
                           bundle: "synthetic-identity-contract-only", tracks: tracks(frames: motion.frames))
        }
        let reviewed = DuelWeaponProfile(id: "liu_hammers", hero: .liu, faction: "Synthetic",
            resourceName: "Synthetic_Liu_Metadata", bytes: 1, sha256: newHash,
            bodyID: "arm__str_03", weaponID: "wpn__hammers_01_01", activeWeaponSides: ["left", "right"],
            roles: [:], clips: clips)
        XCTAssertTrue(DuelTriadSourceMorphAssets.acceptsReviewedTarget(reviewed))
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reviewed)) as? [String: Any])
        func altered(_ changes: [String: Any]) throws -> DuelWeaponProfile {
            var object = base
            for (key, value) in changes { object[key] = value }
            return try JSONDecoder().decode(DuelWeaponProfile.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let old = try altered(["sha256": oldHash, "clips": [[String: Any]]()])
        XCTAssertTrue(DuelTriadSourceMorphAssets.acceptsReviewedTarget(old), "Keep the reviewed original hammers target")
        let missing = try altered(["clips": [[String: Any]]()])
        XCTAssertFalse(DuelTriadSourceMorphAssets.acceptsReviewedTarget(missing), "The new container needs all victim clips")
        let wrongMotion = try changingClips(reviewed) { $0[0]["sha256"] = String(repeating: "a", count: 64) }
        XCTAssertFalse(DuelTriadSourceMorphAssets.acceptsReviewedTarget(wrongMotion))
        for changes: [String: Any] in [
            ["sha256": String(repeating: "e", count: 64)],
            ["id": "liu_pangu"], ["hero": DuelGame.Hero.ember.rawValue],
            ["bodyID": "unreviewed_pangu_body"], ["weaponID": "unreviewed_pangu_axe"]
        ] {
            XCTAssertFalse(DuelTriadSourceMorphAssets.acceptsReviewedTarget(try altered(changes)))
        }
    }
}
#endif
