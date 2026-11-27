import AVKit
import SwiftUI
import UIKit

/// Flagship WUMIND AI Video Studio (OpenAI Sora 2 · Google Veo 3 · Grok Imagine Video).
/// Supports BOTH WUMIND Managed Gateway (`/v1/videos`) and Own API / AIHubMix relay,
/// enforces per-model valid durations (e.g. Sora 2: 4 / 8 / 12s) & aspect ratios,
/// auto-archives every task to 「我的作品」 / 「历史」 with zero double-charge recovery.
@MainActor
struct AIVideoToolView: View {
    private static let lastModelKey = "wumind.video.lastModelID"

    private typealias GeneratedClip = AIVideoStudioSessionStore.GeneratedClip
    private typealias UnconfirmedManagedVideoJob = AIVideoStudioSessionStore.UnconfirmedManagedVideoJob

    private struct InspirationCard: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let prompt: String
        let icon: String
    }

    private static let inspirations: [InspirationCard] = [
        .init(
            title: "赛博雨夜穿梭",
            subtitle: "霓虹镜头 · 低空航拍",
            prompt: "电影级低空航拍镜头穿过午夜赛博朋克都市霓虹街道，细雨反光，体积光穿过云雾，4K 电影质感运镜平滑",
            icon: "sparkles.tv.fill"
        ),
        .init(
            title: "轨道空间站日出",
            subtitle: "科幻写实 · 黄金光晕",
            prompt: "近地轨道空间站舷窗视角，太阳从蔚蓝地球边缘缓缓升起，金色阳光洒在太阳能帆板上，极度写实 NASA 胶片质感",
            icon: "globe.asia.australia.fill"
        ),
        .init(
            title: "东方水墨鹤影",
            subtitle: "国风流动 · 慢动作",
            prompt: "中国传统青绿山水云雾缭绕，一只仙鹤振翅掠过松林与瀑布，水墨粒子随气流缓缓散开，诗意慢动作镜头",
            icon: "wind"
        ),
        .init(
            title: "旗舰产品发布会",
            subtitle: "棚拍微距 · 商业广告",
            prompt: "极简黑色镜面舞台上，一块钛金属智能设备在柔和轮廓光中缓慢旋转，金属拉丝与玻璃折射精致细腻，苹果发布会商业广告镜头",
            icon: "cube.transparent.fill"
        ),
    ]

    private enum StudioMode: String, CaseIterable, Identifiable {
        case shortDrama
        case singleClip

        var id: String { rawValue }
        var title: String {
            switch self {
            case .shortDrama: return "短剧"
            case .singleClip: return "单镜头直出"
            }
        }
        var icon: String {
            switch self {
            case .shortDrama: return "clapperboard.fill"
            case .singleClip: return "film.stack.fill"
            }
        }
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var wmStore = WuMindStore.shared
    @ObservedObject private var sessionStore = AIVideoStudioSessionStore.shared
    @State private var studioMode: StudioMode = .shortDrama
    @State private var showingDramaAPIConfig = false
    @State private var showingHistory = false
    @State private var showingGenerationStage = false
    @State private var stagePrompt = ""
    @State private var stagePreviousClipID: UUID?
    @State private var stageOwner: String?
    @State private var model: AIVideoTool.Model
    @State private var isSyncingModels = false
    @State private var syncStatusNote: String? = nil
    @State private var aspect: AIVideoTool.AspectRatio = .landscape16x9
    @State private var durationSeconds = 5
    @State private var resolution: AIVideoTool.Resolution = .hd720
    @State private var configuringProvider: AIProvider?
    @FocusState private var promptFocused: Bool

    private var discoveredModels: [AIVideoTool.Model] {
        get { sessionStore.discoveredModels }
        nonmutating set { sessionStore.discoveredModels = newValue }
    }
    private var managedSelectedVideoID: String {
        get { sessionStore.managedSelectedVideoID }
        nonmutating set { sessionStore.managedSelectedVideoID = newValue }
    }
    private var prompt: String {
        get { sessionStore.prompt }
        nonmutating set { sessionStore.prompt = newValue }
    }
    private var isGenerating: Bool {
        get { sessionStore.isGenerating }
        nonmutating set { sessionStore.isGenerating = newValue }
    }
    private var activeJobID: String? {
        get { sessionStore.activeJobID }
        nonmutating set { sessionStore.activeJobID = newValue }
    }
    private var unconfirmedJob: UnconfirmedManagedVideoJob? {
        get { sessionStore.unconfirmedJob }
        nonmutating set { sessionStore.unconfirmedJob = newValue }
    }
    private var progress: AIVideoTool.ProgressUpdate? {
        get { sessionStore.progress }
        nonmutating set { sessionStore.progress = newValue }
    }
    private var clips: [GeneratedClip] {
        get { sessionStore.clips }
        nonmutating set { sessionStore.clips = newValue }
    }
    private var activePlayer: AVPlayer? {
        get { sessionStore.activePlayer }
        nonmutating set { sessionStore.activePlayer = newValue }
    }
    private var activeClipID: UUID? {
        get { sessionStore.activeClipID }
        nonmutating set { sessionStore.activeClipID = newValue }
    }
    private var errorMessage: String? {
        get { sessionStore.errorMessage }
        nonmutating set { sessionStore.errorMessage = newValue }
    }
    private var generateTask: Task<Void, Never>? {
        get { sessionStore.generateTask }
        nonmutating set { sessionStore.generateTask = newValue }
    }

    init() {
        let configured = Set(AIProvider.allCases.filter { Keychain.providerChatAPIKey($0) != nil })
        let openAIUsesRelay = AIProviderToolHTTP.isOpenAICompatibleRelay(AIProviderEndpoints.baseURL(for: .openAI))
        let savedID = UserDefaults.standard.string(forKey: Self.lastModelKey)
        let chosen = AIVideoTool.preferredModel(
            configuredProviders: configured,
            lastSelectedID: savedID,
            openAIUsesRelay: openAIUsesRelay
        )
        _model = State(initialValue: chosen)
        _durationSeconds = State(initialValue: chosen.defaultDuration)
    }

    private var canvasBg: Color { DS.Palette.background }
    private var cardBg: Color { DS.Palette.cardSurface }

    private var useManagedGateway: Bool {
        wmStore.channel == .managed
    }

    private var openAIUsesRelay: Bool {
        AIProviderToolHTTP.isOpenAICompatibleRelay(AIProviderEndpoints.baseURL(for: .openAI))
    }

    private var ownAPIModels: [AIVideoTool.Model] {
        let builtIn = AIVideoTool.availableBuiltInModels(openAIUsesRelay: openAIUsesRelay)
        guard !discoveredModels.isEmpty else { return builtIn }
        var seen = Set(builtIn.map(\.id))
        var merged = builtIn
        for extra in discoveredModels where seen.insert(extra.id).inserted {
            merged.append(extra)
        }
        return merged
    }

    private var activeManagedVideoModel: WuMindCatalogModel? {
        let list = wmStore.enabledManagedVideoModels
        if let hit = list.first(where: { $0.id == managedSelectedVideoID }) { return hit }
        return list.first
    }

    private var activeModelID: String {
        if useManagedGateway { return activeManagedVideoModel?.id ?? "" }
        return model.id
    }

    private var activeModelDisplayName: String {
        if useManagedGateway { return activeManagedVideoModel?.displayName ?? "内置视频模型暂不可用" }
        return model.displayName
    }

    /// Valid durations strictly matched to the selected model (e.g. Sora 2 -> [4, 8, 12], Wan 2.6 -> [5, 8, 10]).
    private var validDurations: [Int] {
        if useManagedGateway, let secs = activeManagedVideoModel?.supportedParams?.seconds, !secs.isEmpty {
            return secs
        }
        return model.supportedDurations
    }

    private var validAspects: [AIVideoTool.AspectRatio] {
        if activeModelID.lowercased().contains("sora") {
            return [.landscape16x9, .portrait9x16]
        }
        return model.supportedAspectRatios
    }

    private var hasKey: Bool {
        useManagedGateway ? (wmStore.hasGatewayURL && activeManagedVideoModel != nil) : (Keychain.providerChatAPIKey(model.provider) != nil)
    }
    private var hasAnyDramaKey: Bool {
        WuMindDramaVideoEngine.allCases.contains { WuMindShortDramaStore.shared.isEngineConfigured($0) }
    }
    private var canSubmit: Bool {
        !isGenerating && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    studioModeSwitcher

                    if studioMode == .shortDrama {
                        WuMindShortDramaView(showingAPIConfig: $showingDramaAPIConfig)
                    } else {
                        AppSectionCard(title: "镜头描述") {
                            TextField("描述画面、镜头运动和光线", text: $sessionStore.prompt, axis: .vertical)
                                .lineLimit(3...7)
                                .font(DS.Font.body)
                                .focused($promptFocused)
                                .accessibilityLabel("镜头描述")
                                .accessibilityIdentifier("ai.video.prompt")
                        }
                        controlBar

                        if !hasKey {
                            missingKeyCard
                        }

                        if let errorMessage {
                            errorBanner(errorMessage)
                        }

                        if isGenerating {
                            generatingHUD
                                .id("video.progress")
                        }

                        if clips.isEmpty && !isGenerating {
                            emptyStage
                        } else if !clips.isEmpty {
                            Text("生成结果")
                                .font(DS.Font.headline)
                                .accessibilityAddTraits(.isHeader)
                            LazyVStack(spacing: DS.Space.m) {
                                ForEach(clips) { clip in
                                    clipCard(clip)
                                }
                            }
                        }
                    }

                }
                .padding(DS.Space.m)
                .frame(maxWidth: DS.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(canvasBg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if studioMode == .singleClip {
                    generateBar
                }
            }
            .onChange(of: isGenerating) { active in
                if active {
                    withAnimation { proxy.scrollTo("video.progress", anchor: .top) }
                }
            }
        }
        .navigationTitle("视频")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        showingHistory = true
                    } label: {
                        Label("历史", systemImage: "clock.arrow.circlepath")
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityIdentifier("ai.video.history")

                    if !useManagedGateway {
                        Button {
                            if studioMode == .shortDrama {
                                showingDramaAPIConfig = true
                            } else {
                                configuringProvider = model.provider
                            }
                        } label: {
                            let configured = (studioMode == .shortDrama) ? hasAnyDramaKey : hasKey
                            Image(systemName: configured ? "key.fill" : "key.slash.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(configured ? .green : .orange)
                        }
                        .accessibilityLabel(studioMode == .shortDrama ? "短剧接口配置" : "配置服务商 Key")
                        .accessibilityIdentifier("ai.video.keyConfig")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingGenerationStage, onDismiss: {
            if stageOwner == WuMindWorksStore.shared.currentOwnerID, !isGenerating,
               let clip = clips.first, clip.id != stagePreviousClipID {
                play(clip)
            }
        }) {
            let clip = clips.first.flatMap { $0.id == stagePreviousClipID ? nil : $0 }
            WuMindVideoGenerationStage(
                prompt: stagePrompt,
                isRunning: isGenerating,
                progress: progress?.percent,
                jobID: activeJobID,
                asset: clip?.fileURL,
                notice: errorMessage,
                onStop: { sessionStore.cancelGeneration() }
            )
            .onChange(of: WuMindWorksStore.shared.currentOwnerID) { owner in
                if owner != stageOwner { showingGenerationStage = false }
            }
        }
        .sheet(isPresented: $showingHistory) {
            WuMindWorksView(initialFilter: .video, onRetryWork: { failed in
                studioMode = .singleClip
                prompt = failed.prompt
            })
        }
        .sheet(isPresented: $showingDramaAPIConfig) {
            WuMindShortDramaAPISheet()
        }
        .sheet(item: $configuringProvider) { provider in
            ProviderKeyView(provider: provider) { _ in }
        }
        .task(id: useManagedGateway) {
            if useManagedGateway && wmStore.hasGatewayURL { try? await wmStore.syncManagedGatewayConfig() }
            clampParametersForActiveModel()
        }
        .onAppear {
            clampParametersForActiveModel()
            resumePendingManagedJob()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { resumePendingManagedJob() }
        }
        .onDisappear {
            // Pause local video playback preview when leaving view, but NEVER cancel an active
            // video submission or polling task — returning to Launcher Home preserves all running tasks.
            sessionStore.activePlayer?.pause()
        }
    }

    private func clampParametersForActiveModel() {
        if !validDurations.contains(durationSeconds), let first = validDurations.first {
            durationSeconds = first
        }
        if !validAspects.contains(aspect), let first = validAspects.first {
            aspect = first
        }
    }

    private func syncOwnAPIVideoModels() {
        guard !isSyncingModels else { return }
        isSyncingModels = true
        syncStatusNote = "正在同步账号可用视频模型…"
        Task {
            var found: [AIVideoTool.Model] = []
            let tool = AIVideoTool()
            if let openAIKey = Keychain.providerChatAPIKey(.openAI), !openAIKey.isEmpty {
                if let list = try? await tool.discoverVideoModels(
                    provider: .openAI,
                    apiKey: openAIKey,
                    baseURL: AIProviderEndpoints.baseURL(for: .openAI)
                ) {
                    found.append(contentsOf: list)
                }
            }
            if let geminiKey = Keychain.providerChatAPIKey(.gemini), !geminiKey.isEmpty {
                if let list = try? await tool.discoverVideoModels(
                    provider: .gemini,
                    apiKey: geminiKey,
                    baseURL: AIProviderEndpoints.baseURL(for: .gemini)
                ) {
                    found.append(contentsOf: list)
                }
            }
            discoveredModels = found
            if found.isEmpty {
                syncStatusNote = "未拉取到额外视频模型，请检查中转/官方 Key 与网络"
            } else {
                syncStatusNote = "已同步 \(found.count) 个当前账号可用视频模型"
                Haptics.success()
            }
            isSyncingModels = false
        }
    }

    private var studioModeSwitcher: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DS.Space.xxs))
            : AnyLayout(HStackLayout(spacing: DS.Space.xxs))
        return layout {
            ForEach(StudioMode.allCases) { mode in
                let selected = studioMode == mode
                Button {
                    promptFocused = false
                    studioMode = mode
                    Haptics.select()
                } label: {
                    Label(mode.title, systemImage: mode.icon)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, DS.Space.xs)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.primary)
                        .background(selected ? cardBg : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.s))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("ai.video.mode.\(mode.rawValue)")
            }
        }
        .padding(DS.Space.xxs)
        .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m))
    }

    private var controlBar: some View {
        AppSectionCard(title: "生成参数") {
            VStack(alignment: .leading, spacing: 0) {
                Menu {
                    if useManagedGateway {
                        ForEach(wmStore.enabledManagedVideoModels) { m in
                            Button {
                                managedSelectedVideoID = m.id
                                clampParametersForActiveModel()
                            } label: {
                                Label("\(m.displayName)（\(m.pricingSummary)）",
                                      systemImage: m.id == activeModelID ? "checkmark" : "film")
                            }
                        }
                    } else {
                        ForEach(ownAPIModels) { item in
                            Button {
                                model = item
                                UserDefaults.standard.set(item.id, forKey: Self.lastModelKey)
                                clampParametersForActiveModel()
                            } label: {
                                let configured = Keychain.providerChatAPIKey(item.provider) != nil
                                Label(
                                    "\(item.displayName)\(configured ? "" : "（待配 Key）")",
                                    systemImage: item.id == model.id ? "checkmark" : "film"
                                )
                            }
                        }
                        Divider()
                        Button {
                            syncOwnAPIVideoModels()
                        } label: {
                            Label(
                                isSyncingModels ? "正在同步账号可用视频模型…" : "同步当前账号可用视频模型",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                    }
                } label: {
                    parameterRow("模型", value: activeModelDisplayName)
                }
                .tint(.primary)
                .accessibilityIdentifier("ai.video.model")

                Menu {
                    ForEach(validAspects) { ratio in
                        Button(ratio.displayLabel) { aspect = ratio }
                    }
                } label: {
                    parameterRow("画幅", value: aspect.displayLabel)
                }
                .tint(.primary)
                .accessibilityIdentifier("ai.video.aspect")
                Menu {
                    ForEach(validDurations, id: \.self) { sec in
                        Button("\(sec) 秒") { durationSeconds = sec }
                    }
                } label: {
                    parameterRow("时长", value: "\(durationSeconds) 秒")
                }
                .tint(.primary)
                .accessibilityIdentifier("ai.video.duration")

                Menu {
                    ForEach(AIVideoTool.Resolution.allCases) { res in
                        Button(res.displayLabel) { resolution = res }
                    }
                } label: {
                    parameterRow("分辨率", value: resolution.displayLabel)
                }
                .tint(.primary)

                Divider()
                let channel = useManagedGateway
                    ? (wmStore.isBillingExempt ? "内置通道 · 免扣费" : "内置通道")
                    : (AIProviderEndpoints.displayHost(for: model.provider) ?? "官方直连")
                Label(channel, systemImage: useManagedGateway ? "bolt.shield" : "network")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, DS.Space.s)
            }

            if let syncStatusNote, !useManagedGateway {
                HStack(spacing: 6) {
                    if isSyncingModels {
                        ProgressView().controlSize(.mini)
                    }
                    Text(syncStatusNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func parameterRow(_ title: String, value: String) -> some View {
        LabeledContent {
            HStack(spacing: DS.Space.xs) {
                Text(value)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .accessibilityHidden(true)
            }
        } label: {
            Text(title)
        }
        .font(.subheadline)
        .padding(.vertical, DS.Space.xxs)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var missingKeyCard: some View {
        AppSectionCard {
            Label(useManagedGateway ? "内置视频通道暂不可用" : "尚未配置 \(model.provider.displayName) API Key",
                  systemImage: useManagedGateway ? "exclamationmark.circle" : "key")
                .font(DS.Font.headline)
            if useManagedGateway {
                Text("请联系管理员检查内置网关及可用视频模型。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("切换至自有通道") {
                    Haptics.tap()
                    wmStore.setChannel(.ownAPI)
                    clampParametersForActiveModel()
                }
                .frame(minHeight: 44)
            } else {
                Button("配置服务商 Key") { configuringProvider = model.provider }
                    .frame(minHeight: 44)
            }
        }
    }

    private var emptyStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("镜头示例")
                .font(DS.Font.headline)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 290 : 146), spacing: DS.Space.xs)], spacing: DS.Space.xs) {
                ForEach(Self.inspirations) { card in
                    Button {
                        Haptics.tap()
                        prompt = card.prompt
                        promptFocused = true
                    } label: {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Label(card.title, systemImage: card.icon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(card.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(DS.Space.s)
                        .background(cardBg, in: RoundedRectangle(cornerRadius: DS.Radius.m))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.m).strokeBorder(DS.Palette.hairline))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var generatingHUD: some View {
        Button {
            if stageOwner == WuMindWorksStore.shared.currentOwnerID {
                showingGenerationStage = true
            } else {
                presentGenerationStage(prompt: unconfirmedJob?.prompt ?? prompt)
            }
        } label: {
            HStack(spacing: 12) {
                ProgressView().tint(.primary)
                Text("视频生成中").font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(cardBg, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ai.video.openGeneration")
    }

    private func presentGenerationStage(prompt: String) {
        stagePrompt = prompt
        stagePreviousClipID = clips.first?.id
        stageOwner = WuMindWorksStore.shared.currentOwnerID
        activePlayer?.pause()
        showingGenerationStage = true
    }

    private func clipCard(_ clip: GeneratedClip) -> some View {
        let ratio: CGFloat = {
            switch clip.aspect {
            case .portrait9x16: return 9.0 / 16.0
            case .landscape16x9: return 16.0 / 9.0
            case .square1x1: return 1
            }
        }()
        return AppSectionCard {
            if activeClipID == clip.id, let player = activePlayer {
                VideoPlayer(player: player)
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxHeight: 380)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Button {
                    play(clip)
                } label: {
                    VideoClipPoster(url: clip.fileURL)
                        .aspectRatio(ratio, contentMode: .fit)
                        .frame(maxHeight: 380)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
                        .accessibilityLabel("播放成片")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }

            Text(clip.prompt)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Text("\(clip.modelName) · \(clip.aspect.displayLabel) · \(clip.duration)s · \(String(format: "%.1fs", clip.elapsedSeconds))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                ShareLink(item: clip.fileURL) {
                    Label("导出视频", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: unconfirmedJob != nil ? "wifi.exclamationmark" : "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    if let pending = unconfirmedJob {
                        Text("暂时无法确认 · 任务号 \(pending.jobID)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !isGenerating {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    if unconfirmedJob == nil && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("重新发起（新任务）") {
                            startGeneration()
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                    if unconfirmedJob == nil && !useManagedGateway && openAIUsesRelay && model.id.lowercased().hasPrefix("sora-") {
                        if let wan = AIVideoTool.models.first(where: { $0.id == "wan2.6-t2v" }) {
                            Button("改用通义万相 Wan 2.6") {
                                model = wan
                                UserDefaults.standard.set(wan.id, forKey: Self.lastModelKey)
                                clampParametersForActiveModel()
                                errorMessage = nil
                            }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                        if let veo = AIVideoTool.models.first(where: { $0.id == "veo-3.1-fast-generate-preview" }) {
                            Button("改用 Veo 3.1 Fast") {
                                model = veo
                                UserDefaults.standard.set(veo.id, forKey: Self.lastModelKey)
                                clampParametersForActiveModel()
                                errorMessage = nil
                            }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var generateBar: some View {
        HStack(spacing: DS.Space.s) {
            if promptFocused {
                Button { promptFocused = false } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("收起键盘")
                .accessibilityIdentifier("ai.video.dismissKeyboard")
            }
            let pending = unconfirmedJob
            AppPrimaryCTA(title: isGenerating ? "正在生成" : (pending == nil ? "生成视频" : "恢复查询进度（原任务）"),
                          icon: pending == nil ? "play.fill" : "arrow.clockwise",
                          isLoading: isGenerating, isDisabled: pending == nil && !canSubmit) {
                if let pending {
                    resumeUnconfirmedJob(pending)
                } else {
                    startGeneration()
                }
            }
            .accessibilityIdentifier("ai.video.generate")
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.xs)
        .frame(maxWidth: DS.readableWidth)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func startGeneration() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isGenerating, !trimmed.isEmpty else { return }
        promptFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        clampParametersForActiveModel()
        let selectedAspect = aspect
        let selectedDuration = durationSeconds
        let selectedResolution = resolution
        let idemKey = "vid-\(UUID().uuidString.prefix(12))"

        if useManagedGateway {
            guard wmStore.hasGatewayURL, let managedModel = activeManagedVideoModel else {
                errorMessage = "内置视频通道暂不可用，请联系管理员检查网关及视频模型。"
                return
            }
            let preferredSize: String = {
                let candidate: String
                if selectedResolution == .fhd1080 {
                    candidate = (selectedAspect == .portrait9x16) ? "1080x1920" : "1920x1080"
                } else {
                    candidate = (selectedAspect == .portrait9x16) ? "720x1280" : "1280x720"
                }
                if let allowed = managedModel.supportedParams?.sizes, !allowed.isEmpty {
                    if allowed.contains(candidate) { return candidate }
                    let hdFallback = (selectedAspect == .portrait9x16) ? "720x1280" : "1280x720"
                    if allowed.contains(hdFallback) { return hdFallback }
                    return allowed[0]
                }
                return candidate
            }()
            let gateway = wmStore.gatewayBaseURL
            let sizeStr = preferredSize
            let work = WuMindWorksStore.shared.recordSubmittedTask(
                workType: .video,
                title: String(trimmed.prefix(40)),
                prompt: trimmed,
                modelID: managedModel.id,
                params: ["seconds": "\(selectedDuration)", "size": sizeStr, "channel": "managed"],
                status: "queued",
                progress: 5,
                idempotencyKey: idemKey
            )

            errorMessage = nil
            unconfirmedJob = nil
            isGenerating = true
            activeJobID = nil
            progress = .init(stage: "正在通过 WUMIND 网关提交视频任务…", percent: 5, elapsedSeconds: 0)
            let started = Date()
            presentGenerationStage(prompt: trimmed)

            generateTask?.cancel()
            generateTask = Task {
                // Phase 1: Submission ONLY (if this fails, no remote job was created -> safe to mark failed)
                let token: String
                let accountID: String
                let submitted: WuMindManagedVideoJob
                do {
                    token = try await wmStore.ensureManagedAccount()
                    guard wmStore.gatewayBaseURL == gateway else { throw WuMindGatewayClient.GatewayError.invalidGatewayURL }
                    accountID = wmStore.managedAccountID
                    submitted = try await WuMindGatewayClient().submitManagedVideo(
                        gatewayURL: gateway,
                        userToken: token,
                        modelID: managedModel.id,
                        prompt: trimmed,
                        seconds: selectedDuration,
                        size: sizeStr,
                        idempotencyKey: idemKey
                    )
                } catch is CancellationError {
                    isGenerating = false
                    progress = nil
                    return
                } catch {
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    errorMessage = "内置视频提交失败（\(managedModel.id)）：\(msg)"
                    WuMindWorksStore.shared.failWork(id: work.id, errorMessage: msg)
                    Haptics.warning()
                    isGenerating = false
                    progress = nil
                    return
                }

                // Server accepted the job! From this point onward, transient poll/download errors
                // MUST NEVER mark the work as failed — show "暂时无法确认" and resume with original jobID.
                activeJobID = submitted.id
                WuMindWorksStore.shared.updateProgress(
                    id: work.id,
                    status: submitted.status,
                    progress: max(10, submitted.progress ?? 10),
                    upstreamJobID: submitted.id,
                    videoJobOrigin: .init(gateway: gateway, accountID: accountID, jobID: submitted.id)
                )
                let jobCtx = UnconfirmedManagedVideoJob(
                    workID: work.id,
                    jobID: submitted.id,
                    remoteWorkID: submitted.workID,
                    gatewayURL: gateway,
                    accountID: accountID,
                    prompt: trimmed,
                    modelName: managedModel.displayName,
                    aspect: selectedAspect,
                    duration: selectedDuration,
                    started: started
                )
                await pollAndDownloadManagedVideo(jobCtx, initialJob: submitted, token: token)
            }
            return
        }

        // Own API / AIHubMix Direct Path
        guard let apiKey = Keychain.providerChatAPIKey(model.provider), !apiKey.isEmpty else {
            configuringProvider = model.provider
            return
        }

        let selectedModel = model
        let baseURL = AIProviderEndpoints.baseURL(for: selectedModel.provider)
        let work = WuMindWorksStore.shared.recordSubmittedTask(
            workType: .video,
            title: String(trimmed.prefix(40)),
            prompt: trimmed,
            modelID: selectedModel.id,
            params: ["seconds": "\(selectedDuration)", "aspect": selectedAspect.rawValue, "channel": "own_api"],
            status: "in_progress",
            progress: 10,
            idempotencyKey: idemKey
        )

        errorMessage = nil
        isGenerating = true
        activeJobID = nil
        progress = .init(stage: "正在提交视频生成任务…", percent: 5, elapsedSeconds: 0)
        let started = Date()
        presentGenerationStage(prompt: trimmed)

        generateTask?.cancel()
        generateTask = Task {
            do {
                let options = AIVideoTool.Options(
                    aspectRatio: selectedAspect,
                    durationSeconds: selectedDuration,
                    resolution: selectedResolution,
                    customBaseURL: baseURL
                )
                let mp4Data = try await AIVideoTool().generate(
                    model: selectedModel,
                    apiKey: apiKey,
                    prompt: trimmed,
                    options: options
                ) { update in
                    await MainActor.run {
                        self.progress = update
                        if let jobID = update.jobID { self.activeJobID = jobID }
                        if let pct = update.percent {
                            WuMindWorksStore.shared.updateProgress(id: work.id, status: "in_progress", progress: pct, upstreamJobID: update.jobID)
                        }
                    }
                }
                try Task.checkCancellation()
                let saved = WuMindWorksStore.shared.completeWork(
                    id: work.id,
                    assetData: mp4Data,
                    assetMime: "video/mp4",
                    assetExtension: "mp4"
                )
                let fileURL: URL
                if let saved, let local = WuMindWorksStore.shared.localAssetURL(for: saved) {
                    fileURL = local
                } else {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wumind_video_\(UUID().uuidString.prefix(8)).mp4")
                    try mp4Data.write(to: tmp, options: .atomic)
                    fileURL = tmp
                }
                let clip = GeneratedClip(
                    prompt: trimmed,
                    modelName: selectedModel.displayName,
                    aspect: selectedAspect,
                    duration: selectedDuration,
                    fileURL: fileURL,
                    elapsedSeconds: Date().timeIntervalSince(started)
                )
                clips.insert(clip, at: 0)
                if !showingGenerationStage { play(clip) }
                Haptics.success()
            } catch is CancellationError {
                // Cancelled cleanly
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let phase = activeJobID == nil ? "提交" : (progress?.downloading == true ? "下载" : "查询")
                let detail = "自有 Key 视频" + phase + "失败（" + selectedModel.id + "）：" + msg
                errorMessage = detail
                WuMindWorksStore.shared.failWork(id: work.id, errorMessage: detail)
                Haptics.warning()
            }
            isGenerating = false
            progress = nil
        }
    }

    private func resumePendingManagedJob() {
        if let job = unconfirmedJob, !isGenerating { resumeUnconfirmedJob(job) }
    }

    private func resumeUnconfirmedJob(_ job: UnconfirmedManagedVideoJob) {
        guard !isGenerating else { return }
        guard wmStore.gatewayBaseURL == job.gatewayURL, wmStore.managedAccountID == job.accountID else {
            errorMessage = "请切回提交此视频时使用的网关和账号，再查询原任务。"
            return
        }
        errorMessage = nil
        isGenerating = true
        activeJobID = job.jobID
        progress = .init(
            stage: "正在用原任务号恢复查询进度（不重复提交）…",
            percent: 25,
            elapsedSeconds: Date().timeIntervalSince(job.started)
        )
        presentGenerationStage(prompt: job.prompt)
        generateTask?.cancel()
        generateTask = Task {
            let token: String
            do {
                token = try await wmStore.ensureManagedAccount()
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                errorMessage = "暂时无法确认云端状态（\(msg)），服务器可能仍在生成，请稍后重试恢复查询。"
                isGenerating = false
                progress = nil
                return
            }
            await pollAndDownloadManagedVideo(job, initialJob: nil, token: token)
        }
    }

    /// Phase 2: Read-only status polling & MP4 download for an already-accepted job ID.
    /// NEVER marks the work `"failed"` on network/timeout errors — transitions to `"status_unknown"` ("暂时无法确认")
    /// and preserves `unconfirmedJob` so the user can resume polling with the EXACT SAME job ID!
    private func pollAndDownloadManagedVideo(
        _ job: UnconfirmedManagedVideoJob,
        initialJob: WuMindManagedVideoJob?,
        token: String
    ) async {
        defer {
            isGenerating = false
            progress = nil
        }

        var downloading = false
        var upstreamConfirmedFailed = false
        do {
            var current: WuMindManagedVideoJob
            if let initialJob {
                current = initialJob
            } else {
                current = try await WuMindGatewayClient().fetchManagedVideoStatus(
                    gatewayURL: job.gatewayURL,
                    userToken: token,
                    jobID: job.jobID
                )
            }
            while !current.isCompleted && !current.isFailed {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 4_000_000_000)
                current = try await WuMindGatewayClient().fetchManagedVideoStatus(
                    gatewayURL: job.gatewayURL,
                    userToken: token,
                    jobID: job.jobID
                )
                let pct = current.progress ?? 35
                progress = .init(
                    stage: current.status == "queued" ? "云端排队渲染中…" : "视频渲染中（\(pct)%）…",
                    percent: pct,
                    elapsedSeconds: Date().timeIntervalSince(job.started)
                )
                WuMindWorksStore.shared.updateProgress(
                    id: job.workID,
                    status: current.status,
                    progress: pct,
                    upstreamJobID: job.jobID
                )
            }

            if current.isFailed {
                upstreamConfirmedFailed = true
                let msg = current.error ?? "上游确认视频生成失败，预留额度已全额退还。"
                WuMindWorksStore.shared.failWork(id: job.workID, errorMessage: msg)
                unconfirmedJob = nil
                errorMessage = msg
                Haptics.warning()
                return
            }

            downloading = true
            progress = .init(stage: "正在下载 MP4 成片…", percent: 95, elapsedSeconds: Date().timeIntervalSince(job.started))
            let mp4Data = try await WuMindGatewayClient().downloadManagedVideoContent(
                gatewayURL: job.gatewayURL,
                userToken: token,
                jobID: job.jobID
            )
            let saved = WuMindWorksStore.shared.completeWork(
                id: job.workID,
                assetData: mp4Data,
                assetMime: "video/mp4",
                assetExtension: "mp4",
                remoteWorkID: job.remoteWorkID
            )
            let fileURL: URL
            if let saved, let local = WuMindWorksStore.shared.localAssetURL(for: saved) {
                fileURL = local
            } else {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wumind_video_\(UUID().uuidString.prefix(8)).mp4")
                try mp4Data.write(to: tmp, options: .atomic)
                fileURL = tmp
            }
            let clip = GeneratedClip(
                prompt: job.prompt,
                modelName: job.modelName,
                aspect: job.aspect,
                duration: job.duration,
                fileURL: fileURL,
                elapsedSeconds: Date().timeIntervalSince(job.started)
            )
            unconfirmedJob = nil
            errorMessage = nil
            clips.insert(clip, at: 0)
            if !showingGenerationStage { play(clip) }
            try? await wmStore.refreshManagedAccount()
            Haptics.success()
        } catch is CancellationError {
            // Task remains safely persisted in My Works for later read-only status refresh
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let classification = WuMindVideoJobFailureClassifier.classify(
                upstreamJobID: job.jobID,
                upstreamConfirmedFailed: upstreamConfirmedFailed
            )
            if classification == .pollStatusUnconfirmed {
                let phase = downloading ? "成片下载" : "原任务状态查询"
                let notice = "\(phase)受阻，暂时无法确认云端进度（\(msg)）。服务器可能仍在生成，请点下方「恢复查询进度（原任务）」，不会重复生成或扣费。"
                unconfirmedJob = job
                errorMessage = notice
                WuMindWorksStore.shared.markStatusUnconfirmed(
                    id: job.workID,
                    upstreamJobID: job.jobID,
                    message: notice
                )
            } else {
                unconfirmedJob = nil
                errorMessage = msg
                WuMindWorksStore.shared.failWork(id: job.workID, errorMessage: msg)
            }
            Haptics.warning()
        }
    }

    private func play(_ clip: GeneratedClip) {
        activePlayer?.pause()
        let player = AVPlayer(url: clip.fileURL)
        activePlayer = player
        activeClipID = clip.id
        player.play()
    }
}

private struct VideoClipPoster: View {
    let url: URL
    @State private var still: CGImage?

    var body: some View {
        Rectangle()
            .fill(Color.black)
            .overlay {
                if let still {
                    Image(decorative: still, scale: 1)
                        .resizable()
                        .scaledToFit()
                }
            }
            .overlay {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.65), in: Circle())
            }
            .task(id: url) {
                still = nil
                guard url.isFileURL else { return }
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 720, height: 720)
                let frame = try? await generator.image(at: .zero)
                if !Task.isCancelled { still = frame?.image }
            }
    }
}

/// Quiet, full-screen progress canvas shared by a chat video and the single-shot studio.
/// A missing progress value stays indeterminate. The video controls never control remote work.
@MainActor
struct WuMindVideoGenerationStage: View {
    let prompt: String
    let isRunning: Bool
    let progress: Int?
    var jobID: String? = nil
    let asset: URL?
    let notice: String?
    let onStop: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var muted = false
    @State private var confirmingStop = false

    private var estimate: Int? {
        guard isRunning, asset == nil, let progress, (1..<100).contains(progress) else { return nil }
        return progress
    }

    private var stageBackground: some View {
        ZStack {
            Color(white: 0.045)
            Canvas { context, size in
                var dots = Path()
                let step: CGFloat = 17
                for y in stride(from: CGFloat(5), to: size.height, by: step) {
                    for x in stride(from: CGFloat(5), to: size.width, by: step) {
                        dots.addEllipse(in: CGRect(x: x, y: y, width: 1.6, height: 1.6))
                    }
                }
                context.fill(dots, with: .color(.white.opacity(0.22)))
            }
            LinearGradient(colors: [.black.opacity(0.1), .clear, .black.opacity(0.4)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }

    var body: some View {
        ZStack {
            stageBackground
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack {
                    Label("WuMind", systemImage: "sparkles")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isRunning ? "收起，继续生成" : "关闭视频")
                    .accessibilityIdentifier("wumind.video.stage.close")
                }

                Group {
                    if let player {
                        WuMindStagePlayerSurface(player: player)
                            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)) { _ in
                                isPlaying = false
                                player.seek(to: .zero)
                            }
                    } else if let notice, !isRunning {
                        Text(notice)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(6)
                            .accessibilityIdentifier("wumind.video.stage.notice")
                    } else if !isRunning {
                        Text("未取得可播放成片").foregroundStyle(.secondary)
                    } else {
                        Color.clear.accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Button {
                            guard let player else { return }
                            if isPlaying { player.pause() } else { player.play() }
                            isPlaying.toggle()
                        } label: {
                            Image(systemName: isPlaying || player == nil ? "pause.fill" : "play.fill")
                                .frame(width: 46, height: 44)
                        }
                        .accessibilityLabel(isPlaying ? "暂停播放" : "播放成片")
                        Button {
                            muted.toggle()
                            player?.isMuted = muted
                        } label: {
                            Image(systemName: muted ? "speaker.slash" : "speaker.wave.2")
                                .frame(width: 46, height: 44)
                        }
                        .accessibilityLabel(muted ? "打开声音" : "静音")
                    }
                    .buttonStyle(.plain)
                    .opacity(player == nil ? 0.35 : 1)
                    .disabled(player == nil)
                    .background(.white.opacity(0.12), in: Capsule())

                    Spacer(minLength: 4)
                    if asset == nil, isRunning {
                        Text(estimate.map { "≈\($0)%" } ?? "生成中")
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(.white.opacity(0.12), in: Capsule())
                            .accessibilityIdentifier("wumind.video.stage.status")
                        if onStop != nil {
                            Button("取消") { confirmingStop = true }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(.white.opacity(0.12), in: Capsule())
                                .accessibilityIdentifier("wumind.video.stage.stop")
                        }
                    } else if let asset {
                        ShareLink(item: asset) {
                            Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                        }
                        .background(.white.opacity(0.12), in: Capsule())
                        .accessibilityLabel("分享视频")
                    }
                }
                if let jobID, !jobID.isEmpty {
                    Text("任务号 " + jobID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("wumind.video.stage.jobID")
                }
                if let estimate {
                    ProgressView(value: Double(estimate), total: 100)
                        .tint(.white)
                        .accessibilityLabel("预计生成进度")
                } else if asset == nil, isRunning {
                    ProgressView().progressViewStyle(.linear).tint(.white)
                        .accessibilityLabel("正在生成，暂无准确进度")
                }

                HStack(spacing: 10) {
                    Text(prompt)
                        .multilineTextAlignment(.leading)
                        .font(.subheadline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("wumind.video.stage.prompt")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(.white.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 760)
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .task(id: asset) {
            player?.pause()
            player = asset.map { AVPlayer(url: $0) }
            player?.isMuted = muted
            player?.play()
            isPlaying = player != nil
        }
        .onDisappear { player?.pause() }
        .alert("停止等待视频？", isPresented: $confirmingStop) {
            Button("停止等待", role: .destructive) { onStop?(); dismiss() }
            Button("继续生成", role: .cancel) {}
        } message: {
            Text("已提交的云端任务可能继续运行，停止等待不会再次提交任务。")
        }
    }
}

@MainActor
struct WuMindChatVideoStage: View {
    let workID: String
    @ObservedObject private var works = WuMindWorksStore.shared
    @ObservedObject private var chat = WuMindStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let work = works.works.first(where: { $0.id == workID && $0.workType == .video }) {
            let running = chat.activeTurnID != nil &&
                chat.activeConversation?.turns.contains { $0.id == chat.activeTurnID && $0.chatBuildWorkID == workID } == true
            WuMindVideoGenerationStage(
                prompt: work.prompt,
                isRunning: running,
                progress: nil,
                jobID: work.upstreamJobID,
                asset: works.localAssetURL(for: work),
                notice: work.errorMessage,
                onStop: running ? { chat.stopGeneration() } : nil
            )
        } else {
            Color.black.ignoresSafeArea().task { dismiss() }
        }
    }
}

private struct WuMindStagePlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
    }

    func makeUIView(context: Context) -> Surface { Surface() }

    func updateUIView(_ view: Surface, context: Context) {
        guard let layer = view.layer as? AVPlayerLayer else { return }
        layer.videoGravity = .resizeAspect
        layer.player = player
    }

    static func dismantleUIView(_ view: Surface, coordinator: ()) {
        (view.layer as? AVPlayerLayer)?.player = nil
    }
}
