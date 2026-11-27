import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import QuickLook

import UIKit

/// Persistent, background-resilient workflow store for the Tender golden chain:
/// Tender PDF/DOCX -> Clause Check + Missing Items + Verified Sources -> Editable Word (.docx) -> WeChat Share.
/// Survives tab switches, sheet dismissal, backgrounding, and app relaunches without losing work.
@MainActor
final class TenderWorkflowStore: ObservableObject {
    static let shared = TenderWorkflowStore()

    typealias Client = DeepSeekTenderClient

    enum Document: Sendable {
        case file(URL)
        case inbox(TenderShareInbox.Item)

        var filename: String {
            switch self {
            case .file(let url): return url.lastPathComponent
            case .inbox(let item): return item.filename
            }
        }
    }

    struct LocalOriginal {
        let data: Data
        let filename: String
    }

    private struct PersistedDraftSnapshot: Codable {
        let filename: String
        let facts: String
        let draft: Client.Draft
        let savedAt: Date
    }

    private enum LocalFailure: LocalizedError {
        case inaccessible, oversized
        var errorDescription: String? {
            switch self {
            case .inaccessible: return "文件未能读取。请确认文件已下载到本机，再重新选择。"
            case .oversized: return "该文件超出当前版本可处理的大小，未上传。请选更小的文件。"
            }
        }
    }

    @Published var selectedDocument: Document?
    @Published var facts: String = ""
    @Published private(set) var operation: UUID?
    @Published private(set) var stage: String = ""
    @Published private(set) var problem: String?
    @Published private(set) var result: Client.Result?
    @Published private(set) var generatedFacts: String?
    @Published private(set) var generatedFilename: String?
    @Published private(set) var savedAt: Date?
    @Published private(set) var restoredFromDisk: Bool = false
    @Published private(set) var original: LocalOriginal?
    @Published private(set) var export: URL?
    @Published private(set) var exportProblem: String?

    private var task: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    var busy: Bool { operation != nil }
    var cleanFacts: String { facts.trimmingCharacters(in: .whitespacesAndNewlines) }

    private init() {
        restoreLastDraftIfAvailable()
    }

    func selectDocument(_ document: Document?) {
        guard !busy else { return }
        selectedDocument = document
        discardDraft()
        problem = nil
    }

    func generate() {
        guard !busy, let document = selectedDocument else { return }
        guard let key = Keychain.get(.deepSeekPlanAPIKey), !key.isEmpty else { return }
        let supplemental = cleanFacts
        guard supplemental.utf8.count <= Client.maxFactsBytes else {
            problem = "资料过长，请缩短再生成。"
            return
        }
        let id = UUID()
        operation = id
        stage = "1/3 正在读取本机招标文件…"
        problem = nil
        beginBackgroundProtection()

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.operation == id {
                    self.operation = nil
                    self.task = nil
                    self.stage = ""
                    self.endBackgroundProtection()
                }
            }
            do {
                let data = try await Self.readLocalDocument(document)
                try Task.checkCancellation()
                guard self.operation == id else { return }
                self.stage = "2/3 正在读招标正文与表格条款并深度起草（切后台或离开本页不会中断）…"
                let generated = try await Client.generate(
                    data: data,
                    filename: document.filename,
                    facts: supplemental,
                    apiKey: key
                )
                try Task.checkCancellation()
                guard self.operation == id else { return }
                self.stage = "3/3 正在生成可编辑 Word (.docx) 草稿…"
                self.discardDraft(clearDisk: false)
                self.original = LocalOriginal(data: data, filename: document.filename)
                self.result = generated
                self.generatedFacts = supplemental
                self.generatedFilename = document.filename
                let now = Date()
                self.savedAt = now
                self.restoredFromDisk = false
                self.persistDraft(
                    PersistedDraftSnapshot(
                        filename: document.filename,
                        facts: supplemental,
                        draft: generated.draft,
                        savedAt: now
                    )
                )
                // Build editable Word (.docx) automatically so 1-tap Share to WeChat is immediately ready!
                self.writeCurrentDraftExport()
            } catch is CancellationError {
                // Provider-side cleanup is handled by DeepSeekTenderClient.
            } catch {
                guard self.operation == id else { return }
                self.problem = (error as? Client.Failure)?.errorDescription
                    ?? (error as? TenderShareInbox.Failure)?.errorDescription
                    ?? (error as? LocalFailure)?.errorDescription
                    ?? "未能生成草稿，请稍后重试。"
            }
        }
    }

    func cancel(report: Bool = false) {
        guard busy else { return }
        task?.cancel()
        task = nil
        operation = nil
        stage = ""
        endBackgroundProtection()
        if report {
            problem = "已停止等待。本次如果已开始上传，停止不等于撤回发出的文件。"
        }
    }

    func discardDraft(clearDisk: Bool = true) {
        original = nil
        result = nil
        generatedFacts = nil
        generatedFilename = nil
        savedAt = nil
        restoredFromDisk = false
        if let export {
            try? FileManager.default.removeItem(at: export.deletingLastPathComponent())
        }
        export = nil
        exportProblem = nil
        if clearDisk {
            if let url = Self.draftSnapshotURL(create: false) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func makeExport() {
        guard !busy else { return }
        writeCurrentDraftExport()
    }

    private func writeCurrentDraftExport() {
        guard let result, generatedFacts == cleanFacts else { return }
        if let existing = export, FileManager.default.fileExists(atPath: existing.path) {
            return
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("deepseek-tender-\(UUID().uuidString)", isDirectory: true)
        do {
            let data = try TenderDOCXExporter.make(draft: result.draft)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safeTitle = Self.sanitizedExportBasename(result.draft.title)
            let file = folder.appendingPathComponent("\(safeTitle)-投标书草稿.docx")
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            export = file
            exportProblem = nil
        } catch {
            try? FileManager.default.removeItem(at: folder)
            exportProblem = "未能生成 Word 文件，草稿仍可在本页查看。"
        }
    }

    func setProblem(_ text: String?) {
        problem = text
    }

    private func beginBackgroundProtection() {
        endBackgroundProtection()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "WuMindTenderGeneration") { [weak self] in
            Task { @MainActor [weak self] in
                self?.endBackgroundProtection()
            }
        }
    }

    private func endBackgroundProtection() {
        if backgroundTaskID != .invalid {
            let id = backgroundTaskID
            backgroundTaskID = .invalid
            UIApplication.shared.endBackgroundTask(id)
        }
    }

    private func persistDraft(_ snapshot: PersistedDraftSnapshot) {
        guard let url = Self.draftSnapshotURL(create: true),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func restoreLastDraftIfAvailable() {
        guard let url = Self.draftSnapshotURL(create: false),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(PersistedDraftSnapshot.self, from: data) else { return }
        facts = snapshot.facts
        generatedFacts = snapshot.facts
        generatedFilename = snapshot.filename
        savedAt = snapshot.savedAt
        restoredFromDisk = true
        result = Client.Result(draft: snapshot.draft, cleanup: .deleted)
        makeExport()
    }

    private static func draftSnapshotURL(create: Bool) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = dir.appendingPathComponent("WuMindTender", isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent("last_draft.json")
    }

    private static func sanitizedExportBasename(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = raw.components(separatedBy: illegal).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "投标文件" }
        return String(cleaned.prefix(36))
    }

    private nonisolated static func readLocalDocument(_ document: Document) async throws -> Data {
        switch document {
        case .file(let url): return try await readFile(url)
        case .inbox(let item):
            try Task.checkCancellation()
            return try TenderShareInbox.appGroup().read(item)
        }
    }

    private nonisolated static func readFile(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let stream = try? FileHandle(forReadingFrom: url) else { throw LocalFailure.inaccessible }
        defer { try? stream.close() }
        guard let bytes = try? stream.read(upToCount: Client.maxFileBytes + 1),
              !bytes.isEmpty else { throw LocalFailure.inaccessible }
        guard bytes.count <= Client.maxFileBytes else { throw LocalFailure.oversized }
        try Task.checkCancellation()
        return bytes
    }
}

/// Standalone, opt-in draft generation from one tender document. Nothing is
/// submitted, sent to a buyer, or imported into another app automatically.
struct DeepSeekTenderView: View {
    private typealias Client = DeepSeekTenderClient
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var workflow = TenderWorkflowStore.shared
    @State private var selecting = false
    @State private var showingKey = false
    @State private var confirming = false
    @State private var inboxItems: [TenderShareInbox.Item] = []
    @State private var inboxProblem: String?
    @State private var pendingDeletion: TenderShareInbox.Item?
    @State private var sourcePreview: SourcePreview?
    @State private var wordPreviewFolder: URL?
    @State private var sourcePreviewProblem: String?

    private struct SourcePreview: Identifiable {
        enum Document {
            case pdf(Data, pageIndex: Int)
            case word(URL)
        }

        let id = UUID()
        let document: Document
    }

    private var busy: Bool { workflow.busy }
    private var cleanFacts: String { workflow.cleanFacts }
    private var allowedTypes: [UTType] {
        [.pdf, UTType(filenameExtension: "docx")
            ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document", conformingTo: .data)]
    }

    var body: some View {
        List {
            if busy {
                Section {
                    ProgressView(workflow.stage)
                        .font(DS.Font.body)
                        .accessibilityIdentifier("deepSeek.tender.progress")
                    Button("停止生成", role: .cancel) { workflow.cancel(report: true) }
                }
            }
            if let problem = workflow.problem {
                Section {
                    Text(problem)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Palette.danger)
                        .accessibilityIdentifier("deepSeek.tender.problem")
                }
            }
            if let result = workflow.result {
                draftHeading(result)
                if workflow.generatedFacts == cleanFacts {
                    exportSection
                }
                requirements(result.draft.requirements)
                chapters(result.draft.sections)
                Section {
                    Button("清除本机缓存草稿", role: .destructive) {
                        sourcePreview = nil
                        removeWordPreview()
                        workflow.discardDraft(clearDisk: true)
                    }
                    .disabled(busy)
                }
            }
            materialSection
            if workflow.selectedDocument == nil && workflow.result == nil {
                inboxSection
            }
            factsSection
            if workflow.selectedDocument != nil && !busy {
                generateSection
            }
            if workflow.selectedDocument != nil || workflow.result != nil {
                inboxSection
            }
        }
        .appList()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("投标草稿")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $selecting, allowedContentTypes: allowedTypes, onCompletion: pick)
        .sheet(isPresented: $showingKey) { DeepSeekPlanKeyView() }
        .sheet(item: $sourcePreview, onDismiss: removeWordPreview) { preview in
            NavigationStack {
                sourcePreviewContent(preview)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { sourcePreview = nil }
                        }
                    }
            }
        }
        .alert("无法查看原招标文件", isPresented: Binding(
            get: { sourcePreviewProblem != nil },
            set: { if !$0 { sourcePreviewProblem = nil } }
        )) {
            Button("好", role: .cancel) { sourcePreviewProblem = nil }
        } message: {
            Text(sourcePreviewProblem ?? "")
        }
        .alert("将招标文件和填写资料发送给 DeepSeek？", isPresented: $confirming) {
            Button("确认上传并生成") { workflow.generate() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本次将发送「\(workflow.selectedDocument?.filename ?? "选中的文件")」及补充资料至 DeepSeek 官方接口 (api.deepseek.com)，读取正文/表格条款并按条款起草可编辑 Word 草稿、标出缺项与原文出处。生成过程中切后台不会中断，也不会向招标方自动提交。")
        }
        .confirmationDialog("从招标收件箱删除？", isPresented: deletingInboxItem,
                            titleVisibility: .visible, presenting: pendingDeletion) { item in
            Button("删除本机副本", role: .destructive) { removeInboxItem(item) }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: { item in
            Text("将删除「\(item.filename)」在值班提醒里的副本，不影响微信或其他应用里的原文件。")
        }
        .onAppear(perform: refreshInbox)
        .onChange(of: scenePhase) { phase in
            if phase == .active { refreshInbox() }
        }
        // Keep in-flight tender generation alive when switching tabs or backgrounding!
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deepSeek.tender")
    }

    private var materialSection: some View {
        Section {
            if let selectedDocument = workflow.selectedDocument {
                Label(selectedDocument.filename, systemImage: "doc.text")
                    .font(DS.Font.headline)
                    .textSelection(.enabled)
                Button("更换招标文件") { selecting = true }
                    .disabled(busy)
                    .accessibilityIdentifier("deepSeek.tender.import")
                Button("取消选择", role: .destructive) { workflow.selectDocument(nil) }
                    .disabled(busy)
            } else if workflow.result == nil {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("导入招标文件")
                        .font(DS.Font.title)
                        .accessibilityAddTraits(.isHeader)
                    Text("选择一份 PDF 或 Word（DOCX）。确认生成时才会上传。")
                        .font(DS.Font.body)
                        .foregroundStyle(.secondary)
                    AppPrimaryCTA(title: "选择招标文件", icon: "folder", action: { selecting = true })
                        .accessibilityIdentifier("deepSeek.tender.import")
                }
                .padding(.vertical, DS.Space.xs)
            } else {
                Button { selecting = true } label: { Label("选择招标文件", systemImage: "folder") }
                    .accessibilityIdentifier("deepSeek.tender.import")
            }
        } header: {
            if workflow.selectedDocument != nil || workflow.result != nil { Text("招标文件") }
        }
    }

    private var inboxSection: some View {
        Section {
            if inboxItems.isEmpty && inboxProblem == nil {
                Text("尚未收到文件")
                    .font(DS.Font.body)
                    .foregroundStyle(.secondary)
            }
            ForEach(inboxItems, id: \.id) { item in
                Button {
                    guard !busy else { return }
                    workflow.selectDocument(.inbox(item))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.filename).foregroundStyle(.primary)
                            Text(item.createdAt.formatted(date: .numeric, time: .shortened)
                                 + " · " + ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if case .inbox(let selected)? = workflow.selectedDocument, selected.id == item.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                .accessibilityLabel("已选中")
                        }
                    }
                }
                .disabled(busy)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("删除", role: .destructive) { pendingDeletion = item }
                        .disabled(busy)
                }
            }
            if let inboxProblem {
                Text(inboxProblem).font(DS.Font.caption).foregroundStyle(.secondary)
            }
            Button(action: refreshInbox) { Label("刷新收件箱", systemImage: "arrow.clockwise") }
        } header: {
            Text("招标收件箱")
        } footer: {
            Text("在微信将文件分享到「值班提醒」即可在这里选择。本机收件箱保留 24 小时。")
        }
    }

    private var deletingInboxItem: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private func refreshInbox() {
        do {
            inboxItems = try TenderShareInbox.appGroup().items()
            inboxProblem = nil
            if !busy, case .inbox(let selected)? = workflow.selectedDocument,
               !inboxItems.contains(where: { $0.id == selected.id }) {
                workflow.selectDocument(nil)
                workflow.setProblem("所选收件箱文件已删除或过期，请重新分享。")
            }
        } catch {
            inboxProblem = "收件箱暂时无法读取，可刷新或从「文件」导入。"
        }
    }

    private func removeInboxItem(_ item: TenderShareInbox.Item) {
        pendingDeletion = nil
        guard !busy else { return }
        do {
            try TenderShareInbox.appGroup().delete(item)
            if case .inbox(let selected)? = workflow.selectedDocument, selected.id == item.id {
                workflow.selectDocument(nil)
            }
            refreshInbox()
        } catch {
            inboxProblem = "未能删除本机副本，请刷新后重试。"
        }
    }

    private var factsSection: some View {
        Section {
            TextField("产品型号、交付周期、保修承诺等", text: $workflow.facts, axis: .vertical)
                .lineLimit(3...8)
                .disabled(busy)
                .accessibilityIdentifier("deepSeek.tender.facts")
            if workflow.facts.utf8.count > Client.maxFactsBytes {
                Text("资料过长，请缩短再生成。").font(.footnote).foregroundStyle(DS.Palette.danger)
            }
        } header: {
            Text("投标方资料（可选）")
        } footer: {
            Text("仅填写已核实且允许外发的事实。缺少的材料会列入待补清单。")
        }
    }

    private var generateSection: some View {
        Section {
            if workflow.result != nil && workflow.generatedFacts == cleanFacts {
                Button("重新生成草稿", action: requestGeneration)
                    .accessibilityIdentifier("deepSeek.tender.generate")
            } else {
                AppPrimaryCTA(title: workflow.result == nil ? "生成投标草稿" : "重新生成草稿",
                              icon: "doc.text", isDisabled: cleanFacts.utf8.count > Client.maxFactsBytes,
                              action: requestGeneration)
                    .accessibilityIdentifier("deepSeek.tender.generate")
            }
        }
    }

    private func requestGeneration() {
        if Keychain.get(.deepSeekPlanAPIKey)?.isEmpty != false {
            showingKey = true
        } else {
            confirming = true
        }
    }

    private func draftHeading(_ result: Client.Result) -> some View {
        Section {
            Text(result.draft.title).font(DS.Font.title).accessibilityAddTraits(.isHeader).textSelection(.enabled)
            if let savedAt = workflow.savedAt {
                HStack(spacing: 6) {
                    Image(systemName: workflow.restoredFromDisk ? "arrow.counterclockwise.circle.fill" : "checkmark.seal.fill")
                        .foregroundStyle(DS.Palette.success)
                    Text(
                        (workflow.restoredFromDisk ? "已自动恢复上次草稿" : "已保存至本机")
                        + (workflow.generatedFilename.map { " · \($0)" } ?? "")
                        + " · \(savedAt.formatted(date: .omitted, time: .shortened))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Label("待人工审核", systemImage: "doc.text.magnifyingglass")
                .font(DS.Font.callout)
            if workflow.generatedFacts != cleanFacts {
                Text(workflow.selectedDocument == nil ? "补充资料已变更。请重新选择原文件并生成，再导出更新后的草稿。" : "补充资料已变更，请重新生成后再导出。")
                    .font(.footnote).foregroundStyle(DS.Palette.warning)
            }
            if let notice = result.cleanup.notice {
                Text(notice).font(.footnote).foregroundStyle(DS.Palette.warning)
            }
            if !result.draft.missingFacts.isEmpty {
                DisclosureGroup("待补资料 / 缺失清单（\(result.draft.missingFacts.count)）") {
                    ForEach(result.draft.missingFacts.indices, id: \.self) { i in
                        Text(result.draft.missingFacts[i]).font(.footnote).textSelection(.enabled)
                    }
                }
            }
            if !result.draft.warnings.isEmpty {
                DisclosureGroup("人工核验提醒（\(result.draft.warnings.count)）") {
                    ForEach(result.draft.warnings.indices, id: \.self) { i in
                        Text(result.draft.warnings[i]).font(.footnote).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func requirements(_ requirements: [Client.Requirement]) -> some View {
        Section {
            ForEach(requirements.indices, id: \.self) { i in
                let requirement = requirements[i]
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("响应草稿").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(requirement.response).textSelection(.enabled)
                        Divider()
                        sourceLine(requirement.source)
                    }
                    .padding(.vertical, 6)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(requirement.requirement).font(.subheadline.weight(.semibold))
                        switch requirement.status {
                        case .drafted:
                            Label(requirement.status.title, systemImage: "doc.text")
                                .font(.caption).foregroundStyle(.secondary)
                        case .missing:
                            Label(requirement.status.title, systemImage: "doc.badge.plus")
                                .font(.caption).foregroundStyle(DS.Palette.warning)
                        case .verify:
                            Label(requirement.status.title, systemImage: "magnifyingglass")
                                .font(.caption).foregroundStyle(DS.Palette.warning)
                        }
                    }
                }
                .accessibilityIdentifier("deepSeek.tender.requirement.\(i)")
            }
        } header: {
            Text("逐条核查招标响应（\(requirements.count) 项）")
        } footer: {
            Text("展开可核对原文。提交前请人工确认条款覆盖、合规性和待补材料。")
        }
    }

    private func chapters(_ sections: [Client.Section]) -> some View {
        Section("投标书正文草稿") {
            ForEach(sections.indices, id: \.self) { i in
                let section = sections[i]
                DisclosureGroup {
                    Text(section.body).textSelection(.enabled)
                    ForEach(section.sources.indices, id: \.self) { j in
                        sourceLine(section.sources[j])
                    }
                } label: {
                    Text(section.title).font(.headline)
                }
            }
        }
    }

    private func sourceLine(_ source: Client.Source) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let location = source.reviewLocation {
                Text("本机匹配到原文 · \(location)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(source.quote).font(.caption).textSelection(.enabled)
                if let pageIndex = source.reviewPDFPageIndex, workflow.original != nil {
                    Button("打开原 PDF 第 \(pageIndex + 1) 页") { openPDFSource(pageIndex) }
                        .buttonStyle(.borderless)
                } else if let paragraph = source.reviewWordParagraph, workflow.original != nil {
                    Button("预览原 Word 文档") { openWordSource() }
                        .buttonStyle(.borderless)
                    Text("原文摘录位于本机提取顺序第 \(paragraph) 段。Word 预览不自动跳段，可对照上方摘录。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("未核实摘录 · 无可靠定位")
                    .font(.caption.weight(.semibold)).foregroundStyle(DS.Palette.warning)
                Text(source.quote).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("模型提取内容，仅供人工查找，不能当作招标原文。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func openPDFSource(_ page: Int) {
        guard let original = workflow.original,
              (original.filename as NSString).pathExtension.lowercased() == "pdf" else { return }
        sourcePreview = SourcePreview(document: .pdf(original.data, pageIndex: page))
    }

    private func openWordSource() {
        guard let original = workflow.original,
              (original.filename as NSString).pathExtension.lowercased() == "docx" else { return }
        removeWordPreview()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("tender-source-preview-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("原招标文件.docx")
            try original.data.write(to: file, options: [.atomic, .completeFileProtection])
            wordPreviewFolder = folder
            sourcePreview = SourcePreview(document: .word(file))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            sourcePreviewProblem = "未能创建本机 Word 预览，仍可查看核对过的摘录。"
        }
    }

    private func removeWordPreview() {
        if let wordPreviewFolder { try? FileManager.default.removeItem(at: wordPreviewFolder) }
        wordPreviewFolder = nil
    }

    @ViewBuilder
    private func sourcePreviewContent(_ preview: SourcePreview) -> some View {
        switch preview.document {
        case .pdf(let data, let index):
            if let document = PDFDocument(data: data), let page = document.page(at: index) {
                TenderPDFSourceViewer(document: document, page: page)
                    .navigationTitle("原 PDF · 第 \(index + 1) 页")
            } else {
                Text("无法打开这份 PDF 的原页，仍可对照摘录。")
                    .navigationTitle("原 PDF")
            }
        case .word(let url):
            TenderWordSourceViewer(url: url)
                .navigationTitle("原 Word 文档")
        }
    }

    private var exportSection: some View {
        Section {
            if let export = workflow.export {
                ShareLink(item: export) {
                    Label("分享 Word 草稿", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primaryWide)
                .disabled(busy || workflow.generatedFacts != cleanFacts)
                .accessibilityIdentifier("deepSeek.tender.shareDocx")
            } else {
                AppPrimaryCTA(title: "生成 Word 文件", icon: "doc.badge.plus", isDisabled: busy) {
                    workflow.makeExport()
                }
            }
            if let exportProblem = workflow.exportProblem {
                Text(exportProblem).font(.footnote).foregroundStyle(DS.Palette.danger)
            }
        } header: {
            Text("导出与分享")
        } footer: {
            Text("Word 文件包含正文、响应表、原文出处和待补资料清单。")
        }
    }

    private func pick(_ outcome: Swift.Result<URL, Error>) {
        guard !busy else { return }
        switch outcome {
        case .success(let url):
            guard ["pdf", "docx"].contains(url.pathExtension.lowercased()) else {
                workflow.setProblem("请选择 PDF 或 DOCX 文件。")
                return
            }
            workflow.selectDocument(.file(url))
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            workflow.setProblem("未能选择文件，请重新打开「文件」选择。")
        }
    }
}


private struct TenderPDFSourceViewer: UIViewRepresentable {
    let document: PDFDocument
    let page: PDFPage

    func makeUIView(context: Context) -> PDFView {
        let view = PagePositioningView()
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        view.document = document
        view.initialPage = page
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}

    private final class PagePositioningView: PDFView {
        var initialPage: PDFPage?

        override func layoutSubviews() {
            super.layoutSubviews()
            guard window != nil, bounds.width > 0, bounds.height > 0, let page = initialPage else { return }
            initialPage = nil
            go(to: page)
        }
    }
}

private struct TenderWordSourceViewer: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
