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
    let onOpenAdvancedTool: (WuMindWorkspaceView.ToolboxDestination) -> Void
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerRow
                    studiosGrid
                    if toolQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        expandableRow("继续编辑", icon: "clock.arrow.circlepath",
                                      id: "wumind.workbench.continue", expanded: $showPipelines)
                        if showPipelines { multiStepPipelinesSection }
                        if !worksStore.works.isEmpty {
                            expandableRow(activeCount > 0 ? "任务 · \(activeCount) 项进行中" : "任务记录",
                                          icon: "tray", id: "wumind.workbench.queue", expanded: $showQueue)
                            if showQueue { taskQueueSection }
                        }
                        expandableRow("空间与账户", icon: "slider.horizontal.3",
                                      id: "wumind.workbench.manage", expanded: $showManagement)
                        if showManagement { workspaceToolsRow }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .frame(maxWidth: 660)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await worksStore.syncFromCloud() }
            searchBar
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
        [
            .init(id: "wumind.quick.image", title: "生图", icon: "photo", keywords: "图片 绘画 image") { onOpenTool(.image) },
            .init(id: "wumind.quick.video", title: "视频", icon: "video", keywords: "短剧 生成 剪辑 video") { onOpenTool(.video) },
            .init(id: "wumind.quick.ppt", title: "PPT", icon: "rectangle.on.rectangle.angled", keywords: "幻灯片 演示 汇报") { onOpenTool(.ppt) },
            .init(id: "wumind.quick.spatial3d", title: "3D 空间", icon: "cube", keywords: "建模 人物 建筑 CAD") { onOpenTool(.spatial3d) },
            .init(id: "deepSeek.chat.tender", title: "标书", icon: "doc.text", keywords: "招投标 文档") { onOpenTool(.tender) },
            .init(id: "wumind.quick.code", title: "编程", icon: "chevron.left.forwardslash.chevron.right", keywords: "代码 工程 code") { onOpenTool(.code) },
            .init(id: "wumind.quick.research", title: "深度调研", icon: "globe", keywords: "搜索 核验 联网") { onStartDeepResearch() },
            .init(id: "wumind.quick.plugins", title: "插件", icon: "puzzlepiece.extension", keywords: "连接器 GitHub") { onOpenInChatConnectors() },
            .init(id: "ai.providers.open", title: "全部工坊", icon: "square.grid.2x2", keywords: "工具 智能体") { onOpenTool(.hub) },
        ]
    }

    private var managementEntries: [StudioEntry] {
        [
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
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(elevatedSurface, in: Circle())
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
        .padding(.leading, 15)
        .padding(.trailing, 5)
        .frame(minHeight: 48)
        .background(elevatedSurface, in: Capsule())
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: 660)
        .frame(maxWidth: .infinity)
    }

    private var studiosGrid: some View {
        let query = toolQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = query.isEmpty ? studioEntries : (studioEntries + managementEntries).filter {
            ($0.title + " " + $0.keywords).localizedCaseInsensitiveContains(query)
        }
        return Group {
            if matches.isEmpty {
                Text("没有匹配的工具")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                studioGrid(matches)
            }
        }
    }

    private func studioGrid(_ entries: [StudioEntry]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
            ForEach(entries) { entry in
                Button {
                    Haptics.tap()
                    searchFocused = false
                    entry.action()
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: entry.icon)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(entry.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(entry.id)
            }
        }
    }

    private func expandableRow(_ title: String, icon: String, id: String, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityValue(expanded.wrappedValue ? "已展开" : "已收起")
    }

    // MARK: - Live Multi-Step Workflows (Real State from PPT & 3D Studios)

    private var multiStepPipelinesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1) PPT Multi-Step Pipeline
            Button {
                Haptics.tap()
                onOpenAdvancedTool(.ppt)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.on.rectangle.angled")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(pptStore.deck?.title ?? "汇报 PPT 多步流水线")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        if pptStore.generating {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text(pptStore.deck != nil ? "继续修改" : "开始")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.13), in: Capsule())
                        }
                    }

                    let step1Done = !pptStore.sourceAttachments.isEmpty || pptStore.rawExcelData != nil
                    let step2Done = pptStore.deck != nil
                    let step3Done = pptStore.lastSurgicalEditSummary != nil
                    let step4Done = pptStore.exportedPPTXURL != nil
                    HStack(spacing: 6) {
                        pipelineStepChip("1.上传资料", done: step1Done)
                        pipelineStepChip("2.生成大纲", done: step2Done)
                        pipelineStepChip("3.单页精修", done: step3Done)
                        pipelineStepChip("4.导出PPTX", done: step4Done)
                    }

                    if pptStore.generating && !pptStore.stageLabel.isEmpty {
                        Text(pptStore.stageLabel)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if let deck = pptStore.deck {
                        Text("已生成 \(deck.slides.count) 页 · \(pptStore.lastSurgicalEditSummary ?? "点进可局部修改任意单页并导出新版本")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("上传 Word / Excel / Logo → 生成 10 页管理层汇报 → 修改指定页 → 导出可编辑 .pptx")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(13)
                .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wumind.workbench.pipeline.ppt")

            // 2) 3D Blueprint & Parametric Editing Pipeline
            Button {
                Haptics.tap()
                onOpenAdvancedTool(.spatial3d)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "cube.transparent")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.teal)
                        Text(spatial3DStore.scene.title.isEmpty ? "3D 空间与图纸转场景" : spatial3DStore.scene.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        if spatial3DStore.isGenerating {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("继续编辑")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.teal)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.teal.opacity(0.13), in: Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        pipelineStepChip("1.图纸/文本", done: spatial3DStore.activeBlueprintDraft != nil || !spatial3DStore.scene.nodes.isEmpty)
                        pipelineStepChip("2.生成场景", done: !spatial3DStore.scene.nodes.isEmpty)
                        pipelineStepChip("3.门洞精修", done: spatial3DStore.sceneRevision > 0)
                        pipelineStepChip("4.导出GLB", done: spatial3DStore.exportedGLBURL != nil)
                    }

                    Text(spatial3DStore.isGenerating
                         ? spatial3DStore.generationStatus
                         : "当前场景含 \(spatial3DStore.scene.nodes.count) 个可独立编辑构件 · 支持户型图纠偏与毫米级门洞同步")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(13)
                .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wumind.workbench.pipeline.3d")
        }
    }

    private func pipelineStepChip(_ title: String, done: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(done ? .green : .secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background((done ? Color.green : Color.secondary).opacity(0.10), in: Capsule())
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
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text(statusFilter == .all ? "暂无进行中或历史任务" : "当前筛选「\(statusFilter.rawValue)」暂无任务")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("点击上方「新建任务」或在任意工坊发起生成，所有步骤、失败原因与最终产物都会自动归档在此。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
                .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
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
                    if let thumb = worksStore.loadThumbnailImage(for: work) {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: work.workType.iconName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
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

    // MARK: - Workspace Management Shortcuts (Projects, Schedules, Skills, Wallet/Channel)

    private var workspaceToolsRow: some View {
        studioGrid(managementEntries)
    }
}
