import SceneKit
import SwiftUI
import UIKit

/// 对战 3D 画面：擂台、两名角色、镜头（跟随 + 震屏）、特效与音效分发。
struct RiftArenaView: UIViewRepresentable {
    let session: RiftSession

    func makeCoordinator() -> RiftArenaController { RiftArenaController(session: session) }

    func makeUIView(context: Context) -> SCNView {
        context.coordinator.makeView()
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    static func dismantleUIView(_ view: SCNView, coordinator: RiftArenaController) {
        coordinator.shutdown()
    }
}

@MainActor
final class RiftArenaController: NSObject {
    let session: RiftSession
    private let scene = SCNScene()
    private var view: SCNView?
    private var rigs: [RiftRig] = []
    private var effects: RiftEffects?
    private let cameraNode = SCNNode()
    private var link: CADisplayLink?
    private var shake: Float = 0
    private var shakeSeed: Float = 0
    private var camX: Float = 0
    private var camDist: Float = 6
    private let audio = RiftAudio()
    private var start = CACurrentMediaTime()
    private var flashLevel: [Float] = [0, 0]
    private var lastPoses: [RiftPose] = [RiftPose(), RiftPose()]
    private var slowMo = 0

    init(session: RiftSession) {
        self.session = session
        super.init()
    }

    func makeView() -> SCNView {
        let v = SCNView(frame: .zero)
        v.scene = scene
        v.backgroundColor = .black
        v.antialiasingMode = .multisampling2X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        v.isPlaying = true
        v.isJitteringEnabled = false
        v.accessibilityIdentifier = "rift.arena"
        view = v
        buildStage()
        buildFighters()
        buildCamera()
        effects = RiftEffects(scene: scene, rigs: rigs)
        session.eventSink = { [weak self] events, fight in self?.handle(events, fight: fight) }
        session.projector = { [weak self] world in
            guard let view = self?.view else { return nil }
            let p = view.projectPoint(SCNVector3(world.x, world.y, world.z))
            return p.z < 1 ? CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)) : nil
        }
        // 预编译着色器，避免第一刀卡顿
        v.prepare([scene], completionHandler: nil)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
        Task { await audio.prepare(); audio.play(.fight, volume: 0.6) }
        return v
    }

    func shutdown() {
        link?.invalidate()
        link = nil
        audio.stop()
        view?.isPlaying = false
        session.eventSink = nil
        session.projector = nil
    }

    // MARK: 场景

    private func buildStage() {
        scene.background.contents = RiftTextures.sky
        scene.lightingEnvironment.contents = RiftTextures.sky
        scene.lightingEnvironment.intensity = 1.2
        scene.fogStartDistance = 14
        scene.fogEndDistance = 40
        scene.fogColor = UIColor(red: 0.25, green: 0.14, blue: 0.3, alpha: 1)

        // 擂台地面
        let floor = SCNPlane(width: 40, height: 14)
        let fm = SCNMaterial()
        fm.lightingModel = .physicallyBased
        fm.diffuse.contents = RiftTextures.stoneFloor
        fm.diffuse.contentsTransform = SCNMatrix4MakeScale(4, 1.4, 1)
        fm.diffuse.wrapS = .repeat; fm.diffuse.wrapT = .repeat
        fm.roughness.contents = 0.8
        floor.materials = [fm]
        let floorNode = SCNNode(geometry: floor)
        floorNode.eulerAngles.x = -.pi / 2
        floorNode.position = SCNVector3(0, 0, -2)
        scene.rootNode.addChildNode(floorNode)

        // 擂台边缘的石阶与立柱灯笼
        let stoneMat = SCNMaterial()
        stoneMat.lightingModel = .physicallyBased
        stoneMat.diffuse.contents = UIColor(red: 0.3, green: 0.28, blue: 0.32, alpha: 1)
        stoneMat.roughness.contents = 0.9
        let lanternMat = SCNMaterial()
        lanternMat.lightingModel = .constant
        lanternMat.diffuse.contents = UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1)
        for x in stride(from: -9.0, through: 9.0, by: 4.5) {
            let pillar = SCNBox(width: 0.5, height: 3.2, length: 0.5, chamferRadius: 0.05)
            pillar.materials = [stoneMat]
            let n = SCNNode(geometry: pillar)
            n.position = SCNVector3(Float(x), 1.6, -4.5)
            scene.rootNode.addChildNode(n)
            let lantern = SCNSphere(radius: 0.22); lantern.materials = [lanternMat]
            let ln = SCNNode(geometry: lantern); ln.scale = SCNVector3(1, 1.3, 1)
            ln.position = SCNVector3(Float(x), 3.4, -4.5)
            scene.rootNode.addChildNode(ln)
            let roof = SCNPyramid(width: 0.8, height: 0.35, length: 0.8); roof.materials = [stoneMat]
            let rn = SCNNode(geometry: roof); rn.position = SCNVector3(Float(x), 3.62, -4.5)
            scene.rootNode.addChildNode(rn)
        }
        let step = SCNBox(width: 40, height: 0.3, length: 1.2, chamferRadius: 0.02); step.materials = [stoneMat]
        let stepNode = SCNNode(geometry: step); stepNode.position = SCNVector3(0, 0.15, -3.6)
        scene.rootNode.addChildNode(stepNode)

        // 远山剪影（三层，越远越淡）
        for layer in 0..<3 {
            let path = UIBezierPath()
            var rng = RiftRandom(seed: UInt64(layer + 3))
            path.move(to: CGPoint(x: -40, y: 0))
            var x: CGFloat = -40
            while x < 40 {
                x += CGFloat(3 + Int(rng.next() % 5))
                let h = CGFloat(2 + Int(rng.next() % 6)) + CGFloat(layer) * 1.5
                path.addLine(to: CGPoint(x: x, y: h))
            }
            path.addLine(to: CGPoint(x: 40, y: 0))
            path.close()
            let shape = SCNShape(path: path, extrusionDepth: 0.1)
            let m = SCNMaterial()
            m.lightingModel = .constant
            let shade = 0.08 + CGFloat(2 - layer) * 0.06
            m.diffuse.contents = UIColor(red: shade, green: shade * 0.7, blue: shade * 1.4, alpha: 1)
            shape.materials = [m]
            let n = SCNNode(geometry: shape)
            n.position = SCNVector3(0, -0.5, -14 - Float(layer) * 8)
            scene.rootNode.addChildNode(n)
        }

        // 灯光：主光 + 冷色轮廓光 + 环境光
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1300
        sun.color = UIColor(red: 1, green: 0.88, blue: 0.75, alpha: 1)
        let sunNode = SCNNode(); sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.9, 0.5, 0)
        scene.rootNode.addChildNode(sunNode)
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 800
        rim.color = UIColor(red: 0.55, green: 0.5, blue: 1, alpha: 1)
        let rimNode = SCNNode(); rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.3, .pi - 0.4, 0)
        scene.rootNode.addChildNode(rimNode)
        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 250
        amb.color = UIColor(red: 0.5, green: 0.42, blue: 0.6, alpha: 1)
        let ambNode = SCNNode(); ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // 漂浮的余烬
        let embers = SCNParticleSystem()
        embers.particleImage = RiftTextures.softDot
        embers.birthRate = 18
        embers.particleLifeSpan = 6
        embers.particleVelocity = 0.4
        embers.emittingDirection = SCNVector3(0.2, 1, 0)
        embers.spreadingAngle = 30
        embers.particleSize = 0.04
        embers.particleColor = UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1)
        embers.blendMode = .additive
        embers.emitterShape = SCNBox(width: 24, height: 0.1, length: 6, chamferRadius: 0)
        embers.loops = true
        let emberNode = SCNNode(); emberNode.position = SCNVector3(0, 0, -2)
        emberNode.addParticleSystem(embers)
        scene.rootNode.addChildNode(emberNode)
    }

    private func buildFighters() {
        rigs = [RiftRig(hero: session.config.player), RiftRig(hero: session.config.opponent)]
        for rig in rigs {
            rig.installPersonalHead()
            scene.rootNode.addChildNode(rig.root)
        }
        // 镜像对战时区分两边：对手衣甲稍暗
        if session.config.player == session.config.opponent {
            for m in rigs[1].flashMaterials { m.multiply.contents = UIColor(white: 0.7, alpha: 1) }
        }
        place()
    }

    private func buildCamera() {
        let cam = SCNCamera()
        cam.fieldOfView = 38
        cam.zNear = 0.1
        cam.zFar = 120
        cam.wantsHDR = false
        cam.bloomIntensity = 0
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        updateCamera(dt: 1)
    }

    // MARK: 每帧

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if slowMo > 0 {
            // 终结一击：短暂慢动作（每两帧推进一次）
            slowMo -= 1
            if slowMo % 2 == 0 { session.advance(now: now) } else { session.resetClock(); session.advance(now: now) }
        } else {
            session.advance(now: now)
        }
        place()
        effects?.update(fight: session.fight, rigs: rigs, poses: lastPoses, now: now)
        updateCamera(dt: Float(link.targetTimestamp - link.timestamp))
        session.prunePopups(now: Date())
    }

    private func place() {
        let fight = session.fight
        let t = CACurrentMediaTime() - start
        for i in 0..<min(2, rigs.count) {
            let f = fight.fighters[i]
            let rig = rigs[i]
            rig.root.position = SCNVector3(Float(f.x), Float(f.y), 0)
            rig.root.eulerAngles.y = f.facing > 0 ? .pi / 2 : -.pi / 2
            // 影子留在地面
            rig.shadowBlob.position = SCNVector3(0, 0.01 - Float(f.y), 0)
            rig.shadowBlob.opacity = CGFloat(max(0.2, 1 - f.y * 0.4))
            let pose = RiftAnimator.pose(for: f, time: t + Double(i) * 0.7, frame: fight.frame)
            lastPoses[i] = pose
            rig.apply(pose)
            // 飘带摆动
            for (k, seg) in rig.scarf.enumerated() {
                let sway = Float(sin(t * 6 + Double(k) * 0.8)) * 0.15 + Float(min(0.6, abs(f.vx) * 8))
                seg.eulerAngles.x = (rig.hero == .xuXiao ? 0.1 : -0.9) - sway
            }
            // 受击闪白
            if f.hitFlash > 0 { flashLevel[i] = 0.9 }
            flashLevel[i] = max(0, flashLevel[i] - 0.12)
            rig.setFlash(flashLevel[i])
        }
    }

    private func updateCamera(dt: Float) {
        let fight = session.fight
        let a = fight.fighters[0], b = fight.fighters[1]
        let mid = Float(a.x + b.x) / 2
        let sep = Float(abs(a.x - b.x))
        let targetDist = min(9.5, max(5.2, 3.6 + sep * 0.75))
        camX += (mid - camX) * 0.12
        camDist += (targetDist - camDist) * 0.08
        shake *= 0.86
        shakeSeed += 1.7
        let sx = sin(shakeSeed * 2.3) * shake, sy = cos(shakeSeed * 3.1) * shake
        let height: Float = 1.55 + max(0, Float(max(a.y, b.y)) * 0.4)
        cameraNode.position = SCNVector3(camX + sx, height + sy, camDist)
        cameraNode.look(at: SCNVector3(camX, 1.05 + max(0, Float(max(a.y, b.y))) * 0.3, 0))
    }

    // MARK: 事件 → 特效 / 音效 / 震动

    private func handle(_ events: [RiftEvent], fight: RiftFight) {
        let now = CACurrentMediaTime()
        if fight.lastShake > 0 { shake = max(shake, Float(fight.lastShake)) }
        for e in events {
            switch e {
            case .hit(let h):
                effects?.hit(h, now: now)
                switch h.kind {
                case .block: audio.play(.block, volume: 0.7)
                case .parry: audio.play(.parry); haptic(.rigid)
                case .guardBreak: audio.play(.guardBreak); haptic(.heavy)
                case .echo: audio.play(.hitLight, volume: 0.35)
                default:
                    switch h.tier {
                    case .light: audio.play(.hitLight, volume: 0.8)
                    case .medium: audio.play(.hitLight); audio.play(.hitHeavy, volume: 0.4)
                    case .heavy: audio.play(.hitHeavy); haptic(.medium)
                    case .ultimate: audio.play(.hitUltimate); haptic(.heavy)
                    }
                }
            case .swing(let side, let slot, let style):
                if slot == .transform { audio.play(.transform); effects?.swing(side: side, style: style, rig: rigs[side], now: now) }
                else if slot == .heavy || slot == .skill1 || slot == .skill2 || slot == .ultimate || slot == .light3 {
                    audio.play(.swingHeavy, volume: 0.8)
                } else {
                    audio.play(.swingLight, volume: 0.7)
                }
            case .ultimate:
                audio.play(.ultimate)
                haptic(.heavy)
            case .projectileSpawned:
                audio.play(.projectile, volume: 0.8)
            case .projectileClash:
                audio.play(.block)
            case .land(let side, let heavy):
                if heavy { audio.play(.land); effects?.land(side: side, at: Float(fight.fighters[side].x), heavy: true, now: now) }
            case .ko:
                audio.play(.ko)
                slowMo = 50
                shake = 0.3
            case .fight:
                audio.play(.fight, volume: 0.8)
            default:
                break
            }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard session.config.mode != .demo else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    func setPaused(_ paused: Bool) {
        audio.setPaused(paused)
        if !paused { session.resetClock() }
    }
}
