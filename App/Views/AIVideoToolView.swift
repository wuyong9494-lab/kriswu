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

    private struct GeneratedClip: Identifiable {
        let id = UUID()
        let prompt: String
        let modelName: String
        let aspect: AIVideoTool.AspectRatio
        let duration: Int
        let fileURL: URL
        let elapsedSeconds: Double
        let createdAt = Date()
    }

    private struct InspirationCard: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let prompt: String
        let icon: String
        let colors: [Color]
    }

    private static let inspirations: [InspirationCard] = [
        .init(
            title: "赛博雨夜穿梭",
            subtitle: "霓虹镜头 · 低空航拍",
            prompt: "电影级低空航拍镜头穿过午夜赛博朋克都市霓虹街道，细雨反光，体积光穿过云雾，4K 电影质感运镜平滑",
            icon: "sparkles.tv.fill",
            colors: [Color(red: 0.14, green: 0.25, blue: 0.65), Color(red: 0.45, green: 0.16, blue: 0.65)]
        ),
        .init(
            title: "轨道空间站日出",
            subtitle: "科幻写实 · 黄金光晕",
            prompt: "近地轨道空间站舷窗视角，太阳从蔚蓝地球边缘缓缓升起，金色阳光洒在太阳能帆板上，极度写实 NASA 胶片质感",
            icon: "globe.asia.australia.fill",
            colors: [Color(red: 0.10, green: 0.34, blue: 0.56), Color(red: 0.85, green: 0.44, blue: 0.18)]
        ),
        .init(
            title: "东方水墨鹤影",
            subtitle: "国风流动 · 慢动作",
            prompt: "中国传统青绿山水云雾缭绕，一只仙鹤振翅掠过松林与瀑布，水墨粒子随气流缓缓散开，诗意慢动作镜头",
            icon: "wind",
            colors: [Color(red: 0.08, green: 0.42, blue: 0.40), Color(red: 0.18, green: 0.54, blue: 0.44)]
        ),
        .init(
            title: "旗舰产品发布会",
            subtitle: "棚拍微距 · 商业广告",
            prompt: "极简黑色镜面舞台上，一块钛金属智能设备在柔和轮廓光中缓慢旋转，金属拉丝与玻璃折射精致细腻，苹果发布会商业广告镜头",
            icon: "cube.transparent.fill",
            colors: [Color(red: 0.22, green: 0.24, blue: 0.32), Color(red: 0.38, green: 0.28, blue: 0.58)]
        ),
    ]

    private enum StudioMode: String, CaseIterable, Identifiable {
        case shortDrama
        case singleClip

        var id: String { rawValue }
        var title: String {
            switch self {
            case .shortDrama: return "短剧工坊 · 单镜重拍"
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

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var wmStore = WuMindStore.shared
    @State private var studioMode: StudioMode = .shortDrama
    @State private var showingDramaAPIConfig = false
    @State private var showingHistory = false
    @State private var showingAdminCatalog = false
    @State private var model: AIVideoTool.Model
    @State private var discoveredModels: [AIVideoTool.Model] = []
    @State private var isSyncingModels = false
    @State private var syncStatusNote: String? = nil
    @State private var managedSelectedVideoID: String = ""
    @State private var aspect: AIVideoTool.AspectRatio = .landscape16x9
    @State private var durationSeconds = 5
    @State private var resolution: AIVideoTool.Resolution = .hd720
    @State private var prompt = ""
    private struct UnconfirmedManagedVideoJob {
        let workID: String
        let jobID: String
        let remoteWorkID: String?
        let prompt: String
        let modelName: String
        let aspect: AIVideoTool.AspectRatio
        let duration: Int
        let started: Date
    }

    @State private var isGenerating = false
    @State private var activeJobID: String? = nil
    @State private var unconfirmedJob: UnconfirmedManagedVideoJob? = nil
    @State private var progress: AIVideoTool.ProgressUpdate?
    @State private var clips: [GeneratedClip] = []
    @State private var activePlayer: AVPlayer?
    @State private var activeClipID: UUID?
    @State private var errorMessage: String?
    @State private var configuringProvider: AIProvider?
    @State private var generateTask: Task<Void, Never>?
    @FocusState private var promptFocused: Bool

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

    private var isDark: Bool { colorScheme == .dark }
    private var canvasBg: Color {
        isDark ? Color(red: 0.03, green: 0.035, blue: 0.055) : Color(red: 0.955, green: 0.96, blue: 0.98)
    }
    private var cardBg: Color {
        isDark ? Color(red: 0.09, green: 0.10, blue: 0.138) : Color.white
    }
    private var cardBorder: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }

    private var useManagedGateway: Bool {
        wmStore.channel == .managed && wmStore.hasGatewayURL
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
        if useManagedGateway, let m = activeManagedVideoModel { return m.id }
        return model.id
    }

    private var activeModelDisplayName: String {
        if useManagedGateway, let m = activeManagedVideoModel { return m.displayName }
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
        useManagedGateway ? activeManagedVideoModel != nil : (Keychain.providerChatAPIKey(model.provider) != nil)
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
                        } else {
                            ForEach(clips) { clip in
                                clipCard(clip)
                            }
                        }
                    }

                    Color.clear.frame(height: 16)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(canvasBg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if studioMode == .singleClip {
                    floatingComposer
                }
            }
            .onChange(of: isGenerating) { active in
                if active {
                    withAnimation { proxy.scrollTo("video.progress", anchor: .top) }
                }
            }
        }
        .navigationTitle("AI 生视频工坊")
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
                    .accessibilityIdentifier("ai.video.keyConfig")
                }
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
        .sheet(isPresented: $showingAdminCatalog) {
            NavigationStack {
                WuMindAdminBillingView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("完成") {
                                showingAdminCatalog = false
                                Task { try? await wmStore.refreshManagedAccount() }
                            }
                        }
                    }
            }
        }
        .sheet(item: $configuringProvider) { provider in
            ProviderKeyView(provider: provider) { _ in }
        }
        .onAppear {
            clampParametersForActiveModel()
        }
        .onDisappear {
            activePlayer?.pause()
            generateTask?.cancel()
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
        HStack(spacing: 6) {
            ForEach(StudioMode.allCases) { mode in
                let selected = studioMode == mode
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        studioMode = mode
                    }
                    Haptics.tap()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.caption.weight(.bold))
                        Text(mode.title)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 10)
                    .foregroundStyle(selected ? .white : .secondary)
                    .background(
                        LinearGradient(
                            colors: selected
                                ? (mode == .shortDrama ? [.pink, .purple] : [.purple, .indigo])
                                : [.clear, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.video.mode.\(mode.rawValue)")
            }
        }
        .padding(4)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    private var controlBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    if useManagedGateway && !wmStore.enabledManagedVideoModels.isEmpty {
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
                    HStack(spacing: 6) {
                        Image(systemName: "film.stack.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.purple)
                        Text(activeModelDisplayName)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                }
                .tint(.primary)
                .accessibilityIdentifier("ai.video.model")

                Menu {
                    ForEach(validAspects) { ratio in
                        Button(ratio.displayLabel) { aspect = ratio }
                    }
                } label: {
                    compactChip(icon: "aspectratio", text: aspect.displayLabel)
                }
                .tint(.primary)
                .accessibilityIdentifier("ai.video.aspect")
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(validDurations, id: \.self) { sec in
                        Button("\(sec) 秒") { durationSeconds = sec }
                    }
                } label: {
                    compactChip(icon: "timer", text: "\(durationSeconds) 秒")
                        .frame(maxWidth: .infinity)
                }
                .tint(.primary)
                .accessibilityIdentifier("ai.video.duration")

                Menu {
                    ForEach(AIVideoTool.Resolution.allCases) { res in
                        Button(res.displayLabel) { resolution = res }
                    }
                } label: {
                    compactChip(icon: "sparkles.tv", text: resolution.displayLabel)
                        .frame(maxWidth: .infinity)
                }
                .tint(.primary)

                if useManagedGateway {
                    compactChip(icon: "bolt.shield.fill", text: wmStore.isBillingExempt ? "内置·免扣" : "内置网关")
                        .frame(maxWidth: .infinity)
                } else if let relayHost = AIProviderEndpoints.displayHost(for: model.provider) {
                    compactChip(icon: "server.rack", text: relayHost)
                        .frame(maxWidth: .infinity)
                } else {
                    compactChip(icon: "checkmark.seal", text: "官方直连")
                        .frame(maxWidth: .infinity)
                }
            }

            if let syncStatusNote, !useManagedGateway {
                HStack(spacing: 6) {
                    if isSyncingModels {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
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

    private func compactChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    private var missingKeyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: useManagedGateway ? "slider.horizontal.3" : "key.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(useManagedGateway ? "管理员尚未在动态模型目录启用视频模型" : "尚未配置 \(model.provider.displayName) API Key")
                        .font(.caption.weight(.bold))
                    Text(useManagedGateway
                         ? "请在「动态模型目录」同步并实测视频模型（推荐 wan2.6-t2v / veo-3.1-fast-generate-preview / kling-v3-omni）后启用，或一键切回「自带 API」通道。"
                         : "填入官方 Key 或 AIHubMix 等中转站地址即可开始生成")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if !useManagedGateway {
                    Button("去配置") {
                        configuringProvider = model.provider
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .foregroundStyle(.orange)
                }
            }

            if useManagedGateway {
                HStack(spacing: 8) {
                    Button {
                        Haptics.tap()
                        showingAdminCatalog = true
                    } label: {
                        Label("去启用视频目录", systemImage: "checklist")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Color.purple.opacity(0.16), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.tap()
                        wmStore.setChannel(.ownAPI)
                        clampParametersForActiveModel()
                    } label: {
                        Label("切换「自带 API」", systemImage: "arrow.left.arrow.right")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Color.orange.opacity(0.16), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.orange.opacity(0.32), lineWidth: 1))
    }

    private var emptyStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.45, green: 0.25, blue: 0.95), Color(red: 0.14, green: 0.62, blue: 0.96)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 58, height: 58)
                        .shadow(color: .purple.opacity(0.35), radius: 14, y: 6)
                    Image(systemName: "video.badge.waveform.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                Text("WUMIND 电影级视频工坊")
                    .font(.title3.weight(.bold))
                Text("支持通义万相 Wan 2.6、Google Veo 3.1 / Omni 1.2 Flash、可灵 Kling、豆包 Seedance、Sora 2 与 Grok；提交后自动归档「我的作品」，退出页面可随时回来查看与导出 MP4")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            Text("导演灵感模板")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Self.inspirations) { card in
                    Button {
                        Haptics.tap()
                        prompt = card.prompt
                        promptFocused = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: card.icon)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.95))
                            Spacer(minLength: 4)
                            Text(card.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                            Text(card.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
                        .padding(12)
                        .background(
                            LinearGradient(colors: card.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var generatingHUD: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress?.stage ?? "正在生成视频…")
                        .font(.subheadline.weight(.bold))
                    let jobTag = activeJobID.map { " · 任务 \($0.prefix(12))" } ?? ""
                    Text("\(activeModelDisplayName) · \(aspect.displayLabel) · \(durationSeconds)s\(jobTag) · 已耗时 \(Int(progress?.elapsedSeconds ?? 0))s")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") {
                    generateTask?.cancel()
                    isGenerating = false
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.14), in: Capsule())
            }

            if let pct = progress?.percent {
                ProgressView(value: Double(max(0, min(100, pct))), total: 100)
                    .tint(.purple)
            }
            Text("任务已自动归档至「我的作品 / 历史」，离开页面不会丢单或重复扣费。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.purple.opacity(0.32), lineWidth: 1))
    }

    private func clipCard(_ clip: GeneratedClip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if activeClipID == clip.id, let player = activePlayer {
                VideoPlayer(player: player)
                    .frame(height: clip.aspect == .portrait9x16 ? 380 : 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Button {
                    play(clip)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.20), Color(red: 0.22, green: 0.14, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 190)
                        VStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white)
                            Text("点击播放 MP4 成片")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Text(clip.prompt)
                .font(.caption)
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
                        .background(Color.purple.opacity(0.16), in: Capsule())
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
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
                HStack(spacing: 8) {
                    if let pending = unconfirmedJob {
                        Button("恢复查询进度（原任务）") {
                            resumeUnconfirmedJob(pending)
                        }
                        .font(.caption2.weight(.bold))
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .controlSize(.mini)
                    } else if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("重新发起（新任务）") {
                            startGeneration()
                        }
                        .font(.caption2.weight(.bold))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    if unconfirmedJob == nil && !useManagedGateway && openAIUsesRelay && model.id.lowercased().hasPrefix("sora-") {
                        if let wan = AIVideoTool.models.first(where: { $0.id == "wan2.6-t2v" }) {
                            Button("改用通义万相 Wan 2.6") {
                                model = wan
                                UserDefaults.standard.set(wan.id, forKey: Self.lastModelKey)
                                clampParametersForActiveModel()
                                errorMessage = nil
                            }
                            .font(.caption2.weight(.bold))
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.mini)
                        }
                        if let veo = AIVideoTool.models.first(where: { $0.id == "veo-3.1-fast-generate-preview" }) {
                            Button("改用 Veo 3.1 Fast") {
                                model = veo
                                UserDefaults.standard.set(veo.id, forKey: Self.lastModelKey)
                                clampParametersForActiveModel()
                                errorMessage = nil
                            }
                            .font(.caption2.weight(.bold))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var floatingComposer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("描述你想生成的视频画面、镜头运动与光线…", text: $prompt, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.subheadline)
                    .focused($promptFocused)
                    .submitLabel(.done)
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
                    .accessibilityIdentifier("ai.video.prompt")

                Button {
                    startGeneration()
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                canSubmit
                                    ? LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.secondary.opacity(0.28), Color.secondary.opacity(0.28)], startPoint: .top, endPoint: .bottom)
                            )
                            .frame(width: 38, height: 38)
                        if isGenerating {
                            ProgressView().tint(.white).controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .accessibilityIdentifier("ai.video.generate")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(isDark ? 0.35 : 0.10), radius: 14, y: 4)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .background(
            LinearGradient(
                colors: [canvasBg.opacity(0), canvasBg.opacity(0.92), canvasBg],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func startGeneration() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        promptFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        clampParametersForActiveModel()
        let selectedAspect = aspect
        let selectedDuration = durationSeconds
        let selectedResolution = resolution
        let idemKey = "vid-\(UUID().uuidString.prefix(12))"

        if useManagedGateway {
            guard let managedModel = activeManagedVideoModel else {
                errorMessage = "当前内置目录尚未开通可用视频模型，请在管理员后台「动态模型目录」实测并启用后再试。"
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

            generateTask?.cancel()
            generateTask = Task {
                // Phase 1: Submission ONLY (if this fails, no remote job was created -> safe to mark failed)
                let token: String
                let submitted: WuMindManagedVideoJob
                do {
                    token = try await wmStore.ensureManagedAccount()
                    submitted = try await WuMindGatewayClient().submitManagedVideo(
                        gatewayURL: wmStore.gatewayBaseURL,
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
                    errorMessage = msg
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
                    upstreamJobID: submitted.id
                )
                let jobCtx = UnconfirmedManagedVideoJob(
                    workID: work.id,
                    jobID: submitted.id,
                    remoteWorkID: submitted.workID,
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
                        if let pct = update.percent {
                            WuMindWorksStore.shared.updateProgress(id: work.id, status: "in_progress", progress: pct)
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
                play(clip)
                Haptics.success()
            } catch is CancellationError {
                // Cancelled cleanly
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                errorMessage = msg
                WuMindWorksStore.shared.failWork(id: work.id, errorMessage: msg)
                Haptics.warning()
            }
            isGenerating = false
            progress = nil
        }
    }

    private func resumeUnconfirmedJob(_ job: UnconfirmedManagedVideoJob) {
        guard !isGenerating else { return }
        errorMessage = nil
        isGenerating = true
        activeJobID = job.jobID
        progress = .init(
            stage: "正在用原任务号恢复查询进度（不重复提交）…",
            percent: 25,
            elapsedSeconds: Date().timeIntervalSince(job.started)
        )
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

        var upstreamConfirmedFailed = false
        do {
            var current: WuMindManagedVideoJob
            if let initialJob {
                current = initialJob
            } else {
                current = try await WuMindGatewayClient().fetchManagedVideoStatus(
                    gatewayURL: wmStore.gatewayBaseURL,
                    userToken: token,
                    jobID: job.jobID
                )
            }
            while !current.isCompleted && !current.isFailed {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 4_000_000_000)
                current = try await WuMindGatewayClient().fetchManagedVideoStatus(
                    gatewayURL: wmStore.gatewayBaseURL,
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

            progress = .init(stage: "正在下载 MP4 成片…", percent: 95, elapsedSeconds: Date().timeIntervalSince(job.started))
            let mp4Data = try await WuMindGatewayClient().downloadManagedVideoContent(
                gatewayURL: wmStore.gatewayBaseURL,
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
            play(clip)
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
                let notice = "暂时无法确认云端进度（\(msg)）。服务器可能仍在生成，请点下方「恢复查询进度（原任务）」，不会重复生成或扣费。"
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
