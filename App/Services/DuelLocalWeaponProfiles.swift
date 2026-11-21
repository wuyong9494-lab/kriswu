import Foundation

/// An optional local profile is authenticated by the app build, never by a
/// digest inside the same JSON. Models remain independently byte-verified by
/// DuelWeaponCharacterAsset before presentation or combat can use them.
enum DuelLocalWeaponProfiles {
    static let founderFileName = "SF3_XuXiao_Profile.json"
    static let founderInfoKey = "FighterXuXiaoProfileSHA256"
    static let maximumBytes = 32_000_000

    enum Failure: Error, Equatable {
        case missingPin, invalidPin, identity, missingSerpentProfile
    }

    /// A failed optional install is unavailable, not a reason to exchange its
    /// identity for a legacy or another person's model. Keep diagnostic detail
    /// separate from the short, user-facing availability message.
    struct Unavailability: Error, Equatable, LocalizedError {
        enum Stage: String, Equatable { case profile, model, combatMedia }
        let hero: DuelGame.Hero
        let stage: Stage
        let resourceName: String
        let underlyingDescription: String

        init(hero: DuelGame.Hero, stage: Stage, resourceName: String, underlying: Error) {
            self.hero = hero; self.stage = stage; self.resourceName = resourceName
            underlyingDescription = String(reflecting: underlying)
        }
        var errorDescription: String? {
            "\(hero.name) resource unavailable (\(stage.rawValue), \(resourceName)): \(underlyingDescription)"
        }
    }

    /// Used by both profile resolution and the store's model/media boundary.
    /// The original throwing validators remain authoritative. Only the affected
    /// person's advertised entry is removed when one of those validators fails.
    struct Resolution: Sendable {
        private(set) var profiles: [DuelWeaponProfile]
        private(set) var unavailableHeroes: [DuelGame.Hero: Unavailability] = [:]

        init(profiles: [DuelWeaponProfile]) { self.profiles = profiles }

        mutating func keepParticipants(_ player: DuelGame.Hero, _ opponent: DuelGame.Hero) {
            profiles.removeAll { $0.hero != player && $0.hero != opponent }
        }

        mutating func quarantine(_ hero: DuelGame.Hero, stage: Unavailability.Stage,
                                 resourceName: String, underlying: Error) {
            let reason = (underlying as? Unavailability).flatMap { $0.hero == hero ? $0 : nil } ??
                Unavailability(hero: hero, stage: stage, resourceName: resourceName, underlying: underlying)
            if unavailableHeroes[hero] == nil { unavailableHeroes[hero] = reason }
            profiles.removeAll { $0.hero == hero }
        }

        mutating func attempt<Value>(hero: DuelGame.Hero, stage: Unavailability.Stage,
                                     resourceName: String, _ load: () throws -> Value) -> Value? {
            guard unavailableHeroes[hero] == nil else { return nil }
            do { return try load() }
            catch {
                quarantine(hero, stage: stage, resourceName: resourceName, underlying: error)
                return nil
            }
        }

        mutating func applyingOptional(hero: DuelGame.Hero, resourceName: String,
                                       _ load: ([DuelWeaponProfile]) throws -> [DuelWeaponProfile]) {
            let previous = profiles
            if let next = attempt(hero: hero, stage: .profile, resourceName: resourceName,
                                  { try load(previous) }) { profiles = next }
        }
    }

    /// A separately authenticated D13 profile replaces only the installed Liu
    /// slot. The signed base catalog remains intact for its own release assets;
    /// its old hammer trails/material bindings are never re-labelled as D13.
    static func replacingOptionalSerpent(directory: URL, in profiles: [DuelWeaponProfile],
                                         catalog: DuelWeaponCatalog) throws -> [DuelWeaponProfile] {
        let name = DuelSerpentAssetIdentity.profileName
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) else {
            // The retired model is absent from new bundles. Keep the historical
            // catalog available to validate its signed metadata, but never
            // advertise its legacy Liu entry as a playable replacement.
            if profiles.contains(where: { $0.hero == .liu && $0.id == "liu_hammers" }) {
                throw Failure.missingSerpentProfile
            }
            return profiles
        }
        let data = try DuelFighterAssetReleaseLoader.read(directory: directory, name: name,
            maximum: maximumBytes, hash: DuelSerpentAssetIdentity.profileSHA256)
        let profile = try JSONDecoder().decode(DuelWeaponProfile.self, from: data)
        guard DuelSerpentBottlePresentation.accepts(profile),
              profile.sha256 == DuelSerpentAssetIdentity.characterSHA256,
              let binding = profile.serpentBinding,
              profiles.filter({ $0.hero == .liu }).count == 1,
              !profiles.contains(where: { $0.id == profile.id && $0.hero != .liu }),
              let previous = profiles.first(where: { $0.hero == .liu }),
              ["liu_hammers", "liu_pangu", "liu_serpent"].contains(previous.id)
        else { throw Failure.identity }
        try binding.validate(profile: profile)
        let result = profiles.map { $0.hero == .liu ? profile : $0 }
        for opponent in result where opponent.hero != .liu {
            try DuelWeaponCatalog(schemaVersion: catalog.schemaVersion,
                previewFramesPerSecond: catalog.previewFramesPerSecond,
                sourceFramesPerSecond: catalog.sourceFramesPerSecond,
                profiles: [profile, opponent]).validate()
        }
        return result
    }

    /// Preserve the two-person network contract while resolving actual installed
    /// identities. Explicit lobby pairs must contain two intended, loaded heroes.
    static func networkCatalog(base: DuelWeaponCatalog, profiles: [DuelWeaponProfile],
                               heroes: [DuelGame.Hero]? = nil) throws -> DuelWeaponCatalog {
        let selected = heroes ?? base.profiles.map(\.hero)
        guard selected.count == 2, Set(selected).count == 2 else { throw Failure.identity }
        let resolved = try selected.map { hero -> DuelWeaponProfile in
            let matches = profiles.filter { $0.hero == hero }
            guard matches.count == 1, let profile = matches.first,
                  profile.isIntendedCharacter else { throw Failure.identity }
            // D20 currently has no complete original network resource binding.
            // Its independent profile pin alone cannot enable this path.
            guard !profile.isFounder else { throw Failure.identity }
            return profile
        }
        let result = DuelWeaponCatalog(schemaVersion: base.schemaVersion,
            previewFramesPerSecond: base.previewFramesPerSecond,
            sourceFramesPerSecond: base.sourceFramesPerSecond, profiles: resolved)
        try result.validate()
        return result
    }

    /// The profile and digest come from the same bytes after the optional install has passed validation.
    struct VerifiedProfile: Sendable {
        let name: String
        let sha256: String
        let profile: DuelWeaponProfile

        fileprivate init(name: String, sha256: String, profile: DuelWeaponProfile) {
            self.name = name
            self.sha256 = sha256
            self.profile = profile
        }
    }

    static func appendingOptional(directory: URL, name: String,
                                  expectedSHA256: String?, hero: DuelGame.Hero,
                                  profileID: String, characterSHA256: String? = nil,
                                  to profiles: [DuelWeaponProfile],
                                  catalog: DuelWeaponCatalog,
                                  onVerified: ((VerifiedProfile) -> Void)? = nil) throws -> [DuelWeaponProfile] {
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
        onVerified?(VerifiedProfile(name: name, sha256: pin, profile: profile))
        return profiles + [profile]
    }
}
