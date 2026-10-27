import SceneKit
import SpriteKit
import UIKit
import simd

/// 场上的一个人（3D）：模型、脚下的圈、大招攒满的光圈；每帧按这个人现在的样子摆位置、转身、放动作。
/// 动作分两层：底下是站着 / 跑 / 欢呼（换的时候淡过去），上面是出手、放大招、倒下（跑着出手只换上半身，腿接着跑）
@MainActor
final class ArenaAvatar {
    /// 角色模型缩多小（模型大约 2.3 高，缩完比一格高一点）
    static let scale: Float = 0.6
    /// 血条画在离地多高
    static let headHeight: Float = 1.6

    let node = SCNNode()
    let brawler: Brawler
    private let look: BrawlerLook
    private let model: GLTFModel?
    private let instance: GLTFModel.Instance?
    private let body = SCNNode()
    private let ring = SCNNode()
    private let glow = SCNNode()
    /// 上半身的骨骼（跑着出手只换这些）
    private let upper: [Int]

    private struct Playing {
        let clip: GLTFModel.Clip
        var time: Float = 0
        var rate: Float = 1
    }

    private struct Action {
        let clip: GLTFModel.Clip
        let move: BrawlerLook.Move
        var elapsed: Float = 0
        /// 放完停在最后一帧（倒下）
        let hold: Bool
        /// 整个身子都换（冲锋、跳、倒下）；不然跑着时只换上半身
        let fullBody: Bool
    }

    private var base: Playing?
    private var fading: Playing?
    private var fade: Float = 1
    private var action: Action?
    private var angle: Float = 0
    private var lastPosition: V2?
    /// 看起来走得多快（按每帧挪了多远算，联机收到的别人也一样）
    private var speed: Float = 0
    private(set) var opacity: Float = 0
    private var placedOpacity = false
    private var deadSince: Double?
    private var flashUntil: Double = 0
    private var flashing = false
    private var placed = false

    init(brawler: Brawler, color: UIColor, isMe: Bool, decorated: Bool = true) {
        self.brawler = brawler
        look = BrawlerLook.of(brawler)
        model = ArenaModels.shared.character(brawler)
        if let model {
            instance = model.instantiate()
            upper = model.node(named: "spine").map { Array(model.subtree(of: $0).intersection(model.animated)) } ?? []
        } else {
            instance = nil
            upper = []
        }
        if let instance {
            for name in look.hidden {
                instance.root.childNode(withName: name, recursively: true)?.isHidden = true
            }
            body.addChildNode(instance.root)
            body.simdScale = SIMD3(repeating: ArenaAvatar.scale)
        } else {
            // 模型读不出来：一个胶囊当身子
            let capsule = SCNCapsule(capRadius: 0.32, height: 1.2)
            capsule.firstMaterial = ArenaAvatar.material(color, lit: true)
            let torso = SCNNode(geometry: capsule)
            torso.simdPosition = SIMD3(0, 0.6, 0)
            body.addChildNode(torso)
        }
        node.addChildNode(body)
        guard decorated else {
            opacity = 1
            return
        }
        // 脚下的圈：自己这边蓝、对面红，自己的描白边
        let disc = SCNCylinder(radius: 0.46, height: 0.01)
        disc.radialSegmentCount = 40
        disc.firstMaterial = ArenaAvatar.decal(color.withAlphaComponent(0.3))
        let discNode = SCNNode(geometry: disc)
        let rim = SCNTube(innerRadius: 0.42, outerRadius: 0.5, height: 0.012)
        rim.radialSegmentCount = 40
        rim.firstMaterial = ArenaAvatar.decal(isMe ? UIColor.white.withAlphaComponent(0.95) : color.withAlphaComponent(0.9))
        let rimNode = SCNNode(geometry: rim)
        ring.addChildNode(discNode)
        ring.addChildNode(rimNode)
        ring.simdPosition = SIMD3(0, 0.03, 0)
        ring.renderingOrder = 5
        ring.castsShadow = false
        discNode.castsShadow = false
        rimNode.castsShadow = false
        node.addChildNode(ring)
        // 大招攒满：脚下一圈金光
        let halo = SCNTube(innerRadius: 0.52, outerRadius: 0.64, height: 0.02)
        halo.radialSegmentCount = 40
        halo.firstMaterial = ArenaAvatar.decal(ArenaPalette.gold.withAlphaComponent(0.9))
        glow.geometry = halo
        glow.simdPosition = SIMD3(0, 0.04, 0)
        glow.castsShadow = false
        glow.renderingOrder = 6
        glow.isHidden = true
        node.addChildNode(glow)
        node.opacity = 0
    }

    // MARK: - 每帧

    /// visible：这一队看不看得见他；translucent：自己这边的人躲在草丛里（半透明）；cheering：赢了
    func update(_ fighter: Fighter, visible: Bool, translucent: Bool, cheering: Bool, dt: Float, clock: Double) {
        // 位置：跳起来时往上抛一道弧
        var height: Float = 0
        if let leap = fighter.leap {
            let t = Float(min(max(leap.elapsed / Fighter.Leap.duration, 0), 1))
            height = sin(t * .pi) * 1.6
        }
        node.simdPosition = SIMD3(Float(fighter.pos.x), height, Float(fighter.pos.y))
        if let lastPosition, dt > 0 {
            let moved = min(Float(fighter.pos.distance(to: lastPosition)) / dt, 20)
            speed += (moved - speed) * min(1, dt * 10)
        }
        lastPosition = fighter.pos

        // 转身：慢慢转过去，不一下子跳
        if fighter.facing.length > 0.01 {
            let target = atan2(Float(fighter.facing.x), Float(fighter.facing.y))
            if placed {
                var delta = target - angle
                while delta > .pi { delta -= 2 * .pi }
                while delta < -.pi { delta += 2 * .pi }
                angle += delta * min(1, dt * 16)
            } else {
                angle = target
            }
        }
        placed = true
        body.simdEulerAngles = SIMD3(0, angle, 0)

        // 倒下、复活
        if fighter.alive {
            if deadSince != nil {
                deadSince = nil
                action = nil
            }
        } else if deadSince == nil {
            deadSince = clock
            start(BrawlerLook.death, hold: true, fullBody: true)
        }

        // 透明度：看不见的淡出；倒下的过一秒淡出
        var target: Float
        if let deadSince {
            target = clock - deadSince < 1.1 ? 1 : 0
        } else {
            target = visible ? (translucent ? 0.5 : 1) : 0
        }
        if !placedOpacity {
            opacity = target
            placedOpacity = true
        } else {
            opacity += (target - opacity) * min(1, dt * 10)
        }
        node.opacity = CGFloat(opacity)
        node.isHidden = opacity < 0.02
        ring.isHidden = !fighter.alive
        glow.isHidden = !(fighter.alive && fighter.superCharge >= 1)
        if !glow.isHidden {
            let pulse = 1 + 0.07 * Float(sin(clock * 6))
            glow.simdScale = SIMD3(pulse, 1, pulse)
        }

        if flashing && clock >= flashUntil {
            flashing = false
            instance?.materials.forEach { $0.emission.contents = UIColor.black }
        }

        guard !node.isHidden else { return }
        let moving = fighter.alive && speed > 0.6
        let wanted = cheering ? BrawlerLook.cheer : (moving ? look.run : look.idle)
        animate(dt: dt, moving: moving, base: wanted)
    }

    /// 开了一枪
    func attack() {
        start(look.attack, hold: false, fullBody: false)
    }

    /// 放了大招（冲锋、跳整个身子都动）
    func special() {
        start(look.special, hold: false, fullBody: brawler == .knight || brawler == .barbarian)
    }

    /// 挨打：白一下
    func flash(clock: Double) {
        flashUntil = clock + 0.09
        guard !flashing, let instance else { return }
        flashing = true
        instance.materials.forEach { $0.emission.contents = UIColor(white: 0.7, alpha: 1) }
    }

    /// 摆一个静止的姿势（画头像用）
    func hold(_ name: String, at time: Float) {
        guard let model, let instance, let clip = model.clips[name] else { return }
        var pose = model.restPose
        clip.sample(at: time, into: &pose)
        for i in model.animated { instance.nodes[i].simdTransform = pose.transform(i) }
    }

    func turn(to angle: Float) {
        self.angle = angle
        body.simdEulerAngles = SIMD3(0, angle, 0)
    }

    // MARK: - 动作

    private func start(_ move: BrawlerLook.Move, hold: Bool, fullBody: Bool) {
        guard let clip = model?.clips[move.clip], clip.duration > 0 else { return }
        action = Action(clip: clip, move: move, hold: hold, fullBody: fullBody)
    }

    private func animate(dt: Float, moving: Bool, base wanted: String) {
        guard let model, let instance else { return }
        // 底下一层：站着 / 跑 / 欢呼，换的时候 0.15 秒淡过去
        if base?.clip.name != wanted, let clip = model.clips[wanted], clip.duration > 0 {
            fading = base
            fade = base == nil ? 1 : 0
            base = Playing(clip: clip)
        }
        if var playing = base {
            playing.rate = playing.clip.name == look.run ? min(max(speed / 2.4, 0.75), 1.4) : 1
            playing.time += dt * playing.rate
            base = playing
        }
        fade = min(1, fade + dt / 0.15)
        if fade >= 1 { fading = nil }
        if var old = fading {
            old.time += dt * old.rate
            fading = old
        }
        var pose = model.restPose
        if let base { base.clip.sample(at: Self.looped(base.time, base.clip.duration), into: &pose) }
        if let fading {
            var previous = model.restPose
            fading.clip.sample(at: Self.looped(fading.time, fading.clip.duration), into: &previous)
            previous.blend(toward: pose, weight: fade, nodes: model.animated)
            pose = previous
        }

        // 上面一层：出手、大招、倒下
        if var current = action {
            current.elapsed += dt
            let progress = current.elapsed / max(current.move.seconds, 0.01)
            if progress >= 1 && !current.hold {
                action = nil
            } else {
                action = current
                let t = current.move.from + (current.move.to - current.move.from) * min(progress, 1)
                var layer = model.restPose
                current.clip.sample(at: t * current.clip.duration, into: &layer)
                let fadeIn = min(1, current.elapsed / 0.06)
                let fadeOut = current.hold ? 1 : min(1, (1 - progress) * current.move.seconds / 0.12)
                let weight = min(fadeIn, fadeOut)
                if current.fullBody || !moving {
                    pose.blend(toward: layer, weight: weight, nodes: model.animated)
                } else {
                    pose.blend(toward: layer, weight: weight, nodes: upper)
                }
            }
        }
        for i in model.animated { instance.nodes[i].simdTransform = pose.transform(i) }
    }

    private static func looped(_ time: Float, _ duration: Float) -> Float {
        duration > 0 ? time.truncatingRemainder(dividingBy: duration) : 0
    }

    // MARK: - 材质

    /// 普通的有光照的颜色
    static func material(_ color: UIColor, lit: Bool) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = lit ? .lambert : .constant
        material.diffuse.contents = color
        return material
    }

    /// 贴在地上的圈、范围：不受光、不挡后面的东西
    static func decal(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        return material
    }
}

/// 一个人头顶上的名字、血条（自己的再加三格弹药），画在 3D 画面上面那层
@MainActor
final class ArenaTag {
    let node = SKNode()
    private let label: SKLabelNode
    private let back: SKSpriteNode
    private let fill: SKSpriteNode
    private let number: SKLabelNode
    private let starLabel: SKLabelNode
    private var ammo: [SKSpriteNode] = []
    private let color: UIColor
    private let isMe: Bool
    private var shownHealth = -1
    private var shownStars = -1
    private static let width: CGFloat = 50
    private static let barHeight: CGFloat = 9

    init(fighter: Fighter, isMe: Bool, color: UIColor) {
        self.isMe = isMe
        self.color = color
        let width = ArenaTag.width
        label = SKLabelNode(fontNamed: "PingFangSC-Semibold")
        label.text = isMe ? "我" : fighter.name
        label.fontSize = 11
        label.fontColor = .white
        label.verticalAlignmentMode = .baseline
        label.position = CGPoint(x: 0, y: ArenaTag.barHeight / 2 + 4)
        back = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.6), size: CGSize(width: width + 2, height: ArenaTag.barHeight + 2))
        fill = SKSpriteNode(color: isMe ? .systemGreen : color, size: CGSize(width: width, height: ArenaTag.barHeight))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position = CGPoint(x: -width / 2, y: 0)
        number = SKLabelNode(fontNamed: "AvenirNext-Bold")
        number.fontSize = 8
        number.fontColor = .white
        number.verticalAlignmentMode = .center
        starLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        starLabel.fontSize = 12
        starLabel.fontColor = ArenaPalette.gold
        starLabel.verticalAlignmentMode = .baseline
        starLabel.position = CGPoint(x: 0, y: ArenaTag.barHeight / 2 + 18)
        [back, fill, number, label, starLabel].forEach(node.addChild)
        if isMe {
            let segment = (width - 4) / 3
            for k in 0..<3 {
                let bar = SKSpriteNode(color: .systemOrange, size: CGSize(width: segment, height: 4))
                bar.anchorPoint = CGPoint(x: 0, y: 0.5)
                bar.position = CGPoint(x: -width / 2 + CGFloat(k) * (segment + 2), y: -ArenaTag.barHeight / 2 - 5)
                node.addChild(bar)
                ammo.append(bar)
            }
        }
        node.isHidden = true
    }

    /// point：头顶在屏幕上的位置（nil：在镜头后面）
    func update(_ fighter: Fighter, at point: CGPoint?, opacity: Float) {
        guard let point, fighter.alive, opacity > 0.05 else {
            node.isHidden = true
            return
        }
        node.isHidden = false
        node.position = point
        node.alpha = CGFloat(min(1, opacity * 1.4))
        let fraction = CGFloat(fighter.health) / CGFloat(max(fighter.maxHealth, 1))
        fill.xScale = max(0, min(1, fraction))
        if isMe { fill.color = fraction < 0.3 ? .systemRed : .systemGreen }
        if fighter.health != shownHealth {
            shownHealth = fighter.health
            number.text = "\(max(fighter.health, 0))"
        }
        if fighter.stars != shownStars {
            shownStars = fighter.stars
            starLabel.text = fighter.stars > 0 ? "★\(fighter.stars)" : ""
        }
        for (k, bar) in ammo.enumerated() {
            let part = CGFloat(min(max(fighter.ammo - Double(k), 0), 1))
            bar.xScale = max(part, 0.02)
            bar.alpha = part >= 1 ? 1 : 0.45
        }
    }
}
