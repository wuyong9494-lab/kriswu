import XCTest
import UIKit
import SceneKit
import Metal
import simd
@testable import ShiftReminder

/// The first complete offscreen encoding after normal cold World assembly.
/// A non-black PNG only rejects the known empty frame; visual review is separate.
@MainActor
final class DuelSceneAssemblyFollowupTests: XCTestCase {
    private enum Failure: Error { case sourceIdentity, missingWorld }

    override func setUpWithError() throws { continueAfterFailure = false }

    func testInstalledColdSceneAssemblyRendersFirstFullFrameWithoutRegistrationWorkarounds() throws {
        let releaseSHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
        guard Bundle.main.object(forInfoDictionaryKey: DuelFighterAssetRelease.infoKey) as? String == releaseSHA else {
            throw Failure.sourceIdentity
        }
        let clocksBefore = DuelWorldView.activeClocks
        let started = ProcessInfo.processInfo.systemUptime
        var phase = "construct-session"
        var completed = false
        var stateInvariant = false
        var identityInvariant = false
        var nonBlackRegressionPassed = false
        var captureFrameCalls = 0
        var construction: [String: Any] = [:]
        var beforeFirstCapture: [String: Any] = [:]
        var pixelStatistics: [String: Any] = [:]
        var samples: [[String: Any]] = []
        var captures: [[String: Any]] = []
        var timings: [[String: Any]] = []
        var session: DuelSession?
        var world: DuelWorldView?
        var window: UIWindow?
        var capturedSurface: DuelTriadRenderSurface?
        var capturedRenderer: SCNRenderer?
        var reportFinalized = false
        @MainActor func finalizeReport() {
            guard !reportFinalized else { return }
            reportFinalized = true
            world?.shutdown()
            session?.shutdown()
            window?.isHidden = true
            let cleanup: [String: Any] = [
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
            var report: [String: Any] = [
                "schemaVersion": 1, "schema": "fighter-scene-assembly-followup-v1",
                "scope": "installed-scene-assembly-followup-one", "releaseSHA256": releaseSHA,
                "diagnosticCompleted": completed, "lastPhase": phase,
                "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started,
                "construction": construction, "beforeFirstCapture": beforeFirstCapture,
                "samples": samples, "captures": captures, "timings": timings, "cleanup": cleanup,
                "pixelStatistics": pixelStatistics, "nonBlackRegressionPassed": nonBlackRegressionPassed,
                "captureLabels": captures.compactMap { $0["label"] as? String },
                "expectedSimulationFrames": [0], "simulationAdvanceCalls": 0,
                "explicitDrawStateCalls": 0, "captureFrameCalls": captureFrameCalls,
                "activeSceneRebindCalls": 0, "freshRendererCreationCalls": 0,
                "freshAssociationCalls": 0, "explicitPrepareCalls": 0, "snapshotCalls": 0,
                "projectorDetachCalls": 0, "stateInvariant": stateInvariant, "identityInvariant": identityInvariant,
                "combatStateInjected": false, "liveDisplayLinkAdvancesSelected": false,
                "sourcePacketsExpectedZero": true, "sceneKitLightsChanged": false,
                "firstCompleteOffscreenEncodingSelected": true, "normalDrawablePresentationValidated": false,
                "uiExecutionStatus": "not_selected", "physicalDeviceValidated": false,
                "liveUIValidated": false, "audiblePlaybackVerified": false,
                "performanceVerified": false, "pixels": "PENDING", "panguEquipmentActivated": false,
                "captureTimingIncludesGPUReadbackWait": true
            ]
            report["pixelWarning"] = "A visible non-black pixel rejects the known opaque-black or empty-transparent frame only; composition, characters, effects and source accuracy still require review"
            report["submissionWarning"] = "World retains its construction-time pose sampling; this test does not drawState. The first capture encodes offscreen and invokes the original submitted-frame callback but does not present a drawable or increment submittedFrames"
            report["preparationWarning"] = "The test calls no prepare, rebind or auxiliary renderer; normal World mounting may retain its existing asynchronous SCNView music preparation"
            report["timingWarning"] = "Construction, mounting and synchronous offscreen readback are wall times, not live FPS or isolated GPU performance"
            report["lifecycleWarning"] = "Cleanup verifies cleared owners and bindings, not ARC deallocation"
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "scene-assembly-followup-report"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        defer { finalizeReport() }

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
            return ["exists": true, "fieldOfView": Double(value.fieldOfView), "near": value.zNear, "far": value.zFar,
                "usesOrthographicProjection": value.usesOrthographicProjection, "orthographicScale": value.orthographicScale,
                "categoryMask": value.categoryBitMask, "projectionTransform": projection(value.projectionTransform)]
        }

        let state = timed("construct-session") {
            DuelSession(.init(hero: .ember, difficulty: .learning, mode: .practice, originalWeapons: true))
        }
        session = state
        phase = "construct-world"
        let view = timed(phase) { DuelWorldView(session: state) }
        world = view
        guard state.loadError == nil, view.stageAsset != nil,
              let assets = state.weaponAssets, let release = assets.release,
              release.definition.id == "h17-shared-root-floorfall-20261115-v2",
              let scene = view.scene, let eye = view.pointOfView, let camera = eye.camera,
              let surface = view.triadRenderSurface, let packets = view.triadMetalRenderer,
              let device = surface.device, let projector = surface.projectedShadow,
              let frameDriver = surface.delegate as? DuelTriadSurfaceFrameDriver else { throw Failure.missingWorld }
        let activeRenderer = surface.sceneRenderer
        capturedSurface = surface; capturedRenderer = activeRenderer
        XCTAssertEqual(Set(assets.catalog.profiles.map(\.id)), Set(["sun_triad", "liu_hammers"]))
        XCTAssertNil(assets.panguAudio)
        XCTAssertFalse(assets.catalog.profiles.contains(where: \.isPangu))
        XCTAssertEqual(view.triadSurfaceCreationAttempts, 1)
        XCTAssertTrue(view.initialPoseAppliedBeforeTriadSurface)
        XCTAssertTrue(view.sceneAssemblyCompletedForDiagnostics)
        XCTAssertEqual(view.subviews.compactMap { $0 as? DuelTriadRenderSurface }.count, 1)
        XCTAssertEqual(surface.submittedFrames, 0); XCTAssertNil(surface.lastSubmittedTick)
        XCTAssertNil(projector.lastFrame)
        XCTAssertNotNil(surface.didSubmitFrame); XCTAssertNotNil(surface.lateSourceGeometry)
        XCTAssertTrue(surface.packetRenderer === packets)
        XCTAssertTrue(activeRenderer.scene === scene); XCTAssertTrue(activeRenderer.pointOfView === eye)
        XCTAssertEqual(activeRenderer.device?.registryID, device.registryID)
        XCTAssertFalse(activeRenderer.usesReverseZ); XCTAssertFalse(activeRenderer.autoenablesDefaultLighting)
        XCTAssertFalse(activeRenderer.isPlaying); XCTAssertNil(activeRenderer.delegate)
        XCTAssertFalse(view.rendersContinuously); XCTAssertFalse(view.isPlaying)
        XCTAssertEqual(state.game.frame, 0); XCTAssertEqual(state.animationTick, 0)
        XCTAssertEqual(view.clockCallbacks, 0); XCTAssertEqual(packets.submittedPacketCount, 0)
        construction = [
            "sceneAssemblyCompleted": view.sceneAssemblyCompletedForDiagnostics,
            "surfaceCreationAttempts": view.triadSurfaceCreationAttempts,
            "initialPoseAppliedBeforeSurface": view.initialPoseAppliedBeforeTriadSurface,
            "surfaceSubviewCount": view.subviews.compactMap { $0 as? DuelTriadRenderSurface }.count,
            "samePacketRenderer": surface.packetRenderer === packets,
            "originalProjectorInstalled": surface.projectedShadow === projector,
            "originalProjectorHasEncodedFrame": projector.lastFrame != nil,
            "renderCallbackInstalled": surface.didSubmitFrame != nil,
            "lateGeometryProviderInstalled": surface.lateSourceGeometry != nil,
            "frameDriverInstalled": surface.delegate === frameDriver,
            "surfaceSubmittedFrames": surface.submittedFrames,
            "surfaceLastSubmittedTick": nullableInt(surface.lastSubmittedTick),
            "frame": state.game.frame, "animationTick": state.animationTick,
            "sourceLiveTick": nullableInt(state.game.weaponFight?.triadPresentation.liveTick),
            "displayLinkCallbacks": view.clockCallbacks, "sessionPaused": state.paused,
            "worldWindowAbsent": view.window == nil, "worldBoundsEmpty": view.bounds.isEmpty
        ]

        let initialGame = state.game
        let pixelSize = CGSize(width: 956, height: 440)
        let viewport = CGRect(origin: .zero, size: pixelSize)
        let host = UIWindow(frame: viewport)
        window = host
        host.rootViewController = UIViewController()
        host.makeKeyAndVisible()
        view.frame = viewport; view.autoresizingMask = []
        phase = "mount-layout"
        timed(phase) {
            host.rootViewController?.view.addSubview(view)
            view.setNeedsLayout(); view.layoutIfNeeded()
        }
        XCTAssertEqual(view.bounds.size, pixelSize); XCTAssertEqual(surface.bounds.size, pixelSize)
        XCTAssertEqual(DuelTriadRenderSurface.format(samples: 2).samples, 4)
        XCTAssertEqual(surface.submittedFrames, 0); XCTAssertNil(surface.lastSubmittedTick)
        XCTAssertNil(projector.lastFrame)
        XCTAssertEqual(state.game, initialGame); XCTAssertEqual(view.clockCallbacks, 0)
        XCTAssertEqual(packets.submittedPacketCount, 0); XCTAssertTrue(view.activeSourceEffectIDs.isEmpty)
        XCTAssertTrue(surface.projectedShadow === projector)
        XCTAssertNil(state.loadError); XCTAssertNil(view.triadPreparationFailure)
        XCTAssertNil(surface.lastFailure); XCTAssertNil(packets.lastFailure)
        let initialCameraTransform = matrix(eye.simdWorldTransform)
        let initialFOV = camera.fieldOfView, initialCameraMask = camera.categoryBitMask
        beforeFirstCapture = [
            "surfaceSubmittedFrames": surface.submittedFrames,
            "surfaceLastSubmittedTick": nullableInt(surface.lastSubmittedTick),
            "projectorLastFrameAvailable": projector.lastFrame != nil,
            "sourceProjectorInstalled": surface.projectedShadow === projector,
            "displayLinkCallbacks": view.clockCallbacks, "frame": state.game.frame,
            "animationTick": state.animationTick,
            "sourceLiveTick": nullableInt(state.game.weaponFight?.triadPresentation.liveTick),
            "submittedPackets": packets.submittedPacketCount, "sourceEffectIDs": view.activeSourceEffectIDs,
            "sameActiveSurface": view.triadRenderSurface === surface,
            "sameActiveRenderer": surface.sceneRenderer === activeRenderer,
            "sameScene": activeRenderer.scene === scene, "samePointOfView": activeRenderer.pointOfView === eye
        ]

        let label = "assembly-cold-first-full-frame"
        phase = label
        let image = try timed("cold-first-offscreen-capture") {
            captureFrameCalls += 1
            return try surface.captureFrame(tick: 0, pixelSize: pixelSize, samples: 2)
        }
        let data = try XCTUnwrap(image.pngData())
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(image.cgImage?.width, 956); XCTAssertEqual(image.cgImage?.height, 440)
        let fight = try XCTUnwrap(state.game.weaponFight)
        let frame = try XCTUnwrap(projector.lastFrame)
        XCTAssertEqual(frame.tick, 0)
        XCTAssertEqual(state.game, initialGame); XCTAssertEqual(state.game.frame, 0)
        XCTAssertEqual(state.animationTick, 0); XCTAssertEqual(fight.triadPresentation.liveTick, 0)
        XCTAssertEqual(view.clockCallbacks, 0); XCTAssertEqual(packets.submittedPacketCount, 0)
        XCTAssertEqual(surface.submittedFrames, 0); XCTAssertNil(surface.lastSubmittedTick)
        XCTAssertTrue(view.activeSourceEffectIDs.isEmpty)
        XCTAssertEqual(matrix(eye.simdWorldTransform), initialCameraTransform)
        XCTAssertEqual(camera.fieldOfView, initialFOV); XCTAssertEqual(camera.categoryBitMask, initialCameraMask)
        XCTAssertNil(state.loadError); XCTAssertNil(view.triadPreparationFailure)
        XCTAssertNil(surface.lastFailure); XCTAssertNil(packets.lastFailure)
        identityInvariant = view.triadRenderSurface === surface && surface.sceneRenderer === activeRenderer &&
            view.scene === scene && view.pointOfView === eye && eye.camera === camera &&
            activeRenderer.scene === scene && activeRenderer.pointOfView === eye &&
            surface.projectedShadow === projector && surface.packetRenderer === packets &&
            surface.delegate === frameDriver && surface.didSubmitFrame != nil && surface.lateSourceGeometry != nil
        stateInvariant = state.game == initialGame && state.animationTick == 0 &&
            fight.triadPresentation.liveTick == 0 && view.clockCallbacks == 0
        XCTAssertTrue(identityInvariant); XCTAssertTrue(stateInvariant)

        // Inspect the saved PNG itself. The unmodified attachment remains the
        // evidence; this RGBA buffer is used only for the narrow black-frame gate.
        phase = "decode-png-pixel-statistics"
        let decoded = try XCTUnwrap(UIImage(data: data)?.cgImage)
        let width = decoded.width, height = decoded.height, pixelCount = width * height
        var rgba = [UInt8](repeating: 0, count: pixelCount * 4)
        try timed(phase) {
            try rgba.withUnsafeMutableBytes { buffer in
                let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
                let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo))
                context.setBlendMode(.copy); context.interpolationQuality = .none
                context.draw(decoded, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            }
        }
        var opaquePixelCount = 0, opaqueBlackPixelCount = 0
        var transparentPixelCount = 0, visibleNonBlackPixelCount = 0
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            let alpha = rgba[offset + 3]
            let nonBlack = rgba[offset] > 0 || rgba[offset + 1] > 0 || rgba[offset + 2] > 0
            if alpha == 255 {
                opaquePixelCount += 1
                if !nonBlack { opaqueBlackPixelCount += 1 }
            }
            if alpha == 0 { transparentPixelCount += 1 }
            if alpha > 0 && nonBlack { visibleNonBlackPixelCount += 1 }
        }
        nonBlackRegressionPassed = visibleNonBlackPixelCount > 0
        pixelStatistics = ["width": width, "height": height, "pixelCount": pixelCount,
            "opaquePixelCount": opaquePixelCount, "opaqueBlackPixelCount": opaqueBlackPixelCount,
            "transparentPixelCount": transparentPixelCount, "visibleNonBlackPixelCount": visibleNonBlackPixelCount,
            "source": "decoded-original-png", "representation": "sRGB-RGBA8-premultipliedLast-byteOrder32Big",
            "criterion": "alpha > 0 and at least one RGB channel > 0", "opaqueOutputExpected": true,
            "nonBlackRegressionPassed": nonBlackRegressionPassed]

        var inventory: [[String: Any]] = []
        for root in scene.rootNode.childNodes {
            var geometries = 0, skinners = 0, pending = [root]
            while let node = pending.popLast() {
                if node.geometry != nil { geometries += 1 }
                if node.skinner != nil { skinners += 1 }
                pending.append(contentsOf: node.childNodes)
            }
            inventory.append(["name": root.name ?? "", "geometries": geometries, "skinners": skinners,
                "hidden": root.isHidden, "opacity": Double(root.opacity)])
        }
        var sample: [String: Any] = [
            "label": label, "frame": state.game.frame, "animationTick": state.animationTick,
            "sourceLiveTick": fight.triadPresentation.liveTick, "displayLinkCallbacks": view.clockCallbacks,
            "surfaceSubmittedFrames": surface.submittedFrames, "surfaceLastSubmittedTick": nullableInt(surface.lastSubmittedTick),
            "sourceIntroActive": fight.sourceIntroActive, "sourceStance": fight.sourceStance(0)?.motion.rawValue ?? "none",
            "sourceStanceTick": fight.sourceStance(0)?.tick ?? -1,
            "weaponReady": fight.canUse(.weapon, index: 0), "branchesReady": fight.canUseTriad(.branches, index: 0),
            "sourceEffectIDs": view.activeSourceEffectIDs, "submittedPackets": packets.submittedPacketCount,
            "sourceProjectorInstalled": surface.projectedShadow === projector, "projectorEncodedForCapture": true,
            "rendererRoute": "surface.captureFrame", "sameActiveSurface": view.triadRenderSurface === surface,
            "sameActiveRenderer": surface.sceneRenderer === activeRenderer, "sameScene": activeRenderer.scene === scene,
            "samePointOfView": activeRenderer.pointOfView === eye, "sameOriginalProjector": surface.projectedShadow === projector,
            "sameFrameDriver": surface.delegate === frameDriver, "renderCallbackInstalled": surface.didSubmitFrame != nil,
            "lateGeometryProviderInstalled": surface.lateSourceGeometry != nil,
            "rendererUsesReverseZ": activeRenderer.usesReverseZ,
            "rendererAutoenablesDefaultLighting": activeRenderer.autoenablesDefaultLighting,
            "rendererIsPlaying": activeRenderer.isPlaying,
            "requestedSurfaceSamples": 2, "resolvedSurfaceSamples": DuelTriadRenderSurface.format(samples: 2).samples,
            "simulationInvariant": stateInvariant, "identityInvariant": identityInvariant
        ]
        sample["projectorLastFrame"] = ["available": true, "tick": frame.tick, "aspect": frame.aspect,
            "sourceCameraPosition": [frame.sourceCameraPosition.x, frame.sourceCameraPosition.y, frame.sourceCameraPosition.z],
            "sourceView": matrix(frame.sourceView), "sourceProjection": matrix(frame.sourceProjection),
            "sourceShadowMatrix": matrix(frame.sourceShadowMatrix), "casterCount": frame.casterCount,
            "triangleCount": frame.triangleCount, "factors": frame.factors]
        sample["fighters"] = fight.fighters.enumerated().map { index, fighter in [
            "index": index, "hero": fighter.hero.rawValue, "x": fighter.x, "y": fighter.y,
            "health": fighter.health, "clip": fighter.weaponPose?.clip ?? "", "clipTick": fighter.weaponPose?.tick ?? -1
        ] as [String: Any] }
        sample["camera"] = ["modelWorldTransform": matrix(eye.simdWorldTransform),
            "presentationWorldTransform": matrix(eye.presentation.simdWorldTransform),
            "model": cameraValues(camera), "presentation": cameraValues(eye.presentation.camera),
            "metalProjection": matrix(try DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: pixelSize))]
        sample["sceneInventory"] = inventory
        sample["viewport"] = ["pointsWidth": Double(view.bounds.width), "pointsHeight": Double(view.bounds.height),
            "drawableWidth": Double(surface.drawableSize.width), "drawableHeight": Double(surface.drawableSize.height),
            "viewScale": Double(view.contentScaleFactor), "surfaceScale": Double(surface.contentScaleFactor),
            "captureWidth": 956, "captureHeight": 440]
        sample["rendererFailure"] = packets.lastFailure.map { String(describing: $0) } ?? ""
        sample["surfaceFailure"] = surface.lastFailure.map { String(describing: $0) } ?? ""
        sample["sourcePreparationFailure"] = view.triadPreparationFailure ?? ""
        samples.append(sample)
        captures.append(["label": label, "frame": fight.frame, "animationTick": state.animationTick,
            "sourceLiveTick": fight.triadPresentation.liveTick, "rendererRoute": "surface.captureFrame",
            "isolation": "first complete offscreen encoding after cold World assembly; original projector always installed; no registration workaround",
            "sourceProjectorInstalled": surface.projectedShadow === projector, "projectorEncodedForCapture": true,
            "surfaceSubmittedFrames": surface.submittedFrames, "surfaceLastSubmittedTick": nullableInt(surface.lastSubmittedTick),
            "submittedPackets": packets.submittedPacketCount, "requestedSurfaceSamples": 2,
            "resolvedSurfaceSamples": DuelTriadRenderSurface.format(samples: 2).samples,
            "pngSHA256": DuelNetworkContentRecord.digest(data), "bytes": data.count, "width": width, "height": height,
            "pixelsRequireReview": true, "simulationAndModelCameraUnchanged": true])
        completed = true
        phase = "captured-before-regression-assertions"
        // Do not rely on defer during XCTest's stop-on-failure path. Persist
        // the image and report, including actual cleanup, before any final
        // cleanup/pixel assertion can stop this method. A complete report is
        // still not evidence that those assertions or visual review passed.
        finalizeReport()
        XCTAssertEqual(DuelWorldView.activeClocks, clocksBefore)
        XCTAssertEqual(opaquePixelCount, pixelCount, "The full source-projector surface must retain opaque output")
        XCTAssertGreaterThan(visibleNonBlackPixelCount, 0, "The first complete original-surface frame is still black or transparent")
    }
}
