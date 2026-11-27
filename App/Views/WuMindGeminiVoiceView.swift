@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech
import SwiftUI

/// Chat dictation and the native realtime call use separate engines.
@MainActor
struct WuMindGeminiVoiceView: View {
    enum VoiceMode: String, CaseIterable, Identifiable {
        case universal
        case openAIRealtime
        var id: String { rawValue }
        var title: String {
            switch self {
            case .universal: return "转写与朗读"
            case .openAIRealtime: return "OpenAI Realtime"
            }
        }
    }

    let isTemporaryChat: Bool
    let onCommitExchange: ((_ question: String, _ answer: String) -> Void)?

    @ObservedObject private var store = WuMindStore.shared
    @StateObject private var engine = WuMindGeminiVoiceEngine()
    @Environment(\.dismiss) private var dismiss

    @State private var mode: VoiceMode = .universal

    var body: some View {
        VStack(spacing: DS.Space.s) {
            HStack {
                Text("语音").font(DS.Font.title).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("关闭") { engine.stopEverything(); dismiss() }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("wumind.voice.close")
            }
            .padding(.horizontal, DS.Space.m)
            Picker("语音方式", selection: $mode) {
                ForEach(VoiceMode.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DS.Space.m)
            if mode == .openAIRealtime {
                NavigationStack { AILiveCallView() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        AppSectionCard(title: engine.phaseTitle, subtitle: engine.phaseSubtitle) {
                            Label(engine.audioRouteLabel, systemImage: engine.audioRouteIcon)
                                .font(DS.Font.caption).foregroundStyle(.secondary)
                            Text(store.channel == .managed ? store.managedSelectedModelID : store.selectedModelName)
                                .font(DS.Font.caption)
                            if isTemporaryChat {
                                Label("临时对话", systemImage: "eye.slash").font(DS.Font.caption)
                            } else {
                                let files = store.pendingAttachments.count
                                Text(files == 0 ? "转写与回复将保存在当前对话。" : "当前对话附有 \(files) 份文件。")
                                    .font(DS.Font.caption).foregroundStyle(.secondary)
                            }
                            AppPrimaryCTA(title: primaryActionLabel, icon: primaryActionIcon) { handlePrimaryOrbTap() }
                                .accessibilityIdentifier("wumind.voice.orb")
                            Toggle("连续听写", isOn: Binding(
                                get: { engine.autoLoop },
                                set: { if $0 != engine.autoLoop { engine.toggleHandsFreeAutoLoop() } }
                            ))
                        }
                        if !engine.liveUserTranscript.isEmpty {
                            AppSectionCard(title: "你的转写") { Text(engine.liveUserTranscript) }
                        }
                        if !engine.lastAssistantReply.isEmpty {
                            AppSectionCard(title: "WuMind") { Text(engine.lastAssistantReply) }
                        }
                        if case .error = engine.phase, engine.canRetryLastQuestion {
                            Button("重试上一句") { engine.retryLastQuestion() }
                                .buttonStyle(.secondary)
                                .accessibilityIdentifier("wumind.voice.retry")
                        }
                        if engine.phase != .idle {
                            Button("结束语音") { engine.stopEverything(); dismiss() }
                                .buttonStyle(.secondary)
                                .accessibilityIdentifier("wumind.voice.end")
                        }
                    }
                    .frame(maxWidth: DS.readableWidth)
                    .padding(DS.Space.m)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, DS.Space.xs)
        .background(AppBackground())
        .onChange(of: mode) { if $0 == .openAIRealtime { engine.stopEverything() } }
        .onDisappear { engine.stopEverything() }
    }

    private var primaryActionIcon: String {
        switch engine.phase {
        case .idle, .error: return "mic.fill"
        case .listening: return "arrow.up"
        case .thinking: return "stop.fill"
        case .speaking: return "hand.raised.fill"
        }
    }

    private var primaryActionLabel: String {
        switch engine.phase {
        case .idle, .error: return "开始说话"
        case .listening: return "立即发送"
        case .thinking: return "停止生成"
        case .speaking: return "打断说话"
        }
    }

    private func handlePrimaryOrbTap() {
        Haptics.tap()
        switch engine.phase {
        case .idle, .error:
            engine.startListening(store: store, isTemporaryChat: isTemporaryChat, onCommitExchange: onCommitExchange)
        case .listening:
            engine.sendCurrentTranscriptNow(store: store, isTemporaryChat: isTemporaryChat, onCommitExchange: onCommitExchange)
        case .thinking:
            engine.cancelGenerationAndIdle()
        case .speaking:
            engine.interruptSpeechAndListen(store: store, isTemporaryChat: isTemporaryChat, onCommitExchange: onCommitExchange)
        }
    }
}

// MARK: - Hands-Free Voice Engine (STT + RMS Level + Any WUMIND Model + Natural TTS)

@MainActor
final class WuMindGeminiVoiceEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum Phase: Equatable {
        case idle
        case listening
        case thinking
        case speaking
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var audioLevel: CGFloat = 0
    @Published private(set) var liveUserTranscript = ""
    @Published private(set) var lastAssistantReply = ""
    @Published private(set) var autoLoop = true
    @Published private(set) var audioRouteLabel = "扬声器"
    @Published private(set) var audioRouteIcon = "speaker.wave.2.fill"

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?
    private var llmTask: Task<Void, Never>?
    private var routeRecoveryTask: Task<Void, Never>?
    private var sessionHistory: [AIProviderMessage] = []
    private var hasSeededConversationContext = false
    private var seededAttachmentSummary: String?
    private var seededNativeImages: [AIProviderMessage.ImageAttachment] = []
    private var lastFailedQuestion: String?
    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    private weak var activeStore: WuMindStore?
    private var activeTempMode = false
    private var activeOnCommit: ((String, String) -> Void)?

    var canRetryLastQuestion: Bool {
        guard let q = lastFailedQuestion else { return false }
        return !q.isEmpty
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        refreshAudioRouteInfo()
        installAudioSessionObservers()
    }

    private func installAudioSessionObservers() {
        let center = NotificationCenter.default
        routeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAudioRouteChanged()
            }
        }
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                self?.handleAudioInterruption(rawType: rawType, rawOptions: rawOptions)
            }
        }
    }

    private func refreshAudioRouteInfo() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        if let bt = outputs.first(where: {
            $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
        }) {
            audioRouteLabel = bt.portName.isEmpty ? "蓝牙耳机" : String(bt.portName.prefix(12))
            audioRouteIcon = "airpodspro"
        } else if outputs.contains(where: { $0.portType == .headphones || $0.portType == .usbAudio }) {
            audioRouteLabel = "有线耳机"
            audioRouteIcon = "headphones"
        } else {
            audioRouteLabel = "扬声器"
            audioRouteIcon = "speaker.wave.2.fill"
        }
    }

    private func handleAudioRouteChanged() {
        refreshAudioRouteInfo()
        // Hot-swapping Bluetooth/AirPods changes inputNode hardware sample rate; cleanly rebind audio tap.
        guard phase == .listening, let store = activeStore else { return }
        stopRecognitionOnly()
        routeRecoveryTask?.cancel()
        routeRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self, !Task.isCancelled else { return }
            self.startListening(store: store, isTemporaryChat: self.activeTempMode, onCommitExchange: self.activeOnCommit)
        }
    }

    private func handleAudioInterruption(rawType: UInt?, rawOptions: UInt) {
        guard let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            stopRecognitionOnly()
            if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
            if phase == .listening || phase == .speaking {
                phase = .idle
            }
        case .ended:
            let opts = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if opts.contains(.shouldResume), autoLoop, let store = activeStore, phase == .idle {
                startListening(store: store, isTemporaryChat: activeTempMode, onCommitExchange: activeOnCommit)
            }
        @unknown default:
            break
        }
    }

    private func seedConversationIfNeeded(store: WuMindStore, isTemporaryChat: Bool) {
        guard !hasSeededConversationContext else { return }
        hasSeededConversationContext = true
        guard !isTemporaryChat else { return }
        let seed = store.voiceSeedContext()
        if !seed.recentMessages.isEmpty {
            sessionHistory = seed.recentMessages
        }
        seededAttachmentSummary = seed.attachmentSummary
        seededNativeImages = seed.nativeImages
    }

    var phaseTitle: String {
        switch phase {
        case .idle: return "点按开始语音对话"
        case .listening: return "正在聆听…"
        case .thinking: return "WUMIND 思考中…"
        case .speaking: return "正在语音回复…"
        case .error: return "语音连接提示"
        }
    }

    var phaseSubtitle: String {
        switch phase {
        case .idle: return "无需按键不放，开口即聊 · 支持全部已配置大模型"
        case .listening: return "说完停顿约 1.6 秒自动发送，也可点按立即发送"
        case .thinking: return "正在等待模型生成自然口语回答"
        case .speaking: return "随时点击光球可打断并继续提问"
        case .error(let msg): return msg
        }
    }

    func toggleHandsFreeAutoLoop() {
        autoLoop.toggle()
    }

    func retryLastQuestion() {
        guard let q = lastFailedQuestion, !q.isEmpty else { return }
        lastFailedQuestion = nil
        dispatchToModel(q)
    }

    func startListening(
        store: WuMindStore,
        isTemporaryChat: Bool,
        onCommitExchange: ((String, String) -> Void)?
    ) {
        activeStore = store
        activeTempMode = isTemporaryChat
        activeOnCommit = onCommitExchange
        seedConversationIfNeeded(store: store, isTemporaryChat: isTemporaryChat)
        stopRecognitionOnly()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let speechOK = await Self.requestSpeechPermission()
            guard speechOK else {
                self.phase = .error("请在 iPhone「设置」中开启语音识别权限。")
                return
            }
            let micOK = await Self.requestMicPermission()
            guard micOK else {
                self.phase = .error("请在 iPhone「设置」中开启麦克风权限。")
                return
            }
            self.beginCapture()
        }
    }

    func sendCurrentTranscriptNow(
        store: WuMindStore,
        isTemporaryChat: Bool,
        onCommitExchange: ((String, String) -> Void)?
    ) {
        activeStore = store
        activeTempMode = isTemporaryChat
        activeOnCommit = onCommitExchange
        seedConversationIfNeeded(store: store, isTemporaryChat: isTemporaryChat)
        let text = liveUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopRecognitionOnly()
        guard !text.isEmpty else {
            phase = .idle
            return
        }
        dispatchToModel(text)
    }

    func cancelGenerationAndIdle() {
        llmTask?.cancel()
        llmTask = nil
        phase = .idle
    }

    func interruptSpeechAndListen(
        store: WuMindStore,
        isTemporaryChat: Bool,
        onCommitExchange: ((String, String) -> Void)?
    ) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        startListening(store: store, isTemporaryChat: isTemporaryChat, onCommitExchange: onCommitExchange)
    }

    func stopEverything() {
        routeRecoveryTask?.cancel()
        routeRecoveryTask = nil
        silenceTimer?.cancel()
        silenceTimer = nil
        llmTask?.cancel()
        llmTask = nil
        stopRecognitionOnly()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        phase = .idle
        audioLevel = 0
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopRecognitionOnly() {
        silenceTimer?.cancel()
        silenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        audioLevel = 0
    }

    private func beginCapture() {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) ?? SFSpeechRecognizer(locale: Locale.current)
        guard let recognizer, recognizer.isAvailable else {
            phase = .error("当前设备语音识别暂不可用。")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            refreshAudioRouteInfo()
        } catch {
            phase = .error("无法启动音频会话，请检查麦克风占用情况。")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16.0, *) { request.addsPunctuation = true }
        recognitionRequest = request
        liveUserTranscript = ""

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        Self.installLevelAndSpeechTap(on: inputNode, format: format, request: request) { [weak self] level in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .listening else { return }
                self.audioLevel = max(0, min(1, level))
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stopRecognitionOnly()
            phase = .error("音频引擎启动失败。")
            return
        }

        phase = .listening

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hasError = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.phase == .listening else { return }
                if let text, !text.isEmpty {
                    self.liveUserTranscript = text
                    self.armSilenceAutoSend()
                }
                if isFinal {
                    let clean = self.liveUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.stopRecognitionOnly()
                    if !clean.isEmpty {
                        self.dispatchToModel(clean)
                    } else {
                        self.phase = .idle
                    }
                } else if hasError {
                    let clean = self.liveUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.stopRecognitionOnly()
                    if !clean.isEmpty {
                        self.dispatchToModel(clean)
                    } else {
                        self.phase = .idle
                    }
                }
            }
        }
    }

    private func armSilenceAutoSend() {
        silenceTimer?.cancel()
        silenceTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_650_000_000)
            guard let self, !Task.isCancelled, self.phase == .listening else { return }
            let clean = self.liveUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            self.stopRecognitionOnly()
            self.dispatchToModel(clean)
        }
    }

    private func dispatchToModel(_ question: String) {
        guard let store = activeStore else {
            phase = .idle
            return
        }
        seedConversationIfNeeded(store: store, isTemporaryChat: activeTempMode)
        phase = .thinking
        lastAssistantReply = ""
        lastFailedQuestion = nil

        // Seamless multimodal continuity: carry pending chat images/documents into the voice turn!
        var outgoingText = question
        var outgoingImages: [AIProviderMessage.ImageAttachment] = []
        if !activeTempMode {
            if let summary = seededAttachmentSummary {
                outgoingText = "\(summary)\n\n【用户语音追问】\n\(question)"
                seededAttachmentSummary = nil
            }
            if !seededNativeImages.isEmpty && store.activeProviderForDisplay != .deepSeek {
                outgoingImages = seededNativeImages
                seededNativeImages = []
            }
        }

        sessionHistory.append(AIProviderMessage(role: .user, text: outgoingText, images: outgoingImages))
        let recent = Array(sessionHistory.suffix(12))

        llmTask?.cancel()
        llmTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var systemParts: [String] = []
                if let baseSystem = store.composedSystemPrompt(isTemporaryChat: self.activeTempMode) {
                    systemParts.append(baseSystem)
                }
                systemParts.append("你是 WUMIND 实时语音助手。请承接当前对话历史与已上传图片/文件直接回答，用自然、简洁、口语化、适合语音朗读的方式表达（避免 Markdown 星号与冗长代码块；单次回复尽量控制在 3~5 句话内，除非用户明确要求展开）。")
                let voiceSystem = systemParts.joined(separator: "\n\n")
                let result = try await store.runStatelessChat(
                    messages: recent,
                    systemPrompt: voiceSystem,
                    deepThinking: false,
                    onAnswerDelta: { partial in
                        self.lastAssistantReply = partial
                    }
                )
                try Task.checkCancellation()
                let answer = result.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                self.lastAssistantReply = answer
                self.sessionHistory.append(AIProviderMessage(role: .assistant, text: answer))
                if !self.activeTempMode {
                    self.activeOnCommit?(question, answer)
                }
                self.speak(answer)
            } catch is CancellationError {
                self.phase = .idle
            } catch {
                self.lastFailedQuestion = question
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.phase = .error(msg)
            }
        }
    }

    private func speak(_ text: String) {
        let spoken = Self.cleanForSpeech(text)
        guard !spoken.isEmpty else {
            phase = .idle
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {}

        let utterance = AVSpeechUtterance(string: spoken)
        let hasCJK = spoken.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        utterance.voice = AVSpeechSynthesisVoice(language: hasCJK ? "zh-CN" : "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.04
        phase = .speaking
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.phase == .speaking else { return }
            if self.autoLoop, let store = self.activeStore {
                self.startListening(store: store, isTemporaryChat: self.activeTempMode, onCommitExchange: self.activeOnCommit)
            } else {
                self.phase = .idle
            }
        }
    }

    private static func cleanForSpeech(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"[`*_#>\[\]]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func installLevelAndSpeechTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest,
        onLevel: @escaping @Sendable (CGFloat) -> Void
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for i in 0..<count {
                let s = channel[i]
                sum += s * s
            }
            let rms = sqrt(sum / Float(count))
            let normalized = min(1.0, max(0.0, CGFloat(rms * 14.0)))
            onLevel(normalized)
        }
    }

    private nonisolated static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    private nonisolated static func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }
}
