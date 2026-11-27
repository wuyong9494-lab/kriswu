import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
struct AISpeechToolView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case tts, stt
        var id: String { rawValue }
        var title: String { self == .tts ? "文字转语音 (TTS)" : "录音转文字 (STT)" }
        var icon: String { self == .tts ? "speaker.wave.2.fill" : "mic.fill" }
    }

    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var store = WuMindStore.shared
    @State private var mode: Mode = .tts
    @State private var recorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var recordingTimer: Task<Void, Never>?
    @State private var recordingSession: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    @State private var script = ""
    @State private var voice = AISpeechTool.Voice.eve
    @State private var synthesized: Data?
    @State private var recording: Recording?
    @State private var transcript = ""
    @State private var message: String?
    @State private var activity: Task<Void, Never>?
    @State private var activeID: UUID?
    @State private var player: AVAudioPlayer?
    @State private var localSpeaker = AVSpeechSynthesizer()
    @State private var importing = false
    @State private var exporting = false
    @State private var consent: Consent?

    private struct Recording: Sendable {
        let name: String
        let format: AISpeechTool.RecordingFormat
        let data: Data
    }

    private enum Consent: Identifiable {
        case speak, transcribe
        var id: Int { self == .speak ? 0 : 1 }
        var title: String {
            switch self {
            case .speak: return "把朗读文字发给 xAI？"
            case .transcribe: return "把选中的录音发给 OpenAI？"
            }
        }
    }

    private var isDark: Bool { colorScheme == .dark }
    private var pageBg: Color {
        isDark ? Color(red: 0.035, green: 0.04, blue: 0.06) : Color(red: 0.955, green: 0.96, blue: 0.98)
    }
    private var cardBg: Color {
        isDark ? Color(red: 0.095, green: 0.105, blue: 0.14) : Color.white
    }
    private var cardBorder: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }
    private var busy: Bool { activity != nil }
    private let importTypes: [UTType] = [.audio, .mpeg4Movie, .wav] +
        ["flac", "ogg", "webm", "m4a", "mp3"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WuMindHubHeroBanner(
                    title: "WUMIND 语音工坊",
                    subtitle: "系统离线朗读、xAI 拟真音色合成与 OpenAI 录音高精转写",
                    icon: "waveform",
                    colors: [Color(red: 0.24, green: 0.26, blue: 0.78), Color(red: 0.52, green: 0.26, blue: 0.76)],
                    chips: [
                        ("离线朗读", "免 Key 免费"),
                        ("音频转写", "支持 20MB 导入")
                    ]
                )

                // Full-width 2-Tab Mode Switcher (Zero horizontal overflow)
                HStack(spacing: 6) {
                    ForEach(Mode.allCases) { item in
                        let active = mode == item
                        Button {
                            Haptics.select()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                mode = item
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.icon)
                                    .font(.caption.weight(.bold))
                                Text(item.title)
                                    .font(.caption.weight(.bold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(active ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(active ? Color.indigo : cardBg, in: Capsule())
                            .overlay(Capsule().strokeBorder(active ? Color.clear : cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if mode == .tts {
                    reading
                } else {
                    transcription
                }

                if busy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在处理语音任务…")
                            .font(.footnote.weight(.medium))
                        Spacer()
                        Button("停止等待", role: .cancel) {
                            cancel()
                            message = "已停止等待。已经发出的请求可能产生用量。"
                        }
                        .font(.caption.weight(.bold))
                    }
                    .padding(14)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                }
            }
            .padding(14)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(pageBg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("语音合成与转写")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("收起键盘") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: importTypes) { result in
            loadSelection(result)
        }
        .fileExporter(isPresented: $exporting, document: synthesized.map { WaveDocument(data: $0) },
                      contentType: .wav, defaultFilename: "AI语音") { result in
            if case .failure = result { message = "未能保存音频，请重试。" }
        }
        .alert(item: $consent) { confirmation in
            let explanation = confirmation == .speak
                ? "只发送当前朗读文字，由 xAI 合成音频，可能产生 API 费用。不要输入未获授权外发的内容。"
                : "只发送你选中的完整文件，由 OpenAI 转写，可能产生 API 费用。请确认有权外发录音及其中的声音和内容。MP4 或 WebM 会上传整个所选文件。"
            return Alert(title: Text(confirmation.title), message: Text(explanation),
                         primaryButton: .default(Text("确认发送")) {
                switch confirmation {
                case .speak: synthesize()
                case .transcribe: transcribe()
                }
            }, secondaryButton: .cancel())
        }
        .onChange(of: phase) { next in
            if next != .active, recorder != nil { endRecording(keep: false) }
        }
        .onDisappear {
            endRecording(keep: false)
            cancel()
            stopPlaying()
            recording = nil
            synthesized = nil
        }
    }

    private var reading: some View {
        let validScript = (try? AISpeechTool.cleanedScript(script)) != nil
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("输入朗读文本")
                    .font(.subheadline.weight(.bold))
                TextField("输入要朗读的文字，可用系统键盘听写…", text: $script, axis: .vertical)
                    .lineLimit(4...8)
                    .disabled(busy || recorder != nil)
                    .padding(12)
                    .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("ai.speech.script")

                Text("xAI 合成音色")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(AISpeechTool.Voice.allCases, id: \.self) { item in
                        let active = voice == item
                        Button {
                            Haptics.select()
                            voice = item
                        } label: {
                            Text(item.rawValue.capitalized)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(active ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(active ? Color.indigo : Color.secondary.opacity(0.11), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || recorder != nil)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        playLocal()
                    } label: {
                        Label("系统朗读", systemImage: "speaker.wave.2")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.secondary.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || recorder != nil || !validScript)

                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        guard speechKey(for: .grok) != nil else { return }
                        consent = .speak
                    } label: {
                        Label("xAI 合成", systemImage: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background((busy || recorder != nil || !validScript) ? Color.secondary.opacity(0.35) : Color.indigo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || recorder != nil || !validScript)
                }

                if synthesized != nil {
                    HStack(spacing: 10) {
                        Button { playCloud() } label: {
                            Label("播放合成音频", systemImage: "play.fill")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color.teal.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || recorder != nil)

                        Button { exporting = true } label: {
                            Label("导出 WAV", systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || recorder != nil)
                    }
                }

                Button("停止播放", role: .cancel) { stopPlaying() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
        }
    }

    private var transcription: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text("录音或导入音频文件")
                    .font(.subheadline.weight(.bold))

                if recorder != nil {
                    HStack(spacing: 10) {
                        Image(systemName: "record.circle.fill")
                            .foregroundStyle(.red)
                            .font(.title3)
                        Text("正在录音（最多 60 秒）")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 10) {
                        Button {
                            endRecording(keep: true)
                        } label: {
                            Text("结束并保留")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color.indigo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            endRecording(keep: false)
                        } label: {
                            Text("取消删除")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(DS.Palette.danger)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(DS.Palette.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button { beginRecording() } label: {
                            Label("开始录音", systemImage: "mic.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.indigo, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)

                        Button { importing = true } label: {
                            Label("导入录音", systemImage: "folder.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.secondary.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy || recorder != nil)
                        .accessibilityIdentifier("ai.speech.import")
                    }
                }

                if let recording {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(recording.name, systemImage: "waveform.circle.fill")
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(recording.data.count), countStyle: .file))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Button("试听") { playData(recording.data) }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.secondary.opacity(0.13), in: Capsule())
                                .buttonStyle(.plain)
                                .disabled(busy || recorder != nil)

                            Button("OpenAI 转文字") {
                                guard speechKey(for: .openAI) != nil else { return }
                                consent = .transcribe
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.teal, in: Capsule())
                            .buttonStyle(.plain)
                            .disabled(busy || recorder != nil)

                            Spacer()

                            Button("移除", role: .destructive) { self.recording = nil }
                                .font(.caption.weight(.semibold))
                                .disabled(busy || recorder != nil)
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }

                Text("支持录制 60 秒或导入 20MB 以内音频，仅在你确认后上传转写，不在后台录音。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

            if !transcript.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("转写结果")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        Button("复制") {
                            UIPasteboard.general.string = transcript
                            Haptics.success()
                        }
                        .font(.caption.weight(.semibold))
                        Button("清除", role: .destructive) { transcript = "" }
                            .font(.caption.weight(.semibold))
                    }
                    Text(transcript)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
            }
        }
    }

    private func beginRecording() {
        guard !busy, recorder == nil else { return }
        start { id in
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            guard activeID == id, !Task.isCancelled else { return }
            guard granted else {
                message = "未获得麦克风权限。你仍可以导入录音文件。"
                return
            }
            guard phase == .active else {
                message = "回到 App 后再点一次开始录音。"
                return
            }
            stopPlaying()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ai-speech-" + UUID().uuidString)
                .appendingPathExtension("m4a")
            let session = AVAudioSession.sharedInstance()
            recordingURL = url
            recordingSession = (session.category, session.mode, session.categoryOptions)
            do {
                try session.setCategory(.record, mode: .default)
                try session.setActive(true)
                let new = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 24_000.0,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 64_000
                ])
                recorder = new
                guard new.prepareToRecord() else {
                    endRecording(keep: false)
                    message = "无法准备录音，请稍后重试。"
                    return
                }
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
                guard new.record(forDuration: 60) else {
                    endRecording(keep: false)
                    message = "无法开始录音，请稍后重试。"
                    return
                }
                recording = nil
                transcript = ""
                recordingTimer = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                    catch { return }
                    endRecording(keep: true)
                }
            } catch {
                endRecording(keep: false)
                message = "无法使用麦克风录音，请稍后重试。"
            }
        }
    }

    private func endRecording(keep: Bool) {
        recordingTimer?.cancel()
        recordingTimer = nil
        recorder?.stop()
        recorder = nil
        if let saved = recordingSession {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(saved.0, mode: saved.1, options: saved.2)
            recordingSession = nil
        }
        guard let url = recordingURL else { return }
        recordingURL = nil
        defer { try? FileManager.default.removeItem(at: url) }
        guard keep, phase == .active else { return }
        do {
            let captured = try Self.readRecording(url)
            recording = Recording(name: "本次麦克风录音", format: captured.format, data: captured.data)
        } catch {
            message = "未能保存这段录音，请再试一次。"
        }
    }

    private func loadSelection(_ result: Result<URL, Error>) {
        guard !busy, recorder == nil else { return }
        switch result {
        case .failure:
            message = "未能打开文件选择，请重试。"
        case .success(let url):
            recording = nil
            transcript = ""
            start { id in
                let load = Task.detached(priority: .userInitiated) { try Self.readRecording(url) }
                let imported = try await withTaskCancellationHandler {
                    try await load.value
                } onCancel: {
                    load.cancel()
                }
                guard activeID == id, !Task.isCancelled else { return }
                recording = imported
            }
        }
    }

    private nonisolated static func readRecording(_ url: URL) throws -> Recording {
        guard let format = AISpeechTool.RecordingFormat(rawValue: url.pathExtension.lowercased()) else {
            throw AISpeechTool.Problem.unsupportedAudio
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard metadata.isRegularFile == true else { throw AISpeechTool.Problem.unreadableAudio }
            guard let size = metadata.fileSize, size > 0, size <= AISpeechTool.maxRecordingBytes else {
                throw AISpeechTool.Problem.invalidSize
            }
            let stream = try FileHandle(forReadingFrom: url)
            defer { try? stream.close() }
            var bytes = Data()
            while let chunk = try stream.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                try Task.checkCancellation()
                guard chunk.count <= AISpeechTool.maxRecordingBytes - bytes.count else {
                    throw AISpeechTool.Problem.invalidSize
                }
                bytes.append(chunk)
            }
            guard !bytes.isEmpty else { throw AISpeechTool.Problem.invalidSize }
            return Recording(name: url.lastPathComponent, format: format, data: bytes)
        } catch let problem as AISpeechTool.Problem {
            throw problem
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AISpeechTool.Problem.unreadableAudio
        }
    }

    private func speechKey(for provider: AIProvider) -> String? {
        guard store.channel == .ownAPI else {
            message = "内置通道暂不支持这项云端语音操作。系统朗读可直接使用。"
            return nil
        }
        guard store.selectedProvider.multiProvider == provider else {
            message = "此操作需要在自有通道选择 \(provider.displayName)。"
            return nil
        }
        if let base = AIProviderEndpoints.baseURL(for: provider),
           ![provider.defaultBaseURLString, provider.defaultBaseURLString + "/v1"].contains(base.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()) {
            message = "此语音协议仅支持 \(provider.displayName) 官方接口，当前连接使用了自定义地址。"
            return nil
        }
        guard let key = Keychain.providerChatAPIKey(provider, baseURL: nil) else {
            message = "请在自有通道保存 \(provider.displayName) 的 Key。"
            return nil
        }
        return key
    }

    private func synthesize() {
        guard let key = speechKey(for: .grok) else { return }
        let requestedScript = script
        let requestedVoice = voice
        synthesized = nil
        stopPlaying()
        start { id in
            let data = try await AISpeechTool().synthesize(requestedScript, voice: requestedVoice, apiKey: key)
            guard activeID == id, !Task.isCancelled else { return }
            synthesized = data
        }
    }

    private func transcribe() {
        guard let recording else { return }
        guard let key = speechKey(for: .openAI) else { return }
        transcript = ""
        start { id in
            let text = try await AISpeechTool().transcribe(recording.data, format: recording.format, apiKey: key)
            guard activeID == id, !Task.isCancelled else { return }
            transcript = text
        }
    }

    private func start(_ body: @escaping @MainActor (UUID) async throws -> Void) {
        guard !busy else { return }
        message = nil
        let id = UUID()
        activeID = id
        activity = Task { @MainActor in
            defer {
                if activeID == id {
                    activeID = nil
                    activity = nil
                }
            }
            do {
                try await body(id)
            } catch is CancellationError {
                return
            } catch {
                guard activeID == id, !Task.isCancelled else { return }
                message = (error as? LocalizedError)?.errorDescription ?? "语音操作失败，请重试。"
            }
        }
    }

    private func cancel() {
        activity?.cancel()
        activity = nil
        activeID = nil
    }

    private func playLocal() {
        guard let text = try? AISpeechTool.cleanedScript(script) else { return }
        stopPlaying()
        localSpeaker.speak(AVSpeechUtterance(string: text))
    }

    private func playCloud() {
        guard let synthesized else { return }
        playData(synthesized)
    }

    private func playData(_ data: Data) {
        stopPlaying()
        do {
            let next = try AVAudioPlayer(data: data)
            guard next.play() else { message = "无法播放这段音频。"; return }
            player = next
        } catch {
            message = "无法播放这段音频。"
        }
    }

    private func stopPlaying() {
        player?.stop()
        player = nil
        localSpeaker.stopSpeaking(at: .immediate)
    }
}

private struct WaveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.wav] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw AISpeechTool.Problem.unreadableAudio
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
