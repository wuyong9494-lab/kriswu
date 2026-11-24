import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct AISpeechToolView: View {
    @Environment(\.scenePhase) private var phase
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

    private var busy: Bool { activity != nil }
    private let importTypes: [UTType] = [.audio, .mpeg4Movie, .wav] +
        ["flac", "ogg", "webm", "m4a", "mp3"].compactMap { UTType(filenameExtension: $0) }

    var body: some View {
        Form {
            reading
            transcription
            if busy {
                Section {
                    ProgressView("处理中…")
                    Button("停止等待", role: .cancel) {
                        cancel()
                        message = "已停止等待。已经发出的请求可能产生用量。"
                    }
                }
            }
            if let message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
        }
        .modifier(AvoidTabBar())
        .navigationTitle("语音工具")
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
        Section {
            TextField("输入要朗读的文字，可用系统键盘听写", text: $script, axis: .vertical)
                .lineLimit(3...7)
                .disabled(busy || recorder != nil)
                .accessibilityIdentifier("ai.speech.script")
            Button("系统朗读（无需 API Key）") { playLocal() }
                .disabled(busy || recorder != nil || (try? AISpeechTool.cleanedScript(script)) == nil)
            Picker("xAI 合成音色", selection: $voice) {
                ForEach(AISpeechTool.Voice.allCases, id: \.self) { voice in
                    Text(voice.rawValue.capitalized).tag(voice)
                }
            }
            .disabled(busy || recorder != nil)
            Button("用 xAI 合成音频") {
                guard Keychain.providerChatAPIKey(.grok) != nil else {
                    message = "请先到「切换 AI → xAI Grok → 管理 API Key」填写自己的密钥。"
                    return
                }
                consent = .speak
            }
            .disabled(busy || recorder != nil || (try? AISpeechTool.cleanedScript(script)) == nil)
            if synthesized != nil {
                Button("播放 AI 合成音频") { playCloud() }.disabled(busy || recorder != nil)
                Button("保存 WAV 到文件") { exporting = true }.disabled(busy || recorder != nil)
            }
            Button("停止播放", role: .cancel) { stopPlaying() }
        } header: {
            Text("文字转语音")
        } footer: {
            Text("声音由系统或 AI 合成，不是真人。系统朗读使用设备可用的系统声音，没有 API 费用。键盘听写由你的系统设置管理。")
        }
    }

    private var transcription: some View {
        Section {
            if recorder != nil {
                Label("正在录音（最多 60 秒）", systemImage: "record.circle")
                Button("结束录音") { endRecording(keep: true) }
                Button("取消并删除录音", role: .destructive) { endRecording(keep: false) }
            } else {
                Button("开始录音") { beginRecording() }.disabled(busy)
            }
            Button("选取已有录音") { importing = true }
                .disabled(busy || recorder != nil)
                .accessibilityIdentifier("ai.speech.import")
            if let recording {
                Text(recording.name).lineLimit(2)
                Text(ByteCountFormatter.string(fromByteCount: Int64(recording.data.count), countStyle: .file))
                    .font(.footnote).foregroundStyle(.secondary)
                Button("试听录音") { playData(recording.data) }.disabled(busy || recorder != nil)
                Button("用 OpenAI 转写录音") {
                    guard Keychain.providerChatAPIKey(.openAI) != nil else {
                        message = "请先到「切换 AI → OpenAI / GPT → 管理 API Key」填写自己的密钥。"
                        return
                    }
                    consent = .transcribe
                }
                .disabled(busy || recorder != nil)
                Button("移除录音", role: .destructive) { self.recording = nil }.disabled(busy || recorder != nil)
            }
            if !transcript.isEmpty {
                Text(transcript).textSelection(.enabled)
                Button("清除转写文字", role: .destructive) { transcript = "" }.disabled(busy || recorder != nil)
            }
        } header: {
            Text("录音转文字")
        } footer: {
            Text("可录制最多 60 秒，或选择 20 MB 以内的音频。录制和选取时不上传；确认后才发送。不在后台录音。")
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

    private func synthesize() {
        guard let key = Keychain.providerChatAPIKey(.grok) else {
            message = "xAI API Key 不可用，请检查设置。"
            return
        }
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
        guard let key = Keychain.providerChatAPIKey(.openAI) else {
            message = "OpenAI API Key 不可用，请检查设置。"
            return
        }
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
