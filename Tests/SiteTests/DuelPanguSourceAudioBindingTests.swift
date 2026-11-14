import XCTest
import SceneKit
@testable import ShiftReminder

#if DEBUG
/// Synthetic PCM and identities exercise the authenticated binding contract.
/// These fixtures are not recovered Pangu sounds or retail timing evidence.
@MainActor
final class DuelPanguSourceAudioBindingTests: XCTestCase {
    private final class Player: DuelEffectPlayback {
        let duration: TimeInterval = 0.1
        var currentTime: TimeInterval = 0
        var isPlaying = false
        var plays = 0
        func prepareToPlay() -> Bool { true }
        func play() -> Bool { isPlaying = true; plays += 1; return true }
        func pause() { isPlaying = false }
        func stop() { isPlaying = false }
    }

    private struct Fixture {
        let directory: URL
        let name: String
        let profile: DuelWeaponProfile
        var document: [String: Any]
        var digest: String
    }

    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pangu-audio-contract-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let profile = DuelWeaponProfile(id: "liu_pangu", hero: .liu, faction: "synthetic", resourceName: "Synthetic_Pangu",
            bytes: 1, sha256: String(repeating: "b", count: 64), bodyID: "synthetic-body", weaponID: "synthetic-axe",
            activeWeaponSides: ["right"], roles: [:], clips: [], comboLinks: nil)
        var files: [[String: Any]] = [], audio: [String: [String]] = [:]
        for (index, category) in ["panguHit", "panguBlock", "panguWhoosh"].enumerated() {
            let name = "Synthetic_\(category).wav", data = wav(sample: UInt8(index + 1))
            try data.write(to: directory.appendingPathComponent(name))
            files.append(["name": name, "bytes": data.count, "sha256": DuelNetworkContentRecord.digest(data)])
            audio[category] = [name]
        }
        var result = Fixture(directory: directory, name: "Synthetic_PanguAudio.json", profile: profile,
            document: ["version": 1, "profileID": profile.id, "characterSHA256": profile.sha256,
                       "files": files, "audio": audio], digest: "")
        try write(&result)
        return result
    }

    private func wav(sample: UInt8) -> Data {
        var result = Data()
        func word(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { result.append(contentsOf: $0) } }
        func long(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { result.append(contentsOf: $0) } }
        result.append(contentsOf: "RIFF".utf8); long(36 + 1600); result.append(contentsOf: "WAVEfmt ".utf8)
        long(16); word(1); word(1); long(8000); long(16000); word(2); word(16)
        result.append(contentsOf: "data".utf8); long(1600)
        result.append(Data(repeating: sample, count: 1600))
        return result
    }

    private func write(_ fixture: inout Fixture) throws {
        let data = try JSONSerialization.data(withJSONObject: fixture.document, options: [.sortedKeys])
        try data.write(to: fixture.directory.appendingPathComponent(fixture.name))
        fixture.digest = DuelNetworkContentRecord.digest(data)
    }
    private func load(_ fixture: Fixture) throws -> DuelSourceEffects.PanguAudioBinding {
        try .load(directory: fixture.directory, manifestName: fixture.name,
                  expectedSHA256: fixture.digest, profile: fixture.profile)
    }

    private func addCues(_ cues: [[String: Any]], to fixture: inout Fixture) throws {
        let data = wav(sample: 12), name = "Synthetic_skill_cue.wav"
        try data.write(to: fixture.directory.appendingPathComponent(name))
        var files = try XCTUnwrap(fixture.document["files"] as? [[String: Any]])
        files.append(["name": name, "bytes": data.count, "sha256": DuelNetworkContentRecord.digest(data)])
        fixture.document["files"] = files
        fixture.document["cues"] = cues.map { cue in
            var cue = cue; cue["files"] = [name]; return cue
        }
        try write(&fixture)
    }

    private func event(_ kind: DuelPanguPresentation.Event.Kind, frame: Int = 10,
                       sequence: Int = 0) -> DuelPanguPresentation.Event {
        .init(id: .init(frame: frame, sequence: sequence), liveTick: 3, kind: kind)
    }

    func testExactTargetIdentityAndAllContentReceiptsAreRequired() throws {
        let fixture = try fixture(), binding = try load(fixture)
        XCTAssertEqual(binding.profileID, "liu_pangu")
        XCTAssertEqual(binding.characterSHA256, fixture.profile.sha256)
        XCTAssertEqual(binding.verifiedFiles.count, 4)
        XCTAssertEqual(Set(binding.verifiedFiles.map(\.path)),
            [fixture.name, "Synthetic_panguHit.wav", "Synthetic_panguBlock.wav", "Synthetic_panguWhoosh.wav"])
        for file in binding.verifiedFiles {
            let data = try Data(contentsOf: fixture.directory.appendingPathComponent(file.path))
            XCTAssertEqual(data.count, file.bytes)
            XCTAssertEqual(DuelNetworkContentRecord.digest(data), file.sha256)
        }
    }

    func testWrongManifestPinProfileAndCharacterCannotLoad() throws {
        var fixture = try fixture()
        XCTAssertThrowsError(try DuelSourceEffects.PanguAudioBinding.load(directory: fixture.directory,
            manifestName: fixture.name, expectedSHA256: String(repeating: "0", count: 64), profile: fixture.profile))
        fixture.document["profileID"] = "liu_hammers"; try write(&fixture)
        XCTAssertThrowsError(try load(fixture))
        fixture.document["profileID"] = "liu_pangu"
        fixture.document["characterSHA256"] = String(repeating: "a", count: 64); try write(&fixture)
        XCTAssertThrowsError(try load(fixture))
    }

    func testMissingUnknownAndDuplicateAudioBindingsFailClosed() throws {
        for mutation in ["missing", "unknown", "duplicate", "unused"] {
            var fixture = try fixture()
            var audio = try XCTUnwrap(fixture.document["audio"] as? [String: [String]])
            switch mutation {
            case "missing": audio.removeValue(forKey: "panguWhoosh")
            case "unknown": audio["hammerWhoosh"] = ["Synthetic_panguWhoosh.wav"]
            case "duplicate": audio["panguHit"] = ["Synthetic_panguHit.wav", "Synthetic_panguHit.wav"]
            default: audio["panguWhoosh"] = ["Synthetic_panguHit.wav"]
            }
            fixture.document["audio"] = audio; try write(&fixture)
            XCTAssertThrowsError(try load(fixture), mutation)
        }
    }

    func testMissingCorruptSymlinkAndEscapingResourcesFailClosed() throws {
        for mutation in ["missing", "corrupt", "symlink", "path"] {
            var fixture = try fixture()
            let audioURL = fixture.directory.appendingPathComponent("Synthetic_panguHit.wav")
            switch mutation {
            case "missing": try FileManager.default.removeItem(at: audioURL)
            case "corrupt": try Data(repeating: 0, count: 1644).write(to: audioURL)
            case "symlink":
                try FileManager.default.removeItem(at: audioURL)
                try FileManager.default.createSymbolicLink(at: audioURL,
                    withDestinationURL: fixture.directory.appendingPathComponent("Synthetic_panguBlock.wav"))
            default:
                var audio = try XCTUnwrap(fixture.document["audio"] as? [String: [String]])
                audio["panguHit"] = ["../Synthetic_panguHit.wav"]
                fixture.document["audio"] = audio
                var files = try XCTUnwrap(fixture.document["files"] as? [[String: Any]])
                files[0]["name"] = "../Synthetic_panguHit.wav"; fixture.document["files"] = files
                try write(&fixture)
            }
            XCTAssertThrowsError(try load(fixture), mutation)
        }
    }

    func testVerifiedBytesSurviveFileRemovalAndOnlyPlayPanguCategories() throws {
        let fixture = try fixture(), binding = try load(fixture)
        var players: [Player] = [], decodedDigests: [String] = []
        // The retained binding owns bytes; runtime recovery must not reopen disk.
        for file in binding.verifiedFiles { try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent(file.path)) }
        let effects = try DuelSourceEffects.panguAudioFixture(root: SCNNode(), binding: binding) { data in
            decodedDigests.append(DuelNetworkContentRecord.digest(data))
            let player = Player(); players.append(player); return player
        }
        defer { effects.shutdown() }
        XCTAssertEqual(Set(decodedDigests), Set(binding.verifiedFiles.filter { $0.path.hasSuffix(".wav") }.map(\.sha256)))
        effects.playWhoosh(heavy: false, tick: 1, sound: .pangu)
        effects.emit(kind: .hit, position: SCNVector3Zero, direction: 1, tick: 1, sound: .pangu)
        effects.emit(kind: .block, position: SCNVector3Zero, direction: -1, tick: 2, sound: .pangu)
        XCTAssertEqual(effects.playedSoundCategories, ["panguHit": 1, "panguBlock": 1, "panguWhoosh": 1])
        effects.playWhoosh(heavy: false, tick: 3, sound: .katana)
        effects.emit(kind: .hit, position: SCNVector3Zero, direction: 1, tick: 3, sound: .dualHammers)
        XCTAssertEqual(effects.playedSounds, 3)
        effects.setPaused(true)
        effects.playWhoosh(heavy: false, tick: 4, sound: .pangu)
        XCTAssertEqual(effects.playedSounds, 3)
        XCTAssertTrue(players.allSatisfy { !$0.isPlaying })
        effects.shutdown()
        effects.playWhoosh(heavy: false, tick: 5, sound: .pangu)
        XCTAssertEqual(effects.allocatedAudioPlayerCount, 0)
        XCTAssertTrue(players.allSatisfy { !$0.isPlaying })
    }

    func testAnUnboundTargetCannotFallBackToLegacyAudio() {
        let effects = DuelSourceEffects.preparationFixture(root: SCNNode())
        defer { effects.shutdown() }
        effects.playWhoosh(heavy: true, tick: 1, sound: .pangu)
        effects.emit(kind: .hit, position: SCNVector3Zero, direction: 1, tick: 1, sound: .pangu)
        XCTAssertEqual(effects.playedSounds, 0)
        XCTAssertTrue(effects.playedSoundCategories.isEmpty)
    }

    func testEverySupportedCueUsesItsExactAcceptedEventAndCastPhase() throws {
        var fixture = try fixture()
        try addCues([
            ["id": "start", "event": "castStarted", "ability": "heavenfall", "phase": "petrifying"],
            ["id": "charge", "event": "castPhase", "ability": "heavenfall", "phase": "charging"],
            ["id": "release", "event": "attackReleased", "ability": "shard", "generated": false, "empowered": false],
            ["id": "impact", "event": "contact", "ability": "shard", "contactKind": "hit", "generated": false, "empowered": false],
            ["id": "teleport", "event": "teleported"],
            ["id": "landing", "event": "landed"],
            ["id": "escape", "event": "ordinaryThrowEscaped"]
        ], to: &fixture)
        let effects = try DuelSourceEffects.panguAudioFixture(root: SCNNode(), binding: load(fixture)) { _ in Player() }
        defer { effects.shutdown() }
        let volume = DuelPanguPresentation.Volume(id: .init(owner: 1, attackID: 3), ability: .shard,
            delivery: .ground, damageKind: .shadow, generated: false, empowered: false, direction: -1,
            center: .init(), bounds: .init(minX: 0, maxX: 100, minY: 0, maxY: 100),
            radiusMillimeters: 50, expiresAtTick: 20)
        let contact = DuelPanguPresentation.Contact(owner: 1, target: 0, attackID: 3, ability: .shard,
            delivery: .ground, damageKind: .shadow, generated: false, empowered: false,
            kind: .hit, position: .init(), direction: -1)
        let kinds: [DuelPanguPresentation.Event.Kind] = [
            .castStarted(.init(owner: 1, id: 4, ability: .heavenfall, phase: .petrifying,
                              tick: 0, duration: 20, empowered: false, position: .init())),
            .castPhase(owner: 1, ability: .heavenfall, phase: .charging),
            .attackReleased(volume), .contact(contact),
            .teleported(owner: 1, from: .init(), to: .init(x: 1)),
            .landed(owner: 1, position: .init()), .ordinaryThrowEscaped(attacker: 0, target: 1, position: .init())
        ]
        let events = kinds.enumerated().map { event($0.element, sequence: $0.offset) }
        effects.consumePangu(events: events, frame: 10, fighting: true)
        effects.consumePangu(events: events, frame: 10, fighting: true)
        XCTAssertEqual(effects.playedSounds, 7)
        XCTAssertEqual(Set(effects.playedSoundCategories.keys),
            Set(["start", "charge", "release", "impact", "teleport", "landing", "escape"].map { "panguCue:" + $0 }))
        effects.consumePangu(events: [
            event(.castPhase(owner: 1, ability: .heavenfall, phase: .rising), sequence: 7),
            event(.castPhase(owner: 1, ability: .shard, phase: .charging), sequence: 8)
        ], frame: 10, fighting: true)
        XCTAssertEqual(effects.playedSounds, 7, "Other abilities/phases never select the closest cue")
        XCTAssertNil(effects.playedSoundCategories["panguWhoosh"])
    }

    func testCueDedupKeepsDistinctSequencesAndPausedEventsRemainUnconsumed() throws {
        var fixture = try fixture()
        try addCues([["id": "active", "event": "castPhase", "ability": "shard", "phase": "active"]], to: &fixture)
        let effects = try DuelSourceEffects.panguAudioFixture(root: SCNNode(), binding: load(fixture)) { _ in Player() }
        defer { effects.shutdown() }
        let first = event(.castPhase(owner: 1, ability: .shard, phase: .active))
        effects.consumePangu(events: [first], frame: 10, fighting: true)
        effects.consumePangu(events: [first], frame: 10, fighting: true)
        XCTAssertEqual(effects.playedSounds, 1)
        let next = event(.castPhase(owner: 1, ability: .shard, phase: .active), frame: 11)
        effects.setPaused(true)
        effects.consumePangu(events: [next], frame: 11, fighting: true)
        XCTAssertEqual(effects.playedSounds, 1)
        effects.setPaused(false)
        effects.consumePangu(events: [next], frame: 11, fighting: true)
        let second = event(.castPhase(owner: 1, ability: .shard, phase: .active), frame: 11, sequence: 1)
        effects.consumePangu(events: [next, second], frame: 11, fighting: true)
        effects.consumePangu(events: [second], frame: 11, fighting: true)
        effects.consumePangu(events: [first], frame: 10, fighting: true)
        XCTAssertEqual(effects.playedSounds, 3)
        effects.reset()
        effects.consumePangu(events: [first], frame: 10, fighting: true)
        XCTAssertEqual(effects.playedSounds, 1)
        effects.shutdown()
        effects.consumePangu(events: [next], frame: 11, fighting: true)
        XCTAssertEqual(effects.playedSounds, 0)
    }

    func testUnknownAmbiguousOrUnmatchableCueMappingsFailClosed() throws {
        let invalid: [[[String: Any]]] = [
            [["id": "bad", "event": "guessedAnimation"]],
            [["id": "bad", "event": "castPhase", "phase": "active"]],
            [["id": "bad", "event": "castStarted", "ability": "shard", "phase": "unmeasured"]],
            [["id": "bad", "event": "teleported", "ability": "shard"]],
            [["id": "bad", "event": "contact", "ability": "shard"]],
            [["id": "bad", "event": "attackReleased", "ability": "splitter", "generated": false]],
            [["id": "bad", "event": "contact", "ability": "heavenfall", "contactKind": "hit", "empowered": false]],
            [["id": "bad", "event": "castPhase", "ability": "shard", "phase": "active", "generated": false]],
            [["id": "bad", "event": "landed", "empowered": true]],
            [["id": "one", "event": "landed"], ["id": "two", "event": "landed"]]
        ]
        for cues in invalid {
            var fixture = try fixture(); try addCues(cues, to: &fixture)
            XCTAssertThrowsError(try load(fixture))
        }
    }

    func testMissingSkillCueAndSilentImpactCannotUseGenericPanguAudio() throws {
        let fixture = try fixture()
        let effects = try DuelSourceEffects.panguAudioFixture(root: SCNNode(), binding: load(fixture)) { _ in Player() }
        defer { effects.shutdown() }
        effects.consumePangu(events: [event(.castPhase(owner: 1, ability: .shard, phase: .active))], frame: 10, fighting: true)
        effects.emit(kind: .hit, position: SCNVector3Zero, direction: 1, tick: 10, sound: .silent)
        effects.playWhoosh(heavy: false, tick: 10, sound: .silent)
        XCTAssertEqual(effects.emittedHits, 1, "Shared contact artwork remains independent of target audio")
        XCTAssertEqual(effects.playedSounds, 0)
        XCTAssertTrue(effects.playedSoundCategories.isEmpty)
    }

    func testNilAbilityCueOnlyMatchesGeneratedAttackAndNeverOrdinaryContact() throws {
        var fixture = try fixture()
        try addCues([["id": "derived", "event": "contact", "contactKind": "hit", "generated": true, "empowered": false]], to: &fixture)
        let effects = try DuelSourceEffects.panguAudioFixture(root: SCNNode(), binding: load(fixture)) { _ in Player() }
        defer { effects.shutdown() }
        func contact(attackID: UInt64?) -> DuelPanguPresentation.Contact {
            .init(owner: 1, target: 0, attackID: attackID, ability: nil,
                  delivery: attackID == nil ? nil : .windBlade, damageKind: .weapon,
                  generated: attackID != nil, empowered: false, kind: .hit, position: .init(), direction: 1)
        }
        effects.consumePangu(events: [event(.contact(contact(attackID: nil)))], frame: 10, fighting: true)
        XCTAssertEqual(effects.playedSounds, 0)
        effects.consumePangu(events: [event(.contact(contact(attackID: 9)), sequence: 1)], frame: 10, fighting: true)
        XCTAssertEqual(effects.playedSoundCategories, ["panguCue:derived": 1])
    }

    func testFinishingStepConsumesAcceptedCuesOnceAfterCombatPhaseChanges() throws {
        var fixture = try fixture()
        try addCues([
            ["id": "finish", "event": "contact", "ability": "heavenfall", "contactKind": "hit",
             "generated": false, "empowered": true],
            ["id": "land", "event": "landed"]
        ], to: &fixture)
        let effects = try DuelSourceEffects.panguAudioFixture(root: SCNNode(), binding: load(fixture)) { _ in Player() }
        defer { effects.shutdown() }
        let impact = DuelPanguPresentation.Contact(owner: 1, target: 0, attackID: 21, ability: .heavenfall,
            delivery: .landingShock, damageKind: .shadow, generated: false, empowered: true,
            kind: .hit, position: .init(), direction: -1)
        let finish = event(.contact(impact), frame: 42)
        let landing = event(.landed(owner: 1, position: .init()), frame: 42, sequence: 1)
        effects.consumePangu(events: [], frame: 41, fighting: true)
        // The fixed step's current phase is already roundBreak or matchOver.
        effects.setPaused(true)
        effects.consumePangu(events: [finish], frame: 42, fighting: false)
        XCTAssertEqual(effects.playedSounds, 0)
        effects.setPaused(false)
        effects.consumePangu(events: [finish], frame: 42, fighting: false)
        effects.consumePangu(events: [finish, landing], frame: 42, fighting: false)
        XCTAssertEqual(effects.playedSoundCategories, ["panguCue:finish": 1, "panguCue:land": 1])
        effects.consumePangu(events: [], frame: 42, fighting: false)
        effects.consumePangu(events: [finish, landing], frame: 42, fighting: false)
        XCTAssertEqual(effects.playedSounds, 2, "An empty final-frame draw must not erase deduplication")
        effects.consumePangu(events: [], frame: 43, fighting: false)
        effects.consumePangu(events: [finish, landing], frame: 43, fighting: false)
        effects.consumePangu(events: [finish, landing], frame: 42, fighting: false)
        XCTAssertEqual(effects.playedSounds, 2, "Break steps cannot replay a previous accepted final hit")
    }

    func testReleasedAndContactCuesSeparateGeneratedAndEmpoweredVariants() throws {
        var fixture = try fixture(), cues: [[String: Any]] = []
        var events: [(DuelPanguPresentation.Event, String)] = []
        for ability in [DuelPanguRules.Ability.splitter, .heavenfall] {
            for generated in [false, true] {
                for empowered in [false, true] {
                    let suffix = "\(ability.rawValue)_\(generated ? "derived" : "primary")_\(empowered ? "empowered" : "plain")"
                    let releaseID = "release_" + suffix, contactID = "contact_" + suffix
                    cues.append(["id": releaseID, "event": "attackReleased", "ability": ability.rawValue,
                                 "generated": generated, "empowered": empowered])
                    cues.append(["id": contactID, "event": "contact", "ability": ability.rawValue,
                                 "contactKind": "hit", "generated": generated, "empowered": empowered])
                    let attackID = UInt64(events.count + 1)
                    let delivery: DuelPanguRules.Delivery = generated ? .windBlade : .landingShock
                    let volume = DuelPanguPresentation.Volume(id: .init(owner: 1, attackID: attackID), ability: ability,
                        delivery: delivery, damageKind: .shadow, generated: generated, empowered: empowered, direction: 1,
                        center: .init(), bounds: .init(minX: 0, maxX: 100, minY: 0, maxY: 100),
                        radiusMillimeters: 50, expiresAtTick: 20)
                    let contact = DuelPanguPresentation.Contact(owner: 1, target: 0, attackID: attackID, ability: ability,
                        delivery: delivery, damageKind: .shadow, generated: generated, empowered: empowered,
                        kind: .hit, position: .init(), direction: 1)
                    events.append((event(.attackReleased(volume), sequence: events.count), "panguCue:" + releaseID))
                    events.append((event(.contact(contact), sequence: events.count), "panguCue:" + contactID))
                }
            }
        }
        try addCues(cues, to: &fixture)
        let effects = try DuelSourceEffects.panguAudioFixture(root: SCNNode(), binding: load(fixture)) { _ in Player() }
        defer { effects.shutdown() }
        var expected: [String: Int] = [:]
        for (accepted, category) in events {
            effects.consumePangu(events: [accepted], frame: 10, fighting: true)
            expected[category] = 1
            XCTAssertEqual(effects.playedSoundCategories, expected,
                           "Each source cue must match one exact ability/generated/empowered tuple")
        }
        effects.consumePangu(events: events.map(\.0), frame: 10, fighting: true)
        XCTAssertEqual(effects.playedSounds, 16)
    }
}
#endif
