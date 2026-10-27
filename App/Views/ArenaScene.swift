import SpriteKit
import UIKit

/// 乱斗的画面：地图、每个人、子弹、星星、圈、毒圈、特效，镜头跟着自己走。
/// 规则在 ArenaGame 里算，这里每帧按最新的样子摆一遍
final class ArenaScene: SKScene {
    weak var controller: ArenaController?
    /// 一格多少点
    private var tile: CGFloat = 36
    private let world = SKNode()
    private let cameraNode = SKCameraNode()
    private var mapNode: SKNode?
    private var fighterNodes: [Int: ArenaFighterNode] = [:]
    private var projectileNodes: [Int: SKNode] = [:]
    private var starNodes: [SKLabelNode] = []
    private let zoneNode = SKShapeNode()
    private let poisonNode = SKShapeNode()
    private let poisonEdge = SKShapeNode()
    private let aimNode = SKShapeNode()
    private var lastPoison: Double = -1
    private var lastTime: TimeInterval?
    private var builtSize: CGSize = .zero

    static let blue = UIColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1)
    static let red = UIColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1)
    static let ground = UIColor(red: 0.93, green: 0.84, blue: 0.62, alpha: 1)
    static let wall = UIColor(red: 0.55, green: 0.38, blue: 0.26, alpha: 1)
    static let wallTop = UIColor(red: 0.68, green: 0.50, blue: 0.35, alpha: 1)
    static let bush = UIColor(red: 0.30, green: 0.66, blue: 0.30, alpha: 1)

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.42, green: 0.62, blue: 0.85, alpha: 1)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        if world.parent == nil { addChild(world) }
        if cameraNode.parent == nil { addChild(cameraNode) }
        camera = cameraNode
    }

    override func update(_ currentTime: TimeInterval) {
        let elapsed = lastTime.map { currentTime - $0 } ?? 0
        lastTime = currentTime
        MainActor.assumeIsolated {
            guard let controller else { return }
            controller.advance(elapsed)
            render(controller)
        }
    }

    // MARK: - 摆一遍

    @MainActor
    private func render(_ controller: ArenaController) {
        let game = controller.game
        if mapNode == nil || builtSize != size { buildMap(game.map) }
        let myTeam = controller.mine.team

        // 人
        for fighter in game.fighters {
            let node = fighterNodes[fighter.id] ?? {
                let created = ArenaFighterNode(fighter: fighter, tile: tile, isMe: fighter.id == controller.me,
                                               color: color(team: fighter.team, myTeam: myTeam, mode: game.mode))
                world.addChild(created)
                fighterNodes[fighter.id] = created
                return created
            }()
            let visible = game.isVisible(fighter, to: myTeam)
            node.update(fighter, at: point(fighter.pos), visible: visible, hidden: game.map.inBush(fighter.pos), tile: tile)
        }

        // 子弹、炸弹
        var seen = Set<Int>()
        for projectile in game.projectiles {
            seen.insert(projectile.id)
            let node = projectileNodes[projectile.id] ?? {
                let created = projectileNode(projectile, myTeam: myTeam, mode: game.mode)
                world.addChild(created)
                projectileNodes[projectile.id] = created
                return created
            }()
            node.position = point(projectile.pos)
            if let lob = projectile.lob, let ball = node.childNode(withName: "ball") {
                let t = lob.elapsed / lob.duration
                ball.position = CGPoint(x: 0, y: CGFloat(sin(t * .pi)) * tile * 1.4)
                node.childNode(withName: "landing")?.position = point(lob.to) - node.position
            }
        }
        for (id, node) in projectileNodes where !seen.contains(id) {
            node.removeFromParent()
            projectileNodes[id] = nil
        }

        // 星星
        while starNodes.count < game.stars.count {
            let star = SKLabelNode(text: "⭐️")
            star.fontSize = tile * 0.6
            star.verticalAlignmentMode = .center
            star.zPosition = 3
            world.addChild(star)
            starNodes.append(star)
        }
        while starNodes.count > game.stars.count {
            starNodes.removeLast().removeFromParent()
        }
        for (k, star) in game.stars.enumerated() {
            starNodes[k].position = point(star) + CGPoint(x: 0, y: CGFloat(sin(game.time * 4 + Double(k))) * 3)
        }

        // 占点的圈：谁站着就是谁的颜色
        if game.mode == .zone {
            let inside = Set(game.fighters.filter { $0.alive && $0.pos.distance(to: game.map.center) < ArenaGame.zoneRadius }.map(\.team))
            let fill: UIColor = inside.count == 1 ? color(team: inside.first!, myTeam: myTeam, mode: game.mode) : .white
            zoneNode.fillColor = fill.withAlphaComponent(inside.isEmpty ? 0.12 : 0.3)
            zoneNode.strokeColor = inside.count > 1 ? .orange : fill.withAlphaComponent(0.8)
        }

        // 毒圈
        if game.mode == .showdown, abs(game.safeRadius - lastPoison) > 0.01 {
            lastPoison = game.safeRadius
            // 圈外一片绿：画一个很粗的圆环，里边正好是安全的地方
            let width: CGFloat = 4000
            let radius = CGFloat(game.safeRadius) * tile + width / 2
            poisonNode.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
            poisonNode.lineWidth = width
            poisonNode.position = point(game.map.center)
            poisonEdge.path = CGPath(ellipseIn: CGRect(x: -CGFloat(game.safeRadius) * tile, y: -CGFloat(game.safeRadius) * tile,
                                                       width: CGFloat(game.safeRadius) * tile * 2, height: CGFloat(game.safeRadius) * tile * 2),
                                     transform: nil)
            poisonEdge.position = poisonNode.position
        }

        // 特效
        for event in controller.takeEvents() { effect(event, game: game, myTeam: myTeam) }

        // 瞄准线
        drawAim(controller)

        // 镜头跟着自己
        let target = point(controller.mine.pos)
        let current = cameraNode.position
        cameraNode.position = CGPoint(x: current.x + (target.x - current.x) * 0.2, y: current.y + (target.y - current.y) * 0.2)
    }

    private func point(_ v: V2) -> CGPoint {
        CGPoint(x: CGFloat(v.x) * tile, y: -CGFloat(v.y) * tile)
    }

    private func color(team: Int, myTeam: Int, mode: ArenaGame.Mode) -> UIColor {
        team == myTeam ? Self.blue : Self.red
    }

    // MARK: - 地图

    @MainActor
    private func buildMap(_ map: ArenaMap) {
        mapNode?.removeFromParent()
        fighterNodes.values.forEach { $0.removeFromParent() }
        fighterNodes = [:]
        builtSize = size
        // 竖屏看 11 格宽；iPad 上看得多一点
        tile = max(24, min(size.width / 11, size.height / 15))
        let node = SKNode()
        let ground = SKSpriteNode(color: Self.ground, size: CGSize(width: CGFloat(map.width) * tile, height: CGFloat(map.height) * tile))
        ground.anchorPoint = CGPoint(x: 0, y: 1)
        ground.position = .zero
        ground.zPosition = -10
        node.addChild(ground)
        // 浅浅的格子
        for y in 0..<map.height {
            for x in 0..<map.width where (x + y) % 2 == 0 && map.tile(x, y) == .floor {
                let checker = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.035), size: CGSize(width: tile, height: tile))
                checker.position = CGPoint(x: (CGFloat(x) + 0.5) * tile, y: -(CGFloat(y) + 0.5) * tile)
                checker.zPosition = -9
                node.addChild(checker)
            }
        }
        for y in 0..<map.height {
            for x in 0..<map.width {
                let center = CGPoint(x: (CGFloat(x) + 0.5) * tile, y: -(CGFloat(y) + 0.5) * tile)
                switch map.tile(x, y) {
                case .wall:
                    let block = SKSpriteNode(color: Self.wall, size: CGSize(width: tile, height: tile))
                    block.position = center
                    block.zPosition = 1
                    let top = SKSpriteNode(color: Self.wallTop, size: CGSize(width: tile, height: tile * 0.75))
                    top.position = CGPoint(x: 0, y: tile * 0.18)
                    block.addChild(top)
                    node.addChild(block)
                case .bush:
                    let bush = SKShapeNode(rectOf: CGSize(width: tile * 1.04, height: tile * 1.04), cornerRadius: tile * 0.3)
                    bush.fillColor = Self.bush
                    bush.strokeColor = Self.bush.withAlphaComponent(0.6)
                    bush.position = center
                    bush.zPosition = 6
                    bush.alpha = 0.92
                    node.addChild(bush)
                case .floor:
                    break
                }
            }
        }
        if !map.spawns.isEmpty {
            for (team, spots) in map.spawns.enumerated() where map.spawns.count == 2 {
                for spot in spots {
                    let pad = SKShapeNode(circleOfRadius: tile * 0.45)
                    pad.fillColor = (team == 0 ? Self.blue : Self.red).withAlphaComponent(0.18)
                    pad.strokeColor = .clear
                    pad.position = point(spot)
                    pad.zPosition = -5
                    node.addChild(pad)
                }
            }
        }
        // 占点的圈、星星出生的地方
        zoneNode.removeFromParent()
        let zone = CGFloat(ArenaGame.zoneRadius) * tile
        zoneNode.path = CGPath(ellipseIn: CGRect(x: -zone, y: -zone, width: zone * 2, height: zone * 2), transform: nil)
        zoneNode.position = point(map.center)
        zoneNode.lineWidth = 3
        zoneNode.zPosition = -4
        zoneNode.fillColor = .clear
        zoneNode.strokeColor = .clear
        node.addChild(zoneNode)
        poisonNode.removeFromParent()
        poisonNode.fillColor = .clear
        poisonNode.strokeColor = UIColor(red: 0.25, green: 0.65, blue: 0.3, alpha: 0.4)
        poisonNode.zPosition = 20
        poisonEdge.removeFromParent()
        poisonEdge.fillColor = .clear
        poisonEdge.strokeColor = UIColor(red: 0.2, green: 0.85, blue: 0.3, alpha: 0.9)
        poisonEdge.lineWidth = 3
        poisonEdge.zPosition = 21
        lastPoison = -1
        node.addChild(poisonNode)
        node.addChild(poisonEdge)
        aimNode.removeFromParent()
        aimNode.zPosition = 4
        node.addChild(aimNode)
        world.addChild(node)
        mapNode = node
        if let controller {
            if controller.game.mode == .zone {
                zoneNode.strokeColor = UIColor.white.withAlphaComponent(0.7)
            } else if controller.game.mode == .stars {
                let mine = SKShapeNode(circleOfRadius: tile * 0.6)
                mine.fillColor = UIColor.purple.withAlphaComponent(0.25)
                mine.strokeColor = UIColor.purple.withAlphaComponent(0.6)
                mine.position = point(map.center)
                mine.zPosition = -4
                node.addChild(mine)
            }
            cameraNode.position = point(controller.mine.pos)
        }
    }

    // MARK: - 子弹

    private func projectileNode(_ projectile: Projectile, myTeam: Int, mode: ArenaGame.Mode) -> SKNode {
        let color = color(team: projectile.team, myTeam: myTeam, mode: mode)
        let node = SKNode()
        node.zPosition = 8
        if let lob = projectile.lob {
            // 地上的影子 + 天上的炸弹
            let shadow = SKShapeNode(ellipseOf: CGSize(width: tile * 0.5, height: tile * 0.25))
            shadow.fillColor = UIColor.black.withAlphaComponent(0.25)
            shadow.strokeColor = .clear
            node.addChild(shadow)
            let ball = SKShapeNode(circleOfRadius: tile * (projectile.isSuper ? 0.36 : 0.24))
            ball.fillColor = projectile.isSuper ? .orange : UIColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 1)
            ball.strokeColor = color
            ball.lineWidth = 2
            ball.name = "ball"
            node.addChild(ball)
            // 落点
            let landing = SKShapeNode(circleOfRadius: CGFloat(lob.blast) * tile)
            landing.strokeColor = color.withAlphaComponent(0.6)
            landing.fillColor = color.withAlphaComponent(0.08)
            landing.position = point(lob.to) - point(lob.from)
            landing.zPosition = -1
            landing.name = "landing"
            node.addChild(landing)
        } else {
            let ball = SKShapeNode(circleOfRadius: CGFloat(projectile.radius) * tile * (projectile.isSuper ? 1.2 : 1))
            ball.fillColor = projectile.isSuper ? .yellow : color
            ball.strokeColor = .white
            ball.lineWidth = 1.5
            ball.glowWidth = projectile.isSuper ? 4 : 0
            node.addChild(ball)
        }
        return node
    }

    // MARK: - 特效

    @MainActor
    private func effect(_ event: ArenaGame.Event, game: ArenaGame, myTeam: Int) {
        switch event {
        case .hit(let target, let amount):
            guard let node = fighterNodes[target], node.alpha > 0.1 else { return }
            let label = SKLabelNode(text: "\(amount)")
            label.fontName = "AvenirNext-Heavy"
            label.fontSize = tile * 0.42
            label.fontColor = game.fighters[target].team == myTeam ? .white : .yellow
            label.position = node.position + CGPoint(x: CGFloat.random(in: -8...8), y: tile * 0.9)
            label.zPosition = 30
            world.addChild(label)
            label.run(.sequence([.group([.moveBy(x: 0, y: tile * 0.8, duration: 0.6), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
            node.flash()
        case .explosion(let at, let radius):
            let ring = SKShapeNode(circleOfRadius: CGFloat(radius) * tile)
            ring.fillColor = UIColor.orange.withAlphaComponent(0.45)
            ring.strokeColor = .yellow
            ring.position = point(at)
            ring.zPosition = 9
            ring.setScale(0.3)
            world.addChild(ring)
            ring.run(.sequence([.group([.scale(to: 1, duration: 0.15), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        case .knockout(let target, _):
            guard let node = fighterNodes[target] else { return }
            let poof = SKLabelNode(text: "💥")
            poof.fontSize = tile * 0.9
            poof.position = node.position
            poof.zPosition = 30
            world.addChild(poof)
            poof.run(.sequence([.group([.scale(to: 1.8, duration: 0.4), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
            if target == controller?.me { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        case .special(let fighter):
            fighterNodes[fighter]?.run(.sequence([.scale(to: 1.25, duration: 0.08), .scale(to: 1, duration: 0.15)]), withKey: "pulse")
        case .pickup, .respawn:
            break
        }
    }

    // MARK: - 瞄准线

    @MainActor
    private func drawAim(_ controller: ArenaController) {
        let fighter = controller.mine
        guard fighter.alive, let drag = controller.superAiming ?? controller.aiming else {
            aimNode.path = nil
            return
        }
        let isSuper = controller.superAiming != nil
        let range = isSuper ? fighter.brawler.superRange : fighter.brawler.attackRange
        let direction = drag.length > 0.25 ? drag.normalized : fighter.facing
        let origin = point(fighter.pos)
        let path = CGMutablePath()
        let lobbing = fighter.brawler == .frog || (isSuper && fighter.brawler == .tiger)
        if lobbing {
            let distance = max(drag.length, 0.35) * range
            let target = point(fighter.pos + direction * distance)
            let radius = (fighter.brawler == .frog ? (isSuper ? 2.2 : 1.2) : 1.6) * tile
            path.addEllipse(in: CGRect(x: target.x - radius, y: target.y - radius, width: radius * 2, height: radius * 2))
            path.move(to: origin)
            path.addLine(to: target)
        } else {
            let width = (fighter.brawler == .panda || (isSuper && fighter.brawler == .robot) || fighter.brawler == .tiger ? 0.9 : 0.3) * tile
            let end = point(fighter.pos + direction * range)
            let normal = CGPoint(x: -CGFloat(direction.y), y: -CGFloat(direction.x)) * (width / 2)
            path.move(to: origin + normal)
            path.addLine(to: end + normal * (fighter.brawler == .panda || isSuper && fighter.brawler == .robot ? 2.5 : 1))
            path.addLine(to: end - normal * (fighter.brawler == .panda || isSuper && fighter.brawler == .robot ? 2.5 : 1))
            path.addLine(to: origin - normal)
            path.closeSubpath()
        }
        aimNode.path = path
        aimNode.fillColor = (isSuper ? UIColor.systemYellow : UIColor.white).withAlphaComponent(0.25)
        aimNode.strokeColor = (isSuper ? UIColor.systemYellow : UIColor.white).withAlphaComponent(0.7)
        aimNode.lineWidth = 2
    }
}

/// 一个人：影子、身体（队伍颜色）、表情、血条、名字；自己的再加上三格弹药和大招满了的光圈
final class ArenaFighterNode: SKNode {
    private let body: SKShapeNode
    private let face: SKLabelNode
    private let healthBack: SKSpriteNode
    private let healthFill: SKSpriteNode
    private let label: SKLabelNode
    private let ring: SKShapeNode
    private var ammo: [SKSpriteNode] = []
    private let isMe: Bool
    private let barWidth: CGFloat
    private let color: UIColor
    private var starsLabel: SKLabelNode

    init(fighter: Fighter, tile: CGFloat, isMe: Bool, color: UIColor) {
        self.isMe = isMe
        self.color = color
        let radius = CGFloat(ArenaGame.fighterRadius) * tile
        barWidth = tile * 1.1
        let shadow = SKShapeNode(ellipseOf: CGSize(width: radius * 2, height: radius * 0.8))
        shadow.fillColor = UIColor.black.withAlphaComponent(0.25)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -radius * 0.8)
        body = SKShapeNode(circleOfRadius: radius)
        body.fillColor = color
        body.strokeColor = isMe ? .white : color.withAlphaComponent(0.6)
        body.lineWidth = isMe ? 3 : 2
        face = SKLabelNode(text: fighter.brawler.emoji)
        face.fontSize = radius * 1.5
        face.verticalAlignmentMode = .center
        healthBack = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.55), size: CGSize(width: barWidth, height: tile * 0.14))
        healthBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        healthBack.position = CGPoint(x: -barWidth / 2, y: radius + tile * 0.32)
        healthFill = SKSpriteNode(color: isMe ? .systemGreen : color, size: CGSize(width: barWidth, height: tile * 0.14))
        healthFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        healthFill.position = healthBack.position
        label = SKLabelNode(text: isMe ? "我" : fighter.name)
        label.fontName = "PingFangSC-Semibold"
        label.fontSize = tile * 0.26
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: radius + tile * 0.45)
        ring = SKShapeNode(circleOfRadius: radius + 5)
        ring.strokeColor = .systemYellow
        ring.lineWidth = 3
        ring.glowWidth = 4
        ring.isHidden = true
        starsLabel = SKLabelNode(text: "")
        starsLabel.fontName = "AvenirNext-Heavy"
        starsLabel.fontSize = tile * 0.3
        starsLabel.fontColor = .systemYellow
        starsLabel.position = CGPoint(x: 0, y: -radius - tile * 0.45)
        super.init()
        zPosition = 5
        [shadow, ring, body, face, healthBack, healthFill, label, starsLabel].forEach(addChild)
        if isMe {
            let segment = (barWidth - 4) / 3
            for k in 0..<3 {
                let bar = SKSpriteNode(color: .systemOrange, size: CGSize(width: segment, height: tile * 0.09))
                bar.anchorPoint = CGPoint(x: 0, y: 0.5)
                bar.position = CGPoint(x: -barWidth / 2 + CGFloat(k) * (segment + 2), y: radius + tile * 0.18)
                addChild(bar)
                ammo.append(bar)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("不从文件里读") }

    func update(_ fighter: Fighter, at position: CGPoint, visible: Bool, hidden: Bool, tile: CGFloat) {
        self.position = position
        guard fighter.alive else {
            alpha = 0
            return
        }
        // 在草丛里：敌人看不见，自己和队友半透明
        alpha = visible ? (hidden ? 0.55 : 1) : 0
        zPosition = hidden ? 7 : 5
        let fraction = CGFloat(fighter.health) / CGFloat(max(fighter.maxHealth, 1))
        healthFill.xScale = max(0, min(1, fraction))
        healthFill.color = isMe ? (fraction < 0.3 ? .systemRed : .systemGreen) : color
        face.xScale = fighter.facing.x < -0.1 ? -1 : 1
        ring.isHidden = fighter.superCharge < 1
        starsLabel.text = fighter.stars > 0 ? "⭐️\(fighter.stars)" : ""
        for (k, bar) in ammo.enumerated() {
            let fill = CGFloat(min(max(fighter.ammo - Double(k), 0), 1))
            bar.xScale = max(fill, 0.02)
            bar.alpha = fill >= 1 ? 1 : 0.45
        }
        // 跳起来的时候变大
        if let leap = fighter.leap {
            let t = leap.elapsed / Fighter.Leap.duration
            setScale(1 + 0.6 * CGFloat(sin(t * .pi)))
        } else if action(forKey: "pulse") == nil {
            setScale(1)
        }
    }

    /// 挨打时白一下
    func flash() {
        body.fillColor = .white
        run(.sequence([.wait(forDuration: 0.06), .run { [weak self] in
            guard let self else { return }
            self.body.fillColor = self.color
        }]), withKey: "flash")
    }
}

private extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
}
