import SwiftUI
import SceneKit
import UIKit
import Darwin
import simd

struct DuelWorld: UIViewRepresentable {
    let session: DuelSession
    var preparation: DuelNetworkMatchPreparation? = nil
    func makeUIView(context: Context) -> DuelWorldView {
        #if DEBUG
        let source: DuelWorldView.CharacterSource = preparation?.permitsFixture == true ? .presentationFixture : .bundled
        #else
        let source: DuelWorldView.CharacterSource = .bundled
        #endif
        let view = DuelWorldView(session: session, characterSource: source)
        if let preparation { view.schedulePreparationAttachment(preparation) }
        return view
    }
    func updateUIView(_ view: DuelWorldView, context: Context) {}
    static func dismantleUIView(_ view: DuelWorldView, coordinator: ()) { view.shutdown() }
}

/// Authored personal characters plus procedural fallbacks. Assets live for one fight.
/// The offline clock advances simulation; external sessions only render supplied state.
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
    private(set) var verifiedEffectsRoot: SCNNode?
    private(set) var verifiedStageRoot: SCNNode?
    private(set) var opticalFramingFailure: DuelDisplayedSkinBounds.Failure?
    private var cameraBasePosition = SCNVector3(5, 3.6, 14)
    private(set) var combatCamera = DuelCombatCamera()
    private var opticalFOV = DuelCameraOpticalFOV()
    private var perspectiveDistance: Float = 7.7
    enum CharacterSource {
        case bundled, legacy, procedural
        #if DEBUG
        /// Asset-free renderer for synthetic external presentation tests only.
        /// Unlike procedural characters, this also bypasses source stage/effects.
        case presentationFixture
        #endif
    }
    private(set) var usesSyntheticPresentationResources = false
    private var bolts: [Int: SCNNode] = [:]
    private var hurtNodes: [SCNNode] = []
    private var attackNodes: [SCNNode] = []
    private var slamRing: SCNNode?
    private var ended = false
    private var sceneAssemblyFinished = false
    private var musicPreparingScene: SCNScene?
    private var musicPreparationID: UUID?
    private var musicPreparationFinished = false
    private var musicPreparedScene: SCNScene?
    private weak var musicStageRoot: SCNNode?

    private var hasSourceMusicResources: Bool {
        guard !ended, sceneAssemblyFinished, session.loadError == nil,
              stageAsset?.kind == .palace, let scene, pointOfView?.camera != nil,
              musicStageRoot?.parent === scene.rootNode, actors.count == session.game.fighters.count,
              actors.allSatisfy({ $0.root.parent === scene.rootNode }) else { return false }
        if session.setup.originalWeapons {
            return sourceEffects != nil && weaponEffects != nil &&
                session.game.fighters.enumerated().allSatisfy { index, fighter in
                    guard let character = weaponAssets[fighter.hero] else { return false }
                    return actors[index].hasAttachedWeapon(character)
                }
        }
        return session.game.fighters.allSatisfy {
            characterAssets[$0.hero] != nil || originalAssets[$0.hero] != nil
        }
    }
    var hasPreparedSourceMusicScene: Bool {
        guard hasSourceMusicResources, hasUsableMountedBounds, let scene else { return false }
        if session.driver == .externalAuthoritative {
            // Reuse the coordinator's real preparation receipt. A synthetic or
            // awaiting/failed mount must never acquire source battle music.
            return session.hasLiveVerifiedResources && hasVerifiedResourceIdentity &&
                preparationFinished && preparedRuntimeEffects && preparingScene === scene
        }
        return musicPreparedScene === scene
    }
    private func prepareSourceMusicIfMounted() {
        guard session.driver == .offline, hasSourceMusicResources, hasUsableMountedBounds,
              let scene, musicPreparingScene == nil, musicPreparedScene !== scene else { return }
        musicPreparingScene = scene
        let request = UUID(); musicPreparationID = request
        #if DEBUG
        if let testingMusicPrepare {
            testingMusicPrepare([scene]) { [weak self] success in
                self?.finishSourceMusicPreparation(request: request, success: success)
            }
            return
        }
        #endif
        // Only a Sendable request ID crosses the renderer callback. The exact
        // scene identity is retained and checked on the main actor.
        prepare([scene], completionHandler: { [weak self] success in
            Task { @MainActor [weak self] in
                self?.finishSourceMusicPreparation(request: request, success: success)
            }
        })
    }
    private func finishSourceMusicPreparation(request: UUID, success: Bool) {
        guard !ended, musicPreparationID == request, !musicPreparationFinished else { return }
        musicPreparationFinished = true
        guard let prepared = musicPreparingScene, scene === prepared else { return }
        // Keep the attempted identity on failure: later layouts must not spin
        // up preparation retries. Detachment keeps readiness false even if the
        // retained scene completes successfully while offscreen.
        if success && hasSourceMusicResources { musicPreparedScene = prepared }
        session.refreshSourceMusicReadiness(from: self)
    }

    enum PreparationFailure: Error, Equatable {
        case invalidSession, alreadyRequested, rendererFailed, detached, replaced
    }
    /// Proves this mounted SCNView prepared its scene and, for equipped matches,
    /// the effect owners' complete shader/material templates. It is not a frame-
    /// rate promise. The combined owner separately checks retained identities.
    struct PreparationReceipt: Equatable {
        let owner: UUID
        let initialScenePrepared: Bool
        let runtimeEffectVariantsPrepared: Bool
    }
    typealias PreparationCompletion = @MainActor (Result<PreparationReceipt, PreparationFailure>) -> Void
    private var preparationOwner: UUID?
    private var preparationCompletion: PreparationCompletion?
    private var preparationInvalidated: (@MainActor (PreparationFailure) -> Void)?
    private var preparedMountChanged: (@MainActor () -> Void)?
    // Only the SwiftUI/UIKit boundary is deferred. Direct preparation APIs keep
    // their synchronous observer/revalidation contract for owners and tests.
    private weak var pendingUIAttachment: DuelNetworkMatchPreparation?
    private var uiAttachmentQueued = false
    private var defersMountUpdates = false
    func schedulePreparationAttachment(_ owner: DuelNetworkMatchPreparation) {
        guard !ended else { return }
        pendingUIAttachment = owner
        defersMountUpdates = true
        retryPreparationAttachment()
    }
    private func retryPreparationAttachment() {
        guard !ended, !uiAttachmentQueued, let owner = pendingUIAttachment else { return }
        uiAttachmentQueued = true
        DispatchQueue.main.async { [weak self, weak owner] in
            guard let self else { return }
            self.uiAttachmentQueued = false
            guard !self.ended, let owner, self.pendingUIAttachment === owner else { return }
            // The first update can precede mounting. Keep the pending owner;
            // didMoveToWindow/layout will retry rather than losing first attach.
            guard self.hasUsableMountedBounds else { return }
            self.pendingUIAttachment = nil
            owner.attach(self)
        }
    }
    #if DEBUG
    var preparationPhaseDescription: String {
        "requested=\(preparationOwner != nil), started=\(preparingScene != nil), finished=\(preparationFinished), " +
        "actual=\(usedActualScenePreparation), variants=\(preparedRuntimeEffects), " +
        "window=\(window != nil), bounds=\(bounds.size), queued=\(uiAttachmentQueued), pending=\(pendingUIAttachment != nil)"
    }
    #endif
    private var preparedRuntimeEffects = false
    private var preparingScene: SCNScene?
    private var preparationMounted = false
    private var preparationFinished = false
    private(set) var usedActualScenePreparation = false
    #if DEBUG
    private(set) var attemptedBundledStageLoad = false
    typealias TestPrepare = @MainActor ([Any], @escaping @MainActor (Bool) -> Void) -> Void
    var testingPrepare: TestPrepare?
    var testingMusicPrepare: TestPrepare?
    func installPreparationEffectFixtures() throws {
        guard !ended, usesSyntheticPresentationResources, session.isPresentationFixture,
              preparationOwner == nil, session.committedConfiguration == nil,
              session.awaitingNetworkPreparation, let scene else { throw PreparationFailure.invalidSession }
        sourceEffects = DuelSourceEffects.preparationFixture(root: scene.rootNode)
        weaponEffects = DuelWeaponEffects.preparationFixture(root: scene.rootNode)
    }
    #endif

    func represents(_ candidate: DuelSession) -> Bool { session === candidate }

    /// Recheck actual actor instances and the same stage/effect objects, not
    /// just hero labels, URLs, fingerprints or earlier readiness flags.
    var hasVerifiedResourceIdentity: Bool {
        guard !ended, session.hasLiveVerifiedResources, let prepared = session.preparedResources,
              let scene, let stageAsset, stageAsset === prepared.stage,
              let verifiedStageRoot, verifiedStageRoot.parent === scene.rootNode,
              let verifiedEffectsRoot, verifiedEffectsRoot === prepared.effectsRoot,
              verifiedEffectsRoot.parent === scene.rootNode,
              sourceEffects === prepared.sourceEffects, weaponEffects === prepared.weaponEffects,
              weaponEffects?.hasLiveContainer(attachedTo: verifiedEffectsRoot) == true,
              actors.count == 2, weaponAssets.count == Set(session.game.fighters.map(\.hero)).count else { return false }
        return session.game.fighters.enumerated().allSatisfy { index, fighter in
            guard let character = prepared.loadedCharacter(for: fighter.hero) else { return false }
            return weaponAssets[fighter.hero] === character && actors[index].hasAttachedWeapon(character) &&
                actors[index].root.parent === scene.rootNode
        }
    }

    func prepareNetworkScene(owner: UUID,
                             invalidated: (@MainActor (PreparationFailure) -> Void)? = nil,
                             changed: (@MainActor () -> Void)? = nil,
                             completion: @escaping PreparationCompletion) throws {
        guard !ended, session.awaitingNetworkPreparation else { throw PreparationFailure.invalidSession }
        guard preparationOwner == nil else { throw PreparationFailure.alreadyRequested }
        preparationOwner = owner; preparationCompletion = completion; preparationInvalidated = invalidated
        preparedMountChanged = changed
        prepareNetworkSceneIfMounted()
    }

    func hasPreparedSceneIdentity(owner: UUID) -> Bool {
        !ended && preparationOwner == owner && preparationFinished &&
            preparingScene != nil && scene === preparingScene
    }
    var hasUsableMountedBounds: Bool {
        window != nil && bounds.width.isFinite && bounds.height.isFinite && bounds.width > 0 && bounds.height > 0
    }
    private func preparationMountChanged() {
        if !ended, preparationFinished, preparingScene != nil, scene !== preparingScene {
            failNetworkPreparation(.replaced)
            return
        }
        // Layout/window callbacks run inside SwiftUI updates. Observe the settled
        // mount on the next main-queue turn, but retain synchronous invalidation above.
        guard defersMountUpdates else { preparedMountChanged?(); return }
        let owner = preparationOwner
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.ended, self.preparationOwner == owner else { return }
            self.preparedMountChanged?()
        }
    }

    private func prepareNetworkSceneIfMounted() {
        guard !ended, let owner = preparationOwner, !preparationFinished else { return }
        if window != nil { preparationMounted = true }
        guard preparingScene == nil, window != nil,
              bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return }
        guard session.awaitingNetworkPreparation, let scene, pointOfView?.camera != nil,
              !session.usesVerifiedPreparedResources || hasVerifiedResourceIdentity else {
            finishNetworkPreparation(owner: owner, success: false)
            return
        }
        var objects: [Any] = [scene]
        if session.setup.originalWeapons || sourceEffects != nil || weaponEffects != nil {
            guard let sourceEffects, let weaponEffects else { failNetworkPreparation(.rendererFailed); return }
            let contacts = sourceEffects.preparationObjects(), trails = weaponEffects.preparationObjects()
            guard !contacts.isEmpty, !trails.isEmpty else { failNetworkPreparation(.rendererFailed); return }
            objects += contacts; objects += trails
            preparedRuntimeEffects = true
        }
        preparingScene = scene
        #if DEBUG
        if let testingPrepare {
            testingPrepare(objects) { [weak self] success in
                self?.finishNetworkPreparation(owner: owner, success: success)
            }
            return
        }
        #endif
        // SceneKit may complete on a rendering thread. UIKit/session ownership,
        // token checks and the one-shot callback always remain on MainActor.
        usedActualScenePreparation = true
        prepare(objects, completionHandler: { [weak self] success in
            Task { @MainActor [weak self] in
                self?.finishNetworkPreparation(owner: owner, success: success)
            }
        })
    }

    private func finishNetworkPreparation(owner: UUID, success: Bool) {
        guard !ended, preparationOwner == owner, !preparationFinished else { return }
        guard window != nil, bounds.width > 0, bounds.height > 0,
              session.awaitingNetworkPreparation, let preparingScene, scene === preparingScene,
              !session.usesVerifiedPreparedResources || hasVerifiedResourceIdentity else {
            failNetworkPreparation(.replaced)
            return
        }
        guard success else { failNetworkPreparation(.rendererFailed); return }
        preparationFinished = true
        let completion = preparationCompletion; preparationCompletion = nil
        // Keep the prepared scene identity until teardown. Controls may still
        // be waiting for layout; later combined readiness must revalidate it.
        completion?(.success(.init(owner: owner, initialScenePrepared: true,
                                   runtimeEffectVariantsPrepared: preparedRuntimeEffects)))
        session.refreshSourceMusicReadiness(from: self)
    }

    private func failNetworkPreparation(_ failure: PreparationFailure) {
        guard !ended, preparationOwner != nil else { return }
        let completion = preparationCompletion
        preparationCompletion = nil; preparationFinished = true
        shutdown(preparationFailure: failure)
        completion?(.failure(failure))
    }

    init(session: DuelSession, characterSource: CharacterSource = .bundled) {
        self.session = session
        super.init(frame: .zero, options: nil)
        #if DEBUG
        if characterSource == .presentationFixture {
            // Never turn a real/verified match, even a closed one, into a
            // synthetic fallback. Reject before touching callbacks or assets.
            guard session.isPresentationFixture, session.awaitingNetworkPreparation,
                  session.committedConfiguration == nil, session.weaponAssets == nil,
                  session.preparedResources == nil, !session.usesVerifiedPreparedResources else {
                ended = true
                return
            }
            usesSyntheticPresentationResources = true
        }
        #endif
        if session.usesVerifiedPreparedResources {
            guard characterSource == .bundled, session.claimPreparedWorld(self) else {
                // A rejected duplicate never touches the first renderer's roots,
                // callbacks or assets. It cannot restart or reload a closed owner.
                ended = true
                return
            }
        }
        if session.driver == .offline, !session.claimOfflineWorld(self) {
            ended = true
            return
        }
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
        if characterSource != .procedural && !usesSyntheticPresentationResources {
            for hero in Set(session.game.fighters.map(\.hero)) where hero != .gale {
                if session.setup.originalWeapons {
                    do {
                        guard let assets = session.weaponAssets else { throw DuelWeaponAssets.AssetError.missing }
                        if session.usesVerifiedPreparedResources {
                            guard let character = session.preparedResources?.loadedCharacter(for: hero),
                                  assets.loadedCharacter(for: hero) === character else {
                                throw DuelWeaponAssets.AssetError.missing
                            }
                            weaponAssets[hero] = character
                        } else {
                            weaponAssets[hero] = try assets.character(for: hero)
                        }
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
            guard let self, !self.ended else { return }
            self.sourceEffects?.setPaused(paused)
            self.weaponEffects?.setPaused(paused)
            if paused { self.stopClock() } else { self.startClock() }
        }
        if session.setup.originalWeapons && !usesSyntheticPresentationResources {
            if session.usesVerifiedPreparedResources {
                if let prepared = session.preparedResources, let root = prepared.effectsRoot,
                   let source = prepared.sourceEffects, let weapon = prepared.weaponEffects {
                    verifiedEffectsRoot = root; world.rootNode.addChildNode(root)
                    sourceEffects = source; weaponEffects = weapon
                } else { session.characterFailed() }
            } else if let directory = session.weaponAssets?.directory {
                do {
                    sourceEffects = try DuelSourceEffects(root: world.rootNode, directory: directory)
                    weaponEffects = try DuelWeaponEffects(root: world.rootNode, directory: directory)
                }
                catch { session.characterFailed() }
            }
        }
        session.didSimulateStep = { [weak self] game, tick in self?.consumeFeedback(game, tick: tick) }
        consumeFeedback(session.game, tick: 0)
        session.didReset = { [weak self] in
            guard let self, !self.ended else { return }
            self.sourceEffects?.reset(); self.weaponEffects?.reset()
            self.combatCamera = DuelCombatCamera()
            // A restarted bout can reuse frame 0. Clear the previous lens
            // before rendering its opening pose or the old weapon-swing FOV
            // can persist and make both fighters appear too small.
            self.opticalFOV.reset()
            self.consumeFeedback(self.session.game, tick: 0)
            self.drawState()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        drawState()
        sceneAssemblyFinished = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard !ended else { return }
        retryPreparationAttachment()
        if window == nil {
            if preparationOwner != nil && preparationMounted {
                failNetworkPreparation(.detached)
                return
            }
            stopClock(); session.clearInput()
            session.updateCharacterOcclusion([], from: self)
        } else {
            prepareNetworkSceneIfMounted()
            preparationMountChanged()
            if !session.paused { startClock() }
        }
        prepareSourceMusicIfMounted()
        session.refreshSourceMusicReadiness(from: self)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        retryPreparationAttachment()
        updateCameraFraming()
        prepareNetworkSceneIfMounted()
        prepareSourceMusicIfMounted()
        session.refreshSourceMusicReadiness(from: self)
        preparationMountChanged()
    }
    /// Use the same projection during layout and rendering. A rotation-safe
    /// layout value must not be replaced by a narrow FOV on the next frame.
    private func updateCameraFraming() {
        // UIKit can deliver layout after dismantling. Do not ask a closed
        // SceneKit renderer for a camera (or mutate a default camera it exposes).
        guard !ended, scene != nil, bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0, let eye = pointOfView,
              let camera = eye.camera else {
            session.updateCharacterOcclusion([], from: self)
            return
        }
        let aspect = Double(bounds.width / bounds.height)
        guard aspect.isFinite, aspect > 0 else {
            opticalFramingFailure = .invalidTransform
            session.updateCharacterOcclusion([], from: self)
            return
        }
        let framing = DuelCameraFraming(aspect: aspect, separation: combatCamera.separation)
        let trackedX = Float(combatCamera.centerX)
        var position = cameraBasePosition
        position.x = trackedX
        if stageAsset != nil {
            perspectiveDistance = Float(framing.perspectiveDistance)
            position.z = perspectiveDistance
        }
        eye.position = position
        eye.look(at: SCNVector3(trackedX, stageAsset != nil ? 1.2 : 1.0, 0))
        if !UIAccessibility.isReduceMotionEnabled {
            eye.position.x += Float(combatCamera.impactOffsetX)
            eye.position.y += Float(combatCamera.impactOffsetY)
            if let hold = session.game.grapple {
                let release = DuelGame.Grapple.takedownTicks + DuelGame.Grapple.holdTicks
                let elapsed = hold.age >= release ? hold.age - release : hold.age - DuelGame.Grapple.takedownTicks
                if (0..<18).contains(elapsed) {
                    eye.position.y += sin(Float(elapsed) * 1.8) * 0.035 * (1 - Float(elapsed) / 18)
                }
            }
        }
        opticalFramingFailure = nil
        if stageAsset != nil {
            camera.fieldOfView = CGFloat(framing.verticalFieldOfView)
            if session.setup.originalWeapons {
                do {
                    let points = try actors.flatMap { try $0.displayedCameraPoints(camera: eye) }
                    // Reserve eight UIKit points on the shorter viewport axis,
                    // conservatively at least that much on the longer axis.
                    let shortSide = Double(min(bounds.width, bounds.height))
                    let inset = 1 - 2 * min(8, shortSide * 0.1) / shortSide
                    let requiredFOV = try DuelDisplayedSkinBounds.verticalFOV(
                        points: points, aspect: aspect, minimum: framing.verticalFieldOfView,
                        near: camera.zNear, inset: inset)
                    // Fit the entire measured pose immediately. Contract only
                    // once per simulation frame, so weapon swings do not cause
                    // abrupt lens pumping or shrink on repeated layout calls.
                    camera.fieldOfView = CGFloat(opticalFOV.consume(
                        required: requiredFOV, frame: session.game.frame, aspect: aspect))
                    // Reuse the same conservative points and the final installed FOV.
                    // This does not change the camera, actor scale or touch geometry.
                    let rectangles = DuelDisplayedSkinBounds.artworkRectangles(
                        points: points, size: bounds.size, verticalFieldOfView: Double(camera.fieldOfView))
                    session.updateCharacterOcclusion(rectangles, from: self)
                } catch {
                    opticalFOV.reset()
                    opticalFramingFailure = (error as? DuelDisplayedSkinBounds.Failure) ?? .unsupportedGeometry
                    session.updateCharacterOcclusion([], from: self)
                }
            } else {
                opticalFOV.reset()
            }
        } else {
            opticalFOV.reset()
            camera.orthographicScale = framing.orthographicScale
        }
    }

    @objc private func interrupted() { guard !ended else { return }; session.pause() }
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
    func shutdown(preparationFailure: PreparationFailure = .replaced) {
        guard !ended else { return }
        ended = true
        pendingUIAttachment = nil; uiAttachmentQueued = false
        musicPreparationID = nil; musicPreparationFinished = true
        musicPreparingScene = nil; musicPreparedScene = nil; musicStageRoot = nil
        let invalidated = preparationInvalidated; preparationInvalidated = nil
        preparationOwner = nil; preparationCompletion = nil; preparingScene = nil; preparedMountChanged = nil
        preparationFinished = true
        #if DEBUG
        testingPrepare = nil; testingMusicPrepare = nil
        #endif
        stopClock()
        session.renderPause = nil; session.didSimulateStep = nil; session.didReset = nil
        if session.driver == .offline {
            session.releaseOfflineWorld(self)
            session.clearInput()
        }
        sourceEffects?.shutdown(); sourceEffects = nil
        weaponEffects?.shutdown(); weaponEffects = nil
        NotificationCenter.default.removeObserver(self)
        // Break application ownership before clearing the SCNView reference.
        // Renderer/UIKit work may still finish after this method returns.
        // Disconnect the scene first and clear its camera last, then flush
        // pending node detachments before dropping the asset owners.
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        scene?.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        scene = nil
        pointOfView = nil
        SCNTransaction.commit()
        SCNTransaction.flush()
        verifiedEffectsRoot = nil; verifiedStageRoot = nil
        actors.removeAll(); characterAsset = nil; characterAssets.removeAll(); originalAssets.removeAll(); weaponAssets.removeAll(); stageAsset = nil; bolts.removeAll(); hurtNodes.removeAll(); attackNodes.removeAll(); slamRing = nil
        // Report the renderer's precise reason after releasing its resources,
        // before the terminal session signal can report generic invalidation.
        session.releaseSourceMusicWorld(self)
        invalidated?(preparationFailure)
        if session.driver == .externalAuthoritative { session.pause() }
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
        guard !ended, scene != nil else { return }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        for i in 0..<actors.count {
            actors[i].pose(session.game.fighters[i], frame: session.animationTick, grapple: session.game.grapple, index: i, phase: session.game.phase, shadow: session.game.weaponFight?.shadowVisual(i))
            place(hurtNodes[i], box: session.game.hurtBox(i), visible: session.showBoxes && session.game.fighters[i].knockdown == 0 && session.game.grapple == nil)
            if let box = session.game.attackBox(i) { place(attackNodes[i], box: box, visible: session.showBoxes) }
            else { attackNodes[i].isHidden = true }
        }
        if let hold = session.game.grapple {
            actors[hold.attacker].connectWrist(to: actors[1 - hold.attacker], hold: hold)
        }
        slamRing?.isHidden = true
        // Read-only sampling: repeated draws, layout, and skipped display
        // frames cannot speed up tracking or drain a confirmed impact.
        if let hold = session.game.grapple {
            let release = DuelGame.Grapple.takedownTicks + DuelGame.Grapple.holdTicks
            let elapsed = hold.age >= release ? hold.age - release : hold.age - DuelGame.Grapple.takedownTicks
            if (0..<18).contains(elapsed), let ring = slamRing {
                let t = Float(elapsed) / 18, scale = 0.5 + 2.0 * t
                ring.isHidden = false; ring.opacity = CGFloat(1 - t)
                ring.position = SCNVector3(Float(session.game.fighters[1 - hold.attacker].x) / 1000, 0.025, 0)
                ring.scale = SCNVector3(scale, 1, scale)
            }
        }
        updateCameraFraming()
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
        guard !ended, game.fighters.count == 2 else { return }
        let impacts = game.weaponFight?.contacts.map { contact in
            DuelCombatCamera.Impact(kind: contact.kind == .block ? .block : contact.heavy ? .heavy : .light,
                                    direction: contact.direction)
        } ?? []
        combatCamera.consume(frame: game.frame, animationTick: tick,
                             firstX: Double(game.fighters[0].x) / 1000,
                             secondX: Double(game.fighters[1].x) / 1000, impacts: impacts)
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
        weaponEffects?.consumeStep(poses: Self.weaponEffectPoses(fight, tick: tick), animationTick: tick)
    }
    /// Read-only adapter shared by native presentation verification.
    static func weaponEffectPoses(_ fight: DuelWeaponFight, tick: Int) -> [DuelWeaponEffects.Pose] {
        fight.fighters.enumerated().compactMap { index, fighter in
            guard let pose = fighter.weaponPose, let clip = fight.profiles[index].clip(named: pose.clip) else { return nil }
            let profile = fight.profiles[index], tracks = clip.tracks
            func world(_ value: DuelWeaponPoint) -> SCNVector3 {
                SCNVector3(Float(fighter.x) / 1000 + Float(value.x) * Float(fighter.facing),
                           Float(value.y + pose.groundLift), Float(value.z) * Float(fighter.facing))
            }
            let shadow = fight.shadowVisual(index)
            let endpoints: [DuelWeaponEffects.Endpoints] = profile.activeWeaponSides.map { side in
                if side == "right", let base = shadow?.weaponBase, let tip = shadow?.weaponTip {
                    return .init(slot: 1,
                                 base: SCNVector3(Float(base.x), Float(base.y), Float(base.z)),
                                 tip: SCNVector3(Float(tip.x), Float(tip.y), Float(tip.z)))
                }
                return .init(slot: side == "left" ? 0 : 1,
                      base: world(tracks.sample(side == "left" ? tracks.weaponBaseL : tracks.weaponBaseR, phase: pose.phase)),
                      tip: world(tracks.sample(side == "left" ? tracks.weaponTipL : tracks.weaponTipR, phase: pose.phase)))
            }
            return .init(fighterID: index, family: profile.isKatana ? .katana : .dualHammers,
                         // Shadow body time is rescaled source time, not action time.
                         // Keep one ribbon through outbound, apex and return.
                         motionID: fight.weaponTrailIsActive(index)
                            ? (shadow != nil ? "shadow:\(index):\(pose.clip)" : "\(pose.clip):\(tick - pose.tick)") : nil,
                         isShadow: fight.shadowIsActive(index), endpoints: endpoints)
        }
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
    private func installStage(_ asset: DuelStageAsset, in root: SCNNode) {
        stageAsset = asset
        let stageRoot = asset.makeRoot()
        musicStageRoot = stageRoot
        if session.usesVerifiedPreparedResources { verifiedStageRoot = stageRoot }
        root.addChildNode(stageRoot)
        cameraBasePosition = SCNVector3(5, 2, 7.7)
        pointOfView?.camera?.usesOrthographicProjection = false
        pointOfView?.camera?.projectionDirection = .vertical
        pointOfView?.camera?.fieldOfView = 35
        pointOfView?.camera?.zFar = 350
        pointOfView?.position = cameraBasePosition
        pointOfView?.look(at: SCNVector3(5, 1.2, 0))
    }
    private func buildStage(_ root: SCNNode) {
        #if DEBUG
        if usesSyntheticPresentationResources {
            let fixture = SCNNode()
            fixture.name = "duel.stage.presentation-fixture"
            buildProceduralStage(fixture)
            root.addChildNode(fixture)
            return
        }
        #endif
        if session.usesVerifiedPreparedResources {
            guard let asset = session.preparedResources?.stage else { session.characterFailed(); return }
            installStage(asset, in: root)
            return
        }
        #if DEBUG
        attemptedBundledStageLoad = true
        #endif
        if let url = DuelStageAsset.bundledURL, let asset = try? DuelStageAsset(url: url) {
            installStage(asset, in: root)
            return
        }
        if session.committedConfiguration != nil {
            // An external match must not silently replace a missing/corrupt
            // verified arena with the offline laboratory floor.
            session.characterFailed()
            return
        }
        buildProceduralStage(root)
    }
    private func buildProceduralStage(_ root: SCNNode) {
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
    func hasAttachedWeapon(_ asset: DuelWeaponCharacterAsset) -> Bool {
        guard let weapon else { return false }
        return weapon.asset === asset && weapon.instance.root.parent === root
    }
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
    func displayedCameraPoints(camera: SCNNode) throws -> [SIMD3<Float>] {
        guard !root.isHidden else { return [] }
        guard let weapon else { throw DuelDisplayedSkinBounds.Failure.unsupportedGeometry }
        if let failure = weapon.displayedBoundsFailure { throw failure }
        guard let bounds = weapon.displayedBounds else { throw DuelDisplayedSkinBounds.Failure.unsupportedGeometry }
        return try bounds.cameraPoints(camera: camera)
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
    func pose(_ fighter: DuelGame.Fighter, frame: Int, grapple: DuelGame.Grapple?, index: Int, phase: DuelGame.Phase, shadow: DuelShadowVisual? = nil) {
        if let weapon {
            weapon.pose(fighter, root: root, shadow: shadow); shield.isHidden = true
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


