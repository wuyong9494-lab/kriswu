import XCTest
import UIKit
import SceneKit
@testable import ShiftReminder

@MainActor
final class DuelLifecycleTests: XCTestCase {
    private func session(_ hero: DuelGame.Hero = .ember, mode: DuelGame.Mode = .practice) -> DuelSession {
        DuelSession(.init(hero: hero, difficulty: .learning, mode: mode))
    }

    /// Ordinary CI has no private character pack. Decide expected behavior
    /// from source availability, never from whether the decoder happened to work.
    /// A present but broken source must still fail the successful-switch asserts.
    private func showroomHasSource(for hero: DuelGame.Hero) -> Bool {
        if !ProcessInfo.processInfo.arguments.contains("-duel-legacy-controls"),
           DuelWeaponAssets.catalogURL() != nil { return true }
        if let identity = DuelOriginalRigAsset.identity(for: hero),
           DuelOriginalRigAsset.bundledURL(for: identity) != nil { return true }
        return DuelCharacterAsset.bundledURL(for: hero) != nil
    }

    func testCameraKeepsNarrowFramingAcrossRenderAndRestart() throws {
        let state = session()
        let world = DuelWorldView(session: state, characterSource: .procedural)
        defer { world.shutdown(); state.shutdown() }
        world.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        world.layoutSubviews()
        let camera = try XCTUnwrap(world.pointOfView?.camera)
        let narrowProjection = camera.usesOrthographicProjection
            ? camera.orthographicScale : Double(camera.fieldOfView)
        XCTAssertGreaterThan(narrowProjection, 10)
        for _ in 0..<4 { state.advance(); world.drawState() }
        let afterRender = camera.usesOrthographicProjection
            ? camera.orthographicScale : Double(camera.fieldOfView)
        XCTAssertEqual(afterRender, narrowProjection, accuracy: 0.001)
        world.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        world.layoutSubviews(); world.drawState()
        let wideProjection = camera.usesOrthographicProjection
            ? camera.orthographicScale : Double(camera.fieldOfView)
        XCTAssertLessThan(wideProjection, narrowProjection)
        state.input("right", down: true)
        for _ in 0..<10 { state.advance(); world.drawState() }
        state.restart()
        XCTAssertEqual(world.pointOfView?.position.x ?? -1, 5, accuracy: 0.001)
    }

    func testPersonalCharactersRemainPairedAfterRestart() {
        for hero in [DuelGame.Hero.liu, .ember] {
            let state = session(hero)
            let expected: [DuelGame.Hero] = hero == .liu ? [.liu, .ember] : [.ember, .liu]
            XCTAssertEqual(state.game.fighters.map(\.hero), expected)
            state.input("right", down: true); state.advance(); state.restart()
            XCTAssertEqual(state.game.fighters.map(\.hero), expected)
            XCTAssertEqual(state.game.fighters.map(\.x), [3500, 6500])
            state.shutdown()
        }
    }

    func testLobbySelectionDoesNotStartCombatClockAndReleasesScene() {
        let clocks = DuelWorldView.activeClocks
        for hero in [DuelGame.Hero.liu, .ember, .liu] {
            weak var releasedScene: SCNScene?
            var retainedView: DuelLobbySceneView?
            autoreleasepool {
                let lobby = DuelLobbySceneView(hero: hero)
                retainedView = lobby
                let scene = lobby.scene
                releasedScene = scene
                XCTAssertNotNil(scene)
                XCTAssertEqual(lobby.selectedHero, showroomHasSource(for: hero) ? hero : nil)
                for choice in [DuelGame.Hero.ember, .liu] {
                    let previousSelection = lobby.selectedHero
                    let previousNodeCount = scene?.rootNode.childNodes.count
                    lobby.select(choice)
                    if showroomHasSource(for: choice) {
                        XCTAssertEqual(lobby.selectedHero, choice)
                    } else {
                        XCTAssertEqual(lobby.selectedHero, previousSelection,
                                       "Missing sources must not report a successful character switch")
                        XCTAssertEqual(scene?.rootNode.childNodes.count, previousNodeCount)
                    }
                }
                XCTAssertFalse(lobby.rendersContinuously)
                XCTAssertFalse(lobby.isPlaying)
                XCTAssertEqual(DuelWorldView.activeClocks, clocks)
                lobby.shutdown()
                XCTAssertNil(lobby.scene); XCTAssertNil(lobby.pointOfView)
                XCTAssertEqual(scene?.rootNode.childNodes.count, 0,
                               "Closing the lobby must detach its resource-owning scene nodes immediately")
            }
            // SceneKit uses Objective-C temporary objects. Drain the event's
            // autorelease pool before checking lifetime, while retaining the
            // SCNView itself to detect a hidden renderer-to-scene reference.
            XCTAssertNotNil(retainedView)
            XCTAssertNil(releasedScene, "A retained lobby view must not keep the closed scene alive")
            retainedView = nil
        }
    }

    func testShowroomRotationZoomScrollAndTeardown() {
        let lobby = DuelLobbySceneView(hero: .ember)
        XCTAssertEqual(lobby.yaw, .pi, accuracy: 0.0001)
        XCTAssertEqual(lobby.zoom, DuelLobbySceneView.defaultZoom, accuracy: 0.0001)
        XCTAssertTrue(DuelLobbySceneView.acceptsHorizontalPan(CGPoint(x: 20, y: 1)))
        XCTAssertFalse(DuelLobbySceneView.acceptsHorizontalPan(CGPoint(x: 1, y: 20)))
        XCTAssertFalse(DuelLobbySceneView.acceptsHorizontalPan(.zero))
        XCTAssertNotNil(lobby.gestureRecognizers?.first(where: { $0 is UIPanGestureRecognizer })?.delegate)
        lobby.rotatePreview(by: 0.5)
        XCTAssertEqual(lobby.yaw, .pi + 0.5, accuracy: 0.0001)
        lobby.scalePreview(by: 2)
        XCTAssertEqual(lobby.zoom, 0.7, accuracy: 0.0001)
        lobby.scalePreview(by: 0.01)
        XCTAssertEqual(lobby.zoom, 1.5, accuracy: 0.0001)
        let previousSelection = lobby.selectedHero
        let previousYaw = lobby.yaw, previousZoom = lobby.zoom
        lobby.select(.liu)
        if showroomHasSource(for: .liu) {
            XCTAssertEqual(lobby.selectedHero, .liu)
            XCTAssertEqual(lobby.yaw, .pi, accuracy: 0.0001)
            XCTAssertEqual(lobby.zoom, DuelLobbySceneView.defaultZoom, accuracy: 0.0001)
        } else {
            XCTAssertEqual(lobby.selectedHero, previousSelection)
            XCTAssertEqual(lobby.yaw, previousYaw, accuracy: 0.0001)
            XCTAssertEqual(lobby.zoom, previousZoom, accuracy: 0.0001)
        }
        lobby.shutdown()
        XCTAssertTrue(lobby.gestureRecognizers?.isEmpty ?? true)
        XCTAssertNil(lobby.scene)
    }

    func testReleasedGaleTapSurvivesDelayedSimulationAndHitsExactlyOnce() {
        let state = session(.gale)
        defer { state.shutdown() }
        let initial = state.game
        // A short touch may begin and end before the next display callback.
        // Releasing it must retain the pending tap without retaining a hold.
        state.input("skill1", down: true)
        state.input("skill1", down: false)
        XCTAssertTrue(state.held.isEmpty)
        XCTAssertEqual(state.game, initial)

        var clock = DuelClock()
        // Each one-second hitch advances only six production simulation ticks.
        // Five seconds on this schedule is not enough for projectile contact.
        for _ in 0..<5 {
            let steps = clock.consume(seconds: 1)
            XCTAssertEqual(steps, 6)
            for _ in 0..<steps { state.advance() }
        }
        XCTAssertEqual(state.game.frame, 30)
        XCTAssertEqual(state.game.landedHits, [0, 0])
        XCTAssertEqual(state.game.damageDealt, [0, 0])
        XCTAssertEqual(state.game.projectiles.count, 1)

        // At the initial 3000-unit gap, startup plus flight reaches the target
        // on tick 33. This checks progression and real damage, not elapsed time.
        for _ in 0..<2 { state.advance() }
        XCTAssertEqual(state.game.landedHits, [0, 0])
        state.advance()
        XCTAssertEqual(state.game.frame, 33)
        XCTAssertEqual(state.game.landedHits, [1, 0])
        XCTAssertEqual(state.game.damageDealt, [135, 0])
        XCTAssertEqual(state.game.fighters[1].health, 865)
        XCTAssertEqual(state.game.fighters[1].x, 6760)
        XCTAssertTrue(state.game.projectiles.isEmpty)

        for _ in 0..<120 { state.advance() }
        XCTAssertNil(state.game.fighters[0].attack)
        XCTAssertEqual(state.game.fighters[1].health, 1000,
                       "Practice restores health, so UI contact must use persistent hit/damage totals")
        XCTAssertEqual(state.game.landedHits, [1, 0])
        XCTAssertEqual(state.game.damageDealt, [135, 0])
        XCTAssertTrue(state.held.isEmpty)
    }

    func testTwoHeldInputsPauseAndRestartCannotLeaveAnAutomaticAction() {
        let state = session()
        state.input("right", down: true); state.input("light", down: true)
        state.advance()
        XCTAssertGreaterThan(state.game.fighters[0].x, 3500)
        XCTAssertNotNil(state.game.fighters[0].attack)
        XCTAssertEqual(state.held, ["right", "light"])
        state.pause()
        let paused = state.game
        state.input("left", down: true); state.input("skill2", down: true)
        for _ in 0..<120 { state.advance() }
        XCTAssertEqual(state.game, paused)
        XCTAssertTrue(state.held.isEmpty)
        state.resume()
        let x = state.game.fighters[0].x
        for _ in 0..<120 { state.advance() }
        XCTAssertEqual(state.game.fighters[0].x, x)
        XCTAssertNil(state.game.fighters[0].attack)
        XCTAssertEqual(state.game.fighters[0].energy, 100)
        state.input("right", down: true); state.restart(); state.advance()
        XCTAssertEqual(state.game.fighters[0].x, 3500)
        XCTAssertTrue(state.held.isEmpty)
    }

    func testTutorialRequiresJumpGuardAndBothAcceptedSkills() {
        let state = session(mode: .tutorial)
        state.input("right", down: true)
        for _ in 0..<40 { state.advance() }
        state.input("right", down: false)
        state.input("light", down: true); state.advance(); state.input("light", down: false)
        for _ in 0..<60 { state.advance() }
        XCTAssertEqual(state.tutorialStep, 2)
        state.input("guard", down: true); state.advance(); state.input("guard", down: false)
        XCTAssertEqual(state.tutorialStep, 2, "Guard alone cannot complete the jump instruction")
        state.input("jump", down: true); state.advance(); state.input("jump", down: false)
        for _ in 0..<45 { state.advance() }
        state.input("guard", down: true); state.advance(); state.input("guard", down: false)
        XCTAssertEqual(state.tutorialStep, 3)
        state.input("skill1", down: true); state.advance(); state.input("skill1", down: false)
        for _ in 0..<70 { state.advance() }
        XCTAssertEqual(state.tutorialStep, 3)
        state.input("skill2", down: true); state.advance(); state.input("skill2", down: false)
        XCTAssertEqual(state.tutorialStep, 4)
    }

    func testPauseDiscardsTheComboTapBufferedDuringHitStop() {
        let state = session()
        state.input("right", down: true)
        for _ in 0..<40 { state.advance() }
        state.input("right", down: false)
        state.input("light", down: true); state.advance(); state.input("light", down: false)
        for _ in 0..<20 {
            state.advance()
            if state.game.hitStop > 0 { break }
        }
        XCTAssertGreaterThan(state.game.hitStop, 0)
        XCTAssertEqual(state.game.landedHits[0], 1)
        state.input("light", down: true); state.advance()
        state.pause(); state.resume()
        for _ in 0..<120 { state.advance() }
        XCTAssertEqual(state.game.landedHits[0], 1, "A pre-pause combo command must not fire after resuming")
        XCTAssertNil(state.game.fighters[0].attack)
        XCTAssertTrue(state.held.isEmpty)
    }

    func testGrapplePauseResumeAndRestartClearPendingInputAndTheCapture() {
        let state = session(.liu)
        state.input("right", down: true)
        for _ in 0..<42 { state.advance() }
        state.input("right", down: false)
        state.input("ultimate", down: true); state.advance(); state.input("ultimate", down: false)
        for _ in 0..<70 { state.advance() }
        XCTAssertEqual(state.game.grapple?.stage, .hold)
        let frozen = state.game
        state.input("light", down: true); state.input("left", down: true); state.pause()
        for _ in 0..<300 { state.advance() }
        XCTAssertEqual(state.game, frozen)
        XCTAssertTrue(state.held.isEmpty)
        state.resume()
        for _ in 0..<330 { state.advance() }
        XCTAssertNil(state.game.grapple)
        XCTAssertEqual(state.game.damageDealt[0], 280)
        XCTAssertEqual(state.game.landedHits[0], 2)
        XCTAssertNil(state.game.fighters[0].attack)
        state.restart()
        XCTAssertNil(state.game.grapple)
        XCTAssertEqual(state.game.fighters[0].energy, 100)
        XCTAssertEqual(state.game.fighters.map(\.x), [3500, 6500])
    }

    func testGrappleRendersTakedownSideLockAndReleaseFromActualRuleState() throws {
        let state = session(.liu)
        state.input("right", down: true)
        for _ in 0..<42 { state.advance() }
        state.input("right", down: false)
        state.input("ultimate", down: true); state.advance(); state.input("ultimate", down: false)
        for _ in 0..<35 { if state.game.grapple == nil { state.advance() } }
        XCTAssertNotNil(state.game.grapple)
        for (name, age) in [("takedown", 12), ("side-lock", 65), ("release", 210)] {
            while let hold = state.game.grapple, hold.age < age { state.advance() }
            XCTAssertEqual(state.game.grapple?.age, age)
            let world = DuelWorldView(session: state, characterSource: .procedural)
            world.frame = CGRect(x: 0, y: 0, width: 956, height: 440); world.layoutIfNeeded()
            let scene = try XCTUnwrap(world.scene)
            let actor = try XCTUnwrap(scene.rootNode.childNode(withName: "duel.actor.0", recursively: false))
            let defender = try XCTUnwrap(scene.rootNode.childNode(withName: "duel.actor.1", recursively: false))
            XCTAssertTrue(actor.position.x.isFinite && defender.position.x.isFinite)
            for footName in ["duel.foot.left", "duel.foot.right"] {
                let foot = try XCTUnwrap(actor.childNode(withName: footName, recursively: true))
                for x in [Float(-0.12), Float(0.12)] {
                    for z in [Float(-0.20), Float(0.20)] {
                        let sole = foot.convertPosition(SCNVector3(x, -0.075, z), to: nil)
                        XCTAssertGreaterThanOrEqual(sole.y, -0.06, "A grappling pose must keep its soles above the stage floor")
                    }
                }
            }
            if name == "side-lock" {
                XCTAssertGreaterThan(actor.position.z - defender.position.z, 0.5, "The attacker must hold from the opponent's side")
                let head = try XCTUnwrap(defender.childNode(withName: "head", recursively: false))
                let hip = try XCTUnwrap(actor.childNode(withName: "hip", recursively: false))
                XCTAssertEqual(head.worldPosition.y, defender.position.y, accuracy: 0.02)
                XCTAssertLessThan(head.worldPosition.x, defender.position.x - 1.5, "The body must lie along the arena, not into the depth axis")
                XCTAssertGreaterThan(abs(hip.worldPosition.x - head.worldPosition.x), 0.45, "The opponent's head silhouette must remain clear of the attacker's torso")
                let grip = try XCTUnwrap(actor.childNode(withName: "duel.hand.right", recursively: true))
                let held = try XCTUnwrap(defender.childNode(withName: "duel.hand.right", recursively: true))
                let a = grip.worldPosition, b = held.worldPosition
                let distanceSquared = (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) + (a.z - b.z) * (a.z - b.z)
                XCTAssertLessThan(distanceSquared, 0.25 * 0.25, "The wrist hold must stay connected when separating the silhouettes")
                XCTAssertLessThan(actor.position.x, defender.position.x - 1.5)
            }
            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = scene; renderer.pointOfView = world.pointOfView
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1434, height: 660), antialiasingMode: .multisampling2X)
            let evidence = XCTAttachment(image: image)
            evidence.name = "fighter-liu-\(name)"; evidence.lifetime = .keepAlways; add(evidence)
            XCTAssertGreaterThan(image.pngData()?.count ?? 0, 5000)
            world.shutdown(); state.resume()
        }
        state.shutdown()
    }

    private func awaitClockProgress(_ state: DuelSession, world: DuelWorldView, phase: String) async throws {
        let initial = state.game.frame
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        // Wait for the behavior under test, not an assumed 300 ms render warmup.
        // A registered but non-advancing driver must still fail the bounded wait.
        while state.game.frame == initial && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let delay = world.firstStepDelay.map { String(format: "%.4f", $0) } ?? "none"
        let evidence = XCTAttachment(string: "phase=\(phase) initial=\(initial) frame=\(state.game.frame) callbacks=\(world.clockCallbacks) firstStepDelay=\(delay) app=\(UIApplication.shared.applicationState.rawValue) window=\(world.window != nil) paused=\(state.paused)")
        evidence.name = "fighter-progress-\(state.setup.hero.rawValue)-\(phase)"
        evidence.lifetime = .keepAlways; add(evidence)
        XCTAssertGreaterThan(state.game.frame, initial, "A foreground scene must actually advance its simulation")
        XCTAssertGreaterThanOrEqual(world.clockCallbacks, 2)
        XCTAssertNotNil(world.firstStepDelay)
    }

    func testShutdownRejectsLateLayoutAndCopiedSessionCallbacks() throws {
        let state = session()
        let world = DuelWorldView(session: state, characterSource: .procedural)
        defer { world.pointOfView = nil; world.shutdown(); state.shutdown() }
        world.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
        let latePause = try XCTUnwrap(state.renderPause)
        let lateReset = try XCTUnwrap(state.didReset)
        let clocks = DuelWorldView.activeClocks
        world.shutdown()
        XCTAssertNil(world.scene)
        XCTAssertNil(state.renderPause); XCTAssertNil(state.didReset); XCTAssertNil(state.didSimulateStep)

        // Observe late layout independently of SceneKit's default-camera timing.
        // A closed renderer can still expose a camera; application callbacks
        // must not frame or move it after the fight has ended.
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.orthographicScale = 123
        camera.position = SCNVector3(17, 19, 23)
        world.pointOfView = camera
        let transform = camera.simdTransform
        let callbacks = world.clockCallbacks, frame = state.game.frame
        var inputResets = 0
        state.inputReset = { inputResets += 1 }
        world.layoutSubviews(); world.drawState()
        lateReset(); latePause(true); latePause(false)
        world.didMoveToWindow()
        world.shutdown()
        XCTAssertEqual(camera.camera?.orthographicScale ?? -1, 123, accuracy: 0.001)
        XCTAssertEqual(camera.simdTransform, transform)
        XCTAssertNil(world.scene)
        XCTAssertFalse(world.isPlaying); XCTAssertFalse(world.rendersContinuously)
        XCTAssertEqual(world.clockCallbacks, callbacks)
        XCTAssertEqual(state.game.frame, frame)
        XCTAssertEqual(inputResets, 0, "A late window callback must not touch the detached session")
        XCTAssertEqual(DuelWorldView.activeClocks, clocks)
    }

    private func awaitSceneRelease(_ probe: DuelWorldReleaseProbe, state: DuelSession, clocks: Int) async throws {
        let started = probe.releaseStartedAt
        let stoppedFrame = state.game.frame
        var samples: [String] = []
        var viewReleasedAt: Double?, sceneReleasedAt: Double?, cameraReleasedAt: Double?
        var firstSampleAfter100ms: String?
        var released = false
        // SceneKit/UIKit can finish an in-flight frame after application
        // ownership ends. Observe weak references, never keep the view in an
        // async parameter or retain it between polls. A persistent owner still
        // fails this deadline; no extra shutdown/flush is used to make it pass.
        repeat {
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            let live = autoreleasepool { probe.liveObjects() }
            let sample = String(format: "t=%.4f view=%d scene=%d originalCamera=%d", elapsed,
                                live.view ? 1 : 0, live.scene ? 1 : 0, live.camera ? 1 : 0)
            samples.append(sample)
            if !live.view, viewReleasedAt == nil { viewReleasedAt = elapsed }
            if !live.scene, sceneReleasedAt == nil { sceneReleasedAt = elapsed }
            if !live.camera, cameraReleasedAt == nil { cameraReleasedAt = elapsed }
            if elapsed >= 0.1, firstSampleAfter100ms == nil { firstSampleAfter100ms = sample }
            released = !live.view && !live.scene && !live.camera
            if released || elapsed >= 3 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        } while true
        func duration(_ value: Double?) -> String { value.map { String(format: "%.4f", $0) } ?? "still retained" }
        let summary = "hero=\(state.setup.hero.rawValue) viewReleasedSeconds=\(duration(viewReleasedAt)) sceneReleasedSeconds=\(duration(sceneReleasedAt)) originalCameraReleasedSeconds=\(duration(cameraReleasedAt)) firstSampleAtOrAfter100ms=\(firstSampleAfter100ms ?? "all released before 100 ms")"
        print("[fighter-release] \(summary)")
        let evidence = XCTAttachment(string: summary + "\n" + samples.joined(separator: "\n"))
        evidence.name = "fighter-release-\(state.setup.hero.rawValue)"; evidence.lifetime = .keepAlways; add(evidence)
        XCTAssertEqual(state.game.frame, stoppedFrame, "A detached scene must not advance during renderer drainage")
        XCTAssertEqual(DuelWorldView.activeClocks, clocks)
        XCTAssertTrue(released, "The view, original scene and original camera must all deallocate within 3 seconds: \(summary)")
    }

    func testSceneClockStopsOnPauseAndResourcesReleaseAcrossRepeatedEntries() async throws {
        XCTAssertTrue(ProcessInfo.processInfo.arguments.contains("-demo"), "Use the existing demo launch argument so first-launch permission alerts do not interrupt the host")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
        let host = UIViewController(); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let baseline = DuelWorldView.activeClocks
        for hero in [DuelGame.Hero.ember, .gale, .liu] {
            let state = session(hero)
            defer { state.shutdown() }
            // Let every strong setup/render temporary and async progress frame
            // leave scope before observing deallocation, not just world = nil.
            let entry = try await exerciseSceneEntry(state, host: host, scene: scene, baseline: baseline)
            try await awaitSceneRelease(entry.probe, state: state, clocks: baseline)
            // Invoking these after the wait keeps both closures and the session
            // alive throughout observation, without a strong view reference.
            entry.lateReset(); entry.latePause(false)
            XCTAssertEqual(DuelWorldView.activeClocks, baseline)
        }
    }

    private func exerciseSceneEntry(_ state: DuelSession, host: UIViewController, scene: UIWindowScene,
                                    baseline: Int) async throws
        -> (probe: DuelWorldReleaseProbe, latePause: (Bool) -> Void, lateReset: () -> Void) {
        let hero = state.setup.hero
        var world: DuelWorldView? = DuelWorldView(session: state)
        defer { world?.shutdown(); world?.removeFromSuperview() }
        let probe = try autoreleasepool { DuelWorldReleaseProbe(try XCTUnwrap(world)) }
        let originalObjects = probe.liveObjects()
        XCTAssertTrue(originalObjects.view && originalObjects.scene && originalObjects.camera,
                      "Lifetime checks must start with an actual view, scene and camera")
        // Keep copies alive even after the session clears its own slots:
        // stale callbacks must be weak and must not reactivate the view.
        let latePause = try XCTUnwrap(state.renderPause)
        let lateReset = try XCTUnwrap(state.didReset)
        world?.frame = host.view.bounds; host.view.addSubview(try XCTUnwrap(world))
        try await awaitClockProgress(state, world: XCTUnwrap(world), phase: "attach")
        let lifecycle = XCTAttachment(string: "hero=\(hero.rawValue) app=\(UIApplication.shared.applicationState.rawValue) scene=\(scene.activationState.rawValue) window=\(world?.window != nil) paused=\(state.paused) frame=\(state.game.frame) clocks=\(DuelWorldView.activeClocks)")
        lifecycle.name = "fighter-clock-\(hero.rawValue)"; lifecycle.lifetime = .keepAlways; add(lifecycle)
        XCTAssertEqual(UIApplication.shared.applicationState, .active, "The host must be in the foreground during clock checks")
        XCTAssertEqual(DuelWorldView.activeClocks, baseline + 1)
        XCTAssertGreaterThan(state.game.frame, 0)
        state.pause()
        XCTAssertEqual(DuelWorldView.activeClocks, baseline)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(DuelWorldView.activeClocks, baseline, "Foregrounding must not automatically resume an interrupted fight")
        let paused = state.game.frame
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(state.game.frame, paused)
        state.resume()
        XCTAssertEqual(DuelWorldView.activeClocks, baseline + 1)
        try await awaitClockProgress(state, world: XCTUnwrap(world), phase: "resume")
        let stoppedFrame = state.game.frame, stoppedCallbacks = world?.clockCallbacks
        autoreleasepool {
            world?.shutdown(); world?.removeFromSuperview()
            XCTAssertNil(world?.scene)
            XCTAssertFalse(world?.isPlaying ?? true); XCTAssertFalse(world?.rendersContinuously ?? true)
            XCTAssertNil(state.renderPause); XCTAssertNil(state.didReset); XCTAssertNil(state.didSimulateStep)
            XCTAssertTrue(world?.originalAssets.isEmpty ?? false)
            XCTAssertTrue(world?.weaponAssets.isEmpty ?? false)
            XCTAssertNil(world?.characterAsset); XCTAssertNil(world?.stageAsset)
            XCTAssertNil(world?.sourceEffects); XCTAssertNil(world?.weaponEffects)
            XCTAssertEqual(DuelWorldView.activeClocks, baseline)
            world?.layoutSubviews(); world?.drawState()
            lateReset(); latePause(true); latePause(false)
            XCTAssertEqual(state.game.frame, stoppedFrame)
            XCTAssertEqual(world?.clockCallbacks, stoppedCallbacks)
            probe.beginReleaseObservation()
            world = nil
        }
        return (probe, latePause, lateReset)
    }
}

@MainActor
private final class DuelWorldReleaseProbe {
    private weak var view: DuelWorldView?
    private weak var scene: SCNScene?
    private weak var camera: SCNNode?
    private(set) var releaseStartedAt = 0.0
    init(_ view: DuelWorldView) {
        self.view = view; scene = view.scene; camera = view.pointOfView
    }
    func beginReleaseObservation() { releaseStartedAt = ProcessInfo.processInfo.systemUptime }
    func liveObjects() -> (view: Bool, scene: Bool, camera: Bool) {
        // Do not query pointOfView on a closed SCNView: that would inspect a
        // fallback camera, not establish the lifetime of the original node.
        (view != nil, scene != nil, camera != nil)
    }
}
