import XCTest
import UIKit
import SceneKit
import Metal
import simd
@testable import ShiftReminder

/// One frame-zero preparation diagnostic on the existing production renderer.
/// No second renderer, snapshot API, simulation advance or pixel verdict is used.
@MainActor
final class DuelScenePreparationDiagnosticTests: XCTestCase {
    private enum Failure: Error { case sourceIdentity, missingWorld, unexpectedState }

    override func setUpWithError() throws { continueAfterFailure = false }

    func testInstalledScenePreparationAndProjectorAreIsolatedWithoutAdvancing() throws {
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
        var prepareCalls = 0
        var explicitDrawStateCalls = 0
        var restoredPNGEqualsOriginal: Any = NSNull()
        var basePNGEqualsBeforePreparation: Any = NSNull()
        var samples: [[String: Any]] = []
        var captures: [[String: Any]] = []
        var timings: [[String: Any]] = []
        var preparation: [String: Any] = [
            "api": "SCNRenderer.prepare(_:shouldAbortBlock:)",
            "target": "existing-active-surface-scene-renderer",
            "input": "same-installed-SCNScene", "synchronous": true,
            "calls": 0, "completionReturned": false, "success": NSNull(), "seconds": NSNull(),
            "beforeCaptureLabel": "prep-no-projector-before",
            "afterCaptureLabel": "prep-no-projector-after"
        ]
        var session: DuelSession?
        var world: DuelWorldView?
        var window: UIWindow?
        defer {
            // The later restoration defer runs first, with all render owners
            // alive. Cleanup is not a substitute for the fourth restored image.
            world?.shutdown()
            session?.shutdown()
            window?.isHidden = true
            let cleanup: [String: Any] = [
                "sceneReleased": world?.scene == nil,
                "surfaceReleased": world?.triadRenderSurface == nil,
                "rendererReleased": world?.triadMetalRenderer == nil,
                "sourceProjectorRestoredBeforeShutdown": sourceProjectorRestored,
                "activeClocksBefore": clocksBefore, "activeClocksAfter": DuelWorldView.activeClocks
            ]
            XCTAssertEqual(DuelWorldView.activeClocks, clocksBefore)
            let report: [String: Any] = [
                "schemaVersion": 1, "schema": "fighter-scene-preparation-diagnostic-v1",
                "releaseSHA256": releaseSHA,
                "scope": "One installed frame-zero active-renderer preparation and projector isolation",
                "diagnosticCompleted": completed, "lastPhase": phase,
                "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
                "samples": samples, "captures": captures, "timings": timings, "cleanup": cleanup,
                "preparation": preparation, "prepareCalls": prepareCalls,
                "explicitDrawStateCalls": explicitDrawStateCalls,
                "captureLabels": captures.compactMap { $0["label"] as? String },
                "captureSourceProjectorStates": captures.compactMap { $0["sourceProjectorInstalled"] as? Bool },
                "expectedSimulationFrames": [0], "simulationAdvanceCalls": 0,
                "stateInvariant": stateInvariant, "restorationInvariant": restorationInvariant,
                "restoredPNGEqualsOriginal": restoredPNGEqualsOriginal,
                "basePNGEqualsBeforePreparation": basePNGEqualsBeforePreparation,
                "freshRendererCreated": false, "snapshotCalls": 0,
                "combatStateInjected": false, "liveDisplayLinkAdvancesSelected": false,
                "sourcePacketsExpectedZero": true, "sceneKitLightsChanged": false,
                "uiExecutionStatus": "not_selected", "physicalDeviceValidated": false,
                "liveUIValidated": false, "audiblePlaybackVerified": false,
                "performanceVerified": false, "pixels": "PENDING", "panguEquipmentActivated": false,
                "captureTimingIncludesGPUReadbackWait": true,
                "timingWarning": "Construction, explicit draw, synchronous preparation and capture readback are separate wall times; none measures live FPS or isolated GPU time",
                "visibilityWarning": "Model and presentation transforms and geometric visibility are diagnostics, not proof of visible rendered pixels",
                "projectorWarning": "The retained projector lastFrame remains available while detached; it is not evidence that a detached capture encoded the projector"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "scene-preparation-diagnostic-report"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }

        @MainActor func timed<T>(_ label: String, _ operation: @MainActor () throws -> T) rethrows -> T {
            let start = ProcessInfo.processInfo.systemUptime
            defer { timings.append(["phase": label, "seconds": ProcessInfo.processInfo.systemUptime - start]) }
            return try operation()
        }
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
              let originalProjector = surface.projectedShadow else { throw Failure.missingWorld }
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
        defer {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            SCNTransaction.disableActions = true
            surface.projectedShadow = originalProjector
            SCNTransaction.commit()
            SCNTransaction.flush()
            sourceProjectorRestored = surface.projectedShadow === originalProjector
            restorationInvariant = sourceProjectorRestored && view.triadRenderSurface === surface &&
                surface.sceneRenderer === activeRenderer && activeRenderer.scene === scene &&
                activeRenderer.pointOfView === eye
            XCTAssertTrue(restorationInvariant)
        }
        let gameBeforeDraw = state.game
        phase = "frame-0-original-draw-submission"
        timed(phase) {
            explicitDrawStateCalls += 1
            view.drawState()
        }
        XCTAssertEqual(state.game, gameBeforeDraw)
        XCTAssertEqual(view.clockCallbacks, 0)
        XCTAssertNil(state.loadError)
        XCTAssertNil(surface.lastFailure)
        XCTAssertNil(packets.lastFailure)
        XCTAssertEqual(packets.submittedPacketCount, 0)
        XCTAssertTrue(view.activeSourceEffectIDs.isEmpty)
        let initialGame = state.game

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
            return ["exists": true, "fieldOfView": Double(value.fieldOfView),
                "near": value.zNear, "far": value.zFar,
                "usesOrthographicProjection": value.usesOrthographicProjection,
                "orthographicScale": value.orthographicScale, "categoryMask": value.categoryBitMask,
                "projectionTransform": projection(value.projectionTransform)]
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
                var masks = Set<Int>()
                var pending = [root]
                while let node = pending.popLast() {
                    if node.geometry != nil {
                        geometries += 1
                        masks.insert(node.categoryBitMask)
                        if effectivelyVisible(node) { visible += 1 }
                    }
                    if node.skinner != nil { skinners += 1 }
                    pending.append(contentsOf: node.childNodes)
                }
                rows.append(["name": root.name ?? "", "geometries": geometries,
                    "visibleGeometries": visible, "skinners": skinners,
                    "hidden": root.isHidden, "opacity": Double(root.opacity),
                    "categoryMasks": masks.sorted(), "worldTransform": matrix(root.simdWorldTransform),
                    "presentationWorldTransform": matrix(root.presentation.simdWorldTransform)])
            }
            return rows
        }
        var lightNodes: [SCNNode] = []
        var nodes = [scene.rootNode]
        while let node = nodes.popLast() {
            if node.light != nil { lightNodes.append(node) }
            nodes.append(contentsOf: node.childNodes)
        }
        @MainActor func lightStates() -> [[String: Any]] {
            var rows: [[String: Any]] = []
            for node in lightNodes {
                guard let light = node.light else { continue }
                rows.append(["name": node.name ?? "", "type": light.type.rawValue,
                    "castsShadow": light.castsShadow, "intensity": Double(light.intensity),
                    "hidden": node.isHidden, "worldTransform": matrix(node.simdWorldTransform)])
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
        let initialCameraTransform = matrix(eye.simdWorldTransform)
        let initialFOV = camera.fieldOfView
        let initialCameraMask = camera.categoryBitMask
        let initialModelObjects = modelObjectIdentities()
        let initialLights = try JSONSerialization.data(withJSONObject: lightStates(), options: [.sortedKeys])
        @MainActor func assertInvariant(projectorInstalled: Bool) throws {
            XCTAssertEqual(state.game, initialGame)
            XCTAssertEqual(state.game.frame, 0)
            XCTAssertEqual(state.animationTick, 0)
            XCTAssertEqual(state.game.weaponFight?.triadPresentation.liveTick, 0)
            XCTAssertEqual(view.clockCallbacks, 0)
            XCTAssertEqual(packets.submittedPacketCount, 0)
            XCTAssertTrue(view.activeSourceEffectIDs.isEmpty)
            XCTAssertEqual(matrix(eye.simdWorldTransform), initialCameraTransform)
            XCTAssertEqual(camera.fieldOfView, initialFOV)
            XCTAssertEqual(camera.categoryBitMask, initialCameraMask)
            XCTAssertEqual(modelObjectIdentities(), initialModelObjects)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: lightStates(), options: [.sortedKeys]), initialLights)
            XCTAssertEqual(view.bounds.size, pixelSize)
            XCTAssertEqual(surface.bounds.size, pixelSize)
            XCTAssertTrue(view.triadRenderSurface === surface)
            XCTAssertTrue(surface.sceneRenderer === activeRenderer)
            XCTAssertTrue(activeRenderer.scene === scene)
            XCTAssertTrue(activeRenderer.pointOfView === eye)
            if projectorInstalled { XCTAssertTrue(surface.projectedShadow === originalProjector) }
            else { XCTAssertNil(surface.projectedShadow) }
            XCTAssertNil(state.loadError)
            XCTAssertNil(surface.lastFailure)
            XCTAssertNil(packets.lastFailure)
        }
        @MainActor func capture(_ label: String, projectorInstalled: Bool, isolation: String) throws {
            phase = label
            try assertInvariant(projectorInstalled: projectorInstalled)
            let image = try timed(label + "-synchronous-capture") {
                try surface.captureFrame(tick: 0, pixelSize: pixelSize, samples: 2)
            }
            try assertInvariant(projectorInstalled: projectorInstalled)
            let fight = try XCTUnwrap(state.game.weaponFight)
            let data = try XCTUnwrap(image.pngData())
            XCTAssertEqual(image.cgImage?.width, 956)
            XCTAssertEqual(image.cgImage?.height, 440)
            XCTAssertEqual(originalProjector.lastFrame?.tick, 0)
            samples.append([
                "label": label, "frame": state.game.frame, "animationTick": state.animationTick,
                "sourceLiveTick": fight.triadPresentation.liveTick, "displayLinkCallbacks": view.clockCallbacks,
                "sourceIntroActive": fight.sourceIntroActive,
                "sourceStance": fight.sourceStance(0)?.motion.rawValue ?? "none",
                "sourceStanceTick": fight.sourceStance(0)?.tick ?? -1,
                "weaponReady": fight.canUse(.weapon, index: 0),
                "branchesReady": fight.canUseTriad(.branches, index: 0),
                "fighters": fight.fighters.enumerated().map { index, fighter in [
                    "index": index, "hero": fighter.hero.rawValue, "x": fighter.x,
                    "y": fighter.y, "health": fighter.health,
                    "clip": fighter.weaponPose?.clip ?? "", "clipTick": fighter.weaponPose?.tick ?? -1
                ] as [String: Any] },
                "sourceEffectIDs": view.activeSourceEffectIDs,
                "submittedPackets": packets.submittedPacketCount,
                "sourceProjectorInstalled": surface.projectedShadow != nil,
                "projectorEncodedForCapture": projectorInstalled,
                "projectorLastFrame": projectorFrame(),
                "prepareCallsSoFar": prepareCalls,
                "prepareSuccessSoFar": preparation["success"] ?? NSNull(),
                "rendererRoute": "surface.captureFrame", "sameActiveSurface": view.triadRenderSurface === surface,
                "sameActiveRenderer": surface.sceneRenderer === activeRenderer,
                "sameScene": activeRenderer.scene === scene, "samePointOfView": activeRenderer.pointOfView === eye,
                "rendererUsesReverseZ": activeRenderer.usesReverseZ,
                "rendererAutoenablesDefaultLighting": activeRenderer.autoenablesDefaultLighting,
                "rendererIsPlaying": activeRenderer.isPlaying,
                "requestedSurfaceSamples": 2, "resolvedSurfaceSamples": DuelTriadRenderSurface.format(samples: 2).samples,
                "camera": ["modelWorldTransform": matrix(eye.simdWorldTransform),
                    "presentationWorldTransform": matrix(eye.presentation.simdWorldTransform),
                    "model": cameraValues(camera), "presentation": cameraValues(eye.presentation.camera),
                    "metalProjection": matrix(try DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: pixelSize))],
                "lights": lightStates(), "sceneInventory": sceneInventory(),
                "viewport": ["pointsWidth": Double(view.bounds.width), "pointsHeight": Double(view.bounds.height),
                    "drawableWidth": Double(surface.drawableSize.width), "drawableHeight": Double(surface.drawableSize.height),
                    "viewScale": Double(view.contentScaleFactor), "surfaceScale": Double(surface.contentScaleFactor),
                    "captureWidth": 956, "captureHeight": 440],
                "rendererFailure": packets.lastFailure.map { String(describing: $0) } ?? "",
                "surfaceFailure": surface.lastFailure.map { String(describing: $0) } ?? "",
                "sourcePreparationFailure": view.triadPreparationFailure ?? "",
                "modelObjectIdentityUnchanged": modelObjectIdentities() == initialModelObjects,
                "simulationInvariant": state.game == initialGame && state.animationTick == 0
            ])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
            captures.append(["label": label, "frame": fight.frame, "animationTick": state.animationTick,
                "sourceLiveTick": fight.triadPresentation.liveTick, "rendererRoute": "surface.captureFrame",
                "isolation": isolation, "sourceProjectorInstalled": surface.projectedShadow != nil,
                "projectorEncodedForCapture": projectorInstalled, "submittedPackets": packets.submittedPacketCount,
                "prepareCallsSoFar": prepareCalls, "requestedSurfaceSamples": 2,
                "resolvedSurfaceSamples": DuelTriadRenderSurface.format(samples: 2).samples,
                "pngSHA256": DuelNetworkContentRecord.digest(data), "bytes": data.count,
                "width": 956, "height": 440, "pixelsRequireReview": true,
                "simulationAndModelCameraUnchanged": true])
        }
        @MainActor func installProjector(_ enabled: Bool) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            SCNTransaction.disableActions = true
            surface.projectedShadow = enabled ? originalProjector : nil
            SCNTransaction.commit()
            SCNTransaction.flush()
        }

        try capture("prep-original-before", projectorInstalled: true,
                    isolation: "original projector; before explicit active-renderer preparation")
        installProjector(false)
        try capture("prep-no-projector-before", projectorInstalled: false,
                    isolation: "projector detached; before explicit active-renderer preparation")
        phase = "prepare-active-scene-renderer-once"
        try assertInvariant(projectorInstalled: false)
        preparation["targetIsActiveSceneRendererBefore"] = surface.sceneRenderer === activeRenderer
        preparation["sceneMatchesBefore"] = activeRenderer.scene === scene
        preparation["pointOfViewMatchesBefore"] = activeRenderer.pointOfView === eye
        preparation["sourceProjectorAbsentBefore"] = surface.projectedShadow == nil
        let prepareStarted = ProcessInfo.processInfo.systemUptime
        prepareCalls += 1
        preparation["calls"] = prepareCalls
        let prepareSucceeded = activeRenderer.prepare(scene, shouldAbortBlock: nil)
        let prepareSeconds = ProcessInfo.processInfo.systemUptime - prepareStarted
        timings.append(["phase": phase, "seconds": prepareSeconds])
        preparation["completionReturned"] = true
        preparation["success"] = prepareSucceeded
        preparation["seconds"] = prepareSeconds
        preparation["targetIsActiveSceneRendererAfter"] = surface.sceneRenderer === activeRenderer
        preparation["sceneMatchesAfter"] = activeRenderer.scene === scene
        preparation["pointOfViewMatchesAfter"] = activeRenderer.pointOfView === eye
        preparation["sourceProjectorAbsentAfter"] = surface.projectedShadow == nil
        preparation["simulationInvariantAfter"] = state.game == initialGame && state.animationTick == 0
        try assertInvariant(projectorInstalled: false)
        // Preserve the after/restore images even when prepare returned false.
        // The failed preparation is asserted only after this capture closure.
        try capture("prep-no-projector-after", projectorInstalled: false,
                    isolation: "projector detached; after one synchronous active-renderer preparation")
        installProjector(true)
        try capture("prep-original-after", projectorInstalled: true,
                    isolation: "same original projector restored; after explicit active-renderer preparation")
        try assertInvariant(projectorInstalled: true)
        XCTAssertEqual(prepareCalls, 1)
        XCTAssertEqual(explicitDrawStateCalls, 1)
        XCTAssertEqual(samples.count, 4)
        XCTAssertEqual(captures.count, 4)
        stateInvariant = state.game == initialGame && state.animationTick == 0 && view.clockCallbacks == 0
        XCTAssertTrue(stateInvariant)
        restoredPNGEqualsOriginal = (captures[0]["pngSHA256"] as? String) == (captures[3]["pngSHA256"] as? String)
        basePNGEqualsBeforePreparation = (captures[1]["pngSHA256"] as? String) == (captures[2]["pngSHA256"] as? String)
        phase = prepareSucceeded ? "diagnostic-completed-pixels-pending" : "diagnostic-captured-prepare-failed"
        completed = true
        XCTAssertTrue(prepareSucceeded, "The existing active SceneKit renderer did not prepare the installed scene")
    }
}
