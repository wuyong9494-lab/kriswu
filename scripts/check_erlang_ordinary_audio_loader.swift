import Foundation
import ShiftCore

/// New schema-2 checks only. Pass the real bound directory, manifest digest
/// and matching profile digest. Playback is never invoked.
@main
struct ErlangOrdinaryAudioLoaderChecks {
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
        require(binding.markers.count == 98 && binding.verifiedFiles.count == 76 &&
                binding.pendingModelMarkerCount == 0, "complete original audio inventory differs")
        require(binding.markers.filter { $0.id.hasPrefix("ordinary_") }.count == 69,
                "ordinary/shared source groups are missing")
        require(binding.markers.filter { $0.modelRole != nil }.count == 11, "D15 model cues changed")
        print("PASS production loader authenticates 75 actual PCM files and all 98 source markers")

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try profileData.write(to: temporary.appendingPathComponent("SF3_Erlang_Profile.json"))
        // These malformed bindings must be rejected before opening any PCM.
        // No duplicate source-file copy or original decoding is needed.
        func rejected(_ mutate: (inout [[String: Any]]) -> Void) throws -> Bool {
            var document = try JSONSerialization.jsonObject(with: manifest) as! [String: Any]
            var markers = document["markers"] as! [[String: Any]]
            mutate(&markers); document["markers"] = markers
            let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
            try data.write(to: temporary.appendingPathComponent("SF3_Erlang_Audio.json"))
            do {
                _ = try DuelErlangSourceAudio.load(directory: temporary,
                    manifestName: "SF3_Erlang_Audio.json", expectedSHA256: DuelNetworkContentRecord.digest(data),
                    profileName: "SF3_Erlang_Profile.json", profileSHA256: args[3], profile: profile)
            } catch DuelErlangSourceAudio.Failure.marker { return true }
            return false
        }
        require(try rejected { markers in
            let index = markers.firstIndex { ($0["sourceEntry"] as? String) == "settings_style_imperial_spear.bytes" }!
            markers[index]["sourceConfigurationSHA256"] = DuelErlangSourceAudio.sourceConfigurationSHA256
        }, "Imperial marker accepted the unrelated D15 configuration digest")
        print("PASS wrong source-configuration identity rejected before PCM access")
        require(try rejected { markers in
            let index = markers.firstIndex { ($0["role"] as? String) == "imperialHeavyPassiveMirrored" }!
            markers[index]["clip"] = "imperial_spear_heavy_slash_passive"
        }, "mirrored source role accepted the unmirrored same-motion bytes")
        print("PASS mirrored ordinary audio cannot attach to the unmirrored animation clip")
        print("3 affected ordinary-source loader checks passed; no playback or native execution")
    }
}
