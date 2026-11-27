import Combine
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Isolated composer draft container held as a non-observed reference by `WuMindWorkspaceView`
/// and observed ONLY by `WuMindIsolatedComposerBar`, so typing NEVER invalidates the chat transcript
/// or re-parses historical Markdown turns on every keystroke.
@MainActor
private final class WuMindComposerDraftState: ObservableObject {
    @Published var text: String = ""

    private let storageKey = "wumind.unsentDraft.v1"
    private var persistTask: Task<Void, Never>?

    var cleaned: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setText(_ newText: String) {
        guard text != newText else { return }
        text = newText
        schedulePersist()
    }

    func clear() {
        persistTask?.cancel()
        persistTask = nil
        if !text.isEmpty {
            text = ""
        }
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func restoreIfEmpty() {
        guard text.isEmpty,
              let saved = UserDefaults.standard.string(forKey: storageKey),
              !saved.isEmpty else { return }
        text = saved
    }

    func schedulePersist() {
        persistTask?.cancel()
        let snapshot = text
        let key = storageKey
        persistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            if snapshot.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(snapshot, forKey: key)
            }
        }
    }

    func flushPersist() {
        persistTask?.cancel()
        persistTask = nil
        if text.isEmpty {
            UserDefaults.standard.removeObject(forKey: storageKey)
        } else {
            UserDefaults.standard.set(text, forKey: storageKey)
        }
    }
}



/// Flagship multi-model AI aggregator workspace ("WUMIND").
/// Presented full-screen without the bottom duty tab bar; supports dual channels
/// (Own API Keys vs WUMIND Managed Real-Time Metered Gateway), file & photo uploads,
/// Skills center, direct GitHub repository context, persistent local session history,
/// and live collapsible chain-of-thought reasoning.
struct WuMindWorkspaceView: View {
    @ObservedObject private var store = WuMindStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    var onClose: (() -> Void)? = nil
    var onReturnHome: (() -> Void)? = nil
    var isStandaloneFullScreen: Bool = false
    var onHideDutyMode: (() -> Void)? = nil
    var onRestoreDutyMode: (() -> Void)? = nil

    // Non-observed reference: ONLY WuMindIsolatedComposerBar observes draftState.text,
    // preventing per-keystroke full-view & transcript re-renders!
    @State private var draftState = WuMindComposerDraftState()
    @State private var drawerOpen = false
    @State private var drawerSearch = ""
    @State private var includeArchivedInSearch = false
    @State private var showingArchivedSheet = false
    @State private var archiveUndoTarget: (id: UUID, title: String)? = nil
    @State private var archiveUndoTask: Task<Void, Never>? = nil
    @State private var showingModelHub = false
    @State private var showingSkills = false
    @State private var showingGitHub = false
    @State private var showingWallet = false
    @State private var showingProjects = false
    @State private var showingSchedules = false
    @State private var showingSettings = false
    @State private var showingSync = false
    @State private var showingInChatConnectors = false
    @State private var showingGeminiVoice = false
    @State private var showingRealtimeCall = false
    @State private var showingCamera = false
    @State private var showingMyWorks = false
    @State private var regNameDraft = ""
    @State private var fetchingChatCatalog = false
    @State private var regBusy = false
    @State private var regError: String? = nil
    @State private var isTemporaryChat = false
    @State private var temporaryTurns: [WuMindTurn] = []
    @State private var temporaryGenerating = false
    @State private var temporaryTask: Task<Void, Never>? = nil
    @State private var temporaryElapsedSeconds: Int = 1
    @State private var temporaryClockTask: Task<Void, Never>? = nil
    @State private var showingFileImporter = false
    @State private var showingPhotoPicker = false
    @State private var pickedPhotoItem: PhotosPickerItem? = nil
    @State private var importingAttachment = false
    @State private var keyAfterModelHub: WuMindProvider?
    @State private var showingKeyFor: WuMindProvider?
    @State private var keyEditorService: AICompatibleChatService?
    @State private var confirmingClearAll = false
    @State private var confirmingTemporaryOfflineSend = false
    @State private var renamingConversation: WuMindConversation?
    @State private var renameDraft = ""

    @StateObject private var dictation = WuMindDictationController()
    @State private var dictationSeed = ""

    @State private var scrollFollow = WuMindScrollFollowState()
    @State private var compactedBannerExpanded = false
    @State private var comparingTurn: WuMindTurn? = nil
    @State private var openModelHubAfterComparison = false
    @State private var showingSharedMaterialsSheet = false

    @State private var toolboxPath: [ToolboxDestination] = []
    @State private var selectedMainTab: WuMindMainTab = .chat
    @State private var selectedChatBuild: WuMindChatBuild?
    @State private var showChatBuildConfirmation = false
    @State private var chatBuildMediaRoute: WuMindChatBuildService.MediaRoute?
    @State private var footageConversationID: UUID?
    @State private var footageSource: WuMindFootageSource?
    @State private var chatBuildPreview: WuMindLocalWork?
    @State private var editAfterPreview: ToolboxDestination?
    @State private var chatVideoStage: String?
    @State private var showVideoStageFixture = false
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

    enum WuMindMainTab: String, CaseIterable, Identifiable {
        case chat = "对话"
        case workbench = "工作台"
        case works = "作品"
        var id: String { rawValue }
        var iconName: String {
            switch self {
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .workbench: return "square.grid.2x2.fill"
            case .works: return "square.stack.3d.up.fill"
            }
        }
        var accessibilityID: String {
            switch self {
            case .chat: return "wumind.tab.chat"
            case .workbench: return "wumind.tab.workbench"
            case .works: return "wumind.tab.works"
            }
        }
    }

    enum ToolboxDestination: String, Identifiable, Hashable {
        case hub, live, image, video, spatial3d, agentOS, ppt, speech, code, work, tender
        var id: String { rawValue }
    }

    private func searchContinuationBanner(_ prompt: WuMindStore.SearchContinuationPrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("联网搜索未完成", systemImage: "wifi.exclamationmark")
                .font(.subheadline.weight(.semibold))
            Text(prompt.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if prompt.gatewayAction != nil {
                Button("改用网关搜索") {
                    store.resolveSearchContinuation(turnID: prompt.turnID, choice: .tryGateway)
                }
                .accessibilityIdentifier("wumind.webSearch.tryGateway")
            }
            HStack {
                Button("不联网继续") {
                    store.resolveSearchContinuation(turnID: prompt.turnID, choice: .continueOffline)
                }
                .accessibilityIdentifier("wumind.webSearch.continueOffline")
                Button("停止", role: .cancel) {
                    store.resolveSearchContinuation(turnID: prompt.turnID, choice: .cancel)
                }
                .accessibilityIdentifier("wumind.webSearch.cancel")
            }
        }
        .buttonStyle(.bordered)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10))
        .accessibilityIdentifier("wumind.webSearch.continuation")
    }

    private func dismissKeyboard() {
        composerFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func openTool(_ destination: ToolboxDestination) {
        dismissKeyboard()
        toolboxPath.append(destination)
    }

    private func selectChatBuild(_ tool: WuMindChatBuild?) {
        guard !generating, !isTemporaryChat else {
            ToastCenter.shared.show("请先结束当前任务或退出临时聊天。", style: .info)
            return
        }
        selectedChatBuild = tool
        chatBuildMediaRoute = nil
        selectedMainTab = .chat
        if tool != nil { composerFocused = true }
    }

    private func launchWorkbenchTool(_ destination: ToolboxDestination) {
        switch destination {
        case .image: selectChatBuild(.image)
        case .video: selectChatBuild(.video)
        case .code: selectChatBuild(.code)
        case .ppt: selectChatBuild(.ppt)
        case .spatial3d: selectChatBuild(.spatial3d)
        case .tender: selectChatBuild(.tender)
        default: openTool(destination)
        }
    }

    private func chatBuildCard(id: String) -> some View {
        WuMindInlineBuildCard(workID: id, onPreview: { chatBuildPreview = $0 }, onVideoStage: { chatVideoStage = id })
    }

    private var turns: [WuMindTurn] {
        isTemporaryChat ? temporaryTurns : (store.activeConversation?.turns ?? [])
    }
    private var generating: Bool {
        isTemporaryChat ? temporaryGenerating : store.isGenerating
    }
    private var generatingInCurrentConversation: Bool {
        if isTemporaryChat { return temporaryGenerating }
        return store.isGenerating && store.activeGenerationConversationID == store.activeConversationID
    }
    private var cleanedDraft: String { draftState.cleaned }
    private var canSend: Bool {
        !generating
            && !fetchingChatCatalog
            && !importingAttachment
            && (!cleanedDraft.isEmpty || !store.pendingAttachments.isEmpty)
            && cleanedDraft.utf8.count <= questionLimit
    }

    private var canvasBackground: Color { DS.Palette.background }
    private var elevatedSurface: Color { DS.Palette.cardSurface }
    private var subtleBorder: Color { DS.Palette.hairline }

    var body: some View {
        NavigationStack(path: $toolboxPath) {
            ZStack(alignment: .leading) {
                VStack(spacing: 0) {
                    topBar
                    #if DEBUG
                    if AppStore.isDemo, ProcessInfo.processInfo.arguments.contains("-wumind-stream-qa") {
                        Button(store.streamBenchmarkResult.isEmpty ? "开始离线流样例" : store.streamBenchmarkResult) {
                            store.startStreamBenchmark(batched: ProcessInfo.processInfo.arguments.contains("-wumind-batched-baseline"))
                        }.accessibilityIdentifier("wumind.qa.stream")
                        if WuMindStore.longHistoryQA {
                            WuMindHistoryStreamProgress(buffer: store.streamBuffer)
                        }
                    }
                    #endif
                    upstreamBalanceNoticeBanner
                    if selectedMainTab == .chat {
                        if let prompt = store.searchContinuationPrompt,
                           !isTemporaryChat,
                           store.activeGenerationConversationID == store.activeConversationID {
                            searchContinuationBanner(prompt)
                        }
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
                        if isTemporaryChat {
                            HStack(spacing: 8) {
                                Image(systemName: "eye.slash.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.orange)
                                Text("临时聊天模式 · 不保存历史记录，不读写长期记忆")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Button("退出") {
                                    Haptics.tap()
                                    exitTemporaryChat()
                                }
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.11))
                            .overlay(
                                Rectangle()
                                    .frame(height: 0.7)
                                    .foregroundStyle(Color.orange.opacity(0.28)),
                                alignment: .bottom
                            )
                            .accessibilityIdentifier("wumind.tempChat.banner")
                        }
                        transcriptView
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                VStack(spacing: 0) {
                                    if let source = footageSource {
                                        HStack {
                                            Label(source.filename, systemImage: "film").lineLimit(1)
                                            Spacer()
                                            Button("移除素材") { footageSource = nil }
                                        }.font(.caption).padding(.horizontal)
                                    }
                                    composerBar
                                }
                            }
                    } else if selectedMainTab == .workbench {
                        WuMindWorkbenchView(
                            store: store,
                            elevatedSurface: elevatedSurface,
                            subtleBorder: subtleBorder,
                            onOpenTool: openTool,
                            onOpenProjects: { showingProjects = true },
                            onOpenSchedules: { showingSchedules = true },
                            onOpenSkills: { showingSkills = true },
                            onOpenInChatConnectors: { showingInChatConnectors = true },
                            onOpenWallet: { showingWallet = true },
                            onOpenModelHub: { showingModelHub = true },
                            onOpenSettings: { showingSettings = true },
                            onSwitchToWorks: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                    selectedMainTab = .works
                                }
                            },
                            onStartDeepResearch: {
                                if let skill = store.allSkills.first(where: { $0.id == "builtin.deep_research" }) {
                                    store.selectSkill(skill)
                                }
                                store.webSearchEnabled = true
                                store.agentModeEnabled = true
                                selectedChatBuild = nil
                                selectedMainTab = .chat
                                composerFocused = true
                                ToastCenter.shared.show("已开启「联网深度调研」模式", style: .success)
                            }
                        )
                    } else {
                        WuMindWorksView(
                            initialFilter: nil,
                            isEmbedded: true,
                            onReopenPPT: { deck, workID in
                                WuMindPPTWorkflowStore.shared.loadExternalDeck(deck, workID: workID)
                                openTool(.ppt)
                            },
                            onReopenScene3D: { json, workID in
                                WuMindSpatial3DStore.shared.openProjectJSON(json, linkedWorkID: workID)
                                openTool(.spatial3d)
                            },
                            onRetryWork: { failed in
                                switch failed.workType {
                                case .image: openTool(.image)
                                case .video: openTool(.video)
                                case .ppt: openTool(.ppt)
                                case .scene3d: openTool(.spatial3d)
                                case .document: openTool(.tender)
                                case .code: openTool(.code)
                                }
                            }
                        )
                    }
                    if !composerFocused || selectedMainTab != .chat {
                        mainTabSwitcherBar
                    }
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

                // Mandatory WUMIND user registration gate for ALL users (internal duty staff & external users alike)
                if store.requiresWuMindRegistration {
                    mandatoryRegistrationOverlay
                        .zIndex(5)
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
            .observeTabRootNavigationDepth(tabID: "ext.wumind")
            .onChange(of: toolboxPath.count) { count in
                AppTabBarVisibility.shared.setTabPushed(count > 0, for: "ext.wumind")
            }
            .navigationDestination(for: ToolboxDestination.self) { dest in
                dest.page
                .toolbar(.visible, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .background(
            Color.clear
                .photosPicker(isPresented: $showingPhotoPicker, selection: $pickedPhotoItem, matching: .images)
        )
        .onChange(of: store.currentStorageOwnerID) { _ in footageSource = nil; chatBuildMediaRoute = nil }
        .onChange(of: store.activeConversationID) { id in
            if id != footageConversationID { footageSource = nil }
        }
        .onChange(of: isTemporaryChat) { _ in footageSource = nil }
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
        .sheet(isPresented: $showingInChatConnectors) {
            WuMindInChatConnectorsSheet(
                store: store,
                onPickPhoto: {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        showingPhotoPicker = true
                    }
                },
                onTakePhoto: {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showingCamera = true
                        } else {
                            ToastCenter.shared.show("当前设备不支持相机，已为你打开相册图片", style: .error)
                            showingPhotoPicker = true
                        }
                    }
                },
                onPickFile: {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        showingFileImporter = true
                    }
                },
                onOpenFullGitHub: {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        showingGitHub = true
                    }
                },
                onOpenCustomizations: {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        showingSkills = true
                    }
                },
                onOpenTool: { dest in
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        launchWorkbenchTool(dest)
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                handleCapturedCameraImage(image)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingGeminiVoice) {
            WuMindGeminiVoiceView(
                isTemporaryChat: isTemporaryChat,
                onCommitExchange: { q, a in
                    store.appendCompletedVoiceExchange(question: q, answer: a)
                }
            )
        }
        .fullScreenCover(isPresented: $showingRealtimeCall) {
            AILiveCallView(autoConnectOnAppear: true) {
                showingRealtimeCall = false
            }
        }
        .sheet(item: $comparingTurn, onDismiss: {
            if openModelHubAfterComparison {
                openModelHubAfterComparison = false
                showingModelHub = true
            }
        }) { turn in
            if let cid = store.activeConversationID {
                WuMindCompareTurnSheet(
                    store: store,
                    conversationID: cid,
                    turn: turn,
                    onOpenModelHub: {
                        openModelHubAfterComparison = true
                        comparingTurn = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingSharedMaterialsSheet) {
            if let convo = store.activeConversation {
                WuMindSharedMaterialsSheet(store: store, conversation: convo)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingModelHub, onDismiss: {
            if let provider = keyAfterModelHub {
                keyAfterModelHub = nil
                showingKeyFor = provider
            }
        }) {
            WuMindModelHubSheet(
                store: store,
                onEditKey: { provider, service in
                    keyEditorService = service
                    keyAfterModelHub = provider
                    showingModelHub = false
                },
                onOpenTool: { dest in
                    showingModelHub = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 240_000_000)
                        openTool(dest)
                    }
                },
                onOpenWallet: {
                    showingModelHub = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 240_000_000)
                        showingWallet = true
                    }
                }
            )
        }
        .sheet(isPresented: $showingSkills) {
            WuMindCustomizationsSheet(store: store) {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    showingGitHub = true
                }
            }
        }
        .sheet(isPresented: $showingProjects) {
            WuMindProjectsSheet(store: store)
        }
        .sheet(isPresented: $showingSchedules) {
            WuMindSchedulesSheet(store: store)
        }
        .sheet(isPresented: $showingSettings) {
            WuMindSettingsSheet(
                store: store,
                onOpenWallet: {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        showingWallet = true
                    }
                },
                onOpenCustomizations: {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        showingSkills = true
                    }
                },
                onOpenProjects: {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        showingProjects = true
                    }
                },
                onOpenSchedules: {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        showingSchedules = true
                    }
                },
                onOpenModelHub: {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        showingModelHub = true
                    }
                },
                onOpenSync: {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        showingSync = true
                    }
                }
            )
        }
        .sheet(isPresented: $showingSync) {
            WuMindSyncSheet(store: store)
        }
        .sheet(isPresented: $showingGitHub) {
            WuMindGitHubSheet(store: store)
        }
        .sheet(isPresented: $showingWallet) {
            WuMindWalletSheet(store: store)
        }
        .sheet(item: $showingKeyFor, onDismiss: {
            keyEditorService = nil
            store.objectWillChange.send()
        }) { provider in
            if provider == .deepSeek {
                DeepSeekPlanKeyView(onSaved: {
                    if store.channel == .ownAPI { store.selectProvider(.deepSeek) }
                })
            } else if let mp = provider.multiProvider {
                ProviderKeyView(provider: mp, initialService: keyEditorService) { configured in
                    if configured && store.channel == .ownAPI {
                        store.selectProvider(provider)
                    } else if !configured {
                        store.cachedModels[provider] = []
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
        .fullScreenCover(isPresented: Binding(
            get: { chatVideoStage != nil || showVideoStageFixture },
            set: { if !$0 { chatVideoStage = nil; showVideoStageFixture = false } }
        )) {
            if let workID = chatVideoStage {
                WuMindChatVideoStage(workID: workID)
            } else if showVideoStageFixture {
                WuMindVideoGenerationStage(
                    prompt: "东北农村带前后院子，镜头从稻田掠过。", isRunning: true,
                    progress: 15, asset: nil, notice: nil, onStop: {}
                )
            }
        }
        .sheet(item: $chatBuildPreview, onDismiss: {
            if let destination = editAfterPreview {
                editAfterPreview = nil
                openTool(destination)
            }
        }) { work in
            WuMindChatArtifactPreview(work: work, onReopenPPT: { deck, id in
                WuMindPPTWorkflowStore.shared.loadExternalDeck(deck, workID: id)
                editAfterPreview = .ppt
                chatBuildPreview = nil
            }, onReopenScene3D: { json, id in
                WuMindSpatial3DStore.shared.openProjectJSON(json, linkedWorkID: id)
                editAfterPreview = .spatial3d
                chatBuildPreview = nil
            })
        }
        .alert("开始生成作品？", isPresented: $showChatBuildConfirmation) {
            Button("生成") { beginRequest() }
            Button("取消", role: .cancel) {
                selectedChatBuild = nil
                chatBuildMediaRoute = nil
            }
        } message: {
            if case .footage = chatBuildMediaRoute {
                Text("将在本机用原始素材生成新的 MP4，可在对话中预览或分享。")
            } else {
                Text("将使用 \(chatBuildMediaRoute?.confirmation ?? headerModelTitle)，可能按该通道计费。完成后在这条对话预览，也可在「作品」找到。")
            }
        }
        .alert("临时聊天不执行联网搜索", isPresented: $confirmingTemporaryOfflineSend) {
            Button("不联网继续") { requestSend(temporaryOfflineApproved: true) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出临时聊天后可使用联网搜索，或继续接受不联网的回答。")
        }
        .confirmationDialog("清空所有 WUMIND 历史对话？", isPresented: $confirmingClearAll, titleVisibility: .visible) {
            Button("清空全部历史", role: .destructive) {
                store.stopGeneration()
                store.deleteAllConversations()
            }
        } message: {
            Text("此操作只删除本机聊天记录，不会影响 API Key 或值班数据。")
        }
        .sheet(isPresented: $showingMyWorks) {
            myWorksSheetContent
        }
        .sheet(isPresented: $showingArchivedSheet) {
            WuMindArchivedConversationsSheet(
                store: store,
                onOpenConversation: { convoID in
                    store.openConversation(convoID)
                    selectedMainTab = .chat
                    showingArchivedSheet = false
                    drawerOpen = false
                }
            )
        }
        .overlay(alignment: .bottom) {
            if let undo = archiveUndoTarget {
                HStack(spacing: 10) {
                    Image(systemName: "archivebox.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("已归档「\(undo.title)」")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Button("撤销") {
                        Haptics.tap()
                        undoArchive(undo.id)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 0.56, green: 0.78, blue: 1.0))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wumind.archive.undo")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.12, green: 0.14, blue: 0.19).opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 6)
                .padding(.horizontal, 18)
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("wumind.archive.undoBanner")
            }
        }
        .onAppear(perform: handleWorkspaceAppear)
        .task(id: scenePhase) {
            guard scenePhase == .active, !AppStore.isDemo else { return }
            await store.reconcileBackgroundTasks()
        }
        .onDisappear {
            // Leaving the screen does not cancel store-owned tasks. iOS can still suspend the process.
            dictation.stop()
            dismissKeyboard()
            store.flushSave()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deepseek.chat")
    }

    @ViewBuilder
    private var upstreamBalanceNoticeBanner: some View {
        if let upstreamNotice = store.lastUpstreamBalanceNotice {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text(upstreamNotice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("知道了") {
                    store.lastUpstreamBalanceNotice = nil
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.11))
            .accessibilityIdentifier("wumind.upstreamBalanceNotice")
        }
    }

    private var myWorksSheetContent: some View {
        WuMindWorksView(
            initialFilter: nil,
            onReopenPPT: { deck, workID in
                WuMindPPTWorkflowStore.shared.loadExternalDeck(deck, workID: workID)
                openTool(.ppt)
            },
            onReopenScene3D: { json, workID in
                WuMindSpatial3DStore.shared.openProjectJSON(json, linkedWorkID: workID)
                openTool(.spatial3d)
            }
        )
    }

    private func handleWorkspaceAppear() {
        #if DEBUG
        if WuMindStore.longHistoryQA || WuMindChatPageReview.enabled { return }
        if AppStore.isDemo, ProcessInfo.processInfo.arguments.contains("-wumind-code-preview-qa"), chatBuildPreview == nil {
            let works = WuMindWorksStore.shared
            let sample = works.recordSubmittedTask(workType: .code, title: "计数器", prompt: "生成计数器", modelID: "fixture", syncToCloud: false)
            let page = #"<html><body><button onclick="this.textContent='计数 1'">计数 0</button></body></html>"#
            chatBuildPreview = works.completeWork(id: sample.id, assetData: Data(("<!doctype html>" + page).utf8),
                                                 assetMime: "text/html", assetExtension: "html", syncToCloud: false)
            return
        }
        if AppStore.isDemo, ProcessInfo.processInfo.arguments.contains("-wumind-video-stage-qa") {
            showVideoStageFixture = true
        }
        if AppStore.isDemo, ProcessInfo.processInfo.arguments.contains("-wumind-transcript-qa"),
           temporaryTurns.isEmpty {
            isTemporaryChat = true
            let detail = Array(repeating: "长回复测试段落，使用固定文字，不发出任何模型请求。", count: 45).joined(separator: "\n\n")
            let preview = """
            预览已生成。地图支持缩放，点击不同区域可以查看公开数据。

            - 向下滑动查看更多内容。
            - 键盘 `1–6` 切换指标，`Esc` 取消选择。
            """
            temporaryTurns = [WuMindTurn(
                question: "检查对话折叠", reasoning: "此文本只用于验证思考折叠。",
                reasoningSeconds: 3, answer: preview + "\n\n## 示例详情\n\n" + detail,
                modelLabel: "WuMind 界面样例", provider: .deepSeek, isDeepThinking: true, state: .complete
            )]
            return
        }
        #endif
        if regNameDraft.isEmpty {
            let candidate = AppAccountManager.shared.externalProfile?.nickname
                ?? AppStore.shared.myRosterName
                ?? ""
            if !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                regNameDraft = candidate
            }
        }
        draftState.restoreIfEmpty()
        if store.channel == .managed && store.hasGatewayURL {
            Task { @MainActor in
                try? await store.syncManagedGatewayConfig()
                if WuMindStore.shared.managedSessionToken != nil {
                    try? await store.refreshManagedAccount()
                }
            }
        }
    }

    // MARK: - Mandatory WUMIND User Registration Gate (Internal Duty + External Users Alike)

    private var mandatoryRegistrationOverlay: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text("创建 WuMind 账号").font(DS.Font.title)
                Text("用昵称保存个人作品和账单。")
                    .font(DS.Font.body)
                    .foregroundStyle(.secondary)
                TextField("姓名或常用昵称", text: $regNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.nickname)
                    .submitLabel(.done)
                    .accessibilityIdentifier("wumind.registration.nameInput")
                if let regError { AppErrorBannerCard(message: regError) }
                AppPrimaryCTA(title: "注册并进入 WuMind", isLoading: regBusy,
                              isDisabled: regNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    submitMandatoryRegistration()
                }
                .accessibilityIdentifier("wumind.registration.submit")
                if let onReturnHome {
                    Button("返回首页", action: onReturnHome)
                        .accessibilityIdentifier("wumind.registration.backHome")
                } else if let onClose {
                    Button("返回上一页", action: onClose)
                }
            }
            .frame(maxWidth: 480, alignment: .leading)
            .padding(DS.Space.l)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(canvasBackground.ignoresSafeArea())
        .accessibilityIdentifier("wumind.registration.gate")
    }

    private func submitMandatoryRegistration() {
        let name = regNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        regBusy = true
        regError = nil
        dismissKeyboard()
        Task { @MainActor in
            defer { regBusy = false }
            do {
                _ = try await store.registerWuMindUser(displayName: name)
                if store.hasGatewayURL {
                    ToastCenter.shared.show("已登录 WuMind", style: .success)
                    if store.channel == .managed { try? await store.syncManagedGatewayConfig() }
                } else {
                    ToastCenter.shared.show("本机资料已保存。内置服务尚未配置，请联系管理员。", style: .info)
                }
            } catch {
                regError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Top Header Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            if let onReturnHome {
                Button {
                    dismissKeyboard()
                    Haptics.tap()
                    draftState.flushPersist()
                    store.flushSave()
                    onReturnHome()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("首页").font(DS.Font.callout)
                    }
                    .foregroundStyle(.primary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回首页")
                .accessibilityIdentifier("wumind.backToHome")
            }

            Button {
                dismissKeyboard()
                Haptics.tap()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    drawerOpen.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("历史对话侧边栏")
            .accessibilityIdentifier("wumind.sidebar.open")

            Spacer(minLength: 2)

            Button {
                dismissKeyboard()
                Haptics.tap()
                showingModelHub = true
            } label: {
                ViewThatFits(in: .horizontal) {
                    headerPickerLabel(showModel: true)
                    headerPickerLabel(showModel: false)
                    Text("WUMIND")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 5)
                }
                .frame(minHeight: 44)
                .contentShape(Capsule())
                .background(elevatedSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(generating)
            .accessibilityLabel("切换模型，当前 \(headerModelTitle)")
            .accessibilityIdentifier("wumind.model.picker")

            Spacer(minLength: 4)

            HStack(spacing: 0) {
                Button {
                    dismissKeyboard()
                    Haptics.select()
                    if isTemporaryChat {
                        exitTemporaryChat()
                    } else {
                        enterTemporaryChat()
                    }
                    selectedMainTab = .chat
                } label: {
                    Image(systemName: isTemporaryChat ? "eye.slash.fill" : "eye.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isTemporaryChat ? DS.Palette.warning : .primary)
                        .frame(width: 44, height: 44)
                            .contentShape(Rectangle())

                }
                .buttonStyle(.plain)
                .disabled(generating)
                .accessibilityLabel(isTemporaryChat ? "退出临时聊天" : "开启临时聊天")
                .accessibilityIdentifier("wumind.tempChat.toggle")

                Button {
                    Haptics.tap()
                    if isTemporaryChat {
                        temporaryTask?.cancel()
                        temporaryClockTask?.cancel()
                        temporaryGenerating = false
                        temporaryTurns = []
                    } else {
                        store.startNewConversation()
                    }
                    store.clearAttachments()
                    draftState.clear()
                    selectedMainTab = .chat
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建对话")
                .accessibilityIdentifier("wumind.chat.new")

                if !turns.isEmpty && selectedMainTab == .chat {
                    Button {
                        dismissKeyboard()
                        Haptics.tap()
                        if isTemporaryChat {
                            exitTemporaryChat()
                        } else {
                            store.flushSave()
                            store.startNewConversation()
                        }
                        store.clearAttachments()
                        draftState.clear()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回 WUMIND 主页")
                    .accessibilityIdentifier("wumind.chat.backHome")
                } else if let onClose {
                    Button {
                        dismissKeyboard()
                        Haptics.tap()
                        store.flushSave()
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回值班首页")
                    .accessibilityIdentifier("wumind.close")
                }
            }
        }
        .padding(.horizontal, DS.Space.xs)
        .padding(.vertical, DS.Space.xxs)
        .background(canvasBackground)
    }

    private var mainTabSwitcherBar: some View {
        HStack(spacing: 0) {
            ForEach(WuMindMainTab.allCases) { tab in
                let active = selectedMainTab == tab
                Button {
                    dismissKeyboard()
                    Haptics.select()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedMainTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 17, weight: .medium))
                        Text(tab.rawValue)
                            .font(.caption2.weight(active ? .semibold : .regular))
                    }
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
                .accessibilityIdentifier(tab.accessibilityID)
            }
        }
        .frame(maxWidth: 470)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            Rectangle().fill(subtleBorder).frame(height: 1)
        }
    }

    private func headerPickerLabel(showModel: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: store.channel == .managed ? "bolt.shield.fill" : store.activeProviderForDisplay.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(store.channel == .managed ? Color.indigo : store.activeProviderForDisplay.brandColor)
            Text("WUMIND")
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if showModel {
                Text("· \(compactHeaderModelName)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, showModel ? 13 : 8)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var headerModelTitle: String {
        store.activeModelDisplayName
    }

    private var compactHeaderModelName: String {
        let name = headerModelTitle
        if name.count <= 14 { return name }
        return String(name.prefix(13)) + "…"
    }

    // MARK: - Transcript / Welcome Canvas

    private var usesBaselineStreamPresentation: Bool {
        #if DEBUG
        return store.streamBenchmark?.batchedBaseline == true
        #else
        return false
        #endif
    }

    private var transcriptView: some View {
        GeometryReader { viewportGeo in
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if turns.isEmpty {
                            welcomeCanvas
                                .frame(minHeight: max(0, viewportGeo.size.height - 44))
                        } else {
                            if !isTemporaryChat,
                               let convo = store.activeConversation,
                               let summary = convo.compactedSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !summary.isEmpty {
                                compactedMemoryCard(
                                    conversationID: convo.id,
                                    summary: summary,
                                    compactedCount: max(1, convo.safeCompactedTurnCount)
                                )
                            }
                            if !isTemporaryChat && store.compactingContext {
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
                                        baseline: usesBaselineStreamPresentation,
                                        streamSmoothMode: store.preferences.streamSmoothMode,
                                        thinkingStartedAt: store.thinkingStartedAt,
                                        elevatedSurface: elevatedSurface,
                                        subtleBorder: subtleBorder,
                                        onCopy: copyText,
                                        onRetryPrompt: { prompt in
                                            draftState.setText(prompt)
                                            composerFocused = true
                                        },
                                        onRegenerate: {
                                            guard !generating else { return }
                                            draftState.setText(turn.question)
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
                                    let canRecover = !isTemporaryChat && (turn.clientRequestID?.isEmpty == false)
                                    WuMindTurnView(
                                        turn: turn,
                                        isLast: turn.id == turns.last?.id,
                                        isGenerating: turn.state == .generating,
                                        liveElapsedSeconds: isTemporaryChat ? temporaryElapsedSeconds : 1,
                                        thinkingStartedAt: nil,
                                        elevatedSurface: elevatedSurface,
                                        subtleBorder: subtleBorder,
                                        onCopy: copyText,
                                        onRetryPrompt: { prompt in
                                            draftState.setText(prompt)
                                            composerFocused = true
                                        },
                                        onRegenerate: {
                                            guard !generating else { return }
                                            draftState.setText(turn.question)
                                            requestSend()
                                        },
                                        onManageKey: {
                                            showingKeyFor = turn.provider
                                        },
                                        onOpenWallet: {
                                            showingWallet = true
                                        },
                                        onCompare: isTemporaryChat ? nil : {
                                            dismissKeyboard()
                                            comparingTurn = turn
                                        },
                                        onAdoptComparison: { compID in
                                            if let cid = store.activeConversationID {
                                                store.adoptComparison(conversationID: cid, turnID: turn.id, comparisonID: compID)
                                                Haptics.success()
                                                ToastCenter.shared.show("已标记采纳该复核版本", style: .success)
                                            }
                                        },
                                        onRecoverTask: canRecover ? {
                                            guard let cid = store.activeConversationID else { return }
                                            Task { @MainActor in
                                                let msg = await store.recoverInterruptedTurn(conversationID: cid, turnID: turn.id)
                                                ToastCenter.shared.show(msg, style: msg.contains("恢复") ? .success : .info)
                                            }
                                        } : nil
                                    )
                                    .equatable()
                                }
                                if let workID = turn.chatBuildWorkID { chatBuildCard(id: workID) }
                            }
                        }
                        Group {
                            #if DEBUG
                            if WuMindStore.longHistoryQA {
                                Text("离线样本末尾").font(.caption)
                                    .accessibilityIdentifier("wumind.qa.historyBottom")
                            } else {
                                Color.clear.frame(height: 8)
                            }
                            #else
                            Color.clear.frame(height: 8)
                            #endif
                        }
                        .id(bottomAnchor)
                    }
                    .background {
                        if generatingInCurrentConversation && scrollFollow.shouldAutoScrollOnStreamTick {
                            WuMindScrollFollower(
                                streamBuffer: store.streamBuffer,
                                viewportHeight: viewportGeo.size.height,
                                baseline: usesBaselineStreamPresentation
                            ) { needsScroll in
                                guard scrollFollow.shouldAutoScrollOnStreamTick else { return }
                                #if DEBUG
                                store.streamBenchmark?.recordFollowCheck(requestedScroll: needsScroll)
                                #endif
                                guard needsScroll else { return }
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) { scroller.scrollTo(bottomAnchor, anchor: .bottom) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: WuMindScrollFollower.viewport)
                .accessibilityIdentifier("wumind.transcript.scroll")
                .scrollDismissesKeyboard(.immediately)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    if composerFocused {
                        dismissKeyboard()
                    }
                })
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8).onChanged { value in
                        let dy = value.translation.height
                        guard dy > abs(value.translation.width) else { return }
                        var next = scrollFollow
                        next.handleUserDrag(translationY: Double(dy), isGenerating: generatingInCurrentConversation)
                        if next != scrollFollow { scrollFollow = next }
                    }
                )
                .onChange(of: turns.last?.id) { _ in
                    if scrollFollow.shouldAutoScrollOnStreamTick {
                        scroller.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if generatingInCurrentConversation {
                        Button {
                            if scrollFollow.shouldAutoScrollOnStreamTick {
                                scrollFollow.pauseFollow()
                            } else {
                                scrollFollow.jumpToLatest()
                                scroller.scrollTo(bottomAnchor, anchor: .bottom)
                            }
                        } label: {
                            Label(scrollFollow.shouldAutoScrollOnStreamTick ? "暂停滚动" : "回到最新",
                                  systemImage: scrollFollow.shouldAutoScrollOnStreamTick ? "pause.fill" : "arrow.down")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(elevatedSurface, in: Capsule())
                                .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wumind.scroll.followToggle")
                        .padding(.trailing, 16)
                        .padding(.bottom, 10)
                    }
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
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Spacer(minLength: DS.Space.l)
            Text(isTemporaryChat ? "临时聊天" : "今天想聊点什么？")
                .font(DS.Font.display)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("wumind.chat.greeting")

            if !isTemporaryChat {
                if !AppAccountManager.shared.isExternalRestricted && !isStandaloneFullScreen {
                    welcomeSuggestion("查今天的值班", icon: "calendar", id: "wumind.starter.dutyToday") {
                        draftState.setText("今天谁值班、哪组休息、谁请假或出差？")
                        composerFocused = true
                    }
                } else {
                    welcomeSuggestion("联网查资料", icon: "globe", id: "wumind.starter.webResearch") {
                        store.webSearchEnabled = true
                        draftState.setText("请帮我联网查证并整理最新进展，标注原文来源：")
                        composerFocused = true
                    }
                }
            }
            Spacer(minLength: DS.Space.l)
        }
        .padding(.horizontal, DS.Space.xs)
        .frame(maxWidth: DS.readableWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func welcomeSuggestion(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .foregroundStyle(.primary)
                Image(systemName: "arrow.turn.down.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: - Flagship Multi-Model Capsule Composer

    private var composerPlaceholder: String {
        if footageSource != nil { return "例：删除第 2 到 5 秒，字幕改为「到达现场」" }
        if let tool = selectedChatBuild, !isTemporaryChat { return tool.promptPlaceholder }
        if !store.pendingAttachments.isEmpty {
            return "针对已上传的 \(store.pendingAttachments.count) 个附件提问…"
        }
        if let proj = store.activeProject {
            return "向「\(proj.name)」提问…"
        }
        if let repo = store.attachedGitHubContext {
            return "结合 \(repo.repo.fullName) 提问，或输入消息…"
        }
        if let skill = store.activeSkill {
            return "以「\(skill.name)」模式向 WUMIND 提问…"
        }
        return "问 WuMind，或描述想构建的作品"
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
        WuMindIsolatedComposerBar(
            draftState: draftState,
            store: store,
            dictation: dictation,
            placeholder: composerPlaceholder,
            activeAccentColor: activeAccentColor,
            elevatedSurface: elevatedSurface,
            subtleBorder: subtleBorder,
            colorScheme: colorScheme,
            generating: generating,
            importingAttachment: importingAttachment,
            isTemporaryChat: isTemporaryChat,
            canManualCompact: canManualCompact,
            baseContextTokens: baseContextEstimatedTokens,
            windowTokenBudget: activeWindowTokenBudget,
            questionLimit: questionLimit,
            compactModelTitle: compactComposerModelTitle,
            headerModelTitle: headerModelTitle,
            composerFocused: $composerFocused,
            selectedBuild: isTemporaryChat ? nil : selectedChatBuild,
            onSelectBuild: selectChatBuild,
            onOpenProjects: {
                dismissKeyboard()
                showingProjects = true
            },
            onOpenSkills: {
                dismissKeyboard()
                Haptics.tap()
                showingSkills = true
            },
            onOpenGitHub: {
                dismissKeyboard()
                showingGitHub = true
            },
            onOpenSharedMaterials: {
                dismissKeyboard()
                showingSharedMaterialsSheet = true
            },
            onOpenConnectors: {
                dismissKeyboard()
                Haptics.tap()
                showingInChatConnectors = true
            },
            onOpenModelHub: {
                dismissKeyboard()
                Haptics.tap()
                showingModelHub = true
            },
            onManualCompact: {
                dismissKeyboard()
                if let convoID = store.activeConversationID {
                    store.triggerManualCompaction(conversationID: convoID)
                }
            },
            onDismissKeyboard: {
                Haptics.tap()
                dismissKeyboard()
            },
            onOpenVoiceInput: {
                dismissKeyboard()
                Haptics.tap()
                showingGeminiVoice = true
            },
            onOpenRealtimeVoice: {
                dismissKeyboard()
                Haptics.tap()
                showingRealtimeCall = true
            },
            onStop: {
                Haptics.tap()
                if isTemporaryChat {
                    temporaryTask?.cancel()
                    temporaryClockTask?.cancel()
                    temporaryGenerating = false
                } else {
                    store.stopGeneration()
                }
            },
            onSend: { requestSend() }
        )
    }

    // MARK: - Slide-Over History Sidebar Drawer

    private var historyDrawer: some View {
        GeometryReader { geo in
            let drawerWidth = min(316, geo.size.width * 0.84)
            VStack(spacing: 0) {
                // Drawer Header with ⋯ -> 已归档 menu and New Chat
                HStack(spacing: DS.Space.xs) {
                    Text("对话历史")
                        .font(DS.Font.headline)
                    Spacer()
                    Menu {
                        Button {
                            Haptics.tap()
                            showingArchivedSheet = true
                        } label: {
                            Label("已归档（\(store.archivedConversations.count)）", systemImage: "archivebox")
                        }
                        .accessibilityIdentifier("wumind.history.archivedEntry")

                        Toggle(isOn: $includeArchivedInSearch) {
                            Label("搜索时包含已归档", systemImage: "magnifyingglass")
                        }

                        if !store.conversations.isEmpty {
                            Divider()
                            Button(role: .destructive) {
                                confirmingClearAll = true
                            } label: {
                                Label("清空全部历史", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("历史更多操作")
                    .accessibilityIdentifier("wumind.history.moreMenu")

                    Button {
                        Haptics.tap()
                        store.startNewConversation()
                        draftState.clear()
                        selectedMainTab = .chat
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            drawerOpen = false
                        }
                    } label: {
                        Label("新对话", systemImage: "square.and.pencil")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(DS.Palette.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(DS.Palette.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

                // Search bar + optional "包含已归档" filter toggle (default OFF)
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("搜索历史对话", text: $drawerSearch)
                            .font(.subheadline)
                            .accessibilityIdentifier("wumind.history.search")
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

                    if !drawerSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.archivedConversations.isEmpty {
                        HStack(spacing: 8) {
                            Button {
                                Haptics.select()
                                includeArchivedInSearch.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: includeArchivedInSearch ? "checkmark.circle.fill" : "circle")
                                        .font(.caption2.weight(.semibold))
                                    Text("包含已归档")
                                        .font(.caption2.weight(.semibold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    includeArchivedInSearch
                                        ? Color.indigo.opacity(0.16)
                                        : Color.secondary.opacity(0.10),
                                    in: Capsule()
                                )
                                .foregroundStyle(includeArchivedInSearch ? Color.indigo : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(includeArchivedInSearch ? .isSelected : [])
                            .accessibilityIdentifier("wumind.history.includeArchived")

                            Spacer()

                            if !store.archivedConversations.isEmpty {
                                Button {
                                    Haptics.tap()
                                    showingArchivedSheet = true
                                } label: {
                                    Label("已归档 \(store.archivedConversations.count)", systemImage: "archivebox")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("wumind.history.archivedQuickLink")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                Divider()

                // Conversation List with native left-swipe & long-press Archive
                let filtered = filteredConversations
                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text(drawerSearch.isEmpty ? "暂无历史对话" : "未找到匹配的对话")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if !drawerSearch.isEmpty && !includeArchivedInSearch && !store.archivedConversations.isEmpty {
                            Button("包含已归档继续搜索") {
                                includeArchivedInSearch = true
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.indigo)
                            .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 40)
                } else {
                    let pinned = filtered.filter { !$0.isArchived && $0.isPinned }
                    let recent = filtered.filter { !$0.isArchived && !$0.isPinned }
                    let archivedHits = filtered.filter(\.isArchived)
                    List {
                        if !pinned.isEmpty {
                            Section {
                                ForEach(pinned) { convo in
                                    drawerConversationRow(convo)
                                }
                            } header: {
                                Text("置顶对话")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !recent.isEmpty {
                            Section {
                                ForEach(recent) { convo in
                                    drawerConversationRow(convo)
                                }
                            } header: {
                                if !pinned.isEmpty || !archivedHits.isEmpty {
                                    Text("最近对话")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if !archivedHits.isEmpty {
                            Section {
                                ForEach(archivedHits) { convo in
                                    drawerConversationRow(convo)
                                }
                            } header: {
                                Text("已归档匹配")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.indigo)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.immediately)
                }

                Divider()

                // Drawer Footer Shortcuts (Flagship App Sidebar Structure)
                VStack(spacing: 3) {
                    drawerActionRow(
                        store.activeProject.map { "项目：\($0.name)" } ?? "项目空间（\(store.projects.count)）",
                        icon: "folder.fill"
                    ) {
                        drawerOpen = false
                        showingProjects = true
                    }
                    drawerActionRow(
                        "定制中心（\(store.installedConnectorIDs.count) 插件 · Skills）",
                        icon: "puzzlepiece.extension.fill"
                    ) {
                        drawerOpen = false
                        showingSkills = true
                    }
                    drawerActionRow(
                        "定时任务（\(store.scheduledTasks.filter(\.enabled).count) 运行中）",
                        icon: "clock.arrow.circlepath"
                    ) {
                        drawerOpen = false
                        showingSchedules = true
                    }
                    drawerActionRow(
                        store.managedBalanceYuan.map { String(format: "WUMIND 钱包（¥%.2f）", $0) } ?? "WUMIND 钱包与用量",
                        icon: "creditcard"
                    ) {
                        drawerOpen = false
                        showingWallet = true
                    }
                    drawerActionRow("跨设备加密同步（iPhone ↔ iPad）", icon: "icloud.and.arrow.up.fill") {
                        drawerOpen = false
                        showingSync = true
                    }
                    drawerActionRow("WUMIND 设置与长期记忆", icon: "gearshape.fill") {
                        drawerOpen = false
                        showingSettings = true
                    }
                    drawerActionRow("模型与 API Key 中心", icon: "key") {
                        drawerOpen = false
                        showingModelHub = true
                    }
                    if isStandaloneFullScreen, let onRestoreDutyMode {
                        Divider().padding(.vertical, 3)
                        drawerActionRow("恢复显示值班界面", icon: "calendar.badge.clock") {
                            drawerOpen = false
                            store.flushSave()
                            onRestoreDutyMode()
                        }
                        .accessibilityIdentifier("wumind.restoreDutyMode")
                    } else if let onClose {
                        Divider().padding(.vertical, 3)
                        if let onHideDutyMode {
                            drawerActionRow("隐藏值班界面（全屏纯享）", icon: "eye.slash.circle") {
                                drawerOpen = false
                                store.flushSave()
                                onHideDutyMode()
                            }
                            .accessibilityIdentifier("wumind.hideDutyMode")
                        }
                        drawerActionRow("返回值班 App 主页", icon: "arrow.uturn.left.circle") {
                            drawerOpen = false
                            store.flushSave()
                            onClose()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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

    private func performArchive(_ convo: WuMindConversation) {
        Haptics.tap()
        _ = store.archiveConversation(convo.id)
        archiveUndoTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            archiveUndoTarget = (id: convo.id, title: convo.title)
        }
        archiveUndoTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                if archiveUndoTarget?.id == convo.id {
                    archiveUndoTarget = nil
                }
            }
        }
    }

    private func undoArchive(_ id: UUID) {
        archiveUndoTask?.cancel()
        archiveUndoTask = nil
        _ = store.unarchiveConversation(id)
        withAnimation(.easeOut(duration: 0.2)) {
            archiveUndoTarget = nil
        }
        ToastCenter.shared.show("已撤销归档，对话已恢复", style: .success)
    }

    private var filteredConversations: [WuMindConversation] {
        let q = drawerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return store.activeConversations
        }
        let pool = includeArchivedInSearch ? store.sortedConversations : store.activeConversations
        return pool.filter { convo in
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
            selectedMainTab = .chat
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
                    Image(systemName: convo.isArchived ? "archivebox.fill" : (convo.isPinned ? "pin.fill" : convo.provider.iconName))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(convo.isArchived ? .indigo : (convo.isPinned ? .orange : convo.provider.brandColor))
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(convo.title)
                            .font(.subheadline.weight(active ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if convo.isArchived {
                            Text("已归档")
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.indigo.opacity(0.15), in: Capsule())
                                .foregroundStyle(.indigo)
                        }
                    }
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
            .padding(.vertical, 8)
            .background(
                active ? convo.provider.brandColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if convo.isArchived {
                Button {
                    _ = store.unarchiveConversation(convo.id)
                    ToastCenter.shared.show("已取消归档，已恢复至原位置", style: .success)
                } label: {
                    Label("取消归档", systemImage: "tray.and.arrow.up")
                }
                .tint(.indigo)
            } else {
                Button {
                    performArchive(convo)
                } label: {
                    Label("归档", systemImage: "archivebox")
                }
                .tint(.indigo)
            }
        }
        .contextMenu {
            if !convo.isArchived {
                Button {
                    store.togglePin(convo.id)
                } label: {
                    Label(convo.isPinned ? "取消置顶" : "置顶对话", systemImage: convo.isPinned ? "pin.slash" : "pin")
                }
            }
            Button {
                renameDraft = convo.title
                renamingConversation = convo
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            if convo.isArchived {
                Button {
                    _ = store.unarchiveConversation(convo.id)
                    ToastCenter.shared.show("已取消归档，已恢复至原位置", style: .success)
                } label: {
                    Label("取消归档", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button {
                    performArchive(convo)
                } label: {
                    Label("归档", systemImage: "archivebox")
                }
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
            let movieTypes = ["mov", "mp4", "m4v"]
            let owner = store.currentStorageOwnerID
            let conversation = store.activeConversationID
            if urls.contains(where: { movieTypes.contains($0.pathExtension.lowercased()) }) {
                guard urls.count == 1, !isTemporaryChat, store.pendingAttachments.isEmpty, let url = urls.first else {
                    ToastCenter.shared.show("请在普通对话中单独选择一个视频文件。", style: .info)
                    return
                }
                importingAttachment = true
                Task { @MainActor in
                    defer { importingAttachment = false }
                    do {
                        let source = try await Task.detached(priority: .userInitiated) {
                            let granted = url.startAccessingSecurityScopedResource()
                            defer { if granted { url.stopAccessingSecurityScopedResource() } }
                            return try WuMindFootageSource(copying: url)
                        }.value
                        guard store.currentStorageOwnerID == owner, store.activeConversationID == conversation, !isTemporaryChat else { return }
                        footageConversationID = conversation
                        footageSource = source
                        selectedChatBuild = nil
                    } catch { ToastCenter.shared.show("未能读取视频素材。", style: .error) }
                }
                return
            }
            importingAttachment = true
            Task { @MainActor in
                defer { importingAttachment = false }
                var addedCount = 0
                var lastError: String?
                for url in urls.prefix(4) {
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try await Task.detached(priority: .userInitiated) {
                            let file = try FileHandle(forReadingFrom: url)
                            defer { try? file.close() }
                            let limit = WuMindAttachmentParser.maxFileBytes
                            let data = try file.read(upToCount: limit + 1) ?? Data()
                            guard data.count <= limit else { throw WuMindAttachmentParser.ParseError.fileTooLarge }
                            return data
                        }.value
                        let filename = url.lastPathComponent
                        let ext = url.pathExtension.lowercased()
                        let doc: WuMindAttachmentParser.ExtractedDocument
                        if ["png", "jpg", "jpeg", "heic", "webp"].contains(ext) {
                            doc = try await WuMindAttachmentHelper.extractImageAttachment(data: data, filename: filename)
                        } else {
                            doc = try await Task.detached(priority: .userInitiated) {
                                try WuMindAttachmentParser.extract(data: data, filename: filename)
                            }.value
                        }
                        guard store.currentStorageOwnerID == owner, store.activeConversationID == conversation else { return }
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

    private func handleCapturedCameraImage(_ image: UIImage) {
        importingAttachment = true
        Task { @MainActor in
            defer {
                importingAttachment = false
            }
            do {
                guard let jpeg = image.jpegData(compressionQuality: 0.86) else {
                    ToastCenter.shared.show("未能编码拍照图片", style: .error)
                    return
                }
                let stamp = Int(Date().timeIntervalSince1970) % 10_000
                let doc = try await WuMindAttachmentHelper.extractImageAttachment(data: jpeg, filename: "拍照_\(stamp).jpg")
                store.addAttachment(doc)
                ToastCenter.shared.show("已拍照并附加识图内容", style: .success)
            } catch {
                ToastCenter.shared.show((error as? LocalizedError)?.errorDescription ?? "拍照图片解析失败", style: .error)
            }
        }
    }

    // MARK: - Sending & Streaming Engine (Dual Channel + Attachments + Skills + GitHub)

    private func requestSend(temporaryOfflineApproved: Bool = false) {
        guard canSend else { return }
        dismissKeyboard()
        if let source = footageSource {
            guard store.pendingAttachments.isEmpty, let edit = WuMindFootageEdit(instruction: cleanedDraft) else {
                ToastCenter.shared.show("请单独使用视频素材，例如：删除第 2 到 5 秒，字幕改为「到达现场」。", style: .info)
                return
            }
            selectedChatBuild = .video
            chatBuildMediaRoute = .footage(source, edit)
            showChatBuildConfirmation = true
            return
        }
        // Local intranet Duty queries run 100% on-device with zero external LLM calls,
        // so they must work immediately regardless of API key / gateway / active model configuration.
        if store.pendingAttachments.isEmpty,
           WuMindDutyQueryEngine.classifyIntent(
               prompt: cleanedDraft,
               timezoneID: Calendar.app.timeZone.identifier,
               knownPeople: Array(AppStore.shared.roster.keys)
           ) != nil {
            selectedChatBuild = nil
            beginRequest()
            return
        }
        if isTemporaryChat && store.webSearchEnabled && !temporaryOfflineApproved {
            confirmingTemporaryOfflineSend = true
            return
        }
        let requestedBuild = isTemporaryChat ? nil : (selectedChatBuild ?? WuMindChatBuild.detectRequest(cleanedDraft))
        if let tool = requestedBuild, tool == .image || tool == .video {
            let attachments = store.pendingAttachments
            if cleanedDraft.isEmpty || attachments.count > 1 || attachments.contains(where: { $0.document.makeAIImageAttachment() == nil }) {
                ToastCenter.shared.show("请填写描述。对话生图最多支持一张参考图片。", style: .info)
                return
            }
            do {
                chatBuildMediaRoute = try WuMindChatBuildService.mediaRoute(for: tool, using: store, hasReference: !attachments.isEmpty, prompt: cleanedDraft)
                selectedChatBuild = tool
                showChatBuildConfirmation = true
            } catch {
                ToastCenter.shared.show(error.localizedDescription, style: .warning)
            }
            return
        }
        if store.channel == .managed {
            guard store.hasGatewayURL else {
                ToastCenter.shared.show("此版本尚未配置 WuMind 内置服务，请联系管理员。", style: .warning)
                return
            }
            guard store.activeManagedModel != nil else {
                let draft = cleanedDraft
                let attachments = store.pendingAttachments.map(\.id)
                let owner = store.currentStorageOwnerID
                let conversation = store.activeConversationID
                fetchingChatCatalog = true
                Task { @MainActor in
                    do {
                        try await store.syncManagedGatewayConfig()
                        fetchingChatCatalog = false
                        guard store.channel == .managed, store.currentStorageOwnerID == owner,
                              store.activeConversationID == conversation, cleanedDraft == draft,
                              store.pendingAttachments.map(\.id) == attachments else { return }
                        if store.activeManagedModel != nil {
                            requestSend(temporaryOfflineApproved: temporaryOfflineApproved)
                        } else if store.enabledManagedModels.isEmpty {
                            ToastCenter.shared.show("内置服务暂未提供可用的对话模型，请联系管理员。", style: .warning)
                        } else {
                            ToastCenter.shared.show("原模型当前不可用，请从列表选择模型。", style: .info)
                            showingModelHub = true
                        }
                    } catch {
                        fetchingChatCatalog = false
                        ToastCenter.shared.show(error.localizedDescription, style: .warning)
                    }
                }
                return
            }
            selectedChatBuild = requestedBuild
            if requestedBuild != nil { showChatBuildConfirmation = true }
            else { beginRequest() }
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
        selectedChatBuild = requestedBuild
        if requestedBuild != nil { showChatBuildConfirmation = true }
        else { beginRequest() }
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

    /// Pre-computed history + attachment token estimate independent of live typing draft,
    /// so `WuMindIsolatedComposerBar` can add draft tokens in O(1) without re-evaluating parent body.
    private var baseContextEstimatedTokens: Int {
        let convo = store.activeConversation
        let attachmentEstimate = store.pendingAttachments.reduce("") { $0 + $1.document.extractedText }
        return WuMindContextEngine.planContext(
            turns: activeCompleteSnapshots,
            existingSummary: convo?.compactedSummary,
            compactedTurnCount: convo?.safeCompactedTurnCount ?? 0,
            pendingPrompt: attachmentEstimate,
            systemPrompt: store.composedSystemPrompt(),
            maxWindowTokens: activeWindowTokenBudget
        ).estimatedTokens
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

    private func enterTemporaryChat() {
        selectedChatBuild = nil
        temporaryTask?.cancel()
        temporaryClockTask?.cancel()
        temporaryGenerating = false
        temporaryElapsedSeconds = 1
        temporaryTurns = []
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            isTemporaryChat = true
        }
        ToastCenter.shared.show("已进入临时聊天（不记录历史、不读写记忆）", style: .success)
    }

    private func exitTemporaryChat() {
        temporaryTask?.cancel()
        temporaryClockTask?.cancel()
        temporaryGenerating = false
        temporaryElapsedSeconds = 1
        temporaryTurns = []
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            isTemporaryChat = false
        }
    }

    private func beginRequest() {
        let sendStarted = Date()
        dictation.stop()
        let userText = cleanedDraft
        let attachments = store.pendingAttachments
        guard !generating, (!userText.isEmpty || !attachments.isEmpty), userText.utf8.count <= questionLimit else { return }

        let displayQuestion = userText.isEmpty ? "请帮我精读并分析我上传的附件内容" : userText
        let prepStarted = ProcessInfo.processInfo.systemUptime
        let attachmentContext = WuMindDocumentChunker.formatGroundedContext(
            query: displayQuestion,
            documents: attachments.map(\.document)
        )
        let outgoingPrompt: String = {
            guard !attachmentContext.isEmpty else { return displayQuestion }
            return "\(attachmentContext)\n\n用户提问：\n\(displayQuestion)"
        }()
        let attachmentNames = attachments.isEmpty ? nil : attachments.map { $0.document.filename }
        let imageAttachments = attachments.compactMap { $0.document.makeAIImageAttachment() }
        let attachmentPrepMs = attachments.isEmpty ? 0 : Int((ProcessInfo.processInfo.systemUptime - prepStarted) * 1000)
        let autoRepoName = store.attachedGitHubContext == nil ? WuMindGitHubClient.detectRepoInText(displayQuestion) : nil

        if let tool = selectedChatBuild, !isTemporaryChat {
            guard store.startChatBuild(tool, question: displayQuestion, prompt: outgoingPrompt,
                                       attachments: attachments, mediaRoute: chatBuildMediaRoute) else { return }
            if case .footage = chatBuildMediaRoute { footageConversationID = store.activeConversationID }
            if tool == .video { chatVideoStage = store.activeConversation?.turns.last?.chatBuildWorkID }
            chatBuildMediaRoute = nil
            selectedChatBuild = nil
            draftState.clear()
            store.clearAttachments()
            scrollFollow.jumpToLatest()
            return
        }

        draftState.clear()
        store.clearAttachments()
        scrollFollow.jumpToLatest()

        if isTemporaryChat {
            beginTemporaryRequest(
                displayQuestion: displayQuestion,
                outgoingPrompt: outgoingPrompt,
                attachmentNames: attachmentNames,
                imageAttachments: imageAttachments
            )
            return
        }

        if !attachments.isEmpty {
            store.archiveAttachmentsToActiveConversation(attachments, initialPrompt: displayQuestion)
        }

        store.startGeneration(
            displayQuestion: displayQuestion,
            outgoingPrompt: outgoingPrompt,
            attachmentNames: attachmentNames,
            imageAttachments: imageAttachments,
            autoRepoName: autoRepoName, sendTriggeredAt: sendStarted, attachmentPrepMs: attachmentPrepMs
        )
    }

    /// Runs strictly in-memory temporary conversation turns without ever saving to disk,
    /// conversation history, cloud sync, or long-term memories.
    private func beginTemporaryRequest(
        displayQuestion: String,
        outgoingPrompt: String,
        attachmentNames: [String]?,
        imageAttachments: [AIProviderMessage.ImageAttachment]
    ) {
        let turnID = UUID()
        let provider = store.activeProviderForDisplay
        let isDeep = store.deepThinking && store.activeSupportsDeepThinking
        let modelLabel = "\(headerModelTitle) · 临时"
        let resolvedModelID = store.channel == .managed
            ? (store.activeManagedModel?.id ?? store.managedSelectedModelID)
            : store.selectedModelID
        let ownIsRelay: Bool = {
            guard store.channel == .ownAPI, let mp = provider.multiProvider else { return false }
            return ((try? AIProvider.normalizedBaseURL(AIProviderEndpoints.baseURL(for: mp))) ?? nil) != nil
        }()

        var priorMessages: [AIProviderMessage] = []
        for t in temporaryTurns where t.state == .complete && !t.answer.isEmpty {
            priorMessages.append(AIProviderMessage(role: .user, text: t.question))
            priorMessages.append(AIProviderMessage(role: .assistant, text: t.answer))
        }
        priorMessages.append(AIProviderMessage(role: .user, text: outgoingPrompt, images: imageAttachments))

        let turn = WuMindTurn(
            id: turnID,
            question: displayQuestion,
            modelLabel: modelLabel,
            provider: provider,
            isDeepThinking: isDeep,
            state: .generating,
            attachmentNames: attachmentNames
        )
        temporaryTurns.append(turn)

        if imageAttachments.isEmpty,
           let dutyExec = WuMindDutyBridge.tryExecuteLocalDutyQuery(prompt: displayQuestion, activeModelLabel: modelLabel) {
            if let idx = temporaryTurns.firstIndex(where: { $0.id == turnID }) {
                temporaryTurns[idx].modelLabel = "本机内网直查 · 零外发（临时）"
                temporaryTurns[idx].actualChannelLabel = "App 内网只读引擎（独立于 \(modelLabel)）"
                temporaryTurns[idx].answer = dutyExec.formattedReport
                temporaryTurns[idx].state = .complete
            }
            temporaryGenerating = false
            return
        }

        if let violation = WuMindModelCapabilityMatrix.validateChatRequest(
            providerRaw: provider.rawValue,
            modelID: resolvedModelID,
            connectionLabel: store.activeDataDestinationLabel,
            isRelayBaseURL: ownIsRelay,
            deepThinking: isDeep,
            attachedImageCount: imageAttachments.count
        ) {
            if let idx = temporaryTurns.firstIndex(where: { $0.id == turnID }) {
                temporaryTurns[idx].failureStage = "发送前能力校验（未扣费）"
                temporaryTurns[idx].state = .failed(violation.userMessage)
            }
            temporaryGenerating = false
            return
        }

        temporaryGenerating = true
        temporaryElapsedSeconds = 1
        let tempStartedAt = Date()
        temporaryClockTask?.cancel()
        temporaryClockTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                temporaryElapsedSeconds = max(1, Int(Date().timeIntervalSince(tempStartedAt).rounded(.down)) + 1)
            }
        }

        // Notice: temporary mode intentionally omits long-term user memories!
        let systemPrompt = "你是 WUMIND AI 助手。当前处于「临时无痕聊天」模式，请直接、专业、清晰地回答用户问题。"

        temporaryTask?.cancel()
        temporaryTask = Task { @MainActor in
            defer {
                temporaryClockTask?.cancel()
                temporaryClockTask = nil
                temporaryGenerating = false
            }
            do {
                let res = try await store.runStatelessChat(
                    messages: priorMessages,
                    systemPrompt: systemPrompt,
                    deepThinking: isDeep,
                    onReasoningDelta: { r in
                        if let idx = temporaryTurns.firstIndex(where: { $0.id == turnID }) {
                            temporaryTurns[idx].reasoning = r
                        }
                    },
                    onAnswerDelta: { a in
                        if let idx = temporaryTurns.firstIndex(where: { $0.id == turnID }) {
                            temporaryTurns[idx].answer = a
                        }
                    }
                )
                try Task.checkCancellation()
                if let idx = temporaryTurns.firstIndex(where: { $0.id == turnID }) {
                    temporaryTurns[idx].reasoning = res.reasoning
                    temporaryTurns[idx].answer = res.answer
                    temporaryTurns[idx].state = .complete
                }
            } catch is CancellationError {
                if let idx = temporaryTurns.firstIndex(where: { $0.id == turnID }) {
                    temporaryTurns[idx].state = .stopped
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "临时聊天请求失败，请检查模型配置或网络。"
                if let idx = temporaryTurns.firstIndex(where: { $0.id == turnID }) {
                    temporaryTurns[idx].state = .failed(msg)
                }
            }
        }
    }

    private func copyText(_ text: String) {
        UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
        ToastCenter.shared.show("已复制", style: .success)
    }
}

/// Isolated composer view observing ONLY `WuMindComposerDraftState`, so typing every character
/// never triggers re-evaluation of `WuMindWorkspaceView`, `transcriptView`, or historical turns.
private struct WuMindIsolatedComposerBar: View {
    @ObservedObject var draftState: WuMindComposerDraftState
    @ObservedObject var store: WuMindStore
    @ObservedObject var dictation: WuMindDictationController

    let placeholder: String
    let activeAccentColor: Color
    let elevatedSurface: Color
    let subtleBorder: Color
    let colorScheme: ColorScheme
    let generating: Bool
    let importingAttachment: Bool
    let isTemporaryChat: Bool
    let canManualCompact: Bool
    let baseContextTokens: Int
    let windowTokenBudget: Int
    let questionLimit: Int
    let compactModelTitle: String
    let headerModelTitle: String
    var composerFocused: FocusState<Bool>.Binding
    let selectedBuild: WuMindChatBuild?
    let onSelectBuild: (WuMindChatBuild?) -> Void

    let onOpenProjects: () -> Void
    let onOpenSkills: () -> Void
    let onOpenGitHub: () -> Void
    let onOpenSharedMaterials: () -> Void
    let onOpenConnectors: () -> Void
    let onOpenModelHub: () -> Void
    let onManualCompact: () -> Void
    let onDismissKeyboard: () -> Void
    let onOpenVoiceInput: () -> Void
    let onOpenRealtimeVoice: () -> Void
    let onStop: () -> Void
    let onSend: () -> Void

    var body: some View {
        let cleaned = draftState.cleaned
        let draftTokens = cleaned.isEmpty ? 0 : WuMindContextEngine.estimateTokens(cleaned)
        let liveTokens = baseContextTokens + draftTokens
        let liveRatio = windowTokenBudget > 0 ? min(1.0, Double(liveTokens) / Double(windowTokenBudget)) : 0
        let overLimit = draftState.text.utf8.count > questionLimit
        let canSendNow = !generating
            && !importingAttachment
            && (!cleaned.isEmpty || !store.pendingAttachments.isEmpty)
            && !overLimit
        let draftBinding = Binding<String>(
            get: { draftState.text },
            set: { draftState.setText($0) }
        )

        VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 10) {
                WuMindComposerAttachmentsStrip(
                    store: store,
                    dictation: dictation,
                    importingAttachment: importingAttachment,
                    isTemporaryChat: isTemporaryChat,
                    cleanedDraft: cleaned,
                    liveEstimatedTokens: liveTokens,
                    onOpenProjects: onOpenProjects,
                    onOpenSkills: onOpenSkills,
                    onOpenGitHub: onOpenGitHub,
                    onOpenSharedMaterials: onOpenSharedMaterials
                )

                WuMindComposerTextInput(
                    placeholder: placeholder,
                    draft: draftBinding,
                    generating: generating,
                    composerFocused: composerFocused
                )

                WuMindComposerActionButtons(
                    store: store,
                    activeAccentColor: activeAccentColor,
                    generating: generating,
                    importingAttachment: importingAttachment,
                    isFocused: composerFocused.wrappedValue,
                    isOverLimit: overLimit,
                    canSend: canSendNow,
                    canManualCompact: canManualCompact,
                    liveUsageRatio: liveRatio,
                    liveEstimatedTokens: liveTokens,
                    compactModelTitle: compactModelTitle,
                    headerModelTitle: headerModelTitle,
                    canOfferBuild: !isTemporaryChat,
                    selectedBuild: selectedBuild,
                    onSelectBuild: onSelectBuild,
                    onOpenSkills: onOpenSkills,
                    onOpenConnectors: onOpenConnectors,
                    onOpenModelHub: onOpenModelHub,
                    onManualCompact: onManualCompact,
                    onDismissKeyboard: onDismissKeyboard,
                    onOpenVoiceInput: onOpenVoiceInput,
                    onOpenRealtimeVoice: onOpenRealtimeVoice,
                    onStop: onStop,
                    onSend: onSend
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(composerFocused.wrappedValue ? Color.primary.opacity(0.27) : subtleBorder,
                                  lineWidth: 1)
                    .allowsHitTesting(false)
            }

        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: 780)
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
private struct WuMindHistoryStreamProgress: View {
    @ObservedObject var buffer: WuMindStreamBuffer

    var body: some View {
        Text("样本字节 \(buffer.answer.text.utf8.count)")
            .font(.caption.monospacedDigit())
            .accessibilityIdentifier("wumind.qa.liveBytes")
            .accessibilityValue(String(buffer.answer.text.utf8.count))
    }
}
#endif

/// Geometry stays local to this observer. Offsets update during scrolling without invalidating chat rows.
private final class WuMindScrollGeometry: ObservableObject {
    private(set) var frame = CGRect.null
    let layoutChanges = PassthroughSubject<Void, Never>()

    func update(_ next: CGRect) {
        let sizeChanged = frame.size != next.size || frame.isNull
        frame = next
        if sizeChanged { layoutChanges.send() }
    }
}

private struct WuMindScrollFollower: View {
    nonisolated static let viewport = "wumind.transcript.viewport"
    let streamBuffer: WuMindStreamBuffer
    let viewportHeight: CGFloat
    let baseline: Bool
    let onCheck: (Bool) -> Void
    @StateObject private var geometry = WuMindScrollGeometry()

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.viewport))
            } action: { frame in
                geometry.update(frame)
            }
            .onChange(of: viewportHeight) { _ in geometry.layoutChanges.send() }
            .onReceive((baseline ? streamBuffer.answerLayoutChanges : geometry.layoutChanges).throttle(
                for: .milliseconds(210), scheduler: RunLoop.main, latest: true
            )) { _ in
                guard !geometry.frame.isNull else { return }
                onCheck(baseline || WuMindTranscriptPresentation.needsScrollToRevealBottom(
                    contentBottom: Double(geometry.frame.maxY), viewportHeight: Double(viewportHeight)
                ))
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// Isolated streaming leaf view observing `WuMindStreamBuffer` so ONLY the active turn redraws at ~12.5 Hz.
private struct WuMindStreamingTurnView: View {
    let turn: WuMindTurn
    @ObservedObject var streamBuffer: WuMindStreamBuffer
    let baseline: Bool
    let streamSmoothMode: Bool
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
        if !streamBuffer.answer.text.isEmpty {
            liveTurn.answer = streamBuffer.answer.text
        }
        if !streamBuffer.agentSteps.isEmpty {
            liveTurn.agentSteps = streamBuffer.agentSteps
        }
        if !streamBuffer.liveWebCitations.isEmpty {
            liveTurn.webCitations = streamBuffer.liveWebCitations
        }
        if !streamBuffer.liveAgentCitations.isEmpty {
            liveTurn.agentCitations = streamBuffer.liveAgentCitations
        }
        if !streamBuffer.liveToolFailures.isEmpty {
            liveTurn.toolFailureNotices = streamBuffer.liveToolFailures
        }
        if let lead = streamBuffer.inlineIntroLead, !lead.isEmpty {
            liveTurn.assistantIntroLead = lead
        }
        return WuMindTurnView(
            turn: liveTurn,
            liveAnswer: baseline || streamBuffer.answer.text.isEmpty ? nil : streamBuffer.answer,
            isLast: true,
            isGenerating: true,
            liveElapsedSeconds: streamBuffer.liveElapsedSeconds,
            streamSmoothMode: streamSmoothMode,
            activeAgentPhase: streamBuffer.activeAgentPhase,
            inlineStatusKind: streamBuffer.inlineStatusKind,
            inlineStatusText: streamBuffer.inlineStatusText,
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

private struct WuMindTurnView: View, Equatable {
    let turn: WuMindTurn
    let liveAnswer: WuMindStreamingAnswer?
    let isLast: Bool
    let isGenerating: Bool
    let liveElapsedSeconds: Int
    let streamSmoothMode: Bool
    let activeAgentPhase: String?
    let inlineStatusKind: WuMindStreamBuffer.InlineStatusKind?
    let inlineStatusText: String?
    let thinkingStartedAt: Date?
    let elevatedSurface: Color
    let subtleBorder: Color
    let onCopy: (String) -> Void
    let onRetryPrompt: (String) -> Void
    let onRegenerate: () -> Void
    let onManageKey: () -> Void
    let onOpenWallet: () -> Void
    let onCompare: (() -> Void)?
    let onAdoptComparison: ((UUID) -> Void)?
    let onRecoverTask: (() -> Void)?
    let hasCompareAction: Bool
    let hasRecoverAction: Bool

    init(
        turn: WuMindTurn,
        liveAnswer: WuMindStreamingAnswer? = nil,
        isLast: Bool,
        isGenerating: Bool,
        liveElapsedSeconds: Int = 1,
        streamSmoothMode: Bool = true,
        activeAgentPhase: String? = nil,
        inlineStatusKind: WuMindStreamBuffer.InlineStatusKind? = nil,
        inlineStatusText: String? = nil,
        thinkingStartedAt: Date?,
        elevatedSurface: Color,
        subtleBorder: Color,
        onCopy: @escaping (String) -> Void,
        onRetryPrompt: @escaping (String) -> Void,
        onRegenerate: @escaping () -> Void,
        onManageKey: @escaping () -> Void,
        onOpenWallet: @escaping () -> Void,
        onCompare: (() -> Void)? = nil,
        onAdoptComparison: ((UUID) -> Void)? = nil,
        onRecoverTask: (() -> Void)? = nil
    ) {
        self.turn = turn
        self.liveAnswer = liveAnswer
        self.isLast = isLast
        self.isGenerating = isGenerating
        self.liveElapsedSeconds = liveElapsedSeconds
        self.streamSmoothMode = streamSmoothMode
        self.activeAgentPhase = activeAgentPhase
        self.inlineStatusKind = inlineStatusKind
        self.inlineStatusText = inlineStatusText
        self.thinkingStartedAt = thinkingStartedAt
        self.elevatedSurface = elevatedSurface
        self.subtleBorder = subtleBorder
        self.onCopy = onCopy
        self.onRetryPrompt = onRetryPrompt
        self.onRegenerate = onRegenerate
        self.onManageKey = onManageKey
        self.onOpenWallet = onOpenWallet
        self.onCompare = onCompare
        self.onAdoptComparison = onAdoptComparison
        self.onRecoverTask = onRecoverTask
        self.hasCompareAction = onCompare != nil
        self.hasRecoverAction = onRecoverTask != nil
    }

    nonisolated static func == (lhs: WuMindTurnView, rhs: WuMindTurnView) -> Bool {
        lhs.turn == rhs.turn
            && lhs.isLast == rhs.isLast
            && lhs.isGenerating == rhs.isGenerating
            && lhs.liveElapsedSeconds == rhs.liveElapsedSeconds
            && lhs.streamSmoothMode == rhs.streamSmoothMode
            && lhs.activeAgentPhase == rhs.activeAgentPhase
            && lhs.inlineStatusKind == rhs.inlineStatusKind
            && lhs.inlineStatusText == rhs.inlineStatusText
            && lhs.elevatedSurface == rhs.elevatedSurface
            && lhs.subtleBorder == rhs.subtleBorder
            && lhs.hasCompareAction == rhs.hasCompareAction
            && lhs.hasRecoverAction == rhs.hasRecoverAction
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .body) private var messageSize = 16.0
    @ScaledMetric(relativeTo: .footnote) private var disclosureSize = 14.0
    @State private var thinkingExpanded = false
    @ScaledMetric(relativeTo: .body) private var streamingBodySize = 16.0
    @State private var answerExpansionOverride: Bool?
    @State private var showingPrimaryInCompactCompare = false

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
                        .font(.system(size: messageSize))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(
                            elevatedSurface,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(subtleBorder, lineWidth: 0.8)
                        )
                        .accessibilityLabel(Text("你：\(turn.question)"))
                }
            }

            // Assistant editorial response: a quiet model signature, then the answer on the canvas.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: turn.provider.iconName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                    Text(turn.modelLabel)
                        .font(.system(size: messageSize, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }

                // Reference-Recording Single Shared Inline Status Row (real event-driven: searching -> reading -> agent)
                let activeInlineText = isGenerating ? (inlineStatusText ?? activeAgentPhase) : nil
                if isGenerating, turn.chatBuildWorkID != nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(activeInlineText ?? "正在准备构建")
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("· \(max(1, liveElapsedSeconds)) 秒")
                            .monospacedDigit()
                            .fixedSize()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("wumind.chat.buildProgress")
                } else if (isGenerating && (activeInlineText != nil || turn.assistantIntroLead != nil)) {
                    WuMindInlineStatusRow(
                        introLead: turn.assistantIntroLead,
                        kind: inlineStatusKind,
                        text: activeInlineText,
                        isActive: isGenerating && turn.answer.isEmpty
                    )
                } else if !isGenerating, let steps = turn.agentSteps, !steps.isEmpty {
                    // Collapsible trace available after turn finishes (not stacked on top of live inline row)
                    WuMindAgentTraceCard(
                        steps: steps,
                        activePhase: nil,
                        isGenerating: false,
                        elevatedSurface: elevatedSurface,
                        subtleBorder: subtleBorder
                    )
                }

                // Official DeepSeek-style collapsible Thinking Process block
                if !turn.reasoning.isEmpty || (isCurrentlyThinking && activeInlineText == nil) {
                    thinkingBlock
                }

                if !turn.answer.isEmpty {
                    answerBlock
                }

                // Structured Persisted Citations (Web Sources + Separate Agent Citations) & Honest Tool Failure Notice
                let webCites = turn.webCitations ?? []
                let agentCites = turn.agentCitations ?? []
                let toolFails = turn.toolFailureNotices ?? []
                if !webCites.isEmpty || !WuMindToolTruthfulnessPolicy.visibleAgentCitations(from: agentCites).isEmpty || !toolFails.isEmpty {
                    WuMindTurnCitationsSection(
                        webCitations: webCites,
                        agentCitations: agentCites,
                        failureNotices: toolFails,
                        elevatedSurface: elevatedSurface,
                        subtleBorder: subtleBorder,
                        onRetry: (!isGenerating && isLast) ? onRegenerate : nil
                    )
                }

                // Dual-Model Cross-Review & Side-by-Side Comparison Cards
                if let comps = turn.comparisons, !comps.isEmpty {
                    ForEach(comps) { comp in
                        comparisonCard(comp)
                    }
                }

                // State footer
                switch turn.state {
                case .generating:
                    if turn.answer.isEmpty && !isCurrentlyThinking && activeInlineText == nil {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在连接模型并生成… \(max(1, liveElapsedSeconds))s")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                case .complete:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Button { onCopy(turn.answer) } label: {
                                Label("复制", systemImage: "doc.on.doc")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(elevatedSurface, in: Capsule())
                                    .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 0.9))
                            }
                            .buttonStyle(.plain)

                            if let onCompare {
                                Button(action: onCompare) {
                                    Label("对比/复核", systemImage: "rectangle.split.2x1")
                                        .font(DS.Font.caption.weight(.semibold))
                                        .foregroundStyle(DS.Palette.accent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.indigo.opacity(0.11), in: Capsule())
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("wumind.turn.compare")
                            }

                            if !turn.reasoning.isEmpty {
                                Button { onCopy(turn.reasoning) } label: {
                                    Label("思考", systemImage: "brain")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(elevatedSurface, in: Capsule())
                                        .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 0.9))
                                }
                                .buttonStyle(.plain)
                            }

                            if isLast {
                                Button(action: onRegenerate) {
                                    Label("重答", systemImage: "arrow.clockwise")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(elevatedSurface, in: Capsule())
                                        .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 0.9))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let channelInfo = turn.actualChannelLabel, !channelInfo.isEmpty {
                            let allowVerifiedBadge = WuMindToolTruthfulnessPolicy.canShowCapabilityVerifiedBadge(
                                baseBadge: turn.modelCapabilityBadge,
                                agentCitations: turn.agentCitations ?? [],
                                failureNotices: turn.toolFailureNotices ?? []
                            )
                            HStack(spacing: 4) {
                                Image(systemName: allowVerifiedBadge ? "checkmark.shield" : "exclamationmark.shield")
                                    .font(.system(size: 9))
                                Text("实际通道：\(channelInfo)")
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if allowVerifiedBadge, let badge = turn.modelCapabilityBadge, !badge.isEmpty {
                                    Text("· \(badge)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(badge == "目录可见" ? .orange : .green)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }

                        if let trace = turn.callTrace {
                            HStack(spacing: 4) {
                                Image(systemName: "speedometer")
                                    .font(.system(size: 9))
                                Text("\(trace.modelDiagnosticSummary) · \(trace.upstreamRoute) · \(trace.timing.compactSummary)")
                                    .font(.caption2.monospacedDigit())
                                    .lineLimit(2)
                            }
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("wumind.turn.latencyMetrics")
                        } else if turn.firstTokenMs != nil || turn.totalLatencyMs != nil {
                            let parts: [String] = {
                                var list: [String] = []
                                if let ttft = turn.firstTokenMs {
                                    list.append(ttft < 1000 ? "首字 \(ttft)ms" : String(format: "首字 %.1fs", Double(ttft) / 1000.0))
                                }
                                if let total = turn.totalLatencyMs {
                                    list.append(total < 1000 ? "总计 \(total)ms" : String(format: "总计 %.1fs", Double(total) / 1000.0))
                                }
                                return list
                            }()
                            if !parts.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "speedometer")
                                        .font(.system(size: 9))
                                    Text(parts.joined(separator: " · "))
                                        .font(.caption2.monospacedDigit())
                                }
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("wumind.turn.latencyMetrics")
                            }
                        }

                        if let cost = turn.costYuan {
                            let inTok = turn.promptTokens ?? 0
                            let outTok = (turn.completionTokens ?? 0) + (turn.reasoningTokens ?? 0)
                            Button(action: onOpenWallet) {
                                HStack(spacing: 5) {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.system(size: 9.5))
                                    Text("输入 \(WuMindAccountStatus.formatTokens(inTok)) · 输出 \(WuMindAccountStatus.formatTokens(outTok)) · 扣费 ¥\(String(format: "%.4f", cost)) · 查看余额")
                                        .font(.caption2.monospacedDigit().weight(.medium))
                                }
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.indigo.opacity(0.09), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                case .stopped:
                    VStack(alignment: .leading, spacing: 6) {
                        let stopSuffix = turn.callTrace?.timing.stopLatencyMs.map { " · 停止响应 \($0)ms" } ?? ""
                        Text("已停止生成（未完成片段不会带入下一轮上下文\(stopSuffix)）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let onRecoverTask, turn.answer.isEmpty {
                            Button("查询原任务结果（不重提）", action: onRecoverTask)
                                .font(.caption.weight(.bold))
                                .buttonStyle(.borderedProminent)
                                .tint(.teal)
                                .accessibilityIdentifier("wumind.turn.recoverTaskStopped")
                        }
                        if isLast {
                            HStack(spacing: 8) {
                                Button("重新生成", action: onRegenerate)
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                                Button("放回输入框") { onRetryPrompt(turn.question) }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                case .failed(let message):
                    let terminalProviderFailure = ["model_refused", "provider_key_disabled"].contains(turn.callTrace?.failureCode ?? "")
                    VStack(alignment: .leading, spacing: 8) {
                        if let stage = turn.failureStage, !stage.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "scope")
                                    .font(.system(size: 9.5, weight: .bold))
                                Text("失败阶段：\(stage)")
                                    .font(.caption2.weight(.bold))
                                if let ch = turn.actualChannelLabel, !ch.isEmpty {
                                    Text("· \(ch)")
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                            }
                            .foregroundStyle(DS.Palette.danger.opacity(0.9))
                        }
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.danger)
                        if let onRecoverTask, !terminalProviderFailure {
                            Button("查询原任务结果（不重提）", action: onRecoverTask)
                                .font(.caption.weight(.bold))
                                .buttonStyle(.borderedProminent)
                                .tint(.teal)
                                .accessibilityIdentifier("wumind.turn.recoverTask")
                        }
                        if isLast {
                            HStack(spacing: 8) {
                                if !terminalProviderFailure {
                                    Button("立即重试发送", action: onRegenerate)
                                        .font(.caption.weight(.bold))
                                        .buttonStyle(.borderedProminent)
                                        .tint(.indigo)
                                        .accessibilityIdentifier("wumind.turn.retryNow")
                                }
                                Button("放回输入框") { onRetryPrompt(turn.question) }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                            }
                        }
                        if message.contains("余额不足") || message.contains("充值") || message.contains("网关") {
                            Button("查看钱包 / 兑换码", action: onOpenWallet)
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.borderedProminent)
                                .tint(.indigo)
                        } else if message.contains("Key") || message.contains("密钥") || message.contains("余额") {
                            Button("管理 API Key", action: onManageKey)
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(12)
                    .background(DS.Palette.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.leading, 2)
        }
    }

    @ViewBuilder
    private func comparisonCard(_ comp: WuMindComparisonResult) -> some View {
        let compProvider = WuMindProvider(rawValue: comp.providerRaw) ?? .openAI
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: comp.mode == .crossReview ? "checkmark.shield.fill" : "rectangle.split.2x1.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(compProvider.brandColor, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("\(comp.mode.title) · \(comp.modelLabel)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if comp.adopted {
                            Text("已采纳")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.teal, in: Capsule())
                        }
                    }
                    Text(comp.channelLabel + (comp.costYuan.map { String(format: " · 扣费 ¥%.4f", $0) } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
            }

            if horizontalSizeClass == .regular && comp.mode == .independentCompare {
                // iPad / wide viewport: true side-by-side comparison!
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("主答 · \(turn.modelLabel)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(turn.provider.brandColor)
                        WuMindMarkdownView(
                            text: turn.answer,
                            isStreaming: false,
                            elevatedSurface: elevatedSurface,
                            subtleBorder: subtleBorder,
                            onCopyCode: onCopy
                        )
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("并排对比 · \(comp.modelLabel)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(compProvider.brandColor)
                        WuMindMarkdownView(
                            text: comp.answer,
                            isStreaming: false,
                            elevatedSurface: elevatedSurface,
                            subtleBorder: subtleBorder,
                            onCopyCode: onCopy
                        )
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(compProvider.brandColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            } else {
                if comp.mode == .independentCompare {
                    HStack(spacing: 6) {
                        Button {
                            showingPrimaryInCompactCompare = false
                        } label: {
                            Text("\(comp.modelLabel)（对比版）")
                                .font(.caption2.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(!showingPrimaryInCompactCompare ? compProvider.brandColor.opacity(0.16) : Color.clear, in: Capsule())
                                .foregroundStyle(!showingPrimaryInCompactCompare ? compProvider.brandColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        Button {
                            showingPrimaryInCompactCompare = true
                        } label: {
                            Text("\(turn.modelLabel)（主答）")
                                .font(.caption2.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(showingPrimaryInCompactCompare ? turn.provider.brandColor.opacity(0.16) : Color.clear, in: Capsule())
                                .foregroundStyle(showingPrimaryInCompactCompare ? turn.provider.brandColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(3)
                    .background(elevatedSurface, in: Capsule())
                }

                WuMindMarkdownView(
                    text: (comp.mode == .independentCompare && showingPrimaryInCompactCompare) ? turn.answer : comp.answer,
                    isStreaming: false,
                    elevatedSurface: elevatedSurface,
                    subtleBorder: subtleBorder,
                    onCopyCode: onCopy
                )
            }

            HStack(spacing: 8) {
                Button { onCopy(comp.answer) } label: {
                    Label("复制复核内容", systemImage: "doc.on.doc")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(elevatedSurface, in: Capsule())
                        .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 0.8))
                }
                .buttonStyle(.plain)

                if let onAdoptComparison {
                    Button {
                        onAdoptComparison(comp.id)
                    } label: {
                        Label(comp.adopted ? "已采纳此版" : "采纳复核结论", systemImage: comp.adopted ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(comp.adopted ? .white : .teal)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(comp.adopted ? Color.teal : Color.teal.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(compProvider.brandColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(compProvider.brandColor.opacity(0.28), lineWidth: 1))
    }

    private var answerBlock: some View {
        let longAnswer = (!isGenerating || !streamSmoothMode) && WuMindTranscriptPresentation.shouldFoldAnswer(turn.answer)
        let expanded = answerExpansionOverride ?? (isGenerating || !longAnswer)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                answerExpansionOverride = !expanded
            } label: {
                disclosureLabel(expanded ? "收起回复" : "展开回复", expanded: expanded)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wumind.answer.toggle")
            .accessibilityValue(expanded ? "已展开" : "已收起")
            if expanded {
                if let liveAnswer, streamSmoothMode || longAnswer, !liveAnswer.completeBlocks.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(liveAnswer.completeBlocks.indices, id: \.self) { index in
                            Text(verbatim: liveAnswer.completeBlocks[index])
                        }
                        Text(verbatim: liveAnswer.tail.isEmpty ? "\u{200B}" : liveAnswer.tail)
                    }
                    .font(.system(size: streamingBodySize)).lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("wumind.answer.full")
                } else {
                    WuMindMarkdownView(
                        text: turn.answer,
                        isStreaming: isGenerating && (streamSmoothMode || longAnswer),
                        elevatedSurface: elevatedSurface,
                        subtleBorder: subtleBorder,
                        onCopyCode: onCopy
                    )
                    .accessibilityIdentifier("wumind.answer.full")
                }
            } else {
                Text(WuMindTranscriptPresentation.answerPreview(turn.answer))
                    .font(.system(size: messageSize))
                    .foregroundStyle(.primary)
                    .lineSpacing(5)
                    .lineLimit(3)
                    .accessibilityIdentifier("wumind.answer.preview")
            }
        }
    }

    private func disclosureLabel(_ title: String, expanded: Bool, loading: Bool = false) -> some View {
        HStack(spacing: 7) {
            if loading { ProgressView().controlSize(.mini) }
            Text(title)
                .font(.system(size: disclosureSize))
                .monospacedDigit()
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .accessibilityHidden(true)
        }
        .foregroundStyle(.secondary)
        .frame(minHeight: 36, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var thinkingBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                thinkingExpanded.toggle()
            } label: {
                disclosureLabel(
                    isCurrentlyThinking ? "思考中 · \(max(1, liveElapsedSeconds)) 秒" : "思考结果",
                    expanded: thinkingExpanded, loading: isCurrentlyThinking
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wumind.thinking.toggle")
            .accessibilityValue(thinkingExpanded ? "已展开" : "已收起")

            if thinkingExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if let seconds = turn.reasoningSeconds, seconds.isFinite {
                        Text("用时 \(max(1, Int(seconds.rounded()))) 秒")
                            .font(.caption.monospacedDigit())
                    }
                    if turn.reasoning.isEmpty {
                        Text("等待思考内容…")
                    } else if isGenerating {
                        Text(turn.reasoning)
                    } else {
                        Text(turn.reasoning).textSelection(.enabled)
                    }
                }
                .font(.system(size: disclosureSize))
                .lineSpacing(5)
                .foregroundStyle(.secondary)
                .padding(.leading, 11)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    Rectangle().fill(subtleBorder).frame(width: 1)
                }
            }
        }
    }
}

// MARK: - Rich Markdown & Styled Code Block Renderer (60 FPS Streaming Fast-Path + Cached Rich Path)

@MainActor
private final class WuMindRichSegmentBox {
    let sourceText: String
    let segments: [WuMindRichContentParser.Segment]
    init(sourceText: String, segments: [WuMindRichContentParser.Segment]) {
        self.sourceText = sourceText
        self.segments = segments
    }
}

@MainActor
private enum WuMindRichSegmentCache {
    private static let cache: NSCache<NSString, WuMindRichSegmentBox> = {
        let c = NSCache<NSString, WuMindRichSegmentBox>()
        c.countLimit = 80
        return c
    }()

    static func segments(for text: String) -> [WuMindRichContentParser.Segment] {
        let key = "\(text.utf8.count):\(text.hashValue)" as NSString
        if let hit = cache.object(forKey: key), hit.sourceText == text {
            return hit.segments
        }
        let parsed = WuMindRichContentParser.splitSegments(text)
        cache.setObject(WuMindRichSegmentBox(sourceText: text, segments: parsed), forKey: key)
        return parsed
    }
}

private struct WuMindMarkdownView: View {
    let text: String
    let isStreaming: Bool
    let elevatedSurface: Color
    let subtleBorder: Color
    let onCopyCode: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var proseSize = 16.0

    private var proseFont: Font { .system(size: proseSize) }
    private var inlineCodeTint: Color {
        colorScheme == .dark ? Color(red: 1, green: 0.52, blue: 0.25) : Color(red: 0.62, green: 0.22, blue: 0.045)
    }

    private enum RichSegmentKind {
        case divider
        case heading(level: Int, text: String)
        case quote(String)
        case bullet(String)
        case numbered(index: String, text: String)
        case paragraph(String)
    }

    private struct RichSegment: Identifiable {
        let id: Int
        let kind: RichSegmentKind
    }

    var body: some View {
        if isStreaming {
            Text(text)
                .font(proseFont)
                .foregroundStyle(.primary)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let segments = WuMindRichSegmentCache.segments(for: text)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .prose(let prose):
                        richProseView(prose)
                    case .code(let lang, let code):
                        codeCard(language: lang, code: code, selectable: true)
                    case .displayMath(let latex, let pretty):
                        WuMindMathBlockView(
                            latex: latex,
                            pretty: pretty,
                            elevatedSurface: elevatedSurface,
                            subtleBorder: subtleBorder,
                            onCopy: onCopyCode
                        )
                    case .mermaid(let source, let diagram):
                        WuMindMermaidDiagramView(
                            source: source,
                            diagram: diagram,
                            elevatedSurface: elevatedSurface,
                            subtleBorder: subtleBorder,
                            onCopy: onCopyCode
                        )
                    case .table(let headers, let rows):
                        WuMindMarkdownTableView(
                            headers: headers,
                            rows: rows,
                            elevatedSurface: elevatedSurface,
                            subtleBorder: subtleBorder
                        )
                    }
                }
            }
        }
    }

    private func codeCard(language: String, code: String, selectable: Bool) -> some View {
        let lineCount = max(1, code.components(separatedBy: "\n").count)
        let obsidianBg = Color(red: 0.085, green: 0.098, blue: 0.13)
        let obsidianHeader = Color(red: 0.125, green: 0.142, blue: 0.185)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(Color.red.opacity(0.75)).frame(width: 7, height: 7)
                    Circle().fill(Color.yellow.opacity(0.75)).frame(width: 7, height: 7)
                    Circle().fill(Color.green.opacity(0.75)).frame(width: 7, height: 7)
                }
                Text(language.isEmpty ? "CODE" : language.uppercased())
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.82))
                Text("· \(lineCount) 行")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
                Spacer()
                Button { onCopyCode(code) } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.11), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(obsidianHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                if selectable {
                    Text(code)
                        .font(.system(size: 13.2, design: .monospaced))
                        .foregroundStyle(Color(red: 0.90, green: 0.93, blue: 0.98))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(13)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Text(code)
                        .font(.system(size: 13.2, design: .monospaced))
                        .foregroundStyle(Color(red: 0.90, green: 0.93, blue: 0.98))
                        .lineSpacing(4)
                        .padding(13)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .background(obsidianBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Zero-jank streaming renderer: groups text into ~1,200-char chunks using native `Text` without
    /// running O(N^2) `AttributedString(markdown:)` or `textSelection` layout on every incoming delta.
    private func richProseView(_ raw: String) -> some View {
        let segments = parseRichSegments(raw)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { segment in
                switch segment.kind {
                case .divider:
                    Rectangle()
                        .fill(subtleBorder)
                        .frame(height: 1)
                        .padding(.vertical, 6)
                case .heading(let level, let headingText):
                    markdownText(headingText)
                        .font(.system(size: proseSize + (level == 1 ? 5 : level == 2 ? 2 : 0), weight: .semibold))
                        .lineSpacing(4)
                        .padding(.top, 5)
                        .accessibilityAddTraits(.isHeader)
                case .quote(let quoteText):
                    markdownText(quoteText)
                        .font(proseFont)
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                        .padding(.leading, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(subtleBorder).frame(width: 1)
                        }
                case .bullet(let bulletText):
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("•")
                            .font(.system(size: proseSize * 0.77))
                            .frame(minWidth: 12)
                            .accessibilityHidden(true)
                        markdownText(bulletText)
                            .font(proseFont)
                            .lineSpacing(5)
                    }
                case .numbered(let index, let itemText):
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("\(index).")
                            .font(proseFont.monospacedDigit())
                        markdownText(itemText)
                            .font(proseFont)
                            .lineSpacing(5)
                    }
                case .paragraph(let bodyText):
                    markdownText(bodyText)
                        .font(proseFont)
                        .lineSpacing(5)
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

    private func parseNumberedPrefix(_ trimmed: String) -> (index: String, body: String)? {
        guard let dot = trimmed.firstIndex(of: ".") else { return nil }
        let prefix = trimmed[..<dot]
        guard !prefix.isEmpty, prefix.count <= 3, prefix.allSatisfy(\.isNumber) else { return nil }
        let afterDot = trimmed.index(after: dot)
        guard afterDot < trimmed.endIndex, trimmed[afterDot] == " " else { return nil }
        let body = String(trimmed[trimmed.index(after: afterDot)...]).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        return (String(prefix), body)
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
            } else if let num = parseNumberedPrefix(trimmed) {
                flushParagraph()
                segments.append(RichSegment(id: segments.count, kind: .numbered(index: num.index, text: num.body)))
            } else {
                paragraphBuffer.append(line)
            }
        }
        flushParagraph()
        return segments
    }

    private func markdownText(_ source: String) -> Text {
        if var attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            let codeRanges = attributed.runs.compactMap { run in
                run[AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute.self]?.contains(.code) == true ? run.range : nil
            }
            for range in codeRanges {
                attributed[range][AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = inlineCodeTint
            }
            return Text(attributed)
        }
        return Text(source)
    }


}

// MARK: - Flagship Multi-Provider Model, Verification & Capability Center

@MainActor
struct WuMindModelHubSheet: View {
    enum CapabilityTab: String, CaseIterable, Identifiable {
        case chat
        case image
        case voice

        var id: String { rawValue }
        var title: String {
            switch self {
            case .chat: return "文字对话"
            case .image: return "图像生成"
            case .voice: return "实时语音"
            }
        }
        var icon: String {
            switch self {
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .image: return "photo.on.rectangle.angled"
            case .voice: return "phone.waveform.fill"
            }
        }
    }

    @ObservedObject var store: WuMindStore
    let onEditKey: (WuMindProvider, AICompatibleChatService?) -> Void
    let onOpenTool: (WuMindWorkspaceView.ToolboxDestination) -> Void
    let onOpenWallet: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewingProvider: WuMindProvider
    @State private var capabilityTab: CapabilityTab = .chat
    @State private var query = ""
    @State private var manualModelID = ""
    @State private var refreshing = false
    @State private var refreshError: String?
    @State private var testingModelID: String?
    @State private var smokeDiagnosticBanner: String?
    @State private var showNonChatCatalog = false
    @State private var pendingExpensiveUpgrade: WuMindPricingItem? = nil

    init(
        store: WuMindStore,
        onEditKey: @escaping (WuMindProvider, AICompatibleChatService?) -> Void,
        onOpenTool: @escaping (WuMindWorkspaceView.ToolboxDestination) -> Void,
        onOpenWallet: @escaping () -> Void
    ) {
        self.store = store
        self.onEditKey = onEditKey
        self.onOpenTool = onOpenTool
        self.onOpenWallet = onOpenWallet
        _viewingProvider = State(initialValue: store.selectedProvider)
    }

    private var isDark: Bool { colorScheme == .dark }
    private var pageBg: Color {
        DS.Palette.background
    }
    private var cardBg: Color {
        DS.Palette.cardSurface
    }
    private var cardBorder: Color {
        DS.Palette.hairline
    }

    private var allProviderModels: [WuMindModelOption] {
        store.models(for: viewingProvider)
    }

    private var availableTextModels: [WuMindModelOption] {
        let base = allProviderModels.filter(\.supportsTextChat)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = q.isEmpty ? base : base.filter {
            $0.displayName.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q)
        }
        return filtered.sorted { lhs, rhs in
            let lActive = (store.selectedProvider == lhs.provider && store.selectedModelID == lhs.id)
            let rActive = (store.selectedProvider == rhs.provider && store.selectedModelID == rhs.id)
            if lActive != rActive { return lActive }
            let lPassed = store.smokeRecord(for: lhs.provider, modelID: lhs.id)?.status == .passed
            let rPassed = store.smokeRecord(for: rhs.provider, modelID: rhs.id)?.status == .passed
            if lPassed != rPassed { return lPassed }
            return false
        }
    }

    private var nonChatCatalogModels: [WuMindModelOption] {
        allProviderModels.filter { !$0.supportsTextChat }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Channel & Capability Entrance Bar (Zero horizontal scroll!)
                VStack(spacing: 10) {
                    // 3-Capability Entrance Segmented Bar (Chat / Image / Realtime Voice)
                    HStack(spacing: 6) {
                        ForEach(CapabilityTab.allCases) { tab in
                            let active = capabilityTab == tab
                            Button {
                                Haptics.select()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    capabilityTab = tab
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text(tab.title)
                                        .font(.caption.weight(.bold))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(active ? (isDark ? Color.black : Color.white) : .secondary)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 48)
                                .background(
                                    active ? (isDark ? Color.white : Color.black) : Color.secondary.opacity(0.11),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(active ? .isSelected : [])
                            .accessibilityIdentifier("wumind.models.tab.\(tab.rawValue)")
                        }
                    }

                    if capabilityTab == .chat {
                        // Channel quick toggle (Own API vs WUMIND Managed)
                        HStack(spacing: 6) {
                            ForEach(WuMindChannel.allCases) { ch in
                                let active = store.channel == ch
                                Button {
                                    Haptics.select()
                                    store.setChannel(ch)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: ch == .managed ? "bolt.shield.fill" : "key.fill")
                                            .font(.system(size: 10.5, weight: .semibold))
                                        Text(ch == .managed ? "WUMIND 内置" : "自有通道")
                                            .font(.caption2.weight(.bold))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(active ? .white : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 48)
                                    .background(
                                        active ? (ch == .managed ? Color.indigo : viewingProvider.brandColor) : Color.secondary.opacity(0.10),
                                        in: Capsule()
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(active ? .isSelected : [])
                                .accessibilityIdentifier("wumind.channel.\(ch.rawValue)")
                            }
                        }

                        if store.channel == .ownAPI {
                            HStack {
                                Text("服务商").font(.subheadline)
                                Spacer()
                                Menu {
                                    ForEach(WuMindProvider.allCases) { provider in
                                        if provider == .openAI {
                                            ForEach(AICompatibleChatService.allCases) { service in
                                                Button(service.displayName) { chooseProvider(provider, service: service) }
                                            }
                                        } else {
                                            Button(provider.displayName) { chooseProvider(provider) }
                                        }
                                    }
                                } label: {
                                    let service = viewingProvider == .openAI
                                        ? AICompatibleChatService.matching(AIProviderEndpoints.baseURL(for: .openAI)) : nil
                                    Label(service?.displayName ?? viewingProvider.displayName, systemImage: "chevron.up.chevron.down")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .accessibilityIdentifier("wumind.provider.menu")
                            }

                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .background(pageBg)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        switch capabilityTab {
                        case .chat:
                            if store.channel == .managed {
                                managedChatSection
                            } else {
                                ownAPIChatSection
                            }
                        case .image:
                            imageCapabilitySection
                        case .voice:
                            voiceCapabilitySection
                        }
                    }
                    .padding(14)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(pageBg.ignoresSafeArea())
            }
            .navigationTitle("WUMIND 模型与能力中心")
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
            .alert(
                "确认切换至更高价模型？",
                isPresented: Binding(
                    get: { pendingExpensiveUpgrade != nil },
                    set: { if !$0 { pendingExpensiveUpgrade = nil } }
                ),
                presenting: pendingExpensiveUpgrade
            ) { item in
                Button("确认切换") {
                    store.selectManagedModel(item)
                    pendingExpensiveUpgrade = nil
                    dismiss()
                }
                Button("保持当前模型", role: .cancel) {
                    pendingExpensiveUpgrade = nil
                }
            } message: { item in
                let curPrice = store.activeManagedModel?.outputPricePerMillion ?? 0
                Text("「\(item.displayName)」输出单价约 ¥\(String(format: "%.1f", item.outputPricePerMillion))/百万 Token，明显高于当前模型（约 ¥\(String(format: "%.1f", curPrice))/百万 Token）。WUMIND 不会在未提示的情况下自动升级到更贵模型。")
            }
        }
    }

    // MARK: - Managed Channel Models

    private var managedChatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                onOpenWallet()
            } label: {
                HStack {
                    Label("钱包与用量", systemImage: "creditcard.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(store.managedBalanceYuan.map { String(format: "¥%.2f", $0) } ?? "余额未知")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(13)
                .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)

            ForEach(store.enabledManagedModels) { item in
                let active = store.activeManagedModel?.id == item.id
                Button {
                    Haptics.select()
                    if let cur = store.activeManagedModel,
                       cur.id != item.id,
                       WuMindCostTransparency.requiresUpgradeConfirmation(
                           fromPricePer1K: cur.outputPricePerMillion / 1_000.0,
                           toPricePer1K: item.outputPricePerMillion / 1_000.0
                       ) {
                        pendingExpensiveUpgrade = item
                    } else {
                        store.selectManagedModel(item)
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("输入 ¥\(String(format: "%.1f", item.inputPricePerMillion)) · 输出 ¥\(String(format: "%.1f", item.outputPricePerMillion)) / 百万 Token")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if active {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.indigo)
                                .font(.title3)
                        }
                    }
                    .padding(13)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(active ? Color.indigo.opacity(0.55) : cardBorder, lineWidth: active ? 1.4 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chooseProvider(_ provider: WuMindProvider, service: AICompatibleChatService? = nil) {
        Haptics.select()
        refreshError = nil
        smokeDiagnosticBanner = nil
        query = ""
        manualModelID = ""
        if let service, Keychain.providerChatAPIKey(.openAI, baseURL: service.baseURL) != nil {
            store.activateOwnEndpoint(service.baseURL, for: .openAI)
        } else if service != nil || !provider.hasKey {
            onEditKey(provider, service)
            return
        }
        store.selectProvider(provider)
        viewingProvider = provider
    }

    // MARK: - Own-API Full Searchable Chat Models + Live Smoke Test

    private var ownAPIChatSection: some View {
        let ver = store.verification(for: viewingProvider)
        let currentHost = store.resolvedHost(for: viewingProvider)
        let verifiedCount = store.verifiedModelCount(for: viewingProvider)
        let totalChatCount = allProviderModels.filter(\.supportsTextChat).count

        return VStack(alignment: .leading, spacing: 12) {
            // Provider Status & Honest Separation Card (Catalog Readable vs Smoke Verified)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    WuMindIconBadge(icon: viewingProvider.iconName, color: viewingProvider.brandColor)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(viewingProvider.displayName)
                                .font(.headline)
                            Text(ver?.badgeText ?? "未配置")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(ver?.dotColor ?? .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background((ver?.dotColor ?? Color.secondary).opacity(0.14), in: Capsule())
                        }
                        Text("请求域名：\(currentHost)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(viewingProvider.brandColor)
                    }
                    Spacer(minLength: 4)
                    Button(viewingProvider.hasKey ? "配置 Key" : "填写 Key") {
                        store.selectProvider(viewingProvider)
                        onEditKey(viewingProvider, nil)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(viewingProvider.brandColor, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wumind.models.editKey")
                }

                Text("当前模型 · \(store.selectedModelName)")
                    .font(.footnote.weight(.medium))
                if verifiedCount > 0 {
                    Text("已试跑 \(verifiedCount) 个模型").font(.caption).foregroundStyle(.secondary)
                }

                if viewingProvider != .deepSeek && viewingProvider.hasKey {
                    HStack(spacing: 8) {
                        Button {
                            fetchModels(for: viewingProvider)
                        } label: {
                            HStack(spacing: 6) {
                                if refreshing {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption.weight(.bold))
                                }
                                Text(totalChatCount == 0 ? "拉取全部模型目录" : "刷新全部目录")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(viewingProvider.brandColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(viewingProvider.brandColor.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(refreshing)

                        Spacer()

                        if !nonChatCatalogModels.isEmpty {
                            Text("另含 \(nonChatCatalogModels.count) 个非聊天模型")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    DisclosureGroup("高级设置") {
                        HStack(spacing: 8) {
                            TextField("自定义模型 ID", text: $manualModelID)
                                .font(.footnote)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Button("使用") {
                                let trimmed = manualModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                Haptics.select()
                                store.addManualModel(trimmed, for: viewingProvider)
                                manualModelID = ""
                                dismiss()
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                manualModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.secondary.opacity(0.35) : viewingProvider.brandColor,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .buttonStyle(.plain)
                            .disabled(manualModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                if let refreshError {
                    Text(refreshError)
                        .font(.caption)
                        .foregroundStyle(DS.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let smokeDiagnosticBanner {
                    Text(smokeDiagnosticBanner)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

            // Instant Full-Catalog Search Box (No truncation!)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("搜索全部 \(totalChatCount) 个聊天模型（完整显示不截断）", text: $query)
                    .font(.subheadline)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("wumind.models.search")
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(cardBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

            // Full Un-Truncated Chat Model List
            if !viewingProvider.hasKey && viewingProvider != .deepSeek {
                Text("点击「填写 Key」保存服务商密钥，即可用预设模型开始对话。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else if availableTextModels.isEmpty {
                Text(query.isEmpty
                     ? "点击上方「拉取全部模型目录」查看全部模型，或直接手动输入模型编号。"
                     : "未找到包含「\(query)」的聊天模型。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else {
                Text("全部聊天模型（共显示 \(availableTextModels.count) / \(totalChatCount) 个）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(availableTextModels) { model in
                    chatModelRow(model)
                }
            }

            // Expandable Non-Chat Catalog Visibility (so nothing is ever mysteriously hidden!)
            if !nonChatCatalogModels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showNonChatCatalog.toggle()
                        }
                    } label: {
                        HStack {
                            Label("目录中另有 \(nonChatCatalogModels.count) 个非聊天模型（出图 / 语音 / 向量）", systemImage: "info.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: showNonChatCatalog ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if showNonChatCatalog {
                        Text("出图与实时语音模型使用独立协议，不在普通文字聊天接口调用；请切换到顶部「图像生成」或「实时语音」标签进入专用工坊。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(nonChatCatalogModels) { item in
                            HStack(spacing: 8) {
                                Text(item.id)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(capabilityBadgeTitle(item.capability))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .padding(12)
                .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
            }
        }
    }

    private func chatModelRow(_ model: WuMindModelOption) -> some View {
        let isActive = store.selectedProvider == model.provider && store.selectedModelID == model.id
        let smoke = store.smokeRecord(for: model.provider, modelID: model.id)
        let isTesting = testingModelID == model.id

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    Haptics.select()
                    store.selectModel(model)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(smoke?.dotColor ?? Color.blue.opacity(0.65))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(model.displayName)
                                    .font(.subheadline.weight(isActive ? .bold : .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if isActive {
                                    Text("当前")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(viewingProvider.brandColor, in: Capsule())
                                }
                            }
                            HStack(spacing: 6) {
                                if model.displayName != model.id {
                                    Text(model.id)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Text(smoke?.badgeText ?? "待试跑")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(smoke?.dotColor ?? .blue)
                            }
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if viewingProvider.hasKey {
                    Button {
                        Haptics.tap()
                        smokeTestModel(model)
                    } label: {
                        HStack(spacing: 4) {
                            if isTesting {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: smoke?.status == .passed ? "checkmark.seal.fill" : "play.fill")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(isTesting ? "测中" : "试跑")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(smoke?.status == .passed ? Color.green : viewingProvider.brandColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            (smoke?.status == .passed ? Color.green : viewingProvider.brandColor).opacity(0.13),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(testingModelID != nil)
                }
            }

            if let smoke, smoke.status == .failed {
                Text("上次失败：\(smoke.errorCode.map { "\($0) · " } ?? "")\(smoke.detail)")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isActive ? viewingProvider.brandColor.opacity(0.55) : cardBorder, lineWidth: isActive ? 1.3 : 1)
        )
    }

    // MARK: - Dedicated Image Generation Entrance

    private var imageCapabilitySection: some View {
        let snapshot = AIProviderEndpoints.currentImageCredentialSnapshot(store: store)
        let routeLabel: String = {
            if snapshot.useManagedGateway {
                return AIImageRouteKind.managedGateway.badgeText
            }
            if snapshot.ownPreference != .directVendor, snapshot.aihubmixConnection != nil {
                return AIImageRouteKind.ownAIHubMix.badgeText
            }
            return AIImageRouteKind.ownDirectVendor.badgeText
        }()
        let readyCount = AIImageTool.models.filter {
            AIImageStudioAvailability.evaluate(model: $0, hasReferenceImage: false, snapshot: snapshot).isReady
        }.count

        return VStack(alignment: .leading, spacing: 12) {
            LabeledContent(routeLabel) {
                Text("可用 \(readyCount) / \(AIImageTool.models.count)")
            }
            .font(DS.Font.callout)
            .card(padding: DS.Space.m)

            ForEach(AIImageTool.models) { item in
                let availability = AIImageStudioAvailability.evaluate(
                    model: item,
                    hasReferenceImage: false,
                    snapshot: snapshot
                )
                let isReady = availability.isReady
                let isGatewayConfigInvalid: Bool = {
                    if case .managedGatewayConfigInvalid = availability { return true }
                    return false
                }()
                let subtitleText: String = {
                    if case .ready(_, _, let detail, _, _) = availability {
                        return "\(item.id) · \(detail)"
                    }
                    if case .managedGatewayConfigInvalid = availability {
                        return "\(item.id) · WuMind 网关地址无效或未配置（不读本机 Key）"
                    }
                    if case .managedModelNotEnabled = availability {
                        return "\(item.id) · WuMind 内置暂未开通"
                    }
                    return "\(item.provider.displayName) · \(item.id)"
                }()

                Button {
                    Haptics.tap()
                    UserDefaults.standard.set(item.id, forKey: "wumind.imageStudio.modelID")
                    onOpenTool(.image)
                } label: {
                    HStack(spacing: 12) {
                        WuMindIconBadge(icon: "wand.and.stars", color: isReady ? .purple : (isGatewayConfigInvalid ? .orange : .secondary))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(subtitleText)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(availability.modelCenterPillTitle)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(isReady ? Color.white : (isGatewayConfigInvalid ? Color.orange : (snapshot.useManagedGateway ? Color.secondary : Color.orange)))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                isReady
                                    ? Color.purple
                                    : (isGatewayConfigInvalid ? Color.orange.opacity(0.14) : (snapshot.useManagedGateway ? Color.secondary.opacity(0.14) : Color.orange.opacity(0.14))),
                                in: Capsule()
                            )
                    }
                    .padding(13)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Dedicated Realtime Voice Entrance

    private var voiceCapabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(store.channel == .managed ? "内置通道" : "自有通道", systemImage: "waveform")
                .font(DS.Font.callout)
                .foregroundStyle(.secondary)

            ForEach(AILiveProtocol.models) { item in
                Button {
                    Haptics.tap()
                    onOpenTool(.live)
                } label: {
                    HStack(spacing: 12) {
                        WuMindIconBadge(icon: "waveform.circle.fill", color: .teal)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("OpenAI Realtime · \(item.id)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("进入通话")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.teal, in: Capsule())
                    }
                    .padding(13)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Button {
                Haptics.tap()
                onOpenTool(.speech)
            } label: {
                HStack(spacing: 12) {
                    WuMindIconBadge(icon: "mic.fill", color: .indigo)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("语音合成与录音转写（TTS / STT）")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("系统离线朗读 · xAI 拟真音色 · OpenAI 录音转文字")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(13)
                .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func capabilityBadgeTitle(_ cap: AIProviderModel.Capability) -> String {
        switch cap {
        case .chat: return "文字对话"
        case .image: return "图像生成"
        case .realtimeVoice: return "实时语音"
        case .audio: return "音频 / 转写"
        case .other: return "专用工具"
        }
    }

    private func fetchModels(for provider: WuMindProvider) {
        guard !refreshing, let mp = provider.multiProvider, let key = provider.apiKey() else { return }
        refreshing = true
        refreshError = nil
        Task { @MainActor in
            defer { refreshing = false }
            do {
                let probe = try await MultiProviderAIClient().probeAndListModels(
                    provider: mp,
                    apiKey: key,
                    baseURL: AIProviderEndpoints.baseURL(for: mp)
                )
                store.updateCachedModels(probe.models, for: provider, verifiedHost: probe.host)
                if probe.models.filter(\.supportsTextChat).isEmpty {
                    refreshError = "服务商（\(probe.host)）目录可读，但未返回标准文字对话模型，可在上方手动输入模型编号后点「试跑」。"
                }
            } catch let diag as AIProviderDiagnosticError {
                refreshError = diag.errorDescription
                store.markProviderFailed(provider, host: diag.host, summary: diag.shortBadgeSummary)
            } catch {
                let host = store.resolvedHost(for: provider)
                refreshError = "\((error as? LocalizedError)?.errorDescription ?? "未能获取模型列表。")\n[请求域名：\(host)]"
                store.markProviderFailed(provider, host: host, summary: "\(host) · 连接失败")
            }
        }
    }

    private func smokeTestModel(_ model: WuMindModelOption) {
        guard testingModelID == nil, let key = model.provider.apiKey() else { return }
        testingModelID = model.id
        smokeDiagnosticBanner = nil
        Task { @MainActor in
            defer { testingModelID = nil }
            if model.provider == .deepSeek {
                do {
                    let probe = try await MultiProviderAIClient().probeModelChat(
                        provider: .openAI,
                        model: AIProviderModel(id: model.id, displayName: model.displayName, supportsTextChat: true),
                        apiKey: key,
                        baseURL: "https://api.deepseek.com/v1"
                    )
                    store.markModelSmokePassed(.deepSeek, modelID: model.id, host: probe.host, endpointPath: probe.endpointPath, latencyMs: probe.latencyMs)
                    smokeDiagnosticBanner = "试跑成功：\(model.id)（\(probe.host)\(probe.endpointPath) · \(probe.latencyMs)ms）"
                    Haptics.success()
                } catch let diag as AIProviderDiagnosticError {
                    store.markModelSmokeFailed(.deepSeek, modelID: model.id, host: diag.host, httpStatus: diag.httpStatus, errorCode: diag.errorCode, detail: diag.sanitizedDetail ?? diag.shortBadgeSummary)
                    smokeDiagnosticBanner = "\(model.id) 试跑失败：\(diag.errorDescription ?? diag.shortBadgeSummary)"
                    Haptics.warning()
                } catch {
                    let msg = (error as? LocalizedError)?.errorDescription ?? "试跑失败"
                    store.markModelSmokeFailed(.deepSeek, modelID: model.id, host: "api.deepseek.com", httpStatus: nil, errorCode: nil, detail: msg)
                    smokeDiagnosticBanner = "\(model.id) 试跑失败：\(msg)"
                    Haptics.warning()
                }
                return
            }

            guard let mp = model.provider.multiProvider else { return }
            let baseURL = AIProviderEndpoints.baseURL(for: mp)
            do {
                let probe = try await MultiProviderAIClient().probeModelChat(
                    provider: mp,
                    model: AIProviderModel(id: model.id, displayName: model.displayName, supportsTextChat: true),
                    apiKey: key,
                    baseURL: baseURL
                )
                store.markModelSmokePassed(model.provider, modelID: model.id, host: probe.host, endpointPath: probe.endpointPath, latencyMs: probe.latencyMs)
                smokeDiagnosticBanner = "试跑成功：\(model.id)（\(probe.host)\(probe.endpointPath) · \(probe.latencyMs)ms）"
                Haptics.success()
            } catch let diag as AIProviderDiagnosticError {
                store.markModelSmokeFailed(
                    model.provider,
                    modelID: model.id,
                    host: diag.host,
                    httpStatus: diag.httpStatus,
                    errorCode: diag.errorCode,
                    detail: diag.sanitizedDetail ?? diag.shortBadgeSummary
                )
                smokeDiagnosticBanner = "\(model.id) 试跑失败：\(diag.errorDescription ?? diag.shortBadgeSummary)"
                Haptics.warning()
            } catch {
                let host = store.resolvedHost(for: model.provider)
                let msg = (error as? LocalizedError)?.errorDescription ?? "调用失败"
                store.markModelSmokeFailed(model.provider, modelID: model.id, host: host, httpStatus: nil, errorCode: nil, detail: msg)
                smokeDiagnosticBanner = "\(model.id) 试跑失败（\(host)）：\(msg)"
                Haptics.warning()
            }
        }
    }
}

// MARK: - Direct GitHub Repository Connector Sheet

struct WuMindGitHubSheet: View {
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

    private var pageBg: Color {
        DS.Palette.background
    }
    private var cardBg: Color {
        DS.Palette.cardSurface
    }
    private var cardBorder: Color {
        DS.Palette.hairline
    }

    private var filteredRepoFiles: [String] {
        guard let ctx = store.attachedGitHubContext else { return [] }
        let q = fileFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = q.isEmpty ? ctx.filePaths : ctx.filePaths.filter { $0.localizedCaseInsensitiveContains(q) }
        return Array(matches.prefix(40))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let ctx = store.attachedGitHubContext {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(ctx.repo.fullName, systemImage: "checkmark.seal.fill")
                                    .font(.headline)
                                    .foregroundStyle(.teal)
                                Spacer()
                                if ctx.repo.isPrivate {
                                    Text("私有")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.14), in: Capsule())
                                }
                            }
                            if !ctx.repo.description.isEmpty {
                                Text(ctx.repo.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("分支 \(ctx.repo.defaultBranch) · \(ctx.filePaths.count) 个文件 · \(ctx.recentCommits.count) 条提交 · README \(ctx.readmeExcerpt.isEmpty ? "无" : "已读取")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if !ctx.attachedFiles.isEmpty {
                                Divider()
                                Text("已附加源码文件（发送时自动带入）")
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

                            Button("断开此仓库", role: .destructive) {
                                Haptics.tap()
                                store.attachedGitHubContext = nil
                                statusMessage = "已断开 GitHub 仓库上下文。"
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .padding(14)
                        .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.teal.opacity(0.32), lineWidth: 1))

                        if !ctx.filePaths.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("点选附加源码文件（前 40 项）")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                TextField("筛选文件路径（如 Swift / View / Package）", text: $fileFilter)
                                    .font(.footnote)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                ForEach(filteredRepoFiles, id: \.self) { path in
                                    let attached = ctx.attachedFiles.contains { $0.path == path }
                                    Button {
                                        if attached { detachFile(path) } else { attachFile(path, in: ctx) }
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
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal)
                                            } else {
                                                Image(systemName: "plus.circle").foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(loadingFilePath != nil)
                                }
                            }
                            .padding(14)
                            .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                        }
                    }

                    // Connect any repo card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("连接任意 GitHub 仓库")
                            .font(.subheadline.weight(.bold))
                        TextField("输入 owner/repo 或 github.com 链接", text: $repoInput)
                            .font(.subheadline)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("wumind.github.repoInput")

                        Button {
                            connectRepo(repoInput)
                        } label: {
                            HStack(spacing: 8) {
                                if loadingRepo {
                                    ProgressView().controlSize(.small).tint(.white)
                                } else {
                                    Image(systemName: "link.badge.plus")
                                }
                                Text("连接并读取仓库上下文")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                (loadingRepo || repoInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    ? Color.secondary.opacity(0.35) : Color.teal,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(loadingRepo || repoInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("wumind.github.connect")

                        if let statusError {
                            Text(statusError).font(.caption).foregroundStyle(DS.Palette.danger)
                        }
                        if let statusMessage {
                            Text(statusMessage).font(.caption).foregroundStyle(.teal)
                        }
                        Text("公开仓库免 Token 直连；在对话中直接粘贴 github.com/owner/repo 链接也会自动抓取上下文。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                    if hasToken {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("我的 GitHub 仓库")
                                    .font(.subheadline.weight(.bold))
                                Spacer()
                                Button {
                                    fetchUserRepos()
                                } label: {
                                    HStack(spacing: 5) {
                                        if loadingUserRepos { ProgressView().controlSize(.mini) }
                                        Text(userRepos.isEmpty ? "拉取列表" : "刷新")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(.teal)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.teal.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(loadingUserRepos)
                            }
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
                                                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
                                                }
                                            }
                                            if !repo.description.isEmpty {
                                                Text(repo.description).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        if store.attachedGitHubContext?.repo.fullName == repo.fullName {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                        .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                    }

                    // Device-only PAT card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: hasToken ? "checkmark.shield.fill" : "key.fill")
                                .foregroundStyle(hasToken ? .green : .secondary)
                            Text(hasToken ? "已配置本机 GitHub Token（支持私有仓库）" : "GitHub Access Token（选填 · 仅存本机钥匙串）")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }

                        SecureField(hasToken ? "输入新 Token 可替换（ghp_ / github_pat_）" : "粘贴 Fine-grained PAT（仅需 Contents 只读）",
                                    text: $tokenDraft)
                            .font(.footnote)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("wumind.github.tokenInput")

                        HStack(spacing: 10) {
                            Button("保存 Token") {
                                saveToken()
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                MultiProviderAIClient.sanitizePastedKey(tokenDraft).isEmpty
                                    ? Color.secondary.opacity(0.35) : Color.teal,
                                in: Capsule()
                            )
                            .buttonStyle(.plain)
                            .disabled(MultiProviderAIClient.sanitizePastedKey(tokenDraft).isEmpty)

                            if hasToken {
                                Button("移除 Token", role: .destructive) {
                                    _ = Keychain.setGitHubToken("")
                                    hasToken = false
                                    userRepos = []
                                    statusMessage = "已移除本机 GitHub Token。"
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    .padding(14)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                }
                .padding(14)
            }
            .background(pageBg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
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

// MARK: - Dual-Model Comparison / Cross-Review Picker Sheet

private struct WuMindCompareTurnSheet: View {
    @ObservedObject var store: WuMindStore
    let conversationID: UUID
    let turn: WuMindTurn
    let onOpenModelHub: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: WuMindComparisonResult.Mode = .crossReview
    @State private var runningTargetID: String? = nil
    @State private var errorMessage: String? = nil

    private var targets: [WuMindStore.ComparisonTarget] {
        store.availableComparisonTargets(excludingModelLabel: turn.modelLabel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("对比模式", selection: $mode) {
                        ForEach(WuMindComparisonResult.Mode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("对比方式")
                }

                Section {
                    if targets.isEmpty {
                        AppEmptyStateCard(
                            icon: "text.bubble", title: "没有可选的第二个模型",
                            message: "在模型中心查看通道和可用模型。",
                            actionTitle: "打开模型中心", action: onOpenModelHub
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(targets) { target in
                            Button {
                                runCompare(target)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: target.provider.iconName)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(target.provider.brandColor, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(target.displayName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(target.channelLabel + (target.priceNote.map { " · \($0)" } ?? ""))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                    if runningTargetID == target.id {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Text(mode == .crossReview ? "开始复核" : "并排对比")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.indigo)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 4)
                                            .background(Color.indigo.opacity(0.11), in: Capsule())
                                    }
                                }
                            }
                            .disabled(runningTargetID != nil)
                        }
                    }
                } header: {
                    Text("第二个模型")
                } footer: {
                    Text("主答模型：\(turn.modelLabel)。复核或对比结果会直接附在本轮对话卡片下，清晰展示共识、依据与分歧，不会覆盖原回答。")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.danger)
                    }
                }
            }
            .appList()
            .navigationTitle("同题对比与交叉复核")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func runCompare(_ target: WuMindStore.ComparisonTarget) {
        guard runningTargetID == nil else { return }
        runningTargetID = target.id
        errorMessage = nil
        let selectedMode = mode
        Task { @MainActor in
            defer { runningTargetID = nil }
            do {
                _ = try await store.runModelComparison(
                    conversationID: conversationID,
                    turnID: turn.id,
                    mode: selectedMode,
                    target: target
                )
                Haptics.success()
                ToastCenter.shared.show("已完成 \(target.displayName) \(selectedMode.title)", style: .success)
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Haptics.warning()
            }
        }
    }
}

// MARK: - Thread-Shared Cross-Model Materials Manager Sheet

private struct WuMindSharedMaterialsSheet: View {
    @ObservedObject var store: WuMindStore
    let conversation: WuMindConversation
    @Environment(\.dismiss) private var dismiss

    private var materials: [WuMindThreadMaterial] {
        store.conversations.first(where: { $0.id == conversation.id })?.sharedMaterials ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                if materials.isEmpty {
                    AppEmptyStateCard(icon: "doc.on.doc", title: "暂无共享资料", message: "从聊天输入栏上传文件，同一对话的后续模型也能使用。")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(materials) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text.fill")
                                    .foregroundStyle(.indigo)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.filename)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(item.summaryBadge) · \(item.extractedText.count) 字已提取")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    store.removeSharedMaterial(item.id, from: conversation.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 48, height: 48)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("移除 \(item.filename)")
                            }
                        }
                    } header: {
                        Text("共享文件（\(materials.count)）")
                    } footer: {
                        Text("切换模型或发起模型复核时，当前对话会继续使用这些文件。移除文件后，后续对话不再附带。")
                    }
                }
            }
            .appList()
            .navigationTitle("对话共享资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

/// Archived Conversations management view (`⋯ → 已归档`).
/// Supports searching archived threads, opening them to read/continue with all messages & attachments intact,
/// and unarchiving back into the main list at their original `updatedAt` sort order with zero duplicates.
private struct WuMindArchivedConversationsSheet: View {
    @ObservedObject var store: WuMindStore
    let onOpenConversation: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredArchived: [WuMindConversation] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.archivedConversations }
        return store.archivedConversations.filter { convo in
            convo.title.localizedCaseInsensitiveContains(q)
                || convo.modelDisplayName.localizedCaseInsensitiveContains(q)
                || convo.turns.contains {
                    $0.question.localizedCaseInsensitiveContains(q)
                        || $0.answer.localizedCaseInsensitiveContains(q)
                }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredArchived.isEmpty {
                    AppEmptyStateCard(
                        icon: "archivebox",
                        title: searchText.isEmpty ? "暂无已归档对话" : "未找到匹配的对话",
                        message: searchText.isEmpty ? "在历史列表左滑或长按对话可将其归档。" : "试试其他标题、模型或消息内容。"
                    )
                    .padding(DS.Space.m)
                } else {
                    List {
                        Section {
                            ForEach(filteredArchived) { convo in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "archivebox.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(.indigo)
                                            .padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(convo.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
                                            HStack(spacing: 6) {
                                                Text(convo.modelDisplayName)
                                                Text("·")
                                                Text("\(convo.turns.count) 轮")
                                                let matCount = convo.sharedMaterials?.count ?? 0
                                                if matCount > 0 {
                                                    Text("·")
                                                    Text("\(matCount) 附件")
                                                }
                                            }
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            HStack(spacing: 8) {
                                                Text("原更新 \(convo.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                                if let archivedAt = convo.archivedAt {
                                                    Text("· 归档于 \(archivedAt.formatted(date: .abbreviated, time: .shortened))")
                                                }
                                            }
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        }
                                        Spacer(minLength: 6)
                                    }

                                    HStack(spacing: 8) {
                                        Button {
                                            Haptics.tap()
                                            onOpenConversation(convo.id)
                                        } label: {
                                            Label("打开对话", systemImage: "bubble.left.and.bubble.right")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button {
                                            Haptics.tap()
                                            _ = store.unarchiveConversation(convo.id)
                                            ToastCenter.shared.show("已取消归档，已恢复至原位置", style: .success)
                                        } label: {
                                            Label("取消归档", systemImage: "tray.and.arrow.up")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.indigo)
                                        .controlSize(.small)
                                        .accessibilityIdentifier("wumind.archived.unarchive")

                                        Spacer()
                                    }
                                    .padding(.top, 2)
                                }
                                .padding(.vertical, 4)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        _ = store.unarchiveConversation(convo.id)
                                        ToastCenter.shared.show("已取消归档，已恢复至原位置", style: .success)
                                    } label: {
                                        Label("取消归档", systemImage: "tray.and.arrow.up")
                                    }
                                    .tint(.indigo)
                                }
                            }
                        } header: {
                            Text("已归档对话（\(filteredArchived.count)）")
                        } footer: {
                            Text("取消归档后，对话会按原更新时间回到历史列表。")
                        }
                    }
                    .appList()
                }
            }
            .searchable(text: $searchText, prompt: "搜索已归档对话")
            .navigationTitle("已归档对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .accessibilityIdentifier("wumind.archived.sheet")
        }
    }
}

