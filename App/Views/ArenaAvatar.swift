import SceneKit
import UIKit
import simd

/// 场上的一个人（3D）：模型、脚下的圈、大招攒满的光圈；每帧按这个人现在的样子摆位置、转身、放动作。
/// 动作分两层：底下是站着 / 跑 / 欢呼（换的时候淡过去），上面是出手、放大招、倒下（跑着出手只换上半身，腿接着跑）
@MainActor
final class ArenaAvatar {
    /// 角色模型缩多小（模型大约 2.3 高，缩完比一格高一点）
    static let scale: Float = 0.76
    /// 血条画在离地多高。大头和帽子大约到 2 米，再低会被头挡住
    static let headHeight: Float = 1.90

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
    /// 是不是自己（大招攒满时自己是金边，队友蓝、对面红）
    private let mine: Bool
    private let teamColor: UIColor
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
    /// 大招攒满：身上加一圈高对比的光，敌我颜色不一样
    private var superLit = false
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
    /// 挥击时把胳膊的旋转再推远一点，缩得很小也看得见
    private let swingBones: [Int]
    /// 出手、挨打时身子和头再多动一点
    private let torsoBones: [Int]
    /// 站着的时候胸口慢慢起伏
    private let chestBone: Int?
    /// 跑起来身子前倾，停下来再立直
    private var lean: Float = 0
    /// 挨打时往后仰一下，很快回到前倾
    private var recoil: Float = 0

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
        /// 换弹：不论站着还是跑，都只换上半身，腿继续走
        var upperOnly = false
    }

    private var base: Playing?
    private var fading: Playing?
    private var fade: Float = 1
    private var action: Action?
    private var angle: Float = 0
    private var aimAngle: Float = 0
    /// 身子本来多大。挨打时在这上面弹一下，弹完改回去
    private var bodyScale: Float = 1
    private var punch: Float = 0
    private var lastPosition: V2?
    /// 看起来走得多快（按每帧挪了多远算，联机收到的别人也一样）
    private var speed: Float = 0
    private(set) var opacity: Float = 0
    private var placedOpacity = false
    private var concealmentRim: SCNMaterial?
    private var concealmentHold: Float = 0
    private var showingConcealment = false
    private(set) var concealmentAmount: Float = 0
    private var concealmentMaterials: [SCNMaterial] = []

    // Screen-ray stipple discards the SAME samples in every mesh layer. Remaining
    // samples stay opaque and write depth; no transparent skeleton sorting.
    static let concealmentFragment = """
        #pragma arguments
        float arenaConcealment;
        #pragma opaque
        #pragma body
        if (arenaConcealment > 0.001) {
        float2 cell = floor((_surface.position.xy / max(abs(_surface.position.z), 0.001)) * 900.0);
        float pattern = fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
        if (pattern < arenaConcealment * 0.58) { discard_fragment(); }
        _output.color.rgb = mix(_output.color.rgb, _output.color.rgb * float3(0.65, 0.88, 1.0), arenaConcealment * 0.65);
        }
        """

    private func prepareConcealment() {
        var copies: [ObjectIdentifier: SCNMaterial] = [:]
        let owned = Set((instance?.materials ?? []).map { ObjectIdentifier($0) })
        body.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            // Geometry is per instance; material copies prevent a concealed ally
            // from changing another hero or the globally shared outline material.
            geometry.materials = geometry.materials.map { original in
                let key = ObjectIdentifier(original)
                if let copy = copies[key] { return copy }
                let copy = owned.contains(key) ? original : original.copy() as! SCNMaterial
                var modifiers = copy.shaderModifiers ?? [:]
                let previous = modifiers[.fragment] ?? ""
                modifiers[.fragment] = Self.concealmentFragment + "\n" + previous.replacingOccurrences(of: "#pragma body", with: "")
                copy.shaderModifiers = modifiers
                copy.setValue(Float(0), forKey: "arenaConcealment")
                copies[key] = copy
                return copy
            }
        }
        concealmentMaterials = Array(copies.values)
    }
    private var deadSince: Double?
    private var flashUntil: Double = 0
    private var flashing = false
    private var placed = false
    private var ammoPips = 3
    private var pose = GLTFModel.Pose(translation: [], rotation: [], scale: [])
    private var previous = GLTFModel.Pose(translation: [], rotation: [], scale: [])
    private var layer = GLTFModel.Pose(translation: [], rotation: [], scale: [])

    /// skin：穿第几套皮肤（0 原来的样子）
    init(brawler: Brawler, color: UIColor, isMe: Bool, decorated: Bool = true, size: Float = 1, skin: Int = 0, stageLit: Bool = false) {
        self.brawler = brawler
        self.mine = isMe
        self.teamColor = color
        self.size = size
        look = BrawlerLook.of(brawler)
        model = ArenaModels.shared.character(brawler)
        if let model {
            instance = model.instantiate(outline: look.authored ? nil : ArenaArt.outline)
            upper = model.node(named: "spine").map { Array(model.subtree(of: $0).intersection(model.animated)) } ?? []
            swingBones = ["upperarm.l", "upperarm.r", "lowerarm.l", "lowerarm.r"].compactMap { model.node(named: $0) }
            torsoBones = ["spine", "chest", "head"].compactMap { model.node(named: $0) }
            chestBone = model.node(named: "chest")
        } else {
            instance = nil
            upper = []
            swingBones = []
            torsoBones = []
            chestBone = nil
        }
        if let instance {
            for name in look.hidden {
                instance.root.childNode(withName: name, recursively: true)?.isHidden = true
            }
            for weapon in look.weapons {
                guard let piece = ArenaModels.shared.prop(weapon.file),
                      let bone = instance.root.childNode(withName: weapon.bone, recursively: true) else { continue }
                let held = piece.instantiate(shareMaterials: false, outline: ArenaArt.outline)
                held.root.simdPosition = weapon.position
                held.root.simdOrientation = weapon.rotation
                bone.addChildNode(held.root)
                outlines += held.outlines
                Self.paint(held.root, stage: stageLit)
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
            }
            instance.materials.forEach {
                if look.authored {
                    $0.lightingModel = .constant
                    ArenaArt.grade($0, ArenaArt.authoredCharacter)
                } else { Self.finish($0, stage: stageLit) }
            }
            glows = instance.materials.map { $0.emission.contents }
            body.addChildNode(instance.root)
            bodyScale = ArenaAvatar.scale * size * look.scale
            body.simdScale = SIMD3(repeating: bodyScale)
            // 手、脚、肩膀已经做在模型里，不再临时加球
        } else {
            // 模型读不出来：一个胶囊当身子
            let capsule = SCNCapsule(capRadius: 0.32, height: 1.2)
            capsule.firstMaterial = ArenaAvatar.material(color, lit: true)
            let torso = SCNNode(geometry: capsule)
            torso.simdPosition = SIMD3(0, 0.6, 0)
            body.addChildNode(torso)
        }
        node.addChildNode(body)
        prepareConcealment()
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
        concealmentRim = rim.firstMaterial
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
        let shine = ArenaAvatar.decal(ArenaPalette.gold.withAlphaComponent(0.09))
        shine.isDoubleSided = false
        shell.firstMaterial = shine
        bubble.geometry = shell
        bubble.simdPosition = SIMD3(0, 0.7 * size, 0)
        bubble.simdScale = SIMD3(size, 1.05 * size, size)
        bubble.castsShadow = false
        bubble.renderingOrder = 12
        bubble.isHidden = true
        // Keep a readable shield boundary without tinting the entire character.
        let shieldRim = SCNTorus(ringRadius: 0.78, pipeRadius: 0.018)
        shieldRim.ringSegmentCount = 32
        shieldRim.pipeSegmentCount = 6
        shieldRim.firstMaterial = ArenaAvatar.decal(ArenaPalette.gold.withAlphaComponent(0.75))
        let shieldEdge = SCNNode(geometry: shieldRim)
        shieldEdge.castsShadow = false
        shieldEdge.renderingOrder = 12
        bubble.addChildNode(shieldEdge)
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

    /// visible：这一队看不看得见他；translucent：角色处于草丛/隐身提示状态（实心模型、绿色脚圈）；cheering：赢了
    func update(_ fighter: Fighter, visible: Bool, translucent: Bool, cheering: Bool, dt: Float, clock: Double, sampleBones: Bool = true) {
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
            aimAngle = target
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
        let leaning = fighter.alive && speed > 0.6
        let leanTarget: Float = leaning && !look.authored ? -0.16 : 0
        lean += (leanTarget - lean) * min(1, dt * 6)
        if recoil > 0 { recoil = max(0, recoil - dt * 2.2) }
        body.simdEulerAngles = SIMD3(lean + recoil, angle, 0)

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
            target = visible ? 1 : 0
        }
        if fighter.alive || !placedOpacity {
            opacity = target
            placedOpacity = true
        } else {
            opacity += (target - opacity) * min(1, dt * 10)
        }
        // Concealment is communicated by a stable rim, not whole-skeleton alpha.
        // Enemy visibility and death fade still use the original visible/dead gates.
        concealmentHold = translucent && visible && fighter.alive ? 0.15 : max(0, concealmentHold - max(dt, 0))
        let concealed = fighter.alive && visible && concealmentHold > 0
        if concealed != showingConcealment {
            showingConcealment = concealed
            concealmentRim?.diffuse.contents = concealed ? UIColor(red: 0.35, green: 1, blue: 0.5, alpha: 1)
                : (mine ? UIColor.white.withAlphaComponent(0.95) : teamColor.withAlphaComponent(0.9))
        }
        let next = concealmentAmount + ((concealed ? Float(1) : 0) - concealmentAmount) * (1 - exp(-16 * max(dt, 0)))
        if abs(next - concealmentAmount) > 0.0001 {
            concealmentAmount = abs(next - (concealed ? 1 : 0)) < 0.001 ? (concealed ? 1 : 0) : next
            concealmentMaterials.forEach { $0.setValue(concealmentAmount, forKey: "arenaConcealment") }
        }
        node.opacity = CGFloat(opacity)
        node.isHidden = (!visible && fighter.alive) || opacity < 0.02
        // 不透明时才描边（半透明时会从身子里透出一圈黑）
        let solid = opacity > 0.97 && ArenaDiagnostics.shared.variant != .noCharacterOutlines
        if solid != outlined {
            outlined = solid
            outlines.forEach { $0.isHidden = !solid }
        }
        ring.isHidden = !fighter.alive
        glow.isHidden = !(fighter.alive && fighter.superCharge >= 1)
        bubble.isHidden = !(fighter.alive && fighter.shield > 0)
        if !glow.isHidden {
            let pulse = (1 + 0.18 * Float(sin(clock * 6))) * size
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
        if fast {
            streak?.birthRate = 24
            streak?.particleColor = fighter.hyperTime > 0 ? ArenaPalette.hyper : UIColor(white: 1, alpha: 0.9)
        } else if fighter.alive && speed > 0.6 && opacity > 0.3 {
            streak?.birthRate = 8
            streak?.particleColor = UIColor(white: 0.8, alpha: 0.45)
        } else {
            streak?.birthRate = 0
        }
        // 被冰霜打中：身上发蓝
        if [.noParticles, .noNumbersOrParticles].contains(ArenaDiagnostics.shared.variant) {
            sparks?.birthRate = 0
            streak?.birthRate = 0
        }
        let frozen = fighter.alive && fighter.slowed > 0
        if frozen != frosted, let instance {
            frosted = frozen
            instance.materials.forEach { $0.multiply.contents = frozen ? ArenaPalette.frost : baseTint }
        }
        let charged = fighter.alive && fighter.superCharge >= 1 && !frosted && !flashing
        if charged != superLit {
            superLit = charged
            paintCharge(charged)
        }

        if flashing && clock >= flashUntil {
            flashing = false
            if superLit { paintCharge(true) } else { restoreGlow() }
        }

        let pips = Int(fighter.ammo.rounded(.down))
        // 弹回来的那一发才做换弹，而且只动手。开枪那一下不算换弹，免得把跑和出手盖住
        if fighter.alive, pips > ammoPips, action == nil, (brawler == .ranger || brawler == .shade) {
            let reload = look.authored ? BrawlerLook.Move(clip: "1H_Ranged_Reload", seconds: 0.65)
                : BrawlerLook.Move(clip: "1H_Ranged_Reload", from: 0.08, to: 0.72, seconds: 0.28)
            start(reload, hold: false, fullBody: false, upperOnly: true)
        }
        ammoPips = pips

        if punch > 0 { punch = max(0, punch - dt) }
        let bob = !look.authored && fighter.alive && speed > 0.6 ? abs(sin(Float(clock) * 14)) * 0.07 : 0
        let k = bodyScale * (look.authored ? 1 : 1 + punch * 0.9)
        body.simdScale = SIMD3(k * (1 + bob * 0.25), k * (1 - bob), k * (1 + bob * 0.25))

        let moving = fighter.alive && speed > 0.6
        let wanted = cheering ? BrawlerLook.cheer : (moving ? look.run : look.idle)
        ArenaDiagnostics.shared.measure(.animation) {
            animate(dt: dt, moving: moving, base: wanted, samplePose: !node.isHidden && sampleBones)
        }
    }


    /// 贴图保持原色，明暗和边光在着色器里算，不再整个人乘一层灰。描边材质别动
    private static func finish(_ material: SCNMaterial, stage: Bool = false) {
        guard material !== ArenaArt.outline else { return }
        material.lightingModel = .constant
        ArenaArt.grade(material, stage ? ArenaArt.stageShade(material) : ArenaArt.characterToon)
    }

    private static func paint(_ node: SCNNode, stage: Bool = false) {
        node.geometry?.materials.forEach { finish($0, stage: stage) }
        node.enumerateChildNodes { child, _ in child.geometry?.materials.forEach { finish($0, stage: stage) } }
    }

    /// 大招攒满时给身上打一层亮光；关掉就回到原来的眼睛光
    private static func chargeEmission(_ color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * 0.12, green: g * 0.12, blue: b * 0.12, alpha: 1)
    }

    private func paintCharge(_ on: Bool) {
        guard let instance else { return }
        if on {
            let glow = mine
                ? UIColor(red: 0.12, green: 0.08, blue: 0.01, alpha: 1)
                : Self.chargeEmission(teamColor)
            instance.materials.forEach { $0.emission.contents = glow }
        } else {
            restoreGlow()
        }
    }

    private func restoreGlow() {
        for (material, original) in zip(instance?.materials ?? [], glows) {
            material.emission.contents = original ?? UIColor.black
        }
    }

    /// 大厅展台的轻出手：整个人跟着挥，比场上那一下稍长，好让人看见。不改对局里的出手
    func showcaseSwing() {
        let move = look.attack
        start(BrawlerLook.Move(clip: move.clip, from: move.from, to: move.to, seconds: max(move.seconds, 0.62)),
              hold: false, fullBody: true)
    }

    /// 开了一枪
    func attack() {
        alignAuthoredShot()
        // 剑圣转圈、书灵放环：整个身子跟着动，不要只动手
        let whole = brawler == .swordsman || brawler == .scholar
        start(look.attack, hold: false, fullBody: whole)
    }

    /// The crossbow is already aimed in the authored rest pose. Match the simulation's
    /// instant release direction before sampling recoil, without moving the collision body.
    private func alignAuthoredShot() {
        guard look.authored else { return }
        angle = aimAngle
        body.simdEulerAngles = SIMD3(0, angle, 0)
    }

    var muzzlePosition: SIMD3<Float>? {
        guard look.authored, let muzzle = instance?.root.childNode(withName: "muzzle", recursively: true) else { return nil }
        return muzzle.simdWorldPosition
    }

    /// 放了大招（冲锋、跳、转圈、喝酒、抬手、闪现整个身子都动）
    func special() {
        alignAuthoredShot()
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
        punch = 0.28
        recoil = look.authored ? 0 : 0.2
        if flinch, deadSince == nil, action == nil || (action?.elapsed ?? 0) > (action?.move.seconds ?? 0) * 0.65 {
            let hit = look.authored ? BrawlerLook.Move(clip: "Hit_A", seconds: 0.24)
                : BrawlerLook.Move(clip: "Hit_A", from: 0.05, to: 0.5, seconds: 0.2)
            start(hit, hold: false, fullBody: false)
        }
        guard !flashing, let instance else { return }
        flashing = true
        instance.materials.forEach { $0.emission.contents = UIColor(white: 0.22, alpha: 1) }
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

    private func start(_ move: BrawlerLook.Move, hold: Bool, fullBody: Bool, upperOnly: Bool = false) {
        guard let clip = model?.clips[move.clip], clip.duration > 0 else { return }
        action = Action(clip: clip, move: move, hold: hold, fullBody: fullBody, upperOnly: upperOnly)
    }

    private func animate(dt: Float, moving: Bool, base wanted: String, samplePose: Bool) {
        guard let model, let instance else { return }
        // 底下一层：站着 / 跑 / 欢呼，换的时候 0.15 秒淡过去
        if base?.clip.name != wanted, let clip = model.clips[wanted], clip.duration > 0 {
            fading = base
            fade = base == nil ? 1 : 0
            base = Playing(clip: clip)
        }
        if var playing = base {
            let strideSpeed = look.authored ? 2.4 * bodyScale : 2.4
            playing.rate = playing.clip.name == look.run
                ? min(max(speed / strideSpeed, look.authored ? 0.25 : 0.75), look.authored ? 2.5 : 1.4) : 1
            playing.time += dt * playing.rate
            base = playing
        }
        fade = min(1, fade + dt / 0.15)
        if fade >= 1 { fading = nil }
        if var old = fading {
            old.time += dt * old.rate
            fading = old
        }
        // Hidden fighters still age their actions, but do not sample or write bones.
        // Otherwise a shot fired in a bush resumes seconds later when revealed.
        if var current = action {
            current.elapsed += dt
            action = current.elapsed >= max(current.move.seconds, 0.01) && !current.hold ? nil : current
        }
        guard samplePose else { return }
        pose.reset(from: model.restPose)
        if let base { base.clip.sample(at: Self.looped(base.time, base.clip.duration), into: &pose) }
        if let fading {
            previous.reset(from: model.restPose)
            fading.clip.sample(at: Self.looped(fading.time, fading.clip.duration), into: &previous)
            previous.blend(toward: pose, weight: fade, nodes: model.animated)
            swap(&pose, &previous)
        }

        // 上面一层：出手、大招、倒下
        if let current = action {
            let progress = current.elapsed / max(current.move.seconds, 0.01)
            let linear = min(progress, 1)
            // 前半段走得快，挥出去那一下先到，后半段收回来
            let eased = look.authored ? linear : 1 - (1 - linear) * (1 - linear)
            let t = current.move.from + (current.move.to - current.move.from) * eased
            layer.reset(from: model.restPose)
            current.clip.sample(at: t * current.clip.duration, into: &layer)
            let fadeIn: Float = look.authored ? 1 : min(1, current.elapsed / 0.06)
            let fadeOut = current.hold ? 1 : min(1, (1 - progress) * current.move.seconds / 0.22)
            let weight = min(fadeIn, fadeOut)
            if current.upperOnly || (!current.fullBody && moving) {
                pose.blend(toward: layer, weight: weight, nodes: upper)
            } else {
                pose.blend(toward: layer, weight: weight, nodes: model.animated)
            }
        }
        accent(&pose, rest: model.restPose, moving: moving)
        apply(pose, to: instance, nodes: model.animated)
    }

    /// 片段本身是写实的，幅度小。在静止姿势和当前姿势之间再推一截，相当于加一层，不新做动画
    private func accent(_ pose: inout GLTFModel.Pose, rest: GLTFModel.Pose, moving: Bool) {
        guard !look.authored else { return }
        let name = action?.clip.name
        let attacking = name != nil && name != "Hit_A" && name != BrawlerLook.death.clip
        let hit = name == "Hit_A"
        let armGain: Float = attacking ? 1.55 : (moving ? 1.28 : 1)
        let torsoGain: Float = attacking ? 1.28 : (hit ? 1.45 : 1)
        if armGain > 1 { push(bones: swingBones, gain: armGain, pose: &pose, rest: rest) }
        if torsoGain > 1 { push(bones: torsoBones, gain: torsoGain, pose: &pose, rest: rest) }
        if !moving, !attacking, !hit, let chest = chestBone, pose.scale.indices.contains(chest) {
            let wave = sin((base?.time ?? 0) * 2.4)
            pose.scale[chest] *= 1 + wave * 0.045
        }
    }

    private func push(bones: [Int], gain: Float, pose: inout GLTFModel.Pose, rest: GLTFModel.Pose) {
        for i in bones {
            guard pose.rotation.indices.contains(i), rest.rotation.indices.contains(i) else { continue }
            pose.rotation[i] = GLTFModel.exaggerated(rest.rotation[i], pose.rotation[i], gain)
        }
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

/// 一个人头顶上的东西：名字、大号血量、细血条。能量方块用 ◆。贴在角色头顶，正对镜头。
@MainActor
final class ArenaTag {
    let node = SCNNode()
    private let name: ArenaText
    private let bar: ArenaBar
    private let number: ArenaText
    private let starText = ArenaText(size: 13, color: ArenaPalette.gold)
    private var ammo: [ArenaBar] = []
    private var shownHealth = -1
    private var shownStars = -1
    private let healthy: UIColor
    private static let width: CGFloat = 64
    private static let barHeight: CGFloat = 10

    /// boss：骷髅王的血条长一倍、粗一点
    init(fighter: Fighter, isMe: Bool, ally: Bool, boss: Bool = false) {
        let width = boss ? 120 : ArenaTag.width, barHeight = boss ? 15 : ArenaTag.barHeight
        let healthColor = isMe ? ArenaPalette.myName : (ally ? ArenaPalette.allyName : ArenaPalette.enemyName)
        let barColor = isMe ? ArenaPalette.mine : (ally ? ArenaPalette.blue : ArenaPalette.red)
        healthy = barColor
        name = ArenaText(size: boss ? 14 : 10, color: healthColor)
        number = ArenaText(size: boss ? 18 : 13, color: healthColor)
        bar = ArenaBar(width: width, height: barHeight, color: barColor)
        name.set(fighter.name)
        let barH = Float(barHeight / 55)
        let numberH = Float(boss ? 18 : 13) / 48
        let nameH = Float(boss ? 14 : 10) / 48
        number.node.simdPosition = SIMD3(0, barH / 2 + numberH / 2 + 0.04, 0.02)
        name.node.simdPosition = SIMD3(0, barH / 2 + numberH + nameH / 2 + 0.08, 0.01)
        starText.node.simdPosition = SIMD3(0, barH / 2 + numberH + nameH + 0.2, 0.01)
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
        let ratio = CGFloat(fighter.health) / CGFloat(max(fighter.maxHealth, 1))
        bar.set(ratio)
        if ratio < 0.28 {
            bar.color = UIColor(red: 1, green: 0.28, blue: 0.22, alpha: 1)
        } else if ratio < 0.55 {
            bar.color = ArenaPalette.gold
        } else {
            bar.color = healthy
        }
        if fighter.health != shownHealth {
            let dropped = shownHealth >= 0 && fighter.health < shownHealth
            shownHealth = fighter.health
            number.set("\(max(fighter.health, 0))")
            if dropped {
                number.node.removeAllActions()
                number.node.simdScale = SIMD3(repeating: 1.35)
                number.node.runAction(.scale(to: 1, duration: 0.12))
            }
        }
        let mark = fighter.stars > 0 ? fighter.stars : -fighter.cubes
        if mark != shownStars {
            shownStars = mark
            starText.set(fighter.stars > 0 ? "★\(fighter.stars)" : (fighter.cubes > 0 ? "◆\(fighter.cubes)" : ""),
                         color: ArenaPalette.gold)
        }
        for (k, piece) in ammo.enumerated() {
            let part = CGFloat(min(max(fighter.ammo - Double(k), 0), 1))
            piece.set(part, dim: part < 1)
        }
    }
}

