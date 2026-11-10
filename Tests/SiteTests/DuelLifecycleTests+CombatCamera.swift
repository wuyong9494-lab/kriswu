import XCTest
import UIKit
import SceneKit
@testable import ShiftReminder

@MainActor
extension DuelLifecycleTests {
    func testCombatCameraDoesNotAdvanceOnRepeatedDrawsOrPausedLayout() throws {
        let state = DuelSession(.init(hero: .ember, difficulty: .learning, mode: .practice))
        let world = DuelWorldView(session: state, characterSource: .procedural)
        defer { world.shutdown(); state.shutdown() }
        world.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        world.layoutSubviews()
        state.input("right", down: true)
        for _ in 0..<20 { state.advance() }
        world.drawState()
        let camera = try XCTUnwrap(world.pointOfView)
        let motion = world.combatCamera, position = camera.position
        XCTAssertGreaterThan(motion.centerX, 5)
        for _ in 0..<30 {
            world.drawState(); world.layoutSubviews()
            XCTAssertEqual(world.combatCamera, motion)
            XCTAssertEqual(camera.position.x, position.x, accuracy: 0.000001)
            XCTAssertEqual(camera.position.y, position.y, accuracy: 0.000001)
            XCTAssertEqual(camera.position.z, position.z, accuracy: 0.000001)
        }
        state.pause()
        for _ in 0..<10 { state.advance(); world.drawState() }
        XCTAssertEqual(world.combatCamera, motion)
        state.restart(); world.drawState()
        XCTAssertEqual(world.combatCamera.centerX, 5)
        XCTAssertEqual(world.combatCamera.impactOffsetX, 0)
        XCTAssertEqual(world.combatCamera.separation, 3)
    }

    func testCombatCameraMatchesAcrossSingleAndBatchedRendering() throws {
        let first = DuelSession(.init(hero: .ember, difficulty: .learning, mode: .practice))
        let second = DuelSession(.init(hero: .ember, difficulty: .learning, mode: .practice))
        let firstWorld = DuelWorldView(session: first, characterSource: .procedural)
        let secondWorld = DuelWorldView(session: second, characterSource: .procedural)
        defer { firstWorld.shutdown(); secondWorld.shutdown(); first.shutdown(); second.shutdown() }
        for world in [firstWorld, secondWorld] {
            world.frame = CGRect(x: 0, y: 0, width: 844, height: 390); world.layoutSubviews()
        }
        first.input("right", down: true); second.input("right", down: true)
        for tick in 0..<40 {
            first.advance(); second.advance()
            firstWorld.drawState()
            if tick % 7 == 0 { secondWorld.drawState() }
        }
        secondWorld.drawState()
        XCTAssertEqual(first.game, second.game)
        XCTAssertEqual(firstWorld.combatCamera, secondWorld.combatCamera,
                       "Drawing fewer frames must not change the per-step camera state")
        let a = try XCTUnwrap(firstWorld.pointOfView), b = try XCTUnwrap(secondWorld.pointOfView)
        XCTAssertEqual(a.position.x, b.position.x, accuracy: 0.000001)
        XCTAssertEqual(a.position.z, b.position.z, accuracy: 0.000001)
        XCTAssertEqual(a.camera?.fieldOfView, b.camera?.fieldOfView)
        XCTAssertEqual(a.camera?.orthographicScale, b.camera?.orthographicScale)
    }

    #if DEBUG
    func testAuthoritativeCameraUsesEveryPublishedStepAndStopsOnCancellation() throws {
        var game = DuelGame(hero: .ember, difficulty: .learning, mode: .practice, opponentHero: .liu)
        let first = try DuelSession(presentationFixture: game, localFighterIndex: 0)
        let second = try DuelSession(presentationFixture: game, localFighterIndex: 1)
        let firstWorld = DuelWorldView(session: first, characterSource: .presentationFixture)
        let secondWorld = DuelWorldView(session: second, characterSource: .presentationFixture)
        defer { firstWorld.shutdown(); secondWorld.shutdown(); first.shutdown(); second.shutdown() }
        try first.startAuthoritativePresentation(); try second.startAuthoritativePresentation()
        for tick in 0..<40 {
            game.step(.init(move: 1), opponent: .neutral)
            try first.publishAuthoritativeStep(trustedGame: game, tick: UInt64(tick))
            try second.publishAuthoritativeStep(trustedGame: game, tick: UInt64(tick))
            firstWorld.drawState()
            if tick % 7 == 0 { secondWorld.drawState() }
            XCTAssertEqual(firstWorld.combatCamera, secondWorld.combatCamera)
        }
        XCTAssertGreaterThan(firstWorld.combatCamera.centerX, 5)
        let finalCamera = secondWorld.combatCamera
        game.cancelBufferedInputs()
        try first.publishAuthoritativeCancellation(trustedGame: game)
        try second.publishAuthoritativeCancellation(trustedGame: game)
        for _ in 0..<10 { second.advance(); secondWorld.drawState() }
        XCTAssertTrue(second.paused)
        XCTAssertEqual(secondWorld.combatCamera, finalCamera,
                       "Cancellation must not synthesize another camera/effect step")
    }
    #endif
}
