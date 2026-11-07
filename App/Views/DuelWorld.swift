import SwiftUI
import SceneKit
import UIKit
import Darwin

struct DuelWorld: UIViewRepresentable {
    let session: DuelSession
    func makeUIView(context: Context) -> DuelWorldView { DuelWorldView(session: session) }
    func updateUIView(_ view: DuelWorldView, context: Context) {}
    static func dismantleUIView(_ view: DuelWorldView, coordinator: ()) { view.shutdown() }
}

/// Original procedural greybox. Two articulated silhouettes share no arena assets.
/// One main-thread clock owns simulation; SceneKit only renders the resulting pose.
@MainActor
final class DuelWorldView: SCNView {
    private(set) static var activeClocks = 0
    private let session: DuelSession
    private var clock = DuelClock()
    private var link: CADisplayLink?
    private var lastTime: Double?
    private var lastReport = 0.0
    private var intervals: [Double] = []
    private var intervalCursor = 0
    private var slowCallbacks = 0
    private var sampleCount = 0
    private var actors: [DuelActor] = []
    private var bolts: [Int: SCNNode] = [:]
    private var hurtNodes: [SCNNode] = []
    private var attackNodes: [SCNNode] = []
    private var ended = false

    init(session: DuelSession) {
        self.session = session
        super.init(frame: .zero, options: nil)
        backgroundColor = UIColor(red: 0.045, green: 0.055, blue: 0.13, alpha: 1)
        antialiasingMode = .multisampling2X; preferredFramesPerSecond = 60
        isUserInteractionEnabled = false; isAccessibilityElement = false; accessibilityElementsHidden = true
        let world = SCNScene(); scene = world
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 3.6; camera.camera?.zNear = 0.1; camera.camera?.zFar = 80
        camera.position = SCNVector3(5, 3.6, 14); camera.look(at: SCNVector3(5, 1.0, 0))
        world.rootNode.addChildNode(camera); pointOfView = camera
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.color = UIColor(red: 0.42, green: 0.45, blue: 0.65, alpha: 1); ambient.light?.intensity = 520
        world.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional
        key.light?.intensity = 1250; key.light?.castsShadow = true
        key.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.light?.shadowColor = UIColor.black.withAlphaComponent(0.32)
        key.eulerAngles = SCNVector3(-0.8, -0.5, 0); world.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .omni
        fill.light?.color = UIColor.cyan; fill.light?.intensity = 320; fill.position = SCNVector3(8, 4, -2)
        world.rootNode.addChildNode(fill)
        buildStage(world.rootNode)
        for fighter in session.game.fighters {
            let actor = DuelActor(hero: fighter.hero); actors.append(actor); world.rootNode.addChildNode(actor.root)
            let hurt = debugBox(.green), attack = debugBox(.orange)
            hurtNodes.append(hurt); attackNodes.append(attack); world.rootNode.addChildNode(hurt); world.rootNode.addChildNode(attack)
        }
        session.renderPause = { [weak self] paused in
            if paused { self?.stopClock() } else { self?.startClock() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        drawState()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopClock(); session.clearInput() } else if !session.paused { startClock() }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep all ten world units visible even during the rotation transition.
        guard bounds.width > 0, bounds.height > 0 else { return }
        let aspect = Double(bounds.width / bounds.height)
        pointOfView?.camera?.orthographicScale = max(3.2, 5.8 / max(0.1, aspect))
    }
    @objc private func interrupted() { session.pause() }
    @objc private func becameActive() {
        // A new view may be attached during the first foreground transition.
        // Start its clock when UIKit is active; an interrupted fight stays
        // paused until the player explicitly chooses Resume.
        if !session.paused { startClock() }
    }
    private func startClock() {
        guard !ended, window != nil, !session.paused, UIApplication.shared.applicationState == .active, link == nil else { return }
        lastTime = nil; clock.reset(); rendersContinuously = true; isPlaying = true
        let target = DuelDisplayTarget(self)
        let driver = CADisplayLink(target: target, selector: #selector(DuelDisplayTarget.tick(_:)))
        driver.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        driver.add(to: .main, forMode: .common); link = driver; Self.activeClocks += 1
    }
    private func stopClock() {
        if link != nil { Self.activeClocks -= 1 }
        link?.invalidate(); link = nil; lastTime = nil; clock.reset()
        rendersContinuously = false; isPlaying = false
    }
    func shutdown() {
        guard !ended else { return }
        ended = true; stopClock(); session.clearInput(); session.renderPause = nil
        NotificationCenter.default.removeObserver(self)
        scene = nil; pointOfView = nil; actors.removeAll(); bolts.removeAll(); hurtNodes.removeAll(); attackNodes.removeAll()
    }
    fileprivate func tick(_ timestamp: Double) {
        guard !ended, !session.paused else { return }
        guard let previous = lastTime else { lastTime = timestamp; return }
        lastTime = timestamp
        let elapsed = timestamp - previous
        let steps = clock.consume(seconds: elapsed)
        for _ in 0..<steps { session.advance() }
        drawState()
        if case .matchOver = session.game.phase { stopClock() }
        sampleCount += 1
        if elapsed > 0.025 { slowCallbacks += 1 }
        if intervals.count < 1200 { intervals.append(elapsed) }
        else { intervals[intervalCursor] = elapsed; intervalCursor = (intervalCursor + 1) % 1200 }
        if timestamp - lastReport >= 1 {
            lastReport = timestamp
            let sorted = intervals.sorted(), p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))] * 1000
            session.metrics(String(format: "刷新回调 p95 %.1f ms · 慢回调 %d/%d\n内存 %.0f MB · 热状态 %d · 丢弃补步 %.2f s",
                p95, slowCallbacks, sampleCount, Self.memoryMB(), ProcessInfo.processInfo.thermalState.rawValue, clock.droppedSeconds))
        }
    }
    private func drawState() {
        guard scene != nil else { return }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        for i in 0..<actors.count {
            actors[i].pose(session.game.fighters[i], frame: session.game.frame)
            place(hurtNodes[i], box: session.game.hurtBox(i), visible: session.showBoxes && session.game.fighters[i].knockdown == 0)
            if let box = session.game.attackBox(i) { place(attackNodes[i], box: box, visible: session.showBoxes) }
            else { attackNodes[i].isHidden = true }
        }
        let alive = Set(session.game.projectiles.map(\.id))
        for id in Array(bolts.keys) where !alive.contains(id) { bolts.removeValue(forKey: id)?.removeFromParentNode() }
        for projectile in session.game.projectiles {
            let node: SCNNode
            if let existing = bolts[projectile.id] { node = existing }
            else {
                node = DuelActor.shape(SCNSphere(radius: 0.16), .cyan)
                node.geometry?.firstMaterial?.emission.contents = UIColor.cyan.withAlphaComponent(0.4)
                node.scale = SCNVector3(1.8, 0.5, 0.7); bolts[projectile.id] = node; scene?.rootNode.addChildNode(node)
            }
            node.position = SCNVector3(Float(projectile.x) / 1000, 0.9, 0.15)
        }
        SCNTransaction.commit()
    }
    private func debugBox(_ color: UIColor) -> SCNNode {
        let node = DuelActor.shape(SCNBox(width: 1, height: 1, length: 0.02, chamferRadius: 0), color)
        node.geometry?.firstMaterial?.fillMode = .lines; node.geometry?.firstMaterial?.lightingModel = .constant
        node.geometry?.firstMaterial?.readsFromDepthBuffer = false; node.renderingOrder = 20
        node.isHidden = true; return node
    }
    private func place(_ node: SCNNode, box: DuelGame.Box, visible: Bool) {
        node.isHidden = !visible
        node.position = SCNVector3(Float(box.minX + box.maxX) / 2000, Float(box.minY + box.maxY) / 2000, 0.65)
        node.scale = SCNVector3(Float(box.maxX - box.minX) / 1000, Float(box.maxY - box.minY) / 1000, 1)
    }
    private func buildStage(_ root: SCNNode) {
        let floor = DuelActor.shape(SCNBox(width: 11.5, height: 0.3, length: 3.2, chamferRadius: 0.12),
                                    UIColor(red: 0.14, green: 0.16, blue: 0.28, alpha: 1))
        floor.position = SCNVector3(5, -0.2, 0); root.addChildNode(floor)
        for x in [0.35, 9.65] {
            let marker = DuelActor.shape(SCNBox(width: 0.10, height: 0.025, length: 2.8, chamferRadius: 0.01), .cyan)
            marker.position = SCNVector3(Float(x), -0.035, 0); root.addChildNode(marker)
        }
        for index in 0..<9 {
            let height = 1.0 + Double((index * 7) % 5) * 0.55
            let pillar = DuelActor.shape(SCNBox(width: 0.9, height: height, length: 0.7, chamferRadius: 0.08),
                                         UIColor(red: 0.10, green: 0.12, blue: 0.23, alpha: 1))
            pillar.position = SCNVector3(Float(index) * 1.6 - 1.4, Float(height) / 2 - 0.7, -3.5)
            pillar.eulerAngles.z = Float(index % 2 == 0 ? 0.10 : -0.12); root.addChildNode(pillar)
        }
        let rim = DuelActor.shape(SCNBox(width: 11, height: 0.035, length: 0.035, chamferRadius: 0.01), .systemPurple)
        rim.position = SCNVector3(5, 0, -1.4); rim.geometry?.firstMaterial?.emission.contents = UIColor.systemPurple
        root.addChildNode(rim)
    }
    private static func memoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: capacity) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }
}

@MainActor
private final class DuelDisplayTarget: NSObject {
    weak var view: DuelWorldView?
    init(_ view: DuelWorldView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) { view?.tick(link.timestamp) }
}

@MainActor
private final class DuelActor {
    let root = SCNNode()
    let leftArm = SCNNode(), rightArm = SCNNode(), leftLeg = SCNNode(), rightLeg = SCNNode()
    let shield: SCNNode
    private let body: SCNNode
    init(hero: DuelGame.Hero) {
        let color = hero == .ember ? UIColor.systemOrange : UIColor.systemTeal
        let dark = UIColor(red: 0.10, green: 0.13, blue: 0.22, alpha: 1)
        body = Self.shape(SCNCapsule(capRadius: hero == .ember ? 0.31 : 0.25, height: 0.72), color)
        body.position.y = 1.08; root.addChildNode(body)
        let head = Self.shape(SCNSphere(radius: 0.23), UIColor(red: 0.78, green: 0.82, blue: 0.86, alpha: 1))
        head.position.y = 1.67; root.addChildNode(head)
        let visor = Self.shape(SCNBox(width: 0.30, height: 0.09, length: 0.08, chamferRadius: 0.04), dark)
        visor.position = SCNVector3(0, 1.69, 0.20); root.addChildNode(visor)
        let belt = Self.shape(SCNBox(width: 0.53, height: 0.16, length: 0.32, chamferRadius: 0.06), dark)
        belt.position.y = 0.74; root.addChildNode(belt)
        for (joint, x) in [(leftArm, Float(-0.37)), (rightArm, Float(0.37))] {
            joint.position = SCNVector3(x, 1.33, 0); root.addChildNode(joint)
            let arm = Self.shape(SCNCapsule(capRadius: 0.105, height: 0.48), dark); arm.position.y = -0.20; joint.addChildNode(arm)
            let fist = Self.shape(SCNBox(width: hero == .ember ? 0.29 : 0.21, height: 0.27, length: 0.30, chamferRadius: 0.09), color)
            fist.position = SCNVector3(0, -0.48, 0.04); joint.addChildNode(fist)
        }
        for (joint, x) in [(leftLeg, Float(-0.17)), (rightLeg, Float(0.17))] {
            joint.position = SCNVector3(x, 0.72, 0); root.addChildNode(joint)
            let leg = Self.shape(SCNCapsule(capRadius: 0.115, height: 0.64), dark); leg.position.y = -0.28; joint.addChildNode(leg)
            let foot = Self.shape(SCNBox(width: 0.24, height: 0.15, length: 0.40, chamferRadius: 0.05), color)
            foot.position = SCNVector3(0, -0.65, 0.09); joint.addChildNode(foot)
        }
        shield = Self.shape(SCNTorus(ringRadius: 0.54, pipeRadius: 0.025), .cyan)
        shield.position = SCNVector3(0, 1, 0.55); shield.eulerAngles.x = .pi / 2; shield.isHidden = true
        root.addChildNode(shield)
    }
    static func shape(_ geometry: SCNGeometry, _ color: UIColor) -> SCNNode {
        let material = SCNMaterial(); material.diffuse.contents = color; material.roughness.contents = 0.7
        material.metalness.contents = 0.12; material.lightingModel = .physicallyBased
        geometry.materials = [material]; return SCNNode(geometry: geometry)
    }
    func pose(_ fighter: DuelGame.Fighter, frame: Int) {
        root.position = SCNVector3(Float(fighter.x) / 1000, Float(fighter.y) / 1000, 0)
        root.eulerAngles.y = fighter.facing > 0 ? .pi / 2 : -.pi / 2
        root.eulerAngles.z = fighter.knockdown > 0 ? Float(fighter.facing) * -.pi / 2 : 0
        if fighter.knockdown > 0 { root.position.y = 0.25 }
        let swing = fighter.walking ? sin(Float(frame) * 0.24) * 0.5 : 0
        leftLeg.eulerAngles.x = swing; rightLeg.eulerAngles.x = -swing
        leftArm.eulerAngles.x = -0.35 - swing * 0.3; rightArm.eulerAngles.x = -0.35 + swing * 0.3
        if fighter.y > 0 { leftLeg.eulerAngles.x = -0.7; rightLeg.eulerAngles.x = 0.45 }
        shield.isHidden = !fighter.guarding
        if fighter.guarding { leftArm.eulerAngles.x = -1.2; rightArm.eulerAngles.x = -1.4 }
        if let attack = fighter.attack {
            let data = DuelGame.data(attack.move, hero: fighter.hero)
            let recovery = Float(max(0, attack.age - data.startup - data.active)) / Float(data.recovery)
            let pose: Float = attack.age < data.startup ? 0.5 : -1.65 + min(1, recovery) * 1.3
            if attack.move == .cross { leftArm.eulerAngles.x = pose }
            else { rightArm.eulerAngles.x = pose }
            if attack.move == .heavy || attack.move == .skill2 { leftArm.eulerAngles.x = pose }
        }
        body.geometry?.firstMaterial?.emission.contents = fighter.flash > 0 ? UIColor(red: 0.22, green: 0.10, blue: 0.02, alpha: 1) : UIColor.black
    }
}
