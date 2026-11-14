import Foundation

/// Independently pinned H17/Ninjato audio. Every cue is bound to accepted
/// gameplay events or a source animation marker; filenames never infer timing.
@MainActor
struct DuelTriadAudioBinding {
    enum Failure: Error { case identity, manifest, file(String) }
    enum EventKind: String, Decodable {
        case castStarted, castPhase, attackReleased, contact
        case forestStarted, forestEnded, mistBladeStarted, mistBladeEnded
        case soulAppeared, soulSummoned, feast, deflected, rootReleased
        case sourceRootModelCreated, sourceRootModelEnded, sourceWaveFirstFrame, sourceWaveModelCreated, sourceBlastModelCreated
        case sourceSoulModelCreated, sourceSoulAnimationEnded
        case arenaForestLoopStarted, sourceRoundStarted, sourceRoundFightEnded
    }
    struct Cue: Decodable {
        let id: String
        let event: EventKind
        let ability: DuelTriadRules.Ability?
        let phase: DuelTriadState.Phase?
        let origin: DuelTriadState.Origin?
        let contactKind: String?
        let files: [String]
        let loopUntil: EventKind?
        let sourceRoles: [String]?
        /// The shared source cue also routes FX callbacks: lock1799 owns the
        /// first RoundStart, while lock1800 starts ambience in later rounds.
        /// Original audio starts the first forest at its intro interval marker.
        let sourceRoundScope: String?
        var category: String { "triadCue:" + id }
        init(id: String, event: EventKind, ability: DuelTriadRules.Ability?, phase: DuelTriadState.Phase?,
             origin: DuelTriadState.Origin?, contactKind: String?, files: [String],
             loopUntil: EventKind?, sourceRoles: [String]? = nil, sourceRoundScope: String? = nil) {
            self.id = id; self.event = event; self.ability = ability; self.phase = phase; self.origin = origin
            self.contactKind = contactKind; self.files = files; self.loopUntil = loopUntil; self.sourceRoles = sourceRoles
            self.sourceRoundScope = sourceRoundScope
        }
        /// Both original H17 wave models carry Sounds.Frame=1. That is two
        /// live simulation ticks after their own ModelCreated, not the owner.
        var delayTicks: Int { event == .sourceWaveFirstFrame ? 2 : 0 }
        func matches(_ value: DuelTriadPresentation.Event.Kind) -> Bool {
            switch (event, value) {
            case (.castStarted, .castStarted(_, let cast)): return ability == cast.ability && phase == cast.phase
            case (.castPhase, .effect(_, .castPhase(let ability, let phase))): return self.ability == ability && self.phase == phase
            case (.attackReleased, .attackReleased(let attack)): return ability == attack.ability && origin == attack.origin
            case (.contact, .contact(let contact)):
                return contact.attackID != nil && ability == contact.ability && contactKind == contact.kind.rawValue
            case (.soulAppeared, .effect(_, .soulAppeared(let soul, let origin, _))),
                 (.soulSummoned, .effect(_, .soulSummoned(let soul, let origin, _))):
                return ability?.soul == soul && self.origin == origin
            case (.soulAppeared, .effect(_, .sourceSoulAppeared(let value))):
                return ability?.soul == value.soul && origin == value.origin
            case (.forestStarted, .effect(_, .forestStarted)), (.forestEnded, .effect(_, .forestEnded)),
                 (.mistBladeStarted, .effect(_, .mistBladeStarted)), (.mistBladeEnded, .effect(_, .mistBladeEnded)),
                 (.feast, .effect(_, .feast)), (.deflected, .effect(_, .deflected)):
                return true
            case (.rootReleased, .effect(_, .controlReleased(_, let kind))): return kind == .root
            case (.sourceRootModelCreated, .source(_, .modelCreated(_, .roots, _))),
                 (.sourceRootModelEnded, .source(_, .rootModelEnded)),
                 (.sourceWaveFirstFrame, .source(_, .modelCreated(_, .mistWave, _))),
                 (.sourceWaveModelCreated, .source(_, .modelCreated(_, .mistWave, _))),
                 (.sourceBlastModelCreated, .source(_, .modelCreated(_, .heraldBlast, _))),
                 (.arenaForestLoopStarted, .source(_, .arenaForestLoopStarted)),
                 (.sourceRoundFightEnded, .source(_, .roundFightEnded)):
                return true
            case (.sourceRoundStarted, .source(_, .roundStarted(let round))):
                return sourceRoundScope == "first" ? round == 1 : sourceRoundScope == nil && round > 1
            case (.sourceSoulModelCreated, .source(_, .soulModelCreated(_, let move))):
                return sourceRoles?.contains(move.role) == true
            case (.sourceSoulAnimationEnded, .source(_, .soulAnimationEnded(_, let role))):
                return sourceRoles?.contains(role) == true
            default: return false
            }
        }
        func stops(on value: DuelTriadPresentation.Event.Kind) -> Bool {
            if loopUntil == .forestEnded, case .effect(_, .forestEnded) = value { return true }
            if loopUntil == .sourceRoundFightEnded, case .source(_, .roundFightEnded) = value { return true }
            return false
        }
    }
    struct Marker: Decodable {
        enum Clock: String, Decodable { case soundFrame, intervalStart, animationStart }
        let id: String
        let clip: String
        let sourceFrame: Int
        let files: [String]
        let summonRole: String?
        let clock: Clock?
        let loopUntil: EventKind?
        /// Original arrays can deliberately repeat a sound to weight a
        /// variant. Their order/multiplicity is retained by the binding.
        let context: String?
        /// An explicitly pinned second character may use only its verified
        /// common throw clips. Nil means this document's main H17 character.
        let profileID: String?
        var category: String { "triadMarker:" + id }
        var sourceKey: String { profileID.map { $0 + "/" + clip } ?? summonRole.map { $0 + "/" + clip } ?? clip }
        var playbackFrame: Int { clock == .intervalStart ? max(0, sourceFrame - 1) : sourceFrame }
    }
    struct SourceContext: Decodable, Equatable {
        let gender: String
        let floor: String
        static let maleStone = Self(gender: "Male", floor: "Stone")
    }
    private struct Document: Decodable {
        let version: Int
        let profileID: String
        let characterSHA256: String
        let sourceConfigurationSHA256: String
        let evidence: [String]
        let files: [DuelFighterAssetRelease.File]
        let audio: [String: [String]]
        let cues: [Cue]
        let markers: [Marker]
        let context: SourceContext?
        let motionProfiles: [String: String]?
    }
    let profileID: String
    let characterSHA256: String
    let verifiedFiles: [DuelNetworkContentRecord]
    let audio: [String: [Data]]
    let cues: [Cue]
    let markers: [Marker]
    let sourceFrameCounts: [String: Int]
    let companionClips: [String: String]
    let motionProfileIDs: Set<String>
    var loopCategories: Set<String> {
        Set(cues.filter { $0.loopUntil != nil }.map(\.category) + markers.filter { $0.loopUntil != nil }.map(\.category))
    }
    var sourceLoopCategories: Set<String> {
        Set(cues.filter { $0.loopUntil == .sourceRoundFightEnded }.map(\.category) +
            markers.filter { $0.loopUntil == .sourceRoundFightEnded }.map(\.category))
    }

    static func load(directory: URL, manifestName: String, expectedSHA256: String,
                     profile: DuelWeaponProfile, companions: DuelTriadSummonAssets? = nil,
                     context: SourceContext = .maleStone,
                     additionalProfiles: [DuelWeaponProfile] = []) throws -> Self {
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
        guard profile.isTriad, profile.hero == .ember, DuelFighterAssetRelease.validDigest(profile.sha256),
              DuelFighterAssetRelease.File.validName(manifestName), manifestName.hasSuffix(".json"),
              DuelFighterAssetRelease.validDigest(expectedSHA256) else { throw Failure.identity }
        let manifestURL = directory.appendingPathComponent(manifestName)
        let values = try manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let count = values.fileSize, (1...512_000).contains(count) else { throw Failure.manifest }
        let data = try read(.init(name: manifestName, bytes: count, sha256: expectedSHA256), maximum: 512_000)
        let document = try JSONDecoder().decode(Document.self, from: data)
        let categories: Set<String> = ["ninjatoHit", "ninjatoBlock", "ninjatoWhoosh"]
        func validID(_ value: String) -> Bool {
            value.range(of: "^[A-Za-z0-9_-]{1,96}$", options: .regularExpression) != nil
        }
        func validGroup(_ files: [String]) -> Bool {
            (1...32).contains(files.count) && (document.version >= 2 || Set(files).count == files.count)
        }
        guard (1...2).contains(document.version), document.profileID == profile.id, document.characterSHA256 == profile.sha256,
              (document.version == 1 ? document.context == nil : document.context == context),
              context == .maleStone,
              DuelFighterAssetRelease.validDigest(document.sourceConfigurationSHA256),
              (1...32).contains(document.evidence.count), document.evidence.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }),
              Set(document.audio.keys).isSubset(of: categories), document.audio.values.allSatisfy(validGroup),
              document.cues.count <= 128, document.markers.count <= 1024,
              Set(document.cues.map(\.id)).count == document.cues.count,
              Set(document.markers.map(\.id)).count == document.markers.count,
              (1...96).contains(document.files.count), Set(document.files.map(\.name)).count == document.files.count else {
            throw Failure.manifest
        }
        let sourceRoles = Set(DuelTriadRules.SummonMove.allCases.map(\.role) +
            [DuelTriadRules.SoulAnimation.ninjatoActiveStart.role, DuelTriadRules.SoulAnimation.ninjatoActiveEnd.role])
        for cue in document.cues {
            guard validID(cue.id), validGroup(cue.files), cue.sourceRoundScope == nil else { throw Failure.manifest }
            if cue.event.rawValue.hasPrefix("source") || cue.event == .arenaForestLoopStarted {
                guard document.version == 2 else { throw Failure.manifest }
            }
            switch cue.event {
            case .castStarted, .castPhase:
                guard cue.ability != nil, cue.phase != nil, cue.origin == nil, cue.contactKind == nil else { throw Failure.manifest }
            case .attackReleased, .soulAppeared, .soulSummoned:
                guard cue.ability != nil, cue.origin != nil, cue.phase == nil, cue.contactKind == nil,
                      cue.event == .attackReleased || cue.ability?.soul != nil else { throw Failure.manifest }
            case .contact:
                guard cue.ability != nil, cue.origin == nil, cue.phase == nil,
                      cue.contactKind == "hit" || cue.contactKind == "block" else { throw Failure.manifest }
            default:
                guard cue.ability == nil, cue.origin == nil, cue.phase == nil, cue.contactKind == nil else { throw Failure.manifest }
            }
            if cue.event == .sourceSoulModelCreated || cue.event == .sourceSoulAnimationEnded {
                guard document.version == 2, let roles = cue.sourceRoles, !roles.isEmpty,
                      roles.count <= sourceRoles.count, Set(roles).count == roles.count,
                      Set(roles).isSubset(of: sourceRoles) else { throw Failure.manifest }
            } else if cue.sourceRoles != nil { throw Failure.manifest }
            if let stop = cue.loopUntil {
                let legacy = cue.event == .forestStarted && stop == .forestEnded
                let source = (cue.event == .arenaForestLoopStarted || cue.event == .sourceRoundStarted) &&
                    stop == .sourceRoundFightEnded && document.version == 2
                guard (legacy || source), cue.files.count == 1 else { throw Failure.manifest }
            }
        }
        var sourceFrames = Dictionary(uniqueKeysWithValues: profile.clips.map { ($0.name, $0.frames) })
        var sharedClips: [String: Set<String>] = [:]
        if let pins = document.motionProfiles {
            guard document.version == 2, pins.count == 1,
                  Set(additionalProfiles.map(\.id)).count == additionalProfiles.count else { throw Failure.identity }
            for (id, hash) in pins {
                guard id != profile.id, id == "liu_hammers" || id == "liu_pangu",
                      DuelFighterAssetRelease.validDigest(hash),
                      let other = additionalProfiles.first(where: { $0.id == id }), other.hero == .liu,
                      other.sha256 == hash, let rules = other.ordinaryThrows?.source else { throw Failure.identity }
                try rules.validate()
                var names = Set<String>()
                for motion in rules.motions.values {
                    guard let clip = other.clip(role: motion.role), clip.sha256 == motion.sourceSHA256,
                          2 * (clip.frames - 1) == motion.lastSampleTick, clip.ticks == motion.lastSampleTick else {
                        throw Failure.identity
                    }
                    names.insert(clip.name); sourceFrames[id + "/" + clip.name] = clip.frames
                }
                guard names.count == DuelSourceThrowRules.Motion.allCases.count else { throw Failure.identity }
                sharedClips[id] = names
            }
        }
        var companionClips: [String: String] = [:]
        if let companions {
            guard companions.profileID == profile.id, companions.characterSHA256 == profile.sha256 else { throw Failure.identity }
            sourceFrames.merge(companions.sourceFrameCounts) { first, _ in first }
            companionClips = companions.roles.mapValues { $0.motion.clip }
        }
        for marker in document.markers {
            if let id = marker.profileID {
                guard document.version == 2, sharedClips[id]?.contains(marker.clip) == true,
                      marker.summonRole == nil, marker.loopUntil == nil,
                      marker.clock == .soundFrame else { throw Failure.identity }
            }
            guard validID(marker.id), validGroup(marker.files), let frames = sourceFrames[marker.sourceKey],
                  (0..<frames).contains(marker.sourceFrame),
                  marker.clock != .intervalStart || marker.sourceFrame > 0,
                  marker.clock != .animationStart || marker.sourceFrame == 0,
                  marker.context == nil || (document.version == 2 && ["Common", "Gender.Male", "Floor.Stone"].contains(marker.context!)) else {
                throw Failure.manifest
            }
            if let stop = marker.loopUntil {
                guard document.version == 2, stop == .sourceRoundFightEnded, marker.files.count == 1,
                      marker.summonRole == nil, marker.clock == .intervalStart else { throw Failure.manifest }
            }
        }
        let references = document.audio.values.flatMap { $0 } + document.cues.flatMap(\.files) + document.markers.flatMap(\.files)
        guard Set(references) == Set(document.files.map(\.name)) else { throw Failure.manifest }
        var contents: [String: Data] = [:]
        var records = [DuelNetworkContentRecord(path: manifestName, bytes: data.count, sha256: expectedSHA256)]
        var total = 0
        for file in document.files {
            guard file.name.hasSuffix(".wav"), (1...4_000_000).contains(file.bytes) else { throw Failure.manifest }
            total += file.bytes; guard total <= 32_000_000 else { throw Failure.manifest }
            let bytes = try read(file, maximum: 4_000_000)
            guard bytes.count >= 44, bytes.prefix(4) == Data("RIFF".utf8), bytes[8..<12] == Data("WAVE".utf8) else {
                throw Failure.file(file.name)
            }
            contents[file.name] = bytes
            records.append(.init(path: file.name, bytes: file.bytes, sha256: file.sha256))
        }
        var audio = document.audio.mapValues { names in names.map { contents[$0]! } }
        for cue in document.cues { audio[cue.category] = cue.files.map { contents[$0]! } }
        for marker in document.markers { audio[marker.category] = marker.files.map { contents[$0]! } }
        return Self(profileID: document.profileID, characterSHA256: document.characterSHA256,
            verifiedFiles: records.sorted { $0.path < $1.path }, audio: audio, cues: document.cues,
            markers: document.markers, sourceFrameCounts: sourceFrames, companionClips: companionClips,
            motionProfileIDs: Set(sharedClips.keys))
    }
}
