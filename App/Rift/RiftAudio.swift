import AVFoundation

/// 战斗音效：全部在启动时用代码合成（挥刀风声、命中、金属格挡、完美格挡、变身、终极技、倒地、KO），
/// 背景音乐复用项目里原创的 arena_theme_battle。
@MainActor
final class RiftAudio {
    enum Sound: CaseIterable, Sendable {
        case swingLight, swingHeavy, hitLight, hitHeavy, hitUltimate, block, parry, guardBreak
        case transform, ultimate, land, ko, projectile, fight
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var next = 0
    private var music: AVAudioPlayer?
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private(set) var ready = false

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.9
    }

    /// 合成在后台线程完成，不卡进局
    func prepare() async {
        let fmt = format
        let made: [(Sound, [Float])] = await Task.detached(priority: .userInitiated) {
            Sound.allCases.map { ($0, RiftSynth.samples(for: $0)) }
        }.value
        for (s, data) in made {
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(data.count)) else { continue }
            buf.frameLength = AVAudioFrameCount(data.count)
            data.withUnsafeBufferPointer { src in
                buf.floatChannelData![0].update(from: src.baseAddress!, count: data.count)
            }
            buffers[s] = buf
        }
        do { try engine.start(); ready = true } catch { ready = false }
        if let url = Bundle.main.url(forResource: "arena_theme_battle", withExtension: "m4a"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = -1
            player.volume = 0.35
            player.play()
            music = player
        }
    }

    func play(_ s: Sound, volume: Float = 1, pitch: Float = 1) {
        guard ready, let buf = buffers[s] else { return }
        let p = players[next]
        next = (next + 1) % players.count
        p.stop()
        p.volume = volume
        p.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        p.play()
        _ = pitch
    }

    func stop() {
        music?.stop()
        engine.stop()
    }

    func setPaused(_ paused: Bool) {
        if paused { music?.pause() } else { music?.play() }
    }
}

enum RiftSynth {
    static let rate: Float = 44_100

    static func samples(for s: RiftAudio.Sound) -> [Float] {
        var rng = RiftRandom(seed: UInt64(RiftAudio.Sound.allCases.firstIndex(of: s) ?? 0) &+ 11)
        func noise() -> Float { Float(Int64(rng.next() % 20_000) - 10_000) / 10_000 }
        func make(_ seconds: Float, _ f: (Float, Float) -> Float) -> [Float] {
            let n = Int(seconds * rate)
            return (0..<n).map { i in
                let t = Float(i) / rate
                return f(t, t / seconds)
            }
        }
        var lp: Float = 0
        func lowpass(_ x: Float, _ a: Float) -> Float { lp += (x - lp) * a; return lp }
        switch s {
        case .swingLight, .swingHeavy:
            let heavy = s == .swingHeavy
            let len: Float = heavy ? 0.32 : 0.18
            return make(len) { t, p in
                let env = sin(p * .pi) * (heavy ? 0.7 : 0.5)
                let sweep = 0.05 + 0.5 * sin(p * .pi)
                return lowpass(noise(), sweep) * env * 2.2
            }
        case .hitLight, .hitHeavy, .hitUltimate:
            let power: Float = s == .hitLight ? 0.6 : (s == .hitHeavy ? 0.9 : 1)
            let len: Float = s == .hitLight ? 0.22 : (s == .hitHeavy ? 0.42 : 0.7)
            let thump: Float = s == .hitLight ? 140 : (s == .hitHeavy ? 85 : 60)
            return make(len) { t, p in
                let crack = noise() * exp(-t * 38) * 0.9
                let body = sin(2 * .pi * thump * t * (1 - p * 0.4)) * exp(-t * (s == .hitLight ? 18 : 9))
                let slice = lowpass(noise(), 0.35) * exp(-t * 14) * 0.6
                return (crack + body + slice) * power
            }
        case .block:
            return make(0.35) { t, _ in
                let partials: [Float] = [1200, 1870, 2650, 3420]
                let ring = partials.enumerated().reduce(Float(0)) { acc, e in acc + sin(2 * .pi * e.element * t) / Float(e.offset + 1) }
                return (ring * 0.35 * exp(-t * 16) + noise() * exp(-t * 60) * 0.5)
            }
        case .parry:
            return make(0.7) { t, _ in
                let partials: [Float] = [1560, 2340, 3120, 4680]
                let ring = partials.enumerated().reduce(Float(0)) { acc, e in acc + sin(2 * .pi * e.element * t) / Float(e.offset + 1) }
                return ring * 0.4 * exp(-t * 6) + noise() * exp(-t * 50) * 0.6
            }
        case .guardBreak:
            return make(0.5) { t, _ in
                let glass = sin(2 * .pi * 900 * t + sin(2 * .pi * 37 * t) * 4) * exp(-t * 10)
                return glass * 0.5 + noise() * exp(-t * 12) * 0.6
            }
        case .transform:
            return make(1.2) { t, p in
                let f = 80 + 500 * p * p
                let tone = sin(2 * .pi * f * t) * 0.4 + sin(2 * .pi * f * 1.5 * t) * 0.2
                let whoosh = lowpass(noise(), 0.05 + 0.4 * p) * 0.6
                return (tone + whoosh) * min(1, p * 4) * (1 - max(0, (p - 0.85) / 0.15))
            }
        case .ultimate:
            return make(1.4) { t, p in
                let boom = sin(2 * .pi * 45 * t) * exp(-t * 2.5)
                let shimmer = sin(2 * .pi * 660 * t) * sin(2 * .pi * 3 * t) * 0.2 * (1 - p)
                return (boom + shimmer + noise() * exp(-t * 5) * 0.3) * 0.9
            }
        case .land:
            return make(0.3) { t, _ in sin(2 * .pi * 55 * t) * exp(-t * 14) + lowpass(noise(), 0.08) * exp(-t * 10) }
        case .ko:
            return make(1.6) { t, _ in
                let gong = [110, 165, 233, 311].enumerated().reduce(Float(0)) { a, e in a + sin(2 * .pi * Float(e.element) * t) / Float(e.offset + 1) }
                return gong * 0.4 * exp(-t * 1.8) + noise() * exp(-t * 30) * 0.4
            }
        case .projectile:
            return make(0.45) { t, p in
                lowpass(noise(), 0.3) * sin(p * .pi) * 0.7 + sin(2 * .pi * (900 - 500 * p) * t) * 0.15 * (1 - p)
            }
        case .fight:
            return make(0.6) { t, _ in
                let drum = sin(2 * .pi * 70 * t) * exp(-t * 6)
                let drum2 = t > 0.18 ? sin(2 * .pi * 70 * (t - 0.18)) * exp(-(t - 0.18) * 6) : 0
                return (drum + drum2) * 0.9 + noise() * exp(-t * 25) * 0.3
            }
        }
    }
}
