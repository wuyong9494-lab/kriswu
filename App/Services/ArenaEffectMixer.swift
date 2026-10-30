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
    var loadedCount: Int { buffers.count }

    func load(theme: Bool) {
        guard nodes.isEmpty else { return }
        for effect in ArenaSound.Effect.allCases {
            let themeFile = effect == .win ? "arena_theme_win" : (effect == .lose ? "arena_theme_lose" : nil)
            let sample = theme && !effect.file.hasPrefix("vendor_") ? themeFile.flatMap { Bundle.main.url(forResource: $0, withExtension: "m4a") } : nil
            guard let url = sample ?? Bundle.main.url(forResource: effect.file, withExtension: "wav"),
                  let buffer = try? Self.decode(url, format: format) else { continue }
            buffers[effect] = buffer
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
        // Extended Audio File performs synchronous decode/resampling into caller-owned
        // PCM. No @Sendable input callback captures a mutable AVAudioPCMBuffer.
        var handle: ExtAudioFileRef?
        try check(ExtAudioFileOpenURL(url as CFURL, &handle))
        guard let file = handle else { throw NSError(domain: "ArenaPCM", code: 1) }
        defer { ExtAudioFileDispose(file) }
        var sourceFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &formatSize, &sourceFormat))
        var frames: Int64 = 0
        var frameSize = UInt32(MemoryLayout<Int64>.size)
        try check(ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &frameSize, &frames))
        guard sourceFormat.mSampleRate > 0, frames > 0 else { throw NSError(domain: "ArenaPCM", code: 2) }
        var clientFormat = format.streamDescription.pointee
        try check(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                         UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientFormat))
        let capacity = AVAudioFrameCount(ceil(Double(frames) * format.sampleRate / sourceFormat.mSampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw NSError(domain: "ArenaPCM", code: 3)
        }
        // AVAudioPCMBuffer starts with frameLength=0, so its AudioBufferList
        // advertises zero writable bytes until frameLength is set.
        output.frameLength = capacity
        var decoded = capacity
        try check(ExtAudioFileRead(file, &decoded, output.mutableAudioBufferList))
        guard decoded > 0 else { throw NSError(domain: "ArenaPCM", code: 4) }
        output.frameLength = decoded
        return output
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
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
