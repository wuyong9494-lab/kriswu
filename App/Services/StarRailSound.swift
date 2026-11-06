import AVFoundation
import UIKit

@MainActor
final class StarRailSound: NSObject {
    static let shared = StarRailSound()
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate:Double(StarRailAudioPCM.sampleRate),channels:1)!
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [StarRailAudioPCM.Cue:AVAudioPCMBuffer] = [:]
    private var nextVoice = 0
    private var active = false
    private var enabled = true
    private var interrupted = false
    private(set) var running = false
    var loadedCueCount: Int { buffers.count }

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self,selector:#selector(interruption(_:)),name:AVAudioSession.interruptionNotification,object:nil)
        center.addObserver(self,selector:#selector(configurationChanged),name:.AVAudioEngineConfigurationChange,object:engine)
        center.addObserver(self,selector:#selector(routeChanged(_:)),name:AVAudioSession.routeChangeNotification,object:nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    func configure(active: Bool, enabled: Bool) {
        self.active = active; self.enabled = enabled
        if !active || !enabled { pause(); return }
        interrupted = false
        resume()
    }
    private func load() {
        guard players.isEmpty else { return }
        for cue in StarRailAudioPCM.Cue.allCases {
            let samples = StarRailAudioPCM.samples(cue)
            guard let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { continue }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { source in channel.update(from:source.baseAddress!,count:source.count) }
            buffers[cue] = buffer
        }
        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player); engine.connect(player,to:engine.mainMixerNode,format:format)
            player.volume = 0.65; players.append(player)
        }
        engine.prepare()
    }
    private func resume() {
        guard active, enabled, !interrupted, !running else { return }
        load()
        do {
            let session = AVAudioSession.sharedInstance()
            // Ambient honors Silent mode and naturally mixes with the user's music.
            // No global session deactivation on exit: other app modules own audio too.
            try session.setCategory(.ambient,mode:.default)
            try session.setActive(true)
            engine.prepare(); try engine.start()
            players.forEach { $0.play() }; running = true
        } catch { running = false }
    }
    private func pause() {
        players.forEach { $0.stop() }; engine.pause(); running = false; nextVoice = 0
    }
    func play(_ cue: StarRailAudioPCM.Cue) {
        guard active, enabled, !interrupted, running, engine.isRunning,
              let buffer = buffers[cue], !players.isEmpty else { return }
        let player = players[nextVoice]; nextVoice = (nextVoice + 1) % players.count
        player.scheduleBuffer(buffer,at:nil,options:.interrupts,completionHandler:nil)
    }
    @objc nonisolated private func interruption(_ note: Notification) {
        guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
        let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        Task { @MainActor [weak self] in
            guard let self else { return }
            if type == AVAudioSession.InterruptionType.began.rawValue { self.interrupted = true; self.pause() }
            else if AVAudioSession.InterruptionOptions(rawValue:options).contains(.shouldResume) {
                self.interrupted = false; self.resume()
            }
        }
    }
    @objc nonisolated private func configurationChanged() {
        Task { @MainActor [weak self] in self?.pause(); self?.resume() }
    }
    @objc nonisolated private func routeChanged(_ note: Notification) {
        let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pause()
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self.interrupted = true }
            else { self.resume() }
        }
    }
}
