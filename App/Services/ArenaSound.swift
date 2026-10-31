import AVFoundation
import Foundation
import UIKit

/// 乱斗的声音。效果和两首循环音乐各只创建一次：大厅一首，进对局换成战斗那首，出来再换回去。
/// 用「环境音」：和别的 App 的音乐混着放，手机静音时不响；正放着别的音乐时不放背景音乐。
/// 静音记在 arena.mute，音量记在 arena.volume（0–1）
@MainActor
final class ArenaSound: NSObject, AVAudioPlayerDelegate {
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
    private let importedEffects = ArenaImportedEffectMixer()
    private var importedCues: [String: [ArenaImportedAudioAssets.Cue]] = [:]
    private var sourceSequence: [String: Int] = [:]
    private var preparedSourceHeroes: Set<String> = []
    private static let sourceEvents = ["weapon.attack", "weapon.use", "ultimate.attack", "ultimate.use",
        "damage", "death", "voice.start", "voice.attack", "voice.ultimate", "voice.takeDamage", "voice.death", "voice.kill", "voice.lead", "voice.unlock"]
    private var assetsLoaded = false
    private var beds: [Bed: AVAudioPlayer] = [:]
    private var bedGains: [Bed: Float] = [:]
    private var resultMusic: [Bool: AVAudioPlayer] = [:]
    private var resultGains: [Bool: Float] = [:]
    private var resultWon: Bool?
    private var resultCompleted = false
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
        center.addObserver(self, selector: #selector(engineConfigurationChanged), name: .AVAudioEngineConfigurationChange, object: importedEffects.notificationObject)
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
            self.importedEffects.pause()
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
        resultMusic.values.forEach { $0.pause() }
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

    func enterLobby() { stopResultMusic(); state.enterLobby(); reconcile() }
    func leaveLobby() { state.leaveLobby(); reconcile() }
    func begin(owner: ObjectIdentifier? = nil) {
        stopResultMusic()
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
        stopResultMusic()
        resultMusic.removeAll()
        resultGains.removeAll()
        bedGains.removeAll()
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
            resultMusic.values.forEach { $0.pause() }
            if muted || state.scene == .off { deactivate() }
            return
        }
        prepare()
        guard !musicMuted, !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint else {
            beds.values.forEach { $0.pause() }
            resultMusic.values.forEach { $0.pause() }
            return
        }
        switch state.scene {
        case .lobby: start(.lobby)
        case .battle: start(.battle)
        case .off: stopBed()
        case .result:
            beds.values.forEach { $0.pause() }
            if !resultCompleted, let resultWon, let player = resultMusic[resultWon] {
                player.volume = level(Self.musicVolumeKey) * (resultGains[resultWon] ?? 1)
                if player.currentTime < player.duration && !player.isPlaying { player.play() }
            }
        }
    }

    func finish(won: Bool) {
        state.finish()
        if let current = bed, let player = beds[current] {
            player.setVolume(0, fadeDuration: 0.4)
        }
        if let player = resultMusic[won] {
            stopResultMusic()
            resultWon = won
            player.currentTime = 0
            if state.canPlay, !musicMuted, sessionOn,
               !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint {
                player.volume = level(Self.musicVolumeKey) * (resultGains[won] ?? 1)
                player.play()
            }
            return
        }
        play(won ? .win : .lose)
    }

    private func stopEffects() {
        effects.pause()
        importedEffects.pause()
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
        let sourceEvent = effect == .uiBack ? "menu.back" : "menu.click"
        if playSource(event: sourceEvent, volume: 0.55, menu: true) { return }
        effects.play(effect, volume: 0.55 * level(Self.effectsVolumeKey))
    }

    /// Called while entering a lobby/match, before its first frame. Only this
    /// roster and menu clips enter the PCM bank; thousands of unused VO stay on disk.
    func prepareSourceAudio(heroIDs: Set<String>) {
        preparedSourceHeroes = heroIDs
        importedCues.removeAll(); sourceSequence.removeAll()
        guard ArenaResourcePackStore.shared.enabled else { importedEffects.unload(); return }
        let resolver = ArenaImportedAudioAssets.shared
        for event in ["menu.click", "menu.back", "menu.dismiss"] {
            importedCues["|" + event] = resolver.cues(event: event)
        }
        for hero in heroIDs {
            for event in Self.sourceEvents {
                importedCues[hero + "|" + event] = resolver.cues(event: event, heroID: hero)
            }
            if let profile = ArenaImportedCombatAssets.shared.hero(id: hero) {
                func register(_ areas: [ArenaSourceAreaEffect], role: String, depth: Int = 0) {
                    guard depth < 5 else { return }
                    for area in areas {
                        let event = role + ".area.start"
                        importedCues[hero + "|" + event + "|" + area.id] =
                            resolver.cues(event: event, heroID: hero, areaEffectID: area.id)
                        if let explosion = area.bulletExplosion {
                            register(explosion.projectile.areaEffects, role: role, depth: depth + 1)
                        }
                    }
                }
                for skill in [profile.weapon, profile.ultimate].compactMap({ $0 }) {
                    register(skill.areaEffects + skill.projectiles.flatMap(\.areaEffects) + (skill.charge?.endAreas ?? []),
                             role: skill.role == .ultimate ? "ultimate" : "weapon")
                }
            }
        }
        let urls = Set(importedCues.values.flatMap { $0 }.flatMap { $0.variants.map(\.url) })
        importedEffects.prepare(urls: urls)
        if state.canPlay, !effectsMuted, sessionOn { importedEffects.resume() }
    }

    @discardableResult
    func playSource(event: String, heroID: String? = nil, areaEffectID: String? = nil,
                    volume: Float = 1, menu: Bool = false) -> Bool {
        let key = (heroID ?? "") + "|" + event + (areaEffectID.map { "|" + $0 } ?? "")
        guard (menu || inMatch), state.canPlay, !effectsMuted, sessionOn,
              ArenaResourcePackStore.shared.enabled,
              ArenaDiagnostics.shared.variant != .noEffectAudio,
              let cues = importedCues[key], !cues.isEmpty else { return false }
        var available = false
        for cue in cues {
            let variant: ArenaImportedAudioAssets.Variant?
            if cue.sequence == true {
                let index = sourceSequence[cue.id, default: 0]
                // Preserve missing source positions. Never relabel another voice
                // as the absent sequence entry.
                variant = cue.variants.first { $0.index == index }
                sourceSequence[cue.id] = (index + 1) % max(cue.sourceVariantCount, 1)
            } else { variant = cue.variants.randomElement() }
            guard let variant, variant.loop != true else { continue }
            func value(_ low: Double?, _ high: Double?, fallback: Double) -> Double {
                let a = low ?? high ?? fallback, b = high ?? low ?? fallback
                guard a.isFinite, b.isFinite else { return fallback }
                return Double.random(in: min(a, b)...max(a, b))
            }
            let gain = Float(value(variant.minVolumePercent, variant.maxVolumePercent, fallback: 100) / 100)
            let pitch = Float(value(variant.minPitchPercent, variant.maxPitchPercent, fallback: 100) / 100)
            let delay = value(variant.startDelayMinMs, variant.startDelayMaxMs, fallback: 0) / 1000
            let played = importedEffects.play(url: variant.url, cue: cue.id,
                volume: volume * gain * level(Self.effectsVolumeKey), pitch: pitch,
                limit: variant.maximumByType.flatMap { $0 > 0 ? $0 : nil } ?? 4,
                repeatInterval: max(0, variant.maxRepeatMs ?? 0) / 1000, delay: delay)
            available = available || played
        }
        return available
    }

    private func musicLevel(_ bed: Bed) -> Float { (bedGains[bed] ?? 0.45) * level(Self.musicVolumeKey) }

    private func stopResultMusic() {
        resultMusic.values.forEach { $0.stop() }
        resultWon = nil
        resultCompleted = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Delegate notifications are delivered on the player's owning run loop.
        // Carry only identity across the actor boundary, not AVAudioPlayer itself.
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let won = self.resultWon,
                  let current = self.resultMusic[won], ObjectIdentifier(current) == identity else { return }
            self.resultCompleted = true
        }
    }

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
        if !effectsMuted { effects.resume(); importedEffects.resume() }
    }

    private func deactivate() {
        guard sessionOn else { return }
        sessionOn = false
        effects.pause()
        importedEffects.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func load() {
        guard !assetsLoaded else { return }
        assetsLoaded = true
        let theme = Self.prefersTheme()
        effects.load(theme: theme)
        prepareSourceAudio(heroIDs: preparedSourceHeroes)
        for (role, bed, legacy) in [("lobby", Bed.lobby, "arena_lobby"),
                                    ("battle", Bed.battle, "arena_music")] {
            if let source = ArenaResourcePackStore.shared.music(for: role),
               let player = loop(source.url, repeats: source.track.loop ?? true) {
                beds[bed] = player
                bedGains[bed] = Float(source.track.volumePercent ?? 100) / 100
                loadedMusicFiles[role] = source.url.lastPathComponent
                continue
            }
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
        for (won, role) in [(true, "win"), (false, "lose")] {
            if let source = ArenaResourcePackStore.shared.music(for: role),
               let player = loop(source.url, repeats: false) {
                resultMusic[won] = player
                player.delegate = self
                resultGains[won] = Float(source.track.volumePercent ?? 100) / 100
                loadedMusicFiles[role] = source.url.lastPathComponent
            }
        }
    }

    private func loop(_ url: URL, repeats: Bool = true) -> AVAudioPlayer? {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = repeats ? -1 : 0
        guard player.prepareToPlay() else { return nil }
        return player
    }

    private func start(_ next: Bed) {
        guard !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint else { return }
        if bed == next, beds[next]?.isPlaying == true {
            beds[next]?.volume = musicLevel(next)
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
        player.setVolume(musicLevel(next), fadeDuration: 0.8)
    }

    private func stopBed() {
        fadeTask?.cancel()
        beds.values.forEach { $0.stop() }
        bed = nil
    }
}
