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
    nonisolated static let themeKey = "arena.themeAudio"

    /// New installs use the completed score; an explicit earlier choice is retained.
    nonisolated static func prefersTheme(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: themeKey) as? Bool ?? true
    }

    enum Effect: String, CaseIterable {
        case shot, slash, magic, boom, hit, knockout = "ko", power = "super", pickup, heal, respawn, blink, win, lose, gadget, hyper
        case uiClick = "ui_click", uiToggle = "ui_toggle", uiSelect = "ui_select"
        case uiConfirm = "ui_confirm", uiBack = "ui_back"
        case uiError = "ui_error", uiUpgrade = "ui_upgrade", uiReward = "ui_reward"
        case stepGrass = "step_grass", stepStone = "step_stone", stepWood = "step_wood"
        case pageTurn = "page_turn"

        struct Resource: Equatable {
            let name: String
            let ext: String
        }

        var file: String {
            switch self {
            case .slash, .hit, .knockout, .pickup, .blink, .gadget, .win, .lose,
                 .uiClick, .uiToggle, .uiSelect, .uiConfirm, .uiBack,
                 .uiError, .uiUpgrade, .uiReward, .stepGrass, .stepStone, .stepWood:
                return "vendor_" + rawValue
            case .pageTurn: return "vendor_magic"
            case .shot, .magic, .boom, .power, .heal, .respawn, .hyper:
                return "arena_" + rawValue
            }
        }

        /// The selected sound, then its existing fallback. Both missing and undecodable
        /// files fall back during preparation, never during a combat callback.
        func resources(theme: Bool) -> [Resource] {
            var result: [Resource] = []
            if theme && (self == .win || self == .lose) {
                result.append(Resource(name: "arena_theme_" + rawValue, ext: "m4a"))
            }
            result.append(Resource(name: file, ext: "wav"))
            switch self {
            case .slash, .hit, .knockout, .pickup, .blink, .gadget, .win, .lose:
                result.append(Resource(name: "arena_" + rawValue, ext: "wav"))
            case .pageTurn:
                result.append(Resource(name: "arena_magic", ext: "wav"))
            default: break
            }
            return result
        }
        /// 同时能响几个（电脑一起开火时叠得起来）
        var voices: Int {
            switch self {
            case .shot, .slash, .magic, .pageTurn, .hit: return 5
            case .boom: return 3
            default: return 2
            }
        }
    }

    private enum Bed { case lobby, battle }

    private let effects = ArenaEffectMixer()
    private var assetsLoaded = false
    private var beds: [Bed: AVAudioPlayer] = [:]
    private(set) var loadedMusicFiles: [String: String] = [:]
    private var bed: Bed?
    private var sessionOn = false
    private(set) var state = ArenaAudioState()
    private var fadeTask: Task<Void, Never>?
    private var inMatch: Bool { state.inMatch }
    private var matchOwner: ObjectIdentifier?

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(engineConfigurationChanged), name: .AVAudioEngineConfigurationChange, object: effects.notificationObject)
        center.addObserver(self, selector: #selector(suspendApp), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(resumeApp), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(interruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(silenceHintChanged), name: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil)
    }

    @objc nonisolated private func engineConfigurationChanged() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.effects.pause()
            self.reconcile()
        }
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
            } else { self.effects.pause(); self.reconcile() }
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
        stopEffects()
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
            stopEffects()
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
        stopEffects()
        reconcile()
    }

    func muteChanged(battle: Bool) {
        if muted { stopEffects() }
        reconcile()
    }
    func volumeChanged() {
        if effectsMuted { stopEffects() }
        reconcile()
    }

    /// Replace cached music without changing lobby/battle/pause ownership.
    func themeChanged() {
        fadeTask?.cancel()
        beds.values.forEach { $0.stop() }
        stopEffects()
        beds.removeAll()
        effects.unload()
        assetsLoaded = false
        loadedMusicFiles.removeAll()
        bed = nil
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

    private func stopEffects() {
        effects.pause()
    }

    /// volume：0–1（离得远的小声一点）
    func play(_ effect: Effect, volume: Float = 1) {
        guard inMatch, state.canPlay, !effectsMuted, sessionOn, volume > 0.02,
              ArenaDiagnostics.shared.variant != .noEffectAudio else { return }
        // Effect dispatch includes audio. Measure the entire voice-selection/seek/play
        // path, not only prepare(), before attributing event stalls to rendering.
        // This now schedules predecoded PCM; it never seeks/starts an AVAudioPlayer.
        let started = ProcessInfo.processInfo.systemUptime
        defer { ArenaDiagnostics.shared.record(.audio, seconds: ProcessInfo.processInfo.systemUptime - started) }
        effects.play(effect, volume: min(volume, 1) * level(Self.effectsVolumeKey))
    }

    /// Menus share the same bounded PCM mixer and the user's effects/mute settings.
    func menu(_ effect: Effect) {
        guard [.uiClick, .uiToggle, .uiSelect, .uiConfirm, .uiBack,
               .uiError, .uiUpgrade, .uiReward].contains(effect),
              state.canPlay, !effectsMuted else { return }
        prepare()
        guard sessionOn else { return }
        effects.play(effect, volume: 0.55 * level(Self.effectsVolumeKey))
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
        if !effectsMuted { effects.resume() }
    }

    private func deactivate() {
        guard sessionOn else { return }
        sessionOn = false
        effects.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func load() {
        guard !assetsLoaded else { return }
        assetsLoaded = true
        let theme = Self.prefersTheme()
        effects.load(theme: theme)
        for (role, bed, legacy) in [("lobby", Bed.lobby, "arena_lobby"),
                                    ("battle", Bed.battle, "arena_music")] {
            let candidates = (theme ? [Effect.Resource(name: "arena_theme_" + role, ext: "m4a")] : [])
                + [Effect.Resource(name: legacy, ext: "wav")]
            for candidate in candidates {
                guard let url = Bundle.main.url(forResource: candidate.name, withExtension: candidate.ext),
                      let player = loop(url) else { continue }
                beds[bed] = player
                loadedMusicFiles[role] = url.lastPathComponent
                break
            }
        }
    }

    private func loop(_ url: URL) -> AVAudioPlayer? {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = -1
        guard player.prepareToPlay() else { return nil }
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
