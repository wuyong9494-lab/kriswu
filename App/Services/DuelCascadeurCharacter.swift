import Foundation
import SceneKit
import UIKit
import simd

/// Optional configuration file (`DuelChar_<key>.json`) placed next to a user-authored
/// Cascadeur/Meshy character `.glb` to fine-tune height, facing yaw, and weapon socket
/// offsets without re-exporting from Blender/Cascadeur.
struct DuelCascadeurCharacterConfig: Decodable, Sendable {
    struct SocketTransform: Decodable, Sendable {
        var boneName: String?
        var position: [Float]?
        var eulerDeg: [Float]?
        var scale: Float?
    }
    var heightMeters: Float?
    var facingYawOffsetDeg: Float?
    var embeddedWeapons: Bool?
    var alternateFormFile: String?
    var bladeBone: String?
    var bladeBaseOffset: [Float]?
    var bladeTipOffset: [Float]?
    var rightWeapon: SocketTransform?
    var leftWeapon: SocketTransform?
}

/// Universal original-character loader for Meshy + Cascadeur rigged `.glb` characters
/// with independent right/left-hand weapon Socket mounting.
/// Looks for optional local files under `DuelCharacters/` (or main bundle root):
///   - `DuelChar_<key>.glb` (rigged body + head + Cascadeur animation clips)
///   - `DuelWeapon_<key>.glb` (optional standalone right-hand weapon, e.g., Odachi)
///   - `DuelWeaponL_<key>.glb` (optional standalone left-hand weapon)
///   - `DuelChar_<key>.json` (optional socket/scale calibration)
@MainActor
final class DuelCascadeurCharacterAsset {
    enum ClipRole: String, CaseIterable {
        case idle, walk, backstep, guardPose, jump, hit, hitHead, hitLow, knockdown, getUp, victory
        case jab, cross, finisher, heavy, heavyCharge, skill1, skill2, ultimate
        case shogunFierce, shogunDespotism, inquisitorSpin, midnightRemoval
        case weaponForward, weaponUp, weaponDown, weaponBack
        case kick, kickForward, kickUp, kickDown, kickBack, throwMove
        case wakeupKick, rollForward, rollBack, dashForward, dashBack
        case inquisitorLightUp, inquisitorLightForward, inquisitorLightDown
        case emperorTransform, emperorBeastShadowJump
        case legionShadowChain, legionShadowForward, legionShadowDown, legionRevive
        case monkeyAscensionPerch, monkeyAscensionPlunge, monkeyHeavenlyPillar

        var aliases: [String] {
            switch self {
            case .idle: return ["idle", "stance", "combat_idle", "stand", "breath"]
            case .walk: return ["walk", "walk_forward", "run", "advance", "move"]
            case .backstep: return ["backstep", "walk_back", "walk_backward", "retreat", "walk"]
            case .guardPose: return ["guard", "block", "defend", "parry", "idle"]
            case .jump: return ["jump", "air", "leap", "idle"]
            case .hit: return ["hit", "hurt", "damage", "stagger", "hit_react"]
            case .hitHead: return ["hit_head", "head_hit", "hit", "hurt"]
            case .hitLow: return ["hit_low", "low_hit", "hit", "hurt"]
            case .knockdown: return ["knockdown", "fall", "down", "death", "ko", "hit"]
            case .getUp: return ["getup", "get_up", "rise", "standup", "wakeup", "idle"]
            case .victory: return ["victory", "win", "taunt", "celebrate", "idle"]
            case .jab: return ["light1", "jab", "light", "attack1", "basic1", "slash1", "attack"]
            case .cross: return ["light2", "cross", "light1", "attack2", "basic2", "slash2", "light"]
            case .finisher: return ["finisher", "heavy", "light3", "attack3", "combo_finish", "special", "light1"]
            case .heavy: return ["heavy", "heavy_attack", "overhead", "cleave", "strong", "slash_heavy", "light1"]
            case .heavyCharge: return ["heavy_charge", "charge", "windup", "stance_charge", "heavy", "idle"]
            case .weaponForward: return ["weapon_forward", "light1", "skill1", "heavy"]
            case .weaponUp: return ["weapon_up", "upper", "anti_air", "heavy", "light1"]
            case .weaponDown: return ["weapon_down", "low_sweep", "sweep", "light1"]
            case .weaponBack: return ["weapon_back", "spin_slash", "light1", "skill1"]
            case .kick: return ["kick", "front_kick", "skill1", "light1"]
            case .kickForward: return ["kick_forward", "ruthless_advance", "kick", "skill1"]
            case .kickUp: return ["kick_up", "high_kick", "kick", "skill1"]
            case .kickDown: return ["kick_down", "low_kick", "sweep_kick", "kick"]
            case .kickBack: return ["kick_back", "spin_kick", "kick", "skill1"]
            case .throwMove: return ["throw", "grapple", "toss", "heavy", "skill1"]
            case .wakeupKick: return ["wakeup_kick", "kick_down", "kick"]
            case .rollForward: return ["roll_forward", "roll", "walk"]
            case .rollBack: return ["roll_back", "roll", "backstep"]
            case .dashForward: return ["dash_forward", "roll_forward", "walk"]
            case .dashBack: return ["dash_back", "roll_back", "backstep"]
            case .skill1: return ["skill1", "ruthless_advance", "kick", "special_kick", "dash_attack", "heavy", "light1"]
            case .skill2: return ["skill2", "command", "summon", "upper", "special", "skill1", "heavy"]
            case .ultimate: return ["ultimate", "shadow", "super", "finisher", "heavy", "skill1"]
            case .shogunFierce: return ["shogun_fierce", "fierce_reprisal", "shadow_front", "dash_slash", "heavy", "skill1"]
            case .shogunDespotism: return ["shogun_despotism", "despotism", "shadow_back", "weapon_up", "heavy", "skill1"]
            case .inquisitorSpin: return ["inquisitor_spin", "towers_dogma", "spin", "skill1", "heavy"]
            case .inquisitorLightUp: return ["inquisitor_light_up", "weapon_up", "inquisitor_spin", "heavy"]
            case .inquisitorLightForward: return ["inquisitor_light_forward", "weapon_forward", "inquisitor_spin", "heavy"]
            case .inquisitorLightDown: return ["inquisitor_light_down", "weapon_down", "inquisitor_spin", "heavy"]
            case .midnightRemoval: return ["midnight_removal", "removal", "execute", "heavy", "skill1"]
            case .emperorTransform: return ["emperor_transition", "emperor_transform", "transform", "ultimate", "heavy"]
            case .emperorBeastShadowJump: return ["ultimate", "skill2", "heavy", "weapon_forward"]
            case .legionShadowChain: return ["shadow_ranged_chain", "legion_chain", "skill1", "weapon_forward"]
            case .legionShadowForward: return ["skill2", "weapon_forward", "heavy"]
            case .legionShadowDown: return ["ultimate", "weapon_down", "heavy"]
            case .legionRevive: return ["legion_revive", "getup", "victory", "idle"]
            case .monkeyAscensionPerch: return ["monkey_climb_stance", "monkey_climb_pillar", "jump", "idle"]
            case .monkeyAscensionPlunge: return ["monkey_climb_forward", "weapon_forward", "heavy"]
            case .monkeyHeavenlyPillar: return ["monkey_climb_pillar", "ultimate", "heavy"]
            }
        }
    }

    static func resourceKeys(for hero: DuelGame.Hero) -> [String] {
        switch hero {
        case .wuYong: return ["wuYong", "wuyong"]
        case .ember: return ["sunDeng", "sundeng"]
        case .liu: return ["liuQuanwei", "liuquanwei"]
        case .gale: return ["xuXiao", "xuxiao"]
        }
    }

    static func resourceKey(for hero: DuelGame.Hero) -> String {
        resourceKeys(for: hero)[0]
    }

    private static func findBundled(prefix: String, hero: DuelGame.Hero, ext: String, bundle: Bundle) -> URL? {
        for key in resourceKeys(for: hero) {
            let name = prefix + key
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "DuelCharacters") ??
                bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    static func bundledURL(for hero: DuelGame.Hero, bundle: Bundle = .main) -> URL? {
        findBundled(prefix: "DuelChar_", hero: hero, ext: "glb", bundle: bundle)
    }

    static func bundledWeaponURL(for hero: DuelGame.Hero, leftHand: Bool = false, bundle: Bundle = .main) -> URL? {
        findBundled(prefix: leftHand ? "DuelWeaponL_" : "DuelWeapon_", hero: hero, ext: "glb", bundle: bundle)
    }

    static func bundledConfigURL(for hero: DuelGame.Hero, bundle: Bundle = .main) -> URL? {
        findBundled(prefix: "DuelChar_", hero: hero, ext: "json", bundle: bundle)
    }

    static func bundledAlternateURL(named name: String, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: name, withExtension: "glb", subdirectory: "DuelCharacters")
            ?? bundle.url(forResource: name, withExtension: "glb")
    }

    let hero: DuelGame.Hero
    let model: GLTFModel
    let alternateModel: GLTFModel?
    let rightWeapon: GLTFModel?
    let leftWeapon: GLTFModel?
    let config: DuelCascadeurCharacterConfig
    let clipMap: [ClipRole: String]
    let clipStarts: [String: Float]
    let alternateClipMap: [ClipRole: String]
    let alternateClipStarts: [String: Float]
    let rightHandNodeIndex: Int?
    let leftHandNodeIndex: Int?
    let bladeNodeIndex: Int?
    let leftFootNodeIndex: Int?
    let rightFootNodeIndex: Int?
    let alternateLeftFootNodeIndex: Int?
    let alternateRightFootNodeIndex: Int?
    let alternateRightHandNodeIndex: Int?

    static let rightHandCandidates = [
        "weapon_socket_r", "weapon_r", "Weapon_R", "RightHand", "mixamorig:RightHand",
        "hand_r", "hand.R", "Hand_R", "R_Hand", "Bip001 R Hand", "J_Bip_R_Hand", "wrist_r", "Wrist_R"
    ]
    static let leftHandCandidates = [
        "weapon_socket_l", "weapon_l", "Weapon_L", "LeftHand", "mixamorig:LeftHand",
        "hand_l", "hand.L", "Hand_L", "L_Hand", "Bip001 L Hand", "J_Bip_L_Hand", "wrist_l", "Wrist_L"
    ]
    static let leftFootCandidates = [
        "LeftFoot", "mixamorig:LeftFoot", "foot_l", "foot.L", "Foot_L", "L_Foot", "Bip001 L Foot", "J_Bip_L_Foot"
    ]
    static let rightFootCandidates = [
        "RightFoot", "mixamorig:RightFoot", "foot_r", "foot.R", "Foot_R", "R_Foot", "Bip001 R Foot", "J_Bip_R_Foot"
    ]

    private struct PreparedBundle: @unchecked Sendable {
        let bodyURL: URL
        let bodyContainer: GLTFModel.Container
        let alternateURL: URL?
        let alternateContainer: GLTFModel.Container?
        let rightWeaponURL: URL?
        let rightWeaponContainer: GLTFModel.Container?
        let leftWeaponURL: URL?
        let leftWeaponContainer: GLTFModel.Container?
        let config: DuelCascadeurCharacterConfig
    }

    private nonisolated static func unpackContainer(from url: URL) -> GLTFModel.Container? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if data.count >= 12, data.prefix(4) == Data("glTF".utf8) {
            var offset = 12
            var jsonData: Data?
            var binaryRange: Range<Data.Index>?
            while offset + 8 <= data.count {
                let b0 = UInt32(data[data.startIndex + offset])
                let b1 = UInt32(data[data.startIndex + offset + 1]) << 8
                let b2 = UInt32(data[data.startIndex + offset + 2]) << 16
                let b3 = UInt32(data[data.startIndex + offset + 3]) << 24
                let length = Int(b0 | b1 | b2 | b3)
                let t0 = UInt32(data[data.startIndex + offset + 4])
                let t1 = UInt32(data[data.startIndex + offset + 5]) << 8
                let t2 = UInt32(data[data.startIndex + offset + 6]) << 16
                let t3 = UInt32(data[data.startIndex + offset + 7]) << 24
                let type = t0 | t1 | t2 | t3
                let end = min(offset + 8 + length, data.count)
                let range = (data.startIndex + offset + 8)..<(data.startIndex + end)
                if type == 0x4E4F534A { jsonData = data.subdata(in: range) }
                else if type == 0x004E4942 { binaryRange = range }
                offset = end
            }
            guard let jsonData,
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }
            let images = GLTFModel.predecodeEmbeddedImages(
                data: data, json: json, binaryRange: binaryRange, maxTexture: 1024, physicallyBased: true
            )
            return GLTFModel.Container(data: data, json: json, binaryRange: binaryRange, predecodedImages: images)
        }
        guard let (json, _) = try? GLTFModel.unpack(data) else { return nil }
        return GLTFModel.Container(data: data, json: json, binaryRange: nil)
    }

    private nonisolated static func readPreparedBundle(
        bodyURL: URL,
        alternateURL: URL?,
        rightWeaponURL: URL?,
        leftWeaponURL: URL?,
        configURL: URL?
    ) -> PreparedBundle? {
        guard let bodyContainer = unpackContainer(from: bodyURL) else { return nil }
        let config: DuelCascadeurCharacterConfig
        if let configURL, let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(DuelCascadeurCharacterConfig.self, from: data) {
            config = decoded
        } else {
            config = DuelCascadeurCharacterConfig()
        }
        let embedded = config.embeddedWeapons == true
        let rightContainer = embedded ? nil : rightWeaponURL.flatMap { unpackContainer(from: $0) }
        let leftContainer = embedded ? nil : leftWeaponURL.flatMap { unpackContainer(from: $0) }
        let altContainer = alternateURL.flatMap { unpackContainer(from: $0) }
        return PreparedBundle(
            bodyURL: bodyURL,
            bodyContainer: bodyContainer,
            alternateURL: altContainer != nil ? alternateURL : nil,
            alternateContainer: altContainer,
            rightWeaponURL: embedded ? nil : rightWeaponURL,
            rightWeaponContainer: rightContainer,
            leftWeaponURL: embedded ? nil : leftWeaponURL,
            leftWeaponContainer: leftContainer,
            config: config
        )
    }

    private static var assetCache: [DuelGame.Hero: DuelCascadeurCharacterAsset] = [:]
    private static var inflightTasks: [DuelGame.Hero: Task<DuelCascadeurCharacterAsset?, Never>] = [:]
    private static var prewarmChainTask: Task<Void, Never>?

    static func cached(for hero: DuelGame.Hero) -> DuelCascadeurCharacterAsset? {
        assetCache[hero]
    }

    private static func buildClipLookup(for loadedModel: GLTFModel) -> (map: [ClipRole: String], starts: [String: Float]) {
        let starts = loadedModel.clips.mapValues { clip in
            clip.channels.compactMap { $0.times.first }.min() ?? 0
        }
        let lowerToActual = Dictionary(loadedModel.clips.keys.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let sortedKeys = loadedModel.clips.keys.sorted()
        var resolved: [ClipRole: String] = [:]
        for role in ClipRole.allCases {
            var matched: String?
            for alias in role.aliases {
                if let exact = lowerToActual[alias] { matched = exact; break }
                if let partial = sortedKeys.first(where: {
                    let low = $0.lowercased()
                    guard low.contains(alias) else { return false }
                    if role == .hit && (low.contains("hit_head") || low.contains("hit_low")) { return false }
                    return true
                }) {
                    matched = partial; break
                }
            }
            if let matched { resolved[role] = matched }
            else if let fallback = sortedKeys.first { resolved[role] = fallback }
        }
        return (resolved, starts)
    }

    private static func findBone(in loadedModel: GLTFModel, customName: String?, defaults: [String]) -> Int? {
        let lowerNames = loadedModel.names.map { $0.lowercased() }
        let candidates = (customName.map { [$0] } ?? []) + defaults
        for candidate in candidates {
            if let exact = loadedModel.node(named: candidate) { return exact }
        }
        for candidate in candidates {
            let target = candidate.lowercased()
            if let idx = lowerNames.firstIndex(of: target) { return idx }
        }
        for candidate in candidates {
            let target = candidate.lowercased()
            if let idx = lowerNames.firstIndex(where: { $0.hasSuffix(target) || $0.contains(target) }) { return idx }
        }
        return nil
    }

    init(url: URL, hero: DuelGame.Hero, alternateURL: URL? = nil, rightWeaponURL: URL? = nil, leftWeaponURL: URL? = nil, configURL: URL? = nil,
         bodyContainer: GLTFModel.Container? = nil, alternateContainer: GLTFModel.Container? = nil,
         rightWeaponContainer: GLTFModel.Container? = nil, leftWeaponContainer: GLTFModel.Container? = nil,
         predecodedConfig: DuelCascadeurCharacterConfig? = nil) throws {
        self.hero = hero
        let resolvedConfig: DuelCascadeurCharacterConfig
        if let predecodedConfig {
            resolvedConfig = predecodedConfig
        } else if let configURL, let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(DuelCascadeurCharacterConfig.self, from: data) {
            resolvedConfig = decoded
        } else {
            resolvedConfig = DuelCascadeurCharacterConfig()
        }
        self.config = resolvedConfig

        let loadedModel = try GLTFModel(url: url, validatedContainer: bodyContainer, maxTexture: 1024, physicallyBased: true)
        self.model = loadedModel

        let loadedAlt: GLTFModel? = alternateURL.flatMap {
            try? GLTFModel(url: $0, validatedContainer: alternateContainer, maxTexture: 1024, physicallyBased: true)
        }
        self.alternateModel = loadedAlt

        if resolvedConfig.embeddedWeapons == true {
            self.rightWeapon = nil
            self.leftWeapon = nil
        } else {
            self.rightWeapon = rightWeaponURL.flatMap {
                try? GLTFModel(url: $0, validatedContainer: rightWeaponContainer, maxTexture: 1024, physicallyBased: true)
            }
            self.leftWeapon = leftWeaponURL.flatMap {
                try? GLTFModel(url: $0, validatedContainer: leftWeaponContainer, maxTexture: 1024, physicallyBased: true)
            }
        }

        let mainClips = Self.buildClipLookup(for: loadedModel)
        self.clipMap = mainClips.map
        self.clipStarts = mainClips.starts

        if let loadedAlt {
            let altClips = Self.buildClipLookup(for: loadedAlt)
            self.alternateClipMap = altClips.map
            self.alternateClipStarts = altClips.starts
            self.alternateLeftFootNodeIndex = Self.findBone(in: loadedAlt, customName: nil, defaults: Self.leftFootCandidates)
            self.alternateRightFootNodeIndex = Self.findBone(in: loadedAlt, customName: nil, defaults: Self.rightFootCandidates)
            self.alternateRightHandNodeIndex = Self.findBone(in: loadedAlt, customName: "hand_r", defaults: Self.rightHandCandidates)
        } else {
            self.alternateClipMap = [:]
            self.alternateClipStarts = [:]
            self.alternateLeftFootNodeIndex = nil
            self.alternateRightFootNodeIndex = nil
            self.alternateRightHandNodeIndex = nil
        }

        self.rightHandNodeIndex = Self.findBone(in: loadedModel, customName: resolvedConfig.rightWeapon?.boneName, defaults: Self.rightHandCandidates)
        self.leftHandNodeIndex = Self.findBone(in: loadedModel, customName: resolvedConfig.leftWeapon?.boneName, defaults: Self.leftHandCandidates)
        self.bladeNodeIndex = Self.findBone(in: loadedModel, customName: resolvedConfig.bladeBone, defaults: Self.rightHandCandidates)
        self.leftFootNodeIndex = Self.findBone(in: loadedModel, customName: nil, defaults: Self.leftFootCandidates)
        self.rightFootNodeIndex = Self.findBone(in: loadedModel, customName: nil, defaults: Self.rightFootCandidates)
    }

    static func loadBundled(for hero: DuelGame.Hero, bundle: Bundle = .main) -> DuelCascadeurCharacterAsset? {
        if bundle == .main, let cached = assetCache[hero] {
            return cached
        }
        guard let bodyURL = bundledURL(for: hero, bundle: bundle) else { return nil }
        let configURL = bundledConfigURL(for: hero, bundle: bundle)
        let altURL: URL? = {
            guard let configURL, let data = try? Data(contentsOf: configURL),
                  let cfg = try? JSONDecoder().decode(DuelCascadeurCharacterConfig.self, from: data),
                  let altName = cfg.alternateFormFile else { return nil }
            return bundledAlternateURL(named: altName, bundle: bundle)
        }()
        guard let asset = try? DuelCascadeurCharacterAsset(
            url: bodyURL,
            hero: hero,
            alternateURL: altURL,
            rightWeaponURL: bundledWeaponURL(for: hero, leftHand: false, bundle: bundle),
            leftWeaponURL: bundledWeaponURL(for: hero, leftHand: true, bundle: bundle),
            configURL: configURL
        ) else { return nil }
        if bundle == .main {
            assetCache[hero] = asset
        }
        return asset
    }

    /// Reads and unpacks GLB binary/JSON containers off the main thread, then builds and caches
    /// the lightweight SceneKit template on MainActor so lobby & battle share one warm copy.
    static func loadBundledAsync(for hero: DuelGame.Hero, bundle: Bundle = .main) async -> DuelCascadeurCharacterAsset? {
        let isMainBundle = (bundle == .main)
        if isMainBundle, let cached = assetCache[hero] {
            return cached
        }
        if isMainBundle, let existing = inflightTasks[hero] {
            return await existing.value
        }
        guard let bodyURL = bundledURL(for: hero, bundle: bundle) else { return nil }
        let rightURL = bundledWeaponURL(for: hero, leftHand: false, bundle: bundle)
        let leftURL = bundledWeaponURL(for: hero, leftHand: true, bundle: bundle)
        let configURL = bundledConfigURL(for: hero, bundle: bundle)
        let altURL: URL? = {
            guard let configURL, let data = try? Data(contentsOf: configURL),
                  let cfg = try? JSONDecoder().decode(DuelCascadeurCharacterConfig.self, from: data),
                  let altName = cfg.alternateFormFile else { return nil }
            return bundledAlternateURL(named: altName, bundle: bundle)
        }()

        let task = Task<DuelCascadeurCharacterAsset?, Never> {
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.readPreparedBundle(bodyURL: bodyURL, alternateURL: altURL, rightWeaponURL: rightURL,
                                        leftWeaponURL: leftURL, configURL: configURL)
            }.value
            guard let prepared else {
                if isMainBundle { inflightTasks.removeValue(forKey: hero) }
                return nil
            }
            if isMainBundle, let cached = assetCache[hero] {
                inflightTasks.removeValue(forKey: hero)
                return cached
            }
            let asset = try? DuelCascadeurCharacterAsset(
                url: prepared.bodyURL,
                hero: hero,
                alternateURL: prepared.alternateURL,
                rightWeaponURL: prepared.rightWeaponURL,
                leftWeaponURL: prepared.leftWeaponURL,
                configURL: configURL,
                bodyContainer: prepared.bodyContainer,
                alternateContainer: prepared.alternateContainer,
                rightWeaponContainer: prepared.rightWeaponContainer,
                leftWeaponContainer: prepared.leftWeaponContainer,
                predecodedConfig: prepared.config
            )
            if isMainBundle {
                if let asset { assetCache[hero] = asset }
                inflightTasks.removeValue(forKey: hero)
            }
            return asset
        }
        if isMainBundle {
            inflightTasks[hero] = task
        }
        return await task.value
    }

    static func prewarmBundledAsync(for hero: DuelGame.Hero) async {
        _ = await loadBundledAsync(for: hero)
    }

    /// Sequentially prewarms requested heroes and the 3D sanctuary environment in the background
    /// without spiking memory or blocking the active lobby/battle UI.
    static func prewarm(heroes: [DuelGame.Hero]) {
        DuelEnvironmentAssetCache.prewarmAll()
        let missing = heroes.filter { assetCache[$0] == nil }
        guard !missing.isEmpty else { return }
        prewarmChainTask?.cancel()
        prewarmChainTask = Task(priority: .utility) {
            for hero in missing {
                if Task.isCancelled { return }
                _ = await loadBundledAsync(for: hero)
                await Task.yield()
            }
        }
    }
}

/// Shared off-main-thread cache for the sculpted PBR 3D Sanctuary stage, Dark-Lacquer Samurai
/// Retainer prop, and Radiance HDR equirectangular IBL environment light maps.
@MainActor
enum DuelEnvironmentAssetCache {
    private static var stageModel: GLTFModel?
    private static var retainerModel: GLTFModel?
    private static var spiritWolfModel: GLTFModel?
    private static var spiritOwlModel: GLTFModel?
    private static var legionChainModel: GLTFModel?
    private static var monkeyPillarModel: GLTFModel?
    private static var stageTask: Task<GLTFModel?, Never>?
    private static var retainerTask: Task<GLTFModel?, Never>?
    private static var spiritWolfTask: Task<GLTFModel?, Never>?
    private static var spiritOwlTask: Task<GLTFModel?, Never>?
    private static var legionChainTask: Task<GLTFModel?, Never>?
    private static var monkeyPillarTask: Task<GLTFModel?, Never>?

    private struct PreparedGLB: @unchecked Sendable {
        let url: URL
        let container: GLTFModel.Container
    }

    static func bundledResourceURL(name: String, ext: String, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: name, withExtension: ext, subdirectory: "DuelCharacters")
            ?? bundle.url(forResource: name, withExtension: ext)
    }

    static func bundledHDRURL(named name: String, bundle: Bundle = .main) -> URL? {
        bundledResourceURL(name: name, ext: "hdr", bundle: bundle)
    }

    private nonisolated static func unpackGLB(from url: URL) -> PreparedGLB? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if data.count >= 12, data.prefix(4) == Data("glTF".utf8) {
            var offset = 12
            var jsonData: Data?
            var binaryRange: Range<Data.Index>?
            while offset + 8 <= data.count {
                let b0 = UInt32(data[data.startIndex + offset])
                let b1 = UInt32(data[data.startIndex + offset + 1]) << 8
                let b2 = UInt32(data[data.startIndex + offset + 2]) << 16
                let b3 = UInt32(data[data.startIndex + offset + 3]) << 24
                let length = Int(b0 | b1 | b2 | b3)
                let t0 = UInt32(data[data.startIndex + offset + 4])
                let t1 = UInt32(data[data.startIndex + offset + 5]) << 8
                let t2 = UInt32(data[data.startIndex + offset + 6]) << 16
                let t3 = UInt32(data[data.startIndex + offset + 7]) << 24
                let type = t0 | t1 | t2 | t3
                let end = min(offset + 8 + length, data.count)
                let range = (data.startIndex + offset + 8)..<(data.startIndex + end)
                if type == 0x4E4F534A { jsonData = data.subdata(in: range) }
                else if type == 0x004E4942 { binaryRange = range }
                offset = end
            }
            guard let jsonData,
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }
            let images = GLTFModel.predecodeEmbeddedImages(
                data: data, json: json, binaryRange: binaryRange, maxTexture: 1024, physicallyBased: true
            )
            return PreparedGLB(
                url: url,
                container: GLTFModel.Container(data: data, json: json, binaryRange: binaryRange, predecodedImages: images)
            )
        }
        return nil
    }

    static func loadStageAsync() async -> GLTFModel? {
        if let stageModel { return stageModel }
        if let stageTask { return await stageTask.value }
        guard let url = bundledResourceURL(name: "DuelStage_Sanctuary", ext: "glb") else { return nil }
        let task = Task<GLTFModel?, Never> {
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.unpackGLB(from: url)
            }.value
            guard let prepared else { stageTask = nil; return nil }
            if let existing = stageModel { stageTask = nil; return existing }
            let loaded = try? GLTFModel(url: prepared.url, validatedContainer: prepared.container,
                                        maxTexture: 1024, physicallyBased: true)
            stageModel = loaded
            stageTask = nil
            return loaded
        }
        stageTask = task
        return await task.value
    }

    static var preloadedStage: GLTFModel? { stageModel }

    static func cachedStage() -> GLTFModel? {
        if let stageModel { return stageModel }
        guard let url = bundledResourceURL(name: "DuelStage_Sanctuary", ext: "glb"),
              let loaded = try? GLTFModel(url: url, maxTexture: 1024, physicallyBased: true) else { return nil }
        stageModel = loaded
        return loaded
    }

    static func loadRetainerAsync() async -> GLTFModel? {
        if let retainerModel { return retainerModel }
        if let retainerTask { return await retainerTask.value }
        guard let url = bundledResourceURL(name: "DuelProp_ShogunRetainer", ext: "glb") else { return nil }
        let task = Task<GLTFModel?, Never> {
            let prepared = await Task.detached(priority: .utility) {
                Self.unpackGLB(from: url)
            }.value
            guard let prepared else { retainerTask = nil; return nil }
            if let existing = retainerModel { retainerTask = nil; return existing }
            let loaded = try? GLTFModel(url: prepared.url, validatedContainer: prepared.container,
                                        maxTexture: 1024, physicallyBased: true)
            retainerModel = loaded
            retainerTask = nil
            return loaded
        }
        retainerTask = task
        return await task.value
    }

    static func cachedRetainer() -> GLTFModel? {
        if let retainerModel { return retainerModel }
        guard let url = bundledResourceURL(name: "DuelProp_ShogunRetainer", ext: "glb"),
              let loaded = try? GLTFModel(url: url, maxTexture: 1024, physicallyBased: true) else { return nil }
        retainerModel = loaded
        return loaded
    }

    static func loadSpiritWolfAsync() async -> GLTFModel? {
        if let spiritWolfModel { return spiritWolfModel }
        if let spiritWolfTask { return await spiritWolfTask.value }
        guard let url = bundledResourceURL(name: "DuelProp_SpiritWolf", ext: "glb") else { return nil }
        let task = Task<GLTFModel?, Never> {
            let prepared = await Task.detached(priority: .utility) {
                Self.unpackGLB(from: url)
            }.value
            guard let prepared else { spiritWolfTask = nil; return nil }
            if let existing = spiritWolfModel { spiritWolfTask = nil; return existing }
            let loaded = try? GLTFModel(url: prepared.url, validatedContainer: prepared.container,
                                        maxTexture: 1024, physicallyBased: true)
            spiritWolfModel = loaded
            spiritWolfTask = nil
            return loaded
        }
        spiritWolfTask = task
        return await task.value
    }

    static func cachedSpiritWolf() -> GLTFModel? {
        if let spiritWolfModel { return spiritWolfModel }
        guard let url = bundledResourceURL(name: "DuelProp_SpiritWolf", ext: "glb"),
              let loaded = try? GLTFModel(url: url, maxTexture: 1024, physicallyBased: true) else { return nil }
        spiritWolfModel = loaded
        return loaded
    }

    static func loadSpiritOwlAsync() async -> GLTFModel? {
        if let spiritOwlModel { return spiritOwlModel }
        if let spiritOwlTask { return await spiritOwlTask.value }
        guard let url = bundledResourceURL(name: "DuelProp_SpiritOwl", ext: "glb") else { return nil }
        let task = Task<GLTFModel?, Never> {
            let prepared = await Task.detached(priority: .utility) {
                Self.unpackGLB(from: url)
            }.value
            guard let prepared else { spiritOwlTask = nil; return nil }
            if let existing = spiritOwlModel { spiritOwlTask = nil; return existing }
            let loaded = try? GLTFModel(url: prepared.url, validatedContainer: prepared.container,
                                        maxTexture: 1024, physicallyBased: true)
            spiritOwlModel = loaded
            spiritOwlTask = nil
            return loaded
        }
        spiritOwlTask = task
        return await task.value
    }

    static func cachedSpiritOwl() -> GLTFModel? {
        if let spiritOwlModel { return spiritOwlModel }
        guard let url = bundledResourceURL(name: "DuelProp_SpiritOwl", ext: "glb"),
              let loaded = try? GLTFModel(url: url, maxTexture: 1024, physicallyBased: true) else { return nil }
        spiritOwlModel = loaded
        return loaded
    }

    static func loadLegionChainAsync() async -> GLTFModel? {
        if let legionChainModel { return legionChainModel }
        if let legionChainTask { return await legionChainTask.value }
        guard let url = bundledResourceURL(name: "DuelProp_LegionChain", ext: "glb") else { return nil }
        let task = Task<GLTFModel?, Never> {
            let prepared = await Task.detached(priority: .utility) {
                Self.unpackGLB(from: url)
            }.value
            guard let prepared else { legionChainTask = nil; return nil }
            if let existing = legionChainModel { legionChainTask = nil; return existing }
            let loaded = try? GLTFModel(url: prepared.url, validatedContainer: prepared.container,
                                        maxTexture: 1024, physicallyBased: true)
            legionChainModel = loaded
            legionChainTask = nil
            return loaded
        }
        legionChainTask = task
        return await task.value
    }

    static func cachedLegionChain() -> GLTFModel? {
        if let legionChainModel { return legionChainModel }
        guard let url = bundledResourceURL(name: "DuelProp_LegionChain", ext: "glb"),
              let loaded = try? GLTFModel(url: url, maxTexture: 1024, physicallyBased: true) else { return nil }
        legionChainModel = loaded
        return loaded
    }

    static func loadMonkeyPillarAsync() async -> GLTFModel? {
        if let monkeyPillarModel { return monkeyPillarModel }
        if let monkeyPillarTask { return await monkeyPillarTask.value }
        guard let url = bundledResourceURL(name: "DuelProp_MonkeyPillar", ext: "glb") else { return nil }
        let task = Task<GLTFModel?, Never> {
            let prepared = await Task.detached(priority: .utility) {
                Self.unpackGLB(from: url)
            }.value
            guard let prepared else { monkeyPillarTask = nil; return nil }
            if let existing = monkeyPillarModel { monkeyPillarTask = nil; return existing }
            let loaded = try? GLTFModel(url: prepared.url, validatedContainer: prepared.container,
                                        maxTexture: 1024, physicallyBased: true)
            monkeyPillarModel = loaded
            monkeyPillarTask = nil
            return loaded
        }
        monkeyPillarTask = task
        return await task.value
    }

    static func cachedMonkeyPillar() -> GLTFModel? {
        if let monkeyPillarModel { return monkeyPillarModel }
        guard let url = bundledResourceURL(name: "DuelProp_MonkeyPillar", ext: "glb"),
              let loaded = try? GLTFModel(url: url, maxTexture: 1024, physicallyBased: true) else { return nil }
        monkeyPillarModel = loaded
        return loaded
    }

    static func prewarmStageAsync() async {
        _ = await loadStageAsync()
    }

    static func prewarmAll() {
        Task(priority: .utility) {
            _ = await loadStageAsync()
            _ = await loadLegionChainAsync()
            _ = await loadMonkeyPillarAsync()
        }
    }
}

/// Live SceneKit instance of a Cascadeur-rigged fighter with right/left-hand weapon sockets,
/// optional live alternate-form mesh swap (Emperor -> Shadow Beast), and smooth fixed-tick pose sampling.
@MainActor
final class DuelCascadeurCharacterInstance {
    let asset: DuelCascadeurCharacterAsset
    let instance: GLTFModel.Instance
    private let alternateInstance: GLTFModel.Instance?
    let weaponSocketR: SCNNode?
    let weaponSocketL: SCNNode?
    private let rightWeaponInstance: GLTFModel.Instance?
    private let leftWeaponInstance: GLTFModel.Instance?
    private let modelContainer = SCNNode()
    private var pose: GLTFModel.Pose
    private var transition: GLTFModel.Pose
    private var alternatePose: GLTFModel.Pose?
    private var alternateTransition: GLTFModel.Pose?
    private var showingAlternateForm = false
    private var lastKey: String?
    private var changedAt = 0
    private var lastTick = -1
    private var soles: [SCNNode] = []
    private var alternateSoles: [SCNNode] = []
    private let originalEmission: [Any?]
    private let alternateOriginalEmission: [Any?]
    private let baseScale: Float
    private let alternateBaseScale: Float
    private let facingYawOffsetRad: Float

    var root: SCNNode { modelContainer }

    init(_ asset: DuelCascadeurCharacterAsset) {
        self.asset = asset
        self.instance = asset.model.instantiate()
        self.pose = asset.model.restPose
        self.transition = asset.model.restPose
        self.originalEmission = instance.materials.map { $0.emission.contents }
        self.facingYawOffsetRad = (asset.config.facingYawOffsetDeg ?? 0) * .pi / 180

        modelContainer.name = "duel.\(asset.hero.rawValue).cascadeur"
        modelContainer.addChildNode(instance.root)
        // Decimated ~40-50k-tri hero rigs cast crisp real directional sunlight shadows on the courtyard.
        instance.root.enumerateHierarchy { node, _ in node.castsShadow = (node.geometry != nil) }

        // Auto-normalize height to ~1.82m (handles cm-exported FBX/GLB or arbitrary Meshy scale).
        let (minB, maxB) = instance.root.boundingBox
        let rawHeight = maxB.y - minB.y
        let targetHeight = asset.config.heightMeters ?? 1.82
        if rawHeight.isFinite && rawHeight > 0.01 && (rawHeight < 0.7 || rawHeight > 3.2 || asset.config.heightMeters != nil) {
            baseScale = targetHeight / rawHeight
        } else {
            baseScale = 1.0
        }
        instance.root.scale = SCNVector3(baseScale, baseScale, baseScale)

        // Pre-instantiate optional alternate form (Emperor -> Shadow Beast) hidden in container so
        // mid-round form swap is instantaneous with zero shader/buffer hitch!
        if let altModel = asset.alternateModel {
            let altInst = altModel.instantiate()
            altInst.root.name = "duel.\(asset.hero.rawValue).alternate"
            altInst.root.isHidden = true
            altInst.root.enumerateHierarchy { node, _ in node.castsShadow = (node.geometry != nil) }
            let (altMin, altMax) = altInst.root.boundingBox
            let altRawH = altMax.y - altMin.y
            let altTargetH = targetHeight * 1.08
            let altScale: Float = (altRawH.isFinite && altRawH > 0.01) ? (altTargetH / altRawH) : 1.0
            altInst.root.scale = SCNVector3(altScale, altScale, altScale)
            modelContainer.addChildNode(altInst.root)
            self.alternateInstance = altInst
            self.alternatePose = altModel.restPose
            self.alternateTransition = altModel.restPose
            self.alternateOriginalEmission = altInst.materials.map { $0.emission.contents }
            self.alternateBaseScale = altScale
            for idx in [asset.alternateLeftFootNodeIndex, asset.alternateRightFootNodeIndex].compactMap({ $0 })
                where altInst.nodes.indices.contains(idx) {
                let foot = altInst.nodes[idx]
                let marker = SCNNode()
                marker.name = "duel.cascadeur.alt.sole"
                marker.position = SCNVector3(0, -0.04 / max(0.01, altScale), 0)
                foot.addChildNode(marker)
                alternateSoles.append(marker)
            }
        } else {
            self.alternateInstance = nil
            self.alternatePose = nil
            self.alternateTransition = nil
            self.alternateOriginalEmission = []
            self.alternateBaseScale = 1.0
        }

        // Mount right-hand weapon socket onto resolved hand bone.
        if let idx = asset.rightHandNodeIndex, instance.nodes.indices.contains(idx) {
            let socket = SCNNode()
            socket.name = "duel.weapon.socket.r"
            Self.applySocketTransform(asset.config.rightWeapon, to: socket)
            instance.nodes[idx].addChildNode(socket)
            self.weaponSocketR = socket
            if asset.config.embeddedWeapons != true, let weaponModel = asset.rightWeapon {
                let inst = weaponModel.instantiate()
                inst.root.name = "duel.weapon.mesh.r"
                socket.addChildNode(inst.root)
                self.rightWeaponInstance = inst
            } else {
                self.rightWeaponInstance = nil
            }
        } else {
            self.weaponSocketR = nil
            self.rightWeaponInstance = nil
        }

        // Mount optional left-hand weapon socket.
        if let idx = asset.leftHandNodeIndex, instance.nodes.indices.contains(idx) {
            let socket = SCNNode()
            socket.name = "duel.weapon.socket.l"
            Self.applySocketTransform(asset.config.leftWeapon, to: socket)
            instance.nodes[idx].addChildNode(socket)
            self.weaponSocketL = socket
            if asset.config.embeddedWeapons != true, let weaponModel = asset.leftWeapon {
                let inst = weaponModel.instantiate()
                inst.root.name = "duel.weapon.mesh.l"
                socket.addChildNode(inst.root)
                self.leftWeaponInstance = inst
            } else {
                self.leftWeaponInstance = nil
            }
        } else {
            self.weaponSocketL = nil
            self.leftWeaponInstance = nil
        }

        // Foot markers for ground contact clamping.
        for idx in [asset.leftFootNodeIndex, asset.rightFootNodeIndex].compactMap({ $0 })
            where instance.nodes.indices.contains(idx) {
            let foot = instance.nodes[idx]
            let marker = SCNNode()
            marker.name = "duel.cascadeur.sole"
            marker.position = SCNVector3(0, -0.04 / max(0.01, baseScale), 0)
            foot.addChildNode(marker)
            soles.append(marker)
        }
    }

    private static func applySocketTransform(_ cfg: DuelCascadeurCharacterConfig.SocketTransform?, to node: SCNNode) {
        if let pos = cfg?.position, pos.count == 3 {
            node.position = SCNVector3(pos[0], pos[1], pos[2])
        }
        if let deg = cfg?.eulerDeg, deg.count == 3 {
            let k = Float.pi / 180
            node.eulerAngles = SCNVector3(deg[0] * k, deg[1] * k, deg[2] * k)
        }
        if let s = cfg?.scale, s > 0.001 {
            node.scale = SCNVector3(s, s, s)
        }
    }

    private func sample(_ role: DuelCascadeurCharacterAsset.ClipRole, progress: Float, into target: inout GLTFModel.Pose, alternate: Bool = false) {
        if alternate, let altModel = asset.alternateModel {
            target.reset(from: altModel.restPose)
            guard let name = asset.alternateClipMap[role], let clip = altModel.clips[name] else { return }
            let start = asset.alternateClipStarts[name] ?? 0
            let span = max(0, clip.duration - start)
            let clamped = min(1, max(0, progress))
            clip.sample(at: start + span * clamped, into: &target)
            return
        }
        target.reset(from: asset.model.restPose)
        guard let name = asset.clipMap[role], let clip = asset.model.clips[name] else { return }
        let start = asset.clipStarts[name] ?? 0
        let span = max(0, clip.duration - start)
        let clamped = min(1, max(0, progress))
        clip.sample(at: start + span * clamped, into: &target)
    }

    func applyShowroomIdle(progress: Float = 0) {
        showingAlternateForm = false
        instance.root.isHidden = false
        alternateInstance?.root.isHidden = true
        sample(.idle, progress: progress, into: &pose)
        for nodeIndex in asset.model.animated {
            instance.nodes[nodeIndex].simdTransform = pose.transform(nodeIndex)
        }
        modelContainer.opacity = 1
    }

    /// World position of the fighter's left hand (used by Legion King's 3D 28-Link Shadow Chain emitter!).
    func leftHandWorldPosition(fallback: SIMD3<Float>) -> SIMD3<Float> {
        if let idx = asset.leftHandNodeIndex, instance.nodes.indices.contains(idx) {
            let w = instance.nodes[idx].simdWorldPosition
            if w.x.isFinite && w.y.isFinite { return w }
        }
        return fallback
    }

    func pose(_ fighter: DuelGame.Fighter, tick: Int, grapple: DuelGame.Grapple?, index: Int,
              phase: DuelGame.Phase, shogun: DuelShogunState?, arenaKit: DuelArenaKitState? = nil,
              hitStopShiverX: Float = 0, root: SCNNode) {
        if tick < lastTick { lastKey = nil }

        // Emperor -> Shadow Beast live 3D mesh swap!
        let useAlternateForm: Bool
        if alternateInstance != nil, case .emperor(let emp) = arenaKit, emp.isBeastForm {
            useAlternateForm = true
        } else {
            useAlternateForm = false
        }
        if useAlternateForm != showingAlternateForm {
            showingAlternateForm = useAlternateForm
            instance.root.isHidden = useAlternateForm
            alternateInstance?.root.isHidden = !useAlternateForm
            lastKey = nil
        }

        let (key, role, progress, blendTicks) = selectClip(fighter: fighter, tick: tick, index: index, phase: phase, shogun: shogun, arenaKit: arenaKit)

        let hadPose = lastKey != nil
        if useAlternateForm, let altModel = asset.alternateModel, let altInst = alternateInstance,
           var curAltPose = alternatePose, var curAltTrans = alternateTransition {
            if lastKey != key {
                curAltTrans.reset(from: curAltPose)
                changedAt = tick
            }
            sample(role, progress: progress, into: &curAltPose, alternate: true)
            if hadPose && blendTicks > 0 {
                let elapsed = max(0, tick - changedAt)
                let weight = max(0, 1 - Float(elapsed) / Float(blendTicks))
                curAltPose.blend(toward: curAltTrans, weight: weight, nodes: altModel.animated)
            }
            for nodeIndex in altModel.animated {
                altInst.nodes[nodeIndex].simdTransform = curAltPose.transform(nodeIndex)
            }
            alternatePose = curAltPose
            alternateTransition = curAltTrans
        } else {
            if lastKey != key {
                transition.reset(from: pose)
                changedAt = tick
            }
            sample(role, progress: progress, into: &pose, alternate: false)
            if hadPose && blendTicks > 0 {
                let elapsed = max(0, tick - changedAt)
                let weight = max(0, 1 - Float(elapsed) / Float(blendTicks))
                pose.blend(toward: transition, weight: weight, nodes: asset.model.animated)
            }
            for nodeIndex in asset.model.animated {
                instance.nodes[nodeIndex].simdTransform = pose.transform(nodeIndex)
            }
        }
        lastKey = key
        lastTick = tick

        // Grand Inquisitor Form of Light: genuinely soar above the battlefield with subtle divine hover!
        let inquisitorSoaring: Bool
        if case .inquisitor(let inq) = arenaKit, inq.isInFormOfLight, fighter.knockdown == 0 {
            inquisitorSoaring = true
        } else {
            inquisitorSoaring = false
        }
        let soarOffsetY: Float = inquisitorSoaring ? (0.58 + sin(Float(tick) * 0.14) * 0.05) : 0

        // Monkey King Ascension Perch/Plunge/Pillar: SF4 baked clips already carry true vertical pelvis elevation!
        let isMonkeyBakedElevation = asset.config.embeddedWeapons == true &&
            (role == .monkeyAscensionPerch || role == .monkeyAscensionPlunge || role == .monkeyHeavenlyPillar)
        let isMonkeyPerched: Bool = {
            if case .monkeyKing(let mk) = arenaKit { return mk.isPerchedOnPillar }
            return false
        }()

        // Nonna Flame Form (True Shape) OR Emperor Beast fallback (when beast GLB absent): grow to 1.14x stature!
        let nonnaTrueShape: Bool = {
            if case .nonna(let nonna) = arenaKit, nonna.isInFlameForm { return true }
            return false
        }()
        let emperorFallbackBeastScale: Bool = {
            if !useAlternateForm, case .emperor(let emp) = arenaKit, emp.isBeastForm { return true }
            return false
        }()
        let effectiveScale = baseScale * ((nonnaTrueShape || emperorFallbackBeastScale) ? 1.14 : 1.0)
        instance.root.scale = SCNVector3(effectiveScale, effectiveScale, effectiveScale)
        if let altInst = alternateInstance {
            altInst.root.scale = SCNVector3(alternateBaseScale, alternateBaseScale, alternateBaseScale)
        }

        let posY: Float = isMonkeyBakedElevation ? 0 : (Float(fighter.y) / 1000 + soarOffsetY)
        root.position = SCNVector3(Float(fighter.x) / 1000 + hitStopShiverX, posY, 0)
        let baseYaw: Float = (fighter.facing > 0 ? .pi / 2 : -.pi / 2) + facingYawOffsetRad
        var roll: Float = 0
        let activeClipMap = useAlternateForm ? asset.alternateClipMap : asset.clipMap
        if fighter.knockdown > 0 && activeClipMap[.knockdown] == activeClipMap[.idle] {
            // Fallback visual tip when knockdown clip has not been authored yet.
            roll = -Float(fighter.facing) * .pi / 2
            root.position.y = 0.25
            root.position.x -= Float(fighter.facing) * 0.85
        }
        root.simdOrientation = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1)) *
            simd_quatf(angle: baseYaw, axis: SIMD3<Float>(0, 1, 0))

        let isRolling = fighter.attack?.move.isRoll == true
        let activeSoles = useAlternateForm ? alternateSoles : soles
        if fighter.y == 0 && fighter.knockdown == 0 && !isRolling && !inquisitorSoaring && !isMonkeyPerched && !isMonkeyBakedElevation,
           let low = activeSoles.map({ $0.worldPosition.y }).min() {
            root.position.y += max(-0.25, min(0.5, -0.03 - low))
        }

        // Midnight Shadow Shift: phase transparently out of this dimension!
        let isMidnightPhased: Bool
        if case .midnight(let mid) = arenaKit, mid.isPhasedOut {
            isMidnightPhased = true
        } else {
            isMidnightPhased = false
        }
        modelContainer.opacity = isMidnightPhased ? 0.24 : 1.0

        // Dynamic combat feedback emission & SF4 dark-ink shadow silhouette multiply.
        let overrideEmission: UIColor?
        let weaponEmission: UIColor
        var bodyMultiply = UIColor.white
        if fighter.frozenTicks > 0 {
            // Midnight Blink Counter Freeze: crystalline shadow-frost stasis glow!
            bodyMultiply = UIColor(red: 0.68, green: 0.90, blue: 1.0, alpha: 1)
            overrideEmission = UIColor(red: 0.14, green: 0.42, blue: 0.62, alpha: 1)
            weaponEmission = UIColor(red: 0.20, green: 0.56, blue: 0.82, alpha: 1)
        } else if fighter.flash > 0 {
            overrideEmission = fighter.hero == .gale
                ? UIColor(red: 0.14, green: 0.10, blue: 0.05, alpha: 1)
                : UIColor(red: 0.26, green: 0.18, blue: 0.09, alpha: 1)
            weaponEmission = UIColor.black
        } else if let shogun, shogun.isCataclysm {
            bodyMultiply = UIColor(red: 0.42, green: 0.28, blue: 0.30, alpha: 1)
            overrideEmission = UIColor(red: 0.24, green: 0.03, blue: 0.06, alpha: 1)
            weaponEmission = UIColor(red: 0.58, green: 0.08, blue: 0.14, alpha: 1)
        } else if let shogun, shogun.isInShadow {
            // Authentic SF4 Shadow Form: jet-obsidian shadow silhouette with cool ice-cyan rim gleam!
            bodyMultiply = UIColor(red: 0.22, green: 0.27, blue: 0.34, alpha: 1)
            overrideEmission = UIColor(red: 0.05, green: 0.18, blue: 0.28, alpha: 1)
            weaponEmission = UIColor(red: 0.18, green: 0.62, blue: 0.88, alpha: 1)
        } else if let shogun, shogun.heavyChargeTicks > 0 {
            let ratio = CGFloat(min(1, Float(shogun.heavyChargeTicks) / Float(DuelShogunState.heavyFullChargeTicks)))
            overrideEmission = UIColor(red: 0.24 * ratio, green: 0.16 * ratio, blue: 0.03, alpha: 1)
            weaponEmission = UIColor(red: 0.42, green: 0.26, blue: 0.05, alpha: 1)
        } else if case .emperor(let emp) = arenaKit, emp.transformBurstTicks > 0 {
            bodyMultiply = UIColor(red: 0.54, green: 0.34, blue: 0.78, alpha: 1)
            overrideEmission = UIColor(red: 0.24, green: 0.08, blue: 0.46, alpha: 1)
            weaponEmission = UIColor(red: 0.45, green: 0.18, blue: 0.82, alpha: 1)
        } else if case .emperor(let emp) = arenaKit, emp.isBeastForm {
            if !useAlternateForm {
                bodyMultiply = UIColor(red: 0.22, green: 0.20, blue: 0.32, alpha: 1)
            }
            overrideEmission = UIColor(red: 0.05, green: 0.14, blue: 0.24, alpha: 1)
            weaponEmission = UIColor(red: 0.18, green: 0.46, blue: 0.76, alpha: 1)
        } else if case .legionKing(let lk) = arenaKit, lk.reviveAnimTicks > 0 {
            bodyMultiply = UIColor(red: 0.36, green: 0.76, blue: 0.90, alpha: 1)
            overrideEmission = UIColor(red: 0.10, green: 0.34, blue: 0.46, alpha: 1)
            weaponEmission = UIColor(red: 0.22, green: 0.72, blue: 0.92, alpha: 1)
        } else if case .legionKing(let lk) = arenaKit, lk.isShadowEmpowered {
            overrideEmission = UIColor(red: 0.04, green: 0.15, blue: 0.22, alpha: 1)
            weaponEmission = UIColor(red: 0.16, green: 0.56, blue: 0.78, alpha: 1)
        } else if case .monkeyKing(let mk) = arenaKit, mk.hasHeavenlyAura || mk.isPerchedOnPillar {
            overrideEmission = UIColor(red: 0.20, green: 0.13, blue: 0.02, alpha: 1)
            weaponEmission = UIColor(red: 0.62, green: 0.44, blue: 0.08, alpha: 1)
        } else if case .inquisitor(let inq) = arenaKit, inq.isInFormOfLight {
            overrideEmission = UIColor(red: 0.18, green: 0.13, blue: 0.03, alpha: 1)
            weaponEmission = UIColor(red: 0.58, green: 0.42, blue: 0.09, alpha: 1)
        } else if case .nonna(let nonna) = arenaKit, nonna.isInFlameForm {
            overrideEmission = UIColor(red: 0.36, green: 0.11, blue: 0.02, alpha: 1)
            weaponEmission = UIColor(red: 0.68, green: 0.22, blue: 0.04, alpha: 1)
        } else if case .nonna(let nonna) = arenaKit, nonna.empoweredStrikeReady {
            overrideEmission = UIColor(red: 0.18, green: 0.07, blue: 0.02, alpha: 1)
            weaponEmission = UIColor(red: 0.48, green: 0.22, blue: 0.04, alpha: 1)
        } else if case .midnight(let mid) = arenaKit, mid.isPhasedOut {
            bodyMultiply = UIColor(red: 0.28, green: 0.36, blue: 0.46, alpha: 1)
            overrideEmission = UIColor(red: 0.08, green: 0.24, blue: 0.38, alpha: 1)
            weaponEmission = UIColor(red: 0.20, green: 0.56, blue: 0.78, alpha: 1)
        } else if case .midnight(let mid) = arenaKit, mid.isInBlinkStance {
            overrideEmission = UIColor(red: 0.08, green: 0.20, blue: 0.32, alpha: 1)
            weaponEmission = UIColor(red: 0.20, green: 0.52, blue: 0.74, alpha: 1)
        } else if case .midnight(let mid) = arenaKit, mid.isInShadowForm {
            bodyMultiply = UIColor(red: 0.22, green: 0.27, blue: 0.34, alpha: 1)
            overrideEmission = UIColor(red: 0.05, green: 0.20, blue: 0.32, alpha: 1)
            weaponEmission = UIColor(red: 0.22, green: 0.70, blue: 0.96, alpha: 1)
        } else if let attack = fighter.attack {
            let data = DuelGame.data(attack.move, hero: fighter.hero, chargeTicks: attack.chargeTicks, ruleset: .shadowArena)
            if data.armorStart >= 0 && attack.age >= data.armorStart && attack.age < data.armorEnd {
                overrideEmission = UIColor(red: 0.22, green: 0.18, blue: 0.09, alpha: 1)
                weaponEmission = UIColor(red: 0.34, green: 0.26, blue: 0.10, alpha: 1)
            } else {
                overrideEmission = nil
                weaponEmission = UIColor.black
            }
        } else {
            overrideEmission = nil
            weaponEmission = UIColor.black
        }

        if useAlternateForm, let altInst = alternateInstance {
            for (i, material) in altInst.materials.enumerated() {
                material.emission.contents = overrideEmission ?? (i < alternateOriginalEmission.count ? alternateOriginalEmission[i] : UIColor.black)
                material.multiply.contents = bodyMultiply
            }
        } else {
            for (i, material) in instance.materials.enumerated() {
                material.emission.contents = overrideEmission ?? originalEmission[i]
                material.multiply.contents = bodyMultiply
            }
            for weaponInst in [rightWeaponInstance, leftWeaponInstance].compactMap({ $0 }) {
                for material in weaponInst.materials {
                    material.emission.contents = weaponEmission
                }
            }
        }
    }

    /// Live world-space blade base & tip endpoints sampled directly from the animated weapon sockets
    /// or embedded SF4 weapon/claw bones. Used by `DuelOriginalVFX` to sweep 3D slash ribbons.
    func weaponBladeWorldSegments() -> [(base: SIMD3<Float>, tip: SIMD3<Float>)] {
        if showingAlternateForm, let altInst = alternateInstance,
           let handIdx = asset.alternateRightHandNodeIndex, altInst.nodes.indices.contains(handIdx) {
            let m = altInst.nodes[handIdx].simdWorldTransform
            let base4 = m * SIMD4<Float>(0, 0, -0.05, 1)
            let tip4 = m * SIMD4<Float>(0, 0, 0.42, 1)
            let base = SIMD3<Float>(base4.x, base4.y, base4.z)
            let tip = SIMD3<Float>(tip4.x, tip4.y, tip4.z)
            if base.x.isFinite && tip.x.isFinite && simd_distance(base, tip) > 0.08 {
                return [(base, tip)]
            }
        }
        if asset.config.embeddedWeapons == true,
           let boneIdx = asset.bladeNodeIndex ?? asset.rightHandNodeIndex,
           instance.nodes.indices.contains(boneIdx) {
            let m = instance.nodes[boneIdx].simdWorldTransform
            let bo = asset.config.bladeBaseOffset ?? [0, 0, -0.10]
            let to = asset.config.bladeTipOffset ?? [0, 0, 0.90]
            if bo.count == 3 && to.count == 3 {
                let base4 = m * SIMD4<Float>(bo[0], bo[1], bo[2], 1)
                let tip4 = m * SIMD4<Float>(to[0], to[1], to[2], 1)
                let base = SIMD3<Float>(base4.x, base4.y, base4.z)
                let tip = SIMD3<Float>(tip4.x, tip4.y, tip4.z)
                if base.x.isFinite && tip.x.isFinite && simd_distance(base, tip) > 0.08 {
                    return [(base, tip)]
                }
            }
        }
        let span: (baseY: Float, tipY: Float)
        switch asset.hero {
        case .wuYong: span = (0.10, 1.18) // Odachi blade
        case .liu: span = (0.10, 0.72)    // Emperor claws / Axe fallback
        case .gale: span = (0.12, 1.24)   // Legion King Greatsword blade
        case .ember: span = (0.06, 1.12)  // Jingu Staff
        }
        var out: [(base: SIMD3<Float>, tip: SIMD3<Float>)] = []
        if let r = weaponSocketR, rightWeaponInstance != nil {
            let m = r.simdWorldTransform
            let base4 = m * SIMD4<Float>(0, span.baseY, 0, 1)
            let tip4 = m * SIMD4<Float>(0, span.tipY, 0, 1)
            let base = SIMD3<Float>(base4.x, base4.y, base4.z)
            let tip = SIMD3<Float>(tip4.x, tip4.y, tip4.z)
            if base.x.isFinite && tip.x.isFinite && simd_distance(base, tip) > 0.08 {
                out.append((base, tip))
            }
        }
        if let l = weaponSocketL, leftWeaponInstance != nil {
            let m = l.simdWorldTransform
            let base4 = m * SIMD4<Float>(0, span.baseY, 0, 1)
            let tip4 = m * SIMD4<Float>(0, span.tipY, 0, 1)
            let base = SIMD3<Float>(base4.x, base4.y, base4.z)
            let tip = SIMD3<Float>(tip4.x, tip4.y, tip4.z)
            if base.x.isFinite && tip.x.isFinite && simd_distance(base, tip) > 0.08 {
                out.append((base, tip))
            }
        }
        return out
    }

    /// Wu Yong's GLB clips were exported at Blender's 24fps timeline (1.25x longer timestamps than 30fps SF4 native).
    /// All other three heroes are natively 30fps. Dividing by `sourceFPSCorrection` restores exact 1.0x SF4 timing.
    private var sourceFPSCorrection: Float {
        asset.hero == .wuYong ? 1.25 : 1.0
    }

    private func naturalDurationSeconds(for role: DuelCascadeurCharacterAsset.ClipRole, alternate: Bool = false) -> Float {
        if alternate, let altModel = asset.alternateModel,
           let name = asset.alternateClipMap[role], let clip = altModel.clips[name] {
            let start = asset.alternateClipStarts[name] ?? 0
            return max(0.25, (clip.duration - start) / sourceFPSCorrection)
        }
        guard let name = asset.clipMap[role], let clip = asset.model.clips[name] else { return 1.5 }
        let start = asset.clipStarts[name] ?? 0
        return max(0.25, (clip.duration - start) / sourceFPSCorrection)
    }

    /// True 1.0x looping period (in 60Hz ticks) for showroom & combat idle breathing.
    var idlePeriodTicks: Int {
        max(60, Int((naturalDurationSeconds(for: .idle, alternate: showingAlternateForm) * 60.0).rounded()))
    }

    private func loopProgress(for role: DuelCascadeurCharacterAsset.ClipRole, tick: Int, alternate: Bool) -> Float {
        let naturalSec = naturalDurationSeconds(for: role, alternate: alternate)
        let periodTicks = max(24, Int((naturalSec * 60.0).rounded()))
        return Float(max(0, tick) % periodTicks) / Float(periodTicks)
    }

    /// Samples combat & reaction clips at true 1.0x human martial-arts speed instead of squashing
    /// 1.5s–9.9s SF4 clips into 0.4s (which previously caused 2x–6x fast-forward playback).
    private func realTimeProgress(
        for role: DuelCascadeurCharacterAsset.ClipRole,
        elapsedTicks: Int,
        totalTicks: Int,
        alternate: Bool,
        maxRate: Float = 1.15
    ) -> Float {
        let naturalSec = naturalDurationSeconds(for: role, alternate: alternate)
        let moveSec = max(0.18, Float(max(1, totalTicks)) / 60.0)
        // Allow gentle rate adaptation [0.88x ... maxRate] so short clips finish cleanly while
        // long multi-phase or long-tail SF4 clips NEVER exceed ~1.15x natural speed!
        let desiredRate = naturalSec / moveSec
        let effectiveRate = min(maxRate, max(0.88, desiredRate))
        let elapsedSec = Float(max(0, elapsedTicks)) / 60.0
        return min(1.0, (elapsedSec * effectiveRate) / naturalSec)
    }

    private func selectClip(fighter: DuelGame.Fighter, tick: Int, index: Int,
                            phase: DuelGame.Phase, shogun: DuelShogunState?,
                            arenaKit: DuelArenaKitState? = nil)
        -> (key: String, role: DuelCascadeurCharacterAsset.ClipRole, progress: Float, blend: Int) {
        let alt = showingAlternateForm
        if fighter.knockdown > 0 {
            if fighter.knockdown <= 24 {
                let elapsed = max(0, 24 - fighter.knockdown)
                let p = realTimeProgress(for: .getUp, elapsedTicks: elapsed, totalTicks: 24, alternate: alt, maxRate: 1.25)
                return ("getUp", .getUp, p, 5)
            }
            let elapsed = max(0, 54 - fighter.knockdown)
            let p = realTimeProgress(for: .knockdown, elapsedTicks: elapsed, totalTicks: 30, alternate: alt, maxRate: 1.20)
            return ("knockdown", .knockdown, p, 2)
        }
        if case .matchOver(let winner) = phase {
            let role: DuelCascadeurCharacterAsset.ClipRole = winner == index ? .victory : .knockdown
            let p: Float = winner == index ? loopProgress(for: .victory, tick: tick, alternate: alt) : 1.0
            return ("result", role, p, 6)
        }
        if case .legionKing(let lk) = arenaKit, lk.reviveAnimTicks > 0 {
            let elapsed = max(0, DuelLegionKingState.darkIncarnationInvulnerableTicks - lk.reviveAnimTicks)
            let p = realTimeProgress(for: .legionRevive, elapsedTicks: elapsed,
                                     totalTicks: DuelLegionKingState.darkIncarnationInvulnerableTicks,
                                     alternate: alt, maxRate: 1.20)
            return ("legionRevive", .legionRevive, p, 3)
        }
        if fighter.frozenTicks > 0 {
            return ("frozen", .hit, 0.24, 0)
        }
        if fighter.stun > 0 {
            if fighter.guarding { return ("guard", .guardPose, 0.42, 2) }
            let hitRole: DuelCascadeurCharacterAsset.ClipRole
            switch fighter.lastHitZone {
            case .high: hitRole = .hitHead
            case .low: hitRole = .hitLow
            case .mid: hitRole = .hit
            }
            let elapsed = max(0, 22 - fighter.stun)
            let p = realTimeProgress(for: hitRole, elapsedTicks: elapsed, totalTicks: 22, alternate: alt, maxRate: 1.15)
            // Instant 0-tick blend snap on impact so head/torso recoil whips back immediately on Frame 1!
            return ("hit.\(hitRole.rawValue)", hitRole, p, 0)
        }
        if case .monkeyKing(let mk) = arenaKit, mk.isPerchedOnPillar, fighter.attack == nil {
            let elapsed = max(0, DuelMonkeyKingState.ascensionMaxTicks - mk.ascensionTicks)
            return ("monkeyPerch", .monkeyAscensionPerch, loopProgress(for: .monkeyAscensionPerch, tick: elapsed, alternate: alt), 3)
        }
        if let attack = fighter.attack {
            let data = DuelGame.data(attack.move, hero: fighter.hero, chargeTicks: attack.chargeTicks, ruleset: .shadowArena)
            let role: DuelCascadeurCharacterAsset.ClipRole
            switch attack.move {
            case .jab: role = .jab
            case .cross: role = .cross
            case .finisher: role = .finisher
            case .heavy: role = .heavy
            case .skill1: role = .skill1
            case .skill2: role = .skill2
            case .ultimate: role = .ultimate
            case .shogunFierceReprisal: role = .shogunFierce
            case .shogunDespotism: role = .shogunDespotism
            case .inquisitorLightSpin: role = .inquisitorSpin
            case .inquisitorLightUp: role = .inquisitorLightUp
            case .inquisitorLightForward: role = .inquisitorLightForward
            case .inquisitorLightDown: role = .inquisitorLightDown
            case .midnightRemoval: role = .midnightRemoval
            case .emperorTransform: role = .emperorTransform
            case .emperorBeastShadowJump: role = .emperorBeastShadowJump
            case .legionShadowChain: role = .legionShadowChain
            case .legionShadowForward: role = .legionShadowForward
            case .legionShadowDown: role = .legionShadowDown
            case .monkeyAscensionPlunge: role = .monkeyAscensionPlunge
            case .monkeyHeavenlyPillar: role = .monkeyHeavenlyPillar
            case .weaponForward: role = .weaponForward
            case .weaponUp: role = .weaponUp
            case .weaponDown: role = .weaponDown
            case .weaponBack: role = .weaponBack
            case .kick: role = .kick
            case .kickForward: role = .kickForward
            case .kickUp: role = .kickUp
            case .kickDown: role = .kickDown
            case .kickBack: role = .kickBack
            case .throwForward, .throwBack: role = .throwMove
            case .wakeupKick: role = .wakeupKick
            case .rollForward: role = .rollForward
            case .rollBack: role = .rollBack
            case .dashForward: role = .dashForward
            case .dashBack: role = .dashBack
            }
            let maxRate: Float = (attack.move.isRoll || attack.move.isDash) ? 1.25 : 1.15
            let progress = realTimeProgress(for: role, elapsedTicks: attack.age,
                                            totalTicks: max(1, data.duration),
                                            alternate: alt, maxRate: maxRate)
            return ("atk.\(attack.move.rawValue).\(tick - attack.age)", role, progress, attack.age < data.startup ? 3 : 0)
        }
        if let shogun, shogun.heavyChargeTicks > 0 {
            let p = realTimeProgress(for: .heavyCharge, elapsedTicks: shogun.heavyChargeTicks,
                                     totalTicks: DuelShogunState.heavyFullChargeTicks, alternate: alt, maxRate: 1.05)
            return ("heavyCharge", .heavyCharge, p, 4)
        }
        if fighter.y > 0 || fighter.velocityY > 0 {
            let progress = Float(DuelGame.jumpVelocity - fighter.velocityY) /
                Float(2 * DuelGame.jumpVelocity + DuelGame.gravity)
            return ("jump", .jump, min(1, max(0, progress)), 3)
        }
        if fighter.walking {
            let forward = fighter.movementDirection * fighter.facing >= 0
            let role: DuelCascadeurCharacterAsset.ClipRole = forward ? .walk : .backstep
            return (role.rawValue, role, loopProgress(for: role, tick: tick, alternate: alt), 5)
        }
        // In Shadow Fight 4, standing still auto-blocks from natural combat stance and snaps into
        // the guard parry clip when actively blocking an incoming strike (stun > 0 && guarding).
        if fighter.guarding && fighter.stun > 0 {
            return ("guard", .guardPose, 0.42, 2)
        }
        return ("idle", .idle, loopProgress(for: .idle, tick: tick, alternate: alt), 7)
    }
}
