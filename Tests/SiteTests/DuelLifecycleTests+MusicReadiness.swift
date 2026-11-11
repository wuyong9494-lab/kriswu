import XCTest
import UIKit
import AVFoundation
@testable import ShiftReminder

@MainActor
extension DuelLifecycleTests {
    func testProceduralActorsCannotAuthorizeOriginalPalaceMusic() {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        state.pause()
        let world = DuelWorldView(session: state, characterSource: .procedural)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 956, height: 440))
        window.rootViewController = UIViewController()
        defer { world.shutdown(); state.shutdown(); window.isHidden = true }
        world.testingMusicPrepare = { _, _ in XCTFail("Procedural placeholders must not request original scene music") }
        world.frame = window.bounds
        window.rootViewController?.view.addSubview(world)
        window.isHidden = false
        world.layoutSubviews()
        XCTAssertFalse(world.hasPreparedSourceMusicScene)
        XCTAssertFalse(state.sourceMusicReady)
        state.shutdown()
        state.refreshSourceMusicReadiness(from: world)
        XCTAssertFalse(state.sourceMusicReady)
    }

    func testOnlyCompletedUserResumeCanAuthorizeAudioSafetyRelease() {
        for restarting in [false, true] {
            let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
            defer { state.shutdown() }
            state.pause()
            state.inputReset = { state.pause() }
            XCTAssertFalse(state.performUserResume(restarting: restarting))
            XCTAssertTrue(state.paused)
            state.inputReset = nil
            XCTAssertTrue(state.performUserResume(restarting: restarting))
            state.shutdown()
            XCTAssertFalse(state.performUserResume(restarting: restarting))
        }
    }

    // UNRUN: notification ordering and consent regression, not audible parity.
    func testAudioInterruptionRejectsEarlyResumeAndRouteRemovalPausesCurrentSession() async {
        XCTAssertEqual(UIApplication.shared.applicationState, .active,
                       "Run audio-consent recovery acceptance with the app host foreground-active")
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        defer { state.shutdown() }
        let center = NotificationCenter.default
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        await drainSessionAudioNotifications()
        XCTAssertTrue(state.paused)
        XCTAssertFalse(state.performUserResume())
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        await drainSessionAudioNotifications()
        state.resume(); XCTAssertTrue(state.paused)
        XCTAssertTrue(state.performUserResume())
        XCTAssertFalse(state.paused)
        center.post(name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        await drainSessionAudioNotifications()
        XCTAssertTrue(state.paused)
        state.restart(); XCTAssertTrue(state.paused)
        XCTAssertTrue(state.performUserResume(restarting: true))
        state.shutdown()
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        await drainSessionAudioNotifications()
        XCTAssertFalse(state.performUserResume())
    }

    func testRouteRemovalTerminatesAuthoritativeSessionRatherThanOfferingResume() async throws {
        let state = try DuelSession(presentationFixture:
            DuelGame(hero: .liu, difficulty: .learning, mode: .practice), localFighterIndex: 0)
        defer { state.shutdown() }
        var stops = 0
        state.didRequestAuthoritativeStop = { stops += 1 }
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        await drainSessionAudioNotifications()
        XCTAssertEqual(stops, 1)
        XCTAssertTrue(state.paused)
        XCTAssertFalse(state.performUserResume(restarting: true))
        state.pause(); XCTAssertEqual(stops, 1)
    }

    private func drainSessionAudioNotifications() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

}
