import Foundation

/// Authenticated source body markers supplement the separately bound poison
/// and bottle trigger path. Native loading must verify the manifest's byte pin.
public struct DuelSerpentBodyAudioManifest: Codable, Sendable {
    public struct Context: Codable, Sendable {
        public let gender, floor, stageName, stageSHA256, floorSourceSHA256: String
    }
    public struct Clip: Codable, Sendable {
        public let clip, animationAlias, sourceMotion, sourceMotionSHA256: String
        public let sourceEntry, sourceSHA256: String
        public let sourceRecordIndex, sourceFirstIndex, sourceFrameStride, sourceFrames: Int
        public let playbackTicks, sourceEndEventTick: Int
        public let looped: Bool
    }
    public struct Choice: Codable, Hashable, Sendable {
        public let identifier, sourcePath, file, bus, mixerGroup: String
    }
    public struct Marker: Codable, Sendable {
        public let id, clip, animationAlias, sourceMotion, sourceMotionSHA256: String
        public let sourceEntry, sourceSHA256, route: String
        public let sourceRecordIndex, markerIndex, rawFrame, sourceFrame: Int
        public let sourceFirstIndex, sourceFrameStride, tick, sourceFrames: Int
        public let playbackTicks, sourceEndEventTick: Int
        public let looped: Bool
        public let choices: [Choice]
        public let existingAction: String?
        public var clock: DuelSerpentBodyAudioClock.Marker {
            .init(id: id, clip: clip, tick: tick, duration: playbackTicks,
                  requiresPalaceStone: route == "Floor.Stone")
        }
    }
    public let schema, profileID, characterSHA256: String
    public let sourceMatchProfileSHA256, sourcePhysicalProfileSHA256, sourceNamedSHA256: String
    public let sourceReceiptSHA256, sourceCatalogSHA256: String
    public let sourceExistingAudioManifestSHA256, sourceReusedAudioManifestSHA256: String
    public let sourceConfigurationHashes: [String: String]
    public let context: Context
    public let files: [DuelSerpentSourceAudioManifest.PCM]
    public let clips: [Clip]
    public let markers, excludedExistingBodyMarkers: [Marker]
    public let allSourceMarkerCount: Int
    public enum Failure: Error, Equatable { case identity, manifest, clip, marker }

    public static let sourceConfigurations = [
        "settings_sets_dynasty.bytes": "3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701",
        "settings_style_shuangou.bytes": "3c85fc3257fe4f0f92045818ff64a202194e62f1e1f9a4b6ccaa9ac45e64a20f",
        "moves_settings.bytes": "fcdecefdc0ef9cb5bc0a079c6511ccf2a9a352bb29aae8b016113236beac9a6b",
        "settings_blocks.bytes": "ecad88aefa412f8972d508ee63ab916190065f8a0c9dcc8bb8a2c7d8f716b091",
        "settings_hits.bytes": "d6daca4777b04dcab96375ce6aa899ec75a6b0aa5784b0beddd53f843aa9226a",
        "settings_style_kicks.bytes": "15318c7a03085ea91c7010ab41a9407d820505666dea02880e1779f38bfa34cf",
        "settings_sets_heralds.bytes": "64bd77afa0edacdc7b672047222fb4261771f08b835367bc3aeeb5b02e668f5a"
    ]

    public func validate(profile: DuelWeaponProfile) throws {
        let actions = try DuelSerpentActionBinding(profile: profile)
        guard schema == "d13-body-source-audio-v1", profileID == profile.id, profile.isSerpent,
              characterSHA256 == profile.sha256,
              sourceMatchProfileSHA256 == "ca44aec355d6c70487df550a818112172a897bc64a0bbaa143748045a8284e53",
              sourcePhysicalProfileSHA256 == "05f5e49993120467a1c2cd5fdcbce3dba0dd3e8a5223b455f50adcfcd5441818",
              sourceNamedSHA256 == "612b85ed595e4a29ab686c00370d0c4bd573d6aaaa62384c769a4abb1f2cf09a",
              sourceReceiptSHA256 == "d169d518d0133ee6180c81d11edd5b5c11816e91886b7aae2eed54806f775d37",
              sourceCatalogSHA256 == "2c01276ca8c58ea32d79bfe481e37adc6696bc4c5a6140f6f6842ca262d07055",
              sourceExistingAudioManifestSHA256 == "1ecd028177667cb2412df83d3a65252c064b0b299ccb3e5cd3105d55cd70acee",
              sourceReusedAudioManifestSHA256 == "07d582bf8eb888424bb64939c2f469f4dc0e9536e6b58acc5c51fbaed307928e",
              sourceConfigurationHashes == Self.sourceConfigurations,
              context.gender == "Male", context.floor == "Stone",
              context.stageName == "SF3_Palace_Exterior.glb",
              context.stageSHA256 == DuelSerpentBodyAudioClock.palaceStageSHA256,
              context.floorSourceSHA256 == "aed69b0fe5f39de00bd3871a5361f4b8d887e9ba9753302546dcc0cb97e109c3"
        else { throw Failure.identity }
        guard files.count == 66, Set(files.map(\.name)).count == 66,
              Set(files.map(\.sourcePath)).count == 66,
              clips.count == 66, profile.clips.count == 66, Set(clips.map(\.clip)).count == 66,
              Set(clips.map(\.clip)) == Set(profile.clips.map(\.name)),
              markers.count == 135, excludedExistingBodyMarkers.count == 4, allSourceMarkerCount == 139,
              markers.filter({ $0.route == "Common" }).count == 92,
              markers.filter({ $0.route == "Male" }).count == 36,
              markers.filter({ $0.route == "Floor.Stone" }).count == 7,
              markers.reduce(0, { $0 + $1.choices.count }) == 639 else { throw Failure.manifest }
        let prefix = "assets/gamedata/resources/audio/sounds/"
        var total = 0
        for file in files {
            try DuelFighterAssetRelease.File(name: file.name, bytes: file.bytes,
                                             sha256: file.sha256).validate(maximum: 4_000_000)
            guard file.name.hasSuffix(".wav"), file.name.hasPrefix("SF3"),
                  DuelFighterAssetRelease.validDigest(file.pcmSHA256),
                  DuelFighterAssetRelease.validDigest(file.sourceBundleSHA256),
                  DuelFighterAssetRelease.File.validName(file.sourceBundle),
                  file.sampleWidth == 2, [1, 2].contains(file.channels),
                  (8_000...192_000).contains(file.sampleRate),
                  (1...30 * file.sampleRate).contains(file.sampleFrames),
                  file.sourcePath.hasPrefix(prefix), !file.sourcePath.contains(".."),
                  file.sourcePath.hasSuffix(".wav") else { throw Failure.manifest }
            total += file.bytes
            guard total <= 32_000_000 else { throw Failure.manifest }
        }
        for clip in clips {
            guard let motion = profile.clip(named: clip.clip), motion.sha256 == clip.sourceMotionSHA256,
                  motion.frames == clip.sourceFrames, motion.ticks == clip.playbackTicks,
                  motion.sourceEndEventTick == clip.sourceEndEventTick,
                  Self.sourceConfigurations[clip.sourceEntry] == clip.sourceSHA256,
                  (0..<10_000).contains(clip.sourceRecordIndex),
                  (2...36_001).contains(clip.sourceFrames), (1...9).contains(clip.sourceFrameStride),
                  (0...36_000).contains(clip.sourceFirstIndex),
                  clip.playbackTicks == (clip.sourceFrames - 1) * clip.sourceFrameStride,
                  (1...36_000).contains(clip.playbackTicks),
                  (0...clip.playbackTicks).contains(clip.sourceEndEventTick),
                  clip.sourceMotion.hasSuffix(".bin"), !clip.sourceMotion.contains(".."),
                  clip.animationAlias.range(of: "^[A-Za-z0-9_]{1,128}$", options: .regularExpression) != nil
            else { throw Failure.clip }
        }
        let byName = Dictionary(uniqueKeysWithValues: files.map { ($0.name, $0) })
        let byClip = Dictionary(uniqueKeysWithValues: clips.map { ($0.clip, $0) })
        let allMarkers = markers + excludedExistingBodyMarkers
        guard Set(allMarkers.map(\.id)).count == 139,
              Set(allMarkers.flatMap { $0.choices.map(\.file) }) == Set(byName.keys),
              markers.allSatisfy({ $0.existingAction == nil }) else { throw Failure.marker }
        for marker in allMarkers {
            guard let clip = byClip[marker.clip], marker.animationAlias == clip.animationAlias,
                  marker.sourceMotion == clip.sourceMotion, marker.sourceMotionSHA256 == clip.sourceMotionSHA256,
                  marker.sourceEntry == clip.sourceEntry, marker.sourceSHA256 == clip.sourceSHA256,
                  marker.sourceRecordIndex == clip.sourceRecordIndex,
                  marker.sourceFirstIndex == clip.sourceFirstIndex,
                  marker.sourceFrameStride == clip.sourceFrameStride, marker.sourceFrames == clip.sourceFrames,
                  marker.playbackTicks == clip.playbackTicks, marker.sourceEndEventTick == clip.sourceEndEventTick,
                  marker.looped == clip.looped, ["Common", "Male", "Floor.Stone"].contains(marker.route),
                  marker.id.range(of: "^[A-Za-z0-9_-]{1,160}$", options: .regularExpression) != nil,
                  (0..<256).contains(marker.markerIndex), (-1...36_000).contains(marker.rawFrame),
                  marker.sourceFrame == max(0, marker.rawFrame),
                  marker.sourceFrame >= marker.sourceFirstIndex,
                  marker.sourceFrame - marker.sourceFirstIndex < marker.sourceFrames,
                  marker.tick == (marker.sourceFrame - marker.sourceFirstIndex) * marker.sourceFrameStride,
                  (1...32).contains(marker.choices.count) else { throw Failure.marker }
            for choice in marker.choices {
                let parts = choice.identifier.components(separatedBy: "@")
                guard let file = byName[choice.file], parts.count == 3,
                      choice.sourcePath == file.sourcePath, choice.sourcePath == prefix + parts[0].lowercased() + ".wav",
                      choice.bus == parts[1], choice.mixerGroup == parts[2] else { throw Failure.marker }
            }
        }
        let poison = actions.motion(.poison), bottle = actions.motion(.bottle)
        let expected = [
            "poison|\(poison.clipName)|20|set_d13/poison_energy_cast@Battle@Movement",
            "poison|\(poison.clipName)|36|shadow_moves/mind_throw/mind_throw_whoosh_1@Battle@Movement",
            "poison|\(poison.clipName)|180|shadow_moves/mind_throw/mind_throw_whoosh_1@Battle@Movement",
            "bottle|\(bottle.clipName)|46|set_d13/poison_rain_bottle@Battle@Movement"
        ]
        let excluded = excludedExistingBodyMarkers.map {
            "\($0.existingAction ?? "")|\($0.clip)|\($0.tick)|\($0.choices.first?.identifier ?? "")"
        }
        guard Set(excluded) == Set(expected), excludedExistingBodyMarkers.allSatisfy({
            $0.route == "Common" && $0.choices.count == 1
        }) else { throw Failure.marker }
    }
}
