import Foundation

/// settings_sets_dynasty record133 keeps only staff_idle's first original frame.
/// FirstFrame=nil, EndFrame=1, SelfEndFrame=0, BlendingFrames=0. The release
/// separately authenticates the complete raw source and exported GLB/FK data.
public enum DuelErlangTransformOutMotion {
    public static let role = "erlangTransformOut"
    public static let sourceSHA256 = "72da7978875aa9b288933add7c045cdc417938a6f9887a55d0e0efddcf7123e1"
    public static let sourceBundle = "baccadc1bc62c24fcf83246b63fd6c17.bin"

    public static func matches(clip: DuelWeaponClip, profile: DuelWeaponProfile) -> Bool {
        profile.isErlang && profile.roles[role] == clip.name &&
            clip.sha256 == sourceSHA256 && clip.bundle == sourceBundle &&
            clip.frames == 1 && clip.playbackTicks == 0 && clip.sourceEndEventTick == 0 &&
            clip.tracks.samplesPerSourceFrame == 2 &&
            clip.tracks.centerOfMass?.count == 1 && clip.tracks.pelvis?.count == 1 &&
            clip.tracks.toeL?.count == 1 && clip.tracks.toeR?.count == 1 &&
            clip.tracks.head?.count == 1 && clip.tracks.hurtCapsules?.count == 15
    }
}
