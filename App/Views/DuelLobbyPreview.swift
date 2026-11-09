import SwiftUI
import SceneKit
import UIKit

/// Interactive 3D character showroom; its lightweight idle clock stops offscreen.
struct DuelLobbyPreview: UIViewRepresentable {
    let hero: DuelGame.Hero
    func makeUIView(context: Context) -> DuelLobbySceneView { DuelLobbySceneView(hero: hero) }
    func updateUIView(_ view: DuelLobbySceneView, context: Context) { view.select(hero) }
    static func dismantleUIView(_ view: DuelLobbySceneView, coordinator: ()) { view.shutdown() }
}

@MainActor
final class DuelLobbySceneView: SCNView, UIGestureRecognizerDelegate {
    private(set) var selectedHero: DuelGame.Hero?
    private var stage: DuelStageAsset?
    private var character: DuelCharacterAsset?
    private var originalCharacter: DuelOriginalRigAsset?
    private var characterRoot: SCNNode?
    private var weaponAssets: DuelWeaponAssets?
    private var equippedActor: DuelWeaponCharacterInstance?
    private var equippedIdle: DuelWeaponClip?
    private var idleDriver: CADisplayLink?
    private var idleTick = 0
    private var lastIdleTime: CFTimeInterval?
    private var accumulatedIdleTime: CFTimeInterval = 0
    private(set) var yaw: Float = .pi
    private(set) var zoom: Float = 1
    private var cameraNode: SCNNode?
    private let showroomCenter = SCNVector3(4.7, 0.85, -0.35)
    private(set) var showroomFrameCount = 0

    init(hero: DuelGame.Hero) {
        super.init(frame: .zero, options: nil)
        backgroundColor = UIColor(red: 0.045, green: 0.04, blue: 0.075, alpha: 1)
        antialiasingMode = .multisampling2X
        rendersContinuously = false; isPlaying = false; isUserInteractionEnabled = true
        isAccessibilityElement = false; accessibilityElementsHidden = true
        let world = SCNScene(); scene = world
        if let url = DuelStageAsset.bundledURL(for: .autumnLobby),
           let asset = try? DuelStageAsset(url: url, kind: .autumnLobby) {
            stage = asset; world.rootNode.addChildNode(asset.makeRoot())
        }
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.projectionDirection = .vertical; camera.camera?.fieldOfView = 35
        camera.camera?.zNear = 0.05; camera.camera?.zFar = 100
        camera.position = SCNVector3(5, 1.6, 4.8)
        camera.look(at: SCNVector3(4.7, 0.85, -0.35))
        world.rootNode.addChildNode(camera); pointOfView = camera; cameraNode = camera
        let rotate = UIPanGestureRecognizer(target: self, action: #selector(rotateCharacter(_:)))
        rotate.maximumNumberOfTouches = 1
        rotate.delegate = self
        addGestureRecognizer(rotate)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(zoomCharacter(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 450; ambient.light?.color = UIColor(white: 0.8, alpha: 1)
        world.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional
        key.light?.intensity = 1100; key.light?.color = UIColor(red: 1, green: 0.91, blue: 0.8, alpha: 1)
        key.eulerAngles = SCNVector3(-0.7, -0.4, 0); world.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .omni
        // Neutral fill keeps the personal face and armor consistent with combat.
        fill.light?.intensity = 180; fill.light?.color = UIColor.white
        fill.position = SCNVector3(7, 3, -1); world.rootNode.addChildNode(fill)
        select(hero)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopIdle() } else { startIdle() }
    }
    private func startIdle() {
        guard window != nil, equippedActor != nil, idleDriver == nil else { return }
        let driver = CADisplayLink(target: self, selector: #selector(advanceIdle(_:)))
        driver.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        driver.add(to: .main, forMode: .common)
        idleDriver = driver
        lastIdleTime = nil
    }
    private func stopIdle() {
        idleDriver?.invalidate(); idleDriver = nil
        lastIdleTime = nil; accumulatedIdleTime = 0
    }
    @objc private func advanceIdle(_ link: CADisplayLink) {
        guard let actor = equippedActor, let idle = equippedIdle else { return }
        defer { lastIdleTime = link.timestamp }
        guard let lastIdleTime else { return }
        accumulatedIdleTime += min(0.1, max(0, link.timestamp - lastIdleTime))
        let steps = Int(accumulatedIdleTime * 60)
        guard steps > 0 else { return }
        accumulatedIdleTime -= Double(steps) / 60
        renderIdle(at: idleTick + steps)
    }
    /// One source sample per simulation tick; also updates sole clearance.
    /// Keeping this deterministic makes the showroom animation testable.
    func renderIdle(at tick: Int) {
        guard let actor = equippedActor, let idle = equippedIdle else { return }
        idleTick = tick % max(1, idle.ticks)
        let phase = idle.phase(at: idleTick)
        let lift = idle.tracks.lift(phase: phase)
        actor.apply(.init(clip: idle.name, tick: idleTick, duration: idle.ticks,
                          groundLift: lift))
        actor.instance.root.position.y = -0.14 + Float(lift)
        showroomFrameCount += 1
        setNeedsDisplay()
    }
    /// A vertical gesture belongs to the enclosing SwiftUI ScrollView.
    /// Otherwise the SceneKit pan eats the swipe and hides the practice button.
    static func acceptsHorizontalPan(_ movement: CGPoint) -> Bool {
        abs(movement.x) > abs(movement.y) * 1.15 && abs(movement.x) > 1
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        return Self.acceptsHorizontalPan(pan.translation(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer is UIPinchGestureRecognizer &&
            otherGestureRecognizer is UIPanGestureRecognizer
    }
    func rotatePreview(by amount: Float) {
        guard let characterRoot, amount.isFinite else { return }
        yaw += amount
        characterRoot.eulerAngles.y = yaw
        setNeedsDisplay()
    }
    func scalePreview(by factor: Float) {
        guard let cameraNode, factor.isFinite, factor > 0 else { return }
        zoom = min(1.5, max(0.7, zoom / factor))
        cameraNode.position = SCNVector3(5, 1.6, -0.35 + 5.15 * zoom)
        cameraNode.look(at: showroomCenter)
        setNeedsDisplay()
    }
    @objc private func rotateCharacter(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        rotatePreview(by: Float(translation.x) * 0.008)
    }
    @objc private func zoomCharacter(_ gesture: UIPinchGestureRecognizer) {
        scalePreview(by: Float(gesture.scale))
        gesture.scale = 1
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(_ hero: DuelGame.Hero) {
        guard selectedHero != hero, let scene else { return }
        stopIdle()
        let previousHero = selectedHero
        selectedHero = hero; idleTick = 0; yaw = .pi; zoom = 1
        cameraNode?.position = SCNVector3(5, 1.6, 4.8)
        cameraNode?.look(at: showroomCenter)
        characterRoot?.removeFromParentNode(); characterRoot = nil; character = nil; originalCharacter = nil
        equippedActor = nil; equippedIdle = nil
        // A retired model must not stay cached as an invisible second character.
        if let previousHero { weaponAssets?.releaseCharacter(for: previousHero) }
        if !ProcessInfo.processInfo.arguments.contains("-duel-legacy-controls"), DuelWeaponAssets.catalogURL() != nil {
            do {
                if weaponAssets == nil { weaponAssets = try DuelWeaponAssets() }
                guard let asset = try weaponAssets?.character(for: hero), let idle = asset.profile.clip(role: "idle") else { return }
                let actor = DuelWeaponCharacterInstance(asset)
                actor.apply(.init(clip: idle.name, tick: 0, duration: idle.ticks, groundLift: idle.tracks.lift(phase: 0)))
                actor.instance.root.position = SCNVector3(4.7, -0.14 + Float(idle.tracks.lift(phase: 0)), -0.35)
                actor.instance.root.eulerAngles.y = .pi
                actor.instance.root.name = "duel.lobby.character.\(hero.rawValue)"
                scene.rootNode.addChildNode(actor.instance.root); characterRoot = actor.instance.root
                equippedActor = actor; equippedIdle = idle
                startIdle(); setNeedsDisplay()
            } catch { return }
            return
        }
        if let identity = DuelOriginalRigAsset.identity(for: hero),
           let url = DuelOriginalRigAsset.bundledURL(for: identity) {
            guard let asset = try? DuelOriginalRigAsset(url: url, identity: identity) else { return }
            let actor = DuelOriginalRigInstance(asset)
            actor.apply(.init(clip: .idle, phase: 0))
            actor.instance.root.position = SCNVector3(4.7, -0.14, -0.35)
            actor.instance.root.eulerAngles.y = .pi
            actor.instance.root.name = "duel.lobby.character.\(hero.rawValue)"
            scene.rootNode.addChildNode(actor.instance.root)
            originalCharacter = asset; characterRoot = actor.instance.root; setNeedsDisplay()
            return
        }
        guard let url = DuelCharacterAsset.bundledURL(for: hero),
              let asset = try? DuelCharacterAsset(url: url, hero: hero) else { return }
        let instance = asset.model.instantiate()
        var pose = asset.model.restPose
        if let clip = asset.model.clips["Idle"] {
            clip.sample(at: asset.starts["Idle"] ?? 0, into: &pose)
            for i in asset.model.animated { instance.nodes[i].simdTransform = pose.transform(i) }
        }
        instance.root.position = SCNVector3(4.7, -0.14, -0.35)
        instance.root.name = "duel.lobby.character.\(hero.rawValue)"
        scene.rootNode.addChildNode(instance.root)
        character = asset; characterRoot = instance.root; setNeedsDisplay()
    }
    func shutdown() {
        // Detach resource-owning nodes even if SceneKit keeps an autoreleased
        // scene or renderer alive until the current event finishes.
        stopIdle()
        gestureRecognizers?.forEach { removeGestureRecognizer($0) }
        scene?.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        scene = nil; pointOfView = nil; stage = nil; character = nil; originalCharacter = nil; characterRoot = nil; weaponAssets = nil; equippedActor = nil; equippedIdle = nil; cameraNode = nil
        rendersContinuously = false; isPlaying = false
    }
}
