import Foundation
import ShiftCore

/// Only the new schema-3 source trigger and final actor identity are exercised.
@main
struct ErlangMeditationAudioLoaderChecks {
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
        require(binding.hasMeditationTrigger && binding.markers.count == 98 && binding.verifiedFiles.count == 76 &&
                binding.pendingModelMarkerCount == 0 && profile.clips.count == 62,
                "final actor and source event audio closure differs")
        let first = binding.meditationCategory(owner: 0)!, second = binding.meditationCategory(owner: 1)!
        require(first != second && binding.audio[first] == binding.audio[second] &&
                binding.audio[first]?.first?.count == 882_044 && binding.meditationCategory(owner: 2) == nil,
                "exact ten-second original PCM or per-owner categories differ")
        print("PASS final 62-clip actor with 75 original PCM, 98 markers and one owner-bound source trigger")

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try profileData.write(to: temporary.appendingPathComponent("SF3_Erlang_Profile.json"))
        func rejected(_ key: String, _ value: Any) throws -> Bool {
            var document = try JSONSerialization.jsonObject(with: manifest) as! [String: Any]
            var triggers = document["triggerSounds"] as! [[String: Any]]
            triggers[0][key] = value; document["triggerSounds"] = triggers
            let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
            try data.write(to: temporary.appendingPathComponent("SF3_Erlang_Audio.json"))
            do {
                _ = try DuelErlangSourceAudio.load(directory: temporary,
                    manifestName: "SF3_Erlang_Audio.json", expectedSHA256: DuelNetworkContentRecord.digest(data),
                    profileName: "SF3_Erlang_Profile.json", profileSHA256: args[3], profile: profile)
            } catch DuelErlangSourceAudio.Failure.manifest { return true }
            return false
        }
        require(try rejected("loop", true), "one-shot original PlaySound was admitted as a loop")
        print("PASS invented looping rejected before any PCM access")
        require(try rejected("stopTrigger", 13), "start trigger was admitted as the conditional stop")
        print("PASS wrong original StopSound trigger rejected before any PCM access")
        print("3 new schema-3 binding checks passed; no playback or native execution")
    }
}
