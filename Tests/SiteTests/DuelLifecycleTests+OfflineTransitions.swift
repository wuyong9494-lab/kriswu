import XCTest
import Combine
@testable import ShiftReminder

@MainActor
extension DuelLifecycleTests {
    private func offlineTransitionSession() -> DuelSession {
        DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
    }

    func testOfflinePauseDoesNotRecursivelyPublishOrDispatchRendererStop() {
        let state = offlineTransitionSession()
        var publications = 0, stops = 0
        state.renderPause = { paused in
            XCTAssertTrue(paused)
            stops += 1
            state.pause()
        }
        let subscription = state.objectWillChange.sink {
            publications += 1
            state.pause()
            state.resume()
        }
        defer { subscription.cancel(); state.renderPause = nil; state.shutdown() }
        state.pause(); state.pause()
        XCTAssertTrue(state.paused)
        XCTAssertEqual(publications, 1, "An unchanged paused value must not republish to synchronous observers")
        XCTAssertGreaterThan(stops, 0)
        XCTAssertLessThanOrEqual(stops, 3, "A renderer stop callback must not recursively dispatch itself")
    }

    func testOfflineResumeCannotOverwritePauseOrShutdownDuringInputReset() {
        for closes in [false, true] {
            let state = offlineTransitionSession()
            state.pause()
            var resets = 0, starts = 0
            state.renderPause = { if !$0 { starts += 1 } }
            state.inputReset = {
                resets += 1
                if closes { state.shutdown() } else { state.pause() }
                state.input("right", down: true)
                state.resume()
            }
            state.resume()
            XCTAssertEqual(resets, 1)
            XCTAssertEqual(starts, 0)
            XCTAssertTrue(state.paused)
            XCTAssertTrue(state.held.isEmpty)
            let frame = state.game.frame
            state.advance()
            XCTAssertEqual(state.game.frame, frame)
            state.inputReset = nil
            state.resume()
            XCTAssertEqual(state.paused, closes, "A fresh explicit resume may recover a pause, never a closed session")
            state.shutdown()
        }
    }

    func testOfflineResumeRepairsStalePublishedFalseAfterPauseOrShutdown() {
        for closes in [false, true] {
            let state = offlineTransitionSession()
            state.pause()
            var starts = 0, publications = 0
            state.renderPause = { if !$0 { starts += 1 } }
            let subscription = state.objectWillChange.sink {
                publications += 1
                if closes { state.shutdown() } else { state.pause() }
            }
            state.resume()
            XCTAssertTrue(state.paused, "Published willSet must not let an outer false assignment erase a newer stop")
            XCTAssertEqual(starts, 0)
            XCTAssertEqual(publications, 2, "Publish the attempted resume and one corrective pause, without recursion")
            subscription.cancel()
            state.shutdown()
        }
    }

    func testShutdownInsidePausePublicationStillStopsRendererBeforeRemovingHook() {
        let state = offlineTransitionSession()
        var stops = 0
        state.renderPause = { if $0 { stops += 1 } }
        let subscription = state.objectWillChange.sink { state.shutdown() }
        state.pause()
        XCTAssertTrue(state.paused)
        XCTAssertEqual(stops, 1)
        XCTAssertNil(state.renderPause)
        subscription.cancel()
    }

    func testOfflineResumeAllowsOnlyOneReentrantStartAndStopsOnRendererInterruption() {
        for closes in [false, true] {
            let state = offlineTransitionSession()
            state.pause()
            var resets = 0, events: [Bool] = []
            state.inputReset = { resets += 1; state.resume() }
            state.renderPause = { paused in
                events.append(paused)
                if !paused {
                    if closes { state.shutdown() } else { state.pause() }
                }
            }
            state.resume()
            XCTAssertTrue(state.paused)
            XCTAssertEqual(events, [false, true])
            XCTAssertEqual(resets, 2, "Resume and the later stop each clear input once; nested resume never starts")
            state.inputReset = nil; state.renderPause = nil; state.shutdown()
        }
    }

    func testOfflineRestartStopsAfterInterruptionAtEveryCallbackBoundary() {
        for boundary in ["inputReset", "published", "didReset", "renderResume"] {
            for closes in [false, true] {
                let state = offlineTransitionSession()
                state.advance(); state.pause()
                let before = state.game
                var presented = 0
                let interrupt = { if closes { state.shutdown() } else { state.pause() } }
                var subscription: AnyCancellable?
                switch boundary {
                case "inputReset": state.inputReset = interrupt
                case "published": subscription = state.objectWillChange.sink { interrupt() }
                case "didReset": state.didReset = interrupt
                default: state.renderPause = { if !$0 { interrupt() } }
                }
                state.didSimulateStep = { _, _ in presented += 1 }
                state.restart()
                XCTAssertTrue(state.paused, "\(boundary)/closed=\(closes)")
                XCTAssertEqual(presented, 0, "An interrupted restart must not publish a fresh running frame")
                if boundary == "inputReset" || boundary == "published" {
                    XCTAssertEqual(state.game, before, "An early interrupted restart must not partially replace simulation state")
                } else {
                    XCTAssertEqual(state.game.frame, 0)
                    XCTAssertEqual(state.animationTick, 0)
                }
                subscription?.cancel()
                state.inputReset = nil; state.didReset = nil; state.renderPause = nil
                state.shutdown()
            }
        }
    }

    func testOfflineRestartRejectsNestedRestartResumeAndInputWithoutLosingItsOneReset() {
        let state = offlineTransitionSession()
        state.advance(); state.pause()
        var resets = 0, starts = 0, presented = 0
        state.didReset = { resets += 1; state.restart(); state.resume() }
        state.renderPause = { if !$0 { starts += 1 } }
        state.didSimulateStep = { _, _ in presented += 1 }
        let subscription = state.objectWillChange.sink {
            state.restart(); state.resume()
            state.input("right", down: true)
            state.advance()
        }
        state.restart()
        XCTAssertFalse(state.paused)
        XCTAssertEqual(resets, 1); XCTAssertEqual(starts, 1); XCTAssertEqual(presented, 1)
        XCTAssertEqual(state.game.frame, 0)
        XCTAssertTrue(state.held.isEmpty)
        subscription.cancel()
        state.didReset = nil; state.renderPause = nil; state.shutdown()
    }
}
