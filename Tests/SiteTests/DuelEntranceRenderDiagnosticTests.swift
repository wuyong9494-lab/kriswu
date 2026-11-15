import XCTest
import UIKit
import SceneKit
import Metal
import simd
@testable import ShiftReminder

/// One new causal diagnostic for the failed live entrance. This uses the
/// authenticated installed release and normal fixed steps, never a ready-state
/// injection. Frozen offscreen captures cannot certify live UI or frame rate.
@MainActor
final class DuelEntranceRenderDiagnosticTests: XCTestCase {
    private enum Failure: Error { case sourceIdentity, missingWorld, unexpectedState }

    override func setUpWithError() throws { continueAfterFailure = false }

    func testInstalledEntranceCompletesAndCapturesSceneEffectShadowIsolationOnce() throws {
        let releaseSHA = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
        guard Bundle.main.object(forInfoDictionaryKey: DuelFighterAssetRelease.infoKey) as? String == releaseSHA else {
            throw Failure.sourceIdentity
        }
        let clocksBefore = DuelWorldView.activeClocks
        var phase = "construct-session"
        var finished = false
        var advanceCalls = 0
        var isolationInvariant = false
        var samples: [[String: Any]] = []
        var captures: [[String: Any]] = []
        var timings: [[String: Any]] = []
        var cleanup: [String: Any] = [:]
        var session: DuelSession?
        var world: DuelWorldView?
        var window: UIWindow?
        let start = ProcessInfo.processInfo.systemUptime
        defer {
            world?.shutdown()
            session?.shutdown()
            window?.isHidden = true
            cleanup = ["sceneReleased": world?.scene == nil,
                       "surfaceReleased": world?.triadRenderSurface == nil,
                       "rendererReleased": world?.triadMetalRenderer == nil,
                       "activeClocksBefore": clocksBefore,
                       "activeClocksAfter": DuelWorldView.activeClocks]
            XCTAssertEqual(DuelWorldView.activeClocks, clocksBefore)
            let report: [String: Any] = [
                "schemaVersion": 1,
                "schema": "fighter-entrance-render-diagnostic-v1",
                "releaseSHA256": releaseSHA,
                "scope": "One installed fixed-step entrance and frozen scene/effect/projector isolation",
                "diagnosticCompleted": finished, "lastPhase": phase,
                "elapsedSeconds": ProcessInfo.processInfo.systemUptime - start,
                "samples": samples, "captures": captures, "timings": timings, "cleanup": cleanup,
                "expectedSimulationFrames": [0, 164, 394],
                "simulationAdvanceCalls": advanceCalls,
                "captureLabels": captures.compactMap { $0["label"] as? String },
                "stateInvariant": isolationInvariant,
                "combatStateInjected": false,
                "normalSessionAdvanceUsed": true,
                "liveDisplayLinkAdvancesSelected": false,
                "uiExecutionStatus": "not_selected",
                "physicalDeviceValidated": false,
                "liveUIValidated": false,
                "audiblePlaybackVerified": false,
                "performanceVerified": false,
                "pixels": "PENDING",
                "panguEquipmentActivated": false,
                "isolationMutatesOnlyDiagnosticRenderOwners": true,
                "captureTimingIncludesGPUReadbackWait": true,
                "timingWarning": "Diagnostic construction, fixed-step CPU, draw submission and synchronous readback are separate; none is a live FPS measurement"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "entrance-render-diagnostic-report"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }

        func timed<T>(_ label: String, _ operation: () throws -> T) rethrows -> T {
            let began = ProcessInfo.processInfo.systemUptime
            defer { timings.append(["phase": label, "seconds": ProcessInfo.processInfo.systemUptime - began]) }
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
        // UIWindow may adopt the host screen's orientation. The offscreen
        // diagnostic keeps its requested camera aspect independently of that
        // window; it does not claim to validate UIKit layout or rotation.
        view.frame = viewport
        view.autoresizingMask = []
        host.rootViewController?.view.addSubview(view)
        timed("mount-layout") { view.setNeedsLayout(); view.layoutIfNeeded() }
        guard state.loadError == nil, view.stageAsset != nil,
              let assets = state.weaponAssets, let release = assets.release,
              release.definition.id == "h17-shared-root-floorfall-20261115-v2",
              let surface = view.triadRenderSurface, let renderer = view.triadMetalRenderer,
              let eye = view.pointOfView, let camera = eye.camera,
              let shadow = surface.projectedShadow else { throw Failure.missingWorld }
        XCTAssertEqual(Set(assets.catalog.profiles.map(\.id)), Set(["sun_triad", "liu_hammers"]))
        XCTAssertNil(assets.panguAudio)
        XCTAssertFalse(assets.catalog.profiles.contains(where: \.isPangu))
        XCTAssertTrue(state.game.weaponFight?.hasSourceStance(0) == true)
        XCTAssertEqual(state.game.frame, 0)
        XCTAssertEqual(view.clockCallbacks, 0)
        XCTAssertEqual(view.bounds.size, pixelSize)
        XCTAssertEqual(surface.bounds.size, pixelSize)
        XCTAssertTrue(surface.sceneRenderer.scene === view.scene)
        XCTAssertTrue(surface.sceneRenderer.pointOfView === eye)
        let requestedSamples = view.antialiasingMode == .none ? 1 : 2

        func matrix(_ value: simd_float4x4) -> [Float] {
            (0..<4).flatMap { column in (0..<4).map { row in value[column][row] } }
        }
        func effectiveVisibility(_ node: SCNNode) -> Bool {
            var current: SCNNode? = node
            while let value = current {
                if value.isHidden || value.opacity == 0 { return false }
                current = value.parent
            }
            return true
        }
        func sceneInventory() -> [[String: Any]] {
            guard let root = view.scene?.rootNode else { return [] }
            return root.childNodes.map { node in
                var geometries = 0, visible = 0, skinners = 0
                var masks = Set<Int>()
                func count(_ item: SCNNode) {
                    guard item.geometry != nil else { return }
                    geometries += 1
                    if effectiveVisibility(item) { visible += 1 }
                    if item.skinner != nil { skinners += 1 }
                    masks.insert(item.categoryBitMask)
                }
                count(node)
                node.enumerateChildNodes { item, _ in count(item) }
                return ["name": node.name ?? "", "geometries": geometries,
                        "visibleGeometries": visible, "skinners": skinners,
                        "hidden": node.isHidden, "opacity": node.opacity,
                        "categoryMasks": masks.sorted(), "worldTransform": matrix(node.simdWorldTransform)]
            }
        }
        func stateSample(_ label: String) throws {
            let fight = try XCTUnwrap(state.game.weaponFight)
            let projection = try DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: view.bounds.size)
            let lateGeometry = surface.lateSourceGeometry?() ?? []
            samples.append([
                "label": label, "frame": fight.frame, "animationTick": state.animationTick,
                "sourceLiveTick": fight.triadPresentation.liveTick,
                "sourceIntroActive": fight.sourceIntroActive,
                "sourceStance": fight.sourceStance(0)?.motion.rawValue ?? "none",
                "sourceStanceTick": fight.sourceStance(0)?.tick ?? -1,
                "weaponReady": fight.canUse(.weapon, index: 0),
                "branchesReady": fight.canUseTriad(.branches, index: 0),
                "fighters": fight.fighters.enumerated().map { index, fighter in [
                    "index": index, "hero": fighter.hero.rawValue, "x": fighter.x,
                    "y": fighter.y, "health": fighter.health,
                    "clip": fighter.weaponPose?.clip ?? "", "clipTick": fighter.weaponPose?.tick ?? -1,
                    "clipPhase": fighter.weaponPose?.phase ?? -1
                ] as [String: Any] },
                "sourceEffectIDs": view.activeSourceEffectIDs,
                "submittedPackets": renderer.submittedPacketCount,
                "surfaceSubmittedFrames": surface.submittedFrames,
                "displayLinkCallbacks": view.clockCallbacks,
                "sourcePreparationFailure": view.triadPreparationFailure ?? "",
                "surfaceFailure": surface.lastFailure.map { String(describing: $0) } ?? "",
                "rendererFailure": renderer.lastFailure.map { String(describing: $0) } ?? "",
                "projectorInstalled": surface.projectedShadow != nil,
                "lateSourceGeometryCount": lateGeometry.count,
                "lateSourceVisibleGeometryCount": lateGeometry.filter(effectiveVisibility).count,
                "lateSourceCategoryMasks": Array(Set(lateGeometry.map(\.categoryBitMask))).sorted(),
                "camera": ["worldTransform": matrix(eye.simdWorldTransform),
                           "metalProjection": matrix(projection), "fieldOfView": camera.fieldOfView,
                           "orthographicScale": camera.orthographicScale,
                           "usesOrthographicProjection": camera.usesOrthographicProjection,
                           "near": camera.zNear, "far": camera.zFar,
                           "categoryMask": camera.categoryBitMask,
                           "worldUsesReverseZ": view.usesReverseZ,
                           "surfaceUsesReverseZ": surface.sceneRenderer.usesReverseZ],
                "viewport": ["pointsWidth": view.bounds.width, "pointsHeight": view.bounds.height,
                             "viewScale": view.contentScaleFactor, "surfaceScale": surface.contentScaleFactor,
                             "drawableWidth": surface.drawableSize.width, "drawableHeight": surface.drawableSize.height,
                             "captureWidth": pixelSize.width, "captureHeight": pixelSize.height,
                             "requestedSamples": requestedSamples,
                             "actualSamples": DuelTriadRenderSurface.format(samples: requestedSamples).samples],
                "sceneInventory": sceneInventory()
            ])
        }
        func redraw(_ label: String) throws {
            let game = state.game, animation = state.animationTick
            timed(label + "-draw-submission") { view.drawState() }
            XCTAssertEqual(state.game, game)
            XCTAssertEqual(state.animationTick, animation)
            XCTAssertNil(state.loadError)
            XCTAssertNil(surface.lastFailure)
            XCTAssertNil(renderer.lastFailure)
        }
        func capture(_ label: String, isolation: String) throws {
            phase = label
            XCTAssertEqual(view.bounds.size, pixelSize)
            XCTAssertEqual(surface.bounds.size, pixelSize)
            XCTAssertTrue(surface.sceneRenderer.scene === view.scene)
            XCTAssertTrue(surface.sceneRenderer.pointOfView === eye)
            let before = state.game, animation = state.animationTick
            let cameraBefore = matrix(eye.simdWorldTransform)
            let fovBefore = camera.fieldOfView, cameraMaskBefore = camera.categoryBitMask
            let fight = try XCTUnwrap(state.game.weaponFight)
            try stateSample(label)
            let image = try timed(label + "-synchronous-readback") {
                try surface.captureFrame(tick: fight.triadPresentation.liveTick,
                    pixelSize: pixelSize, samples: requestedSamples)
            }
            let data = try XCTUnwrap(image.pngData())
            XCTAssertEqual(image.cgImage?.width, 956)
            XCTAssertEqual(image.cgImage?.height, 440)
            XCTAssertEqual(state.game, before)
            XCTAssertEqual(state.animationTick, animation)
            XCTAssertEqual(matrix(eye.simdWorldTransform), cameraBefore)
            XCTAssertEqual(camera.fieldOfView, fovBefore)
            XCTAssertEqual(camera.categoryBitMask, cameraMaskBefore)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = label
            attachment.lifetime = .keepAlways
            add(attachment)
            captures.append(["label": label, "frame": fight.frame,
                "sourceLiveTick": fight.triadPresentation.liveTick, "isolation": isolation,
                "pngSHA256": DuelNetworkContentRecord.digest(data), "bytes": data.count,
                "width": 956, "height": 440, "pixelsRequireReview": true,
                "simulationAndCameraUnchanged": true])
        }
        func advance(to frame: Int) throws {
            phase = "advance-to-\(frame)"
            let initial = state.game.frame
            guard initial <= frame else { throw Failure.unexpectedState }
            var durations: [Double] = []
            durations.reserveCapacity(frame - initial)
            try timed(phase + "-fixed-step-cpu") {
                for _ in initial..<frame {
                    let began = ProcessInfo.processInfo.systemUptime
                    state.advance()
                    advanceCalls += 1
                    durations.append(ProcessInfo.processInfo.systemUptime - began)
                    guard state.loadError == nil else { throw Failure.unexpectedState }
                }
            }
            XCTAssertEqual(state.game.frame, frame)
            durations.sort()
            timings.append(["phase": phase + "-per-step", "count": durations.count,
                "p95Seconds": durations.isEmpty ? 0 : durations[min(durations.count - 1, Int(Double(durations.count) * 0.95))],
                "maximumSeconds": durations.last ?? 0,
                "doesNotMeasureLiveFrameRate": true])
        }

        try redraw("frame-0")
        try capture("entrance-frame-0-full", isolation: "none")
        try advance(to: 164)
        XCTAssertTrue(state.game.weaponFight?.sourceIntroActive == true)
        try redraw("frame-164")
        try capture("entrance-frame-164-full", isolation: "none")
        try advance(to: 392)
        XCTAssertEqual(state.game.weaponFight?.sourceStance(0)?.motion, .firstIntro)
        XCTAssertEqual(state.game.weaponFight?.sourceStance(0)?.tick, 391)
        XCTAssertTrue(state.game.weaponFight?.sourceIntroActive == true)
        try stateSample("frame-392-before-source-end")
        try advance(to: 393)
        XCTAssertEqual(state.game.weaponFight?.sourceStance(0)?.motion, .startIdle)
        XCTAssertEqual(state.game.weaponFight?.sourceStance(0)?.tick, 0)
        XCTAssertTrue(state.game.weaponFight?.sourceIntroActive == true)
        XCTAssertTrue(state.game.weaponFight?.canUse(.weapon, index: 0) == false)
        try stateSample("frame-393-source-end-published")
        try advance(to: 394)
        let ready = try XCTUnwrap(state.game.weaponFight)
        XCTAssertFalse(ready.sourceIntroActive)
        XCTAssertTrue(ready.canUse(.weapon, index: 0))
        XCTAssertTrue(ready.canUseTriad(.branches, index: 0))
        XCTAssertEqual(ready.fighters.map(\.health), [1000, 1000])
        try redraw("frame-394")
        let packets = renderer.submittedPacketCount
        let isolationState = state.game, isolationAnimation = state.animationTick
        let isolationCamera = matrix(eye.simdWorldTransform), isolationFOV = camera.fieldOfView
        XCTAssertGreaterThan(packets, 0)
        try capture("entrance-frame-394-full", isolation: "none")

        // Only render-owner state changes for A/B. No combat input, source
        // sample, animation tick, quality preset or resource bytes are changed.
        // Always restore the projector and normal packets before leaving.
        defer {
            surface.projectedShadow = shadow
            view.drawState()
        }
        renderer.clear()
        try capture("entrance-frame-394-no-fx", isolation: "source effect packets removed; original projector retained")
        surface.projectedShadow = nil
        try capture("entrance-frame-394-scene-only", isolation: "source effect packets and projector removed")
        surface.projectedShadow = shadow
        try redraw("frame-394-restored")
        XCTAssertEqual(renderer.submittedPacketCount, packets)
        try capture("entrance-frame-394-restored", isolation: "normal source effects and projector restored")
        isolationInvariant = state.game == isolationState && state.animationTick == isolationAnimation &&
            matrix(eye.simdWorldTransform) == isolationCamera && camera.fieldOfView == isolationFOV &&
            surface.projectedShadow === shadow && renderer.submittedPacketCount == packets
        XCTAssertTrue(isolationInvariant)
        XCTAssertEqual(captures.count, 6)
        XCTAssertEqual(state.game.frame, 394)
        XCTAssertEqual(advanceCalls, 394)
        XCTAssertEqual(view.clockCallbacks, 0, "Fixed-step evidence must not include a live clock callback")
        phase = "diagnostic-completed-pixels-pending"
        finished = true
    }
}
