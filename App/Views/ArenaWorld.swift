import SceneKit
import SpriteKit
import SwiftUI
import UIKit
import simd

/// SwiftUI 里放乱斗的 3D 画面
struct ArenaWorld: UIViewRepresentable {
    let controller: ArenaController

    func makeUIView(context: Context) -> ArenaWorldView {
        ArenaWorldView(controller: controller)
    }

    func updateUIView(_ view: ArenaWorldView, context: Context) {}

    static func dismantleUIView(_ view: ArenaWorldView, coordinator: ()) {
        view.stop()
    }
}

/// 乱斗的 3D 画面（SceneKit）：斜着往下看的镜头跟着自己走；地图、每个人、子弹、星星、圈、毒圈、特效每帧按 ArenaGame 摆一遍。
/// 名字、血条、伤害数字画在上面一层（SpriteKit），按 3D 位置算出在屏幕上的哪里。
/// 卡通的样子：亮绿的草地、浅色木箱木桶、蓬松的草丛，东西都描深色的边（见 ArenaArt）。iPhone 上横着打。
/// 坐标：地图上的 (x, y) 格就是 3D 里的 (x, 0, y)，一格 1 米；在上边那一队的人看到的整个转过来（自己家总在下边）
@MainActor
final class ArenaWorldView: SCNView {
    /// 镜头在看的那一点的斜上方。高 15、往屏幕下方 14.5，大约 46 度，能看见身子和挥砍
    private static let cameraOffset = SIMD3<Float>(0, 15, 14.5)
    /// 竖屏时自己这一排左右看得到多宽：tan(半个视角)，自己身边左右各大约 5 格
    private static let sideView: Float = 0.267
    /// 横屏时镜头看着的那一排左右各看得到几格（比原来近，人更大）
    private static let landscapeHalfWidth: Float = 7
    /// 毒圈外的绿雾有多厚。做成一圈墙，不要铺满整屏（整屏透明的面会把手机画死）
    private static let gasBand: CGFloat = 7

    private let controller: ArenaController
    private let world = SCNScene()
    private let overlay = SKScene(size: CGSize(width: 390, height: 844))
    private let rig = SCNNode()
    private let cameraNode = SCNNode()
    private let aimNode = SCNNode()
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var clock = 0.0
    private var flipped = false
    private var myTeam = 0
    private var cameraPlaced = false
    private var tanX: Float = 0.267
    private var tanY: Float = 0.58
    /// 镜头往自己前面（屏幕上方）多看几格
    private var lookAhead = 3.0
    /// 屏幕四边落在地上离镜头看着的那点多远：左右、往上、往下（镜头走到场地边上就不再往外跟）
    private var reach: (side: Float, above: Float, below: Float) = (5.6, 15, 8.6)

    private var avatars: [ArenaAvatar] = []
    private var tags: [ArenaTag] = []
    private var bushes: [(node: SCNNode, at: V2, faded: Bool)] = []
    private var projectiles: [Int: ProjectileView] = [:]
    private var starNodes: [SCNNode] = []
    private var floaters: [Floater] = []
    private var zone: (disc: SCNNode, rim: SCNNode, state: Int)?
    private var poison: (wall: SCNTube, edge: SCNTube, radius: Double)?
    private var geometries: [String: SCNGeometry] = [:]
    /// 亡灵之地（按顺序一一对上）、骨塔（按编号）
    private var zoneNodes: [SCNNode] = []
    private var turretViews: [Int: TurretView] = [:]
    /// 上一帧每个人在哪（一下子挪得很远是闪现了，两头冒烟）
    private var lastPositions: [V2?] = []
    /// 输赢的声音放过了
    private var finished = false
    /// 伤害数字的贴图（同样的数字、颜色画一次）
    private var numberTextures: [String: (texture: SKTexture, size: CGSize)] = [:]
    /// 足球：球、地上的影子、转到哪了（滚动）、上一帧在哪
    private var ballNode: SCNNode?
    private var ballShadow: SCNNode?
    private var ballSpin = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var lastBallSpot: V2?
    /// 宝箱攻防的宝箱（和 game.chests 一个对一个）
    private var chestViews: [ChestView] = []
    /// 地上快要炸的红圈
    private var warningNodes: [SCNNode] = []
    /// 大乱斗的能量箱（和 game.boxes 一个对一个）、地上的能量块
    private var boxViews: [BoxView] = []
    private var cubeNodes: [SCNNode] = []
    private var cubeLabels: [ArenaText] = []

    private struct BoxView {
        let node: SCNNode
        let wood: SCNMaterial
        let bar: ArenaBar
        var shownHealth: Int
        var flashUntil: Double = 0
    }

    /// 头顶冒的表情（跟着人走，2 秒多一点消失）
    private var bubbles: [(node: SKSpriteNode, fighter: Int, born: Double)] = []
    /// 震屏：越大晃得越厉害，很快就停
    private var shake: Float = 0
    /// 打完了镜头凑到自己跟前（0–1）
    private var closeUp: Float = 0

    private struct ChestView {
        let node: SCNNode
        let bar: ArenaBar
        let number: ArenaText
        let glow: [SCNMaterial]
        var flashUntil: Double = 0
        var shownHealth = -1
    }

    private struct TurretView {
        let node: SCNNode
        let head: SCNNode
        let bar: ArenaBar
    }

    private struct ProjectileView {
        let root: SCNNode
        /// 扔出去的炸弹：天上的球、地上的影子
        var ball: SCNNode?
        var shadow: SCNNode?
    }

    /// 飘起来的伤害数字
    private struct Floater {
        let label: SKSpriteNode
        let at: SIMD3<Float>
        let born: Double
    }

    init(controller: ArenaController) {
        self.controller = controller
        super.init(frame: .zero, options: nil)
        backgroundColor = ArenaPalette.grass
        antialiasingMode = .multisampling2X
        preferredFramesPerSecond = 60
        rendersContinuously = true
        isPlaying = true
        isUserInteractionEnabled = false
        overlay.scaleMode = .resizeFill
        overlay.backgroundColor = .clear
        overlaySKScene = overlay
        scene = world
        build()
        pointOfView = cameraNode
    }

    required init?(coder: NSCoder) { fatalError("不从文件里读") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stop()
        } else if link == nil {
            ArenaSound.shared.begin()
            let target = DisplayTarget(view: self)
            let link = CADisplayLink(target: target, selector: #selector(DisplayTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = nil
        ArenaSound.shared.end()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let aspect = Float(bounds.width / bounds.height)
        if aspect >= 1 {
            // 横屏：左右看得到整个场地宽，上下按屏幕比例；自己在屏幕中间偏下一点
            tanX = Self.landscapeHalfWidth / simd_length(Self.cameraOffset)
            tanY = tanX / aspect
            lookAhead = 1.2
        } else {
            // 竖屏（iPad 竖着）：左右看得到的宽度固定，往前多看几格
            tanY = Self.sideView / min(max(aspect, 0.3), 0.6)
            tanX = tanY * aspect
            lookAhead = 3
        }
        cameraNode.camera?.fieldOfView = CGFloat(2 * atan(tanY) * 180 / .pi)
        let lift = Self.cameraOffset.y, back = Self.cameraOffset.z
        let pitch = atan2(lift, back)
        let spread = min(atan(tanY), 0.5)
        reach = (side: tanX * simd_length(Self.cameraOffset),
                 above: lift / tan(pitch - spread) - back,
                 below: back - lift / tan(pitch + spread))
        overlay.size = bounds.size
    }

    fileprivate func tick(_ timestamp: CFTimeInterval) {
        let elapsed = lastTimestamp.map { timestamp - $0 } ?? 0
        lastTimestamp = timestamp
        controller.advance(elapsed)
        let dt = Float(min(max(elapsed, 0), 0.1))
        clock += Double(dt)
        sync(dt: dt)
    }

    // MARK: - 搭场景

    private func build() {
        let game = controller.game
        let map = game.map
        myTeam = controller.mine.team
        flipped = game.mode.isTeams && myTeam == 1
        let root = world.rootNode
        let width = Float(map.width), height = Float(map.height)
        let look = ThemeLook.of(map.theme)

        // 镜头：装在一个跟着自己走的架子上；上边那一队的人整个架子转半圈
        let camera = SCNCamera()
        camera.zNear = 4
        camera.zFar = 140
        camera.projectionDirection = .vertical
        camera.fieldOfView = 60
        camera.wantsHDR = true
        camera.bloomIntensity = 0.4
        camera.bloomThreshold = 0.8
        camera.bloomBlurRadius = 6
        camera.saturation = 1.16
        camera.contrast = 1.05
        camera.vignettingIntensity = 0.28
        camera.vignettingPower = 0.55
        cameraNode.camera = camera
        cameraNode.simdPosition = Self.cameraOffset
        cameraNode.simdEulerAngles = SIMD3(-atan2(Self.cameraOffset.y, Self.cameraOffset.z), 0, 0)
        rig.addChildNode(cameraNode)
        rig.simdEulerAngles = SIMD3(0, flipped ? .pi : 0, 0)
        root.addChildNode(rig)

        // 光：亮亮的环境光，加一盏斜着照、投影子的“太阳”（也装在架子上，两队看到的光一样）：顶上亮、朝前的面暗一点
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        ambient.light?.color = UIColor(red: 1.0, green: 0.98, blue: 0.95, alpha: 1)
        root.addChildNode(ambient)
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 640
        sun.color = look.sunlight
        sun.castsShadow = false
        let sunNode = SCNNode()
        sunNode.light = sun
        let toward = simd_normalize(SIMD3<Float>(0.35, -1, -0.45))
        sunNode.simdOrientation = simd_quatf(from: SIMD3(0, 0, -1), to: toward)
        sunNode.simdPosition = -toward * 20
        rig.addChildNode(sunNode)
        // 背后一道冷光，把角色从草地上勾出来。不投影：整屏阴影贴图是开打闪退的原因，脚下用软影子
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 340
        rim.light?.color = UIColor(red: 0.72, green: 0.86, blue: 1, alpha: 1)
        rim.light?.castsShadow = false
        rim.simdOrientation = simd_quatf(from: SIMD3(0, 0, -1), to: simd_normalize(SIMD3(-0.25, -0.35, 1)))
        rig.addChildNode(rim)

        // 地：场地外一大片草，场地里一格格深浅两种绿；上面再铺一层草叶、落叶的细纹
        let lawn = SCNPlane(width: CGFloat(width + 160), height: CGFloat(height + 160))
        lawn.firstMaterial = grass(look.lawn, repeats: SIMD2(width + 160, height + 160) / 2)
        let lawnNode = SCNNode(geometry: lawn)
        lawnNode.simdEulerAngles = SIMD3(-Float.pi / 2, 0, 0)
        lawnNode.simdPosition = SIMD3(width / 2, -0.02, height / 2)
        lawnNode.castsShadow = false
        root.addChildNode(lawnNode)
        let floor = SCNPlane(width: CGFloat(width), height: CGFloat(height))
        floor.firstMaterial = grass(groundImage(game, look: look), repeats: SIMD2(width, height) / 2)
        let floorNode = SCNNode(geometry: floor)
        floorNode.simdEulerAngles = SIMD3(-Float.pi / 2, 0, 0)
        floorNode.simdPosition = SIMD3(width / 2, 0, height / 2)
        floorNode.castsShadow = false
        root.addChildNode(floorNode)
        root.addChildNode(ArenaArt.border(width: width, height: height))

        // 墙：木箱、木桶、石块（同一格每次都一样）；草丛
        let wallNode = walls(map, look: look)
        wallNode.castsShadow = false
        root.addChildNode(wallNode)
        for y in 0..<map.height {
            for x in 0..<map.width where map.tile(x, y) == .bush {
                let node = SCNNode(geometry: ArenaArt.bushes[(x * 7 + y * 3) % ArenaArt.bushes.count])
                node.simdPosition = SIMD3(Float(x) + 0.5, 0, Float(y) + 0.5)
                node.simdEulerAngles = SIMD3(0, Float((x * 7 + y * 13) % 12) * .pi / 6, 0)
                let size = 1 + Float((x * 5 + y * 3) % 4) * 0.04
                node.simdScale = SIMD3(size, size, size)
                node.castsShadow = false
                root.addChildNode(node)
                bushes.append((node, V2(Double(x) + 0.5, Double(y) + 0.5), false))
            }
        }
        root.addChildNode(scenery(game))

        // 各个玩法的东西
        let center = SIMD3(Float(map.center.x), 0, Float(map.center.y))
        switch game.mode {
        case .zone:
            let disc = SCNCylinder(radius: CGFloat(ArenaGame.zoneRadius), height: 0.01)
            disc.radialSegmentCount = 64
            disc.firstMaterial = ArenaAvatar.decal(UIColor.white.withAlphaComponent(0.15))
            let discNode = SCNNode(geometry: disc)
            discNode.simdPosition = center + SIMD3(0, 0.02, 0)
            discNode.castsShadow = false
            discNode.renderingOrder = 2
            let rim = SCNTube(innerRadius: CGFloat(ArenaGame.zoneRadius) - 0.08, outerRadius: CGFloat(ArenaGame.zoneRadius) + 0.04, height: 0.02)
            rim.radialSegmentCount = 64
            rim.firstMaterial = ArenaAvatar.decal(UIColor.white.withAlphaComponent(0.8))
            let rimNode = SCNNode(geometry: rim)
            rimNode.simdPosition = center + SIMD3(0, 0.025, 0)
            rimNode.castsShadow = false
            rimNode.renderingOrder = 3
            root.addChildNode(discNode)
            root.addChildNode(rimNode)
            zone = (discNode, rimNode, -1)
        case .stars:
            let pad = SCNCylinder(radius: 0.7, height: 0.01)
            pad.radialSegmentCount = 48
            pad.firstMaterial = ArenaAvatar.decal(UIColor.purple.withAlphaComponent(0.35))
            let padNode = SCNNode(geometry: pad)
            padNode.simdPosition = center + SIMD3(0, 0.02, 0)
            padNode.castsShadow = false
            root.addChildNode(padNode)
        case .ball:
            for team in 0...1 {
                guard let box = goalBox(map, team: team) else { continue }
                root.addChildNode(ArenaArt.goal(from: box.x0, to: box.x1, mouth: box.mouth, back: box.back))
            }
            let ball = ArenaArt.ball()
            root.addChildNode(ball)
            ballNode = ball
            let shadow = SCNNode(geometry: shared("ball-shadow") {
                let disc = SCNCylinder(radius: 0.3, height: 0.005)
                disc.firstMaterial = ArenaAvatar.decal(UIColor.black.withAlphaComponent(0.3))
                return disc
            })
            shadow.castsShadow = false
            shadow.renderingOrder = 4
            root.addChildNode(shadow)
            ballShadow = shadow
        case .heist:
            for chest in game.chests {
                let color = chest.team == myTeam ? ArenaPalette.blue : ArenaPalette.red
                let made = ArenaArt.chest(color: color)
                made.node.simdPosition = SIMD3(Float(chest.center.x), 0, Float(chest.center.y))
                // 锁朝着场地中间
                made.node.simdEulerAngles = SIMD3(0, chest.center.y < map.center.y ? 0 : .pi, 0)
                root.addChildNode(made.node)
                let bar = ArenaBar(width: 96, height: 13, color: chest.team == myTeam ? ArenaPalette.blue : ArenaPalette.red)
                let number = ArenaText(size: 11, color: .white)
                bar.node.addChild(number.node)
                bar.node.isHidden = true
                overlay.addChild(bar.node)
                chestViews.append(ChestView(node: made.node, bar: bar, number: number, glow: made.glow))
            }
        case .showdown, .duo:
            for box in game.boxes {
                let made = ArenaArt.powerBox()
                made.node.simdPosition = SIMD3(Float(box.pos.x), 0, Float(box.pos.y))
                root.addChildNode(made.node)
                let bar = ArenaBar(width: 44, height: 7, color: ArenaPalette.gadget, border: 1.2)
                bar.node.isHidden = true
                overlay.addChild(bar.node)
                boxViews.append(BoxView(node: made.node, wood: made.wood, bar: bar, shownHealth: box.health))
            }
        case .teamFight, .bounty, .knockout, .duel, .boss:
            break
        }
        if game.mode.hasPoison {
            // 毒圈：圈外一圈半透明的绿墙，边上一道亮线
            let radius = game.safeRadius
            let wall = SCNTube(innerRadius: CGFloat(radius), outerRadius: CGFloat(radius) + Self.gasBand, height: 3.2)
            wall.radialSegmentCount = 64
            let gas = ArenaAvatar.decal(ArenaPalette.poison.withAlphaComponent(0.55))
            wall.firstMaterial = gas
            let wallNode = SCNNode(geometry: wall)
            wallNode.simdPosition = center + SIMD3(0, 1.6, 0)
            wallNode.castsShadow = false
            wallNode.renderingOrder = 20
            let edge = SCNTube(innerRadius: CGFloat(radius), outerRadius: CGFloat(radius + 0.18), height: 3.5)
            edge.radialSegmentCount = 64
            edge.firstMaterial = ArenaAvatar.decal(UIColor(red: 0.6, green: 1, blue: 0.5, alpha: 0.9))
            let edgeNode = SCNNode(geometry: edge)
            edgeNode.simdPosition = center + SIMD3(0, 1.75, 0)
            edgeNode.castsShadow = false
            edgeNode.renderingOrder = 21
            root.addChildNode(wallNode)
            root.addChildNode(edgeNode)
            poison = (wall, edge, radius)
        }

        // 人：自己这边蓝、对面红（大乱斗除了自己都是红）；骷髅王 2.2 倍大
        for fighter in game.fighters {
            let isMe = fighter.id == controller.me
            let ally = fighter.team == myTeam
            let avatar = ArenaAvatar(brawler: fighter.brawler, color: ally ? ArenaPalette.blue : ArenaPalette.red, isMe: isMe,
                                     size: fighter.isBoss ? 2.2 : 1, skin: fighter.isBoss ? 0 : fighter.skin)
            root.addChildNode(avatar.node)
            avatars.append(avatar)
            let tag = ArenaTag(fighter: fighter, isMe: isMe, ally: ally, boss: fighter.isBoss)
            overlay.addChild(tag.node)
            tags.append(tag)
        }

        aimNode.simdEulerAngles = SIMD3(-Float.pi / 2, 0, 0)
        aimNode.renderingOrder = 30
        aimNode.castsShadow = false
        aimNode.isHidden = true
        root.addChildNode(aimNode)
    }

    /// 地面的材质：底色（颜色或画好的地面）乘上草叶、落叶的细纹（细纹一张铺 2 × 2 格）
    private func grass(_ base: Any, repeats: SIMD2<Float>) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = base
        material.diffuse.mipFilter = .linear
        material.multiply.contents = ArenaArt.grassDetail
        material.multiply.wrapS = .repeat
        material.multiply.wrapT = .repeat
        material.multiply.mipFilter = .linear
        material.multiply.maxAnisotropy = 4
        material.multiply.contentsTransform = SCNMatrix4MakeScale(repeats.x, repeats.y, 1)
        return material
    }

    /// 场地的地面：深浅两种绿的格子，一块块颜色不一样的草皮，草丛、墙底下暗一点；分队玩法两队出生的地方一块队伍颜色的地
    private func groundImage(_ game: ArenaGame, look: ThemeLook) -> UIImage {
        let map = game.map
        let cell: CGFloat = 32
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: CGFloat(map.width) * cell, height: CGFloat(map.height) * cell)
        // 同一张地图每次画得一样
        var random = SeededRandom(seed: map.id.unicodeScalars.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1.value) })
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            for y in 0..<map.height {
                for x in 0..<map.width {
                    cg.setFillColor(((x + y) % 2 == 0 ? look.floor : look.floorDark).cgColor)
                    cg.fill(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
                }
            }
            // 草皮：几圈叠起来，边上淡
            cg.setFillColor(look.patch.withAlphaComponent(0.22).cgColor)
            for _ in 0..<(map.width * map.height / 14) {
                let center = CGPoint(x: CGFloat(random.below(map.width * 100)) / 100 * cell,
                                     y: CGFloat(random.below(map.height * 100)) / 100 * cell)
                let radius = (0.6 + CGFloat(random.below(90)) / 100) * cell
                let squash = 0.6 + CGFloat(random.below(60)) / 100
                for ring in 0..<3 {
                    let r = radius * (1 - CGFloat(ring) * 0.22)
                    cg.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r * squash, width: r * 2, height: r * 2 * squash))
                }
            }
            for y in 0..<map.height {
                for x in 0..<map.width {
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                    switch map.tile(x, y) {
                    case .bush:
                        cg.setFillColor(look.bushGround.cgColor)
                        cg.fillEllipse(in: rect.insetBy(dx: -cell * 0.18, dy: -cell * 0.18))
                    case .wall:
                        cg.setFillColor(UIColor(white: 0, alpha: 0.18).cgColor)
                        cg.fill(rect.insetBy(dx: -cell * 0.06, dy: -cell * 0.06))
                    case .goal:
                        // 球门里：守门那队的颜色，淡淡的
                        let team = Double(y) + 0.5 < Double(map.height) / 2 ? 1 : 0
                        cg.setFillColor((team == myTeam ? ArenaPalette.blue : ArenaPalette.red).withAlphaComponent(0.3).cgColor)
                        cg.fill(rect)
                    case .floor:
                        break
                    }
                }
            }
            // 小花
            if look.flowers {
                for _ in 0..<(map.width * map.height / 4) {
                    let x = random.below(map.width), y = random.below(map.height)
                    let at = CGPoint(x: (CGFloat(x) + CGFloat(random.below(100)) / 100) * cell,
                                     y: (CGFloat(y) + CGFloat(random.below(100)) / 100) * cell)
                    let petals = random.below(2) == 0 ? UIColor.white : UIColor(red: 1, green: 0.88, blue: 0.35, alpha: 1)
                    guard map.tile(x, y) == .floor else { continue }
                    cg.setFillColor(petals.cgColor)
                    let offsets: [(CGFloat, CGFloat)] = [(-1.8, 0), (1.8, 0), (0, -1.8), (0, 1.8)]
                    for (dx, dy) in offsets {
                        cg.fillEllipse(in: CGRect(x: at.x + dx - 1.5, y: at.y + dy - 1.5, width: 3, height: 3))
                    }
                    cg.setFillColor(UIColor(red: 1, green: 0.6, blue: 0.1, alpha: 1).cgColor)
                    cg.fillEllipse(in: CGRect(x: at.x - 1.2, y: at.y - 1.2, width: 2.4, height: 2.4))
                }
            }
            if game.mode.isTeams, map.spawns.count == 2 {
                for (team, spots) in map.spawns.enumerated() {
                    let xs = spots.map(\.x), ys = spots.map(\.y)
                    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { continue }
                    let color = team == myTeam ? ArenaPalette.blue : ArenaPalette.red
                    let area = CGRect(x: CGFloat(minX - 1.1) * cell, y: CGFloat(minY - 1.1) * cell,
                                      width: CGFloat(maxX - minX + 2.2) * cell, height: CGFloat(maxY - minY + 2.2) * cell)
                    let shape = UIBezierPath(roundedRect: area, cornerRadius: cell * 0.6).cgPath
                    cg.setFillColor(color.withAlphaComponent(0.2).cgColor)
                    cg.addPath(shape)
                    cg.fillPath()
                    cg.setStrokeColor(color.withAlphaComponent(0.55).cgColor)
                    cg.setLineWidth(3)
                    cg.addPath(shape)
                    cg.strokePath()
                }
            }
            // 球门线：白的
            for team in 0...1 {
                guard let box = goalBox(map, team: team) else { continue }
                cg.setFillColor(UIColor(white: 1, alpha: 0.85).cgColor)
                cg.fill(CGRect(x: CGFloat(box.x0) * cell, y: CGFloat(box.mouth) * cell - 2, width: CGFloat(box.x1 - box.x0) * cell, height: 4))
            }
            cg.setStrokeColor(UIColor(white: 0, alpha: 0.2).cgColor)
            cg.setLineWidth(4)
            cg.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2))
        }
    }

    /// 一队守的球门在哪：门口两边的 x、门口那条线、后面那条线（地图坐标）
    private func goalBox(_ map: ArenaMap, team: Int) -> (x0: Float, x1: Float, mouth: Float, back: Float)? {
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<map.height {
            for x in 0..<map.width where map.tile(x, y) == .goal && (Double(y) + 0.5 < Double(map.height) / 2 ? 1 : 0) == team {
                xs.append(x)
                ys.append(y)
            }
        }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let top = team == 1
        return (Float(minX), Float(maxX + 1), top ? Float(maxY + 1) : Float(minY), top ? Float(minY) : Float(maxY + 1))
    }

    /// 墙：按地图的主题挑木箱、木桶、石块（同一格每次都一样），整张地图拼成一个网格
    private func walls(_ map: ArenaMap, look: ThemeLook) -> SCNNode {
        let total = max(look.walls.reduce(0) { $0 + $1.weight }, 1)
        var cells: [(x: Int, y: Int, kind: ArenaArt.Wall)] = []
        for y in 0..<map.height {
            for x in 0..<map.width where map.tile(x, y) == .wall && !map.isChest(x, y) {
                var left = (x * 37 + y * 61 + x * y) % total
                let kind = look.walls.first { left -= $0.weight; return left < 0 }?.kind ?? .crate
                cells.append((x: x, y: y, kind: kind))
            }
        }
        return ArenaArt.walls(cells)
    }

    /// 场地外两圈树、几块石头，分队玩法两头插旗。每种模型只读一次，摆下去的是同一份网格，不描边、不投影，再合成一块
    private func scenery(_ game: ArenaGame) -> SCNNode {
        let map = game.map
        let width = Double(map.width), height = Double(map.height)
        let models = ArenaModels.shared
        let trees = ["trees_A_small.gltf", "trees_A_medium.gltf", "trees_A_large.gltf",
                     "trees_B_small.gltf", "trees_B_medium.gltf", "trees_B_large.gltf"].compactMap { models.prop($0) }
        let rocks = ["rock_single_A.gltf", "rock_single_B.gltf", "rock_single_C.gltf"].compactMap { models.prop($0) }
        var random = SeededRandom(seed: 2026)
        let holder = SCNNode()
        func source(_ model: GLTFModel) -> SCNNode {
            let node = model.instantiate(shareMaterials: true).root
            node.castsShadow = false
            node.enumerateChildNodes { child, _ in child.castsShadow = false }
            return node
        }
        let treeSources = trees.map(source)
        let rockSources = rocks.map(source)
        func place(_ template: SCNNode, at point: V2, scale: Float, turn: Float) {
            let node = template.clone()
            node.simdPosition = SIMD3(Float(point.x), 0, Float(point.y))
            node.simdScale = SIMD3(repeating: scale)
            node.simdEulerAngles = SIMD3(0, turn, 0)
            holder.addChildNode(node)
        }
        for row in 0..<2 {
            let gap = 1.6 + Double(row) * 2.2
            let step = 2.6
            var edge: [V2] = []
            var t = -gap + Double(row) * step / 2
            while t <= width + gap {
                edge.append(V2(t, -gap))
                edge.append(V2(t, height + gap))
                t += step
            }
            t = Double(row) * step / 2
            while t <= height {
                edge.append(V2(-gap, t))
                edge.append(V2(width + gap, t))
                t += step
            }
            for point in edge where !treeSources.isEmpty {
                let jitter = V2(Double(random.below(50)) / 100 - 0.25, Double(random.below(50)) / 100 - 0.25)
                place(treeSources[random.below(treeSources.count)], at: point + jitter, scale: 1.3 + Float(random.below(40)) / 100,
                      turn: Float(random.below(6)) * .pi / 3)
            }
        }
        for _ in 0..<12 where !rockSources.isEmpty {
            let side = random.below(4)
            let along = Double(random.below(1000)) / 1000
            let point: V2
            switch side {
            case 0: point = V2(along * width, -0.6)
            case 1: point = V2(along * width, height + 0.6)
            case 2: point = V2(-0.6, along * height)
            default: point = V2(width + 0.6, along * height)
            }
            place(rockSources[random.below(rockSources.count)], at: point, scale: 2.2 + Float(random.below(14)) / 10, turn: Float(random.below(628)) / 100)
        }
        if game.mode.isTeams, let blue = models.prop("flag_blue.gltf"), let red = models.prop("flag_red.gltf") {
            let flags = [source(blue), source(red)]
            for (team, z) in [(1, -0.9), (0, height + 0.9)] {
                let flag = flags[team == myTeam ? 0 : 1]
                for x in [2.5, width - 2.5] {
                    place(flag, at: V2(x, z), scale: 4, turn: team == 0 ? .pi : 0)
                }
            }
        }
        let baked = holder.flattenedClone()
        baked.castsShadow = false
        return baked
    }

    // MARK: - 每帧摆一遍

    private func sync(dt: Float) {
        let game = controller.game
        moveCamera(dt: dt, game: game)
        let view = cameraNode.simdWorldTransform.inverse
        let events = controller.takeEvents()
        // 进球、一局打完大家回到出发的地方：不算闪现
        if events.contains(.reset) { lastPositions = [] }

        // 人、头顶的血条
        let winners: (Fighter) -> Bool = { fighter in
            switch game.result {
            case .team(let team)?: return fighter.team == team
            case .survivor(let id)?: return fighter.id == id
            default: return false
            }
        }
        if lastPositions.count != game.fighters.count { lastPositions = game.fighters.map { $0.alive ? $0.pos : nil } }
        for fighter in game.fighters where avatars.indices.contains(fighter.id) {
            // 闪现：上一帧还在别处
            if fighter.alive, fighter.leap == nil, fighter.dash == nil, let last = lastPositions[fighter.id], last.distance(to: fighter.pos) > 2 {
                let from = SIMD3(Float(last.x), 0.6, Float(last.y)), to = SIMD3(Float(fighter.pos.x), 0.6, Float(fighter.pos.y))
                burst(at: from, color: UIColor(red: 0.6, green: 0.4, blue: 1, alpha: 1), count: 24, speed: 1.5, size: 0.35, life: 0.5)
                burst(at: to, color: UIColor(red: 0.6, green: 0.4, blue: 1, alpha: 1), count: 24, speed: 2, size: 0.35, life: 0.5)
            }
            lastPositions[fighter.id] = fighter.alive ? fighter.pos : nil
            // 一对一换了下一个角色上：换模型
            if avatars[fighter.id].brawler != fighter.brawler, !fighter.isBoss {
                avatars[fighter.id].node.removeFromParentNode()
                let ally = fighter.team == myTeam
                let replacement = ArenaAvatar(brawler: fighter.brawler, color: ally ? ArenaPalette.blue : ArenaPalette.red,
                                              isMe: fighter.id == controller.me, skin: fighter.skin)
                world.rootNode.addChildNode(replacement.node)
                avatars[fighter.id] = replacement
            }
            let avatar = avatars[fighter.id]
            let visible = game.isVisible(fighter, to: myTeam)
            // 自己这边躲在草丛里的、隐身的（对面贴近了才看得见）：半透明
            let hidden = (fighter.team == myTeam && game.map.inBush(fighter.pos)) || fighter.invisible > 0
            avatar.update(fighter, visible: visible, translucent: hidden, cheering: winners(fighter), dt: dt, clock: clock)
            let head = avatar.node.simdPosition + SIMD3(0, ArenaAvatar.headHeight * avatar.size, 0)
            tags[fighter.id].update(fighter, at: project(head, view), opacity: avatar.opacity)
        }

        // 自己旁边的草丛变透明，看得见自己
        let me = controller.mine
        for k in bushes.indices {
            let fade = me.alive && bushes[k].at.distance(to: me.pos) < 1.45
            if fade != bushes[k].faded {
                bushes[k].faded = fade
                bushes[k].node.opacity = fade ? 0.4 : 1
            }
        }

        syncProjectiles(game)
        syncStars(game)
        syncZone(game)
        syncHealZones(game)
        syncTurrets(game, view: view)
        syncBall(game)
        syncChests(game, view: view)
        syncWarnings(game)
        syncPower(game, view: view)
        if var current = poison, abs(current.radius - game.safeRadius) > 0.02 {
            current.radius = game.safeRadius
            current.wall.outerRadius = CGFloat(current.radius) + Self.gasBand
            current.wall.innerRadius = CGFloat(current.radius)
            current.edge.outerRadius = CGFloat(current.radius + 0.18)
            current.edge.innerRadius = CGFloat(current.radius)
            poison = current
        }

        for event in events { effect(event, game: game) }
        // 结算时镜头凑近自己，头顶的名字、血条、数字都收起来
        overlay.isHidden = controller.hud.result != nil
        if !finished, let result = controller.hud.result {
            finished = true
            ArenaSound.shared.finish(won: controller.won(result))
        }
        syncFloaters(view)
        syncBubbles(view)
        syncAim(me)
    }

    /// 镜头跟着自己（往前多看几格；走到边上就不再往外跟，场外最多露出一格半）
    private func moveCamera(dt: Float, game: ArenaGame) {
        let map = game.map
        let width = Double(map.width), height = Double(map.height)
        let me = controller.mine.pos
        // 换成“屏幕上的方向”算：上边那一队的人看到的整个倒过来
        var screen = flipped ? V2(width - me.x, height - me.y) : me
        let margin = 1.5
        let side = Double(reach.side) - margin
        screen.x = width > side * 2 ? min(max(screen.x, side), width - side) : width / 2
        let top = Double(reach.above) - margin, bottom = height + margin - Double(reach.below)
        screen.y = top <= bottom ? min(max(screen.y - lookAhead, top), bottom) : (top + bottom) / 2
        let target = flipped ? V2(width - screen.x, height - screen.y) : screen
        var goal = SIMD3(Float(target.x), 0, Float(target.y))
        // 打完了：镜头凑到自己跟前（横屏时自己在画面左边，右边放结算）
        let ending = controller.hud.result != nil
        closeUp = ending ? min(1, closeUp + dt * 0.9) : 0
        if ending {
            let me = controller.mine.pos
            let shift: Float = bounds.width > bounds.height ? 1.4 : 0
            goal = SIMD3(Float(me.x) + (flipped ? -shift : shift), 0, Float(me.y))
        }
        if cameraPlaced {
            rig.simdPosition += (goal - rig.simdPosition) * min(1, dt * (ending ? 3 : 11))
        } else {
            rig.simdPosition = goal
            cameraPlaced = true
        }
        let t = closeUp * closeUp * (3 - 2 * closeUp)
        let offset = Self.cameraOffset + (Self.closeOffset(tanY: tanY) - Self.cameraOffset) * t
        let look = 0.8 * t
        shake = max(0, shake - dt * 2.2)
        let jitter = shake > 0 ? SIMD3(Float.random(in: -1...1), Float.random(in: -1...1), 0) * (shake * shake * 0.5) : .zero
        cameraNode.simdPosition = offset + jitter
        cameraNode.simdEulerAngles = SIMD3(-atan2(offset.y - look, offset.z), 0, 0)
    }

    /// 结算时镜头凑多近：画面上下大约 3.2 米，还是斜着往下看，对着自己胸口
    private static func closeOffset(tanY: Float) -> SIMD3<Float> {
        simd_normalize(SIMD3<Float>(0, 0.55, 0.835)) * (3.2 / (2 * max(tanY, 0.05))) + SIMD3(0, 0.8, 0)
    }

    /// 晃一下镜头（几下叠在一起取最大的）
    private func addShake(_ amount: Float) {
        guard amount > 0 else { return }
        shake = min(0.9, max(shake, amount))
    }

    /// 3D 里的一点在上面那层（SpriteKit，左下角是原点）的哪里；在镜头后面返回 nil
    private func project(_ point: SIMD3<Float>, _ view: simd_float4x4) -> CGPoint? {
        let c = view * SIMD4(point, 1)
        guard c.z < -0.5 else { return nil }
        let x = c.x / -c.z / tanX
        let y = c.y / -c.z / tanY
        return CGPoint(x: CGFloat(x + 1) / 2 * bounds.width, y: CGFloat(y + 1) / 2 * bounds.height)
    }

    // MARK: - 足球、宝箱、红圈

    /// 球：有人带着画在他脚前（跳起来也跟着），没人带画在地上；按走了多远滚着转
    private func syncBall(_ game: ArenaGame) {
        guard let node = ballNode else { return }
        guard let ball = game.ball else {
            node.isHidden = true
            ballShadow?.isHidden = true
            return
        }
        var spot = ball.pos
        var lift: Float = 0
        if let carrier = ball.carrier, game.fighters.indices.contains(carrier), avatars.indices.contains(carrier) {
            let holder = game.fighters[carrier]
            spot = holder.pos + holder.facing * 0.5
            lift = avatars[carrier].node.simdPosition.y
        }
        if let last = lastBallSpot {
            let moved = spot - last
            if moved.length > 0.0001, moved.length < 2 {
                let axis = simd_normalize(SIMD3(Float(moved.y), 0, Float(-moved.x)))
                ballSpin = simd_normalize(simd_quatf(angle: Float(moved.length / ArenaGame.Ball.radius), axis: axis) * ballSpin)
            }
        }
        lastBallSpot = spot
        node.isHidden = false
        node.simdPosition = SIMD3(Float(spot.x), Float(ArenaGame.Ball.radius) + lift, Float(spot.y))
        node.simdOrientation = ballSpin
        ballShadow?.isHidden = false
        ballShadow?.simdPosition = SIMD3(Float(spot.x), 0.03, Float(spot.y))
    }

    /// 宝箱头顶的血条（数字写在条上）；挨打白一下
    private func syncChests(_ game: ArenaGame, view: simd_float4x4) {
        for (k, chest) in game.chests.enumerated() where chestViews.indices.contains(k) {
            let item = chestViews[k]
            if let point = project(SIMD3(Float(chest.center.x), 2.6, Float(chest.center.y)), view) {
                item.bar.node.isHidden = chest.health <= 0
                item.bar.node.position = point
                item.bar.set(CGFloat(chest.health) / CGFloat(max(chest.maxHealth, 1)))
                if chest.health != item.shownHealth {
                    chestViews[k].shownHealth = chest.health
                    item.number.set("\(max(chest.health, 0))")
                }
            } else {
                item.bar.node.isHidden = true
            }
            if item.flashUntil > 0, clock >= item.flashUntil {
                chestViews[k].flashUntil = 0
                item.glow.forEach { $0.emission.contents = UIColor.black }
            }
        }
    }

    /// 能量箱：挨打闪白、飘伤害数字，打了就露出血条，碎了收起来冒一阵绿光；地上的能量块转着上下浮，叠了几块写着几
    private func syncPower(_ game: ArenaGame, view: simd_float4x4) {
        for (k, box) in game.boxes.enumerated() where boxViews.indices.contains(k) {
            let item = boxViews[k]
            if box.health != item.shownHealth {
                let lost = item.shownHealth - box.health
                boxViews[k].shownHealth = box.health
                if box.health <= 0 {
                    item.node.isHidden = true
                    item.bar.node.isHidden = true
                    let at = SIMD3(Float(box.pos.x), 0.6, Float(box.pos.y))
                    burst(at: at, color: ArenaPalette.gadget, count: 36, speed: 3, size: 0.32, life: 0.5)
                    burst(at: at, color: UIColor(red: 0.75, green: 0.55, blue: 0.3, alpha: 1), count: 18, speed: 2.4, size: 0.24, life: 0.45)
                    continue
                }
                if lost > 0 {
                    item.wood.emission.contents = UIColor(white: 0.5, alpha: 1)
                    boxViews[k].flashUntil = clock + 0.08
                    floater("\(lost)", at: SIMD3(Float(box.pos.x) + Float.random(in: -0.2...0.2), 1.3, Float(box.pos.y)), color: .white)
                }
            }
            if boxViews[k].flashUntil > 0, clock >= boxViews[k].flashUntil {
                boxViews[k].flashUntil = 0
                item.wood.emission.contents = UIColor.black
            }
            guard box.health > 0 else { continue }
            item.node.childNode(withName: "gem", recursively: false)?.simdEulerAngles = SIMD3(0.6, Float(clock * 1.5), 0)
            if box.health < ArenaGame.PowerBox.fullHealth, let point = project(SIMD3(Float(box.pos.x), 1.35, Float(box.pos.y)), view) {
                item.bar.node.isHidden = false
                item.bar.node.position = point
                item.bar.set(CGFloat(box.health) / CGFloat(ArenaGame.PowerBox.fullHealth))
            } else {
                item.bar.node.isHidden = true
            }
        }
        while cubeNodes.count < game.cubes.count {
            let node = SCNNode(geometry: ArenaArt.cube)
            node.castsShadow = false
            node.addChildNode(halo("cube", ArenaPalette.gadget, size: 1.1))
            world.rootNode.addChildNode(node)
            cubeNodes.append(node)
            let label = ArenaText(size: 13, color: ArenaPalette.myName)
            overlay.addChild(label.node)
            cubeLabels.append(label)
        }
        while cubeNodes.count > game.cubes.count {
            cubeNodes.removeLast().removeFromParentNode()
            cubeLabels.removeLast().node.removeFromParent()
        }
        for (k, cube) in game.cubes.enumerated() {
            let bob = Float(sin(clock * 3 + Double(k))) * 0.08
            let at = SIMD3(Float(cube.pos.x), 0.45 + bob, Float(cube.pos.y))
            cubeNodes[k].simdPosition = at
            cubeNodes[k].simdEulerAngles = SIMD3(0.5, Float(clock * 1.8) + Float(k), 0.3)
            let scale = Float(min(1 + 0.12 * Double(cube.count - 1), 1.6))
            cubeNodes[k].simdScale = SIMD3(repeating: scale)
            if cube.count > 1, let point = project(at + SIMD3(0, 0.55, 0), view) {
                cubeLabels[k].node.isHidden = false
                cubeLabels[k].node.position = point
                cubeLabels[k].set("×\(cube.count)")
            } else {
                cubeLabels[k].node.isHidden = true
            }
        }
    }

    /// 地上快要炸的红圈：外面一道红边，里面的红一点点填满
    private func syncWarnings(_ game: ArenaGame) {
        while warningNodes.count < game.warnings.count {
            let node = SCNNode()
            let rim = SCNNode(geometry: shared("warning-rim") {
                let tube = SCNTube(innerRadius: 0.93, outerRadius: 1, height: 0.02)
                tube.radialSegmentCount = 48
                tube.firstMaterial = ArenaAvatar.decal(UIColor(red: 1, green: 0.2, blue: 0.15, alpha: 0.95))
                return tube
            })
            let fill = SCNNode(geometry: shared("warning-fill") {
                let disc = SCNCylinder(radius: 1, height: 0.01)
                disc.radialSegmentCount = 48
                disc.firstMaterial = ArenaAvatar.decal(UIColor(red: 1, green: 0.15, blue: 0.1, alpha: 0.4))
                return disc
            })
            fill.name = "fill"
            for part in [rim, fill] {
                part.castsShadow = false
                part.renderingOrder = 7
                node.addChildNode(part)
            }
            world.rootNode.addChildNode(node)
            warningNodes.append(node)
        }
        while warningNodes.count > game.warnings.count {
            warningNodes.removeLast().removeFromParentNode()
        }
        for (k, warning) in game.warnings.enumerated() {
            let node = warningNodes[k]
            let radius = Float(warning.radius)
            node.simdPosition = SIMD3(Float(warning.center.x), 0.05, Float(warning.center.y))
            node.simdScale = SIMD3(radius, 1, radius)
            let progress = Float(min(max(1 - warning.left / max(warning.total, 0.01), 0.05), 1))
            node.childNode(withName: "fill", recursively: false)?.simdScale = SIMD3(progress, 1, progress)
        }
    }

    // MARK: - 子弹

    private func syncProjectiles(_ game: ArenaGame) {
        var seen = Set<Int>()
        for p in game.projectiles {
            seen.insert(p.id)
            let view = projectiles[p.id] ?? makeProjectile(p, game)
            projectiles[p.id] = view
            if let lob = p.lob {
                let t = Float(min(max(lob.elapsed / lob.duration, 0), 1))
                let arc: Float = p.isSuper ? 3 : 2
                view.ball?.simdPosition = SIMD3(Float(p.pos.x), 0.6 + sin(t * .pi) * arc, Float(p.pos.y))
                view.shadow?.simdPosition = SIMD3(Float(p.pos.x), 0.035, Float(p.pos.y))
            } else {
                view.root.simdPosition = SIMD3(Float(p.pos.x), 0.6, Float(p.pos.y))
            }
        }
        for (id, view) in projectiles where !seen.contains(id) {
            view.root.removeFromParentNode()
            projectiles[id] = nil
        }
    }

    private func makeProjectile(_ p: Projectile, _ game: ArenaGame) -> ProjectileView {
        let owner = game.fighters.indices.contains(p.owner) ? game.fighters[p.owner].brawler : .ranger
        // 超级充能开着放的大招：紫的
        let hyper = p.isSuper && game.fighters.indices.contains(p.owner) && game.fighters[p.owner].hyperTime > 0
        let tint = hyper ? ArenaPalette.hyper : (p.isSuper ? ArenaPalette.gold : (p.team == myTeam ? ArenaPalette.allyShot : ArenaPalette.enemyShot))
        let tintKey = hyper ? "hyper" : (p.isSuper ? "gold" : (p.team == myTeam ? "ally" : "enemy"))
        // 子弹芯是偏白的亮色，外面一圈光晕，后面拖一条尾巴
        let core = Self.lighter(tint, 0.5)
        if let lob = p.lob {
            // 扔出去的火球：天上的球、地上的影子、落点的圈
            let root = SCNNode()
            let radius: CGFloat = p.isSuper ? 0.45 : 0.25
            let fire = hyper ? ArenaPalette.hyper : (p.isSuper ? UIColor.orange : tint)
            let ball = SCNNode(geometry: shared("ball-\(tintKey)-\(p.isSuper)") {
                let sphere = SCNSphere(radius: radius)
                sphere.segmentCount = 14
                sphere.firstMaterial = ArenaAvatar.material(Self.lighter(fire, 0.4), lit: false)
                return sphere
            })
            ball.castsShadow = false
            ball.addChildNode(halo(hyper ? "hyperfire" : (p.isSuper ? "fire" : tintKey), fire, size: radius * 5))
            ball.addParticleSystem(trail(fire, size: p.isSuper ? 0.5 : 0.3))
            let shadow = SCNNode(geometry: shared("shadow-\(p.isSuper)") {
                let disc = SCNCylinder(radius: radius * 0.9, height: 0.005)
                disc.firstMaterial = ArenaAvatar.decal(UIColor.black.withAlphaComponent(0.3))
                return disc
            })
            shadow.castsShadow = false
            shadow.renderingOrder = 4
            let marker = SCNNode(geometry: shared("landing-\(tintKey)-\(lob.blast)") {
                let ring = SCNTube(innerRadius: CGFloat(lob.blast) - 0.07, outerRadius: CGFloat(lob.blast), height: 0.01)
                ring.radialSegmentCount = 48
                ring.firstMaterial = ArenaAvatar.decal(tint.withAlphaComponent(0.75))
                return ring
            })
            marker.simdPosition = SIMD3(Float(lob.to.x), 0.04, Float(lob.to.y))
            marker.castsShadow = false
            marker.renderingOrder = 4
            [ball, shadow, marker].forEach(root.addChildNode)
            world.rootNode.addChildNode(root)
            return ProjectileView(root: root, ball: ball, shadow: shadow)
        }
        // 直着飞的：剑气、斧风是扁的一道，魂火是一团，弩箭、飞刀是细长的
        let piece = SCNNode()
        switch owner {
        case .necromancer:
            piece.geometry = shared("soul-\(tintKey)") {
                let sphere = SCNSphere(radius: 0.3)
                sphere.segmentCount = 14
                sphere.firstMaterial = ArenaAvatar.material(core, lit: false)
                return sphere
            }
            piece.addParticleSystem(trail(UIColor(red: 0.5, green: 1, blue: 0.6, alpha: 1), size: 0.35))
        case .knight, .barbarian, .guardian:
            let wide: CGFloat = owner == .knight ? 0.55 : (owner == .guardian ? 1.0 : 0.8)
            piece.geometry = shared("slash-\(owner.rawValue)-\(tintKey)") {
                let box = SCNBox(width: wide, height: 0.06, length: 0.16, chamferRadius: 0.03)
                box.firstMaterial = ArenaAvatar.material(core, lit: false)
                return box
            }
        default:
            let thick: CGFloat = p.isSuper ? 0.12 : (owner == .assassin ? 0.045 : 0.06)
            let long: CGFloat = p.isSuper ? 1.2 : (owner == .assassin ? 0.42 : 0.7)
            piece.geometry = shared("bolt-\(owner.rawValue)-\(tintKey)-\(p.isSuper)") {
                let capsule = SCNCapsule(capRadius: thick, height: long)
                capsule.firstMaterial = ArenaAvatar.material(core, lit: false)
                return capsule
            }
            piece.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        }
        piece.castsShadow = false
        let root = SCNNode()
        root.addChildNode(piece)
        root.addChildNode(halo(tintKey, tint, size: p.isSuper ? 1.5 : 0.95))
        root.simdEulerAngles = SIMD3(0, atan2(Float(p.velocity.x), Float(p.velocity.y)), 0)
        root.simdPosition = SIMD3(Float(p.pos.x), 0.6, Float(p.pos.y))
        root.addParticleSystem(trail(tint, size: p.isSuper ? 0.4 : 0.24, life: p.isSuper ? 0.3 : 0.16))
        world.rootNode.addChildNode(root)
        return ProjectileView(root: root)
    }

    /// 一团朝着镜头的光晕（颜色加上去，越叠越亮）
    private func halo(_ key: String, _ color: UIColor, size: CGFloat) -> SCNNode {
        let node = SCNNode(geometry: shared("halo-\(key)-\(size)") {
            let plane = SCNPlane(width: size, height: size)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = ArenaArt.glow(color)
            material.blendMode = .add
            material.writesToDepthBuffer = false
            material.isDoubleSided = true
            plane.firstMaterial = material
            return plane
        })
        node.constraints = [SCNBillboardConstraint()]
        node.castsShadow = false
        node.renderingOrder = 40
        return node
    }

    /// 往白里调一点（子弹芯）
    private static func lighter(_ color: UIColor, _ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r + (1 - r) * amount, green: g + (1 - g) * amount, blue: b + (1 - b) * amount, alpha: a)
    }

    /// 同样的子弹共用一个形状
    private func shared(_ key: String, _ make: () -> SCNGeometry) -> SCNGeometry {
        if let geometry = geometries[key] { return geometry }
        let geometry = make()
        geometries[key] = geometry
        return geometry
    }

    // MARK: - 星星、占点的圈

    private func syncStars(_ game: ArenaGame) {
        while starNodes.count < game.stars.count {
            let node = SCNNode(geometry: shared("star") {
                let shape = SCNShape(path: Self.starPath(outer: 0.34, inner: 0.15), extrusionDepth: 0.12)
                shape.firstMaterial = ArenaAvatar.material(ArenaPalette.gold, lit: false)
                return shape
            })
            node.castsShadow = false
            world.rootNode.addChildNode(node)
            starNodes.append(node)
        }
        while starNodes.count > game.stars.count {
            starNodes.removeLast().removeFromParentNode()
        }
        for (k, star) in game.stars.enumerated() {
            let bob = Float(sin(clock * 4 + Double(k))) * 0.1
            starNodes[k].simdPosition = SIMD3(Float(star.x), 0.55 + bob, Float(star.y))
            starNodes[k].simdEulerAngles = SIMD3(0, Float(clock * 2) + Float(k), 0)
        }
    }

    private static func starPath(outer: CGFloat, inner: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        for k in 0..<10 {
            let radius = k % 2 == 0 ? outer : inner
            let angle = CGFloat(k) * .pi / 5 - .pi / 2
            let point = CGPoint(x: cos(angle) * radius, y: -sin(angle) * radius)
            if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.close()
        return path
    }

    /// 占点：圈里只有一队就是这队的颜色，两队都在是橙色
    private func syncZone(_ game: ArenaGame) {
        guard var current = zone else { return }
        let inside = Set(game.fighters.filter { $0.alive && $0.pos.distance(to: game.map.center) < ArenaGame.zoneRadius }.map(\.team))
        let state = inside.count > 1 ? 3 : (inside.first.map { $0 == myTeam ? 1 : 2 } ?? 0)
        guard state != current.state else { return }
        current.state = state
        zone = current
        let color: UIColor = [UIColor.white, ArenaPalette.blue, ArenaPalette.red, UIColor.orange][state]
        current.disc.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(state == 0 ? 0.15 : 0.3)
        current.rim.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.85)
    }

    // MARK: - 特效

    private func effect(_ event: ArenaGame.Event, game: ArenaGame) {
        switch event {
        case .hit(let target, let amount):
            guard avatars.indices.contains(target), avatars[target].opacity > 0.1 else { return }
            // 毒圈这种一帧扣一点的不出声、不闪
            guard amount >= 60 else { return }
            ArenaSound.shared.play(.hit, volume: loudness(game.fighters[target].pos) * 0.8)
            avatars[target].flash(clock: clock)
            if target == controller.me, amount >= 900 { addShake(0.22) }
            let at = avatars[target].node.simdPosition
            spark(at: at + SIMD3(0, 0.7, 0))
            floater("\(amount)", at: at + SIMD3(Float.random(in: -0.25...0.25), ArenaAvatar.headHeight + 0.35, 0),
                    color: game.fighters[target].team == myTeam ? UIColor(red: 1, green: 0.45, blue: 0.4, alpha: 1) : .white)
        case .explosion(let point, let radius):
            ArenaSound.shared.play(.boom, volume: loudness(point))
            addShake(Float(radius) * 0.16 * max(0, 1 - Float(point.distance(to: controller.mine.pos)) / 9))
            let at = SIMD3(Float(point.x), 0.05, Float(point.y))
            burst(at: at + SIMD3(0, 0.3, 0), color: .orange, count: 40, speed: 4 * CGFloat(radius), size: 0.45, life: 0.45)
            burst(at: at + SIMD3(0, 0.3, 0), color: ArenaPalette.gold, count: 20, speed: 2.5 * CGFloat(radius), size: 0.3, life: 0.35)
            let disc = SCNCylinder(radius: CGFloat(radius), height: 0.01)
            disc.radialSegmentCount = 40
            disc.firstMaterial = ArenaAvatar.decal(UIColor.orange.withAlphaComponent(0.55))
            let node = SCNNode(geometry: disc)
            node.simdPosition = at
            node.castsShadow = false
            node.renderingOrder = 8
            node.simdScale = SIMD3(0.3, 1, 0.3)
            world.rootNode.addChildNode(node)
            node.runAction(.sequence([.group([.scale(to: 1, duration: 0.12), .fadeOut(duration: 0.4)]), .removeFromParentNode()]))
        case .knockout(let target, _):
            guard avatars.indices.contains(target) else { return }
            ArenaSound.shared.play(.knockout, volume: target == controller.me ? 1 : loudness(game.fighters[target].pos))
            burst(at: avatars[target].node.simdPosition + SIMD3(0, 0.6, 0), color: UIColor(white: 0.9, alpha: 1),
                  count: 30, speed: 2, size: 0.4, life: 0.6)
            if target == controller.me {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                addShake(0.5)
            }
        case .special(let fighter):
            guard avatars.indices.contains(fighter) else { return }
            let caster = game.fighters[fighter]
            ArenaSound.shared.play(caster.brawler == .shade ? .blink : .power, volume: loudness(caster.pos))
            avatars[fighter].special()
            // 草丛里看不见的对面放大招不出光（免得暴露）
            if avatars[fighter].opacity > 0.1 || caster.team == myTeam {
                superFlash(caster, at: avatars[fighter].node.simdPosition, size: avatars[fighter].size)
            }
            if fighter == controller.me {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                addShake(0.15)
            }
        case .attack(let fighter):
            guard avatars.indices.contains(fighter) else { return }
            let sound: ArenaSound.Effect
            switch game.fighters[fighter].brawler {
            case .knight, .barbarian, .guardian: sound = .slash
            case .mage, .necromancer: sound = .magic
            default: sound = .shot
            }
            // 看不见的人开火也听得见一点（草丛里有人）
            ArenaSound.shared.play(sound, volume: loudness(game.fighters[fighter].pos) * (fighter == controller.me ? 1 : 0.7))
            avatars[fighter].attack()
            // 枪口一闪（看不见的人不闪，免得暴露草丛里的人）
            if avatars[fighter].opacity > 0.1 {
                let shooter = game.fighters[fighter]
                let at = SIMD3(Float(shooter.pos.x + shooter.facing.x * 0.55), 0.75, Float(shooter.pos.y + shooter.facing.y * 0.55))
                burst(at: at, color: shooter.team == myTeam ? ArenaPalette.allyShot : ArenaPalette.enemyShot, count: 8, speed: 1.6, size: 0.22, life: 0.14)
            }
        case .heal(let target, let amount):
            guard avatars.indices.contains(target), avatars[target].opacity > 0.1 else { return }
            ArenaSound.shared.play(.heal, volume: loudness(game.fighters[target].pos) * 0.7)
            let at = avatars[target].node.simdPosition
            burst(at: at + SIMD3(0, 0.5, 0), color: UIColor(red: 0.4, green: 1, blue: 0.5, alpha: 1), count: 10, speed: 1, size: 0.25, life: 0.5)
            floater("+\(amount)", at: at + SIMD3(Float.random(in: -0.25...0.25), ArenaAvatar.headHeight + 0.35, 0),
                    color: UIColor(red: 0.45, green: 1, blue: 0.5, alpha: 1))
        case .goal(let team):
            let ours = team == myTeam
            ArenaSound.shared.play(ours ? .win : .lose, volume: 0.8)
            if let ball = game.ball {
                let at = SIMD3(Float(ball.pos.x), 0.7, Float(ball.pos.y))
                burst(at: at, color: ArenaPalette.gold, count: 70, speed: 5, size: 0.35, life: 0.9)
                burst(at: at, color: ours ? ArenaPalette.blue : ArenaPalette.red, count: 50, speed: 4, size: 0.3, life: 0.8)
            }
            if ours { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            addShake(0.3)
        case .round(let winner):
            ArenaSound.shared.play(winner == myTeam ? .win : .lose, volume: 0.7)
        case .reset:
            for (k, fighter) in game.fighters.enumerated() where fighter.alive && avatars.indices.contains(k) {
                ring(at: avatars[k].node.simdPosition, color: fighter.team == myTeam ? ArenaPalette.blue : ArenaPalette.red, to: 1.8)
            }
            lastBallSpot = nil
        case .chestHit(let chest, let amount):
            guard chestViews.indices.contains(chest), game.chests.indices.contains(chest) else { return }
            let center = game.chests[chest].center
            chestViews[chest].glow.forEach { $0.emission.contents = UIColor(white: 0.45, alpha: 1) }
            chestViews[chest].flashUntil = clock + 0.08
            ArenaSound.shared.play(.hit, volume: loudness(center) * 0.6)
            floater("\(amount)", at: SIMD3(Float(center.x) + Float.random(in: -0.4...0.4), 2.0, Float(center.y)), color: .white)
        case .gadget(let fighter):
            guard avatars.indices.contains(fighter) else { return }
            let user = game.fighters[fighter]
            let at = avatars[fighter].node.simdPosition
            // 隐身的人用小道具，对面看不见就不出光、不出声
            guard game.isVisible(user, to: myTeam) || user.team == myTeam else { return }
            ArenaSound.shared.play(.gadget, volume: loudness(user.pos))
            ring(at: at, color: ArenaPalette.gadget, to: 1.6)
            burst(at: at + SIMD3(0, 0.8, 0), color: ArenaPalette.gadget, count: 18, speed: 1.8, size: 0.24, life: 0.4)
            switch user.gadget {
            case .frost?:
                ring(at: at, color: ArenaPalette.frost, to: 6.5)
                burst(at: at + SIMD3(0, 0.4, 0), color: ArenaPalette.frost, count: 60, speed: 5, size: 0.3, life: 0.5)
            case .potion?:
                burst(at: at + SIMD3(0, 0.6, 0), color: UIColor(red: 1, green: 0.4, blue: 0.6, alpha: 1), count: 24, speed: 1.2, size: 0.3, life: 0.6)
            case .vanish?:
                burst(at: at + SIMD3(0, 0.7, 0), color: UIColor(white: 0.85, alpha: 1), count: 40, speed: 1.4, size: 0.5, life: 0.6)
            case .ward?, .reload?:
                ring(at: at, color: ArenaPalette.gold, to: 2.2)
            default:
                break
            }
            if fighter == controller.me { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        case .hyper(let fighter):
            guard avatars.indices.contains(fighter) else { return }
            let user = game.fighters[fighter]
            let at = avatars[fighter].node.simdPosition
            ArenaSound.shared.play(.hyper, volume: fighter == controller.me ? 1 : loudness(user.pos))
            ring(at: at, color: ArenaPalette.hyper, to: 3.2)
            ring(at: at, color: .white, to: 2.2)
            burst(at: at + SIMD3(0, 0.8, 0), color: ArenaPalette.hyper, count: 70, speed: 4, size: 0.4, life: 0.6)
            burst(at: at + SIMD3(0, 0.8, 0), color: .white, count: 24, speed: 2.5, size: 0.25, life: 0.4)
            if fighter == controller.me {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                addShake(0.35)
            }
        case .emote(let fighter, let emote):
            guard avatars.indices.contains(fighter), let symbol = ArenaEmote.find(emote)?.symbol else { return }
            // 同一个人的上一个表情收起来
            for item in bubbles where item.fighter == fighter { item.node.removeFromParent() }
            bubbles.removeAll { $0.fighter == fighter }
            let node = SKSpriteNode(texture: SKTexture(image: ArenaArt.bubble(symbol)))
            node.size = CGSize(width: 60, height: 60)
            node.isHidden = true
            node.setScale(0.3)
            node.run(.scale(to: 1, duration: 0.16))
            overlay.addChild(node)
            bubbles.append((node: node, fighter: fighter, born: clock))
            if avatars[fighter].opacity > 0.1 {
                ArenaSound.shared.play(.pickup, volume: loudness(game.fighters[fighter].pos) * 0.5)
            }
        case .pickup(let fighter):
            guard avatars.indices.contains(fighter) else { return }
            ArenaSound.shared.play(.pickup, volume: loudness(game.fighters[fighter].pos))
            burst(at: avatars[fighter].node.simdPosition + SIMD3(0, 0.8, 0), color: ArenaPalette.gold, count: 16, speed: 1.6, size: 0.18, life: 0.4)
        case .respawn(let fighter):
            guard avatars.indices.contains(fighter) else { return }
            if fighter == controller.me { ArenaSound.shared.play(.respawn) }
            let color = game.fighters[fighter].team == myTeam ? ArenaPalette.blue : ArenaPalette.red
            ring(at: avatars[fighter].node.simdPosition, color: color, to: 1.8)
        }
    }

    /// 放大招：脚下一圈这个角色的颜色往外扩，身上冲起一道光柱、往外蹦光点（超级充能的是紫的）
    private func superFlash(_ caster: Fighter, at point: SIMD3<Float>, size: Float) {
        let color = caster.hyperTime > 0 ? ArenaPalette.hyper : Self.superColor(caster.brawler)
        ring(at: point, color: color, to: CGFloat(2.6 * size))
        ring(at: point, color: .white, to: CGFloat(1.6 * size))
        let tube = SCNCylinder(radius: CGFloat(0.55 * size), height: CGFloat(3.4 * size))
        tube.radialSegmentCount = 24
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = ArenaArt.beam
        glow.multiply.contents = color
        glow.blendMode = .add
        glow.writesToDepthBuffer = false
        glow.isDoubleSided = true
        let cap = SCNMaterial()
        cap.transparency = 0
        tube.materials = [glow, cap, cap]
        let beam = SCNNode(geometry: tube)
        beam.simdPosition = point + SIMD3(0, 1.7 * size, 0)
        beam.castsShadow = false
        beam.renderingOrder = 30
        beam.simdScale = SIMD3(0.6, 0.2, 0.6)
        world.rootNode.addChildNode(beam)
        beam.runAction(.sequence([.group([.scale(to: 1, duration: 0.14), .fadeOut(duration: 0.45)]), .removeFromParentNode()]))
        burst(at: point + SIMD3(0, size, 0), color: color, count: 40, speed: 3.5, size: 0.3, life: 0.5)
    }

    /// 每个角色大招的颜色
    static func superColor(_ brawler: Brawler) -> UIColor {
        switch brawler {
        case .knight: return ArenaPalette.gold
        case .ranger: return UIColor(red: 0.45, green: 0.9, blue: 1, alpha: 1)
        case .barbarian: return UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1)
        case .mage: return UIColor(red: 1, green: 0.42, blue: 0.2, alpha: 1)
        case .assassin: return UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1)
        case .guardian: return UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)
        case .necromancer: return UIColor(red: 0.45, green: 1, blue: 0.55, alpha: 1)
        case .shade: return UIColor(red: 0.62, green: 0.42, blue: 1, alpha: 1)
        case .summoner: return UIColor(red: 0.4, green: 1, blue: 0.85, alpha: 1)
        case .swordsman: return UIColor(red: 0.8, green: 0.88, blue: 1, alpha: 1)
        case .brewer: return UIColor(red: 1, green: 0.7, blue: 0.3, alpha: 1)
        case .scholar: return UIColor(red: 0.55, green: 1, blue: 0.75, alpha: 1)
        case .darter: return UIColor(red: 0.6, green: 0.6, blue: 0.65, alpha: 1)
        }
    }

    /// 表情跟着头顶走，最后 0.4 秒淡掉；人看不见了表情也藏起来
    private func syncBubbles(_ view: simd_float4x4) {
        for k in bubbles.indices.reversed() {
            let item = bubbles[k]
            let age = clock - item.born
            guard age < 2.4, avatars.indices.contains(item.fighter) else {
                item.node.removeFromParent()
                bubbles.remove(at: k)
                continue
            }
            let avatar = avatars[item.fighter]
            let head = avatar.node.simdPosition + SIMD3(0, (ArenaAvatar.headHeight + 0.8) * avatar.size, 0)
            if avatar.opacity > 0.1, let point = project(head, view) {
                item.node.isHidden = false
                item.node.position = point
                item.node.alpha = age > 2 ? CGFloat((2.4 - age) / 0.4) : 1
            } else {
                item.node.isHidden = true
            }
        }
    }

    /// 离自己越远声音越小
    private func loudness(_ point: V2) -> Float {
        let distance = Float(point.distance(to: controller.mine.pos))
        return 1 / (1 + distance / 5)
    }

    /// 一下子炸开的一团光点
    private func burst(at point: SIMD3<Float>, color: UIColor, count: CGFloat, speed: CGFloat, size: CGFloat, life: CGFloat) {
        let system = SCNParticleSystem()
        system.loops = false
        system.emissionDuration = 0.05
        system.birthRate = count / 0.05
        system.particleLifeSpan = life
        system.particleLifeSpanVariation = life * 0.3
        system.particleVelocity = speed
        system.particleVelocityVariation = speed * 0.5
        system.spreadingAngle = 180
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.particleSize = size
        system.particleSizeVariation = size * 0.4
        system.particleColor = color
        system.particleImage = ArenaArt.dot
        system.blendMode = .additive
        system.isAffectedByGravity = false
        system.dampingFactor = 2
        system.propertyControllers = [.opacity: Self.fadeOut]
        let holder = SCNNode()
        holder.simdPosition = point
        holder.addParticleSystem(system)
        world.rootNode.addChildNode(holder)
        holder.runAction(.sequence([.wait(duration: Double(life) * 1.4 + 0.2), .removeFromParentNode()]))
    }

    /// 打中的地方：一下亮光，几颗火星往外蹦
    private func spark(at point: SIMD3<Float>) {
        burst(at: point, color: UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1), count: 14, speed: 3.5, size: 0.13, life: 0.22)
        let flash = halo("spark", UIColor(red: 1, green: 0.88, blue: 0.5, alpha: 1), size: 1.1)
        flash.simdPosition = point
        flash.simdScale = SIMD3(repeating: 0.4)
        world.rootNode.addChildNode(flash)
        flash.runAction(.sequence([.group([.scale(to: 1.2, duration: 0.12), .fadeOut(duration: 0.16)]), .removeFromParentNode()]))
    }

    /// 子弹后面拖的尾巴
    private func trail(_ color: UIColor, size: CGFloat, life: CGFloat = 0.3) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.loops = true
        system.birthRate = 70
        system.particleLifeSpan = life
        system.particleVelocity = 0.2
        system.spreadingAngle = 180
        system.particleSize = size
        system.particleColor = color
        system.particleImage = ArenaArt.dot
        system.blendMode = .additive
        system.propertyControllers = [.opacity: Self.fadeOut]
        return system
    }

    /// 地上一个往外扩的圈（放大招、复活）
    private func ring(at point: SIMD3<Float>, color: UIColor, to scale: CGFloat) {
        let tube = SCNTube(innerRadius: 0.45, outerRadius: 0.6, height: 0.02)
        tube.radialSegmentCount = 40
        tube.firstMaterial = ArenaAvatar.decal(color.withAlphaComponent(0.9))
        let node = SCNNode(geometry: tube)
        node.simdPosition = SIMD3(point.x, 0.06, point.z)
        node.castsShadow = false
        node.renderingOrder = 9
        world.rootNode.addChildNode(node)
        node.runAction(.sequence([.group([.scale(to: scale, duration: 0.35), .fadeOut(duration: 0.35)]), .removeFromParentNode()]))
    }

    private static let fadeOut: SCNParticlePropertyController = {
        let animation = CAKeyframeAnimation()
        animation.values = [1, 0.8, 0]
        animation.keyTimes = [0, 0.4, 1]
        return SCNParticlePropertyController(animation: animation)
    }()

    // MARK: - 亡灵之地、骨塔

    /// 亡灵之地：地上一个发光的圈，自己这边绿、对面紫，冒着光点
    private func syncHealZones(_ game: ArenaGame) {
        while zoneNodes.count < game.zones.count {
            let node = SCNNode()
            let disc = SCNNode(geometry: SCNCylinder(radius: 1, height: 0.01))
            disc.castsShadow = false
            disc.renderingOrder = 3
            disc.name = "disc"
            let rim = SCNNode(geometry: SCNTube(innerRadius: 0.95, outerRadius: 1, height: 0.02))
            rim.castsShadow = false
            rim.renderingOrder = 3
            rim.name = "rim"
            node.addChildNode(disc)
            node.addChildNode(rim)
            let motes = SCNParticleSystem()
            motes.birthRate = 40
            motes.particleLifeSpan = 0.9
            motes.particleVelocity = 1
            motes.emittingDirection = SCNVector3(0, 1, 0)
            motes.spreadingAngle = 10
            motes.particleSize = 0.12
            motes.particleImage = ArenaArt.dot
            motes.blendMode = .additive
            motes.emitterShape = SCNCylinder(radius: 1, height: 0.01)
            motes.birthLocation = .surface
            motes.propertyControllers = [.opacity: Self.fadeOut]
            node.addParticleSystem(motes)
            world.rootNode.addChildNode(node)
            zoneNodes.append(node)
        }
        while zoneNodes.count > game.zones.count {
            zoneNodes.removeLast().removeFromParentNode()
        }
        for (k, zone) in game.zones.enumerated() {
            let node = zoneNodes[k]
            let radius = Float(zone.radius)
            node.simdPosition = SIMD3(Float(zone.center.x), 0.03, Float(zone.center.y))
            node.simdScale = SIMD3(radius, 1, radius)
            let color = zone.team == myTeam ? UIColor(red: 0.35, green: 0.95, blue: 0.5, alpha: 1) : UIColor(red: 0.75, green: 0.35, blue: 1, alpha: 1)
            let key = zone.team == myTeam ? "ally" : "enemy"
            if node.name != key {
                node.name = key
                node.childNode(withName: "disc", recursively: false)?.geometry?.firstMaterial = ArenaAvatar.decal(color.withAlphaComponent(0.25))
                node.childNode(withName: "rim", recursively: false)?.geometry?.firstMaterial = ArenaAvatar.decal(color.withAlphaComponent(0.85))
                node.particleSystems?.first?.particleColor = color
            }
            // 快没了的时候淡出
            node.opacity = CGFloat(min(1, zone.left / 0.5))
        }
    }

    /// 骨塔：插在地上的骨杖，顶上一团光，头顶一条血
    private func syncTurrets(_ game: ArenaGame, view: simd_float4x4) {
        var seen = Set<Int>()
        for turret in game.turrets {
            seen.insert(turret.id)
            let item = turretViews[turret.id] ?? makeTurret(turret)
            turretViews[turret.id] = item
            item.node.simdPosition = SIMD3(Float(turret.pos.x), 0, Float(turret.pos.y))
            let bob = Float(sin(clock * 3 + Double(turret.id))) * 0.06
            item.head.simdPosition = SIMD3(0, 2.0 + bob, 0)
            if let point = project(item.node.simdPosition + SIMD3(0, 2.4, 0), view) {
                item.bar.node.isHidden = false
                item.bar.node.position = point
                item.bar.set(CGFloat(turret.health) / CGFloat(max(turret.maxHealth, 1)))
            } else {
                item.bar.node.isHidden = true
            }
        }
        for (id, item) in turretViews where !seen.contains(id) {
            burst(at: item.node.simdPosition + SIMD3(0, 0.8, 0), color: UIColor(white: 0.9, alpha: 1), count: 20, speed: 1.5, size: 0.3, life: 0.5)
            item.node.removeFromParentNode()
            item.bar.node.removeFromParent()
            turretViews[id] = nil
        }
    }

    private func makeTurret(_ turret: ArenaGame.Turret) -> TurretView {
        let ally = turret.team == myTeam
        let color = ally ? ArenaPalette.blue : ArenaPalette.red
        let node = SCNNode()
        if let staff = ArenaModels.shared.prop("Skeleton_Staff.gltf") {
            // 骨杖竖着插在地上（模型握把在原点，往下 0.85、往上 1.26），骷髅头朝上
            let piece = staff.instantiate(shareMaterials: true, outline: ArenaArt.outline).root
            piece.simdScale = SIMD3(repeating: 0.85)
            piece.simdPosition = SIMD3(0, 0.72, 0)
            node.addChildNode(piece)
        } else {
            let pole = SCNNode(geometry: SCNCylinder(radius: 0.08, height: 1.4))
            pole.geometry?.firstMaterial = ArenaAvatar.material(UIColor(red: 0.85, green: 0.8, blue: 0.7, alpha: 1), lit: true)
            pole.simdPosition = SIMD3(0, 0.7, 0)
            node.addChildNode(pole)
        }
        let orb = SCNSphere(radius: 0.18)
        orb.segmentCount = 12
        orb.firstMaterial = ArenaAvatar.material(ally ? UIColor(red: 0.5, green: 0.85, blue: 1, alpha: 1) : UIColor(red: 1, green: 0.5, blue: 0.4, alpha: 1), lit: false)
        let head = SCNNode(geometry: orb)
        head.castsShadow = false
        head.addParticleSystem(trail(ally ? ArenaPalette.allyShot : ArenaPalette.enemyShot, size: 0.25))
        node.addChildNode(head)
        let base = SCNNode(geometry: SCNTube(innerRadius: 0.36, outerRadius: 0.46, height: 0.012))
        base.geometry?.firstMaterial = ArenaAvatar.decal(color.withAlphaComponent(0.85))
        base.simdPosition = SIMD3(0, 0.03, 0)
        base.castsShadow = false
        node.addChildNode(base)
        world.rootNode.addChildNode(node)
        burst(at: SIMD3(Float(turret.pos.x), 0.5, Float(turret.pos.y)), color: color, count: 20, speed: 1.5, size: 0.3, life: 0.5)
        let bar = ArenaBar(width: 40, height: 7, color: color, border: 1.2)
        bar.node.isHidden = true
        overlay.addChild(bar.node)
        return TurretView(node: node, head: head, bar: bar)
    }

    // MARK: - 伤害数字

    private func floater(_ text: String, at point: SIMD3<Float>, color: UIColor) {
        // 同样的数字、颜色只画一次
        let key = "\(text)-\(color.hash)"
        let made: (texture: SKTexture, size: CGSize)
        if let cached = numberTextures[key] {
            made = cached
        } else {
            let image = ArenaArt.text(text, size: 17, color: color)
            made = (SKTexture(image: image), image.size)
            if numberTextures.count > 150 { numberTextures.removeAll() }
            numberTextures[key] = made
        }
        let label = SKSpriteNode(texture: made.texture, color: .white, size: made.size)
        label.isHidden = true
        overlay.addChild(label)
        floaters.append(Floater(label: label, at: point, born: clock))
        if floaters.count > 40 { floaters.removeFirst().label.removeFromParent() }
    }

    private func syncFloaters(_ view: simd_float4x4) {
        floaters.removeAll { floater in
            let age = clock - floater.born
            guard age < 0.75 else {
                floater.label.removeFromParent()
                return true
            }
            let rise = Float(age) * 1.1
            if let point = project(floater.at + SIMD3(0, rise, 0), view) {
                floater.label.isHidden = false
                floater.label.position = point
                floater.label.alpha = CGFloat(age < 0.4 ? 1 : 1 - (age - 0.4) / 0.35)
                floater.label.setScale(age < 0.08 ? CGFloat(0.6 + age * 5) : 1)
            } else {
                floater.label.isHidden = true
            }
            return false
        }
    }

    // MARK: - 瞄准

    /// 拖着攻击 / 大招摇杆时，地上画出会打到哪
    private func syncAim(_ fighter: Fighter) {
        guard fighter.alive, let drag = controller.superAiming ?? controller.aiming else {
            aimNode.isHidden = true
            return
        }
        let isSuper = controller.superAiming != nil
        let brawler = fighter.brawler
        let range = isSuper ? brawler.superRange : brawler.attackRange
        let direction = drag.length > 0.25 ? drag.normalized : fighter.facing
        // 路径画在 x、-z 平面上（节点转了 -90 度躺平）
        func flat(_ v: V2) -> CGPoint { CGPoint(x: v.x, y: -v.y) }
        let path = UIBezierPath()
        // 落在一个点上的（扔火球、跳、亡灵之地、闪现、骨塔）画落点的圈和一条线
        let lobbing = brawler == .mage || brawler == .brewer && !isSuper
            || (isSuper && [.barbarian, .necromancer, .shade, .summoner].contains(brawler))
        // 给自己（身边一圈）的：骨盾、豪饮、烟雾弹、护盾书；剑圣转圈砍、书灵的灵光也是身边一圈
        let selfRadius: Double? = {
            if isSuper { return [.guardian, .brewer, .darter].contains(brawler) ? 0.9 : (brawler == .scholar ? range : nil) }
            return brawler == .swordsman || brawler == .scholar ? range : nil
        }()
        if let selfRadius {
            path.append(UIBezierPath(ovalIn: CGRect(x: -selfRadius, y: -selfRadius, width: selfRadius * 2, height: selfRadius * 2)))
        } else if lobbing {
            let distance = max(drag.length, 0.35) * range
            let target = direction * distance
            let blast: Double
            switch brawler {
            case .mage: blast = isSuper ? 2.2 : 1.2
            case .brewer: blast = 1.3
            case .necromancer: blast = 2.2
            case .summoner: blast = 0.6
            default: blast = 1.6
            }
            path.append(UIBezierPath(ovalIn: CGRect(x: target.x - blast, y: -target.y - blast, width: blast * 2, height: blast * 2)))
            let side = V2(-direction.y, direction.x) * 0.06
            let line = UIBezierPath()
            line.move(to: flat(side))
            line.addLine(to: flat(target + side))
            line.addLine(to: flat(target - side))
            line.addLine(to: flat(side * -1))
            line.close()
            path.append(line)
        } else {
            // 散开打的画一个扇形，一条直线打的画一条
            let spread: Double
            switch (brawler, isSuper) {
            case (.knight, false): spread = 0.3
            case (.barbarian, false): spread = 0.5
            case (.assassin, true): spread = 0.56
            case (.summoner, false): spread = 0.17
            default: spread = 0
            }
            if spread > 0 {
                path.move(to: .zero)
                for k in 0...12 {
                    let angle = -spread + 2 * spread * Double(k) / 12
                    path.addLine(to: flat(direction.rotated(by: angle) * range))
                }
                path.close()
            } else {
                let half: Double
                switch brawler {
                case .knight: half = ArenaGame.fighterRadius
                case .guardian: half = 0.5
                case .necromancer: half = 0.32
                default: half = isSuper ? 0.35 : 0.22
                }
                let side = V2(-direction.y, direction.x) * half
                let end = direction * range
                path.move(to: flat(side))
                path.addLine(to: flat(end + side))
                path.addLine(to: flat(end - side))
                path.addLine(to: flat(side * -1))
                path.close()
            }
        }
        path.flatness = 0.03
        let shape = SCNShape(path: path, extrusionDepth: 0)
        shape.firstMaterial = ArenaAvatar.decal((isSuper ? ArenaPalette.gold : UIColor.white).withAlphaComponent(0.3))
        aimNode.geometry = shape
        aimNode.simdPosition = SIMD3(Float(fighter.pos.x), 0.07, Float(fighter.pos.y))
        aimNode.isHidden = false
    }
}

/// 每种地图的样子：都是亮绿的草地，主题换的是地上一块块的颜色（沙土、石板、深一点的草）、阳光、墙用哪几种（各占几成）
private struct ThemeLook {
    let floor: UIColor
    let floorDark: UIColor
    /// 地上一块块颜色不一样的地方
    let patch: UIColor
    let bushGround: UIColor
    let lawn: UIColor
    let sunlight: UIColor
    let flowers: Bool
    let walls: [(kind: ArenaArt.Wall, weight: Int)]

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    static func of(_ theme: ArenaMap.Theme) -> ThemeLook {
        switch theme {
        case .sand:
            return ThemeLook(floor: color(0.58, 0.79, 0.30), floorDark: color(0.54, 0.75, 0.28), patch: color(0.93, 0.80, 0.52),
                             bushGround: color(0.33, 0.55, 0.22), lawn: color(0.45, 0.67, 0.26), sunlight: color(1.0, 0.97, 0.9),
                             flowers: false, walls: [(kind: .crate, weight: 7), (kind: .barrel, weight: 3)])
        case .meadow:
            return ThemeLook(floor: color(0.53, 0.80, 0.31), floorDark: color(0.49, 0.76, 0.29), patch: color(0.36, 0.62, 0.22),
                             bushGround: color(0.30, 0.53, 0.21), lawn: color(0.42, 0.66, 0.25), sunlight: color(1.0, 0.98, 0.92),
                             flowers: true, walls: [(kind: .crate, weight: 5), (kind: .barrel, weight: 5)])
        case .stone:
            return ThemeLook(floor: color(0.52, 0.77, 0.34), floorDark: color(0.48, 0.73, 0.32), patch: color(0.74, 0.74, 0.70),
                             bushGround: color(0.31, 0.52, 0.24), lawn: color(0.42, 0.64, 0.28), sunlight: color(0.96, 0.98, 1.0),
                             flowers: false, walls: [(kind: .stone, weight: 6), (kind: .crate, weight: 4)])
        case .dusk:
            return ThemeLook(floor: color(0.60, 0.77, 0.30), floorDark: color(0.56, 0.73, 0.28), patch: color(0.82, 0.63, 0.38),
                             bushGround: color(0.34, 0.52, 0.22), lawn: color(0.47, 0.64, 0.26), sunlight: color(1.0, 0.88, 0.72),
                             flowers: false, walls: [(kind: .crate, weight: 5), (kind: .barrel, weight: 5)])
        }
    }
}

/// CADisplayLink 会一直拉着它的 target，用这个小东西隔开，画面不用了能正常释放
@MainActor
private final class DisplayTarget: NSObject {
    weak var view: ArenaWorldView?

    init(view: ArenaWorldView) {
        self.view = view
        super.init()
    }

    @objc func tick(_ link: CADisplayLink) {
        view?.tick(link.timestamp)
    }
}
