import SceneKit
import UIKit

/// 一个角色的骨骼姿势（弧度）。正值约定：手臂/腿“向前抬”，身体“向前倾”。
struct RiftPose {
    var rootYaw: Float = 0          // 整体绕竖轴转（旋风斩）
    var rootPitch: Float = 0        // 整体前后翻（倒地、击飞）
    var rootRoll: Float = 0
    var hipsY: Float = 0            // 下蹲（负）
    var hipsForward: Float = 0
    var lean: Float = 0             // 上身前倾
    var twist: Float = 0            // 上身扭转
    var head: Float = 0
    var rShoulder: Float = 0, rRaise: Float = 0, rElbow: Float = 0, rWrist: Float = 1.1
    var lShoulder: Float = 0, lRaise: Float = 0, lElbow: Float = 0, lWrist: Float = 1.1
    var rThigh: Float = 0, rKnee: Float = 0
    var lThigh: Float = 0, lKnee: Float = 0

    static func mix(_ a: RiftPose, _ b: RiftPose, _ t: Float) -> RiftPose {
        func m(_ x: Float, _ y: Float) -> Float { x + (y - x) * t }
        var p = RiftPose()
        p.rootYaw = m(a.rootYaw, b.rootYaw); p.rootPitch = m(a.rootPitch, b.rootPitch); p.rootRoll = m(a.rootRoll, b.rootRoll)
        p.hipsY = m(a.hipsY, b.hipsY); p.hipsForward = m(a.hipsForward, b.hipsForward)
        p.lean = m(a.lean, b.lean); p.twist = m(a.twist, b.twist); p.head = m(a.head, b.head)
        p.rShoulder = m(a.rShoulder, b.rShoulder); p.rRaise = m(a.rRaise, b.rRaise); p.rElbow = m(a.rElbow, b.rElbow); p.rWrist = m(a.rWrist, b.rWrist)
        p.lShoulder = m(a.lShoulder, b.lShoulder); p.lRaise = m(a.lRaise, b.lRaise); p.lElbow = m(a.lElbow, b.lElbow); p.lWrist = m(a.lWrist, b.lWrist)
        p.rThigh = m(a.rThigh, b.rThigh); p.rKnee = m(a.rKnee, b.rKnee)
        p.lThigh = m(a.lThigh, b.lThigh); p.lKnee = m(a.lKnee, b.lKnee)
        return p
    }
}

/// 程序生成的角色：骨骼节点 + 原创造型（衣甲、武器），头部可以换成真人头模。
@MainActor
final class RiftRig {
    let hero: RiftHeroID
    let root = SCNNode()
    let body = SCNNode()       // 承担缩放（变身变大）
    let hips = SCNNode()
    let chest = SCNNode()
    let neck = SCNNode()
    let headSocket = SCNNode()
    let rShoulder = SCNNode(), rElbow = SCNNode(), rHand = SCNNode()
    let lShoulder = SCNNode(), lElbow = SCNNode(), lHand = SCNNode()
    let rHip = SCNNode(), rKnee = SCNNode()
    let lHip = SCNNode(), lKnee = SCNNode()
    /// 刀光取样点（世界坐标由渲染器读取）
    let bladeTip = SCNNode(), bladeBase = SCNNode()
    let offTip = SCNNode(), offBase = SCNNode()
    let hasOffhandBlade: Bool
    let twoHanded: Bool
    private(set) var flashMaterials: [SCNMaterial] = []
    private(set) var glowMaterials: [SCNMaterial] = []
    let shadowBlob: SCNNode
    let auraNode = SCNNode()
    var scarf: [SCNNode] = []

    static let upperArm: Float = 0.30, foreArm: Float = 0.27, thigh: Float = 0.44, shin: Float = 0.44

    init(hero: RiftHeroID) {
        self.hero = hero
        hasOffhandBlade = hero == .sunDeng
        twoHanded = hero == .liuQuanwei || hero == .wuYong
        shadowBlob = RiftRig.makeShadowBlob()
        build()
    }

    // MARK: - 材质

    private func mat(_ color: UIColor, metal: CGFloat = 0, rough: CGFloat = 0.6, emission: UIColor? = nil, flash: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        if let emission { m.emission.contents = emission; glowMaterials.append(m) }
        if flash { flashMaterials.append(m) }
        return m
    }

    private func capsule(_ radius: CGFloat, _ length: Float, _ m: SCNMaterial, into parent: SCNNode, down: Bool = true) -> SCNNode {
        let g = SCNCapsule(capRadius: radius, height: CGFloat(length) + radius * 2)
        g.radialSegmentCount = 14
        g.heightSegmentCount = 1
        g.capSegmentCount = 8
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(0, down ? -length / 2 : length / 2, 0)
        parent.addChildNode(n)
        return n
    }

    private func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, chamfer: CGFloat = 0.02, _ m: SCNMaterial,
                     at p: SCNVector3, into parent: SCNNode, euler: SCNVector3 = SCNVector3Zero) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = p
        n.eulerAngles = euler
        parent.addChildNode(n)
        return n
    }

    // MARK: - 搭建

    private func build() {
        root.name = "rift.fighter.\(hero.rawValue)"
        root.addChildNode(body)
        root.addChildNode(shadowBlob)
        body.addChildNode(hips)
        hips.position = SCNVector3(0, 0.98, 0)
        hips.addChildNode(chest)
        chest.position = SCNVector3(0, 0.12, 0)
        chest.addChildNode(neck)
        neck.position = SCNVector3(0, 0.50, 0)
        neck.addChildNode(headSocket)
        headSocket.position = SCNVector3(0, 0.07, 0)

        for (s, x) in [(rShoulder, Float(-0.22)), (lShoulder, Float(0.22))] {
            chest.addChildNode(s); s.position = SCNVector3(x, 0.42, 0)
        }
        rShoulder.addChildNode(rElbow); rElbow.position = SCNVector3(0, -Self.upperArm, 0)
        lShoulder.addChildNode(lElbow); lElbow.position = SCNVector3(0, -Self.upperArm, 0)
        rElbow.addChildNode(rHand); rHand.position = SCNVector3(0, -Self.foreArm, 0)
        lElbow.addChildNode(lHand); lHand.position = SCNVector3(0, -Self.foreArm, 0)
        for (h, x) in [(rHip, Float(-0.11)), (lHip, Float(0.11))] {
            hips.addChildNode(h); h.position = SCNVector3(x, -0.04, 0)
        }
        rHip.addChildNode(rKnee); rKnee.position = SCNVector3(0, -Self.thigh, 0)
        lHip.addChildNode(lKnee); lKnee.position = SCNVector3(0, -Self.thigh, 0)

        switch hero {
        case .sunDeng: buildSun()
        case .wuYong: buildWu()
        case .liuQuanwei: buildLiu()
        case .xuXiao: buildXu()
        }
        buildPlaceholderHead()
        body.scale = SCNVector3(1, 1, 1) * Float(RiftRoster.spec(hero).scale)
        auraNode.position = SCNVector3(0, 1.0, 0)
        body.addChildNode(auraNode)
    }

    private func limbs(skin: SCNMaterial, sleeve: SCNMaterial, pants: SCNMaterial, boots: SCNMaterial,
                       armR: CGFloat = 0.055, legR: CGFloat = 0.075) {
        _ = capsule(armR * 1.1, Self.upperArm, sleeve, into: rShoulder)
        _ = capsule(armR * 1.1, Self.upperArm, sleeve, into: lShoulder)
        _ = capsule(armR, Self.foreArm, sleeve, into: rElbow)
        _ = capsule(armR, Self.foreArm, sleeve, into: lElbow)
        for hand in [rHand, lHand] {
            let g = SCNSphere(radius: armR * 1.15); g.segmentCount = 12; g.materials = [skin]
            hand.addChildNode(SCNNode(geometry: g))
        }
        _ = capsule(legR * 1.1, Self.thigh, pants, into: rHip)
        _ = capsule(legR * 1.1, Self.thigh, pants, into: lHip)
        _ = capsule(legR * 0.9, Self.shin, pants, into: rKnee)
        _ = capsule(legR * 0.9, Self.shin, pants, into: lKnee)
        for knee in [rKnee, lKnee] {
            _ = box(0.13, 0.08, 0.26, chamfer: 0.03, boots, at: SCNVector3(0, -Self.shin - 0.02, 0.05), into: knee)
            _ = box(0.12, 0.2, 0.13, chamfer: 0.03, boots, at: SCNVector3(0, -Self.shin + 0.08, 0), into: knee)
        }
    }

    private func torso(_ m: SCNMaterial, width: CGFloat = 0.36, depth: CGFloat = 0.22, waist: SCNMaterial? = nil) {
        // 胸腔（上宽下窄）
        let chestShape = SCNNode(geometry: {
            let g = SCNCylinder(radius: 1, height: 1); g.radialSegmentCount = 16; g.materials = [m]; return g
        }())
        chestShape.scale = SCNVector3(Float(width) / 2, 0.36, Float(depth) / 2)
        chestShape.position = SCNVector3(0, 0.27, 0)
        chest.addChildNode(chestShape)
        let shoulders = SCNNode(geometry: { let g = SCNCapsule(capRadius: 0.075, height: width + 0.12); g.materials = [m]; return g }())
        shoulders.eulerAngles.z = .pi / 2
        shoulders.position = SCNVector3(0, 0.42, 0)
        chest.addChildNode(shoulders)
        let belly = SCNNode(geometry: { let g = SCNCylinder(radius: 1, height: 1); g.radialSegmentCount = 16; g.materials = [waist ?? m]; return g }())
        belly.scale = SCNVector3(Float(width) * 0.42, 0.2, Float(depth) * 0.45)
        belly.position = SCNVector3(0, 0.02, 0)
        chest.addChildNode(belly)
        let pelvis = SCNNode(geometry: { let g = SCNSphere(radius: 1); g.segmentCount = 16; g.materials = [waist ?? m]; return g }())
        pelvis.scale = SCNVector3(Float(width) * 0.45, 0.12, Float(depth) * 0.5)
        pelvis.position = SCNVector3(0, -0.04, 0)
        hips.addChildNode(pelvis)
        let neckGeo = SCNCylinder(radius: 0.05, height: 0.12); neckGeo.materials = [skinMaterial]
        let neckNode = SCNNode(geometry: neckGeo); neckNode.position = SCNVector3(0, 0.0, 0)
        neck.addChildNode(neckNode)
    }

    private lazy var skinMaterial: SCNMaterial = mat(UIColor(red: 0.86, green: 0.68, blue: 0.55, alpha: 1), rough: 0.55)

    private func blade(length: Float, width: CGFloat, color: UIColor, edge: UIColor, guardColor: UIColor,
                       grip: Float = 0.2, in hand: SCNNode, tip: SCNNode, base: SCNNode, curve: Float = 0) {
        let holder = SCNNode()
        hand.addChildNode(holder)
        let gripMat = mat(UIColor(white: 0.12, alpha: 1), rough: 0.8)
        let g = SCNCylinder(radius: 0.022, height: CGFloat(grip)); g.materials = [gripMat]
        let gripNode = SCNNode(geometry: g)
        gripNode.position = SCNVector3(0, -grip * 0.15, 0)
        holder.addChildNode(gripNode)
        let guardNode = box(0.11, 0.025, 0.06, chamfer: 0.01, mat(guardColor, metal: 0.9, rough: 0.3), at: SCNVector3(0, -grip * 0.6, 0), into: holder)
        _ = guardNode
        let steel = mat(color, metal: 1, rough: 0.18, emission: edge.withAlphaComponent(0.0))
        let segments = 4
        var y = -grip * 0.6
        let segLen = length / Float(segments)
        for s in 0..<segments {
            let w = width * CGFloat(1 - Double(s) * 0.12)
            let seg = box(w, CGFloat(segLen) + 0.01, 0.012, chamfer: 0.004, steel,
                          at: SCNVector3(0, y - segLen / 2, Float(s) * curve), into: holder)
            seg.eulerAngles.x = -curve * 2
            y -= segLen
        }
        holder.addChildNode(base); base.position = SCNVector3(0, -grip * 0.6 - 0.05, 0)
        holder.addChildNode(tip); tip.position = SCNVector3(0, y, Float(segments) * curve)
    }

    private func buildSun() {
        let cloth = mat(UIColor(red: 0.08, green: 0.1, blue: 0.16, alpha: 1), rough: 0.8)
        let wrap = mat(UIColor(red: 0.18, green: 0.2, blue: 0.26, alpha: 1), rough: 0.7)
        let leather = mat(UIColor(red: 0.28, green: 0.18, blue: 0.12, alpha: 1), rough: 0.6)
        let red = mat(UIColor(red: 0.72, green: 0.08, blue: 0.08, alpha: 1), rough: 0.7)
        torso(cloth, width: 0.34, depth: 0.2, waist: wrap)
        limbs(skin: skinMaterial, sleeve: cloth, pants: wrap, boots: leather, armR: 0.05, legR: 0.07)
        // 护腕、腰带、背后的刀鞘
        for e in [rElbow, lElbow] { _ = capsule(0.058, 0.14, leather, into: e) }
        _ = box(0.36, 0.06, 0.24, chamfer: 0.02, red, at: SCNVector3(0, 0.0, 0), into: chest)
        _ = box(0.06, 0.5, 0.05, chamfer: 0.02, leather, at: SCNVector3(0.08, 0.25, -0.13), into: chest, euler: SCNVector3(0, 0, 0.5))
        _ = box(0.06, 0.5, 0.05, chamfer: 0.02, leather, at: SCNVector3(-0.08, 0.25, -0.13), into: chest, euler: SCNVector3(0, 0, -0.5))
        // 红色围巾（飘带）
        var parent = neck
        for i in 0..<5 {
            let seg = SCNNode(geometry: { let g = SCNBox(width: 0.1, height: 0.12, length: 0.015, chamferRadius: 0.005); g.materials = [red]; return g }())
            seg.position = i == 0 ? SCNVector3(0.05, -0.02, -0.1) : SCNVector3(0, -0.11, 0)
            seg.pivot = SCNMatrix4MakeTranslation(0, 0.06, 0)
            parent.addChildNode(seg)
            scarf.append(seg)
            parent = seg
        }
        let ring = SCNTorus(ringRadius: 0.075, pipeRadius: 0.03); ring.materials = [red]
        let ringNode = SCNNode(geometry: ring); ringNode.position = SCNVector3(0, 0.0, 0); neck.addChildNode(ringNode)
        let bladeColor = UIColor(red: 0.8, green: 0.86, blue: 0.95, alpha: 1)
        let edge = UIColor(red: 0.4, green: 0.65, blue: 1, alpha: 1)
        blade(length: 0.62, width: 0.045, color: bladeColor, edge: edge, guardColor: UIColor(white: 0.3, alpha: 1), grip: 0.16,
              in: rHand, tip: bladeTip, base: bladeBase, curve: 0.012)
        blade(length: 0.62, width: 0.045, color: bladeColor, edge: edge, guardColor: UIColor(white: 0.3, alpha: 1), grip: 0.16,
              in: lHand, tip: offTip, base: offBase, curve: 0.012)
    }

    private func buildWu() {
        let lacquer = mat(UIColor(red: 0.45, green: 0.05, blue: 0.06, alpha: 1), metal: 0.3, rough: 0.35)
        let black = mat(UIColor(red: 0.06, green: 0.05, blue: 0.06, alpha: 1), metal: 0.2, rough: 0.45)
        let gold = mat(UIColor(red: 0.85, green: 0.65, blue: 0.25, alpha: 1), metal: 1, rough: 0.3)
        let cloth = mat(UIColor(red: 0.12, green: 0.1, blue: 0.14, alpha: 1), rough: 0.85)
        torso(lacquer, width: 0.4, depth: 0.25, waist: black)
        limbs(skin: skinMaterial, sleeve: cloth, pants: cloth, boots: black, armR: 0.058, legR: 0.08)
        // 胸甲横条（胴）
        for i in 0..<4 {
            _ = box(0.44, 0.05, 0.28, chamfer: 0.015, i % 2 == 0 ? lacquer : black,
                    at: SCNVector3(0, 0.1 + Float(i) * 0.075, 0.0), into: chest)
        }
        // 大袖（肩甲）：层叠甲片
        for (shoulder, side) in [(rShoulder, Float(-1)), (lShoulder, Float(1))] {
            for i in 0..<4 {
                _ = box(0.2, 0.05, 0.22, chamfer: 0.01, i % 2 == 0 ? lacquer : black,
                        at: SCNVector3(side * 0.05, 0.03 - Float(i) * 0.055, 0), into: shoulder,
                        euler: SCNVector3(0, 0, side * 0.35))
            }
            _ = box(0.21, 0.015, 0.23, chamfer: 0.005, gold, at: SCNVector3(side * 0.05, 0.06, 0), into: shoulder,
                    euler: SCNVector3(0, 0, side * 0.35))
        }
        // 草摺（腰甲裙）
        for k in 0..<6 {
            let angle = Float(k) / 6 * .pi * 2
            let plate = box(0.15, 0.3, 0.025, chamfer: 0.01, k % 2 == 0 ? lacquer : black,
                            at: SCNVector3(sin(angle) * 0.17, -0.16, cos(angle) * 0.13), into: hips,
                            euler: SCNVector3(-0.2 * cos(angle), angle, 0.2 * sin(angle)))
            _ = plate
        }
        // 臂甲、胫甲
        for e in [rElbow, lElbow] { _ = capsule(0.064, 0.2, black, into: e) }
        for k in [rKnee, lKnee] { _ = capsule(0.085, 0.3, lacquer, into: k) }
        // 兜（头盔，不遮脸，适配真人头模高度）+ 金色前立
        let helmet = SCNSphere(radius: 0.165); helmet.segmentCount = 18; helmet.materials = [black]
        let helmetNode = SCNNode(geometry: helmet)
        helmetNode.scale = SCNVector3(1, 0.58, 1.05)
        helmetNode.position = SCNVector3(0, 0.24, -0.01)
        headSocket.addChildNode(helmetNode)
        let brim = SCNTube(innerRadius: 0.14, outerRadius: 0.23, height: 0.02); brim.materials = [lacquer]
        let brimNode = SCNNode(geometry: brim); brimNode.position = SCNVector3(0, 0.19, -0.03); brimNode.eulerAngles.x = 0.25
        headSocket.addChildNode(brimNode)
        let crest = SCNTorus(ringRadius: 0.12, pipeRadius: 0.012); crest.materials = [gold]
        let crestNode = SCNNode(geometry: crest)
        crestNode.position = SCNVector3(0, 0.34, 0.12); crestNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        crestNode.scale = SCNVector3(1, 1, 0.6)
        headSocket.addChildNode(crestNode)
        // 大太刀
        blade(length: 1.05, width: 0.05, color: UIColor(red: 0.85, green: 0.88, blue: 0.92, alpha: 1),
              edge: UIColor(red: 1, green: 0.4, blue: 0.15, alpha: 1), guardColor: UIColor(red: 0.8, green: 0.6, blue: 0.2, alpha: 1),
              grip: 0.3, in: rHand, tip: bladeTip, base: bladeBase, curve: 0.018)
        // 背后的旗指物
        let pole = SCNCylinder(radius: 0.012, height: 1.0); pole.materials = [black]
        let poleNode = SCNNode(geometry: pole); poleNode.position = SCNVector3(0, 0.75, -0.16); chest.addChildNode(poleNode)
        let flag = box(0.24, 0.5, 0.01, chamfer: 0, mat(UIColor(red: 0.9, green: 0.85, blue: 0.75, alpha: 1), rough: 0.9),
                       at: SCNVector3(0.12, 1.0, -0.16), into: chest)
        _ = flag
        _ = box(0.1, 0.1, 0.012, chamfer: 0.05, lacquer, at: SCNVector3(0.12, 1.05, -0.152), into: chest)
    }

    private func buildLiu() {
        let skin = mat(UIColor(red: 0.72, green: 0.5, blue: 0.36, alpha: 1), rough: 0.5)
        let fur = mat(UIColor(red: 0.36, green: 0.24, blue: 0.14, alpha: 1), rough: 1)
        let bark = mat(UIColor(red: 0.25, green: 0.18, blue: 0.1, alpha: 1), rough: 0.9)
        let bronze = mat(UIColor(red: 0.62, green: 0.42, blue: 0.2, alpha: 1), metal: 1, rough: 0.35,
                         emission: UIColor(red: 1, green: 0.7, blue: 0.2, alpha: 1).withAlphaComponent(0))
        let stone = mat(UIColor(red: 0.3, green: 0.3, blue: 0.32, alpha: 1), rough: 0.95)
        torso(skin, width: 0.46, depth: 0.28, waist: bark)
        limbs(skin: skin, sleeve: skin, pants: bark, boots: fur, armR: 0.075, legR: 0.095)
        // 肌肉轮廓
        for x in [Float(-0.09), 0.09] {
            let pec = SCNSphere(radius: 0.1); pec.materials = [skin]
            let n = SCNNode(geometry: pec); n.scale = SCNVector3(1, 0.7, 0.55); n.position = SCNVector3(x, 0.32, 0.08); chest.addChildNode(n)
        }
        // 毛皮披肩
        let mantle = SCNTorus(ringRadius: 0.2, pipeRadius: 0.09); mantle.materials = [fur]
        let mantleNode = SCNNode(geometry: mantle); mantleNode.position = SCNVector3(0, 0.46, -0.02); mantleNode.scale = SCNVector3(1.1, 0.8, 0.9)
        chest.addChildNode(mantleNode)
        // 石质护肩与兽骨项链
        for (s, side) in [(rShoulder, Float(-1)), (lShoulder, Float(1))] {
            let pad = SCNSphere(radius: 0.12); pad.materials = [stone]
            let n = SCNNode(geometry: pad); n.scale = SCNVector3(1, 0.6, 1); n.position = SCNVector3(side * 0.03, 0.04, 0); s.addChildNode(n)
        }
        for i in 0..<7 {
            let a = Float(i - 3) * 0.32
            let tooth = SCNCone(topRadius: 0, bottomRadius: 0.018, height: 0.07); tooth.materials = [mat(UIColor(white: 0.92, alpha: 1), rough: 0.5)]
            let n = SCNNode(geometry: tooth); n.position = SCNVector3(sin(a) * 0.15, 0.36 - abs(a) * 0.04, 0.12 + cos(a) * 0.02)
            n.eulerAngles.x = .pi
            chest.addChildNode(n)
        }
        // 腰间兽皮
        let kilt = SCNCone(topRadius: 0.2, bottomRadius: 0.27, height: 0.32); kilt.materials = [fur]
        let kiltNode = SCNNode(geometry: kilt); kiltNode.position = SCNVector3(0, -0.14, 0); hips.addChildNode(kiltNode)
        // 开天巨斧：长柄 + 新月斧刃
        let holder = SCNNode(); rHand.addChildNode(holder)
        let shaft = SCNCylinder(radius: 0.03, height: 1.45); shaft.materials = [bark]
        let shaftNode = SCNNode(geometry: shaft); shaftNode.position = SCNVector3(0, -0.45, 0); holder.addChildNode(shaftNode)
        let head = SCNNode(); head.position = SCNVector3(0, -1.08, 0); holder.addChildNode(head)
        let bladeShape = UIBezierPath()
        bladeShape.move(to: CGPoint(x: 0, y: 0.12))
        bladeShape.addQuadCurve(to: CGPoint(x: 0.42, y: 0.32), controlPoint: CGPoint(x: 0.25, y: 0.1))
        bladeShape.addQuadCurve(to: CGPoint(x: 0.42, y: -0.32), controlPoint: CGPoint(x: 0.6, y: 0))
        bladeShape.addQuadCurve(to: CGPoint(x: 0, y: -0.12), controlPoint: CGPoint(x: 0.25, y: -0.1))
        bladeShape.close()
        bladeShape.flatness = 0.01
        let axe = SCNShape(path: bladeShape, extrusionDepth: 0.04); axe.chamferRadius = 0.01; axe.materials = [bronze]
        let axeNode = SCNNode(geometry: axe); axeNode.eulerAngles = SCNVector3(0, -Float.pi / 2, Float.pi / 2)
        head.addChildNode(axeNode)
        let collar = SCNCylinder(radius: 0.06, height: 0.24); collar.materials = [bronze]
        head.addChildNode(SCNNode(geometry: collar))
        holder.addChildNode(bladeBase); bladeBase.position = SCNVector3(0, -0.85, 0.2)
        holder.addChildNode(bladeTip); bladeTip.position = SCNVector3(0, -1.2, 0.5)
        holder.eulerAngles.x = 0
    }

    private func buildXu() {
        let robe = mat(UIColor(red: 0.06, green: 0.05, blue: 0.06, alpha: 1), rough: 0.55)
        let red = mat(UIColor(red: 0.55, green: 0.08, blue: 0.06, alpha: 1), rough: 0.6)
        let gold = mat(UIColor(red: 0.92, green: 0.72, blue: 0.3, alpha: 1), metal: 1, rough: 0.25,
                       emission: UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1).withAlphaComponent(0))
        let jade = mat(UIColor(red: 0.3, green: 0.7, blue: 0.5, alpha: 1), metal: 0.1, rough: 0.2)
        torso(robe, width: 0.38, depth: 0.23, waist: red)
        limbs(skin: skinMaterial, sleeve: robe, pants: robe, boots: robe, armR: 0.065, legR: 0.08)
        // 金边交领
        _ = box(0.05, 0.4, 0.02, chamfer: 0.01, gold, at: SCNVector3(0.05, 0.28, 0.115), into: chest, euler: SCNVector3(0, 0, 0.45))
        _ = box(0.05, 0.4, 0.02, chamfer: 0.01, gold, at: SCNVector3(-0.05, 0.28, 0.115), into: chest, euler: SCNVector3(0, 0, -0.45))
        // 玄色长袍下摆
        let skirt = SCNCone(topRadius: 0.2, bottomRadius: 0.34, height: 0.72); skirt.radialSegmentCount = 20; skirt.materials = [robe]
        let skirtNode = SCNNode(geometry: skirt); skirtNode.position = SCNVector3(0, -0.36, 0); hips.addChildNode(skirtNode)
        let hem = SCNTube(innerRadius: 0.33, outerRadius: 0.35, height: 0.05); hem.materials = [gold]
        let hemNode = SCNNode(geometry: hem); hemNode.position = SCNVector3(0, -0.7, 0); hips.addChildNode(hemNode)
        // 宽袖
        for e in [rElbow, lElbow] {
            let sleeve = SCNCone(topRadius: 0.07, bottomRadius: 0.13, height: 0.24); sleeve.materials = [robe]
            let n = SCNNode(geometry: sleeve); n.position = SCNVector3(0, -0.16, 0); e.addChildNode(n)
            let cuff = SCNTube(innerRadius: 0.12, outerRadius: 0.135, height: 0.03); cuff.materials = [gold]
            let c = SCNNode(geometry: cuff); c.position = SCNVector3(0, -0.28, 0); e.addChildNode(c)
        }
        // 金腰带 + 玉佩
        _ = box(0.4, 0.07, 0.26, chamfer: 0.02, gold, at: SCNVector3(0, -0.0, 0), into: chest)
        let pendant = SCNCylinder(radius: 0.04, height: 0.012); pendant.materials = [jade]
        let pn = SCNNode(geometry: pendant); pn.eulerAngles.x = .pi / 2; pn.position = SCNVector3(0.1, -0.12, 0.14); hips.addChildNode(pn)
        // 冕冠：冕板 + 前后旒珠（适配真人头模高度）
        let board = SCNBox(width: 0.2, height: 0.015, length: 0.34, chamferRadius: 0.005); board.materials = [robe]
        let boardNode = SCNNode(geometry: board); boardNode.position = SCNVector3(0, 0.33, 0.0); headSocket.addChildNode(boardNode)
        let cap = SCNCylinder(radius: 0.085, height: 0.1); cap.materials = [robe]
        let capNode = SCNNode(geometry: cap); capNode.position = SCNVector3(0, 0.28, -0.01); headSocket.addChildNode(capNode)
        for z in [Float(0.17), -0.17] {
            for i in 0..<6 {
                let bead = SCNCylinder(radius: 0.004, height: 0.11); bead.materials = [i % 2 == 0 ? gold : jade]
                let b = SCNNode(geometry: bead); b.position = SCNVector3(-0.08 + Float(i) * 0.032, 0.27, z); headSocket.addChildNode(b)
            }
        }
        // 黑色披风
        let cape = box(0.42, 0.9, 0.015, chamfer: 0.005, red, at: SCNVector3(0, 0.0, -0.15), into: chest, euler: SCNVector3(0.1, 0, 0))
        cape.pivot = SCNMatrix4MakeTranslation(0, -0.4, 0)
        cape.position = SCNVector3(0, 0.45, -0.15)
        scarf.append(cape)
        // 秦王剑：青铜金纹，玉首
        blade(length: 0.82, width: 0.05, color: UIColor(red: 0.78, green: 0.68, blue: 0.45, alpha: 1),
              edge: UIColor(red: 1, green: 0.85, blue: 0.35, alpha: 1), guardColor: UIColor(red: 0.3, green: 0.7, blue: 0.5, alpha: 1),
              grip: 0.2, in: rHand, tip: bladeTip, base: bladeBase)
        _ = gold
    }

    // MARK: - 头部

    private var placeholderHead: SCNNode?

    private func buildPlaceholderHead() {
        let headNode = SCNNode()
        headNode.name = "rift.head.placeholder"
        let skull = SCNSphere(radius: 0.115); skull.segmentCount = 20; skull.materials = [skinMaterial]
        let s = SCNNode(geometry: skull); s.scale = SCNVector3(0.9, 1.08, 0.98); s.position = SCNVector3(0, 0.12, 0)
        headNode.addChildNode(s)
        let hairColor = UIColor(red: 0.07, green: 0.06, blue: 0.06, alpha: 1)
        let hair = SCNSphere(radius: 0.12); hair.segmentCount = 16; hair.materials = [mat(hairColor, rough: 0.9)]
        let h = SCNNode(geometry: hair); h.scale = SCNVector3(0.94, 0.75, 1.0); h.position = SCNVector3(0, 0.17, -0.012)
        headNode.addChildNode(h)
        let eyeMat = mat(UIColor(white: 0.08, alpha: 1), rough: 0.3, flash: false)
        for x in [Float(-0.04), 0.04] {
            let e = SCNSphere(radius: 0.012); e.materials = [eyeMat]
            let n = SCNNode(geometry: e); n.position = SCNVector3(x, 0.13, 0.1); headNode.addChildNode(n)
        }
        headSocket.addChildNode(headNode)
        placeholderHead = headNode
    }

    private static var cachedHeadModels: [RiftHeroID: GLTFModel] = [:]

    /// 换上真人头模（App 包里的 RiftHead_<英雄>.glb）。成功返回 true。
    @discardableResult
    func installPersonalHead() -> Bool {
        let model: GLTFModel
        if let cached = Self.cachedHeadModels[hero] {
            model = cached
        } else {
            let name = "RiftHead_\(hero.rawValue)"
            let url = Bundle.main.url(forResource: name, withExtension: "glb")
                ?? Bundle.main.url(forResource: name, withExtension: "glb", subdirectory: "RiftHeads")
            guard let url,
                  let loaded = try? GLTFModel(url: url, maxTexture: 1024, smoothNormals: false, physicallyBased: true) else { return false }
            Self.cachedHeadModels[hero] = loaded
            model = loaded
        }
        let instance = model.instantiate()
        let node = instance.root
        let (minV, maxV) = node.boundingBox
        let height = maxV.y - minV.y
        guard height > 0.0001 else { return false }
        // 头顶到下巴约 0.25 米；下巴落在脖子顶端
        let scale = 0.27 / height
        node.scale = SCNVector3(scale, scale, scale)
        node.position = SCNVector3(-(minV.x + maxV.x) / 2 * scale, -minV.y * scale - 0.01, -(minV.z + maxV.z) / 2 * scale)
        node.name = "rift.head.personal"
        headSocket.addChildNode(node)
        flashMaterials.append(contentsOf: instance.materials)
        placeholderHead?.removeFromParentNode()
        return true
    }

    private static func makeShadowBlob() -> SCNNode {
        let plane = SCNPlane(width: 1.1, height: 0.7)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = RiftTextures.radial(inner: UIColor(white: 0, alpha: 0.55), outer: UIColor(white: 0, alpha: 0))
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -.pi / 2
        n.position = SCNVector3(0, 0.01, 0)
        n.renderingOrder = -1
        return n
    }

    // MARK: - 姿势

    func apply(_ p: RiftPose) {
        body.eulerAngles = SCNVector3(p.rootPitch, p.rootYaw, p.rootRoll)
        hips.position = SCNVector3(0, 0.98 + p.hipsY, p.hipsForward)
        hips.eulerAngles = SCNVector3(p.lean * 0.3, 0, 0)
        chest.eulerAngles = SCNVector3(p.lean * 0.7, p.twist, 0)
        neck.eulerAngles = SCNVector3(p.head - p.lean * 0.5, -p.twist * 0.5, 0)
        rShoulder.eulerAngles = SCNVector3(-p.rShoulder, 0, -p.rRaise)
        lShoulder.eulerAngles = SCNVector3(-p.lShoulder, 0, p.lRaise)
        rElbow.eulerAngles = SCNVector3(-p.rElbow, 0, 0)
        lElbow.eulerAngles = SCNVector3(-p.lElbow, 0, 0)
        rHand.eulerAngles = SCNVector3(-p.rWrist, 0, 0)
        lHand.eulerAngles = SCNVector3(-p.lWrist, 0, 0)
        rHip.eulerAngles = SCNVector3(-p.rThigh, 0, 0)
        lHip.eulerAngles = SCNVector3(-p.lThigh, 0, 0)
        rKnee.eulerAngles = SCNVector3(p.rKnee, 0, 0)
        lKnee.eulerAngles = SCNVector3(p.lKnee, 0, 0)
    }

    private var lastFlashAmount: Float = -1

    func setFlash(_ amount: Float, color: UIColor = .white) {
        guard abs(amount - lastFlashAmount) > 0.005 else { return }
        lastFlashAmount = amount
        let c = amount > 0 ? color.withAlphaComponent(CGFloat(amount)) : UIColor.black
        for m in flashMaterials where !glowMaterials.contains(m) { m.emission.contents = c }
    }

    func setGlow(_ amount: Float, color: UIColor) {
        for m in glowMaterials { m.emission.contents = color.withAlphaComponent(CGFloat(amount)) }
    }
}

extension SCNVector3 {
    static func * (v: SCNVector3, s: Float) -> SCNVector3 { SCNVector3(v.x * s, v.y * s, v.z * s) }
}
