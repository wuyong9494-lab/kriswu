import SwiftUI
import SceneKit
import UIKit
import simd

/// Display-only values copied from an already verified catalog. This never owns
/// the catalog's motion tracks, character models or their resource manager.
struct DuelLobbyIdentitySnapshot: Equatable, Sendable {
    struct Identity: Equatable, Sendable {
        let profileID: String
        let bodyID: String
        let weaponID: String
        let title: String
        let weaponTitle: String
        let hasDirectionalAttacks: Bool
        let hasHeavy: Bool

        var skillHelp: String {
            if profileID == "wuyong_erlang" {
                return "天律长枪：方向攻击与长按重击；远程键冥想或飞剑，光能满时进入金身。金身技能：下踏击、前开山斧、后天眼、上裂地枪；附加键召犬或终末裁决。"
            }
            let attack = hasDirectionalAttacks ? "配合摇杆施放方向攻击" : "点击武器键攻击"
            return weaponTitle + "：" + attack + (hasHeavy ? "；长按武器键重击。" : "。")
        }
    }

    var displaysSerpentPersonalHead: Bool?
    let byHero: [DuelGame.Hero: Identity]
    let unavailableReasons: [DuelGame.Hero: String]

    /// A display projection only; this cannot load a character or authorize a
    /// combat catalog. Production projections come from the verified store.
    init(displayIdentities: [DuelGame.Hero: Identity],
         unavailableReasons: [DuelGame.Hero: String] = [:]) {
        byHero = displayIdentities
        self.unavailableReasons = unavailableReasons
    }

    func intendedIdentity(for hero: DuelGame.Hero) -> Identity? {
        guard unavailableReasons[hero] == nil, let identity = byHero[hero],
              hero.characterIdentity.matches(hero: hero, profileID: identity.profileID,
                  bodyID: identity.bodyID, weaponID: identity.weaponID) else { return nil }
        return identity
    }

    func unavailableMessage(for hero: DuelGame.Hero) -> String? {
        if let reason = unavailableReasons[hero] { return reason }
        return intendedIdentity(for: hero) == nil ? "专属角色资源尚未就绪" : nil
    }

    init(verifiedCatalog catalog: DuelWeaponCatalog) { self.init(verifiedProfiles: catalog.profiles) }
    init(verifiedProfiles profiles: [DuelWeaponProfile],
         unavailableReasons: [DuelGame.Hero: String] = [:]) {
        self.unavailableReasons = unavailableReasons
        let directions: [DuelWeaponCommand] = [.weaponForward, .weaponUp, .weaponDown, .weaponBack]
        byHero = profiles.reduce(into: [:]) { identities, profile in
            identities[profile.hero] = Identity(profileID: profile.id,
                bodyID: profile.bodyID, weaponID: profile.weaponID, title: profile.title,
                weaponTitle: profile.weaponTitle,
                hasDirectionalAttacks: directions.contains { profile.clip(command: $0) != nil },
                hasHeavy: profile.clip(command: .heavy) != nil)
        }
    }

    @MainActor
    init(verifiedAssets assets: DuelWeaponAssets) {
        // Raw loader diagnostics can contain private paths. Only this bounded
        // user-facing state is copied into the showroom's display projection.
        self.init(verifiedProfiles: assets.localProfiles,
                  unavailableReasons: assets.unavailableHeroes.mapValues { _ in "角色资源校验未通过" })
    }
}

/// Interactive 3D character showroom; its lightweight idle clock stops offscreen.
struct DuelLobbyPreview: UIViewRepresentable {
    let hero: DuelGame.Hero
    var requiresIntendedCharacter = true
    var verifiedIndex: DuelWeaponAssetIndex? = nil
    var preparedAutumnLobby: DuelStageAsset.PreparedAutumnLobby? = nil
    var visibleRegion: CGRect? = nil
    var onCatalogIdentity: ((DuelLobbyIdentitySnapshot) -> Void)? = nil
    var onSelectedHero: ((DuelGame.Hero?) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> DuelLobbySceneView {
        let view = DuelLobbySceneView(hero: hero, requiresIntendedCharacter: requiresIntendedCharacter,
                                     verifiedIndex: verifiedIndex, preparedAutumnLobby: preparedAutumnLobby)
        view.isHidden = requiresIntendedCharacter && view.selectedHero != hero
        context.coordinator.update(view.catalogIdentity, onChange: onCatalogIdentity)
        context.coordinator.updateSelection(view.selectedHero, onChange: onSelectedHero)
        return view
    }
    func updateUIView(_ view: DuelLobbySceneView, context: Context) {
        view.setVisibleRegion(visibleRegion)
        view.select(hero)
        view.isHidden = requiresIntendedCharacter && view.selectedHero != hero
        context.coordinator.update(view.catalogIdentity, onChange: onCatalogIdentity)
        context.coordinator.updateSelection(view.selectedHero, onChange: onSelectedHero)
    }
    static func dismantleUIView(_ view: DuelLobbySceneView, coordinator: Coordinator) {
        coordinator.invalidate()
        view.shutdown()
    }

    @MainActor
    final class Coordinator {
        private var onChange: ((DuelLobbyIdentitySnapshot) -> Void)?
        private var published: DuelLobbyIdentitySnapshot?
        private var pending: DuelLobbyIdentitySnapshot?
        private var generation: UInt64 = 0
        private var invalidated = false
        private var selectionChange: ((DuelGame.Hero?) -> Void)?
        private var publishedSelection: DuelGame.Hero?
        private var pendingSelection: DuelGame.Hero?
        private var hasPublishedSelection = false
        private var selectionIsPending = false
        private var selectionGeneration: UInt64 = 0

        func updateSelection(_ hero: DuelGame.Hero?, onChange: ((DuelGame.Hero?) -> Void)?) {
            guard !invalidated else { return }
            selectionChange = onChange
            guard onChange != nil else {
                selectionGeneration &+= 1; selectionIsPending = false
                hasPublishedSelection = false
                return
            }
            guard !hasPublishedSelection || hero != publishedSelection else {
                selectionGeneration &+= 1; selectionIsPending = false
                return
            }
            guard !selectionIsPending || hero != pendingSelection else { return }
            selectionGeneration &+= 1
            let delivery = selectionGeneration
            pendingSelection = hero; selectionIsPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.invalidated, self.selectionGeneration == delivery,
                      self.selectionIsPending, let callback = self.selectionChange else { return }
                self.selectionIsPending = false
                self.publishedSelection = hero; self.hasPublishedSelection = true
                callback(hero)
            }
        }

        func update(_ snapshot: DuelLobbyIdentitySnapshot?,
                    onChange: ((DuelLobbyIdentitySnapshot) -> Void)?) {
            guard !invalidated else { return }
            self.onChange = onChange
            guard let snapshot, onChange != nil else {
                generation &+= 1; pending = nil; published = nil
                self.onChange = nil
                return
            }
            guard snapshot != published else {
                generation &+= 1; pending = nil
                return
            }
            guard snapshot != pending else { return }
            generation &+= 1
            let delivery = generation
            pending = snapshot
            // make/updateUIView run inside SwiftUI updates. Publish only after
            // that update, using the latest callback and this live coordinator.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.invalidated, self.generation == delivery,
                      self.pending == snapshot, let callback = self.onChange else { return }
                self.pending = nil; self.published = snapshot
                callback(snapshot)
            }
        }

        func invalidate() {
            invalidated = true; generation &+= 1
            pending = nil; published = nil; onChange = nil
            selectionGeneration &+= 1; selectionIsPending = false; selectionChange = nil
        }
    }
}

@MainActor
final class DuelLobbySceneView: SCNView, UIGestureRecognizerDelegate {
    private let verifiedIndex: DuelWeaponAssetIndex?
    private let requiresIntendedCharacter: Bool
    private var lastRequestedHero: DuelGame.Hero?
    private(set) var selectedHero: DuelGame.Hero?
    private(set) var catalogIdentity: DuelLobbyIdentitySnapshot?
    private var stage: DuelStageAsset?
    private var character: DuelCharacterAsset?
    private var originalCharacter: DuelOriginalRigAsset?
    private var cascadeurCharacter: DuelCascadeurCharacterInstance?
    private var cascadeurLoadTask: Task<Void, Never>?
    private var sanctuaryStageTask: Task<Void, Never>?
    private var characterRoot: SCNNode?
    private var weaponAssets: DuelWeaponAssets?
    private var equippedActor: DuelWeaponCharacterInstance?
    private var equippedIdle: DuelWeaponClip?
    private var idleDriver: CADisplayLink?
    private var idleTick = 0
    private var lastIdleTime: CFTimeInterval?
    private var accumulatedIdleTime: CFTimeInterval = 0
    private(set) var yaw: Float = .pi
    static let defaultZoom: Float = 0.75
    private(set) var zoom: Float = DuelLobbySceneView.defaultZoom
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

    // Direct renderer fixtures may exercise historical exports. The production
    // representable always supplies its explicit source-character requirement.
    init(hero: DuelGame.Hero, requiresIntendedCharacter: Bool = false,
         verifiedIndex: DuelWeaponAssetIndex? = nil, preparedAutumnLobby: DuelStageAsset.PreparedAutumnLobby? = nil) {
        self.verifiedIndex = verifiedIndex
        self.requiresIntendedCharacter = requiresIntendedCharacter
        super.init(frame: .zero, options: nil)
        let sunlitSky = UIColor(red: 0.52, green: 0.58, blue: 0.64, alpha: 1)
        backgroundColor = UIColor(red: 0.045, green: 0.04, blue: 0.075, alpha: 1)
        antialiasingMode = .multisampling2X
        rendersContinuously = false; isPlaying = false; isUserInteractionEnabled = true
        isAccessibilityElement = false; accessibilityElementsHidden = true
        let world = SCNScene(); scene = world
        if let preparedAutumnLobby {
            stage = try? DuelStageAsset(preparedAutumnLobby: preparedAutumnLobby)
        } else if let url = DuelStageAsset.bundledURL(for: .autumnLobby) {
            stage = try? DuelStageAsset(url: url, kind: .autumnLobby)
        }
        if let stage {
            world.rootNode.addChildNode(stage.makeRoot())
        } else {
            backgroundColor = sunlitSky
            world.background.contents = sunlitSky
            world.fogColor = sunlitSky
            world.fogStartDistance = 11.0
            world.fogEndDistance = 44.0
            world.fogDensityExponent = 1.15
            if let preloaded = DuelEnvironmentAssetCache.preloadedStage {
                attachSanctuaryBackdrop(preloaded, to: world)
            } else {
                sanctuaryStageTask = Task { @MainActor [weak self] in
                    guard let model = await DuelEnvironmentAssetCache.loadStageAsync(),
                          let self, !Task.isCancelled, let liveScene = self.scene else { return }
                    self.attachSanctuaryBackdrop(model, to: liveScene)
                    self.setNeedsDisplay()
                }
            }
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
        if let envURL = DuelEnvironmentAssetCache.bundledHDRURL(named: "DuelEnv_Sunlit") {
            world.lightingEnvironment.contents = envURL
            world.lightingEnvironment.intensity = 1.15
        }
        if let cam = cameraNode?.camera {
            cam.wantsHDR = true
            cam.wantsExposureAdaptation = false
            cam.exposureOffset = -0.04
            cam.contrast = 0.14
            cam.saturation = 1.06
            cam.bloomIntensity = 0.28
            cam.bloomThreshold = 1.32
            cam.bloomBlurRadius = 5.5
            cam.vignettingPower = 1.15
            cam.vignettingIntensity = 0.36
            if stage == nil {
                cam.wantsDepthOfField = true
                cam.focusDistance = 5.0
                cam.fStop = 2.6
                cam.apertureBladeCount = 6
            }
        }
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 135; ambient.light?.color = UIColor(red: 0.72, green: 0.78, blue: 0.86, alpha: 1)
        world.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional
        key.light?.intensity = 1950; key.light?.color = UIColor(red: 1.0, green: 0.90, blue: 0.74, alpha: 1)
        if stage == nil {
            key.light?.castsShadow = true
            key.light?.shadowMode = .forward
            key.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
            key.light?.shadowSampleCount = 4
            key.light?.shadowRadius = 2.5
            key.light?.shadowBias = 2.0
            key.light?.shadowColor = UIColor(red: 0.04, green: 0.06, blue: 0.11, alpha: 0.54)
            key.light?.automaticallyAdjustsShadowProjection = false
            key.light?.orthographicScale = 5.2
            key.light?.zNear = 1.0
            key.light?.zFar = 22.0
            key.position = SCNVector3(2.5, 8.0, 6.0)
        }
        key.eulerAngles = SCNVector3(-0.58, -0.52, 0); world.rootNode.addChildNode(key)
        let rim = SCNNode(); rim.light = SCNLight(); rim.light?.type = .directional
        rim.light?.intensity = 1050; rim.light?.color = UIColor(red: 0.68, green: 0.86, blue: 1.0, alpha: 1)
        rim.eulerAngles = SCNVector3(-0.36, 2.55, 0); world.rootNode.addChildNode(rim)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .directional
        // Soft low ground-bounce fill keeps armor shadow side rich without flattening PBR metalness.
        fill.light?.intensity = 160; fill.light?.color = UIColor(red: 0.82, green: 0.78, blue: 0.72, alpha: 1)
        fill.eulerAngles = SCNVector3(0.45, 0.35, 0); world.rootNode.addChildNode(fill)
        for name in [UIScreen.didConnectNotification, UIScreen.didDisconnectNotification, UIScreen.modeDidChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(updateDisplayBudget), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(backgrounded),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foregrounded),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        select(hero)
    }

    private func attachSanctuaryBackdrop(_ model: GLTFModel, to world: SCNScene) {
        guard world.rootNode.childNode(withName: "duel.lobby.sanctuary", recursively: false) == nil else { return }
        let inst = model.instantiate()
        inst.root.name = "duel.lobby.sanctuary"
        inst.root.enumerateHierarchy { node, _ in
            let nm = (node.name ?? "").lowercased()
            node.castsShadow = nm.contains("ruinsstone") || nm.contains("brazieriron")
            if nm.contains("brazierembers") {
                for mat in node.geometry?.materials ?? [] {
                    mat.emission.intensity = 2.6
                }
            }
        }
        world.rootNode.addChildNode(inst.root)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        updateDisplayBudget()
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
        updateDisplayBudget()
        if window == nil { stopIdle() } else { startIdle() }
    }
    override var isHidden: Bool {
        didSet {
            guard isHidden != oldValue else { return }
            if isHidden { stopIdle() } else { startIdle() }
        }
    }
    @objc private func updateDisplayBudget() {
        guard scene != nil, let screen = window?.screen else { return }
        let casting = window?.windowScene?.session.role == .windowExternalDisplayNonInteractive ||
            UIScreen.screens.contains { $0.mirrored === screen }
        guard let budget = DuelDisplayRenderBudget(size: bounds.size,
            screenScale: screen.scale, casting: casting) else { return }
        if contentScaleFactor != budget.scale { contentScaleFactor = budget.scale }
        let aa: SCNAntialiasingMode = budget.samples == 1 ? .none : .multisampling2X
        if antialiasingMode != aa { antialiasingMode = aa }
    }
    @objc private func backgrounded() { stopIdle() }
    @objc private func foregrounded() { updateDisplayBudget(); startIdle() }
    private func startIdle() {
        guard !isHidden, window != nil, UIApplication.shared.applicationState == .active,
              (equippedActor != nil || cascadeurCharacter != nil), idleDriver == nil else { return }
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
        guard !isHidden, (equippedActor != nil && equippedIdle != nil) || cascadeurCharacter != nil else { return }
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
        if let cascadeur = cascadeurCharacter {
            idleTick = tick % 120
            cascadeur.applyShowroomIdle(progress: Float(idleTick) / 120.0)
            showroomFrameCount += 1
            setNeedsDisplay()
            return
        }
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
        guard let scene, hero != lastRequestedHero else { return }
        lastRequestedHero = hero
        guard hero != selectedHero else { return }

        // Prepare the new, fully posed scene node before touching the visible
        // character, its camera state or its idle driver. A missing profile,
        // damaged model or failed decode must leave the current portrait intact.
        var nextRoot: SCNNode?
        var nextWeaponAssets: DuelWeaponAssets?
        var nextEquippedActor: DuelWeaponCharacterInstance?
        var nextEquippedIdle: DuelWeaponClip?
        var nextOriginal: DuelOriginalRigAsset?
        var nextCascadeur: DuelCascadeurCharacterInstance?
        var nextCharacter: DuelCharacterAsset?

        if requiresIntendedCharacter ||
            (!ProcessInfo.processInfo.arguments.contains("-duel-legacy-controls") &&
             DuelWeaponAssets.catalogURL() != nil) {
            do {
                let assets: DuelWeaponAssets
                if let weaponAssets { assets = weaponAssets }
                else if let verifiedIndex { assets = try DuelWeaponAssets(verifiedIndex: verifiedIndex, purpose: .showroom) }
                else { assets = try DuelWeaponAssets(purpose: .showroom) }
                // Publish the verified roster even when the initial selection
                // is absent, so another ready person can still be selected.
                weaponAssets = assets
                catalogIdentity = DuelLobbyIdentitySnapshot(verifiedAssets: assets)
                guard !requiresIntendedCharacter ||
                        assets.localProfiles.contains(where: { $0.hero == hero && $0.isIntendedCharacter }) else { return }
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
            } catch {
                // character(for:) can discover a damaged GLB after the lighter
                // catalog stage. Publish that failure instead of leaving a
                // stale selectable identity and an endless preparation label.
                if let weaponAssets {
                    catalogIdentity = DuelLobbyIdentitySnapshot(verifiedAssets: weaponAssets)
                } else {
                    let reasons = Dictionary(uniqueKeysWithValues: DuelGame.Hero.allCases.map {
                        ($0, "大厅资源未能载入，请返回后重试")
                    })
                    catalogIdentity = DuelLobbyIdentitySnapshot(displayIdentities: [:], unavailableReasons: reasons)
                }
                return
            }
        } else if DuelCascadeurCharacterAsset.bundledURL(for: hero) != nil {
            cascadeurLoadTask?.cancel()
            cascadeurLoadTask = nil
            if let cached = DuelCascadeurCharacterAsset.cached(for: hero) {
                DuelProceduralVFXAssets.startPrewarm()
                let actor = DuelCascadeurCharacterInstance(cached)
                actor.applyShowroomIdle(progress: 0)
                actor.root.position = SCNVector3(4.7, 0.015, -0.35)
                actor.root.eulerAngles.y = 0
                nextRoot = actor.root
                nextCascadeur = actor
            } else {
                DuelProceduralVFXAssets.startPrewarm()
                cascadeurLoadTask = Task { @MainActor [weak self] in
                    guard let asset = await DuelCascadeurCharacterAsset.loadBundledAsync(for: hero),
                          let self, !Task.isCancelled, self.lastRequestedHero == hero,
                          let liveScene = self.scene else { return }
                    let actor = DuelCascadeurCharacterInstance(asset)
                    actor.applyShowroomIdle(progress: 0)
                    actor.root.position = SCNVector3(4.7, 0.015, -0.35)
                    actor.root.eulerAngles.y = 0
                    actor.root.name = "duel.lobby.character.\(hero.rawValue)"
                    self.stopIdle()
                    self.characterRoot?.removeFromParentNode()
                    self.characterRoot = actor.root
                    self.character = nil
                    self.originalCharacter = nil
                    self.cascadeurCharacter = actor
                    self.equippedActor = nil
                    self.equippedIdle = nil
                    self.selectedHero = hero
                    self.idleTick = 0
                    self.yaw = 0
                    self.zoom = Self.defaultZoom
                    self.updateCameraFraming()
                    liveScene.rootNode.addChildNode(actor.root)
                    self.startIdle()
                    self.setNeedsDisplay()
                }
                return
            }
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
        cascadeurCharacter = nextCascadeur
        equippedActor = nextEquippedActor
        equippedIdle = nextEquippedIdle
        weaponAssets = nextWeaponAssets
        if previousAssets !== nextWeaponAssets {
            catalogIdentity = nextWeaponAssets.map { DuelLobbyIdentitySnapshot(verifiedAssets: $0) }
        }
        if let actor = nextEquippedActor, actor.asset.profile.isSerpent {
            catalogIdentity?.displaysSerpentPersonalHead = actor.displaysSerpentPersonalHead
        }
        if let previousHero { previousAssets?.releaseCharacter(for: previousHero) }
        selectedHero = hero
        idleTick = 0; yaw = nextCascadeur != nil ? 0 : .pi; zoom = Self.defaultZoom
        updateCameraFraming()
        scene.rootNode.addChildNode(nextRoot)
        startIdle()
        setNeedsDisplay()
    }
    func shutdown() {
        // Detach resource-owning nodes even if SceneKit keeps an autoreleased
        // scene or renderer alive until the current event finishes.
        cascadeurLoadTask?.cancel()
        cascadeurLoadTask = nil
        sanctuaryStageTask?.cancel()
        sanctuaryStageTask = nil
        stopIdle()
        NotificationCenter.default.removeObserver(self)
        gestureRecognizers?.forEach { removeGestureRecognizer($0) }
        scene?.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        scene = nil; pointOfView = nil; stage = nil; character = nil; originalCharacter = nil; cascadeurCharacter = nil; characterRoot = nil; weaponAssets = nil; equippedActor = nil; equippedIdle = nil; cameraNode = nil
        catalogIdentity = nil
        visibleRegion = nil; framing = nil
        rendersContinuously = false; isPlaying = false
    }
}
