import Foundation

/// Original D13 PCM routes and clocks. Byte authentication is the native
/// loader's responsibility; a manifest cannot authorize its own contents.
public struct DuelSerpentSourceAudioManifest: Codable, Sendable {
    public struct PCM: Codable, Sendable {
        public let name, sha256, pcmSHA256: String
        public let bytes, sampleRate, channels, sampleFrames, sampleWidth: Int
        public let sourcePath, sourceName, sourceBundle, sourceBundleSHA256: String
    }
    public struct Sound: Codable, Sendable {
        public let identifier, file: String
        public let loop: Bool
    }
    public struct Marker: Codable, Hashable, Sendable {
        public let action, alias, clip, sourceMotionSHA256: String
        public let tick: Int
        public let identifier: String
    }
    public struct Trigger: Codable, Hashable, Sendable {
        public let lock, sourceSet, trigger: Int
        public let identifier: String
        public let stop, loop: Bool
    }
    public struct Unbound: Codable, Sendable {
        public let file, reason: String
    }
    public let schema, profileID, characterSHA256: String
    public let sourceProfileSHA256, sourceNamedSHA256, sourceReceiptSHA256, sourceCatalogSHA256: String
    public let sourceAudioVersion: String
    public let dedicatedSourceClips, sharedSourceClips: Int
    public let files: [PCM]
    public let sounds: [Sound]
    public let bodyMarkers: [Marker]
    public let triggerSources: [Trigger]
    public let unbound: [Unbound]
    public enum Failure: Error, Equatable { case identity, manifest, marker, pcm }

    public func validate(profile: DuelWeaponProfile) throws {
        let actions = try DuelSerpentActionBinding(profile: profile)
        guard schema == "d13-ordinary-source-audio-v1", profileID == profile.id,
              characterSHA256 == profile.sha256,
              sourceProfileSHA256 == "05f5e49993120467a1c2cd5fdcbce3dba0dd3e8a5223b455f50adcfcd5441818",
              sourceNamedSHA256 == "612b85ed595e4a29ab686c00370d0c4bd573d6aaaa62384c769a4abb1f2cf09a",
              sourceReceiptSHA256 == "d169d518d0133ee6180c81d11edd5b5c11816e91886b7aae2eed54806f775d37",
              sourceCatalogSHA256 == "2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055",
              sourceAudioVersion == "Android Xiaomi 1.45.3" else { throw Failure.identity }
        guard dedicatedSourceClips == 13, sharedSourceClips == 1, files.count == 14,
              Set(files.map(\.name)).count == files.count,
              Set(files.map(\.sourcePath)).count == files.count,
              sounds.count == DuelSerpentAudioTimeline.sounds.count,
              Set(sounds.map(\.identifier)) == Set(DuelSerpentAudioTimeline.sounds.keys),
              Set(sounds.map(\.file)).count == sounds.count,
              unbound.count == files.count - sounds.count,
              Set(unbound.map(\.file)).count == unbound.count else { throw Failure.manifest }
        let prefix = "assets/gamedata/resources/audio/sounds/"
        for file in files {
            try DuelFighterAssetRelease.File(name: file.name, bytes: file.bytes,
                                             sha256: file.sha256).validate(maximum: 4_000_000)
            guard file.name.hasPrefix("SF3Serpent_"), file.name.hasSuffix(".wav"),
                  DuelFighterAssetRelease.validDigest(file.pcmSHA256),
                  DuelFighterAssetRelease.validDigest(file.sourceBundleSHA256),
                  DuelFighterAssetRelease.File.validName(file.sourceBundle),
                  file.sampleWidth == 2, [1, 2].contains(file.channels),
                  (8_000...192_000).contains(file.sampleRate),
                  (1...30 * file.sampleRate).contains(file.sampleFrames),
                  file.sourcePath.hasPrefix(prefix), !file.sourcePath.contains(".."),
                  file.sourcePath.hasSuffix(".wav") else { throw Failure.manifest }
        }
        guard files.reduce(0, { $0 + $1.bytes }) <= 4_000_000 else { throw Failure.manifest }
        let byName = Dictionary(uniqueKeysWithValues: files.map { ($0.name, $0) })
        for sound in sounds {
            guard DuelSerpentAudioTimeline.sounds[sound.identifier] == sound.loop,
                  let file = byName[sound.file],
                  sound.identifier.hasSuffix("@Battle@Movement"),
                  file.sourcePath == prefix + sound.identifier.components(separatedBy: "@")[0] + ".wav"
            else { throw Failure.manifest }
        }
        let bound = Set(sounds.map(\.file)), deferred = Set(unbound.map(\.file))
        guard bound.isDisjoint(with: deferred), bound.union(deferred) == Set(byName.keys),
              unbound.allSatisfy({ $0.reason == "outside-ordinary-poison-and-bottle-path" })
        else { throw Failure.manifest }
        let expected: [(DuelSerpentActionBinding.Action, Int, String)] = [
            (.poison, 20, "set_d13/poison_energy_cast@Battle@Movement"),
            (.poison, 36, "shadow_moves/mind_throw/mind_throw_whoosh_1@Battle@Movement"),
            (.poison, 180, "shadow_moves/mind_throw/mind_throw_whoosh_1@Battle@Movement"),
            (.bottle, 46, "set_d13/poison_rain_bottle@Battle@Movement")
        ]
        let markers = expected.map { action, tick, identifier -> Marker in
            let motion = actions.motion(action)
            return .init(action: action.rawValue, alias: motion.alias, clip: motion.clipName,
                         sourceMotionSHA256: motion.clipSHA256, tick: tick, identifier: identifier)
        }
        guard bodyMarkers.count == markers.count, Set(bodyMarkers) == Set(markers)
        else { throw Failure.marker }
        let rain = DuelSerpentRainRuntime.rainSound, outro = DuelSerpentRainRuntime.rainOutSound
        let expectedTriggers: [Trigger] = [
            .init(lock: 1379, sourceSet: 0, trigger: 7, identifier: "set_d13/poison_energy_hit_hiss@Battle@Movement", stop: false, loop: false),
            .init(lock: 1403, sourceSet: 0, trigger: 1, identifier: rain, stop: false, loop: true),
            .init(lock: 1403, sourceSet: 0, trigger: 3, identifier: rain, stop: false, loop: true),
            .init(lock: 1403, sourceSet: 0, trigger: 10, identifier: rain, stop: true, loop: false),
            .init(lock: 1403, sourceSet: 0, trigger: 10, identifier: outro, stop: false, loop: false),
            .init(lock: 1403, sourceSet: 0, trigger: 16, identifier: rain, stop: true, loop: false),
            .init(lock: 1403, sourceSet: 0, trigger: 16, identifier: outro, stop: false, loop: false)
        ]
        guard triggerSources.count == expectedTriggers.count,
              Set(triggerSources) == Set(expectedTriggers) else { throw Failure.marker }
    }

    /// Strict RIFF parsing before native playback. The returned sample bytes
    /// must also match pcmSHA256; their container must match the pinned file.
    public static func pcmPayload(_ input: Data, file: PCM) throws -> Data {
        let data = Data(input)
        func word(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        func long(_ offset: Int) -> Int { word(offset) | word(offset + 2) << 16 }
        guard data.count >= 44, data.count == file.bytes,
              data.prefix(4) == Data("RIFF".utf8), data[8..<12] == Data("WAVE".utf8),
              long(4) == data.count - 8, file.sampleWidth == 2,
              [1, 2].contains(file.channels), (8_000...192_000).contains(file.sampleRate),
              (1...30 * file.sampleRate).contains(file.sampleFrames) else { throw Failure.pcm }
        var index = 12, chunks = 0, format = false, pcm: Data?
        while index < data.count {
            guard index <= data.count - 8, chunks < 32 else { throw Failure.pcm }
            let size = long(index + 4), start = index + 8
            guard size <= data.count - start else { throw Failure.pcm }
            switch data[index..<index + 4] {
            case Data("fmt ".utf8):
                guard !format, (16...40).contains(size), word(start) == 1,
                      word(start + 2) == file.channels, long(start + 4) == file.sampleRate,
                      long(start + 8) == file.sampleRate * file.channels * 2,
                      word(start + 12) == file.channels * 2, word(start + 14) == 16 else { throw Failure.pcm }
                format = true
            case Data("data".utf8):
                guard pcm == nil, size == file.sampleFrames * file.channels * 2 else { throw Failure.pcm }
                pcm = Data(data[start..<start + size])
            default: break
            }
            index = start + size + size % 2; chunks += 1
        }
        guard index == data.count, format, let pcm else { throw Failure.pcm }
        return pcm
    }
}
