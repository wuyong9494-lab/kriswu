@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech
import SwiftUI

/// Dedicated Full-Screen Gemini Live-Style Voice Conversation Overlay.
/// Pops over WUMIND chat as a focused cosmic voice stage with animated plasma orb,
/// real-time RMS audio waveform halo, hands-free STT -> ANY WUMIND model -> natural TTS
/// with instant barge-in interrupt, plus 1-tap top switch to OpenAI Realtime native audio.
@MainActor
struct WuMindGeminiVoiceView: View {
    enum VoiceMode: String, CaseIterable, Identifiable {
        case universal
        case openAIRealtime
        var id: String { rawValue }
        var title: String {
            switch self {
            case .universal: return "Gemini 全模型语音"
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
    @State private var pulsePhase: CGFloat = 0

    var body: some View {
        ZStack {
            cosmicBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if mode == .openAIRealtime {
                    NavigationStack {
                        AILiveCallView()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                } else {
                    universalGeminiStage
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                pulsePhase = 1
            }
        }
        .onDisappear {
            engine.stopEverything()
        }
        .accessibilityIdentifier("wumind.geminiVoice.screen")
    }

    private var cosmicBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.09),
                    Color(red: 0.05, green: 0.07, blue: 0.16),
                    Color(red: 0.03, green: 0.035, blue: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [
                    orbPrimaryColor.opacity(0.26 + Double(engine.audioLevel) * 0.25),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 340
            )
            .animation(.easeOut(duration: 0.18), value: engine.audioLevel)
        }
    }

    private var orbPrimaryColor: Color {
        switch engine.phase {
        case .idle: return Color(red: 0.30, green: 0.55, blue: 0.98)
        case .listening: return Color(red: 0.24, green: 0.78, blue: 0.98)
        case .thinking: return Color(red: 0.58, green: 0.38, blue: 0.98)
        case .speaking: return Color(red: 0.22, green: 0.85, blue: 0.72)
        case .error: return Color.orange
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(orbPrimaryColor)
                    Text(store.channel == .managed ? store.managedSelectedModelID : store.selectedModelName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if isTemporaryChat {
                        Text("临时")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.09), in: Capsule())

                Spacer()

                Button {
                    Haptics.tap()
                    engine.stopEverything()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wumind.voice.close")
            }

            // Full-width 2-mode pill toggle
            HStack(spacing: 4) {
                ForEach(VoiceMode.allCases) { item in
                    let active = mode == item
                    Button {
                        Haptics.tap()
                        if item == .openAIRealtime { engine.stopEverything() }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            mode = item
                        }
                    } label: {
                        Text(item.title)
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(active ? Color.white.opacity(0.18) : Color.clear, in: Capsule())
                            .foregroundStyle(active ? .white : .white.opacity(0.62))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var universalGeminiStage: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 10)

            // Animated Luminous Gemini Live Plasma Orb
            Button {
                handlePrimaryOrbTap()
            } label: {
                ZStack {
                    // Outer audio-reactive ripple rings
                    ForEach(0..<3, id: \.self) { idx in
                        Circle()
                            .stroke(orbPrimaryColor.opacity(0.28 - Double(idx) * 0.08), lineWidth: 2)
                            .frame(
                                width: 170 + CGFloat(idx) * 34 + engine.audioLevel * 44,
                                height: 170 + CGFloat(idx) * 34 + engine.audioLevel * 44
                            )
                            .scaleEffect(1 + pulsePhase * 0.05)
                    }

                    // Luminous core orb
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [
                                    Color(red: 0.25, green: 0.60, blue: 1.0),
                                    Color(red: 0.56, green: 0.32, blue: 0.98),
                                    Color(red: 0.18, green: 0.85, blue: 0.78),
                                    Color(red: 0.25, green: 0.60, blue: 1.0)
                                ],
                                center: .center,
                                angle: .degrees(engine.phase == .thinking ? 360 : Double(pulsePhase) * 90)
                            )
                        )
                        .frame(width: 148 + engine.audioLevel * 22, height: 148 + engine.audioLevel * 22)
                        .blur(radius: 10)
                        .opacity(0.85)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.95), orbPrimaryColor.opacity(0.88), Color(red: 0.14, green: 0.18, blue: 0.45)],
                                center: .topLeading,
                                startRadius: 8,
                                endRadius: 96
                            )
                        )
                        .frame(width: 132, height: 132)
                        .shadow(color: orbPrimaryColor.opacity(0.65), radius: 28)

                    Image(systemName: orbIconName)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(height: 255)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wumind.voice.orb")

            VStack(spacing: 6) {
                Text(engine.phaseTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(engine.phaseSubtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            // Live Subtitle / Transcript Panel
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !engine.liveUserTranscript.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("你说")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.cyan)
                            Text(engine.liveUserTranscript)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.94))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !engine.lastAssistantReply.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("WUMIND")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.mint)
                            Text(engine.lastAssistantReply)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.90))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if engine.liveUserTranscript.isEmpty && engine.lastAssistantReply.isEmpty {
                        Text("支持连续自然语音对话：点按中间按钮开口说话，停顿约 1.6 秒自动发送给当前模型并语音播报；播报时随时点击即可打断插话。")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 165)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .padding(.horizontal, 18)

            Spacer(minLength: 6)

            // Bottom Gemini Live Control Dock
            HStack(spacing: 28) {
                Button {
                    Haptics.tap()
                    engine.toggleHandsFreeAutoLoop()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: engine.autoLoop ? "repeat.circle.fill" : "repeat.circle")
                            .font(.title2)
                            .foregroundStyle(engine.autoLoop ? .cyan : .white.opacity(0.6))
                            .frame(width: 54, height: 54)
                            .background(Color.white.opacity(0.10), in: Circle())
                        Text(engine.autoLoop ? "连续对话" : "单轮对话")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .buttonStyle(.plain)

                Button {
                    handlePrimaryOrbTap()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: primaryActionIcon)
                            .font(.title.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(
                                LinearGradient(colors: [orbPrimaryColor, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: Circle()
                            )
                            .shadow(color: orbPrimaryColor.opacity(0.55), radius: 14, y: 4)
                        Text(primaryActionLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wumind.voice.action")

                Button {
                    Haptics.tap()
                    engine.stopEverything()
                    dismiss()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "phone.down.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Color.red.opacity(0.88), in: Circle())
                        Text("结束")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wumind.voice.end")
            }
            .padding(.bottom, 26)
        }
    }

    private var orbIconName: String {
        switch engine.phase {
        case .idle: return "mic.fill"
        case .listening: return "waveform"
        case .thinking: return "sparkles"
        case .speaking: return "speaker.wave.3.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
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
final class WuMindGeminiVoiceEngine: NSObject, ObservableObject, @preconcurrency AVSpeechSynthesizerDelegate {
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

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?
    private var llmTask: Task<Void, Never>?
    private var sessionHistory: [AIProviderMessage] = []

    private weak var activeStore: WuMindStore?
    private var activeTempMode = false
    private var activeOnCommit: ((String, String) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
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

    func startListening(
        store: WuMindStore,
        isTemporaryChat: Bool,
        onCommitExchange: ((String, String) -> Void)?
    ) {
        activeStore = store
        activeTempMode = isTemporaryChat
        activeOnCommit = onCommitExchange
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
        silenceTimer?.cancel()
        silenceTimer = nil
        llmTask?.cancel()
        llmTask = nil
        stopRecognitionOnly()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        phase = .idle
        audioLevel = 0
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
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
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
        phase = .thinking
        lastAssistantReply = ""
        sessionHistory.append(AIProviderMessage(role: .user, text: question))
        let recent = Array(sessionHistory.suffix(10))

        llmTask?.cancel()
        llmTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let voiceSystem = "你是 WUMIND 实时语音助手。请用自然、简洁、口语化、适合语音朗读的方式直接回答（避免 Markdown 表格、星号和冗长代码块；单次回复尽量控制在 3~5 句话内，除非用户要求展开）。"
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
