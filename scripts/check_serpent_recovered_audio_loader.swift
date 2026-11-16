import Foundation
@testable import ShiftCore

/// Actual 75-file D13 input through the App loader and existing Core clocks.
/// Linux uses only a SHA-256 compatibility adapter; this performs no playback.
@main
struct SerpentRecoveredAudioLoaderChecks {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    @MainActor
    static func main() throws {
        let args = CommandLine.arguments
        require(args.count == 3, "expected audio directory and the separate authenticated match profile")
        let directory = URL(fileURLWithPath: args[1], isDirectory: true)
        let profileData = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        require(DuelNetworkContentRecord.digest(profileData) ==
                "ca44aec355d6c70487df550a818112172a897bc64a0bbaa143748045a8284e53",
                "expected the unchanged 66-clip D13 match body with the final receipt boundary")
        let profile = try JSONDecoder().decode(DuelWeaponProfile.self, from: profileData)
        let binding = try DuelSerpentSourceAudio.load(directory: directory, profile: profile)
        let bodyData = try Data(contentsOf: directory.appendingPathComponent(DuelSerpentSourceAudio.bodyManifestName))
        let body = try JSONDecoder().decode(DuelSerpentBodyAudioManifest.self, from: bodyData)
        require(profile.clips.count == 66 && binding.profileID == "liu_serpent" &&
                binding.verifiedFiles.count == 77 && Set(binding.verifiedFiles.map(\.path)).count == 77 &&
                binding.verifiedFiles.filter { $0.path.hasSuffix(".wav") }.count == 75 &&
                binding.bodyMarkers.count == 135 && binding.audio.count == 282 &&
                binding.loopCategories.count == 2,
                "actual 75-PCM plus two-manifest closure differs")
        require(binding.verifiedFiles.filter { $0.path.hasSuffix(".wav") }.reduce(0) { $0 + $1.bytes } == 4_889_902,
                "actual original PCM byte closure differs")
        print("PASS actual App loader: 75 original WAV, two pinned manifests, 135 body markers, 66 body clips")

        let repeated = body.markers.first { $0.clip == "m_step_back" && $0.route == "Floor.Stone" }!
        require(repeated.rawFrame == 9 && repeated.tick == 18 && repeated.playbackTicks == 40 &&
                repeated.choices.count == 3 && repeated.choices[1] == repeated.choices[2] &&
                repeated.choices[0] != repeated.choices[1],
                "original Frame origin or the V1,V2,V2 candidate list changed")
        let verifiedPCM = try Dictionary(uniqueKeysWithValues: body.files.map {
            ($0.name, try Data(contentsOf: directory.appendingPathComponent($0.name)))
        })
        for marker in body.markers {
            let categories = (0..<2).map { binding.bodyCategory(markerID: marker.id, owner: $0)! }
            require(categories[0] != categories[1], "opponent body categories share a player identity")
            for category in categories {
                let audio = binding.audio[category]!
                require(audio.count == marker.choices.count, "source ordered candidate count differs")
                for (data, choice) in zip(audio, marker.choices) {
                    require(data == verifiedPCM[choice.file], "ordered original PCM candidate was substituted")
                }
            }
        }
        let weighted = binding.audio[binding.bodyCategory(markerID: repeated.id, owner: 0)!]!
        require(weighted[1] == weighted[2] && weighted[0] != weighted[1], "duplicate source weight was deduplicated")
        require(binding.audio.filter { $0.key.hasPrefix("serpentBody:") }.reduce(0) { $0 + $1.value.count } == 1278,
                "two-owner ordered candidate multiplicity differs")
        print("PASS all 639 ordered body choices per owner; V1,V2,V2 weighting and separate owner categories")

        let clips = Array(Set(binding.bodyMarkers.map(\.clip))).sorted()
        var samples: [DuelSourceMotionSample] = []
        for owner in 0..<2 {
            for (index, clip) in clips.enumerated() {
                let duration = binding.bodyMarkers.first { $0.clip == clip }!.duration
                samples.append(.init(frame: 11, sequence: owner * clips.count + index,
                    owner: owner, clip: clip, previousTick: -1, tick: duration, duration: duration))
            }
        }
        require(samples.count <= 256, "actual source sample scope exceeds clock bound")
        var clock = DuelSerpentBodyAudioClock()
        let palace = DuelSerpentBodyAudioClock.palaceStageSHA256
        require(clock.consume(markers: binding.bodyMarkers, samples: samples, frame: 11,
                paused: true, owners: [0, 1], stageSHA256: palace).isEmpty,
                "paused body clocks emitted or consumed a source event")
        let cues = clock.consume(markers: binding.bodyMarkers, samples: samples, frame: 11,
                                paused: false, owners: [0, 1], stageSHA256: palace)
        require(cues.count == 270 && (0..<2).allSatisfy { owner in
            let actual = cues.filter { $0.owner == owner }.map(\.markerID)
            return actual.count == 135 && Set(actual) == Set(binding.bodyMarkers.map(\.id))
        }, "not all 135 actual source clocks fired once for each owner")
        require(clock.consume(markers: binding.bodyMarkers, samples: samples, frame: 11,
                paused: false, owners: [0, 1], stageSHA256: palace).isEmpty &&
                clock.consume(markers: binding.bodyMarkers, samples: samples, frame: 10,
                paused: false, owners: [0, 1], stageSHA256: palace).isEmpty,
                "duplicate or rewound presentation replayed a source interval")
        print("PASS 135 real source clocks per owner; pause, duplicate samples and rewound frames do not replay")

        var noStage = DuelSerpentBodyAudioClock()
        let withoutFloor = noStage.consume(markers: binding.bodyMarkers, samples: samples, frame: 11,
            paused: false, owners: [0, 1], stageSHA256: nil)
        require(withoutFloor.count == 256 && noStage.consume(markers: binding.bodyMarkers,
            samples: samples, frame: 11, paused: false, owners: [0, 1], stageSHA256: palace).isEmpty,
            "unknown or late stage context admitted/replayed Floor.Stone")
        let stepSample = DuelSourceMotionSample(frame: 12, sequence: 0, owner: 0,
            clip: repeated.clip, previousTick: 17, tick: 18, duration: 40)
        var exactFloor = DuelSerpentBodyAudioClock()
        require(exactFloor.consume(markers: binding.bodyMarkers, samples: [stepSample], frame: 12,
            paused: false, owners: [0], stageSHA256: palace) == [.init(owner: 0, markerID: repeated.id)],
            "verified Palace step did not retain its actual 9 -> 18 sound Frame")
        var wrongStage = DuelSerpentBodyAudioClock()
        require(wrongStage.consume(markers: binding.bodyMarkers, samples: [stepSample], frame: 12,
            paused: false, owners: [0], stageSHA256: String(repeating: "0", count: 64)).isEmpty,
            "a different stage authorized the original Palace floor route")
        print("PASS exactly seven Floor.Stone markers per owner require Palace SHA; late context cannot replay")

        require(body.excludedExistingBodyMarkers.count == 4, "dedicated body exclusion scope differs")
        for marker in body.excludedExistingBodyMarkers {
            for owner in 0..<2 {
                require(binding.bodyCategory(markerID: marker.id, owner: owner) == nil &&
                        binding.category(identifier: marker.choices[0].identifier, owner: owner) != nil,
                        "a dedicated poison/bottle marker entered both audio timelines")
            }
        }
        require(binding.bodyCategory(markerID: repeated.id, owner: -1) == nil &&
                binding.bodyCategory(markerID: repeated.id, owner: 2) == nil &&
                binding.bodyCategory(markerID: "unknown", owner: 0) == nil,
                "unbound owner or body marker received a category")
        print("PASS four existing poison/bottle events are excluded only from the supplemental timeline")

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for file in binding.verifiedFiles {
            try FileManager.default.copyItem(at: directory.appendingPathComponent(file.path),
                                            to: temporary.appendingPathComponent(file.path))
        }
        func rejected(_ name: String) throws -> Bool {
            do {
                _ = try DuelSerpentSourceAudio.load(directory: temporary, profile: profile)
            } catch DuelFighterAssetReleaseLoader.Failure.integrity(let file) {
                return file == name
            }
            return false
        }
        var changedManifest = bodyData
        changedManifest[changedManifest.startIndex] ^= 1
        let temporaryManifest = temporary.appendingPathComponent(DuelSerpentSourceAudio.bodyManifestName)
        try changedManifest.write(to: temporaryManifest)
        require(try rejected(DuelSerpentSourceAudio.bodyManifestName), "modified body manifest authorized itself")
        try bodyData.write(to: temporaryManifest)
        print("PASS the fixed outer supplemental SHA rejects a changed manifest")

        let newFile = body.files.first { $0.name.hasPrefix("SF3SerpentBody_") }!
        let newURL = temporary.appendingPathComponent(newFile.name)
        var changedPCM = try Data(contentsOf: newURL)
        changedPCM[changedPCM.index(before: changedPCM.endIndex)] ^= 1
        try changedPCM.write(to: newURL)
        require(try rejected(newFile.name), "modified new PCM was admitted under its source receipt")
        print("PASS a changed original WAV sample is rejected before audio category construction")
        print("7 actual D13 loader/clock checks passed; Linux Core and App loading only, no Apple audio playback")
    }
}
