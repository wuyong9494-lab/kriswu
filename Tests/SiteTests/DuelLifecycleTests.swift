import XCTest
import UIKit
import SceneKit
@testable import ShiftReminder

@MainActor
final class DuelLifecycleTests: XCTestCase {
    private func session(_ hero: DuelGame.Hero = .ember, mode: DuelGame.Mode = .practice) -> DuelSession {
        DuelSession(.init(hero: hero, difficulty: .learning, mode: mode))
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
            var world: DuelWorldView? = DuelWorldView(session: state)
            weak var released = world
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
            world?.shutdown(); world?.removeFromSuperview()
            XCTAssertNil(world?.scene)
            XCTAssertEqual(DuelWorldView.activeClocks, baseline)
            world = nil
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertNil(released, "SceneKit view must not be retained by its display link or session")
        }
    }
}
