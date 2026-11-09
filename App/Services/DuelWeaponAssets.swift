import Foundation
import CryptoKit
import SceneKit

/// Integrity-bound catalog and separate source character assets. A corrupt or
/// missing equipped character must never silently become the old common body.
@MainActor
final class DuelWeaponAssets {
    static let catalogSHA256 = "c4ee840d89cf1b2b8b82db0aebce878dbc5c2f2f60a52cf5b5a77b84f139ed5f"
    enum AssetError: Error { case missing, integrity, incomplete }
    let catalog: DuelWeaponCatalog
    let directory: URL
    private var characters: [DuelGame.Hero: DuelWeaponCharacterAsset] = [:]
    static func catalogURL(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "SF3_DistinctFighters", withExtension: "json") ??
            bundle.url(forResource: "SF3_DistinctFighters", withExtension: "json", subdirectory: "FighterPrivate")
    }
    init(directory: URL? = nil, bundle: Bundle = .main) throws {
        let url: URL
        if let directory { url = directory.appendingPathComponent("SF3_DistinctFighters.json") }
        else if let found = Self.catalogURL(bundle: bundle) { url = found }
        else { throw AssetError.missing }
        let data = try Data(contentsOf: url)
        guard Self.digest(data) == Self.catalogSHA256 else { throw AssetError.integrity }
        let catalog = try JSONDecoder().decode(DuelWeaponCatalog.self, from: data)
        try catalog.validate()
        self.catalog = catalog; self.directory = url.deletingLastPathComponent()
        for profile in catalog.profiles {
            let modelURL = self.directory.appendingPathComponent(profile.resourceName + ".glb")
            guard FileManager.default.fileExists(atPath: modelURL.path) else { throw AssetError.missing }
        }
    }
    func character(for hero: DuelGame.Hero) throws -> DuelWeaponCharacterAsset {
        if let existing = characters[hero] { return existing }
        guard let profile = catalog.profile(for: hero) else { throw AssetError.incomplete }
        let value = try DuelWeaponCharacterAsset(url: directory.appendingPathComponent(profile.resourceName + ".glb"), profile: profile)
        characters[hero] = value; return value
    }
    func releaseCharacter(for hero: DuelGame.Hero) { characters.removeValue(forKey: hero) }
    func releaseCharacters() { characters.removeAll() }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

@MainActor
final class DuelWeaponCharacterAsset {
    let profile: DuelWeaponProfile
    let model: GLTFModel
    private let starts: [String: Float]
    init(url: URL, profile: DuelWeaponProfile) throws {
        let data = try Data(contentsOf: url)
        guard data.count == profile.bytes, DuelWeaponAssets.digest(data) == profile.sha256 else {
            throw DuelWeaponAssets.AssetError.integrity
        }
        // These two byte-verified exports include node 0 ("skeleton") in the
        // skin's joints, but declare its child node 1 ("Armature") as the root.
        // SceneKit needs the common ancestor of every joint. Correct only that
        // declaration in memory; preserve the original hierarchy, joint order,
        // inverse binds, animation channels, and authenticated source bytes.
        let correctedExports: Set<String> = [
            "5a1a64c9986b0d5284a7986efc1589dbfc1f00f91ac9477cdae45930612ac553",
            "9ff998118a69b1d089694e97b2623cf6d6fb81e64451a8462dddaff756b6a09f"
        ]
        let corrections: [Int: GLTFModel.SkinRootCorrection] = correctedExports.contains(profile.sha256)
            ? [0: .init(declared: 1, corrected: 0)] : [:]
        let model = try GLTFModel(url: url, maxTexture: 1024, physicallyBased: true,
                                  skinRootCorrections: corrections)
        let expected = Set(profile.clips.map(\.name))
        guard model.hasSkinning, expected.isSubset(of: Set(model.clips.keys)),
              ["pelvis", "head", "hand_l", "hand_r", "foot_l", "foot_r", "weapon_l", "weapon_r"].allSatisfy({ model.node(named: $0) != nil }),
              model.node(named: (profile.hero == .ember ? "Sun" : "Liu") + "_Personal_Head") != nil else {
            throw DuelWeaponAssets.AssetError.incomplete
        }
        var starts: [String: Float] = [:]
        for clip in profile.clips {
            guard let native = model.clips[clip.name], !native.channels.isEmpty,
                  let start = native.channels.compactMap({ $0.times.first }).min(), start.isFinite,
                  abs(native.duration - start - Float(clip.frames - 1) / 30) < 0.001 else {
                throw DuelWeaponAssets.AssetError.incomplete
            }
            starts[clip.name] = start
        }
        self.profile = profile; self.model = model; self.starts = starts
    }
    func sample(_ selection: DuelWeaponPose, into pose: inout GLTFModel.Pose) {
        pose.reset(from: model.restPose)
        guard let clip = model.clips[selection.clip], let start = starts[selection.clip] else { return }
        clip.sample(at: start + Float(selection.phase) * (clip.duration - start), into: &pose)
    }
}

@MainActor
final class DuelWeaponCharacterInstance {
    let asset: DuelWeaponCharacterAsset
    let instance: GLTFModel.Instance
    private var pose: GLTFModel.Pose
    private var previousClip: String?
    private var idleBlendSource: GLTFModel.Pose?
    private var idleBlendStartTick = 0
    private static let idleBlendTicks = 6

    init(_ asset: DuelWeaponCharacterAsset) {
        self.asset = asset; instance = asset.model.instantiate(); pose = asset.model.restPose
        instance.root.name = "duel.equipped.\(asset.profile.id)"
    }
    func apply(_ selection: DuelWeaponPose) {
        // Smooth recovery-to-idle only in the displayed skeleton. Source clips,
        // combat timing and collision sampling are deliberately untouched.
        // Simulation ticks prevent repeated display callbacks advancing a blend.
        if selection.clip != previousClip {
            if selection.clip == asset.profile.roles["idle"], previousClip != nil {
                idleBlendSource = pose
                idleBlendStartTick = selection.tick
            } else {
                idleBlendSource = nil
            }
            previousClip = selection.clip
        }
        asset.sample(selection, into: &pose)
        if let source = idleBlendSource {
            let elapsed = selection.tick - idleBlendStartTick
            if elapsed < 0 || elapsed >= Self.idleBlendTicks {
                idleBlendSource = nil
            } else {
                // Keep the exact recovery pose on the first idle simulation tick.
                // Reach the unmodified idle sample on the final transition tick.
                let t = Float(elapsed) / Float(Self.idleBlendTicks - 1)
                let eased = t * t * (3 - 2 * t)
                for index in asset.model.animated {
                    pose.translation[index] = simd_mix(source.translation[index], pose.translation[index],
                                                       SIMD3<Float>(repeating: eased))
                    pose.rotation[index] = simd_slerp(source.rotation[index], pose.rotation[index], eased)
                    pose.scale[index] = simd_mix(source.scale[index], pose.scale[index],
                                                 SIMD3<Float>(repeating: eased))
                }
            }
        }
        for index in asset.model.animated { instance.nodes[index].simdTransform = pose.transform(index) }
    }
    func pose(_ fighter: DuelGame.Fighter, root: SCNNode) {
        guard let selection = fighter.weaponPose else { return }
        apply(selection)
        // Exported pelvis X/Z are in-place. Source pelvis Y is retained, so
        // jumping is already in the sampled pose and is not added twice here.
        root.position = SCNVector3(Float(fighter.x) / 1000, Float(selection.groundLift), 0)
        root.eulerAngles = SCNVector3(0, -Float(fighter.facing) * .pi / 2, 0)
    }
}
