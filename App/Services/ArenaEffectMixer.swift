import AVFoundation
import AudioToolbox
import Foundation

/// A persistent engine and 12 running nodes replace per-event AVAudioPlayer start/seek.
/// All state stays on MainActor; the render thread only reads scheduled immutable PCM.
@MainActor
final class ArenaEffectMixer {
    private let engine: AVAudioEngine
    var notificationObject: AVAudioEngine { engine }
    init(engine: AVAudioEngine = AVAudioEngine()) { self.engine = engine }
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var nodes: [AVAudioPlayerNode] = []
    private var buffers: [ArenaSound.Effect: AVAudioPCMBuffer] = [:]
    private var budget = ArenaVoiceBudget()
    private(set) var running = false
    private(set) var loadedFiles: [ArenaSound.Effect: String] = [:]
    var loadedCount: Int { buffers.count }

    func load(theme: Bool) {
        guard nodes.isEmpty else { return }
        for effect in ArenaSound.Effect.allCases {
            for resource in effect.resources(theme: theme) {
                guard let url = Bundle.main.url(forResource: resource.name, withExtension: resource.ext),
                      let buffer = try? Self.decode(url, format: format) else { continue }
                buffers[effect] = buffer
                loadedFiles[effect] = url.lastPathComponent
                break
            }
        }
        for _ in 0..<12 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            nodes.append(node)
        }
        engine.prepare()
    }

    /// File IO and conversion happen once at lobby entry, never on a shot/hit.
    static func decode(_ url: URL, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        try ArenaAudioDecoder.decode(url, format: format)
    }

    func resume() {
        guard !nodes.isEmpty else { return }
        if running && engine.isRunning { return }
        // Configuration changes can stop the engine. Discard stale sounds before recovery.
        nodes.forEach { $0.stop() }
        budget.reset()
        do {
            engine.prepare()
            try engine.start()
            nodes.forEach { $0.play() }
            running = true
        } catch { running = false }
    }

    func pause() {
        guard running else { return }
        nodes.forEach { $0.stop() }
        engine.pause()
        running = false
        budget.reset()
    }

    func unload() {
        pause()
        engine.stop()
        nodes.forEach { engine.detach($0) }
        nodes.removeAll()
        buffers.removeAll()
        loadedFiles.removeAll()
        budget.reset()
    }

    func play(_ effect: ArenaSound.Effect, volume: Float) {
        // Never start/reconfigure the engine in a combat callback.
        guard running, engine.isRunning, let buffer = buffers[effect] else { return }
        let critical = effect == .hit || effect == .win || effect == .lose || effect == .respawn
        guard let slot = budget.reserve(effect: effect.rawValue, limit: effect.voices, critical: critical,
            duration: Double(buffer.frameLength) / format.sampleRate, now: ProcessInfo.processInfo.systemUptime) else { return }
        let node = nodes[slot]
        node.volume = volume
        // Interrupts prevents a delayed render cycle from building a stale-sound queue.
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }
}
