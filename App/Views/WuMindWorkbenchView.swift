import SwiftUI

/// Unified WUMIND Workbench（「工作台」）:
/// Consolidates multi-step creative workflows (PPT, 3D, Image, Video, Tender, Code, Agent OS),
/// live background task tracking (queued / in_progress / completed / failed),
/// and direct shortcuts to Projects, Schedules, Plugins, and Wallet.
struct WuMindWorkbenchView: View {
    @ObservedObject var store: WuMindStore
    @ObservedObject private var worksStore = WuMindWorksStore.shared
    @ObservedObject private var pptStore = WuMindPPTWorkflowStore.shared
    @ObservedObject private var spatial3DStore = WuMindSpatial3DStore.shared

    let elevatedSurface: Color
    let subtleBorder: Color
    let onOpenTool: (WuMindWorkspaceView.ToolboxDestination) -> Void
    let onOpenProjects: () -> Void
    let onOpenSchedules: () -> Void
    let onOpenSkills: () -> Void
    let onOpenInChatConnectors: () -> Void
    let onOpenWallet: () -> Void
    let onOpenModelHub: () -> Void
    let onOpenSettings: () -> Void
    let onSwitchToWorks: () -> Void
    let onStartDeepResearch: () -> Void

    private enum TaskStatusFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case active = "进行中"
        case completed = "已完成"
        case failed = "失败"
        var id: String { rawValue }
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var toolQuery = ""
    @FocusState private var searchFocused: Bool
    @State private var showPipelines = false
    @State private var showQueue = false
    @State private var showManagement = false
    @State private var statusFilter: TaskStatusFilter = .all
    @State private var selectedDetailWork: WuMindLocalWork? = nil
    @State private var refreshingWorkID: String? = nil
    @State private var retryingUploadID: String? = nil

    private var filteredTasks: [WuMindLocalWork] {
        let all = worksStore.works
        switch statusFilter {
        case .all: return all
        case .active: return all.filter(\.isInProgress)
        case .completed: return all.filter(\.isCompleted)
        case .failed: return all.filter(\.isFailed)
        }
    }

    private var activeCount: Int { worksStore.works.filter(\.isInProgress).count }
    private var completedCount: Int { worksStore.works.filter(\.isCompleted).count }
    private var failedCount: Int { worksStore.works.filter(\.isFailed).count }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760 && !dynamicTypeSize.isAccessibilitySize
            let columns = dynamicTypeSize.isAccessibilitySize || geometry.size.width < 340 ? 1 : 2
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    headerRow
                    searchBar
                    if wide && searchTerm.isEmpty {
                        HStack(alignment: .top, spacing: DS.Space.xl) {
                            directory(columns: columns)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                            activityAndManagement
                                .frame(width: min(300, geometry.size.width * 0.3))
                        }
                    } else {
                        directory(columns: columns)
                        if searchTerm.isEmpty {
                            activityAndManagement
                        }
                    }
                }
                .padding(.horizontal, wide ? DS.Space.xl : DS.Space.m)
                .padding(.vertical, DS.Space.m)
                .frame(maxWidth: 1120)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await worksStore.syncFromCloud() }
            .accessibilityIdentifier("wumind.workbench.scroll")
        }
        .sheet(item: $selectedDetailWork) { work in
            WuMindWorkDetailSheet(
                work: work,
                onReopenPPT: { deck, workID in
                    selectedDetailWork = nil
                    WuMindPPTWorkflowStore.shared.loadExternalDeck(deck, workID: workID)
                    onOpenTool(.ppt)
                },
                onReopenScene3D: { json, workID in
                    selectedDetailWork = nil
                    WuMindSpatial3DStore.shared.openProjectJSON(json, linkedWorkID: workID)
                    onOpenTool(.spatial3d)
                },
                onRetryWork: { failed in
                    selectedDetailWork = nil
                    switch failed.workType {
                    case .image: onOpenTool(.image)
                    case .video: onOpenTool(.video)
                    case .ppt: onOpenTool(.ppt)
                    case .scene3d: onOpenTool(.spatial3d)
                    case .document: onOpenTool(.tender)
                    case .code: onOpenTool(.code)
                    }
                }
            )
        }
        .task {
            worksStore.reloadForCurrentAccount()
            await worksStore.syncFromCloud()
        }
    }

    private struct StudioEntry: Identifiable {
        let id: String
        let title: String
        let icon: String
        let keywords: String
        let action: () -> Void
    }

    private var studioEntries: [StudioEntry] {
        WuMindStudioLink.all.map { studio in
            StudioEntry(id: studio.workbenchID, title: studio.title, icon: studio.icon, keywords: studio.keywords) {
                onOpenTool(studio.destination)
            }
        }
    }

    private var managementEntries: [StudioEntry] {
        [
            .init(id: "wumind.quick.research", title: "深度调研", icon: "globe", keywords: "搜索 核验 联网", action: onStartDeepResearch),
            .init(id: "wumind.quick.plugins", title: "插件", icon: "puzzlepiece.extension", keywords: "连接器 GitHub", action: onOpenInChatConnectors),
            .init(id: "ai.providers.open", title: "全部工具", icon: "square.grid.2x2", keywords: "工坊 工具") { onOpenTool(.hub) },
            .init(id: "wumind.dock.projects", title: "项目空间", icon: "folder", keywords: "知识库 项目", action: onOpenProjects),
            .init(id: "wumind.dock.schedules", title: "定时任务", icon: "clock", keywords: "提醒 日程", action: onOpenSchedules),
            .init(id: "wumind.dock.models", title: "模型与密钥", icon: "cpu", keywords: "API Key", action: onOpenModelHub),
            .init(id: "wumind.wallet.open", title: "钱包", icon: "wallet.bifold", keywords: "计费 充值 余额", action: onOpenWallet),
            .init(id: "wumind.dock.skills", title: "技能", icon: "bolt", keywords: "智能体 自定义", action: onOpenSkills),
            .init(id: "wumind.dock.works", title: "作品", icon: "tray", keywords: "历史 文件", action: onSwitchToWorks),
        ]
    }

    private var headerRow: some View {
        HStack {
            Text("工作台")
                .font(DS.Font.display)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)

            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
            .accessibilityIdentifier("wumind.workbench.settings")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索工具", text: $toolQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("wumind.workbench.search")
            if !toolQuery.isEmpty {
                Button {
                    toolQuery = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
                .accessibilityIdentifier("wumind.workbench.clearSearch")
            }
        }
        .padding(.horizontal, DS.Space.s)
        .frame(minHeight: 46)
        .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m))
    }

    private var searchTerm: String {
        toolQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func directory(columns: Int) -> some View {
        let matches = searchTerm.isEmpty ? studioEntries : (studioEntries + managementEntries).filter {
            ($0.title + " " + $0.keywords).localizedCaseInsensitiveContains(searchTerm)
        }
        return Group {
            if matches.isEmpty {
                Text("没有匹配的工具")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                studioGrid(matches, columns: columns)
            }
        }
    }

    private func studioGrid(_ entries: [StudioEntry], columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.m), count: columns),
                  alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                Button {
                    Haptics.tap()
                    searchFocused = false
                    entry.action()
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: entry.icon)
                            .font(.title3.weight(.regular))
                            .foregroundStyle(DS.Palette.iconPrimary)
                            .frame(width: 26)
                            .accessibilityHidden(true)
                        Text(entry.title)
                            .font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, DS.Space.xs)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { Divider() }
                .accessibilityIdentifier(entry.id)
            }
        }
    }

    private var activityAndManagement: some View {
        VStack(alignment: .leading, spacing: 0) {
            expandableRow("继续编辑", icon: "clock.arrow.circlepath",
                          id: "wumind.workbench.continue", expanded: $showPipelines)
            if showPipelines { multiStepPipelinesSection }
            Divider()
            if !worksStore.works.isEmpty {
                expandableRow(activeCount > 0 ? "任务 · \(activeCount) 项进行中" : "任务记录",
                              icon: "tray", id: "wumind.workbench.queue", expanded: $showQueue)
                if showQueue { taskQueueSection }
                Divider()
            }
            expandableRow("空间与账户", icon: "slider.horizontal.3",
                          id: "wumind.workbench.manage", expanded: $showManagement)
            if showManagement { studioGrid(managementEntries, columns: 1) }
        }
    }

    private func expandableRow(_ title: String, icon: String, id: String, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 10) {
                Label {
                    Text(title).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: icon)
                }
                .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 52)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityValue(expanded.wrappedValue ? "已展开" : "已收起")
    }

    // MARK: - Live Multi-Step Workflows (Real State from PPT & 3D Studios)

    private var multiStepPipelinesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            let deck = pptStore.deck
            documentRow(title: deck?.title ?? "新建幻灯片",
                        detail: pptStore.generating ? pptStore.stageLabel : deck.map { "\($0.slides.count) 页" },
                        icon: "rectangle.on.rectangle.angled",
                        busy: pptStore.generating,
                        action: { onOpenTool(.ppt) })
                .accessibilityIdentifier("wumind.workbench.pipeline.ppt")
            let scene = spatial3DStore.scene
            documentRow(title: scene.title.isEmpty ? "3D 空间" : scene.title,
                        detail: spatial3DStore.isGenerating ? spatial3DStore.generationStatus : "\(scene.nodes.count) 个构件",
                        icon: "cube",
                        busy: spatial3DStore.isGenerating,
                        action: { onOpenTool(.spatial3d) })
                .accessibilityIdentifier("wumind.workbench.pipeline.3d")
        }
        .padding(.bottom, DS.Space.s)
    }

    private func documentRow(title: String, detail: String?, icon: String, busy: Bool,
                             action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.s) {
                Image(systemName: icon).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if busy { ProgressView() }
            }
            .padding(.vertical, DS.Space.xs)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Unified Task Queue (In-Progress / Completed / Failed)

    private var taskQueueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("任务与产物队列")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Haptics.tap()
                    onSwitchToWorks()
                } label: {
                    Text("查看全部作品")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                statusFilterChip(.all, count: worksStore.works.count)
                statusFilterChip(.active, count: activeCount)
                statusFilterChip(.completed, count: completedCount)
                statusFilterChip(.failed, count: failedCount)
            }

            if filteredTasks.isEmpty {
                AppEmptyStateCard(icon: "tray", title: "暂无符合条件的任务", message: "在工具里创建作品后，可在这里查看进度。")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredTasks.prefix(12)) { work in
                        taskRow(work)
                    }
                }
            }
        }
    }

    private func statusFilterChip(_ filter: TaskStatusFilter, count: Int) -> some View {
        let selected = statusFilter == filter
        return Button {
            Haptics.select()
            statusFilter = filter
        } label: {
            Text("\(filter.rawValue) \(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? Color.indigo : elevatedSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.indigo : subtleBorder, lineWidth: 0.9))
        }
        .buttonStyle(.plain)
    }

    private func taskRow(_ work: WuMindLocalWork) -> some View {
        Button {
            selectedDetailWork = work
        } label: {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.11))
                        .frame(width: 50, height: 50)
                    Image(systemName: work.workType.iconName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(DS.Palette.iconPrimary)

                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(work.workType.title)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.indigo)
                        if work.versionNumber > 1 {
                            Text("v\(work.versionNumber)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        let color: Color = work.isCompleted ? .green : (work.isFailed ? .red : .orange)
                        Text(work.statusLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.14), in: Capsule())
                    }

                    Text(work.title.isEmpty ? "未命名任务" : work.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if work.isFailed, let err = work.errorMessage, !err.isEmpty {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    } else {
                        HStack(spacing: 6) {
                            Text(work.resolvedAssetSyncState.badgeTitle)
                                .font(.caption2)
                                .foregroundStyle(work.resolvedAssetSyncState == .synced ? .blue : (work.resolvedAssetSyncState == .failed ? .red : .secondary))
                            if let sz = work.formattedAssetSize {
                                Text("· \(sz)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if work.isCompleted,
                               (work.resolvedAssetSyncState == .failed || work.resolvedAssetSyncState == .pendingUpload),
                               worksStore.localAssetURL(for: work) != nil {
                                Button {
                                    retryingUploadID = work.id
                                    Task {
                                        await worksStore.retryAssetUpload(id: work.id)
                                        retryingUploadID = nil
                                    }
                                } label: {
                                    if retryingUploadID == work.id {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Text(work.resolvedAssetSyncState == .pendingUpload ? "继续同步" : "重试同步")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .buttonStyle(.plain)
                            } else if work.isInProgress && work.workType == .video && work.upstreamJobID != nil {
                                Button {
                                    refreshingWorkID = work.id
                                    Task {
                                        _ = await worksStore.refreshInProgressVideoWork(work)
                                        refreshingWorkID = nil
                                    }
                                } label: {
                                    if refreshingWorkID == work.id {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Text(work.isStatusUnknown ? "恢复查询" : "查询进度")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(11)
            .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

}
