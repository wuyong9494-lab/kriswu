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
        case wakeupKick, rollForward, rollBack

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
            case .skill1: return ["skill1", "ruthless_advance", "kick", "special_kick", "dash_attack", "heavy", "light1"]
            case .skill2: return ["skill2", "command", "summon", "upper", "special", "skill1", "heavy"]
            case .ultimate: return ["ultimate", "shadow", "super", "finisher", "heavy", "skill1"]
            case .shogunFierce: return ["shogun_fierce", "fierce_reprisal", "shadow_front", "dash_slash", "heavy", "skill1"]
            case .shogunDespotism: return ["shogun_despotism", "despotism", "shadow_back", "weapon_up", "heavy", "skill1"]
            case .inquisitorSpin: return ["inquisitor_spin", "towers_dogma", "spin", "skill1", "heavy"]
            case .midnightRemoval: return ["midnight_removal", "removal", "execute", "heavy", "skill1"]
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

    let hero: DuelGame.Hero
    let model: GLTFModel
    let rightWeapon: GLTFModel?
    let leftWeapon: GLTFModel?
    let config: DuelCascadeurCharacterConfig
    let clipMap: [ClipRole: String]
    let clipStarts: [String: Float]
    let rightHandNodeIndex: Int?
    let leftHandNodeIndex: Int?
    let leftFootNodeIndex: Int?
    let rightFootNodeIndex: Int?

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
            return GLTFModel.Container(data: data, json: json, binaryRange: binaryRange)
        }
        guard let (json, _) = try? GLTFModel.unpack(data) else { return nil }
        return GLTFModel.Container(data: data, json: json, binaryRange: nil)
    }

    private nonisolated static func readPreparedBundle(
        bodyURL: URL,
        rightWeaponURL: URL?,
        leftWeaponURL: URL?,
        configURL: URL?
    ) -> PreparedBundle? {
        guard let bodyContainer = unpackContainer(from: bodyURL) else { return nil }
        let rightContainer = rightWeaponURL.flatMap { unpackContainer(from: $0) }
        let leftContainer = leftWeaponURL.flatMap { unpackContainer(from: $0) }
        let config: DuelCascadeurCharacterConfig
        if let configURL, let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(DuelCascadeurCharacterConfig.self, from: data) {
            config = decoded
        } else {
            config = DuelCascadeurCharacterConfig()
        }
        return PreparedBundle(
            bodyURL: bodyURL,
            bodyContainer: bodyContainer,
            rightWeaponURL: rightWeaponURL,
            rightWeaponContainer: rightContainer,
            leftWeaponURL: leftWeaponURL,
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

    init(url: URL, hero: DuelGame.Hero, rightWeaponURL: URL? = nil, leftWeaponURL: URL? = nil, configURL: URL? = nil,
         bodyContainer: GLTFModel.Container? = nil, rightWeaponContainer: GLTFModel.Container? = nil,
         leftWeaponContainer: GLTFModel.Container? = nil, predecodedConfig: DuelCascadeurCharacterConfig? = nil) throws {
        self.hero = hero
        let loadedModel = try GLTFModel(url: url, validatedContainer: bodyContainer, maxTexture: 1024, physicallyBased: true)
        self.model = loadedModel
        self.rightWeapon = rightWeaponURL.flatMap {
            try? GLTFModel(url: $0, validatedContainer: rightWeaponContainer, maxTexture: 1024, physicallyBased: true)
        }
        self.leftWeapon = leftWeaponURL.flatMap {
            try? GLTFModel(url: $0, validatedContainer: leftWeaponContainer, maxTexture: 1024, physicallyBased: true)
        }
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

        let starts = loadedModel.clips.mapValues { clip in
            clip.channels.compactMap { $0.times.first }.min() ?? 0
        }
        self.clipStarts = starts

        // Build case-insensitive lookup table for clip matching.
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
        self.clipMap = resolved

        let lowerNames = loadedModel.names.map { $0.lowercased() }
        func findBone(_ customName: String?, defaults: [String]) -> Int? {
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

        self.rightHandNodeIndex = findBone(resolvedConfig.rightWeapon?.boneName, defaults: Self.rightHandCandidates)
        self.leftHandNodeIndex = findBone(resolvedConfig.leftWeapon?.boneName, defaults: Self.leftHandCandidates)
        self.leftFootNodeIndex = findBone(nil, defaults: Self.leftFootCandidates)
        self.rightFootNodeIndex = findBone(nil, defaults: Self.rightFootCandidates)
    }

    static func loadBundled(for hero: DuelGame.Hero, bundle: Bundle = .main) -> DuelCascadeurCharacterAsset? {
        if bundle == .main, let cached = assetCache[hero] {
            return cached
        }
        guard let bodyURL = bundledURL(for: hero, bundle: bundle) else { return nil }
        guard let asset = try? DuelCascadeurCharacterAsset(
            url: bodyURL,
            hero: hero,
            rightWeaponURL: bundledWeaponURL(for: hero, leftHand: false, bundle: bundle),
            leftWeaponURL: bundledWeaponURL(for: hero, leftHand: true, bundle: bundle),
            configURL: bundledConfigURL(for: hero, bundle: bundle)
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

        let task = Task<DuelCascadeurCharacterAsset?, Never> {
            let prepared = await Task.detached(priority: .userInitiated) {
                Self.readPreparedBundle(bodyURL: bodyURL, rightWeaponURL: rightURL,
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
                rightWeaponURL: prepared.rightWeaponURL,
                leftWeaponURL: prepared.leftWeaponURL,
                configURL: configURL,
                bodyContainer: prepared.bodyContainer,
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

    /// Sequentially prewarms requested heroes in the background without spiking memory or
    /// blocking the active lobby/battle UI.
    static func prewarm(heroes: [DuelGame.Hero]) {
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

/// Live SceneKit instance of a Cascadeur-rigged fighter with right/left-hand weapon sockets
/// and smooth fixed-tick pose sampling.
@MainActor
final class DuelCascadeurCharacterInstance {
    let asset: DuelCascadeurCharacterAsset
    let instance: GLTFModel.Instance
    let weaponSocketR: SCNNode?
    let weaponSocketL: SCNNode?
    private let rightWeaponInstance: GLTFModel.Instance?
    private let leftWeaponInstance: GLTFModel.Instance?
    private let modelContainer = SCNNode()
    private var pose: GLTFModel.Pose
    private var transition: GLTFModel.Pose
    private var lastKey: String?
    private var changedAt = 0
    private var lastTick = -1
    private var soles: [SCNNode] = []
    private let originalEmission: [Any?]
    private let baseScale: Float
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
        // Grounding is handled by lightweight elliptical floor contact shadow discs; disabling
        // castsShadow avoids a redundant full-mesh GPU shadow-map skinning pass every frame.
        instance.root.enumerateHierarchy { node, _ in node.castsShadow = false }

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

        // Mount right-hand weapon socket onto resolved hand bone.
        if let idx = asset.rightHandNodeIndex, instance.nodes.indices.contains(idx) {
            let socket = SCNNode()
            socket.name = "duel.weapon.socket.r"
            Self.applySocketTransform(asset.config.rightWeapon, to: socket)
            instance.nodes[idx].addChildNode(socket)
            self.weaponSocketR = socket
            if let weaponModel = asset.rightWeapon {
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
            if let weaponModel = asset.leftWeapon {
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

    private func sample(_ role: DuelCascadeurCharacterAsset.ClipRole, progress: Float, into target: inout GLTFModel.Pose) {
        target.reset(from: asset.model.restPose)
        guard let name = asset.clipMap[role], let clip = asset.model.clips[name] else { return }
        let start = asset.clipStarts[name] ?? 0
        let span = max(0, clip.duration - start)
        let clamped = min(1, max(0, progress))
        clip.sample(at: start + span * clamped, into: &target)
    }

    func applyShowroomIdle(progress: Float = 0) {
        sample(.idle, progress: progress, into: &pose)
        for nodeIndex in asset.model.animated {
            instance.nodes[nodeIndex].simdTransform = pose.transform(nodeIndex)
        }
        modelContainer.opacity = 1
    }

    func pose(_ fighter: DuelGame.Fighter, tick: Int, grapple: DuelGame.Grapple?, index: Int,
              phase: DuelGame.Phase, shogun: DuelShogunState?, arenaKit: DuelArenaKitState? = nil, root: SCNNode) {
        if tick < lastTick { lastKey = nil }
        let (key, role, progress, blendTicks) = selectClip(fighter: fighter, tick: tick, index: index, phase: phase, shogun: shogun)

        let hadPose = lastKey != nil
        if lastKey != key {
            transition.reset(from: pose)
            changedAt = tick
        }
        sample(role, progress: progress, into: &pose)
        if hadPose && blendTicks > 0 {
            let elapsed = max(0, tick - changedAt)
            let weight = max(0, 1 - Float(elapsed) / Float(blendTicks))
            pose.blend(toward: transition, weight: weight, nodes: asset.model.animated)
        }
        for nodeIndex in asset.model.animated {
            instance.nodes[nodeIndex].simdTransform = pose.transform(nodeIndex)
        }
        lastKey = key
        lastTick = tick

        root.position = SCNVector3(Float(fighter.x) / 1000, Float(fighter.y) / 1000, 0)
        let baseYaw: Float = (fighter.facing > 0 ? .pi / 2 : -.pi / 2) + facingYawOffsetRad
        var roll: Float = 0
        if fighter.knockdown > 0 && asset.clipMap[.knockdown] == asset.clipMap[.idle] {
            // Fallback visual tip when knockdown clip has not been authored yet.
            roll = -Float(fighter.facing) * .pi / 2
            root.position.y = 0.25
            root.position.x -= Float(fighter.facing) * 0.85
        }
        root.simdOrientation = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1)) *
            simd_quatf(angle: baseYaw, axis: SIMD3<Float>(0, 1, 0))

        let isRolling = fighter.attack?.move.isRoll == true
        if fighter.y == 0 && fighter.knockdown == 0 && !isRolling, let low = soles.map({ $0.worldPosition.y }).min() {
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

        // Dynamic combat feedback emission (hit flash, forms, hyper-armor, charge).
        let overrideEmission: UIColor?
        let weaponEmission: UIColor
        if fighter.flash > 0 {
            overrideEmission = UIColor(red: 0.28, green: 0.12, blue: 0.04, alpha: 1)
            weaponEmission = UIColor.black
        } else if let shogun, shogun.isCataclysm {
            overrideEmission = UIColor(red: 0.35, green: 0.03, blue: 0.10, alpha: 1)
            weaponEmission = UIColor(red: 0.55, green: 0.06, blue: 0.14, alpha: 1)
        } else if let shogun, shogun.isInShadow {
            overrideEmission = UIColor(red: 0.14, green: 0.04, blue: 0.28, alpha: 1)
            weaponEmission = UIColor(red: 0.26, green: 0.06, blue: 0.45, alpha: 1)
        } else if let shogun, shogun.heavyChargeTicks > 0 {
            let ratio = CGFloat(min(1, Float(shogun.heavyChargeTicks) / Float(DuelShogunState.heavyFullChargeTicks)))
            overrideEmission = UIColor(red: 0.30 * ratio, green: 0.18 * ratio, blue: 0.02, alpha: 1)
            weaponEmission = UIColor(red: 0.45, green: 0.26, blue: 0.04, alpha: 1)
        } else if case .inquisitor(let inq) = arenaKit, inq.isInFormOfLight {
            // Kept low: Xu Xiao's white tabard already sits near the bloom threshold.
            overrideEmission = UIColor(red: 0.17, green: 0.12, blue: 0.02, alpha: 1)
            weaponEmission = UIColor(red: 0.65, green: 0.48, blue: 0.08, alpha: 1)
        } else if case .nonna(let nonna) = arenaKit, nonna.isInFlameForm {
            overrideEmission = UIColor(red: 0.44, green: 0.12, blue: 0.03, alpha: 1)
            weaponEmission = UIColor(red: 0.72, green: 0.22, blue: 0.04, alpha: 1)
        } else if case .nonna(let nonna) = arenaKit, nonna.empoweredStrikeReady {
            overrideEmission = UIColor(red: 0.20, green: 0.07, blue: 0.02, alpha: 1)
            weaponEmission = UIColor(red: 0.55, green: 0.24, blue: 0.04, alpha: 1)
        } else if case .midnight(let mid) = arenaKit, mid.isPhasedOut {
            overrideEmission = UIColor(red: 0.20, green: 0.06, blue: 0.44, alpha: 1)
            weaponEmission = UIColor(red: 0.34, green: 0.12, blue: 0.62, alpha: 1)
        } else if case .midnight(let mid) = arenaKit, mid.isInBlinkStance {
            overrideEmission = UIColor(red: 0.12, green: 0.24, blue: 0.38, alpha: 1)
            weaponEmission = UIColor(red: 0.25, green: 0.52, blue: 0.75, alpha: 1)
        } else if case .midnight(let mid) = arenaKit, mid.isInShadowForm {
            overrideEmission = UIColor(red: 0.18, green: 0.04, blue: 0.32, alpha: 1)
            weaponEmission = UIColor(red: 0.45, green: 0.08, blue: 0.68, alpha: 1)
        } else if let attack = fighter.attack {
            let data = DuelGame.data(attack.move, hero: fighter.hero, chargeTicks: attack.chargeTicks)
            if data.armorStart >= 0 && attack.age >= data.armorStart && attack.age < data.armorEnd {
                overrideEmission = UIColor(red: 0.26, green: 0.22, blue: 0.12, alpha: 1)
                weaponEmission = UIColor(red: 0.38, green: 0.30, blue: 0.12, alpha: 1)
            } else {
                overrideEmission = nil
                weaponEmission = UIColor.black
            }
        } else {
            overrideEmission = nil
            weaponEmission = UIColor.black
        }

        for (i, material) in instance.materials.enumerated() {
            material.emission.contents = overrideEmission ?? originalEmission[i]
        }
        for weaponInst in [rightWeaponInstance, leftWeaponInstance].compactMap({ $0 }) {
            for material in weaponInst.materials {
                material.emission.contents = weaponEmission
            }
        }
    }

    /// Live world-space blade base & tip endpoints sampled directly from the animated weapon sockets.
    /// Used by `DuelOriginalVFX` to sweep blade-attached 3D slash ribbons hugging the moving steel.
    func weaponBladeWorldSegments() -> [(base: SIMD3<Float>, tip: SIMD3<Float>)] {
        let span: (baseY: Float, tipY: Float)
        switch asset.hero {
        case .wuYong: span = (0.10, 1.18) // Odachi blade
        case .liu: span = (0.36, 1.05)    // Great Axe head & upper haft
        case .gale: span = (0.12, 1.01)   // Crusader Greatsword blade
        case .ember: span = (0.06, 0.60)  // Dual Ninjato blades
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

    private func selectClip(fighter: DuelGame.Fighter, tick: Int, index: Int,
                            phase: DuelGame.Phase, shogun: DuelShogunState?)
        -> (key: String, role: DuelCascadeurCharacterAsset.ClipRole, progress: Float, blend: Int) {
        if fighter.knockdown > 0 {
            if fighter.knockdown <= 16 {
                return ("getUp", .getUp, Float(16 - fighter.knockdown) / 16, 4)
            }
            return ("knockdown", .knockdown, min(1, Float(43 - fighter.knockdown) / 18), 2)
        }
        if case .matchOver(let winner) = phase {
            return ("result", winner == index ? .victory : .knockdown, 1, 6)
        }
        if fighter.stun > 0 {
            if fighter.guarding { return ("guard", .guardPose, 0.5, 2) }
            let hitRole: DuelCascadeurCharacterAsset.ClipRole
            switch fighter.lastHitZone {
            case .high: hitRole = .hitHead
            case .low: hitRole = .hitLow
            case .mid: hitRole = .hit
            }
            return ("hit.\(hitRole.rawValue)", hitRole, min(1, Float(max(0, 17 - fighter.stun)) / 17), 1)
        }
        if let attack = fighter.attack {
            let data = DuelGame.data(attack.move, hero: fighter.hero, chargeTicks: attack.chargeTicks)
            let progress = Float(attack.age) / Float(max(1, data.duration - 1))
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
            case .midnightRemoval: role = .midnightRemoval
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
            }
            return ("atk.\(attack.move.rawValue).\(tick - attack.age)", role, progress, attack.age < data.startup ? 3 : 0)
        }
        if let shogun, shogun.heavyChargeTicks > 0 {
            let ratio = min(1, Float(shogun.heavyChargeTicks) / Float(DuelShogunState.heavyFullChargeTicks))
            return ("heavyCharge", .heavyCharge, ratio, 3)
        }
        if fighter.y > 0 || fighter.velocityY > 0 {
            let progress = Float(DuelGame.jumpVelocity - fighter.velocityY) /
                Float(2 * DuelGame.jumpVelocity + DuelGame.gravity)
            return ("jump", .jump, progress, 3)
        }
        if fighter.walking {
            let forward = fighter.movementDirection * fighter.facing >= 0
            let role: DuelCascadeurCharacterAsset.ClipRole = forward ? .walk : .backstep
            return (role.rawValue, role, Float(max(0, tick) % 44) / 44, 4)
        }
        // In Shadow Fight 4, standing still auto-blocks from natural combat stance and snaps into
        // the guard parry clip when actively blocking an incoming strike (stun > 0 && guarding).
        if fighter.guarding && fighter.stun > 0 {
            return ("guard", .guardPose, 0.5, 2)
        }
        return ("idle", .idle, Float(max(0, tick) % 90) / 90, 5)
    }
}
