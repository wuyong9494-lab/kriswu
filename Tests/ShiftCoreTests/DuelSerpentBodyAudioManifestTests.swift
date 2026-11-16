import Foundation
import XCTest
@testable import ShiftCore

final class DuelSerpentBodyAudioManifestTests: XCTestCase {
    private func input() throws -> (URL, Data, DuelWeaponProfile) {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["SERPENT_BODY_AUDIO_DIRECTORY"], let profile = env["SERPENT_MATCH_PROFILE"] else {
            throw XCTSkip("Actual authenticated D13 body audio and match profile required")
        }
        let base = URL(fileURLWithPath: directory)
        return (base, try Data(contentsOf: base.appendingPathComponent("SF3_Serpent_Body_Audio.json")),
                try JSONDecoder().decode(DuelWeaponProfile.self, from: Data(contentsOf: URL(fileURLWithPath: profile))))
    }

    func testActualSixtySixPCMFilesAndSourceClockRecordsAreComplete() throws {
        let (base, raw, profile) = try input()
        let document = try JSONDecoder().decode(DuelSerpentBodyAudioManifest.self, from: raw)
        try document.validate(profile: profile)
        XCTAssertEqual(document.markers.count, 135)
        XCTAssertEqual(document.excludedExistingBodyMarkers.count, 4)
        XCTAssertEqual(Set(document.markers.map { $0.choices.map(\.file) }).count, 19)
        XCTAssertEqual(document.markers.reduce(0) { $0 + $1.choices.count }, 639)
        XCTAssertTrue(document.markers.contains { Set($0.choices).count < $0.choices.count },
                      "Authored repeated candidates retain their selection weight")
        var bytes = 0
        for file in document.files {
            let wav = try Data(contentsOf: base.appendingPathComponent(file.name))
            let pcm = try DuelSerpentSourceAudioManifest.pcmPayload(wav, file: file)
            XCTAssertEqual(pcm.count, file.sampleFrames * file.channels * 2)
            bytes += wav.count
        }
        XCTAssertEqual(bytes, 2_971_156)
    }

    func testEveryActualMarkerUsesItsOriginalIntervalAndCannotReplayOnDisplay() throws {
        let (_, raw, profile) = try input()
        let document = try JSONDecoder().decode(DuelSerpentBodyAudioManifest.self, from: raw)
        try document.validate(profile: profile)
        var clock = DuelSerpentBodyAudioClock()
        let markers = document.markers.map(\.clock)
        for (frame, marker) in document.markers.enumerated() {
            let sample = DuelSourceMotionSample(frame: frame, sequence: 0, owner: frame % 2,
                clip: marker.clip, previousTick: marker.tick - 1, tick: marker.tick, duration: marker.playbackTicks)
            let result = clock.consume(markers: markers, samples: [sample], frame: frame,
                paused: false, owners: [0, 1], stageSHA256: DuelSerpentBodyAudioClock.palaceStageSHA256)
            XCTAssertEqual(result, [.init(owner: frame % 2, markerID: marker.id)], marker.id)
            XCTAssertTrue(clock.consume(markers: markers, samples: [sample], frame: frame,
                paused: false, owners: [0, 1], stageSHA256: DuelSerpentBodyAudioClock.palaceStageSHA256).isEmpty)
        }
    }

    func testWrongActorConfigurationCroppedClockAndDuplicateBoundEventsFailClosed() throws {
        let (_, raw, profile) = try input()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        for mutation in 0..<9 {
            var object = original
            switch mutation {
            case 0: object["profileID"] = "wuyong_erlang"
            case 1: object["sourceMatchProfileSHA256"] = String(repeating: "0", count: 64)
            case 2:
                var configs = object["sourceConfigurationHashes"] as! [String: String]
                configs["settings_style_shuangou.bytes"] = String(repeating: "1", count: 64)
                object["sourceConfigurationHashes"] = configs
            case 3:
                var context = object["context"] as! [String: Any]
                context["stageSHA256"] = String(repeating: "0", count: 64); object["context"] = context
            case 4:
                var markers = object["markers"] as! [[String: Any]]
                markers[0]["tick"] = (markers[0]["tick"] as! Int) - 2; object["markers"] = markers
            case 5:
                var clips = object["clips"] as! [[String: Any]]
                clips[0]["sourceMotionSHA256"] = String(repeating: "0", count: 64); object["clips"] = clips
            case 6:
                var markers = object["markers"] as! [[String: Any]]
                markers[0] = (object["excludedExistingBodyMarkers"] as! [[String: Any]])[0]
                object["markers"] = markers
            case 7:
                var markers = object["markers"] as! [[String: Any]]
                var choices = markers[0]["choices"] as! [[String: Any]]
                choices[0]["bus"] = "Invented"; markers[0]["choices"] = choices; object["markers"] = markers
            default:
                var clips = object["clips"] as! [[String: Any]]
                clips[1] = clips[0]; object["clips"] = clips
            }
            let changed = try JSONDecoder().decode(DuelSerpentBodyAudioManifest.self,
                from: JSONSerialization.data(withJSONObject: object))
            XCTAssertThrowsError(try changed.validate(profile: profile), "mutation \(mutation)")
        }
    }
}
