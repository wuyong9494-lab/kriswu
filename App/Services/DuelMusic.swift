import AVFoundation
import UIKit

@MainActor
protocol DuelMusicPlayback: AnyObject {
    var volume: Float { get set }
    var numberOfLoops: Int { get set }
    func play() -> Bool
    func pause()
    func stop()
}

extension AVAudioPlayer: DuelMusicPlayback {}

/// Lifecycle adapter for explicitly verified track URLs. DuelSourceMusic pins
/// the recovered temple-fall/Palace bytes and binds only a proven scene. Never
/// substitute the unrelated Arena score or infer scene variants from a character.
@MainActor
final class DuelMusic: NSObject {
    enum Scene: Hashable, Sendable { case lobby, battle }
    enum Status: Equatable { case stopped, unavailable, paused, playing, failed }
    private(set) var status: Status = .stopped
    private(set) var scene: Scene?
    private let tracks: [Scene: URL]
    private let makePlayer: (URL) throws -> DuelMusicPlayback
    private let activateSession: () throws -> Void
    private let center: NotificationCenter
    private var player: DuelMusicPlayback?
    private var loadedScene: Scene?
    private var active: Bool
    private var paused = false
    private var muted = false
    private var interrupted = false
    private var requiresUserResume = false
    private var pendingUserResume = false
    private var mediaServicesAvailable = true
    private var closed = false
    private var gain: Float = 0.6
    private var permitsPlayback: @MainActor () -> Bool = { true }

    init(tracks: [Scene: URL] = [:],
         center: NotificationCenter = .default,
         initiallyActive: Bool? = nil,
         makePlayer: @escaping (URL) throws -> DuelMusicPlayback = { try AVAudioPlayer(contentsOf: $0) },
         activateSession: @escaping () throws -> Void = {
             let session = AVAudioSession.sharedInstance()
             try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
             try session.setActive(true)
         }) {
        self.tracks = tracks; self.center = center
        active = initiallyActive ?? (UIApplication.shared.applicationState == .active)
        self.makePlayer = makePlayer; self.activateSession = activateSession
        super.init()
        center.addObserver(self, selector: #selector(suspend), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(activate), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(interruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(mediaServicesLost), name: AVAudioSession.mediaServicesWereLostNotification, object: nil)
        center.addObserver(self, selector: #selector(mediaServicesReset), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    deinit { center.removeObserver(self) }

    func setScene(_ value: Scene?) { setScene(value, paused: paused) }

    /// Install both owner inputs before reconciling. A remount is not a user
    /// resume, and must not briefly play the previous scene while switching.
    func setScene(_ value: Scene?, paused: Bool) {
        guard !closed else { return }
        // Ownership invokes this when the selected token or pause state changes,
        // including same-scene replacements. Deferred consent cannot transfer.
        pendingUserResume = false
        self.paused = paused
        if scene != value {
            player?.stop(); player = nil; loadedScene = nil; scene = value
        }
        reconcile()
    }

    /// Ownership supplies a live predicate so deferred SwiftUI updates cannot
    /// let foreground/interruption callbacks start a failed or closed session.
    func setPlaybackPermission(_ predicate: @escaping @MainActor () -> Bool) {
        guard !closed else { return }
        pendingUserResume = false
        permitsPlayback = predicate
    }
    /// Refresh a retained owner's readiness without granting user consent.
    /// Interruption, route and media-reset gates remain authoritative.
    func refreshPlaybackPermission() {
        guard !closed else { return }
        if !permitsPlayback() { pendingUserResume = false }
        // Do not turn ordinary ownership updates into failed-session retries.
        guard status == .playing || status == .paused else { return }
        reconcile()
    }

    func setPaused(_ value: Bool) {
        guard !closed else { return }
        if value { pendingUserResume = false }
        paused = value; reconcile()
    }
    /// Only an explicit successful user Resume/Restart may clear route/reset
    /// safety. Visibility, readiness and owner replacement are not permission.
    func resumeAfterUserAction(sessionInterruptionEnded: Bool = false) {
        guard !closed, !paused, scene != nil, active, mediaServicesAvailable, permitsPlayback() else { return }
        if interrupted {
            // The current session can consume ended before this independent
            // observer. Retain its successful explicit action, never permission
            // to play through an interruption or to transfer to another owner.
            if sessionInterruptionEnded { pendingUserResume = true }
            return
        }
        pendingUserResume = false
        requiresUserResume = false
        reconcile()
    }
    func setMuted(_ value: Bool) {
        guard !closed else { return }
        if value { pendingUserResume = false }
        muted = value; reconcile()
    }
    func setVolume(_ value: Float) {
        guard !closed else { return }
        gain = value.isFinite ? min(1, max(0, value)) : 0
        player?.volume = gain
    }

    /// Final disposal is terminal. A late resume or foreground event cannot
    /// restart audio from a dismissed match. Do not deactivate the shared audio
    /// session here: source hit sounds and other app features also use it.
    func shutdown() {
        guard !closed else { return }
        closed = true; pendingUserResume = false; center.removeObserver(self)
        player?.stop(); player = nil; loadedScene = nil; scene = nil; status = .stopped
    }

    private enum Event: Sendable, Equatable {
        case suspend, activate, interruptionBegan, interruptionEnded(shouldResume: Bool), headphonesRemoved
        case mediaServicesLost, mediaServicesReset
    }

    // NotificationCenter selector delivery uses the posting thread, not the
    // actor of this object. Extract only Sendable values there, then enqueue all
    // events (including main-thread posts) on one FIFO main queue. Mixing inline
    // delivery and asynchronous delivery can reverse began/ended notifications.
    private nonisolated func enqueue(_ event: Event) {
        DispatchQueue.main.async { [weak self] in self?.receive(event) }
    }
    @objc private nonisolated func suspend() { enqueue(.suspend) }
    @objc private nonisolated func activate() { enqueue(.activate) }
    @objc private nonisolated func mediaServicesLost() { enqueue(.mediaServicesLost) }
    @objc private nonisolated func mediaServicesReset() { enqueue(.mediaServicesReset) }
    @objc private nonisolated func interruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began { enqueue(.interruptionBegan) }
        else {
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            enqueue(.interruptionEnded(shouldResume:
                AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)))
        }
    }
    @objc private nonisolated func routeChanged(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        enqueue(.headphonesRemoved)
    }

    private func receive(_ event: Event) {
        // Observer removal does not cancel callbacks already queued before
        // shutdown. Check terminal ownership before any state mutation.
        guard !closed else { return }
        switch event {
        case .suspend: active = false; pendingUserResume = false
        case .activate: active = true
        case .interruptionBegan: interrupted = true; pendingUserResume = false
        case .interruptionEnded(let shouldResume):
            interrupted = false
            if !shouldResume, scene.flatMap({ tracks[$0] }) != nil { requiresUserResume = true }
            let granted = pendingUserResume
            pendingUserResume = false
            if granted, active, !paused, !muted, mediaServicesAvailable, permitsPlayback() {
                requiresUserResume = false
            }
        case .headphonesRemoved:
            pendingUserResume = false
            // Do not unexpectedly transfer music from headphones to speakers.
            if scene.flatMap({ tracks[$0] }) != nil { requiresUserResume = true }
        case .mediaServicesLost, .mediaServicesReset:
            pendingUserResume = false
            mediaServicesAvailable = event == .mediaServicesReset
            if mediaServicesAvailable { interrupted = false }
            // AVAudioPlayer objects are invalid after a media-server reset.
            // Keep owner/mute/pause state, discard the old player, and wait for
            // explicit user intent instead of automatically replaying audio.
            player?.stop(); player = nil; loadedScene = nil
            if scene.flatMap({ tracks[$0] }) != nil { requiresUserResume = true }
        }
        reconcile()
    }

    private func reconcile() {
        guard !closed else { return }
        guard let scene else { status = .stopped; return }
        guard let url = tracks[scene] else { status = .unavailable; return }
        guard active, !paused, !muted, !interrupted, !requiresUserResume, mediaServicesAvailable, permitsPlayback() else {
            player?.pause(); status = .paused; return
        }
        // Repeated SwiftUI updates must not restart the current loop.
        if status == .playing, loadedScene == scene { return }
        do {
            if loadedScene != scene || player == nil {
                player = try makePlayer(url); loadedScene = scene
                player?.numberOfLoops = -1; player?.volume = gain
            }
            try activateSession()
            status = player?.play() == true ? .playing : .failed
        } catch { status = .failed }
    }
}
