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
    let onSwitchToWorks: () -> Void
    let onStartDeepResearch: () -> Void

    private enum TaskStatusFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case active = "进行中"
        case completed = "已完成"
        case failed = "失败"
        var id: String { rawValue }
    }

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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerRow
                studiosGrid
                multiStepPipelinesSection
                taskQueueSection
                workspaceToolsRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            await worksStore.syncFromCloud()
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
        .accessibilityIdentifier("wumind.workbench")
    }

    // MARK: - Header + "+ 新建任务"

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("工作台")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("多步任务 · 后台跟踪 · 统一交付")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button { onOpenTool(.ppt) } label: {
                    Label("文档 / 表格 → AI 汇报 PPT", systemImage: "rectangle.on.rectangle.angled")
                }
                Button { onOpenTool(.image) } label: {
                    Label("文字 / 参考图生图", systemImage: "photo.on.rectangle.angled")
                }
                Button { onOpenTool(.video) } label: {
                    Label("AI 生视频 / 短剧分镜", systemImage: "video.badge.waveform.fill")
                }
                Button { onOpenTool(.spatial3d) } label: {
                    Label("户型图 / 文字 → 3D 场景", systemImage: "cube.transparent")
                }
                Button { onOpenTool(.tender) } label: {
                    Label("标书与专业长文档", systemImage: "doc.text.fill")
                }
                Button { onOpenTool(.code) } label: {
                    Label("代码与工程助手", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Divider()
                Button { onOpenTool(.agentOS) } label: {
                    Label("多步智能体总控（Loops & Graphs）", systemImage: "cpu.fill")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 12.5, weight: .bold))
                    Text("新建任务")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.indigo, in: Capsule())
            }
            .accessibilityIdentifier("wumind.workbench.newTask")
        }
    }

    // MARK: - Studio Launchers (Clean 4x2 Compact Grid)

    private var studiosGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 4), spacing: 9) {
            studioTile("生图", icon: "photo.on.rectangle.angled", color: .purple, id: "wumind.quick.image") {
                onOpenTool(.image)
            }
            studioTile("生视频", icon: "video.badge.waveform.fill", color: .pink, id: "wumind.quick.video") {
                onOpenTool(.video)
            }
            studioTile("写 PPT", icon: "rectangle.on.rectangle.angled", color: .orange, id: "wumind.quick.ppt") {
                onOpenTool(.ppt)
            }
            studioTile("3D 空间", icon: "cube.transparent", color: .teal, id: "wumind.quick.spatial3d") {
                onOpenTool(.spatial3d)
            }
            studioTile("写标书", icon: "doc.text.fill", color: .blue, id: "deepSeek.chat.tender") {
                onOpenTool(.tender)
            }
            studioTile("深度调研", icon: "magnifyingglass.circle.fill", color: .indigo, id: "wumind.quick.research") {
                onStartDeepResearch()
            }
            studioTile("插件连接", icon: "puzzlepiece.extension.fill", color: .mint, id: "wumind.quick.plugins") {
                onOpenInChatConnectors()
            }
            studioTile("全部工坊", icon: "square.grid.2x2.fill", color: .secondary, id: "ai.providers.open") {
                onOpenTool(.hub)
            }
        }
    }

    private func studioTile(_ title: String, icon: String, color: Color, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: - Live Multi-Step Workflows (Real State from PPT & 3D Studios)

    private var multiStepPipelinesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("多步骤续作流水线")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            // 1) PPT Multi-Step Pipeline
            Button {
                Haptics.tap()
                onOpenTool(.ppt)
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
                onOpenTool(.spatial3d)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("空间与账户管理")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                compactManageTile("项目空间", icon: "folder.fill", color: .indigo, badge: store.projects.isEmpty ? nil : "\(store.projects.count)", id: "wumind.dock.projects") {
                    onOpenProjects()
                }
                compactManageTile("定时任务", icon: "clock.arrow.circlepath", color: .orange, badge: store.scheduledTasks.filter(\.enabled).isEmpty ? nil : "\(store.scheduledTasks.filter(\.enabled).count)", id: "wumind.dock.schedules") {
                    onOpenSchedules()
                }
                compactManageTile("模型 / Key", icon: "cpu.fill", color: store.selectedProvider.brandColor, badge: nil, id: "wumind.dock.models") {
                    onOpenModelHub()
                }
                compactManageTile(store.channel == .managed ? "钱包计费" : "钱包通道", icon: "creditcard.fill", color: .indigo, badge: nil, id: "wumind.wallet.open") {
                    onOpenWallet()
                }
            }
        }
    }

    private func compactManageTile(_ title: String, icon: String, color: Color, badge: String?, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 30, height: 30)
                        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(color, in: Capsule())
                            .offset(x: 6, y: -4)
                    }
                }
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
