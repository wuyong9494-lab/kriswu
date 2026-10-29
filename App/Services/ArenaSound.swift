import AVFoundation
import Foundation
import UIKit

/// 乱斗的声音。效果和两首循环音乐各只创建一次：大厅一首，进对局换成战斗那首，出来再换回去。
/// 用「环境音」：和别的 App 的音乐混着放，手机静音时不响；正放着别的音乐时不放背景音乐。
/// 静音记在 arena.mute，音量记在 arena.volume（0–1）
@MainActor
final class ArenaSound: NSObject {
    static let shared = ArenaSound()
    nonisolated static let muteKey = "arena.mute"
    nonisolated static let volumeKey = "arena.volume"
    nonisolated static let musicVolumeKey = "arena.musicVolume"
    nonisolated static let effectsVolumeKey = "arena.effectsVolume"
    nonisolated static let musicMuteKey = "arena.musicMute"
    nonisolated static let effectsMuteKey = "arena.effectsMute"

    enum Effect: String, CaseIterable {
        case shot, slash, magic, boom, hit, knockout = "ko", power = "super", pickup, heal, respawn, blink, win, lose, gadget, hyper

        var file: String { "arena_" + rawValue }
        /// 同时能响几个（电脑一起开火时叠得起来）
        var voices: Int {
            switch self {
            case .shot, .slash, .magic, .hit: return 5
            case .boom: return 3
            default: return 2
            }
        }
    }

    private enum Bed { case lobby, battle }

    private var players: [Effect: [AVAudioPlayer]] = [:]
    private var lastPlayed: [Effect: TimeInterval] = [:]
    private var beds: [Bed: AVAudioPlayer] = [:]
    private var bed: Bed?
    private var sessionOn = false
    private(set) var state = ArenaAudioState()
    private var fadeTask: Task<Void, Never>?
    private var inMatch: Bool { state.inMatch }
    private var matchOwner: ObjectIdentifier?

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(suspendApp), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(resumeApp), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(interruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(silenceHintChanged), name: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil)
    }

    @objc private func suspendApp() { pause(.background) }
    @objc private func resumeApp() { state.resume(.background); reconcile() }
    @objc nonisolated private func interruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
        let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        // AVAudioSession notifications are not guaranteed to arrive on the main thread.
        Task { @MainActor [weak self] in
            guard let self, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began { self.sessionOn = false; self.pause(.interruption) }
            else if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                self.state.resume(.interruption)
                self.reconcile()
            }
        }
    }
    @objc nonisolated private func routeChanged(_ note: Notification) {
        let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        Task { @MainActor [weak self] in
            guard let self else { return }
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                self.pause(.interruption)
            } else { self.reconcile() }
        }
    }
    @objc nonisolated private func silenceHintChanged() {
        Task { @MainActor [weak self] in self?.reconcile() }
    }

    func pauseRenderer(owner: ObjectIdentifier? = nil) {
        guard owner == matchOwner else { return }
        pause(.renderer)
    }
    private func pause(_ reason: ArenaAudioState.Pause) {
        state.pause(reason)
        fadeTask?.cancel()
        players.values.joined().forEach { $0.stop() }
        beds.values.forEach { $0.pause() }
        if reason == .background { deactivate() }
    }

    /// Explicit user action after headphone removal or a non-resumable interruption.
    func resumeAudio() { state.resume(.interruption); reconcile() }

    var muted: Bool { UserDefaults.standard.bool(forKey: Self.muteKey) }

    var volume: Float {
        let stored = UserDefaults.standard.object(forKey: Self.volumeKey) as? Double
        return Float(min(max(stored ?? 0.7, 0), 1))
    }

    private func level(_ key: String) -> Float {
        let value = UserDefaults.standard.object(forKey: key) as? Double ?? Double(volume)
        return Float(min(max(value, 0), 1))
    }
    private var musicMuted: Bool { muted || UserDefaults.standard.bool(forKey: Self.musicMuteKey) }
    private var effectsMuted: Bool { muted || UserDefaults.standard.bool(forKey: Self.effectsMuteKey) }

    func enterLobby() { state.enterLobby(); reconcile() }
    func leaveLobby() { state.leaveLobby(); reconcile() }
    func begin(owner: ObjectIdentifier? = nil) {
        if owner != matchOwner {
            state.end()
            matchOwner = owner
        }
        state.begin()
        reconcile()
    }

    /// Only actual match teardown calls end; backgrounding only pauses.
    func end(owner: ObjectIdentifier? = nil) {
        guard owner == matchOwner else { return }
        matchOwner = nil
        state.end()
        players.values.joined().forEach { $0.stop() }
        reconcile()
    }

    func muteChanged(battle: Bool) {
        if muted { players.values.joined().forEach { $0.stop() } }
        reconcile()
    }
    func volumeChanged() {
        if effectsMuted { players.values.joined().forEach { $0.stop() } }
        reconcile()
    }

    private func reconcile() {
        guard state.canPlay, !muted else {
            beds.values.forEach { $0.pause() }
            if muted || state.scene == .off { deactivate() }
            return
        }
        prepare()
        guard !musicMuted, !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint else {
            beds.values.forEach { $0.pause() }
            return
        }
        switch state.scene {
        case .lobby: start(.lobby)
        case .battle: start(.battle)
        case .off: stopBed()
        case .result: beds.values.forEach { $0.pause() }
        }
    }

    func finish(won: Bool) {
        state.finish()
        if let current = bed, let player = beds[current] {
            player.setVolume(0, fadeDuration: 0.4)
        }
        play(won ? .win : .lose)
    }

    /// volume：0–1（离得远的小声一点）
    func play(_ effect: Effect, volume: Float = 1) {
        guard inMatch, state.canPlay, !effectsMuted, sessionOn, volume > 0.02 else { return }
        // Players are prewarmed at scene entry, never created/decoded by a hit.
        let critical = [Effect.hit, .win, .lose, .respawn].contains(effect)
        let active = players.values.reduce(0) { count, voices in count + voices.reduce(0) { $0 + ($1.isPlaying ? 1 : 0) } }
        guard active < (critical ? 12 : 8) else { return }
        // 同一种声音 30 毫秒内只响一次，免得一帧里好几下叠成噪音
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[effect], now - last < 0.03 { return }
        lastPlayed[effect] = now
        guard let voices = players[effect], let player = voices.first(where: { !$0.isPlaying }) else { return }
        player.currentTime = 0
        player.volume = min(volume, 1) * level(Self.effectsVolumeKey)
        player.play()
    }

    private var musicLevel: Float { 0.45 * level(Self.musicVolumeKey) }

    private func prepare() {
        let started = ProcessInfo.processInfo.systemUptime
        defer { ArenaDiagnostics.shared.record(.audio, seconds: ProcessInfo.processInfo.systemUptime - started) }

        if !sessionOn {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.ambient, mode: .default)
                try session.setActive(true)
                sessionOn = true
            } catch { return }
        }
        load()
    }

    private func deactivate() {
        guard sessionOn else { return }
        sessionOn = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func load() {
        guard players.isEmpty else { return }
        let theme = UserDefaults.standard.bool(forKey: "arena.themeAudio")
        for effect in Effect.allCases {
            let themeFile = effect == .win ? "arena_theme_win" : (effect == .lose ? "arena_theme_lose" : nil)
            let sample = theme ? themeFile.flatMap { Bundle.main.url(forResource: $0, withExtension: "m4a") } : nil
            guard let url = sample ?? Bundle.main.url(forResource: effect.file, withExtension: "wav") else { continue }
            players[effect] = (0..<effect.voices).compactMap { _ in
                let player = try? AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
                return player
            }
        }
        if let url = (theme ? Bundle.main.url(forResource: "arena_theme_lobby", withExtension: "m4a") : nil) ?? Bundle.main.url(forResource: "arena_lobby", withExtension: "wav") {
            beds[.lobby] = loop(url)
        }
        if let url = (theme ? Bundle.main.url(forResource: "arena_theme_battle", withExtension: "m4a") : nil) ?? Bundle.main.url(forResource: "arena_music", withExtension: "wav") {
            beds[.battle] = loop(url)
        }
    }

    private func loop(_ url: URL) -> AVAudioPlayer? {
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.prepareToPlay()
        return player
    }

    private func start(_ next: Bed) {
        guard !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint else { return }
        if bed == next, beds[next]?.isPlaying == true {
            beds[next]?.volume = musicLevel
            return
        }
        fadeTask?.cancel()
        if let current = bed, current != next {
            beds[current]?.setVolume(0, fadeDuration: 0.25)
            fadeTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self, self.bed != current else { return }
                self.beds[current]?.pause()
            }
        }
        let changed = bed != next
        bed = next
        guard let player = beds[next] else { return }
        if changed { player.currentTime = 0 }
        player.volume = 0
        player.play()
        player.setVolume(musicLevel, fadeDuration: 0.8)
    }

    private func stopBed() {
        fadeTask?.cancel()
        beds.values.forEach { $0.stop() }
        bed = nil
    }
}