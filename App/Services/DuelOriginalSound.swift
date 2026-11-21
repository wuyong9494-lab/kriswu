import AVFoundation
import Foundation

/// 100% original procedural martial combat SFX player for Shadow Arena mode.
/// Pre-synthesizes every `DuelOriginalAudioPCM.Cue` buffer once and plays them through a
/// bounded 8-voice `AVAudioEngine` pool with zero disk I/O during combat frames.
@MainActor
final class DuelOriginalSound: NSObject {
    static let shared = DuelOriginalSound()

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(
        standardFormatWithSampleRate: Double(DuelOriginalAudioPCM.sampleRate),
        channels: 1
    )!
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [DuelOriginalAudioPCM.Cue: AVAudioPCMBuffer] = [:]
    private var nextVoice = 0
    private var active = false
    private var interrupted = false
    private(set) var running = false

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(interruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(configurationChanged),
                           name: .AVAudioEngineConfigurationChange, object: engine)
        center.addObserver(self, selector: #selector(routeChanged(_:)),
                           name: AVAudioSession.routeChangeNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func setActive(_ isActive: Bool) {
        active = isActive
        if !isActive {
            pause()
            return
        }
        interrupted = false
        resume()
    }

    private func loadIfNeeded() {
        guard players.isEmpty else { return }
        for cue in DuelOriginalAudioPCM.Cue.allCases {
            let samples = DuelOriginalAudioPCM.samples(for: cue)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { continue }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                channel.update(from: src.baseAddress!, count: src.count)
            }
            buffers[cue] = buffer
        }
        for _ in 0..<8 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            player.volume = 0.72
            players.append(player)
        }
        engine.prepare()
    }

    private func resume() {
        guard active, !interrupted, !running else { return }
        loadIfNeeded()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            engine.prepare()
            try engine.start()
            players.forEach { $0.play() }
            running = true
        } catch {
            running = false
        }
    }

    private func pause() {
        players.forEach { $0.stop() }
        engine.pause()
        running = false
        nextVoice = 0
    }

    func play(_ cue: DuelOriginalAudioPCM.Cue, volume: Float = 0.72) {
        guard active, !interrupted, running, engine.isRunning,
              let buffer = buffers[cue], !players.isEmpty else { return }
        let player = players[nextVoice]
        nextVoice = (nextVoice + 1) % players.count
        player.volume = min(1.0, max(0.0, volume))
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    @objc nonisolated private func interruption(_ note: Notification) {
        guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
        let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        Task { @MainActor [weak self] in
            guard let self else { return }
            if type == AVAudioSession.InterruptionType.began.rawValue {
                self.interrupted = true
                self.pause()
            } else if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                self.interrupted = false
                self.resume()
            }
        }
    }

    @objc nonisolated private func configurationChanged() {
        Task { @MainActor [weak self] in
            self?.pause()
            self?.resume()
        }
    }

    @objc nonisolated private func routeChanged(_ note: Notification) {
        let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pause()
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                self.interrupted = true
            } else {
                self.resume()
            }
        }
    }
}
