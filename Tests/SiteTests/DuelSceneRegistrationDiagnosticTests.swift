import XCTest
import UIKit
import SceneKit
import Metal
import simd
@testable import ShiftReminder

/// Four captures from the original surface at frame zero. The last branch
/// associates a second renderer but never asks it to prepare or render.
@MainActor
final class DuelSceneRegistrationDiagnosticTests: XCTestCase {
    private enum Failure: Error { case sourceIdentity, missingWorld }

    override func setUpWithError() throws { continueAfterFailure = false }

    func testInstalledSceneRegistrationChangesAreIsolatedAtFrameZero() throws {
        let releaseSHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
        guard Bundle.main.object(forInfoDictionaryKey: DuelFighterAssetRelease.infoKey) as? String == releaseSHA else {
            throw Failure.sourceIdentity
        }
        let clocksBefore = DuelWorldView.activeClocks
        let started = ProcessInfo.processInfo.systemUptime
        var phase = "construct-session"
        var completed = false
        var stateInvariant = false
        var restorationInvariant = false
        var sourceProjectorRestored = false
        var originalSceneAndPointOfViewRestored = false
        var freshBindingsCleared = false
        var freshTestReferenceCleared = false
        var explicitDrawStateCalls = 0
        var activeSceneRebindCalls = 0
        var freshRendererCreationCalls = 0
        var freshAssociationCalls = 0
        var projectorRemovedBeforeFirstDraw = false
        var surfaceSubmittedFramesBeforeExperiment: Any = NSNull()
        var surfaceLastSubmittedTickBeforeExperiment: Any = NSNull()
        var surfaceSubmittedFramesAfterExplicitDraw: Any = NSNull()
        var surfaceLastSubmittedTickAfterExplicitDraw: Any = NSNull()
        var samples: [[String: Any]] = []
        var captures: [[String: Any]] = []
        var timings: [[String: Any]] = []
        var registrationOperations: [[String: Any]] = []
        var adjacentPNGEqualities: [Bool] = []
        var session: DuelSession?
        var world: DuelWorldView?
        var window: UIWindow?
        var freshRenderer: SCNRenderer?
        defer {
            // The later restoration defer first unbinds the auxiliary renderer
            // and restores the original owners. No post-detachment image exists.
            world?.shutdown()
            session?.shutdown()
            window?.isHidden = true
            let cleanup: [String: Any] = [
                "sceneReleased": world?.scene == nil,
                "surfaceReleased": world?.triadRenderSurface == nil,
                "rendererReleased": world?.triadMetalRenderer == nil,
                "sourceProjectorRestoredBeforeShutdown": sourceProjectorRestored,
                "originalSceneAndPointOfViewRestoredBeforeShutdown": originalSceneAndPointOfViewRestored,
                "freshBindingsClearedBeforeShutdown": freshBindingsCleared,
                "freshTestReferenceClearedBeforeShutdown": freshTestReferenceCleared,
                "freshObjectDeallocationVerified": false,
                "activeClocksBefore": clocksBefore, "activeClocksAfter": DuelWorldView.activeClocks
            ]
            XCTAssertEqual(DuelWorldView.activeClocks, clocksBefore)
            var report: [String: Any] = [
                "schemaVersion": 1, "schema": "fighter-scene-registration-diagnostic-v1",
                "scope": "installed-scene-registration-diagnostic-one", "releaseSHA256": releaseSHA,
                "diagnosticCompleted": completed, "lastPhase": phase,
                "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
                "samples": samples, "captures": captures, "timings": timings, "cleanup": cleanup,
                "registrationOperations": registrationOperations,
                "captureLabels": captures.compactMap { $0["label"] as? String },
                "captureSourceProjectorStates": captures.compactMap { $0["sourceProjectorInstalled"] as? Bool },
                "expectedSimulationFrames": [0], "simulationAdvanceCalls": 0,
                "explicitDrawStateCalls": explicitDrawStateCalls,
                "activeSceneRebindCalls": activeSceneRebindCalls,
                "freshRendererCreationCalls": freshRendererCreationCalls,
                "freshAssociationCalls": freshAssociationCalls,
                "explicitPrepareCalls": 0, "freshRenderCalls": 0,
                "freshPrepareCalls": 0, "freshSnapshotCalls": 0, "snapshotCalls": 0,
                "sourceProjectorRemovedBeforeFirstExplicitDraw": projectorRemovedBeforeFirstDraw,
                "surfaceSubmittedFramesBeforeExperiment": surfaceSubmittedFramesBeforeExperiment,
                "surfaceLastSubmittedTickBeforeExperiment": surfaceLastSubmittedTickBeforeExperiment,
                "surfaceSubmittedFramesAfterExplicitDraw": surfaceSubmittedFramesAfterExplicitDraw,
                "surfaceLastSubmittedTickAfterExplicitDraw": surfaceLastSubmittedTickAfterExplicitDraw,
                "stateInvariant": stateInvariant, "restorationInvariant": restorationInvariant,
                "adjacentPNGEqualities": adjacentPNGEqualities,
                "combatStateInjected": false, "liveDisplayLinkAdvancesSelected": false,
                "sourcePacketsExpectedZero": true, "sceneKitLightsChanged": false,
                "freshRendererUsedForCapture": false, "postFreshDetachmentCaptureTaken": false,
                "uiExecutionStatus": "not_selected", "physicalDeviceValidated": false,
                "liveUIValidated": false, "audiblePlaybackVerified": false,
                "performanceVerified": false, "pixels": "PENDING", "panguEquipmentActivated": false,
                "captureTimingIncludesGPUReadbackWait": true
            ]
            report["timingWarning"] = "Construction, explicit draw, registration operations and original-surface readbacks are separate wall times; none measures live FPS or isolated GPU time"
            report["visibilityWarning"] = "Model and presentation values and geometric visibility are diagnostics, not proof of visible rendered pixels"
            report["freshLifetimeWarning"] = "Cleanup verifies detached scene/camera/delegate and the cleared test-owned strong reference; it does not prove ARC deallocation and has no following capture"
            report["projectorWarning"] = "The first unprojected image may have no retained projector lastFrame; later records describe the same original projector at tick zero"
            report["submissionWarning"] = "explicitDrawStateCalls counts this test's explicit calls, not World's constructor call; submittedFrames counts normal drawable submissions and is not incremented by captureFrame readbacks"
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "scene-registration-diagnostic-report"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }

        @MainActor func timed<T>(_ label: String, _ operation: @MainActor () throws -> T) rethrows -> T {
            let start = ProcessInfo.processInfo.systemUptime
            defer { timings.append(["phase": label, "seconds": ProcessInfo.processInfo.systemUptime - start]) }
            return try operation()
        }
        func nullableInt(_ value: Int?) -> Any { value.map { $0 as Any } ?? NSNull() }
        let state = timed("construct-session") {
            DuelSession(.init(hero: .ember, difficulty: .learning, mode: .practice, originalWeapons: true))
        }
        session = state
        phase = "construct-world"
        let view = timed("construct-world") { DuelWorldView(session: state) }
        world = view
        let pixelSize = CGSize(width: 956, height: 440)
        let viewport = CGRect(origin: .zero, size: pixelSize)
        let host = UIWindow(frame: viewport)
        window = host
        host.rootViewController = UIViewController()
        host.makeKeyAndVisible()
        view.frame = viewport
        view.autoresizingMask = []
        host.rootViewController?.view.addSubview(view)
        timed("mount-layout") { view.setNeedsLayout(); view.layoutIfNeeded() }
        guard state.loadError == nil, view.stageAsset != nil,
              let assets = state.weaponAssets, let release = assets.release,
              release.definition.id == "h17-shared-root-floorfall-20261115-v2",
              let scene = view.scene, let eye = view.pointOfView, let camera = eye.camera,
              let surface = view.triadRenderSurface, let packets = view.triadMetalRenderer,
              let device = surface.device, let originalProjector = surface.projectedShadow else { throw Failure.missingWorld }
        let activeRenderer = surface.sceneRenderer
        XCTAssertEqual(Set(assets.catalog.profiles.map(\.id)), Set(["sun_triad", "liu_hammers"]))
        XCTAssertNil(assets.panguAudio)
        XCTAssertFalse(assets.catalog.profiles.contains(where: \.isPangu))
        XCTAssertEqual(DuelTriadRenderSurface.format(samples: 2).samples, 4)
        XCTAssertEqual(state.game.frame, 0)
        XCTAssertEqual(state.animationTick, 0)
        XCTAssertEqual(view.clockCallbacks, 0)
        XCTAssertEqual(view.bounds.size, pixelSize)
        XCTAssertEqual(surface.bounds.size, pixelSize)
        XCTAssertTrue(activeRenderer.scene === scene)
        XCTAssertTrue(activeRenderer.pointOfView === eye)
        // World retains its construction-time drawState call. Verify the
        // actual normal-submission boundary before this experiment changes it.
        surfaceSubmittedFramesBeforeExperiment = surface.submittedFrames
        surfaceLastSubmittedTickBeforeExperiment = nullableInt(surface.lastSubmittedTick)
        XCTAssertEqual(surface.submittedFrames, 0)
        defer {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            SCNTransaction.disableActions = true
            if let fresh = freshRenderer {
                fresh.delegate = nil; fresh.scene = nil; fresh.pointOfView = nil
            }
            if activeRenderer.scene !== scene { activeRenderer.scene = scene }
            if activeRenderer.pointOfView !== eye { activeRenderer.pointOfView = eye }
            surface.projectedShadow = originalProjector
            SCNTransaction.commit()
            SCNTransaction.flush()
            if let fresh = freshRenderer {
                freshBindingsCleared = fresh.scene == nil && fresh.pointOfView == nil && fresh.delegate == nil
            } else { freshBindingsCleared = true }
            freshRenderer = nil
            freshTestReferenceCleared = freshRenderer == nil
            sourceProjectorRestored = surface.projectedShadow === originalProjector
            originalSceneAndPointOfViewRestored = activeRenderer.scene === scene && activeRenderer.pointOfView === eye &&
                view.scene === scene && view.pointOfView === eye
            restorationInvariant = sourceProjectorRestored && originalSceneAndPointOfViewRestored &&
                freshBindingsCleared && freshTestReferenceCleared && view.triadRenderSurface === surface &&
                surface.sceneRenderer === activeRenderer
            XCTAssertTrue(restorationInvariant)
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        surface.projectedShadow = nil
        SCNTransaction.commit()
        SCNTransaction.flush()
        projectorRemovedBeforeFirstDraw = surface.projectedShadow == nil && freshRenderer == nil
        XCTAssertTrue(projectorRemovedBeforeFirstDraw)
        let gameBeforeDraw = state.game
        phase = "frame-0-base-draw-submission"
        timed(phase) { explicitDrawStateCalls += 1; view.drawState() }
        XCTAssertEqual(state.game, gameBeforeDraw)
        XCTAssertEqual(view.clockCallbacks, 0)
        XCTAssertNil(state.loadError)
        XCTAssertNil(surface.lastFailure)
        XCTAssertNil(packets.lastFailure)
        XCTAssertEqual(packets.submittedPacketCount, 0)
        XCTAssertTrue(view.activeSourceEffectIDs.isEmpty)
        let initialGame = state.game
        let submittedFramesAfterDraw = surface.submittedFrames
        let lastSubmittedTickAfterDraw = surface.lastSubmittedTick
        surfaceSubmittedFramesAfterExplicitDraw = submittedFramesAfterDraw
        surfaceLastSubmittedTickAfterExplicitDraw = nullableInt(lastSubmittedTickAfterDraw)

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
            return ["exists": true, "fieldOfView": Double(value.fieldOfView), "near": value.zNear, "far": value.zFar,
                "usesOrthographicProjection": value.usesOrthographicProjection, "orthographicScale": value.orthographicScale,
                "categoryMask": value.categoryBitMask, "projectionTransform": projection(value.projectionTransform)]
        }
        @MainActor func effectivelyVisible(_ node: SCNNode) -> Bool {
            var current: SCNNode? = node
            while let value = current {
                if value.isHidden || value.opacity == 0 { return false }
                current = value.parent
            }
            return true
        }
        @MainActor func modelObjectIdentities() -> [ObjectIdentifier] {
            var values: [ObjectIdentifier] = []
            var pending = [scene.rootNode]
            while let node = pending.popLast() {
                values.append(ObjectIdentifier(node))
                if let geometry = node.geometry {
                    values.append(ObjectIdentifier(geometry))
                    for material in geometry.materials { values.append(ObjectIdentifier(material)) }
                }
                if let skin = node.skinner { values.append(ObjectIdentifier(skin)) }
                pending.append(contentsOf: node.childNodes)
            }
            return values
        }
        @MainActor func sceneInventory() -> [[String: Any]] {
            var rows: [[String: Any]] = []
            for root in scene.rootNode.childNodes {
                var geometries = 0, visible = 0, skinners = 0
                var masks = Set<Int>(), pending = [root]
                while let node = pending.popLast() {
                    if node.geometry != nil {
                        geometries += 1; masks.insert(node.categoryBitMask)
                        if effectivelyVisible(node) { visible += 1 }
                    }
                    if node.skinner != nil { skinners += 1 }
                    pending.append(contentsOf: node.childNodes)
                }
                rows.append(["name": root.name ?? "", "geometries": geometries, "visibleGeometries": visible,
                    "skinners": skinners, "hidden": root.isHidden, "opacity": Double(root.opacity),
                    "categoryMasks": masks.sorted(), "worldTransform": matrix(root.simdWorldTransform),
                    "presentationWorldTransform": matrix(root.presentation.simdWorldTransform)])
            }
            return rows
        }
        var lightNodes: [SCNNode] = [], nodes = [scene.rootNode]
        while let node = nodes.popLast() {
            if node.light != nil { lightNodes.append(node) }
            nodes.append(contentsOf: node.childNodes)
        }
        @MainActor func lightStates() -> [[String: Any]] {
            var rows: [[String: Any]] = []
            for node in lightNodes {
                guard let light = node.light else { continue }
                rows.append(["name": node.name ?? "", "type": light.type.rawValue, "castsShadow": light.castsShadow,
                    "intensity": Double(light.intensity), "hidden": node.isHidden,
                    "worldTransform": matrix(node.simdWorldTransform)])
            }
            return rows
        }
        @MainActor func projectorFrame() -> [String: Any] {
            guard let value = originalProjector.lastFrame else { return ["available": false] }
            return ["available": true, "tick": value.tick, "aspect": value.aspect,
                "sourceCameraPosition": [value.sourceCameraPosition.x, value.sourceCameraPosition.y, value.sourceCameraPosition.z],
                "sourceView": matrix(value.sourceView), "sourceProjection": matrix(value.sourceProjection),
                "sourceShadowMatrix": matrix(value.sourceShadowMatrix), "casterCount": value.casterCount,
                "triangleCount": value.triangleCount, "factors": value.factors]
        }
        @MainActor func freshState() -> [String: Any] {
            guard let fresh = freshRenderer else { return ["created": false, "testStrongReferencePresent": false] }
            return ["created": true, "testStrongReferencePresent": true,
                "distinctFromActiveRenderer": fresh !== activeRenderer,
                "sameDevice": fresh.device?.registryID == device.registryID,
                "sameScene": fresh.scene === scene, "samePointOfView": fresh.pointOfView === eye,
                "usesReverseZ": fresh.usesReverseZ, "autoenablesDefaultLighting": fresh.autoenablesDefaultLighting,
                "isPlaying": fresh.isPlaying, "delegateAbsent": fresh.delegate == nil,
                "renderCalls": 0, "prepareCalls": 0, "snapshotCalls": 0]
        }
        let initialCameraTransform = matrix(eye.simdWorldTransform)
        let initialFOV = camera.fieldOfView, initialCameraMask = camera.categoryBitMask
        let initialModelObjects = modelObjectIdentities()
        let initialLights = try JSONSerialization.data(withJSONObject: lightStates(), options: [.sortedKeys])
        var firstEncodedProjectorFrame: Data?
        @MainActor func assertInvariant(projectorInstalled: Bool) throws {
            XCTAssertEqual(state.game, initialGame)
            XCTAssertEqual(state.game.frame, 0); XCTAssertEqual(state.animationTick, 0)
            XCTAssertEqual(state.game.weaponFight?.triadPresentation.liveTick, 0)
            XCTAssertEqual(view.clockCallbacks, 0); XCTAssertEqual(packets.submittedPacketCount, 0)
            XCTAssertEqual(surface.submittedFrames, submittedFramesAfterDraw)
            XCTAssertEqual(surface.lastSubmittedTick, lastSubmittedTickAfterDraw)
            XCTAssertTrue(view.activeSourceEffectIDs.isEmpty)
            XCTAssertEqual(matrix(eye.simdWorldTransform), initialCameraTransform)
            XCTAssertEqual(camera.fieldOfView, initialFOV); XCTAssertEqual(camera.categoryBitMask, initialCameraMask)
            XCTAssertEqual(modelObjectIdentities(), initialModelObjects)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: lightStates(), options: [.sortedKeys]), initialLights)
            XCTAssertEqual(view.bounds.size, pixelSize); XCTAssertEqual(surface.bounds.size, pixelSize)
            XCTAssertTrue(view.triadRenderSurface === surface); XCTAssertTrue(surface.sceneRenderer === activeRenderer)
            XCTAssertTrue(view.scene === scene); XCTAssertTrue(view.pointOfView === eye); XCTAssertTrue(eye.camera === camera)
            XCTAssertTrue(activeRenderer.scene === scene); XCTAssertTrue(activeRenderer.pointOfView === eye)
            if projectorInstalled { XCTAssertTrue(surface.projectedShadow === originalProjector) }
            else { XCTAssertNil(surface.projectedShadow) }
            XCTAssertNil(state.loadError); XCTAssertNil(surface.lastFailure); XCTAssertNil(packets.lastFailure)
        }
        @MainActor func capture(_ label: String, projectorInstalled: Bool, isolation: String) throws {
            phase = label
            try assertInvariant(projectorInstalled: projectorInstalled)
            let image = try timed(label + "-synchronous-capture") {
                try surface.captureFrame(tick: 0, pixelSize: pixelSize, samples: 2)
            }
            try assertInvariant(projectorInstalled: projectorInstalled)
            let fight = try XCTUnwrap(state.game.weaponFight), data = try XCTUnwrap(image.pngData())
            XCTAssertEqual(image.cgImage?.width, 956); XCTAssertEqual(image.cgImage?.height, 440)
            let frame = projectorFrame()
            if projectorInstalled {
                XCTAssertEqual(originalProjector.lastFrame?.tick, 0)
                let encoded = try JSONSerialization.data(withJSONObject: frame, options: [.sortedKeys])
                if let previous = firstEncodedProjectorFrame { XCTAssertEqual(encoded, previous) }
                else { firstEncodedProjectorFrame = encoded }
            }
            var sample: [String: Any] = [
                "label": label, "frame": state.game.frame, "animationTick": state.animationTick,
                "sourceLiveTick": fight.triadPresentation.liveTick, "displayLinkCallbacks": view.clockCallbacks,
                "surfaceSubmittedFrames": surface.submittedFrames,
                "surfaceLastSubmittedTick": nullableInt(surface.lastSubmittedTick),
                "sourceIntroActive": fight.sourceIntroActive,
                "sourceStance": fight.sourceStance(0)?.motion.rawValue ?? "none",
                "sourceStanceTick": fight.sourceStance(0)?.tick ?? -1,
                "weaponReady": fight.canUse(.weapon, index: 0), "branchesReady": fight.canUseTriad(.branches, index: 0),
                "sourceEffectIDs": view.activeSourceEffectIDs, "submittedPackets": packets.submittedPacketCount,
                "sourceProjectorInstalled": surface.projectedShadow != nil, "projectorEncodedForCapture": projectorInstalled,
                "projectorLastFrame": frame, "activeSceneRebindCallsSoFar": activeSceneRebindCalls,
                "freshRendererCreationCallsSoFar": freshRendererCreationCalls, "freshAssociationCallsSoFar": freshAssociationCalls,
                "rendererRoute": "surface.captureFrame", "sameActiveSurface": view.triadRenderSurface === surface,
                "sameActiveRenderer": surface.sceneRenderer === activeRenderer,
                "sameScene": activeRenderer.scene === scene, "samePointOfView": activeRenderer.pointOfView === eye,
                "rendererUsesReverseZ": activeRenderer.usesReverseZ,
                "rendererAutoenablesDefaultLighting": activeRenderer.autoenablesDefaultLighting,
                "rendererIsPlaying": activeRenderer.isPlaying,
                "requestedSurfaceSamples": 2, "resolvedSurfaceSamples": DuelTriadRenderSurface.format(samples: 2).samples,
                "modelObjectIdentityUnchanged": modelObjectIdentities() == initialModelObjects,
                "simulationInvariant": state.game == initialGame && state.animationTick == 0
            ]
            sample["fighters"] = fight.fighters.enumerated().map { index, fighter in [
                "index": index, "hero": fighter.hero.rawValue, "x": fighter.x, "y": fighter.y,
                "health": fighter.health, "clip": fighter.weaponPose?.clip ?? "", "clipTick": fighter.weaponPose?.tick ?? -1
            ] as [String: Any] }
            sample["camera"] = ["modelWorldTransform": matrix(eye.simdWorldTransform),
                "presentationWorldTransform": matrix(eye.presentation.simdWorldTransform),
                "model": cameraValues(camera), "presentation": cameraValues(eye.presentation.camera),
                "metalProjection": matrix(try DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: pixelSize))]
            sample["lights"] = lightStates(); sample["sceneInventory"] = sceneInventory(); sample["freshRenderer"] = freshState()
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
            captures.append(["label": label, "frame": fight.frame, "animationTick": state.animationTick,
                "sourceLiveTick": fight.triadPresentation.liveTick, "rendererRoute": "surface.captureFrame", "isolation": isolation,
                "surfaceSubmittedFrames": surface.submittedFrames,
                "surfaceLastSubmittedTick": nullableInt(surface.lastSubmittedTick),
                "sourceProjectorInstalled": surface.projectedShadow != nil, "projectorEncodedForCapture": projectorInstalled,
                "submittedPackets": packets.submittedPacketCount, "activeSceneRebindCallsSoFar": activeSceneRebindCalls,
                "freshRendererCreationCallsSoFar": freshRendererCreationCalls, "freshAssociationCallsSoFar": freshAssociationCalls,
                "requestedSurfaceSamples": 2, "resolvedSurfaceSamples": DuelTriadRenderSurface.format(samples: 2).samples,
                "pngSHA256": DuelNetworkContentRecord.digest(data), "bytes": data.count, "width": 956, "height": 440,
                "pixelsRequireReview": true, "simulationAndModelCameraUnchanged": true])
        }

        try capture("registration-base-before", projectorInstalled: false,
                    isolation: "cold original surface; original projector detached before first explicit draw; no fresh renderer")
        phase = "restore-original-projector"
        timed(phase) {
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0; SCNTransaction.disableActions = true
            surface.projectedShadow = originalProjector
            SCNTransaction.commit(); SCNTransaction.flush()
        }
        try capture("registration-original-projector", projectorInstalled: true,
                    isolation: "same original projector restored; no active-renderer rebind or fresh renderer")

        phase = "rebind-active-scene-once"
        try assertInvariant(projectorInstalled: true)
        let rebindStarted = ProcessInfo.processInfo.systemUptime
        activeSceneRebindCalls += 1
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0; SCNTransaction.disableActions = true
        activeRenderer.scene = nil
        let nilSceneObserved = activeRenderer.scene == nil
        activeRenderer.scene = scene; activeRenderer.pointOfView = eye
        SCNTransaction.commit(); SCNTransaction.flush()
        let rebindSeconds = ProcessInfo.processInfo.systemUptime - rebindStarted
        timings.append(["phase": phase, "seconds": rebindSeconds])
        registrationOperations.append(["order": 1, "operation": "rebind-active-scene", "calls": activeSceneRebindCalls,
            "beforeCaptureLabel": "registration-original-projector", "afterCaptureLabel": "registration-original-rebound",
            "seconds": rebindSeconds, "nilSceneObserved": nilSceneObserved,
            "sameActiveRendererAfter": surface.sceneRenderer === activeRenderer,
            "sameSceneAfter": activeRenderer.scene === scene, "samePointOfViewAfter": activeRenderer.pointOfView === eye,
            "sameOriginalProjectorAfter": surface.projectedShadow === originalProjector])
        XCTAssertTrue(nilSceneObserved)
        try capture("registration-original-rebound", projectorInstalled: true,
                    isolation: "same active renderer rebound to the same scene and camera; original projector retained")

        phase = "associate-fresh-renderer-once"
        try assertInvariant(projectorInstalled: true)
        let associationStarted = ProcessInfo.processInfo.systemUptime
        XCTAssertNil(freshRenderer)
        freshRendererCreationCalls += 1
        freshRenderer = SCNRenderer(device: device, options: nil)
        if let fresh = freshRenderer {
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0; SCNTransaction.disableActions = true
            fresh.scene = scene; fresh.pointOfView = eye
            fresh.usesReverseZ = false; fresh.autoenablesDefaultLighting = false
            fresh.isPlaying = false; fresh.delegate = nil
            freshAssociationCalls += 1
            SCNTransaction.commit(); SCNTransaction.flush()
        }
        let associationSeconds = ProcessInfo.processInfo.systemUptime - associationStarted
        timings.append(["phase": phase, "seconds": associationSeconds])
        registrationOperations.append(["order": 2, "operation": "associate-fresh-renderer", "calls": freshAssociationCalls,
            "creationCalls": freshRendererCreationCalls,
            "beforeCaptureLabel": "registration-original-rebound", "afterCaptureLabel": "registration-fresh-associated",
            "seconds": associationSeconds, "freshRenderer": freshState(),
            "sameActiveRendererAfter": surface.sceneRenderer === activeRenderer,
            "sameSceneAfter": activeRenderer.scene === scene, "samePointOfViewAfter": activeRenderer.pointOfView === eye,
            "sameOriginalProjectorAfter": surface.projectedShadow === originalProjector])
        try capture("registration-fresh-associated", projectorInstalled: true,
                    isolation: "one fresh renderer associated without preparing or rendering; original surface and projector still capture")
        try assertInvariant(projectorInstalled: true)
        XCTAssertEqual(explicitDrawStateCalls, 1); XCTAssertEqual(activeSceneRebindCalls, 1)
        XCTAssertEqual(freshRendererCreationCalls, 1); XCTAssertEqual(freshAssociationCalls, 1)
        XCTAssertEqual(samples.count, 4); XCTAssertEqual(captures.count, 4); XCTAssertEqual(registrationOperations.count, 2)
        stateInvariant = state.game == initialGame && state.animationTick == 0 && view.clockCallbacks == 0
        XCTAssertTrue(stateInvariant)
        for index in 0..<3 {
            adjacentPNGEqualities.append((captures[index]["pngSHA256"] as? String) == (captures[index + 1]["pngSHA256"] as? String))
        }
        phase = "diagnostic-completed-pixels-pending"
        completed = true
    }
}
