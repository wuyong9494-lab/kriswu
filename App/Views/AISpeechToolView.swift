import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
struct AISpeechToolView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case tts, stt
        var id: String { rawValue }
        var title: String { self == .tts ? "文字转语音" : "录音转文字" }
    }

    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject private var store = WuMindStore.shared
    @State private var mode: Mode = .tts
    @State private var recorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var recordingTimer: Task<Void, Never>?
    @State private var recordingSession: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    @State private var script = ""
    @State private var useCloudVoice: Bool
    @State private var voice = AISpeechTool.Voice.eve
    @State private var synthesized: Data?
    @State private var recording: Recording?
    @State private var transcript = ""
    @State private var message: String?
    @State private var activity: Task<Void, Never>?
    @State private var activeID: UUID?
    @State private var player: AVAudioPlayer?
    @State private var localSpeaker = AVSpeechSynthesizer()
    @StateObject private var playback = SpeechPlaybackStatus()
    @State private var importing = false
    @State private var exporting = false
    @State private var consent: Consent?

    init() {
        let selected = WuMindStore.shared
        _useCloudVoice = State(initialValue: selected.channel == .ownAPI && selected.selectedProvider.multiProvider == .grok)
    }

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

    private var busy: Bool { activity != nil }
    private let importTypes: [UTType] = [.audio, .mpeg4Movie, .wav] +
        ["flac", "ogg", "webm", "m4a", "mp3"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Group {
                    if typeSize.isAccessibilitySize {
                        modePicker.pickerStyle(.menu)
                    } else {
                        modePicker.pickerStyle(.segmented)
                    }
                }
                .disabled(busy || recorder != nil)
                .onChange(of: mode) { _ in
                    message = nil
                    Haptics.select()
                }

                if busy {
                    AppSectionCard {
                        ProgressView("正在处理语音任务…")
                        Button("停止等待", role: .cancel) {
                            cancel()
                            message = "已停止等待。已经发出的请求可能产生用量。"
                        }
                    }
                }

                if playback.source != nil {
                    Button(role: .cancel, action: stopPlaying) {
                        Label("停止播放", systemImage: "stop.fill")
                            .font(DS.Font.callout)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("ai.speech.stopPlayback")
                }

                if let message {
                    Text(message)
                        .font(DS.Font.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ai.speech.status")
                }

                if mode == .tts {
                    reading
                } else {
                    transcription
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: DS.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
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
                      contentType: .wav, defaultFilename: "朗读音频") { result in
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

    private var modePicker: some View {
        Picker("音频操作", selection: $mode) {
            ForEach(Mode.allCases) { item in
                Text(item.title).tag(item)
            }
        }
    }

    private var reading: some View {
        let validScript = (try? AISpeechTool.cleanedScript(script)) != nil
        return VStack(alignment: .leading, spacing: DS.Space.m) {
            AppSectionCard(title: "朗读文本") {
                TextField("输入要朗读的文字", text: $script, axis: .vertical)
                    .lineLimit(4...8)
                    .padding(DS.Space.s)
                    .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m))
                    .font(DS.Font.body)
                    .disabled(busy || recorder != nil)
                    .accessibilityLabel("朗读文本")
                    .accessibilityIdentifier("ai.speech.script")
                if !validScript && !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("朗读文本最多 3,000 字、12 KB。")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.danger)
                }
                Divider()
                LabeledContent("朗读方式") {
                    Picker("朗读方式", selection: $useCloudVoice) {
                        Text("本机系统").tag(false)
                        Text("xAI 云端").tag(true)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(busy)
                }
                if useCloudVoice {
                    LabeledContent("xAI 音色") {
                        Picker("xAI 音色", selection: $voice) {
                            ForEach(AISpeechTool.Voice.allCases, id: \.self) { item in
                                Text(item.rawValue.capitalized).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(busy)
                    }
                }
                if !busy {
                    AppPrimaryCTA(title: useCloudVoice ? "xAI 合成" : "系统朗读",
                                  icon: useCloudVoice ? "waveform" : "speaker.wave.2.fill",
                                  isDisabled: recorder != nil || !validScript) {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        if useCloudVoice {
                            guard speechKey(for: .grok) != nil else { return }
                            consent = .speak
                        } else {
                            playLocal()
                        }
                    }
                }
            }

            if synthesized != nil {
                AppSectionCard(title: "上次合成的音频") {
                    Button(action: playCloud) { Label("播放合成音频", systemImage: "play.fill") }
                    Divider()
                    Button { exporting = true } label: { Label("导出 WAV", systemImage: "square.and.arrow.up") }
                }
                .disabled(busy || recorder != nil)
            }
        }
    }

    private var transcription: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            if !transcript.isEmpty {
                AppSectionCard(title: "转写结果") {
                    Text(transcript)
                        .font(DS.Font.body)
                        .textSelection(.enabled)
                    AppPrimaryCTA(title: "复制转写结果", icon: "doc.on.doc") {
                        UIPasteboard.general.string = transcript
                        Haptics.success()
                    }
                    Button("清除转写结果", role: .destructive) { transcript = "" }
                }
            }
            AppSectionCard(title: recorder != nil ? "正在录音" : "录音文件") {
                if recorder != nil {
                    Label("最多录制 60 秒", systemImage: "record.circle")
                        .foregroundStyle(DS.Palette.danger)
                    AppPrimaryCTA(title: "结束并保留", icon: "stop.fill") {
                        endRecording(keep: true)
                    }
                    Button("放弃本次录音", role: .destructive) { endRecording(keep: false) }
                } else if let recording {
                    Label(recording.name, systemImage: "waveform")
                        .font(DS.Font.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(recording.data.count), countStyle: .file))
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                    if !busy {
                        if transcript.isEmpty {
                            AppPrimaryCTA(title: "OpenAI 转文字", icon: "text.alignleft", action: confirmTranscription)
                        } else {
                            Button("重新转写", action: confirmTranscription)
                        }
                    }
                    Button { playData(recording.data) } label: { Label("试听", systemImage: "play.fill") }
                    Divider()
                    Button(action: beginRecording) { Label("重新录音", systemImage: "mic.fill") }
                    importRecording
                    Button("移除录音", role: .destructive) { self.recording = nil }
                } else {
                    Text("可录制 60 秒，或导入 20 MB 以内的音频。确认后发送给 OpenAI 转写。")
                        .font(DS.Font.body)
                        .foregroundStyle(.secondary)
                    if transcript.isEmpty {
                        AppPrimaryCTA(title: "开始录音", icon: "mic.fill", isDisabled: busy, action: beginRecording)
                    } else {
                        Button(action: beginRecording) { Label("开始录音", systemImage: "mic.fill") }
                    }
                    importRecording
                }
            }
            .disabled(busy && recorder == nil)
        }
    }

    private var importRecording: some View {
        Button { importing = true } label: {
            Label("导入录音", systemImage: "folder")
                .frame(minHeight: 44)
        }
        .accessibilityIdentifier("ai.speech.import")
    }

    private func confirmTranscription() {
        guard speechKey(for: .openAI) != nil else { return }
        consent = .transcribe
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
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { return }
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
        let utterance = AVSpeechUtterance(string: text)
        localSpeaker.delegate = playback
        playback.source = ObjectIdentifier(utterance)
        localSpeaker.speak(utterance)
    }

    private func playCloud() {
        guard let synthesized else { return }
        playData(synthesized)
    }

    private func playData(_ data: Data) {
        stopPlaying()
        do {
            let next = try AVAudioPlayer(data: data)
            next.delegate = playback
            guard next.play() else { message = "无法播放这段音频。"; return }
            player = next
            playback.source = ObjectIdentifier(next)
        } catch {
            message = "无法播放这段音频。"
        }
    }

    private func stopPlaying() {
        player?.stop()
        player = nil
        localSpeaker.stopSpeaking(at: .immediate)
        playback.source = nil
    }
}

@MainActor
private final class SpeechPlaybackStatus: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var source: ObjectIdentifier?

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finished(ObjectIdentifier(player))
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finished(ObjectIdentifier(player))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    private nonisolated func finished(_ id: ObjectIdentifier) {
        Task { @MainActor in
            if self.source == id { self.source = nil }
        }
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
