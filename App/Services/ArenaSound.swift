import AVFoundation
import Foundation

/// 乱斗的声音。效果和两首循环音乐各只创建一次：大厅一首，进对局换成战斗那首，出来再换回去。
/// 用「环境音」：和别的 App 的音乐混着放，手机静音时不响；正放着别的音乐时不放背景音乐。
/// 静音记在 arena.mute，音量记在 arena.volume（0–1）
@MainActor
final class ArenaSound {
    static let shared = ArenaSound()
    nonisolated static let muteKey = "arena.mute"
    nonisolated static let volumeKey = "arena.volume"

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
    /// 人还在大厅（对局结束要把大厅的音乐放回来）
    private var lobbyOpen = false
    /// 人还在对局里（静音再打开要放回战斗音乐，不是大厅）
    private var inMatch = false

    var muted: Bool { UserDefaults.standard.bool(forKey: Self.muteKey) }

    var volume: Float {
        let stored = UserDefaults.standard.object(forKey: Self.volumeKey) as? Double
        return Float(min(max(stored ?? 0.7, 0), 1))
    }

    /// 打开大厅
    func enterLobby() {
        lobbyOpen = true
        guard !muted, !inMatch else { return }
        prepare()
        start(.lobby)
    }

    /// 离开勇者乱斗
    func leaveLobby() {
        lobbyOpen = false
        guard !inMatch else { return }
        stopBed()
        if !inMatch { deactivate() }
    }

    /// 进一局
    func begin() {
        inMatch = true
        guard !muted else { return }
        prepare()
        start(.battle)
    }

    /// 离开这一局，大厅还开着就放回大厅的音乐
    func end() {
        inMatch = false
        players.values.joined().forEach { $0.stop() }
        guard lobbyOpen, !muted else {
            stopBed()
            deactivate()
            return
        }
        start(.lobby)
    }

    /// 点了静音 / 取消静音。battle：人在对局里
    func muteChanged(battle: Bool) {
        if muted {
            inMatch = battle
            players.values.joined().forEach { $0.stop() }
            stopBed()
            deactivate()
        } else if battle {
            begin()
        } else {
            enterLobby()
        }
    }

    func volumeChanged() {
        let level = musicLevel
        if let current = bed, let player = beds[current], player.isPlaying {
            player.volume = level
        }
    }

    /// 打完了：停音乐，放输赢的声音
    func finish(won: Bool) {
        if let current = bed, let player = beds[current] {
            player.setVolume(0, fadeDuration: 0.4)
        }
        play(won ? .win : .lose)
    }

    /// volume：0–1（离得远的小声一点）
    func play(_ effect: Effect, volume: Float = 1) {
        guard inMatch, !muted, volume > 0.02 else { return }
        prepare()
        // 同一种声音 30 毫秒内只响一次，免得一帧里好几下叠成噪音
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[effect], now - last < 0.03 { return }
        lastPlayed[effect] = now
        guard let voices = players[effect], let player = voices.first(where: { !$0.isPlaying }) else { return }
        player.currentTime = 0
        player.volume = min(volume, 1) * self.volume
        player.play()
    }

    private var musicLevel: Float { 0.45 * volume }

    private func prepare() {
        let started = ProcessInfo.processInfo.systemUptime
        defer { ArenaDiagnostics.shared.record(.audio, seconds: ProcessInfo.processInfo.systemUptime - started) }

        if !sessionOn {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, mode: .default)
            try? session.setActive(true)
            sessionOn = true
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
        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.file, withExtension: "wav") else { continue }
            players[effect] = (0..<effect.voices).compactMap { _ in
                let player = try? AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
                return player
            }
        }
        if let url = Bundle.main.url(forResource: "arena_lobby", withExtension: "wav") {
            beds[.lobby] = loop(url)
        }
        if let url = Bundle.main.url(forResource: "arena_music", withExtension: "wav") {
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
        if let current = bed, current != next {
            beds[current]?.stop()
        }
        bed = next
        guard let player = beds[next] else { return }
        player.currentTime = 0
        player.volume = 0
        player.play()
        player.setVolume(musicLevel, fadeDuration: 0.8)
    }

    private func stopBed() {
        beds.values.forEach { $0.stop() }
        bed = nil
    }
}