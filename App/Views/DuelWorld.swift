import SwiftUI
import SceneKit
import UIKit
import Darwin
import simd

struct DuelWorld: UIViewRepresentable {
    let session: DuelSession
    func makeUIView(context: Context) -> DuelWorldView { DuelWorldView(session: session) }
    func updateUIView(_ view: DuelWorldView, context: Context) {}
    static func dismantleUIView(_ view: DuelWorldView, coordinator: ()) { view.shutdown() }
}

/// Authored personal characters plus procedural fallbacks. Assets live for one fight.
/// One main-thread clock owns simulation; SceneKit only renders the resulting pose.
@MainActor
final class DuelWorldView: SCNView {
    private(set) static var activeClocks = 0
    private let session: DuelSession
    private var clock = DuelClock()
    private var link: CADisplayLink?
    private var lastTime: Double?
    private var clockStartedAt: Double?
    private(set) var clockCallbacks = 0
    private(set) var firstStepDelay: Double?
    private var lastReport = 0.0
    private var intervals: [Double] = []
    private var intervalCursor = 0
    private var slowCallbacks = 0
    private var sampleCount = 0
    private var actors: [DuelActor] = []
    private(set) var characterAsset: DuelCharacterAsset?
    private var characterAssets: [DuelGame.Hero: DuelCharacterAsset] = [:]
    private(set) var originalAssets: [DuelGame.Hero: DuelOriginalRigAsset] = [:]
    private(set) var weaponAssets: [DuelGame.Hero: DuelWeaponCharacterAsset] = [:]
    private(set) var sourceEffects: DuelSourceEffects?
    private(set) var weaponEffects: DuelWeaponEffects?
    private(set) var stageAsset: DuelStageAsset?
    private var cameraBasePosition = SCNVector3(5, 3.6, 14)
    private var trackedCameraX: Float = 5
    enum CharacterSource { case bundled, legacy, procedural }
    private var bolts: [Int: SCNNode] = [:]
    private var hurtNodes: [SCNNode] = []
    private var attackNodes: [SCNNode] = []
    private var slamRing: SCNNode?
    private var ended = false

    init(session: DuelSession, characterSource: CharacterSource = .bundled) {
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
        // Neutral, softer rear fill keeps skin and pale clothing from taking on a cyan cast.
        fill.light?.color = UIColor.white; fill.light?.intensity = 180; fill.position = SCNVector3(8, 4, -2)
        world.rootNode.addChildNode(fill)
        buildStage(world.rootNode)
        let ring = DuelActor.shape(SCNTorus(ringRadius: 0.65, pipeRadius: 0.028), .systemOrange)
        ring.geometry?.firstMaterial?.lightingModel = .constant
        ring.castsShadow = false; ring.isHidden = true; world.rootNode.addChildNode(ring); slamRing = ring
        if characterSource != .procedural {
            for hero in Set(session.game.fighters.map(\.hero)) where hero != .gale {
                if session.setup.originalWeapons {
                    do {
                        guard let assets = session.weaponAssets else { throw DuelWeaponAssets.AssetError.missing }
                        weaponAssets[hero] = try assets.character(for: hero)
                    } catch { session.characterFailed() }
                } else if characterSource == .bundled, let identity = DuelOriginalRigAsset.identity(for: hero),
                   let url = DuelOriginalRigAsset.bundledURL(for: identity) {
                    // A present-but-invalid source asset must not be silently
                    // replaced by another person's older model.
                    originalAssets[hero] = try? DuelOriginalRigAsset(url: url, identity: identity)
                } else if let url = DuelCharacterAsset.bundledURL(for: hero),
                   let asset = try? DuelCharacterAsset(url: url, hero: hero) {
                    characterAssets[hero] = asset
                }
            }
            characterAsset = characterAssets[.liu]
            let loaded = session.game.fighters.compactMap { characterAssets[$0.hero] == nil && originalAssets[$0.hero] == nil && weaponAssets[$0.hero] == nil ? nil : $0.hero.name }
            session.characterLoaded(session.setup.originalWeapons ? loaded.joined(separator: "、") + " · 武士刀 / 双锤" : loaded.isEmpty ? "人物资源未就绪 · 当前显示动作替身" : loaded.joined(separator: "、") + " · 全身人物")
        }
        for fighter in session.game.fighters {
            let actor = DuelActor(hero: fighter.hero, asset: characterAssets[fighter.hero], originalAsset: originalAssets[fighter.hero], weaponAsset: weaponAssets[fighter.hero]); actor.root.name = "duel.actor.\(actors.count)"
            if session.setup.originalWeapons && weaponAssets[fighter.hero] == nil { actor.root.isHidden = true }
            actors.append(actor); world.rootNode.addChildNode(actor.root)
            let hurt = debugBox(.green), attack = debugBox(.orange)
            hurtNodes.append(hurt); attackNodes.append(attack); world.rootNode.addChildNode(hurt); world.rootNode.addChildNode(attack)
        }
        session.renderPause = { [weak self] paused in
            self?.sourceEffects?.setPaused(paused)
            self?.weaponEffects?.setPaused(paused)
            if paused { self?.stopClock() } else { self?.startClock() }
        }
        if session.setup.originalWeapons, let directory = session.weaponAssets?.directory {
            do {
                sourceEffects = try DuelSourceEffects(root: world.rootNode, directory: directory)
                weaponEffects = try DuelWeaponEffects(root: world.rootNode, directory: directory)
            }
            catch { session.characterFailed() }
            session.didSimulateStep = { [weak self] game, tick in self?.consumeFeedback(game, tick: tick) }
            session.didReset = { [weak self] in
                self?.sourceEffects?.reset(); self?.weaponEffects?.reset()
            }
            consumeFeedback(session.game, tick: 0)
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
        // A wide fight should show full-height fighters rather than shrinking
        // them to fit the whole stage. Narrow layouts retain a safe overview.
        if stageAsset != nil {
            let vertical = aspect >= 1.5 ? 31.0 : 2 * atan(5.8 / (7.7 * max(0.1, aspect))) * 180 / .pi
            pointOfView?.camera?.fieldOfView = CGFloat(min(100, max(31, vertical)))
        } else {
            pointOfView?.camera?.orthographicScale = aspect >= 1.5 ? 2.85 : max(3.2, 5.8 / max(0.1, aspect))
        }
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
        lastTime = nil; clock.reset(); clockCallbacks = 0; firstStepDelay = nil
        clockStartedAt = CACurrentMediaTime(); rendersContinuously = true; isPlaying = true
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
        ended = true; stopClock(); session.clearInput(); session.renderPause = nil; session.didSimulateStep = nil; session.didReset = nil
        sourceEffects?.shutdown(); sourceEffects = nil
        weaponEffects?.shutdown(); weaponEffects = nil
        NotificationCenter.default.removeObserver(self)
        // Explicitly break the renderer/scene/node graph before clearing the
        // SCNView reference. SceneKit can defer renderer teardown until its
        // autorelease pool drains after repeated fight entries.
        // Flush pending SceneKit node transactions while the renderer is still
        // attached, then disconnect its camera and scene synchronously.
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        scene?.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        pointOfView = nil
        scene = nil
        SCNTransaction.commit()
        SCNTransaction.flush()
        actors.removeAll(); characterAsset = nil; characterAssets.removeAll(); originalAssets.removeAll(); weaponAssets.removeAll(); stageAsset = nil; bolts.removeAll(); hurtNodes.removeAll(); attackNodes.removeAll(); slamRing = nil
    }
    fileprivate func tick(_ timestamp: Double) {
        guard !ended, !session.paused else { return }
        clockCallbacks += 1
        guard let previous = lastTime else { lastTime = timestamp; return }
        lastTime = timestamp
        let elapsed = timestamp - previous
        let steps = clock.consume(seconds: elapsed)
        if steps > 0, firstStepDelay == nil, let started = clockStartedAt {
            firstStepDelay = max(0, timestamp - started)
        }
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
    func drawState() {
        guard scene != nil else { return }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        for i in 0..<actors.count {
            actors[i].pose(session.game.fighters[i], frame: session.animationTick, grapple: session.game.grapple, index: i, phase: session.game.phase)
            place(hurtNodes[i], box: session.game.hurtBox(i), visible: session.showBoxes && session.game.fighters[i].knockdown == 0 && session.game.grapple == nil)
            if let box = session.game.attackBox(i) { place(attackNodes[i], box: box, visible: session.showBoxes) }
            else { attackNodes[i].isHidden = true }
        }
        if let hold = session.game.grapple {
            actors[hold.attacker].connectWrist(to: actors[1 - hold.attacker], hold: hold)
        }
        slamRing?.isHidden = true
        // Follow the pair, not the leading fighter. Smooth changes in the
        // center of combat without allocating animation actions each frame.
        // The zoom-out at large separation keeps both combatants in shot.
        if session.game.fighters.count == 2 {
            let left = Float(session.game.fighters[0].x) / 1000
            let right = Float(session.game.fighters[1].x) / 1000
            let midpoint = min(7.0, max(3.0, (left + right) * 0.5))
            trackedCameraX += (midpoint - trackedCameraX) * 0.12
            let separation = abs(left - right)
            if stageAsset != nil {
                let baseFOV: CGFloat = bounds.width > bounds.height * 1.5 ? 31 : 35
                let extra = CGFloat(max(0, separation - 4.5)) * 3
                pointOfView?.camera?.fieldOfView = min(47, baseFOV + extra)
            } else if bounds.width > bounds.height * 1.5 {
                pointOfView?.camera?.orthographicScale = CGFloat(max(2.85, separation * 0.56 + 0.8))
            }
        }
        var cameraPosition = cameraBasePosition
        cameraPosition.x = trackedCameraX
        pointOfView?.position = cameraPosition
        pointOfView?.look(at: SCNVector3(trackedCameraX, stageAsset != nil ? 1.2 : 1.0, 0))
        if let hold = session.game.grapple {
            let release = DuelGame.Grapple.takedownTicks + DuelGame.Grapple.holdTicks
            let elapsed = hold.age >= release ? hold.age - release : hold.age - DuelGame.Grapple.takedownTicks
            if (0..<18).contains(elapsed), let ring = slamRing {
                let t = Float(elapsed) / 18, scale = 0.5 + 2.0 * t
                ring.isHidden = false; ring.opacity = CGFloat(1 - t)
                ring.position = SCNVector3(Float(session.game.fighters[1 - hold.attacker].x) / 1000, 0.025, 0)
                ring.scale = SCNVector3(scale, 1, scale)
                if !UIAccessibility.isReduceMotionEnabled {
                    pointOfView?.position.y += sin(Float(elapsed) * 1.8) * 0.035 * (1 - t)
                }
            }
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
    private func consumeFeedback(_ game: DuelGame, tick: Int) {
        guard let fight = game.weaponFight else { return }
        let contacts = fight.contacts.map { contact in
            DuelSourceEffects.Contact(kind: contact.kind == .hit ? .hit : .block,
                position: SCNVector3(Float(contact.position.x), Float(contact.position.y), Float(contact.position.z)),
                direction: contact.direction, heavy: contact.heavy,
                sound: !contact.usesWeapon ? .unarmed : fight.profiles[contact.attacker].isKatana ? .katana : .dualHammers)
        }
        let swings = fight.swings.map {
            DuelSourceEffects.Swing(heavy: $0.heavy, sound: !$0.usesWeapon ? .unarmed : fight.profiles[$0.attacker].isKatana ? .katana : .dualHammers)
        }
        // Called for every fixed simulation step, including all catch-up steps.
        // A display frame is not an event queue and must not drop earlier hits.
        sourceEffects?.consumeStep(contacts: contacts, swings: swings, animationTick: tick)
        let poses: [DuelWeaponEffects.Pose] = fight.fighters.enumerated().compactMap { index, fighter in
            guard let pose = fighter.weaponPose, let clip = fight.profiles[index].clip(named: pose.clip) else { return nil }
            let profile = fight.profiles[index], tracks = clip.tracks
            func world(_ value: DuelWeaponPoint) -> SCNVector3 {
                SCNVector3(Float(fighter.x) / 1000 + Float(value.x) * Float(fighter.facing),
                           Float(value.y + pose.groundLift), Float(value.z) * Float(fighter.facing))
            }
            let endpoints: [DuelWeaponEffects.Endpoints] = profile.activeWeaponSides.map { side in
                .init(slot: side == "left" ? 0 : 1,
                      base: world(tracks.sample(side == "left" ? tracks.weaponBaseL : tracks.weaponBaseR, phase: pose.phase)),
                      tip: world(tracks.sample(side == "left" ? tracks.weaponTipL : tracks.weaponTipR, phase: pose.phase)))
            }
            return .init(fighterID: index, family: profile.isKatana ? .katana : .dualHammers,
                         motionID: fight.weaponTrailIsActive(index) ? "\(pose.clip):\(tick - pose.tick)" : nil,
                         isShadow: fight.shadowIsActive(index), endpoints: endpoints)
        }
        weaponEffects?.consumeStep(poses: poses, animationTick: tick)
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
        if let url = DuelStageAsset.bundledURL, let asset = try? DuelStageAsset(url: url) {
            stageAsset = asset
            root.addChildNode(asset.makeRoot())
            cameraBasePosition = SCNVector3(5, 2, 7.7)
            pointOfView?.camera?.usesOrthographicProjection = false
            pointOfView?.camera?.projectionDirection = .vertical
            pointOfView?.camera?.fieldOfView = 35
            pointOfView?.camera?.zFar = 350
            pointOfView?.position = cameraBasePosition
            pointOfView?.look(at: SCNVector3(5, 1.2, 0))
            return
        }
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
    let leftElbow = SCNNode(), rightElbow = SCNNode(), leftKnee = SCNNode(), rightKnee = SCNNode()
    let shield: SCNNode
    private let body: SCNNode
    private var feet: [SCNNode] = []
    private let character: DuelCharacterInstance?
    private let original: DuelOriginalCombatInstance?
    private let weapon: DuelWeaponCharacterInstance?
    init(hero: DuelGame.Hero, asset: DuelCharacterAsset?, originalAsset: DuelOriginalRigAsset? = nil, weaponAsset: DuelWeaponCharacterAsset? = nil) {
        character = asset.map { DuelCharacterInstance($0) }
        original = originalAsset.map { DuelOriginalCombatInstance($0) }
        weapon = weaponAsset.map { DuelWeaponCharacterInstance($0) }
        let color = hero == .liu ? UIColor(white: 0.88, alpha: 1) : hero == .ember ? UIColor.systemOrange : UIColor.systemTeal
        let dark = UIColor(red: 0.10, green: 0.13, blue: 0.22, alpha: 1)
        let skin = UIColor(red: 0.68, green: 0.48, blue: 0.35, alpha: 1)
        body = Self.shape(SCNCapsule(capRadius: hero == .ember ? 0.31 : 0.25, height: 0.72), color)
        body.position.y = 1.08; root.addChildNode(body)
        let head = Self.shape(SCNSphere(radius: 0.23), hero == .liu ? skin : UIColor(red: 0.78, green: 0.82, blue: 0.86, alpha: 1))
        head.name = "head"; head.position.y = 1.67; root.addChildNode(head)
        let visor = Self.shape(SCNBox(width: 0.30, height: 0.09, length: 0.08, chamferRadius: 0.04), dark)
        visor.position = SCNVector3(0, 1.69, 0.20)
        if hero != .liu { root.addChildNode(visor) }
        if hero == .liu {
            let hair = Self.shape(SCNCapsule(capRadius: 0.225, height: 0.30), dark)
            hair.scale = SCNVector3(1, 0.40, 1); hair.position = SCNVector3(0, 1.83, -0.015); root.addChildNode(hair)
            for x in [Float(-0.12), Float(0.12)] {
                let lapel = Self.shape(SCNBox(width: 0.10, height: 0.28, length: 0.035, chamferRadius: 0.01), .white)
                lapel.position = SCNVector3(x, 1.23, 0.255); lapel.eulerAngles.z = x > 0 ? -0.28 : 0.28; root.addChildNode(lapel)
            }
            let tie = Self.shape(SCNBox(width: 0.06, height: 0.30, length: 0.035, chamferRadius: 0.01), dark)
            tie.position = SCNVector3(0, 1.22, 0.28); root.addChildNode(tie)
        }
        let belt = Self.shape(SCNBox(width: 0.53, height: 0.16, length: 0.32, chamferRadius: 0.06), dark)
        belt.name = "hip"; belt.position.y = 0.74; root.addChildNode(belt)
        for (joint, elbow, x) in [(leftArm, leftElbow, Float(-0.37)), (rightArm, rightElbow, Float(0.37))] {
            joint.position = SCNVector3(x, 1.33, 0); root.addChildNode(joint)
            let arm = Self.shape(SCNCapsule(capRadius: 0.105, height: 0.30), hero == .liu ? color : dark)
            arm.position.y = -0.13; joint.addChildNode(arm)
            elbow.position.y = -0.28; joint.addChildNode(elbow)
            let forearm = Self.shape(SCNCapsule(capRadius: 0.09, height: 0.24), hero == .liu ? color : dark)
            forearm.position.y = -0.10; elbow.addChildNode(forearm)
            let fist = Self.shape(SCNBox(width: hero == .ember ? 0.29 : 0.21, height: 0.22, length: 0.25, chamferRadius: 0.08), hero == .liu ? skin : color)
            fist.name = x < 0 ? "duel.hand.left" : "duel.hand.right"
            fist.position = SCNVector3(0, -0.24, 0.04); elbow.addChildNode(fist)
        }
        for (joint, knee, x) in [(leftLeg, leftKnee, Float(-0.17)), (rightLeg, rightKnee, Float(0.17))] {
            joint.position = SCNVector3(x, 0.72, 0); root.addChildNode(joint)
            let leg = Self.shape(SCNCapsule(capRadius: 0.115, height: 0.35), dark); leg.position.y = -0.15; joint.addChildNode(leg)
            knee.position.y = -0.32; joint.addChildNode(knee)
            let shin = Self.shape(SCNCapsule(capRadius: 0.10, height: 0.34), dark); shin.position.y = -0.15; knee.addChildNode(shin)
            let foot = Self.shape(SCNBox(width: 0.24, height: 0.15, length: 0.40, chamferRadius: 0.05), hero == .liu ? dark : color)
            foot.name = x < 0 ? "duel.foot.left" : "duel.foot.right"
            foot.position = SCNVector3(0, -0.33, 0.09); knee.addChildNode(foot); feet.append(foot)
        }
        shield = Self.shape(SCNTorus(ringRadius: 0.54, pipeRadius: 0.025), .cyan)
        shield.position = SCNVector3(0, 1, 0.55); shield.eulerAngles.x = .pi / 2; shield.isHidden = true
        root.addChildNode(shield)
        if let presentedRoot = weapon?.instance.root ?? original?.instance.root ?? character?.instance.root {
            for child in root.childNodes where child !== shield { child.isHidden = true }
            root.addChildNode(presentedRoot)
        }
    }
    private func bone(_ name: String) -> SCNNode? { original?.bone(name) ?? character?.bone(name) }
    private func reach(suffix: String, target: SIMD3<Float>, weight: Float) {
        if let original { original.reach(suffix: suffix, target: target, weight: weight) }
        else { character?.reach(suffix: suffix, target: target, weight: weight) }
    }
    func connectWrist(to other: DuelActor, hold: DuelGame.Grapple) {
        guard character != nil || original != nil else { return }
        let suffix = hold.direction > 0 ? "R" : "L"
        let name = hold.direction > 0 ? "duel.hand.right" : "duel.hand.left"
        let fall = min(1, Float(hold.age) / Float(DuelGame.Grapple.takedownTicks))
        let release = max(0, Float(hold.age - DuelGame.Grapple.takedownTicks - DuelGame.Grapple.holdTicks) / Float(DuelGame.Grapple.releaseTicks))
        let weight = fall * fall * (3 - 2 * fall) * (1 - release)
        if other.character == nil && other.original == nil {
            // Raise the captured wrist to match the authored adult's shoulder
            // height; preserve the old greybox pair when no real asset is used.
            let heldArm = hold.direction > 0 ? other.rightArm : other.leftArm
            heldArm.eulerAngles.x = -3.85 * fall * fall * (3 - 2 * fall)
        } else if let shoulder = bone("upper_arm.\(suffix)"),
                  let capturedShoulder = other.bone("upper_arm.\(suffix)") {
            // A skinned opponent's Hit pose leaves its wrist on the floor,
            // beyond the attacker's reach. Raise that arm toward a shared
            // contact between the shoulders before constraining the grip.
            // Both skeletons retain their authored arm lengths.
            let contact = (shoulder.simdWorldPosition + capturedShoulder.simdWorldPosition) * 0.5
            other.reach(suffix: suffix, target: contact, weight: weight)
        }
        guard let target = other.bone("hand.\(suffix)") ?? other.root.childNode(withName: name, recursively: true) else { return }
        reach(suffix: suffix, target: target.simdWorldPosition, weight: weight)
    }
    static func shape(_ geometry: SCNGeometry, _ color: UIColor) -> SCNNode {
        let material = SCNMaterial(); material.diffuse.contents = color; material.roughness.contents = 0.7
        material.metalness.contents = 0.12; material.lightingModel = .physicallyBased
        geometry.materials = [material]; return SCNNode(geometry: geometry)
    }
    private func orient(yaw: Float, worldRoll: Float) {
        // Apply facing before a world-space fall/lean. Combining Euler yaw and
        // roll would roll first in SceneKit and tip the body into scene depth.
        root.simdOrientation = simd_quatf(angle: worldRoll, axis: SIMD3<Float>(0, 0, 1)) *
            simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    }
    func pose(_ fighter: DuelGame.Fighter, frame: Int, grapple: DuelGame.Grapple?, index: Int, phase: DuelGame.Phase) {
        if let weapon {
            weapon.pose(fighter, root: root); shield.isHidden = true
            return
        }
        if let original {
            original.pose(fighter, tick: frame, grapple: grapple, index: index, phase: phase, root: root)
            shield.isHidden = !fighter.guarding || grapple != nil
            return
        }
        if let character {
            character.pose(fighter, tick: frame, grapple: grapple, index: index, phase: phase, root: root)
            shield.isHidden = !fighter.guarding || grapple != nil
            return
        }
        root.position = SCNVector3(Float(fighter.x) / 1000, Float(fighter.y) / 1000, 0)
        let yaw: Float = fighter.facing > 0 ? .pi / 2 : -.pi / 2
        orient(yaw: yaw, worldRoll: fighter.knockdown > 0 ? Float(fighter.facing) * -.pi / 2 : 0)
        if fighter.knockdown > 0 { root.position.y = 0.25; root.position.x -= Float(fighter.facing) * 0.95 }
        for joint in [leftElbow, rightElbow, leftKnee, rightKnee] { joint.eulerAngles = SCNVector3Zero }
        for foot in feet { foot.eulerAngles = SCNVector3Zero }
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
            if attack.move == .ultimate {
                leftArm.eulerAngles.x = -0.75; rightArm.eulerAngles.x = -0.8
                leftElbow.eulerAngles.x = -0.45; rightElbow.eulerAngles.x = -0.40
                orient(yaw: yaw, worldRoll: -Float(fighter.facing) * 0.10)
            }
        }
        if let hold = grapple {
            shield.isHidden = true
            let fall = min(1, Float(hold.age) / Float(DuelGame.Grapple.takedownTicks))
            let eased = fall * fall * (3 - 2 * fall)
            let release = max(0, Float(hold.age - DuelGame.Grapple.takedownTicks - DuelGame.Grapple.holdTicks) / Float(DuelGame.Grapple.releaseTicks))
            let direction = Float(hold.direction)
            if index == hold.attacker {
                // Stable side-on wrist/shoulder hold with a clear gap between
                // the attacker and the prone opponent's head.
                let crouch = eased * (1 - release)
                root.position.x -= direction * 0.05 * crouch
                root.position.y = -0.38 * crouch; root.position.z = 0.55 * eased
                orient(yaw: yaw, worldRoll: -direction * 0.20 * crouch)
                leftLeg.eulerAngles.x = -0.90 * crouch; rightLeg.eulerAngles.x = -0.82 * crouch
                leftKnee.eulerAngles.x = 2.38 * crouch; rightKnee.eulerAngles.x = 2.36 * crouch
                // Keep the soles level and lift the root during the transition
                // when straight interpolation would sink the shins below stage.
                feet[0].eulerAngles.x = -(leftLeg.eulerAngles.x + leftKnee.eulerAngles.x + 0.20 * crouch)
                feet[1].eulerAngles.x = -(rightLeg.eulerAngles.x + rightKnee.eulerAngles.x + 0.20 * crouch)
                let lowestSole = min(feet[0].worldPosition.y, feet[1].worldPosition.y) - 0.075
                root.position.y += max(0, -0.05 - lowestSole)
                let gripArm = direction > 0 ? rightArm : leftArm, gripElbow = direction > 0 ? rightElbow : leftElbow
                let supportArm = direction > 0 ? leftArm : rightArm, supportElbow = direction > 0 ? leftElbow : rightElbow
                supportArm.eulerAngles.x = -0.85 + 0.40 * crouch; gripArm.eulerAngles.x = -0.80 + 0.30 * crouch
                supportElbow.eulerAngles.x = -0.35; gripElbow.eulerAngles.x = -0.20
            } else {
                root.position.x += direction * (1.35 * eased + 0.30 * release)
                root.position.y = 0.25 * eased + sin(fall * .pi) * 0.25
                root.position.z = -0.08 * eased; orient(yaw: yaw, worldRoll: direction * .pi / 2 * eased)
                leftLeg.eulerAngles.x = -0.12; rightLeg.eulerAngles.x = 0.12
                leftKnee.eulerAngles.x = 0.18; rightKnee.eulerAngles.x = 0.35
                let heldArm = direction > 0 ? rightArm : leftArm, heldElbow = direction > 0 ? rightElbow : leftElbow
                let freeArm = direction > 0 ? leftArm : rightArm, freeElbow = direction > 0 ? leftElbow : rightElbow
                freeArm.eulerAngles.x = -0.90 * eased; heldArm.eulerAngles.x = -3.50 * eased
                freeElbow.eulerAngles.x = -0.55 * eased; heldElbow.eulerAngles.x = 0
            }
        }
        body.geometry?.firstMaterial?.emission.contents = fighter.flash > 0 ? UIColor(red: 0.22, green: 0.10, blue: 0.02, alpha: 1) : UIColor.black
    }
}
