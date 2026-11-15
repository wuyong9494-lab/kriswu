import XCTest
import UIKit
import SceneKit
import Metal
import simd
@testable import ShiftReminder

/// One new frame-zero diagnostic. It does not repeat the successful 394-step
/// entrance method, advance gameplay, or certify pixels or live performance.
@MainActor
final class DuelSceneBasePassDiagnosticTests: XCTestCase {
    private enum Failure: Error { case sourceIdentity, missingWorld, unexpectedState }

    override func setUpWithError() throws { continueAfterFailure = false }

    func testInstalledBaseSceneSeparatesSceneKitShadowAndSurfaceWithoutAdvancing() throws {
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
        var restoredPNGEqualsOriginal: Any = NSNull()
        var samples: [[String: Any]] = []
        var captures: [[String: Any]] = []
        var timings: [[String: Any]] = []
        var session: DuelSession?
        var world: DuelWorldView?
        var window: UIWindow?
        var freshRendererReleased = false
        var sourceProjectorRestored = false
        var sceneKitLightRestored = false
        defer {
            // The later restoration defer runs first, while every render owner
            // is still alive. Teardown must not substitute for an A/B restore.
            world?.shutdown()
            session?.shutdown()
            window?.isHidden = true
            let cleanup: [String: Any] = [
                "sceneReleased": world?.scene == nil,
                "surfaceReleased": world?.triadRenderSurface == nil,
                "rendererReleased": world?.triadMetalRenderer == nil,
                "freshRendererReleased": freshRendererReleased,
                "sourceProjectorRestoredBeforeShutdown": sourceProjectorRestored,
                "sceneKitLightRestoredBeforeShutdown": sceneKitLightRestored,
                "activeClocksBefore": clocksBefore,
                "activeClocksAfter": DuelWorldView.activeClocks
            ]
            XCTAssertEqual(DuelWorldView.activeClocks, clocksBefore)
            let report: [String: Any] = [
                "schemaVersion": 1, "schema": "fighter-scene-base-pass-diagnostic-v1",
                "releaseSHA256": releaseSHA,
                "scope": "One installed frame-zero SceneKit shadow and surface-path isolation",
                "diagnosticCompleted": completed, "lastPhase": phase,
                "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
                "samples": samples, "captures": captures, "timings": timings, "cleanup": cleanup,
                "captureLabels": captures.compactMap { $0["label"] as? String },
                "expectedSimulationFrames": [0], "simulationAdvanceCalls": 0,
                "stateInvariant": stateInvariant, "restorationInvariant": restorationInvariant,
                "restoredPNGEqualsOriginal": restoredPNGEqualsOriginal,
                "combatStateInjected": false, "liveDisplayLinkAdvancesSelected": false,
                "sourceProjectorRemovedForAllCaptures": true, "sourcePacketsExpectedZero": true,
                "uiExecutionStatus": "not_selected", "physicalDeviceValidated": false,
                "liveUIValidated": false, "audiblePlaybackVerified": false,
                "performanceVerified": false, "pixels": "PENDING", "panguEquipmentActivated": false,
                "captureTimingIncludesGPUReadbackWait": true,
                "timingWarning": "Construction, explicit draw, surface readback and SceneKit snapshot wall times are separate; none measures live FPS or isolated GPU time",
                "visibilityWarning": "Node visibility, frustum queries and projected centers are geometric diagnostics, not proof of visible rendered pixels"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "scene-base-pass-diagnostic-report"
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
              let device = surface.device, let originalProjector = surface.projectedShadow else {
            throw Failure.missingWorld
        }
        XCTAssertEqual(Set(assets.catalog.profiles.map(\.id)), Set(["sun_triad", "liu_hammers"]))
        XCTAssertNil(assets.panguAudio)
        XCTAssertFalse(assets.catalog.profiles.contains(where: \.isPangu))
        XCTAssertEqual(DuelTriadRenderSurface.format(samples: 2).samples, 4,
                       "This diagnostic is bound to the reviewed Simulator 4x path")
        XCTAssertTrue(device.supportsTextureSampleCount(1))
        XCTAssertTrue(device.supportsTextureSampleCount(4))
        XCTAssertEqual(state.game.frame, 0)
        XCTAssertEqual(state.animationTick, 0)
        XCTAssertEqual(view.clockCallbacks, 0)
        XCTAssertEqual(view.bounds.size, pixelSize)
        XCTAssertEqual(surface.bounds.size, pixelSize)
        XCTAssertTrue(surface.sceneRenderer.scene === scene)
        XCTAssertTrue(surface.sceneRenderer.pointOfView === eye)

        var lightNodes: [SCNNode] = []
        var directionalShadowLights: [SCNLight] = []
        var pending = [scene.rootNode]
        while let node = pending.popLast() {
            if let light = node.light {
                lightNodes.append(node)
                if light.type == .directional && light.castsShadow { directionalShadowLights.append(light) }
            }
            pending.append(contentsOf: node.childNodes)
        }
        guard directionalShadowLights.count == 1, let keyLight = directionalShadowLights.first else {
            throw Failure.unexpectedState
        }
        let originalKeyCastsShadow = keyLight.castsShadow
        let fresh = timed("construct-fresh-renderer") { SCNRenderer(device: device, options: nil) }
        fresh.scene = scene; fresh.pointOfView = eye
        fresh.usesReverseZ = false
        fresh.autoenablesDefaultLighting = false
        fresh.isPlaying = false
        fresh.delegate = nil
        defer {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            SCNTransaction.disableActions = true
            keyLight.castsShadow = originalKeyCastsShadow
            surface.projectedShadow = originalProjector
            SCNTransaction.commit()
            SCNTransaction.flush()
            sourceProjectorRestored = surface.projectedShadow === originalProjector
            sceneKitLightRestored = keyLight.castsShadow == originalKeyCastsShadow
            fresh.delegate = nil; fresh.scene = nil; fresh.pointOfView = nil
            freshRendererReleased = fresh.scene == nil && fresh.pointOfView == nil
            restorationInvariant = sourceProjectorRestored && sceneKitLightRestored && freshRendererReleased
            XCTAssertTrue(restorationInvariant)
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        surface.projectedShadow = nil
        SCNTransaction.commit()
        SCNTransaction.flush()
        timed("frame-0-draw-submission") { view.drawState() }
        XCTAssertNil(state.loadError)
        XCTAssertNil(surface.lastFailure)
        XCTAssertNil(packets.lastFailure)
        XCTAssertEqual(packets.submittedPacketCount, 0)
        XCTAssertTrue(view.activeSourceEffectIDs.isEmpty)
        let initialGame = state.game
        let initialAnimationTick = state.animationTick

        func matrix(_ value: simd_float4x4) -> [Float] {
            (0..<4).flatMap { column in (0..<4).map { row in value[column][row] } }
        }
        func projection(_ value: SCNMatrix4) -> [Float] {
            [Float(value.m11), Float(value.m12), Float(value.m13), Float(value.m14),
             Float(value.m21), Float(value.m22), Float(value.m23), Float(value.m24),
             Float(value.m31), Float(value.m32), Float(value.m33), Float(value.m34),
             Float(value.m41), Float(value.m42), Float(value.m43), Float(value.m44)]
        }
        func vector(_ value: SCNVector3) -> Any {
            guard value.x.isFinite, value.y.isFinite, value.z.isFinite else { return NSNull() }
            return [Float(value.x), Float(value.y), Float(value.z)]
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
        @MainActor func sceneInventory(_ renderer: SCNRenderer) -> [[String: Any]] {
            var rows: [[String: Any]] = []
            for root in scene.rootNode.childNodes {
                var geometries = 0, visible = 0, frustum = 0, visibleInFrustum = 0, skinners = 0
                var masks = Set<Int>()
                var nodes = [root]
                while let node = nodes.popLast() {
                    if node.geometry != nil {
                        geometries += 1
                        masks.insert(node.categoryBitMask)
                        let inFrustum = renderer.isNode(node, insideFrustumOf: eye)
                        if inFrustum { frustum += 1 }
                        if effectivelyVisible(node) {
                            visible += 1
                            if inFrustum { visibleInFrustum += 1 }
                        }
                    }
                    if node.skinner != nil { skinners += 1 }
                    nodes.append(contentsOf: node.childNodes)
                }
                rows.append(["name": root.name ?? "", "geometries": geometries,
                    "visibleGeometries": visible, "frustumGeometries": frustum,
                    "visibleFrustumGeometries": visibleInFrustum, "skinners": skinners,
                    "hidden": root.isHidden, "opacity": Double(root.opacity),
                    "categoryMasks": masks.sorted(), "worldTransform": matrix(root.simdWorldTransform),
                    "presentationWorldTransform": matrix(root.presentation.simdWorldTransform)])
            }
            return rows
        }
        @MainActor func projectedActorCenters(_ renderer: SCNRenderer) throws -> [[String: Any]] {
            var rows: [[String: Any]] = []
            for index in 0..<2 {
                guard let actor = scene.rootNode.childNode(withName: "duel.actor.\(index)", recursively: false) else {
                    throw Failure.unexpectedState
                }
                let box = actor.boundingBox
                let center = SCNVector3((box.min.x + box.max.x) / 2,
                                       (box.min.y + box.max.y) / 2,
                                       (box.min.z + box.max.z) / 2)
                let modelWorld = actor.convertPosition(center, to: nil)
                let presentationWorld = actor.presentation.convertPosition(center, to: nil)
                rows.append(["index": index, "name": actor.name ?? "",
                    "centerBasis": "midpoint of recorded model local boundingBox; not a skinned pixel bound",
                    "localBoundingMin": vector(box.min), "localBoundingMax": vector(box.max),
                    "modelWorldCenter": vector(modelWorld), "presentationWorldCenter": vector(presentationWorld),
                    "modelProjectedCenter": vector(renderer.projectPoint(modelWorld)),
                    "presentationProjectedCenter": vector(renderer.projectPoint(presentationWorld)),
                    "modelRootInsideFrustum": renderer.isNode(actor, insideFrustumOf: eye),
                    "presentationRootInsideFrustum": renderer.isNode(actor.presentation, insideFrustumOf: eye)])
            }
            return rows
        }
        @MainActor func lightStates() -> [[String: Any]] {
            var rows: [[String: Any]] = []
            for node in lightNodes {
                guard let light = node.light else { continue }
                rows.append(["name": node.name ?? "", "type": light.type.rawValue,
                    "castsShadow": light.castsShadow, "isSelectedKeyLight": light === keyLight,
                    "intensity": Double(light.intensity), "hidden": node.isHidden,
                    "worldTransform": matrix(node.simdWorldTransform)])
            }
            return rows
        }
        let initialCameraTransform = matrix(eye.simdWorldTransform)
        let initialFOV = camera.fieldOfView
        let initialCameraMask = camera.categoryBitMask
        @MainActor func assertInvariant() {
            XCTAssertEqual(state.game, initialGame)
            XCTAssertEqual(state.game.frame, 0)
            XCTAssertEqual(state.animationTick, initialAnimationTick)
            XCTAssertEqual(state.animationTick, 0)
            XCTAssertEqual(state.game.weaponFight?.triadPresentation.liveTick, 0)
            XCTAssertEqual(view.clockCallbacks, 0)
            XCTAssertNil(surface.projectedShadow)
            XCTAssertEqual(packets.submittedPacketCount, 0)
            XCTAssertTrue(view.activeSourceEffectIDs.isEmpty)
            XCTAssertEqual(matrix(eye.simdWorldTransform), initialCameraTransform)
            XCTAssertEqual(camera.fieldOfView, initialFOV)
            XCTAssertEqual(camera.categoryBitMask, initialCameraMask)
            XCTAssertEqual(view.bounds.size, pixelSize)
            XCTAssertEqual(surface.bounds.size, pixelSize)
            XCTAssertTrue(surface.sceneRenderer.scene === scene)
            XCTAssertTrue(surface.sceneRenderer.pointOfView === eye)
            XCTAssertTrue(fresh.scene === scene)
            XCTAssertTrue(fresh.pointOfView === eye)
            XCTAssertNil(state.loadError)
            XCTAssertNil(surface.lastFailure)
            XCTAssertNil(packets.lastFailure)
        }
        @MainActor func capture(_ label: String, route: String, isolation: String,
                                surfaceSamples: Int?, renderer: SCNRenderer,
                                _ operation: @MainActor () throws -> UIImage) throws {
            phase = label
            assertInvariant()
            let image = try timed(label + "-synchronous-capture", operation)
            assertInvariant()
            let fight = try XCTUnwrap(state.game.weaponFight)
            let data = try XCTUnwrap(image.pngData())
            XCTAssertEqual(image.cgImage?.width, 956)
            XCTAssertEqual(image.cgImage?.height, 440)
            let requested: Any, resolved: Any, snapshotAA: Any
            if let surfaceSamples {
                requested = surfaceSamples
                resolved = DuelTriadRenderSurface.format(samples: surfaceSamples).samples
                snapshotAA = NSNull()
            } else {
                requested = NSNull(); resolved = NSNull()
                snapshotAA = "multisampling4X"
            }
            let sample: [String: Any] = [
                "label": label, "frame": state.game.frame, "animationTick": state.animationTick,
                "sourceLiveTick": fight.triadPresentation.liveTick, "displayLinkCallbacks": view.clockCallbacks,
                "sourceIntroActive": fight.sourceIntroActive,
                "sourceStance": fight.sourceStance(0)?.motion.rawValue ?? "none",
                "sourceStanceTick": fight.sourceStance(0)?.tick ?? -1,
                "sourceEffectIDs": view.activeSourceEffectIDs,
                "submittedPackets": packets.submittedPacketCount, "sourceProjectorInstalled": surface.projectedShadow != nil,
                "selectedKeyLightCastsShadow": keyLight.castsShadow, "lights": lightStates(),
                "rendererRoute": route, "requestedSurfaceSamples": requested, "resolvedSurfaceSamples": resolved,
                "requestedSnapshotAntialiasing": snapshotAA,
                "sameScene": renderer.scene === scene, "samePointOfView": renderer.pointOfView === eye,
                "rendererUsesReverseZ": renderer.usesReverseZ,
                "rendererAutoenablesDefaultLighting": renderer.autoenablesDefaultLighting,
                "rendererIsPlaying": renderer.isPlaying,
                "camera": ["modelWorldTransform": matrix(eye.simdWorldTransform),
                    "presentationWorldTransform": matrix(eye.presentation.simdWorldTransform),
                    "model": cameraValues(camera), "presentation": cameraValues(eye.presentation.camera),
                    "metalProjection": matrix(try DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: pixelSize))],
                "sceneInventory": sceneInventory(renderer), "projectedActorCenters": try projectedActorCenters(renderer),
                "viewport": ["pointsWidth": Double(view.bounds.width), "pointsHeight": Double(view.bounds.height),
                    "drawableWidth": Double(surface.drawableSize.width), "drawableHeight": Double(surface.drawableSize.height),
                    "viewScale": Double(view.contentScaleFactor), "surfaceScale": Double(surface.contentScaleFactor),
                    "captureWidth": 956, "captureHeight": 440],
                "rendererFailure": packets.lastFailure.map { String(describing: $0) } ?? "",
                "surfaceFailure": surface.lastFailure.map { String(describing: $0) } ?? "",
                "sourcePreparationFailure": view.triadPreparationFailure ?? "",
                "simulationInvariant": state.game == initialGame && state.animationTick == initialAnimationTick
            ]
            samples.append(sample)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
            captures.append(["label": label, "frame": fight.frame,
                "animationTick": state.animationTick, "sourceLiveTick": fight.triadPresentation.liveTick,
                "rendererRoute": route, "isolation": isolation,
                "sceneKitLightShadowEnabled": keyLight.castsShadow,
                "sourceProjectorInstalled": false, "submittedPackets": packets.submittedPacketCount,
                "requestedSurfaceSamples": requested, "resolvedSurfaceSamples": resolved,
                "requestedSnapshotAntialiasing": snapshotAA,
                "pngSHA256": DuelNetworkContentRecord.digest(data), "bytes": data.count,
                "width": 956, "height": 440, "pixelsRequireReview": true,
                "simulationAndModelCameraUnchanged": true])
        }
        @MainActor func setKeyLightShadow(_ enabled: Bool) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            SCNTransaction.disableActions = true
            keyLight.castsShadow = enabled
            SCNTransaction.commit()
            SCNTransaction.flush()
        }

        try capture("base-scene-original-4x", route: "surface.captureFrame",
                    isolation: "source projector removed; original SceneKit key-light shadow retained",
                    surfaceSamples: 2, renderer: surface.sceneRenderer) {
            try surface.captureFrame(tick: 0, pixelSize: pixelSize, samples: 2)
        }
        setKeyLightShadow(false)
        try capture("base-scene-no-scenekit-shadow-4x", route: "surface.captureFrame",
                    isolation: "source projector removed; only original key-light castsShadow disabled",
                    surfaceSamples: 2, renderer: surface.sceneRenderer) {
            try surface.captureFrame(tick: 0, pixelSize: pixelSize, samples: 2)
        }
        try capture("base-scene-no-scenekit-shadow-1x", route: "surface.captureFrame",
                    isolation: "source projector removed; key-light shadow disabled; surface samples 1",
                    surfaceSamples: 1, renderer: surface.sceneRenderer) {
            try surface.captureFrame(tick: 0, pixelSize: pixelSize, samples: 1)
        }
        try capture("base-scene-snapshot-no-scenekit-shadow", route: "freshSCNRenderer.snapshot",
                    isolation: "same scene and camera; source projector removed; key-light shadow disabled; fresh SceneKit snapshot",
                    surfaceSamples: nil, renderer: fresh) {
            fresh.snapshot(atTime: 0, with: pixelSize, antialiasingMode: .multisampling4X)
        }
        setKeyLightShadow(originalKeyCastsShadow)
        try capture("base-scene-snapshot-original", route: "freshSCNRenderer.snapshot",
                    isolation: "same scene and camera; source projector removed; original key-light shadow restored; fresh SceneKit snapshot",
                    surfaceSamples: nil, renderer: fresh) {
            fresh.snapshot(atTime: 0, with: pixelSize, antialiasingMode: .multisampling4X)
        }
        try capture("base-scene-restored-4x", route: "surface.captureFrame",
                    isolation: "original surface and key-light shadow restored; source projector remains removed",
                    surfaceSamples: 2, renderer: surface.sceneRenderer) {
            try surface.captureFrame(tick: 0, pixelSize: pixelSize, samples: 2)
        }
        assertInvariant()
        XCTAssertEqual(samples.count, 6)
        XCTAssertEqual(captures.count, 6)
        XCTAssertEqual(keyLight.castsShadow, originalKeyCastsShadow)
        stateInvariant = state.game == initialGame && state.animationTick == 0 && view.clockCallbacks == 0
        XCTAssertTrue(stateInvariant)
        restoredPNGEqualsOriginal = (captures.first?["pngSHA256"] as? String) == (captures.last?["pngSHA256"] as? String)
        phase = "diagnostic-completed-pixels-pending"
        completed = true
    }
}
