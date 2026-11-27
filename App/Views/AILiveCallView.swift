import AVFoundation
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
    var sentFramesCount = 0
    var receivedChunksCount = 0
    var outputRoute = "系统默认输出"

    mutating func reset() {
        micCaptured = false
        audioSent = false
        serverVADStopped = false
        firstAudioReceived = false
        speakerPlaying = false
        sentFramesCount = 0
        receivedChunksCount = 0
    }
}

@MainActor
struct AILiveCallView: View {
    var autoConnectOnAppear: Bool = false
    var onDismiss: (() -> Void)? = nil

    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var wmStore = WuMindStore.shared
    @StateObject private var call = AILiveCallController()
    @State private var model: AILiveProtocol.Model? = AILiveProtocol.models.first(where: { $0.id == "gpt-realtime" }) ?? AILiveProtocol.models.first
    @State private var confirmation = false
    @State private var showingKey = false
    @State private var keyAvailable = false
    @State private var orbPulse = false
    @State private var didAttemptAutoConnect = false
    @State private var showPipelineTrace = true

    private var isDark: Bool { colorScheme == .dark }
    private var stageBg: Color {
        isDark ? Color(red: 0.025, green: 0.032, blue: 0.05) : Color(red: 0.945, green: 0.96, blue: 0.98)
    }
    private var accent: Color {
        switch call.callPhase {
        case .speaking:
            return Color(red: 0.45, green: 0.34, blue: 0.98)
        case .listening:
            return Color(red: 0.12, green: 0.78, blue: 0.60)
        case .disconnected:
            return Color.orange
        case .idle, .connecting:
            return Color(red: 0.22, green: 0.52, blue: 0.96)
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
        ZStack {
            stageBg.ignoresSafeArea()
            RadialGradient(
                colors: [
                    accent.opacity(call.connected ? 0.30 : (isDark ? 0.18 : 0.10)),
                    Color.clear
                ],
                center: .center,
                startRadius: 24,
                endRadius: 320
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 16) {
                // Top Bar: Close (when fullScreenCover) + Model Picker + Config Key
                HStack(spacing: 8) {
                    if onDismiss != nil {
                        Button {
                            call.hangUp()
                            onDismiss?()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.primary)
                                .frame(width: 34, height: 34)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭实时语音")
                        .accessibilityIdentifier("ai.live.close")
                    }

                    Spacer(minLength: 0)

                    Menu {
                        ForEach(AILiveProtocol.models) { option in
                            Button {
                                Haptics.select()
                                model = option
                            } label: {
                                HStack {
                                    Text(option.displayName)
                                    if model == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isReadyToCall ? accent : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(model?.displayName ?? "选择实时语音模型")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(isDark ? 0.14 : 0.08), lineWidth: 0.8))
                    }
                    .tint(.primary)
                    .disabled(call.active)

                    if !useManagedGateway && !isReadyToCall && !call.active {
                        Button {
                            Haptics.tap()
                            showingKey = true
                        } label: {
                            Label("配置 Key", systemImage: "key.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.orange, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ai.live.configureKey")
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Explicit unconfigured prompt (NEVER silently degrades to ordinary voice Q&A!)
                if !isReadyToCall && !call.active {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("实时语音暂不可用", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                        Text(useManagedGateway ? "内置通道尚未配置，请联系管理员。" : "请点「配置 Key」保存所选服务商的实时语音凭据。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("ai.live.unconfiguredBanner")
                }

                Spacer(minLength: 6)

                // Breathing Voice Orb
                ZStack {
                    Circle()
                        .fill(accent.opacity(call.connected ? 0.16 : 0.08))
                        .frame(width: 210, height: 210)
                        .scaleEffect(orbPulse ? 1.12 : 0.94)
                        .animation(.easeInOut(duration: call.callPhase == .speaking ? 0.85 : (call.connected ? 1.3 : 2.6)).repeatForever(autoreverses: true), value: orbPulse)

                    Circle()
                        .fill(accent.opacity(call.connected ? 0.26 : 0.14))
                        .frame(width: 162, height: 162)
                        .scaleEffect(orbPulse ? 1.06 : 0.96)
                        .animation(.easeInOut(duration: call.callPhase == .speaking ? 0.7 : 1.1).repeatForever(autoreverses: true), value: orbPulse)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.65), Color.indigo.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 118, height: 118)
                        .shadow(color: accent.opacity(0.45), radius: 24, y: 10)
                        .overlay(
                            Group {
                                if call.callPhase == .connecting {
                                    ProgressView().tint(.white).scaleEffect(1.3)
                                } else {
                                    Image(systemName: orbIconName)
                                        .font(.system(size: 34, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                        )
                }

                // Truthful 4-State Status Header + Detail + Live Captions
                VStack(spacing: 6) {
                    Text(call.callPhase.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(call.callPhase == .disconnected ? .orange : .primary)
                        .accessibilityIdentifier("ai.live.phaseTitle")

                    Text(call.status)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("ai.live.status")

                    Text(call.connected ? "\(activeRouteLabel) · 输出：\(call.telemetry.outputRoute)" : activeRouteLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if !call.liveTranscript.isEmpty {
                        ScrollView {
                            Text(call.liveTranscript)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 88)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("ai.live.transcript")
                    }
                }

                // 5-Stage Live Pipeline Diagnostic Strip (never silent failure!)
                if call.active || call.callPhase == .disconnected || showPipelineTrace {
                    pipelineTraceStrip
                        .padding(.horizontal, 18)
                }

                Spacer(minLength: 8)

                // Floating Frosted-Glass Call Controls Dock
                VStack(spacing: 12) {
                    HStack(spacing: 20) {
                        if call.active {
                            if call.connected {
                                Button {
                                    Haptics.tap()
                                    call.toggleMute()
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: call.muted ? "mic.slash.fill" : "mic.fill")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(call.muted ? .white : .primary)
                                            .frame(width: 58, height: 58)
                                            .background(call.muted ? Color.orange : Color.primary.opacity(isDark ? 0.14 : 0.08), in: Circle())
                                        Text(call.muted ? "取消静音" : "静音")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("ai.live.mute")
                            }

                            Button {
                                Haptics.warning()
                                call.hangUp(reason: "已挂断实时语音")
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "phone.down.fill")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 66, height: 66)
                                        .background(DS.Palette.danger, in: Circle())
                                        .shadow(color: DS.Palette.danger.opacity(0.45), radius: 14, y: 6)
                                    Text("挂断")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(DS.Palette.danger)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ai.live.end")
                        } else if call.callPhase == .disconnected {
                            // Explicit Manual Retry (no infinite auto-redial, no white screen)
                            Button {
                                Haptics.tap()
                                if isReadyToCall {
                                    startSelectedCall()
                                } else if !useManagedGateway {
                                    showingKey = true
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 16, weight: .bold))
                                    Text("重新连接实时语音")
                                        .font(.headline.weight(.bold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: 280)
                                .padding(.vertical, 15)
                                .background(Color.orange, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(model == nil || (useManagedGateway && !isReadyToCall))
                            .accessibilityIdentifier("ai.live.retry")
                        } else {
                            Button {
                                Haptics.tap()
                                if isReadyToCall {
                                    confirmation = true
                                } else if !useManagedGateway {
                                    showingKey = true
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 17, weight: .bold))
                                    Text("开始实时语音")
                                        .font(.headline.weight(.bold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: 280)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [accent, Color.indigo],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    in: Capsule()
                                )
                                .shadow(color: accent.opacity(0.38), radius: 16, y: 8)
                            }
                            .buttonStyle(.plain)
                            .disabled(model == nil || (useManagedGateway && !isReadyToCall))
                            .accessibilityIdentifier("ai.live.start")
                        }
                    }

                    Text("接通就绪后 AI 会主动问候「你好，今天想聊什么？」；随时开口可打断；挂断立即释放麦克风，单次上限 10 分钟。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 22)
                }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("实时语音通话")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            orbPulse = true
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

    private var pipelineTraceStrip: some View {
        let t = call.telemetry
        return HStack(spacing: 6) {
            stageDot("麦克风", ok: t.micCaptured)
            stageDot("已发出", ok: t.audioSent)
            stageDot("判停", ok: t.serverVADStopped)
            stageDot("首段音", ok: t.firstAudioReceived)
            stageDot("播出", ok: t.speakerPlaying)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("ai.live.pipelineTrace")
    }

    private func stageDot(_ label: String, ok: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ok ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: ok ? .bold : .medium))
                .foregroundStyle(ok ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
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
private final class AILiveCallController: ObservableObject {
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
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var startupOrReader: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var connectDeadline: Task<Void, Never>?
    private var callDeadline: Task<Void, Never>?
    private var audioRecoveryTask: Task<Void, Never>?
    private var capture: AsyncStream<LiveCaptureFrame>.Continuation?
    private var captureGate: LiveCaptureGate?
    private let audio = AILiveAudio()
    private var output: Output?
    private var cutItems = Set<String>()
    private var foreground = false
    private var userSpeaking = false
    private var omitNoiseReduction = false
    private var hasGreetedInSession = false

    func setForeground(_ value: Bool) { foreground = value }

    /// Connects through WUMIND Managed Billing Gateway (`wss://<gateway>/v1/realtime?model=...`).
    func beginManaged(model: AILiveProtocol.Model, store: WuMindStore) {
        guard !active else { return }
        let generation = UUID()
        id = generation
        active = true
        connected = false
        hasGreetedInSession = false
        liveTranscript = ""
        telemetry.reset()
        omitNoiseReduction = true
        callPhase = .connecting
        status = "等待麦克风授权…"

        startupOrReader = Task { @MainActor [weak self] in
            guard await AILiveAudio.requestMicrophonePermission() else {
                self?.fail(generation, "未开启麦克风权限。请在系统设置中允许访问麦克风。")
                return
            }
            guard let self, self.id == generation, !Task.isCancelled else { return }
            self.status = "正在连接 WUMIND 实时语音网关…"
            self.startConnectTimer(generation)
            do {
                let userToken = try await store.ensureManagedAccount()
                let gwURL = try WuMindGatewayClient.normalizedGatewayURL(store.gatewayBaseURL)
                let req = try AILiveProtocol.directWebSocketRequest(
                    model: model,
                    baseURL: gwURL.absoluteString,
                    bearerToken: userToken
                )
                try await self.runDirectSocket(req, generation: generation)
            } catch is CancellationError {
                self.hangUp(reason: "连接已取消")
            } catch let error as LocalizedError {
                self.fail(generation, error.errorDescription ?? "WUMIND 实时语音连接失败。")
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
        hasGreetedInSession = false
        liveTranscript = ""
        telemetry.reset()
        let cleanCustomBase = customBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let useDirectRelay = cleanCustomBase?.isEmpty == false
        omitNoiseReduction = useDirectRelay
        callPhase = .connecting
        status = "等待麦克风授权…"

        startupOrReader = Task { @MainActor [weak self] in
            guard await AILiveAudio.requestMicrophonePermission() else {
                self?.fail(generation, "未开启麦克风权限。请在系统设置中允许访问麦克风。")
                return
            }
            guard let self, self.id == generation, !Task.isCancelled else { return }
            self.status = useDirectRelay ? "正在连接中转实时语音（Bearer WS）…" : "正在连接 OpenAI Realtime…"
            self.startConnectTimer(generation)
            do {
                if let baseStr = cleanCustomBase, !baseStr.isEmpty {
                    let directReq = try AILiveProtocol.directWebSocketRequest(
                        model: model,
                        baseURL: baseStr,
                        bearerToken: apiKey
                    )
                    try await self.runDirectSocket(directReq, generation: generation)
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
                    guard let socketURL = handshake.url else { throw MultiProviderAIError.invalidRequest }
                    try await self.runOfficialSocket(socketURL, protocols: AILiveProtocol.webSocketProtocols(token: token),
                                                     generation: generation)
                }
            } catch is CancellationError {
                self.hangUp(reason: "连接已取消")
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

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 660
        return URLSession(configuration: config, delegate: LiveSocketPolicy(), delegateQueue: nil)
    }

    private func runDirectSocket(_ request: URLRequest, generation: UUID) async throws {
        let session = makeSession()
        self.session = session
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = AILiveProtocol.maximumServerEventBytes
        self.socket = socket
        socket.resume()
        try await readLoop(socket: socket, generation: generation)
    }

    private func runOfficialSocket(_ url: URL, protocols: [String], generation: UUID) async throws {
        let session = makeSession()
        self.session = session
        let socket = session.webSocketTask(with: url, protocols: protocols)
        socket.maximumMessageSize = AILiveProtocol.maximumServerEventBytes
        self.socket = socket
        socket.resume()
        try await readLoop(socket: socket, generation: generation)
    }

    private func readLoop(socket: URLSessionWebSocketTask, generation: UUID) async throws {
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
            if !connected {
                status = "会话已创建，正在协商 24kHz PCM 音频与 VAD…"
                try await send(AILiveProtocol.sessionUpdate(omitNoiseReduction: omitNoiseReduction), to: socket)
            }
        case .sessionReady:
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
            if !hasGreetedInSession {
                hasGreetedInSession = true
                try? await send(AILiveProtocol.responseCreateGreeting("你好，今天想聊什么？"), to: socket)
            }

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
            telemetry.receivedChunksCount += 1
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
            callPhase = .speaking
            status = "AI 正在回复（随时开口可打断）"
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
            telemetry.serverVADStopped = true
            callPhase = .listening
            status = muted ? "麦克风已静音" : "服务端已判停 · 等待 AI 语音回复…"
        case .audioDone(let item, let index):
            if output?.item == item, output?.contentIndex == index {
                output?.finishedStreaming = true
            }
        case .responseDone:
            if !userSpeaking {
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

    private func startAudio(_ socket: URLSessionWebSocketTask, generation: UUID) throws {
        var continuation: AsyncStream<LiveCaptureFrame>.Continuation?
        let stream = AsyncStream<LiveCaptureFrame>(bufferingPolicy: .bufferingNewest(12)) { continuation = $0 }
        guard let sink = continuation else { return }
        let gate = LiveCaptureGate()
        capture = sink
        captureGate = gate
        audio.onPlaybackStarted = { [weak self] in
            guard let self else { return }
            self.telemetry.speakerPlaying = true
            self.telemetry.outputRoute = self.audio.activeOutputRouteDescription
        }
        try audio.start { bytes in gate.enqueue(bytes, to: sink) }
        sender = Task { @MainActor [weak self] in
            do {
                for await frame in stream {
                    guard let self, !Task.isCancelled, self.id == generation else { return }
                    if !self.telemetry.micCaptured && !frame.bytes.isEmpty {
                        self.telemetry.micCaptured = true
                    }
                    if self.foreground, !self.muted, gate.isCurrent(frame.epoch) {
                        try await self.send(AILiveProtocol.appendPCM(frame.bytes), to: socket)
                        if !self.telemetry.audioSent {
                            self.telemetry.audioSent = true
                        }
                        self.telemetry.sentFramesCount += 1
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

    private func send(_ bytes: Data, to socket: URLSessionWebSocketTask) async throws {
        try await socket.send(.string(String(decoding: bytes, as: UTF8.self)))
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
        captureGate?.set(!muted)
        status = muted ? "麦克风已静音" : "请继续说话"
    }

    private func startConnectTimer(_ generation: UUID) {
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
        callPhase = isFailure ? .disconnected : .idle
        status = reason
    }
}
