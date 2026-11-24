import SwiftUI
import SceneKit
import UIKit
import Darwin
import simd

/// An offline match already has a display link. Several main-queue turns before
/// its next callback represent one opportunity to obtain the initial drawable.
struct DuelInitialSurfacePresentation {
    enum Action: Equatable { case request, waitForDisplay, exhausted }
    private(set) var attempts = 0
    private var lastOfflineFrame: Int?

    func action(offlineFrame: Int?) -> Action {
        if let offlineFrame {
            // The swap chain can be empty across rotation or foregrounding.
            // Retry on the existing clock until Metal submits or reports an error.
            return lastOfflineFrame == offlineFrame ? .waitForDisplay : .request
        }
        return attempts < 3 ? .request : .exhausted
    }

    mutating func didRequest(offlineFrame: Int?) {
        attempts += 1
        lastOfflineFrame = offlineFrame
    }
}

struct DuelWorld: UIViewRepresentable {
    let session: DuelSession
    var preparation: DuelNetworkMatchPreparation? = nil
    func makeUIView(context: Context) -> DuelTelevisionHostView {
        #if DEBUG
        let source: DuelWorldView.CharacterSource = preparation?.permitsFixture == true
            ? .presentationFixture
            : (session.setup.originalWeapons ? .bundled : .procedural)
        #else
        let source: DuelWorldView.CharacterSource = session.setup.originalWeapons ? .bundled : .procedural
        #endif
        let view = DuelWorldView(session: session, characterSource: source)
        if let preparation { view.schedulePreparationAttachment(preparation) }
        return DuelTelevisionHostView(world: view, session: session)
    }
    func updateUIView(_ view: DuelTelevisionHostView, context: Context) {}
    static func dismantleUIView(_ view: DuelTelevisionHostView, coordinator: ()) { view.shutdown() }
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
    private var cpuSamples: [(simulation: Double, drawing: Double)] = []
    private var frozenStepCount = 0
    private var actors: [DuelActor] = []
    private(set) var characterAsset: DuelCharacterAsset?
    private var characterAssets: [DuelGame.Hero: DuelCharacterAsset] = [:]
    private(set) var originalAssets: [DuelGame.Hero: DuelOriginalRigAsset] = [:]
    private(set) var weaponAssets: [DuelGame.Hero: DuelWeaponCharacterAsset] = [:]
    private var cascadeurAssets: [DuelGame.Hero: DuelCascadeurCharacterAsset] = [:]
    private var shogunCompanions: [Int: DuelShogunCompanionNode] = [:]
    private var spiritWolves: [Int: DuelSpiritWolfNode] = [:]
    private var spiritOwls: [Int: DuelSpiritOwlNode] = [:]
    private var stigmataHalos: [Int: SCNNode] = [:]
    private var legionChains: [Int: DuelLegionChainNode] = [:]
    private var monkeyPillars: [Int: DuelMonkeyPillarNode] = [:]
    private var hitSpark: SCNNode?
    private var hitSparkAge = 99
    private var originalVFX: DuelOriginalVFX?
    private(set) var sourceEffects: DuelSourceEffects?
    private(set) var weaponEffects: DuelWeaponEffects?
    private var panguDiagnostics: DuelPanguDiagnostics?
    private var triadSummons: DuelTriadSummonRenderer?
    private var erlangCompanions: DuelErlangCompanionRenderer?
    private var serpentBottles: DuelSerpentBottleRenderer?
    private var erlangHoundEffects: DuelErlangHoundEffects?
    private var erlangStompEffects: DuelErlangStompEffects?
    private var erlangSwordEffects: DuelErlangSwordEffects?
    private var erlangSkillEffects: DuelErlangSkillEffects?
    private var triadSourceEffects: DuelTriadSourceEffects?
    private var triadSourceMorph: DuelTriadSourceMorph.Binding?
    private var triadMorphOwner: Int?
    private var triadMorphTrigger: DuelTriadSourceMorphAssets.Trigger?
    private var triadMorphRequested = false
    var sourceMorphProgress: Float? { triadSourceMorph?.progress }
    var sourceMorphIsComplete: Bool { triadSourceMorph?.isComplete == true }
    var sourceProjectedShadowIsInstalled: Bool { triadRenderSurface?.projectedShadow != nil }
    private(set) var triadMetalRenderer: DuelTriadMetalRenderer?
    private(set) var triadRenderSurface: DuelTriadRenderSurface?
    private var triadSurfaceFrameDriver: DuelTriadSurfaceFrameDriver?
    /// Private acceptance diagnostics retain source compiler/runtime errors.
    /// They are not rendered in the product or written to public logs.
    private(set) var triadPreparationFailure: String?
    var activeSourceEffectIDs: [String] { triadSourceEffects?.activeSourceEffectIDs ?? [] }
    #if DEBUG
    /// Native A/B capture only; production always prefers verified source skins.
    var sourceWeaponSkinsEnabled = true
    #else
    private let sourceWeaponSkinsEnabled = true
    #endif
    private(set) var stageAsset: DuelStageAsset?
    private(set) var verifiedEffectsRoot: SCNNode?
    private(set) var verifiedStageRoot: SCNNode?
    private(set) var opticalFramingFailure: DuelDisplayedSkinBounds.Failure?
    private var cameraBasePosition = SCNVector3(5, 3.6, 14)
    private(set) var combatCamera = DuelCombatCamera()
    private var opticalFOV = DuelCameraOpticalFOV()
    private var cameraPoints: [SIMD3<Float>] = []
    private var perspectiveDistance: Float = 7.7
    private var dramaticZoomTicks = 0
    private var dramaticZoomDuration = 1
    private var dramaticFocusX: Float = 5.0
    private var dramaticFocusY: Float = 1.25
    private var slowMoTicks = 0
    private var slowMoSkipFlip = false
    private var smoothedShadowCameraZ: Float = 5.45
    private var shadowCameraInitialized = false
    private var atmosphereShadowBlend: Float = 0
    private var atmosphereLightBlend: Float = 0
    private var atmosphereFlameBlend: Float = 0
    private var ambientLightNode: SCNNode?
    private var keyLightNode: SCNNode?
    private var rimLightNode: SCNNode?
    private var fillLightNode: SCNNode?
    private var sunbeamNodes: [SCNNode] = []
    private var sunlitEnvURL: URL?
    private var shadowEnvURL: URL?
    private var activeShadowEnv = false
    private var isCastingDisplay = false
    private var isShadowArenaScene = false
    private var lastAudioAttackKeys: [String?] = [nil, nil]
    private var lastWarnAttackKeys: [String?] = [nil, nil]
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
    private var fighterShadowDiscs: [SCNNode] = []
    private var ended = false
    private var sceneAssemblyFinished = false
    private var musicPreparingScene: SCNScene?
    private var musicPreparationID: UUID?
    private var musicPreparationFinished = false
    private var musicPreparedScene: SCNScene?
    private weak var musicStageRoot: SCNNode?
    private struct SourcePreparationIdentity: Equatable {
        let scene: ObjectIdentifier
        let surface: ObjectIdentifier
        let renderer: ObjectIdentifier
    }
    private var firstCommittedSourceIdentity: SourcePreparationIdentity?
    private var pendingInitialSourcePresentation: SourcePreparationIdentity?
    private var pendingPreparationAfterCommit: SourcePreparationIdentity?
    private var initialSourcePresentationIdentity: SourcePreparationIdentity?
    private var initialSourcePresentation = DuelInitialSurfacePresentation()

    private var offlinePresentationFrame: Int? {
        session.driver == .offline ? clockCallbacks : nil
    }

    private func sourcePreparationIdentity(scene: SCNScene,
        surface: DuelTriadRenderSurface) -> SourcePreparationIdentity {
        .init(scene: ObjectIdentifier(scene), surface: ObjectIdentifier(surface),
              renderer: ObjectIdentifier(surface.sceneRenderer))
    }

    /// Let the original source pass establish its render state before its
    /// asynchronous SceneKit preparation. A request to draw is not a commit.
    /// Invalid renderer identity still reaches the existing fail-closed helper.
    private func sourcePreparationMayStart(scene: SCNScene) -> Bool {
        guard let surface = triadRenderSurface else { return true }
        guard surface.sceneRenderer.scene === scene else { return true }
        let identity = sourcePreparationIdentity(scene: scene, surface: surface)
        if firstCommittedSourceIdentity == identity { return true }
        guard !ended, sceneAssemblyFinished, hasUsableMountedBounds,
              pendingInitialSourcePresentation != identity else { return false }
        if initialSourcePresentationIdentity != identity {
            initialSourcePresentationIdentity = identity
            initialSourcePresentation = DuelInitialSurfacePresentation()
        }
        switch initialSourcePresentation.action(offlineFrame: offlinePresentationFrame) {
        case .waitForDisplay: return false
        case .exhausted:
            guard UIApplication.shared.applicationState == .active, session.loadError == nil else { return false }
            failInitialSourcePresentation("Original source Surface did not commit within three mounted presentation attempts")
            return false
        case .request: break
        }
        pendingInitialSourcePresentation = identity
        #if DEBUG
        sourcePreparationPresentationSchedules += 1
        #endif
        DispatchQueue.main.async { [weak self, weak surface] in
            guard let self, let surface, !self.ended,
                  self.pendingInitialSourcePresentation == identity else { return }
            self.pendingInitialSourcePresentation = nil
            guard self.firstCommittedSourceIdentity != identity,
                  self.triadRenderSurface === surface, let current = self.scene,
                  surface.sceneRenderer.scene === current,
                  self.sourcePreparationIdentity(scene: current, surface: surface) == identity,
                  self.sceneAssemblyFinished, self.hasUsableMountedBounds,
                  UIApplication.shared.applicationState == .active,
                  self.session.loadError == nil, let frameDriver = self.triadSurfaceFrameDriver else { return }
            self.initialSourcePresentation.didRequest(offlineFrame: self.offlinePresentationFrame)
            #if DEBUG
            self.sourcePreparationPresentationAttempts += 1
            #endif
            // A pending network match is paused until its preparation receipt.
            // Present its current pose once without advancing or resuming it;
            // otherwise waiting for that receipt and the first frame would cycle.
            surface.setPaused(false)
            defer {
                if self.triadRenderSurface === surface { surface.setPaused(self.session.paused) }
            }
            do {
                try frameDriver.drawFrame(tick: self.session.game.weaponFight?.triadPresentation.liveTick ?? self.session.animationTick,
                    pointOfView: self.pointOfView, samples: self.antialiasingMode == .none ? 1 : 2)
            } catch {
                self.failInitialSourcePresentation(String(describing: error))
                return
            }
            guard !self.ended, self.firstCommittedSourceIdentity != identity,
                  self.triadRenderSurface === surface, let current = self.scene,
                  surface.sceneRenderer.scene === current,
                  self.sourcePreparationIdentity(scene: current, surface: surface) == identity,
                  self.hasUsableMountedBounds, UIApplication.shared.applicationState == .active,
                  self.session.loadError == nil else { return }
            // A paused network preparation may request another presentation immediately.
            // Offline retries wait for its existing display link to provide a new opportunity.
            _ = self.sourcePreparationMayStart(scene: current)
        }
        return false
    }

    private func failInitialSourcePresentation(_ reason: String) {
        guard !ended else { return }
        pendingInitialSourcePresentation = nil
        triadPreparationFailure = reason
        triadMetalRenderer?.clear()
        if preparationOwner != nil { failNetworkPreparation(.rendererFailed) }
        else { session.characterFailed() }
    }

    private func sourceSurfaceDidSubmitFrame(_ surface: DuelTriadRenderSurface) {
        guard !ended, triadRenderSurface === surface, let scene,
              surface.sceneRenderer.scene === scene else { return }
        let identity = sourcePreparationIdentity(scene: scene, surface: surface)
        #if DEBUG
        sourceFrameCommitCount += 1
        #endif
        // Keep the recovered MORPH end-of-frame wait on every real commit.
        sourceMorphDidRenderFrame()
        guard firstCommittedSourceIdentity != identity else { return }
        firstCommittedSourceIdentity = identity
        pendingInitialSourcePresentation = nil
        pendingPreparationAfterCommit = identity
        // Surface invokes this after command.commit(), including offscreen
        // capture. It is not GPU completion or proof of a displayed drawable.
        // Leave its encoding/draw callback before invoking SceneKit.prepare.
        DispatchQueue.main.async { [weak self, weak surface] in
            guard let self, let surface, !self.ended,
                  self.pendingPreparationAfterCommit == identity else { return }
            self.pendingPreparationAfterCommit = nil
            guard self.firstCommittedSourceIdentity == identity,
                  self.triadRenderSurface === surface, let current = self.scene,
                  surface.sceneRenderer.scene === current,
                  self.sourcePreparationIdentity(scene: current, surface: surface) == identity,
                  self.hasUsableMountedBounds, self.session.loadError == nil else { return }
            self.prepareNetworkSceneIfMounted()
            self.prepareSourceMusicIfMounted()
        }
    }

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
        #if DEBUG
        let intercepted = testingMusicPrepare != nil
        #else
        let intercepted = false
        #endif
        guard intercepted || sourcePreparationMayStart(scene: scene) else { return }
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
        prepareOnActiveRenderer([scene], scene: scene) { [weak self] success in
            self?.finishSourceMusicPreparation(request: request, success: success)
        }
    }

    /// Prepare on the actual source renderer only after its first commit.
    /// Both callers keep their original ownership, completion and readiness
    /// contracts. Legacy scenes without a source Surface still use self.
    @discardableResult
    private func prepareOnActiveRenderer(_ objects: [Any], scene expectedScene: SCNScene,
        completion: @escaping @MainActor @Sendable (Bool) -> Void) -> Bool {
        guard !ended, scene === expectedScene else { completion(false); return false }
        let surface = triadRenderSurface
        if let surface {
            guard surface.sceneRenderer.scene === expectedScene,
                  firstCommittedSourceIdentity == sourcePreparationIdentity(scene: expectedScene, surface: surface) else {
                completion(false)
                return false
            }
        }
        let sceneID = ObjectIdentifier(expectedScene)
        let surfaceID = surface.map(ObjectIdentifier.init)
        let rendererID = surface.map { ObjectIdentifier($0.sceneRenderer) } ?? ObjectIdentifier(self)
        #if DEBUG
        scenePreparationRequestCount += 1
        scenePreparationTarget = surface == nil ? "world.scnView" : "surface.sceneRenderer"
        scenePreparationRendererID = rendererID; scenePreparationSceneID = sceneID
        scenePreparationObjectCount = objects.count
        scenePreparationRawSuccess = nil; scenePreparationIdentityMatched = nil
        scenePreparationCommitCountAtRequest = surface == nil ? nil : sourceFrameCommitCount
        scenePreparationNormalFramesAtRequest = surface?.submittedFrames
        #endif
        // Only value identities and the MainActor completion cross SceneKit's
        // callback. Each caller retains its expected scene and request token.
        let finished: @Sendable (Bool) -> Void = { [weak self] success in
            Task { @MainActor [weak self] in
                guard let self, !self.ended else { completion(false); return }
                let currentSurface = self.triadRenderSurface
                let currentRendererID = currentSurface.map { ObjectIdentifier($0.sceneRenderer) }
                    ?? ObjectIdentifier(self)
                let identityMatches = self.scene.map(ObjectIdentifier.init) == sceneID
                    && currentSurface.map(ObjectIdentifier.init) == surfaceID
                    && currentRendererID == rendererID
                    && (currentSurface == nil || currentSurface?.sceneRenderer.scene === self.scene)
                #if DEBUG
                self.scenePreparationCompletionCount += 1
                self.scenePreparationRawSuccess = success
                self.scenePreparationIdentityMatched = identityMatches
                #endif
                completion(success && identityMatches)
            }
        }
        if let surface { surface.sceneRenderer.prepare(objects, completionHandler: finished) }
        else { prepare(objects, completionHandler: finished) }
        return true
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
    /// Read-only evidence of the real production route; these cannot replace
    /// preparation or its completion and are not product readiness inputs.
    private(set) var scenePreparationRequestCount = 0
    private(set) var scenePreparationCompletionCount = 0
    private(set) var scenePreparationTarget: String?
    private(set) var scenePreparationRendererID: ObjectIdentifier?
    private(set) var scenePreparationSceneID: ObjectIdentifier?
    private(set) var scenePreparationObjectCount = 0
    private(set) var scenePreparationRawSuccess: Bool?
    private(set) var scenePreparationIdentityMatched: Bool?
    private(set) var sourceFrameCommitCount = 0
    private(set) var sourcePreparationPresentationSchedules = 0
    private(set) var sourcePreparationPresentationAttempts = 0
    private(set) var scenePreparationCommitCountAtRequest: Int?
    private(set) var scenePreparationNormalFramesAtRequest: Int?
    var sourcePreparationHasFirstCommit: Bool {
        guard let scene, let surface = triadRenderSurface,
              surface.sceneRenderer.scene === scene else { return false }
        return firstCommittedSourceIdentity == sourcePreparationIdentity(scene: scene, surface: surface)
    }
    var sourcePreparationHasPendingWork: Bool {
        pendingInitialSourcePresentation != nil || pendingPreparationAfterCommit != nil
    }
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
        #if DEBUG
        let intercepted = testingPrepare != nil
        #else
        let intercepted = false
        #endif
        guard intercepted || sourcePreparationMayStart(scene: scene) else { return }
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
        usedActualScenePreparation = prepareOnActiveRenderer(objects, scene: scene) { [weak self] success in
            self?.finishNetworkPreparation(owner: owner, success: success)
        }
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
        let isShadowArena = !session.setup.originalWeapons && !usesSyntheticPresentationResources
        isShadowArenaScene = isShadowArena
        let sunlitSky = UIColor(red: 0.62, green: 0.68, blue: 0.72, alpha: 1)
        backgroundColor = isShadowArena ? sunlitSky : UIColor(red: 0.045, green: 0.055, blue: 0.13, alpha: 1)
        antialiasingMode = .multisampling2X; preferredFramesPerSecond = 60
        isUserInteractionEnabled = false; isAccessibilityElement = false; accessibilityElementsHidden = true
        let world = SCNScene(); scene = world
        if isShadowArena {
            world.background.contents = sunlitSky
            world.fogColor = sunlitSky
            world.fogStartDistance = 13.5
            world.fogEndDistance = 56.0
            world.fogDensityExponent = 1.15
            sunlitEnvURL = DuelEnvironmentAssetCache.bundledHDRURL(named: "DuelEnv_Sunlit")
            shadowEnvURL = DuelEnvironmentAssetCache.bundledHDRURL(named: "DuelEnv_Shadow")
            if let envURL = sunlitEnvURL {
                world.lightingEnvironment.contents = envURL
                world.lightingEnvironment.intensity = 1.18
            }
        }
        if session.game.weaponFight?.profiles.contains(where: \.isPangu) == true {
            panguDiagnostics = DuelPanguDiagnostics(parent: world.rootNode)
        }
        let camera = SCNNode(); camera.camera = SCNCamera()
        if isShadowArena {
            camera.camera?.usesOrthographicProjection = false
            camera.camera?.projectionDirection = .vertical
            camera.camera?.fieldOfView = 34
            camera.camera?.zNear = 0.1
            camera.camera?.zFar = 120
            camera.camera?.wantsHDR = true
            camera.camera?.wantsExposureAdaptation = false
            camera.camera?.exposureOffset = -0.10
            camera.camera?.bloomIntensity = 0.10
            camera.camera?.bloomThreshold = 1.65
            camera.camera?.bloomBlurRadius = 4.0
            camera.camera?.vignettingPower = 1.15
            camera.camera?.vignettingIntensity = 0.34
            camera.camera?.saturation = 1.06
            camera.camera?.contrast = 0.14
            // Restrained SSAO grounds boots & armor crevices without stalling mobile GPUs; disabled during TV casting.
            camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.42
            camera.camera?.screenSpaceAmbientOcclusionRadius = 0.24
            camera.camera?.screenSpaceAmbientOcclusionBias = 0.025
            // Subtle depth of field on native phone; automatically disabled during TV/AirPlay casting.
            camera.camera?.wantsDepthOfField = true
            camera.camera?.focusDistance = 5.45
            camera.camera?.fStop = 2.8
            camera.camera?.apertureBladeCount = 6
            camera.position = SCNVector3(5, 1.50, 5.55); camera.look(at: SCNVector3(5, 1.04, 0))
        } else {
            camera.camera?.usesOrthographicProjection = true
            camera.camera?.orthographicScale = 3.6; camera.camera?.zNear = 0.1; camera.camera?.zFar = 80
            camera.position = SCNVector3(5, 3.6, 14); camera.look(at: SCNVector3(5, 1.0, 0))
        }
        world.rootNode.addChildNode(camera); pointOfView = camera
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.color = isShadowArena
            ? UIColor(red: 0.68, green: 0.74, blue: 0.82, alpha: 1)
            : UIColor(red: 0.56, green: 0.58, blue: 0.68, alpha: 1)
        // Low ambient lets our HDR IBL + directional key + rim light carve dramatic 3D form (zero chalky flat wash!)
        ambient.light?.intensity = isShadowArena ? 115 : 560
        world.rootNode.addChildNode(ambient); ambientLightNode = ambient
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional
        key.light?.color = isShadowArena
            ? UIColor(red: 1.0, green: 0.90, blue: 0.72, alpha: 1)
            : UIColor(red: 1.0, green: 0.94, blue: 0.86, alpha: 1)
        key.light?.intensity = isShadowArena ? 1850 : 1320
        key.light?.castsShadow = isShadowArena || session.setup.originalWeapons
        if isShadowArena {
            key.light?.shadowMode = .forward
            key.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
            key.light?.shadowSampleCount = 2
            key.light?.shadowRadius = 2.2
            key.light?.shadowBias = 2.2
            key.light?.shadowColor = UIColor(red: 0.04, green: 0.06, blue: 0.11, alpha: 0.56)
            key.light?.automaticallyAdjustsShadowProjection = false
            key.light?.orthographicScale = 8.5
            key.light?.zNear = 1.0
            key.light?.zFar = 28.0
            key.position = SCNVector3(1.5, 9.5, 7.5)
        } else if session.setup.originalWeapons {
            key.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
            key.light?.shadowColor = UIColor.black.withAlphaComponent(0.36)
        }
        key.eulerAngles = isShadowArena ? SCNVector3(-0.62, -0.48, 0) : SCNVector3(-0.68, -0.38, 0)
        world.rootNode.addChildNode(key); keyLightNode = key
        if isShadowArena {
            // Heroic cool sky back-rim light carves crisp metallic highlights around shoulders, blades & armor!
            let rim = SCNNode(); rim.light = SCNLight(); rim.light?.type = .directional
            rim.light?.color = UIColor(red: 0.68, green: 0.86, blue: 1.0, alpha: 1)
            rim.light?.intensity = 1200
            rim.eulerAngles = SCNVector3(-0.38, 2.58, 0)
            world.rootNode.addChildNode(rim); rimLightNode = rim
        }
        let fill = SCNNode(); fill.light = SCNLight()
        if isShadowArena {
            // Soft warm courtyard ground-bounce fill (replaces chalky frontal omni blast!)
            fill.light?.type = .directional
            fill.light?.color = UIColor(red: 0.82, green: 0.76, blue: 0.66, alpha: 1)
            fill.light?.intensity = 165
            fill.eulerAngles = SCNVector3(0.45, 0.35, 0)
        } else {
            fill.light?.type = .omni
            fill.light?.color = UIColor(red: 0.96, green: 0.96, blue: 1.0, alpha: 1)
            fill.light?.intensity = 320
            fill.position = SCNVector3(5, 2.8, 5.2)
        }
        world.rootNode.addChildNode(fill); fillLightNode = fill
        buildStage(world.rootNode)
        let ringPlane = SCNPlane(width: 1.35, height: 1.35)
        let ringMat = SCNMaterial()
        ringMat.diffuse.contents = DuelProceduralVFXAssets.shockRipple
        ringMat.multiply.contents = UIColor.systemOrange
        ringMat.lightingModel = .constant; ringMat.isDoubleSided = true
        ringMat.transparencyMode = .aOne; ringMat.blendMode = .add; ringMat.writesToDepthBuffer = false
        ringPlane.materials = [ringMat]
        let ring = SCNNode(geometry: ringPlane)
        ring.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        ring.castsShadow = false; ring.isHidden = true; world.rootNode.addChildNode(ring); slamRing = ring
        let sparkPlane = SCNPlane(width: 1.15, height: 1.15)
        let sparkMat = SCNMaterial()
        sparkMat.diffuse.contents = DuelProceduralVFXAssets.impactCross
        sparkMat.multiply.contents = UIColor.systemYellow
        sparkMat.lightingModel = .constant; sparkMat.isDoubleSided = true
        sparkMat.transparencyMode = .aOne; sparkMat.blendMode = .add; sparkMat.writesToDepthBuffer = false
        sparkPlane.materials = [sparkMat]
        let spark = SCNNode(geometry: sparkPlane)
        spark.castsShadow = false; spark.isHidden = true; world.rootNode.addChildNode(spark); hitSpark = spark
        if !session.setup.originalWeapons && !usesSyntheticPresentationResources {
            originalVFX = DuelOriginalVFX(parent: world.rootNode)
            for hero in Set(session.game.fighters.map(\.hero)) {
                if let asset = DuelCascadeurCharacterAsset.loadBundled(for: hero) {
                    cascadeurAssets[hero] = asset
                }
            }
            if !cascadeurAssets.isEmpty {
                let loaded = session.game.fighters.compactMap { cascadeurAssets[$0.hero] == nil ? nil : $0.hero.name }
                session.characterLoaded(loaded.joined(separator: "、") + " · 原创骨骼角色")
            } else {
                session.characterLoaded("人物资源未就绪 · 当前显示动作替身")
            }
        }
        if characterSource != .procedural && !usesSyntheticPresentationResources {
            for hero in Set(session.game.fighters.map(\.hero)) {
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
            let loaded = session.game.fighters.compactMap { cascadeurAssets[$0.hero] == nil && characterAssets[$0.hero] == nil && originalAssets[$0.hero] == nil && weaponAssets[$0.hero] == nil ? nil : $0.hero.name }
            let equippedTitles = session.game.weaponFight?.profiles.map(\.weaponTitle).joined(separator: " / ") ?? ""
            session.characterLoaded(session.setup.originalWeapons ? loaded.joined(separator: "、") + " · " + equippedTitles : loaded.isEmpty ? "人物资源未就绪 · 当前显示动作替身" : loaded.joined(separator: "、") + " · 全身人物")
        }
        for (index, fighter) in session.game.fighters.enumerated() {
            let actor = DuelActor(hero: fighter.hero, asset: characterAssets[fighter.hero], originalAsset: originalAssets[fighter.hero], weaponAsset: weaponAssets[fighter.hero], cascadeurAsset: cascadeurAssets[fighter.hero]); actor.root.name = "duel.actor.\(actors.count)"
            if session.setup.originalWeapons && weaponAssets[fighter.hero] == nil { actor.root.isHidden = true }
            actors.append(actor); world.rootNode.addChildNode(actor.root)
            if session.game.shogunState(index) != nil {
                let companion = DuelShogunCompanionNode()
                companion.root.name = "duel.shogun.companion.\(index)"
                shogunCompanions[index] = companion
                world.rootNode.addChildNode(companion.root)
            }
            if session.game.nonnaState(index) != nil {
                let wolf = DuelSpiritWolfNode()
                wolf.root.name = "duel.nonna.wolf.\(index)"
                wolf.root.isHidden = true
                spiritWolves[index] = wolf
                world.rootNode.addChildNode(wolf.root)
                let owl = DuelSpiritOwlNode()
                owl.root.name = "duel.nonna.owl.\(index)"
                owl.root.isHidden = true
                spiritOwls[index] = owl
                world.rootNode.addChildNode(owl.root)
            }
            if session.game.inquisitorState(index) != nil {
                let halo = DuelOriginalVFX.makeStigmataSigilNode()
                halo.isHidden = true
                halo.name = "duel.inquisitor.stigmata.\(index)"
                stigmataHalos[index] = halo
                world.rootNode.addChildNode(halo)
            }
            if session.game.legionKingState(index) != nil {
                let chain = DuelLegionChainNode()
                chain.root.name = "duel.legion.chain.\(index)"
                chain.root.isHidden = true
                legionChains[index] = chain
                world.rootNode.addChildNode(chain.root)
            }
            if session.game.monkeyKingState(index) != nil {
                let pillar = DuelMonkeyPillarNode()
                pillar.root.name = "duel.monkey.pillar.\(index)"
                pillar.root.isHidden = true
                monkeyPillars[index] = pillar
                world.rootNode.addChildNode(pillar.root)
            }
            let hurt = debugBox(.green), attack = debugBox(.orange)
            hurtNodes.append(hurt); attackNodes.append(attack); world.rootNode.addChildNode(hurt); world.rootNode.addChildNode(attack)
        }
        session.renderPause = { [weak self] paused in
            guard let self, !self.ended else { return }
            self.sourceEffects?.setPaused(paused)
            self.weaponEffects?.setPaused(paused)
            self.triadRenderSurface?.setPaused(paused)
            if paused { self.stopClock() } else { self.startClock() }
        }
        if session.setup.originalWeapons, let summons = session.weaponAssets?.triadSummons {
            triadSummons = DuelTriadSummonRenderer(assets: summons, parent: world.rootNode)
        }
        if session.setup.originalWeapons, let companions = session.weaponAssets?.erlangCompanions {
            erlangCompanions = DuelErlangCompanionRenderer(assets: companions, parent: world.rootNode)
        }
        if session.setup.originalWeapons, let bottle = session.weaponAssets?.serpentBottle {
            serpentBottles = DuelSerpentBottleRenderer(assets: bottle, parent: world.rootNode)
        }
        if session.setup.originalWeapons,
           session.weaponAssets?.triadEffects != nil || session.weaponAssets?.erlangHoundEffects != nil ||
           session.weaponAssets?.erlangStompEffects != nil || session.weaponAssets?.erlangSwordEffects != nil ||
           session.weaponAssets?.erlangSkillEffects != nil {
            do {
                usesReverseZ = false
                let formats = try DuelTriadRenderSurface.formats(device: device)
                let renderer = try DuelTriadMetalRenderer(device: device, formats: formats)
                if let effects = session.weaponAssets?.triadEffects {
                    let factory = try effects.prepare(device: device, formats: formats)
                    triadSourceEffects = DuelTriadSourceEffects(assets: effects, factory: factory, parent: world.rootNode)
                }
                if let effects = session.weaponAssets?.erlangHoundEffects {
                    let factory = try effects.particles.prepare(device: device, formats: formats)
                    erlangHoundEffects = DuelErlangHoundEffects(assets: effects, factory: factory)
                }
                if let effects = session.weaponAssets?.erlangStompEffects {
                    let factory = try effects.particles.prepare(device: device, formats: formats)
                    erlangStompEffects = DuelErlangStompEffects(assets: effects, factory: factory)
                }
                if let effects = session.weaponAssets?.erlangSwordEffects {
                    let factory = try effects.particles.prepare(device: device, formats: formats)
                    erlangSwordEffects = DuelErlangSwordEffects(assets: effects, factory: factory)
                }
                if let effects = session.weaponAssets?.erlangSkillEffects {
                    let factory = try effects.particles.prepare(device: device, formats: formats)
                    erlangSkillEffects = DuelErlangSkillEffects(assets: effects, factory: factory)
                }
                let surface = try DuelTriadRenderSurface(frame: bounds, device: device, scene: world,
                    pointOfView: pointOfView, packets: renderer)
                let frameDriver = try DuelTriadSurfaceFrameDriver(surface: surface)
                surface.lateSourceGeometry = { [weak self] in self?.triadSummons?.lateSourceGeometry ?? [] }
                surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                addSubview(surface)
                surface.applyRenderScale(contentScaleFactor)
                triadMetalRenderer = renderer; triadRenderSurface = surface
                triadSurfaceFrameDriver = frameDriver
                surface.didSubmitFrame = { [weak self, weak surface] in
                    guard let surface else { return }
                    self?.sourceSurfaceDidSubmitFrame(surface)
                }
                rendersContinuously = false; isPlaying = false
            } catch { triadPreparationFailure = String(describing: error); session.characterFailed() }
        }
        if session.setup.originalWeapons, let fight = session.game.weaponFight,
           let assets = session.weaponAssets?.sourceMorph(for: fight.profiles) {
            do {
                guard let owner = fight.profiles.firstIndex(where: { $0.id == assets.ownerProfileID }),
                      let target = fight.profiles.firstIndex(where: {
                          $0.id == assets.targetProfileID && $0.sha256 == assets.targetCharacterSHA256
                      }), owner != target, actors.indices.contains(target),
                      let surface = triadRenderSurface, let gpu = device,
                      stageAsset?.kind == .palace, let stageRoot = musicStageRoot,
                      actors.count == 2 else {
                    throw DuelTriadSourceMorphAssets.Failure.identity
                }
                let prepared = try assets.prepare(device: device)
                let binding = try actors[target].installSourceMorph(prepared, materials: assets.materials)
                triadSourceMorph = binding
                let casterInstances = try actors.map { try $0.sourceShadowInstance() }
                let shadow = try DuelSourceProjectedShadowRenderer(device: gpu,
                    formats: DuelTriadRenderSurface.formats(device: gpu),
                    definition: assets.projectedShadow, stageRoot: stageRoot, actors: casterInstances,
                    worldCenters: { [weak self] in
                        guard let self, !self.ended, let current = self.session.game.weaponFight,
                              current.fighters.count == 2 else { throw DuelSourceProjectedShadowRenderer.Failure.geometry }
                        return try (0..<2).map { index in
                            // Native actor centerOfMass is the mass-weighted
                            // FK point, including its current full XYZ pose.
                            // Neither a root nor pelvis origin may replace it.
                            guard let point = current.sourceCenterOfMass(index) else {
                                throw DuelSourceProjectedShadowRenderer.Failure.geometry
                            }
                            return SIMD3(Float(point.x), Float(point.y), Float(point.z))
                        }
                    }, fade: { [weak binding] index in index == target ? binding?.progress ?? 0 : 0 })
                surface.projectedShadow = shadow
                triadMorphOwner = owner; triadMorphTrigger = assets.trigger
                // The shared submit callback preserves the recovered MORPH
                // wait; layout or a simulation step cannot satisfy it.
            } catch { triadPreparationFailure = String(describing: error); session.characterFailed() }
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
                    sourceEffects = try DuelSourceEffects(root: world.rootNode, directory: directory,
                        panguAudio: session.weaponAssets?.panguAudio, triadAudio: session.weaponAssets?.triadAudio,
                        erlangAudio: session.weaponAssets?.erlangAudio,
                        serpentAudio: session.weaponAssets?.serpentAudio)
                    weaponEffects = try DuelWeaponEffects(root: world.rootNode, directory: directory)
                }
                catch { session.characterFailed() }
            }
        }
        session.didSimulateStep = { [weak self] game, tick in self?.consumeFeedback(game, tick: tick) }
        consumeFeedback(session.game, tick: 0)
        session.didReset = { [weak self] in
            guard let self, !self.ended else { return }
            self.originalVFX?.reset()
            self.dramaticZoomTicks = 0
            self.slowMoTicks = 0
            self.slowMoSkipFlip = false
            self.shadowCameraInitialized = false
            self.atmosphereShadowBlend = 0
            self.atmosphereLightBlend = 0
            self.atmosphereFlameBlend = 0
            self.lastAudioAttackKeys = [nil, nil]
            self.lastWarnAttackKeys = [nil, nil]
            self.sourceEffects?.reset(); self.weaponEffects?.reset()
            self.panguDiagnostics?.reset()
            self.triadSummons?.reset()
            self.erlangCompanions?.reset()
            self.serpentBottles?.reset()
            self.erlangHoundEffects?.reset()
            self.erlangStompEffects?.reset()
            self.erlangSwordEffects?.reset()
            self.erlangSkillEffects?.reset()
            self.triadSourceEffects?.reset()
            self.triadSourceMorph?.reset(); self.triadMorphRequested = false
            self.triadRenderSurface?.projectedShadow?.reset()
            self.triadMetalRenderer?.clear()
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
        for name in [UIScreen.didConnectNotification, UIScreen.didDisconnectNotification,
                     UIScreen.modeDidChangeNotification, UIScreen.capturedDidChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(updateDisplayRenderBudget), name: name, object: nil)
        }
        drawState()
        sceneAssemblyFinished = true
        if isShadowArena {
            // Asynchronously precompile Metal pipelines on a background queue so Frame 0 / first hit never stalls.
            prepare([world], completionHandler: nil)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// Bound GPU work while preserving the external viewport and camera aspect.
    static func televisionRenderScale(size: CGSize, screenScale: CGFloat, casting: Bool) -> CGFloat {
        DuelDisplayRenderBudget(size: size, screenScale: screenScale, casting: casting)?.scale ?? screenScale
    }
    @objc private func updateDisplayRenderBudget() {
        guard let screen = window?.screen else { return }
        let external = window?.windowScene?.session.role == .windowExternalDisplayNonInteractive
        let mirrored = UIScreen.screens.contains { $0.mirrored === screen }
        let casting = DuelDisplayRenderBudget.isCasting(
            externalDisplay: external, mirrored: mirrored, screenCaptured: screen.isCaptured
        )
        isCastingDisplay = casting
        guard let budget = DuelDisplayRenderBudget(size: bounds.size,
            screenScale: screen.scale, casting: casting) else { return }
        if contentScaleFactor != budget.scale { contentScaleFactor = budget.scale }
        // A wireless mirror notification can arrive without any layout pass.
        // Apply to the actual Metal drawable immediately, not just its parent.
        triadRenderSurface?.applyRenderScale(budget.scale, casting: casting)
        let aa: SCNAntialiasingMode = budget.samples == 1 ? .none : .multisampling2X
        if antialiasingMode != aa { antialiasingMode = aa }
        if isShadowArenaScene {
            if let cam = pointOfView?.camera {
                cam.wantsDepthOfField = budget.allowsDepthOfField
                cam.screenSpaceAmbientOcclusionIntensity = budget.allowsAmbientOcclusion ? 0.42 : 0.0
                if !budget.allowsBloom { cam.bloomIntensity = 0.0 }
            }
            if let keyLight = keyLightNode?.light {
                let dim = CGFloat(budget.shadowMapDimension)
                let target = CGSize(width: dim, height: dim)
                if keyLight.shadowMapSize != target { keyLight.shadowMapSize = target }
                if keyLight.shadowSampleCount != budget.shadowSampleCount {
                    keyLight.shadowSampleCount = budget.shadowSampleCount
                }
            }
        }
    }
    private var relocatingDisplay = false

    /// Transfer the existing renderer, never clone its scene/clock/simulation.
    /// The temporary window=nil during a synchronous authorized transfer is not
    /// a network mount loss. All ordinary detachments retain their fail-closed path.
    @discardableResult
    func relocateDisplay(to destination: UIView) -> Bool {
        guard !ended, !relocatingDisplay, destination.window != nil,
              destination.bounds.width > 0, destination.bounds.height > 0 else { return false }
        if superview === destination { return true }
        session.clearInput()
        guard !ended, destination.window != nil else { return false }
        relocatingDisplay = true
        stopClock()
        removeFromSuperview()
        frame = destination.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        destination.addSubview(self)
        relocatingDisplay = false
        // Re-evaluate exact mount/readiness and camera bounds after the transfer.
        didMoveToWindow()
        setNeedsLayout(); layoutIfNeeded()
        return !ended && window != nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard !ended, !relocatingDisplay else { return }
        retryPreparationAttachment()
        if window == nil {
            if preparationOwner != nil && preparationMounted {
                failNetworkPreparation(.detached)
                return
            }
            stopClock(); session.clearInput()
            session.updateCharacterOcclusion([], from: self)
        } else {
            updateDisplayRenderBudget()
            prepareNetworkSceneIfMounted()
            preparationMountChanged()
            if !session.paused { startClock() }
        }
        prepareSourceMusicIfMounted()
        session.refreshSourceMusicReadiness(from: self)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !relocatingDisplay else { return }
        retryPreparationAttachment()
        triadRenderSurface?.frame = bounds
        updateDisplayRenderBudget()
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
        let isShadowArenaPerspective = stageAsset == nil && !session.setup.originalWeapons && !usesSyntheticPresentationResources
        let dramaticWeight: Float
        if isShadowArenaPerspective && dramaticZoomTicks > 0 && !UIAccessibility.isReduceMotionEnabled {
            let phase = Float(dramaticZoomTicks) / Float(max(1, dramaticZoomDuration))
            // Smooth attack-hold-release zoom curve (fast zoom-in, brief hold, smooth ease-out)
            dramaticWeight = min(1.0, phase * 2.2) * sin(min(1.0, phase) * .pi * 0.5)
        } else {
            dramaticWeight = 0
        }
        let trackedX = Float(combatCamera.centerX) * (1 - dramaticWeight * 0.50) + dramaticFocusX * (dramaticWeight * 0.50)
        let trackedY: Float
        var position = cameraBasePosition
        position.x = trackedX
        if isShadowArenaPerspective {
            let fovDeg: Float = 34.0
            let tanHalfFov = tan(fovDeg * .pi / 360.0)
            let sep = Float(combatCamera.separation)
            let minVertZ: Float = 4.75 + max(0, sep - 1.3) * 0.30
            let requiredHalfWidth = max(sep * 0.5 + 1.15, 2.35)
            let minHorizZ = requiredHalfWidth / (max(Float(aspect), 0.55) * tanHalfFov)
            let targetZ = max(3.9, min(8.6, max(minVertZ, minHorizZ)) - dramaticWeight * 0.72)
            if !shadowCameraInitialized {
                smoothedShadowCameraZ = targetZ
                shadowCameraInitialized = true
            } else {
                smoothedShadowCameraZ += (targetZ - smoothedShadowCameraZ) * 0.16
            }
            position.z = smoothedShadowCameraZ
            position.y = 1.46 + (smoothedShadowCameraZ - 5.2) * 0.08 - dramaticWeight * 0.14
            trackedY = 1.03 * (1 - dramaticWeight * 0.42) + dramaticFocusY * (dramaticWeight * 0.42)
            fillLightNode?.position = SCNVector3(trackedX, 2.8, 4.8)
        } else {
            trackedY = (stageAsset != nil ? 1.2 : 1.0) * (1 - dramaticWeight * 0.45) + dramaticFocusY * (dramaticWeight * 0.45)
            if stageAsset != nil {
                perspectiveDistance = Float(framing.perspectiveDistance)
                position.z = perspectiveDistance
            } else if dramaticWeight > 0.001 {
                position.y = cameraBasePosition.y * (1 - dramaticWeight * 0.25) + (dramaticFocusY + 0.65) * (dramaticWeight * 0.25)
            }
        }
        eye.position = position
        eye.look(at: SCNVector3(trackedX, trackedY, 0))
        if !UIAccessibility.isReduceMotionEnabled {
            let shakeBoost: Float = isShadowArenaPerspective ? 3.5 : 1.0
            eye.position.x += Float(combatCamera.impactOffsetX) * shakeBoost
            eye.position.y += Float(combatCamera.impactOffsetY) * shakeBoost * (isShadowArenaPerspective ? 1.35 : 1.0)
            if let hold = session.game.grapple {
                let release = DuelGame.Grapple.takedownTicks + DuelGame.Grapple.holdTicks
                let elapsed = hold.age >= release ? hold.age - release : hold.age - DuelGame.Grapple.takedownTicks
                if (0..<18).contains(elapsed) {
                    eye.position.y += sin(Float(elapsed) * 1.8) * 0.035 * (1 - Float(elapsed) / 18)
                }
            }
        }
        opticalFramingFailure = nil
        let viewTransform = simd_inverse(eye.simdWorldTransform)
        if isShadowArenaPerspective {
            opticalFOV.reset()
            camera.usesOrthographicProjection = false
            camera.projectionDirection = .vertical
            let fovPunch = UIAccessibility.isReduceMotionEnabled ? 0.0 : combatCamera.fovPunchDegrees
            camera.fieldOfView = CGFloat(max(29.0, 34.0 - fovPunch))
            camera.focusDistance = CGFloat(max(2.0, position.z))
        } else if stageAsset != nil {
            camera.fieldOfView = CGFloat(framing.verticalFieldOfView)
            if session.setup.originalWeapons {
                do {
                    cameraPoints.removeAll(keepingCapacity: true)
                    for actor in actors {
                        try actor.appendDisplayedCameraPoints(view: viewTransform, to: &cameraPoints)
                    }
                    // Reserve eight UIKit points on the shorter viewport axis,
                    // conservatively at least that much on the longer axis.
                    let shortSide = Double(min(bounds.width, bounds.height))
                    let inset = 1 - 2 * min(8, shortSide * 0.1) / shortSide
                    let requiredFOV = try DuelDisplayedSkinBounds.verticalFOV(
                        points: cameraPoints, aspect: aspect, minimum: framing.verticalFieldOfView,
                        near: camera.zNear, inset: inset)
                    // Fit the entire measured pose immediately. Contract only
                    // once per simulation frame, so weapon swings do not cause
                    // abrupt lens pumping or shrink on repeated layout calls.
                    camera.fieldOfView = CGFloat(opticalFOV.consume(
                        required: requiredFOV, frame: session.game.frame, aspect: aspect))
                    // Reuse the same conservative points and the final installed FOV.
                    // This does not change the camera, actor scale or touch geometry.
                    let rectangles = DuelDisplayedSkinBounds.artworkRectangles(
                        points: cameraPoints, size: bounds.size, verticalFieldOfView: Double(camera.fieldOfView))
                    session.updateCharacterOcclusion(rectangles, from: self)
                } catch {
                    // A missing/invalid skin envelope is NOT a successful fit.
                    // Retain the last wider lens rather than snapping to the
                    // narrow pair-only FOV; preserve the explicit failure and
                    // clear stale control occlusion until valid bounds return.
                    camera.fieldOfView = CGFloat(opticalFOV.retainedAfterFailedFit(
                        minimum: framing.verticalFieldOfView))
                    opticalFramingFailure = (error as? DuelDisplayedSkinBounds.Failure) ?? .unsupportedGeometry
                    session.updateCharacterOcclusion([], from: self)
                }
            } else {
                opticalFOV.reset()
            }
        } else {
            opticalFOV.reset()
            let zoomFactor = Double(1.0 - 0.24 * dramaticWeight)
            camera.orthographicScale = framing.orthographicScale * zoomFactor
        }
        for actor in actors { actor.updateSourceLighting(viewTransform) }
    }

    @objc private func interrupted() { guard !ended else { return }; session.pause() }
    @objc private func becameActive() {
        // A new view may be attached during the first foreground transition.
        // Start its clock when UIKit is active; an interrupted fight stays
        // paused until the player explicitly chooses Resume.
        if !session.paused { startClock() }
        prepareNetworkSceneIfMounted()
        prepareSourceMusicIfMounted()
    }
    private func startClock() {
        guard !ended, window != nil, !session.paused, UIApplication.shared.applicationState == .active, link == nil else { return }
        lastTime = nil; clock.reset(); clockCallbacks = 0; firstStepDelay = nil
        clockStartedAt = CACurrentMediaTime()
        rendersContinuously = triadRenderSurface == nil; isPlaying = triadRenderSurface == nil
        triadRenderSurface?.setPaused(false)
        if !session.setup.originalWeapons && !usesSyntheticPresentationResources {
            DuelOriginalSound.shared.setActive(true)
        }
        let target = DuelDisplayTarget(self)
        let driver = window?.windowScene?.screen.displayLink(withTarget: target, selector: #selector(DuelDisplayTarget.tick(_:))) ?? CADisplayLink(target: target, selector: #selector(DuelDisplayTarget.tick(_:)))
        driver.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        driver.add(to: .main, forMode: .common); link = driver; Self.activeClocks += 1
    }
    private func stopClock() {
        if link != nil { Self.activeClocks -= 1 }
        link?.invalidate(); link = nil; lastTime = nil; clock.reset()
        rendersContinuously = false; isPlaying = false
        triadRenderSurface?.setPaused(true)
        if !session.setup.originalWeapons {
            DuelOriginalSound.shared.setActive(false)
        }
    }
    func shutdown(preparationFailure: PreparationFailure = .replaced) {
        guard !ended else { return }
        ended = true
        pendingUIAttachment = nil; uiAttachmentQueued = false
        pendingInitialSourcePresentation = nil; pendingPreparationAfterCommit = nil
        firstCommittedSourceIdentity = nil
        initialSourcePresentationIdentity = nil; initialSourcePresentation = DuelInitialSurfacePresentation()
        musicPreparationID = nil; musicPreparationFinished = true
        musicPreparingScene = nil; musicPreparedScene = nil; musicStageRoot = nil
        let invalidated = preparationInvalidated; preparationInvalidated = nil
        preparationOwner = nil; preparationCompletion = nil; preparingScene = nil; preparedMountChanged = nil
        preparationFinished = true
        #if DEBUG
        testingPrepare = nil; testingMusicPrepare = nil
        #endif
        stopClock()
        if !session.setup.originalWeapons {
            DuelOriginalSound.shared.setActive(false)
        }
        session.renderPause = nil; session.didSimulateStep = nil; session.didReset = nil
        if session.driver == .offline {
            session.releaseOfflineWorld(self)
            session.clearInput()
        }
        originalVFX?.shutdown(); originalVFX = nil
        sourceEffects?.shutdown(); sourceEffects = nil
        weaponEffects?.shutdown(); weaponEffects = nil
        panguDiagnostics?.shutdown(); panguDiagnostics = nil
        triadSummons?.shutdown(); triadSummons = nil
        erlangCompanions?.shutdown(); erlangCompanions = nil
        serpentBottles?.shutdown(); serpentBottles = nil
        erlangHoundEffects?.shutdown(); erlangHoundEffects = nil
        erlangStompEffects?.shutdown(); erlangStompEffects = nil
        erlangSwordEffects?.shutdown(); erlangSwordEffects = nil
        erlangSkillEffects?.shutdown(); erlangSkillEffects = nil
        triadSourceEffects?.shutdown(); triadSourceEffects = nil
        triadSourceMorph?.shutdown(); triadSourceMorph = nil
        triadMorphOwner = nil; triadMorphTrigger = nil; triadMorphRequested = false
        triadSurfaceFrameDriver?.shutdown(); triadSurfaceFrameDriver = nil
        triadRenderSurface?.shutdown(); triadRenderSurface?.removeFromSuperview(); triadRenderSurface = nil
        triadMetalRenderer?.shutdown(); triadMetalRenderer = nil; delegate = nil
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
        actors.removeAll(); characterAsset = nil; characterAssets.removeAll(); originalAssets.removeAll(); weaponAssets.removeAll(); cascadeurAssets.removeAll(); shogunCompanions.removeAll(); spiritWolves.removeAll(); spiritOwls.removeAll(); stigmataHalos.removeAll(); legionChains.removeAll(); monkeyPillars.removeAll(); stageAsset = nil; bolts.removeAll(); hurtNodes.removeAll(); attackNodes.removeAll(); slamRing = nil; hitSpark = nil
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
        let cpuStart = CACurrentMediaTime()
        if dramaticZoomTicks > 0 { dramaticZoomTicks -= 1 }
        var effectiveSteps = steps
        if !session.setup.originalWeapons && slowMoTicks > 0 && !UIAccessibility.isReduceMotionEnabled {
            slowMoTicks -= 1
            slowMoSkipFlip.toggle()
            if slowMoSkipFlip { effectiveSteps = 0 }
            else { effectiveSteps = min(1, steps) }
        }
        for _ in 0..<effectiveSteps {
            if session.game.hitStop > 0 { frozenStepCount += 1 }
            session.advance()
        }
        let simulationEnd = CACurrentMediaTime()
        drawState()
        if session.driver == .offline, !ended, session.loadError == nil,
           initialSourcePresentation.attempts > 0, let scene, let surface = triadRenderSurface,
           firstCommittedSourceIdentity != sourcePreparationIdentity(scene: scene, surface: surface) {
            _ = sourcePreparationMayStart(scene: scene)
        }
        let drawingEnd = CACurrentMediaTime()
        cpuSamples.append((simulationEnd - cpuStart, drawingEnd - simulationEnd))
        if case .matchOver = session.game.phase { stopClock() }
        sampleCount += 1
        if elapsed > 0.025 { slowCallbacks += 1 }
        if intervals.count < 1200 { intervals.append(elapsed) }
        else { intervals[intervalCursor] = elapsed; intervalCursor = (intervalCursor + 1) % 1200 }
        if timestamp - lastReport >= 1 {
            lastReport = timestamp
            let sorted = intervals.sorted(), p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))] * 1000
            func cpuP95(_ values: [Double]) -> Double {
                let sorted = values.sorted()
                return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))] * 1000
            }
            let detail = String(format: "\n逻辑CPU p95 %.1f ms · 画面CPU p95 %.1f ms · 命中停顿步 %d\n渲染 %.0f×%.0f · AA %d",
                cpuP95(cpuSamples.map(\.simulation)), cpuP95(cpuSamples.map(\.drawing)), frozenStepCount,
                bounds.width * contentScaleFactor, bounds.height * contentScaleFactor, antialiasingMode.rawValue)
            cpuSamples.removeAll(keepingCapacity: true); frozenStepCount = 0
            session.metrics(String(format: "刷新回调 p95 %.1f ms · 慢回调 %d/%d\n内存 %.0f MB · 热状态 %d · 丢弃补步 %.2f s",
                p95, slowCallbacks, sampleCount, Self.memoryMB(), ProcessInfo.processInfo.thermalState.rawValue, clock.droppedSeconds) + detail)
        }
    }
    func drawState() {
        guard !ended, scene != nil else { return }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        for i in 0..<actors.count {
            let fighter = session.game.fighters[i]
            let shiver: Float = (!reduceMotion && session.game.hitStop > 0 && fighter.flash > 0)
                ? (session.game.hitStop % 2 == 0 ? 0.022 : -0.022)
                : 0
            actors[i].pose(fighter, frame: session.animationTick, grapple: session.game.grapple, index: i, phase: session.game.phase, shadow: session.game.weaponFight?.shadowVisual(i),
                           sourceTrailActive: sourceWeaponSkinsEnabled && session.game.weaponFight?.weaponTrailIsActive(i) == true,
                           sourceTrailEnabled: sourceWeaponSkinsEnabled,
                           shogun: session.game.shogunState(i),
                           arenaKit: session.game.arenaKitStates.indices.contains(i) ? session.game.arenaKitStates[i] : nil,
                           hitStopShiverX: shiver)
            if let companion = shogunCompanions[i], let shogun = session.game.shogunState(i) {
                companion.pose(shogun, frame: session.animationTick)
            }
            if let wolf = spiritWolves[i], let nonna = session.game.nonnaState(i) {
                wolf.pose(nonna, frame: session.animationTick)
            }
            if let owl = spiritOwls[i], let nonna = session.game.nonnaState(i) {
                owl.pose(nonna, frame: session.animationTick)
            }
            if let halo = stigmataHalos[i], let inq = session.game.inquisitorState(i) {
                if inq.hasStigmataOnOpponent {
                    let target = session.game.fighters[1 - i]
                    halo.isHidden = false
                    halo.position = SCNVector3(Float(target.x) / 1000, Float(target.y) / 1000 + 2.06 + sin(Float(session.animationTick) * 0.14) * 0.04, 0.14)
                    halo.simdOrientation = simd_quatf(angle: -Float.pi / 2 + 0.34, axis: SIMD3<Float>(1, 0, 0)) *
                        simd_quatf(angle: Float(session.animationTick) * 0.08, axis: SIMD3<Float>(0, 0, 1))
                } else {
                    halo.isHidden = true
                }
            }
            if let chain = legionChains[i], let lk = session.game.legionKingState(i) {
                let fallbackHand = SIMD3<Float>(Float(fighter.x) / 1000 + Float(fighter.facing) * 0.38, Float(fighter.y) / 1000 + 1.24, 0.10)
                let handPos = actors[i].leftHandWorldPosition(fallback: fallbackHand)
                let targetFighter = session.game.fighters[1 - i]
                chain.pose(lk, origin: handPos, facing: fighter.facing, target: targetFighter, frame: session.animationTick)
            }
            if let pillar = monkeyPillars[i], let mk = session.game.monkeyKingState(i) {
                pillar.pose(mk, frame: session.animationTick)
            }
            // Debug hurt boxes resample every source hurt capsule. Leave that
            // work to combat unless the player actually wants to display them.
            if session.showBoxes && session.game.fighters[i].knockdown == 0 && session.game.grapple == nil {
                place(hurtNodes[i], box: session.game.hurtBox(i))
            } else if !hurtNodes[i].isHidden {
                hurtNodes[i].isHidden = true
            }
            if session.showBoxes, let box = session.game.attackBox(i) {
                place(attackNodes[i], box: box)
            } else if !attackNodes[i].isHidden {
                attackNodes[i].isHidden = true
            }
        }
        if let hold = session.game.grapple {
            actors[hold.attacker].connectWrist(to: actors[1 - hold.attacker], hold: hold)
        }
        updateSourceMorph(session.game.weaponFight)
        // SceneKit and source FX must observe this same final camera. Moving
        // it after making source packets would separate effects from bodies.
        updateCameraFraming()
        if let fight = session.game.weaponFight {
            panguDiagnostics?.draw(fight.panguPresentation, visible: session.showBoxes,
                                   fighting: fight.phase == .fighting)
            triadSummons?.draw(fight.triadPresentation, fighting: fight.phase == .fighting)
            erlangCompanions?.draw(fight)
            serpentBottles?.draw(fight)
            if let renderer = triadMetalRenderer, let cameraNode = pointOfView,
               let camera = cameraNode.camera, bounds.width > 0, bounds.height > 0 {
                do {
                    let projection = try DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: bounds.size)
                    var additional = try erlangHoundEffects?.draw(fight,
                        cameraTransform: cameraNode.simdWorldTransform, projection: projection) ?? []
                    let stomp = try erlangStompEffects?.draw(fight,
                        cameraTransform: cameraNode.simdWorldTransform, projection: projection) ?? []
                    let offset = (additional.map { $0.order.emitter }.max() ?? -1) + 1
                    additional += stomp.map { .init(draw: $0.draw, order: $0.ordering(rebasedBy: offset)) }
                    let swords = try erlangSwordEffects?.draw(fight,
                        cameraTransform: cameraNode.simdWorldTransform, projection: projection) ?? []
                    let swordOffset = (additional.map { $0.order.emitter }.max() ?? -1) + 1
                    additional += swords.map { .init(draw: $0.draw, order: $0.ordering(rebasedBy: swordOffset)) }
                    let skills = try erlangSkillEffects?.draw(fight,
                        cameraTransform: cameraNode.simdWorldTransform, projection: projection,
                        orthographic: camera.usesOrthographicProjection) ?? []
                    let skillOffset = (additional.map { $0.order.emitter }.max() ?? -1) + 1
                    additional += skills.map { .init(draw: $0.draw, order: $0.ordering(rebasedBy: skillOffset)) }
                    let packets = try triadSourceEffects?.draw(fight, cameraTransform: cameraNode.simdWorldTransform,
                        projection: projection, additionalPackets: additional) ?? DuelSourceParticlePacket.sorted(additional)
                    let format = DuelTriadRenderSurface.format(samples: antialiasingMode == .none ? 1 : 2)
                    try renderer.submit(.init(format: format, draws: packets))
                } catch { triadPreparationFailure = String(describing: error); renderer.clear(); session.characterFailed() }
            }
        }
        slamRing?.isHidden = true
        // Smooth SF4 Monochrome Ink Shadow World & radiant form atmosphere transitions!
        let anyCataclysm = (0..<session.game.fighters.count).contains { session.game.shogunState($0)?.isCataclysm == true }
        let anyLightForm = (0..<session.game.fighters.count).contains {
            session.game.inquisitorState($0)?.isInFormOfLight == true ||
            session.game.monkeyKingState($0)?.hasHeavenlyAura == true
        }
        let anyFlameForm = (0..<session.game.fighters.count).contains { session.game.nonnaState($0)?.isInFlameForm == true }
        let anyShadow = (0..<session.game.fighters.count).contains {
            session.game.shogunState($0)?.isInShadow == true ||
            session.game.midnightState($0)?.isInShadowForm == true ||
            (session.game.emperorState($0)?.transformBurstTicks ?? 0) > 0 ||
            (session.game.legionKingState($0)?.reviveAnimTicks ?? 0) > 0
        }
        if !session.setup.originalWeapons && !usesSyntheticPresentationResources {
            let targetShadow: Float = (anyShadow || anyCataclysm) ? 1.0 : 0.0
            let targetLight: Float = (anyLightForm && !anyShadow && !anyCataclysm) ? 1.0 : 0.0
            let targetFlame: Float = (anyFlameForm && !anyShadow && !anyCataclysm) ? 1.0 : 0.0
            atmosphereShadowBlend += (targetShadow - atmosphereShadowBlend) * 0.14
            atmosphereLightBlend += (targetLight - atmosphereLightBlend) * 0.14
            atmosphereFlameBlend += (targetFlame - atmosphereFlameBlend) * 0.14
            let s = CGFloat(atmosphereShadowBlend)
            let l = CGFloat(atmosphereLightBlend)
            let fl = CGFloat(atmosphereFlameBlend)
            let formPeak = max(atmosphereShadowBlend, max(atmosphereLightBlend, atmosphereFlameBlend))

            // Base sunlit misty sanctuary sky -> deep SF4 midnight-indigo ink in Shadow World (preserving electric-blue VFX!)
            let baseR: CGFloat = 0.62, baseG: CGFloat = 0.68, baseB: CGFloat = 0.72
            let r = baseR * (1 - s * 0.88) + l * 0.12 - fl * 0.14 + (anyCataclysm ? s * 0.12 : 0)
            let g = baseG * (1 - s * 0.84) + l * 0.04 - fl * 0.30
            let b = baseB * (1 - s * 0.68) - l * 0.14 - fl * 0.36
            let skyColor = UIColor(red: max(0.04, min(0.88, r)),
                                   green: max(0.07, min(0.88, g)),
                                   blue: max(0.16, min(0.88, b)),
                                   alpha: 1)
            backgroundColor = skyColor
            scene?.background.contents = skyColor
            scene?.fogColor = skyColor
            scene?.fogStartDistance = CGFloat(13.5 - atmosphereShadowBlend * 7.8)
            scene?.fogEndDistance = CGFloat(56.0 - atmosphereShadowBlend * 38.0)

            // Swap HDR equirectangular IBL seamlessly when entering/exiting Shadow World
            let wantShadowEnv = atmosphereShadowBlend > 0.35
            if wantShadowEnv != activeShadowEnv {
                activeShadowEnv = wantShadowEnv
                if let url = wantShadowEnv ? shadowEnvURL : sunlitEnvURL {
                    scene?.lightingEnvironment.contents = url
                }
            }
            scene?.lightingEnvironment.intensity = CGFloat(1.18 - 0.24 * atmosphereShadowBlend + 0.16 * atmosphereLightBlend)

            ambientLightNode?.light?.intensity = CGFloat(115 - atmosphereShadowBlend * 48 + atmosphereLightBlend * 45)
            keyLightNode?.light?.intensity = CGFloat(1850 - atmosphereShadowBlend * 920 + atmosphereLightBlend * 240)
            if let rim = rimLightNode?.light {
                rim.intensity = CGFloat(1250 + atmosphereShadowBlend * 1550 + atmosphereLightBlend * 320)
                rim.color = UIColor(
                    red: 0.68 * (1 - s) + (anyCataclysm ? 0.95 : 0.16) * s,
                    green: 0.86 * (1 - s) + (anyCataclysm ? 0.24 : 0.84) * s,
                    blue: anyCataclysm ? (1.0 * (1 - s) + 0.22 * s) : 1.0,
                    alpha: 1
                )
            }
            let beamOpacity = CGFloat(max(0, 1 - atmosphereShadowBlend * 1.35))
            for beam in sunbeamNodes {
                beam.opacity = beamOpacity
            }

            if let cam = pointOfView?.camera, cam.wantsHDR {
                // Keep saturation rich enough (~0.62) in Shadow World so electric cyan shadow skills & crimson flames pop!
                cam.saturation = CGFloat(1.08 - 0.44 * atmosphereShadowBlend + 0.10 * atmosphereLightBlend + 0.14 * atmosphereFlameBlend)
                cam.contrast = CGFloat(0.14 + 0.22 * atmosphereShadowBlend + 0.06 * atmosphereLightBlend)
                cam.exposureOffset = CGFloat(-0.08 - 0.18 * atmosphereShadowBlend + 0.06 * atmosphereLightBlend)
                cam.vignettingIntensity = CGFloat(0.32 + 0.44 * formPeak)
                cam.bloomIntensity = isCastingDisplay ? 0.0 : CGFloat(0.14 + 0.22 * formPeak)
            }
        }
        for i in 0..<session.game.fighters.count {
            let f = session.game.fighters[i]
            if i < fighterShadowDiscs.count {
                let disc = fighterShadowDiscs[i]
                let airFactor = max(0.32, 1.0 - Float(f.y) / 2400.0)
                let widthScale: Float = f.knockdown > 0 ? 1.55 : (f.attack?.move.isRoll == true ? 1.18 : 1.0)
                disc.isHidden = false
                disc.position = SCNVector3(Float(f.x) / 1000, 0.025, 0.0)
                disc.scale = SCNVector3(airFactor * widthScale, 1.0, airFactor * 0.78)
                let phased = session.game.midnightState(i)?.isPhasedOut == true
                disc.opacity = CGFloat((phased ? 0.08 : 0.26) * airFactor)
            }
            if originalVFX == nil, let shogun = session.game.shogunState(i), shogun.cataclysmPulseTicks > 0, let ring = slamRing {
                let t = Float(18 - shogun.cataclysmPulseTicks) / 18
                let scale = 0.65 + 2.6 * max(0, t)
                ring.isHidden = false
                ring.geometry?.firstMaterial?.multiply.contents = shogun.isCataclysm ? UIColor.systemRed : UIColor.systemPurple
                ring.opacity = CGFloat(max(0, 1 - t))
                ring.position = SCNVector3(Float(session.game.fighters[i].x) / 1000, 0.05, 0)
                ring.scale = SCNVector3(scale, scale, 1)
            }
        }
        // Read-only sampling: repeated draws, layout, and skipped display
        // frames cannot speed up tracking or drain a confirmed impact.
        if originalVFX == nil, let hold = session.game.grapple {
            let release = DuelGame.Grapple.takedownTicks + DuelGame.Grapple.holdTicks
            let elapsed = hold.age >= release ? hold.age - release : hold.age - DuelGame.Grapple.takedownTicks
            if (0..<18).contains(elapsed), let ring = slamRing {
                let t = Float(elapsed) / 18, scale = 0.55 + 1.85 * t
                ring.isHidden = false; ring.opacity = CGFloat(1 - t)
                ring.geometry?.firstMaterial?.multiply.contents = UIColor.systemOrange
                ring.position = SCNVector3(Float(session.game.fighters[1 - hold.attacker].x) / 1000, 0.04, 0)
                ring.scale = SCNVector3(scale, scale, 1)
            }
        }
        if let spark = hitSpark {
            if hitSparkAge < 10 {
                let t = Float(hitSparkAge) / 10
                spark.isHidden = false
                spark.opacity = CGFloat(1 - t)
                let s = 0.6 + 1.9 * t
                spark.scale = SCNVector3(s, s, s)
            } else {
                spark.isHidden = true
            }
        }
        originalVFX?.sampleBladeTrails(game: session.game, bladeSegments: actors.map { $0.bladeWorldSegments() })
        originalVFX?.updateAuras(session.game)
        let alive = Set(session.game.projectiles.map(\.id))
        for id in Array(bolts.keys) where !alive.contains(id) { bolts.removeValue(forKey: id)?.removeFromParentNode() }
        for projectile in session.game.projectiles {
            let node: SCNNode
            if let existing = bolts[projectile.id] { node = existing }
            else {
                node = (projectile.kind == .shadowKunai || projectile.kind == .emperorShadowDart)
                    ? DuelOriginalVFX.makeShadowKunaiNode()
                    : DuelOriginalVFX.makeSalvationPillarNode()
                bolts[projectile.id] = node; scene?.rootNode.addChildNode(node)
            }
            if projectile.kind == .shadowKunai || projectile.kind == .emperorShadowDart {
                node.position = SCNVector3(Float(projectile.x) / 1000, 1.24, 0.16)
                node.eulerAngles = SCNVector3(Float(session.animationTick) * 0.42,
                                              projectile.direction > 0 ? 0 : .pi, 0)
            } else {
                node.position = SCNVector3(Float(projectile.x) / 1000, 1.35, 0.12)
            }
        }
        SCNTransaction.commit()
        if let frameDriver = triadSurfaceFrameDriver {
            do {
                try frameDriver.drawFrame(tick: session.game.weaponFight?.triadPresentation.liveTick ?? session.animationTick,
                    pointOfView: pointOfView, samples: antialiasingMode == .none ? 1 : 2)
            } catch { triadPreparationFailure = String(describing: error); triadMetalRenderer?.clear(); session.characterFailed() }
        }
    }
    private func triggerDramaticFocus(fighter: DuelGame.Fighter, zoomTicks: Int, slowTicks: Int) {
        guard !session.setup.originalWeapons, !UIAccessibility.isReduceMotionEnabled else { return }
        dramaticFocusX = Float(fighter.x) / 1000
        dramaticFocusY = max(1.05, Float(fighter.y) / 1000 + 1.25)
        if zoomTicks >= dramaticZoomTicks {
            dramaticZoomDuration = max(1, zoomTicks)
            dramaticZoomTicks = zoomTicks
        }
        slowMoTicks = max(slowMoTicks, slowTicks)
    }

    private func consumeFeedback(_ game: DuelGame, tick: Int) {
        guard !ended, game.fighters.count == 2 else { return }
        let impacts: [DuelCombatCamera.Impact]
        if let weaponContacts = game.weaponFight?.contacts {
            impacts = weaponContacts.map { contact in
                DuelCombatCamera.Impact(kind: contact.kind == .block ? .block : contact.heavy ? .heavy : .light,
                                        direction: contact.direction)
            }
        } else {
            originalVFX?.consumeStep(game, tick: tick)
            hitSparkAge = min(99, hitSparkAge + 1)
            let sound = DuelOriginalSound.shared
            // Swing whoosh cues right as each attack begins its strike arc
            for i in 0..<2 {
                let f = game.fighters[i]
                if let attack = f.attack {
                    let key = "\(attack.move.rawValue):\(tick - attack.age)"
                    let data = DuelGame.data(attack.move, hero: f.hero, chargeTicks: attack.chargeTicks, ruleset: game.ruleset)
                    if lastWarnAttackKeys[i] != key,
                       DuelOriginalVFX.unblockableStartupProgress(game, fighter: i) != nil {
                        lastWarnAttackKeys[i] = key
                        sound.play(.unblockableWarn, volume: 0.62)
                    }
                    if attack.age >= max(0, data.startup - 2) && lastAudioAttackKeys[i] != key {
                        lastAudioAttackKeys[i] = key
                        switch attack.move {
                        case .kick, .kickForward, .kickUp, .kickDown, .kickBack, .wakeupKick:
                            sound.play(.kickWhoosh, volume: 0.56)
                        case .rollForward, .rollBack, .dashForward, .dashBack:
                            sound.play(.kickWhoosh, volume: 0.36)
                        case .heavy, .skill2, .shogunFierceReprisal, .shogunDespotism,
                             .inquisitorLightSpin, .inquisitorLightUp, .inquisitorLightForward, .inquisitorLightDown,
                             .midnightRemoval, .emperorTransform, .emperorBeastShadowJump,
                             .legionShadowChain, .legionShadowForward, .legionShadowDown,
                             .monkeyAscensionPlunge, .monkeyHeavenlyPillar:
                            sound.play(.bladeWhooshHeavy, volume: 0.72)
                        case .throwForward, .throwBack:
                            break
                        default:
                            sound.play(.bladeWhooshLight, volume: 0.58)
                        }
                    }
                } else {
                    lastAudioAttackKeys[i] = nil
                    lastWarnAttackKeys[i] = nil
                }
            }
            var eventImpacts: [DuelCombatCamera.Impact] = []
            var playedPrimaryImpactAudio = false
            for event in game.events {
                switch event {
                case .hit(let attacker, let damage):
                    let defender = 1 - attacker
                    let heavy = (game.ruleset == .shadowArena && damage >= 360) || (game.ruleset == .laboratory && damage >= 145)
                    eventImpacts.append(.init(kind: heavy ? .heavy : .light, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: heavy ? .systemOrange : .systemYellow)
                    if heavy {
                        triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 9, slowTicks: 0)
                    }
                    if !playedPrimaryImpactAudio {
                        sound.play(heavy ? .hitHeavy : .hitLight, volume: heavy ? 0.82 : 0.68)
                        if let signature = Self.weaponSignatureCue(for: game.fighters[attacker]) {
                            sound.play(signature, volume: heavy ? 0.78 : 0.62)
                        }
                        playedPrimaryImpactAudio = true
                    }
                case .counterHit(let attacker, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemOrange)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 12, slowTicks: 3)
                    sound.play(.headHit, volume: 0.90)
                    playedPrimaryImpactAudio = true
                case .bladeClash:
                    eventImpacts.append(.init(kind: .heavy, direction: 0))
                    triggerHitSpark(at: game.fighters[0], color: .cyan)
                    triggerDramaticFocus(fighter: game.fighters[0], zoomTicks: 13, slowTicks: 4)
                    sound.play(.blockClang, volume: 0.96)
                    sound.play(.odachiSlice, volume: 0.74)
                    playedPrimaryImpactAudio = true
                case .wallSplat(let defender):
                    eventImpacts.append(.init(kind: .heavy, direction: -game.fighters[defender].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemOrange)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 11, slowTicks: 2)
                    sound.play(.throwSlam, volume: 0.92)
                case .headHit(let attacker, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemYellow)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 11, slowTicks: 2)
                    sound.play(.headHit, volume: 0.88)
                    playedPrimaryImpactAudio = true
                case .criticalHit(let attacker, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemYellow)
                    sound.play(.criticalHit, volume: 0.94)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 14, slowTicks: 6)
                    playedPrimaryImpactAudio = true
                case .throwHit(let attacker, _, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemYellow)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 10, slowTicks: 0)
                    sound.play(.throwSlam, volume: 0.86)
                    playedPrimaryImpactAudio = true
                case .shogunShadowForm(let fighter):
                    sound.play(.shadowActivate, volume: 0.90)
                    triggerDramaticFocus(fighter: game.fighters[fighter], zoomTicks: 26, slowTicks: 14)
                case .shogunCataclysmStrike(let attacker, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemRed)
                    sound.play(.criticalHit, volume: 0.95)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 20, slowTicks: 10)
                    playedPrimaryImpactAudio = true
                case .shogunCritical(let attacker, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemYellow)
                    sound.play(.criticalHit, volume: 0.94)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 16, slowTicks: 8)
                    playedPrimaryImpactAudio = true
                case .shogunCataclysm(let fighter):
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[fighter].facing))
                    sound.play(.shadowActivate, volume: 0.96)
                    triggerDramaticFocus(fighter: game.fighters[fighter], zoomTicks: 30, slowTicks: 16)
                case .shogunCompanionHit:
                    sound.play(.hitLight, volume: 0.65)
                case .emperorTransformed(let fighter, _):
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[fighter].facing))
                    triggerHitSpark(at: game.fighters[fighter], color: .systemPurple)
                    sound.play(.shadowActivate, volume: 0.96)
                    triggerDramaticFocus(fighter: game.fighters[fighter], zoomTicks: 28, slowTicks: 12)
                case .emperorLifesteal:
                    sound.play(.midnightPhase, volume: 0.45)
                case .legionChainSnag(let attacker, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: -game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .cyan)
                    sound.play(.greatswordChime, volume: 0.88)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 14, slowTicks: 4)
                    playedPrimaryImpactAudio = true
                case .legionDarkIncarnation(let fighter):
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[fighter].facing))
                    triggerHitSpark(at: game.fighters[fighter], color: .cyan)
                    sound.play(.shadowActivate, volume: 0.96)
                    triggerDramaticFocus(fighter: game.fighters[fighter], zoomTicks: 28, slowTicks: 12)
                case .monkeyAscensionPerch:
                    sound.play(.kickWhoosh, volume: 0.72)
                case .monkeyPerchEvade:
                    sound.play(.midnightPhase, volume: 0.62)
                case .monkeyPillarSlam(let attacker, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemYellow)
                    sound.play(.throwSlam, volume: 0.92)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 18, slowTicks: 6)
                    playedPrimaryImpactAudio = true
                case .inquisitorStigmataFlash(let attacker, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemYellow)
                    sound.play(.lightForm, volume: 0.88)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 18, slowTicks: 8)
                    playedPrimaryImpactAudio = true
                case .inquisitorSalvationStrike(let attacker, _, let damage),
                     .inquisitorSalvationEcho(let attacker, _, let damage):
                    if damage > 0 {
                        let defender = 1 - attacker
                        eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                        triggerHitSpark(at: game.fighters[defender], color: .systemYellow)
                        sound.play(.lightForm, volume: 0.88)
                        triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 12, slowTicks: 2)
                        playedPrimaryImpactAudio = true
                    } else {
                        sound.play(.lightForm, volume: 0.44)
                    }
                case .inquisitorLightFormBroken(let defender):
                    eventImpacts.append(.init(kind: .heavy, direction: -game.fighters[defender].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemYellow)
                    sound.play(.guardBreak, volume: 0.90)
                case .inquisitorFormOfLight(let fighter):
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[fighter].facing))
                    triggerHitSpark(at: game.fighters[fighter], color: .systemYellow)
                    sound.play(.lightForm, volume: 0.94)
                    triggerDramaticFocus(fighter: game.fighters[fighter], zoomTicks: 28, slowTicks: 14)
                case .nonnaFlameForm(let fighter):
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[fighter].facing))
                    triggerHitSpark(at: game.fighters[fighter], color: .systemOrange)
                    sound.play(.flameForm, volume: 0.94)
                    triggerDramaticFocus(fighter: game.fighters[fighter], zoomTicks: 28, slowTicks: 14)
                case .nonnaWolfHit(let owner, _), .nonnaOwlHit(let owner, _, _):
                    let defender = 1 - owner
                    eventImpacts.append(.init(kind: .light, direction: game.fighters[owner].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemOrange)
                    sound.play(.hitLight, volume: 0.66)
                case .nonnaTrueShapeStrike(let attacker, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemOrange)
                    sound.play(.axeCleave, volume: 0.90)
                    sound.play(.flameForm, volume: 0.52)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 13, slowTicks: 3)
                    playedPrimaryImpactAudio = true
                case .nonnaTrueShapeExecute(let attacker, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemRed)
                    sound.play(.flameForm, volume: 0.95)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 24, slowTicks: 12)
                    playedPrimaryImpactAudio = true
                case .midnightShadowShift:
                    sound.play(.midnightPhase, volume: 0.78)
                case .midnightNocturneBurst(let attacker, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemPurple)
                    sound.play(.criticalHit, volume: 0.92)
                    sound.play(.midnightPhase, volume: 0.76)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 15, slowTicks: 5)
                    playedPrimaryImpactAudio = true
                case .midnightBlinkCounter(let attacker, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemPurple)
                    sound.play(.midnightPhase, volume: 0.90)
                    triggerDramaticFocus(fighter: game.fighters[attacker], zoomTicks: 18, slowTicks: 8)
                    playedPrimaryImpactAudio = true
                case .midnightRemovalStrike(let attacker, _):
                    let defender = 1 - attacker
                    eventImpacts.append(.init(kind: .heavy, direction: game.fighters[attacker].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemPurple)
                    sound.play(.shadowActivate, volume: 0.94)
                    triggerDramaticFocus(fighter: game.fighters[defender], zoomTicks: 26, slowTicks: 14)
                    playedPrimaryImpactAudio = true
                case .blocked(let defender):
                    eventImpacts.append(.init(kind: .block, direction: -game.fighters[defender].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .cyan)
                    sound.play(.blockClang, volume: 0.78)
                case .guardBreak(let defender):
                    eventImpacts.append(.init(kind: .heavy, direction: -game.fighters[defender].facing))
                    triggerHitSpark(at: game.fighters[defender], color: .systemRed)
                    sound.play(.guardBreak, volume: 0.92)
                default:
                    break
                }
            }
            impacts = eventImpacts
        }
        combatCamera.consume(frame: game.frame, animationTick: tick,
                             firstX: Double(game.fighters[0].x) / 1000,
                             secondX: Double(game.fighters[1].x) / 1000, impacts: impacts)
        guard let fight = game.weaponFight else { return }
        consumeSourceMorph(fight)
        do { try erlangSwordEffects?.consume(fight: fight) }
        catch { triadPreparationFailure = String(describing: error); triadMetalRenderer?.clear(); session.characterFailed() }
        do { try erlangStompEffects?.sampleStep(fight) }
        catch { triadPreparationFailure = String(describing: error); triadMetalRenderer?.clear(); session.characterFailed() }
        if let effects = erlangSkillEffects {
            do {
                let transforms = effects.sourceBoneNames(fight).reduce(into: [Int: [String: simd_float4x4]]()) { result, entry in
                    guard actors.indices.contains(entry.key), fight.fighters.indices.contains(entry.key) else { return }
                    result[entry.key] = actors[entry.key].sourceBoneTransforms(entry.value, fighter: fight.fighters[entry.key])
                }
                try effects.sampleStep(fight, bones: transforms)
            } catch {
                triadPreparationFailure = String(describing: error); triadMetalRenderer?.clear(); session.characterFailed()
            }
        }
        if let effects = triadSourceEffects {
            do {
                try effects.consume(fight)
                let transforms = effects.sourceBoneNames.reduce(into: [Int: [String: simd_float4x4]]()) { result, entry in
                    guard actors.indices.contains(entry.key), fight.fighters.indices.contains(entry.key) else { return }
                    result[entry.key] = actors[entry.key].sourceBoneTransforms(entry.value, fighter: fight.fighters[entry.key])
                }
                try effects.sampleStep(fight, bones: transforms)
            } catch {
                triadPreparationFailure = String(describing: error); triadMetalRenderer?.clear(); session.characterFailed()
            }
        }
        panguDiagnostics?.consume(fight.panguPresentation, events: fight.panguPresentationEvents,
                                  frame: fight.frame, fighting: fight.phase == .fighting)
        let contacts = Self.sourceEffectContacts(fight)
        let swings = fight.swings.map {
            DuelSourceEffects.Swing(heavy: $0.heavy, sound: fight.profiles[$0.attacker].isErlang || fight.profiles[$0.attacker].isSerpent ? .silent :
                fight.profiles[$0.attacker].isTriad ? .ninjato :
                !$0.usesWeapon ? .unarmed : fight.profiles[$0.attacker].isPangu ? .pangu :
                fight.profiles[$0.attacker].isKatana ? .katana : .dualHammers)
        }
        // Called for every fixed simulation step, including all catch-up steps.
        // A display frame is not an event queue and must not drop earlier hits.
        let liuIndex = fight.fighters.firstIndex { $0.hero == .liu }
        sourceEffects?.consumeStep(contacts: contacts, swings: swings, animationTick: tick,
                                  liuShadowTick: liuIndex.flatMap { fight.shadowVisual($0)?.tick })
        sourceEffects?.consumePangu(events: fight.panguPresentationEvents, frame: fight.frame,
                                    fighting: fight.phase == .fighting)
        sourceEffects?.consumeTriad(events: fight.triadPresentationEvents, samples: fight.sourceMotionSamples,
            summons: fight.triadPresentation.summons, frame: fight.frame, fighting: fight.phase == .fighting,
            liveTick: fight.triadPresentation.liveTick,
            owners: Set(fight.profiles.indices.filter { fight.profiles[$0].isTriad }),
            motionProfiles: Dictionary(uniqueKeysWithValues: fight.profiles.indices.map { ($0, fight.profiles[$0].id) }))
        sourceEffects?.consumeErlang(samples: fight.sourceMotionSamples,
            models: fight.erlangModels.map { .init(owner: $0.owner, id: $0.id,
                role: $0.role, age: $0.motionTick(at: fight.erlangLiveTick), stateStartedAt: $0.stateStartedAt) },
            events: fight.erlangAudioEvents.map { event in
                let kind: DuelErlangMeditationAudioClock.Kind
                switch event.kind {
                case .meditationStarted: kind = .start
                case .meditationStopped: kind = .stop
                }
                return .init(frame: event.frame, sequence: event.sequence, liveTick: event.liveTick,
                    owner: event.owner, kind: kind)
            },
            stageSHA256: stageAsset?.kind == .palace ? DuelStageAsset.digest : nil,
            frame: fight.frame, fighting: fight.phase == .fighting,
            owners: Set(fight.profiles.indices.filter { fight.profiles[$0].isErlang }))
        sourceEffects?.consumeSerpent(events: fight.serpentEvents, samples: fight.sourceMotionSamples,
            stageSHA256: stageAsset?.kind == .palace ? DuelStageAsset.digest : nil, frame: fight.frame,
            fighting: fight.phase == .fighting,
            owners: Set(fight.profiles.indices.filter { fight.profiles[$0].isSerpent }))
        let skinned = Set(fight.fighters.indices.filter { index in
            sourceWeaponSkinsEnabled && actors.indices.contains(index) &&
                actors[index].supportsSourceTrail(fight.fighters[index].weaponPose?.clip)
        })
        weaponEffects?.consumeStep(poses: Self.weaponEffectPoses(fight, tick: tick, sourceSkinFighters: skinned), animationTick: tick)
    }

    private func consumeSourceMorph(_ fight: DuelWeaponFight) {
        guard let binding = triadSourceMorph, let owner = triadMorphOwner,
              let trigger = triadMorphTrigger else { return }
        do {
            // Source lock 1796, final-victory trigger 12 targets Enemy. Frame
            // 36 is one-based in configuration, hence sample index 35/tick 70.
            // Round wins, another actor's clip and repeated draws cannot fire it.
            if !triadMorphRequested, fight.sourceStance(owner)?.purpose == .finalVictory,
               fight.sourceMotionSamples.contains(where: {
                   $0.owner == owner && $0.clip == trigger.clip &&
                       $0.crosses(sourceFrame: trigger.sourceFrame - 1,
                                  totalSourceFrames: DuelTriadStanceState.Motion.win.frames)
               }) {
                try binding.requestHide(sourceTick: fight.sourcePresentationTick,
                                        transitionTicks: trigger.transitionTicks)
                triadMorphRequested = true
            }
            try binding.update(sourceTick: fight.sourcePresentationTick, paused: session.paused)
        } catch { failSourceMorph(error) }
    }

    private func updateSourceMorph(_ fight: DuelWeaponFight?) {
        guard let binding = triadSourceMorph, let fight else { return }
        do { try binding.update(sourceTick: fight.sourcePresentationTick, paused: session.paused) }
        catch { failSourceMorph(error) }
    }

    private func sourceMorphDidRenderFrame() {
        guard !ended, let binding = triadSourceMorph,
              let fight = session.game.weaponFight else { return }
        do { try binding.didRenderFrame(sourceTick: fight.sourcePresentationTick) }
        catch { failSourceMorph(error) }
    }

    private func failSourceMorph(_ error: Error) {
        triadPreparationFailure = String(describing: error)
        triadMetalRenderer?.clear(); session.characterFailed()
    }
    /// Contact events and the generic impact queue are appended in the same
    /// simulation order. A skill's cue owns its audio even when two contacts
    /// share one position/tick; no coordinate-only lookup may merge them.
    static func sourceEffectContacts(_ fight: DuelWeaponFight) -> [DuelSourceEffects.Contact] {
        let pangu = fight.panguPresentationEvents.compactMap { event -> DuelPanguPresentation.Contact? in
            if case .contact(let value) = event.kind { return value }
            return nil
        }
        var next = 0
        return fight.contacts.map { contact in
            let profile = fight.profiles[contact.attacker]
            let sound: DuelSourceEffects.SoundFamily
            if profile.isTriad {
                sound = contact.authoredAudio ? .silent : contact.usesWeapon ? .ninjato : .unarmed
            } else if profile.isPangu {
                if next < pangu.count, pangu[next].owner == contact.attacker,
                   pangu[next].kind == contact.kind, pangu[next].position == contact.position,
                   pangu[next].direction == contact.direction {
                    sound = pangu[next].attackID == nil ? (contact.usesWeapon ? .pangu : .unarmed) : .silent
                    next += 1
                } else {
                    // Feedback overflow cannot license an unrelated impact sound.
                    sound = .silent
                }
            } else if profile.isErlang || profile.isSerpent {
                // Actual source markers own these profiles' sounds. A contact
                // must not invent a generic fist or dual-hammer impact cue.
                sound = .silent
            } else {
                sound = !contact.usesWeapon ? .unarmed : profile.isKatana ? .katana : .dualHammers
            }
            return .init(kind: contact.kind == .hit ? .hit : .block,
                position: SCNVector3(Float(contact.position.x), Float(contact.position.y), Float(contact.position.z)),
                direction: contact.direction, heavy: contact.heavy, sound: sound)
        }
    }
    /// Read-only adapter shared by native presentation verification.
    static func weaponEffectPoses(_ fight: DuelWeaponFight, tick: Int, sourceSkinFighters: Set<Int> = []) -> [DuelWeaponEffects.Pose] {
        fight.fighters.enumerated().compactMap { index, fighter in
            guard let pose = fighter.weaponPose, let clip = fight.profiles[index].clip(named: pose.clip) else { return nil }
            let profile = fight.profiles[index], tracks = clip.tracks
            // These authenticated trail families belong to the old weapons.
            // Pangu needs its own verified binding before visual activation.
            guard !profile.isPangu && !profile.isTriad else { return nil }
            func world(_ value: DuelWeaponPoint) -> SCNVector3 {
                SCNVector3(Float(fighter.x) / 1000 + Float(value.x) * Float(fighter.facing),
                           Float(value.y + pose.groundLift) + Float(fighter.y) / 1000,
                           Float(value.z) * Float(fighter.facing))
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
                         motionID: fight.weaponTrailIsActive(index) && (fight.shadowIsActive(index) || !sourceSkinFighters.contains(index))
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
    private func place(_ node: SCNNode, box: DuelGame.Box) {
        node.isHidden = false
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
        if !session.setup.originalWeapons {
            buildProceduralStage(root)
            return
        }
        if session.usesVerifiedPreparedResources {
            guard let asset = session.preparedResources?.stage else { session.characterFailed(); return }
            installStage(asset, in: root)
            return
        }
        #if DEBUG
        attemptedBundledStageLoad = true
        #endif
        if let prepared = session.takePreparedLocalPalace(for: self),
           let asset = try? DuelStageAsset(preparedPalace: prepared) {
            installStage(asset, in: root)
            return
        }
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
        sunbeamNodes.forEach { $0.removeFromParentNode() }
        sunbeamNodes.removeAll()

        if let sanctuary = DuelEnvironmentAssetCache.cachedStage() {
            // Genuine sculpted PBR 3D Ancient Mountain Sanctuary Courtyard (Albedo + Normal + Roughness + AO).
            let stageInst = sanctuary.instantiate()
            stageInst.root.name = "duel.sanctuary.glb"
            stageInst.root.enumerateHierarchy { node, _ in
                let nm = (node.name ?? "").lowercased()
                // Main foreground stone arches, columns & woody vines cast crisp sunlight shadows;
                // ground floor, distant cloister, foliage cards & sky dome skip shadow casting for 60fps speed.
                let casts = nm.contains("ruinsstone") || nm.contains("brazieriron") || nm.contains("woodyvines")
                node.castsShadow = casts
                if nm.contains("brazierembers") {
                    for mat in node.geometry?.materials ?? [] {
                        mat.emission.intensity = 2.6
                    }
                }
            }
            root.addChildNode(stageInst.root)

            // Subtle warm flickering amber glow lights inside the two sculpted temple stone braziers
            for bx in [Float(2.25), Float(7.75)] {
                let brazierLight = SCNNode()
                let lt = SCNLight()
                lt.type = .omni
                lt.color = UIColor(red: 1.0, green: 0.50, blue: 0.16, alpha: 1)
                lt.intensity = 145
                lt.attenuationStartDistance = 0.35
                lt.attenuationEndDistance = 4.2
                brazierLight.light = lt
                brazierLight.position = SCNVector3(bx, 1.48, -3.12)
                root.addChildNode(brazierLight)
            }

            // 2 whisper-soft atmospheric sunlit mist haze shafts through the central ruined stone arch (zero harsh bars!)
            let beamSpecs: [(x: Float, y: Float, z: Float, w: CGFloat, h: CGFloat, roll: Float, alpha: CGFloat)] = [
                (4.1, 2.85, -3.70, 2.65, 6.4, -0.43, 0.022),
                (5.4, 2.75, -3.85, 2.40, 6.0, -0.44, 0.026),
            ]
            for spec in beamSpecs {
                let plane = SCNPlane(width: spec.w, height: spec.h)
                let mat = SCNMaterial()
                mat.diffuse.contents = DuelProceduralVFXAssets.smokeWisp
                mat.multiply.contents = UIColor(red: 1.0, green: 0.92, blue: 0.72, alpha: spec.alpha)
                mat.lightingModel = .constant
                mat.blendMode = .add
                mat.isDoubleSided = true
                mat.writesToDepthBuffer = false
                plane.materials = [mat]
                let node = SCNNode(geometry: plane)
                node.position = SCNVector3(spec.x, spec.y, spec.z)
                node.eulerAngles = SCNVector3(0, 0.08, spec.roll)
                node.castsShadow = false
                node.renderingOrder = 6
                root.addChildNode(node)
                sunbeamNodes.append(node)
            }
        } else {
            // Minimal floor fallback only if DuelStage_Sanctuary.glb is absent
            let floorGeom = SCNBox(width: 36.0, height: 0.36, length: 24.0, chamferRadius: 0.04)
            let floorMat = SCNMaterial()
            floorMat.diffuse.contents = DuelProceduralVFXAssets.dojoStone
            floorMat.diffuse.wrapS = .repeat; floorMat.diffuse.wrapT = .repeat
            floorMat.diffuse.contentsTransform = SCNMatrix4MakeScale(7.5, 5.2, 1)
            floorMat.roughness.contents = 0.88; floorMat.metalness.contents = 0.02
            floorMat.lightingModel = .physicallyBased
            floorGeom.materials = [floorMat]
            let floor = SCNNode(geometry: floorGeom)
            floor.position = SCNVector3(5, -0.20, -4.5); floor.castsShadow = false
            root.addChildNode(floor)
        }

        // Subtle soft contact AO disc right beneath boots (complements the real 2048 directional sunlight shadow!)
        fighterShadowDiscs.forEach { $0.removeFromParentNode() }
        fighterShadowDiscs.removeAll()
        for _ in 0..<2 {
            let disc = SCNPlane(width: 1.08, height: 0.72)
            let mat = SCNMaterial()
            mat.diffuse.contents = DuelProceduralVFXAssets.smokeWisp
            mat.multiply.contents = UIColor.black
            mat.lightingModel = .constant
            mat.transparencyMode = .aOne
            mat.writesToDepthBuffer = false
            disc.materials = [mat]
            let node = SCNNode(geometry: disc)
            node.eulerAngles.x = -.pi / 2
            node.position = SCNVector3(5, 0.025, 0)
            node.opacity = 0.26
            node.castsShadow = false
            node.renderingOrder = 2
            root.addChildNode(node)
            fighterShadowDiscs.append(node)
        }

        // Atmospheric sunlit golden dust motes & occasional drifting crimson maple petals
        let petalNode = SCNNode()
        petalNode.position = SCNVector3(5, 2.7, -1.4)
        let petals = SCNParticleSystem()
        petals.particleImage = DuelProceduralVFXAssets.smokeWisp
        petals.particleColor = UIColor(red: 0.96, green: 0.84, blue: 0.56, alpha: 0.38)
        petals.birthRate = 5.0
        petals.particleLifeSpan = 6.2
        petals.particleLifeSpanVariation = 2.0
        petals.particleSize = 0.042
        petals.particleSizeVariation = 0.020
        petals.particleVelocity = 0.34
        petals.particleVelocityVariation = 0.14
        petals.spreadingAngle = 35
        petals.emittingDirection = SCNVector3(-0.75, -0.65, 0.1)
        petals.emitterShape = SCNBox(width: 12.0, height: 1.2, length: 3.5, chamferRadius: 0)
        petals.blendMode = .alpha
        petals.isLightingEnabled = false
        petals.isAffectedByGravity = false
        petalNode.addParticleSystem(petals)
        root.addChildNode(petalNode)
    }
    /// Per-hero weapon impact signature layered over the generic hit body so each
    /// weapon reads differently (Odachi shing, Axe chop, Greatsword chime, twin Ninjato).
    static func weaponSignatureCue(for attacker: DuelGame.Fighter) -> DuelOriginalAudioPCM.Cue? {
        guard let move = attacker.attack?.move else { return nil }
        switch move {
        case .kick, .kickForward, .kickUp, .kickDown, .kickBack, .wakeupKick, .throwForward, .throwBack, .rollForward, .rollBack:
            return nil
        case .skill1 where attacker.hero == .wuYong:
            return nil  // Shogun skill1 is a kick.
        default:
            break
        }
        switch attacker.hero {
        case .wuYong: return .odachiSlice
        case .liu: return .axeCleave
        case .gale: return .greatswordChime
        case .ember: return .ninjatoTwinSlice
        }
    }

    private func triggerHitSpark(at fighter: DuelGame.Fighter, color: UIColor) {
        guard originalVFX == nil, let spark = hitSpark else { return }
        hitSparkAge = 0
        spark.position = SCNVector3(Float(fighter.x) / 1000, Float(fighter.y) / 1000 + 1.05, 0.35)
        spark.geometry?.firstMaterial?.multiply.contents = color
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
    private var weaponBlades: [SCNNode] = []
    private var feet: [SCNNode] = []
    private let character: DuelCharacterInstance?
    private let original: DuelOriginalCombatInstance?
    private let weapon: DuelWeaponCharacterInstance?
    private let cascadeur: DuelCascadeurCharacterInstance?
    func installSourceMorph(_ prepared: DuelTriadSourceMorph.Prepared,
                            materials: [DuelTriadSourceMorph.MaterialBinding]) throws -> DuelTriadSourceMorph.Binding {
        guard let weapon else { throw DuelTriadSourceMorph.Failure.geometry }
        let scene = try DuelSerpentHeadlessMorphScene.select(asset: weapon.asset,
            instance: weapon.instance, materials: materials)
        return try prepared.install(on: scene.instance, materials: scene.materials)
    }
    func sourceShadowInstance() throws -> GLTFModel.Instance {
        guard let weapon else { throw DuelSourceProjectedShadowRenderer.Failure.geometry }
        return weapon.instance
    }
    func updateSourceLighting(_ viewTransform: simd_float4x4) {
        weapon?.materialBinding?.update(viewTransform: viewTransform)
    }
    func supportsSourceTrail(_ clip: String?) -> Bool {
        guard let clip else { return false }
        return weapon?.sourceTrailBinding?.supports(clip) == true
    }
    func hasAttachedWeapon(_ asset: DuelWeaponCharacterAsset) -> Bool {
        guard let weapon else { return false }
        return weapon.asset === asset && weapon.instance.root.parent === root
    }
    func bladeWorldSegments() -> [(base: SIMD3<Float>, tip: SIMD3<Float>)] {
        cascadeur?.weaponBladeWorldSegments() ?? []
    }
    init(hero: DuelGame.Hero, asset: DuelCharacterAsset?, originalAsset: DuelOriginalRigAsset? = nil,
         weaponAsset: DuelWeaponCharacterAsset? = nil, cascadeurAsset: DuelCascadeurCharacterAsset? = nil) {
        character = asset.map { DuelCharacterInstance($0) }
        original = originalAsset.map { DuelOriginalCombatInstance($0) }
        weapon = weaponAsset.map { DuelWeaponCharacterInstance($0) }
        cascadeur = cascadeurAsset.map { DuelCascadeurCharacterInstance($0) }
        let color: UIColor = hero == .wuYong ? UIColor(red: 0.56, green: 0.10, blue: 0.14, alpha: 1) :
            hero == .gale ? UIColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1) :
            hero == .liu ? UIColor(red: 0.24, green: 0.10, blue: 0.12, alpha: 1) :
            UIColor(red: 0.12, green: 0.28, blue: 0.22, alpha: 1)
        let dark = UIColor(red: 0.10, green: 0.13, blue: 0.22, alpha: 1)
        let gold = UIColor(red: 0.86, green: 0.68, blue: 0.26, alpha: 1)
        let crimson = UIColor(red: 0.72, green: 0.12, blue: 0.14, alpha: 1)
        let skin = UIColor(red: 0.68, green: 0.48, blue: 0.35, alpha: 1)
        body = Self.shape(SCNCapsule(capRadius: hero == .liu ? 0.28 : hero == .wuYong ? 0.28 : 0.25, height: 0.72), color)
        body.position.y = 1.08; root.addChildNode(body)
        let head = Self.shape(SCNSphere(radius: 0.23), hero == .wuYong ? dark : skin)
        head.name = "head"; head.position.y = 1.67; root.addChildNode(head)
        let visor = Self.shape(SCNBox(width: 0.30, height: 0.09, length: 0.08, chamferRadius: 0.04), hero == .wuYong ? gold : hero == .ember ? UIColor.systemPurple : dark)
        visor.position = SCNVector3(0, 1.69, 0.20)
        if hero == .wuYong || hero == .ember { root.addChildNode(visor) }
        if hero == .wuYong {
            // Shogun kabuto golden crescent crest + broad samurai pauldrons.
            let crest = Self.shape(SCNTorus(ringRadius: 0.18, pipeRadius: 0.024), gold)
            crest.position = SCNVector3(0, 1.94, 0.15); crest.eulerAngles.x = .pi / 2; crest.scale = SCNVector3(1.15, 0.65, 1)
            root.addChildNode(crest)
            for sx in [Float(-0.39), Float(0.39)] {
                let pauldron = Self.shape(SCNBox(width: 0.20, height: 0.24, length: 0.30, chamferRadius: 0.04), color)
                pauldron.position = SCNVector3(sx, 1.38, 0); pauldron.eulerAngles.z = sx > 0 ? -0.30 : 0.30
                root.addChildNode(pauldron)
            }
        } else if hero == .gale {
            // Grand Inquisitor Templar crimson cross tabard + golden shoulder guards.
            let crossV = Self.shape(SCNBox(width: 0.09, height: 0.44, length: 0.04, chamferRadius: 0.01), crimson)
            crossV.position = SCNVector3(0, 1.12, 0.26); root.addChildNode(crossV)
            let crossH = Self.shape(SCNBox(width: 0.30, height: 0.09, length: 0.04, chamferRadius: 0.01), crimson)
            crossH.position = SCNVector3(0, 1.22, 0.26); root.addChildNode(crossH)
            for sx in [Float(-0.37), Float(0.37)] {
                let pauldron = Self.shape(SCNBox(width: 0.19, height: 0.20, length: 0.26, chamferRadius: 0.05), gold)
                pauldron.position = SCNVector3(sx, 1.38, 0); pauldron.eulerAngles.z = sx > 0 ? -0.24 : 0.24
                root.addChildNode(pauldron)
            }
        } else if hero == .liu {
            // Nonna floral/flame berserker shoulder crowns + crimson sash.
            let hair = Self.shape(SCNCapsule(capRadius: 0.225, height: 0.30), dark)
            hair.scale = SCNVector3(1, 0.40, 1); hair.position = SCNVector3(0, 1.83, -0.015); root.addChildNode(hair)
            for sx in [Float(-0.38), Float(0.38)] {
                let flower = Self.shape(SCNSphere(radius: 0.14), UIColor(red: 0.88, green: 0.28, blue: 0.16, alpha: 1))
                flower.scale = SCNVector3(1.1, 0.72, 1.1); flower.position = SCNVector3(sx, 1.40, 0)
                root.addChildNode(flower)
            }
            let sash = Self.shape(SCNBox(width: 0.16, height: 0.56, length: 0.05, chamferRadius: 0.02), UIColor.systemOrange)
            sash.position = SCNVector3(0, 1.12, 0.26); sash.eulerAngles.z = 0.25; root.addChildNode(sash)
        } else if hero == .ember {
            // Midnight dark emerald assassin hood/hair + violet shadow scarf.
            let hair = Self.shape(SCNCapsule(capRadius: 0.23, height: 0.30), dark)
            hair.scale = SCNVector3(1, 0.44, 1); hair.position = SCNVector3(0, 1.82, -0.015); root.addChildNode(hair)
            let scarf = Self.shape(SCNTorus(ringRadius: 0.24, pipeRadius: 0.055), UIColor(red: 0.34, green: 0.14, blue: 0.54, alpha: 1))
            scarf.position = SCNVector3(0, 1.44, 0); root.addChildNode(scarf)
        }
        let belt = Self.shape(SCNBox(width: 0.53, height: 0.16, length: 0.32, chamferRadius: 0.06), hero == .wuYong || hero == .gale ? gold : dark)
        belt.name = "hip"; belt.position.y = 0.74; root.addChildNode(belt)
        for (joint, elbow, x) in [(leftArm, leftElbow, Float(-0.37)), (rightArm, rightElbow, Float(0.37))] {
            joint.position = SCNVector3(x, 1.33, 0); root.addChildNode(joint)
            let arm = Self.shape(SCNCapsule(capRadius: 0.105, height: 0.30), hero == .gale ? color : dark)
            arm.position.y = -0.13; joint.addChildNode(arm)
            elbow.position.y = -0.28; joint.addChildNode(elbow)
            let forearm = Self.shape(SCNCapsule(capRadius: 0.09, height: 0.24), hero == .gale ? color : dark)
            forearm.position.y = -0.10; elbow.addChildNode(forearm)
            let fist = Self.shape(SCNBox(width: 0.21, height: 0.22, length: 0.25, chamferRadius: 0.08), skin)
            fist.name = x < 0 ? "duel.hand.left" : "duel.hand.right"
            fist.position = SCNVector3(0, -0.24, 0.04); elbow.addChildNode(fist)
        }
        let steel = UIColor(white: 0.85, alpha: 1)
        if hero == .wuYong {
            // Long curved-silhouette Odachi mounted on right hand socket.
            let weaponRoot = SCNNode(); weaponRoot.name = "duel.procedural.odachi"
            weaponRoot.position = SCNVector3(0, -0.25, 0.10)
            let hilt = Self.shape(SCNCylinder(radius: 0.025, height: 0.34), dark)
            hilt.position = SCNVector3(0, 0, -0.04); hilt.eulerAngles.x = .pi / 2
            let guardPlate = Self.shape(SCNBox(width: 0.14, height: 0.14, length: 0.025, chamferRadius: 0.01), gold)
            guardPlate.position = SCNVector3(0, 0, 0.13)
            let blade = Self.shape(SCNBox(width: 0.032, height: 0.095, length: 1.48, chamferRadius: 0.008), steel)
            blade.geometry?.firstMaterial?.metalness.contents = 0.85
            blade.geometry?.firstMaterial?.roughness.contents = 0.22
            blade.position = SCNVector3(0, 0.01, 0.88)
            weaponRoot.addChildNode(hilt); weaponRoot.addChildNode(guardPlate); weaponRoot.addChildNode(blade)
            rightElbow.addChildNode(weaponRoot); weaponBlades.append(blade)
        } else if hero == .gale {
            // Grand Inquisitor Cruciform Greatsword (right hand) + Holy Tome (left hand).
            let swordRoot = SCNNode(); swordRoot.name = "duel.procedural.greatsword"
            swordRoot.position = SCNVector3(0, -0.25, 0.10)
            let hilt = Self.shape(SCNCylinder(radius: 0.026, height: 0.36), dark)
            hilt.position = SCNVector3(0, 0, -0.04); hilt.eulerAngles.x = .pi / 2
            let crossGuard = Self.shape(SCNBox(width: 0.34, height: 0.055, length: 0.045, chamferRadius: 0.01), gold)
            crossGuard.position = SCNVector3(0, 0, 0.14)
            let blade = Self.shape(SCNBox(width: 0.042, height: 0.13, length: 1.42, chamferRadius: 0.01), steel)
            blade.geometry?.firstMaterial?.metalness.contents = 0.88
            blade.geometry?.firstMaterial?.roughness.contents = 0.20
            blade.position = SCNVector3(0, 0, 0.86)
            swordRoot.addChildNode(hilt); swordRoot.addChildNode(crossGuard); swordRoot.addChildNode(blade)
            rightElbow.addChildNode(swordRoot); weaponBlades.append(blade)
            let tome = Self.shape(SCNBox(width: 0.22, height: 0.28, length: 0.07, chamferRadius: 0.015), gold)
            tome.position = SCNVector3(0, -0.24, 0.14)
            leftElbow.addChildNode(tome); weaponBlades.append(tome)
        } else if hero == .liu {
            // Nonna Two-Handed Floral/Flame Great Axe.
            let axeRoot = SCNNode(); axeRoot.name = "duel.procedural.greataxe"
            axeRoot.position = SCNVector3(0, -0.25, 0.10)
            let shaft = Self.shape(SCNCylinder(radius: 0.030, height: 1.50), UIColor(red: 0.32, green: 0.18, blue: 0.10, alpha: 1))
            shaft.position = SCNVector3(0, 0, 0.45); shaft.eulerAngles.x = .pi / 2
            let headBlade = Self.shape(SCNBox(width: 0.05, height: 0.44, length: 0.38, chamferRadius: 0.03), steel)
            headBlade.geometry?.firstMaterial?.metalness.contents = 0.84
            headBlade.geometry?.firstMaterial?.roughness.contents = 0.25
            headBlade.position = SCNVector3(0, 0.06, 1.06)
            let collar = Self.shape(SCNSphere(radius: 0.075), UIColor.systemOrange)
            collar.position = SCNVector3(0, 0, 1.06)
            axeRoot.addChildNode(shaft); axeRoot.addChildNode(headBlade); axeRoot.addChildNode(collar)
            rightElbow.addChildNode(axeRoot); weaponBlades.append(headBlade)
        } else if hero == .ember {
            // Midnight Dual Ninjato Blades (both hands!).
            for (elbowNode, name) in [(rightElbow, "duel.procedural.ninjato.r"), (leftElbow, "duel.procedural.ninjato.l")] {
                let knifeRoot = SCNNode(); knifeRoot.name = name
                knifeRoot.position = SCNVector3(0, -0.24, 0.10)
                let hilt = Self.shape(SCNCylinder(radius: 0.022, height: 0.24), dark)
                hilt.position = SCNVector3(0, 0, -0.02); hilt.eulerAngles.x = .pi / 2
                let tsuba = Self.shape(SCNBox(width: 0.10, height: 0.10, length: 0.02, chamferRadius: 0.01), UIColor.systemPurple)
                tsuba.position = SCNVector3(0, 0, 0.10)
                let blade = Self.shape(SCNBox(width: 0.028, height: 0.072, length: 0.86, chamferRadius: 0.006), steel)
                blade.geometry?.firstMaterial?.metalness.contents = 0.90
                blade.geometry?.firstMaterial?.roughness.contents = 0.18
                blade.position = SCNVector3(0, 0, 0.54)
                knifeRoot.addChildNode(hilt); knifeRoot.addChildNode(tsuba); knifeRoot.addChildNode(blade)
                elbowNode.addChildNode(knifeRoot); weaponBlades.append(blade)
            }
        }
        for (joint, knee, x) in [(leftLeg, leftKnee, Float(-0.17)), (rightLeg, rightKnee, Float(0.17))] {
            joint.position = SCNVector3(x, 0.72, 0); root.addChildNode(joint)
            let leg = Self.shape(SCNCapsule(capRadius: 0.115, height: 0.35), dark); leg.position.y = -0.15; joint.addChildNode(leg)
            knee.position.y = -0.32; joint.addChildNode(knee)
            let shin = Self.shape(SCNCapsule(capRadius: 0.10, height: 0.34), dark); shin.position.y = -0.15; knee.addChildNode(shin)
            let foot = Self.shape(SCNBox(width: 0.24, height: 0.15, length: 0.40, chamferRadius: 0.05), hero == .liu || hero == .ember ? dark : color)
            foot.name = x < 0 ? "duel.foot.left" : "duel.foot.right"
            foot.position = SCNVector3(0, -0.33, 0.09); knee.addChildNode(foot); feet.append(foot)
        }
        shield = DuelOriginalVFX.makeGuardWardNode()
        shield.position = SCNVector3(0, 1.05, 0.48); shield.isHidden = true
        root.addChildNode(shield)
        if let presentedRoot = weapon?.instance.root ?? cascadeur?.root ?? original?.instance.root ?? character?.instance.root {
            for child in root.childNodes where child !== shield { child.isHidden = true }
            root.addChildNode(presentedRoot)
        }
    }
    func appendDisplayedCameraPoints(view: simd_float4x4, to points: inout [SIMD3<Float>]) throws {
        guard !root.isHidden else { return }
        guard let weapon else { throw DuelDisplayedSkinBounds.Failure.unsupportedGeometry }
        if let failure = weapon.displayedBoundsFailure { throw failure }
        guard let bounds = weapon.displayedBounds else { throw DuelDisplayedSkinBounds.Failure.unsupportedGeometry }
        try bounds.appendCameraPoints(view: view, to: &points)
    }
    private func bone(_ name: String) -> SCNNode? { original?.bone(name) ?? character?.bone(name) }
    func sourceBoneTransform(_ name: String) -> simd_float4x4? {
        guard let weapon, let index = weapon.asset.model.node(named: name),
              weapon.instance.nodes.indices.contains(index) else { return nil }
        return weapon.instance.nodes[index].simdWorldTransform
    }
    func sourceBoneTransforms(_ names: Set<String>, fighter: DuelGame.Fighter) -> [String: simd_float4x4] {
        weapon?.asset.sourceBoneTransforms(names, fighter: fighter) ?? [:]
    }
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
            let heldArm = hold.direction > 0 ? other.rightArm : other.leftArm
            heldArm.eulerAngles.x = -3.85 * fall * fall * (3 - 2 * fall)
        } else if let shoulder = bone("upper_arm.\(suffix)"),
                  let capturedShoulder = other.bone("upper_arm.\(suffix)") {
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
        root.simdOrientation = simd_quatf(angle: worldRoll, axis: SIMD3<Float>(0, 0, 1)) *
            simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    }
    func leftHandWorldPosition(fallback: SIMD3<Float>) -> SIMD3<Float> {
        if let cascadeur {
            return cascadeur.leftHandWorldPosition(fallback: fallback)
        }
        return fallback
    }
    func pose(_ fighter: DuelGame.Fighter, frame: Int, grapple: DuelGame.Grapple?, index: Int, phase: DuelGame.Phase, shadow: DuelShadowVisual? = nil, sourceTrailActive: Bool = false, sourceTrailEnabled: Bool = true, shogun: DuelShogunState? = nil, arenaKit: DuelArenaKitState? = nil, hitStopShiverX: Float = 0) {
        if let weapon {
            weapon.pose(fighter, root: root, shadow: shadow); shield.isHidden = true
            weapon.sourceTrailBinding?.update(clip: fighter.weaponPose?.clip ?? "",
                active: sourceTrailActive && shadow == nil,
                phaseBps: fighter.weaponPose.map { Int(($0.phase * 10_000).rounded()) },
                enabled: sourceTrailEnabled && phase == .fighting && shadow == nil)
            return
        }
        if let cascadeur {
            cascadeur.pose(fighter, tick: frame, grapple: grapple, index: index, phase: phase, shogun: shogun, arenaKit: arenaKit, hitStopShiverX: hitStopShiverX, root: root)
            shield.isHidden = !(fighter.guarding && fighter.stun > 0) || grapple != nil
            return
        }
        if let original {
            original.pose(fighter, tick: frame, grapple: grapple, index: index, phase: phase, root: root)
            shield.isHidden = !(fighter.guarding && fighter.stun > 0) || grapple != nil
            return
        }
        if let character {
            character.pose(fighter, tick: frame, grapple: grapple, index: index, phase: phase, root: root)
            shield.isHidden = !(fighter.guarding && fighter.stun > 0) || grapple != nil
            return
        }
        root.position = SCNVector3(Float(fighter.x) / 1000 + hitStopShiverX, Float(fighter.y) / 1000, 0)
        let yaw: Float = fighter.facing > 0 ? .pi / 2 : -.pi / 2
        orient(yaw: yaw, worldRoll: fighter.knockdown > 0 ? Float(fighter.facing) * -.pi / 2 : 0)
        if fighter.knockdown > 0 { root.position.y = 0.25; root.position.x -= Float(fighter.facing) * 0.95 }
        for joint in [leftElbow, rightElbow, leftKnee, rightKnee] { joint.eulerAngles = SCNVector3Zero }
        for foot in feet { foot.eulerAngles = SCNVector3Zero }
        let swing = fighter.walking ? sin(Float(frame) * 0.24) * 0.5 : 0
        leftLeg.eulerAngles.x = swing; rightLeg.eulerAngles.x = -swing
        leftArm.eulerAngles.x = -0.35 - swing * 0.3; rightArm.eulerAngles.x = -0.35 + swing * 0.3
        if fighter.y > 0 { leftLeg.eulerAngles.x = -0.7; rightLeg.eulerAngles.x = 0.45 }
        shield.isHidden = !(fighter.guarding && fighter.stun > 0)
        if fighter.guarding && fighter.stun > 0 { leftArm.eulerAngles.x = -1.2; rightArm.eulerAngles.x = -1.4 }
        if let shogun, shogun.heavyChargeTicks > 0 {
            let ratio = min(1, Float(shogun.heavyChargeTicks) / Float(DuelShogunState.heavyFullChargeTicks))
            rightArm.eulerAngles.x = 0.85 + 0.55 * ratio
            leftArm.eulerAngles.x = 0.65 + 0.40 * ratio
            orient(yaw: yaw, worldRoll: Float(fighter.facing) * 0.14 * ratio)
        }
        var armoredPose = false
        if let attack = fighter.attack {
            let data = DuelGame.data(attack.move, hero: fighter.hero, chargeTicks: attack.chargeTicks, ruleset: .shadowArena)
            armoredPose = data.armorStart >= 0 && attack.age >= data.armorStart && attack.age < data.armorEnd
            let recovery = Float(max(0, attack.age - data.startup - data.active)) / Float(max(1, data.recovery))
            let pose: Float = attack.age < data.startup ? 0.5 : -1.65 + min(1, recovery) * 1.3
            if fighter.hero == .wuYong && attack.move == .skill1 {
                let kickPhase: Float = attack.age < data.startup ? 0.4 : -1.45 + min(1, recovery) * 1.15
                rightLeg.eulerAngles.x = kickPhase
                rightKnee.eulerAngles.x = attack.age < data.startup ? 1.1 : 0.15
                orient(yaw: yaw, worldRoll: -Float(fighter.facing) * 0.12)
            } else if fighter.hero == .wuYong && attack.move == .shogunFierceReprisal {
                rightArm.eulerAngles.x = attack.age < data.startup ? -2.3 : -0.35 + min(1, recovery) * 0.8
                leftArm.eulerAngles.x = -1.6
                orient(yaw: yaw, worldRoll: -Float(fighter.facing) * 0.22)
            } else if fighter.hero == .wuYong && attack.move == .shogunDespotism {
                rightArm.eulerAngles.x = attack.age < data.startup ? 0.45 : -2.25 + min(1, recovery) * 1.5
                leftArm.eulerAngles.x = -0.9
            } else if attack.move == .inquisitorLightSpin {
                // Tower's Dogma: full spinning golden greatsword cleave!
                let spin = Float(attack.age) / Float(max(1, data.duration)) * .pi * 2 * Float(fighter.facing)
                rightArm.eulerAngles.x = -1.45; leftArm.eulerAngles.x = -1.20
                orient(yaw: yaw + spin, worldRoll: -Float(fighter.facing) * 0.14)
            } else if attack.move == .midnightRemoval {
                // Midnight Removal: dual-ninjato cross execute!
                let crossPose: Float = attack.age < data.startup ? 0.65 : -1.95 + min(1, recovery) * 1.4
                rightArm.eulerAngles.x = crossPose; leftArm.eulerAngles.x = crossPose
                orient(yaw: yaw, worldRoll: -Float(fighter.facing) * 0.20)
            } else {
                if attack.move == .cross { leftArm.eulerAngles.x = pose }
                else { rightArm.eulerAngles.x = pose }
                if attack.move == .heavy || attack.move == .skill2 { leftArm.eulerAngles.x = pose }
                if attack.move == .ultimate {
                    leftArm.eulerAngles.x = -0.75; rightArm.eulerAngles.x = -0.8
                    leftElbow.eulerAngles.x = -0.45; rightElbow.eulerAngles.x = -0.40
                    orient(yaw: yaw, worldRoll: -Float(fighter.facing) * 0.10)
                }
            }
        }
        if let hold = grapple {
            shield.isHidden = true
            let fall = min(1, Float(hold.age) / Float(DuelGame.Grapple.takedownTicks))
            let eased = fall * fall * (3 - 2 * fall)
            let release = max(0, Float(hold.age - DuelGame.Grapple.takedownTicks - DuelGame.Grapple.holdTicks) / Float(DuelGame.Grapple.releaseTicks))
            let direction = Float(hold.direction)
            if index == hold.attacker {
                let crouch = eased * (1 - release)
                root.position.x -= direction * 0.05 * crouch
                root.position.y = -0.38 * crouch; root.position.z = 0.55 * eased
                orient(yaw: yaw, worldRoll: -direction * 0.20 * crouch)
                leftLeg.eulerAngles.x = -0.90 * crouch; rightLeg.eulerAngles.x = -0.82 * crouch
                leftKnee.eulerAngles.x = 2.38 * crouch; rightKnee.eulerAngles.x = 2.36 * crouch
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
        // Midnight Shadow Shift: phase transparently out!
        if case .midnight(let mid) = arenaKit, mid.isPhasedOut {
            root.opacity = 0.24
        } else {
            root.opacity = 1.0
        }
        let bodyEmission: UIColor
        let bladeEmission: UIColor
        if fighter.flash > 0 {
            bodyEmission = UIColor(red: 0.25, green: 0.10, blue: 0.02, alpha: 1)
            bladeEmission = UIColor.black
        } else if let shogun, shogun.isCataclysm {
            bodyEmission = UIColor(red: 0.42, green: 0.04, blue: 0.10, alpha: 1)
            bladeEmission = UIColor(red: 0.72, green: 0.08, blue: 0.16, alpha: 1)
        } else if let shogun, shogun.isInShadow {
            bodyEmission = UIColor(red: 0.18, green: 0.05, blue: 0.32, alpha: 1)
            bladeEmission = UIColor(red: 0.35, green: 0.10, blue: 0.65, alpha: 1)
        } else if let shogun, shogun.heavyChargeTicks > 0 {
            let r = CGFloat(min(1, Float(shogun.heavyChargeTicks) / Float(DuelShogunState.heavyFullChargeTicks)))
            bodyEmission = UIColor(red: 0.35 * r, green: 0.20 * r, blue: 0.02, alpha: 1)
            bladeEmission = UIColor(red: 0.60, green: 0.36, blue: 0.05, alpha: 1)
        } else if case .inquisitor(let inq) = arenaKit, inq.isInFormOfLight {
            bodyEmission = UIColor(red: 0.44, green: 0.32, blue: 0.06, alpha: 1)
            bladeEmission = UIColor(red: 0.78, green: 0.58, blue: 0.10, alpha: 1)
        } else if case .nonna(let nonna) = arenaKit, nonna.isInFlameForm {
            bodyEmission = UIColor(red: 0.50, green: 0.14, blue: 0.03, alpha: 1)
            bladeEmission = UIColor(red: 0.85, green: 0.26, blue: 0.04, alpha: 1)
        } else if case .nonna(let nonna) = arenaKit, nonna.empoweredStrikeReady {
            bodyEmission = UIColor(red: 0.22, green: 0.08, blue: 0.02, alpha: 1)
            bladeEmission = UIColor(red: 0.64, green: 0.28, blue: 0.04, alpha: 1)
        } else if case .midnight(let mid) = arenaKit, mid.isPhasedOut {
            bodyEmission = UIColor(red: 0.24, green: 0.08, blue: 0.52, alpha: 1)
            bladeEmission = UIColor(red: 0.42, green: 0.14, blue: 0.74, alpha: 1)
        } else if case .midnight(let mid) = arenaKit, mid.isInBlinkStance {
            bodyEmission = UIColor(red: 0.14, green: 0.28, blue: 0.42, alpha: 1)
            bladeEmission = UIColor(red: 0.28, green: 0.58, blue: 0.82, alpha: 1)
        } else if case .midnight(let mid) = arenaKit, mid.isInShadowForm {
            bodyEmission = UIColor(red: 0.20, green: 0.04, blue: 0.36, alpha: 1)
            bladeEmission = UIColor(red: 0.52, green: 0.10, blue: 0.78, alpha: 1)
        } else if armoredPose {
            bodyEmission = UIColor(red: 0.32, green: 0.26, blue: 0.08, alpha: 1)
            bladeEmission = UIColor(red: 0.45, green: 0.34, blue: 0.10, alpha: 1)
        } else {
            bodyEmission = UIColor.black
            bladeEmission = UIColor.black
        }
        body.geometry?.firstMaterial?.emission.contents = bodyEmission
        for blade in weaponBlades {
            blade.geometry?.firstMaterial?.emission.contents = bladeEmission
        }
    }
}

/// Renders Wu Yong's asynchronous Shadow Retinue phantom samurai (死士随从 / Absolute Power)
/// using the sculpted dark-lacquer PBR armored samurai + kabuto + odachi GLB.
@MainActor
private final class DuelShogunCompanionNode {
    let root = SCNNode()
    private let rig = SCNNode()
    private let smokeAnchor = SCNNode()
    private var armorMaterials: [SCNMaterial] = []
    private let inkSmoke = SCNParticleSystem()
    private var currentZ: Float = -0.68

    init() {
        root.opacity = 0.90
        root.addChildNode(rig)

        if let model = DuelEnvironmentAssetCache.cachedRetainer() {
            let inst = model.instantiate()
            inst.root.enumerateHierarchy { node, _ in
                node.castsShadow = (node.geometry != nil)
                for mat in node.geometry?.materials ?? [] {
                    let matName = (mat.name ?? "").lowercased()
                    if matName.contains("eye") {
                        mat.emission.intensity = 3.2
                    } else {
                        armorMaterials.append(mat)
                    }
                }
            }
            rig.addChildNode(inst.root)
        }

        smokeAnchor.position = SCNVector3(0, 0.95, 0)
        rig.addChildNode(smokeAnchor)

        // Billowing obsidian ink-smoke wisps around the dark armored retainer
        inkSmoke.particleImage = DuelProceduralVFXAssets.smokeWisp
        inkSmoke.particleColor = UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 0.62)
        inkSmoke.birthRate = 16
        inkSmoke.particleLifeSpan = 0.60
        inkSmoke.particleSize = 0.34
        inkSmoke.particleSizeVariation = 0.14
        inkSmoke.particleVelocity = 0.42
        inkSmoke.spreadingAngle = 32
        inkSmoke.emittingDirection = SCNVector3(0, 1, 0)
        inkSmoke.blendMode = .alpha
        inkSmoke.isLightingEnabled = false
        smokeAnchor.addParticleSystem(inkSmoke)
    }

    func pose(_ shogun: DuelShogunState, frame: Int) {
        // DuelProp_ShogunRetainer.glb faces +X at yaw = 0 and -X at yaw = .pi.
        let yaw: Float = shogun.companionFacing > 0 ? 0 : .pi
        let breath = sin(Float(frame) * 0.16) * 0.018
        let unconscious = shogun.companionPhase == .unconscious
        let targetZ: Float = shogun.companionPhase == .strike ? -0.24 : -0.68
        currentZ += (targetZ - currentZ) * 0.25

        let lungeX: Float
        let leanForward: Float
        let armorEmission: UIColor
        switch shogun.companionPhase {
        case .follow:
            lungeX = 0
            leanForward = 0.04 + sin(Float(frame) * 0.16) * 0.02
            armorEmission = shogun.agonyRemainingTicks > 0
                ? UIColor(red: 0.32, green: 0.05, blue: 0.05, alpha: 1)
                : UIColor.black
        case .windup:
            lungeX = -Float(shogun.companionFacing) * 0.12
            leanForward = -0.14
            armorEmission = UIColor(red: 0.04, green: 0.14, blue: 0.22, alpha: 1)
        case .strike:
            lungeX = Float(shogun.companionFacing) * 0.26
            leanForward = 0.28
            armorEmission = UIColor(red: 0.08, green: 0.28, blue: 0.40, alpha: 1)
        case .recover:
            lungeX = Float(shogun.companionFacing) * 0.08
            leanForward = 0.10
            armorEmission = UIColor(red: 0.03, green: 0.10, blue: 0.16, alpha: 1)
        case .unconscious:
            lungeX = 0
            leanForward = -.pi / 2
            armorEmission = UIColor.black
        }

        root.position = SCNVector3(
            Float(shogun.companionX) / 1000 + lungeX,
            unconscious ? 0.14 : 0.01 + breath,
            currentZ
        )
        root.simdOrientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        // Negative local Z rotation tilts +Y forward toward local +X.
        rig.eulerAngles = SCNVector3(0, 0, -leanForward)
        root.opacity = unconscious ? 0.55 : (shogun.companionPhase == .strike ? 0.96 : 0.88)
        inkSmoke.birthRate = unconscious ? 0 : (shogun.companionPhase == .strike ? 28 : 14)

        for mat in armorMaterials {
            mat.emission.contents = armorEmission
        }
    }
}

/// Renders Liu Quanwei (Nonna)'s Blazing Hunt sculpted 3D PBR obsidian-and-molten-flame Spirit Wolf (花焰灵狼).
@MainActor
private final class DuelSpiritWolfNode {
    let root = SCNNode()
    private let rig = SCNNode()
    private let usesGLB: Bool

    init() {
        root.addChildNode(rig)
        let tailAnchor = SCNNode()

        if let model = DuelEnvironmentAssetCache.cachedSpiritWolf() {
            usesGLB = true
            let inst = model.instantiate()
            inst.root.scale = SCNVector3(0.92, 0.92, 0.92)
            inst.root.enumerateHierarchy { node, _ in
                node.castsShadow = (node.geometry != nil)
                for mat in node.geometry?.materials ?? [] {
                    let nm = (mat.name ?? "").lowercased()
                    if nm.contains("eye") {
                        mat.emission.intensity = 3.8
                    } else if nm.contains("flame") {
                        mat.emission.intensity = 2.4
                    } else {
                        mat.emission.intensity = 1.25
                    }
                }
            }
            rig.addChildNode(inst.root)
            tailAnchor.position = SCNVector3(-0.72, 0.62, 0)
            rig.addChildNode(tailAnchor)
        } else {
            usesGLB = false
            func spiritPart(_ geom: SCNGeometry, alpha: CGFloat = 0.62) -> SCNNode {
                let m = SCNMaterial()
                m.diffuse.contents = UIColor(red: 1.0, green: 0.48, blue: 0.10, alpha: alpha)
                m.emission.contents = UIColor(red: 1.0, green: 0.40, blue: 0.06, alpha: 1)
                m.lightingModel = .constant; m.blendMode = .add; m.writesToDepthBuffer = false
                geom.materials = [m]
                let n = SCNNode(geometry: geom); n.castsShadow = false
                return n
            }
            let torso = spiritPart(SCNCapsule(capRadius: 0.14, height: 0.76), alpha: 0.58)
            torso.eulerAngles.x = .pi / 2; torso.position = SCNVector3(0, 0.54, 0)
            rig.addChildNode(torso)
            let snout = spiritPart(SCNCone(topRadius: 0.03, bottomRadius: 0.12, height: 0.34), alpha: 0.78)
            snout.eulerAngles.x = .pi / 2; snout.position = SCNVector3(0, 0.64, 0.50)
            rig.addChildNode(snout)
            tailAnchor.position = SCNVector3(0, 0.60, -0.50)
            rig.addChildNode(tailAnchor)
        }

        let fireWisp = SCNParticleSystem()
        fireWisp.particleImage = DuelProceduralVFXAssets.smokeWisp
        fireWisp.particleColor = UIColor(red: 1.0, green: 0.42, blue: 0.08, alpha: 0.45)
        fireWisp.birthRate = 28; fireWisp.particleLifeSpan = 0.34; fireWisp.particleSize = 0.30
        fireWisp.particleVelocity = 1.3; fireWisp.spreadingAngle = 28; fireWisp.blendMode = .additive
        fireWisp.isLightingEnabled = false
        tailAnchor.addParticleSystem(fireWisp)

        let embers = SCNParticleSystem()
        embers.particleImage = DuelProceduralVFXAssets.sparkNeedle
        embers.particleColor = UIColor(red: 1.0, green: 0.84, blue: 0.32, alpha: 1)
        embers.birthRate = 42; embers.particleLifeSpan = 0.30; embers.particleSize = 0.075
        embers.particleVelocity = 2.6; embers.stretchFactor = 0.06; embers.spreadingAngle = 32
        embers.blendMode = .additive; embers.isLightingEnabled = false
        tailAnchor.addParticleSystem(embers)
    }

    func pose(_ nonna: DuelNonnaState, frame: Int) {
        guard nonna.wolfActive else { root.isHidden = true; return }
        root.isHidden = false
        let phase = Float(frame) * 0.40
        let leap = abs(sin(phase)) * 0.22
        root.position = SCNVector3(Float(nonna.wolfX) / 1000, leap, 0.20)
        if usesGLB {
            // DuelProp_SpiritWolf.glb faces +X at yaw = 0 and -X at yaw = .pi.
            let yaw: Float = nonna.wolfFacing > 0 ? 0 : .pi
            root.simdOrientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            rig.eulerAngles = SCNVector3(0, 0, cos(phase) * 0.16)
        } else {
            let yaw: Float = nonna.wolfFacing > 0 ? .pi / 2 : -.pi / 2
            root.eulerAngles = SCNVector3(0, yaw, 0)
        }
    }
}

/// Renders Liu Quanwei (Nonna)'s Fire Grip sculpted 3D PBR obsidian-and-solar-flame Spirit Owl (烈焰灵枭).
@MainActor
private final class DuelSpiritOwlNode {
    let root = SCNNode()
    private let rig = SCNNode()
    private let usesGLB: Bool
    private var leftWing: SCNNode?
    private var rightWing: SCNNode?

    init() {
        root.addChildNode(rig)
        let trailAnchor = SCNNode()

        if let model = DuelEnvironmentAssetCache.cachedSpiritOwl() {
            usesGLB = true
            let inst = model.instantiate()
            inst.root.scale = SCNVector3(0.86, 0.86, 0.86)
            inst.root.enumerateHierarchy { node, _ in
                node.castsShadow = false
                for mat in node.geometry?.materials ?? [] {
                    let nm = (mat.name ?? "").lowercased()
                    if nm.contains("eye") {
                        mat.emission.intensity = 4.2
                    } else if nm.contains("solar") {
                        mat.emission.intensity = 2.6
                    } else {
                        mat.emission.intensity = 1.20
                    }
                }
            }
            rig.addChildNode(inst.root)
            trailAnchor.position = SCNVector3(-0.34, 0.0, 0)
            rig.addChildNode(trailAnchor)
        } else {
            usesGLB = false
            let bodyGeom = SCNSphere(radius: 0.13)
            let bodyMat = SCNMaterial()
            bodyMat.diffuse.contents = UIColor(red: 1.0, green: 0.72, blue: 0.22, alpha: 0.82)
            bodyMat.emission.contents = UIColor(red: 1.0, green: 0.56, blue: 0.12, alpha: 1)
            bodyMat.lightingModel = .constant; bodyMat.blendMode = .add; bodyMat.writesToDepthBuffer = false
            bodyGeom.materials = [bodyMat]
            let core = SCNNode(geometry: bodyGeom)
            core.scale = SCNVector3(0.85, 0.90, 1.40); core.castsShadow = false
            rig.addChildNode(core)

            func makeWing(sign: Float) -> SCNNode {
                let pivot = SCNNode()
                pivot.position = SCNVector3(sign * 0.08, 0.02, 0)
                let plane = SCNPlane(width: 0.64, height: 0.34)
                plane.materials = [DuelOriginalVFX.makeHDRGlowMaterial(
                    texture: DuelProceduralVFXAssets.slashCrescent,
                    color: UIColor(red: 1.0, green: 0.58, blue: 0.14, alpha: 0.96),
                    hdrBoost: 2.25
                )]
                let wingMesh = SCNNode(geometry: plane)
                wingMesh.position = SCNVector3(sign * 0.28, 0, -0.02)
                wingMesh.eulerAngles = SCNVector3(-Float.pi / 2, sign > 0 ? 0 : .pi, 0)
                wingMesh.castsShadow = false
                pivot.addChildNode(wingMesh)
                return pivot
            }
            let lw = makeWing(sign: -1); let rw = makeWing(sign: 1)
            leftWing = lw; rightWing = rw
            rig.addChildNode(lw); rig.addChildNode(rw)
            rig.addChildNode(trailAnchor)
        }

        let wingTrail = SCNParticleSystem()
        wingTrail.particleImage = DuelProceduralVFXAssets.sparkNeedle
        wingTrail.particleColor = UIColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1)
        wingTrail.birthRate = 38; wingTrail.particleLifeSpan = 0.28; wingTrail.particleSize = 0.07
        wingTrail.particleVelocity = 1.6; wingTrail.stretchFactor = 0.05; wingTrail.spreadingAngle = 35
        wingTrail.blendMode = .additive; wingTrail.isLightingEnabled = false
        trailAnchor.addParticleSystem(wingTrail)
    }

    func pose(_ nonna: DuelNonnaState, frame: Int) {
        guard nonna.owlPhase != .idle else { root.isHidden = true; return }
        root.isHidden = false
        let facing: Int = nonna.owlPhase == .returning ? -nonna.owlFacing : nonna.owlFacing
        let bob = sin(Float(frame) * 0.28) * 0.10
        root.position = SCNVector3(Float(nonna.owlX) / 1000, 1.48 + bob, 0.22)
        if usesGLB {
            // DuelProp_SpiritOwl.glb faces +X at yaw = 0 and -X at yaw = .pi.
            let yaw: Float = facing > 0 ? 0 : .pi
            root.simdOrientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            let bank = sin(Float(frame) * 0.42) * 0.18
            let pitch: Float = nonna.owlPhase == .latched ? 0.12 : -0.14
            rig.eulerAngles = SCNVector3(bank, 0, pitch)
        } else {
            let yaw: Float = facing > 0 ? .pi / 2 : -.pi / 2
            root.eulerAngles = SCNVector3(0, yaw, 0)
            let flap = sin(Float(frame) * 0.52) * 0.56
            leftWing?.eulerAngles.z = flap
            rightWing?.eulerAngles.z = -flap
        }
    }
}

/// Renders Xu Xiao's (King of the Legion) 28-link ghostly iron 3D Shadow Chain (`DuelProp_LegionChain.glb`,
/// unit-length X: 0..1m) stretched dynamically from Xu Xiao's left hand to the snagged opponent or max reach.
@MainActor
private final class DuelLegionChainNode {
    let root = SCNNode()
    private let rig = SCNNode()

    init() {
        root.addChildNode(rig)
        if let model = DuelEnvironmentAssetCache.cachedLegionChain() {
            let inst = model.instantiate()
            inst.root.enumerateHierarchy { node, _ in
                node.castsShadow = false
                for mat in node.geometry?.materials ?? [] {
                    mat.emission.intensity = 1.65
                }
            }
            rig.addChildNode(inst.root)
        } else {
            // Crisp procedural ghostly metallic chain + 4-spiked shackle fallback when private pack GLB is absent.
            let linkMat = SCNMaterial()
            linkMat.lightingModel = .physicallyBased
            linkMat.diffuse.contents = UIColor(red: 0.14, green: 0.34, blue: 0.42, alpha: 1)
            linkMat.metalness.contents = 0.85
            linkMat.roughness.contents = 0.25
            linkMat.emission.contents = UIColor(red: 0.22, green: 0.78, blue: 0.96, alpha: 1)
            linkMat.emission.intensity = 1.6
            for i in 0..<14 {
                let torus = SCNTorus(ringRadius: 0.042, pipeRadius: 0.013)
                torus.materials = [linkMat]
                let n = SCNNode(geometry: torus)
                n.position = SCNVector3(Float(i) * (0.90 / 14.0) + 0.03, 0, 0)
                n.eulerAngles = SCNVector3(i % 2 == 0 ? Float.pi / 2 : 0, 0, 0)
                n.castsShadow = false
                rig.addChildNode(n)
            }
            let cuff = SCNTorus(ringRadius: 0.14, pipeRadius: 0.025)
            cuff.materials = [linkMat]
            let cuffNode = SCNNode(geometry: cuff)
            cuffNode.position = SCNVector3(0.96, 0, 0)
            cuffNode.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
            cuffNode.castsShadow = false
            rig.addChildNode(cuffNode)
        }
    }

    func pose(_ lk: DuelLegionKingState, origin: SIMD3<Float>, facing: Int, target: DuelGame.Fighter, frame: Int) {
        guard lk.chainActiveTicks > 0 else { root.isHidden = true; return }
        root.isHidden = false
        let endX = lk.chainSnagged ? Float(target.x) / 1000 : Float(lk.chainTargetX) / 1000
        let endY = lk.chainSnagged ? (Float(target.y) / 1000 + 1.12) : origin.y
        let endPos = SIMD3<Float>(endX, endY, origin.z)
        let delta = endPos - origin
        let fullLen = max(0.35, simd_length(delta))
        // Crisp whip extension over first 6 ticks, taut lock when snagged, quick retract on final 6 ticks.
        let elapsed = max(0, 24 - lk.chainActiveTicks)
        let extendFrac: Float = lk.chainSnagged
            ? 1.0
            : (elapsed < 6 ? Float(elapsed + 1) / 6.0 : (lk.chainActiveTicks < 6 ? Float(lk.chainActiveTicks) / 6.0 : 1.0))
        let length = max(0.30, fullLen * extendFrac)
        root.position = SCNVector3(origin.x, origin.y, origin.z)
        let dir = delta / fullLen
        let yaw = atan2(-dir.z, dir.x)
        let pitch = asin(max(-0.95, min(0.95, dir.y)))
        let whipRoll = sin(Float(frame) * 0.55) * (lk.chainSnagged ? 0.04 : 0.18)
        root.simdOrientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)) *
            simd_quatf(angle: pitch, axis: SIMD3<Float>(0, 0, 1)) *
            simd_quatf(angle: whipRoll, axis: SIMD3<Float>(1, 0, 0))
        rig.scale = SCNVector3(length, 1.0, 1.0)
    }
}

/// Renders Sun Deng's (Monkey King) sculpted upright 2.25m Ascension Jingu Pillar (`DuelProp_MonkeyPillar.glb`)
/// rising cleanly out of the courtyard flagstones when Sun Deng perches or slams Heavenly Pillar.
@MainActor
private final class DuelMonkeyPillarNode {
    let root = SCNNode()
    private let rig = SCNNode()

    init() {
        root.addChildNode(rig)
        if let model = DuelEnvironmentAssetCache.cachedMonkeyPillar() {
            let inst = model.instantiate()
            inst.root.enumerateHierarchy { node, _ in
                node.castsShadow = (node.geometry != nil)
            }
            rig.addChildNode(inst.root)
        } else {
            // Sculpted crimson-lacquer & burnished imperial gold Jingu Pillar fallback when private pack GLB is absent.
            let shaftMat = SCNMaterial()
            shaftMat.lightingModel = .physicallyBased
            shaftMat.diffuse.contents = UIColor(red: 0.62, green: 0.12, blue: 0.09, alpha: 1)
            shaftMat.roughness.contents = 0.35
            shaftMat.metalness.contents = 0.18
            let goldMat = SCNMaterial()
            goldMat.lightingModel = .physicallyBased
            goldMat.diffuse.contents = UIColor(red: 0.90, green: 0.72, blue: 0.24, alpha: 1)
            goldMat.metalness.contents = 0.88
            goldMat.roughness.contents = 0.24
            goldMat.emission.contents = UIColor(red: 0.32, green: 0.22, blue: 0.04, alpha: 1)

            let shaft = SCNCylinder(radius: 0.13, height: 2.22)
            shaft.materials = [shaftMat]
            let shaftNode = SCNNode(geometry: shaft)
            shaftNode.position = SCNVector3(0, 1.11, 0)
            rig.addChildNode(shaftNode)

            for yPos in [0.16, 2.08] as [Float] {
                let cap = SCNCylinder(radius: 0.165, height: 0.30)
                cap.materials = [goldMat]
                let capNode = SCNNode(geometry: cap)
                capNode.position = SCNVector3(0, yPos, 0)
                rig.addChildNode(capNode)
            }
        }
        let aura = SCNParticleSystem()
        aura.particleImage = DuelProceduralVFXAssets.sparkNeedle
        aura.particleColor = UIColor(red: 1.0, green: 0.84, blue: 0.32, alpha: 0.92)
        aura.birthRate = 24
        aura.particleLifeSpan = 0.40
        aura.particleSize = 0.06
        aura.particleVelocity = 1.4
        aura.spreadingAngle = 35
        aura.blendMode = .additive
        aura.isLightingEnabled = false
        let baseEmitter = SCNNode()
        baseEmitter.position = SCNVector3(0, 0.12, 0)
        baseEmitter.addParticleSystem(aura)
        root.addChildNode(baseEmitter)
    }

    func pose(_ mk: DuelMonkeyKingState, frame: Int) {
        guard mk.pillarShowTicks > 0 else { root.isHidden = true; return }
        root.isHidden = false
        let fadeScale: Float = mk.pillarShowTicks < 10 ? max(0.15, Float(mk.pillarShowTicks) / 10.0) : 1.0
        root.position = SCNVector3(Float(mk.pillarX) / 1000, 0, 0)
        rig.scale = SCNVector3(1.0, fadeScale, 1.0)
        rig.eulerAngles = SCNVector3(0, sin(Float(frame) * 0.04) * 0.05, 0)
    }
}





