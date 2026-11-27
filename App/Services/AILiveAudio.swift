import AVFoundation
import Foundation

@MainActor
protocol AILiveAudioIO: AnyObject {
    var activeOutputRouteDescription: String { get }
    var isReconfiguring: Bool { get }
    var hasPendingPlayback: Bool { get }
    var onPlaybackStarted: (@MainActor () -> Void)? { get set }
    var onPlaybackDrained: (@MainActor () -> Void)? { get set }
    func start(onCapture: @escaping @Sendable (Data) -> Void) throws
    func play(_ pcm16: Data) throws
    func playedMilliseconds() -> Int
    func resetPlayback()
    func ownsEngine(_ candidate: Any?) -> Bool
    func reconfigureForRouteChange() async -> Bool
    func stop()
}

/// A foreground, caller-owned duplex engine. Wire format is 24 kHz mono PCM16 little-endian.
@MainActor
final class AILiveAudio: AILiveAudioIO {
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
    private var captureHandler: (@Sendable (Data) -> Void)?
    private var activeHardwareSampleRate: Double = 0
    private var activeHardwareChannels: AVAudioChannelCount = 0
    private var previousCategory: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    private(set) var isReconfiguring = false
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
        captureHandler = onCapture
        do {
            try configureAudioSession(session)
            try buildAndStartEngine(onCapture: onCapture)
        } catch {
            stop()
            throw Issue.unavailable
        }
    }

    var onPlaybackStarted: (@MainActor () -> Void)?
    var onPlaybackDrained: (@MainActor () -> Void)?
    var hasPendingPlayback: Bool { pendingFrames > 0 }

    var activeOutputRouteDescription: String {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let first = outputs.first else { return "系统默认输出" }
        switch first.portType {
        case .builtInSpeaker: return "扬声器"
        case .builtInReceiver: return "听筒"
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: return "蓝牙（\(first.portName)）"
        case .headphones, .headsetMic: return "有线耳机"
        case .airPlay: return "隔空播放"
        default: return first.portName.isEmpty ? "外部音频" : first.portName
        }
    }

    /// Rebuilds the AVAudioEngine graph in-place after iOS fires AVAudioEngineConfigurationChange
    /// (which routinely happens on real iPhones when VoiceProcessingIO settles or audio routes change)
    /// without dropping the active WebSocket call.
    func reconfigureForRouteChange() async -> Bool {
        guard captureHandler != nil else { return false }
        guard !isReconfiguring else { return true }
        isReconfiguring = true
        defer { isReconfiguring = false }

        let backoffNS: [UInt64] = [150_000_000, 260_000_000, 400_000_000]
        for delay in backoffNS {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return false
            }
            guard let handler = captureHandler else { return false }

            // If CoreAudio kept the engine running with the exact same hardware format, no rebuild needed.
            if let engine, engine.isRunning, let input = inputWithTap {
                let currentFormat = input.outputFormat(forBus: 0)
                if currentFormat.sampleRate.isFinite,
                   currentFormat.sampleRate > 0,
                   currentFormat.sampleRate == activeHardwareSampleRate,
                   currentFormat.channelCount == activeHardwareChannels {
                    return true
                }
            }

            teardownEngineOnly()
            let session = AVAudioSession.sharedInstance()
            do {
                try configureAudioSession(session)
                try buildAndStartEngine(onCapture: handler)
                return true
            } catch {
                teardownEngineOnly()
                continue
            }
        }
        return false
    }

    private func configureAudioSession(_ session: AVAudioSession) throws {
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try? session.setPreferredSampleRate(Self.wireRate)
        try? session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
    }

    private func buildAndStartEngine(onCapture: @escaping @Sendable (Data) -> Void) throws {
        teardownEngineOnly()
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        // Enable system Voice Processing I/O before choosing formats. Never fall back
        // silently to open-speaker full duplex without the device's echo cancellation.
        _ = engine.outputNode
        try input.setVoiceProcessingEnabled(true)
        guard input.isVoiceProcessingEnabled else { throw Issue.unavailable }
        let route = AVAudioSession.sharedInstance().currentRoute
        guard !route.inputs.isEmpty, !route.outputs.isEmpty else { throw Issue.unavailable }
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard outputFormat.sampleRate.isFinite, outputFormat.sampleRate > 0, outputFormat.channelCount > 0,
              hardwareFormat.sampleRate.isFinite, hardwareFormat.sampleRate > 0,
              hardwareFormat.channelCount > 0,
              let wireInput = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.wireRate,
                                           channels: 1, interleaved: false),
              let wirePlay = AVAudioFormat(standardFormatWithSampleRate: Self.wireRate, channels: 1)
        else { throw Issue.unavailable }
        let capture = try LiveCaptureConverter(from: hardwareFormat, to: wireInput, deliver: onCapture)
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: wirePlay)
        self.player = player
        self.playFormat = wirePlay
        self.activeHardwareSampleRate = hardwareFormat.sampleRate
        self.activeHardwareChannels = hardwareFormat.channelCount
        let tap: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
            capture.consume(buffer)
        }
        // A newly created engine has no tap. Let the device own its input format during route negotiation.
        input.installTap(onBus: 0, bufferSize: 960, format: nil, block: tap)
        inputWithTap = input
        engine.prepare()
        try engine.start()
    }

    private func teardownEngineOnly() {
        resetPlayback()
        inputWithTap?.removeTap(onBus: 0)
        inputWithTap = nil
        engine?.stop()
        engine = nil
        player = nil
        playFormat = nil
        activeHardwareSampleRate = 0
        activeHardwareChannels = 0
    }

    func ownsEngine(_ candidate: Any?) -> Bool {
        guard let candidate = candidate as? AVAudioEngine, let engine else { return false }
        return candidate === engine
    }

    func play(_ pcm16: Data) throws {
        // Drop transient audio chunks while AVAudioEngine is rebuilding after a hardware route change.
        if isReconfiguring { return }
        guard let player, let playFormat, let engine, engine.isRunning, player.engine === engine,
              !AVAudioSession.sharedInstance().currentRoute.outputs.isEmpty else { throw Issue.unavailable }
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
                if self.pendingFrames == 0 { self.onPlaybackDrained?() }
            }
        }
        if !player.isPlaying {
            player.play()
            onPlaybackStarted?()
        }
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
        captureHandler = nil
        isReconfiguring = false
        teardownEngineOnly()
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
final class LiveCaptureConverter: @unchecked Sendable {
    private let sourceFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let format: AVAudioFormat
    private let ratio: Double
    private let deliver: @Sendable (Data) -> Void

    init(from: AVAudioFormat, to: AVAudioFormat, deliver: @escaping @Sendable (Data) -> Void) throws {
        guard let converter = AVAudioConverter(from: from, to: to) else { throw AILiveAudio.Issue.unavailable }
        self.sourceFormat = from
        self.converter = converter
        self.format = to
        self.ratio = to.sampleRate / from.sampleRate
        self.deliver = deliver
    }

    private struct UncheckedPCMBuffer: @unchecked Sendable {
        let value: AVAudioPCMBuffer
    }

    private final class OneShotFlag: @unchecked Sendable {
        var used = false
    }

    func consume(_ input: AVAudioPCMBuffer) {
        guard input.format == sourceFormat, input.frameLength > 0, input.frameLength <= 8192 else { return }
        let capacity = ceil(Double(input.frameLength) * ratio) + 128
        guard capacity.isFinite, capacity > 0, capacity <= 24_000,
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity))
        else { return }
        // The audio converter may request input more than once. Return this slice
        // once and mark the rest not yet available, rather than duplicating it.
        let oneShot = OneShotFlag()
        var error: NSError?
        let boxedInput = UncheckedPCMBuffer(value: input)
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if oneShot.used {
                inputStatus.pointee = .noDataNow
                return nil
            }
            oneShot.used = true
            inputStatus.pointee = .haveData
            return boxedInput.value
        }
        guard status != .error, error == nil, output.frameLength > 0,
              let channel = output.int16ChannelData?[0] else { return }
        // Supported iOS devices are little-endian; copy before AVFoundation reuses the buffer.
        deliver(Data(bytes: channel, count: Int(output.frameLength) * MemoryLayout<Int16>.size))
    }
}
