import AVFoundation
import SwiftUI

@MainActor

struct AILiveCallView: View {
    @Environment(\.scenePhase) private var phase
    @StateObject private var call = AILiveCallController()
    @State private var model: AILiveProtocol.Model? = AILiveProtocol.models.first
    @State private var confirmation = false
    @State private var showingKey = false
    @State private var keyAvailable = false

    var body: some View {
        Form {
            Section {
                Picker("实时语音模型", selection: $model) {
                    ForEach(AILiveProtocol.models) { option in
                        Text(option.displayName).tag(Optional(option))
                    }
                }
                .disabled(call.active)
                if !keyAvailable && !call.active {
                    Button("填写 OpenAI API Key") { showingKey = true }
                }
                Label(call.status, systemImage: call.connected ? "waveform.circle" : "phone")
                    .accessibilityIdentifier("ai.live.status")
                if call.active {
                    if call.connected {
                        Button(call.muted ? "取消静音" : "麦克风静音") { call.toggleMute() }
                            .accessibilityIdentifier("ai.live.mute")
                    }
                    Button("挂断", role: .destructive) { call.hangUp() }
                        .accessibilityIdentifier("ai.live.end")
                } else {
                    Button("开始实时语音") {
                        if Keychain.providerChatAPIKey(.openAI) != nil {
                            confirmation = true
                        } else {
                            showingKey = true
                        }
                    }
                    .disabled(model == nil)
                    .accessibilityIdentifier("ai.live.start")
                }
            } header: { Text("OpenAI Realtime") } footer: {
                Text("和 AI 通话，不是拨打电话。在通话页面内实时传送麦克风声音，包括环境声，可能产生费用。不会自动发送值班资料，App 不保存录音或文字。离开页面、锁屏或中断时结束通话。单次最多 10 分钟。")
            }
        }
        .navigationTitle("实时语音通话")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            keyAvailable = Keychain.providerChatAPIKey(.openAI) != nil
            call.setForeground(phase == .active)
        }
        .onDisappear { call.hangUp() }
        .onChange(of: phase) { newPhase in
            call.setForeground(newPhase == .active)
            if newPhase == .background || (newPhase != .active && call.connected) {
                call.hangUp(reason: "已在离开前台时挂断。")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: value) == .began, call.active else { return }
            call.hangUp(reason: "系统中断了音频，通话已结束。")
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable,
                  call.connected else { return }
            call.hangUp(reason: "音频设备已断开，通话已结束。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange)) { notification in
            call.audioConfigurationChanged(notification.object)
        }
        .sheet(isPresented: $showingKey) {
            ProviderKeyView(provider: .openAI) { keyAvailable = $0 }
        }
        .alert("开始向 OpenAI 传送麦克风声音？", isPresented: $confirmation) {
            Button("开始通话") {
                guard phase == .active, let model, let key = Keychain.providerChatAPIKey(.openAI) else { return }
                call.begin(model: model, apiKey: key)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你和附近的声音都可能包含在实时音频中。仅在获准的环境中使用，通话按你的 OpenAI API 用量计费。")
        }
    }
}

/// Lock is used only to gate real-time data enqueue; it never waits on the network.
private struct LiveCaptureFrame: Sendable {
    let bytes: Data
    let epoch: UInt64
}

private final class LiveCaptureGate: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed = true
    private var epoch: UInt64 = 0

    func set(_ active: Bool) {
        lock.lock()
        allowed = active
        epoch &+= 1
        lock.unlock()
    }

    func isCurrent(_ candidate: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return allowed && candidate == epoch
    }

    func enqueue(_ frame: Data, to sink: AsyncStream<LiveCaptureFrame>.Continuation) {
        lock.lock()
        defer { lock.unlock() }
        guard allowed else { return }
        if case .dropped = sink.yield(.init(bytes: frame, epoch: epoch)) { sink.finish() }
    }
}

private final class LiveSocketPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
private final class AILiveCallController: ObservableObject {
    @Published private(set) var status = "未通话"
    @Published private(set) var active = false
    @Published private(set) var connected = false
    @Published private(set) var muted = false

    private struct Output {
        let item: String
        let contentIndex: Int
        var sentSamples: Int
        var finishedStreaming = false
    }

    private var id: UUID?
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var startupOrReader: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var connectDeadline: Task<Void, Never>?
    private var callDeadline: Task<Void, Never>?
    private var capture: AsyncStream<LiveCaptureFrame>.Continuation?
    private var captureGate: LiveCaptureGate?
    private let audio = AILiveAudio()
    private var output: Output?
    private var cutItems = Set<String>()
    private var foreground = false
    private var userSpeaking = false

    func setForeground(_ value: Bool) { foreground = value }

    func begin(model: AILiveProtocol.Model, apiKey: String) {
        guard !active else { return }
        let generation = UUID()
        id = generation
        active = true
        status = "等待麦克风授权…"
        startupOrReader = Task { @MainActor [weak self] in
            guard await AILiveAudio.requestMicrophonePermission() else {
                self?.fail(generation, "未开启麦克风权限。可在系统设置中允许。")
                return
            }
            guard let self, self.id == generation, !Task.isCancelled else { return }
            self.status = "正在连接 OpenAI…"
            self.startConnectTimer(generation)
            do {
                let mint = try AILiveProtocol.tokenRequest(model: model, apiKey: apiKey)
                let bytes = try await AIProviderToolHTTP.data(for: mint, provider: .openAI, maxBytes: 32_768)
                guard self.id == generation, !Task.isCancelled else { return }
                let token = try AILiveProtocol.parseToken(bytes)
                let handshake = try AILiveProtocol.webSocketRequest(model: model, token: token)
                guard let socketURL = handshake.url else { throw MultiProviderAIError.invalidRequest }
                try await self.runSocket(socketURL, protocols: AILiveProtocol.webSocketProtocols(token: token),
                                         generation: generation)
            } catch is CancellationError {
                self.fail(generation, "连接已取消。")
            } catch let error as AILiveProtocolError {
                self.fail(generation, error.errorDescription ?? "实时语音协议出错。")
            } catch let error as MultiProviderAIError {
                self.fail(generation, error.errorDescription ?? "未能连接 OpenAI 实时语音。")
            } catch {
                self.fail(generation, "实时语音连接中断。请检查网络、Key 的实时语音权限或额度。")
            }
        }
    }

    private func runSocket(_ url: URL, protocols: [String], generation: UUID) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 660
        let session = URLSession(configuration: config, delegate: LiveSocketPolicy(), delegateQueue: nil)
        self.session = session
        let socket = session.webSocketTask(with: url, protocols: protocols)
        socket.maximumMessageSize = AILiveProtocol.maximumServerEventBytes
        self.socket = socket
        socket.resume()
        while !Task.isCancelled, id == generation {
            let packet = try await socket.receive()
            guard !Task.isCancelled, id == generation else { break }
            let bytes: Data
            switch packet {
            case .string(let string): bytes = Data(string.utf8)
            case .data(let data): bytes = data
            @unknown default: continue
            }
            try await handle(AILiveProtocol.parse(bytes), socket: socket, generation: generation)
        }
    }

    private func handle(_ event: AILiveProtocol.ServerEvent, socket: URLSessionWebSocketTask, generation: UUID) async throws {
        switch event {
        case .sessionCreated:
            if !connected { try await send(AILiveProtocol.sessionUpdate(), to: socket) }
        case .sessionReady:
            guard !connected else { return }
            guard foreground else {
                fail(generation, "通话必须在前台开始，请回到页面重试。")
                return
            }
            connectDeadline?.cancel()
            connectDeadline = nil
            do { try startAudio(socket, generation: generation) }
            catch { fail(generation, "无法打开通话音频。检查麦克风或音频设备后再试。"); return }
            connected = true
            status = "通话中 · 可以说话"
            callDeadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 600_000_000_000) } catch { return }
                self?.fail(generation, "已达到本次 10 分钟上限。")
            }
        case .audioChunk(let frame, let item, let index):
            guard connected, !cutItems.contains(item) else { return }
            guard !userSpeaking else { rememberCutItem(item); return }
            if output?.item != item || output?.contentIndex != index {
                audio.resetPlayback()
                output = Output(item: item, contentIndex: index, sentSamples: 0)
            }
            do { try audio.play(frame) }
            catch { fail(generation, "通话音频播放中断，请重新拨打。"); return }
            output?.sentSamples += frame.count / 2
            status = "通话中 · AI 正在说话"
        case .userSpeechStarted:
            userSpeaking = true
            let current = output
            let played = audio.playedMilliseconds()
            audio.resetPlayback()
            output = nil
            status = muted ? "通话中 · 麦克风已静音" : "通话中 · 正在听你说话"
            if let current {
                rememberCutItem(current.item)
                let queuedDuration = current.sentSamples / 24
                if !current.finishedStreaming || played < queuedDuration {
                    try await send(AILiveProtocol.truncate(itemID: current.item, contentIndex: current.contentIndex,
                                                           audioEndMS: max(0, played)), to: socket)
                }
            }
        case .userSpeechStopped:
            userSpeaking = false
            status = muted ? "通话中 · 麦克风已静音" : "通话中 · 等待回答"
        case .audioDone(let item, let index):
            if output?.item == item, output?.contentIndex == index {
                output?.finishedStreaming = true
            }
        case .responseDone:
            if !userSpeaking { status = muted ? "通话中 · 麦克风已静音" : "通话中 · 可以继续说话" }
        case .failure(let error):
            fail(generation, error.errorDescription ?? "OpenAI 结束了实时语音通话。")
        case .unhandled:
            break
        }
    }

    private func rememberCutItem(_ item: String) {
        if cutItems.count >= 64 { cutItems.removeAll(keepingCapacity: true) }
        cutItems.insert(item)
    }

    private func startAudio(_ socket: URLSessionWebSocketTask, generation: UUID) throws {
        var continuation: AsyncStream<LiveCaptureFrame>.Continuation?
        let stream = AsyncStream<LiveCaptureFrame>(bufferingPolicy: .bufferingNewest(12)) { continuation = $0 }
        guard let sink = continuation else { return }
        let gate = LiveCaptureGate()
        capture = sink
        captureGate = gate
        try audio.start { bytes in gate.enqueue(bytes, to: sink) }
        sender = Task { @MainActor [weak self] in
            do {
                for await frame in stream {
                    guard let self, !Task.isCancelled, self.id == generation else { return }
                    if self.foreground, !self.muted, gate.isCurrent(frame.epoch) {
                        try await self.send(AILiveProtocol.appendPCM(frame.bytes), to: socket)
                    }
                }
                guard !Task.isCancelled else { return }
                self?.fail(generation, "网络太慢，通话已结束，避免积压麦克风音频。")
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(generation, "无法继续传送语音，通话已结束。")
            }
        }
    }

    private func send(_ bytes: Data, to socket: URLSessionWebSocketTask) async throws {
        try await socket.send(.string(String(decoding: bytes, as: UTF8.self)))
    }

    func audioConfigurationChanged(_ engine: Any?) {
        guard connected, audio.ownsEngine(engine) else { return }
        hangUp(reason: "系统更改了音频设备，通话已结束。")
    }

    func toggleMute() {
        guard connected else { return }
        muted = !muted
        captureGate?.set(!muted)
        status = muted ? "通话中 · 麦克风已静音" : "通话中 · 可以说话"
    }

    private func startConnectTimer(_ generation: UUID) {
        connectDeadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            self?.fail(generation, "连接超时。请检查网络后重试。")
        }
    }

    private func fail(_ generation: UUID, _ reason: String) {
        guard id == generation else { return }
        hangUp(reason: reason)
    }

    func hangUp(reason: String = "通话已结束") {
        guard active else { return }
        id = nil
        captureGate?.set(false)
        captureGate = nil
        sender?.cancel()
        sender = nil
        capture?.finish()
        capture = nil
        audio.stop()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        startupOrReader?.cancel()
        startupOrReader = nil
        connectDeadline?.cancel()
        connectDeadline = nil
        callDeadline?.cancel()
        callDeadline = nil
        output = nil
        cutItems.removeAll()
        userSpeaking = false
        connected = false
        muted = false
        active = false
        status = reason
    }
}
