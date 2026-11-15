import Foundation
import ShiftCore

/// Run against an existing private candidate and an already built ShiftCore.
/// The production loader/clock bodies are compiled unchanged. On Linux only
/// the existing content-record SHA implementation needs the system adapter;
/// this is not an Apple audio-player or CryptoKit acceptance test.
@main
struct ErlangSourceAudioLoaderChecks {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        precondition(args.count == 4)
        let directory = URL(fileURLWithPath: args[1], isDirectory: true)
        let profileData = try Data(contentsOf: directory.appendingPathComponent("SF3_Erlang_Profile.json"))
        let profile = try JSONDecoder().decode(DuelWeaponProfile.self, from: profileData)
        func load(_ value: DuelWeaponProfile = profile, manifestSHA: String? = nil) throws -> DuelErlangSourceAudio {
            try .load(directory: directory, manifestName: "SF3_Erlang_Audio.json",
                expectedSHA256: manifestSHA ?? args[2], profileName: "SF3_Erlang_Profile.json",
                profileSHA256: args[3], profile: value)
        }
        let binding = try load()
        precondition(binding.verifiedFiles.count == 29 && !binding.audio.isEmpty)
        precondition(binding.audio.count == binding.markers.count)
        precondition(binding.markers.count + binding.pendingModelMarkerCount == 29)
        precondition(binding.markers.first(where: { $0.modelRole == "erlangSummon_hound" })?.sourceTick == 2)
        precondition(binding.markers.first(where: { $0.role == "erlangEarthshaker" })?.duration == 110)
        print("PASS exact profile, 28 original PCM formats/hashes, actor/model clocks and pending scope")
        do {
            _ = try load(manifestSHA: String(repeating: "0", count: 64))
            fatalError("changed manifest pin was accepted")
        } catch { print("PASS changed runtime manifest identity rejected") }
        var object = try JSONSerialization.jsonObject(with: profileData) as! [String: Any]
        object["sha256"] = String(repeating: "0", count: 64)
        let changed = try JSONDecoder().decode(DuelWeaponProfile.self,
            from: JSONSerialization.data(withJSONObject: object))
        do {
            _ = try load(changed)
            fatalError("another in-memory character profile was accepted")
        } catch { print("PASS in-memory profile substitution rejected") }
        print("3 new production-loader checks passed; AVAudioPlayer/CryptoKit not executed")
    }
}
