import AVFoundation
import Network
import SwiftUI

enum AILiveCallPhase: Equatable {
    case idle
    case connecting
    case listening
    case speaking
    case disconnected

    var title: String {
        switch self {
        case .idle: return "未通话"
        case .connecting: return "连接中"
        case .listening: return "正在听"
        case .speaking: return "AI 正在说"
        case .disconnected: return "连接中断"
        }
    }
}

struct AILiveVoiceTelemetry: Equatable {
    var micCaptured = false
    var audioSent = false
    var serverVADStopped = false
    var firstAudioReceived = false
    var speakerPlaying = false
    var firstPlaybackMS: Int?
    var outputRoute = "系统默认输出"

}

@MainActor
struct AILiveCallView: View {
    var autoConnectOnAppear: Bool = false
    var onDismiss: (() -> Void)? = nil

    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var wmStore = WuMindStore.shared
    @StateObject private var call = AILiveCallController()
    @State private var model: AILiveProtocol.Model? = AILiveProtocol.models.first(where: { $0.id == "gpt-realtime" }) ?? AILiveProtocol.models.first
    @State private var confirmation = false
    @State private var showingKey = false
    @State private var keyAvailable = false
    @State private var didAttemptAutoConnect = false
    @State private var showPipelineTrace = false

    private var phaseColor: Color {
        switch call.callPhase {
        case .speaking: return DS.Palette.accent
        case .listening: return DS.Palette.success
        case .disconnected: return DS.Palette.warning
        case .idle, .connecting: return DS.Palette.info
        }
    }

    private var useManagedGateway: Bool {
        wmStore.channel == .managed
    }

    private var activeRouteLabel: String {
        if useManagedGateway {
            return wmStore.isBillingExempt ? "WUMIND 内置网关（管理员免扣）" : "WUMIND 内置网关实时通道"
        }
        if let relayHost = AIProviderEndpoints.displayHost(for: .openAI) {
            return "\(relayHost) 直连 Bearer WebSocket"
        }
        return "OpenAI 官方 Realtime 临时令牌通道"
    }

    private var isReadyToCall: Bool {
        useManagedGateway ? wmStore.hasGatewayURL : keyAvailable
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                if let onDismiss {
                    HStack {
                        Text("实时语音").font(DS.Font.title)
                        Spacer()
                        Button("关闭") {
                            call.hangUp()
                            onDismiss()
                        }
                        .accessibilityIdentifier("ai.live.close")
                    }
                }
                AppSectionCard(tint: phaseColor) {
                    HStack(spacing: DS.Space.m) {
                        Image(systemName: orbIconName)
                            .font(.title)
                            .foregroundStyle(phaseColor)
                            .frame(width: 56, height: 56)
                            .background(phaseColor.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(call.callPhase.title)
                                .font(DS.Font.title)
                                .accessibilityIdentifier("ai.live.phaseTitle")
                            Text(call.status).font(DS.Font.body).foregroundStyle(.secondary)
                                .accessibilityIdentifier("ai.live.status")
                        }
                    }
                    Divider()
                    LabeledContent("调用通道", value: activeRouteLabel)
                    LabeledContent("音频输出", value: call.active || call.callPhase == .disconnected
                                   ? call.telemetry.outputRoute : "系统当前设备")
                    if call.connected {
                        Button(call.muted ? "取消静音" : "麦克风静音") { call.toggleMute() }
                            .accessibilityIdentifier("ai.live.mute")
                    }
                }
                .font(DS.Font.body)
                if !isReadyToCall || call.needsMicrophoneSettings {
                    AppSectionCard {
                        if call.needsMicrophoneSettings {
                            Button("打开系统设置，允许麦克风") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        } else if useManagedGateway {
                            Text("内置通道尚未配置，请联系管理员。")
                                .accessibilityIdentifier("ai.live.unconfiguredBanner")
                        } else {
                            Button("配置 OpenAI 语音凭据") { showingKey = true }
                                .accessibilityIdentifier("ai.live.configureKey")
                        }
                    }
                    .font(DS.Font.body)
                }
                if !call.liveTranscript.isEmpty {
                    AppSectionCard(title: "实时字幕") {
                        Text(call.liveTranscript).font(DS.Font.body).textSelection(.enabled)
                    }
                    .accessibilityIdentifier("ai.live.transcript")
                }
                AppSectionCard {
                    Picker("语音模型", selection: $model) {
                        ForEach(useManagedGateway ? AILiveProtocol.managedModels : AILiveProtocol.models) { item in Text(item.displayName).tag(Optional(item)) }
                    }
                    .pickerStyle(.menu)
                    .disabled(call.active)
                    DisclosureGroup(isExpanded: $showPipelineTrace) {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            stageDot("已采集麦克风音频", ok: call.telemetry.micCaptured)
                                .accessibilityIdentifier("ai.live.micEvidence")
                            stageDot("已发送音频", ok: call.telemetry.audioSent)
                            stageDot("服务端检测到停顿", ok: call.telemetry.serverVADStopped)
                            stageDot("已收到回复音频", ok: call.telemetry.firstAudioReceived)
                            stageDot("已启动播放", ok: call.telemetry.speakerPlaying)
                            if let ms = call.telemetry.firstPlaybackMS {
                                Text("连接到首次启动播放  \(ms) ms")
                            }
                        }
                        .font(DS.Font.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text("通话诊断").accessibilityIdentifier("ai.live.pipelineTrace")
                    }
                }
                if !call.active {
                    Text("扬声器和蓝牙耳机跟随系统音频输出。蓝牙设备未出现时，可先在系统蓝牙设置中重新连接。")
                        .font(DS.Font.caption).foregroundStyle(.secondary)
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: DS.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            AppPrimaryCTA(
                title: call.active ? "挂断" : (call.callPhase == .disconnected ? "重新连接" : "开始实时语音"),
                icon: call.active ? "phone.down.fill" : "phone.fill",
                tint: call.active ? DS.Palette.danger : DS.Palette.accent,
                isDisabled: !call.active && (!isReadyToCall || model == nil)
            ) {
                if call.active { call.hangUp(reason: "已挂断实时语音") }
                else { confirmation = true }
            }
            .accessibilityIdentifier(call.active ? "ai.live.end" : (call.callPhase == .disconnected ? "ai.live.retry" : "ai.live.start"))
            .padding(DS.Space.m)
            .frame(maxWidth: DS.readableWidth)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
        .appBackground()
        .navigationTitle("实时语音通话")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            keyAvailable = !useManagedGateway && Keychain.providerChatAPIKey(.openAI) != nil
            call.setForeground(phase == .active)
            if autoConnectOnAppear && !didAttemptAutoConnect && isReadyToCall && phase == .active {
                didAttemptAutoConnect = true
                if useManagedGateway || wmStore.selectedProvider == .openAI {
                    startSelectedCall()
                } else {
                    confirmation = true
                }
            }
        }
        .onDisappear { call.hangUp() }
        .onChange(of: wmStore.activeDataDestinationLabel) { _ in call.hangUp(reason: "调用通道已改变，请重新连接。") }
        .onChange(of: wmStore.managedAccountID) { _ in
            if call.connected && useManagedGateway { call.hangUp(reason: "登录账号已改变，请重新连接。") }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)) { _ in
            if call.active { call.hangUp(reason: "系统音频服务已重置，请重新连接。", isFailure: true) }
        }
        .onChange(of: phase) { newPhase in
            call.setForeground(newPhase == .active)
            if newPhase == .background || (newPhase != .active && call.connected) {
                call.hangUp(reason: "已在离开前台时挂断。")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: value) == .began, call.active else { return }
            call.hangUp(reason: "系统中断了音频，通话已结束。", isFailure: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  call.connected else { return }
            let reason = AVAudioSession.RouteChangeReason(rawValue: value)
            if reason == .oldDeviceUnavailable || reason == .newDeviceAvailable || reason == .override {
                call.handleAudioRouteRecovery()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange)) { notification in
            call.audioConfigurationChanged(notification.object)
        }
        .sheet(isPresented: $showingKey) {
            ProviderKeyView(provider: .openAI) { keyAvailable = $0 }
        }
        .alert("开始实时语音通话？", isPresented: $confirmation) {
            Button("开始通话") {
                startSelectedCall()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前通道：\(activeRouteLabel)。你和附近的声音会通过加密 WebSocket 实时传输，离开页面自动断开。")
        }
    }

    private var orbIconName: String {
        switch call.callPhase {
        case .speaking: return "waveform.and.magnifyingglass"
        case .listening: return call.muted ? "mic.slash.fill" : "waveform"
        case .disconnected: return "exclamationmark.triangle.fill"
        case .idle, .connecting: return "phone.waveform.fill"
        }
    }

    private func stageDot(_ label: String, ok: Bool) -> some View {
        Label(label, systemImage: ok ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(ok ? DS.Palette.success : Color.secondary)
            .accessibilityValue(ok ? "已完成" : "未完成")
    }

    private func startSelectedCall() {
        guard phase == .active, isReadyToCall, let model else { return }
        if useManagedGateway {
            call.beginManaged(model: model, store: wmStore)
        } else if let key = Keychain.providerChatAPIKey(.openAI) {
            call.beginOwnAPI(model: model, apiKey: key, customBaseURL: AIProviderEndpoints.baseURL(for: .openAI))
        }
    }
}

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
protocol AILiveConnection: AnyObject {
    func read() async throws -> URLSessionWebSocketTask.Message
    func write(_ data: Data) async throws
    func close()
}

@MainActor
private final class LiveNetworkConnection: AILiveConnection {
    let session: URLSession
    let socket: URLSessionWebSocketTask
    private let monitor = NWPathMonitor()

    init(request: URLRequest, protocols: [String]?) throws {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 660
        let session = URLSession(configuration: config, delegate: LiveSocketPolicy(), delegateQueue: nil)
        self.session = session
        if let protocols, let url = request.url {
            socket = session.webSocketTask(with: url, protocols: protocols)
        } else {
            socket = session.webSocketTask(with: request)
        }
        socket.maximumMessageSize = AILiveProtocol.maximumServerEventBytes
        let callSocket = socket
        monitor.pathUpdateHandler = { path in
            if path.status == .unsatisfied {
                callSocket.cancel(with: .goingAway, reason: nil)
            }
        }
        monitor.start(queue: DispatchQueue(label: "wumind.voice.network"))
        socket.resume()
    }

    func read() async throws -> URLSessionWebSocketTask.Message { try await socket.receive() }
    func write(_ data: Data) async throws { try await socket.send(.string(String(decoding: data, as: UTF8.self))) }
    func close() {
        monitor.cancel()
        socket.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}

@MainActor
final class AILiveCallController: ObservableObject {
    @Published private(set) var callPhase: AILiveCallPhase = .idle
    @Published private(set) var status = "点击下方开始实时语音通话"
    @Published private(set) var liveTranscript = ""
    @Published private(set) var active = false
    @Published private(set) var connected = false
    @Published private(set) var muted = false
    @Published private(set) var telemetry = AILiveVoiceTelemetry()

    private struct Output {
        let item: String
        let contentIndex: Int
        var sentSamples: Int
        var finishedStreaming = false
    }

    private var id: UUID?
    private var socket: AILiveConnection?
    private var startupOrReader: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var connectDeadline: Task<Void, Never>?
    private var callDeadline: Task<Void, Never>?
    private var audioRecoveryTask: Task<Void, Never>?
    private var capture: AsyncStream<LiveCaptureFrame>.Continuation?
    private var captureGate: LiveCaptureGate?
    private let audio: AILiveAudioIO
    private let permission: @MainActor () async -> Bool
    private let connect: @MainActor (URLRequest, [String]?) throws -> AILiveConnection
    private let replyTimeout: UInt64
    private var replyDeadline: Task<Void, Never>?
    private var captureDeadline: Task<Void, Never>?
    private var startedAt: UInt64 = 0
    @Published private(set) var needsMicrophoneSettings = false

    init(audio: AILiveAudioIO? = nil,
         permission: @escaping @MainActor () async -> Bool = { await AILiveAudio.requestMicrophonePermission() },
         replyTimeout: UInt64 = 20_000_000_000,
         connect: @escaping @MainActor (URLRequest, [String]?) throws -> AILiveConnection = {
             try LiveNetworkConnection(request: $0, protocols: $1)
         }) {
        self.audio = audio ?? AILiveAudio()
        self.permission = permission
        self.replyTimeout = replyTimeout
        self.connect = connect
    }
    private var output: Output?
    private var cutItems = Set<String>()
    private var foreground = false
    private var userSpeaking = false
    private var omitNoiseReduction = false
    private var sentSessionUpdate = false

    func setForeground(_ value: Bool) { foreground = value }

    /// Connects through WUMIND Managed Billing Gateway (`wss://<gateway>/v1/realtime?model=...`).
    func beginManaged(model: AILiveProtocol.Model, store: WuMindStore) {
        guard !active else { return }
        let generation = UUID()
        id = generation
        active = true
        connected = false
        sentSessionUpdate = false
        liveTranscript = ""
        telemetry = AILiveVoiceTelemetry()
        needsMicrophoneSettings = false
        omitNoiseReduction = true
        callPhase = .connecting
        status = "等待麦克风授权…"

        startupOrReader = Task { @MainActor [weak self] in
            guard let self else { return }
            let granted = await self.permission()
            guard self.id == generation, !Task.isCancelled else { return }
            guard granted else {
                self.needsMicrophoneSettings = true
                self.fail(generation, "未开启麦克风权限。请在系统设置中允许访问麦克风。")
                return
            }
            self.status = "正在连接 WUMIND 实时语音网关…"
            self.startConnectTimer(generation)
            do {
                let userToken = try await store.ensureManagedAccount()
                guard self.id == generation, !Task.isCancelled else { return }
                guard store.managedSessionToken == userToken else { throw WuMindGatewayClient.GatewayError.unauthorized }
                let gwURL = try WuMindGatewayClient.normalizedGatewayURL(store.gatewayBaseURL)
                let req = try AILiveProtocol.directWebSocketRequest(
                    model: model,
                    baseURL: gwURL.absoluteString,
                    bearerToken: userToken
                )
                try await self.runSocket(req, generation: generation)
            } catch is CancellationError {
                self.fail(generation, "连接已取消")
            } catch let error as LocalizedError {
                self.fail(generation, (error as? AILiveProtocolError) == .unauthorized ? "内置语音授权失败，请重新登录或联系管理员。" : (error.errorDescription ?? "WUMIND 实时语音连接失败。"))
            } catch {
                self.fail(generation, "WUMIND 实时语音连接中断（\(error.localizedDescription)）。")
            }
        }
    }

    /// Connects directly using user's Own API Key (AIHubMix Bearer WS or OpenAI ephemeral client_secret).
    func beginOwnAPI(model: AILiveProtocol.Model, apiKey: String, customBaseURL: String?) {
        guard !active else { return }
        let generation = UUID()
        id = generation
        active = true
        connected = false
        sentSessionUpdate = false
        liveTranscript = ""
        telemetry = AILiveVoiceTelemetry()
        needsMicrophoneSettings = false
        let cleanCustomBase = customBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let useDirectRelay = cleanCustomBase?.isEmpty == false
        omitNoiseReduction = useDirectRelay
        callPhase = .connecting
        status = "等待麦克风授权…"

        startupOrReader = Task { @MainActor [weak self] in
            guard let self else { return }
            let granted = await self.permission()
            guard self.id == generation, !Task.isCancelled else { return }
            guard granted else {
                self.needsMicrophoneSettings = true
                self.fail(generation, "未开启麦克风权限。请在系统设置中允许访问麦克风。")
                return
            }
            self.status = useDirectRelay ? "正在连接中转实时语音（Bearer WS）…" : "正在连接 OpenAI Realtime…"
            self.startConnectTimer(generation)
            do {
                if let baseStr = cleanCustomBase, !baseStr.isEmpty {
                    let directReq = try AILiveProtocol.directWebSocketRequest(
                        model: model,
                        baseURL: baseStr,
                        bearerToken: apiKey
                    )
                    try await self.runSocket(directReq, generation: generation)
                } else {
                    let mint = try AILiveProtocol.tokenRequest(model: model, apiKey: apiKey)
                    let (bytes, _) = try await AIProviderToolHTTP.dataWithDiagnostics(
                        for: mint,
                        provider: .openAI,
                        maxBytes: 32_768
                    )
                    guard self.id == generation, !Task.isCancelled else { return }
                    let token = try AILiveProtocol.parseToken(bytes)
                    let handshake = try AILiveProtocol.webSocketRequest(model: model, token: token)
                    try await self.runSocket(handshake, protocols: AILiveProtocol.webSocketProtocols(token: token),
                                                     generation: generation)
                }
            } catch is CancellationError {
                self.fail(generation, "连接已取消")
            } catch let error as AILiveProtocolError {
                self.fail(generation, error.errorDescription ?? "实时语音协议出错。")
            } catch let error as AIProviderToolDiagnosticError {
                self.fail(generation, error.errorDescription ?? "实时语音接口返回错误。")
            } catch let error as MultiProviderAIError {
                self.fail(generation, error.errorDescription ?? "未能连接实时语音服务。")
            } catch {
                self.fail(generation, "实时语音连接中断（\(error.localizedDescription)）。请检查网络、模型（\(model.id)）及实时语音权限。")
            }
        }
    }

    private func runSocket(_ request: URLRequest, protocols: [String]? = nil, generation: UUID) async throws {
        guard id == generation, !Task.isCancelled else { return }
        let socket = try connect(request, protocols)
        self.socket = socket
        while !Task.isCancelled, id == generation {
            let packet = try await socket.read()
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

    private func handle(_ event: AILiveProtocol.ServerEvent, socket: AILiveConnection, generation: UUID) async throws {
        switch event {
        case .sessionCreated:
            if !sentSessionUpdate {
                sentSessionUpdate = true
                status = "会话已创建，正在协商 24kHz PCM 音频与 VAD…"
                try await send(AILiveProtocol.sessionUpdate(omitNoiseReduction: omitNoiseReduction), to: socket)
            }
        case .sessionReady:
            guard sentSessionUpdate else { throw AILiveProtocolError.invalidSession }
            guard !connected else { return }
            guard foreground else {
                fail(generation, "通话必须在前台开始，请回到页面重试。")
                return
            }
            connectDeadline?.cancel()
            connectDeadline = nil
            do { try startAudio(socket, generation: generation) }
            catch { fail(generation, "无法打开通话音频。请检查麦克风或蓝牙/扬声器设备后再试。"); return }
            connected = true
            telemetry.outputRoute = audio.activeOutputRouteDescription
            callPhase = .listening
            status = "已就绪 · 等待 AI 问候或直接开口说话"

            // Strictly AFTER server session.updated AND local AVAudioEngine playback readiness:
            // trigger ONE active greeting ("你好，今天想聊什么？") without repeating on route recovery.
            awaitReply(generation)
            do { try await send(AILiveProtocol.responseCreateGreeting(), to: socket) }
            catch { fail(generation, "问候请求发送失败，请检查连接后重试。"); return }
            guard id == generation else { return }

            callDeadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 600_000_000_000) } catch { return }
                self?.fail(generation, "已达到本次 10 分钟上限。")
            }
        case .audioChunk(let frame, let item, let index):
            guard connected, !cutItems.contains(item) else { return }
            guard !userSpeaking else { rememberCutItem(item); return }
            if audio.isReconfiguring { return }
            if !telemetry.firstAudioReceived {
                telemetry.firstAudioReceived = true
            }
            if output?.item != item || output?.contentIndex != index {
                audio.resetPlayback()
                output = Output(item: item, contentIndex: index, sentSamples: 0)
            }
            do { try audio.play(frame) }
            catch AILiveAudio.Issue.unavailable {
                if let currentID = id {
                    scheduleAudioRecovery(generation: currentID)
                }
                return
            } catch {
                fail(generation, (error as? LocalizedError)?.errorDescription ?? "通话音频播放中断，请重新连接。")
                return
            }
            output?.sentSamples += frame.count / 2
            replyDeadline?.cancel()
            replyDeadline = nil
            if callPhase != .speaking {
                callPhase = .speaking
                status = "AI 正在回复，可以开口打断。"
            }
        case .transcriptDelta(let delta):
            if liveTranscript.count > 600 {
                liveTranscript = String(liveTranscript.suffix(400))
            }
            liveTranscript += delta
        case .transcriptDone:
            if !liveTranscript.isEmpty && !liveTranscript.hasSuffix("\n") {
                liveTranscript += "\n"
            }
        case .userSpeechStarted:
            userSpeaking = true
            replyDeadline?.cancel()
            let current = output
            let played = audio.playedMilliseconds()
            audio.resetPlayback()
            output = nil
            callPhase = .listening
            status = muted ? "麦克风已静音" : "检测到你正在说话…"
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
            awaitReply(generation)
            telemetry.serverVADStopped = true
            callPhase = .listening
            status = muted ? "麦克风已静音" : "服务端已判停 · 等待 AI 语音回复…"
        case .audioDone(let item, let index):
            if output?.item == item, output?.contentIndex == index {
                output?.finishedStreaming = true
            }
        case .responseDone:
            output?.finishedStreaming = true
            if !userSpeaking && !audio.hasPendingPlayback && replyDeadline == nil {
                callPhase = .listening
                status = muted ? "麦克风已静音" : "请继续说话"
            }
        case .failure(let error):
            fail(generation, error.errorDescription ?? "实时语音服务端结束了通话。")
        case .unhandled:
            break
        }
    }

    private func rememberCutItem(_ item: String) {
        if cutItems.count >= 64 { cutItems.removeAll(keepingCapacity: true) }
        cutItems.insert(item)
    }

    private func startAudio(_ socket: AILiveConnection, generation: UUID) throws {
        var continuation: AsyncStream<LiveCaptureFrame>.Continuation?
        let stream = AsyncStream<LiveCaptureFrame>(bufferingPolicy: .bufferingNewest(12)) { continuation = $0 }
        guard let sink = continuation else { return }
        let gate = LiveCaptureGate()
        capture = sink
        captureGate = gate
        audio.onPlaybackStarted = { [weak self] in
            guard let self, self.id == generation else { return }
            if self.telemetry.firstPlaybackMS == nil {
                self.telemetry.firstPlaybackMS = Int((DispatchTime.now().uptimeNanoseconds - self.startedAt) / 1_000_000)
            }
            self.telemetry.speakerPlaying = true
            self.telemetry.outputRoute = self.audio.activeOutputRouteDescription
        }
        audio.onPlaybackDrained = { [weak self] in
            guard let self, self.id == generation, self.callPhase == .speaking,
                  self.output?.finishedStreaming == true else { return }
            self.callPhase = .listening
            self.status = self.muted ? "麦克风已静音" : "请继续说话"
        }
        try audio.start { bytes in gate.enqueue(bytes, to: sink) }
        awaitCapture(generation)
        sender = Task { @MainActor [weak self] in
            do {
                for await frame in stream {
                    guard let self, !Task.isCancelled, self.id == generation else { return }
                    if !self.telemetry.micCaptured && !frame.bytes.isEmpty {
                        self.captureDeadline?.cancel()
                        self.telemetry.micCaptured = true
                    }
                    if self.foreground, !self.muted, gate.isCurrent(frame.epoch) {
                        try await self.send(AILiveProtocol.appendPCM(frame.bytes), to: socket)
                        guard self.id == generation, !Task.isCancelled else { return }
                        if !self.telemetry.audioSent {
                            self.telemetry.audioSent = true
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                self?.fail(generation, "网络太慢，通话已结束，避免积压麦克风音频。")
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(generation, "无法继续传送语音，连接已中断。")
            }
        }
    }

    private func send(_ bytes: Data, to socket: AILiveConnection) async throws {
        try await socket.write(bytes)
    }

    func audioConfigurationChanged(_ engine: Any?) {
        guard connected, let generation = id, audio.ownsEngine(engine), !audio.isReconfiguring else { return }
        scheduleAudioRecovery(generation: generation)
    }

    func handleAudioRouteRecovery() {
        guard connected, let generation = id, !audio.isReconfiguring else { return }
        scheduleAudioRecovery(generation: generation)
    }

    private func scheduleAudioRecovery(generation: UUID) {
        audioRecoveryTask?.cancel()
        audioRecoveryTask = Task { @MainActor [weak self] in
            guard let self, self.id == generation, self.connected else { return }
            let recovered = await self.audio.reconfigureForRouteChange()
            guard !Task.isCancelled, self.id == generation, self.connected else { return }
            if recovered {
                self.telemetry.outputRoute = self.audio.activeOutputRouteDescription
                self.telemetry.micCaptured = false
                self.awaitCapture(generation)
                self.callPhase = .listening
                self.status = self.muted ? "麦克风已静音（音频路由已恢复）" : "音频设备已切换（\(self.telemetry.outputRoute)）· 请继续说话"
            } else {
                self.fail(generation, "音频设备切换后未能恢复麦克风，请点击重新连接。")
            }
        }
    }

    func toggleMute() {
        guard connected else { return }
        muted = !muted
        if muted { captureDeadline?.cancel() }
        else if let generation = id { telemetry.micCaptured = false; awaitCapture(generation) }
        captureGate?.set(!muted)
        status = muted ? "麦克风已静音" : "请继续说话"
    }

    private func awaitReply(_ generation: UUID) {
        replyDeadline?.cancel()
        let timeout = replyTimeout
        replyDeadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: timeout) } catch { return }
            self?.fail(generation, "等待语音回复超时。请检查网络和当前输出设备，重新连接。")
        }
    }

    private func awaitCapture(_ generation: UUID) {
        captureDeadline?.cancel()
        guard !muted else { return }
        captureDeadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            self?.fail(generation, "未收到麦克风输入。请检查麦克风或蓝牙设备后重新连接。")
        }
    }

    private func startConnectTimer(_ generation: UUID) {
        startedAt = DispatchTime.now().uptimeNanoseconds
        connectDeadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            self?.fail(generation, "连接超时。请检查网络、实时语音模型及上游通道配置后重试。")
        }
    }

    private func fail(_ generation: UUID, _ reason: String) {
        guard id == generation else { return }
        hangUp(reason: reason, isFailure: true)
    }

    func hangUp(reason: String = "通话已结束", isFailure: Bool = false) {
        guard active || isFailure else { return }
        id = nil
        audioRecoveryTask?.cancel()
        audioRecoveryTask = nil
        captureGate?.set(false)
        captureGate = nil
        sender?.cancel()
        sender = nil
        capture?.finish()
        capture = nil
        audio.onPlaybackStarted = nil
        audio.onPlaybackDrained = nil
        audio.stop()
        socket?.close()
        socket = nil
        replyDeadline?.cancel()
        replyDeadline = nil
        captureDeadline?.cancel()
        captureDeadline = nil
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
        callPhase = isFailure ? .disconnected : .idle
        status = reason
    }
}
