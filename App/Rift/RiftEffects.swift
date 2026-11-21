import SceneKit
import UIKit

/// 战斗特效：刀光拖尾、命中火花、冲击波、飞行道具、变身光环、影分身。
/// 全部用代码生成的几何体和粒子，不依赖外部特效资源。
@MainActor
final class RiftEffects {
    private let scene: SCNScene
    private let root = SCNNode()
    private var trails: [[RiftTrail]] = [[], []]
    private var projectileNodes: [Int: SCNNode] = [:]
    private var auras: [SCNParticleSystem?] = [nil, nil]
    private var auraLights: [SCNNode?] = [nil, nil]
    private var transientNodes: [(SCNNode, CFTimeInterval)] = []
    private var shadowClones: [RiftRig?] = [nil, nil]
    private var poseHistory: [[RiftPose]] = [[], []]
    private var dragons: [SCNNode?] = [nil, nil]

    init(scene: SCNScene, rigs: [RiftRig]) {
        self.scene = scene
        scene.rootNode.addChildNode(root)
        for (i, rig) in rigs.enumerated() {
            let color = Self.uiColor(RiftPalette.accent(rig.hero))
            var list = [RiftTrail(color: color, width: rig.hero == .liuQuanwei ? 1.25 : 1)]
            if rig.hasOffhandBlade { list.append(RiftTrail(color: color, width: 1)) }
            for t in list { root.addChildNode(t.node) }
            trails[i] = list
        }
    }

    static func uiColor(_ c: SIMD3<Float>, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: alpha)
    }

    // MARK: 每帧

    func update(fight: RiftFight, rigs: [RiftRig], poses: [RiftPose], now: CFTimeInterval) {
        for i in 0..<2 {
            let f = fight.fighters[i]
            let rig = rigs[i]
            let swinging: Bool = {
                guard f.state == .attacking, let m = f.move, m.damage > 0 || m.style == .transform else { return false }
                if m.style == .transform || m.projectile != nil { return false }
                return f.stateFrame >= m.startup - 2 && f.stateFrame <= m.startup + m.active + 3
            }()
            let pairs: [(SCNNode, SCNNode)] = rig.hasOffhandBlade
                ? [(rig.bladeTip, rig.bladeBase), (rig.offTip, rig.offBase)]
                : [(rig.bladeTip, rig.bladeBase)]
            for (k, pair) in pairs.enumerated() where k < trails[i].count {
                trails[i][k].sample(tip: pair.0.presentation.worldPosition, base: pair.1.presentation.worldPosition,
                                    active: swinging, boost: f.isTransformed)
            }
            updateAura(i, fighter: f, rig: rig)
            updateShadowClone(i, fighter: f, rig: rig, pose: poses[i])
            updateDragon(i, fighter: f, rig: rig, now: now)
        }
        syncProjectiles(fight)
        transientNodes.removeAll { node, expiry in
            if now > expiry { node.removeFromParentNode(); return true }
            return false
        }
    }

    // MARK: 命中

    func hit(_ h: RiftHitEvent, now: CFTimeInterval) {
        let pos = SCNVector3(Float(h.x), Float(h.y), 0.2)
        let accent = RiftPalette.accent(h.heroID)
        switch h.kind {
        case .block:
            burst(at: pos, color: UIColor(red: 0.8, green: 0.9, blue: 1, alpha: 1), count: 18, speed: 3, size: 0.05, life: 0.18, streak: true)
            flash(at: pos, color: UIColor(white: 1, alpha: 0.8), size: 0.6, life: 0.08, now: now)
        case .parry:
            burst(at: pos, color: UIColor(red: 0.5, green: 0.95, blue: 1, alpha: 1), count: 60, speed: 6, size: 0.06, life: 0.35, streak: true)
            flash(at: pos, color: UIColor(red: 0.6, green: 1, blue: 1, alpha: 1), size: 1.8, life: 0.15, now: now)
            ring(at: pos, color: UIColor(red: 0.5, green: 1, blue: 1, alpha: 1), size: 2.4, life: 0.3, vertical: true, now: now)
        case .guardBreak:
            burst(at: pos, color: .red, count: 70, speed: 5, size: 0.08, life: 0.4, streak: true)
            ring(at: pos, color: .red, size: 2.6, life: 0.35, vertical: true, now: now)
        case .echo:
            burst(at: pos, color: Self.uiColor(RiftPalette.secondary(h.heroID)), count: 14, speed: 2.5, size: 0.06, life: 0.25, streak: false)
        case .armor:
            burst(at: pos, color: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), count: 20, speed: 3, size: 0.06, life: 0.2, streak: true)
        case .hit, .counterHit:
            let tier = h.tier.rawValue
            let color = Self.uiColor(accent)
            burst(at: pos, color: color, count: 24 + tier * 22, speed: 3.5 + Float(tier) * 1.6, size: 0.05 + 0.015 * CGFloat(tier),
                  life: 0.22 + 0.06 * Double(tier), streak: true)
            burst(at: pos, color: UIColor(red: 0.9, green: 0.08, blue: 0.08, alpha: 1), count: 6 + tier * 6, speed: 2, size: 0.07,
                  life: 0.3, streak: false, gravity: true)
            flash(at: pos, color: UIColor(white: 1, alpha: 1), size: 0.7 + 0.45 * CGFloat(tier), life: 0.07 + 0.02 * Double(tier), now: now)
            slashMark(at: pos, color: color, size: 0.9 + 0.3 * CGFloat(tier), now: now)
            if h.tier >= .heavy {
                ring(at: SCNVector3(pos.x, 0.03, 0), color: color, size: 2.4 + CGFloat(tier), life: 0.35, vertical: false, now: now)
            }
            if h.kind == .counterHit {
                ring(at: pos, color: .orange, size: 1.6, life: 0.2, vertical: true, now: now)
            }
            if h.style == .groundSlam {
                dust(at: SCNVector3(pos.x, 0.05, 0), now: now)
            }
        }
    }

    func swing(side: Int, style: RiftMoveStyle, rig: RiftRig, now: CFTimeInterval) {
        if style == .groundSlam || style == .overhead {
            // 落地重击的尘土在命中/落斧时再出
        }
        if style == .transform {
            let p = rig.root.presentation.worldPosition
            let color = Self.uiColor(RiftPalette.accent(rig.hero))
            ring(at: SCNVector3(p.x, 0.05, 0), color: color, size: 5, life: 0.8, vertical: false, now: now)
            burst(at: SCNVector3(p.x, 1.0, 0), color: color, count: 160, speed: 5, size: 0.08, life: 0.9, streak: true)
            pillar(at: p, color: color, now: now)
        }
    }

    func land(side: Int, at x: Float, heavy: Bool, now: CFTimeInterval) {
        if heavy { dust(at: SCNVector3(x, 0.05, 0), now: now) }
    }

    // MARK: 构件

    private func particleSystem(color: UIColor, count: Int, speed: Float, size: CGFloat, life: Double, streak: Bool, gravity: Bool = false) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.particleImage = streak ? RiftTextures.spark : RiftTextures.softDot
        p.birthRate = CGFloat(count) / 0.03
        p.emissionDuration = 0.03
        p.loops = false
        p.particleLifeSpan = CGFloat(life)
        p.particleLifeSpanVariation = CGFloat(life * 0.4)
        p.particleVelocity = CGFloat(speed)
        p.particleVelocityVariation = CGFloat(speed * 0.6)
        p.spreadingAngle = 180
        p.particleSize = size
        p.particleSizeVariation = size * 0.5
        p.particleColor = color
        p.blendMode = .additive
        p.isLightingEnabled = false
        p.isAffectedByGravity = gravity
        p.acceleration = gravity ? SCNVector3(0, -6, 0) : SCNVector3Zero
        p.dampingFactor = 2.5
        if streak { p.orientationMode = .free; p.isBlackPassEnabled = false; p.stretchFactor = 0.04 }
        let fade = CAKeyframeAnimation()
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.5, 1]
        p.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        return p
    }

    private func burst(at pos: SCNVector3, color: UIColor, count: Int, speed: Float, size: CGFloat, life: Double, streak: Bool, gravity: Bool = false) {
        let p = particleSystem(color: color, count: count, speed: speed, size: size, life: life, streak: streak, gravity: gravity)
        scene.addParticleSystem(p, transform: SCNMatrix4MakeTranslation(pos.x, pos.y, pos.z))
    }

    private func billboard(_ image: UIImage, color: UIColor, size: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: size, height: size)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.multiply.contents = color
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        m.isDoubleSided = true
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.renderingOrder = 50
        return n
    }

    private func flash(at pos: SCNVector3, color: UIColor, size: CGFloat, life: Double, now: CFTimeInterval) {
        let n = billboard(RiftTextures.softDot, color: color, size: size)
        n.position = pos
        n.constraints = [SCNBillboardConstraint()]
        root.addChildNode(n)
        n.scale = SCNVector3(0.4, 0.4, 0.4)
        n.runAction(.group([.scale(to: 1.4, duration: life), .fadeOut(duration: life)]))
        transientNodes.append((n, now + life + 0.05))
    }

    private func slashMark(at pos: SCNVector3, color: UIColor, size: CGFloat, now: CFTimeInterval) {
        let n = billboard(RiftTextures.spark, color: color, size: size)
        n.scale = SCNVector3(0.25, 1.6, 1)
        n.position = pos
        n.eulerAngles.z = Float.random(in: -1.2...1.2)
        root.addChildNode(n)
        n.runAction(.group([.scale(to: 0.0, duration: 0.18), .fadeOut(duration: 0.18)]))
        n.runAction(.customAction(duration: 0.18) { node, t in node.scale = SCNVector3(0.25 * (1 - Float(t / 0.18)), 1.6 + Float(t) * 4, 1) })
        transientNodes.append((n, now + 0.25))
    }

    private func ring(at pos: SCNVector3, color: UIColor, size: CGFloat, life: Double, vertical: Bool, now: CFTimeInterval) {
        let n = billboard(RiftTextures.ring, color: color, size: size)
        n.position = pos
        if vertical { n.constraints = [SCNBillboardConstraint()] } else { n.eulerAngles.x = -.pi / 2 }
        n.scale = SCNVector3(0.1, 0.1, 0.1)
        root.addChildNode(n)
        n.runAction(.group([.scale(to: 1, duration: life), .fadeOut(duration: life)]))
        transientNodes.append((n, now + life + 0.05))
    }

    private func dust(at pos: SCNVector3, now: CFTimeInterval) {
        let p = particleSystem(color: UIColor(red: 0.6, green: 0.5, blue: 0.42, alpha: 0.6), count: 50, speed: 2.2, size: 0.35, life: 0.8, streak: false)
        p.blendMode = .alpha
        p.emittingDirection = SCNVector3(0, 1, 0)
        p.spreadingAngle = 80
        p.particleSizeVariation = 0.2
        scene.addParticleSystem(p, transform: SCNMatrix4MakeTranslation(pos.x, pos.y, pos.z))
        // 地裂
        let crack = billboard(RiftTextures.ring, color: UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1), size: 1.8)
        crack.eulerAngles.x = -.pi / 2
        crack.position = SCNVector3(pos.x, 0.02, 0)
        root.addChildNode(crack)
        crack.runAction(.sequence([.wait(duration: 0.3), .fadeOut(duration: 0.5)]))
        transientNodes.append((crack, now + 0.9))
    }

    private func pillar(at p: SCNVector3, color: UIColor, now: CFTimeInterval) {
        let cyl = SCNCylinder(radius: 0.6, height: 6)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = RiftTextures.radial(inner: color, outer: color.withAlphaComponent(0), size: 64)
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        cyl.materials = [m]
        let n = SCNNode(geometry: cyl)
        n.position = SCNVector3(p.x, 3, 0)
        n.opacity = 0.9
        root.addChildNode(n)
        n.runAction(.group([.scale(to: 1.8, duration: 0.7), .fadeOut(duration: 0.7)]))
        transientNodes.append((n, now + 0.8))
    }

    // MARK: 飞行道具

    private func syncProjectiles(_ fight: RiftFight) {
        var alive = Set<Int>()
        for p in fight.projectiles {
            alive.insert(p.id)
            let node = projectileNodes[p.id] ?? makeProjectile(p, hero: fight.fighters[p.owner].heroID)
            projectileNodes[p.id] = node
            node.position = SCNVector3(Float(p.x), Float(p.y), 0)
            node.eulerAngles.y = p.vx >= 0 ? 0 : .pi
        }
        for (id, node) in projectileNodes where !alive.contains(id) {
            node.runAction(.sequence([.fadeOut(duration: 0.12), .removeFromParentNode()]))
            projectileNodes[id] = nil
        }
    }

    private func makeProjectile(_ p: RiftProjectile, hero: RiftHeroID) -> SCNNode {
        let color = Self.uiColor(RiftPalette.accent(hero))
        let node = SCNNode()
        switch p.spec.style {
        case .groundSlam:
            // 裂地波：贴地推进的岩浆冲击
            let wave = billboard(RiftTextures.crescent, color: color, size: 1.4)
            wave.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
            wave.scale = SCNVector3(0.6, 1, 1)
            node.addChildNode(wave)
            let trail = particleSystem(color: UIColor(red: 1, green: 0.5, blue: 0.15, alpha: 1), count: 40, speed: 1.5, size: 0.18, life: 0.5, streak: false)
            trail.loops = true; trail.emissionDuration = 1; trail.birthRate = 120
            trail.emittingDirection = SCNVector3(0, 1, 0); trail.spreadingAngle = 40
            node.addParticleSystem(trail)
        case .dragonWave:
            // 金龙：一串鳞片节点，正弦摆动
            let head = SCNSphere(radius: 0.35); head.materials = [glow(color)]
            let h = SCNNode(geometry: head); h.scale = SCNVector3(1.4, 0.8, 0.8)
            node.addChildNode(h)
            for i in 1..<9 {
                let seg = SCNSphere(radius: 0.32 - CGFloat(i) * 0.028); seg.materials = [glow(color)]
                let s = SCNNode(geometry: seg)
                s.position = SCNVector3(-Float(i) * 0.32, 0, 0)
                s.runAction(.repeatForever(.customAction(duration: 1) { n, t in
                    n.position.y = sin(Float(t) * 2 * .pi + Float(i) * 0.7) * 0.25
                }))
                node.addChildNode(s)
            }
            let sparks = particleSystem(color: color, count: 60, speed: 1, size: 0.12, life: 0.6, streak: false)
            sparks.loops = true; sparks.emissionDuration = 1; sparks.birthRate = 160
            node.addParticleSystem(sparks)
        default:
            // 剑气：新月形光刃
            let blade = billboard(RiftTextures.crescent, color: color, size: 1.3)
            blade.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
            node.addChildNode(blade)
            let core = billboard(RiftTextures.crescent, color: .white, size: 0.9)
            core.eulerAngles = blade.eulerAngles
            node.addChildNode(core)
            let trail = particleSystem(color: color, count: 30, speed: 0.6, size: 0.1, life: 0.35, streak: false)
            trail.loops = true; trail.emissionDuration = 1; trail.birthRate = 90
            node.addParticleSystem(trail)
        }
        root.addChildNode(node)
        return node
    }

    private func glow(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.emission.contents = color
        m.transparency = 0.85
        m.blendMode = .add
        return m
    }

    // MARK: 变身

    private func updateAura(_ i: Int, fighter f: RiftFighter, rig: RiftRig) {
        let on = f.isTransformed || (f.state == .attacking && f.slot == .transform)
        if on && auras[i] == nil {
            let color = Self.uiColor(RiftPalette.accent(f.heroID))
            let p = SCNParticleSystem()
            p.particleImage = f.heroID == .wuYong ? RiftTextures.softDot : RiftTextures.spark
            p.birthRate = 90
            p.loops = true
            p.emissionDuration = 1
            p.particleLifeSpan = 0.7
            p.particleVelocity = 1.2
            p.emittingDirection = SCNVector3(0, 1, 0)
            p.spreadingAngle = 25
            p.particleSize = f.heroID == .wuYong ? 0.16 : 0.07
            p.particleColor = color
            p.blendMode = .additive
            p.emitterShape = SCNCylinder(radius: 0.35, height: 1.6)
            p.birthLocation = .surface
            let fade = CAKeyframeAnimation(); fade.values = [0, 1, 0]; fade.keyTimes = [0, 0.3, 1]
            p.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
            rig.auraNode.addParticleSystem(p)
            auras[i] = p
            let light = SCNLight()
            light.type = .omni
            light.color = color
            light.intensity = 350
            light.attenuationEndDistance = 4
            let ln = SCNNode(); ln.light = light; ln.position = SCNVector3(0, 0.6, 0.6)
            rig.auraNode.addChildNode(ln)
            auraLights[i] = ln
            rig.setGlow(1, color: color)
        } else if !on, let p = auras[i] {
            rig.auraNode.removeParticleSystem(p)
            auras[i] = nil
            auraLights[i]?.removeFromParentNode()
            auraLights[i] = nil
            rig.setGlow(0, color: .black)
        }
        // 盘古变身：体型变大
        let target: Float = Float(RiftRoster.spec(f.heroID).scale) * (f.isTransformed ? Float(f.spec.transform.scale) : 1)
        let current = rig.body.scale.x
        let next = current + (target - current) * 0.12
        rig.body.scale = SCNVector3(next, next, next)
    }

    /// 孙登影刃：身后跟随一个延迟几帧的暗影分身
    private func updateShadowClone(_ i: Int, fighter f: RiftFighter, rig: RiftRig, pose: RiftPose) {
        guard f.heroID == .sunDeng else { return }
        poseHistory[i].append(pose)
        if poseHistory[i].count > 6 { poseHistory[i].removeFirst() }
        if f.isTransformed {
            if shadowClones[i] == nil {
                let clone = RiftRig(hero: .sunDeng)
                clone.root.enumerateHierarchy { node, _ in
                    node.geometry?.materials.forEach { m in
                        m.lightingModel = .constant
                        m.diffuse.contents = UIColor(red: 0.25, green: 0.2, blue: 0.7, alpha: 1)
                        m.emission.contents = UIColor(red: 0.3, green: 0.25, blue: 1, alpha: 1)
                        m.transparency = 0.35
                        m.blendMode = .add
                        m.writesToDepthBuffer = false
                    }
                }
                clone.shadowBlob.isHidden = true
                root.addChildNode(clone.root)
                shadowClones[i] = clone
            }
            if let clone = shadowClones[i], let old = poseHistory[i].first {
                clone.apply(old)
                clone.root.position = SCNVector3(rig.root.position.x - Float(f.facing) * 0.35, rig.root.position.y, -0.15)
                clone.root.eulerAngles = rig.root.eulerAngles
            }
        } else if let clone = shadowClones[i] {
            clone.root.removeFromParentNode()
            shadowClones[i] = nil
        }
    }

    /// 徐骁始皇：金龙环绕
    private func updateDragon(_ i: Int, fighter f: RiftFighter, rig: RiftRig, now: CFTimeInterval) {
        guard f.heroID == .xuXiao || f.heroID == .wuYong else { return }
        if f.isTransformed, dragons[i] == nil {
            let color = f.heroID == .xuXiao ? Self.uiColor(RiftPalette.accent(.xuXiao)) : UIColor(red: 1, green: 0.3, blue: 0.1, alpha: 1)
            let holder = SCNNode()
            for k in 0..<14 {
                let s = SCNSphere(radius: CGFloat(0.09 - Double(k) * 0.005)); s.materials = [glow(color)]
                let n = SCNNode(geometry: s)
                n.name = "seg\(k)"
                holder.addChildNode(n)
            }
            rig.root.addChildNode(holder)
            dragons[i] = holder
        } else if !f.isTransformed, let d = dragons[i] {
            d.removeFromParentNode()
            dragons[i] = nil
        }
        if let d = dragons[i] {
            for (k, n) in d.childNodes.enumerated() {
                let a = Float(now * 3) - Float(k) * 0.25
                n.position = SCNVector3(cos(a) * 0.7, 1.0 + sin(a * 1.5) * 0.5 + Float(k) * 0.02, sin(a) * 0.7)
            }
        }
    }
}

/// 刀光拖尾：记录最近若干帧刀尖/刀根位置，生成渐隐三角带
@MainActor
final class RiftTrail {
    let node = SCNNode()
    private var tips: [SCNVector3] = []
    private var bases: [SCNVector3] = []
    private let color: UIColor
    private let width: Float
    private let maxSamples = 12
    private var fading = 0

    init(color: UIColor, width: Float) {
        self.color = color
        self.width = width
        node.renderingOrder = 40
    }

    func sample(tip: SCNVector3, base: SCNVector3, active: Bool, boost: Bool) {
        if active {
            fading = 0
            tips.append(tip)
            bases.append(lerp(base, tip, 1 - width * 0.55))
            if tips.count > maxSamples { tips.removeFirst(); bases.removeFirst() }
        } else if !tips.isEmpty {
            fading += 1
            tips.removeFirst(); bases.removeFirst()
        }
        rebuild(boost: boost)
    }

    private func lerp(_ a: SCNVector3, _ b: SCNVector3, _ t: Float) -> SCNVector3 {
        SCNVector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
    }

    private func rebuild(boost: Bool) {
        guard tips.count >= 2 else { node.geometry = nil; return }
        var verts: [SCNVector3] = []
        var colors: [SIMD4<Float>] = []
        var indices: [UInt16] = []
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let n = tips.count
        for k in 0..<n {
            let alpha = Float(k) / Float(n - 1)
            verts.append(tips[k]); verts.append(bases[k])
            let edge = SIMD4<Float>(min(1, Float(r) + 0.35 * alpha), min(1, Float(g) + 0.35 * alpha), min(1, Float(b) + 0.35 * alpha), alpha * (boost ? 1 : 0.85))
            colors.append(edge)
            colors.append(SIMD4<Float>(Float(r), Float(g), Float(b), 0))
        }
        for k in 0..<(n - 1) {
            let i = UInt16(k * 2)
            indices += [i, i + 1, i + 2, i + 1, i + 3, i + 2]
        }
        let vsrc = SCNGeometrySource(vertices: verts)
        let cdata = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let csrc = SCNGeometrySource(data: cdata, semantic: .color, vectorCount: colors.count, usesFloatComponents: true,
                                     componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geo = SCNGeometry(sources: [vsrc, csrc], elements: [element])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.white
        m.blendMode = .add
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        geo.materials = [m]
        node.geometry = geo
    }
}
