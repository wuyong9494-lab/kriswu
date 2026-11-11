import XCTest
import UIKit
@testable import ShiftReminder

@MainActor
extension DuelLifecycleTests {
    func testOfflineReplacementRetiresOldRendererBeforeInstallingCallbacks() {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        let old = DuelWorldView(session: state, characterSource: .procedural)
        let replacement = DuelWorldView(session: state, characterSource: .procedural)
        defer { old.shutdown(); replacement.shutdown(); state.shutdown() }

        XCTAssertNil(old.scene, "A replacement must retire the previous renderer, including its clock")
        XCTAssertNotNil(replacement.scene)
        state.input("right", down: true)
        // UIKit can deliver dismantle/detach after the replacement is live.
        old.shutdown()
        old.didMoveToWindow()
        XCTAssertNotNil(state.renderPause, "Late old-view teardown must preserve pause/resume routing")
        XCTAssertNotNil(state.didSimulateStep)
        XCTAssertNotNil(state.didReset)
        XCTAssertTrue(state.held.contains("right"), "Late teardown must not cancel the new view's input")
        state.pause(); state.resume()
        XCTAssertFalse(state.paused)
        XCTAssertNotNil(state.renderPause)
        replacement.shutdown()
        XCTAssertNil(state.renderPause)
        XCTAssertNil(state.didSimulateStep)
        XCTAssertNil(state.didReset)
    }

    func testOfflineReplacementCannotOverwriteReentrantRendererClaim() {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        let old = DuelWorldView(session: state, characterSource: .procedural)
        var newest: DuelWorldView?
        state.inputReset = {
            state.inputReset = nil
            newest = DuelWorldView(session: state, characterSource: .procedural)
        }
        let superseded = DuelWorldView(session: state, characterSource: .procedural)
        defer { old.shutdown(); superseded.shutdown(); newest?.shutdown(); state.shutdown() }
        XCTAssertNil(old.scene)
        XCTAssertNil(superseded.scene)
        XCTAssertNotNil(newest?.scene)
        superseded.shutdown()
        XCTAssertNotNil(state.renderPause)
        XCTAssertNotNil(state.didSimulateStep)
        XCTAssertNotNil(state.didReset)
    }

    func testClosedOfflineSessionRejectsLateRendererConstruction() {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        state.shutdown()
        let late = DuelWorldView(session: state, characterSource: .procedural)
        defer { late.shutdown() }
        XCTAssertNil(late.scene)
        XCTAssertNil(state.renderPause)
        XCTAssertNil(state.didSimulateStep)
        XCTAssertNil(state.didReset)
    }
}
