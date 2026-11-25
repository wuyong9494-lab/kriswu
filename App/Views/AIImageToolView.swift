import ImageIO
import SwiftUI
import UIKit

/// Flagship WUMIND Imagine Studio — Grok / ChatGPT-grade visual canvas with fast JPEG streaming,
/// concurrent multi-image generation, floating frosted-glass bottom composer (zero keyboard occlusion),
/// one-tap HD upscale, and full-screen pinch-zoom lightbox.
@MainActor
struct AIImageToolView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var model: AIImageTool.Model = AIImageTool.models[0]
    @State private var quality: AIImageTool.Quality = .fast
    @State private var aspectRatio: AIImageTool.AspectRatio = .portrait
    @State private var batchCount: Int = 1
    @State private var selectedStyle: StudioStylePreset = .none
    @State private var prompt = ""

    @State private var hasKey = false
    @State private var customHost: String? = nil
    @State private var settingKey = false

    @State private var sessions: [StudioSession] = []
    @State private var activeRunID: UUID? = nil
    @State private var activeTask: Task<Void, Never>? = nil
    @State private var failureMessage: String? = nil
    @State private var toastMessage: String? = nil
    @State private var lightboxItem: LightboxItem? = nil

    @FocusState private var promptFocused: Bool

    private enum PrefKey {
        static let modelID = "wumind.imageStudio.modelID"
        static let quality = "wumind.imageStudio.quality"
        static let aspect = "wumind.imageStudio.aspect"
        static let batchCount = "wumind.imageStudio.batchCount"
    }

    private struct StudioSlot: Identifiable {
        let id: UUID
        let index: Int
        var image: UIImage?
        var pixelSize: CGSize?
        var elapsedSeconds: Double?
        var failed: Bool = false
    }

    private struct StudioSession: Identifiable {
        let id: UUID
        let rawPrompt: String
        let effectivePrompt: String
        let styleName: String?
        let model: AIImageTool.Model
        let quality: AIImageTool.Quality
        let aspectRatio: AIImageTool.AspectRatio
        let startedAt: Date
        var slots: [StudioSlot]
        var finishedAt: Date?
        var errorMessage: String?

        var isGenerating: Bool {
            finishedAt == nil
        }

        var completedSlots: [StudioSlot] {
            slots.filter { $0.image != nil }
        }

        var fastestSeconds: Double? {
            completedSlots.compactMap(\.elapsedSeconds).min()
        }
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
                    LazyVStack(alignment: .leading, spacing: 18) {
                        Color.clear.frame(height: 2).id("studio.top")

                        if !hasKey {
                            missingKeyBanner
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
                    if !sessions.isEmpty && !isGenerating {
                        Button {
                            Haptics.tap()
                            withAnimation(.easeOut(duration: 0.2)) {
                                sessions.removeAll()
                                failureMessage = nil
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("清空本次画廊")
                        .accessibilityIdentifier("ai.image.clear")
                    }

                    Button {
                        dismissKeyboard()
                        Haptics.tap()
                        settingKey = true
                    } label: {
                        Image(systemName: hasKey ? "key.fill" : "key.radiowaves.forward")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(hasKey ? providerAccent : Color.orange)
                    }
                    .accessibilityLabel("配置 \(model.provider.displayName) API Key")
                    .accessibilityIdentifier("ai.image.keyConfig")
                }
            }
        }
        .sheet(isPresented: $settingKey) {
            ProviderKeyView(provider: model.provider) { configured in
                hasKey = configured
                customHost = AIProviderEndpoints.displayHost(for: model.provider)
                failureMessage = nil
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
        }
        .onChange(of: quality) { _ in persistPreferences() }
        .onChange(of: aspectRatio) { _ in persistPreferences() }
        .onChange(of: batchCount) { _ in persistPreferences() }
        .onDisappear(perform: stopGeneration)
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

    // MARK: - Top Model Picker Pill

    private var modelPickerPill: some View {
        Menu {
            Section("选择出图模型") {
                ForEach(AIImageTool.models) { item in
                    let configured = Keychain.providerChatAPIKey(item.provider) != nil
                    Button {
                        Haptics.select()
                        model = item
                    } label: {
                        HStack {
                            Text("\(item.displayName) · \(item.provider.displayName)")
                            if item == model {
                                Image(systemName: "checkmark")
                            } else if configured {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                    }
                }
            }
            Section {
                Button {
                    dismissKeyboard()
                    settingKey = true
                } label: {
                    Label(
                        hasKey ? "管理 \(model.provider.displayName) Key / 中转地址" : "配置 \(model.provider.displayName) API Key",
                        systemImage: "key.fill"
                    )
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(hasKey ? providerAccent : Color.orange)
                    .frame(width: 7, height: 7)
                Text(model.shortStudioName)
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
        .disabled(isGenerating)
        .accessibilityIdentifier("ai.image.model")
    }

    // MARK: - Key Banner

    private var missingKeyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.radiowaves.forward.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(Color.orange.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("需配置 \(model.provider.displayName) API Key")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("仅将本次提示词发往所选服务商，不读取聊天或相册")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button {
                dismissKeyboard()
                Haptics.tap()
                settingKey = true
            } label: {
                Text("配置")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(providerAccent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.28), lineWidth: 0.9)
        )
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

                if let errorMessage = session.errorMessage, !session.completedSlots.isEmpty {
                    Text("部分图片生成失败：\(errorMessage)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(DS.Palette.danger)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 3) {
                    Text("生成未完成")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("目标域名：\(model.provider.resolvedHost(baseURL: AIProviderEndpoints.baseURL(for: model.provider)))")
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
                        Label("重试", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(providerAccent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    dismissKeyboard()
                    settingKey = true
                } label: {
                    Label("检查 Key / 接口", systemImage: "key")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.09), in: Capsule())
                }
                .buttonStyle(.plain)
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
                .disabled(isGenerating)
                .accessibilityLabel("高级出图参数")
                .accessibilityIdentifier("ai.image.settings")
            }

            // Row 2: Frosted-Glass Prompt Composer Card (mirrors Grok IMG_4203 & ChatGPT composer!)
            VStack(spacing: 8) {
                TextField("输入即见所想…", text: $prompt, axis: .vertical)
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
                    .disabled(isGenerating)
                    .accessibilityLabel("选择画风预设")
                    .accessibilityIdentifier("ai.image.styleMenu")

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
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("图像")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(isDark ? .black : .white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(isDark ? Color.white : Color.primary, in: Capsule())
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

    private var speedToggleCapsule: some View {
        HStack(spacing: 2) {
            speedSegmentButton(title: "极速", target: .fast, active: quality == .fast)
            speedSegmentButton(
                title: quality == .balanced ? "均衡" : "超清",
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
                .padding(.horizontal, 11)
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

    // MARK: - Actions & Concurrency

    private func dismissKeyboard() {
        promptFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func hydratePreferences() {
        let configuredProviders = Set(AIProvider.allCases.filter { Keychain.providerChatAPIKey($0) != nil })
        let savedModelID = UserDefaults.standard.string(forKey: PrefKey.modelID)
        model = AIImageTool.preferredModel(configuredProviders: configuredProviders, lastSelectedID: savedModelID)

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
        // Dismiss keyboard IMMEDIATELY so results are NEVER covered!
        dismissKeyboard()

        guard Keychain.providerChatAPIKey(model.provider) != nil else {
            Haptics.warning()
            settingKey = true
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
        guard Keychain.providerChatAPIKey(model.provider) != nil else {
            settingKey = true
            return
        }
        startGeneration(rawPrompt: rawPrompt, overrideQuality: .hd, overrideCount: 1)
    }

    private func startGeneration(rawPrompt: String, overrideQuality: AIImageTool.Quality?, overrideCount: Int? = nil) {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let apiKey = Keychain.providerChatAPIKey(model.provider) else { return }

        let targetModel = model
        let targetQuality = overrideQuality ?? quality
        let targetAspect = aspectRatio
        let targetCount = overrideCount ?? batchCount
        let styleSuffix = selectedStyle.promptSuffix
        let effectivePrompt = styleSuffix.map { trimmed + $0 } ?? trimmed
        let baseURL = AIProviderEndpoints.baseURL(for: targetModel.provider)

        let runID = UUID()
        let sessionID = UUID()
        let startedAt = Date()
        let initialSlots = (0..<targetCount).map { StudioSlot(id: UUID(), index: $0) }
        let newSession = StudioSession(
            id: sessionID,
            rawPrompt: trimmed,
            effectivePrompt: effectivePrompt,
            styleName: selectedStyle == .none ? nil : selectedStyle.title,
            model: targetModel,
            quality: targetQuality,
            aspectRatio: targetAspect,
            startedAt: startedAt,
            slots: initialSlots,
            finishedAt: nil,
            errorMessage: nil
        )

        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
            sessions.insert(newSession, at: 0)
        }
        failureMessage = nil
        activeRunID = runID

        let options = AIImageTool.Options(
            quality: targetQuality,
            aspectRatio: targetAspect,
            outputFormat: .jpeg,
            customBaseURL: baseURL
        )

        activeTask = Task { @MainActor in
            defer {
                if activeRunID == runID {
                    activeRunID = nil
                    activeTask = nil
                }
            }

            do {
                let results = try await AIImageTool().generateBatch(
                    model: targetModel,
                    apiKey: apiKey,
                    prompt: effectivePrompt,
                    count: targetCount,
                    options: options
                ) { @MainActor slotResult in
                    // Decode off main thread for locked 120fps ProMotion smoothness
                    let decoded = await Self.decodeImageOffMain(slotResult.data)
                    guard activeRunID == runID else { return }
                    if let decoded {
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
                finalizeSession(sessionID: sessionID, errorMessage: results.isEmpty ? "服务商未返回可用图片。" : nil)
                if !results.isEmpty {
                    Haptics.success()
                }
            } catch is CancellationError {
                finalizeSession(sessionID: sessionID, errorMessage: "已停止等待。")
            } catch {
                guard activeRunID == runID, !Task.isCancelled else { return }
                let msg = (error as? LocalizedError)?.errorDescription ?? "未能生成图片，请重试。"
                failureMessage = msg
                finalizeSession(sessionID: sessionID, errorMessage: msg)
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
