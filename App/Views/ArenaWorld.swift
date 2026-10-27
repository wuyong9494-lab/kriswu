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
/// 坐标：地图上的 (x, y) 格就是 3D 里的 (x, 0, y)，一格 1 米；在上边那一队的人看到的整个转过来（自己家总在下边）
@MainActor
final class ArenaWorldView: SCNView {
    /// 镜头在看的那一点的斜上方多远（高 18、往屏幕下方 11，往下看大约 59 度）
    private static let cameraOffset = SIMD3<Float>(0, 18, 11)
    /// 竖屏时自己这一排左右看得到多宽：tan(半个视角)，自己身边左右各大约 5 格
    private static let sideView: Float = 0.267
    /// 镜头往自己前面（屏幕上方）多看几格
    private static let lookAhead = 3.0

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

    private struct TurretView {
        let node: SCNNode
        let head: SCNNode
        let bar: SKNode
        let fill: SKSpriteNode
    }

    private struct ProjectileView {
        let root: SCNNode
        /// 扔出去的炸弹：天上的球、地上的影子
        var ball: SCNNode?
        var shadow: SCNNode?
    }

    /// 飘起来的伤害数字
    private struct Floater {
        let label: SKLabelNode
        let at: SIMD3<Float>
        let born: Double
    }

    init(controller: ArenaController) {
        self.controller = controller
        super.init(frame: .zero, options: nil)
        backgroundColor = ArenaPalette.grass
        antialiasingMode = .multisampling4X
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
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // 竖屏（窄）时左右看得到的宽度固定；横屏、iPad 上下看得到的固定，左右多看一些
        let aspect = Float(bounds.width / bounds.height)
        tanY = Self.sideView / min(max(aspect, 0.3), 0.6)
        tanX = tanY * aspect
        cameraNode.camera?.fieldOfView = CGFloat(2 * atan(tanY) * 180 / .pi)
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
        cameraNode.camera = camera
        cameraNode.simdPosition = Self.cameraOffset
        cameraNode.simdEulerAngles = SIMD3(-atan2(Self.cameraOffset.y, Self.cameraOffset.z), 0, 0)
        rig.addChildNode(cameraNode)
        rig.simdEulerAngles = SIMD3(0, flipped ? .pi : 0, 0)
        root.addChildNode(rig)

        // 光：环境光，加一盏斜着照、投影子的“太阳”（也装在架子上，两队看到的光一样）
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 450
        ambient.light?.color = UIColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 1)
        root.addChildNode(ambient)
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 650
        sun.color = look.sunlight
        sun.castsShadow = true
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.shadowSampleCount = 4
        sun.shadowRadius = 2
        sun.shadowColor = UIColor(white: 0, alpha: 0.3)
        sun.automaticallyAdjustsShadowProjection = true
        sun.maximumShadowDistance = 50
        let sunNode = SCNNode()
        sunNode.light = sun
        let toward = simd_normalize(SIMD3<Float>(0.35, -1, -0.45))
        sunNode.simdOrientation = simd_quatf(from: SIMD3(0, 0, -1), to: toward)
        sunNode.simdPosition = -toward * 20
        rig.addChildNode(sunNode)

        // 地：场地外一大片草，场地一格格的
        let lawn = SCNPlane(width: CGFloat(width + 160), height: CGFloat(height + 160))
        lawn.firstMaterial = ArenaAvatar.material(look.lawn, lit: true)
        let lawnNode = SCNNode(geometry: lawn)
        lawnNode.simdEulerAngles = SIMD3(-Float.pi / 2, 0, 0)
        lawnNode.simdPosition = SIMD3(width / 2, -0.02, height / 2)
        lawnNode.castsShadow = false
        root.addChildNode(lawnNode)
        let floor = SCNPlane(width: CGFloat(width), height: CGFloat(height))
        let floorMaterial = SCNMaterial()
        floorMaterial.lightingModel = .lambert
        floorMaterial.diffuse.contents = groundImage(game, look: look)
        floorMaterial.diffuse.mipFilter = .linear
        floor.firstMaterial = floorMaterial
        let floorNode = SCNNode(geometry: floor)
        floorNode.simdEulerAngles = SIMD3(-Float.pi / 2, 0, 0)
        floorNode.simdPosition = SIMD3(width / 2, 0, height / 2)
        floorNode.castsShadow = false
        root.addChildNode(floorNode)
        root.addChildNode(border(map))

        // 墙：箱子、桶；草丛
        root.addChildNode(walls(map, look: look))
        let leafy = bushGeometry(ArenaPalette.bush)
        let leafyDark = bushGeometry(ArenaPalette.bushDark)
        for y in 0..<map.height {
            for x in 0..<map.width where map.tile(x, y) == .bush {
                let node = SCNNode(geometry: (x + y) % 3 == 0 ? leafyDark : leafy)
                node.simdPosition = SIMD3(Float(x) + 0.5, 0, Float(y) + 0.5)
                node.simdEulerAngles = SIMD3(0, Float((x * 7 + y * 13) % 12) * .pi / 6, 0)
                let size = 1 + Float((x * 5 + y * 3) % 4) * 0.04
                node.simdScale = SIMD3(size, size, size)
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
        case .showdown:
            // 毒圈：圈外一圈半透明的绿墙，边上一道亮线
            let radius = game.safeRadius
            let wall = SCNTube(innerRadius: CGFloat(radius), outerRadius: CGFloat(radius + 80), height: 1.6)
            wall.radialSegmentCount = 96
            let gas = ArenaAvatar.decal(ArenaPalette.poison.withAlphaComponent(0.38))
            wall.firstMaterial = gas
            let wallNode = SCNNode(geometry: wall)
            wallNode.simdPosition = center + SIMD3(0, 0.8, 0)
            wallNode.castsShadow = false
            wallNode.renderingOrder = 20
            let edge = SCNTube(innerRadius: CGFloat(radius), outerRadius: CGFloat(radius + 0.1), height: 1.7)
            edge.radialSegmentCount = 96
            edge.firstMaterial = ArenaAvatar.decal(UIColor(red: 0.6, green: 1, blue: 0.5, alpha: 0.9))
            let edgeNode = SCNNode(geometry: edge)
            edgeNode.simdPosition = center + SIMD3(0, 0.85, 0)
            edgeNode.castsShadow = false
            edgeNode.renderingOrder = 21
            root.addChildNode(wallNode)
            root.addChildNode(edgeNode)
            poison = (wall, edge, radius)
        case .teamFight:
            break
        }

        // 人：自己这边蓝、对面红（大乱斗除了自己都是红）
        for fighter in game.fighters {
            let isMe = fighter.id == controller.me
            let color = fighter.team == myTeam ? ArenaPalette.blue : ArenaPalette.red
            let avatar = ArenaAvatar(brawler: fighter.brawler, color: color, isMe: isMe)
            root.addChildNode(avatar.node)
            avatars.append(avatar)
            let tag = ArenaTag(fighter: fighter, isMe: isMe, color: color)
            overlay.addChild(tag.node)
            tags.append(tag)
        }

        aimNode.simdEulerAngles = SIMD3(-Float.pi / 2, 0, 0)
        aimNode.renderingOrder = 30
        aimNode.castsShadow = false
        aimNode.isHidden = true
        root.addChildNode(aimNode)
    }

    /// 场地的地面：浅浅的棋盘格，两队家门口带一点队伍的颜色
    private func groundImage(_ game: ArenaGame, look: ThemeLook) -> UIImage {
        let map = game.map
        let cell: CGFloat = 64
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: CGFloat(map.width) * cell, height: CGFloat(map.height) * cell)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            for y in 0..<map.height {
                for x in 0..<map.width {
                    let color: UIColor
                    switch map.tile(x, y) {
                    case .bush: color = look.bushGround
                    case .wall: color = look.floorDark
                    case .floor: color = (x + y) % 2 == 0 ? look.floor : look.floorDark
                    }
                    cg.setFillColor(color.cgColor)
                    cg.fill(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
                }
            }
            if game.mode.isTeams, map.spawns.count == 2 {
                for (team, spots) in map.spawns.enumerated() {
                    let tint = (team == myTeam ? ArenaPalette.blue : ArenaPalette.red).withAlphaComponent(0.22)
                    cg.setFillColor(tint.cgColor)
                    for spot in spots {
                        let r = cell * 0.55
                        cg.fillEllipse(in: CGRect(x: CGFloat(spot.x) * cell - r, y: CGFloat(spot.y) * cell - r, width: r * 2, height: r * 2))
                    }
                }
            }
            cg.setStrokeColor(UIColor(white: 0, alpha: 0.18).cgColor)
            cg.setLineWidth(6)
            cg.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3))
        }
    }

    /// 场地四周一圈矮石沿
    private func border(_ map: ArenaMap) -> SCNNode {
        let width = Float(map.width), height = Float(map.height)
        let stone = ArenaAvatar.material(UIColor(red: 0.78, green: 0.74, blue: 0.68, alpha: 1), lit: true)
        let holder = SCNNode()
        let pieces: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(width / 2, 0.1, -0.15), SIMD3(width + 0.6, 0.2, 0.3)),
            (SIMD3(width / 2, 0.1, height + 0.15), SIMD3(width + 0.6, 0.2, 0.3)),
            (SIMD3(-0.15, 0.1, height / 2), SIMD3(0.3, 0.2, height)),
            (SIMD3(width + 0.15, 0.1, height / 2), SIMD3(0.3, 0.2, height)),
        ]
        for (at, size) in pieces {
            let box = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0.04)
            box.firstMaterial = stone
            let node = SCNNode(geometry: box)
            node.simdPosition = at
            holder.addChildNode(node)
        }
        return holder.flattenedClone()
    }

    /// 墙：按地图的样子挑箱子、桶、矮树丛（同一格每次都一样）
    private func walls(_ map: ArenaMap, look: ThemeLook) -> SCNNode {
        let pieces = look.walls.map { (model: ArenaModels.shared.prop($0.file), scale: $0.scale, weight: $0.weight) }
        let total = max(pieces.reduce(0) { $0 + $1.weight }, 1)
        let fallback = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.06)
        fallback.firstMaterial = ArenaAvatar.material(UIColor(red: 0.62, green: 0.45, blue: 0.3, alpha: 1), lit: true)
        let holder = SCNNode()
        for y in 0..<map.height {
            for x in 0..<map.width where map.tile(x, y) == .wall {
                let pick = (x * 37 + y * 61 + x * y) % total
                var left = pick
                let piece = pieces.first { left -= $0.weight; return left < 0 } ?? pieces.first
                let node: SCNNode
                if let piece, let model = piece.model {
                    node = model.instantiate(shareMaterials: true).root
                    node.simdScale = SIMD3(repeating: piece.scale)
                } else {
                    node = SCNNode(geometry: fallback)
                    node.simdPosition = SIMD3(0, 0.5, 0)
                }
                let cell = SCNNode()
                cell.addChildNode(node)
                cell.simdPosition = SIMD3(Float(x) + 0.5, 0, Float(y) + 0.5)
                cell.simdEulerAngles = SIMD3(0, Float(pick % 4) * .pi / 2, 0)
                holder.addChildNode(cell)
            }
        }
        return holder.flattenedClone()
    }

    /// 草丛：几个低多边形的绿球挤在一起
    private func bushGeometry(_ color: UIColor) -> SCNGeometry {
        let material = ArenaAvatar.material(color, lit: true)
        let holder = SCNNode()
        let balls: [(SIMD3<Float>, CGFloat)] = [
            (SIMD3(0, 0.42, 0), 0.52), (SIMD3(0.24, 0.6, 0.14), 0.38),
            (SIMD3(-0.22, 0.62, -0.1), 0.36), (SIMD3(0.04, 0.78, -0.18), 0.3),
        ]
        for (at, radius) in balls {
            let sphere = SCNSphere(radius: radius)
            sphere.segmentCount = 10
            sphere.firstMaterial = material
            let node = SCNNode(geometry: sphere)
            node.simdPosition = at
            node.simdScale = SIMD3(1, 0.85, 1)
            holder.addChildNode(node)
        }
        return holder.flattenedClone().geometry ?? SCNSphere(radius: 0.5)
    }

    /// 场地外：两排树、几块石头，分队玩法两头插上两队的旗子
    private func scenery(_ game: ArenaGame) -> SCNNode {
        let map = game.map
        let width = Double(map.width), height = Double(map.height)
        let models = ArenaModels.shared
        let trees = ["trees_A_small.gltf", "trees_A_medium.gltf", "trees_A_large.gltf",
                     "trees_B_small.gltf", "trees_B_medium.gltf", "trees_B_large.gltf"].compactMap { models.prop($0) }
        let rocks = ["rock_single_A.gltf", "rock_single_B.gltf", "rock_single_C.gltf"].compactMap { models.prop($0) }
        var random = SeededRandom(seed: 2026)
        let holder = SCNNode()
        func place(_ model: GLTFModel, at point: V2, scale: Float, turn: Float) {
            let node = model.instantiate(shareMaterials: true).root
            node.simdPosition = SIMD3(Float(point.x), 0, Float(point.y))
            node.simdScale = SIMD3(repeating: scale)
            node.simdEulerAngles = SIMD3(0, turn, 0)
            holder.addChildNode(node)
        }
        // 沿四边，离场地 1.4 格、3.4 格各一排，错开
        for row in 0..<3 {
            let gap = 1.4 + Double(row) * 2.1
            let step = 1.9
            var edge: [V2] = []
            var t = -gap + Double(row % 2) * step / 2
            while t <= width + gap {
                edge.append(V2(t, -gap))
                edge.append(V2(t, height + gap))
                t += step
            }
            t = Double(row % 2) * step / 2
            while t <= height {
                edge.append(V2(-gap, t))
                edge.append(V2(width + gap, t))
                t += step
            }
            for point in edge where !trees.isEmpty {
                let jitter = V2(Double(random.below(60)) / 100 - 0.3, Double(random.below(60)) / 100 - 0.3)
                place(trees[random.below(trees.count)], at: point + jitter, scale: 1.25 + Float(random.below(40)) / 100,
                      turn: Float(random.below(6)) * .pi / 3)
            }
        }
        // 石头：贴着场地边上
        for _ in 0..<14 where !rocks.isEmpty {
            let side = random.below(4)
            let along = Double(random.below(1000)) / 1000
            let point: V2
            switch side {
            case 0: point = V2(along * width, -0.6)
            case 1: point = V2(along * width, height + 0.6)
            case 2: point = V2(-0.6, along * height)
            default: point = V2(width + 0.6, along * height)
            }
            place(rocks[random.below(rocks.count)], at: point, scale: 2.4 + Float(random.below(15)) / 10, turn: Float(random.below(628)) / 100)
        }
        // 旗子：插在两队家后面
        if game.mode.isTeams, let blue = models.prop("flag_blue.gltf"), let red = models.prop("flag_red.gltf") {
            for (team, z) in [(1, -0.9), (0, height + 0.9)] {
                let flag = team == myTeam ? blue : red
                for x in [2.5, width - 2.5] {
                    place(flag, at: V2(x, z), scale: 4, turn: team == 0 ? .pi : 0)
                }
            }
        }
        return holder.flattenedClone()
    }

    // MARK: - 每帧摆一遍

    private func sync(dt: Float) {
        let game = controller.game
        moveCamera(dt: dt, game: game)
        let view = cameraNode.simdWorldTransform.inverse

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
            let avatar = avatars[fighter.id]
            let visible = game.isVisible(fighter, to: myTeam)
            let hidden = fighter.team == myTeam && game.map.inBush(fighter.pos)
            avatar.update(fighter, visible: visible, translucent: hidden, cheering: winners(fighter), dt: dt, clock: clock)
            let head = avatar.node.simdPosition + SIMD3(0, ArenaAvatar.headHeight, 0)
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
        if var current = poison, abs(current.radius - game.safeRadius) > 0.02 {
            current.radius = game.safeRadius
            current.wall.outerRadius = CGFloat(current.radius + 80)
            current.wall.innerRadius = CGFloat(current.radius)
            current.edge.outerRadius = CGFloat(current.radius + 0.1)
            current.edge.innerRadius = CGFloat(current.radius)
            poison = current
        }

        for event in controller.takeEvents() { effect(event, game: game) }
        syncFloaters(view)
        syncAim(me)
    }

    /// 镜头跟着自己（往前多看几格；走到边上就不再往外跟，免得看到一大片场外）
    private func moveCamera(dt: Float, game: ArenaGame) {
        let map = game.map
        let width = Double(map.width), height = Double(map.height)
        let me = controller.mine.pos
        // 换成“屏幕上的方向”算：上边那一队的人看到的整个倒过来
        var screen = flipped ? V2(width - me.x, height - me.y) : me
        let side = 3.6
        screen.x = width > side * 2 ? min(max(screen.x, side), width - side) : width / 2
        screen.y = min(screen.y, height - 5) - Self.lookAhead
        let target = flipped ? V2(width - screen.x, height - screen.y) : screen
        let goal = SIMD3(Float(target.x), 0, Float(target.y))
        if cameraPlaced {
            rig.simdPosition += (goal - rig.simdPosition) * min(1, dt * 7)
        } else {
            rig.simdPosition = goal
            cameraPlaced = true
        }
    }

    /// 3D 里的一点在上面那层（SpriteKit，左下角是原点）的哪里；在镜头后面返回 nil
    private func project(_ point: SIMD3<Float>, _ view: simd_float4x4) -> CGPoint? {
        let c = view * SIMD4(point, 1)
        guard c.z < -0.5 else { return nil }
        let x = c.x / -c.z / tanX
        let y = c.y / -c.z / tanY
        return CGPoint(x: CGFloat(x + 1) / 2 * bounds.width, y: CGFloat(y + 1) / 2 * bounds.height)
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
        let tint = p.isSuper ? ArenaPalette.gold : (p.team == myTeam ? ArenaPalette.allyShot : ArenaPalette.enemyShot)
        let tintKey = p.isSuper ? "gold" : (p.team == myTeam ? "ally" : "enemy")
        if let lob = p.lob {
            // 扔出去的火球：天上的球、地上的影子、落点的圈
            let root = SCNNode()
            let radius: CGFloat = p.isSuper ? 0.45 : 0.25
            let ball = SCNNode(geometry: shared("ball-\(tintKey)-\(p.isSuper)") {
                let sphere = SCNSphere(radius: radius)
                sphere.segmentCount = 14
                sphere.firstMaterial = ArenaAvatar.material(p.isSuper ? UIColor.orange : tint, lit: false)
                return sphere
            })
            ball.castsShadow = false
            ball.addParticleSystem(trail(p.isSuper ? UIColor.orange : tint, size: p.isSuper ? 0.5 : 0.3))
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
                sphere.firstMaterial = ArenaAvatar.material(tint, lit: false)
                return sphere
            }
            piece.addParticleSystem(trail(UIColor(red: 0.5, green: 1, blue: 0.6, alpha: 1), size: 0.35))
        case .knight, .barbarian, .guardian:
            let wide: CGFloat = owner == .knight ? 0.55 : (owner == .guardian ? 1.0 : 0.8)
            piece.geometry = shared("slash-\(owner.rawValue)-\(tintKey)") {
                let box = SCNBox(width: wide, height: 0.06, length: 0.16, chamferRadius: 0.03)
                box.firstMaterial = ArenaAvatar.material(tint, lit: false)
                return box
            }
        default:
            let thick: CGFloat = p.isSuper ? 0.12 : (owner == .assassin ? 0.045 : 0.06)
            let long: CGFloat = p.isSuper ? 1.2 : (owner == .assassin ? 0.42 : 0.7)
            piece.geometry = shared("bolt-\(owner.rawValue)-\(tintKey)-\(p.isSuper)") {
                let capsule = SCNCapsule(capRadius: thick, height: long)
                capsule.firstMaterial = ArenaAvatar.material(tint, lit: false)
                return capsule
            }
            piece.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        }
        piece.castsShadow = false
        let root = SCNNode()
        root.addChildNode(piece)
        root.simdEulerAngles = SIMD3(0, atan2(Float(p.velocity.x), Float(p.velocity.y)), 0)
        root.simdPosition = SIMD3(Float(p.pos.x), 0.6, Float(p.pos.y))
        if p.isSuper { root.addParticleSystem(trail(tint, size: 0.35)) }
        world.rootNode.addChildNode(root)
        return ProjectileView(root: root)
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
            avatars[target].flash(clock: clock)
            let at = avatars[target].node.simdPosition
            burst(at: at + SIMD3(0, 0.7, 0), color: .white, count: 10, speed: 2.5, size: 0.12, life: 0.25)
            floater("\(amount)", at: at + SIMD3(Float.random(in: -0.25...0.25), ArenaAvatar.headHeight + 0.35, 0),
                    color: game.fighters[target].team == myTeam ? UIColor(red: 1, green: 0.45, blue: 0.4, alpha: 1) : .white)
        case .explosion(let point, let radius):
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
            burst(at: avatars[target].node.simdPosition + SIMD3(0, 0.6, 0), color: UIColor(white: 0.9, alpha: 1),
                  count: 30, speed: 2, size: 0.4, life: 0.6)
            if target == controller.me { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        case .special(let fighter):
            guard avatars.indices.contains(fighter) else { return }
            avatars[fighter].special()
            ring(at: avatars[fighter].node.simdPosition, color: ArenaPalette.gold, to: 2.2)
            if fighter == controller.me { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        case .attack(let fighter):
            guard avatars.indices.contains(fighter) else { return }
            avatars[fighter].attack()
        case .heal(let target, let amount):
            guard avatars.indices.contains(target), avatars[target].opacity > 0.1 else { return }
            let at = avatars[target].node.simdPosition
            burst(at: at + SIMD3(0, 0.5, 0), color: UIColor(red: 0.4, green: 1, blue: 0.5, alpha: 1), count: 10, speed: 1, size: 0.25, life: 0.5)
            floater("+\(amount)", at: at + SIMD3(Float.random(in: -0.25...0.25), ArenaAvatar.headHeight + 0.35, 0),
                    color: UIColor(red: 0.45, green: 1, blue: 0.5, alpha: 1))
        case .pickup(let fighter):
            guard avatars.indices.contains(fighter) else { return }
            burst(at: avatars[fighter].node.simdPosition + SIMD3(0, 0.8, 0), color: ArenaPalette.gold, count: 16, speed: 1.6, size: 0.18, life: 0.4)
        case .respawn(let fighter):
            guard avatars.indices.contains(fighter) else { return }
            let color = game.fighters[fighter].team == myTeam ? ArenaPalette.blue : ArenaPalette.red
            ring(at: avatars[fighter].node.simdPosition, color: color, to: 1.8)
        }
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
        system.particleImage = Self.dot
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

    /// 火球、大招子弹后面拖的尾巴
    private func trail(_ color: UIColor, size: CGFloat) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.loops = true
        system.birthRate = 70
        system.particleLifeSpan = 0.3
        system.particleVelocity = 0.2
        system.spreadingAngle = 180
        system.particleSize = size
        system.particleColor = color
        system.particleImage = Self.dot
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

    /// 光点用的软圆点
    private static let dot: UIImage = {
        let size = CGSize(width: 32, height: 32)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                                                 endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
        }
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
            motes.particleImage = Self.dot
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
                item.bar.isHidden = false
                item.bar.position = point
                item.fill.xScale = CGFloat(max(0, min(1, Double(turret.health) / Double(max(turret.maxHealth, 1)))))
            } else {
                item.bar.isHidden = true
            }
        }
        for (id, item) in turretViews where !seen.contains(id) {
            burst(at: item.node.simdPosition + SIMD3(0, 0.8, 0), color: UIColor(white: 0.9, alpha: 1), count: 20, speed: 1.5, size: 0.3, life: 0.5)
            item.node.removeFromParentNode()
            item.bar.removeFromParent()
            turretViews[id] = nil
        }
    }

    private func makeTurret(_ turret: ArenaGame.Turret) -> TurretView {
        let ally = turret.team == myTeam
        let color = ally ? ArenaPalette.blue : ArenaPalette.red
        let node = SCNNode()
        if let staff = ArenaModels.shared.prop("Skeleton_Staff.gltf") {
            // 骨杖竖着插在地上（模型握把在原点，往下 0.85、往上 1.26），骷髅头朝上
            let piece = staff.instantiate(shareMaterials: true).root
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
        let bar = SKNode()
        let back = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.6), size: CGSize(width: 38, height: 7))
        let fill = SKSpriteNode(color: color, size: CGSize(width: 36, height: 5))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position = CGPoint(x: -18, y: 0)
        bar.addChild(back)
        bar.addChild(fill)
        bar.isHidden = true
        overlay.addChild(bar)
        return TurretView(node: node, head: head, bar: bar, fill: fill)
    }

    // MARK: - 伤害数字

    private func floater(_ text: String, at point: SIMD3<Float>, color: UIColor) {
        let label = SKLabelNode()
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .heavy),
            .foregroundColor: color,
            .strokeColor: UIColor.black,
            .strokeWidth: -4.0,
        ])
        label.verticalAlignmentMode = .center
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
        let lobbing = brawler == .mage || (isSuper && [.barbarian, .necromancer, .shade, .summoner].contains(brawler))
        if isSuper && brawler == .guardian {
            // 骨盾是给自己的：脚下一圈
            path.append(UIBezierPath(ovalIn: CGRect(x: -0.9, y: -0.9, width: 1.8, height: 1.8)))
        } else if lobbing {
            let distance = max(drag.length, 0.35) * range
            let target = direction * distance
            let blast: Double
            switch brawler {
            case .mage: blast = isSuper ? 2.2 : 1.2
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
        let shape = SCNShape(path: path, extrusionDepth: 0)
        shape.flatness = 0.03
        shape.firstMaterial = ArenaAvatar.decal((isSuper ? ArenaPalette.gold : UIColor.white).withAlphaComponent(0.3))
        aimNode.geometry = shape
        aimNode.simdPosition = SIMD3(Float(fighter.pos.x), 0.07, Float(fighter.pos.y))
        aimNode.isHidden = false
    }
}

/// 每种地图的样子：地面颜色、场地外的草、阳光、墙用什么模型（缩多少、占几成）
private struct ThemeLook {
    let floor: UIColor
    let floorDark: UIColor
    let bushGround: UIColor
    let lawn: UIColor
    let sunlight: UIColor
    let walls: [(file: String, scale: Float, weight: Int)]

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    static func of(_ theme: ArenaMap.Theme) -> ThemeLook {
        let crate = (file: "box_large.glb", scale: Float(1 / 1.5))
        let barrel = (file: "barrel_large.glb", scale: Float(1 / 1.85))
        let stack = (file: "crates_stacked.glb", scale: Float(1 / 2.2))
        switch theme {
        case .sand:
            return ThemeLook(floor: ArenaPalette.sand, floorDark: ArenaPalette.sandDark, bushGround: color(0.55, 0.66, 0.38),
                             lawn: ArenaPalette.grass, sunlight: color(1.0, 0.97, 0.9),
                             walls: [(crate.file, crate.scale, 7), (barrel.file, barrel.scale, 2), (stack.file, stack.scale, 1)])
        case .meadow:
            return ThemeLook(floor: color(0.66, 0.82, 0.47), floorDark: color(0.61, 0.77, 0.43), bushGround: color(0.45, 0.62, 0.33),
                             lawn: color(0.33, 0.58, 0.30), sunlight: color(1.0, 0.98, 0.92),
                             walls: [("trees_A_small.gltf", 0.68, 4), ("trees_B_small.gltf", 0.72, 4), (barrel.file, barrel.scale, 2)])
        case .stone:
            return ThemeLook(floor: color(0.82, 0.82, 0.80), floorDark: color(0.76, 0.76, 0.74), bushGround: color(0.55, 0.62, 0.45),
                             lawn: color(0.45, 0.62, 0.40), sunlight: color(0.95, 0.97, 1.0),
                             walls: [(stack.file, stack.scale, 5), (crate.file, crate.scale, 5)])
        case .dusk:
            return ThemeLook(floor: color(0.93, 0.76, 0.58), floorDark: color(0.88, 0.70, 0.53), bushGround: color(0.58, 0.60, 0.38),
                             lawn: color(0.50, 0.58, 0.34), sunlight: color(1.0, 0.85, 0.68),
                             walls: [(barrel.file, barrel.scale, 5), (crate.file, crate.scale, 5)])
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
