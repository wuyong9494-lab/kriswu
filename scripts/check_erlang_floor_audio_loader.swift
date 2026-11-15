import Foundation
@testable import ShiftCore

/// Only the newly bound Palace Floor source and its runtime selection.
@main
struct ErlangFloorAudioLoaderChecks {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    @MainActor
    static func main() throws {
        let args = CommandLine.arguments
        require(args.count == 4, "expected directory, manifest SHA256 and profile SHA256")
        let directory = URL(fileURLWithPath: args[1], isDirectory: true)
        let profileData = try Data(contentsOf: directory.appendingPathComponent("SF3_Erlang_Profile.json"))
        let profile = try JSONDecoder().decode(DuelWeaponProfile.self, from: profileData)
        let manifest = try Data(contentsOf: directory.appendingPathComponent("SF3_Erlang_Audio.json"))
        let binding = try DuelErlangSourceAudio.load(directory: directory,
            manifestName: "SF3_Erlang_Audio.json", expectedSHA256: args[2],
            profileName: "SF3_Erlang_Profile.json", profileSHA256: args[3], profile: profile)
        require(binding.markers.count == 119 && binding.verifiedFiles.count == 83 &&
                binding.pendingModelMarkerCount == 0 && binding.hasMeditationTrigger && profile.clips.count == 62,
                "actual schema-4 closure differs")
        let floor = binding.markers.filter { $0.route == "Floor.Stone" }
        require(floor.count == 21 && floor.allSatisfy { $0.modelRole == nil }, "actor-only Floor scope differs")
        let step = floor.first { $0.role == "walkForward" }!
        require(step.sourceFrame == 10 && step.sourceTick == 20 && step.duration == 40 &&
                step.files.count == 3 && step.files[1] == step.files[2] && step.files[0] != step.files[1],
                "native Frame origin or repeated source alternative changed")
        print("PASS actual 82 PCM / 119 markers and exact Stone source Frame / duplicate alternatives")

        let palace = binding.clocks(stageSHA256: DuelErlangSourceAudio.palaceStageSHA256)
        require(palace.count == 119 && binding.clocks.count == 98 &&
                binding.clocks(stageSHA256: String(repeating: "0", count: 64)).count == 98,
                "unknown stage admitted Palace Floor sounds")
        let sample = DuelSourceMotionSample(frame: 1, sequence: 0, owner: 0, clip: step.clip,
            previousTick: 19, tick: 20, duration: 40)
        var clock = DuelErlangAudioClock()
        require(clock.consume(markers: palace, samples: [sample], models: [], frame: 1,
                    fighting: true, paused: false, owners: [0]) == [step.category],
                "actual Palace crossing did not emit exactly one step cue")
        var unknown = DuelErlangAudioClock()
        require(unknown.consume(markers: binding.clocks, samples: [sample], models: [], frame: 1,
                    fighting: true, paused: false, owners: [0]).isEmpty &&
                unknown.consume(markers: palace, samples: [sample], models: [], frame: 1,
                    fighting: true, paused: false, owners: [0]).isEmpty,
                "unknown stage or late context replayed an already consumed Floor interval")
        print("PASS only the verified Palace selects Floor; late stage context cannot replay an interval")

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try profileData.write(to: temporary.appendingPathComponent("SF3_Erlang_Profile.json"))
        func rejected(_ mutate: (inout [String: Any]) -> Void) throws -> Bool {
            var document = try JSONSerialization.jsonObject(with: manifest) as! [String: Any]
            mutate(&document)
            let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
            try data.write(to: temporary.appendingPathComponent("SF3_Erlang_Audio.json"))
            do {
                _ = try DuelErlangSourceAudio.load(directory: temporary,
                    manifestName: "SF3_Erlang_Audio.json", expectedSHA256: DuelNetworkContentRecord.digest(data),
                    profileName: "SF3_Erlang_Profile.json", profileSHA256: args[3], profile: profile)
            } catch DuelErlangSourceAudio.Failure.manifest { return true
            } catch DuelErlangSourceAudio.Failure.marker { return true }
            return false
        }
        require(try rejected { document in
            var context = document["context"] as! [String: Any]
            context["floor"] = "Metal"; document["context"] = context
        }, "a different original floor type was admitted under the Palace binding")
        print("PASS wrong source floor rejected before any PCM access")
        require(try rejected { document in
            var markers = document["markers"] as! [[String: Any]]
            let index = markers.firstIndex { ($0["route"] as? String) == "Floor.Stone" }!
            markers[index]["sourceFrame"] = 9; document["markers"] = markers
        }, "animation's minus-one convention was admitted as a sound Frame")
        print("PASS subtracting one from the original sound Frame rejected before PCM access")
        print("4 new Floor loader/clock checks passed; no playback or native execution")
    }
}
