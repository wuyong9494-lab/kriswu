import AVKit
import SwiftUI
import UIKit

/// Flagship WUMIND AI Video Studio (Grok Imagine Video · OpenAI Sora 2 · Google Veo 3).
/// Matches Grok/GPT dark obsidian studio aesthetic with zero keyboard occlusion,
/// live render progress HUD, native AVPlayer playback, and 1-tap ShareLink export.
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
    @State private var studioMode: StudioMode = .shortDrama
    @State private var showingDramaAPIConfig = false
    @State private var model: AIVideoTool.Model
    @State private var aspect: AIVideoTool.AspectRatio = .landscape16x9
    @State private var durationSeconds = 5
    @State private var resolution: AIVideoTool.Resolution = .hd720
    @State private var prompt = ""
    @State private var isGenerating = false
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
        let savedID = UserDefaults.standard.string(forKey: Self.lastModelKey)
        _model = State(initialValue: AIVideoTool.preferredModel(configuredProviders: configured, lastSelectedID: savedID))
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
    private var hasKey: Bool {
        Keychain.providerChatAPIKey(model.provider) != nil
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
        .sheet(isPresented: $showingDramaAPIConfig) {
            WuMindShortDramaAPISheet()
        }
        .sheet(item: $configuringProvider) { provider in
            ProviderKeyView(provider: provider) { _ in }
        }
        .onDisappear {
            activePlayer?.pause()
            generateTask?.cancel()
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
                    ForEach(AIVideoTool.models) { item in
                        Button {
                            model = item
                            UserDefaults.standard.set(item.id, forKey: Self.lastModelKey)
                        } label: {
                            let configured = Keychain.providerChatAPIKey(item.provider) != nil
                            Label(
                                "\(item.displayName)\(configured ? "" : "（待配 Key）")",
                                systemImage: item.id == model.id ? "checkmark" : "film"
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "film.stack.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.purple)
                        Text(model.displayName)
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
                    ForEach(AIVideoTool.AspectRatio.allCases) { ratio in
                        Button(ratio.displayLabel) { aspect = ratio }
                    }
                } label: {
                    compactChip(icon: "aspectratio", text: aspect.displayLabel)
                }
                .tint(.primary)
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach([5, 8, 10], id: \.self) { sec in
                        Button("\(sec) 秒") { durationSeconds = sec }
                    }
                } label: {
                    compactChip(icon: "timer", text: "\(durationSeconds) 秒")
                        .frame(maxWidth: .infinity)
                }
                .tint(.primary)

                Menu {
                    ForEach(AIVideoTool.Resolution.allCases) { res in
                        Button(res.displayLabel) { resolution = res }
                    }
                } label: {
                    compactChip(icon: "sparkles.tv", text: resolution.displayLabel)
                        .frame(maxWidth: .infinity)
                }
                .tint(.primary)

                if let relayHost = AIProviderEndpoints.displayHost(for: model.provider) {
                    compactChip(icon: "server.rack", text: relayHost)
                        .frame(maxWidth: .infinity)
                } else {
                    compactChip(icon: "checkmark.seal", text: "官方直连")
                        .frame(maxWidth: .infinity)
                }
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
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("尚未配置 \(model.provider.displayName) API Key")
                    .font(.caption.weight(.bold))
                Text("填入官方 Key 或支持视频接口的中转站地址即可开始生成")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("去配置") {
                configuringProvider = model.provider
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.16), in: Capsule())
            .foregroundStyle(.orange)
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
                Text("直连 Grok Imagine Video、OpenAI Sora 2 与 Google Veo 3，支持自动异步轮询与 MP4 成片导出")
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
                    Text("\(model.displayName) · \(aspect.displayLabel) · \(durationSeconds)s · 已耗时 \(Int(progress?.elapsedSeconds ?? 0))s")
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
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

        guard let apiKey = Keychain.providerChatAPIKey(model.provider), !apiKey.isEmpty else {
            configuringProvider = model.provider
            return
        }

        let selectedModel = model
        let selectedAspect = aspect
        let selectedDuration = durationSeconds
        let selectedResolution = resolution
        let baseURL = AIProviderEndpoints.baseURL(for: selectedModel.provider)

        errorMessage = nil
        isGenerating = true
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
                    }
                }
                try Task.checkCancellation()
                let fileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("wumind_video_\(UUID().uuidString.prefix(8)).mp4")
                try mp4Data.write(to: fileURL, options: .atomic)
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
                // User cancelled cleanly
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Haptics.warning()
            }
            isGenerating = false
            progress = nil
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
