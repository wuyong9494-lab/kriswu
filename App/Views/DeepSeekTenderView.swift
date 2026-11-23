import SwiftUI
import UniformTypeIdentifiers

/// Standalone, opt-in draft generation from one tender document. Nothing is
/// submitted, sent to a buyer, or imported into another app automatically.
struct DeepSeekTenderView: View {
    private typealias Client = DeepSeekTenderClient
    @State private var selecting = false
    @State private var showingKey = false
    @State private var confirming = false
    @State private var selectedFile: URL?
    @State private var facts = ""
    @State private var task: Task<Void, Never>?
    @State private var operation: UUID?
    @State private var result: Client.Result?
    @State private var generatedFacts: String?
    @State private var stage = ""
    @State private var problem: String?
    @State private var export: URL?
    @State private var exportProblem: String?

    private var busy: Bool { operation != nil }
    private var cleanFacts: String { facts.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var allowedTypes: [UTType] {
        [.pdf, UTType(filenameExtension: "docx")
            ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document", conformingTo: .data)]
    }

    var body: some View {
        List {
            materialSection
            factsSection
            generateSection
            if let result {
                draftHeading(result)
                requirements(result.draft.requirements)
                chapters(result.draft.sections)
                exportSection
            }
        }
        .appList()
        .navigationTitle("投标书草稿")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $selecting, allowedContentTypes: allowedTypes, onCompletion: pick)
        .sheet(isPresented: $showingKey) { DeepSeekPlanKeyView() }
        .alert("将招标文件和填写资料发送给 DeepSeek？", isPresented: $confirming) {
            Button("确认上传并生成") { generate() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这次会上传「\(selectedFile?.lastPathComponent ?? "选中的文件")」及上面填写的资料，使用你的 API 额度。仅选公开、测试或已获准外发的文件和内容。不会上传值班数据，也不会向招标方提交。")
        }
        .onDisappear { cancel() }
        .accessibilityIdentifier("deepSeek.tender")
    }

    private var materialSection: some View {
        Section {
            Button { selecting = true } label: {
                Label(selectedFile == nil ? "从文件选 PDF / Word" : "更换招标文件", systemImage: "folder")
            }
            .disabled(busy)
            .accessibilityIdentifier("deepSeek.tender.import")
            if let selectedFile {
                Label(selectedFile.lastPathComponent, systemImage: "doc.text")
                    .font(.subheadline)
                    .textSelection(.enabled)
                Button("取消选择", role: .destructive) {
                    self.selectedFile = nil
                    discardDraft()
                    problem = nil
                }
                .disabled(busy)
            }
        } header: {
            Text("1. 招标文件")
        } footer: {
            Text("一次选一份 PDF 或 DOCX。微信里的文件先「存储到文件」，再从这里选。仅选择文件不会上传。")
        }
    }

    private var factsSection: some View {
        Section {
            TextField("例如：已确认的产品型号、交付周期、保修承诺和可证明的业绩", text: $facts, axis: .vertical)
                .lineLimit(3...8)
                .disabled(busy)
                .accessibilityIdentifier("deepSeek.tender.facts")
            if facts.utf8.count > Client.maxFactsBytes {
                Text("资料过长，请缩短再生成。").font(.footnote).foregroundStyle(DS.Palette.danger)
            }
        } header: {
            Text("2. 补充真实投标资料（可选）")
        } footer: {
            Text("只写已经核实、允许外发的事实。缺少的报价、证书、人员、签章、承诺会作为待补项，不要让 AI 编造。")
        }
    }

    private var generateSection: some View {
        Section {
            if busy {
                HStack {
                    ProgressView()
                    Text(stage).font(.footnote)
                    Spacer()
                    Button("停止", role: .cancel) { cancel(report: true) }
                        .buttonStyle(.borderless)
                }
            } else {
                Button {
                    if Keychain.get(.deepSeekPlanAPIKey)?.isEmpty != false {
                        showingKey = true
                    } else {
                        confirming = true
                    }
                } label: {
                    Label("按招标要求起草投标书", systemImage: "sparkles")
                }
                .disabled(selectedFile == nil || cleanFacts.utf8.count > Client.maxFactsBytes)
                .accessibilityIdentifier("deepSeek.tender.generate")
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(DS.Palette.danger)
            }
        } footer: {
            Text("输出是新写的投标草稿，不是招标文件摘要。草稿、引用、参数和报价都需要人工检查。停止不能撤回已上传的文件；已上传文件会尝试删除，并设置短期过期。")
        }
    }

    private func draftHeading(_ result: Client.Result) -> some View {
        Section {
            Text(result.draft.title).font(.headline).textSelection(.enabled)
            Label("AI 草稿 · 未审核，不可直接提交", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            if generatedFacts != cleanFacts {
                Text("补充资料已变更，下方仍是上一次的草稿。请重新生成后再导出。")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if let notice = result.cleanup.notice {
                Text(notice).font(.footnote).foregroundStyle(.orange)
            }
            if !result.draft.missingFacts.isEmpty {
                DisclosureGroup("待补资料（\(result.draft.missingFacts.count)）") {
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
        Section("招标条款与响应") {
            ForEach(requirements.indices, id: \.self) { i in
                let requirement = requirements[i]
                DisclosureGroup {
                    Text(requirement.response).textSelection(.enabled)
                    sourceLine(requirement.source)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(requirement.requirement).font(.subheadline.weight(.semibold))
                        Text(requirement.status.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
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
            Text("\(source.verified ? "摘录经文本核对，位置仍请核实" : "出处待核验") · \(source.location)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(source.verified ? Color.secondary : Color.orange)
            Text(source.quote).font(.caption).textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var exportSection: some View {
        Section {
            if let export {
                ShareLink(item: export) { Label("分享或存储 Word 草稿", systemImage: "square.and.arrow.up") }
                    .disabled(busy || generatedFacts != cleanFacts)
            } else {
                Button(action: makeExport) { Label("准备 Word 草稿（.docx）", systemImage: "doc.badge.plus") }
                    .disabled(busy || generatedFacts != cleanFacts)
            }
            if let exportProblem {
                Text(exportProblem).font(.footnote).foregroundStyle(DS.Palette.danger)
            }
        } footer: {
            Text("Word 文件在本机生成。使用系统分享面板前，请核对分享对象与文件内容。")
        }
    }

    private func pick(_ outcome: Swift.Result<URL, Error>) {
        guard !busy else { return }
        switch outcome {
        case .success(let url):
            guard ["pdf", "docx"].contains(url.pathExtension.lowercased()) else {
                problem = "请选择 PDF 或 DOCX 文件。"
                return
            }
            selectedFile = url
            discardDraft()
            problem = nil
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            problem = "未能选择文件，请重新打开「文件」选择。"
        }
    }

    private func generate() {
        guard !busy, let file = selectedFile else { return }
        guard let key = Keychain.get(.deepSeekPlanAPIKey), !key.isEmpty else { showingKey = true; return }
        let supplemental = cleanFacts
        guard supplemental.utf8.count <= Client.maxFactsBytes else { problem = "资料过长，请缩短再生成。"; return }
        let id = UUID()
        operation = id
        stage = "正在读取选中的文件…"
        problem = nil
        task = Task { @MainActor in
            defer {
                if operation == id { operation = nil; task = nil; stage = "" }
            }
            do {
                let data = try await Self.readLocalDocument(file)
                try Task.checkCancellation()
                guard operation == id else { return }
                stage = "正在解析文件并起草，可能需要一些时间…"
                let generated = try await Client.generate(data: data, filename: file.lastPathComponent,
                                                          facts: supplemental, apiKey: key)
                try Task.checkCancellation()
                guard operation == id else { return }
                discardDraft()
                result = generated
                generatedFacts = supplemental
            } catch is CancellationError {
                // Any provider-side cleanup is owned by the client.
            } catch {
                guard operation == id else { return }
                problem = (error as? Client.Failure)?.errorDescription
                    ?? (error as? LocalFailure)?.errorDescription
                    ?? "未能生成草稿，请稍后重试。"
            }
        }
    }

    private func cancel(report: Bool = false) {
        guard busy else { return }
        task?.cancel()
        task = nil
        operation = nil
        stage = ""
        if report { problem = "已停止等待。本次如果已开始上传，停止不等于撤回发出的文件。" }
    }

    private func discardDraft() {
        result = nil
        generatedFacts = nil
        if let export { try? FileManager.default.removeItem(at: export.deletingLastPathComponent()) }
        export = nil
        exportProblem = nil
    }

    private func makeExport() {
        guard let result, !busy, generatedFacts == cleanFacts else { return }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("deepseek-tender-\(UUID().uuidString)", isDirectory: true)
        do {
            let data = try TenderDOCXExporter.make(draft: result.draft)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("投标书草稿-待审核.docx")
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            export = file
            exportProblem = nil
        } catch {
            try? FileManager.default.removeItem(at: folder)
            exportProblem = "未能生成 Word 文件，草稿仍可在本页查看。"
        }
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

    private nonisolated static func readLocalDocument(_ url: URL) async throws -> Data {
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
