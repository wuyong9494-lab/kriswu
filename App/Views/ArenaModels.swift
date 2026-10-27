import Foundation
import Metal
import SceneKit
import SwiftUI
import UIKit
import simd

// 乱斗的 3D 素材：角色、武器、场外的树这些模型从 App 里读（KayKit 的免费素材，CC0 授权，见 App/Arena3D/KayKit-LICENSE.txt）。
// 以后换成买的素材：同名文件放进私有仓库，打包时覆盖这里的就行

/// 乱斗的颜色（3D 画面、上面那排比分、摇杆共用）
enum ArenaPalette {
    static let blue = UIColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1)
    static let red = UIColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1)
    static let gold = UIColor(red: 1.0, green: 0.82, blue: 0.22, alpha: 1)
    static let grass = UIColor(red: 0.45, green: 0.67, blue: 0.26, alpha: 1)
    static let poison = UIColor(red: 0.28, green: 0.80, blue: 0.36, alpha: 1)
    /// 自己这边、对面打出来的子弹
    static let allyShot = UIColor(red: 0.55, green: 0.82, blue: 1.0, alpha: 1)
    static let enemyShot = UIColor(red: 1.0, green: 0.48, blue: 0.38, alpha: 1)
    /// 自己的血条（绿）、弹药（橙）
    static let mine = UIColor(red: 0.36, green: 0.86, blue: 0.22, alpha: 1)
    static let ammo = UIColor(red: 1.0, green: 0.62, blue: 0.10, alpha: 1)
    /// 头顶的名字：自己、队友、对面
    static let myName = UIColor(red: 0.62, green: 1.0, blue: 0.38, alpha: 1)
    static let allyName = UIColor(red: 0.50, green: 0.80, blue: 1.0, alpha: 1)
    static let enemyName = UIColor(red: 1.0, green: 0.47, blue: 0.43, alpha: 1)
}

/// 每个角色的样子：用哪个模型、拿什么、怎么动
struct BrawlerLook {
    /// 一个动作：放模型里哪段动画的哪一截、放多久
    struct Move {
        let clip: String
        var from: Float = 0
        var to: Float = 1
        let seconds: Float
    }

    /// 挂到手上的武器（骷髅的武器是单独的模型）：哪个文件、挂在哪根骨头上、相对那根骨头的位置和朝向
    struct Weapon {
        let file: String
        let bone: String
        let position: SIMD3<Float>
        let rotation: simd_quatf
    }

    let file: String
    /// 模型自带、这个角色不用的武器和配件
    let hidden: [String]
    let idle: String
    let run: String
    let attack: Move
    let special: Move
    var weapons: [Weapon] = []

    static let death = Move(clip: "Death_A", seconds: 0.8)
    static let cheer = "Cheer"

    static func of(_ brawler: Brawler) -> BrawlerLook {
        switch brawler {
        case .knight:
            return BrawlerLook(file: "Knight.glb", hidden: ["1H_Sword_Offhand", "Rectangle_Shield", "Round_Shield", "Spike_Shield", "2H_Sword"],
                               idle: "Idle", run: "Running_A",
                               attack: Move(clip: "1H_Melee_Attack_Slice_Horizontal", from: 0.2, to: 0.75, seconds: 0.42),
                               special: Move(clip: "1H_Melee_Attack_Stab", from: 0.15, to: 0.7, seconds: 0.5))
        case .ranger:
            return BrawlerLook(file: "Rogue.glb", hidden: ["Knife_Offhand", "2H_Crossbow", "Knife", "Throwable"],
                               idle: "Idle", run: "Running_A",
                               attack: Move(clip: "1H_Ranged_Shoot", from: 0.1, to: 0.7, seconds: 0.4),
                               special: Move(clip: "1H_Ranged_Shoot", from: 0, to: 0.8, seconds: 0.6))
        case .barbarian:
            return BrawlerLook(file: "Barbarian.glb", hidden: ["1H_Axe_Offhand", "Barbarian_Round_Shield", "1H_Axe", "Mug"],
                               idle: "2H_Melee_Idle", run: "Running_A",
                               attack: Move(clip: "2H_Melee_Attack_Chop", from: 0.25, to: 0.7, seconds: 0.4),
                               special: Move(clip: "Jump_Full_Short", from: 0.1, to: 0.9, seconds: Float(Fighter.Leap.duration)))
        case .mage:
            return BrawlerLook(file: "Mage.glb", hidden: ["Spellbook", "Spellbook_open", "1H_Wand"],
                               idle: "Idle", run: "Running_A",
                               attack: Move(clip: "Spellcast_Shoot", from: 0.15, to: 0.8, seconds: 0.5),
                               special: Move(clip: "Spellcast_Raise", from: 0.2, to: 0.7, seconds: 0.8))
        case .assassin:
            return BrawlerLook(file: "Rogue_Hooded.glb", hidden: ["1H_Crossbow", "2H_Crossbow", "Throwable"],
                               idle: "Idle", run: "Running_A",
                               attack: Move(clip: "Throw", from: 0.25, to: 0.7, seconds: 0.4),
                               special: Move(clip: "Dualwield_Melee_Attack_Slice", from: 0.1, to: 0.75, seconds: 0.5))
        case .guardian:
            return BrawlerLook(file: "Skeleton_Warrior.glb", hidden: [], idle: "Idle", run: "Running_A",
                               attack: Move(clip: "1H_Melee_Attack_Chop", from: 0.2, to: 0.75, seconds: 0.42),
                               special: Move(clip: "Block", from: 0, to: 0.6, seconds: 0.6),
                               weapons: [Weapon(file: "Skeleton_Axe.gltf", bone: "handslot.r", position: SIMD3(0, 0.033, 0), rotation: Self.turned),
                                         Weapon(file: "Skeleton_Shield_Large_A.gltf", bone: "handslot.l", position: SIMD3(0, 0.017, 0.156),
                                                rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))])
        case .necromancer:
            return BrawlerLook(file: "Skeleton_Mage.glb", hidden: [], idle: "Idle", run: "Running_A",
                               attack: Move(clip: "Spellcast_Shoot", from: 0.15, to: 0.8, seconds: 0.5),
                               special: Move(clip: "Spellcast_Summon", from: 0.1, to: 0.35, seconds: 0.9),
                               weapons: [Weapon(file: "Skeleton_Staff.gltf", bone: "handslot.r", position: .zero, rotation: Self.turned)])
        case .shade:
            return BrawlerLook(file: "Skeleton_Rogue.glb", hidden: [], idle: "Idle", run: "Running_A",
                               attack: Move(clip: "1H_Ranged_Shoot", from: 0.1, to: 0.7, seconds: 0.4),
                               special: Move(clip: "Dodge_Forward", seconds: 0.4),
                               weapons: [Weapon(file: "Skeleton_Crossbow.gltf", bone: "handslot.r", position: SIMD3(-0.105, -0.01, 0),
                                                rotation: simd_quatf(ix: 0, iy: 0.7071068, iz: 0, r: 0.7071068))])
        case .summoner:
            return BrawlerLook(file: "Skeleton_Minion.glb", hidden: [], idle: "Idle", run: "Running_A",
                               attack: Move(clip: "Throw", from: 0.25, to: 0.7, seconds: 0.4),
                               special: Move(clip: "Use_Item", from: 0.1, to: 0.6, seconds: 0.7),
                               weapons: [Weapon(file: "Skeleton_Blade.gltf", bone: "handslot.r", position: SIMD3(0, 0.033, 0), rotation: Self.turned)])
        }
    }

    /// 绕竖轴转半圈（武器挂在右手上的朝向，和冒险者模型里自带的一样）
    private static let turned = simd_quatf(ix: 0, iy: -1, iz: 0, r: 0)

    /// 要从模型里读的动画
    var clips: Set<String> { [idle, run, attack.clip, special.clip, Self.death.clip, Self.cheer] }
}

/// 乱斗用到的 3D 模型：第一次用时从 App 里读（读不出来就返回 nil，画面用简单的形状代替，照样能玩），之后一直留着
final class ArenaModels: @unchecked Sendable {
    static let shared = ArenaModels()

    /// 骷髅的武器，场地外的树、石头、旗子（墙的箱子、桶是代码画的，见 ArenaArt）
    static let props = ["Skeleton_Axe.gltf", "Skeleton_Shield_Large_A.gltf", "Skeleton_Staff.gltf", "Skeleton_Crossbow.gltf", "Skeleton_Blade.gltf",
                        "trees_A_small.gltf", "trees_A_medium.gltf", "trees_A_large.gltf",
                        "trees_B_small.gltf", "trees_B_medium.gltf", "trees_B_large.gltf",
                        "rock_single_A.gltf", "rock_single_B.gltf", "rock_single_C.gltf",
                        "flag_blue.gltf", "flag_red.gltf"]

    private let lock = NSLock()
    private var models: [String: GLTFModel] = [:]
    private var missing: Set<String> = []

    func character(_ brawler: Brawler) -> GLTFModel? {
        let look = BrawlerLook.of(brawler)
        return model(look.file, animations: look.clips)
    }

    func prop(_ file: String) -> GLTFModel? {
        model(file, animations: [])
    }

    private func model(_ file: String, animations: Set<String>) -> GLTFModel? {
        lock.lock()
        defer { lock.unlock() }
        if let model = models[file] { return model }
        guard !missing.contains(file) else { return nil }
        let name = (file as NSString).deletingPathExtension
        let type = (file as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: type),
              let model = try? GLTFModel(url: url, animations: animations) else {
            missing.insert(file)
            return nil
        }
        models[file] = model
        return model
    }

    /// 在后台把全部模型读好（进乱斗首页时就开始，开打时不用等）
    static func loadAll() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                for brawler in Brawler.allCases { _ = shared.character(brawler) }
                for file in props { _ = shared.prop(file) }
                continuation.resume()
            }
        }
    }
}

/// 选角色时的头像：用 3D 模型摆个姿势现画（画好留着）；模型读不出来就显示表情
@MainActor
final class ArenaPortraits: ObservableObject {
    static let shared = ArenaPortraits()
    @Published private(set) var images: [Brawler: UIImage] = [:]
    private var preparing = false

    func prepare() async {
        guard !preparing, images.count < Brawler.allCases.count else { return }
        preparing = true
        await ArenaModels.loadAll()
        for brawler in Brawler.allCases where images[brawler] == nil {
            if let image = render(brawler) { images[brawler] = image }
        }
        preparing = false
    }

    private func render(_ brawler: Brawler) -> UIImage? {
        guard let device = MTLCreateSystemDefaultDevice(), ArenaModels.shared.character(brawler) != nil else { return nil }
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        let avatar = ArenaAvatar(brawler: brawler, color: .clear, isMe: false, decorated: false)
        avatar.hold(BrawlerLook.of(brawler).idle, at: 0.3)
        avatar.turn(to: -0.4)
        scene.rootNode.addChildNode(avatar.node)
        let camera = SCNCamera()
        camera.fieldOfView = 27
        camera.zNear = 0.1
        camera.zFar = 20
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3(0, 1.12, 2.5)
        cameraNode.simdEulerAngles = SIMD3(-0.07, 0, 0)
        scene.rootNode.addChildNode(cameraNode)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 450
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 700
        key.simdOrientation = simd_quatf(from: SIMD3(0, 0, -1), to: simd_normalize(SIMD3(0.5, -0.6, -1)))
        scene.rootNode.addChildNode(key)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        // 刚摆好的姿势马上生效再画
        SCNTransaction.flush()
        return renderer.snapshot(atTime: 0, with: CGSize(width: 200, height: 200), antialiasingMode: .multisampling4X)
    }
}

/// 角色头像（圆的）：3D 头像画好前先显示表情
struct BrawlerBadge: View {
    let brawler: Brawler
    var size: CGFloat = 52
    var selected = false
    @ObservedObject private var portraits = ArenaPortraits.shared

    var body: some View {
        ZStack {
            Circle().fill(selected ? DS.Palette.accentSoft : DS.Palette.surfaceSunken)
            if let image = portraits.images[brawler] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text(brawler.emoji).font(.system(size: size * 0.6))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(selected ? DS.Palette.accent : .clear, lineWidth: 2))
        .task { await portraits.prepare() }
    }
}
