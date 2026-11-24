import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Flagship multi-model AI aggregator workspace ("WUMIND").
/// Presented full-screen without the bottom duty tab bar; supports dual channels
/// (Own API Keys vs WUMIND Managed Real-Time Metered Gateway), file & photo uploads,
/// Skills center, direct GitHub repository context, persistent local session history,
/// and live collapsible chain-of-thought reasoning.
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
    @State private var showingWallet = false
    @State private var showingFileImporter = false
    @State private var showingPhotoPicker = false
    @State private var pickedPhotoItem: PhotosPickerItem? = nil
    @State private var importingAttachment = false
    @State private var showingKeyFor: WuMindProvider?
    @State private var confirmingClearAll = false
    @State private var renamingConversation: WuMindConversation?
    @State private var renameDraft = ""

    @State private var following = true
    @State private var compactedBannerExpanded = false

    @State private var toolboxPath: [ToolboxDestination] = []
    @FocusState private var composerFocused: Bool

    private let bottomAnchor = "wumind.chat.bottom"
    private let questionLimit = 200_000

    private static let allowedUploadTypes: [UTType] = {
        var types: [UTType] = [.pdf, .plainText, .commaSeparatedText, .json, .xml, .sourceCode, .utf8PlainText, .data]
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        return types
    }()

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
    private var generating: Bool { store.isGenerating }
    private var generatingInCurrentConversation: Bool {
        store.isGenerating && store.activeGenerationConversationID == store.activeConversationID
    }
    private var cleanedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool {
        !generating
            && !importingAttachment
            && (!cleanedDraft.isEmpty || !store.pendingAttachments.isEmpty)
            && cleanedDraft.utf8.count <= questionLimit
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
                    if let bgID = store.activeGenerationConversationID,
                       bgID != store.activeConversationID {
                        Button {
                            Haptics.tap()
                            store.openConversation(bgID)
                        } label: {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.mini)
                                Text("「\(store.activeGenerationConversationTitle ?? "对话")」正在后台生成中")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text("点击查看")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(activeAccentColor)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(activeAccentColor.opacity(0.10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wumind.bg.banner")
                    }
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
        .background(
            Color.clear
                .photosPicker(isPresented: $showingPhotoPicker, selection: $pickedPhotoItem, matching: .images)
        )
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: Self.allowedUploadTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImportedFiles(result)
        }
        .onChange(of: pickedPhotoItem) { item in
            guard let item else { return }
            handlePickedPhoto(item)
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
        .sheet(isPresented: $showingWallet) {
            WuMindWalletSheet(store: store)
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
                store.stopGeneration()
                store.deleteAllConversations()
            }
        } message: {
            Text("此操作只删除本机聊天记录，不会影响 API Key 或值班数据。")
        }
        .onAppear {
            if store.channel == .managed && store.hasGatewayURL {
                Task { @MainActor in
                    try? await store.syncManagedGatewayConfig()
                    if Keychain.wumindGatewayUserToken != nil {
                        try? await store.refreshManagedAccount()
                    }
                }
            }
        }
        .onDisappear {
            // Keep active AI generation running seamlessly in the background when leaving WUMIND!
            dismissKeyboard()
            store.flushSave()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deepseek.chat")
    }

    // MARK: - Top Header Bar

    private var topBar: some View {
        HStack(spacing: 8) {
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
                if store.channel == .managed {
                    showingWallet = true
                } else {
                    showingModelHub = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.channel == .managed ? "bolt.shield.fill" : store.activeProviderForDisplay.iconName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(store.channel == .managed ? Color.indigo : store.activeProviderForDisplay.brandColor)
                    Text(headerModelTitle)
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if store.channel == .managed {
                        Text(store.managedBalanceYuan.map { String(format: "¥%.2f", $0) } ?? "充值")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.12), in: Capsule())
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(elevatedSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(generating)
            .accessibilityLabel("切换模型，当前 \(headerModelTitle)")
            .accessibilityIdentifier("wumind.model.picker")

            Spacer(minLength: 4)

            HStack(spacing: 7) {
                Button {
                    Haptics.tap()
                    store.startNewConversation()
                    store.clearAttachments()
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
        store.activeModelDisplayName
    }

    // MARK: - Transcript / Welcome Canvas

    private var transcriptView: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if turns.isEmpty {
                        welcomeCanvas
                    } else {
                        if let convo = store.activeConversation,
                           let summary = convo.compactedSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !summary.isEmpty {
                            compactedMemoryCard(
                                conversationID: convo.id,
                                summary: summary,
                                compactedCount: max(1, convo.safeCompactedTurnCount)
                            )
                        }
                        if store.compactingContext {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("正在自动压缩早期上下文（保留最近对话 verbatim）…")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.indigo.opacity(0.22), lineWidth: 0.8)
                            )
                            .accessibilityIdentifier("wumind.context.compacting")
                        }
                        ForEach(turns) { turn in
                            if store.activeTurnID == turn.id {
                                WuMindStreamingTurnView(
                                    turn: turn,
                                    streamBuffer: store.streamBuffer,
                                    thinkingStartedAt: store.thinkingStartedAt,
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
                                    },
                                    onOpenWallet: {
                                        showingWallet = true
                                    }
                                )
                            } else {
                                WuMindTurnView(
                                    turn: turn,
                                    isLast: turn.id == turns.last?.id,
                                    isGenerating: false,
                                    thinkingStartedAt: nil,
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
                                    },
                                    onOpenWallet: {
                                        showingWallet = true
                                    }
                                )
                            }
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
            .simultaneousGesture(
                DragGesture(minimumDistance: 16).onChanged { value in
                    // Immediately pause auto-follow when user drags downward (reading earlier text)
                    if generatingInCurrentConversation && following && value.translation.height > 24 {
                        following = false
                    }
                }
            )
            .background {
                if generatingInCurrentConversation && following {
                    WuMindScrollFollower(streamBuffer: store.streamBuffer) {
                        scroller.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                }
            }
            .onChange(of: turns.last?.id) { _ in
                if following {
                    scroller.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if generatingInCurrentConversation {
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

    private func compactedMemoryCard(conversationID: UUID, summary: String, compactedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    compactedBannerExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("已自动压缩前 \(compactedCount) 轮历史上下文")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Claude 模式连续记忆 · 窗口上限 \(store.maxContextLabel) Tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: compactedBannerExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if compactedBannerExpanded {
                Divider()
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button {
                        copyText(summary)
                    } label: {
                        Label("复制压缩记忆", systemImage: "doc.on.doc")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.indigo)
                    Spacer()
                    Button {
                        Haptics.tap()
                        store.clearCompaction(conversationID: conversationID)
                        compactedBannerExpanded = false
                    } label: {
                        Label("恢复原始上下文", systemImage: "arrow.uturn.backward")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.indigo.opacity(0.26), lineWidth: 1)
        )
        .accessibilityIdentifier("wumind.context.compactedCard")
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
                    Text("1M 超长上下文 · Claude 式自动压缩 · 文件上传 · GitHub")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Dual-Channel Switcher: Own API vs WUMIND Managed Metered Channel
                HStack(spacing: 4) {
                    ForEach(WuMindChannel.allCases) { ch in
                        let active = store.channel == ch
                        Button {
                            dismissKeyboard()
                            Haptics.select()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                store.setChannel(ch)
                            }
                            if ch == .managed && store.hasGatewayURL {
                                Task { @MainActor in
                                    try? await store.syncManagedGatewayConfig()
                                    if Keychain.wumindGatewayUserToken != nil {
                                        try? await store.refreshManagedAccount()
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: ch == .managed ? "bolt.shield.fill" : "key.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(ch.title)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(active ? .white : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                active
                                    ? (ch == .managed ? Color.indigo : store.selectedProvider.brandColor)
                                    : Color.clear,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wumind.channel.\(ch.rawValue)")
                    }
                }
                .padding(3)
                .background(elevatedSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 1))
                .accessibilityIdentifier("wumind.channel.picker")
            }
            .padding(.top, 8)

            if store.channel == .managed {
                // WUMIND Managed Billing Balance & Usage Card
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.shield.fill")
                                    .foregroundStyle(.indigo)
                                Text("WUMIND 内置付费通道")
                                    .font(.subheadline.weight(.bold))
                            }
                            Text(store.managedAccountID.isEmpty
                                 ? "免自备 API Key · 按真实 Token 实时计费"
                                 : "账号 \(store.managedAccountID) · 余额与用量实时同步")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            dismissKeyboard()
                            Haptics.tap()
                            showingWallet = true
                        } label: {
                            Text("余额 / 用量 / 充值")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.indigo, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wumind.wallet.open")
                    }

                    // 3-Column Live Balance & Usage Strip
                    HStack(spacing: 8) {
                        managedMetricPill(
                            title: "当前余额",
                            value: store.managedBalanceYuan.map { String(format: "¥%.2f", $0) } ?? "¥0.00",
                            accent: .indigo
                        )
                        managedMetricPill(
                            title: "今日消费",
                            value: String(format: "¥%.4f", store.managedAccountStatus?.todaySpentYuan ?? 0),
                            accent: .orange
                        )
                        managedMetricPill(
                            title: "累计用量",
                            value: "\(WuMindAccountStatus.formatTokens(store.managedAccountStatus?.totalTokens ?? 0)) Tok",
                            accent: .teal
                        )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                        Haptics.tap()
                        showingWallet = true
                    }

                    if let model = store.activeManagedModel {
                        HStack(spacing: 8) {
                            Text("当前模型：\(model.displayName)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Text("输入 ¥\(String(format: "%.1f", model.inputPricePerMillion)) · 输出 ¥\(String(format: "%.1f", model.outputPricePerMillion)) / 百万")
                                .font(.caption2)
                                .foregroundStyle(.indigo)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(14)
                .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.indigo.opacity(0.28), lineWidth: 1))
                .accessibilityIdentifier("wumind.managed.card")
            } else {
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
            }

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

    private func managedMetricPill(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        if !store.pendingAttachments.isEmpty {
            return "针对已上传的 \(store.pendingAttachments.count) 个附件提问…"
        }
        if let repo = store.attachedGitHubContext {
            return "结合 \(repo.repo.fullName) 提问，或输入消息…"
        }
        if let skill = store.activeSkill {
            return "以「\(skill.name)」模式向 WUMIND 提问…"
        }
        return "向 WUMIND 提问，可上传 PDF / Word / 表格 / 图片或粘贴 GitHub 链接…"
    }

    private var compactComposerModelTitle: String {
        let name = headerModelTitle
        if name.count <= 13 { return name }
        return String(name.prefix(12)) + "…"
    }

    private var activeAccentColor: Color {
        store.channel == .managed ? .indigo : store.activeProviderForDisplay.brandColor
    }

    private var composerBar: some View {
        VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 10) {
                // Active Context & Uploaded File Chips (Attachments + Skill + GitHub Repo)
                if !store.pendingAttachments.isEmpty || importingAttachment
                    || store.activeSkill != nil || store.attachedGitHubContext != nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            if importingAttachment {
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.mini)
                                    Text("解析附件中…")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                            }

                            ForEach(store.pendingAttachments) { item in
                                HStack(spacing: 6) {
                                    Image(systemName: item.iconName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(item.tintColor)
                                    VStack(alignment: .leading, spacing: 0.5) {
                                        Text(item.document.filename)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .frame(maxWidth: 130, alignment: .leading)
                                        Text(item.document.summaryBadge)
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Button {
                                        Haptics.tap()
                                        store.removeAttachment(item.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary.opacity(0.75))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("移除附件 \(item.document.filename)")
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(item.tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(item.tintColor.opacity(0.25), lineWidth: 0.8)
                                )
                            }

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
                                .padding(.vertical, 6)
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
                                .padding(.vertical, 6)
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

                // Bottom Inline Controls Bar: Attach + Model/Channel Switcher + Thinking + Skills + GitHub + Toolbox + Send
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            // 📎 Direct File & Photo Attachment Menu
                            Menu {
                                Button {
                                    dismissKeyboard()
                                    showingFileImporter = true
                                } label: {
                                    Label("上传文件（PDF / Word / Excel / 代码）", systemImage: "doc.badge.plus")
                                }
                                Button {
                                    dismissKeyboard()
                                    showingPhotoPicker = true
                                } label: {
                                    Label("上传图片（相册 OCR 识字）", systemImage: "photo.on.rectangle")
                                }
                                Divider()
                                Button {
                                    dismissKeyboard()
                                    showingGitHub = true
                                } label: {
                                    Label("连接 GitHub 仓库", systemImage: "chevron.left.forwardslash.chevron.right")
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 12.5, weight: .semibold))
                                    if !store.pendingAttachments.isEmpty {
                                        Text("\(store.pendingAttachments.count)")
                                            .font(.caption2.weight(.bold))
                                    }
                                }
                                .foregroundStyle(store.pendingAttachments.isEmpty ? Color.primary : Color.white)
                                .padding(.horizontal, store.pendingAttachments.isEmpty ? 9 : 10)
                                .padding(.vertical, 7)
                                .background(
                                    store.pendingAttachments.isEmpty ? Color.secondary.opacity(0.13) : activeAccentColor,
                                    in: Capsule()
                                )
                            }
                            .disabled(generating || importingAttachment)
                            .accessibilityLabel("上传文件或图片")
                            .accessibilityIdentifier("wumind.attach.open")

                            // 1-Tap Inline Dual-Channel Model Switcher Menu directly below input
                            Menu {
                                // Channel Switcher at top
                                Button {
                                    Haptics.select()
                                    store.setChannel(store.channel == .managed ? .ownAPI : .managed)
                                } label: {
                                    Label(
                                        store.channel == .managed ? "切换为「自带 API」通道" : "切换为「WUMIND 内置」计费通道",
                                        systemImage: store.channel == .managed ? "key.fill" : "bolt.shield.fill"
                                    )
                                }
                                Divider()

                                if store.channel == .managed {
                                    ForEach(store.enabledManagedModels) { item in
                                        let active = store.activeManagedModel?.id == item.id
                                        Button {
                                            Haptics.select()
                                            store.selectManagedModel(item)
                                        } label: {
                                            let priceLabel = "\(item.displayName)（¥\(String(format: "%.0f", item.inputPricePerMillion))/¥\(String(format: "%.0f", item.outputPricePerMillion))）"
                                            if active {
                                                Label(priceLabel, systemImage: "checkmark")
                                            } else {
                                                Text(priceLabel)
                                            }
                                        }
                                    }
                                    Divider()
                                    Button {
                                        dismissKeyboard()
                                        showingWallet = true
                                    } label: {
                                        Label("钱包余额、扫码充值与完整价目表…", systemImage: "creditcard")
                                    }
                                } else {
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
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: store.channel == .managed ? "bolt.shield.fill" : store.activeProviderForDisplay.iconName)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(activeAccentColor)
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
                                .background(activeAccentColor.opacity(0.11), in: Capsule())
                                .overlay(Capsule().strokeBorder(activeAccentColor.opacity(0.25), lineWidth: 0.8))
                            }
                            .disabled(generating)
                            .accessibilityLabel("切换模型，当前 \(headerModelTitle)")
                            .accessibilityIdentifier("wumind.composer.model")

                            // Deep Thinking Toggle Pill
                            if store.activeSupportsDeepThinking {
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
                                            ? activeAccentColor
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

                            // 1M Context Window & Claude-Style Auto-Compaction Menu Pill
                            Menu {
                                if !generating {
                                    let plan = liveContextPlan
                                    let pct = Int((plan.usageRatio * 100).rounded())
                                    Text("当前上下文：\(WuMindAccountStatus.formatTokens(plan.estimatedTokens)) / \(store.maxContextLabel) Tokens（\(pct)%）")
                                    Divider()
                                }

                                Button {
                                    Haptics.select()
                                    store.setAutoCompactContext(!store.autoCompactContext)
                                } label: {
                                    Label(
                                        store.autoCompactContext ? "自动压缩上下文（已开启 · 80% 触发）" : "开启自动压缩上下文（Claude 模式）",
                                        systemImage: store.autoCompactContext ? "checkmark.circle.fill" : "circle"
                                    )
                                }

                                Menu {
                                    ForEach([1_000_000, 512_000, 256_000, 128_000], id: \.self) { cap in
                                        let label = cap >= 1_000_000 ? "1M Tokens（旗舰超长上下文）" : "\(cap / 1_000)K Tokens"
                                        Button {
                                            Haptics.select()
                                            store.setMaxContextTokens(cap)
                                        } label: {
                                            if store.maxContextTokens == cap {
                                                Label(label, systemImage: "checkmark")
                                            } else {
                                                Text(label)
                                            }
                                        }
                                    }
                                } label: {
                                    Label("上下文窗口上限：\(store.maxContextLabel)", systemImage: "slider.horizontal.3")
                                }

                                if canManualCompact {
                                    Divider()
                                    Button {
                                        dismissKeyboard()
                                        if let convoID = store.activeConversationID {
                                            store.triggerManualCompaction(conversationID: convoID)
                                        }
                                    } label: {
                                        Label("立即压缩当前上下文（/compact）", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                }
                            } label: {
                                let labelInfo: (text: String, tint: Color) = {
                                    if store.compactingContext { return ("压缩中…", .indigo) }
                                    if generating { return ("\(store.maxContextLabel) · 生成中", .indigo) }
                                    let plan = liveContextPlan
                                    let tint: Color = plan.usageRatio >= 0.80 ? .orange : (store.autoCompactContext ? .indigo : .secondary)
                                    return (contextPillLabel(for: plan), tint)
                                }()
                                HStack(spacing: 4) {
                                    Image(systemName: store.compactingContext ? "arrow.triangle.2.circlepath" : "memorychip")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(labelInfo.tint)
                                    Text(labelInfo.text)
                                        .font(.caption2.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .background(labelInfo.tint.opacity(0.11), in: Capsule())
                                .overlay(Capsule().strokeBorder(labelInfo.tint.opacity(0.24), lineWidth: 0.8))
                            }
                            .disabled(generating || store.compactingContext)
                            .accessibilityLabel("上下文窗口与自动压缩")
                            .accessibilityIdentifier("wumind.context.menu")

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
                        Button {
                            Haptics.tap()
                            store.stopGeneration()
                        } label: {
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
                                    canSend ? activeAccentColor : Color.secondary.opacity(0.20),
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
                    .strokeBorder(composerFocused ? activeAccentColor.opacity(0.60) : subtleBorder,
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
                    drawerActionRow(store.managedBalanceYuan.map { String(format: "WUMIND 钱包（¥%.2f）", $0) } ?? "WUMIND 钱包与充值",
                                    icon: "creditcard") {
                        drawerOpen = false
                        showingWallet = true
                    }
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
        let isStreamingHere = convo.id == store.activeGenerationConversationID && store.isGenerating
        return Button {
            dismissKeyboard()
            Haptics.tap()
            store.openConversation(convo.id)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                drawerOpen = false
            }
        } label: {
            HStack(spacing: 10) {
                if isStreamingHere {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 24)
                } else {
                    Image(systemName: convo.isPinned ? "pin.fill" : convo.provider.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(convo.isPinned ? .orange : convo.provider.brandColor)
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(convo.title)
                        .font(.subheadline.weight(active ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(isStreamingHere ? "正在后台生成…" : convo.modelDisplayName)
                            .foregroundStyle(isStreamingHere ? activeAccentColor : .secondary)
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

    // MARK: - Composer File & Photo Attachment Importers

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            ToastCenter.shared.show("未选择文件", style: .info)
        case .success(let urls):
            guard !urls.isEmpty else { return }
            importingAttachment = true
            Task { @MainActor in
                defer { importingAttachment = false }
                var addedCount = 0
                var lastError: String?
                for url in urls.prefix(4) {
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        let filename = url.lastPathComponent
                        let ext = url.pathExtension.lowercased()
                        let doc: WuMindAttachmentParser.ExtractedDocument
                        if ["png", "jpg", "jpeg", "heic", "webp"].contains(ext) {
                            doc = try await WuMindAttachmentHelper.extractImageAttachment(data: data, filename: filename)
                        } else {
                            doc = try WuMindAttachmentParser.extract(data: data, filename: filename)
                        }
                        store.addAttachment(doc)
                        addedCount += 1
                    } catch {
                        lastError = (error as? LocalizedError)?.errorDescription ?? "无法解析文件 \(url.lastPathComponent)"
                    }
                }
                if addedCount > 0 {
                    ToastCenter.shared.show("已附加 \(addedCount) 个文件", style: .success)
                } else if let lastError {
                    ToastCenter.shared.show(lastError, style: .error)
                }
            }
        }
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem) {
        importingAttachment = true
        Task { @MainActor in
            defer {
                importingAttachment = false
                pickedPhotoItem = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    ToastCenter.shared.show("未能读取所选图片", style: .error)
                    return
                }
                let stamp = Int(Date().timeIntervalSince1970) % 10_000
                let doc = try await WuMindAttachmentHelper.extractImageAttachment(data: data, filename: "图片_\(stamp).jpg")
                store.addAttachment(doc)
                ToastCenter.shared.show("已识别并附加图片内容", style: .success)
            } catch {
                ToastCenter.shared.show((error as? LocalizedError)?.errorDescription ?? "图片解析失败", style: .error)
            }
        }
    }

    // MARK: - Sending & Streaming Engine (Dual Channel + Attachments + Skills + GitHub)

    private func requestSend() {
        guard canSend else { return }
        dismissKeyboard()
        if store.channel == .managed {
            guard store.hasGatewayURL else {
                showingWallet = true
                return
            }
            beginRequest()
            return
        }
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

    // MARK: - 1M Context Engine & Claude-Style Auto-Compaction

    private var activeCompleteSnapshots: [WuMindContextEngine.TurnSnapshot] {
        (store.activeConversation?.turns ?? [])
            .filter { $0.state == .complete && !$0.answer.isEmpty }
            .map { WuMindContextEngine.TurnSnapshot(question: $0.question, answer: $0.answer) }
    }

    private var activeWindowTokenBudget: Int {
        let providerRaw = store.activeProviderForDisplay.rawValue
        let modelID = store.channel == .managed
            ? (store.activeManagedModel?.id ?? "deepseek-reasoner")
            : store.selectedModelID
        return WuMindContextEngine.supportedWindowTokens(
            provider: providerRaw,
            modelID: modelID,
            preferredCap: store.maxContextTokens
        )
    }

    private var liveContextPlan: WuMindContextEngine.ContextPlan {
        let convo = store.activeConversation
        let attachmentEstimate = store.pendingAttachments.reduce("") { $0 + $1.document.extractedText }
        let pendingText = cleanedDraft + (attachmentEstimate.isEmpty ? "" : "\n" + attachmentEstimate)
        return WuMindContextEngine.planContext(
            turns: activeCompleteSnapshots,
            existingSummary: convo?.compactedSummary,
            compactedTurnCount: convo?.safeCompactedTurnCount ?? 0,
            pendingPrompt: pendingText,
            systemPrompt: store.composedSystemPrompt(),
            maxWindowTokens: activeWindowTokenBudget
        )
    }

    private var canManualCompact: Bool {
        guard let convo = store.activeConversation else { return false }
        let snapshots = convo.turns
            .filter { $0.state == .complete && !$0.answer.isEmpty }
            .map { WuMindContextEngine.TurnSnapshot(question: $0.question, answer: $0.answer) }
        return WuMindContextEngine.planManualCompaction(
            turns: snapshots,
            compactedTurnCount: convo.safeCompactedTurnCount
        ) != nil
    }

    private func contextPillLabel(for plan: WuMindContextEngine.ContextPlan) -> String {
        if store.compactingContext { return "压缩中…" }
        if plan.estimatedTokens < 400 {
            return store.autoCompactContext ? "\(store.maxContextLabel) · 自动" : store.maxContextLabel
        }
        return "\(WuMindAccountStatus.formatTokens(plan.estimatedTokens))/\(store.maxContextLabel)"
    }

    private func beginRequest() {
        let userText = cleanedDraft
        let attachments = store.pendingAttachments
        guard !generating, (!userText.isEmpty || !attachments.isEmpty), userText.utf8.count <= questionLimit else { return }

        let displayQuestion = userText.isEmpty ? "请帮我精读并分析我上传的附件内容" : userText
        let attachmentContext = WuMindAttachmentParser.formatContext(for: attachments.map(\.document))
        let outgoingPrompt: String = {
            guard !attachmentContext.isEmpty else { return displayQuestion }
            return "\(attachmentContext)\n\n用户提问：\n\(displayQuestion)"
        }()
        let attachmentNames = attachments.isEmpty ? nil : attachments.map { $0.document.filename }
        let autoRepoName = store.attachedGitHubContext == nil ? WuMindGitHubClient.detectRepoInText(displayQuestion) : nil

        draft = ""
        store.clearAttachments()
        following = true

        store.startGeneration(
            displayQuestion: displayQuestion,
            outgoingPrompt: outgoingPrompt,
            attachmentNames: attachmentNames,
            autoRepoName: autoRepoName
        )
    }

    private func copyText(_ text: String) {
        UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
        ToastCenter.shared.show("已复制", style: .success)
    }
}

/// Isolated scroll follower observing ONLY `WuMindStreamBuffer.tick` at throttled cadence (~6 Hz)
/// so the parent `WuMindWorkspaceView` and previous turns never re-evaluate during streaming.
private struct WuMindScrollFollower: View {
    @ObservedObject var streamBuffer: WuMindStreamBuffer
    let onScrollToBottom: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: streamBuffer.tick) { tick in
                // Throttle auto-scroll to every 2nd coalesced flush (~160ms) to keep 60 FPS smooth scrolling
                if tick.isMultiple(of: 2) {
                    onScrollToBottom()
                }
            }
    }
}

/// Isolated streaming leaf view observing `WuMindStreamBuffer` so ONLY the active turn redraws at ~12.5 Hz.
private struct WuMindStreamingTurnView: View {
    let turn: WuMindTurn
    @ObservedObject var streamBuffer: WuMindStreamBuffer
    let thinkingStartedAt: Date?
    let elevatedSurface: Color
    let subtleBorder: Color
    let onCopy: (String) -> Void
    let onRetryPrompt: (String) -> Void
    let onRegenerate: () -> Void
    let onManageKey: () -> Void
    let onOpenWallet: () -> Void

    var body: some View {
        var liveTurn = turn
        if !streamBuffer.reasoning.isEmpty {
            liveTurn.reasoning = streamBuffer.reasoning
        }
        if let sec = streamBuffer.reasoningSeconds {
            liveTurn.reasoningSeconds = sec
        }
        if !streamBuffer.answer.isEmpty {
            liveTurn.answer = streamBuffer.answer
        }
        return WuMindTurnView(
            turn: liveTurn,
            isLast: true,
            isGenerating: true,
            thinkingStartedAt: thinkingStartedAt,
            elevatedSurface: elevatedSurface,
            subtleBorder: subtleBorder,
            onCopy: onCopy,
            onRetryPrompt: onRetryPrompt,
            onRegenerate: onRegenerate,
            onManageKey: onManageKey,
            onOpenWallet: onOpenWallet
        )
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
    let onOpenWallet: () -> Void

    @State private var thinkingExpanded = true

    private var isCurrentlyThinking: Bool {
        isGenerating && turn.answer.isEmpty && (turn.isDeepThinking || !turn.reasoning.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // User prompt pill (with uploaded attachment badges if any)
            HStack {
                Spacer(minLength: 44)
                VStack(alignment: .trailing, spacing: 6) {
                    if let names = turn.attachmentNames, !names.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(names, id: \.self) { name in
                                Label(name, systemImage: "paperclip")
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(elevatedSurface, in: Capsule())
                                    .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 0.8))
                            }
                        }
                    }
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
                        isStreaming: isGenerating,
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
                    VStack(alignment: .leading, spacing: 6) {
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

                        if let cost = turn.costYuan {
                            let inTok = turn.promptTokens ?? 0
                            let outTok = (turn.completionTokens ?? 0) + (turn.reasoningTokens ?? 0)
                            Button(action: onOpenWallet) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.system(size: 9.5))
                                    Text("输入 \(WuMindAccountStatus.formatTokens(inTok)) · 输出 \(WuMindAccountStatus.formatTokens(outTok)) · 扣费 ¥\(String(format: "%.4f", cost)) · 查看余额")
                                        .font(.caption2.monospacedDigit())
                                }
                                .foregroundStyle(.indigo.opacity(0.9))
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
                            if message.contains("余额不足") || message.contains("充值") || message.contains("网关") {
                                Button("立即扫码充值 / 兑换码", action: onOpenWallet)
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.borderedProminent)
                                    .tint(.indigo)
                            } else if message.contains("Key") || message.contains("密钥") || message.contains("余额") {
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
                        } else if isGenerating {
                            // Fast-path during streaming: avoid expensive UITextView selection geometry churn
                            Text(turn.reasoning)
                                .font(.system(size: 13.5))
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
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

// MARK: - Rich Markdown & Styled Code Block Renderer (60 FPS Streaming Fast-Path + Batched Rich Path)

private struct WuMindMarkdownView: View {
    let text: String
    let isStreaming: Bool
    let elevatedSurface: Color
    let subtleBorder: Color
    let onCopyCode: (String) -> Void

    private struct Block: Identifiable {
        let id: Int
        let language: String?
        let content: String
    }

    private enum RichSegmentKind {
        case divider
        case heading(level: Int, text: String)
        case quote(String)
        case bullet(String)
        case paragraph(String)
    }

    private struct RichSegment: Identifiable {
        let id: Int
        let kind: RichSegmentKind
    }

    var body: some View {
        let blocks = parseBlocks(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                if let lang = block.language {
                    codeCard(language: lang, code: block.content, selectable: !isStreaming)
                } else if isStreaming {
                    streamingProseView(block.content)
                } else {
                    richProseView(block.content)
                }
            }
        }
    }

    private func codeCard(language: String, code: String, selectable: Bool) -> some View {
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
                if selectable {
                    Text(code)
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Text(code)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(12)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Zero-jank streaming renderer: groups text into ~1,200-char chunks using native `Text` without
    /// running O(N^2) `AttributedString(markdown:)` or `textSelection` layout on every incoming delta.
    private func streamingProseView(_ raw: String) -> some View {
        let chunks = chunkForStreaming(raw)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                Text(chunk)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Completed-message rich renderer: batches consecutive plain lines into paragraphs so even
    /// 10,000+ word responses stay smooth while preserving headings, bullets, quotes, and inline Markdown.
    private func richProseView(_ raw: String) -> some View {
        let segments = parseRichSegments(raw)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                switch segment.kind {
                case .divider:
                    Divider().padding(.vertical, 4)
                case .heading(let level, let headingText):
                    markdownText(headingText)
                        .font(level == 1 ? .title2.bold() : (level == 2 ? .title3.bold() : .headline))
                        .padding(.top, level == 3 ? 4 : 6)
                case .quote(let quoteText):
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.4)).frame(width: 3)
                        markdownText(quoteText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                case .bullet(let bulletText):
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        markdownText(bulletText)
                            .font(.body)
                            .lineSpacing(4)
                    }
                case .paragraph(let bodyText):
                    markdownText(bodyText)
                        .font(.body)
                        .lineSpacing(4)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chunkForStreaming(_ source: String) -> [String] {
        let paragraphs = source.components(separatedBy: "\n\n")
        var result: [String] = []
        var buffer = ""
        for para in paragraphs {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !buffer.isEmpty && buffer.count + trimmed.count > 1_200 {
                result.append(buffer)
                buffer = trimmed
            } else {
                buffer = buffer.isEmpty ? trimmed : (buffer + "\n\n" + trimmed)
            }
        }
        if !buffer.isEmpty {
            result.append(buffer)
        }
        return result.isEmpty ? [source] : result
    }

    private func parseRichSegments(_ raw: String) -> [RichSegment] {
        var segments: [RichSegment] = []
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: "\n")
            paragraphBuffer.removeAll(keepingCapacity: true)
            segments.append(RichSegment(id: segments.count, kind: .paragraph(joined)))
        }

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
            } else if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                segments.append(RichSegment(id: segments.count, kind: .divider))
            } else if trimmed.hasPrefix("### ") {
                flushParagraph()
                segments.append(RichSegment(id: segments.count, kind: .heading(level: 3, text: String(trimmed.dropFirst(4)))))
            } else if trimmed.hasPrefix("## ") {
                flushParagraph()
                segments.append(RichSegment(id: segments.count, kind: .heading(level: 2, text: String(trimmed.dropFirst(3)))))
            } else if trimmed.hasPrefix("# ") {
                flushParagraph()
                segments.append(RichSegment(id: segments.count, kind: .heading(level: 1, text: String(trimmed.dropFirst(2)))))
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                segments.append(RichSegment(id: segments.count, kind: .quote(String(trimmed.dropFirst(2)))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                segments.append(RichSegment(id: segments.count, kind: .bullet(String(trimmed.dropFirst(2)))))
            } else {
                paragraphBuffer.append(line)
            }
        }
        flushParagraph()
        return segments
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

