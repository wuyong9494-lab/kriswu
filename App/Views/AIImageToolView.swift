import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Flagship WUMIND Imagine Studio — supports Text-to-Image & Reference-Image Editing (`添加参考图`),
/// BOTH WUMIND Managed Gateway and Own API/AIHubMix, explicit 「快速草稿 / 高清成品」 tiers (never silently swaps model),
/// 4-stage real latency profiling (准备上传 → 网关提交 → 上游出图 → 手机显示), and automatic 「我的作品 / 历史」 persistence.
@MainActor
struct AIImageToolView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var wmStore = WuMindStore.shared
    @ObservedObject private var sessionStore = AIImageStudioSessionStore.shared

    @State private var model: AIImageTool.Model = AIImageTool.models[0]
    @State private var managedSelectedImageID: String = ""
    @State private var quality: AIImageTool.Quality = .fast
    @State private var aspectRatio: AIImageTool.AspectRatio = .portrait
    @State private var batchCount: Int = 1
    @State private var selectedStyle: StudioStylePreset = .none

    // Reference image picker presentation flags (selected reference persists in sessionStore)
    @State private var showingRefPhotoPicker = false
    @State private var showingRefFileImporter = false
    @State private var pickedRefPhotoItem: PhotosPickerItem? = nil

    @State private var hasKey = false
    @State private var customHost: String? = nil
    @State private var settingKey = false
    @State private var settingAIHubMix = false
    @State private var showingHistory = false
    @State private var showingDiagnostics = false
    @State private var isSyncingManagedCatalog = false
    @State private var credentialRevision = 0
    @State private var ownConnectionPreference = AIProviderEndpoints.imageStudioOwnConnectionPreference

    @State private var toastMessage: String? = nil
    @State private var lightboxItem: LightboxItem? = nil

    @FocusState private var promptFocused: Bool

    private typealias StudioSlot = AIImageStudioSessionStore.StudioSlot
    private typealias StudioSession = AIImageStudioSessionStore.StudioSession

    private var prompt: String {
        get { sessionStore.prompt }
        nonmutating set { sessionStore.prompt = newValue }
    }
    private var referenceImage: AIImageTool.ReferenceImage? {
        get { sessionStore.referenceImage }
        nonmutating set { sessionStore.referenceImage = newValue }
    }
    private var referenceThumbnail: UIImage? {
        get { sessionStore.referenceThumbnail }
        nonmutating set { sessionStore.referenceThumbnail = newValue }
    }
    private var referencePrepNote: String? {
        get { sessionStore.referencePrepNote }
        nonmutating set { sessionStore.referencePrepNote = newValue }
    }
    private var referencePrepMs: Int {
        get { sessionStore.referencePrepMs }
        nonmutating set { sessionStore.referencePrepMs = newValue }
    }
    private var sessions: [StudioSession] {
        get { sessionStore.sessions }
        nonmutating set { sessionStore.sessions = newValue }
    }
    private var activeRunID: UUID? {
        get { sessionStore.activeRunID }
        nonmutating set { sessionStore.activeRunID = newValue }
    }
    private var activeTask: Task<Void, Never>? {
        get { sessionStore.activeTask }
        nonmutating set { sessionStore.activeTask = newValue }
    }
    private var liveStageLabel: String? {
        get { sessionStore.liveStageLabel }
        nonmutating set { sessionStore.liveStageLabel = newValue }
    }
    private var failureMessage: String? {
        get { sessionStore.failureMessage }
        nonmutating set { sessionStore.failureMessage = newValue }
    }
    private var lastClassifiedError: AIImageClassifiedError? {
        get { sessionStore.lastClassifiedError }
        nonmutating set { sessionStore.lastClassifiedError = newValue }
    }
    private var diagnostics: [AIImageRequestDiagnostic] {
        get { sessionStore.diagnostics }
        nonmutating set { sessionStore.diagnostics = newValue }
    }
    private var pendingRetrySignature: String? {
        get { sessionStore.pendingRetrySignature }
        nonmutating set { sessionStore.pendingRetrySignature = newValue }
    }
    private var pendingRetryIdempotencyKey: String? {
        get { sessionStore.pendingRetryIdempotencyKey }
        nonmutating set { sessionStore.pendingRetryIdempotencyKey = newValue }
    }

    private enum PrefKey {
        static let modelID = "wumind.imageStudio.modelID"
        static let quality = "wumind.imageStudio.quality"
        static let aspect = "wumind.imageStudio.aspect"
        static let batchCount = "wumind.imageStudio.batchCount"
    }

    private struct LightboxItem: Identifiable {
        let id = UUID()
        let image: UIImage
        let pixelSize: CGSize?
        let prompt: String
        let modelName: String
        let quality: AIImageTool.Quality
        let elapsedSeconds: Double?
    }

    private enum StudioStylePreset: String, CaseIterable, Identifiable {
        case none
        case cinematic
        case editorialPortrait
        case cyberpunk
        case anime
        case inkWash
        case productStudio

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "自动画风"
            case .cinematic: return "电影质感"
            case .editorialPortrait: return "胶片人像"
            case .cyberpunk: return "赛博霓虹"
            case .anime: return "日系插画"
            case .inkWash: return "新中式水墨"
            case .productStudio: return "商业微距"
            }
        }

        var icon: String {
            switch self {
            case .none: return "wand.and.stars"
            case .cinematic: return "film"
            case .editorialPortrait: return "camera.aperture"
            case .cyberpunk: return "sparkles"
            case .anime: return "paintpalette"
            case .inkWash: return "mountain.2"
            case .productStudio: return "cube.transparent"
            }
        }

        var promptSuffix: String? {
            switch self {
            case .none: return nil
            case .cinematic: return "，电影级光影构图，柔和景深，胶片细腻质感"
            case .editorialPortrait: return "，时尚杂志人像摄影，自然肤质与柔光眼神，85mm 镜头"
            case .cyberpunk: return "，赛博朋克雨夜霓虹反射，高对比电影色调，细节丰富"
            case .anime: return "，精致日系动画原画风格，通透光影与细腻线条"
            case .inkWash: return "，新中式水墨青绿山水意境，留白构图，宣纸墨韵与柔光"
            case .productStudio: return "，徕卡级商业静物微距摄影，干净棚拍布光，高级材质反射"
            }
        }
    }

    private struct InspirationCard: Identifiable {
        let id: String
        let title: String
        let tag: String
        let prompt: String
        let icon: String
        let colors: [Color]
        let aspect: AIImageTool.AspectRatio
    }

    private static let inspirations: [InspirationCard] = [
        InspirationCard(
            id: "portrait",
            title: "电影感人像",
            tag: "人像 · 黄金时刻",
            prompt: "黄金时刻窗边柔和逆光人像特写，自然细腻肤质，35mm 胶片电影质感与浅景深",
            icon: "camera.aperture",
            colors: [Color(red: 0.28, green: 0.16, blue: 0.24), Color(red: 0.72, green: 0.42, blue: 0.30)],
            aspect: .portrait
        ),
        InspirationCard(
            id: "wildlife",
            title: "荒野大象纪实",
            tag: "自然 · 国家地理",
            prompt: "非洲草原晨雾中迎面走来的非洲象特写，自然阳光与细腻纹理，长焦纪实摄影",
            icon: "leaf.fill",
            colors: [Color(red: 0.12, green: 0.26, blue: 0.18), Color(red: 0.42, green: 0.48, blue: 0.24)],
            aspect: .portrait
        ),
        InspirationCard(
            id: "cyber",
            title: "雨夜赛博都市",
            tag: "科幻 · 电影宽画",
            prompt: "未来东方雨夜街头，湿润路面反射霓虹灯牌与悬浮车流，高质感电影宽幅构图",
            icon: "building.2.crop.circle",
            colors: [Color(red: 0.08, green: 0.12, blue: 0.28), Color(red: 0.56, green: 0.18, blue: 0.54)],
            aspect: .landscape
        ),
        InspirationCard(
            id: "ink",
            title: "云海青绿水墨",
            tag: "国风 · 意境留白",
            prompt: "清晨云海孤峰与双鹤掠影，宋代青绿山水与现代柔光层次融合，高级留白构图",
            icon: "mountain.2.fill",
            colors: [Color(red: 0.07, green: 0.20, blue: 0.24), Color(red: 0.22, green: 0.52, blue: 0.48)],
            aspect: .square
        ),
    ]

    private var cleanedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isPromptValid: Bool {
        !cleanedPrompt.isEmpty && cleanedPrompt.utf8.count <= AIImageTool.maxPromptBytes
    }

    private var isGenerating: Bool {
        activeRunID != nil
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var canvasBackground: Color {
        isDark ? Color(red: 0.025, green: 0.028, blue: 0.042) : Color(red: 0.955, green: 0.960, blue: 0.975)
    }

    private var providerAccent: Color {
        switch model.provider {
        case .openAI: return Color(red: 0.10, green: 0.72, blue: 0.54)
        case .gemini: return Color(red: 0.28, green: 0.54, blue: 0.98)
        case .grok: return Color(red: 0.64, green: 0.48, blue: 0.98)
        case .claude: return Color(red: 0.88, green: 0.50, blue: 0.30)
        }
    }

    private var useManagedGateway: Bool {
        wmStore.channel == .managed
    }

    private var credentialSnapshot: AIImageCredentialSnapshot {
        _ = credentialRevision
        let base = AIProviderEndpoints.currentImageCredentialSnapshot(
            store: wmStore,
            isCatalogSyncing: isSyncingManagedCatalog
        )
        return AIImageCredentialSnapshot(
            useManagedGateway: base.useManagedGateway,
            isGatewayConfigured: base.isGatewayConfigured,
            isGatewayLoggedIn: base.isGatewayLoggedIn,
            isGatewayCatalogSyncing: base.isGatewayCatalogSyncing,
            enabledManagedImageModels: base.enabledManagedImageModels,
            ownPreference: ownConnectionPreference,
            aihubmixConnection: base.aihubmixConnection,
            directProviderKeys: base.directProviderKeys,
            directProviderBaseURLs: base.directProviderBaseURLs
        )
    }

    private var managedSelectionResolution: AIImageManagedSelectionResolution {
        AIImageStudioAvailability.resolveManagedSelection(
            requestedModelID: managedSelectedImageID,
            fallbackModel: model,
            enabledManagedImageModels: wmStore.enabledManagedImageModels
        )
    }

    private var activeManagedImageModel: WuMindCatalogModel? {
        managedSelectionResolution.catalogModel
    }

    private var activeEvaluationModel: AIImageTool.Model {
        useManagedGateway ? managedSelectionResolution.displayModel : model
    }

    private var availabilityState: AIImageAvailabilityState {
        AIImageStudioAvailability.evaluate(
            model: activeEvaluationModel,
            hasReferenceImage: referenceImage != nil,
            snapshot: credentialSnapshot
        )
    }

    private var activeSupportsReferenceImage: Bool {
        if useManagedGateway, let m = activeManagedImageModel {
            return m.supportsImageEdit
        }
        return activeEvaluationModel.supportsReferenceImage
    }

    private var activeModelDisplayName: String {
        if useManagedGateway, let m = activeManagedImageModel { return m.displayName }
        return activeEvaluationModel.shortStudioName
    }

    private var isReadyToGenerate: Bool {
        availabilityState.isReady
    }

    private var latestUpgradeableSession: StudioSession? {
        guard !isGenerating else { return nil }
        guard let latest = sessions.first, !latest.completedSlots.isEmpty else { return nil }
        return latest.quality != .hd ? latest : nil
    }

    var body: some View {
        ZStack {
            studioBackdrop

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Color.clear.frame(height: 2).id("studio.top")

                        routeStatusBar

                        if !isReadyToGenerate {
                            availabilityBanner
                        }

                        if let stage = liveStageLabel, isGenerating {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small).tint(providerAccent)
                                Text(stage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("已归档「我的作品」")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(providerAccent.opacity(0.35), lineWidth: 1))
                            .accessibilityIdentifier("ai.image.liveStage")
                        }

                        if let failureMessage, sessions.isEmpty {
                            errorBanner(message: failureMessage, retryPrompt: cleanedPrompt.isEmpty ? nil : cleanedPrompt)
                        }

                        if sessions.isEmpty {
                            emptyStudioGallery
                        } else {
                            ForEach(sessions) { session in
                                sessionBlock(session)
                                    .id(session.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 22)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture {
                    if promptFocused {
                        dismissKeyboard()
                    }
                }
                .onChange(of: sessions.first?.id) { firstID in
                    guard let firstID else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        proxy.scrollTo(firstID, anchor: .top)
                    }
                }
            }

            if let toastMessage {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(toastMessage)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(isDark ? 0.16 : 0.35), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.24), radius: 12, y: 6)
                    .padding(.top, 12)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(5)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            floatingBottomDock
        }
        .navigationTitle("WUMIND 画室")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                modelPickerPill
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    Button {
                        dismissKeyboard()
                        Haptics.tap()
                        showingDiagnostics = true
                    } label: {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(diagnostics.isEmpty ? Color.secondary : providerAccent)
                    }
                    .accessibilityLabel("画室脱敏诊断日志")
                    .accessibilityIdentifier("ai.image.diagnostics")

                    Button {
                        dismissKeyboard()
                        Haptics.tap()
                        showingHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                    .accessibilityLabel("生图历史")
                    .accessibilityIdentifier("ai.image.history")

                    if !sessions.isEmpty && !isGenerating {
                        Button {
                            Haptics.tap()
                            withAnimation(.easeOut(duration: 0.2)) {
                                sessions.removeAll()
                                failureMessage = nil
                                lastClassifiedError = nil
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("清空本次画廊")
                        .accessibilityIdentifier("ai.image.clear")
                    }

                    if !useManagedGateway {
                        Button {
                            dismissKeyboard()
                            Haptics.tap()
                            if availabilityState.routeKind == .ownAIHubMix || ownConnectionPreference == .aihubmix {
                                settingAIHubMix = true
                            } else {
                                settingKey = true
                            }
                        } label: {
                            Image(systemName: isReadyToGenerate ? "key.fill" : "key.radiowaves.forward")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(isReadyToGenerate ? providerAccent : Color.orange)
                        }
                        .accessibilityLabel(availabilityState.routeKind == .ownAIHubMix ? "配置 AIHubMix 连接" : "配置 \(model.provider.displayName) API Key")
                        .accessibilityIdentifier("ai.image.keyConfig")
                    }
                }
            }
        }
        .background(
            Color.clear
                .photosPicker(isPresented: $showingRefPhotoPicker, selection: $pickedRefPhotoItem, matching: .images)
        )
        .fileImporter(
            isPresented: $showingRefFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleImportedReferenceFile(result)
        }
        .onChange(of: pickedRefPhotoItem) { item in
            guard let item else { return }
            handlePickedReferencePhoto(item)
        }
        .sheet(isPresented: $showingHistory) {
            WuMindWorksView(initialFilter: .image, onRetryWork: { failed in
                prompt = failed.prompt
            })
        }
        .sheet(isPresented: $showingDiagnostics) {
            ImageStudioDiagnosticsSheet(
                routeBadge: availabilityState.routeBadge,
                activeModelID: activeEvaluationModel.id,
                entries: diagnostics
            )
        }
        .sheet(isPresented: $settingAIHubMix) {
            AIHubMixConnectionSheet {
                ownConnectionPreference = AIProviderEndpoints.imageStudioOwnConnectionPreference
                credentialRevision += 1
                syncProviderState()
                failureMessage = nil
                lastClassifiedError = nil
            }
        }
        .sheet(isPresented: $settingKey) {
            ProviderKeyView(provider: model.provider) { configured in
                hasKey = configured
                customHost = AIProviderEndpoints.displayHost(for: model.provider)
                credentialRevision += 1
                failureMessage = nil
                lastClassifiedError = nil
            }
        }
        .fullScreenCover(item: $lightboxItem) { item in
            ImageStudioLightbox(
                image: item.image,
                pixelSize: item.pixelSize,
                prompt: item.prompt,
                modelName: item.modelName,
                quality: item.quality,
                elapsedSeconds: item.elapsedSeconds,
                onUpscale: {
                    lightboxItem = nil
                    triggerHDUpgrade(prompt: item.prompt)
                },
                onCopied: {
                    showToast("已复制提示词")
                },
                onSaved: { success in
                    showToast(success ? "已保存到系统相册" : "保存失败，请在系统设置开启相册写入权限")
                }
            )
        }
        .onAppear(perform: hydratePreferences)
        .onChange(of: model) { _ in
            persistPreferences()
            syncProviderState()
            invalidatePendingRetryKey()
        }
        .onChange(of: managedSelectedImageID) { newID in
            if !newID.isEmpty {
                UserDefaults.standard.set(newID, forKey: PrefKey.modelID)
            }
            invalidatePendingRetryKey()
        }
        .onChange(of: wmStore.channel) { _ in
            credentialRevision += 1
            failureMessage = nil
            lastClassifiedError = nil
            invalidatePendingRetryKey()
            if wmStore.channel == .managed {
                refreshManagedCatalogIfNeeded(force: false)
            }
        }
        .onChange(of: quality) { _ in
            persistPreferences()
            invalidatePendingRetryKey()
        }
        .onChange(of: aspectRatio) { _ in
            persistPreferences()
            invalidatePendingRetryKey()
        }
        .onChange(of: batchCount) { _ in
            persistPreferences()
            invalidatePendingRetryKey()
        }
        // NOTE: Intentionally NO `.onDisappear(perform: stopGeneration)` — returning to Launcher Home
        // or switching tabs MUST keep running image generation, drafts, and results alive.
        // Only explicit user tap on 「停止 / 取消」 calls `stopGeneration()`.
    }

    // MARK: - Backdrop

    private var studioBackdrop: some View {
        ZStack {
            canvasBackground.ignoresSafeArea()
            RadialGradient(
                colors: [
                    providerAccent.opacity(isDark ? 0.16 : 0.08),
                    Color.clear,
                ],
                center: .top,
                startRadius: 12,
                endRadius: 360
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: - Explicit Route & Connection Status Bar

    private var routeStatusBar: some View {
        let route = availabilityState.routeKind
        let badgeColor: Color = {
            switch route {
            case .managedGateway: return .indigo
            case .ownAIHubMix: return .purple
            case .ownDirectVendor: return .teal
            }
        }()
        let subtitle: String = {
            switch availabilityState {
            case .ready(_, _, let detail, _, _):
                return detail
            case .managedCatalogSyncing:
                return "正在同步网关已开通的生图能力…"
            case .managedGatewayConfigInvalid:
                return "内置网关暂不可用，请联系管理员"
            case .managedModelNotEnabled(_, let name, _):
                return "\(name) 内置暂未开通（不读本机 Key）"
            case .managedLoginRequired:
                return "走 WuMind 凭证与余额，请先登录或检查网关"
            case .missingConnection(_, _, _, _):
                return route == .ownAIHubMix ? "请保存 AIHubMix Key" : "可选 AIHubMix 统一连接或厂商直连 Key"
            case .referenceImageUnsupported(_, let name):
                return "\(name) 仅支持纯文生图"
            }
        }()

        return HStack(spacing: 10) {
            Menu {
                Section("显式切换生图路由（绝不静默切换）") {
                    Button {
                        Haptics.select()
                        managedSelectedImageID = activeEvaluationModel.id
                        wmStore.setChannel(.managed)
                        refreshManagedCatalogIfNeeded(force: true)
                    } label: {
                        Label(
                            "WuMind 内置（走网关与 WuMind 余额）",
                            systemImage: useManagedGateway ? "checkmark.circle.fill" : "bolt.shield"
                        )
                    }

                    Button {
                        Haptics.select()
                        wmStore.setChannel(.ownAPI)
                        ownConnectionPreference = .aihubmix
                        AIProviderEndpoints.imageStudioOwnConnectionPreference = .aihubmix
                        credentialRevision += 1
                    } label: {
                        let active = !useManagedGateway && availabilityState.routeKind == .ownAIHubMix
                        Label(
                            "自有 API · AIHubMix（一套 Key 驱动 GPT + Nano Banana 2）",
                            systemImage: active ? "checkmark.circle.fill" : "network"
                        )
                    }

                    Button {
                        Haptics.select()
                        wmStore.setChannel(.ownAPI)
                        ownConnectionPreference = .directVendor
                        AIProviderEndpoints.imageStudioOwnConnectionPreference = .directVendor
                        credentialRevision += 1
                    } label: {
                        let active = !useManagedGateway && availabilityState.routeKind == .ownDirectVendor
                        Label(
                            "自有 API · 厂商官方直连",
                            systemImage: active ? "checkmark.circle.fill" : "key"
                        )
                    }
                }
                if !useManagedGateway {
                    Section("自有连接管理") {
                        Button {
                            dismissKeyboard()
                            settingAIHubMix = true
                        } label: {
                            Label("管理 AIHubMix 连接", systemImage: "network.badge.shield.half.filled")
                        }
                        Button {
                            dismissKeyboard()
                            settingKey = true
                        } label: {
                            Label("管理 \(model.provider.displayName) 直连 Key", systemImage: "key.fill")
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isReadyToGenerate ? badgeColor : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(availabilityState.routeBadge)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(badgeColor)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(badgeColor.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(badgeColor.opacity(0.13), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
            .accessibilityIdentifier("ai.image.routeBadge")

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if useManagedGateway {
                if wmStore.isBillingExempt {
                    Text("免扣费")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12), in: Capsule())
                } else {
                    Text(wmStore.managedBalanceYuan.map { String(format: "¥%.2f", $0) } ?? "未同步")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                Button {
                    Haptics.tap()
                    refreshManagedCatalogIfNeeded(force: true)
                } label: {
                    if isSyncingManagedCatalog {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSyncingManagedCatalog || isGenerating)
                .accessibilityLabel("刷新内置生图目录")
            } else {
                Button {
                    dismissKeyboard()
                    Haptics.tap()
                    if availabilityState.routeKind == .ownAIHubMix || ownConnectionPreference == .aihubmix {
                        settingAIHubMix = true
                    } else {
                        settingKey = true
                    }
                } label: {
                    Text(availabilityState.routeKind == .ownAIHubMix ? "AIHubMix" : "连接")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(badgeColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(badgeColor.opacity(0.24), lineWidth: 0.9)
        )
    }

    // MARK: - Top Model Picker Pill

    private var modelPickerPill: some View {
        Menu {
            if useManagedGateway {
                Section("WuMind 内置已开通生图（网关实测）") {
                    if wmStore.enabledManagedImageModels.isEmpty {
                        Text("当前网关尚未启用内置生图模型")
                    } else {
                        ForEach(wmStore.enabledManagedImageModels) { m in
                            Button {
                                Haptics.select()
                                managedSelectedImageID = m.id
                                if let matched = AIImageTool.models.first(where: { $0.id.lowercased() == m.id.lowercased() }) {
                                    model = matched
                                }
                            } label: {
                                let tag = m.supportsImageEdit ? "支持参考图" : "仅纯文生图"
                                Label(
                                    "\(m.displayName) · \(tag) · \(m.pricingSummary)",
                                    systemImage: m.id.lowercased() == activeEvaluationModel.id.lowercased() ? "checkmark" : "photo"
                                )
                            }
                        }
                    }
                }
                let enabledLower = Set(wmStore.enabledManagedImageModels.map { $0.id.lowercased() })
                let disabledDefaults = AIImageTool.models.filter { !enabledLower.contains($0.id.lowercased()) }
                if !disabledDefaults.isEmpty {
                    Section("内置暂未开通（不会要求填厂商 Key）") {
                        ForEach(disabledDefaults) { item in
                            Button {
                                Haptics.select()
                                managedSelectedImageID = item.id
                                model = item
                            } label: {
                                Label("\(item.displayName) · 内置暂未开通", systemImage: "lock.fill")
                            }
                        }
                    }
                }
            } else {
                let snap = credentialSnapshot
                Section("选择出图模型（\(availabilityState.routeBadge)）") {
                    ForEach(AIImageTool.models) { item in
                        let eval = AIImageStudioAvailability.evaluate(model: item, hasReferenceImage: false, snapshot: snap)
                        let capTag = item.supportsReferenceImage ? "支持参考图" : "仅文生图"
                        Button {
                            Haptics.select()
                            model = item
                        } label: {
                            HStack {
                                Text("\(item.displayName) · \(capTag)")
                                if item == model {
                                    Image(systemName: "checkmark")
                                } else if eval.isReady {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
                    }
                }
                Section("连接管理") {
                    Button {
                        dismissKeyboard()
                        settingAIHubMix = true
                    } label: {
                        Label(
                            snap.aihubmixConnection != nil ? "管理 AIHubMix 统一连接" : "配置 AIHubMix（一套 Key 调全模型）",
                            systemImage: "network.badge.shield.half.filled"
                        )
                    }
                    Button {
                        dismissKeyboard()
                        settingKey = true
                    } label: {
                        Label(
                            hasKey ? "管理 \(model.provider.displayName) 直连 Key" : "配置 \(model.provider.displayName) 直连 Key",
                            systemImage: "key.fill"
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isReadyToGenerate ? providerAccent : Color.orange)
                    .frame(width: 7, height: 7)
                Text(activeModelDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isDark ? 0.14 : 0.09), lineWidth: 0.8))
        }
        .tint(.primary)
        .disabled(isGenerating)
        .accessibilityIdentifier("ai.image.model")
    }

    // MARK: - Unified Availability Banner (Zero Cross-Route Contamination!)

    private var availabilityBanner: some View {
        let state = availabilityState
        let iconName: String = {
            switch state {
            case .managedCatalogSyncing: return "arrow.triangle.2.circlepath"
            case .managedGatewayConfigInvalid: return "network.slash"
            case .managedModelNotEnabled: return "lock.shield.fill"
            case .managedLoginRequired: return "person.crop.circle.badge.exclamationmark"
            case .missingConnection: return "network.badge.shield.half.filled"
            case .referenceImageUnsupported: return "photo.badge.exclamationmark"
            case .ready: return "checkmark.circle.fill"
            }
        }()
        let tintColor: Color = {
            switch state {
            case .managedCatalogSyncing: return .indigo
            case .managedModelNotEnabled: return .indigo
            default: return .orange
            }
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tintColor)
                    .frame(width: 32, height: 32)
                    .background(tintColor.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.bannerTitle ?? "暂不可生成")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.primary)
                    if let detail = state.bannerDetail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
            }

            HStack(spacing: 8) {
                switch state {
                case .managedGatewayConfigInvalid:
                    Text("请联系管理员检查内置网关配置。")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                case .managedModelNotEnabled(_, _, let hasOther):
                    if hasOther, let firstReady = wmStore.enabledManagedImageModels.first {
                        Button {
                            Haptics.tap()
                            managedSelectedImageID = firstReady.id
                        } label: {
                            Text("切至 \(firstReady.displayName)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.indigo, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        Haptics.tap()
                        refreshManagedCatalogIfNeeded(force: true)
                    } label: {
                        Text(isSyncingManagedCatalog ? "同步中…" : "刷新内置目录")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.09), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSyncingManagedCatalog)

                case .missingConnection(_, _, _, let action):
                    Button {
                        dismissKeyboard()
                        Haptics.tap()
                        settingAIHubMix = true
                    } label: {
                        Text("配置 AIHubMix")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.purple, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    if case .configureDirectVendor = action {
                        Button {
                            dismissKeyboard()
                            Haptics.tap()
                            settingKey = true
                        } label: {
                            Text("配置 \(model.provider.displayName) Key")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.primary.opacity(0.09), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                case .referenceImageUnsupported:
                    Button {
                        Haptics.tap()
                        switchToReferenceCapableModel()
                    } label: {
                        Text("切换支持参考图的模型")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.orange, in: Capsule())
                    }
                    .buttonStyle(.plain)

                case .managedCatalogSyncing, .managedLoginRequired, .ready:
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tintColor.opacity(0.30), lineWidth: 0.9)
        )
        .accessibilityIdentifier("ai.image.availabilityBanner")
    }

    // MARK: - Empty Inspiration Studio Gallery (2x2 Zero-Overflow Grid)

    private var emptyStudioGallery: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [providerAccent.opacity(0.32), providerAccent.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(providerAccent)
                }

                Text("WUMIND 画室")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    studioFeatureBadge("极速 JPEG 直出")
                    studioFeatureBadge("多图并发")
                    studioFeatureBadge("一键超清")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 4)

            HStack {
                Text("灵感模板")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let customHost {
                    Label("中转 \(customHost)", systemImage: "network")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("点击即可填入提示词")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(Self.inspirations) { card in
                    Button {
                        Haptics.tap()
                        prompt = card.prompt
                        aspectRatio = card.aspect
                        dismissKeyboard()
                    } label: {
                        inspirationTile(card)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ai.image.inspiration.\(card.id)")
                }
            }
        }
    }

    private func studioFeatureBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(isDark ? 0.08 : 0.05), in: Capsule())
    }

    private func inspirationTile(_ card: InspirationCard) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: card.colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle ambient highlight orb for editorial depth
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 96, height: 96)
                .blur(radius: 18)
                .offset(x: 52, y: -38)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: card.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.24), in: Circle())
                    Spacer()
                    Text(card.aspect.displayLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.28), in: Capsule())
                }

                Spacer(minLength: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(card.tag)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(card.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(card.prompt)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
        }
        .frame(height: 154)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.9)
        )
        .shadow(color: .black.opacity(isDark ? 0.35 : 0.10), radius: 10, y: 5)
    }

    // MARK: - Gallery Session Block (Grok Imagine Visual Feed)

    private func sessionBlock(_ session: StudioSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Prompt pill + metadata header (mirrors Grok's "大象" pill above the gallery)
            HStack(alignment: .center, spacing: 8) {
                Button {
                    Haptics.tap()
                    prompt = session.rawPrompt
                    showToast("已填入该提示词")
                } label: {
                    HStack(spacing: 5) {
                        Text(session.rawPrompt)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let styleName = session.styleName {
                            Text(styleName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(providerAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(providerAccent.opacity(0.14), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(
                        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.primary.opacity(isDark ? 0.12 : 0.06), lineWidth: 0.7)
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                sessionStatusBadge(session)
            }

            if let errorMessage = session.errorMessage, session.completedSlots.isEmpty {
                errorBanner(message: errorMessage, retryPrompt: session.rawPrompt)
            } else {
                let columns: [GridItem] = session.slots.count == 1
                    ? [GridItem(.flexible())]
                    : [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)]

                LazyVGrid(columns: columns, spacing: 7) {
                    ForEach(session.slots) { slot in
                        galleryCard(slot: slot, session: session, isHeroSingle: session.slots.count == 1)
                    }
                }

                if let timing = session.stageTiming {
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .font(.caption2)
                            .foregroundStyle(.teal)
                        Text(formatFourStageTiming(timing, usedRef: session.usedReferenceImage))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("ai.image.timingBreakdown")
                }

                if let errorMessage = session.errorMessage, !session.completedSlots.isEmpty {
                    Text("部分图片生成失败：\(errorMessage)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func formatFourStageTiming(_ t: WuMindCloudWorkTiming, usedRef: Bool) -> String {
        var parts: [String] = []
        if let u = t.uploadPrepareMs, (usedRef || u > 0) {
            parts.append(String(format: "上传准备 %.2fs", Double(u) / 1000))
        }
        if let g = t.gatewaySubmitMs, g > 0 {
            parts.append(String(format: "网关提交 %.2fs", Double(g) / 1000))
        }
        if let s = t.upstreamGenerateMs, s > 0 {
            parts.append(String(format: "上游出图 %.2fs", Double(s) / 1000))
        }
        if let d = t.displayRenderMs {
            parts.append(String(format: "手机显示 %.2fs", Double(d) / 1000))
        }
        if let total = t.totalMs {
            parts.append(String(format: "首图总耗时 %.2fs", Double(total) / 1000))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func sessionStatusBadge(_ session: StudioSession) -> some View {
        if session.isGenerating {
            TimelineView(.periodic(from: session.startedAt, by: 0.2)) { context in
                let sec = max(0.0, context.date.timeIntervalSince(session.startedAt))
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(String(format: "%.1fs", sec))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
            }
        } else {
            HStack(spacing: 4) {
                Text(session.quality.shortLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(session.quality == .hd ? Color.amberStudio : providerAccent)
                if let fastest = session.fastestSeconds {
                    Text("· \(String(format: "%.1fs", fastest))")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(isDark ? 0.07 : 0.05), in: Capsule())
        }
    }

    private func galleryCard(slot: StudioSlot, session: StudioSession, isHeroSingle: Bool) -> some View {
        let ratio = CGFloat(session.aspectRatio.widthToHeight)
        let cornerRadius: CGFloat = isHeroSingle ? 20 : 14

        return ZStack {
            if let uiImage = slot.image {
                Button {
                    dismissKeyboard()
                    Haptics.tap()
                    lightboxItem = LightboxItem(
                        image: uiImage,
                        pixelSize: slot.pixelSize,
                        prompt: session.rawPrompt,
                        modelName: session.model.displayName,
                        quality: session.quality,
                        elapsedSeconds: slot.elapsedSeconds
                    )
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Color.clear
                            .aspectRatio(ratio, contentMode: .fit)
                            .overlay(
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                            )
                            .clipped()

                        // Subtle bottom-right badge matching Grok Imagine's floating card corner badge
                        HStack(spacing: 4) {
                            if session.quality == .hd {
                                Text("HD")
                                    .font(.system(size: 9.5, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.black.opacity(0.56), in: Capsule())
                            }
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.black.opacity(0.48), in: Circle())
                        }
                        .padding(8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("生成的图片")
                .contextMenu {
                    Button {
                        lightboxItem = LightboxItem(
                            image: uiImage,
                            pixelSize: slot.pixelSize,
                            prompt: session.rawPrompt,
                            modelName: session.model.displayName,
                            quality: session.quality,
                            elapsedSeconds: slot.elapsedSeconds
                        )
                    } label: {
                        Label("全屏查看", systemImage: "viewfinder")
                    }
                    Button {
                        saveImageToAlbum(uiImage)
                    } label: {
                        Label("保存到相册", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        triggerHDUpgrade(prompt: session.rawPrompt)
                    } label: {
                        Label("提高质量重绘 (超清)", systemImage: "sparkles")
                    }
                    Button {
                        UIPasteboard.general.string = session.rawPrompt
                        showToast("已复制提示词")
                    } label: {
                        Label("复制提示词", systemImage: "doc.on.doc")
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if slot.failed {
                Color.clear
                    .aspectRatio(ratio, contentMode: .fit)
                    .background(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("该张未生成")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    )
            } else {
                StudioShimmerCard(
                    aspectRatio: ratio,
                    accent: providerAccent,
                    startedAt: session.startedAt,
                    slotLabel: session.slots.count > 1 ? "#\(slot.index + 1)" : session.quality.shortLabel,
                    isDark: isDark
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(isDark ? 0.12 : 0.45), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(isDark ? 0.35 : 0.08), radius: 10, y: 4)
        .frame(maxWidth: isHeroSingle ? (session.aspectRatio == .landscape ? 560 : 420) : .infinity)
    }

    private func errorBanner(message: String, retryPrompt: String?) -> some View {
        let classified = lastClassifiedError
        let categoryTitle = classified?.title ?? "生成未完成"
        let categoryTag = classified?.category.label ?? "接口错误"
        let safeRetryLabel = (classified?.isRetryableWithSameIdempotencyKey == true) ? "安全重试（同幂等键）" : "重试"
        let route = availabilityState.routeKind
        let targetDisplay: String = {
            switch route {
            case .managedGateway:
                let host = (try? WuMindGatewayClient.normalizedGatewayURL(wmStore.gatewayBaseURL).host) ?? "未配置网关"
                return "路由：WuMind 内置 · \(host)"
            case .ownAIHubMix:
                let host = credentialSnapshot.aihubmixConnection?.resolvedHost ?? "aihubmix.com"
                return "路由：自有 API · AIHubMix（\(host)）"
            case .ownDirectVendor:
                let host = model.provider.resolvedHost(baseURL: AIProviderEndpoints.baseURL(for: model.provider))
                return "路由：自有 API · \(host)"
            }
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(DS.Palette.danger)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(categoryTitle)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(categoryTag)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DS.Palette.danger)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Palette.danger.opacity(0.12), in: Capsule())
                    }
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(targetDisplay)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                if let retryPrompt, !retryPrompt.isEmpty {
                    Button {
                        Haptics.tap()
                        startGeneration(rawPrompt: retryPrompt, overrideQuality: nil)
                    } label: {
                        Label(safeRetryLabel, systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(providerAccent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if useManagedGateway {
                    Button {
                        Haptics.tap()
                        refreshManagedCatalogIfNeeded(force: true)
                    } label: {
                        Label("刷新内置目录", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.09), in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        dismissKeyboard()
                        if route == .ownAIHubMix || ownConnectionPreference == .aihubmix {
                            settingAIHubMix = true
                        } else {
                            settingKey = true
                        }
                    } label: {
                        Label(route == .ownAIHubMix ? "检查 AIHubMix 连接" : "检查 Key / 接口", systemImage: "key")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.09), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if !diagnostics.isEmpty {
                    Button {
                        dismissKeyboard()
                        showingDiagnostics = true
                    } label: {
                        Label("诊断", systemImage: "waveform.path.ecg")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DS.Palette.danger.opacity(0.32), lineWidth: 0.9)
        )
    }

    // MARK: - Floating Frosted-Glass Bottom Composer Dock (Zero Keyboard Occlusion!)

    private var floatingBottomDock: some View {
        VStack(spacing: 9) {
            // Grok-style floating "提高质量" pill right above the composer when viewing a fast/balanced result
            if !promptFocused, let latest = latestUpgradeableSession {
                Button {
                    Haptics.tap()
                    triggerHDUpgrade(prompt: latest.rawPrompt)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12.5, weight: .bold))
                        Text("提高质量")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(isDark ? .white : .primary)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(isDark ? 0.22 : 0.45), lineWidth: 0.9)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.image.upscale")
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Row 1: Floating Frosted-Glass Controls Strip (zero horizontal overflow — fits 375pt cleanly!)
            HStack(spacing: 7) {
                // Grok-style 极速 | 质量 segmented glass pill
                speedToggleCapsule

                // Aspect ratio glass pill (2:3 / 1:1 / 3:2 / 9:16)
                Menu {
                    ForEach(AIImageTool.AspectRatio.allCases) { ratio in
                        Button {
                            Haptics.select()
                            aspectRatio = ratio
                        } label: {
                            HStack {
                                Text(aspectMenuLabel(ratio))
                                if aspectRatio == ratio {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: aspectIcon(aspectRatio))
                            .font(.system(size: 11, weight: .semibold))
                        Text(aspectRatio.displayLabel)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7.5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(isDark ? 0.18 : 0.40), lineWidth: 0.8))
                }
                .tint(.primary)
                .disabled(isGenerating)
                .accessibilityIdentifier("ai.image.aspect")

                // Batch count glass pill (1张 / 2张 / 4张)
                Menu {
                    ForEach([1, 2, 4], id: \.self) { count in
                        Button {
                            Haptics.select()
                            batchCount = count
                        } label: {
                            HStack {
                                Text(count == 1 ? "1 张 · 极速省额度" : count == 2 ? "2 张 · 双图并发" : "4 张 · 四宫格并发")
                                if batchCount == count {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: batchCount == 1 ? "photo" : "square.grid.2x2")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(batchCount)张")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7.5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(isDark ? 0.18 : 0.40), lineWidth: 0.8))
                }
                .tint(.primary)
                .disabled(isGenerating)
                .accessibilityIdentifier("ai.image.count")

                Spacer(minLength: 2)

                // Fine quality / sliders popover button (mirrors Grok's right-side sliders button)
                Menu {
                    Section("画质与速度档位") {
                        ForEach(AIImageTool.Quality.allCases) { q in
                            Button {
                                Haptics.select()
                                quality = q
                            } label: {
                                HStack {
                                    Text(q.detailLabel)
                                    if quality == q {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    Section("画风预设") {
                        ForEach(StudioStylePreset.allCases) { preset in
                            Button {
                                Haptics.select()
                                selectedStyle = preset
                            } label: {
                                HStack {
                                    Text(preset.title)
                                    if selectedStyle == preset {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(isDark ? 0.18 : 0.40), lineWidth: 0.8))
                }
                .tint(.primary)
                .disabled(isGenerating)
                .accessibilityLabel("高级出图参数")
                .accessibilityIdentifier("ai.image.settings")
            }

            // Reference image preview strip + explicit T2I-only refusal guard (zero silent downgrade!)
            if let refThumb = referenceThumbnail {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(uiImage: refThumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("已附参考图（图生图 / 编辑模式）")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.primary)
                            if let note = referencePrepNote {
                                Text(note)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Button("更换") {
                            showingRefPhotoPicker = true
                        }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        Button {
                            referenceImage = nil
                            referenceThumbnail = nil
                            referencePrepNote = nil
                            referencePrepMs = 0
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除参考图")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                    if !activeSupportsReferenceImage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("当前模型仅支持纯文生图，不支持参考图（绝不悄悄降级）")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("切换支持模型") {
                                switchToReferenceCapableModel()
                            }
                            .font(.caption2.weight(.bold))
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.mini)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .accessibilityIdentifier("ai.image.refUnsupportedBanner")
                    }
                }
            }

            // Row 2: Frosted-Glass Prompt Composer Card (mirrors Grok IMG_4203 & ChatGPT composer!)
            VStack(spacing: 8) {
                TextField(referenceImage != nil ? "描述如何基于参考图修改或重绘…" : "输入即见所想…", text: $sessionStore.prompt, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...4)
                    .focused($promptFocused)
                    .disabled(isGenerating)
                    .submitLabel(.send)
                    .onSubmit {
                        handleGenerateTap()
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                    .accessibilityIdentifier("ai.image.prompt")

                HStack(spacing: 8) {
                    // + Style preset menu button
                    Menu {
                        Section("选择画面风格") {
                            ForEach(StudioStylePreset.allCases) { preset in
                                Button {
                                    Haptics.select()
                                    selectedStyle = preset
                                } label: {
                                    Label(preset.title, systemImage: preset.icon)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(isDark ? 0.12 : 0.08), in: Circle())
                    }
                    .tint(.primary)
                    .disabled(isGenerating)
                    .accessibilityLabel("选择画风预设")
                    .accessibilityIdentifier("ai.image.styleMenu")

                    // Reference-image upload button (PhotosPicker + FileImporter)
                    Menu {
                        Button {
                            dismissKeyboard()
                            showingRefPhotoPicker = true
                        } label: {
                            Label("从相册选择参考图", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            dismissKeyboard()
                            showingRefFileImporter = true
                        } label: {
                            Label("从文件导入参考图", systemImage: "folder")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: referenceImage != nil ? "photo.badge.checkmark.fill" : "photo.badge.plus")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(referenceImage != nil ? "已选参考图" : "添加参考图")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(referenceImage != nil ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            referenceImage != nil ? providerAccent : Color.primary.opacity(isDark ? 0.12 : 0.08),
                            in: Capsule()
                        )
                    }
                    .tint(.primary)
                    .disabled(isGenerating)
                    .accessibilityIdentifier("ai.image.addReference")

                    if selectedStyle != .none {
                        Button {
                            Haptics.tap()
                            selectedStyle = .none
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: selectedStyle.icon)
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text(selectedStyle.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(isDark ? .black : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isDark ? Color.white : Color.primary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 4)

                    if promptFocused && !isGenerating {
                        Button {
                            Haptics.tap()
                            dismissKeyboard()
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .background(Color.primary.opacity(isDark ? 0.12 : 0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("收起键盘")
                        .accessibilityIdentifier("ai.image.dismissKeyboard")
                    }

                    // Circular Generate ↑ / Stop ■ button
                    Button {
                        if isGenerating {
                            Haptics.warning()
                            stopGeneration()
                        } else {
                            handleGenerateTap()
                        }
                    } label: {
                        Group {
                            if isGenerating {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(DS.Palette.danger, in: Circle())
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(
                                        isPromptValid
                                            ? (isDark ? Color.black : Color.white)
                                            : Color.secondary
                                    )
                                    .frame(width: 34, height: 34)
                                    .background(
                                        isPromptValid
                                            ? (isDark ? Color.white : Color.black)
                                            : Color.primary.opacity(isDark ? 0.14 : 0.09),
                                        in: Circle()
                                    )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isGenerating && !isPromptValid)
                    .accessibilityLabel(isGenerating ? "停止生成" : "生成图片")
                    .accessibilityIdentifier("ai.image.generate")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(isDark ? 0.20 : 0.55), lineWidth: 0.9)
            )
            .shadow(color: .black.opacity(isDark ? 0.42 : 0.10), radius: 16, y: 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [canvasBackground.opacity(0), canvasBackground.opacity(0.88), canvasBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        )
    }

    /// Explicit user-selectable speed/quality tiers: never silently swaps model or lowers quality!
    private var speedToggleCapsule: some View {
        HStack(spacing: 2) {
            speedSegmentButton(title: "快速草稿", target: .fast, active: quality == .fast)
            speedSegmentButton(
                title: quality == .balanced ? "均衡" : "高清成品",
                target: .hd,
                active: quality != .fast
            )
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(isDark ? 0.18 : 0.40), lineWidth: 0.8))
        .accessibilityIdentifier("ai.image.speed")
    }

    private func speedSegmentButton(title: String, target: AIImageTool.Quality, active: Bool) -> some View {
        Button {
            Haptics.select()
            withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                quality = target
            }
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(
                    active
                        ? (isDark ? Color.black : Color.white)
                        : Color.secondary
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    active
                        ? (isDark ? Color.white : Color.black)
                        : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }

    // MARK: - Reference Image Preparation (Smart Downscale <= 1536px before upload!)

    private func handlePickedReferencePhoto(_ item: PhotosPickerItem) {
        Task { @MainActor in
            let prepStart = Date()
            defer { pickedRefPhotoItem = nil }
            guard let raw = try? await item.loadTransferable(type: Data.self), !raw.isEmpty else {
                showToast("未能读取所选参考图，请重试")
                return
            }
            applyPreparedReferenceImage(rawData: raw, filename: "reference.jpg", startedAt: prepStart)
        }
    }

    private func handleImportedReferenceFile(_ result: Result<[URL], Error>) {
        let prepStart = Date()
        guard case .success(let urls) = result, let url = urls.first else { return }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url), !raw.isEmpty else {
            showToast("未能读取导入的图片文件")
            return
        }
        applyPreparedReferenceImage(rawData: raw, filename: url.lastPathComponent, startedAt: prepStart)
    }

    private func applyPreparedReferenceImage(rawData: Data, filename: String, startedAt: Date) {
        guard let original = UIImage(data: rawData) else {
            showToast("图片格式不支持，请选择 JPG / PNG 图片")
            return
        }
        let maxSide: CGFloat = 1536
        let origW = original.size.width * original.scale
        let origH = original.size.height * original.scale
        let scale = min(1.0, maxSide / max(1, max(origW, origH)))
        let targetSize = CGSize(width: max(1, (origW * scale).rounded()), height: max(1, (origH * scale).rounded()))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            original.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let jpegData = resized.jpegData(compressionQuality: 0.85) else {
            showToast("参考图压缩失败，请重试")
            return
        }
        let elapsedMs = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
        referenceImage = AIImageTool.ReferenceImage(data: jpegData, mimeType: "image/jpeg", filename: "reference.jpg")
        referenceThumbnail = resized
        referencePrepMs = elapsedMs
        let origKB = max(1, rawData.count / 1024)
        let scaledKB = max(1, jpegData.count / 1024)
        referencePrepNote = "\(Int(targetSize.width))×\(Int(targetSize.height)) · \(origKB)KB→\(scaledKB)KB · 预处理 \(elapsedMs)ms"
        showToast("参考图已优化缩放（\(scaledKB)KB）")
    }

    private func switchToReferenceCapableModel() {
        if useManagedGateway {
            if let editModel = wmStore.enabledManagedImageEditModels.first {
                managedSelectedImageID = editModel.id
                showToast("已切换至 \(editModel.displayName)")
            } else {
                showToast("内置目录暂无已开通的参考图模型，请联系管理员。")
            }
        } else if let refModel = AIImageTool.models.first(where: \.supportsReferenceImage) {
            model = refModel
            showToast("已切换至 \(refModel.displayName)")
        }
    }

    // MARK: - Actions & Concurrency

    private func dismissKeyboard() {
        promptFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func hydratePreferences() {
        ownConnectionPreference = AIProviderEndpoints.imageStudioOwnConnectionPreference
        let configuredProviders = Set(AIProvider.allCases.filter { Keychain.providerChatAPIKey($0) != nil })
        let savedModelID = UserDefaults.standard.string(forKey: PrefKey.modelID)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let savedModelID, !savedModelID.isEmpty {
            managedSelectedImageID = savedModelID
            if let exact = AIImageTool.models.first(where: { $0.id.lowercased() == savedModelID.lowercased() }) {
                model = exact
            } else {
                model = AIImageTool.preferredModel(configuredProviders: configuredProviders, lastSelectedID: savedModelID)
            }
        } else {
            model = AIImageTool.preferredModel(configuredProviders: configuredProviders, lastSelectedID: nil)
            if let firstManaged = wmStore.enabledManagedImageModels.first {
                managedSelectedImageID = firstManaged.id
            } else {
                managedSelectedImageID = model.id
            }
        }

        if let rawQ = UserDefaults.standard.string(forKey: PrefKey.quality),
           let savedQ = AIImageTool.Quality(rawValue: rawQ) {
            quality = savedQ
        }
        if let rawA = UserDefaults.standard.string(forKey: PrefKey.aspect),
           let savedA = AIImageTool.AspectRatio(rawValue: rawA) {
            aspectRatio = savedA
        }
        let savedCount = UserDefaults.standard.integer(forKey: PrefKey.batchCount)
        if [1, 2, 4].contains(savedCount) {
            batchCount = savedCount
        }
        syncProviderState()
        credentialRevision += 1
        if useManagedGateway {
            refreshManagedCatalogIfNeeded(force: wmStore.enabledManagedImageModels.isEmpty)
        }
    }

    private func refreshManagedCatalogIfNeeded(force: Bool) {
        guard useManagedGateway, wmStore.hasGatewayURL, !isSyncingManagedCatalog else { return }
        if !force && !wmStore.enabledManagedImageModels.isEmpty { return }
        isSyncingManagedCatalog = true
        Task { @MainActor in
            defer {
                isSyncingManagedCatalog = false
                credentialRevision += 1
            }
            try? await wmStore.syncManagedGatewayConfig()
            if managedSelectedImageID.isEmpty, let first = wmStore.enabledManagedImageModels.first {
                managedSelectedImageID = first.id
            }
        }
    }

    private func invalidatePendingRetryKey() {
        pendingRetrySignature = nil
        pendingRetryIdempotencyKey = nil
    }

    private func recordDiagnostic(_ entry: AIImageRequestDiagnostic) {
        diagnostics.insert(entry, at: 0)
        if diagnostics.count > 20 {
            diagnostics.removeLast(diagnostics.count - 20)
        }
    }

    private func persistPreferences() {
        UserDefaults.standard.set(model.id, forKey: PrefKey.modelID)
        UserDefaults.standard.set(quality.rawValue, forKey: PrefKey.quality)
        UserDefaults.standard.set(aspectRatio.rawValue, forKey: PrefKey.aspect)
        UserDefaults.standard.set(batchCount, forKey: PrefKey.batchCount)
    }

    private func syncProviderState() {
        hasKey = Keychain.providerChatAPIKey(model.provider) != nil
        customHost = AIProviderEndpoints.displayHost(for: model.provider)
    }

    private func handleGenerateTap() {
        guard !isGenerating, isPromptValid else { return }
        dismissKeyboard()

        switch availabilityState {
        case .ready:
            break
        case .referenceImageUnsupported(_, let name):
            Haptics.warning()
            let msg = "当前模型（\(name)）仅支持纯文生图，不支持参考图编辑；请先切换支持参考图的模型后再生成。"
            failureMessage = msg
            lastClassifiedError = AIImageClassifiedError(category: .apiError, title: "模型不支持参考图", message: msg)
            return
        case .managedModelNotEnabled(_, let name, _):
            Haptics.warning()
            let msg = "\(name) 在 WuMind 内置通道暂未开通，不会要求填写厂商 Key 或自动切换自有 API。"
            failureMessage = msg
            lastClassifiedError = AIImageClassifiedError(category: .modelNotEnabled, title: "模型未开通", message: msg, httpStatus: 403)
            return
        case .managedCatalogSyncing:
            Haptics.warning()
            showToast("正在同步 WuMind 内置目录，请稍候…")
            return
        case .managedGatewayConfigInvalid(let detail):
            Haptics.warning()
            failureMessage = detail
            lastClassifiedError = AIImageClassifiedError(category: .missingConnection, title: "网关配置无效", message: detail)
            return
        case .managedLoginRequired(let detail):
            Haptics.warning()
            failureMessage = detail
            lastClassifiedError = AIImageClassifiedError(category: .missingConnection, title: "需登录 WuMind 账号", message: detail)
            return
        case .missingConnection(_, let title, let detail, let action):
            Haptics.warning()
            failureMessage = detail
            lastClassifiedError = AIImageClassifiedError(category: .missingConnection, title: title, message: detail)
            switch action {
            case .configureAIHubMix:
                settingAIHubMix = true
            case .configureDirectVendor:
                settingKey = true
            case .openGatewayAccount:
                break
            }
            return
        }

        Haptics.tap()
        let text = cleanedPrompt
        prompt = ""
        startGeneration(rawPrompt: text, overrideQuality: nil)
    }

    private func triggerHDUpgrade(prompt rawPrompt: String) {
        guard !isGenerating else { return }
        dismissKeyboard()
        if !availabilityState.isReady {
            switch availabilityState {
            case .missingConnection(_, _, _, let action):
                if case .configureAIHubMix = action {
                    settingAIHubMix = true
                } else if case .configureDirectVendor = action {
                    settingKey = true
                }
            default:
                failureMessage = availabilityState.bannerDetail ?? "当前不可升级超清"
            }
            return
        }
        startGeneration(rawPrompt: rawPrompt, overrideQuality: .hd, overrideCount: 1)
    }

    private func startGeneration(rawPrompt: String, overrideQuality: AIImageTool.Quality?, overrideCount: Int? = nil) {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetRef = referenceImage
        let prepMs = targetRef != nil ? referencePrepMs : 0
        if targetRef != nil && !activeSupportsReferenceImage {
            failureMessage = "当前模型不支持参考图编辑，请切换到支持参考图的模型（绝不悄悄降级）。"
            return
        }

        let snap = credentialSnapshot
        let currentRoute = availabilityState.routeKind
        let targetModel = activeEvaluationModel
        let targetQuality = overrideQuality ?? quality
        let targetAspect = aspectRatio
        let targetCount = targetRef != nil ? 1 : (overrideCount ?? batchCount)
        let styleSuffix = selectedStyle.promptSuffix
        let effectivePrompt = styleSuffix.map { trimmed + $0 } ?? trimmed
        let workModelID = useManagedGateway ? (activeManagedImageModel?.id ?? targetModel.id) : targetModel.id

        // Deterministic idempotency key: retry after timeout/network interruption reuses the EXACT same key!
        let requestSignature = "\(currentRoute.rawValue)|\(workModelID)|\(effectivePrompt)|\(targetQuality.rawValue)|\(targetAspect.rawValue)|\(targetCount)|\(targetRef?.data.count ?? 0)"
        let idemKey: String
        if let savedSig = pendingRetrySignature, savedSig == requestSignature, let savedKey = pendingRetryIdempotencyKey {
            idemKey = savedKey
        } else {
            idemKey = "img-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))"
        }
        let clientReqID = "CLI-\(UUID().uuidString.prefix(8))"

        let runID = UUID()
        let sessionID = UUID()
        let startedAt = Date()
        let initialSlots = (0..<targetCount).map { StudioSlot(id: UUID(), index: $0) }
        let displayOverride = useManagedGateway ? activeManagedImageModel?.displayName : nil
        let newSession = StudioSession(
            id: sessionID,
            rawPrompt: trimmed,
            effectivePrompt: effectivePrompt,
            styleName: selectedStyle == .none ? nil : selectedStyle.title,
            model: targetModel,
            modelDisplayOverride: displayOverride,
            usedReferenceImage: targetRef != nil,
            quality: targetQuality,
            aspectRatio: targetAspect,
            startedAt: startedAt,
            slots: initialSlots,
            finishedAt: nil,
            errorMessage: nil,
            stageTiming: nil
        )

        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
            sessions.insert(newSession, at: 0)
        }
        failureMessage = nil
        lastClassifiedError = nil
        activeRunID = runID

        let modeString = targetRef != nil ? "image_edit" : "text_to_image"
        let work = WuMindWorksStore.shared.recordSubmittedTask(
            workType: .image,
            title: String(trimmed.prefix(40)),
            prompt: trimmed,
            modelID: workModelID,
            params: [
                "tier": targetQuality == .fast ? "快速草稿" : "高清成品",
                "aspect": targetAspect.rawValue,
                "mode": modeString,
                "route": currentRoute.rawValue,
            ],
            status: "in_progress",
            progress: 15,
            idempotencyKey: idemKey
        )

        // PATH 1: WuMind 内置 (Managed Billing Gateway) — NEVER reads local vendor keys, NEVER falls back to Own API!
        if useManagedGateway {
            guard let managedModel = activeManagedImageModel else {
                let msg = "\(targetModel.shortStudioName) 在 WuMind 内置通道暂未开通（不会要求填写厂商 Key，也不会静默切至自有 API）。"
                failureMessage = msg
                lastClassifiedError = AIImageClassifiedError(category: .modelNotEnabled, title: "模型未开通", message: msg, httpStatus: 403)
                recordDiagnostic(
                    .sanitized(
                        requestID: clientReqID,
                        route: .managedGateway,
                        modelID: targetModel.id,
                        mode: modeString,
                        endpointDisplay: "wumind-gateway/local-guard",
                        httpStatus: 403,
                        errorCategory: .modelNotEnabled,
                        billingResult: "not_charged",
                        idempotencyKey: idemKey,
                        succeeded: false
                    )
                )
                finalizeSession(sessionID: sessionID, errorMessage: msg)
                WuMindWorksStore.shared.failWork(id: work.id, errorMessage: msg)
                activeRunID = nil
                return
            }

            let sizeStr: String = {
                switch targetAspect {
                case .square: return "1024x1024"
                case .landscape: return "1536x1024"
                case .portrait, .tall: return "1024x1536"
                }
            }()
            let qStr = targetQuality == .fast ? "low" : "high"

            activeTask = Task { @MainActor in
                defer {
                    if activeRunID == runID {
                        activeRunID = nil
                        activeTask = nil
                        liveStageLabel = nil
                    }
                }
                do {
                    liveStageLabel = targetRef != nil ? "1/4 上传缩放参考图 → 2/4 网关提交中…" : "2/4 WuMind 内置网关提交中…"
                    let token = try await wmStore.ensureManagedAccount()
                    let reqStart = Date()
                    liveStageLabel = "3/4 WuMind 内置（\(managedModel.displayName)）出图中…"
                    let res = try await WuMindGatewayClient().generateManagedImages(
                        gatewayURL: wmStore.gatewayBaseURL,
                        userToken: token,
                        modelID: managedModel.id,
                        prompt: effectivePrompt,
                        size: sizeStr,
                        aspectRatio: targetAspect.apiRatio,
                        quality: qStr,
                        n: targetCount,
                        outputFormat: "jpeg",
                        referenceImage: targetRef,
                        idempotencyKey: idemKey
                    )
                    guard activeRunID == runID, !Task.isCancelled else { return }
                    let netMs = Int(Date().timeIntervalSince(reqStart) * 1000)
                    let gwMs = res.timing?.gatewaySubmitMs ?? max(1, netMs / 8)
                    let upMs = res.timing?.upstreamGenerateMs ?? max(1, netMs - gwMs)

                    liveStageLabel = "4/4 解码与显示首图…"
                    let renderStart = Date()
                    var firstImageData: Data? = nil
                    for (idx, item) in res.data.enumerated() {
                        if let raw = Data(base64Encoded: item.b64_json),
                           let decoded = await Self.decodeImageOffMain(raw) {
                            if firstImageData == nil { firstImageData = raw }
                            updateSlot(
                                sessionID: sessionID,
                                slotIndex: idx,
                                image: UIImage(cgImage: decoded.0),
                                pixelSize: decoded.1,
                                elapsed: Date().timeIntervalSince(startedAt)
                            )
                        } else {
                            markSlotFailed(sessionID: sessionID, slotIndex: idx)
                        }
                    }
                    let displayMs = max(1, Int(Date().timeIntervalSince(renderStart) * 1000))
                    let totalMs = Int(Date().timeIntervalSince(startedAt) * 1000) + prepMs
                    let timing = WuMindCloudWorkTiming(
                        uploadPrepareMs: prepMs,
                        gatewaySubmitMs: gwMs,
                        upstreamGenerateMs: upMs,
                        displayRenderMs: displayMs,
                        totalMs: totalMs
                    )
                    if let sIdx = sessions.firstIndex(where: { $0.id == sessionID }) {
                        sessions[sIdx].stageTiming = timing
                    }
                    let decodedAny = (firstImageData != nil)
                    let decodeFailureMsg = res.data.isEmpty
                        ? "网关未返回可用图片。"
                        : "网关返回的图片数据无法解码显示。"
                    if let firstImageData {
                        _ = WuMindWorksStore.shared.completeWork(
                            id: work.id,
                            assetData: firstImageData,
                            assetMime: "image/jpeg",
                            assetExtension: "jpg",
                            timing: timing,
                            remoteWorkID: res.workID
                        )
                    } else {
                        WuMindWorksStore.shared.failWork(id: work.id, errorMessage: decodeFailureMsg)
                    }
                    let billingDesc: String = {
                        if res.idempotentReplay == true {
                            return "幂等回放（0 重复扣费）"
                        }
                        if let b = res.billing {
                            return String(format: "WuMind 实扣 ¥%.3f · 余额 ¥%.2f", b.costYuan, b.balanceYuan)
                        }
                        return res.billingResult ?? "WuMind 已结算"
                    }()
                    recordDiagnostic(
                        .sanitized(
                            requestID: res.requestID ?? clientReqID,
                            route: .managedGateway,
                            modelID: managedModel.id,
                            mode: modeString,
                            endpointDisplay: res.endpoint ?? "/v1/images",
                            httpStatus: 200,
                            errorCategory: decodedAny ? nil : .apiError,
                            billingResult: billingDesc,
                            idempotencyKey: idemKey,
                            succeeded: decodedAny
                        )
                    )
                    invalidatePendingRetryKey()
                    finalizeSession(sessionID: sessionID, errorMessage: decodedAny ? nil : decodeFailureMsg)
                    if let b = res.billing { wmStore.managedBalanceYuan = b.balanceYuan }
                    try? await wmStore.refreshManagedAccount()
                    if decodedAny {
                        Haptics.success()
                    } else {
                        failureMessage = decodeFailureMsg
                        lastClassifiedError = AIImageClassifiedError(category: .apiError, title: "图片解码失败", message: decodeFailureMsg, httpStatus: 200)
                        Haptics.warning()
                    }
                } catch is CancellationError {
                    finalizeSession(sessionID: sessionID, errorMessage: "已停止等待。")
                } catch {
                    guard activeRunID == runID, !Task.isCancelled else { return }
                    let classified = AIImageErrorClassifier.classify(error: error, route: .managedGateway)
                    if classified.isRetryableWithSameIdempotencyKey {
                        pendingRetrySignature = requestSignature
                        pendingRetryIdempotencyKey = idemKey
                    } else {
                        invalidatePendingRetryKey()
                    }
                    lastClassifiedError = classified
                    failureMessage = classified.message
                    recordDiagnostic(
                        .sanitized(
                            requestID: clientReqID,
                            route: .managedGateway,
                            modelID: managedModel.id,
                            mode: modeString,
                            endpointDisplay: "wumind-gateway/\(modeString)",
                            httpStatus: classified.httpStatus,
                            errorCategory: classified.category,
                            billingResult: "未扣费（预留已释放）",
                            idempotencyKey: idemKey,
                            succeeded: false
                        )
                    )
                    finalizeSession(sessionID: sessionID, errorMessage: classified.message)
                    WuMindWorksStore.shared.failWork(id: work.id, errorMessage: classified.message)
                    Haptics.warning()
                }
            }
            return
        }

        // PATH 2: 自有 API (AIHubMix Decoupled Connection OR Direct Vendor Key — 0 WuMind balance deduction!)
        guard let ownTarget = AIImageStudioAvailability.resolveOwnExecutionTarget(
            model: targetModel,
            snapshot: snap,
            directAPIKeyProvider: { Keychain.providerChatAPIKey($0, baseURL: snap.directProviderBaseURLs[$0]) }
        ) else {
            let msg = ownConnectionPreference == .aihubmix
                ? "尚未配置 AIHubMix 连接，请保存 AIHubMix API Key 后重试。"
                : "尚未配置可用连接，请配置 AIHubMix 统一连接或 \(targetModel.provider.displayName) 直连 API Key。"
            failureMessage = msg
            lastClassifiedError = AIImageClassifiedError(category: .missingConnection, title: "缺连接", message: msg)
            finalizeSession(sessionID: sessionID, errorMessage: msg)
            WuMindWorksStore.shared.failWork(id: work.id, errorMessage: msg)
            activeRunID = nil
            return
        }

        let options = AIImageTool.Options(
            quality: targetQuality,
            aspectRatio: targetAspect,
            outputFormat: .jpeg,
            customBaseURL: ownTarget.baseURL,
            requireAggregatorHost: ownTarget.requireAggregatorHost
        )

        activeTask = Task { @MainActor in
            defer {
                if activeRunID == runID {
                    activeRunID = nil
                    activeTask = nil
                    liveStageLabel = nil
                }
            }

            do {
                liveStageLabel = targetRef != nil
                    ? "1/4 上传参考图 → 3/4 \(ownTarget.route.badgeText)（\(targetModel.shortStudioName)）出图中…"
                    : "3/4 \(ownTarget.route.badgeText)（\(targetModel.shortStudioName)）出图中…"
                let reqStart = Date()
                @MainActor final class FirstSlotBox {
                    var rawData: Data? = nil
                    var displayMs: Int = 0
                    var endpointDisplay: String = ""
                    var httpStatus: Int = 200
                }
                let firstSlot = FirstSlotBox()

                let results = try await AIImageTool().generateBatch(
                    model: targetModel,
                    apiKey: ownTarget.apiKey,
                    prompt: effectivePrompt,
                    count: targetCount,
                    referenceImage: targetRef,
                    options: options
                ) { @MainActor slotResult in
                    liveStageLabel = "4/4 解码与显示首图…"
                    let decodeStart = Date()
                    let decoded = await Self.decodeImageOffMain(slotResult.data)
                    let dMs = max(1, Int(Date().timeIntervalSince(decodeStart) * 1000))
                    guard activeRunID == runID else { return }
                    if let decoded {
                        if firstSlot.rawData == nil {
                            firstSlot.rawData = slotResult.data
                            firstSlot.displayMs = dMs
                            firstSlot.endpointDisplay = slotResult.endpointDisplay ?? (ownTarget.baseURL ?? targetModel.provider.defaultBaseURLString)
                            firstSlot.httpStatus = slotResult.httpStatus ?? 200
                        }
                        updateSlot(
                            sessionID: sessionID,
                            slotIndex: slotResult.index,
                            image: UIImage(cgImage: decoded.0),
                            pixelSize: decoded.1,
                            elapsed: slotResult.elapsedSeconds
                        )
                    } else {
                        markSlotFailed(sessionID: sessionID, slotIndex: slotResult.index)
                    }
                }

                guard activeRunID == runID, !Task.isCancelled else { return }
                let upstreamMs = max(1, Int(Date().timeIntervalSince(reqStart) * 1000) - firstSlot.displayMs)
                let timing = WuMindCloudWorkTiming(
                    uploadPrepareMs: prepMs,
                    gatewaySubmitMs: 0,
                    upstreamGenerateMs: upstreamMs,
                    displayRenderMs: firstSlot.displayMs,
                    totalMs: Int(Date().timeIntervalSince(startedAt) * 1000) + prepMs
                )
                if let sIdx = sessions.firstIndex(where: { $0.id == sessionID }) {
                    sessions[sIdx].stageTiming = timing
                }
                let decodedAny = (firstSlot.rawData != nil) && !results.isEmpty
                let decodeFailureMsg = results.isEmpty
                    ? "服务商未返回可用图片。"
                    : "服务商返回的图片数据无法解码显示。"
                if let firstRawData = firstSlot.rawData {
                    _ = WuMindWorksStore.shared.completeWork(
                        id: work.id,
                        assetData: firstRawData,
                        assetMime: "image/jpeg",
                        assetExtension: "jpg",
                        timing: timing
                    )
                } else {
                    WuMindWorksStore.shared.failWork(id: work.id, errorMessage: decodeFailureMsg)
                }
                recordDiagnostic(
                    .sanitized(
                        requestID: clientReqID,
                        route: ownTarget.route,
                        modelID: targetModel.id,
                        mode: modeString,
                        endpointDisplay: firstSlot.endpointDisplay,
                        httpStatus: firstSlot.httpStatus,
                        errorCategory: decodedAny ? nil : .apiError,
                        billingResult: ownTarget.route == .ownAIHubMix ? "AIHubMix 计费（WuMind ¥0）" : "厂商自有计费（WuMind ¥0）",
                        idempotencyKey: idemKey,
                        succeeded: decodedAny
                    )
                )
                invalidatePendingRetryKey()
                finalizeSession(sessionID: sessionID, errorMessage: decodedAny ? nil : decodeFailureMsg)
                if decodedAny {
                    Haptics.success()
                } else {
                    failureMessage = decodeFailureMsg
                    lastClassifiedError = AIImageClassifiedError(category: .apiError, title: "图片解码失败", message: decodeFailureMsg, httpStatus: firstSlot.httpStatus)
                    Haptics.warning()
                }
            } catch is CancellationError {
                finalizeSession(sessionID: sessionID, errorMessage: "已停止等待。")
            } catch {
                guard activeRunID == runID, !Task.isCancelled else { return }
                let classified = AIImageErrorClassifier.classify(error: error, route: ownTarget.route)
                if classified.isRetryableWithSameIdempotencyKey {
                    pendingRetrySignature = requestSignature
                    pendingRetryIdempotencyKey = idemKey
                } else {
                    invalidatePendingRetryKey()
                }
                lastClassifiedError = classified
                failureMessage = classified.message
                recordDiagnostic(
                    .sanitized(
                        requestID: clientReqID,
                        route: ownTarget.route,
                        modelID: targetModel.id,
                        mode: modeString,
                        endpointDisplay: targetModel.provider.resolvedHost(baseURL: ownTarget.baseURL),
                        httpStatus: classified.httpStatus,
                        errorCategory: classified.category,
                        billingResult: "未扣 WuMind 余额",
                        idempotencyKey: idemKey,
                        succeeded: false
                    )
                )
                finalizeSession(sessionID: sessionID, errorMessage: classified.message)
                WuMindWorksStore.shared.failWork(id: work.id, errorMessage: classified.message)
                Haptics.warning()
            }
        }
    }

    private func updateSlot(sessionID: UUID, slotIndex: Int, image: UIImage, pixelSize: CGSize, elapsed: Double) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[sIdx].slots.indices.contains(slotIndex) else { return }
        withAnimation(.easeOut(duration: 0.28)) {
            sessions[sIdx].slots[slotIndex].image = image
            sessions[sIdx].slots[slotIndex].pixelSize = pixelSize
            sessions[sIdx].slots[slotIndex].elapsedSeconds = elapsed
        }
    }

    private func markSlotFailed(sessionID: UUID, slotIndex: Int) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[sIdx].slots.indices.contains(slotIndex) else { return }
        sessions[sIdx].slots[slotIndex].failed = true
    }

    private func finalizeSession(sessionID: UUID, errorMessage: String?) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        for idx in sessions[sIdx].slots.indices where sessions[sIdx].slots[idx].image == nil {
            sessions[sIdx].slots[idx].failed = true
        }
        sessions[sIdx].finishedAt = Date()
        sessions[sIdx].errorMessage = errorMessage
    }

    private func stopGeneration() {
        if activeRunID != nil {
            activeRunID = nil
            if let first = sessions.first, first.isGenerating {
                finalizeSession(sessionID: first.id, errorMessage: "已停止等待（已发出的请求可能仍产生 API 用量）。")
            }
        }
        activeTask?.cancel()
        activeTask = nil
    }

    private func saveImageToAlbum(_ image: UIImage) {
        PhotoAlbumSaver.save(image) { success in
            showToast(success ? "已保存到系统相册" : "保存失败，请在系统设置开启相册写入权限")
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            toastMessage = text
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_100_000_000)
            if toastMessage == text {
                withAnimation(.easeOut(duration: 0.22)) {
                    toastMessage = nil
                }
            }
        }
    }

    private func aspectMenuLabel(_ ratio: AIImageTool.AspectRatio) -> String {
        switch ratio {
        case .portrait: return "2:3 · 竖图人像"
        case .square: return "1:1 · 经典方图"
        case .landscape: return "3:2 · 电影横画"
        case .tall: return "9:16 · 手机壁纸"
        }
    }

    private func aspectIcon(_ ratio: AIImageTool.AspectRatio) -> String {
        switch ratio {
        case .portrait, .tall: return "rectangle.portrait"
        case .square: return "square"
        case .landscape: return "rectangle"
        }
    }

    /// Off-main-thread raster decoding with immediate pixel decompression so gallery scrolling stays 120fps.
    nonisolated private static func decodeImageOffMain(_ data: Data) async -> (CGImage, CGSize)? {
        await Task.detached(priority: .userInitiated) {
            let options = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, options),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  height > 0, width > 0, height <= 4_096, width <= 4_096,
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options) else { return nil }
            return (cgImage, CGSize(width: width, height: height))
        }.value
    }
}

// MARK: - Animated Shimmer Skeleton Card

private struct StudioShimmerCard: View {
    let aspectRatio: CGFloat
    let accent: Color
    let startedAt: Date
    let slotLabel: String
    let isDark: Bool

    @State private var shimmerPhase: CGFloat = -1.0

    var body: some View {
        ZStack {
            Color.clear
                .aspectRatio(aspectRatio, contentMode: .fit)
                .background(
                    LinearGradient(
                        colors: isDark
                            ? [Color.white.opacity(0.06), accent.opacity(0.14), Color.white.opacity(0.05)]
                            : [Color.black.opacity(0.04), accent.opacity(0.10), Color.black.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            GeometryReader { geo in
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(isDark ? 0.14 : 0.40),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: geo.size.width * 0.75)
                .offset(x: shimmerPhase * geo.size.width * 1.4)
            }
            .clipped()

            TimelineView(.periodic(from: startedAt, by: 0.25)) { context in
                let sec = max(0.0, context.date.timeIntervalSince(startedAt))
                VStack(spacing: 7) {
                    ProgressView()
                        .tint(isDark ? .white : accent)
                    Text("绘图中 \(String(format: "%.1fs", sec))")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(isDark ? .white.opacity(0.86) : .primary)
                    Text(slotLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.45).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.2
            }
        }
    }
}

// MARK: - Full-Screen Pinch-Zoom Lightbox

private struct ImageStudioLightbox: View {
    let image: UIImage
    let pixelSize: CGSize?
    let prompt: String
    let modelName: String
    let quality: AIImageTool.Quality
    let elapsedSeconds: Double?
    let onUpscale: () -> Void
    let onCopied: () -> Void
    let onSaved: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var steadyScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(4.0, max(1.0, steadyScale * value))
                        }
                        .onEnded { _ in
                            steadyScale = scale
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        if scale > 1.2 {
                            scale = 1.0
                            steadyScale = 1.0
                        } else {
                            scale = 2.2
                            steadyScale = 2.2
                        }
                    }
                }
                .padding(.vertical, 64)

            // Top translucent header
            VStack {
                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("关闭预览")

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(modelName) · \(quality.shortLabel)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        if let pixelSize {
                            let timePart = elapsedSeconds.map { String(format: " · %.1fs", $0) } ?? ""
                            Text("\(Int(pixelSize.width))×\(Int(pixelSize.height))\(timePart)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                // Bottom prompt caption + 4-button studio action bar
                VStack(spacing: 12) {
                    Text(prompt)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    HStack(spacing: 8) {
                        lightboxButton(title: "存相册", icon: "square.and.arrow.down") {
                            Haptics.tap()
                            PhotoAlbumSaver.save(image, completion: onSaved)
                        }

                        let shareImg = Image(uiImage: image)
                        ShareLink(item: shareImg, preview: SharePreview(prompt, image: shareImg)) {
                            VStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("分享")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        lightboxButton(title: "提高质量", icon: "sparkles") {
                            Haptics.tap()
                            onUpscale()
                        }

                        lightboxButton(title: "复制词", icon: "doc.on.doc") {
                            Haptics.tap()
                            UIPasteboard.general.string = prompt
                            onCopied()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func lightboxButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Safe One-Tap Photo Album Writer

@MainActor
private final class PhotoAlbumSaver: NSObject {
    private let completion: (Bool) -> Void

    private init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    static func save(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        let helper = PhotoAlbumSaver(completion: completion)
        let retained = Unmanaged.passRetained(helper).toOpaque()
        UIImageWriteToSavedPhotosAlbum(
            image,
            helper,
            #selector(handleSave(_:didFinishSavingWithError:contextInfo:)),
            retained
        )
    }

    @objc nonisolated private func handleSave(
        _ image: UIImage,
        didFinishSavingWithError error: Error?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        let succeeded = (error == nil)
        let pointerBits = contextInfo.map { UInt(bitPattern: $0) }
        Task { @MainActor in
            guard let bits = pointerBits, let ptr = UnsafeMutableRawPointer(bitPattern: bits) else { return }
            let saver = Unmanaged<PhotoAlbumSaver>.fromOpaque(ptr).takeRetainedValue()
            saver.completion(succeeded)
        }
    }
}

private extension Color {
    static let amberStudio = Color(red: 0.96, green: 0.68, blue: 0.22)
}

// MARK: - Sanitized Image Studio Diagnostics Sheet (Zero Keys / Prompts / Reference Images!)

@MainActor
private struct ImageStudioDiagnosticsSheet: View {
    let routeBadge: String
    let activeModelID: String
    let entries: [AIImageRequestDiagnostic]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("当前画室路由") {
                    LabeledContent("当前路由", value: routeBadge)
                    LabeledContent("当前模型", value: activeModelID)
                    Text("脱敏诊断仅保留 requestID、模型、路由、HTTP 状态码与计费结果，绝不记录 API Key、提示词或参考图。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("最近请求记录（\(entries.count) 条）") {
                    if entries.isEmpty {
                        Text("本次画室会话尚无生图请求记录。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(entry.requestID)
                                        .font(.caption.monospaced().weight(.bold))
                                    Spacer()
                                    Text(entry.succeeded ? "成功" : (entry.errorCategory?.label ?? "失败"))
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(entry.succeeded ? Color.green : DS.Palette.danger)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(
                                            (entry.succeeded ? Color.green : DS.Palette.danger).opacity(0.12),
                                            in: Capsule()
                                        )
                                }
                                Text("\(entry.routeBadge) · \(entry.modelID) · \(entry.mode)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.primary)
                                Text("端点：\(entry.endpointDisplay) · HTTP \(entry.httpStatus.map(String.init) ?? "-")")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text("计费：\(entry.billingResult)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let idem = entry.idempotencyKeyPrefix {
                                    Text("幂等键前缀：\(idem)…")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .navigationTitle("画室脱敏诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
