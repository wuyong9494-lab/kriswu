import Foundation

/// Byte-authenticated ordinary snake poison/bottle source audio. Unbound
/// source files are checked but never assigned an invented gameplay event.
@MainActor
struct DuelSerpentSourceAudio {
    static let manifestName = "SF3_Serpent_Audio.json"
    static let manifestSHA256 = "1ecd028177667cb2412df83d3a65252c064b0b299ccb3e5cd3105d55cd70acee"
    static let bodyManifestName = "SF3_Serpent_Body_Audio.json"
    static let bodyManifestSHA256 = "0c595b5c6e79423e3b2dc6ba21ba00e55f55194dc417aba959813a3531f28387"
    let profileID, characterSHA256: String
    let verifiedFiles: [DuelNetworkContentRecord]
    let audio: [String: [Data]]
    let loopCategories: Set<String>
    let bodyMarkers: [DuelSerpentBodyAudioClock.Marker]
    private let identifiers: Set<String>
    private let bodyMarkerIDs: Set<String>

    func category(identifier: String, owner: Int) -> String? {
        guard (0..<2).contains(owner), identifiers.contains(identifier) else { return nil }
        return "serpentSource:\(owner):" + identifier
    }

    func bodyCategory(markerID: String, owner: Int) -> String? {
        guard (0..<2).contains(owner), bodyMarkerIDs.contains(markerID) else { return nil }
        return "serpentBody:\(owner):" + markerID
    }

    static func load(directory: URL, profile: DuelWeaponProfile) throws -> Self {
        let data = try DuelFighterAssetReleaseLoader.read(directory: directory, name: manifestName,
            maximum: 128_000, hash: manifestSHA256)
        let document = try JSONDecoder().decode(DuelSerpentSourceAudioManifest.self, from: data)
        try document.validate(profile: profile)
        var contents: [String: Data] = [:]
        var records = [DuelNetworkContentRecord(path: manifestName, bytes: data.count, sha256: manifestSHA256)]
        for file in document.files {
            let bytes = try DuelFighterAssetReleaseLoader.read(directory: directory, name: file.name,
                maximum: 4_000_000, bytes: file.bytes, hash: file.sha256)
            let pcm = try DuelSerpentSourceAudioManifest.pcmPayload(bytes, file: file)
            guard DuelNetworkContentRecord.digest(pcm) == file.pcmSHA256 else {
                throw DuelSerpentSourceAudioManifest.Failure.pcm
            }
            contents[file.name] = bytes
            records.append(.init(path: file.name, bytes: file.bytes, sha256: file.sha256))
        }
        let bodyData = try DuelFighterAssetReleaseLoader.read(directory: directory, name: bodyManifestName,
            maximum: 1_000_000, hash: bodyManifestSHA256)
        let body = try JSONDecoder().decode(DuelSerpentBodyAudioManifest.self, from: bodyData)
        try body.validate(profile: profile)
        records.append(.init(path: bodyManifestName, bytes: bodyData.count, sha256: bodyManifestSHA256))
        for file in body.files {
            let bytes: Data
            if let existing = contents[file.name] {
                guard existing.count == file.bytes, DuelNetworkContentRecord.digest(existing) == file.sha256 else {
                    throw DuelSerpentSourceAudioManifest.Failure.pcm
                }
                bytes = existing
            } else {
                bytes = try DuelFighterAssetReleaseLoader.read(directory: directory, name: file.name,
                    maximum: 4_000_000, bytes: file.bytes, hash: file.sha256)
                contents[file.name] = bytes
                records.append(.init(path: file.name, bytes: file.bytes, sha256: file.sha256))
            }
            let pcm = try DuelSerpentSourceAudioManifest.pcmPayload(bytes, file: file)
            guard DuelNetworkContentRecord.digest(pcm) == file.pcmSHA256 else {
                throw DuelSerpentSourceAudioManifest.Failure.pcm
            }
        }
        var audio: [String: [Data]] = [:], loops: Set<String> = []
        // Each fighter owns a distinct player, including same-tick starts.
        // Stopping one owner's rain must not stop the opponent's instance.
        for owner in 0..<2 {
            for sound in document.sounds {
                let category = "serpentSource:\(owner):" + sound.identifier
                audio[category] = [contents[sound.file]!]
                if sound.loop { loops.insert(category) }
            }
            for marker in body.markers {
                // Keep the source order and repeated candidates: duplicates
                // are the authored selection weight, not redundant entries.
                audio["serpentBody:\(owner):" + marker.id] = marker.choices.map { contents[$0.file]! }
            }
        }
        return Self(profileID: profile.id, characterSHA256: profile.sha256,
            verifiedFiles: records.sorted { $0.path < $1.path }, audio: audio,
            loopCategories: loops, bodyMarkers: body.markers.map(\.clock),
            identifiers: Set(document.sounds.map(\.identifier)), bodyMarkerIDs: Set(body.markers.map(\.id)))
    }

    #if DEBUG
    /// Synthetic playback seam, never used by the production resource loader.
    static func playbackFixture(pcm: Data, includeBody: Bool = false) -> Self {
        let names = Set(DuelSerpentAudioTimeline.sounds.keys)
        let markers: [DuelSerpentBodyAudioClock.Marker] = includeBody ? [
            .init(id: "fixture-swing", clip: "fixture-motion", tick: 20, duration: 60),
            .init(id: "fixture-stone", clip: "fixture-motion", tick: 22, duration: 60, requiresPalaceStone: true)
        ] : []
        var audio: [String: [Data]] = [:], loops: Set<String> = []
        for owner in 0..<2 {
            for (identifier, loop) in DuelSerpentAudioTimeline.sounds {
                let category = "serpentSource:\(owner):" + identifier
                audio[category] = [pcm]
                if loop { loops.insert(category) }
            }
            for marker in markers { audio["serpentBody:\(owner):" + marker.id] = [pcm] }
        }
        return Self(profileID: "synthetic-audio-only", characterSHA256: "", verifiedFiles: [],
                    audio: audio, loopCategories: loops, bodyMarkers: markers,
                    identifiers: names, bodyMarkerIDs: Set(markers.map(\.id)))
    }
    #endif
}
