import Foundation

/// Exact associations for an independently reviewed private asset revision.
/// Its SHA-256 must come from the signed application's build settings, never
/// from this document or a peer. Integrity is not proof of original-game fidelity.
public struct DuelFighterAssetRelease: Codable, Equatable, Sendable {
    public static let fileName = "SF3_FighterRelease.json"
    public static let infoKey = "FighterAssetReleaseSHA256"
    public static let maximumBytes = 1_000_000

    public struct File: Codable, Equatable, Sendable {
        public let name: String
        public let bytes: Int
        public let sha256: String
        public init(name: String, bytes: Int, sha256: String) {
            self.name = name; self.bytes = bytes; self.sha256 = sha256
        }
        public func validate(maximum: Int) throws {
            guard Self.validName(name), (1...maximum).contains(bytes),
                  DuelFighterAssetRelease.validDigest(sha256) else { throw Failure.file }
        }
        public static func validName(_ name: String) -> Bool {
            !name.contains("..") && name.utf8.count <= 128 &&
                name.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.-]*\\z", options: .regularExpression) != nil
        }
    }
    public struct Motion: Codable, Equatable, Sendable {
        public let clip: String
        public let sourceSHA256: String
        public let sourceBundle: String
        public let frames: Int
        public let exportFramesPerSecond: Int
        /// Nil means unrecovered. The export clock must never fill this field.
        public let sourceFramesPerSecond: Double?
    }
    public struct SkinRoot: Codable, Equatable, Sendable {
        public let skin: Int
        public let declared: Int
        public let corrected: Int
    }
    public struct Material: Codable, Equatable, Sendable {
        public enum Cull: String, Codable, Sendable { case back, front }
        public enum Filter: String, Codable, Sendable { case nearest, linear }
        public enum Mip: String, Codable, Sendable { case none, nearest, linear }
        public enum Wrap: String, Codable, Sendable { case clamp, `repeat` }
        public let name: String
        public let doubleSided: Bool
        public let cull: Cull
        public let minification: Filter
        public let magnification: Filter
        public let mip: Mip
        public let wrapS: Wrap
        public let wrapT: Wrap
        public let maxAnisotropy: Int
    }
    public struct Profile: Codable, Equatable, Sendable {
        public let id: String
        public let characterSHA256: String
        public let bodyID: String
        public let weaponID: String
        public let sourceVersion: String
        public let evidence: [String]
        public let motions: [Motion]
        public let skinRoots: [SkinRoot]
        public let restorePersonalBindSpace: Bool
        public let materials: [Material]
    }
    public let schemaVersion: Int
    public let id: String
    public let catalog: File
    public let sourceTrails: File
    public let panguAudio: File?
    public let triadAudio: File?
    public let triadSummons: File?
    public let triadEffects: File?
    public let profiles: [Profile]

    public enum Failure: Error, Equatable {
        case version, identity, file, profile, motion, rig, material
    }
    public static func validDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    public func profile(id: String) -> Profile? { profiles.first { $0.id == id } }

    public func validate(catalog target: DuelWeaponCatalog) throws {
        guard schemaVersion == 1 || schemaVersion == 2 else { throw Failure.version }
        guard !id.isEmpty, id.utf8.count <= 128 else { throw Failure.identity }
        try target.validate()
        try catalog.validate(maximum: 32_000_000)
        try sourceTrails.validate(maximum: 2_000_000)
        try panguAudio?.validate(maximum: 256_000)
        try triadAudio?.validate(maximum: 512_000)
        try triadSummons?.validate(maximum: 1_000_000)
        try triadEffects?.validate(maximum: 32_000_000)
        let audioFiles = [panguAudio, triadAudio, triadSummons, triadEffects].compactMap { $0 }
        guard catalog.name == "SF3_DistinctFighters.json",
              sourceTrails.name.hasSuffix(".json"), audioFiles.allSatisfy({
                  $0.name.hasSuffix(".json") || ($0 == triadEffects && $0.name.hasSuffix(".json.gz"))
              }),
              sourceTrails.name != "SF3_SourceTrails.json",
              audioFiles.allSatisfy({ $0.name != "SF3FX_manifest.json" }),
              Set([catalog.name, sourceTrails.name, Self.fileName] + audioFiles.map(\.name)).count == 3 + audioFiles.count else {
            throw Failure.file
        }
        let hasPangu = target.profiles.contains(where: \.isPangu), hasTriad = target.profiles.contains(where: \.isTriad)
        guard schemaVersion == 2 ? hasTriad : (hasPangu && !hasTriad),
              (panguAudio != nil) == hasPangu, (triadAudio != nil) == hasTriad,
              (triadSummons != nil) == hasTriad,
              (triadEffects != nil) == hasTriad,
              profiles.count == target.profiles.count,
              Set(profiles.map(\.id)) == Set(target.profiles.map(\.id)) else { throw Failure.profile }
        for binding in profiles {
            guard let equipped = target.profiles.first(where: { $0.id == binding.id }),
                  binding.characterSHA256 == equipped.sha256,
                  Self.validDigest(binding.characterSHA256),
                  binding.bodyID == equipped.bodyID, binding.weaponID == equipped.weaponID,
                  !binding.sourceVersion.isEmpty, binding.sourceVersion.utf8.count <= 256,
                  (1...32).contains(binding.evidence.count),
                  binding.evidence.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }) else { throw Failure.profile }
            guard binding.motions.count == equipped.clips.count,
                  Set(binding.motions.map(\.clip)) == Set(equipped.clips.map(\.name)) else { throw Failure.motion }
            for motion in binding.motions {
                guard let clip = equipped.clip(named: motion.clip),
                      motion.sourceSHA256 == clip.sha256, Self.validDigest(motion.sourceSHA256),
                      motion.sourceBundle == clip.bundle, !motion.sourceBundle.isEmpty,
                      motion.sourceBundle.utf8.count <= 512, motion.frames == clip.frames,
                      motion.exportFramesPerSecond == target.previewFramesPerSecond else { throw Failure.motion }
                if let fps = motion.sourceFramesPerSecond {
                    guard fps.isFinite, (1...240).contains(fps) else { throw Failure.motion }
                }
                if let fps = target.sourceFramesPerSecond, motion.sourceFramesPerSecond != fps {
                    throw Failure.motion
                }
            }
            guard binding.skinRoots.count <= 32,
                  Set(binding.skinRoots.map(\.skin)).count == binding.skinRoots.count,
                  binding.skinRoots.allSatisfy({ (0..<32).contains($0.skin) &&
                      (0..<4096).contains($0.declared) && (0..<4096).contains($0.corrected) &&
                      $0.declared != $0.corrected }) else { throw Failure.rig }
            guard binding.materials.count <= 128,
                  Set(binding.materials.map(\.name)).count == binding.materials.count,
                  binding.materials.allSatisfy({ !$0.name.isEmpty && $0.name.utf8.count <= 256 &&
                      (1...16).contains($0.maxAnisotropy) }) else { throw Failure.material }
        }
    }
}
