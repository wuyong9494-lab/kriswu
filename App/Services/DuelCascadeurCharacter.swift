import Foundation
import SceneKit
import UIKit
import simd

/// Optional configuration file (`DuelChar_<key>.json`) placed next to a user-authored
/// Cascadeur/Meshy character `.glb` to fine-tune height, facing yaw, and weapon socket
/// offsets without re-exporting from Blender/Cascadeur.
struct DuelCascadeurCharacterConfig: Decodable {
    struct SocketTransform: Decodable {
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
        case idle, walk, backstep, guardPose, jump, hit, knockdown, getUp, victory
        case jab, cross, finisher, heavy, heavyCharge, skill1, skill2, ultimate
        case shogunFierce, shogunDespotism, inquisitorSpin, midnightRemoval

        var aliases: [String] {
            switch self {
            case .idle: return ["idle", "stance", "combat_idle", "stand", "breath"]
            case .walk: return ["walk", "walk_forward", "run", "advance", "move"]
            case .backstep: return ["backstep", "walk_back", "walk_backward", "retreat", "walk"]
            case .guardPose: return ["block", "guard", "defend", "parry", "idle"]
            case .jump: return ["jump", "air", "leap", "idle"]
            case .hit: return ["hit", "hurt", "damage", "stagger", "hit_react"]
            case .knockdown: return ["knockdown", "fall", "down", "death", "ko", "hit"]
            case .getUp: return ["getup", "get_up", "rise", "standup", "wakeup", "idle"]
            case .victory: return ["victory", "win", "taunt", "celebrate", "idle"]
            case .jab: return ["jab", "light", "light1", "attack1", "basic1", "slash1", "attack"]
            case .cross: return ["cross", "light2", "attack2", "basic2", "slash2", "light", "jab"]
            case .finisher: return ["finisher", "light3", "attack3", "combo_finish", "special", "heavy", "light"]
            case .heavy: return ["heavy", "heavy_attack", "overhead", "cleave", "strong", "slash_heavy", "light"]
            case .heavyCharge: return ["heavy_charge", "charge", "windup", "stance_charge", "heavy", "idle"]
            case .skill1: return ["skill1", "ruthless_advance", "kick", "special_kick", "dash_attack", "heavy", "light"]
            case .skill2: return ["skill2", "command", "summon", "upper", "special", "heavy", "light"]
            case .ultimate: return ["ultimate", "shadow", "super", "finisher", "heavy", "light"]
            case .shogunFierce: return ["shogun_fierce", "fierce_reprisal", "shadow_front", "dash_slash", "ultimate", "heavy", "light"]
            case .shogunDespotism: return ["shogun_despotism", "despotism", "shadow_back", "pull_slash", "upper", "ultimate", "heavy", "light"]
            case .inquisitorSpin: return ["inquisitor_spin", "towers_dogma", "spin", "skill2", "heavy", "light"]
            case .midnightRemoval: return ["midnight_removal", "removal", "execute", "ultimate", "heavy", "light"]
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

    init(url: URL, hero: DuelGame.Hero, rightWeaponURL: URL? = nil, leftWeaponURL: URL? = nil, configURL: URL? = nil) throws {
        self.hero = hero
        let loadedModel = try GLTFModel(url: url, maxTexture: 1024, physicallyBased: true)
        self.model = loadedModel
        self.rightWeapon = rightWeaponURL.flatMap { try? GLTFModel(url: $0, maxTexture: 1024, physicallyBased: true) }
        self.leftWeapon = leftWeaponURL.flatMap { try? GLTFModel(url: $0, maxTexture: 1024, physicallyBased: true) }
        let resolvedConfig: DuelCascadeurCharacterConfig
        if let configURL, let data = try? Data(contentsOf: configURL),
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
        let lowerToActual = Dictionary(uniqueKeysWithValues: loadedModel.clips.keys.map { ($0.lowercased(), $0) })
        let sortedKeys = loadedModel.clips.keys.sorted()
        var resolved: [ClipRole: String] = [:]
        for role in ClipRole.allCases {
            var matched: String?
            for alias in role.aliases {
                if let exact = lowerToActual[alias] { matched = exact; break }
                if let partial = sortedKeys.first(where: { $0.lowercased().contains(alias) }) {
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
        guard let bodyURL = bundledURL(for: hero, bundle: bundle) else { return nil }
        return try? DuelCascadeurCharacterAsset(
            url: bodyURL,
            hero: hero,
            rightWeaponURL: bundledWeaponURL(for: hero, leftHand: false, bundle: bundle),
            leftWeaponURL: bundledWeaponURL(for: hero, leftHand: true, bundle: bundle),
            configURL: bundledConfigURL(for: hero, bundle: bundle)
        )
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

        if fighter.y == 0 && fighter.knockdown == 0, let low = soles.map({ $0.worldPosition.y }).min() {
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
            overrideEmission = UIColor(red: 0.38, green: 0.28, blue: 0.05, alpha: 1)
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
            return ("hit", .hit, min(1, Float(max(0, 17 - fighter.stun)) / 17), 1)
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
        if fighter.guarding {
            return ("guard", .guardPose, 0.5, 4)
        }
        if fighter.walking {
            let forward = fighter.movementDirection * fighter.facing >= 0
            let role: DuelCascadeurCharacterAsset.ClipRole = forward ? .walk : .backstep
            return (role.rawValue, role, Float(max(0, tick) % 44) / 44, 4)
        }
        return ("idle", .idle, Float(max(0, tick) % 90) / 90, 5)
    }
}
