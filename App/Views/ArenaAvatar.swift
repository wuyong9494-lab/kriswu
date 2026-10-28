import SceneKit
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

    /// 脚下的软影子，所有人共用一张
    private static let blobShadow: SCNMaterial = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { renderer in
            let colors = [UIColor.black.withAlphaComponent(0.5).cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.15, 1]) else { return }
            renderer.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 1,
                                                  endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        return material
    }()

    let node = SCNNode()
    let brawler: Brawler
    /// 个子多大（骷髅王 2.2 倍）
    let size: Float
    private let look: BrawlerLook
    private let model: GLTFModel?
    private let instance: GLTFModel.Instance?
    private let body = SCNNode()
    private let ring = SCNNode()
    private let glow = SCNNode()
    /// 骨盾：罩在身上的一层金光
    private let bubble = SCNNode()
    /// 超级充能开着：脚下一圈紫光、身上往上冒紫色光点
    private let aura = SCNNode()
    private var sparks: SCNParticleSystem?
    /// 走得快（疾行、超级充能）：脚下拖一道光
    private var streak: SCNParticleSystem?
    /// 被冰霜减速：身上发蓝
    private var frosted = false
    /// 大招和超级充能都满了：脚下的光圈变紫
    private var hyperReady = false
    /// 皮肤的颜色（冻住时换成冰蓝，好了换回来）
    private var baseTint = UIColor.white
    /// 材质本来的自发光（骷髅的眼睛），挨打闪白后改回去
    private var glows: [Any?] = []
    /// 身上、手里武器的描边（半透明、淡出时藏起来）
    private var outlines: [SCNNode] = []
    private var outlined = true
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
    private var ammoPips = 3

    /// skin：穿第几套皮肤（0 原来的样子）
    init(brawler: Brawler, color: UIColor, isMe: Bool, decorated: Bool = true, size: Float = 1, skin: Int = 0) {
        self.brawler = brawler
        self.size = size
        look = BrawlerLook.of(brawler)
        model = ArenaModels.shared.character(brawler)
        if let model {
            instance = model.instantiate(outline: ArenaArt.outline)
            upper = model.node(named: "spine").map { Array(model.subtree(of: $0).intersection(model.animated)) } ?? []
        } else {
            instance = nil
            upper = []
        }
        if let instance {
            for name in look.hidden {
                instance.root.childNode(withName: name, recursively: true)?.isHidden = true
            }
            for weapon in look.weapons {
                guard let piece = ArenaModels.shared.prop(weapon.file),
                      let bone = instance.root.childNode(withName: weapon.bone, recursively: true) else { continue }
                let held = piece.instantiate(shareMaterials: true, outline: ArenaArt.outline)
                held.root.simdPosition = weapon.position
                held.root.simdOrientation = weapon.rotation
                bone.addChildNode(held.root)
                outlines += held.outlines
            }
            outlines += instance.outlines
            // 皮肤：身上的颜色乘上皮肤的颜色，原来不发光的地方加一点光（武器、骷髅的眼睛不变）
            if let look = ArenaSkin.of(brawler).first(where: { $0.index == skin }), look.tint.count == 3, look.glow.count == 3 {
                let tint = UIColor(red: look.tint[0], green: look.tint[1], blue: look.tint[2], alpha: 1)
                let glow = UIColor(red: look.glow[0], green: look.glow[1], blue: look.glow[2], alpha: 1)
                for material in instance.materials {
                    material.multiply.contents = tint
                    if Self.dark(material.emission.contents) { material.emission.contents = glow }
                }
                baseTint = tint
            } else if let tint = BrawlerLook.baseTint(brawler) {
                instance.materials.forEach { $0.multiply.contents = tint }
                baseTint = tint
            }
            instance.materials.forEach { ArenaArt.grade($0, ArenaArt.characterSurface) }
            glows = instance.materials.map { $0.emission.contents }
            body.addChildNode(instance.root)
            body.simdScale = SIMD3(repeating: ArenaAvatar.scale * size * look.scale)
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
        // 脚下一块软影子（往镜头那边扁一点）。不靠整屏阴影贴图，手机扛得住，人也立在地上
        let blob = SCNPlane(width: 1.35, height: 0.82)
        blob.firstMaterial = Self.blobShadow
        let blobNode = SCNNode(geometry: blob)
        blobNode.simdEulerAngles = SIMD3(-Float.pi / 2, 0, 0)
        blobNode.simdPosition = SIMD3(0, 0.015, 0.08)
        blobNode.simdScale = SIMD3(size, 1, size)
        blobNode.castsShadow = false
        blobNode.renderingOrder = 1
        node.addChildNode(blobNode)
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
        let span = isMe ? size * 1.35 : size
        ring.simdScale = SIMD3(span, 1, span)
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
        glow.simdScale = SIMD3(size, 1, size)
        glow.castsShadow = false
        glow.renderingOrder = 6
        glow.isHidden = true
        node.addChildNode(glow)
        let shell = SCNSphere(radius: 0.78)
        shell.segmentCount = 24
        let shine = ArenaAvatar.decal(ArenaPalette.gold.withAlphaComponent(0.22))
        shine.isDoubleSided = false
        shell.firstMaterial = shine
        bubble.geometry = shell
        bubble.simdPosition = SIMD3(0, 0.7 * size, 0)
        bubble.simdScale = SIMD3(size, 1.05 * size, size)
        bubble.castsShadow = false
        bubble.renderingOrder = 12
        bubble.isHidden = true
        node.addChildNode(bubble)
        let band = SCNTube(innerRadius: 0.56, outerRadius: 0.8, height: 0.02)
        band.radialSegmentCount = 40
        band.firstMaterial = ArenaAvatar.decal(ArenaPalette.hyper.withAlphaComponent(0.85))
        aura.geometry = band
        aura.simdPosition = SIMD3(0, 0.05, 0)
        aura.castsShadow = false
        aura.renderingOrder = 6
        aura.isHidden = true
        node.addChildNode(aura)
        let rising = ArenaAvatar.particles(color: ArenaPalette.hyper, size: 0.2 * CGFloat(size), life: 0.7)
        rising.emitterShape = SCNCylinder(radius: CGFloat(0.42 * size), height: CGFloat(1.1 * size))
        rising.birthLocation = .surface
        rising.emittingDirection = SCNVector3(0, 1, 0)
        rising.spreadingAngle = 12
        rising.particleVelocity = 1.4
        let riser = SCNNode()
        riser.simdPosition = SIMD3(0, 0.6 * size, 0)
        riser.addParticleSystem(rising)
        node.addChildNode(riser)
        sparks = rising
        let trail = ArenaAvatar.particles(color: UIColor(white: 1, alpha: 0.9), size: 0.34 * CGFloat(size), life: 0.32)
        trail.emitterShape = SCNSphere(radius: CGFloat(0.25 * size))
        trail.particleVelocity = 0.15
        let feet = SCNNode()
        feet.simdPosition = SIMD3(0, 0.25, 0)
        feet.addParticleSystem(trail)
        node.addChildNode(feet)
        streak = trail
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
        // 不透明时才描边（半透明时会从身子里透出一圈黑）
        let solid = opacity > 0.97
        if solid != outlined {
            outlined = solid
            outlines.forEach { $0.isHidden = !solid }
        }
        ring.isHidden = !fighter.alive
        glow.isHidden = !(fighter.alive && fighter.superCharge >= 1)
        bubble.isHidden = !(fighter.alive && fighter.shield > 0)
        if !glow.isHidden {
            let pulse = (1 + 0.07 * Float(sin(clock * 6))) * size
            glow.simdScale = SIMD3(pulse, 1, pulse)
        }
        // 大招满了、超级充能也满了：光圈变紫（这一下放出去是加强版）
        let ready = fighter.hyperCharge >= 1
        if ready != hyperReady {
            hyperReady = ready
            glow.geometry?.firstMaterial?.diffuse.contents = (ready ? ArenaPalette.hyper : ArenaPalette.gold).withAlphaComponent(0.9)
        }
        // 超级充能开着：紫光一圈一圈往外跳、身上冒光点
        let hyper = fighter.alive && fighter.hyperTime > 0 && opacity > 0.05
        aura.isHidden = !hyper
        if hyper {
            let pulse = (1.05 + 0.12 * Float(sin(clock * 10))) * size
            aura.simdScale = SIMD3(pulse, 1, pulse)
        }
        sparks?.birthRate = hyper ? 40 : 0
        // 走得快：脚下拖一道光（超级充能是紫的）
        let fast = fighter.alive && (fighter.speedBoost > 0 || fighter.hyperTime > 0) && speed > 0.6 && opacity > 0.3
        streak?.birthRate = fast ? 60 : 0
        streak?.particleColor = fighter.hyperTime > 0 ? ArenaPalette.hyper : UIColor(white: 1, alpha: 0.9)
        // 被冰霜打中：身上发蓝
        let frozen = fighter.alive && fighter.slowed > 0
        if frozen != frosted, let instance {
            frosted = frozen
            instance.materials.forEach { $0.multiply.contents = frozen ? ArenaPalette.frost : baseTint }
        }

        if flashing && clock >= flashUntil {
            flashing = false
            for (material, original) in zip(instance?.materials ?? [], glows) {
                material.emission.contents = original ?? UIColor.black
            }
        }

        let pips = Int(fighter.ammo)
        if fighter.alive, pips < ammoPips, action == nil, (brawler == .ranger || brawler == .shade) {
            start(BrawlerLook.Move(clip: "1H_Ranged_Reload", from: 0.08, to: 0.72, seconds: 0.38), hold: false, fullBody: false)
        }
        ammoPips = pips

        guard !node.isHidden else { return }
        let moving = fighter.alive && speed > 0.6
        let wanted = cheering ? BrawlerLook.cheer : (moving ? look.run : look.idle)
        animate(dt: dt, moving: moving, base: wanted)
    }

    /// 开了一枪
    func attack() {
        // 剑圣转圈、书灵放环：整个身子跟着动，不要只动手
        let whole = brawler == .swordsman || brawler == .scholar
        start(look.attack, hold: false, fullBody: whole)
    }

    /// 放了大招（冲锋、跳、转圈、喝酒、抬手、闪现整个身子都动）
    func special() {
        switch brawler {
        case .knight, .barbarian, .swordsman, .brewer, .scholar, .shade, .darter:
            start(look.special, hold: false, fullBody: true)
        default:
            start(look.special, hold: false, fullBody: false)
        }
    }

    /// 挨打：白一下。打得重、而且这一下没在出招，才缩一下身子
    func flash(clock: Double, flinch: Bool = false) {
        flashUntil = clock + 0.09
        if flinch, deadSince == nil, action == nil || (action?.elapsed ?? 0) > (action?.move.seconds ?? 0) * 0.65 {
            start(BrawlerLook.Move(clip: "Hit_A", from: 0.05, to: 0.5, seconds: 0.2), hold: false, fullBody: false)
        }
        guard !flashing, let instance else { return }
        flashing = true
        instance.materials.forEach { $0.emission.contents = UIColor(white: 0.7, alpha: 1) }
    }

    /// 摆一个静止的姿势（画头像用）
    func hold(_ name: String, at time: Float) {
        guard let model, let instance, let clip = model.clips[name] else { return }
        var pose = model.restPose
        clip.sample(at: time, into: &pose)
        apply(pose, to: instance, nodes: model.animated)
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
        apply(pose, to: instance, nodes: model.animated)
    }

    /// 只在主线程写，而且这根骨骼得在、变换得是有限数。半初始化的骨头不写，避免和渲染线程抢着 retain
    private func apply(_ pose: GLTFModel.Pose, to instance: GLTFModel.Instance, nodes: [Int]) {
        guard Thread.isMainThread else { return }
        for i in nodes {
            guard instance.nodes.indices.contains(i),
                  pose.rotation.indices.contains(i),
                  pose.translation.indices.contains(i),
                  pose.scale.indices.contains(i) else { continue }
            let node = instance.nodes[i]
            guard node.parent != nil else { continue }
            let m = pose.transform(i)
            guard m.columns.0.x.isFinite, m.columns.0.y.isFinite, m.columns.0.z.isFinite,
                  m.columns.3.x.isFinite, m.columns.3.y.isFinite, m.columns.3.z.isFinite else { continue }
            node.simdTransform = m
        }
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

    /// 材质原来不发光（没设、或者是黑的）
    private static func dark(_ contents: Any?) -> Bool {
        guard let contents else { return true }
        guard let color = contents as? UIColor else { return false }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return max(red, green, blue) < 0.05 || alpha < 0.05
    }

    /// 一直冒的光点（先不冒：birthRate 0，要的时候再开）
    static func particles(color: UIColor, size: CGFloat, life: CGFloat) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.loops = true
        system.birthRate = 0
        system.particleLifeSpan = life
        system.particleLifeSpanVariation = life * 0.3
        system.particleSize = size
        system.particleSizeVariation = size * 0.3
        system.particleColor = color
        system.particleImage = ArenaArt.dot
        system.blendMode = .additive
        system.isAffectedByGravity = false
        let fade = CAKeyframeAnimation()
        fade.values = [0, 1, 0]
        fade.keyTimes = [0, 0.2, 1]
        system.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        return system
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

/// 一个人头顶上的东西：名字（自己绿、队友蓝、对面红）、圆头粗血条（血量写在条上），自己的再加一排橙色弹药。
/// 贴在角色头顶，正对镜头（场景里的牌子，不走 SpriteKit）
@MainActor
final class ArenaTag {
    let node = SCNNode()
    private let name: ArenaText
    private let bar: ArenaBar
    private let number = ArenaText(size: 11, color: .white)
    private let starText = ArenaText(size: 13, color: ArenaPalette.gold)
    private var ammo: [ArenaBar] = []
    private var shownHealth = -1
    private var shownStars = -1
    private static let width: CGFloat = 58
    private static let barHeight: CGFloat = 12

    /// boss：骷髅王的血条长一倍、粗一点
    init(fighter: Fighter, isMe: Bool, ally: Bool, boss: Bool = false) {
        let width = boss ? 120 : ArenaTag.width, barHeight = boss ? 15 : ArenaTag.barHeight
        name = ArenaText(size: boss ? 15 : 12, color: isMe ? ArenaPalette.myName : (ally ? ArenaPalette.allyName : ArenaPalette.enemyName))
        bar = ArenaBar(width: width, height: barHeight, color: isMe ? ArenaPalette.mine : (ally ? ArenaPalette.blue : ArenaPalette.red))
        name.set(isMe ? "我" : fighter.name)
        let barH = Float(barHeight / 55)
        name.node.simdPosition = SIMD3(0, barH / 2 + 0.18, 0.01)
        starText.node.simdPosition = SIMD3(0, barH / 2 + 0.42, 0.01)
        number.node.simdPosition = SIMD3(0, 0, 0.02)
        node.addChildNode(bar.node)
        node.addChildNode(number.node)
        node.addChildNode(name.node)
        node.addChildNode(starText.node)
        if isMe {
            let gap: Float = 3 / 55
            let segment = (Float(width) / 55 - gap * 2) / 3
            for k in 0..<3 {
                let piece = ArenaBar(width: CGFloat(segment * 55), height: 5, color: ArenaPalette.ammo, border: 1.2)
                piece.node.simdPosition = SIMD3(-Float(width) / 55 / 2 + segment / 2 + Float(k) * (segment + gap), -barH / 2 - 0.12, 0)
                node.addChildNode(piece.node)
                ammo.append(piece)
            }
        }
        node.faceCamera()
        node.isHidden = true
    }

    /// 人还活着、看得到才显示。牌子跟着角色走，不用再换算屏幕坐标
    func update(_ fighter: Fighter, opacity: Float) {
        guard fighter.alive, opacity > 0.05 else {
            node.isHidden = true
            return
        }
        node.isHidden = false
        node.opacity = CGFloat(min(1, opacity * 1.4))
        bar.set(CGFloat(fighter.health) / CGFloat(max(fighter.maxHealth, 1)))
        if fighter.health != shownHealth {
            shownHealth = fighter.health
            number.set("\(max(fighter.health, 0))")
        }
        let mark = fighter.stars > 0 ? fighter.stars : -fighter.cubes
        if mark != shownStars {
            shownStars = mark
            starText.set(fighter.stars > 0 ? "★\(fighter.stars)" : (fighter.cubes > 0 ? "⚡\(fighter.cubes)" : ""),
                         color: fighter.stars > 0 ? ArenaPalette.gold : ArenaPalette.myName)
        }
        for (k, piece) in ammo.enumerated() {
            let part = CGFloat(min(max(fighter.ammo - Double(k), 0), 1))
            piece.set(part, dim: part < 1)
        }
    }
}
