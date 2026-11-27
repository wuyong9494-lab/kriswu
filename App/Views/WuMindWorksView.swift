import SwiftUI
import AVKit

/// Unified private 「我的作品」 gallery and per-studio 「历史」 sheet across
/// Image, Video, PPT, and 3D studios.
/// - Reopening / refreshing queries status read-only (never resubmits or double-charges).
/// - Displays thumbnail first and downloads full original on demand.
/// - Preserves full version lineage (`v1`, `v2`, ...) and failed task params for manual retry.
struct WuMindWorksView: View {
    let initialFilter: WuMindWorkType?
    var isEmbedded: Bool = false
    var onReopenPPT: ((WuMindPPTDeck, String) -> Void)? = nil
    var onReopenScene3D: ((String, String) -> Void)? = nil
    var onRetryWork: ((WuMindLocalWork) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var worksStore = WuMindWorksStore.shared
    @ObservedObject private var wmStore = WuMindStore.shared
    @State private var selectedFilter: WuMindWorkType?
    @State private var searchText: String = ""
    @State private var activeWork: WuMindLocalWork? = nil
    @State private var refreshingWorkID: String? = nil
    @State private var retryingUploadID: String? = nil

    init(
        initialFilter: WuMindWorkType? = nil,
        isEmbedded: Bool = false,
        onReopenPPT: ((WuMindPPTDeck, String) -> Void)? = nil,
        onReopenScene3D: ((String, String) -> Void)? = nil,
        onRetryWork: ((WuMindLocalWork) -> Void)? = nil
    ) {
        self.initialFilter = initialFilter
        self.isEmbedded = isEmbedded
        self.onReopenPPT = onReopenPPT
        self.onReopenScene3D = onReopenScene3D
        self.onRetryWork = onRetryWork
        _selectedFilter = State(initialValue: initialFilter)
    }

    private var filteredWorks: [WuMindLocalWork] {
        let base = worksStore.works(of: selectedFilter)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(q)
                || $0.prompt.lowercased().contains(q)
                || $0.modelID.lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if isEmbedded {
                embeddedContent
            } else {
                NavigationStack {
                    mainListContent
                        .navigationTitle(initialFilter == nil ? "我的作品" : "\(initialFilter!.title)历史")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(.visible, for: .navigationBar)
                        .searchable(text: $searchText, prompt: "按标题、提示词或模型检索")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("关闭") { dismiss() }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                refreshButton
                            }
                        }
                }
            }
        }
        .sheet(item: $activeWork) { work in
            let retry = initialFilter == nil || initialFilter == work.workType ? onRetryWork : nil
            WuMindWorkDetailSheet(
                work: work,
                onReopenPPT: onReopenPPT.map { open in
                    { deck, workID in
                        closeForAction()
                        open(deck, workID)
                    }
                },
                onReopenScene3D: onReopenScene3D.map { open in
                    { json, workID in
                        closeForAction()
                        open(json, workID)
                    }
                },
                onRetryWork: retry.map { run in
                    { failed in
                        closeForAction()
                        run(failed)
                    }
                }
            )
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshWorks()
        }
    }

    private func closeForAction() {
        activeWork = nil
        if !isEmbedded { dismiss() }
    }

    private func refreshWorks() async {
        await worksStore.syncFromCloud(type: selectedFilter)
        guard !Task.isCancelled else { return }
        if selectedFilter == nil || selectedFilter == .video {
            await worksStore.reconcileBackgroundVideos()
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await refreshWorks() }
        } label: {
            if worksStore.isSyncing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .accessibilityLabel("刷新作品")
        .accessibilityIdentifier("wumind.works.refresh")
    }

    private var embeddedContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text("作品")
                    .font(DS.Font.display)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                refreshButton
                    .frame(minWidth: 44, minHeight: 44)
            }
            HStack(spacing: DS.Space.s) {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("搜索标题、提示词或模型", text: $searchText)
                        .submitLabel(.search)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, DS.Space.s)
                .frame(minHeight: 46)
                .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m))
                filterMenu
            }
            mainListContent
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.top, DS.Space.m)
        .frame(maxWidth: DS.readableWidth)
        .frame(maxWidth: .infinity)
    }

    private var mainListContent: some View {
        VStack(spacing: 0) {
            if !isEmbedded {
                HStack {
                    Spacer()
                    filterMenu
                }
                .padding(.horizontal, DS.Space.m)
            }
            if worksStore.pendingDeleteCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(worksStore.pendingDeleteError ?? "有 \(worksStore.pendingDeleteCount) 项已删作品待同步到云端，恢复联网将自动补发。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button("补发删除") {
                        Task { await worksStore.flushPendingDeletes() }
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.10))
            }

            if let err = worksStore.lastSyncError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("云端同步提示：\(err)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.10))
            }

            if filteredWorks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredWorks) { work in
                            workCard(work)
                        }
                    }
                    .padding(.horizontal, isEmbedded ? 0 : DS.Space.m)
                    .padding(.vertical, DS.Space.s)
                    .frame(maxWidth: DS.readableWidth)
                    .frame(maxWidth: .infinity)
                }
                .refreshable {
                    await worksStore.syncFromCloud(type: selectedFilter)
                }
            }
        }
        .appBackground()
    }

    private var filterMenu: some View {
        Menu {
            Picker("作品类型", selection: $selectedFilter) {
                Text("全部 (\(worksStore.works.count))").tag(nil as WuMindWorkType?)
                ForEach(WuMindWorkType.allCases) { type in
                    Text("\(type.title) (\(worksStore.works(of: type).count))").tag(Optional(type))
                }
            }
        } label: {
            HStack(spacing: DS.Space.xxs) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(selectedFilter?.title ?? "全部")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.medium))
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("筛选作品，\(selectedFilter?.title ?? "全部")")
        .accessibilityIdentifier("wumind.works.filter")
    }

    private var emptyState: some View {
        AppEmptyStateCard(
            icon: selectedFilter?.iconName ?? "square.stack.3d.up",
            title: searchText.isEmpty ? "暂无\(selectedFilter?.title ?? "")作品" : "未找到作品",
            message: searchText.isEmpty ? "已保存的作品会显示在这里。" : "试试其他标题、提示词或模型名称。"
        )
        .padding(DS.Space.m)
        .frame(maxWidth: DS.readableWidth, maxHeight: .infinity)
    }

    private func workCard(_ work: WuMindLocalWork) -> some View {
        Button {
            activeWork = work
        } label: {
            HStack(alignment: .top, spacing: 12) {
                thumbnailBox(for: work)
                VStack(alignment: .leading, spacing: 5) {
                    Text(work.title.isEmpty ? "未命名作品" : work.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DS.Space.xs) {
                        Text(work.workType.title)
                        if work.versionNumber > 1 { Text("v\(work.versionNumber)") }
                        if let sizeLabel = work.formattedAssetSize { Text(sizeLabel) }
                        statusBadge(for: work)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    if !work.modelID.isEmpty {
                        Text("模型：\(work.modelID)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let timing = work.timing, let summary = formatTimingSummary(timing) {
                        Text(summary)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.teal)
                            .lineLimit(1)
                    }

                    if work.isFailed, let err = work.errorMessage, !err.isEmpty {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        Text(work.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        assetSyncBadge(for: work)
                        Spacer()
                        if work.isCompleted,
                           (work.resolvedAssetSyncState == .failed || work.resolvedAssetSyncState == .localOnly || work.resolvedAssetSyncState == .pendingUpload),
                           worksStore.localAssetURL(for: work) != nil,
                           wmStore.hasGatewayURL {
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
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.16), in: Capsule())
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
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.blue.opacity(0.14), in: Capsule())
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.vertical, DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Divider() }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wumind.works.open.\(work.id)")
        .contextMenu {
            if work.isCompleted, worksStore.localAssetURL(for: work) != nil {
                Button {
                    Task { await worksStore.retryAssetUpload(id: work.id) }
                } label: {
                    Label("重新同步原文件到云端", systemImage: "icloud.and.arrow.up")
                }
            }
            Button(role: .destructive) {
                worksStore.deleteWork(id: work.id)
            } label: {
                Label("删除作品", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func assetSyncBadge(for work: WuMindLocalWork) -> some View {
        let state = work.resolvedAssetSyncState
        switch state {
        case .synced:
            Label(state.badgeTitle, systemImage: "icloud.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .pendingUpload:
            Label(state.badgeTitle, systemImage: "icloud.and.arrow.up")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .uploading:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(state.badgeTitle)
                    .font(.caption2)
                    .foregroundStyle(.indigo)
            }
        case .failed:
            Label(state.badgeTitle, systemImage: "exclamationmark.icloud.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .storageUnconfigured:
            Label(state.badgeTitle, systemImage: "externaldrive.badge.exclamationmark")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .localOnly:
            Label(state.badgeTitle, systemImage: "internaldrive")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func thumbnailBox(for work: WuMindLocalWork) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 72, height: 72)
            if let img = worksStore.loadThumbnailImage(for: work) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: work.workType.iconName)
                    .font(.title2)
                    .foregroundStyle(colorForType(work.workType))
            }
        }
    }

    private func statusBadge(for work: WuMindLocalWork) -> some View {
        let color: Color = work.isCompleted ? .green : (work.isFailed ? .red : .orange)
        return Text(work.statusLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private func colorForType(_ type: WuMindWorkType) -> Color {
        switch type {
        case .image: return .pink
        case .video: return .purple
        case .ppt: return .blue
        case .scene3d: return .teal
        case .document: return .orange
        case .code: return .mint
        }
    }

    private func formatTimingSummary(_ t: WuMindCloudWorkTiming) -> String? {
        var parts: [String] = []
        if let u = t.uploadPrepareMs, u > 0 { parts.append(String(format: "准备 %.1fs", Double(u) / 1000)) }
        if let g = t.gatewaySubmitMs, g > 0 { parts.append(String(format: "网关 %.1fs", Double(g) / 1000)) }
        if let s = t.upstreamGenerateMs, s > 0 { parts.append(String(format: "出图 %.1fs", Double(s) / 1000)) }
        if let d = t.displayRenderMs, d > 0 { parts.append(String(format: "显示 %.1fs", Double(d) / 1000)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Detail viewer for one saved work: shows thumbnail immediately, downloads full original on demand,
/// lists version history (`v1`, `v2`, ...), supports ShareLink export, reopen-to-edit, and manual Retry.
struct WuMindWorkDetailSheet: View {
    let work: WuMindLocalWork
    var onReopenPPT: ((WuMindPPTDeck, String) -> Void)? = nil
    var onReopenScene3D: ((String, String) -> Void)? = nil
    var onRetryWork: ((WuMindLocalWork) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var worksStore = WuMindWorksStore.shared
    @State private var currentWork: WuMindLocalWork
    @State private var loadedAssetURL: URL? = nil
    @State private var loadedProjectJSON: String? = nil
    @State private var previewImage: UIImage?
    @State private var previewPlayer: AVPlayer?
    @State private var loadedDeck: WuMindPPTDeck?
    @State private var pending: VersionRequest?
    @State private var loadError: String?
    @State private var showsAllVersions = false
    @ScaledMetric(relativeTo: .body) private var versionWidth: CGFloat = 92

    private struct VersionRequest {
        enum Operation { case download, query }
        let id = UUID()
        let work: WuMindLocalWork
        let operation: Operation
    }

    init(
        work: WuMindLocalWork,
        onReopenPPT: ((WuMindPPTDeck, String) -> Void)? = nil,
        onReopenScene3D: ((String, String) -> Void)? = nil,
        onRetryWork: ((WuMindLocalWork) -> Void)? = nil
    ) {
        self.work = work
        self.onReopenPPT = onReopenPPT
        self.onReopenScene3D = onReopenScene3D
        self.onRetryWork = onRetryWork
        _currentWork = State(initialValue: work)
    }

    private var lineage: [WuMindLocalWork] {
        worksStore.versions(for: currentWork)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(currentWork.title.isEmpty ? "未命名作品" : currentWork.title)
                            .font(DS.Font.title)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("wumind.work.title")
                        Text("\(currentWork.workType.title) · \(currentWork.statusLabel)")
                            .font(DS.Font.callout)
                            .foregroundStyle(.secondary)
                        if let error = currentWork.errorMessage, !error.isEmpty {
                            Text(error)
                                .font(DS.Font.body)
                                .foregroundStyle(currentWork.isFailed ? DS.Palette.danger : Color.primary)
                        }
                    }
                    if lineage.count > 1 { versionPicker }
                    previewArea
                    actionButtons
                    if let loadError {
                        Text(loadError).font(DS.Font.body).foregroundStyle(DS.Palette.danger)
                    }
                    if !currentWork.prompt.isEmpty {
                        AppSectionCard(title: "提示词") {
                            Text(currentWork.prompt).font(DS.Font.body).textSelection(.enabled)
                        }
                    }
                    AppSectionCard(title: "文件信息") {
                        LabeledContent("同步状态", value: currentWork.resolvedAssetSyncState.badgeTitle)
                        if let size = currentWork.formattedAssetSize {
                            LabeledContent("文件大小", value: size)
                        }
                        if !currentWork.modelID.isEmpty {
                            LabeledContent("模型", value: currentWork.modelID)
                        }
                        LabeledContent("账号", value: currentWork.ownerID)
                        if let error = currentWork.lastAssetUploadError, !error.isEmpty {
                            Text("同步说明：\(error)").font(DS.Font.caption).foregroundStyle(.secondary)
                        }
                        if !currentWork.params.isEmpty {
                            DisclosureGroup("生成参数") {
                                VStack(alignment: .leading, spacing: DS.Space.xs) {
                                    ForEach(currentWork.params.keys.sorted(), id: \.self) { key in
                                        LabeledContent(key, value: currentWork.params[key] ?? "")
                                    }
                                }
                                .font(DS.Font.caption)
                                .textSelection(.enabled)
                            }
                        }
                    }
                }
                .frame(maxWidth: DS.readableWidth)
                .padding(DS.Space.m)
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .hidesFloatingTabBar()
            .navigationTitle("作品详情 v\(currentWork.versionNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { selectVersion(currentWork) }
            .onDisappear {
                pending = nil
                previewPlayer?.pause()
            }
            .onChange(of: worksStore.activeOwnerID) { owner in
                if owner != currentWork.ownerID {
                    pending = nil
                    dismiss()
                }
            }
            .task(id: pending?.id) { [pending] in
                if let pending { await perform(pending) }
            }
        }
    }

    private var versionPicker: some View {
        let versions = lineage
        var visible = Array(versions.prefix(3))
        if !visible.contains(where: { $0.id == currentWork.id }), !visible.isEmpty {
            visible[visible.count - 1] = currentWork
        }
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("版本").font(DS.Font.headline).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: versionWidth), spacing: DS.Space.xs)],
                      alignment: .leading, spacing: DS.Space.xs) {
                ForEach(showsAllVersions ? versions : visible) { version in
                    let selected = version.id == currentWork.id
                    let time = version.updatedAt.formatted(date: .omitted, time: .shortened)
                    Button { if !selected { selectVersion(version) } } label: {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            HStack {
                                Text("v\(version.versionNumber)").font(DS.Font.headline)
                                if selected { Image(systemName: "checkmark") }
                            }
                            Text(time).font(DS.Font.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, DS.Space.s)
                        .padding(.vertical, DS.Space.xs)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(selected ? DS.Palette.accentSoft : DS.Palette.cardSurface,
                                    in: RoundedRectangle(cornerRadius: DS.Radius.m))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("v\(version.versionNumber) · \(time)")
                    .accessibilityIdentifier("wumind.work.version.\(version.versionNumber)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if versions.count > 3 {
                Button(showsAllVersions ? "收起版本" : "查看全部 \(versions.count) 个版本") {
                    showsAllVersions.toggle()
                }
                .frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        if let previewPlayer {
            VideoPlayer(player: previewPlayer)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
        } else if let previewImage {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: currentWork.workType == .image ? nil : 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
                    .accessibilityLabel("\(currentWork.title)，版本 \(currentWork.versionNumber) 预览")
                if currentWork.workType == .image && currentWork.hasRemoteAsset && loadedAssetURL == nil {
                    Text("正在显示缩略图").font(DS.Font.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionButtons: some View {
        let workID = currentWork.id
        let canRetry = currentWork.isFailed && onRetryWork != nil
        let canQuery = currentWork.isInProgress && currentWork.workType == .video && currentWork.upstreamJobID != nil
        let canEdit = (loadedDeck != nil && onReopenPPT != nil)
            || (currentWork.workType == .scene3d && loadedProjectJSON != nil && onReopenScene3D != nil)
        let needsDownload = (currentWork.hasRemoteAsset && loadedAssetURL == nil)
            || (currentWork.hasRemoteProject && loadedProjectJSON == nil)
        let ready = !canRetry && !canQuery
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            if canQuery {
                detailButton("查询原任务进度", icon: "arrow.triangle.2.circlepath", primary: true,
                             loading: pending?.operation == .query) { begin(.query) }
                    .disabled(pending != nil)
            }
            if canRetry, let onRetryWork {
                detailButton("返回工具重试", icon: "arrow.clockwise", primary: true) {
                    onRetryWork(currentWork)
                }
            }
            if let deck = loadedDeck, let onReopenPPT {
                detailButton("在 PPT 工坊继续编辑（将存为新版本）", icon: "pencil", primary: ready) {
                    if currentWork.id == workID { onReopenPPT(deck, workID) }
                }
            }
            if currentWork.workType == .scene3d, let json = loadedProjectJSON, let onReopenScene3D {
                detailButton("在 3D 工坊继续编辑（将存为新版本）", icon: "cube", primary: ready) {
                    if currentWork.id == workID { onReopenScene3D(json, workID) }
                }
            }
            if needsDownload {
                detailButton("下载原文件与工程", icon: "icloud.and.arrow.down", primary: ready && !canEdit,
                             loading: pending?.operation == .download) { begin(.download) }
                    .disabled(pending != nil)
            }
            if let url = loadedAssetURL {
                ShareLink(item: url) { Label("导出 / 分享原文件", systemImage: "square.and.arrow.up") }
                    .buttonStyle(DSButtonStyle(kind: ready && !canEdit && !needsDownload ? .primary : .secondary,
                                               fullWidth: true))
            }
        }
    }

    private func detailButton(_ title: String, icon: String, primary: Bool,
                              loading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                if loading { ProgressView().controlSize(.small) }
                else { Image(systemName: icon) }
                Text(title).fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(DSButtonStyle(kind: primary ? .primary : .secondary, fullWidth: true))
        .accessibilityLabel(title)
    }

    private func selectVersion(_ version: WuMindLocalWork) {
        pending = nil
        loadError = nil
        currentWork = version
        showFiles(asset: worksStore.localAssetURL(for: version),
                  project: worksStore.loadLocalProjectJSON(for: version))
    }

    private func showFiles(asset: URL?, project: String?) {
        if currentWork.workType == .video, let asset {
            if loadedAssetURL != asset || previewPlayer == nil {
                previewPlayer?.pause()
                previewPlayer = AVPlayer(url: asset)
            }
            previewImage = nil
        } else {
            previewPlayer?.pause()
            previewPlayer = nil
            if currentWork.workType == .image, let asset, let original = UIImage(contentsOfFile: asset.path) {
                previewImage = original
            } else {
                previewImage = worksStore.loadThumbnailImage(for: currentWork)
            }
        }
        loadedAssetURL = asset
        loadedProjectJSON = project
        if currentWork.workType == .ppt, let project {
            loadedDeck = try? JSONDecoder().decode(WuMindPPTDeck.self, from: Data(project.utf8))
        } else {
            loadedDeck = nil
        }
    }

    private func begin(_ operation: VersionRequest.Operation) {
        guard pending == nil else { return }
        loadError = nil
        pending = VersionRequest(work: currentWork, operation: operation)
    }

    private func isCurrent(_ request: VersionRequest) -> Bool {
        !Task.isCancelled && pending?.id == request.id && currentWork.id == request.work.id
            && currentWork.ownerID == request.work.ownerID && worksStore.currentOwnerID == request.work.ownerID
    }

    @MainActor
    private func perform(_ request: VersionRequest) async {
        defer { if pending?.id == request.id { pending = nil } }
        guard isCurrent(request) else { return }
        switch request.operation {
        case .download:
            do {
                let files = try await worksStore.fetchFullOriginalIfNeeded(for: request.work)
                guard isCurrent(request) else { return }
                if let saved = worksStore.works.first(where: { $0.id == request.work.id && $0.ownerID == request.work.ownerID }) {
                    currentWork = saved
                }
                showFiles(asset: files.assetURL, project: files.projectJSON)
                if (request.work.hasRemoteAsset && files.assetURL == nil)
                    || (request.work.hasRemoteProject && files.projectJSON == nil) {
                    loadError = "未能取回此版本的全部文件，请检查连接后重试。"
                }
            } catch {
                guard isCurrent(request) else { return }
                loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        case .query:
            let updated = await worksStore.refreshInProgressVideoWork(request.work)
            guard isCurrent(request) else { return }
            guard let updated, updated.id == request.work.id, updated.ownerID == request.work.ownerID else {
                loadError = "未能取得此版本的任务进度，请稍后再次查询。"
                return
            }
            selectVersion(updated)
        }
    }
}
