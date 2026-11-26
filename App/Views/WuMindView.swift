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
    var isStandaloneFullScreen: Bool = false
    var onHideDutyMode: (() -> Void)? = nil
    var onRestoreDutyMode: (() -> Void)? = nil

    @State private var draft = ""
    @State private var drawerOpen = false
    @State private var drawerSearch = ""
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
    @State private var regBusy = false
    @State private var regError: String? = nil
    @State private var isTemporaryChat = false
    @State private var temporaryTurns: [WuMindTurn] = []
    @State private var temporaryGenerating = false
    @State private var temporaryTask: Task<Void, Never>? = nil
    @State private var showingFileImporter = false
    @State private var showingPhotoPicker = false
    @State private var pickedPhotoItem: PhotosPickerItem? = nil
    @State private var importingAttachment = false
    @State private var showingKeyFor: WuMindProvider?
    @State private var confirmingClearAll = false
    @State private var renamingConversation: WuMindConversation?
    @State private var renameDraft = ""

    @StateObject private var dictation = WuMindDictationController()
    @State private var dictationSeed = ""

    @State private var following = true
    @State private var compactedBannerExpanded = false
    @State private var comparingTurn: WuMindTurn? = nil
    @State private var showingSharedMaterialsSheet = false

    @State private var toolboxPath: [ToolboxDestination] = []
    @State private var selectedMainTab: WuMindMainTab = .chat
    @FocusState private var composerFocused: Bool

    private let bottomAnchor = "wumind.chat.bottom"
    private let unsentDraftKey = "wumind.unsentDraft.v1"
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

    private func dismissKeyboard() {
        composerFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func openTool(_ destination: ToolboxDestination) {
        dismissKeyboard()
        toolboxPath.append(destination)
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
                    if !composerFocused || selectedMainTab != .chat {
                        mainTabSwitcherBar
                    }
                    upstreamBalanceNoticeBanner
                    if selectedMainTab == .chat {
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
                        composerBar
                    } else if selectedMainTab == .workbench {
                        WuMindWorkbenchView(
                            store: store,
                            elevatedSurface: elevatedSurface,
                            subtleBorder: subtleBorder,
                            onOpenTool: { dest in openTool(dest) },
                            onOpenProjects: { showingProjects = true },
                            onOpenSchedules: { showingSchedules = true },
                            onOpenSkills: { showingSkills = true },
                            onOpenInChatConnectors: { showingInChatConnectors = true },
                            onOpenWallet: { showingWallet = true },
                            onOpenModelHub: { showingModelHub = true },
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
                Group {
                    switch dest {
                    case .hub: AIProviderListView()
                    case .live: AILiveCallView()
                    case .image: AIImageToolView()
                    case .video: AIVideoToolView()
                    case .spatial3d: WuMindSpatial3DStudioView()
                    case .agentOS: WuMindAgentWorkspaceView()
                    case .ppt: WuMindPPTStudioView()
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
        .onChange(of: draft) { latest in
            // Persist unsent draft so offline drops / app switches NEVER lose user input!
            if latest.isEmpty {
                UserDefaults.standard.removeObject(forKey: unsentDraftKey)
            } else {
                UserDefaults.standard.set(latest, forKey: unsentDraftKey)
            }
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
                        openTool(dest)
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
        .sheet(item: $comparingTurn) { turn in
            if let cid = store.activeConversationID {
                WuMindCompareTurnSheet(
                    store: store,
                    conversationID: cid,
                    turn: turn,
                    onOpenModelHub: {
                        comparingTurn = nil
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 220_000_000)
                            showingModelHub = true
                        }
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
        .sheet(isPresented: $showingModelHub) {
            WuMindModelHubSheet(
                store: store,
                onEditKey: { provider in
                    showingModelHub = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        showingKeyFor = provider
                    }
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
        .sheet(isPresented: $showingMyWorks) {
            myWorksSheetContent
        }
        .onAppear(perform: handleWorkspaceAppear)
        .onDisappear {
            // Keep active AI generation running seamlessly in the background when leaving WUMIND!
            temporaryTask?.cancel()
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
        if regNameDraft.isEmpty {
            let candidate = AppAccountManager.shared.externalProfile?.nickname
                ?? AppStore.shared.myRosterName
                ?? ""
            if !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                regNameDraft = candidate
            }
        }
        if draft.isEmpty,
           let savedDraft = UserDefaults.standard.string(forKey: unsentDraftKey),
           !savedDraft.isEmpty {
            draft = savedDraft
        }
        if store.channel == .managed && store.hasGatewayURL {
            Task { @MainActor in
                try? await store.syncManagedGatewayConfig()
                if Keychain.wumindGatewayUserToken != nil {
                    try? await store.refreshManagedAccount()
                }
            }
        }
    }

    // MARK: - Mandatory WUMIND User Registration Gate (Internal Duty + External Users Alike)

    private var mandatoryRegistrationOverlay: some View {
        ZStack {
            canvasBackground.opacity(0.98).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.indigo)
                Text("进入 WUMIND 前请先注册用户")
                    .font(.title3.weight(.bold))
                Text("无论是否为值班内部成员，进入 WUMIND 均需先注册您的个人 WUMIND 账号，以便独立保存「我的作品」、账本明细与跨设备同步。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 10) {
                    TextField("请输入您的姓名或常用昵称（必填）", text: $regNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .accessibilityIdentifier("wumind.registration.nameInput")

                    if let regError {
                        Text(regError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        submitMandatoryRegistration()
                    } label: {
                        HStack {
                            Spacer()
                            if regBusy { ProgressView().tint(.white).controlSize(.small) }
                            Text("注册并进入 WUMIND")
                                .font(.subheadline.weight(.bold))
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(regBusy || regNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("wumind.registration.submit")
                }
                .padding(16)
                .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))

                if let onClose {
                    Button("暂不进入，返回上一页") {
                        onClose()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 440)
        }
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
                ToastCenter.shared.show("注册成功 · \(store.managedAccountID)", style: .success)
            } catch {
                regError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
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
                showingModelHub = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.channel == .managed ? "bolt.shield.fill" : store.activeProviderForDisplay.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(store.channel == .managed ? Color.indigo : store.activeProviderForDisplay.brandColor)
                    Text("WUMIND")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("· \(compactHeaderModelName)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
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

            HStack(spacing: 6) {
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
                        .foregroundStyle(isTemporaryChat ? .white : .primary)
                        .frame(width: 36, height: 36)
                        .background(
                            isTemporaryChat ? Color.orange : elevatedSurface,
                            in: Circle()
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isTemporaryChat ? Color.orange : subtleBorder,
                                    style: StrokeStyle(lineWidth: 1.2, dash: isTemporaryChat ? [] : [3, 2.5])
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(generating)
                .accessibilityLabel(isTemporaryChat ? "退出临时聊天" : "开启临时聊天")
                .accessibilityIdentifier("wumind.tempChat.toggle")

                Button {
                    Haptics.tap()
                    if isTemporaryChat {
                        temporaryTask?.cancel()
                        temporaryGenerating = false
                        temporaryTurns = []
                    } else {
                        store.startNewConversation()
                    }
                    store.clearAttachments()
                    draft = ""
                    selectedMainTab = .chat
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(elevatedSurface, in: Circle())
                        .overlay(Circle().strokeBorder(subtleBorder, lineWidth: 1))
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
                        draft = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(elevatedSurface, in: Circle())
                            .overlay(Circle().strokeBorder(subtleBorder, lineWidth: 1))
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
                            .frame(width: 36, height: 36)
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
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(canvasBackground)
    }

    private var mainTabSwitcherBar: some View {
        HStack(spacing: 4) {
            ForEach(WuMindMainTab.allCases) { tab in
                let active = selectedMainTab == tab
                Button {
                    dismissKeyboard()
                    Haptics.select()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selectedMainTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(active ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        active ? activeAccentColor : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityID)
            }
        }
        .padding(3)
        .background(elevatedSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(subtleBorder, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .background(canvasBackground)
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

    private var transcriptView: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if turns.isEmpty {
                        welcomeCanvas
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
                                    streamSmoothMode: store.preferences.streamSmoothMode,
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
                                    isGenerating: turn.state == .generating,
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
                            .background(elevatedSurface, in: Capsule())
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
        VStack(spacing: 24) {
            Spacer(minLength: 42)

            // 1. Serene ChatGPT / Gemini Flagship Greeting (Zero Home Clutter)
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isTemporaryChat
                                    ? [Color.orange, Color.pink]
                                    : [
                                        Color(red: 0.24, green: 0.48, blue: 1.0),
                                        Color(red: 0.54, green: 0.34, blue: 0.96),
                                        Color(red: 0.14, green: 0.74, blue: 0.80)
                                    ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 54, height: 54)
                        .shadow(color: (isTemporaryChat ? Color.orange : Color(red: 0.30, green: 0.46, blue: 1.0)).opacity(0.28), radius: 16, y: 6)
                    Image(systemName: isTemporaryChat ? "eye.slash.fill" : "sparkles")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text(isTemporaryChat ? "临时聊天" : "今天想做什么？")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                if isTemporaryChat {
                    Text("无痕对话 · 关闭即销毁，不保存历史与长期记忆")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // 2. Maximum 3 Clean Flagship Starter Pills
            VStack(spacing: 10) {
                if !AppAccountManager.shared.isExternalRestricted && !isStandaloneFullScreen {
                    minimalStarterPill(
                        icon: "calendar.badge.clock",
                        color: .indigo,
                        title: "今日值班与休息查询",
                        id: "wumind.starter.dutyToday"
                    ) {
                        draft = "今天谁值班、哪组休息、谁请假或出差？"
                        composerFocused = true
                    }
                } else {
                    minimalStarterPill(
                        icon: "globe.asia.australia.fill",
                        color: .blue,
                        title: "联网核验调研",
                        id: "wumind.starter.webResearch"
                    ) {
                        store.webSearchEnabled = true
                        draft = "请帮我联网查证并整理最新进展，标注原文来源："
                        composerFocused = true
                    }
                }

                minimalStarterPill(
                    icon: "rectangle.on.rectangle.angled",
                    color: .orange,
                    title: "上传文档 / 表格制作 PPT",
                    id: "wumind.starter.ppt"
                ) {
                    openTool(.ppt)
                }

                minimalStarterPill(
                    icon: "square.grid.2x2.fill",
                    color: .purple,
                    title: "前往工作台（生图 · 视频 · 3D · 标书）",
                    id: "wumind.starter.workbench"
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selectedMainTab = .workbench
                    }
                }
            }
            .frame(maxWidth: 420)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
    }

    private func minimalStarterPill(
        icon: String,
        color: Color,
        title: String,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12), in: Circle())
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: - Flagship Multi-Model Capsule Composer

    private var composerPlaceholder: String {
        if !store.pendingAttachments.isEmpty {
            return "针对已上传的 \(store.pendingAttachments.count) 个附件提问…"
        }
        if let proj = store.activeProject {
            return "在项目「\(proj.name)」中提问（已共享指令与 \(proj.knowledgeDocs.count) 份资料）…"
        }
        if let repo = store.attachedGitHubContext {
            return "结合 \(repo.repo.fullName) 提问，或输入消息…"
        }
        if let skill = store.activeSkill {
            return "以「\(skill.name)」模式向 WUMIND 提问…"
        }
        return "向 WUMIND 提问，可开启智能体、上传文件或连接项目…"
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
                WuMindComposerAttachmentsStrip(
                    store: store,
                    dictation: dictation,
                    importingAttachment: importingAttachment,
                    isTemporaryChat: isTemporaryChat,
                    cleanedDraft: cleanedDraft,
                    liveEstimatedTokens: liveContextPlan.estimatedTokens,
                    onOpenProjects: {
                        dismissKeyboard()
                        showingProjects = true
                    },
                    onOpenSkills: {
                        dismissKeyboard()
                        showingSkills = true
                    },
                    onOpenGitHub: {
                        dismissKeyboard()
                        showingGitHub = true
                    },
                    onOpenSharedMaterials: {
                        dismissKeyboard()
                        showingSharedMaterialsSheet = true
                    }
                )

                WuMindComposerTextInput(
                    placeholder: composerPlaceholder,
                    draft: $draft,
                    generating: generating,
                    composerFocused: $composerFocused
                )

                WuMindComposerActionButtons(
                    store: store,
                    activeAccentColor: activeAccentColor,
                    generating: generating,
                    importingAttachment: importingAttachment,
                    isFocused: composerFocused,
                    isOverLimit: draft.utf8.count > questionLimit,
                    canSend: canSend,
                    canManualCompact: canManualCompact,
                    liveUsageRatio: liveContextPlan.usageRatio,
                    liveEstimatedTokens: liveContextPlan.estimatedTokens,
                    compactModelTitle: compactComposerModelTitle,
                    headerModelTitle: headerModelTitle,
                    onOpenSkills: {
                        dismissKeyboard()
                        Haptics.tap()
                        showingSkills = true
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
                            temporaryGenerating = false
                        } else {
                            store.stopGeneration()
                        }
                    },
                    onSend: requestSend
                )
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
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.06), radius: 8, y: 3)
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
                        selectedMainTab = .chat
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

                // Conversation List (Pinned section + Recent section)
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
                            let pinned = filtered.filter(\.isPinned)
                            let recent = filtered.filter { !$0.isPinned }
                            if !pinned.isEmpty {
                                Text("置顶对话")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 4)
                                ForEach(pinned) { convo in
                                    drawerConversationRow(convo)
                                }
                                if !recent.isEmpty {
                                    Text("最近对话")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.top, 8)
                                }
                            }
                            ForEach(recent) { convo in
                                drawerConversationRow(convo)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.immediately)

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

    private func requestSend() {
        guard canSend else { return }
        dismissKeyboard()
        // Local intranet Duty queries run 100% on-device with zero external LLM calls,
        // so they must work immediately regardless of API key / gateway / active model configuration.
        if store.pendingAttachments.isEmpty,
           WuMindDutyQueryEngine.classifyIntent(
               prompt: cleanedDraft,
               timezoneID: Calendar.app.timeZone.identifier,
               knownPeople: Array(AppStore.shared.roster.keys)
           ) != nil {
            beginRequest()
            return
        }
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

    private func enterTemporaryChat() {
        temporaryTask?.cancel()
        temporaryGenerating = false
        temporaryTurns = []
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            isTemporaryChat = true
        }
        ToastCenter.shared.show("已进入临时聊天（不记录历史、不读写记忆）", style: .success)
    }

    private func exitTemporaryChat() {
        temporaryTask?.cancel()
        temporaryGenerating = false
        temporaryTurns = []
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            isTemporaryChat = false
        }
    }

    private func beginRequest() {
        dictation.stop()
        let userText = cleanedDraft
        let attachments = store.pendingAttachments
        guard !generating, (!userText.isEmpty || !attachments.isEmpty), userText.utf8.count <= questionLimit else { return }

        let displayQuestion = userText.isEmpty ? "请帮我精读并分析我上传的附件内容" : userText
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
        let autoRepoName = store.attachedGitHubContext == nil ? WuMindGitHubClient.detectRepoInText(displayQuestion) : nil

        draft = ""
        store.clearAttachments()
        following = true

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
            autoRepoName: autoRepoName
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

        temporaryGenerating = true

        // Notice: temporary mode intentionally omits long-term user memories!
        let systemPrompt = "你是 WUMIND AI 助手。当前处于「临时无痕聊天」模式，请直接、专业、清晰地回答用户问题。"

        temporaryTask?.cancel()
        temporaryTask = Task { @MainActor in
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
            temporaryGenerating = false
        }
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
        if !streamBuffer.answer.isEmpty {
            liveTurn.answer = streamBuffer.answer
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
            isLast: true,
            isGenerating: true,
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

private struct WuMindTurnView: View {
    let turn: WuMindTurn
    let isLast: Bool
    let isGenerating: Bool
    var streamSmoothMode: Bool = true
    var activeAgentPhase: String? = nil
    var inlineStatusKind: WuMindStreamBuffer.InlineStatusKind? = nil
    var inlineStatusText: String? = nil
    let thinkingStartedAt: Date?
    let elevatedSurface: Color
    let subtleBorder: Color
    let onCopy: (String) -> Void
    let onRetryPrompt: (String) -> Void
    let onRegenerate: () -> Void
    let onManageKey: () -> Void
    let onOpenWallet: () -> Void
    var onCompare: (() -> Void)? = nil
    var onAdoptComparison: ((UUID) -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var thinkingExpanded = true
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

                // Reference-Recording Single Shared Inline Status Row (real event-driven: searching -> reading -> agent)
                let activeInlineText = isGenerating ? (inlineStatusText ?? activeAgentPhase) : nil
                if (isGenerating && (activeInlineText != nil || turn.assistantIntroLead != nil)) {
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
                    WuMindMarkdownView(
                        text: turn.answer,
                        isStreaming: isGenerating && streamSmoothMode,
                        elevatedSurface: elevatedSurface,
                        subtleBorder: subtleBorder,
                        onCopyCode: onCopy
                    )
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
                            if let started = thinkingStartedAt {
                                TimelineView(.periodic(from: started, by: 1.0)) { context in
                                    let sec = max(1, Int(context.date.timeIntervalSince(started).rounded(.down)) + 1)
                                    Text("正在连接模型并生成… \(sec)s")
                                        .font(.footnote.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("正在连接模型并生成…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
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
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.indigo)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.indigo.opacity(0.11), in: Capsule())
                                        .overlay(Capsule().strokeBorder(Color.indigo.opacity(0.28), lineWidth: 0.9))
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

                        if turn.firstTokenMs != nil || turn.totalLatencyMs != nil {
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
                        Text("已停止生成（未完成片段不会带入下一轮上下文）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        if isLast {
                            HStack(spacing: 8) {
                                Button("立即重试发送", action: onRegenerate)
                                    .font(.caption.weight(.bold))
                                    .buttonStyle(.borderedProminent)
                                    .tint(.indigo)
                                    .accessibilityIdentifier("wumind.turn.retryNow")
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
                    if isCurrentlyThinking, let started = thinkingStartedAt {
                        TimelineView(.periodic(from: started, by: 1.0)) { context in
                            let sec = max(1, Int(context.date.timeIntervalSince(started).rounded(.down)) + 1)
                            Text("正在深度思考… \(sec)s")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(thinkingHeaderTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
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
        case numbered(index: String, text: String)
        case paragraph(String)
    }

    private struct RichSegment: Identifiable {
        let id: Int
        let kind: RichSegmentKind
    }

    var body: some View {
        if isStreaming {
            let blocks = parseBlocks(text)
            VStack(alignment: .leading, spacing: 11) {
                ForEach(blocks) { block in
                    if let lang = block.language {
                        codeCard(language: lang, code: block.content, selectable: false)
                    } else {
                        streamingProseView(block.content)
                    }
                }
            }
        } else {
            let segments = WuMindRichContentParser.splitSegments(text)
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
    private func streamingProseView(_ raw: String) -> some View {
        let chunks = chunkForStreaming(raw)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                Text(chunk)
                    .font(.system(size: 15.8))
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Completed-message flagship editorial renderer: Apple/Claude-grade typographic hierarchy,
    /// generous line rhythm, numbered pills, accented headings, and soft blockquote cards.
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
                    if level == 1 {
                        markdownText(headingText)
                            .font(.system(size: 21, weight: .bold))
                            .tracking(-0.3)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                    } else if level == 2 {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.indigo)
                                    .frame(width: 3.5, height: 17)
                                markdownText(headingText)
                                    .font(.system(size: 18, weight: .bold))
                                    .tracking(-0.2)
                            }
                            Rectangle()
                                .fill(subtleBorder)
                                .frame(height: 0.7)
                        }
                        .padding(.top, 8)
                    } else {
                        markdownText(headingText)
                            .font(.system(size: 16.2, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.top, 5)
                    }
                case .quote(let quoteText):
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.indigo.opacity(0.75))
                            .frame(width: 3)
                        markdownText(quoteText)
                            .font(.system(size: 14.8))
                            .foregroundStyle(.secondary)
                            .lineSpacing(5)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                case .bullet(let bulletText):
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(Color.indigo.opacity(0.72))
                            .frame(width: 5.5, height: 5.5)
                            .padding(.top, 8)
                        markdownText(bulletText)
                            .font(.system(size: 15.8))
                            .lineSpacing(6)
                    }
                case .numbered(let index, let itemText):
                    HStack(alignment: .top, spacing: 9) {
                        Text(index)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.indigo)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.indigo.opacity(0.12), in: Circle())
                            .padding(.top, 2)
                        markdownText(itemText)
                            .font(.system(size: 15.8))
                            .lineSpacing(6)
                    }
                case .paragraph(let bodyText):
                    markdownText(bodyText)
                        .font(.system(size: 15.8))
                        .lineSpacing(6)
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

// MARK: - Flagship Multi-Provider Model, Verification & Capability Center

@MainActor
private struct WuMindModelHubSheet: View {
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
    let onEditKey: (WuMindProvider) -> Void
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
        onEditKey: @escaping (WuMindProvider) -> Void,
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
        isDark ? Color(red: 0.04, green: 0.045, blue: 0.065) : Color(red: 0.955, green: 0.96, blue: 0.98)
    }
    private var cardBg: Color {
        isDark ? Color(red: 0.10, green: 0.11, blue: 0.145) : Color.white
    }
    private var cardBorder: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
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
                                .padding(.vertical, 8)
                                .background(
                                    active ? (isDark ? Color.white : Color.black) : Color.secondary.opacity(0.11),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
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
                                        Text(ch == .managed ? "WUMIND 内置" : "自带 API（全量模型）")
                                            .font(.caption2.weight(.bold))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(active ? .white : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6.5)
                                    .background(
                                        active ? (ch == .managed ? Color.indigo : viewingProvider.brandColor) : Color.secondary.opacity(0.10),
                                        in: Capsule()
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("wumind.channel.\(ch.rawValue)")
                            }
                        }

                        if store.channel == .ownAPI {
                            // 5-Column Full-Width Provider Switcher (Zero horizontal scroll!)
                            HStack(spacing: 5) {
                                ForEach(WuMindProvider.allCases) { provider in
                                    let selected = provider == viewingProvider
                                    let ver = store.verification(for: provider)
                                    Button {
                                        Haptics.select()
                                        viewingProvider = provider
                                        refreshError = nil
                                        smokeDiagnosticBanner = nil
                                        query = ""
                                        manualModelID = ""
                                    } label: {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(ver?.dotColor ?? Color.secondary.opacity(0.35))
                                                .frame(width: 6, height: 6)
                                            Text(provider.shortName)
                                                .font(.system(size: 11.5, weight: selected ? .bold : .medium))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.75)
                                        }
                                        .foregroundStyle(selected ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 7.5)
                                        .background(
                                            selected ? provider.brandColor : Color.secondary.opacity(0.11),
                                            in: Capsule()
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("wumind.provider.\(provider.rawValue)")
                                }
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
            WuMindHubHeroBanner(
                title: "WUMIND 内置计费通道",
                subtitle: "免自备 Key · 统一账单透明扣费",
                icon: "bolt.shield.fill",
                colors: [Color.indigo, Color(red: 0.42, green: 0.28, blue: 0.88)],
                chips: [
                    ("当前余额", store.managedBalanceYuan.map { String(format: "¥%.2f", $0) } ?? "¥0.00"),
                    ("可用模型", "\(store.enabledManagedModels.count) 个")
                ]
            )

            Button {
                onOpenWallet()
            } label: {
                HStack {
                    Label("打开钱包余额、用量与充值教程", systemImage: "creditcard.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
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
                        onEditKey(viewingProvider)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(viewingProvider.brandColor, in: Capsule())
                    .buttonStyle(.plain)
                }

                // 2-Column Honest Verification Meter: 目录可读 vs 已试跑可用
                HStack(spacing: 8) {
                    statusMetricTile(
                        title: "目录可读（拉取列表）",
                        value: totalChatCount > 0 ? "\(totalChatCount) 个聊天模型" : (ver?.status == .failed ? "读取失败" : "未拉取"),
                        color: totalChatCount > 0 ? .blue : .secondary
                    )
                    statusMetricTile(
                        title: "实测可用（已试跑成功）",
                        value: verifiedCount > 0 ? "\(verifiedCount) 个已验证" : "0 个 · 点右侧试跑",
                        color: verifiedCount > 0 ? .green : .orange
                    )
                }

                Text("目录可读只说明 Key 能列出模型，不代表每个模型都有调用权限或支持同一接口；点任意模型右侧「试跑」即可真实检验并显示精确域名与错误码。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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

                    // Manual Model ID input
                    HStack(spacing: 8) {
                        TextField("手动添加模型编号（如 gpt-5 / gemini-2.5-pro）", text: $manualModelID)
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
                Text("先点击上方「填写 Key」（中转站 Key 请同步填入自定义 HTTPS 接口地址），密钥仅存本机钥匙串。")
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
                                Text(smoke?.badgeText ?? "目录可读 · 待试跑")
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
            WuMindHubHeroBanner(
                title: "图像生成专用入口",
                subtitle: snapshot.useManagedGateway
                    ? "当前为 WuMind 内置模式：按网关实际启用的生图能力出图，不读取本机厂商 Key，不静默切自有 API"
                    : (snapshot.aihubmixConnection != nil
                        ? "当前为自有 API · AIHubMix：同一套 Base URL 与 Key 可直接驱动 GPT Image 与 Nano Banana 2，0 扣 WuMind 余额"
                        : "出图模型使用专用 Images / Gemini Native 协议，支持配置一套 AIHubMix 连接共享调用或按厂商直连"),
                icon: "photo.on.rectangle.angled",
                colors: [Color(red: 0.44, green: 0.22, blue: 0.78), Color(red: 0.76, green: 0.30, blue: 0.56)],
                chips: [
                    ("当前路由", routeLabel),
                    ("当前可用", "\(readyCount) / \(AIImageTool.models.count) 个")
                ]
            )

            ForEach(AIImageTool.models) { item in
                let availability = AIImageStudioAvailability.evaluate(
                    model: item,
                    hasReferenceImage: false,
                    snapshot: snapshot
                )
                let isReady = availability.isReady
                let subtitleText: String = {
                    if case .ready(_, _, let detail, _, _) = availability {
                        return "\(item.id) · \(detail)"
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
                        WuMindIconBadge(icon: "wand.and.stars", color: isReady ? .purple : .secondary)
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
                            .foregroundStyle(isReady ? Color.white : (snapshot.useManagedGateway ? Color.secondary : Color.orange))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                isReady
                                    ? Color.purple
                                    : (snapshot.useManagedGateway ? Color.secondary.opacity(0.14) : Color.orange.opacity(0.14)),
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
        let openAIKeyReady = Keychain.providerChatAPIKey(.openAI) != nil
        return VStack(alignment: .leading, spacing: 12) {
            WuMindHubHeroBanner(
                title: "实时语音通话专用入口",
                subtitle: "OpenAI Realtime WebSocket 全双工语音协议，与普通文本对话接口分开",
                icon: "phone.waveform.fill",
                colors: [Color(red: 0.08, green: 0.52, blue: 0.44), Color(red: 0.14, green: 0.36, blue: 0.78)],
                chips: [
                    ("实时语音模型", "\(AILiveProtocol.models.count) 个"),
                    ("OpenAI Key", openAIKeyReady ? "已就绪" : "待配置")
                ]
            )

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

    private func statusMetricTile(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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

private struct WuMindGitHubSheet: View {
    @ObservedObject var store: WuMindStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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

    private var isDark: Bool { colorScheme == .dark }
    private var pageBg: Color {
        isDark ? Color(red: 0.04, green: 0.045, blue: 0.065) : Color(red: 0.955, green: 0.96, blue: 0.98)
    }
    private var cardBg: Color {
        isDark ? Color(red: 0.10, green: 0.11, blue: 0.145) : Color.white
    }
    private var cardBorder: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
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
                    WuMindHubHeroBanner(
                        title: "GitHub 源码上下文连接器",
                        subtitle: "直连 GitHub 读取目录、README 与源码文件，让 WUMIND 精准审查与改代码",
                        icon: "chevron.left.forwardslash.chevron.right",
                        colors: [Color(red: 0.06, green: 0.42, blue: 0.48), Color(red: 0.12, green: 0.24, blue: 0.56)],
                        chips: [
                            ("连接状态", store.attachedGitHubContext?.repo.fullName ?? "未连接"),
                            ("本机 PAT", hasToken ? "支持私有仓" : "公开仓免密")
                        ]
                    )

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
                    Text("1. 选择复核 / 对比方式")
                }

                Section {
                    if targets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("暂未发现其他已就绪的模型")
                                .font(.subheadline.weight(.semibold))
                            Text("请先在模型中心配置至少一家 API Key，或切换到 WUMIND 内置通道即可使用双模型对比与交叉复核。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("打开模型中心配置") {
                                onOpenModelHub()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.indigo)
                        }
                        .padding(.vertical, 6)
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
                    Text("2. 选择第二家模型（自动携带本对话全部共享资料）")
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
                    Text("当前对话暂无共享资料。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("已跨模型共享的本对话资料（\(materials.count)）")
                    } footer: {
                        Text("你在本对话内切换 GPT / Claude / Gemini / DeepSeek / Grok 或发起双模型复核时，以上资料会自动延续，无需重新上传；移除后后续轮次将不再附带。")
                    }
                }
            }
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
