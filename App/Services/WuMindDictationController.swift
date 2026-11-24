@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

/// Live on-device streaming speech-to-text dictation controller for the WUMIND composer.
/// Strictly Swift 6 concurrency-safe: audio render callbacks feed `SFSpeechAudioBufferRecognitionRequest`
/// off-MainActor and deliver partial/final transcripts back on `@MainActor`.
@MainActor
final class WuMindDictationController: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var statusMessage: String? = nil

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onTranscript: ((String) -> Void)?

    func toggle(onTranscript: @escaping (String) -> Void) {
        if isListening {
            stop()
        } else {
            start(onTranscript: onTranscript)
        }
    }

    func start(onTranscript: @escaping (String) -> Void) {
        guard !isListening else { return }
        self.onTranscript = onTranscript
        statusMessage = "正在请求语音权限…"

        Task { @MainActor [weak self] in
            guard let self else { return }
            let speechOK = await Self.requestSpeechPermission()
            guard speechOK else {
                self.statusMessage = "请在系统设置中允许语音识别权限。"
                return
            }
            let micOK = await Self.requestMicrophonePermission()
            guard micOK else {
                self.statusMessage = "请在系统设置中允许麦克风权限。"
                return
            }
            self.beginRecognitionSession()
        }
    }

    func stop() {
        guard isListening || recognitionTask != nil else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        statusMessage = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginRecognitionSession() {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
            ?? SFSpeechRecognizer(locale: Locale.current)
        guard let recognizer, recognizer.isAvailable else {
            statusMessage = "当前设备语音听写暂不可用。"
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            statusMessage = "无法启动麦克风录音会话。"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = false
        }
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        Self.installAudioTap(on: inputNode, format: recordingFormat, request: request)

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            statusMessage = "启动音频引擎失败。"
            stop()
            return
        }

        isListening = true
        statusMessage = "正在聆听，说停即可…"

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hasError = error != nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text, !text.isEmpty {
                    self.onTranscript?(text)
                }
                if isFinal || hasError {
                    self.stop()
                }
            }
        }
    }

    private nonisolated static func installAudioTap(
        on node: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
