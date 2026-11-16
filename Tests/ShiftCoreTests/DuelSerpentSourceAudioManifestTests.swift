import Foundation
import XCTest
@testable import ShiftCore

final class DuelSerpentSourceAudioManifestTests: XCTestCase {
    private func input() throws -> (URL, Data, DuelWeaponProfile) {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["SERPENT_AUDIO_DIRECTORY"], let profile = env["SERPENT_MATCH_PROFILE"] else {
            throw XCTSkip("Authenticated D13 PCM and actual body profile required")
        }
        let base = URL(fileURLWithPath: directory)
        return (base, try Data(contentsOf: base.appendingPathComponent("SF3_Serpent_Audio.json")),
                try JSONDecoder().decode(DuelWeaponProfile.self, from: Data(contentsOf: URL(fileURLWithPath: profile))))
    }

    func testActualSourceManifestKeepsSixBoundSoundsAndEightUnboundFilesSeparate() throws {
        let (base, raw, profile) = try input()
        let value = try JSONDecoder().decode(DuelSerpentSourceAudioManifest.self, from: raw)
        try value.validate(profile: profile)
        XCTAssertEqual(value.files.count, 14)
        XCTAssertEqual(value.unbound.count, 8)
        XCTAssertEqual(value.bodyMarkers.count, 4)
        XCTAssertEqual(value.triggerSources.count, 7)
        XCTAssertEqual(value.sounds.filter(\.loop).map(\.identifier), [DuelSerpentRainRuntime.rainSound])
        var total = 0
        for file in value.files {
            let wav = try Data(contentsOf: base.appendingPathComponent(file.name))
            let pcm = try DuelSerpentSourceAudioManifest.pcmPayload(wav, file: file)
            XCTAssertEqual(pcm.count, file.sampleFrames * file.channels * file.sampleWidth)
            total += wav.count
        }
        XCTAssertEqual(total, 2_837_484)
    }

    func testRewiredSoundOrSourceTickAndUnboundFileCannotPassValidation() throws {
        let (_, raw, profile) = try input()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        for mutation in 0..<6 {
            var object = original
            switch mutation {
            case 0:
                var sounds = object["sounds"] as! [[String: Any]]
                sounds[0]["loop"] = true; object["sounds"] = sounds
            case 1:
                var sounds = object["sounds"] as! [[String: Any]]
                sounds[0]["file"] = sounds[1]["file"]; object["sounds"] = sounds
            case 2:
                var markers = object["bodyMarkers"] as! [[String: Any]]
                markers[0]["tick"] = 35; object["bodyMarkers"] = markers
            case 3:
                var unbound = object["unbound"] as! [[String: Any]]
                unbound[0]["file"] = (object["sounds"] as! [[String: Any]])[0]["file"]
                object["unbound"] = unbound
            case 4:
                var triggers = object["triggerSources"] as! [[String: Any]]
                triggers[3]["stop"] = false; object["triggerSources"] = triggers
            default:
                object["characterSHA256"] = String(repeating: "0", count: 64)
            }
            let changed = try JSONDecoder().decode(DuelSerpentSourceAudioManifest.self,
                from: JSONSerialization.data(withJSONObject: object))
            XCTAssertThrowsError(try changed.validate(profile: profile), "mutation \(mutation)")
        }
    }

    func testPCMRejectsTruncationFormatSpoofAndImpossibleChunkSize() throws {
        let (base, raw, _) = try input()
        let value = try JSONDecoder().decode(DuelSerpentSourceAudioManifest.self, from: raw)
        let file = try XCTUnwrap(value.files.first)
        let original = try Data(contentsOf: base.appendingPathComponent(file.name))
        for mutation in 0..<5 {
            var data = original
            switch mutation {
            case 0: data.removeLast()
            case 1: data[20] = 3 // IEEE float is not the authored 16-bit PCM.
            case 2: data[28] ^= 1 // byte rate must agree with the verified format.
            case 3: data.replaceSubrange(16..<20, with: [255, 255, 255, 255])
            default: data[40] ^= 1 // data byte count must match exact sample frames.
            }
            XCTAssertThrowsError(try DuelSerpentSourceAudioManifest.pcmPayload(data, file: file), "mutation \(mutation)")
        }
    }
}
