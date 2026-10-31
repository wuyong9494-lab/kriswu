import AVFoundation
import Darwin
import Foundation

/// A bounded PCM bank for the selected source heroes. Preparation is explicit;
/// event dispatch never opens or decodes a media file. Source pitch is applied by
/// a varispeed unit on each voice, independently of the user's effects volume.
@MainActor
final class ArenaImportedEffectMixer {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var nodes: [AVAudioPlayerNode] = []
    private var rates: [AVAudioUnitVarispeed] = []
    private var buffers: [URL: AVAudioPCMBuffer] = [:]
    private var leases: [(cue: String, until: Double)] = []
    private var last: [String: Double] = [:]
    private(set) var running = false
    var notificationObject: AVAudioEngine { engine }

    func prepare(urls: Set<URL>) {
        pause()
        buffers = buffers.filter { urls.contains($0.key) }
        var bytes = buffers.values.reduce(0) { $0 + Int($1.frameLength) * 4 }
        for url in urls.sorted(by: { $0.path < $1.path }) where buffers[url] == nil {
            guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0,
                  Double(file.length) / file.processingFormat.sampleRate <= 30 else { continue }
            let estimatedBytes = Int(ceil(Double(file.length) * format.sampleRate / file.processingFormat.sampleRate)) * 4
            guard estimatedBytes > 0, bytes + estimatedBytes <= 128 * 1024 * 1024,
                  let buffer = try? ArenaEffectMixer.decode(url, format: format) else { continue }
            buffers[url] = buffer
            bytes += Int(buffer.frameLength) * 4
        }
        if nodes.isEmpty {
            for _ in 0..<12 {
                let node = AVAudioPlayerNode(), rate = AVAudioUnitVarispeed()
                engine.attach(node); engine.attach(rate)
                engine.connect(node, to: rate, format: format)
                engine.connect(rate, to: engine.mainMixerNode, format: format)
                nodes.append(node); rates.append(rate)
                leases.append(("", 0))
            }
        }
        engine.prepare()
    }

    func resume() {
        guard !nodes.isEmpty, !buffers.isEmpty else { return }
        if running && engine.isRunning { return }
        nodes.forEach { $0.stop() }
        leases = nodes.map { _ in ("", 0) }; last.removeAll()
        do {
            try engine.start()
            nodes.forEach { $0.play() }
            running = true
        } catch { running = false }
    }

    func pause() {
        nodes.forEach { $0.stop() }
        engine.pause()
        leases = nodes.map { _ in ("", 0) }; last.removeAll()
        running = false
    }

    func unload() { pause(); buffers.removeAll() }

    /// False means that this exact variant is unavailable, never a substituted VO.
    @discardableResult
    func play(url: URL, cue: String, volume: Float, pitch: Float, limit: Int,
              repeatInterval: Double, delay: Double) -> Bool {
        guard running, engine.isRunning, let buffer = buffers[url],
              volume.isFinite, pitch.isFinite, pitch > 0, delay.isFinite else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = last[cue], now - previous < max(0.03, repeatInterval) { return true }
        let active = leases.filter { $0.until > now }
        guard active.filter({ $0.cue == cue }).count < min(max(limit, 1), 12),
              let slot = leases.firstIndex(where: { $0.until <= now }) else { return true }
        let appliedPitch = min(max(pitch, 0.25), 4)
        let wait = min(max(delay, 0), 30)
        let duration = Double(buffer.frameLength) / format.sampleRate / Double(appliedPitch)
        leases[slot] = (cue, now + wait + duration + 0.02)
        last[cue] = now
        rates[slot].rate = appliedPitch
        nodes[slot].volume = min(max(volume, 0), 1)
        let at = wait > 0 ? AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: wait)) : nil
        nodes[slot].scheduleBuffer(buffer, at: at, options: .interrupts, completionHandler: nil)
        return true
    }
}
