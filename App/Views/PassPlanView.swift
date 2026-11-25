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

/// 发数传计划：优先支持原相机直拍与相册选图（可选文档扫描/Excel/粘贴），
/// 支持 DeepSeek AI 或本机离线视觉识别、逐条手动修改识别错误，并按运营商对照表顺序一键依次发送。
struct PassPlanView: View {
    @EnvironmentObject private var store: AppStore
    /// 打开时带进来的计划（分享过来的 Excel、截图演示）
    private let initial: PassPlan.Reading?
    /// 从快捷指令「拍数传计划」打开：直接进原相机拍照
    private let autoScan: Bool

    @State private var entryState = PassPlanEntryState()
    @State private var reading = false
    @State private var readingStage = ""
    @State private var readingGeneration = UUID()
    @State private var readingTask: Task<Void, Never>?
    @State private var problem: String?
    @State private var scanning = false
    @State private var showingCamera = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var lastCloudImage: UIImage?
    @State private var capturedPhoto: UIImage?
    @State private var pendingPhoto: PendingPhoto?
    @State private var confirmingCloudPhoto = false
    @State private var showingCloudKey = false
    @State private var cloudKeyConfigured = false
    @State private var preferCloudRecognition = true
    @State private var importing = false
    @State private var editing: EditingRow?
    /// 给这个站新建一家运营商
    @State private var newOperatorFor: String?
    @State private var newOperatorName = ""
    /// 每家的图（读完、改完重新画）
    @State private var images: [String: UIImage] = [:]
    @State private var renderedInput: RenderInput?
    @State private var clearing = false
    @State private var onlyReview = false
    @State private var showingSettings = false
    @State private var sharePreview: PendingPreview?
    @State private var pendingReceipt: String?
    @State private var activeSystemShare: UUID?
    @State private var pendingRoute: PendingRoute?
    @State private var blockedReview: BlockedReviewAlert?

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

    private struct BlockedReviewAlert: Identifiable {
        let id = UUID()
        let rowIndex: Int
        let row: PassPlanRow
        let format: PassPlan.DeliveryFormat
        let summary: String
        let issues: String
    }

    private enum PendingPhoto {
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
                    batchRoutes: store.passPlan.batchRoutes)
    }

    private var imagesAreCurrent: Bool { !reading && renderedInput == renderInput }

    private var imageFormat: PassPlan.DeliveryFormat {
        store.settings.passPlanOriginal && store.passPlan.fromPhotos ? .originalImage : .recognizedContent
    }

    private func imageItem(_ image: UIImage) -> PassPlanShareItem {
        imageFormat == .originalImage ? .originalImage(image) : .renderedImage(image)
    }

    private typealias Audit = [Int: [PassPlan.ReviewIssue]]

    private func effectiveAudit(format: PassPlan.DeliveryFormat) -> Audit {
        let raw = PassPlan.reviewIssues(rows, format: format, rules: rules, layout: layout,
                                        batchRoutes: store.passPlan.batchRoutes)
        guard rules.isEmpty else { return raw }
        // 未建对照表时仍允许按站名「-」前分组预览与依次发送，只保留真实的数据疑项。
        var filtered: Audit = [:]
        for (index, issues) in raw {
            let kept = issues.filter { !$0.message.contains("尚未添加运营商对照表") }
            if !kept.isEmpty { filtered[index] = kept }
        }
        return filtered
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

    /// 分得出是哪家、要发的（标了「不用发」的不算，严格按运营商对照表顺序）
    private var sendable: [OperatorGroup] {
        let skipped = Set(store.settings.passPlanSkipped)
        return allGroups.filter { $0.name != PassPlan.unassigned && !skipped.contains($0.name) }
    }

    private func isDispatched(_ name: String) -> Bool {
        store.passPlan.delivery.handedOff.contains(name) || store.passPlan.confirmedReceipts[name] != nil
    }

    private typealias OperatorGroup = (name: String, rows: [PassPlanRow])

    private struct IndexedOperatorGroup: Identifiable {
        let orderNumber: Int
        let group: OperatorGroup
        var id: String { group.name }
    }

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

    // MARK: - 主页面布局

    private var planBody: some View {
        let checks = effectiveAudit(format: imageFormat)
        let grouped = groupedPlans(checks)
        return ScrollView {
            VStack(spacing: DS.Space.m) {
                captureCard
                if !rows.isEmpty {
                    sequentialDispatchCard(grouped, audit: checks)
                    planCards(grouped, audit: checks)
                }
                settingsCard
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.top, DS.Space.s)
            .padding(.bottom, DS.Space.xl)
            .frame(maxWidth: DS.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
    }

    // MARK: - 顶部采集与识别卡（原相机优先 + 相册直选 + 辅助工具）

    private var captureCard: some View {
        let usingCloud = preferCloudRecognition && cloudKeyConfigured
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            // 标题与识别引擎切换
            HStack(alignment: .center, spacing: DS.Space.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("数传计划识别")
                        .font(DS.Font.headline)
                    Text(usingCloud ? "当前：DeepSeek AI 识别（复杂表格更准）" : "当前：本机离线识别（无需 API Key）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 4)
                Button {
                    if cloudKeyConfigured {
                        withAnimation(DS.Motion.snappy) { preferCloudRecognition.toggle() }
                    } else {
                        showingCloudKey = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: usingCloud ? "sparkles" : "iphone.gen3")
                            .font(.caption2.weight(.semibold))
                        Text(usingCloud ? "DeepSeek" : (cloudKeyConfigured ? "本机离线" : "配 Key"))
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(usingCloud ? DS.Palette.accentSoft : DS.Palette.surfaceSunken, in: Capsule())
                    .foregroundStyle(usingCloud ? DS.Palette.accent : .primary)
                }
                .buttonStyle(.plain)
                .disabled(reading)
            }

            // 两大核心主按钮：原相机拍照 + 从相册选图
            HStack(spacing: DS.Space.s) {
                Button {
                    startCapture(useDocumentScanner: false)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .font(.title3.weight(.semibold))
                            Spacer()
                            Text("推荐")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.22), in: Capsule())
                        }
                        Text("原相机拍照")
                            .font(.headline.weight(.bold))
                        Text("直接调用系统相机拍摄")
                            .font(.caption)
                            .opacity(0.88)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(DS.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: [DS.Palette.accent, DS.Palette.accent.blended(with: .black, 0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                    )
                }
                .buttonStyle(PressableStyle())
                .disabled(reading)
                .accessibilityIdentifier("passplan.capture.camera")

                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(DS.Palette.accent)
                            Spacer()
                        }
                        Text("从相册选图")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("选取已拍照片或截图")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(DS.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                            .strokeBorder(DS.Palette.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(reading)
                .accessibilityIdentifier("passplan.capture.album")
            }

            // 辅助功能 2×2 轻量网格（文档扫描可选，不再强制）
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.xs), GridItem(.flexible(), spacing: DS.Space.xs)],
                      spacing: DS.Space.xs) {
                secondaryActionPill(title: "文档扫描", icon: "doc.viewfinder", tint: DS.Palette.info) {
                    startCapture(useDocumentScanner: true)
                }
                .disabled(reading)
                .accessibilityIdentifier("passplan.capture.scanner")

                secondaryActionPill(title: "导入 Excel", icon: "tablecells", tint: DS.Palette.success) {
                    importing = true
                }
                .disabled(reading)

                secondaryActionPill(title: "粘贴表格", icon: "doc.on.clipboard", tint: DS.Palette.warning) {
                    read { try PlanReader.readClipboard() }
                }
                .disabled(reading)

                NavigationLink {
                    PassPlanOperatorsView()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.number")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DS.Palette.accent)
                        Text(rules.isEmpty ? "运营商对照表" : "运营商（\(rules.count)家）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if reading {
                HStack(spacing: DS.Space.xs) {
                    DSSpinner(size: 15)
                    Text(readingStage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { cancelReading() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.danger)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(DS.Palette.accentSoft, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            }

            if let problem {
                VStack(alignment: .leading, spacing: 8) {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.danger)
                    if let fallbackImage = lastCloudImage {
                        Button {
                            processLocalPhoto(fallbackImage)
                        } label: {
                            Label("改用本机离线识别这张图", systemImage: "text.viewfinder")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(reading)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Palette.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            }
        }
        .card()
    }

    private func secondaryActionPill(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 按顺序发送总控卡

    private func sequentialDispatchCard(_ grouped: GroupedPlans, audit: Audit) -> some View {
        let groups = grouped.sendable
        let names = groups.map(\.name)
        let sentCount = names.filter(isDispatched).count
        let unsent = names.filter { !isDispatched($0) }
        let nextName = unsent.first
        let lostCount = grouped.all.first { $0.name == PassPlan.unassigned }?.rows.count ?? 0
        let queue = unsent.isEmpty ? names : unsent
        let canSendImages = !reading && !names.isEmpty && imagesAreCurrent && !groups.contains { images[$0.name] == nil }

        return VStack(alignment: .leading, spacing: DS.Space.s) {
            // 顶部总览指标条
            HStack(spacing: DS.Space.xs) {
                metricPill(title: "计划条数", value: "\(rows.count)", tint: DS.Palette.accent)
                metricPill(title: "发送进度", value: "\(sentCount)/\(groups.count) 家",
                           tint: sentCount == groups.count && !groups.isEmpty ? DS.Palette.success : DS.Palette.info)
                metricPill(title: "待核对", value: "\(grouped.doubtful) 条",
                           tint: grouped.doubtful > 0 ? DS.Palette.warning : DS.Palette.success)
            }

            // 按顺序发送队列可视化进度条
            if !groups.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("按顺序发送队列", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if sentCount > 0 {
                            Button("重置进度") { invalidateAllDelivery() }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DS.Palette.accent)
                        }
                    }

                    let indexedGroups = groups.enumerated().map { IndexedOperatorGroup(orderNumber: $0.offset + 1, group: $0.element) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(indexedGroups) { entry in
                                let group = entry.group
                                let sent = isDispatched(group.name)
                                let isNext = group.name == nextName
                                let hasIssue = !indexedRows(for: group.name, audit: audit, includeAll: true)
                                    .filter { audit[$0.offset] != nil }.isEmpty
                                Button {
                                    openPreview([group.name], useText: false)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("\(entry.orderNumber)")
                                            .font(.caption2.weight(.bold).monospacedDigit())
                                            .frame(width: 17, height: 17)
                                            .background(sent ? DS.Palette.success : (isNext ? DS.Palette.accent : DS.Palette.hairline), in: Circle())
                                            .foregroundStyle(sent || isNext ? .white : .secondary)
                                        Text(group.name)
                                            .font(.caption.weight(isNext ? .bold : .semibold))
                                            .foregroundStyle(isNext ? DS.Palette.accent : .primary)
                                        if sent {
                                            Image(systemName: "checkmark")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(DS.Palette.success)
                                        } else if hasIssue {
                                            Circle()
                                                .fill(DS.Palette.warning)
                                                .frame(width: 6, height: 6)
                                        } else if isNext {
                                            Text("下一家")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(DS.Palette.accent)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        isNext ? DS.Palette.accentSoft : (sent ? DS.Palette.success.opacity(0.10) : DS.Palette.surfaceSunken),
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(isNext ? DS.Palette.accent.opacity(0.45) : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // 主操作按钮：按顺序依次发图（发完一家自动弹下一家，无需填群名）
                Button {
                    sendInTurn(queue, useText: false)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: unsent.isEmpty ? "arrow.clockwise" : "paperplane.fill")
                            .font(.subheadline.weight(.bold))
                        Text(chainButtonTitle(names: names, unsent: unsent))
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(
                            colors: canSendImages
                                ? [DS.Palette.accent, DS.Palette.accent.blended(with: .black, 0.18)]
                                : [Color.gray.opacity(0.45), Color.gray.opacity(0.45)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    )
                }
                .buttonStyle(PressableStyle())
                .disabled(!canSendImages || activeSystemShare != nil)
                .accessibilityIdentifier("passplan.sequential.send")

                // 次级操作行：按顺序发文字 / 发前预览 / 补一条
                HStack(spacing: DS.Space.xs) {
                    Button {
                        sendInTurn(queue, useText: true)
                    } label: {
                        Label("按顺序发文字", systemImage: "text.alignleft")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(reading || activeSystemShare != nil)

                    Button {
                        openPreview(names, useText: false)
                    } label: {
                        Label("总览预览", systemImage: "eye")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(reading)

                    Button {
                        editing = EditingRow(sourceID: store.passPlan.sourceID, index: nil, row: PassPlanRow(), format: .recognizedContent)
                    } label: {
                        Label("补一条", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(reading)
                }
            } else {
                Button {
                    editing = EditingRow(sourceID: store.passPlan.sourceID, index: nil, row: PassPlanRow(), format: .recognizedContent)
                } label: {
                    Label("手动补录一条计划", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(DS.Palette.accentSoft, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        .foregroundStyle(DS.Palette.accent)
                }
                .buttonStyle(.plain)
            }

            // 筛选条 + 简洁状态提示（默认显示全部，点击任意行即可手动修改）
            Picker("查看范围", selection: $onlyReview) {
                Text("全部（\(rows.count)）").tag(false)
                Text("仅存疑（\(grouped.doubtful)）").tag(true)
            }
            .pickerStyle(.segmented)

            if onlyReview && grouped.doubtful == 0 {
                Label("没有标黄存疑项，切换到「全部」可查看或修改任意一条计划。", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.success)
            }
            if lostCount > 0 {
                Label("\(lostCount) 条暂未归属到运营商，请在下方先指定归属或点开修改站名。", systemImage: "questionmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warning)
            }
            if grouped.excluded > 0 {
                Label("\(grouped.excluded) 条 test 状态计划已自动排除，不参与发送。", systemImage: "nosign")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if rules.isEmpty {
                Text("当前按站名「-」前自动分组；在「运营商对照表」中可固定各家发送顺序。系统分享后直接选微信群，无需提前填群名。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("点「按顺序依次发图」会从第 1 家起依次弹出微信分享，发完一家自动弹下一家；点任意一条计划可随时手动修改。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !grouped.idle.isEmpty && !onlyReview {
                Text("本批无计划：\(grouped.idle.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("passplan.sequential.card")
    }

    private func metricPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
    }

    private func chainButtonTitle(names: [String], unsent: [String]) -> String {
        if unsent.isEmpty { return "再按顺序发一遍（\(names.count) 家）" }
        let next = unsent[0]
        if unsent.count == names.count {
            return "按顺序依次发图（\(names.count) 家 · 首家：\(next)）"
        }
        return "接着按顺序发剩下 \(unsent.count) 家（下家：\(next)）"
    }

    // MARK: - 运营商卡片列表

    @ViewBuilder
    private func planCards(_ grouped: GroupedPlans, audit: Audit) -> some View {
        if let lost = grouped.all.first(where: { $0.name == PassPlan.unassigned }) {
            unassignedCard(lost.rows, known: grouped.sendable.map(\.name), audit: audit)
        }

        let visibleSendable = grouped.sendable.enumerated().compactMap { offset, group -> IndexedOperatorGroup? in
            (!onlyReview || !indexedRows(for: group.name, audit: audit).isEmpty)
                ? IndexedOperatorGroup(orderNumber: offset + 1, group: group)
                : nil
        }
        ForEach(visibleSendable) { entry in
            operatorCard(entry.group, orderNumber: entry.orderNumber, audit: audit)
        }

        let resting = grouped.resting.filter { !onlyReview || !indexedRows(for: $0.name, audit: audit).isEmpty }
        if !resting.isEmpty {
            restingCard(resting, audit: audit)
        }

        if !onlyReview, grouped.excluded > 0 {
            excludedCard
        }
    }

    private func operatorCard(_ group: OperatorGroup, orderNumber: Int, audit: Audit) -> some View {
        let name = group.name
        let urgent = group.rows.contains { PassPlan.emergency($0, layout: layout) == true }
        let dispatched = isDispatched(name)
        let confirmed = store.passPlan.confirmedReceipts[name] != nil
        let visibleRows = indexedRows(for: name, audit: audit)
        let canShareImage = !reading && imagesAreCurrent && images[name] != nil

        return VStack(alignment: .leading, spacing: DS.Space.s) {
            // 卡片头部：序号 + 运营商名 + 状态标签 + 简洁菜单（无目标群名干扰）
            HStack(spacing: DS.Space.xs) {
                Text("#\(orderNumber)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(dispatched ? DS.Palette.success.opacity(0.16) : DS.Palette.accentSoft, in: Capsule())
                    .foregroundStyle(dispatched ? DS.Palette.success : DS.Palette.accent)

                Text(name)
                    .font(DS.Font.headline)

                Text("\(group.rows.count) 条")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if urgent {
                    Text("应急")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.Palette.danger, in: Capsule())
                }

                if confirmed {
                    Label("已确认", systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DS.Palette.success)
                } else if dispatched {
                    Label("已发", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DS.Palette.success)
                }

                Spacer(minLength: 4)

                Menu {
                    if !confirmed {
                        Button {
                            markOperatorConfirmed(name)
                        } label: {
                            Label("标记对方已收到", systemImage: "checkmark.seal")
                        }
                    }
                    if dispatched || store.passPlan.delivery.requested.contains(name) {
                        Button {
                            invalidateDelivery(name)
                        } label: {
                            Label("重置为未发送", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Button {
                        openPreview([name], useText: false)
                    } label: {
                        Label("预览图片与内容", systemImage: "eye")
                    }
                    Divider()
                    Button(role: .destructive) {
                        store.settings.passPlanSkipped.append(name)
                    } label: {
                        Label("标为不用发", systemImage: "eye.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
            }

            // 计划逐行列表（点击任意行即可修改识别错误）
            VStack(spacing: DS.Space.xs) {
                ForEach(visibleRows, id: \.offset) { item in
                    rowCard(item.element, at: item.offset, issues: audit[item.offset] ?? [])
                }
            }

            outputDescription(for: group.rows)

            // 单家直发按钮行（发图片 / 发文字 / 预览）
            HStack(spacing: DS.Space.xs) {
                Button {
                    sendInTurn([name], useText: false)
                } label: {
                    Label(dispatched ? "重发图片" : "发图片", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            canShareImage ? DS.Palette.accent : Color.gray.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressableStyle())
                .disabled(!canShareImage || activeSystemShare != nil)

                Button {
                    sendInTurn([name], useText: true)
                } label: {
                    Label("发文字", systemImage: "text.alignleft")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(PressableStyle())
                .disabled(reading || activeSystemShare != nil)

                Button {
                    openPreview([name], useText: false)
                } label: {
                    Image(systemName: "eye")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(PressableStyle())
                .disabled(reading)
                .accessibilityLabel("预览 \(name) 计划图片")
            }
        }
        .card(tint: urgent ? DS.Palette.danger : (dispatched ? DS.Palette.success : nil))
    }

    private func unassignedCard(_ rows: [PassPlanRow], known: [String], audit: Audit) -> some View {
        let stations = Array(Set(rows.map(\.station))).sorted()
        let names = (rules.map(\.name) + known).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let cloud = store.passPlan.fromDeepSeek

        return VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Label("\(PassPlan.unassigned) · \(rows.count) 条", systemImage: "questionmark.circle.fill")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Palette.warning)
                Spacer()
            }

            ForEach(stations, id: \.self) { station in
                let candidates = PassPlan.stationCandidates(of: station, rules: rules)
                let conflicting = candidates.count > 1
                let nearAliases = cloud && !conflicting ? PassPlan.nearbyStationAliases(of: station, rules: rules) : []
                let similar = conflicting ? nil : PassPlan.likelyOperator(of: station, rules: rules)
                let neighbor = conflicting ? nil : PassPlan.neighborOperator(of: station, in: PassPlan.sendableRows(self.rows), rules: rules)
                let likely = similar ?? neighbor
                let reason = conflicting ? " · 对照表冲突：\(candidates.joined(separator: "、"))"
                    : !nearAliases.isEmpty ? " · 相近站名：\(nearAliases.joined(separator: "、"))"
                    : similar.map { " · 猜测：像「\($0)」" } ?? neighbor.map { " · 猜测：邻近「\($0)」" } ?? ""

                HStack(spacing: DS.Space.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station.isEmpty ? "（未识别出站名）" : station)
                            .font(.subheadline.weight(.semibold))
                        Text("\(rows.filter { $0.station == station }.count) 条" + reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                            Text("修正对照表")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(DS.Palette.warning.opacity(0.15), in: Capsule())
                                .foregroundStyle(DS.Palette.warning)
                        }
                    } else if !PassPlan.normalizedStationAlias(station).isEmpty {
                        Menu {
                            if !rules.isEmpty {
                                Menu("仅限本批归属") {
                                    ForEach(Array(Set(rules.map(\.name))).sorted(), id: \.self) { name in
                                        Button(name) {
                                            pendingRoute = PendingRoute(sourceID: store.passPlan.sourceID, station: station, name: name)
                                        }
                                    }
                                }
                            }
                            ForEach(names, id: \.self) { name in
                                Button(name == likely ? "记住归 \(name)（推荐）" : "记住归 \(name)") { assign(station, to: name) }
                            }
                            Button {
                                newOperatorName = ""
                                newOperatorFor = station
                            } label: {
                                Label("新建一家运营商…", systemImage: "plus")
                            }
                        } label: {
                            Label(cloud || likely == nil ? "分给哪家" : "改归属", systemImage: "arrow.turn.down.right")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(DS.Palette.accentSoft, in: Capsule())
                                .foregroundStyle(DS.Palette.accent)
                        }
                    }
                }
                .padding(10)
                .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            }

            VStack(spacing: DS.Space.xs) {
                ForEach(indexedRows(for: PassPlan.unassigned, audit: audit), id: \.offset) { item in
                    rowCard(item.element, at: item.offset, issues: audit[item.offset] ?? [])
                }
            }

            Text("点「分给哪家」即可归类；若站名识别有错字，点下方任意一条直接修改。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card(tint: DS.Palette.warning)
    }

    private func restingCard(_ groups: [OperatorGroup], audit: Audit) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("不用发的运营商")
                .font(DS.Font.headline)
                .foregroundStyle(.secondary)
            ForEach(groups, id: \.name) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(group.name) · \(group.rows.count) 条")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复发送") {
                            store.settings.passPlanSkipped.removeAll { $0 == group.name }
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DS.Palette.accentSoft, in: Capsule())
                        .foregroundStyle(DS.Palette.accent)
                    }
                    ForEach(indexedRows(for: group.name, audit: audit), id: \.offset) { item in
                        rowCard(item.element, at: item.offset, issues: audit[item.offset] ?? [])
                    }
                }
            }
        }
        .card()
    }

    private var excludedCard: some View {
        let excluded = rows.enumerated().filter { PassPlan.isExcludedFromSending($0.element) }
        return DisclosureGroup {
            VStack(spacing: DS.Space.xs) {
                ForEach(excluded, id: \.offset) { item in
                    rowCard(item.element, at: item.offset)
                }
            }
            .padding(.top, DS.Space.xs)
        } label: {
            Label("已排除 \(excluded.count) 条 test 计划（不发送）", systemImage: "nosign")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .card()
    }

    // MARK: - 单条可编辑计划行卡片（显式「修改」入口）

    private func rowCard(_ row: PassPlanRow, at index: Int, issues: [PassPlan.ReviewIssue] = []) -> some View {
        let sourceID = store.passPlan.sourceID
        let problems = issues.map(\.message)
        let flagged = !PassPlan.isExcludedFromSending(row) && !problems.isEmpty
        let timeText = [PassPlan.shortTime(row.start), PassPlan.shortTime(row.end)]
            .filter { !$0.isEmpty }
            .joined(separator: " – ")
        let satText = row.satellite.isEmpty ? row.satelliteID : row.satellite
        let metaText = [row.station, row.orbit.isEmpty ? "" : "圈 \(row.orbit)",
                        row.satellite.isEmpty ? "" : row.satelliteID, row.info]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return Button {
            edit(row, at: index, sourceID: sourceID)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    if imageFormat == .originalImage {
                        Text(row.station.isEmpty ? "未识别站名" : row.station)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    } else {
                        Text(timeText.isEmpty ? "时间待补充" : timeText)
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(timeText.isEmpty ? DS.Palette.warning : .primary)
                    }

                    if PassPlan.emergency(row, layout: layout) == true {
                        Text("应急")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DS.Palette.danger, in: Capsule())
                    }
                    if PassPlan.isExcludedFromSending(row) {
                        Text("test")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DS.Palette.hairline, in: Capsule())
                    }

                    Spacer(minLength: 4)

                    if imageFormat != .originalImage, !satText.isEmpty {
                        Text(satText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    // 显式「修改」微胶囊：一眼知道每条识别结果都能手动改
                    HStack(spacing: 3) {
                        Image(systemName: "pencil")
                            .font(.caption2.weight(.bold))
                        Text("修改")
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(flagged ? DS.Palette.warning.opacity(0.22) : DS.Palette.accentSoft, in: Capsule())
                    .foregroundStyle(flagged ? DS.Palette.warning : DS.Palette.accent)
                }

                if imageFormat == .originalImage {
                    if let region = row.region, let data = store.passPlan.strips[region], let source = UIImage(data: data) {
                        Image(uiImage: source)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .accessibilityLabel("这条计划的原图，点开可放大核对与修改")
                    } else {
                        Label("缺少这一行的原图切片，点开核对或切换重绘表格", systemImage: "photo.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.warning)
                    }
                } else if !metaText.isEmpty {
                    Text(metaText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if flagged {
                    Label(problems.joined(separator: "；"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.warning)
                        .multilineTextAlignment(.leading)
                }

                if let reviewed = row.reviewedWarnings, !reviewed.isEmpty {
                    Text("已人工核对：\(reviewed.joined(separator: "；"))")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.success)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                flagged ? DS.Palette.warning.opacity(0.11) : DS.Palette.surfaceSunken,
                in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .strokeBorder(flagged ? DS.Palette.warning.opacity(0.35) : DS.Palette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(reading)
        .contextMenu {
            Button {
                edit(row, at: index, sourceID: sourceID)
            } label: {
                Label("手动修改这一条", systemImage: "pencil")
            }
            if !PassPlan.isExcludedFromSending(row), !PassPlan.normalizedStationAlias(row.station).isEmpty,
               PassPlan.stationCandidates(of: row.station, rules: rules).count < 2 && !rules.isEmpty {
                Menu("仅本批改归属") {
                    ForEach(Array(Set(rules.map(\.name))).sorted(), id: \.self) { name in
                        Button(name) { pendingRoute = PendingRoute(sourceID: sourceID, station: row.station, name: name) }
                    }
                }
            }
            Divider()
            Button(role: .destructive) {
                delete(row, at: index, sourceID: sourceID)
            } label: {
                Label("删除这一条", systemImage: "trash")
            }
        }
    }

    // MARK: - 底部折叠设置卡

    private var settingsCard: some View {
        DisclosureGroup(isExpanded: $showingSettings) {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Divider()
                NavigationLink {
                    PassPlanOperatorsView()
                } label: {
                    HStack {
                        Label("运营商对照表与发送顺序", systemImage: "list.number")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(rules.isEmpty ? "未配置" : "\(rules.count) 家")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }

                Divider()

                Button {
                    showingCloudKey = true
                } label: {
                    HStack {
                        Label("DeepSeek API Key", systemImage: "key.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(cloudKeyConfigured ? "已配置" : "未设置")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(cloudKeyConfigured ? DS.Palette.success : .secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                Divider()

                Toggle(isOn: $store.settings.passPlanOriginal) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("图片优先裁切原图")
                            .font(.subheadline.weight(.medium))
                        Text(store.settings.passPlanOriginal
                             ? "本机离线识别时裁切原照片各行；手动修改文字后建议关闭此项以发重绘表格"
                             : "根据核对修改后的文字重新绘制清晰白底表格图")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("图片附带提示语")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("普通计划提示语（例如：麻烦确认一下数传计划）", text: $store.settings.passPlanCaption)
                        .textFieldStyle(DSFieldStyle())
                    TextField("应急计划提示语（含应急行时自动使用）", text: $store.settings.passPlanUrgentCaption)
                        .textFieldStyle(DSFieldStyle())
                }

                Divider()

                Toggle("每天定时提醒发计划", isOn: $store.settings.passPlanReminder)
                    .font(.subheadline.weight(.medium))
                if store.settings.passPlanReminder {
                    DatePicker("提醒时间", selection: reminderTime, displayedComponents: .hourAndMinute)
                        .font(.subheadline)
                }
            }
            .padding(.top, DS.Space.xs)
        } label: {
            HStack {
                Label("发送与提醒设置", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(store.settings.passPlanOriginal ? "原图优先" : "重绘表格")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: - 导航、弹窗与输入

    private var navigationContent: some View {
        planBody
            .navigationTitle("发数传计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !rows.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("清空", role: .destructive) { clearing = true }
                    }
                }
            }
    }

    private var reviewContent: some View {
        navigationContent
            .confirmationDialog("把读到的计划全部清空？", isPresented: $clearing, titleVisibility: .visible) {
                Button("全部清空", role: .destructive) {
                    restoreReminderIfNeeded()
                    store.passPlan = PassPlanSession()
                    problem = nil
                }
            }
            .alert(item: $pendingRoute) { chosen in
                Alert(title: Text("仅修改本批归属？"),
                      message: Text("把「\(chosen.station)」仅在本批归给「\(chosen.name)」，不改动运营商对照表。"),
                      primaryButton: .default(Text("确认")) { applyBatchRoute(chosen) },
                      secondaryButton: .cancel())
            }
            .alert(item: $blockedReview) { item in
                Alert(
                    title: Text("先核对或修改这一条"),
                    message: Text("\(item.summary)\n\n\(item.issues)"),
                    primaryButton: .default(Text("去修改")) {
                        edit(item.row, at: item.rowIndex, sourceID: store.passPlan.sourceID, format: item.format)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
    }

    private var captureContent: some View {
        reviewContent
            .fullScreenCover(isPresented: $scanning, onDismiss: handleCapturedPhotoDismiss) {
                DocumentScanner { pages in acceptCapturedPages(pages) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showingCamera, onDismiss: handleCapturedPhotoDismiss) {
                CameraPicker { image in acceptCapturedPages([image]) }
                    .ignoresSafeArea()
            }
            .onChange(of: pickedPhoto) { item in
                guard let item else { return }
                pickedPhoto = nil
                guard !reading else { return }
                handleSelectedAlbumItem(item)
            }
            .confirmationDialog("选择这张图的识别方式", isPresented: $confirmingCloudPhoto, titleVisibility: .visible) {
                Button("用 DeepSeek AI 识别") { processCloudPhoto() }
                Button("改用本机离线识别（不联网）") { processLocalPendingPhoto() }
                Button("取消", role: .cancel) { pendingPhoto = nil }
            } message: {
                Text("选择 DeepSeek AI 会上传这张单图并使用你的 API 额度；也可以直接用本机离线识别，识别后都支持逐条手动修改。")
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
            .sheet(item: $sharePreview, onDismiss: { pendingReceipt = nil }) { request in
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
                Button("保存", action: saveOperatorName)
                Button("取消", role: .cancel) { newOperatorFor = nil }
            } message: {
                if store.passPlan.fromDeepSeek {
                    Text("只把完整站名「\(newOperatorFor ?? "")」记给这一家；不会影响相似站名。")
                } else {
                    Text("「\(newOperatorFor.map(PassPlan.suggestedPrefix(of:)) ?? "")」开头的站以后都算这一家")
                }
            }
    }

    private var newOperatorPresented: Binding<Bool> {
        Binding(get: { newOperatorFor != nil }, set: { if !$0 { newOperatorFor = nil } })
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
            ToastCenter.shared.show("计划已经更新，请重新打开要修改的那一条", style: .warning)
            return
        }
        if let i = target.index {
            guard store.passPlan.rows.indices.contains(i), store.passPlan.rows[i] == target.row else {
                ToastCenter.shared.show("这一条已经变化，请重新打开修改", style: .warning)
                return
            }
            let old = store.passPlan.rows[i]
            if let saved {
                store.passPlan.rows[i] = saved
                // 如果用户手动修正了文字内容，而当前开着「发原图」，提醒用户自动切回重绘表格或保持文字更新
                if editedTextFields(old, saved), store.settings.passPlanOriginal, store.passPlan.fromPhotos {
                    store.settings.passPlanOriginal = false
                    ToastCenter.shared.show("已保存修改，并自动切换为重绘表格图以体现修改内容", style: .success)
                }
            } else {
                store.passPlan.rows.remove(at: i)
            }
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

    // MARK: - 拍照与选图流程（默认原相机，不强制扫描，无 Key 也可离线识别）

    private func startCapture(useDocumentScanner: Bool = false) {
        guard !reading else { return }
        capturedPhoto = nil
        problem = nil
        if useDocumentScanner && DocumentScanner.isSupported {
            scanning = true
        } else {
            showingCamera = true
        }
    }

    private func acceptCapturedPages(_ pages: [UIImage]) {
        capturedPhoto = nil
        guard let image = pages.first else { return }
        if pages.count > 1 && preferCloudRecognition && cloudKeyConfigured {
            problem = "DeepSeek 单次仅识别一张完整计划图；若需多页扫描请改用本机离线识别，或拍摄单张完整计划图。"
            return
        }
        capturedPhoto = image
    }

    private func handleCapturedPhotoDismiss() {
        guard let image = capturedPhoto else { return }
        capturedPhoto = nil
        guard !reading else { return }
        loadCloudKeyStatus()
        if preferCloudRecognition && cloudKeyConfigured {
            pendingPhoto = .capture(image)
            confirmingCloudPhoto = true
        } else {
            processLocalPhoto(image)
        }
    }

    private func handleSelectedAlbumItem(_ item: PhotosPickerItem) {
        loadCloudKeyStatus()
        if preferCloudRecognition && cloudKeyConfigured {
            pendingPhoto = .album(item)
            confirmingCloudPhoto = true
        } else {
            processLocalAlbumItem(item)
        }
    }

    private func loadCloudKeyStatus() {
        let configured = !(Keychain.get(.deepSeekPlanAPIKey) ?? "").isEmpty
        cloudKeyConfigured = configured
        if !configured {
            preferCloudRecognition = false
        }
    }

    private func processCloudPhoto() {
        guard let item = pendingPhoto else { return }
        pendingPhoto = nil
        guard let key = Keychain.get(.deepSeekPlanAPIKey), !key.isEmpty else {
            showingCloudKey = true
            problem = "请先设置 DeepSeek API Key，或切换到「本机离线」直接识别。"
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
            readingStage = "正在用 DeepSeek AI 识别…"
            let readingResult = try await DeepSeekPlanReader.read(imageData: data, apiKey: key)
            lastCloudImage = nil
            return (readingResult, data)
        }
    }

    private func processLocalPendingPhoto() {
        guard let item = pendingPhoto else { return }
        pendingPhoto = nil
        switch item {
        case .album(let selected):
            processLocalAlbumItem(selected)
        case .capture(let captured):
            processLocalPhoto(captured)
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

    private func prepareOnAppear() {
        let actions = entryState.consume(initial: initial, autoScan: autoScan)
        if let initial = actions.reading {
            restoreReminderIfNeeded()
            store.passPlan = PassPlanSession(
                fromPhotos: initial.header != nil || initial.rows.contains { $0.region != nil },
                rows: initial.rows, layout: initial.layout, header: initial.header, strips: initial.strips
            )
        }
        if actions.autoScan {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                startCapture(useDocumentScanner: false)
            }
        }
    }

    // MARK: - 读、改、发逻辑

    private func indexedRows(for name: String, audit: Audit, includeAll: Bool = false) -> [(offset: Int, element: PassPlanRow)] {
        rows.enumerated().filter {
            !PassPlan.isExcludedFromSending($0.element)
                && (resolved($0.element.station) ?? PassPlan.unassigned) == name
                && (includeAll || !onlyReview || audit[$0.offset] != nil)
        }
    }

    @ViewBuilder
    private func outputDescription(for rows: [PassPlanRow]) -> some View {
        if store.settings.passPlanOriginal && store.passPlan.fromPhotos {
            let missing = rows.filter { $0.region.flatMap { store.passPlan.strips[$0] } == nil }.count
            let hasHeader = store.passPlan.header.flatMap { store.passPlan.strips[$0] } != nil
            if missing > 0 || !hasHeader {
                VStack(alignment: .leading, spacing: 6) {
                    Label(missing > 0 ? "这家有 \(missing) 条缺少原图切片，暂不能拼原图" : "未裁出完整表头，暂不能拼原图",
                          systemImage: "photo.badge.exclamationmark")
                    Button("切换为重绘表格图") { store.settings.passPlanOriginal = false }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                }
                .font(.caption)
                .foregroundStyle(DS.Palette.warning)
            }
        }
    }

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
        readingStage = fromDeepSeek ? "正在载入图片…" : "正在识别计划…"
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
                guard readingGeneration == generation, store.passPlan.sourceID == sourceID else { return }
                let found = result.rows
                restoreReminderIfNeeded()
                withAnimation(DS.Motion.snappy) {
                    store.passPlan = PassPlanSession(
                        fromPhotos: !fromDeepSeek && (result.header != nil || !result.strips.isEmpty),
                        fromDeepSeek: fromDeepSeek,
                        rows: found,
                        layout: result.layout,
                        sourcePage: sourcePage,
                        header: result.header,
                        strips: result.strips
                    )
                    onlyReview = false
                }
                let doubtful = effectiveAudit(format: imageFormat).keys.count
                let excluded = found.filter(PassPlan.isExcludedFromSending).count
                let grouped = PassPlan.grouped(found, rules: rules)
                let lost = grouped.first { $0.name == PassPlan.unassigned }?.rows.count ?? 0
                let families = grouped.filter { $0.name != PassPlan.unassigned }.count
                var message = "\(fromDeepSeek ? "DeepSeek " : "")识别出 \(found.count) 条，分成 \(families) 家"
                if excluded > 0 { message += "（已排除 \(excluded) 条 test）" }
                if lost > 0 { message += "；\(lost) 条待选归属" } else if doubtful > 0 { message += "；\(doubtful) 条标黄待核对" }
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
    }

    private func edit(_ row: PassPlanRow, at index: Int, sourceID: UUID, format: PassPlan.DeliveryFormat? = nil) {
        guard !reading else { return }
        guard sourceID == store.passPlan.sourceID, rows.indices.contains(index), rows[index] == row else {
            ToastCenter.shared.show("这一条已经变化，请重新打开修改", style: .warning)
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
            ToastCenter.shared.show("这一条已经变化，请重新操作", style: .warning)
            return
        }
        store.passPlan.rows.remove(at: index)
        store.passPlan.changesRecordedAt = Date()
        if let name = resolved(row.station) { invalidateDelivery(name) }
    }

    // MARK: - 按顺序依次发送（恢复并升级，零目标群名门槛）

    private func firstBlockingReview(for names: [String], format: PassPlan.DeliveryFormat) -> BlockedReviewAlert? {
        let checks = effectiveAudit(format: format)
        for name in names {
            let items = indexedRows(for: name, audit: checks, includeAll: true)
            for item in items {
                if let issues = checks[item.offset], !issues.isEmpty {
                    let label = item.element.satellite.isEmpty ? item.element.satelliteID : item.element.satellite
                    return BlockedReviewAlert(
                        rowIndex: item.offset,
                        row: item.element,
                        format: format,
                        summary: "\(name) · \(label.isEmpty ? "未命名卫星" : label)（\(item.element.station)）",
                        issues: issues.map(\.message).joined(separator: "；")
                    )
                }
            }
        }
        return nil
    }

    /// 按运营商对照表顺序依次分享：发完一家自动弹下一家；取消即暂停并提示下一家是谁。
    private func sendInTurn(_ names: [String], step: Int = 1, total: Int? = nil, useText: Bool) {
        guard !reading, activeSystemShare == nil, !names.isEmpty else { return }
        let format: PassPlan.DeliveryFormat = useText ? .recognizedContent : imageFormat
        if step == 1, let blocker = firstBlockingReview(for: names, format: format) {
            blockedReview = blocker
            return
        }

        let totalCount = total ?? names.count
        guard let name = names.first, let group = sendable.first(where: { $0.name == name }) else { return }
        let snapshotInput = renderInput

        let item: PassPlanShareItem
        if useText {
            let message = PassPlan.message(name: name, rows: group.rows, layout: layout, caption: caption(group.rows))
            guard !message.isEmpty else { return }
            item = .text(message)
        } else {
            guard imagesAreCurrent, let image = images[name] else {
                ToastCenter.shared.show("图片正在生成中，请稍候再试", style: .warning)
                return
            }
            item = imageItem(image)
        }

        let title = totalCount > 1 ? "\(step)/\(totalCount) · \(name)数传计划" : "\(name)数传计划"
        let activityID = UUID()
        activeSystemShare = activityID
        store.passPlan.delivery.requestShare(name)
        let payload = SharePayload(item.value, title: title, preview: useText ? nil : images[name])

        ActivityShare.present([payload], excluding: ActivityShare.chatOnly) { completed in
            guard activeSystemShare == activityID else { return }
            activeSystemShare = nil
            guard snapshotInput == renderInput else { return }
            store.passPlan.delivery.reportHandoff(name, completed: completed)
            let rest = Array(names.dropFirst())
            if completed {
                if !rest.isEmpty {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 280_000_000)
                        guard snapshotInput == renderInput else { return }
                        sendInTurn(rest, step: step + 1, total: totalCount, useText: useText)
                    }
                } else {
                    markAllSentIfComplete(totalCount: totalCount)
                }
            } else if totalCount > 1 {
                ToastCenter.shared.show("已停在「\(name)」，点「接着按顺序发」可从这家继续", style: .warning)
            }
        }
    }

    private func markAllSentIfComplete(totalCount: Int) {
        let allNames = sendable.map(\.name)
        let hasUnassigned = allGroups.contains(where: { $0.name == PassPlan.unassigned })
        if !hasUnassigned, !allNames.isEmpty, allNames.allSatisfy(isDispatched) {
            store.settings.passPlanSentDay = .today
            Task { await store.schedulePlanReminder() }
        }
        ToastCenter.shared.show(totalCount > 1 ? "全部 \(totalCount) 家已按顺序发送完成" : "发送操作已完成", style: .success)
    }

    private func markOperatorConfirmed(_ name: String) {
        if !store.passPlan.delivery.requested.contains(name) {
            store.passPlan.delivery.requestShare(name)
            store.passPlan.delivery.reportHandoff(name, completed: true)
        }
        _ = store.passPlan.delivery.confirmReceipt(name, at: Date())
        let names = Set(sendable.map(\.name))
        let hasUnassigned = allGroups.contains(where: { $0.name == PassPlan.unassigned })
        if !hasUnassigned, !names.isEmpty, names.isSubset(of: Set(store.passPlan.confirmedReceipts.keys)) {
            store.settings.passPlanSentDay = .today
            ToastCenter.shared.show("本批各家均已确认收到", style: .success)
            Task { await store.schedulePlanReminder() }
        }
    }

    // MARK: - 发送前总览预览（无目标群名限制）

    private func openPreview(_ names: [String], useText: Bool) {
        guard !reading, !names.isEmpty else { return }
        sharePreview = PendingPreview(input: renderInput, names: names, useText: useText,
                                      format: useText ? .recognizedContent : imageFormat)
    }

    private func sharePreviewView(_ request: PendingPreview) -> some View {
        let current = request.input == renderInput && !reading
        let groups = sendable.filter { request.names.contains($0.name) }
        let checks = current ? effectiveAudit(format: request.format) : [:]
        let unassignedCount = allGroups.first(where: { $0.name == PassPlan.unassigned })?.rows.count ?? 0

        return NavigationStack {
            List {
                Section {
                    Text("确认每家条数与图片无误后，点「打开分享面板」直接在微信中选择群发送，无需提前填写群名。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if unassignedCount > 0 {
                        Label("\(unassignedCount) 条未确定归属或冲突的计划不在本次分享中。", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.warning)
                    }
                    if current && groups.count > 1 {
                        Button {
                            sharePreview = nil
                            let queue = groups.map(\.name)
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                sendInTurn(queue, useText: request.useText)
                            }
                        } label: {
                            Label("按顺序依次发送这 \(groups.count) 家", systemImage: "paperplane.fill")
                                .font(.headline)
                        }
                    }
                }
                if !current {
                    Section {
                        Label("本批计划或分组已变更，请关闭后重新预览。", systemImage: "arrow.clockwise")
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
            .confirmationDialog("确认对方已收到？", isPresented: receiptPresented, titleVisibility: .visible) {
                Button("已确认收到") {
                    if let name = pendingReceipt { confirmReceipt(name, request: request) }
                    pendingReceipt = nil
                }
                Button("取消", role: .cancel) { pendingReceipt = nil }
            } message: {
                Text("记录「\(pendingReceipt ?? "")」已收到本批数传计划，便于值班交接核对。")
            }
        }
    }

    private var receiptPresented: Binding<Bool> {
        Binding(get: { pendingReceipt != nil }, set: { if !$0 { pendingReceipt = nil } })
    }

    private func sharePreviewSection(_ group: OperatorGroup, request: PendingPreview, checks: Audit) -> some View {
        let name = group.name
        let indices = indexedRows(for: name, audit: checks, includeAll: true).map(\.offset)
        let checked = indices.flatMap { checks[$0] ?? [] }
        var shown = Set<String>()
        let distinctMessages = checked.map(\.message).filter { shown.insert($0).inserted }
        let content = request.useText ? PassPlan.message(name: name, rows: group.rows, layout: layout,
                                                           caption: caption(group.rows)) : nil
        let photo = !request.useText && imagesAreCurrent ? images[name] : nil
        let enabled = checked.isEmpty && ((content?.isEmpty == false) || photo != nil)

        return Section {
            LabeledContent("包含计划", value: "\(group.rows.count) 条（不含 test）")
            LabeledContent("分享内容", value: request.useText ? "纯文字" : (request.format == .originalImage ? "原照裁切图" : "重绘表格图"))
            if let content {
                Text(content).font(.footnote.monospaced()).textSelection(.enabled)
            } else if let photo {
                Image(uiImage: photo).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("将交给系统分享的实际图片")
            } else {
                Text(imagesAreCurrent ? "没有可用附件；请核对或切换重绘表格图。" : "正在准备预览图片…")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !distinctMessages.isEmpty {
                ForEach(Array(distinctMessages.enumerated()), id: \.offset) { _, message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(DS.Palette.warning)
                }
                Button("返回修改存疑项") { onlyReview = true; sharePreview = nil }
            }
            Button {
                openSystemShare(name, request: request)
            } label: {
                Label("打开分享面板", systemImage: "square.and.arrow.up")
            }
            .disabled(!enabled || activeSystemShare != nil)

            if let date = store.passPlan.confirmedReceipts[name] {
                Label("已确认收到 · \(date.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DS.Palette.success)
            } else if store.passPlan.delivery.requested.contains(name) {
                Text(store.passPlan.delivery.handedOff.contains(name)
                     ? "已交给系统分享，可点下方标记对方已收到。"
                     : "已打开系统分享。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("标记对方已收到") { pendingReceipt = name }
                    .disabled(!enabled || activeSystemShare != nil)
            }
        } header: {
            Text(name)
        }
    }

    private func openSystemShare(_ name: String, request: PendingPreview) {
        guard !reading, activeSystemShare == nil, request.input == renderInput, request.names.contains(name),
              let group = sendable.first(where: { $0.name == name }) else { return }
        let checks = effectiveAudit(format: request.format)
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
        let payload = SharePayload(item.value, title: "\(name)数传计划", preview: request.useText ? nil : images[name])
        ActivityShare.present([payload], excluding: ActivityShare.chatOnly) { completed in
            guard activeSystemShare == activityID else { return }
            activeSystemShare = nil
            guard request.input == renderInput else { return }
            store.passPlan.delivery.reportHandoff(name, completed: completed)
        }
    }

    private func confirmReceipt(_ name: String, request: PendingPreview) {
        let checks = effectiveAudit(format: request.format)
        guard !reading, activeSystemShare == nil, request.input == renderInput, request.names.contains(name),
              sendable.contains(where: { $0.name == name }),
              !indexedRows(for: name, audit: checks, includeAll: true).contains(where: { checks[$0.offset] != nil }),
              store.passPlan.delivery.confirmReceipt(name, at: Date()) else { return }
        let names = Set(sendable.map(\.name))
        let hasUnassigned = allGroups.contains(where: { $0.name == PassPlan.unassigned })
        guard !hasUnassigned, !names.isEmpty, names.isSubset(of: Set(store.passPlan.confirmedReceipts.keys)) else { return }
        store.settings.passPlanSentDay = .today
        ToastCenter.shared.show("本批各家均已确认收到", style: .success)
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
        ToastCenter.shared.show("仅本批改为「\(chosen.name)」", style: .success)
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

    private func editedTextFields(_ old: PassPlanRow, _ new: PassPlanRow) -> Bool {
        old.orbit != new.orbit || old.satelliteID != new.satelliteID || old.satellite != new.satellite
            || old.start != new.start || old.end != new.end || old.info != new.info || old.cells != new.cells
    }

    private func editedPayload(_ old: PassPlanRow, _ new: PassPlanRow) -> Bool {
        editedTextFields(old, new) || old.station != new.station || old.status != new.status
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
    var caption = ""

    var body: some View {
        let table = PassPlan.table(rows, layout: layout)
        let urgentColumn = table.headers.firstIndex { $0.contains("应急") }
        VStack(alignment: .leading, spacing: 12) {
            Text(PassPlan.title(name: name, rows: rows)).font(.system(size: 20, weight: .bold))
            Grid(alignment: .center, horizontalSpacing: 18, verticalSpacing: 0) {
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

/// 改一条（认错的字、站名、时间、圈号、漏的一条都可以轻松手动修正）
struct PassPlanRowEditor: View {
    @State private var row: PassPlanRow
    @State private var emergencyConfirmed = false
    private let layout: PassPlan.Layout?
    private let rules: [PassPlan.OperatorRule]
    private let sourceImage: UIImage?
    private let sourceHeader: UIImage?
    private let sourcePage: UIImage?
    private let sendsOriginal: Bool
    private let originalRow: PassPlanRow
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
        self.originalRow = r
        self.originalStatus = row.status
        self.originalTestStatusDetected = row.testStatusDetected
        self.isNew = isNew
        self.onDone = onDone
    }

    private var otherColumns: [Int] {
        guard let layout else { return [] }
        return layout.slots.indices.filter { layout.slots[$0].column == nil && $0 != layout.emergencyIndex }
    }

    private var statusBinding: Binding<String> {
        Binding(get: { row.status }, set: { value in
            row.status = value
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

    private var editedTextManually: Bool {
        row.orbit != originalRow.orbit || row.satelliteID != originalRow.satelliteID || row.satellite != originalRow.satellite
            || row.start != originalRow.start || row.end != originalRow.end || row.info != originalRow.info
            || row.station != originalRow.station || row.cells != originalRow.cells
    }

    private var deliveryFormat: PassPlan.DeliveryFormat {
        (sendsOriginal && !editedTextManually) ? .originalImage : .recognizedContent
    }

    private func labeledField(_ title: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: DS.Space.s) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .multilineTextAlignment(.leading)
        }
    }

    private func applyStationPrefix(for rule: PassPlan.OperatorRule) {
        let prefix = rule.prefixes.first ?? rule.name
        guard !prefix.isEmpty else { return }
        if let dash = row.station.firstIndex(of: "-") {
            let suffix = row.station[dash...]
            row.station = prefix + suffix
        } else if row.station.isEmpty {
            row.station = "\(prefix)-"
        } else {
            row.station = "\(prefix)-\(row.station)"
        }
    }

    private var sendingRulesSection: some View {
        Section {
            Picker("计划类型", selection: emergencySelection) {
                if emergencyNeedsChoice { Text("待核对").tag(-1) }
                Text("普通计划").tag(0)
                Text("应急计划").tag(1)
            }
            .pickerStyle(.segmented)

            if emergencyNeedsChoice {
                Text("请对照原图选择「普通计划」或「应急计划」。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.warning)
            }
            if PassPlan.isExcludedFromSending(row) {
                Label("当前状态为 test：自动排除，不发送给任何一家", systemImage: "nosign")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if row.testStatusDetected == true, row.status.filter({ !$0.isWhitespace }).lowercased() != "test" {
                    Button("已核对原图，状态不是 test") { row.testStatusDetected = nil }
                }
            }
        } header: {
            Text("计划类型与发送规则")
        }
    }

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
                    .frame(height: min(260, max(70, headerHeight + rowHeight + 4)))
                    .accessibilityLabel("这一条计划的原照片，左右滑动查看各列")
                } header: {
                    Text("对照原图切片（左右拖动放大查看）")
                }
            }
            if sourceImage == nil, let sourcePage {
                Section("对照整页输入图（拖动查看）") {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: sourcePage).resizable().scaledToFit()
                            .frame(width: max(1000, sourcePage.size.width))
                    }
                    .frame(height: 240)
                }
            }

            let issues = PassPlan.deliveryProblems(row, format: deliveryFormat, rules: rules, layout: layout)
            if !issues.isEmpty {
                Section("识别存疑提醒") {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.warning)
                    }
                    Text("直接修改下方对应字段，点右上角「保存修改」即可确认清除标黄。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("卫星与地面站") {
                labeledField("卫星名称", placeholder: "例如：试验一号", text: $row.satellite)
                labeledField("卫星 ID", placeholder: "例如：SAT-A1", text: $row.satelliteID)
                labeledField("圈号", placeholder: "例如：1201", text: $row.orbit, keyboard: .asciiCapable)
                labeledField("地面站", placeholder: "运营商-站名", text: $row.station)

                if !rules.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Text("快捷改站前缀:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ForEach(rules, id: \.name) { rule in
                                Button(rule.name) { applyStationPrefix(for: rule) }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(DS.Palette.accentSoft, in: Capsule())
                                    .foregroundStyle(DS.Palette.accent)
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                labeledField("开始时间", placeholder: "2026-10-27 22:57:51", text: $row.start)
                labeledField("结束时间", placeholder: "2026-10-27 23:05:12", text: $row.end)
                labeledField("数传信息", placeholder: "通道1：900M", text: $row.info)
                labeledField("状态", placeholder: "等待数传", text: statusBinding)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(["等待数传", "待执行", "已完成", "test"], id: \.self) { preset in
                            Button(preset) { statusBinding.wrappedValue = preset }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(row.status == preset ? DS.Palette.accentSoft : DS.Palette.surfaceSunken, in: Capsule())
                                .foregroundStyle(row.status == preset ? DS.Palette.accent : .primary)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("时间、通道与状态")
            } footer: {
                Text("时间格式支持 2026-10-27 22:57:51，保存时自动规范格式。")
            }

            sendingRulesSection

            if let layout, !otherColumns.isEmpty {
                Section("原表其他列") {
                    ForEach(otherColumns, id: \.self) { i in
                        labeledField(layout.slots[i].label, placeholder: "填写内容", text: $row.cells[i])
                    }
                }
            }

            if !isNew {
                Section {
                    Button(role: .destructive) {
                        onDone(nil)
                        dismiss()
                    } label: {
                        Label("删除这一条计划", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .navigationTitle(isNew ? "手动补一条" : "手动修改计划")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存修改") {
                    row.start = PassPlan.normalizedTime(row.start)
                    row.end = PassPlan.normalizedTime(row.end)
                    row = PassPlan.confirmedDeliveryReview(row, format: deliveryFormat)
                    onDone(row)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(row.station.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || (row.satellite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && row.satelliteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                          || emergencyNeedsChoice)
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
