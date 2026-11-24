import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 发数传计划这一次的状态：读到的计划、哪几家已经发了。只在内存里（离开这一页再回来还在，关掉 App 就没了）
struct PassPlanSession: Equatable {
    /// 每次读取都是一批新原图；发出状态不参与图片是否过期的判断。
    var sourceID = UUID()
    var fromPhotos = false
    var fromDeepSeek = false
    var rows: [PassPlanRow] = []
    /// 读到的那张表的列（发出去的表照它）；补的、演示的是 nil，用默认的列
    var layout: PassPlan.Layout?
    var delivery = PassPlan.DeliveryLedger()
    var confirmedReceipts: [String: Date] { delivery.confirmedReceipts }
    var changesRecordedAt: Date?
    var batchRoutes: [String: String] = [:]
    /// 已明确选择的整页照片，仅本批在内存留存；DeepSeek 没有可验证的逐行裁剪。
    var sourcePage: Data?
    /// 发原图用：表头那一条在照片里的位置，和每一条（表头、每一行）从照片上裁下来的图
    var header: PassPlan.Region?
    var strips: [PassPlan.Region: Data] = [:]
}

/// 发送内容决定检查范围，不能因页面开着「发原图」就放宽文字分享。
enum PassPlanShareItem {
    case originalImage(UIImage)
    case renderedImage(UIImage)
    case text(String)

    var format: PassPlan.DeliveryFormat {
        if case .originalImage = self { return .originalImage }
        return .recognizedContent
    }

    var value: Any {
        switch self {
        case .originalImage(let image), .renderedImage(let image): return image
        case .text(let text): return text
        }
    }
}

/// 发数传计划：对着电脑屏幕拍一张完整计划（系统文档扫描自动框出屏幕、扶正），
/// 按运营商（地面站「-」前面的名字）分开，每家生成一张清楚的表格图 / 一段文字，发到那家的微信群。
/// 图片统一由 DeepSeek 识别；只有确认发送单张图片后才调用接口。表格直接在本机读取。
struct PassPlanView: View {
    @EnvironmentObject private var store: AppStore
    /// 打开时带进来的计划（分享过来的 Excel、截图演示）
    private let initial: PassPlan.Reading?
    /// 从快捷指令「拍数传计划」打开：直接进扫描
    private let autoScan: Bool
    @State private var entryState = PassPlanEntryState()
    @State private var reading = false
    @State private var readingStage = ""
    @State private var readingGeneration = UUID()
    @State private var readingTask: Task<Void, Never>?
    @State private var problem: String?
    @State private var scanning = false
    @State private var showingCamera = false
    @State private var showingCloudAlbum = false
    @State private var cloudPhoto: PhotosPickerItem?
    @State private var showingLocalAlbum = false
    @State private var localPhoto: PhotosPickerItem?
    @State private var lastCloudImage: UIImage?
    @State private var capturedCloudPhoto: UIImage?
    @State private var pendingCloudPhoto: CloudPhoto?
    @State private var confirmingCloudPhoto = false
    @State private var showingCloudKey = false
    @State private var cloudKeyConfigured = false
    @State private var importing = false
    @State private var editing: EditingRow?
    @State private var naming: String?
    @State private var groupName = ""
    /// 给这个站新建一家运营商
    @State private var newOperatorFor: String?
    @State private var newOperatorName = ""
    /// 每家的图（读完、改完重新画）
    @State private var images: [String: UIImage] = [:]
    @State private var renderedInput: RenderInput?
    @State private var clearing = false
    @State private var onlyReview = true
    @State private var sharePreview: PendingPreview?
    @State private var previewRecipientToEdit: String?
    @State private var pendingReceipt: String?
    @State private var activeSystemShare: UUID?
    @State private var pendingRoute: PendingRoute?

    private struct PendingPreview: Identifiable {
        let id = UUID()
        let input: RenderInput
        let names: [String]
        let useText: Bool
        let format: PassPlan.DeliveryFormat
    }

    private struct PendingRoute: Identifiable {
        let id = UUID()
        let sourceID: UUID
        let station: String
        let name: String
    }

    private enum CloudPhoto {
        case album(PhotosPickerItem)
        case capture(UIImage)
    }

    private struct RenderInput: Equatable {
        var sourceID: UUID
        var rows: [PassPlanRow]
        var layout: PassPlan.Layout?
        var rules: [PassPlan.OperatorRule]
        var normalCaption: String
        var urgentCaption: String
        var original: Bool
        var skipped: [String]
        var recipients: [String: String]
        var batchRoutes: [String: String]
    }

    private struct EditingRow: Identifiable {
        let id = UUID()
        var sourceID: UUID
        var index: Int?
        var row: PassPlanRow
        var sourceImage: UIImage?
        var sourceHeader: UIImage?
        var sourcePage: UIImage?
        var format: PassPlan.DeliveryFormat
    }

    init(reading: PassPlan.Reading? = nil, autoScan: Bool = false) {
        initial = reading
        self.autoScan = autoScan
    }

    private var rows: [PassPlanRow] { store.passPlan.rows }
    private var layout: PassPlan.Layout? { store.passPlan.layout }
    /// 运营商对照表（没填名字的那行不算）
    private var rules: [PassPlan.OperatorRule] { store.settings.passPlanOperators.filter { !$0.name.isEmpty } }
    private var renderInput: RenderInput {
        RenderInput(sourceID: store.passPlan.sourceID, rows: rows, layout: layout, rules: rules,
                    normalCaption: store.settings.passPlanCaption, urgentCaption: store.settings.passPlanUrgentCaption,
                    original: store.settings.passPlanOriginal, skipped: store.settings.passPlanSkipped,
                    recipients: store.settings.passPlanGroups, batchRoutes: store.passPlan.batchRoutes)
    }
    private var imagesAreCurrent: Bool { !reading && renderedInput == renderInput }
    private var imageFormat: PassPlan.DeliveryFormat {
        store.settings.passPlanOriginal && store.passPlan.fromPhotos ? .originalImage : .recognizedContent
    }
    private func imageItem(_ image: UIImage) -> PassPlanShareItem {
        imageFormat == .originalImage ? .originalImage(image) : .renderedImage(image)
    }
    private typealias Audit = [Int: [PassPlan.ReviewIssue]]

    private func audit(format: PassPlan.DeliveryFormat) -> Audit {
        PassPlan.reviewIssues(rows, format: format, rules: rules, layout: layout,
                              batchRoutes: store.passPlan.batchRoutes)
    }

    private func resolved(_ station: String) -> String? {
        PassPlan.resolvedOperator(of: station, rules: rules, batchRoutes: store.passPlan.batchRoutes)
    }

    private var allGroups: [OperatorGroup] {
        PassPlan.grouped(rows, rules: rules, batchRoutes: store.passPlan.batchRoutes)
    }
    /// 图下面那句话（这一家有应急计划就是「……应急计划优先推送」）
    private func caption(_ rows: [PassPlanRow]) -> String {
        PassPlan.caption(rows, layout: layout, normal: store.settings.passPlanCaption, urgent: store.settings.passPlanUrgentCaption)
    }

    /// 分得出是哪家、要发的（标了「不用发」的不算）
    private var sendable: [(name: String, rows: [PassPlanRow])] {
        let skipped = Set(store.settings.passPlanSkipped)
        return allGroups.filter { $0.name != PassPlan.unassigned && !skipped.contains($0.name) }
    }

    private typealias OperatorGroup = (name: String, rows: [PassPlanRow])

    private struct GroupedPlans {
        var all: [OperatorGroup]
        var sendable: [OperatorGroup]
        var resting: [OperatorGroup]
        var excluded: Int
        var doubtful: Int
        var idle: [String]
    }

    private func groupedPlans(_ audit: Audit) -> GroupedPlans {
        let all = allGroups
        let skipped = Set(store.settings.passPlanSkipped)
        let groups = all.filter { $0.name != PassPlan.unassigned && !skipped.contains($0.name) }
        // 标了「不用发」的几家（长春站这种）：收在最下面，不算在依次发、已发里。
        let resting = all.filter { skipped.contains($0.name) }
        let doubtful = audit.keys.count
        return GroupedPlans(all: all, sendable: groups, resting: resting,
                            excluded: rows.filter(PassPlan.isExcludedFromSending).count, doubtful: doubtful,
                            idle: PassPlan.idle(rows, rules: rules, batchRoutes: store.passPlan.batchRoutes))
    }

    var body: some View {
        namingContent
            .onAppear(perform: prepareOnAppear)
            .onAppear(perform: loadCloudKeyStatus)
            .onChange(of: initial) { _ in prepareOnAppear() }
            .onChange(of: autoScan) { _ in prepareOnAppear() }
            .onChange(of: rules) { _ in invalidateAllDelivery() }
            .onChange(of: store.settings.passPlanSkipped) { _ in invalidateAllDelivery() }
            .onChange(of: store.settings.passPlanCaption) { _ in invalidateAllDelivery() }
            .onChange(of: store.settings.passPlanUrgentCaption) { _ in invalidateAllDelivery() }
            .onChange(of: store.settings.passPlanOriginal) { _ in invalidateAllDelivery() }
            .task(id: renderInput) { renderImages() }
    }

    // MARK: - 页面分区

    private var planList: some View {
        let checks = audit(format: imageFormat)
        let grouped = groupedPlans(checks)
        return List {
            scannerSection
            if !rows.isEmpty {
                summarySection(grouped)
                planSections(grouped, audit: checks)
                addPlanSection
            }
            settingsSection
        }
    }

    private var scannerSection: some View {
        Section {
            Button { startCapture() } label: {
                Label("拍一张计划，用 DeepSeek 识别", systemImage: "doc.viewfinder").font(.headline)
            }
            .disabled(reading)
            Button {
                if requireCloudKey() { showingCloudAlbum = true }
            } label: {
                Label("从相册选一张", systemImage: "photo.on.rectangle")
            }
            .disabled(reading)
            DisclosureGroup("其他方式") {
                Button { startCapture(useDocumentScanner: false) } label: { Label("普通拍照（DeepSeek 识别）", systemImage: "camera") }
                Button { showingLocalAlbum = true } label: { Label("从相册选图（本机离线识别，不联网）", systemImage: "text.viewfinder") }
                Button { importing = true } label: { Label("导入 Excel", systemImage: "tablecells") }
                Button { read { try PlanReader.readClipboard() } } label: {
                    Label("粘贴复制的表格", systemImage: "doc.on.clipboard")
                }
            }
            .disabled(reading)
            Button {
                showingCloudKey = true
            } label: {
                Label(cloudKeyConfigured ? "管理 DeepSeek API Key" : "设置 DeepSeek API Key", systemImage: "key")
            }
            .disabled(reading)
            if reading {
                HStack(spacing: DS.Space.xs) {
                    DSSpinner(size: 14)
                    Text(readingStage).foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { cancelReading() }.buttonStyle(.borderless)
                }
            }
            if let problem {
                VStack(alignment: .leading, spacing: 8) {
                    Text(problem).font(.footnote).foregroundStyle(DS.Palette.danger)
                    if let fallbackImage = lastCloudImage {
                        Button {
                            processLocalPhoto(fallbackImage)
                        } label: {
                            Label("改用本机离线识别这张图", systemImage: "text.viewfinder")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(reading)
                    }
                }
            }
        } footer: {
            Text("每次拍或选一张含完整表头和任务行的计划图。使用 DeepSeek 识别时，会标黄提示存疑行供发前复核；也可以选择本机离线识别、导入 Excel 或粘贴表格。")
        }
    }

    private func summarySection(_ grouped: GroupedPlans) -> some View {
        let groups = grouped.sendable
        let lostCount = grouped.all.first { $0.name == PassPlan.unassigned }?.rows.count ?? 0
        return Section {
            LabeledContent("一共", value: "\(rows.count) 条，\(groups.count) 家")
            LabeledContent("人工确认收到", value: "\(groups.filter { store.passPlan.confirmedReceipts[$0.name] != nil }.count) / \(groups.count) 家")
            Picker("查看范围", selection: $onlyReview) {
                Text("仅异常（\(grouped.doubtful)）").tag(true)
                Text("全部（\(rows.count)）").tag(false)
            }
            .pickerStyle(.segmented)
            if onlyReview && grouped.doubtful == 0 {
                Label("没有待复核项，可以切换到「全部」或打开预览。", systemImage: "checkmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if grouped.excluded > 0 {
                Label("\(grouped.excluded) 条 test 已排除，不进入分享。", systemImage: "nosign")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if lostCount > 0 {
                Label("\(lostCount) 条站名未确定归属或有冲突，暂不进入分享。", systemImage: "questionmark.circle")
                    .font(.footnote).foregroundStyle(DS.Palette.warning)
            }
            if rules.isEmpty {
                Text("尚未配置运营商对照表。当前仅按站名分段预览；先添加对照表，才能打开分享。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !grouped.idle.isEmpty && !onlyReview {
                Text("无可分享计划：\(grouped.idle.joined(separator: "、"))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !groups.isEmpty {
                Button {
                    openPreview(groups.map(\.name), useText: false)
                } label: {
                    Label("发前预览（\(groups.count) 家）", systemImage: "doc.text.magnifyingglass").font(.headline)
                }
                .disabled(reading)
            }
        } footer: {
            Text("预览确认谁、几条、附件是什么，再逐家打开系统分享。微信群由你选，App 不会自动发送；系统分享操作完成不等于对方收到。")
        }
    }

    @ViewBuilder
    private func planSections(_ grouped: GroupedPlans, audit: Audit) -> some View {
        if let lost = grouped.all.first(where: { $0.name == PassPlan.unassigned }) {
            unassignedSection(lost.rows, known: grouped.sendable.map(\.name), audit: audit)
        }
        ForEach(grouped.sendable.filter { group in
            !onlyReview || !indexedRows(for: group.name, audit: audit).isEmpty
        }, id: \.name) { group in
            operatorSection(group, audit: audit)
        }
        let resting = grouped.resting.filter { !onlyReview || !indexedRows(for: $0.name, audit: audit).isEmpty }
        if !resting.isEmpty { restingSection(resting, audit: audit) }
        if !onlyReview, grouped.excluded > 0 {
            excludedSection
        }
    }

    private func operatorSection(_ group: OperatorGroup, audit: Audit) -> some View {
        Section {
            ForEach(indexedRows(for: group.name, audit: audit), id: \.offset) { item in
                rowButton(item.element, at: item.offset, issues: audit[item.offset] ?? [])
            }
            outputDescription(for: group.rows)
            sendButtons(group.name, rows: group.rows)
        } header: {
            header(group.name, count: group.rows.count,
                   urgent: group.rows.contains { PassPlan.emergency($0, layout: layout) == true })
        }
    }

    private func restingSection(_ groups: [OperatorGroup], audit: Audit) -> some View {
        Section {
            ForEach(groups, id: \.name) { group in
                HStack {
                    Text("\(group.name) · \(group.rows.count) 条").foregroundStyle(.secondary)
                    Spacer()
                    Button("要发") { store.settings.passPlanSkipped.removeAll { $0 == group.name } }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
                ForEach(indexedRows(for: group.name, audit: audit), id: \.offset) { item in
                    rowButton(item.element, at: item.offset, issues: audit[item.offset] ?? [])
                }
            }
        } header: {
            Text("不用发的")
        } footer: {
            Text("这几家标了「不用发」：不纳入预览与分享。点「要发」改回来。")
        }
    }

    private var excludedSection: some View {
        let excluded = rows.enumerated().filter { PassPlan.isExcludedFromSending($0.element) }
        return Section {
            DisclosureGroup("查看已排除的 \(excluded.count) 条") {
                ForEach(excluded, id: \.offset) { item in
                    rowButton(item.element, at: item.offset)
                }
            }
        } header: {
            Text("test · 不发送")
        } footer: {
            Text("状态为 test 的计划不进入任何一家的图片或文字预览；即使标了应急也会排除。点开可对照原图核对状态。")
        }
    }

    private var addPlanSection: some View {
        Section {
            Button { editing = EditingRow(sourceID: store.passPlan.sourceID, index: nil, row: PassPlanRow(), format: .recognizedContent) } label: {
                Label("补一条", systemImage: "plus")
            }
            .disabled(reading)
        }
    }

    private var settingsSection: some View {
        Section {
            NavigationLink {
                PassPlanOperatorsView()
            } label: {
                LabeledContent("运营商对照表", value: rules.isEmpty ? "还没填" : "\(rules.count) 家")
            }
            Toggle(isOn: $store.settings.passPlanOriginal) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("发原图")
                    Text(store.settings.passPlanOriginal
                         ? "裁下表头和各家的完整行；核对站名、应急和 test，图片里的编号与时间保留原照片"
                         : "发重新画的表：字是认出来的，可能有认错的，发之前核对标黄的")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("图片下面那句话").font(.caption).foregroundStyle(.secondary)
                TextField("没有应急计划时", text: $store.settings.passPlanCaption)
                TextField("有应急计划时（左侧「应急」或「是否应急」为「是」）", text: $store.settings.passPlanUrgentCaption)
            }
            Toggle("每天提醒发计划", isOn: $store.settings.passPlanReminder)
            if store.settings.passPlanReminder {
                DatePicker("提醒时间", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
        } footer: {
            Text("到点提醒一次，点提醒直接打开这一页；那天各家都人工确认收到后就不再提醒。也可以在「快捷指令」里把「拍数传计划」设成轻点两下手机背面（设置 › 辅助功能 › 触控 › 轻点背面），一下就进扫描。")
        }
    }

    // MARK: - 导航、弹窗与输入

    private var navigationContent: some View {
        planList
            .appList()
            .navigationTitle("发数传计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !rows.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("全部清掉", role: .destructive) { clearing = true }
                    }
                }
            }
    }

    private var reviewContent: some View {
        navigationContent
            .confirmationDialog("把读到的计划全部清掉？", isPresented: $clearing, titleVisibility: .visible) {
                Button("全部清掉", role: .destructive) {
                    restoreReminderIfNeeded()
                    store.passPlan = PassPlanSession()
                    problem = nil
                }
            }
            .alert(item: $pendingRoute) { chosen in
                Alert(title: Text("只修改本批分组？"),
                      message: Text("把本站「\(chosen.station)」仅在本批归给「\(chosen.name)」。请先与原图核对运营商；不更改识别内容、不改对照表、不发消息。"),
                      primaryButton: .default(Text("确认分组")) { applyBatchRoute(chosen) },
                      secondaryButton: .cancel())
            }
    }

    private var captureContent: some View {
        reviewContent
            .fullScreenCover(isPresented: $scanning, onDismiss: confirmCapturedCloudPhoto) {
                DocumentScanner { pages in acceptCapturedPages(pages) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showingCamera, onDismiss: confirmCapturedCloudPhoto) {
                CameraPicker { image in acceptCapturedPages([image]) }
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showingCloudAlbum, selection: $cloudPhoto, matching: .images)
            .onChange(of: cloudPhoto) { item in
                guard let item else { return }
                cloudPhoto = nil
                guard !reading else { return }
                pendingCloudPhoto = .album(item)
                confirmingCloudPhoto = true
            }
            .background(
                Color.clear
                    .photosPicker(isPresented: $showingLocalAlbum, selection: $localPhoto, matching: .images)
            )
            .onChange(of: localPhoto) { item in
                guard let item else { return }
                localPhoto = nil
                guard !reading else { return }
                processLocalAlbumItem(item)
            }
            .alert("发送这一张图给 DeepSeek？", isPresented: $confirmingCloudPhoto) {
                Button("确认发送") { processCloudPhoto() }
                Button("取消", role: .cancel) { pendingCloudPhoto = nil }
            } message: {
                Text("这一张图片（含图中文字）将发送到 DeepSeek，并使用你的 API 额度。请确认它是测试图或已获准外发；不会上传其他照片、Excel 或历史计划。")
            }
    }

    private var editingContent: some View {
        captureContent
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data,
                                                .commaSeparatedText, .tabSeparatedText, .plainText]) { result in
                readImportedFile(result)
            }
            .sheet(item: $editing) { target in editorView(target) }
            .sheet(item: $sharePreview, onDismiss: applyPreviewRecipientEdit) { request in
                sharePreviewView(request)
            }
            .sheet(isPresented: $showingCloudKey, onDismiss: loadCloudKeyStatus) {
                DeepSeekPlanKeyView()
            }
    }

    private var namingContent: some View {
        editingContent
            .alert("新的一家运营商", isPresented: newOperatorPresented) {
                TextField("运营商名字", text: $newOperatorName)
                Button("好", action: saveOperatorName)
                Button("取消", role: .cancel) { newOperatorFor = nil }
            } message: {
                if store.passPlan.fromDeepSeek {
                    Text("只把完整站名「\(newOperatorFor ?? "")」记给这一家；不会学习站名前缀。请先与原图核对站名。")
                } else {
                    Text("「\(newOperatorFor.map(PassPlan.suggestedPrefix(of:)) ?? "")」开头的站以后都算这一家")
                }
            }
            .alert("\(naming ?? "")的计划发到哪个群", isPresented: groupNamePresented) {
                TextField("群名（只是给自己看的提示）", text: $groupName)
                Button("好", action: saveGroupName)
                Button("取消", role: .cancel) { naming = nil }
            } message: {
                Text("微信不让别的 App 直接发到群里：预览会列出这个群名。打开系统分享后，仍由你在微信里选择。")
            }
    }

    private var newOperatorPresented: Binding<Bool> {
        Binding(get: { newOperatorFor != nil }, set: { if !$0 { newOperatorFor = nil } })
    }

    private var groupNamePresented: Binding<Bool> {
        Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })
    }

    private func editorView(_ target: EditingRow) -> some View {
        NavigationStack {
            PassPlanRowEditor(row: target.row, layout: layout, rules: rules, isNew: target.index == nil,
                              sourceImage: target.sourceImage, sourceHeader: target.sourceHeader,
                              sourcePage: target.sourcePage, sendsOriginal: target.format == .originalImage) { saved in
                saveEditedRow(saved, for: target)
            }
        }
    }

    private func saveEditedRow(_ saved: PassPlanRow?, for target: EditingRow) {
        guard target.sourceID == store.passPlan.sourceID else {
            ToastCenter.shared.show("计划已经更新，请重新打开要核对的那一条", style: .warning)
            return
        }
        if let i = target.index {
            guard store.passPlan.rows.indices.contains(i), store.passPlan.rows[i] == target.row else {
                ToastCenter.shared.show("这一条已经变化，请重新打开核对", style: .warning)
                return
            }
            let old = store.passPlan.rows[i]
            if let saved { store.passPlan.rows[i] = saved } else { store.passPlan.rows.remove(at: i) }
            if saved.map({ editedPayload(old, $0) }) != false { store.passPlan.changesRecordedAt = Date() }
            if let name = resolved(old.station), saved.map({ editedPayload(old, $0) }) != false {
                invalidateDelivery(name)
            }
        } else if let saved {
            store.passPlan.rows.append(saved)
            store.passPlan.changesRecordedAt = Date()
        }
        if let saved, let name = resolved(saved.station), target.index == nil || editedPayload(target.row, saved) {
            invalidateDelivery(name)
        }
    }

    private func startCapture(useDocumentScanner: Bool = true) {
        guard !reading, requireCloudKey() else { return }
        capturedCloudPhoto = nil
        problem = nil
        if useDocumentScanner && DocumentScanner.isSupported {
            scanning = true
        } else {
            showingCamera = true
        }
    }

    private func acceptCapturedPages(_ pages: [UIImage]) {
        capturedCloudPhoto = nil
        guard pages.count == 1, let image = pages.first else {
            problem = "DeepSeek 每次只识别一张完整计划图。这次未上传，原计划保留；请重拍一张含完整表头和全部任务行的图片，或直接导入 Excel。"
            return
        }
        capturedCloudPhoto = image
    }

    private func confirmCapturedCloudPhoto() {
        guard let image = capturedCloudPhoto else { return }
        capturedCloudPhoto = nil
        guard !reading, requireCloudKey() else { return }
        pendingCloudPhoto = .capture(image)
        confirmingCloudPhoto = true
    }

    private func loadCloudKeyStatus() {
        cloudKeyConfigured = !(Keychain.get(.deepSeekPlanAPIKey) ?? "").isEmpty
    }

    private func requireCloudKey() -> Bool {
        loadCloudKeyStatus()
        if !cloudKeyConfigured {
            showingCloudKey = true
            problem = "请先设置 DeepSeek API Key，再拍照或选图。导入 Excel 和粘贴表格不需要 Key。"
        }
        return cloudKeyConfigured
    }

    private func processCloudPhoto() {
        guard let item = pendingCloudPhoto else { return }
        pendingCloudPhoto = nil
        guard let key = Keychain.get(.deepSeekPlanAPIKey), !key.isEmpty else {
            _ = requireCloudKey()
            return
        }
        readBatch(fromDeepSeek: true) {
            let data: Data
            do {
                let image: UIImage
                switch item {
                case .album(let selected):
                    guard let bytes = try await selected.loadTransferable(type: Data.self),
                          let selectedImage = UIImage(data: bytes) else {
                        throw DeepSeekPlanPhoto.Failure.unreadable
                    }
                    image = selectedImage
                case .capture(let captured):
                    image = captured
                }
                lastCloudImage = image
                guard let jpeg = DeepSeekPlanPhoto.jpegWithoutMetadata(image) else {
                    throw DeepSeekPlanPhoto.Failure.unreadable
                }
                data = jpeg
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw DeepSeekPlanPhoto.Failure.unreadable
            }
            try Task.checkCancellation()
            readingStage = "正在用 DeepSeek 识别…"
            let readingResult = try await DeepSeekPlanReader.read(imageData: data, apiKey: key)
            lastCloudImage = nil
            return (readingResult, data)
        }
    }

    private func processLocalAlbumItem(_ item: PhotosPickerItem) {
        readBatch(fromDeepSeek: false) {
            readingStage = "正在载入图片…"
            guard let bytes = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: bytes) else {
                throw DeepSeekPlanPhoto.Failure.unreadable
            }
            let pageData = DeepSeekPlanPhoto.jpegWithoutMetadata(image)
            readingStage = "正在用本机离线视觉识别表格…"
            let found = try await PlanReader.read(pages: [image], rules: rules)
            lastCloudImage = nil
            return (found, pageData)
        }
    }

    private func processLocalPhoto(_ image: UIImage) {
        readBatch(fromDeepSeek: false) {
            let pageData = DeepSeekPlanPhoto.jpegWithoutMetadata(image)
            readingStage = "正在用本机离线视觉识别表格…"
            let found = try await PlanReader.read(pages: [image], rules: rules)
            lastCloudImage = nil
            return (found, pageData)
        }
    }

    private func readImportedFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        read { try PlanReader.read(file: url) }
    }

    private func saveOperatorName() {
        let name = newOperatorName.trimmingCharacters(in: .whitespaces)
        if let station = newOperatorFor, !name.isEmpty { assign(station, to: name) }
        newOperatorFor = nil
    }

    private func saveGroupName() {
        if let name = naming {
            let trimmed = groupName.trimmingCharacters(in: .whitespaces)
            let updated: String? = trimmed.isEmpty ? nil : trimmed
            if store.settings.passPlanGroups[name] != updated {
                store.settings.passPlanGroups[name] = updated
                invalidateDelivery(name)
            }
        }
        naming = nil
    }

    private func prepareOnAppear() {
        let actions = entryState.consume(initial: initial, autoScan: autoScan)
        if let initial = actions.reading {
            restoreReminderIfNeeded()
            store.passPlan = PassPlanSession(fromPhotos: initial.header != nil || initial.rows.contains { $0.region != nil },
                                            rows: initial.rows, layout: initial.layout, header: initial.header, strips: initial.strips)
        }
        if actions.autoScan {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                startCapture()
            }
        }
    }

    // MARK: - 一家的标题、一行

    /// 两条值完全相同的计划仍是两条记录；分组后保留它们在本批计划中的独立下标。
    private func indexedRows(for name: String, audit: Audit, includeAll: Bool = false) -> [(offset: Int, element: PassPlanRow)] {
        rows.enumerated().filter {
            !PassPlan.isExcludedFromSending($0.element)
                && (resolved($0.element.station) ?? PassPlan.unassigned) == name
                && (includeAll || !onlyReview || audit[$0.offset] != nil)
        }
    }

    private func rowButton(_ row: PassPlanRow, at index: Int, issues: [PassPlan.ReviewIssue] = []) -> some View {
        let sourceID = store.passPlan.sourceID
        return Button { edit(row, at: index, sourceID: sourceID) } label: { rowView(row, issues: issues) }
            .buttonStyle(.plain)
            .disabled(reading)
            // 可能认错的标黄
            .listRowBackground(PassPlan.isExcludedFromSending(row) || issues.isEmpty
                               ? nil : DS.Palette.warning.opacity(0.12))
            .swipeActions {
                Button("删掉", role: .destructive) { delete(row, at: index, sourceID: sourceID) }
                    .disabled(reading)
            }
            .contextMenu {
                if !PassPlan.isExcludedFromSending(row), !PassPlan.normalizedStationAlias(row.station).isEmpty,
                   PassPlan.stationCandidates(of: row.station, rules: rules).count < 2 && !rules.isEmpty {
                    Menu("只修改本批分组") {
                        ForEach(Array(Set(rules.map(\.name))).sorted(), id: \.self) { name in
                            Button(name) { pendingRoute = PendingRoute(sourceID: sourceID, station: row.station, name: name) }
                        }
                    }
                }
            }
    }

    /// 分不出是哪家的：每个站点一下「分给哪家」，记进对照表，以后自动分
    private func unassignedSection(_ rows: [PassPlanRow], known: [String], audit: Audit) -> some View {
        let stations = Array(Set(rows.map(\.station))).sorted()
        let names = (rules.map(\.name) + known).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let cloud = store.passPlan.fromDeepSeek
        return Section {
            ForEach(stations, id: \.self) { station in
                let candidates = PassPlan.stationCandidates(of: station, rules: rules)
                let conflicting = candidates.count > 1
                let nearAliases = cloud && !conflicting ? PassPlan.nearbyStationAliases(of: station, rules: rules) : []
                let similar = conflicting ? nil : PassPlan.likelyOperator(of: station, rules: rules)
                let neighbor = conflicting ? nil : PassPlan.neighborOperator(of: station, in: PassPlan.sendableRows(self.rows), rules: rules)
                let likely = similar ?? neighbor
                let reason = conflicting ? " · 对照表冲突：\(candidates.joined(separator: "、"))"
                    : !nearAliases.isEmpty ? " · 相近站名（仅供核对）：\(nearAliases.joined(separator: "、"))"
                    : similar.map { " · 猜测：字形最像「\($0)」" } ?? neighbor.map { " · 猜测：邻近行属于「\($0)」" } ?? ""
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station).font(.subheadline.weight(.medium))
                        Text("\(rows.filter { $0.station == station }.count) 条" + reason)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !cloud, let likely {
                        Button("算\(likely)") { assign(station, to: likely) }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                    }
                    if conflicting {
                        NavigationLink {
                            PassPlanOperatorsView()
                        } label: {
                            Text("修正对照表").font(.caption.weight(.semibold))
                        }
                    } else if !PassPlan.normalizedStationAlias(station).isEmpty {
                        Menu {
                            if !rules.isEmpty {
                                Menu("仅限本批") {
                                    ForEach(Array(Set(rules.map(\.name))).sorted(), id: \.self) { name in
                                        Button(name) {
                                            pendingRoute = PendingRoute(sourceID: store.passPlan.sourceID, station: station, name: name)
                                        }
                                    }
                                }
                            }
                            ForEach(names, id: \.self) { name in
                                Button(name == likely ? "记住 \(name)（猜测）" : "记住 \(name)") { assign(station, to: name) }
                            }
                            Button {
                                newOperatorName = ""
                                newOperatorFor = station
                            } label: {
                                Label("新的一家…", systemImage: "plus")
                            }
                        } label: {
                            Label(cloud || likely == nil ? "分给哪家" : "别的", systemImage: "arrow.turn.down.right")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            ForEach(indexedRows(for: PassPlan.unassigned, audit: audit), id: \.offset) { item in
                rowButton(item.element, at: item.offset, issues: audit[item.offset] ?? [])
            }
        } header: {
            Label("\(PassPlan.unassigned) · \(rows.count) 条", systemImage: "questionmark.circle.fill")
                .foregroundStyle(DS.Palette.warning)
        } footer: {
            Text(cloud
                 ? "对照表无匹配或存在冲突，暂不发送。先与原图核对；如果字读错了，可在下方改站名。确认归属后，可只记住这个完整站名，不影响相似站名。"
                 : "对照表无匹配或存在冲突，暂不发送。点「分给哪家」会记下站名开头；站名有错字就在下方修改；冲突到对照表中处理。")
        }
    }

    private func header(_ name: String, count: Int, urgent: Bool = false) -> some View {
        HStack {
            Text("\(name) · \(count) 条")
            if urgent {
                Text("应急").font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(DS.Palette.danger, in: Capsule())
            }
            if store.passPlan.confirmedReceipts[name] != nil {
                Label("人工确认收到", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon).foregroundStyle(DS.Palette.success)
            }
            Spacer()
            Button("不用发") { store.settings.passPlanSkipped.append(name) }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            Button {
                groupName = store.settings.passPlanGroups[name] ?? ""
                naming = name
            } label: {
                Label(store.settings.passPlanGroups[name].map { "发到：\($0)" } ?? "记一下发哪个群", systemImage: "person.3")
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
        }
    }

    private func rowView(_ row: PassPlanRow, issues: [PassPlan.ReviewIssue] = []) -> some View {
        let problems = issues.map(\.message)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                if imageFormat == .originalImage {
                    Text(row.station).font(.subheadline.weight(.semibold))
                } else {
                    Text([PassPlan.shortTime(row.start), PassPlan.shortTime(row.end)].filter { !$0.isEmpty }.joined(separator: "–"))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                if PassPlan.emergency(row, layout: layout) == true {
                    Text("应急").font(.caption2.weight(.bold)).foregroundStyle(DS.Palette.danger)
                }
                if PassPlan.isExcludedFromSending(row) {
                    Text("test · 已排除").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                if imageFormat != .originalImage {
                    Text(row.satellite.isEmpty ? row.satelliteID : row.satellite).font(.subheadline)
                }
            }
            if imageFormat == .originalImage {
                if let region = row.region, let data = store.passPlan.strips[region], let source = UIImage(data: data) {
                    Image(uiImage: source).resizable().scaledToFit()
                        .accessibilityLabel("这条计划的原图，点开可放大核对")
                } else {
                    Label("缺少这一行的原图", systemImage: "photo.badge.exclamationmark")
                        .font(.caption).foregroundStyle(DS.Palette.warning)
                }
            } else {
                Text([row.station, row.orbit.isEmpty ? "" : "圈号 \(row.orbit)", row.satelliteID, row.info]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !PassPlan.isExcludedFromSending(row), !problems.isEmpty {
                Label(problems.joined(separator: "；"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(DS.Palette.warning)
            }
            if let reviewed = row.reviewedWarnings, !reviewed.isEmpty {
                Text("已核对黄标： " + reviewed.joined(separator: "；")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func sendButtons(_ name: String, rows: [PassPlanRow]) -> some View {
        HStack(spacing: DS.Space.s) {
            Button { openPreview([name], useText: false) } label: {
                Label("预览图片", systemImage: "photo").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button { openPreview([name], useText: true) } label: {
                Label("预览文字", systemImage: "text.alignleft").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .disabled(reading || rows.isEmpty)
        .font(.subheadline.weight(.medium))
        .padding(.vertical, DS.Space.xxs)
    }

    @ViewBuilder
    private func outputDescription(for rows: [PassPlanRow]) -> some View {
        if store.settings.passPlanOriginal && store.passPlan.fromPhotos {
            let missing = rows.filter { $0.region.flatMap { store.passPlan.strips[$0] } == nil }.count
            let hasHeader = store.passPlan.header.flatMap { store.passPlan.strips[$0] } != nil
            if missing > 0 || !hasHeader {
                VStack(alignment: .leading, spacing: 6) {
                    Label(missing > 0 ? "这家有 \(missing) 条缺少原图，暂时不能拼成完整图片" : "没有裁出完整表头，暂时不能拼原图",
                          systemImage: "photo.badge.exclamationmark")
                    Text("可以重新拍摄；核对文字后，也可以改用重新绘制的表格。")
                    Button("改用文字绘制图片") { store.settings.passPlanOriginal = false }
                        .buttonStyle(.bordered)
                }
                .font(.caption).foregroundStyle(DS.Palette.warning)
            } else {
                Text("图片使用原照片；为避免传错，仍需完成本批计划的时间、重复项、站名与黄标复核。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text(store.passPlan.fromDeepSeek
                 ? "图片由 DeepSeek 识别文字重新绘制，不是原图裁切。请先核对标黄的计划。"
                 : store.passPlan.fromPhotos ? "图片由识别文字重新绘制，请先核对标黄的计划。" : "图片根据导入或填写的表格生成。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - 读、改、发

    private func read(_ work: @escaping @MainActor () async throws -> PassPlan.Reading) {
        readBatch(fromDeepSeek: false) { (try await work(), nil) }
    }

    private func readBatch(fromDeepSeek: Bool,
                           _ work: @escaping @MainActor () async throws -> (PassPlan.Reading, Data?)) {
        guard !reading else { return }
        let sourceID = store.passPlan.sourceID
        let generation = UUID()
        readingGeneration = generation
        reading = true
        readingStage = fromDeepSeek ? "正在载入图片…" : "正在读取表格…"
        problem = nil
        readingTask = Task {
            defer {
                if readingGeneration == generation {
                    reading = false
                    readingStage = ""
                    readingTask = nil
                }
            }
            do {
                let (result, sourcePage) = try await work()
                // 清空或换了一批计划后，旧识别任务不能把结果重新写回来。
                guard readingGeneration == generation, store.passPlan.sourceID == sourceID else { return }
                let found = result.rows
                restoreReminderIfNeeded()
                withAnimation {
                    store.passPlan = PassPlanSession(
                        fromPhotos: !fromDeepSeek && (result.header != nil || !result.strips.isEmpty),
                        fromDeepSeek: fromDeepSeek,
                        rows: found,
                        layout: result.layout,
                        sourcePage: sourcePage,
                        header: result.header,
                        strips: result.strips
                    )
                }
                let doubtful = audit(format: imageFormat).keys.count
                let excluded = found.filter(PassPlan.isExcludedFromSending).count
                let grouped = PassPlan.grouped(found, rules: rules)
                let lost = grouped.first { $0.name == PassPlan.unassigned }?.rows.count ?? 0
                let families = grouped.filter { $0.name != PassPlan.unassigned }.count
                var message = "\(fromDeepSeek ? "DeepSeek " : "")认出 \(found.count) 条，分成 \(families) 家"
                if excluded > 0 { message += "；已排除 \(excluded) 条 test" }
                if lost > 0 { message += "；\(lost) 条分不出是哪家，在最上面" } else if doubtful > 0 { message += "，\(doubtful) 条要核对" }
                ToastCenter.shared.show(message, style: doubtful > 0 || lost > 0 ? .warning : .success)
            } catch {
                guard readingGeneration == generation, store.passPlan.sourceID == sourceID else { return }
                problem = error.localizedDescription
            }
        }
    }

    private func cancelReading() {
        readingTask?.cancel()
        readingGeneration = UUID()
        readingTask = nil
        reading = false
        readingStage = ""
        // Some image-recognition APIs finish synchronously despite cancellation.
        // The generation check above still prevents their stale results replacing
        // the current plan when the user starts again.
    }

    private func edit(_ row: PassPlanRow, format: PassPlan.DeliveryFormat? = nil) {
        guard let index = rows.firstIndex(of: row) else { return }
        edit(row, at: index, sourceID: store.passPlan.sourceID, format: format)
    }

    private func edit(_ row: PassPlanRow, at index: Int, sourceID: UUID, format: PassPlan.DeliveryFormat? = nil) {
        guard !reading else { return }
        guard sourceID == store.passPlan.sourceID, rows.indices.contains(index), rows[index] == row else {
            ToastCenter.shared.show("这一条已经变化，请重新打开核对", style: .warning)
            return
        }
        editing = EditingRow(sourceID: sourceID, index: index, row: row,
                             sourceImage: row.region.flatMap { store.passPlan.strips[$0] }.flatMap(UIImage.init(data:)),
                             sourceHeader: store.passPlan.header.flatMap { store.passPlan.strips[$0] }.flatMap(UIImage.init(data:)),
                             sourcePage: store.passPlan.sourcePage.flatMap(UIImage.init(data:)),
                             format: format ?? .recognizedContent)
    }

    private func delete(_ row: PassPlanRow, at index: Int, sourceID: UUID) {
        guard !reading else { return }
        guard sourceID == store.passPlan.sourceID, rows.indices.contains(index), rows[index] == row else {
            ToastCenter.shared.show("这一条已经变化，请重新打开核对", style: .warning)
            return
        }
        store.passPlan.rows.remove(at: index)
        store.passPlan.changesRecordedAt = Date()
        if let name = resolved(row.station) { invalidateDelivery(name) }
    }

    private func openPreview(_ names: [String], useText: Bool) {
        guard !reading, !names.isEmpty else { return }
        sharePreview = PendingPreview(input: renderInput, names: names, useText: useText,
                                      format: useText ? .recognizedContent : imageFormat)
    }

    private func sharePreviewView(_ request: PendingPreview) -> some View {
        let current = request.input == renderInput && !reading
        let groups = sendable.filter { request.names.contains($0.name) }
        let checks = current ? audit(format: request.format) : [:]
        let unassignedCount = allGroups.first(where: { $0.name == PassPlan.unassigned })?.rows.count ?? 0
        return NavigationStack {
            List {
                Section {
                    Text("这里只预览。按每家「打开分享面板」后，仍需你在微信里核对、选择群并发送。App 不读取微信回执。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if unassignedCount > 0 {
                        Label("\(unassignedCount) 条未确定归属或冲突的计划不在这次分享中。", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(DS.Palette.warning)
                    }
                }
                if !current {
                    Section {
                        Label("本批计划、分组或群名已变更。请关闭并重新预览。", systemImage: "arrow.clockwise")
                            .foregroundStyle(DS.Palette.warning)
                    }
                } else {
                    ForEach(groups, id: \.name) { group in
                        sharePreviewSection(group, request: request, checks: checks)
                    }
                }
            }
            .navigationTitle("发送前预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { sharePreview = nil }
                }
            }
            .confirmationDialog("确认对方收到？", isPresented: receiptPresented, titleVisibility: .visible) {
                Button("我已人工核实收到") {
                    if let name = pendingReceipt { confirmReceipt(name, request: request) }
                    pendingReceipt = nil
                }
                Button("取消", role: .cancel) { pendingReceipt = nil }
            } message: {
                Text("仅在你实际确认「\(pendingReceipt ?? "")」的目标群收到本批计划后才记录。系统分享完成不构成回执。")
            }
        }
    }

    private var receiptPresented: Binding<Bool> {
        Binding(get: { pendingReceipt != nil }, set: { if !$0 { pendingReceipt = nil } })
    }

    private func sharePreviewSection(_ group: OperatorGroup, request: PendingPreview, checks: Audit) -> some View {
        let name = group.name
        let groupName = recipient(for: name)
        let indices = indexedRows(for: name, audit: checks, includeAll: true).map(\.offset)
        let checked = indices.flatMap { checks[$0] ?? [] }
        var shown = Set<String>()
        let distinctMessages = checked.map(\.message).filter { shown.insert($0).inserted }
        let content = request.useText ? PassPlan.message(name: name, rows: group.rows, layout: layout,
                                                           caption: caption(group.rows)) : nil
        let photo = !request.useText && imagesAreCurrent ? images[name] : nil
        let enabled = groupName != nil && checked.isEmpty && ((content?.isEmpty == false) || photo != nil)
        return Section {
            LabeledContent("目标微信群", value: groupName ?? "没有设置")
            LabeledContent("包含计划", value: "\(group.rows.count) 条（不含 test）")
            LabeledContent("分享项", value: request.useText ? "文字" : (request.format == .originalImage ? "原照裁切图片" : "重绘表格图"))
            if let content {
                Text(content).font(.footnote.monospaced()).textSelection(.enabled)
            } else if let photo {
                Image(uiImage: photo).resizable().scaledToFit()
                    .accessibilityLabel("将交给系统分享的实际图片")
            } else {
                Text(imagesAreCurrent ? "没有可用附件；不会用整页图代替，也不会自动切换格式。" : "正在准备预览图片…")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !distinctMessages.isEmpty {
                ForEach(Array(distinctMessages.enumerated()), id: \.offset) { _, message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(DS.Palette.warning)
                }
                Button("返回复核") { onlyReview = true; sharePreview = nil }
            }
            Button(groupName == nil ? "先填写群名" : "修改微信群名") {
                previewRecipientToEdit = name
                sharePreview = nil
            }
            Button {
                openSystemShare(name, request: request)
            } label: {
                Label("打开分享面板", systemImage: "square.and.arrow.up")
            }
            .disabled(!enabled || activeSystemShare != nil)
            if let date = store.passPlan.confirmedReceipts[name] {
                Label("人工确认收到 · \(date.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DS.Palette.success)
            } else if store.passPlan.delivery.requested.contains(name) {
                Text(store.passPlan.delivery.handedOff.contains(name)
                     ? "系统报告分享操作完成，尚未确认对方收到。"
                     : "已请求打开系统分享，未确认操作完成或对方收到。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("我已核实对方收到") { pendingReceipt = name }
                    .disabled(!enabled || activeSystemShare != nil)
            }
        } header: {
            Text(name)
        }
    }

    private func recipient(for name: String) -> String? {
        guard let text = store.settings.passPlanGroups[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    private func applyPreviewRecipientEdit() {
        pendingReceipt = nil
        guard let selected = previewRecipientToEdit else { return }
        previewRecipientToEdit = nil
        groupName = recipient(for: selected) ?? ""
        naming = selected
    }

    private func openSystemShare(_ name: String, request: PendingPreview) {
        guard !reading, activeSystemShare == nil, request.input == renderInput, request.names.contains(name),
              let target = recipient(for: name), let group = sendable.first(where: { $0.name == name }) else { return }
        let checks = audit(format: request.format)
        guard !indexedRows(for: name, audit: checks, includeAll: true).contains(where: { checks[$0.offset] != nil }) else { return }
        let item: PassPlanShareItem
        if request.useText {
            let message = PassPlan.message(name: name, rows: group.rows, layout: layout, caption: caption(group.rows))
            guard !message.isEmpty else { return }
            item = .text(message)
        } else {
            guard imagesAreCurrent, let image = images[name] else { return }
            item = imageItem(image)
        }
        let activityID = UUID()
        activeSystemShare = activityID
        store.passPlan.delivery.requestShare(name)
        let payload = SharePayload(item.value, title: "\(name)数传计划 → 请选择「\(target)」", preview: request.useText ? nil : images[name])
        ActivityShare.present([payload], excluding: ActivityShare.chatOnly) { completed in
            guard activeSystemShare == activityID else { return }
            activeSystemShare = nil
            guard request.input == renderInput else { return }
            store.passPlan.delivery.reportHandoff(name, completed: completed)
        }
    }

    private func confirmReceipt(_ name: String, request: PendingPreview) {
        let checks = audit(format: request.format)
        guard !reading, activeSystemShare == nil, request.input == renderInput, request.names.contains(name),
              recipient(for: name) != nil, sendable.contains(where: { $0.name == name }),
              !indexedRows(for: name, audit: checks, includeAll: true).contains(where: { checks[$0.offset] != nil }),
              store.passPlan.delivery.confirmReceipt(name, at: Date()) else { return }
        let names = Set(sendable.map(\.name))
        let hasUnassigned = allGroups.contains(where: { $0.name == PassPlan.unassigned })
        guard !hasUnassigned, !names.isEmpty, names.isSubset(of: Set(store.passPlan.confirmedReceipts.keys)) else { return }
        store.settings.passPlanSentDay = .today
        ToastCenter.shared.show("本批各家均已人工确认收到", style: .success)
        Task { await store.schedulePlanReminder() }
    }

    private func applyBatchRoute(_ chosen: PendingRoute) {
        let key = PassPlan.normalizedStationAlias(chosen.station)
        guard !reading, chosen.sourceID == store.passPlan.sourceID, !key.isEmpty,
              rules.contains(where: { $0.name == chosen.name }), !chosen.name.isEmpty,
              PassPlan.stationCandidates(of: chosen.station, rules: rules).count < 2 else { return }
        let old = resolved(chosen.station)
        guard old != chosen.name else { return }
        store.passPlan.batchRoutes[key] = chosen.name
        store.passPlan.changesRecordedAt = Date()
        if let old { invalidateDelivery(old) }
        invalidateDelivery(chosen.name)
        ToastCenter.shared.show("仅本批改为「\(chosen.name)」，未重新识别", style: .success)
    }

    private func invalidateDelivery(_ name: String) {
        let wasConfirmed = store.passPlan.confirmedReceipts[name] != nil
        store.passPlan.delivery.invalidate(name)
        if wasConfirmed { restoreReminderIfNeeded() }
    }

    private func invalidateAllDelivery() {
        let hadReceipts = !store.passPlan.confirmedReceipts.isEmpty
        store.passPlan.delivery = PassPlan.DeliveryLedger()
        if hadReceipts { restoreReminderIfNeeded() }
    }

    private func restoreReminderIfNeeded() {
        if store.settings.passPlanSentDay == .today {
            store.settings.passPlanSentDay = nil
            Task { await store.schedulePlanReminder() }
        }
    }

    private func editedPayload(_ old: PassPlanRow, _ new: PassPlanRow) -> Bool {
        old.orbit != new.orbit || old.satelliteID != new.satelliteID || old.satellite != new.satellite
            || old.station != new.station || old.start != new.start || old.end != new.end
            || old.info != new.info || old.status != new.status || old.cells != new.cells
            || PassPlan.isExcludedFromSending(old) != PassPlan.isExcludedFromSending(new)
            || PassPlan.emergency(old, layout: layout) != PassPlan.emergency(new, layout: layout)
    }
    /// 云端识别只学习已确认的完整站名；原本机入口保留显式前缀学习。
    private func assign(_ station: String, to name: String) {
        let cloud = store.passPlan.fromDeepSeek
        let alias = station.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = PassPlan.suggestedPrefix(of: station)
        guard !name.isEmpty,
              !PassPlan.normalizedStationAlias(cloud ? alias : prefix).isEmpty else { return }
        var proposed = store.settings.passPlanOperators
        let i: Int
        if let existing = proposed.firstIndex(where: { $0.name == name }) {
            i = existing
        } else {
            i = proposed.endIndex
            proposed.append(PassPlan.OperatorRule(name: name, prefixes: []))
        }
        if cloud {
            var stations = proposed[i].exactStations ?? []
            if !stations.contains(where: { PassPlan.normalizedStationAlias($0) == PassPlan.normalizedStationAlias(alias) }) {
                stations.append(alias)
            }
            proposed[i].exactStations = stations
        } else {
            if !proposed[i].prefixes.contains(prefix) { proposed[i].prefixes.append(prefix) }
        }
        guard PassPlan.operatorName(of: station, rules: proposed.filter { !$0.name.isEmpty }) == name else {
            ToastCenter.shared.show("没有保存：站名有冲突，请到「运营商对照表」核对", style: .warning)
            return
        }
        store.settings.passPlanOperators = proposed
        store.passPlan.changesRecordedAt = Date()
        ToastCenter.shared.show(cloud ? "已记住完整站名「\(alias)」属于\(name)" : "以后「\(prefix)」开头的站都算\(name)", style: .success)
    }

    /// 提醒时间（DatePicker 用 Date）
    private var reminderTime: Binding<Date> {
        Binding(get: {
            let t = store.settings.passPlanReminderTime
            return DayKey.today.date(calendar: .current, hour: t.hour, minute: t.minute)
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            store.settings.passPlanReminderTime = ClockTime(hour: c.hour ?? 15, minute: c.minute ?? 0)
        })
    }

    private func renderImages() {
        let input = renderInput
        // One corrected OCR row should only redraw that operator's image.
        // Keep the cache scoped to this photo batch and the same presentation
        // rules, so an old crop or caption can never leak into a new share.
        let mayReuse = renderedInput.map { old in
            old.sourceID == input.sourceID && old.layout == input.layout
                && old.rules == input.rules && old.normalCaption == input.normalCaption
                && old.urgentCaption == input.urgentCaption && old.original == input.original
        } ?? false
        let previousGroups: [String: [PassPlanRow]]
        if mayReuse, let previous = renderedInput {
            previousGroups = Dictionary(PassPlan.grouped(previous.rows, rules: previous.rules, batchRoutes: previous.batchRoutes)
                .map { ($0.name, $0.rows) }, uniquingKeysWith: { first, _ in first })
        } else {
            previousGroups = [:]
        }
        var made: [String: UIImage] = [:]
        for group in sendable {
            if let previous = previousGroups[group.name], previous == group.rows,
               let existingImage = images[group.name] {
                made[group.name] = existingImage
                continue
            }
            if store.settings.passPlanOriginal && store.passPlan.fromPhotos {
                // 原图缺行时不能悄悄换成 OCR 重绘图，把认错的字带出去。
                if let original = originalImage(name: group.name, rows: group.rows) { made[group.name] = original }
                continue
            }
            let renderer = ImageRenderer(content: PassPlanSheet(name: group.name, rows: group.rows, layout: layout,
                                                                caption: caption(group.rows)))
            renderer.scale = 3
            if let image = renderer.uiImage { made[group.name] = image }
        }
        images = made
        renderedInput = input
    }

    /// 发原图：表头那一条加上这一家每一行那一条（都是从照片上裁下来扶正的），上面标题、下面那句话。
    /// 任意一行没有原图就返回 nil，让页面说明缺图；不自动换成识别文字绘制的表。
    private func originalImage(name: String, rows: [PassPlanRow]) -> UIImage? {
        let session = store.passPlan
        return PassPlanOriginal.image(name: name, rows: rows, header: session.header, strips: session.strips,
                                      caption: caption(PassPlan.sendableRows(rows)))
    }
}

/// 发到群里的那张图：白底表格，深色模式下也是白底（群里大家看着一样）
struct PassPlanSheet: View {
    let name: String
    let rows: [PassPlanRow]
    var layout: PassPlan.Layout?
    /// 表下面那一行字（「麻烦确认一下数传计划」）
    var caption = ""

    /// 和网页上的表一样：同样的表头、列的先后、行的先后，时间写全；居中、每行一条细线
    var body: some View {
        let table = PassPlan.table(rows, layout: layout)
        let urgentColumn = table.headers.firstIndex { $0.contains("应急") }
        VStack(alignment: .leading, spacing: 12) {
            Text(PassPlan.title(name: name, rows: rows)).font(.system(size: 20, weight: .bold))
            Grid(alignment: .center, horizontalSpacing: 18, verticalSpacing: 0) {
                // 间距加在每一格上（GridRow 本身加修饰会打乱对齐）
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                        Text(header).font(.system(size: 14, weight: .semibold)).padding(.vertical, 10)
                    }
                }
                ForEach(Array(table.cells.enumerated()), id: \.offset) { _, cells in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(Array(cells.enumerated()), id: \.offset) { c, cell in
                            let value = cell.filter { !$0.isWhitespace }
                            let urgent = c == urgentColumn && (value == "是" || value == "应急")
                            Text(cell).font(.system(size: 14, weight: urgent ? .bold : .regular)).monospacedDigit()
                                .foregroundStyle(urgent ? Color.red : Color.black)
                                .padding(.vertical, 10)
                        }
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
            }
            if !caption.isEmpty {
                Text(caption).font(.system(size: 18, weight: .semibold)).padding(.top, 4)
            }
        }
        .foregroundStyle(Color.black)
        .padding(20)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

/// 改一条（认错的字、漏的一条）
struct PassPlanRowEditor: View {
    @State private var row: PassPlanRow
    @State private var emergencyConfirmed = false
    /// 读到的那张表的列：认不出含义的列（是否应急、创建时间……）也能改
    private let layout: PassPlan.Layout?
    private let rules: [PassPlan.OperatorRule]
    private let sourceImage: UIImage?
    private let sourceHeader: UIImage?
    private let sourcePage: UIImage?
    private let sendsOriginal: Bool
    private let originalStatus: String
    private let originalTestStatusDetected: Bool?
    let isNew: Bool
    var onDone: (PassPlanRow?) -> Void
    @Environment(\.dismiss) private var dismiss

    init(row: PassPlanRow, layout: PassPlan.Layout?, rules: [PassPlan.OperatorRule] = [], isNew: Bool,
         sourceImage: UIImage? = nil, sourceHeader: UIImage? = nil, sourcePage: UIImage? = nil, sendsOriginal: Bool = false,
         onDone: @escaping (PassPlanRow?) -> Void) {
        var r = row
        if let layout, r.cells.count < layout.slots.count {
            r.cells += Array(repeating: "", count: layout.slots.count - r.cells.count)
        }
        _row = State(initialValue: r)
        self.layout = layout
        self.rules = rules
        self.sourceImage = sourceImage
        self.sourceHeader = sourceHeader
        self.sourcePage = sourcePage
        self.sendsOriginal = sendsOriginal
        self.originalStatus = row.status
        self.originalTestStatusDetected = row.testStatusDetected
        self.isNew = isNew
        self.onDone = onDone
    }

    /// 只有原表里才有、App 认不出含义的那几列
    private var otherColumns: [Int] {
        guard let layout else { return [] }
        return layout.slots.indices.filter { layout.slots[$0].column == nil && $0 != layout.emergencyIndex }
    }

    private var statusBinding: Binding<String> {
        Binding(get: { row.status }, set: { value in
            row.status = value
            // 明确改过状态后，以核对的新值为准；仅改空格/大小写不能抹掉先前读到 test 的证据。
            let same = value.filter { !$0.isWhitespace }.lowercased() == originalStatus.filter { !$0.isWhitespace }.lowercased()
            row.testStatusDetected = same ? originalTestStatusDetected : nil
        })
    }

    private var emergencySelection: Binding<Int> {
        Binding(get: {
            if emergencyNeedsChoice { return -1 }
            if let value = PassPlan.emergency(row, layout: layout) { return value ? 1 : 0 }
            return layout?.emergencyIndex == nil ? 0 : -1
        }, set: { choice in
            emergencyConfirmed = choice >= 0
            row.emergencyBadge = choice < 0 ? nil : choice == 1
            if let index = layout?.emergencyIndex, row.cells.indices.contains(index) {
                row.cells[index] = choice < 0 ? "" : (choice == 1 ? "是" : "不是")
            }
        })
    }

    private var emergencyNeedsChoice: Bool {
        if emergencyConfirmed { return false }
        return (layout?.emergencyIndex != nil && PassPlan.emergency(row, layout: layout) == nil)
            || row.recognitionIssues?.contains(where: { $0.contains("应急") }) == true
    }

    private var sendingRulesSection: some View {
        Section {
            Picker("计划类型", selection: emergencySelection) {
                if emergencyNeedsChoice { Text("待核对").tag(-1) }
                Text("普通计划").tag(0)
                Text("应急计划").tag(1)
            }
            if emergencyNeedsChoice {
                Text("请对照原图，选择这条是否为应急计划。")
                    .font(.footnote).foregroundStyle(DS.Palette.warning)
            }
            if PassPlan.isExcludedFromSending(row) {
                Label("已排除：不发送给任何一家", systemImage: "nosign")
                    .foregroundStyle(.secondary)
                if row.testStatusDetected == true, row.status.filter({ !$0.isWhitespace }).lowercased() != "test" {
                    Text("有一次识别结果读到 test，请对照原图最右侧的状态列。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("已核对原图，状态不是 test") { row.testStatusDetected = nil }
                }
            }
        } header: {
            Text("应急与发送")
        } footer: {
            Text("最左侧标「应急」的按应急计划处理；最右侧状态为 test 的始终不发送，包括应急计划。")
        }
    }

    private var deliveryFormat: PassPlan.DeliveryFormat { sendsOriginal ? .originalImage : .recognizedContent }

    var body: some View {
        Form {
            if let sourceImage {
                Section {
                    let width = max(900, sourceImage.size.width)
                    let headerHeight = sourceHeader.map { width * $0.size.height / max($0.size.width, 1) } ?? 0
                    let rowHeight = width * sourceImage.size.height / max(sourceImage.size.width, 1)
                    ScrollView([.horizontal, .vertical]) {
                        VStack(spacing: 2) {
                            if let sourceHeader {
                                Image(uiImage: sourceHeader).resizable().scaledToFit().frame(width: width)
                            }
                            Image(uiImage: sourceImage).resizable().scaledToFit().frame(width: width)
                        }
                    }
                    .frame(height: min(280, max(70, headerHeight + rowHeight + 4)))
                    .accessibilityLabel("这一条计划的原照片，左右滑动查看各列")
                } header: {
                    Text("对照原照片")
                } footer: {
                    Text(sendsOriginal
                         ? "左右滑动查看各列。当前发图片使用原照片；修改下面的识别结果会修正分家和文字计划，不会改写照片中的字。"
                         : "左右滑动查看各列，再核对下面的识别结果；发送的文字和重绘图片使用你确认后的内容。")
                }
            }
            if sourceImage == nil, let sourcePage {
                Section("对照整页输入图") {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: sourcePage).resizable().scaledToFit()
                            .frame(width: max(1000, sourcePage.size.width))
                    }
                    .frame(height: 280)
                    .accessibilityLabel("整页照片，滑动查看。没有自动对准某一行。")
                    Text("没有可靠的逐行定位。请在整页里找对应文字，不能把模型提供的位置当成原图行。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            let issues = PassPlan.deliveryProblems(row, format: deliveryFormat, rules: rules, layout: layout)
            if !issues.isEmpty {
                Section("需要核对") {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(DS.Palette.warning)
                    }
                    Text(sendsOriginal ? "核对站名、应急和状态；保存不会确认编号、时间等识别文字。"
                         : "对照原文逐项核对，确认无误后点「保存并确认」。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if sendsOriginal {
                let textIssues = PassPlan.problems(row, rules: rules, layout: layout).filter { !issues.contains($0) }
                if !textIssues.isEmpty {
                    Section {
                        DisclosureGroup("文字发送另有 \(textIssues.count) 项待核对") {
                            ForEach(Array(textIssues.enumerated()), id: \.offset) { _, issue in
                                Text(issue).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text("这些识别疑项不阻止发送原图；改发文字或重绘图片时仍需核对。")
                    }
                }
            }
            Section {
                TextField("卫星名称", text: $row.satellite)
                TextField("卫星 ID", text: $row.satelliteID)
                TextField("圈号", text: $row.orbit).keyboardType(.numberPad)
                TextField("地面站（运营商-站名）", text: $row.station)
            }
            Section {
                TextField("开始时间", text: $row.start)
                TextField("结束时间", text: $row.end)
                TextField("数传信息", text: $row.info)
                TextField("状态", text: statusBinding)
            } footer: {
                Text("时间写成 2026-10-27 22:57:51 这样")
            }
            sendingRulesSection
            if let layout, !otherColumns.isEmpty {
                Section {
                    ForEach(otherColumns, id: \.self) { i in
                        TextField(layout.slots[i].label, text: $row.cells[i])
                    }
                } footer: {
                    Text("这里保留原表中的其他列，按原图核对。")
                }
            }
            if !isNew {
                Section {
                    Button("删掉这一条", role: .destructive) { onDone(nil); dismiss() }
                }
            }
        }
        .navigationTitle(isNew ? "补一条" : "改这一条")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(sendsOriginal ? "保存原图核对" : "保存并确认") {
                    if !sendsOriginal {
                        row.start = PassPlan.normalizedTime(row.start)
                        row.end = PassPlan.normalizedTime(row.end)
                    }
                    row = PassPlan.confirmedDeliveryReview(row, format: deliveryFormat)
                    onDone(row)
                    dismiss()
                }
                .disabled(row.station.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || (!sendsOriginal && row.satellite.isEmpty && row.satelliteID.isEmpty) || emergencyNeedsChoice)
            }
        }
    }
}

extension PassPlanView {
    /// 截图、演示用（虚构）
    static var demoRows: [PassPlanRow] {
        let day = DayKey.today.description
        return [
            PassPlanRow(orbit: "1201", satelliteID: "SAT-A1", satellite: "试验一号", station: "甲站-北区01",
                        start: "\(day) 08:12:30", end: "\(day) 08:20:05", info: "通道1：900M", status: "等待数传"),
            PassPlanRow(orbit: "1202", satelliteID: "SAT-A1", satellite: "试验一号", station: "乙站-东区02",
                        start: "\(day) 09:48:10", end: "\(day) 09:55:42", info: "通道1：900M，通道2：900M", status: "等待数传"),
            PassPlanRow(orbit: "873", satelliteID: "SAT-B2", satellite: "试验二号", station: "甲站-北区05",
                        start: "\(day) 13:05:51", end: "\(day) 13:13:03", info: "通道2：900M", status: "等待数传"),
            PassPlanRow(orbit: "874", satelliteID: "SAT-B2", satellite: "试验二号", station: "丙站-西区01",
                        start: "\(day) 20:31:27", end: "\(day) 20:39:03", info: "通道1：900M", status: "等待数传"),
            PassPlanRow(orbit: "875", satelliteID: "SAT-B2", satellite: "试验二号", station: "丁光北区02",
                        start: "\(day) 22:04:27", end: "\(day) 22:11:21", info: "通道1：900M", status: "等待数传"),
        ]
    }
}

/// 发原图：把从照片上裁下来的几条（表头、这一家的每一行）上下拼成一张，上面标题、下面那句话
enum PassPlanOriginal {
    /// 所有原图出口共用过滤：test 行连原照片切片也不能带入任何一家的图片。
    @MainActor
    static func image(name: String, rows: [PassPlanRow], header: PassPlan.Region?,
                      strips: [PassPlan.Region: Data], caption: String) -> UIImage? {
        let included = PassPlan.sendableRows(rows)
        guard !included.isEmpty, let header, let top = strips[header].flatMap(UIImage.init(data:)) else { return nil }
        var pieces = [top]
        for row in included {
            guard let region = row.region, let strip = strips[region].flatMap(UIImage.init(data:)) else { return nil }
            pieces.append(strip)
        }
        return compose(title: PassPlan.originalImageTitle(name: name, rows: included), caption: caption, strips: pieces)
    }

    @MainActor
    static func compose(title: String, caption: String, strips: [UIImage]) -> UIImage? {
        let width = strips.map(\.size.width).max() ?? 0
        guard width > 0 else { return nil }
        let pad = (width / 50).rounded()
        let titleFont = UIFont.boldSystemFont(ofSize: max(28, width / 36))
        let captionFont = UIFont.systemFont(ofSize: max(26, width / 40), weight: .semibold)
        let heights = strips.map { ($0.size.height * width / max($0.size.width, 1)).rounded() }
        let titleHeight = ceil(titleFont.lineHeight)
        let captionBox = (caption as NSString).boundingRect(with: CGSize(width: width - pad * 2, height: .greatestFiniteMagnitude),
                                                            options: .usesLineFragmentOrigin,
                                                            attributes: [.font: captionFont], context: nil)
        let captionHeight = caption.isEmpty ? 0 : ceil(captionBox.height) + pad
        let total = pad + titleHeight + pad + heights.reduce(0, +) + captionHeight + pad
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: total), format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: width, height: total))
            (title as NSString).draw(at: CGPoint(x: pad, y: pad), withAttributes: [.font: titleFont, .foregroundColor: UIColor.black])
            var y = pad + titleHeight + pad
            for (strip, height) in zip(strips, heights) {
                strip.draw(in: CGRect(x: 0, y: y, width: width, height: height))
                y += height
            }
            if !caption.isEmpty {
                (caption as NSString).draw(with: CGRect(x: pad, y: y + pad, width: width - pad * 2, height: ceil(captionBox.height) + 2),
                                           options: .usesLineFragmentOrigin,
                                           attributes: [.font: captionFont, .foregroundColor: UIColor.black], context: nil)
            }
        }
    }
}
