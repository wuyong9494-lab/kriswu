import AVFoundation
import Foundation

/// A foreground, caller-owned duplex engine. Wire format is 24 kHz mono PCM16 little-endian.
@MainActor
final class AILiveAudio {
    enum Issue: LocalizedError {
        case unavailable, invalidPlayback, playbackBacklog

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "无法开启双向语音。请检查麦克风权限及当前音频设备。"
            case .invalidPlayback:
                return "服务商返回了无法播放的语音数据。"
            case .playbackBacklog:
                return "语音播放积压，已停止。请重新连接。"
            }
        }
    }

    private static let wireRate = 24_000.0
    private static let maxQueuedFrames: Int64 = 24_000 * 8
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var inputWithTap: AVAudioInputNode?
    private var playFormat: AVAudioFormat?
    private var previousCategory: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    private var epoch = UUID()
    private var pendingFrames: Int64 = 0
    private var scheduledFrames: Int64 = 0
    private var confirmedFrames: Int64 = 0
    private var segmentStartFrames: Int64 = 0
    private var lastReportedFrames: Int64 = 0

    static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { @Sendable in continuation.resume(returning: $0) }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { @Sendable in
                    continuation.resume(returning: $0)
                }
            }
        }
    }

    func start(onCapture: @escaping @Sendable (Data) -> Void) throws {
        // Each connection has its own converter and audio graph. No retained old mic tap.
        stop()
        let session = AVAudioSession.sharedInstance()
        let permitted: Bool
        if #available(iOS 17.0, *) {
            permitted = AVAudioApplication.shared.recordPermission == .granted
        } else {
            permitted = session.recordPermission == .granted
        }
        guard permitted else { throw Issue.unavailable }
        previousCategory = (session.category, session.mode, session.categoryOptions)
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
            try session.setActive(true)
            let engine = AVAudioEngine()
            self.engine = engine
            let input = engine.inputNode
            // Enable system Voice Processing I/O before choosing formats. Never fall back
            // silently to open-speaker full duplex without the device's echo cancellation.
            _ = engine.outputNode
            try input.setVoiceProcessingEnabled(true)
            guard input.isVoiceProcessingEnabled else { throw Issue.unavailable }
            let hardwareFormat = input.outputFormat(forBus: 0)
            guard hardwareFormat.sampleRate.isFinite, hardwareFormat.sampleRate > 0,
                  hardwareFormat.channelCount > 0,
                  let wireInput = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.wireRate,
                                               channels: 1, interleaved: false),
                  let wirePlay = AVAudioFormat(standardFormatWithSampleRate: Self.wireRate, channels: 1)
            else { throw Issue.unavailable }
            let capture = try CaptureConverter(from: hardwareFormat, to: wireInput, deliver: onCapture)
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: wirePlay)
            self.player = player
            self.playFormat = wirePlay
            let tap: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
                capture.consume(buffer)
            }
            input.installTap(onBus: 0, bufferSize: 960, format: hardwareFormat, block: tap)
            inputWithTap = input
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            throw Issue.unavailable
        }
    }

    func ownsEngine(_ candidate: Any?) -> Bool {
        guard let candidate = candidate as? AVAudioEngine, let engine else { return false }
        return candidate === engine
    }

    func play(_ pcm16: Data) throws {
        guard let player, let playFormat, engine?.isRunning == true else { throw Issue.unavailable }
        guard !pcm16.isEmpty, pcm16.count.isMultiple(of: 2) else { throw Issue.invalidPlayback }
        let frames = Int64(pcm16.count / 2)
        guard frames <= Self.maxQueuedFrames - pendingFrames else { throw Issue.playbackBacklog }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(frames)),
              let samples = buffer.floatChannelData?[0]
        else { throw Issue.invalidPlayback }
        buffer.frameLength = AVAudioFrameCount(frames)
        pcm16.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for frame in 0..<Int(frames) {
                let low = UInt16(bytes[2 * frame])
                let high = UInt16(bytes[2 * frame + 1])
                samples[frame] = Float(Int16(bitPattern: low | (high << 8))) / 32768
            }
        }
        if pendingFrames == 0 {
            // Start a fresh node clock after starvation so elapsed silence is never
            // counted toward the model's audio truncation point.
            player.stop()
            segmentStartFrames = scheduledFrames
        }
        let epoch = self.epoch
        pendingFrames += frames
        scheduledFrames += frames
        let endOfBuffer = scheduledFrames
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.epoch == epoch else { return }
                self.pendingFrames = max(0, self.pendingFrames - frames)
                self.confirmedFrames = max(self.confirmedFrames, endOfBuffer)
            }
        }
        if !player.isPlaying { player.play() }
    }

    /// Approximate model audio that has reached the output, not merely been queued.
    /// Call before resetting to report the truncation position.
    func playedMilliseconds() -> Int {
        var estimate = confirmedFrames
        if pendingFrames > 0, let player, let renderTime = player.lastRenderTime,
           let time = player.playerTime(forNodeTime: renderTime),
           time.sampleRate.isFinite, time.sampleRate > 0, time.sampleTime >= 0 {
            let session = AVAudioSession.sharedInstance()
            let latency = max(0, session.outputLatency + session.ioBufferDuration)
            let seconds = max(0, Double(time.sampleTime) / time.sampleRate - latency)
            let segmentBound = max(0, scheduledFrames - segmentStartFrames)
            estimate = max(estimate,
                           segmentStartFrames + Int64(min(Double(segmentBound), seconds * Self.wireRate)))
        }
        lastReportedFrames = max(lastReportedFrames, min(estimate, scheduledFrames))
        // Divide first to avoid multiplication overflow if a long session reconnects late.
        return Int(lastReportedFrames / 24)
    }

    func resetPlayback() {
        epoch = UUID()
        player?.stop()
        pendingFrames = 0
        scheduledFrames = 0
        confirmedFrames = 0
        segmentStartFrames = 0
        lastReportedFrames = 0
    }

    func stop() {
        resetPlayback()
        inputWithTap?.removeTap(onBus: 0)
        inputWithTap = nil
        engine?.stop()
        engine = nil
        player = nil
        playFormat = nil
        if let saved = previousCategory {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(saved.0, mode: saved.1, options: saved.2)
            previousCategory = nil
        }
    }
}

/// Owned only by the serial AVAudioEngine tap for its lifetime. Its converter
/// is never touched by playback or teardown code on the main actor.
private final class CaptureConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let format: AVAudioFormat
    private let ratio: Double
    private let deliver: @Sendable (Data) -> Void

    init(from: AVAudioFormat, to: AVAudioFormat, deliver: @escaping @Sendable (Data) -> Void) throws {
        guard let converter = AVAudioConverter(from: from, to: to) else { throw AILiveAudio.Issue.unavailable }
        self.converter = converter
        self.format = to
        self.ratio = to.sampleRate / from.sampleRate
        self.deliver = deliver
    }

    func consume(_ input: AVAudioPCMBuffer) {
        guard input.frameLength > 0, input.frameLength <= 8192 else { return }
        let capacity = ceil(Double(input.frameLength) * ratio) + 128
        guard capacity.isFinite, capacity > 0, capacity <= 24_000,
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity))
        else { return }
        // The audio converter may request input more than once. Return this slice
        // once and mark the rest not yet available, rather than duplicating it.
        var called = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if called {
                inputStatus.pointee = .noDataNow
                return nil
            }
            called = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, error == nil, output.frameLength > 0,
              let channel = output.int16ChannelData?[0] else { return }
        // Supported iOS devices are little-endian; copy before AVFoundation reuses the buffer.
        deliver(Data(bytes: channel, count: Int(output.frameLength) * MemoryLayout<Int16>.size))
    }
}
