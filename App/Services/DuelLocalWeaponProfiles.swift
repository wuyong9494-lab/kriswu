import Foundation

/// An optional local profile is authenticated by the app build, never by a
/// digest inside the same JSON. Models remain independently byte-verified by
/// DuelWeaponCharacterAsset before presentation or combat can use them.
@MainActor
enum DuelLocalWeaponProfiles {
    static let founderFileName = "SF3_XuXiao_Profile.json"
    static let founderInfoKey = "FighterXuXiaoProfileSHA256"
    static let maximumBytes = 32_000_000

    enum Failure: Error, Equatable {
        case missingPin, invalidPin, identity
    }

    static func appendingOptional(directory: URL, name: String,
                                  expectedSHA256: String?, hero: DuelGame.Hero,
                                  profileID: String, characterSHA256: String? = nil,
                                  to profiles: [DuelWeaponProfile],
                                  catalog: DuelWeaponCatalog) throws -> [DuelWeaponProfile] {
        guard DuelFighterAssetRelease.File.validName(name) else { throw Failure.identity }
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return profiles }
        guard let pin = expectedSHA256, !pin.isEmpty else { throw Failure.missingPin }
        guard DuelFighterAssetRelease.validDigest(pin) else { throw Failure.invalidPin }
        let data = try DuelFighterAssetReleaseLoader.read(directory: directory, name: name,
            maximum: maximumBytes, hash: pin)
        let profile = try JSONDecoder().decode(DuelWeaponProfile.self, from: data)
        guard profile.hero == hero, profile.id == profileID,
              characterSHA256.map({ profile.sha256 == $0 }) ?? true,
              !profiles.contains(where: { $0.hero == hero || $0.id == profileID }),
              !profiles.isEmpty else { throw Failure.identity }
        // Validate every advertised pairing, including shared motion contracts
        // such as throws and the serpent's pelvis/COM tracks.
        for opponent in profiles {
            try DuelWeaponCatalog(schemaVersion: catalog.schemaVersion,
                previewFramesPerSecond: catalog.previewFramesPerSecond,
                sourceFramesPerSecond: catalog.sourceFramesPerSecond,
                profiles: [profile, opponent]).validate()
        }
        return profiles + [profile]
    }
}
