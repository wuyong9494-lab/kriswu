import XCTest
import UIKit
import SceneKit
import Metal
import simd
@testable import ShiftReminder

/// Separates the existing host SCNView's preparation from the Surface renderer.
/// Both images use the unchanged original Surface; image content is an observation.
@MainActor
final class DuelHostSceneOwnershipTests: XCTestCase {
    private enum Failure: Error { case sourceIdentity, missingWorld, invariant(String) }

    override func setUpWithError() throws { continueAfterFailure = false }

    func testInstalledHostScenePreparationIsIsolatedAtFrameZero() throws {
        let releaseSHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
        guard Bundle.main.object(forInfoDictionaryKey: DuelFighterAssetRelease.infoKey) as? String == releaseSHA else {
            throw Failure.sourceIdentity
        }
        let clocksBefore = DuelWorldView.activeClocks
        let started = ProcessInfo.processInfo.systemUptime
        var phase = "construct-paused-session"
        var completed = false
        var finalized = false
        var cleanupSucceeded = false
        var automaticRequests = 0
        var requestSceneMatches: [Bool] = []
        var hostPrepareCalls = 0
        var hostPrepareSuccess: Bool?
        var captures: [[String: Any]] = []
        var samples: [[String: Any]] = []
        var timings: [[String: Any]] = []
        var preparation: [String: Any] = [:]
        var setup: [String: Any] = [:]
        var stateInvariant = false
        var objectInvariant = false
        var imagesEqual: Any = NSNull()
        var session: DuelSession?
        var world: DuelWorldView?
        var window: UIWindow?
        var capturedSurface: DuelTriadRenderSurface?
        var capturedRenderer: SCNRenderer?

        @MainActor func finalizeReport() {
            guard !finalized else { return }
            finalized = true
            world?.testingMusicPrepare = nil
            let hookCleared = world?.testingMusicPrepare == nil
            world?.shutdown(); session?.shutdown(); window?.isHidden = true
            let cleanup: [String: Any] = [
                "interceptionHookCleared": hookCleared,
                "worldSceneReleased": world?.scene == nil,
                "worldSurfaceReleased": world?.triadRenderSurface == nil,
                "worldPacketRendererReleased": world?.triadMetalRenderer == nil,
                "surfaceSceneDetached": capturedRenderer?.scene == nil,
                "surfacePointOfViewDetached": capturedRenderer?.pointOfView == nil,
                "surfaceDelegateDetached": capturedSurface?.delegate == nil,
                "sourceProjectorDetached": capturedSurface?.projectedShadow == nil,
                "renderCallbackCleared": capturedSurface?.didSubmitFrame == nil,
                "lateGeometryProviderCleared": capturedSurface?.lateSourceGeometry == nil,
                "objectDeallocationVerified": false,
                "activeClocksBefore": clocksBefore, "activeClocksAfter": DuelWorldView.activeClocks
            ]
            let actualChecks = ["interceptionHookCleared", "worldSceneReleased", "worldSurfaceReleased",
                "worldPacketRendererReleased", "surfaceSceneDetached", "surfacePointOfViewDetached",
                "surfaceDelegateDetached", "sourceProjectorDetached", "renderCallbackCleared", "lateGeometryProviderCleared"]
            cleanupSucceeded = actualChecks.allSatisfy { cleanup[$0] as? Bool == true }
                && DuelWorldView.activeClocks == clocksBefore
            let report: [String: Any] = [
                "schemaVersion": 1, "schema": "fighter-host-scene-ownership-v1",
                "scope": "installed-host-scene-ownership-one", "releaseSHA256": releaseSHA,
                "diagnosticCompleted": completed, "lastPhase": phase,
                "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
                "setup": setup, "samples": samples, "captures": captures, "timings": timings,
                "preparation": preparation, "cleanup": cleanup,
                "automaticPrepareRequestsIntercepted": automaticRequests,
                "interceptedRequestSceneMatches": requestSceneMatches,
                "interceptedCompletionForwardCalls": 0, "backgroundPrepareCallsByTest": 0,
                "hostSynchronousPrepareCalls": hostPrepareCalls,
                "activeRendererPrepareCalls": 0, "explicitDrawStateCalls": 0,
                "captureFrameCalls": captures.count, "simulationAdvanceCalls": 0,
                "activeSceneRebindCalls": 0, "hostSceneRebindCalls": 0,
                "freshRendererCreationCalls": 0, "snapshotCalls": 0, "projectorDetachCalls": 0,
                "expectedSimulationFrames": [0], "stateInvariant": stateInvariant,
                "modelObjectIdentityInvariant": objectInvariant,
                "captureLabels": captures.compactMap { $0["label"] as? String },
                "pngEqualBeforeAndAfterHostPreparation": imagesEqual,
                "gamePausedForIsolation": true, "presentationOnlyUnpauseCalls": 1,
                "interceptedCompletionIntentionallyNotForwarded": true,
                "combatStateInjected": false, "liveDisplayLinkAdvancesSelected": false,
                "sourcePacketsExpectedZero": true, "sceneKitLightsChanged": false,
                "normalDrawablePresentationValidated": false, "uiExecutionStatus": "not_selected",
                "physicalDeviceValidated": false, "liveUIValidated": false,
                "audiblePlaybackVerified": false, "performanceVerified": false,
                "panguEquipmentActivated": false, "pixels": "PENDING",
                "captureTimingIncludesGPUReadbackWait": true,
                "completionWarning": "A complete report and successful prepare do not prove visible pixels; compare the two original images",
                "interceptionWarning": "Only the existing mounted World music-readiness prepare request is intercepted; its SceneKit background call and readiness completion are not invoked",
                "pauseWarning": "The game is paused before World construction; only the original Surface presentation flag is enabled once for fixed-frame offscreen captures",
                "scopeWarning": "This method does not render a UI flow, present a normal drawable, release a fresh renderer, or accept production visuals"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "host-scene-ownership-report"; attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        defer { finalizeReport() }

        func checked(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Failure.invariant(name) }
        }
        @MainActor func timed<T>(_ label: String, _ operation: @MainActor () throws -> T) rethrows -> T {
            let start = ProcessInfo.processInfo.systemUptime
            defer { timings.append(["phase": label, "seconds": ProcessInfo.processInfo.systemUptime - start]) }
            return try operation()
        }
        func nullableInt(_ value: Int?) -> Any { value.map { $0 as Any } ?? NSNull() }
        func matrix(_ value: simd_float4x4) -> [Float] {
            (0..<4).flatMap { column in (0..<4).map { row in value[column][row] } }
        }
        func projection(_ value: SCNMatrix4) -> [Float] {
            [Float(value.m11), Float(value.m12), Float(value.m13), Float(value.m14),
             Float(value.m21), Float(value.m22), Float(value.m23), Float(value.m24),
             Float(value.m31), Float(value.m32), Float(value.m33), Float(value.m34),
             Float(value.m41), Float(value.m42), Float(value.m43), Float(value.m44)]
        }
        @MainActor func cameraValues(_ value: SCNCamera?) -> [String: Any] {
            guard let value else { return ["exists": false] }
            return ["exists": true, "fieldOfView": Double(value.fieldOfView), "near": value.zNear,
                "far": value.zFar, "usesOrthographicProjection": value.usesOrthographicProjection,
                "orthographicScale": value.orthographicScale, "categoryMask": value.categoryBitMask,
                "projectionTransform": projection(value.projectionTransform)]
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
              let projector = surface.projectedShadow, let device = surface.device,
              let driver = surface.delegate as? DuelTriadSurfaceFrameDriver else { throw Failure.missingWorld }
        let renderer = surface.sceneRenderer
        capturedSurface = surface; capturedRenderer = renderer
        try checked(Set(assets.catalog.profiles.map(\.id)) == Set(["sun_triad", "liu_hammers"]), "source-profiles")
        try checked(!assets.catalog.profiles.contains(where: \.isPangu) && assets.panguAudio == nil, "not-pangu")
        try checked(view.testingMusicPrepare == nil && state.paused && view.clockCallbacks == 0, "cold-paused-owner")
        try checked(view.window == nil && surface.submittedFrames == 0 && surface.lastSubmittedTick == nil, "no-normal-frame")
        try checked(projector.lastFrame == nil, "no-projector-warmup")
        let initialGame = state.game
        view.testingMusicPrepare = { objects, _ in
            automaticRequests += 1
            requestSceneMatches.append(objects.count == 1 && (objects.first as? SCNScene) === scene)
        }
        // This changes no game state and starts no display link. Both captures
        // use the same presentation state while the session remains paused.
        surface.setPaused(false)
        let pixelSize = CGSize(width: 956, height: 440)
        let host = UIWindow(frame: CGRect(origin: .zero, size: pixelSize))
        window = host; host.rootViewController = UIViewController(); host.makeKeyAndVisible()
        view.frame = host.bounds; view.autoresizingMask = []
        phase = "mount-layout-intercepted"
        timed(phase) {
            host.rootViewController?.view.addSubview(view)
            view.setNeedsLayout(); view.layoutIfNeeded()
        }
        try checked(automaticRequests == 1 && requestSceneMatches == [true], "exact-scene-request-intercepted")
        try checked(view.bounds.size == pixelSize && surface.bounds.size == pixelSize, "viewport")
        try checked(state.paused && state.game == initialGame && view.clockCallbacks == 0, "mounted-game-unadvanced")
        try checked(DuelWorldView.activeClocks == clocksBefore, "display-link-not-started")
        try checked(surface.submittedFrames == 0 && surface.lastSubmittedTick == nil && projector.lastFrame == nil, "cold-capture")
        try checked(!view.hasPreparedSourceMusicScene && !state.sourceMusicReady, "no-forwarded-readiness")

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
                    result.append(ObjectIdentifier(geometry))
                    result.append(contentsOf: geometry.materials.map(ObjectIdentifier.init))
                }
                if let skinner = node.skinner { result.append(ObjectIdentifier(skinner)) }
            }
            return result
        }
        @MainActor func modelState() -> [[Float]] {
            nodes().map { matrix($0.simdTransform) + [Float($0.opacity), $0.isHidden ? 1 : 0] }
        }
        @MainActor func lightStates() -> [[String: Any]] {
            nodes().compactMap { node in
                guard let light = node.light else { return nil }
                return ["type": light.type.rawValue, "castsShadow": light.castsShadow,
                    "intensity": light.intensity, "categoryMask": light.categoryBitMask,
                    "modelWorldTransform": matrix(node.simdWorldTransform)]
            }
        }
        let initialObjects = objectIDs(), initialModel = modelState()
        let initialCamera = matrix(eye.simdWorldTransform), initialFOV = camera.fieldOfView
        let initialMask = camera.categoryBitMask
        let initialLights = try JSONSerialization.data(withJSONObject: lightStates(), options: [.sortedKeys])
        setup = ["pausedBeforeWorldConstruction": true, "gamePaused": state.paused,
            "automaticPrepareRequestsIntercepted": automaticRequests, "requestSceneMatches": requestSceneMatches,
            "hostAndSurfaceShareScene": view.scene === renderer.scene,
            "hostAndSurfaceSharePointOfView": view.pointOfView === renderer.pointOfView,
            "sameMetalDevice": view.device?.registryID == device.registryID,
            "surfaceSubmittedFrames": surface.submittedFrames, "surfaceLastSubmittedTick": nullableInt(surface.lastSubmittedTick),
            "projectorLastFrameAvailable": projector.lastFrame != nil,
            "displayLinkCallbacks": view.clockCallbacks, "activeClocksBefore": clocksBefore,
            "activeClocksAfterMount": DuelWorldView.activeClocks, "hostMusicReadiness": view.hasPreparedSourceMusicScene]

        @MainActor func assertInvariant() throws {
            try checked(state.paused && state.game == initialGame && state.animationTick == 0 && view.clockCallbacks == 0,
                        "simulation-or-clock-changed")
            try checked(DuelWorldView.activeClocks == clocksBefore && automaticRequests == 1 && requestSceneMatches == [true],
                        "clock-or-request-count-changed")
            try checked(view.scene === scene && view.pointOfView === eye && view.triadRenderSurface === surface
                && surface.sceneRenderer === renderer && renderer.scene === scene && renderer.pointOfView === eye
                && surface.projectedShadow === projector && surface.delegate === driver, "owner-changed")
            try checked(surface.submittedFrames == 0 && surface.lastSubmittedTick == nil && packets.submittedPacketCount == 0
                && view.activeSourceEffectIDs.isEmpty, "unexpected-frame-or-effects")
            try checked(objectIDs() == initialObjects && modelState() == initialModel
                && matrix(eye.simdWorldTransform) == initialCamera && camera.fieldOfView == initialFOV
                && camera.categoryBitMask == initialMask, "model-identity-or-transform-changed")
            try checked(try JSONSerialization.data(withJSONObject: lightStates(), options: [.sortedKeys]) == initialLights,
                        "lights-changed")
            try checked(!view.hasPreparedSourceMusicScene && !state.sourceMusicReady, "readiness-callback-was-forwarded")
            try checked(state.loadError == nil && view.triadPreparationFailure == nil && packets.lastFailure == nil
                && surface.lastFailure == nil, "render-error")
        }
        @MainActor func capture(_ label: String, isolation: String) throws {
            phase = label
            try assertInvariant()
            let image = try timed(label + "-synchronous-capture") { try surface.captureFrame(tick: 0, pixelSize: pixelSize, samples: 2) }
            guard let data = image.pngData(), let frame = projector.lastFrame, let fight = state.game.weaponFight else {
                throw Failure.missingWorld
            }
            try checked(image.cgImage?.width == 956 && image.cgImage?.height == 440 && frame.tick == 0, "capture-shape")
            try assertInvariant()
            let common: [String: Any] = ["label": label, "frame": fight.frame, "animationTick": state.animationTick,
                "sourceLiveTick": fight.triadPresentation.liveTick, "rendererRoute": "surface.captureFrame",
                "sourceProjectorInstalled": true, "projectorEncodedForCapture": true,
                "submittedPackets": packets.submittedPacketCount, "surfaceSubmittedFrames": surface.submittedFrames,
                "surfaceLastSubmittedTick": nullableInt(surface.lastSubmittedTick),
                "requestedSurfaceSamples": 2, "resolvedSurfaceSamples": DuelTriadRenderSurface.format(samples: 2).samples,
                "hostPrepareCallsSoFar": hostPrepareCalls]
            var sample = common
            sample["hostPrepareSuccessSoFar"] = hostPrepareSuccess.map { $0 as Any } ?? NSNull()
            sample["automaticPrepareRequestsIntercepted"] = automaticRequests
            sample["displayLinkCallbacks"] = view.clockCallbacks; sample["gamePaused"] = state.paused
            sample["sourceIntroActive"] = fight.sourceIntroActive; sample["sourceStance"] = fight.sourceStance(0)?.motion.rawValue ?? "none"
            sample["sourceStanceTick"] = fight.sourceStance(0)?.tick ?? -1
            sample["weaponReady"] = fight.canUse(.weapon, index: 0); sample["branchesReady"] = fight.canUseTriad(.branches, index: 0)
            sample["sourceEffectIDs"] = view.activeSourceEffectIDs
            sample["sameActiveSurface"] = view.triadRenderSurface === surface; sample["sameActiveRenderer"] = surface.sceneRenderer === renderer
            sample["sameScene"] = renderer.scene === scene; sample["samePointOfView"] = renderer.pointOfView === eye
            sample["hostStillOwnsScene"] = view.scene === scene; sample["hostStillOwnsPointOfView"] = view.pointOfView === eye
            sample["modelObjectIdentityUnchanged"] = objectIDs() == initialObjects
            sample["simulationInvariant"] = state.game == initialGame
            sample["rendererUsesReverseZ"] = renderer.usesReverseZ; sample["rendererIsPlaying"] = renderer.isPlaying
            sample["rendererAutoenablesDefaultLighting"] = renderer.autoenablesDefaultLighting
            sample["hostRendersContinuously"] = view.rendersContinuously; sample["hostIsPlaying"] = view.isPlaying
            sample["hostMusicReadiness"] = view.hasPreparedSourceMusicScene
            sample["hostRenderingAPI"] = view.renderingAPI.rawValue
            sample["sameMetalDevice"] = view.device?.registryID == device.registryID
            sample["projectorLastFrame"] = ["available": true, "tick": frame.tick, "aspect": frame.aspect,
                "sourceCameraPosition": [frame.sourceCameraPosition.x, frame.sourceCameraPosition.y, frame.sourceCameraPosition.z],
                "sourceView": matrix(frame.sourceView), "sourceProjection": matrix(frame.sourceProjection),
                "sourceShadowMatrix": matrix(frame.sourceShadowMatrix), "casterCount": frame.casterCount,
                "triangleCount": frame.triangleCount, "factors": frame.factors]
            sample["fighters"] = fight.fighters.enumerated().map { index, fighter in ["index": index,
                "hero": fighter.hero.rawValue, "health": fighter.health, "x": fighter.x, "y": fighter.y,
                "clip": fighter.weaponPose?.clip ?? "", "clipTick": fighter.weaponPose?.tick ?? -1] as [String: Any] }
            sample["camera"] = ["modelWorldTransform": matrix(eye.simdWorldTransform),
                "presentationWorldTransform": matrix(eye.presentation.simdWorldTransform), "model": cameraValues(camera),
                "presentation": cameraValues(eye.presentation.camera),
                "metalProjection": matrix(try DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: pixelSize))]
            sample["lights"] = lightStates()
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
            sample["viewport"] = ["pointsWidth": Double(view.bounds.width), "pointsHeight": Double(view.bounds.height),
                "drawableWidth": Double(surface.drawableSize.width), "drawableHeight": Double(surface.drawableSize.height),
                "viewScale": Double(view.contentScaleFactor), "surfaceScale": Double(surface.contentScaleFactor),
                "captureWidth": 956, "captureHeight": 440]
            sample["rendererFailure"] = packets.lastFailure.map { String(describing: $0) } ?? ""
            sample["surfaceFailure"] = surface.lastFailure.map { String(describing: $0) } ?? ""
            sample["sourcePreparationFailure"] = view.triadPreparationFailure ?? ""
            samples.append(sample)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
            var captured = common
            captured["isolation"] = isolation; captured["pngSHA256"] = DuelNetworkContentRecord.digest(data)
            captured["bytes"] = data.count; captured["width"] = 956; captured["height"] = 440
            captured["pixelsRequireReview"] = true; captured["simulationAndModelCameraUnchanged"] = true
            captures.append(captured)
        }
        try capture("host-prepare-intercepted", isolation: "automatic host SceneKit prepare intercepted; no explicit prepare; original Surface and projector")
        phase = "prepare-existing-host-view-once"
        try assertInvariant()
        let prepareStarted = ProcessInfo.processInfo.systemUptime
        hostPrepareCalls += 1
        hostPrepareSuccess = view.prepare(scene, shouldAbortBlock: nil)
        let prepareSeconds = ProcessInfo.processInfo.systemUptime - prepareStarted
        timings.append(["phase": phase, "seconds": prepareSeconds])
        try assertInvariant()
        preparation = ["api": "SCNView.prepare(_:shouldAbortBlock:)", "target": "existing-world-SCNView",
            "input": "same-installed-SCNScene", "synchronous": true, "calls": hostPrepareCalls,
            "completionReturned": true, "success": hostPrepareSuccess.map { $0 as Any } ?? NSNull(), "seconds": prepareSeconds,
            "beforeCaptureLabel": "host-prepare-intercepted", "afterCaptureLabel": "host-world-prepared",
            "targetIsHostView": true, "targetIsActiveSurfaceRenderer": false,
            "hostSceneMatchesBeforeAndAfter": view.scene === scene,
            "activeRendererSceneMatchesBeforeAndAfter": renderer.scene === scene,
            "pointOfViewMatchesBeforeAndAfter": view.pointOfView === eye && renderer.pointOfView === eye,
            "sameOriginalProjector": surface.projectedShadow === projector,
            "simulationInvariantAfter": state.game == initialGame]
        try capture("host-world-prepared", isolation: "one synchronous prepare on existing World SCNView; same original Surface and projector")
        try assertInvariant()
        imagesEqual = (captures[0]["pngSHA256"] as? String) == (captures[1]["pngSHA256"] as? String)
        stateInvariant = state.game == initialGame && state.animationTick == 0 && view.clockCallbacks == 0
        objectInvariant = objectIDs() == initialObjects && modelState() == initialModel
        completed = true; phase = "captured-before-diagnostic-assertions"
        // Attach both original images and the actual cleanup receipt before a
        // failed prepare assertion can abort XCTest. No pixel assertion exists.
        finalizeReport()
        XCTAssertTrue(hostPrepareSuccess == true, "The existing host SCNView did not prepare the original scene")
        XCTAssertTrue(cleanupSucceeded, "Original owners or paused-clock lifecycle did not clean up")
        XCTAssertEqual(DuelWorldView.activeClocks, clocksBefore)
    }
}
