import XCTest
import UIKit
import SceneKit
import Metal
import simd
@testable import ShiftReminder

/// Rechecks the one failed method with the original first Surface commit before
/// real asynchronous preparation, then a second same-tick image after completion.
/// Non-black is a narrow regression gate, not normal drawable or visual acceptance.
@MainActor
final class DuelActiveRendererPreparationTests: XCTestCase {
    private enum Failure: Error { case sourceIdentity, missingWorld, pixels, invariant(String) }

    override func setUpWithError() throws { continueAfterFailure = false }

    func testInstalledActiveRendererPreparationKeepsFirstFrameVisible() async throws {
        let releaseSHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
        guard Bundle.main.object(forInfoDictionaryKey: DuelFighterAssetRelease.infoKey) as? String == releaseSHA else {
            throw Failure.sourceIdentity
        }
        let clocksBefore = DuelWorldView.activeClocks
        let started = ProcessInfo.processInfo.systemUptime
        let captureLabels = ["first-submit-before-preparation", "first-submit-after-preparation"]
        let pixelSize = CGSize(width: 956, height: 440)
        var phase = "construct-paused-session"
        var completed = false, finalized = false, cleanupSucceeded = false
        var readinessPassed = false, nonBlackPassed = false, firstCommitOrderingPassed = false
        var firstCaptureOccurredBeforePrepare = false
        var stateInvariant = false, objectInvariant = false
        var waitTimedOut = false
        var captureFrameCalls = 0, presentationUnpauseCalls = 0
        var samples: [[String: Any]] = [], captures: [[String: Any]] = [], timings: [[String: Any]] = []
        var setup: [String: Any] = [:], beforeFirstCapture: [String: Any] = [:], beforeSecondCapture: [String: Any] = [:]
        var statistics: [String: [String: Int]] = [:]
        var session: DuelSession?, world: DuelWorldView?, window: UIWindow?
        var capturedSurface: DuelTriadRenderSurface?, capturedRenderer: SCNRenderer?, capturedScene: SCNScene?

        func nullableInt(_ value: Int?) -> Any { value.map { $0 as Any } ?? NSNull() }
        func nullableBool(_ value: Bool?) -> Any { value.map { $0 as Any } ?? NSNull() }
        func checked(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Failure.invariant(name) }
        }
        @MainActor func timed<T>(_ label: String, _ operation: @MainActor () throws -> T) rethrows -> T {
            let start = ProcessInfo.processInfo.systemUptime
            defer { timings.append(["phase": label, "seconds": ProcessInfo.processInfo.systemUptime - start]) }
            return try operation()
        }
        @MainActor func preparationObservation() -> [String: Any] {
            let rendererMatches = capturedRenderer.map { world?.scenePreparationRendererID == ObjectIdentifier($0) } ?? false
            let sceneMatches = capturedScene.map { world?.scenePreparationSceneID == ObjectIdentifier($0) } ?? false
            return ["api": "SCNSceneRenderer.prepare(_:completionHandler:)", "automatic": true,
                "target": world?.scenePreparationTarget ?? "not-started",
                "requestCount": world?.scenePreparationRequestCount ?? 0,
                "completionCount": world?.scenePreparationCompletionCount ?? 0,
                "objectCount": world?.scenePreparationObjectCount ?? 0,
                "prepareSuccess": nullableBool(world?.scenePreparationRawSuccess),
                "completionIdentityMatched": nullableBool(world?.scenePreparationIdentityMatched),
                "rendererMatchesOriginalSurface": rendererMatches, "sceneMatchesOriginalScene": sceneMatches,
                "hasPreparedSourceMusicScene": world?.hasPreparedSourceMusicScene ?? false,
                "sourceMusicReady": session?.sourceMusicReady ?? false,
                "testingMusicPrepareInstalled": world?.testingMusicPrepare != nil,
                "testingPrepareInstalled": world?.testingPrepare != nil,
                "commitCountAtRequest": nullableInt(world?.scenePreparationCommitCountAtRequest),
                "normalSubmittedFramesAtRequest": nullableInt(world?.scenePreparationNormalFramesAtRequest),
                "waitDeadlineSeconds": 15, "waitTimedOut": waitTimedOut,
                "prepareCallsByTest": 0, "synchronousPrepareCallsByTest": 0,
                "completionCallsByTest": 0]
        }
        @MainActor func commitObservation() -> [String: Any] {
            ["sourceFrameCommitCount": world?.sourceFrameCommitCount ?? 0,
                "firstCommitObservedForCurrentOwners": world?.sourcePreparationHasFirstCommit ?? false,
                "presentationKickScheduleCount": world?.sourcePreparationPresentationSchedules ?? 0,
                "presentationKickAttemptCount": world?.sourcePreparationPresentationAttempts ?? 0,
                "queuedPreparationWorkPending": world?.sourcePreparationHasPendingWork ?? false,
                "normalSubmittedFrames": capturedSurface?.submittedFrames ?? 0,
                "normalLastSubmittedTick": nullableInt(capturedSurface?.lastSubmittedTick),
                "callbackMeansCommandBufferCommit": true, "callbackMeansGPUCompletion": false,
                "callbackMeansDisplayedDrawable": false]
        }
        @MainActor func finalizeReport() {
            guard !finalized else { return }
            finalized = true
            let preparation = preparationObservation(), commits = commitObservation()
            world?.shutdown(); session?.shutdown(); window?.isHidden = true
            let cleanup: [String: Any] = [
                "worldSceneReleased": world?.scene == nil, "worldSurfaceReleased": world?.triadRenderSurface == nil,
                "worldPacketRendererReleased": world?.triadMetalRenderer == nil,
                "surfaceSceneDetached": capturedRenderer?.scene == nil,
                "surfacePointOfViewDetached": capturedRenderer?.pointOfView == nil,
                "surfaceDelegateDetached": capturedSurface?.delegate == nil,
                "sourceProjectorDetached": capturedSurface?.projectedShadow == nil,
                "renderCallbackCleared": capturedSurface?.didSubmitFrame == nil,
                "lateGeometryProviderCleared": capturedSurface?.lateSourceGeometry == nil,
                "queuedPreparationWorkCleared": world?.sourcePreparationHasPendingWork == false,
                "firstCommitIdentityCleared": world?.sourcePreparationHasFirstCommit == false,
                "sourceMusicReadyAfterShutdown": session?.sourceMusicReady ?? false,
                "objectDeallocationVerified": false,
                "activeClocksBefore": clocksBefore, "activeClocksAfter": DuelWorldView.activeClocks]
            let keys = ["worldSceneReleased", "worldSurfaceReleased", "worldPacketRendererReleased",
                "surfaceSceneDetached", "surfacePointOfViewDetached", "surfaceDelegateDetached",
                "sourceProjectorDetached", "renderCallbackCleared", "lateGeometryProviderCleared",
                "queuedPreparationWorkCleared", "firstCommitIdentityCleared"]
            cleanupSucceeded = keys.allSatisfy { cleanup[$0] as? Bool == true }
                && cleanup["sourceMusicReadyAfterShutdown"] as? Bool == false
                && DuelWorldView.activeClocks == clocksBefore
            let report: [String: Any] = [
                "schemaVersion": 1, "schema": "fighter-first-submit-preparation-v1",
                "scope": "installed-first-submit-preparation-one", "releaseSHA256": releaseSHA,
                "diagnosticCompleted": completed, "lastPhase": phase,
                "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
                "setup": setup, "preparation": preparation, "firstCommit": commits,
                "beforeFirstCapture": beforeFirstCapture, "beforeSecondCapture": beforeSecondCapture,
                "samples": samples, "captures": captures, "pixelStatistics": statistics,
                "timings": timings, "cleanup": cleanup,
                "readinessRegressionPassed": readinessPassed, "nonBlackRegressionPassed": nonBlackPassed,
                "firstCommitOrderingPassed": firstCommitOrderingPassed,
                "firstCaptureOccurredBeforePrepare": firstCaptureOccurredBeforePrepare,
                "explicitDrawStateCalls": 0, "captureFrameCalls": captureFrameCalls,
                "simulationAdvanceCalls": 0, "sceneRebindCalls": 0, "freshRendererCreationCalls": 0,
                "snapshotCalls": 0, "projectorDetachCalls": 0, "prepareCallsByTest": 0,
                "synchronousPrepareCallsByTest": 0, "completionCallsByTest": 0,
                "expectedSimulationFrames": [0], "stateInvariant": stateInvariant,
                "modelObjectIdentityInvariant": objectInvariant, "captureLabels": captures.compactMap { $0["label"] as? String },
                "gamePausedForIsolation": true, "presentationOnlyUnpauseCalls": presentationUnpauseCalls,
                "combatStateInjected": false, "liveDisplayLinkAdvancesSelected": false,
                "sourcePacketsExpectedZero": true, "sceneKitLightsChanged": false,
                "normalDrawablePresentationValidated": false, "uiFlowExecutedByThisMethod": false,
                "physicalDeviceValidated": false, "liveUIValidated": false,
                "audiblePlaybackVerified": false, "performanceVerified": false,
                "panguEquipmentActivated": false, "pixels": "PENDING",
                "captureTimingIncludesGPUReadbackWait": true,
                "pixelDecode": "Original PNG decoded as sRGB RGBA8, byteOrder32Big/premultipliedLast, copy blend, no resizing",
                "scopeWarning": "A is the first complete offscreen encoding before preparation. B is a second same-tick encoding after the actual asynchronous completion. A commit is not GPU completion or normal drawable presentation. Both nonblack images remain pending visual review."
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "first-submit-preparation-report"; attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        defer { finalizeReport() }

        func matrix(_ value: simd_float4x4) -> [Float] {
            (0..<4).flatMap { column in (0..<4).map { row in value[column][row] } }
        }
        let state = timed(phase) {
            let value = DuelSession(.init(hero: .ember, difficulty: .learning, mode: .practice, originalWeapons: true))
            value.pause()
            return value
        }
        session = state
        phase = "construct-world"
        let view = timed(phase) { DuelWorldView(session: state) }
        world = view
        guard state.loadError == nil, let assets = state.weaponAssets,
              assets.release?.definition.id == "h17-shared-root-floorfall-20261115-v2",
              let scene = view.scene, let eye = view.pointOfView, let camera = eye.camera,
              let surface = view.triadRenderSurface, let packets = view.triadMetalRenderer,
              let projector = surface.projectedShadow,
              let driver = surface.delegate as? DuelTriadSurfaceFrameDriver else { throw Failure.missingWorld }
        let renderer = surface.sceneRenderer
        capturedSurface = surface; capturedRenderer = renderer; capturedScene = scene
        try checked(Set(assets.catalog.profiles.map(\.id)) == Set(["sun_triad", "liu_hammers"]), "source-profiles")
        try checked(!assets.catalog.profiles.contains(where: \.isPangu) && assets.panguAudio == nil, "not-pangu")
        try checked(view.testingMusicPrepare == nil && view.testingPrepare == nil, "preparation-hook-installed")
        try checked(state.paused && view.window == nil && view.clockCallbacks == 0, "cold-paused-owner")
        try checked(view.scenePreparationRequestCount == 0 && view.scenePreparationCompletionCount == 0, "prepared-before-mount")
        try checked(surface.submittedFrames == 0 && surface.lastSubmittedTick == nil && projector.lastFrame == nil, "prior-gpu-frame")
        let initialGame = state.game
        let host = UIWindow(frame: CGRect(origin: .zero, size: pixelSize))
        window = host; host.rootViewController = UIViewController(); host.makeKeyAndVisible()
        view.frame = host.bounds; view.autoresizingMask = []
        phase = "mount-production-first-submit-deferral"
        timed(phase) {
            host.rootViewController?.view.addSubview(view)
            view.setNeedsLayout(); view.layoutIfNeeded()
        }
        try checked(view.bounds.size == pixelSize && surface.bounds.size == pixelSize, "viewport")

        @MainActor func nodes() -> [SCNNode] {
            var result: [SCNNode] = [], pending = [scene.rootNode]
            while let node = pending.popLast() { result.append(node); pending.append(contentsOf: node.childNodes.reversed()) }
            return result
        }
        @MainActor func objectIDs() -> [ObjectIdentifier] {
            var result: [ObjectIdentifier] = []
            for node in nodes() {
                result.append(ObjectIdentifier(node))
                if let geometry = node.geometry {
                    result.append(ObjectIdentifier(geometry)); result.append(contentsOf: geometry.materials.map(ObjectIdentifier.init))
                }
                if let skinner = node.skinner { result.append(ObjectIdentifier(skinner)) }
            }
            return result
        }
        @MainActor func modelState() -> [[Float]] {
            nodes().map { matrix($0.simdTransform) + [Float($0.opacity), $0.isHidden ? 1 : 0] }
        }
        @MainActor func lights() -> [[String: Any]] {
            nodes().compactMap { node in
                guard let light = node.light else { return nil }
                return ["type": light.type.rawValue, "castsShadow": light.castsShadow, "intensity": light.intensity,
                    "categoryMask": light.categoryBitMask, "modelWorldTransform": matrix(node.simdWorldTransform)]
            }
        }
        let initialObjects = objectIDs(), initialModel = modelState()
        let initialCamera = matrix(eye.simdWorldTransform), initialFOV = camera.fieldOfView, initialMask = camera.categoryBitMask
        let initialLights = try JSONSerialization.data(withJSONObject: lights(), options: [.sortedKeys])
        setup = ["pausedBeforeWorldConstruction": true, "gamePaused": state.paused,
            "testingMusicPrepareInstalled": view.testingMusicPrepare != nil, "testingPrepareInstalled": view.testingPrepare != nil,
            "hostAndSurfaceShareScene": view.scene === renderer.scene,
            "hostAndSurfaceSharePointOfView": view.pointOfView === renderer.pointOfView,
            "surfaceSubmittedFrames": surface.submittedFrames, "surfaceLastSubmittedTick": nullableInt(surface.lastSubmittedTick),
            "projectorLastFrameAvailable": projector.lastFrame != nil, "displayLinkCallbacks": view.clockCallbacks,
            "activeClocksBefore": clocksBefore, "activeClocksAfterMount": DuelWorldView.activeClocks,
            "preparationRequestCountAfterMount": view.scenePreparationRequestCount,
            "sourceFrameCommitCount": view.sourceFrameCommitCount,
            "firstCommitObservedForCurrentOwners": view.sourcePreparationHasFirstCommit,
            "presentationKickScheduleCount": view.sourcePreparationPresentationSchedules,
            "presentationKickAttemptCount": view.sourcePreparationPresentationAttempts,
            "queuedPreparationWorkPending": view.sourcePreparationHasPendingWork]

        @MainActor func assertInvariant() throws {
            try checked(state.paused && state.game == initialGame && state.animationTick == 0 && view.clockCallbacks == 0,
                        "simulation-or-clock-changed")
            try checked(DuelWorldView.activeClocks == clocksBefore, "clock-started")
            try checked(view.scene === scene && view.pointOfView === eye && view.triadRenderSurface === surface
                && surface.sceneRenderer === renderer && renderer.scene === scene && renderer.pointOfView === eye
                && surface.projectedShadow === projector && surface.delegate === driver, "owner-changed")
            try checked(surface.submittedFrames == 0 && surface.lastSubmittedTick == nil && packets.submittedPacketCount == 0
                && view.activeSourceEffectIDs.isEmpty, "unexpected-frame-or-effects")
            try checked(objectIDs() == initialObjects && modelState() == initialModel
                && matrix(eye.simdWorldTransform) == initialCamera && camera.fieldOfView == initialFOV
                && camera.categoryBitMask == initialMask, "model-identity-or-transform-changed")
            try checked(try JSONSerialization.data(withJSONObject: lights(), options: [.sortedKeys]) == initialLights, "lights-changed")
            try checked(view.testingMusicPrepare == nil && view.testingPrepare == nil, "preparation-hook-installed")
            try checked(state.loadError == nil && view.triadPreparationFailure == nil && packets.lastFailure == nil
                && surface.lastFailure == nil, "render-error")
        }
        @MainActor func captureBoundary() -> [String: Any] {
            ["surfaceSubmittedFrames": surface.submittedFrames,
                "surfaceLastSubmittedTick": nullableInt(surface.lastSubmittedTick),
                "projectorLastFrameAvailable": projector.lastFrame != nil,
                "frame": state.game.frame, "animationTick": state.animationTick,
                "displayLinkCallbacks": view.clockCallbacks,
                "sourceMusicReady": state.sourceMusicReady,
                "hasPreparedSourceMusicScene": view.hasPreparedSourceMusicScene,
                "preparationRequestCount": view.scenePreparationRequestCount,
                "preparationCompletionCount": view.scenePreparationCompletionCount,
                "sourceFrameCommitCount": view.sourceFrameCommitCount,
                "firstCommitObservedForCurrentOwners": view.sourcePreparationHasFirstCommit,
                "presentationKickAttemptCount": view.sourcePreparationPresentationAttempts]
        }
        @MainActor func capture(_ label: String, ordinal: Int) throws {
            phase = label
            let image = try timed(label + "-synchronous-capture") {
                captureFrameCalls += 1
                return try surface.captureFrame(tick: 0, pixelSize: pixelSize, samples: 2)
            }
            guard let data = image.pngData() else { throw Failure.pixels }
            // Preserve each original image before any pixel or ordering assertion.
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
            guard let shadowFrame = projector.lastFrame, let fight = state.game.weaponFight else {
                throw Failure.missingWorld
            }
            try checked(image.cgImage?.width == 956 && image.cgImage?.height == 440 && shadowFrame.tick == 0, "capture-shape")
            try assertInvariant()
            statistics[label] = try Self.pixelStatistics(data)
            let common: [String: Any] = ["label": label, "frame": fight.frame, "animationTick": state.animationTick,
                "sourceLiveTick": fight.triadPresentation.liveTick, "rendererRoute": "surface.captureFrame",
                "sourceProjectorInstalled": true, "projectorEncodedForCapture": true,
                "submittedPackets": packets.submittedPacketCount, "surfaceSubmittedFrames": surface.submittedFrames,
                "surfaceLastSubmittedTick": nullableInt(surface.lastSubmittedTick), "requestedSurfaceSamples": 2,
                "resolvedSurfaceSamples": DuelTriadRenderSurface.format(samples: 2).samples,
                "captureOrdinal": ordinal, "firstCompleteOffscreenEncoding": ordinal == 1,
                "preparationPhase": ordinal == 1 ? "before-prepare" : "after-real-completion",
                "sourceFrameCommitCount": view.sourceFrameCommitCount,
                "presentationKickAttemptCount": view.sourcePreparationPresentationAttempts]
            var sample = common
            sample["gamePaused"] = state.paused; sample["displayLinkCallbacks"] = view.clockCallbacks
            sample["sourceIntroActive"] = fight.sourceIntroActive; sample["sourceStance"] = fight.sourceStance(0)?.motion.rawValue ?? "none"
            sample["sourceStanceTick"] = fight.sourceStance(0)?.tick ?? -1
            sample["sourceEffectIDs"] = view.activeSourceEffectIDs; sample["simulationInvariant"] = state.game == initialGame
            sample["sameActiveSurface"] = view.triadRenderSurface === surface; sample["sameActiveRenderer"] = surface.sceneRenderer === renderer
            sample["sameScene"] = renderer.scene === scene; sample["samePointOfView"] = renderer.pointOfView === eye
            sample["hostStillOwnsScene"] = view.scene === scene; sample["hostStillOwnsPointOfView"] = view.pointOfView === eye
            sample["modelObjectIdentityUnchanged"] = objectIDs() == initialObjects
            sample["rendererUsesReverseZ"] = renderer.usesReverseZ; sample["rendererIsPlaying"] = renderer.isPlaying
            sample["rendererAutoenablesDefaultLighting"] = renderer.autoenablesDefaultLighting
            sample["hostRendersContinuously"] = view.rendersContinuously; sample["hostIsPlaying"] = view.isPlaying
            sample["preparation"] = preparationObservation(); sample["lights"] = lights()
            sample["firstCommitObservedForCurrentOwners"] = view.sourcePreparationHasFirstCommit
            sample["queuedPreparationWorkPending"] = view.sourcePreparationHasPendingWork
            sample["camera"] = ["modelWorldTransform": matrix(eye.simdWorldTransform),
                "presentationWorldTransform": matrix(eye.presentation.simdWorldTransform),
                "fieldOfView": Double(camera.fieldOfView), "near": camera.zNear, "far": camera.zFar,
                "categoryMask": camera.categoryBitMask, "usesOrthographicProjection": camera.usesOrthographicProjection,
                "metalProjection": matrix(try DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: pixelSize))]
            sample["fighters"] = fight.fighters.enumerated().map { index, fighter in ["index": index,
                "hero": fighter.hero.rawValue, "health": fighter.health, "x": fighter.x, "y": fighter.y,
                "clip": fighter.weaponPose?.clip ?? "", "clipTick": fighter.weaponPose?.tick ?? -1] as [String: Any] }
            sample["sceneInventory"] = scene.rootNode.childNodes.filter {
                ["duel.stage.palace", "duel.actor.0", "duel.actor.1"].contains($0.name ?? "")
            }.map { root -> [String: Any] in
                var count = 0, skins = 0, pending = [root]
                while let node = pending.popLast() {
                    if node.geometry != nil { count += 1 }; if node.skinner != nil { skins += 1 }
                    pending.append(contentsOf: node.childNodes)
                }
                return ["name": root.name ?? "", "hidden": root.isHidden, "opacity": root.opacity,
                    "geometries": count, "skinners": skins, "modelWorldTransform": matrix(root.simdWorldTransform),
                    "presentationWorldTransform": matrix(root.presentation.simdWorldTransform)]
            }
            sample["projectorLastFrame"] = ["available": true, "tick": shadowFrame.tick, "aspect": shadowFrame.aspect,
                "sourceCameraPosition": [shadowFrame.sourceCameraPosition.x, shadowFrame.sourceCameraPosition.y, shadowFrame.sourceCameraPosition.z],
                "sourceView": matrix(shadowFrame.sourceView), "sourceProjection": matrix(shadowFrame.sourceProjection),
                "sourceShadowMatrix": matrix(shadowFrame.sourceShadowMatrix), "casterCount": shadowFrame.casterCount,
                "triangleCount": shadowFrame.triangleCount, "factors": shadowFrame.factors]
            sample["viewport"] = ["pointsWidth": Double(view.bounds.width), "pointsHeight": Double(view.bounds.height),
                "captureWidth": 956, "captureHeight": 440]
            sample["rendererFailure"] = packets.lastFailure.map { String(describing: $0) } ?? ""
            sample["surfaceFailure"] = surface.lastFailure.map { String(describing: $0) } ?? ""
            sample["sourcePreparationFailure"] = view.triadPreparationFailure ?? ""
            samples.append(sample)
            var captured = common
            captured["pngSHA256"] = DuelNetworkContentRecord.digest(data); captured["bytes"] = data.count
            captured["width"] = 956; captured["height"] = 440; captured["pixelsRequireReview"] = true
            captured["simulationAndModelCameraUnchanged"] = true
            captures.append(captured)
        }
        try assertInvariant()
        try checked(projector.lastFrame == nil && view.sourceFrameCommitCount == 0, "prior-source-encoding")
        beforeFirstCapture = captureBoundary()
        // A runs synchronously before yielding to the queued presentation kick.
        // Its real commit cancels that redundant kick and schedules preparation.
        surface.setPaused(false)
        presentationUnpauseCalls += 1
        try capture(captureLabels[0], ordinal: 1)
        firstCaptureOccurredBeforePrepare = view.scenePreparationRequestCount == 0
            && view.scenePreparationCompletionCount == 0 && !state.sourceMusicReady
            && !view.hasPreparedSourceMusicScene && view.sourceFrameCommitCount == 1
            && view.sourcePreparationHasFirstCommit && surface.submittedFrames == 0
            && view.sourcePreparationPresentationAttempts == 0

        phase = "await-production-automatic-completion"
        let waitStarted = ProcessInfo.processInfo.systemUptime
        while view.scenePreparationCompletionCount == 0 && state.loadError == nil
            && ProcessInfo.processInfo.systemUptime - waitStarted < 15 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        timings.append(["phase": phase, "seconds": ProcessInfo.processInfo.systemUptime - waitStarted])
        waitTimedOut = view.scenePreparationCompletionCount == 0
        if waitTimedOut {
            phase = "automatic-preparation-not-completed"
            throw Failure.invariant("automatic-preparation-not-completed")
        }
        readinessPassed = view.scenePreparationRequestCount == 1 && view.scenePreparationCompletionCount == 1
            && view.scenePreparationTarget == "surface.sceneRenderer"
            && view.scenePreparationRendererID == ObjectIdentifier(renderer)
            && view.scenePreparationSceneID == ObjectIdentifier(scene) && view.scenePreparationObjectCount == 1
            && view.scenePreparationRawSuccess == true && view.scenePreparationIdentityMatched == true
            && view.hasPreparedSourceMusicScene && state.sourceMusicReady
            && view.testingMusicPrepare == nil && view.testingPrepare == nil
        beforeSecondCapture = captureBoundary()
        try capture(captureLabels[1], ordinal: 2)
        firstCommitOrderingPassed = firstCaptureOccurredBeforePrepare
            && view.scenePreparationCommitCountAtRequest == 1 && view.scenePreparationNormalFramesAtRequest == 0
            && view.sourceFrameCommitCount == 2 && view.sourcePreparationHasFirstCommit
            && view.sourcePreparationPresentationSchedules == 1 && view.sourcePreparationPresentationAttempts == 0
            && !view.sourcePreparationHasPendingWork
        nonBlackPassed = captureLabels.allSatisfy { label in
            guard let pixels = statistics[label] else { return false }
            return pixels["pixelCount"] == 420640 && pixels["opaquePixelCount"] == 420640
                && (pixels["visibleNonBlackPixelCount"] ?? 0) > 0
        }
        stateInvariant = state.game == initialGame && state.animationTick == 0 && view.clockCallbacks == 0
        objectInvariant = objectIDs() == initialObjects && modelState() == initialModel
        completed = true; phase = "captured-before-regression-assertions"
        // Both original PNGs, actual preparation and cleanup precede assertions;
        // either black image or false readiness remains a complete failed result.
        finalizeReport()
        XCTAssertTrue(firstCommitOrderingPassed, "Actual preparation did not follow the original first Surface commit without an extra presentation")
        XCTAssertTrue(readinessPassed, "Real active-renderer completion did not authorize the original scene readiness")
        XCTAssertTrue(nonBlackPassed, "A or B original Surface frame is empty, transparent or entirely black")
        XCTAssertTrue(cleanupSucceeded, "Scene owners, queued preparation or paused-clock lifecycle did not clean up")
        XCTAssertEqual(DuelWorldView.activeClocks, clocksBefore)
    }

    private static func pixelStatistics(_ originalPNG: Data) throws -> [String: Int] {
        guard let image = UIImage(data: originalPNG)?.cgImage, image.width == 956, image.height == 440,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw Failure.pixels }
        let width = image.width, height = image.height, count = width * height
        var rgba = [UInt8](repeating: 0, count: count * 4)
        let decoded = rgba.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard decoded else { throw Failure.pixels }
        var opaque = 0, opaqueBlack = 0, transparent = 0, visibleNonBlack = 0
        for pixel in 0..<count {
            let offset = pixel * 4, alpha = rgba[offset + 3]
            let black = rgba[offset] == 0 && rgba[offset + 1] == 0 && rgba[offset + 2] == 0
            if alpha == 255 { opaque += 1; if black { opaqueBlack += 1 } }
            if alpha == 0 { transparent += 1 }
            if alpha > 0 && !black { visibleNonBlack += 1 }
        }
        return ["width": width, "height": height, "pixelCount": count, "opaquePixelCount": opaque,
            "opaqueBlackPixelCount": opaqueBlack, "transparentPixelCount": transparent,
            "visibleNonBlackPixelCount": visibleNonBlack]
    }
}
