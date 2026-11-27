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
            WuMindWorkDetailSheet(
                work: work,
                onReopenPPT: { deck, workID in
                    activeWork = nil
                    if !isEmbedded { dismiss() }
                    onReopenPPT?(deck, workID)
                },
                onReopenScene3D: { json, workID in
                    activeWork = nil
                    if !isEmbedded { dismiss() }
                    onReopenScene3D?(json, workID)
                },
                onRetryWork: { failed in
                    activeWork = nil
                    if !isEmbedded { dismiss() }
                    onRetryWork?(failed)
                }
            )
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshWorks()
        }
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
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("搜索标题、提示词或模型", text: $searchText)
                        .font(.subheadline)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                refreshButton
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            mainListContent
        }
    }

    private var mainListContent: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))

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
                    LazyVStack(spacing: 12) {
                        ForEach(filteredWorks) { work in
                            workCard(work)
                        }
                    }
                    .padding(DS.Space.m)
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

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "全部 (\(worksStore.works.count))", type: nil)
                ForEach(WuMindWorkType.allCases) { t in
                    let count = worksStore.works(of: t).count
                    filterChip(title: "\(t.title) (\(count))", type: t)
                }
            }
        }
    }

    private func filterChip(title: String, type: WuMindWorkType?) -> some View {
        let selected = selectedFilter == type
        return Button {
            selectedFilter = type
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
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
                    HStack(spacing: 6) {
                        Label(work.workType.title, systemImage: work.workType.iconName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if work.versionNumber > 1 {
                            Text("v\(work.versionNumber)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.indigo.opacity(0.15), in: Capsule())
                                .foregroundStyle(.indigo)
                        }
                        if let sizeLabel = work.formattedAssetSize {
                            Text(sizeLabel)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        statusBadge(for: work)
                    }

                    Text(work.title.isEmpty ? "未命名作品" : work.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

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
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
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
    @State private var isLoadingOriginal = false
    @State private var loadError: String? = nil

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
                VStack(alignment: .leading, spacing: 14) {
                    if lineage.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(lineage) { ver in
                                    Button {
                                        currentWork = ver
                                        loadedAssetURL = worksStore.localAssetURL(for: ver)
                                        loadedProjectJSON = worksStore.loadLocalProjectJSON(for: ver)
                                    } label: {
                                        Text("v\(ver.versionNumber) · \(ver.updatedAt.formatted(date: .omitted, time: .shortened))")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(ver.id == currentWork.id ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                                            .foregroundStyle(ver.id == currentWork.id ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("wumind.work.version.\(ver.versionNumber)")
                                    .accessibilityAddTraits(ver.id == currentWork.id ? .isSelected : [])
                                }
                            }
                        }
                    }

                    previewArea
                    actionButtons

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(currentWork.title.isEmpty ? "作品详情" : currentWork.title)
                                .font(.headline)
                            Spacer()
                            Text(currentWork.statusLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(currentWork.isCompleted ? .green : (currentWork.isFailed ? .red : .orange))
                        }

                        if !currentWork.prompt.isEmpty {
                            Text(currentWork.prompt)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        if !currentWork.modelID.isEmpty {
                            Text("模型：\(currentWork.modelID) · 账号：\(currentWork.ownerID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Label(currentWork.resolvedAssetSyncState.badgeTitle, systemImage: currentWork.resolvedAssetSyncState == .synced ? "icloud.fill" : "internaldrive")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(currentWork.resolvedAssetSyncState == .synced ? .blue : (currentWork.resolvedAssetSyncState == .failed ? .red : .orange))
                            if let sizeLabel = currentWork.formattedAssetSize {
                                Text("· \(sizeLabel)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let uploadErr = currentWork.lastAssetUploadError, !uploadErr.isEmpty {
                            Text("同步说明：\(uploadErr)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }

                        if !currentWork.params.isEmpty {
                            let paramStr = currentWork.params.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: " · ")
                            Text("参数：\(paramStr)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let err = currentWork.errorMessage, !err.isEmpty {
                            Text("失败原因：\(err)")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }

                        if let loadError {
                            Text(loadError)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

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
            .onAppear {
                loadedAssetURL = worksStore.localAssetURL(for: currentWork)
                loadedProjectJSON = worksStore.loadLocalProjectJSON(for: currentWork)
            }
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        if currentWork.workType == .video, let url = loadedAssetURL {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else if currentWork.workType == .image {
            if let url = loadedAssetURL, let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if let thumb = worksStore.loadThumbnailImage(for: currentWork) {
                VStack(spacing: 8) {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    if currentWork.hasRemoteAsset && loadedAssetURL == nil {
                        Text("当前展示快速缩略图，可按需下载高清原图")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if let thumb = worksStore.loadThumbnailImage(for: currentWork) {
            Image(uiImage: thumb)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 10) {
            if (currentWork.hasRemoteAsset && loadedAssetURL == nil) || (currentWork.hasRemoteProject && loadedProjectJSON == nil) {
                Button {
                    Task { await downloadOriginal() }
                } label: {
                    HStack {
                        if isLoadingOriginal { ProgressView().controlSize(.small) }
                        Label("下载原文件与工程", systemImage: "icloud.and.arrow.down")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingOriginal)
            }

            if currentWork.workType == .ppt, let json = loadedProjectJSON,
               let data = json.data(using: .utf8),
               let deck = try? JSONDecoder().decode(WuMindPPTDeck.self, from: data),
               let onReopenPPT {
                Button {
                    onReopenPPT(deck, currentWork.id)
                } label: {
                    Label("在 PPT 工坊继续编辑（将存为新版本）", systemImage: "pencil.and.outline")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }

            if currentWork.workType == .scene3d, let json = loadedProjectJSON, let onReopenScene3D {
                Button {
                    onReopenScene3D(json, currentWork.id)
                } label: {
                    Label("在 3D 工坊继续编辑（将存为新版本）", systemImage: "cube.transparent")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }

            if let url = loadedAssetURL {
                ShareLink(item: url) {
                    Label("导出 / 分享原文件", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }

            if currentWork.isFailed, let onRetryWork {
                Button {
                    onRetryWork(currentWork)
                } label: {
                    Label("使用原提示词和参数重试", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            if currentWork.isInProgress && currentWork.workType == .video && currentWork.upstreamJobID != nil {
                Button {
                    Task {
                        if let updated = await worksStore.refreshInProgressVideoWork(currentWork) {
                            currentWork = updated
                            loadedAssetURL = worksStore.localAssetURL(for: updated)
                        }
                    }
                } label: {
                    Label("查询原任务进度", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func downloadOriginal() async {
        isLoadingOriginal = true
        loadError = nil
        defer { isLoadingOriginal = false }
        do {
            let res = try await worksStore.fetchFullOriginalIfNeeded(for: currentWork)
            loadedAssetURL = res.assetURL
            loadedProjectJSON = res.projectJSON
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
