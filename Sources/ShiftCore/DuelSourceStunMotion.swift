import Foundation

/// Shared original victim motions from moves_settings records87/88/89.
/// This capability does not identify the victim's equipment as Pangu. The
/// authenticated release separately pins the complete GLBs and rig FK tracks.
public enum DuelSourceStunMotion: String, CaseIterable, Sendable {
    case start, loop, end

    public static let sourceBundle = "1b0a132a449bc2947a2a326ff30ff33d.bin"
    public var clip: String { "h_stun_" + rawValue }
    public var role: String {
        switch self { case .start: return "sourceStunIn"; case .loop: return "sourceStunLoop"; case .end: return "sourceStunOut" }
    }
    public var frames: Int { self == .loop ? 35 : 31 }
    public var lastSampleTick: Int { 2 * (frames - 1) }
    /// Source defaults MidFrames=1 and SelfEndFrame=4. lock1548/t3/t4
    /// switches only at the In/Loop AnimationEnd, not at timer expiry.
    public var endEventTick: Int { 2 * (frames - 1 - 4) }
    public var sourceSHA256: String {
        switch self {
        case .start: return "ea3b5942fd8c7d8721f9b90bfab4c7c03c55a3dd570c4aa9cff12eefd4d9965b"
        case .loop: return "bd1e3f455499a3caf6df7b67d5c5e40c0aff418fa88dd96aab6fd014de879eb3"
        case .end: return "5d23977e9369fa15724fe5f0b9e3abdf7393d944182425f734258f14369c1eac"
        }
    }

    public init?(role: String) {
        guard let value = Self.allCases.first(where: { $0.role == role }) else { return nil }
        self = value
    }
    public static func declaresBinding(_ profile: DuelWeaponProfile) -> Bool {
        allCases.contains { profile.roles[$0.role] != nil }
    }
    public static func matches(profile: DuelWeaponProfile) -> Bool {
        allCases.allSatisfy { motion in
            guard profile.roles[motion.role] == motion.clip,
                  let clip = profile.clip(role: motion.role) else { return false }
            let samples = motion.lastSampleTick + 1
            return clip.sha256 == motion.sourceSHA256 && clip.bundle == sourceBundle &&
                clip.frames == motion.frames && clip.ticks == motion.lastSampleTick &&
                clip.tracks.samplesPerSourceFrame == 2 &&
                clip.tracks.pelvis?.count == samples && clip.tracks.centerOfMass?.count == samples &&
                clip.tracks.hurtCapsules?.count == 15
        }
    }
}
