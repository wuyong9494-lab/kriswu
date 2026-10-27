import AVFoundation
import Foundation

/// 乱斗的声音：开枪、劈砍、施法、爆炸、挨打、倒下、大招、捡星星、回血、闪现、输赢，和对战背景音乐。
/// 都是自己合成的（scripts/arena_sounds.py）。用「环境音」：和别的 App 的音乐混着放，手机静音时不响；
/// 正放着别的音乐时不放背景音乐。对局里能关（记在 arena.mute）
@MainActor
final class ArenaSound {
    static let shared = ArenaSound()
    nonisolated static let muteKey = "arena.mute"

    enum Effect: String, CaseIterable {
        case shot, slash, magic, boom, hit, knockout = "ko", power = "super", pickup, heal, respawn, blink, win, lose

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

    private var players: [Effect: [AVAudioPlayer]] = [:]
    private var lastPlayed: [Effect: TimeInterval] = [:]
    private var music: AVAudioPlayer?
    private var active = false

    var muted: Bool { UserDefaults.standard.bool(forKey: Self.muteKey) }

    /// 进一局
    func begin() {
        guard !muted else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default)
        try? session.setActive(true)
        active = true
        load()
        if !session.secondaryAudioShouldBeSilencedHint { startMusic() }
    }

    /// 离开这一局
    func end() {
        guard active else { return }
        active = false
        music?.stop()
        players.values.joined().forEach { $0.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 对局里点了静音 / 取消静音
    func muteChanged() {
        if muted { end() } else { begin() }
    }

    /// 打完了：停音乐，放输赢的声音
    func finish(won: Bool) {
        music?.setVolume(0, fadeDuration: 0.4)
        play(won ? .win : .lose)
    }

    /// volume：0–1（离得远的小声一点）
    func play(_ effect: Effect, volume: Float = 1) {
        guard active, volume > 0.02 else { return }
        // 同一种声音 30 毫秒内只响一次，免得一帧里好几下叠成噪音
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[effect], now - last < 0.03 { return }
        lastPlayed[effect] = now
        guard let voices = players[effect], let player = voices.first(where: { !$0.isPlaying }) ?? voices.first else { return }
        player.currentTime = 0
        player.volume = min(volume, 1)
        player.play()
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
        if let url = Bundle.main.url(forResource: "arena_music", withExtension: "wav") {
            music = try? AVAudioPlayer(contentsOf: url)
            music?.numberOfLoops = -1
            music?.prepareToPlay()
        }
    }

    private func startMusic() {
        guard let music else { return }
        music.currentTime = 0
        music.volume = 0
        music.play()
        music.setVolume(0.45, fadeDuration: 1)
    }
}
