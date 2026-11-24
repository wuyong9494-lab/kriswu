import SwiftUI
import UIKit

/// Flagship multi-model AI aggregator workspace ("WUMIND").
/// Presented full-screen without the bottom duty tab bar; supports persistent local
/// session history, live collapsible chain-of-thought reasoning, unified 5-provider
/// model switching, rich Markdown + code cards, and 1-tap access to AI Toolbox & Tender Draft.
struct WuMindWorkspaceView: View {
    @ObservedObject private var store = WuMindStore.shared
    @Environment(\.colorScheme) private var colorScheme
    var onClose: (() -> Void)? = nil

    @State private var draft = ""
    @State private var drawerOpen = false
    @State private var drawerSearch = ""
    @State private var showingModelHub = false
    @State private var showingSkills = false
    @State private var showingGitHub = false
    @State private var showingKeyFor: WuMindProvider?
    @State private var confirmingClearAll = false
    @State private var renamingConversation: WuMindConversation?
    @State private var renameDraft = ""

    @State private var activeTask: Task<Void, Never>?
    @State private var activeTurnID: UUID?
    @State private var activeConversationForTask: UUID?
    @State private var thinkingStartedAt: Date?
    @State private var following = true

    @State private var toolboxPath: [ToolboxDestination] = []
    @FocusState private var composerFocused: Bool

    private let bottomAnchor = "wumind.chat.bottom"
    private let questionLimit = 12_000
    private let contextLimit = 64_000

    private enum ToolboxDestination: String, Identifiable, Hashable {
        case hub, live, image, speech, code, work, tender
        var id: String { rawValue }
    }

    private func dismissKeyboard() {
        composerFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func openTool(_ destination: ToolboxDestination) {
        dismissKeyboard()
        toolboxPath.append(destination)
    }

    private var turns: [WuMindTurn] { store.activeConversation?.turns ?? [] }
    private var generating: Bool { activeTurnID != nil }
    private var cleanedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool {
        !generating && !cleanedDraft.isEmpty && cleanedDraft.utf8.count <= questionLimit
    }

    private var canvasBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.06, green: 0.07, blue: 0.09)
            : Color(red: 0.965, green: 0.97, blue: 0.985)
    }

    private var elevatedSurface: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.125, blue: 0.155)
            : Color.white
    }

    private var subtleBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    }

    var body: some View {
        NavigationStack(path: $toolboxPath) {
            ZStack(alignment: .leading) {
                VStack(spacing: 0) {
                    topBar
                    transcriptView
                    composerBar
                }
                .background(canvasBackground.ignoresSafeArea())

                if drawerOpen {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture {
                            dismissKeyboard()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                drawerOpen = false
                            }
                        }
                        .transition(.opacity)

                    historyDrawer
                        .transition(.move(edge: .leading))
                        .zIndex(2)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        dismissKeyboard()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "keyboard.chevron.compact.down")
                            Text("收起键盘")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("wumind.keyboard.dismiss")
                }
            }
            .navigationDestination(for: ToolboxDestination.self) { dest in
                Group {
                    switch dest {
                    case .hub: AIProviderListView()
                    case .live: AILiveCallView()
                    case .image: AIImageToolView()
                    case .speech: AISpeechToolView()
                    case .code: AICodeWorkToolsView(kind: .code)
                    case .work: AICodeWorkToolsView(kind: .work)
                    case .tender: DeepSeekTenderView()
                    }
                }
                .toolbar(.visible, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showingModelHub) {
            WuMindModelHubSheet(store: store) { provider in
                showingModelHub = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    showingKeyFor = provider
                }
            }
        }
        .sheet(isPresented: $showingSkills) {
            WuMindSkillsSheet(store: store)
        }
        .sheet(isPresented: $showingGitHub) {
            WuMindGitHubSheet(store: store)
        }
        .sheet(item: $showingKeyFor, onDismiss: {
            store.objectWillChange.send()
        }) { provider in
            if provider == .deepSeek {
                DeepSeekPlanKeyView()
            } else if let mp = provider.multiProvider {
                ProviderKeyView(provider: mp) { configured in
                    if !configured {
                        store.cachedModels[provider] = []
                        if store.selectedProvider == provider {
                            store.selectedModelID = ""
                            store.selectedModelName = provider.displayName
                        }
                    }
                    store.objectWillChange.send()
                }
            }
        }
        .alert("重命名对话", isPresented: Binding(
            get: { renamingConversation != nil },
            set: { if !$0 { renamingConversation = nil } }
        )) {
            TextField("对话标题", text: $renameDraft)
            Button("保存") {
                if let convo = renamingConversation {
                    store.renameConversation(convo.id, title: renameDraft)
                }
                renamingConversation = nil
            }
            Button("取消", role: .cancel) { renamingConversation = nil }
        }
        .confirmationDialog("清空所有 WUMIND 历史对话？", isPresented: $confirmingClearAll, titleVisibility: .visible) {
            Button("清空全部历史", role: .destructive) {
                stopRequest()
                store.deleteAllConversations()
            }
        } message: {
            Text("此操作只删除本机聊天记录，不会影响 API Key 或值班数据。")
        }
        .onDisappear {
            dismissKeyboard()
            stopRequest()
            store.flushSave()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deepseek.chat")
    }

    // MARK: - Top Header Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismissKeyboard()
                Haptics.tap()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    drawerOpen.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(elevatedSurface, in: Circle())
                    .overlay(Circle().strokeBorder(subtleBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("历史对话侧边栏")
            .accessibilityIdentifier("wumind.sidebar.open")

            Spacer(minLength: 4)

            Button {
                dismissKeyboard()
                Haptics.tap()
                showingModelHub = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: store.selectedProvider.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(store.selectedProvider.brandColor)
                    Text(headerModelTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(elevatedSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(generating)
            .accessibilityLabel("切换模型，当前 \(headerModelTitle)")
            .accessibilityIdentifier("wumind.model.picker")

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    stopRequest()
                    store.startNewConversation()
                    draft = ""
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(elevatedSurface, in: Circle())
                        .overlay(Circle().strokeBorder(subtleBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建对话")
                .accessibilityIdentifier("wumind.chat.new")

                if let onClose {
                    Button {
                        Haptics.tap()
                        stopRequest()
                        store.flushSave()
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, height: 38)
                            .background(elevatedSurface, in: Circle())
                            .overlay(Circle().strokeBorder(subtleBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回值班首页")
                    .accessibilityIdentifier("wumind.close")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(canvasBackground)
    }

    private var headerModelTitle: String {
        let name = store.selectedModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? store.selectedProvider.displayName : name
    }

    // MARK: - Transcript / Welcome Canvas

    private var transcriptView: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if turns.isEmpty {
                        welcomeCanvas
                    } else {
                        ForEach(turns) { turn in
                            WuMindTurnView(
                                turn: turn,
                                isLast: turn.id == turns.last?.id,
                                isGenerating: activeTurnID == turn.id,
                                thinkingStartedAt: activeTurnID == turn.id ? thinkingStartedAt : nil,
                                elevatedSurface: elevatedSurface,
                                subtleBorder: subtleBorder,
                                onCopy: copyText,
                                onRetryPrompt: { prompt in
                                    draft = prompt
                                    composerFocused = true
                                },
                                onRegenerate: {
                                    guard !generating else { return }
                                    draft = turn.question
                                    requestSend()
                                },
                                onManageKey: {
                                    showingKeyFor = turn.provider
                                }
                            )
                        }
                    }
                    Color.clear.frame(height: 8).id(bottomAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                if composerFocused {
                    dismissKeyboard()
                }
            })
            .onChange(of: turns.last?.id) { _ in
                if following {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scroller.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                }
            }
            .onChange(of: turns.last?.answer.utf8.count) { _ in
                if following && generating {
                    scroller.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
            .onChange(of: turns.last?.reasoning.utf8.count) { _ in
                if following && generating {
                    scroller.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if generating {
                    Button {
                        following.toggle()
                        if following { scroller.scrollTo(bottomAnchor, anchor: .bottom) }
                    } label: {
                        Label(following ? "暂停滚动" : "回到最新",
                              systemImage: following ? "pause.fill" : "arrow.down")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private var welcomeCanvas: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.27, green: 0.44, blue: 1.0),
                                    Color(red: 0.56, green: 0.35, blue: 0.96),
                                    Color(red: 0.14, green: 0.72, blue: 0.78)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 54, height: 54)
                        .shadow(color: Color(red: 0.32, green: 0.45, blue: 1.0).opacity(0.35), radius: 16, y: 6)
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 4) {
                    Text("WUMIND")
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .tracking(1.4)
                    Text("多模型旗舰工作台 · Skills 技能 · GitHub 仓库直连 · 深度思考")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 10)

            // Home Quick Multi-Provider API & GitHub Configuration Strip
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("模型 API 与 GitHub 快捷配置")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        dismissKeyboard()
                        Haptics.tap()
                        showingModelHub = true
                    } label: {
                        Text("管理全部")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(store.selectedProvider.brandColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(WuMindProvider.allCases) { provider in
                            homeProviderAPICard(provider)
                        }
                        homeGitHubAPICard
                    }
                    .padding(.vertical, 2)
                }
            }
            .accessibilityIdentifier("wumind.home.apiStrip")

            // Quick AI Toolbox Strip
            VStack(alignment: .leading, spacing: 9) {
                Text("AI 能力中心")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        quickToolPill("实时语音", icon: "phone.waveform", color: .green, id: "wumind.quick.live") {
                            openTool(.live)
                        }
                        quickToolPill("文字生图", icon: "photo.on.rectangle.angled", color: .purple, id: "wumind.quick.image") {
                            openTool(.image)
                        }
                        quickToolPill("投标书草稿", icon: "doc.text.fill", color: .blue, id: "deepSeek.chat.tender") {
                            openTool(.tender)
                        }
                        quickToolPill("代码 / 办公", icon: "curlybraces", color: .orange, id: "wumind.quick.code") {
                            openTool(.code)
                        }
                        quickToolPill("全部工具箱", icon: "square.grid.2x2.fill", color: .indigo, id: "ai.providers.open") {
                            openTool(.hub)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Starter Prompts 2x2 Grid
            VStack(alignment: .leading, spacing: 9) {
                Text("试试这样问")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    starterCard(icon: "lightbulb.fill", color: .orange, title: "深度拆解问题",
                                prompt: "请用通俗清晰的步骤，帮我分析一个复杂问题并给出可执行方案")
                    starterCard(icon: "chevron.left.forwardslash.chevron.right", color: .blue, title: "审查 GitHub 仓库",
                                prompt: "请帮我分析已连接的 GitHub 仓库核心架构，并给出最有价值的 3 条优化建议")
                    starterCard(icon: "doc.richtext", color: .purple, title: "公文与汇报润色",
                                prompt: "帮我起草一份简洁专业的周度运行保障总结报告框架")
                    starterCard(icon: "globe", color: .teal, title: "专业英文翻译",
                                prompt: "请将下面这段技术说明润色为地道自然的中文与英文双语版本：")
                }
            }

            if !store.conversations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("最近对话")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("查看全部") {
                            dismissKeyboard()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                drawerOpen = true
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    ForEach(store.sortedConversations.prefix(3)) { convo in
                        Button {
                            dismissKeyboard()
                            Haptics.tap()
                            store.openConversation(convo.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: convo.provider.iconName)
                                    .font(.caption)
                                    .foregroundStyle(convo.provider.brandColor)
                                    .frame(width: 26, height: 26)
                                    .background(convo.provider.brandColor.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(convo.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(convo.modelDisplayName) · \(convo.turns.count) 轮")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func homeProviderAPICard(_ provider: WuMindProvider) -> some View {
        let configured = provider.hasKey
        let isCurrent = store.selectedProvider == provider
        let customHost = provider.multiProvider.flatMap { AIProviderEndpoints.displayHost(for: $0) }
        return Button {
            dismissKeyboard()
            Haptics.tap()
            showingKeyFor = provider
        } label: {
            HStack(spacing: 8) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(provider.brandColor)
                    .frame(width: 28, height: 28)
                    .background(provider.brandColor.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.shortName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(configured ? Color.green : Color.orange.opacity(0.75))
                            .frame(width: 6, height: 6)
                        Text(configured ? (customHost ?? "已配置") : "配置 API")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(configured ? .secondary : provider.brandColor)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(isCurrent ? provider.brandColor.opacity(0.55) : subtleBorder,
                                  lineWidth: isCurrent ? 1.3 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(provider.displayName) \(configured ? "已配置 API" : "配置 API")")
        .accessibilityIdentifier("wumind.home.api.\(provider.rawValue)")
    }

    private var homeGitHubAPICard: some View {
        let connectedRepo = store.attachedGitHubContext?.repo.fullName
        let hasToken = Keychain.githubToken != nil
        let isActive = connectedRepo != nil || hasToken
        let statusText: String = {
            if let repo = connectedRepo {
                return repo.split(separator: "/").last.map(String.init) ?? repo
            }
            return hasToken ? "已授权" : "连接仓库"
        }()
        return Button {
            dismissKeyboard()
            Haptics.tap()
            showingGitHub = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.teal)
                    .frame(width: 28, height: 28)
                    .background(Color.teal.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("GitHub")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isActive ? Color.green : Color.secondary.opacity(0.45))
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isActive ? .teal : .secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(connectedRepo != nil ? Color.teal.opacity(0.55) : subtleBorder,
                                  lineWidth: connectedRepo != nil ? 1.3 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("GitHub 仓库连接")
        .accessibilityIdentifier("wumind.home.api.github")
    }

    private func quickToolPill(_ title: String, icon: String, color: Color, id: String, action: @escaping () -> Void) -> some View {
        Button {
            dismissKeyboard()
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(elevatedSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func starterCard(icon: String, color: Color, title: String, prompt: String) -> some View {
        Button {
            Haptics.tap()
            draft = prompt
            composerFocused = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Flagship Multi-Model Capsule Composer

    private var composerPlaceholder: String {
        if let repo = store.attachedGitHubContext {
            return "结合 \(repo.repo.fullName) 提问，或输入消息…"
        }
        if let skill = store.activeSkill {
            return "以「\(skill.name)」模式向 WUMIND 提问…"
        }
        return "向 WUMIND 提问，支持粘贴 GitHub 仓库链接…"
    }

    private var compactComposerModelTitle: String {
        let name = headerModelTitle
        if name.count <= 14 { return name }
        return String(name.prefix(13)) + "…"
    }

    private var composerBar: some View {
        VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 10) {
                // Active Context Chips (Skill + GitHub Repo)
                if store.activeSkill != nil || store.attachedGitHubContext != nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            if let skill = store.activeSkill {
                                HStack(spacing: 5) {
                                    Button {
                                        dismissKeyboard()
                                        showingSkills = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: skill.icon)
                                                .font(.system(size: 10.5, weight: .semibold))
                                            Text(skill.name)
                                                .font(.caption2.weight(.semibold))
                                                .lineLimit(1)
                                        }
                                        .foregroundStyle(.indigo)
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        Haptics.tap()
                                        store.selectSkill(nil)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.indigo.opacity(0.65))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("取消 Skill")
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.indigo.opacity(0.12), in: Capsule())
                            }

                            if let gh = store.attachedGitHubContext {
                                HStack(spacing: 5) {
                                    Button {
                                        dismissKeyboard()
                                        showingGitHub = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                                .font(.system(size: 10, weight: .bold))
                                            Text(gh.attachedFiles.isEmpty
                                                 ? gh.repo.fullName
                                                 : "\(gh.repo.fullName) +\(gh.attachedFiles.count) 文件")
                                                .font(.caption2.weight(.semibold))
                                                .lineLimit(1)
                                        }
                                        .foregroundStyle(.teal)
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        Haptics.tap()
                                        store.attachedGitHubContext = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.teal.opacity(0.65))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("断开 GitHub 仓库")
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.teal.opacity(0.13), in: Capsule())
                            }
                        }
                    }
                }

                // Generous Flagship Multi-Line Input Area
                TextField(composerPlaceholder, text: $draft, axis: .vertical)
                    .lineLimit(2...7)
                    .font(.system(size: 16))
                    .frame(minHeight: 54, alignment: .topLeading)
                    .focused($composerFocused)
                    .disabled(generating)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !generating {
                            composerFocused = true
                        }
                    }
                    .accessibilityIdentifier("deepSeek.chat.composer")

                // Bottom Inline Controls Bar: Model Switcher + Thinking + Skills + GitHub + Toolbox + Send
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            // 1-Tap Inline Model Switcher Menu directly below input
                            Menu {
                                ForEach(WuMindModelOption.deepSeekDefaults) { model in
                                    let active = store.selectedProvider == .deepSeek && store.selectedModelID == model.id
                                    Button {
                                        Haptics.select()
                                        store.selectModel(model)
                                    } label: {
                                        if active {
                                            Label(model.displayName, systemImage: "checkmark")
                                        } else {
                                            Label(model.displayName, systemImage: "sparkles")
                                        }
                                    }
                                }
                                Divider()
                                ForEach(WuMindProvider.allCases.filter { $0 != .deepSeek }) { provider in
                                    let textModels = store.models(for: provider).filter(\.supportsTextChat)
                                    if !provider.hasKey {
                                        Button {
                                            dismissKeyboard()
                                            showingKeyFor = provider
                                        } label: {
                                            Label("配置 \(provider.shortName) API Key…", systemImage: "key.fill")
                                        }
                                    } else if textModels.isEmpty {
                                        Button {
                                            dismissKeyboard()
                                            store.selectProvider(provider)
                                            showingModelHub = true
                                        } label: {
                                            Label("拉取或填入 \(provider.shortName) 模型…", systemImage: "arrow.clockwise")
                                        }
                                    } else {
                                        Menu {
                                            ForEach(textModels.prefix(12)) { model in
                                                let active = store.selectedProvider == model.provider && store.selectedModelID == model.id
                                                Button {
                                                    Haptics.select()
                                                    store.selectModel(model)
                                                } label: {
                                                    if active {
                                                        Label(model.displayName, systemImage: "checkmark")
                                                    } else {
                                                        Text(model.displayName)
                                                    }
                                                }
                                            }
                                            Divider()
                                            Button {
                                                dismissKeyboard()
                                                store.selectProvider(provider)
                                                showingModelHub = true
                                            } label: {
                                                Label("刷新 / 手动输入模型…", systemImage: "slider.horizontal.3")
                                            }
                                        } label: {
                                            Label(provider.displayName, systemImage: provider.iconName)
                                        }
                                    }
                                }
                                Divider()
                                Button {
                                    dismissKeyboard()
                                    showingModelHub = true
                                } label: {
                                    Label("管理全部模型与自定义接口…", systemImage: "slider.horizontal.3")
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: store.selectedProvider.iconName)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(store.selectedProvider.brandColor)
                                    Text(compactComposerModelTitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(store.selectedProvider.brandColor.opacity(0.11), in: Capsule())
                                .overlay(Capsule().strokeBorder(store.selectedProvider.brandColor.opacity(0.25), lineWidth: 0.8))
                            }
                            .disabled(generating)
                            .accessibilityLabel("切换模型，当前 \(headerModelTitle)")
                            .accessibilityIdentifier("wumind.composer.model")

                            // Deep Thinking Toggle Pill
                            if store.selectedProvider.supportsDeepThinkingToggle {
                                Button {
                                    Haptics.select()
                                    store.toggleDeepThinking()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 11.5, weight: .semibold))
                                        Text("深度思考")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(store.deepThinking ? .white : .secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        store.deepThinking
                                            ? store.selectedProvider.brandColor
                                            : Color.secondary.opacity(0.13),
                                        in: Capsule()
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(generating)
                                .accessibilityLabel(store.deepThinking ? "深度思考已开启" : "深度思考已关闭")
                                .accessibilityIdentifier("deepSeek.chat.thinking")
                            }

                            // Skills Pill
                            Button {
                                dismissKeyboard()
                                Haptics.tap()
                                showingSkills = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: store.activeSkill?.icon ?? "wand.and.stars")
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text(store.activeSkill != nil ? "Skill ✓" : "Skills")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(store.activeSkill != nil ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    store.activeSkill != nil
                                        ? Color.indigo
                                        : Color.secondary.opacity(0.13),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(generating)
                            .accessibilityLabel("WUMIND Skills 技能中心")
                            .accessibilityIdentifier("wumind.skills.open")

                            // GitHub Repo Connector Pill
                            Button {
                                dismissKeyboard()
                                Haptics.tap()
                                showingGitHub = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                                        .font(.system(size: 10.5, weight: .bold))
                                    Text(store.attachedGitHubContext != nil ? "GitHub ✓" : "GitHub")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(store.attachedGitHubContext != nil ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    store.attachedGitHubContext != nil
                                        ? Color.teal
                                        : Color.secondary.opacity(0.13),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(generating)
                            .accessibilityLabel("连接 GitHub 仓库")
                            .accessibilityIdentifier("wumind.github.open")

                            // + AI Toolbox Quick Menu
                            Menu {
                                Button { openTool(.live) } label: {
                                    Label("实时语音通话", systemImage: "phone.waveform")
                                }
                                Button { openTool(.image) } label: {
                                    Label("文字生成图片", systemImage: "photo.on.rectangle.angled")
                                }
                                Button { openTool(.speech) } label: {
                                    Label("语音合成与转写", systemImage: "waveform")
                                }
                                Button { openTool(.code) } label: {
                                    Label("代码助手", systemImage: "curlybraces")
                                }
                                Button { openTool(.work) } label: {
                                    Label("工作助手", systemImage: "briefcase")
                                }
                                Divider()
                                Button { openTool(.tender) } label: {
                                    Label("生成投标书草稿", systemImage: "doc.text")
                                }
                                Button { openTool(.hub) } label: {
                                    Label("全部 AI 工具箱", systemImage: "square.grid.2x2")
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, height: 30)
                                    .background(Color.secondary.opacity(0.13), in: Circle())
                            }
                            .disabled(generating)
                            .accessibilityLabel("更多 AI 工具")
                        }
                        .padding(.vertical, 1)
                    }

                    if draft.utf8.count > questionLimit {
                        Text("过长")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DS.Palette.danger)
                    }

                    if composerFocused && !generating {
                        Button {
                            Haptics.tap()
                            dismissKeyboard()
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .background(Color.secondary.opacity(0.13), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("收起键盘")
                        .accessibilityIdentifier("wumind.composer.dismissKeyboard")
                    }

                    if generating {
                        Button(action: stopRequest) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(DS.Palette.danger, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("停止生成")
                        .accessibilityIdentifier("deepseek.chat.stop")
                    } else {
                        Button(action: requestSend) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(canSend ? .white : .secondary)
                                .frame(width: 38, height: 38)
                                .background(
                                    canSend ? store.selectedProvider.brandColor : Color.secondary.opacity(0.20),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .accessibilityLabel("发送消息")
                        .accessibilityIdentifier("deepseek.chat.send")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(composerFocused ? store.selectedProvider.brandColor.opacity(0.60) : subtleBorder,
                                  lineWidth: composerFocused ? 1.6 : 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.40 : 0.08), radius: 18, y: 5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: 780)
        .frame(maxWidth: .infinity)
        .background(canvasBackground)
    }

    // MARK: - Slide-Over History Sidebar Drawer

    private var historyDrawer: some View {
        GeometryReader { geo in
            let drawerWidth = min(316, geo.size.width * 0.84)
            VStack(spacing: 0) {
                // Drawer Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(red: 0.30, green: 0.45, blue: 1.0))
                        Text("WUMIND")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .tracking(0.8)
                    }
                    Spacer()
                    Button {
                        Haptics.tap()
                        stopRequest()
                        store.startNewConversation()
                        draft = ""
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            drawerOpen = false
                        }
                    } label: {
                        Label("新对话", systemImage: "square.and.pencil")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.30, green: 0.45, blue: 1.0).opacity(0.15), in: Capsule())
                            .foregroundStyle(Color(red: 0.30, green: 0.45, blue: 1.0))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("搜索历史对话", text: $drawerSearch)
                        .font(.subheadline)
                    if !drawerSearch.isEmpty {
                        Button { drawerSearch = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                Divider()

                // Conversation List
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        let filtered = filteredConversations
                        if filtered.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.text.bubble.right")
                                    .font(.title2)
                                    .foregroundStyle(.tertiary)
                                Text(drawerSearch.isEmpty ? "暂无历史对话" : "未找到匹配的对话")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(filtered) { convo in
                                drawerConversationRow(convo)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.immediately)

                Divider()

                // Drawer Footer Shortcuts
                VStack(spacing: 4) {
                    drawerActionRow(store.activeSkill.map { "Skills（\($0.name)）" } ?? "Skills 技能中心",
                                    icon: "wand.and.stars") {
                        drawerOpen = false
                        showingSkills = true
                    }
                    drawerActionRow(store.attachedGitHubContext.map { "GitHub（\($0.repo.fullName)）" } ?? "连接 GitHub 仓库",
                                    icon: "chevron.left.forwardslash.chevron.right") {
                        drawerOpen = false
                        showingGitHub = true
                    }
                    drawerActionRow("AI 工具箱（语音 / 生图 / 代码）", icon: "square.grid.2x2") {
                        drawerOpen = false
                        openTool(.hub)
                    }
                    drawerActionRow("生成投标书草稿", icon: "doc.text") {
                        drawerOpen = false
                        openTool(.tender)
                    }
                    drawerActionRow("模型与 API Key 中心", icon: "key") {
                        drawerOpen = false
                        showingModelHub = true
                    }
                    if !store.conversations.isEmpty {
                        drawerActionRow("清空历史记录", icon: "trash", destructive: true) {
                            confirmingClearAll = true
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(width: drawerWidth, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(elevatedSurface.ignoresSafeArea())
            .overlay(alignment: .trailing) {
                Rectangle().fill(subtleBorder).frame(width: 1).ignoresSafeArea()
            }
            .shadow(color: Color.black.opacity(0.25), radius: 22, x: 6, y: 0)
        }
    }

    private var filteredConversations: [WuMindConversation] {
        let q = drawerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.sortedConversations }
        return store.sortedConversations.filter { convo in
            convo.title.localizedCaseInsensitiveContains(q)
                || convo.modelDisplayName.localizedCaseInsensitiveContains(q)
                || convo.turns.contains {
                    $0.question.localizedCaseInsensitiveContains(q)
                        || $0.answer.localizedCaseInsensitiveContains(q)
                }
        }
    }

    private func drawerConversationRow(_ convo: WuMindConversation) -> some View {
        let active = convo.id == store.activeConversationID
        return Button {
            dismissKeyboard()
            Haptics.tap()
            stopRequest()
            store.openConversation(convo.id)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                drawerOpen = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: convo.isPinned ? "pin.fill" : convo.provider.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(convo.isPinned ? .orange : convo.provider.brandColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(convo.title)
                        .font(.subheadline.weight(active ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(convo.modelDisplayName)
                        Text("·")
                        Text(convo.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                active ? convo.provider.brandColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                store.togglePin(convo.id)
            } label: {
                Label(convo.isPinned ? "取消置顶" : "置顶对话", systemImage: convo.isPinned ? "pin.slash" : "pin")
            }
            Button {
                renameDraft = convo.title
                renamingConversation = convo
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive) {
                store.deleteConversation(convo.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func drawerActionRow(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            dismissKeyboard()
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(destructive ? DS.Palette.danger : .secondary)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(destructive ? DS.Palette.danger : .primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sending & Streaming Engine

    private func requestSend() {
        guard canSend else { return }
        dismissKeyboard()
        let provider = store.selectedProvider
        guard provider.hasKey else {
            showingKeyFor = provider
            return
        }
        if provider != .deepSeek && store.selectedModelID.isEmpty {
            showingModelHub = true
            return
        }
        beginRequest()
    }

    private func beginRequest() {
        let prompt = cleanedDraft
        guard !generating, !prompt.isEmpty, prompt.utf8.count <= questionLimit else { return }
        let provider = store.selectedProvider
        guard let apiKey = provider.apiKey(), !apiKey.isEmpty else {
            showingKeyFor = provider
            return
        }

        let convoID = store.ensureActiveConversation(initialPrompt: prompt)
        let turnID = UUID()
        let isDeep = store.deepThinking && provider.supportsDeepThinkingToggle
        let modelLabel = headerModelTitle
        let priorTurns = store.conversations.first(where: { $0.id == convoID })?.turns ?? []
        let autoRepoName = store.attachedGitHubContext == nil ? WuMindGitHubClient.detectRepoInText(prompt) : nil

        draft = ""
        following = true
        activeTurnID = turnID
        activeConversationForTask = convoID
        thinkingStartedAt = Date()

        let turn = WuMindTurn(
            id: turnID,
            question: prompt,
            modelLabel: modelLabel,
            provider: provider,
            isDeepThinking: isDeep,
            state: .generating
        )
        store.appendTurn(turn, to: convoID)

        if provider == .deepSeek {
            let dsModel = DeepSeekChatClient.Model(rawValue: store.selectedModelID) ?? .pro
            let dsThinking: DeepSeekChatClient.Thinking = isDeep ? .deep : .normal
            let history = buildDeepSeekContext(priorTurns: priorTurns, prompt: prompt)

            activeTask = Task { @MainActor in
                var answerStarted = false
                do {
                    if let repoName = autoRepoName,
                       let fetched = try? await WuMindGitHubClient().fetchRepoContext(fullName: repoName, token: Keychain.githubToken) {
                        store.attachedGitHubContext = fetched
                    }
                    let sysPrompt = store.composedSystemPrompt()
                    for try await event in DeepSeekChatClient.streamEvents(
                        messages: history,
                        apiKey: apiKey,
                        model: dsModel,
                        thinking: dsThinking,
                        systemPrompt: sysPrompt
                    ) {
                        guard !Task.isCancelled, activeTurnID == turnID else { return }
                        switch event {
                        case .reasoning(let delta):
                            store.mutateTurn(conversationID: convoID, turnID: turnID) { item in
                                item.reasoning += delta
                            }
                        case .content(let delta):
                            if !answerStarted {
                                answerStarted = true
                                let elapsed = thinkingStartedAt.map { Date().timeIntervalSince($0) }
                                store.mutateTurn(conversationID: convoID, turnID: turnID) { item in
                                    if !item.reasoning.isEmpty, item.reasoningSeconds == nil {
                                        item.reasoningSeconds = elapsed
                                    }
                                    item.answer += delta
                                }
                            } else {
                                store.mutateTurn(conversationID: convoID, turnID: turnID) { item in
                                    item.answer += delta
                                }
                            }
                        }
                    }
                    try Task.checkCancellation()
                    finishTurn(conversationID: convoID, turnID: turnID, state: .complete)
                } catch is CancellationError {
                    finishTurn(conversationID: convoID, turnID: turnID, state: .stopped)
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? "未收到完整回复，请检查网络后重试。"
                    finishTurn(conversationID: convoID, turnID: turnID, state: .failed(message))
                }
            }
        } else if let mp = provider.multiProvider {
            let modelObj = AIProviderModel(id: store.selectedModelID, displayName: modelLabel, supportsTextChat: true)
            let history = buildMultiProviderContext(priorTurns: priorTurns, prompt: prompt)

            activeTask = Task { @MainActor in
                do {
                    if let repoName = autoRepoName,
                       let fetched = try? await WuMindGitHubClient().fetchRepoContext(fullName: repoName, token: Keychain.githubToken) {
                        store.attachedGitHubContext = fetched
                    }
                    let sysPrompt = store.composedSystemPrompt()
                    let reply = try await MultiProviderAIClient().sendDetailed(
                        provider: mp,
                        model: modelObj,
                        apiKey: apiKey,
                        messages: history,
                        deepThinking: isDeep,
                        baseURL: AIProviderEndpoints.baseURL(for: mp),
                        systemPrompt: sysPrompt
                    )
                    guard !Task.isCancelled, activeTurnID == turnID else { return }
                    let elapsed = thinkingStartedAt.map { Date().timeIntervalSince($0) }
                    store.mutateTurn(conversationID: convoID, turnID: turnID) { item in
                        if let reasoning = reply.reasoning, !reasoning.isEmpty {
                            item.reasoning = reasoning
                            item.reasoningSeconds = elapsed
                        }
                        item.answer = reply.answer
                    }
                    finishTurn(conversationID: convoID, turnID: turnID, state: .complete)
                } catch is CancellationError {
                    finishTurn(conversationID: convoID, turnID: turnID, state: .stopped)
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? "未收到回复，请检查网络或 API Key。"
                    finishTurn(conversationID: convoID, turnID: turnID, state: .failed(message))
                }
            }
        }
    }

    private func buildDeepSeekContext(priorTurns: [WuMindTurn], prompt: String) -> [DeepSeekChatClient.Message] {
        var remaining = contextLimit - prompt.utf8.count
        var reversedPairs: [DeepSeekChatClient.Message] = []
        for turn in priorTurns.lazy.reversed().filter({ $0.state == .complete && !$0.answer.isEmpty }).prefix(12) {
            let cost = turn.question.utf8.count + turn.answer.utf8.count
            guard cost <= remaining else { break }
            remaining -= cost
            reversedPairs.append(.init(role: .assistant, content: turn.answer))
            reversedPairs.append(.init(role: .user, content: turn.question))
        }
        return Array(reversedPairs.reversed()) + [.init(role: .user, content: prompt)]
    }

    private func buildMultiProviderContext(priorTurns: [WuMindTurn], prompt: String) -> [AIProviderMessage] {
        var remaining = 48_000 - prompt.utf8.count
        var reversedPairs: [AIProviderMessage] = []
        for turn in priorTurns.lazy.reversed().filter({ $0.state == .complete && !$0.answer.isEmpty }).prefix(12) {
            let cost = turn.question.utf8.count + turn.answer.utf8.count
            guard cost <= remaining else { break }
            remaining -= cost
            reversedPairs.append(.init(role: .assistant, text: turn.answer))
            reversedPairs.append(.init(role: .user, text: turn.question))
        }
        return Array(reversedPairs.reversed()) + [.init(role: .user, text: prompt)]
    }

    private func finishTurn(conversationID: UUID, turnID: UUID, state: WuMindTurn.State) {
        guard activeTurnID == turnID else { return }
        let elapsed = thinkingStartedAt.map { Date().timeIntervalSince($0) }
        store.mutateTurn(conversationID: conversationID, turnID: turnID, persist: true) { item in
            if !item.reasoning.isEmpty && item.reasoningSeconds == nil {
                item.reasoningSeconds = elapsed
            }
            item.state = state
        }
        activeTurnID = nil
        activeConversationForTask = nil
        activeTask = nil
        thinkingStartedAt = nil
    }

    private func stopRequest() {
        activeTask?.cancel()
        if let cID = activeConversationForTask, let tID = activeTurnID {
            finishTurn(conversationID: cID, turnID: tID, state: .stopped)
        } else {
            activeTurnID = nil
            activeConversationForTask = nil
            activeTask = nil
            thinkingStartedAt = nil
        }
    }

    private func copyText(_ text: String) {
        UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
        ToastCenter.shared.show("已复制", style: .success)
    }
}

// MARK: - Turn & Thinking Process View

private struct WuMindTurnView: View {
    let turn: WuMindTurn
    let isLast: Bool
    let isGenerating: Bool
    let thinkingStartedAt: Date?
    let elevatedSurface: Color
    let subtleBorder: Color
    let onCopy: (String) -> Void
    let onRetryPrompt: (String) -> Void
    let onRegenerate: () -> Void
    let onManageKey: () -> Void

    @State private var thinkingExpanded = true

    private var isCurrentlyThinking: Bool {
        isGenerating && turn.answer.isEmpty && (turn.isDeepThinking || !turn.reasoning.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // User prompt pill
            HStack {
                Spacer(minLength: 44)
                Text(turn.question)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(
                        turn.provider.brandColor.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(turn.provider.brandColor.opacity(0.22), lineWidth: 0.8)
                    )
                    .accessibilityLabel(Text("你：\(turn.question)"))
            }

            // Assistant editorial response
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: turn.provider.iconName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(turn.provider.brandColor, in: Circle())
                    Text(turn.modelLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }

                // Official DeepSeek-style collapsible Thinking Process block
                if !turn.reasoning.isEmpty || isCurrentlyThinking {
                    thinkingBlock
                }

                if !turn.answer.isEmpty {
                    WuMindMarkdownView(
                        text: turn.answer,
                        elevatedSurface: elevatedSurface,
                        subtleBorder: subtleBorder,
                        onCopyCode: onCopy
                    )
                }

                // State footer
                switch turn.state {
                case .generating:
                    if turn.answer.isEmpty && !isCurrentlyThinking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在思考并生成回复…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                case .complete:
                    HStack(spacing: 14) {
                        Button { onCopy(turn.answer) } label: {
                            Label("复制", systemImage: "doc.on.doc")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        if !turn.reasoning.isEmpty {
                            Button { onCopy(turn.reasoning) } label: {
                                Label("复制思考", systemImage: "brain")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        if isLast {
                            Button(action: onRegenerate) {
                                Label("重新生成", systemImage: "arrow.clockwise")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                case .stopped:
                    Text("已停止生成（未完成片段不会带入下一轮上下文）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.danger)
                        HStack(spacing: 10) {
                            if isLast {
                                Button("放回输入框") { onRetryPrompt(turn.question) }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                            }
                            if message.contains("Key") || message.contains("密钥") || message.contains("余额") {
                                Button("管理 API Key", action: onManageKey)
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding(12)
                    .background(DS.Palette.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.leading, 2)
        }
    }

    private var thinkingBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    thinkingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    if isCurrentlyThinking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "brain.head.profile")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(turn.provider.brandColor)
                    }
                    Text(thinkingHeaderTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: thinkingExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(elevatedSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wumind.thinking.toggle")

            if thinkingExpanded {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(turn.provider.brandColor.opacity(0.45))
                        .frame(width: 2.5)
                    Group {
                        if turn.reasoning.isEmpty {
                            Text("正在梳理思路与推理步骤…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(turn.reasoning)
                                .font(.system(size: 13.5))
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var thinkingHeaderTitle: String {
        if isCurrentlyThinking {
            if let started = thinkingStartedAt {
                let sec = max(1, Int(Date().timeIntervalSince(started).rounded()))
                return "正在深度思考… \(sec)s"
            }
            return "正在深度思考…"
        }
        if let sec = turn.reasoningSeconds {
            return "已深度思考（用时 \(max(1, Int(sec.rounded()))) 秒）"
        }
        return "已深度思考"
    }
}

// MARK: - Rich Markdown & Styled Code Block Renderer

private struct WuMindMarkdownView: View {
    let text: String
    let elevatedSurface: Color
    let subtleBorder: Color
    let onCopyCode: (String) -> Void

    private struct Block: Identifiable {
        let id: Int
        let language: String?
        let content: String
    }

    var body: some View {
        let blocks = parseBlocks(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                if let lang = block.language {
                    codeCard(language: lang, code: block.content)
                } else {
                    proseView(block.content)
                }
            }
        }
    }

    private func codeCard(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "代码" : language)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { onCopyCode(code) } label: {
                    Label("复制代码", systemImage: "doc.on.doc")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.10))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func proseView(_ raw: String) -> some View {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    Spacer().frame(height: 2)
                } else if trimmed == "---" || trimmed == "***" {
                    Divider().padding(.vertical, 4)
                } else if trimmed.hasPrefix("### ") {
                    markdownText(String(trimmed.dropFirst(4)))
                        .font(.headline)
                        .padding(.top, 4)
                } else if trimmed.hasPrefix("## ") {
                    markdownText(String(trimmed.dropFirst(3)))
                        .font(.title3.bold())
                        .padding(.top, 6)
                } else if trimmed.hasPrefix("# ") {
                    markdownText(String(trimmed.dropFirst(2)))
                        .font(.title2.bold())
                        .padding(.top, 6)
                } else if trimmed.hasPrefix("> ") {
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.4)).frame(width: 3)
                        markdownText(String(trimmed.dropFirst(2)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        markdownText(String(trimmed.dropFirst(2)))
                            .font(.body)
                            .lineSpacing(4)
                    }
                } else {
                    markdownText(line)
                        .font(.body)
                        .lineSpacing(4)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markdownText(_ source: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(source)
    }

    private func parseBlocks(_ source: String) -> [Block] {
        var result: [Block] = []
        var language: String?
        var lines: [Substring] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let marker = line.trimmingCharacters(in: .whitespaces)
            if language == nil, marker.hasPrefix("```"), !marker.dropFirst(3).contains("`") {
                if !lines.isEmpty {
                    result.append(Block(id: result.count, language: nil, content: lines.joined(separator: "\n")))
                }
                lines.removeAll(keepingCapacity: true)
                language = String(marker.dropFirst(3).prefix(24)).trimmingCharacters(in: .whitespaces)
            } else if language != nil, marker == "```" {
                result.append(Block(id: result.count, language: language, content: lines.joined(separator: "\n")))
                lines.removeAll(keepingCapacity: true)
                language = nil
            } else {
                lines.append(line)
            }
        }
        if !lines.isEmpty {
            result.append(Block(id: result.count, language: language, content: lines.joined(separator: "\n")))
        }
        return result
    }
}

// MARK: - Unified Multi-Provider Model & Key Hub Sheet

private struct WuMindModelHubSheet: View {
    @ObservedObject var store: WuMindStore
    let onEditKey: (WuMindProvider) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewingProvider: WuMindProvider
    @State private var query = ""
    @State private var manualModelID = ""
    @State private var refreshing = false
    @State private var refreshError: String?

    init(store: WuMindStore, onEditKey: @escaping (WuMindProvider) -> Void) {
        self.store = store
        self.onEditKey = onEditKey
        _viewingProvider = State(initialValue: store.selectedProvider)
    }

    private var availableTextModels: [WuMindModelOption] {
        let base = store.models(for: viewingProvider).filter(\.supportsTextChat)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.displayName.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Horizontal Provider Switcher Strip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WuMindProvider.allCases) { provider in
                            let selected = provider == viewingProvider
                            Button {
                                Haptics.select()
                                viewingProvider = provider
                                refreshError = nil
                                query = ""
                                manualModelID = ""
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(provider.hasKey ? Color.green : Color.secondary.opacity(0.35))
                                        .frame(width: 7, height: 7)
                                    Text(provider.shortName)
                                        .font(.subheadline.weight(selected ? .bold : .medium))
                                }
                                .foregroundStyle(selected ? .white : .primary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(
                                    selected ? provider.brandColor : Color.secondary.opacity(0.12),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("wumind.provider.\(provider.rawValue)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider()

                List {
                    // Key & Refresh Header Section
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(viewingProvider.displayName)
                                    .font(.headline)
                                Text(viewingProvider.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let mp = viewingProvider.multiProvider,
                                   let host = AIProviderEndpoints.displayHost(for: mp) {
                                    Text("自定义接口：\(host)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(viewingProvider.brandColor)
                                }
                            }
                            Spacer()
                            Button(viewingProvider.hasKey ? "配置 / Key" : "填写 Key") {
                                onEditKey(viewingProvider)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(viewingProvider.brandColor)
                            .controlSize(.small)
                        }
                        if viewingProvider != .deepSeek && viewingProvider.hasKey {
                            HStack {
                                Button {
                                    fetchModels(for: viewingProvider)
                                } label: {
                                    Label(availableTextModels.isEmpty ? "拉取可用模型列表" : "刷新模型列表",
                                          systemImage: "arrow.clockwise")
                                }
                                .disabled(refreshing)
                                Spacer()
                                if refreshing { ProgressView() }
                            }
                            HStack(spacing: 8) {
                                TextField("手动输入模型编号（如 gpt-4o / gemini-2.5-flash）", text: $manualModelID)
                                    .font(.subheadline)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                Button("使用") {
                                    let trimmed = manualModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    Haptics.select()
                                    store.addManualModel(trimmed, for: viewingProvider)
                                    manualModelID = ""
                                    dismiss()
                                }
                                .font(.subheadline.weight(.semibold))
                                .disabled(manualModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        if let refreshError {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(refreshError)
                                    .font(.footnote)
                                    .foregroundStyle(DS.Palette.danger)
                                Button("检查 Key 或配置中转站地址") {
                                    onEditKey(viewingProvider)
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                    }

                    // Model List Section
                    Section(viewingProvider == .deepSeek ? "DeepSeek 模型" : "可用文字对话模型（\(availableTextModels.count)）") {
                        if !viewingProvider.hasKey && viewingProvider != .deepSeek {
                            Text("先点击上方「填写 Key」（使用中转站/聚合 API 时顺手填入自定义接口地址），密钥只保存在本机钥匙串。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if availableTextModels.isEmpty {
                            Text("点击上方「拉取可用模型列表」，或直接在上方手动输入模型编号即可开聊。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(availableTextModels) { model in
                                let isActive = store.selectedProvider == model.provider && store.selectedModelID == model.id
                                Button {
                                    Haptics.select()
                                    store.selectModel(model)
                                    dismiss()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(model.displayName)
                                                .font(.body.weight(isActive ? .semibold : .regular))
                                                .foregroundStyle(.primary)
                                            if model.displayName != model.id {
                                                Text(model.id)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if isActive {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(viewingProvider.brandColor)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .searchable(text: $query, prompt: "搜索模型名称或编号")
            }
            .navigationTitle("WUMIND 模型与密钥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }

    private func fetchModels(for provider: WuMindProvider) {
        guard !refreshing, let mp = provider.multiProvider, let key = provider.apiKey() else { return }
        refreshing = true
        refreshError = nil
        Task { @MainActor in
            defer { refreshing = false }
            do {
                let fetched = try await MultiProviderAIClient().listModels(
                    provider: mp,
                    apiKey: key,
                    baseURL: AIProviderEndpoints.baseURL(for: mp)
                )
                store.updateCachedModels(fetched, for: provider)
                if fetched.filter(\.supportsTextChat).isEmpty {
                    refreshError = "该服务商未返回可用于文字聊天的模型，可在上方直接手动填入模型编号。"
                }
            } catch {
                refreshError = (error as? LocalizedError)?.errorDescription ?? "未能获取模型列表。"
            }
        }
    }
}

// MARK: - WUMIND Skills Center Sheet

private struct WuMindSkillsSheet: View {
    @ObservedObject var store: WuMindStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingSkill: WuMindSkill?
    @State private var creatingNew = false

    var body: some View {
        NavigationStack {
            List {
                Section("当前对话模式") {
                    if let active = store.activeSkill {
                        HStack(spacing: 10) {
                            Image(systemName: active.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.indigo, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(active.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(active.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("停用") {
                                Haptics.tap()
                                store.selectSkill(nil)
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Label("通用默认模式（无额外 Skill 约束）", systemImage: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        Haptics.tap()
                        creatingNew = true
                    } label: {
                        Label("新建自定义 Skill", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                    .accessibilityIdentifier("wumind.skills.create")

                    ForEach(store.customSkills) { skill in
                        skillRow(skill)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.deleteCustomSkill(skill.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    editingSkill = skill
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.indigo)
                            }
                    }
                } header: {
                    Text("我的自定义 Skills（\(store.customSkills.count)）")
                }

                Section {
                    ForEach(WuMindSkill.builtIn) { skill in
                        skillRow(skill)
                    }
                } header: {
                    Text("内置旗舰 Skills")
                } footer: {
                    Text("启用 Skill 后会自动作为系统指令注入当前所选模型（DeepSeek / GPT / Gemini / Claude / Grok 均支持）。自定义 Skill 仅保存在本机。")
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("WUMIND Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $creatingNew) {
                WuMindSkillEditorSheet(existing: nil) { name, icon, summary, prompt in
                    store.saveCustomSkill(id: nil, name: name, icon: icon, summary: summary, prompt: prompt)
                }
            }
            .sheet(item: $editingSkill) { skill in
                WuMindSkillEditorSheet(existing: skill) { name, icon, summary, prompt in
                    store.saveCustomSkill(id: skill.id, name: name, icon: icon, summary: summary, prompt: prompt)
                }
            }
        }
    }

    private func skillRow(_ skill: WuMindSkill) -> some View {
        let active = store.activeSkillID == skill.id
        return Button {
            Haptics.select()
            store.selectSkill(active ? nil : skill)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: skill.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(active ? .white : .indigo)
                    .frame(width: 32, height: 32)
                    .background(
                        active ? Color.indigo : Color.indigo.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(skill.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if !skill.isBuiltIn {
                            Text("自定义")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.indigo.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(skill.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(skill.prompt)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.indigo)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wumind.skill.\(skill.id)")
    }
}

private struct WuMindSkillEditorSheet: View {
    let existing: WuMindSkill?
    let onSave: (String, String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var summary: String
    @State private var prompt: String

    private let iconOptions = [
        "wand.and.stars", "chevron.left.forwardslash.chevron.right", "hammer.fill",
        "doc.richtext", "chart.xyaxis.line", "globe", "bolt.fill", "cpu"
    ]

    init(existing: WuMindSkill?, onSave: @escaping (String, String, String, String) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _icon = State(initialValue: existing?.icon ?? "wand.and.stars")
        _summary = State(initialValue: existing?.summary ?? "")
        _prompt = State(initialValue: existing?.prompt ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Skill 名称与简介") {
                    TextField("例如：SwiftUI 架构评审 / 投标审查专家", text: $name)
                    TextField("一句话用途说明（选填）", text: $summary)
                }

                Section("图标") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(iconOptions, id: \.self) { symbol in
                                let picked = icon == symbol
                                Button {
                                    Haptics.select()
                                    icon = symbol
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(picked ? .white : .primary)
                                        .frame(width: 38, height: 38)
                                        .background(picked ? Color.indigo : Color.secondary.opacity(0.14), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    TextField("输入系统角色指令、输出格式、约束要求…", text: $prompt, axis: .vertical)
                        .lineLimit(5...12)
                } header: {
                    Text("Skill 提示词（System Prompt）")
                } footer: {
                    Text("保存后将立即启用并保存在本机。")
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(existing == nil ? "新建 Skill" : "编辑 Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name, icon, summary, prompt)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }
}

// MARK: - Direct GitHub Repository Connector Sheet

private struct WuMindGitHubSheet: View {
    @ObservedObject var store: WuMindStore
    @Environment(\.dismiss) private var dismiss

    @State private var repoInput = ""
    @State private var fileFilter = ""
    @State private var tokenDraft = ""
    @State private var hasToken = false

    @State private var loadingRepo = false
    @State private var loadingFilePath: String?
    @State private var loadingUserRepos = false
    @State private var userRepos: [WuMindGitHubClient.RepoSummary] = []
    @State private var statusError: String?
    @State private var statusMessage: String?

    private var filteredRepoFiles: [String] {
        guard let ctx = store.attachedGitHubContext else { return [] }
        let q = fileFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = q.isEmpty ? ctx.filePaths : ctx.filePaths.filter { $0.localizedCaseInsensitiveContains(q) }
        return Array(matches.prefix(40))
    }

    var body: some View {
        NavigationStack {
            List {
                // Currently Connected Repo Section
                if let ctx = store.attachedGitHubContext {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(ctx.repo.fullName, systemImage: "checkmark.seal.fill")
                                    .font(.headline)
                                    .foregroundStyle(.teal)
                                Spacer()
                                if ctx.repo.isPrivate {
                                    Text("私有")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.14), in: Capsule())
                                }
                            }
                            if !ctx.repo.description.isEmpty {
                                Text(ctx.repo.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("分支 \(ctx.repo.defaultBranch) · \(ctx.filePaths.count) 个文件 · \(ctx.recentCommits.count) 条近期提交 · README \(ctx.readmeExcerpt.isEmpty ? "无" : "已读取")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if !ctx.attachedFiles.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("已附加源码文件（发送时自动带入上下文）")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(ctx.attachedFiles) { file in
                                    HStack {
                                        Label(file.path, systemImage: "doc.text.fill")
                                            .font(.caption.monospaced())
                                            .lineLimit(1)
                                        Spacer()
                                        Button {
                                            detachFile(file.path)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        Button("断开此仓库", role: .destructive) {
                            Haptics.tap()
                            store.attachedGitHubContext = nil
                            statusMessage = "已断开 GitHub 仓库上下文。"
                        }
                    } header: {
                        Text("当前已连接仓库")
                    }

                    if !ctx.filePaths.isEmpty {
                        Section {
                            TextField("筛选文件路径（如 Swift / View / Package）", text: $fileFilter)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)

                            ForEach(filteredRepoFiles, id: \.self) { path in
                                let attached = ctx.attachedFiles.contains { $0.path == path }
                                Button {
                                    if attached {
                                        detachFile(path)
                                    } else {
                                        attachFile(path, in: ctx)
                                    }
                                } label: {
                                    HStack {
                                        Text(path)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        if loadingFilePath == path {
                                            ProgressView().controlSize(.small)
                                        } else if attached {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.teal)
                                        } else {
                                            Image(systemName: "plus.circle")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(loadingFilePath != nil)
                            }
                        } header: {
                            Text("点选附加仓库源码文件（最多显示前 40 项）")
                        }
                    }
                }

                // Connect any repo by owner/repo or URL
                Section {
                    TextField("输入 owner/repo 或 github.com 链接", text: $repoInput)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("wumind.github.repoInput")

                    Button {
                        connectRepo(repoInput)
                    } label: {
                        HStack {
                            Label("连接并读取仓库上下文", systemImage: "link.badge.plus")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if loadingRepo {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(loadingRepo || repoInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("wumind.github.connect")

                    if let statusError {
                        Text(statusError)
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.danger)
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.teal)
                    }
                } header: {
                    Text("连接任意 GitHub 仓库")
                } footer: {
                    Text("公开仓库无需 Token 即可直接连接；访问私有仓库请先在下方保存本机 GitHub Token。在对话框中直接粘贴 github.com/owner/repo 链接也会自动抓取上下文。")
                }

                // User Repositories Picker (when GitHub PAT is configured)
                if hasToken {
                    Section {
                        Button {
                            fetchUserRepos()
                        } label: {
                            HStack {
                                Label(userRepos.isEmpty ? "拉取我的 GitHub 仓库列表" : "刷新我的仓库列表",
                                      systemImage: "arrow.clockwise")
                                Spacer()
                                if loadingUserRepos {
                                    ProgressView().controlSize(.small)
                                }
                            }
                        }
                        .disabled(loadingUserRepos)

                        ForEach(userRepos) { repo in
                            Button {
                                repoInput = repo.fullName
                                connectRepo(repo.fullName)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(repo.fullName)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                            if repo.isPrivate {
                                                Image(systemName: "lock.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                        if !repo.description.isEmpty {
                                            Text(repo.description)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if store.attachedGitHubContext?.repo.fullName == repo.fullName {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.teal)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("我的 GitHub 仓库")
                    }
                }

                // Device-only GitHub PAT Section
                Section {
                    HStack {
                        Image(systemName: hasToken ? "checkmark.shield.fill" : "key.fill")
                            .foregroundStyle(hasToken ? .green : .secondary)
                        Text(hasToken ? "已配置本机 GitHub Token（支持私有仓库）" : "未配置 Token（当前仅可连接公开仓库）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    SecureField(hasToken ? "输入新 Token 可替换（ghp_ / github_pat_）" : "粘贴 GitHub Personal Access Token（选填）",
                                text: $tokenDraft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("wumind.github.tokenInput")

                    Button("保存 Token 到本机钥匙串") {
                        saveToken()
                    }
                    .disabled(MultiProviderAIClient.sanitizePastedKey(tokenDraft).isEmpty)

                    if hasToken {
                        Button("移除本机 GitHub Token", role: .destructive) {
                            _ = Keychain.setGitHubToken("")
                            hasToken = false
                            userRepos = []
                            statusMessage = "已移除本机 GitHub Token。"
                        }
                    }
                } header: {
                    Text("GitHub Access Token（仅本机钥匙串，不上传）")
                } footer: {
                    Text("建议使用 GitHub Fine-grained PAT（仅授予目标仓库 Contents 只读权限）。Token 仅存本机钥匙串，仅直连 api.github.com。")
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("连接 GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .onAppear {
                hasToken = Keychain.githubToken != nil
                if repoInput.isEmpty, let existing = store.attachedGitHubContext?.repo.fullName {
                    repoInput = existing
                }
            }
        }
    }

    private func saveToken() {
        statusError = nil
        statusMessage = nil
        let cleaned = MultiProviderAIClient.sanitizePastedKey(tokenDraft)
        guard !cleaned.isEmpty, cleaned.utf8.count <= 512,
              cleaned.utf8.allSatisfy({ (33...126).contains($0) }) else {
            statusError = "Token 格式不正确，请粘贴纯英文数字 GitHub Token。"
            return
        }
        guard Keychain.setGitHubToken(cleaned) else {
            statusError = "未能写入钥匙串，请解锁设备后重试。"
            return
        }
        tokenDraft = ""
        hasToken = true
        statusMessage = "GitHub Token 已安全保存到本机。"
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func fetchUserRepos() {
        guard !loadingUserRepos, let token = Keychain.githubToken else { return }
        loadingUserRepos = true
        statusError = nil
        Task { @MainActor in
            defer { loadingUserRepos = false }
            do {
                userRepos = try await WuMindGitHubClient().listUserRepos(token: token)
                if userRepos.isEmpty {
                    statusMessage = "该 Token 未返回可见仓库。"
                }
            } catch {
                statusError = (error as? LocalizedError)?.errorDescription ?? "无法拉取 GitHub 仓库列表。"
            }
        }
    }

    private func connectRepo(_ raw: String) {
        guard !loadingRepo else { return }
        loadingRepo = true
        statusError = nil
        statusMessage = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task { @MainActor in
            defer { loadingRepo = false }
            do {
                let ctx = try await WuMindGitHubClient().fetchRepoContext(
                    fullName: raw,
                    token: Keychain.githubToken
                )
                store.attachedGitHubContext = ctx
                statusMessage = "已连接 \(ctx.repo.fullName)，提问时将自动带入仓库结构与 README。"
            } catch {
                statusError = (error as? LocalizedError)?.errorDescription ?? "连接仓库失败。"
            }
        }
    }

    private func attachFile(_ path: String, in ctx: WuMindGitHubClient.RepoContext) {
        guard loadingFilePath == nil else { return }
        loadingFilePath = path
        statusError = nil
        Task { @MainActor in
            defer { loadingFilePath = nil }
            do {
                let file = try await WuMindGitHubClient().fetchFileContent(
                    fullName: ctx.repo.fullName,
                    path: path,
                    ref: ctx.repo.defaultBranch,
                    token: Keychain.githubToken
                )
                if var current = store.attachedGitHubContext, current.repo.fullName == ctx.repo.fullName {
                    if !current.attachedFiles.contains(where: { $0.path == file.path }) {
                        current.attachedFiles.append(file)
                        store.attachedGitHubContext = current
                    }
                }
            } catch {
                statusError = (error as? LocalizedError)?.errorDescription ?? "无法读取该文件内容。"
            }
        }
    }

    private func detachFile(_ path: String) {
        guard var current = store.attachedGitHubContext else { return }
        current.attachedFiles.removeAll { $0.path == path }
        store.attachedGitHubContext = current
    }
}

