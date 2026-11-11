import XCTest
import AVFoundation
import UIKit
@testable import ShiftReminder

@MainActor
final class DuelMusicTests: XCTestCase {
    private final class Player: DuelMusicPlayback {
        var volume: Float = 0
        var numberOfLoops = 0
        var plays = 0, pauses = 0, stops = 0
        func play() -> Bool { XCTAssertTrue(Thread.isMainThread); plays += 1; return true }
        func pause() { XCTAssertTrue(Thread.isMainThread); pauses += 1 }
        func stop() { XCTAssertTrue(Thread.isMainThread); stops += 1 }
    }

    private func drainNotifications() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    func testOffMainCallbacksPreserveOrderAndLateCallbacksCannotRestart() async {
        let center = NotificationCenter(), player = Player()
        let music = DuelMusic(tracks: [.battle: URL(fileURLWithPath: "/fixture.wav")], center: center,
            initiallyActive: true, makePlayer: { _ in player }, activateSession: {})
        music.setScene(.battle)
        // The serial posting queue must enqueue began before ended. No audio
        // player method is allowed to execute on this posting thread.
        await withCheckedContinuation { continuation in
            DispatchQueue(label: "duel.music.notification-test").async {
                center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
                center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                               AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
                continuation.resume()
            }
        }
        await drainNotifications()
        XCTAssertEqual(music.status, .playing); XCTAssertEqual(player.plays, 2)
        XCTAssertEqual(player.pauses, 1)
        // Queue callbacks while still on the actor, then close before yielding.
        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        music.shutdown()
        await drainNotifications()
        XCTAssertEqual(music.status, .stopped); XCTAssertNil(music.scene)
        XCTAssertEqual(player.plays, 2); XCTAssertEqual(player.stops, 1)
    }

    func testMissingSourceNeverConstructsPlayerOrActivatesSession() {
        let music = DuelMusic(initiallyActive: true, makePlayer: { _ in
            XCTFail("No verified music track is available"); return Player()
        }, activateSession: { XCTFail("Missing music must not change the shared audio session") })
        defer { music.shutdown() }
        music.setScene(.lobby); XCTAssertEqual(music.status, .unavailable)
        music.setScene(.battle); XCTAssertEqual(music.status, .unavailable)
    }

    func testScenePauseBackgroundAndTerminalShutdown() async {
        let center = NotificationCenter(), lobby = Player(), battle = Player()
        let music = DuelMusic(tracks: [.lobby: URL(fileURLWithPath: "/fixture-lobby.wav"),
                                       .battle: URL(fileURLWithPath: "/fixture-battle.wav")],
            center: center, initiallyActive: true,
            makePlayer: { $0.lastPathComponent.contains("lobby") ? lobby : battle }, activateSession: {})
        music.setScene(.lobby); music.setScene(.lobby)
        XCTAssertEqual(lobby.plays, 1); XCTAssertEqual(lobby.numberOfLoops, -1)
        music.setScene(.battle); XCTAssertEqual(lobby.stops, 1); XCTAssertEqual(battle.plays, 1)
        music.setPaused(true); XCTAssertEqual(music.status, .paused)
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await drainNotifications()
        XCTAssertEqual(battle.plays, 1)
        music.setPaused(false); XCTAssertEqual(battle.plays, 2)
        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        await drainNotifications()
        music.setPaused(false); XCTAssertEqual(battle.plays, 2)
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await drainNotifications()
        XCTAssertEqual(battle.plays, 3)
        music.shutdown(); music.setScene(.lobby); music.setPaused(false)
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await drainNotifications()
        XCTAssertEqual(music.status, .stopped); XCTAssertEqual(battle.plays, 3)
    }

    func testDecoderFailureIsExplicitAndInterruptionWithoutPermissionStaysPaused() async {
        enum FixtureError: Error { case decoding }
        let broken = DuelMusic(tracks: [.lobby: URL(fileURLWithPath: "/broken.wav")], initiallyActive: true,
            makePlayer: { _ in throw FixtureError.decoding }, activateSession: {})
        broken.setScene(.lobby); XCTAssertEqual(broken.status, .failed); broken.shutdown()
        let center = NotificationCenter(), player = Player()
        let music = DuelMusic(tracks: [.battle: URL(fileURLWithPath: "/fixture.wav")], center: center,
            initiallyActive: true, makePlayer: { _ in player }, activateSession: {})
        defer { music.shutdown() }
        music.setScene(.battle)
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        await drainNotifications()
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        await drainNotifications()
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await drainNotifications()
        XCTAssertEqual(music.status, .paused); XCTAssertEqual(player.plays, 1)
        music.setPaused(false); XCTAssertEqual(player.plays, 1)
        music.resumeAfterUserAction(); XCTAssertEqual(player.plays, 2)
    }

    func testInterruptionCannotResumeMutedMusicAndRouteRemovalRequiresResume() async {
        let center = NotificationCenter(), player = Player()
        let music = DuelMusic(tracks: [.battle: URL(fileURLWithPath: "/fixture.wav")], center: center,
            initiallyActive: true, makePlayer: { _ in player }, activateSession: {})
        defer { music.shutdown() }
        music.setScene(.battle)
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        await drainNotifications()
        music.setMuted(true)
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                               AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        await drainNotifications()
        XCTAssertEqual(player.plays, 1)
        music.setMuted(false); XCTAssertEqual(player.plays, 2)
        center.post(name: AVAudioSession.routeChangeNotification, object: nil,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        await drainNotifications()
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await drainNotifications()
        XCTAssertEqual(player.plays, 2)
        music.setPaused(false); XCTAssertEqual(player.plays, 2)
        music.resumeAfterUserAction(); XCTAssertEqual(player.plays, 3)
        music.setVolume(.nan); XCTAssertEqual(player.volume, 0)
    }

    func testSafetySuspensionSurvivesAutomaticScenePauseAndMuteChanges() async {
        let center = NotificationCenter(), player = Player()
        let music = DuelMusic(tracks: [.battle: URL(fileURLWithPath: "/fixture.wav")], center: center,
            initiallyActive: true, makePlayer: { _ in player }, activateSession: {})
        defer { music.shutdown() }
        music.setScene(.battle)
        center.post(name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        await drainNotifications()
        music.setScene(nil); music.setScene(.battle, paused: true)
        music.setPaused(false); music.setMuted(true); music.setMuted(false)
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await drainNotifications()
        XCTAssertEqual(player.plays, 1)
        XCTAssertEqual(music.status, .paused)
        music.resumeAfterUserAction()
        XCTAssertEqual(player.plays, 2)
    }

    func testMediaServiceLossAndResetRequireExplicitResumeAndRecreatePlayer() async {
        let center = NotificationCenter(), previous = Player(), replacement = Player()
        var creations = 0, activations = 0
        let music = DuelMusic(tracks: [.battle: URL(fileURLWithPath: "/fixture.wav")], center: center,
            initiallyActive: true, makePlayer: { _ in
                creations += 1; return creations == 1 ? previous : replacement
            }, activateSession: { activations += 1 })
        defer { music.shutdown() }
        music.setScene(.battle)
        center.post(name: AVAudioSession.mediaServicesWereLostNotification, object: nil)
        await drainNotifications()
        XCTAssertEqual(previous.stops, 1)
        music.resumeAfterUserAction()
        XCTAssertEqual(creations, 1, "A lost media service cannot be restarted yet")
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        await drainNotifications()
        music.setScene(.battle, paused: false)
        XCTAssertEqual(music.status, .paused); XCTAssertEqual(activations, 1)
        music.resumeAfterUserAction()
        XCTAssertEqual(creations, 2); XCTAssertEqual(activations, 2)
        XCTAssertEqual(replacement.plays, 1); XCTAssertEqual(previous.plays, 1)
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        music.shutdown()
        await drainNotifications()
        music.resumeAfterUserAction()
        XCTAssertEqual(creations, 2); XCTAssertEqual(music.status, .stopped)
    }

    func testPausedLoadingAndFailedActivationNeverPlayOrReactivateImplicitly() {
        enum FixtureError: Error { case session }
        let player = Player()
        var creations = 0, activations = 0, mayActivate = false
        let music = DuelMusic(tracks: [.battle: URL(fileURLWithPath: "/fixture.wav")], initiallyActive: true,
            makePlayer: { _ in creations += 1; return player }, activateSession: {
                activations += 1
                if !mayActivate { throw FixtureError.session }
            })
        defer { music.shutdown() }
        music.setScene(.battle, paused: true)
        music.resumeAfterUserAction()
        XCTAssertEqual(creations, 0); XCTAssertEqual(activations, 0)
        music.setPaused(false)
        XCTAssertEqual(music.status, .failed); XCTAssertEqual(player.plays, 0)
        mayActivate = true
        music.resumeAfterUserAction()
        XCTAssertEqual(music.status, .playing); XCTAssertEqual(activations, 2)
        music.setScene(.battle, paused: false)
        XCTAssertEqual(activations, 2, "Repeated updates must not reconfigure the shared audio session")
    }

    func testUnownedSharedSessionEventsDoNotBlockALaterNewMatch() async {
        let center = NotificationCenter(), player = Player()
        let music = DuelMusic(tracks: [.battle: URL(fileURLWithPath: "/fixture.wav")], center: center,
            initiallyActive: true, makePlayer: { _ in player }, activateSession: {})
        defer { music.shutdown() }
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        center.post(name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        await drainNotifications()
        music.setScene(.battle)
        XCTAssertEqual(player.plays, 1)
    }

    // UNRUN. Session-ended evidence arrives before the music observer's ended.
    func testSuccessfulSessionConsentWaitsForMusicEndedWithoutEarlyPlayback() async {
        let center = NotificationCenter(), player = Player()
        let music = DuelMusic(tracks: [.battle: URL(fileURLWithPath: "/fixture.wav")], center: center,
            initiallyActive: true, makePlayer: { _ in player }, activateSession: {})
        defer { music.shutdown() }
        music.setScene(.battle)
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        await drainNotifications()
        music.resumeAfterUserAction() // No successful-session evidence: still rejected.
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        music.resumeAfterUserAction(sessionInterruptionEnded: true)
        XCTAssertEqual(player.plays, 1)
        await drainNotifications()
        XCTAssertEqual(player.plays, 2)
        XCTAssertEqual(music.status, .playing)
        // A later interruption cannot reuse the one-shot grant.
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        await drainNotifications()
        XCTAssertEqual(player.plays, 2)
        XCTAssertEqual(music.status, .paused)
    }

    func testNewSuspensionOrInvalidPermissionCancelsDeferredMusicConsent() async {
        for cancellation in ["began", "route", "background", "reset", "pause", "mute", "permission", "closed"] {
            let center = NotificationCenter(), player = Player()
            let music = DuelMusic(tracks: [.battle: URL(fileURLWithPath: "/fixture.wav")], center: center,
                initiallyActive: true, makePlayer: { _ in player }, activateSession: {})
            defer { music.shutdown() }
            var permitted = true
            music.setPlaybackPermission { permitted }
            music.setScene(.battle)
            center.post(name: AVAudioSession.interruptionNotification, object: nil,
                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
            await drainNotifications()
            music.resumeAfterUserAction(sessionInterruptionEnded: true)
            switch cancellation {
            case "began":
                center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
            case "route":
                center.post(name: AVAudioSession.routeChangeNotification, object: nil,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
            case "background": center.post(name: UIApplication.willResignActiveNotification, object: nil)
            case "reset": center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
            case "pause": music.setPaused(true); music.setPaused(false)
            case "mute": music.setMuted(true); music.setMuted(false)
            case "permission": permitted = false
            default: music.shutdown()
            }
            center.post(name: AVAudioSession.interruptionNotification, object: nil,
                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
            await drainNotifications()
            permitted = true
            center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            await drainNotifications()
            XCTAssertEqual(player.plays, 1, cancellation)
        }
    }

}
