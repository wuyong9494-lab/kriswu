import SwiftUI
import SceneKit
import UIKit
import simd

/// Interactive 3D character showroom; its lightweight idle clock stops offscreen.
struct DuelLobbyPreview: UIViewRepresentable {
    let hero: DuelGame.Hero
    var visibleRegion: CGRect? = nil
    func makeUIView(context: Context) -> DuelLobbySceneView { DuelLobbySceneView(hero: hero) }
    func updateUIView(_ view: DuelLobbySceneView, context: Context) {
        view.setVisibleRegion(visibleRegion)
        view.select(hero)
    }
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
    private(set) var visibleRegion: CGRect?
    private(set) var framing: DuelLobbyFraming?
    private(set) var showroomFrameCount = 0
    /// Host showroom placement only. The verified pedestal's highest point is
    /// -0.1182284; corrected equipped idle soles reach -0.0038394 relative to
    /// their root after the unchanged source lift. This baseline clears both.
    private static let equippedPedestalBaselineY: Float = -0.113

    private func showroomBaseline(for actor: DuelWeaponCharacterInstance) -> Float {
        // Do not apply an asset-specific support correction to a missing stage,
        // legacy character, or a future export with different geometry.
        guard let stage, case .autumnLobby = stage.kind else { return -0.14 }
        switch actor.asset.profile.sha256 {
        case "5a1a64c9986b0d5284a7986efc1589dbfc1f00f91ac9477cdae45930612ac553",
             "9ff998118a69b1d089694e97b2623cf6d6fb81e64451a8462dddaff756b6a09f":
            return Self.equippedPedestalBaselineY
        default: return -0.14
        }
    }

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
        camera.camera?.projectionDirection = .vertical; camera.camera?.fieldOfView = CGFloat(DuelLobbyFraming.verticalFieldOfView)
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
    override func layoutSubviews() {
        super.layoutSubviews()
        updateCameraFraming()
    }

    func setVisibleRegion(_ region: CGRect?) {
        guard visibleRegion != region else { return }
        visibleRegion = region
        updateCameraFraming()
    }

    private func updateCameraFraming() {
        guard let cameraNode, let camera = cameraNode.camera else { return }
        let region = visibleRegion ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let rect = CGRect(x: region.minX * bounds.width, y: region.minY * bounds.height,
                          width: region.width * bounds.width, height: region.height * bounds.height)
        guard let fit = DuelLobbyFraming(size: bounds.size, visibleRect: rect, zoom: Double(zoom)) else { return }
        framing = fit
        cameraNode.position = SCNVector3(Float(fit.position.x), Float(fit.position.y), Float(fit.position.z))
        cameraNode.look(at: showroomCenter)
        equippedActor?.materialBinding?.update(viewTransform: simd_inverse(cameraNode.simdWorldTransform))
        camera.fieldOfView = CGFloat(fit.verticalFieldOfViewDegrees)
        // A perspective lens shift changes composition, not the physical eye.
        // Both landscape fitting and stacked-preview zoom must remain in front
        // of the verified lobby's opaque foreground rail.
        let near: Float = 0.05, far: Float = 100
        var projection = SCNMatrix4Identity
        projection.m11 = Float(1 / (fit.verticalTangent * Double(bounds.width / bounds.height)))
        projection.m22 = Float(1 / fit.verticalTangent)
        projection.m31 = -Float(fit.projectionOffset.x)
        projection.m32 = -Float(fit.projectionOffset.y)
        projection.m33 = -(far + near) / (far - near)
        projection.m34 = -1
        projection.m43 = -(2 * far * near) / (far - near)
        projection.m44 = 0
        camera.projectionTransform = projection
        setNeedsDisplay()
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
        guard equippedActor != nil, equippedIdle != nil else { return }
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
        actor.instance.root.position.y = showroomBaseline(for: actor) + Float(lift)
        showroomFrameCount += 1
        setNeedsDisplay()
    }
    /// A vertical gesture belongs to the enclosing SwiftUI ScrollView.
    /// Otherwise the SceneKit pan eats the swipe and hides the practice button.
    static func acceptsHorizontalPan(_ movement: CGPoint) -> Bool {
        abs(movement.x) > abs(movement.y) * 1.15 && abs(movement.x) > 1
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        return Self.acceptsHorizontalPan(pan.translation(in: self))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer is UIPinchGestureRecognizer &&
            otherGestureRecognizer is UIPanGestureRecognizer
    }
    func rotatePreview(by amount: Float) {
        guard amount.isFinite else { return }
        yaw += amount
        characterRoot?.eulerAngles.y = yaw
        setNeedsDisplay()
    }
    func scalePreview(by factor: Float) {
        guard cameraNode != nil, factor.isFinite, factor > 0 else { return }
        zoom = min(1.5, max(0.7, zoom / factor))
        updateCameraFraming()
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

        // Prepare the new, fully posed scene node before touching the visible
        // character, its camera state or its idle driver. A missing profile,
        // damaged model or failed decode must leave the current portrait intact.
        var nextRoot: SCNNode?
        var nextWeaponAssets: DuelWeaponAssets?
        var nextEquippedActor: DuelWeaponCharacterInstance?
        var nextEquippedIdle: DuelWeaponClip?
        var nextOriginal: DuelOriginalRigAsset?
        var nextCharacter: DuelCharacterAsset?

        if !ProcessInfo.processInfo.arguments.contains("-duel-legacy-controls"),
           DuelWeaponAssets.catalogURL() != nil {
            do {
                let assets = try weaponAssets ?? DuelWeaponAssets()
                let asset = try assets.character(for: hero)
                guard let idle = asset.profile.clip(role: "idle") else { return }
                let actor = DuelWeaponCharacterInstance(asset, environment: .autumn)
                let lift = idle.tracks.lift(phase: 0)
                actor.apply(.init(clip: idle.name, tick: 0,
                                  duration: idle.ticks, groundLift: lift))
                actor.instance.root.position = SCNVector3(4.7, showroomBaseline(for: actor) + Float(lift), -0.35)
                actor.instance.root.eulerAngles.y = .pi
                nextRoot = actor.instance.root
                nextWeaponAssets = assets
                nextEquippedActor = actor
                nextEquippedIdle = idle
            } catch { return }
        } else if let identity = DuelOriginalRigAsset.identity(for: hero),
                  let url = DuelOriginalRigAsset.bundledURL(for: identity) {
            guard let asset = try? DuelOriginalRigAsset(url: url, identity: identity) else { return }
            let actor = DuelOriginalRigInstance(asset)
            actor.apply(.init(clip: .idle, phase: 0))
            actor.instance.root.position = SCNVector3(4.7, -0.14, -0.35)
            actor.instance.root.eulerAngles.y = .pi
            nextRoot = actor.instance.root
            nextOriginal = asset
        } else {
            guard let url = DuelCharacterAsset.bundledURL(for: hero),
                  let asset = try? DuelCharacterAsset(url: url, hero: hero) else { return }
            let instance = asset.model.instantiate()
            var pose = asset.model.restPose
            if let clip = asset.model.clips["Idle"] {
                clip.sample(at: asset.starts["Idle"] ?? 0, into: &pose)
                for i in asset.model.animated { instance.nodes[i].simdTransform = pose.transform(i) }
            }
            instance.root.position = SCNVector3(4.7, -0.14, -0.35)
            nextRoot = instance.root
            nextCharacter = asset
        }
        guard let nextRoot else { return }
        nextRoot.name = "duel.lobby.character.\(hero.rawValue)"

        // Commit a successful switch on the main actor. Detach and release the
        // retired model only after the replacement has passed preparation.
        stopIdle()
        let previousHero = selectedHero
        let previousAssets = weaponAssets
        characterRoot?.removeFromParentNode()
        characterRoot = nextRoot
        character = nextCharacter
        originalCharacter = nextOriginal
        equippedActor = nextEquippedActor
        equippedIdle = nextEquippedIdle
        weaponAssets = nextWeaponAssets
        if let previousHero { previousAssets?.releaseCharacter(for: previousHero) }
        selectedHero = hero
        idleTick = 0; yaw = .pi; zoom = 1
        updateCameraFraming()
        scene.rootNode.addChildNode(nextRoot)
        startIdle()
        setNeedsDisplay()
    }
    func shutdown() {
        // Detach resource-owning nodes even if SceneKit keeps an autoreleased
        // scene or renderer alive until the current event finishes.
        stopIdle()
        gestureRecognizers?.forEach { removeGestureRecognizer($0) }
        scene?.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        scene = nil; pointOfView = nil; stage = nil; character = nil; originalCharacter = nil; characterRoot = nil; weaponAssets = nil; equippedActor = nil; equippedIdle = nil; cameraNode = nil
        visibleRegion = nil; framing = nil
        rendersContinuously = false; isPlaying = false
    }
}
