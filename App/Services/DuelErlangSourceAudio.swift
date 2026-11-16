import Foundation

/// Pinned D15, ordinary Common/Male and Palace Floor.Stone Sounds markers. Independently triggered or currently
/// unreferenced source files stay unplayed until their real event is bound.
@MainActor
struct DuelErlangSourceAudio {
    enum Failure: Error { case identity, manifest, file(String), marker(String) }
    struct PCM: Decodable {
        let name: String
        let bytes: Int
        let sha256: String
        let sampleRate: Int
        let channels: Int
        let sampleFrames: Int
        let sampleWidth: Int
        let pcmSHA256: String
        var file: DuelFighterAssetRelease.File { .init(name: name, bytes: bytes, sha256: sha256) }
    }
    struct Marker: Decodable {
        let id: String
        let animationAlias: String
        let role: String
        let modelRole: String?
        let clip: String
        let sourceMotionSHA256: String
        let sourceEntry: String?
        let sourceConfigurationSHA256: String?
        let sourceRecordIndex: Int
        let route: String
        let sourceFrame: Int
        let sourceFirstIndex: Int
        let sourceFrameStride: Int
        let sourceFrames: Int
        let sourceTick: Int
        let duration: Int
        let files: [String]
        var category: String { "erlangMarker:" + id }
        var clock: DuelErlangAudioClock.Marker {
            .init(category: category, clip: clip, modelRole: modelRole, sourceTick: sourceTick, duration: duration)
        }
    }
    private struct Deferred: Decodable { let sourceName: String; let file: String; let reason: String }
    private struct Trigger: Decodable {
        let id: String
        let file: String
        let loop: Bool
        let sourceIdentifier: String
        let sourceLock: Int
        let sourceLockSHA256: String
        let startTrigger: Int
        let stopTrigger: Int
        let startEvent: String
        let stopEvent: String
    }
    private struct PendingModel: Decodable { let id: String; let animationAlias: String; let files: [String]; let reason: String }
    private struct Context: Decodable {
        let gender: String
        let floor: String?
        let stageName: String?
        let stageSHA256: String?
        let floorSourceSHA256: String?
    }
    private struct Document: Decodable {
        let schemaVersion: Int
        let profileID: String
        let profileSHA256: String
        let characterSHA256: String
        let sourceConfigurationSHA256: String
        let sourceAudioManifestSHA256: String
        let sourceRecoveredProfileSHA256: String?
        let sourceOrdinaryAudioManifestSHA256: String?
        let sourceConfigurationHashes: [String: String]?
        let sourceTriggerManifestSHA256: String?
        let sourceFloorAudioManifestSHA256: String?
        let context: Context?
        let files: [PCM]
        let markers: [Marker]
        let deferredTriggers: [Deferred]
        let pendingModels: [PendingModel]
        let triggerSounds: [Trigger]?
    }
    static let sourceConfigurationSHA256 = "3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701"
    static let sourceAudioManifestSHA256 = "01649a542d8a20cbe66e9e1bee831201c3c70cdd4200c6f0b1b23c66e88aa9fd"
    static let sourceOrdinaryAudioManifestSHA256 = "7296d0f5152bf07b34c532f621b5ffc3b91e92e00ab69f898325c9a7b6a41ea3"
    static let sourceTriggerManifestSHA256 = "77cdd96fb7649acb2d9f1e93d68155f1df7fab5a99dc94e3199c058c2fce21b1"
    static let sourceFloorAudioManifestSHA256 = "8e43cbe4b0f4d63cedb64f9b8f386dd992f12e3922daef4e9219bd9e1849a41d"
    static let sourceFloorManifestSHA256 = "aed69b0fe5f39de00bd3871a5361f4b8d887e9ba9753302546dcc0cb97e109c3"
    // A newly recovered input, independently compared with all 82 historical
    // PCM hashes and 119 source clock records. The lost historical manifests
    // are not presented as reconstructed bytes. Schemas 1...4 retain their pins.
    static let recoveredSourceAudioManifestSHA256 = "07d582bf8eb888424bb64939c2f469f4dc0e9536e6b58acc5c51fbaed307928e"
    static let recoveredSourceProfileSHA256 = "bb058e221c6402c3c1562e0c18c2f24970682d73b8052ef372e09c194c7604ff"
    static let palaceStageSHA256 = "185aff02bbfb932e6cbf77daf9dba34d02adf6cec4ff78ee595414cef1f169d8"
    private static let sourceConfigurations = [
        "settings_sets_dynasty.bytes": sourceConfigurationSHA256,
        "settings_style_imperial_spear.bytes": "fb54e61b150349f0a02735ee8354ed6fe21a4263862dd6162e0123583705e8b0",
        "settings_blocks.bytes": "ecad88aefa412f8972d508ee63ab916190065f8a0c9dcc8bb8a2c7d8f716b091",
        "moves_settings.bytes": "fcdecefdc0ef9cb5bc0a079c6511ccf2a9a352bb29aae8b016113236beac9a6b",
        "settings_hits.bytes": "d6daca4777b04dcab96375ce6aa899ec75a6b0aa5784b0beddd53f843aa9226a",
        "settings_style_kicks.bytes": "15318c7a03085ea91c7010ab41a9407d820505666dea02880e1779f38bfa34cf"
    ]
    private static let modelRoles = [
        "D15_Ability_Dog_Attack_Model": "erlangSummon_hound",
        "D15_Meditation_Explosion_Model_Attack_Damage": "erlangSummon_meditation",
        "D15_Hovering_Sword_Model_Attack": "erlangSummon_sword",
        "D15_Avatara_Axe_Ground_Model_Attack": "erlangSummon_aftershock"
    ].merging(Dictionary(uniqueKeysWithValues: (1...6).map {
        ("D15_Hovering_Sword_Model_Birth_\($0)", "erlangSummon_swordBirth\($0)")
    })) { first, _ in first }
    private static let unplayedReasons = [
        "d15_meditation": "awaiting-exact-source-trigger",
        "d15_swords_explosion": "no-active-reference-in-reviewed-source-scope"
    ]
    let profileID: String
    let characterSHA256: String
    let verifiedFiles: [DuelNetworkContentRecord]
    let audio: [String: [Data]]
    let markers: [Marker]
    let pendingModelMarkerCount: Int
    let hasMeditationTrigger: Bool
    var clocks: [DuelErlangAudioClock.Marker] { clocks(stageSHA256: nil) }
    func clocks(stageSHA256: String?) -> [DuelErlangAudioClock.Marker] {
        // The caller supplies a digest only after the actual stage loader has
        // verified those bytes. Unknown/autumn stages cannot borrow Stone.
        markers.filter { $0.route != "Floor.Stone" || stageSHA256 == Self.palaceStageSHA256 }.map(\.clock)
    }
    func meditationCategory(owner: Int) -> String? {
        guard hasMeditationTrigger, (0..<2).contains(owner) else { return nil }
        return "erlangTrigger:d15_meditation:\(owner)"
    }

    static func load(directory: URL, manifestName: String, expectedSHA256: String,
                     profileName: String, profileSHA256: String, profile: DuelWeaponProfile) throws -> Self {
        func read(_ file: DuelFighterAssetRelease.File, maximum: Int) throws -> Data {
            try file.validate(maximum: maximum)
            let url = directory.appendingPathComponent(file.name)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == file.bytes else {
                throw Failure.file(file.name)
            }
            let data = try Data(contentsOf: url)
            guard data.count == file.bytes, DuelNetworkContentRecord.digest(data) == file.sha256 else { throw Failure.file(file.name) }
            return data
        }
        func metadata(_ name: String, digest: String, maximum: Int) throws -> Data {
            guard DuelFighterAssetRelease.File.validName(name), name.hasSuffix(".json"),
                  DuelFighterAssetRelease.validDigest(digest) else { throw Failure.identity }
            let values = try directory.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey])
            guard let count = values.fileSize, (1...maximum).contains(count) else { throw Failure.manifest }
            return try read(.init(name: name, bytes: count, sha256: digest), maximum: maximum)
        }
        guard profile.id == "wuyong_erlang", profile.hero.rawValue == "wuyong_erlang",
              DuelFighterAssetRelease.validDigest(profile.sha256) else { throw Failure.identity }
        // Bind to the very same decoded profile, not merely its GLB basename.
        let profileData = try metadata(profileName, digest: profileSHA256, maximum: 48_000_000)
        let decodedProfile = try JSONDecoder().decode(DuelWeaponProfile.self, from: profileData)
        guard decodedProfile == profile else { throw Failure.identity }
        let data = try metadata(manifestName, digest: expectedSHA256, maximum: 512_000)
        let document = try JSONDecoder().decode(Document.self, from: data)
        let recovered = document.schemaVersion == 5
        let ordinary = (2...5).contains(document.schemaVersion)
        let triggered = (3...5).contains(document.schemaVersion)
        let floor = document.schemaVersion == 4 || recovered
        let triggers = document.triggerSounds ?? []
        guard (recovered ? document.sourceRecoveredProfileSHA256 == recoveredSourceProfileSHA256 &&
                    document.sourceOrdinaryAudioManifestSHA256 == nil &&
                    document.sourceConfigurationHashes == sourceConfigurations :
                document.sourceRecoveredProfileSHA256 == nil && (ordinary ?
                    document.sourceOrdinaryAudioManifestSHA256 == sourceOrdinaryAudioManifestSHA256 &&
                    document.sourceConfigurationHashes == sourceConfigurations :
                    document.schemaVersion == 1 && document.sourceOrdinaryAudioManifestSHA256 == nil)),
              document.profileID == profile.id,
              document.profileSHA256 == profileSHA256, document.characterSHA256 == profile.sha256,
              document.sourceConfigurationSHA256 == sourceConfigurationSHA256,
              document.sourceAudioManifestSHA256 == (recovered ? recoveredSourceAudioManifestSHA256 : sourceAudioManifestSHA256),
              document.files.count == (floor ? 82 : ordinary ? 75 : 28), Set(document.files.map(\.name)).count == document.files.count,
              (1...128).contains(document.markers.count), Set(document.markers.map(\.id)).count == document.markers.count,
              Set(document.deferredTriggers.map(\.sourceName)) ==
                    (triggered ? ["d15_swords_explosion"] : ["d15_meditation", "d15_swords_explosion"]),
              document.deferredTriggers.count == (triggered ? 1 : 2),
              document.deferredTriggers.allSatisfy({ unplayedReasons[$0.sourceName] == $0.reason }),
              document.pendingModels.count <= 11,
              Set(document.pendingModels.map(\.id)).count == document.pendingModels.count,
              Set(document.pendingModels.map(\.id)).isDisjoint(with: Set(document.markers.map(\.id))),
              document.pendingModels.allSatisfy({ $0.reason == "awaiting-exact-source-model-binding" &&
                  $0.animationAlias.hasPrefix("D15_") && (1...32).contains($0.files.count) }) else { throw Failure.manifest }
        if floor {
            guard (recovered ? document.sourceFloorAudioManifestSHA256 == nil :
                    document.sourceFloorAudioManifestSHA256 == sourceFloorAudioManifestSHA256),
                  let context = document.context, context.gender == "Male", context.floor == "Stone",
                  context.stageName == "SF3_Palace_Exterior.glb", context.stageSHA256 == palaceStageSHA256,
                  context.floorSourceSHA256 == sourceFloorManifestSHA256,
                  document.pendingModels.isEmpty, document.markers.count == 119,
                  document.markers.filter({ $0.route == "Floor.Stone" }).count == 21 else { throw Failure.manifest }
        } else {
            guard document.sourceFloorAudioManifestSHA256 == nil, document.context?.floor == nil else { throw Failure.manifest }
        }
        if triggered {
            guard document.sourceTriggerManifestSHA256 == sourceTriggerManifestSHA256, triggers.count == 1,
                  let trigger = triggers.first, trigger.id == "d15_meditation", !trigger.loop,
                  trigger.file == "SF3Erlang_d15_meditation_c928faf2c6d7.wav",
                  let pcm = document.files.first(where: { $0.name == trigger.file }),
                  pcm.sha256 == "c928faf2c6d7645465a94ac376269d1012a52237c11f43821f404b8a099e174e",
                  pcm.sampleRate == 44_100, pcm.channels == 1, pcm.sampleFrames == 441_000,
                  trigger.sourceIdentifier == "set_d15/d15_meditation@Battle@Movement",
                  trigger.sourceLock == 1432,
                  trigger.sourceLockSHA256 == "74917b81d2e8e0bae60123a7bb2a42f15d7ce4dc9f90f57a62c787c66dc4dde7",
                  trigger.startTrigger == 13, trigger.stopTrigger == 21,
                  trigger.startEvent == "meditationStarted", trigger.stopEvent == "meditationStopped" else {
                throw Failure.manifest
            }
        } else {
            guard triggers.isEmpty, document.sourceTriggerManifestSHA256 == nil else { throw Failure.manifest }
        }
        for marker in document.markers {
            if ordinary {
                guard let entry = marker.sourceEntry, let digest = marker.sourceConfigurationSHA256,
                      sourceConfigurations[entry] == digest else { throw Failure.marker(marker.id) }
            }
            guard marker.id.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil,
                  (ordinary || marker.animationAlias.hasPrefix("D15_")),
                  marker.animationAlias.range(of: "^[A-Za-z0-9_]{1,128}$", options: .regularExpression) != nil,
                  (["Common", "Male"].contains(marker.route) ||
                    (floor && marker.route == "Floor.Stone" && marker.modelRole == nil)),
                  (0..<10_000).contains(marker.sourceRecordIndex),
                  (2...36_001).contains(marker.sourceFrames), (1...9).contains(marker.sourceFrameStride),
                  marker.sourceFirstIndex >= 0, marker.sourceFirstIndex <= 36_000,
                  marker.sourceFrame >= marker.sourceFirstIndex,
                  marker.sourceFrame - marker.sourceFirstIndex < marker.sourceFrames,
                  marker.duration == (marker.sourceFrames - 1) * marker.sourceFrameStride,
                  (1...36_000).contains(marker.duration),
                  marker.sourceTick == (marker.sourceFrame - marker.sourceFirstIndex) * marker.sourceFrameStride,
                  (1...32).contains(marker.files.count) else { throw Failure.marker(marker.id) }
            if let role = marker.modelRole {
                guard marker.role == role, modelRoles[marker.animationAlias] == role,
                      let track = profile.summonTrack(role: role),
                      track.clip == marker.clip, track.sourceSHA256 == marker.sourceMotionSHA256,
                      track.frames == marker.sourceFrames, track.root.count - 1 == marker.duration else { throw Failure.marker(marker.id) }
            } else {
                guard let clip = profile.clip(role: marker.role), clip.name == marker.clip,
                      clip.sha256 == marker.sourceMotionSHA256, clip.frames == marker.sourceFrames,
                      clip.ticks == marker.duration else { throw Failure.marker(marker.id) }
            }
        }
        let referenced = Set(document.markers.flatMap(\.files) + document.pendingModels.flatMap(\.files) +
            document.deferredTriggers.map(\.file) + triggers.map(\.file))
        guard referenced == Set(document.files.map(\.name)),
              Set(document.deferredTriggers.map(\.file)).isDisjoint(with: Set(document.markers.flatMap(\.files))) else {
            throw Failure.manifest
        }
        var contents: [String: Data] = [:], total = 0
        var records = [DuelNetworkContentRecord(path: manifestName, bytes: data.count, sha256: expectedSHA256)]
        for file in document.files {
            guard file.name.hasSuffix(".wav") else { throw Failure.file(file.name) }
            total += file.bytes; guard total <= 32_000_000 else { throw Failure.manifest }
            let bytes = try read(file.file, maximum: 4_000_000)
            try verifyPCM(bytes, file: file)
            contents[file.name] = bytes
            records.append(.init(path: file.name, bytes: file.bytes, sha256: file.sha256))
        }
        var audio: [String: [Data]] = [:]
        for marker in document.markers { audio[marker.category] = marker.files.map { contents[$0]! } }
        if let trigger = triggers.first {
            for owner in 0..<2 { audio["erlangTrigger:d15_meditation:\(owner)"] = [contents[trigger.file]!] }
        }
        return Self(profileID: profile.id, characterSHA256: profile.sha256,
            verifiedFiles: records.sorted { $0.path < $1.path }, audio: audio, markers: document.markers,
            pendingModelMarkerCount: document.pendingModels.count, hasMeditationTrigger: triggered)
    }

    private static func verifyPCM(_ data: Data, file: PCM) throws {
        func word(_ index: Int) -> Int { Int(data[index]) | Int(data[index + 1]) << 8 }
        func long(_ index: Int) -> Int { word(index) | word(index + 2) << 16 }
        guard data.count >= 44, data.prefix(4) == Data("RIFF".utf8),
              data[8..<12] == Data("WAVE".utf8), long(4) == data.count - 8,
              file.sampleWidth == 2, [1, 2].contains(file.channels),
              (8_000...192_000).contains(file.sampleRate),
              (1...30 * file.sampleRate).contains(file.sampleFrames),
              DuelFighterAssetRelease.validDigest(file.pcmSHA256) else { throw Failure.file(file.name) }
        var index = 12, chunks = 0, format = false, pcm: Data?
        while index < data.count {
            guard index <= data.count - 8, chunks < 32 else { throw Failure.file(file.name) }
            let size = long(index + 4), start = index + 8
            guard size <= data.count - start else { throw Failure.file(file.name) }
            let tag = data[index..<index + 4]
            if tag == Data("fmt ".utf8) {
                guard !format, (16...40).contains(size), word(start) == 1,
                      word(start + 2) == file.channels, long(start + 4) == file.sampleRate,
                      long(start + 8) == file.sampleRate * file.channels * 2,
                      word(start + 12) == file.channels * 2, word(start + 14) == 16 else { throw Failure.file(file.name) }
                format = true
            } else if tag == Data("data".utf8) {
                guard pcm == nil, size == file.sampleFrames * file.channels * 2 else { throw Failure.file(file.name) }
                pcm = Data(data[start..<start + size])
            }
            index = start + size + size % 2; chunks += 1
        }
        guard index == data.count, format, let pcm,
              DuelNetworkContentRecord.digest(pcm) == file.pcmSHA256 else { throw Failure.file(file.name) }
    }
}
